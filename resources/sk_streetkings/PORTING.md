# sk_streetkings — porting handoff

Written 2026-07-27. Read this cold in a new session to continue the port.
See `README.md` for how the resource is structured; this file is only about
**what is left to do and how to do it**.

---

## Status

**Done and working** (12,142 lines, 61 files, all syntax-verified):
car meet (Randolio base + drift + NPC betting), racing (routes, time trials,
MP lobbies, leaderboards, `/racemaker`), meet night, nitrous, manual gearbox,
hangout/passive zones, repair stations, career stats, speed cameras, police,
stunt jumps + `/stuntdev`, rampage, NPC street challenges, and the whole
`modules/core/` compatibility layer.

`um_carmeet`, `sk_racing`, `meet_night` already moved to `../../../_Retired/`.

**Remaining: 2 groups, ~2,300 lines of upstream source.** Ports come out
smaller — the NUI layers get replaced by ox_lib.

**Nothing here has been run in-game yet.** Everything below the syntax check is
untested: no server start, no live check of the new modules.

---

## Getting the source back

The upstream clone was in a temp scratchpad and is gone. Re-clone:

```bash
git -c core.longpaths=true clone --depth 1 https://github.com/streetkings-fivem/streetkings.git C:/Users/gecko/AppData/Local/Temp/sk_up
```

Both parts matter on Windows: cloning into the session scratchpad fails with
`cannot write keep file ... Filename too long`, because the scratchpad path is
already near MAX_PATH before git appends `.git/objects/pack/...`. Use a short
target directory *and* `core.longpaths`.

Everything referenced below is under `modules/` and `data/` in that repo.

### The other three repos

`github.com/streetkings-fivem` hosts four repos, not one. The main resource's
manifest only declares `streetkings_audio` as a dependency, so the other two are
easy to miss:

| Repo | What it is | Verdict |
|---|---|---|
| `streetkings` | the main resource, everything ported here | — |
| `streetkings_audio` | `sk_soundset` — a wavepack + `dat54.rel`, 2 files | **safe, optional** |
| `streetkings_blips` | `stream/minimap.ytd` + `blips_texturesheet_ng_2.dds` | **installed, sheet only** |
| `txAdminRecipe` | full-server recipe, not useful here | ignore |

Both are installed at `[Scripts]/streetkings_audio` and
`[Scripts]/streetkings_blips`, covered by the existing `ensure [Scripts]`.

**`streetkings_audio`** registers a new soundset and wavepack and replaces no
vanilla file. `SK.PlaySound` picks it up automatically when present and falls
back to stock sounds when absent, so deleting the folder is safe.

**`streetkings_blips` is installed WITHOUT `minimap.ytd`.** Upstream ships both
that and `blips_texturesheet_ng_2.dds`; `um_hud` already streams its own
`stream/minimap.ytd` (with `minimap.gfx` and `radarmasksm.png`), which is what
gives this server its custom minimap. Two resources streaming the same filename
is load-order roulette, so only the sprite sheet was taken. **Do not add
`minimap.ytd` to that folder later** — the reasoning is repeated in its
`fxmanifest.lua`.

**It is also now redundant, and deleting it is recommended.** Upstream's sprite
IDs (827 speed camera, 500 stunt, 378 rampage) only make sense against its own
sheet — on the stock sheet 500 is `radar_production_money` and 378 is
`radar_team_deathmatch`. `Config.Blips` now uses purpose-built vanilla sprites
instead (184 `radar_camera`, 488 `radar_stunt`, 84 `radar_rampage`), which need
no custom sheet at all. The folder's only remaining effect is restyling blips
from *other* resources that sit on sheet 2 — a side effect with no upside.

Pick sprite IDs by name from `docs.fivem.net/docs/game-references/blips` rather
than copying upstream's numbers.

---

## ~~Group 1 — Stunt jumps, rampage, NPC challenges~~ — DONE

Landed as `modules/stunts/`, `modules/rampage/`, `modules/npcchallenge/` and
`modules/devtools/`. Notes worth keeping:

- **`data/stunt_jumps.lua` is still an empty template**, by design. Jumps get
  placed in-game: `/stuntdev` opens the placement tool, `/stuntedit` loads the
  nearest jump, `/stuntdelete` removes it. All three are admin-gated in
  `modules/devtools/stunt_devtool_s.lua` (same shape as `/racemaker`). Saved
  jumps go to the new `sk_stunt_jumps` table and sync live — no restart needed.
  F9 in the tool copies the current jump as a `data/stunt_jumps.lua` snippet,
  if you would rather keep it in source control than in the database.
- **Rampage locations are staged** in `data/rampages.lua` — the five entries
  upstream shipped, lifted out of its `data/events.lua`.
- **Scores go to `sk_activity_scores`**, and each submit returns the player's
  rank so the result readout can show it. Both activities clamp the
  client-reported score; neither can be recomputed server-side, same as
  upstream.
- **`Config.Rampage.cashPerPoint = 0.35` is very generous** — see the note in
  `shared/config.lua`. Left at upstream's value rather than silently rebalanced.
- **The devtool needed a freecam.** Upstream's lived in
  `modules/devtools/race_editor_freecam_c.lua` and was not on the porting list;
  it is ported as `modules/devtools/freecam_c.lua` (`SKFreecam`). `/racemaker`
  predates it and still places from the player's own position.

**Game states are now actually driven.** Nothing in the resource ever called
`SKC.SetGameState` outside the car meet, so `GameState.EVENT` was never entered
and `SKRacingStates` was dead — which would have left speed cameras, stunt jumps
and police firing in the middle of a race. `race_singleplayer_c` and
`race_multiplayer_c` now enter `EVENT` / `MULTIPLAYER_LOBBY` /
`MULTIPLAYER_EVENT` and return to `FREEROAM` on finish, abort and forfeit.

---

## ~~Group 2 — Speed cameras + police~~ — DONE

Landed as `modules/speedcameras/` and `modules/police/`. Notes worth keeping:

- **The flash pays a fine, not a reward.** Upstream posted every trigger to its
  daily-events system, which is not ported. `Config.SpeedCameras.fine` is
  charged to `fineAccount` (`'bank'`), falling back to the other account so an
  empty bank isn't a free pass. Camera lookup and cooldown are server-side —
  the client only names which camera fired.
- **Police is still `Config.Modules.police = false`** and should stay that way
  unless it is a deliberate call. Its tuning now lives in `Config.Police`.
- **The bust is a fine and a fade, not an arrest.** Upstream ran an arrest NUI
  sequence and dropped the player into its own garage. Arrests, jail and
  respawn belong to the police RP stack here, so the port stops at charging and
  clearing the wanted level.
- **`SKPolice` only exists when the module is on** — the early return happens
  before the table is built. Group 1's `npc_challenge_c` calls
  `SKPolice.isChasing()`; guard it as `SKPolice and SKPolice.isChasing()`.

---

## Group 3 — Nametags, progression, admin, controller

| Upstream file | Lines | What it does |
|---|---:|---|
| `modules/nametags/*` | 143 | Player nametags above vehicles |
| `modules/progression/*` | 828 | Vehicle XP + mod unlock curves |
| `modules/admincommands/*` | 137 | Teleports, vehicle spawning, state overrides |
| `modules/controllerfriendly/*` | 194 | Gamepad prompt/navigation helpers |

**Two scoping decisions needed from the user before starting:**

1. **Nametags** likely duplicate whatever already shows player IDs on this
   server. Check before adding a second system.
2. **Progression** gates cosmetic mods behind vehicle levels, which collides
   with `um_customs` and the existing vehicle-mod flow. Probably
   wants scoping down to the XP curve only, dropping the unlock gating.

Race XP/levels are **already wired** (`SKProfiles.awardXp`, keyed on source,
stored at `progression.playerXp` / `progression.level`). This group is about
*vehicle* progression on top of that.

Do this group **last** because of the two open questions.

---

## Group 4 — Clothing store on ox_lib

