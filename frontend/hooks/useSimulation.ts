// ============================================================
// useSimulation.ts — 通用仿真状态管理 Hook
//
// 不绑定任何 UI 框架细节（纯 React state 管理）。
// 可被任何组件消费：地图、KPI 面板、模型树等。
//
// 使用方式:
//   const sim = useSimulation()
//   sim.connect("ws://localhost:8080/ws/sim")
//   sim.start()
//   const entities = sim.entities  // EntityCache
// ============================================================

'use client'

import { useState, useCallback, useRef, useEffect } from 'react'
import { WebSocketTransport, HttpTransport, MockTransport } from '../protocol/transport'
import type { Transport } from '../protocol/transport'
import type { SimCommand, SimMessage, ModelEntities, OutputPortInfo, PresetInfo, ExperimentPayload, ComparisonPayload, RobustnessPayload, ExperimentSummaryData } from '../protocol/types'
import { EntityCache } from '../protocol/serializer'

export type SimMode = 'academic' | 'real_time'
export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'error'

export interface SimulationState {
  /** Connection status */
  connectionStatus: ConnectionStatus
  /** Whether connected */
  connected: boolean
  /** Whether simulation is running */
  running: boolean
  /** Whether simulation is paused */
  paused: boolean
  /** Current simulation time */
  currentTime: number
  /** Current step count */
  stepCount: number
  /** Simulation speed multiplier */
  speed: number
  /** Maximum steps */
  maxSteps: number
  /** Maximum time */
  maxTime: number
  /** Simulation mode */
  mode: SimMode
  /** Entity state cache */
  entityCache: EntityCache
  /** Model entity info */
  modelEntities: ModelEntities | null
  /** Available presets */
  presets: PresetInfo[]
  /** Currently active preset */
  activePresetId: string | null
  /** Current project path */
  projectPath: string | null
  /** Output ports */
  outputPorts: OutputPortInfo[]
  /** Experiment result (new architecture) */
  experimentResult: ExperimentSummaryData | null
  /** Error message */
  error: string | null
}

export interface SimulationActions {
  /** Connect to backend (pass URL or "mock" for mock data) */
  connect: (url: string) => void
  /** Disconnect */
  disconnect: () => void
  /** Start simulation */
  start: (maxSteps?: number, maxTime?: number) => void
  /** Pause */
  pause: () => void
  /** Resume */
  resume: () => void
  /** Reset */
  reset: () => void
  /** Set speed */
  setSpeed: (speed: number) => void
  /** Single step */
  step: () => void
  /** Continuous run */
  simulate: () => void
  /** Fetch model entity list */
  fetchEntities: () => void
  /** Fetch available presets */
  fetchPresets: () => void
  /** Fetch output ports */
  fetchOutputs: () => void
  /** Load preset */
  loadPreset: (presetId: string, config?: Record<string, unknown>) => void
  /** Set mode */
  setMode: (mode: SimMode) => void
  /** Update parameters */
  setConfig: (params: Record<string, Record<string, unknown>>) => void
  /** Run experiment (new architecture) */
  runExperiment: (payload: ExperimentPayload) => void
  /** Run model comparison */
  runComparison: (payload: ComparisonPayload) => void
  /** Run robustness analysis */
  runRobustness: (payload: RobustnessPayload) => void
  /** Fetch experiment result */
  fetchExperimentResult: () => void
}

const initialState: SimulationState = {
  connectionStatus: 'disconnected',
  connected: false,
  running: false,
  paused: false,
  currentTime: 0,
  stepCount: 0,
  speed: 1,
  maxSteps: 10000,
  maxTime: 1e6,
  mode: 'academic',
  entityCache: new EntityCache(),
  modelEntities: null,
  presets: [],
  activePresetId: null,
  projectPath: null,
  outputPorts: [],
  experimentResult: null,
  error: null,
}

