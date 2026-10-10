import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { ChevronDown } from 'lucide-react'

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger'

const VARIANT: Record<Variant, string> = {
  primary: 'border-transparent',
  secondary: 'text-white/85 bg-white/[0.04] border-white/10 hover:border-white/20 hover:bg-white/[0.06]',
  ghost: 'text-white/70 border-transparent hover:text-white hover:bg-white/[0.05]',
  danger: 'text-[#ff8b8b] bg-[rgba(239,68,68,0.10)] border-[rgba(239,68,68,0.22)] hover:bg-[rgba(239,68,68,0.16)]',
}

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant
  icon?: ReactNode
}

export function Button({ variant = 'secondary', icon, children, className = '', style, ...rest }: ButtonProps) {
  return (
    <button
      {...rest}
      style={variant === 'primary' ? { background: 'var(--accent)', color: 'var(--accent-foreground)', ...style } : style}
      className={`inline-flex h-8 items-center justify-center gap-1.5 rounded-lg border px-3 text-[11px] font-semibold transition-all duration-150 disabled:cursor-not-allowed disabled:opacity-40 cursor-pointer ${VARIANT[variant]} ${className}`}
    >
      {icon}
      {children}
    </button>
  )
}

interface FieldProps {
  label: string
  help?: string
  children: ReactNode
  /** True when the value differs from what the design shipped with. */
  modified?: boolean
  onReset?: () => void
  /** Called when the owner starts interacting, so the preview can move to the
   *  state where this control's effect is visible. */
  onEngage?: () => void
}

/** One control, with a sentence saying what it does and a mark when it has been
 *  moved off the shipped value. */
export function Field({ label, help, children, modified, onReset, onEngage }: FieldProps) {
  return (
    <div
      className="group grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-1 py-2.5"
      onPointerDownCapture={onEngage}
      onFocusCapture={onEngage}
    >
      <div className="min-w-0">
        <div className="flex items-center gap-1.5">
          <span className="text-[12px] font-medium text-white/85">{label}</span>
          {modified && (
            <button
              type="button"
              onClick={onReset}
              title="Changed from the shipped default — click to restore"
              className="flex h-3.5 w-3.5 shrink-0 cursor-pointer items-center justify-center rounded-full"
              style={{ background: 'var(--accent)' }}
            >
              <span className="block h-1.5 w-1.5 rounded-full bg-black/45" />
            </button>
          )}
        </div>
        {/* Help text is the thing most owners actually read; at white/35 on a
            near-black panel it sat around 3:1 and vanished at a glance. white/60
            clears 4.5:1 and still reads quieter than the label above it. */}
        {help && <div className="mt-1 max-w-[46ch] text-[11px] leading-relaxed text-white/60">{help}</div>}
      </div>
      <div className="flex min-w-[188px] justify-end">{children}</div>
    </div>
  )
}

export function SearchField({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder?: string }) {
  return (
    <div className="relative flex-1">
      <input
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        spellCheck={false}
        className="h-7 w-full rounded-lg border border-white/8 bg-white/[0.02] pl-7 pr-2 text-[11px] text-white outline-none transition-colors placeholder:text-white/45 hover:border-white/15 focus:border-white/25"
      />
      <svg
        viewBox="0 0 24 24" width="12" height="12"
        className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-white/30"
      >
        <circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" strokeWidth="2" />
        <path d="M 16.5 16.5 L 21 21" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      </svg>
    </div>
  )
}

export function NumberSlider({
  value, min, max, step, unit, onChange,
}: { value: number; min: number; max: number; step: number; unit?: string; onChange: (v: number) => void }) {
  const pct = max > min ? ((value - min) / (max - min)) * 100 : 0

  return (
    <div className="flex w-full items-center gap-3">
      <input
        type="range"
        className="osm-range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        style={{
          background: `linear-gradient(to right, var(--accent) 0%, var(--accent) ${pct}%, rgba(255,255,255,0.07) ${pct}%, rgba(255,255,255,0.07) 100%)`,
        }}
      />
      <span className="num w-[52px] shrink-0 text-right text-[11px] font-semibold text-white/70">
        {Number.isInteger(step) ? value : value.toFixed(2)}
        {unit && <span className="ml-0.5 text-white/50">{unit}</span>}
      </span>
    </div>
  )
}

export function Toggle({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      type="button"
      onClick={() => onChange(!checked)}
      aria-pressed={checked}
      className={`flex h-5 w-9 shrink-0 cursor-pointer items-center rounded-full p-0.5 transition-all duration-150 ${checked ? 'justify-end' : 'justify-start bg-white/10'}`}
      style={checked ? { background: 'var(--accent)' } : undefined}
    >
      <span className="h-4 w-4 rounded-full bg-white" />
    </button>
  )
}

