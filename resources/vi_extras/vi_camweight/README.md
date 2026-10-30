# vi_camweight

**CAMERA WEIGHT**, from the fork's ViExtras (`src/ViExtras/WeightedCam/WeightedCam.cs`,
`ViExtras.ini` `[WeightedCam]`). Land a jump, hit a bump hard or crash, and the
driving camera dips with your car or bike, as hard as the hit, then eases back to
your view in about a second. Each player switches it in HUD OPTIONS (hold V);
`config.enabled = false` takes it away from everyone.

## How it works (single player's numbers)

- **Landings and bumps:** how much of the speed the vehicle was coming down at
  (over the last 200 ms) has gone, in km/h. Nothing under `landMin` (9), the full
  `landDip` (4.5 degrees) from `landFull` (45); the bottom is reached in `landMs` (110 ms).
- **Crashes:** the biggest change in speed along the ground against any reading in
  the last 200 ms, in km/h. Nothing under `crashMin` (20), the full `crashDip`
  (3.5 degrees) from `crashFull` (80), the bottom in `crashMs` (75 ms).
- Each hit is a critically damped spring: `peak x (t / T) x e^(1 - t / T)`, at the
  bottom at T, nearly back by 6T, dropped at 8T. A hit read over several frames
  only adds what it hasn't dipped for yet (in steps of at least 2%); a hit is over
  after 250 ms of nothing. Hits add up, to at most 1.5 x the larger dip x `strength`.
- A jump of more than 3 m plus twice a frame's travel (a teleport) clears the readings.

The dip is shown through a scripted camera that copies the game's third-person
vehicle camera every frame (coord, rotation and FOV, carried on by one frame of
the vehicle's travel and the camera's last turn, clamped to 5 degrees), pitched
down by the dip. The game's camera is never touched, so the mouse or stick keeps
working and the view handed back is the one you would have had. Nudging
`SetGameplayCamRelativePitch` instead doesn't work: in a vehicle it lands 2 to 3.5
degrees off what `GetGameplayCamRelativePitch` reads.

Not in first person, aiming, looking behind, the cinematic camera, any other
scripted camera, with player control off, or in boats, helicopters, planes and trains.

## config.lua

| key | default | single player |
| --- | --- | --- |
| `enabled` | `true` | (FiveM only) the feature and its row at all |
| `default` | `true` | `[Switches] CameraWeight` |
| `strength` | `1.0` | `[WeightedCam] Strength` (0 is off) |
| `landMin`, `landFull`, `landDip`, `landMs` | `9`, `45`, `4.5`, `110` | `[WeightedCam]` same names |
| `crashMin`, `crashFull`, `crashDip`, `crashMs` | `20`, `80`, `3.5`, `75` | `[WeightedCam]` same names |
| `debug` | `false` | `[WeightedCam] Debug` |

## Different from single player

- **Who else has the screen.** Single player asks its own CrashCam, Binoculars,
  the VI pause menu and GTA6Hud's shops. Here: `vi_crashcam`
  (`IsCrashCamPlaying`), `vi_binoculars` (`IsActive`), any scripted camera on
  screen that isn't this one (`GetRenderingCam()`), the pause menu, and anything
  holding NUI focus (the VI pause menu is a NUI page). Any of these mid-dip hands
  the view straight back, and the dip camera is destroyed without touching the
  other camera. A dip camera another script destroys ends the dip.
- **Death.** Besides a dead ped, the death state Qbox (`qbx_medical`,
  `LocalPlayer.state.isDead`) and `wasabi_ambulance` (`LocalPlayer.state.dead`)
  keep on a living ped.
- **Leaving.** Out of the vehicle, dead, the row off or the resource stopped: the
  camera is handed back at once. Outside a vehicle it looks every 200 ms instead of
  every frame.
- **Logging.** `debug` prints to the F8 console instead of `ViExtras.log`. Single
  player also logs every dip over a quarter of the full one with `Debug` off; here
  nothing is printed unless `debug` is on.
- `vi_crashcam` needs no change: it cuts in over the dip camera, and this one
  steps aside while it plays (single player's CrashCam has to be told the dip
  camera may be cut away from).
