-- Client half of the race vehicle hand-out (see racevehicle_s.lua): asks the server for the
-- route's vehicle, sits the player in it, starts it moving for an air race, and puts everything
-- back afterwards.

SKRaceVehicle = {}

local handedOut = nil -- { veh, returnCoords, returnHeading }

-- Ground under an entry point: the route data only has an approximate Z.
local function groundAt(x, y, z)
    for probeZ = z + 30.0, z - 30.0, -10.0 do
        local found, gz = GetGroundZFor_3dCoord(x, y, probeZ, false)
        if found then return gz end
    end
    return z
end
SKRaceVehicle.groundAt = groundAt

--- Where a route is entered from on foot: its own entry point, or its start line.
---@return vector3
function SKRaceVehicle.entryPoint(def)
    local e = def.entry or def.start
    return vector3(e.x, e.y, def.entry and groundAt(e.x, e.y, e.z) or e.z)
end

--- Does this route hand out its own vehicle?
function SKRaceVehicle.handsOut(def)
    return def.vehicle ~= nil and (def.vehicle.spawn == true or def.vehicle.airborne == true)
end

--- Asks the server for the route's vehicle and seats the player in it, frozen where it stands.
--- Must run in a thread (it waits on the network).
---@return integer|nil vehicle, string|nil reason, table|nil info
function SKRaceVehicle.acquire(routeId, def, laneOffset)
    local returnCoords, returnHeading = GetEntityCoords(cache.ped), GetEntityHeading(cache.ped)

    local resp = lib.callback.await('sk_streetkings:racing:spawnVehicle', false, routeId, laneOffset or 0.0)
    if not resp or not resp.ok then return nil, resp and resp.reason or 'no_response' end

    -- An air race starts kilometres from where it is entered. The server made the vehicle at the
    -- start, and a client only receives entities near it, so go there first (held in place, so the
    -- ped does not fall while the vehicle streams in).
    local s = def.start
    FreezeEntityPosition(cache.ped, true)
    SetEntityCoords(cache.ped, s.x, s.y, s.z, false, false, false, false)

    -- lib.waitFor raises on timeout (passing false for the message does not stop that), so catch it:
    -- a plane that never streams in must put the player back, not strand them frozen in the sky.
    local waited, veh = pcall(lib.waitFor, function()
        if not NetworkDoesNetworkIdExist(resp.netId) then return end
        local e = NetworkGetEntityFromNetworkId(resp.netId)
        if e ~= 0 and DoesEntityExist(e) then return e end
    end, 'the race vehicle never arrived', 8000)
    if not waited or not veh then
        FreezeEntityPosition(cache.ped, false)
        SetEntityCoords(cache.ped, returnCoords.x, returnCoords.y, returnCoords.z, false, false, false, false)
        TriggerServerEvent('sk_streetkings:racing:releaseVehicle')
        return nil, 'vehicle_timeout'
    end

    NetworkRequestControlOfEntity(veh)
    local deadline = GetGameTimer() + 2000
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < deadline do Wait(0) end

    handedOut = { veh = veh, returnCoords = returnCoords, returnHeading = returnHeading }

    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleEngineOn(veh, true, true, false)
    SetVehicleDoorsLocked(veh, 1)
    FreezeEntityPosition(veh, true)
    SetPedIntoVehicle(cache.ped, veh, -1)
    FreezeEntityPosition(cache.ped, false)
    if resp.airborne then
        -- Rockstar starts you in the air already flying: wheels up, engine on.
        ControlLandingGear(veh, 3)
    end
    return veh, nil, resp
end

--- The instant the countdown ends: let go of the vehicle and, in the air, give it its flying speed.
function SKRaceVehicle.launch(veh, info)
    FreezeEntityPosition(veh, false)
    if info and info.airborne then
        SetVehicleForwardSpeed(veh, info.speed or 40.0)
    end
end

--- True while the player is in a vehicle this race handed out.
function SKRaceVehicle.isHandedOut()
    return handedOut ~= nil and DoesEntityExist(handedOut.veh)
end

--- Ends a hand-out: fades out, puts the player back on the ground where they entered, and has the
--- server delete the vehicle. Safe to call when nothing was handed out.
function SKRaceVehicle.giveBack()
    local h = handedOut
    handedOut = nil
    if not h then return end

    CreateThread(function()
        DoScreenFadeOut(500)
        while not IsScreenFadedOut() do Wait(10) end

        if DoesEntityExist(h.veh) then
            TaskLeaveVehicle(cache.ped, h.veh, 16)
            Wait(100)
        end
        SetEntityCoords(cache.ped, h.returnCoords.x, h.returnCoords.y, h.returnCoords.z, false, false, false, false)
        SetEntityHeading(cache.ped, h.returnHeading)
        TriggerServerEvent('sk_streetkings:racing:releaseVehicle')

        DoScreenFadeIn(500)
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if handedOut and IsScreenFadedOut() then DoScreenFadeIn(0) end
end)
