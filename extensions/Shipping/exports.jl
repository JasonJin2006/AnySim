import ..DEVS: DEVSContext, DEVSSolver, devs_collect_outputs, devs_step!, init_devs_context
import JSON3

function _ensure_dir(path::String)
    isdir(path) || mkpath(path)
    return path
end

function collect_shipping_snapshot!(snapshot::SimSnapshot,
                                    ctx::DEVSContext,
                                    outputs::Dict{Symbol, Vector{DEVSMessage}})
    snapshot.time = ctx.current_time

    for messages in values(outputs)
        for msg in messages
            value = msg.value
            if value isa VesselEvent
                push!(snapshot.events, deepcopy(value))
            elseif value isa PortStats
                push!(snapshot.stats, deepcopy(value))
            elseif value isa CargoBatch
                push!(snapshot.cargo, deepcopy(value))
            end
        end
    end

    return snapshot
end

function collect_shipping_history(ctx::DEVSContext; max_time::Float64=200.0, max_steps::Int=100000)
    history = SimSnapshot[]
    step = 0

    while step < max_steps
        result = devs_step!(ctx; max_time=max_time, capture_outputs=true)
        if result isa Bool
            result || break
            outputs = Dict{Symbol, Vector{DEVSMessage}}()
        else
            result.running || break
            outputs = result.outputs
        end
        if result isa Bool && !result
            break
        end
        snapshot = SimSnapshot(ctx.current_time)
        collect_shipping_snapshot!(snapshot, ctx, outputs)
        if !isempty(snapshot.events) || !isempty(snapshot.stats) || !isempty(snapshot.cargo)
            push!(history, snapshot)
        end
        step += 1
    end

    return history
end

function simulate_shipping_project(model::ComposeDef; max_time::Float64=200.0, max_steps::Int=100000)
    ctx = init_devs_context(model)
    history = collect_shipping_history(ctx; max_time=max_time, max_steps=max_steps)

    events = VesselEvent[]
    stats = PortStats[]
    cargo = CargoBatch[]
    for snapshot in history
        append!(events, snapshot.events)
        append!(stats, snapshot.stats)
        append!(cargo, snapshot.cargo)
    end

    return (
        history = history,
        events = events,
        stats = stats,
        cargo = cargo,
    )
end

function shipping_events_table(events::Vector{VesselEvent})
    sorted_events = sort(events; by = e -> (e.sim_time, e.event_type == "ARRIVAL" ? 0 : 1, e.port_order))
    return [
        Dict{String,Any}(
            "sim_time" => e.sim_time,
            "vessel" => e.vessel_name,
            "route" => e.route_id,
            "port" => e.port_code,
            "event_type" => e.event_type,
            "port_order" => e.port_order,
            "is_return" => e.is_return,
        )
        for e in sorted_events
    ]
end

function shipping_port_stats_table(stats::Vector{PortStats})
    sorted_stats = sort(stats; by = s -> (s.sim_time, s.port_code))
    return [
        Dict{String,Any}(
            "sim_time" => s.sim_time,
            "port" => s.port_code,
            "vessel_count" => s.vessel_count,
            "cargo_loaded_ffes" => s.cargo_loaded,
            "total_discharged_ffes" => s.cargo_discharged,
        )
        for s in sorted_stats
    ]
end

function shipping_cargo_table(cargo::Vector{CargoBatch})
    sorted_cargo = sort(cargo; by = c -> (c.sim_time, c.batch_id))
    return [
        Dict{String,Any}(
            "sim_time" => c.sim_time,
            "batch_id" => c.batch_id,
            "origin" => c.origin,
            "destination" => c.destination,
            "ffe" => c.ffe,
            "revenue" => c.revenue_per_unit,
            "week" => c.created_week,
            "route_id" => c.route_id,
            "transit_time" => c.transit_time,
            "vessel" => c.assigned_vessel,
        )
        for c in sorted_cargo
    ]
end

