# vi_drawanims: DRAW ANIMATIONS

Single player's DRAW ANIMATIONS (GTA6Hud's equip steps, `GTA6Hud.ini [WeaponsOnBack]
EquipAnimations`), for FiveM. When you draw or put away a gun, you reach for it.

## What it does (as single player)

A switch from one gun to another plays two steps: the old gun's holster clip, then the
new gun's draw clip. Each step plays with `TASK_PLAY_ANIM` (blend 4 / -4, flag 48:
upper body, you keep moving). The gun changes hands at `switchAt`, and the clip lets go
at `blendOutAt`, or 0.5 s after its end at the latest. Standing still uses the full
clip. Walking, running or sprinting (checked once per switch) uses its `_gesture`
version.

| Gun | Step | Dictionary (`mech_inventory@equip@fallback@base@unarmed@`...) | Clip | switchAt | blendOutAt |
|---|---|---|---|---|---|
| Pistol | put away | `rhip` / `rhip_gesture` | holster | 0.19 / 0.26 | 0.40 / 0.30 |
| Pistol | draw | `rhip` / `rhip_gesture` | unholster | 0.14 / 0.15 | 0.46 / 0.24 |
| Long gun | put away | `back@longarms` / `back@longarms_gesture` | holster | 0.32 / 0.18 | 0.72 / 0.30 |
| Long gun | draw | `back@longarms` / `back@longarms_gesture` | unholster | 0.16 / 0.11 | 0.75 / 0.33 |

- A pistol is `GROUP_PISTOL`. A long gun is `GROUP_RIFLE`, `GROUP_MG`,
  `GROUP_SHOTGUN`, `GROUP_SNIPER` or `GROUP_HEAVY`. Anything else (an SMG, a knife)
  has no clip. It goes straight into the hand, after the old gun's clip if there is one.
- Nothing plays when neither gun is a pistol or a long gun, in a vehicle, ragdolling,
  swimming, falling, dead, in first person, or while the mission flag is set. If any of
  those happens mid-way, or the row is switched off, the switch finishes at once.
- Attack, aim and the weapon wheel (controls 24, 25, 37) are held off while a switch plays.
- A long gun going on or off the back is in the right hand between the back and the
  switch point. vi_gunsonback shows it, through the local event `vi_drawanims:hand`.
- If the clips haven't loaded 1.5 s after the switch was asked for, the switch just
  happens.

## The clips must be streamed

The four dictionaries aren't in GTA V. They're single player's own, from its
`vihudanims` pack (copied out of `GTA-VI-Inspired-HUD-Legacy.oiv`), and they're in
`vi_extras/stream/vi_drawanims/`: FiveM only streams a resource's top-level `stream/`
folder. Taking this feature into another resource, take those four files to its `stream/`
as well. Without them, guns switch after the 1.5 s wait and nothing plays.

## On a server

- **With ox_inventory, the gun is ox_inventory's.** It takes the old gun and gives the
  new one at once (a server round trip apart), and switches it back if anything else
  changes the ped's weapon. So the clips play around that switch instead of making it:
  - the old gun is gone at the start of its holster clip, not at `switchAt`. A long
    gun stays in the hand from the start of that clip until it reaches the back;
  - the new gun is in the hand but kept out of sight (`SetPedCurrentWeaponVisible`)
    until its draw clip reaches `switchAt`;
  - ox_inventory sends `ox_inventory:currentWeapon` again when the gun's ammo or
    durability changes. Those repeats are ignored.
- **ox_inventory's own switch animations should be off.** This server has
  `setr inventory:weaponanims 1` in `ox.cfg`. With it on, ox_inventory plays its own
  `reaction@intimidation` clips and holds each switch for 1.2 to 1.4 s, and both sets
  play. Set it to 0.
- **Without ox_inventory,** the game's weapon wheel (or a script) switches the gun
  first. The old gun is put back at once and the switch then plays as in single
  player, with the ped's weapon changed at `switchAt`.
- **Other players** see the clips, because the ped's anim task is synced and every
  client has the streamed dictionaries. They see the hand prop through vi_gunsonback's
  state bag. Whether they also see the new gun kept out of sight depends on the game
  syncing weapon visibility. If it doesn't, they see the gun a moment early.

## Not ported

- **The off-hand long gun.** In single player, going from a long gun to a pistol with
  these animations on keeps the long gun in the left hand (`OffHand*` settings) while
  the pistol is drawn. That runs on single player's one-handed aiming and its
  `arthur@weapons@pistol_1h` clips, and it would need syncing for other players too.
  Here a long gun to a pistol puts the long gun away and draws the pistol.
- **Carrying a body.** Single player plays no clip while you're carrying a body. There's
  no body carrying here.

## Default

`default = false`: single player's ini ships `EquipAnimations = False`, though
GTA6Hud's own default with no ini is True.
