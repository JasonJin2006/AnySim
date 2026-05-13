# ============================================================
# runtime.jl — DEVS 运行时与 DSL
# ============================================================

"""
    INFINITY

表示 DEVS 中的无穷大时间推进（被动状态）。
"""
const INFINITY = Inf

"""
    Phase 常量

DEVS 相位标识 — 用 Symbol 表示。
"""
const PhaseInit = :init
const PhaseActive = :active
const PhasePassive = :passive
const PhaseDone = :done

"""
    DEVSMessage

DEVS 端口消息的载体。
"""
struct DEVSMessage
    port::Symbol
    value::Any
end

# ============================================================
# 2. 状态管理辅助函数（用于 behavior 代码中）
#
# 这些函数直接在 state dict 上操作，适用于被 compile_relation
# 编译后的函数内部调用。
#
# 在 lambdaf/deltint/deltext 代码中，可以直接调用:
#   hold_in(state, :sailing, 5.0)
#   passivate(state)
#   activate(state)
#   devs_send!(state, :o_arrival, event)
#   msgs = devs_receive(state, :i_cargo)
# ============================================================

"""
    sigma(state) -> Float64

获取当前时间推进值（ta）。
"""
sigma(state) = get(state, :_sigma, INFINITY)

"""
    set_sigma(state, value)

设置时间推进值。
"""
set_sigma(state, value) = (state[:_sigma] = Float64(value))

"""
    hold_in(state, phase::Symbol, sigma_val)

进入指定阶段，设置时间推进。
等效于 DEVS 的 hold_in(phase, sigma)。
"""
function hold_in(state, phase::Symbol, sigma_val::Real)
    state[:_phase] = phase
    state[:_sigma] = Float64(sigma_val)
end

"""
    passivate(state)

进入被动状态（ta = ∞），等待外部事件。
"""
passivate(state) = hold_in(state, :passive, INFINITY)

"""
    activate(state)

在被动状态下立即激活（ta = 0），触发内部转移。
"""
activate(state) = hold_in(state, state[:_phase], 0.0)

"""
    continuef(state, e)

外部转移后保持当前阶段，减去消耗的时间 e。
"""
continuef(state, e) = (state[:_sigma] -= Float64(e))

function _rewrite_devs_helpers(expr)
    if !(expr isa Expr)
        return expr
    end

    if expr.head == :call && !isempty(expr.args)
        fn = expr.args[1]
        if fn == :hold_in && length(expr.args) == 4 && expr.args[2] == :state
            phase = _rewrite_devs_helpers(expr.args[3])
            sigma_val = _rewrite_devs_helpers(expr.args[4])
            return quote
                _phase = $phase
                _sigma = Float64($sigma_val)
            end
        elseif fn == :passivate && length(expr.args) == 2 && expr.args[2] == :state
            return quote
                _phase = :passive
                _sigma = INFINITY
            end
        elseif fn == :activate && length(expr.args) == 2 && expr.args[2] == :state
            return quote
                _sigma = 0.0
            end
        elseif fn == :continuef && length(expr.args) == 3 && expr.args[2] == :state
            e = _rewrite_devs_helpers(expr.args[3])
            return :(_sigma -= Float64($e))
        elseif fn == :set_sigma && length(expr.args) == 3 && expr.args[2] == :state
            sigma_val = _rewrite_devs_helpers(expr.args[3])
            return :(_sigma = Float64($sigma_val))
        end
    end

    new_args = Any[_rewrite_devs_helpers(arg) for arg in expr.args]
    return Expr(expr.head, new_args...)
end

"""
    devs_send!(state, port_name::Symbol, value)

在 lambdaf 中发送消息到指定输出端口。
"""
function devs_send!(state, port_name::Symbol, value)
    outbox = get(state, :_outbox, DEVSMessage[])
    push!(outbox, DEVSMessage(port_name, value))
    state[:_outbox] = outbox
end

