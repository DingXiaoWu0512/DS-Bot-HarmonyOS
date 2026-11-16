// Formulas in a view blueprint: `{ "=": "price * qty" }`. Port of deep-view's
// formula.js to ArkTS-compatible TS: the same parser, functions and errors.
export type FormulaNode =
  | { kind: 'value'; value: string | number | boolean }
  | { kind: 'name'; name: string }
  | { kind: 'unary'; op: string; value: FormulaNode }
  | { kind: 'binary'; op: string; left: FormulaNode; right: FormulaNode }
  | { kind: 'if'; test: FormulaNode; yes: FormulaNode; no: FormulaNode }
  | { kind: 'call'; name: string; args: FormulaNode[] }

interface Token {
  kindOf: 'number' | 'name' | 'string' | 'op'
  value: string | number
  at: number
}

class FormulaError extends Error {}

const fail = (message: string): never => {
  throw new FormulaError(message)
}

function num(value: unknown): number {
  if (typeof value === 'number') return value
  if (typeof value === 'boolean') return value ? 1 : 0
  const parsed = Number(value)
  if (typeof value === 'string' && value.trim() !== '' && !Number.isNaN(parsed)) return parsed
  return fail(`${JSON.stringify(value)} is not a number`)
}

const digitsOf = (digits: unknown): number => {
  const value = num(digits)
  if (!Number.isInteger(value) || value < 0 || value > 10) fail('digits must be a whole number from 0 to 10')
  return value
}

const roundTo = (value: number, digits: number): number => {
  const scale = 10 ** digits
  return Math.round(value * scale) / scale
}

function grouped(value: number, digits: number): string {
  if (!Number.isFinite(value)) return String(value)
  const fixed = Math.abs(roundTo(value, digits)).toFixed(digits)
  const at = fixed.indexOf('.')
  const whole = at === -1 ? fixed : fixed.slice(0, at)
  const part = at === -1 ? '' : fixed.slice(at + 1)
  const sign = value < 0 && Number(whole + part) !== 0 ? '-' : ''
  return `${sign}${whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',')}${part !== '' ? `.${part}` : ''}`
}

interface FormulaFunction {
  min: number
  max: number
  run: (values: unknown[]) => unknown
}

const FUNCTIONS: Record<string, FormulaFunction> = {
  min: { min: 1, max: Infinity, run: values => Math.min(...values.map(num)) },
  max: { min: 1, max: Infinity, run: values => Math.max(...values.map(num)) },
  abs: { min: 1, max: 1, run: values => Math.abs(num(values[0])) },
  floor: { min: 1, max: 1, run: values => Math.floor(num(values[0])) },
  ceil: { min: 1, max: 1, run: values => Math.ceil(num(values[0])) },
  sqrt: { min: 1, max: 1, run: values => Math.sqrt(num(values[0])) },
  pow: { min: 2, max: 2, run: values => num(values[0]) ** num(values[1]) },
  round: { min: 1, max: 2, run: values => roundTo(num(values[0]), values.length > 1 ? digitsOf(values[1]) : 0) },
  clamp: { min: 3, max: 3, run: values => Math.min(Math.max(num(values[0]), num(values[1])), num(values[2])) },
  fixed: { min: 1, max: 2, run: values => roundTo(num(values[0]), values.length > 1 ? digitsOf(values[1]) : 0).toFixed(values.length > 1 ? digitsOf(values[1]) : 0) },
  format: { min: 1, max: 2, run: values => grouped(num(values[0]), values.length > 1 ? digitsOf(values[1]) : 0) },
  percent: { min: 1, max: 2, run: values => `${grouped(num(values[0]) * 100, values.length > 1 ? digitsOf(values[1]) : 0)}%` },
}

const FORMULA_FUNCTIONS = Object.keys(FUNCTIONS)
const CONSTANTS = new Map<string, unknown>([['true', true], ['false', false]])
// Nesting deeper than this is no calculation a view needs.
const MAX_NESTING = 64

const IDENT = /^[A-Za-z_][A-Za-z0-9_]*$/

export const isName = (value: unknown): boolean => typeof value === 'string' && IDENT.test(value)

const OPERATORS = ['==', '!=', '<=', '>=', '&&', '||', '+', '-', '*', '/', '%', '<', '>', '!', '?', ':', '(', ')', ',']
const BINARY: string[][] = [['||'], ['&&'], ['==', '!='], ['<', '<=', '>', '>='], ['+', '-'], ['*', '/', '%']]

