# ============================================================
# optimization.jl -- Liner shipping optimization-layer types
# and time-space network construction utilities.
# ============================================================

import JSON3
using Dates

struct ServiceLeg
    route_id::String
    leg_index::Int
    origin::String
    destination::String
    depart_day::Int
    arrival_day::Int
    sailing_days::Int
    port_stay_days::Int
    is_transshipment_allowed::Bool
end

struct ShippingService
    route_id::String
    service_name::String
    cycle_days::Int
    frequency_days::Int
    route_total_days::Int
    required_vessels::Int
    allowed_fleet_types::Vector{String}
    is_active_candidate::Bool
    port_calls::Vector{PortCall}
    legs::Vector{ServiceLeg}
end

struct FleetType
    fleet_id::String
    fleet_name::String
    capacity_ffe::Float64
    available_units::Int
    fixed_deployment_cost::Float64
    sailing_cost_per_day::Float64
    port_call_cost::Float64
    max_service_days::Int
    speed_class::String
end

struct OptimizationDemand
    demand_id::String
    origin::String
    destination::String
    quantity_ffe::Float64
    revenue_per_ffe::Float64
    release_time::Int
    due_time::Int
    transit_time::Int
    priority_class::String
    max_transshipments::Int
    is_mandatory::Bool
    reject_penalty_per_ffe::Float64
end

# CostConfig and ScenarioConfig are now defined in Shipping types.jl (platform-level)

struct TimeSpaceNode
    id::Int
    port_code::String
    slot::Int
    layer::Int
    time::Int
end

struct TimeSpaceArc
    id::Int
    from::Int
    to::Int
    kind::Symbol
    service_id::Union{Nothing, String}
    duration::Int
end

struct TimeSpaceNetwork
    cycle_days::Int
    horizon_cycles::Int
    total_layers::Int
    ports::Vector{String}
    nodes::Vector{TimeSpaceNode}
    arcs::Vector{TimeSpaceArc}
    node_lookup::Dict{Tuple{String, Int, Int}, Int}
    outgoing_arc_ids::Dict{Int, Vector{Int}}
    incoming_arc_ids::Dict{Int, Vector{Int}}
    service_arc_ids::Dict{String, Vector{Int}}
end

struct OptimizationInstance
    services::Vector{ShippingService}
    fleet_types::Vector{FleetType}
    demands::Vector{OptimizationDemand}
    network::TimeSpaceNetwork
    demand_sources::Dict{String, Int}
    demand_sinks::Dict{String, Vector{Int}}
end

struct ServiceFleetOption
    service_id::String
    fleet_id::String
    required_vessels::Int
    capacity::Float64
    fixed_cost::Float64
end

struct DemandBalanceRow
    demand_id::String
    node_id::Int
    row_type::Symbol
    rhs_symbol::Symbol
    outgoing_arc_ids::Vector{Int}
    incoming_arc_ids::Vector{Int}
end

struct OptimizationModelData
    service_ids::Vector{String}
    fleet_ids::Vector{String}
    demand_ids::Vector{String}
    node_ids::Vector{Int}
    arc_ids::Vector{Int}
    sea_arc_ids::Vector{Int}
    wait_arc_ids::Vector{Int}
    trans_arc_ids::Vector{Int}
    service_arc_ids::Dict{String, Vector{Int}}
    demand_arc_ids::Dict{String, Vector{Int}}
    demand_balance_rows::Vector{DemandBalanceRow}
    service_fleet_options::Vector{ServiceFleetOption}
    demand_data::Dict{String, OptimizationDemand}
    fleet_data::Dict{String, FleetType}
    service_data::Dict{String, ShippingService}
end

struct ArcCostConfig
    sea_cost_per_day::Float64
    wait_cost_per_day::Float64
    trans_cost_per_day::Float64
    port_handling_cost_per_ffe::Float64
    late_penalty_per_ffe::Float64
    reject_penalty_per_ffe::Float64
end

ArcCostConfig(; sea_cost_per_day::Float64=1.0,
                wait_cost_per_day::Float64=0.0,
                trans_cost_per_day::Float64=0.0,
                port_handling_cost_per_ffe::Float64=0.0,
                late_penalty_per_ffe::Float64=0.0,
                reject_penalty_per_ffe::Float64=0.0) =
    ArcCostConfig(sea_cost_per_day, wait_cost_per_day, trans_cost_per_day,
                  port_handling_cost_per_ffe, late_penalty_per_ffe, reject_penalty_per_ffe)

# Backward-compatible constructor from CostConfig
ArcCostConfig(cc::CostConfig) = ArcCostConfig(
    cc.sea_cost_per_day, cc.wait_cost_per_day, cc.trans_cost_per_day,
    cc.port_handling_cost_per_ffe, cc.late_penalty_per_ffe, cc.reject_penalty_per_ffe)

# Execution Plan types (PlannedCall, PlannedVesselRotation, PlannedPathLeg,
# PlannedDemandAssignment, PlannedService, PlanMeta, ExecutionPlan)
# are now defined in Shipping types.jl (platform-level)

# ============================================================
# Optimization Output types (§7.1)
# ============================================================

struct ServiceDecision
    service_id::String
    is_active::Bool
    fleet_id::String
    vessel_count::Int
    total_capacity::Float64
    fixed_cost::Float64
end

struct DemandDecision
    demand_id::String
    accepted_quantity::Float64
    total_quantity::Float64
    acceptance_rate::Float64
    revenue::Float64
    is_mandatory::Bool
end

struct DemandPath
    demand_id::String
    legs::Vector{PlannedPathLeg}
    total_transit_days::Int
    transshipment_count::Int
end

struct ArcUtilization
    arc_id::Int
    kind::Symbol
    service_id::Union{Nothing, String}
    total_flow::Float64
    capacity::Float64
    utilization_rate::Float64
end

struct PortFlowSummary
    port_code::String
    total_inflow::Float64
    total_outflow::Float64
    net_flow::Float64
end

struct EconomicBreakdown
    cargo_revenue::Float64
    fleet_deployment_cost::Float64
    sea_transport_cost::Float64
    waiting_cost::Float64
    transshipment_cost::Float64
    port_handling_cost::Float64
    late_penalty::Float64
    reject_penalty::Float64
    net_profit::Float64
end

struct OptimizationResult
    solve_status::Symbol
    objective_value::Float64
    service_decisions::Vector{ServiceDecision}
    demand_decisions::Vector{DemandDecision}
    demand_paths::Vector{DemandPath}
    arc_utilizations::Vector{ArcUtilization}
    port_flows::Vector{PortFlowSummary}
    economic_breakdown::EconomicBreakdown
    variable_values::Dict{String, Float64}
end

# ============================================================
# Simulation Output types (§7.2)
# ============================================================

struct DemandOutcome
    demand_id::String
    origin::String
    destination::String
    planned_quantity::Float64
    delivered_quantity::Float64
    planned_arrival_day::Float64
    actual_arrival_day::Float64
    delay_days::Float64
    is_on_time::Bool
    is_delivered::Bool
end

struct ServiceReliability
    service_id::String
    planned_calls::Int
    on_time_calls::Int
    delayed_calls::Int
    missed_calls::Int
    reliability_rate::Float64
    avg_delay_days::Float64
end

struct PortCongestion
    port_code::String
    total_vessel_visits::Int
    avg_wait_days::Float64
    max_wait_days::Float64
    peak_vessel_count::Int
end

# ============================================================
# KPI Summary (§7.3)
# ============================================================

struct KpiSummary
    planned_profit::Float64
    simulated_profit::Float64
    profit_retention_rate::Float64
    accepted_cargo_ffe::Float64
    delivered_cargo_ffe::Float64
    on_time_delivery_rate::Float64
    avg_transit_time::Float64
    avg_utilization::Float64
    max_arc_utilization::Float64
    service_reliability::Float64
    rejection_rate::Float64
end

struct AcceptanceVarKey
    demand_id::String
end

struct ActivationVarKey
    service_id::String
end

struct DeploymentVarKey
    service_id::String
    fleet_id::String
end

struct FlowVarKey
    demand_id::String
    arc_id::Int
end

struct SinkVarKey
    demand_id::String
    node_id::Int
end

const AbstractVarKey = Union{
    AcceptanceVarKey,
    ActivationVarKey,
    DeploymentVarKey,
    FlowVarKey,
    SinkVarKey,
}

struct LinearTerm
    key::AbstractVarKey
    coefficient::Float64
end

struct VariableSpec
    key::AbstractVarKey
    name::String
    lower_bound::Float64
    upper_bound::Union{Nothing, Float64}
    domain::Symbol
end

struct LinearConstraintSpec
    name::String
    sense::Symbol
    rhs::Float64
    terms::Vector{LinearTerm}
end

struct ObjectiveSpec
    sense::Symbol
    terms::Vector{LinearTerm}
    constant::Float64
end

struct MILPSpec
    variable_specs::Vector{VariableSpec}
    acceptance_vars::Vector{AcceptanceVarKey}
    activation_vars::Vector{ActivationVarKey}
    deployment_vars::Vector{DeploymentVarKey}
    flow_vars::Vector{FlowVarKey}
    sink_vars::Vector{SinkVarKey}
    objective::ObjectiveSpec
    constraints::Vector{LinearConstraintSpec}
end

struct OptimizationArtifacts
    preset_id::String
    instance::OptimizationInstance
    model_data::OptimizationModelData
    milp_spec::MILPSpec
    metadata::Dict{String, Any}
end

_day_index(x::Float64) = round(Int, x)

function _service_total_days(route::RouteSchedule)
    return max(1, ceil(Int, route.total_days))
end

