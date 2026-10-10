import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import {
  AlertTriangle, Ban, Check, ChevronDown, ChevronRight, ChevronUp, Download, Pause, Play,
  RotateCcw, RotateCw, SlidersHorizontal, Upload, Volume2, X,
} from 'lucide-react'
import { fetchNui } from '../lib/nui'
import { applyTunables } from '../lib/appearance'
import { playSfx, type PackName } from '../lib/sound'
import {
  Button, ColorField, Field, MiniButton, NumberSlider, SearchField, SectionTitle, Segmented, Select, TextField, Toggle,
} from '../components/primitives'
import {
  DesignPreview, INITIAL_STAGE, SAMPLE_LABELS, firstGated, sampleOptions,
  type SampleName, type StageState,
} from './DesignPreview'
import { PRESETS, activePreset, presetFor } from './presets'
import { SYSTEM_GROUPS } from './systemControls'
import type { AdminOpenPayload, ControlAffects, DesignControl, StoredConfig } from '../lib/types'

type Section = 'design' | 'system'
type Tier = 'basic' | 'all'

interface Props {
  payload: AdminOpenPayload
  onClose: () => void
}

export function AdminSurface({ payload, onClose }: Props) {
  // Clone config payload: CEF 91 compatibility requires JSON serialization.
  const [config, setConfig] = useState<StoredConfig>(() => JSON.parse(JSON.stringify(payload.config)) as StoredConfig)
  const [section, setSection] = useState<Section>('design')
  const [tier, setTier] = useState<Tier>('basic')
  const [query, setQuery] = useState('')
  const [dirty, setDirty] = useState(false)
  const [transfer, setTransfer] = useState<'none' | 'export' | 'import'>('none')
  const [importText, setImportText] = useState('')
  const [confirmReset, setConfirmReset] = useState(false)
  const [stage, setStage] = useState<StageState>(INITIAL_STAGE)

  // Synchronize incoming config: resets working draft when new payload is received.
  useEffect(() => {
    setConfig(JSON.parse(JSON.stringify(payload.config)) as StoredConfig)
    setDirty(false)
    setConfirmReset(false)
  }, [payload])

  const designs = payload.designs
  const active = designs.find((d) => d.id === config.design) ?? designs[0]
  const tunables = config.designs[config.design] ?? {}

  // Apply appearance tunables: updates active CSS variables for live preview.
  useEffect(() => {
    applyTunables(tunables, { ...payload.prefs, scale: 100 })
  }, [tunables, payload.prefs])

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void fetchNui('previewAppearance', { design: config.design, tunables })
    }, 160)
    return () => window.clearTimeout(timer)
  }, [config.design, tunables])

  const patchStage = useCallback((patch: Partial<StageState>) => {
    setStage((current) => ({ ...current, ...patch }))
  }, [])

  /** Updates stage view state to demonstrate the affected control category. */
  const demonstrate = useCallback((affects?: ControlAffects) => {
    if (!affects) return

    setStage((current) => {
      switch (affects) {
        case 'indicator':
          return { ...current, view: 'indicator', playToken: current.playToken + 1 }
        case 'cursor':
          return { ...current, view: 'cursor' }
        case 'motion':
          return { ...current, view: 'menu', auto: false, playToken: current.playToken + 1 }
        case 'locked': {
          // Select gated sample option: keeps focus on gated item during evaluation.
          const sample: SampleName = sampleOptions(current.sample).some((o) => !o.enabled) ? current.sample : 'gated'
          return { ...current, view: 'menu', auto: false, sample, focus: firstGated(sample) }
        }
        case 'sound':
          return current
        default:
          return { ...current, view: 'menu' }
      }
    })
  }, [])

  const audition = useCallback(() => {
    const pack = (tunables.soundPack as PackName) ?? 'signature'
    const volume = typeof tunables.soundVolume === 'number' ? tunables.soundVolume : 70
    playSfx('scroll', pack, volume, false)
    window.setTimeout(() => playSfx('confirm', pack, volume, false), 220)
    window.setTimeout(() => playSfx('reject', pack, volume, false), 620)
  }, [tunables])

  const setTunable = (key: string, value: string | number | boolean) => {
    setDirty(true)
    setConfig((current) => ({
      ...current,
      designs: {
        ...current.designs,
        [current.design]: { ...current.designs[current.design], [key]: value },
      },
    }))
  }

  const applyPreset = (values: Record<string, string | number | boolean>) => {
    setDirty(true)
    setStage((current) => ({ ...current, view: 'menu' }))
    setConfig((current) => ({
      ...current,
      designs: {
        ...current.designs,
        [current.design]: { ...current.designs[current.design], ...values },
      },
    }))
  }

  const setSystem = (key: string, value: string | number | boolean) => {
    setDirty(true)
    setConfig((current) => ({ ...current, system: { ...current.system, [key]: value } }))
  }

  const chooseDesign = (id: string) => {
    setDirty(true)
    setSection('design')
    setStage((current) => ({ ...current, view: 'menu', playToken: current.playToken + 1 }))
    setConfig((current) => ({ ...current, design: id }))
  }

  const save = () => {
    void fetchNui('saveConfig', config)
    setDirty(false)
  }

  const revert = () => {
    setConfirmReset(false)
    void fetchNui('revertDesign', { design: config.design })
    setDirty(false)
  }

  const close = () => {
    if (dirty) void fetchNui('cancelPreview')
    onClose()
  }

  const schema = active?.schema ?? []
  const groups = useMemo(() => groupControls(schema, tier, query), [schema, tier, query])
  const advancedCount = useMemo(() => schema.filter((c) => c.tier === 'advanced').length, [schema])
  // Filter schema keys: scopes active preset detection to declared design controls.
  const schemaKeys = useMemo(() => new Set(schema.map((c) => c.key)), [schema])
  const preset = useMemo(() => activePreset(tunables, schemaKeys), [tunables, schemaKeys])

  return (
    <div className="pointer-events-auto absolute inset-0 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.72)' }}>
      <div
        className="animate-scale-in flex overflow-hidden rounded-xl border border-white/[0.08]"
        style={{
          width: 'min(1240px, 95vw)',
          height: 'min(760px, 92vh)',
          background: '#0b0b0c',
          boxShadow: 'var(--shadow-float)',
        }}
      >
        {/* Navigation rail: design selector and settings categories */}
        <aside className="flex w-[248px] shrink-0 flex-col border-r border-white/[0.06]">
          <header className="px-4 pb-3 pt-5">
            <div className="t-title">Interaction</div>
            <p className="mt-1 text-[11px] leading-relaxed text-white/55">
              Server-wide. Saving applies to everyone online.
            </p>
          </header>

          <div className="min-h-0 flex-1 overflow-y-auto px-3 pb-2">
            <RailLabel>Design</RailLabel>

            <nav className="flex flex-col gap-1.5">
              {designs.length === 0 && (
                <p className="px-2 py-3 text-[11px] leading-relaxed text-white/40">
                  No designs are installed. Put a design pack folder in
                  <span className="text-white/60"> osm-target/designs/ </span>
                  and restart the resource.
                </p>
              )}
              {designs.map((design) => (
                <RailCard
                  key={design.id}
                  selected={design.id === config.design && section === 'design'}
                  applied={design.id === config.design}
                  exclusive={design.exclusive === true}
                  accent={design.accent}
                  title={design.tagline}
                  onClick={() => chooseDesign(design.id)}
                >
                  <span className="truncate">{design.label}</span>
                  {design.exclusive === true && <ExclusiveChip />}
                </RailCard>
              ))}
            </nav>

            <RailLabel>Settings</RailLabel>

            <RailCard
              selected={section === 'system'}
              icon={<SlidersHorizontal size={13} className="shrink-0 opacity-70" />}
              chevron
              title="Distances, thresholds and option policy. Shared by every design."
              onClick={() => setSection('system')}
            >
              <span className="truncate">System &amp; behaviour</span>
            </RailCard>
          </div>

          <div className="flex gap-2 border-t border-white/[0.06] p-3">
            <Button variant="ghost" className="flex-1" icon={<Download size={13} />} onClick={() => setTransfer('export')}>Export</Button>
            <Button variant="ghost" className="flex-1" icon={<Upload size={13} />} onClick={() => setTransfer('import')}>Import</Button>
          </div>
        </aside>

        {/* ── pane ───────────────────────────────────────────────────────── */}
        <main className="flex min-w-0 flex-1 flex-col">
          <header className="flex items-center gap-3 border-b border-white/[0.06] px-6 py-3.5">
            <div className="min-w-0">
              <div className="t-title truncate">
                {section === 'design' ? active?.label : 'System & behaviour'}
              </div>
              {/* Active design summary */}
              <div className="mt-0.5 truncate text-[11px] text-white/55">
                {section === 'design'
                  ? (active?.tagline ?? 'Palette, surface, type, motion and sound for this design.')
                  : 'Distances, thresholds and option policy. Applies to every design.'}
              </div>
            </div>

            <div className="ml-auto flex items-center gap-2">
              {section === 'design' && (
                <Button variant="ghost" icon={<RotateCcw size={13} />} onClick={() => setConfirmReset(true)}>Reset design</Button>
              )}
              <Button variant={dirty ? 'primary' : 'secondary'} onClick={save} disabled={!dirty}>
                {dirty ? 'Save changes' : 'Saved'}
              </Button>
              <Button variant="ghost" icon={<X size={14} />} onClick={close} aria-label="Close" />
            </div>
          </header>

          <div className="flex min-h-0 flex-1">
            <div className="flex min-w-0 flex-1 flex-col">
              {section === 'design' && (
                <div className="flex items-center gap-3 border-b border-white/[0.05] px-6 py-2.5">
                  <Segmented
                    value={tier}
                    options={[{ value: 'basic' as Tier, label: 'Essentials' }, { value: 'all' as Tier, label: `All controls` }]}
                    onChange={setTier}
                  />
                  <SearchField value={query} onChange={setQuery} placeholder="Search controls…" />
                  {tier === 'basic' && query.length === 0 && (
                    <span className="shrink-0 text-[10px] text-white/50">+{advancedCount} advanced</span>
                  )}
                </div>
              )}

              <div className="min-w-0 flex-1 overflow-y-auto px-6 py-5">
                {section === 'design' ? (
                  <>
                    {query.length === 0 && (
                      <PresetRow active={preset} keys={schemaKeys} onApply={applyPreset} />
                    )}

                    {groups.length === 0 && (
                      <p className="pt-6 text-[12px] text-white/55">
                        Nothing matches “{query}”. {tier === 'basic' && 'Try All controls.'}
                      </p>
                    )}

                    {groups.map(([group, controls]) => (
                      <section key={group} className="mb-7">
                        <SectionTitle>{group}</SectionTitle>
                        <div className="divide-y divide-white/[0.04]">
                          {controls.map((control) => (
                            <DesignField
                              key={control.key}
                              control={control}
                              value={tunables[control.key]}
                              shipped={active?.defaults?.[control.key] ?? control.default}
                              onChange={(value) => {
                                setTunable(control.key, value)
                                demonstrate(control.affects)
                              }}
                              onEngage={() => demonstrate(control.affects)}
                              onReset={() => {
                                setTunable(control.key, active?.defaults?.[control.key] ?? control.default)
                                demonstrate(control.affects)
                              }}
                            />
                          ))}
                        </div>
                      </section>
                    ))}
                  </>
                ) : (
                  SYSTEM_GROUPS.map((group) => (
                    <section key={group.title} className="mb-7">
                      <SectionTitle>{group.title}</SectionTitle>
                      {group.blurb && (
                        <p className="mb-1 max-w-[68ch] pt-2 text-[11px] leading-relaxed text-white/55">{group.blurb}</p>
                      )}
                      <div className="divide-y divide-white/[0.04]">
                        {group.controls.map((control) => (
                          <Field key={control.key} label={control.label} help={control.help}>
                            {control.type === 'boolean' ? (
                              <Toggle
                                checked={Boolean(config.system[control.key])}
                                onChange={(v) => setSystem(control.key, v)}
                              />
                            ) : control.type === 'select' ? (
                              shouldUseSelect(control) ? (
                                <Select
                                  value={String(config.system[control.key] ?? control.options?.[0]?.value ?? '')}
                                  options={control.options ?? []}
                                  onChange={(v) => setSystem(control.key, v)}
                                />
                              ) : (
                                <Segmented
                                  value={String(config.system[control.key] ?? control.options?.[0]?.value ?? '')}
                                  options={control.options ?? []}
                                  onChange={(v) => setSystem(control.key, v)}
                                />
                              )
                            ) : control.type === 'text' ? (
                              <TextField
                                value={String(config.system[control.key] ?? '')}
                                onChange={(v) => setSystem(control.key, v)}
                              />
                            ) : (
                              <NumberSlider
                                value={Number(config.system[control.key] ?? control.min ?? 0)}
                                min={control.min ?? 0}
                                max={control.max ?? 1}
                                step={control.step ?? 1}
                                unit={control.unit}
                                onChange={(v) => setSystem(control.key, v)}
                              />
                            )}
                          </Field>
                        ))}
                      </div>
                    </section>
                  ))
                )}
              </div>
            </div>

            <div className="w-[440px] shrink-0 overflow-y-auto border-l border-white/[0.06] p-5">
              <DesignPreview
                designId={config.design}
                tunables={tunables}
                manifest={active}
                stage={stage}
                onStage={patchStage}
                width={400}
                height={400}
              />
              <StageControls stage={stage} onStage={patchStage} onAudition={audition} />
            </div>
          </div>
        </main>
      </div>

      {confirmReset && (
        <ConfirmDialog
          title="Reset this design?"
          body={
            <>
              Every control for <strong className="font-semibold text-white/80">{active?.label}</strong> goes
              back to its shipped defaults, and the change is saved and pushed to everyone online
              immediately. Other designs and the system settings are untouched.
            </>
          }
          confirmLabel="Reset to defaults"
          onConfirm={revert}
          onClose={() => setConfirmReset(false)}
        />
      )}

      {transfer !== 'none' && (
        <TransferDialog
          mode={transfer}
          config={config}
          value={importText}
          onChange={setImportText}
          onImport={() => {
            void fetchNui('importConfig', { blob: importText })
            setTransfer('none')
          }}
          onClose={() => setTransfer('none')}
        />
      )}
    </div>
  )
}

