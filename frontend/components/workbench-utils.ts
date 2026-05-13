export type SurfaceMode = 'split' | 'canvas' | 'code'

export function sanitizeIdentifier(value: string) {
  return value.replace(/[^A-Za-z0-9_]/g, '_')
}

export function formatValue(value: unknown) {
  if (typeof value === 'number') {
    return Number.isInteger(value) ? String(value) : value.toFixed(2)
  }
  if (typeof value === 'string') {
    return value
  }
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false'
  }
  if (value === null || value === undefined) {
    return 'null'
  }
  return JSON.stringify(value)
}
