// The phone palette derives from the same eight theme colors as the desktop team
// UI, through allThemes() so preset themes follow. Port of tokens.ts + inks.js
// + themes.js (the desktop's custom-theme registry does not reach the phone).
export interface ThemeMode {
  bg: string
  sidebar: string
  bubble: string
  card: string
  text: string
  user: string
  userText: string
  accent: string
}

// Inks (light, dark) for characters, names, and mentions. Port of inks.js.
export const INKS: Record<string, string[]> = {
  deepseek: ['#4D6BFE', '#6A84FF'], charcoal: ['#141416', '#F1F2F4'], graphite: ['#2D2D2D', '#D6D6DA'],
  rose: ['#EC2F6B', '#FF5A7A'], sky: ['#0AA8D6', '#2EE6E0'], tangerine: ['#FF6900', '#FF8A2E'],
  cobalt: ['#082DFF', '#5C78FF'],
  black: ['#000000', '#FFFFFF'], brown: ['#9A6B44', '#7C5332'], red: ['#FF3E51', '#E02135'],
  orange: ['#FF6B1A', '#FF5E00'], yellow: ['#FFB020', '#F59E0B'], green: ['#10B981', '#059669'],
  cyan: ['#06B6D4', '#0891B2'], blue: ['#2563EB', '#3B82F6'], violet: ['#8B5CF6', '#7C3AED'],
  magenta: ['#F43F85', '#E11D74'], gray: ['#8A8F98', '#6E737B'], aurora: ['#00B8D4', '#2EE6E0'],
}

export const ACCENT_INKS = ['deepseek', 'charcoal', 'graphite', 'rose', 'sky', 'tangerine', 'cobalt']

// Gradient colors paint a character from its top left to its bottom right.
export const GRADIENTS: Record<string, [number, string][]> = {
  aurora: [[0, '#A4FFB0'], [0.42, '#00F0E4'], [1, '#2E9EF7']],
}

export const isHex = (color: string | undefined): boolean =>
  typeof color === 'string' && /^#[0-9a-f]{6}$/i.test(color)

export const luminance = (hex: string): number => [1, 3, 5]
  .map(index => parseInt(hex.slice(index, index + 2), 16) / 255)
  .map(channel => (channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4))
  .reduce((sum, channel, index) => sum + channel * [0.2126, 0.7152, 0.0722][index]!, 0)

// Renamed ink ids still found in saved Bots (old id → new id).
const LEGACY_INKS: Record<string, string> = { kimi: 'charcoal', zai: 'graphite', minimax: 'rose', stepfun: 'sky', mimo: 'tangerine', qwen: 'cobalt' }

export function inkName(color: string): string {
  if (INKS[color] !== undefined) return color
  const legacy = LEGACY_INKS[color]
  if (legacy !== undefined && INKS[legacy] !== undefined) return legacy
  return 'gray'
}

// The four preset themes. Port of themes.js THEMES.
const THEME_KEYS = ['bg', 'sidebar', 'bubble', 'card', 'text', 'user', 'userText', 'accent']
const THEMES: Record<string, { label: string; light: ThemeMode; dark: ThemeMode }> = {
  deepseek: {
    label: 'DeepSeek',
    light: { bg: '#fcfcfc', sidebar: '#f7f7f7', bubble: '#eeeeee', card: '#ffffff', text: '#141414', user: '#070707', userText: '#fcfcfc', accent: '#4d6bfe' },
    dark: { bg: '#141414', sidebar: '#1b1b1b', bubble: '#262626', card: '#1f1f1f', text: '#f2f2f2', user: '#f2f2f2', userText: '#141414', accent: '#5b7bff' },
  },
  mono: {
    label: 'Mono',
    light: { bg: '#ffffff', sidebar: '#f9f9f9', bubble: '#f0f0f0', card: '#ffffff', text: '#0d0d0d', user: '#0d0d0d', userText: '#ffffff', accent: '#0d0d0d' },
    dark: { bg: '#0f0f0f', sidebar: '#171717', bubble: '#242424', card: '#1c1c1c', text: '#f4f4f4', user: '#f4f4f4', userText: '#0f0f0f', accent: '#f4f4f4' },
  },
  paper: {
    label: 'Paper',
    light: { bg: '#faf9f5', sidebar: '#f3f0e8', bubble: '#ebe7dc', card: '#ffffff', text: '#1f1e1b', user: '#2b2a26', userText: '#faf9f5', accent: '#d97757' },
    dark: { bg: '#1f1e1b', sidebar: '#262521', bubble: '#34322d', card: '#2a2925', text: '#f3f0e8', user: '#f3f0e8', userText: '#1f1e1b', accent: '#e08a6d' },
  },
  moonlight: {
    label: 'Moonlight',
    light: { bg: '#f7f9fc', sidebar: '#eef2f8', bubble: '#e5ebf5', card: '#ffffff', text: '#121826', user: '#1e3a8a', userText: '#ffffff', accent: '#1e86ff' },
    dark: { bg: '#0b1020', sidebar: '#10172a', bubble: '#1a2340', card: '#141c33', text: '#e8edf7', user: '#3b6fd8', userText: '#ffffff', accent: '#4f9dff' },
  },
}

