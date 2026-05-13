
# ============================================================
# decision_interface.jl — 决策模型抽象接口 (Decision Modeling Layer)
#
# 核心思想：
#   1. 所有运筹学决策模型实现同一个抽象接口
#   2. 接口输入：ShippingWorld（统一世界模型）
#   3. 接口输出：ExecutionPlan（统一执行计划）
#   4. 不同模型从世界模型中投影自己需要的部分
#   5. 仿真层不关心背后用的是哪种模型，只关心执行计划
# ============================================================

import Dates

# ============================================================
# 1. 抽象决策模型接口
# ============================================================

"""
    AbstractDecisionModel — 所有运筹学决策模型的抽象基类

子类必须实现：
- `model_name`：模型名称
- `model_version`：版本号
- `required_projection`：从世界模型中投影哪些部分
- `solve_decision`：求解决策问题，返回 ExecutionPlan
- `decision_variables`：该模型决定哪些内生变量
- `model_capabilities`：模型能力标签
"""
abstract type AbstractDecisionModel end

# ---- 必须实现的接口函数 ----

"""模型名称"""
function model_name(::AbstractDecisionModel)::String
    error("model_name not implemented")
end

"""模型版本"""
function model_version(::AbstractDecisionModel)::String
    error("model_version not implemented")
end

"""模型能力标签，描述该模型支持哪些决策维度"""
function model_capabilities(::AbstractDecisionModel)::Vector{Symbol}
    error("model_capabilities not implemented")
end

"""该模型决定的内生变量列表"""
function decision_variables(::AbstractDecisionModel)::Vector{Symbol}
    error("decision_variables not implemented")
end

"""从世界模型中投影该模型需要的子集"""
function required_projection(model::AbstractDecisionModel, world::ShippingWorld)::WorldProjection
    error("required_projection not implemented")
end

"""求解决策问题，返回 ExecutionPlan"""
function solve_decision(model::AbstractDecisionModel, world::ShippingWorld;
                        scenario_id::String="baseline",
                        kwargs...)::ExecutionPlan
    error("solve_decision not implemented")
end

# ---- 可选的接口函数（有默认实现）----

"""模型的简短描述"""
function model_description(model::AbstractDecisionModel)::String
    return "$(model_name(model)) v$(model_version(model))"
end

"""该模型是否支持某个能力"""
function has_capability(model::AbstractDecisionModel, cap::Symbol)::Bool
    return cap in model_capabilities(model)
end

"""求解前的验证：世界模型是否包含该模型需要的所有数据"""
function validate_world(model::AbstractDecisionModel, world::ShippingWorld)::Vector{String}
    errors = String[]
    proj = required_projection(model, world)

    # 检查是否有服务
    if isempty(proj.included_service_ids)
        push!(errors, "No services in world projection")
    end

    # 检查是否有需求
    if isempty(proj.included_demand_ids)
        push!(errors, "No demands in world projection")
    end

    # 检查是否有船型
    if isempty(proj.included_fleet_ids)
        push!(errors, "No fleet types in world projection")
    end

    return errors
end

# ============================================================
# 2. 模型能力标签定义
# ============================================================

"""
模型能力标签的完整列表，用于描述不同决策模型支持的功能
"""
const CAP_SERVICE_ACTIVATION  = :service_activation   # 服务是否开通
const CAP_FLEET_DEPLOYMENT    = :fleet_deployment     # 配什么船型
const CAP_VESSEL_COUNT        = :vessel_count         # 投几艘船
const CAP_DEMAND_ACCEPTANCE   = :demand_acceptance    # 哪些货接不接
const CAP_CARGO_ROUTING       = :cargo_routing        # 货怎么走
const CAP_TRANSSHIPMENT       = :transshipment        # 是否允许中转
const CAP_TIME_WINDOWS        = :time_windows         # 是否考虑时间窗
const CAP_CAPACITY            = :capacity             # 是否考虑容量约束
const CAP_PORT_CONGESTION     = :port_congestion      # 是否考虑港口拥堵
const CAP_DISRUPTION          = :disruption           # 是否考虑扰动
const CAP_RECOVERY            = :recovery             # 是否考虑恢复策略
const CAP_SPEED_ADJUSTMENT    = :speed_adjustment     # 是否允许调速
const CAP_SKIP_PORT           = :skip_port            # 是否允许跳港
const CAP_ROBUST              = :robust               # 是否为鲁棒优化
const CAP_STOCHASTIC          = :stochastic           # 是否为随机规划
const CAP_HEURISTIC           = :heuristic            # 是否为启发式
const CAP_EXACT               = :exact                # 是否为精确方法

