--[[ ===========================================================================
     vi_camweight — client
     ---------------------------------------------------------------------------
     CAMERA WEIGHT, ported from the fork's ViExtras (single player's
     WeightedCam). The driving camera has weight, as in GTA VI: land a jump,
     take a hard bump or crash, and the camera dips with the vehicle, as hard as
     the hit, then eases back to the view you had in half a second to a second.

     The dip is shown through a scripted camera that, while the dip lasts,
     copies the game's own third-person vehicle camera every frame (where it is,
     where it looks, its field of view), nodded down by the dip. The game's
     camera is never touched: it goes on following the vehicle and the mouse or
     stick underneath, so the view handed back is exactly the one the player
     would have had. Its pitch can't be nudged in place instead: in a vehicle
     SetGameplayCamRelativePitch lands 2 to 3.5 degrees off what
     GetGameplayCamRelativePitch reads, so doing it every frame walks the camera
     into the ground.

     Each hit dips like a critically damped spring kicked by it:
     peak * (t / T) * e^(1 - t / T), at the bottom at T, nearly back by 6T.
     Hits that come close together add up.

     Left alone: first person, aiming, looking behind, the cinematic camera,
     any other scripted camera (vi_crashcam, shops, another resource's),
     binoculars, a menu, player control off, boats, aircraft and trains. Any of
     those mid-dip, leaving the vehicle, dying or switching the row off hands
     the view straight back.

     Public API: none. The CAMERA WEIGHT row of HUD OPTIONS switches it per
     player.
     ========================================================================= ]]

local options = require 'vi_hudoptions.options'
local config = require 'vi_camweight.config'
if not config.enabled then return end

local KMH = 3.6
-- How far back a hit is looked for: the game settles a hit in a frame or
-- three, while braking and cornering never change speed this fast.
local WINDOW_MS = 200.0
-- A hit is over once nothing has registered for this long.
local QUIET_MS = 250.0
-- After a loading screen or character switch, wait this long (single player's
-- GameReady).
local SETTLE_MS = 3000

local strength = tonumber(config.strength) or 1.0
local LAND = { min = config.landMin or 9.0, full = config.landFull or 45.0, dip = config.landDip or 4.5, ms = config.landMs or 110.0 }
local CRASH = { min = config.crashMin or 20.0, full = config.crashFull or 80.0, dip = config.crashDip or 3.5, ms = config.crashMs or 75.0 }
-- several hard hits at once still only dip so far
local MAX_DIP = math.max(LAND.dip, CRASH.dip) * strength * 1.5

local on = false
local samples = {}              -- { at, vel }: the last WINDOW_MS of velocity
local dips = {}                 -- { start, peak, tau }
local landMeter = { kind = 'land', taken = 0.0, loudest = 0.0, firstLoud = 0.0, lastLoud = -math.huge }
local crashMeter = { kind = 'crash', taken = 0.0, loudest = 0.0, firstLoud = 0.0, lastLoud = -math.huge }
local clock = 0.0               -- game ms: slow motion slows the dip too
local curVeh = 0
local lastPos = nil
local airMs, lastAirMs, landedAt = 0.0, 0.0, -math.huge
local lastWhy = ''              -- why the camera was left alone last frame, for debug
-- The game camera's rotation last frame. Scripts run before the game moves its
-- camera, so what is read is a frame old; the turn carries it on by one.
local lastRot = nil
local cam = -1                  -- the camera a dip shows through, while it does
local okSince = -1
local othersAt, crashCamUp, binocularsUp = 0, false, false

local function log(text)
    if config.debug then print('[vi_extras] camweight: ' .. text) end
end

local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end

local function wrap(deg)
    while deg > 180.0 do deg = deg - 360.0 end
    while deg < -180.0 do deg = deg + 360.0 end
    return deg
end

