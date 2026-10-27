-- ============================================================================
-- qbx_vehiclekeys / client / slimjim
--
-- A Slim Jim row on the driver door of a locked, keyless vehicle, plus its
-- "hold, release inside the zone" lockpick ring (vice_hud's, still).
--
-- CHANGED 2026-09-12 (osm-target migration). This file used to own the front
-- end as well: a 250ms proximity loop that drew a combined "Slim Jim / Smash
-- Window" list through vice_hud's world-actions prompt, each row on its own
-- keybind. Targeting is osm-target now, and having a walk-up-and-press prompt
-- on the same door the rail already lists doors, boot and bonnet on meant two
-- interaction styles on one car. The prompt loop is gone; the row is registered
-- on the target instead, and smashwindow.lua's own row -- previously suppressed
-- whenever vice_hud ran -- is live again beside it.
--
-- The RING is unchanged and still vice_hud's, because it is good and there is
-- nothing in osm-target to replace it with. While it runs he works a slim jim
-- (a 50 cm strip in his fists) into the window, with the single-player
-- version's clips (see "the slim jim in his hands" below). What changed is only how it STARTS:
-- picking the row calls slimJim() directly rather than a key press doing it.
-- The release still has to be a key, since the ring is timed on hold length --
-- see the keybind below, which is now enabled only while a ring is actually up.
--
-- Deliberately NOT built on LockpickDoor / lib.skillCheck
-- (client/functions.lua). That flow already exists, already works, and is
-- left completely alone; this is a second, parallel front end for the same
-- kind of theft, using vice_hud's ring instead of ox_lib's skill check, and
-- firing its own server event (qbx_vehiclekeys:server:slimJimmed) rather
-- than reusing functions.lua's locals, which aren't visible across files in
-- the same resource.
-- ============================================================================

-- Still gated on vice_hud: the lockpick ring is its export. Without it there is
-- no Slim Jim, and Smash Window carries on alone through smashwindow.lua.
if GetResourceState('vice_hud') ~= 'started' then return end

local config = require 'config.client'
local sjConfig = config.slimJim

if not sjConfig.enable then return end

local isSlimJimming = false
local endAttempt = nil -- while a ring runs: ends it with no result (the key let go)

-- Declared here, assigned further down where the binding is built: slimJim()
-- has to arm it when a ring goes up and disarm it when one comes down, and it
-- is defined above that point.
local slimJimKeybind

---@param vehicle number
---@return boolean
local function getIsPickable(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if cache.vehicle then return false end -- already sat in something
    if GetVehicleDoorLockStatus(vehicle) < 2 then return false end -- not locked
    if not IsVehicleSeatFree(vehicle, -1) then return false end -- someone is in the driver's seat
    if GetIsVehicleAccessible(vehicle) then return false end -- we have keys / job access

    local vehicleConfig = GetVehicleConfig(vehicle)
    if vehicleConfig.noLock or vehicleConfig.shared or vehicleConfig.lockpickImmune then return false end

    return true
end

---Which Slim Jim tier the player is carrying, if any. Its own dedicated
---items (slimjim / slimjim_pro, see ox_inventory's data/items.lua), not the
---lockpick items LockpickDoor uses, those are a different tool for a
---different flow. Pro preferred when they have both, no reason to burn the
---better tool if a plain one would do, but if all they brought was the good
---one, that's what's used.
---@return 'advanced'|'base'|nil
local function getLockpickTier()
    local okAdv, hasAdvanced = pcall(function() return exports.ox_inventory:Search('count', 'slimjim_pro') end)
    if okAdv and hasAdvanced and hasAdvanced > 0 then return 'advanced' end
    local okBase, hasBase = pcall(function() return exports.ox_inventory:Search('count', 'slimjim') end)
    if okBase and hasBase and hasBase > 0 then return 'base' end
    return nil
end

---Mirrors smashwindow.lua's own getHonorTuning() almost exactly, see that
---file's comment for the full reasoning. Not shared between the two: their
---locals aren't visible across files in the same resource, and extracting a
---module for a dozen lines would touch smashwindow.lua for no real gain.
---@return {durationMultiplier: number, alertChanceMultiplier: number}
local function getHonorTuning()
    -- Honor is the qbx_honor resource, or part of vice_hud.
    if GetResourceState('qbx_honor') ~= 'started' and GetResourceState('vice_hud') ~= 'started' then return sjConfig.honor.neutral end

    local ok, honor = pcall(function() return exports.qbx_honor:GetHonor() end)
    if not ok or type(honor) ~= 'number' then return sjConfig.honor.neutral end

    local tierOk, tier = pcall(function() return exports.qbx_honor:GetBadgeTier(honor) end)
    if not tierOk then tier = nil end

    return sjConfig.honor[tier or 'neutral'] or sjConfig.honor.neutral
end

---@param vehicle number
---@param tier 'advanced'|'base'
local function onSlimJimResult(vehicle, tier, success)
    if success then
        TriggerServerEvent('qbx_vehiclekeys:server:slimJimmed', NetworkGetNetworkIdFromEntity(vehicle))
        TriggerServerEvent('hud:server:GainStress', math.random(sjConfig.stressGain[1], sjConfig.stressGain[2]))
        exports.qbx_core:Notify(locale('notify.vehicle_lockedpick'), 'success')
    else
        exports.qbx_core:Notify(locale('notify.failed_lockedpick'), 'error')
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))

        -- Same durability fields LockpickDoor's own breakLockpick already
        -- reads (shared/vehicle-config.lua). A vehicle tuned harder to
        -- pick is harder for BOTH flows to walk away from, not just one.
        local vehicleConfig = GetVehicleConfig(vehicle)
        local breakChance = tier == 'advanced'
            and vehicleConfig.removeAdvancedLockpickChance
            or vehicleConfig.removeNormalLockpickChance
        if math.random() <= (breakChance or 0) then
            TriggerServerEvent('qb-vehiclekeys:server:breakLockpick', tier == 'advanced' and 'slimjim_pro' or 'slimjim')
        end

        local tuning = getHonorTuning()
        if math.random() <= (tuning.alertChanceMultiplier or 1.0) then
            SendPoliceAlertAttempt(locale('info.crime_smash'), vehicle)
        end
    end
end

-- ---- the slim jim in his hands -------------------------------------------
-- The single-player version's clips and strip (stream/vi_slimjim.ycd,
-- stream/vi_prop_slimjim.ydr + .ytyp, made on top of GTA's own
-- veh@break_in@0h@p_m_one@ low_force_entry_ds): he steps up to the front
-- door, bends to the window and works a 50 cm strip into the gap with both
-- fists for as long as the ring runs, then pulls it out and straightens. The
-- clips were made for one spot: 30 cm out from the front door's handle,
-- facing it, the strip 5 cm to his left, so he's slid there over 0.3 s.
-- config.client slimJim.animation = false plays config.anims.slimJim instead.