"""
    devs_receive(state, port_name::Symbol) -> Vector{DEVSMessage}

在 deltext 中接收指定端口的消息。
"""
function devs_receive(state, port_name::Symbol)
    inbox = get(state, :_inbox, DEVSMessage[])
    return [msg for msg in inbox if msg.port == port_name]
end

"""
    devs_has_input(state, port_name::Symbol) -> Bool

检查指定输入端口是否有消息。
"""
function devs_has_input(state, port_name::Symbol)
    inbox = get(state, :_inbox, DEVSMessage[])
    return any(msg -> msg.port == port_name, inbox)
end

# ============================================================
# 3. 宏辅助函数（用于 @devs_atomic 的定义时解析）
# ============================================================

"""
    _devs_macro_name(macro_arg) -> Union{Symbol, Nothing}

统一处理宏名: 兼容 Symbol 和 GlobalRef 形式。
"""
function _devs_macro_name(macro_arg)
    if macro_arg isa Symbol
        return macro_arg
    elseif macro_arg isa GlobalRef
        return Symbol("@", macro_arg.name)
    end
    return nothing
end

function _lookup_devs_type_binding(name::Symbol, base_module::Module)
    if isdefined(base_module, name)
        value = getfield(base_module, name)
        value isa Type && return value
    end
    if isdefined(Main, name)
        value = getfield(Main, name)
        value isa Type && return value
    end
    if isdefined(Base, name)
        value = getfield(Base, name)
        value isa Type && return value
    end
    if isdefined(Core, name)
        value = getfield(Core, name)
        value isa Type && return value
    end
    return nothing
end

function _resolve_devs_type_expr(type_expr; base_module::Module=@__MODULE__)
    if type_expr isa Symbol
        resolved = _lookup_devs_type_binding(type_expr, base_module)
        resolved !== nothing && return resolved
    elseif type_expr isa Expr && type_expr.head == :curly
        base_type = _resolve_devs_type_expr(type_expr.args[1]; base_module=base_module)
        params = map(arg -> _resolve_devs_type_expr(arg; base_module=base_module), type_expr.args[2:end])
        return base_type{params...}
    elseif type_expr isa Expr && type_expr.head == :. && length(type_expr.args) == 2
        parent = _resolve_devs_type_expr(type_expr.args[1]; base_module=base_module)
        field = type_expr.args[2]
        field_name = field isa QuoteNode ? field.value : field
        if parent isa Module && field_name isa Symbol && isdefined(parent, field_name)
            resolved = getfield(parent, field_name)
            resolved isa Type && return resolved
        end
    elseif type_expr isa GlobalRef
        resolved = getfield(type_expr.mod, type_expr.name)
        resolved isa Type && return resolved
    end
    throw(ArgumentError("unsupported type expression: $(repr(type_expr))"))
end

"""
    _make_devs_port(expr, direction) -> Port

解析端口定义表达式 (如 `x::Int` 或 `name`)，
返回带指定方向的 Port。
"""
function _make_devs_port(expr, direction)
    if expr isa Symbol
        return Port(expr, Any, direction)
    elseif expr isa Expr && expr.head == :(::)
        return Port(expr.args[1], _resolve_devs_type_expr(expr.args[2]), direction)
    end
    error("不支持的 @port_in/@port_out 语法: $expr")
end

"""
    _make_devs_param(expr) -> Parameter

解析参数定义表达式。
支持:
  @state R             → Symbol, 类型 Any, 无默认值
  @state R::Real       → (::), 类型 Real, 无默认值
  @state R = 1000      → (=), 类型 Any, 默认值 1000
  @state R::Real = 1000  → (::) + (=), 类型 Real, 默认值 1000
"""
function _make_devs_param(expr)
    if expr isa Symbol
        return Parameter(expr, nothing, Any)
    elseif expr isa Expr && expr.head == :(::)
        return Parameter(expr.args[1], nothing, _resolve_devs_type_expr(expr.args[2]))
    elseif expr isa Expr && expr.head == :(=)
        lhs = expr.args[1]
        value = expr.args[2]
        # 宏上下文中 :symbol 被解析为 QuoteNode，需解包为 Symbol
        if value isa QuoteNode
            value = value.value
        end
        if lhs isa Symbol
            return Parameter(lhs, value, Any)
        elseif lhs isa Expr && lhs.head == :(::)
            return Parameter(lhs.args[1], value, _resolve_devs_type_expr(lhs.args[2]))
        end
    end
    error("不支持的 @state 语法: $expr")
