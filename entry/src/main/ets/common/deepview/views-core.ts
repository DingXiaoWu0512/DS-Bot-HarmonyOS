// View cards: the pieces the phone needs — inputs, answers and the answer text.
// Port of deep-view's views.js validation subset and reply.js's viewAnswerText.
import { compileFormula, createScope, evaluate, show, type FormulaNode, type Lookup } from './formula.ts'

const LAYOUT = ['stack', 'row']
const INPUT_TYPES = ['slider', 'choice', 'toggle', 'number']
const ANSWERS = ['options', 'confirm', 'form', 'submit']
const INTERACTIVE = new Set<string>(ANSWERS)
const INPUTS = new Set<string>(INPUT_TYPES)
const MAX_TEXT = 2000

export type ViewNode = Record<string, unknown>

export const isRecord = (value: unknown): boolean =>
  value !== null && typeof value === 'object' && !Array.isArray(value)

const isNumber = (value: unknown): boolean => typeof value === 'number' && Number.isFinite(value)
const quoted = (value: unknown): string => JSON.stringify(value)
const allowed = (list: string[]): string => list.join(', ')

/** `{ "=": "…" }`: a value worked out from the view's inputs. */
export function isFormula(value: unknown): boolean {
  return isRecord(value) && Object.keys(value as ViewNode).length === 1 && '=' in (value as ViewNode)
}

export const choiceValue = (option: unknown): unknown =>
  isRecord(option) ? ((option as ViewNode).value !== undefined ? (option as ViewNode).value : (option as ViewNode).label) : option

function walk(node: unknown, visit: (node: ViewNode) => void): void {
  if (!isRecord(node)) return
  visit(node as ViewNode)
  const children = (node as ViewNode).children
  if (LAYOUT.includes(String((node as ViewNode).type)) && Array.isArray(children)) {
    for (const child of children) walk(child, visit)
  }
}

export function viewInputs(view: unknown): ViewNode[] {
  const found: ViewNode[] = []
  walk(view, node => {
    if (INPUTS.has(String(node.type))) found.push(node)
  })
  return found
}

export function inputDefault(node: ViewNode): unknown {
  if (node.type === 'toggle') return node.value === true
  if (node.type === 'choice') return node.value !== undefined ? node.value : choiceValue(Array.isArray(node.options) ? (node.options as unknown[])[0] : undefined)
  return node.value
}

export function hasInputs(view: unknown): boolean {
  return viewInputs(view).length > 0
}

/** A scope for one view: input values, plus `let` names worked out on demand. */
export function viewScope(view: unknown, values: Record<string, unknown> = {}, extraLets?: Map<string, FormulaNode>): Lookup {
  const inputs = new Map<string, unknown>()
  for (const node of viewInputs(view)) {
    inputs.set(String(node.id), Object.prototype.hasOwnProperty.call(values, String(node.id)) ? values[String(node.id)] : inputDefault(node))
  }
  const lets = new Map<string, FormulaNode>()
  const declared = isRecord(view) ? (view as ViewNode).let : undefined
  if (isRecord(declared)) {
    for (const [name, source] of Object.entries(declared as Record<string, unknown>)) {
      const entry = compileFormula(isFormula(source) ? (source as ViewNode)['='] : source)
      if ('tree' in entry) lets.set(name, entry.tree)
    }
  }
  if (extraLets !== undefined) for (const [name, tree] of extraLets) lets.set(name, tree)
  return createScope(inputs, lets)
}

/** A property's value: the literal, or the formula worked out with a fallback. */
export function resolve(value: unknown, lookup: Lookup, fallback: unknown = undefined): unknown {
  if (!isFormula(value)) return value
  const entry = compileFormula((value as ViewNode)['='])
  if (!('tree' in entry)) return fallback
  const result = evaluate(entry.tree, lookup)
  return 'error' in result ? fallback : result.value
}

export const asText = (value: unknown): string => (value === undefined || value === null ? '' : show(value))

// -------------------------------------------------------------------------
// Answers

function interactiveNodes(node: unknown): ViewNode[] {
  const found: ViewNode[] = []
  walk(node, item => {
    if (INTERACTIVE.has(String(item.type))) found.push(item)
  })
  return found
}

