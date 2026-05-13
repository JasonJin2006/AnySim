# ============================================================
# DAE2ODESolver — 线性 Acausal → ODE 变换求解器
#
# 将 entity 行为方程 + 连接拓扑 → 扁平的显式 ODE。
#
# 管線（全部在 flat symbol 空间中操作）：
#   1. 抽取 entity 方程，把 port.field 拍平为 ent_port_field
#   2. 自动生成内部 KCL（多端口实体的 I 之和 = 0）
#   3. 按节点生成连接方程（across .V 相等 + KCL .I 之和 = 0）
#   4. 符号消元消除代数变量
#   5. 编译为 ODE 并用 ODESolver 求解
# ============================================================

struct DAE2ODESolver <: AbstractSolver
    dt::Float64
    reltol::Float64
end
DAE2ODESolver(; dt=1e-3, reltol=1e-6) = DAE2ODESolver(dt, reltol)

function can_solve(::DAE2ODESolver, model::ComposeDef)
    classify_model(model) == :static && return false
    return true
end
can_solve(::DAE2ODESolver, ::EntityDef) = false

# ============================================================
# 1. Port → Field 发现
#
# 扫描 entity 方程中的所有 port.field 模式，
# 构建 (ent, port, field) → flat symbol 映射。
# ============================================================

"""
    _scan_port_field_accesses(expr, port_names) -> Set{Tuple{Symbol,Symbol}}

从表达式树中收集所有 `port.field` 访问对。
port_names 是该 entity 的有效端口名集合。
"""
function _scan_port_field_accesses(expr, port_names::Set{Symbol})
    accesses = Set{Tuple{Symbol,Symbol}}()
    _scan!(accesses, expr, port_names)
    return accesses
end

function _scan!(accesses, ex, port_names)
    if ex isa Expr && ex.head == :(.)
        if length(ex.args) >= 2
            obj = ex.args[1]
            fld = ex.args[2]
            if obj isa Symbol && obj in port_names
                fld_sym = fld isa QuoteNode ? fld.value : fld
                fld_sym isa Symbol && push!(accesses, (obj, fld_sym))
            end
        end
        for arg in ex.args
            _scan!(accesses, arg, port_names)
        end
    elseif ex isa Expr
        for arg in ex.args
            _scan!(accesses, arg, port_names)
        end
    end
end

"""
    _make_flat_name(ent::Symbol, port::Symbol, field::Symbol) -> Symbol

生成扁平符号：`ent_port_field`。
"""
_make_flat_name(ent, port, field) = Symbol(string(ent, "_", port, "_", field))

"""
    _field_to_flat(ex, ent_name, port_names) -> (expr, mapping)

将表达式中的所有 `port.field` 替换为扁平符号 `ent_port_field`。
返回 (替换后的表达式, Dict{port_field => flat_symbol})。
"""
function _field_to_flat(ex, ent_name::Symbol, port_names::Set{Symbol})
    mapping = Dict{Tuple{Symbol,Symbol}, Symbol}()
    result = _replace_pf(ex, ent_name, port_names, mapping)
    return result, mapping
end

function _replace_pf(ex, ent_name, port_names, mapping)
    if ex isa Expr && ex.head == :(.) && length(ex.args) >= 2
        obj = ex.args[1]
        fld = ex.args[2]
        if obj isa Symbol && obj in port_names
            fld_sym = fld isa QuoteNode ? fld.value : fld
            flat = _make_flat_name(ent_name, obj, fld_sym)
            mapping[(obj, fld_sym)] = flat
            return flat
        end
        # 递归处理 obj（可能是嵌套访问）
        new_obj = _replace_pf(obj, ent_name, port_names, mapping)
        new_fld = _replace_pf(fld, ent_name, port_names, mapping)
        return Expr(:., new_obj, new_fld isa Symbol ? QuoteNode(new_fld) : new_fld)
    elseif ex isa Expr
        return Expr(ex.head, [_replace_pf(a, ent_name, port_names, mapping) for a in ex.args]...)
    else
        return ex
    end
