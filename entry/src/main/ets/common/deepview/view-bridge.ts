// Object-typed adapters over views-core: the ArkTS UI layer may not name
// `unknown`, so every dynamic deep-view value crosses this bridge as `Object`
// (absent or failed resolutions arrive as null). Field reads, formula
// resolution, input collection and answer validation all live here so the
// .ets side only ever handles Object / string / number / boolean.
import { ViewNode, isRecord, viewInputs, inputDefault, viewScope, resolve, choiceValue, validateViewAnswer } from './views-core.ts'
import { show } from './formula.ts'

export type ObjMap = Map<string, Object>

export interface AnswerCheck {
  error?: string
  answer?: Record<string, Object>
}

function toRecord(map: ObjMap): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  map.forEach((value: Object, key: string): void => {
    out[key] = value
  })
  return out
}

/** A value worked out with the view's inputs; null when absent or failed. */
export function resolveObj(root: ViewNode, inputs: ObjMap, value: Object | null): Object | null {
  if (value === null) return null
  const resolved = resolve(value, viewScope(root, toRecord(inputs)), null)
  return resolved === undefined || resolved === null ? null : resolved as Object
}

export function resolveString(root: ViewNode, inputs: ObjMap, value: Object | null): string | null {
  const resolved = resolveObj(root, inputs, value)
  return resolved === null ? null : String(resolved)
}

/** Like resolveString, but numbers go through formula.show's formatting. */
export function resolveShow(root: ViewNode, inputs: ObjMap, value: Object | null): string | null {
  const resolved = resolveObj(root, inputs, value)
  if (resolved === null) return null
  return typeof resolved === 'number' ? show(resolved) : String(resolved)
}

export function resolveNumber(root: ViewNode, inputs: ObjMap, value: Object | null, fallback: number): number {
  const resolved = resolveObj(root, inputs, value)
  if (resolved === null) return fallback
  const num = Number(resolved)
  return Number.isFinite(num) ? num : fallback
}

export function asObjectArray(value: Object | null): Object[] | null {
  if (value === null || !Array.isArray(value)) return null
  const out: Object[] = []
  for (const entry of value as Object[]) out.push(entry)
  return out
}

export function resolveArray(root: ViewNode, inputs: ObjMap, value: Object | null): Object[] | null {
  return asObjectArray(resolveObj(root, inputs, value))
}

export function resolveNodes(root: ViewNode, inputs: ObjMap, value: Object | null): ViewNode[] {
  const raw = resolveArray(root, inputs, value)
  if (raw === null) return []
  const out: ViewNode[] = []
  for (const entry of raw) {
    if (isRecord(entry)) out.push(entry as ViewNode)
  }
  return out
}

// --- literal field reads on a node ---

export function hasField(node: ViewNode, key: string): boolean {
  return node[key] !== undefined
}

export function fieldOf(node: ViewNode, key: string): Object | null {
  const value = node[key]
  return value === undefined || value === null ? null : value as Object
}

export function nodeString(node: ViewNode, key: string): string | null {
  const value = node[key]
  return value === undefined || value === null ? null : String(value)
}

export function nodeNumber(node: ViewNode, key: string, fallback: number): number {
  const value = node[key]
  if (value === undefined || value === null) return fallback
  const num = Number(value)
  return Number.isFinite(num) ? num : fallback
}

export function nodeIsTrue(node: ViewNode, key: string): boolean {
  return node[key] === true
}

export function nodeList(node: ViewNode, key: string): ViewNode[] {
  const raw = node[key]
  if (!Array.isArray(raw)) return []
  const out: ViewNode[] = []
  for (const entry of raw) {
    if (isRecord(entry)) out.push(entry as ViewNode)
  }
  return out
}

/** node[first] when present, else node[second]; numbers, 0 for non-finite. */
export function nodeNumberList(node: ViewNode, first: string, second: string): number[] {
  const raw = node[first] !== undefined ? node[first] : node[second]
  if (!Array.isArray(raw)) return []
  const out: number[] = []
  for (const value of raw as Object[]) {
    const num = Number(value)
    out.push(Number.isFinite(num) ? num : 0)
  }
  return out
}

export function asNode(value: Object | null): ViewNode | null {
  return isRecord(value) ? value as ViewNode : null
}

export function choiceOf(option: ViewNode): Object | null {
  const value = choiceValue(option)
  return value === undefined || value === null ? null : value as Object
}

// --- inputs and answers ---

/** The view's input ids mapped to their defaults (undefined defaults skipped). */
export function initialInputs(root: ViewNode): ObjMap {
  const out: ObjMap = new Map<string, Object>()
  for (const node of viewInputs(root)) {
    const fallback = inputDefault(node)
    if (fallback !== undefined && fallback !== null) out.set(String(node['id'] ?? ''), fallback as Object)
  }
  return out
}

export function checkAnswer(root: ViewNode, action: string, values: Record<string, Object>): AnswerCheck {
  const result = validateViewAnswer(root, action, values)
  if (result.answer !== undefined) {
    const answer: Record<string, Object> = {}
    for (const key of Object.keys(result.answer)) {
      const value = result.answer[key]
      answer[key] = (value === undefined || value === null ? '' : value) as Object
    }
    return { answer }
  }
  return { error: result.error }
}