export type ValidatedAnswer = { selected: string[] } | { confirmed: boolean } | { fields: Record<string, string> } | Record<string, never>

function validateInputs(view: unknown, sent: unknown): { inputs?: Record<string, unknown> } | { error: string } {
  const nodes = viewInputs(view)
  if (nodes.length === 0) return sent === undefined ? {} : { error: 'values.inputs: this view has no inputs' }
  if (sent !== undefined && !isRecord(sent)) return { error: 'values.inputs: expected an object of input ids to values' }
  const given = (sent ?? {}) as Record<string, unknown>
  const ids = nodes.map(node => String(node.id))
  let unknown: string | undefined
  for (const key of Object.keys(given)) {
    if (!ids.includes(key)) {
      unknown = key
      break
    }
  }
  if (unknown !== undefined) return { error: `values.inputs.${unknown}: unknown input; allowed: ${allowed(ids)}` }
  const inputs: Record<string, unknown> = {}
  for (const node of nodes) {
    const value = Object.prototype.hasOwnProperty.call(given, String(node.id)) ? given[String(node.id)] : inputDefault(node)
    const at = `values.inputs.${node.id}`
    if (node.type === 'toggle' && typeof value !== 'boolean') return { error: `${at}: expected true or false` }
    if (node.type === 'choice') {
      const options = Array.isArray(node.options) ? (node.options as unknown[]) : []
      if (!options.some(option => choiceValue(option) === value)) return { error: `${at}: expected one of the options' values` }
    }
    if (node.type === 'slider' || node.type === 'number') {
      if (!isNumber(value)) return { error: `${at}: expected a number` }
      const min = node.min !== undefined ? Number(node.min) : undefined
      const max = node.max !== undefined ? Number(node.max) : undefined
      if ((min !== undefined && (value as number) < min) || (max !== undefined && (value as number) > max)) {
        return { error: `${at}: expected a number from ${min ?? '-∞'} to ${max ?? '∞'}` }
      }
    }
    inputs[String(node.id)] = value
  }
  return { inputs }
}

function validateOptions(node: ViewNode, values: Record<string, unknown>): ValidatedAnswer | { error: string } {
  if (!Array.isArray(values.selected)) return { error: 'values.selected: expected an array of option labels' }
  const labels = new Set<string>((Array.isArray(node.options) ? (node.options as unknown[]) : []).map(option => String(isRecord(option) ? (option as ViewNode).label : option)))
  const picked = (values.selected as unknown[]).filter(label => typeof label === 'string' && labels.has(label as string)) as string[]
  const selected = node.multi === true ? [...new Set(picked)] : picked.slice(0, 1)
  if (selected.length === 0) return { error: 'values.selected: select at least one option' }
  return { selected }
}

function validateConfirm(values: Record<string, unknown>): ValidatedAnswer | { error: string } {
  if (typeof values.confirmed !== 'boolean') return { error: 'values.confirmed: expected a boolean' }
  return { confirmed: values.confirmed }
}

function validateForm(node: ViewNode, values: Record<string, unknown>): ValidatedAnswer | { error: string } {
  if (!isRecord(values.fields)) return { error: 'values.fields: expected an object of field ids to strings' }
  const declared = (Array.isArray(node.fields) ? (node.fields as unknown[]) : [])
    .map(field => (isRecord(field) ? (field as ViewNode).id : undefined))
    .filter(id => typeof id === 'string') as string[]
  const allowedIds = new Set(declared)
  const fields: Record<string, string> = {}
  for (const [key, value] of Object.entries(values.fields as Record<string, unknown>)) {
    if (!allowedIds.has(key)) return { error: `values.fields.${key}: unknown field; allowed: ${allowed(declared)}` }
    if (typeof value !== 'string') return { error: `values.fields.${key}: expected a string` }
    if (value.length > MAX_TEXT) return { error: `values.fields.${key}: ${value.length} characters exceeds the limit of ${MAX_TEXT}` }
    fields[key] = value
  }
  return { fields }
}

/**
 * The answer a user may send back: `action` is the id of the component the user
 * submitted. One submit settles the whole card.
 */