end

# ============================================================
# 2. 内部 KCL 生成
#
# 对多端口实体自动生成 sum(ent_port_I) == 0。
# ============================================================

"""
    _make_internal_kcl(ent_name, ports, all_fields) -> Union{Nothing, Expr}

对多端口实体生成内部 KCL：ent_port1_I + ent_port2_I + ... == 0。
1 端口实体跳过（单端口没有内部 KCL）。
"""
function _make_internal_kcl(ent_name, ports, all_fields)
    length(ports) <= 1 && return nothing
    # 收集所有端口的 .I field flat symbol
    i_terms = Symbol[]
    for p in ports
        pname = p.name
        # 检查该端口是否有 .I 场
        if haskey(all_fields, (pname, :I))
            push!(i_terms, all_fields[(pname, :I)])
        end
    end
    isempty(i_terms) && return nothing
    # 生成 expr == 0
    if length(i_terms) == 1
        return :($(i_terms[1]) == 0)
    end
    sum_expr = Expr(:call, :+, i_terms...)
    return :($sum_expr == 0)
end

# ============================================================
# 3. 连接拓扑 → 节点
#
# 将 Connection 列表转为无向图，找出连通分量（节点）。
# ============================================================

"""
    _find_nodes(connections) -> Vector{Vector{Tuple{Symbol,Symbol}}}

将 connection 列表转为连通分量（节点）。
每个节点是一个端口列表 [(ent, port), ...]。
"""
function _find_nodes(connections)
    # 构建邻接表
    adj = Dict{Tuple{Symbol,Symbol}, Vector{Tuple{Symbol,Symbol}}}()
    for conn in connections
        push!(get!(adj, conn.from, Tuple{Symbol,Symbol}[]), conn.to)
        push!(get!(adj, conn.to, Tuple{Symbol,Symbol}[]), conn.from)
    end
    # BFS 找连通分量
    visited = Set{Tuple{Symbol,Symbol}}()
    nodes = Vector{Tuple{Symbol,Symbol}}[]
    for start in keys(adj)
        start in visited && continue
        # BFS
        component = Tuple{Symbol,Symbol}[]
        queue = [start]
        while !isempty(queue)
            v = popfirst!(queue)
            v in visited && continue
            push!(visited, v)
            push!(component, v)
            for nb in get(adj, v, Tuple{Symbol,Symbol}[])
                nb in visited && continue
                push!(queue, nb)
            end
        end
        push!(nodes, component)
    end
    return nodes
end

# ============================================================
# 4. 连接方程生成
#
# 对每个节点生成：
#   - across（.V）相等：ent1_port1_V == ent2_port2_V
#   - through（.I）KCL：sum(ent_port_I) == 0
# ============================================================

"""
    _generate_node_eqs(nodes, all_fields) -> Vector{Expr}

对每个节点生成连接方程。
all_fields: Dict{(port, field), flat_symbol} 包含所有已知 field mapping。
"""
function _generate_node_eqs(nodes, all_fields)
    eqs = Expr[]
    for node in nodes
        # Across（.V）方程：第一个端口的 V 与其余端口的 V 相等
        v_ports = [(ent, port) for (ent, port) in node
                   if haskey(all_fields, (port, :V))]
        for i in 2:length(v_ports)
            v1 = all_fields[(v_ports[1][2], :V)]
            v2 = all_fields[(v_ports[i][2], :V)]
            flat1 = _make_flat_name(v_ports[1][1], v_ports[1][2], :V)
            flat2 = _make_flat_name(v_ports[i][1], v_ports[i][2], :V)
            push!(eqs, :($flat1 == $flat2))
        end

        # Through（.I）KCL 方程：sum(port_I) == 0
        i_terms = Symbol[]
        for (ent, port) in node
            if haskey(all_fields, (port, :I))
                push!(i_terms, _make_flat_name(ent, port, :I))
            end
        end
        if length(i_terms) >= 2
            sum_expr = length(i_terms) == 2 ? Expr(:call, :+, i_terms[1], i_terms[2]) :
                                              Expr(:call, :+, i_terms...)
            push!(eqs, :($sum_expr == 0))
        end
    end
    return eqs
