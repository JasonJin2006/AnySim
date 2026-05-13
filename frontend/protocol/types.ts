// ============================================================
// types.ts — AnySim 前端协议类型定义
//
// 与 Julia 后端协议层的 TypeScript 对应。
// 不绑定任何 UI 框架——纯数据定义。
// ============================================================

// === 仿真命令（前端 → 后端） ===

export type SimCommand =
  | { cmd: 'start'; payload?: { max_steps?: number; max_time?: number } }
  | { cmd: 'pause' }
  | { cmd: 'resume' }
  | { cmd: 'reset' }
  | { cmd: 'set_speed'; payload: { speed: number } }
  | { cmd: 'step' }
  | { cmd: 'simulate' }
  | { cmd: 'get_status' }
  | { cmd: 'get_entities' }
  | { cmd: 'get_presets' }
  | { cmd: 'get_outputs' }
  | { cmd: 'load_preset'; payload: { preset_id: string; config?: Record<string, unknown> } }
  | { cmd: 'set_config'; payload: { params: Record<string, Record<string, unknown>> } }
  // 新架构命令
  | { cmd: 'run_experiment'; payload: ExperimentPayload }
  | { cmd: 'run_comparison'; payload: ComparisonPayload }
  | { cmd: 'run_robustness'; payload: RobustnessPayload }
  | { cmd: 'get_experiment_result' }

// === 状态消息（后端 → 前端） ===

/** 全量状态更新 */
export interface SimStateMessage {
  type: 'sim_state'
  time: number
  entities: Record<string, EntityState>
  entity_count: number
  step: number
}

/** 增量状态更新 */
export interface SimStateDeltaMessage {
  type: 'sim_state_delta'
  time: number
  changed: Record<string, Partial<EntityState>>
  changed_count: number
  step: number
}

/** 单个实体的状态快照 */
export interface EntityState {
  [field: string]: FieldValue
}

export type FieldValue =
  | number
  | string
  | boolean
  | null
  | FieldValue[]
  | { [key: string]: FieldValue }

/** 确认响应 */
export interface AckMessage {
  type: 'ack'
  cmd: string
  success: boolean
  [key: string]: unknown
}

/** 错误响应 */
export interface ErrorMessage {
  type: 'error'
  msg: string
}

/** 状态查询响应 */
export interface StatusMessage {
  type: 'status'
  data: RunnerStatus
}

/** 实体查询响应 */
export interface EntitiesMessage {
  type: 'entities'
  data: ModelEntities
}

export interface PresetInfo {
  id: string
  label: string
  extension_id: string
  model_key: string
  description?: string
}

export interface PresetsMessage {
  type: 'presets'
  data: {
    items: PresetInfo[]
  }
}

export interface OutputPortInfo {
  id: string
  label: string
  kind: string
  updated_at?: number
  data: Record<string, unknown>
}

export interface OutputsMessage {
  type: 'outputs'
  data: {
    items: OutputPortInfo[]
  }
}

export type SimMessage =
  | SimStateMessage
  | SimStateDeltaMessage
  | AckMessage
  | ErrorMessage
  | StatusMessage
  | EntitiesMessage
  | PresetsMessage
  | OutputsMessage
  | ExperimentResultMessage

// === 新架构：实验相关类型 ===

export type DecisionModelName = 'TimeSpaceMILP' | 'SimpleDirectAllocation' | 'GreedyHeuristic'

export interface ExperimentPayload {
  decision_model: DecisionModelName
  scenario_id?: string
  disruption_level?: number
  demand_multiplier?: number
  capacity_multiplier?: number
  max_time?: number
  max_steps?: number
  schedule_file?: string
  od_file?: string
}

export interface ComparisonPayload {
  models: DecisionModelName[]
  scenario_id?: string
  disruption_level?: number
  demand_multiplier?: number
  capacity_multiplier?: number
  max_time?: number
  max_steps?: number
}

export interface RobustnessPayload {
  decision_model: DecisionModelName
  disruption_levels: number[]
  scenario_id?: string
  demand_multiplier?: number
  capacity_multiplier?: number
  max_time?: number
  max_steps?: number
}

export interface KpiData {
  planned_profit: number
  simulated_profit: number
  profit_retention_rate: number
  accepted_cargo_ffe: number
  delivered_cargo_ffe: number
  on_time_delivery_rate: number
  avg_transit_time: number
  avg_utilization: number
  max_arc_utilization: number
  service_reliability: number
  rejection_rate: number
}

export interface EconomicBreakdownData {
  cargo_revenue: number
  fleet_deployment_cost: number
  sea_transport_cost: number
  port_handling_cost: number
  late_penalty: number
  net_profit: number
}

export interface TimeSeriesPointData {
  metric_name: string
  unit: string
  points: [number, number, string][]  // [time, value, label]
}

export interface ExperimentSummaryData {
  experiment_id: string
  model_name: string
  scenario_id: string
  disruption_level: number
  kpi: KpiData
  demand_outcomes_count: number
  on_time_count: number
  delivered_count: number
  economic_breakdown: EconomicBreakdownData
  time_series_metrics: string[]
  time_series?: Record<string, TimeSeriesPointData>
  robustness?: RobustnessData
  comparison?: ExperimentSummaryData[]
}

export interface RobustnessData {
  model_name: string
  disruption_levels: number[]
  profits: number[]
  on_time_rates: number[]
  reliability_rates: number[]
  rejection_rates: number[]
  profit_retention: number
  on_time_degradation_slope: number
  reliability_degradation_slope: number
  robustness_score: number
}

export interface ExperimentResultMessage {
  type: 'experiment_result'
  data: ExperimentSummaryData | { error: string }
}

// === 仿真运行器状态 ===

export interface RunnerStatus {
  running: boolean
  paused: boolean
  speed: number
  current_time: number
  step_count: number
  max_steps: number
  max_time: number
  entity_count: number
  model_loaded: boolean
  preset_id?: string
  project_path?: string
}

// === 模型结构 ===

export interface ModelEntities {
  model_name: string
  entity_count: number
  preset_id?: string
  project_path?: string
  entities: EntityInfo[]
}

export interface EntityInfo {
  name: string
  port_count: number
  relation_count: number
  parameter_count: number
  parameters: ParamInfo[]
}

export interface ParamInfo {
  name: string
  type: string
  has_default: boolean
}
