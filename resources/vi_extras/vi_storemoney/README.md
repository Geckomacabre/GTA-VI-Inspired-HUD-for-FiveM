# vi_storemoney

**MONEY IN STORES**, from the fork's ViExtras (single player's `ViExtras.ini`
`[Switches] MoneyInStores`, `Core\StoreMoney.cs`). In GTA VI your money is on screen
from the moment you walk into a store until you walk out, not only with a shop's
menu open. Each player switches it in HUD OPTIONS (hold V); `config.enabled = false`
takes it away from everyone.

## What it does (single player's numbers)

Every 400 ms, 3 s after a loading screen or character switch: you're in a store
when you're on foot, indoors (`GetInteriorFromEntity` not 0) and within 12 m across
and 4 m up or down (each axis on its own) of one of the store points below. While
you are, vice_hud's cash and bank rows stay up; the next check after you leave
lets them go.

## Needs vice_hud's `SetMoneyShown`

vice_hud draws the money and shows the rows only with the item wheel or an
inventory open (ox_inventory's shops included) or at an ATM. This calls

```lua
exports.vice_hud:SetMoneyShown(on, source)   -- source: 'vi_extras:storemoney'
```

on entering and leaving a store, again when vice_hud restarts, and with `false`
when switched off or stopped. vice_hud keeps the rows up while any source holds
it on (as with the wheel). Until vice_hud has the export, one `^1[vi_extras]^7`
line says so and nothing else happens.

## What counts as a store

Single player's stores are where GTA6Hud sells things: a 24/7's shelves, a clothes
rack or barber's chair, an Ammu-Nation till. Here they are where this server sells
things, read when the resource starts and again when either resource restarts:

- **ox_inventory**: every shop in `data/shops.lua` anyone can use (no `groups` or
  `jobs`, not a vending-machine `model`): its `locations` and its `targets`' `loc`.
  On this server 108 points over 26 shops (24/7s, Ammu-Nation, liquor stores,
  YouTool, the dealers...). Outdoor ones (a hot dog stand) never count: you have to
  be indoors.
- **illenium-appearance**: its `clothing` and `barber` stores in `Config.Stores` (the
  store's spot and its zone's corners), and every clothes rack in `Config.RackSpots`.
  On this server 110 store points and 244 racks. Tattoo parlours are not in
  single player's list.

Both files are read through ox_lib's `lib.load` in a table of their own, so
illenium-appearance's `Config` global doesn't land in vi_extras.

## config.lua

| key | default | single player |
| --- | --- | --- |
| `enabled` | `true` | (FiveM only) the feature and its row at all |
| `default` | `true` | `[Switches] MoneyInStores` |

## Different from single player

- **The store list** is the server's shops instead of GTA6Hud's lists, and every
  point uses StoreMoney's 12 m / 4 m reach. (GTA6Hud's 24/7 test uses 14 m / 5 m
  round its shelves; here a 24/7 is its till.)
- **The money doesn't grey here.** In single player that is the stores' own menus
  (the HUD's stores and Leonida Customs), greying while the item you're on costs
  more than you have. ox_inventory's shop shows every item at once and tells no
  other resource which one you're looking at, so there is no item to compare.
  vice_hud's own shop panel (`ShowShopItem`, used by illenium-appearance's racks
  and barber) already knows (`afford`), but vice_hud hides the money while those
  are open (illenium-appearance's `Config.HideHudMoneyInShops`).
- Single player keeps the money a quarter of a second after you leave; here it
  goes at the next check, up to 400 ms after.
