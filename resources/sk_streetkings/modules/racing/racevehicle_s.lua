-- Hands a player the vehicle a race is built around: the stunt plane for an air
-- race (spawned in the air on the start line, like Rockstar's own), or the
-- Sanchez / Mesa an offroad race gives you. The server creates it, so the
-- model is the route's own and nothing a client asks for.
--
-- One vehicle per player. It is deleted when the run ends (finish, abort,
-- disconnect) so a race never leaves a plane parked in the sky.

SKRaceVehicle = {}

local spawned = {} -- src -> { entity, routeId }

local function horizontalDist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function SKRaceVehicle.release(src)
    local rec = spawned[src]
    if not rec then return end
    spawned[src] = nil
    if DoesEntityExist(rec.entity) then DeleteEntity(rec.entity) end
end

--- The vehicle a route hands out, or nil when it hands out none.
---@return table|nil vehicle { model, netType, airborne, speed }
function SKRaceVehicle.forRoute(def)
    local v = def and def.vehicle
    if not v or not (v.spawn or v.airborne) then return nil end
    local allowed = Config.RaceVehicles[v.model]
    if not allowed then return nil end
    return { model = v.model, netType = allowed.netType, airborne = v.airborne == true, speed = v.speed or 0.0 }
end

-- Client asks for the route's vehicle. `laneOffset` shifts it sideways off the start line so a
-- grid of racers does not spawn inside each other (0 for a solo run).
lib.callback.register('sk_streetkings:racing:spawnVehicle', function(src, routeId, laneOffset)
    local def = SKRoutes.get(routeId)
    if not def then return { ok = false, reason = 'unknown_route' } end

    local v = SKRaceVehicle.forRoute(def)
    if not v then return { ok = false, reason = 'no_vehicle_for_route' } end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return { ok = false, reason = 'not_loaded' } end

    -- Standing at the race's entry (an air race's start is in the sky, so it has its own).
    local entry = def.entry or def.start
    if horizontalDist(GetEntityCoords(ped), entry) > Config.RaceVehicleEntryRadius then
        return { ok = false, reason = 'too_far_from_start' }
    end

    if def.unlockRequirement then
        local player = exports.qbx_core:GetPlayer(src)
        if not player then return { ok = false, reason = 'not_loaded' } end
        local unlocked, reason = SKRoutes.checkUnlockRequirement(def, player.PlayerData.citizenid)
        if not unlocked then return { ok = false, reason = reason } end
    end

    SKRaceVehicle.release(src)

    local offset = math.max(-30.0, math.min(tonumber(laneOffset) or 0.0, 30.0))
    local h = math.rad(-(def.start.w or 0.0))
    local x = def.start.x + math.sin(h + math.pi / 2) * offset
    local y = def.start.y + math.cos(h + math.pi / 2) * offset

    local entity = CreateVehicleServerSetter(GetHashKey(v.model), v.netType, x, y, def.start.z, def.start.w or 0.0)
    if not entity or entity == 0 then return { ok = false, reason = 'spawn_failed' } end

    local bucket = GetPlayerRoutingBucket(src)
    if bucket ~= 0 then SetEntityRoutingBucket(entity, bucket) end

    spawned[src] = { entity = entity, routeId = routeId }
    return { ok = true, netId = NetworkGetNetworkIdFromEntity(entity), model = v.model, airborne = v.airborne, speed = v.speed }
end)

RegisterNetEvent('sk_streetkings:racing:releaseVehicle', function()
    SKRaceVehicle.release(source)
end)

AddEventHandler('playerDropped', function()
    SKRaceVehicle.release(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(spawned) do SKRaceVehicle.release(src) end
end)