local SJ_DICT = 'vi_slimjim'
local SJ_PROP = `vi_prop_slimjim`
-- the middle of his right fist from SKEL_R_Hand (57005), where the strip's
-- handle goes; the prop's axes are the hand bone's, so it needs no turn
local SJ_GRIP = vec3(0.0934, 0.0, -0.003)
local SJ_STAND_OUT, SJ_STRIP_LEFT, SJ_SKIN_IN = 0.30, 0.05, 0.03

local sjStage = nil -- a table while the clips run (each run its own), nil when not
local sjProp = nil

---Where the clips want him for this car: in front of the nearer front door's
---handle (its door when the car has no handle bones), facing it.
---@return vector3?, number?
local function slimJimSpot(vehicle)
    local from = GetEntityCoords(cache.ped)
    local best, bestDist
    for _, names in ipairs({ { 'handle_dside_f', 'door_dside_f' }, { 'handle_pside_f', 'door_pside_f' } }) do
        for _, name in ipairs(names) do
            local bone = GetEntityBoneIndexByName(vehicle, name)
            if bone ~= -1 then
                local p = GetWorldPositionOfEntityBone(vehicle, bone)
                local d = #(p - from)
                if not bestDist or d < bestDist then best, bestDist = p, d end
                break
            end
        end
    end
    if not best then return nil end
    local h = math.rad(GetEntityHeading(vehicle))
    local right = vec3(math.cos(h), math.sin(h), 0.0)
    local rel = best - GetEntityCoords(vehicle)
    local outward = (rel.x * right.x + rel.y * right.y) < 0.0 and right * -1.0 or right
    local facing = outward * -1.0
    local left = vec3(-facing.y, facing.x, 0.0)
    local strip = best - outward * SJ_SKIN_IN
    local stand = strip + outward * SJ_STAND_OUT - left * SJ_STRIP_LEFT
    return vec3(stand.x, stand.y, from.z), math.deg(math.atan(-facing.x, facing.y))
end

