# Development Guide

This guide covers setting up the development environment, developing the UI, adding custom interface designs, and performing verification checks.

---

## UI Development Environment

The user interface is built with React, TypeScript, and Vite inside the `ui/` directory:

```bash
cd ui
npm install
npm run dev              # Launch local browser development server
npm run build            # Build the host into html/
npm run build:designs    # Build every design pack into designs/<id>/
npm run build:all        # Both of the above
npm run verify           # Check the built packs against the design SDK
```

The host and individual designs are **separate builds**:
- `npm run build` compiles the host into `html/` without modifying `designs/`.
- `npm run build:designs` compiles each design pack into its dedicated `designs/<id>/` bundle.
- See [Design Packs](./design-packs.md) for architecture and SDK specifications.

### Browser Development Tools
- **Live Preview Harness**: Running `npm run dev` exposes a top development bar to simulate state payloads and switch surfaces.
- **Surface URLs**: Each surface can be loaded directly with query parameters:
  - `?surface=menu&design=rail` — Test the menu surface with a specific design.
  - `?surface=indicator&state=near` — Test the world indicator surface.
  - `?surface=cursor` — Test the screen cursor surface.
  - `?demo=1` — Automatically populates sample options of various lengths and gate types.
  - `?demo=admin` — Opens the in-game admin panel with mock backend data.

---

## Adding a New Design

Design packs are modular subpackages residing in `designs/<id>/` (see [Design Packs](./design-packs.md) for full specifications). Adding a new design requires implementing the component bundle and the metadata descriptor:

1. **Component Implementation (`ui/src/designs/<id>/index.tsx`)**:
   Import required utilities and types from `@host` and register the design module:

   ```tsx
   import { registerDesign, useState, OptionIcon, readNumber, EASE } from '@host'
   import type { CursorViewProps, DesignModule, IndicatorViewProps, MenuViewProps } from '@host'

   function Menu({ options, focus, tunables, reducedMotion }: MenuViewProps) { /* ... */ }
   function Indicator({ state, tunables }: IndicatorViewProps) { /* ... */ }
   function Cursor({ tunables }: CursorViewProps) { /* ... */ }

   const design: DesignModule = { id: 'mydesign', sdk: 1, Menu, Indicator, Cursor }

   registerDesign(design)

   export default design
   ```

   - **Externalized Dependencies**: Always import from `@host` rather than direct `react` imports to prevent duplicate runtime instances.
   - **Styling**: Use inline styles or core class utilities (`.world`, `.world-anchor`, `.num`). Do not rely on utility classes generated exclusively for host surfaces.

2. **Metadata Descriptor (`ui/src/designs/<id>/design.lua`)**:
   Defines identity, tunable controls, and default parameters for server-side registration and the admin panel:

   ```lua
   local Designs = OsmTargetDesigns

   Designs.define {
     id = 'mydesign',
     sdk = 1,
     version = '1.0.0',
     label = 'My Design',
     tagline = 'What it looks like and how it behaves.',
     accent = '#14b8a6',
     anchor = { x = 0.34, y = 0.0 },
     schema = Designs.extend(Designs.commonSchema(), {
       { key = 'customWidth', label = 'Custom width', type = 'number', default = 400,
         min = 200, max = 600, group = 'Design', tier = 'basic', affects = 'menu',
         help = 'Adjusts custom panel width.' },
     }),
     overrides = { accent = '#14b8a6', corner = 14 },
   }
   ```

   `Designs.commonSchema()`, `commonSchemaExcept(...)`, `retune()`, and `extend()` provide the standardized tunable vocabulary.

3. **Development Mock Schema (`ui/src/designs/<id>/mock.ts`)**:
   Mirrors the Lua schema in TypeScript to support browser-based previews during `npm run dev`.

4. **Compilation**:

   ```bash
   cd ui
   npm run build:design -- mydesign   # Compiles to designs/mydesign/{design.js, design.lua}
   npm run verify                     # Validates pack bundle against the SDK contract
   ```

   Upon resource restart, the design is automatically discovered and listed in `/targetadmin`.

5. **Shared Tunable Integration**:
   Utilize `@host` helper functions (`labelLines`, `disabledStyle`, `amp`, `duration`, `gate`) to ensure typography, gating, and motion preferences remain consistent across all designs.

---

## Releasing and Packaging

```bash
cd ui
npm run build:all      # Builds host and all design packs
npm run verify         # Validates packs against the SDK
npm run pack -- <id>   # Packages dist/packs/osm-target-<id>-v<version>.zip
npm run pack:public    # Builds dist/public/osm-target (public distribution)
```

The `pack:public` script stages a release distribution and verifies that the core build compiles cleanly. Which packs it includes is configured in `scripts/lib/designs.mjs`.

---

## Verification & Pre-Release Checklist

Before releasing or deploying builds, complete the following manual checks in-game:

- [ ] **Targeting Hysteresis**: Verify target acquisition at `snapAngle`, stability during camera adjustments, and release after `releaseTime`.
- [ ] **Entity Tracking**: Verify world-space anchor tracking on moving vehicles and walking peds.
- [ ] **Distance Scaling**: Verify menu and indicator readability across interaction distance extremes.
- [ ] **Resource Lifecycle & Teardown**: Verify that all DUI surfaces are properly hidden and cleaned up upon player death, opening the pause menu, starting cutscenes, entity deletion, and resource restarts.
- [ ] **Input Suppression**: Verify weapon cycling and attack controls are suppressed while targeting and restored immediately upon key release.
- [ ] **Resolution Handling**: Verify DUI scaling and positioning after display resolution changes and window alt-tabbing.
- [ ] **Dialect Compatibility**: Test registration, display, and execution of unmodified legacy scripts for `ox_target`, `qb-target`, and `qtarget`.
- [ ] **Replacement Coexistence**: With `ox_target` / `qb-target` / `qtarget` removed, verify dependent resources still resolve through the `provide` declarations in `fxmanifest.lua`.
- [ ] **Design Installation**: Copy a pack directory into `designs/`, restart, and confirm it appears in `/targetadmin` without manual manifest changes.
- [ ] **Design Removal**: Delete an active design pack directory, restart, and confirm fallback to the default design occurs cleanly with saved database configuration intact.
- [ ] **Design Updates**: Deploy a higher-version design pack bundle and verify that the updated UI bundle is fetched without browser caching issues.
