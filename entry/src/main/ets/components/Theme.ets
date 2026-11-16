// Theme bridge: the single import point screens use for design tokens.
// Re-exports the palette/type/radius/shadow primitives from common/ui/tokens.ts,
// the reactive app state from appstate/AppStore.ets, and adds the ArkUI-specific
// shadowOf() mapping (tokens' shadow levels → ShadowOptions with ARGB colors).

import {
  type, radius, MONO, rgba, palette, allThemes, themeLabel,
  inkColor, inkName, isHex, luminance, INKS, GRADIENTS,
  shadowRadiusOf, shadowOffsetYOf
} from '../common/ui/tokens'
import { appStore, AppStore, ThemeState, LinkState, PrefsState, ComputersState } from '../appstate/AppStore'

export {
  type, radius, MONO, rgba, palette, allThemes, themeLabel,
  inkColor, inkName, isHex, luminance, INKS, GRADIENTS,
  shadowRadiusOf, shadowOffsetYOf
}
export { appStore, AppStore, ThemeState, LinkState, PrefsState, ComputersState }
export type { Palette, TypeRow, ThemeMode } from '../common/ui/tokens'

// Shadow levels 0-4 as ARGB numbers (28% black at level 1 … 50% at level 4),
// matching the Android shadow variant of the desktop standard.
const SHADOW_COLORS: number[] = [0, 0x47000000, 0x59000000, 0x66000000, 0x80000000]

// Maps a standard shadow level (0-4) to ArkUI ShadowOptions.
export function shadowOf(level: number): ShadowOptions {
  return {
    radius: shadowRadiusOf(level),
    color: SHADOW_COLORS[level] ?? 0,
    offsetX: 0,
    offsetY: shadowOffsetYOf(level)
  }
}
