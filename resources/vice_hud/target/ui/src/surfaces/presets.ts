import type { Tunables } from '../lib/types'

export interface Preset {
  id: string
  label: string
  blurb: string
  values: Tunables
}

export const PRESETS: Preset[] = [
  {
    id: 'midnight',
    label: 'Midnight',
    blurb: 'The shipped look. Deep neutral panels, one teal accent, soft elevation.',
    values: {
      accent: '#14b8a6', surface: '#0b0d0e', text: '#f2f4f5', textMuted: '#8f979c', disabled: '#6b7377',
      surfaceAlpha: 88, outline: 14, corner: 14, gradient: 'linear', gradientDepth: 32, shadow: 40,
      typeWeight: '600', typeCase: 'normal',
    },
  },
  {
    id: 'porcelain',
    label: 'Porcelain',
    blurb: 'Light panels with dark type. Reads best on servers with bright, daylight-heavy scenery.',
    values: {
      accent: '#0f766e', surface: '#f3f4f5', text: '#12171a', textMuted: '#5c6469', disabled: '#848c90',
      surfaceAlpha: 93, outline: 22, corner: 18, gradient: 'none', gradientDepth: 0, shadow: 34,
      typeWeight: '600', typeCase: 'normal',
    },
  },
  {
    id: 'ember',
    label: 'Ember',
    blurb: 'Warm and close. A dark red-black panel with an orange accent.',
    values: {
      accent: '#ff6b4a', surface: '#150a09', text: '#f7efec', textMuted: '#a08b85', disabled: '#7a6660',
      surfaceAlpha: 90, outline: 15, corner: 10, gradient: 'radial', gradientDepth: 40, shadow: 55,
      typeWeight: '600', typeCase: 'normal',
    },
  },
  {
    id: 'signal',
    label: 'Signal',
    blurb: 'Maximum contrast, square corners, uppercase labels. Built to be readable over anything.',
    values: {
      accent: '#ffd400', surface: '#070707', text: '#ffffff', textMuted: '#a8a8a8', disabled: '#6e6e6e',
      surfaceAlpha: 96, outline: 30, corner: 2, gradient: 'none', gradientDepth: 0, shadow: 30,
      typeWeight: '700', typeCase: 'upper',
    },
  },
  {
    id: 'frost',
    label: 'Frost',
    blurb: 'Cool, rounded and quiet. The softest of the five.',
    values: {
      accent: '#8ec5ff', surface: '#0c1116', text: '#eef4fa', textMuted: '#93a3b3', disabled: '#66717c',
      surfaceAlpha: 90, outline: 12, corner: 22, gradient: 'linear', gradientDepth: 44, shadow: 60,
      typeWeight: '600', typeCase: 'normal',
    },
  },
]

/** Narrow preset values to controls declared by the target design schema. */
export function presetFor(preset: Preset, keys: Set<string>): Tunables {
  const out: Tunables = {}
  for (const key of Object.keys(preset.values)) {
    if (keys.has(key)) out[key] = preset.values[key]
  }
  return out
}

/** Matches current tunable values against known presets across declared schema keys. */
export function activePreset(tunables: Tunables, keys?: Set<string>): string | null {
  for (const preset of PRESETS) {
    let matches = true
    for (const key of Object.keys(preset.values)) {
      if (keys && !keys.has(key)) continue
      if (tunables[key] !== preset.values[key]) {
        matches = false
        break
      }
    }
    if (matches) return preset.id
  }
  return null
}
