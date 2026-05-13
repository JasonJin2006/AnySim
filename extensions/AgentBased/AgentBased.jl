# ============================================================
# AgentBased Extension — ABM 领域语言
#
# 将 ABM 概念映射到 AnySim Core 类型上。
# 不自创新类型，只是语法糖：
#
#   @agent        → @entity
#   @state        → @param    （Core 无 state 概念，用 param 承载）
#   @on_tick      → @relation Behavioral
#   @on_message   → @relation Event
#   @environment  → ComposeDef 级别的共享数据域
#
# 依赖：AnySim Core（types.jl + macros.jl）
# 不依赖：任何求解器
#
# 使用方法：
#   using AnySim
#   include("extensions/AgentBased/AgentBased.jl")
#   using .AgentBased
# ============================================================

module AgentBased

# ── 引入 Core 类型 ──
# AgentBased 是 AnySim 生态中的独立模块。
# 用户加载方式：先 using AnySim，再 include 本文件 using .AgentBased。
import ..AnySim: @entity, @param, @relation, @behavior, @compose, @connect, @expose
import ..AnySim: EntityDef, Relation, RelationKind, Behavioral, Event, Equation
import ..AnySim: Port, Parameter, Connection, ComposeDef, compile_relation
import ..AnySim: Message, send!
import ..AnySim: make_entity, traverse_entities

# ── 加载 Statechart 子系统 ──
include("statechart.jl")

# ============================================================
# 1. Agent 元数据（运行时标记）
# ============================================================
# 标记一个 entity 是 "agent"。DESolver 可以查这个标记
# 来决定是否使用 ABM 友好的执行路径。

const AGENT_TAG = :agent

"""
    agent_tag(entity_name::Symbol) -> Symbol

生成 agent 标记标签，用于在 entity 参数中标记 agent 身份。
"""
agent_tag(name::Symbol) = Symbol("@agent_", name)

"""
    is_agent(entity::EntityDef) -> Bool

检查一个 entity 是否被标记为 agent（即是通过 @agent 创建的）。
"""
function is_agent(entity::EntityDef)
    for p in entity.parameters
        startswith(string(p.name), "@agent_") && return true
    end
    return false
end

# ============================================================
# 2. @agent 宏
#
# 语法：
#   @agent Wolf begin
#       @state energy = 100.0
#       @state pos_x = 0.0
#       @on_tick :move begin
#           energy -= 1
#       end
#       @on_message :eat begin
#           energy += msg.nutrition
#       end
#   end
#
# 展开为：
#   @entity Wolf begin
#       @param energy = 100.0
#       @param pos_x = 0.0
#       @param @agent_Wolf = true       # agent 标记
#       @relation Behavioral move begin
#           energy -= 1
#       end
#       @relation Event eat begin
#           ... 消息处理
#       end
#   end
# ============================================================

