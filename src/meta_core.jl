# ============================================================
# Meta-Core: 反射 / 遍历 / 查询 / 变换 API
#
# 五项核心能力：
#   1. 结构遍历（Traversal）
#   2. 算子/标签检测（Query）
#   3. 模型变换（Transform）
#   4. 运行时结构变更（Injection）
#   5. 跨模型映射（Mapping）
# ============================================================

# ============================================================
# 1. 结构遍历
# ============================================================

"""
    traverse_entities(model) -> Vector{EntityDef}

返回 model 中所有的 entity 定义。
- EntityDef → 返回 `[自身]`（一元操作，便于泛型调度）
- ComposeDef → 递归展开嵌套 compose
"""
traverse_entities(e::EntityDef) = [e]

function traverse_entities(model::ComposeDef)
    result = EntityDef[]
    _traverse_entities!(result, model)
    return result
end

function _traverse_entities!(result, cd::ComposeDef)
    for e in cd.entities
        push!(result, e)
    end
    for sc in cd.subcomposes
        _traverse_entities!(result, sc)
    end
end

"""
    traverse_relations(model) -> Vector{Relation}

返回 model 中所有的 relation。
- EntityDef → 返回自身的 relations（一元操作）
- ComposeDef → 包含嵌套 entity 内 + 自身层级的所有 relations
"""
traverse_relations(e::EntityDef) = e.relations

function traverse_relations(model::ComposeDef)
    result = Relation[]
    for e in traverse_entities(model)
        append!(result, e.relations)
    end
    append!(result, model.relations)
    return result
end

"""
    traverse_connections(model::ComposeDef) -> Vector{Connection}

返回 compose 中所有的连接映射。
"""
traverse_connections(model::ComposeDef) = model.connections

# ============================================================
# 2. 算子/标签检测
# ============================================================

"""
    relation_uses_operator(rel::Relation, op::Symbol) -> Bool

检测 relation 是否使用了特定算子（如 `:der`, `:∫`, `:when`）。

双路径检测：
  1. 快速路径 — 检查 tags（来自宏展开时的 auto-tagging）
  2. 完整路径 — 递归扫描 expr AST（覆盖手动构造无标签的 Relation）

底层复用 `AnySim._has_operator`（定义于 macros.jl）。
"""
function relation_uses_operator(rel::Relation, op::Symbol)
    # 快速路径：标签匹配
    op in rel.tags && return true
    # 如果查询的是 :der，也检查同义标签 :∂ₜ
    if op == :der && Symbol("∂ₜ") in rel.tags
        return true
    end
    # 完整路径：扫描表达式 AST
    return _has_operator(rel.expr, op)
end

"""
    classify_model(model::ComposeDef) -> Symbol

对模型进行分类。

返回类型：
  - `:continuous` — 包含微分算子（der/∂ₜ）
  - `:discrete`   — 包含事件算子（when/stochastic），无微分
  - `:hybrid`     — 同时包含微分和事件算子
  - `:static`     — 纯代数方程，无微分无事件
"""
function classify_model(model::ComposeDef)
    all_rels = traverse_relations(model)

    has_der = any(r -> relation_uses_operator(r, :der), all_rels)
    has_event = any(r -> relation_uses_operator(r, :when), all_rels)
    has_stochastic = any(r -> relation_uses_operator(r, :stochastic), all_rels)

    if has_der && (has_event || has_stochastic)
        return :hybrid
    elseif has_der
        return :continuous
    elseif has_event || has_stochastic
        return :discrete
    else
        return :static
    end
end

# ============================================================
# 3. 模型查询（Tag / 模式搜索）
# ============================================================

"""
    find_by_tag(model, tag::Symbol) -> Vector{Relation}
    find_by_tag(rels::Vector{Relation}, tag::Symbol) -> Vector{Relation}

按标签搜索所有 relation。返回包含指定标签的 relation 列表。
支持 EntityDef、ComposeDef 以及预提取的 Vector{Relation}。
"""
find_by_tag(model, tag::Symbol) = [r for r in traverse_relations(model) if tag in r.tags]
find_by_tag(rels::Vector{Relation}, tag::Symbol) = [r for r in rels if tag in r.tags]

