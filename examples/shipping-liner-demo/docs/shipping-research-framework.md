# Shipping Research Framework

## 1. Research Goal

This project should evolve from a schedule-driven event replay demo into an academic-grade
"optimization + simulation" framework for liner shipping.

The target problem is:

Fixed-service liner shipping network optimization with explicit time-space modeling,
fleet deployment, and cargo flow assignment, followed by disruption-aware simulation
to evaluate plan robustness.

The core principle is:

- Optimization decides what the plan should be.
- Simulation evaluates whether the plan can be executed under disturbances.


## 2. Current Project Status

The current codebase now contains:

- route schedule loading and normalized input modeling (aligned with §6)
- OD demand loading with full OptimizationDemand fields
- DEVS-based vessel / port / demand simulation with disturbance support
- shipping result export and KPI summaries
- time-space network optimization with MILP specification
- solver integration (GLPK external solver + LP relaxation fallback)
- execution plan generation (bridge between optimization and simulation)
- optimization output types (ServiceDecision, DemandDecision, DemandPath, etc.)
- simulation output types (DemandOutcome, ServiceReliability, PortCongestion)
- KPI summary with planned-vs-realized comparison
- disturbance-aware simulation (disturbance_factor, port_disturbance_factor)
- shipping-optimization preset for end-to-end optimization→simulation workflow

Remaining gaps:

- execution plan is not yet consumed by simulation to override schedule-driven behavior
- global rerouting recovery is not implemented (only local delay propagation)
- empty container repositioning is still ignored
- stochastic demand arrival disturbance is not yet in the demand generator

Recent semantic fixes already applied to the DEVS demo layer:

- port statistics now emit actual event time instead of a constant `0.0`
- in-port vessel count now increments on arrival and decrements on departure
- discharged cargo totals are now reported with clearer semantics


## 3. Research Problem Definition

The proposed V1 academic problem is:

Joint fleet deployment and cargo flow assignment in a fixed liner service network
with release times, delivery deadlines, and explicit time-space network representation.

Assumptions for V1:

- service structure is known
- port sequence is fixed
- discrete time is used
- cargo can be split
- at most limited transshipment is allowed
- empty container repositioning is ignored
- stochastic disruptions are not part of the optimization layer
- disruptions are introduced only in the simulation layer


## 4. Time Modeling

Time should be modeled using a discrete periodic time-space network.

Recommended baseline:

- time unit: 1 day
- cycle length: 7 days
- planning horizon: multiple cycles

Nodes are expanded by port and absolute cycle layer:

- node = (port, time_slot_in_cycle, cycle_layer)

This is preferred over a pure modulo-time model because:

- cargo with release time and due time can be represented correctly
- cross-cycle movement remains valid
- flow conservation remains consistent

Arc types:

- sea arcs
- waiting arcs
- transshipment arcs


## 5. Optimization Model

### 5.1 Decision Scope

The optimization layer should determine:

- which services are active
- which fleet type is assigned to each service
- how many service strings are deployed
- which demand is accepted
- how accepted demand is routed through the time-space network

### 5.2 Core Variables

Suggested V1 variables:

- service activation variable
- service-fleet deployment variable
- accepted demand variable
- demand flow on arcs
- sink absorption variable

### 5.3 Objective

Primary objective:

maximize profit

Profit should include:

- cargo revenue
- fleet deployment cost
- sea transport cost
- waiting cost
- transshipment cost
- optional rejection or lateness penalties

### 5.4 Core Constraints

V1 should include:

- demand acceptance bounds
- flow conservation
- sink absorption balance
- sea arc capacity constraints
- fleet availability constraints
- service activation / deployment consistency


## 6. Input Modeling

The input layer should be normalized into six major tables / objects.

### 6.1 Service

Fields include:

- service_id
- service_name
- cycle_days
- frequency_days
- round_trip_days
- required_vessels
- allowed_fleet_types
- is_active_candidate

