--[[ ===========================================================================
     vi_killcam — KILL CAMERA
     ---------------------------------------------------------------------------
     Single player's kill camera (GTA6Hud, FBICat's 2.1). Every third kill you
     make with a single shot of a gun cuts to a slow-motion shot: first the
     victim, seen from between you and them, then you, from low down in front,
     the camera swinging slowly round each. It lasts 2.8 seconds, runs at a
     quarter speed, washes the colour out and has no HUD. It never takes
     control away: you keep aiming, moving and turning all through it, which
     is what FBICat's 2.1 means by "never freezes you" (its CloseKillCamera
     still unfreezes you, but nothing freezes you any more).

     What counts, as single player counts it:
       - a one-shot kill: you killed them (their source of death), with a
         pistol, SMG, rifle, machine gun, shotgun or sniper, they were seen
         alive first, and they lost no health or armour before the frame they
         died (someone already hurt when they came within 65 m never counts);
       - every third one: the count climbs to 3 and stays there until a shot
         plays, so a shot the cooldown turned away comes with the next one;
       - no shot within 7 seconds of the last one starting, or while another
         script's camera (vi_crashcam's, a shop's) is on screen.

     The shot, in real time whatever the time scale:
       0.000 s  a hard cut to the victim: 2.3 m from their chest towards you,
                1.1 m to one side, 0.15 m up, FOV 40, swinging round them at
                14 degrees a second, looking at their chest as they fall
       1.456 s  a cut to you: 1.4 m in front of your chest towards the victim,
                1.6 m to one side, 0.55 m down, FOV 46, swinging round you
       2.800 s  a hard cut back to your own camera, at full speed
     Each cut picks its side and swing at random. It ends early if you die or
     pause, open the weapon wheel or inventory, a cutscene, switch or fade
     starts, the victim is deleted, or KILL CAMERA is switched off.

     Public API:
         exports.vi_extras:IsKillCamPlaying()
     ========================================================================= ]]

local options = require 'vi_hudoptions.options'
local config = require 'vi_killcam.config'

local playing = false
exports('IsKillCamPlaying', function() return playing end)

if not config.enabled then return end

-- ---- Single player's numbers (GTA6Hud UpdateKillCamera, BeginCinematic, PlaceKillCamera)
local SHOT_MS     = 2800      -- KillCineSeconds
local CUT_MS      = 1456      -- the cut from the victim to you
local PAN_DEG     = 14.0      -- degrees a second each cut swings round its subject
local SLOW        = 0.25      -- time scale for the length of the shot
local COOLDOWN_MS = 7000      -- from one shot's start to the next one's earliest
local OPEN_FOV    = 48.0      -- the camera as created, before the first cut places it
local FILTER      = 'rply_saturation_neg'   -- the washed-out colour, at strength 1
local SPINE3      = 24817     -- SKEL_Spine3: the chest each cut frames
local PICKUP_M    = 65.0      -- people this near are watched
local DROP_M      = 80.0      -- and forgotten this far away
local EVERY       = 3         -- one-shot kills per shot

-- ---- FiveM's: how often new people are looked for, and how long after the
-- gun goes away the watching carries on (a kill only counts with a gun, so
-- with none out nothing is watched at all)
local SCAN_MS     = 250
local IDLE_MS     = 500
local ARMED_MS    = 1000

local function u32(h) return (h or 0) & 0xFFFFFFFF end
local GUN_GROUPS = {}
for _, name in ipairs({ 'GROUP_PISTOL', 'GROUP_SMG', 'GROUP_RIFLE', 'GROUP_MG', 'GROUP_SHOTGUN', 'GROUP_SNIPER' }) do
    GUN_GROUPS[u32(GetHashKey(name))] = true
end

