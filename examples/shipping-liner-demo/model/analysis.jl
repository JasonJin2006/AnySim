
# ============================================================
# analysis.jl — 结果分析层 (Result Analysis Layer)
#
# 核心职责：
#   1. 从仿真结果中计算多层级、多时段的运营指标
#   2. 计划值与实际值的偏差分析
#   3. 不同决策模型之间的表现对比
#   4. 同一模型在不同扰动强度下的鲁棒性分析
#   5. 指标随时间的分布与演化
#
# 这是方法论中的 E层(结果分析层)
# ============================================================

# ============================================================
# 1. 时间序列数据
# ============================================================

"""
    TimeSeriesPoint — 单个时间点的指标快照
"""
struct TimeSeriesPoint
    time::Float64
    value::Float64
    label::String
end

"""
    TimeSeriesData — 指标随时间的演化
"""
struct TimeSeriesData
    metric_name::String
    unit::String
    points::Vector{TimeSeriesPoint}
end

TimeSeriesData(name::String; unit::String="") =
    TimeSeriesData(name, unit, TimeSeriesPoint[])

"""添加一个时间点"""
function add_point!(ts::TimeSeriesData, time::Float64, value::Float64; label::String="")
    push!(ts.points, TimeSeriesPoint(time, value, label))
    return ts
end

"""获取时间序列的值数组"""
function ts_values(ts::TimeSeriesData)
    return [p.value for p in ts.points]
end

"""获取时间序列的时间数组"""
function times(ts::TimeSeriesData)
    return [p.time for p in ts.points]
end

"""计算时间序列的均值"""
function mean_value(ts::TimeSeriesData)
    vals = ts_values(ts)
    return isempty(vals) ? 0.0 : sum(vals) / length(vals)
end

"""计算时间序列的最大值"""
function max_value(ts::TimeSeriesData)
    vals = ts_values(ts)
    return isempty(vals) ? 0.0 : maximum(vals)
end

"""计算时间序列的最小值"""
function min_value(ts::TimeSeriesData)
    vals = ts_values(ts)
    return isempty(vals) ? 0.0 : minimum(vals)
end

"""计算时间序列的末值"""
function last_value(ts::TimeSeriesData)
    return isempty(ts.points) ? 0.0 : ts.points[end].value
end

# ============================================================
# 2. 实验结果
# ============================================================

"""
    ExperimentResult — 单次实验的完整结果

包含：世界模型、执行计划、仿真原始数据、计算后的KPI
"""
struct ExperimentResult
    # 标识
    experiment_id::String
    model_name::String
    scenario_id::String
    # 输入
    world::ShippingWorld
    plan::ExecutionPlan
    # 仿真原始数据
    sim_events::Vector{VesselEvent}
    sim_stats::Vector{PortStats}
    sim_cargo::Vector{CargoBatch}
    # 计算后的KPI
    kpi::KpiSummary
    demand_outcomes::Vector{DemandOutcome}
    service_reliability::Vector{ServiceReliability}
    port_congestion::Vector{PortCongestion}
    # 时间序列
    time_series::Dict{String, TimeSeriesData}
    # 经济分析
    economic_breakdown::EconomicBreakdown
end

# ============================================================
# 3. 需求结果分析
# ============================================================