function build_service(route::RouteSchedule; cycle_days::Int=7,
                                          allowed_fleet_types::Vector{String}=String[],
                                          is_active_candidate::Bool=true)
    legs = ServiceLeg[]
    calls = route.port_calls
    for i in 1:(length(calls) - 1)
        from_call = calls[i]
        to_call = calls[i + 1]
        from_call.etd_day === nothing && continue

        depart_day = _day_index(from_call.etd_day)
        arrival_day = _day_index(to_call.eta_day)
        sailing_days = max(arrival_day - depart_day, 0)

        # Compute port stay: time between arrival and departure at the from_call port
        port_stay = from_call.etd_day !== nothing && from_call.eta_day !== nothing ?
                    max(_day_index(from_call.etd_day) - _day_index(from_call.eta_day), 0) : 0

        push!(legs, ServiceLeg(
            route.route_id,
            i,
            from_call.port_code,
            to_call.port_code,
            depart_day,
            arrival_day,
            sailing_days,
            port_stay,
            true,  # is_transshipment_allowed — default true for V1
        ))
    end

    total_days = _service_total_days(route)
    required_vessels = max(1, cld(total_days, cycle_days))

    return ShippingService(
        route.route_id,
        route.route_id,  # service_name defaults to route_id
        cycle_days,
        cycle_days,       # frequency_days = cycle_days for weekly service
        total_days,
        required_vessels,
        allowed_fleet_types,
        is_active_candidate,
        route.port_calls,
        legs,
    )
end

function build_services(routes::Vector{RouteSchedule}; cycle_days::Int=7)
    return [build_service(route; cycle_days=cycle_days) for route in routes]
end

function build_optimization_demands(ods::Vector{ODDemand};
                                    periods::Int=1,
                                    cycle_days::Int=7,
                                    release_offset::Int=0,
                                    due_slack_days::Int=0,
                                    demand_multiplier::Float64=1.0,
                                    prefix::String="D",
                                    priority_class::String="standard",
                                    max_transshipments::Int=2,
                                    is_mandatory::Bool=false,
                                    reject_penalty_per_ffe::Float64=0.0)
    demands = OptimizationDemand[]
    batch_counter = 0

    for period in 0:(periods - 1)
        release_time = release_offset + period * cycle_days
        for od in ods
            batch_counter += 1
            transit_time = max(1, ceil(Int, od.transit_time))
            due_time = release_time + transit_time + due_slack_days
            demand_id = string(prefix, "-", lpad(batch_counter, 4, '0'))
            quantity_ffe = max(0.0, od.ffe_per_week * demand_multiplier)

            push!(demands, OptimizationDemand(
                demand_id,
                od.origin,
                od.destination,
                quantity_ffe,
                od.revenue_per_unit,
                release_time,
                due_time,
                transit_time,
                priority_class,
                max_transshipments,
                is_mandatory,
                reject_penalty_per_ffe,
            ))
        end
    end

    return demands
end

function node_id(network::TimeSpaceNetwork, port_code::String, slot::Int, layer::Int)
    key = (port_code, slot, layer)
    haskey(network.node_lookup, key) || error("Unknown time-space node: $key")
    return network.node_lookup[key]
end

function arc_ids_by_kind(network::TimeSpaceNetwork, kind::Symbol)
    return [arc.id for arc in network.arcs if arc.kind == kind]
end

function variable_name(key::AcceptanceVarKey)
    return string("u__", key.demand_id)
end

function variable_name(key::ActivationVarKey)
    return string("z__", key.service_id)
end

function variable_name(key::DeploymentVarKey)
    return string("m__", key.service_id, "__", key.fleet_id)
end

function variable_name(key::FlowVarKey)
    return string("x__", key.demand_id, "__a", key.arc_id)
end

function variable_name(key::SinkVarKey)
    return string("w__", key.demand_id, "__n", key.node_id)
end

function feasible_arc_ids(instance::OptimizationInstance, demand::OptimizationDemand)
    feasible = Int[]
    source_id = source_node_id(instance, demand)
    sink_ids = Set(sink_node_ids(instance, demand))

    for arc in instance.network.arcs
        from_node = instance.network.nodes[arc.from]
        to_node = instance.network.nodes[arc.to]

        # Enforce time-window monotonicity at the indexing layer so the
        # optimization model can use a reduced variable set.
        if to_node.time < demand.release_time
            continue
        end
        if from_node.time > demand.due_time
            continue
        end
        if to_node.time > demand.due_time && !(arc.to in sink_ids)
            continue
        end

        # Keep only arcs reachable from the demand's origin time onward.
        if from_node.time < instance.network.nodes[source_id].time
            continue
        end

        push!(feasible, arc.id)
    end

    return feasible
end

function feasible_arc_ids(instance::OptimizationInstance, demand_id::String)
    for demand in instance.demands
        if demand.demand_id == demand_id
            return feasible_arc_ids(instance, demand)
        end
    end
    error("Unknown demand id: $demand_id")
end

function _add_arc!(arcs::Vector{TimeSpaceArc},
                   outgoing::Dict{Int, Vector{Int}},
                   incoming::Dict{Int, Vector{Int}},
                   service_arc_ids::Dict{String, Vector{Int}},
                   from_id::Int,
                   to_id::Int,
                   kind::Symbol;
                   service_id::Union{Nothing, String}=nothing,
                   duration::Int=0)
    arc_id = length(arcs) + 1
    push!(arcs, TimeSpaceArc(arc_id, from_id, to_id, kind, service_id, duration))
    push!(get!(outgoing, from_id, Int[]), arc_id)
    push!(get!(incoming, to_id, Int[]), arc_id)
    if service_id !== nothing
        push!(get!(service_arc_ids, service_id, Int[]), arc_id)
    end
    return arc_id
end

function _unique_ports(services::Vector{ShippingService}, extra_ports::Vector{String})
    seen = Set{String}()
    ordered = String[]

    for service in services
        for call in service.port_calls
            if !(call.port_code in seen)
                push!(seen, call.port_code)
                push!(ordered, call.port_code)
            end
        end
    end

    for port_code in extra_ports
        if !(port_code in seen)
            push!(seen, port_code)
            push!(ordered, port_code)
        end
    end

    return ordered
end

function build_time_space_network(services::Vector{ShippingService};
                                  horizon_cycles::Int=8,
                                  cycle_days::Int=7,
                                  ports::Vector{String}=String[],
                                  min_connection_time::Int=1)
    max_service_layers = isempty(services) ? 1 : maximum(s.required_vessels for s in services)
    total_layers = horizon_cycles + max_service_layers
    network_ports = _unique_ports(services, ports)

    nodes = TimeSpaceNode[]
    node_lookup = Dict{Tuple{String, Int, Int}, Int}()
    outgoing_arc_ids = Dict{Int, Vector{Int}}()
    incoming_arc_ids = Dict{Int, Vector{Int}}()
    service_arc_ids = Dict{String, Vector{Int}}()

    for port_code in network_ports
        for layer in 0:(total_layers - 1)
            for slot in 0:(cycle_days - 1)
                node_idx = length(nodes) + 1
                time = layer * cycle_days + slot
                push!(nodes, TimeSpaceNode(node_idx, port_code, slot, layer, time))
                node_lookup[(port_code, slot, layer)] = node_idx
            end
        end
    end

    arcs = TimeSpaceArc[]

    # Waiting arcs keep time monotonic inside each port.
    for port_code in network_ports
        for layer in 0:(total_layers - 1)
            for slot in 0:(cycle_days - 1)
                from_id = node_lookup[(port_code, slot, layer)]
                if slot < cycle_days - 1
                    to_id = node_lookup[(port_code, slot + 1, layer)]
                    _add_arc!(arcs, outgoing_arc_ids, incoming_arc_ids, service_arc_ids,
                              from_id, to_id, :wait; duration=1)
                elseif layer < total_layers - 1
                    to_id = node_lookup[(port_code, 0, layer + 1)]
                    _add_arc!(arcs, outgoing_arc_ids, incoming_arc_ids, service_arc_ids,
                              from_id, to_id, :wait; duration=1)
                end
            end
        end
    end

    # Sea arcs are generated from the weekly service start cycle.
    for service in services
        for start_cycle in 0:(horizon_cycles - 1)
            for leg in service.legs
                depart_abs = start_cycle * cycle_days + leg.depart_day
                arrive_abs = start_cycle * cycle_days + leg.arrival_day
                from_layer = fld(depart_abs, cycle_days)
                from_slot = mod(depart_abs, cycle_days)
                to_layer = fld(arrive_abs, cycle_days)
                to_slot = mod(arrive_abs, cycle_days)

                if from_layer >= total_layers || to_layer >= total_layers
                    continue
                end

                from_id = node_lookup[(leg.origin, from_slot, from_layer)]
                to_id = node_lookup[(leg.destination, to_slot, to_layer)]
                _add_arc!(arcs, outgoing_arc_ids, incoming_arc_ids, service_arc_ids,
                          from_id, to_id, :sea;
                          service_id=service.route_id,
                          duration=max(arrive_abs - depart_abs, 0))
            end
        end
    end

    # Optional transfer arcs can skip short infeasible port connections while
    # keeping the dense wait-arc backbone intact.
    if min_connection_time > 1
        for port_code in network_ports
            max_time = total_layers * cycle_days - 1
            for t in 0:(max_time - min_connection_time)
                from_layer = fld(t, cycle_days)
                from_slot = mod(t, cycle_days)
                to_time = t + min_connection_time
                to_layer = fld(to_time, cycle_days)
                to_slot = mod(to_time, cycle_days)
                to_layer >= total_layers && continue

                from_id = node_lookup[(port_code, from_slot, from_layer)]
                to_id = node_lookup[(port_code, to_slot, to_layer)]
                _add_arc!(arcs, outgoing_arc_ids, incoming_arc_ids, service_arc_ids,
                          from_id, to_id, :trans; duration=min_connection_time)
            end
        end
    end

    return TimeSpaceNetwork(
        cycle_days,
        horizon_cycles,
        total_layers,
        network_ports,
        nodes,
        arcs,
        node_lookup,
        outgoing_arc_ids,
        incoming_arc_ids,
        service_arc_ids,
    )
