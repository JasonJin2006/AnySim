import type { AnySimExtension, ExtensionPreset } from '../types'
import { PortKpiPanel } from './views/PortKpiPanel'
import { ShippingNetworkView } from './views/ShippingNetworkView'
import { VesselTimelineView } from './views/VesselTimelineView'
import { ExperimentResultView } from './views/ExperimentResultView'
import { shippingProjectManifest, shippingProjectScenarios } from '@/lib/shipping-project'

/** Default view set shared across shipping presets */
const SHIPPING_DEFAULT_VIEWS = ['shipping-network', 'experiment-result', 'port-kpi-panel', 'vessel-timeline']

/** Scenario-specific default config overrides */
const SCENARIO_DEFAULT_CONFIGS: Record<string, Record<string, unknown>> = {
  baseline: {
    vessels_per_route: 5,
    weeks_to_sim: 8,
    first_week: 51,
  },
  'aeu3-single-vessel': {
    route_id: 'AEU3',
    first_week: 51,
    max_sim_time: 200,
  },
  'aeu3-disrupted': {
    route_id: 'AEU3',
    first_week: 51,
    max_sim_time: 250,
    disruption_level: 1.0,
    decision_model: 'TimeSpaceMILP',
    demand_multiplier: 1.0,
    capacity_multiplier: 1.0,
  },
}

/**
 * Build presets dynamically from the project manifest scenarios.
 * Each scenario becomes a preset; the scenario config is merged as defaultConfig.
 */
function buildPresetsFromManifest(): ExtensionPreset[] {
  const scenarios = shippingProjectManifest.scenarios
  return scenarios.map((scenario) => {
    const scenarioConfig = shippingProjectScenarios.find((s) => s.id === scenario.id)?.config
    const defaultConfig = SCENARIO_DEFAULT_CONFIGS[scenario.id] ?? scenarioConfig ?? {}
    // preset_id 必须与后端 Shipping extension_presets 格式一致: "project_id::scenario_id"
    const projectId = shippingProjectManifest.project_id
    return {
      id: `${projectId}::${scenario.id}`,
      label: scenario.label,
      modelKey: `shipping-${scenario.id}`,
      extensionId: 'shipping',
      description: `Scenario: ${scenario.label}`,
      defaultViewIds: SHIPPING_DEFAULT_VIEWS,
      defaultConfig,
    }
  })
}

export const shippingExtension: AnySimExtension = {
  id: 'shipping',
  label: 'Liner Shipping',
  description: 'Shipping scenario pack for routes, ports, vessels, and cargo flow.',
  presets: buildPresetsFromManifest(),
  views: [
    {
      id: 'shipping-network',
      label: 'Route Network',
      placement: 'workspace',
      supports: (ctx) => (ctx as { extensionId?: string }).extensionId === 'shipping' || (ctx.modelName ?? '').toLowerCase().includes('shipping'),
      Component: ShippingNetworkView,
    },

    {
      id: 'port-kpi-panel',
      label: 'Port KPIs',
      placement: 'dock',
      supports: (ctx) => (ctx as { extensionId?: string }).extensionId === 'shipping' || (ctx.modelName ?? '').toLowerCase().includes('shipping'),
      Component: PortKpiPanel,
    },
    {
      id: 'vessel-timeline',
      label: 'Vessel Timeline',
      placement: 'workspace',
      supports: (ctx) => (ctx as { extensionId?: string }).extensionId === 'shipping' || (ctx.modelName ?? '').toLowerCase().includes('shipping'),
      Component: VesselTimelineView,
    },
    {
      id: 'experiment-result',
      label: 'Experiment Result',
      placement: 'workspace',
      supports: (ctx) => (ctx as { extensionId?: string }).extensionId === 'shipping' || (ctx.modelName ?? '').toLowerCase().includes('shipping'),
      Component: ExperimentResultView,
    },
  ],
  kpis: [
    {
      id: 'ports-online',
      label: 'Ports Online',
      compute: (ctx) => {
        const network = ctx.entityCache.getEntity('ShippingNetwork')
        const value = network?.ports_online
        return typeof value === 'number' ? value : null
      },
    },
    {
      id: 'live-vessels',
      label: 'Live Vessels',
      compute: (ctx) => {
        const network = ctx.entityCache.getEntity('ShippingNetwork')
        const value = network?.live_vessels
        return typeof value === 'number' ? value : null
      },
    },
  ],
  config: [
    { key: 'vessels_per_route', label: 'Vessels Per Route', type: 'number', defaultValue: 5, min: 1, max: 30, step: 1 },
    { key: 'weeks_to_sim', label: 'Weeks To Simulate', type: 'number', defaultValue: 8, min: 1, max: 52, step: 1 },
    { key: 'first_week', label: 'First Week', type: 'number', defaultValue: 51, min: 1, max: 53, step: 1 },
    { key: 'disruption_level', label: 'Disruption Level', type: 'number', defaultValue: 0, min: 0, max: 5, step: 0.5 },
    {
      key: 'decision_model',
      label: 'Decision Model',
      type: 'select',
      defaultValue: 'TimeSpaceMILP',
      options: [
        { label: 'Time-Space MILP (Exact)', value: 'TimeSpaceMILP' },
        { label: 'Simple Direct Allocation', value: 'SimpleDirectAllocation' },
        { label: 'Greedy Heuristic', value: 'GreedyHeuristic' },
      ],
    },
    { key: 'demand_multiplier', label: 'Demand Multiplier', type: 'number', defaultValue: 1.0, min: 0.1, max: 5.0, step: 0.1 },
    { key: 'capacity_multiplier', label: 'Capacity Multiplier', type: 'number', defaultValue: 1.0, min: 0.1, max: 5.0, step: 0.1 },
  ],
  entitySemantics: [
    {
      kind: 'network',
      label: 'Shipping Network',
      color: '#0369a1',
      match: (entityName) => entityName === 'ShippingNetwork',
    },
    {
      kind: 'vessel',
      label: 'Vessel',
      color: '#b45309',
      match: (entityName) => entityName.startsWith('Vessel_'),
    },
    {
      kind: 'port',
      label: 'Port',
      color: '#047857',
      match: (entityName) => entityName.startsWith('Port_'),
    },
  ],
}
