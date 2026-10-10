import { useEffect, useRef, useState, type CSSProperties } from 'react'
import { useDesignModule } from '../designs'
import { anchorFor } from '../lib/appearance'
import type { DesignManifestEntry, IndicatorState, TargetOption, Tunables } from '../lib/types'

export type SampleName = 'typical' | 'single' | 'long' | 'gated' | 'empty'

const TYPICAL: TargetOption[] = [
  { id: 1, label: 'Open trunk', icon: 'trunk', enabled: true, focusable: true, submenu: false },
  { id: 2, label: 'Search vehicle', description: 'Takes about 8 seconds', icon: 'search', enabled: true, focusable: true, submenu: false },
  { id: 3, label: 'Hotwire', icon: 'lockpick', enabled: false, reason: 'Requires Lockpick', focusable: true, submenu: false },
  { id: 4, label: 'Impound', icon: 'shield', enabled: false, reason: 'Police only', focusable: true, submenu: false },
  { id: 5, label: 'Repair', icon: 'wrench', enabled: true, focusable: true, submenu: true },
  // Sample option badge test data: verifies multi-badge rendering.
  { id: 6, label: 'Refuel', icon: 'fuel', iconColor: '#3ddc97', enabled: true, focusable: true, submenu: false,
    badges: [{ icon: 'eye', color: '#a06cff' }] },
]

// Stress test sample options: verifies text wrapping and boundary layout under long labels.
const LONG: TargetOption[] = [
  { id: 1, label: 'Change Vehicle Tyres', description: 'Front and rear, from the boot kit', icon: 'wheel', enabled: true, focusable: true, submenu: true },
  { id: 2, label: 'Register vehicle at the DMV office', icon: 'clipboard', enabled: true, focusable: true, submenu: false },
  { id: 3, label: 'Sell to chop shop for $12,400', icon: 'cash', enabled: false, reason: 'Requires Bolt Cutters x2', focusable: true, submenu: false },
  { id: 4, label: 'Transfer ownership to another player', icon: 'handshake', enabled: false, reason: 'Nobody nearby to transfer to', focusable: true, submenu: false },
  { id: 5, label: 'Store in the Legion Square garage', icon: 'building', enabled: true, focusable: true, submenu: false },
]

const GATED: TargetOption[] = [
  { id: 1, label: 'Hotwire', icon: 'lockpick', enabled: false, reason: 'Requires Lockpick', focusable: true, submenu: false },
  { id: 2, label: 'Change Vehicle Tyres', icon: 'wheel', enabled: false, reason: 'Requires Tyre Kit x1', focusable: true, submenu: false },
  { id: 3, label: 'Impound', icon: 'shield', enabled: false, reason: 'Police only', focusable: true, submenu: false },
  { id: 4, label: 'Open trunk', icon: 'trunk', enabled: true, focusable: true, submenu: false },
]

// Single option sample: verifies minimal option layout behaviour.
const SINGLE: TargetOption[] = [
  { id: 1, label: 'Fridge', icon: undefined, enabled: true, focusable: true, submenu: true },
]

const SAMPLES: Record<SampleName, TargetOption[]> = {
  typical: TYPICAL,
  single: SINGLE,
  long: LONG,
  gated: GATED,
  empty: [],
}

// Preview sample descriptors: provides segment tab labels and descriptive titles.
export const SAMPLE_LABELS: { value: SampleName; label: string; title: string }[] = [
  { value: 'typical', label: 'Typical', title: 'Six options: named, described, gated and a submenu' },
  { value: 'single', label: 'Single', title: 'One option — the state most doors and tills are in' },
  { value: 'long', label: 'Long', title: 'Names long enough to break a careless layout' },
  { value: 'gated', label: 'Gated', title: 'Mostly options the player is not eligible for' },
  { value: 'empty', label: 'Empty', title: 'Nothing registered on the entity' },
]

export function sampleOptions(name: SampleName): TargetOption[] {
  return SAMPLES[name]
}

/** First option in a sample the player cannot use, 1-based. */
export function firstGated(name: SampleName): number {
  const index = SAMPLES[name].findIndex((option) => !option.enabled)
  return index < 0 ? 1 : index + 1
}

export interface StageState {
  view: 'menu' | 'indicator' | 'cursor'
  sample: SampleName
  focus: number
  indicator: IndicatorState
  /** Token bumped to trigger open animation replay. */
  playToken: number
  /** Token bumped to trigger interaction refusal animation. */
  rejectToken: number
  /** Enables auto-cycling focus in preview mode. */
  auto: boolean
}

export const INITIAL_STAGE: StageState = {
  view: 'menu',
  sample: 'typical',
  focus: 2,
  indicator: 'near',
  playToken: 0,
  rejectToken: 0,
  auto: true,
}

