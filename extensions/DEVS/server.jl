# ============================================================
# server.jl — DEVS WebSocket 仿真服务端
#
# 提供基于 DEVS 运行时的 WebSocket 接口与 anysim-web 前端通信。
# 支持的协议:
#   - 命令 (前端→后端): start, pause, resume, reset, set_speed,
#                         step, simulate, get_status, get_entities,
#                         get_presets, get_outputs, load_preset
#   - 消息 (后端→前端): sim_state, sim_state_delta, ack, status,
#                         entities, presets, outputs, error
#
# 使用:
#   include("src/AnySim.jl")
#   include("extensions/DEVS/DEVS.jl")
#   include("extensions/DEVS/server.jl")
#   run_server(host="127.0.0.1", port=8080)
# ============================================================

using HTTP
using JSON3
import ..AnySim: EntityDef, Relation, Connection, ComposeDef, Port, Parameter, exception_payload
import ..AnySim: EngineCommand, AbstractSimTransport, deserialize_command
import Main: all_presets, find_plugin_for_preset, build_model

# ============================================================
# 1. 仿真运行器状态
# ============================================================

mutable struct SimRunner
    # 仿真状态
    running::Bool
    paused::Bool
    speed::Float64
    current_time::Float64
    step_count::Int
    max_steps::Int
    max_time::Float64

    # 模型上下文
    model_loaded::Bool
    model_name::String
    preset_id::String
    project_path::String
    model::Union{Nothing, ComposeDef}
    ctx::Union{Nothing, DEVSContext}
    entities::Vector{EntityDef}

    # 活跃的 WebSocket 客户端
    clients::Set{HTTP.WebSockets.WebSocket}

    # 配置
    steps_per_tick::Int
    loop_task::Union{Nothing, Task}

    # 输出端口缓存
    output_ports::Dict{String,Any}
    shipping_events::Vector{Any}
    shipping_stats::Vector{Any}
    shipping_cargo::Vector{Any}

    # 新架构：实验结果缓存
    world::Any                              # ShippingWorld (Any 避免硬依赖)
    execution_plan::Any                     # ExecutionPlan
    experiment_result::Any                  # ExperimentResult
    experiment_results::Vector{Any}         # 多模型对比结果
    robustness_result::Any                  # RobustnessAnalysis
end

function SimRunner()
    return SimRunner(
        false, false, 1.0, 0.0, 0, 10000, 1e6,
        false, "", "", "", nothing, nothing, EntityDef[],
        Set{HTTP.WebSockets.WebSocket}(),
        1,
        nothing,
        Dict{String,Any}(),
        Any[],
        Any[],
        Any[],
        nothing, nothing, nothing, Any[], nothing,
    )
end

# ============================================================
# 2. 命令分发
# ============================================================

struct ServerTransport <: AbstractSimTransport end

function handle_command(runner::SimRunner, ws::HTTP.WebSocket, command::EngineCommand)
    cmd_type = String(command.type)
    payload = command.params

    try
        if cmd_type == "start"
            cmd_start(runner, payload)
        elseif cmd_type == "pause"
            cmd_pause(runner)
        elseif cmd_type == "resume"
            cmd_resume(runner)
        elseif cmd_type == "reset"
            cmd_reset(runner)
        elseif cmd_type == "set_speed"
            cmd_set_speed(runner, payload)
        elseif cmd_type == "step"
            cmd_step(runner)
        elseif cmd_type == "simulate"
            cmd_simulate(runner, payload)
        elseif cmd_type == "get_status"
            cmd_get_status(ws, runner)
        elseif cmd_type == "get_entities"
            cmd_get_entities(ws, runner)
        elseif cmd_type == "get_presets"
            cmd_get_presets(ws)
        elseif cmd_type == "get_outputs"
            cmd_get_outputs(ws, runner)
        elseif cmd_type == "load_preset"
            cmd_load_preset(runner, payload)
        elseif cmd_type == "set_config"
            cmd_set_config(runner, payload)
        # 新架构命令
        elseif cmd_type == "run_experiment"
            cmd_run_experiment(runner, payload)
        elseif cmd_type == "run_comparison"
            cmd_run_comparison(runner, payload)
        elseif cmd_type == "run_robustness"
            cmd_run_robustness(runner, payload)
        elseif cmd_type == "get_experiment_result"
            cmd_get_experiment_result(ws, runner)
        else
            send_ack(ws, cmd_type, false, "未知命令: $cmd_type")
        end
    catch e
        @warn "[Server] 命令处理失败: $cmd_type — $e"
        send_error(ws, runner, e; cmd=cmd_type, phase="simulation_runtime")
        send_ack(ws, cmd_type, false, string(e))
    end
