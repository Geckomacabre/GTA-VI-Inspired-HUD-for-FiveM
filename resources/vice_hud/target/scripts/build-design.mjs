#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { resolve } from 'node:path'
import { SOURCE_DIR, UI_DIR, sourceDesignIds } from './lib/designs.mjs'

/**
 * Design pack build script: compiles design components into `designs/<id>/` using Vite.
 *
 * Usage:
 *   node scripts/build-design.mjs <design_id>
 *   node scripts/build-design.mjs --all
 */

const VITE = resolve(UI_DIR, 'node_modules/vite/bin/vite.js')
if (!existsSync(VITE)) {
  console.error('vite is not installed. Run `npm install` in ui/ first.')
  process.exit(1)
}

const args = process.argv.slice(2).filter((arg) => arg !== '--')
const ids = args.length === 0 || args.includes('--all') ? sourceDesignIds() : args

if (ids.length === 0) {
  console.error('no design sources found in ui/src/designs/')
  process.exit(1)
}

for (const id of ids) {
  if (!existsSync(resolve(SOURCE_DIR, id, 'index.tsx'))) {
    console.error(`no design source at ui/src/designs/${id}/index.tsx`)
    process.exit(1)
  }

  console.log(`\n── building design "${id}" ──`)

  const result = spawnSync(
    process.execPath,
    [VITE, 'build', '-c', 'vite.design.config.ts'],
    { cwd: UI_DIR, stdio: 'inherit', env: { ...process.env, DESIGN_ID: id } },
  )

  if (result.status !== 0) process.exit(result.status ?? 1)
}

console.log(`\nbuilt ${ids.length} design pack(s): ${ids.join(', ')}`)