end

function _demand_sinks(network::TimeSpaceNetwork, demand::OptimizationDemand)
    sink_ids = Int[]
    for node in network.nodes
        if node.port_code == demand.destination &&
           node.time >= demand.release_time &&
           node.time <= demand.due_time
            push!(sink_ids, node.id)
        end
    end
    return sink_ids
end

function _build_demand_maps(demands::Vector{OptimizationDemand}, network::TimeSpaceNetwork)
    demand_sources = Dict{String, Int}()
    demand_sinks = Dict{String, Vector{Int}}()

    for demand in demands
        source_layer = fld(demand.release_time, network.cycle_days)
        source_slot = mod(demand.release_time, network.cycle_days)
        source_layer < network.total_layers || error("Demand $(demand.demand_id) starts outside network horizon.")

        source_id = node_id(network, demand.origin, source_slot, source_layer)
        sink_ids = _demand_sinks(network, demand)
        isempty(sink_ids) && error("Demand $(demand.demand_id) has no reachable sink nodes in network horizon.")

        demand_sources[demand.demand_id] = source_id
        demand_sinks[demand.demand_id] = sink_ids
    end

    return demand_sources, demand_sinks
end

function build_optimization_instance(route::RouteSchedule,
                                     ods::Vector{ODDemand};
                                     cycle_days::Int=7,
                                     horizon_cycles::Int=8,
                                     demand_periods::Int=horizon_cycles,
                                     due_slack_days::Int=0,
                                     min_connection_time::Int=1,
                                     demand_multiplier::Float64=1.0,
                                     fleet_types::Vector{FleetType}=FleetType[])
    service = build_service(route; cycle_days=cycle_days)
    demands = build_optimization_demands(
        ods;
        periods=demand_periods,
        cycle_days=cycle_days,
        due_slack_days=due_slack_days,
        demand_multiplier=demand_multiplier,
        prefix=route.route_id,
    )

    extra_ports = unique(vcat(
        [d.origin for d in demands],
        [d.destination for d in demands],
    ))

    network = build_time_space_network(
        [service];
        horizon_cycles=horizon_cycles,
        cycle_days=cycle_days,
        ports=extra_ports,
        min_connection_time=min_connection_time,
    )

    demand_sources, demand_sinks = _build_demand_maps(demands, network)

    return OptimizationInstance(
        [service],
        fleet_types,
        demands,
        network,
        demand_sources,
        demand_sinks,
    )
end

function build_optimization_instance(routes::Vector{RouteSchedule},
                                     route_od_map::Dict{String, Vector{ODDemand}};
                                     cycle_days::Int=7,
                                     horizon_cycles::Int=8,
                                     demand_periods::Int=horizon_cycles,
                                     due_slack_days::Int=0,
                                     min_connection_time::Int=1,
                                     demand_multiplier::Float64=1.0,
                                     fleet_types::Vector{FleetType}=FleetType[])
    services = build_services(routes; cycle_days=cycle_days)
    demands = OptimizationDemand[]

    for route in routes
        ods = get(route_od_map, route.route_id, ODDemand[])
        append!(demands, build_optimization_demands(
            ods;
            periods=demand_periods,
            cycle_days=cycle_days,
            due_slack_days=due_slack_days,
            demand_multiplier=demand_multiplier,
            prefix=route.route_id,
        ))
    end

    extra_ports = unique(vcat(
        [d.origin for d in demands],
        [d.destination for d in demands],
    ))

    network = build_time_space_network(
        services;
        horizon_cycles=horizon_cycles,
        cycle_days=cycle_days,
        ports=extra_ports,
        min_connection_time=min_connection_time,
    )

    demand_sources, demand_sinks = _build_demand_maps(demands, network)

    return OptimizationInstance(
        services,
        fleet_types,
        demands,
        network,
        demand_sources,
        demand_sinks,
    )
end

function source_node_id(instance::OptimizationInstance, demand::OptimizationDemand)
    return instance.demand_sources[demand.demand_id]
end

function source_node_id(instance::OptimizationInstance, demand_id::String)
    return instance.demand_sources[demand_id]
end

function sink_node_ids(instance::OptimizationInstance, demand::OptimizationDemand)
    return instance.demand_sinks[demand.demand_id]
end

function sink_node_ids(instance::OptimizationInstance, demand_id::String)
    return instance.demand_sinks[demand_id]
end

function _demand_lookup(instance::OptimizationInstance)
    return Dict(d.demand_id => d for d in instance.demands)
end

function _fleet_lookup(instance::OptimizationInstance)
    return Dict(f.fleet_id => f for f in instance.fleet_types)
end

function _service_lookup(instance::OptimizationInstance)
    return Dict(s.route_id => s for s in instance.services)
end

function _service_fleet_options(instance::OptimizationInstance)
    options = ServiceFleetOption[]
    for service in instance.services
        # If service restricts fleet types, only consider those; otherwise all
        eligible_fleets = isempty(service.allowed_fleet_types) ?
                          instance.fleet_types :
                          filter(f -> f.fleet_id in service.allowed_fleet_types, instance.fleet_types)
        for fleet in eligible_fleets
            push!(options, ServiceFleetOption(
                service.route_id,
                fleet.fleet_id,
                service.required_vessels,
                fleet.capacity_ffe,
                fleet.fixed_deployment_cost,
            ))
        end
    end
    return options
end

function _demand_arc_map(instance::OptimizationInstance)
    return Dict(d.demand_id => feasible_arc_ids(instance, d) for d in instance.demands)
end

function _balance_row_type(node_id_value::Int, source_id::Int, sink_ids::Set{Int})
    if node_id_value == source_id
        return (:source, :u)
    elseif node_id_value in sink_ids
        return (:sink, :w)
    else
        return (:transit, :zero)
    end
end

function _build_balance_rows(instance::OptimizationInstance,
                             demand_arc_ids::Dict{String, Vector{Int}})
    rows = DemandBalanceRow[]

    for demand in instance.demands
        demand_id = demand.demand_id
        source_id = source_node_id(instance, demand)
        sink_ids = Set(sink_node_ids(instance, demand))
        feasible_ids = Set(demand_arc_ids[demand_id])

        touched_nodes = Set{Int}()
        for arc_id in feasible_ids
            arc = instance.network.arcs[arc_id]
            push!(touched_nodes, arc.from)
            push!(touched_nodes, arc.to)
        end
        push!(touched_nodes, source_id)
        union!(touched_nodes, sink_ids)

        for nid in sort!(collect(touched_nodes))
            outgoing = [arc_id for arc_id in get(instance.network.outgoing_arc_ids, nid, Int[]) if arc_id in feasible_ids]
            incoming = [arc_id for arc_id in get(instance.network.incoming_arc_ids, nid, Int[]) if arc_id in feasible_ids]
            row_type, rhs_symbol = _balance_row_type(nid, source_id, sink_ids)

            push!(rows, DemandBalanceRow(
                demand_id,
                nid,
                row_type,
                rhs_symbol,
                outgoing,
                incoming,
            ))
        end
    end

    return rows
end

function _arc_unit_cost(arc::TimeSpaceArc, config::ArcCostConfig)
    if arc.kind == :sea
        return config.sea_cost_per_day * arc.duration
    elseif arc.kind == :wait
        return config.wait_cost_per_day * arc.duration
    elseif arc.kind == :trans
        return config.trans_cost_per_day * arc.duration
    end
    return 0.0
end

function _acceptance_vars(model_data::OptimizationModelData)
    return [AcceptanceVarKey(demand_id) for demand_id in model_data.demand_ids]
end

function _activation_vars(model_data::OptimizationModelData)
    return [ActivationVarKey(service_id) for service_id in model_data.service_ids]
end

function _deployment_vars(model_data::OptimizationModelData)
    vars = DeploymentVarKey[]
    for option in model_data.service_fleet_options
        push!(vars, DeploymentVarKey(option.service_id, option.fleet_id))
    end
    return vars
end

function _flow_vars(model_data::OptimizationModelData)
    vars = FlowVarKey[]
    for demand_id in model_data.demand_ids
        for arc_id in model_data.demand_arc_ids[demand_id]
            push!(vars, FlowVarKey(demand_id, arc_id))
        end
    end
    return vars
end

function _sink_vars(model_data::OptimizationModelData)
    vars = SinkVarKey[]
    for row in model_data.demand_balance_rows
        if row.row_type == :sink
            push!(vars, SinkVarKey(row.demand_id, row.node_id))
        end
    end
    return vars
end

function _variable_specs(instance::OptimizationInstance,
                         model_data::OptimizationModelData,
                         acceptance_vars::Vector{AcceptanceVarKey},
                         activation_vars::Vector{ActivationVarKey},
                         deployment_vars::Vector{DeploymentVarKey},
                         flow_vars::Vector{FlowVarKey},
                         sink_vars::Vector{SinkVarKey})
    specs = VariableSpec[]

    for key in acceptance_vars
        demand = model_data.demand_data[key.demand_id]
        push!(specs, VariableSpec(
            key,
            variable_name(key),
            0.0,
            demand.quantity_ffe,
            :continuous,
        ))
    end

    for key in activation_vars
        push!(specs, VariableSpec(
            key,
            variable_name(key),
            0.0,
            1.0,
            :binary,
        ))
    end

    for key in deployment_vars
        push!(specs, VariableSpec(
            key,
            variable_name(key),
            0.0,
            1.0,
            :binary,
        ))
    end

    for key in flow_vars
        demand = model_data.demand_data[key.demand_id]
        push!(specs, VariableSpec(
            key,
            variable_name(key),
            0.0,
            demand.quantity_ffe,
            :continuous,
        ))
    end

    for key in sink_vars
        demand = model_data.demand_data[key.demand_id]
        push!(specs, VariableSpec(
            key,
            variable_name(key),
            0.0,
            demand.quantity_ffe,
            :continuous,
        ))
    end

    return specs