---@return boolean started
local function startSlimJimAnim(vehicle)
    if not pcall(lib.requestAnimDict, SJ_DICT, 2000) then return false end
    local ped = cache.ped
    local stage = {}
    sjStage = stage

    SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    TaskPlayAnim(ped, SJ_DICT, 'slimjim_in', 4.0, -4.0, -1, 2, 0.0, false, false, false)

    -- the step into place
    local to, heading = slimJimSpot(vehicle)
    if to then
        CreateThread(function()
            local from, fromHeading = GetEntityCoords(ped), GetEntityHeading(ped)
            local turn = ((heading - fromHeading) % 360.0 + 540.0) % 360.0 - 180.0
            local start = GetGameTimer()
            while sjStage == stage do
                local t = math.min(1.0, (GetGameTimer() - start) / 300.0)
                local e = t * t * (3.0 - 2.0 * t)
                local p = from + (to - from) * e
                -- keepTasks, keepIK on: with keepTasks off every step dropped
                -- slimjim_in, so he T-posed until the loop started. doWarp off:
                -- a 30 cm step, not a teleport.
                SetEntityCoordsNoOffset(ped, p.x, p.y, from.z, true, true, false)
                SetEntityHeading(ped, fromHeading + turn * e)
                if t >= 1.0 then break end
                Wait(0)
            end
        end)
    end

    -- in (1.0 s), then the loop for as long as the ring runs
    SetTimeout(950, function()
        if sjStage == stage then
            TaskPlayAnim(ped, SJ_DICT, 'slimjim_loop', 8.0, -4.0, -1, 1, 0.0, false, false, false)
        end
    end)

    -- the strip in his right fist
    CreateThread(function()
        if not pcall(lib.requestModel, SJ_PROP, 2000) or sjStage ~= stage then return end
        local c = GetEntityCoords(ped)
        local prop = CreateObject(SJ_PROP, c.x, c.y, c.z, true, true, false)
        SetModelAsNoLongerNeeded(SJ_PROP)
        if sjStage ~= stage then DeleteEntity(prop) return end
        SetEntityCollision(prop, false, false)
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 57005), SJ_GRIP.x, SJ_GRIP.y, SJ_GRIP.z,
            0.0, 0.0, 0.0, true, true, false, true, 2, true)
        sjProp = prop
    end)
    return true
end

---Out (0.8 s): he pulls it out and straightens, and the strip goes.
---@param instant boolean? no out clip, everything off now (the resource stopping)
local function stopSlimJimAnim(instant)
    if not sjStage then return end
    sjStage = nil
    local ped, prop = cache.ped, sjProp
    sjProp = nil
    if instant then
        StopAnimTask(ped, SJ_DICT, 'slimjim_in', 4.0)
        StopAnimTask(ped, SJ_DICT, 'slimjim_loop', 4.0)
        if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
        return
    end
    TaskPlayAnim(ped, SJ_DICT, 'slimjim_out', 8.0, -4.0, -1, 0, 0.0, false, false, false)
    SetTimeout(800, function()
        if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    end)
end