end

# ============================================================
# 4. DEVS 原子模型定义宏
#
# @devs_atomic Name begin
#     @port_in  x::Int
#     @port_out y::Float64
#
#     @state   phase = :init
#     @state   sigma = 0.0
#     @state   counter = 0
#
#     @ta begin
#         # ta 函数：设置 _sigma 的值
#         # 注意：编译后的函数通过 unpack→code→repack 机制，
#         # 用户只需在代码中写入 _sigma = 计算值，就会被回写到 state[:_sigma]
#     end
#
#     @lambdaf begin
#         # 输出函数：产生输出到 out port
#         # 使用 devs_send!(state, :port_name, value)
#     end
#
#     @deltint begin
#         # 内部转移
#         # 使用 hold_in(state, :phase, sigma)
#     end
#
#     @deltext begin
#         # 外部转移：e = 距上次转移的时间 (自动注入)
#         # 使用 devs_receive(state, :port_name) 获取输入消息
#     end
# end
#
# 展开为: Name = EntityDef(:Name, [ports...], [relations...], [params...])
#
# 其中 relations 包含带 DEVS 标签的 Behavioral 类型：
#   - :devs_ta     → ta 函数
#   - :devs_lambdaf → 输出函数
#   - :devs_deltint → 内部转移
#   - :devs_deltext → 外部转移
# ============================================================

macro devs_atomic(name, body)
    ports = Port[]
    params = Parameter[]
    relations = Relation[]

    ta_body = nothing
    lambdaf_body = nothing
    deltint_body = nothing
    deltext_body = nothing

    # 第一步：解析 body 中的所有子句
    @assert body isa Expr && body.head == :block "@devs_atomic body 必须是 begin...end 块"

    for stmt in body.args
        if !(stmt isa Expr) || stmt.head != :macrocall
            continue
        end

        mn = _devs_macro_name(stmt.args[1])
        mn === nothing && continue

        if mn == Symbol("@port_in")
            push!(ports, _make_devs_port(stmt.args[3], :in))

        elseif mn == Symbol("@port_out")
            push!(ports, _make_devs_port(stmt.args[3], :out))

        elseif mn == Symbol("@state")
            push!(params, _make_devs_param(stmt.args[3]))

        elseif mn == Symbol("@ta")
            ta_body = stmt.args[3]

        elseif mn == Symbol("@lambdaf")
            lambdaf_body = stmt.args[3]

        elseif mn == Symbol("@deltint")
            deltint_body = stmt.args[3]

        elseif mn == Symbol("@deltext")
            # 支持两种语法:
            #   @deltext(e) begin ... end  → args[3]=:e, args[4]=body
            #   @deltext begin ... end     → args[3]=body (e 自动注入)
            if length(stmt.args) >= 4
                deltext_body = stmt.args[4]
            else
                deltext_body = stmt.args[3]
            end
        end
    end

    # 第二步：注入 DEVS 系统参数（仅当用户未显式声明时添加）
    for (name, default, ptype) in [
        (:_phase, PhaseInit, Symbol),
        (:_sigma, 0.0, Float64),
        (:_inbox, DEVSMessage[], Vector{DEVSMessage}),
        (:_outbox, DEVSMessage[], Vector{DEVSMessage}),
    ]
        if !any(p -> p.name == name, params)
            push!(params, Parameter(name, default, ptype))
        end
    end

    # 第三步：生成 Behavioral relation（带 DEVS 标签）
    if ta_body !== nothing
        push!(relations, Relation(:ta, Behavioral, _rewrite_devs_helpers(ta_body), [:devs_ta, :behavioral]))
    end
    if lambdaf_body !== nothing
        push!(relations, Relation(:lambdaf, Behavioral, _rewrite_devs_helpers(lambdaf_body), [:devs_lambdaf, :behavioral]))
    end
    if deltint_body !== nothing
        push!(relations, Relation(:deltint, Behavioral, _rewrite_devs_helpers(deltint_body), [:devs_deltint, :behavioral]))
    end
    if deltext_body !== nothing
        # 第四步：为 deltext 注入 local e = dt
        # 这样用户在 @deltext(e) begin ... end 中可以使用 e 表示流逝时间
        # 内部实现中，compile_relation 生成 (state, t, dt) -> nothing 函数，
        # DEVS solver 调用时第三个参数 (dt) 是流逝时间 tn
        injected_body = if deltext_body isa Expr && deltext_body.head == :block
            filtered = filter(a -> !(a isa Expr && a.head == :line), deltext_body.args)
            Expr(:block, :(local e = dt), filtered...)
        else
            Expr(:block, :(local e = dt), deltext_body)
        end
        push!(relations, Relation(:deltext, Behavioral, _rewrite_devs_helpers(injected_body), [:devs_deltext, :behavioral]))
    end

    # 第五步：构造 EntityDef（此时构造，嵌入为字面量）
    ed = EntityDef(name, ports, relations, params)
    return :($(esc(name)) = $ed)