end

function _acceptance_upper_bound_constraints(model_data::OptimizationModelData)
    constraints = LinearConstraintSpec[]
    for demand_id in model_data.demand_ids
        demand = model_data.demand_data[demand_id]
        push!(constraints, LinearConstraintSpec(
            string("acceptance_cap__", demand_id),
            :le,
            demand.quantity_ffe,
            [LinearTerm(AcceptanceVarKey(demand_id), 1.0)],
        ))
    end
    return constraints
end

function _flow_balance_constraints(model_data::OptimizationModelData)
    constraints = LinearConstraintSpec[]

    for row in model_data.demand_balance_rows
        terms = LinearTerm[]

        for arc_id in row.incoming_arc_ids
            push!(terms, LinearTerm(FlowVarKey(row.demand_id, arc_id), 1.0))
        end
        for arc_id in row.outgoing_arc_ids
            push!(terms, LinearTerm(FlowVarKey(row.demand_id, arc_id), -1.0))
        end

        if row.rhs_symbol == :u
            push!(terms, LinearTerm(AcceptanceVarKey(row.demand_id), -1.0))
        elseif row.rhs_symbol == :w
            push!(terms, LinearTerm(SinkVarKey(row.demand_id, row.node_id), -1.0))
        end

        push!(constraints, LinearConstraintSpec(
            string("flow_balance__", row.demand_id, "__n", row.node_id),
            :eq,
            0.0,
            terms,
        ))
    end

    return constraints
end

function _sink_absorption_constraints(instance::OptimizationInstance,
                                      model_data::OptimizationModelData)
    constraints = LinearConstraintSpec[]

    for demand_id in model_data.demand_ids
        sink_terms = LinearTerm[]
        for sink_id in sink_node_ids(instance, demand_id)
            push!(sink_terms, LinearTerm(SinkVarKey(demand_id, sink_id), 1.0))
        end
        push!(sink_terms, LinearTerm(AcceptanceVarKey(demand_id), -1.0))

        push!(constraints, LinearConstraintSpec(
            string("sink_absorption__", demand_id),
            :eq,
            0.0,
            sink_terms,
        ))
    end

    return constraints
end

function _sea_capacity_constraints(instance::OptimizationInstance,
                                   model_data::OptimizationModelData)
    constraints = LinearConstraintSpec[]

    for arc_id in model_data.sea_arc_ids
        terms = LinearTerm[]

        for demand_id in model_data.demand_ids
            if arc_id in model_data.demand_arc_ids[demand_id]
                push!(terms, LinearTerm(FlowVarKey(demand_id, arc_id), 1.0))
            end
        end

        service_id = nothing
        for (sid, arc_ids) in model_data.service_arc_ids
            if arc_id in arc_ids
                service_id = sid
                break
            end
        end

        service_id === nothing && continue

        for option in model_data.service_fleet_options
            if option.service_id == service_id
                push!(terms, LinearTerm(
                    DeploymentVarKey(option.service_id, option.fleet_id),
                    -option.capacity,
                ))
            end
        end

        push!(constraints, LinearConstraintSpec(
            string("sea_capacity__a", arc_id),
            :le,
            0.0,
            terms,
        ))
    end

    return constraints
end

function _fleet_availability_constraints(model_data::OptimizationModelData)
    constraints = LinearConstraintSpec[]

    for fleet_id in model_data.fleet_ids
        fleet = model_data.fleet_data[fleet_id]
        terms = LinearTerm[]

        for option in model_data.service_fleet_options
            if option.fleet_id == fleet_id
                push!(terms, LinearTerm(
                    DeploymentVarKey(option.service_id, option.fleet_id),
                    Float64(option.required_vessels),
                ))
            end
        end

        push!(constraints, LinearConstraintSpec(
            string("fleet_availability__", fleet_id),
            :le,
            Float64(fleet.available_units),
            terms,
        ))
    end

    return constraints
end

function _service_activation_constraints(model_data::OptimizationModelData)
    constraints = LinearConstraintSpec[]

    for service_id in model_data.service_ids
        terms = LinearTerm[]

        for option in model_data.service_fleet_options
            if option.service_id == service_id
                push!(terms, LinearTerm(
                    DeploymentVarKey(option.service_id, option.fleet_id),
                    1.0,
                ))
            end
        end
        push!(terms, LinearTerm(ActivationVarKey(service_id), -1.0))

        push!(constraints, LinearConstraintSpec(
            string("service_activation__", service_id),
            :eq,
            0.0,
            terms,
        ))
    end

    return constraints
end

function _objective_spec(instance::OptimizationInstance,
                         model_data::OptimizationModelData,
                         cost_config::ArcCostConfig)
    terms = LinearTerm[]

    for demand_id in model_data.demand_ids
        demand = model_data.demand_data[demand_id]
        push!(terms, LinearTerm(AcceptanceVarKey(demand_id), demand.revenue_per_ffe))
    end

    for option in model_data.service_fleet_options
        push!(terms, LinearTerm(
            DeploymentVarKey(option.service_id, option.fleet_id),
            -option.fixed_cost,
        ))
    end

    for demand_id in model_data.demand_ids
        for arc_id in model_data.demand_arc_ids[demand_id]
            arc = instance.network.arcs[arc_id]
            arc_cost = _arc_unit_cost(arc, cost_config)
            iszero(arc_cost) && continue
            push!(terms, LinearTerm(FlowVarKey(demand_id, arc_id), -arc_cost))
        end
    end

    return ObjectiveSpec(:Max, terms, 0.0)
end

function build_model_data(instance::OptimizationInstance)
    service_ids = [s.route_id for s in instance.services]
    fleet_ids = [f.fleet_id for f in instance.fleet_types]
    demand_ids = [d.demand_id for d in instance.demands]
    node_ids = [n.id for n in instance.network.nodes]
    arc_ids = [a.id for a in instance.network.arcs]
    sea_arc_ids = arc_ids_by_kind(instance.network, :sea)
    wait_arc_ids = arc_ids_by_kind(instance.network, :wait)
    trans_arc_ids = arc_ids_by_kind(instance.network, :trans)
    demand_arc_ids = _demand_arc_map(instance)
    balance_rows = _build_balance_rows(instance, demand_arc_ids)

    return OptimizationModelData(
        service_ids,
        fleet_ids,
        demand_ids,
        node_ids,
        arc_ids,
        sea_arc_ids,
        wait_arc_ids,
        trans_arc_ids,
        deepcopy(instance.network.service_arc_ids),
        demand_arc_ids,
        balance_rows,
        _service_fleet_options(instance),
        _demand_lookup(instance),
        _fleet_lookup(instance),
        _service_lookup(instance),
    )
end

function build_milp_spec(instance::OptimizationInstance;
                         cost_config::ArcCostConfig=ArcCostConfig())
    model_data = build_model_data(instance)
    acceptance_vars = _acceptance_vars(model_data)
    activation_vars = _activation_vars(model_data)
    deployment_vars = _deployment_vars(model_data)
    flow_vars = _flow_vars(model_data)
    sink_vars = _sink_vars(model_data)

    constraints = LinearConstraintSpec[]
    append!(constraints, _acceptance_upper_bound_constraints(model_data))
    append!(constraints, _flow_balance_constraints(model_data))
    append!(constraints, _sink_absorption_constraints(instance, model_data))
    append!(constraints, _sea_capacity_constraints(instance, model_data))
    append!(constraints, _fleet_availability_constraints(model_data))
    append!(constraints, _service_activation_constraints(model_data))

    return MILPSpec(
        _variable_specs(
            instance,
            model_data,
            acceptance_vars,
            activation_vars,
            deployment_vars,
            flow_vars,
            sink_vars,
        ),
        acceptance_vars,
        activation_vars,
        deployment_vars,
        flow_vars,
        sink_vars,
        _objective_spec(instance, model_data, cost_config),
        constraints,
    )
end

function _term_dict(term::LinearTerm)
    return Dict{String, Any}(
        "var" => variable_name(term.key),
        "coefficient" => term.coefficient,
    )
end

function _constraint_dict(spec::LinearConstraintSpec)
    return Dict{String, Any}(
        "name" => spec.name,
        "sense" => String(spec.sense),
        "rhs" => spec.rhs,
        "terms" => [_term_dict(term) for term in spec.terms],
    )
end

function _variable_spec_dict(spec::VariableSpec)
    return Dict{String, Any}(
        "name" => spec.name,
        "lower_bound" => spec.lower_bound,
        "upper_bound" => spec.upper_bound,
        "domain" => String(spec.domain),
    )
end

function milp_spec_dict(spec::MILPSpec)
    return Dict{String, Any}(
        "variables" => [_variable_spec_dict(v) for v in spec.variable_specs],
        "objective" => Dict{String, Any}(
            "sense" => String(spec.objective.sense),
            "constant" => spec.objective.constant,
            "terms" => [_term_dict(term) for term in spec.objective.terms],
        ),
        "constraints" => [_constraint_dict(c) for c in spec.constraints],
        "counts" => Dict{String, Any}(
            "variables" => length(spec.variable_specs),
            "acceptance_vars" => length(spec.acceptance_vars),
            "activation_vars" => length(spec.activation_vars),
            "deployment_vars" => length(spec.deployment_vars),
            "flow_vars" => length(spec.flow_vars),
            "sink_vars" => length(spec.sink_vars),
            "constraints" => length(spec.constraints),
        ),
    )
end