# ============================================================
# 3. 决策变量标签定义
# ============================================================

"""
决策变量标签，描述该模型决定哪些内生变量
"""
const DEC_SERVICE_ACTIVE      = :service_active       # 服务是否开通
const DEC_FLEET_TYPE          = :fleet_type           # 配什么船型
const DEC_VESSEL_COUNT        = :vessel_count         # 投几艘船
const DEC_DEMAND_ACCEPTED     = :demand_accepted      # 需求是否接受
const DEC_CARGO_FLOW          = :cargo_flow           # 货流路径
const DEC_TRANSSHIPMENT_PORT  = :transshipment_port   # 中转港口选择
const DEC_RECOVERY_ACTION     = :recovery_action      # 恢复策略动作
const DEC_SPEED_LEVEL         = :speed_level          # 航速等级
const DEC_SKIP_DECISION       = :skip_decision        # 跳港决策

# ============================================================
# 4. 具体决策模型实现 — 时空网络 MILP
# ============================================================

"""
    TimeSpaceMILPModel — 时空网络混合整数线性规划模型

包装现有 optimization.jl 中的 MILP 管道：
  build_time_space_network → build_model_data → build_milp_spec → solve → extract result → build plan

这是最完整的模型，支持服务选择、船型分配、货流路径、中转等。
"""
struct TimeSpaceMILPModel <: AbstractDecisionModel
    # 模型配置
    allow_transshipment::Bool
    consider_time_windows::Bool
    consider_capacity::Bool
    allow_service_activation::Bool
    # 求解器配置
    solver_time_limit_seconds::Float64
    solver_gap_tolerance::Float64
    # 成本配置（覆盖世界模型默认值）
    cost_override::Union{Nothing, ArcCostConfig}
end

TimeSpaceMILPModel(;
    allow_transshipment::Bool=true,
    consider_time_windows::Bool=true,
    consider_capacity::Bool=true,
    allow_service_activation::Bool=true,
    solver_time_limit_seconds::Float64=300.0,
    solver_gap_tolerance::Float64=0.01,
    cost_override::Union{Nothing, ArcCostConfig}=nothing
) = TimeSpaceMILPModel(allow_transshipment, consider_time_windows,
                        consider_capacity, allow_service_activation,
                        solver_time_limit_seconds, solver_gap_tolerance, cost_override)

function model_name(::TimeSpaceMILPModel)::String
    return "TimeSpaceMILP"
end

function model_version(::TimeSpaceMILPModel)::String
    return "1.0.0"
end

function model_capabilities(m::TimeSpaceMILPModel)::Vector{Symbol}
    caps = [CAP_EXACT, CAP_CARGO_ROUTING, CAP_CAPACITY]
    if m.allow_service_activation
        push!(caps, CAP_SERVICE_ACTIVATION, CAP_FLEET_DEPLOYMENT, CAP_VESSEL_COUNT)
    end
    if m.allow_transshipment
        push!(caps, CAP_TRANSSHIPMENT)
    end
    if m.consider_time_windows
        push!(caps, CAP_TIME_WINDOWS)
    end
    if m.consider_capacity
        push!(caps, CAP_DEMAND_ACCEPTANCE)
    end
    return caps
end

function decision_variables(m::TimeSpaceMILPModel)::Vector{Symbol}
    vars = [DEC_CARGO_FLOW]
    if m.allow_service_activation
        push!(vars, DEC_SERVICE_ACTIVE, DEC_FLEET_TYPE, DEC_VESSEL_COUNT)
    end
    if m.allow_transshipment
        push!(vars, DEC_TRANSSHIPMENT_PORT)
    end
    if m.consider_capacity
        push!(vars, DEC_DEMAND_ACCEPTED)
    end
    return vars
end

