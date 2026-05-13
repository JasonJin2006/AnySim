# ============================================================
# types.jl — 海运仿真领域数据类型
# ============================================================

struct PortCall
    port_code::String
    port_order::Int
    eta_day::Float64
    etd_day::Union{Float64, Nothing}
end

function duration(pc::PortCall)
    pc.etd_day === nothing && return 0.0
    return pc.etd_day - pc.eta_day
end

struct RouteSchedule
    route_id::String
    port_calls::Vector{PortCall}
    total_days::Float64
end

function ports(route::RouteSchedule)
    return [pc.port_code for pc in route.port_calls]
end

struct ODDemand
    origin::String
    destination::String
    ffe_per_week::Float64
    revenue_per_unit::Float64
    transit_time::Float64
end

struct VesselEvent
    vessel_name::String
    route_id::String
    port_code::String
    event_type::String
    sim_time::Float64
    port_order::Int
    is_return::Bool
end

mutable struct CargoBatch
    batch_id::String
    origin::String
    destination::String
    ffe::Float64
    revenue_per_unit::Float64
    created_week::Int
    route_id::String
    transit_time::Float64
    assigned_vessel::String
    sim_time::Float64
end

function CargoBatch(batch_id, origin, destination, ffe, revenue_per_unit, created_week;
                    route_id::String="", transit_time::Float64=30.0)
    return CargoBatch(batch_id, origin, destination, ffe, revenue_per_unit, created_week, route_id, transit_time, "", -1.0)
end

struct PortStats
    port_code::String
    sim_time::Float64
    vessel_count::Int
    cargo_loaded::Float64
    cargo_discharged::Float64
end

mutable struct SimSnapshot
    time::Float64
    events::Vector{VesselEvent}
    stats::Vector{PortStats}
    cargo::Vector{CargoBatch}
end

SimSnapshot(t) = SimSnapshot(t, VesselEvent[], PortStats[], CargoBatch[])

# ============================================================
# Cost & Scenario Configuration
# ============================================================

struct CostConfig
    sea_cost_per_day::Float64
    wait_cost_per_day::Float64
    trans_cost_per_day::Float64
    port_handling_cost_per_ffe::Float64
    late_penalty_per_ffe::Float64
    reject_penalty_per_ffe::Float64
end

CostConfig(; sea_cost_per_day::Float64=1.0,
             wait_cost_per_day::Float64=0.0,
             trans_cost_per_day::Float64=0.0,
             port_handling_cost_per_ffe::Float64=0.0,
             late_penalty_per_ffe::Float64=0.0,
             reject_penalty_per_ffe::Float64=0.0) =
    CostConfig(sea_cost_per_day, wait_cost_per_day, trans_cost_per_day,
               port_handling_cost_per_ffe, late_penalty_per_ffe, reject_penalty_per_ffe)

struct ScenarioConfig
    scenario_id::String
    description::String
    cycle_days::Int
    horizon_cycles::Int
    demand_periods::Int
    min_connection_time::Int
    due_slack_days::Int
    demand_multiplier::Float64
    capacity_multiplier::Float64
    disruption_level::Float64
end

ScenarioConfig(; scenario_id::String="baseline",
                 description::String="",
                 cycle_days::Int=7,
                 horizon_cycles::Int=8,
                 demand_periods::Int=-1,
                 min_connection_time::Int=1,
                 due_slack_days::Int=0,
                 demand_multiplier::Float64=1.0,
                 capacity_multiplier::Float64=1.0,
                 disruption_level::Float64=0.0) =
    ScenarioConfig(scenario_id, description, cycle_days, horizon_cycles,
                   demand_periods < 0 ? horizon_cycles : demand_periods,
                   min_connection_time, due_slack_days, demand_multiplier,
                   capacity_multiplier, disruption_level)

# ============================================================
# Execution Plan types (Bridge between Optimization and Simulation)
# ============================================================

struct PlannedCall
    port_code::String
    planned_eta_day::Float64
    planned_etd_day::Float64
    port_order::Int
end

struct PlannedVesselRotation
    vessel_name::String
    service_id::String
    fleet_id::String
    start_delay::Float64
    planned_calls::Vector{PlannedCall}
end

struct PlannedPathLeg
    leg_index::Int
    service_id::String
    origin_port::String
    destination_port::String
    depart_day::Int
    arrival_day::Int
end

struct PlannedDemandAssignment
    demand_id::String
    origin::String
    destination::String
    quantity::Float64
    path_legs::Vector{PlannedPathLeg}
end

struct PlannedService
    service_id::String
    fleet_id::String
    vessel_count::Int
    is_active::Bool
end

struct PlanMeta
    preset_id::String
    scenario_id::String
    cycle_days::Int
    horizon_cycles::Int
    created_at::String
    objective_value::Float64
    solve_status::Symbol
end

struct ExecutionPlan
    meta::PlanMeta
    planned_services::Vector{PlannedService}
    planned_rotations::Vector{PlannedVesselRotation}
    planned_assignments::Vector{PlannedDemandAssignment}
end
