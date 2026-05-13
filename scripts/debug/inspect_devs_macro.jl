include(joinpath(@__DIR__, "..", "..", "src", "AnySim.jl"))
using .AnySim
include(joinpath(@__DIR__, "..", "..", "extensions", "DEVS", "DEVS.jl"))
using .DEVS

@devs_atomic SimpleTimer begin
    @state _phase = :ticking
    @state _sigma = 1.0

    @ta begin
        _sigma = _phase == :ticking ? 1.0 : INFINITY
    end
    @deltint begin
        hold_in(state, :ticking, 1.0)
    end
end

println("=== EntityDef ===")
println("Name: ", SimpleTimer.name)
println("\nParams:")
for p in SimpleTimer.parameters
    println("  $(p.name) = $(p.default) :: $(p.ptype)")
end

println("\nRelations:")
for r in SimpleTimer.relations
    println("  $(r.name): tags=$(r.tags)")
    println("    metadata=$(r.metadata)")
    println("    expr type=$(typeof(r.expr))")
    println("    expr=$(r.expr)")
end

println("\n=== Testing compile_relation ===")
for r in SimpleTimer.relations
    if :devs_ta in r.tags
        fn = compile_relation(r, SimpleTimer.parameters)
        println("ta function: ", fn)
        state = Dict{Symbol, Any}(
            :_phase => :ticking,
            :_sigma => 1.0,
            :_inbox => DEVSMessage[],
            :_outbox => DEVSMessage[],
        )
        println("Before: _phase=$(state[:_phase]), _sigma=$(state[:_sigma])")
        fn(state, nothing, 0.0)
        println("After: _phase=$(state[:_phase]), _sigma=$(state[:_sigma])")
    end
end
