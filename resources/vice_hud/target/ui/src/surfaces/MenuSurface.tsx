import { useEffect, useState } from 'react'
import { useNuiEvent } from '../lib/useNuiEvent'
import { useAppearance } from '../lib/appearance'
import { useDesignModule } from '../designs'
import type { InputPrompts, MenuFocusPayload, MenuMode, MenuOpenPayload, TargetOption } from '../lib/types'

type Phase = 'idle' | 'opening' | 'open' | 'closing'

export function MenuSurface() {
  const appearance = useAppearance()
  const design = useDesignModule(appearance.design, appearance.version)

  const [options, setOptions] = useState<TargetOption[]>([])
  const [focus, setFocus] = useState(1)
  const [emptyLabel, setEmptyLabel] = useState('Nothing to do here')
  const [phase, setPhase] = useState<Phase>('idle')
  const [rejectToken, setRejectToken] = useState(0)
  const [input, setInput] = useState<InputPrompts | undefined>(undefined)
  const [mode, setMode] = useState<MenuMode>('list')
  const [collapseLabel, setCollapseLabel] = useState('')

  useNuiEvent<MenuOpenPayload>('menu:open', (data) => {
    setOptions(data.options ?? [])
    setFocus(data.focus ?? 1)
    if (data.emptyLabel) setEmptyLabel(data.emptyLabel)
    setMode(data.mode ?? 'list')
    setCollapseLabel(data.collapseLabel ?? '')
    setPhase((current) => (current === 'open' ? 'open' : 'opening'))
  })

  useNuiEvent<MenuFocusPayload>('menu:focus', (data) => setFocus(data.focus ?? 1))
  useNuiEvent('menu:reject', () => setRejectToken((n) => n + 1))
  useNuiEvent<InputPrompts>('input', (data) => setInput(data))
  useNuiEvent('menu:close', () => setPhase((current) => (current === 'idle' ? 'idle' : 'closing')))

  // Transition opening phase: advance to open state on next animation frame for smooth entrance.
  useEffect(() => {
    if (phase !== 'opening') return
    const raf = requestAnimationFrame(() => setPhase('open'))
    return () => cancelAnimationFrame(raf)
  }, [phase])

  // Delay state cleanup: wait for closing transition to complete before clearing options.
  useEffect(() => {
    if (phase !== 'closing') return
    const timer = window.setTimeout(() => {
      setPhase('idle')
      setOptions([])
    }, appearance.closeMs + 40)
    return () => window.clearTimeout(timer)
  }, [phase, appearance.closeMs])

  if (!design || phase === 'idle') return <div className="world world--biased" />

  const Menu = design.Menu

  return (
    <div className="world world--biased">
      <Menu
        options={options}
        focus={focus}
        rejectToken={rejectToken}
        phase={phase === 'open' ? 'open' : phase === 'closing' ? 'closing' : 'opening'}
        emptyLabel={emptyLabel}
        input={input}
        mode={mode}
        collapseLabel={collapseLabel}
        tunables={appearance.tunables}
        reducedMotion={appearance.reducedMotion}
        openMs={appearance.openMs}
        closeMs={appearance.closeMs}
      />
    </div>
  )
}