export function useSimulation(): SimulationState & SimulationActions {
  const [state, setState] = useState<SimulationState>(initialState)
  const transportRef = useRef<Transport | null>(null)
  // Use ref for message handler to avoid stale closure issues
  const handleMessageRef = useRef<((msg: SimMessage) => void) | null>(null)

  const cleanup = useCallback(() => {
    transportRef.current?.disconnect()
    transportRef.current = null
  }, [])

  useEffect(() => {
    return cleanup
  }, [cleanup])

  const update = useCallback((partial: Partial<SimulationState>) => {
    setState((prev) => ({ ...prev, ...partial }))
  }, [])

  // Message handler using functional setState to always read latest state
  // This avoids the stale closure problem where handleMessage captured an outdated entityCache
  handleMessageRef.current = useCallback(
    (msg: SimMessage) => {
      setState((prev) => {
        switch (msg.type) {
          case 'sim_state': {
            const cache = prev.entityCache.clone()
            cache.applyFull(msg)
            return {
              ...prev,
              entityCache: cache,
              currentTime: msg.time,
              stepCount: msg.step,
              running: true,
              error: null,
            }
          }
          case 'sim_state_delta': {
            const cache = prev.entityCache.clone()
            cache.applyDelta(msg)
            return {
              ...prev,
              entityCache: cache,
              currentTime: msg.time,
              stepCount: msg.step,
              running: true,
              error: null,
            }
          }
          case 'ack': {
            if (msg.cmd === 'set_speed' && typeof msg.speed === 'number') {
              return { ...prev, speed: msg.speed }
            }
            return prev
          }
          case 'status': {
            return {
              ...prev,
              running: msg.data.running,
              paused: msg.data.paused,
              currentTime: msg.data.current_time,
              stepCount: msg.data.step_count,
              speed: msg.data.speed,
              maxSteps: msg.data.max_steps,
              maxTime: msg.data.max_time,
              activePresetId: msg.data.preset_id ?? prev.activePresetId,
              projectPath: msg.data.project_path ?? prev.projectPath,
              error: null,
            }
          }
          case 'entities': {
            return {
              ...prev,
              modelEntities: msg.data,
              activePresetId: msg.data.preset_id ?? prev.activePresetId,
              projectPath: msg.data.project_path ?? prev.projectPath,
            }
          }
          case 'presets': {
            return { ...prev, presets: msg.data.items }
          }
          case 'outputs': {
            return { ...prev, outputPorts: msg.data.items }
          }
          case 'experiment_result': {
            const data = msg.data
            if ('error' in data) {
              return { ...prev, error: data.error }
            }
            return { ...prev, experimentResult: data }
          }
          case 'error': {
            return { ...prev, error: msg.msg, running: false, paused: false }
          }
          default:
            return prev
        }
      })
    },
    [],
  )

  // Bridge: transport calls bridgeMessage which delegates to handleMessageRef.current
  // This ensures the transport always calls the latest handler without needing to re-assign onMessage
  const bridgeMessage = useCallback((msg: SimMessage) => {
    handleMessageRef.current?.(msg)
  }, [])

  const connect = useCallback(
    (url: string) => {
      cleanup()
      update({ connectionStatus: 'connecting', error: null })

      let transport: Transport

      if (url === 'mock') {
        transport = new MockTransport()
      } else if (url.startsWith('ws')) {
        transport = new WebSocketTransport(url)
      } else {
        transport = new HttpTransport(url)
      }

      transport.onMessage = bridgeMessage
      transport.onError = (err) => update({ error: err.message, connectionStatus: 'error' })
      transport.onStatusChange = (connected) =>
        update({ connectionStatus: connected ? 'connected' : 'disconnected', connected })

      transport.connect()
      transportRef.current = transport
    },
    [cleanup, update, bridgeMessage],
  )

  const disconnect = useCallback(() => {
    cleanup()
    update(initialState)
  }, [cleanup, update])

  const send = useCallback((cmd: SimCommand) => {
    transportRef.current?.send(cmd)
  }, [])

  const start = useCallback(
    (maxSteps?: number, maxTime?: number) => {
      const payload: { max_steps?: number; max_time?: number } = {}
      if (typeof maxSteps === 'number' && Number.isFinite(maxSteps)) {
        payload.max_steps = maxSteps
      }
      if (typeof maxTime === 'number' && Number.isFinite(maxTime)) {
        payload.max_time = maxTime
      }
      send({ cmd: 'start', payload })
    },
    [send],
  )

  const pause = useCallback(() => send({ cmd: 'pause' }), [send])
  const resume = useCallback(() => send({ cmd: 'resume' }), [send])
  const reset = useCallback(() => {
    update({ entityCache: new EntityCache() })
    send({ cmd: 'reset' })
  }, [send, update])
  const setSpeed = useCallback(
    (speed: number) => send({ cmd: 'set_speed', payload: { speed } }),
    [send],
  )
  const step = useCallback(() => send({ cmd: 'step' }), [send])
  const simulate = useCallback(() => send({ cmd: 'simulate' }), [send])
  const fetchEntities = useCallback(() => send({ cmd: 'get_entities' }), [send])
  const fetchPresets = useCallback(() => send({ cmd: 'get_presets' }), [send])
  const fetchOutputs = useCallback(() => send({ cmd: 'get_outputs' }), [send])
  const loadPreset = useCallback(
    (presetId: string, config?: Record<string, unknown>) => {
      update({
        activePresetId: presetId,
        entityCache: new EntityCache(),
        modelEntities: null,
        outputPorts: [],
      })
      send({ cmd: 'load_preset', payload: { preset_id: presetId, config } })
      send({ cmd: 'get_entities' })
      send({ cmd: 'get_status' })
      send({ cmd: 'get_outputs' })
    },
    [send, update],
  )
  const setMode = useCallback((_mode: SimMode) => {
    // Mode switch: currently a frontend-only marker; backend mode is applied at start time
    update({ mode: _mode })
  }, [update])
  const setConfig = useCallback(
    (params: Record<string, Record<string, unknown>>) => {
      send({ cmd: 'set_config', payload: { params } })
    },
    [send],
  )
  const runExperiment = useCallback(
    (payload: ExperimentPayload) => {
      update({ experimentResult: null, error: null })
      send({ cmd: 'run_experiment', payload })
    },
    [send, update],
  )
  const runComparison = useCallback(
    (payload: ComparisonPayload) => {
      update({ experimentResult: null, error: null })
      send({ cmd: 'run_comparison', payload })
    },
    [send, update],
  )
  const runRobustness = useCallback(
    (payload: RobustnessPayload) => {
      update({ experimentResult: null, error: null })
      send({ cmd: 'run_robustness', payload })
    },
    [send, update],
  )
  const fetchExperimentResult = useCallback(() => send({ cmd: 'get_experiment_result' }), [send])

  return {
    ...state,
    connect,
    disconnect,
    start,
    pause,
    resume,
    reset,
    setSpeed,
    step,
    simulate,
    fetchEntities,
    fetchPresets,
    fetchOutputs,
    loadPreset,
    setMode,
    setConfig,
    runExperiment,
    runComparison,
    runRobustness,
    fetchExperimentResult,
  }
}
