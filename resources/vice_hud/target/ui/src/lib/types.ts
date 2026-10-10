export type SurfaceKind = 'app' | 'menu' | 'indicator' | 'cursor'
export type IndicatorState = 'idle' | 'near' | 'active'

/** Badge icon and color styling descriptor for an option item. */
export interface OptionBadge {
  icon: string
  color?: string
}

/** Resolved target option data model. */
export interface TargetOption {
  id: number
  label: string
  description?: string
  icon?: string
  iconColor?: string
  badges?: OptionBadge[]
  /** Eligibility flag: false indicates player cannot confirm action. */
  enabled: boolean
  /** Requirement explanation displayed for ineligible options. */
  reason?: string
  /** Focusable flag: allows inspecting requirements on disabled options. */
  focusable: boolean
  /** Indicates option opens a submenu. */
  submenu: boolean
  /**
   * Live binding label for this option's own dedicated key, resolved the same
   * way as `InputPrompts.confirm` (raw `GetControlInstructionalButton` text,
   * mapped through the same device-aware glyph table by the design). Only
   * meaningful - and only ever populated by the host - when the menu payload's
   * `mode` is `'direct'`: a 3+ option list still scrolls through one shared
   * confirm, so it has no use for a per-row key.
   */
  directKey?: string
}

/**
 * Which shape the design should render the menu as:
 * - `'list'` - the existing scrolling rail (3+ options, or fewer with the
 *   collapsed prompt disabled).
 * - `'collapsed'` - a single row (bound expand key + submenu indicator +
 *   entity label) shown before a 3+ option list is opened.
 * - `'direct'` - every option (1-2 of them) shown at once, each with its own
 *   independently bound `TargetOption.directKey`, no scrolling involved.
 *
 * Absent entirely, a design built against the original SDK 1 contract (before
 * this field existed) should treat it as `'list'` - the only shape it already
 * knows how to draw.
 */
export type MenuMode = 'list' | 'collapsed' | 'direct'

export interface MenuOpenPayload {
  options: TargetOption[]
  focus: number
  menu?: string
  empty: boolean
  emptyLabel: string
  /** Defaults to `'list'` when absent. */
  mode?: MenuMode
  /** Entity/menu label to print beside the collapsed prompt's key. Only sent
   *  when `mode` is `'collapsed'`. */
  collapseLabel?: string
}

export interface MenuFocusPayload {
  focus: number
}

/** Appearance sync payload containing active design tokens and player preferences. */
export interface AppearancePayload {
  design: string
  /** Installed pack version for client cache busting. */
  version?: string
  tunables: Tunables
  /** World anchor offset fraction relative to sprite center. */
  anchor?: { x: number; y: number }
  prefs: Preferences
  timings: { open: number; close: number }
}

/** Which family of pad button art to draw. GetControlInstructionalButton
 *  cannot tell Xbox and PlayStation apart on its own (see InputPrompts'
 *  own comment) -- this is a player preference, not a detection. */
export type PadBrand = 'xbox' | 'playstation'

export interface Preferences {
  scale: number
  volume: number
  muted: boolean
  reducedMotion: boolean
  padBrand: PadBrand
}

/** Tunable configuration key-value map. */
export type Tunables = Record<string, string | number | boolean>

export type ControlType = 'color' | 'number' | 'select' | 'boolean'

/** Preview surface target associated with a specific control. */
export type ControlAffects = 'menu' | 'locked' | 'motion' | 'indicator' | 'cursor' | 'sound'

export interface DesignControl {
  key: string
  label: string
  type: ControlType
  default: string | number | boolean
  group: string
  help?: string
  unit?: string
  min?: number
  max?: number
  step?: number
  options?: { value: string; label: string; title?: string }[]
  widget?: 'select' | 'segmented'
  /** Tier visibility categorization for administrative controls. */
  tier?: 'basic' | 'advanced'
  affects?: ControlAffects
}

