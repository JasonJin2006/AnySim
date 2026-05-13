using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

include(joinpath(@__DIR__, "..", "src", "AnySim.jl"))
using .AnySim
include(joinpath(@__DIR__, "..", "extensions", "registry.jl"))
include(joinpath(@__DIR__, "..", "extensions", "DEVS", "DEVS.jl"))
using .DEVS
include(joinpath(@__DIR__, "..", "extensions", "DEVS", "server.jl"))
include(joinpath(@__DIR__, "..", "extensions", "Shipping", "Shipping.jl"))
using .Shipping
using JSON3
using Test
using UUIDs

@testset "AnySim Smoke" begin
    @test isdefined(AnySim, :compile)
    @test isdefined(AnySim, :solve)
    @test !isdefined(AnySim, :DEVSSolver)
    @test isdefined(DEVS, :DEVSSolver)
    @test !isdefined(AnySim, :build_shipping_network)

    @devs_atomic SmokeCounter begin
        @state count = 0

        @ta begin
            hold_in(state, :active, 1.0)
        end

        @deltint begin
            count += 1
            hold_in(state, :active, 1.0)
        end
    end

    model = ComposeDef(:SmokeModel, [SmokeCounter], Relation[], Connection[], [])
    result = solve(DEVSSolver(max_steps=3, max_time=10.0), model)

    @test !isempty(result.times)
    @test result.times[1] == 0.0
end

@testset "DEVS Solver Boundaries" begin
    @devs_atomic TickModel begin
        @state count = 0

        @ta begin
            hold_in(state, :active, 1.0)
        end

        @deltint begin
            count += 1
            hold_in(state, :active, 1.0)
        end
    end

    tick_model = ComposeDef(:TickModelRoot, [TickModel], Relation[], Connection[], [])

    max_time_result = solve(DEVSSolver(max_steps=100, max_time=2.5), tick_model)
    @test max_time_result.times == [0.0, 1.0, 2.0]
    @test max_time_result.states[:TickModel_count] == [0.0, 1.0, 2.0]

    max_steps_result = solve(DEVSSolver(max_steps=2, max_time=100.0), tick_model)
    @test max_steps_result.times == [0.0, 1.0, 2.0]
    @test max_steps_result.states[:TickModel_count] == [0.0, 1.0, 2.0]
end

@testset "DEVS Solver Stop Conditions" begin
    @devs_atomic OneShotModel begin
        @state fired = 0

        @ta begin
            if fired == 0
                hold_in(state, :active, 3.0)
            else
                passivate(state)
            end
        end

        @deltint begin
            fired += 1
            passivate(state)
        end
    end

    one_shot_model = ComposeDef(:OneShotRoot, [OneShotModel], Relation[], Connection[], [])
    one_shot_result = solve(DEVSSolver(max_steps=10, max_time=100.0), one_shot_model)

    @test one_shot_result.times == [0.0, 3.0]
    @test one_shot_result.states[:OneShotModel_fired] == [0.0, 1.0]
end

