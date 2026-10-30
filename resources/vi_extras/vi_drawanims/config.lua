-- DRAW ANIMATIONS: you reach for a pistol at your hip or a long gun over your
-- shoulder when you draw or put it away (single player: GTA6Hud's equip steps,
-- GTA6Hud.ini [WeaponsOnBack] EquipAnimations). The clips and their timings
-- are single player's own and are fixed there too, so they live in client.lua.
return {
    -- false: no draw animations for anyone and no DRAW ANIMATIONS row
    enabled = true,

    -- What the row starts on for a player who has never switched it.
    -- Single player: [WeaponsOnBack] EquipAnimations = False as shipped
    -- (GTA6Hud's own default, with no ini, is True).
    default = false,
}
