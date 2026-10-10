import type { ReactNode } from 'react'
import { useEffect, useState } from 'react'
import { MOCK_DESIGNS, MOCK_PREFS, defaultsFor, mockConfig } from './mockData'
import { anchorFor } from '../lib/appearance'
import type { AdminOpenPayload, Preferences, TargetOption } from '../lib/types'

// Mock sample target options for local browser development and preview testing.
const SAMPLE: TargetOption[] = [
  { id: 1, label: 'Open trunk', icon: 'trunk', enabled: true, focusable: true, submenu: false },
  { id: 2, label: 'Search vehicle', icon: 'search', description: 'Takes about 8 seconds', enabled: true, focusable: true, submenu: false },
  { id: 3, label: 'Change Vehicle Tyres', icon: 'wheel', enabled: true, focusable: true, submenu: true },
  { id: 4, label: 'Hotwire', icon: 'lockpick', enabled: false, reason: 'Requires Lockpick', focusable: true, submenu: false },
  { id: 5, label: 'Impound', icon: 'shield', enabled: false, reason: 'Police only', focusable: true, submenu: false },
  { id: 6, label: 'Register vehicle at the DMV office', icon: 'clipboard', enabled: true, focusable: true, submenu: false },
  { id: 7, label: 'Sell to chop shop for $12,400', icon: 'cash', enabled: false, reason: 'Requires Bolt Cutters x2', focusable: true, submenu: false },
]

interface Props {
  onAdmin: (payload: AdminOpenPayload) => void
  onPrefs: (prefs: Preferences) => void
}

export function DevPreviewBar({ onAdmin, onPrefs }: Props) {
  useEffect(() => {
    const demo = new URLSearchParams(location.search).get('demo')
    if (demo === 'admin') onAdmin({ config: mockConfig(), designs: MOCK_DESIGNS, prefs: MOCK_PREFS })
    if (demo === 'prefs') onPrefs({ ...MOCK_PREFS })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <Panel title="Dev preview" subtitle="npm run dev · not shown in-game">
      <Row label="Panels">
        <Btn onClick={() => onAdmin({ config: mockConfig(), designs: MOCK_DESIGNS, prefs: MOCK_PREFS })}>Admin</Btn>
        <Btn onClick={() => onPrefs({ ...MOCK_PREFS })}>Prefs</Btn>
      </Row>
      <Row label="Surfaces">
        <Link href="?surface=menu&design=rail">menu</Link>
        <Link href="?surface=indicator&state=near&design=rail">indicator</Link>
        <Link href="?surface=cursor&design=rail">cursor</Link>
      </Row>
    </Panel>
  )
}

export function DevWorldBar({ surface }: { surface: 'menu' | 'indicator' | 'cursor' }) {
  const [design, setDesign] = useState(new URLSearchParams(location.search).get('design') ?? 'rail')
  const [focus, setFocus] = useState(3)
  const [count, setCount] = useState(SAMPLE.length)

  const push = (action: string, data?: unknown) => window.postMessage({ action, data }, '*')

  const appearance = (id: string) => {
    const manifest = MOCK_DESIGNS.find((d) => d.id === id)
    const tunables = defaultsFor(id)
    push('appearance', {
      design: id,
      tunables,
      anchor: anchorFor(manifest, tunables),
      prefs: MOCK_PREFS,
      timings: { open: 220, close: 160 },
    })
  }

  const open = (nextFocus = focus, nextCount = count) => {
    push('menu:open', {
      options: SAMPLE.slice(0, nextCount),
      focus: Math.min(nextFocus, nextCount),
      empty: nextCount === 0,
      emptyLabel: 'Nothing to do here',
    })
  }

  // Seed surface data on load when demo query parameter is present.
  useEffect(() => {
    if (!new URLSearchParams(location.search).has('demo')) return
    appearance(design)
    if (surface === 'menu') {
      window.setTimeout(() => open(3, SAMPLE.length), 30)
    }
    if (surface === 'indicator') {
      window.setTimeout(() => push('indicator:activate', { duration: 220 }), 30)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return (
    <Panel title={`Dev · ${surface}`} subtitle="Push the same messages Lua sends">
      <Row label="Design">
        {MOCK_DESIGNS.map((d) => (
          <Btn
            key={d.id}
            active={design === d.id}
            onClick={() => { setDesign(d.id); appearance(d.id) }}
          >
            {d.id}
          </Btn>
        ))}
      </Row>

      {surface === 'menu' && (
        <>
          <Row label="Menu">
            <Btn onClick={() => open()}>open</Btn>
            <Btn onClick={() => push('menu:close')}>close</Btn>
            <Btn onClick={() => push('menu:reject')}>reject</Btn>
          </Row>
          <Row label="Focus">
            <Btn onClick={() => { const n = Math.max(1, focus - 1); setFocus(n); push('menu:focus', { focus: n }) }}>-</Btn>
            <span className="num text-[11px] text-white/60">{focus}</span>
            <Btn onClick={() => { const n = Math.min(count, focus + 1); setFocus(n); push('menu:focus', { focus: n }) }}>+</Btn>
          </Row>
          <Row label="Options">
            {[0, 2, 4, 7].map((n) => (
              <Btn key={n} active={count === n} onClick={() => { setCount(n); open(Math.min(focus, Math.max(1, n)), n) }}>{n}</Btn>
            ))}
          </Row>
        </>
      )}

      {surface === 'indicator' && (
        <>
          <Row label="State">
            <Link href={`?surface=indicator&state=idle&design=${design}`}>idle</Link>
            <Link href={`?surface=indicator&state=near&design=${design}`}>near</Link>
            <Link href={`?surface=indicator&state=active&design=${design}`}>active</Link>
          </Row>
          <Row label="Absorb">
            <Btn onClick={() => push('indicator:activate', { duration: 220 })}>play</Btn>
          </Row>
        </>
      )}

      <Row label="Back">
        <Link href="?">screen page</Link>
      </Row>
    </Panel>
  )
}

function Panel({ title, subtitle, children }: { title: string; subtitle: string; children: ReactNode }) {
  return (
    <div
      className="pointer-events-auto fixed bottom-4 right-4 z-[500] w-[300px] overflow-hidden rounded-xl"
      style={{ background: '#0d0d0e', border: '1px solid #2a2a2e' }}
    >
      <div className="border-b border-white/[0.06] px-3 py-2">
        <p className="text-[12px] font-semibold text-white">{title}</p>
        <p className="text-[10px] text-white/35">{subtitle}</p>
      </div>
      <div className="flex flex-col gap-2 p-3">{children}</div>
    </div>
  )
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-2">
      <span className="t-label shrink-0">{label}</span>
      <div className="flex flex-wrap items-center justify-end gap-1">{children}</div>
    </div>
  )
}

function Btn({ active, onClick, children }: { active?: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      onClick={onClick}
      className="h-6 cursor-pointer rounded-md border px-2 text-[11px] font-semibold transition-colors"
      style={active
        ? { background: 'var(--accent)', color: 'var(--accent-foreground)', borderColor: 'transparent' }
        : { background: 'rgba(255,255,255,0.04)', color: 'rgba(255,255,255,0.8)', borderColor: 'rgba(255,255,255,0.1)' }}
    >
      {children}
    </button>
  )
}

function Link({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a
      href={href}
      className="h-6 rounded-md border px-2 text-[11px] font-semibold leading-6 transition-colors"
      style={{ background: 'rgba(255,255,255,0.04)', color: 'rgba(255,255,255,0.8)', borderColor: 'rgba(255,255,255,0.1)' }}
    >
      {children}
    </a>
  )
}
