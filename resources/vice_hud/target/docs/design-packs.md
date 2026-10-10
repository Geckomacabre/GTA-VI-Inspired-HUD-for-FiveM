# Design Packs

An **osm-target** design pack is a self-contained module placed in the `designs/` directory:

```
osm-target/
  designs/
    rail/            # Default design included with osm-target
      design.lua     # Identity, tunable schema, and default values
      design.js      # Compiled UI bundle
    custom/          # Any further pack, dropped in the same way
      design.lua
      design.js
```

Packs are dynamically discovered at runtime. No manual edits to `fxmanifest.lua`, `config.lua`, or code registries are required; `fxmanifest.lua` dynamically matches `designs/**/design.lua`, and each pack registers itself upon resource startup.

---

## Installing and Managing Packs

1. **Installation**: Copy the `designs/<id>/` directory into your `osm-target` resource root. If `designs/` already exists, merge the new folder into it.
2. **Restart**: Restart the `osm-target` resource.
3. **Activation**: Open `/targetadmin` in-game, select the new design from the list, and save.

- **Updating**: Replace the existing `designs/<id>/` directory with the new version and restart the resource. Existing database configuration for that design will be preserved.
- **Removal**: Delete the `designs/<id>/` folder and restart. The resource will automatically fall back to the design defined in `config.lua`. Stored database configuration remains saved.

### Troubleshooting and Diagnostics

Pack errors are logged to the server console with the `[osm-target]` prefix:

| Console Message | Cause and Resolution |
|---|---|
| `design "<id>" is missing designs/<id>/design.js` | Incomplete pack. Both `design.lua` and `design.js` must be present. |
| `design "<id>" was built against SDK n` | SDK version mismatch. Update either the design pack or osm-target to matching SDK versions. |
| `two design packs claim the id "<id>"` | Duplicate ID declared across two directories. Remove the duplicate pack. |
| `no designs are installed` | The `designs/` directory contains no valid packs. Ensure at least one pack is installed. |

In the client F8 console, `design "<id>" did not load` indicates that the client browser could not fetch `design.js` (e.g. invalid path, missing file, or network permission issue).

---

## Pack Structure

### `design.lua`

Evaluated in shared context by both client and server. It defines the design's metadata and tunable schema for `/targetadmin`:

| Field | Required | Description |
|---|---|---|
| `id` | Yes | Unique identifier and directory name. |
| `sdk` | Yes | Target SDK version contract. Refused if host provides a different version. |
| `version` | Yes | Semantic version string used for NUI cache-busting. |
| `label`, `tagline`, `accent` | Yes | Display metadata presented in `/targetadmin`. |
| `schema` | Yes | Array of tunable controls defined via `Designs.commonSchema()` and schema helpers. |
| `overrides` | No | Design-specific defaults overriding baseline schema values. |
| `anchor` | No | World anchor coordinate offset relative to texture center `{ x, y }`. |
| `anchorRule` | No | Dynamic anchor rule mapping tunable values to coordinate offsets. |
| `exclusive` | No | Renders design as headline banner in admin UI. |
| `hidesIndicator` | No | Suppresses active indicator when menu is open (if design provides custom anchor marker). |

### `design.js`

Compiled JavaScript bundle containing the React UI components. To optimize bundle size and prevent runtime conflicts, shared dependencies (React runtime, option icons, and motion utilities) are externalized and provided by the host at runtime via `window.OsmTargetHost`.

The bundle is fetched at runtime from `designs/<id>/design.js?v=<version>`. The version query string acts as a cache buster for the Chromium Embedded Framework (CEF).

---

## The Design SDK

Design packs compile against `@host`, exported globally as `window.OsmTargetHost`. It includes:
- React hooks (`useState`, `useEffect`, `useRef`, `useMemo`, `useCallback`, `useLayoutEffect`, `Fragment`).
- Icon components and resolvers (`OptionIcon`, `resolveIcon`).
- Shared geometries and glyphs (`IndicatorShape`, `CursorShape`, `LockGlyph`, `ChevronGlyph`).
- Typed configuration readers (`readNumber`, `readString`, `readBool`).
- Motion and timing helpers (`amp`, `duration`, `gate`, `intensity`, `EASE`).
- Typography and label helpers (`labelLines`, `clampLines`, `labelType`, `disabledStyle`, `gatedLabel`, `showsLock`).

A design module provides three pure, prop-driven view components:

```typescript
interface DesignModule {
  id: string
  sdk: number
  Menu: ComponentType<MenuViewProps>
  Indicator: ComponentType<IndicatorViewProps>
  Cursor: ComponentType<CursorViewProps>
  fonts?: DesignFont[]
}
```

Design components are stateless relative to Lua communication; they receive data, focus, and tunables via props and render view states accordingly.

### Menu shapes (`mode`)

`MenuViewProps.mode` (`'list' | 'collapsed' | 'direct'`, added after SDK 1's
initial publish) tells `Menu` which of three shapes the current option list
calls for, alongside the always-present `options`/`focus`:

- `'list'` (or the field absent entirely) - the original scrolling rail. A
  design built before this field existed only ever receives this shape in
  practice and can ignore `mode` altogether; it is purely additive and does
  not change the SDK version.
- `'collapsed'` - the resolved list is a single option that itself opens a
  submenu (e.g. a "Fridge" entry). `collapseLabel` carries that option's own
  label to print. The host still drives focus/confirm on the single option
  normally - confirming it is what swaps the payload to `'list'` for the
  submenu underneath - so a design that ignores `collapsed` and always
  renders its `'list'` layout will still work, just without the dedicated
  single-row prompt.
- `'direct'` - 1-2 options meant to be shown at once, each independently
  pressable, rather than scrolled through. Each option in this mode carries
  its own `TargetOption.directKey` (a live binding label, resolved the same
  way as `InputPrompts.confirm`) instead of sharing the one focus cursor.

The rail's own implementation
(`designs/rail/index.tsx`) is the reference for reading both fields.

### Dynamic Anchor Rules (`anchorRule`)

To keep world-space sprite offsets in Lua synchronized with CSS layout offsets in DUI, designs with variable opening directions declare anchor rules in data:

```lua
anchor = { x = 0.34, y = 0.0 },
anchorRule = {
  key = 'arcSide',
  values = {
    right = { x = 0.34, y = 0.0 },
    left = { x = -0.34, y = 0.0 },
    up = { x = 0.0, y = -0.34 },
  },
},
```

### SDK Versioning

| SDK Version | osm-target Release | Notes |
|---|---|---|
| `1` | 1.0.0+ | Initial published contract. |

The SDK version increments on breaking changes to host exports or interface definitions.

---

## Packaging and Distribution

See [Development Guide](./development.md#adding-a-new-design) for authoring workflows.

```bash
cd ui
npm run build:design -- <id>   # Compiles to designs/<id>/
npm run verify                 # Validates pack against SDK contract
npm run pack -- <id>           # Packages dist/packs/osm-target-<id>-v<version>.zip
npm run pack:public            # Builds the public distribution
```

The resulting zip archive contains `designs/<id>/` along with a `README.md` guide for straightforward installation.
