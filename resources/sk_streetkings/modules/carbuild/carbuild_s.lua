-- Car building: validation, economy, and vehicle registration for both
-- Assemble (instant, materials + cash) and Wreck Lot (buy cheap + restore in
-- paid stages). See modules/carbuild/carbuild_c.lua for the menus and
-- Config.CarBuild for the numbers.
--
-- New vehicles are registered through qbx_vehicles' own CreatePlayerVehicle
-- export — the same path any other vehicle shop on this server would use —
-- rather than hand-rolling a player_vehicles INSERT here.

if not Config.Modules.carBuild then return end

local cfg = Config.CarBuild

-- In-progress wreck restorations, keyed by citizenid rather than source so a
-- disconnect mid-restoration doesn't lose progress. Not its own SQL table —
-- this is small transient state, and the vehicle itself (with whatever
-- health it currently has) is what actually persists, via player_vehicles,
-- same as any other owned car.
---@type table<string, {plate: string, stage: integer, stagesTotal: integer}>
local wreckBuilds = {}

local lastAssembleAt = {} -- source -> GetGameTimer() of their last successful assemble

---@param src integer
---@return string|nil
local function citizenidFor(src)
    local player = exports.qbx_core:GetPlayer(src)
    return player and player.PlayerData.citizenid or nil
end

---@param src integer
---@param materials table[] { item, amount }
---@return boolean ok, table|nil missing
local function hasMaterials(src, materials)
    for _, m in ipairs(materials) do
        local count = exports.ox_inventory:GetItemCount(src, m.item) or 0
        if count < m.amount then return false, m end
    end
    return true
end

---@param src integer
---@param materials table[] { item, amount }
local function removeMaterials(src, materials)
    for _, m in ipairs(materials) do
        exports.ox_inventory:RemoveItem(src, m.item, m.amount)
    end
end

-- ── Assemble a racer ─────────────────────────────────────────────────────

lib.callback.register('sk_streetkings:carbuild:assemble', function(source, stationCoords)
    local src = source
    local citizenid = citizenidFor(src)
    if not citizenid then return false, 'Not loaded.' end

    local a = cfg.assemble
    local now = GetGameTimer()
    if lastAssembleAt[src] and (now - lastAssembleAt[src]) < a.cooldownMs then
        local remainSec = math.ceil((a.cooldownMs - (now - lastAssembleAt[src])) / 1000)
        return false, ('Workshop is busy — %ds left.'):format(remainSec)
    end

    local hasMats, missing = hasMaterials(src, a.materials)
    if not hasMats then
        return false, ('Missing materials — need more %s.'):format(missing.item)
    end
    if SKPlayer.getMoney(src) < a.cashCost then
        return false, ('Need %s for parts and labour.'):format(SKFormatMoney(a.cashCost))
    end

    removeMaterials(src, a.materials)
    if a.cashCost > 0 then
        SKPlayer.removeMoney(src, a.cashCost, 'sk-carbuild-assemble')
    end

    local props = { engineHealth = 1000.0, bodyHealth = 1000.0, fuelLevel = 100.0 }
    local vehicleId = exports.qbx_vehicles:CreatePlayerVehicle({
        model     = a.vehicleModel,
        citizenid = citizenid,
        props     = props,
    })

    if not vehicleId then
        -- Materials are already gone (mistakes here shouldn't hand out a free
        -- car on retry), but the cash is refundable.
        if a.cashCost > 0 then SKPlayer.addMoney(src, a.cashCost, 'sk-carbuild-refund') end
        return false, 'Something went wrong — cash refunded.'
    end

    lastAssembleAt[src] = now

    local coords = (type(stationCoords) == 'table' and stationCoords.x)
        and vector3(stationCoords.x, stationCoords.y, stationCoords.z)
        or GetEntityCoords(GetPlayerPed(src))
    TriggerClientEvent('sk_streetkings:carbuild:spawnVehicle', src, a.vehicleModel, props, coords)

    if Config.Modules.stats then
        SKStats.increment(src, 'totalCashSpent', a.cashCost)
    end

    return true, 'Racer assembled — check outside.'
end)

