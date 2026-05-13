// ============================================================
// serializer.ts — 前端数据转换/缓存层
//
// 将后端发来的原始 JSON 转换为前端组件可消费的类型。
// 核心功能：
//   1. SimStateMessage → Map<entity, entity_state> 缓存
//   2. SimStateDeltaMessage → 增量合并到缓存
//   3. 原始字段名 (_phase, _sigma) → 前端友好的形式
// ============================================================

import type {
  SimStateMessage,
  SimStateDeltaMessage,
  EntityState,
  FieldValue,
} from './types'

function cloneFieldValue(value: FieldValue): FieldValue {
  if (Array.isArray(value)) {
    return value.map((item) => cloneFieldValue(item as FieldValue)) as FieldValue
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value as Record<string, FieldValue>).map(([key, nested]) => [key, cloneFieldValue(nested)]),
    ) as FieldValue
  }

  return value
}

function cloneEntityState(state: EntityState): EntityState {
  return Object.fromEntries(Object.entries(state).map(([key, value]) => [key, cloneFieldValue(value)])) as EntityState
}

function clonePartialEntityState(state: Partial<EntityState>): Partial<EntityState> {
  return Object.fromEntries(
    Object.entries(state)
      .filter(([, value]) => value !== undefined)
      .map(([key, value]) => [key, cloneFieldValue(value as FieldValue)]),
  ) as Partial<EntityState>
}

/**
 * 实体状态缓存。
 * 维护所有实体的最新状态快照。
 * 支持增量合并：只更新有变化的字段。
 */
export class EntityCache {
  /** entity_name → entity_state */
  private cache = new Map<string, EntityState>()
  private _time = 0
  private _step = 0

  get time(): number {
    return this._time
  }
  get step(): number {
    return this._step
  }

  /** 应用全量更新 */
  applyFull(msg: SimStateMessage): void {
    this._time = msg.time
    this._step = msg.step
    this.cache.clear()
    for (const [name, state] of Object.entries(msg.entities)) {
      this.cache.set(name, cloneEntityState(state))
    }
  }

  /** 应用增量更新 */
  applyDelta(msg: SimStateDeltaMessage): void {
    this._time = msg.time
    this._step = msg.step
    for (const [name, changes] of Object.entries(msg.changed)) {
      const existing = this.cache.get(name) ?? {}
      this.cache.set(name, { ...cloneEntityState(existing), ...clonePartialEntityState(changes) } as EntityState)
    }
  }

  /** 生成当前缓存的拷贝，避免原地修改影响 React 状态更新 */
  clone(): EntityCache {
    const copy = new EntityCache()
    copy.cache = new Map(Array.from(this.cache.entries(), ([name, state]) => [name, cloneEntityState(state)]))
    copy._time = this._time
    copy._step = this._step
    return copy
  }

  /** 获取实体状态 */
  getEntity(name: string): EntityState | undefined {
    return this.cache.get(name)
  }

  /** 获取所有实体 */
  getAllEntities(): Map<string, EntityState> {
    return new Map(this.cache)
  }

  /** 获取实体数量 */
  get entityCount(): number {
    return this.cache.size
  }

  /** 获取所有状态变量名 */
  get fields(): Set<string> {
    const fields = new Set<string>()
    for (const state of this.cache.values()) {
      for (const key of Object.keys(state)) {
        fields.add(key)
      }
    }
    return fields
  }

  /** 按字段类型过滤实体 */
  getEntitiesByField(field: string): Map<string, FieldValue> {
    const result = new Map<string, FieldValue>()
    for (const [name, state] of this.cache) {
      if (field in state) {
        result.set(name, state[field])
      }
    }
    return result
  }

  /** 重置缓存 */
  clear(): void {
    this.cache.clear()
    this._time = 0
    this._step = 0
  }
}

/**
 * 字段名转换工具。
 * 下划线前缀 → 中文友好名称。
 */
export function fieldDisplayName(field: string): string {
  const map: Record<string, string> = {
    _phase: '阶段',
    _sigma: '时间推进',
    _inbox: '收件箱',
    _outbox: '发件箱',
  }
  return map[field] ?? field
}

/**
 * Symbol 类型字段的值显示转换。
 */
export function formatSymbolValue(value: string): string {
  // 去除下划线前缀
  return value.replace(/^_/, '')
}
