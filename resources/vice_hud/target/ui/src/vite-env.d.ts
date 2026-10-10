/// <reference types="vite/client" />

import type * as Host from './host'

declare global {
  interface Window {
    /** Design SDK interface published by host runtime for dynamic design pack modules. */
    OsmTargetHost?: typeof Host
    invokeNative?: unknown
    GetParentResourceName?: () => string
    webkitAudioContext?: typeof AudioContext
  }
}

export {}