"""
    compute_demand_outcomes(plan::ExecutionPlan, sim_cargo::Vector{CargoBatch};
                            planned_transit_days) -> Vector{DemandOutcome}

对比计划与实际，计算每条需求的交付结果。
"""
function compute_demand_outcomes(plan::ExecutionPlan,
                                 sim_cargo::Vector{CargoBatch};
                                 planned_transit_days::Float64=30.0)
    outcomes = DemandOutcome[]

    # 构建计划分配的查找表
    planned_qty = Dict{String, Float64}()
    planned_arrival = Dict{String, Float64}()
    for assignment in plan.planned_assignments
        planned_qty[assignment.demand_id] = assignment.quantity
        if !isempty(assignment.path_legs)
            planned_arrival[assignment.demand_id] = Float64(maximum(
                leg -> leg.arrival_day, assignment.path_legs))
        end
    end

    # 按需求OD聚合仿真中的货物
    cargo_by_od = Dict{Tuple{String,String}, Vector{CargoBatch}}()
    for c in sim_cargo
        key = (c.origin, c.destination)
        if !haskey(cargo_by_od, key)
            cargo_by_od[key] = CargoBatch[]
        end
        push!(cargo_by_od[key], c)
    end

    # 为每个计划分配计算结果
    for assignment in plan.planned_assignments
        key = (assignment.origin, assignment.destination)
        delivered_cargo = get(cargo_by_od, key, CargoBatch[])

        # 筛选已交付的
        delivered = [c for c in delivered_cargo if c.sim_time >= 0]
        delivered_qty = sum(c.ffe for c in delivered; init=0.0)

        # 计划到达时间
        p_arrival = get(planned_arrival, assignment.demand_id, -1.0)

        # 实际到达时间（取最晚交付的）
        actual_arrival = isempty(delivered) ? -1.0 : maximum(c.sim_time for c in delivered)

        # 延误
        delay = (actual_arrival >= 0 && p_arrival >= 0) ? max(actual_arrival - p_arrival, 0.0) : 0.0

        # 是否准时（10%宽限）
        promised = p_arrival > 0 ? p_arrival : planned_transit_days
        is_on_time = actual_arrival >= 0 && actual_arrival <= promised * 1.1

        push!(outcomes, DemandOutcome(
            assignment.demand_id,
            assignment.origin,
            assignment.destination,
            assignment.quantity,
            delivered_qty,
            p_arrival,
            actual_arrival,
            delay,
            is_on_time,
            !isempty(delivered),
        ))
    end

    return outcomes
end

# ============================================================
# 4. 服务可靠性分析
# ============================================================

"""
    compute_service_reliability(plan::ExecutionPlan, sim_events::Vector{VesselEvent})
    -> Vector{ServiceReliability}

计算每条服务的可靠性指标。
"""
function compute_service_reliability(plan::ExecutionPlan,
                                     sim_events::Vector{VesselEvent})
    reliabilities = ServiceReliability[]

    # 按服务分组到港事件
    events_by_service = Dict{String, Vector{VesselEvent}}()
    for evt in sim_events
        if evt.event_type == "ARRIVAL"
            if !haskey(events_by_service, evt.route_id)
                events_by_service[evt.route_id] = VesselEvent[]
            end
            push!(events_by_service[evt.route_id], evt)
        end
    end

    # 计算每条服务的可靠性
    for rotation in plan.planned_rotations
        sid = rotation.service_id
        service_events = get(events_by_service, sid, VesselEvent[])

        planned_count = length(rotation.planned_calls)
        actual_arrivals = length(service_events)

        on_time = actual_arrivals
        delayed = max(actual_arrivals - on_time, 0)
        missed = max(planned_count - actual_arrivals, 0)

        reliability_rate = planned_count > 0 ? Float64(on_time) / planned_count : 0.0
        avg_delay = 0.0

        push!(reliabilities, ServiceReliability(
            sid, planned_count, on_time, delayed, missed,
            reliability_rate, avg_delay,
        ))
    end

    return reliabilities
end

# ============================================================
# 5. 港口拥堵分析
# ============================================================