function RailLabel({ children }: { children: ReactNode }) {
  return <div className="t-label px-1 pb-2 pt-4 first:pt-1">{children}</div>
}

/** Navigation card component for design and section selection. */
function RailCard({
  children, onClick, selected, applied, exclusive, accent, icon, chevron, title,
}: {
  children: ReactNode
  onClick: () => void
  selected: boolean
  /** Indicates currently active server design. */
  applied?: boolean
  exclusive?: boolean
  accent?: string
  icon?: ReactNode
  chevron?: boolean
  title?: string
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={title}
      className={`group relative flex h-[34px] w-full cursor-pointer items-center gap-2 overflow-hidden rounded-lg border pl-2.5 pr-2 text-left text-[12px] font-semibold transition-colors duration-150 ${
        exclusive ? 'osm-exclusive' : ''
      } ${selected ? 'text-white' : 'text-white/65 hover:text-white/90'}`}
      style={{
        background: selected ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.018)',
        borderColor: selected ? 'rgba(255,255,255,0.20)' : 'rgba(255,255,255,0.07)',
      }}
    >
      {/* Active indicator accent spine */}
      <span
        className="absolute inset-y-0 left-0 w-[2px] transition-opacity duration-150"
        style={{ background: 'var(--accent)', opacity: selected ? 1 : 0 }}
      />

      {accent && <span className="relative h-2 w-2 shrink-0 rounded-full" style={{ background: accent }} />}
      {icon}

      <span className="relative flex min-w-0 flex-1 items-center gap-2">{children}</span>

      {applied && <Check size={12} className="relative shrink-0" style={{ color: 'var(--accent)' }} />}
      {chevron && <ChevronRight size={13} className="relative shrink-0 opacity-40" />}
    </button>
  )
}