end

function _is_shipping_runner(runner::SimRunner)
    return runner.preset_id in ("shipping-demo", "shipping-single-vessel") || occursin("Shipping", runner.model_name)
end

function _clear_output_ports!(runner::SimRunner)
    empty!(runner.output_ports)
    empty!(runner.shipping_events)
    empty!(runner.shipping_stats)
    empty!(runner.shipping_cargo)
    return runner
end

function _refresh_output_ports!(runner::SimRunner)
    if _is_shipping_runner(runner) && isdefined(Main, :Shipping)
        events = Main.Shipping.VesselEvent[v for v in runner.shipping_events if v isa Main.Shipping.VesselEvent]
        stats = Main.Shipping.PortStats[v for v in runner.shipping_stats if v isa Main.Shipping.PortStats]
        cargo = Main.Shipping.CargoBatch[v for v in runner.shipping_cargo if v isa Main.Shipping.CargoBatch]
        scorecard = Main.Shipping.shipping_scorecard(events, stats, cargo)
        if haskey(scorecard, "meta") && scorecard["meta"] isa AbstractDict
            scorecard["meta"]["step_count"] = runner.step_count
        end
        runner.output_ports["shipping-scorecard"] = Dict{String,Any}(
            "id" => "shipping-scorecard",
            "label" => "评分输出端口",
            "kind" => "scorecard",
            "updated_at" => runner.current_time,
            "data" => scorecard,
        )
    end
    return runner
end

function _capture_domain_outputs!(runner::SimRunner, outputs::Dict{Symbol, Vector{DEVSMessage}})
    isempty(outputs) && return runner
    if _is_shipping_runner(runner) && isdefined(Main, :Shipping)
        for messages in values(outputs)
            for msg in messages
                value = msg.value
                if value isa Main.Shipping.VesselEvent
                    push!(runner.shipping_events, deepcopy(value))
                elseif value isa Main.Shipping.PortStats
                    push!(runner.shipping_stats, deepcopy(value))
                elseif value isa Main.Shipping.CargoBatch
                    push!(runner.shipping_cargo, deepcopy(value))
                end
            end
        end
        _refresh_output_ports!(runner)
    end
    return runner
end

# ============================================================
# 3. 命令实现
# ============================================================

function cmd_start(runner::SimRunner, payload::Dict{String,Any})
    runner.running = true
    runner.paused = false
    runner.max_steps = get(payload, "max_steps", 10000)
    runner.max_time = get(payload, "max_time", 1e6)

    # 如果没有模型，使用默认的 DEVS 测试模型
    if !runner.model_loaded
        _load_default_model(runner)
    end

    # 初始化 DEVS 上下文
    if runner.ctx === nothing && runner.model !== nothing
        runner.ctx = init_devs_context(runner.model)
    end

    # 广播给所有客户端
    broadcast_to_all(runner, Dict{String,Any}(
        "type" => "ack",
        "cmd" => "start",
        "success" => true,
    ))

    # 启动仿真协程
    _ensure_sim_loop!(runner)
end

function cmd_pause(runner::SimRunner)
    runner.paused = true
    runner.running = true
    send_ack_to_all(runner, "pause", true)
end

function cmd_resume(runner::SimRunner)
    runner.paused = false
    runner.running = true
    send_ack_to_all(runner, "resume", true)
end

function cmd_reset(runner::SimRunner)
    runner.running = false
    runner.paused = false
    runner.current_time = 0.0
    runner.step_count = 0
    _clear_output_ports!(runner)

    # 重置上下文
    if runner.model !== nothing
        runner.ctx = init_devs_context(runner.model)
    end
    _refresh_output_ports!(runner)

    send_ack_to_all(runner, "reset", true)