end

# ============================================================
# 5. DEVS 求解器（Coordinator）
# ============================================================

struct DEVSSolver <: AbstractSolver
    max_steps::Int
    max_time::Float64
end

DEVSSolver(; max_steps=100000, max_time=1e6) = DEVSSolver(max_steps, max_time)
DEVSSolver() = DEVSSolver(100000, 1e6)

function can_solve(::DEVSSolver, model::ComposeDef)
    # 任何模型都能用 DEVS 求解器
    return true
end

function can_solve(::DEVSSolver, model::EntityDef)
    return true
end

# ============================================================
# 6. DEVS 仿真引擎（运行时）
# ============================================================

mutable struct DEVSContext
    compiled::CompiledDEVSModel
    runtime::DEVSRuntimeState

    # 组件状态：实体名 → 状态字典
    states::Dict{Symbol, Dict{Symbol, Any}}

    # DEVS 行为函数：
    # ta_fn:      (state, ctx, 0.0) -> nothing  （设置 state[:_sigma]）
    # lambdaf_fn: (state, ctx, 0.0) -> nothing  （输出消息到 _outbox）
    # deltint_fn: (state, ctx, 0.0) -> nothing  （内部转移）
    # deltext_fn: (state, ctx, e)   -> nothing  （外部转移, e=流逝时间）
    ta_fns::Dict{Symbol, Function}
    lambdaf_fns::Dict{Symbol, Function}
    deltint_fns::Dict{Symbol, Function}
    deltext_fns::Dict{Symbol, Function}

    # 耦合定义 (from_entity, from_port, to_entity, to_port)
    couplings::Vector{Tuple{Symbol,Symbol,Symbol,Symbol}}

    # 当前仿真时间
    current_time::Float64
end

