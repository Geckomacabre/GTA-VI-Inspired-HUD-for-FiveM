/**
 * Design SDK host interface: exports runtime dependencies, drawing utilities, and registration hooks for design packs.
 */

import type { DesignModule } from '../lib/types'

/** Host SDK contract version supported by the runtime. */
export const SDK = 1

// React runtime exports: expose core hooks and component utilities to design bundles
export {
  Fragment,
  useCallback,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
} from 'react'
export type { ComponentType, CSSProperties, ReactNode } from 'react'

// JSX runtime namespaces: map external compiler imports to host React instance
import * as React from 'react'
import * as ReactDOM from 'react-dom'
import * as jsxRuntime from 'react/jsx-runtime'

export { React, ReactDOM, jsxRuntime }

// Contract interfaces: shared type definitions for design modules and UI state
export type {
  CursorViewProps,
  DesignControl,
  DesignFont,
  DesignManifestEntry,
  DesignModule,
  DesignRuntime,
  IndicatorState,
  IndicatorViewProps,
  InputDevice,
  InputPrompts,
  MenuMode,
  MenuViewProps,
  OptionBadge,
  Preferences,
  TargetOption,
  Tunables,
} from '../lib/types'

// Shared drawing helpers: typography, motion, and shape rendering utilities
export { OptionIcon, resolveIcon } from '../lib/icons'
export type { IconWeight } from '../lib/icons'

export { hexToRgb, rgba } from '../lib/appearance'

export { ChevronGlyph, CursorShape, IndicatorShape, LockGlyph } from '../designs/shared/shapes'
export type { CursorShapeName, IndicatorShapeName } from '../designs/shared/shapes'

export {
  EASE,
  amp,
  clampLines,
  disabledStyle,
  duration,
  gate,
  gatedLabel,
  intensity,
  labelLines,
  labelType,
  readBool,
  readNumber,
  readString,
  showsLock,
} from '../designs/shared/read'
export type { DisabledStyle } from '../designs/shared/read'

// Design registration: manage runtime registration and asynchronous loading promises
const registry = new Map<string, DesignModule>()
const waiting = new Map<string, ((module: DesignModule) => void)[]>()

export function registerDesign(module: DesignModule): void {
  if (module.sdk !== SDK) {
    console.error(
      `[osm-target] design "${module.id}" was built against SDK ${module.sdk}, ` +
        `this build of osm-target provides SDK ${SDK}. Update the design pack. Not registered.`,
    )
    return
  }

  registry.set(module.id, module)

  const queued = waiting.get(module.id)
  if (!queued) return
  waiting.delete(module.id)
  for (const resolve of queued) resolve(module)
}

/** Get registered design module: returns design module or null if not yet loaded. */
export function registeredDesign(id: string): DesignModule | null {
  return registry.get(id) ?? null
}

export function registeredDesignIds(): string[] {
  return [...registry.keys()]
}

/** Wait for design registration: resolves when target design module registers. */
export function whenRegistered(id: string): Promise<DesignModule> {
  const present = registry.get(id)
  if (present) return Promise.resolve(present)

  return new Promise((resolve) => {
    const queued = waiting.get(id)
    if (queued) queued.push(resolve)
    else waiting.set(id, [resolve])
  })
}