-- ---------------------------------------------------------------------------
-- Who is watched, and what single player keeps on each
-- ---------------------------------------------------------------------------
local watched = {}      -- [ped] = true
local lastHealth = {}   -- [ped] = health + armour last frame, once seen alive
local wounded = {}      -- [ped] = true: hurt before the hit that killed them
local counted = {}      -- [ped] = true: a death already seen, never counted twice
local oneShots = 0      -- KillCadence

local function unwatch(p)
    watched[p], lastHealth[p], wounded[p] = nil, nil, nil
end

local function forget()
    if next(watched) == nil then return end
    watched, lastHealth, wounded = {}, {}, {}
end

-- KillCadence.Record: one-shot kills count up to EVERY and stay there until
-- a shot plays (and the count goes back to 0).
local function record(oneShot)
    if not oneShot then return false end
    if oneShots < EVERY then oneShots = oneShots + 1 end
    return oneShots >= EVERY
end

-- ---------------------------------------------------------------------------
-- The shot
-- ---------------------------------------------------------------------------
local cam, victim = nil, nil
local started, lastStart = nil, nil     -- { network time, game timer }
local cut = 0
local centre, offset = nil, nil         -- what the camera swings round, and from where
local panSign = 1.0
local filtered, filterIndex = false, -1
local hudHidden, waitingToShow = false, false

-- Two clocks, because slow motion stretches the game timer. Whichever has
-- moved further is the real one.
local function clocks() return GetNetworkTimeAccurate(), GetGameTimer() end
local function since(t)
    local net, game = clocks()
    return math.max(net - t[1], game - t[2])
end

local function hudRunning() return GetResourceState('vice_hud') == 'started' end

local function hideHud()
    if hudRunning() and pcall(function() exports.vice_hud:SetHudVisible(false) end) then
        hudHidden = true
    end
end

-- Death draws its own screen and vice_hud hides its HUD for it; a HUD put
-- back over that would stay up. It comes back once you're up again instead.
local function down()
    return IsEntityDead(PlayerPedId()) or LocalPlayer.state['qbx_medical:deathState'] == 3
end
local function showHud(final)
    if not hudHidden or waitingToShow then return end
    if down() then
        -- the resource is stopping: vice_hud's own death handling brings it back
        if final then return end
        waitingToShow = true
        CreateThread(function()
            while down() do Wait(IDLE_MS) end
            waitingToShow = false
            if not playing then showHud() end
        end)
        return
    end
    hudHidden = false
    if hudRunning() then pcall(function() exports.vice_hud:SetHudVisible(true) end) end
end

local function crashCamPlaying()
    if GetResourceState('vi_crashcam') ~= 'started' then return false end
    local ok, on = pcall(function() return exports.vi_crashcam:IsCrashCamPlaying() end)
    return ok and on == true
end

-- CameraClear: the spot wanted, or short of it if the map is in the way.
local function clear(from, want, ignore)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, want.x, want.y, want.z, 1, ignore, 7)
    local _, hit, at, normal = GetShapeTestResult(ray)
    if hit == true or hit == 1 then return at + normal * 0.3 end
    return want
end

-- PlaceKillCamera: cut 0 frames the victim from your side of them, cut 1
-- frames you from theirs. The swing centre stays where the chest was at the
-- cut; only the aim follows it.
local function place(ped, which)
    local d = GetEntityCoords(victim) - GetEntityCoords(ped)
    local dir = vector3(d.x, d.y, 0.0)
    local len = #dir
    if len > 0.1 then dir = dir * (1.0 / len) else dir = GetEntityForwardVector(ped) end
    local side = vector3(-dir.y, dir.x, 0.0)
    panSign = math.random(0, 1) == 0 and 1.0 or -1.0

    local want, fov, subject
    if which == 0 then
        centre = GetPedBoneCoords(victim, SPINE3, 0.0, 0.0, 0.0)
        want = centre - dir * 2.3 + side * (1.1 * panSign) + vector3(0.0, 0.0, 0.15)
        fov, subject = 40.0, victim
    else
        centre = GetPedBoneCoords(ped, SPINE3, 0.0, 0.0, 0.0)
        want = centre + dir * 1.4 + side * (1.6 * panSign) + vector3(0.0, 0.0, -0.55)
        fov, subject = 46.0, ped
    end
    offset = clear(centre, want, subject) - centre
    SetCamFov(cam, fov)
    SetCamCoord(cam, centre.x + offset.x, centre.y + offset.y, centre.z + offset.z)
