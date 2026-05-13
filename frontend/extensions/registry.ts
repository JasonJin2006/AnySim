import type { AnySimExtension, ExtensionPreset } from './types'
import { shippingExtension } from './shipping'

const extensions: AnySimExtension[] = [shippingExtension]

export function getExtensions(): AnySimExtension[] {
  return extensions
}

export function getExtensionById(id: string): AnySimExtension | null {
  return extensions.find((extension) => extension.id === id) ?? null
}

export function getAllPresets(): ExtensionPreset[] {
  return extensions.flatMap((extension) => extension.presets)
}

export function getPresetById(id: string): ExtensionPreset | null {
  return getAllPresets().find((preset) => preset.id === id) ?? null
}
