include(joinpath(@__DIR__, "..", "..", "src", "AnySim.jl"))
using .AnySim
include(joinpath(@__DIR__, "..", "..", "extensions", "DEVS", "DEVS.jl"))
using .DEVS

# Use @devs_atomic macro (the actual use case)
@devs_atomic SimpleTimer begin
    @state _phase = :ticking
    @state _sigma = 1.0

    @ta begin
        # Test 1: simple assignment
        _phase = :ticking  # set _phase to make sure
        # Debug: use a simple boolean to check
        is_ticking = _phase == :ticking
        if is_ticking
            _sigma = 1.0
        else
            _sigma = INFINITY
        end
    end
    @deltint begin
        hold_in(state, :ticking, 1.0)
    end
end

println("=== Testing ===")
for r in SimpleTimer.relations
    if :devs_ta in r.tags
        fn = compile_relation(r, SimpleTimer.parameters)
        println("ta function compiled: ", fn)
        state = Dict{Symbol, Any}(
            :_phase => :ticking,
            :_sigma => 1.0,
            :_inbox => DEVSMessage[],
            :_outbox => DEVSMessage[],
        )
        println("Before: _phase=$(repr(state[:_phase])), _sigma=$(state[:_sigma])")
        try
            Base.invokelatest(fn, state, nothing, 0.0)
            println("After: _phase=$(repr(state[:_phase])), _sigma=$(state[:_sigma])")
        catch e
            println("ERROR: $e")
        end
    end
end
