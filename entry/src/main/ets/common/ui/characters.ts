// Character marks: the SHAPES view over CHARACTERS, default looks derived from
// the Bot id, and the SVG path strings ArkUI renders. Port of characters.js.
import { INKS, GRADIENTS, isHex, inkName } from './tokens.ts'
import { CHARACTERS, DEFAULT_SHAPES, DEFAULT_COLORS, FALLBACK_SHAPE, type Look } from './characters-table.ts'

export interface ShapeEntry {
  label: string
  body: string
  paints: [string, string, number][]
  shade: string
  light: string
  eyes: [number, number, number, number, number][]
}

// The characters table entries, typed.
const ENTRIES = CHARACTERS as unknown as Record<string, { label?: string; body: string; paints?: [string, string, number][]; shade?: string; light?: string; eyes: [number, number, number, number, number][] }>

const SHAPES: Record<string, ShapeEntry & { size: number }> = {}
for (const [id, character] of Object.entries(ENTRIES)) {
  // Each shape draws body, then its fixed-color paints, then the shade; the
  // eye capsules are punched out of the finished mark (upstream masks them).
  SHAPES[id] = {
    label: character.label ?? id.charAt(0).toUpperCase() + id.slice(1),
    body: character.body,
    paints: character.paints ?? [],
    shade: character.shade ?? '',
    light: character.light ?? '',
    eyes: character.eyes,
    size: 100,
  }
}

export function hasShape(id: string | undefined): boolean {
  return typeof id === 'string' && SHAPES[id] !== undefined
}

export function shapeIdOf(id: string | undefined): string {
  return hasShape(id) ? (id as string) : FALLBACK_SHAPE
}

export function shapeOf(id: string | undefined): ShapeEntry & { size: number } {
  return SHAPES[shapeIdOf(id)]!
}

// The default look comes from the Bot id (FNV-1a, then mulberry32 for the color
// and murmur3's fmix32 for the shape), so it is the same on every device.
export function fnv1a(text: string): number {
  let value = 2166136261
  for (let index = 0; index < text.length; index += 1) value = Math.imul(value ^ text.charCodeAt(index), 16777619)
  return value >>> 0
}

export function defaultColor(id: string): string {
  const t = (fnv1a(id) + 1831565813) | 0
  let n = Math.imul(t ^ (t >>> 15), 1 | t)
  n = (n + Math.imul(n ^ (n >>> 7), 61 | n)) ^ n
  return DEFAULT_COLORS[Math.floor((((n ^ (n >>> 14)) >>> 0) / 4294967296) * DEFAULT_COLORS.length)] ?? 'blue'
}

export function defaultShape(id: string): string {
  let value = fnv1a(id) | 0
  value = Math.imul(value ^ (value >>> 16), 73244475)
  value = Math.imul(value ^ (value >>> 13), 3266489909)
  return DEFAULT_SHAPES[((value ^ (value >>> 16)) >>> 0) % DEFAULT_SHAPES.length] ?? FALLBACK_SHAPE
}

export function isColor(color: string | undefined): boolean {
  return isHex(color) || (color !== undefined && INKS[color] !== undefined)
}

// A stored shape or color wins; then the id. With no Bot it is a black gumdrop.
export function colorOf(bot: { color?: string; id?: string } | null | undefined): string {
  if (bot !== undefined && bot !== null && isColor(bot.color)) return bot.color as string
  if (bot?.id) return defaultColor(String(bot.id))
  return 'black'
}

export function lookOf(bot: { id?: string; color?: string; avatar?: { shape?: string; image?: string; imageRef?: string } } | null | undefined): Look {
  const avatar = bot?.avatar ?? {}
  return {
    shape: hasShape(avatar.shape) ? (avatar.shape as string) : bot?.id ? defaultShape(String(bot.id)) : FALLBACK_SHAPE,
    image: avatar.image,
    color: colorOf(bot),
  }
}

