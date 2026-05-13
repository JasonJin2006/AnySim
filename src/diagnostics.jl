# ============================================================
# diagnostics.jl — AnySim 结构化诊断核心
#
# 目标：
#   1. 让验证/报错不再只是 String[]
#   2. 为 AI 修复链路提供英文 machine-facing 字段
#   3. 保持现有 validate(model) -> Vector{String} 兼容
# ============================================================

"""
    DiagnosticSpan

可选的源码定位信息。当前核心模型对象大多不携带源码位置，
因此第一版允许所有字段为空，后续可由 DSL parser / workbench 注入。
"""
Base.@kwdef struct DiagnosticSpan
    file::Union{Nothing, String} = nothing
    start_line::Union{Nothing, Int} = nothing
    start_col::Union{Nothing, Int} = nothing
    end_line::Union{Nothing, Int} = nothing
    end_col::Union{Nothing, Int} = nothing
end

"""
    Diagnostic

AnySim 的结构化诊断对象。

设计规则：
- `human_*` 可本地化
- machine-facing 字段必须使用英文
"""
Base.@kwdef struct Diagnostic
    id::String
    code::String
    severity::String = "error"
    phase::String = "semantic_validation"
    human_message::String
    human_summary::String = ""
    span::DiagnosticSpan = DiagnosticSpan()
    entity::Dict{String, String} = Dict{String, String}()
    constraint::String
    expected::Union{Nothing, String} = nothing
    actual::Union{Nothing, String} = nothing
    context::Dict{String, Any} = Dict{String, Any}()
    repair_hints::Vector{String} = String[]
    ai_hint::Dict{String, Any} = Dict{String, Any}()
    docs_ref::Union{Nothing, String} = nothing
end

"""
    DiagnosticError

用于在仍需中断控制流的场景里抛出结构化 diagnostics。
第一版先支持单个 diagnostic；后续可扩展为批量 diagnostics。
"""
struct DiagnosticError <: Exception
    diagnostic::Diagnostic
end

Base.showerror(io::IO, err::DiagnosticError) = print(io, diagnostic_message(err.diagnostic))

const DIAG_ERROR = "error"
const DIAG_WARNING = "warning"
const DIAG_INFO = "info"

const PHASE_RESOLVE = "resolve"
const PHASE_SEMANTIC_VALIDATION = "semantic_validation"
const PHASE_TOPOLOGY_VALIDATION = "topology_validation"

const E_NAME_DUPLICATE_PORT = "E_NAME_DUPLICATE_PORT"
const E_NAME_DUPLICATE_RELATION = "E_NAME_DUPLICATE_RELATION"
const E_NAME_DUPLICATE_PARAMETER = "E_NAME_DUPLICATE_PARAMETER"
const E_NAME_DUPLICATE_ENTITY = "E_NAME_DUPLICATE_ENTITY"
const E_TOPOLOGY_UNKNOWN_ENTITY = "E_TOPOLOGY_UNKNOWN_ENTITY"
const E_PORT_INVALID_REFERENCE = "E_PORT_INVALID_REFERENCE"
const E_TOPOLOGY_INVALID_DIRECTION = "E_TOPOLOGY_INVALID_DIRECTION"
const E_SYNTAX_UNSUPPORTED_PORT = "E_SYNTAX_UNSUPPORTED_PORT"
const E_SYNTAX_UNSUPPORTED_PARAM = "E_SYNTAX_UNSUPPORTED_PARAM"
const E_SYNTAX_MISSING_RELATION_NAME = "E_SYNTAX_MISSING_RELATION_NAME"
const E_SYNTAX_UNSUPPORTED_ENTITY = "E_SYNTAX_UNSUPPORTED_ENTITY"
const E_SYNTAX_UNSUPPORTED_CONNECT = "E_SYNTAX_UNSUPPORTED_CONNECT"
const E_SOLVER_UNKNOWN = "E_SOLVER_UNKNOWN"
const E_SOLVER_NOT_FOUND = "E_SOLVER_NOT_FOUND"
const E_ODE_UNSUPPORTED_EXPRESSION = "E_ODE_UNSUPPORTED_EXPRESSION"
const E_ODE_UNKNOWN_FUNCTION = "E_ODE_UNKNOWN_FUNCTION"
const E_ODE_UNSUPPORTED_LITERAL = "E_ODE_UNSUPPORTED_LITERAL"
const E_ODE_STACK_DEPTH_INVALID = "E_ODE_STACK_DEPTH_INVALID"
const E_ODE_EXPECTED_NUMBER = "E_ODE_EXPECTED_NUMBER"
const E_ODE_EXPECTED_BOOL = "E_ODE_EXPECTED_BOOL"
const E_ODE_STACK_UNDERFLOW = "E_ODE_STACK_UNDERFLOW"
const E_ODE_UNKNOWN_CONSTANT = "E_ODE_UNKNOWN_CONSTANT"
const E_PARAM_MISSING_DEFAULT = "E_PARAM_MISSING_DEFAULT"
const E_STATE_MISSING_INITIAL_VALUE = "E_STATE_MISSING_INITIAL_VALUE"
const E_RUNTIME_SEND_OUTSIDE_SIMULATION = "E_RUNTIME_SEND_OUTSIDE_SIMULATION"
const E_RUNTIME_UNKNOWN_AGENT = "E_RUNTIME_UNKNOWN_AGENT"
const E_RUNTIME_UNHANDLED = "E_RUNTIME_UNHANDLED"

