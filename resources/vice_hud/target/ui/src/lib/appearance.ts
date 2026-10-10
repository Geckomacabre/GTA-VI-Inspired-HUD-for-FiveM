import { useEffect, useState } from 'react'
import { useNuiEvent } from './useNuiEvent'
import { surfaceParams } from './nui'
import type { AppearancePayload, DesignFont, DesignManifestEntry, Preferences, Tunables } from './types'

const DEFAULT_PREFS: Preferences = { scale: 100, volume: 70, muted: false, reducedMotion: false, padBrand: 'xbox' }

/** Convert hex color string to RGB comma-separated values. */
export function hexToRgb(hex: string): string {
  const value = hex.replace('#', '')
  const full = value.length === 3 ? value.split('').map((c) => c + c).join('') : value
  const int = parseInt(full, 16)
  if (Number.isNaN(int)) return '255, 255, 255'
  return `${(int >> 16) & 255}, ${(int >> 8) & 255}, ${int & 255}`
}

export function rgba(hex: string, alpha: number): string {
  return `rgba(${hexToRgb(hex)}, ${alpha})`
}

// Default font stack definitions
const FONT_STACKS: Record<string, string> = {
  ui: "'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
  jakarta: "'Plus Jakarta Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif",
}

const injectedFonts = new Set<string>()
const fontListeners = new Set<() => void>()
let fontEpoch = 0

/** Register dynamic design fonts and inject external stylesheets. */
export function registerFonts(fonts: DesignFont[] | undefined) {
  if (!fonts || fonts.length === 0) return

  let changed = false

  for (const font of fonts) {
    if (FONT_STACKS[font.key] !== font.stack) {
      FONT_STACKS[font.key] = font.stack
      changed = true
    }

    if (!font.href || injectedFonts.has(font.href)) continue
    injectedFonts.add(font.href)

    const link = document.createElement('link')
    link.rel = 'stylesheet'
    link.href = font.href
    document.head.appendChild(link)
    changed = true
  }

  if (!changed) return
  fontEpoch += 1
  for (const listener of fontListeners) listener()
}

