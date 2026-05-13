module DEVS

import ..AnySim: AbstractSolver, AbstractExecutionIR, AbstractExecutionRuntime
import ..AnySim: Port, Parameter, Relation, RelationKind, Behavioral, Event, Equation
import ..AnySim: EntityDef, Connection, ComposeDef
import ..AnySim: SimResult, SimState, make_sim_state
import ..AnySim: traverse_entities, flatten, compile_relation
import ..AnySim: register_solver!, can_solve, solve
import ..AnySim: Message, send!

include("execution_ir.jl")
include("runtime.jl")

export @devs_atomic, @devs_coupled
export DEVSSolver, DEVSMessage, DEVSResult, DEVSContext
export INFINITY, PhaseInit, PhaseActive, PhasePassive, PhaseDone
export sigma, set_sigma, hold_in, passivate, activate, continuef
export devs_send!, devs_receive, devs_has_input
export CompiledDEVSModel, DEVSRuntimeState, compile_devs_ir
export DEVSCompileDiagnostics, devs_compile_diagnostics, has_devs_compile_warnings
export init_devs_context, time_advance, route_messages!, devs_step!
export devs_entity_names, devs_entity_state, devs_collect_outputs
export run_server

println("[DEVS] Extension loaded.")

end # module DEVS
