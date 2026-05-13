module Shipping

import ..AnySim: EntityDef, Relation, Behavioral, Connection, ComposeDef
import ..AnySim: Port, Parameter
import ..DEVS: DEVSMessage, INFINITY, PhaseInit

include("types.jl")
include("models.jl")              # DEVS 原子模型工厂 (平台能力)
include("exports.jl")             # 通用导出工具 (平台能力)
include("plugin.jl")              # 扩展注册入口

# ============================================================
# 项目模型文件动态加载
# 业务逻辑从项目目录动态 include，不再硬编码在扩展中。
# 调用 load_project_models(project_dir) 加载。
# ============================================================

const _project_models_loaded = Ref(false)
const _symbols_before_project = Set{Symbol}()

function load_project_models(project_dir::String)
    model_dir = joinpath(project_dir, "model")
    if !isdir(model_dir)
        @warn "[Shipping] 项目模型目录不存在: $model_dir"
        return
    end

    # 记录加载前的符号集合，用于后续自动发现新符号
    empty!(_symbols_before_project)
    for sym in names(Shipping; all=true)
        push!(_symbols_before_project, sym)
    end

    # 支持从 anysim-project.json 的 model_files 字段读取文件列表
    # 如果项目配置未指定，则使用默认加载顺序
    model_files = String[]
    manifest_path = joinpath(project_dir, "anysim-project.json")
    if isfile(manifest_path)
        try
            manifest = Main.load_project_manifest(project_dir)
            configured = get(manifest, "model_files", Any[])
            if !isempty(configured)
                for f in configured
                    push!(model_files, string(f))
                end
            end
        catch
            # 配置读取失败，使用默认
        end
    end
    if isempty(model_files)
        model_files = [
            "world.jl",              # A层: 世界模型
            "optimization.jl",       # 优化求解
            "decision_interface.jl", # B层: 决策模型
            "simulation_bridge.jl",  # C→D层: 仿真桥接
            "analysis.jl",           # E层: 结果分析
        ]
    end

    for fname in model_files
        fpath = joinpath(model_dir, fname)
        if isfile(fpath)
            Base.include(Shipping, fpath)
            @info "[Shipping] 已加载项目模型: $fname"
        else
            @warn "[Shipping] 项目模型文件缺失: $fpath"
        end
    end
    _project_models_loaded[] = true
    _export_project_symbols()
    return nothing
end

function project_models_loaded()
    return _project_models_loaded[]
end

# ============================================================
# 平台级 export — 扩展自带的建模原语和基础类型
# 这些在扩展初始化时就可用，不依赖项目模型文件
# ============================================================

# 基础类型 (types.jl)
export PortCall, RouteSchedule, ODDemand, VesselEvent, CargoBatch, PortStats, SimSnapshot
export CostConfig, ScenarioConfig
export PlannedCall, PlannedVesselRotation, PlannedPathLeg, PlannedDemandAssignment
export PlannedService, PlanMeta, ExecutionPlan

# DEVS 模型工厂 (models.jl) — 平台核心能力
export create_vessel, create_port, create_demand_generator
export build_multi_vessel_route, build_shipping_network
export build_simulation_model, build_plan_from_config, build_plan_from_schedules
export load_route_schedules, load_od_demand, filter_ods_by_route
export duration, ports

# 导出工具 (exports.jl)
export ShippingPlugin
export collect_shipping_history, simulate_shipping_project
export shipping_events_table, shipping_port_stats_table
export shipping_cargo_table, shipping_revenue_summary, shipping_scorecard, shipping_report_lines
export write_shipping_events_csv, write_shipping_port_stats_csv, write_shipping_cargo_csv
export write_shipping_report, write_shipping_scorecard
export export_shipping_results

# ============================================================
# 项目级 export — 自动发现机制
# 加载项目模型文件后，自动对比加载前后的符号差异，
# 将新增的公开符号（非下划线开头）全部导出。
# 不再需要硬编码符号列表。
# ============================================================

function _export_project_symbols()
    if isempty(_symbols_before_project)
        @warn "[Shipping] _symbols_before_project 为空，跳过自动导出"
        return
    end
    current_symbols = Set{Symbol}(names(Shipping; all=true))
    new_symbols = setdiff(current_symbols, _symbols_before_project)
    exported_count = 0
    for sym in new_symbols
        # 跳过内部符号（下划线开头）和模块自身
        str = string(sym)
        if startswith(str, "_") || sym === :Shipping
            continue
        end
        if isdefined(Shipping, sym)
            Base.export(Shipping, sym)
            exported_count += 1
        end
    end
    @info "[Shipping] 自动导出 $(exported_count) 个项目符号（共发现 $(length(new_symbols)) 个新符号）"
end

println("[Shipping] Extension loaded.")

end # module Shipping
