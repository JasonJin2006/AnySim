// ============================================================
// transport.ts — Frontend transport layer abstraction
//
// Defines the abstract transport interface supporting multiple backends:
//   - WebSocketTransport: real-time simulation (default)
//   - HttpTransport: pure REST polling (fallback)
//   - MockTransport: mock data for development/testing
//
// Usage:
//   const transport = new WebSocketTransport("ws://localhost:8080/ws/sim")
//   transport.onMessage = (msg) => { ... }
//   transport.connect()
//   transport.send({ cmd: "start" })
// ============================================================

import type { EntityInfo, EntityState, PresetInfo, SimCommand, SimMessage } from './types'
import { shippingProjectManifest, shippingProjectScenarios } from '@/lib/shipping-project'

/** Build PresetInfo[] from project manifest scenarios */
function buildPresetsFromManifest(): PresetInfo[] {
  const projectId = shippingProjectManifest.project_id
  return shippingProjectManifest.scenarios.map((scenario) => ({
    id: `${projectId}::${scenario.id}`,
    label: scenario.label,
    extension_id: 'shipping',
    model_key: `shipping-${scenario.id}`,
    description: `Scenario: ${scenario.label}`,
  }))
}

/** Build scenario config map for mock transport */
function buildProjectScenarios(): Record<string, Record<string, unknown>> {
  const result: Record<string, Record<string, unknown>> = {}
  for (const scenario of shippingProjectScenarios) {
    result[scenario.id] = scenario.config
  }
  return result
}

/** 传输层抽象接口 */
export interface Transport {
  /** 连接后端 */
  connect(): void
  /** 断开连接 */
  disconnect(): void
  /** 发送命令 */
  send(cmd: SimCommand): void
  /** 是否已连接 */
  get connected(): boolean
  /** 消息回调 */
  onMessage: ((msg: SimMessage) => void) | null
  /** 错误回调 */
  onError: ((err: Error) => void) | null
  /** 连接状态变化回调 */
  onStatusChange: ((connected: boolean) => void) | null
}

// ============================================================
// WebSocketTransport — 实时 WebSocket 通信
// ============================================================

export class WebSocketTransport implements Transport {
  private ws: WebSocket | null = null
  private url: string
  private reconnectAttempts = 0
  private maxReconnectAttempts = 5
  private reconnectDelay = 1000
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private _connected = false

  onMessage: ((msg: SimMessage) => void) | null = null
  onError: ((err: Error) => void) | null = null
  onStatusChange: ((connected: boolean) => void) | null = null

  constructor(url: string) {
    this.url = url
  }

  get connected(): boolean {
    return this._connected
  }

  connect(): void {
    if (this.ws?.readyState === WebSocket.OPEN) return

    try {
      this.ws = new WebSocket(this.url)
    } catch (err) {
      this.handleError(err as Error)
      return
    }

    this.ws.onopen = () => {
      this._connected = true
      this.reconnectAttempts = 0
      this.onStatusChange?.(true)
    }

    this.ws.onclose = () => {
      this._connected = false
      this.onStatusChange?.(false)
      this.tryReconnect()
    }

    this.ws.onerror = () => {
      this.handleError(new Error(`WebSocket connection failed: ${this.url}`))
    }

    this.ws.onmessage = (event: MessageEvent) => {
      try {
        const msg = JSON.parse(event.data) as SimMessage
        this.onMessage?.(msg)
      } catch (err) {
        console.warn('[Transport] JSON parse failed:', err, event.data)
      }
    }
  }

  disconnect(): void {
    this.reconnectAttempts = this.maxReconnectAttempts // prevent reconnect
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    this.ws?.close()
    this.ws = null
    this._connected = false
    this.onStatusChange?.(false)
  }

