# Design Authoring & Packaging Guide

This guide details how to create new interface designs for **osm-target**, test and verify them against the Design SDK, and package them into distributable **Built** and **Source** ZIP archives.

---

## 1. Overview & Distribution Model

`osm-target` uses a modular design pack system. The base resource ships with the default **Context Rail** (`rail`) design. Further designs are dropped into `designs/` and picked up on restart, without touching the core code.

### The Two Distribution Tiers

| Tier | Archive Filename | Target Audience | What is Included |
|---|---|---|---|
| **Built Edition** | `osm-target-<id>-v<version>-built.zip` | Standard server owners / plug-and-play installs | **Complete `osm-target/` resource** with `<id>` pre-installed, **plus** standalone `designs/<id>/` folder and `README.md`. |
| **Source Edition** | `osm-target-<id>-v<version>-source.zip` | Developers wanting to customize designs | **Complete `osm-target/` resource** with `<id>` pre-installed **AND** uncompiled source files in `osm-target/ui/src/designs/<id>/`, **plus** standalone `designs/<id>/` & `ui/src/designs/<id>/` folders and `README.md`. |

---

## 2. Authoring a New Design

To create a new design (e.g. `mydesign`):

### Directory Structure
Create a new directory inside `ui/src/designs/<id>/`:

```
osm-target/
  └── ui/
        └── src/
              └── designs/
                    └── <id>/
                          ├── index.tsx       # React components (Menu, Indicator, Cursor)
                          ├── design.lua      # Lua descriptor, schema controls, and defaults
                          ├── mock.ts         # Development mock for browser harness
                          └── (optional)      # Extra SVGs, glyphs, or subcomponents
```

### Component Implementation (`ui/src/designs/<id>/index.tsx`)
```tsx
import {
  registerDesign, useState, useEffect, useRef,
  OptionIcon, CursorShape, IndicatorShape,
  readNumber, readString, readBool, rgba, EASE
} from '@host'
import type { CursorViewProps, DesignModule, IndicatorViewProps, MenuViewProps } from '@host'

function Menu({ options, focus, tunables, reducedMotion }: MenuViewProps) {
  // Render options list, focus state, badges, and labels
  return (
    <div className="world">
      {/* Your menu markup */}
    </div>
  )
}

function Indicator({ state, tunables }: IndicatorViewProps) {
  // World-space target marker (idle vs near vs focused)
  return <IndicatorShape style="dot" />
}

function Cursor({ tunables }: CursorViewProps) {
  // Center screen aiming cursor
  return <CursorShape style="dot" />
}

const design: DesignModule = {
  id: '<id>',
  sdk: 1,
  Menu,
  Indicator,
  Cursor,
}

registerDesign(design)
export default design
```

