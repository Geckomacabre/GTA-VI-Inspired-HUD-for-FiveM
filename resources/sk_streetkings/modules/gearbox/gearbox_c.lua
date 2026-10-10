-- Manual gearbox, ported from streetkings modules/gearbox/gearbox_c.lua.
--
-- The transmission model is unchanged: it takes over GTA's automatic box by
-- pinning the current gear, zeroing drive force during a shift window, and
-- feeding RPM manually while the clutch is engaged. Expert mode requires the
-- clutch and stalls the engine below a throttle threshold.
--
-- Rewired for this server:
--   * gear badge and the stall mash-prompt are SKHud widgets rather than NUI
--   * mode comes from /gearbox (persisted per character) instead of
--     StreetKings' per-vehicle shop upgrade
--   * SKPauseMenu / SKSoundtrack hooks dropped (those modules are not ported);
--     the pause check falls back to the IsPauseMenuActive native
--   * Lua 5.4 compound assignments written out longhand

if not Config.Modules.gearbox then return end

SKGearbox = {}

local MODES = {
    beginner = {
        noClutchMult   = 1.0,
        withClutchMult = 1.0,
        stallThreshold = 0.0,
        stallTimer     = 1000,
    },
    expert = {
        noClutchMult   = 1.0,
        withClutchMult = 0.5,
        stallThreshold = 0.23,
        stallTimer     = 1000,
        requireClutch  = true,
    },
}

local STALL_PRESSES_NEEDED = 20
local STALL_TIME_MS        = 5000
local STALL_RETRY_DELAY_MS = 3000
local STALL_INTERACTION_BLOCK_MS = 1000
local INPUT_VEH_HORN       = 86

local UPSHIFT_BOOST_MULT = 1.18
local UPSHIFT_BOOST_MS   = 450

local activeGearboxType = nil

local noClutchMult   = 1.0
local withClutchMult = 1.0
local stallThreshold = 0.0
local stallTimer     = 1000
local requireClutch  = false

local vehicle  = 0
local inVeh    = false
local active   = false

local clutchDown = false
local reqUp      = false
local reqDown    = false

local gear      = 1
local gearCount = 1
local shifting  = false
local shiftDir  = 0

local origForce   = 0.0
local origInertia = 0.0
local origMaxVel  = 0.0

local shiftTimeUp   = 0.0
local shiftTimeDown = 0.0

local shiftEndsAt, shiftDur     = 0, 0
local penaltyEndsAt, penaltyDur = 0, 0
local shiftPct, penaltyPct      = 0, 0

local stalled    = false
local restarted  = true
local limiter    = false
local modified   = false
local stallCount = 0
local stallInteractionBlockedUntil = 0

local runToken = 0

local setGearHash = GetHashKey('SET_VEHICLE_CURRENT_GEAR') & 0xFFFFFFFF

local function SetGear(veh, g)
    Citizen.InvokeNative(setGearHash, veh, g)
end

local function SetReducedRatio(veh, val)
    Citizen.InvokeNative(0x337EF33DA3DDB990, veh, val)
end

-- ── HUD ─────────────────────────────────────────────────────────────────────

SKHud.register('gearbox', function(data)
    local a = SKHud.Anchor.bottomCentreGear
    SKHud.Panel(a.x, a.y - 0.004, 0.048, 0.052, SKHud.Palette.panelDark)

    local label = data.gear == -1 and 'R' or (data.gear == 0 and 'N' or tostring(data.gear))
    local colour = data.shifting and SKHud.Palette.warning
        or (data.clutch and SKHud.Palette.info or SKHud.Palette.accent)
    SKHud.Text(label, a.x, a.y - 0.026, 0.62, colour, true, 7)
    SKHud.Text(data.mode:upper(), a.x, a.y + 0.010, 0.22, SKHud.Palette.textDim, true)
end)