  send(cmd: SimCommand): void {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      this.handleError(new Error('WebSocket not connected'))
      return
    }
    this.ws.send(JSON.stringify(cmd))
  }

  private tryReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) return
    this.reconnectAttempts++
    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1)
    console.log(`[Transport] ${this.reconnectAttempts}/${this.maxReconnectAttempts} reconnecting (${delay}ms)...`)
    this.reconnectTimer = setTimeout(() => {
      this.connect()
    }, delay)
  }

  private handleError(err: Error): void {
    console.error('[Transport]', err.message)
    this.onError?.(err)
  }
}

// ============================================================
// HttpTransport — 纯 HTTP 轮询（降级方案）
//
// 适用于后端不支持 WebSocket 的场景。
// 每 100ms 轮询 /api/sim/status，性能较低。
// ============================================================

export class HttpTransport implements Transport {
  private baseUrl: string
  private pollTimer: ReturnType<typeof setTimeout> | null = null
  private readonly basePollInterval = 250 // ms
  private readonly maxPollInterval = 5000 // ms
  private currentPollInterval = this.basePollInterval
  private _connected = false
  private stopped = false

  onMessage: ((msg: SimMessage) => void) | null = null
  onError: ((err: Error) => void) | null = null
  onStatusChange: ((connected: boolean) => void) | null = null

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl.replace(/\/$/, '')
  }

  get connected(): boolean {
    return this._connected
  }

  connect(): void {
    this.stopped = false
    this.clearPollTimer()
    this.checkHealth()
    this.scheduleNextPoll(0)
  }

  disconnect(): void {
    this.stopped = true
    this.clearPollTimer()
    this._connected = false
    this.currentPollInterval = this.basePollInterval
    this.onStatusChange?.(false)
  }

  send(cmd: SimCommand): void {
    const body = JSON.stringify(cmd)
    const url = cmd.cmd === 'start' ? `${this.baseUrl}/api/sim/run` : `${this.baseUrl}/api/sim/${cmd.cmd}`
    fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body })
      .then((res) => res.json())
      .then((data) => {
        this.onMessage?.({ type: 'ack', cmd: cmd.cmd, success: true, ...data })
      })
      .catch((err) => this.handleError(err))
  }

  private async checkHealth(): Promise<void> {
    try {
      const res = await fetch(`${this.baseUrl}/api/health`)
      if (res.ok) {
        this._connected = true
        this.currentPollInterval = this.basePollInterval
        this.onStatusChange?.(true)
      }
    } catch {
      this._connected = false
      this.onStatusChange?.(false)
    }
  }

  private async pollStatus(): Promise<void> {
    if (this.stopped) return

    try {
      const res = await fetch(`${this.baseUrl}/api/sim/status`)
      if (res.ok) {
        if (!this._connected) {
          this._connected = true
          this.onStatusChange?.(true)
        }
        this.currentPollInterval = this.basePollInterval
        const data = await res.json()
        this.onMessage?.({ type: 'status', data })
      } else {
        this.handlePollFailure()
      }
    } catch {
      this.handlePollFailure()
    } finally {
      if (!this.stopped) {
        this.scheduleNextPoll(this.currentPollInterval)
      }
    }
  }

  private handleError(err: Error): void {
    console.error('[HttpTransport]', err.message)
    this.onError?.(err)
  }

  private scheduleNextPoll(delay: number): void {
    this.clearPollTimer()
    this.pollTimer = setTimeout(() => {
      void this.pollStatus()
    }, delay)
  }

  private clearPollTimer(): void {
    if (this.pollTimer) {
      clearTimeout(this.pollTimer)
      this.pollTimer = null
    }
  }

  private handlePollFailure(): void {
    if (this._connected) {
      this._connected = false
      this.onStatusChange?.(false)
    }
    this.currentPollInterval = Math.min(this.currentPollInterval * 2, this.maxPollInterval)
  }
}

// ============================================================
// MockTransport — 测试/开发用模拟数据
//
// 精简版：只提供基础仿真协议的模拟，
// 新架构命令 (run_experiment 等) 返回模拟实验结果。
// ============================================================

export class MockTransport implements Transport {
  private timer: ReturnType<typeof setInterval> | null = null
  private time = 0
  private _connected = false
  private speed = 1
  private activePresetId = 'aeu3-single-vessel'
  private readonly presets: PresetInfo[] = buildPresetsFromManifest()