"""
    compute_port_congestion(sim_stats::Vector{PortStats}) -> Vector{PortCongestion}

从仿真统计数据中计算港口拥堵指标。
"""
function compute_port_congestion(sim_stats::Vector{PortStats})
    stats_by_port = Dict{String, Vector{PortStats}}()
    for s in sim_stats
        if !haskey(stats_by_port, s.port_code)
            stats_by_port[s.port_code] = PortStats[]
        end
        push!(stats_by_port[s.port_code], s)
    end

    congestions = PortCongestion[]
    for (port_code, port_stats) in stats_by_port
        total_visits = length(port_stats)
        avg_wait = 0.0
        max_wait = 0.0
        peak_vessels = isempty(port_stats) ? 0 : maximum(s.vessel_count for s in port_stats)

        push!(congestions, PortCongestion(
            port_code, total_visits, avg_wait, max_wait, peak_vessels,
        ))
    end

    return congestions
end

# ============================================================
# 6. 经济分析
# ============================================================

"""
    compute_economic_breakdown(plan::ExecutionPlan, sim_cargo::Vector{CargoBatch};
                               world) -> EconomicBreakdown

计算详细的经济分解：收入、各类成本、净利润。
"""
function compute_economic_breakdown(plan::ExecutionPlan,
                                    sim_cargo::Vector{CargoBatch};
                                    world::ShippingWorld=ShippingWorld())
    # 收入
    delivered = [c for c in sim_cargo if c.sim_time >= 0]
    cargo_revenue = sum(c.revenue_per_unit * c.ffe for c in delivered; init=0.0)

    # 船队部署成本
    fleet_cost = 0.0
    for ps in plan.planned_services
        if ps.is_active
            fleet_cost += world.cost.charter_rate_per_day * ps.vessel_count * 7.0 * world.time.horizon_cycles
        end
    end

    # 海运成本
    sea_cost = 0.0
    for rotation in plan.planned_rotations
        total_sailing = 0.0
        for i in 2:length(rotation.planned_calls)
            prev = rotation.planned_calls[i-1]
            curr = rotation.planned_calls[i]
            sailing = curr.planned_eta_day - (prev.planned_etd_day > 0 ? prev.planned_etd_day : prev.planned_eta_day)
            total_sailing += max(sailing, 0.0)
        end
        sea_cost += total_sailing * world.cost.sea_cost_per_day
    end

    # 港口操作成本
    port_handling = sum(c.ffe for c in delivered; init=0.0) * world.cost.port_handling_cost_per_ffe

    # 延误罚金
    late_penalty = 0.0
    for c in delivered
        created_time = c.created_week * 7.0
        actual_transit = c.sim_time - created_time
        promised = c.transit_time > 0 ? c.transit_time : 30.0
        delay = max(actual_transit - promised, 0.0)
        late_penalty += delay * c.ffe * world.cost.late_penalty_per_ffe_per_day
    end

    reject_penalty = 0.0
    trans_cost = 0.0
    wait_cost = 0.0

    net_profit = cargo_revenue - fleet_cost - sea_cost - port_handling -
                 late_penalty - reject_penalty - trans_cost - wait_cost

    return EconomicBreakdown(
        cargo_revenue, fleet_cost, sea_cost, wait_cost,
        trans_cost, port_handling, late_penalty, reject_penalty, net_profit,
    )
end

# ============================================================
# 7. 时间序列构建
# ============================================================

