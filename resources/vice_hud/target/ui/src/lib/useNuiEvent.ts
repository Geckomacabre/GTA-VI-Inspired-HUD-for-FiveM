import { useEffect, useRef } from 'react'

/**
 * SendNUIMessage and SendDuiMessage both deliver through the same `message`
 * event, so one hook serves every surface. Lua sends `{ action, data }`.
 */
export function useNuiEvent<T = unknown>(action: string, handler: (data: T) => void) {
  const saved = useRef(handler)
  saved.current = handler

  useEffect(() => {
    const listener = (event: MessageEvent) => {
      const payload = event.data
      if (!payload || payload.action !== action) return
      saved.current((payload.data ?? payload) as T)
    }

    window.addEventListener('message', listener)
    return () => window.removeEventListener('message', listener)
  }, [action])
}