  private readonly projectScenarios = buildProjectScenarios()

  onMessage: ((msg: SimMessage) => void) | null = null
  onError: ((err: Error) => void) | null = null
  onStatusChange: ((connected: boolean) => void) | null = null

  get connected(): boolean {
    return this._connected
  }

  connect(): void {
    this._connected = true
    this.onStatusChange?.(true)
  }

  disconnect(): void {
    this._connected = false
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
    this.onStatusChange?.(false)
  }

  send(cmd: SimCommand): void {
    switch (cmd.cmd) {
      case 'start':
      case 'simulate':
        this.startMockSim()
        this.onMessage?.({ type: 'ack', cmd: cmd.cmd, success: true })
        break
      case 'pause':
        this.stopMockSim()
        this.onMessage?.({ type: 'ack', cmd: cmd.cmd, success: true })
        break
      case 'reset':
        this.time = 0
        this.stopMockSim()
        this.onMessage?.({ type: 'ack', cmd: cmd.cmd, success: true })
        break
      case 'set_speed':
        this.speed = cmd.payload.speed
        this.onMessage?.({ type: 'ack', cmd: cmd.cmd, success: true, speed: this.speed })
        break
      case 'get_status':
        this.onMessage?.({
          type: 'status',
          data: {
            running: this.timer !== null,
            paused: false,
            speed: this.speed,
            current_time: this.time,
            step_count: Math.floor(this.time),
            max_steps: 10000,
            max_time: 1e6,
            entity_count: 0,
            model_loaded: true,
          },
        })
        break
      case 'get_presets':
        this.onMessage?.({
          type: 'presets',
          data: { items: [...this.presets] },
        })
        break
      case 'get_outputs':
        this.onMessage?.({
          type: 'outputs',
          data: { items: [] },
        })
        break
      case 'get_entities':
        this.onMessage?.({
          type: 'entities',
          data: {
            model_name: 'ShippingNetworkDemo',
            entity_count: 0,
            entities: [],
          },
        })
        break
      case 'load_preset':
        this.activePresetId = cmd.payload.preset_id
        this.time = 0
        this.stopMockSim()
        this.onMessage?.({
          type: 'ack',
          cmd: cmd.cmd,
          success: true,
          preset_id: this.activePresetId,
          model_name: 'ShippingNetworkDemo',
        })
        break
      // 新架构命令
      case 'run_experiment':
        this.onMessage?.({ type: 'ack', cmd: cmd.cmd, success: true })
        this.onMessage?.({
          type: 'experiment_result',
          data: this.buildMockExperimentResult(cmd.payload.decision_model ?? 'SimpleDirectAllocation'),
        })
        break
      case 'run_comparison':
        this.onMessage?.({ type: 'ack', cmd: cmd.cmd, success: true })
        this.onMessage?.({
          type: 'experiment_result',
          data: this.buildMockComparisonResult(cmd.payload.models ?? ['SimpleDirectAllocation', 'GreedyHeuristic']),
        })
        break
      case 'run_robustness':
        this.onMessage?.({ type: 'ack', cmd: cmd.cmd, success: true })
        this.onMessage?.({
          type: 'experiment_result',
          data: this.buildMockRobustnessResult(cmd.payload.decision_model ?? 'SimpleDirectAllocation'),
        })
        break
      case 'get_experiment_result':
        this.onMessage?.({
          type: 'experiment_result',
          data: this.buildMockExperimentResult('SimpleDirectAllocation'),
        })
        break
      default:
        this.onMessage?.({ type: 'ack', cmd: cmd.cmd, success: true })
    }
  }

  private startMockSim(): void {
    if (this.timer) return
    this.timer = setInterval(() => {
      this.time += 0.25 * this.speed
      this.onMessage?.({
        type: 'sim_state',
        time: this.time,
        entities: {},
        entity_count: 0,
        step: Math.floor(this.time / 0.25),
      })
    }, 100)
  }