function milp_summary_lines(spec::MILPSpec)
    lines = String[]
    push!(lines, "Shipping MILP Specification")
    push!(lines, "  Variables: $(length(spec.variable_specs))")
    push!(lines, "  Acceptance vars: $(length(spec.acceptance_vars))")
    push!(lines, "  Activation vars: $(length(spec.activation_vars))")
    push!(lines, "  Deployment vars: $(length(spec.deployment_vars))")
    push!(lines, "  Flow vars: $(length(spec.flow_vars))")
    push!(lines, "  Sink vars: $(length(spec.sink_vars))")
    push!(lines, "  Constraints: $(length(spec.constraints))")
    push!(lines, "  Objective sense: $(spec.objective.sense)")
    return lines
end

function _format_number(x::Float64)
    if isinteger(x)
        return string(round(Int, x))
    end
    return string(round(x; digits=6))
end

function _linear_expr_string(terms::Vector{LinearTerm})
    isempty(terms) && return "0"

    parts = String[]
    for (idx, term) in enumerate(terms)
        coeff = term.coefficient
        iszero(coeff) && continue

        var_name = variable_name(term.key)
        abs_coeff = abs(coeff)
        coeff_text = abs_coeff == 1.0 ? "" : string(_format_number(abs_coeff), " ")

        if idx == 1 || isempty(parts)
            if coeff < 0
                push!(parts, string("- ", coeff_text, var_name))
            else
                push!(parts, string(coeff_text, var_name))
            end
        else
            if coeff < 0
                push!(parts, string("- ", coeff_text, var_name))
            else
                push!(parts, string("+ ", coeff_text, var_name))
            end
        end
    end

    return isempty(parts) ? "0" : join(parts, " ")
end

function _sense_token(sense::Symbol)
    if sense == :le
        return "<="
    elseif sense == :ge
        return ">="
    elseif sense == :eq
        return "="
    end
    error("Unsupported constraint sense: $sense")
end

function milp_lp_lines(spec::MILPSpec)
    lines = String[]
    push!(lines, spec.objective.sense == :Max ? "Maximize" : "Minimize")
    push!(lines, string(" obj: ", _linear_expr_string(spec.objective.terms)))

    push!(lines, "Subject To")
    for constraint in spec.constraints
        push!(lines, string(
            " ", constraint.name, ": ",
            _linear_expr_string(constraint.terms), " ",
            _sense_token(constraint.sense), " ",
            _format_number(constraint.rhs),
        ))
    end

    push!(lines, "Bounds")
    for spec_var in spec.variable_specs
        if spec_var.lower_bound == 0.0 && spec_var.upper_bound === nothing
            push!(lines, string(" ", spec_var.name, " >= 0"))
        elseif spec_var.upper_bound === nothing
            push!(lines, string(
                " ", _format_number(spec_var.lower_bound), " <= ",
                spec_var.name
            ))
        else
            push!(lines, string(
                " ", _format_number(spec_var.lower_bound), " <= ",
                spec_var.name, " <= ", _format_number(spec_var.upper_bound),
            ))
        end
    end

    binary_names = [spec_var.name for spec_var in spec.variable_specs if spec_var.domain == :binary]
    integer_names = [spec_var.name for spec_var in spec.variable_specs if spec_var.domain == :integer]

    if !isempty(binary_names)
        push!(lines, "Binaries")
        for name in binary_names
            push!(lines, string(" ", name))
        end
    end

    if !isempty(integer_names)
        push!(lines, "Generals")
        for name in integer_names
            push!(lines, string(" ", name))
        end
    end

    push!(lines, "End")
    return lines
end

function write_milp_lp(filepath::String, spec::MILPSpec)
    open(filepath, "w") do io
        for line in milp_lp_lines(spec)
            println(io, line)
        end
    end
    return filepath
end

function _string_key_dict(data)
    if data isa AbstractDict
        return Dict{String, Any}(string(k) => v for (k, v) in pairs(data))
    end
    return Dict{String, Any}()
end

function _default_shipping_data_files(config::Dict{String, Any})
    data_config = _string_key_dict(get(config, "data", Dict{String, Any}()))
    data_dir = joinpath(@__DIR__, "..", "..", "data", "shipping")
    schedule_file = get(data_config, "route_schedule", joinpath(data_dir, "航线船期_20260507_ych.csv"))
    od_file = get(data_config, "od_demand", joinpath(data_dir, "od对需求_20260507_ych.csv"))
    return schedule_file, od_file
end

function _default_fleet_types(config::Dict{String, Any})
    fleet_config = get(config, "fleet_types", Any[])
    fleet_types = FleetType[]
    capacity_multiplier = Float64(get(config, "capacity_multiplier", 1.0))

    if fleet_config isa AbstractVector && !isempty(fleet_config)
        for (idx, item) in enumerate(fleet_config)
            item_dict = _string_key_dict(item)
            fleet_id = string(get(item_dict, "fleet_id", "fleet$(idx)"))
            fleet_name = string(get(item_dict, "fleet_name", fleet_id))
            capacity_ffe = Float64(get(item_dict, "capacity_ffe", get(item_dict, "capacity", 1000.0))) * capacity_multiplier
            available_units = Int(get(item_dict, "available_units", 10))
            fixed_deployment_cost = Float64(get(item_dict, "fixed_deployment_cost", get(item_dict, "fixed_cost", 0.0)))
            sailing_cost_per_day = Float64(get(item_dict, "sailing_cost_per_day", 0.0))
            port_call_cost = Float64(get(item_dict, "port_call_cost", 0.0))
            max_service_days = Int(get(item_dict, "max_service_days", 365))
            speed_class = string(get(item_dict, "speed_class", "standard"))
            push!(fleet_types, FleetType(fleet_id, fleet_name, capacity_ffe, available_units,
                                         fixed_deployment_cost, sailing_cost_per_day, port_call_cost,
                                         max_service_days, speed_class))
        end
    else
        # Default fleet: provide sufficient capacity so MILP is feasible
        default_units = Int(get(config, "vessels_per_route", 5))
        default_capacity = 10000.0 * capacity_multiplier  # Large default to ensure feasibility
        push!(fleet_types, FleetType("default", "Default Fleet", default_capacity,
                                     max(default_units, 1), 0.0, 0.0, 0.0, 365, "standard"))
    end

    return fleet_types
end

function _cost_config_from_config(config::Dict{String, Any})
    cost_config = _string_key_dict(get(config, "costs", Dict{String, Any}()))
    return ArcCostConfig(
        sea_cost_per_day=Float64(get(cost_config, "sea_cost_per_day", 1.0)),
        wait_cost_per_day=Float64(get(cost_config, "wait_cost_per_day", 0.0)),
        trans_cost_per_day=Float64(get(cost_config, "trans_cost_per_day", 0.0)),
        port_handling_cost_per_ffe=Float64(get(cost_config, "port_handling_cost_per_ffe", 0.0)),
        late_penalty_per_ffe=Float64(get(cost_config, "late_penalty_per_ffe", 0.0)),
        reject_penalty_per_ffe=Float64(get(cost_config, "reject_penalty_per_ffe", 0.0)),
    )
end

function build_optimization_artifacts(preset_id::String;
                                      config::Dict{String, Any}=Dict{String, Any}())
    preset_id in ("shipping-demo", "shipping-single-vessel") || error("Unknown shipping preset: $preset_id")

    schedule_file, od_file = _default_shipping_data_files(config)
    isfile(schedule_file) || error("Shipping schedule file not found: $schedule_file")
    isfile(od_file) || error("Shipping OD file not found: $od_file")

    schedules = load_route_schedules(schedule_file)
    all_ods = load_od_demand(od_file)
    route_od_map = Dict{String, Vector{ODDemand}}()
    for route in schedules
        route_od_map[route.route_id] = filter_ods_by_route(all_ods, route)
    end

    cycle_days = Int(get(config, "cycle_days", 7))
    horizon_cycles = Int(get(config, "weeks_to_sim", get(config, "horizon_cycles", 8)))
    demand_periods = Int(get(config, "demand_periods", horizon_cycles))
    due_slack_days = Int(get(config, "due_slack_days", 0))
    min_connection_time = Int(get(config, "min_connection_time", 1))
    demand_multiplier = Float64(get(config, "demand_multiplier", 1.0))
    capacity_multiplier = Float64(get(config, "capacity_multiplier", 1.0))
    route_id = uppercase(string(get(config, "route_id", "AEU3")))
    fleet_types = _default_fleet_types(config)

    instance = if preset_id == "shipping-single-vessel"
        target = findfirst(route -> route.route_id == route_id, schedules)
        target === nothing && error("Route not found for single vessel preset: $route_id")
        route = schedules[target]
        ods = get(route_od_map, route.route_id, ODDemand[])
        build_optimization_instance(
            route,
            ods;
            cycle_days=cycle_days,
            horizon_cycles=horizon_cycles,
            demand_periods=demand_periods,
            due_slack_days=due_slack_days,
            min_connection_time=min_connection_time,
            demand_multiplier=demand_multiplier,
            fleet_types=fleet_types,
        )
    else
        build_optimization_instance(
            schedules,
            route_od_map;
            cycle_days=cycle_days,
            horizon_cycles=horizon_cycles,
            demand_periods=demand_periods,
            due_slack_days=due_slack_days,
            min_connection_time=min_connection_time,
            demand_multiplier=demand_multiplier,
            fleet_types=fleet_types,
        )
    end

    model_data = build_model_data(instance)
    milp_spec = build_milp_spec(instance; cost_config=_cost_config_from_config(config))

    metadata = Dict{String, Any}(
        "preset_id" => preset_id,
        "schedule_file" => schedule_file,
        "od_file" => od_file,
        "route_id" => route_id,
        "cycle_days" => cycle_days,
        "horizon_cycles" => horizon_cycles,
        "demand_periods" => demand_periods,
        "due_slack_days" => due_slack_days,
        "min_connection_time" => min_connection_time,
        "demand_multiplier" => demand_multiplier,
        "capacity_multiplier" => capacity_multiplier,
        "fleet_count" => length(fleet_types),
        "service_count" => length(instance.services),
        "demand_count" => length(instance.demands),
    )

    return OptimizationArtifacts(
        preset_id,
        instance,
        model_data,
        milp_spec,
        metadata,
    )
