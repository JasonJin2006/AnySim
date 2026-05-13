# ============================================================
# 宏注册表：扩展可注册自定义宏名
# ============================================================

const PORT_MACROS = Set{Symbol}([Symbol("@port")])
const RELATION_MACROS = Set{Symbol}([Symbol("@relation"), Symbol("@behavior")])
const PARAM_MACROS = Set{Symbol}([Symbol("@param")])

register_port_macro(m::Symbol) = push!(PORT_MACROS, m)
register_relation_macro(m::Symbol) = push!(RELATION_MACROS, m)
register_param_macro(m::Symbol) = push!(PARAM_MACROS, m)

# ============================================================
# 宏辅助函数
# ============================================================

function _lookup_type_binding(name::Symbol, base_module::Module)
    if isdefined(base_module, name)
        value = getfield(base_module, name)
        value isa Type && return value
    end
    if isdefined(Main, name)
        value = getfield(Main, name)
        value isa Type && return value
    end
    if isdefined(Base, name)
        value = getfield(Base, name)
        value isa Type && return value
    end
    if isdefined(Core, name)
        value = getfield(Core, name)
        value isa Type && return value
    end
    return nothing
end

function _resolve_type_expr(type_expr; base_module::Module=@__MODULE__)
    if type_expr isa Symbol
        resolved = _lookup_type_binding(type_expr, base_module)
        resolved !== nothing && return resolved
    elseif type_expr isa Expr && type_expr.head == :curly
        base_type = _resolve_type_expr(type_expr.args[1]; base_module=base_module)
        params = map(arg -> _resolve_type_expr(arg; base_module=base_module), type_expr.args[2:end])
        return base_type{params...}
    elseif type_expr isa Expr && type_expr.head == :. && length(type_expr.args) == 2
        parent = _resolve_type_expr(type_expr.args[1]; base_module=base_module)
        field = type_expr.args[2]
        field_name = field isa QuoteNode ? field.value : field
        if parent isa Module && field_name isa Symbol && isdefined(parent, field_name)
            resolved = getfield(parent, field_name)
            resolved isa Type && return resolved
        end
    elseif type_expr isa GlobalRef
        resolved = getfield(type_expr.mod, type_expr.name)
        resolved isa Type && return resolved
    end
    throw(ArgumentError("unsupported type expression: $(repr(type_expr))"))
end

"""
    make_port(expr) -> Port

解析端口定义表达式，返回 Port 实例。
"""
function make_port(expr)
    if expr isa Symbol
        return Port(expr, Any, :inout)
    elseif expr isa Expr && expr.head == :(::)
        local ptype
        try
            ptype = _resolve_type_expr(expr.args[2])
        catch err
            throw_diagnostic(
                E_SYNTAX_UNSUPPORTED_PORT;
                phase="parse",
                human_message="不支持的端口类型声明",
                human_summary="无法安全解析端口类型: $(expr.args[2])",
                entity=Dict("kind" => "macro", "name" => "@port"),
                constraint="port_type_must_be_static_type_reference",
                expected="type_symbol_or_qualified_type",
                actual=string(expr.args[2]),
                context=Dict{String, Any}("macro" => "@port", "expr" => string(expr), "error" => sprint(showerror, err)),
                repair_hints=[
                    "Use a plain type name such as `Float64`, `Int`, or `Vector{Float64}`.",
                    "Avoid function calls or computed expressions in type positions.",
                ],
                docs_ref="rules/dsl/port-syntax",
            )
        end
        return Port(expr.args[1], ptype, :inout)
    else
        throw_diagnostic(
            E_SYNTAX_UNSUPPORTED_PORT;
            phase="parse",
            human_message="不支持的 @port 语法",
            human_summary="无法解析端口定义: $expr",
            entity=Dict("kind" => "macro", "name" => "@port"),
            constraint="port_macro_syntax_supported",
            expected="symbol_or_typed_symbol",
            actual=string(expr),
            context=Dict{String, Any}("macro" => "@port", "expr" => string(expr)),
            repair_hints=[
                "Use `@port name` or `@port name::Type`.",
                "Avoid unsupported nested expressions in port declarations.",
            ],
            ai_hint=_default_ai_hint(
                "Rewrite the port declaration into supported AnySim DSL syntax.",
                "The @port macro accepts either a bare symbol or a typed symbol declaration.",
                [
                    "Check whether the declaration can be simplified to `name` or `name::Type`.",
                    "Remove unsupported wrapper expressions.",
                ];
                constraints=[
                    "Do not rewrite unrelated declarations.",
                    "Keep the patch minimal.",
                ],
                recheck=["parse"],
            ),
            docs_ref="rules/dsl/port-syntax",
        )
    end