end

function cmd_set_speed(runner::SimRunner, payload::Dict{String,Any})
    runner.speed = Float64(get(payload, "speed", 1.0))
    send_ack_to_all(runner, "set_speed", true, Dict{String,Any}("speed" => runner.speed))
end

function cmd_step(runner::SimRunner)
    if runner.ctx === nothing
        send_ack_to_all(runner, "step", false, "模型未加载")
        return
    end

    result = devs_step!(runner.ctx; max_time=runner.max_time, capture_outputs=true)
    if result isa Bool
        running = result
        outputs = Dict{Symbol, Vector{DEVSMessage}}()
    else
        running = result.running
        outputs = result.outputs
    end
    if running
        runner.step_count += 1
        runner.current_time = runner.ctx.current_time
        _capture_domain_outputs!(runner, outputs)
        broadcast_sim_state(runner)
    end
    send_ack_to_all(runner, "step", true)
end

function cmd_simulate(runner::SimRunner, payload::Dict{String,Any})
    # 连续运行（非循环调度）
    runner.running = true
    runner.paused = false
    runner.max_steps = get(payload, "max_steps", 10000)
    runner.max_time = get(payload, "max_time", 1e6)

    _ensure_sim_loop!(runner)
end

function cmd_get_status(ws::HTTP.WebSocket, runner::SimRunner)
    send_json(ws, Dict{String,Any}(
        "type" => "status",
        "data" => Dict{String,Any}(
            "running" => runner.running,
            "paused" => runner.paused,
            "speed" => runner.speed,
            "current_time" => runner.current_time,
            "step_count" => runner.step_count,
            "max_steps" => runner.max_steps,
            "max_time" => runner.max_time,
            "entity_count" => length(runner.entities),
            "model_loaded" => runner.model_loaded,
            "preset_id" => runner.preset_id,
            "project_path" => runner.project_path,
        ),
    ))
end

function cmd_get_entities(ws::HTTP.WebSocket, runner::SimRunner)
    entities_info = [Dict{String,Any}(
        "name" => string(e.name),
        "port_count" => length(e.ports),
        "relation_count" => length(e.relations),
        "parameter_count" => length(e.parameters),
        "parameters" => [Dict{String,Any}(
            "name" => string(p.name),
            "type" => string(p.ptype),
            "has_default" => p.default !== nothing,
        ) for p in e.parameters],
    ) for e in runner.entities]

    send_json(ws, Dict{String,Any}(
        "type" => "entities",
        "data" => Dict{String,Any}(
            "model_name" => runner.model_name,
            "entity_count" => length(runner.entities),
            "preset_id" => runner.preset_id,
            "project_path" => runner.project_path,
            "entities" => entities_info,
        ),
    ))
end

function cmd_get_presets(ws::HTTP.WebSocket)
    presets = all_presets()
    send_json(ws, Dict{String,Any}(
        "type" => "presets",
        "data" => Dict{String,Any}(
            "items" => presets,
        ),
    ))
end

function cmd_get_outputs(ws::HTTP.WebSocket, runner::SimRunner)
    _refresh_output_ports!(runner)
    items = sort!(collect(values(runner.output_ports)); by = item -> get(item, "id", ""))
    send_json(ws, Dict{String,Any}(
        "type" => "outputs",
        "data" => Dict{String,Any}(
            "items" => items,
        ),
    ))
end

function cmd_load_preset(runner::SimRunner, payload::Dict{String,Any})
    preset_id = get(payload, "preset_id", "")
    if isempty(preset_id)
        error("preset_id is required")
    end

    raw_config = get(payload, "config", Dict{String,Any}())
    config = raw_config isa Dict{String,Any} ? raw_config : Dict{String,Any}(raw_config)

    _load_preset_model(runner, preset_id; config=config)
    runner.ctx = nothing
    runner.current_time = 0.0
    runner.step_count = 0
    runner.running = false
    runner.paused = false
    _clear_output_ports!(runner)
    _refresh_output_ports!(runner)

    send_ack_to_all(runner, "load_preset", true; extra=Dict{String,Any}(
        "preset_id" => preset_id,
        "model_name" => runner.model_name,
    ))
end

