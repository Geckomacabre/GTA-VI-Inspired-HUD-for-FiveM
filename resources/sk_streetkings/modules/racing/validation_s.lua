-- Server-authoritative singleplayer run tracking + checkpoint validation.
-- Ported from StreetKings' events_validation_s.lua design: a single accept
-- radius server-side, sequential-order enforcement, vehicle-swap rejection,
-- and a run timeout. Pure game-state/distance math, no framework dependency.

SKValidation = {}

local activeRuns = {} -- source -> run state

local function playerState(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return nil end
    return ped, veh, GetEntityCoords(ped)
end

function SKValidation.withinRadius(coords, target, radius)
    return #(coords - target) <= radius
end

-- Starts a singleplayer timed run if the player is in a vehicle near the
-- route's start line. `vehInfo` is the client-reported { class, model } (the
-- server can't read those natives itself). Returns (true, run) or (false, reason).
function SKValidation.beginRun(source, routeId, vehInfo)
    local def = SKRoutes.get(routeId)
    if not def then return false, 'unknown_route' end

    if def.unlockRequirement then
        local player = exports.qbx_core:GetPlayer(source)
        if not player then return false, 'not_loaded' end
        local unlocked, reason = SKRoutes.checkUnlockRequirement(def, player.PlayerData.citizenid)
        if not unlocked then return false, reason end
    end

    local ped, veh, coords = playerState(source)
    if not ped then return false, 'not_in_vehicle' end

    if not SKValidation.withinRadius(coords, vec3(def.start.x, def.start.y, def.start.z), def.startRadius or Config.StartRadius) then
        return false, 'too_far_from_start'
    end

    local classId = vehInfo and tonumber(vehInfo.class) or -1
    activeRuns[source] = {
        routeId          = routeId,
        kind             = def.kind or 'road',
        checkpoints      = SKRouteBuilder.buildCheckpointList(def),
        checkpointRadii  = SKRouteBuilder.buildCheckpointRadii(def),
        -- def.checkpoints index behind every expanded checkpoint, so per-gate stunt data follows laps
        sourceIndex      = SKRouteBuilder.buildSourceIndex(def),
        gateStunts       = def.gateStunts,
        netBonusSeconds  = 0.0, -- bonuses minus penalties, stunt-plane scoring (shared/gates_sh.lua)
        gateResults      = {},  -- status per gate, for the result screen
        nextIndex        = 1,
        startedAt        = GetGameTimer(),
        lastActivityAt   = GetGameTimer(),
        vehicleModelHash = GetEntityModel(veh), -- server-side, for the swap check only
        vehicleClassName = Config.VehicleClassNames[classId] or 'Unknown',
        vehicleModelName = vehInfo and tostring(vehInfo.model or '') or '',
    }
    return true, activeRuns[source]
end

-- Returns the run, clearing and returning nil if it has timed out.
function SKValidation.getRun(source)
    local run = activeRuns[source]
    if not run then return nil end
    if GetGameTimer() - run.startedAt > Config.RunTimeoutMs then
        activeRuns[source] = nil
        return nil
    end
    return run
end

function SKValidation.clearRun(source)
    activeRuns[source] = nil
end

-- The stunt a gate asks for ('inverted' | 'left' | 'right') or false.
local function stuntFor(run, index)
    local src = run.sourceIndex and run.sourceIndex[index]
    return (src and src > 0 and run.gateStunts and run.gateStunts[src]) or false
end

-- Vertical component of the plane's up vector from the server's own reading of its rotation.
-- Sign-agnostic (pitch and roll enter as cosines), so it does not depend on which way a roll is signed.
local function upZOf(veh)
    local rot = GetEntityRotation(veh, 2)
    return math.cos(math.rad(rot.x)) * math.cos(math.rad(rot.y))
end

-- checkpointIndex is 1-based and must match the run's expected next checkpoint.
-- `status` is the client's stunt-plane verdict for the gate ('perfect', 'knife_inner', 'stunt', 'miss'...);
-- ignored on road and offroad routes, and only ever a claim on air routes: the server keeps the
-- ring/tilt it measures itself (SKGates.verifyClaim) and scores seconds from that, never from the client.
-- Returns (true, run, scoredStatus) on acceptance, (false, reason) otherwise.
function SKValidation.validateCheckpointHit(source, checkpointIndex, status)
    local run = SKValidation.getRun(source)
    if not run then return false, 'no_active_run' end
    if checkpointIndex ~= run.nextIndex then return false, 'out_of_order' end

    local ped, veh, coords = playerState(source)
    if not ped then return false, 'not_in_vehicle' end
    if GetEntityModel(veh) ~= run.vehicleModelHash then return false, 'vehicle_changed' end

    local target = run.checkpoints[checkpointIndex]
    if not target then return false, 'invalid_index' end
    local radius = run.checkpointRadii[checkpointIndex] or Config.CheckpointRadius

    local scored
    if run.kind == 'air' and status == 'miss' then
        -- Flew past the gate: only believable when the plane really is past it, near it, on the way to the next.
        if not SKGates.isMiss(coords, target, run.checkpoints[checkpointIndex + 1], radius) then
            return false, 'bad_miss'
        end
        scored = 'miss'
    else
        if not SKValidation.withinRadius(coords, target, radius) then return false, 'too_far' end
        if run.kind == 'air' then
            scored = SKGates.verifyClaim(status or 'pass', stuntFor(run, checkpointIndex), coords, target, upZOf(veh))
            if not scored then return false, 'bad_status' end
        end
    end

    if scored then
        run.netBonusSeconds = run.netBonusSeconds + SKGates.seconds(scored)
        run.gateResults[#run.gateResults + 1] = scored
    end

    run.nextIndex = run.nextIndex + 1
    run.lastActivityAt = GetGameTimer()
    return true, run, scored
end

function SKValidation.isFinished(run)
    return run.nextIndex > #run.checkpoints
end

AddEventHandler('playerDropped', function()
    SKValidation.clearRun(source)
end)