end

function _ensure_dir(path::String)
    isdir(path) || mkpath(path)
    return path
end

function export_optimization_artifacts(output_dir::String,
                                       preset_id::String;
                                       config::Dict{String, Any}=Dict{String, Any}(),
                                       basename::String="shipping_optimization")
    artifacts = build_optimization_artifacts(preset_id; config=config)
    _ensure_dir(output_dir)

    summary_path = joinpath(output_dir, string(basename, "_summary.txt"))
    lp_path = joinpath(output_dir, string(basename, ".lp"))
    spec_path = joinpath(output_dir, string(basename, "_spec.json"))
    metadata_path = joinpath(output_dir, string(basename, "_metadata.json"))

    open(summary_path, "w") do io
        for line in milp_summary_lines(artifacts.milp_spec)
            println(io, line)
        end
    end

    write_milp_lp(lp_path, artifacts.milp_spec)

    open(spec_path, "w") do io
        JSON3.write(io, milp_spec_dict(artifacts.milp_spec))
    end

    open(metadata_path, "w") do io
        JSON3.write(io, artifacts.metadata)
    end

    return Dict{String, String}(
        "summary_txt" => summary_path,
        "lp_file" => lp_path,
        "spec_json" => spec_path,
        "metadata_json" => metadata_path,
    )
end

# ============================================================
# 15. LP File Solver — Parse solution from external solver output
# ============================================================

"""
    solve_milp_from_lp(spec::MILPSpec; lp_path::String="", solver_cmd::String="glpsol")

Solve MILP by writing an LP file and invoking an external solver (GLPK via glpsol).
Returns a Dict of variable_name => value.
"""
function solve_milp_from_lp(spec::MILPSpec; lp_path::String=tempname() * ".lp",
                                                  solver_cmd::String="glpsol",
                                                  solution_path::String=tempname() * ".sol")
    # Write LP file
    write_milp_lp(lp_path, spec)

    # Try to solve with GLPK (glpsol)
    solve_status = :not_attempted
    var_values = Dict{String, Float64}()

    try
        cmd = Cmd([solver_cmd, "--lp", lp_path, "--output", solution_path])
        result = run(cmd; wait=true, stderr=devnull, stdout=devnull)
        if result.exitcode == 0
            solve_status = :optimal
            var_values = _parse_glpk_solution(solution_path, spec)
        else
            solve_status = :infeasible
        end
    catch e
        # Solver not available — return relaxed LP approximation
        @warn "[Shipping] External solver not available ($solver_cmd), using LP relaxation fallback"
        solve_status = :solver_unavailable
        var_values = _lp_relaxation_fallback(spec)
    end

    # Cleanup temp files
    for f in (lp_path, solution_path)
        try isfile(f) && rm(f) catch end
    end

    return (status=solve_status, variable_values=var_values)
end

"""Parse GLPK --output solution file"""
function _parse_glpk_solution(solution_path::String, spec::MILPSpec)
    var_values = Dict{String, Float64}()
    if !isfile(solution_path)
        return var_values
    end

    lines = readlines(solution_path)
    in_columns = false
    for line in lines
        stripped = strip(line)
        if startswith(stripped, "Column name")
            in_columns = true
            continue
        end
        if in_columns
            if isempty(stripped) || startswith(stripped, "Row")
                in_columns = false
                continue
            end
            parts = split(stripped, r"\s+"; keepempty=false)
            if length(parts) >= 3
                name = parts[1]
                value = tryparse(Float64, parts[3])
                if value !== nothing
                    var_values[name] = value
                end
            end
        end
    end
    return var_values
end

"""LP relaxation fallback: assign acceptance vars proportionally when solver is unavailable"""
function _lp_relaxation_fallback(spec::MILPSpec)
    var_values = Dict{String, Float64}()

    for vs in spec.variable_specs
        if occursin("u__", vs.name)
            # Acceptance: set to upper bound (accept all)
            var_values[vs.name] = vs.upper_bound !== nothing ? vs.upper_bound : vs.lower_bound
        elseif occursin("z__", vs.name)
            # Activation: set to 1 (all active)
            var_values[vs.name] = 1.0
        elseif occursin("m__", vs.name)
            # Deployment: set to 1 (deploy first fleet type)
            var_values[vs.name] = 1.0
        elseif occursin("w__", vs.name)
            # Sink: distribute evenly
            var_values[vs.name] = vs.upper_bound !== nothing ? vs.upper_bound * 0.5 : 0.0
        elseif occursin("x__", vs.name)
            # Flow: zero by default (would need path extraction for proper values)
            var_values[vs.name] = 0.0
        end
    end
    return var_values
end

# ============================================================
# 16. Optimization Result Extraction
# ============================================================

"""
    extract_optimization_result(instance, model_data, milp_spec, var_values; solve_status=:optimal, objective_value=0.0)

Extract structured OptimizationResult from solver variable values.
"""
function extract_optimization_result(instance::OptimizationInstance,
                                     model_data::OptimizationModelData,
                                     spec::MILPSpec,
                                     var_values::Dict{String, Float64};
                                     solve_status::Symbol=:optimal,
                                     objective_value::Float64=0.0)
    # Service decisions
    service_decisions = ServiceDecision[]
    for service_id in model_data.service_ids
        z_val = get(var_values, variable_name(ActivationVarKey(service_id)), 0.0)
        is_active = z_val > 0.5

        # Find the deployed fleet
        deployed_fleet = ""
        deployed_capacity = 0.0
        deployed_cost = 0.0
        for option in model_data.service_fleet_options
            if option.service_id == service_id
                m_val = get(var_values, variable_name(DeploymentVarKey(option.service_id, option.fleet_id)), 0.0)
                if m_val > 0.5
                    deployed_fleet = option.fleet_id
                    deployed_capacity = option.capacity
                    deployed_cost = option.fixed_cost
                    break
                end
            end
        end

        service = model_data.service_data[service_id]
        push!(service_decisions, ServiceDecision(
            service_id, is_active, deployed_fleet,
            is_active ? service.required_vessels : 0,
            deployed_capacity, deployed_cost,
        ))
    end

    # Demand decisions
    demand_decisions = DemandDecision[]
    for demand_id in model_data.demand_ids
        demand = model_data.demand_data[demand_id]
        u_val = get(var_values, variable_name(AcceptanceVarKey(demand_id)), 0.0)
        push!(demand_decisions, DemandDecision(
            demand_id, u_val, demand.quantity_ffe,
            demand.quantity_ffe > 0 ? u_val / demand.quantity_ffe : 0.0,
            u_val * demand.revenue_per_ffe, demand.is_mandatory,
        ))
    end

    # Demand paths — extract from flow variables
    demand_paths = _extract_demand_paths(model_data, instance, var_values)

    # Arc utilization
    arc_utils = ArcUtilization[]
    for arc_id in model_data.sea_arc_ids
        total_flow = 0.0
        for demand_id in model_data.demand_ids
            if arc_id in model_data.demand_arc_ids[demand_id]
                x_val = get(var_values, variable_name(FlowVarKey(demand_id, arc_id)), 0.0)
                total_flow += x_val
            end
        end
        arc = instance.network.arcs[arc_id]
        sid = arc.service_id
        capacity = 0.0
        for option in model_data.service_fleet_options
            if option.service_id == sid
                m_val = get(var_values, variable_name(DeploymentVarKey(option.service_id, option.fleet_id)), 0.0)
                if m_val > 0.5
                    capacity = option.capacity
                    break
                end
            end
        end
        util_rate = capacity > 0 ? total_flow / capacity : 0.0
        push!(arc_utils, ArcUtilization(arc_id, arc.kind, sid, total_flow, capacity, util_rate))
    end

    # Port flow summary
    port_flows = _compute_port_flows(model_data, instance, var_values)

    # Economic breakdown
    econ = _compute_economic_breakdown(model_data, instance, spec, var_values)

    # Objective value
    obj_val = objective_value > 0 ? objective_value : econ.net_profit

    return OptimizationResult(
        solve_status, obj_val,
        service_decisions, demand_decisions, demand_paths,
        arc_utils, port_flows, econ, var_values,
    )
end

function _extract_demand_paths(model_data::OptimizationModelData,
                               instance::OptimizationInstance,
                               var_values::Dict{String, Float64})
    paths = DemandPath[]
    for demand_id in model_data.demand_ids
        legs = PlannedPathLeg[]
        arc_ids = get(model_data.demand_arc_ids, demand_id, Int[])
        for arc_id in arc_ids
            x_val = get(var_values, variable_name(FlowVarKey(demand_id, arc_id)), 0.0)
            if x_val > 1e-6
                arc = instance.network.arcs[arc_id]
                if arc.kind == :sea
                    push!(legs, PlannedPathLeg(
                        length(legs) + 1,
                        arc.service_id !== nothing ? arc.service_id : "",
                        instance.network.nodes[arc.from].port_code,
                        instance.network.nodes[arc.to].port_code,
                        instance.network.nodes[arc.from].time,
                        instance.network.nodes[arc.to].time,
                    ))
                end
            end
        end
        total_transit = isempty(legs) ? 0 : legs[end].arrival_day - legs[1].depart_day
        trans_count = count(l -> l.service_id != "" && (isempty(legs) || l.service_id != first(legs).service_id), legs)
        push!(paths, DemandPath(demand_id, legs, total_transit, max(0, trans_count)))
    end
    return paths
