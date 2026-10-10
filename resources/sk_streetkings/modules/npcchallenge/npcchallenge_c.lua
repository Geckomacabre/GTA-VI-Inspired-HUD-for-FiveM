-- NPC street challenges, ported from streetkings
-- modules/freeroam/npc_challenge_c.lua.
--
-- Pull up next to a stopped AI car facing the same way, hold a burnout, and it
-- may take you on: both cars race to a point roughly a kilometre ahead.
--
-- Changes from upstream:
--   * The mission-objective path and the car-meet racer path are dropped.
--     Both hung off systems that are not ported (missions, and the meet's
--     `skMeetRacer` statebag tagging), leaving only the freeroam behaviour.
--   * The countdown reuses SKRaceCountdown; the result panel is an SKHud
--     widget rather than NUI.
--   * Payout comes from Config.NpcChallenge instead of upstream's per-class
--     stake roll.
--   * Config.Modules.streetPack lets a triggered challenge roll into a small
--     pack (1-3 extra rivals) instead of staying 1v1 — see rollPackMates and
--     Config.StreetPack. A caller can also hand its own pre-built rival list
--     to SKNpcRace.start (modules/npcinvite does this for nothing yet, but
--     the hook exists for e.g. a "bring friends" invite variant).

if not Config.Modules.npcChallenge then return end

local COOLDOWN_MS          = 45000
local TRIGGER_CHANCE       = 65 -- percent, when both cars are the same tier
local TIER_MISMATCH_CHANCE = 12
local DECLINE_COOLDOWN_MS  = 2000

local RAY_LENGTH     = 10.0
local HEADING_DOT_MIN = 0.55 -- how closely the two cars must be pointing the same way

local BURNOUT_REQ           = 2000
local CALM_BURNOUT_INTERVAL = 2000

local DEST_MIN      = 800
local DEST_MAX      = 1400
local FINISH_RADIUS = 30.0
local RACE_TIMEOUT  = 150000

local NPC_DRIVE_SPEED = 100.0
local NPC_DRIVE_FLAGS = 786468
local RETASK_INTERVAL = 3000

local PACK_SPAWN_TIMEOUT_MS = 3000

local RESULTS_MS = 8000

-- Rough "would these two race each other" grouping, by GetVehicleClass().
-- Classes absent from this table never start a challenge.
local RACE_TIER = {
    [7]  = 1, [6]  = 1, [5] = 1, [4] = 1, [22] = 1, -- Super/Sports/Classics/Muscle/Open Wheel
    [3]  = 2, [1]  = 2, [0] = 2, [2] = 2,           -- Coupes/Sedans/Compacts/SUVs
    [9]  = 3, [12] = 3,                             -- Off-road/Vans
    [8]  = 4,                                       -- Motorcycles
}

local challengeActive = false
local scanning        = false
local cooldownUntil   = 0
local burnoutStart    = 0
local lastCalmBurnout = 0
local declinedNpcs    = {}

local activeBlip       = nil
local activeNpcBlip    = nil
local activeCheckpoint = nil
local activeRacers     = {} -- { {veh=, ped=, spawned=bool}, ... }, primary rival is always index 1
local drawingMarker    = false

-- ── HUD ─────────────────────────────────────────────────────────────────────

local P      = SKHud.Palette
local RESULT = SKHud.Anchor.centreLow

SKHud.register('npcchallenge', function(data)
    SKHud.Panel(RESULT.x, RESULT.y, 0.310, 0.126, P.panelDark)
    SKHud.Text(data.title or 'STREET CHALLENGE', RESULT.x, RESULT.y - 0.056, 0.30, P.textDim, true)
    SKHud.Text(data.won and 'YOU WON' or data.placeLabel or 'YOU LOST', RESULT.x, RESULT.y - 0.036, 0.70,
        data.won and P.success or P.danger, true)
    SKHud.Text(SKFormatTime(data.elapsedMs), RESULT.x, RESULT.y + 0.012, 0.32, P.text, true)
    if data.summary then
        SKHud.Text(data.summary, RESULT.x, RESULT.y + 0.032, 0.30, P.accent, true)
    end
end)

