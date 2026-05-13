# ============================================================
# DESolver — 离散事件 / Agent-Based 求解器
#
# 统一的离散仿真引擎，通过事件队列同时支持 ABM 和 DES：
#
# ABM 模式（:discrete_time）
#   为每个有 Behavioral relation 的 entity 生成周期性 tick 事件。
#   每 step 执行所有 agent 的行为规则。等价于离散时间 ABM。
#
# DES 模式（:event_driven）
#   只处理 event queue 中的调度事件，无自动 tick。
#   时间跳到下一个事件时间。等价于经典 DEVS。
#
# 统一原理：
#   事件队列是唯一的时间推进机制。
#   ABM = 自调度 tick 事件（DES 的一个特例）。
#
# 设计约束：
#   - 时间是 DESolver 的内部概念，不泄漏到 Core
#   - 遵循 Solver 协议，与 ODESolver/MTKODESolver 平级
#   - Behavioral/Event RelationKind 已定义在 Core 层
# ============================================================

# ============================================================
# 1. 事件类型
# ============================================================

"""
    SimEvent

离散事件的基本单元。
- time: 事件触发时间
- entity: 所属 entity 名称
- relation: 所属 relation 名称
- action: 事件动作 (state, t, dt) -> nothing
- priority: 优先级（同时间点时，低 priority 先执行，默认 0）
"""
struct SimEvent
    time::Float64
    entity::Symbol
    relation::Symbol
    action::Function
    priority::Int
end

# 向后兼容：不传 priority 时默认为 0
SimEvent(time, entity, relation, action) = SimEvent(time, entity, relation, action, 0)

# ============================================================
# 2. DESolver 结构
# ============================================================

struct DESolver <: AbstractSolver
    mode::Symbol         # :discrete_time 或 :event_driven
    dt::Float64          # ABM 模式的时间步长
    max_steps::Int       # 最大步数
    record_every::Int    # 每 N 步记录一次状态
    max_zeno::Int        # Zeno 检测阈值（同时间点连续事件数上限）
end

DESolver(; mode=:discrete_time, dt=0.1, max_steps=1000, record_every=1, max_zeno=100) =
    DESolver(mode, dt, max_steps, record_every, max_zeno)

function can_solve(::DESolver, model::ComposeDef)
    any(r -> r.kind in (Behavioral, Event), traverse_relations(model))
end

function can_solve(::DESolver, model::EntityDef)
    any(r -> r.kind in (Behavioral, Event), model.relations)
end

# ============================================================
# 3. Behavior 编译 → 委托给 compile_relation()
#
# Behavioral/Event relation 的表达式编译由
# compile.jl 中的 compile_relation() 统一负责。
# DESolver 仅负责将其注册到事件队列中。
#
# 详见 solver_utils.jl:
#   compile_relation(rel::Relation, params::Vector{Parameter}) -> Function
# ============================================================

# ============================================================
# 4. 状态初始化
# ============================================================

function _init_agent_states(model::ComposeDef)
    states = Dict{Symbol, Dict{Symbol, Any}}()
    for e in traverse_entities(model)
        agent_state = Dict{Symbol, Any}()
        for p in e.parameters
            agent_state[p.name] = p.default !== nothing ? p.default : 0.0
        end
        # 注入 entity 名称，供 send!() 在行为代码中使用
        agent_state[:_my_name] = e.name
        # 初始化 mailbox（如果 agent 没有声明 _mailbox 参数）
        if !haskey(agent_state, :_mailbox)
            agent_state[:_mailbox] = Message[]
        end
        states[e.name] = agent_state
    end
    return states
end

# ============================================================
# 5. 事件队列管理
# ============================================================

function _schedule_tick!(events::Vector{SimEvent}, t::Float64, dt::Float64,
                         behavior_fns::Dict{Tuple{Symbol,Symbol}, Function})
    for ((ent_name, rel_name), action) in behavior_fns
        push!(events, SimEvent(t + dt, ent_name, rel_name, action))
    end
    sort!(events; by=e -> e.time)
    return nothing
end

function _pop_events!(events::Vector{SimEvent}, t::Float64)
    # 返回所有在时间 t 的事件
    current = SimEvent[]
    remaining = SimEvent[]
    for e in events
        if e.time <= t
            push!(current, e)
        else
            push!(remaining, e)
        end
    end
    # 按优先级排序（最低 priority 优先，同 priority 按 entity/relation 保确定性）
    sort!(current; by=e -> (e.time, e.priority, e.entity, e.relation))
    empty!(events)
    append!(events, remaining)
    return current
end

# ============================================================
# 6. SimResult 构建
# ============================================================

