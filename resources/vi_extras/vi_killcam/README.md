# vi_killcam: KILL CAMERA

Single player's kill camera (GTA6Hud, FBICat's 2.1), ported to FiveM. Every
third kill you make with a single shot of a gun cuts to a short slow-motion
shot: first the victim, then you. Players switch it on and off with the
**KILL CAMERA** row of HUD OPTIONS (hold V).

## What it does (as single player does it)

**Which kills count.** A kill is a *one-shot kill* when all of these are true:

- you killed them (their source of death is you);
- the weapon was a pistol, SMG, rifle, machine gun, shotgun or sniper rifle;
- they were seen alive first, within 65 m of you (and stayed within 80 m);
- they lost no health or armour before the frame they died. Anyone already
  hurt when first seen never counts.

**How often.** One-shot kills are counted up to 3. The third one plays the
shot, and the count goes back to 0. If the shot can't play then, the count
stays at 3 and the next one-shot kill plays it. Other kills don't change the
count.

**When it can't start.** It won't start within 7 seconds of the last shot
starting, while another script's camera is on screen (a shop, a garage, a
spectate camera), or while `vi_crashcam` is playing.

**The shot.** All times are real time, whatever the time scale.

| Time      | What you see |
|-----------|--------------|
| 0.000 s   | A hard cut to the victim. The camera is 2.3 m from their chest towards you, 1.1 m to one side and 0.15 m up, with FOV 40. It swings round them at 14° a second and keeps looking at their chest (+0.1 m) as they fall. |
| 1.456 s   | A cut to you. The camera is 1.4 m in front of your chest towards the victim, 1.6 m to one side and 0.55 m down, with FOV 46, swinging round you at 14° a second and looking at your chest (+0.25 m). |
| 2.800 s   | A hard cut back to your own camera. |

Each cut picks its side and swing direction at random. If a wall is in the
way, the camera stops 0.3 m short of it. The game runs at a quarter speed for
the whole shot. The picture is washed out (the `rply_saturation_neg`
timecycle, at full strength), but only when no other timecycle modifier is
already on. The HUD and radar are hidden. There are no letterbox bars, no
vignette and no sound: single player draws bars and plays a sound only for
its crash camera.

**You keep control.** FBICat's changelog says his 2.1 kill cam "never freezes
you". In GTA6Hud 2.1, the code that ends the shot still unfreezes your
position, but nothing ever freezes it. No control is disabled during the
shot: you keep aiming, moving and turning, in slow motion, while the camera
plays. The only thing single player holds back is its HUD OPTIONS menu, which
can't open during the shot.

**Ending early.** The shot ends at once, and puts back your camera, normal
speed, the colour and the HUD, if:

- you die;
- a pause menu opens (GTA's own, or `gk_pausemenu`);
- the weapon wheel opens;
- the inventory opens;
- a cutscene, a character switch or a fade starts;
- the victim is deleted;
- the KILL CAMERA row is switched off;
- `vi_extras` stops.

## Config (`config.lua`)

| Key       | Default | What it does |
|-----------|---------|--------------|
| `enabled` | `true`  | `false` switches the feature off on the whole server: no camera and no row. |
| `default` | `false` | What the row starts on for a player who has never switched it: off, as single player ships it (`GTA6Hud.ini` `[Cinematics] KillCamera = False`; GTA6Hud's own default is on). |
| `players` | `false` | Also count kills of other players. This is FiveM only (see below). |

## What is different on FiveM

- **Slow motion is local.** `SetTimeScale` slows only this player's game. For
  those 2.8 seconds, other players see this player move slowly and then catch
  up. That is the price of single player's slow motion on a server.
- **Only while a gun is out.** Single player checks everyone within 65 m every
  frame. Here, people are only checked while you have a gun out, and for one
  second after you put it away. A one-shot kill needs a gun anyway, so no kill
  that counts is missed, and with no gun out the feature costs nothing. New
  people are picked up every 250 ms, not every frame.
- **Other players don't count unless `players` is on.** Single player has no
  other players. Someone else's health reaches you in steps, so two quick
  hits can look like one. A slowed shot in a gunfight with real people is also
  unfair on whoever sees it.
- **People owned by another player.** For the same reason, a quick double tap
  on a ped another player's game owns can count as one shot. A hit that takes
  someone below their fatal threshold is never counted as a wound, even when
  their death reaches this machine a frame after their health does.
- **What ends the shot.** Single player also ends it during a mission, its
  lock-picking, fuel pump, struggle and surrender moments, and its own weapon
  wheel. FiveM has no missions and none of those features. Here, GTA's weapon
  wheel and the inventory (ox_inventory, which is where shops and car boots
  are) take their place.
- **Restoring.** Single player restores the time scale it found. FiveM can't
  read the time scale, so it goes back to 1.0. The colour filter is cleared
  only if it is still the one this module put on. Another script may have
  replaced it during the shot.
- **The HUD.** With `vice_hud` running, its HUD is hidden for the shot
  (`SetHudVisible`). If you die during the shot, the HUD stays hidden until
  you are up again, because `vice_hud` hides the HUD for death itself.

## For other scripts

```lua
exports.vi_extras:IsKillCamPlaying()   -- true during the shot
```
