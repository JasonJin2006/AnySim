
# ============================================================
# world.jl — 统一航运世界模型 (World Definition Layer)
#
# 本文件定义班轮航运系统中所有对象、属性、关系和约束背景。
# 核心原则：
#   1. 世界模型尽量完整，具体决策模型只取自己需要的那部分
#   2. 属性分为外生(exogenous)和内生(endogenous)两类
#   3. 外生参数直接给定，内生参数由运筹学模型或仿真算出
#   4. 每个属性标注其所属层级：:world / :decision / :simulation
# ============================================================

# ============================================================
# 1. 港口 (Port)
# ============================================================

"""
    PortSpec — 港口的完整世界模型定义

外生参数：地理位置、作业能力、成本结构
内生参数：实际拥堵水平、吞吐量（由仿真产生）
"""
struct PortSpec
    port_code::String
    port_name::String
    region::String
    country::String
    latitude::Float64
    longitude::Float64
    # 作业能力
    berths::Int                          # 泊位数
    cranes_per_berth::Int                # 每泊位岸桥数
    handling_rate_ffe_per_hour::Float64  # 每小时装卸效率 (FFE)
    max_vessel_size_teu::Int             # 最大靠泊船型 (TEU)
    # 成本
    port_call_cost::Float64              # 靠泊费
    loading_cost_per_ffe::Float64        # 装船成本
    discharging_cost_per_ffe::Float64    # 卸船成本
    storage_cost_per_ffe_per_day::Float64# 堆存成本
    # 时间
    min_port_stay_hours::Float64         # 最短在港时间
    pilotage_hours::Float64              # 引航时间
    # 扰动参数
    congestion_sensitivity::Float64      # 拥堵敏感度 [0,1]
    disruption_probability::Float64      # 扰动概率 [0,1]
    mean_delay_days::Float64             # 平均延误天数
end

PortSpec(;
    port_code::String="UNKNOWN",
    port_name::String="",
    region::String="",
    country::String="",
    latitude::Float64=0.0,
    longitude::Float64=0.0,
    berths::Int=4,
    cranes_per_berth::Int=4,
    handling_rate_ffe_per_hour::Float64=100.0,
    max_vessel_size_teu::Int=20000,
    port_call_cost::Float64=50000.0,
    loading_cost_per_ffe::Float64=150.0,
    discharging_cost_per_ffe::Float64=150.0,
    storage_cost_per_ffe_per_day::Float64=5.0,
    min_port_stay_hours::Float64=12.0,
    pilotage_hours::Float64=4.0,
    congestion_sensitivity::Float64=0.5,
    disruption_probability::Float64=0.0,
    mean_delay_days::Float64=0.0
) = PortSpec(port_code, port_name, region, country, latitude, longitude,
             berths, cranes_per_berth, handling_rate_ffe_per_hour, max_vessel_size_teu,
             port_call_cost, loading_cost_per_ffe, discharging_cost_per_ffe, storage_cost_per_ffe_per_day,
             min_port_stay_hours, pilotage_hours, congestion_sensitivity, disruption_probability, mean_delay_days)

# ============================================================
# 2. 船舶/船型 (Vessel / FleetType)
# ============================================================

"""
    VesselSpec — 船舶的完整世界模型定义

外生参数：船型规格、成本结构
内生参数：部署状态（由决策模型决定）
"""
struct VesselSpec
    fleet_id::String
    fleet_name::String
    # 容量
    capacity_teu::Int
    capacity_ffe::Float64
    reefer_plugs::Int                    # 冷藏箱插头数
    # 尺寸限制
    max_draft_meters::Float64            # 最大吃水
    length_overall_meters::Float64       # 船长
    # 性能
    design_speed_knots::Float64          # 设计航速
    min_speed_knots::Float64             # 最低航速
    fuel_consumption_tons_per_day::Float64 # 日燃油消耗 (设计航速)
    # 成本
    fixed_deployment_cost::Float64       # 固定部署成本 (周)
    sailing_cost_per_day::Float64        # 航行日成本
    port_call_cost::Float64              # 靠泊费
    charter_rate_per_day::Float64        # 日租金
    # 可用性
    available_units::Int                 # 可用数量
    max_service_days::Int                # 最长服务天数
    speed_class::String                  # 速度等级
end