SKHud.register('gearboxStall', function(data)
    SKHud.Panel(0.5, 0.72, 0.30, 0.085, SKHud.Palette.panelDark)

    if data.state == 'countdown' then
        SKHud.Text('ENGINE STALLED', 0.5, 0.690, 0.42, SKHud.Palette.danger, true, 7)
        SKHud.Text(('Retrying in %ds'):format(data.seconds or 0), 0.5, 0.730, 0.30, SKHud.Palette.textDim, true)
        return
    end

    if data.state == 'success' then
        SKHud.Text('ENGINE STARTED', 0.5, 0.700, 0.42, SKHud.Palette.success, true, 7)
        return
    end

    SKHud.Text(('MASH  %s  TO RESTART'):format(data.key or 'E'), 0.5, 0.688, 0.38, SKHud.Palette.text, true, 7)
    SKHud.Bar(0.5, 0.735, 0.26, 0.012, data.pct or 0.0, SKHud.Palette.success)
    -- Time remaining drains right-to-left underneath the progress bar.
    SKHud.Bar(0.5, 0.752, 0.26, 0.006, data.timePct or 0.0, SKHud.Palette.danger)
end)

local function updateGearHud()
    if not active or not activeGearboxType then
        SKHud.clear('gearbox')
        return
    end
    SKHud.set('gearbox', {
        gear     = gear,
        shifting = shifting,
        clutch   = clutchDown,
        mode     = activeGearboxType,
    })
end

-- ── Gating ──────────────────────────────────────────────────────────────────

local function isAllowedClass(veh)
    local c = GetVehicleClass(veh)
    return c ~= 13 and c ~= 14 and c ~= 15 and c ~= 16 and c ~= 21
end

---@return boolean
local function isAllowedState()
    return SKDrivingStates[SKC.GetGameState()] == true
end

local function updateTimers()
    local now  = GetGameTimer()
    shiftPct   = (shiftEndsAt   > now and shiftDur   > 0) and (shiftEndsAt   - now) / shiftDur   or 0
    penaltyPct = (penaltyEndsAt > now and penaltyDur > 0) and (penaltyEndsAt - now) / penaltyDur or 0
end

local function startShift(ms)
    shiftDur    = ms
    shiftEndsAt = GetGameTimer() + ms
end

local function startPenalty(ms)
    penaltyDur    = ms
    penaltyEndsAt = GetGameTimer() + ms
end

local function playShiftAnim()
    local dict = 'veh@driveby@first_person@passenger_rear_right_handed@smg'
    local anim = 'outro_90r'
    if not SK.LoadAnimDict(dict) then return end
    TaskPlayAnim(cache.ped, dict, anim, 8.0, 1.0, 500, 48, 0, false, false, false)
    Wait(1000)
    StopAnimTask(cache.ped, dict, anim, 1.0)
end

local function playShiftSound()
    PlaySoundFromEntity(-1, 'COLLECT_IN_BAG', vehicle, 'NIGEL_1D_SOUNDSET', false, 0)
end

-- ── Keybinds ────────────────────────────────────────────────────────────────

lib.addKeybind({
    name        = 'sk_gears_upshift',
    description = 'Manual Gearbox: Shift Up',
    defaultKey  = 'UP',
    defaultMapper = 'KEYBOARD',
    secondaryKey = 'RRIGHT_INDEX',
    secondaryMapper = 'PAD_DIGITALBUTTONANY',
    onPressed   = function()
        if not active then return end
        if gear + 1 <= gearCount then
            CreateThread(playShiftAnim)
            reqUp = true
        end
    end,
})

lib.addKeybind({
    name        = 'sk_gears_downshift',
    description = 'Manual Gearbox: Shift Down',
    defaultKey  = 'DOWN',
    defaultMapper = 'KEYBOARD',
    secondaryKey = 'RUP_INDEX',
    secondaryMapper = 'PAD_DIGITALBUTTONANY',
    onPressed   = function()
        if not active then return end
        if gear - 2 >= -1 then
            CreateThread(playShiftAnim)
            reqDown = true
        end
    end,
})

lib.addKeybind({
    name        = 'sk_gears_clutch',
    description = 'Manual Gearbox: Clutch',
    defaultKey  = 'LSHIFT',
    defaultMapper = 'KEYBOARD',
    secondaryKey = 'L1_INDEX',
    secondaryMapper = 'PAD_DIGITALBUTTONANY',
    onPressed   = function() clutchDown = true  end,
    onReleased  = function() clutchDown = false end,
})