"""
    query_relations(model; tags=[], operator=nothing, kind=nothing) -> Vector{Relation}

多条件组合查询。支持按标签集合、算子名、RelationKind 过滤。
条件之间是 AND 关系。所有条件可省略（返回全部 relation）。

# 示例
    query_relations(model, tags=[:equation])
    query_relations(model, operator=:der, kind=Equation)
    query_relations(model, tags=[:∂ₜ])
"""
function query_relations(model; tags=Symbol[], operator=nothing, kind=nothing)
    rels = traverse_relations(model)
    if !isempty(tags)
        tag_set = Set(tags)
        rels = filter(r -> !isempty(intersect(r.tags, tag_set)), rels)
    end
    if operator !== nothing
        rels = filter(r -> relation_uses_operator(r, operator), rels)
    end
    if kind !== nothing
        rels = filter(r -> r.kind == kind, rels)
    end
    return rels
end

# ============================================================
# 4. 模型变换
# ============================================================

"""
    map_model(f, model) -> model

对模型中所有 relation 应用变换函数 `f(relation) -> new_relation`。
返回变换后的模型副本（不修改原模型）。

支持 EntityDef 和 ComposeDef。
配合 `substitute_relation` 使用时，`map_model` 适合批量变换，
而 `substitute_relation` 适合精确替换单个 relation。
"""
function map_model(f, model::EntityDef)
    new_rels = Relation[f(r) for r in model.relations]
    return EntityDef(model.name, model.ports, new_rels, model.parameters)
end

function map_model(f, model::ComposeDef)
    new_entities = [map_model(f, e) for e in model.entities]
    new_subcomposes = [map_model(f, sc) for sc in model.subcomposes]
    new_rels = Relation[f(r) for r in model.relations]
    return ComposeDef(model.name, new_entities, new_subcomposes, new_rels,
                      model.connections, model.exports)
end

"""
    substitute_relation(model, target_name::Symbol, new_rel::Relation) -> model

替换模型中指定名称的 relation 为新的 relation。
返回变换后的模型副本。
"""
function substitute_relation(model::EntityDef, target_name::Symbol, new_rel::Relation)
    new_rels = [r.name == target_name ? new_rel : r for r in model.relations]
    return EntityDef(model.name, model.ports, new_rels, model.parameters)
end

function substitute_relation(model::ComposeDef, target_name::Symbol, new_rel::Relation)
    new_entities = [substitute_relation(e, target_name, new_rel) for e in model.entities]
    new_subcomposes = [substitute_relation(sc, target_name, new_rel) for sc in model.subcomposes]
    new_rels = [r.name == target_name ? new_rel : r for r in model.relations]
    return ComposeDef(model.name, new_entities, new_subcomposes, new_rels,
                      model.connections, model.exports)
end

# ============================================================
# 5. 模型验证
# ============================================================

"""
    validate_diagnostics(model) -> Vector{Diagnostic}

验证模型有效性，返回结构化 diagnostics。
这是 AnySim 后续 AI-friendly diagnostics 的核心入口。

当前第一版覆盖：

EntityDef 验证项：
  - 端口名称唯一性
  - relation 名称唯一性
  - 参数名称唯一性

ComposeDef 验证项：
  - 子实体名称唯一性
  - 递归验证所有嵌套 entity / compose
  - 连接引用实体存在性
  - 连接端口存在性
  - 连接方向兼容性
"""

"""
    validate(model) -> Vector{String}

兼容旧接口。内部复用 `validate_diagnostics(model)`，并将结构化诊断渲染为字符串。
"""
validate(model) = diagnostic_messages(validate_diagnostics(model))

function _find_duplicates(names)
    counts = Dict{Symbol, Int}()
    for name in names
        counts[name] = get(counts, name, 0) + 1
    end
    return sort!(Symbol[name for (name, count) in counts if count > 1]; by=string)
end

function _duplicate_name_diag(code::String, owner_kind::String, owner_name::Symbol,
                              field_kind_human::String, field_kind_machine::String,
                              duplicates::Vector{Symbol})
    dup_list = join([":" * string(name) for name in duplicates], ", ")
    human_summary = string(owner_kind, " :", owner_name, " — ", field_kind_human, "不唯一: ", dup_list)
    diagnosis = string("Duplicate ", field_kind_machine, " names were found in ",
                       lowercase(owner_kind), " ", owner_name, ".")
    return _make_diag(
        code;
        phase=PHASE_SEMANTIC_VALIDATION,
        human_message=string(field_kind_human, "不唯一"),
        human_summary=human_summary,
        entity=Dict("kind" => lowercase(owner_kind), "name" => string(owner_name)),
        constraint=string(lowercase(owner_kind), "_", field_kind_machine, "_names_unique"),
        expected="unique_names",
        actual="duplicate_names",
        context=Dict{String, Any}("duplicates" => [string(name) for name in duplicates]),
        repair_hints=[
            string("Rename duplicated ", field_kind_machine, " declarations so each name is unique."),
            "Keep the semantic intent unchanged while applying the smallest valid rename set.",
        ],
        ai_hint=_default_ai_hint(
            "Resolve duplicate declarations while preserving the original model structure.",
            diagnosis,
            [
                string("Identify all duplicated ", field_kind_machine, " declarations."),
                "Rename only the conflicting declarations.",
                "Preserve unrelated entities and references.",
            ];
            constraints=[
                "Do not rename unrelated symbols.",
                "Keep the patch minimal.",
            ],
            recheck=[
                "name_resolution",
                "semantic_validation",
            ],
        ),
        docs_ref=string("rules/naming/", field_kind_machine, "-unique"),
    )
