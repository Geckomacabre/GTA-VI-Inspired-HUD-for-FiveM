import { useEffect, useState } from 'react'
import { closeNui, isEnvBrowser, surfaceParams } from './lib/nui'
import { useNuiEvent } from './lib/useNuiEvent'
import { useAppearance } from './lib/appearance'
import { playSfx, type PackName, type SfxName } from './lib/sound'
import { MenuSurface } from './surfaces/MenuSurface'
import { IndicatorSurface } from './surfaces/IndicatorSurface'
import { CursorSurface } from './surfaces/CursorSurface'
import { AdminSurface } from './surfaces/AdminSurface'
import { PrefsPanel } from './surfaces/PrefsPanel'
import { DevPreviewBar, DevWorldBar } from './dev/DevPreviewBar'
import type { AdminOpenPayload, Preferences } from './lib/types'

export default function App() {
  const { surface } = surfaceParams()

  useEffect(() => {
    if (!isEnvBrowser) return

    // index.html sets `background: transparent !important` inline so the page
    // never flashes opaque over the game; that outranks any stylesheet, so the
    // dev canvas has to be set inline too.
    document.documentElement.setAttribute('data-dev-mode', 'true')
    for (const element of [document.documentElement, document.body, document.getElementById('root')]) {
      element?.style.setProperty('background', '#0a0a0b', 'important')
    }
  }, [])

  if (surface !== 'app') {
    return (
      <>
        {surface === 'menu' && (
          isEnvBrowser ? (
            <div className="flex h-screen w-screen items-center justify-center">
              <div className="relative border border-white/10 shadow-2xl" style={{ width: 1024, height: 1024 }}>
                <MenuSurface />
              </div>
            </div>
          ) : (
            <MenuSurface />
          )
        )}
        {surface === 'indicator' && (
          isEnvBrowser ? (
            <div className="flex h-screen w-screen items-center justify-center">
              <div className="relative border border-white/10 shadow-2xl" style={{ width: 256, height: 256 }}>
                <IndicatorSurface />
              </div>
            </div>
          ) : (
            <IndicatorSurface />
          )
        )}
        {surface === 'cursor' && (
          isEnvBrowser ? (
            <div className="flex h-screen w-screen items-center justify-center">
              <div className="relative border border-white/10 shadow-2xl" style={{ width: 128, height: 128 }}>
                <CursorSurface />
              </div>
            </div>
          ) : (
            <CursorSurface />
          )
        )}
        {isEnvBrowser && <DevWorldBar surface={surface} />}
      </>
    )
  }

  return <ScreenSurface />
}

/** Passive except while a panel is open; its standing job is the sound bus,
 *  because a DUI surface has no audio output. */
function ScreenSurface() {
  const appearance = useAppearance()
  const [admin, setAdmin] = useState<AdminOpenPayload | null>(null)
  const [prefs, setPrefs] = useState<Preferences | null>(null)

  useNuiEvent<AdminOpenPayload>('admin:open', (data) => setAdmin(data))
  useNuiEvent('admin:close', () => setAdmin(null))
  useNuiEvent<{ prefs: Preferences }>('prefs:open', (data) => setPrefs(data.prefs))
  useNuiEvent('prefs:close', () => setPrefs(null))

  useNuiEvent<{ name: SfxName }>('sfx', (data) => {
    const pack = (appearance.tunables.soundPack as PackName) ?? 'signature'
    const designVolume = typeof appearance.tunables.soundVolume === 'number'
      ? appearance.tunables.soundVolume
      : 100
    // The owner's pack volume and the player's own volume multiply: a server can
    // set its overall level, a player can still turn it down.
    const volume = (designVolume / 100) * appearance.prefs.volume
    playSfx(data.name, pack, volume, appearance.prefs.muted)
  })

  const interactive = admin !== null || prefs !== null

  return (
    <div className={`relative h-screen w-screen select-none overflow-hidden ${interactive ? 'pointer-events-auto' : 'pointer-events-none'}`}>
      {admin && <AdminSurface payload={admin} onClose={() => { setAdmin(null); void closeNui() }} />}
      {prefs && <PrefsPanel initial={prefs} onClose={() => { setPrefs(null); void closeNui() }} />}
      {isEnvBrowser && <DevPreviewBar onAdmin={setAdmin} onPrefs={setPrefs} />}
    </div>
  )
}