end

# ============================================================
# 5. 变量分类：状态变量 vs 代数变量
# ============================================================

"""
    _find_state_vars(eqs) -> Set{Symbol}

找到所有出现在 `der(...)` 中的变量（状态变量）。
在 flat symbol 空间中，状态是简单 Symbol。
"""
function _find_state_vars(eqs)
    states = Set{Symbol}()
    for eq in eqs
        _collect_states!(states, eq)
    end
    return states
end

function _collect_states!(states, ex)
    if ex isa Expr && ex.head == :call && length(ex.args) >= 2 && ex.args[1] == :der
        inner = ex.args[2]
        if inner isa Symbol
            push!(states, inner)
        elseif inner isa Expr
            # der(expr) → expr 中所有 Symbol 都是状态的一部分
            _collect_syms_in_expr!(states, inner)
        end
    elseif ex isa Expr
        for arg in ex.args
            _collect_states!(states, arg)
        end
    end
end

function _collect_syms_in_expr!(syms, ex)
    if ex isa Symbol
        if !(ex in _BUILTIN_FUNS)
            push!(syms, ex)
        end
    elseif ex isa Expr
        for arg in ex.args
            _collect_syms_in_expr!(syms, arg)
        end
    end
end

"""
    _find_all_vars(eqs) -> Set{Symbol}

从一组方程中提取所有符号变量（排除内建函数和 der）。
"""
function _find_all_vars(eqs)
    vars = Set{Symbol}()
    for eq in eqs
        _collect_plain_vars!(vars, eq)
    end
    return setdiff(vars, _BUILTIN_FUNS)
end

function _collect_plain_vars!(vars, ex)
    if ex isa Symbol
        push!(vars, ex)
    elseif ex isa Expr
        if !(ex.head == :call && length(ex.args) >= 1 && ex.args[1] == :der)
            for arg in ex.args
                _collect_plain_vars!(vars, arg)
            end
        end
    end
end

# ============================================================
# 6. 符号消元
#
# 对每个代数变量，寻找定义方程 var == rhs，
# 代入到状态变量的 der() 方程中。
# ============================================================

"""
    _find_algebraic_defs(eqs, algebraic_vars) -> Dict{Symbol, Expr}

寻找代数变量的定义方程（形如 var == expr，var 单独在等式一侧）。
返回 {var => definition_expr} 映射。
"""
function _find_algebraic_defs(eqs, algebraic_vars)
    defs = Dict{Symbol, Any}()  # var => defining expr (the RHS of var == rhs)
    av_set = Set(algebraic_vars)
    for eq in eqs
        if eq isa Expr && eq.head == :call && length(eq.args) >= 3 && eq.args[1] == :(==)
            lhs = eq.args[2]
            rhs = eq.args[3]
            if lhs isa Symbol && lhs in av_set && !_contains_der_in_expr(rhs)
                defs[lhs] = rhs
            elseif rhs isa Symbol && rhs in av_set && !_contains_der_in_expr(lhs)
                defs[rhs] = lhs
            end
        end
    end
    return defs
end

function _contains_der_in_expr(ex)
    if ex isa Expr && ex.head == :call && length(ex.args) >= 1 && ex.args[1] == :der
        return true
    elseif ex isa Expr
        return any(_contains_der_in_expr, ex.args)
    end
    return false
end

"""
    _substitute_var(expr, var::Symbol, replacement, var_set) -> Expr

在表达式树中替换所有 var 为 replacement。
var_set 是当前正在处理的变量链，用于检测循环引用。
"""
function _substitute_var(ex, var::Symbol, replacement, var_set=Set{Symbol}())
    # 检测循环引用
    var in var_set && return ex
    new_set = copy(var_set)
    push!(new_set, var)

    if ex isa Symbol
        return ex == var ? replacement : ex
    elseif ex isa Expr
        return Expr(ex.head, [_substitute_var(a, var, replacement, new_set) for a in ex.args]...)
    else
        return ex
    end
