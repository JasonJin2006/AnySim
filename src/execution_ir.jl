# ============================================================
# Execution IR — 执行层中间表示
#
# Core IR 面向人类和 LLM：表达灵活、元数据丰富。
# Execution IR 面向求解器：结构明确、可预分配、适合热路径执行。
# ============================================================

abstract type AbstractExecutionIR end
abstract type AbstractExecutionRuntime end
abstract type AbstractODEProgramNode end
abstract type AbstractODEOpcode end

struct ODEValue
    num::Float64
    flag::Bool
    is_bool::Bool
end

struct ODELiteral <: AbstractODEProgramNode
    value::Any
end

struct ODEStateRef <: AbstractODEProgramNode
    index::Int
end

struct ODEParamRef <: AbstractODEProgramNode
    name::Symbol
end

struct ODETimeRef <: AbstractODEProgramNode end

struct ODECall <: AbstractODEProgramNode
    fname::Symbol
    args::Vector{AbstractODEProgramNode}
end

struct ODEIfElse <: AbstractODEProgramNode
    cond::AbstractODEProgramNode
    on_true::AbstractODEProgramNode
    on_false::AbstractODEProgramNode
end

struct ODEPushLiteral <: AbstractODEOpcode
    value::Float64
end

struct ODEPushBool <: AbstractODEOpcode
    value::Bool
end

struct ODEPushState <: AbstractODEOpcode
    index::Int
end

struct ODEPushParam <: AbstractODEOpcode
    name::Symbol
end

struct ODEPushTime <: AbstractODEOpcode end

struct ODEApplyCall <: AbstractODEOpcode
    fname::Symbol
    argc::Int
end

struct ODESelect <: AbstractODEOpcode end

"""
    CompiledODEModel

ODE 求解器的执行层表示。
由 `compile_ode_ir(model)` 生成，作为数值求解器的稳定输入。
"""
struct CompiledODEModel <: AbstractExecutionIR
    model_name::Symbol
    state_names::Vector{Symbol}
    param_names::Vector{Symbol}
    state_index::Dict{Symbol, Int}
    param_index::Dict{Symbol, Int}
    rhs_program::Vector{AbstractODEProgramNode}
    rhs_bytecode::Vector{Vector{AbstractODEOpcode}}
    f!::Function
end

"""
    ode_rhs!(compiled, du, u, p, t)

调用 ODE 执行模型的右端函数。
当前直接调用编译好的执行闭包，不再依赖 `eval/invokelatest`。
"""
function ode_rhs!(compiled::CompiledODEModel, du, u, p, t)
    return compiled.f!(du, u, p, t)
end

"""
    ODERuntimeBuffers

ODE 热路径使用的预分配缓存。
当前服务于 RK4，也为后续 step-by-step 模式保留结构。
"""
struct ODERuntimeBuffers <: AbstractExecutionRuntime
    du::Vector{Float64}
    k1::Vector{Float64}
    k2::Vector{Float64}
    k3::Vector{Float64}
    k4::Vector{Float64}
    tmp::Vector{Float64}
    vm_stack::Vector{ODEValue}
end

function ODERuntimeBuffers(compiled::CompiledODEModel)
    n = length(compiled.state_names)
    return ODERuntimeBuffers(
        zeros(Float64, n),
        zeros(Float64, n),
        zeros(Float64, n),
        zeros(Float64, n),
        zeros(Float64, n),
        zeros(Float64, n),
        ODEValue[],
    )
end

function ode_rhs!(compiled::CompiledODEModel, buffers::ODERuntimeBuffers, du, u, p, t)
    for (i, code) in enumerate(compiled.rhs_bytecode)
        empty!(buffers.vm_stack)
        du[i] = _odevalue_number(_eval_ode_bytecode(code, buffers.vm_stack, u, p, t))
    end
    return nothing
end

"""
    compile_ode_ir(model) -> Union{CompiledODEModel, Nothing}

将当前 Core 模型 lowering 为 ODE 执行表示。
这是 ODE 执行路径的正式编译入口。
"""
function compile_ode_ir(model::EntityDef)
    return _compile_entity_ode_ir(model.name, model.relations)
end

