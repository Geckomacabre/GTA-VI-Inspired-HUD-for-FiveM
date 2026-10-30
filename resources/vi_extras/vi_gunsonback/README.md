# vi_gunsonback: GUNS ON BACK

Single player's GUNS ON BACK (GTA6Hud's `WeaponsOnBack`, `GTA6Hud.ini [WeaponsOnBack]`),
for FiveM. The long guns you carry but aren't holding hang on your back, and every
player near you sees them.

## What it does (as single player)

- **Which guns.** Rifles, machine guns, shotguns, snipers and launchers
  (`GROUP_RIFLE`, `GROUP_MG`, `GROUP_SHOTGUN`, `GROUP_SNIPER`, `GROUP_HEAVY`). Pistols,
  SMGs, melee weapons and throwables never show, and neither does the gun in your hand.
- **How many.** `max` (2). Single player goes through the weapons in hash order and
  takes the first two, so this does the same.
- **Where.** Weapon objects on the upper spine bone (`SKEL_Spine3`, 24817). The 1st
  (3rd...) gun goes at `primary` (0.17, -0.14, 0.11, yaw 168) and the 2nd (4th...) at
  `secondary` (0.17, -0.14, -0.11, yaw 192), so the two cross.
- **In the hand.** While DRAW ANIMATIONS carries a long gun to or from the back, that
  gun goes to the right hand (`SKEL_R_Hand`, 57005) at `handGripX` minus the point
  `anchorFrac` of the way along its model, with no rotation.
- **When.** All of them come off when you're dead or in a vehicle, and they're put back
  when you're not. A change of the gun in hand shows at once. The guns you carry are
  checked again every `recheckSeconds` (0.5). Any change takes every prop down and
  puts the new set up.

## On a server

- **What you carry.** While ox_inventory runs, your weapons are its weapon items
  (`exports.ox_inventory:GetPlayerItems()`). They're read again when it sends
  `ox_inventory:updateInventory`, and every 5 s in case it didn't. ox_inventory only
  ever gives the ped the gun in hand, so the ped can't be asked. Without ox_inventory,
  the ped's own weapons are used, from the game's guns in those groups.
- **Everyone sees them.** Your list goes in your player state bag, `viBack =
  { w = { weapon hashes }, h = the one in the hand }`. It's set only when the list
  changes and cleared when there's nothing to show. Every client hangs its own local,
  non-networked weapon objects on the players within `drawDistance` (50 m, FiveM only),
  so no networked objects are made. A state bag is only data: anything that isn't a real
  gun of the slung kind, or more than `max` of them, is ignored.
- **The row.** GUNS ON BACK in HUD OPTIONS is per player. Off means no props on you for
  anyone, and your state bag is cleared. You still see other players' guns.
  `enabled = false` in config.lua takes the whole feature out.
- **Invisible peds.** A ped that's invisible (an admin's noclip, a spawn screen) gets no
  props, so no guns hang in the air. Single player never needs this.

## Not ported

- `Tune`: single player's numpad live-tuning of the `Primary*` placement. It's a
  developer tool, and here it would put numpad keys on every player.
- `Spread`, `Solo*`, `Right*`, `Left*`: single player reads them but never uses them.
- `OffHand*`, `OffHandGripAlong`, `OffHandTune`: these belong to single player's
  off-hand long gun, which isn't ported (see vi_drawanims/README.md).
- Off ox_inventory, addon weapons aren't found, because the ped's weapons can't be
  listed. With ox_inventory, addon weapon items work.

## Default

`default = false`: single player's ini ships `Enabled = False`, though GTA6Hud's own
default with no ini is True.
