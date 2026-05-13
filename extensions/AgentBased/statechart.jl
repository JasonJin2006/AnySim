# ============================================================
# Statechart — Harel 状态图 DSL
#
# 完整的 Harel 状态图在 AgentBased Extension 中的实现。
# 支持：
#   - 嵌套状态（OR 分解）
#   - 浅层/深层历史（H / H*）
#   - entry / exit 动作
#   - guard 条件 + transition 动作
#   - 自动初始子状态展开
#
# 编译策略：状态图在编译期展开为 entity 参数 +
# Behavioral relation，不引入新类型。
#
# 依赖：Core 类型系统（EntityDef, Parameter, Relation, Behavioral）
#
# 关键设计决策（生成的 _sc_step 代码）：
#   - 使用 _state / _history 本地变量（compile_relation 自动解包）
#   - 生成单个 if-elseif 链，防止级联转移
#   - 无提前 return，通过 repack 统一写回 Dict
# ============================================================

# ============================================================
# 1. IR 类型 — Statechart 中间表示
# ============================================================

"""
    HistoryKind

- `NoHistory` — 无历史，每次进入该状态时回到 initial 子状态
- `ShallowHistory` — `H`，记住直接子状态，嵌套内层走 initial
- `DeepHistory` — `H*`，记住完整嵌套路径
"""
@enum HistoryKind begin
    NoHistory
    ShallowHistory
    DeepHistory
end

"""
    TransitionIR

表示一条状态转移。
- name: 转移名称（用户标识）
- defining_path: 定义此转移的状态的完整路径（如 [:Idle, :Wandering]）
- target_state: 目标状态名称
- guard_expr: guard 条件表达式（nothing = 无条件）
- action_expr: 转移动作表达式（nothing = 无动作）
"""
struct TransitionIR
    name::Symbol
    defining_path::Vector{Symbol}
    target_state::Symbol
    guard_expr::Any
    action_expr::Any
end

"""
    StateIR

表示一个状态节点。
- name: 状态名称
- initial: 默认子状态名称（nothing = 未指定）
- history: 历史类型
- entry_expr: 进入动作（nothing = 无）
- exit_expr: 退出动作（nothing = 无）
- children: 嵌套子状态列表
- transitions: 定义在此状态上的转移列表
"""
struct StateIR
    name::Symbol
    initial::Union{Symbol, Nothing}
    history::HistoryKind
    entry_expr::Any
    exit_expr::Any
    children::Vector{StateIR}
    transitions::Vector{TransitionIR}
end

StateIR(name) = StateIR(name, nothing, NoHistory, nothing, nothing, StateIR[], TransitionIR[])

# ============================================================
# 2. DSL 解析器
# ============================================================

"""
    _macro_name(macrocall_first_arg) -> Symbol

从 macrocall 的第一个参数提取宏名。
"""
function _macro_name(mn)
    mn isa Symbol && return mn
    mn isa GlobalRef && return mn.name
    return Symbol(mn)
end

"""
    _unwrap_symbol(arg) -> Symbol

从可能被 QuoteNode/Expr(:quote) 包裹的符号中提取裸 Symbol。
例如 `:hunt` 在宏参数中可能是 `Expr(:quote, :hunt)`，
解包后得到 `:hunt`。
"""
function _unwrap_symbol(arg)
    if arg isa Symbol
        return arg
    elseif isdefined(Base, :QuoteNode) && arg isa QuoteNode
        # QuoteNode(:hunt) → :hunt
        return arg.value
    elseif arg isa Expr && arg.head == :quote
        # Expr(:quote, :hunt) → :hunt
        inner = arg.args[1]
        return inner isa Symbol ? inner : Symbol(inner)
    else
        return Symbol(arg)
    end
end

function _unwrap_value(arg)
    if isdefined(Base, :QuoteNode) && arg isa QuoteNode
        return arg.value
    else
        return arg
    end
end