function compile_ode_ir(model::ComposeDef)
    flat = flatten(model)
    all_rels = vcat([e.relations for e in flat.entities]..., flat.relations)
    return _compile_entity_ode_ir(model.name, all_rels)
end

function _compile_entity_ode_ir(model_name::Symbol, relations::Vector{Relation})
    state_names = Symbol[]
    rhs_exprs = Any[]
    for rel in relations
        if _is_explicit_ode(rel.expr)
            state_name, rhs = _split_ode(rel.expr)
            push!(state_names, state_name)
            push!(rhs_exprs, rhs)
        end
    end
    isempty(state_names) && return nothing

    state_index = Dict(s => i for (i, s) in enumerate(state_names))
    all_syms = _collect_symbols(rhs_exprs)
    param_names = sort!(collect(setdiff(all_syms, Set(state_names), _BUILTIN_FUNS)))
    param_index = Dict(s => i for (i, s) in enumerate(param_names))

    param_set = Set(param_names)
    replaced = [_replace_refs(rhs, state_index, param_set) for rhs in rhs_exprs]
    rhs_program = AbstractODEProgramNode[_compile_ode_node(rhs) for rhs in replaced]
    rhs_bytecode = [_compile_ode_bytecode(node) for node in rhs_program]
    f! = _build_ode_rhs_closure(rhs_bytecode)
    return CompiledODEModel(
        model_name,
        state_names,
        param_names,
        state_index,
        param_index,
        rhs_program,
        rhs_bytecode,
        f!,
    )
end

function _build_ode_rhs_closure(rhs_bytecode::Vector{Vector{AbstractODEOpcode}})
    stack = ODEValue[]
    sizehint!(stack, 32)
    function f!(du, u, p, t)
        for (i, code) in enumerate(rhs_bytecode)
            empty!(stack)
            du[i] = _odevalue_number(_eval_ode_bytecode(code, stack, u, p, t))
        end
        return nothing
    end
    return f!
end

function _compile_ode_node(ex)
    if ex isa Number || ex isa Bool
        return ODELiteral(ex)
    elseif ex isa Symbol
        if ex == :t
            return ODETimeRef()
        end
        return ODELiteral(_ode_constant_value(ex))
    elseif ex isa Expr
        if ex.head == :ref
            target = ex.args[1]
            if target == :u
                return ODEStateRef(Int(ex.args[2]))
            elseif target == :p
                arg = ex.args[2]
                name = arg isa QuoteNode ? arg.value : arg
                return ODEParamRef(name)
            end
        elseif ex.head == :call
            fname = ex.args[1]
            args = AbstractODEProgramNode[_compile_ode_node(arg) for arg in ex.args[2:end]]
            return ODECall(fname, args)
        elseif ex.head == :if
            return ODEIfElse(
                _compile_ode_node(ex.args[1]),
                _compile_ode_node(ex.args[2]),
                _compile_ode_node(ex.args[3]),
            )
        elseif ex.head == :block
            filtered = filter(arg -> !(arg isa LineNumberNode), ex.args)
            isempty(filtered) && return ODELiteral(0.0)
            length(filtered) == 1 && return _compile_ode_node(filtered[1])
        end
    end
    throw_diagnostic(
        E_ODE_UNSUPPORTED_EXPRESSION;
        phase="semantic_validation",
        human_message="暂不支持的 ODE 表达式节点",
        human_summary="无法编译该 ODE 表达式节点: $(repr(ex))",
        entity=Dict("kind" => "ode_expression"),
        constraint="ode_expression_node_supported",
        expected="supported_ode_expression_node",
        actual=repr(ex),
        context=Dict{String, Any}("expr" => repr(ex)),
        repair_hints=[
            "Rewrite the ODE expression using supported arithmetic, comparison, boolean, and if-else constructs.",
            "Avoid unsupported AST node forms in ODE equations.",
        ],
        ai_hint=_default_ai_hint(
            "Rewrite the ODE expression into a form supported by the AnySim ODE compiler.",
            "The current ODE expression contains an AST node that the compiler does not support.",
            [
                "Reduce the expression to supported literals, symbols, calls, and if-else nodes.",
                "Preserve the mathematical intent while simplifying unsupported syntax.",
            ];
            constraints=[
                "Do not alter unrelated equations.",
                "Keep the patch minimal.",
            ],
            recheck=["semantic_validation"],
        ),
        docs_ref="rules/ode/supported-expression-nodes",
    )
