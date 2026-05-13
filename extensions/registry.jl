abstract type AbstractExtensionPlugin end

extension_id(::AbstractExtensionPlugin)::String = error("extension_id not implemented")
extension_label(::AbstractExtensionPlugin)::String = error("extension_label not implemented")
extension_presets(::AbstractExtensionPlugin)::Vector{Dict{String,Any}} = Dict{String,Any}[]
build_model(::AbstractExtensionPlugin, preset_id::String; config::Dict{String,Any}=Dict{String,Any}()) =
    error("build_model not implemented")

const EXTENSION_REGISTRY = Dict{String, AbstractExtensionPlugin}()

function register_extension!(plugin::AbstractExtensionPlugin)
    EXTENSION_REGISTRY[extension_id(plugin)] = plugin
    return plugin
end

function registered_extensions()
    return collect(values(EXTENSION_REGISTRY))
end

function all_presets()
    presets = Dict{String,Any}[]
    for plugin in values(EXTENSION_REGISTRY)
        append!(presets, extension_presets(plugin))
    end
    return presets
end

function find_plugin_for_preset(preset_id::String)
    for plugin in values(EXTENSION_REGISTRY)
        for preset in extension_presets(plugin)
            if get(preset, "id", "") == preset_id
                return plugin
            end
        end
    end
    error("Unknown preset: $preset_id")
end
