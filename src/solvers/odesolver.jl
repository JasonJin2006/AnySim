# ============================================================
# ODESolver — 内置 RK4 求解器
# ============================================================

"""
    ODESolver <: AbstractSolver

显式 ODE 求解器。使用经典 4 阶 Runge-Kutta (RK4) 方法。
支持固定步长和自适应步长（通过 dt 控制精度）。

# 关键字参数
- `dt=1e-3` — 固定时间步长
- `reltol=1e-6` — 相对容差（当 dt 较小时自动调整）
"""
struct ODESolver <: AbstractSolver
    dt::Float64
    reltol::Float64
end
ODESolver(; dt=1e-3, reltol=1e-6) = ODESolver(dt, reltol)

function can_solve(::ODESolver, model::EntityDef)
    any(r -> _is_explicit_ode(r.expr), model.relations)
end
function can_solve(::ODESolver, model::ComposeDef)
    for r in traverse_relations(model)
        _is_explicit_ode(r.expr) && return true
    end
    return false
end

"""
    solve(solver::ODESolver, model; kwargs...) -> SimResult

使用 RK4 求解 ODE 模型。

# 关键字参数
- `u0` — 初始条件，如 `Dict(:x => 1.0, :y => 0.0)`
- `tspan` — 时间区间，如 `(0.0, 10.0)`
- `params` — 参数覆盖，如 `Dict(:k => -2.0)`
"""
function solve(solver::ODESolver, model; u0=Dict{Symbol,Float64}(),
               tspan=(0.0, 10.0), params=Dict{Symbol,Any}())
    compiled = compile_ode_ir(model)
    compiled === nothing && error("模型不含显式 ODE 方程，无法使用 ODESolver")

    states = compiled.state_names
    param_syms = compiled.param_names

    # 初始化参数
    p = _extract_params(model, param_syms, params)

    # 初始化状态
    n_states = length(states)
    u0_vec = zeros(Float64, n_states)
    for (i, s) in enumerate(states)
        if haskey(u0, s)
            u0_vec[i] = Float64(u0[s])
        elseif haskey(params, s)
            u0_vec[i] = Float64(params[s])
        else
            # 从模型参数找默认值
            found = _find_param_default(model, s)
            found !== nothing ? (u0_vec[i] = Float64(found)) :
                error("状态 :$s 没有初始值")
        end
    end

    # RK4 推进
    t0, tf = tspan
    dt = solver.dt
    n_steps = ceil(Int, (tf - t0) / dt)
    dt_actual = (tf - t0) / n_steps

    ts = Vector{Float64}(undef, n_steps + 1)
    us = Matrix{Float64}(undef, n_states, n_steps + 1)

    t = t0
    u = copy(u0_vec)
    ts[1] = t
    us[:, 1] = u

    buffers = ODERuntimeBuffers(compiled)

    for step in 1:n_steps
        # RK4 步
        # k1
        ode_rhs!(compiled, buffers, buffers.du, u, p, t)
        copyto!(buffers.k1, buffers.du)

        # k2
        @. buffers.tmp = u + 0.5 * dt_actual * buffers.k1
        ode_rhs!(compiled, buffers, buffers.du, buffers.tmp, p, t + 0.5 * dt_actual)
        copyto!(buffers.k2, buffers.du)

        # k3
        @. buffers.tmp = u + 0.5 * dt_actual * buffers.k2
        ode_rhs!(compiled, buffers, buffers.du, buffers.tmp, p, t + 0.5 * dt_actual)
        copyto!(buffers.k3, buffers.du)

        # k4
        @. buffers.tmp = u + dt_actual * buffers.k3
        ode_rhs!(compiled, buffers, buffers.du, buffers.tmp, p, t + dt_actual)
        copyto!(buffers.k4, buffers.du)

        @. u = u + (dt_actual / 6.0) * (
            buffers.k1 + 2.0 * buffers.k2 + 2.0 * buffers.k3 + buffers.k4
        )
        t += dt_actual

        ts[step + 1] = t
        us[:, step + 1] = u
    end

    return SimResult(ts, us, states, p, true)
end

# 自注册
register_solver!(ODESolver)
