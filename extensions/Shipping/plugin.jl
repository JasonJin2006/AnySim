import Main: AbstractExtensionPlugin, extension_id, extension_label, extension_presets, build_model
import Main: load_project_manifest

struct ShippingPlugin <: AbstractExtensionPlugin end

extension_id(::ShippingPlugin) = "shipping"
extension_label(::ShippingPlugin) = "Liner Shipping"

# ============================================================
# Preset 发现：从项目配置动态生成
# 不再硬编码 preset 列表，而是扫描已注册的项目目录
# ============================================================

const _REGISTERED_PROJECTS = Dict{String, String}()  # project_id => project_dir

function register_project!(project_id::String, project_dir::String)
    _REGISTERED_PROJECTS[project_id] = project_dir
end

function extension_presets(::ShippingPlugin)
    presets = Dict{String,Any}[]
    for (project_id, project_dir) in _REGISTERED_PROJECTS
        try
            manifest = load_project_manifest(project_dir)
            scenarios = get(manifest, "scenarios", Any[])
            for scenario in scenarios
                scenario_dict = Dict{String,Any}(string(k) => v for (k, v) in pairs(scenario))
                scenario_id = get(scenario_dict, "id", "")
                scenario_label = get(scenario_dict, "label", scenario_id)
                preset_id = "$(project_id)::$(scenario_id)"
                push!(presets, Dict{String,Any}(
                    "id" => preset_id,
                    "label" => scenario_label,
                    "extension_id" => "shipping",
                    "model_key" => project_id,
                    "description" => get(scenario_dict, "description", "Scenario: $(scenario_label)"),
                    "project_dir" => project_dir,
                    "scenario_id" => scenario_id,
                ))
            end
        catch e
            @warn "[Shipping] Failed to load project manifest for $(project_id): $e"
        end
    end
    return presets
end

