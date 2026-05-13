# ============================================================
# Solver 协议 — 定义求解器接口和注册机制
#
# 所有求解器通过 register_solver!() 注册，
# 通过 select_solver() 自动选型或用户手动指定。
# ============================================================

# ============================================================
# 1. 仿真结果类型
# ============================================================

"""
    SimResult

仿真结果。t 为时间点，u[i][t] 为第 i 个状态的时间序列。
states 提供状态名称映射。
"""
struct SimResult
    t::Vector{Float64}
    u::Matrix{Float64}       # u[state_idx, time_idx]
    states::Vector{Symbol}
    params::Dict{Symbol, Any}
    success::Bool
    raw::Dict{Symbol, Vector}  # 非数值状态的完整轨迹
end

# 向后兼容构造函数
SimResult(t, u, states, params, success) =
    SimResult(t, u, states, params, success, Dict{Symbol, Vector}())

Base.length(r::SimResult) = length(r.t)
function Base.getindex(r::SimResult, s::Symbol, idx::Int)
    if haskey(r.raw, s)
        return r.raw[s][idx]
    end
    return r.u[findfirst(==(s), r.states), idx]
end
function Base.getindex(r::SimResult, s::Symbol)
    if haskey(r.raw, s)
        return r.raw[s]
    end
    return r.u[findfirst(==(s), r.states), :]
end

# ============================================================
# 2. Solver 接口定义
# ============================================================

"""
    AbstractSolver

所有求解器的抽象基类。
子类需实现 `solve(solver, model; kwargs...)` 和可选的 `can_solve(solver, model)`。
"""
abstract type AbstractSolver end

"""
    can_solve(solver, model) -> Bool

检查求解器是否能处理该模型。
默认返回 true，子类可重写。
"""
can_solve(::AbstractSolver, ::Any) = true

"""
    solve(solver, model; kwargs...) -> SimResult

求解模型。关键字参数：
- `u0` — 初始条件 Dict{Symbol, Float64}
- `tspan` — 时间区间 Tuple{Float64, Float64}，默认 (0.0, 10.0)
- `params` — 参数覆盖 Dict{Symbol, Any}
"""
function solve end

# ============================================================
# 3. Solver 注册与发现
# ============================================================

"""
    _SOLVER_REGISTRY

求解器注册表。存储 {名称 => 求解器类型} 的映射。
"""
const _SOLVER_REGISTRY = Dict{Symbol, DataType}()

"""
    _SOLVER_ORDER

按注册顺序保存求解器名称，用于 select_solver 的优先级判断。
"""
const _SOLVER_ORDER = Symbol[]

"""
    register_solver!([name::Symbol,] solver_type::Type{<:AbstractSolver})

注册一个求解器类型到 AnySim 的求解器注册表中。
如果未提供 name，使用类型的默认名称（nameof）。
"""
function register_solver!(name::Symbol, solver_type::DataType)
    _SOLVER_REGISTRY[name] = solver_type
    if !(name in _SOLVER_ORDER)
        push!(_SOLVER_ORDER, name)
    end
    return nothing
end

function register_solver!(solver_type::DataType)
    return register_solver!(nameof(solver_type), solver_type)
end

function _solver_type_or_throw(prefer)
    T = get(_SOLVER_REGISTRY, prefer, nothing)
    T !== nothing && return T

    avail = join(available_solvers(), ", ")
    throw_diagnostic(
        E_SOLVER_UNKNOWN;
        phase=PHASE_RESOLVE,
        human_message="未知求解器",
        human_summary=string("求解器 :", prefer, " 未注册，可用求解器: ", avail),
        entity=Dict("kind" => "solver", "name" => string(prefer)),
        constraint="solver_name_must_be_registered",
        expected="registered_solver_name",
        actual=string(prefer),
        context=Dict{String, Any}("available_solvers" => string.(available_solvers())),
        repair_hints=[
            "Choose one of the registered solver names.",
            "If a new solver is intended, register it before selection.",
        ],
        ai_hint=_default_ai_hint(
            "Replace the unknown solver name with a registered solver or register the intended solver.",
            string("The solver name ", prefer, " is not registered."),
            [
                "Check for a spelling mismatch first.",
                "If the intended solver already exists, use its registered name.",
                "Only add a new solver registration if the surrounding code clearly requires it.",
            ];
            constraints=[
                "Do not change unrelated solver logic.",
                "Keep the patch minimal.",
            ],
            recheck=["resolve"],
        ),
        docs_ref="rules/solvers/registered-solver-name",
    )
end

"""
    select_solver(model; prefer=nothing) -> AbstractSolver
    select_solver(; prefer) -> AbstractSolver

从已注册的求解器中自动选择能处理该模型的求解器。
如不传 model 只传 prefer，直接返回对应求解器的默认实例。
"""
function select_solver(model; prefer=nothing)
    if prefer !== nothing
        T = _solver_type_or_throw(prefer)
        return T()
    end
    for name in _SOLVER_ORDER
        T = _SOLVER_REGISTRY[name]
        if can_solve(T(), model)
            return T()
        end
    end
    avail = join(available_solvers(), ", ")
    throw_diagnostic(
        E_SOLVER_NOT_FOUND;
        phase=PHASE_RESOLVE,
        human_message="没有可用求解器",
        human_summary=string("当前模型没有匹配的已注册求解器，可用求解器: ", avail),
        entity=Dict("kind" => "solver_selection"),
        constraint="at_least_one_solver_must_accept_model",
        expected="compatible_solver",
        actual="no_matching_solver",
        context=Dict{String, Any}(
            "available_solvers" => string.(available_solvers()),
            "model_type" => string(typeof(model)),
        ),
        repair_hints=[
            "Try an explicit compatible solver if one exists.",
            "If the model uses a new paradigm, add or register a solver that supports it.",
        ],
        ai_hint=_default_ai_hint(
            "Select or register a solver that can handle the current model.",
            "No registered solver reported compatibility with the current model.",
            [
                "Inspect the model kind and the solver capability checks.",
                "Prefer selecting an existing compatible solver first.",
                "Only add a new solver implementation if no compatible solver exists.",
            ];
            constraints=[
                "Do not remove existing solver registrations.",
                "Preserve current model semantics.",
            ],
            recheck=["resolve"],
        ),
        docs_ref="rules/solvers/model-must-have-compatible-solver",
    )
end

# 便捷方法：无需 model，直接按名称返回 solver
function select_solver(; prefer)
    T = _solver_type_or_throw(prefer)
    return T()
end

"""
    available_solvers() -> Vector{Symbol}

返回所有已注册求解器的名称列表。
"""
available_solvers() = collect(keys(_SOLVER_REGISTRY))

# ============================================================
# 4. 便捷接口
# ============================================================

"""
    solve(model; kwargs...) -> SimResult

便捷方法：自动选择求解器并求解。
等价于 `solve(select_solver(model), model; kwargs...)`。
"""
function solve(model; kwargs...)
    solver = select_solver(model)
    return solve(solver, model; kwargs...)
end