### 6.2 ServiceLeg

Fields include:

- service_id
- leg_index
- origin_port
- destination_port
- depart_day_in_cycle
- arrival_day_in_cycle
- sailing_days
- port_stay_days
- is_transshipment_allowed

### 6.3 FleetType

Fields include:

- fleet_id
- fleet_name
- capacity_ffe
- available_units
- fixed_deployment_cost
- sailing_cost_per_day
- port_call_cost
- max_service_days
- speed_class

### 6.4 Demand

Fields include:

- demand_id
- origin_port
- destination_port
- quantity_ffe
- release_time
- due_time
- revenue_per_ffe
- priority_class
- max_transshipments
- is_mandatory
- reject_penalty_per_ffe

### 6.5 CostConfig

Fields include:

- sea_cost_per_day
- wait_cost_per_day
- trans_cost_per_day
- port_handling_cost_per_ffe
- late_penalty_per_ffe
- reject_penalty_per_ffe

### 6.6 ScenarioConfig

Fields include:

- scenario_id
- description
- cycle_days
- horizon_cycles
- demand_periods
- min_connection_time
- due_slack_days
- demand_multiplier
- capacity_multiplier
- disruption_level


## 7. Output Analysis

The output layer should distinguish optimization outputs from simulation outputs.

### 7.1 Optimization Outputs

Recommended result objects:

- ServiceDecision
- DemandDecision
- DemandPath
- ArcUtilization
- PortFlowSummary
- EconomicBreakdown

These should support:

- service-level analysis
- demand-level analysis
- network bottleneck analysis
- economic interpretation

### 7.2 Simulation Outputs

Recommended result objects:

- SimulationEvent
- DemandOutcome
- ServiceReliability
- PortCongestion

### 7.3 KPI Summary

A top-level experiment KPI table should include:

- planned profit
- simulated profit
- profit retention rate
- accepted cargo
- delivered cargo
- on-time delivery rate
- average transit time
- average utilization
- maximum arc utilization
- service reliability
- rejection rate


## 8. Bridge Between Optimization and Simulation

Optimization output should not be passed directly as raw model variables.

Instead, it should be translated into an execution plan.

The execution plan is the contract between planning and simulation.

Recommended components:

- PlannedService
- PlannedVesselRotation
- PlannedCall
- PlannedDemandAssignment
- PlannedPathLeg
- optional PlannedPortOperation
- PlanMeta

The execution plan should encode:

- which services are opened
- which fleet type is used
- how many vessel instances exist
- when each vessel should call each port
- how each demand is planned to move through the network


## 9. Simulation Layer

The simulation layer should validate the optimization plan under disturbances.

It should not silently replace optimization by re-optimizing globally.

### 9.1 Disturbance Types

Recommended V1 disturbances:

- sea travel time disturbance
- port operation disturbance
- demand arrival disturbance
- missed transshipment connection

### 9.2 Recovery Rules

Recommended V1 recovery rules:

- delay propagation / schedule shifting
- limited waiting for missed connection
- rollover to next feasible service cycle
- no global rerouting

V1 should stay conservative:

- local recovery allowed
- full network re-optimization not allowed


## 10. Academic Experiment Logic

The recommended experiment ladder is:

1. no disruption, compare optimization plan and simulation replay
2. disruption without recovery
3. disruption with basic recovery
4. disruption with stronger recovery in later versions

This allows the study to isolate:

- intrinsic plan quality
- disruption sensitivity
- recovery value


## 11. Software Architecture Direction

The desired architecture is:

1. Raw data layer
   - original CSV / Excel inputs

2. Normalized input layer
   - Service
   - ServiceLeg
   - FleetType
   - Demand
   - CostConfig
   - ScenarioConfig

3. Optimization layer
   - time-space network
   - model data
   - MILP specification

4. Execution-plan layer
   - planned service
   - planned vessel rotations
   - planned cargo pathing