end

"""
    make_param(expr) -> Parameter

解析参数定义表达式，返回 Parameter 实例。
支持:
  @param R             → Symbol, 类型 Any, 无默认值
  @param R::Real       → (::), 类型 Real, 无默认值
  @param R = 1000      → (=), 类型 Any, 默认值 1000
  @param R::Real = 1000  → (::) + (=), 类型 Real, 默认值 1000
"""
function make_param(expr)
    if expr isa Symbol
        return Parameter(expr, nothing, Any)
    elseif expr isa Expr && expr.head == :(::)
        # @param R::Real
        local ptype
        try
            ptype = _resolve_type_expr(expr.args[2])
        catch err
            throw_diagnostic(
                E_SYNTAX_UNSUPPORTED_PARAM;
                phase="parse",
                human_message="不支持的参数类型声明",
                human_summary="无法安全解析参数类型: $(expr.args[2])",
                entity=Dict("kind" => "macro", "name" => "@param"),
                constraint="param_type_must_be_static_type_reference",
                expected="type_symbol_or_qualified_type",
                actual=string(expr.args[2]),
                context=Dict{String, Any}("macro" => "@param", "expr" => string(expr), "error" => sprint(showerror, err)),
                repair_hints=[
                    "Use a plain type name such as `Float64`, `Int`, or `Vector{Float64}`.",
                    "Avoid function calls or computed expressions in type positions.",
                ],
                docs_ref="rules/dsl/param-syntax",
            )
        end
        return Parameter(expr.args[1], nothing, ptype)
    elseif expr isa Expr && expr.head == :(=)
        lhs = expr.args[1]
        value = expr.args[2]
        if lhs isa Symbol
            return Parameter(lhs, value, Any)
        elseif lhs isa Expr && lhs.head == :(::)
            # @param R::Real = 1000
            local ptype
            try
                ptype = _resolve_type_expr(lhs.args[2])
            catch err
                throw_diagnostic(
                    E_SYNTAX_UNSUPPORTED_PARAM;
                    phase="parse",
                    human_message="不支持的参数类型声明",
                    human_summary="无法安全解析参数类型: $(lhs.args[2])",
                    entity=Dict("kind" => "macro", "name" => "@param"),
                    constraint="param_type_must_be_static_type_reference",
                    expected="type_symbol_or_qualified_type",
                    actual=string(lhs.args[2]),
                    context=Dict{String, Any}("macro" => "@param", "expr" => string(expr), "error" => sprint(showerror, err)),
                    repair_hints=[
                        "Use a plain type name such as `Float64`, `Int`, or `Vector{Float64}`.",
                        "Avoid function calls or computed expressions in type positions.",
                    ],
                    docs_ref="rules/dsl/param-syntax",
                )
            end
            return Parameter(lhs.args[1], value, ptype)
        end
    end
    throw_diagnostic(
        E_SYNTAX_UNSUPPORTED_PARAM;
        phase="parse",
        human_message="不支持的 @param 语法",
        human_summary="无法解析参数定义: $expr",
        entity=Dict("kind" => "macro", "name" => "@param"),
        constraint="param_macro_syntax_supported",
        expected="symbol_or_typed_assignment",
        actual=string(expr),
        context=Dict{String, Any}("macro" => "@param", "expr" => string(expr)),
        repair_hints=[
            "Use `@param name`, `@param name::Type`, `@param name = value`, or `@param name::Type = value`.",
            "Avoid unsupported nested expressions in parameter declarations.",
        ],
        ai_hint=_default_ai_hint(
            "Rewrite the parameter declaration into supported AnySim DSL syntax.",
            "The @param macro accepts a bare symbol, a typed symbol, an assignment, or a typed assignment.",
            [
                "Normalize the declaration into one of the four supported forms.",
                "Preserve the intended parameter name, type, and default value.",
            ];
            constraints=[
                "Do not modify unrelated declarations.",
                "Keep the patch minimal.",
            ],
            recheck=["parse"],
        ),
        docs_ref="rules/dsl/param-syntax",
    )
end

"""
    _has_operator(expr, op_name::Symbol) -> Bool

递归检测表达式树中是否包含特定算子调用。
"""
function _has_operator(expr, op_name::Symbol)
    if expr isa Expr
        if expr.head == :call && length(expr.args) >= 1 && expr.args[1] == op_name
            return true
        end
        for arg in expr.args
            _has_operator(arg, op_name) && return true
        end
    end
    return false
