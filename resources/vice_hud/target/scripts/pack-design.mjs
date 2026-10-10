#!/usr/bin/env node
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  PACK_DIR,
  ROOT,
  SOURCE_DIR,
  builtDesignIds,
  collectBaseReleaseFiles,
  collectSourceFiles,
  readDescriptor,
  resolveBasePublicDir,
} from './lib/designs.mjs'
import { zip } from './lib/zip.mjs'

/**
 * Design pack packaging script: creates standalone ZIP archives for distributable design packs.
 *
 * Each archive contains:
 *   1. A full `osm-target/` folder pre-loaded with the purchased design (ready to drop into resources).
 *   2. Standalone add-on files (`designs/` and `ui/src/designs/`) for existing installations.
 *   3. A comprehensive `README.md` detailing both installation methods.
 *
 * Supported Tiers:
 *   - Built Edition: Full osm-target runtime + compiled design bundle (`designs/<id>/`).
 *   - Source Edition: Full osm-target runtime & UI development setup + uncompiled UI source (`ui/src/designs/<id>/`).
 *
 * Usage:
 *   node scripts/pack-design.mjs <design_id> [--built | --source | --both]
 *   node scripts/pack-design.mjs --all [--built | --source | --both]
 */

const OUT_DIR = resolve(ROOT, 'dist/packs')

const README_BUILT = (design) => `# ${design.label} — Design Pack for osm-target
> **Edition:** Built (Ready-to-Use / Production)  
> **Pack Version:** v${design.version}  
> **SDK Contract:** ${design.sdk}  

Thank you for purchasing **${design.label}**!

This package provides **two installation options** for your convenience:
1. **Full Pre-Installed Resource (\`osm-target/\` folder)**: A complete, latest release of \`osm-target\` with "${design.label}" pre-installed and ready to run.
2. **Standalone Add-On (\`designs/\` folder)**: Direct drop-in files if you already have \`osm-target\` installed.

---

## 📦 Package Contents

\`\`\`
osm-target/                         # Complete ready-to-run FiveM resource (latest release)
  ├── fxmanifest.lua
  ├── config.lua
  ├── client/...
  ├── server/...
  ├── shared/...
  ├── locales/...
  ├── html/...
  └── designs/
        ├── rail/                   # Base Context Rail design
        └── ${design.id}/           # Pre-installed ${design.label}
              ├── design.lua
              └── design.js
designs/${design.id}/               # Standalone add-on for existing installations
  ├── design.lua
  └── design.js
README.md                           # This guide
\`\`\`

---

## 🚀 Installation Instructions

### Option 1: Complete Resource (Recommended for New Setups)
1. Copy the **\`osm-target\`** folder from this archive directly into your server's resource directory:
   \`\`\`
   resources/[osmfx]/osm-target/
   \`\`\`
   *(or \`resources/osm-target/\`)*
2. In your \`server.cfg\`, ensure \`osm-target\` starts after its dependencies:
   \`\`\`cfg
   ensure ox_lib
   ensure oxmysql
   ensure osm-target
   \`\`\`
3. Start or restart your server.

---

### Option 2: Standalone Add-On (For Existing osm-target Installations)
1. If you already have \`osm-target\` installed, simply copy the **\`designs\`** folder from this package into your existing \`osm-target\` resource root:
   \`\`\`
   osm-target/
     └── designs/
           └── ${design.id}/
                 ├── design.lua
                 └── design.js
   \`\`\`
2. In your server console or txAdmin, run:
   \`\`\`bash
   restart osm-target
   \`\`\`

---

## 🎨 Activating & Customizing the Design

- **Method A (In-Game Admin GUI):**
  Execute \`/targetadmin\` in-game (requires ACE permission \`command.targetadmin\`).
  Locate **"${design.label}"** in the design list, select it, customize colors, typography, or badge styles in real-time, and click **Save**.
- **Method B (Server Default in config.lua):**
  In \`osm-target/config.lua\`, set:
  \`\`\`lua
  Config.Design = '${design.id}'
  \`\`\`

All settings saved via \`/targetadmin\` are automatically stored in your database (\`oxmysql\`) and persist across restarts.

---

## 🔄 Updating & Removal

- **Updating:** Replace \`osm-target/designs/${design.id}/\` with the new version and run \`restart osm-target\`. Your database configuration is preserved.
- **Removal:** Delete \`osm-target/designs/${design.id}/\` and restart. The resource will seamlessly fall back to your default design.

---
*Created by OsmFX Mods. Built for high performance, zero-conflict world-space interaction in FiveM.*
`