"""
    diagnostic_message(diag::Diagnostic) -> String

向后兼容的人类可读消息。
"""
function diagnostic_message(diag::Diagnostic)
    isempty(diag.human_summary) && return diag.human_message
    return string(diag.human_message, " — ", diag.human_summary)
end

diagnostic_messages(diags::Vector{Diagnostic}) = String[diagnostic_message(diag) for diag in diags]

"""
    diagnostic_to_dict(diag::Diagnostic) -> Dict{String, Any}

将诊断对象转为便于 JSON 序列化的纯 Dict。
"""
function diagnostic_to_dict(diag::Diagnostic)
    span = Dict{String, Any}(
        "file" => diag.span.file,
        "start_line" => diag.span.start_line,
        "start_col" => diag.span.start_col,
        "end_line" => diag.span.end_line,
        "end_col" => diag.span.end_col,
    )

    return Dict{String, Any}(
        "id" => diag.id,
        "code" => diag.code,
        "severity" => diag.severity,
        "phase" => diag.phase,
        "human_message" => diag.human_message,
        "human_summary" => diag.human_summary,
        "span" => span,
        "entity" => Dict{String, String}(diag.entity),
        "constraint" => diag.constraint,
        "expected" => diag.expected,
        "actual" => diag.actual,
        "context" => Dict{String, Any}(diag.context),
        "repair_hints" => copy(diag.repair_hints),
        "ai_hint" => Dict{String, Any}(diag.ai_hint),
        "docs_ref" => diag.docs_ref,
    )
end

function _default_ai_hint(goal::String, diagnosis::String, strategy::Vector{String};
                          constraints=String[], patch_scope="minimal", recheck=String[])
    return Dict{String, Any}(
        "goal" => goal,
        "diagnosis" => diagnosis,
        "strategy" => strategy,
        "constraints" => collect(constraints),
        "patch_scope" => patch_scope,
        "recheck" => collect(recheck),
    )
end

function _make_diag(code::String;
                    severity::String=DIAG_ERROR,
                    phase::String=PHASE_SEMANTIC_VALIDATION,
                    human_message::String,
                    human_summary::String="",
                    entity::Dict{String, String}=Dict{String, String}(),
                    constraint::String,
                    expected::Union{Nothing, String}=nothing,
                    actual::Union{Nothing, String}=nothing,
                    context::Dict{String, Any}=Dict{String, Any}(),
                    repair_hints::Vector{String}=String[],
                    ai_hint::Dict{String, Any}=Dict{String, Any}(),
                    docs_ref::Union{Nothing, String}=nothing)
    return Diagnostic(
        id=code,
        code=code,
        severity=severity,
        phase=phase,
        human_message=human_message,
        human_summary=human_summary,
        entity=entity,
        constraint=constraint,
        expected=expected,
        actual=actual,
        context=context,
        repair_hints=repair_hints,
        ai_hint=ai_hint,
        docs_ref=docs_ref,
    )
end

throw_diagnostic(diag::Diagnostic) = throw(DiagnosticError(diag))

function diagnostic_from_exception(err::Exception;
                                   code::String=E_RUNTIME_UNHANDLED,
                                   phase::String="simulation_runtime",
                                   human_message::String="未处理异常",
                                   human_summary::String=string(err),
                                   entity::Dict{String, String}=Dict{String, String}(),
                                   docs_ref::Union{Nothing, String}="rules/runtime/unhandled-exception")
    return _make_diag(
        code;
        phase=phase,
        human_message=human_message,
        human_summary=human_summary,
        entity=entity,
        constraint="runtime_exception_captured",
        expected="handled_execution",
        actual=string(typeof(err)),
        context=Dict{String, Any}(
            "exception_type" => string(typeof(err)),
            "exception_message" => string(err),
        ),
        repair_hints=[
            "Inspect the failing execution path and convert recurring failures into structured diagnostics where possible.",
            "Preserve unrelated runtime behavior while fixing the root cause.",
        ],
        ai_hint=_default_ai_hint(
            "Repair the failing execution path while preserving intended model behavior.",
            string("An unhandled exception of type ", typeof(err), " was captured: ", err),
            [
                "Check the immediate failing call site first.",
                "If this is a recurring user-facing failure, convert it into a dedicated structured diagnostic.",
                "Keep the fix local to the failing path unless a deeper invariant is broken.",
            ];
            constraints=[
                "Do not change unrelated runtime behavior.",
                "Keep the patch minimal.",
            ],
            patch_scope="local",
            recheck=["simulation_runtime"],
        ),
        docs_ref=docs_ref,
    )
end

function throw_diagnostic(code::String;
                          severity::String=DIAG_ERROR,
                          phase::String=PHASE_SEMANTIC_VALIDATION,
                          human_message::String,
                          human_summary::String="",
                          entity::Dict{String, String}=Dict{String, String}(),
                          constraint::String,
                          expected::Union{Nothing, String}=nothing,
                          actual::Union{Nothing, String}=nothing,
                          context::Dict{String, Any}=Dict{String, Any}(),
                          repair_hints::Vector{String}=String[],
                          ai_hint::Dict{String, Any}=Dict{String, Any}(),
                          docs_ref::Union{Nothing, String}=nothing)
    throw_diagnostic(_make_diag(
        code;
        severity=severity,
        phase=phase,
        human_message=human_message,
        human_summary=human_summary,
        entity=entity,
        constraint=constraint,
        expected=expected,
        actual=actual,
        context=context,
        repair_hints=repair_hints,
        ai_hint=ai_hint,
        docs_ref=docs_ref,
    ))
end