"""
    parse_statechart_body(body) -> StateIR

解析 `@statechart begin ... end` 的 body。
"""
function parse_statechart_body(body)
    body isa Expr && body.head == :block ||
        error("@statechart body 必须是 begin...end 块")

    state_irs = StateIR[]
    initial = nothing

    for stmt in body.args
        stmt isa Expr || continue
        if stmt.head == :macrocall
            mn = _macro_name(stmt.args[1])
            if mn == Symbol("@state")
                push!(state_irs, _parse_state_stmt(stmt))
            elseif mn == Symbol("@initial")
                initial = _unwrap_symbol(stmt.args[3])
            end
        end
    end

    isempty(state_irs) && error("statechart 至少需要一个 @state")

    return StateIR(:_sc_root, initial, NoHistory, nothing, nothing,
                   state_irs, TransitionIR[])
end

"""
    _parse_state_stmt(stmt) -> StateIR

解析单个 @state 语句。
"""
function _parse_state_stmt(stmt)
    args = stmt.args
    name = _unwrap_symbol(args[3])

    history_kind = NoHistory
    body = nothing

    if length(args) >= 5
        # @state Name history=true begin ... end
        kwargs_expr = args[4]
        if kwargs_expr isa Expr && kwargs_expr.head == :(=)
            if kwargs_expr.args[1] == :history
                hist_val = kwargs_expr.args[2]
                uhist = _unwrap_value(hist_val)
                if uhist == true || uhist == :shallow
                    history_kind = ShallowHistory
                elseif uhist == :deep
                    history_kind = DeepHistory
                else
                    error("不支持的 history 值: $hist_val")
                end
            else
                error("未知的关键字: $(kwargs_expr.args[1])")
            end
        end
        body = args[5]
    elseif length(args) >= 4
        body = args[4]
    end

    body isa Expr || error("@state $name 需要一个 begin...end 块")

    entry_expr = nothing
    exit_expr = nothing
    children = StateIR[]
    transitions = TransitionIR[]
    initial = nothing

    for sub_stmt in body.args
        sub_stmt isa Expr || continue
        if sub_stmt.head == :macrocall
            mn = _macro_name(sub_stmt.args[1])

            if mn == Symbol("@entry")
                entry_expr = sub_stmt.args[3]
            elseif mn == Symbol("@exit")
                exit_expr = sub_stmt.args[3]
            elseif mn == Symbol("@state")
                push!(children, _parse_state_stmt(sub_stmt))
            elseif mn == Symbol("@initial")
                initial = _unwrap_symbol(sub_stmt.args[3])
            elseif mn == Symbol("@transition")
                trans = _parse_transition_stmt(sub_stmt, [name])
                push!(transitions, trans)
            end
        end
    end

    return StateIR(name, initial, history_kind, entry_expr, exit_expr,
                   children, transitions)
end

"""
    _parse_transition_stmt(stmt, defining_path) -> TransitionIR
"""
function _parse_transition_stmt(stmt, defining_path)
    args = stmt.args
    trans_name = args[3]
    body = nothing

    if length(args) >= 5 && args[4] isa Expr && args[4].head == :block
        body = args[4]
    elseif length(args) >= 4
        body = args[4]
    end

    body isa Expr || error("@transition 需要一个 begin...end 块")

    guard_expr = nothing
    action_expr = nothing
    target_state = nothing

    for sub_stmt in body.args
        sub_stmt isa Expr || continue
        if sub_stmt.head == :macrocall
            mn = _macro_name(sub_stmt.args[1])
            if mn == Symbol("@guard")
                guard_expr = sub_stmt.args[3]
            elseif mn == Symbol("@action")
                action_expr = sub_stmt.args[3]
            elseif mn == Symbol("@target")
                target = sub_stmt.args[3]
                target_state = _unwrap_symbol(target)
            end
        end
    end

    target_state === nothing && error("@transition $(trans_name) 缺少 @target")

    return TransitionIR(
        _unwrap_symbol(trans_name),
        defining_path, target_state, guard_expr, action_expr
    )
