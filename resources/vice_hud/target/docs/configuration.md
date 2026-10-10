# Configuration Guide

Configuration in **osm-target** is divided into static engine settings, server-wide live administration, and client-side accessibility preferences.

---

## Static Configuration (`config.lua`)

`config.lua` defines the core runtime settings, input bindings, default distances, and spatial parameters:

```lua
Config = {}

Config.Locale = 'en'
Config.Framework = 'auto' -- 'auto' | 'qbox' | 'qbcore' | 'esx' | 'ox' | 'standalone'
Config.Debug = false
Config.VersionCheck = true
Config.AcePermission = 'osm_target.admin'

Config.Commands = {
    admin   = 'targetadmin',   -- Server-wide appearance and system panel
    prefs   = 'targetui',      -- Player accessibility preferences
    debug   = 'targetdebug',   -- Toggle in-world diagnostics overlay
    test    = 'targettest',    -- Spawn a test ped with sample options
    explain = 'targetexplain', -- Print resolver verdicts for the current target
    bench   = 'targetbench',   -- Benchmark world anchor calculation paths
}

Config.Input = {
    key = 'LMENU',         -- Default activation key (can be rebound in FiveM keybinds)
    mode = 'hold',         -- 'hold' | 'toggle'
    confirm = 24,          -- INPUT_ATTACK (Left Click)
    cancel = 25,           -- INPUT_AIM (Right Click)
    scrollUp = 241,        -- INPUT_CURSOR_SCROLL_UP
    scrollDown = 242,      -- INPUT_CURSOR_SCROLL_DOWN
}

Config.Interaction = {
    distance = 7.0,        -- Maximum interaction distance in meters
    raycastDistance = 12.0,-- Camera raycast length
    scanInterval = 50,     -- Raycast throttle interval in milliseconds
    snapAngle = 4.0,       -- Degrees: angle threshold to lock target
    releaseAngle = 6.0,    -- Degrees: angle threshold to start releasing target
    releaseTime = 180,     -- Milliseconds to hold beyond releaseAngle before closing
    openTime = 220,        -- Menu open animation duration in milliseconds
    closeTime = 160,       -- Menu close animation duration in milliseconds
}

Config.Indicators = {
    enabled = true,        -- World-space indicator markers
    radius = 5.0,          -- Maximum indicator visibility radius
    cap = 8,               -- Maximum visible indicators simultaneously (up to 24)
    discoveryInterval = 250, -- Discovery pass interval in milliseconds
    scanInterval = 1000,   -- Entity pool rescan interval
    scanSlack = 6.0,       -- Padded boundary radius for pool caching
    nearAngle = 12.0,      -- Angle threshold for "near" indicator visual state
    includeGlobals = false,-- Whether global registrations generate world indicators
}

Config.Options = {
    showDisabled = true,   -- Render ineligible options in a disabled state
    hideUnexplained = true,-- Hide opaque options returning bare false with no reason
    defaultDistance = 7.0, -- Default distance fallback for options without distance
    focusDisabled = true,  -- Allow focusing disabled options to inspect requirements
}
```

### Walk-up prompts (`Config.Proximity`)

No key held. Nothing shows until the player walks up to something; then the
prop, item or zone in reach and in front of them shows what can be done with
it, each option beside the key or pad button that does it, and that key does
it. Walking away takes the prompt down. The targeting key still works as
before and is how everything left out of this is reached.

```lua
Config.Proximity = {
    enabled = true,
    distance = 2.0,       -- Metres before a prompt comes up
    angle = 30.0,         -- Degrees either side of where the camera looks
    peds = false,         -- Peds and players stay behind the targeting key
    vehicles = 'named',   -- 'named' (only Config.Input.directKeyByName), 'all', or false
    inVehicle = false,    -- No prompts while driving
    maxDirect = 1,        -- More options than this: one prompt, with three dots, that opens the list
    keys = { ... },       -- E (Y / Triangle on a pad) first; the rest matter with maxDirect above 1
    blocks = { ... },     -- Game controls switched off while their button is a prompt
}
```