  private stopMockSim(): void {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  private buildMockExperimentResult(modelName: string) {
    return {
      experiment_id: `${modelName}_baseline`,
      model_name: modelName,
      scenario_id: 'baseline',
      disruption_level: 0,
      kpi: {
        planned_profit: 125000 + Math.random() * 50000,
        simulated_profit: 98000 + Math.random() * 40000,
        profit_retention_rate: 0.78 + Math.random() * 0.1,
        accepted_cargo_ffe: 2400 + Math.round(Math.random() * 600),
        delivered_cargo_ffe: 2100 + Math.round(Math.random() * 500),
        on_time_delivery_rate: 0.82 + Math.random() * 0.12,
        avg_transit_time: 18 + Math.random() * 8,
        avg_utilization: 0.65 + Math.random() * 0.2,
        max_arc_utilization: 0.88 + Math.random() * 0.1,
        service_reliability: 0.85 + Math.random() * 0.1,
        rejection_rate: 0.05 + Math.random() * 0.1,
      },
      demand_outcomes_count: 48,
      on_time_count: 38 + Math.round(Math.random() * 8),
      delivered_count: 42 + Math.round(Math.random() * 5),
      economic_breakdown: {
        cargo_revenue: 280000 + Math.random() * 80000,
        fleet_deployment_cost: 85000 + Math.random() * 20000,
        sea_transport_cost: 42000 + Math.random() * 15000,
        port_handling_cost: 18000 + Math.random() * 8000,
        late_penalty: 5000 + Math.random() * 8000,
        net_profit: 98000 + Math.random() * 40000,
      },
      time_series_metrics: ['cumulative_delivered_ffe', 'cumulative_revenue', 'avg_delay_days'],
      time_series: {
        cumulative_delivered_ffe: {
          metric_name: 'cumulative_delivered_ffe',
          unit: 'FFE',
          points: Array.from({ length: 12 }, (_, i) => [i * 7, (i + 1) * 180 + Math.random() * 50, ''] as [number, number, string]),
        },
        cumulative_revenue: {
          metric_name: 'cumulative_revenue',
          unit: 'USD',
          points: Array.from({ length: 12 }, (_, i) => [i * 7, (i + 1) * 22000 + Math.random() * 5000, ''] as [number, number, string]),
        },
        avg_delay_days: {
          metric_name: 'avg_delay_days',
          unit: 'days',
          points: Array.from({ length: 12 }, (_, i) => [i * 7, 1.5 + Math.random() * 3, ''] as [number, number, string]),
        },
      },
    }
  }

  private buildMockComparisonResult(models: string[]) {
    const base = this.buildMockExperimentResult(models[0] ?? 'SimpleDirectAllocation')
    return {
      ...base,
      comparison: models.map((m) => ({
        ...this.buildMockExperimentResult(m),
      })),
    }
  }

  private buildMockRobustnessResult(modelName: string) {
    const base = this.buildMockExperimentResult(modelName)
    const levels = [0, 0.5, 1, 1.5, 2]
    return {
      ...base,
      robustness: {
        model_name: modelName,
        disruption_levels: levels,
        profits: levels.map((l) => base.economic_breakdown.net_profit * Math.max(0.3, 1 - l * 0.2) + Math.random() * 5000),
        on_time_rates: levels.map((l) => Math.max(0.4, base.kpi.on_time_delivery_rate - l * 0.1 + Math.random() * 0.05)),
        reliability_rates: levels.map((l) => Math.max(0.5, base.kpi.service_reliability - l * 0.08 + Math.random() * 0.04)),
        rejection_rates: levels.map((l) => Math.min(0.4, base.kpi.rejection_rate + l * 0.06 + Math.random() * 0.03)),
        profit_retention: 0.62 + Math.random() * 0.15,
        on_time_degradation_slope: -0.08 + Math.random() * 0.04,
        reliability_degradation_slope: -0.06 + Math.random() * 0.03,
        robustness_score: 0.6 + Math.random() * 0.25,
      },
    }
  }
}