end

"""
    _replace_der_expr(expr, target, replacement) -> Expr

在所有 `der(target)` 表达式中将 `target` 替换为 `replacement`。
仅在 der() 内部替换。
"""
function _replace_der_expr(ex, target, replacement)
    if ex isa Expr && ex.head == :call && length(ex.args) >= 2 && ex.args[1] == :der
        inner = ex.args[2]
        if inner == target
            return Expr(:call, :der, replacement)
        end
        return ex
    elseif ex isa Expr
        return Expr(ex.head, [_replace_der_expr(a, target, replacement) for a in ex.args]...)
    else
        return ex
    end
end

"""
    _extract_ode_from_equation(eq, state_set, defs)

从方程中提取 der(state) == rhs 形式。
处理两种情况：
  - der(x) == rhs                  → rhs
  - expr_with_der == other_expr    → 移项求解 der(x)
返回 nothing 如果方程不含 der。
"""
function _extract_ode_from_equation(eq, state_set, defs)
    if !(eq isa Expr && eq.head == :call && length(eq.args) >= 3 && eq.args[1] == :(==))
        return nothing
    end
    lhs = eq.args[2]
    rhs_side = eq.args[3]

    # 情况 1：der(x) == rhs (x 可能是单符号或表达式)
    if lhs isa Expr && lhs.head == :call && length(lhs.args) >= 2 && lhs.args[1] == :der
        inner = lhs.args[2]
        rhs_clean = defs !== nothing ? _apply_defs(rhs_side, defs) : rhs_side
        return (inner, rhs_clean)
    end

    # 情况 2：rhs == der(x)
    if rhs_side isa Expr && rhs_side.head == :call && length(rhs_side.args) >= 2 && rhs_side.args[1] == :der
        inner = rhs_side.args[2]
        lhs_clean = defs !== nothing ? _apply_defs(lhs, defs) : lhs
        return (inner, lhs_clean)
    end

    # 情况 3：lhs 或 rhs 包含 der 但不等于 der
    # 例如：x == C * der(y) → der(y) == x / C
    lhs_has_der = _contains_der_in_expr(lhs)
    rhs_has_der = _contains_der_in_expr(rhs_side)

    if lhs_has_der
        return _isolate_der_from(lhs, rhs_side, state_set, defs)
    elseif rhs_has_der
        return _isolate_der_from(rhs_side, lhs, state_set, defs)
    end

    return nothing
end

"""
    _isolate_der_from(der_side, other_side, state_set, defs)

从包含 der() 的一侧提取 der(x) == ... 形式。
处理系数提取：C * der(y) → der(y) == other_side / C
"""
function _isolate_der_from(der_side, other_side, state_set, defs)
    # der(x) == other_side
    if der_side isa Expr && der_side.head == :call && length(der_side.args) >= 2 && der_side.args[1] == :der
        inner = der_side.args[2]
        rhs_clean = defs !== nothing ? _apply_defs(other_side, defs) : other_side
        return (inner, rhs_clean)
    end

    # C * der(x) 或 der(x) * C
    if der_side isa Expr && der_side.head == :call && der_side.args[1] == :*
        der_pos = findfirst(a -> a isa Expr && a.head == :call && length(a.args) >= 1 && a.args[1] == :der,
                            der_side.args)
        if der_pos !== nothing
            der_expr = der_side.args[der_pos]
            inner = der_expr.args[2]
            # 收集系数
            coeffs = Any[der_side.args[i] for i in 2:length(der_side.args) if i != der_pos]
            if isempty(coeffs)
                rhs_clean = defs !== nothing ? _apply_defs(other_side, defs) : other_side
                return (inner, rhs_clean)
            end
            coeff = length(coeffs) == 1 ? coeffs[1] : Expr(:call, :*, coeffs...)
            rhs_clean = defs !== nothing ? _apply_defs(other_side, defs) : other_side
            return (inner, :($rhs_clean / $coeff))
        end
    end

    # 复杂情况：der 在复合表达式中，对整个表达式移项
    # 将包含 der 的方程视为整体移项，应用代数定义
    if defs !== nothing
        rhs_clean = _apply_defs(other_side, defs)
        return (der_side, rhs_clean)
    end

    return nothing  # 无法处理