function required_projection(m::TimeSpaceMILPModel, world::ShippingWorld)::WorldProjection
    return WorldProjection(world;
        include_time_windows=m.consider_time_windows,
        include_transshipment=m.allow_transshipment,
        include_capacity=m.consider_capacity,
        include_port_congestion=false,
        include_disruption=false,
        include_recovery=false,
        include_speed_adjustment=false,
        include_skip_port=false,
    )
end

function solve_decision(model::TimeSpaceMILPModel, world::ShippingWorld;
                        scenario_id::String="baseline",
                        kwargs...)::ExecutionPlan
    # 验证
    errors = validate_world(model, world)
    if !isempty(errors)
        error("World validation failed for $(model_name(model)): " * join(errors, "; "))
    end

    # 从 ShippingWorld 构建 optimization.jl 需要的中间类型
    services = ShippingService[]
    for (sid, svc_spec) in world.services
        push!(services, ShippingService(
            sid, svc_spec.service_name,
            svc_spec.cycle_days, svc_spec.frequency_days,
            svc_spec.route_total_days, svc_spec.required_vessels,
            svc_spec.allowed_fleet_types, svc_spec.is_active_candidate,
            svc_spec.port_calls,
            [ServiceLeg(sid, i, l.origin, l.destination, l.depart_day, l.arrival_day,
                        l.sailing_days, l.port_stay_days, l.is_transshipment_allowed)
             for (i, l) in enumerate(svc_spec.legs)],
        ))
    end

    fleet_types = FleetType[]
    for (fid, v_spec) in world.vessels
        push!(fleet_types, FleetType(
            fid, v_spec.fleet_name,
            v_spec.capacity_ffe, v_spec.available_units,
            v_spec.fixed_deployment_cost, v_spec.sailing_cost_per_day,
            v_spec.port_call_cost, v_spec.max_service_days,
            v_spec.speed_class,
        ))
    end

    demands = OptimizationDemand[]
    for d_spec in world.demands
        push!(demands, OptimizationDemand(
            d_spec.demand_id, d_spec.origin, d_spec.destination,
            d_spec.quantity_ffe, d_spec.revenue_per_ffe,
            d_spec.release_time, d_spec.due_time, d_spec.transit_time,
            d_spec.priority_class, d_spec.max_transshipments,
            d_spec.is_mandatory, d_spec.reject_penalty_per_ffe,
        ))
    end

    # 构建时空网络
    cost_cfg = model.cost_override !== nothing ? model.cost_override :
               ArcCostConfig(
                   sea_cost_per_day=world.cost.sea_cost_per_day,
                   wait_cost_per_day=world.cost.wait_cost_per_day,
                   trans_cost_per_day=world.cost.trans_cost_per_day,
                   port_handling_cost_per_ffe=world.cost.port_handling_cost_per_ffe,
                   late_penalty_per_ffe=world.cost.late_penalty_per_ffe_per_day,
                   reject_penalty_per_ffe=world.cost.reject_penalty_per_ffe,
               )

    scenario_cfg = ScenarioConfig(
        scenario_id=scenario_id,
        description=world.description,
        cycle_days=world.time.cycle_days,
        horizon_cycles=world.time.horizon_cycles,
        demand_periods=world.time.demand_periods,
        min_connection_time=world.time.min_connection_time,
        due_slack_days=world.time.due_slack_days,
        demand_multiplier=world.demand_multiplier,
        capacity_multiplier=world.capacity_multiplier,
        disruption_level=world.disruption_level,
    )

    network = build_time_space_network(services;
        horizon_cycles=scenario_cfg.horizon_cycles,
        cycle_days=scenario_cfg.cycle_days,
        min_connection_time=scenario_cfg.min_connection_time,
    )

    instance = build_optimization_instance(services, fleet_types, demands, network)

    # 构建 MILP
    model_data = build_model_data(instance;
        cost_config=cost_cfg,
        allow_transshipment=model.allow_transshipment,
    )

    milp_spec = build_milp_spec(instance, model_data;
        cost_config=cost_cfg,
        allow_service_activation=model.allow_service_activation,
    )

    # 求解
    artifacts = OptimizationArtifacts(
        scenario_id, instance, model_data, milp_spec,
        Dict{String, Any}(
            "model_name" => model_name(model),
            "model_version" => model_version(model),
            "capabilities" => model_capabilities(model),
        ),
    )

    exec_plan = build_execution_plan_from_artifacts(artifacts; preset_id=scenario_id)
    return exec_plan