// A character color as paint, for swatches and a member's name in a group.
export const COLOR_PAINT: Record<string, string> = {
  black: '#3c4048', brown: '#8d6e57', red: '#e5484d', orange: '#f76b15', yellow: '#d4a017',
  green: '#30a46c', cyan: '#12a5b4', blue: '#4f7df3', violet: '#7d5aff', magenta: '#d3458b', gray: '#8b8f98',
  aurora: '#5cc8a0',
}

export function inkFill(color: string): string {
  if (isHex(color)) return color
  return `var(--bt-ink-${inkName(color)})`
}

// A rotated rounded-rect subpath for one eye. Upstream draws each eye as a
// black <rect rx> inside an SVG mask over the whole mark, so the hole shows
// through every layer; the port punches these same capsules out of the
// finished drawing instead.
function eyeSubpath(eye: [number, number, number, number, number]): string {
  const [cx, cy, w, h, tiltDeg] = eye
  const tilt = (tiltDeg * Math.PI) / 180
  const hw = w / 2
  const hh = h / 2
  const cos = Math.cos(tilt)
  const sin = Math.sin(tilt)
  // Rotate a point around the eye center.
  const rot = (x: number, y: number): [number, number] => [
    cx + x * cos - y * sin,
    cy + x * sin + y * cos,
  ]
  const f = (point: [number, number]): string => `${point[0].toFixed(2)} ${point[1].toFixed(2)}`
  const r = Math.min(hw, hh)
  if (hh >= hw) {
    // Vertical capsule: the cap centers sit on the vertical axis.
    const d = hh - r
    const tl = rot(-r, -d)
    const tr = rot(r, -d)
    const br = rot(r, d)
    const bl = rot(-r, d)
    return `M ${f(tl)} A ${r.toFixed(2)} ${r.toFixed(2)} 0 0 1 ${f(tr)} L ${f(br)} A ${r.toFixed(2)} ${r.toFixed(2)} 0 0 1 ${f(bl)} Z`
  }
  // Horizontal capsule: the cap centers sit on the horizontal axis.
  const d = hw - r
  const tr = rot(d, -r)
  const br = rot(d, r)
  const bl = rot(-d, r)
  const tl = rot(-d, -r)
  return `M ${f(tr)} A ${r.toFixed(2)} ${r.toFixed(2)} 0 0 1 ${f(br)} L ${f(bl)} A ${r.toFixed(2)} ${r.toFixed(2)} 0 0 1 ${f(tl)} Z`
}

// One mark layer's path, as authored. Fill with the evenodd rule: the ring's
// body carries an inner hole and several shades/lights are multi-part.
export function shapeLayerPath(shapeId: string, layer: 'body' | 'shade' | 'light'): string {
  const def = shapeOf(shapeId)
  if (layer === 'body') return def.body
  if (layer === 'shade') return def.shade
  return def.light
}

// The fixed-color paint polygons for a mark, as authored (upstream never lets
// them cover the eyes; the eye punch runs after all layers).
export function shapePaintPaths(shapeId: string): { d: string; fill: string; opacity: number }[] {
  const def = shapeOf(shapeId)
  return def.paints.map(([d, fill, opacity]) => ({ d, fill, opacity }))
}

// The eye holes to punch out of the finished mark, matching upstream's mask.
export function shapeEyePaths(shapeId: string): string[] {
  return shapeOf(shapeId).eyes.map(eyeSubpath)
}

// The paint for a mark's body: an ink name resolves to its light/dark value, a
// gradient paints through two stacked Paths (the body then a tinted overlay).
export function shapeBodyPaint(color: string, dark: boolean): string {
  if (GRADIENTS[color] !== undefined) return (GRADIENTS[color]![0] ?? [0, '#000'])[1]
  if (isHex(color)) return color
  return INKS[inkName(color)]![dark ? 1 : 0]
}

export { GRADIENTS }
