# Test ta function compilation directly
include(joinpath(@__DIR__, "..", "..", "src", "AnySim.jl"))
using .AnySim

# Test ta body directly
ta_expr = quote
    _sigma = _phase == :ticking ? 1.0 : INFINITY
end

println("ta_expr: ", ta_expr)
println("INFINITY = ", INFINITY)

ta_rel = Relation(:ta, Behavioral, ta_expr, [:devs_ta, :behavioral],
    Dict{Symbol,Any}(:state_vars => [:_phase, :_sigma]))

params = [
    Parameter(:_phase, :ticking, Symbol),
    Parameter(:_sigma, 1.0, Float64),
]

fn = compile_relation(ta_rel, params)
println("function type: ", typeof(fn))
println("function: ", fn)

state = Dict{Symbol, Any}(:_phase => :ticking, :_sigma => 1.0)
println("Before: _phase=$(state[:_phase]), _sigma=$(state[:_sigma])")

try
    fn(state, nothing, 0.0)
    println("After: _phase=$(state[:_phase]), _sigma=$(state[:_sigma])")
catch e
    println("ERROR: $e")
    showerror(stderr, e)
end