local function slimJim(vehicle)
    if isSlimJimming then return end
    local tier = getLockpickTier()
    if not tier then
        exports.qbx_core:Notify(locale('notify.no_lockpick'), 'error')
        return
    end

    isSlimJimming = true
    -- The ring is timed on how long the key is held, so the binding has to be
    -- live for the release to register. Armed only now, never while the player
    -- is merely standing near a car, so R does nothing until they pick the row.
    slimJimKeybind:disable(false)

    -- ADDED 2026-09-13 (first real in-game test): Smash Window's own progress
    -- bar (lib.progressCircle) already stops osm-target from re-scanning/
    -- re-opening a menu mid-action, because osm-target's own blocked() check
    -- reads lib.progressActive(). This ring is a separate vice_hud mechanic,
    -- outside ox_lib's progress system entirely, so osm-target had no way to
    -- know it was running -- it kept sweeping the same door, and the moment
    -- the player pressed LMB to drag the ring (this mechanic's OWN input),
    -- osm-target's shared confirm binding (also LMB, Config.Input.confirm.kbm)
    -- read that same press and re-confirmed whatever the menu's focus
    -- currently was, which could land on Smash Window: the two options share
    -- one target menu, so a second, unrelated LMB press live during Slim Jim
    -- was read as "confirm the other row." exports.osm_target:disableTargeting
    -- both force-closes the menu immediately (Machine.setDisabled calls
    -- Machine.abort()) and blocks it reopening until re-enabled below --
    -- every exit path (win, lose, and the drove-off/despawned abort further
    -- down) re-enables it, so targeting always comes back regardless of how
    -- the ring ends.
    exports['osm-target']:disableTargeting(true)
    local tuning = getHonorTuning()
    local duration = math.floor(sjConfig.ringDurationMs * (tuning.durationMultiplier or 1.0))
    local zoneLen = tier == 'advanced' and sjConfig.zoneLenAdvanced or sjConfig.zoneLenBase

    -- Slim jim had no animation at all: the ring came up and the character
    -- stood there. It uses the same working-a-door anims the lockpick flow
    -- does (config.anims.slimJim), since that is the same act with a
    -- different tool in hand.
    --
    -- -1 duration, not the ring's length: the hold can end early on a win, a
    -- miss, or the car driving off, and every one of those paths goes through
    -- handleResult below, which stops it. Timing it to the ring instead would
    -- leave the anim running past a result that arrived sooner.
    --
    -- The single-player clips and strip come first (slimJim.animation); the
    -- lockpick's clips are the fallback, and also what plays when the clips'
    -- dictionary can't be loaded.
    local anim = nil
    if not (sjConfig.animation and startSlimJimAnim(vehicle)) then
        anim = ResolveVehicleAnim(config.anims.slimJim, vehicle)
        if anim then
            lib.playAnim(cache.ped, anim.dict, anim.clip, 3.0, 3.0, -1, 16, 0, false, false, false)
        end
    end

    local resultHandled = false
    local handler, alarmHandler

    -- Every way a ring ends hands back what it took: the release key,
    -- targeting, and his hands.
    local function finish()
        if resultHandled then return false end
        resultHandled = true
        if handler then RemoveEventHandler(handler) end
        if alarmHandler then RemoveEventHandler(alarmHandler) end
        handler, alarmHandler, endAttempt = nil, nil, nil
        isSlimJimming = false
        slimJimKeybind:disable(true)
        exports['osm-target']:disableTargeting(false)
        if anim then StopAnimTask(cache.ped, anim.dict, anim.clip, 1.0) end
        stopSlimJimAnim()
        return true
    end

    local function handleResult(success)
        if not finish() then return end
        if DoesEntityExist(vehicle) and GetIsCloseToVehicleDoor(vehicle, sjConfig.maxDistance) then
            onSlimJimResult(vehicle, tier, success)
        end
    end

    -- vice_hud:lockpickResult is fired locally (TriggerEvent, not
    -- TriggerClientEvent, see StartLockpickCheck/ReleaseLockpickCheck in
    -- vice_hud/client.lua), so this is a plain client-side AddEventHandler,
    -- not a net event.
    handler = AddEventHandler('vice_hud:lockpickResult', function(success)
        handleResult(success)
    end)

    -- Pushed the wrong way to 100%: vice_hud's trap. It sends no
    -- lockpickResult, so without this the ring's attempt never ended (the
    -- release key stayed armed and targeting stayed off). The car's alarm goes
    -- off (as in single player, and the way smashwindow.lua sets it off), and
    -- it counts as a failed pick.
    alarmHandler = AddEventHandler('vice_hud:lockpickAlarm', function()
        if DoesEntityExist(vehicle) then
            SetVehicleAlarm(vehicle, true)
            SetVehicleAlarmTimeLeft(vehicle, config.smashWindow.alarmDurationMs)
            StartVehicleAlarm(vehicle)
        end
        handleResult(false)
    end)

    -- Letting go of the key before the ring is done (ReleaseLockpickCheck)
    -- sends nothing either: no result, everything handed back.
    endAttempt = function() finish() end

    -- Cancel outright (no win, no lose) if the vehicle drives off or
    -- despawns mid-hold, same guard smashWindow's own progress bar has.
    CreateThread(function()
        while isSlimJimming do
            if not DoesEntityExist(vehicle) or not GetIsCloseToVehicleDoor(vehicle, sjConfig.maxDistance * 2) then
                exports.vice_hud:CancelLockpickCheck()
                -- This path deliberately skips handleResult (no win, no lose,
                -- nothing to report) but still has to stop the anim, or the
                -- character keeps working a door that has driven away.
                finish()
                return
            end
            Wait(200)
        end
    end)

    exports.vice_hud:StartLockpickCheck({ durationMs = duration, zoneLen = zoneLen, glyph = 'R' })
end

-- ---- the release binding ---------------------------------------------------

