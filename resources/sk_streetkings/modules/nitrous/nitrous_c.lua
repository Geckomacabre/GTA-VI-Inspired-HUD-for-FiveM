-- Nitrous, ported from streetkings modules/nitrous/nitrous_c.lua.
--
-- The physics, recharge model and effects are unchanged: boost consumes fuel at
-- 1.0/sec, applies an engine torque multiplier plus GTA's own vehicle boost,
-- and refills from drifting, near-missing traffic, driving into oncoming
-- traffic, and clearing race checkpoints.
--
-- Three things were rewired for this server:
--   * the NUI gauge became an SKHud widget (bottom-centre-left, clear of um_hud)
--   * the tier no longer comes from StreetKings' shop
--     (streetkings:shop:getActiveVehicleNitrous); it comes from
--     Config.Nitrous.defaultTier, overridable per-player by the server
--   * freeroamEnter/freeroamExit events became a game-state watcher, since the
--     old ones were fired by StreetKings' own state machine

if not Config.Modules.nitrous then return end

SKNitrous = {}

local INPUT_KEYBOARD_LEFT_ALT = 19
local INPUT_CONTROLLER_FACE_X = 179

local LEVELS = Config.Nitrous.tiers

local CHECKPOINT_REFILL       = Config.Nitrous.checkpointRefill
local NEAR_MISS_REFILL        = Config.Nitrous.nearMissRefill
local DRIFT_REFILL_PER_SEC    = Config.Nitrous.driftRefillPerSec
local ONCOMING_REFILL_PER_SEC = Config.Nitrous.oncomingRefillPerSec

local NEAR_MISS_COOLDOWN_MS    = 2200
local RECHARGE_SCAN_INTERVAL_MS = 120
local BACKFIRE_INTERVAL_MS     = 85
local BACKFIRE_SCALE           = 1.25
local BACKFIRE_ASSET           = 'core'
local BACKFIRE_EFFECT          = 'veh_backfire'

local EXHAUST_BONES = {
    'exhaust',    'exhaust_2',  'exhaust_3',  'exhaust_4',
    'exhaust_5',  'exhaust_6',  'exhaust_7',  'exhaust_8',
    'exhaust_9',  'exhaust_10', 'exhaust_11', 'exhaust_12',
    'exhaust_13', 'exhaust_14', 'exhaust_15', 'exhaust_16',
}

-- Server-forced tier, set through sk_streetkings:nitrous:setTier. Overrides
-- whatever is fitted to the vehicle; nil means "use the vehicle's own bottle".
local playerTierOverride = nil
local vehicle      = 0
local inVeh        = false
local active       = false
local boosting     = false
local multiplayerRaceDisabled = false
local fuel         = 0.0
local capacity     = 0.0
local torque       = 1.0
local runToken     = 0
local nearMissCooldowns = {}
local lastScanAt   = 0
local oncomingActiveUntil = 0
local backfireAssetRequested = false

-- ── HUD ─────────────────────────────────────────────────────────────────────

SKHud.register('nitrous', function(data)
    local a = SKHud.Anchor.bottomCentreLeft
    local colour = data.boosting and SKHud.Palette.warning or SKHud.Palette.accent
    SKHud.Bar(a.x, a.y, 0.13, 0.011, data.pct, colour)
    SKHud.Text('NOS', a.x - 0.078, a.y - 0.014, 0.26, SKHud.Palette.textDim)
end)

-- Mirrors the gauge into the state bag vice_hud's nitrous icon reads. Assigned
-- further down, once activeTier() exists.
local publishHudState

local function sendHudUpdate()
    publishHudState()
    -- vice_hud draws nitrous as a ring on its vehicle panel, fed by the state
    -- bag just published. With it running, the bar here would be a second
    -- gauge for the same tank.
    if not active or GetResourceState('vice_hud') == 'started' then
        SKHud.clear('nitrous')
        return
    end
    SKHud.set('nitrous', {
        pct      = capacity > 0 and fuel / capacity or 0,
        boosting = boosting,
    })
end

-- ── Gating ──────────────────────────────────────────────────────────────────

---@param veh integer
---@return boolean
local function isAllowedClass(veh)
    local c = GetVehicleClass(veh)
    -- Excludes cycles, boats, helicopters, planes and trains.
    return c ~= 13 and c ~= 14 and c ~= 15 and c ~= 16 and c ~= 21
end

-- Tier fitted to the vehicle the player is currently in, resolved from the
-- server. nil until the lookup completes, so nitrous stays off rather than
-- flickering on with the wrong tier.
local vehicleTier = nil
local tierPlate   = nil
local tierToken   = 0