end

-- One frame of the shot: the swing, and the aim at whoever this cut is on.
local function frame(ped, t)
    HideHudAndRadarThisFrame()
    local which = t < CUT_MS and 0 or 1
    if which ~= cut then
        cut = which
        place(ped, which)
    end
    local a = math.rad(panSign * ((which == 0 and t or t - CUT_MS) / 1000.0) * PAN_DEG)
    local ca, sa = math.cos(a), math.sin(a)
    SetCamCoord(cam, centre.x + offset.x * ca - offset.y * sa, centre.y + offset.x * sa + offset.y * ca, centre.z + offset.z)
    local chest = GetPedBoneCoords(which == 0 and victim or ped, SPINE3, 0.0, 0.0, 0.0)
    PointCamAtCoord(cam, chest.x, chest.y, chest.z + (which == 0 and 0.1 or 0.25))
end

-- Single player's chase music stops where it is while the shot plays (its
-- music update is skipped then); vi_chasemusic holds the same way.
local function holdMusic(on)
    pcall(function() exports.vi_extras:HoldChaseMusic('killcam', on) end)
end

-- CloseKillCamera: your own camera, full speed, the colour and the HUD back.
local function stop(final)
    if not playing then return end
    playing = false
    holdMusic(false)
    if cam then
        -- only if it is still ours on screen: another script may have cut in
        if GetRenderingCam() == cam then RenderScriptCams(false, false, 0, true, false) end
        if DoesCamExist(cam) then DestroyCam(cam, false) end
        cam = nil
    end
    SetTimeScale(1.0)
    if filtered then
        if GetTimecycleModifierIndex() == filterIndex then ClearTimecycleModifier() end
        filtered = false
    end
    victim = nil
    showHud(final)
end

-- BeginCinematic
local function begin(ped, target)
    if playing then return false end
    local rendering = GetRenderingCam()
    if rendering ~= -1 and DoesCamExist(rendering) then return false end
    if lastStart and since(lastStart) < COOLDOWN_MS then return false end
    if crashCamPlaying() then return false end

    local at, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local made = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', at.x, at.y, at.z, rot.x, rot.y, rot.z, OPEN_FOV, false, 2)
    if not made or not DoesCamExist(made) then return false end

    cam, victim, playing = made, target, true
    holdMusic(true)
    started = { clocks() }
    lastStart = started
    SetTimeScale(SLOW)
    -- the washed-out look only when nothing else has a modifier on
    filtered = GetTimecycleModifierIndex() < 0
    if filtered then
        SetTimecycleModifier(FILTER)
        SetTimecycleModifierStrength(1.0)
        filterIndex = GetTimecycleModifierIndex()
    end
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, false)
    cut = 0
    place(ped, 0)
    frame(ped, 0)
    hideHud()
    return true
end

-- ---------------------------------------------------------------------------
-- Watching for kills
-- ---------------------------------------------------------------------------
-- New people within PICKUP_M are watched from now on; anyone already hurt
-- when first seen can't be a one-shot kill.
local function scan(ped)
    local here = GetEntityCoords(ped)
    for p in pairs(watched) do
        if not DoesEntityExist(p) or #(GetEntityCoords(p) - here) > DROP_M then unwatch(p) end
    end
    for p in pairs(counted) do
        -- a body's handle comes back for someone new once the body is gone
        if not DoesEntityExist(p) then counted[p] = nil end
    end
    for _, p in ipairs(GetGamePool('CPed')) do
        if p ~= ped and not watched[p] and not counted[p]
            and (config.players or not IsPedAPlayer(p))
            and #(GetEntityCoords(p) - here) <= PICKUP_M then
            watched[p] = true
            if not IsEntityDead(p) then
                local health = GetEntityHealth(p)
                lastHealth[p] = health + GetPedArmour(p)
                if health < GetEntityMaxHealth(p) - 0.5 then wounded[p] = true end
            end
        end
    end