"""
    build_time_series(sim_events, sim_stats, sim_cargo; interval_days)
    -> Dict{String, TimeSeriesData}

从仿真结果中构建关键指标的时间序列。
"""
function build_time_series(sim_events::Vector{VesselEvent},
                           sim_stats::Vector{PortStats},
                           sim_cargo::Vector{CargoBatch};
                           interval_days::Float64=7.0)
    time_series = Dict{String, TimeSeriesData}()

    ts_delivered = TimeSeriesData("cumulative_delivered_ffe"; unit="FFE")
    ts_revenue = TimeSeriesData("cumulative_revenue"; unit="USD")
    ts_delay = TimeSeriesData("avg_delay_days"; unit="days")
    ts_port_vessels = TimeSeriesData("avg_port_vessels"; unit="vessels")
    ts_arrivals = TimeSeriesData("cumulative_arrivals"; unit="count")

    # 按时间区间聚合
    delivered = [c for c in sim_cargo if c.sim_time >= 0]
    arrivals = [e for e in sim_events if e.event_type == "ARRIVAL"]

    if !isempty(delivered)
        max_time = maximum(c.sim_time for c in delivered)
        max_time = max(max_time, maximum(e.sim_time for e in arrivals; init=1.0))

        for t in interval_days:interval_days:max_time
            # 截至时间 t 的累计交付
            cum_delivered = [c for c in delivered if c.sim_time <= t]
            cum_ffe = sum(c.ffe for c in cum_delivered; init=0.0)
            cum_revenue = sum(c.revenue_per_unit * c.ffe for c in cum_delivered; init=0.0)

            # 区间内的平均延误
            interval_cargo = [c for c in cum_delivered if c.sim_time > t - interval_days]
            avg_delay = 0.0
            for c in interval_cargo
                created_time = c.created_week * 7.0
                actual_transit = c.sim_time - created_time
                promised = c.transit_time > 0 ? c.transit_time : 30.0
                avg_delay += max(actual_transit - promised, 0.0)
            end
            if !isempty(interval_cargo)
                avg_delay /= length(interval_cargo)
            end

            # 区间内的到港事件
            cum_arrivals = count(e -> e.sim_time <= t, arrivals)

            # 区间内的平均港口船舶数
            interval_stats = [s for s in sim_stats if s.sim_time <= t]
            avg_vessels = isempty(interval_stats) ? 0.0 :
                          sum(s.vessel_count for s in interval_stats) / length(interval_stats)

            add_point!(ts_delivered, t, cum_ffe)
            add_point!(ts_revenue, t, cum_revenue)
            add_point!(ts_delay, t, avg_delay)
            add_point!(ts_arrivals, t, Float64(cum_arrivals))
            add_point!(ts_port_vessels, t, avg_vessels)
        end
    end

    time_series["cumulative_delivered_ffe"] = ts_delivered
    time_series["cumulative_revenue"] = ts_revenue
    time_series["avg_delay_days"] = ts_delay
    time_series["cumulative_arrivals"] = ts_arrivals
    time_series["avg_port_vessels"] = ts_port_vessels

    return time_series
end

# ============================================================
# 8. 完整实验分析
# ============================================================

"""
    analyze_experiment(world, plan, sim_events, sim_stats, sim_cargo;
                       experiment_id, model_name, scenario_id)
    -> ExperimentResult

对一次实验的仿真结果进行完整分析，产出所有层级的指标。
"""
function analyze_experiment(world::ShippingWorld,
                            plan::ExecutionPlan,
                            sim_events::Vector{VesselEvent},
                            sim_stats::Vector{PortStats},
                            sim_cargo::Vector{CargoBatch};
                            experiment_id::String="exp-001",
                            model_name::String="unknown",
                            scenario_id::String="baseline")
    # 需求结果
    demand_outcomes = compute_demand_outcomes(plan, sim_cargo)

    # 服务可靠性
    service_rel = compute_service_reliability(plan, sim_events)

    # 港口拥堵
    port_cong = compute_port_congestion(sim_stats)

    # 经济分析
    econ = compute_economic_breakdown(plan, sim_cargo; world=world)

    # KPI汇总
    # 先构建一个简化的 OptimizationResult 用于 compute_kpi_summary
    opt_result = OptimizationResult(
        :analyzed, 0.0,
        ServiceDecision[], DemandDecision[], DemandPath[],
        ArcUtilization[], PortFlowSummary[], econ,
        Dict{String, Float64}(),
    )
    kpi = compute_kpi_summary(opt_result, sim_events, sim_stats, sim_cargo)

    # 时间序列
    ts = build_time_series(sim_events, sim_stats, sim_cargo)

    return ExperimentResult(
        experiment_id, model_name, scenario_id,
        world, plan,
        sim_events, sim_stats, sim_cargo,
        kpi, demand_outcomes, service_rel, port_cong,
        ts, econ,
    )