"""
    init_devs_context(model::ComposeDef) -> DEVSContext

从 ComposeDef 初始化 DEVS 运行时上下文。
遍历所有 entity，提取 DEVS 关系并编译为行为函数。
"""
function init_devs_context(model::ComposeDef)
    compiled = compile_devs_ir(model)
    diag = devs_compile_diagnostics(compiled)
    if has_devs_compile_warnings(diag)
        @info "[DEVS] 编译诊断" model=String(compiled.model_name) missing_ta=diag.missing_ta missing_lambdaf=diag.missing_lambdaf missing_deltint=diag.missing_deltint missing_deltext=diag.missing_deltext
    end
    runtime = DEVSRuntimeState(compiled)

    states = Dict{Symbol, Dict{Symbol, Any}}()
    ta_fns = Dict{Symbol, Function}()
    lambdaf_fns = Dict{Symbol, Function}()
    deltint_fns = Dict{Symbol, Function}()
    deltext_fns = Dict{Symbol, Function}()
    couplings = Tuple{Symbol,Symbol,Symbol,Symbol}[]

    for (i, ent_name) in enumerate(compiled.entity_names)
        states[ent_name] = runtime.states[i]

        ta_fn = compiled.ta_fns[i]
        ta_fn !== nothing && (ta_fns[ent_name] = ta_fn)

        lambdaf_fn = compiled.lambdaf_fns[i]
        lambdaf_fn !== nothing && (lambdaf_fns[ent_name] = lambdaf_fn)

        deltint_fn = compiled.deltint_fns[i]
        deltint_fn !== nothing && (deltint_fns[ent_name] = deltint_fn)

        deltext_fn = compiled.deltext_fns[i]
        deltext_fn !== nothing && (deltext_fns[ent_name] = deltext_fn)
    end

    for coupling in compiled.couplings
        push!(couplings, Tuple(coupling))
    end

    return DEVSContext(
        compiled,
        runtime,
        states,
        ta_fns,
        lambdaf_fns,
        deltint_fns,
        deltext_fns,
        couplings,
        runtime.current_time,
    )
end

# ============================================================
# 协议层集成（DEVSContext → SimState 转换）
# 定义在 DEVS.jl 而不是 protocol.jl，因为 DEVSContext 在此定义
# ============================================================

"""
    make_sim_state(ctx::DEVSContext, entities::Vector{EntityDef}; kwargs...) -> SimState

DEVSContext 的重载版本。委派给核心 make_sim_state。
"""
function make_sim_state(ctx::DEVSContext, entities::Vector{EntityDef}; kwargs...)
    return make_sim_state(ctx.current_time, _devs_state_dict(ctx), entities; kwargs...)
end

devs_entity_names(ctx::DEVSContext) = ctx.compiled.entity_names

function devs_entity_state(ctx::DEVSContext, ent_name::Symbol)
    return _entity_state(ctx, ent_name)
end

function _devs_state_dict(ctx::DEVSContext)
    states = Dict{Symbol, Dict{Symbol, Any}}()
    for ent_name in devs_entity_names(ctx)
        states[ent_name] = devs_entity_state(ctx, ent_name)
    end
    return states
end

_devs_state_snapshot(ctx::DEVSContext) = deepcopy(_devs_state_dict(ctx))

function _sync_runtime_time!(ctx::DEVSContext)
    ctx.runtime.current_time = ctx.current_time
    return nothing
end

_entity_names(ctx::DEVSContext) = devs_entity_names(ctx)

function _entity_state(ctx::DEVSContext, ent_name::Symbol)
    idx = ctx.compiled.entity_index[ent_name]
    return ctx.runtime.states[idx]
end

function _entity_state_by_index(ctx::DEVSContext, idx::Int)
    return ctx.runtime.states[idx]
end

function _entity_index(ctx::DEVSContext, ent_name::Symbol)
    return ctx.compiled.entity_index[ent_name]
end

function _compiled_ta_fn(ctx::DEVSContext, ent_name::Symbol)
    return ctx.compiled.ta_fns[_entity_index(ctx, ent_name)]
end

function _compiled_lambdaf_fn(ctx::DEVSContext, ent_name::Symbol)
    return ctx.compiled.lambdaf_fns[_entity_index(ctx, ent_name)]
end

function _compiled_deltint_fn(ctx::DEVSContext, ent_name::Symbol)
    return ctx.compiled.deltint_fns[_entity_index(ctx, ent_name)]
end

function _compiled_deltext_fn(ctx::DEVSContext, ent_name::Symbol)
    return ctx.compiled.deltext_fns[_entity_index(ctx, ent_name)]
