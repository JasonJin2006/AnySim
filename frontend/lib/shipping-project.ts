export interface ShippingProjectScenario {
  id: string
  label: string
  configPath: string
  config: Record<string, unknown>
  content: string
}

export interface ShippingProjectFile {
  id: string
  label: string
  path: string
  group: 'manifest' | 'docs' | 'scenarios'
  language: 'json' | 'markdown'
  description: string
  content: string
}

export const shippingProjectRoot = 'examples/shipping-liner-demo'

export const shippingProjectManifest = {
  schema_version: '0.2',
  project_id: 'shipping-liner-demo',
  name: 'Shipping Liner Demo',
  description: 'A packaged liner-shipping example project built on top of the Shipping and DEVS extensions.',
  runtime: {
    solver_extension: 'devs',
    domain_extension: 'shipping',
  },
  entrypoint: {
    type: 'preset',
    preset_id: 'shipping-liner-demo::aeu3-single-vessel',
  },
  model_files: [
    'model/world.jl',
    'model/optimization.jl',
    'model/decision_interface.jl',
    'model/simulation_bridge.jl',
    'model/analysis.jl',
  ],
  data: {
    route_schedule: './data/\u822a\u7ebf\u8239\u671f_20260507_ych.csv',
    od_demand: './data/od\u5bf9\u9700\u6c42_20260507_ych.csv',
  },
  scenarios: [
    {
      id: 'baseline',
      label: 'Baseline',
      config_path: './scenarios/baseline.json',
    },
    {
      id: 'aeu3-single-vessel',
      label: 'AEU3 Single Vessel',
      config_path: './scenarios/aeu3-single-vessel.json',
    },
    {
      id: 'aeu3-disrupted',
      label: 'AEU3 Disrupted',
      config_path: './scenarios/aeu3-disrupted.json',
    },
  ],
  views: [
    {
      id: 'shipping-network',
      label: 'Route Network',
      placement: 'workspace',
      source: 'views/ShippingNetworkView.tsx',
    },
    {
      id: 'port-kpi-panel',
      label: 'Port KPIs',
      placement: 'dock',
      source: 'views/PortKpiPanel.tsx',
    },
    {
      id: 'vessel-timeline',
      label: 'Vessel Timeline',
      placement: 'workspace',
      source: 'views/VesselTimelineView.tsx',
    },
    {
      id: 'experiment-result',
      label: 'Experiment Result',
      placement: 'workspace',
      source: 'views/ExperimentResultView.tsx',
    },
  ],
  kpis: ['ports-online', 'live-vessels'],
} as const

export const shippingProjectReadme = `# Shipping Liner Demo

This folder is an example AnySim project package.

It shows how a user-facing project keeps its modeling assets together while relying on installed platform extensions:

- \`DEVS\` provides the solver/runtime.
- \`Shipping\` provides the domain library, preset builder, views, and KPIs.

## Layout

- \`anysim-project.json\`: project manifest
- \`data/\`: project-bound input data references or copied inputs
- \`scenarios/\`: scenario-level config overrides
- \`docs/\`: project notes and modeling assumptions

## Run

From the repo root:

\`\`\`powershell
julia bin/anysim-server.jl --project examples/shipping-liner-demo
\`\`\`

The server will load the project manifest, resolve the \`shipping-single-vessel\` preset, and apply the first scenario config by default.

## First Milestone

The first packaged milestone is \`AEU3\` single-vessel baseline validation:

- one route
- one vessel
- schedule-driven arrival/departure events
- port statistics suitable for later KPI and export work
`

export const shippingProjectNotes = `# Modeling Notes

- This project uses bundled route schedule and OD demand data.
- The project manifest points to Shipping extension assets rather than redefining solver internals locally.
- Future project-specific model files can live under \`model/\` once project-authored model composition is enabled.
`

export const shippingProjectScenarios: ShippingProjectScenario[] = [
  {
    id: 'baseline',
    label: 'Baseline',
    configPath: './scenarios/baseline.json',
    config: {
      weeks_to_sim: 8,
      vessels_per_route: 5,
      first_week: 51,
      seed: 42,
    },
    content: `{
  "weeks_to_sim": 8,
  "vessels_per_route": 5,
  "first_week": 51,
  "seed": 42
}`,
  },
  {
    id: 'aeu3-single-vessel',
    label: 'AEU3 Single Vessel',
    configPath: './scenarios/aeu3-single-vessel.json',
    config: {
      route_id: 'AEU3',
      first_week: 51,
      max_sim_time: 200,
    },
    content: `{
  "route_id": "AEU3",
  "first_week": 51,
  "max_sim_time": 200.0
}`,
  },
  {
    id: 'aeu3-disrupted',
    label: 'AEU3 Disrupted',
    configPath: './scenarios/aeu3-disrupted.json',
    config: {
      route_id: 'AEU3',
      disruption_level: 1.0,
      first_week: 51,
      max_sim_time: 250,
    },
    content: `{
  "scenario_id": "aeu3-disrupted",
  "description": "AEU3 single vessel with moderate disruption for robustness evaluation",
  "route_id": "AEU3",
  "disruption_level": 1.0,
  "first_week": 51,
  "max_sim_time": 250.0
}`,
  },
]

