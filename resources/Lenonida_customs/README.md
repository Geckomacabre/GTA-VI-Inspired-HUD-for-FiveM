# Leonida Customs

A full screen mod shop and mechanic job for FiveM, styled after the GTA VI mod shop: slanted tabs, a vehicle card with live stat bars, an orbit camera, Pro Builds, and a working nitrous system.

Built on [renzu_customs](https://github.com/renzuzu/renzu_customs) by Renzuzu. The mechanic features of the original (stock room, parts inventory, spray cans, engine swaps, turbo kits, tire compounds) are still here; the upgrade menu, its pricing and the nitrous system are new.

## Features

**Upgrade menu**
- Three tabs: **Pro Builds**, **Cosmetics**, **Performance**. Categories with one part type open straight on their options, the rest list their part types first.
- Options are shown one at a time with a `2 / 3` counter and their status: `Not owned` with the price, or `Applied`. Every option is previewed on the vehicle before you buy it.
- Parts are bought one at a time. Buying shows a `Purchased` confirmation and the option becomes `Applied`.
- Vehicle card with five stat bars (Speed, Acceleration, Asphalt Handling, Off-Road Handling, Strength) and road / off-road ratings. The bars show the factory value as a tick and the change an option would make in green or red.
- Respray with swatches grouped by colour family, including the gen9 chameleon paints, pearlescent, wheel colour and custom RGB.
- Pro Builds: one purchase that fits a whole set of parts at a fixed price.
- Orbit camera with a view per category (engine bay with the hood open, wheels, cabin, plate and so on). Drag to look around, scroll to zoom.
- Repair prompt on the way in when the vehicle is damaged.

**Nitrous**
- Kits sold under Performance > Nitrous. Hold the boost key to boost; the tank drains, refills on its own and locks out briefly when run dry.
- Stored by plate on the server and kept across restarts.
- Publishes its state for HUDs (see [HUD integration](#hud-integration)).

**Mechanic job** (from renzu_customs)
- Multiple shops, each tied to a job, with job grades per upgrade type.
- Stock room, parts inventory and installing / removing parts by hand.
- Spray cans in the paint room, with a custom colour picker.
- Engine swaps (sound and handling of another vehicle), turbo kits with blow off valve sounds, and tire compounds.

## Requirements

- **Framework**: ESX (v1 final, Legacy), QBCore, or Qbox through its qb-core bridge.
- **Database**: oxmysql or mysql-async.
- OneSync.

Optional:

| Resource | Used for |
|---|---|
| [renzu_contextmenu](https://github.com/renzuzu/renzu_contextmenu) | stock room, parts inventory and spray can menus |
| [renzu_popui](https://github.com/renzuzu/renzu_popui) | interaction prompts, when `Config.usePopui` is on |
| [renzu_notify](https://github.com/renzuzu/renzu_notify) | notifications from the mechanic features |
| [renzu_progressbar](https://github.com/renzuzu/renzu_progressbar) | repair progress bar, when `Config.UseRenzu_progressbar` is on |
| [renzu_jobs](https://github.com/renzuzu/renzu_jobs) | job money, when `Config.UseRenzu_jobs` is on |
| [renzu_garage](https://github.com/renzuzu/renzu_garage) | restoring engine swaps, turbo kits and tire compounds from saved vehicle props |

Society accounts are found automatically on QBCore / Qbox: Renewed-Banking, then qb-banking, then qb-management. ESX uses esx_addonaccount.

## Installation

1. Put the folder in your resources. Any folder name works.
2. Nothing to import: the `renzu_customs` table (the parts inventory of each shop) is created on first start. The `.sql` files are there if you would rather create it yourself.
3. If you run renzu_shield, add `shared_script '@renzu_shield/init.lua'` back at the top of `fxmanifest.lua`.
4. Set up `config.lua` (see below) and add `ensure <folder name>` to your server.cfg, after your framework and database.

## Configuration

**`config.lua`**: framework, shops, costs and the mechanic features.

```lua
Config.framework = 'auto' -- "auto", "ESX", "QBCORE" (Qbox: "auto" or "QBCORE")
Config.Mysql = 'mysql-async' -- "mysql-async", "oxmysql", "ghmattisql"
Config.JobPermissionAll = false -- false: anyone can use the upgrade menu and pays with their own money
                                -- true: only the shop's job can use it, and the shop account pays
Config.OwnedVehiclesOnly = false -- only vehicles in the owned vehicles table can be upgraded
Config.RepairCost = 1500
Config.EnableDiscounts = false -- job discounts, global (Config.JobDiscounts) or per upgrade type
Config.FreeUpgradeToClass = { [18] = true, [19] = true } -- vehicle classes that upgrade for free
```

- `Config.Customs`: the shops. Each has a radius and upgrade spots (`mod`). `job` and the stock room, paint room and parts inventory positions are optional: a shop without them is a plain public mod shop. The defaults are the five Los Santos Customs (public) and Benny's (run by the `mechanic` job).
- `Config.VehicleMod`: every upgrade type with its cost, `percent_cost`, job grades and discounts. `multicostperlvl = true` charges the cost times the level.
- `Config.VehicleValuetoFormula`: price upgrades from the value of the vehicle instead of the fixed cost.

**`config_menu.lua`**: everything about the upgrade menu.

- `Config.ShopLabels`: the title shown top left, per shop.
- `Config.Menu`: tabs, categories and the slots in each. Slots a vehicle has no parts for are hidden, and so are categories and tabs that end up empty.
- `Config.ProBuilds`: the kits. `'max'` fits the best part a vehicle has for that slot. `price` is what the whole kit costs; a vehicle that takes fewer of its parts, or already has some, pays the cost of the parts it actually gets instead, never more.
- `Config.PadGlyphs`: `'xbox'` or `'playstation'`, the button names shown while a controller is in use.
- `Config.PayAccounts`: the accounts customers pay from, in order. Default cash, then bank.
- `Config.ExtraPrices`: prices of wheel colour, pearlescent, chameleon and custom RGB paint, tire smoke, drift and bulletproof tires.

The default prices are tiered: small items (horn, plates, tint, extras) $500 to $2,500, body and interior parts $2,000 to $6,000, a respray $3,500 to $6,000 with chameleon and custom colours above that, wheels $4,000 to $6,000, and performance upgrades $15,000 per level.
- `Config.StatEffects`: how much each upgrade moves the bars on the vehicle card. This only changes what the card shows, not how the vehicle drives.
- `Config.NitrousSystem`: `'builtin'`, `'streetkings'` or `'auto'` (see [Nitrous from sk_streetkings](#nitrous-from-sk_streetkings)).
- `Config.Nitrous` and `Config.VehicleMod['nitrous']`: boost key, refill behaviour, and the built-in kits (`power`, `duration`, `recharge`, `value`).
- `Config.MenuDepthOfField`: blur the background behind the vehicle.

## Controls

| Keyboard / mouse | Controller | Action |
|---|---|---|
| W A S D / arrows | D-pad / left stick | move, change option |
| Q / E | LB / RB | previous / next tab or colour group |
| Enter / Space | A | select, buy |
| Backspace / Esc | B | back, exit |
| R (hold) | X (hold) | rev the engine |
| Tab | Y | vehicle card page: name, stats, fitted parts |
| Mouse drag / scroll | Right stick / LT RT | look around the vehicle, zoom |
| Left Shift (hold, while driving) | L3, left stick press (hold, while driving) | nitrous boost, both rebindable under Settings > Key Bindings > FiveM |

The prompts show the buttons of whichever was used last. `Config.PadGlyphs` switches the controller names between Xbox and PlayStation. Custom colours (the colour picker) need a mouse.

`/freecustoms` opens the menu on the vehicle you are in, anywhere, with everything free. Admins only.

## How pricing works

The client never tells the server what something costs. When a part is bought, the server compares the props the vehicle came in with to the props it is leaving with, and prices the difference with the same code the menu uses to show prices (`shared/customs.lua`). Anything that is not for sale is refused.

Who pays:
- `Config.JobPermissionAll = true`: the shop's society account. If the server has no account for the job, the mechanic pays.
- `Config.JobPermissionAll = false`: the customer, and the money goes to the shop's society account.

## HUD integration

The menu has no money display of its own, your HUD is expected to draw it. While the menu is open `LocalPlayer.state['customs:menuOpen']` is `true` and the local event `customs:menu` fires with `true`, then `false` on close. The game's own HUD and radar are hidden while it is open.

Nitrous state is in `LocalPlayer.state['customs:nitrous']` (not replicated) and is also sent as the local event `customs:nitrous`:

```lua
{
    installed = true,           -- the player is driving a vehicle with a kit, false = hide the gauge
    kit = 'Street',             -- Config.VehicleMod['nitrous'].list key
    label = 'Street 50 Shot',
    level = 0.82,               -- tank, 0.0 - 1.0
    active = false,             -- boosting right now
    ready = true,               -- false while locked out after running the tank dry
    command = '+customsnitrous' -- key mapping command of the boost key
}
```

It is written whenever something changes and about ten times a second while the tank level is moving.

## Nitrous from sk_streetkings

If the server runs sk_streetkings, its nitrous is used instead of the built-in one (`Config.NitrousSystem = 'auto'`): the Nitrous category sells the StreetKings tiers at StreetKings' prices, and StreetKings does the boosting, refilling and storing. Nothing nitrous-related in this resource runs, and Pro Builds skip their nitrous part.

It needs two exports in sk_streetkings (`modules/tuning/tuning_c.lua`): `GetNitrousShop(vehicle)` returning `{ current = tier or nil, tiers = { { id, label, price }, ... } }`, and `BuyNitrous(vehicle, tier)` returning `{ ok, reason, tier }`. For the HUD, sk_streetkings writes the same `customs:nitrous` state bag described above, with `key` (a control id) in place of `command`.

## Mission hooks

The menu has no objective text of its own. A mission that sends the player to the mod shop can add one:

```lua
exports[resource]:SetMenuObjective('Apply the ~nitrous boost~ mod', 'nitrous') -- line at the bottom, ~words~ highlighted
exports[resource]:SetMenuObjective('Exit the mod shop') -- text only
exports[resource]:SetMenuObjective() -- clear
```

The optional second argument is a slot (see `config_menu.lua`): its tab gets a tag, its category a dot. The local event `customs:purchased` fires after every purchase with a table of slot > value, so the mission can move on:

```lua
AddEventHandler('customs:purchased', function(changes)
    if changes['nitrous'] and changes['nitrous'] ~= 'Default' then
        exports[resource]:SetMenuObjective('Exit the mod shop')
    end
end)
```

## Exports

Client:

```lua
exports[resource]:GetVehicleProperties(vehicle) -- props, including the custom upgrades
exports[resource]:SetVehicleProp(vehicle, props)
exports[resource]:GetVehicleEngine(vehicle)
exports[resource]:SetVehicleEngine(vehicle, model) -- 'Default' removes the swap
exports[resource]:GetVehicleTurbo(vehicle)
exports[resource]:SetVehicleTurbo(vehicle, turbo) -- 'Street', 'Sports', 'Racing', 'Default'
exports[resource]:SetVehicleHandlingSpec(vehicle, model)
exports[resource]:GetHandlingfromModel(model, vehicle)
exports[resource]:GetVehicleValue(modelhash)
exports[resource]:GetVehicleNitrous(vehicle) -- kit name or 'Default'
exports[resource]:GetNitrousState() -- the table above
```

Server:

```lua
exports[resource]:SetVehicleNitrous(plate, kit) -- 'Default' removes it
exports[resource]:GetVehicleNitrous(plate)
```

## Fonts and logos

Text is set in GTA Art Deco (bundled in `html/fonts`). Headings use Bahnschrift Condensed, which ships with Windows 10 and 11. To use another heading font, change `--font-display` in `html/style.css`.

The manufacturer mark on the vehicle card comes from `html/logos` and `html/makes.js`, the same files [vice_hud](https://github.com/Geckomacabre/GTA-VI-UI-and-HUD-for-FiveM) ships. Vehicles with no known make, which includes most addon vehicles, show no mark.

## Notes

- Engine swaps, turbo kits and tire compounds are kept in memory by plate and in the saved vehicle props. They come back after a restart only if your garage restores props through `SetVehicleProp`. Nitrous does not need this.
- The Intakes category uses the game's air filter mod, which only some vehicles have.
- The demo shop positions are Benny's and the [Tuner Auto Shop MLO](https://forum.cfx.re/t/free-mlo-tuner-auto-shop/4247145). Change `Config.Customs` for your own maps.

## Credits

- [renzu_customs](https://github.com/renzuzu/renzu_customs) by Renzuzu, the resource this is built on.
- Vehicle property getter and setter from [es_extended](https://github.com/esx-framework/es_extended).

Licensed under the GNU General Public License v3.0, see [LICENSE](LICENSE).