- An option can settle it for itself: `proximity = true` shows it without the
  key whatever it is on (a shop clerk, say), `proximity = false` keeps it
  behind the key.
- One option is a button and its name. More than one, or an option that opens
  a submenu, is a button, three dots and a name; pressing it opens the list on
  that target, which closes on a pick, on cancel, or on walking away. The
  list's name is "Interact" unless one of its options carries
  `targetName = 'Fridge'`.
- Options that each have their own key in `Config.Input.directKeyByName`
  (Slim Jim, Smash Window) always stand side by side, each on its button.
- `dot = true` (or a `'#rrggbb'`) on an option draws a coloured dot before its
  name, for something on sale.
- With `vice_hud` running the prompt is its world prompt
  (`exports.vice_hud:ShowWorldActions`), drawn with the player's own key or pad
  button and redrawn when they change device. Without it the active design
  draws it as a direct prompt.

---

## Targeting Hysteresis Parameters

The interaction engine uses three complementary hysteresis settings to ensure smooth target acquisition and prevent menu flickering:

| Setting | Default | Purpose |
|---|---|---|
| `snapAngle` | `4.0°` | The cone threshold from camera forward vector required to acquire and magnetize a target. |
| `releaseAngle` | `6.0°` | The angle that must be exceeded before release evaluation begins. Enforced to be larger than `snapAngle`. |
| `releaseTime` | `180ms` | Duration the camera must remain outside `releaseAngle` before the menu dissolves. |

---

## In-Game Admin Panel (`/targetadmin`)

Administrators can open the live configuration panel. Access is granted by either the dedicated ACE object in `Config.AcePermission` or the standard per-command ACE:

```cfg
add_ace group.admin osm_target.admin allow
# or, per command
add_ace group.admin command.targetadmin allow
```

The same check guards `/targetdebug`, `/targettest`, and every admin NUI callback (config save, design revert, config import), so a client cannot reach them by firing the events directly.


- **Database Persistence**: Changes are stored in MySQL (`osm_target_config`) with full revision history.
- **Live Synchronization**: Saving immediately broadcasts updates to all connected clients without requiring server or resource restarts.
- **Live Preview Stage**: An interactive preview stage displays the exact UI rendering across normal, gated, long-text, and empty states.
- **Palette Presets**: Shipped starting palettes include *Midnight*, *Porcelain*, *Ember*, *Signal*, and *Frost*.

### Configurable Parameter Groups

| Group | Available Settings |
|---|---|
| **Palette** | Accent color, surface background, surface opacity, primary text, secondary text, disabled color. |
| **Surface** | Corner radius, gradient mode (none/linear/radial), gradient depth, border outline brightness, contact shadow depth. |
| **Typography** | Type scale (80%–130%), label line wrapping (1–3 lines), subtext visibility, font weight, letter case. |
| **Motion** | Motion intensity (0%–150%), animation transition speed (60%–180%). |
| **Parts** | Gated option style (lock badge / dim / strike-through), indicator shape (ring / diamond / bracket / dot), cursor style. |
| **Sound** | Audio pack (signature / soft / mechanical / silent), master volume ceiling. |
| **Scale** | Global interface scale (60%–160%). |
| **Design-Specific** | Design-dependent geometry settings (arc radius, card width, board dimensions, etc.). |

---

## Player Accessibility Preferences (`/targetui`)

Players can customize client-side accessibility options at any time:

- **Interface Scale**: Adjust UI rendering scale (50% to 200%).
- **Sound Volume**: Adjust local interaction sound volume (0% to 100%).
- **Mute Audio**: Toggle all interface sound effects.
- **Reduced Motion**: Disables entrance animations and screen cursor transitions.

Settings are persisted in client KVP storage across sessions.
