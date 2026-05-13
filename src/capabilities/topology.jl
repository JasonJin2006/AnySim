using Graphs

struct TopologySummary
    entity_names::Vector{Symbol}
    entity_index::Dict{Symbol, Int}
    graph::SimpleDiGraph{Int}
    edge_connections::Dict{Tuple{Int, Int}, Vector{Connection}}
end

function topology_summary(model::ComposeDef)
    entities = traverse_entities(model)
    entity_names = [ent.name for ent in entities]
    entity_index = Dict(name => idx for (idx, name) in enumerate(entity_names))
    graph = SimpleDiGraph(length(entity_names))
    edge_connections = Dict{Tuple{Int, Int}, Vector{Connection}}()

    for conn in traverse_connections(model)
        src_name = conn.from[1]
        dst_name = conn.to[1]
        src = get(entity_index, src_name, 0)
        dst = get(entity_index, dst_name, 0)
        if src == 0 || dst == 0 || src == dst
            continue
        end

        add_edge!(graph, src, dst)
        push!(get!(edge_connections, (src, dst), Connection[]), conn)
    end

    return TopologySummary(entity_names, entity_index, graph, edge_connections)
end

function topology_metrics(model::ComposeDef)
    summary = topology_summary(model)
    graph = summary.graph
    node_count = nv(graph)
    edge_count = ne(graph)

    indegrees = node_count == 0 ? Int[] : indegree(graph)
    outdegrees = node_count == 0 ? Int[] : outdegree(graph)
    weak_components = weakly_connected_components(graph)
    cycles = simplecycles(graph)

    return Dict{String, Any}(
        "entity_count" => node_count,
        "connection_count" => length(traverse_connections(model)),
        "edge_count" => edge_count,
        "weak_component_count" => length(weak_components),
        "is_weakly_connected" => (node_count <= 1 ? true : length(weak_components) == 1),
        "has_cycles" => !isempty(cycles),
        "cycle_count" => length(cycles),
        "source_entities" => Symbol[
            summary.entity_names[idx] for idx in 1:node_count if indegrees[idx] == 0
        ],
        "sink_entities" => Symbol[
            summary.entity_names[idx] for idx in 1:node_count if outdegrees[idx] == 0
        ],
        "max_in_degree" => (isempty(indegrees) ? 0 : maximum(indegrees)),
        "max_out_degree" => (isempty(outdegrees) ? 0 : maximum(outdegrees)),
    )
end

function shortest_entity_path(model::ComposeDef, from::Symbol, to::Symbol)
    summary = topology_summary(model)
    src = get(summary.entity_index, from, 0)
    dst = get(summary.entity_index, to, 0)
    if src == 0 || dst == 0
        return Symbol[]
    end

    state = dijkstra_shortest_paths(summary.graph, src)
    if !isfinite(state.dists[dst])
        return Symbol[]
    end

    path = enumerate_paths(state, dst)
    return Symbol[summary.entity_names[idx] for idx in path]
end