function shipping_revenue_summary(cargo::Vector{CargoBatch};
                                  delay_penalty_rate::Float64=50.0,
                                  promised_transit_days::Float64=30.0,
                                  fuel_consumed_tons::Float64=0.0,
                                  fuel_price::Float64=600.0,
                                  daily_charter_rate::Float64=15000.0,
                                  port_loading_cost::Float64=150.0,
                                  port_discharging_cost::Float64=150.0,
                                  port_call_cost::Float64=50000.0,
                                  port_call_count::Int=0,
                                  time_days::Union{Nothing,Float64}=nothing)
    delivered = [c for c in cargo if c.sim_time >= 0]
    total_revenue = sum((c.revenue_per_unit * c.ffe for c in delivered); init=0.0)
    total_ffe = sum((c.ffe for c in delivered); init=0.0)
    cargo_loaded = sum((c.ffe for c in cargo); init=0.0)
    cargo_discharged = total_ffe

    delay_penalty = 0.0
    for c in delivered
        created_time = c.created_week * 7.0
        actual_time = c.sim_time - created_time
        promised_time = c.transit_time > 0 ? c.transit_time : promised_transit_days
        delay_days = max(actual_time - promised_time, 0.0)
        delay_penalty += delay_days * c.ffe * delay_penalty_rate
    end

    voyage_days = isnothing(time_days) ? (isempty(delivered) ? 0.0 : maximum(c.sim_time for c in delivered)) : time_days
    fuel_cost = fuel_consumed_tons * fuel_price
    port_cost = cargo_loaded * port_loading_cost + cargo_discharged * port_discharging_cost + port_call_count * port_call_cost
    time_cost = voyage_days * daily_charter_rate
    total_cost = fuel_cost + port_cost + time_cost + delay_penalty
    net_profit = total_revenue - total_cost
    profit_per_ffe = cargo_loaded <= 0 ? 0.0 : net_profit / cargo_loaded

    return Dict{String,Any}(
        "delivered_batches" => length(delivered),
        "delivered_ffe" => total_ffe,
        "cargo_loaded_ffe" => cargo_loaded,
        "cargo_discharged_ffe" => cargo_discharged,
        "total_revenue" => total_revenue,
        "fuel_consumed_tons" => fuel_consumed_tons,
        "fuel_cost" => fuel_cost,
        "port_cost" => port_cost,
        "time_cost" => time_cost,
        "delay_penalty" => delay_penalty,
        "total_cost" => total_cost,
        "net_profit" => net_profit,
        "profit_per_ffe" => profit_per_ffe,
        "net_revenue_after_penalty" => total_revenue - delay_penalty,
    )
end

function shipping_scorecard(events::Vector{VesselEvent},
                            stats::Vector{PortStats},
                            cargo::Vector{CargoBatch};
                            delay_penalty_rate::Float64=50.0,
                            promised_transit_days::Float64=30.0,
                            fuel_consumed_tons::Float64=0.0,
                            fuel_price::Float64=600.0,
                            daily_charter_rate::Float64=15000.0,
                            port_loading_cost::Float64=150.0,
                            port_discharging_cost::Float64=150.0,
                            port_call_cost::Float64=50000.0)
    final_time = isempty(events) ? 0.0 : maximum(e.sim_time for e in events)
    port_call_count = count(e -> e.event_type == "ARRIVAL", events)
    revenue = shipping_revenue_summary(
        cargo;
        delay_penalty_rate=delay_penalty_rate,
        promised_transit_days=promised_transit_days,
        fuel_consumed_tons=fuel_consumed_tons,
        fuel_price=fuel_price,
        daily_charter_rate=daily_charter_rate,
        port_loading_cost=port_loading_cost,
        port_discharging_cost=port_discharging_cost,
        port_call_cost=port_call_cost,
        port_call_count=port_call_count,
        time_days=final_time,
    )
    arrival_count = count(e -> e.event_type == "ARRIVAL", events)
    departure_count = count(e -> e.event_type == "DEPARTURE", events)
    route_ids = sort!(collect(Set(e.route_id for e in events)))
    vessel_names = sort!(collect(Set(e.vessel_name for e in events)))
    port_codes = sort!(collect(Set(s.port_code for s in stats)))

    peak_vessel_count = isempty(stats) ? 0 : maximum(s.vessel_count for s in stats)
    total_loaded = sum((s.cargo_loaded for s in stats); init=0.0)
    total_discharged = sum((s.cargo_discharged for s in stats); init=0.0)
    avg_loaded = isempty(stats) ? 0.0 : total_loaded / length(stats)
    avg_discharged = isempty(stats) ? 0.0 : total_discharged / length(stats)
    event_density = final_time <= 0 ? 0.0 : length(events) / final_time

    score = 100.0
    score -= min(25.0, Float64(revenue["delay_penalty"]) / 1000.0)
    score -= min(20.0, max(0.0, 10.0 - arrival_count) * 1.5)
    score -= isempty(stats) ? 10.0 : 0.0
    score = clamp(score, 0.0, 100.0)

    readiness = score >= 85 ? "good" : score >= 60 ? "watch" : "risk"
    narrative = isempty(cargo) ?
        "Current scenario validates schedule semantics and event continuity, but cargo delivery evidence is still limited." :
        "Current scenario already produces cargo outcomes and can support a first operational review loop."

    return Dict{String,Any}(
        "score" => round(score; digits=1),
        "readiness" => readiness,
        "summary" => narrative,
        "meta" => Dict{String,Any}(
            "final_sim_time_days" => round(final_time; digits=1),
            "step_count" => 0,
            "route_count" => length(route_ids),
            "vessel_count" => length(vessel_names),
            "port_count" => length(port_codes),
            "routes" => route_ids,
            "vessels" => vessel_names,
            "ports" => port_codes,
        ),
        "operations" => Dict{String,Any}(
            "event_count" => length(events),
            "arrivals" => arrival_count,
            "departures" => departure_count,
            "event_density_per_day" => round(event_density; digits=3),
            "port_stat_records" => length(stats),
            "peak_vessels_in_port" => peak_vessel_count,
            "avg_loaded_ffe" => round(avg_loaded; digits=1),
            "avg_discharged_ffe" => round(avg_discharged; digits=1),
        ),
        "economics" => Dict{String,Any}(
            "delivered_batches" => revenue["delivered_batches"],
            "delivered_ffe" => round(Float64(revenue["delivered_ffe"]); digits=1),
            "cargo_loaded_ffe" => round(Float64(revenue["cargo_loaded_ffe"]); digits=1),
            "cargo_discharged_ffe" => round(Float64(revenue["cargo_discharged_ffe"]); digits=1),
            "revenue_usd" => round(Float64(revenue["total_revenue"]); digits=2),
            "fuel_consumed_tons" => round(Float64(revenue["fuel_consumed_tons"]); digits=2),
            "fuel_cost_usd" => round(Float64(revenue["fuel_cost"]); digits=2),
            "port_cost_usd" => round(Float64(revenue["port_cost"]); digits=2),
            "time_cost_usd" => round(Float64(revenue["time_cost"]); digits=2),
            "delay_penalty_usd" => round(Float64(revenue["delay_penalty"]); digits=2),
            "total_cost_usd" => round(Float64(revenue["total_cost"]); digits=2),
            "net_profit_usd" => round(Float64(revenue["net_profit"]); digits=2),
            "profit_per_ffe_usd" => round(Float64(revenue["profit_per_ffe"]); digits=2),
            "net_revenue_usd" => round(Float64(revenue["net_revenue_after_penalty"]); digits=2),
        ),
    )
