import { mockData } from '../dev/mockData'

/** Resource folder name, used when GetParentResourceName is unavailable. */
export const RESOURCE_FALLBACK = 'osm-target'

/** Browser environment check: validates native invocation globals. */
export const isEnvBrowser = !window.invokeNative && !window.GetParentResourceName

function resourceName(): string {
  return window.GetParentResourceName ? window.GetParentResourceName() : RESOURCE_FALLBACK
}

/** Dispatches NUI callback requests to client Lua backend. */
export async function fetchNui<T = unknown>(event: string, data?: unknown): Promise<T> {
  if (isEnvBrowser) return mockData<T>(event, data)

  const res = await fetch(`https://${resourceName()}/${event}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data ?? {}),
  })
  return (await res.json()) as T
}

export function closeNui() {
  return fetchNui('closeUI')
}

/** Parses active surface query parameters from URL. */
export function surfaceParams() {
  const params = new URLSearchParams(window.location.search)
  return {
    surface: (params.get('surface') ?? 'app') as 'app' | 'menu' | 'indicator' | 'cursor',
    state: (params.get('state') ?? 'idle') as 'idle' | 'near' | 'active',
    design: params.get('design') ?? 'rail',
    // Read version from query string: enables immediate cache-busting on initial DUI fetch.
    version: params.get('v') ?? undefined,
  }
}