@testset "Structured Diagnostics" begin
    bad_entity = EntityDef(
        :BadEntity,
        [Port(:p, Float64, :in), Port(:p, Float64, :out)],
        [
            Relation(:r, Equation, :(x == 1), Symbol[]),
            Relation(:r, Equation, :(y == 2), Symbol[]),
        ],
        [
            Parameter(:k, 1.0, Float64),
            Parameter(:k, 2.0, Float64),
        ],
    )

    entity_diags = validate_diagnostics(bad_entity)
    entity_codes = Set(diag.code for diag in entity_diags)

    @test length(entity_diags) == 3
    @test E_NAME_DUPLICATE_PORT in entity_codes
    @test E_NAME_DUPLICATE_RELATION in entity_codes
    @test E_NAME_DUPLICATE_PARAMETER in entity_codes
    @test any(diag -> diag.ai_hint["goal"] isa String, entity_diags)
    @test all(diag -> all(isascii, join(diag.repair_hints, "")), entity_diags)

    source = EntityDef(:Source, [Port(:out, Float64, :out)], Relation[], Parameter[])
    target = EntityDef(:Target, [Port(:in, Float64, :out)], Relation[], Parameter[])

    bad_compose = ComposeDef(
        :BadCompose,
        [source, target],
        Relation[],
        [
            Connection((:Ghost, :out), (:Target, :in)),
            Connection((:Source, :missing), (:Target, :in)),
            Connection((:Source, :out), (:Target, :in)),
        ],
        [],
    )

    compose_diags = validate_diagnostics(bad_compose)
    compose_codes = Set(diag.code for diag in compose_diags)

    @test E_TOPOLOGY_UNKNOWN_ENTITY in compose_codes
    @test E_PORT_INVALID_REFERENCE in compose_codes
    @test E_TOPOLOGY_INVALID_DIRECTION in compose_codes
    @test !isempty(validate(bad_compose))

    first_dict = diagnostic_to_dict(compose_diags[1])
    @test haskey(first_dict, "code")
    @test haskey(first_dict, "ai_hint")
end

@testset "Diagnostic Exceptions" begin
    port_err = try
        AnySim.make_port(:(x + y))
        nothing
    catch err
        err
    end
    @test port_err isa DiagnosticError
    @test port_err.diagnostic.code == E_SYNTAX_UNSUPPORTED_PORT
    @test port_err.diagnostic.ai_hint["goal"] isa String
    @test all(isascii, join(port_err.diagnostic.repair_hints, ""))

    solver_err = try
        select_solver(; prefer=:NoSuchSolver)
        nothing
    catch err
        err
    end
    @test solver_err isa DiagnosticError
    @test solver_err.diagnostic.code == E_SOLVER_UNKNOWN
    @test "available_solvers" in collect(keys(solver_err.diagnostic.context))

    ode_expr_err = try
        AnySim._compile_ode_node(:(begin local z = 1 end))
        nothing
    catch err
        err
    end
    @test ode_expr_err isa DiagnosticError
    @test ode_expr_err.diagnostic.code == E_ODE_UNSUPPORTED_EXPRESSION

    send_err = try
        send!(:A, :B, :ping)
        nothing
    catch err
        err
    end
    @test send_err isa DiagnosticError
    @test send_err.diagnostic.code == E_RUNTIME_SEND_OUTSIDE_SIMULATION

    payload = diagnostic_payload(send_err)
    @test payload["type"] == "sim_error"
    @test payload["metadata"]["diagnostic"]["code"] == E_RUNTIME_SEND_OUTSIDE_SIMULATION

    generic_payload = exception_payload(ErrorException("boom"))
    @test generic_payload["type"] == "sim_error"
    @test generic_payload["metadata"]["diagnostic"]["code"] == E_RUNTIME_UNHANDLED
end

println("Smoke tests passed.")

@testset "Shipping Plugin Presets" begin
    register_extension!(Shipping.ShippingPlugin())
    plugin = find_plugin_for_preset("shipping-single-vessel")

    single = build_model(plugin, "shipping-single-vessel"; config=Dict{String,Any}(
        "route_id" => "AEU3",
        "first_week" => 51,
    ))

    @test single.model_name == "AEU3SingleVessel"
    @test any(e -> startswith(String(e.name), "AEU3_PT_"), single.entities)
    @test any(e -> String(e.name) == "AEU3-W51", single.entities)
    @test single.metadata["preset_id"] == "shipping-single-vessel"

    full = build_model(plugin, "shipping-demo"; config=Dict{String,Any}(
        "weeks_to_sim" => 2,
        "vessels_per_route" => 2,
        "first_week" => 51,
        "seed" => 42,
    ))

    @test full.model_name == "ShippingNetworkDemo"
    @test length(full.entities) > length(single.entities)
end

