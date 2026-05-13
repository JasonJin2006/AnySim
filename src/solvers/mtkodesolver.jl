# ============================================================
# MTKODESolver — ModelingToolkit.jl 桥接求解器
#
# 将 AnySim 的 acausal ComposeDef 映射为 MTK ODESystem，
# 利用 MTK 的 structural_simplify 进行 DAE → ODE 降阶，
# 再用 OrdinaryDiffEq 求解。
#
# 设计原则：
# - AnySim 负责建模 DSL 和模型管理（Core + Meta-Core）
# - MTK 负责符号代数消元——不需要我们自己手写
# - OrdinaryDiffEq 负责数值积分
#
# 管线：
#   1. 展开模型（flatten）+ 生成平铺方程
#   2. 将平铺方程转换为 MTK 符号方程
#   3. 构建 ODESystem → structural_simplify
#   4. 生成 ODEProblem → OrdinaryDiffEq 求解
#   5. 结果映射回平铺命名空间
# ============================================================

struct MTKODESolver <: AbstractSolver
    alg::Symbol
    reltol::Float64
    abstol::Float64
end
MTKODESolver(; alg=:Tsit5, reltol=1e-6, abstol=1e-8) = MTKODESolver(alg, reltol, abstol)

function can_solve(::MTKODESolver, model::ComposeDef)
    classify_model(model) == :static && return false
    return true
end
function can_solve(::MTKODESolver, model::EntityDef)
    # 检查是否有 ODE 方程
    any(r -> _is_explicit_ode(r.expr), model.relations)
end

# ============================================================
# 0. 依赖检查
# ============================================================

function _has_mtk()
    try
        Base.require(Base.PkgId(
            Base.UUID("961ee093-0014-501f-94e3-6117800e7a78"), "ModelingToolkit"))
        return true
    catch
        return false
    end
end

function _get_mtk()
    return Base.require(Base.PkgId(
        Base.UUID("961ee093-0014-501f-94e3-6117800e7a78"), "ModelingToolkit"))
end

function _get_symbolics()
    return Base.require(Base.PkgId(
        Base.UUID("0c5d862f-8b57-4792-8d23-62f2024744c7"), "Symbolics"))
end

function _get_ode()
    return Base.require(Base.PkgId(
        Base.UUID("1dea7af3-3e70-54e6-95c3-0bf5283fa5ed"), "OrdinaryDiffEq"))
end

# ============================================================
# 1. Port → Field 发现（来自原 DAE2ODESolver）
#
# 扫描 entity 方程中的所有 port.field 模式，
# 构建 (ent, port, field) → flat symbol 映射。
# ============================================================

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

_make_flat_name(ent, port, field) = Symbol(string(ent, "_", port, "_", field))

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
# ============================================================

function _make_internal_kcl(ent_name, ports, all_fields)
    length(ports) <= 1 && return nothing
    i_terms = Symbol[]
    for p in ports
        pname = p.name
        if haskey(all_fields, (pname, :I))
            push!(i_terms, all_fields[(pname, :I)])
        end
    end
    isempty(i_terms) && return nothing
    if length(i_terms) == 1
        return :($(i_terms[1]) == 0)
    end
    sum_expr = Expr(:call, :+, i_terms...)
    return :($sum_expr == 0)
end

# ============================================================
# 3. 连接拓扑 → 节点
# ============================================================

function _find_nodes(connections)
    adj = Dict{Tuple{Symbol,Symbol}, Vector{Tuple{Symbol,Symbol}}}()
    for conn in connections
        push!(get!(adj, conn.from, Tuple{Symbol,Symbol}[]), conn.to)
        push!(get!(adj, conn.to, Tuple{Symbol,Symbol}[]), conn.from)
    end
    visited = Set{Tuple{Symbol,Symbol}}()
    nodes = Vector{Tuple{Symbol,Symbol}}[]
    for start in keys(adj)
        start in visited && continue
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
# 4. Flat 方程生成（Phase 1-3 合并）
#
# 将 flatten + connection topology → 平铺方程列表
# 返回 (equations::Vector{Expr}, parameters::Vector{Parameter})
# ============================================================