"""
    @agent Name body

定义 agent。展开为 @entity + agent 元数据。

当前支持 body 内的子宏：
  - `@state name = default`  → 展开为 `@param name = default`
  - `@on_tick :name body`    → 展开为 `@relation Behavioral name body`
  - `@on_message :name body` → 展开为 `@relation Event name body`

未来可扩展：
  - `@on_init body`     → 初始化行为
  - `@environment ref`  → 环境引用
  - `@network type`     → 通信拓扑（网格 / 随机 / 小世界）
"""
macro agent(name, body)
    # 解析 body 中的子语句
    entity_stmts = Expr[]
    statechart_params = Parameter[]
    statechart_relations = Relation[]

    for stmt in body.args
        if !(stmt isa Expr)
            continue  # 跳过 LineNumberNode 等非表达式节点
        end
        if stmt.head == :macrocall
            macro_name = stmt.args[1]
            macro_name_sym = macro_name isa GlobalRef ? macro_name.name : macro_name

            if macro_name_sym == Symbol("@state")
                # @state energy = 100.0 → @param energy = 100.0
                state_expr = stmt.args[3]
                param_call = Expr(:macrocall, Symbol("@param"),
                                  stmt.args[2], state_expr)
                push!(entity_stmts, param_call)

            elseif macro_name_sym == Symbol("@on_tick")
                # @on_tick :name begin ... end → @relation Behavioral name begin ... end
                tick_name = stmt.args[3]
                tick_body = stmt.args[4]
                rel_call = Expr(:macrocall, Symbol("@relation"),
                               stmt.args[2],
                               :Behavioral, tick_name, tick_body)
                push!(entity_stmts, rel_call)

            elseif macro_name_sym == Symbol("@behavior")
                # @behavior :name [var1, var2] begin ... end
                # → @relation Behavioral :name [var1, var2] begin ... end
                behavior_name = stmt.args[3]
                behavior_vars = stmt.args[4]   # [var1, var2] — Expr(:vect, ...)
                behavior_body = stmt.args[5]   # begin ... end
                rel_call = Expr(:macrocall, Symbol("@relation"),
                               stmt.args[2],
                               :Behavioral, behavior_name, behavior_vars, behavior_body)
                push!(entity_stmts, rel_call)

            elseif macro_name_sym == Symbol("@on_message")
                # @on_message :name begin ... end → @relation Event name begin ... end
                msg_name = stmt.args[3]
                msg_body = stmt.args[4]
                rel_call = Expr(:macrocall, Symbol("@relation"),
                               stmt.args[2],
                               :Event, msg_name, msg_body)
                push!(entity_stmts, rel_call)

            elseif macro_name_sym == Symbol("@statechart")
                # @statechart begin ... end
                # 解析状态图 → 编译为 params + relations
                sc_body = stmt.args[3]
                sc_ir = parse_statechart_body(sc_body)
                sc_params, sc_rels = compile_statechart(sc_ir)
                append!(statechart_params, sc_params)
                append!(statechart_relations, sc_rels)
                # 不添加到 entity_stmts（状态图不生成 @param/@relation 宏调用）

            else
                # 其他宏（@param, @relation 等）原样传递
                push!(entity_stmts, stmt)
            end
        else
            push!(entity_stmts, stmt)
        end
    end

    # 生成 EntityDef（直接调用 make_entity，避免嵌套宏的 esc() 作用域问题）
    agent_body = Expr(:block, entity_stmts...)
    ed = make_entity(name, agent_body)

    # 注入 statechart 参数和关系
    for p in statechart_params
        push!(ed.parameters, p)
    end
    for r in statechart_relations
        push!(ed.relations, r)
    end

    # 注入 _mailbox 参数（消息队列）
    push!(ed.parameters, Parameter(:_mailbox, Message[], Vector{Message}))
    # 注入 _my_name 参数（agent 的实体名，用于 send! 等函数）
    push!(ed.parameters, Parameter(:_my_name, name, Symbol))

    # 注入 agent 标记参数（不在 body 中用宏，直接构造 Parameter）
    push!(ed.parameters, Parameter(agent_tag(name), true, Any))
    return :($(esc(name)) = $ed)
end

# ============================================================
# 3. 便利函数
# ============================================================

"""
    agents(model::ComposeDef) -> Vector{EntityDef}

从 ComposeDef 中筛选出所有 agent entity。
"""
function agents(model::ComposeDef)
    [e for e in traverse_entities(model) if is_agent(e)]
end

"""
    agent_count(model::ComposeDef) -> Int

返回 agent 数量。
"""
agent_count(model::ComposeDef) = length(agents(model))

# ============================================================
# 4. 导出
# ============================================================

export @agent, @state, @on_tick, @on_message, @behavior
export @statechart, @state, @entry, @exit
export @transition, @guard, @action, @target, @initial
export is_agent, agents, agent_count
export Message, send!

println("[AgentBased] Extension loaded. Use @agent to define agents.")

end # module AgentBased