function build_model(::ShippingPlugin, preset_id::String; config::Dict{String,Any}=Dict{String,Any}())
    # 支持两种 preset_id 格式：
    #   新格式: "project_id::scenario_id"（项目驱动）
    #   旧格式: "shipping-demo" / "shipping-single-vessel" / "shipping-optimization"（向后兼容）
    project_dir = string(get(config, "project_dir", ""))
    scenario_id = ""

    if occursin("::", preset_id)
        parts = split(preset_id, "::"; limit=2)
        project_id = String(parts[1])
        scenario_id = String(parts[2])
        # 从注册表获取项目目录
        if isempty(project_dir) && haskey(_REGISTERED_PROJECTS, project_id)
            project_dir = _REGISTERED_PROJECTS[project_id]
        end
    elseif preset_id in ("shipping-demo", "shipping-single-vessel", "shipping-optimization")
        # 向后兼容：旧 preset_id 映射到默认项目
        if isempty(project_dir)
            project_dir = joinpath(@__DIR__, "..", "..", "examples", "shipping-liner-demo")
        end
        scenario_id = preset_id == "shipping-demo" ? "baseline" :
                      preset_id == "shipping-single-vessel" ? "aeu3-single-vessel" :
                      "aeu3-disrupted"
    else
        error("Unknown shipping preset: $preset_id")
    end

    # 从项目配置解析数据路径
    data_config = get(config, "data", Dict{String,Any}())
    if data_config isa AbstractDict
        data_config = Dict{String,Any}(string(k) => v for (k, v) in pairs(data_config))
    else
        data_config = Dict{String,Any}()
    end

    # 数据文件解析：优先从 config 获取，否则从项目目录解析
    function _resolve_data_path(path::String, base_dir::String, fallback_name::String)
        if isempty(path)
            return joinpath(base_dir, "data", fallback_name)
        elseif startswith(path, "./") || startswith(path, ".\\")
            return normpath(joinpath(base_dir, path))
        elseif isabspath(path)
            return path
        else
            return normpath(joinpath(base_dir, "data", path))
        end
    end

    schedule_file = _resolve_data_path(
        string(get(data_config, "route_schedule", "")),
        project_dir, "航线船期_20260507_ych.csv")
    od_file = _resolve_data_path(
        string(get(data_config, "od_demand", "")),
        project_dir, "od对需求_20260507_ych.csv")

    if !isfile(schedule_file)
        error("Shipping schedule file not found: $schedule_file")
    end
    if !isfile(od_file)
        error("Shipping OD file not found: $od_file")
    end

    schedules = load_route_schedules(schedule_file)
    all_ods = load_od_demand(od_file)
    route_id = string(get(config, "route_id", "AEU3"))
    max_sim_time = Float64(get(config, "max_sim_time", 200.0))

    # Disturbance factors from disruption_level
    disruption_level = Float64(get(config, "disruption_level", 0.0))
    disturbance_factor = 1.0 + disruption_level * 0.2   # e.g. level 1 -> 1.2x sailing time
    port_disturbance_factor = 1.0 + disruption_level * 0.1  # e.g. level 1 -> 1.1x port time

    route_od_map = Dict{String, Vector{ODDemand}}()
    for route in schedules
        route_od_map[route.route_id] = filter_ods_by_route(all_ods, route)
    end

    # 确保项目模型文件已加载（world, optimization, decision, simulation_bridge, analysis）
    if !project_models_loaded() && !isempty(project_dir)
        load_project_models(project_dir)
    end

    # 从项目场景配置中读取 scenario_id，用于判断构建逻辑
    # scenario_id 为空时使用 config 中的值
    if isempty(scenario_id)
        scenario_id = string(get(config, "scenario_id", "baseline"))
    end

    # 从项目场景配置加载额外参数
    scenario_config = Dict{String,Any}()
    if !isempty(project_dir)
        try
            manifest = load_project_manifest(project_dir)
            scenario_config = Main.load_project_scenario_config(manifest, scenario_id)
            # 合并场景配置到 config（场景配置优先级低于显式传入的 config）
            for (k, v) in pairs(scenario_config)
                if !haskey(config, k)
                    config[k] = v
                end
            end
        catch
            # 场景配置加载失败时继续，使用默认值
        end
    end

    model_name = "ShippingNetworkDemo"
    model = nothing

    # 根据 scenario_id 特征判断构建模式
    # 含 "disrupted" 或 "optimization" → 优化/扰动模式
    # 含 "single" 或 config 中有 route_id 且无 vessels_per_route → 单船模式
    # 其他 → 全网络模式
    is_optimization = occursin("disrupted", scenario_id) || occursin("optimization", scenario_id) ||
                      !isempty(string(get(config, "decision_model", "")))
    is_single_vessel = occursin("single", scenario_id) ||
                       (haskey(config, "route_id") && !haskey(config, "vessels_per_route"))

    if is_optimization && project_models_loaded()
        # 优化模式：构建世界 → 决策模型求解 → 注入仿真
        world = build_shipping_world(schedule_file, od_file;
            scenario_id=scenario_id,
            demand_multiplier=Float64(get(config, "demand_multiplier", 1.0)),
            capacity_multiplier=Float64(get(config, "capacity_multiplier", 1.0)),
            disruption_level=disruption_level,
            cycle_days=7,
            horizon_cycles=Int(get(config, "weeks_to_sim", 8)),
        )

        # 选择决策模型
        decision_model = TimeSpaceMILPModel(
            allow_transshipment=true,
            consider_time_windows=true,
            consider_capacity=true,
            allow_service_activation=true,
        )

        # 求解决策 → 生成 ExecutionPlan
        exec_plan = solve_decision(decision_model, world;
            scenario_id=scenario_id,
        )

        # 将 ExecutionPlan 注入仿真
        model = inject_plan(world, exec_plan)
        model_name = string("Optimized_", route_id)
    elseif is_single_vessel
        target = findfirst(route -> route.route_id == uppercase(route_id), schedules)
        target === nothing && error("Route not found for single vessel scenario: $route_id")

        route = schedules[target]
        model = build_multi_vessel_route(
            Symbol(string(route.route_id, "_Single")),
            route;
            vessel_count=1,
            first_vessel_week=Int(get(config, "first_week", 51)),
            disturbance_factor=disturbance_factor,
            port_disturbance_factor=port_disturbance_factor,
        )
        model_name = string(route.route_id, "SingleVessel")
    else
        weeks_to_sim = Int(get(config, "weeks_to_sim", 8))
        vessels_per_route = Int(get(config, "vessels_per_route", 5))
        first_week = Int(get(config, "first_week", 51))
        seed = Int(get(config, "seed", 42))

        model = build_shipping_network(
            :ShippingNetworkDemo,
            schedules,
            route_od_map;
            weeks_to_sim=weeks_to_sim,
            vessels_per_route=vessels_per_route,
            first_week=first_week,
            seed=seed,
            disturbance_factor=disturbance_factor,
            port_disturbance_factor=port_disturbance_factor,
        )
    end

    return (
        model_name = model_name,
        model = model,
        entities = model.entities,
        metadata = Dict{String,Any}(
            "extension_id" => "shipping",
            "preset_id" => preset_id,
            "scenario_id" => scenario_id,
            "project_dir" => project_dir,
            "schedule_file" => schedule_file,
            "od_file" => od_file,
            "route_id" => route_id,
            "max_sim_time" => max_sim_time,
            "disruption_level" => disruption_level,
        ),
    )
end