-- ── Helpers ─────────────────────────────────────────────────────────────────

---@param veh integer
---@return integer|nil tier
local function getVehTier(veh)
    return RACE_TIER[GetVehicleClass(veh)]
end

---@param ped integer
---@param speechName string
local function playPedSpeech(ped, speechName)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    PlayPedAmbientSpeechNative(ped, speechName, 'SPEECH_PARAMS_FORCE')
end

---@param playerVeh integer
---@param otherVeh integer
---@return boolean
local function sameRoughHeading(playerVeh, otherVeh)
    local pf = GetEntityForwardVector(playerVeh)
    local of = GetEntityForwardVector(otherVeh)
    return (pf.x * of.x + pf.y * of.y + pf.z * of.z) >= HEADING_DOT_MIN
end

local function cleanup()
    drawingMarker = false

    if activeBlip and DoesBlipExist(activeBlip) then RemoveBlip(activeBlip) end
    activeBlip = nil

    if activeNpcBlip and DoesBlipExist(activeNpcBlip) then RemoveBlip(activeNpcBlip) end
    activeNpcBlip = nil

    if activeCheckpoint then DeleteCheckpoint(activeCheckpoint) end
    activeCheckpoint = nil

    ClearGpsMultiRoute()
    DeleteWaypoint()

    -- Hand every racer back to the game rather than leaving mission entities
    -- behind. A found-in-traffic primary rival gets its flee/attack flags
    -- restored; a freshly spawned pack mate just gets released for the
    -- population system to clean up, same as npcinvite's rival always has.
    for _, racer in ipairs(activeRacers) do
        local ped, veh = racer.ped, racer.veh
        if ped and DoesEntityExist(ped) then
            SetBlockingOfNonTemporaryEvents(ped, false)
            SetPedKeepTask(ped, false)
            SetDriverAggressiveness(ped, 0.0)
            SetEntityAsMissionEntity(ped, false, true)
            SetEntityAsNoLongerNeeded(ped)
        end
        if veh and DoesEntityExist(veh) then
            SetVehicleLights(veh, 0)
            SetVehicleHandbrake(veh, false)
            SetEntityInvincible(veh, false)
            SetEntityAsMissionEntity(veh, false, true)
            SetEntityAsNoLongerNeeded(veh)
        end
    end

    activeRacers    = {}
    challengeActive = false
    SKHud.clear('npcchallenge')
end

--- Takes ownership of the NPC and makes it drive like a racer rather than an
--- ambient driver that panics and pulls over.
---@param npcPed integer
---@param npcVeh integer
local function lockdownNpc(npcPed, npcVeh)
    local deadline = GetGameTimer() + 2000
    while not NetworkHasControlOfEntity(npcVeh) or not NetworkHasControlOfEntity(npcPed) do
        NetworkRequestControlOfEntity(npcVeh)
        NetworkRequestControlOfEntity(npcPed)
        if GetGameTimer() > deadline then break end
        Wait(50)
    end

    SetEntityAsMissionEntity(npcPed, true, true)
    SetEntityAsMissionEntity(npcVeh, true, true)
    SetEntityInvincible(npcVeh, true)

    SetBlockingOfNonTemporaryEvents(npcPed, true)
    SetPedKeepTask(npcPed, true)
    SetPedCanBeDraggedOut(npcPed, false)
    SetPedFleeAttributes(npcPed, 0, false)
    SetPedCombatAttributes(npcPed, 46, true)
    SetPedConfigFlag(npcPed, 128, false)
    SetPedConfigFlag(npcPed, 281, true)
    SetDriverAbility(npcPed, 1.0)
    SetDriverAggressiveness(npcPed, 1.0)

    -- Neutral relationship both ways, so the racer neither attacks nor flees.
    AddRelationshipGroup('YOURTEAM_NPCRACE')
    local group = `YOURTEAM_NPCRACE`
    SetPedRelationshipGroupHash(npcPed, group)
    SetRelationshipBetweenGroups(1, group, `PLAYER`)
    SetRelationshipBetweenGroups(1, `PLAYER`, group)