-- ── Stall handling ──────────────────────────────────────────────────────────

local stallGameActive = false
local stallGameToken  = 0

---@return boolean
local function isPauseMenuOpen()
    return IsPauseMenuActive()
end

local function doRestart()
    if GetIsVehicleEngineRunning(vehicle) or IsVehicleEngineStarting(vehicle) then return end
    if GetVehicleEngineHealth(vehicle) <= 0.0 then
        SetVehicleEngineHealth(vehicle, 300.0)
    end
    SetVehicleEngineOn(vehicle, true, true, false)
    stallInteractionBlockedUntil = GetGameTimer() + STALL_INTERACTION_BLOCK_MS
    gear       = 1
    SetGear(vehicle, 1)
    stallCount = 0
    stalled    = false
    restarted  = true
end

---@param targetVehicle integer
local function forceRestartAfterTransition(targetVehicle)
    if not stalled then return end
    stallGameToken  = stallGameToken + 1
    stallGameActive = false
    stallCount      = 0
    stalled         = false
    restarted       = true
    gear            = 1

    SKHud.clear('gearboxStall')

    if targetVehicle == 0 or not DoesEntityExist(targetVehicle) then
        targetVehicle = vehicle
    end
    if targetVehicle == 0 or not DoesEntityExist(targetVehicle) then return end

    vehicle = targetVehicle
    if GetVehicleEngineHealth(vehicle) <= 0.0 then
        SetVehicleEngineHealth(vehicle, 300.0)
    end
    SetVehicleEngineOn(vehicle, true, true, false)
    stallInteractionBlockedUntil = GetGameTimer() + STALL_INTERACTION_BLOCK_MS
    SetGear(vehicle, 1)
end

local function startStallMinigame()
    if stallGameActive then return end
    stallGameActive = true
    stallGameToken  = stallGameToken + 1
    local token     = stallGameToken

    CreateThread(function()
        while token == stallGameToken and stalled do
            local presses  = 0
            local deadline = GetGameTimer() + STALL_TIME_MS

            while token == stallGameToken and stalled and GetGameTimer() < deadline do
                Wait(0)
                DisableControlAction(0, 14, true)
                DisableControlAction(0, INPUT_VEH_HORN, true)

                if isPauseMenuOpen() then
                    -- Freeze the attempt while paused rather than burning the clock.
                    SKHud.clear('gearboxStall')
                    deadline = deadline + math.floor(GetFrameTime() * 1000.0)
                else
                    SKHud.set('gearboxStall', {
                        state   = 'mash',
                        key     = SKInput.getInteractLabel(),
                        pct     = presses / STALL_PRESSES_NEEDED,
                        timePct = math.max(0.0, (deadline - GetGameTimer()) / STALL_TIME_MS),
                    })

                    local control = SKInput.getInteractControl()
                    if IsControlJustPressed(0, control) then
                        presses = presses + 1

                        if presses >= STALL_PRESSES_NEEDED then
                            SKHud.set('gearboxStall', { state = 'success' })
                            Wait(600)
                            SKHud.clear('gearboxStall')
                            stallGameActive = false
                            stallCount = 0
                            doRestart()
                            return
                        end
                    end
                end
            end

            if token ~= stallGameToken or not stalled then break end

            if isPauseMenuOpen() then
                SKHud.clear('gearboxStall')
                while token == stallGameToken and stalled and isPauseMenuOpen() do
                    Wait(100)
                end
                if token ~= stallGameToken or not stalled then break end
            else
                local retrySeconds = math.floor(STALL_RETRY_DELAY_MS / 1000)
                for remaining = retrySeconds, 1, -1 do
                    SKHud.set('gearboxStall', { state = 'countdown', seconds = remaining })
                    Wait(1000)
                    if token ~= stallGameToken or not stalled then break end
                end
            end
        end

        stallGameActive = false
        SKHud.clear('gearboxStall')
    end)
end