end

_eval_ode_node(node::ODELiteral, u, p, t) = node.value
_eval_ode_node(node::ODEStateRef, u, p, t) = u[node.index]
_eval_ode_node(node::ODEParamRef, u, p, t) = p[node.name]
_eval_ode_node(::ODETimeRef, u, p, t) = t

function _eval_ode_node(node::ODECall, u, p, t)
    f = get(_ODE_CALL_FUNS, node.fname, nothing)
    f === nothing && throw_diagnostic(
        E_ODE_UNKNOWN_FUNCTION;
        phase="runtime_validation",
        human_message="未注册的 ODE 内建函数",
        human_summary="无法求值 ODE 内建函数: $(node.fname)",
        entity=Dict("kind" => "ode_call", "function" => string(node.fname)),
        constraint="ode_builtin_function_must_exist",
        expected="registered_ode_builtin",
        actual=string(node.fname),
        context=Dict{String, Any}("function" => string(node.fname)),
        repair_hints=[
            "Use a supported ODE builtin function.",
            "If the function is intended to be supported, register it before evaluation.",
        ],
        ai_hint=_default_ai_hint(
            "Replace the unknown ODE builtin function with a registered function or register the intended function.",
            string("The ODE evaluator could not find a registered builtin named ", node.fname, "."),
            [
                "Check for a spelling mismatch first.",
                "Prefer an existing supported builtin with equivalent semantics.",
                "Only add a new builtin registration if the runtime clearly requires it.",
            ];
            constraints=[
                "Do not change unrelated equations.",
                "Keep the patch minimal.",
            ],
            recheck=["runtime_validation"],
        ),
        docs_ref="rules/ode/builtin-functions",
    )
    vals = map(arg -> _eval_ode_node(arg, u, p, t), node.args)
    return f(vals...)
end

function _eval_ode_node(node::ODEIfElse, u, p, t)
    if _eval_ode_node(node.cond, u, p, t)
        return _eval_ode_node(node.on_true, u, p, t)
    end
    return _eval_ode_node(node.on_false, u, p, t)
end

function _compile_ode_bytecode(node::AbstractODEProgramNode)
    code = AbstractODEOpcode[]
    _emit_ode_bytecode!(code, node)
    return code
end

function _emit_ode_bytecode!(code::Vector{AbstractODEOpcode}, node::ODELiteral)
    if node.value isa Bool
        push!(code, ODEPushBool(node.value))
    elseif node.value isa Number
        push!(code, ODEPushLiteral(Float64(node.value)))
    else
        throw_diagnostic(
            E_ODE_UNSUPPORTED_LITERAL;
            phase="semantic_validation",
            human_message="ODE 字面量类型暂不支持",
            human_summary="当前 ODE 字面量类型不支持: $(typeof(node.value))",
            entity=Dict("kind" => "ode_literal"),
            constraint="ode_literal_type_supported",
            expected="number_or_bool_literal",
            actual=string(typeof(node.value)),
            context=Dict{String, Any}("literal_type" => string(typeof(node.value))),
            repair_hints=[
                "Use numeric or boolean literals in ODE expressions.",
                "Convert unsupported literal values into supported numeric parameters or constants.",
            ],
            ai_hint=_default_ai_hint(
                "Replace the unsupported ODE literal with a supported numeric or boolean representation.",
                string("The ODE compiler only accepts numeric and boolean literals, but received ", typeof(node.value), "."),
                [
                    "Convert the literal to a numeric or boolean form if possible.",
                    "If the value is symbolic, move it into a parameter or supported constant.",
                ];
                constraints=[
                    "Do not change unrelated equations.",
                    "Keep the patch minimal.",
                ],
                recheck=["semantic_validation"],
            ),
            docs_ref="rules/ode/literal-types",
        )
    end
    return code
end

function _emit_ode_bytecode!(code::Vector{AbstractODEOpcode}, node::ODEStateRef)
    push!(code, ODEPushState(node.index))
    return code
end

