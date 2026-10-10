export type SfxName = 'sweep' | 'magnetise' | 'scroll' | 'confirm' | 'reject' | 'cancel'
export type PackName = 'signature' | 'soft' | 'mechanical' | 'off'

interface ToneSpec {
  type: OscillatorType
  from: number
  to?: number
  duration: number
  gain: number
  attack?: number
  delay?: number
}

interface NoiseSpec {
  duration: number
  gain: number
  cutoff: number
  q?: number
  delay?: number
}

interface Voice {
  tones?: ToneSpec[]
  noise?: NoiseSpec[]
}

type Pack = Record<SfxName, Voice>

// Sound pack voice synthesizer definitions.

const PACKS: Record<Exclude<PackName, 'off'>, Pack> = {
  signature: {
    sweep: { tones: [{ type: 'sine', from: 420, to: 640, duration: 0.14, gain: 0.05, attack: 0.01 }] },
    magnetise: {
      tones: [
        { type: 'sine', from: 320, to: 880, duration: 0.20, gain: 0.10, attack: 0.012 },
        { type: 'triangle', from: 640, to: 1320, duration: 0.16, gain: 0.045, delay: 0.02 },
      ],
    },
    scroll: { tones: [{ type: 'sine', from: 880, to: 760, duration: 0.055, gain: 0.075, attack: 0.004 }] },
    confirm: {
      tones: [
        { type: 'sine', from: 660, to: 990, duration: 0.13, gain: 0.11, attack: 0.006 },
        { type: 'sine', from: 1320, duration: 0.09, gain: 0.05, delay: 0.045 },
      ],
    },
    reject: {
      tones: [{ type: 'sine', from: 190, to: 140, duration: 0.16, gain: 0.10, attack: 0.008 }],
      noise: [{ duration: 0.07, gain: 0.028, cutoff: 700, q: 0.8 }],
    },
    cancel: { tones: [{ type: 'sine', from: 520, to: 300, duration: 0.12, gain: 0.06 }] },
  },

  soft: {
    sweep: { noise: [{ duration: 0.20, gain: 0.020, cutoff: 1600, q: 0.6 }] },
    magnetise: {
      tones: [{ type: 'sine', from: 260, to: 520, duration: 0.28, gain: 0.065, attack: 0.05 }],
      noise: [{ duration: 0.16, gain: 0.014, cutoff: 2400 }],
    },
    scroll: { tones: [{ type: 'sine', from: 560, duration: 0.05, gain: 0.045, attack: 0.012 }] },
    confirm: { tones: [{ type: 'sine', from: 440, to: 660, duration: 0.20, gain: 0.075, attack: 0.02 }] },
    reject: { tones: [{ type: 'sine', from: 170, to: 150, duration: 0.20, gain: 0.070, attack: 0.03 }] },
    cancel: { tones: [{ type: 'sine', from: 400, to: 260, duration: 0.16, gain: 0.045, attack: 0.02 }] },
  },

  mechanical: {
    sweep: { noise: [{ duration: 0.05, gain: 0.030, cutoff: 4200, q: 2.0 }] },
    magnetise: {
      noise: [
        { duration: 0.04, gain: 0.055, cutoff: 3200, q: 3.0 },
        { duration: 0.05, gain: 0.035, cutoff: 1400, q: 2.0, delay: 0.05 },
      ],
      tones: [{ type: 'square', from: 180, to: 120, duration: 0.07, gain: 0.030 }],
    },
    scroll: { noise: [{ duration: 0.028, gain: 0.055, cutoff: 5200, q: 2.6 }] },
    confirm: {
      noise: [{ duration: 0.035, gain: 0.070, cutoff: 3000, q: 2.2 }],
      tones: [{ type: 'square', from: 720, to: 900, duration: 0.055, gain: 0.035, delay: 0.02 }],
    },
    reject: {
      noise: [{ duration: 0.09, gain: 0.045, cutoff: 520, q: 1.2 }],
      tones: [{ type: 'square', from: 130, to: 96, duration: 0.11, gain: 0.045 }],
    },
    cancel: { noise: [{ duration: 0.05, gain: 0.035, cutoff: 1800, q: 1.4 }] },
  },
}

let context: AudioContext | null = null
let master: GainNode | null = null
let noiseBuffer: AudioBuffer | null = null

function ensureContext(): AudioContext | null {
  if (context) {
    // Resume audio context: handles suspended state in CEF runtime.
    if (context.state === 'suspended') void context.resume()
    return context
  }

  const Ctor = window.AudioContext ?? window.webkitAudioContext
  if (!Ctor) return null

  context = new Ctor()
  master = context.createGain()
  master.gain.value = 0.7
  master.connect(context.destination)

  const length = Math.floor(context.sampleRate * 0.5)
  noiseBuffer = context.createBuffer(1, length, context.sampleRate)
  const channel = noiseBuffer.getChannelData(0)
  for (let i = 0; i < length; i += 1) channel[i] = Math.random() * 2 - 1

  return context
}

export function setVolume(percent: number) {
  if (!ensureContext() || !master) return
  master.gain.value = Math.max(0, Math.min(1, percent / 100))
}

function playTone(ctx: AudioContext, out: GainNode, spec: ToneSpec) {
  const start = ctx.currentTime + (spec.delay ?? 0)
  const osc = ctx.createOscillator()
  const gain = ctx.createGain()

  osc.type = spec.type
  osc.frequency.setValueAtTime(spec.from, start)
  if (spec.to !== undefined) {
    osc.frequency.exponentialRampToValueAtTime(Math.max(1, spec.to), start + spec.duration)
  }

  const attack = spec.attack ?? 0.005
  gain.gain.setValueAtTime(0.0001, start)
  gain.gain.exponentialRampToValueAtTime(spec.gain, start + attack)
  gain.gain.exponentialRampToValueAtTime(0.0001, start + spec.duration)

  osc.connect(gain)
  gain.connect(out)
  osc.start(start)
  osc.stop(start + spec.duration + 0.02)
}

function playNoise(ctx: AudioContext, out: GainNode, spec: NoiseSpec) {
  if (!noiseBuffer) return

  const start = ctx.currentTime + (spec.delay ?? 0)
  const source = ctx.createBufferSource()
  const filter = ctx.createBiquadFilter()
  const gain = ctx.createGain()

  source.buffer = noiseBuffer
  filter.type = 'bandpass'
  filter.frequency.value = spec.cutoff
  filter.Q.value = spec.q ?? 1.0

  gain.gain.setValueAtTime(spec.gain, start)
  gain.gain.exponentialRampToValueAtTime(0.0001, start + spec.duration)

  source.connect(filter)
  filter.connect(gain)
  gain.connect(out)
  source.start(start)
  source.stop(start + spec.duration + 0.02)
}

/** Plays synthesized interaction sound effect from active sound pack. */
export function playSfx(name: SfxName, pack: PackName, volume: number, muted: boolean) {
  if (muted || pack === 'off' || volume <= 0) return

  const ctx = ensureContext()
  if (!ctx || !master) return

  setVolume(volume)

  const voice = PACKS[pack]?.[name]
  if (!voice) return

  voice.tones?.forEach((spec) => playTone(ctx, master as GainNode, spec))
  voice.noise?.forEach((spec) => playNoise(ctx, master as GainNode, spec))
}
