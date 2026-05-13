# ============================================================
# Solver 共享工具 — ODE 编译、参数提取等通用函数
# ============================================================

# ============================================================
# 1. ODE 表达式检测与解析
# ============================================================

"""
    _is_explicit_ode(ex) -> Bool

检查表达式是否为显式 ODE 形式 `der(x) == rhs`。
"""
function _is_explicit_ode(ex)
    ex isa Expr || return false
    if ex.head == :call && length(ex.args) >= 3 && ex.args[1] == :(==)
        lhs = ex.args[2]
        return lhs isa Expr && lhs.head == :call &&
               length(lhs.args) >= 2 && lhs.args[1] == :der
    end
    return false
end

"""
    _split_ode(ex) -> (state::Symbol, rhs)

从 `der(x) == rhs` 中提取状态变量 x 和右端表达式 rhs。
"""
function _split_ode(ex)
    lhs = ex.args[2]  # der(x)
    rhs = ex.args[3]  # rhs expression
    state = lhs.args[2]
    return state, rhs
end

# ============================================================
# 2. 表达式符号收集
# ============================================================

"""
    _collect_symbols(ex) -> Set{Symbol}
    _collect_symbols(exs::Vector) -> Set{Symbol}

递归收集表达式树中所有 Symbol。
接受单个 Expr 或 Expr 数组。
"""
_collect_symbols(exs::Vector) = union!(_collect_symbols.(exs)...)

function _collect_symbols(ex)
    syms = Set{Symbol}()
    _collect_syms!(syms, ex)
    return syms
end

function _collect_syms!(syms, ex)
    if ex isa Symbol
        push!(syms, ex)
    elseif ex isa Expr
        for arg in ex.args
            _collect_syms!(syms, arg)
        end
    end
end

# Julia 内建函数集合（不被视为参数）
const _BUILTIN_FUNS = Set{Symbol}([
    :+, :-, :*, :/, :^, :div, :mod, :rem,
    :sin, :cos, :tan, :asin, :acos, :atan,
    :sinh, :cosh, :tanh, :exp, :log, :log10, :sqrt,
    :abs, :sign, :floor, :ceil, :round,
    Symbol("=="), Symbol("!="), Symbol("<"), Symbol(">"),
    Symbol("<="), Symbol(">="),
    :if, :else, Symbol(":"), :&&, :||, :!,
    Symbol("true"), Symbol("false"), :pi, :π, :ℯ, :Inf, :NaN, :t,
    :der, :integral, :when,
    :Tuple, :Vector, :Dict, :Symbol, :Float64, :Int, :String,
    :rand, :randn, :println, :print, :sleep,
    :length, :size, :push!, :pop!, :haskey, :get, :get!,
    :keys, :values, :empty!, :append!,
    :setindex!, :getindex, :nothing, :missing, :undef,
])

function _is_builtin(s::Symbol)
    s in _BUILTIN_FUNS || startswith(string(s), "__")
end

"""
    _replace_refs(expr, state_idx, param_set)

在表达式树中用 `u[idx]` 替换状态变量、
用 `p[:sym]` 替换参数。
"""
function _replace_refs(ex, state_idx::Dict{Symbol,Int}, param_set::Set{Symbol})
    if ex isa Symbol
        if haskey(state_idx, ex)
            return :(u[$(state_idx[ex])])
        elseif ex in param_set
            return :(p[$(QuoteNode(ex))])
        else
            return ex  # 内建函数、常量
        end
    elseif ex isa Expr
        return Expr(ex.head, [_replace_refs(a, state_idx, param_set) for a in ex.args]...)
    else
        return ex  # 字面量
    end
end

# ============================================================
# 3. ODE 编译器
# ============================================================