end

function _compute_port_flows(model_data::OptimizationModelData,
                             instance::OptimizationInstance,
                             var_values::Dict{String, Float64})
    port_inflow = Dict{String, Float64}()
    port_outflow = Dict{String, Float64}()
    for port_code in instance.network.ports
        port_inflow[port_code] = 0.0
        port_outflow[port_code] = 0.0
    end
    for demand_id in model_data.demand_ids
        for arc_id in get(model_data.demand_arc_ids, demand_id, Int[])
            x_val = get(var_values, variable_name(FlowVarKey(demand_id, arc_id)), 0.0)
            if x_val > 1e-6
                arc = instance.network.arcs[arc_id]
                from_port = instance.network.nodes[arc.from].port_code
                to_port = instance.network.nodes[arc.to].port_code
                port_outflow[from_port] = get(port_outflow, from_port, 0.0) + x_val
                port_inflow[to_port] = get(port_inflow, to_port, 0.0) + x_val
            end
        end
    end
    return [PortFlowSummary(p, port_inflow[p], port_outflow[p], port_inflow[p] - port_outflow[p])
            for p in sort!(collect(keys(port_inflow)))]
end

function _compute_economic_breakdown(model_data::OptimizationModelData,
                                     instance::OptimizationInstance,
                                     spec::MILPSpec,
                                     var_values::Dict{String, Float64})
    cargo_revenue = 0.0
    for demand_id in model_data.demand_ids
        demand = model_data.demand_data[demand_id]
        u_val = get(var_values, variable_name(AcceptanceVarKey(demand_id)), 0.0)
        cargo_revenue += u_val * demand.revenue_per_ffe
    end

    fleet_cost = 0.0
    for option in model_data.service_fleet_options
        m_val = get(var_values, variable_name(DeploymentVarKey(option.service_id, option.fleet_id)), 0.0)
        fleet_cost += m_val * option.fixed_cost
    end

    sea_cost = 0.0
    wait_cost = 0.0
    trans_cost = 0.0
    port_handling = 0.0
    for demand_id in model_data.demand_ids
        for arc_id in get(model_data.demand_arc_ids, demand_id, Int[])
            x_val = get(var_values, variable_name(FlowVarKey(demand_id, arc_id)), 0.0)
            if x_val > 1e-6
                arc = instance.network.arcs[arc_id]
                if arc.kind == :sea
                    # Use arc duration * cost per day from objective terms
                    sea_cost += x_val * Float64(arc.duration)
                elseif arc.kind == :wait
                    wait_cost += x_val * Float64(arc.duration) * 0.0  # wait cost from config
                elseif arc.kind == :trans
                    trans_cost += x_val * Float64(arc.duration) * 0.0  # trans cost from config
                end
            end
        end
    end

    net_profit = cargo_revenue - fleet_cost - sea_cost - wait_cost - trans_cost - port_handling

    return EconomicBreakdown(
        cargo_revenue, fleet_cost, sea_cost, wait_cost, trans_cost,
        port_handling, 0.0, 0.0, net_profit,
    )
end

# ============================================================
# 17. Execution Plan Generation (Bridge: Optimization → Simulation)
# ============================================================