end

function shipping_report_lines(events::Vector{VesselEvent},
                               stats::Vector{PortStats},
                               cargo::Vector{CargoBatch};
                               step_count::Int=0)
    final_time = isempty(events) ? 0.0 : maximum(e.sim_time for e in events)
    route_ids = sort!(collect(Set(e.route_id for e in events)))
    vessel_names = sort!(collect(Set(e.vessel_name for e in events)))
    revenue = shipping_revenue_summary(cargo)

    lines = String[]
    delivered_batches = revenue["delivered_batches"]
    delivered_ffe = revenue["delivered_ffe"]
    total_revenue = revenue["total_revenue"]
    delay_penalty = revenue["delay_penalty"]
    net_revenue = revenue["net_revenue_after_penalty"]
    route_text = isempty(route_ids) ? "-" : join(route_ids, ", ")
    vessel_text = isempty(vessel_names) ? "-" : join(vessel_names, ", ")
    push!(lines, "="^50)
    push!(lines, "Shipping Simulation Report")
    push!(lines, "="^50)
    push!(lines, "  Total Steps: $step_count")
    push!(lines, string("  Final Sim Time: ", round(final_time; digits=1), " days"))
    push!(lines, "  Event Count: $(length(events))")
    push!(lines, "  Port Stat Records: $(length(stats))")
    push!(lines, "  Delivered Cargo Batches: $delivered_batches")
    push!(lines, "  Delivered FFE: $(round(delivered_ffe; digits=0))")
    push!(lines, "  Revenue: $(round(total_revenue; digits=2)) USD")
    push!(lines, "  Fuel Cost: $(round(revenue["fuel_cost"]; digits=2)) USD")
    push!(lines, "  Port Cost: $(round(revenue["port_cost"]; digits=2)) USD")
    push!(lines, "  Time Cost: $(round(revenue["time_cost"]; digits=2)) USD")
    push!(lines, "  Delay Penalty: $(round(delay_penalty; digits=2)) USD")
    push!(lines, "  Total Cost: $(round(revenue["total_cost"]; digits=2)) USD")
    push!(lines, "  Net Profit: $(round(revenue["net_profit"]; digits=2)) USD")
    push!(lines, "  Net Revenue After Penalty: $(round(net_revenue; digits=2)) USD")
    push!(lines, "  Routes: $route_text")
    push!(lines, "  Vessels: $vessel_text")
    scorecard = shipping_scorecard(events, stats, cargo)
    push!(lines, "  Review Score: $(scorecard["score"])")
    push!(lines, "  Review Readiness: $(scorecard["readiness"])")
    push!(lines, "  Review Summary: $(scorecard["summary"])")
    return lines