function ExclusiveChip() {
  return (
    <span
      className="relative shrink-0 rounded-[4px] px-1.5 py-[1px] text-[8.5px] font-bold uppercase leading-[1.4] tracking-[0.14em]"
      style={{ background: 'linear-gradient(100deg, #f4e2b8 0%, #ffffff 40%, #d8c48f 100%)', color: '#2a2113' }}
    >
      Exclusive
    </span>
  )
}

/** Renders quick-select theme preset buttons. */
function PresetRow({ active, keys, onApply }: {
  active: string | null
  /** Controls declared by current design schema. */
  keys: Set<string>
  onApply: (values: Record<string, string | number | boolean>) => void
}) {
  return (
    <section className="mb-7">
      <SectionTitle meta={<span className="text-[10px] text-white/50">A starting point — every value stays editable</span>}>
        Looks
      </SectionTitle>

      <div className="flex flex-wrap gap-2 pt-3">
        {PRESETS.map((preset) => {
          const on = preset.id === active
          return (
            <button
              key={preset.id}
              type="button"
              onClick={() => onApply(presetFor(preset, keys))}
              title={preset.blurb}
              className="flex cursor-pointer items-center gap-2 rounded-lg border px-2.5 py-2 transition-colors duration-150"
              style={{
                borderColor: on ? 'var(--accent)' : 'rgba(255,255,255,0.08)',
                background: on ? 'var(--accent-muted)' : 'rgba(255,255,255,0.02)',
              }}
            >
              <span className="flex shrink-0 overflow-hidden rounded-md border border-white/10">
                <span className="block h-5 w-3" style={{ background: String(preset.values.surface) }} />
                <span className="block h-5 w-3" style={{ background: String(preset.values.accent) }} />
                <span className="block h-5 w-3" style={{ background: String(preset.values.text) }} />
              </span>
              <span className={`text-[11px] font-semibold ${on ? 'text-white' : 'text-white/75'}`}>{preset.label}</span>
            </button>
          )
        })}
      </div>
    </section>
  )
}