local function doStall()
    if not GetIsVehicleEngineRunning(vehicle) or IsVehicleEngineStarting(vehicle) then return end
    SetVehicleEngineOn(vehicle, false, true, true)
    SetGear(vehicle, gear)
    stalled   = true
    restarted = false
    startStallMinigame()
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

local function shutdown()
    if vehicle ~= 0 and DoesEntityExist(vehicle) then
        SetReducedRatio(vehicle, false)
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce',      origForce)
        SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', origMaxVel)
    end
    stallGameToken  = stallGameToken + 1
    stallGameActive = false
    SKHud.clear('gearboxStall')
    SKHud.clear('gearbox')

    active        = false
    shifting      = false
    limiter       = false
    modified      = false
    stalled       = false
    restarted     = true
    stallCount    = 0
    requireClutch = false
    reqUp         = false
    reqDown       = false
    shiftEndsAt   = 0 ; shiftDur     = 0
    penaltyEndsAt = 0 ; penaltyDur   = 0
    shiftPct      = 0 ; penaltyPct   = 0
end

local function startLoop()
    runToken = runToken + 1
    local token = runToken

    CreateThread(function()
        local clutchReady = false
        local clutchTimer = 0
        local lastModTick = 0
        local nativeGear  = 0
        local lastShiftUp = false
        local boostEndsAt = 0
        local lastHudGear, lastHudShifting, lastHudClutch = nil, nil, nil

        while token == runToken do
            if not active or vehicle == 0 then
                Wait(250)
                goto continue
            end

            if GetPedInVehicleSeat(vehicle, -1) ~= cache.ped then
                shutdown()
                Wait(250)
                goto continue
            end

            Wait(0)

            local now     = GetGameTimer()
            local frameMs = math.max(GetFrameTime() * 1000.0, 1.0)
            local rpm     = GetVehicleCurrentRpm(vehicle)

            updateTimers()

            -- Block GTA's own shift-up/shift-down inputs.
            DisableControlAction(0, 363, true)
            DisableControlAction(0, 364, true)

            if reqUp then
                if requireClutch and not clutchDown then reqUp = false goto continue end
                local prev = gear
                if gear == -1 then
                    gear = 1
                elseif gear >= 1 and gear < gearCount then
                    gear = gear + 1
                end
                if gear ~= prev then
                    shiftDir    = shiftDir + (prev == -1 and 2 or 1)
                    lastShiftUp = true
                    shifting    = true
                    local ms = clutchDown
                        and (shiftTimeUp * withClutchMult)
                        or  (shiftTimeUp * noClutchMult)
                    startShift(ms)
                    if not clutchDown then startPenalty(shiftTimeUp * noClutchMult) end
                end
                reqUp = false
            end

            if reqDown then
                if requireClutch and not clutchDown then reqDown = false goto continue end
                local prev = gear
                if gear == 1 then
                    gear = -1
                elseif gear >= 2 then
                    gear = gear - 1
                end
                if gear ~= prev then
                    shiftDir    = shiftDir - (prev == 1 and 2 or 1)
                    lastShiftUp = false
                    shifting    = true
                    local ms = clutchDown
                        and (shiftTimeDown * withClutchMult)
                        or  (shiftTimeDown * noClutchMult)
                    startShift(ms)
                    if not clutchDown then startPenalty(shiftTimeDown * noClutchMult) end
                end
                reqDown = false
            end

            if shifting and shiftPct == 0 and penaltyPct == 0 then
                playShiftSound()
                if lastShiftUp then
                    boostEndsAt = GetGameTimer() + UPSHIFT_BOOST_MS
                end
                shifting = false
                shiftDir = 0
            end

            nativeGear = GetVehicleCurrentGear(vehicle)

            if rpm >= 1.0 then
                limiter = true
            elseif rpm < 0.95 then
                limiter = false
            end

            -- Give handling values half a second to settle after entry before
            -- taking over drive force, or the first frames fight the engine.
            if not clutchReady then
                clutchTimer = clutchTimer + 1
                if clutchTimer >= (500.0 / frameMs) then clutchReady = true end
            end

            if clutchReady then
                local clutchActive = shiftPct > 0 or penaltyPct > 0 or clutchDown
                if clutchActive then
                    local throttle = GetVehicleThrottleOffset(vehicle)
                    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', 0.0)
                    if not limiter then
                        if nativeGear == 0 then
                            if rpm < -throttle then
                                SetVehicleCurrentRpm(vehicle, rpm + (-throttle * origInertia * 0.02))
                            end
                        else
                            if rpm < throttle then
                                SetVehicleCurrentRpm(vehicle, rpm + (throttle * origInertia * 0.02))
                            end
                        end
                    end
                elseif not limiter then
                    local boost = (boostEndsAt > now) and UPSHIFT_BOOST_MULT or 1.0
                    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce', origForce * boost)
                end

                -- Re-applying the engine mod forces the game to pick up the
                -- handling float changes above.
                if (now - lastModTick) >= 500 then
                    lastModTick = now
                    SetVehicleMod(vehicle, 11, GetVehicleMod(vehicle, 11), false)
                end
            end

            if not shifting then
                SetGear(vehicle, gear == -1 and 0 or gear)
            end

            local spd = GetEntitySpeedVector(vehicle, true)
            if gear == -1 then
                if spd.y > -2.0 then DisableControlAction(0, 71, true) end
            else
                if spd.y < 0.5  then DisableControlAction(0, 72, true) end
            end

            local clutchActive = shiftPct > 0 or penaltyPct > 0 or clutchDown
            if stallThreshold > 0 and nativeGear >= 2 and not stalled and not clutchActive then
                if rpm < stallThreshold then
                    stallCount = stallCount + 1
                    if stallCount > (stallTimer / frameMs) then doStall() end
                else
                    stallCount = 0
                end
            elseif clutchActive then
                stallCount = 0
            end

            if stalled then
                if IsVehicleEngineStarting(vehicle) then
                    SetVehicleEngineOn(vehicle, false, true, true)
                end
                DisableControlAction(0, 14, true)
                SetGear(vehicle, gear == -1 and 0 or (gear == 0 and 1 or gear))
            end

            if GetIsVehicleEngineRunning(vehicle) then
                if stalled then
                    stallInteractionBlockedUntil = GetGameTimer() + STALL_INTERACTION_BLOCK_MS
                end
                stalled   = false
                restarted = true
            end

            if not shifting then
                if nativeGear == gearCount and not modified then
                    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', origMaxVel * 0.888)
                    modified = true
                elseif nativeGear ~= gearCount and modified then
                    SetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel', origMaxVel)
                    modified = false
                end
            end

            if gear ~= lastHudGear or shifting ~= lastHudShifting or clutchDown ~= lastHudClutch then
                lastHudGear, lastHudShifting, lastHudClutch = gear, shifting, clutchDown
                updateGearHud()
            end

            ::continue::
        end
    end)
