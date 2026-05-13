
# 班轮航运系统研究框架 — 五层架构设计

## 概述

本框架基于以下方法论：

> 本研究首先构建一个统一的班轮航运系统描述框架，对船舶、港口、货物、服务网络、时间结构、成本要素、扰动机制及评价指标进行完整定义。在此基础上，不同运筹学决策模型可作为可替换模块，对其中一部分可决策参数进行求解，并将结果统一映射为执行计划注入仿真系统。仿真系统在给定扰动与恢复规则下执行计划，并输出多层级、多时段的运营结果，最终用于评价不同决策模型的执行效果与鲁棒性。

## 五层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    E. 结果分析层                              │
│   分析结果、时间分布、偏差传播、鲁棒性、模型对比               │
├─────────────────────────────────────────────────────────────┤
│                    D. 仿真执行层                              │
│   把计划注入仿真，在扰动和恢复规则下执行                       │
├─────────────────────────────────────────────────────────────┤
│                 C. 计划生成层 (桥梁)                           │
│   把不同运筹学模型的解统一转换成可执行计划 (ExecutionPlan)      │
├─────────────────────────────────────────────────────────────┤
│                    B. 决策建模层                              │
│   在世界定义层上，针对某一类问题建立运筹学模型                  │
│   允许存在多个可替换的模型版本                                 │
├─────────────────────────────────────────────────────────────┤
│                    A. 世界定义层                              │
│   定义系统中所有对象、状态、参数、关系、约束背景                │
└─────────────────────────────────────────────────────────────┘
```

## A. 世界定义层 (`world.jl`)

### 设计原则

1. **世界模型尽量完整**，具体决策模型只取自己需要的那部分（投影）
2. 属性分为**外生(exogenous)**和**内生(endogenous)**两类
3. 外生参数直接给定，内生参数由运筹学模型或仿真算出
4. 每个属性标注其所属层级：`:world` / `:decision` / `:simulation`

### 对象总表

| 对象 | 类型 | 外生参数 | 内生参数(决策) | 内生参数(仿真) |
|------|------|---------|--------------|--------------|
| 港口 | `PortSpec` | 位置、能力、成本、扰动参数 | — | 实际拥堵、吞吐量 |
| 船型 | `VesselSpec` | 容量、性能、成本、可用数 | 部署状态 | 实际航行时间 |
| 需求 | `DemandSpec` | OD、量、时间窗、优先级 | 是否接受、路径 | 实际到达、是否准时 |
| 服务 | `ServiceSpec` | 靠港序列、时间结构 | 是否开通、船型、船数 | 实际可靠性 |
| 扰动 | `DisruptionSpec` | 类型、范围、影响程度 | — | 实际影响 |
| 成本 | `CostSpec` | 全部外生 | — | — |
| 时间 | `TimeSpec` | 全部外生 | — | — |
| KPI | `KpiSpec` | 指标开关 | — | 指标值 |

### 投影机制

```julia
# 每个决策模型从完整世界投影自己需要的子集
proj = WorldProjection(world;
    include_time_windows=true,
    include_transshipment=true,
    include_capacity=true,
    include_port_congestion=false,
    include_disruption=false,
)
```

## B. 决策建模层 (`decision_interface.jl`)

### 抽象接口

```julia
abstract type AbstractDecisionModel end

# 必须实现
model_name(model) :: String
model_version(model) :: String
model_capabilities(model) :: Vector{Symbol}
decision_variables(model) :: Vector{Symbol}
required_projection(model, world) :: WorldProjection
solve_decision(model, world; scenario_id) :: ExecutionPlan
```

### 已实现模型

| 模型 | 类型 | 能力 | 决策变量 |
|------|------|------|---------|
| `TimeSpaceMILPModel` | 精确 | 服务选择、船型分配、货流路径、中转、时间窗 | service_active, fleet_type, vessel_count, cargo_flow, demand_accepted |
| `SimpleDirectAllocationModel` | 启发式 | 直达货流分配、容量 | cargo_flow, demand_accepted |
| `GreedyHeuristicModel` | 启发式 | 贪心分配、优先级排序 | cargo_flow, demand_accepted |

### 能力标签

```
CAP_SERVICE_ACTIVATION  — 服务是否开通
CAP_FLEET_DEPLOYMENT    — 配什么船型
CAP_VESSEL_COUNT        — 投几艘船
CAP_DEMAND_ACCEPTANCE   — 哪些货接不接
CAP_CARGO_ROUTING       — 货怎么走
CAP_TRANSSHIPMENT       — 是否允许中转
CAP_TIME_WINDOWS        — 是否考虑时间窗
CAP_CAPACITY            — 是否考虑容量约束
CAP_ROBUST              — 鲁棒优化
CAP_STOCHASTIC          — 随机规划
CAP_HEURISTIC           — 启发式
CAP_EXACT               — 精确方法
```

## C. 计划生成层 (已有 `ExecutionPlan`)

### 统一输出格式

```julia
struct ExecutionPlan
    meta::PlanMeta
    planned_services::Vector{PlannedService}       # 服务开通与船型分配
    planned_rotations::Vector{PlannedVesselRotation} # 船舶旋转计划
    planned_assignments::Vector{PlannedDemandAssignment} # 需求分配与路径