/** Preview viewport and playback controls toolbar. */
function StageControls({
  stage, onStage, onAudition,
}: { stage: StageState; onStage: (patch: Partial<StageState>) => void; onAudition: () => void }) {
  const count = sampleOptions(stage.sample).length

  return (
    <div className="mt-3 rounded-xl border border-white/[0.06] bg-white/[0.015] p-3">
      <div className="flex flex-col gap-2">
        <StageRow label="Showing">
          <Segmented
            size="sm"
            accent
            value={stage.view}
            options={[
              { value: 'menu' as const, label: 'Menu' },
              { value: 'indicator' as const, label: 'Marker' },
              { value: 'cursor' as const, label: 'Cursor' },
            ]}
            onChange={(view) => onStage({ view })}
          />
        </StageRow>

        {stage.view === 'menu' && (
          <>
            <StageRow label="Options">
              <Segmented
                size="sm"
                value={stage.sample}
                options={SAMPLE_LABELS}
                onChange={(sample) => onStage({ sample, focus: 1, auto: false })}
              />
            </StageRow>

            <StageRow label="Play">
              <MiniButton onClick={() => onStage({ auto: false, focus: 1, playToken: Date.now() })} title="Replay the open animation">
                <Play size={10} fill="currentColor" /> Open
              </MiniButton>
              <MiniButton
                square
                onClick={() => onStage({ auto: false, focus: Math.max(1, stage.focus - 1) })}
                title="Focus the previous option"
              >
                <ChevronUp size={13} />
              </MiniButton>
              <MiniButton
                square
                onClick={() => onStage({ auto: false, focus: Math.min(Math.max(1, count), stage.focus + 1) })}
                title="Focus the next option"
              >
                <ChevronDown size={13} />
              </MiniButton>
              <MiniButton onClick={() => onStage({ rejectToken: Date.now() })} title="Confirm a gated option and be refused">
                <Ban size={11} /> Refuse
              </MiniButton>
              <MiniButton
                active={stage.auto}
                onClick={() => onStage({ auto: !stage.auto })}
                title="Cycle the focus automatically"
              >
                {stage.auto ? <Pause size={10} fill="currentColor" /> : <RotateCw size={11} />} Auto
              </MiniButton>
            </StageRow>
          </>
        )}

        {stage.view === 'indicator' && (
          <StageRow label="State">
            <Segmented
              size="sm"
              value={stage.indicator}
              options={[
                { value: 'idle' as const, label: 'Idle' },
                { value: 'near' as const, label: 'Near' },
                { value: 'active' as const, label: 'Locked on' },
              ]}
              onChange={(indicator) => onStage({ indicator, playToken: Date.now() })}
            />
            <MiniButton onClick={() => onStage({ indicator: 'active', playToken: Date.now() })} title="Replay the lock-on">
              <Play size={10} fill="currentColor" /> Replay
            </MiniButton>
          </StageRow>
        )}

        <StageRow label="Sound">
          <MiniButton onClick={onAudition} title="Play scroll, confirm and refuse from the selected pack">
            <Volume2 size={11} /> Audition pack
          </MiniButton>
        </StageRow>
      </div>

      <p className="mt-3 border-t border-white/[0.05] pt-2.5 text-[11px] leading-relaxed text-white/55">
        Drawn at roughly the size a player sees at two metres. Changing a control moves this
        preview to the state that shows it.
      </p>
    </div>
  )
}

function StageRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex min-h-[26px] items-center gap-2.5">
      <span className="t-label w-[46px] shrink-0">{label}</span>
      <div className="flex flex-wrap items-center gap-1.5">{children}</div>
    </div>
  )
}

/** Groups design controls and filters by search query and tier. */
function groupControls(schema: DesignControl[], tier: Tier, query: string): [string, DesignControl[]][] {
  const needle = query.trim().toLowerCase()

  const visible = schema.filter((control) => {
    if (needle.length > 0) {
      return (
        control.label.toLowerCase().includes(needle) ||
        control.group.toLowerCase().includes(needle) ||
        (control.help ?? '').toLowerCase().includes(needle)
      )
    }
    return tier === 'all' || control.tier !== 'advanced'
  })

  const order: string[] = []
  const map = new Map<string, DesignControl[]>()

  for (const control of visible) {
    if (!map.has(control.group)) {
      map.set(control.group, [])
      order.push(control.group)
    }
    map.get(control.group)!.push(control)
  }

  return order.map((group) => [group, map.get(group)!])
}

function shouldUseSelect(control: { widget?: 'select' | 'segmented'; options?: { value: string; label: string }[] }): boolean {
  if (control.widget === 'select') return true
  if (control.widget === 'segmented') return false
  const opts = control.options ?? []
  if (opts.length > 3) return true
  const totalLength = opts.reduce((sum, opt) => sum + opt.label.length, 0)
  return totalLength > 24
}

