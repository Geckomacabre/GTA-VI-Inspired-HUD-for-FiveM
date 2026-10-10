--[[ ===========================================================================
     vi_crashcam — client
     ---------------------------------------------------------------------------
     Crash hard enough and the game cuts away. The hit itself is seen, already
     slowed, from wherever you were looking; then a hard cut to a camera
     standing well back from the car, the edges of the screen closed in and the
     HUD gone; then a hard cut back to exactly the view you had, with time
     running back up to normal.

     Everything here is local to the player it happens to. SetTimeScale slows
     this client's simulation only, so for those few seconds other players see
     this car move slowly too and then catch up -- the price of slow motion on
     a server, and the reason the shot is short and has a cooldown.

     Public API:
         exports.vi_crashcam:PlayCrashCam()            -- on the current vehicle
         exports.vi_crashcam:SetCrashCamEnabled(bool)  -- e.g. off during a race
         exports.vi_crashcam:IsCrashCamPlaying()
     ========================================================================= ]]

local KMH = 3.6                 -- GetEntitySpeed is m/s

local enabled = Config.Enabled ~= false
local playing = false
local readyAt = 0               -- GetGameTimer() before which nothing triggers
local activeCam = nil
local hudOverlay = false        -- vice_hud is drawing the overlay (else the bars are native)
local hudHidden = false

-- Two clocks, because slow motion stretches the game timer. Whichever has
-- moved further is the real one.
local function clocks()
    return GetNetworkTimeAccurate(), GetGameTimer()
end
local function elapsedSince(net0, game0)
    local net, game = clocks()
    return math.max(net - net0, game - game0)
end

local function hudRunning()
    return GetResourceState('vice_hud') == 'started'
end

local function setHud(visible)
    if not hudRunning() then return end
    -- A crash that kills hands the screen to whatever draws death; putting the
    -- HUD back over that is not this resource's call.
    if visible and IsEntityDead(PlayerPedId()) then return end
    pcall(function() exports.vice_hud:SetHudVisible(visible) end)
    hudHidden = not visible
end

-- The edges of the screen closing in. vice_hud draws it when it is there (its
-- Focus effect, in black, with bars); without it the bars alone are drawn per
-- frame from here.
local function setOverlay(on)
    local o = Config.Overlay
    if not o or o.enabled == false then hudOverlay = false return end
    local ok = hudRunning() and pcall(function()
        exports.vice_hud:SetCinematicFx(on, { strength = o.strength, bars = o.bars, pulse = o.pulse })
    end)
    hudOverlay = ok and on or false
end

local function drawBars()
    local o = Config.Overlay
    if hudOverlay or not o or o.enabled == false then return end
    local h = tonumber(o.bars) or 0.0
    if h <= 0.0 then return end
    DrawRect(0.5, h / 2, 1.0, h, 0, 0, 0, 255)
    DrawRect(0.5, 1.0 - h / 2, 1.0, h, 0, 0, 0, 255)
end

local function flat(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y)
    if len < 0.001 then return nil end
    return vector3(v.x / len, v.y / len, 0.0)
end

-- Can the camera, standing at `from`, see the car? Anything solid in between
-- (a wall, a truck, the barrier the car just went through) rules the spot out.
local function clearView(from, veh)
    local to = GetEntityCoords(veh) + vector3(0.0, 0.0, 0.5)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        from.x, from.y, from.z, to.x, to.y, to.z, 1 | 16, veh, 4)
    local _, hit = GetShapeTestResult(ray)
    return hit == 0 or hit == false
end