function tokenize(source: string): Token[] {
  const tokens: Token[] = []
  let at = 0
  while (at < source.length) {
    const char = source.charAt(at)
    if (/\s/.test(char)) {
      at += 1
      continue
    }
    const rest = source.slice(at)
    const number = /^(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/.exec(rest)
    if (number !== null && number[0] !== undefined) {
      tokens.push({ kindOf: 'number', value: Number(number[0]), at })
      at += number[0].length
      continue
    }
    const name = /^[A-Za-z_][A-Za-z0-9_]*/.exec(rest)
    if (name !== null && name[0] !== undefined) {
      tokens.push({ kindOf: 'name', value: name[0], at })
      at += name[0].length
      continue
    }
    if (char === '"' || char === '\'') {
      let end = at + 1
      let text = ''
      while (end < source.length && source.charAt(end) !== char) {
        if (source.charAt(end) === '\\' && end + 1 < source.length) {
          text += source.charAt(end + 1)
          end += 2
          continue
        }
        text += source.charAt(end)
        end += 1
      }
      if (end >= source.length) fail(`unclosed string at ${at + 1}`)
      tokens.push({ kindOf: 'string', value: text, at })
      at = end + 1
      continue
    }
    const operator = OPERATORS.find(op => source.startsWith(op, at))
    if (operator === undefined) fail(`unexpected ${JSON.stringify(char)} at ${at + 1}`)
    tokens.push({ kindOf: 'op', value: operator, at })
    at += operator.length
  }
  return tokens
}

function parse(source: string): FormulaNode {
  const tokens = tokenize(source)
  let index = 0
  let depth = 0
  const peek = (): Token | undefined => tokens[index]
  const isOp = (value: string): boolean => peek()?.kindOf === 'op' && peek()?.value === value
  const expect = (value: string): void => {
    if (!isOp(value)) {
      const at = peek()?.at
      fail(at !== undefined ? `expected "${value}" at ${at + 1}` : `expected "${value}" at the end`)
    }
    index += 1
  }
  const nest = (read: () => FormulaNode): FormulaNode => {
    depth += 1
    if (depth > MAX_NESTING) fail(`nested more than ${MAX_NESTING} levels`)
    const node = read()
    depth -= 1
    return node
  }
  const binary = (level: number): FormulaNode => {
    if (level === BINARY.length) return unary()
    let left = binary(level + 1)
    while (peek()?.kindOf === 'op' && (BINARY[level] ?? []).includes(String(peek()?.value))) {
      const op = String(peek()?.value)
      index += 1
      left = { kind: 'binary', op, left, right: binary(level + 1) }
    }
    return left
  }
  const unary = (): FormulaNode => {
    if (isOp('-') || isOp('!') || isOp('+')) {
      const op = String(peek()?.value)
      index += 1
      return nest(() => ({ kind: 'unary', op, value: unary() }))
    }
    return primary()
  }
  const ternary = (): FormulaNode => nest(() => {
    const test = binary(0)
    if (!isOp('?')) return test
    index += 1
    const yes = ternary()
    expect(':')
    return { kind: 'if', test, yes, no: ternary() }
  })
  const primary = (): FormulaNode => {
    const token = peek()
    if (token === undefined) fail('the formula ends too early')
    index += 1
    if (token.kindOf === 'number' || token.kindOf === 'string') return { kind: 'value', value: token.value }
    if (token.kindOf === 'op' && token.value === '(') {
      const inner = ternary()
      expect(')')
      return inner
    }
    if (token.kindOf !== 'name') fail(`unexpected "${token.value}" at ${token.at + 1}`)
    const name = String(token.value)
    if (!isOp('(')) return CONSTANTS.has(name) ? { kind: 'value', value: CONSTANTS.get(name) as boolean } : { kind: 'name', name }
    const fn = Object.prototype.hasOwnProperty.call(FUNCTIONS, name) ? FUNCTIONS[name] : undefined
    if (fn === undefined) fail(`unknown function "${name}"; allowed: ${FORMULA_FUNCTIONS.join(', ')}`)
    index += 1 // The call's "(" is consumed here; the args start after it.
    const args: FormulaNode[] = []
    if (!isOp(')')) {
      args.push(ternary())
      while (isOp(',')) {
        index += 1
        args.push(ternary())
      }
    }
    expect(')')
    if (args.length < fn.min || args.length > fn.max) {
      fail(`${name}() takes ${fn.min === fn.max ? fn.min : fn.max === Infinity ? `at least ${fn.min}` : `${fn.min} or ${fn.max}`} argument${fn.max === 1 ? '' : 's'}; got ${args.length}`)
    }
    return { kind: 'call', name, args }
  }
  if (tokens.length === 0) fail('the formula is empty')
  const tree = ternary()
  if (index < tokens.length) fail(`unexpected "${peek()?.value}" at ${(peek()?.at ?? 0) + 1}`)
  return tree
}

function namesIn(node: FormulaNode, found: Set<string>): Set<string> {
  if (node.kind === 'name') found.add(node.name)
  else if (node.kind === 'unary') namesIn(node.value, found)
  else if (node.kind === 'binary') {
    namesIn(node.left, found)
    namesIn(node.right, found)
  } else if (node.kind === 'if') {
    namesIn(node.test, found)
    namesIn(node.yes, found)
    namesIn(node.no, found)
  } else if (node.kind === 'call') for (const arg of node.args) namesIn(arg, found)
  return found
}

export type CompiledFormula = { tree: FormulaNode; names: string[] } | { error: string }

/** { tree, names } or { error }. `names` are the names the formula reads. */
export function compileFormula(source: unknown): CompiledFormula {
  if (typeof source !== 'string') return { error: 'expected a formula string' }
  try {
    const tree = parse(source)
    return { tree, names: [...namesIn(tree, new Set())] }
  } catch (error) {
    if (error instanceof FormulaError) return { error: error.message }
    throw error
  }
}

// Evaluation. `lookup(name)` returns a name's value or throws.
function run(node: FormulaNode, lookup: (name: string) => unknown): unknown {
  switch (node.kind) {
    case 'value': return node.value
    case 'name': return lookup(node.name)
    case 'unary': {
      const value = run(node.value, lookup)
      if (node.op === '!') return !truthy(value)
      return node.op === '-' ? -num(value) : num(value)
    }
    case 'if': return truthy(run(node.test, lookup)) ? run(node.yes, lookup) : run(node.no, lookup)
    case 'call': return (FUNCTIONS[node.name] as FormulaFunction).run(node.args.map(arg => run(arg, lookup)))
    default: return binaryRun(node as Extract<FormulaNode, { kind: 'binary' }>, lookup)
  }
}

const truthy = (value: unknown): boolean => (typeof value === 'string' ? value !== '' : Boolean(value))

function binaryRun(node: Extract<FormulaNode, { kind: 'binary' }>, lookup: (name: string) => unknown): unknown {
  if (node.op === '&&') return truthy(run(node.left, lookup)) ? run(node.right, lookup) : false
  if (node.op === '||') {
    const left = run(node.left, lookup)
    return truthy(left) ? left : run(node.right, lookup)
  }
  const left = run(node.left, lookup)
  const right = run(node.right, lookup)
  switch (node.op) {
    case '+': return typeof left === 'string' || typeof right === 'string' ? `${show(left)}${show(right)}` : num(left) + num(right)
    case '-': return num(left) - num(right)
    case '*': return num(left) * num(right)
    case '/': return num(left) / num(right)
    case '%': return num(left) % num(right)
    case '==': return left === right
    case '!=': return left !== right
    case '<': return num(left) < num(right)
    case '<=': return num(left) <= num(right)
    case '>': return num(left) > num(right)
    default: return num(left) >= num(right)
  }
}

/** A value as text: numbers lose float noise (0.1 + 0.2 shows 0.3). */
export function show(value: unknown): string {
  if (typeof value === 'number') return Number.isFinite(value) ? String(Number(value.toPrecision(12))) : String(value)
  return String(value)
}

export type Lookup = (name: string) => unknown

/** A scope for one view: input values, plus `let` names worked out on demand. */
export function createScope(inputs: Map<string, unknown>, lets: Map<string, FormulaNode>): Lookup {
  const done = new Map<string, unknown>()
  const busy = new Set<string>()
  const lookup: Lookup = name => {
    if (inputs.has(name)) return inputs.get(name)
    if (done.has(name)) return done.get(name)
    const tree = lets.get(name)
    if (tree === undefined) fail(`unknown name "${name}"`)
    if (busy.has(name)) fail(`"${name}" refers to itself`)
    busy.add(name)
    try {
      const value = run(tree, lookup)
      done.set(name, value)
      return value
    } finally {
      busy.delete(name)
    }
  }
  return lookup
}

export type Evaluated = { value: unknown } | { error: string }

/** { value } or { error }. */
export function evaluate(tree: FormulaNode, lookup: Lookup): Evaluated {
  try {
    return { value: run(tree, lookup) }
  } catch (error) {
    if (error instanceof FormulaError) return { error: error.message }
    if (error instanceof RangeError) return { error: 'the formula is too deep to work out' }
    throw error
  }
}

export function isFormulaValue(value: unknown): boolean {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return false
  const keys = Object.keys(value as Record<string, unknown>)
  return keys.length === 1 && keys[0] === '='
}