function _emit_ode_bytecode!(code::Vector{AbstractODEOpcode}, node::ODEParamRef)
    push!(code, ODEPushParam(node.name))
    return code
end

function _emit_ode_bytecode!(code::Vector{AbstractODEOpcode}, ::ODETimeRef)
    push!(code, ODEPushTime())
    return code
end

function _emit_ode_bytecode!(code::Vector{AbstractODEOpcode}, node::ODECall)
    for arg in node.args
        _emit_ode_bytecode!(code, arg)
    end
    push!(code, ODEApplyCall(node.fname, length(node.args)))
    return code
end

function _emit_ode_bytecode!(code::Vector{AbstractODEOpcode}, node::ODEIfElse)
    _emit_ode_bytecode!(code, node.cond)
    _emit_ode_bytecode!(code, node.on_true)
    _emit_ode_bytecode!(code, node.on_false)
    push!(code, ODESelect())
    return code
end

function _eval_ode_bytecode(code::Vector{AbstractODEOpcode}, stack::Vector{Any}, u, p, t)
    for op in code
        _execute_ode_opcode!(stack, op, u, p, t)
    end
    length(stack) == 1 || throw_diagnostic(
        E_ODE_STACK_DEPTH_INVALID;
        phase="runtime_validation",
        human_message="ODE bytecode 栈深异常",
        human_summary="ODE bytecode 求值后栈深不是 1，而是 $(length(stack))",
        entity=Dict("kind" => "ode_bytecode"),
        constraint="ode_bytecode_must_leave_single_result",
        expected="stack_depth_1",
        actual=string(length(stack)),
        context=Dict{String, Any}("stack_depth" => length(stack), "stack_type" => "Any"),
        repair_hints=[
            "Inspect the generated bytecode and operator arity.",
            "Ensure each ODE expression reduces to exactly one final value.",
        ],
        ai_hint=_default_ai_hint(
            "Repair the ODE bytecode generation or evaluation path so the expression leaves exactly one result on the stack.",
            string("The ODE bytecode evaluator ended with stack depth ", length(stack), " instead of 1."),
            [
                "Check whether an opcode pushes or pops the wrong number of values.",
                "Check whether the source expression compiles into a balanced bytecode sequence.",
            ];
            constraints=[
                "Do not alter unrelated runtime logic.",
                "Keep the fix local to bytecode generation or evaluation.",
            ],
            patch_scope="local",
            recheck=["runtime_validation"],
        ),
        docs_ref="rules/ode/bytecode-stack-balance",
    )
    return stack[end]
end

function _eval_ode_bytecode(code::Vector{AbstractODEOpcode}, stack::Vector{ODEValue}, u, p, t)
    for op in code
        _execute_ode_opcode!(stack, op, u, p, t)
    end
    length(stack) == 1 || throw_diagnostic(
        E_ODE_STACK_DEPTH_INVALID;
        phase="runtime_validation",
        human_message="ODE bytecode 栈深异常",
        human_summary="ODE bytecode 求值后栈深不是 1，而是 $(length(stack))",
        entity=Dict("kind" => "ode_bytecode"),
        constraint="ode_bytecode_must_leave_single_result",
        expected="stack_depth_1",
        actual=string(length(stack)),
        context=Dict{String, Any}("stack_depth" => length(stack), "stack_type" => "ODEValue"),
        repair_hints=[
            "Inspect the generated bytecode and operator arity.",
            "Ensure each ODE expression reduces to exactly one final value.",
        ],
        ai_hint=_default_ai_hint(
            "Repair the ODE bytecode generation or evaluation path so the expression leaves exactly one result on the stack.",
            string("The ODE bytecode evaluator ended with stack depth ", length(stack), " instead of 1."),
            [
                "Check whether an opcode pushes or pops the wrong number of values.",
                "Check whether the source expression compiles into a balanced bytecode sequence.",
            ];
            constraints=[
                "Do not alter unrelated runtime logic.",
                "Keep the fix local to bytecode generation or evaluation.",
            ],
            patch_scope="local",
            recheck=["runtime_validation"],
        ),
        docs_ref="rules/ode/bytecode-stack-balance",
    )
    return stack[end]
end