end

# ============================================================
# 5. 具体决策模型实现 — 简化直达分配模型
# ============================================================

"""
    SimpleDirectAllocationModel — 简化直达分配模型

不考虑中转，每条需求只分配到一条直达服务上。
适用于快速计算基线方案，或作为对比基准。
"""
struct SimpleDirectAllocationModel <: AbstractDecisionModel
    consider_capacity::Bool
    consider_time_windows::Bool
end

SimpleDirectAllocationModel(;
    consider_capacity::Bool=true,
    consider_time_windows::Bool=false
) = SimpleDirectAllocationModel(consider_capacity, consider_time_windows)

function model_name(::SimpleDirectAllocationModel)::String
    return "SimpleDirectAllocation"
end

function model_version(::SimpleDirectAllocationModel)::String
    return "1.0.0"
end

function model_capabilities(m::SimpleDirectAllocationModel)::Vector{Symbol}
    caps = [CAP_HEURISTIC, CAP_CARGO_ROUTING]
    if m.consider_capacity
        push!(caps, CAP_CAPACITY, CAP_DEMAND_ACCEPTANCE)
    end
    return caps
end

function decision_variables(m::SimpleDirectAllocationModel)::Vector{Symbol}
    vars = [DEC_CARGO_FLOW, DEC_DEMAND_ACCEPTED]
    return vars
end

function required_projection(m::SimpleDirectAllocationModel, world::ShippingWorld)::WorldProjection
    return WorldProjection(world;
        include_time_windows=m.consider_time_windows,
        include_transshipment=false,
        include_capacity=m.consider_capacity,
        include_port_congestion=false,
        include_disruption=false,
        include_recovery=false,
    )
end

