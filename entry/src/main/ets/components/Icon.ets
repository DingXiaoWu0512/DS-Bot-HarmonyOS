// Icon set ported from mobile/src/ui/icons.tsx (viewBox 0 0 20 20, round caps).
// Rendered with the drawing Path component: .commands() takes SVG path syntax in
// px, so each icon's path data is numerically scaled by k = vp2px(size)/20 with
// an arc-flag-aware scaler (A/a rotation and flag args are never scaled, implicit
// command repetition is preserved). Stroke widths are in vp: sw * size / 20.
// Rect/Circle primitives are pre-converted to path data; PinMark's SVG
// rotate(45 10 10) becomes the universal .rotate() about the icon center.

import { appStore, Palette } from './Theme'

interface IconSpec {
  d: string
  sw: number
  round: boolean
  spin45: boolean
}

const UNKNOWN_ICON: IconSpec = { d: '', sw: 0, round: false, spin45: false }

// Rounded-rect and circle primitives converted to path data.
const RECT_SIDEBAR = 'M5.5 4h9a2.5 2.5 0 0 1 2.5 2.5v7a2.5 2.5 0 0 1-2.5 2.5h-9' +
  'a2.5 2.5 0 0 1-2.5-2.5v-7a2.5 2.5 0 0 1 2.5-2.5z'
const CIRCLE_SEARCH = 'M3 8.5a5.5 5.5 0 1 0 11 0a5.5 5.5 0 1 0-11 0'
const CIRCLE_PEOPLE = 'M4.5 7a3 3 0 1 0 6 0a3 3 0 1 0-6 0'
const RECT_STOP = 'M7 5h6a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z'

const ICONS: Record<string, IconSpec> = {
  'chevronLeft': { d: 'M12.5 4.5L7 10l5.5 5.5', sw: 1.6, round: true, spin45: false },
  'chevronRight': { d: 'M7.5 4.5L13 10l-5.5 5.5', sw: 1.6, round: true, spin45: false },
  'sidebar': { d: `${RECT_SIDEBAR} M8 4v12`, sw: 1.6, round: false, spin45: false },
  'search': { d: `${CIRCLE_SEARCH} M13 13l4 4`, sw: 1.6, round: true, spin45: false },
  'plus': { d: 'M10 4v12M4 10h12', sw: 1.6, round: true, spin45: false },
  'arrowUp': { d: 'M10 16V4M5 9l5-5 5 5', sw: 1.8, round: true, spin45: false },
  'arrowDown': { d: 'M10 4v12M5 11l5 5 5-5', sw: 1.6, round: true, spin45: false },
  'gear': {
    d: 'M10 7.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2z' +
      'M7.85 4.4l.29-1.87a7.7 7.7 0 0 1 3.72 0l.29 1.87a6 6 0 0 1 1.63.94l1.76-.69' +
      'a7.7 7.7 0 0 1 1.86 3.23l-1.47 1.18a6 6 0 0 1 0 1.88l1.47 1.18' +
      'a7.7 7.7 0 0 1-1.86 3.23l-1.76-.69a6 6 0 0 1-1.63.94l-.29 1.87' +
      'a7.7 7.7 0 0 1-3.72 0l-.29-1.87a6 6 0 0 1-1.63-.94l-1.76.69' +
      'a7.7 7.7 0 0 1-1.86-3.23l1.47-1.18a6 6 0 0 1 0-1.88L2.6 7.88' +
      'a7.7 7.7 0 0 1 1.86-3.23l1.76.69a6 6 0 0 1 1.63-.94z',
    sw: 1.5, round: true, spin45: false
  },
  'people': {
    d: `${CIRCLE_PEOPLE} M2 16.5c.6-2.8 2.8-4.5 5.5-4.5s4.9 1.7 5.5 4.5` +
      'M13 4.3a3 3 0 0 1 0 5.4M15 12.4c1.6.6 2.6 2 3 4.1',
    sw: 1.5, round: true, spin45: false
  },
  'unread': {
    d: 'M10 3.5a4.5 4.5 0 0 0-4.5 4.5v3L4 13.5h12L14.5 11V8' +
      'M8.3 16a1.8 1.8 0 0 0 3.4 0' +
      'M15.5 3.2a1.6 1.6 0 1 1 0 3.2 1.6 1.6 0 0 1 0-3.2z',
    sw: 1.5, round: true, spin45: false
  },
  'pinMark': {
    d: 'M8 2.5h4a.9.9 0 0 1 0 1.8h-.4v4.1c0 1.4 1.1 2.6 2.6 3.1l.7.3v1.5H5.1v-1.5' +
      'l.7-.3c1.5-.5 2.6-1.7 2.6-3.1V4.3H8a.9.9 0 0 1 0-1.8z' +
      'M9.35 13.3h1.3v3.6L10 18l-.65-1.1z',
    sw: 0, round: false, spin45: true
  },
  'mainStar': {
    d: 'M10 2.4l2.29 5.04 5.51.63-4.09 3.74 1.11 5.42L10 14.5l-4.82 2.73' +
      '1.11-5.42L2.2 8.07l5.51-.63z',
    sw: 0, round: false, spin45: false
  },
  'stop': { d: RECT_STOP, sw: 0, round: false, spin45: false },
  'dots': { d: 'M5 10h.01M10 10h.01M15 10h.01', sw: 1.5, round: true, spin45: false },
  'check': { d: 'M4.5 10.5l3.5 3.5 7.5-8', sw: 1.5, round: true, spin45: false },
  'close': { d: 'M5 5l10 10M15 5L5 15', sw: 1.6, round: true, spin45: false },
  'side': {
    d: 'M17 11.5a6.5 6.5 0 0 1-6.5 6.5H4l2-2.6A6.5 6.5 0 1 1 17 11.5Z' +
      'M8.5 8.5 12 12M12 8.5 8.5 12',
    sw: 1.6, round: true, spin45: false
  }
}