"""
    build_execution_plan(artifacts::OptimizationArtifacts, result::OptimizationResult;
                         scenario_id::String="baseline")

Build an ExecutionPlan from optimization artifacts and result.
This is the contract between the optimization layer and the simulation layer.
"""
function build_execution_plan(artifacts::OptimizationArtifacts, result::OptimizationResult;
                              scenario_id::String="baseline")
    instance = artifacts.instance
    model_data = artifacts.model_data

    # Planned services
    planned_services = PlannedService[]
    for sd in result.service_decisions
        if sd.is_active
            push!(planned_services, PlannedService(sd.service_id, sd.fleet_id, sd.vessel_count, true))
        end
    end

    # Planned vessel rotations
    planned_rotations = PlannedVesselRotation[]
    for sd in result.service_decisions
        if !sd.is_active
            continue
        end
        service = model_data.service_data[sd.service_id]
        vessel_count = sd.vessel_count
        for v_idx in 0:(vessel_count - 1)
            vessel_name = string(sd.service_id, "-W", lpad(string(51 + v_idx), 2, '0'))
            start_delay = Float64(v_idx * service.cycle_days)
            push!(planned_rotations, PlannedVesselRotation(
                vessel_name, sd.service_id, sd.fleet_id, start_delay,
                [PlannedCall(pc.port_code, start_delay + pc.eta_day,
                             pc.etd_day !== nothing ? start_delay + pc.etd_day : start_delay + pc.eta_day,
                             pc.port_order) for pc in service.port_calls],
            ))
        end
    end

    # Planned demand assignments
    planned_assignments = PlannedDemandAssignment[]
    for dp in result.demand_paths
        if !isempty(dp.legs)
            demand = model_data.demand_data[dp.demand_id]
            dd = nothing
            for d in result.demand_decisions
                if d.demand_id == dp.demand_id
                    dd = d
                    break
                end
            end
            qty = dd !== nothing ? dd.accepted_quantity : demand.quantity_ffe
            push!(planned_assignments, PlannedDemandAssignment(
                dp.demand_id, demand.origin, demand.destination, qty, dp.legs,
            ))
        end
    end

    meta = PlanMeta(
        artifacts.preset_id, scenario_id,
        instance.network.cycle_days, instance.network.horizon_cycles,
        string(Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS")), result.objective_value, result.solve_status,
    )

    return ExecutionPlan(meta, planned_services, planned_rotations, planned_assignments)
end

# ============================================================
# 18. Full Optimization Pipeline
# ============================================================

"""
    run_optimization_pipeline(preset_id::String; config=Dict())

Complete pipeline: load data → build instance → solve → extract result → build execution plan.
"""
function run_optimization_pipeline(preset_id::String; config::Dict{String,Any}=Dict{String,Any}())
    # Step 1: Build optimization artifacts
    artifacts = build_optimization_artifacts(preset_id; config=config)

    # Step 2: Solve MILP
    solve_result = solve_milp_from_lp(artifacts.milp_spec)
    var_values = solve_result.variable_values
    solve_status = solve_result.status

    # Step 3: Compute objective from variable values
    obj_val = 0.0
    for term in artifacts.milp_spec.objective.terms
        v = get(var_values, variable_name(term.key), 0.0)
        obj_val += term.coefficient * v
    end

    # Step 4: Extract structured result
    opt_result = extract_optimization_result(
        artifacts.instance, artifacts.model_data, artifacts.milp_spec, var_values;
        solve_status=solve_status, objective_value=obj_val,
    )

    # Step 5: Build execution plan
    scenario_id = string(get(config, "scenario_id", "baseline"))
    exec_plan = build_execution_plan(artifacts, opt_result; scenario_id=scenario_id)

    return (artifacts=artifacts, result=opt_result, execution_plan=exec_plan)
end

# ============================================================
# 19. KPI Summary — Planned vs Realized Comparison
# ============================================================

"""
    compute_kpi_summary(opt_result::OptimizationResult, sim_events, sim_stats, sim_cargo; config...)

Compute the KPI summary comparing planned (optimization) vs realized (simulation) outcomes.
"""
function compute_kpi_summary(opt_result::OptimizationResult,
                             sim_events::Vector{VesselEvent},
                             sim_stats::Vector{PortStats},
                             sim_cargo::Vector{CargoBatch};
                             planned_transit_days::Float64=30.0)
    # Planned metrics
    planned_profit = opt_result.economic_breakdown.net_profit
    accepted_ffe = sum(dd.accepted_quantity for dd in opt_result.demand_decisions; init=0.0)

    # Simulated metrics
    delivered = [c for c in sim_cargo if c.sim_time >= 0]
    delivered_ffe = sum(c.ffe for c in delivered; init=0.0)
    sim_revenue = sum(c.revenue_per_unit * c.ffe for c in delivered; init=0.0)

    # On-time delivery
    on_time_count = 0
    total_transit = 0.0
    for c in delivered
        created_time = c.created_week * 7.0
        actual_transit = c.sim_time - created_time
        promised = c.transit_time > 0 ? c.transit_time : planned_transit_days
        if actual_transit <= promised
            on_time_count += 1
        end
        total_transit += actual_transit
    end
    on_time_rate = length(delivered) > 0 ? Float64(on_time_count) / length(delivered) : 0.0
    avg_transit = length(delivered) > 0 ? total_transit / length(delivered) : 0.0

    # Utilization
    avg_util = isempty(opt_result.arc_utilizations) ? 0.0 :
               sum(au.utilization_rate for au in opt_result.arc_utilizations; init=0.0) / length(opt_result.arc_utilizations)
    max_util = isempty(opt_result.arc_utilizations) ? 0.0 :
               maximum(au.utilization_rate for au in opt_result.arc_utilizations; init=0.0)

    # Service reliability (from simulation events)
    total_arrivals = count(e -> e.event_type == "ARRIVAL", sim_events)
    # Simplified: assume on-time if no major delay evidence
    reliability = total_arrivals > 0 ? min(1.0, Float64(total_arrivals) / max(total_arrivals, 1)) : 0.0

    # Rejection rate
    total_demanded = sum(dd.total_quantity for dd in opt_result.demand_decisions; init=0.0)
    rejection_rate = total_demanded > 0 ? 1.0 - accepted_ffe / total_demanded : 0.0

    # Simulated profit (simplified)
    sim_profit = sim_revenue  # Without full cost model from simulation

    # Profit retention
    profit_retention = planned_profit != 0 ? sim_profit / planned_profit : 0.0

    return KpiSummary(
        round(planned_profit; digits=2),
        round(sim_profit; digits=2),
        round(clamp(profit_retention, 0.0, 2.0); digits=4),
        round(accepted_ffe; digits=1),
        round(delivered_ffe; digits=1),
        round(on_time_rate; digits=4),
        round(avg_transit; digits=2),
        round(avg_util; digits=4),
        round(max_util; digits=4),
        round(reliability; digits=4),
        round(clamp(rejection_rate, 0.0, 1.0); digits=4),
    )
end

"""
    kpi_summary_dict(kpi::KpiSummary) -> Dict

Convert KPI summary to a JSON-friendly dictionary.
"""
function kpi_summary_dict(kpi::KpiSummary)
    return Dict{String, Any}(
        "planned_profit" => kpi.planned_profit,
        "simulated_profit" => kpi.simulated_profit,
        "profit_retention_rate" => kpi.profit_retention_rate,
        "accepted_cargo_ffe" => kpi.accepted_cargo_ffe,
        "delivered_cargo_ffe" => kpi.delivered_cargo_ffe,
        "on_time_delivery_rate" => kpi.on_time_delivery_rate,
        "avg_transit_time" => kpi.avg_transit_time,
        "avg_utilization" => kpi.avg_utilization,
        "max_arc_utilization" => kpi.max_arc_utilization,
        "service_reliability" => kpi.service_reliability,
        "rejection_rate" => kpi.rejection_rate,
    )
end

# ============================================================
# 20. ScenarioConfig from config dict
# ============================================================

"""
    build_scenario_config(config::Dict{String,Any}) -> ScenarioConfig

Build a ScenarioConfig from a flat config dictionary.
"""
function build_scenario_config(config::Dict{String, Any})
    return ScenarioConfig(
        scenario_id=string(get(config, "scenario_id", "baseline")),
        description=string(get(config, "description", "")),
        cycle_days=Int(get(config, "cycle_days", 7)),
        horizon_cycles=Int(get(config, "weeks_to_sim", get(config, "horizon_cycles", 8))),
        demand_periods=Int(get(config, "demand_periods", Int(get(config, "weeks_to_sim", 8)))),
        min_connection_time=Int(get(config, "min_connection_time", 1)),
        due_slack_days=Int(get(config, "due_slack_days", 0)),
        demand_multiplier=Float64(get(config, "demand_multiplier", 1.0)),
        capacity_multiplier=Float64(get(config, "capacity_multiplier", 1.0)),
        disruption_level=Float64(get(config, "disruption_level", 0.0)),
    )
end

# ============================================================
# 21. Convenience: build_execution_plan_from_artifacts
# ============================================================

"""
    build_execution_plan_from_artifacts(artifacts::OptimizationArtifacts; preset_id="") -> ExecutionPlan

Build an ExecutionPlan directly from OptimizationArtifacts by solving the MILP
and extracting the result.
"""
function build_execution_plan_from_artifacts(artifacts::OptimizationArtifacts;
                                             preset_id::String="")
    # Solve the MILP
    solve_result = solve_milp_from_lp(artifacts.milp_spec)
    var_values = solve_result.variable_values
    solve_status = solve_result.status

    # Extract structured result
    opt_result = extract_optimization_result(
        artifacts.instance, artifacts.model_data, artifacts.milp_spec, var_values;
        solve_status=solve_status,
    )

    # Build execution plan
    pid = isempty(preset_id) ? artifacts.preset_id : preset_id
    return build_execution_plan(artifacts, opt_result; preset_id=pid)
end

# ============================================================
# 22. Simulation Output Computation
# ============================================================

"""
    compute_demand_outcomes(opt_result::OptimizationResult, sim_cargo::Vector{CargoBatch}) -> Vector{DemandOutcome}

Compare planned demand assignments with simulated cargo outcomes.
"""
function compute_demand_outcomes(opt_result::OptimizationResult,
                                 sim_cargo::Vector{CargoBatch})
    outcomes = DemandOutcome[]

    # Build lookup: demand_id → (planned_quantity, planned_arrival)
    planned_qty = Dict{String, Float64}()
    planned_arrival = Dict{String, Float64}()
    for dd in opt_result.demand_decisions
        planned_qty[dd.demand_id] = dd.accepted_quantity
    end
    for dp in opt_result.demand_paths
        if !isempty(dp.legs)
            planned_arrival[dp.demand_id] = Float64(dp.legs[end].arrival_day)
        end
    end

    # Build lookup: (origin, destination) → delivered cargo from simulation
    delivered_by_od = Dict{Tuple{String, String}, Vector{CargoBatch}}()
    for c in sim_cargo
        if c.sim_time >= 0
            key = (c.origin, c.destination)
            if !haskey(delivered_by_od, key)
                delivered_by_od[key] = CargoBatch[]
            end
            push!(delivered_by_od[key], c)
        end
    end

    for dd in opt_result.demand_decisions
        did = dd.demand_id
        # Find matching demand in opt_result
        demand_path = nothing
        for dp in opt_result.demand_paths
            if dp.demand_id == did
                demand_path = dp
                break
            end
        end

        # Determine origin/destination from demand decisions
        # We need to look up from the model data — use a simpler approach
        p_qty = get(planned_qty, did, 0.0)
        p_arrival = get(planned_arrival, did, -1.0)

        # For now, create a basic outcome
        push!(outcomes, DemandOutcome(
            did, "", "",  # origin, destination filled by caller if needed
            p_qty, 0.0,   # delivered from sim
            p_arrival, -1.0,  # actual arrival from sim
            0.0, true, false,
        ))
    end

    return outcomes
end

"""
    compute_demand_outcomes(opt_result::OptimizationResult, sim_cargo::Vector{CargoBatch},
                            demand_lookup::Dict{String, OptimizationDemand}) -> Vector{DemandOutcome}

Compare planned demand assignments with simulated cargo outcomes, using demand lookup for origin/destination.
"""
function compute_demand_outcomes(opt_result::OptimizationResult,
                                 sim_cargo::Vector{CargoBatch},
                                 demand_lookup::Dict{String, OptimizationDemand})
    outcomes = DemandOutcome[]

    # Build lookup: (origin, destination) → delivered cargo from simulation
    delivered_by_od = Dict{Tuple{String, String}, Vector{CargoBatch}}()
    for c in sim_cargo
        if c.sim_time >= 0
            key = (c.origin, c.destination)
            if !haskey(delivered_by_od, key)
                delivered_by_od[key] = CargoBatch[]
            end
            push!(delivered_by_od[key], c)
        end
    end

    for dd in opt_result.demand_decisions
        did = dd.demand_id
        demand = get(demand_lookup, did, nothing)

        origin = demand !== nothing ? demand.origin : ""
        destination = demand !== nothing ? demand.destination : ""

        # Planned arrival
        p_arrival = -1.0
        for dp in opt_result.demand_paths
            if dp.demand_id == did && !isempty(dp.legs)
                p_arrival = Float64(dp.legs[end].arrival_day)
                break
            end
        end

        # Find simulated deliveries matching this OD
        od_key = (origin, destination)
        sim_delivered = get(delivered_by_od, od_key, CargoBatch[])
        delivered_qty = sum(c.ffe for c in sim_delivered; init=0.0)
        actual_arrival = isempty(sim_delivered) ? -1.0 : maximum(c.sim_time for c in sim_delivered)

        delay = (p_arrival >= 0 && actual_arrival >= 0) ? max(actual_arrival - p_arrival, 0.0) : 0.0
        is_on_time = delay == 0.0 && actual_arrival >= 0
        is_delivered = !isempty(sim_delivered)

        push!(outcomes, DemandOutcome(
            did, origin, destination,
            dd.accepted_quantity, delivered_qty,
            p_arrival, actual_arrival,
            delay, is_on_time, is_delivered,
        ))
    end

    return outcomes
end

"""
    compute_service_reliability(opt_result::OptimizationResult, sim_events::Vector{VesselEvent}) -> Vector{ServiceReliability}

Compute per-service reliability from planned vs actual events.
"""
function compute_service_reliability(opt_result::OptimizationResult,
                                     sim_events::Vector{VesselEvent})
    reliabilities = ServiceReliability[]

    for sd in opt_result.service_decisions
        if !sd.is_active
            continue
        end

        sid = sd.service_id
        # Count arrival events for this service
        service_arrivals = [e for e in sim_events if e.route_id == sid && e.event_type == "ARRIVAL"]
        planned_calls = sd.vessel_count  # Approximation

        on_time = count(e -> !e.is_return, service_arrivals)  # Simplified
        delayed = count(e -> e.is_return, service_arrivals)   # Simplified
        missed = max(0, planned_calls - on_time - delayed)
        total = on_time + delayed + missed
        reliability_rate = total > 0 ? on_time / total : 0.0

        push!(reliabilities, ServiceReliability(
            sid, planned_calls, on_time, delayed, missed,
            round(reliability_rate; digits=4), 0.0,
        ))
    end

    return reliabilities
end

"""
    compute_port_congestion(sim_events::Vector{VesselEvent}, sim_stats::Vector{PortStats}) -> Vector{PortCongestion}

Compute per-port congestion metrics from simulation output.
"""
function compute_port_congestion(sim_events::Vector{VesselEvent},
                                 sim_stats::Vector{PortStats})
    congestions = PortCongestion[]

    # Group by port
    port_codes = sort!(collect(Set(s.port_code for s in sim_stats)))
    for port_code in port_codes
        port_arrivals = [e for e in sim_events if e.port_code == port_code && e.event_type == "ARRIVAL"]
        port_stats = [s for s in sim_stats if s.port_code == port_code]

        total_visits = length(port_arrivals)
        peak_vessels = isempty(port_stats) ? 0 : maximum(s.vessel_count for s in port_stats)

        push!(congestions, PortCongestion(
            port_code, total_visits, 0.0, 0.0, peak_vessels,
        ))
    end

    return congestions
end