end

"""
    _process_sum_equation!(defs, sum_args, undefined) -> Bool

处理 sum == 0 方程。为第一个未定义的代数变量生成定义。
返回 true 如果生成了新定义。
"""
function _process_sum_equation!(defs, sum_args, undefined)
    for (i, term) in enumerate(sum_args)
        term isa Symbol || continue
        term in undefined || continue
        other_terms = Any[sum_args[j] for j in 1:length(sum_args) if j != i]
        if isempty(other_terms)
            defs[term] = 0
        elseif length(other_terms) == 1
            defs[term] = Expr(:call, :-, other_terms[1])
        else
            defs[term] = Expr(:call, :-, Expr(:call, :+, other_terms...))
        end
        return true
    end
    return false
end

"""
    _apply_defs(expr, defs) -> Expr

在 expr 中递归应用代数变量定义替换（带循环引用保护）。
"""
function _apply_defs(expr, defs)
    result = expr
    for (var, def) in defs
        result = _substitute_var(result, var, def, Set([var]))
    end
    return result
end

# ============================================================
# 7. 主求解方法
# ============================================================

function solve(solver::DAE2ODESolver, model::ComposeDef;
               u0=Dict{Symbol,Float64}(), tspan=(0.0, 10.0),
               params=Dict{Symbol,Any}())

    # ---- Phase 1: Flatten ----
    flat = flatten(model)

    # ---- Phase 2: 方程生成（flat symbol 空间） ----
    all_eqs = Expr[]           # flat symbol 方程
    all_params = Parameter[]

    for e in flat.entities
        port_names = Set{Symbol}(p.name for p in e.ports)
        append!(all_params, e.parameters)

        # 扫描端口 field 访问
        all_fields = Dict{Tuple{Symbol,Symbol}, Symbol}()  # (port, field) => flat_symbol
        for r in e.relations
            r.expr === nothing && continue
            accesses = _scan_port_field_accesses(r.expr, port_names)
            for (port, field) in accesses
                all_fields[(port, field)] = _make_flat_name(e.name, port, field)
            end
        end

        # 替换 entity 方程为 flat symbols
        for r in e.relations
            r.expr === nothing && continue
            flat_expr, _ = _field_to_flat(r.expr, e.name, port_names)
            push!(all_eqs, flat_expr)
        end

        # 补齐：如果端口有任意 field 被使用，自动注册 .V 和 .I 两者
        # （因为电气端口总是有电压和电流两个量）
        used_port_names = Set{Symbol}(k[1] for k in keys(all_fields))
        for pname in used_port_names
            if !haskey(all_fields, (pname, :V))
                all_fields[(pname, :V)] = _make_flat_name(e.name, pname, :V)
            end
            if !haskey(all_fields, (pname, :I))
                all_fields[(pname, :I)] = _make_flat_name(e.name, pname, :I)
            end
        end

        # 内部 KCL
        kcl = _make_internal_kcl(e.name, e.ports, all_fields)
        kcl !== nothing && push!(all_eqs, kcl)
    end

    # ---- Phase 3: 连接方程 ----
    nodes = _find_nodes(flat.connections)

    # 收集所有 field mapping（用 entity relation 扫到的 mapping + 从全局 fields 推断）
    # 重建全局 all_fields
    global_fields = Dict{Tuple{Symbol,Symbol,Symbol}, Symbol}()  # (ent, port, field) => flat_symbol
    for e in flat.entities
        port_names = Set{Symbol}(p.name for p in e.ports)
        for r in e.relations
            r.expr === nothing && continue
            accesses = _scan_port_field_accesses(r.expr, port_names)
            for (port, field) in accesses
                flat = _make_flat_name(e.name, port, field)
                global_fields[(e.name, port, field)] = flat
            end
        end
        # 补齐：对使用了 field 的端口，注册 .V 和 .I
        used_port_names2 = Set{Symbol}(k[2] for k in keys(global_fields) if k[1] == e.name)
        for pname in used_port_names2
            if !haskey(global_fields, (e.name, pname, :V))
                global_fields[(e.name, pname, :V)] = _make_flat_name(e.name, pname, :V)
            end
            if !haskey(global_fields, (e.name, pname, :I))
                global_fields[(e.name, pname, :I)] = _make_flat_name(e.name, pname, :I)
            end
        end
    end

    # 按节点生成连接方程
    for node in nodes
        # 对 node 中的每个 (ent, port)，用 global_fields 取 flat symbol
        # Across .V equality
        v_terms = Tuple{Symbol,Symbol,Symbol,Symbol}[]  # (ent, port, flat_symbol, field)
        for (ent, port) in node
            key = (ent, port, :V)
            if haskey(global_fields, key)
                push!(v_terms, (ent, port, global_fields[key], :V))
            end
        end
        for i in 2:length(v_terms)
            push!(all_eqs, :($(v_terms[1][3]) == $(v_terms[i][3])))
        end

        # Through .I KCL
        i_terms = Symbol[]
        for (ent, port) in node
            key = (ent, port, :I)
            if haskey(global_fields, key)
                push!(i_terms, global_fields[key])
            end
        end
        if length(i_terms) >= 2
            sum_expr = length(i_terms) == 2 ?
                       Expr(:call, :+, i_terms[1], i_terms[2]) :
                       Expr(:call, :+, i_terms...)
            push!(all_eqs, :($sum_expr == 0))
        end
    end

    # ---- Phase 4: 引入辅助状态变量 ----
    # 找到 der(expr) 中 expr 不是 Symbol 的调用，替换为辅助状态 s1/s2/...
    # 同时添加 aux_var == expr 作为代数方程
    isempty(all_eqs) && error("模型没有方程")

    aux_count = Ref(0)
    aux_eqs = Expr[]    # 新增的 aux_var == expr 方程
    all_eqs = [_replace_complex_der!(eq, aux_count, aux_eqs) for eq in all_eqs]

    # 合并方程
    append!(all_eqs, aux_eqs)

    # Phase 4c: 找到所有状态（现在是纯 Symbol，因为 der() 中只有 aux 变量）
    state_set = _find_state_vars(all_eqs)
    isempty(state_set) && error("没有找到状态变量（der() 中的变量）")
    println("[DAE2ODESolver] 状态变量: $state_set")
    println("[DAE2ODESolver] 辅助方程: $aux_eqs")

    all_vars = _find_all_vars(all_eqs)
    # 排除参数名（参数有默认值，不应被消元）
    param_names = Set{Symbol}(p.name for p in all_params)
    algebraic_vars = setdiff(all_vars, state_set, _BUILTIN_FUNS, param_names)
    println("[DAE2ODESolver] 代数变量 ($(length(algebraic_vars)) 个): $algebraic_vars")

    # ---- Phase 5: 代数消元 ----
    defs = _find_algebraic_defs(all_eqs, algebraic_vars)

    # 代数消元主循环：多轮简化 + 新定义发现
    changed = true
    max_rounds = 50
    round = 0
    while changed && round < max_rounds
        round += 1
        changed = false

        # 1. 对现有 defs 应用自身并简化
        for (var, def) in copy(defs)
            new_def = _simplify_expr(_apply_defs(def, defs))
            if new_def != def
                defs[var] = new_def
                changed = true
            end
        end

        # 2. 在简化后的方程中找新定义
        simplified_eqs = [_simplify_expr(_apply_defs(eq, defs)) for eq in all_eqs]
        new_defs = _find_algebraic_defs(simplified_eqs, algebraic_vars)
        for (var, def) in new_defs
            if !haskey(defs, var)
                defs[var] = _simplify_expr(def)
                changed = true
            end
        end

        # 3. 处理求和方程：a + b + c + ... == 0 形式
        # 对每个未定义的代数变量，isolate 它（循环引用由 _substitute_var 保护）
        undefined = setdiff(algebraic_vars, Set(keys(defs)))
        for eq in simplified_eqs
            eq isa Expr && eq.head == :call && length(eq.args) >= 3 && eq.args[1] == :(==) || continue
            lhs_eq = eq.args[2]
            rhs_eq = eq.args[3]
            # sum == 0
            if rhs_eq isa Number && rhs_eq == 0 && lhs_eq isa Expr && lhs_eq.head == :call && lhs_eq.args[1] == :+
                sum_args = lhs_eq.args[2:end]
                got_new = _process_sum_equation!(defs, sum_args, undefined)
                got_new && (changed = true; break)
            end
            # 0 == sum
            if lhs_eq isa Number && lhs_eq == 0 && rhs_eq isa Expr && rhs_eq.head == :call && rhs_eq.args[1] == :+
                sum_args = rhs_eq.args[2:end]
                got_new = _process_sum_equation!(defs, sum_args, undefined)
                got_new && (changed = true; break)
            end
        end
    end
    println("[DAE2ODESolver] 代数定义: $defs")

    # ---- Phase 6: 从方程中提取 ODE ----
    # 对每个含有 der(state) 的方程，提取 der(state) == rhs
    # 对于 C * der(s1) == I 的形式，移项为 der(s1) == I / C
    state_odes = Dict{Symbol, Any}()
    for eq in all_eqs
        if !(eq isa Expr && eq.head == :call && length(eq.args) >= 3 && eq.args[1] == :(==))
            continue
        end
        lhs = eq.args[2]
        rhs_side = eq.args[3]

        # der(s) == rhs  （最简单情况）
        if lhs isa Expr && lhs.head == :call && length(lhs.args) >= 2 && lhs.args[1] == :der
            inner = lhs.args[2]
            if inner isa Symbol && inner in state_set
                state_odes[inner] = _apply_defs(rhs_side, defs)
                continue
            end
        end

        # rhs == der(s)
        if rhs_side isa Expr && rhs_side.head == :call && length(rhs_side.args) >= 2 && rhs_side.args[1] == :der
            inner = rhs_side.args[2]
            if inner isa Symbol && inner in state_set
                state_odes[inner] = _apply_defs(lhs, defs)
                continue
            end
        end

        # C * der(s) == expr
        if lhs isa Expr && lhs.head == :call && lhs.args[1] == :*
            for (i, arg) in enumerate(lhs.args)
                if arg isa Expr && arg.head == :call && length(arg.args) >= 2 && arg.args[1] == :der
                    inner = arg.args[2]
                    if inner isa Symbol && inner in state_set
                        # 收集系数
                        coeffs = Any[lhs.args[j] for j in 2:length(lhs.args) if j != i]
                        if isempty(coeffs)
                            state_odes[inner] = _apply_defs(rhs_side, defs)
                        else
                            coeff_expr = length(coeffs) == 1 ? coeffs[1] : Expr(:call, :*, coeffs...)
                            state_odes[inner] = _apply_defs(:($rhs_side / $coeff_expr), defs)
                        end
                        break
                    end
                end
            end
        end

        # expr == C * der(s)
        if rhs_side isa Expr && rhs_side.head == :call && rhs_side.args[1] == :*
            for (i, arg) in enumerate(rhs_side.args)
                if arg isa Expr && arg.head == :call && length(arg.args) >= 2 && arg.args[1] == :der
                    inner = arg.args[2]
                    if inner isa Symbol && inner in state_set
                        coeffs = Any[rhs_side.args[j] for j in 2:length(rhs_side.args) if j != i]
                        if isempty(coeffs)
                            state_odes[inner] = _apply_defs(lhs, defs)
                        else
                            coeff_expr = length(coeffs) == 1 ? coeffs[1] : Expr(:call, :*, coeffs...)
                            state_odes[inner] = _apply_defs(:($lhs / $coeff_expr), defs)
                        end
                        break
                    end
                end
            end
        end
    end

    isempty(state_odes) && error("无法从方程中提取 ODE")
    println("[DAE2ODESolver] 状态 ODE: $state_odes")

    # ---- Phase 7: 构建 ODE 模型 ----
    ode_rels = Relation[]
    for (i, (state_var, rhs_expr)) in enumerate(collect(state_odes))
        # 对 RHS 重复应用代数定义消去所有代数变量
        rhs_clean = _apply_defs(rhs_expr, defs)
        push!(ode_rels, Relation(
            Symbol("ode_", i), Equation,
            :(der($state_var) == $rhs_clean), [:equation]))
    end

    ode_model = EntityDef(model.name, Port[], ode_rels, all_params)

    # ---- Phase 8: 求解 ----
    ode_solver = ODESolver(dt=solver.dt, reltol=solver.reltol)
    return solve(ode_solver, ode_model; u0=u0, tspan=tspan, params=params)
