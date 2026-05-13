
# ============================================================
# simulation_bridge.jl — 计划→仿真注入管道 (Simulation Bridge)
#
# 核心职责：
#   把 ExecutionPlan 转换成 DEVS 仿真模型（ComposeDef）
#   仿真层不关心计划由哪个运筹学模型产生，只关心执行计划
#
# 这是方法论中 C层(计划生成) → D层(仿真执行) 的桥梁
# ============================================================

import ..AnySim: EntityDef, Relation, Behavioral, Connection, ComposeDef
import ..AnySim: Port, Parameter
import ..DEVS: DEVSMessage, INFINITY, PhaseInit

# ============================================================
# 1. 扰动注入 — 从 DisruptionSpec 计算仿真扰动因子
# ============================================================

"""
    compute_disturbance_factors(world::ShippingWorld)

从世界模型的扰动定义中，计算航行和港口的扰动因子。
如果多个扰动影响同一对象，取最大影响。
"""
function compute_disturbance_factors(world::ShippingWorld)
    sailing_factor = 1.0
    port_factor = 1.0

    for dis in world.disruptions
        sailing_factor = max(sailing_factor, dis.sailing_delay_factor)
        port_factor = max(port_factor, dis.port_delay_factor)
    end

    # 也考虑 disruption_level 的简单缩放
    if world.disruption_level > 0
        sailing_factor = max(sailing_factor, 1.0 + world.disruption_level * 0.2)
        port_factor = max(port_factor, 1.0 + world.disruption_level * 0.1)
    end

    return (sailing_factor=sailing_factor, port_factor=port_factor)
end

"""
    compute_port_disturbance_factors(world::ShippingWorld)

按港口分别计算扰动因子，支持更精细的扰动建模。
"""
function compute_port_disturbance_factors(world::ShippingWorld)
    port_factors = Dict{String, Float64}()
    for (port_code, _) in world.ports
        factor = 1.0
        for dis in world.disruptions
            if port_code in dis.affected_ports || isempty(dis.affected_ports)
                factor = max(factor, dis.port_delay_factor)
            end
        end
        if world.disruption_level > 0
            factor = max(factor, 1.0 + world.disruption_level * 0.1)
        end
        port_factors[port_code] = factor
    end
    return port_factors
end

# ============================================================
# 2. ExecutionPlan → DEVS 仿真模型
# ============================================================