end

-- Every frame, as single player does it: a drop in health or armour marks
-- someone hurt; a death is counted once, and is a one-shot kill if it was
-- yours, with a gun, and they were never hurt before it.
local function track(ped)
    local here
    for p in pairs(watched) do
        if not DoesEntityExist(p) then
            unwatch(p)
        elseif not IsEntityDead(p) then
            if not wounded[p] then
                local health = GetEntityHealth(p) + GetPedArmour(p)
                local last = lastHealth[p]
                -- someone else's ped can lose its health here a frame before
                -- it is dead here; the hit that kills is not a wound
                if last and health < last - 0.5 and not IsPedFatallyInjured(p) then wounded[p] = true end
                lastHealth[p] = health
            end
        else
            here = here or GetEntityCoords(ped)
            local oneShot = lastHealth[p] ~= nil and not wounded[p]
                and #(GetEntityCoords(p) - here) <= DROP_M
                and GetPedSourceOfDeath(p) == ped
                and GUN_GROUPS[u32(GetWeapontypeGroup(GetPedCauseOfDeath(p)))] == true
            unwatch(p)
            counted[p] = true
            if record(oneShot) and begin(ped, p) then oneShots = 0 end
        end
    end
end

-- What ends a shot and clears the watching (single player's list, as far as
-- FiveM has the same things): a pause menu, your death, the weapon wheel, the
-- inventory, which is where shops and boots are here.
local function interrupted(ped)
    return IsPauseMenuActive() or LocalPlayer.state.pauseMenuOpen == true
        or IsEntityDead(ped)
        or IsHudComponentActive(19)
        or LocalPlayer.state.invOpen == true
end

-- What ends a shot and leaves the watching as it is: the moments single
-- player's HUD hides for (a cutscene, a character switch, a fade).
local function hidden()
    return IsCutsceneActive() or IsCutscenePlaying() or IsPlayerSwitchInProgress() or IsScreenFadedOut()
end

options.add({
    id = 'killcam',
    label = 'KILL CAMERA',
    default = config.default ~= false,
    desc = 'A slow-motion camera on some kills.',
    onChange = function(on)
        if not on then
            stop()
            forget()
        end
    end,
})

CreateThread(function()
    local nextScan, armedUntil, idle = 0, 0, true
    while true do
        local wait = IDLE_MS
        local ped = cache.ped
        if playing then
            -- during the shot everything is checked every frame, as single player does
            wait = 0
            local t = since(started)
            if not ped or interrupted(ped) then
                stop()
                forget()
            elseif hidden() or not options.get('killcam') or t >= SHOT_MS
                or not DoesEntityExist(victim) or not DoesCamExist(cam) then
                stop()
            else
                frame(ped, t)
            end
        elseif ped and options.get('killcam') then
            -- between shots the checks run with the scan, so a frame of
            -- watching costs only the health reads
            local now = GetGameTimer()
            if now >= nextScan then
                nextScan = now + SCAN_MS
                if interrupted(ped) then
                    forget()
                    idle = true
                elseif hidden() then
                    idle = true     -- single player leaves its watching as it is
                else
                    idle = false
                    if IsPedArmed(ped, 4) then armedUntil = now + ARMED_MS end
                    if now < armedUntil then scan(ped) else forget() end
                end
            end
            if not idle and next(watched) then
                track(ped)
                wait = 0
            elseif not idle and now < armedUntil then
                wait = SCAN_MS      -- a gun out and nobody near yet
            end
        end
        Wait(wait)
    end
end)

-- Stopped mid-shot: put the game back.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then stop(true) end
end)
