-- Roadside repair stations, ported from streetkings modules/repair/repair_c.lua.
--
-- Drive into a station's radius and press the interact key to fix the vehicle.
-- Same cooldown and must-leave-and-return behaviour as the original; the
-- StreetKings NUI prompt is replaced with lib.showTextUI, and the marker goes
-- through the SKWaypoint shim.

if not Config.Modules.repairPoints then return end

local COLOR_READY    = '#40c057' -- ox_lib green.6
local COLOR_COOLDOWN = '#fa5252' -- ox_lib red.6

local repairPoints    = {}
local repairBlips     = {}
local repairWaypoints = {}

local canRepair  = true
local hasLeft    = true
local cooldownAt = 0
local insideAny  = false

local function setAllWaypointColor(color)
    for _, wpId in ipairs(repairWaypoints) do
        SKWaypoint.Update(wpId, { color = color })
    end
end

local function clearPoints()
    for _, p in ipairs(repairPoints) do p:remove() end
    repairPoints = {}

    for _, b in ipairs(repairBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    repairBlips = {}

    for _, wpId in ipairs(repairWaypoints) do
        SKWaypoint.Remove(wpId)
    end
    repairWaypoints = {}

    lib.hideTextUI()
end

local repairInFlight = false

local function doRepair(veh)
    if not canRepair or not hasLeft or repairInFlight then return end
    repairInFlight = true

    CreateThread(function()
        -- Ask first, repair second. Charging after the fix would hand a free
        -- repair to anyone who cannot pay.
        local ok, reason = lib.callback.await('sk_streetkings:repair:request', false)
        repairInFlight = false

        if not ok then
            lib.notify({ title = 'Repair', description = reason or 'Repair denied.', type = 'error' })
            return
        end

        canRepair = false
        hasLeft   = false
        setAllWaypointColor(COLOR_COOLDOWN)

        SetVehicleUndriveable(veh, false)
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehiclePetrolTankHealth(veh, 1000.0)
        SetVehicleDirtLevel(veh, 0.0)
        SetVehicleEngineOn(veh, true, true, false)

        lib.notify({ title = 'Repair', description = 'Vehicle repaired.', type = 'success' })

        cooldownAt = GetGameTimer() + Config.Repair.cooldownMs
        SetTimeout(Config.Repair.cooldownMs, function()
            canRepair = true
            setAllWaypointColor(COLOR_READY)
        end)
    end)
end

local function setupPoints()
    clearPoints()

    for _, station in ipairs(SKRepairStations) do
        local coords = station.coords

        repairBlips[#repairBlips + 1] = SK.CreateBlip(Config.Blips.repairStation, coords)

        repairWaypoints[#repairWaypoints + 1] = SKWaypoint.Create({
            coords = coords,
            label  = 'REPAIR',
            color  = COLOR_READY,
            size   = 1.2,
        })

        repairPoints[#repairPoints + 1] = lib.points.new({
            coords   = coords,
            distance = station.radius,
            onExit   = function()
                -- Leaving the radius is what re-arms a used station.
                hasLeft   = true
                insideAny = false
                lib.hideTextUI()
            end,
            nearby = function(self)
                local veh = cache.vehicle
                if not veh or veh == 0 or GetPedInVehicleSeat(veh, -1) ~= cache.ped then
                    if insideAny then
                        insideAny = false
                        lib.hideTextUI()
                    end
                    return
                end

                if self.currentDistance > 12.0 then
                    if insideAny then
                        insideAny = false
                        lib.hideTextUI()
                    end
                    return
                end

                if not insideAny then
                    insideAny = true
                    local label = SKInput.getInteractLabel()
                    if not canRepair then
                        lib.showTextUI(('[%s] Repair (cooling down)'):format(label), { position = 'left-center' })
                    elseif Config.Repair.cost > 0 then
                        lib.showTextUI(('[%s] Repair — %s'):format(label, SKFormatMoney(Config.Repair.cost)), { position = 'left-center' })
                    else
                        lib.showTextUI(('[%s] Repair Vehicle'):format(label), { position = 'left-center' })
                    end
                end

                if SKInput.isInteractJustPressed() then
                    if not canRepair then
                        local remaining = math.max(0, math.ceil((cooldownAt - GetGameTimer()) / 1000))
                        lib.notify({
                            title = 'Repair',
                            description = ('Cooling down — %ds left.'):format(remaining),
                            type = 'error',
                        })
                    elseif not hasLeft then
                        lib.notify({
                            title = 'Repair',
                            description = 'Drive away and come back to use this station again.',
                            type = 'error',
                        })
                    else
                        doRepair(veh)
                    end
                end
            end,
        })
    end
end

CreateThread(function()
    Wait(1500)
    setupPoints()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearPoints() end
end)