end

# ============================================================
# 9. 多模型对比
# ============================================================

"""
    ModelComparison — 两个决策模型的对比结果
"""
struct ModelComparison
    model_a_name::String
    model_b_name::String
    scenario_id::String
    # KPI对比
    profit_diff::Float64           # A利润 - B利润
    on_time_diff::Float64          # A准时率 - B准时率
    utilization_diff::Float64      # A利用率 - B利用率
    reliability_diff::Float64      # A可靠性 - B可靠性
    rejection_diff::Float64        # A拒运率 - B拒运率
    # 综合评价
    winner::Symbol                 # :a / :b / :tie
    advantage_domains::Vector{String}  # A占优的领域
    disadvantage_domains::Vector{String}  # A劣势的领域
end

"""
    compare_experiments(result_a::ExperimentResult, result_b::ExperimentResult)
    -> ModelComparison

对比两个实验结果，计算差异并判断优劣。
"""
function compare_experiments(result_a::ExperimentResult, result_b::ExperimentResult)
    kpi_a = result_a.kpi
    kpi_b = result_b.kpi

    profit_diff = kpi_a.simulated_profit - kpi_b.simulated_profit
    on_time_diff = kpi_a.on_time_delivery_rate - kpi_b.on_time_delivery_rate
    utilization_diff = kpi_a.avg_utilization - kpi_b.avg_utilization
    reliability_diff = kpi_a.service_reliability - kpi_b.service_reliability
    rejection_diff = kpi_a.rejection_rate - kpi_b.rejection_rate

    # 综合评分（简单加权）
    score_a = kpi_a.on_time_delivery_rate * 0.3 +
              kpi_a.service_reliability * 0.3 +
              (1.0 - kpi_a.rejection_rate) * 0.2 +
              min(kpi_a.avg_utilization, 1.0) * 0.2

    score_b = kpi_b.on_time_delivery_rate * 0.3 +
              kpi_b.service_reliability * 0.3 +
              (1.0 - kpi_b.rejection_rate) * 0.2 +
              min(kpi_b.avg_utilization, 1.0) * 0.2

    winner = abs(score_a - score_b) < 0.01 ? :tie : (score_a > score_b ? :a : :b)

    # 分析占优领域
    advantage = String[]
    disadvantage = String[]

    if profit_diff > 0 push!(advantage, "profit") else push!(disadvantage, "profit") end
    if on_time_diff > 0 push!(advantage, "on_time_delivery") else push!(disadvantage, "on_time_delivery") end
    if utilization_diff > 0 push!(advantage, "utilization") else push!(disadvantage, "utilization") end
    if reliability_diff > 0 push!(advantage, "reliability") else push!(disadvantage, "reliability") end
    if rejection_diff < 0 push!(advantage, "rejection") else push!(disadvantage, "rejection") end

    return ModelComparison(
        result_a.model_name, result_b.model_name,
        result_a.scenario_id,
        profit_diff, on_time_diff, utilization_diff,
        reliability_diff, rejection_diff,
        winner, advantage, disadvantage,
    )
end

# ============================================================
# 10. 鲁棒性分析
# ============================================================

"""
    RobustnessAnalysis — 同一模型在不同扰动强度下的鲁棒性分析
"""
struct RobustnessAnalysis
    model_name::String
    scenario_ids::Vector{String}
    disruption_levels::Vector{Float64}
    # 各扰动水平下的关键KPI
    profits::Vector{Float64}
    on_time_rates::Vector{Float64}
    reliability_rates::Vector{Float64}
    rejection_rates::Vector{Float64}
    # 鲁棒性指标
    profit_retention::Float64       # 最高扰动下利润保留率
    on_time_degradation::Float64    # 准时率退化斜率
    reliability_degradation::Float64 # 可靠性退化斜率
    robustness_score::Float64       # 综合鲁棒性得分 [0,1]
