-- Nitrous purchasing, surfaced inside um_customs' Performance menu.
--
-- StreetKings' own tuning shop (modules/shop, 1,518 lines) is not ported —
-- um_customs already does visual mods, performance mods, colours, wheels and
-- neon. The only thing it has no concept of is nitrous, so that is all this
-- adds, as one extra row in the menu players already use.
--
-- ── How the hook works ──────────────────────────────────────────────────────
-- um_customs has no exports and no extension points, so it carries a small
-- marked block in `client/menus/performance.lua` that calls the two exports
-- below. All the logic lives here, so re-applying the hook after a um_customs
-- update is a copy-paste of a comment-delimited block, not a port.
--
-- Two constraints shape the contract:
--   * um_customs calls `option.set()` on every side-scroll to preview a mod.
--     Purchasing there would charge the player for scrolling, so `set` is a
--     no-op and the real work hangs off `skPurchase`, which the hook calls only
--     on submit.
--   * um_customs' InstallMod() routes payment through ITS price table, and an
--     unknown mod id would index a nil server-side. Our row never touches that
--     path; it pays through sk_streetkings' own callback.

if not Config.Modules.nitrous then return end

SKTuningClient = {}

-- Menu row order. Index 1 is "no bottle".
local TIER_ORDER = { 'street', 'sport', 'race' }

---@param veh integer
---@return string|nil
local function plateOf(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return nil end
    return (plate:gsub('%s+$', ''))
end

---@return string description line listing every tier and its price
local function priceLabel()
    local parts = {}
    for _, tier in ipairs(TIER_ORDER) do
        local price = Config.Nitrous.prices[tier]
        if price then
            parts[#parts + 1] = ('%s %s'):format(
                Config.Nitrous.tiers[tier] and Config.Nitrous.tiers[tier].label or tier,
                SKFormatMoney(price)
            )
        end
    end
    return table.concat(parts, ' | ')
end

--- Builds the Nitrous row for um_customs' Performance menu.
---
--- Returns a list so the hook can splice it in without caring how many rows
--- this resource contributes.
---@param vehicle integer
---@return table[] options
function SKTuningClient.getPerformanceMenuOptions(vehicle)
    local plate = plateOf(vehicle)
    if not plate then return {} end

    local current = lib.callback.await('sk_streetkings:tuning:getNitrous', false, plate)

    local labels = { 'None' }
    local defaultIndex = 1
    for i, tier in ipairs(TIER_ORDER) do
        local def = Config.Nitrous.tiers[tier]
        labels[i + 1] = def and def.label or tier
        if current == tier then defaultIndex = i + 1 end
    end

    return {
        {
            id           = 'sk_nitrous',
            label        = 'Nitrous',
            description  = priceLabel(),
            values       = labels,
            close        = true,
            defaultIndex = defaultIndex,

            -- Preview only. um_customs fires this on every side-scroll, so it
            -- must never charge or change anything.
            set = function()
                return false, ''
            end,

            restore = function() end,

            -- Called by the hook on submit, in place of um_customs' InstallMod.
            skPurchase = function(index)
                local tier = TIER_ORDER[index - 1] -- index 1 is None

                if tier == current or (tier == nil and current == nil) then
                    lib.notify({
                        title = 'Nitrous',
                        description = 'That is already what this vehicle has.',
                        type = 'error',
                    })
                    return
                end

                local result = lib.callback.await('sk_streetkings:tuning:buyNitrous', false, plate, tier)

                if not result or not result.ok then
                    lib.notify({
                        title = 'Nitrous',
                        description = result and result.reason or 'Purchase failed.',
                        type = 'error',
                    })
                    return
                end

                current = result.tier

                if result.tier then
                    local def = Config.Nitrous.tiers[result.tier]
                    lib.notify({
                        title = 'Nitrous',
                        description = ('%s fitted.'):format(def and def.label or result.tier),
                        type = 'success',
                    })
                else
                    lib.notify({ title = 'Nitrous', description = 'Nitrous removed.', type = 'inform' })
                end

                -- Tell the nitrous module to re-read the bottle immediately
                -- rather than waiting for its next poll.
                TriggerEvent('sk_streetkings:nitrous:refresh')
            end,
        },
    }
end

-- Consumed by the hook block in um_customs/client/menus/performance.lua.
exports('GetPerformanceMenuOptions', SKTuningClient.getPerformanceMenuOptions)

-- ── Mod shop (Lenonida_customs) ───────────────────────────────────────
-- The mod shop sells nitrous in its own Performance tab. It cannot see this
-- resource's config or callbacks, so these two exports are the whole contract.
-- They go through the same server callbacks as the row above: same prices, same
-- ownership rule, same `sk_vehicle_upgrades` storage.

--- What the shop needs to list nitrous for a vehicle.
---@param vehicle integer
---@return { current: string|nil, tiers: { id: string, label: string, price: number }[] }|nil
exports('GetNitrousShop', function(vehicle)
    local plate = plateOf(vehicle)
    if not plate then return nil end

    local tiers = {}
    for _, tier in ipairs(TIER_ORDER) do
        local def = Config.Nitrous.tiers[tier]
        tiers[#tiers + 1] = {
            id    = tier,
            label = def and def.label or tier,
            price = Config.Nitrous.prices[tier] or 0,
        }
    end

    return {
        current = lib.callback.await('sk_streetkings:tuning:getNitrous', false, plate),
        tiers   = tiers,
    }
end)

--- Buys `tier` for the vehicle; nil removes the bottle.
---@param vehicle integer
---@param tier string|nil
---@return { ok: boolean, reason: string|nil, tier: string|nil }
exports('BuyNitrous', function(vehicle, tier)
    local plate = plateOf(vehicle)
    if not plate then return { ok = false, reason = 'Could not read that vehicle\'s plate.' } end

    local result = lib.callback.await('sk_streetkings:tuning:buyNitrous', false, plate, tier)
    if not result or not result.ok then
        return { ok = false, reason = result and result.reason or 'Purchase failed.' }
    end

    -- Same as the menu row: have the nitrous module re-read the bottle now.
    TriggerEvent('sk_streetkings:nitrous:refresh')
    return { ok = true, tier = result.tier }
end)
