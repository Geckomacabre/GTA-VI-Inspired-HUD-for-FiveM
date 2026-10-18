<div align="center">

# vice_hud

**A GTA VI–styled HUD for Qbox.**

Status bars, wanted stars, weapon and ammo, money, zone bar, a vehicle panel
with real manufacturer badges, honor standing, action prompts, directional
police glow and exhaustion effects — with a full in-game layout editor.

![version](https://img.shields.io/badge/version-2.2.0-2f81f7?style=flat-square)
![framework](https://img.shields.io/badge/framework-Qbox-8957e5?style=flat-square)
![dependency](https://img.shields.io/badge/requires-ox__lib-3fb950?style=flat-square)
![licence](https://img.shields.io/badge/licence-CC%20BY--NC--SA%204.0-fa7970?style=flat-square)
![build](https://img.shields.io/badge/build-none-6e7681?style=flat-square)
![tests](https://img.shields.io/badge/tests-624%20passing-3fb950?style=flat-square)

</div>

---

## The interact menu is NUI-based

Between 2.0.0 and 2.2.0 the interact menu (used for things like vehicle slim
jim/lockpick choices) briefly ran through
[ScaleformUI](https://github.com/manups4e/ScaleformUI) instead of NUI, for
sharper native vector graphics with no CEF overhead. That's been reverted:
ScaleformUI holds several scaleform handles for the entire client lifetime,
which caused loading contention with the rest of the HUD's own scaleforms.
The interact menu is back on the original NUI panel (`html/index.html`'s
`#interact`, `html/app.js`'s `onInteract`/`moveInteractSel`/`confirmInteract`/
`closeInteract`), and the resource no longer vendors or depends on
ScaleformUI at all.

## Why this one

**No build step.** No bundler, no framework, no `dist/`. What is on disk is what
runs, so a stale build can never ship and any change is one restart away.

**Everything is tunable in game.** `/movehud` is a real editor — pick a piece on
the left, tune it on the right, drag the panel out of your way, save. It reaches
elements in *other* resources too, and it can publish one layout to the whole
server.

**It explains itself.** Every non-obvious decision has the reasoning written
next to it, in the file where someone would go looking. See
[`docs/INTERNALS.md`](docs/INTERNALS.md).

---

## Features

### The vehicle panel

Gets in, announces the car, then collapses to just the readings.

```
on entering                          for the rest of the drive
+--------------------------------+
|            TRUFFADE            |
|             THRAX              |   ->      (o)  (o)  (o)
+--------------------------------+           no plate, just the gauges
|         (o)  (o)  (o)          |
+--------------------------------+
```

- **51 real manufacturer badges**, stamped into the plate behind the names.
  Rockstar's own marks, normalised to one visual weight *and* one visual size
  (`tools/normalize_logos.py`), keyed off the make the game reports — accents,
  truncated spawn tokens and all.
- **Gauge rings** on engine and fuel that fill to the actual reading, so the
  strip answers *how much* rather than only *is it bad yet*.
- **The icons are about change.** On the name plate you see everything the
  car has, lit if the engine is running and dim if it is switched off. After
  that an icon lights only when its reading changes (fuel dropping a step or
  being topped up, the engine taking a knock, nitrous being used), drops back
  to dim a few seconds after the last change, and the whole row goes away
  once nothing has changed for a while. Lit means "this just moved", not
  "this is bad"; a healthy car that is just driving shows no icons at all. The third pip is a tracker that follows the
  player's wanted state automatically (police have eyes on you: red, still
  hunting: amber, no stars: hidden), and stays hidden the rest of the time.
  Other resources can drive it directly too, with `exports.vice_hud:
  SetVehicleTracker` (clear, searching, spotted), for anything with nothing
  to do with wanted stars. Door lock status lives in qbx_vehiclekeys now, not
  here.
- **A nitrous pip, only on cars that have nitrous.** A fourth disc carrying
  the reference's mark — a wide chevron over a small one — whose ring is the
  tank: it appears when you are driving a car with a kit, drains while you
  boost, goes grey while locked out after running dry and fills back up as
  the tank does. The ring is the only thing that moves. On a car with a kit
  the collapsed row is the reference's row, engine and fuel sitting dim beside
  it; a car with no kit never draws any of it. vice_hud does not run the
  nitrous itself — it reads a state bag (`Config.NitrousStateBag`,
  `customs:nitrous` by default) that whichever resource owns the nitrous
  writes, or takes it from `exports.vice_hud:SetVehicleNitrous`.
- **"Hold [key] to activate nitrous."** The one-line tip from the reference,
  top left, shown once when a kit has just been fitted to the car you are
  sitting in, with the player's live bind in the key cap.
- **A parked car goes monochrome.** Green, amber and red on a car nothing is
  burning fuel in is just noise.

### The rest

| | |
| --- | --- |
| **Status bars** | Health, armour, stamina. Auto-hide at full, with an anti-flicker hold |
| **Minimap** | Rounded corner mask with 14 baked radii, positioned and resized from the editor |
| **Turn-by-turn** | A nav bar above the map while a waypoint is set, from the game's *own* GPS route — so it never disagrees with the line on the minimap. Appears near a junction and gets out of the way otherwise |
| **Wanted** | Star row, plus the "cops are searching for you" notice and its tells |
| **Money** | Cash and bank, in GTA's own Pricedown |
| **Honor** | A standing panel and a separate centre-screen change indicator |
| **Police glow** | Directional edge lighting driven by real siren bearing and distance. Three modes, with a live editor |
| **Exhaustion** | A vignette that breathes in as stamina empties |
| **Skills** | Eight skills that write straight into the character's stats, so levelling changes how the game plays |
| **Prompts** | `ShowActionPrompt` for other resources, auto-cleaned if the caller crashes |

---

## Requirements

| | |
| --- | --- |
| **Required** | [`ox_lib`](https://github.com/overextended/ox_lib) |
| **Required** | [`oxmysql`](https://github.com/overextended/oxmysql) — targeting keeps its `/targetadmin` settings in the database |
| **Optional** | `ox_inventory` — weapon icons, omitted cleanly if absent |
| **Optional** | `qbx_core` — the money readout, skill XP persistence, and honor (built in, see below) |
| **Optional** | `speedlimits`, `zseatbelt` — positioned by the editor's *Other resources* rows |

Nothing optional is a hard failure: each is probed with `GetResourceState` and
the HUD simply leaves that piece out.

## Installation

```bash
# 1. drop the vice_hud folder into your resources/
# 2. in server.cfg, after ox_lib:
ensure vice_hud
```

> [!IMPORTANT]
> Adding new files to a running server needs `refresh` **before** `ensure`. A
> FiveM server only rescans a resource folder on `refresh` — `restart` re-runs
> the scripts but keeps serving the file list from the last scan, so new files
> 404 while everything else looks fine.

---

## The editor

```
/movehud
```

| Key | |
| --- | --- |
| <kbd>←</kbd><kbd>↑</kbd><kbd>↓</kbd><kbd>→</kbd> | move |
| <kbd>Ctrl</kbd> + arrows | resize |
| <kbd>Tab</kbd> | next piece |
| <kbd>[</kbd> <kbd>]</kbd> | pick a setting |
| <kbd>−</kbd> <kbd>+</kbd> | change it |
| <kbd>Shift</kbd> | bigger steps |
| <kbd>Space</kbd> | hold to see through the panel |
| <kbd>Enter</kbd> / <kbd>Esc</kbd> | save / cancel |

Click any value to type an exact number. Twenty elements, each with position,
size, opacity, font, weight, letter spacing, alignment, smoothing, corner radius
and child spacing — every one writing a single CSS custom property, with the
shipped value as the `var()` fallback so an untouched setting renders exactly as
designed.

> [!TIP]
> Run `/hudexport` **before** any restyle. Offsets are nudges away from a
> default, so changing a default silently invalidates every saved one.

Happy with it? `/hudpublish` makes your layout the server default for everyone
(gated behind an ace).

---

## API

```lua
exports.vice_hud:ShowActionPrompt(id, label, key, opts)
-- key: a string (decorative glyph only) or a control id (number, required for hold)
-- opts (optional): { hold = durationMs, onHeld = function() ... end }
exports.vice_hud:HideActionPrompt(id)

exports.vice_hud:OpenInteractMenu(options, selected, token)
-- options: array of { label, badges: {'health'|'stamina'|'focus', ...}, selected }
-- selected (optional, 0-based): starting row; token (optional): opaque
-- value echoed back on the events below, so a caller can tell its own menu's
-- events apart from another caller's -- see client_overlays.lua's comment.
-- Fires vice_hud:interactSelect(index, token) / vice_hud:interactClose(token)
exports.vice_hud:CloseInteractMenu()

exports.vice_hud:ShowHonorToast(mugshot, honor, emoji, reason, broken, severity)
exports.vice_hud:ShowHonorDeed(delta, severity, broken)  -- centre +/- indicator only
exports.vice_hud:ShowHonorChange(delta, mugshot, severity)
exports.vice_hud:SetHonorStanding(honor, broken)   -- seeds the value, draws nothing

exports.vice_hud:ReportWantedTellSighting(id, source)
-- Something of yours has SEEN the player. One shot, nothing to turn off: the
-- tell stays lit until the police lose them. See "The camera tell" below.
exports.vice_hud:SetWantedTellOverride(id, on, source)
-- The continuous version, for a source that can genuinely track visibility.
-- The tell is lit while ANY source claims it, so a speed camera and a CCTV
-- network can both watch you without either switching the other off.
exports.vice_hud:ClearWantedTellOverrides(source)
-- Drop every claim and sighting a source holds, for a resource going down
-- while still holding one; otherwise the tell stays lit with nobody left to
-- clear it.

exports.vice_hud:SetHudVisible(visible)
exports.vice_hud:SetHudOffsetX(pixels)
exports.vice_hud:GetHudOffset(element)             -- returns x, y
exports.vice_hud:GetMinimapOnFoot()                -- /hudminimap's choice: true = the map on foot too
exports.vice_hud:SetMinimapOnFoot(state)           -- set it (saved, as /hudminimap does)

exports.vice_hud:AddSkillXp(id, amount)
exports.vice_hud:GetSkill(id)                      -- { id, xp, level, into, need, frac }

exports.vice_hud:SetVehicleTracker(state)          -- 'clear' | 'searching' | 'spotted' | nil
exports.vice_hud:SetVehicleNitrous(state)          -- { installed, level, active, ready } | nil
exports.vice_hud:ShowNitrousHint(opts)             -- { command, key, duration } | nil
exports.vice_hud:HideNitrousHint()

exports.vice_hud:SetLapTimer(data)                 -- the race HUD; see below
```

### Buttons: controller, keyboard and mouse

Every button the HUD draws (action prompts, world prompts, the nitrous tip) is
the one the player would actually press, on whichever device they touched
last. Pick up the controller and the prompts become its buttons; touch the
keyboard and they become key caps and the mouse.

| | |
| --- | --- |
| `Config.PadGlyphs = 'xbox'` | A B X Y, LB RB LT RT, Menu / View. The default. |
| `Config.PadGlyphs = 'playstation'` | cross circle square triangle, L1 R1 L2 R2, Options / touchpad |
| `/hudpad xbox` / `/hudpad playstation` | a player's own choice, remembered for them; it wins over the config |

A world prompt option can carry `more = true` (three dots on a disc between
the button and the name: it opens a list) or `dot = true` / `'#rrggbb'` (a
coloured dot there). `ShowWorldActions(options, coords, opts)` takes
`{ compact = false }` to keep the name at any distance, `{ centred = true }` to
put the button on the point itself, and `{ id = 'my_resource' }` so that
`HideWorldActions('my_resource')` only takes down a prompt that is still that
resource's. `SetWorldActionsCoords(coords, id)` moves a prompt that is up.
The merged targeting's walk-up prompts (`Config.Proximity`) are drawn with it.
It is drawn at 70% of the corner prompts' size: `--wa-scale` on
`#world-actions` in `html/style.css` (1 is the same size as the corner ones).

`ShowActionPrompt` and `ShowWorldActions` take a control id (or an ox_lib
keybind's `.hash`) as before and need nothing new: the button is resolved from
the live bind by `client_glyphs.lua`. A prompt with `opts.hold` gets a ring
round its button that fills as it is held. The targeting rail uses the same
Xbox / PlayStation setting, so the two cannot disagree.

Not checked in game yet: the mapping from the game's button icon numbers to
buttons comes from the FiveM docs' instructional-buttons table, whose D-pad
left / right and stick entries are the ones most worth a look on a real pad.

### The nitrous pip

The pip needs nothing called on it if your nitrous resource writes its state
to the local player's state bag — that is the default path, and it means the
two resources never depend on each other or on load order:

```lua
-- in the resource that owns the nitrous, client side
LocalPlayer.state:set('customs:nitrous', {
    installed = true,       -- driving a car with a kit; false (or nil) hides the pip
    level     = 0.62,       -- tank fill, 0.0 .. 1.0 -- this is the ring
    active    = false,      -- boosting right now
    ready     = true,       -- false while locked out after running dry; optional
    command   = '+nitrous', -- optional: your RegisterKeyMapping command, for the tip
}, false)
```

The key is `Config.NitrousStateBag`. Extra fields are ignored, the level is
clamped, and the pip disappears the moment `installed` goes false, so leaving
the car is just another write. A resource that would rather push can call
`SetVehicleNitrous` with the same table instead; that takes the pip over
until it is called with `nil`, which hands it back to the state bag.

The **tip** shows by itself when the reading goes from "no kit" to "kit"
while the player is already sitting in the car — a kit being fitted — once
per car per session, for `Config.NitrousHintMs`. `command` puts the player's
live bind for that key mapping in the key cap; `key` takes a control id or a
ready-made label instead. `ShowNitrousHint` shows it on demand, for a resource
that knows better when a player needs telling. `/hudnitrous` previews it.

### The race HUD

Bottom right, as in the reference: a first row, the chequered plate with your
position in the field, and the clock. The first row is `PROGRESS` and a
percentage for a point to point, and `LAP` with the count on a chip (`2/2`)
for a race that has laps: one or the other, as the reference draws them.

```lua
exports.vice_hud:SetLapTimer({
    position  = 1,  racers = 6,    -- "1 / 6" on the plate
    progress  = 0.30,              -- 0.0 .. 1.0 along the route
    lap = 1, laps = 1,             -- laps > 1 swaps PROGRESS for "LAP 1/2"
    cp  = 5, cpTotal = 16,         -- checkpoints this lap / per lap
    elapsedMs = 30390, running = true,
})
exports.vice_hud:SetLapTimer({ show = false })
```

Only the clock is required. With no `position` the plate shows the checkpoint
count; with no `progress` the percentage is worked out from the checkpoints.
`elapsedMs` is a snapshot — push on events and the page runs the clock between
them. While the block is up, action prompts and the honor toast move above it
rather than sit underneath. `/hudlaptimer` previews it.

The rest of a race is four more calls, each held on screen for as long as
the reference holds it and cut in and out with no fade, as it is there:

```lua
-- before the start: small line, the race's name, small line (1.9 s)
exports.vice_hud:ShowRaceTitle({
    series = "HIT 'N' RUN VC", name = 'SALTON TO WANING SANDS', type = 'GROUP RACE',
})

-- 3, 2, 1, go in Pricedown: a digit a second for 0.3 s each, then "go" for 1.1 s
exports.vice_hud:ShowRaceCountdown()              -- the whole run from 3, timed by the page
exports.vice_hud:ShowRaceCountdown({ from = 5 })
exports.vice_hud:ShowRaceCountdown(3)             -- or one beat at a time: 3, 2, 1, 'go'
exports.vice_hud:ShowRaceCountdown(false)         -- stop and clear

-- as the last lap starts: FINAL LAP over the lap just finished (3.0 s)
exports.vice_hud:ShowRaceBanner({ text = 'FINAL LAP', timeMs = 89290 })

-- at the finish: placing over the time to the millisecond (2.0 s)
exports.vice_hud:ShowRaceResult({ position = 1, timeMs = 88893 })   -- "1ST" / "01:28.893"
exports.vice_hud:ShowRaceResult({ label = 'DNF' })
```

`duration` (ms) on the title, the banner and the result overrides how long
they stay; `0` leaves one up until the same export is called with `nil`.
`/hudrace` plays the whole sequence, as a two-lap race.

Prompts are cleaned up automatically when the resource that registered them
stops, so a crashed script cannot strand one on screen — give ids the
`yourresource:something` form for that to work.

### Screen text and overlays

Each of these is one export, empty until it is called, and measured off the
reference. Text takes two marks: `**bold**` for a key word and `{braces}` for
the thing the line is about, which is drawn pink. Durations are in ms; where
one is optional, `nil` is the element's own default and `0` is "until hidden".

| Export | What it draws |
| --- | --- |
| `ShowSubtitle(text, ms)` | one or two lines of speech, bottom centre (4 s) |
| `ShowObjective(text, ms)` | what to do next, under the subtitle: `'Return to {Lucia}'` (until hidden) |
| `ShowHelpText(text, ms, { tells = {...} })` | the help box, top left (7 s) |
| `ShowFeed(text, { icon, duration })` | a line in the feed on the right: `'Crime reported'` (3.5 s) |
| `ShowTitleCard(text, style, ms)` | `'center'` (PROLOGUE), `'stack'` (one word a line), `'location'` (a place name) |
| `SetBinocularOverlay(on, { label, key })` | the lens mask; see `resources/vi_binoculars` for the binoculars themselves |
| `ShowShopItem(data)` / `HideShopItem()` | store, category, price, item, variant, swatches, and why it cannot be bought; `strip = true` (with `counter`, `more`, `progress`, `status`) turns the swatches into a row of item pictures, as GTA VI's barber shows its hairstyles |
| `ShowVehicleStats(data)` / `HideVehicleStats()` | make over model, rated bars, the two ratings |
| `SetCinematicFx(on, { strength, bars, pulse })` | the Focus effect in black with bars; stays up while the HUD is hidden (the crash cam uses it) |

Passing `nil` / `false` as the text hides a text element. `ShowActionPrompt`
takes `opts.off = true` to show a prompt greyed (there, but not usable right
now), and while a shop panel is up the prompts lie in a row.

WASTED and BUSTED are not here: they are `resources/vi_wasted`.

`/hudtext`, `/hudtitle [center|stack|location]`, `/hudshop` and `/hudvehstats`
show samples.

### The top-right corner

Wanted stars, tells, ammo, the weapon and money were re-measured against the
clips where all of them are up at once, and those sizes are now the base
styles; the shipped layout no longer scales that corner.

### The camera tell

Five of the six wanted tells are worked out here. The sixth, `camera`, cannot
be: nothing in this resource knows whether something is filming you, so it
waits to be told. Any resource with cameras in the world can light it, and
more than one can do so at once.

```lua
exports.vice_hud:ReportWantedTellSighting('camera', 'your_resource')
```

That is the whole integration. A sighting **latches**, so you do not report
when the player leaves the camera's view: the police do not forget the photo
when someone drives out of a junction, so the tell stays up until the wanted
level drops back to zero. Report it once, when your camera sees them.

Two details worth knowing:

- A sighting taken while the player is **not** wanted is discarded on the next
  poll. Driving past a camera legally should not light a tell on an unrelated
  crime an hour later.
- Add `exports.vice_hud:ClearWantedTellOverrides('your_resource')` to your
  `onResourceStop`. Otherwise a sighting outlives the resource that reported
  it and burns for the rest of the pursuit with nobody left to clear it.

Use `SetWantedTellOverride` instead if your cameras can genuinely track
continuous visibility, so you can turn the claim back off when they lose
sight. Both compose: the tell is lit while any source claims it, so a speed
camera network and a CCTV script never switch each other off.

The speed cameras in
[streetkings](https://github.com/streetkings-fivem/streetkings) are wired this
way on the server this was built for. That resource is not bundled here, so
the camera side is a single call in its own speed camera module rather than
anything shipped in this repo.

---

## Commands

<details>
<summary><b>Layout</b></summary>

| | |
| --- | --- |
| `/movehud` | The editor — reach for this first |
| `/hudmove <element> <dx> <dy>` | The same by hand. `/hudmove list` prints the elements |
| `/hudreset` | Back to the shipped layout |
| `/hudexport` · `/hudimport <json>` | Dump / restore the whole tuned HUD |
| `/hudpublish` · `/hudunpublish` | Make your layout the server default |
| `/hudoffset <px>` · `/hudtheme` | Global nudge, theme |

</details>

<details>
<summary><b>Minimap</b></summary>

| | |
| --- | --- |
| `/mapinfo` | Prints every value deciding the map's size and shape, plus a block to paste into `config.lua` |
| `/mapmove` · `/mapreset` · `/mapvalues` | Position, restore, dump |
| `/hudmask` · `/hudmaskmode` · `/hudmaskoff` | The rounded corner mask |
| `/hudrects` · `/hudmatch` · `/hudcross` | Draw the engine's own component rects, and line them up |
| `/hudminimap` | Show the map on foot |
| `/hudmap3d` | The drawn minimap or the game's radar, per player |

</details>

<details>
<summary><b>Diagnostics</b></summary>

| | |
| --- | --- |
| `/hudtest` | Push known-good sample data and print the live game state |
| `/hudbrand [make]` | One manufacturer badge for 20s, or walk all 51 |
| `/hudlogos` | Why is there no badge? Names the actual fault |
| `/hudpolice` · `/hudstamina` · `/hudfatigue` | Effect previews |
| `/skills` · `/skillinfo` · `/setskill` · `/skillxp` | The skills panel and its levers |

</details>

---

## Development

No build. Open `html/index.html` in a browser — `app.js` detects it is outside
FiveM and fills itself with representative data.

```bash
npm i jsdom fengari      # test deps only, never shipped

node html/editor.test.js     # the /movehud editor
node html/makes.test.js      # manufacturer badges, gauges, panel states
node html/mapchrome.test.js  # frame / badge / compass follow the map
node html/worldactions.test.js # world-action icons follow the live device
node html/healthreveal.test.js  # health row reveals on change, not on "not full"
node tools/aspect.test.js    # per-display map profiles
node tools/needs.test.js     # hunger / thirst
node tools/notify.test.js    # ox_lib notification offsets
node tools/oxygen.test.js    # the dive model
node tools/radius.test.js    # minimap mask radii
node tools/skills.test.js    # the XP curve
node tools/split.test.js     # every client chunk loads, and stays under Lua's 200-local cap
node tools/navfoot.test.js   # turn-by-turn hides on foot
node tools/radarchrome.test.js # setRadar reports transitions, not ticks
node tools/radarsurvives.test.js # a broken status tick cannot delete the minimap
node tools/onfoot.test.js    # hide-the-map-on-foot: toggle, KVP, and conflicts
node tools/worldactions.test.js # Slim Jim/Smash Window glyph resolves from the real bind
node tools/wheelheld.test.js  # weapon wheel detection covers both enabled and disabled control
node tools/stamina.test.js   # the fatigue model
node tools/waypoint.test.js  # waypoint route colour (one line, not two)
node tools/vehpanel.test.js  # the vehicle panel
```

The Lua suites run the shipped client files themselves through
[fengari](https://fengari.io), so
they test the shipped code rather than a re-implementation of it.

### Regenerating the manufacturer badges

```bash
pip install pillow
python tools/fetch_logos.py      # downloads them, evens out how DARK they are
python tools/normalize_logos.py  # evens out how BIG they are  <- do not skip
python tools/make_makes.py       # writes html/makes.js from what is there
```

The two normalisation passes fix different problems and both are needed.
`fetch_logos.py` flattens each mark to one ink weight, then crops it to its own
edges — which leaves fifty-one wildly different *shapes*, so a single CSS rule
sizes a wide slab and a narrow upright completely differently (the ink area ran
**9.9x** between the largest and smallest mark). `normalize_logos.py` scales
each one to a constant ink area and centres it on one shared square canvas,
which is what lets the stylesheet size all fifty-one with one rule. It keeps the
untouched originals in `tools/logos_raw/` and always re-reads from there, so it
is safe to re-run and `CANVAS` can be retuned freely.

Marks come from the [GTA Wiki](https://gta.fandom.com/wiki/Vehicle_Manufacturers).
**A badge never spells the manufacturer's name** — the panel already prints it
directly above — so marques whose only mark is their own name set as type ship
no badge and render the plain plate. Drop a better one in
`tools/logos_local/<KEY>.png` to override.

`tools/` is not in `fxmanifest`'s `files{}`, so none of it reaches clients.

---

## Configuration

`config.lua`, with the reasoning beside each value. The ones most worth knowing:

| | |
| --- | --- |
| `Config.DefaultLayout` | The shipped layout. A saved layout replaces it wholesale rather than merging |
| `Config.Minimap` · `Config.MinimapComponent` | The map's rect and the engine component values behind it |
| `Config.Nav` | Turn-by-turn: how close a junction has to be before the bar appears, and the hysteresis that stops it flickering |
| `Config.Skills` | The eight skills, their curves and what each one feeds into |
| `Config.PoliceLights` | Mode, brightness, flash, lamp shape, detection range |
| `Config.Exhaustion` · `Config.Stamina` | The fatigue model |
| `Config.HiddenHudComponents` | Which native components to suppress — only the ones actually replaced |

---

## Documentation

**[`docs/INTERNALS.md`](docs/INTERNALS.md)** — the long version. Why the minimap
is built the way it is, why the player blip drifts when you resize the map, how
the honor push works, what the exhaustion model actually models, and the traps
that already bit once. Read it before changing the minimap code.

## Assets and fonts

**Helvetica Neue is not bundled.** It is a commercial Monotype/Linotype face and
redistributing it here is not ours to do, so the four cuts are resolved with
`local()` from the player's own machine instead. The chain falls back
Helvetica Neue → Helvetica → **Arial** → Liberation Sans; Arial is metrically
compatible with Helvetica, so line lengths and the shrink-to-fit measurements
hold either way. The one visible difference is the *Thin* cut, which Arial has
no equivalent for and which therefore renders as regular on machines without
Helvetica Neue — that affects the nav bar and the wanted box, both tuned to
thin in the shipped layout. If you hold a licence, drop the `.otf` files into
`html/fonts/` and restore the `url()` sources in `style.css`; `fxmanifest`
already globs `html/fonts/*.otf`.

**Rockstar-derived assets** — the GTA Art Deco and Pricedown faces, and the 51
manufacturer marks (via the [GTA Wiki](https://gta.fandom.com/wiki/Vehicle_Manufacturers))
— ship as-is, as is normal for FiveM resources. They remain Rockstar's
property; this project claims no rights over them and the licence below covers
only the code.

**`html/fonts/PlusJakartaSans-Variable.ttf`** is Plus Jakarta Sans, licensed
under the [SIL Open Font License 1.1](html/fonts/PlusJakartaSans-OFL.txt) —
free to bundle and redistribute. It's a stand-in for whatever GTA VI's own
scrollable item-select lists actually set (see the comment above its
`@font-face` rule in `html/style.css`), and the same face
[osm-target](https://github.com/Geckomacabre/osm-target) uses for its own UI
text. An earlier version of this file used Belle Sans Extra Condensed Bold,
a commercial font with no redistributable tier; swapped out for that reason.

## Merged in: targeting and honor

Two resources that used to sit beside this one are part of it now, so there is
one HUD, one targeting system and one set of prompts instead of three
resources drawing over each other.

| Folder | Was | What it is |
| --- | --- | --- |
| `target/` | `osm-target` | the targeting engine, its *Context Rail* list drawn in the world, `/targetadmin`, `/targetui`, and the `ox_target` / `qb-target` / `qtarget` APIs |
| `honor/` | `qbx_honor` | the honor stat, its hooks and exports, and the greet / antagonise options on peds |

`vice_hud` `provide`s `osm-target`, `ox_target`, `qb-target`, `qtarget` and
`qbx_honor`, and none of the five may be installed as a resource of its own
beside it. What that covers, and what it does not:

| A script that does this | Still works? |
| --- | --- |
| `dependency 'ox_target'` (or any of the five) in its manifest | Yes, through `provide` |
| `exports.ox_target:addBoxZone(...)`, `exports['qb-target']:...`, `exports.qbx_honor:AddHonor(...)` | Yes. `provide` does not alias exports, so the code registers each one under the old name itself (`ExportAs` in `target/client/api/native.lua`, `HonorExport` in `honor/alias.lua`) |
| `GetResourceState('ox_target') == 'started'` (or `'qbx_honor'`, `'osm-target'`) | **No.** `provide` does not make a name report as started |

For the last row there are two ways out. The resources in this bundle that
tested a name that way (`gk_basketball`, `qbx_vehiclekeys`) now also accept
`vice_hud`. For anything else, either change the test the same way, or run a
manifest-only resource of that name beside `vice_hud` (a folder with nothing
but an `fxmanifest.lua`) and delete the matching `provide` line from this
resource's manifest, so the name has one claimant.

What each kind of interaction is drawn by, so nothing is offered twice:

| Interaction | Drawn by |
| --- | --- |
| Anything registered through a target API | the rail (`target/`) |
| Slim Jim / Smash Window on a locked car | the two-button world prompt (`ShowWorldActions`); `qbx_vehiclekeys` leaves its target option unregistered while this resource runs |
| A single contextual action | an action prompt (`ShowActionPrompt`) |
| `OpenInteractMenu` | the HUD's own list. Nothing in this bundle calls it; it is kept for scripts that do |

All three parts share one `Config` table: `config.lua`, then
`target/config.lua`, then `honor/config.lua`. The only name they had in common
was the debug switch, which is now `Config.Debug` (HUD), `Config.TargetDebug`
and `Config.HonorDebug`.

What was changed in `target/` to load it from here, and nothing else:

- `config.lua` adds to the shared `Config` instead of replacing it, the debug
  switch is renamed as above, and the GitHub version check is off (it would
  compare this resource's version with osm-target's releases);
- the in-world surfaces load their page from `target/html/`, and the design
  packs are looked for under `target/designs/`;
- its screen-space page (admin panel, preferences, sounds) is a frame inside
  this resource's page, since a resource has one `ui_page`; `client/ui/nui.lua`
  sends its messages through the HUD page, and `html/index.html` takes the
  resource name from the frame's own address when the game does not supply it;
- its controller-brand preference reads and writes the HUD's setting;
- its exports are also answered under the name `osm-target`;
- `use_experimental_fxv2_oal` is not carried over, as it would apply to the
  whole HUD.

Its original manifest is kept as `target/fxmanifest.lua.original`, and
honor's as `honor/fxmanifest.lua.original`. `tools/split.test.js` loads every
shared and client script in manifest order, which is the check that the three
parts still load together.

None of this has been run on a live server from this repository yet.

## Something in your hands that is not a weapon

The weapon icon's place in the top-right corner also shows what you are
holding when it is not a weapon. `Config.HeldIcons` lists player state bag
keys and the image for each; `gk_basketball` sets `bbBall` while you have the
ball, so a basketball shows there, from ox_inventory's own item art like the
weapon icons. A weapon in hand always wins.

```lua
exports.vice_hud:SetHeldIcon('nui://ox_inventory/web/images/basketball.png')   -- or any image
exports.vice_hud:SetHeldIcon(nil)                                              -- clear
```

## The drawn minimap: flat colour, sea and sand, buildings standing

The reference minimap is not GTA V's dark radar. It is the map in flat colour,
seen at a slant, with the sea and the beach in their own colours and the
buildings standing up off the ground. `Config.Map3D` draws that in place of the
engine's radar.

It began as a port of, and the world it draws is that of,
[GTA VI MiniMap (3D Buildings) (Legacy & Enhanced)](https://www.gta5-mods.com/scripts/gtavi-minimap-3d-buildings-legacy-enhanced),
a single-player mod by **loneeps** (Discord `@moddims`), ported to FiveM with
their permission:
its roads, its 3,589 building outlines and their heights, and its survey of
where the map is water and where it is sand. The idea of a minimap drawn this
way, and the week of work that mapped the island for it, are theirs; this is
that map redrawn on the HUD's page so a server can show it. The camera it is
seen through and its colours have since been measured off the reference
footage (see below). Around it everything is still
this HUD's: the frame and where it sits, the player marker measured off the
reference, the route in the HUD's accent colour, the distance figure, the
direction panel, and the game's own blips.

**There is nothing to build.** The map ships with the resource, in
`html/map3d/`: `world.bin` and `ground.png` are the mod's map, converted, and
`blips.png` / `blips.json` are the game's blip pictures. Drop the resource in
and it draws.

They can be rebuilt, if the mod is updated or you want to change how its map
is converted:

```bash
python tools/map3d/build.py --mod "path/to/MiniMap.dll"
python tools/map3d/blips.py --docs path/to/fivem-docs
```

- `build.py` writes `world.bin` and `ground.png` from a copy of the mod.
  Nothing in the mod is run; its map is read out of the file. Needs numpy,
  scipy and Pillow.
- `blips.py` writes the sheet of blip pictures, from a clone of
  [fivem-docs](https://github.com/citizenfx/fivem-docs). Needs numpy and
  Pillow.
- If `world.bin` is ever missing the page says so, one line is printed, and
  the engine's radar carries on. Without the blip sheet every blip is a round
  dot in its own colour.

What to know about it:

- **It is seen through a real camera, the reference's.** The reference's
  minimap is a camera behind and above the player, looking down past them at
  about 27 degrees, and this is that camera: its pitch and lens are read off
  the footage (a rectangular roof gives two vanishing points and so the
  horizon; a helipad's circle, drawn a third as tall as it is wide, agrees).
  A metre ahead of the player is drawn 0.59 of a metre across, buildings
  stand their own height through the same lens, the far end of the map pales
  toward the horizon, and the panel is opaque. `Config.Map3D.view.camera`.
- **The camera rides at your height.** On a roof the city falls away below
  you; under a parachute or in an aircraft it shrinks, and what is on the
  ground directly beneath you slides toward the bottom edge. A wall or roof
  that stands between the camera and you is seen through round your marker;
  a roof you are standing on is not. `Config.Map3D.altitude = false` keeps
  it on the ground. The ground itself is flat: the map has no hills.
- **Its colours are the reference's**, sampled off its opaque panel: pale
  pinkish paving with the roads a shade lighter, a deep teal sea that is
  lighter along the shore, and lavender-slate buildings darker than the
  ground they stand on.
- **It is drawn on the HUD's page, by WebGL.** The mod paints straight onto
  the game's frame from a plugin, which a server cannot give its players, and
  the engine's own radar is a flat picture that cannot stand a building up.
  The geometry is uploaded to the graphics card once. After that a frame is a
  few dozen draw calls over the 256 m squares around the player, and a frame
  is only drawn when the player or the camera moved. A player with it switched
  off downloads none of it.
- **Indoors the engine's radar comes back**, because it has the floor plan and
  the drawn map does not (`engineIndoors`).
- **Blips are read from the game** every two seconds, and the ones riding a
  ped or vehicle are followed in between. A blip that is not short-range stays
  pinned to the edge, as on the radar. Radius and area blips are not drawn:
  the game will not say how big they are.
- **The route** is the game's own GPS line, read back from it, for the
  waypoint and for a blip a script gave a route. The game hands it over with
  kinks in it and a tail behind the player, so it is smoothed, started where
  the player is, and brought in gradually just ahead of the marker.
- **Where a route ends is ringed**: four arcs in the route's colour, as the
  reference marks a destination. In the ring is a plain disc of that colour,
  or, when the waypoint was set on a place, that place's own blip.
- **Wanted, the map says so and nothing else does.** The reference puts no
  police on its minimap. The ground round the player floods one flat colour,
  roads and all: red while the police can see you, blue while they have lost
  sight and are searching, a faded red once they are shaken off but the
  wanted level has not gone. It is driven by the same state the wanted stars
  use (fenix-police's contact model when it is running). The blips the game
  hangs on officers, their cars and helicopters are left off
  (`policeBlips`), and the two search rings are off by default
  (`Config.PoliceSearch`). Police stations are places and stay.
- **Spending stamina sends rings out from your marker**, as the reference's
  does while its player runs: thin and light, a new one from the marker's rim
  every 0.4 s, each growing 2.65 marker radii a second and faded out by 4, so
  two or three are on the map at once. They start with the sprint (or with
  the bar falling, swimming or pedalling flat out) and the last is gone about
  a second after it ends. `Config.Map3D.ripple` has the numbers; `false`
  switches them off. The bolt beside the stamina bar follows the same thing:
  for as long as the bar is going down it flashes red every 0.9 s, red at
  once and faded back to teal a fifth of a second later, as the reference's
  does (`Config.Stamina.boltRedEvery`, `boltRedMs`; `boltRed = 'drain'` holds
  it red steadily instead, `false` leaves it teal).
- **After dark the map is dark**: slate land with the roads standing out of
  it, changing over gradually at dusk and dawn by the game's clock
  (`night`, `nightHours`, `paintNight`).
- The pause map and the big map are the engine's and are untouched.
- **It goes when the game's radar would**: a cutscene, a character switch, a
  faded-out screen, as well as the pause menu and the inventory.
- **Things that stand beside the map can follow it.** `vice_hud:minimap` is
  raised with `true` or `false` each time the minimap comes or goes, and
  `exports.vice_hud:IsMinimapShown()` answers the same at any time: enough
  for a speed-limit sign or a seatbelt light in another resource to hide
  when the map does.
- `/hudmap3d` switches between it and the game's radar for that player.

`Config.Map3D.view` has the zoom, the camera, where the player sits on the panel
and the opacity; `Config.Map3D.paint` the colours.

## The player marker on the minimap

The reference marks the player with a black-ringed disc and a pale arrowhead,
not GTA V's white arrow. The minimap is a scaleform and that arrow is a vector
shape inside it, so the marker is made by swapping the shape in a copy of the
game's own `minimap.gfx`: the game still places it and turns it with you, at
no cost, and it cannot drift from the map the way a marker drawn over it would.

`tools/minimap_marker/build.py` does the swap and checks that nothing else in
the file changed. It needs your game build's `minimap.gfx` and JPEXS Free
Flash Decompiler; the script's own header says where each comes from.

```bash
python tools/minimap_marker/build.py --ffdec path/to/ffdec-cli.jar --in minimap.gfx --out stream/minimap.gfx
```

- The built file is not in this repository: it is the game's own file with
  three shapes changed, and it is different for every game build. Build it
  from yours, and again after changing `sv_enforceGameBuild`.
- Its size is **Player arrow** in the HUD editor's map panel (0 is the game's
  own size).
- Delete `stream/minimap.gfx` to get the stock arrow back. Only one resource
  on a server can stream that file.
- The pause-menu map has its own scaleform and keeps the stock arrow.

## Licence

[CC BY-NC-SA 4.0](LICENSE) — **non-commercial**. You may use, modify and
redistribute this resource, including on a server of your own, but not sell it
or bundle it into anything paid, and a modified version has to carry the same
licence. This matches the repository's own licence and every other resource in
it.

`target/` is the exception. It is a modified fork of osm-target by OsmFX Mods
and stays under the [OsmFX Mods Source-Available License v1.0](target/LICENSE),
with its own README and notices; being loaded by this resource's manifest does
not change that. `honor/` is CC BY-NC-SA 4.0 like the rest and keeps its copy.

> [!NOTE]
> The copyright line in `LICENSE`'s *How to Apply* section is left for you to
> fill in with your own name before publishing.

## Credits

Built for Qbox, on top of [`ox_lib`](https://github.com/overextended/ox_lib).
Minimap geometry follows [`qbx_hud`](https://github.com/Qbox-project/qbx_hud)'s
square-map preset. Manufacturer marks and the GTA typefaces are Rockstar's.

The cash icon and its ring (`html/icons/cash.png`, `html/icons/fill_green.png`),
the health/stamina/focus badges (`html/icons/badge_*.png`), the vehicle
panel's tracker/engine/fuel pip glyphs (traced/masked from the same set's
badge art), and the wanted-tell icon set are from the
[Enhanced OIV GTA 6 Inspired HUD](https://www.gta5-mods.com/misc/enhanced-oiv-gta-6-inspired-hud)
mod on GTA5-Mods.com. The BuckMe bank icon and its ring
(`html/icons/buckme.png`, `html/icons/buckme_ring/`,
`html/icons/fill_purple.png`) are original, made in-house.

The drawn minimap (`Config.Map3D`) began as a port of
[GTA VI MiniMap (3D Buildings) (Legacy & Enhanced)](https://www.gta5-mods.com/scripts/gtavi-minimap-3d-buildings-legacy-enhanced)
by **loneeps** (Discord `@moddims`) on GTA5-Mods.com, and the world it draws
(roads, building outlines and heights, sea and sand) is all that mod's, as is
the idea. What is ours is the WebGL redraw that lets a FiveM server show it,
the camera and colours since measured off the reference, and what sits on top
of it. It is ported with loneeps' permission, given on the one condition that
they are credited, which this is. The converted map ships in `html/map3d/`;
`tools/map3d/build.py` is what made it. The blip pictures beside it are the
game's own, taken from [fivem-docs](https://github.com/citizenfx/fivem-docs).

Thanks to GravityExploitz for BuckMe's satire paragraph and for help with the
BuckMe card design.