VesselSpec(;
    fleet_id::String="STD",
    fleet_name::String="Standard",
    capacity_teu::Int=8000,
    capacity_ffe::Float64=4000.0,
    reefer_plugs::Int=400,
    max_draft_meters::Float64=14.5,
    length_overall_meters::Float64=300.0,
    design_speed_knots::Float64=20.0,
    min_speed_knots::Float64=12.0,
    fuel_consumption_tons_per_day::Float64=50.0,
    fixed_deployment_cost::Float64=0.0,
    sailing_cost_per_day::Float64=15000.0,
    port_call_cost::Float64=50000.0,
    charter_rate_per_day::Float64=25000.0,
    available_units::Int=10,
    max_service_days::Int=365,
    speed_class::String="standard"
) = VesselSpec(fleet_id, fleet_name, capacity_teu, capacity_ffe, reefer_plugs,
               max_draft_meters, length_overall_meters, design_speed_knots, min_speed_knots,
               fuel_consumption_tons_per_day, fixed_deployment_cost, sailing_cost_per_day,
               port_call_cost, charter_rate_per_day, available_units, max_service_days, speed_class)

# ============================================================
# 3. 货物/需求 (Demand)
# ============================================================

"""
    DemandSpec — 货物需求的完整世界模型定义

外生参数：OD、量、时间窗、优先级
内生参数：是否被接受、分配路径（由决策模型决定）
"""
struct DemandSpec
    demand_id::String
    origin::String
    destination::String
    # 量
    quantity_ffe::Float64
    quantity_teu::Float64
    reefer_ffe::Float64                  # 冷藏箱量
    # 时间
    release_time::Int                    # 最早可提货日
    due_time::Int                        # 最迟送达日
    transit_time::Int                    # 承诺运输时间
    # 经济
    revenue_per_ffe::Float64             # 单位收入
    priority_class::String               # 优先级: "premium" / "standard" / "economy"
    reject_penalty_per_ffe::Float64      # 拒运罚金
    late_penalty_per_ffe_per_day::Float64 # 延误罚金
    is_mandatory::Bool                   # 是否必须承运
    # 中转约束
    max_transshipments::Int              # 最大中转次数
    # 仿真层属性
    actual_arrival_day::Float64          # 实际到达日 (仿真产出)
    is_delivered::Bool                   # 是否送达 (仿真产出)
    is_on_time::Bool                     # 是否准时 (仿真产出)
end

DemandSpec(;
    demand_id::String="D-0001",
    origin::String="",
    destination::String="",
    quantity_ffe::Float64=0.0,
    quantity_teu::Float64=0.0,
    reefer_ffe::Float64=0.0,
    release_time::Int=0,
    due_time::Int=30,
    transit_time::Int=30,
    revenue_per_ffe::Float64=1000.0,
    priority_class::String="standard",
    reject_penalty_per_ffe::Float64=0.0,
    late_penalty_per_ffe_per_day::Float64=50.0,
    is_mandatory::Bool=false,
    max_transshipments::Int=2,
    actual_arrival_day::Float64=-1.0,
    is_delivered::Bool=false,
    is_on_time::Bool=false
) = DemandSpec(demand_id, origin, destination, quantity_ffe, quantity_teu, reefer_ffe,
               release_time, due_time, transit_time, revenue_per_ffe, priority_class,
               reject_penalty_per_ffe, late_penalty_per_ffe_per_day, is_mandatory,
               max_transshipments, actual_arrival_day, is_delivered, is_on_time)

# ============================================================
# 4. 航段 (Leg) — 世界模型层
# ============================================================

"""
    WorldLeg — 航线中一个航段的世界模型定义

描述两个靠港之间的物理航段，包含起止港口、航行时间和港口停留时间。
与优化层的 ServiceLeg 不同，WorldLeg 不包含优化相关的 route_id / leg_index，
仅关注航段的物理属性。
"""
struct WorldLeg
    origin::String                        # 起始港代码
    destination::String                   # 目的港代码
    depart_day::Int                       # 出发日 (班期周期内的相对天数)
    arrival_day::Int                      # 到达日 (班期周期内的相对天数)
    sailing_days::Int                     # 航行天数
    port_stay_days::Int                   # 港口停留天数
    is_transshipment_allowed::Bool        # 是否允许中转
end

# ============================================================
# 5. 服务/航线 (Service)
# ============================================================