export function validateViewAnswer(view: unknown, action: unknown, values: unknown): { error?: string; answer?: Record<string, unknown> } {
  const nodes = interactiveNodes(view)
  if (typeof action !== 'string' || action === '') {
    return { error: `action: expected an interactive component id; allowed: ${allowed(nodes.map(node => String(node.id)))}` }
  }
  const node = nodes.find(item => item.id === action)
  if (node === undefined) {
    return { error: `action: no interactive component with id ${quoted(action)}; allowed: ${allowed(nodes.map(item => String(item.id)))}` }
  }
  if (!isRecord(values)) return { error: 'values: expected an object' }
  const valuesRecord = values as Record<string, unknown>
  const inputs = validateInputs(view, valuesRecord.inputs)
  if ('error' in inputs) return { error: inputs.error }
  const extra: Record<string, unknown> = inputs.inputs === undefined ? {} : { inputs: inputs.inputs }
  let own: ValidatedAnswer | { error: string }
  if (node.type === 'submit') own = {}
  else if (node.type === 'options') own = validateOptions(node, valuesRecord)
  else if (node.type === 'confirm') own = validateConfirm(valuesRecord)
  else own = validateForm(node, valuesRecord)
  if ('error' in own) return { error: own.error }
  return { answer: { ...(own as Record<string, unknown>), ...extra } }
}

// -------------------------------------------------------------------------
// The answer as one line for the user's own bubble

function eachNode(view: unknown, visit: (node: ViewNode) => void): void {
  if (!isRecord(view)) return
  visit(view as ViewNode)
  for (const child of Array.isArray((view as ViewNode).children) ? ((view as ViewNode).children as unknown[]) : []) eachNode(child, visit)
}

/** The picked labels, confirm/cancel, `label: value` fields and `label=value` inputs. */
export function viewAnswerText(view: unknown, answer: unknown): string {
  if (!isRecord(answer)) return ''
  const values = (answer as ViewNode).values
  if (!isRecord(values)) return ''
  const valuesRecord = values as Record<string, unknown>
  const parts: string[] = []
  if (Array.isArray(valuesRecord.selected)) {
    const labels = new Map<unknown, unknown>()
    eachNode(view, node => {
      for (const option of Array.isArray(node.options) ? (node.options as unknown[]) : []) {
        for (const key of [isRecord(option) ? (option as ViewNode).label : undefined, isRecord(option) ? (option as ViewNode).value : undefined]) {
          if (key !== undefined) labels.set(key, isRecord(option) ? (option as ViewNode).label : undefined)
        }
      }
    })
    parts.push(...(valuesRecord.selected as unknown[]).map(value => String(labels.get(value) ?? value)))
  } else if (typeof valuesRecord.confirmed === 'boolean') {
    let confirmLabel: unknown
    let cancelLabel: unknown
    eachNode(view, node => {
      if (node.id === (answer as ViewNode).action) {
        confirmLabel = node.confirmLabel
        cancelLabel = node.cancelLabel
      }
    })
    parts.push(valuesRecord.confirmed ? String(confirmLabel ?? 'Confirmed') : String(cancelLabel ?? 'Cancelled'))
  } else if (isRecord(valuesRecord.fields)) {
    const labels = new Map<string, unknown>()
    eachNode(view, node => {
      for (const field of Array.isArray(node.fields) ? (node.fields as unknown[]) : []) {
        if (isRecord(field)) labels.set(String((field as ViewNode).id), (field as ViewNode).label ?? (field as ViewNode).id)
      }
    })
    for (const [key, value] of Object.entries(valuesRecord.fields as Record<string, unknown>)) {
      parts.push(`${labels.get(key) ?? key}: ${value}`)
    }
  }
  if (isRecord(valuesRecord.inputs)) {
    const labels = new Map<string, unknown>()
    eachNode(view, node => {
      if (typeof node.id === 'string' && node.label !== undefined) labels.set(node.id, node.label)
    })
    for (const [key, value] of Object.entries(valuesRecord.inputs as Record<string, unknown>)) {
      parts.push(`${labels.get(key) ?? key}=${value}`)
    }
  }
  const text = parts.join('; ')
  return text.length > 200 ? `${text.slice(0, 200)}…` : text
}
