import type { ComponentType } from 'react'
import type { EntityCache } from '@/protocol/serializer'
import type { ModelEntities, OutputPortInfo } from '@/protocol/types'

export type ExtensionId = string
export type ExtensionPlacement = 'workspace' | 'dock' | 'inspector'

export interface ExtensionPreset {
  id: string
  label: string
  modelKey: string
  extensionId: ExtensionId
  description?: string
  defaultViewIds?: string[]
  defaultConfig?: Record<string, unknown>
}

export interface ExtensionRuntimeContext {
  extensionId?: string
  presetId?: string
  modelName?: string
  modelEntities: ModelEntities | null
  entityCache: EntityCache
  outputPorts: OutputPortInfo[]
  runner: {
    running: boolean
    paused: boolean
    currentTime: number
    stepCount: number
    speed: number
  }
}

export interface ExtensionViewProps {
  context: ExtensionRuntimeContext
}

export interface ExtensionKpiDefinition {
  id: string
  label: string
  unit?: string
  description?: string
  compute: (ctx: ExtensionRuntimeContext) => string | number | null
}

export interface ExtensionViewDefinition {
  id: string
  label: string
  placement: ExtensionPlacement
  supports: (ctx: ExtensionRuntimeContext) => boolean
  Component: ComponentType<ExtensionViewProps>
}

export interface ExtensionConfigFieldOption {
  label: string
  value: string | number
}

export interface ExtensionConfigField {
  key: string
  label: string
  type: 'number' | 'select' | 'boolean' | 'text'
  defaultValue?: unknown
  options?: ExtensionConfigFieldOption[]
  min?: number
  max?: number
  step?: number
}

export interface ExtensionEntitySemantic {
  kind: string
  label: string
  color?: string
  match: (entityName: string) => boolean
}

export interface AnySimExtension {
  id: ExtensionId
  label: string
  description?: string
  presets: ExtensionPreset[]
  views: ExtensionViewDefinition[]
  kpis: ExtensionKpiDefinition[]
  config: ExtensionConfigField[]
  entitySemantics?: ExtensionEntitySemantic[]
}
