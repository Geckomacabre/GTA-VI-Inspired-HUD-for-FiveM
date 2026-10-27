-- ============================================================================
-- qbx_vehiclekeys / client / smashwindow
-- Upstate Mafia addition.
--
-- Third-eye the driver door of a locked vehicle you have no keys for and you
-- get a "Smash Window" option. Going ahead with it unlocks the doors, so the
-- resource's existing theft path (search for keys with [H], or a lockpick via
-- `lockpicks:UseLockpick`) takes over from there. This file deliberately does
-- not hand out keys or start the engine itself.
--
-- No tool is required. The cost is time, stress, a police alert and honor: how
-- long the smash takes and how likely the alert is are both scaled by the
-- player's qbx_honor tier (see config.client.smashWindow.honor). If qbx_honor
-- isn't running, everyone is treated as neutral and no honor is deducted.
-- ============================================================================

local config = require 'config.client'
local smashConfig = config.smashWindow

local isSmashing = false

---@param vehicle number The entity number of the vehicle.
---@return boolean `true` if this vehicle can currently have its window smashed.
-- Global for the same reason SmashWindow below is -- see the note there.
function GetIsSmashable(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if cache.vehicle then return false end -- already sat in something
    if GetVehicleDoorLockStatus(vehicle) < 2 then return false end -- not locked
    if not IsVehicleSeatFree(vehicle, -1) then return false end -- someone is in the driver's seat
    if not IsVehicleWindowIntact(vehicle, 0) then return false end -- already put through
    if GetIsVehicleAccessible(vehicle) then return false end -- we have keys / job access

    local vehicleConfig = GetVehicleConfig(vehicle)
    if vehicleConfig.noLock or vehicleConfig.shared or vehicleConfig.windowSmashImmune then return false end

    -- No proximity test here: ox_target has already gated on distance and on the
    -- door bone before it calls this.
    return true
end

---Resolves the local player's honor tier into the tuning table for it.
---Falls back to the neutral tier whenever qbx_honor is absent or unreadable,
---so this resource never hard-depends on it.
---@return {durationMultiplier: number, alertChanceMultiplier: number} tierConfig
---@return 'angel'|'devil'|nil tier
local function getHonorTuning()
    -- Honor is the qbx_honor resource, or part of vice_hud.
    if GetResourceState('qbx_honor') ~= 'started' and GetResourceState('vice_hud') ~= 'started' then
        return smashConfig.honor.neutral, nil
    end

    local ok, honor = pcall(function() return exports.qbx_honor:GetHonor() end)
    if not ok or type(honor) ~= 'number' then
        return smashConfig.honor.neutral, nil
    end

    local tierOk, tier = pcall(function() return exports.qbx_honor:GetBadgeTier(honor) end)
    if not tierOk then tier = nil end

    return smashConfig.honor[tier or 'neutral'] or smashConfig.honor.neutral, tier
end

---Loads an anim dict, with a ceiling so a missing asset cannot hang the swing.
---@param dict string
---@return boolean
local function ensureAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do Wait(0) end

    return HasAnimDictLoaded(dict)
end

---The clip's own real length in ms, not a guess. 0 when it is unusable.
---@param anim {dict: string, clip: string}?
---@return number
local function getClipMs(anim)
    if not anim or not ensureAnimDict(anim.dict) then return 0 end
    return math.floor(GetAnimDuration(anim.dict, anim.clip) * 1000)
end

-- eScriptedAnimFlags, from TASK_PLAY_ANIM's docs. Named rather than written as
-- bare numbers because this file used to pass 16 believing it meant "keep
-- player control". It is AF_UPPERBODY: the try-the-door loop was playing on the
-- torso only with the legs left in idle, then snapping to full body for the
-- swing -- a big part of why the whole thing looked choppy.
local AF_LOOPING = 1
local AF_HIDE_WEAPON = 1048576

---@param a number heading in degrees
---@param b number heading in degrees
---@return number difference, wrapped into -180..180
local function headingDelta(a, b)
    return (a - b + 180.0) % 360.0 - 180.0
end

---@class BreakInScene
---@field x number scene origin to hand TaskPlayAnimAdvanced
---@field y number
---@field z number
---@field rx number
---@field ry number
---@field rz number
---@field standX number where the clip will actually start the ped
---@field standY number
---@field heading number which way the ped faces there

---Works out where to play a `veh@break_in@...` clip so the ped starts on the
---driver's door facing the car, the way the engine lines these clips up.
---
---TaskPlayAnimAdvanced's position/rotation is the SCENE ORIGIN, not where the
---ped ends up: the ped starts at the origin plus whatever root offset the clip
---carries. Anchoring it straight on the vehicle put the player in the middle
---of the car, so these clips carry almost no offset of their own -- the engine
---gets the door position from the entry point in vehiclelayouts.meta instead.
---
---So this measures rather than assumes. GET_ENTRY_POINT_POSITION is the
---engine's own "where does a ped stand to use this door", and
---GET_ANIM_INITIAL_OFFSET_POSITION/_ROTATION say where this particular clip
---would start the ped from a given origin; the origin is shifted by the
---difference. Only X/Y are corrected -- Z stays on the vehicle-derived origin,
---which was already standing the ped at the right height.
---
---Solved once per clip per smash, not per loop: re-solving and re-anchoring
---every cycle was one of the sources of the jitter.
---@param vehicle number
---@param anim {dict: string, clip: string}
---@return BreakInScene? nil to play the clip in place
local function solveBreakInScene(vehicle, anim)
    if not smashConfig.alignToVehicle then return end

    local vehPos = GetEntityCoords(vehicle)
    local vehRot = GetEntityRotation(vehicle, 2) -- order 2 == the ZXY order TaskPlayAnimAdvanced wants

    -- doorId 0 is the front driver-side door, matching this file's targetBones
    -- and the window index passed to SmashVehicleWindow.
    --
    -- Called by hash on purpose. Rockstar's current name for this native is
    -- GET_ENTRY_POINT_POSITION, but FiveM's runtime still generates the Lua
    -- global from the old _GET_ENTRY_POSITION_OF_DOOR name, so the obvious
    -- GetEntryPointPosition is nil at runtime -- it crashed exactly that way.
    local entry = Citizen.InvokeNative(0xC0572928C0ABFDA3, vehicle, 0, Citizen.ResultAsVector())

    -- A vehicle with no entry point for that door hands back something useless
    -- (commonly 0,0,0). Playing in place is the lesser evil there: the raw
    -- vehicle origin is exactly what put people inside the car.
    if not entry or #(vector2(entry.x, entry.y) - vector2(vehPos.x, vehPos.y)) >= 5.0 then return end

    -- Face the car side-on: the vehicle's own right vector is the way someone
    -- stood at the driver's door looks at it.
    local right = GetOffsetFromEntityInWorldCoords(vehicle, 1.0, 0.0, 0.0) - vehPos
    local heading = GetHeadingFromVector_2d(right.x, right.y)

    local startRot = GetAnimInitialOffsetRotation(anim.dict, anim.clip,
        vehPos.x, vehPos.y, vehPos.z, vehRot.x, vehRot.y, vehRot.z, 0.0, 2)
    local rotZ = vehRot.z + headingDelta(heading, startRot.z)

    -- Position is solved AFTER the rotation, because where the clip starts the
    -- ped depends on which way the scene is facing.
    local startPos = GetAnimInitialOffsetPosition(anim.dict, anim.clip,
        vehPos.x, vehPos.y, vehPos.z, vehRot.x, vehRot.y, rotZ, 0.0, 2)

    return {
        x = vehPos.x + (entry.x - startPos.x),
        y = vehPos.y + (entry.y - startPos.y),
        z = vehPos.z,
        rx = vehRot.x,
        ry = vehRot.y,
        rz = rotZ,
        standX = entry.x,
        standY = entry.y,
        heading = heading,
    }
end

---@param anim {dict: string, clip: string}
---@param scene BreakInScene?
---@param flags number
---@param blendIn number 8.0 is a hard cut; lower crossfades from whatever was playing
local function playBreakInAnim(anim, scene, flags, blendIn)
    if not scene then
        TaskPlayAnim(cache.ped, anim.dict, anim.clip, blendIn, 2.0, -1, flags, 0, false, false, false)
        return
    end

    TaskPlayAnimAdvanced(cache.ped, anim.dict, anim.clip,
        scene.x, scene.y, scene.z,
        scene.rx, scene.ry, scene.rz,
        blendIn, 2.0, -1, flags,
        0.0, 2, 0)
end

---Walks the ped onto the door before anything plays, the way the engine walks
---a ped to an entry point, instead of letting TaskPlayAnimAdvanced teleport
---them there -- from the edge of the target range that was up to a couple of
---metres of pop on the very first frame.
---@param scene BreakInScene?
local function walkToDoor(scene)
    if not scene then return end

    local ped = cache.ped
    local target = vector2(scene.standX, scene.standY)
    local pos = GetEntityCoords(ped)

    local function isThere()
        pos = GetEntityCoords(ped)
        return #(vector2(pos.x, pos.y) - target) < 0.25
            and math.abs(headingDelta(GetEntityHeading(ped), scene.heading)) < 30.0
    end

    if isThere() then return end

    -- Timeout -1: the docs note other values break the movement, so the
    -- deadline below is what bounds it. The last 0.3m slides rather than steps,
    -- which is what lands the ped on the spot instead of shuffling around it.
    TaskGoStraightToCoord(ped, scene.standX, scene.standY, pos.z, 1.0, -1, scene.heading, 0.3)

    -- Whatever small error is left when this gives up is absorbed by the
    -- anim's own blend-in, which is barely visible at these distances.
    local deadline = GetGameTimer() + 2500
    repeat Wait(0) until isThere() or GetGameTimer() >= deadline
end

---@param vehicle number The entity number of the vehicle.
-- Left global rather than made local: this and GetIsSmashable above were the
-- shared entry point back when client/slimjim.lua drew one combined vice_hud
-- prompt for both options and called into here. Since the osm-target
-- migration (see the ox_target registration below) slimjim.lua registers its
-- own row and nothing outside this file calls either any more -- they stay
-- global so anything that was hooking them keeps working.
--
-- Plays out the way the engine handles a locked car, as one continuous motion:
--
--   1. Walk onto the driver's door.
--   2. Try the handle (vehiclelayouts.meta's AlternateTryLockedDoorClipId,
--      std_locked_ds), looping under a cancellable bar. This is the part honor
--      scales.
--   3. Crossfade straight into one forced-entry swing (AlternateForcedEntryClipId,
--      std_force_entry_ds), with the glass broken at the frame the elbow lands
--      -- read off the clip's own phase, see smashWindow.smashAtPhase.
--   4. Let that clip finish and blend out on its own.
--
-- Every hand-off is a blend rather than a stop-then-start, which is what keeps
-- it from reading as a string of separate canned moves.
function SmashWindow(vehicle)
    if isSmashing then return end
    isSmashing = true

    local ped = cache.ped
    local tuning = getHonorTuning()
    local tryAnim = ResolveVehicleAnim(config.anims.smashTryDoor, vehicle)
    local impactAnim = ResolveVehicleAnim(config.anims.smashImpact, vehicle)

    local tryCycleMs = getClipMs(tryAnim)
    local impactMs = getClipMs(impactAnim)

    -- The honor tier still scales the whole break-in exactly as before; the
    -- swing is carved out of that budget rather than added onto it.
    local totalMs = math.floor(smashConfig.baseDurationMs * (tuning.durationMultiplier or 1.0))
    local tryMs = math.max(totalMs - impactMs, 1000)

    -- Whole tugs only, so when the bar ends the loop is back at the start of a
    -- tug and the swing crossfades in from a matching stance, not mid-reach.
    if tryCycleMs > 0 then
        tryMs = math.max(1, math.floor(tryMs / tryCycleMs + 0.5)) * tryCycleMs
    end

    local tryScene = tryCycleMs > 0 and solveBreakInScene(vehicle, tryAnim) or nil
    local impactScene = impactMs > 0 and solveBreakInScene(vehicle, impactAnim) or nil

    walkToDoor(tryScene or impactScene)

    local tryFlags = AF_LOOPING | AF_HIDE_WEAPON
    local tryRunning = tryCycleMs > 0

    if tryRunning then
        playBreakInAnim(tryAnim, tryScene, tryFlags, 4.0)

        -- One looping task, with a watchdog, instead of re-sending the task
        -- every cycle. Re-sending restarted the blend and re-anchored the ped
        -- each time, and Wait() drift let a few idle frames in between tugs.
        -- An earlier note here said the loop bit was not honoured for this
        -- dict, but that was observed with flag 49 (looping + upperbody +
        -- secondary) -- if it does still drop out, this puts it back within a
        -- quarter second rather than leaving the ped stood idle.
        CreateThread(function()
            while true do
                Wait(250)
                if not tryRunning then return end

                if not IsEntityPlayingAnim(ped, tryAnim.dict, tryAnim.clip, 3) then
                    playBreakInAnim(tryAnim, tryScene, tryFlags, 4.0)
                end
            end
        end)
    end

    local isSuccess = lib.progressCircle({
        duration = tryMs,
        label = locale('progress.trying_door'),
        position = 'bottom',
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
    })

    tryRunning = false

    -- Aborted, or the vehicle drove off / despawned mid-attempt.
    if not isSuccess
        or not DoesEntityExist(vehicle)
        or not GetIsCloseToVehicleDoor(vehicle, smashConfig.maxDistance)
    then
        if tryAnim then StopAnimTask(ped, tryAnim.dict, tryAnim.clip, 2.0) end
        isSmashing = false
        return
    end

    local smashAt = smashConfig.smashAtPhase or 0.35
    local swingStartedAt = GetGameTimer()

    if impactMs > 0 then
        -- No StopAnimTask on the tug first. Stopping it blended the ped back to
        -- idle and the swing then started from idle; handing the new task over
        -- the running one crossfades directly from tug to swing instead. No
        -- AF_LOOPING, and full body, so it is a committed one-shot.
        playBreakInAnim(impactAnim, impactScene, AF_HIDE_WEAPON, 4.0)

        -- A deadline as well as the phase: if the task never starts (ragdolled,
        -- shoved, dict evicted) this still breaks the glass rather than leaving
        -- the interaction hung with nothing to show for it.
        repeat
            Wait(0)
        until GetEntityAnimCurrentTime(ped, impactAnim.dict, impactAnim.clip) >= smashAt
            or GetGameTimer() - swingStartedAt >= impactMs + 750
    elseif tryAnim then
        StopAnimTask(ped, tryAnim.dict, tryAnim.clip, 2.0)
    end

    SmashVehicleWindow(vehicle, 0) -- 0 = front driver-side window
    SetVehicleAlarm(vehicle, true)
    SetVehicleAlarmTimeLeft(vehicle, smashConfig.alarmDurationMs)
    StartVehicleAlarm(vehicle)

    TriggerServerEvent('qbx_vehiclekeys:server:smashedWindow', NetworkGetNetworkIdFromEntity(vehicle))
    TriggerServerEvent('hud:server:GainStress', math.random(smashConfig.stressGain[1], smashConfig.stressGain[2]))

    -- Ride the clip out to its own natural end (the reach through the broken
    -- window) and let the task blend itself out, rather than StopAnimTask-ing
    -- it on a timer that could clip the last few frames. StopAnimTask is only
    -- the safety net if it somehow overruns.
    if impactMs > 0 then
        local deadline = swingStartedAt + impactMs + 1000
        while GetGameTimer() < deadline and IsEntityPlayingAnim(ped, impactAnim.dict, impactAnim.clip, 3) do
            Wait(0)
        end

        if IsEntityPlayingAnim(ped, impactAnim.dict, impactAnim.clip, 3) then
            StopAnimTask(ped, impactAnim.dict, impactAnim.clip, 2.0)
        end
    end

    -- Rolled on top of SendPoliceAlertAttempt's own chance, so the honor tier can
    -- only ever pull the odds down from this resource's normal baseline.
    if math.random() <= (tuning.alertChanceMultiplier or 1.0) then
        SendPoliceAlertAttempt(locale('info.crime_smash'), vehicle)
    end

    exports.qbx_core:Notify(locale('notify.window_smashed'), 'success')
    isSmashing = false
end

-- An ox_target option on the driver door, not a dialog.
--
-- This started as a centred alertDialog fired the moment you tried a locked
-- door. That is a full-screen modal for a small, optional action - it stole
-- focus, interrupted whatever you were doing, and needed its own per-vehicle
-- cooldown so holding the enter key could not spam it. The target eye already
-- solves all of that: it only appears when you deliberately look at the door,
-- costs nothing when ignored, and needs no polling loop.
--
-- Used to step aside when vice_hud was running, because client/slimjim.lua
-- put both options in vice_hud's world-actions prompt instead and this
-- registration would have stacked a second prompt on top of that one.
--
-- CHANGED 2026-09-12 (osm-target migration): targeting is osm-target now, and
-- the rail is the single front end for everything on a vehicle. slimjim.lua no
-- longer draws a vice_hud prompt at all -- it registers its own Slim Jim row
-- next to this one -- so this row is once again the only thing offering a
-- smash, whether or not vice_hud is running. The vice_hud check is therefore
-- gone; the ox_target one stays, since without a target there is no front end.
-- Nothing about SmashWindow's own behaviour changes.
-- Targeting is ox_target / osm-target, or part of vice_hud.
if smashConfig.enable and (GetResourceState('ox_target') == 'started' or GetResourceState('vice_hud') == 'started') then
    exports.ox_target:addGlobalVehicle({
        {
            name = 'qbx_vehiclekeys:smashwindow',
            label = locale('target.smash_window'),
            icon = 'fas fa-hand-fist',
            distance = smashConfig.maxDistance,
            -- Restricted to the driver-side door bones, so you cannot smash your
            -- way in by aiming at the boot.
            bones = smashConfig.targetBones,
            canInteract = function(entity)
                return GetIsSmashable(entity)
            end,
            onSelect = function(data)
                SmashWindow(data.entity)
            end,
        }
    })
elseif smashConfig.enable then
    -- Loud rather than silent: without this the option simply never appears and
    -- there is nothing on screen or in the log to say why.
    lib.print.warn('window smashing is enabled but ox_target is not started - the option will not appear')
end

---Mirrors a smash onto every other client, since SmashVehicleWindow is local.
RegisterNetEvent('qbx_vehiclekeys:client:windowSmashed', function(netId)
    if not NetworkDoesNetworkIdExist(netId) then return end

    local vehicle = NetToVeh(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end

    SmashVehicleWindow(vehicle, 0)
end)