end

"""
    analyze_robustness(results::Vector{ExperimentResult}) -> RobustnessAnalysis

分析同一模型在不同扰动水平下的表现退化，计算鲁棒性指标。
"""
function analyze_robustness(results::Vector{ExperimentResult})
    # 按扰动水平排序
    sorted = sort(results; by=r -> r.world.disruption_level)

    model_name = isempty(sorted) ? "unknown" : first(sorted).model_name
    scenario_ids = [r.scenario_id for r in sorted]
    disruption_levels = [r.world.disruption_level for r in sorted]
    profits = [r.kpi.simulated_profit for r in sorted]
    on_time_rates = [r.kpi.on_time_delivery_rate for r in sorted]
    reliability_rates = [r.kpi.service_reliability for r in sorted]
    rejection_rates = [r.kpi.rejection_rate for r in sorted]

    # 利润保留率：最高扰动下的利润 / 基准利润
    base_profit = isempty(profits) ? 0.0 : first(profits)
    worst_profit = isempty(profits) ? 0.0 : last(profits)
    profit_retention = base_profit != 0 ? worst_profit / base_profit : 0.0

    # 退化斜率（简单线性回归）
    on_time_degradation = _simple_slope(disruption_levels, on_time_rates)
    reliability_degradation = _simple_slope(disruption_levels, reliability_rates)

    # 综合鲁棒性得分
    robustness_score = clamp(
        0.4 * clamp(profit_retention, 0, 1) +
        0.3 * clamp(1.0 + on_time_degradation, 0, 1) +   # 斜率越负越差
        0.3 * clamp(1.0 + reliability_degradation, 0, 1),
        0.0, 1.0,
    )

    return RobustnessAnalysis(
        model_name, scenario_ids, disruption_levels,
        profits, on_time_rates, reliability_rates, rejection_rates,
        profit_retention, on_time_degradation, reliability_degradation,
        robustness_score,
    )
end

"""简单线性回归斜率"""
function _simple_slope(x::Vector{Float64}, y::Vector{Float64})
    n = length(x)
    n < 2 && return 0.0
    mx = sum(x) / n
    my = sum(y) / n
    sxx = sum((xi - mx)^2 for xi in x)
    sxy = sum((x[i] - mx) * (y[i] - my) for i in 1:n)
    return sxx > 0 ? sxy / sxx : 0.0
end

# ============================================================
# 11. 批量实验运行
# ============================================================

"""
    run_experiment(world::ShippingWorld, model::AbstractDecisionModel;
                   scenario_id, max_time, max_steps)
    -> ExperimentResult

运行一次完整实验：决策 → 仿真 → 分析
"""
function run_experiment(world::ShippingWorld,
                        model::AbstractDecisionModel;
                        scenario_id::String="baseline",
                        max_time::Float64=200.0,
                        max_steps::Int=10000)
    # Step 1: 求解决策
    plan = solve_decision(model, world; scenario_id=scenario_id)

    # Step 2: 注入仿真并运行
    sim_result = run_simulation(world, plan; max_time=max_time, max_steps=max_steps)

    # Step 3: 分析结果
    exp_id = string(model_name(model), "_", scenario_id, "_", world.disruption_level)
    result = analyze_experiment(
        world, plan,
        sim_result.events, sim_result.stats, sim_result.cargo;
        experiment_id=exp_id,
        model_name=model_name(model),
        scenario_id=scenario_id,
    )

    return result
end

"""
    run_comparison(world::ShippingWorld, models::Vector{AbstractDecisionModel};
                   scenario_id, max_time, max_steps)
    -> Vector{ExperimentResult}

在同一世界模型下运行多个决策模型，产出可对比的实验结果。
"""
function run_comparison(world::ShippingWorld,
                        models::Vector{<:AbstractDecisionModel};
                        scenario_id::String="baseline",
                        max_time::Float64=200.0,
                        max_steps::Int=10000)
    results = ExperimentResult[]
    for model in models
        result = run_experiment(world, model;
            scenario_id=scenario_id,
            max_time=max_time,
            max_steps=max_steps,
        )
        push!(results, result)
    end
    return results
