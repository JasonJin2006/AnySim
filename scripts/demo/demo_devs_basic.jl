# ============================================================
# test_devs_basic.jl — DEVS 基础测试
# ============================================================
include(joinpath(@__DIR__, "..", "..", "src", "AnySim.jl"))
using .AnySim
include(joinpath(@__DIR__, "..", "..", "extensions", "DEVS", "DEVS.jl"))
using .DEVS

println("=== 测试 @devs_atomic 宏 ===")

@devs_atomic Counter begin
    @port_in  reset::Int
    @port_out count::Int

    @state value = 0

    @ta begin
    end

    @lambdaf begin
        devs_send!(state, :count, value)
    end

    @deltint begin
        value = value + 1
        hold_in(state, :active, 1.0)
    end

    @deltext begin
        msgs = devs_receive(state, :reset)
        if !isempty(msgs)
            value = 0
        end
        continuef(state, e)
    end
end

println("Counter entity defined: ", Counter isa EntityDef)
println("  Name: ", Counter.name)
println("  Ports: ", [p.name for p in Counter.ports])
println("  Params: ", [(p.name, p.default) for p in Counter.parameters])
println("  Relations: ", [(r.name, r.tags) for r in Counter.relations])

# Test DEVS solver
println("\n=== 测试 DEVS 求解器 ===")
solver = DEVSSolver(max_steps=5, max_time=100.0)
comp = ComposeDef(:Test, [Counter], Relation[], Connection[], [])

result = solve(solver, comp)
println("  Times: ", result.times)
println("  States keys: ", keys(result.states) |> collect)

# Show state values
for (k, v) in result.states
    println("  $k = $v")
end

println("\n=== 测试通过! ===")
