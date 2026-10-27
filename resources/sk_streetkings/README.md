# sk_streetkings

One resource covering the car meet, racing, and the StreetKings gameplay systems
ported onto Qbox.

> **Continuing the port?** See [`PORTING.md`](PORTING.md) — the four remaining
> module groups, the conventions to follow, and the gotchas already hit.

Replaces three resources, now in `_Retired/`:

| Retired | Now lives in |
|---|---|
| `[UM]/um_carmeet` (Randolio's `randol_carmeet` + local additions) | `modules/carmeet/` |
| `[Scripts]/sk_racing` | `modules/racing/` |
| `[Scripts]/meet_night` | `modules/meetnight/` |

## Install

1. Run `sql/install.sql`. Creates `sk_profiles`, `sk_activity_scores`,
   `sk_stunt_jumps` and `sk_vehicle_upgrades`.
   - If you previously ran `sk_racing`, also run the optional migration block
     at the bottom of that file to carry XP/levels into `sk_profiles`, then drop
     `sk_race_profiles`.
   - `sk_race_leaderboards` and `sk_race_routes` are unchanged, so existing lap
     times and `/racemaker` routes survive the merge untouched.
2. Nothing to add to `server.cfg` — the folder sits under `[Scripts]`, which is
   already covered by `ensure [Scripts]`.

### Companion resources

Two upstream asset resources sit alongside this one in `[Scripts]`. Both are
optional — delete either folder and this resource degrades rather than breaks.

| Folder | What it gives you | If you delete it |
|---|---|---|
| `streetkings_audio` | StreetKings' own soundset (`sk_soundset`) | `SK.PlaySound()` falls back to stock sounds |
| `streetkings_blips` | Nothing that is still needed — **safe to delete** | No change |

`streetkings_blips` is installed **without** upstream's `stream/minimap.ytd`,
because `um_hud` already owns that filename and it is what draws this server's
custom minimap. Don't add `minimap.ytd` back.

It is now redundant. `Config.Blips` uses purpose-built vanilla sprites (184
`radar_camera`, 488 `radar_stunt`, 84 `radar_rampage`), which need no custom
sheet. Upstream's numbers only made sense against its own sheet — on the stock
sheet 500 is `radar_production_money` and 378 is `radar_team_deathmatch`. The
folder's only remaining effect is restyling blips belonging to other resources
that sit on the same sheet, so deleting it is the tidier option.

When picking a sprite, choose by **name** from
[the FiveM blip reference](https://docs.fivem.net/docs/game-references/blips/)
rather than copying a number from upstream.

## Blips

Every blip this resource places is defined in `Config.Blips` — sprite, colour,
scale, legend category, and whether it is short range. Change one there rather
than hunting through modules.

**Short range is the setting that keeps your minimap readable.** A short-range
blip always shows on the big pause map, but only appears on the minimap once you
are near it, instead of pinning itself to the minimap edge from across the city.
Everything ambient here (speed cameras, stunt jumps, rampages, repair stations,
hangout zones) is short range. The only long-range blips are things you are
actively driving to: race checkpoints, and the NPC challenge finish and rival.

## Layout

```
shared/     config, formatting, game-state enum, route expansion
data/       location + definition tables (no logic)
modules/
  core/     the Qbox/ox_lib compatibility layer everything else builds on
  carmeet/  meet interior, drift scoring, NPC race betting
  racing/   routes, time trials, multiplayer lobbies, leaderboards
  meetnight/scheduled payout-boost window
  nitrous/  NOS
  gearbox/  manual transmission
  tuning/   nitrous purchasing, shown inside um_customs' Performance menu
  stats/    career tracking
  repair/   roadside repair stations
  hangoutzones/ passive/ghost-mode zones
  speedcameras/ fixed cameras that flash and fine you for speeding
  police/   spawned speed traps, radar detector, pursuit (off by default)
  stunts/   ramp-to-ramp jumps, scored on air time, distance and tricks
  rampage/  timed destruction runs from marked start points
  npcchallenge/ burnout next to an AI driver to start a street race
  devtools/ admin freecam + the stunt jump placement tool
```

## The compatibility layer

StreetKings is a standalone gamemode with its own save system, economy, identity
and game-state machine. Rather than port those (they would fight qbx_core),
`modules/core/` re-implements the globals its gameplay modules expect, backed by
what this server already runs:

| StreetKings global | Backed by |
|---|---|
| `SKPlayer` | `qbx_core` — money, citizenid, notify, admin check |
| `SKSaves` | `sk_profiles` table — progression/stats/settings/unlocks only |
| `SKNotify` | `ox_lib` notifications |
| `SKHud` | native draw calls (see below) |
| `SKWaypoint` | native markers + blips, same public API as the DUI original |
| `GameState` / `SKC` | trimmed local state machine, mirrored to the player statebag |
| `SK.*`, `SKInput` | ported verbatim, no framework coupling |

Money, garages, properties and appearance are **not** duplicated — they stay with
`qbx_core`, `qbx_garages`, `sn_properties` and `illenium-appearance`.

## Street races

`data/races.lua` holds the eight street races and is generated by `_tools/race_sim/street_routes.py`. Never hand-edit
it. Each route is a list of street junctions in that script's `PLAN`; the way between them is the shortest drivable path
on the game's own road network, with a checkpoint at every corner and at most 200 m apart on a straight, each at the road
height measured from the collision mesh. Change `PLAN` and regenerate, or add routes in game with `/racemaker`.

With `vice_hud` running, checkpoints are its light-pillar race marker in the player's accent colour, with an objective
line at GO and Rockstar's checkpoint sound. Without it the stock cylinders are drawn.

## Air and offroad races

`data/rockstar_races.lua` holds 5 stunt-plane time trials (Bridge Binge, Vinewood Flyby, Engineered Bridgework, Airport
Flyby, Altitude) and 6 offroad races (Canyon Cliffs, Ridge Run, Valley Trail, Lakeside Splash, Eco Friendly, Mineward
Spiral), generated from Rockstar's own race scripts by `_tools/race_sim/gen_data.py`. Never hand-edit it.

- **Air races** are entered from the Sandy Shores hangar (one blip, one list). The race hands you a stunt plane, already
  in the air on the start line. You fly *through* each gate: how cleanly you fly it moves your clock (perfect ring -1 s,
  knife edge -1.5/-2.5 s, inverted -2/-3 s, a stunt gate done right -4 s, done wrong +1.5 s, a missed gate +5 s), and the
  finish is judged on that adjusted clock against gold / silver / bronze, which pay on top of the normal reward. Solo only.
  The server re-derives every bonus from the plane's position and tilt; the client only reports which gate it thinks it hit.
- **Offroad races** hand you the race's Sanchez or Mesa on the grid, or race in your own vehicle. Multiplayer works with
  your own vehicle.
- **`/racemaker`** now asks for a race type. In air mode gates hang at a height above the ground you aim at (Up/Down),
  each can ask for a stunt (G), and saving takes gold/silver/bronze times, a plane and the ground entry point.
- Pop-up races and NPC challenges never pick an air or offroad route.

Checks: `_tools/race_sim` (`python run_all.py`). Headless only, see its `HANDOFF.md` for what has not been seen in game.

## UI

Menus, dialogs, prompts and toasts all use ox_lib directly, so they inherit the
server's ox_lib theme automatically. No StreetKings NUI is carried over.

The persistent gameplay overlays ox_lib has no widget for (nitrous gauge, gear
indicator, drift score, spectate list, stall prompt) are drawn with natives via
`SKHud`, styled to match ox_lib's dark theme with the server's `#f1e542` accent.
Retheme in one place: `SKHud.Palette` in `modules/core/hud_c.lua`.

**`SKHud` deliberately avoids the bottom-right corner**, which `um_hud` owns.
um_hud renders as NUI and composites above native draws, so anything placed
there would be invisible. Use `SKHud.Anchor` rather than raw coordinates.

## Nitrous

**Nitrous is bought per vehicle, from the mod shop's Performance tab** (`Lenonida_customs`, which
replaced `um_customs` on 2026-10-10 and calls this resource's `GetNitrousShop` / `BuyNitrous` exports).
Prices are Street $10,000, Sport $17,500, Race $25,000 (raised from upstream's $3,500 / $6,500 /
$8,500 so nitrous sits above a turbo in the mod shop) and live in `Config.Nitrous.prices`.

StreetKings sold nitrous from its own 1,518-line tuning shop, which is **not**
ported: `um_customs` already does visual mods, performance mods, colours,
wheels and neon. Nitrous was the one thing it had no concept of, so that is all
that was taken.

Because nitrous is not a native GTA vehicle mod, it cannot ride along in the
`player_vehicles.mods` blob um_customs saves. It gets its own plate-keyed row in
`sk_vehicle_upgrades`. Only vehicles registered in `player_vehicles` can be
upgraded, so nobody spends money on a car that will never persist — relax that
with `Config.Nitrous.requireOwnedVehicle`.

Buying or removing a bottle takes effect immediately; no need to get out and
back in. `Config.Nitrous.defaultTier` (default `nil`) hands every vehicle a free
tier if you would rather not charge at all, and the server can still force a
tier on a player with `sk_streetkings:nitrous:setTier`, which overrides whatever
the car has.

### The um_customs hook

`um_customs` has no exports or extension points, so it carries a small block in
`client/menus/performance.lua`, delimited by:

```lua
-- >>> sk_streetkings hook — BEGIN
-- <<< sk_streetkings hook — END
```

There are two of them: one appends the row, one routes its purchase. All the
logic is in `modules/tuning/`, so **a um_customs update only costs you those two
blocks back** — nothing else. The hook is guarded, so if `sk_streetkings` is
stopped, um_customs behaves exactly as shipped.

## Config

`shared/config.lua` has a `Config.Modules` block — every system can be switched
off independently.

`Config.Modules.police` defaults to **false**: it spawns its own pursuit AI and
drives GTA's wanted-level system, which overlaps the police RP stack already on
this server (`ps-dispatch`, `fenix-police`, `lvc`, `wk_wars2x`) — officers
would be policing two parallel sets of cops. Turn it on deliberately, not by
accident. Its tuning lives in `Config.Police`; the bust is a fine and a fade,
not an arrest, since arrests, jail and respawn belong to the RP stack.

Speed cameras (`Config.Modules.speedCameras`) are independent of that and safe
to run on their own.

## Commands

## Keybinds

**Rebindable** — these register through `lib.addKeybind`, so they show up in
FiveM's *Settings → Key Bindings → FiveM* and players can change them:

| Action | Keyboard | Controller |
|---|---|---|
| Manual Gearbox: Shift Up | `↑` | D-pad Right |
| Manual Gearbox: Shift Down | `↓` | D-pad Up |
| Manual Gearbox: Clutch | `Left Shift` | L1 |

**Fixed** — read directly as game controls, so they are not rebindable:

| Action | Keyboard | Controller |
|---|---|---|
| Nitrous boost (hold) | `Left Alt` | X / Square |
| Interact | `E` | A |

"Interact" is one shared binding, resolved per input device by `SKInput`. It
covers repair stations, rampage start markers, race start markers, car meet
teleports, dismissing a stunt or rampage result, and the gearbox stall recovery
prompt. Prompts print whichever label matches the device in use.

The stunt jump tool has its own keys, listed on-screen while it is open.

| Command | Who | What |
|---|---|---|
| `/racemaker` | admin | Freecam checkpoint placer; saves to `sk_race_routes` |
| `/stuntdev` | admin | Freecam stunt jump placer; saves to `sk_stunt_jumps` |
| `/stuntedit` | admin | Reopen the nearest stunt jump (within 200m) in the placer |
| `/stuntdelete` | admin | Delete the nearest stunt jump (within 200m) |
| `/raceleaderboard` | all | Browse race times |
| `/racestats` | all | Career stats |
| `/gearbox` | all | Pick automatic / beginner / expert manual |

There are **no stunt jumps until an admin places some** — `data/stunt_jumps.lua`
ships as an empty template, exactly as upstream did. Fly `/stuntdev`, click to
drop the two zones, `R` for ramp mode, `Enter` to save. The on-screen legend
lists every key.

## Not ported

- **`phone`** — excluded by request.
- **`missions`** — a scripted story campaign with cutscenes; it drives
  StreetKings' own progression and mission-state machine.
- **`shop`** — mostly not ported. Its visual and performance mod shop duplicates
  `um_customs`. Only nitrous was taken (see above), since that is the one thing
  um_customs has no concept of. Its gearbox upgrades were dropped too —
  `/gearbox` stays a free per-player preference here rather than a per-vehicle
  purchase.
- **`avatar`, `garage`, `dealership`, `property`, `storage`, `main_menu`,
  `initiation`, `tutorial`, `pausemenu`, `settings`** — these are replacements
  for framework systems this server already has. Bridged or dropped rather than
  duplicated.
- **`speedometer`, `environment`, `soundtrack`, `notify`** — superseded by
  `um_hud`, `Renewed-Weathersync`, `xradio`/`xsound` and `ox_lib`.