end

"""
    _replace_complex_der!(expr, aux_count, aux_eqs)

递归扫描表达式，找 `der(expr)` 中 expr 不是 Symbol 的调用。
替换为 `der(sN)` 并添加 `sN == expr` 到 aux_eqs。
"""
function _replace_complex_der!(ex, aux_count::Base.RefValue{Int}, aux_eqs)
    if ex isa Expr && ex.head == :call && length(ex.args) >= 2 && ex.args[1] == :der
        inner = ex.args[2]
        if inner isa Expr  # complex expression inside der()
            aux_count[] += 1
            aux_name = Symbol("s", aux_count[])
            push!(aux_eqs, :($aux_name == $inner))
            return Expr(:call, :der, aux_name)
        end
        return ex
    elseif ex isa Expr
        return Expr(ex.head, [_replace_complex_der!(a, aux_count, aux_eqs) for a in ex.args]...)
    else
        return ex
    end
end

"""
    _simplify_expr(ex) -> Expr

简单代数简化：x - 0 → x, 0 + x → x, x * 1 → x, 1 * x → x, x / 1 → x, 0 * x → 0
"""
function _simplify_expr(ex)
    if ex isa Expr && ex.head == :call
        fn = ex.args[1]
        args = ex.args[2:end]
        # 先递归简化子表达式
        simplified_args = [_simplify_expr(a) for a in args]
        if fn == :+
            # x + 0 → x, 0 + x → x
            non_zero = filter(a -> !(a isa Number && a == 0), simplified_args)
            if isempty(non_zero)
                return 0
            elseif length(non_zero) == 1
                return non_zero[1]
            end
            return Expr(:call, :+, non_zero...)
        elseif fn == :-
            if length(simplified_args) == 1
                return Expr(:call, :-, simplified_args[1])
            elseif length(simplified_args) == 2
                if simplified_args[2] isa Number && simplified_args[2] == 0
                    return simplified_args[1]
                end
                return Expr(:call, :-, simplified_args[1], simplified_args[2])
            end
        elseif fn == :*
            non_one = filter(a -> !(a isa Number && a == 1), simplified_args)
            if any(a -> a isa Number && a == 0, non_one)
                return 0
            end
            if isempty(non_one)
                return 1
            elseif length(non_one) == 1
                return non_one[1]
            end
            return Expr(:call, :*, non_one...)
        elseif fn == :/
            if length(simplified_args) == 2 && simplified_args[2] isa Number && simplified_args[2] == 1
                return simplified_args[1]
            end
            return Expr(:call, :/, simplified_args[1], simplified_args[2])
        end
        return Expr(:call, fn, simplified_args...)
    elseif ex isa Expr
        return Expr(ex.head, [_simplify_expr(a) for a in ex.args]...)
    else
        return ex
    end
end

# 自注册
# Deprecated: do not auto-register this solver in new environments.
