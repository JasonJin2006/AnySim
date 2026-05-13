using Random
using StatsBase
using Distributions

function degree_distribution(model::ComposeDef)
    summary = topology_summary(model)
    graph = summary.graph
    if nv(graph) == 0
        return Dict{Int, Int}()
    end

    total_degree = indegree(graph) .+ outdegree(graph)
    hist = countmap(total_degree)
    return Dict{Int, Int}(k => v for (k, v) in hist)
end

function sample_parameter(dist::Distribution; rng=Random.default_rng())
    return rand(rng, dist)
end