end

local function enableManual()
    if vehicle == 0 or not inVeh then return end
    if GetPedInVehicleSeat(vehicle, -1) ~= cache.ped then return end
    if not isAllowedClass(vehicle) then return end
    if not activeGearboxType then return end

    local m = MODES[activeGearboxType] or MODES.beginner
    noClutchMult   = m.noClutchMult
    withClutchMult = m.withClutchMult
    stallThreshold = m.stallThreshold
    stallTimer     = m.stallTimer
    requireClutch  = m.requireClutch or false

    SetReducedRatio(vehicle, true)

    local upRate   = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fClutchChangeRateScaleUpShift')
    local downRate = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fClutchChangeRateScaleDownShift')
    gearCount      = GetVehicleHighGear(vehicle)
    shiftTimeUp    = (0.9 / upRate)   * 1000
    shiftTimeDown  = (0.9 / downRate) * 1000

    -- A fitted transmission upgrade shortens the shift windows.
    local transIdx = GetVehicleMod(vehicle, 13)
    if transIdx ~= -1 then
        local bonus = 1 + GetVehicleModModifierValue(vehicle, 13, transIdx) * 0.04
        if bonus > 1 then
            shiftTimeUp   = shiftTimeUp   - shiftTimeUp   / bonus
            shiftTimeDown = shiftTimeDown - shiftTimeDown / bonus
        end
    end

    gear       = 1
    stallCount = 0
    stalled    = false
    restarted  = true
    shifting   = false
    modified   = false
    limiter    = false
    active     = true

    updateGearHud()
    startLoop()