-- ── Wreck Lot: buy ────────────────────────────────────────────────────────

lib.callback.register('sk_streetkings:carbuild:buyWreck', function(source)
    local src = source
    local citizenid = citizenidFor(src)
    if not citizenid then return false, 'Not loaded.' end

    if wreckBuilds[citizenid] then
        return false, 'You already have a wreck being restored — finish that one first.'
    end

    local w = cfg.wreckLot
    local price = math.random(w.priceMin, w.priceMax)
    if SKPlayer.getMoney(src) < price then
        return false, ('Need %s for a wreck.'):format(SKFormatMoney(price))
    end

    SKPlayer.removeMoney(src, price, 'sk-carbuild-wreck')

    local model = w.models[math.random(#w.models)]
    local startHealth = math.random(w.startHealthMin, w.startHealthMax) + 0.0
    local props = { engineHealth = startHealth, bodyHealth = startHealth, fuelLevel = 50.0 }

    local vehicleId = exports.qbx_vehicles:CreatePlayerVehicle({
        model     = model,
        citizenid = citizenid,
        props     = props,
    })
    if not vehicleId then
        SKPlayer.addMoney(src, price, 'sk-carbuild-refund')
        return false, 'Something went wrong — cash refunded.'
    end

    local plate = MySQL.scalar.await('SELECT plate FROM player_vehicles WHERE id = ?', { vehicleId })
    if plate then
        wreckBuilds[citizenid] = { plate = plate, stage = 0, stagesTotal = w.restoreStages }
    end

    TriggerClientEvent('sk_streetkings:carbuild:spawnVehicle', src, model, props,
        vector3(w.coords.x, w.coords.y, w.coords.z))

    return true, ('Bought a %s for %s. Bring it to any repair station to start restoring it.'):format(
        model, SKFormatMoney(price))
end)

-- ── Wreck Lot: restore in stages ─────────────────────────────────────────

lib.callback.register('sk_streetkings:carbuild:restoreStage', function(source, plate)
    local src = source
    local citizenid = citizenidFor(src)
    if not citizenid then return false, 'Not loaded.' end

    local build = wreckBuilds[citizenid]
    if not build then
        return false, 'No wreck in progress — buy one from the Wreck Lot first.'
    end

    plate = type(plate) == 'string' and plate:gsub('%s+', '') or nil
    if not plate or plate ~= build.plate then
        return false, "That's not your wreck."
    end
    if build.stage >= build.stagesTotal then
        wreckBuilds[citizenid] = nil
        return false, 'Already fully restored.'
    end

    local w = cfg.wreckLot
    local hasMats, missing = hasMaterials(src, w.materialsPerStage)
    if not hasMats then
        return false, ('Missing materials — need more %s.'):format(missing.item)
    end
    if SKPlayer.getMoney(src) < w.cashCostPerStage then
        return false, ('Need %s for this stage.'):format(SKFormatMoney(w.cashCostPerStage))
    end

    removeMaterials(src, w.materialsPerStage)
    if w.cashCostPerStage > 0 then
        SKPlayer.removeMoney(src, w.cashCostPerStage, 'sk-carbuild-restore')
    end

    build.stage = build.stage + 1

    -- Wreck-start health up to full, linear across the stage count.
    local frac   = build.stage / build.stagesTotal
    local health = w.startHealthMax + (1000.0 - w.startHealthMax) * frac

    TriggerClientEvent('sk_streetkings:carbuild:applyHealth', src, plate, health)

    if Config.Modules.stats then
        SKStats.increment(src, 'totalCashSpent', w.cashCostPerStage)
    end

    if build.stage >= build.stagesTotal then
        wreckBuilds[citizenid] = nil
        return true, 'Fully restored — that wreck is race-ready.'
    end
    return true, ('Stage %d/%d complete.'):format(build.stage, build.stagesTotal)
end)
