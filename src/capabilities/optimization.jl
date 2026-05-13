using Optim

function optimize_scalar(objective::Function, initial_value::Real; lower=nothing, upper=nothing)
    if lower !== nothing && upper !== nothing
        result = optimize(x -> objective(x), float(lower), float(upper))
    else
        span = max(abs(float(initial_value)), 1.0)
        result = optimize(x -> objective(x), float(initial_value) - 5span, float(initial_value) + 5span)
    end

    return Dict{String, Any}(
        "minimizer" => Optim.minimizer(result),
        "minimum" => Optim.minimum(result),
        "converged" => Optim.converged(result),
    )
end