---@param veh integer
---@return string|nil
local function plateOf(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return nil end
    return (plate:gsub('%s+$', ''))
end

--- Asks the server which bottle this vehicle has. Fire and forget: the poll
--- below picks the answer up once it lands.
---@param veh integer
local function refreshVehicleTier(veh)
    local plate = plateOf(veh)

    if not plate then
        vehicleTier, tierPlate = nil, nil
        return
    end

    tierToken = tierToken + 1
    local token = tierToken

    CreateThread(function()
        local tier = lib.callback.await('sk_streetkings:tuning:getNitrous', false, plate)
        -- A later request already superseded this one.
        if token ~= tierToken then return end
        vehicleTier = tier
        tierPlate   = plate
    end)
end

--- Whether this particular vehicle is fitted with nitrous.
---
--- Upstream asked its own tuning shop per vehicle. That shop is not ported, so
--- the answer comes from `sk_vehicle_upgrades` instead, bought through the
--- Nitrous row this resource adds to um_customs' Performance menu.
---@param veh integer
---@return boolean
local function vehicleHasNitrous(veh)
    return vehicleTier ~= nil and tierPlate ~= nil and tierPlate == plateOf(veh)
end

--- The tier actually in use: a server override if one is set, otherwise
--- whatever is fitted to this vehicle.
---@return string|nil
local function activeTier()
    return playerTierOverride or vehicleTier
end

-- Contract shared with the mod shop (Lenonida_customs README, "HUD integration"):
-- installed false hides the icon, level is the tank 0-1, ready false greys it,
-- key is the control to hold (a control id, since this module polls one).
publishHudState = function()
    local tier = active and activeTier() or nil
    LocalPlayer.state:set('customs:nitrous', {
        installed = active,
        kit       = tier,
        label     = tier and LEVELS[tier] and LEVELS[tier].label or nil,
        level     = (active and capacity > 0) and fuel / capacity or 0.0,
        active    = boosting,
        ready     = active and fuel > 0.0,
        key       = INPUT_KEYBOARD_LEFT_ALT,
        padKey    = INPUT_CONTROLLER_FACE_X,
    }, false)
end

---@return boolean
local function isAllowedState()
    if multiplayerRaceDisabled then return false end
    return SKDrivingStates[SKC.GetGameState()] == true
end

---@param amount number
local function addFuel(amount)
    if not active then return end
    fuel = math.min(capacity, fuel + amount)
end

---@param enabled boolean
local function setBoosting(enabled)
    if boosting == enabled then return end
    boosting = enabled

    if vehicle ~= 0 then
        SetVehicleBoostActive(vehicle, enabled)
        if not enabled then
            SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
        end
    end

    if enabled then
        StopScreenEffect('RaceTurbo')
        StartScreenEffect('RaceTurbo', 0, false)
        ShakeGameplayCam('SKY_DIVING_SHAKE', 0.12)
    else
        StopGameplayCamShaking(true)
        StopScreenEffect('RaceTurbo')
    end
end

-- ── Backfire VFX ────────────────────────────────────────────────────────────

---@return boolean
local function hasBackfireAsset()
    if HasNamedPtfxAssetLoaded(BACKFIRE_ASSET) then return true end
    if not backfireAssetRequested then
        backfireAssetRequested = true
        RequestNamedPtfxAsset(BACKFIRE_ASSET)
    end
    return false
end

---@param veh integer
local function emitExhaustBackfire(veh)
    if not hasBackfireAsset() then return end

    for i = 1, #EXHAUST_BONES do
        local boneIndex = GetEntityBoneIndexByName(veh, EXHAUST_BONES[i])
        if boneIndex ~= -1 then
            local bonePos = GetWorldPositionOfEntityBone(veh, boneIndex)
            local offset = GetOffsetFromEntityGivenWorldCoords(veh, bonePos.x, bonePos.y, bonePos.z)
            UseParticleFxAssetNextCall(BACKFIRE_ASSET)
            StartParticleFxNonLoopedOnEntity(BACKFIRE_EFFECT, veh, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, BACKFIRE_SCALE, false, false, false)
        end
    end
end

-- ── Input ───────────────────────────────────────────────────────────────────

---@return boolean
local function isNitrousPressed()
    local padIndex = SKInput.getActivePadIndex()

    if SKInput.isUsingKeyboard(padIndex) then
        DisableControlAction(0, INPUT_KEYBOARD_LEFT_ALT, true)
        return IsDisabledControlPressed(0, INPUT_KEYBOARD_LEFT_ALT)
    end

    DisableControlAction(padIndex, INPUT_CONTROLLER_FACE_X, true)
    return IsDisabledControlPressed(padIndex, INPUT_CONTROLLER_FACE_X)
        or IsControlPressed(padIndex, INPUT_CONTROLLER_FACE_X)
end

-- ── Recharge ────────────────────────────────────────────────────────────────

---@param veh integer
---@param other integer
---@return boolean
local function isTrafficVehicle(veh, other)
    if other == veh or not DoesEntityExist(other) then return false end
    local driver = GetPedInVehicleSeat(other, -1)
    return driver ~= 0 and not IsPedAPlayer(driver)
end

---@param veh integer
---@param other integer
---@return boolean
local function isOtherVehicleAhead(veh, other)
    local otherPos = GetEntityCoords(other)
    local localPos = GetOffsetFromEntityGivenWorldCoords(veh, otherPos.x, otherPos.y, otherPos.z)
    return localPos.y > -2.0 and localPos.y < 22.0
end

---@param veh integer
---@return number
local function getNearMissRecharge(veh)
    local now = GetGameTimer()
    local pos = GetEntityCoords(veh)
    local speed = GetEntitySpeed(veh)
    if speed < 18.0 then return 0.0 end

    for _, other in ipairs(GetGamePool('CVehicle')) do
        if isTrafficVehicle(veh, other) and isOtherVehicleAhead(veh, other) then
            local distance = #(pos - GetEntityCoords(other))
            if distance <= 4.2 and math.abs(speed - GetEntitySpeed(other)) >= 8.0 then
                local cooldownUntil = nearMissCooldowns[other] or 0
                if now >= cooldownUntil then
                    nearMissCooldowns[other] = now + NEAR_MISS_COOLDOWN_MS
                    return NEAR_MISS_REFILL
                end
            end
        end
    end

    return 0.0
end

---@param veh integer
---@return boolean
local function isInOncomingTraffic(veh)
    if GetEntitySpeed(veh) < 16.0 then return false end

    local forward = GetEntityForwardVector(veh)
    for _, other in ipairs(GetGamePool('CVehicle')) do
        if isTrafficVehicle(veh, other) and isOtherVehicleAhead(veh, other) then
            local otherForward = GetEntityForwardVector(other)
            local dot = forward.x * otherForward.x + forward.y * otherForward.y + forward.z * otherForward.z
            if dot < -0.55 then return true end
        end
    end

    return false
end

---@param veh integer
---@param frameSeconds number
---@return number
local function getDriftRecharge(veh, frameSeconds)
    if IsEntityInAir(veh) then return 0.0 end
    if GetEntitySpeed(veh) < 12.0 then return 0.0 end

    local velocity = GetEntitySpeedVector(veh, true)
    local sideways = math.abs(velocity.x)
    local forward  = math.abs(velocity.y)
    if sideways < 3.0 or sideways / math.max(forward, 0.1) < 0.32 then
        return 0.0
    end

    return DRIFT_REFILL_PER_SEC * frameSeconds
end

---@param frameSeconds number
local function updateRecharge(frameSeconds)
    if vehicle == 0 or fuel >= capacity or boosting then return end

    local amount = getDriftRecharge(vehicle, frameSeconds)
    local now = GetGameTimer()

    if now <= oncomingActiveUntil then
        amount = amount + ONCOMING_REFILL_PER_SEC * frameSeconds
    end

    -- The traffic scans walk the whole vehicle pool, so they run on an interval
    -- rather than every frame.
    if now - lastScanAt >= RECHARGE_SCAN_INTERVAL_MS then
        lastScanAt = now
        if isInOncomingTraffic(vehicle) then
            oncomingActiveUntil = now + RECHARGE_SCAN_INTERVAL_MS + 50
        end
        amount = amount + getNearMissRecharge(vehicle)
    end

    if amount > 0 then addFuel(amount) end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

local function shutdown()
    setBoosting(false)
    active   = false
    vehicle  = 0
    inVeh    = false
    fuel     = 0.0
    capacity = 0.0
    torque   = 1.0
    nearMissCooldowns = {}
    oncomingActiveUntil = 0
    SKHud.clear('nitrous')
    publishHudState()
end

local function startLoop()
    runToken = runToken + 1
    local token = runToken

    CreateThread(function()
        local lastHudPct = -1.0
        local lastHudBoosting = false
        local nextBackfireAt = 0

        while token == runToken do
            if not active or vehicle == 0 then
                Wait(250)
                goto continue
            end

            if not isAllowedState() then
                setBoosting(false)
                Wait(250)
                goto continue
            end

            if GetPedInVehicleSeat(vehicle, -1) ~= cache.ped or not GetIsVehicleEngineRunning(vehicle) then
                setBoosting(false)
                lastHudPct = -1.0
                Wait(100)
                goto continue
            end

            Wait(0)

            local frameSeconds = math.max(GetFrameTime(), 0.001)
            local pressed = isNitrousPressed()

            if pressed and fuel > 0.0 and not IsVehicleStopped(vehicle) then
                setBoosting(true)
                fuel = math.max(0.0, fuel - frameSeconds)
                SetVehicleEngineTorqueMultiplier(vehicle, torque)
                local now = GetGameTimer()
                if now >= nextBackfireAt then
                    nextBackfireAt = now + BACKFIRE_INTERVAL_MS
                    emitExhaustBackfire(vehicle)
                end
            else
                setBoosting(false)
                updateRecharge(frameSeconds)
            end

            if fuel <= 0.0 then setBoosting(false) end

            local pct = capacity > 0 and fuel / capacity or 0
            if math.abs(pct - lastHudPct) >= 0.01 or boosting ~= lastHudBoosting then
                lastHudPct = pct
                lastHudBoosting = boosting
                sendHudUpdate()
            end

            ::continue::
        end
    end)
end

--- Stops nitrous without clearing which tier the player owns.
local function deactivate()
    setBoosting(false)
    active   = false
    fuel     = 0.0
    capacity = 0.0
    SKHud.clear('nitrous')
    publishHudState()
end

--- True when the current vehicle should have a working bottle right now.
---@return boolean
local function shouldBeActive()
    if vehicle == 0 or not inVeh then return false end
    if multiplayerRaceDisabled then return false end
    if not LEVELS[activeTier()] then return false end
    if not isAllowedState() then return false end
    if GetPedInVehicleSeat(vehicle, -1) ~= cache.ped then return false end
    if not isAllowedClass(vehicle) then return false end
    -- A server override applies to whatever the player is driving; otherwise
    -- the bottle has to belong to this specific vehicle.
    return playerTierOverride ~= nil or vehicleHasNitrous(vehicle)
end

local function enableNitrous()
    -- Every guard funnels through deactivate() rather than bailing out, so
    -- stepping from a nitrous car into one without cannot leave `active` set
    -- with the previous vehicle's capacity still loaded.
    if not shouldBeActive() then
        deactivate()
        return
    end

    local level = LEVELS[activeTier()]
    capacity = level.capacity
    torque   = level.torque
    fuel     = capacity
    active   = true
    sendHudUpdate()
    startLoop()
end

lib.onCache('vehicle', function(veh)
    if veh and veh ~= 0 then
        setBoosting(false)
        vehicle = veh
        inVeh   = true
        -- Which bottle this car has is a server lookup, so nitrous stays off
        -- until it lands. The poll below switches it on once it does.
        refreshVehicleTier(veh)
        enableNitrous()
    else
        deactivate()
        inVeh       = false
        vehicle     = 0
        vehicleTier = nil
        tierPlate   = nil
    end
end)

--- Fired by the tuning module the moment a bottle is bought or removed, so the
--- gauge appears without waiting for the player to get out and back in.
AddEventHandler('sk_streetkings:nitrous:refresh', function()
    if cache.vehicle and cache.vehicle ~= 0 then
        refreshVehicleTier(cache.vehicle)
    end
end)

-- StreetKings drove this off its own freeroamEnter/freeroamExit events. Here the
-- situation is polled instead, so entering the car meet (or a menu) suspends
-- nitrous and leaving resumes it without needing every state to fire an event.
--
-- The poll also covers the tier lookup landing a moment after the player got
-- in, and a bottle being bought or sold while they sit in the car.
CreateThread(function()
    while true do
        Wait(500)

        local wanted = shouldBeActive()
        if wanted and not active then
            enableNitrous()
        elseif not wanted and active then
            deactivate()
        end
    end
end)

-- ── Public surface ──────────────────────────────────────────────────────────

--- Called by the racing module each time a checkpoint is cleared. Registered as
--- a net event so it also works if the server ever wants to grant a refill; the
--- handler still fires for a plain local TriggerEvent from the racing module.
RegisterNetEvent('sk_streetkings:nitrous:checkpointCleared', function()
    addFuel(CHECKPOINT_REFILL)
    sendHudUpdate()
end)

--- Multiplayer races can ban nitrous; the host picks this per lobby.
---@param disabled boolean
RegisterNetEvent('sk_streetkings:nitrous:setMultiplayerRaceDisabled', function(disabled)
    multiplayerRaceDisabled = disabled == true
    -- enableNitrous re-reads every condition, so it turns the bottle off or
    -- back on as appropriate without repeating the guards here.
    enableNitrous()
end)

--- Server can grant a better tier (or revoke nitrous entirely) per player.
---@param tier string|nil one of Config.Nitrous.tiers, or nil to disable
RegisterNetEvent('sk_streetkings:nitrous:setTier', function(tier)
    playerTierOverride = LEVELS[tier] and tier or nil
    enableNitrous()
end)

---@return string|nil the tier currently in use, or nil if there is no bottle
function SKNitrous.getType()
    return activeTier()
end

exports('GetNitrousTier', SKNitrous.getType)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then shutdown() end
end)