const README_SOURCE = (design) => `# ${design.label} — Design Pack for osm-target
> **Edition:** Full Source & Developer Edition (Editable + Built)  
> **Pack Version:** v${design.version}  
> **SDK Contract:** ${design.sdk}  

Thank you for purchasing the **Developer Edition** of **${design.label}**!

This package provides everything needed to run, customize, and rebuild the design:
1. **Full Pre-Installed Resource (\`osm-target/\` folder)**: A complete, latest release of \`osm-target\` containing the pre-compiled bundle AND the uncompiled TypeScript/React source code pre-placed into \`ui/src/designs/${design.id}/\`.
2. **Standalone Add-On & Source Folders**: If you already maintain an existing \`osm-target\` repository.

---

## 📦 Package Contents

\`\`\`
osm-target/                         # Complete ready-to-run FiveM resource with UI development setup
  ├── fxmanifest.lua
  ├── config.lua
  ├── client/...
  ├── server/...
  ├── shared/...
  ├── locales/...
  ├── html/...
  ├── designs/
  │     └── ${design.id}/           # Pre-compiled bundle
  │           ├── design.lua
  │           └── design.js
  ├── scripts/...                   # Build and packaging automation scripts
  └── ui/                           # React / Vite development environment
        └── src/
              └── designs/
                    └── ${design.id}/  # Pre-placed editable source files
                          ├── index.tsx
                          ├── design.lua
                          ├── mock.ts
                          └── ...
designs/${design.id}/               # Standalone pre-compiled bundle
ui/src/designs/${design.id}/        # Standalone editable source files
README.md                           # This developer & build guide
\`\`\`

---

## ⚡ Fast Track: Running Immediately

If you simply want to test or run the design first without editing:
1. Copy the included **\`osm-target\`** folder directly into your server's resources.
2. In your \`server.cfg\`, add \`ensure osm-target\` after \`ox_lib\` and \`oxmysql\`.
3. Open \`/targetadmin\` in-game or set \`Config.Design = '${design.id}'\` in \`config.lua\`.

---

## 🛠️ Developer Setup & Rebuilding

### Prerequisites
- Node.js 18+ & npm
- FiveM Server (for live in-game testing)

### 1. Development Environment
The included **\`osm-target\`** folder already contains the complete UI project and the source files for **${design.label}**.

Open your terminal in \`osm-target/ui/\`:
\`\`\`bash
cd osm-target/ui
npm install
\`\`\`

### 2. Live Browser Preview (Dev Mode)
You can iterate on design changes with instant hot-reload without opening FiveM:
\`\`\`bash
npm run dev
\`\`\`
Open the browser URL:
\`\`\`
http://localhost:5173/?surface=menu&design=${design.id}&demo=1
\`\`\`
This harness gives you instant Hot Module Replacement (HMR) for testing layouts, color tunables, badges, and responsive wrapping.

### 3. Build the Production Bundle
When you are satisfied with your custom changes in \`ui/src/designs/${design.id}/\`:
\`\`\`bash
npm run build:design -- ${design.id}
\`\`\`
This will:
- Compile your React & TypeScript components into a high-performance IIFE bundle at \`osm-target/designs/${design.id}/design.js\`.
- Automatically synchronize \`design.lua\` into \`osm-target/designs/${design.id}/design.lua\`.

### 4. Verify SDK Compliance
Run the automated contract verifier:
\`\`\`bash
npm run verify
\`\`\`
This validates that:
- The bundle evaluates cleanly in a sandboxed V8 context without runtime crashes.
- All exports match the SDK contract (\`Menu\`, \`Indicator\`, \`Cursor\`).
- Only approved \`@host\` bindings are consumed.

---

## 📐 Architecture & Customization Guide

### Design Contract
Every design exports three root view components:
- **\`Menu\`**: Renders the options list, focus state, badge indicators, and labels.
- **\`Indicator\`**: World-space marker displayed when pointing at or nearing interactable entities.
- **\`Cursor\`**: Interactive screen cursor / aiming point.

### Host Externalization (\`@host\`)
Do **not** import React directly from \`'react'\`. Always import from \`'@host'\`:
\`\`\`tsx
import {
  registerDesign, useState, useEffect, useRef,
  OptionIcon, CursorShape, IndicatorShape,
  readNumber, readString, readBool, rgba, EASE
} from '@host'
\`\`\`
This ensures the design shares the runtime React instance and icon sets provided by \`osm-target\`, keeping bundle sizes ultra-lean (~10-15 kB).

### Tunables & Schema (\`design.lua\`)
Customizable settings are declared in \`ui/src/designs/${design.id}/design.lua\`.
Controls defined here automatically appear inside the \`/targetadmin\` in-game UI with color pickers, number sliders, select dropdowns, and toggles.

---
*Created by OsmFX Mods. Built for high performance, zero-conflict world-space interaction in FiveM.*
`

