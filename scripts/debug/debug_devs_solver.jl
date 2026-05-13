# ============================================================
# test_devs_debug.jl — DEVS 求解器调试
# ============================================================
include(joinpath(@__DIR__, "..", "..", "src", "AnySim.jl"))
using .AnySim
include(joinpath(@__DIR__, "..", "..", "extensions", "DEVS", "DEVS.jl"))
using .DEVS

@devs_atomic SimpleTimer begin
    @state _phase = :ticking   # 初始相位
    @state _sigma = 1.0        # 初始 sigma

    @ta begin
        # ta 函数：根据阶段设置 sigma
        _sigma = _phase == :ticking ? 1.0 : INFINITY
    end
    @deltint begin
        hold_in(state, :ticking, 1.0)
    end
    @lambdaf begin
        devs_send!(state, :tick, true)
    end
end

println("=== 手动步进测试 ===")
comp = ComposeDef(:Test, [SimpleTimer], Relation[], Connection[], [])
ctx = init_devs_context(comp)
ctx.current_time = 0.0

println("初始状态:")
for (n, s) in ctx.states
    println("  $n: _phase=$(s[:_phase]), _sigma=$(s[:_sigma])")
end

# Debug: check ta_fns
for (n, fn) in ctx.ta_fns
    println("  $n: ta_fn exists: $(fn !== nothing)")
    # Call it and check state
    try
        Base.invokelatest(fn, ctx.states[n], ctx, 0.0)
        println("  $n: after ta: _phase=$(ctx.states[n][:_phase]), _sigma=$(ctx.states[n][:_sigma])")
    catch e
        println("  $n: ta failed: $e")
    end
end

for i in 1:3
    println("\n--- 步 $i ---")
    tn, imminent = time_advance(ctx)
    println("  tn=$tn, imminent=$imminent, time=$(ctx.current_time)")

    tn >= INFINITY && break

    for (n, s) in ctx.states
        s[:_sigma] -= tn
    end
    ctx.current_time += tn

    for ent in imminent
        if haskey(ctx.lambdaf_fns, ent)
            try
                Base.invokelatest(ctx.lambdaf_fns[ent], ctx.states[ent], ctx, 0.0)
                println("  $ent: lambdaf ✓")
            catch e
                println("  $ent: lambdaf ✗: $e")
            end
        end
        if haskey(ctx.deltint_fns, ent)
            try
                Base.invokelatest(ctx.deltint_fns[ent], ctx.states[ent], ctx, 0.0)
                println("  $ent: deltint ✓")
            catch e
                println("  $ent: deltint ✗: $e")
            end
        end
    end

    for (n, s) in ctx.states
        s[:_inbox] = DEVSMessage[]
        s[:_outbox] = DEVSMessage[]
    end

    for (n, s) in ctx.states
        println("  状态: _phase=$(s[:_phase]), _sigma=$(s[:_sigma])")
    end
end

println("\n=== 自动求解测试 ===")
result = solve(DEVSSolver(max_steps=5, max_time=100.0), comp)
println("  Times: ", result.times)
println("  SimpleTimer__sigma = ", get(result.states, :SimpleTimer__sigma, "N/A"))
