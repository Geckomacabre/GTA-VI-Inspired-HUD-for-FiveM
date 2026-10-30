# vi_spinouts

**SPIN-OUTS**, from FBICat's GTA6Hud (single player's `GTA6Hud.ini` `[Driving] SpinOuts`).
Cars lose the back end and spin when something knocks them off line. Each player
switches it in HUD OPTIONS (hold V); `config.enabled = false` takes it away from everyone.

## What it does (single player's numbers)

People's cars within 100 m (looked for every half second), going 11 m/s (40 km/h)
or more the frame before, spin out when:

| trigger | chance | which way |
| --- | --- | --- |
| a tyre bursts (wheels 0, 1, 4, 5) | always | the back goes right for a left tyre, left for a right one |
| the driver dies or gets out | always | either |
| you shoot it | `shotChance` x min(2, speed / 20 m/s): 12% at 72 km/h, 24% from 144 km/h | either |
| it is hit on the side (speed change over 7 m/s in a frame, touching something, hit more than 0.45 m off its centre line) | 65% | away from the hit |

Your own car spins out when it is hit (speed change of `impactMin`, 5 m/s, in a
frame while touching something; 350 ms between hits) on the side rather than the
nose or tail, the change is over 10 m/s, and you were doing over 12 m/s.

Motorcycles, bicycles, boats, aircraft and trains never spin out. A car spins once
while it stays in range.

A spin-out is: `SetVehicleReduceGrip` for 3.5 s, `SetVehicleOutOfControl` on a
person's car (never yours), and an impulse sideways at 85% of the way to the back
of the car, `clamp(speed x 0.16, 2, 4.5)`. Over 20 m/s, `rollChance` (35%) of them
roll 350 ms later, if the car is on the ground and sliding sideways at 4 m/s or
more: an upward impulse of `min(5.5, 2.8 + (speed - 20) x 0.12)` at the side it trails.

## config.lua

| key | default | single player |
| --- | --- | --- |
| `enabled` | `true` | (FiveM only) the feature and its row at all |
| `default` | `true` | `[Driving] SpinOuts` |
| `rollChance` | `0.35` | `[Driving] SpinRollChance` |
| `shotChance` | `0.12` | `[Driving] SpinShotChance` |
| `impacts` | `true` | `[Driving] Impacts` (your own car's spin-out) |
| `impactMin` | `5.0` | `[Driving] ImpactMin` |
| `controlWaitMs` | `250` | (FiveM only) see below |

## Different from single player

- **Network control.** A networked car's physics run on the client that owns it,
  so a push from anyone else does nothing. This client spins out cars it owns. For
  a car another client owns, it asks for control (`NetworkRequestControlOfEntity`)
  and waits up to `controlWaitMs`, but only when this player caused the spin-out
  (shot it, or damaged it with their ped or car). A spin-out nobody here caused, on
  a car someone else's client owns, is left to that client (it happens there if
  that player has SPIN-OUTS on). Two players who both have it on can, rarely, both
  push the same car.
- **Other players' cars.** Single player skips the car the player drives. Here a
  car with any other player in any seat, or last driven by another player, is left
  alone too. Your own car is spun out only by your own client.
- **Script cars.** Single player leaves another script's mission cars alone
  (`IsEntityAMissionEntity` and not `DoesEntityBelongToThisScript`, car or driver).
  The same test here leaves alone every car a resource spawned: garage cars, job
  vehicles, cars other players spawned. It is made at the half-second scan rather
  than every frame.
- **Your own car.** In single player this spin-out is part of GTA6Hud's crash
  impacts (`[Driving] Impacts`), which also shake the pad, add damage and break
  doors and tyres. Only the spin-out is ported; `impacts` and `impactMin` are its
  settings.
- **Grip always comes back.** Single player pauses the whole check while you are
  dead, so a car's grip stays cut until you respawn; here grip comes back on time.
  Switching the row off also forgets queued rolls and the readings (single player
  kept the roll queue and could roll a car when switched back on). Grip is put back
  on this client's copy of a car even after another client has taken it over.