export function allThemes(): Record<string, { label: string; light: ThemeMode; dark: ThemeMode }> {
  return THEMES
}

const DARK_INK = '#141414'
const accentInk = (accent: string): string =>
  (luminance(accent) + 0.05) ** 2 > 1.05 * (luminance(DARK_INK) + 0.05) ? DARK_INK : '#ffffff'

export const rgba = (hex: string, alpha: number): string =>
  `rgba(${[1, 3, 5].map(index => parseInt(hex.slice(index, index + 2), 16)).join(',')},${alpha})`

// A preset accent is saved as its light value; in dark mode it takes the preset's
// dark value, like Bot names. A custom accent is the same in both modes.
const darkAccent = (accent: string): string => {
  for (const ink of ACCENT_INKS) {
    if (INKS[ink] !== undefined && INKS[ink]![0] === accent) return INKS[ink]![1]
  }
  return accent
}

export interface Palette {
  ink: string; ink2: string; ink3: string
  bubble: string; sidebar: string; main: string; card: string
  line: string; line2: string; lineWeak: string
  hover: string; active: string
  accent: string; accentInk: string
  user: string; userInk: string
  tagBg: string; tagInk: string
  knob: string
  danger: string; green: string; star: string
}

export function palette(dark: boolean, themeId?: string, accent?: string): Palette {
  const themes = allThemes()
  const theme = themes[themeId ?? ''] ?? themes.deepseek!
  const mode = dark ? theme.dark : theme.light
  const use = accent === undefined ? mode.accent : dark ? darkAccent(accent) : accent
  void THEME_KEYS
  return {
    ink: mode.text, ink2: rgba(mode.text, 0.6), ink3: rgba(mode.text, 0.36),
    bubble: mode.bubble, sidebar: mode.sidebar, main: mode.bg, card: mode.card,
    line: rgba(mode.text, 0.08), line2: rgba(mode.text, 0.15), lineWeak: rgba(mode.text, 0.1),
    hover: dark ? 'rgba(160,160,160,.12)' : 'rgba(119,119,119,.09)',
    active: dark ? 'rgba(160,160,160,.2)' : 'rgba(119,119,119,.17)',
    accent: use, accentInk: accentInk(use),
    user: mode.user, userInk: mode.userText,
    tagBg: rgba(mode.text, dark ? 0.09 : 0.06), tagInk: rgba(mode.text, 0.58),
    knob: '#ffffff',
    danger: '#e02135', green: '#00c972', star: '#ff9800',
  }
}

export function themeLabel(themeId?: string): string {
  const themes = allThemes()
  return themes[themeId ?? '']?.label ?? themes.deepseek!.label
}

// A Bot's color, resolved the way names and marks do on the desktop: a named ink
// has a light and a dark value, a #rrggbb color is used as is.
export function inkColor(color: string | undefined, dark: boolean): string {
  if (color !== undefined && INKS[color] !== undefined) return INKS[color]![dark ? 1 : 0]
  if (color !== undefined && isHex(color)) return color
  return INKS.gray![dark ? 1 : 0]
}

// Phone type scale: settled sizes for touch, weights only 400/500/600.
export interface TypeRow {
  fontSize: number
  lineHeight: number
  fontWeight: string
}

export const type: Record<string, TypeRow> = {
  rowName: { fontSize: 16, lineHeight: 22, fontWeight: '400' },
  rowPreview: { fontSize: 14, lineHeight: 20, fontWeight: '400' },
  bubble: { fontSize: 16, lineHeight: 24, fontWeight: '400' },
  headerTitle: { fontSize: 17, lineHeight: 24, fontWeight: '600' },
  largeTitle: { fontSize: 28, lineHeight: 34, fontWeight: '600' },
  settingsRow: { fontSize: 16, lineHeight: 22, fontWeight: '400' },
  small: { fontSize: 13, lineHeight: 18, fontWeight: '400' },
  caption: { fontSize: 12, lineHeight: 16, fontWeight: '400' },
}

export const radius = { tag: 4, item: 6, input: 8, row: 10, card: 12, option: 12, dialog: 16, bubble: 18, composer: 22, composerLong: 18, pill: 999 }

// Shadow levels 0-4 from the standard, mapped to ArkUI shadow params.
export const shadowRadiusOf = (level: number): number => [0, 8, 20, 28, 80][level] ?? 0
export const shadowOpacityOf = (level: number): number => [0, 0.06, 0.1, 0.14, 0.24][level] ?? 0
export const shadowOffsetYOf = (level: number): number => [0, 2, 10, 8, 24][level] ?? 0
export const shadowColorOf = (level: number): string => [0, 0x47000000, 0x59000000, 0x66000000, 0x80000000][level]?.toString(16) ?? '0'

export const MONO = 'monospace'