| Upstream file | Lines | What it does |
|---|---:|---|
| `modules/avatar/avatar_stores_c.lua` | 102 | Store locations, entry, purchase flow |
| `modules/avatar/avatar_c.lua` | 733 | Component/prop browsing, preview camera |
| `data/avatar_shop.lua` | 157 | Catalog + pricing |

User explicitly asked this match ox_lib styling.

**Plan:** rebuild browsing as ox_lib context menus bridged to
`illenium-appearance` (which already owns appearance here). Keep SK's catalog
and pricing from `data/avatar_shop.lua`. **Drop** the 733-line NUI character
viewer. Net port is far smaller than the source count suggests.

Config flag already present: `Config.Modules.clothingStore`.
Stat key already valid: `clothingPurchased`.

---

## The um_customs hook (only edit outside this resource)

> **2026-10-10: um_customs was retired from this server** (moved to `_Retired/um_customs_2026-10-10`)
> and replaced by `[UM]/Lenonida_customs`, which needs no hook. It sells nitrous through two exports
> in `modules/tuning/tuning_c.lua`, `GetNitrousShop(vehicle)` and `BuyNitrous(vehicle, tier)`, and the
> nitrous module mirrors its gauge into `LocalPlayer.state['customs:nitrous']` for vice_hud's icon.
> What follows only matters if um_customs is ever brought back.

Nitrous is bought from `um_customs`' Performance menu. um_customs has no exports
and no extension points — every function in it is file-local — so it carries two
small blocks in `client/menus/performance.lua`, delimited by
`-- >>> sk_streetkings hook — BEGIN` / `-- <<< sk_streetkings hook — END`:

1. In `performance()`, after `table.sort` — appends rows from
   `exports.sk_streetkings:GetPerformanceMenuOptions(vehicle)`.
2. At the top of `onSubmit` — routes rows carrying `skPurchase` to that function
   instead of um_customs' `InstallMod`.

**A um_customs update wipes both; re-paste them and nothing else.** All the
logic is in `modules/tuning/`. The hook is guarded on `GetResourceState`, so
um_customs behaves exactly as shipped if this resource is stopped.

Two constraints forced that shape, worth knowing before "simplifying" it:

- um_customs calls `option.set()` on **every side-scroll** to preview a mod.
  Purchasing there would charge the player for scrolling, hence the separate
  `skPurchase` that only fires on submit.
- `InstallMod()` prices every mod through `sharedConfig.prices[mod][level]`, so
  passing it a foreign mod id errors server-side on a nil index. Our row must
  bypass that path entirely.

This is the same trade-off that was declined for `um_hud`. It was accepted here
because it is plain Lua with no build step, and the edit is two comment-marked
blocks rather than a merged feature.

---

## How to port (conventions this resource already follows)

Do **not** port StreetKings' framework modules. Use the compat layer:

| SK global | Use instead | Defined in |
|---|---|---|
| `SKSaves.economy.*` | `SKPlayer.addMoney/removeMoney/getMoney` | `modules/core/player_s.lua` |
| SK identity | `SKPlayer.citizenid/alias/isAdmin` | `modules/core/player_s.lua` |
| `SKSaves.read/write` | same API, kept | `modules/core/saves_s.lua` |
| `SendNUIMessage(...)` | `SKHud.register/set/clear` | `modules/core/hud_c.lua` |
| `SKNotify` | kept, forwards to ox_lib | `modules/core/notify_c.lua` |
| `SKWaypoint.*` | same API, native-backed | `modules/core/waypoints_c.lua` |
| `ALLOWED_STATES` | `SKDrivingStates` / `SKRacingStates` | `shared/game_state_sh.lua` |
| `SK.*`, `SKInput.*` | ported verbatim | `modules/core/` |
| `Cinematic` | same global, kept | `modules/core/helpers_c.lua` |
| `SKCamera.*` | drop the calls | — |
| `'...', 'sk_soundset'` | a stock GTA soundset | — |
| `streetkings:*` events | `sk_streetkings:<module>:*` | — |