"""
    ServiceSpec — 航线服务的完整世界模型定义

外生参数：靠港顺序、航行时间、频率
内生参数：是否开通、配什么船型、投几艘船（由决策模型决定）
"""
struct ServiceSpec
    service_id::String
    service_name::String
    # 靠港序列
    port_calls::Vector{PortCall}
    legs::Vector{WorldLeg}
    # 时间结构
    cycle_days::Int                      # 班期周期 (通常7天)
    frequency_days::Int                  # 发船频率
    route_total_days::Int                # 一圈总天数
    required_vessels::Int                # 最低所需船舶数
    # 决策属性
    is_active_candidate::Bool            # 是否可作为候选开通
    allowed_fleet_types::Vector{String}  # 允许的船型列表
    # 仿真层属性
    is_active::Bool                      # 是否实际开通 (决策产出)
    assigned_fleet_id::String            # 分配的船型 (决策产出)
    deployed_vessel_count::Int           # 实际部署数 (决策产出)
end

ServiceSpec(;
    service_id::String="SVC-001",
    service_name::String="",
    port_calls::Vector{PortCall}=PortCall[],
    legs::Vector{WorldLeg}=WorldLeg[],
    cycle_days::Int=7,
    frequency_days::Int=7,
    route_total_days::Int=35,
    required_vessels::Int=5,
    is_active_candidate::Bool=true,
    allowed_fleet_types::Vector{String}=String[],
    is_active::Bool=false,
    assigned_fleet_id::String="",
    deployed_vessel_count::Int=0
) = ServiceSpec(service_id, service_name, port_calls, legs, cycle_days, frequency_days,
                route_total_days, required_vessels, is_active_candidate, allowed_fleet_types,
                is_active, assigned_fleet_id, deployed_vessel_count)

# ============================================================
# 5. 扰动 (Disruption)
# ============================================================

"""
    DisruptionSpec — 扰动事件的完整世界模型定义

外生参数：扰动类型、影响范围、持续时间
内生参数：实际影响（由仿真产生）
"""
struct DisruptionSpec
    disruption_id::String
    disruption_type::Symbol              # :port_congestion / :weather / :mechanical / :strike / :canal_closure
    # 影响范围
    affected_ports::Vector{String}       # 受影响港口
    affected_services::Vector{String}    # 受影响航线
    # 时间
    start_day::Float64                   # 开始日
    end_day::Float64                     # 结束日
    duration_days::Float64               # 持续天数
    # 影响程度
    sailing_delay_factor::Float64        # 航行延误因子 (1.0=无, >1=延迟)
    port_delay_factor::Float64           # 港口延误因子
    capacity_reduction::Float64          # 容量缩减比例 [0,1]
    # 概率
    probability::Float64                 # 发生概率 [0,1]
end

DisruptionSpec(;
    disruption_id::String="DIS-001",
    disruption_type::Symbol=:weather,
    affected_ports::Vector{String}=String[],
    affected_services::Vector{String}=String[],
    start_day::Float64=0.0,
    end_day::Float64=0.0,
    duration_days::Float64=3.0,
    sailing_delay_factor::Float64=1.2,
    port_delay_factor::Float64=1.1,
    capacity_reduction::Float64=0.0,
    probability::Float64=0.1
) = DisruptionSpec(disruption_id, disruption_type, affected_ports, affected_services,
                   start_day, end_day, duration_days, sailing_delay_factor,
                   port_delay_factor, capacity_reduction, probability)

# ============================================================
# 6. 成本 (Cost)
# ============================================================

"""
    CostSpec — 成本结构的完整世界模型定义

全部为外生参数
"""
struct CostSpec
    sea_cost_per_day::Float64
    wait_cost_per_day::Float64
    trans_cost_per_day::Float64
    port_handling_cost_per_ffe::Float64
    port_call_cost::Float64
    late_penalty_per_ffe_per_day::Float64
    reject_penalty_per_ffe::Float64
    fuel_price_per_ton::Float64
    charter_rate_per_day::Float64
end

CostSpec(;
    sea_cost_per_day::Float64=1.0,
    wait_cost_per_day::Float64=0.0,
    trans_cost_per_day::Float64=0.0,
    port_handling_cost_per_ffe::Float64=0.0,
    port_call_cost::Float64=50000.0,
    late_penalty_per_ffe_per_day::Float64=50.0,
    reject_penalty_per_ffe::Float64=0.0,
    fuel_price_per_ton::Float64=600.0,
    charter_rate_per_day::Float64=25000.0
) = CostSpec(sea_cost_per_day, wait_cost_per_day, trans_cost_per_day,
             port_handling_cost_per_ffe, port_call_cost, late_penalty_per_ffe_per_day,
             reject_penalty_per_ffe, fuel_price_per_ton, charter_rate_per_day)