end

# ============================================================
# 3. 状态图编译器
#
# 将 StateIR 编译为 entity 参数和 _sc_step 函数体。
#
# 编译产物：
#   params: _state (Vector{Symbol}), _history (Dict)
#   relations: _sc_step (Behavioral，函数体是 if-elseif 链)
#
# 核心设计：
#   - 生成的代码使用 _state, _history 本地变量
#     （由 compile_relation 自动从 Dict 解包和回写）
#   - 每个叶子状态对应一个 elseif 分支
#   - 转移触发时修改本地变量，不提前 return
#   - if-elseif 结构天然防止同 tick 内的级联转移
# ============================================================

"""
    compile_statechart(state_ir::StateIR) -> (params::Vector, relations::Vector)

编译状态图到 entity 参数和 relation。
"""
function compile_statechart(state_ir::StateIR)
    # 展开初始路径（不含 _sc_root）
    init_path = _build_initial_path(state_ir, Symbol[])
    init_path = _strip_root(init_path)

    # 收集所有叶子状态及其完整路径（不含 _sc_root）
    leaves = _collect_leaves(state_ir, Symbol[])
    leaves = [(_strip_root(p), ir) for (p, ir) in leaves]

    # 生成 _sc_step 函数体（if-elseif 链）
    step_body = _gen_step_body(leaves, state_ir)

    # 构建参数
    params = [
        Parameter(:_state, init_path, Vector{Symbol}),
        Parameter(:_history, Dict{Symbol, Vector{Symbol}}(),
                  Dict{Symbol, Vector{Symbol}}),
    ]

    # 构建 relation
    relations = [
        Relation(:_sc_step, Behavioral,
                 step_body, Symbol[:behavioral, :statechart]),
    ]

    return params, relations
end

"""
    _strip_root(path) -> Vector{Symbol}

去掉路径开头的 _sc_root（内部实现细节）。
"""
_strip_root(path) = (!isempty(path) && path[1] == Symbol("_sc_root")) ? path[2:end] : path

# ============================================================
# 3a. 路径工具
# ============================================================

"""
    _build_initial_path(ir, parent_path) -> Vector{Symbol}

递归构建初始状态路径（从根到叶子）。
"""
function _build_initial_path(ir::StateIR, parent_path)
    path = vcat(parent_path, [ir.name])

    if !isempty(ir.children)
        target = ir.initial
        if target === nothing && !isempty(ir.children)
            target = ir.children[1].name
        end
        if target !== nothing
            child = _find_state_child(ir, target)
            if child !== nothing
                return _build_initial_path(child, path)
            end
        end
    end
    return path
end

"""
    _collect_leaves(ir, parent_path) -> Vector{Tuple{Vector{Symbol}, StateIR}}
"""
function _collect_leaves(ir::StateIR, parent_path)
    my_path = vcat(parent_path, [ir.name])
    leaves = Vector{Tuple{Vector{Symbol}, StateIR}}()

    if isempty(ir.children)
        push!(leaves, (my_path, ir))
    else
        for child in ir.children
            append!(leaves, _collect_leaves(child, my_path))
        end
    end
    return leaves
end

"""
    _find_state_child(ir, child_name) -> Union{StateIR, Nothing}
"""
function _find_state_child(ir::StateIR, child_name::Symbol)
    for child in ir.children
        child.name == child_name && return child
    end
    return nothing
end

"""
    _find_state_by_name(ir, name) -> Union{StateIR, Nothing}

在整个树中查找指定名称的状态（递归）。
"""
function _find_state_by_name(ir::StateIR, name::Symbol)
    ir.name == name && return ir
    for child in ir.children
        result = _find_state_by_name(child, name)
        result !== nothing && return result
    end
    return nothing
end