5. Simulation layer
   - disturbed execution
   - delay propagation
   - cargo realization

6. Analysis layer
   - KPI summary
   - planned vs realized comparison
   - robustness evaluation


## 12. Current Code Mapping

Current mapping in this repository:

- `RouteSchedule` and `PortCall` are the main inputs for service structure
- `ODDemand` is the raw demand input, normalized into `OptimizationDemand` with full fields
- `ShippingService`, `ServiceLeg`, `FleetType`, `CostConfig`, `ScenarioConfig` are now aligned with §6
- `extensions/Shipping/models.jl` contains the DEVS simulation entities with disturbance support
- `extensions/Shipping/optimization.jl` now contains:
  - optimization-layer data structures (aligned with §6)
  - time-space network builder
  - MILP specification builder
  - LP / JSON export support
  - project-level optimization artifact export
  - solver integration (`solve_milp_from_lp` with GLPK + fallback)
  - optimization result extraction (`extract_optimization_result`)
  - execution plan generation (`build_execution_plan`, `build_execution_plan_from_artifacts`)
  - KPI analysis (`compute_kpi_summary`, `compute_demand_outcomes`, etc.)
  - simulation output types (`DemandOutcome`, `ServiceReliability`, `PortCongestion`)
- `extensions/Shipping/plugin.jl` now supports `shipping-optimization` preset
- Frontend extension now includes `disruption_level` configuration


## 13. Immediate Next Steps

Recommended next implementation priorities:

1. ~~formalize normalized input objects and conversion pipeline~~ (DONE)
2. ~~generate execution plans from optimization solutions~~ (DONE)
3. adapt shipping simulation to consume execution plans (override schedule-driven behavior)
4. ~~add disturbance and recovery logic to the simulation layer~~ (disturbance factors added; recovery rules pending)
5. ~~build planned-vs-realized KPI analysis~~ (DONE)
6. implement local recovery rules (delay propagation, rollover to next cycle)
7. add demand arrival disturbance to DemandGenerator
8. implement empty container repositioning (V2)


## 14. Research Positioning

If implemented well, this project can support a research narrative of:

time-space network optimization for liner shipping, combined with disturbance-aware
execution simulation for robustness evaluation.

That is academically stronger than:

- pure event replay simulation
- pure deterministic network optimization

---

## Appendix A: Architecture Debt — Frontend View Decoupling

**Status**: Open  
**Added**: 2026-05-12

### Problem

Frontend views (`ShippingNetworkView`, `PortKpiPanel`, `VesselTimelineView`, `ExperimentResultView`) are hardcoded in `frontend/extensions/shipping/index.ts`. They should be loaded from the project directory, just as model files are now loaded from `examples/shipping-liner-demo/model/`.

### Root Cause

Next.js is a compile-time bundler. Unlike Julia's runtime `include()`, React components must be available at build time. The extension registry (`frontend/extensions/registry.ts`) statically imports `shippingExtension`, making it impossible to add project-specific views without modifying frontend source code.

### Current Workaround

- View source files are copied to `examples/shipping-liner-demo/views/` as reference
- `anysim-project.json` declares `views[].source` pointing to these files
- Frontend still loads views from hardcoded `frontend/extensions/shipping/`

### Proposed Solution

1. **Project-driven view discovery**: Implement a frontend project reader that parses `anysim-project.json` and dynamically registers views
2. **Dynamic import**: Use Next.js `dynamic(() => import(...))` to lazy-load view components from project directories
3. **Registry refactor**: Change `registry.ts` to merge platform extensions with project-specific views
4. **Extension API**: Add a `registerViews()` API so projects can contribute custom views without modifying core code

### Impact

Without this change, every new shipping project must either:
- Duplicate view code in the frontend extension, or
- Modify the extension source to support new view types

This limits the platform's extensibility and violates the "project as self-contained unit" principle established in Phase 1–2.

