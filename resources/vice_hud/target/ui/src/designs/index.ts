import { useEffect, useState } from 'react'
import { registerFonts } from '../lib/appearance'
import { RESOURCE_FALLBACK } from '../lib/nui'
import { registeredDesign, registeredDesignIds, whenRegistered } from '../host'
import type { DesignModule } from '../lib/types'

/**
 * Runtime design loader: manages dynamic bundle fetching, script injection, and registry caching.
 */

/** Maximum wait time for design bundle download and registration. */
const LOAD_TIMEOUT_MS = 6000

/** Per-candidate fetch timeout before attempting fallback URLs. */
const CANDIDATE_TIMEOUT_MS = 2500

const attempts = new Map<string, Promise<DesignModule | null>>()

/** Resolve candidate script URLs for design bundle loading with cache-busting. */
function bundleUrls(id: string, version?: string): string[] {
  const path = `designs/${id}/design.js`
  const query = version ? `?v=${encodeURIComponent(version)}` : ''
  const resource = window.GetParentResourceName ? window.GetParentResourceName() : RESOURCE_FALLBACK

  const candidates = [`https://cfx-nui-${resource}/${path}${query}`]

  try {
    candidates.unshift(new URL(`../${path}${query}`, window.location.href).href)
  } catch {
    candidates.unshift(`../${path}${query}`)
  }

  return candidates
}

/** Dynamically inject script tag and resolve on successful load or error. */
function injectScript(src: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const element = document.createElement('script')
    let settled = false

    const finish = (error?: Error) => {
      if (settled) return
      settled = true
      window.clearTimeout(timer)
      if (error) {
        element.remove()
        reject(error)
      } else {
        resolve()
      }
    }

    const timer = window.setTimeout(
      () => finish(new Error(`timed out fetching ${src}`)),
      CANDIDATE_TIMEOUT_MS,
    )

    element.src = src
    element.async = true
    element.onload = () => finish()
    element.onerror = () => finish(new Error(`could not fetch ${src}`))
    document.head.appendChild(element)
  })
}

/** Await registration with timeout fallback to prevent hanging. */
function awaitRegistration(id: string): Promise<DesignModule | null> {
  return Promise.race([
    whenRegistered(id),
    new Promise<null>((resolve) => window.setTimeout(() => resolve(null), LOAD_TIMEOUT_MS)),
  ])
}

async function fetchBundle(id: string, version?: string): Promise<void> {
  const candidates = bundleUrls(id, version)
  let last: unknown

  for (const url of candidates) {
    try {
      return await injectScript(url)
    } catch (error) {
      last = error
    }
  }

  throw last ?? new Error(`no bundle for design "${id}"`)
}

async function fetchDesign(id: string, version?: string): Promise<DesignModule | null> {
  let failure: unknown = null

  try {
    if (import.meta.env.DEV) {
      const dev = await import('./dev')
      await dev.loadFromSource(id)
    } else {
      await fetchBundle(id, version)
    }
  } catch (error) {
    failure = error
  }

  const module = await awaitRegistration(id)
  if (!module) {
    console.error(
      `[osm-target] design "${id}" did not load.`,
      failure ??
        'Its bundle was fetched but never called registerDesign - it is built ' +
          'against a different SDK, or is not an osm-target design pack.',
    )
    return null
  }

  // Register pack typography: inject custom web fonts before rendering
  registerFonts(module.fonts)
  return module
}

export async function loadDesign(id: string, version?: string): Promise<DesignModule | null> {
  const ready = registeredDesign(id)
  if (ready) return ready

  const inflight = attempts.get(id)
  if (inflight) return inflight

  const attempt = fetchDesign(id, version).then((module) => {
    if (!module) attempts.delete(id)
    return module
  })

  attempts.set(id, attempt)
  return attempt
}

/** Fallback design lookup: retrieve any currently registered design to prevent blank rendering. */
function anyLoaded(exceptId: string): DesignModule | null {
  for (const id of registeredDesignIds()) {
    if (id !== exceptId) return registeredDesign(id)
  }
  return null
}

/** React hook: load and retain active design module across dynamic transitions. */
export function useDesignModule(id: string, version?: string): DesignModule | null {
  const [module, setModule] = useState<DesignModule | null>(() => registeredDesign(id))

  useEffect(() => {
    const ready = registeredDesign(id)
    if (ready) {
      setModule(ready)
      return
    }

    let cancelled = false
    void loadDesign(id, version).then((loaded) => {
      if (cancelled) return
      setModule(loaded ?? anyLoaded(id))
    })

    return () => {
      cancelled = true
    }
  }, [id, version])

  return module
}