-- This was one of two bindings, each answering a row of the vice_hud prompt
-- this file used to draw. That prompt is gone (see "the row" below), and with
-- it the 2026-08-28 glyph fix that lived here: vice_hud resolved the prompt's
-- controller icon from these keys' `.hash` so label and binding could not
-- drift apart. Nothing draws a glyph for this binding any more, so there is
-- nothing left to keep in sync -- the ring draws its own, from the `glyph`
-- field slimJim() passes to StartLockpickCheck.
--
-- The secondary mapper stays: RUP_INDEX is Y/Triangle (a FACE button, per
-- docs.fivem.net/docs/game-references/input-mapper-parameter-ids/
-- pad_digitalbuttonany/ -- earlier comments here guessed "RB/R1" and were
-- wrong), so a pad player can still time the release.
--
-- No longer the entry point -- the target row is. This binding exists purely to
-- END a ring: it is disabled until slimJim() arms it, so the only press that
-- ever reaches it is the one timing a lockpick that is already running.
-- onPressed is a no-op for that reason; the release is the whole point.
slimJimKeybind = lib.addKeybind({
    name = 'slimjim',
    description = locale('target.slim_jim'),
    defaultKey = 'R',
    defaultMapper = 'keyboard',
    secondaryMapper = 'PAD_DIGITALBUTTONANY',
    secondaryKey = 'RUP_INDEX',           -- Triangle/Y, matches the ring's glyph
    disabled = true,
    onReleased = function()
        if not isSlimJimming then return end
        exports.vice_hud:ReleaseLockpickCheck()
        if endAttempt then endAttempt() end
    end,
})

-- REMOVED 2026-09-12: Smash Window's keybind (F, Circle on a pad). It existed
-- to answer the vice_hud prompt this file used to draw; smashwindow.lua's
-- target row is the entry point now, so a binding here would be a second way
-- to do the same thing with nothing on screen saying it exists. Its whole
-- INPUT_ENTER workaround went with it -- see the note where that thread was.

-- ---- the row -------------------------------------------------------------
-- The proximity loop that used to live here is gone. It ran every 250ms,
-- called lib.getClosestVehicle, and drew vice_hud's world-actions prompt with
-- one entry per available action -- a walk-up-and-press front end, from before
-- targeting could carry this. osm-target's rail already lists the doors, boot
-- and bonnet on the same car; a second prompt at the same door meant two
-- interaction styles a metre apart. So the row goes on the target instead, and
-- the loop, its promptedVehicle bookkeeping and the INPUT_ENTER workaround
-- (needed only because Smash Window's F collided with "enter vehicle") all go
-- with it. Nothing polls now: the target asks canInteract when the player
-- actually looks at the door.
--
-- Same bones and distance the prompt used (config.client's slimJim block, whose
-- maxDistance was already commented "ox_target interaction distance" -- this is
-- what it was waiting for), and the same getIsPickable test, unchanged: locked,
-- driver's seat empty, no keys or job access, not flagged noLock/shared/
-- lockpickImmune. Smash Window sits beside it from smashwindow.lua.
exports.ox_target:addGlobalVehicle({
    {
        name = 'qbx_vehiclekeys:slimjim',
        label = locale('target.slim_jim'),
        icon = 'fas fa-screwdriver',
        distance = sjConfig.maxDistance,
        bones = sjConfig.targetBones,
        -- Two separate verdicts, deliberately. Whether the CAR can be slim
        -- jimmed is a property of the car and stays silent: a row saying
        -- "Requires slim jim" on your own unlocked vehicle would be noise, and
        -- on an occupied one it would tell you someone is sitting in it.
        -- Whether the PLAYER can is a property of their inventory, and that is
        -- worth stating -- it is the difference between "not here" and "not
        -- yet", which is the whole point of the reason string.
        --
        -- slimJim() still re-checks the tier itself and notifies on the way
        -- through. That stays: canInteract runs when the menu is built, and an
        -- inventory can empty between then and the click.
        canInteract = function(entity)
            if not getIsPickable(entity) then return false end
            if not getLockpickTier() then return false, locale('target.slim_jim_missing') end
            return true
        end,
        onSelect = function(data)
            slimJim(data.entity)
        end,
    },
})

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- No HideWorldActions any more: this file no longer shows one. A ring can
    -- still be up mid-hold when the resource stops, though, and that one is
    -- vice_hud's to close.
    if isSlimJimming then exports.vice_hud:CancelLockpickCheck() end
    stopSlimJimAnim(true)
end)