function cmd_set_config(runner::SimRunner, payload::Dict{String,Any})
    params = get(payload, "params", Dict{String,Any}())
    # 更新 entity 参数
    for (ent_name_str, ent_params) in params
        ent_sym = Symbol(ent_name_str)
        if runner.ctx !== nothing && ent_sym in devs_entity_names(runner.ctx)
            state = devs_entity_state(runner.ctx, ent_sym)
            for (k, v) in ent_params
                state[Symbol(k)] = v
            end
        end
    end
    send_ack_to_all(runner, "set_config", true)
end

# ============================================================
# 3b. 新架构命令实现
# ============================================================

"""确保 Shipping 模块已加载"""
function _ensure_shipping!()
    if !isdefined(Main, :Shipping)
        error("Shipping extension not loaded. Please include Shipping.jl first.")
    end
end

"""从 payload 构建 ShippingWorld"""
function _build_world_from_payload(payload::Dict{String,Any})
    _ensure_shipping!()
    data_dir = joinpath(@__DIR__, "..", "..", "data", "shipping")
    schedule_file = get(payload, "schedule_file", joinpath(data_dir, "航线船期_20260507_ych.csv"))
    od_file = get(payload, "od_file", joinpath(data_dir, "od对需求_20260507_ych.csv"))

    return Main.Shipping.build_shipping_world(schedule_file, od_file;
        scenario_id=string(get(payload, "scenario_id", "baseline")),
        description=string(get(payload, "description", "")),
        demand_multiplier=Float64(get(payload, "demand_multiplier", 1.0)),
        capacity_multiplier=Float64(get(payload, "capacity_multiplier", 1.0)),
        disruption_level=Float64(get(payload, "disruption_level", 0.0)),
        cycle_days=Int(get(payload, "cycle_days", 7)),
        horizon_cycles=Int(get(payload, "horizon_cycles", 8)),
    )
end

"""从 payload 选择决策模型"""
function _select_model_from_payload(payload::Dict{String,Any})
    _ensure_shipping!()
    model_name = string(get(payload, "decision_model", "SimpleDirectAllocation"))
    registry = Main.Shipping.default_registry()
    return Main.Shipping.get_model(registry, model_name)
end

"""
    cmd_run_experiment — 运行完整实验：决策 → 仿真 → 分析

Payload: {
    decision_model: "SimpleDirectAllocation" | "TimeSpaceMILP" | "GreedyHeuristic",
    scenario_id: "baseline",
    disruption_level: 0.0,
    max_time: 200.0,
    max_steps: 10000,
    ...world config...
}
"""
function cmd_run_experiment(runner::SimRunner, payload::Dict{String,Any})
    try
        world = _build_world_from_payload(payload)
        model = _select_model_from_payload(payload)
        scenario_id = string(get(payload, "scenario_id", "baseline"))
        max_time = Float64(get(payload, "max_time", 200.0))
        max_steps = Int(get(payload, "max_steps", 10000))

        # 运行实验
        result = Main.Shipping.run_experiment(world, model;
            scenario_id=scenario_id,
            max_time=max_time,
            max_steps=max_steps,
        )

        # 缓存结果
        runner.world = world
        runner.execution_plan = result.plan
        runner.experiment_result = result

        # 更新输出端口
        _refresh_experiment_output_ports!(runner)

        send_ack_to_all(runner, "run_experiment", true; extra=Dict{String,Any}(
            "experiment_id" => result.experiment_id,
            "model_name" => result.model_name,
            "scenario_id" => result.scenario_id,
            "kpi" => Main.Shipping.kpi_summary_dict(result.kpi),
        ))
    catch e
        @warn "[Server] run_experiment 失败: $e"
        send_ack_to_all(runner, "run_experiment", false, Dict{String,Any}("msg" => string(e)))
    end
end

