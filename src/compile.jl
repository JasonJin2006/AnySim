# ============================================================
# compile: 将 Core 定义编译为可操作模型
# ============================================================

"""
    compile(def::Union{EntityDef, ComposeDef}) -> Union{EntityDef, ComposeDef}

"编译"一个模型定义。当前阶段只是返回原对象，后续会：
- 解析方程表达式为可计算/可变换的形式
- 检查类型一致性
- 检查方程平衡性
"""
function compile(def::T) where T <: Union{EntityDef, ComposeDef}
    # 阶段 0：只是返回结构
    return def
end

# ============================================================
# 显示 / 打印
# ============================================================

function show_info(io::IO, ::MIME"text/plain", ed::EntityDef)
    println(io, "Entity: $(ed.name)")
    if !isempty(ed.ports)
        println(io, "  Ports:")
        for p in ed.ports
            println(io, "    $(p.name)::$(p.ptype) ($(p.direction))")
        end
    end
    if !isempty(ed.relations)
        println(io, "  Relations:")
        for r in ed.relations
            println(io, "    $(r.name)  tags=$(r.tags)")
        end
    end
    if !isempty(ed.parameters)
        println(io, "  Params:")
        for p in ed.parameters
            default_str = p.default === nothing ? "" : " = $(p.default)"
            unit_str = p.unit === nothing ? "" : " [$(p.unit)]"
            println(io, "    $(p.name)::$(p.ptype)$default_str$unit_str")
        end
    end
end

function show_info(io::IO, ::MIME"text/plain", cd::ComposeDef)
    println(io, "Compose: $(cd.name)")
    println(io, "  Entities ($(length(cd.entities))):")
    for e in cd.entities
        println(io, "    $(e.name)")
    end
    println(io, "  Relations ($(length(cd.relations))):")
    for r in cd.relations
        println(io, "    $(r.name)")
    end
    if !isempty(cd.exports)
        println(io, "  Exports:")
        for (alias, e, p) in cd.exports
            println(io, "    $alias = $(e).$(p)")
        end
    end
end

Base.show(io::IO, ::MIME"text/plain", ed::EntityDef) = show_info(io, MIME("text/plain"), ed)
Base.show(io::IO, ::MIME"text/plain", cd::ComposeDef) = show_info(io, MIME("text/plain"), cd)

"""
    print_model_info(model::Union{EntityDef, ComposeDef})

打印模型的结构信息。
"""
function print_model_info(model::ComposeDef)
    println("="^50)
    println("Model: $(model.name)")
    println("="^50)
    println()

    entities = traverse_entities(model)
    println("Entities ($(length(entities))):")
    for e in entities
        println("  ├ $(e.name)")
        for p in e.ports
            println("  │  port $(p.name)::$(p.ptype) ($(p.direction))")
        end
        for r in e.relations
            println("  │  rel $(r.name)  tags=$(r.tags)")
        end
        if isempty(e.ports) && isempty(e.relations)
            println("  │  (no ports or relations)")
        end
    end

    println()
    rels = traverse_relations(model)
    println("Total Relations: $(length(rels))")

    model_type = classify_model(model)
    println("Model Type: $model_type")

    if !isempty(model.exports)
        println()
        println("Exports:")
        for (alias, ent, port) in model.exports
            println("  ├ $alias = $ent.$port")
        end
    end
    println("="^50)
end

function print_model_info(model::EntityDef)
    println("="^50)
    println("Entity: $(model.name)")
    println("="^50)
    for p in model.ports
        println("  port $(p.name)::$(p.ptype) ($(p.direction))")
    end
    for r in model.relations
        println("  rel $(r.name)  tags=$(r.tags)")
    end
    println("="^50)
end