"""
    _build_path(ir, target_name, path) -> Bool

递归构建到目标状态的路径。返回是否找到。
"""
function _build_path(ir::StateIR, target_name::Symbol, path)
    if ir.name == target_name
        push!(path, ir.name)
        return true
    end
    for child in ir.children
        if _build_path(child, target_name, path)
            pushfirst!(path, ir.name)
            return true
        end
    end
    return false
end

"""
    resolve_target_path(target_name, root_ir) -> Vector{Symbol}

将目标状态名称解析为从根开始的完整路径。
跳过根状态的 _sc_root 节点。
"""
function resolve_target_path(target_name::Symbol, root_ir::StateIR)
    # 在整个树中查找
    target = _find_state_by_name(root_ir, target_name)
    target === nothing && error("目标状态 :$target_name 未找到")

    # 构建路径
    parts = Symbol[]
    _build_path(root_ir, target_name, parts)
    # 去掉根名称
    if !isempty(parts) && parts[1] == Symbol("_sc_root")
        parts = parts[2:end]
    end
    return parts
end

# ============================================================
# 3b. 目标路径展开
# ============================================================

"""
    expand_target_path(target_path, root_ir) -> Vector{Symbol}

展开目标路径到完整叶子路径。
如果目标是复合状态，递归进入 initial 子状态。
"""
function expand_target_path(target_path, root_ir)
    # 从根开始沿路径查找
    current = root_ir
    for name in target_path
        found = false
        if current.name == name
            found = true
        else
            for child in current.children
                if child.name == name
                    current = child
                    found = true
                    break
                end
            end
        end
        found || return target_path  # 路径中有未知节点，返回原路径
    end

    # current 现在是目标状态
    if !isempty(current.children)
        target = current.initial
        if target === nothing && !isempty(current.children)
            target = current.children[1].name
        end
        if target !== nothing
            return expand_target_path(vcat(target_path, [target]), root_ir)
        end
    end

    return target_path
end

# ============================================================
# 3c. LCA 计算
# ============================================================

"""
    compute_lca(path1, path2) -> Int

计算两个路径的最长公共前缀长度。
跳过 _sc_root。
"""
function compute_lca(path1, path2)
    i1 = 1; i2 = 1
    # 跳过根名
    if !isempty(path1) && path1[1] == Symbol("_sc_root"); i1 = 2; end
    if !isempty(path2) && path2[1] == Symbol("_sc_root"); i2 = 2; end

    while i1 <= length(path1) && i2 <= length(path2) && path1[i1] == path2[i2]
        i1 += 1; i2 += 1
    end
    return min(i1 - 1, length(path1), length(path2))
end

# ============================================================
# 3d. 转移收集
# ============================================================

"""
    collect_ancestor_transitions(leaf_path, root_ir) -> Vector{Tuple{TransitionIR, Vector{Symbol}}}

收集叶子状态及其所有祖先状态的转移。
返回 (TransitionIR, defining_path) 列表，按从下到上顺序。
"""
function collect_ancestor_transitions(leaf_path, root_ir)
    result = Vector{Tuple{TransitionIR, Vector{Symbol}}}()

    # 建立从叶子到根的完整路径
    full_path = vcat([Symbol("_sc_root")], leaf_path)

    for prefix_len in length(leaf_path):-1:1
        prefix = leaf_path[1:prefix_len]
        # 找到这个前缀在状态树中对应的 IR
        state_ir = _find_state_by_prefix(root_ir, prefix)
        if state_ir !== nothing
            for trans in state_ir.transitions
                push!(result, (trans, prefix))
            end
        end
    end

    return result
end