end

function _sync_state_views!(ctx::DEVSContext)
    for ent_name in ctx.compiled.entity_names
        ctx.states[ent_name] = _entity_state(ctx, ent_name)
    end
    return nothing
end

"""
    time_advance(ctx::DEVSContext) -> (Float64, Vector{Symbol})

计算全局最小时间推进，返回 (tn, 该时间点触发的组件列表)。

重要: 在读取 sigma 之前，先调用每个组件的 ta 函数来计算 sigma。
ta 函数通过 compile_relation 的 unpack→code→repack 机制设置 state[:_sigma]。
"""
function time_advance(ctx::DEVSContext)
    # 第一步：调用每个组件 ta 函数，计算 sigma
    for ent_name in _entity_names(ctx)
        state = _entity_state(ctx, ent_name)
        ta_fn = _compiled_ta_fn(ctx, ent_name)
        if ta_fn !== nothing
            try
                Base.invokelatest(ta_fn, state, ctx, 0.0)
            catch e
                @warn "[DEVS] ta 失败: $ent_name: $e"
                showerror(stderr, e)
                println()
            end
        end
    end

    # 第二步：找出最小 sigma 和 imminent 组件
    tn = INFINITY
    imminent = Symbol[]

    for ent_name in _entity_names(ctx)
        state = _entity_state(ctx, ent_name)
        sigma_val = get(state, :_sigma, INFINITY)
        if sigma_val < tn
            tn = sigma_val
            imminent = [ent_name]
        elseif sigma_val == tn
            push!(imminent, ent_name)
        end
    end

    return tn, imminent
end

"""
    route_messages!(ctx::DEVSContext)

从所有组件的 _outbox 路由消息到目标组件的 _inbox。
"""
function route_messages!(ctx::DEVSContext)
    for (from_ent, from_port, to_ent, to_port) in ctx.compiled.couplings
        outbox = get(_entity_state(ctx, from_ent), :_outbox, DEVSMessage[])
        for msg in outbox
            if msg.port == from_port
                inbox = get(_entity_state(ctx, to_ent), :_inbox, DEVSMessage[])
                push!(inbox, DEVSMessage(to_port, msg.value))
            end
        end
    end
end

function devs_collect_outputs(ctx::DEVSContext)
    outputs = Dict{Symbol, Vector{DEVSMessage}}()
    for ent_name in _entity_names(ctx)
        outbox = get(_entity_state(ctx, ent_name), :_outbox, DEVSMessage[])
        outputs[ent_name] = deepcopy(outbox)
    end
    return outputs
end