-- One of Config.Shots, placed. The list is walked from a random start so two
-- crashes in a row are not filmed the same way; each shot is tried on both
-- sides of the line of travel, then closer in.
local function findSpot(veh, dir)
    local shots = Config.Shots
    local pos = GetEntityCoords(veh)
    dir = dir or flat(GetEntityForwardVector(veh)) or vector3(0.0, 1.0, 0.0)
    local side = vector3(-dir.y, dir.x, 0.0)
    local first = math.random(1, #shots)
    local firstSign = math.random(0, 1) == 0 and 1.0 or -1.0

    for step = 0, #shots - 1 do
        local shot = shots[((first - 1 + step) % #shots) + 1]
        for _, scale in ipairs({ 1.0, 0.65, 0.4 }) do
            for _, sign in ipairs({ firstSign, -firstSign }) do
                local at = pos + dir * (shot.ahead * scale) + side * (shot.side * scale * sign)
                local found, groundZ = GetGroundZFor_3dCoord(at.x, at.y, pos.z + 3.0, false)
                if found and math.abs(groundZ - pos.z) < 4.0 then
                    local spot = vector3(at.x, at.y, groundZ + shot.height)
                    if clearView(spot, veh) then return spot, shot.fov end
                end
            end
        end
    end

    -- Nothing had a clear view (a tunnel, a multi-storey): stand just behind
    -- and above the car instead of not filming it at all.
    return pos - dir * 7.0 + side * 3.5 + vector3(0.0, 0.0, 2.8), 45.0
end

local function dropCam()
    if activeCam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(activeCam, false)
        activeCam = nil
    end
end

-- Hold for `ms` of real time, running `each` every frame.
local function hold(ms, each)
    local net0, game0 = clocks()
    local frames = 0
    while elapsedSince(net0, game0) < ms and frames < 3000 do
        if each and each(elapsedSince(net0, game0) / ms) == false then break end
        frames = frames + 1
        Wait(0)
    end
end

local function play(veh, dir)
    if playing or not DoesEntityExist(veh) then return end
    if IsScreenFadedOut() or IsScreenFadingOut() or IsPauseMenuActive() then return end
    playing = true

    local ok, err = pcall(function()
        -- Where the player's own camera is, measured against the car, so the
        -- view can be handed back exactly as it was: behind, to one side,
        -- from the bonnet, whatever they had.
        local view = {
            heading = GetGameplayCamRelativeHeading(),
            pitch = GetGameplayCamRelativePitch(),
            mode = GetFollowVehicleCamViewMode(),
        }

        -- 1. The hit, slowed, from the seat.
        SetTimeScale(Config.TimeScale)
        setOverlay(true)
        hold(Config.ImpactHoldMs, drawBars)

        -- 2. The cut. The spot is chosen now rather than at the moment of the
        -- hit, so it is placed against where the car has ended up heading.
        if not DoesEntityExist(veh) then return end
        local spot, fov = findSpot(veh, dir)
        if Config.BlackFlashMs > 0 then
            DoScreenFadeOut(0)
            Wait(Config.BlackFlashMs)
        end
        activeCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
            spot.x, spot.y, spot.z, 0.0, 0.0, 0.0, fov, false, 2)
        PointCamAtEntity(activeCam, veh, 0.0, 0.0, 0.3, true)
        if (Config.HandShake or 0) > 0 then ShakeCam(activeCam, 'HAND_SHAKE', Config.HandShake + 0.0) end
        SetCamActive(activeCam, true)
        RenderScriptCams(true, false, 0, true, false)
        setHud(false)
        if Config.BlackFlashMs > 0 then DoScreenFadeIn(0) end

        hold(Config.DurationMs, function()
            HideHudAndRadarThisFrame()
            drawBars()
            return DoesEntityExist(veh)
        end)

        -- 3. Back to the view the player had.
        if Config.FadeInMs > 0 then DoScreenFadeOut(0) end
        dropCam()
        setOverlay(false)
        if GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 then
            SetFollowVehicleCamViewMode(view.mode)
        end
        SetGameplayCamRelativeHeading(view.heading)
        SetGameplayCamRelativePitch(view.pitch, 1.0)
        if Config.FadeInMs > 0 then DoScreenFadeIn(Config.FadeInMs) end

        -- Time runs back up rather than snapping, and the camera is put back
        -- once more on the next frame: the first frame after a scripted
        -- camera is the one the game is most likely to override.
        local resetAgain = true
        hold(math.max(Config.EaseOutMs, 1), function(t)
            SetTimeScale(Config.TimeScale + (1.0 - Config.TimeScale) * math.min(t, 1.0))
            HideHudAndRadarThisFrame()
            if resetAgain then
                resetAgain = false
                SetGameplayCamRelativeHeading(view.heading)
                SetGameplayCamRelativePitch(view.pitch, 1.0)
            end
        end)
        SetTimeScale(1.0)

        hold(math.max(Config.HudReturnMs - Config.EaseOutMs, 0), function() HideHudAndRadarThisFrame() end)
    end)

    -- However it ended, the game is left as it was found.
    SetTimeScale(1.0)
    dropCam()
    setOverlay(false)
    if IsScreenFadedOut() then DoScreenFadeIn(0) end
    if hudHidden then setHud(true) end

    readyAt = GetGameTimer() + Config.CooldownMs
    playing = false
    if not ok then print('^1[vi_crashcam]^7 ' .. tostring(err)) end
end

-- Detection: the speed one sample ago against the speed now.
CreateThread(function()
    local lastVeh, lastSpeed, lastPos, lastDir = 0, 0.0, nil, nil

    while true do
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local driving = veh ~= 0
            and (not Config.DriverOnly or GetPedInVehicleSeat(veh, -1) == ped)

        if not enabled or playing or not driving then
            lastVeh, lastSpeed, lastPos, lastDir = 0, 0.0, nil, nil
            Wait(500)
        else
            local speed = GetEntitySpeed(veh) * KMH
            local pos = GetEntityCoords(veh)

            -- The distance test keeps a teleport (a garage, an admin goto)
            -- from reading as the biggest crash of all time.
            if veh == lastVeh and lastPos
                and lastSpeed >= Config.MinSpeed
                and lastSpeed - speed >= Config.MinSpeedLoss
                and #(pos - lastPos) < 40.0
                and GetGameTimer() >= readyAt then
                play(veh, lastDir)
                lastVeh, lastSpeed, lastPos, lastDir = 0, 0.0, nil, nil
            else
                lastVeh, lastSpeed, lastPos = veh, speed, pos
                -- The way it was GOING, kept from before the hit: afterwards
                -- the car may be spinning or stopped and has no useful heading.
                lastDir = flat(GetEntityVelocity(veh)) or lastDir
            end
            Wait(Config.SampleMs)
        end
    end
end)

local function playOnCurrent()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return false end
    CreateThread(function() play(veh, flat(GetEntityVelocity(veh))) end)
    return true
end

exports('PlayCrashCam', playOnCurrent)
exports('IsCrashCamPlaying', function() return playing end)
exports('SetCrashCamEnabled', function(state) enabled = state ~= false end)

if Config.TestCommand then
    RegisterCommand(Config.TestCommand, function()
        if not playOnCurrent() then
            print('^3[vi_crashcam]^7 get in a vehicle first.')
        end
    end, false)
end

-- Stopped mid-shot: put the game back.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not playing then return end
    SetTimeScale(1.0)
    dropCam()
    setOverlay(false)
    DoScreenFadeIn(0)
    if hudHidden then setHud(true) end
end)
