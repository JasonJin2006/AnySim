
# ============================================================
# demo_framework.jl — 新架构端到端演示
#
# 展示五层架构的完整使用方式：
#   A. 构建统一世界模型
#   B. 选择/切换决策模型
#   C. 生成执行计划
#   D. 注入仿真运行
#   E. 分析结果、对比模型、评估鲁棒性
# ============================================================
include(joinpath(@__DIR__, "..", "..", "src", "AnySim.jl"))
using .AnySim
include(joinpath(@__DIR__, "..", "..", "extensions", "DEVS", "DEVS.jl"))
using .DEVS
include(joinpath(@__DIR__, "..", "..", "extensions", "Shipping", "Shipping.jl"))
using .Shipping

data_dir = joinpath(@__DIR__, "..", "..", "data", "shipping")
schedule_file = joinpath(data_dir, "航线船期_20260507_ych.csv")
od_file = joinpath(data_dir, "od对需求_20260507_ych.csv")

println("=" ^ 70)
println("  AnySim 班轮航运研究框架 — 五层架构演示")
println("=" ^ 70)

# ============================================================
# A. 世界定义层 — 构建统一航运世界模型
# ============================================================
println("
[A层] 构建统一航运世界模型...")

world = build_shipping_world(schedule_file, od_file;
    scenario_id="demo",
    description="五层架构演示",
    demand_multiplier=1.0,
    disruption_level=0.0,
    cycle_days=7,
    horizon_cycles=4,
)

println("  港口数: $(length(world.ports))")
println("  服务数: $(length(world.services))")
println("  船型数: $(length(world.vessels))")
println("  需求数: $(length(world.demands))")
println("  扰动数: $(length(world.disruptions))")
println("  服务列表:")
for (sid, svc) in sort(collect(world.services))
    println("    $sid: $(length(svc.port_calls))港, $(svc.route_total_days)天/圈, 需$(svc.required_vessels)艘")
end

# ============================================================
# B. 决策建模层 — 选择运筹学模型
# ============================================================
println("
[B层] 选择决策模型...")

# 注册所有可用模型
registry = default_registry()
println("  可用决策模型: ", list_models(registry))

# 选择三个模型进行对比
milp_model = get_model(registry, "TimeSpaceMILP")
simple_model = get_model(registry, "SimpleDirectAllocation")
greedy_model = get_model(registry, "GreedyHeuristic")

println("
  模型1: $(model_description(milp_model))")
println("    能力: ", model_capabilities(milp_model))
println("    决策变量: ", decision_variables(milp_model))

println("
  模型2: $(model_description(simple_model))")
println("    能力: ", model_capabilities(simple_model))

println("
  模型3: $(model_description(greedy_model))")
println("    能力: ", model_capabilities(greedy_model))

# ============================================================
# C. 计划生成层 — 求解决策模型，生成 ExecutionPlan
# ============================================================
println("
[C层] 求解决策模型，生成执行计划...")

# 用简化模型快速生成计划（MILP可能需要较长时间）
plan_simple = solve_decision(simple_model, world; scenario_id="demo")
println("  SimpleDirectAllocation 计划:")
println("    服务数: $(length(plan_simple.planned_services))")
println("    船舶旋转: $(length(plan_simple.planned_rotations))")
println("    需求分配: $(length(plan_simple.planned_assignments))")
println("    求解状态: $(plan_simple.meta.solve_status)")

# 用贪心模型生成计划
plan_greedy = solve_decision(greedy_model, world; scenario_id="demo")
println("
  GreedyHeuristic 计划:")
println("    服务数: $(length(plan_greedy.planned_services))")
println("    船舶旋转: $(length(plan_greedy.planned_rotations))")
println("    需求分配: $(length(plan_greedy.planned_assignments))")

# ============================================================
# D. 仿真执行层 — 将计划注入仿真
# ============================================================
println("
[D层] 将执行计划注入仿真...")

# 构建仿真模型
sim_model = inject_plan(world, plan_simple)
println("  仿真模型: $(sim_model.name)")
println("  实体数: $(length(sim_model.entities))")
println("  连接数: $(length(sim_model.connections))")

# 运行仿真
println("
  运行仿真...")
sim_result = run_simulation(world, plan_simple; max_time=100.0, max_steps=5000)
println("  仿真事件: $(length(sim_result.events))")
println("  港口统计: $(length(sim_result.stats))")
println("  货物记录: $(length(sim_result.cargo))")

# ============================================================
# E. 结果分析层 — 分析、对比、评估鲁棒性
# ============================================================
println("
[E层] 分析结果...")

# 完整分析
exp_result = analyze_experiment(
    world, plan_simple,
    sim_result.events, sim_result.stats, sim_result.cargo;
    experiment_id="simple-demo",
    model_name="SimpleDirectAllocation",
    scenario_id="demo",
)

println("  KPI汇总:")
println("    计划利润: $(exp_result.kpi.planned_profit)")
println("    仿真利润: $(exp_result.kpi.simulated_profit)")
println("    利润保留率: $(exp_result.kpi.profit_retention_rate)")
println("    准时交付率: $(exp_result.kpi.on_time_delivery_rate)")
println("    平均运输时间: $(exp_result.kpi.avg_transit_time)")
println("    平均利用率: $(exp_result.kpi.avg_utilization)")
println("    拒运率: $(exp_result.kpi.rejection_rate)")

println("
  需求结果:")
on_time_count = count(o -> o.is_on_time, exp_result.demand_outcomes)
delivered_count = count(o -> o.is_delivered, exp_result.demand_outcomes)
println("    总需求: $(length(exp_result.demand_outcomes))")
println("    已交付: $delivered_count")
println("    准时: $on_time_count")

println("
  服务可靠性:")
for sr in exp_result.service_reliability
    println("    $(sr.service_id): 可靠性=$(round(sr.reliability_rate; digits=3)), 计划=$(sr.planned_calls), 实际=$(sr.on_time_calls)")
end

println("
  经济分解:")
eb = exp_result.economic_breakdown
println("    货运收入: $(round(eb.cargo_revenue; digits=2))")
println("    船队成本: $(round(eb.fleet_deployment_cost; digits=2))")
println("    海运成本: $(round(eb.sea_transport_cost; digits=2))")
println("    港口操作: $(round(eb.port_handling_cost; digits=2))")
println("    延误罚金: $(round(eb.late_penalty; digits=2))")
println("    净利润: $(round(eb.net_profit; digits=2))")

# ============================================================
# 多模型对比
# ============================================================
println("
" * "=" ^ 70)
println("  多模型对比")
println("=" ^ 70)

# 用两个模型运行完整实验
println("
运行 SimpleDirectAllocation 实验...")
exp_simple = run_experiment(world, simple_model;
    scenario_id="demo", max_time=100.0, max_steps=5000)

println("运行 GreedyHeuristic 实验...")
exp_greedy = run_experiment(world, greedy_model;
    scenario_id="demo", max_time=100.0, max_steps=5000)

# 对比
comparison = compare_experiments(exp_simple, exp_greedy)
println("
对比结果: $(comparison.model_a_name) vs $(comparison.model_b_name)")
println("  利润差: $(round(comparison.profit_diff; digits=2))")
println("  准时率差: $(round(comparison.on_time_diff; digits=4))")
println("  利用率差: $(round(comparison.utilization_diff; digits=4))")
println("  可靠性差: $(round(comparison.reliability_diff; digits=4))")
println("  胜者: $(comparison.winner)")
println("  A占优领域: $(comparison.advantage_domains)")
println("  A劣势领域: $(comparison.disadvantage_domains)")

# ============================================================
# 鲁棒性分析
# ============================================================
println("
" * "=" ^ 70)
println("  鲁棒性分析")
println("=" ^ 70)

println("
在不同扰动水平下测试 SimpleDirectAllocation...")
robustness = run_robustness_study(world, simple_model;
    disruption_levels=[0.0, 0.5, 1.0, 2.0],
    scenario_id="demo",
    max_time=100.0,
    max_steps=5000,
)

println("
鲁棒性分析结果:")
for (i, dl) in enumerate(robustness.disruption_levels)
    println("  扰动水平=$dl: 利润=$(round(robustness.profits[i]; digits=2)), " *
            "准时率=$(round(robustness.on_time_rates[i]; digits=3)), " *
            "可靠性=$(round(robustness.reliability_rates[i]; digits=3))")
end
println("
  利润保留率: $(round(robustness.profit_retention; digits=3))")
println("  准时率退化斜率: $(round(robustness.on_time_degradation; digits=4))")
println("  可靠性退化斜率: $(round(robustness.reliability_degradation; digits=4))")
println("  综合鲁棒性得分: $(round(robustness.robustness_score; digits=3))")

println("
" * "#" ^ 70)
println("  五层架构演示完成!")
println("=" ^ 70)