function ensureBaseDir() {
  let baseDir = resolveBasePublicDir()
  if (baseDir) return baseDir

  const packPublicScript = resolve(ROOT, 'scripts/pack-public.mjs')
  if (existsSync(packPublicScript)) {
    console.log('No public osm-target directory found. Staging via scripts/pack-public.mjs...')
    const packPublic = spawnSync(process.execPath, [packPublicScript], {
      cwd: ROOT,
      stdio: 'inherit',
    })

    if (packPublic.status === 0) {
      baseDir = resolveBasePublicDir()
    }
  }

  return baseDir
}

function packBuilt(design, baseDir) {
  const { id, version } = design
  const descriptor = resolve(PACK_DIR, id, 'design.lua')
  const bundle = resolve(PACK_DIR, id, 'design.js')

  const descriptorData = readFileSync(descriptor)
  const bundleData = readFileSync(bundle)

  const entriesMap = new Map()

  // 1. Include base osm-target resource files (runtime only)
  if (baseDir) {
    const baseFiles = collectBaseReleaseFiles(baseDir, { includeUi: false })
    for (const { relPath, fullPath } of baseFiles) {
      if (relPath.startsWith(`designs/${id}/`)) continue
      entriesMap.set(`osm-target/${relPath}`, readFileSync(fullPath))
    }

    // Inject design into osm-target folder
    entriesMap.set(`osm-target/designs/${id}/design.lua`, descriptorData)
    entriesMap.set(`osm-target/designs/${id}/design.js`, bundleData)
  }

  // 2. Include root standalone files for existing installations
  entriesMap.set(`designs/${id}/design.lua`, descriptorData)
  entriesMap.set(`designs/${id}/design.js`, bundleData)
  entriesMap.set('README.md', Buffer.from(README_BUILT(design), 'utf8'))

  const entries = Array.from(entriesMap.entries()).map(([name, data]) => ({ name, data }))

  mkdirSync(OUT_DIR, { recursive: true })

  // Primary built archive
  const builtFile = resolve(OUT_DIR, `osm-target-${id}-v${version}-built.zip`)
  const zipBuffer = zip(entries)
  writeFileSync(builtFile, zipBuffer)

  // Standard alias for compatibility
  const aliasFile = resolve(OUT_DIR, `osm-target-${id}-v${version}.zip`)
  writeFileSync(aliasFile, zipBuffer)

  const kb = (zipBuffer.length / 1024).toFixed(1)
  console.log(`  dist/packs/osm-target-${id}-v${version}-built.zip  (${kb} kB archive, ${entries.length} files)`)
}

