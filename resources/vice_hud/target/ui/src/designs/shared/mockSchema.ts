import type { DesignControl, DesignManifestEntry, Tunables } from '../../lib/types'

/**
 * Shared tunable schema mirror for local browser preview harness.
 */

/** Mock design specification matching manifest entry and default overrides. */
export interface MockDesign extends Omit<DesignManifestEntry, 'defaults'> {
  overrides: Tunables
}

export const commonSchema = (): DesignControl[] => [
  { key: 'accent', label: 'Accent', type: 'color', default: '#14b8a6', group: 'Palette', tier: 'basic', affects: 'menu',
    help: 'Primary highlight color for active selection and focus states.' },
  { key: 'surface', label: 'Surface', type: 'color', default: '#0b0d0e', group: 'Palette', tier: 'basic', affects: 'menu',
    help: 'Background surface color for interface cards and plates.' },
  { key: 'surfaceAlpha', label: 'Surface opacity', type: 'number', default: 88, min: 30, max: 100, step: 1, group: 'Palette', unit: '%', tier: 'basic', affects: 'menu',
    help: 'Opacity level for background panels.' },
  { key: 'text', label: 'Text', type: 'color', default: '#f2f4f5', group: 'Palette', tier: 'advanced', affects: 'menu',
    help: 'Primary text color for actionable options.' },
  { key: 'textMuted', label: 'Secondary text', type: 'color', default: '#8f979c', group: 'Palette', tier: 'advanced', affects: 'menu',
    help: 'Secondary text color for descriptions and unfocused rows.' },
  { key: 'disabled', label: 'Disabled', type: 'color', default: '#6b7377', group: 'Palette', tier: 'advanced', affects: 'locked',
    help: 'Text color for disabled options.' },

  { key: 'corner', label: 'Corner radius', type: 'number', default: 12, min: 0, max: 32, step: 1, group: 'Surface', unit: 'px', tier: 'basic', affects: 'menu',
    help: 'Corner curvature radius for panels and plates.' },
  { key: 'gradient', label: 'Gradient', type: 'select', default: 'linear', group: 'Surface', tier: 'advanced', affects: 'menu',
    help: 'Background shading gradient mode.',
    options: [{ value: 'none', label: 'None' }, { value: 'linear', label: 'Linear' }, { value: 'radial', label: 'Radial' }] },
  { key: 'gradientDepth', label: 'Gradient depth', type: 'number', default: 32, min: 0, max: 100, step: 1, group: 'Surface', unit: '%', tier: 'advanced', affects: 'menu',
    help: 'Intensity of the surface gradient illumination.' },
  { key: 'outline', label: 'Outline', type: 'number', default: 14, min: 0, max: 100, step: 1, group: 'Surface', unit: '%', tier: 'advanced', affects: 'menu',
    help: 'Brightness of border outlines and divider lines.' },
  { key: 'shadow', label: 'Contact shadow', type: 'number', default: 40, min: 0, max: 100, step: 1, group: 'Surface', unit: '%', tier: 'advanced', affects: 'menu',
    help: 'Drop shadow depth and elevation behind focused elements.' },

  { key: 'typeScale', label: 'Type scale', type: 'number', default: 100, min: 80, max: 130, step: 1, group: 'Typography', unit: '%', tier: 'basic', affects: 'menu',
    help: 'Overall font size scaling factor.' },
  { key: 'labelLines', label: 'Label wrapping', type: 'select', default: '2', group: 'Typography', tier: 'basic', affects: 'menu',
    help: 'Maximum allowed lines before text truncation occurs.',
    options: [{ value: '1', label: '1 line' }, { value: '2', label: '2 lines' }, { value: '3', label: '3 lines' }] },
  { key: 'subtext', label: 'Option sub-text', type: 'boolean', default: true, group: 'Typography', tier: 'basic', affects: 'locked',
    help: 'Show descriptions and requirement reasons below option labels.' },
  { key: 'typeWeight', label: 'Label weight', type: 'select', default: '600', group: 'Typography', tier: 'advanced', affects: 'menu',
    help: 'Font stroke weight for option labels.',
    options: [{ value: '500', label: 'Medium' }, { value: '600', label: 'Semibold' }, { value: '700', label: 'Bold' }] },
  { key: 'typeCase', label: 'Label case', type: 'select', default: 'normal', group: 'Typography', tier: 'advanced', affects: 'menu',
    help: 'Text casing format.',
    options: [{ value: 'normal', label: 'Sentence' }, { value: 'upper', label: 'Uppercase' }] },

  { key: 'motion', label: 'Motion intensity', type: 'number', default: 100, min: 0, max: 150, step: 5, group: 'Motion', unit: '%', tier: 'basic', affects: 'motion',
    help: 'Travel distance multiplier for interface animations.' },
  { key: 'motionSpeed', label: 'Motion speed', type: 'number', default: 100, min: 60, max: 180, step: 5, group: 'Motion', unit: '%', tier: 'advanced', affects: 'motion',
    help: 'Animation speed rate.' },

  { key: 'disabledStyle', label: 'Gated options look', type: 'select', default: 'lock', group: 'Parts', tier: 'basic', affects: 'locked',
    help: 'Visual presentation style for disabled options.',
    options: [{ value: 'lock', label: 'Lock + reason' }, { value: 'dim', label: 'Dim + reason' }, { value: 'strike', label: 'Struck through' }] },
  { key: 'indicatorStyle', label: 'Indicator', type: 'select', default: 'ring', group: 'Parts', tier: 'advanced', affects: 'indicator',
    help: 'Shape geometry for world-anchored indicator markers.',
    options: [{ value: 'ring', label: 'Ring' }, { value: 'diamond', label: 'Diamond' }, { value: 'bracket', label: 'Bracket' }, { value: 'dot', label: 'Dot' }] },
  { key: 'indicatorAccent', label: 'Indicator uses accent', type: 'boolean', default: false, group: 'Parts', tier: 'advanced', affects: 'indicator',
    help: 'Apply accent color to idle world markers.' },
  { key: 'cursorStyle', label: 'Cursor', type: 'select', default: 'reticle', group: 'Parts', tier: 'advanced', affects: 'cursor',
    help: 'Visual style for the screen aiming reticle.',
    options: [{ value: 'reticle', label: 'Reticle' }, { value: 'crosshair', label: 'Crosshair' }, { value: 'dot', label: 'Dot' }] },

  { key: 'soundPack', label: 'Sound pack', type: 'select', default: 'signature', group: 'Sound', tier: 'basic', affects: 'sound',
    help: 'Sound theme for interaction audio cues.',
    options: [{ value: 'signature', label: 'Signature' }, { value: 'soft', label: 'Soft' }, { value: 'mechanical', label: 'Mechanical' }, { value: 'off', label: 'Silent' }] },
  { key: 'soundVolume', label: 'Sound volume', type: 'number', default: 70, min: 0, max: 100, step: 1, group: 'Sound', unit: '%', tier: 'advanced', affects: 'sound',
    help: 'Master audio volume limit for interaction sounds.' },

  { key: 'scale', label: 'Interface scale', type: 'number', default: 100, min: 60, max: 160, step: 1, group: 'Scale', unit: '%', tier: 'basic', affects: 'menu',
    help: 'Base scaling factor for world-space interface sprites.' },
]

/** Filter shared schema: exclude unsupported controls for specific design. */
export const commonSchemaExcept = (...drop: string[]): DesignControl[] =>
  commonSchema().filter((control) => !drop.includes(control.key))

/** Customize control labels: override label or help text for specific design. */
export const retune = (
  list: DesignControl[],
  wording: Record<string, { label?: string; help?: string }>,
): DesignControl[] => list.map((control) => ({ ...control, ...(wording[control.key] ?? {}) }))
