-- Per-vehicle nitrous purchases.
--
-- StreetKings sold nitrous from its own tuning shop (modules/shop), which is
-- not ported — um_customs owns vehicle mods on this server. Only the parts
-- um_customs has no concept of live here: nitrous is not a native GTA vehicle
-- mod, so it cannot ride along in the `player_vehicles.mods` blob um_customs
-- saves. It gets its own plate-keyed row instead.
--
-- Prices and tiers come from Config.Nitrous. The client never sends a price.

if not Config.Modules.nitrous then return end

SKTuning = {}

local PURCHASE_COOLDOWN_MS = 1500

local nitrousByPlate = {} -- plate -> tier
local lastPurchase   = {} -- src -> timestamp

---@param plate string|nil
---@return string|nil normalised plate
local function normalisePlate(plate)
    if type(plate) ~= 'string' then return nil end
    plate = plate:gsub('%s+$', '')
    if plate == '' or #plate > 12 then return nil end
    return plate
end

local function loadUpgrades()
    local rows = MySQL.query.await('SELECT `plate`, `nitrous_tier` FROM `sk_vehicle_upgrades`') or {}
    for _, row in ipairs(rows) do
        if row.nitrous_tier ~= '' then
            nitrousByPlate[row.plate] = row.nitrous_tier
        end
    end
    print(('^2[sk_streetkings]^0 Loaded nitrous for %d vehicle(s).'):format(#rows))
end

MySQL.ready(loadUpgrades)

--- The tier fitted to a plate, or the free default if one is configured.
---@param plate string|nil
---@return string|nil
function SKTuning.getNitrous(plate)
    plate = normalisePlate(plate)
    if not plate then return Config.Nitrous.defaultTier end
    return nitrousByPlate[plate] or Config.Nitrous.defaultTier
end

lib.callback.register('sk_streetkings:tuning:getNitrous', function(_, plate)
    return SKTuning.getNitrous(plate)
end)

---@param plate string
---@return boolean
local function isOwnedVehicle(plate)
    if not Config.Nitrous.requireOwnedVehicle then return true end
    return MySQL.scalar.await('SELECT 1 FROM `player_vehicles` WHERE `plate` = ?', { plate }) ~= nil
end

--- Buys (or removes) a nitrous tier for one vehicle.
---@param source integer
---@param plate string
---@param tier string|nil nil or '' removes the bottle
---@return { ok: boolean, reason: string?, tier: string? }
lib.callback.register('sk_streetkings:tuning:buyNitrous', function(source, plate, tier)
    plate = normalisePlate(plate)
    if not plate then
        return { ok = false, reason = 'Could not read that vehicle\'s plate.' }
    end

    local now = GetGameTimer()
    if lastPurchase[source] and now - lastPurchase[source] < PURCHASE_COOLDOWN_MS then
        return { ok = false, reason = 'Slow down.' }
    end
    lastPurchase[source] = now

    if not SKSaves.hasActiveSave(source) then
        return { ok = false, reason = 'Profile not loaded.' }
    end

    if not isOwnedVehicle(plate) then
        return { ok = false, reason = 'Nitrous can only be fitted to a vehicle you own.' }
    end

    local current = nitrousByPlate[plate]

    -- Removing the bottle. No refund, matching how every other mod works.
    if tier == nil or tier == '' then
        if not current then
            return { ok = false, reason = 'This vehicle has no nitrous fitted.' }
        end
        nitrousByPlate[plate] = nil
        MySQL.query.await('DELETE FROM `sk_vehicle_upgrades` WHERE `plate` = ?', { plate })
        return { ok = true, tier = nil }
    end

    local price = Config.Nitrous.prices[tier]
    if not price or not Config.Nitrous.tiers[tier] then
        return { ok = false, reason = 'Unknown nitrous tier.' }
    end

    if current == tier then
        return { ok = false, reason = 'Already fitted.' }
    end

    -- Price comes from config, never from the client.
    if not SKPlayer.removeMoney(source, price, 'sk-nitrous-purchase') then
        if not SKPlayer.removeMoney(source, price, 'sk-nitrous-purchase', 'bank') then
            return { ok = false, reason = ('You need %s.'):format(SKFormatMoney(price)) }
        end
    end

    nitrousByPlate[plate] = tier
    MySQL.query.await([[
        INSERT INTO `sk_vehicle_upgrades` (`plate`, `nitrous_tier`)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE `nitrous_tier` = VALUES(`nitrous_tier`)
    ]], { plate, tier })

    if Config.Modules.stats then
        SKStats.increment(source, 'totalCashSpent', price)
    end

    return { ok = true, tier = tier }
end)

AddEventHandler('playerDropped', function()
    lastPurchase[source] = nil
end)