"""
    compile_ode(model::EntityDef) -> (f!, states, params)

从 EntityDef 提取显式 ODE 方程，编译为可调用的 ODE 函数。
兼容层：新的主入口是 `compile_ode_ir(model)`。

返回：
- `f!(du, u, p, t)` — ODE 右端函数
- `states` — 状态变量名列表
- `params` — 参数名列表
"""
function compile_ode(model::EntityDef)
    compiled = compile_ode_ir(model)
    compiled === nothing && return nothing
    return (compiled.f!, compiled.state_names, compiled.param_names)
end

"""
    compile_ode(model::ComposeDef) -> (f!, states, params)

ComposeDef 版本的 compile_ode。兼容层，主入口见 `compile_ode_ir(model)`。
"""
function compile_ode(model::ComposeDef)
    compiled = compile_ode_ir(model)
    compiled === nothing && return nothing
    return (compiled.f!, compiled.state_names, compiled.param_names)
end

# ============================================================
# 4. 参数提取
# ============================================================

"""
    _extract_params(model, param_syms, overrides) -> Dict{Symbol, Float64}

从模型和覆盖参数中提取数值参数。
"""
function _extract_params(model, param_syms, overrides)
    p = Dict{Symbol, Float64}()
    for s in param_syms
        if haskey(overrides, s)
            p[s] = Float64(overrides[s])
        else
            val = _find_param_default(model, s)
            val !== nothing ? (p[s] = Float64(val)) :
                throw_diagnostic(
                    E_PARAM_MISSING_DEFAULT;
                    phase=PHASE_RESOLVE,
                    human_message="参数缺少默认值",
                    human_summary="参数 :$s 没有默认值，请通过 params 提供",
                    entity=Dict("kind" => "parameter", "name" => string(s)),
                    constraint="model_parameter_must_have_value",
                    expected="parameter_value",
                    actual="missing",
                    context=Dict{String, Any}("parameter" => string(s)),
                    repair_hints=[
                        "Provide the missing parameter value through params.",
                        "Or define a default value for the parameter in the model.",
                    ],
                    ai_hint=_default_ai_hint(
                        "Provide a value for the missing parameter without changing unrelated model behavior.",
                        string("The parameter ", s, " has no runtime override and no default value."),
                        [
                            "First check whether the parameter should receive a runtime override.",
                            "If not, add a stable default value in the model definition.",
                        ];
                        constraints=[
                            "Do not change unrelated parameters.",
                            "Keep the patch minimal.",
                        ],
                        recheck=["resolve", "semantic_validation"],
                    ),
                    docs_ref="rules/parameters/parameter-must-have-value",
                )
        end
    end
    return p
end

"""
    _find_param_default(model, name::Symbol) -> Union{Any, Nothing}

递归搜索 EntityDef 和 ComposeDef 中指定名称的参数默认值。
"""
function _find_param_default(model::EntityDef, name::Symbol)
    for p in model.parameters
        p.name == name && p.default !== nothing && return p.default
    end
    return nothing
end
function _find_param_default(model::ComposeDef, name::Symbol)
    for e in traverse_entities(model)
        val = _find_param_default(e, name)
        val !== nothing && return val
    end
    return nothing
end

"""
    _init_u0(model, states, u0, params) -> Vector{Float64}

初始化状态向量。
"""
function _init_u0(model, states, u0, params)
    u0_vec = zeros(Float64, length(states))
    for (i, s) in enumerate(states)
        if haskey(u0, s)
            u0_vec[i] = Float64(u0[s])
        elseif haskey(params, s)
            u0_vec[i] = Float64(params[s])
        else
            found = _find_param_default(model, s)
            u0_vec[i] = found !== nothing ? Float64(found) :
                throw_diagnostic(
                    E_STATE_MISSING_INITIAL_VALUE;
                    phase=PHASE_RESOLVE,
                    human_message="状态缺少初始值",
                    human_summary="状态 :$s 没有初始值",
                    entity=Dict("kind" => "state", "name" => string(s)),
                    constraint="state_must_have_initial_value",
                    expected="initial_value",
                    actual="missing",
                    context=Dict{String, Any}("state" => string(s)),
                    repair_hints=[
                        "Provide the missing initial value through u0 or params.",
                        "Or define a default initial value in the model.",
                    ],
                    ai_hint=_default_ai_hint(
                        "Provide an initial value for the missing state while preserving the intended simulation behavior.",
                        string("The state ", s, " has no initial value from u0, params, or model defaults."),
                        [
                            "First check whether the state should be initialized through u0.",
                            "If not, add a stable model-level default or parameter binding.",
                        ];
                        constraints=[
                            "Do not change unrelated states.",
                            "Keep the patch minimal.",
                        ],
                        recheck=["resolve", "runtime_validation"],
                    ),
                    docs_ref="rules/states/state-must-have-initial-value",
                )
        end
    end
    return u0_vec
