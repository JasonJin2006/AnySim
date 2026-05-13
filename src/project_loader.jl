using JSON3

function _normalize_json_value(value)
    if value isa AbstractDict
        out = Dict{String,Any}()
        for (k, v) in pairs(value)
            out[string(k)] = _normalize_json_value(v)
        end
        return out
    elseif value isa AbstractVector
        return Any[_normalize_json_value(v) for v in value]
    else
        return value
    end
end

function _string_dict(value)::Dict{String,Any}
    if value isa Dict{String,Any}
        return value
    elseif value isa AbstractDict
        out = Dict{String,Any}()
        for (k, v) in pairs(value)
            out[string(k)] = v
        end
        return out
    else
        return Dict{String,Any}()
    end
end

function load_project_manifest(project_dir::String)::Dict{String,Any}
    manifest_path = joinpath(project_dir, "anysim-project.json")
    isfile(manifest_path) || error("Project manifest not found: $manifest_path")

    manifest = _normalize_json_value(JSON3.read(read(manifest_path, String)))
    manifest["project_dir"] = abspath(project_dir)
    manifest["manifest_path"] = abspath(manifest_path)
    return manifest
end

function load_project_scenario_config(manifest::Dict{String,Any}, scenario_id::String="")
    scenarios = get(manifest, "scenarios", Any[])
    isempty(scenarios) && return Dict{String,Any}()

    selected = nothing
    if isempty(scenario_id)
        selected = first(scenarios)
    else
        for scenario in scenarios
            scenario_dict = _string_dict(scenario)
            if get(scenario_dict, "id", "") == scenario_id
                selected = scenario
                break
            end
        end
    end

    selected === nothing && error("Scenario not found: $scenario_id")
    selected_dict = _string_dict(selected)
    config_rel = get(selected_dict, "config_path", "")
    isempty(config_rel) && return Dict{String,Any}()

    config_path = normpath(joinpath(manifest["project_dir"], config_rel))
    isfile(config_path) || error("Scenario config not found: $config_path")
    return _normalize_json_value(JSON3.read(read(config_path, String)))
end

function resolve_project_entry(manifest::Dict{String,Any}; scenario_id::String="")
    entrypoint = _string_dict(get(manifest, "entrypoint", Dict{String,Any}()))
    entry_type = get(entrypoint, "type", "")
    entry_type == "preset" || error("Unsupported project entrypoint type: $entry_type")

    preset_id = get(entrypoint, "preset_id", "")
    isempty(preset_id) && error("Project preset_id is required")

    config = load_project_scenario_config(manifest, scenario_id)
    return (
        preset_id = preset_id,
        config = config,
    )
end