_ode_num(x::Real) = ODEValue(Float64(x), false, false)
_ode_bool(x::Bool) = ODEValue(0.0, x, true)

function _odevalue_number(v::ODEValue)
    v.is_bool && throw_diagnostic(
        E_ODE_EXPECTED_NUMBER;
        phase="runtime_validation",
        human_message="ODE 求值类型不匹配",
        human_summary="期望数值结果，实际得到 Bool",
        entity=Dict("kind" => "ode_value"),
        constraint="ode_numeric_context_requires_number",
        expected="number",
        actual="bool",
        repair_hints=[
            "Ensure arithmetic operators only consume numeric expressions.",
            "If the condition is intentional, use it only in boolean contexts such as if-else or logical operators.",
        ],
        ai_hint=_default_ai_hint(
            "Repair the ODE expression so a numeric context does not receive a boolean value.",
            "A boolean value reached a numeric evaluation context.",
            [
                "Trace the expression that produced the boolean value.",
                "Keep the boolean expression in conditional logic only.",
                "Replace it with a numeric expression if arithmetic semantics are intended.",
            ];
            constraints=[
                "Do not change unrelated equations.",
                "Keep the patch minimal.",
            ],
            recheck=["runtime_validation"],
        ),
        docs_ref="rules/ode/numeric-context-requires-number",
    )
    return v.num
end

function _odevalue_bool(v::ODEValue)
    v.is_bool || throw_diagnostic(
        E_ODE_EXPECTED_BOOL;
        phase="runtime_validation",
        human_message="ODE 求值类型不匹配",
        human_summary="期望 Bool 结果，实际得到数值",
        entity=Dict("kind" => "ode_value"),
        constraint="ode_boolean_context_requires_bool",
        expected="bool",
        actual="number",
        repair_hints=[
            "Ensure condition positions only consume boolean expressions.",
            "Use an explicit comparison if the intent is to derive a boolean from a numeric value.",
        ],
        ai_hint=_default_ai_hint(
            "Repair the ODE expression so a boolean context does not receive a numeric value.",
            "A numeric value reached a boolean evaluation context.",
            [
                "Trace the expression that produced the numeric value.",
                "If a condition was intended, add an explicit comparison.",
                "Preserve arithmetic subexpressions unless a comparison is required.",
            ];
            constraints=[
                "Do not change unrelated equations.",
                "Keep the patch minimal.",
            ],
            recheck=["runtime_validation"],
        ),
        docs_ref="rules/ode/boolean-context-requires-bool",
    )
    return v.flag
end

function _execute_ode_opcode!(stack::Vector{ODEValue}, op::ODEPushLiteral, u, p, t)
    push!(stack, _ode_num(op.value))
    return nothing
end

function _execute_ode_opcode!(stack::Vector{ODEValue}, op::ODEPushBool, u, p, t)
    push!(stack, _ode_bool(op.value))
    return nothing
end

function _execute_ode_opcode!(stack::Vector{ODEValue}, op::ODEPushState, u, p, t)
    push!(stack, _ode_num(u[op.index]))
    return nothing
end

function _execute_ode_opcode!(stack::Vector{ODEValue}, op::ODEPushParam, u, p, t)
    push!(stack, _ode_num(p[op.name]))
    return nothing
end

function _execute_ode_opcode!(stack::Vector{ODEValue}, ::ODEPushTime, u, p, t)
    push!(stack, _ode_num(t))
    return nothing
end