"""
    cmd_run_comparison — 多模型对比

Payload: {
    models: ["SimpleDirectAllocation", "GreedyHeuristic"],
    ...world config...
}
"""
function cmd_run_comparison(runner::SimRunner, payload::Dict{String,Any})
    try
        world = _build_world_from_payload(payload)
        model_names = get(payload, "models", ["SimpleDirectAllocation", "GreedyHeuristic"])
        scenario_id = string(get(payload, "scenario_id", "baseline"))
        max_time = Float64(get(payload, "max_time", 200.0))
        max_steps = Int(get(payload, "max_steps", 10000))

        registry = Main.Shipping.default_registry()
        models = [Main.Shipping.get_model(registry, string(m)) for m in model_names]

        # 运行对比
        results = Main.Shipping.run_comparison(world, models;
            scenario_id=scenario_id,
            max_time=max_time,
            max_steps=max_steps,
        )

        # 缓存结果
        runner.world = world
        runner.experiment_results = Any[r for r in results]
        if !isempty(results)
            runner.experiment_result = results[1]
            runner.execution_plan = results[1].plan
        end

        # 更新输出端口
        _refresh_experiment_output_ports!(runner)

        # 构建对比摘要
        comparison_data = [Main.Shipping.experiment_summary(r) for r in results]

        send_ack_to_all(runner, "run_comparison", true; extra=Dict{String,Any}(
            "model_count" => length(results),
            "comparisons" => comparison_data,
        ))
    catch e
        @warn "[Server] run_comparison 失败: $e"
        send_ack_to_all(runner, "run_comparison", false, Dict{String,Any}("msg" => string(e)))
    end
end

"""
    cmd_run_robustness — 鲁棒性分析

Payload: {
    decision_model: "SimpleDirectAllocation",
    disruption_levels: [0.0, 0.5, 1.0, 2.0],
    ...world config...
}
"""
function cmd_run_robustness(runner::SimRunner, payload::Dict{String,Any})
    try
        world = _build_world_from_payload(payload)
        model = _select_model_from_payload(payload)
        scenario_id = string(get(payload, "scenario_id", "baseline"))
        max_time = Float64(get(payload, "max_time", 200.0))
        max_steps = Int(get(payload, "max_steps", 10000))

        # 解析扰动水平
        raw_levels = get(payload, "disruption_levels", [0.0, 0.5, 1.0, 2.0])
        disruption_levels = [Float64(l) for l in raw_levels]

        # 运行鲁棒性分析
        robustness = Main.Shipping.run_robustness_study(world, model;
            disruption_levels=disruption_levels,
            scenario_id=scenario_id,
            max_time=max_time,
            max_steps=max_steps,
        )

        # 缓存结果
        runner.world = world
        runner.robustness_result = robustness

        # 更新输出端口
        _refresh_experiment_output_ports!(runner)

        send_ack_to_all(runner, "run_robustness", true; extra=Dict{String,Any}(
            "model_name" => robustness.model_name,
            "robustness_score" => robustness.robustness_score,
            "profit_retention" => robustness.profit_retention,
        ))
    catch e
        @warn "[Server] run_robustness 失败: $e"
        send_ack_to_all(runner, "run_robustness", false, Dict{String,Any}("msg" => string(e)))
    end
end

"""
    cmd_get_experiment_result — 获取缓存的实验结果
"""
function cmd_get_experiment_result(ws::HTTP.WebSocket, runner::SimRunner)
    result = runner.experiment_result
    if result === nothing
        send_json(ws, Dict{String,Any}(
            "type" => "experiment_result",
            "data" => Dict{String,Any}("error" => "No experiment result available"),
        ))
        return
    end

    _ensure_shipping!()
    summary = Main.Shipping.experiment_summary(result)

    # 添加时间序列数据
    ts_data = Dict{String, Any}()
    if hasfield(typeof(result), :time_series)
        for (name, ts) in result.time_series
            ts_data[name] = Dict{String, Any}(
                "metric_name" => ts.metric_name,
                "unit" => ts.unit,
                "points" => [[p.time, p.value, p.label] for p in ts.points],
            )
        end
    end
    summary["time_series"] = ts_data

    # 添加鲁棒性结果（如果有）
    if runner.robustness_result !== nothing
        summary["robustness"] = Main.Shipping.robustness_summary(runner.robustness_result)
    end

    # 添加多模型对比结果（如果有）
    if !isempty(runner.experiment_results)
        summary["comparison"] = [Main.Shipping.experiment_summary(r) for r in runner.experiment_results]
    end

    send_json(ws, Dict{String,Any}(
        "type" => "experiment_result",
        "data" => summary,
    ))