end

--- A road node roughly DEST_MIN..DEST_MAX metres straight ahead.
---@return vector3
local function pickDestination()
    local ped    = PlayerPedId()
    local pos    = GetEntityCoords(ped)
    local target = pos + GetEntityForwardVector(ped) * math.random(DEST_MIN, DEST_MAX)

    local found, roadPos = GetClosestVehicleNodeWithHeading(target.x, target.y, target.z, 0, 3.0, 0)
    if found then
        return vector3(roadPos.x, roadPos.y, roadPos.z)
    end
    return vector3(target.x, target.y, target.z)
end

---@param nearVeh integer vehicle to spawn staggered behind/beside
---@param offsetIndex integer 1-based index among spawned mates, for spacing
---@param pool table vehicle model names
---@return integer|nil vehicle, integer|nil ped
local function spawnPackMate(nearVeh, offsetIndex, pool)
    local sp       = Config.StreetPack
    local vehHash  = GetHashKey(pool[math.random(#pool)])
    local pedHash  = GetHashKey(sp.driverPedModels[math.random(#sp.driverPedModels)])

    RequestModel(vehHash)
    RequestModel(pedHash)
    local timeout = GetGameTimer() + PACK_SPAWN_TIMEOUT_MS
    while (not HasModelLoaded(vehHash) or not HasModelLoaded(pedHash)) and GetGameTimer() < timeout do
        Wait(0)
    end
    if not HasModelLoaded(vehHash) or not HasModelLoaded(pedHash) then return nil, nil end

    local basePos = GetEntityCoords(nearVeh)
    local back     = GetEntityForwardVector(nearVeh) * -(4.0 * offsetIndex + 2.0)
    local lateral  = vector3(-GetEntityForwardVector(nearVeh).y, GetEntityForwardVector(nearVeh).x, 0.0)
        * ((offsetIndex % 2 == 0) and 3.0 or -3.0)
    local spawnPos = basePos + back + lateral
    local heading  = GetEntityHeading(nearVeh)

    local veh = CreateVehicle(vehHash, spawnPos.x, spawnPos.y, spawnPos.z, heading, true, false)
    SetModelAsNoLongerNeeded(vehHash)
    local ped = CreatePedInsideVehicle(veh, 4, pedHash, -1, true, false)
    SetModelAsNoLongerNeeded(pedHash)

    return veh, ped
end

--- Rolls whether a 1v1 challenge grows into a pack, and spawns the extra
--- rivals near the primary one if so. Returns {} on a miss or when the
--- module is off, never nil.
---@param npcVeh integer primary rival's vehicle, used as the spawn anchor
---@return table mates
local function rollPackMates(npcVeh)
    if not Config.Modules.streetPack then return {} end
    local sp = Config.StreetPack
    if math.random(1, 100) > sp.packChance then return {} end

    local tier  = getVehTier(npcVeh)
    local pool  = (tier and sp.vehiclePoolsByTier[tier]) or Config.NpcInvite.vehicleModels
    local count = math.random(sp.packMin, sp.packMax)

    local mates = {}
    for i = 1, count do
        local veh, ped = spawnPackMate(npcVeh, i, pool)
        if veh and ped then
            mates[#mates + 1] = { veh = veh, ped = ped, spawned = true }
        end
    end
    return mates
end

---@param npcVeh integer
local function startMarkerThread(npcVeh)
    drawingMarker = true
    CreateThread(function()
        while drawingMarker and DoesEntityExist(npcVeh) do
            local p = GetEntityCoords(npcVeh)
            DrawMarker(2, p.x, p.y, p.z + 2.0, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0,
                0.4, 0.4, 0.4, 255, 210, 0, 200, true, true, 2, false, nil, nil, false)
            Wait(0)
        end
    end)
end

---@param playerVeh integer
---@param racers table list of {veh=, ped=}
local function runCountdown(playerVeh, racers)
    FreezeEntityPosition(playerVeh, true)
    SetVehicleHandbrake(playerVeh, true)
    for _, r in ipairs(racers) do
        FreezeEntityPosition(r.veh, true)
        SetVehicleHandbrake(r.veh, true)
    end

    SKNotify({ title = 'Challenge accepted!', type = 'info', duration = 2000 })
    Wait(1500)

    local released = false
    SKRaceCountdown(3, function()
        StartVehicleHorn(racers[1].veh, 1500, `HELDDOWN`, false)
        FreezeEntityPosition(playerVeh, false)
        SetVehicleHandbrake(playerVeh, false)
        for _, r in ipairs(racers) do
            FreezeEntityPosition(r.veh, false)
            SetVehicleHandbrake(r.veh, false)
        end
        released = true
    end)

    while not released do Wait(0) end
end

-- ── The race ────────────────────────────────────────────────────────────────

---@param npcVeh integer primary rival's vehicle
---@param npcPed integer primary rival's ped
---@param extraMates table|nil pre-built {veh=,ped=,spawned=} list; when nil, rolled via Config.StreetPack
local function startChallenge(npcVeh, npcPed, extraMates)
    challengeActive = true

    local playerVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    if playerVeh == 0 then
        challengeActive = false
        return
    end

    local vehClass = GetVehicleClass(playerVeh)

    local mates = extraMates or rollPackMates(npcVeh)
    activeRacers = { { veh = npcVeh, ped = npcPed, spawned = false } }
    for _, m in ipairs(mates) do activeRacers[#activeRacers + 1] = m end
    local packSize = #activeRacers - 1 -- extra rivals beyond the primary one

    for _, r in ipairs(activeRacers) do
        lockdownNpc(r.ped, r.veh)
        ClearPedTasks(r.ped)
        SetVehicleHandbrake(r.veh, true)
    end
    playPedSpeech(npcPed, 'GENERIC_INSULT')

    local destination = pickDestination()

    -- Stays long range: it's the active objective, so it should sit on the
    -- minimap edge until the player reaches it. No auto-route/waypoint --
    -- the blip marks the destination, getting there is on the player.
    activeBlip = SK.CreateBlip(Config.Blips.challengeDestination, destination)
    SetBlipHighDetail(activeBlip, true)
    SetBlipDisplay(activeBlip, 4)

    -- Only the primary rival gets a blip, even in a pack, to keep the minimap
    -- readable — the notify/HUD below is what tells the player how many cars
    -- they're actually up against.
    activeNpcBlip = SK.CreateBlip(Config.Blips.challengeRival, npcVeh)

    activeCheckpoint = CreateCheckpoint(4,
        destination.x, destination.y, destination.z,
        destination.x, destination.y, destination.z,
        25.0, 255, 210, 0, 180, 0)

    ClearGpsMultiRoute()
    StartGpsMultiRoute(6, false, true)
    AddPointToGpsMultiRoute(destination.x, destination.y, destination.z)
    SetGpsMultiRouteRender(true)

    startMarkerThread(npcVeh)
    runCountdown(playerVeh, activeRacers)

    if packSize > 0 then
        SKNotify({ title = ('%d rivals just rolled up.'):format(packSize + 1), type = 'warning', duration = 3000 })
    end

    -- The server records the destination now so it can check where the player
    -- actually finished, and how long it took.
    TriggerServerEvent('sk_streetkings:npcchallenge:begin', destination.x, destination.y, destination.z, packSize + 2)

    local function taskRacer(r)
        TaskVehicleDriveToCoordLongrange(r.ped, r.veh,
            destination.x, destination.y, destination.z,
            NPC_DRIVE_SPEED, NPC_DRIVE_FLAGS, 5.0)
    end
    for _, r in ipairs(activeRacers) do taskRacer(r) end

    local raceStart      = GetGameTimer()
    local lastRetask     = raceStart
    local aiFinished     = {} -- index -> true
    local aiFinishedCount = 0
    local placement, elapsedMs

    while placement == nil do
        Wait(0)

        if SKC.GetGameState() ~= GameState.FREEROAM then
            SKNotify({ title = 'Challenge cancelled', type = 'warning' })
            TriggerServerEvent('sk_streetkings:npcchallenge:cancel')
            cleanup()
            return
        end

        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then
            SKNotify({ title = 'Challenge forfeited', type = 'error' })
            TriggerServerEvent('sk_streetkings:npcchallenge:cancel')
            cleanup()
            return
        end

        local now = GetGameTimer()
        -- The longrange drive task gives up on its own; keep re-issuing it.
        if (now - lastRetask) > RETASK_INTERVAL then
            for _, r in ipairs(activeRacers) do
                if not (r.ped and DoesEntityExist(r.ped) and IsEntityDead(r.ped)) then
                    taskRacer(r)
                end
            end
            lastRetask = now
        end

        elapsedMs = now - raceStart

        for i, r in ipairs(activeRacers) do
            if not aiFinished[i] and DoesEntityExist(r.ped)
                and #(GetEntityCoords(r.ped) - destination) < FINISH_RADIUS
            then
                aiFinished[i]      = true
                aiFinishedCount    = aiFinishedCount + 1
            end
        end

        if #(GetEntityCoords(ped) - destination) < FINISH_RADIUS then
            placement = aiFinishedCount + 1
        elseif elapsedMs > RACE_TIMEOUT then
            placement = aiFinishedCount + 1
        end
    end

    local won = placement == 1

    DoScreenFadeOut(500)
    Wait(550)
    DoScreenFadeIn(500)
    while not IsScreenFadedIn() do Wait(0) end

    local result = lib.callback.await(
        'sk_streetkings:npcchallenge:finish', false,
        placement, packSize + 2, elapsedMs, vehClass, SK.GetVehicleModelLabel(playerVeh)
    )

    -- Tear the race furniture down before the readout, but keep the widget up.
    cleanup()

    SKHud.set('npcchallenge', {
        title      = packSize > 0 and 'STREET PACK RACE' or 'STREET CHALLENGE',
        won        = won,
        placeLabel = (not won) and ('#%d / %d'):format(placement, packSize + 2) or nil,
        elapsedMs  = elapsedMs,
        summary    = result and result.summary or nil,
    })

    local deadline = GetGameTimer() + RESULTS_MS
    while GetGameTimer() < deadline do
        if SKInput.isInteractJustReleased() then break end
        Wait(0)
    end
    SKHud.clear('npcchallenge')
end

-- Exposed so modules/npcinvite can run the exact same race (countdown,
-- lockdown, HUD, server-validated payout) against a rival it spawned itself,
-- instead of one the burnout scan happened to find nearby. startChallenge's
-- own body is untouched - this is purely an additional way to reach it. A
-- caller can pass a pre-built extraMates list to control pack composition
-- itself; passing nothing lets Config.StreetPack roll it as usual.
SKNpcRace = {
    start    = startChallenge,
    isActive = function() return challengeActive end,
}

-- ── Burnout scanning ────────────────────────────────────────────────────────

local function pruneDeclined()
    for ped in pairs(declinedNpcs) do
        if not DoesEntityExist(ped) then declinedNpcs[ped] = nil end
    end
end

--- Casts short rays out of both flanks looking for a stopped AI car.
--- `pickCandidate = false` just nudges nearby drivers out of their flee/panic
--- flags so they hold still while the player revs.
---@param playerVeh integer
---@param pickCandidate boolean
---@return integer|nil vehicle, integer|nil driver
local function scanNearbyBurnoutVehicles(playerVeh, pickCandidate)
    local fwd      = GetEntityForwardVector(playerVeh)
    local pos      = GetEntityCoords(playerVeh)
    local rightVec = vector3(fwd.y, -fwd.x, 0.0)
    local leftDir  = vector3(-fwd.y, fwd.x, 0.0)

    local rays = {
        { origin = pos + rightVec * 1.5, endPos = pos + rightVec * RAY_LENGTH },
        { origin = pos + leftDir  * 1.5, endPos = pos + leftDir  * RAY_LENGTH },
    }

    for _, ray in ipairs(rays) do
        ray.handle = StartShapeTestRay(
            ray.origin.x, ray.origin.y, ray.origin.z,
            ray.endPos.x, ray.endPos.y, ray.endPos.z,
            10, playerVeh, 0
        )
    end

    Wait(0)

    local bestVeh, bestPed

    for _, ray in ipairs(rays) do
        local result, hit, _, _, hitEntity = GetShapeTestResult(ray.handle)
        if result == 2 and hit == 1 and hitEntity ~= 0 and IsEntityAVehicle(hitEntity) then
            local driver = GetPedInVehicleSeat(hitEntity, -1)
            if driver ~= 0 and not IsPedAPlayer(driver) and not declinedNpcs[driver] then
                SetPedConfigFlag(driver, 128, false)
                SetPedFleeAttributes(driver, 0, false)
                if pickCandidate and not bestVeh
                    and GetEntitySpeed(hitEntity) < 1.0
                    and sameRoughHeading(playerVeh, hitEntity)
                then
                    bestVeh, bestPed = hitEntity, driver
                end
            end
        end
    end

    return bestVeh, bestPed
end

local function resetBurnout()
    burnoutStart    = 0
    lastCalmBurnout = 0
end

local function startScanning()
    if scanning then return end
    scanning = true
    resetBurnout()

    CreateThread(function()
        while scanning do
            Wait(250)
            pruneDeclined()

            if SKC.GetGameState() ~= GameState.FREEROAM then
                resetBurnout()
                goto continue
            end
            if challengeActive or Cinematic then goto continue end
            if GetGameTimer() < cooldownUntil then goto continue end

            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 or not IsVehicleInBurnout(veh) then
                resetBurnout()
                goto continue
            end

            if burnoutStart == 0 then burnoutStart = GetGameTimer() end

            local now = GetGameTimer()
            if (now - burnoutStart) < BURNOUT_REQ then
                -- Still revving. Periodically calm nearby drivers so the one
                -- being challenged does not drive off mid-burnout.
                if now - lastCalmBurnout >= CALM_BURNOUT_INTERVAL then
                    lastCalmBurnout = now
                    scanNearbyBurnoutVehicles(veh, false)
                end
                goto continue
            end

            local npcVeh, npcPed = scanNearbyBurnoutVehicles(veh, true)
            if not npcVeh then
                resetBurnout()
                cooldownUntil = GetGameTimer() + DECLINE_COOLDOWN_MS
                goto continue
            end

            local tiersMatch = getVehTier(veh) == getVehTier(npcVeh)
            local chance = tiersMatch and TRIGGER_CHANCE or TIER_MISMATCH_CHANCE

            resetBurnout()

            if math.random(1, 100) <= chance then
                cooldownUntil = GetGameTimer() + COOLDOWN_MS
                startChallenge(npcVeh, npcPed)
            else
                cooldownUntil = GetGameTimer() + DECLINE_COOLDOWN_MS
                declinedNpcs[npcPed] = true
                SKNotify({ title = 'They declined to race you.', type = 'warning' })
                playPedSpeech(npcPed, 'GENERIC_NO')
            end

            ::continue::
        end
    end)
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

CreateThread(function()
    SK.WaitForControl()
    Wait(2000)
    startScanning()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    scanning = false
    if challengeActive then cleanup() end
end)
