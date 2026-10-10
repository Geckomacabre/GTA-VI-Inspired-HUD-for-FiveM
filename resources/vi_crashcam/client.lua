--[[ ===========================================================================
     vi_crashcam — client
     ---------------------------------------------------------------------------
     Crash hard enough and the game cuts away: a couple of black frames, then a
     low camera at the roadside watching the car go by in slow motion with the
     HUD off, then a short fade back into the seat.

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

-- =============================================================================
-- Real time
-- =============================================================================
-- The shot has to last DurationMs on the wall, and the game is running at a
-- fifth of its speed while it does. Network time is not slowed by the time
-- scale; the game timer may be, so it is only the floor under it -- whichever
-- clock says more time has passed is believed, which is right if either one
-- is honest.
local function clocks()
    return GetNetworkTimeAccurate(), GetGameTimer()
end

local function elapsedSince(net0, game0)
    local net, game = clocks()
    return math.max(net - net0, game - game0)
end

-- =============================================================================
-- HUD
-- =============================================================================
local function setHud(visible)
    if GetResourceState('vice_hud') ~= 'started' then return end
    -- vice_hud hides itself on death and shows itself again on revive, once
    -- per transition. Handing the HUD back to a player who died in the crash
    -- would undo the first half of that and nothing would redo it.
    if visible and IsEntityDead(PlayerPedId()) then return end
    pcall(function() exports.vice_hud:SetHudVisible(visible) end)
end

-- =============================================================================
-- Where the camera goes
-- =============================================================================
local function flat(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y)
    if len < 0.001 then return nil end
    return vector3(v.x / len, v.y / len, 0.0)
end

local function clearView(from, veh)
    local to = GetEntityCoords(veh) + vector3(0.0, 0.0, 0.5)
    -- 1 = world, 16 = objects. Other vehicles are allowed to pass through the
    -- shot; a wall between the camera and the car is not.
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        from.x, from.y, from.z, to.x, to.y, to.z, 1 | 16, veh, 4)
    local _, hit = GetShapeTestResult(ray)
    -- `hit` has been a 0/1 number on some builds and a boolean on others.
    return hit == 0 or hit == false
end

--- `dir` is the direction of travel just before the hit. The camera goes
--- further along it and off to one side, so the car comes TOWARDS the shot
--- and across it rather than away -- on the ground at the roadside, where a
--- person filming would be standing.
local function findSpot(veh, dir)
    local cam = Config.Camera
    local pos = GetEntityCoords(veh)
    dir = dir or flat(GetEntityForwardVector(veh)) or vector3(0.0, 1.0, 0.0)
    local side = vector3(-dir.y, dir.x, 0.0)

    -- Full distance on either side first, then pulled in: a tunnel or a
    -- narrow street has no room ten metres out, and a closer shot beats a
    -- camera inside a wall.
    for _, scale in ipairs({ 1.0, 0.6, 0.35 }) do
        for _, sign in ipairs({ 1.0, -1.0 }) do
            local at = pos + dir * (cam.ahead * scale) + side * (cam.side * scale * sign)
            local found, groundZ = GetGroundZFor_3dCoord(at.x, at.y, pos.z + 2.0, false)
            -- Ground a long way below the car is the road under a bridge, or
            -- the sea: not somewhere to stand.
            if found and math.abs(groundZ - pos.z) < 3.5 then
                local spot = vector3(at.x, at.y, groundZ + cam.height)
                if clearView(spot, veh) then return spot end
            end
        end
    end

    -- Nowhere on the ground works. Above and behind always has a view.
    return pos - dir * 6.0 + side * 3.0 + vector3(0.0, 0.0, 2.5)
end

-- =============================================================================
-- The shot
-- =============================================================================
local function restore()
    SetTimeScale(1.0)
    if activeCam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(activeCam, false)
        activeCam = nil
    end
end

local function play(veh, dir)
    if playing or not DoesEntityExist(veh) then return end
    -- Something else already owns the screen (a respawn, a loading fade).
    if IsScreenFadedOut() or IsScreenFadingOut() or IsPauseMenuActive() then return end
    playing = true

    local ok, err = pcall(function()
        local spot = findSpot(veh, dir)

        if Config.BlackFlashMs > 0 then
            DoScreenFadeOut(0)
            Wait(Config.BlackFlashMs)
        end

        activeCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
            spot.x, spot.y, spot.z, 0.0, 0.0, 0.0, Config.Camera.fov, false, 2)
        -- Pointed AT the car rather than given a rotation, so it turns to
        -- follow as the car slides past, the way the reference shot does.
        PointCamAtEntity(activeCam, veh, 0.0, 0.0, 0.3, true)
        SetCamActive(activeCam, true)
        RenderScriptCams(true, false, 0, true, false)

        setHud(false)
        SetTimeScale(Config.TimeScale)
        DoScreenFadeIn(0)

        local net0, game0 = clocks()
        local frames = 0
        -- The frame cap is a backstop for both clocks failing at once: the
        -- worst it can do is end the shot late, where without it the shot
        -- would not end at all.
        while elapsedSince(net0, game0) < Config.DurationMs and frames < 3000 do
            HideHudAndRadarThisFrame()
            if not DoesEntityExist(veh) then break end
            frames = frames + 1
            Wait(0)
        end

        -- Back into the seat behind a fade, so the camera change is not seen.
        if Config.FadeInMs > 0 then DoScreenFadeOut(0) end
        restore()
        Wait(0)
        if Config.FadeInMs > 0 then DoScreenFadeIn(Config.FadeInMs) end
    end)

    -- Whatever happened in there, the player gets their game back.
    restore()
    if IsScreenFadedOut() then DoScreenFadeIn(0) end
    setHud(true)
    readyAt = GetGameTimer() + Config.CooldownMs
    playing = false

    if not ok then print('^1[vi_crashcam]^7 ' .. tostring(err)) end
end

-- =============================================================================
-- Noticing a crash
-- =============================================================================
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

            if veh == lastVeh and lastPos
                and lastSpeed >= Config.MinSpeed
                and lastSpeed - speed >= Config.MinSpeedLoss
                -- A teleport (a garage, an admin) is also 100 to 0 in one
                -- sample. A crash does not move you forty metres.
                and #(pos - lastPos) < 40.0
                and GetGameTimer() >= readyAt then
                play(veh, lastDir)
                lastVeh, lastSpeed, lastPos, lastDir = 0, 0.0, nil, nil
            else
                -- The direction is kept from BEFORE the hit: afterwards the
                -- car may be spinning, stopped or going backwards, and none
                -- of those say which way the road runs.
                lastVeh, lastSpeed, lastPos = veh, speed, pos
                lastDir = flat(GetEntityVelocity(veh)) or lastDir
            end
            Wait(Config.SampleMs)
        end
    end
end)

-- =============================================================================
-- API, test command, cleanup
-- =============================================================================
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

-- A restart mid-shot must not leave the game at a fifth of its speed behind a
-- camera nobody owns any more.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not playing then return end
    restore()
    DoScreenFadeIn(0)
    setHud(true)
end)