end

function validate_diagnostics(model::EntityDef)
    diags = Diagnostic[]

    pdups = _find_duplicates([p.name for p in model.ports])
    isempty(pdups) || push!(diags, _duplicate_name_diag(
        E_NAME_DUPLICATE_PORT, "Entity", model.name, "端口名称", "port", pdups))

    rdups = _find_duplicates([r.name for r in model.relations])
    isempty(rdups) || push!(diags, _duplicate_name_diag(
        E_NAME_DUPLICATE_RELATION, "Entity", model.name, "关系名称", "relation", rdups))

    adups = _find_duplicates([p.name for p in model.parameters])
    isempty(adups) || push!(diags, _duplicate_name_diag(
        E_NAME_DUPLICATE_PARAMETER, "Entity", model.name, "参数名称", "parameter", adups))

    return diags
end

function validate_diagnostics(model::ComposeDef)
    diags = Diagnostic[]

    edups = _find_duplicates([e.name for e in model.entities])
    isempty(edups) || push!(diags, _duplicate_name_diag(
        E_NAME_DUPLICATE_ENTITY, "Compose", model.name, "子实体名称", "entity", edups))

    for e in model.entities
        append!(diags, validate_diagnostics(e))
    end
    for sc in model.subcomposes
        append!(diags, validate_diagnostics(sc))
    end

    isempty(model.connections) && return diags

    port_lookup = Dict{Symbol, Dict{Symbol, Port}}()
    for e in traverse_entities(model)
        port_lookup[e.name] = Dict(p.name => p for p in e.ports)
    end

    direction_ok(from_dir, to_dir) =
        from_dir == :inout || to_dir == :inout || from_dir != to_dir

    for conn in model.connections
        f_ent, f_port = conn.from
        t_ent, t_port = conn.to

        if !haskey(port_lookup, f_ent)
            push!(diags, _make_diag(
                E_TOPOLOGY_UNKNOWN_ENTITY;
                phase=PHASE_TOPOLOGY_VALIDATION,
                human_message="连接引用了不存在的实体",
                human_summary=string("Compose :", model.name, " — 源实体 :", f_ent, " 不存在"),
                entity=Dict(
                    "kind" => "connection",
                    "compose" => string(model.name),
                    "source_entity" => string(f_ent),
                    "target_entity" => string(t_ent),
                ),
                constraint="connection_entities_must_exist",
                expected="known_entity",
                actual=string(f_ent),
                context=Dict{String, Any}(
                    "connection" => string(f_ent, ".", f_port, " -> ", t_ent, ".", t_port),
                    "endpoint" => "source",
                ),
                repair_hints=[
                    "Use an existing entity name in the connection source endpoint.",
                    "If the entity should exist, declare it before creating the connection.",
                ],
                ai_hint=_default_ai_hint(
                    "Resolve the invalid connection reference without changing unrelated topology.",
                    string("The connection source entity ", f_ent, " does not exist in compose ", model.name, "."),
                    [
                        "Check for a spelling mismatch first.",
                        "If a nearby entity with the intended semantics exists, reconnect to it.",
                        "Only create a new entity if the surrounding model clearly requires one.",
                    ];
                    constraints=[
                        "Do not rename unrelated entities.",
                        "Keep the patch minimal.",
                    ],
                    recheck=[
                        "name_resolution",
                        "topology_validation",
                    ],
                ),
                docs_ref="rules/topology/connection-entities-exist",
            ))
            continue
        end

        if !haskey(port_lookup, t_ent)
            push!(diags, _make_diag(
                E_TOPOLOGY_UNKNOWN_ENTITY;
                phase=PHASE_TOPOLOGY_VALIDATION,
                human_message="连接引用了不存在的实体",
                human_summary=string("Compose :", model.name, " — 目标实体 :", t_ent, " 不存在"),
                entity=Dict(
                    "kind" => "connection",
                    "compose" => string(model.name),
                    "source_entity" => string(f_ent),
                    "target_entity" => string(t_ent),
                ),
                constraint="connection_entities_must_exist",
                expected="known_entity",
                actual=string(t_ent),
                context=Dict{String, Any}(
                    "connection" => string(f_ent, ".", f_port, " -> ", t_ent, ".", t_port),
                    "endpoint" => "target",
                ),
                repair_hints=[
                    "Use an existing entity name in the connection target endpoint.",
                    "If the entity should exist, declare it before creating the connection.",
                ],
                ai_hint=_default_ai_hint(
                    "Resolve the invalid connection reference without changing unrelated topology.",
                    string("The connection target entity ", t_ent, " does not exist in compose ", model.name, "."),
                    [
                        "Check for a spelling mismatch first.",
                        "If a nearby entity with the intended semantics exists, reconnect to it.",
                        "Only create a new entity if the surrounding model clearly requires one.",
                    ];
                    constraints=[
                        "Do not rename unrelated entities.",
                        "Keep the patch minimal.",
                    ],
                    recheck=[
                        "name_resolution",
                        "topology_validation",
                    ],
                ),
                docs_ref="rules/topology/connection-entities-exist",
            ))
            continue
        end

        f_port_def = get(port_lookup[f_ent], f_port, nothing)
        t_port_def = get(port_lookup[t_ent], t_port, nothing)

        if f_port_def === nothing
            push!(diags, _make_diag(
                E_PORT_INVALID_REFERENCE;
                phase=PHASE_TOPOLOGY_VALIDATION,
                human_message="连接引用了不存在的端口",
                human_summary=string("Compose :", model.name, " — 实体 :", f_ent, " 没有端口 :", f_port),
                entity=Dict(
                    "kind" => "connection",
                    "compose" => string(model.name),
                    "entity" => string(f_ent),
                    "port" => string(f_port),
                ),
                constraint="connection_ports_must_exist",
                expected="known_port",
                actual=string(f_port),
                context=Dict{String, Any}(
                    "endpoint" => "source",
                    "connection" => string(f_ent, ".", f_port, " -> ", t_ent, ".", t_port),
                ),
                repair_hints=[
                    "Reconnect using a declared source port.",
                    "If the port should exist, declare it on the source entity first.",
                ],
                ai_hint=_default_ai_hint(
                    "Fix the invalid port reference while preserving the intended connection semantics.",
                    string("The source port ", f_ent, ".", f_port, " does not exist."),
                    [
                        "Check for a spelling mismatch first.",
                        "If a semantically similar declared port exists, reconnect to it.",
                        "Only add a new port if the surrounding model clearly requires one.",
                    ];
                    constraints=[
                        "Do not modify unrelated ports.",
                        "Keep the patch minimal.",
                    ],
                    recheck=[
                        "name_resolution",
                        "topology_validation",
                    ],
                ),
                docs_ref="rules/ports/reference-valid",
            ))
        end

        if t_port_def === nothing
            push!(diags, _make_diag(
                E_PORT_INVALID_REFERENCE;
                phase=PHASE_TOPOLOGY_VALIDATION,
                human_message="连接引用了不存在的端口",
                human_summary=string("Compose :", model.name, " — 实体 :", t_ent, " 没有端口 :", t_port),
                entity=Dict(
                    "kind" => "connection",
                    "compose" => string(model.name),
                    "entity" => string(t_ent),
                    "port" => string(t_port),
                ),
                constraint="connection_ports_must_exist",
                expected="known_port",
                actual=string(t_port),
                context=Dict{String, Any}(
                    "endpoint" => "target",
                    "connection" => string(f_ent, ".", f_port, " -> ", t_ent, ".", t_port),
                ),
                repair_hints=[
                    "Reconnect using a declared target port.",
                    "If the port should exist, declare it on the target entity first.",
                ],
                ai_hint=_default_ai_hint(
                    "Fix the invalid port reference while preserving the intended connection semantics.",
                    string("The target port ", t_ent, ".", t_port, " does not exist."),
                    [
                        "Check for a spelling mismatch first.",
                        "If a semantically similar declared port exists, reconnect to it.",
                        "Only add a new port if the surrounding model clearly requires one.",
                    ];
                    constraints=[
                        "Do not modify unrelated ports.",
                        "Keep the patch minimal.",
                    ],
                    recheck=[
                        "name_resolution",
                        "topology_validation",
                    ],
                ),
                docs_ref="rules/ports/reference-valid",
            ))
        end

        if f_port_def !== nothing && t_port_def !== nothing &&
           !direction_ok(f_port_def.direction, t_port_def.direction)
            push!(diags, _make_diag(
                E_TOPOLOGY_INVALID_DIRECTION;
                phase=PHASE_TOPOLOGY_VALIDATION,
                human_message="端口方向不兼容",
                human_summary=string(
                    "Compose :", model.name, " — :", f_ent, ".", f_port, " (", f_port_def.direction,
                    ") ↔ :", t_ent, ".", t_port, " (", t_port_def.direction, ")"
                ),
                entity=Dict(
                    "kind" => "connection",
                    "compose" => string(model.name),
                    "source" => string(f_ent, ".", f_port),
                    "target" => string(t_ent, ".", t_port),
                ),
                constraint="connection_direction_compatible",
                expected="compatible_port_directions",
                actual=string(f_port_def.direction, "_to_", t_port_def.direction),
                context=Dict{String, Any}(
                    "from_direction" => string(f_port_def.direction),
                    "to_direction" => string(t_port_def.direction),
                ),
                repair_hints=[
                    "Connect an output-like port to an input-like port.",
                    "If bidirectional flow is intended, use an inout port explicitly.",
                ],
                ai_hint=_default_ai_hint(
                    "Fix the invalid connection direction while preserving the intended data flow.",
                    string(
                        "The connection uses incompatible directions: ",
                        f_ent, ".", f_port, " is ", f_port_def.direction,
                        " while ", t_ent, ".", t_port, " is ", t_port_def.direction, "."
                    ),
                    [
                        "Check whether the connection endpoints were reversed.",
                        "If the flow is intentional, reconnect to a compatible input or output port.",
                        "Use an explicit inout port only when bidirectional behavior is intended.",
                    ];
                    constraints=[
                        "Do not change unrelated connections.",
                        "Keep the patch local.",
                    ],
                    recheck=[
                        "topology_validation",
                        "semantic_validation",
                    ],
                ),
                docs_ref="rules/topology/connection-direction-compatible",
            ))
        end
    end

    return diags