# ============================================================
# 7. 时间 (Time)
# ============================================================

"""
    TimeSpec — 时间结构的完整世界模型定义

外生参数：仿真起止、周期、步长
"""
struct TimeSpec
    cycle_days::Int                      # 班期周期 (通常7天)
    horizon_cycles::Int                  # 仿真周期数
    demand_periods::Int                  # 需求期数
    min_connection_time::Int             # 最短中转衔接时间 (天)
    due_slack_days::Int                  # 送达宽限天数
    sim_start_day::Float64               # 仿真开始日
    sim_end_day::Float64                 # 仿真结束日
end

TimeSpec(;
    cycle_days::Int=7,
    horizon_cycles::Int=8,
    demand_periods::Int=8,
    min_connection_time::Int=1,
    due_slack_days::Int=0,
    sim_start_day::Float64=0.0,
    sim_end_day::Float64=200.0
) = TimeSpec(cycle_days, horizon_cycles, demand_periods, min_connection_time,
             due_slack_days, sim_start_day, sim_end_day)

# ============================================================
# 8. 绩效指标 (KPI)
# ============================================================

"""
    KpiSpec — 绩效指标定义

定义我们关心的所有输出指标，标注其所属层级
"""
struct KpiSpec
    # 经济指标
    measure_profit::Bool
    measure_revenue::Bool
    measure_cost::Bool
    measure_roi::Bool
    # 服务指标
    measure_on_time_delivery::Bool
    measure_transit_time::Bool
    measure_reliability::Bool
    measure_rejection_rate::Bool
    # 运营指标
    measure_utilization::Bool
    measure_port_congestion::Bool
    measure_transshipment_rate::Bool
    # 鲁棒性指标
    measure_profit_retention::Bool
    measure_plan_deviation::Bool
    measure_recovery_time::Bool
end

KpiSpec(;
    measure_profit::Bool=true,
    measure_revenue::Bool=true,
    measure_cost::Bool=true,
    measure_roi::Bool=false,
    measure_on_time_delivery::Bool=true,
    measure_transit_time::Bool=true,
    measure_reliability::Bool=true,
    measure_rejection_rate::Bool=true,
    measure_utilization::Bool=true,
    measure_port_congestion::Bool=true,
    measure_transshipment_rate::Bool=false,
    measure_profit_retention::Bool=true,
    measure_plan_deviation::Bool=true,
    measure_recovery_time::Bool=false
) = KpiSpec(measure_profit, measure_revenue, measure_cost, measure_roi,
            measure_on_time_delivery, measure_transit_time, measure_reliability,
            measure_rejection_rate, measure_utilization, measure_port_congestion,
            measure_transshipment_rate, measure_profit_retention, measure_plan_deviation,
            measure_recovery_time)

# ============================================================
# 9. 统一世界模型 (ShippingWorld)
# ============================================================

"""
    ShippingWorld — 统一航运世界模型

包含系统中所有对象、参数、关系的完整定义。
这是整个框架的根对象，不同决策模型从中投影自己需要的部分。
"""
struct ShippingWorld
    # 对象集合
    ports::Dict{String, PortSpec}           # port_code => PortSpec
    vessels::Dict{String, VesselSpec}       # fleet_id => VesselSpec
    demands::Vector{DemandSpec}             # 所有需求
    services::Dict{String, ServiceSpec}     # service_id => ServiceSpec
    disruptions::Vector{DisruptionSpec}     # 所有扰动
    # 配置
    cost::CostSpec
    time::TimeSpec
    kpi::KpiSpec
    # 场景标识
    scenario_id::String
    description::String
    # 元数据
    demand_multiplier::Float64
    capacity_multiplier::Float64
    disruption_level::Float64
end

ShippingWorld(;
    ports::Dict{String, PortSpec}=Dict{String, PortSpec}(),
    vessels::Dict{String, VesselSpec}=Dict{String, VesselSpec}(),
    demands::Vector{DemandSpec}=DemandSpec[],
    services::Dict{String, ServiceSpec}=Dict{String, ServiceSpec}(),
    disruptions::Vector{DisruptionSpec}=DisruptionSpec[],
    cost::CostSpec=CostSpec(),
    time::TimeSpec=TimeSpec(),
    kpi::KpiSpec=KpiSpec(),
    scenario_id::String="baseline",
    description::String="",
    demand_multiplier::Float64=1.0,
    capacity_multiplier::Float64=1.0,
    disruption_level::Float64=0.0
) = ShippingWorld(ports, vessels, demands, services, disruptions, cost, time, kpi,
                  scenario_id, description, demand_multiplier, capacity_multiplier, disruption_level)

