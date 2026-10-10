import { copyFileSync, existsSync, mkdirSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

/**
 * Vite design pack build configuration: compiles individual design components into `designs/<id>/`.
 */

const here = dirname(fileURLToPath(import.meta.url))

const id = process.env.DESIGN_ID?.trim()
if (!id) {
  throw new Error('DESIGN_ID is not set. Use `npm run build:design -- <id>`.')
}

const sourceDir = resolve(here, 'src/designs', id)
const outDir = resolve(here, '../designs', id)
const descriptor = resolve(sourceDir, 'design.lua')

if (!existsSync(resolve(sourceDir, 'index.tsx'))) {
  throw new Error(`no design source at ui/src/designs/${id}/index.tsx`)
}
if (!existsSync(descriptor)) {
  throw new Error(
    `no descriptor at ui/src/designs/${id}/design.lua — a pack without it registers nothing`,
  )
}

/** Parse pack version string from design.lua descriptor for cache-busting. */
function descriptorVersion(): string {
  const match = readFileSync(descriptor, 'utf8').match(/version\s*=\s*'([^']+)'/)
  if (!match) throw new Error(`${descriptor} declares no version`)
  return match[1]
}

function packPlugin(): Plugin {
  return {
    name: 'osm-target-design-pack',

    // Validate emitted bundle: ensure only design.js is output
    generateBundle(_options, bundle) {
      const unexpected = Object.keys(bundle).filter((name) => name !== 'design.js')
      if (unexpected.length > 0) {
        this.error(
          `design "${id}" emitted ${unexpected.join(', ')}. A design pack may only emit ` +
            `design.js: use inline styles and the host's helpers rather than importing assets.`,
        )
      }
    },

    closeBundle() {
      mkdirSync(outDir, { recursive: true })
      copyFileSync(descriptor, resolve(outDir, 'design.lua'))
      console.log(`\n  design pack: designs/${id}/  (v${descriptorVersion()})\n`)
    },
  }
}

export default defineConfig({
  plugins: [react(), packPlugin()],
  build: {
    outDir,
    // Preserve directory contents: avoid wiping copied design.lua
    emptyOutDir: false,
    // Target Chromium 91 compatibility for FiveM NUI environment
    target: 'chrome91',
    cssTarget: 'chrome91',
    // Force EVERY imported asset (button-glyph PNGs, etc.) to inline as a
    // base64 data: URI, regardless of size. Vite's default 4kb cutoff would
    // otherwise emit the larger ones as separate files under designs/<id>/,
    // which the packPlugin below deliberately rejects: a design pack ships
    // as one design.js, because that is the only file DUI's asset-path
    // resolution (see html/index.html / client/ui/surfaces.lua) is set up to
    // load. Assets small enough to matter here (a handful of cropped button
    // icons, a few KB apiece) cost nothing meaningful inlined.
    assetsInlineLimit: Infinity,
    lib: {
      entry: resolve(sourceDir, 'index.tsx'),
      formats: ['iife'],
      // IIFE global export identifier
      name: `OsmDesign_${id.replace(/[^A-Za-z0-9_]/g, '_')}`,
      fileName: () => 'design.js',
    },
    rollupOptions: {
      external: ['@host', 'react', 'react-dom', 'react/jsx-runtime'],
      output: {
        globals: {
          '@host': 'OsmTargetHost',
          react: 'OsmTargetHost.React',
          'react-dom': 'OsmTargetHost.ReactDOM',
          'react/jsx-runtime': 'OsmTargetHost.jsxRuntime',
        },
      },
    },
  },
})