function DesignField({
  control, value, shipped, onChange, onEngage, onReset,
}: {
  control: DesignControl
  value: unknown
  shipped: string | number | boolean
  onChange: (v: string | number | boolean) => void
  onEngage: () => void
  onReset: () => void
}) {
  const current = value ?? shipped
  const modified = current !== shipped

  return (
    <Field
      label={control.label}
      help={control.help}
      modified={modified}
      onReset={onReset}
      onEngage={onEngage}
    >
      {control.type === 'color' && (
        <ColorField value={String(current)} onChange={onChange} />
      )}
      {control.type === 'boolean' && (
        <Toggle checked={Boolean(current)} onChange={onChange} />
      )}
      {control.type === 'select' && (
        shouldUseSelect(control) ? (
          <Select
            value={String(current)}
            options={control.options ?? []}
            onChange={onChange}
          />
        ) : (
          <Segmented
            value={String(current)}
            options={control.options ?? []}
            onChange={onChange}
          />
        )
      )}
      {control.type === 'number' && (
        <NumberSlider
          value={Number(current)}
          min={control.min ?? 0}
          max={control.max ?? 100}
          step={control.step ?? 1}
          unit={control.unit}
          onChange={onChange}
        />
      )}
    </Field>
  )
}

/** Confirmation modal for irreversible operations. */
function ConfirmDialog({
  title, body, confirmLabel, onConfirm, onClose,
}: {
  title: string
  body: ReactNode
  confirmLabel: string
  onConfirm: () => void
  onClose: () => void
}) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
      if (event.key === 'Enter') onConfirm()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose, onConfirm])

  return (
    <div className="absolute inset-0 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.7)' }}>
      <div
        className="animate-scale-in w-[420px] overflow-hidden rounded-xl border border-white/[0.08]"
        style={{ background: '#0d0d0e', boxShadow: 'var(--shadow-float)' }}
      >
        <div className="flex gap-3.5 p-5">
          <span
            className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg"
            style={{ background: 'rgba(239,68,68,0.10)', color: '#ff8b8b' }}
          >
            <AlertTriangle size={15} />
          </span>
          <div className="min-w-0">
            <div className="t-title">{title}</div>
            <p className="mt-1.5 text-[11px] leading-relaxed text-white/60">{body}</p>
          </div>
        </div>

        <div className="flex justify-end gap-2 border-t border-white/[0.06] px-5 py-3.5">
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          <Button variant="danger" onClick={onConfirm}>{confirmLabel}</Button>
        </div>
      </div>
    </div>
  )
}

