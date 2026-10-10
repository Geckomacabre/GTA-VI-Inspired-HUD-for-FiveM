import { commonSchemaExcept, retune } from '../shared/mockSchema'
import type { MockDesign } from '../shared/mockSchema'

/**
 * Design schema preview mock: development mirror of designs/rail/design.lua for browser harness.
 */
export const mock: MockDesign = {
  id: 'rail',
  label: 'Context Rail',
  tagline: 'A vertical rail pinned to the entity. Scroll walks the rows past a fixed focus node, and locked rows say why on the spot.',
  accent: '#ffffff',
  anchor: { x: 0.34, y: 0 },
  anchorRule: {
    key: 'listSide',
    values: {
      right: { x: 0.34, y: 0 },
      left: { x: -0.34, y: 0 },
    },
  },
  schema: [
    ...retune(commonSchemaExcept('surfaceAlpha', 'gradient', 'gradientDepth', 'corner', 'shadow'), {
      surface: { label: 'Scrim colour', help: 'Colour of the soft darkening drawn behind the rows.' },
      outline: { label: 'Rail brightness', help: 'Brightness of the rail line and its dots.' },
    }),

    { key: 'listSide', label: 'List opens', type: 'select', default: 'right', group: 'Design', tier: 'basic', affects: 'menu',
      help: 'Side of the entity the rows are laid out on.',
      options: [{ value: 'right', label: 'Right' }, { value: 'left', label: 'Left' }] },
    { key: 'listWidth', label: 'Text column width', type: 'number', default: 680, min: 320, max: 820, step: 10, group: 'Design', unit: 'px', tier: 'basic', affects: 'menu',
      help: 'Width of the label column before text wraps.' },
    { key: 'visible', label: 'Rows in view', type: 'number', default: 5, min: 3, max: 8, step: 1, group: 'Design', tier: 'basic', affects: 'menu',
      help: 'How many rows are on screen at once. Longer lists scroll through the window.' },
    { key: 'focusEmphasis', label: 'Focus emphasis', type: 'number', default: 124, min: 100, max: 145, step: 1, group: 'Design', unit: '%', tier: 'basic', affects: 'menu',
      help: 'Size of the focused label against the rest of the list.' },
    { key: 'confirmGlyph', label: 'Confirm glyph', type: 'select', default: 'auto', group: 'Design', tier: 'basic', affects: 'menu',
      help: "Mark drawn inside the focused rail node. Bound key follows the player's live binding and swaps when they pick up a controller; the rest are fixed.",
      options: [{ value: 'auto', label: 'Bound key' }, { value: 'cross', label: 'Cross' }, { value: 'mouse', label: 'Mouse' }, { value: 'dot', label: 'Dot' }, { value: 'none', label: 'Ring only' }] },
    { key: 'anchorMode', label: 'Focus behaviour', type: 'select', default: 'slot', group: 'Design', tier: 'advanced', affects: 'menu',
      help: 'Slot parks the focused row on the entity and moves the list past it. List holds the rows still and walks the focus down them.',
      options: [{ value: 'slot', label: 'Fixed slot' }, { value: 'list', label: 'Moving focus' }] },
    { key: 'rowGap', label: 'Row spacing', type: 'number', default: 86, min: 60, max: 140, step: 2, group: 'Design', unit: 'px', tier: 'advanced', affects: 'menu',
      help: 'Vertical distance between rows.' },
    { key: 'railStyle', label: 'Rail', type: 'select', default: 'line', group: 'Design', tier: 'advanced', affects: 'menu',
      help: 'Line runs a hairline through the nodes, Dots leaves the nodes standing alone.',
      options: [{ value: 'line', label: 'Line' }, { value: 'dots', label: 'Dots' }, { value: 'none', label: 'None' }] },
    { key: 'rowIcon', label: 'Option icons', type: 'select', default: 'none', group: 'Design', tier: 'advanced', affects: 'menu',
      help: 'Whether a registered option icon is drawn beside its label.',
      options: [{ value: 'none', label: 'Never' }, { value: 'focus', label: 'Focused row' }, { value: 'all', label: 'Every row' }] },
    { key: 'submenuGlyph', label: 'Submenu mark', type: 'select', default: 'dots', group: 'Design', tier: 'advanced', affects: 'menu',
      help: 'Mark shown on rows that open a nested menu.',
      options: [{ value: 'dots', label: 'Three dots' }, { value: 'chevron', label: 'Chevron' }, { value: 'none', label: 'None' }] },
    { key: 'counter', label: 'Position counter', type: 'boolean', default: false, group: 'Design', tier: 'advanced', affects: 'menu',
      help: 'Show the focused row number and the option count under the rail.' },

    { key: 'scrim', label: 'Scrim', type: 'number', default: 38, min: 0, max: 100, step: 1, group: 'Surface', unit: '%', tier: 'basic', affects: 'menu',
      help: 'Strength of the soft darkening behind the rows. Keeps white text legible against bright surfaces.' },
    { key: 'textOutline', label: 'Text keyline', type: 'number', default: 60, min: 0, max: 100, step: 1, group: 'Surface', unit: '%', tier: 'basic', affects: 'menu',
      help: 'Contrast shadow drawn under every glyph.' },

    { key: 'fontFamily', label: 'Typeface', type: 'select', default: 'barlow', group: 'Typography', tier: 'basic', affects: 'menu',
      help: 'Condensed faces match the reference look. Each falls back to a system face if the font cannot be fetched.',
      options: [
        { value: 'barlow', label: 'Barlow Semi Condensed' },
        { value: 'oswald', label: 'Oswald' },
        { value: 'saira', label: 'Saira Condensed' },
        { value: 'archivo', label: 'Archivo Narrow' },
        { value: 'ui', label: 'Plus Jakarta Sans' },
      ] },
  ],
  overrides: {
    accent: '#ffffff', surface: '#05070a',
    text: '#ffffff', textMuted: '#c2c9ce', disabled: '#939ba1',
    outline: 24, typeCase: 'upper', typeWeight: '700', labelLines: '1',
    indicatorStyle: 'dot', cursorStyle: 'dot', disabledStyle: 'lock',
  },
}
