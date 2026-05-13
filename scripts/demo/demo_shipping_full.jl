# ============================================================
# test_shipping_full.jl — 海运仿真完整端到端测试
# ============================================================
include(joinpath(@__DIR__, "..", "..", "src", "AnySim.jl"))
using .AnySim
include(joinpath(@__DIR__, "..", "..", "extensions", "DEVS", "DEVS.jl"))
using .DEVS
include(joinpath(@__DIR__, "..", "..", "extensions", "Shipping", "Shipping.jl"))
using .Shipping

# 数据文件路径
data_dir = joinpath(@__DIR__, "..", "..", "data", "shipping")
schedule_file = joinpath(data_dir, "航线船期_20260507_ych.csv")
od_file = joinpath(data_dir, "od对需求_20260507_ych.csv")

println("=" ^ 60)
println("海运 DEVS 仿真测试")
println("=" ^ 60)

# ============================================================
# 1. 加载数据
# ============================================================
println("\n[1/5] 加载数据...")
schedules = load_route_schedules(schedule_file)
println("  加载 $(length(schedules)) 条航线:")
for s in schedules
    pc_str = join([pc.port_code for pc in s.port_calls], " → ")
    println("    $(s.route_id): $(length(s.port_calls))港, $(s.total_days)天")
    println("      $pc_str")
end

all_ods = load_od_demand(od_file)
println("  加载 $(length(all_ods)) 个 OD 对")

# 每条航线筛选 OD 对
route_od_map = Dict{String, Vector{ODDemand}}()
for s in schedules
    matched = filter_ods_by_route(all_ods, s)
    route_od_map[s.route_id] = matched
    ffe = sum(od.ffe_per_week for od in matched)
    println("    $(s.route_id): $(length(matched))个OD对, $(ffe) FFE/周")
end

# ============================================================
# 2. 测试单船单航线 (AEU3)
# ============================================================
println("\n[2/5] 测试单船 AEU3...")
route_aeu3 = first([s for s in schedules if s.route_id == "AEU3"])

# 创建单船
vessel = create_vessel(:TestVessel, "TestVessel-AEU3", route_aeu3, 0.0)

# 包装为 ComposeDef
comp_single = ComposeDef(:SingleVessel, [vessel], Relation[], Connection[], [])

println("  Vessel EntityDef: $(vessel.name)")
println("  参数: ", join([p.name for p in vessel.parameters], ", "))
println("  关系: ", join([r.name for r in vessel.relations], ", "))

# ============================================================
# 3. 执行单船仿真
# ============================================================
println("\n[3/5] 运行单船仿真 (DEVSSolver)...")
result_single = solve(DEVSSolver(max_steps=50, max_time=200.0), comp_single)

println("  仿真步数: $(length(result_single.times) - 1)")
println("  仿真时长: $(result_single.times[end]) 天")
println("  时间点: $(result_single.times)")

# 显示 _phase 轨迹
phase_key = Symbol("TestVessel__phase")
sigma_key = Symbol("TestVessel__sigma")
if haskey(result_single.raw, phase_key)
    phases = result_single.raw[phase_key]
    println("  _phase 轨迹:")
    for (i, t) in enumerate(result_single.times)
        println("    t=$t: phase=$(phases[i])")
    end
end
if haskey(result_single.states, sigma_key)
    println("  _sigma 轨迹: ", result_single.states[sigma_key])
end

# ============================================================
# 4. 测试多船航线 (AEU3, 3艘船)
# ============================================================
println("\n[4/5] 测试多船航线 AEU3 (3艘船)...")
multi_route = build_multi_vessel_route(:AEU3_Multi, route_aeu3, vessel_count=3, first_vessel_week=51)

println("  实体数: $(length(multi_route.entities))")
for e in multi_route.entities
    println("    $(e.name): $(length(e.ports))端口, $(length(e.parameters))参数")
end
println("  连接数: $(length(multi_route.connections))")

result_multi = solve(DEVSSolver(max_steps=200, max_time=200.0), multi_route)
println("  仿真步数: $(length(result_multi.times) - 1)")
println("  仿真时长: $(result_multi.times[end]) 天")

# ============================================================
# 5. 测试完整海运网络 (3航线, 短周期)
# ============================================================
println("\n[5/5] 测试完整海运网络 (3航线, 10周)...")
weeks_to_sim = 10
vessels_per_route = max(Int(ceil(maximum(s.total_days for s in schedules) / 7)) + 2, 5)
println("  每航线船舶数: $vessels_per_route")

root = build_shipping_network(:ShippingNetwork, schedules, route_od_map,
    weeks_to_sim=weeks_to_sim,
    vessels_per_route=vessels_per_route,
    first_week=51,
    seed=42)

println("  实体总数: $(length(root.entities))")
println("  连接总数: $(length(root.connections))")

# 限制最大步数和时间
result_full = solve(DEVSSolver(max_steps=5000, max_time=100.0), root)
println("  仿真步数: $(length(result_full.times) - 1)")
println("  仿真时长: $(result_full.times[end]) 天")
println("  时间点数: $(length(result_full.times))")

# 统计基本指标
println("\n--- 仿真统计 ---")
vessel_count = count(e -> any(p -> p.name == :vessel_name, e.parameters), root.entities)
port_count = count(e -> any(p -> p.name == :port_code, e.parameters), root.entities)
println("  船舶数: $vessel_count")
println("  港口数: $port_count")

println("\n" * "#" ^ 60)
println("海运仿真测试完成!")
println("=" ^ 60)