function _build_sim_result(times::Vector{Float64}, records::Vector{Dict{Symbol,Dict{Symbol,Any}}},
                           all_state_names::Vector{Symbol})
    n_steps = length(times)
    n_states = length(all_state_names)
    us = zeros(Float64, n_states, n_steps)
    raw = Dict{Symbol, Vector}()

    for step in 1:n_steps
        rec = records[step]
        for (i, sname) in enumerate(all_state_names)
            # 解析 flat name: entity_var
            # 例如 :wolf_energy → entity=:wolf, var=:energy
            parts = split(string(sname), "_"; limit=2)
            if length(parts) == 2
                ent = Symbol(parts[1])
                var = Symbol(parts[2])
                if haskey(rec, ent) && haskey(rec[ent], var)
                    val = rec[ent][var]
                    if val isa Number
                        us[i, step] = Float64(val)
                    else
                        # 非数值状态存入 raw（首次遇到时初始化数组）
                        if !haskey(raw, sname)
                            raw[sname] = Vector{Any}(undef, n_steps)
                        end
                        raw[sname][step] = val
                    end
                end
            end
        end
    end

    return SimResult(times, us, all_state_names, Dict{Symbol,Any}(), true, raw)
end

# ============================================================
# 7. 主求解方法
# ============================================================

function solve(solver::DESolver, model::ComposeDef;
               u0=Dict{Symbol,Float64}(), tspan=(0.0, 100.0),
               params=Dict{Symbol,Any}())

    # ---- Phase 1: 初始化 agent 状态 ----
    agent_states = _init_agent_states(model)
    _init_msg_ctx!(agent_states)

    # ---- Phase 2: 编译 behavior ----
    # 收集所有 (entity, relation) → 编译后的 behavior 函数
    behavior_fns = Dict{Tuple{Symbol,Symbol}, Function}()
    event_relations = Tuple{Symbol,Symbol}[]

    for e in traverse_entities(model)
        for r in e.relations
            if r.kind == Behavioral
                fn = compile_relation(r, e.parameters)
                behavior_fns[(e.name, r.name)] = fn
            elseif r.kind == Event
                push!(event_relations, (e.name, r.name))
            end
        end
    end

    # ---- Phase 3: 初始化事件队列 ----
    events = SimEvent[]

    if solver.mode == :discrete_time
        # ABM 模式：在 t=0 立即调度所有 behavior 作为 tick 事件
        t_start = tspan[1]
        for ((ent_name, rel_name), action) in behavior_fns
            push!(events, SimEvent(t_start, ent_name, rel_name, action))
        end
    end

    # ---- Phase 4: 仿真循环 ----
    t = tspan[1]
    t_end = tspan[2]
    step = 0
    max_steps = solver.mode == :discrete_time ? solver.max_steps : typemax(Int)
    zeno_count = 0
    last_event_time = -Inf

    # 记录
    times = Float64[t]
    records = [deepcopy(agent_states)]
    all_state_names = Symbol[]

    # 构建 flat state names: entity_var
    for e in traverse_entities(model)
        for p in e.parameters
            push!(all_state_names, Symbol(string(e.name, "_", p.name)))
        end
    end

    while t < t_end && step < max_steps
        step += 1

        if solver.mode == :discrete_time
            # ABM 模式：推进一个时间步
            t += solver.dt
            if t > t_end
                t = t_end
            end

            # 执行所有在该时间点的事件的 action
            # 注: 使用 Base.invokelatest 解决 eval() 的 world-age 问题
            current_events = _pop_events!(events, t)
            for ev in current_events
                try
                    Base.invokelatest(ev.action, agent_states[ev.entity], t, solver.dt)
                catch e
                    @warn "[DESolver] behavior 执行失败: $(ev.entity).$(ev.relation): $e"
                end
            end

            # 所有 behavior 重新调度到下一个时间步
            _schedule_tick!(events, t, solver.dt, behavior_fns)

        elseif solver.mode == :event_driven
            # DES 模式：跳到下一个事件时间
            isempty(events) && break  # 无事件，结束
            ev = popfirst!(events)
            t = ev.time
            if t > t_end
                t = t_end
                break
            end

            # Zeno 检测：同一时间点连续事件过多
            if t ≈ last_event_time
                zeno_count += 1
                if zeno_count >= solver.max_zeno
                    @warn "[DESolver] 可能的 Zeno 行为: $zeno_count 个连续事件在 t=$t"
                    break
                end
            else
                zeno_count = 0
            end
            last_event_time = t

            try
                Base.invokelatest(ev.action, agent_states[ev.entity], t, 0.0)
            catch e
                @warn "[DESolver] event 执行失败: $(ev.entity).$(ev.relation): $e"
            end
        end

        # 记录（按 record_every 间隔）
        if step % solver.record_every == 0
            push!(times, t)
            push!(records, deepcopy(agent_states))
        end
    end

    # ---- Phase 5: 构建结果 ----
    result = _build_sim_result(times, records, all_state_names)
    _clear_msg_ctx!()
    return result
end

# EntityDef → 包装为 ComposeDef 后委派
function solve(solver::DESolver, model::EntityDef; kwargs...)
    comp = ComposeDef(model.name, [model], Relation[], Connection[], [])
    return solve(solver, comp; kwargs...)
end

# 自注册
register_solver!(DESolver)
