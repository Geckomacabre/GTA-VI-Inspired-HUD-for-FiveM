-- Freeroam police, ported from streetkings modules/freeroam/police_c.lua.
--
-- Spawns its own speed-trap cops, runs a radar detector that beeps as you close
-- on one, reports collisions to dispatch, and busts the player if they stop
-- next to a cop while wanted.
--
-- ── Read before enabling ────────────────────────────────────────────────────
-- Config.Modules.police is false by default and should stay that way unless it
-- is a deliberate choice. This module spawns pursuit AI and drives GTA's own
-- wanted-level system, neither of which the server's police RP stack
-- (ps-dispatch, fenix-police, lvc, wk_wars2x) knows anything about. Turning it
-- on gives officers two parallel sets of cops.
--
-- Changes from upstream:
--   * The bust is a fine and a fade, not an arrest. Upstream played an arrest
--     NUI sequence then dropped the player into its own garage; on this server
--     arrests, jail and respawn belong to the police RP stack, so the port
--     stops at charging the player and clearing the wanted level.
--   * Mission, phone and garage coupling is dropped (none of those are ported).
--   * NUI bust countdown redrawn as an SKHud widget.
--   * SKCamera calls dropped — upstream's custom chase camera is not ported.
--   * The radar beep goes through SK.PlaySound, which uses StreetKings' own
--     'radar_detector' sound when the optional streetkings_audio resource is
--     installed and a stock beep otherwise.

if not Config.Modules.police then return end

SKPolice = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────

SKPolice.PoliceVehicles = {
    `police`,
    `police2`,
    `police3`,
    `police4`,
    `sheriff`,
    `sheriff2`,
    `policet`,
    `policeb`,
    `pranger`,
}

SKPolice.RadarDetector = {
    enabled           = Config.Police.radarDetector,
    maxDetectDistance = 150.0,
    minIntervalMs     = 180,
    maxIntervalMs     = 1600,
}

SKPolice.TrapConfig = {
    triggerSpeedMph  = Config.Police.trapTriggerSpeedMph,
    spawnDistance    = 250.0,
    detectDistance   = 45.0,
    defaultCopPed    = 's_m_y_hwaycop_01',
    defaultCopVeh    = 'police3',
    blips = {
        enabled    = false,
        showStatic = false,
        sprite     = 56,
        color      = 3,
        scale      = 1.0,
        shortRange = true,
        name       = 'Trap Cop',
    },
}

-- ── State ───────────────────────────────────────────────────────────────────

SKPolice.TrapPoints      = {}
SKPolice.TrapCopVehicles = {}
SKPolice.TrapCopPeds     = {}

local MPS_TO_MPH        = 2.236936
local CRIME_COOLDOWN    = 30000
local INCIDENT_LIFETIME = 120000
local TRAFFIC_COLLISION_REPORT_CHANCE = 0.08

local pursuit = { active = false, running = false, started = nil }
local crimeCooldown  = 0
local incidents      = {}
local policeDisabled = false

-- Assigned further down; referenced by the disable/reset helpers above it.
local deleteTrap

-- ── Helpers ─────────────────────────────────────────────────────────────────

--- Upstream also allowed GameState.MISSION here; missions are not ported.
---@return boolean
function SKPolice.isInFreeroam()
    return SKC.GetGameState() == GameState.FREEROAM
end

---@return boolean
function SKPolice.isChasing()
    return GetPlayerWantedLevel(PlayerId()) > 0 or pursuit.active or pursuit.running
end

---@return boolean
function SKPolice.hasWantedLevel()
    return GetPlayerWantedLevel(PlayerId()) > 0
end

function SKPolice.notifyAccessBlockedByWantedLevel()
    SKNotify({ type = 'error', title = 'Lose Your Wanted Level First' })
end

--- Nearest cop vehicle or on-foot officer within `distance`.
---@param distance number
---@return integer|nil entity, boolean isNear
function SKPolice.IsNearPolice(distance)
    local playerPos = GetEntityCoords(PlayerPedId())

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) then
            local model = GetEntityModel(vehicle)
            for _, copModel in ipairs(SKPolice.PoliceVehicles) do
                if copModel == model and #(playerPos - GetEntityCoords(vehicle)) < distance then
                    return vehicle, true
                end
            end
        end
    end

    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and not IsPedInAnyVehicle(ped, false) then
            if SKPolice.TrapCopPeds[ped] or GetPedRelationshipGroupHash(ped) == `COP` then
                if #(playerPos - GetEntityCoords(ped)) < distance then
                    return ped, true
                end
            end
        end
    end

    return nil, false