/** Subscribe to font registry updates to trigger style recalibration. */
function useFontEpoch(): number {
  const [epoch, setEpoch] = useState(fontEpoch)

  useEffect(() => {
    const listener = () => setEpoch(fontEpoch)
    fontListeners.add(listener)
    if (fontEpoch !== epoch) setEpoch(fontEpoch)
    return () => {
      fontListeners.delete(listener)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return epoch
}

const num = (t: Tunables, key: string, fallback: number): number => {
  const value = t[key]
  return typeof value === 'number' ? value : fallback
}

const str = (t: Tunables, key: string, fallback: string): string => {
  const value = t[key]
  return typeof value === 'string' ? value : fallback
}

/** Apply design tokens: write computed CSS variables to root element. */
export function applyTunables(tunables: Tunables, prefs: Preferences) {
  const root = document.documentElement.style

  const accent = str(tunables, 'accent', '#14b8a6')
  const surface = str(tunables, 'surface', '#0b0d0e')
  const surfaceAlpha = num(tunables, 'surfaceAlpha', 88) / 100

  root.setProperty('--t-accent', accent)
  root.setProperty('--t-accent-rgb', hexToRgb(accent))
  root.setProperty('--t-accent-soft', rgba(accent, 0.16))
  root.setProperty('--t-accent-glow', rgba(accent, 0.34))

  root.setProperty('--t-surface', surface)
  root.setProperty('--t-surface-rgb', hexToRgb(surface))
  root.setProperty('--t-surface-alpha', String(surfaceAlpha))
  root.setProperty('--t-surface-fill', rgba(surface, surfaceAlpha))
  root.setProperty('--t-surface-fill-soft', rgba(surface, surfaceAlpha * 0.86))

  const text = str(tunables, 'text', '#f2f4f5')
  root.setProperty('--t-text', text)
  root.setProperty('--t-text-muted', str(tunables, 'textMuted', '#8f979c'))
  root.setProperty('--t-disabled', str(tunables, 'disabled', '#6b7377'))

  const outlineRgb = hexToRgb(text)
  const outline = num(tunables, 'outline', 14) / 100
  root.setProperty('--t-outline', `rgba(${outlineRgb}, ${outline.toFixed(3)})`)
  root.setProperty('--t-outline-strong', `rgba(${outlineRgb}, ${Math.min(1, outline * 2.2).toFixed(3)})`)
  root.setProperty('--t-corner', `${num(tunables, 'corner', 12)}px`)

  const shadow = num(tunables, 'shadow', 40) / 100
  root.setProperty('--t-shadow', `0 ${18 * shadow + 6}px ${48 * shadow + 12}px rgba(0, 0, 0, ${(0.55 * shadow).toFixed(3)})`)

  const depth = num(tunables, 'gradientDepth', 32) / 100
  const gradient = str(tunables, 'gradient', 'linear')
  root.setProperty(
    '--t-gradient',
    gradient === 'none'
      ? 'none'
      : gradient === 'radial'
        ? `radial-gradient(120% 120% at 20% 0%, rgba(255,255,255,${(0.10 * depth).toFixed(3)}) 0%, rgba(255,255,255,0) 62%)`
        : `linear-gradient(160deg, rgba(255,255,255,${(0.10 * depth).toFixed(3)}) 0%, rgba(255,255,255,0) 58%)`,
  )

  root.setProperty('--t-font', FONT_STACKS[str(tunables, 'fontFamily', 'ui')] ?? FONT_STACKS.ui)

  root.setProperty('--t-type-scale', String(num(tunables, 'typeScale', 100) / 100))
  root.setProperty('--t-type-weight', str(tunables, 'typeWeight', '600'))
  root.setProperty('--t-type-case', str(tunables, 'typeCase', 'normal') === 'upper' ? 'uppercase' : 'none')
  root.setProperty('--t-type-track', str(tunables, 'typeCase', 'normal') === 'upper' ? '0.08em' : '-0.005em')

  const motion = prefs.reducedMotion ? 0 : num(tunables, 'motion', 100) / 100
  root.setProperty('--t-motion', String(motion))
  root.setProperty('--t-duration', String(100 / Math.max(20, num(tunables, 'motionSpeed', 100))))

  root.setProperty('--t-scale', '1')
}

/** Calculate dynamic anchor coordinates based on manifest rule definitions. */
export function anchorFor(
  manifest: DesignManifestEntry | undefined,
  tunables: Tunables,
): { x: number; y: number } {
  const anchor = manifest?.anchor ?? { x: 0, y: 0 }
  const rule = manifest?.anchorRule
  if (!rule) return anchor

  const selected = tunables[rule.key]
  if (typeof selected !== 'string') return anchor

  return rule.values[selected] ?? anchor
}

/** Subscribe to live appearance NUI events and synchronize CSS variables. */
export function useAppearance() {
  const [design, setDesign] = useState<string>(() => surfaceParams().design)
  const [version, setVersion] = useState<string | undefined>(() => surfaceParams().version)
  const [tunables, setTunables] = useState<Tunables>({})
  const [prefs, setPrefs] = useState<Preferences>(DEFAULT_PREFS)
  const [timings, setTimings] = useState({ open: 220, close: 160 })
  const [anchor, setAnchor] = useState({ x: 0, y: 0 })

  useNuiEvent<AppearancePayload>('appearance', (data) => {
    if (data.design) setDesign(data.design)
    if (data.version) setVersion(data.version)
    if (data.tunables) setTunables(data.tunables)
    if (data.anchor) setAnchor(data.anchor)
    if (data.prefs) setPrefs({ ...DEFAULT_PREFS, ...data.prefs })
    if (data.timings) setTimings(data.timings)
  })

  const fontEpoch = useFontEpoch()

  useEffect(() => {
    applyTunables(tunables, prefs)
  }, [tunables, prefs, fontEpoch])

  useEffect(() => {
    document.documentElement.style.setProperty('--t-anchor-x', String(anchor.x ?? 0))
    document.documentElement.style.setProperty('--t-anchor-y', String(anchor.y ?? 0))
  }, [anchor])

  const speed = typeof tunables.motionSpeed === 'number' ? tunables.motionSpeed : 100

  return {
    design,
    version,
    tunables,
    prefs,
    reducedMotion: prefs.reducedMotion,
    openMs: Math.round(timings.open * (100 / Math.max(20, speed))),
    closeMs: Math.round(timings.close * (100 / Math.max(20, speed))),
  }
}