# ============================================================
# 10. 世界模型投影 — 从完整世界提取特定决策模型需要的子集
# ============================================================

"""
    WorldProjection — 从 ShippingWorld 投影出的子集

每个决策模型不使用全部世界参数，只投影它关心的部分。
这确保了：世界模型尽量完整，但具体模型只取自己需要的那部分。
"""
struct WorldProjection
    # 哪些对象被包含
    included_port_codes::Set{String}
    included_service_ids::Set{String}
    included_demand_ids::Set{String}
    included_fleet_ids::Set{String}
    # 哪些属性维度被包含
    include_time_windows::Bool            # 是否包含 release_time / due_time
    include_transshipment::Bool           # 是否考虑中转
    include_capacity::Bool                # 是否考虑容量约束
    include_port_congestion::Bool         # 是否考虑港口拥堵
    include_disruption::Bool              # 是否考虑扰动
    include_recovery::Bool                # 是否考虑恢复策略
    include_speed_adjustment::Bool        # 是否允许调速
    include_skip_port::Bool               # 是否允许跳港
    # 引用回完整世界
    world::ShippingWorld
end

function WorldProjection(world::ShippingWorld;
                         included_port_codes::Set{String}=Set{String}(),
                         included_service_ids::Set{String}=Set{String}(),
                         included_demand_ids::Set{String}=Set{String}(),
                         included_fleet_ids::Set{String}=Set{String}(),
                         include_time_windows::Bool=true,
                         include_transshipment::Bool=true,
                         include_capacity::Bool=true,
                         include_port_congestion::Bool=false,
                         include_disruption::Bool=false,
                         include_recovery::Bool=false,
                         include_speed_adjustment::Bool=false,
                         include_skip_port::Bool=false)
    # 如果没有显式指定，则默认包含所有
    if isempty(included_port_codes)
        included_port_codes = Set(keys(world.ports))
    end
    if isempty(included_service_ids)
        included_service_ids = Set(keys(world.services))
    end
    if isempty(included_demand_ids)
        included_demand_ids = Set([d.demand_id for d in world.demands])
    end
    if isempty(included_fleet_ids)
        included_fleet_ids = Set(keys(world.vessels))
    end
    return WorldProjection(included_port_codes, included_service_ids,
                           included_demand_ids, included_fleet_ids,
                           include_time_windows, include_transshipment,
                           include_capacity, include_port_congestion,
                           include_disruption, include_recovery,
                           include_speed_adjustment, include_skip_port,
                           world)
end

# ============================================================
# 11. 世界构建器 — 从数据文件构建 ShippingWorld
# ============================================================

