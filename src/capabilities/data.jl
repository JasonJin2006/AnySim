using Tables
using DataFrames
using CSV

function entity_table(model::Union{EntityDef, ComposeDef})
    entities = model isa EntityDef ? [model] : traverse_entities(model)
    rows = NamedTuple[]

    for ent in entities
        push!(rows, (
            name=String(ent.name),
            port_count=length(ent.ports),
            relation_count=length(ent.relations),
            parameter_count=length(ent.parameters),
        ))
    end

    return DataFrame(rows)
end

function write_entity_table_csv(path::AbstractString, model::Union{EntityDef, ComposeDef})
    df = entity_table(model)
    CSV.write(path, df)
    return path
end