end

# ============================================================
# 6. 模型展开（Flatten）
# ============================================================

"""
    flatten(model::ComposeDef) -> ComposeDef

递归展开 compose，将所有嵌套 entity 收集到同一层级，
并生成连接方程作为新的 Relation。
"""
function flatten(model::ComposeDef)
    all_entities = EntityDef[]
    all_relations = Relation[]
    _flatten_collect!(all_entities, all_relations, model)
    # 生成连接方程
    for conn in model.connections
        eq = :($(conn.from[1]).$(conn.from[2]) == $(conn.to[1]).$(conn.to[2]))
        push!(all_relations, Relation(
            Symbol("conn_", conn.from[1], "_", conn.from[2], "__", conn.to[1], "_", conn.to[2]),
            Equation, eq, [:connection, :equation]))
    end
    return ComposeDef(model.name, all_entities, ComposeDef[],
                      all_relations, Connection[], model.exports)
end

function _flatten_collect!(entities, relations, cd::ComposeDef)
    for e in cd.entities
        push!(entities, e)
        append!(relations, e.relations)
    end
    for sc in cd.subcomposes
        sub = flatten(sc)
        append!(entities, sub.entities)
        append!(relations, sub.relations)
    end
end

# ============================================================
# 7. 连接拓扑分析
# ============================================================

"""
    connection_graph(model::ComposeDef) -> Dict{Tuple{Symbol,Symbol}, Vector{Tuple{Symbol,Symbol}}}

返回连接拓扑的无向图。每个端口（entity_name, port_name）映射到
它直接相连的所有端口列表。

# 示例
    graph = connection_graph(circuit)
    graph[(:R, :p)]  # 返回与 R.p 相连的所有端口
"""
function connection_graph(model::ComposeDef)
    graph = Dict{Tuple{Symbol,Symbol}, Vector{Tuple{Symbol,Symbol}}}()
    for conn in traverse_connections(model)
        push!(get!(graph, conn.from, Tuple{Symbol,Symbol}[]), conn.to)
        push!(get!(graph, conn.to, Tuple{Symbol,Symbol}[]), conn.from)
    end
    return graph
end

"""
    entity_connections(model::ComposeDef, entity_name::Symbol) -> Vector{Connection}

返回指定 entity 涉及的所有连接。
"""
function entity_connections(model::ComposeDef, entity_name::Symbol)
    result = Connection[]
    for conn in traverse_connections(model)
        if conn.from[1] == entity_name || conn.to[1] == entity_name
            push!(result, conn)
        end
    end
    return result
end