export function Segmented<T extends string>({
  value, options, onChange, size = 'md', accent = false,
}: {
  value: T
  /** `title` becomes the segment's tooltip, for labels short enough to fit a
   *  narrow column but too short to explain themselves. */
  options: { value: T; label: string; title?: string }[]
  onChange: (v: T) => void
  size?: 'md' | 'sm'
  /** Marks the active segment with the accent rather than a neutral wash. Used
   *  where the segment IS the current mode rather than one setting among many. */
  accent?: boolean
}) {
  const small = size === 'sm'

  // `sm` resolves to a 26px outer height, the one height every control on the
  // preview stage is built to. Change MiniButton with it.
  return (
    <div className="flex items-center gap-0.5 rounded-lg border border-white/8 bg-white/[0.02] p-0.5">
      {options.map((option) => {
        const active = option.value === value
        return (
          <button
            key={option.value}
            type="button"
            title={option.title}
            onClick={() => onChange(option.value)}
            className={`cursor-pointer whitespace-nowrap rounded-md font-semibold transition-colors duration-150 ${small ? 'h-5 px-2.5 text-[10px]' : 'h-6 px-2.5 text-[11px]'} ${active ? 'text-white' : 'text-white/55 hover:text-white/85'}`}
            style={active
              ? accent
                ? { background: 'var(--accent)', color: 'var(--accent-foreground)' }
                : { background: 'rgba(255,255,255,0.08)' }
              : undefined}
          >
            {option.label}
          </button>
        )
      })}
    </div>
  )
}

/** A compact preview-stage action, built to the same 26px height as
 *  `Segmented size="sm"` because the footer mixes the two on every row.
 *  `square` is for the icon-only steppers. */
export function MiniButton({
  onClick, children, title, square = false, active = false,
}: {
  onClick: () => void
  children: ReactNode
  title?: string
  square?: boolean
  /** Latched state - e.g. the auto-cycle toggle is running. */
  active?: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      title={title}
      aria-pressed={active || undefined}
      style={active ? { background: 'var(--accent-muted)', borderColor: 'var(--accent)', color: '#fff' } : undefined}
      className={`flex h-[26px] cursor-pointer items-center justify-center gap-1.5 whitespace-nowrap rounded-lg border border-white/10 bg-white/[0.04] text-[10px] font-semibold text-white/75 transition-colors hover:border-white/20 hover:text-white ${square ? 'w-[26px]' : 'px-2.5'}`}
    >
      {children}
    </button>
  )
}

export function ColorField({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex items-center gap-2">
      <span className="num text-[11px] uppercase text-white/60">{value}</span>
      <span className="h-7 w-9 overflow-hidden rounded-md border border-white/12">
        <input className="osm-swatch" type="color" value={value} onChange={(e) => onChange(e.target.value)} />
      </span>
    </div>
  )
}

export function Select<T extends string>({
  value, options, onChange, className = '',
}: {
  value: T
  options: { value: T; label: string; title?: string }[]
  onChange: (v: T) => void
  className?: string
}) {
  return (
    <div className={`relative inline-flex items-center ${className}`}>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value as T)}
        className="h-8 w-[188px] cursor-pointer appearance-none rounded-lg border border-white/8 bg-white/[0.04] pl-3 pr-8 text-[11px] font-semibold text-white/85 outline-none transition-colors hover:border-white/15 hover:bg-white/[0.06] focus:border-white/25"
        style={{
          colorScheme: 'dark',
        }}
      >
        {options.map((option) => (
          <option key={option.value} value={option.value} title={option.title} className="bg-[#111113] text-white">
            {option.label}
          </option>
        ))}
      </select>
      <ChevronDown
        size={13}
        className="pointer-events-none absolute right-2.5 text-white/45"
      />
    </div>
  )
}

export function TextField({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder?: string }) {
  return (
    <input
      value={value}
      placeholder={placeholder}
      onChange={(e) => onChange(e.target.value)}
      className="h-8 w-[188px] rounded-lg border border-white/8 bg-white/[0.02] px-2.5 text-[11px] text-white outline-none transition-colors placeholder:text-white/20 hover:border-white/15 focus:border-white/25"
    />
  )
}

export function SectionTitle({ children, meta }: { children: ReactNode; meta?: ReactNode }) {
  return (
    <div className="mb-1 flex items-baseline justify-between border-b border-white/[0.06] pb-2">
      <h3 className="t-heading">{children}</h3>
      {meta}
    </div>
  )
}