end

"""刷新实验结果输出端口"""
function _refresh_experiment_output_ports!(runner::SimRunner)
    if runner.experiment_result !== nothing && isdefined(Main, :Shipping)
        result = runner.experiment_result
        summary = Main.Shipping.experiment_summary(result)
        runner.output_ports["experiment-result"] = Dict{String,Any}(
            "id" => "experiment-result",
            "label" => "实验结果",
            "kind" => "experiment",
            "updated_at" => runner.current_time,
            "data" => summary,
        )
    end

    if !isempty(runner.experiment_results) && isdefined(Main, :Shipping)
        comparison_data = [Main.Shipping.experiment_summary(r) for r in runner.experiment_results]
        runner.output_ports["model-comparison"] = Dict{String,Any}(
            "id" => "model-comparison",
            "label" => "模型对比",
            "kind" => "comparison",
            "updated_at" => runner.current_time,
            "data" => Dict{String,Any}(
                "models" => comparison_data,
            ),
        )
    end

    if runner.robustness_result !== nothing && isdefined(Main, :Shipping)
        runner.output_ports["robustness-analysis"] = Dict{String,Any}(
            "id" => "robustness-analysis",
            "label" => "鲁棒性分析",
            "kind" => "robustness",
            "updated_at" => runner.current_time,
            "data" => Main.Shipping.robustness_summary(runner.robustness_result),
        )
    end
end

# ============================================================
# 4. 仿真循环
# ============================================================

function sim_loop(runner::SimRunner)
    try
        while runner.running && !runner.paused
            if runner.ctx === nothing
                sleep(0.1)
                continue
            end

            # 执行 N 步
            for _ in 1:runner.steps_per_tick
                if !runner.running || runner.paused
                    break
                end

                if runner.step_count >= runner.max_steps
                    runner.running = false
                    break
                end
                if runner.current_time >= runner.max_time
                    runner.running = false
                    break
                end

                result = devs_step!(runner.ctx; max_time=runner.max_time, capture_outputs=true)
                if result isa Bool
                    running = result
                    outputs = Dict{Symbol, Vector{DEVSMessage}}()
                else
                    running = result.running
                    outputs = result.outputs
                end
                if !running
                    runner.running = false
                    break
                end

                runner.step_count += 1
                runner.current_time = runner.ctx.current_time
                _capture_domain_outputs!(runner, outputs)
            end

            # 广播状态
            broadcast_sim_state(runner)

            # 速度控制：1x ≈ 每步 50ms
            sleep(max(0.001, 0.05 / max(runner.speed, 1e-6)))
        end
    catch e
        runner.running = false
        runner.paused = false
        @warn "[Server] 仿真循环失败: $e"
        broadcast_error_to_all(runner, e; cmd="simulate", phase="simulation_runtime")
    finally
        runner.loop_task = nothing
        # 发送最终状态
        if runner.ctx !== nothing
            broadcast_sim_state(runner)
        end
    end
end

function _ensure_sim_loop!(runner::SimRunner)
    if runner.loop_task !== nothing && !istaskdone(runner.loop_task)
        return runner.loop_task
    end
    runner.loop_task = @async sim_loop(runner)
    return runner.loop_task
end

# ============================================================
# 5. 消息广播
# ============================================================

function broadcast_sim_state(runner::SimRunner)
    if runner.ctx === nothing || isempty(runner.clients)
        return
    end

    state_dict = _build_state_msg(runner)
    json_str = JSON3.write(state_dict)

    closed = Set{HTTP.WebSockets.WebSocket}()
    for ws in runner.clients
        try
            HTTP.WebSockets.send(ws, json_str)
        catch
            push!(closed, ws)
        end
    end

    # 清理断开的连接
    for ws in closed
        delete!(runner.clients, ws)
    end
end

function _json_safe_number(v::Number)
    value = float(v)
    return isfinite(value) ? value : nothing
end

function _json_sanitize(value)
    if value isa Number
        return _json_safe_number(value)
    elseif value isa AbstractDict
        return Dict{String,Any}(string(k) => _json_sanitize(v) for (k, v) in pairs(value))
    elseif value isa AbstractVector
        return Any[_json_sanitize(v) for v in value]
    elseif value isa Tuple
        return Any[_json_sanitize(v) for v in value]
    else
        return value
    end