function TransferDialog({
  mode, config, value, onChange, onImport, onClose,
}: {
  mode: 'export' | 'import'
  config: StoredConfig
  value: string
  onChange: (v: string) => void
  onImport: () => void
  onClose: () => void
}) {
  const blob = useMemo(() => JSON.stringify(config, null, 2), [config])

  return (
    <div className="absolute inset-0 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.7)' }}>
      <div
        className="animate-scale-in w-[560px] overflow-hidden rounded-xl border border-white/[0.08]"
        style={{ background: '#0d0d0e', boxShadow: 'var(--shadow-float)' }}
      >
        <div className="flex items-center justify-between border-b border-white/[0.06] px-5 py-3.5">
          <span className="t-title">{mode === 'export' ? 'Export configuration' : 'Import configuration'}</span>
          <Button variant="ghost" icon={<X size={14} />} onClick={onClose} aria-label="Close" />
        </div>

        <div className="p-5">
          <textarea
            readOnly={mode === 'export'}
            value={mode === 'export' ? blob : value}
            onChange={(e) => onChange(e.target.value)}
            onFocus={(e) => mode === 'export' && e.currentTarget.select()}
            placeholder={mode === 'import' ? 'Paste a configuration here' : undefined}
            spellCheck={false}
            className="num h-[260px] w-full resize-none rounded-lg border border-white/[0.07] bg-black/40 p-3 text-[11px] leading-relaxed text-white/80 outline-none placeholder:text-white/40 focus:border-white/20"
          />

          <div className="mt-4 flex justify-end gap-2">
            <Button variant="ghost" onClick={onClose}>Close</Button>
            {mode === 'import' && (
              <Button variant="primary" onClick={onImport} disabled={value.trim().length === 0}>
                Import and apply
              </Button>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