-- The game's camera back on screen, if the dip's is still the one there
-- (another resource's camera that took over is left alone).
local function endCam()
    if cam == -1 then return end
    if GetRenderingCam() == cam then RenderScriptCams(false, false, 0, true, false, 0) end
    if DoesCamExist(cam) then DestroyCam(cam, false) end
    cam = -1
end

-- Ends any dip, handing the view straight back.
local function drop()
    if cam ~= -1 then log('dip ended early') end
    endCam()
    if #dips > 0 then dips = {} end
    landMeter.taken, crashMeter.taken = 0.0, 0.0
    landMeter.loudest, crashMeter.loudest = 0.0, 0.0
end

-- A new vehicle, or none: what the last one was doing says nothing now.
local function forget()
    curVeh = 0
    if #samples > 0 then samples = {} end
    airMs, lastAirMs = 0.0, 0.0
    lastRot = nil
end

-- Not while a loading screen is up, there is no ped, or a character switch is
-- under way, nor for three seconds after.
local function ready()
    local ok = not GetIsLoadingScreenActive() and DoesEntityExist(cache.ped or PlayerPedId())
        and not IsPlayerSwitchInProgress()
    local now = GetGameTimer()
    if not ok then okSince = -1 elseif okSince < 0 then okSince = now end
    return ok and now - okSince >= SETTLE_MS
end

local function dead(ped)
    if IsEntityDead(ped) then return true end
    -- Qbox (qbx_medical) and wasabi_ambulance keep a downed player's ped alive
    local state = LocalPlayer.state
    return state.isDead == true or state.dead == true
end

-- Cars, bikes, quads and bicycles: not boats (every wave a landing),
-- helicopters, planes or trains.
local function weighted(veh)
    local class = GetVehicleClass(veh)
    return class ~= 14 and class ~= 15 and class ~= 16 and class ~= 21
end

local function paused()
    -- the VI pause menu (vi_pausemenu) is a page with the focus
    return IsPauseMenuActive() or IsNuiFocused()
end

local function crashCamPlaying()
    if not crashCamUp then return false end
    local ok, playing = pcall(function() return exports.vi_crashcam:IsCrashCamPlaying() end)
    return ok and playing == true
end

local function binocularsActive()
    if not binocularsUp then return false end
    local ok, active = pcall(function() return exports.vi_binoculars:IsActive() end)
    return ok and active == true
end

-- Nil when the game's own third-person vehicle camera is the one on screen (or
-- under the dip's camera) and nobody else wants it, the player least of all;
-- otherwise who has it.
local function notOurs()
    if crashCamPlaying() then return 'the crash camera' end
    if binocularsActive() then return 'the binoculars' end
    if IsCutscenePlaying() or IsPlayerSwitchInProgress() or IsScreenFadedOut() then
        return 'a cutscene, character switch or black screen'
    end
    local player = PlayerId()
    if not IsPlayerControlOn(player) then return 'player control off' end
    local rendering = GetRenderingCam()
    if rendering ~= -1 and rendering ~= cam then return 'a scripted camera' end
    if IsAimCamActive() or IsFirstPersonAimCamActive() or IsPlayerFreeAiming(player) then return 'aiming' end
    if IsGameplayCamLookingBehind() then return 'looking behind' end
    -- first person, in whichever context this vehicle uses (car, bike...)
    if GetCamViewModeForContext(GetCamActiveViewModeContext()) == 4 then return 'first person' end
    -- while the dip's own camera is on screen these read it, not the game's
    if cam ~= -1 then return nil end
    if not IsGameplayCamRendering() then return 'not the gameplay camera' end
    if IsCinematicCamRendering() then return 'the cinematic camera' end
    if not IsFollowVehicleCamActive() then return 'not the vehicle camera' end
    return nil
end

local function finish(m, dip)
    if config.debug and m.taken > 0.0 then
        local what
        if m == landMeter and lastAirMs >= 250.0 and math.abs(m.firstLoud - landedAt) < 1000.0 then
            what = ('landing after %.1f s in the air, falling at %.0f km/h'):format(lastAirMs / 1000.0, m.loudest)
        elseif m == landMeter then
            what = ('bump, falling at %.0f km/h'):format(m.loudest)
        else
            what = ('crash, %.0f km/h of speed lost'):format(m.loudest)
        end
        log(('%s: dipped %.1f deg'):format(what, m.taken * dip * strength))
    end
    m.taken = 0.0
    m.loudest = 0.0
end

-- A reading of `value` km/h. Over `min` it dips the camera, all of `dip`
-- degrees by `full`. A hit takes a few frames to read in full, so only the
-- part of it not dipped for yet is added each frame; the parts, a frame or
-- two apart, move as one.
local function register(m, value, s)
    if value < s.min then
        if m.loudest > 0.0 and clock - m.lastLoud > QUIET_MS then finish(m, s.dip) end
        return
    end
    if m.taken == 0.0 and m.loudest == 0.0 then m.firstLoud = clock end
    m.lastLoud = clock
    m.loudest = math.max(m.loudest, value)
    local share = clamp((value - s.min) / math.max(s.full - s.min, 0.01), 0.0, 1.0)
    if share < m.taken + 0.02 then return end
    dips[#dips + 1] = { start = clock, peak = (share - m.taken) * s.dip * strength, tau = math.max(s.ms, 10.0) }
    m.taken = share
end

-- The view for this frame: the game camera carried on by a frame (turned by
-- `rot`, moved by `step`, the vehicle's way), nodded down by the dips.
local function show(rot, step, inAir, vz)
    local dip = 0.0
    for i = #dips, 1, -1 do
        local d = dips[i]
        local x = (clock - d.start) / d.tau
        if x >= 8.0 then
            table.remove(dips, i)
        else
            dip = dip + d.peak * x * math.exp(1.0 - x)
        end
    end
    if #dips == 0 then
        endCam()
        return
    end
    dip = math.min(dip, MAX_DIP)

    local at = GetGameplayCamCoord() + step
    local fov = GetGameplayCamFov()
    -- another script destroyed it under us: that script wanted the screen
    if cam ~= -1 and not DoesCamExist(cam) then
        cam = -1
        dips = {}
        return
    end
    if cam == -1 then
        cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
        if not cam or cam == -1 or not DoesCamExist(cam) then
            cam = -1
            dips = {}
            return
        end
        SetCamCoord(cam, at.x, at.y, at.z)
        SetCamRot(cam, rot.x - dip, rot.y, rot.z, 2)
        SetCamFov(cam, fov)
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, false, 0)
    end
    SetCamCoord(cam, at.x, at.y, at.z)
    SetCamRot(cam, rot.x - dip, rot.y, rot.z, 2)
    SetCamFov(cam, fov)
    if config.debug then
        log(('t %.0f dip %.2f game pitch %.2f heading %.1f fov %.1f%s%s vz %.1f'):format(
            clock, dip, rot.x, rot.z, fov, IsGameplayCamShaking() and ' shaking' or '',
            inAir and ' in the air' or '', vz))
    end
end

local function frame(veh)
    -- a pause menu: the view back as it was
    if paused() then
        drop()
        return
    end
    local dt = GetFrameTime() * 1000.0
    if dt <= 0.0 then return end
    clock = clock + dt

    if veh ~= curVeh then
        forget()
        curVeh = veh
    end

    local pos, vel = GetEntityCoords(veh), GetEntityVelocity(veh)
    -- Further than it could have gone in a frame: a teleport, or a script
    -- putting it somewhere. Its old speeds would read as the hit of a lifetime.
    if #samples > 0 and lastPos and #(pos - lastPos) > 3.0 + #vel * dt / 1000.0 * 2.0 then samples = {} end
    lastPos = pos

    local inAir = IsEntityInAir(veh)
    if inAir then
        airMs = airMs + dt
    elseif airMs > 0.0 then
        -- a bounce straight after a big drop keeps the drop's air time
        if clock - landedAt > 1000.0 or airMs > lastAirMs then lastAirMs = airMs end
        airMs = 0.0
        landedAt = clock
    end

    samples[#samples + 1] = { at = clock, vel = vel }
    while #samples > 0 and clock - samples[1].at > WINDOW_MS do table.remove(samples, 1) end

    -- Falling stopped: how much of the speed it was coming down at is gone (a
    -- ramp throwing it up stops no fall, and doesn't count). Crashing: how much
    -- its speed along the ground has changed, any way round.
    local lowest, jolt = 0.0, 0.0
    for i = 1, #samples do
        local v = samples[i].vel
        if v.z < lowest then lowest = v.z end
        local dx, dy = vel.x - v.x, vel.y - v.y
        jolt = math.max(jolt, dx * dx + dy * dy)
    end
    local fall = (math.min(vel.z, 0.0) - lowest) * KMH
    jolt = math.sqrt(jolt) * KMH

    -- the game camera, a frame old, and how far it turned in its last frame
    local rot = GetGameplayCamRot(2)
    local turn = vector3(0.0, 0.0, 0.0)
    if lastRot then
        turn = vector3(clamp(rot.x - lastRot.x, -5.0, 5.0), 0.0, clamp(wrap(rot.z - lastRot.z), -5.0, 5.0))
    end
    lastRot = rot

    local why = notOurs()
    if config.debug and why ~= lastWhy then log(why and ('camera left alone: ' .. why) or 'camera ours') end
    lastWhy = why
    if why then
        drop()
        return
    end
    register(landMeter, fall, LAND)
    register(crashMeter, jolt, CRASH)
    show(rot + turn, vel * (dt / 1000.0), inAir, vel.z)
end

options.add({
    id = 'camweight',
    label = 'CAMERA WEIGHT',
    default = config.default ~= false,
    desc = 'The driving camera dips with your car on jumps, bumps and crashes.',
    onChange = function(value)
        on = value and true or false
        if not on then
            -- switched off: the view back as it was, at once
            drop()
            forget()
        end
    end,
})

CreateThread(function()
    while true do
        local wait = 500
        if on and strength > 0.0 then
            local now = GetGameTimer()
            if now >= othersAt then
                othersAt = now + 1000
                crashCamUp = GetResourceState('vi_crashcam') == 'started'
                binocularsUp = GetResourceState('vi_binoculars') == 'started'
            end
            if not ready() then
                drop()
                forget()
            else
                local ped = cache.ped or PlayerPedId()
                local veh = GetVehiclePedIsIn(ped, false)
                if veh == 0 or dead(ped) or not weighted(veh) then
                    -- out of the vehicle, dead, or a boat: never a dip left on screen
                    drop()
                    forget()
                    wait = 200
                else
                    local ok, err = pcall(frame, veh)
                    if not ok then
                        print('^1[vi_extras]^7 camweight: ' .. tostring(err))
                        drop()
                        forget()
                    end
                    wait = 0
                end
            end
        end
        Wait(wait)
    end
end)

-- Never leave the view on a camera nobody is moving any more.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then drop() end
end)
