# vi_crashcam

A GTA VI style crash cam. Hit something hard enough and the game cuts away:
a couple of black frames, then a low camera at the roadside watching your car
go by in slow motion with the HUD off, then a short fade back into the seat.

Standalone. If `vice_hud` is running its HUD is hidden for the length of the
shot; without it the native HUD and radar are hidden and that is all there is
to hide.

## Install

```
ensure vi_crashcam
```

`/crashcam` plays the shot on the car you are sitting in, without needing a
crash — use it to check the camera on your own server before trusting it to a
real one.

## What counts as a crash

Speed lost in almost no time. With the defaults you have to be doing 80 km/h
or more and lose 45 km/h of it inside a tenth of a second, which braking
cannot do and a wall can. Both numbers, the length of the shot, how slow it
is, where the camera stands and the 20 second cooldown are in `config.lua`.

## For other resources

```lua
exports.vi_crashcam:PlayCrashCam()            -- on the player's current vehicle
exports.vi_crashcam:SetCrashCamEnabled(false) -- e.g. for the length of a race
exports.vi_crashcam:IsCrashCamPlaying()
```

## One thing to know

Slow motion is `SetTimeScale`, which slows the game for the player it happens
to and nobody else. For those few seconds other players see that car move
slowly and then catch up. That is why the shot is short and has a cooldown,
and why a race resource may want to switch it off while a race is running.