"""
    devs_step!(ctx::DEVSContext) -> Bool

执行一步 Parallel DEVS 仿真。

流程:
  1. 计算全局最小时间推进 tn 和 imminent 集合
  2. 推进所有组件的时间
  3. λ: imminent 组件的输出函数
  4. 路由消息 (imminent 的输出 → 目标组件的输入)
  5. δ_int: imminent 组件的内部转移
  6. δ_ext: 所有有外部输入的组件执行外部转移
  7. Clear: 清空所有 inbox 和 outbox

返回: 仿真是否继续 (true=继续, false=结束)
"""
function devs_step!(ctx::DEVSContext; max_time::Float64=INFINITY, capture_outputs::Bool=false)
    # 1. 调用 ta 函数计算 sigma，找最小 tn 和 imminent
    tn, imminent = time_advance(ctx)

    # ta 返回 INFINITY → 没有事件要处理
    if tn >= INFINITY || tn > 1e10
        return false
    end
    if ctx.current_time + tn > max_time
        return false
    end

    # 2. 推进时间
    for ent_name in _entity_names(ctx)
        state = _entity_state(ctx, ent_name)
        state[:_sigma] -= tn
    end
    ctx.current_time += tn
    _sync_runtime_time!(ctx)

    # 3. λ: 对 imminent 组件执行输出函数
    for ent_name in imminent
        lambdaf_fn = _compiled_lambdaf_fn(ctx, ent_name)
        if lambdaf_fn !== nothing
            try
                Base.invokelatest(lambdaf_fn,
                    _entity_state(ctx, ent_name), ctx, 0.0)
            catch e
                @warn "[DEVS] lambdaf 失败: $ent_name: $e"
            end
        end
    end

    # 4. 路由消息
    route_messages!(ctx)

    # 5. δ_int: 对 imminent 组件执行内部转移
    for ent_name in imminent
        deltint_fn = _compiled_deltint_fn(ctx, ent_name)
        if deltint_fn !== nothing
            try
                Base.invokelatest(deltint_fn,
                    _entity_state(ctx, ent_name), ctx, 0.0)
            catch e
                @warn "[DEVS] deltint 失败: $ent_name: $e"
            end
        end
    end

    # 6. δ_ext: 对所有有外部输入的组件执行外部转移
    for ent_name in _entity_names(ctx)
        state = _entity_state(ctx, ent_name)
        inbox = get(state, :_inbox, DEVSMessage[])
        deltext_fn = _compiled_deltext_fn(ctx, ent_name)
        if !isempty(inbox) && deltext_fn !== nothing
            try
                Base.invokelatest(deltext_fn,
                    state, ctx, tn)
            catch e
                @warn "[DEVS] deltext 失败: $ent_name: $e"
            end
        end
    end

    captured_outputs = capture_outputs ? devs_collect_outputs(ctx) : nothing

    # 7. Clear: 清空所有 inbox 和 outbox
    for ent_name in _entity_names(ctx)
        state = _entity_state(ctx, ent_name)
        state[:_inbox] = DEVSMessage[]
        state[:_outbox] = DEVSMessage[]
    end

    _sync_state_views!(ctx)

    if capture_outputs
        return (running=true, outputs=captured_outputs)
    end
    return true
end

# ============================================================
# 7. 求解入口
# ============================================================

"""
    solve(solver::DEVSSolver, model::ComposeDef; ...)

使用 DEVS 求解器运行仿真。
"""
function solve(solver::DEVSSolver, model::ComposeDef;
               u0=Dict{Symbol,Float64}(), tspan=(0.0, 1e6),
               params=Dict{Symbol,Any}())

    ctx = init_devs_context(model)
    ctx.current_time = tspan[1]
    _sync_runtime_time!(ctx)
    t_stop = min(tspan[2], solver.max_time)

    step = 0
    times = Float64[tspan[1]]
    records = [_devs_state_snapshot(ctx)]

    while ctx.current_time < t_stop && step < solver.max_steps
        step += 1
        running = devs_step!(ctx; max_time=t_stop)
        if !running
            break
        end
        push!(times, ctx.current_time)
        push!(records, _devs_state_snapshot(ctx))
    end

    # 构建结果
    result = _build_devs_result(times, records, model)
    return result
end

function solve(solver::DEVSSolver, model::EntityDef; kwargs...)
    comp = ComposeDef(model.name, [model], Relation[], Connection[], [])
    return solve(solver, comp; kwargs...)
end

# 自注册
register_solver!(DEVSSolver)

# ============================================================
# 8. 结果构建
# ============================================================

"""
    DEVSResult

DEVS 求解器的仿真结果。
- times: 时间点序列
- states: 数值型状态轨迹 (entity_var → Float64[])
- raw: 非数值状态 (entity_var → Any[])
"""
struct DEVSResult
    times::Vector{Float64}
    states::Dict{Symbol, Vector}
    raw::Dict{Symbol, Vector}
end

const _DEVS_INTERNAL_STATE_KEYS = Set{Symbol}([
    :_phase, :_sigma, :_inbox, :_outbox,
])

_is_devs_internal_state_key(name::Symbol) = name in _DEVS_INTERNAL_STATE_KEYS