end

---@param maxDistance number
---@return number distance to the nearest spawned trap cop, or maxDistance + 1
local function getNearestTrapCopDistance(maxDistance)
    local playerPos = GetEntityCoords(PlayerPedId())
    local nearest   = maxDistance + 1.0
    for _, pt in ipairs(SKPolice.TrapPoints) do
        if pt.spawnedVehicle and DoesEntityExist(pt.spawnedVehicle) then
            local dist = #(playerPos - GetEntityCoords(pt.spawnedVehicle))
            if dist < nearest then nearest = dist end
        end
    end
    return nearest
end

-- ── Bust countdown HUD ──────────────────────────────────────────────────────

local P = SKHud.Palette
local COUNTDOWN = SKHud.Anchor.bottomCentre

SKHud.register('policebust', function(data)
    SKHud.Panel(COUNTDOWN.x, COUNTDOWN.y, 0.180, 0.070, P.panelDark)
    SKHud.Text('BUSTED IN', COUNTDOWN.x, COUNTDOWN.y - 0.030, 0.32, P.textDim, true)
    SKHud.Text(tostring(data.seconds), COUNTDOWN.x, COUNTDOWN.y - 0.014, 0.60, P.danger, true)
end)

---@param seconds integer|nil nil hides the countdown
local function setBustCountdown(seconds)
    if seconds then
        SKHud.set('policebust', { seconds = seconds })
    else
        SKHud.clear('policebust')
    end
end

-- ── Pursuit reset / disable ─────────────────────────────────────────────────

function SKPolice.resetPursuit()
    pursuit.active  = false
    pursuit.running = false
    pursuit.started = nil
    setBustCountdown(nil)

    for _, pt in ipairs(SKPolice.TrapPoints) do
        if pt._triggered then
            pt._triggered      = false
            pt._pendingCleanup = false
            deleteTrap(pt)
        end
    end
end

--- Used by other modules to stand police down (e.g. while a race is running).
---@param disabled boolean
function SKPolice.setPoliceDisabled(disabled)
    policeDisabled = disabled
    if not disabled then return end

    ClearPlayerWantedLevel(PlayerId())
    SKPolice.resetPursuit()

    for _, pt in ipairs(SKPolice.TrapPoints) do
        if pt.spawnedVehicle or pt.spawnedPed then
            deleteTrap(pt)
            pt._triggered      = false
            pt._pendingCleanup = false
        end
    end

    for _, entry in ipairs(incidents) do
        DeleteIncident(entry.handle)
    end
    incidents = {}
end

-- ── Outcomes ────────────────────────────────────────────────────────────────

--- Stopped next to a cop while wanted. Charges the fine, clears the wanted
--- level and hands the player back. Deliberately does not arrest, jail or
--- relocate — that belongs to the server's police RP stack.
---@return boolean handled
function SKPolice.busted()
    local confirmed = lib.callback.await('sk_streetkings:police:confirmBust', false)
    if not confirmed or not confirmed.ok then return false end

    setBustCountdown(nil)
    ClearPlayerWantedLevel(PlayerId())

    DoScreenFadeOut(500)
    Wait(900)
    SKNotify({
        type        = 'error',
        title       = 'Busted',
        description = confirmed.summary or 'Pulled over and fined.',
        duration    = 6000,
    })
    DoScreenFadeIn(800)

    return true
end

--- The cinematic that plays when a speed trap picks the player up.
---@param entity integer the cop vehicle that caught them
function SKPolice.caughtSpeeding(entity)
    for i = 10, 1, -1 do
        SetTimeScale(i / 10)
        Wait(35)
    end

    Cinematic = true
    local playerVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    local cinCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    AttachCamToEntity(cinCam, playerVehicle, 0.0, 20.0, 4.0, true)
    PointCamAtEntity(cinCam, entity, 0.0, 0.0, 0.0, true)
    SetCamActive(cinCam, true)
    RenderScriptCams(true, true, 0, true, true)

    SetPlayerWantedLevel(PlayerId(), 2, false)
    SetPlayerWantedLevelNow(PlayerId(), false)
    SetVehicleIsWanted(playerVehicle, true)
    ReportPoliceSpottedPlayer(PlayerId())

    Wait(5000)

    SetCamActive(cinCam, false)
    DestroyCam(cinCam, false)
    RenderScriptCams(false, true, 0, true, true)

    for i = 1, 10 do
        SetTimeScale(i / 10)
        Wait(35)
    end
    SetTimeScale(1.0)
    Cinematic = false
