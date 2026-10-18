# vi_pausemenu

The pause menu as GTA VI's. ESC, P or a pad's Start opens a grid of picture tiles over the blurred game, the way
GTA VI's own pause menu looks: the server's name at the top left, the mode and the character's name and the VI logo
at the top right, the day and time, the cash and the bank at the bottom left, the keys at the bottom right.

![The home screen](docs/home.jpg)

| Tile | What it does |
| --- | --- |
| Map | The game's own map, with GTA VI's dark blue bars over its top and bottom (the area's name, the character) |
| Brief | Name, job and grade, duty, cash, bank, hunger, thirst, citizen ID, server ID |
| Stats | vice_hud's skills, each 0..100, with how far to the next level (needs `vice_hud`) |
| Rockstar Editor | Records a clip (the menu closes); while recording, choosing it again saves the clip |
| Game | The game's own settings (display, graphics, audio, controls) |
| Settings | This server's settings, below |
| Players | Everyone on the server, by server ID |
| Report | A category, a subject and a message to staff (a Discord webhook, or the server console) |
| Discord | Opens `Config.Discord` in the player's browser; no tile when it is empty |
| Disconnect | Asks first, then leaves the server |

Settings, Brief, Stats, Players and Report are GTA VI's settings screen: a list on the left, a picture and a line
about the chosen row on the right.

| | |
| --- | --- |
| ![Settings](docs/settings.jpg) | ![Stats](docs/stats.jpg) |
| ![Report](docs/report.jpg) | ![The bars over the map](docs/map.jpg) |

(Pictured in the browser preview, `tools/serve.py`, over a blurred still standing in for the game; the map picture
shows where the bars sit, with a still where the game's own map goes.)

## Install

```
ensure vi_pausemenu
```

No dependency. With `qbx_core` it shows the character's name, money and brief; each setting row and the Stats tile
appear only while the resource they belong to is running.

## Keys

Arrows (or WASD) move, Enter chooses, left/right change a setting, Esc or Backspace goes back and at home closes, P
closes, the right mouse button goes back. The mouse works throughout. In the report's subject and message, Tab moves
on.

## Settings

Each row reads and writes the resource it belongs to, so `/hudminimap`, `/mapmode` and the menu agree.

| Row | Resource | Through |
| --- | --- | --- |
| Crash Camera | `vi_crashcam` | `SetCrashCamEnabled`; remembered here (KVP `vi_pausemenu:crashcam`) and set again whenever vi_crashcam starts |
| Map Day/Night | `gen7_map` | `GetMapMode` / `SetMapMode` (auto, day, night); a map resource not in this bundle |
| Map in Vehicle Only | `vice_hud` | `GetMinimapOnFoot` / `SetMinimapOnFoot` |
| Radio | `vi_radio` | `IsMuted` / `SetMuted` |
| Pause Menu | here | GTA VI or Classic (the game's own); `/pausemenu` switches back |
| Key Bindings | the game | its key mapping screen (this server's actions) |
| Game Settings | the game | its settings screen |

## Config

`shared/config.lua`: the title (empty, the default: server.cfg's `sv_projectName`, else `sv_hostname`, sent by the
server with the players list), the mode line, the Discord invite, the report webhook and categories, the skills the
Stats screen lists (id, label, what raises it, its picture) and the tiles (which, in which row, their pictures and the
line at their right; `$location`, `$job`, `$players` and `$recording` are filled in).

## How it takes over the game's menu

As `gk_pausemenu` (in this bundle) does, so run one of the two, not both: the game's menu is kept shut with `SetPauseMenuActive(false)` every frame, and the key
is caught as a control press (`IsControlJustPressed` 199/200), not by watching the pause flag. The map and the game's
settings are the game's own screens (`ActivateFrontendMenu`), entered with the page's NUI focus dropped first and the
pause flag raised; when the player backs out (`IsFrontendReadyForControl` goes false) the page takes focus again and
shows the screen it was on. On the map, the frontend header's own methods (`SHOW_MENU`, `SHOW_HEADING_DETAILS`,
`SET_HEADER_TITLE` in `pause_menu_header.gfx`) take its tabs and player details away every quarter second, and the page
lays its two bars over it.

A UI that disables control 200 while it is up (the ATM, the phone's games, the casino) keeps this menu shut too.
`LocalPlayer.state.pauseMenuOpen` is true while it is up; vice_hud hides its minimap frame then.

## Pictures and type

In game the menu sits over the live game, blurred by the game's own screen blur; nothing is drawn behind it but a
dark tint. The tile and setting pictures (`html/img`) are stills from Rockstar's GTA VI footage; the logo is GTA VI's. The type is
GTA Art Deco throughout, the same three cuts vice_hud ships (`html/fonts`): bold for titles, labels and values, medium
for the lines under them, regular for typed text.

## tools

- `node tools/run.js` — the client and server on a small FiveM (`tools/mock.lua`, `tools/check.lua`): opening and
  closing, the reopen cooldown, the tiles, every settings row against its export, the brief, stats and players, the
  map and settings hand-offs, the editor, reports (rate limit, webhook), disconnect, classic mode. Uses vice_hud's
  fengari (`npm i jsdom fengari` in `vice_hud`, as its README says).
- `python tools/mutate.py` — breaks the code in 25 ways; each must make the checks fail.
- `python tools/serve.py` — the page in a browser with `tools/stub.js` standing in for the client
  (`?screen=settings|brief|stats|players|report`, `?map=1`).
- `python tools/shots.py` — the pictures in `docs/`, from `serve.py`'s page (Python Playwright).

Not yet seen in game: whether the page shows over the game's own map (the bars), and whether the map's header methods
take, are checked only headless.
