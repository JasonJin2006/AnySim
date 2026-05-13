module AnySim

# ============================================================
# 子模块（按依赖顺序 include）
# ============================================================
include("types.jl")             # Core 类型系统（零依赖）
include("diagnostics.jl")       # 结构化 diagnostics（依赖 types）
include("macros.jl")            # DSL 宏 + 宏注册表（依赖 types）
include("meta_core.jl")         # Meta-Core API（依赖 types）
include("compile.jl")           # compile + 打印（依赖 types + meta_core）
include("solver_protocol.jl")   # Solver 协议 + 注册发现（零额外依赖）
include("execution_ir.jl")      # Execution IR 骨架（Core IR → solver runtime）
include("capabilities.jl")      # Julia 生态增强能力层
# 加载 solvers/ 目录下的所有求解器（显式顺序控制注册优先级）
include("solvers/solver_utils.jl")     # 共享工具（无注册）
include("solvers/odesolver.jl")        # 内置 RK4（最通用，优先级最高）
include("solvers/mtkodesolver.jl")     # ModelingToolkit 桥接（acausal → ODE）
include("solvers/deodesolver.jl")      # OrdinaryDiffEq 桥接
include("solvers/desolver.jl")         # 离散事件 / Agent-Based 求解器
include("solvers/hybridsolver.jl")    # 混合连续-离散求解器

# DAE2ODESolver 已废弃，保留历史实现文件仅供迁移参考

# 仿真协议层（Julia ↔ 前端通信）
include("protocol.jl")

# ============================================================
# Exports
# ============================================================
export @entity, @relation, @behavior, @compose, @expose, @port, @param, @connect
export compile, traverse_entities, traverse_relations, traverse_connections, classify_model
export relation_uses_operator, find_by_tag, query_relations
export map_model, substitute_relation
export flatten, connection_graph, entity_connections
export validate
export validate_diagnostics, diagnostic_message, diagnostic_messages, diagnostic_to_dict
export print_model_info
export Port, Parameter, Relation, RelationKind, Equation, Behavioral, Event
export EntityDef, Connection, ComposeDef
export DiagnosticSpan, Diagnostic, DiagnosticError, throw_diagnostic
export DIAG_ERROR, DIAG_WARNING, DIAG_INFO
export PHASE_RESOLVE, PHASE_SEMANTIC_VALIDATION, PHASE_TOPOLOGY_VALIDATION
export E_NAME_DUPLICATE_PORT, E_NAME_DUPLICATE_RELATION, E_NAME_DUPLICATE_PARAMETER
export E_NAME_DUPLICATE_ENTITY, E_TOPOLOGY_UNKNOWN_ENTITY, E_PORT_INVALID_REFERENCE
export E_TOPOLOGY_INVALID_DIRECTION
export E_SYNTAX_UNSUPPORTED_PORT, E_SYNTAX_UNSUPPORTED_PARAM, E_SYNTAX_MISSING_RELATION_NAME
export E_SYNTAX_UNSUPPORTED_ENTITY, E_SYNTAX_UNSUPPORTED_CONNECT
export E_SOLVER_UNKNOWN, E_SOLVER_NOT_FOUND
export E_ODE_UNSUPPORTED_EXPRESSION, E_ODE_UNKNOWN_FUNCTION, E_ODE_UNSUPPORTED_LITERAL
export E_ODE_STACK_DEPTH_INVALID, E_ODE_EXPECTED_NUMBER, E_ODE_EXPECTED_BOOL
export E_ODE_STACK_UNDERFLOW, E_ODE_UNKNOWN_CONSTANT
export E_PARAM_MISSING_DEFAULT, E_STATE_MISSING_INITIAL_VALUE
export E_RUNTIME_SEND_OUTSIDE_SIMULATION, E_RUNTIME_UNKNOWN_AGENT, E_RUNTIME_UNHANDLED
export diagnostic_from_exception
export register_port_macro, register_relation_macro, register_param_macro
export AbstractSolver, ODESolver, MTKODESolver, DEODESolver, DESolver, HybridSolver, SimResult
export solve, can_solve, compile_ode, compile_relation
export register_solver!, select_solver, available_solvers
export AbstractExecutionIR, AbstractExecutionRuntime
export CompiledODEModel, ODERuntimeBuffers, compile_ode_ir, ode_rhs!
export Message, send!
export TopologySummary, topology_summary, topology_metrics, shortest_entity_path
export entity_table, write_entity_table_csv
export degree_distribution, sample_parameter
export nautical_miles, knots, voyage_duration, nautical_miles_to_km
export route_distance, coordinate_distance_km
export optimize_scalar

# ============================================================
# 协议层导出
# ============================================================
export SimState, EngineCommand
export AbstractSimTransport, FileTransport
export make_sim_state, serialize_history
export serialize_state, deserialize_command
export broadcast_state, send_command
export compute_diff, write_states_to_file
export make_error_state, diagnostic_payload, exception_payload

end # module AnySim
