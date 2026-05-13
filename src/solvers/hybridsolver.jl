# ============================================================
# HybridSolver — 混合连续-离散求解器
#
# 处理同时包含连续 ODE 方程（Equation）和离散行为
# （Behavioral/Event）的模型。通过分步推进实现：
#
#   1. ODE 步进：用 ODESolver 推进一个 cross_step
#   2. 事件检查：检查离散事件是否在该步内触发
#   3. 事件处理：执行事件动作（可能修改连续状态）
#   4. 状态同步：更新 ODE 初始条件后继续
#
# 当前状态：⚠️ 框架已搭建，完全实现需要 ODE 求解器支持
# step-by-step 模式（见 TODO 标记）。
#
# 设计约束：
#   - 混合求解发生在求解器层，Core 层无需感知
#   - ODE 步进器和离散事件引擎保持独立
#   - 状态映射（ODE 向量 ↔ agent 字典）是 HybridSolver 的责任
# ============================================================

# ============================================================
# 1. HybridSolver 结构
# ============================================================

"""
    HybridSolver

混合连续-离散求解器。

字段：
- de_solver: 离散事件求解器（DESolver 实例）
- cross_step: 混合步长，每这么多时间检查一次离散事件
- max_consecutive_events: Zeno 保护
- delegation_threshold: 委托给纯 ODE/DE 求解器的模型大小阈值

当前局限：
- TODO: ODE 求解器需要支持 step-by-step 模式（当前 solve() 是一次性算到底）
- TODO: 状态映射（连续 u 向量 ↔ agent Dict）需要实现
- TODO: 事件触发的 ODE 重新初始化需要解决
- TODO: 结构变更（spawn/destroy）需要 Simulation Loop 支持
"""
struct HybridSolver <: AbstractSolver
    de_solver::DESolver
    cross_step::Float64
    max_consecutive_events::Int
end

# 默认构造：使用默认 DESolver，1% 的仿真总时间为混合步长
HybridSolver(; de_solver=DESolver(), cross_step=0.01,
               max_consecutive_events=100) =
    HybridSolver(de_solver, cross_step, max_consecutive_events)

# ============================================================
# 2. 模型分类与适配
# ============================================================

"""
    classify_paradigm(model)

将模型分类为纯连续、纯离散、或混合。
返回 :continuous, :discrete, :hybrid 或 :static。
"""
function classify_paradigm(model)
    has_ode = false
    has_de = false
    for r in traverse_relations(model)
        if r.kind == Equation
            # 检查是否含 der() 算子
            _has_ode_op(r.expr) && (has_ode = true)
        elseif r.kind in (Behavioral, Event)
            has_de = true
        end
    end
    if has_ode && has_de
        return :hybrid
    elseif has_ode
        return :continuous
    elseif has_de
        return :discrete
    else
        return :static
    end
end

function _has_ode_op(ex)
    ex isa Expr || return false
    # 检查顶层是否为 der(x) 调用
    if ex.head == :call && length(ex.args) >= 2 && ex.args[1] == :der
        return true
    end
    # 递归检查子表达式
    for arg in ex.args
        _has_ode_op(arg) && return true
    end
    return false
end

function can_solve(::HybridSolver, model)
    paradigm = classify_paradigm(model)
    return paradigm in (:hybrid, :continuous, :discrete)
end

# ============================================================
# 3. ODE ↔ Agent 状态映射
#
# 混合仿真需要在 ODE 求解器的连续状态向量（u）
# 和 DESolver 的 agent 字典之间同步状态。
# 当前仅定义了接口，完整实现待 step-by-step ODE 支持就绪。
# ============================================================

"""
    _ode_to_agent(u, states, ode_state_names, agent_states) -> nothing

将 ODE 解向量 u 中的值同步到 agent 状态字典。
"""
function _ode_to_agent(u, states, ode_state_names, agent_states)
    for (i, sname) in enumerate(ode_state_names)
        # 解析 entity_var 格式
        parts = split(string(sname), "_"; limit=2)
        length(parts) == 2 || continue
        ent, var = Symbol(parts[1]), Symbol(parts[2])
        if haskey(agent_states, ent)
            agent_states[ent][var] = u[i]
        end
    end
    return nothing
end

"""
    _agent_to_ode(agent_states, u, states, ode_state_names) -> nothing

将 agent 状态字典中的值同步回 ODE 解向量 u。
"""
function _agent_to_ode(agent_states, u, states, ode_state_names)
    for (i, sname) in enumerate(ode_state_names)
        parts = split(string(sname), "_"; limit=2)
        length(parts) == 2 || continue
        ent, var = Symbol(parts[1]), Symbol(parts[2])
        if haskey(agent_states, ent) && haskey(agent_states[ent], var)
            u[i] = Float64(agent_states[ent][var])
        end
    end
    return nothing
end

# ============================================================
# 4. 主求解方法
#
# ⚠️ 当前实现：
#   - 能将纯 ODE 或纯 DE 模型委托给对应求解器
#   - 混合模型的帧同步尚未实——见 solve 中的 TODO
# ============================================================

function solve(solver::HybridSolver, model;
               u0=Dict{Symbol,Float64}(), tspan=(0.0, 10.0),
               params=Dict{Symbol,Any}())

    paradigm = classify_paradigm(model)

    # --- 纯连续 → 委托给 ODESolver ---
    if paradigm == :continuous
        ode_solver = select_solver(model; prefer=:ODESolver)
        return solve(ode_solver, model; u0=u0, tspan=tspan, params=params)
    end

    # --- 纯离散 → 委托给 DESolver ---
    if paradigm == :discrete
        return solve(solver.de_solver, model; u0=u0, tspan=tspan, params=params)
    end

    # --- 混合模型 ---
    # TODO: 完整实现需要：
    #   1. ODESolver 支持 step-by-step 模式（或使用 solve_until_event 接口）
    #   2. 状态同步协议（u 向量 ↔ agent 字典）
    #   3. 事件触发的 ODE 重新初始化
    #   4. 结构变更（spawn/destroy）的 Simulation Loop
    #
    # 当前返回一个标记性结果，标明混合能力已就绪但未实现
    error("""
    HybridSolver: 混合模型求解尚未完全实现。
    框架已就绪，需要以下组件才能运行：
    1. ODESolver 的 step-by-step 模式
    2. 连续↔离散状态同步
    3. 事件触发的 ODE 重新初始化
    4. Simulation Loop 支持

    当前范式分类: $paradigm
    模型包含 ODE 方程和离散行为（Behavioral/Event）。
    建议用纯 ODE 或纯离散模式分别验证各部分。
    """)
end

# 自注册
register_solver!(HybridSolver)
