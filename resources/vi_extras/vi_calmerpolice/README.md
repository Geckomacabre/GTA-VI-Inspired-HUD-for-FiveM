# vi_calmerpolice

**CALMER POLICE**, from the fork's ViExtras (single player's `ViExtras.ini`
`[Switches] CalmerPolice`, `Wanted\CalmerPolice.cs`). GTA's police were on top of
you in seconds, and seemed to know where you were when none of them could see
you. Each player switches it in HUD OPTIONS (hold V); `config.enabled = false`
takes it away from everyone.

## What it does (single player's numbers)

Checked once a second, 3 s after a loading screen or character switch:

- **Slower, further off.** Every police dispatch service (police cars, helicopters,
  SWAT, bikes, backup, roadblocks, the waiting cars, SWAT helicopters, boats, the
  army) waits `spawnDelayMultiplier` (2) times as long between sending units
  (`SET_DISPATCH_TIME_BETWEEN_SPAWN_ATTEMPTS_MULTIPLIER`), and the game places them
  around `spawnDistance` (300) m away (`SET_DISPATCH_IDEAL_SPAWN_DISTANCE`).
- **The search stays where they last saw you.** Once the stars grey out, the
  search centre is noted; whenever the game moves it more than 5 m from there
  (its way of "just knowing"), it is put back.
- **Easier to lose.** The game's hidden-escape time for the current star count is
  `escapeSeconds + escapeSecondsPerStar x stars` (10 + 5 a star: 15 s at 1 star,
  25 s at 3, 35 s at 5), set again whenever the stars change. If the stars are
  still there 5 s after that, hidden the whole time, they are cleared here
  (not while being arrested or dead).

Switched off, while a police resource runs, while a script has the mission flag
up, or when the resource stops, the game's own values go back: multiplier 1,
`RESET_DISPATCH_IDEAL_SPAWN_DISTANCE`, `RESET_WANTED_LEVEL_HIDDEN_ESCAPE_TIME`.

## config.lua

| key | default | single player |
| --- | --- | --- |
| `enabled` | `true` | (FiveM only) the feature and its row at all |
| `default` | `true` | `[Switches] CalmerPolice` |
| `spawnDelayMultiplier` | `2.0` | `[CalmerPolice] SpawnDelayMultiplier` (under 1 counts as 1) |
| `spawnDistance` | `300.0` | `[CalmerPolice] SpawnDistance` (0: the game's own) |
| `escapeSeconds` | `10` | `[CalmerPolice] EscapeSeconds` |
| `escapeSecondsPerStar` | `5` | `[CalmerPolice] EscapeSecondsPerStar` |
| `policeResources` | `{ 'fenix-police' }` | (FiveM only) single player's `[Compat]` RDE / LSR |

## Different from single player

- **Per player.** A FiveM player's wanted level, and the police the game sends for
  it, are run by that player's own game, so all of this is client-side and only
  touches the player's own pursuit.
- **fenix-police runs the police.** While a resource in `policeResources` is
  started this stands down, as single player does for Rebalanced Dispatch Enhanced
  and Los Santos RED. fenix-police switches the game's police dispatch off every
  second (`EnableDispatchService` 1, 4, 6-10 false; its `Config.AIResponse` has all
  15 off) and sends its own units from 80-140 m (`Config.min/maxPoliceSpawnDistance`),
  so the dispatch settings would do nothing. It sets its own hidden-escape times
  (`Config.evasionTimes`: 60 / 90 / 120 / 120 / 150 s) and runs its own sighting model
  (`Config.Pursuit.loseContactMs` 4 s, `giveUpAfterMs` 45 s), which the escape times
  and the early clear here would fight. To have calmer police with it, change
  fenix-police's own numbers (for single player's: `Config.evasionTimes` 15 / 20 / 25 /
  30 / 35 s) rather than taking it off this list.
- **The dispatch multiplier is set per service.** The native takes the dispatch
  service first, then the multiplier; it is set on each police service above.
- **"Where they last saw you".** Single player reads the game's last-spotted
  position (Script Hook V .NET reads it from memory); there is no native for it.
  Here it is the search centre at the moment the stars grey, which the game has
  just put on the last sighting. FiveM's Lua wrapper for
  `SET_PLAYER_WANTED_CENTRE_POSITION` can't pass a position (it offers only an empty
  output vector), so the position goes in through `Citizen.InvokeNative` laid out as
  the game's vector, and is read back. If it doesn't land twice running, the search
  is left to the game for the session and one `^1[vi_extras]^7` line says so.
- **Story missions** are the mission flag (`GetMissionFlag`), which a resource can
  raise. **LSPDFR on duty** has no counterpart here and is not checked.
- Single player's log lines are not printed.