> [!IMPORTANT]
> **Host SDK Rules:**
> 1. **Always import from `@host`**: Do not import `react` directly. The host runtime provides React, ReactDOM, and shared helpers via `window.OsmTargetHost`. This keeps design bundles lightweight (~10–15 kB).
> 2. **No external CSS files**: Bundle styles via inline CSS, SVG, CSS variables, or the shared class utilities (`.world`, `.world-anchor`).
> 3. **Stateless relative to FiveM**: Components receive active options and tunables via props from the host.
> 4. **Images ship inlined, not as separate files**: a design pack builds to exactly one `design.js` (`vite.design.config.ts`'s `packPlugin` fails the build if anything else is emitted) — that is the only file DUI's asset-path resolution (`html/index.html`, loaded per `client/ui/surfaces.lua`) knows how to reach. Put source images under `ui/src/designs/<id>/assets/` and `import` them normally (`import icon from './assets/icon.png'`); `vite.design.config.ts` sets `build.assetsInlineLimit: Infinity` so every imported asset — regardless of size — is base64-inlined into `design.js` instead of emitted alongside it. See `ui/src/designs/rail/index.tsx`'s `BUTTON_ICONS`/`MOUSE_ICONS` for a worked example (real Xbox/PlayStation/mouse button art swapped in for the pad/mouse `resolveGlyph` text path).

### Lua Descriptor (`ui/src/designs/<id>/design.lua`)
```lua
local Designs = OsmTargetDesigns

Designs.define {
  id = '<id>',
  sdk = 1,
  version = '1.0.0',
  label = 'My Custom Design',
  tagline = 'A short description shown in /targetadmin.',
  accent = '#3b82f6',
  anchor = { x = 0.34, y = 0.0 },
  schema = Designs.extend(Designs.commonSchema(), {
    {
      key = 'mySetting',
      label = 'Custom Setting',
      type = 'number',
      default = 10,
      min = 1,
      max = 50,
      step = 1,
      group = 'Design',
      tier = 'basic',
      affects = 'menu',
      help = 'Explain what this control adjusts in /targetadmin.',
    },
  }),
  overrides = {
    accent = '#3b82f6',
    surface = '#000000',
    surfaceAlpha = 80,
  },
}
```

### Browser Mock Schema (`ui/src/designs/<id>/mock.ts`)
```ts
import { commonSchema, extend } from '../shared/mockSchema'
import type { MockDesign } from '../shared/mockSchema'

export const mock: MockDesign = {
  id: '<id>',
  label: 'My Custom Design',
  tagline: 'A short description shown in /targetadmin.',
  accent = '#3b82f6',
  anchor: { x = 0.34, y = 0.0 },
  schema: extend(commonSchema(), [
    // Mirror the controls from design.lua here
  ]),
  overrides: {
    accent: '#3b82f6',
  },
}
```

---

## 3. Local Testing & Live Preview

You do not need to open FiveM to develop or test design layouts.

1. Open a terminal in `osm-target/ui/`:
   ```bash
   npm run dev
   ```
2. Open your browser to the development URL with query parameters:
   - `http://localhost:5173/?surface=menu&design=<id>&demo=1` — Test menu layout with sample actions.
   - `http://localhost:5173/?surface=indicator&state=near` — Test world indicator.
   - `http://localhost:5173/?surface=cursor` — Test screen cursor.
   - `http://localhost:5173/?demo=admin` — Test the in-game `/targetadmin` panel controls.

---

## 4. Building & Verifying

Once your design is ready, compile and test it:

```bash
cd ui

# Compile the specific design pack
npm run build:design -- <id>

# Or compile all design packs in ui/src/designs/
npm run build:designs

# Run SDK verification checks
npm run verify
```

The verification script checks:
- Sandboxed execution in a clean V8 context (no unhandled errors).
- Clean `registerDesign` invocation.
- Proper exports (`Menu`, `Indicator`, `Cursor`).
- ID, version, and SDK contract matching between JavaScript and Lua.
- Host global bindings (ensuring only approved `@host` exports are consumed).
- Asset path resolution from `html/index.html`.

---

## 5. Packaging Distributable ZIPs

Generate the production distribution archives using the packaging scripts:

```bash
cd ui

# Package BOTH Built and Source ZIPs for a design (Recommended):
npm run pack:all-tiers -- <id>
# Or directly:
node ../scripts/pack-design.mjs <id> --both

# Package ONLY the Built edition:
npm run pack:built -- <id>

# Package ONLY the Source edition:
npm run pack:source -- <id>

# Package ALL built designs in designs/ into both tiers:
node ../scripts/pack-design.mjs --all --both
```

The output archives are placed in `dist/packs/`:
- `dist/packs/osm-target-<id>-v<version>-built.zip`
- `dist/packs/osm-target-<id>-v<version>-source.zip`
- `dist/packs/osm-target-<id>-v<version>.zip` (standard alias for backward compatibility)

Each ZIP automatically includes a dedicated, professionally formatted `README.md` customized with the design's label, version, SDK, and step-by-step instructions.

---

## 6. GitHub Actions Automated Packaging

The repository includes an automated workflow at `.github/workflows/package-designs.yml`.

### Manual Trigger (GitHub UI)
1. Go to your repository on GitHub.
2. Click the **Actions** tab.
3. Select **Package Design Packs** on the left.
4. Click **Run workflow**:
   - Choose the design ID (e.g. `rail` or `all`).
   - Choose the tier (`both`, `built`, or `source`).
   - Click **Run workflow**.
5. When complete, download the packaged ZIPs directly from the **Artifacts** section of the run.

### Release on Tag Push
Pushing a release tag (e.g. `git tag design-rail-v1.0.0 && git push origin design-rail-v1.0.0` or `v1.0.0`) automatically:
1. Runs the full build and verification suite.
2. Packages both Built and Source ZIPs.
3. Attaches the ZIP archives directly to a newly published **GitHub Release**.

---

## 7. Adding Designs to a Dedicated Designs Repo (Optional)

If you maintain a separate public or private repo exclusively for design packs (e.g. `osm-target-designs`):
1. Keep the `scripts/`, `ui/src/designs/`, and `.github/workflows/` directories in that repo.
2. Link or copy the `@host` types from `osm-target`.
3. The exact same commands (`npm run build:design -- <id>` and `npm run pack -- <id> --both`) and GitHub Actions workflow will work seamlessly.