end

"""
    extract_equation_expr(body_expr) -> Any

从 @relation 的 body 中提取方程表达式。
支持 @relation Name begin expr end 和 @relation Name = expr 两种形式。
"""
function extract_equation_expr(body_expr)
    if body_expr isa Expr && body_expr.head == :block
        # @relation Name begin ... end
        for item in body_expr.args
            if item isa Expr && item.head == :call
                return item
            end
        end
        # 如果 block 中没有直接表达式，可能只有一行
        for item in body_expr.args
            if item isa Expr && !(item.head in (:line, :block, :macrocall))
                return item
            end
        end
    end
    return nothing
end

"""
    _relation_name_to_sym(name) -> Symbol

从可能的 QuoteNode/Expr(:quote) 包裹中提取 Symbol。
"""
function _relation_name_to_sym(name)
    if name isa Symbol
        return name
    elseif isdefined(Base, :QuoteNode) && name isa QuoteNode
        return name.value
    elseif name isa Expr && name.head == :quote
        return name.args[1]
    else
        return Symbol(name)
    end
end

"""
    make_relation(stmt_args) -> Relation

解析 relation 定义，返回 Relation 实例。
支持 @relation Name begin expr end 和 @relation Name = expr 形式。
自动检测 der/∫ 算子并标注标签。
"""
function make_relation(stmt_args)
    # === 检测是否有明确的 RelationKind 指定 ===
    # 支持语法: @relation Behavioral move begin ... end
    #           @relation Event on_collision = begin ... end
    #           @relation OhmLaw begin ... end  (默认 Equation)
    kind = Equation
    tags = Symbol[:equation]
    offset = 0  # stmt_args 偏移量

    if length(stmt_args) >= 1 && stmt_args[1] isa Symbol
        first_sym = stmt_args[1]
        if first_sym == :Behavioral
            kind = Behavioral
            tags = Symbol[:behavioral]
            offset = 1
        elseif first_sym == :Event
            kind = Event
            tags = Symbol[:event]
            offset = 1
        elseif first_sym == :Equation
            kind = Equation
            tags = Symbol[:equation]
            offset = 1
        end
    end

    # === 解析名称和表达式 ===
    remaining = stmt_args[1+offset:end]
    isempty(remaining) && throw_diagnostic(
        E_SYNTAX_MISSING_RELATION_NAME;
        phase="parse",
        human_message="@relation 缺少名称",
        human_summary="@relation 至少需要一个名称参数",
        entity=Dict("kind" => "macro", "name" => "@relation"),
        constraint="relation_macro_requires_name",
        expected="relation_name",
        actual="missing_argument",
        context=Dict{String, Any}("macro" => "@relation"),
        repair_hints=[
            "Provide a relation name as the first argument.",
            "Keep the existing body and only add the missing name.",
        ],
        ai_hint=_default_ai_hint(
            "Add the missing relation name without changing the relation body semantics.",
            "The @relation macro requires a relation name as its first argument.",
            [
                "Insert a valid symbolic relation name as the first argument.",
                "Preserve the existing body structure.",
            ];
            constraints=[
                "Do not rewrite unrelated relation bodies.",
                "Keep the patch minimal.",
            ],
            recheck=["parse"],
        ),
        docs_ref="rules/dsl/relation-syntax",
    )

    name = remaining[1]
    name_sym = _relation_name_to_sym(name)
    expr = nothing

    # === 检测显式状态变量声明（@behavior 生成的内部语法） ===
    # @relation Behavioral :name [var1, var2] begin ... end
    state_vars = Symbol[]
    body_start = 2
    if kind in (Behavioral, Event) && length(remaining) >= 3
        second = remaining[2]
        if second isa Expr && second.head == :vect
            for arg in second.args
                if arg isa Symbol
                    push!(state_vars, arg)
                end
            end
            body_start = 3
        end
    end

    if length(remaining) >= body_start
        body = remaining[body_start]
        if body isa Expr && body.head == :block
            if kind == Equation
                expr = extract_equation_expr(body)
            else
                # Behavioral/Event: 整个 block 就是行为代码
                expr = body
            end
        elseif body isa Expr && body.head == :macrocall
            expr = body
        end
    elseif length(remaining) == 1
        arg = remaining[1]
        if arg isa Expr && arg.head == :(=)
            name_sym = arg.args[1] isa Symbol ? arg.args[1] : Symbol(arg.args[1])
            expr = arg.args[2]
        end
    end

    # === 构建 metadata（含显式状态变量） ===
    metadata = Dict{Symbol, Any}()
    if !isempty(state_vars)
        metadata[:state_vars] = state_vars
    end

    # === 自动算子检测与标签标注（仅 Equation 类型） ===
    if kind == Equation && expr !== nothing
        if _has_operator(expr, :der)
            push!(tags, Symbol("∂ₜ"))
        end
        if _has_operator(expr, :integral) || _has_operator(expr, Symbol("∫"))
            push!(tags, Symbol("∫ₜ"))
        end
    end

    return Relation(name_sym, kind, expr, tags, metadata)