"""
    _find_state_by_prefix(ir, prefix) -> Union{StateIR, Nothing}

按前缀路径查找状态 IR（从 root 开始）。
"""
function _find_state_by_prefix(ir::StateIR, prefix::Vector{Symbol})
    if ir.name == Symbol("_sc_root") && isempty(prefix)
        return ir
    end

    # 从根开始分段匹配
    current = ir

    # 如果 ir 是 _sc_root，跳过它
    remaining = copy(prefix)
    if current.name == Symbol("_sc_root")
        # 直接匹配子状态
        if isempty(remaining)
            return current  # _sc_root 本身没有转移，但可以返回
        end
        first = popfirst!(remaining)
        found = false
        for child in current.children
            if child.name == first
                current = child
                found = true
                break
            end
        end
        found || return nothing
    end

    # 匹配剩余路径
    for name in remaining
        found = false
        for child in current.children
            if child.name == name
                current = child
                found = true
                break
            end
        end
        found || return nothing
    end

    return current
end

# ============================================================
# 3e. 退出/进入动作生成
# ============================================================

"""
    gen_exit_actions(current_path, lca_len, root_ir) -> Vector{Any}

生成退出动作表达式（从当前叶子到 LCA 反向顺序）。
"""
function gen_exit_actions(current_path, lca_len, root_ir)
    exprs = Any[]
    for i in length(current_path):-1:(lca_len + 1)
        state_name = current_path[i]
        state_ir = _find_state_by_name(root_ir, state_name)
        if state_ir !== nothing && state_ir.exit_expr !== nothing
            push!(exprs, state_ir.exit_expr)
        end
    end
    return exprs
end

"""
    gen_entry_actions(target_path, lca_len, root_ir) -> Vector{Any}

生成进入动作表达式（从 LCA 到目标叶子正序）。
"""
function gen_entry_actions(target_path, lca_len, root_ir)
    exprs = Any[]
    for i in (lca_len + 1):length(target_path)
        state_name = target_path[i]
        state_ir = _find_state_by_name(root_ir, state_name)
        if state_ir !== nothing && state_ir.entry_expr !== nothing
            push!(exprs, state_ir.entry_expr)
        end
    end
    return exprs
end

"""
    gen_history_save(current_path, lca_len, root_ir) -> Vector{Any}

生成历史保存表达式。
当离开一个有 history 的复合状态时，保存其子路径。
"""
function gen_history_save(current_path, lca_len, root_ir)
    exprs = Any[]

    # 从叶子到 LCA 检查每个退出的状态是否有 history
    for i in length(current_path):-1:(lca_len + 1)
        state_name = current_path[i]
        state_ir = _find_state_by_name(root_ir, state_name)
        if state_ir !== nothing && state_ir.history != NoHistory
            # 保存子路径
            if i < length(current_path)
                child_name = current_path[i + 1]
                if state_ir.history == DeepHistory
                    # 深层历史：保存以下全部路径
                    saved = current_path[(i + 1):end]
                    push!(exprs, :(_history[$(QuoteNode(state_name))] = $saved))
                else
                    # 浅层历史：只保存直接子状态
                    push!(exprs, :(_history[$(QuoteNode(state_name))] = [$(QuoteNode(child_name))]))
                end
            end
        end
    end

    return exprs
end

# ============================================================
# 3f. _sc_step 函数体生成
# ============================================================

"""
    _gen_step_body(leaves, root_ir) -> Expr

生成 _sc_step 关系的函数体。
一个大的 if-elseif 链，每个叶子状态对应一个 elseif 分支。
"""
function _gen_step_body(leaves, root_ir)
    if isempty(leaves)
        return Expr(:block)
    end

    # 为每个叶子状态生成 elseif 条件 + 处理体
    clauses = Any[]  # 交替的条件和体

    for (i, (leaf_path, leaf_ir)) in enumerate(leaves)
        condition = Expr(:call, :(==), :_state, leaf_path)
        body = _gen_leaf_handler(leaf_path, leaf_ir, root_ir)
        push!(clauses, condition)
        push!(clauses, body)
    end

    # 添加 _sc_root 级别的处理（处理初始状态未展开的情况）
    root_cond = Expr(:call, :(==), :_state, Symbol[])
    root_body = Expr(:block)
    push!(clauses, root_cond)
    push!(clauses, root_body)

    # 构建 if-elseif 链
    result = Expr(:if, clauses[1], clauses[2])

    for i in 3:2:length(clauses)
        result = Expr(:elseif, clauses[i], clauses[i + 1], result)
    end

    return result
