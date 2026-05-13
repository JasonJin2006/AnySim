#!/usr/bin/env julia
# ============================================================
# anysim-server.jl — AnySim DEVS WebSocket 服务端启动脚本
#
# 用法:
#   julia bin/anysim-server.jl [--port 8080] [--host 127.0.0.1] [--model default|shipping-demo]
#
# 启动后前端通过 ws://host:port/ws/sim 连接。
# ============================================================

# 解析命令行参数
port = 8080
host = "127.0.0.1"
model = "default"
project = ""
for i in 1:length(ARGS)
    if ARGS[i] == "--port" && i < length(ARGS)
        port = parse(Int, ARGS[i+1])
    elseif ARGS[i] == "--host" && i < length(ARGS)
        host = ARGS[i+1]
    elseif ARGS[i] == "--model" && i < length(ARGS)
        model = ARGS[i+1]
    elseif ARGS[i] == "--project" && i < length(ARGS)
        project = ARGS[i+1]
    end
end

println("="^60)
println("  AnySim — DEVS Runtime Server")
println("  WebSocket 服务端 v0.1")
println("="^60)
println()

# 加载 AnySim 核心
include(joinpath(@__DIR__, "..", "src", "AnySim.jl"))
using .AnySim
include(joinpath(@__DIR__, "..", "src", "project_loader.jl"))

# 加载扩展注册中心
include(joinpath(@__DIR__, "..", "extensions", "registry.jl"))

# 加载 DEVS 扩展
include(joinpath(@__DIR__, "..", "extensions", "DEVS", "DEVS.jl"))
using .DEVS

# 加载 Shipping 扩展（仅在选择 shipping-demo 时使用其装配函数）
include(joinpath(@__DIR__, "..", "extensions", "Shipping", "Shipping.jl"))
using .Shipping
register_extension!(Shipping.ShippingPlugin())

# 自动注册默认航运项目，使 get_presets 可用
default_project = joinpath(@__DIR__, "..", "examples", "shipping-liner-demo")
if isdir(default_project)
    Shipping.register_project!("shipping-liner-demo", abspath(default_project))
    @info "[Bootstrap] 已注册默认项目: shipping-liner-demo"
end

# 加载 AgentBased 扩展，保持扩展入口一致
include(joinpath(@__DIR__, "..", "extensions", "AgentBased", "AgentBased.jl"))
using .AgentBased

# 加载 DEVS WebSocket 服务
include(joinpath(@__DIR__, "..", "extensions", "DEVS", "server.jl"))

# 启动服务器
println("  监听地址: ws://$host:$port/ws/sim")
println("  运行模型: $model")
if !isempty(project)
    println("  项目目录: $project")
end
println("  前端连接: 在 frontend/ 目录运行 npm run dev")
println()
println("  按 Ctrl+C 停止服务器")
println()

run_server(host=host, port=port, model=model, project=project)