end
```

**关键解耦**：仿真层只读取 `ExecutionPlan`，不关心它由哪个模型产生。

## D. 仿真执行层 (`simulation_bridge.jl`)

### 注入管道

```julia
# 将 ExecutionPlan 转换成 DEVS 仿真模型
model = inject_plan(world, plan)

# 运行仿真
sim_result = run_simulation(world, plan; max_time=200.0)

# 或一步到位：决策 → 仿真
result = run_decision_and_simulate(model, world; scenario_id="baseline")
```

### 扰动注入

- 从 `DisruptionSpec` 计算航行/港口延误因子
- 支持全局扰动和按港口分别的扰动
- 多个扰动叠加时取最大影响

## E. 结果分析层 (`analysis.jl`)

### 分析维度

1. **需求结果**：每条需求的计划vs实际（交付量、到达时间、延误）
2. **服务可靠性**：每条服务的准时率、延误率、缺失率
3. **港口拥堵**：到港次数、峰值船舶数、等待时间
4. **经济分解**：收入、船队成本、海运成本、港口成本、罚金、净利润
5. **时间序列**：累计交付量、收入、延误、港口船舶数随时间的演化

### 多模型对比

```julia
# 在同一世界下运行多个模型
results = run_comparison(world, [milp_model, simple_model, greedy_model])

# 两两对比
comparison = compare_experiments(results[1], results[2])
# → profit_diff, on_time_diff, winner, advantage_domains
```

### 鲁棒性分析

```julia
# 同一模型在不同扰动水平下
robustness = run_robustness_study(world, model;
    disruption_levels=[0.0, 0.5, 1.0, 2.0, 3.0])
# → profit_retention, degradation_slopes, robustness_score
```

## 完整使用流程

```julia
# 1. 构建世界
world = build_shipping_world(schedule_file, od_file;
    scenario_id="baseline", disruption_level=0.0)

# 2. 选择决策模型
model = TimeSpaceMILPModel(allow_transshipment=true)

# 3. 求解 → 生成计划
plan = solve_decision(model, world; scenario_id="baseline")

# 4. 注入仿真 → 运行
sim_result = run_simulation(world, plan; max_time=200.0)

# 5. 分析结果
result = analyze_experiment(world, plan,
    sim_result.events, sim_result.stats, sim_result.cargo)

# 6. 多模型对比
comparison = run_comparison(world, [
    TimeSpaceMILPModel(),
    SimpleDirectAllocationModel(),
    GreedyHeuristicModel(),
])

# 7. 鲁棒性分析
robustness = run_robustness_study(world, model;
    disruption_levels=[0.0, 0.5, 1.0, 2.0])
```

## 文件组织

```
extensions/Shipping/
├── world.jl              ← A层: 统一世界模型 (679行)
├── decision_interface.jl ← B层: 决策模型抽象接口 (672行)
├── optimization.jl       ← B层: MILP构建 (已有, 被TimeSpaceMILPModel包装)
├── simulation_bridge.jl  ← C→D层: 计划→仿真注入管道 (391行)
├── analysis.jl           ← E层: 结果分析与对比 (766行)
├── types.jl              ← 仿真层轻量类型 (已有)
├── models.jl             ← DEVS原子模型 (已有)
├── plugin.jl             ← 扩展插件入口 (已更新)
├── exports.jl            ← 导出函数 (已有)
└── Shipping.jl           ← 模块定义 (已更新)
```

## 学术价值

本框架的学术叙事不再是"我做了一个模型"，而是：

**"我构建了一个统一评估框架，并比较不同决策方法在同一运营环境中的效果。"**

这使得研究层次从"单一模型"提升到"方法论框架"，具有更强的学术贡献。