end

function _build_state_msg(runner::SimRunner)::Dict{String,Any}
    entities = Dict{String, Dict{String, Any}}()
    for e in runner.entities
        ent_name = string(e.name)
        ent_state = Dict{String, Any}()
        if runner.ctx !== nothing && e.name in devs_entity_names(runner.ctx)
            for (k, v) in devs_entity_state(runner.ctx, e.name)
                if v isa Number
                    ent_state[string(k)] = _json_safe_number(v)
                elseif v isa Symbol
                    ent_state[string(k)] = string(v)
                elseif v isa Bool
                    ent_state[string(k)] = v
                elseif v isa String
                    ent_state[string(k)] = v
                end
            end
        end
        if !isempty(ent_state)
            entities[ent_name] = ent_state
        end
    end

    return Dict{String, Any}(
        "type" => "sim_state",
        "time" => runner.current_time,
        "entities" => entities,
        "entity_count" => length(entities),
        "step" => runner.step_count,
    )
end

function broadcast_to_all(runner::SimRunner, msg::Dict{String,Any})
    json_str = JSON3.write(_json_sanitize(msg))
    closed = Set{HTTP.WebSockets.WebSocket}()
    for ws in runner.clients
        try
            HTTP.WebSockets.send(ws, json_str)
        catch
            push!(closed, ws)
        end
    end
    for ws in closed
        delete!(runner.clients, ws)
    end
end

function _error_metadata(runner::SimRunner, cmd::String)
    return Dict{String, Any}(
        "cmd" => cmd,
        "model_name" => runner.model_name,
    )
end

function send_error(ws::HTTP.WebSocket, runner::SimRunner, err::Exception; cmd::String="unknown", phase::String="simulation_runtime")
    payload = exception_payload(
        err;
        time=runner.current_time,
        step=runner.step_count,
        extra_metadata=_error_metadata(runner, cmd),
        phase=phase,
        human_message="命令执行失败",
        entity=Dict("kind" => "server_command", "cmd" => cmd),
    )
    send_json(ws, payload)
end

function broadcast_error_to_all(runner::SimRunner, err::Exception; cmd::String="simulate", phase::String="simulation_runtime")
    payload = exception_payload(
        err;
        time=runner.current_time,
        step=runner.step_count,
        extra_metadata=_error_metadata(runner, cmd),
        phase=phase,
        human_message="仿真执行失败",
        entity=Dict("kind" => "server_runtime", "cmd" => cmd),
    )
    broadcast_to_all(runner, payload)
end

function send_ack_to_all(runner::SimRunner, cmd::String, success::Bool; extra=Dict{String,Any}())
    msg = merge(Dict{String,Any}(
        "type" => "ack",
        "cmd" => cmd,
        "success" => success,
    ), extra)
    broadcast_to_all(runner, msg)
end

function send_ack(ws::HTTP.WebSocket, cmd::String, success::Bool, msg::String="")
    send_json(ws, Dict{String,Any}(
        "type" => "ack",
        "cmd" => cmd,
        "success" => success,
        "msg" => msg,
    ))
end

function send_json(ws::HTTP.WebSocket, data::Dict{String,Any})
    try
        HTTP.WebSockets.send(ws, JSON3.write(_json_sanitize(data)))
    catch e
        @warn "[Server] 发送失败: $e"
    end
end

# ============================================================
# 6. 默认测试模型
# ============================================================

function _load_default_model(runner::SimRunner)
    # 不再提供默认测试模型，必须通过 load_preset 或 run_experiment 加载
    runner.model_loaded = false
    runner.model_name = ""
    runner.preset_id = ""
    @warn "[Server] No default model. Use load_preset or run_experiment to load a model."
end

function _load_preset_model(runner::SimRunner, preset_id::String; config::Dict{String,Any}=Dict{String,Any}())
    plugin = find_plugin_for_preset(preset_id)
    built = build_model(plugin, preset_id; config=config)

    runner.model_name = built.model_name
    runner.preset_id = preset_id
    runner.model_loaded = true
    runner.model = built.model
    runner.entities = built.entities
    _clear_output_ports!(runner)
    _refresh_output_ports!(runner)