function _execute_ode_opcode!(stack::Vector{ODEValue}, op::ODEApplyCall, u, p, t)
    n = op.argc
    length(stack) >= n || throw_diagnostic(
        E_ODE_STACK_UNDERFLOW;
        phase="runtime_validation",
        human_message="ODE bytecode 栈下溢",
        human_summary="执行 ODE 调用 $(op.fname) 时栈元素不足",
        entity=Dict("kind" => "ode_opcode", "opcode" => "apply_call", "function" => string(op.fname)),
        constraint="ode_opcode_requires_sufficient_stack_values",
        expected=string("at_least_", n, "_stack_values"),
        actual=string(length(stack)),
        context=Dict{String, Any}("function" => string(op.fname), "argc" => n, "stack_depth" => length(stack)),
        repair_hints=[
            "Inspect whether earlier bytecode generation omitted required operands.",
            "Ensure the operator arity matches the compiled source expression.",
        ],
        ai_hint=_default_ai_hint(
            "Repair the ODE bytecode so each call opcode receives the required number of operands.",
            string("The call opcode for ", op.fname, " expected ", n, " operands but only found ", length(stack), " on the stack."),
            [
                "Check the source expression and compiled bytecode sequence for missing pushes.",
                "Check whether the call arity is correct for the selected builtin.",
            ];
            constraints=[
                "Do not alter unrelated runtime logic.",
                "Keep the fix local.",
            ],
            patch_scope="local",
            recheck=["runtime_validation"],
        ),
        docs_ref="rules/ode/bytecode-stack-balance",
    )
    args = ntuple(i -> stack[end - n + i], n)
    resize!(stack, length(stack) - n)
    push!(stack, _apply_ode_call(op.fname, args))
    return nothing
end

function _execute_ode_opcode!(stack::Vector{ODEValue}, ::ODESelect, u, p, t)
    length(stack) >= 3 || throw_diagnostic(
        E_ODE_STACK_UNDERFLOW;
        phase="runtime_validation",
        human_message="ODE bytecode 栈下溢",
        human_summary="执行 ODE 条件选择时栈元素不足",
        entity=Dict("kind" => "ode_opcode", "opcode" => "select"),
        constraint="ode_select_requires_condition_and_branches",
        expected="at_least_3_stack_values",
        actual=string(length(stack)),
        context=Dict{String, Any}("opcode" => "select", "stack_depth" => length(stack)),
        repair_hints=[
            "Inspect whether the condition and both branches were emitted before the select opcode.",
            "Ensure the source if-else expression compiles into a complete conditional sequence.",
        ],
        ai_hint=_default_ai_hint(
            "Repair the ODE bytecode so the select opcode receives condition, true branch, and false branch values.",
            string("The select opcode expected at least 3 stack values but only found ", length(stack), "."),
            [
                "Check the compiled if-else sequence for missing operands.",
                "Ensure condition, true branch, and false branch are all emitted before select.",
            ];
            constraints=[
                "Do not alter unrelated runtime logic.",
                "Keep the fix local.",
            ],
            patch_scope="local",
            recheck=["runtime_validation"],
        ),
        docs_ref="rules/ode/bytecode-stack-balance",
    )
    on_false = pop!(stack)
    on_true = pop!(stack)
    cond = pop!(stack)
    push!(stack, _odevalue_bool(cond) ? on_true : on_false)
    return nothing
end