end

-- ── Traps ───────────────────────────────────────────────────────────────────

---@param point table
local function createTrapVehicleAndCop(point)
    if point.spawnedVehicle and DoesEntityExist(point.spawnedVehicle) then return end
    if SKPolice.isChasing() then return end

    -- Upstream fell back to the ped model for the vehicle here, which silently
    -- spawned nothing.
    local vehicleHash = SK.LoadModel(point.vehicle or SKPolice.TrapConfig.defaultCopVeh)
    local copHash     = SK.LoadModel(point.cop or SKPolice.TrapConfig.defaultCopPed)
    if not vehicleHash or not copHash then return end

    local v = CreateVehicle(vehicleHash, point.coords.x, point.coords.y, point.coords.z, point.heading or 0.0, false, true)
    if not DoesEntityExist(v) then return end

    SetEntityAsMissionEntity(v, true, true)
    SetVehicleOnGroundProperly(v)
    SetVehicleDoorsLocked(v, 4)
    SetVehicleSiren(v, false)
    SetVehicleHasMutedSirens(v, false)
    SetVehicleEngineOn(v, true, true, false)

    local ped = CreatePedInsideVehicle(v, 4, copHash, -1, false, true)
    if not DoesEntityExist(ped) then
        DeleteEntity(v)
        return
    end

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true)
    SetPedKeepTask(ped, true)

    SKPolice.TrapCopVehicles[v]   = true
    SKPolice.TrapCopPeds[ped]     = true
    point.spawnedVehicle          = v
    point.spawnedPed              = ped

    if SKPolice.TrapConfig.blips.enabled then
        point.spawnedBlip = SK.CreateBlip(Config.Blips.policeTrap, v)
    end

    SK.UnloadModel(vehicleHash)
    SK.UnloadModel(copHash)
end

---@param point table
function deleteTrap(point)
    if point.spawnedPed and DoesEntityExist(point.spawnedPed) then
        SKPolice.TrapCopPeds[point.spawnedPed] = nil
        DeleteEntity(point.spawnedPed)
        point.spawnedPed = nil
    end
    if point.spawnedVehicle and DoesEntityExist(point.spawnedVehicle) then
        SKPolice.TrapCopVehicles[point.spawnedVehicle] = nil
        DeleteEntity(point.spawnedVehicle)
        point.spawnedVehicle = nil
    end
    if point.spawnedBlip and DoesBlipExist(point.spawnedBlip) then
        RemoveBlip(point.spawnedBlip)
        point.spawnedBlip = nil
    end
end

---@param point table
local function startTrapChase(point)
    if not point.spawnedPed or not DoesEntityExist(point.spawnedPed) then return end

    SetVehicleSiren(point.spawnedVehicle, true)
    TaskVehicleChase(point.spawnedPed, PlayerPedId())
    SetTaskVehicleChaseBehaviorFlag(point.spawnedPed, 32, true)
    SetTaskVehicleChaseIdealPursuitDistance(point.spawnedPed, 30.0)
    point._triggered = true

    CreateThread(function()
        SKPolice.caughtSpeeding(point.spawnedVehicle)
    end)

    -- Keep re-reporting while the cop still has eyes on, so the wanted level
    -- does not decay the moment the cinematic ends.
    CreateThread(function()
        while point._triggered and point.spawnedVehicle and DoesEntityExist(point.spawnedVehicle) do
            Wait(1000)
            if not SKPolice.isInFreeroam() then break end
            local playerPed = PlayerPedId()
            local dist = #(GetEntityCoords(point.spawnedVehicle) - GetEntityCoords(playerPed))
            if dist <= 50.0 and HasEntityClearLosToEntity(point.spawnedVehicle, playerPed, 17) then
                ReportPoliceSpottedPlayer(PlayerId())
            end
        end
    end)
end