"""
    inject_plan(world::ShippingWorld, plan::ExecutionPlan) -> ComposeDef

将 ExecutionPlan 注入仿真，构建完整的 DEVS 仿真模型。
这是方法论的核心桥梁：决策模型产出计划 → 仿真执行计划。

流程：
1. 从 planned_rotations 创建 VesselSailing 原子模型
2. 从世界模型中的港口创建 PortTerminal 原子模型
3. 从 planned_assignments 创建需求生成器（带路径约束）
4. 连接所有组件
5. 注入扰动参数
"""
function inject_plan(world::ShippingWorld, plan::ExecutionPlan)::ComposeDef
    # 计算扰动因子
    disturbance = compute_disturbance_factors(world)
    port_disturbance = compute_port_disturbance_factors(world)

    # --- 1. 收集所有涉及的港口 ---
    involved_ports = Set{String}()
    for rotation in plan.planned_rotations
        for call in rotation.planned_calls
            push!(involved_ports, call.port_code)
        end
    end
    # 也从需求中收集
    for assignment in plan.planned_assignments
        push!(involved_ports, assignment.origin)
        push!(involved_ports, assignment.destination)
    end

    # 收集每条服务的靠港序列（用于港口的货物匹配）
    service_port_codes = Dict{String, Vector{String}}()
    for rotation in plan.planned_rotations
        service_id = rotation.service_id
        if !haskey(service_port_codes, service_id)
            service_port_codes[service_id] = String[]
        end
        for call in rotation.planned_calls
            port = call.port_code
            if !(port in service_port_codes[service_id])
                push!(service_port_codes[service_id], port)
            end
        end
    end

    # --- 2. 创建港口模型 ---
    port_entities = EntityDef[]
    for port_code in sort(collect(involved_ports))
        port_name = Symbol("Port_", replace(port_code, "-" => "_"))
        route_ports = String[]
        for (sid, ports) in service_port_codes
            append!(route_ports, ports)
        end
        unique!(route_ports)

        port_entity = create_port(port_name, port_code, route_ports)
        push!(port_entities, port_entity)
    end

    # --- 3. 创建船舶模型 ---
    vessel_entities = EntityDef[]
    for rotation in plan.planned_rotations
        # 从旋转计划构建 RouteSchedule
        port_calls = PortCall[]
        for call in rotation.planned_calls
            push!(port_calls, PortCall(
                call.port_code,
                call.port_order,
                call.planned_eta_day - rotation.start_delay,  # 相对时间
                call.planned_etd_day - rotation.start_delay,
            ))
        end

        # 计算总天数
        total_days = isempty(port_calls) ? 0.0 :
                     maximum(pc -> pc.etd_day !== nothing ? pc.etd_day : pc.eta_day, port_calls)

        route = RouteSchedule(
            rotation.service_id,
            port_calls,
            total_days,
        )

        # 获取该船的扰动因子
        vessel_sailing_factor = disturbance.sailing_factor
        vessel_port_factor = get(port_disturbance, rotation.vessel_name, disturbance.port_factor)

        vessel_name = Symbol("Vessel_", replace(rotation.vessel_name, "-" => "_"))
        vessel_entity = create_vessel(
            vessel_name, rotation.vessel_name, route, rotation.start_delay;
            disturbance_factor=vessel_sailing_factor,
            port_disturbance_factor=vessel_port_factor,
        )
        push!(vessel_entities, vessel_entity)
    end

    # --- 4. 创建需求生成器 ---
    demand_entities = EntityDef[]

    # 按服务分组需求分配
    service_demands = Dict{String, Vector{PlannedDemandAssignment}}()
    for assignment in plan.planned_assignments
        # 确定需求属于哪个服务（取第一条腿的服务）
        if !isempty(assignment.path_legs)
            sid = assignment.path_legs[1].service_id
        else
            sid = "unassigned"
        end
        if !haskey(service_demands, sid)
            service_demands[sid] = PlannedDemandAssignment[]
        end
        push!(service_demands[sid], assignment)
    end

    # 为每个服务创建需求生成器
    for (sid, assignments) in service_demands
        sid == "unassigned" && continue

        # 将 PlannedDemandAssignment 转换为 ODDemand
        od_list = ODDemand[]
        for a in assignments
            # 计算运输时间
            transit = isempty(a.path_legs) ? 30 :
                      maximum(leg -> leg.arrival_day, a.path_legs) -
                      minimum(leg -> leg.depart_day, a.path_legs)
            transit = max(transit, 1)

            push!(od_list, ODDemand(
                a.origin, a.destination,
                a.quantity / max(world.time.horizon_cycles, 1),  # 周均量
                1000.0,  # 默认单位收入
                Float64(transit),
            ))
        end

        if !isempty(od_list)
            demand_name = Symbol("Demand_", replace(sid, "-" => "_"))
            demand_entity = create_demand_generator(
                demand_name, od_list, sid;
                seed=42, max_weeks=world.time.horizon_cycles,
            )
            push!(demand_entities, demand_entity)
        end
    end

    # --- 5. 组合所有实体 ---
    all_entities = vcat(port_entities, vessel_entities, demand_entities)

    # --- 6. 建立连接 ---
    connections = Connection[]

    # 需求生成器 → 港口（货物输入）
    for demand_entity in demand_entities
        demand_id = string(demand_entity.name)
        # 从需求名提取服务ID
        sid = replace(replace(demand_id, "Demand_" => ""), "_" => "-")
        # 尝试匹配原始服务ID
        matched_sid = sid
        for existing_sid in keys(service_port_codes)
            if startswith(existing_sid, sid) || startswith(sid, existing_sid)
                matched_sid = existing_sid
                break
            end
        end

        for port_entity in port_entities
            # 获取港口代码
            port_code_param = nothing
            for p in port_entity.parameters
                if p.name == :port_code
                    port_code_param = p.default
                    break
                end
            end
            port_code_param === nothing && continue

            # 检查该港口是否在此服务的靠港序列中
            if haskey(service_port_codes, matched_sid) &&
               port_code_param in service_port_codes[matched_sid]
                push!(connections, Connection(
                    (demand_entity.name, :o_demand),
                    (port_entity.name, :i_cargo_in),
                ))
            end
        end
    end

    # 船舶 → 港口（到港/离港事件、卸货）
    for vessel_entity in vessel_entities
        for port_entity in port_entities
            # 获取船舶路线中的港口
            route_data_param = nothing
            for p in vessel_entity.parameters
                if p.name == :route_data
                    route_data_param = p.default
                    break
                end
            end
            route_data_param === nothing && continue

            route_ports = [pc.port_code for pc in route_data_param.port_calls]

            port_code_param = nothing
            for p in port_entity.parameters
                if p.name == :port_code
                    port_code_param = p.default
                    break
                end
            end
            port_code_param === nothing && continue

            if port_code_param in route_ports
                # 到港事件
                push!(connections, Connection(
                    (vessel_entity.name, :o_arrival),
                    (port_entity.name, :i_arrival),
                ))
                # 离港事件
                push!(connections, Connection(
                    (vessel_entity.name, :o_departure),
                    (port_entity.name, :i_departure),
                ))
                # 卸货
                push!(connections, Connection(
                    (vessel_entity.name, :o_cargo_discharge),
                    (port_entity.name, :i_cargo_discharge),
                ))
            end
        end
    end

    # 港口 → 船舶（装船货物）
    for port_entity in port_entities
        for vessel_entity in vessel_entities
            route_data_param = nothing
            for p in vessel_entity.parameters
                if p.name == :route_data
                    route_data_param = p.default
                    break
                end
            end
            route_data_param === nothing && continue

            route_ports = [pc.port_code for pc in route_data_param.port_calls]

            port_code_param = nothing
            for p in port_entity.parameters
                if p.name == :port_code
                    port_code_param = p.default
                    break
                end
            end
            port_code_param === nothing && continue

            if port_code_param in route_ports
                push!(connections, Connection(
                    (port_entity.name, :o_cargo_out),
                    (vessel_entity.name, :i_cargo),
                ))
            end
        end
    end

    # --- 7. 构建 ComposeDef ---
    model_name = Symbol("Planned_", replace(plan.meta.preset_id, "-" => "_"))

    return ComposeDef(model_name, all_entities, Relation[], connections, [])
