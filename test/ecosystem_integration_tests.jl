using DataFrames
using Distributions
using Test

@testset "Ecosystem Integration" begin
    src = EntityDef(:Source, Port[Port(:out, Float64, :out)], Relation[], Parameter[])
    mid = EntityDef(:Processor, Port[Port(:in, Float64, :in), Port(:out, Float64, :out)], Relation[], Parameter[])
    sink = EntityDef(:Sink, Port[Port(:in, Float64, :in)], Relation[], Parameter[])

    model = ComposeDef(
        :Pipeline,
        [src, mid, sink],
        Relation[],
        Connection[
            Connection((:Source, :out), (:Processor, :in)),
            Connection((:Processor, :out), (:Sink, :in)),
        ],
        Tuple{String, Symbol, Symbol}[],
    )

    summary = topology_summary(model)
    @test length(summary.entity_names) == 3

    metrics = topology_metrics(model)
    @test metrics["entity_count"] == 3
    @test metrics["connection_count"] == 2
    @test metrics["edge_count"] == 2
    @test metrics["cycle_count"] == 0
    @test metrics["source_entities"] == [:Source]
    @test metrics["sink_entities"] == [:Sink]

    @test shortest_entity_path(model, :Source, :Sink) == [:Source, :Processor, :Sink]
    @test shortest_entity_path(model, :Sink, :Source) == Symbol[]

    df = entity_table(model)
    @test nrow(df) == 3
    @test "name" in names(df)

    dist = degree_distribution(model)
    @test get(dist, 1, 0) == 2
    @test get(dist, 2, 0) == 1

    sampled = sample_parameter(Normal(0, 1))
    @test sampled isa Float64

    duration = voyage_duration(240, 20)
    @test occursin("hr", string(duration))
    @test nautical_miles_to_km(10) == 18.52

    @test route_distance(["A", "B", "C"], ["A", "C"]) == 1
    @test coordinate_distance_km((0.0, 0.0), (3.0, 4.0)) == 5.0

    optimum = optimize_scalar(x -> (x - 3)^2, 0.0)
    @test abs(optimum["minimizer"] - 3.0) < 1e-3
    @test optimum["converged"] isa Bool
end
