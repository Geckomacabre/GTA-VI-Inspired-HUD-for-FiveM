-- MONEY IN STORES: the money at the top right the whole time you're in a
-- store, as in GTA VI (single player: the fork's ViExtras, ViExtras.ini
-- [Switches] MoneyInStores).
return {
    -- false: the money shows in stores only with a shop's menu open, for
    -- everyone, and there is no MONEY IN STORES row
    enabled = true,

    -- What the row starts on for a player who has never switched it.
    -- Single player: [Switches] MoneyInStores = True.
    default = true,
}