end

function write_shipping_events_csv(events::Vector{VesselEvent}, filepath::String)
    dir = dirname(filepath)
    isempty(dir) || _ensure_dir(dir)
    open(filepath, "w") do io
        println(io, "sim_time,vessel,route,port,event_type,port_order,is_return")
        for row in shipping_events_table(events)
            println(io,
                string(
                    round(row["sim_time"]; digits=2), ",",
                    row["vessel"], ",",
                    row["route"], ",",
                    row["port"], ",",
                    row["event_type"], ",",
                    row["port_order"], ",",
                    row["is_return"] ? 1 : 0
                )
            )
        end
    end
    return filepath
end

function write_shipping_cargo_csv(cargo::Vector{CargoBatch}, filepath::String)
    dir = dirname(filepath)
    isempty(dir) || _ensure_dir(dir)
    open(filepath, "w") do io
        println(io, "sim_time,batch_id,origin,destination,ffe,revenue,week,route_id,transit_time,vessel")
        for row in shipping_cargo_table(cargo)
            println(io,
                string(
                    round(row["sim_time"]; digits=2), ",",
                    row["batch_id"], ",",
                    row["origin"], ",",
                    row["destination"], ",",
                    round(row["ffe"]; digits=0), ",",
                    round(row["revenue"]; digits=0), ",",
                    row["week"], ",",
                    row["route_id"], ",",
                    round(row["transit_time"]; digits=1), ",",
                    row["vessel"]
                )
            )
        end
    end
    return filepath
end

function write_shipping_port_stats_csv(stats::Vector{PortStats}, filepath::String)
    dir = dirname(filepath)
    isempty(dir) || _ensure_dir(dir)
    open(filepath, "w") do io
        println(io, "sim_time,port,vessel_count,cargo_loaded_ffes,total_discharged_ffes")
        for row in shipping_port_stats_table(stats)
            println(io,
                string(
                    round(row["sim_time"]; digits=2), ",",
                    row["port"], ",",
                    row["vessel_count"], ",",
                    round(row["cargo_loaded_ffes"]; digits=0), ",",
                    round(row["total_discharged_ffes"]; digits=0)
                )
            )
        end
    end
    return filepath
end

function write_shipping_report(events::Vector{VesselEvent},
                               stats::Vector{PortStats},
                               cargo::Vector{CargoBatch},
                               filepath::String;
                               step_count::Int=0)
    dir = dirname(filepath)
    isempty(dir) || _ensure_dir(dir)
    lines = shipping_report_lines(events, stats, cargo; step_count=step_count)
    open(filepath, "w") do io
        println(io, join(lines, "\n"))
    end
    return filepath
end

function write_shipping_scorecard(events::Vector{VesselEvent},
                                  stats::Vector{PortStats},
                                  cargo::Vector{CargoBatch},
                                  filepath::String;
                                  step_count::Int=0)
    dir = dirname(filepath)
    isempty(dir) || _ensure_dir(dir)
    scorecard = shipping_scorecard(events, stats, cargo)
    scorecard["meta"]["step_count"] = step_count
    open(filepath, "w") do io
        JSON3.write(io, scorecard)
    end
    return filepath
end

function export_shipping_results(output_dir::String,
                                 result;
                                 basename::String="shipping")
    _ensure_dir(output_dir)
    events_path = joinpath(output_dir, string(basename, "_events.csv"))
    stats_path = joinpath(output_dir, string(basename, "_stats.csv"))
    cargo_path = joinpath(output_dir, string(basename, "_cargo_discharged.csv"))
    report_path = joinpath(output_dir, string(basename, "_report.txt"))
    scorecard_path = joinpath(output_dir, string(basename, "_scorecard.json"))

    write_shipping_events_csv(result.events, events_path)
    write_shipping_port_stats_csv(result.stats, stats_path)
    write_shipping_cargo_csv(result.cargo, cargo_path)
    write_shipping_report(result.events, result.stats, result.cargo, report_path; step_count=length(result.history))
    write_shipping_scorecard(result.events, result.stats, result.cargo, scorecard_path; step_count=length(result.history))

    return Dict{String,String}(
        "events_csv" => events_path,
        "stats_csv" => stats_path,
        "cargo_csv" => cargo_path,
        "report_txt" => report_path,
        "scorecard_json" => scorecard_path,
    )
end