end

"""
    make_entity(name, body) -> EntityDef

解析 entity 定义，直接返回 EntityDef 实例。
在宏展开时求值，绕开嵌套宏展开限制。
"""
function make_entity(name, body)
    ports = Port[]
    relations = Relation[]
    params = Parameter[]

    if body isa Expr && body.head == :block
        for stmt in body.args
            if stmt isa Expr && stmt.head == :macrocall
                macro_name = stmt.args[1]
                # macro_name 可能是 Symbol("@port") 或 GlobalRef(AnySim, :@port)
                mn = macro_name isa Symbol ? macro_name :
                     (macro_name isa GlobalRef ? Symbol("@", macro_name.name) : nothing)
                if mn !== nothing && mn in PORT_MACROS
                    # stmt.args[2] = LineNumberNode, stmt.args[3] = 实际参数
                    port_expr = stmt.args[3]
                    push!(ports, make_port(port_expr))
                elseif mn !== nothing && mn in PARAM_MACROS
                    param_expr = stmt.args[3]
                    push!(params, make_param(param_expr))
                elseif mn !== nothing && mn in RELATION_MACROS
                    push!(relations, make_relation(stmt.args[3:end]))
                end
            end
        end
    end

    return EntityDef(name, ports, relations, params)
end

# ============================================================
# 宏定义：Core 语法 DSL
# ============================================================

"""
    @entity Name begin
        @port x::Type
        @relation ... begin ... end
    end

定义一个 entity。展开时直接调用 make_entity 求值。

支持两种形式：
  @entity Name begin ... end    # 内联定义
  @entity Name = expr           # 使用预构造的 EntityDef（适用于 compose 内部）
"""
macro entity(expr)
    # 处理 @entity Name = EntityDef(...) 的赋值形式
    if expr isa Expr && expr.head == :(=)
        name = expr.args[1]
        value = expr.args[2]
        return :($(esc(name)) = $value)
    end
    throw_diagnostic(
        E_SYNTAX_UNSUPPORTED_ENTITY;
        phase="parse",
        human_message="不支持的 @entity 语法",
        human_summary="无法解析实体声明: $expr",
        entity=Dict("kind" => "macro", "name" => "@entity"),
        constraint="entity_macro_syntax_supported",
        expected="assignment_or_two_argument_form",
        actual=string(expr),
        context=Dict{String, Any}("macro" => "@entity", "expr" => string(expr)),
        repair_hints=[
            "Use `@entity Name = value` or `@entity Name begin ... end`.",
            "Avoid unsupported single-argument entity syntax.",
        ],
        ai_hint=_default_ai_hint(
            "Rewrite the entity declaration into supported AnySim DSL syntax.",
            "The @entity macro accepts either an assignment form or a two-argument block form.",
            [
                "Check whether the entity should be declared with a block body or assigned from a prebuilt EntityDef.",
                "Preserve the intended entity name and body.",
            ];
            constraints=[
                "Do not alter unrelated entities.",
                "Keep the patch minimal.",
            ],
            recheck=["parse"],
        ),
        docs_ref="rules/dsl/entity-syntax",
    )
end

macro entity(name, body)
    ed = make_entity(name, body)
    return :($(esc(name)) = $ed)
end