function _collect_devs_result_keys(records::Vector{Dict{Symbol,Dict{Symbol,Any}}},
                                   entity::EntityDef)
    keys_set = Set{Symbol}()

    for p in entity.parameters
        _is_devs_internal_state_key(p.name) && continue
        push!(keys_set, p.name)
    end

    for record in records
        if haskey(record, entity.name)
            for key in keys(record[entity.name])
                _is_devs_internal_state_key(key) && continue
                push!(keys_set, key)
            end
        end
    end

    return sort!(collect(keys_set))
end

function _build_devs_result(times::Vector{Float64},
                            records::Vector{Dict{Symbol,Dict{Symbol,Any}}},
                            model::ComposeDef)
    n_steps = length(times)
    states = Dict{Symbol, Vector}()
    raw = Dict{Symbol, Vector}()

    # 遍历所有显式用户状态：
    #   1. entity.parameters 中声明的非内部字段
    #   2. 运行记录里动态出现的非内部字段
    for e in traverse_entities(model)
        for key in _collect_devs_result_keys(records, e)
            sname = Symbol(string(e.name, "_", key))
            values = Vector{Any}(undef, n_steps)
            fill!(values, nothing)
            for step in 1:n_steps
                if haskey(records[step], e.name) && haskey(records[step][e.name], key)
                    values[step] = records[step][e.name][key]
                end
            end

            present_values = [v for v in values if v !== nothing]
            isempty(present_values) && continue

            if all(v -> v isa Number, present_values)
                numeric_values = Vector{Float64}(undef, n_steps)
                for i in 1:n_steps
                    v = values[i]
                    numeric_values[i] = v === nothing ? NaN : Float64(v)
                end
                states[sname] = numeric_values
            else
                raw[sname] = values
            end
        end
    end

    return DEVSResult(times, states, raw)
end

# ============================================================
# 9. @devs_coupled — DEVS 耦合模型宏
#
# 语法:
#   @devs_coupled Name begin
#       @entity Vessel1 = make_vessel(...)
#       @entity PortSH = make_port(...)
#       @connect Vessel1.o_arrival, PortSH.i_arrival
#       @connect PortSH.o_cargo_out, Vessel1.i_cargo
#       @expose i_in = PortSH.i_cargo_in
#   end
#
# 在 AnySim 中，@compose 已经包含了 @entity/@connect/@expose 等完整语法。
# @devs_coupled 仅增加 @component(≡@entity) 和 @link(≡@connect, 支持 --> 箭头) 别名。
# 实际上直接使用 @compose 就足够了。
# ============================================================

macro devs_coupled(name, body)
    # 将 @component X = ... 转换为 @entity X = ...
    # 将 @link A.x, B.y 或 @link A.x --> B.y 转换为 @connect A.x, B.y
    new_stmts = Expr[]

    for stmt in body.args
        if stmt isa Expr && stmt.head == :macrocall
            mn = _devs_macro_name(stmt.args[1])
            if mn == Symbol("@component")
                # @component X = Expr → @entity X = Expr
                push!(new_stmts, Expr(:macrocall, Symbol("@entity"), stmt.args[2], stmt.args[3]))
            elseif mn == Symbol("@link")
                # @link A.x, B.y → @connect A.x, B.y
                link_expr = stmt.args[3]
                if link_expr isa Expr && link_expr.head == :tuple
                    push!(new_stmts, Expr(:macrocall, Symbol("@connect"), stmt.args[2], link_expr))
                elseif link_expr isa Expr && link_expr.head == :call && link_expr.args[1] == :-->
                    # @link A.x --> B.y (箭头语法)
                    push!(new_stmts, Expr(:macrocall, Symbol("@connect"), stmt.args[2],
                        Expr(:tuple, link_expr.args[2], link_expr.args[3])))
                else
                    error("不支持的 @link 语法")
                end
            else
                push!(new_stmts, stmt)
            end
        else
            push!(new_stmts, stmt)
        end
    end

    # 委派给 @compose
    new_body = Expr(:block, new_stmts...)
    return esc(:(@compose $name $new_body))
end
