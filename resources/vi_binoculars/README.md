# vi_binoculars

Binoculars that behave: raise them, look around, zoom smoothly, lower them.

- **Smooth zoom.** Roll the mouse wheel, or hold the triggers (LMB / RMB on a
  mouse). The picture glides to where you asked for instead of stepping, from
  a 42° field of view down to 4°.
- **Mouse and controller.** Looking slows down as you zoom in, so a small
  movement stays small at full zoom on either.
- **Your character does it too.** The ped takes the binocular stance and turns
  with the view, so other players see someone scanning, not a statue.
- **The GTA VI lens.** With `vice_hud` running, the lens-shaped mask, the
  `ZOOM` and `EXIT` prompts (drawn as the player's own controller buttons or
  keys) and the label naming what is being looked at are its own. Without it,
  the game's stock binocular overlay is used.

## Using them

| | |
| --- | --- |
| `/binoculars` | raise or lower (`Config.Command`) |
| a key | `Config.Key`, rebindable per player; off by default |
| an item | `Config.Item = 'binoculars'`; see below |
| Mouse wheel, or hold LMB / RT | zoom in |
| Mouse wheel, or hold RMB / LT | zoom out |
| Backspace / B | lower them |

They cannot be raised in a vehicle, in water, while falling, cuffed or dead,
and come down on their own if any of that happens.

## The item

With `Config.Item` set, the command and key only work while the player is
carrying one. Set it to `false` to need no item.

**ox_inventory** — add to `data/items.lua`:

```lua
['binoculars'] = {
    label = 'Binoculars',
    weight = 600,
    stack = false,
    client = { export = 'vi_binoculars.useItem' },
},
```

**qbx_core / qb-core** — nothing to do: the usable item is registered for you
(`server.lua`). The item itself still has to exist in your items list.

## For other scripts

```lua
exports.vi_binoculars:Use()        -- raise, or lower if they are up
exports.vi_binoculars:Stop()
exports.vi_binoculars:IsActive()
exports.vi_binoculars:GetZoom()    -- 0 (wide) .. 1 (fully in)

-- Name what is being looked at, bottom left, with the button for `key`
-- beside it (a control id). nil clears it.
exports.vi_binoculars:SetLabel('Phone cases', 38)

-- What the centre of the view is on.
local hit, coords, entity = exports.vi_binoculars:GetTarget(600.0)
```

Local client events: `vi_binoculars:started`, `vi_binoculars:stopped`.

A scouting script would poll `GetTarget` while `IsActive()` and call
`SetLabel` with whatever it finds.

## Install

Copy the folder into `resources/` and `ensure vi_binoculars`. No dependencies.
Everything adjustable (zoom range and speed, look speed, hand sway, stance) is
in `config.lua`.

Not run in game yet from this repository; the logic is covered by a stubbed
test of the zoom, look, limits and clean-up.

## Licence

CC BY-NC-SA 4.0, like the rest of this repository.