end

local function cacheHandlingFor(veh)
    origForce   = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveForce')
    origInertia = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fDriveInertia')
    origMaxVel  = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fInitialDriveMaxFlatVel')
end

lib.onCache('vehicle', function(veh)
    if veh and veh ~= 0 then
        vehicle = veh
        inVeh   = true
        cacheHandlingFor(veh)
        if activeGearboxType ~= nil and isAllowedState() then
            enableManual()
        end
    else
        shutdown()
        inVeh   = false
        vehicle = 0
    end
end)

-- Replaces StreetKings' freeroamEnter/freeroamExit events with a state watcher.
CreateThread(function()
    local wasAllowed = nil
    while true do
        Wait(500)
        local allowed = isAllowedState()
        if allowed ~= wasAllowed then
            wasAllowed = allowed
            if allowed then
                if activeGearboxType ~= nil and cache.vehicle and cache.vehicle ~= 0 then
                    vehicle = cache.vehicle
                    inVeh   = true
                    cacheHandlingFor(vehicle)
                    enableManual()
                end
            else
                shutdown()
            end
        end
    end
end)

-- ── Mode selection ──────────────────────────────────────────────────────────
-- StreetKings sold the gearbox as a per-vehicle shop upgrade. Here it is a
-- player preference, persisted on the character profile.

---@param mode string 'off' | 'beginner' | 'expert'
local function applyMode(mode)
    activeGearboxType = MODES[mode] and mode or nil

    if activeGearboxType == nil then
        shutdown()
    elseif cache.vehicle and cache.vehicle ~= 0 and isAllowedState() then
        vehicle = cache.vehicle
        inVeh   = true
        cacheHandlingFor(vehicle)
        enableManual()
    end
end

RegisterCommand('gearbox', function()
    lib.registerContext({
        id = 'sk_gearbox_mode',
        title = 'Manual Gearbox',
        options = {
            {
                title = 'Off',
                description = 'Automatic transmission (game default)',
                icon = 'ban',
                onSelect = function()
                    applyMode('off')
                    TriggerServerEvent('sk_streetkings:gearbox:setMode', 'off')
                    lib.notify({ title = 'Gearbox', description = 'Automatic.', type = 'inform' })
                end,
            },
            {
                title = 'Beginner',
                description = 'Manual shifting, no clutch required, engine never stalls',
                icon = 'gears',
                onSelect = function()
                    applyMode('beginner')
                    TriggerServerEvent('sk_streetkings:gearbox:setMode', 'beginner')
                    lib.notify({ title = 'Gearbox', description = 'Beginner manual enabled.', type = 'success' })
                end,
            },
            {
                title = 'Expert',
                description = 'Clutch required, faster shifts, stalls if you bog it down',
                icon = 'gears',
                onSelect = function()
                    applyMode('expert')
                    TriggerServerEvent('sk_streetkings:gearbox:setMode', 'expert')
                    lib.notify({ title = 'Gearbox', description = 'Expert manual enabled.', type = 'success' })
                end,
            },
        },
    })
    lib.showContext('sk_gearbox_mode')
end, false)

--- Server pushes the saved mode once the character profile has loaded.
RegisterNetEvent('sk_streetkings:gearbox:applyMode', function(mode)
    applyMode(mode)
end)

AddEventHandler('sk_streetkings:gearbox:forceRestartAfterTransition', function(targetVehicle)
    forceRestartAfterTransition(targetVehicle)
end)

-- ── Public surface ──────────────────────────────────────────────────────────

---@return string|nil
function SKGearbox.getType()
    return activeGearboxType
end

--- True while the engine is stalled, so other modules don't steal the E key.
---@return boolean
function SKGearbox.isStallInteractionBlocked()
    return stalled or GetGameTimer() < stallInteractionBlockedUntil
end

exports('GetGearboxType', SKGearbox.getType)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then shutdown() end
end)
