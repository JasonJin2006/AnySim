# ============================================================
# DEODESolver — DifferentialEquations.jl 桥接求解器
# ============================================================

"""
    DEODESolver <: AbstractSolver

DifferentialEquations.jl 桥接求解器。
需要安装 `OrdinaryDiffEq` 包。

使用专业 ODE 求解器替代内置 RK4：
- 自适应步长（更精确）
- 刚性求解器（适用于刚性系统）
- 事件处理

# 关键字参数
- `alg=:Tsit5` — 求解器算法，可选 `:Tsit5`, `:RK4`, `:Vern7`, `:Rosenbrock23` 等
- `reltol=1e-6` — 相对容差
- `abstol=1e-8` — 绝对容差
"""
struct DEODESolver <: AbstractSolver
    alg::Symbol
    reltol::Float64
    abstol::Float64
end
DEODESolver(; alg=:Tsit5, reltol=1e-6, abstol=1e-8) = DEODESolver(alg, reltol, abstol)

function can_solve(::DEODESolver, model)
    try
        if model isa EntityDef
            return any(r -> _is_explicit_ode(r.expr), model.relations)
        elseif model isa ComposeDef
            return any(r -> _is_explicit_ode(r.expr), traverse_relations(model))
        end
    catch
        return false
    end
end

"""
    solve(solver::DEODESolver, model; kwargs...) -> SimResult

使用 DifferentialEquations.jl 求解 ODE 模型。

# 关键字参数
- `u0` — 初始条件 Dict
- `tspan` — 时间区间
- `params` — 参数覆盖
"""
function solve(solver::DEODESolver, model; u0=Dict{Symbol,Float64}(),
               tspan=(0.0, 10.0), params=Dict{Symbol,Any}())

    # 检查依赖
    _has_diffeq() || error(
        "OrdinaryDiffEq 未安装。请运行: using Pkg; Pkg.add(\"OrdinaryDiffEq\")")

    compiled = compile_ode_ir(model)
    compiled === nothing && error("模型不含显式 ODE 方程")

    states = compiled.state_names
    param_syms = compiled.param_names

    # 初始化参数和初始条件
    p = _extract_params(model, param_syms, params)
    u0_vec = _init_u0(model, states, u0, params)

    # 创建 ODEProblem
    prob = _make_ode_problem(compiled, u0_vec, tspan, p)

    # 映射算法名到 OrdinaryDiffEq 类型
    alg = _resolve_alg(solver.alg)

    # 求解
    sol = _solve_diffeq(prob, alg, solver.reltol, solver.abstol)

    # 转换为 SimResult
    n_states = length(states)
    us = Matrix{Float64}(undef, n_states, length(sol.t))
    for i in 1:n_states
        us[i, :] = [sol.u[j][i] for j in 1:length(sol.t)]
    end

    return SimResult(Vector{Float64}(sol.t), us, states, p, true)
end

# ============================================================
# OrdinaryDiffEq 集成工具
# ============================================================

"""
    _has_diffeq() -> Bool

检查 OrdinaryDiffEq 是否已安装。
"""
function _has_diffeq()
    try
        Pkg = Base.require(Base.PkgId(Base.UUID("44cfe95a-1eb2-52ea-b672-e2afdf69b78f"), "Pkg"))
        deps = Pkg.project().dependencies
        return haskey(deps, "OrdinaryDiffEq") || haskey(deps, "DifferentialEquations")
    catch
        return false
    end
end

"""
    _resolve_alg(name::Symbol) -> Symbol

将算法名称 Symbol 映射为 OrdinaryDiffEq 算法类型名。
"""
function _resolve_alg(name::Symbol)
    if name == :Tsit5
        return :Tsit5
    elseif name == :RK4
        return :RK4
    elseif name == :Vern7
        return :Vern7
    elseif name == :Rosenbrock23
        return :Rosenbrock23
    elseif name == :DP5
        return :DP5
    elseif name == :AutoVern7
        return :AutoVern7
    else
        @warn "未知算法 :$(name)，使用默认 :Tsit5"
        return :Tsit5
    end
end

"""
    _make_ode_problem(compiled, u0, tspan, p) -> ODEProblem

创建 ODEProblem。使用 Base.invokelatest 处理 world age 问题。
"""
function _make_ode_problem(compiled::CompiledODEModel, u0, tspan, p)
    OrdinaryDiffEq = Base.require(Base.PkgId(
        Base.UUID("1dea7af3-3e70-54e6-95c3-0bf5283fa5ed"), "OrdinaryDiffEq"))
    _wrapped_f!(du, u, p_, t) = ode_rhs!(compiled, du, u, p_, t)
    return Base.invokelatest(OrdinaryDiffEq.ODEProblem, _wrapped_f!, u0, tspan, p)
end

"""
    _solve_diffeq(prob, alg_name, reltol, abstol) -> ODESolution

使用 OrdinaryDiffEq 求解。
"""
function _solve_diffeq(prob, alg_name, reltol, abstol)
    OrdinaryDiffEq = Base.require(Base.PkgId(
        Base.UUID("1dea7af3-3e70-54e6-95c3-0bf5283fa5ed"), "OrdinaryDiffEq"))

    # 用 invokelatest 解决 world age 问题（OrdinaryDiffEq 预编译在老 world）
    alg = if alg_name == :Tsit5
        Base.invokelatest(OrdinaryDiffEq.Tsit5)
    elseif alg_name == :RK4
        Base.invokelatest(OrdinaryDiffEq.RK4)
    elseif alg_name == :Vern7
        Base.invokelatest(OrdinaryDiffEq.Vern7)
    elseif alg_name == :Rosenbrock23
        Base.invokelatest(OrdinaryDiffEq.Rosenbrock23)
    elseif alg_name == :DP5
        Base.invokelatest(OrdinaryDiffEq.DP5)
    else
        Base.invokelatest(OrdinaryDiffEq.Tsit5)
    end

    return Base.invokelatest(OrdinaryDiffEq.solve, prob, alg, reltol=reltol, abstol=abstol)
end

# 自注册
register_solver!(DEODESolver)
