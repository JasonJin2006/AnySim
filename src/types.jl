# ============================================================
# Core 类型系统
# ============================================================

"""
    Port

表示 entity 上的一个端口。
包含名称、类型、方向（:in/:out/:inout）。
"""
struct Port
    name::Symbol
    ptype::Type
    direction::Symbol  # :in, :out, :inout
end

"""
    Parameter

entity 的配置参数。
包含名称、默认值、类型、可选单位/描述。
参数在仿真过程中不变，属于 entity 的固有配置。
"""
struct Parameter
    name::Symbol
    default::Any
    ptype::Type
    unit::Union{Nothing, String}
    description::String
end

Parameter(name::Symbol, default, ptype::Type) = Parameter(name, default, ptype, nothing, "")

"""
    RelationKind

表示 relation 的类型。
- Equation:   acausal 约束方程（物理建模、电路）
- Behavioral: 算法行为函数（DEVS 转移函数、状态机）
- Event:      when 触发的事件（DES 事件规则）
"""
@enum RelationKind begin
    Equation
    Behavioral
    Event
end

"""
    Relation

表示 entity 上的一条约束/行为关系。
包含名称、类型、表达式、标签、元数据。
"""
struct Relation
    name::Symbol
    kind::RelationKind  # Equation / Behavioral / Event
    expr::Any           # 方程表达式/行为代码块（推迟求值）
    tags::Vector{Symbol}
    metadata::Dict{Symbol, Any}

    Relation(name, kind, expr, tags) = new(name, kind, expr, tags, Dict{Symbol, Any}())
    Relation(name, kind, expr, tags, metadata) = new(name, kind, expr, tags, metadata)
end

# 便捷构造函数：向后兼容（默认 Equation）
Relation(name::Symbol, expr, tags) = Relation(name, Equation, expr, tags)

"""
    EntityDef

entity 的结构化表示。
包含名称、端口列表、内部关系列表、参数列表、元数据。
"""
struct EntityDef
    name::Symbol
    ports::Vector{Port}
    relations::Vector{Relation}
    parameters::Vector{Parameter}
    metadata::Dict{Symbol, Any}

    EntityDef(name, ports, relations, parameters) =
        new(name, ports, relations, parameters, Dict{Symbol, Any}())
    EntityDef(name, ports, relations, parameters, metadata) =
        new(name, ports, relations, parameters, metadata)
end

"""
    Connection

连接两个端口的映射关系。
"""
struct Connection
    from::Tuple{Symbol,Symbol}  # (entity_name, port_name)
    to::Tuple{Symbol,Symbol}
end

"""
    ComposeDef

compose 的结构化表示。
包含名称、内部实体列表、子 compose 列表、连接关系列表、导出端口列表、元数据。
"""
struct ComposeDef
    name::Symbol
    entities::Vector{EntityDef}
    subcomposes::Vector{ComposeDef}
    relations::Vector{Relation}
    connections::Vector{Connection}
    exports::Vector{Tuple{String,Symbol,Symbol}}  # (alias, entity, port)
    metadata::Dict{Symbol, Any}

    # 默认空 subcomposes，保持向后兼容
    ComposeDef(name, entities, relations, connections, exports) =
        new(name, entities, ComposeDef[], relations, connections, exports, Dict{Symbol, Any}())
    # 显式 subcomposes（支持嵌套 compose）
    ComposeDef(name, entities, subcomposes, relations, connections, exports) =
        new(name, entities, subcomposes, relations, connections, exports, Dict{Symbol, Any}())
    # 完整构造函数（含 metadata）
    ComposeDef(name, entities, subcomposes, relations, connections, exports, metadata) =
        new(name, entities, subcomposes, relations, connections, exports, metadata)
end
