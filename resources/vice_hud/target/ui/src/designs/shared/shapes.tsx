export type IndicatorShapeName = 'ring' | 'diamond' | 'bracket' | 'dot'
export type CursorShapeName = 'reticle' | 'crosshair' | 'dot'

interface ShapeProps {
  shape: IndicatorShapeName
  color: string
  /** Stroke width in canvas units (256 canvas). */
  weight?: number
  /** 0-1: how "engaged" the shape is; drives the gap and the core size. */
  charge?: number
  opacity?: number
}

export function IndicatorShape({ shape, color, weight = 10, charge = 0, opacity = 1 }: ShapeProps) {
  const core = 12 + charge * 12
  const spread = 74 - charge * 10

  return (
    <svg viewBox="0 0 256 256" width="100%" height="100%" style={{ opacity, overflow: 'visible' }}>
      {shape === 'ring' && (
        <>
          <circle cx="128" cy="128" r={spread} fill="none" stroke={color} strokeWidth={weight}
            strokeDasharray={`${18 + charge * 40} ${26 - charge * 10}`} strokeLinecap="round" />
          <circle cx="128" cy="128" r={core} fill={color} />
        </>
      )}

      {shape === 'diamond' && (
        <>
          <rect x={128 - spread * 0.72} y={128 - spread * 0.72} width={spread * 1.44} height={spread * 1.44}
            fill="none" stroke={color} strokeWidth={weight} strokeLinejoin="round"
            transform={`rotate(45 128 128)`} rx={6} />
          <rect x={128 - core} y={128 - core} width={core * 2} height={core * 2}
            fill={color} transform="rotate(45 128 128)" rx={3} />
        </>
      )}

      {shape === 'bracket' && (
        <>
          {[
            `M ${128 - spread} ${128 - spread + 34} L ${128 - spread} ${128 - spread} L ${128 - spread + 34} ${128 - spread}`,
            `M ${128 + spread - 34} ${128 - spread} L ${128 + spread} ${128 - spread} L ${128 + spread} ${128 - spread + 34}`,
            `M ${128 + spread} ${128 + spread - 34} L ${128 + spread} ${128 + spread} L ${128 + spread - 34} ${128 + spread}`,
            `M ${128 - spread + 34} ${128 + spread} L ${128 - spread} ${128 + spread} L ${128 - spread} ${128 + spread - 34}`,
          ].map((d, i) => (
            <path key={i} d={d} fill="none" stroke={color} strokeWidth={weight} strokeLinecap="square" />
          ))}
          <rect x={128 - core * 0.7} y={128 - 2} width={core * 1.4} height={4} fill={color} />
          <rect x={128 - 2} y={128 - core * 0.7} width={4} height={core * 1.4} fill={color} />
        </>
      )}

      {shape === 'dot' && (
        // The ring has to clear the core at FULL charge, not just at rest: the
        // core grows and the ring contracts, and sized any closer together the
        // two meet and the marker reads as a plain blob at the exact moment it
        // is meant to read as locked on.
        <>
          <circle cx="128" cy="128" r={spread * 0.72} fill="none" stroke={color}
            strokeWidth={weight * 0.6} opacity={0.35 + charge * 0.4} />
          <circle cx="128" cy="128" r={core * 0.75 + 3} fill={color} />
        </>
      )}
    </svg>
  )
}

/* Shared, so a padlock means the same thing in every design. */

/** Drawn only under the `lock` treatment; `dim` and `strike` say it another way. */
export function LockGlyph({ size = 30, color = 'var(--t-disabled)' }: { size?: number; color?: string }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} style={{ flexShrink: 0, color }}>
      <rect x="5" y="10.5" width="14" height="10" rx="2.2" fill="currentColor" />
      <path d="M 8 10.5 V 7.5 a 4 4 0 0 1 8 0 v 3" fill="none" stroke="currentColor" strokeWidth="2" />
    </svg>
  )
}

export function ChevronGlyph({ size = 26, color = 'var(--t-text-muted)' }: { size?: number; color?: string }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} style={{ flexShrink: 0, color }}>
      <path d="M 9 5 L 16 12 L 9 19" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

interface CursorProps {
  shape: CursorShapeName
  color: string
  weight?: number
}

export function CursorShape({ shape, color, weight = 8 }: CursorProps) {
  return (
    <svg viewBox="0 0 128 128" width="100%" height="100%" style={{ overflow: 'visible' }}>
      {shape === 'reticle' && (
        <>
          <circle cx="64" cy="64" r="34" fill="none" stroke={color} strokeWidth={weight}
            strokeDasharray="14 20" strokeLinecap="round" opacity="0.9" />
          <circle cx="64" cy="64" r="6" fill={color} />
        </>
      )}

      {shape === 'crosshair' && (
        <>
          <path d="M 64 22 L 64 46 M 64 82 L 64 106 M 22 64 L 46 64 M 82 64 L 106 64"
            stroke={color} strokeWidth={weight} strokeLinecap="square" />
          <circle cx="64" cy="64" r="4" fill={color} />
        </>
      )}

      {shape === 'dot' && (
        <>
          <circle cx="64" cy="64" r="26" fill="none" stroke={color} strokeWidth={weight * 0.5} opacity="0.4" />
          <circle cx="64" cy="64" r="10" fill={color} />
        </>
      )}
    </svg>
  )
}