function _generate_flat_equations(flat::ComposeDef, connections::Vector{Connection})
    all_eqs = Expr[]
    all_params = Parameter[]
    # 全局 field 映射： (ent, port, field) → flat_symbol
    global_fields = Dict{Tuple{Symbol,Symbol,Symbol}, Symbol}()

    for e in flat.entities
        port_names = Set{Symbol}(p.name for p in e.ports)
        append!(all_params, e.parameters)

        all_fields = Dict{Tuple{Symbol,Symbol}, Symbol}()
        for r in e.relations
            r.expr === nothing && continue
            accesses = _scan_port_field_accesses(r.expr, port_names)
            for (port, field) in accesses
                all_fields[(port, field)] = _make_flat_name(e.name, port, field)
            end
        end

        # 补齐 .V/.I
        used_port_names = Set{Symbol}(k[1] for k in keys(all_fields))
        for pname in used_port_names
            if !haskey(all_fields, (pname, :V))
                all_fields[(pname, :V)] = _make_flat_name(e.name, pname, :V)
            end
            if !haskey(all_fields, (pname, :I))
                all_fields[(pname, :I)] = _make_flat_name(e.name, pname, :I)
            end
        end

        # 替换 entity 方程
        for r in e.relations
            r.expr === nothing && continue
            flat_expr, _ = _field_to_flat(r.expr, e.name, port_names)
            push!(all_eqs, flat_expr)
        end

        # 写入 global_fields
        for ((port, field), flat) in all_fields
            global_fields[(e.name, port, field)] = flat
        end

        # 内部 KCL
        kcl = _make_internal_kcl(e.name, e.ports, all_fields)
        kcl !== nothing && push!(all_eqs, kcl)
    end

    # ---- 连接方程 ----
    nodes = _find_nodes(connections)
    for node in nodes
        # Across .V equality
        v_terms = Symbol[]
        for (ent, port) in node
            key = (ent, port, :V)
            if haskey(global_fields, key)
                push!(v_terms, global_fields[key])
            end
        end
        for i in 2:length(v_terms)
            push!(all_eqs, :($(v_terms[1]) == $(v_terms[i])))
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

    return all_eqs, all_params
end

# ============================================================
# 5. 变量分类
# ============================================================

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
# 6. Expr → MTK Num / Equation 转换
#
# 将 AnySim 的平铺 Expr 转换为 MTK/Numa 的符号表达式。
# 关键映射：
#   Symbol → Num (变量或参数)
#   == → ~ (MTK Equation)
#   der(x) → D(x) (MTK Derivative)
# ============================================================

"""
    _convert_to_mtk(ex, var_map, param_map, mtk_mod) -> Num_or_Equation

将 AnySim Expr 递归转换为 MTK 符号表达式。
- `ex`: AnySim 平铺表达式（Julia Expr）
- `var_map`: Dict{Symbol, Num} — 状态 + 代数变量映射
- `param_map`: Dict{Symbol, Num} — 参数变量映射
- `mtk_mod`: ModelingToolkit 模块引用（用于 D/Equation 等）
"""
function _convert_to_mtk(ex, var_map, param_map, mtk_mod)
    if ex isa Symbol
        if haskey(var_map, ex)
            return var_map[ex]
        elseif haskey(param_map, ex)
            return param_map[ex]
        end
        # 内置常量 (pi, true, false 等)
        if ex == :pi
            return pi
        elseif ex == :true
            return true
        elseif ex == :false
            return false
        end
        return ex  # 可能是运算符 Symbol，保持原样
    elseif ex isa Number
        return ex
    elseif ex isa Expr && ex.head == :call
        fn = ex.args[1]
        args = [_convert_to_mtk(a, var_map, param_map, mtk_mod) for a in ex.args[2:end]]

        if fn == :(==)
            # 转换为 MTK Equation: lhs ~ rhs
            tilde = getfield(mtk_mod, :~)
            return Base.invokelatest(tilde, args[1], args[2])
        elseif fn == :der
            # 转换为 MTK 导数: D(inner)
            return Base.invokelatest(mtk_mod.D, args[1])
        elseif fn == :+
            # Num 重载了 +，直接用标准算术
            result = args[1]
            for i in 2:length(args)
                result = result + args[i]
            end
            return result
        elseif fn == :-
            if length(args) == 1
                return -args[1]
            else
                result = args[1]
                for i in 2:length(args)
                    result = result - args[i]
                end
                return result
            end
        elseif fn == :*
            result = args[1]
            for i in 2:length(args)
                result = result * args[i]
            end
            return result
        elseif fn == :/
            return args[1] / args[2]
        elseif fn == :^
            return args[1] ^ args[2]
        else
            # 其他函数调用：.sin, .cos 等
            fn_func = getfield(Base, fn)
            return fn_func(args...)
        end
    elseif ex isa Expr
        # 非 call 表达式（如 :ref, :tuple 等），递归处理参数
        return Expr(ex.head, [_convert_to_mtk(a, var_map, param_map, mtk_mod) for a in ex.args]...)
    else
        return ex
    end
