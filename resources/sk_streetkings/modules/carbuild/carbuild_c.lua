-- Car building: assemble a budget racer from scrap materials at any repair
-- station, or buy a cheap wreck from the Wreck Lot and restore it there in
-- paid stages. See Config.CarBuild and modules/carbuild/carbuild_s.lua.
--
-- Reuses SKRepairStations (data/repair_stations.lua) for the "bring it to a
-- repair station" side rather than inventing new locations, and deliberately
-- only shows its own prompt on foot so it never collides with
-- modules/repair's own in-vehicle roadside-repair prompt at the same points.

if not Config.Modules.carBuild then return end

local cfg = Config.CarBuild

local buildPoints  = {}
local wreckLotPoint = nil
local insideAny     = false

---@param maxDist number
---@return integer|nil vehicle
local function findNearbyVehicle(maxDist)
    local playerCoords = GetEntityCoords(cache.ped)
    local best, bestDist

    for _, veh in ipairs(GetGamePool('CVehicle')) do
        local dist = #(GetEntityCoords(veh) - playerCoords)
        if dist <= maxDist and (not bestDist or dist < bestDist) then
            best, bestDist = veh, dist
        end
    end

    return best
end

---@param veh integer
---@return string
local function plateOf(veh)
    return (GetVehicleNumberPlateText(veh):gsub('%s+', ''))
end

-- ── Spawning / applying results the server hands back ──────────────────────

RegisterNetEvent('sk_streetkings:carbuild:spawnVehicle', function(model, props, coords)
    CreateThread(function()
        local hash = GetHashKey(model)
        RequestModel(hash)
        local timeout = GetGameTimer() + 5000
        while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
        if not HasModelLoaded(hash) then return end

        local heading = GetEntityHeading(cache.ped)
        local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)
        SetModelAsNoLongerNeeded(hash)
        SetVehicleOnGroundProperly(veh)
        lib.setVehicleProperties(veh, props)
        SetEntityAsNoLongerNeeded(veh)
    end)
end)

RegisterNetEvent('sk_streetkings:carbuild:applyHealth', function(plate, health)
    plate = (plate or ''):gsub('%s+', '')
    local veh = findNearbyVehicle(15.0)
    if not veh or plateOf(veh) ~= plate then return end

    SetVehicleUndriveable(veh, false)
    SetVehicleEngineHealth(veh, health)
    SetVehicleBodyHealth(veh, health)
    SetVehicleEngineOn(veh, true, true, false)
end)

-- ── Menus ────────────────────────────────────────────────────────────────

local function materialsLine(materials)
    local parts = {}
    for _, m in ipairs(materials) do parts[#parts + 1] = ('%dx %s'):format(m.amount, m.item) end
    return table.concat(parts, ', ')
end

local function openBuildMenu(stationCoords)
    local a = cfg.assemble

    lib.registerContext({
        id = 'sk_carbuild_station',
        title = 'Car Build',
        options = {
            {
                title       = 'Assemble a Racer',
                description = ('%s  +  %s'):format(materialsLine(a.materials), SKFormatMoney(a.cashCost)),
                onSelect    = function()
                    CreateThread(function()
                        local ok, reason = lib.callback.await('sk_streetkings:carbuild:assemble', false, stationCoords)
                        lib.notify({
                            title = 'Car Build', type = ok and 'success' or 'error',
                            description = reason or (ok and 'Racer assembled.' or 'Could not assemble.'),
                        })
                    end)
                end,
            },
            {
                title       = 'Restore My Wreck (next stage)',
                description = 'Park your wreck here first. Costs materials + cash per stage.',
                onSelect    = function()
                    local veh = findNearbyVehicle(10.0)
                    if not veh then
                        lib.notify({ title = 'Car Build', description = 'No vehicle nearby to restore.', type = 'error' })
                        return
                    end
                    local plate = plateOf(veh)
                    CreateThread(function()
                        local ok, reason = lib.callback.await('sk_streetkings:carbuild:restoreStage', false, plate)
                        lib.notify({
                            title = 'Car Build', type = ok and 'success' or 'error',
                            description = reason or (ok and 'Progress made.' or 'Could not restore.'),
                        })
                    end)
                end,
            },
        },
    })
    lib.showContext('sk_carbuild_station')
end

local function openWreckLotMenu()
    local w = cfg.wreckLot
    lib.registerContext({
        id = 'sk_carbuild_wrecklot',
        title = 'Wreck Lot',
        options = {
            {
                title       = 'Buy a Wreck',
                description = ('%s - %s, rough condition. Restore it at any repair station.'):format(
                    SKFormatMoney(w.priceMin), SKFormatMoney(w.priceMax)),
                onSelect    = function()
                    CreateThread(function()
                        local ok, reason = lib.callback.await('sk_streetkings:carbuild:buyWreck', false)
                        lib.notify({
                            title = 'Wreck Lot', type = ok and 'success' or 'error',
                            description = reason or (ok and 'Wreck purchased.' or 'Could not buy a wreck.'),
                        })
                    end)
                end,
            },
        },
    })
    lib.showContext('sk_carbuild_wrecklot')
end

-- ── Proximity prompts ───────────────────────────────────────────────────────
-- On-foot only, by design: modules/repair's own roadside-repair prompt at
-- these same points only shows while seated in a vehicle, so the two never
-- compete for the same on-screen text prompt.

local function isOnFoot()
    return not (cache.vehicle and cache.vehicle ~= 0 and GetPedInVehicleSeat(cache.vehicle, -1) == cache.ped)
end

local function setupBuildPoints()
    for _, station in ipairs(SKRepairStations) do
        buildPoints[#buildPoints + 1] = lib.points.new({
            coords   = station.coords,
            distance = station.radius,
            onExit   = function()
                insideAny = false
                lib.hideTextUI()
            end,
            nearby = function(self)
                if self.currentDistance > 8.0 or not isOnFoot() then
                    if insideAny then insideAny = false; lib.hideTextUI() end
                    return
                end
                if not insideAny then
                    insideAny = true
                    lib.showTextUI(('[%s] Car Build'):format(SKInput.getInteractLabel()), { position = 'left-center' })
                end
                if SKInput.isInteractJustPressed() then
                    openBuildMenu(station.coords)
                end
            end,
        })
    end
end

local function setupWreckLot()
    local w = cfg.wreckLot
    local coords = vector3(w.coords.x, w.coords.y, w.coords.z)

    SK.CreateBlip({ sprite = 496, colour = 47, scale = 0.9, shortRange = true, label = 'Wreck Lot' }, coords)

    local nearWreckLot = false
    wreckLotPoint = lib.points.new({
        coords   = coords,
        distance = 15.0,
        onExit   = function()
            nearWreckLot = false
            lib.hideTextUI()
        end,
        nearby = function(self)
            if self.currentDistance > 6.0 or not isOnFoot() then
                if nearWreckLot then nearWreckLot = false; lib.hideTextUI() end
                return
            end
            if not nearWreckLot then
                nearWreckLot = true
                lib.showTextUI(('[%s] Browse Wrecks'):format(SKInput.getInteractLabel()), { position = 'left-center' })
            end
            if SKInput.isInteractJustPressed() then
                openWreckLotMenu()
            end
        end,
    })
end

CreateThread(function()
    Wait(1500)
    setupBuildPoints()
    setupWreckLot()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, p in ipairs(buildPoints) do p:remove() end
    if wreckLotPoint then wreckLotPoint:remove() end
    lib.hideTextUI()
end)
