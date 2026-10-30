# vi_extras

Single player's GTA VI-Inspired HUD features that FiveM didn't have, and single player's **HUD OPTIONS** menu to
switch them, so the two versions work the same.

It's built like [qbx_smallresources](https://github.com/Qbox-project/qbx_smallresources): every folder is one
feature, with its own `client.lua` (and `server.lua`, `config.lua`, `README.md`), loaded by the manifest's globs.
To take a feature into another resource, copy its folder and `vi_hudoptions` (the rows every feature adds its
switch to), and its streamed files if it has any.

## HUD OPTIONS (hold V)

Hold the camera button for half a second (**V**, or the back / view button on a pad) and the switches come up at the
bottom right, as in single player: each name with its value in a small box, a line, and HUD OPTIONS under it.
**Up / Down** choose a row, **Enter / A** changes it, **Backspace / B** (or holding the button again) closes it. A
tap still changes the camera; a hold that opens the menu puts the view back. `/hudoptions` opens it too.

Every number is single player's (`GTA6Hud.ini` `[SettingsMenu]` and `[Colors]`, in `vi_hudoptions/config.lua`), and
it draws with the same natives: GTA's font 4, single player's outline, its badges and scroll bar.

With `vi_pausemenu` running, its **Settings** page lists the same rows.

Each player's choices are kept (resource KVP), so they come back the next time they join. A row whose feature lives in
another resource is kept by that resource, and shows only while it runs.

## The rows, in single player's order

| Row | Where | Starts | What it is |
| --- | --- | --- | --- |
| GUNS ON BACK | `vi_gunsonback` | off | Long guns you carry but aren't holding hang on your back, two at most; other players see them. |
| DRAW ANIMATIONS | `vi_drawanims` | off | A holster and draw animation when you change weapons (single player's clips, streamed from `stream/vi_drawanims`). |
| CHASE MUSIC | `vi_chasemusic` | off | Your server's own tracks (`vi_chasemusic/music/`) while you're wanted, fading in and out as single player's. |
| KILL CAMERA | `vi_killcam` | off | Every third one-shot kill, a slow-motion shot of the victim and then of you. |
| CRASH CAMERA | `vi_crashcam` | on | (vi_crashcam's own.) |
| MAP DAY/NIGHT | `gen7_map` | auto | (gen7_map's own, where it runs.) |
| MAP IN VEHICLE ONLY | `vice_hud` | off | (vice_hud's minimap on foot.) |
| SEARCH CIRCLE | `vice_hud` | on | The police search area on the drawn minimap. Like single player's, it stands aside for the wanted colouring: it shows only with `Config.Map3D.police = false`. |
| GREET / ANTAGONIZE | `vice_hud` (honor) or `qbx_honor` | on | (honor's greet and antagonize prompts.) |
| SPIN-OUTS | `vi_spinouts` | on | People's cars spin out when you shoot them, burst a tyre, kill the driver or hit them side on; yours spins on a hard side hit. |
| VI RADIO WHEEL | `vi_radio` | on | (vi_radio's wheel; off gives GTA's own back.) |
| POLICE LIGHTS | `vice_hud` | 100% | (vice_hud's police lights, 0 / 60 / 80 / 100 / 120 / 140%.) |
| CROSSHAIR | `vice_hud` | on | (vice_hud's crosshair.) |
| KILL MARKS | `vice_hud` | on | (vice_hud's kill marks.) |
| VI WANTED STARS | `vice_hud` | on | (the four-state stars; off draws them plain.) |
| WANTED BOX | `vice_hud` | on | (vice_hud's wanted box.) |
| CAMERA WEIGHT | `vi_camweight` | on | The driving camera dips with your car when you land a jump, hit a bump hard or crash. |
| BINOCULARS | `vi_binoculars` | on | (vi_binoculars.) |
| CALMER POLICE | `vi_calmerpolice` | on | Police arrive slower and from further away, and give up sooner. Stands aside while `fenix-police` runs. |
| MONEY IN STORES | `vi_storemoney` | on | Your cash and bank stay up while you're in a store (ox_inventory shops, illenium-appearance's clothes and barber shops). |

"Starts" is single player's shipped setting; each module's `config.lua` has `default`, and `enabled = false` takes the
feature (and its row) off the whole server. Single player's CARRY ALL WEAPONS has no row here: on FiveM, what you
carry is ox_inventory's business.

Each module's `README.md` says where its numbers come from in single player and what had to change on a server.

## Install

```
ensure ox_lib
ensure vice_hud        # optional, as are the others below: their rows show while they run
ensure vi_crashcam
ensure vi_binoculars
ensure vi_radio
ensure vi_extras
```

`ox_lib` is the only dependency. Some features read other resources when they're there: `ox_inventory` (guns on back,
draw animations, money in stores), `illenium-appearance` (money in stores), `vi_radio` (chase music stops while your
own music plays), `fenix-police` (calmer police stands aside; the search circle uses its search area).

Two server settings to know:
- **Draw animations with ox_inventory:** ox_inventory plays its own switch animations while `setr inventory:weaponanims 1`
  is in its config. Set it to `0`, or both play.
- **Chase music:** drop your own `.mp3` / `.ogg` / `.wav` / `.m4a` files into `vi_chasemusic/music/`; none come with it.

## Tests

Headless, with the natives stubbed, from this folder: `lua tools/<name>.test.lua` (or under fengari with a
`readfile` global, as the vice_hud tests are run), and `node tools/chasemusic_page.test.js`.

## Credits

The features, and the HUD OPTIONS menu, are FBICat's (GTA6Hud) and the single-player fork's (ViExtras: camera weight,
calmer police, money in stores), ported to FiveM. The draw animations are single player's clips from its `vihudanims`
pack.