@testset "Shipping Single Vessel Outputs" begin
    register_extension!(Shipping.ShippingPlugin())
    plugin = find_plugin_for_preset("shipping-single-vessel")
    single = build_model(plugin, "shipping-single-vessel"; config=Dict{String,Any}(
        "route_id" => "AEU3",
        "first_week" => 51,
        "max_sim_time" => 200.0,
    ))

    result = Shipping.simulate_shipping_project(single.model; max_time=200.0, max_steps=1000)
    events_table = Shipping.shipping_events_table(result.events)
    stats_table = Shipping.shipping_port_stats_table(result.stats)

    @test !isempty(events_table)
    @test events_table[1]["route"] == "AEU3"
    @test events_table[1]["port"] == "CNTXG"
    @test events_table[1]["event_type"] == "ARRIVAL"
    @test events_table[1]["sim_time"] == 0.0
    @test any(row -> row["event_type"] == "DEPARTURE" && row["port"] == "CNTXG", events_table)
    @test any(row -> row["port"] == "CNSHA" && row["event_type"] == "ARRIVAL", events_table)
    @test stats_table isa Vector{Dict{String,Any}}
end

@testset "Shipping Result Export" begin
    register_extension!(Shipping.ShippingPlugin())
    plugin = find_plugin_for_preset("shipping-single-vessel")
    single = build_model(plugin, "shipping-single-vessel"; config=Dict{String,Any}(
        "route_id" => "AEU3",
        "first_week" => 51,
        "max_sim_time" => 200.0,
    ))

    result = Shipping.simulate_shipping_project(single.model; max_time=200.0, max_steps=1000)
    tmp_dir = mktempdir(prefix="anysim-shipping-export-")
    paths = Shipping.export_shipping_results(tmp_dir, result; basename="aeu3_single")

    @test isfile(paths["events_csv"])
    @test isfile(paths["stats_csv"])
    @test isfile(paths["cargo_csv"])
    @test isfile(paths["report_txt"])
    @test isfile(paths["scorecard_json"])

    events_text = read(paths["events_csv"], String)
    cargo_text = read(paths["cargo_csv"], String)
    report_text = read(paths["report_txt"], String)
    scorecard = JSON3.read(read(paths["scorecard_json"], String), Dict{String,Any})

    @test occursin("sim_time,vessel,route,port,event_type,port_order,is_return", events_text)
    @test occursin("sim_time,batch_id,origin,destination,ffe,revenue,week,route_id,transit_time,vessel", cargo_text)
    @test occursin("AEU3-W51", events_text)
    @test occursin("Shipping Simulation Report", report_text)
    @test occursin("Revenue:", report_text)
    @test occursin("Fuel Cost:", report_text)
    @test occursin("Net Profit:", report_text)
    @test scorecard["score"] isa Number
    @test haskey(scorecard, "operations")
    @test haskey(scorecard, "economics")
    @test haskey(scorecard["economics"], "fuel_cost_usd")
    @test haskey(scorecard["economics"], "port_cost_usd")
    @test haskey(scorecard["economics"], "time_cost_usd")
    @test haskey(scorecard["economics"], "total_cost_usd")
    @test haskey(scorecard["economics"], "net_profit_usd")
    @test scorecard["meta"]["step_count"] == length(result.history)
end