end

# ============================================================
# 7. MTK 变量/参数创建
# ============================================================
#
# 这些函数在 __init__ 中通过 @eval 延迟编译，
# 避免动态加载 Symbolics 造成的 world age 问题。

"""
    _make_mtk_var(name, t, sym_mod) -> Num

创建 MTK 状态/代数变量：name(t)
"""
function _make_mtk_var(name, t, sym_mod)
    # 运行时通过闭包 + invokelatest 调用，避免 world age 问题
    f = (args...) -> begin
        n, tv, sm = args
        SU = getfield(sm, :SymbolicUtils)
        SR = getfield(sm, :SymReal)
        fn_type = getfield(SU, :FnType){Tuple, Real, Nothing}
        raw = getfield(SU, :Sym){SR}(n; type=fn_type, shape=UnitRange{Int64}[])
        x_func = raw(tv)
        return getfield(sm, :Num)(x_func)
    end
    return Base.invokelatest(f, name, t, sym_mod)
end

"""
    _make_mtk_param(name, Symbolics_mod) -> Num

创建 MTK 参数（不依赖 t）
"""
function _make_mtk_param(name, sym_mod)
    f = (args...) -> begin
        n, sm = args
        SU = getfield(sm, :SymbolicUtils)
        SR = getfield(sm, :SymReal)
        raw = getfield(SU, :Sym){SR}(n; type=Real, shape=UnitRange{Int64}[])
        return getfield(sm, :Num)(raw)
    end
    return Base.invokelatest(f, name, sym_mod)
end

# ============================================================
# 8. 主求解方法
# ============================================================

# EntityDef → 包装为 ComposeDef 后委派给 ComposeDef 方法
function solve(solver::MTKODESolver, model::EntityDef; kwargs...)
    comp = ComposeDef(model.name, [model], Relation[], Connection[], [])
    return solve(solver, comp; kwargs...)
end

