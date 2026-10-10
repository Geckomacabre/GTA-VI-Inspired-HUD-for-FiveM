import { useAppearance } from '../lib/appearance'
import { useDesignModule } from '../designs'

export function CursorSurface() {
  const appearance = useAppearance()
  const design = useDesignModule(appearance.design, appearance.version)

  if (!design) return <div className="world" />

  const Cursor = design.Cursor

  return (
    <Cursor
      tunables={appearance.tunables}
      reducedMotion={appearance.reducedMotion}
      openMs={appearance.openMs}
      closeMs={appearance.closeMs}
    />
  )
}