end

# ============================================================
# 5. Behavioral/Event Relation 编译器
#
# 将 Behavioral 或 Event relation 的表达式编译为
# 可调用的函数。与 compile_ode() 平级——都是
# "从 Core 模型到可执行形式"的编译管道。
#
# v2 — 基于显式状态变量声明，无 AST 猜测。
# ============================================================

"""
    compile_relation(rel::Relation, params::Vector{Parameter}) -> Function

将 Behavioral/Event relation 编译为可调用的行为函数。
编译后的函数签名: (state::Dict, t::Float64, dt::Float64) -> nothing

工作原理：
  1. 从 entity 参数列表 + 显式 state_vars（如果有）确定变量列表
  2. 生成 unpack 语句: local energy = state[:energy]
  3. 插入用户的 behavior 代码
  4. 生成 repack 语句: state[:energy] = energy

行为代码是正常的 Julia 代码，无需 quote/特殊写法。
编译依靠显式声明，不递归遍历 AST 猜测。
"""
function compile_relation(rel::Relation, params::Vector{Parameter}; eval_module::Module=@__MODULE__)
    # Phase 1: 确定要解包的变量名
    var_names = if haskey(rel.metadata, :state_vars)
        # 显式声明：只解包声明的变量 + entity 参数（去重）
        sv = rel.metadata[:state_vars]
        result = Symbol[p.name for p in params]
        for v in sv
            if !(v in result)
                push!(result, v)
            end
        end
        result
    else
        # 无显式声明：安全回退，解包所有 entity 参数
        Symbol[p.name for p in params]
    end

    # Phase 2: 无表达式 → 返回空函数
    if isempty(var_names) && rel.expr === nothing
        return (state, t, dt) -> nothing
    end

    # Phase 3: 生成 unpack/repack
    unpack_stmts = Expr[]
    for v in var_names
        push!(unpack_stmts, :(local $v = state[$(QuoteNode(v))]))
    end

    repack_stmts = Expr[]
    for v in var_names
        push!(repack_stmts, :(state[$(QuoteNode(v))] = $v))
    end

    # Phase 4: 准备 body
    body = rel.expr === nothing ? Expr(:block) : rel.expr
    if body isa Expr && body.head == :block
        filtered_args = filter(a -> !(a isa Expr && a.head == :line), body.args)
        body = Expr(:block, filtered_args...)
    end

    # Phase 5: 构建并求值函数
    fn_body = Expr(:block, unpack_stmts..., body, repack_stmts...)
    fn_expr = :((state, t, dt) -> begin; $fn_body; return nothing; end)
    return Core.eval(eval_module, fn_expr)
end

# ============================================================
# 6. Agent 消息传递
#
# 简单的邮箱模式：每个 agent 的 _mailbox 是 Vector{Message}，
# send! 通过全局 Ref 写入目标 agent 的 mailbox。
# DESolver 在 solve() 开始/结束时管理 Ref 生命周期。
#
# 设计理由：单线程仿真，全局 Ref 足够安全且调用最简洁。
# 未来可扩展为异步消息队列（需要多线程时）。
# ============================================================