end

function _load_project_model(runner::SimRunner, project_path::String)
    manifest = Main.load_project_manifest(project_path)
    resolved = Main.resolve_project_entry(manifest)
    config = resolved.config

    project_data = get(manifest, "data", Dict{String,Any}())
    if project_data isa AbstractDict && !isempty(project_data)
        resolved_data = Dict{String,Any}()
        for (k, v) in pairs(project_data)
            resolved_data[string(k)] = normpath(joinpath(manifest["project_dir"], String(v)))
        end
        config = Dict{String,Any}(config)
        config["data"] = resolved_data
    end

    # 注入项目目录，供扩展解析项目相对路径
    config = Dict{String,Any}(config)
    config["project_dir"] = manifest["project_dir"]

    # 注册项目到扩展，使 extension_presets 能动态发现
    project_id = get(manifest, "project_id", "")
    if !isempty(project_id) && isdefined(Main, :Shipping) && isdefined(Main.Shipping, :register_project!)
        Main.Shipping.register_project!(project_id, manifest["project_dir"])
    end

    # 加载项目模型文件（world, optimization, decision, simulation_bridge, analysis）
    # 这些业务逻辑文件从项目 model/ 目录动态注入 Shipping 扩展
    if isdefined(Main, :Shipping) && isdefined(Main.Shipping, :load_project_models)
        Main.Shipping.load_project_models(manifest["project_dir"])
    end

    _load_preset_model(runner, resolved.preset_id; config=config)
    runner.project_path = manifest["project_dir"]
end

function _load_named_model(runner::SimRunner, model_key::String)
    # 所有模型都通过 preset 系统加载，不再硬编码
    _load_default_model(runner)
end

# ============================================================
# 7. 服务器入口
# ============================================================

"""
    run_server(; host="127.0.0.1", port=8080, model="default")

启动 DEVS WebSocket 仿真服务端。
前端可以通过 `ws://host:port/ws/sim` 连接。
"""
function run_server(; host="127.0.0.1", port=8080, model="default", project="")
    runner = SimRunner()
    runner.running = false
    runner.paused = false
    runner.current_time = 0.0
    runner.step_count = 0
    runner.ctx = nothing
    runner.model = nothing
    runner.entities = EntityDef[]
    runner.model_loaded = false
    runner.model_name = ""
    runner.preset_id = ""
    runner.project_path = ""

    if isempty(project)
        _load_named_model(runner, model)
    else
        _load_project_model(runner, project)
    end

    @info "[Server] AnySim WebSocket 服务启动中: ws://$host:$port/ws/sim (model=$model, project=$(isempty(project) ? "-" : project), loaded=$(runner.model_name))"

    # HTTP.jl 1.11 WebSocket API：使用 HTTP.WebSockets.listen
    HTTP.WebSockets.listen(host, port) do ws
        push!(runner.clients, ws)
        @info "[Server] 新客户端连接 ($(length(runner.clients)) 个活跃)"

        try
            while !HTTP.WebSockets.isclosed(ws)
                msg = HTTP.WebSockets.receive(ws)
                if msg !== nothing && (msg isa String || msg isa Vector{UInt8})
                    data = String(msg)
                    try
                        raw_cmd = JSON3.read(data, Dict{String,Any})
                        cmd = deserialize_command(ServerTransport(), raw_cmd)
                        handle_command(runner, ws, cmd)
                    catch e
                        @warn "[Server] JSON 解析失败: $data — $e"
                        send_error(ws, runner, e; cmd="unknown", phase="parse")
                        send_ack(ws, "unknown", false, "JSON 解析失败")
                    end
                end
            end
        catch e
            if !(e isa EOFError) && !(e isa HTTP.WebSockets.WebSocketError)
                @warn "[Server] WebSocket 错误: $e"
            end
        finally
            delete!(runner.clients, ws)
            @info "[Server] 客户端断开 ($(length(runner.clients)) 个活跃)"
        end
    end
end

println("[Server] AnySim WebSocket Server loaded. Call run_server() to start.")