"""
    @compose Name begin
        @entity X = EntityDef(...)
        @relation ... begin ... end
        @expose alias = entity.port
    end

将 entity + relation 组合成一个复合模型。
"""
macro compose(name, body)
    entity_stmts = Expr[]
    entity_refs = Expr[]
    relations = Relation[]
    connections = Connection[]
    export_tuples = Expr[]

    if body isa Expr && body.head == :block
        for stmt in body.args
            if stmt isa Expr && stmt.head == :macrocall
                macroname = stmt.args[1]
                macro_name = macroname isa GlobalRef ? macroname.name : macroname
                if macro_name == Symbol("@entity")
                    assign_expr = stmt.args[3]
                    if assign_expr isa Expr && assign_expr.head == :(=)
                        # @entity R1 = EntityDef(...) 形式 → 运行时赋值 + 引用
                        ent_name = assign_expr.args[1]
                        rhs = assign_expr.args[2]
                        push!(entity_stmts, :($(esc(ent_name)) = $rhs))
                        push!(entity_refs, esc(ent_name))
                    else
                        # @entity Wolf 形式 → 引用已定义的 entity
                        push!(entity_refs, esc(assign_expr))
                    end
                elseif macro_name == Symbol("@relation")
                    push!(relations, make_relation(stmt.args[3:end]))
                elseif macro_name == Symbol("@expose")
                    export_stmt = stmt.args[3]
                    if export_stmt isa Expr && export_stmt.head == :(=)
                        alias = string(export_stmt.args[1])
                        path = export_stmt.args[2]
                        ent_sym = path.args[1]
                        port_raw = path.args[2]
                        port_sym = port_raw isa QuoteNode ? port_raw.value : port_raw
                        push!(export_tuples, Expr(:tuple, alias, Expr(:quote, ent_sym), Expr(:quote, port_sym)))
                    end
                elseif macro_name == Symbol("@connect")
                    connect_args = stmt.args[3]
                    if connect_args isa Expr && connect_args.head == :tuple
                        from_expr = connect_args.args[1]
                        to_expr = connect_args.args[2]
                        # 提取 entity.port → (entity_sym, port_sym)
                        function _extract_ep(ex)
                            if ex isa Expr && ex.head == :(.)
                                ent = ex.args[1]
                                prt = ex.args[2]
                                return (ent, prt isa QuoteNode ? prt.value : prt)
                            end
                            throw_diagnostic(
                                E_SYNTAX_UNSUPPORTED_CONNECT;
                                phase="parse",
                                human_message="不支持的 @connect 语法",
                                human_summary="无法解析连接端点: $ex",
                                entity=Dict("kind" => "macro", "name" => "@connect"),
                                constraint="connect_macro_endpoint_supported",
                                expected="entity_dot_port",
                                actual=string(ex),
                                context=Dict{String, Any}("macro" => "@connect", "expr" => string(ex)),
                                repair_hints=[
                                    "Use `@connect entity1.port1, entity2.port2`.",
                                    "Ensure both endpoints use the `entity.port` form.",
                                ],
                                ai_hint=_default_ai_hint(
                                    "Rewrite the connection endpoint into supported AnySim DSL syntax.",
                                    "Each @connect endpoint must use the `entity.port` form.",
                                    [
                                        "Convert both endpoints to `entity.port` references.",
                                        "Preserve the intended source and target entities if possible.",
                                    ];
                                    constraints=[
                                        "Do not change unrelated connections.",
                                        "Keep the patch minimal.",
                                    ],
                                    recheck=["parse", "topology_validation"],
                                ),
                                docs_ref="rules/dsl/connect-syntax",
                            )
                        end
                        from = _extract_ep(from_expr)
                        to = _extract_ep(to_expr)
                        push!(connections, Connection(from, to))
                    end
                end
            end
        end
    end

    return quote
        $(entity_stmts...)
        ComposeDef(
            $(QuoteNode(name)),
            [$(entity_refs...)],
            $relations,
            $connections,
            [$(export_tuples...)]
        )
    end
end

"""
    @expose alias = entity.port

在 compose 中暴露内部端口作为外部接口。
"""
macro expose(expr)
    return expr
end

"""
    @connect entity1.port1, entity2.port2

在 compose 中声明两个端口的连接。
连接关系被存储为 Connection(from=(:entity1, :port1), to=(:entity2, :port2))。
"""
macro connect(expr)
    return expr
end

"""
    @param [name]::[type] = [default]

在 @entity 内部定义参数。
支持:
  @param R
  @param R::Real
  @param R = 1000
  @param R::Real = 1000
"""
macro param(expr)
    return expr
end

"""
    @relation [name] = [expr]
    @relation [name] begin [expr] end

在 @entity 内部定义方程关系。
方程表达式会被存储并自动检测算子（der、∫）。
"""
macro relation(args...)
    return nothing
end

"""
    @behavior :name [state_var1, state_var2] begin
        # 正常 Julia 代码
    end

定义行为代码，必须显式声明要修改的状态变量列表。
与 @relation Behavioral 等效，但通过显式声明消除 AST 猜测。

状态变量列表中的变量会被自动解包和回写。
行为代码中写的所有 Julia 代码都是正常的（无需 quote！）。
"""
macro behavior(args...)
    return nothing
end