"""
    Message

agent 间消息。
- from: 发送者 entity 名称
- to: 接收者 entity 名称
- content: 消息内容（任意类型）
"""
struct Message
    from::Symbol
    to::Symbol
    content::Any
end

"""
    _MSG_CTX

全局消息上下文，由 DESolver 管理生命周期。
"""
const _MSG_CTX = Ref{Union{Nothing, Dict{Symbol, Dict{Symbol, Any}}}}(nothing)

"""
    send!(from, to, content)

发送消息到指定 agent 的 _mailbox。
在 AgentBased 的 @on_tick 或 @statechart 行为代码中直接调用。
无需手动管理——DESolver 自动设置消息上下文。

示例:
    @on_tick :hunt begin
        if energy < 30
            send!(my_name, :Wolf, :help)
        end
    end
"""
function send!(from::Symbol, to::Symbol, content)
    ctx = _MSG_CTX[]
    ctx === nothing && throw_diagnostic(
        E_RUNTIME_SEND_OUTSIDE_SIMULATION;
        phase="simulation_runtime",
        human_message="send!() 使用位置非法",
        human_summary="send!() 只能在仿真循环中使用",
        entity=Dict("kind" => "runtime_call", "function" => "send!"),
        constraint="send_requires_active_simulation_context",
        expected="active_simulation_context",
        actual="missing_context",
        repair_hints=[
            "Call send!() only from simulation behavior executed inside the solver loop.",
            "If message passing is needed outside runtime, use an explicit setup or scheduling API instead.",
        ],
        ai_hint=_default_ai_hint(
            "Move or refactor the send! call so it executes within an active simulation context.",
            "The send! runtime helper was invoked when no simulation message context was active.",
            [
                "Check whether the call was placed in model setup code instead of runtime behavior.",
                "If runtime messaging is intended, move the call into solver-driven behavior execution.",
            ];
            constraints=[
                "Do not change unrelated runtime code.",
                "Keep the patch minimal.",
            ],
            recheck=["simulation_runtime"],
        ),
        docs_ref="rules/runtime/send-requires-active-simulation",
    )
    haskey(ctx, to) || throw_diagnostic(
        E_RUNTIME_UNKNOWN_AGENT;
        phase="simulation_runtime",
        human_message="send!() 目标 agent 不存在",
        human_summary="send!() 目标 agent 不存在: $to",
        entity=Dict("kind" => "runtime_call", "function" => "send!", "target" => string(to)),
        constraint="message_target_agent_must_exist",
        expected="known_agent",
        actual=string(to),
        context=Dict{String, Any}("target" => string(to)),
        repair_hints=[
            "Use an existing agent name as the message target.",
            "If the agent should exist, declare or instantiate it before sending messages to it.",
        ],
        ai_hint=_default_ai_hint(
            "Replace the unknown message target with an existing agent or create the intended agent if required.",
            string("The send! call targets agent ", to, ", but no such agent exists in the current simulation context."),
            [
                "Check for a spelling mismatch first.",
                "If the intended target already exists under a different name, use that name.",
                "Only add a new agent if the model clearly requires it.",
            ];
            constraints=[
                "Do not change unrelated agents.",
                "Keep the patch minimal.",
            ],
            recheck=["simulation_runtime", "name_resolution"],
        ),
        docs_ref="rules/runtime/message-target-agent-exists",
    )
    push!(ctx[to][:_mailbox], Message(from, to, content))
    return nothing
end

"""
    _init_msg_ctx!(states)

初始化消息上下文。
由 DESolver 在求解开始前调用。
"""
function _init_msg_ctx!(states::Dict{Symbol, Dict{Symbol, Any}})
    _MSG_CTX[] = states
    return nothing
end

"""
    _clear_msg_ctx!()

清理消息上下文。
由 DESolver 在求解结束后调用。
"""
function _clear_msg_ctx!()
    _MSG_CTX[] = nothing
    return nothing
end