/** Dynamic anchor rule mapping tunable options to coordinate offsets. */
export interface AnchorRule {
  /** Tunable key to switch on. */
  key: string
  /** Anchor offset coordinate mapping per tunable value. */
  values: Record<string, { x: number; y: number }>
}

export interface DesignManifestEntry {
  id: string
  label: string
  tagline: string
  accent: string
  anchor?: { x: number; y: number }
  anchorRule?: AnchorRule
  /** Visual prominence flag in administration UI. */
  exclusive?: boolean
  /** Pack version string for cache-busting bundle URL. */
  version?: string
  schema: DesignControl[]
  /** Baseline default values merged with design-specific overrides. */
  defaults?: Tunables
}

export interface StoredConfig {
  design: string
  designs: Record<string, Tunables>
  system: Record<string, string | number | boolean>
}

export interface AdminOpenPayload {
  config: StoredConfig
  designs: DesignManifestEntry[]
  prefs: Preferences
}

export interface DesignRuntime {
  tunables: Tunables
  reducedMotion: boolean
  /** Scaled animation duration in milliseconds. */
  openMs: number
  closeMs: number
}

/** Which device the player is currently using. */
export type InputDevice = 'kbm' | 'pad'

/**
 * The player's live bindings. On keyboard/mouse this is genuine resolved text
 * from GetControlInstructionalButton (a letter, "LMB", etc). On a pad it is
 * NOT: confirmed live against a real controller (2026-09-13) that native
 * returns an opaque internal button-icon code for face buttons ("b_2000" for
 * INPUT_FRONTEND_X, "b_1002" for INPUT_FRONTEND_Y, even "b_1003" for
 * INPUT_FRONTEND_ACCEPT), not resolvable text - so for a pad, `confirm`/
 * `cancel`/each option's own `directKey` (see TargetOption) instead carry a
 * `CTRL_<id>` sentinel (client/target/input.lua's labelFor), and this design
 * maps the ids it has real art for (CONTROL_ICONS) rather than trying to
 * print anything from the native's own text.
 */
export interface InputPrompts {
  device: InputDevice
  confirm: string
  cancel: string
  /** Which family of art to use for a `CTRL_<id>` sentinel. Meaningless on
   *  keyboard/mouse, where `confirm`/`cancel`/`directKey` are already text. */
  padBrand: PadBrand
}

export interface MenuViewProps extends DesignRuntime {
  /** Undefined until the first prompt sync arrives. */
  input?: InputPrompts
  options: TargetOption[]
  focus: number
  /** Token sequence counter triggering refusal feedback animation. */
  rejectToken: number
  phase: 'opening' | 'open' | 'closing'
  emptyLabel: string
  /**
   * Additive since SDK 1's initial publish: absent on a payload from a host
   * that predates it, and absent when the design pack itself is running as an
   * older bundle only reading the fields it knows - either way, treat missing
   * as `'list'`, the original always-a-scrolling-list behaviour.
   */
  mode?: MenuMode
  /** See `MenuOpenPayload.collapseLabel`. Only meaningful when `mode` is `'collapsed'`. */
  collapseLabel?: string
}

export interface IndicatorViewProps extends DesignRuntime {
  state: IndicatorState
  /** Token sequence counter triggering indicator activation animation. */
  activateToken: number
}

export interface CursorViewProps extends DesignRuntime {}

/** Dynamic web font declaration for design packs. */
export interface DesignFont {
  /** Tunable key selecting this font family. */
  key: string
  /** CSS font stack string. */
  stack: string
  /** Stylesheet URL to inject dynamically if not already loaded. */
  href?: string
}

/** Design pack component module definition interface. */
export interface DesignModule {
  id: string
  /** Target SDK version supported by design module. */
  sdk: number
  Menu: React.ComponentType<MenuViewProps>
  Indicator: React.ComponentType<IndicatorViewProps>
  Cursor: React.ComponentType<CursorViewProps>
  /** Dynamic web typography definitions registered by design module. */
  fonts?: DesignFont[]
}