export const shippingProjectFiles: ShippingProjectFile[] = [
  {
    id: 'project-manifest',
    label: 'anysim-project.json',
    path: 'examples/shipping-liner-demo/anysim-project.json',
    group: 'manifest',
    language: 'json',
    description: 'Project manifest describing runtime extensions, entrypoint preset, scenarios and registered views.',
    content: `{
  "schema_version": "0.2",
  "project_id": "shipping-liner-demo",
  "name": "Shipping Liner Demo",
  "description": "A packaged liner-shipping example project built on top of the Shipping and DEVS extensions.",
  "runtime": {
    "solver_extension": "devs",
    "domain_extension": "shipping"
  },
  "entrypoint": {
    "type": "preset",
    "preset_id": "shipping-single-vessel"
  },
  "model_files": [
    "model/world.jl",
    "model/optimization.jl",
    "model/decision_interface.jl",
    "model/simulation_bridge.jl",
    "model/analysis.jl"
  ],
  "data": {
    "route_schedule": "../../data/shipping/\\u822a\\u7ebf\\u8239\\u671f_20260507_ych.csv",
    "od_demand": "../../data/shipping/od\\u5bf9\\u9700\\u6c42_20260507_ych.csv"
  },
  "scenarios": [
    {
      "id": "baseline",
      "label": "Baseline",
      "config_path": "./scenarios/baseline.json"
    },
    {
      "id": "aeu3-single-vessel",
      "label": "AEU3 Single Vessel",
      "config_path": "./scenarios/aeu3-single-vessel.json"
    },
    {
      "id": "aeu3-disrupted",
      "label": "AEU3 Disrupted",
      "config_path": "./scenarios/aeu3-disrupted.json"
    }
  ],
  "views": [
    {
      "id": "shipping-network",
      "label": "Route Network",
      "placement": "workspace",
      "source": "views/ShippingNetworkView.tsx"
    },
    {
      "id": "port-kpi-panel",
      "label": "Port KPIs",
      "placement": "dock",
      "source": "views/PortKpiPanel.tsx"
    },
    {
      "id": "vessel-timeline",
      "label": "Vessel Timeline",
      "placement": "workspace",
      "source": "views/VesselTimelineView.tsx"
    },
    {
      "id": "experiment-result",
      "label": "Experiment Result",
      "placement": "workspace",
      "source": "views/ExperimentResultView.tsx"
    }
  ],
  "kpis": [
    "ports-online",
    "live-vessels"
  ]
}`,
  },
  {
    id: 'project-readme',
    label: 'README.md',
    path: 'examples/shipping-liner-demo/README.md',
    group: 'docs',
    language: 'markdown',
    description: 'How the shipping example is packaged and launched.',
    content: shippingProjectReadme,
  },
  {
    id: 'modeling-notes',
    label: 'modeling-notes.md',
    path: 'examples/shipping-liner-demo/docs/modeling-notes.md',
    group: 'docs',
    language: 'markdown',
    description: 'Project-specific modeling notes and assumptions.',
    content: shippingProjectNotes,
  },
  {
    id: 'scenario-baseline',
    label: 'baseline.json',
    path: 'examples/shipping-liner-demo/scenarios/baseline.json',
    group: 'scenarios',
    language: 'json',
    description: 'Baseline scenario overrides for multi-vessel planning.',
    content: shippingProjectScenarios[0].content,
  },
  {
    id: 'scenario-aeu3-single-vessel',
    label: 'aeu3-single-vessel.json',
    path: 'examples/shipping-liner-demo/scenarios/aeu3-single-vessel.json',
    group: 'scenarios',
    language: 'json',
    description: 'Single-vessel AEU3 validation scenario.',
    content: shippingProjectScenarios[1].content,
  },
  {
    id: 'scenario-aeu3-disrupted',
    label: 'aeu3-disrupted.json',
    path: 'examples/shipping-liner-demo/scenarios/aeu3-disrupted.json',
    group: 'scenarios',
    language: 'json',
    description: 'AEU3 single vessel with moderate disruption for robustness evaluation.',
    content: shippingProjectScenarios[2].content,
  },
]

export function getShippingProjectFileById(id: string): ShippingProjectFile | null {
  return shippingProjectFiles.find((file) => file.id === id) ?? null
}

export function getShippingProjectScenarioById(id: string): ShippingProjectScenario | null {
  return shippingProjectScenarios.find((scenario) => scenario.id === id) ?? null
}