`Cinematic` was declared by upstream's custom chase camera
(`modules/freeroam/camera_c.lua`), which is **not** ported — the vanilla GTA
camera is used instead. Modules still read it to mean "a scripted camera is
running, stand down", so the global is declared in `helpers_c.lua` and every
`SKCamera.disable()` / `.enable()` / `.delayEnable()` call is simply dropped.

`sk_soundset` lives in a separate `streetkings_audio` repo (see below). Route
every `PlaySoundFrontend(..., 'sk_soundset', ...)` through `SK.PlaySound(name)`
in `helpers_c.lua` and add the stock stand-in to its `FALLBACK_SOUNDS` table —
that way the sound is right when the resource is installed and sane when it is
not. Sounds still needing a mapping if their module is ever ported:
`purchase1` (avatar shop, group 4) and `airwrench1..3` (tuning shop, not
ported).

Menus/dialogs/prompts/toasts → **ox_lib directly** (`lib.registerContext`,
`lib.inputDialog`, `lib.alertDialog`, `lib.showTextUI`, `lib.notify`). They
inherit the server theme for free. Only persistent overlays use `SKHud`.

**`SKHud` must avoid the bottom-right corner** (roughly x > 0.78, y > 0.72) —
`um_hud` owns it and renders as NUI, which composites *above* native draws, so
anything there is invisible. Use `SKHud.Anchor`, never raw coordinates. The
user considered merging HUDs into um_hud and **declined** (would create a
dependency, need a Vite rebuild per tweak, and be wiped by vendor updates).

Add every new module to `Config.Modules` and early-return on it:

```lua
if not Config.Modules.<name> then return end
```

Then register files in `fxmanifest.lua` — load order there is deliberate and
commented; read those comments before inserting.

---

## Gotchas already hit (don't repeat)

- **Lua has no `?.`** — write `a and a.b and a.b.c`.
- **Player-loaded event** is `QBCore:Server:PlayerLoaded` (local, receives the
  player object). `qbx_core:server:onPlayerLoaded` does **not** exist.
- **Money exports** are `exports.qbx_core:AddMoney(src, moneyType, amount, reason)`.
- **`lib.require` files must be listed in `files{}`** in the manifest (that's
  why `data/carmeet.lua` is there — it returns a table instead of setting a
  global).
- **Don't shadow `Config`** — car meet data is loaded as `local Meet`.
- **Charge before granting**, not after (the original repair module fixed the
  car then billed, so a broke player got it free).
- **MySQL resolves table names at parse time** — a `SELECT` from a possibly
  missing table aborts the whole script even behind an `EXISTS` guard.
- Backticks in Lua are FiveM hash literals; `luaparse` chokes on them. Strip
  with `/\`[^\`\n]*\`/g → `"x"` before syntax-checking.

**Syntax check everything before declaring done:**

```bash
npm install luaparse && node check.js "<path to sk_streetkings>"
```

(`check.js` walks `.lua` files, strips hash literals, parses as Lua 5.3.)

---

## Suggested order

**~~2~~ → ~~1~~ → 4 → 3.** Group 3 is last because it needs user decisions first.

---

## Also outstanding

- **Run `sql/install.sql`** before next server start — `sk_profiles`,
  `sk_activity_scores` and `sk_stunt_jumps` are new and required. Optional block
  at the bottom migrates XP/levels out of `sk_race_profiles`.
- **Test in-game.** None of the ported modules have been run on a live server.
  Worth checking first: a speed camera flash and fine, a stunt jump end to end
  (place one with `/stuntdev` — there are none until you do), a rampage payout,
  and that a race now suppresses all three.
- **Review `Config.Rampage.cashPerPoint`** before letting players at it.
- **Nothing else was retired.** The wider sweep found no clearly-dead
  resources. Name-based greps were misleading: `interact-sound` and
  `qbtarget_bridge` scored zero but are live (8 event callers / 55 `qb-target`
  callers). Genuine zero-reference hits are dev/build tools only —
  `em_toolkit`, `z_offsetfinder-main`, `loaf_offsetfinder`, plus `SmartSigns`
  and `um_fenix_bridge`. User's judgement call, nothing moved.
