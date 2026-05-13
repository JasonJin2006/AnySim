# ============================================================
# execution_ir.jl — DEVS 执行层中间表示
# ============================================================

struct CompiledDEVSModel <: AbstractExecutionIR
    model_name::Symbol
    entity_names::Vector{Symbol}
    entity_index::Dict{Symbol, Int}
    initial_states::Vector{Dict{Symbol, Any}}
    ta_fns::Vector{Any}
    lambdaf_fns::Vector{Any}
    deltint_fns::Vector{Any}
    deltext_fns::Vector{Any}
    couplings::Vector{NTuple{4, Symbol}}
end

struct DEVSCompileDiagnostics
    missing_ta::Vector{Symbol}
    missing_lambdaf::Vector{Symbol}
    missing_deltint::Vector{Symbol}
    missing_deltext::Vector{Symbol}
end

mutable struct DEVSRuntimeState <: AbstractExecutionRuntime
    current_time::Float64
    states::Vector{Dict{Symbol, Any}}
end

function DEVSRuntimeState(compiled::CompiledDEVSModel; current_time=0.0)
    return DEVSRuntimeState(current_time, deepcopy(compiled.initial_states))
end

function compile_devs_ir(model::ComposeDef)
    entities = traverse_entities(model)
    entity_names = [e.name for e in entities]
    entity_index = Dict(name => i for (i, name) in enumerate(entity_names))

    initial_states = Vector{Dict{Symbol, Any}}(undef, length(entities))
    ta_fns = Vector{Any}(undef, length(entities))
    lambdaf_fns = Vector{Any}(undef, length(entities))
    deltint_fns = Vector{Any}(undef, length(entities))
    deltext_fns = Vector{Any}(undef, length(entities))
    fill!(ta_fns, nothing)
    fill!(lambdaf_fns, nothing)
    fill!(deltint_fns, nothing)
    fill!(deltext_fns, nothing)

    for (i, e) in enumerate(entities)
        state = Dict{Symbol, Any}()
        for p in e.parameters
            state[p.name] = p.default !== nothing ? deepcopy(p.default) : 0.0
        end

        if !haskey(state, :_phase)
            state[:_phase] = PhaseInit
        end
        if !haskey(state, :_sigma)
            state[:_sigma] = INFINITY
        end
        if !haskey(state, :_inbox)
            state[:_inbox] = DEVSMessage[]
        end
        if !haskey(state, :_outbox)
            state[:_outbox] = DEVSMessage[]
        end

        initial_states[i] = state

        for r in e.relations
            if :devs_ta in r.tags
                ta_fns[i] = compile_relation(r, e.parameters; eval_module=@__MODULE__)
            elseif :devs_lambdaf in r.tags
                lambdaf_fns[i] = compile_relation(r, e.parameters; eval_module=@__MODULE__)
            elseif :devs_deltint in r.tags
                deltint_fns[i] = compile_relation(r, e.parameters; eval_module=@__MODULE__)
            elseif :devs_deltext in r.tags
                deltext_fns[i] = compile_relation(r, e.parameters; eval_module=@__MODULE__)
            end
        end
    end

    couplings = NTuple{4, Symbol}[]
    for conn in model.connections
        push!(couplings, (conn.from[1], conn.from[2], conn.to[1], conn.to[2]))
    end

    return CompiledDEVSModel(
        model.name,
        entity_names,
        entity_index,
        initial_states,
        ta_fns,
        lambdaf_fns,
        deltint_fns,
        deltext_fns,
        couplings,
    )
end

function devs_compile_diagnostics(compiled::CompiledDEVSModel)
    missing_ta = Symbol[]
    missing_lambdaf = Symbol[]
    missing_deltint = Symbol[]
    missing_deltext = Symbol[]

    for (i, ent_name) in enumerate(compiled.entity_names)
        compiled.ta_fns[i] === nothing && push!(missing_ta, ent_name)
        compiled.lambdaf_fns[i] === nothing && push!(missing_lambdaf, ent_name)
        compiled.deltint_fns[i] === nothing && push!(missing_deltint, ent_name)
        compiled.deltext_fns[i] === nothing && push!(missing_deltext, ent_name)
    end

    return DEVSCompileDiagnostics(
        missing_ta,
        missing_lambdaf,
        missing_deltint,
        missing_deltext,
    )
end

function has_devs_compile_warnings(diag::DEVSCompileDiagnostics)
    return !isempty(diag.missing_ta) ||
           !isempty(diag.missing_lambdaf) ||
           !isempty(diag.missing_deltint) ||
           !isempty(diag.missing_deltext)
end