interface Props {
  designId: string
  tunables: Tunables
  manifest?: DesignManifestEntry
  stage: StageState
  onStage: (patch: Partial<StageState>) => void
  width: number
  height: number
  /** In-game canvas-to-screen scaling ratio. */
  scale?: number
}

export function DesignPreview({ designId, tunables, manifest, stage, onStage, width, height, scale = 0.38 }: Props) {
  const design = useDesignModule(designId, manifest?.version)
  const options = sampleOptions(stage.sample)

  // Triggers entrance transition when playToken updates.
  const phase = useReplay(stage.playToken)

  useEffect(() => {
    if (!stage.auto || stage.view !== 'menu' || options.length === 0) return
    const timer = window.setInterval(() => {
      onStage({ focus: (stage.focus % options.length) + 1 })
    }, 2200)
    return () => window.clearInterval(timer)
  }, [stage.auto, stage.view, stage.focus, options.length, onStage])

  // Clamp focus index: keeps valid focus when switching between sample option lists.
  const focus = options.length === 0 ? 1 : Math.min(stage.focus, options.length)

  const anchor = anchorFor(manifest, tunables)

  // Calculate sprite scale transform: normalizes tunable percentage to CSS scale factor.
  const designScale = typeof tunables.scale === 'number' ? tunables.scale / 100 : 1

  const vars = {
    '--t-anchor-x': String(anchor.x ?? 0),
    '--t-anchor-y': String(anchor.y ?? 0),
    '--t-scale': String(designScale),
  } as CSSProperties

  return (
    <div
      className="relative overflow-hidden rounded-xl border border-white/[0.07]"
      style={{
        width,
        height,
        background: 'radial-gradient(120% 100% at 50% 0%, #16181c 0%, #0a0a0b 70%)',
      }}
    >
      <GameGrid />

      <div
        style={{
          position: 'absolute',
          left: '50%',
          top: '50%',
          width: 1024,
          height: 1024,
          marginLeft: -512,
          marginTop: -512,
          transform: `scale(${scale})`,
          transformOrigin: 'center center',
          ...vars,
        }}
      >
        {design && stage.view === 'menu' && (
          <div className="world world--biased">
            <design.Menu
              options={options}
              focus={focus}
              rejectToken={stage.rejectToken}
              phase={phase}
              emptyLabel="Nothing to do here"
              // The preview has no game to read a binding from, so it stands in
              // for a keyboard player: designs drawing the live bind show
              // something representative instead of falling back.
              input={{ device: 'kbm', confirm: 'MOUSE1', cancel: 'MOUSE2', padBrand: 'xbox' }}
              tunables={tunables}
              reducedMotion={false}
              openMs={220}
              closeMs={160}
            />
          </div>
        )}

        {design && stage.view === 'indicator' && (
          <Centred size={256}>
            <design.Indicator
              state={stage.indicator}
              activateToken={stage.playToken}
              tunables={tunables}
              reducedMotion={false}
              openMs={220}
              closeMs={160}
            />
          </Centred>
        )}

        {design && stage.view === 'cursor' && (
          <Centred size={128}>
            <design.Cursor tunables={tunables} reducedMotion={false} openMs={220} closeMs={160} />
          </Centred>
        )}
      </div>

      <span className="pointer-events-none absolute bottom-2 right-3 text-[10px] tracking-wide text-white/25">
        {stage.view === 'menu' ? 'menu · ~2m' : stage.view === 'indicator' ? 'world marker' : 'sweep cursor'}
      </span>
    </div>
  )
}

/** Renders fixed-size world/cursor canvas preview scaled for visibility. */
function Centred({ size, children }: { size: number; children: React.ReactNode }) {
  const blowUp = 256 / size

  return (
    <div
      style={{
        position: 'absolute',
        left: 512 - size / 2,
        top: 512 - size / 2,
        width: size,
        height: size,
        transform: `scale(${blowUp * 1.6})`,
        transformOrigin: 'center center',
      }}
    >
      {children}
    </div>
  )
}

/** Executes opening-to-open state transition upon token update. */
function useReplay(token: number): 'opening' | 'open' {
  const [phase, setPhase] = useState<'opening' | 'open'>('open')
  const first = useRef(true)

  useEffect(() => {
    if (first.current) {
      first.current = false
      return
    }
    setPhase('opening')
    const raf = requestAnimationFrame(() => setPhase('open'))
    return () => cancelAnimationFrame(raf)
  }, [token])

  return phase
}

/** Renders background grid overlay for preview canvas. */
function GameGrid() {
  return (
    <div
      className="pointer-events-none absolute inset-0"
      style={{
        backgroundImage:
          'linear-gradient(to right, rgba(255,255,255,0.022) 1px, transparent 1px),' +
          'linear-gradient(to bottom, rgba(255,255,255,0.022) 1px, transparent 1px)',
        backgroundSize: '32px 32px',
      }}
    />
  )
}
