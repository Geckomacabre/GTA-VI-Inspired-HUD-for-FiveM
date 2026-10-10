# vi_wasted

The **WASTED** and **BUSTED** screens: the stock death effect, slow motion, a
camera that starts close behind you and pulls back and up, a red wash over the
picture, and the bare word in Pricedown.

These are not new. They are the two cinematics from the
[fenix-police fork](https://github.com/Geckomacabre/fenix-police)
(`client/client.lua`), lifted out so a server can have them without the rest
of that resource. The look and the numbers are its own.

## What it does

- **WASTED** plays when `qbx_medical` reports the player dead, or when
  `exports.vi_wasted:PlayWasted()` is called. It fades to black, fires
  `vi_wasted:wastedFadedOut`, and fades back in.
- **BUSTED** plays only when asked for:
  `exports.vi_wasted:PlayBusted({ coords = vector3, duration = ms, skippable = bool })`.
  It ends on a **black screen** and fires `vi_wasted:bustedFadedOut`; what
  being busted leads to (a cell, a fine) and fading back in are the caller's.
  fenix-police's own arrest goes on to cuffs and a ride; none of that is here.
- `exports.vi_wasted:IsPlaying()` says whether either is on screen.

`/wasted` and `/busted` play them for testing (`Config.TestCommands`).

## If you run fenix-police

Do nothing. It plays both screens itself, and this resource stands down while
it is running (`Config.StandDownFor`), so a death is not announced twice.

## Install

Copy the folder into `resources/` and `ensure vi_wasted`. No dependencies.
Colours, durations and the slow-motion factor are in `config.lua`.

## Licence

GPL-3.0, the licence of the resource this code comes from. See `LICENSE`.