function _apply_ode_call(fname::Symbol, args)
    if fname == :+
        if length(args) == 1
            return _ode_num(+_odevalue_number(args[1]))
        elseif length(args) == 2
            return _ode_num(_odevalue_number(args[1]) + _odevalue_number(args[2]))
        end
    elseif fname == :-
        if length(args) == 1
            return _ode_num(-_odevalue_number(args[1]))
        elseif length(args) == 2
            return _ode_num(_odevalue_number(args[1]) - _odevalue_number(args[2]))
        end
    elseif fname == :*
        return _ode_num(_odevalue_number(args[1]) * _odevalue_number(args[2]))
    elseif fname == :/
        return _ode_num(_odevalue_number(args[1]) / _odevalue_number(args[2]))
    elseif fname == :^
        return _ode_num(_odevalue_number(args[1]) ^ _odevalue_number(args[2]))
    elseif fname == :sin
        return _ode_num(sin(_odevalue_number(args[1])))
    elseif fname == :cos
        return _ode_num(cos(_odevalue_number(args[1])))
    elseif fname == :tan
        return _ode_num(tan(_odevalue_number(args[1])))
    elseif fname == :exp
        return _ode_num(exp(_odevalue_number(args[1])))
    elseif fname == :log
        return _ode_num(log(_odevalue_number(args[1])))
    elseif fname == :log10
        return _ode_num(log10(_odevalue_number(args[1])))
    elseif fname == :sqrt
        return _ode_num(sqrt(_odevalue_number(args[1])))
    elseif fname == :abs
        return _ode_num(abs(_odevalue_number(args[1])))
    elseif fname == :sign
        return _ode_num(sign(_odevalue_number(args[1])))
    elseif fname == :floor
        return _ode_num(floor(_odevalue_number(args[1])))
    elseif fname == :ceil
        return _ode_num(ceil(_odevalue_number(args[1])))
    elseif fname == :round
        return _ode_num(round(_odevalue_number(args[1])))
    elseif fname == Symbol("==")
        return _ode_bool(_odevalue_number(args[1]) == _odevalue_number(args[2]))
    elseif fname == Symbol("!=")
        return _ode_bool(_odevalue_number(args[1]) != _odevalue_number(args[2]))
    elseif fname == Symbol("<")
        return _ode_bool(_odevalue_number(args[1]) < _odevalue_number(args[2]))
    elseif fname == Symbol(">")
        return _ode_bool(_odevalue_number(args[1]) > _odevalue_number(args[2]))
    elseif fname == Symbol("<=")
        return _ode_bool(_odevalue_number(args[1]) <= _odevalue_number(args[2]))
    elseif fname == Symbol(">=")
        return _ode_bool(_odevalue_number(args[1]) >= _odevalue_number(args[2]))
    elseif fname == :!
        return _ode_bool(!_odevalue_bool(args[1]))
    end
    throw_diagnostic(
        E_ODE_UNKNOWN_FUNCTION;
        phase="runtime_validation",
        human_message="未注册或暂不支持的 ODE 内建函数",
        human_summary="无法执行 ODE 内建函数 $(fname)，参数个数为 $(length(args))",
        entity=Dict("kind" => "ode_call", "function" => string(fname)),
        constraint="ode_builtin_function_signature_supported",
        expected="supported_builtin_signature",
        actual=string(fname, "/", length(args)),
        context=Dict{String, Any}("function" => string(fname), "argc" => length(args)),
        repair_hints=[
            "Use a supported builtin function and valid argument count.",
            "If the function is intended to be supported, add runtime support for this signature.",
        ],
        ai_hint=_default_ai_hint(
            "Replace the unsupported ODE builtin call with a supported function/signature or add explicit support for it.",
            string("The runtime does not support the builtin call ", fname, " with argc=", length(args), "."),
            [
                "Check whether the function name or argument count is incorrect.",
                "Prefer an existing supported builtin with equivalent semantics.",
                "Only extend runtime support if the surrounding code clearly requires it.",
            ];
            constraints=[
                "Do not change unrelated equations.",
                "Keep the patch minimal.",
            ],
            recheck=["runtime_validation"],
        ),
        docs_ref="rules/ode/builtin-functions",
    )
end

function _ode_constant_value(sym::Symbol)
    if sym == :pi || sym == :π
        return π
    elseif sym == :ℯ
        return ℯ
    elseif sym == :Inf
        return Inf
    elseif sym == :NaN
        return NaN
    elseif sym == Symbol("true")
        return true
    elseif sym == Symbol("false")
        return false
    end
    throw_diagnostic(
        E_ODE_UNKNOWN_CONSTANT;
        phase="semantic_validation",
        human_message="未识别的 ODE 常量符号",
        human_summary="无法识别 ODE 常量符号: $sym",
        entity=Dict("kind" => "ode_constant", "symbol" => string(sym)),
        constraint="ode_constant_symbol_must_be_supported",
        expected="supported_ode_constant",
        actual=string(sym),
        context=Dict{String, Any}("symbol" => string(sym)),
        repair_hints=[
            "Use a supported built-in constant such as pi, Inf, NaN, true, or false.",
            "If the value is model-specific, declare it as a parameter instead of an implicit constant.",
        ],
        ai_hint=_default_ai_hint(
            "Replace the unknown ODE constant symbol with a supported constant or a declared parameter.",
            string("The ODE compiler does not recognize the constant symbol ", sym, "."),
            [
                "Check for a spelling mismatch first.",
                "Prefer a supported built-in constant if one matches the intended meaning.",
                "Otherwise convert the constant into an explicit parameter reference.",
            ];
            constraints=[
                "Do not alter unrelated equations.",
                "Keep the patch minimal.",
            ],
            recheck=["semantic_validation"],
        ),
        docs_ref="rules/ode/constants",
    )
end
