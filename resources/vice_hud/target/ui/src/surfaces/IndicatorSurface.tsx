import { useState } from 'react'
import { useNuiEvent } from '../lib/useNuiEvent'
import { useAppearance } from '../lib/appearance'
import { useDesignModule } from '../designs'
import { surfaceParams } from '../lib/nui'
import type { IndicatorState } from '../lib/types'

export function IndicatorSurface() {
  const { state } = surfaceParams()
  const appearance = useAppearance()
  const design = useDesignModule(appearance.design, appearance.version)
  const [activateToken, setActivateToken] = useState(0)

  useNuiEvent('indicator:activate', () => setActivateToken((n) => n + 1))
  useNuiEvent('indicator:reset', () => setActivateToken((n) => n + 1))

  if (!design) return <div className="world" />

  const Indicator = design.Indicator

  return (
    <Indicator
      state={state as IndicatorState}
      activateToken={activateToken}
      tunables={appearance.tunables}
      reducedMotion={appearance.reducedMotion}
      openMs={appearance.openMs}
      closeMs={appearance.closeMs}
    />
  )
}
