import type { CSSProperties } from 'react'
import type { Tunables } from '../../lib/types'

/** Typed configuration reader: retrieve number values with fallback defaults. */
export const readNumber = (t: Tunables, key: string, fallback: number): number =>
  typeof t[key] === 'number' ? (t[key] as number) : fallback

/** Typed configuration reader: retrieve string values with fallback defaults. */
export const readString = (t: Tunables, key: string, fallback: string): string =>
  typeof t[key] === 'string' ? (t[key] as string) : fallback

/** Typed configuration reader: retrieve boolean values with fallback defaults. */
export const readBool = (t: Tunables, key: string, fallback: boolean): boolean =>
  typeof t[key] === 'boolean' ? (t[key] as boolean) : fallback

/** Standard easing curve for interface transitions. */
export const EASE = 'cubic-bezier(0.165, 0.84, 0.44, 1)'

/** Scale transition duration: adjust timing based on motion speed and reduced-motion preferences. */
export function duration(ms: number, t: Tunables, reducedMotion: boolean): number {
  if (reducedMotion) return 0
  const speed = readNumber(t, 'motionSpeed', 100)
  const intensity = readNumber(t, 'motion', 100) / 100
  if (intensity <= 0) return 0
  return Math.round(ms * (100 / Math.max(20, speed)))
}

/** Compute motion intensity multiplier: return normalized multiplier or 0 for reduced motion. */
export function intensity(t: Tunables, reducedMotion: boolean): number {
  if (reducedMotion) return 0
  return readNumber(t, 'motion', 100) / 100
}

/** Calculate travel offset distance: scale pixel travel distance by motion intensity. */
export function amp(px: number, t: Tunables, reducedMotion: boolean): number {
  return Math.round(px * intensity(t, reducedMotion) * 100) / 100
}

/** Motion gate evaluation: return duration if motion is active, else zero. */
export function gate(ms: number, t: Tunables, reducedMotion: boolean): number {
  return intensity(t, reducedMotion) > 0 ? ms : 0
}

/** Retrieve configured label line wrapping budget. */
export const labelLines = (t: Tunables): number => {
  const parsed = parseInt(readString(t, 'labelLines', '2'), 10)
  return Number.isFinite(parsed) ? Math.min(3, Math.max(1, parsed)) : 2
}

/** Compute multi-line clamping CSS styles. */
export function clampLines(lines: number): CSSProperties {
  return {
    display: '-webkit-box',
    WebkitBoxOrient: 'vertical',
    WebkitLineClamp: lines,
    overflow: 'hidden',
    overflowWrap: 'anywhere',
  } as CSSProperties
}

/** Generate label typography styles from active CSS variable tokens. */
export function labelType(sizePx: number): CSSProperties {
  return {
    fontSize: `calc(${sizePx}px * var(--t-type-scale))`,
    fontWeight: 'var(--t-type-weight)' as unknown as number,
    letterSpacing: 'var(--t-type-track)',
    textTransform: 'var(--t-type-case)' as 'none',
  }
}

export type DisabledStyle = 'lock' | 'dim' | 'strike'

export const disabledStyle = (t: Tunables): DisabledStyle =>
  readString(t, 'disabledStyle', 'lock') as DisabledStyle

/** Generate CSS styling for ineligible option labels based on active style presentation. */
export function gatedLabel(style: DisabledStyle): CSSProperties {
  if (style === 'strike') {
    return {
      color: 'var(--t-disabled)',
      textDecoration: 'line-through',
      textDecorationThickness: '0.09em',
      textDecorationColor: 'var(--t-disabled)',
    }
  }
  if (style === 'dim') return { color: 'var(--t-disabled)', opacity: 0.72 }
  return { color: 'var(--t-disabled)' }
}

/** Determine if padlock icon should render for disabled style. */
export const showsLock = (style: DisabledStyle): boolean => style === 'lock'