function solve(solver::MTKODESolver, model::ComposeDef;
               u0=Dict{Symbol,Float64}(), tspan=(0.0, 10.0),
               params=Dict{Symbol,Any}())

    # ---- 依赖检查 ----
    _has_mtk() || error(
        "ModelingToolkit 未安装。请运行: using Pkg; Pkg.add(\"ModelingToolkit\")")

    mtk = _get_mtk()
    sym = _get_symbolics()
    ode = _get_ode()

    # ---- Phase 1: 展开 + 平铺方程生成 ----
    flat = flatten(model)
    all_eqs, all_params = _generate_flat_equations(flat, model.connections)
    isempty(all_eqs) && error("模型没有方程")

    # ---- Phase 2: 变量分类 ----
    state_set = _find_state_vars(all_eqs)
    isempty(state_set) && error("没有找到状态变量（der() 中的变量）")

    all_vars = _find_all_vars(all_eqs)
    param_names_set = Set{Symbol}(p.name for p in all_params)
    algebraic_vars = setdiff(all_vars, state_set, _BUILTIN_FUNS, param_names_set)

    @debug "[MTKODESolver] 状态: $state_set"
    @debug "[MTKODESolver] 代数: $algebraic_vars"
    @debug "[MTKODESolver] 参数: $param_names_set"
    @debug "[MTKODESolver] 方程数: $(length(all_eqs))"

    # ---- Phase 3: 创建 MTK 符号变量 ----
    # 独立变量 t
    t_var = _make_mtk_param(:t, sym)

    # 状态变量
    var_map = Dict{Symbol, Any}()
    for s in state_set
        var_map[s] = _make_mtk_var(s, t_var, sym)
    end
    for v in algebraic_vars
        var_map[v] = _make_mtk_var(v, t_var, sym)
    end

    # 参数
    param_map = Dict{Symbol, Any}()
    for p in all_params
        param_map[p.name] = _make_mtk_param(p.name, sym)
    end

    # ---- Phase 4: 转换方程 ----
    mtk_eqs = [_convert_to_mtk(eq, var_map, param_map, mtk) for eq in all_eqs]
    isempty(mtk_eqs) && error("方程转换后没有生成 MTK 方程")

    # ---- Phase 5: 构建 ODESystem + structural_simplify ----
    all_mtk_states = collect(values(var_map))
    all_mtk_params = collect(values(param_map))

    sys = Base.invokelatest(mtk.ODESystem,
        mtk_eqs, t_var, all_mtk_states, all_mtk_params;
        name=model.name)

    simp_sys = Base.invokelatest(mtk.structural_simplify, sys)
    simp_states = Base.invokelatest(mtk.states, simp_sys)

    # 构建逆向映射：MTK Num → flat Symbol
    reverse_map = Dict{Any, Symbol}()
    for (k, v) in var_map
        reverse_map[v] = k
    end
    for (k, v) in param_map
        reverse_map[v] = k
    end

    # ---- Phase 6: 构建 u0 和参数映射 ----
    mtk_u0 = Dict{Any, Float64}()
    for (name, var) in var_map
        if haskey(u0, name)
            mtk_u0[var] = Float64(u0[name])
        end
    end

    mtk_pmap = Dict{Any, Float64}()
    for p in all_params
        if haskey(params, p.name)
            mtk_pmap[param_map[p.name]] = Float64(params[p.name])
        elseif p.default !== nothing
            mtk_pmap[param_map[p.name]] = Float64(p.default)
        end
    end

    # ---- Phase 7: 创建 ODEProblem + 求解 ----
    # ---- Phase 7: 创建 ODEProblem + 求解 ----
    prob = try
        Base.invokelatest(mtk.ODEProblem, simp_sys, mtk_u0, tspan, mtk_pmap)
    catch e
        if occursin("Initial condition", string(e))
            @warn "初始条件不完整，补零处理: $e"
            for ss in simp_states
                if !haskey(mtk_u0, ss)
                    mtk_u0[ss] = 0.0
                end
            end
            Base.invokelatest(mtk.ODEProblem, simp_sys, mtk_u0, tspan, mtk_pmap)
        else
            rethrow()
        end
    end

    alg_obj = _resolve_mtk_alg(solver.alg, ode)
    sol = Base.invokelatest(ode.solve, prob, alg_obj,
        reltol=solver.reltol, abstol=solver.abstol)

    # ---- Phase 8: 结果映射 ----
    flat_names = Symbol[]
    for ss in simp_states
        name = get(reverse_map, ss, nothing)
        if name === nothing
            name = Symbol(string(ss))
        end
        push!(flat_names, name)
    end

    n_states = length(flat_names)
    us = Matrix{Float64}(undef, n_states, length(sol.t))
    for i in 1:n_states
        for j in 1:length(sol.t)
            us[i, j] = sol.u[j][i]
        end
    end

    return SimResult(Vector{Float64}(sol.t), us, flat_names,
        Dict(p.name => Float64(p.default) for p in all_params), true)
end

# ============================================================
# 9. 算法名解析
# ============================================================

function _resolve_mtk_alg(name::Symbol, ode_mod)
    if name == :Tsit5
        return Base.invokelatest(ode_mod.Tsit5)
    elseif name == :RK4
        return Base.invokelatest(ode_mod.RK4)
    elseif name == :Vern7
        return Base.invokelatest(ode_mod.Vern7)
    elseif name == :Rosenbrock23
        return Base.invokelatest(ode_mod.Rosenbrock23)
    elseif name == :DP5
        return Base.invokelatest(ode_mod.DP5)
    elseif name == :AutoVern7
        return Base.invokelatest(ode_mod.AutoVern7)
    else
        @warn "未知算法 :$(name)，使用默认 :Tsit5"
        return Base.invokelatest(ode_mod.Tsit5)
    end
end

# 自注册
register_solver!(MTKODESolver)