function solve_decision(model::SimpleDirectAllocationModel, world::ShippingWorld;
                        scenario_id::String="baseline",
                        kwargs...)::ExecutionPlan
    # 简化直达分配：每条需求分配到第一个能直达的服务
    planned_services = PlannedService[]
    planned_rotations = PlannedVesselRotation[]
    planned_assignments = PlannedDemandAssignment[]

    # 所有服务默认开通
    for (sid, svc_spec) in world.services
        # 选择第一个可用船型
        fleet_id = isempty(svc_spec.allowed_fleet_types) ?
                   first(keys(world.vessels)) :
                   first(svc_spec.allowed_fleet_types)
        vessel_count = svc_spec.required_vessels
        capacity = haskey(world.vessels, fleet_id) ?
                   world.vessels[fleet_id].capacity_ffe : 4000.0

        push!(planned_services, PlannedService(sid, fleet_id, vessel_count, true))

        # 为每艘船创建旋转计划
        for v_idx in 0:(vessel_count - 1)
            vessel_name = string(sid, "-W", lpad(string(51 + v_idx), 2, '0'))
            start_delay = Float64(v_idx * svc_spec.cycle_days)
            planned_calls = [
                PlannedCall(pc.port_code,
                            start_delay + pc.eta_day,
                            pc.etd_day !== nothing ? start_delay + pc.etd_day : start_delay + pc.eta_day,
                            pc.port_order)
                for pc in svc_spec.port_calls
            ]
            push!(planned_rotations, PlannedVesselRotation(
                vessel_name, sid, fleet_id, start_delay, planned_calls,
            ))
        end
    end

    # 为每条需求寻找直达服务
    for d_spec in world.demands
        best_service_id = ""
        best_legs = PlannedPathLeg[]

        for (sid, svc_spec) in world.services
            # 检查该服务是否包含 origin → destination 的直达路径
            port_list = [pc.port_code for pc in svc_spec.port_calls]
            orig_idx = findfirst(==(d_spec.origin), port_list)
            dest_idx = findfirst(==(d_spec.destination), port_list)

            if orig_idx !== nothing && dest_idx !== nothing && orig_idx < dest_idx
                # 找到直达路径
                best_service_id = sid
                # 构建路径腿
                for leg_idx in orig_idx:(dest_idx - 1)
                    if leg_idx <= length(svc_spec.legs)
                        leg = svc_spec.legs[leg_idx]
                        push!(best_legs, PlannedPathLeg(
                            leg_idx, sid, leg.origin, leg.destination,
                            leg.depart_day, leg.arrival_day,
                        ))
                    end
                end
                break
            end
        end

        if !isempty(best_service_id)
            push!(planned_assignments, PlannedDemandAssignment(
                d_spec.demand_id, d_spec.origin, d_spec.destination,
                d_spec.quantity_ffe, best_legs,
            ))
        end
    end

    meta = PlanMeta(
        "simple-direct", scenario_id,
        world.time.cycle_days, world.time.horizon_cycles,
        string(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")),
        0.0,  # 简化模型无目标函数值
        :heuristic,
    )

    return ExecutionPlan(meta, planned_services, planned_rotations, planned_assignments)
end

# ============================================================
# 6. 具体决策模型实现 — 启发式贪心模型
# ============================================================

"""
    GreedyHeuristicModel — 贪心启发式模型

按优先级排序需求，贪心分配到可用容量。
适用于超大规模问题的快速求解。
"""
struct GreedyHeuristicModel <: AbstractDecisionModel
    priority_order::Vector{String}  # 优先级排序: "premium" > "standard" > "economy"
    allow_transshipment::Bool
end

GreedyHeuristicModel(;
    priority_order::Vector{String}=["premium", "standard", "economy"],
    allow_transshipment::Bool=false
) = GreedyHeuristicModel(priority_order, allow_transshipment)

function model_name(::GreedyHeuristicModel)::String
    return "GreedyHeuristic"
end

function model_version(::GreedyHeuristicModel)::String
    return "1.0.0"
end

function model_capabilities(m::GreedyHeuristicModel)::Vector{Symbol}
    caps = [CAP_HEURISTIC, CAP_CARGO_ROUTING, CAP_DEMAND_ACCEPTANCE, CAP_CAPACITY]
    if m.allow_transshipment
        push!(caps, CAP_TRANSSHIPMENT)
    end
    return caps
end

function decision_variables(m::GreedyHeuristicModel)::Vector{Symbol}
    return [DEC_CARGO_FLOW, DEC_DEMAND_ACCEPTED]
end

function required_projection(m::GreedyHeuristicModel, world::ShippingWorld)::WorldProjection
    return WorldProjection(world;
        include_time_windows=false,
        include_transshipment=m.allow_transshipment,
        include_capacity=true,
        include_port_congestion=false,
        include_disruption=false,
        include_recovery=false,
    )
end

function solve_decision(model::GreedyHeuristicModel, world::ShippingWorld;
                        scenario_id::String="baseline",
                        kwargs...)::ExecutionPlan
    # 贪心分配：按优先级排序需求，逐个分配到剩余容量最大的服务
    planned_services = PlannedService[]
    planned_rotations = PlannedVesselRotation[]
    planned_assignments = PlannedDemandAssignment[]

    # 所有服务默认开通
    service_remaining_capacity = Dict{String, Float64}()
    for (sid, svc_spec) in world.services
        fleet_id = isempty(svc_spec.allowed_fleet_types) ?
                   first(keys(world.vessels)) :
                   first(svc_spec.allowed_fleet_types)
        vessel_count = svc_spec.required_vessels
        capacity = haskey(world.vessels, fleet_id) ?
                   world.vessels[fleet_id].capacity_ffe * vessel_count : 4000.0 * vessel_count

        push!(planned_services, PlannedService(sid, fleet_id, vessel_count, true))
        service_remaining_capacity[sid] = capacity

        for v_idx in 0:(vessel_count - 1)
            vessel_name = string(sid, "-W", lpad(string(51 + v_idx), 2, '0'))
            start_delay = Float64(v_idx * svc_spec.cycle_days)
            planned_calls = [
                PlannedCall(pc.port_code,
                            start_delay + pc.eta_day,
                            pc.etd_day !== nothing ? start_delay + pc.etd_day : start_delay + pc.eta_day,
                            pc.port_order)
                for pc in svc_spec.port_calls
            ]
            push!(planned_rotations, PlannedVesselRotation(
                vessel_name, sid, fleet_id, start_delay, planned_calls,
            ))
        end
    end

    # 按优先级排序需求
    sorted_demands = sort(world.demands;
        by=d -> begin
            idx = findfirst(==(d.priority_class), model.priority_order)
            idx === nothing ? 999 : idx
        end,
    )

    # 贪心分配
    for d_spec in sorted_demands
        assigned = false
        # 按剩余容量降序尝试服务
        for (sid, _) in sort(collect(service_remaining_capacity); by=x->x[2], rev=true)
            svc_spec = world.services[sid]
            port_list = [pc.port_code for pc in svc_spec.port_calls]
            orig_idx = findfirst(==(d_spec.origin), port_list)
            dest_idx = findfirst(==(d_spec.destination), port_list)

            if orig_idx !== nothing && dest_idx !== nothing && orig_idx < dest_idx
                if service_remaining_capacity[sid] >= d_spec.quantity_ffe
                    # 分配成功
                    service_remaining_capacity[sid] -= d_spec.quantity_ffe
                    legs = PlannedPathLeg[]
                    for leg_idx in orig_idx:(dest_idx - 1)
                        if leg_idx <= length(svc_spec.legs)
                            leg = svc_spec.legs[leg_idx]
                            push!(legs, PlannedPathLeg(
                                leg_idx, sid, leg.origin, leg.destination,
                                leg.depart_day, leg.arrival_day,
                            ))
                        end
                    end
                    push!(planned_assignments, PlannedDemandAssignment(
                        d_spec.demand_id, d_spec.origin, d_spec.destination,
                        d_spec.quantity_ffe, legs,
                    ))
                    assigned = true
                    break
                end
            end
        end
        # 未分配的需求被拒绝（不加入 planned_assignments）
    end

    meta = PlanMeta(
        "greedy-heuristic", scenario_id,
        world.time.cycle_days, world.time.horizon_cycles,
        string(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")),
        0.0,
        :heuristic,
    )

    return ExecutionPlan(meta, planned_services, planned_rotations, planned_assignments)
end

# ============================================================
# 7. 决策模型注册表
# ============================================================

"""
    DecisionModelRegistry — 决策模型注册表

管理所有可用的决策模型，支持按名称查找和列举。
"""
struct DecisionModelRegistry
    models::Dict{String, AbstractDecisionModel}
end

DecisionModelRegistry() = DecisionModelRegistry(Dict{String, AbstractDecisionModel}())

"""注册一个决策模型"""
function register_model!(registry::DecisionModelRegistry, model::AbstractDecisionModel)
    key = model_name(model)
    registry.models[key] = model
    return registry
end

"""按名称获取决策模型"""
function get_model(registry::DecisionModelRegistry, name::String)::AbstractDecisionModel
    haskey(registry.models, name) || error("Unknown decision model: $name. Available: $(keys(registry.models))")
    return registry.models[name]
end

"""列出所有已注册模型"""
function list_models(registry::DecisionModelRegistry)::Vector{String}
    return collect(keys(registry.models))
end

"""构建默认注册表（包含所有内置模型）"""
function default_registry()::DecisionModelRegistry
    registry = DecisionModelRegistry()
    register_model!(registry, TimeSpaceMILPModel())
    register_model!(registry, SimpleDirectAllocationModel())
    register_model!(registry, GreedyHeuristicModel())
    return registry
end

# ============================================================
# 8. 决策模型接口总表（文档性质）
# ============================================================

#=

| 模型 | 最少输入 | 最少输出 | 能力标签 | 决策变量 |
|------|---------|---------|---------|---------|
| TimeSpaceMILP | services + fleet + demands + cost | ExecutionPlan (full) | exact, routing, capacity, transshipment, time_windows, service_activation | service_active, fleet_type, vessel_count, cargo_flow, demand_accepted, transshipment_port |
| SimpleDirectAllocation | services + demands | ExecutionPlan (direct only) | heuristic, routing, capacity | cargo_flow, demand_accepted |
| GreedyHeuristic | services + fleet + demands | ExecutionPlan (greedy) | heuristic, routing, capacity, demand_acceptance | cargo_flow, demand_accepted |

所有模型的输出统一为 ExecutionPlan，包含：
- planned_services: 服务开通与船型分配
- planned_rotations: 船舶旋转计划
- planned_assignments: 需求分配与路径

仿真层只读取 ExecutionPlan，不关心它由哪个模型产生。

=#