---@param locations table[] entries from SKPoliceTrapLocations
function SKPolice.InitTrapPoints(locations)
    for _, cfg in ipairs(locations) do
        local pt = lib.points.new({
            coords   = cfg.coords,
            distance = SKPolice.TrapConfig.spawnDistance,
        })

        pt.vehicle         = cfg.vehicle
        pt.cop             = cfg.cop
        pt.heading         = cfg.heading
        pt._triggered      = false
        pt._pendingCleanup = false

        function pt:onEnter()
            createTrapVehicleAndCop(self)
        end

        function pt:onExit()
            -- A trap that is mid-chase follows the player out of its own
            -- radius; clean it up when the pursuit ends instead.
            if self._triggered then
                self._pendingCleanup = true
                return
            end
            deleteTrap(self)
        end

        function pt:nearby()
            if not SKPolice.isInFreeroam() then return end
            if policeDisabled then return end
            if self._triggered then return end
            if not self.spawnedVehicle or not DoesEntityExist(self.spawnedVehicle) then return end
            if not IsPedInAnyVehicle(PlayerPedId(), false) then return end
            if GetPlayerWantedLevel(PlayerId()) > 0 then return end

            local veh = GetVehiclePedIsIn(PlayerPedId(), false)
            if GetEntitySpeed(veh) * MPS_TO_MPH < SKPolice.TrapConfig.triggerSpeedMph then return end

            if self.currentDistance <= SKPolice.TrapConfig.detectDistance
                and HasEntityClearLosToEntityInFront(self.spawnedPed, PlayerPedId()) then
                startTrapChase(self)
            end
        end

        if SKPolice.TrapConfig.blips.showStatic then
            pt.staticBlip = SK.CreateBlip(Config.Blips.policeTrap, cfg.coords)
        end

        SKPolice.TrapPoints[#SKPolice.TrapPoints + 1] = pt
    end
end

local function clearTrapPoints()
    for _, pt in ipairs(SKPolice.TrapPoints) do
        deleteTrap(pt)
        if pt.staticBlip and DoesBlipExist(pt.staticBlip) then
            RemoveBlip(pt.staticBlip)
        end
        if pt.remove then pt:remove() end
    end
    SKPolice.TrapPoints      = {}
    SKPolice.TrapCopVehicles = {}
    SKPolice.TrapCopPeds     = {}
end

-- ── Crime reporting ─────────────────────────────────────────────────────────

--- A crime only counts if some NPC could actually see it happen.
---@param victim integer
---@return boolean
local function hasWitness(victim)
    local playerPed    = PlayerPedId()
    local victimCoords = GetEntityCoords(victim)
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and ped ~= playerPed and not IsPedAPlayer(ped) and not IsPedInAnyVehicle(ped, false) then
            if #(GetEntityCoords(ped) - victimCoords) <= 50.0 and HasEntityClearLosToEntity(ped, victim, 17) then
                return true
            end
        end
    end
    return false
end

AddEventHandler('entityDamaged', function(victim, culprit)
    if not SKPolice.isInFreeroam() then return end
    if policeDisabled then return end
    if SKPolice.isChasing() then return end
    if GetGameTimer() - crimeCooldown < CRIME_COOLDOWN then return end

    local playerPed     = PlayerPedId()
    local playerVehicle = GetVehiclePedIsIn(playerPed, false)
    if playerVehicle == 0 then return end
    if culprit ~= playerVehicle then return end

    local victimIsPed     = IsEntityAPed(victim) and victim ~= playerPed and not IsPedAPlayer(victim)
    local victimIsVehicle = IsEntityAVehicle(victim) and not SKPolice.TrapCopVehicles[victim]

    if victimIsPed then
        if not hasWitness(victim) then return end
        local _, incident = CreateIncidentWithEntity(7, playerPed, 4, 20.0)
        incidents[#incidents + 1] = { handle = incident, expiresAt = GetGameTimer() + INCIDENT_LIFETIME }
        SetDispatchCopsForPlayer(PlayerId(), true)
    elseif victimIsVehicle then
        local model = GetEntityModel(victim)
        for _, copModel in ipairs(SKPolice.PoliceVehicles) do
            if copModel == model then return end
        end
        if not hasWitness(victim) then return end
        -- Most fender-benders go unreported.
        if math.random() > TRAFFIC_COLLISION_REPORT_CHANCE then return end
    else
        return
    end

    crimeCooldown = GetGameTimer()
    SetPlayerWantedLevel(PlayerId(), 1, false)
    SetPlayerWantedLevelNow(PlayerId(), false)
end)

CreateThread(function()
    while true do
        Wait(5000)
        if SKPolice.isInFreeroam() and #incidents > 0 then
            local now = GetGameTimer()
            for i = #incidents, 1, -1 do
                if now >= incidents[i].expiresAt then
                    DeleteIncident(incidents[i].handle)
                    table.remove(incidents, i)
                end
            end
        end
    end
end)

-- ── Radar detector ──────────────────────────────────────────────────────────
--
-- Beeps faster the closer the nearest trap cop is.

CreateThread(function()
    local lastBeep = 0
    while true do
        Wait(50)
        if not SKPolice.isInFreeroam() then
            Wait(1000)
        elseif SKPolice.isChasing() then
            Wait(500)
        elseif not policeDisabled and SKPolice.RadarDetector.enabled and IsPedInAnyVehicle(PlayerPedId(), false) then
            local maxD = SKPolice.RadarDetector.maxDetectDistance
            local d    = getNearestTrapCopDistance(maxD)
            if d <= maxD then
                local t = math.max(0.0, math.min(1.0, d / maxD))
                local interval = math.floor(
                    SKPolice.RadarDetector.minIntervalMs
                    + (SKPolice.RadarDetector.maxIntervalMs - SKPolice.RadarDetector.minIntervalMs) * t
                )
                if GetGameTimer() - lastBeep >= interval then
                    SK.PlaySound('radar_detector')
                    lastBeep = GetGameTimer()
                end
            else
                Wait(250)
            end
        else
            Wait(200)
        end
    end
end)

-- ── Pursuit state machine ───────────────────────────────────────────────────

CreateThread(function()
    local bustedIn  = 4
    local wasInFreeroam = true

    while true do
        Wait(250)

        if not SKPolice.isInFreeroam() then
            -- Stand down on the way out of freeroam (race start, car meet).
            if wasInFreeroam then
                wasInFreeroam = false
                bustedIn = 4
                SKPolice.resetPursuit()
                ClearPlayerWantedLevel(PlayerId())
            end
            Wait(1000)
        else
            wasInFreeroam = true

            if policeDisabled then
                if GetPlayerWantedLevel(PlayerId()) > 0 then
                    ClearPlayerWantedLevel(PlayerId())
                end
            elseif IsPedInAnyVehicle(PlayerPedId(), false) and GetPlayerWantedLevel(PlayerId()) > 0 then
                if not pursuit.active then
                    pursuit.active  = true
                    pursuit.started = GetGameTimer()
                end

                local _, isNear = SKPolice.IsNearPolice(12.0)
                if Cinematic then
                    bustedIn = 4
                    setBustCountdown(nil)
                elseif isNear and GetEntitySpeed(PlayerPedId()) < 3.0 then
                    Wait(750)
                    bustedIn = bustedIn - 1
                    if bustedIn > 0 then
                        setBustCountdown(bustedIn)
                    else
                        -- Re-arm either way: a refused bust retries, and a
                        -- successful one must not leave the counter negative
                        -- (which would silently disarm the next pursuit).
                        setBustCountdown(nil)
                        SKPolice.busted()
                        bustedIn = 4
                    end
                else
                    bustedIn = 4
                    setBustCountdown(nil)
                end
            else
                bustedIn = 4
                setBustCountdown(nil)

                if pursuit.active or pursuit.running then
                    TriggerServerEvent('sk_streetkings:police:escaped')
                    pursuit.active  = false
                    pursuit.running = false
                    pursuit.started = nil
                    for _, pt in ipairs(SKPolice.TrapPoints) do
                        if pt._pendingCleanup then
                            deleteTrap(pt)
                            pt._triggered      = false
                            pt._pendingCleanup = false
                        end
                    end
                end
            end
        end
    end
end)

-- ── Lifecycle ───────────────────────────────────────────────────────────────
--
-- Upstream drove this from freeroam_c's enter/exit hooks. There is no freeroam
-- shell here, so traps come up once on start and the loops above gate on game
-- state instead.

CreateThread(function()
    SK.WaitForControl()
    Wait(1500)
    local locations = lib.callback.await('sk_streetkings:police:getActiveTraps', false)
    if locations then SKPolice.InitTrapPoints(locations) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entry in ipairs(incidents) do
        DeleteIncident(entry.handle)
    end
    incidents = {}
    clearTrapPoints()
    SetTimeScale(1.0)
    RenderScriptCams(false, true, 0, true, true)
end)

exports('IsPoliceChasing', SKPolice.isChasing)
exports('GetWantedLevel', function() return GetPlayerWantedLevel(PlayerId()) end)
exports('IsNearPolice', SKPolice.IsNearPolice)