@testset "Shipping Optimization Layer" begin
    route = Shipping.RouteSchedule(
        "R1",
        Shipping.PortCall[
            Shipping.PortCall("AAA", 1, 0.0, 1.0),
            Shipping.PortCall("BBB", 2, 3.0, 4.0),
            Shipping.PortCall("CCC", 3, 6.0, nothing),
        ],
        6.0,
    )

    service = Shipping.build_service(route)
    @test service.route_id == "R1"
    @test service.cycle_days == 7
    @test service.route_total_days == 6
    @test service.required_vessels == 1
    @test length(service.legs) == 2
    @test service.legs[1].origin == "AAA"
    @test service.legs[1].destination == "BBB"
    @test service.legs[1].depart_day == 1
    @test service.legs[1].arrival_day == 3
    @test service.legs[2].depart_day == 4
    @test service.legs[2].arrival_day == 6

    network = Shipping.build_time_space_network(
        [service];
        horizon_cycles=2,
        cycle_days=7,
        min_connection_time=2,
    )

    @test network.cycle_days == 7
    @test network.horizon_cycles == 2
    @test network.total_layers == 3
    @test length(network.nodes) == 63
    @test haskey(network.service_arc_ids, "R1")
    @test length(network.service_arc_ids["R1"]) == 4
    @test any(arc -> arc.kind == :wait, network.arcs)
    @test any(arc -> arc.kind == :trans, network.arcs)

    first_leg_from = Shipping.node_id(network, "AAA", 1, 0)
    first_leg_to = Shipping.node_id(network, "BBB", 3, 0)
    @test any(arc -> arc.kind == :sea &&
                     arc.service_id == "R1" &&
                     arc.from == first_leg_from &&
                     arc.to == first_leg_to,
              network.arcs)

    ods = Shipping.ODDemand[
        Shipping.ODDemand("AAA", "CCC", 10.0, 1200.0, 5.0),
    ]

    demands = Shipping.build_optimization_demands(
        ods;
        periods=2,
        cycle_days=7,
        due_slack_days=1,
        prefix="R1",
    )

    @test length(demands) == 2
    @test demands[1].release_time == 0
    @test demands[1].due_time == 6
    @test demands[2].release_time == 7
    @test demands[2].due_time == 13

    instance = Shipping.build_optimization_instance(
        route,
        ods;
        horizon_cycles=2,
        demand_periods=2,
        due_slack_days=1,
        min_connection_time=2,
    )

    @test length(instance.services) == 1
    @test length(instance.demands) == 2
    @test instance.network.total_layers == 3

    first_demand = instance.demands[1]
    first_source_id = Shipping.source_node_id(instance, first_demand)
    first_source_node = instance.network.nodes[first_source_id]
    @test first_source_node.port_code == "AAA"
    @test first_source_node.time == 0

    first_sink_ids = Shipping.sink_node_ids(instance, first_demand)
    @test !isempty(first_sink_ids)
    @test all(node_id -> begin
            node = instance.network.nodes[node_id]
            node.port_code == "CCC" && node.time <= first_demand.due_time
        end, first_sink_ids)

    second_demand = instance.demands[2]
    second_source_node = instance.network.nodes[Shipping.source_node_id(instance, second_demand)]
    @test second_source_node.port_code == "AAA"
    @test second_source_node.time == 7
end

include(joinpath(@__DIR__, "ecosystem_integration_tests.jl"))

@testset "Shipping Output Port" begin
    register_extension!(Shipping.ShippingPlugin())
    runner = Main.SimRunner()
    Main._load_preset_model(runner, "shipping-single-vessel"; config=Dict{String,Any}(
        "route_id" => "AEU3",
        "first_week" => 51,
        "max_sim_time" => 200.0,
    ))

    @test haskey(runner.output_ports, "shipping-scorecard")

    runner.ctx = DEVS.init_devs_context(runner.model)
    for _ in 1:8
        result = DEVS.devs_step!(runner.ctx; max_time=200.0, capture_outputs=true)
        result isa Bool && continue
        runner.step_count += 1
        runner.current_time = runner.ctx.current_time
        Main._capture_domain_outputs!(runner, result.outputs)
    end

    @test !isempty(runner.shipping_events)
    @test haskey(runner.output_ports, "shipping-scorecard")

    port = runner.output_ports["shipping-scorecard"]
    @test port["label"] == "评分输出端口"
    @test port["kind"] == "scorecard"
    @test port["data"]["score"] isa Number
    @test port["data"]["meta"]["step_count"] == runner.step_count
end