end

# ============================================================
# 3. 便捷函数 — 从世界+模型直接到仿真结果
# ============================================================

"""
    run_simulation(world::ShippingWorld, plan::ExecutionPlan;
                   max_time, max_steps) -> SimResult

将 ExecutionPlan 注入仿真并运行，返回仿真结果。
这是最常用的端到端函数。
"""
function run_simulation(world::ShippingWorld, plan::ExecutionPlan;
                        max_time::Float64=200.0,
                        max_steps::Int=10000)
    # 构建仿真模型
    model = inject_plan(world, plan)

    # 运行仿真
    ctx = init_devs_context(model)
    history = collect_shipping_history(ctx; max_time=max_time, max_steps=max_steps)

    # 收集结果
    events = VesselEvent[]
    stats = PortStats[]
    cargo = CargoBatch[]
    for snapshot in history
        append!(events, snapshot.events)
        append!(stats, snapshot.stats)
        append!(cargo, snapshot.cargo)
    end

    return (history=history, events=events, stats=stats, cargo=cargo, model=model)
end

"""
    run_decision_and_simulate(model::AbstractDecisionModel, world::ShippingWorld;
                              scenario_id, max_time, max_steps)

完整的决策→仿真管道：求解决策模型 → 注入仿真 → 运行 → 收集结果
"""
function run_decision_and_simulate(model::AbstractDecisionModel, world::ShippingWorld;
                                   scenario_id::String="baseline",
                                   max_time::Float64=200.0,
                                   max_steps::Int=10000)
    # Step 1: 求解决策模型
    plan = solve_decision(model, world; scenario_id=scenario_id)

    # Step 2: 注入仿真并运行
    sim_result = run_simulation(world, plan; max_time=max_time, max_steps=max_steps)

    return (plan=plan, sim_result=sim_result)
end