"""
    build_shipping_world(schedule_file, od_file; config...) -> ShippingWorld

从数据文件构建完整的航运世界模型。
这是整个框架的入口：先构建世界，再挂接决策模型。
"""
function build_shipping_world(schedule_file::String, od_file::String;
                              scenario_id::String="baseline",
                              description::String="",
                              demand_multiplier::Float64=1.0,
                              capacity_multiplier::Float64=1.0,
                              disruption_level::Float64=0.0,
                              cycle_days::Int=7,
                              horizon_cycles::Int=8,
                              due_slack_days::Int=0,
                              min_connection_time::Int=1,
                              max_transshipments::Int=2,
                              reject_penalty_per_ffe::Float64=0.0)
    # 加载基础数据
    schedules = load_route_schedules(schedule_file)
    all_ods = load_od_demand(od_file)

    # 构建港口
    port_dict = Dict{String, PortSpec}()
    for route in schedules
        for pc in route.port_calls
            if !haskey(port_dict, pc.port_code)
                port_dict[pc.port_code] = PortSpec(port_code=pc.port_code)
            end
        end
    end

    # 构建服务
    service_dict = Dict{String, ServiceSpec}()
    for route in schedules
        svc = build_service(route; cycle_days=cycle_days)
        service_dict[svc.route_id] = ServiceSpec(
            service_id=svc.route_id,
            service_name=svc.service_name,
            port_calls=svc.port_calls,
            legs=[WorldLeg(l.origin, l.destination, l.depart_day, l.arrival_day, l.sailing_days, l.port_stay_days, l.is_transshipment_allowed) for l in svc.legs],
            cycle_days=svc.cycle_days,
            frequency_days=svc.frequency_days,
            route_total_days=svc.route_total_days,
            required_vessels=svc.required_vessels,
            is_active_candidate=svc.is_active_candidate,
            allowed_fleet_types=svc.allowed_fleet_types,
        )
    end

    # 构建需求
    demand_list = DemandSpec[]
    for route in schedules
        route_ods = filter_ods_by_route(all_ods, route)
        opt_demands = build_optimization_demands(route_ods;
            periods=horizon_cycles, cycle_days=cycle_days,
            due_slack_days=due_slack_days, demand_multiplier=demand_multiplier,
            max_transshipments=max_transshipments,
            reject_penalty_per_ffe=reject_penalty_per_ffe)
        for od in opt_demands
            push!(demand_list, DemandSpec(
                demand_id=od.demand_id,
                origin=od.origin,
                destination=od.destination,
                quantity_ffe=od.quantity_ffe,
                revenue_per_ffe=od.revenue_per_ffe,
                release_time=od.release_time,
                due_time=od.due_time,
                transit_time=od.transit_time,
                priority_class=od.priority_class,
                reject_penalty_per_ffe=od.reject_penalty_per_ffe,
                max_transshipments=od.max_transshipments,
                is_mandatory=od.is_mandatory,
            ))
        end
    end

    # 构建默认船型
    vessel_dict = Dict{String, VesselSpec}(
        "STD-8K" => VesselSpec(fleet_id="STD-8K", fleet_name="Standard 8000 TEU",
                                capacity_teu=8000, capacity_ffe=4000.0, available_units=20),
    )

    # 构建扰动
    disruption_list = DisruptionSpec[]
    if disruption_level > 0
        push!(disruption_list, DisruptionSpec(
            disruption_id="baseline-disruption",
            disruption_type=:port_congestion,
            sailing_delay_factor=1.0 + disruption_level * 0.2,
            port_delay_factor=1.0 + disruption_level * 0.1,
            probability=1.0,
        ))
    end

    return ShippingWorld(
        ports=port_dict,
        vessels=vessel_dict,
        demands=demand_list,
        services=service_dict,
        disruptions=disruption_list,
        cost=CostSpec(),
        time=TimeSpec(cycle_days=cycle_days, horizon_cycles=horizon_cycles,
                      demand_periods=horizon_cycles, min_connection_time=min_connection_time,
                      due_slack_days=due_slack_days),
        kpi=KpiSpec(),
        scenario_id=scenario_id,
        description=description,
        demand_multiplier=demand_multiplier,
        capacity_multiplier=capacity_multiplier,
        disruption_level=disruption_level,
    )
end

# ============================================================
# 12. 便捷查询函数
# ============================================================

"""获取世界中所有港口代码"""
port_codes(w::ShippingWorld) = collect(keys(w.ports))

"""获取世界中所有服务ID"""
service_ids(w::ShippingWorld) = collect(keys(w.services))

"""获取世界中所有船型ID"""
fleet_ids(w::ShippingWorld) = collect(keys(w.vessels))

"""获取世界中所有需求ID"""
demand_ids(w::ShippingWorld) = [d.demand_id for d in w.demands]

"""获取某个服务的靠港序列"""
function service_port_codes(w::ShippingWorld, service_id::String)
    haskey(w.services, service_id) || return String[]
    return [pc.port_code for pc in w.services[service_id].port_calls]
end

"""获取某个服务允许的船型"""
function service_fleet_options(w::ShippingWorld, service_id::String)
    haskey(w.services, service_id) || return VesselSpec[]
    svc = w.services[service_id]
    if isempty(svc.allowed_fleet_types)
        return collect(values(w.vessels))
    end
    return [w.vessels[fid] for fid in svc.allowed_fleet_types if haskey(w.vessels, fid)]
end

"""获取投影中的需求子集"""
function projected_demands(proj::WorldProjection)
    return [d for d in proj.world.demands if d.demand_id in proj.included_demand_ids]
end

"""获取投影中的服务子集"""
function projected_services(proj::WorldProjection)
    return [svc for (sid, svc) in proj.world.services if sid in proj.included_service_ids]
end

"""获取投影中的港口子集"""
function projected_ports(proj::WorldProjection)
    return [p for (pid, p) in proj.world.ports if pid in proj.included_port_codes]
end

"""获取投影中的船型子集"""
function projected_vessels(proj::WorldProjection)
    return [v for (fid, v) in proj.world.vessels if fid in proj.included_fleet_ids]
end