end

"""
    run_robustness_study(world::ShippingWorld, model::AbstractDecisionModel;
                         disruption_levels, scenario_id, max_time, max_steps)
    -> RobustnessAnalysis

对同一模型在不同扰动水平下运行实验，分析鲁棒性。
"""
function run_robustness_study(world::ShippingWorld,
                              model::AbstractDecisionModel;
                              disruption_levels::Vector{Float64}=[0.0, 0.5, 1.0, 2.0, 3.0],
                              scenario_id::String="baseline",
                              max_time::Float64=200.0,
                              max_steps::Int=10000)
    results = ExperimentResult[]
    for dl in disruption_levels
        # 创建不同扰动水平的世界
        disrupted_world = ShippingWorld(
            ports=world.ports,
            vessels=world.vessels,
            demands=world.demands,
            services=world.services,
            disruptions=world.disruptions,
            cost=world.cost,
            time=world.time,
            kpi=world.kpi,
            scenario_id=world.scenario_id,
            description=world.description,
            demand_multiplier=world.demand_multiplier,
            capacity_multiplier=world.capacity_multiplier,
            disruption_level=dl,
        )

        result = run_experiment(disrupted_world, model;
            scenario_id=scenario_id,
            max_time=max_time,
            max_steps=max_steps,
        )
        push!(results, result)
    end

    return analyze_robustness(results)
end

# ============================================================
# 12. 结果导出
# ============================================================

"""
    experiment_summary(result::ExperimentResult) -> Dict

将实验结果转换为 JSON 友好的字典。
"""
function experiment_summary(result::ExperimentResult)
    return Dict{String, Any}(
        "experiment_id" => result.experiment_id,
        "model_name" => result.model_name,
        "scenario_id" => result.scenario_id,
        "disruption_level" => result.world.disruption_level,
        "kpi" => kpi_summary_dict(result.kpi),
        "demand_outcomes_count" => length(result.demand_outcomes),
        "on_time_count" => count(o -> o.is_on_time, result.demand_outcomes),
        "delivered_count" => count(o -> o.is_delivered, result.demand_outcomes),
        "economic_breakdown" => Dict{String, Float64}(
            "cargo_revenue" => result.economic_breakdown.cargo_revenue,
            "fleet_deployment_cost" => result.economic_breakdown.fleet_deployment_cost,
            "sea_transport_cost" => result.economic_breakdown.sea_transport_cost,
            "port_handling_cost" => result.economic_breakdown.port_handling_cost,
            "late_penalty" => result.economic_breakdown.late_penalty,
            "net_profit" => result.economic_breakdown.net_profit,
        ),
        "time_series_metrics" => collect(keys(result.time_series)),
    )
end

"""
    comparison_table(results::Vector{ExperimentResult}) -> Vector{Dict}

将多个实验结果格式化为对比表格。
"""
function comparison_table(results::Vector{ExperimentResult})
    return [experiment_summary(r) for r in results]
end

"""
    robustness_summary(ra::RobustnessAnalysis) -> Dict

将鲁棒性分析结果转换为字典。
"""
function robustness_summary(ra::RobustnessAnalysis)
    return Dict{String, Any}(
        "model_name" => ra.model_name,
        "disruption_levels" => ra.disruption_levels,
        "profits" => ra.profits,
        "on_time_rates" => ra.on_time_rates,
        "reliability_rates" => ra.reliability_rates,
        "rejection_rates" => ra.rejection_rates,
        "profit_retention" => ra.profit_retention,
        "on_time_degradation_slope" => ra.on_time_degradation,
        "reliability_degradation_slope" => ra.reliability_degradation,
        "robustness_score" => ra.robustness_score,
    )
end