function packSource(design, baseDir) {
  const { id, version } = design
  const descriptor = resolve(PACK_DIR, id, 'design.lua')
  const bundle = resolve(PACK_DIR, id, 'design.js')

  const sourceFiles = collectSourceFiles(id)
  if (sourceFiles.length === 0) {
    console.warn(`  [warning] No source files found in ui/src/designs/${id}/. Skipping source pack.`)
    return
  }

  const descriptorData = readFileSync(descriptor)
  const bundleData = readFileSync(bundle)

  const entriesMap = new Map()

  // 1. Include base osm-target resource files (including UI development environment)
  if (baseDir) {
    const baseFiles = collectBaseReleaseFiles(baseDir, { includeUi: true })
    for (const { relPath, fullPath } of baseFiles) {
      if (relPath.startsWith(`designs/${id}/`) || relPath.startsWith(`ui/src/designs/${id}/`)) continue
      entriesMap.set(`osm-target/${relPath}`, readFileSync(fullPath))
    }

    // Inject compiled design into osm-target folder
    entriesMap.set(`osm-target/designs/${id}/design.lua`, descriptorData)
    entriesMap.set(`osm-target/designs/${id}/design.js`, bundleData)

    // Inject uncompiled source files into osm-target/ui/src/designs/<id>/
    for (const { relPath, fullPath } of sourceFiles) {
      entriesMap.set(`osm-target/ui/src/designs/${id}/${relPath}`, readFileSync(fullPath))
    }
  }

  // 2. Include root standalone files
  entriesMap.set(`designs/${id}/design.lua`, descriptorData)
  entriesMap.set(`designs/${id}/design.js`, bundleData)

  for (const { relPath, fullPath } of sourceFiles) {
    entriesMap.set(`ui/src/designs/${id}/${relPath}`, readFileSync(fullPath))
  }

  entriesMap.set('README.md', Buffer.from(README_SOURCE(design), 'utf8'))

  const entries = Array.from(entriesMap.entries()).map(([name, data]) => ({ name, data }))

  mkdirSync(OUT_DIR, { recursive: true })
  const sourceFile = resolve(OUT_DIR, `osm-target-${id}-v${version}-source.zip`)
  const zipBuffer = zip(entries)
  writeFileSync(sourceFile, zipBuffer)

  const kb = (zipBuffer.length / 1024).toFixed(1)
  console.log(`  dist/packs/osm-target-${id}-v${version}-source.zip (${kb} kB archive, ${entries.length} files)`)
}

function packDesign(id, tier, baseDir) {
  const descriptor = resolve(PACK_DIR, id, 'design.lua')
  const design = readDescriptor(descriptor)

  if (design.id !== id) {
    throw new Error(`designs/${id}/design.lua declares id "${design.id}"`)
  }

  if (tier === 'built') {
    packBuilt(design, baseDir)
  } else if (tier === 'source') {
    packSource(design, baseDir)
  } else {
    packBuilt(design, baseDir)
    packSource(design, baseDir)
  }
}

// Parse command line arguments
const rawArgs = process.argv.slice(2).filter((arg) => arg !== '--')
let tier = 'both'
if (rawArgs.includes('--built')) tier = 'built'
else if (rawArgs.includes('--source')) tier = 'source'
else if (rawArgs.includes('--both') || rawArgs.includes('--all-tiers')) tier = 'both'

const isAll = rawArgs.includes('--all')
const ids = rawArgs.filter((arg) => !arg.startsWith('--'))
const built = builtDesignIds()
const targetIds = isAll || ids.length === 0 ? built : ids

if (targetIds.length === 0) {
  console.error('nothing to pack. Run `npm run build:designs` in ui/ first.')
  process.exit(1)
}

for (const id of targetIds) {
  if (!built.includes(id)) {
    console.error(`designs/${id}/ is not built. Run: npm run build:design -- ${id}`)
    process.exit(1)
  }
}

const baseDir = ensureBaseDir()
if (baseDir) {
  console.log(`using base osm-target from: ${baseDir}`)
} else {
  console.warn('warning: could not locate base osm-target directory; packaging standalone design files only.')
}

console.log(`\npackaging designs (tier: ${tier}):`)
for (const id of targetIds) {
  console.log(`\n• ${id}`)
  packDesign(id, tier, baseDir)
}
console.log('\npackaging complete.')
