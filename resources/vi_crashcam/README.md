# vi_crashcam

The GTA VI crash cam. Crash hard enough and:

1. the hit plays out, already slowed, from wherever you were looking;
2. the game cuts hard to a camera standing well back from the car, with the
   edges of the screen closed in and the HUD gone, for a little over three
   seconds;
3. it cuts hard back to **exactly the view you had** (behind, to one side, from
   the bonnet), time runs back up to normal, and the HUD returns a moment later.

Timed off the reference crashes, which all go that way.

## What counts as a crash

A lot of speed lost in almost no time: by default 80 km/h or more beforehand
and 45 km/h of it gone inside a tenth of a second. Braking cannot do that, so
it never triggers on a hard stop. One shot per 20 seconds at most, and only for
the driver unless `Config.DriverOnly` is off.

`/crashcam` plays the shot on the car you are sitting in, without a crash.

## The picture

- **Where the camera stands.** `Config.Shots` lists the places it can go (low at
  the roadside, further up the road with the car coming to it, up and well back
  looking down). Each is tried on both sides and closer in, and one with a clear
  view of the car is picked at random, so two crashes in a row are not filmed
  the same way.
- **The overlay.** With `vice_hud` running it is the same kind of effect as its
  Focus one, in black instead of purple: the edges of the screen closed in,
  breathing slowly, with thin bars top and bottom. Without `vice_hud` only the
  bars are drawn. `Config.Overlay` sets how strong, how tall the bars are, and
  whether it breathes.
- **Hard cuts.** The reference cuts both ways. `Config.BlackFlashMs` and
  `Config.FadeInMs` are there if you want a few black frames in or a fade back.
- **A little hand movement** on the camera (`Config.HandShake`).

## On a server

Slow motion is `SetTimeScale`, which slows this client only. For those few
seconds other players see this car move slowly and then catch up. That is the
price of slow motion in multiplayer, and the reason the shot is short and has a
cooldown.

## For other scripts

```lua
exports.vi_crashcam:PlayCrashCam()              -- on the current vehicle
exports.vi_crashcam:IsCrashCamEnabled()         -- bool: the player's switch
exports.vi_crashcam:SetCrashCamEnabled(false)   -- set it
exports.vi_crashcam:IsCrashCamPlaying()
```

`SetCrashCamEnabled` is the player's own switch, as HUD OPTIONS' CRASH CAMERA
(`vi_extras`) and the pause menu's Crash Camera (`vi_pausemenu`) flip it. It
is saved per player in this resource's KVP (`vi_crashcam:enabled`), so it is
there again the next time they join, and it is `Config.Enabled` until they set
it. Off, crashes are not watched for, and a shot already playing cuts back.
`PlayCrashCam` and `/crashcam` still play a shot when asked. Because it is
saved, it is not the way to hold the camera off for a while (a race, say).

## Install

Copy the folder into `resources/` and `ensure vi_crashcam`. No dependencies.

## Licence

CC BY-NC-SA 4.0, like the rest of this repository.