end

"""
    _gen_leaf_handler(leaf_path, leaf_ir, root_ir) -> Expr

生成叶子状态的处理体。
检查所有转移（自身的 + 祖先的）。
"""
function _gen_leaf_handler(leaf_path, leaf_ir, root_ir)
    # 收集所有需要检查的转移
    transitions = collect_ancestor_transitions(leaf_path, root_ir)

    if isempty(transitions)
        return Expr(:block, nothing)
    end

    # 为每个转移生成检查代码
    trans_blocks = Any[]
    for (trans, defining_path) in transitions
        tb = _gen_transition_block(trans, defining_path, leaf_path, root_ir)
        if tb !== nothing
            push!(trans_blocks, tb)
        end
    end

    if isempty(trans_blocks)
        return Expr(:block, nothing)
    end

    # 生成 guard → handler 的 if-elseif 链
    result = Expr(:if, trans_blocks[1][1], trans_blocks[1][2])
    for i in 2:length(trans_blocks)
        result = Expr(:elseif, trans_blocks[i][1], trans_blocks[i][2], result)
    end

    return Expr(:block, result)
end

"""
    _gen_transition_block(trans, defining_path, current_path, root_ir) -> Union{Vector{Any}, Nothing}

生成单个转移的 [guard_expr, handler_body]。
"""
function _gen_transition_block(trans, defining_path, current_path, root_ir)
    # 解析目标路径
    target_path = resolve_target_path(trans.target_state, root_ir)
    target_path === nothing && return nothing

    # Guard
    guard = trans.guard_expr !== nothing ? trans.guard_expr : true

    # LCA
    # defining_path 是转移定义状态的路径（从根）
    # current_path 是当前叶子状态的路径
    lca_len = compute_lca(current_path, target_path)

    # 构建 handler
    handler = Expr(:block)

    # 1. 保存历史（退出的复合状态如果有 history）
    hist_saves = gen_history_save(current_path, lca_len, root_ir)
    for hs in hist_saves
        push!(handler.args, hs)
    end

    # 2. 退出动作
    exit_actions = gen_exit_actions(current_path, lca_len, root_ir)
    for ea in exit_actions
        push!(handler.args, ea)
    end

    # 3. 转移动作
    if trans.action_expr !== nothing
        push!(handler.args, trans.action_expr)
    end

    # 4. 展开目标路径（递归进入 initial 子状态）
    expanded_target = expand_target_path(target_path, root_ir)

    # 5. 进入动作（从 LCA 到展开后的目标叶子的中间状态）
    entry_actions = gen_entry_actions(expanded_target, lca_len, root_ir)
    for ea in entry_actions
        push!(handler.args, ea)
    end

    # 6. 设置新路径（通过本地变量 _state，由 repack 写回 Dict）
    push!(handler.args, :(_state = $expanded_target))

    return [guard, handler]
end


# ============================================================
# 4. @statechart 宏及其子宏
#
# 这些宏在 @agent body 内部使用，由 @agent 宏解析。
# 它们本身是 no-ops，因为实际处理在 @agent 的 body parser 中。
# ============================================================

macro statechart(body)
    return nothing
end

macro state(args...)
    return nothing
end

macro entry(expr)
    return nothing
end

macro exit(expr)
    return nothing
end

macro transition(args...)
    return nothing
end

macro guard(expr)
    return nothing
end

macro action(expr)
    return nothing
end

macro target(expr)
    return nothing
end

macro initial(expr)
    return nothing
end


# ============================================================
# 5. 导出
# ============================================================

export @statechart, @state, @entry, @exit
export @transition, @guard, @action, @target, @initial
export compile_statechart, parse_statechart_body
export StateIR, TransitionIR, HistoryKind, NoHistory, ShallowHistory, DeepHistory