const scaledCache = new Map<string, string>()

function round2(v: number): number {
  return Math.round(v * 100) / 100
}

// Appends one command (letter + its argument stream) to the output, scaling
// every coordinate by k. Arc (A/a) argument groups are 7-wide: rx ry rotation
// largeArcFlag sweepFlag x y â€?only rx, ry, x, y are scaled.
function emitCommand(cmd: string, args: number[], k: number, out: string): string {
  if (cmd === '' || cmd === 'Z' || cmd === 'z') {
    return out + cmd
  }
  let s = out
  let i = 0
  while (i < args.length) {
    let v = args[i]
    if (cmd !== 'A' && cmd !== 'a') {
      v = round2(v * k)
    } else {
      const pos = i % 7
      if (pos !== 2 && pos !== 3 && pos !== 4) {
        v = round2(v * k)
      }
    }
    s += (i === 0 ? cmd : ' ') + `${v}`
    i += 1
  }
  return s
}

// Scales SVG path data by k (all commands M L H V C S Q T A Z, both cases,
// implicit repetition included). Results are cached per (d, k).
export function scalePathD(d: string, k: number): string {
  const key = `${d}|${round2(k)}`
  const hit = scaledCache.get(key)
  if (hit !== undefined) {
    return hit
  }
  let out = ''
  let cmd = ''
  let args: number[] = []
  const re = /([MmLlHhVvCcSsQqTtAaZz])|(-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)/g
  let m = re.exec(d)
  while (m !== null) {
    if (m[1] !== undefined) {
      out = emitCommand(cmd, args, k, out)
      cmd = m[1]
      args = []
    } else {
      args.push(Number(m[2]))
    }
    m = re.exec(d)
  }
  out = emitCommand(cmd, args, k, out)
  scaledCache.set(key, out)
  return out
}

@ComponentV2
export struct Icon {
  @Param name: string = 'chevronLeft'
  @Param iconSize: number = 20
  @Param color: string = ''

  private spec(): IconSpec {
    const s: IconSpec | undefined = ICONS[this.name]
    if (s !== undefined) {
      return s
    }
    return UNKNOWN_ICON
  }

  private resolvedColor(): string {
    if (this.color !== '') {
      return this.color
    }
    const p: Palette = appStore.theme.p
    if (this.name === 'arrowUp' || this.name === 'stop') {
      return p.accentInk
    }
    if (this.name === 'pinMark') {
      return p.ink3
    }
    if (this.name === 'mainStar') {
      return p.star
    }
    if (this.name === 'check') {
      return p.accent
    }
    return p.ink2
  }

  private k(): number {
    return this.getUIContext().vp2px(this.iconSize) / 20
  }

  private scaled(): string {
    return scalePathD(this.spec().d, this.k())
  }

  private spinOptions(): RotateOptions {
    if (this.spec().spin45) {
      return { x: 0, y: 0, z: 1, angle: 45, centerX: this.iconSize / 2, centerY: this.iconSize / 2 }
    }
    return { x: 0, y: 0, z: 1, angle: 0 }
  }

  build() {
    if (this.spec() === UNKNOWN_ICON) {
      Stack().width(this.iconSize).height(this.iconSize)
    } else if (this.spec().sw === 0) {
      Path()
        .commands(this.scaled())
        .fill(this.resolvedColor())
        .strokeOpacity(0)
        .width(this.iconSize)
        .height(this.iconSize)
        .rotate(this.spinOptions())
    } else {
      Path()
        .commands(this.scaled())
        .fillOpacity(0)
        .stroke(this.resolvedColor())
        .strokeWidth(this.spec().sw * this.iconSize / 20)
        .strokeLineCap(this.spec().round ? LineCapStyle.Round : LineCapStyle.Butt)
        .strokeLineJoin(this.spec().round ? LineJoinStyle.Round : LineJoinStyle.Miter)
        .width(this.iconSize)
        .height(this.iconSize)
        .rotate(this.spinOptions())
    }
  }
}
