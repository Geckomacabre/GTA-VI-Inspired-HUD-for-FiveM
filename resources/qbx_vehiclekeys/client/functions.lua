local config = require 'config.client'

-- ---------------------------------------------------------------------------
-- Break-in animations
-- ---------------------------------------------------------------------------
-- Every anim entry in config.anims resolves model -> class -> default, and any
-- of those three may be EITHER one { dict, clip } table or a LIST of them. A
-- list is picked from at random per attempt, which is the whole reason this
-- helper exists: the same forced entry playing identically every single time
-- reads as one canned move rather than someone working a door.
--
-- A clip that is not in its dict makes TaskPlayAnim silently do nothing (that
-- is exactly how smashWindow ended up with no animation for a while, see the
-- note on it in config/client.lua), and a dict that does not exist on this
-- build behaves the same way. Neither reports an error, so the dict is checked
-- here and an entry that fails is dropped instead of played into the void.

---Is this dict/clip pair real on this build?
---
---Both halves have to be checked and neither reports an error on its own.
---DoesAnimDictExist covers the dict. For the clip there is no direct native, so
---this uses GetAnimDuration, which returns 0 for a name that is not in the
---dict: that is the only way to tell a real clip from a plausible-looking
---typo, and a typo is indistinguishable from a working anim at runtime because
---TaskPlayAnim just quietly does nothing.
---@param dict string
---@param clip string
---@return boolean
local function getAnimIsReal(dict, clip)
    if type(dict) ~= 'string' or dict == '' then return false end
    if type(clip) ~= 'string' or clip == '' then return false end
    if not DoesAnimDictExist(dict) then return false end

    -- GetAnimDuration reads clip metadata, so the dict has to be in memory.
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)

        local timeout = GetGameTimer() + 5000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
            Wait(0)
        end

        if not HasAnimDictLoaded(dict) then return false end
    end

    return GetAnimDuration(dict, clip) > 0.0
end

---Drops variants that are not real, in place.
---@param entry table one { dict, clip } or a list of them
---@param label string for the console summary
---@return table? entry, or nil when nothing in it survived
local function pruneAnimEntry(entry, label)
    if type(entry) ~= 'table' then return end

    if entry.dict then
        if getAnimIsReal(entry.dict, entry.clip) then return entry end
        print(('^3[qbx_vehiclekeys]^7 %s: "%s / %s" is not a real anim on this build, dropped')
            :format(label, tostring(entry.dict), tostring(entry.clip)))
        return
    end

    local kept = {}
    for i = 1, #entry do
        local variant = entry[i]
        if type(variant) == 'table' and getAnimIsReal(variant.dict, variant.clip) then
            kept[#kept + 1] = variant
        elseif type(variant) == 'table' then
            print(('^3[qbx_vehiclekeys]^7 %s: "%s / %s" is not a real anim on this build, dropped')
                :format(label, tostring(variant.dict), tostring(variant.clip)))
        end
    end

    return #kept > 0 and kept or nil
end

-- Validated ONCE at startup rather than per attempt, so the resolver below is a
-- plain table lookup with no streaming work or blocking wait in the middle of
-- someone breaking into a car. It also means the console says plainly which
-- clips are real on this build, which is the only practical way to find out:
-- there is no offline list, and a wrong clip name looks exactly like a working
-- one right up until nothing plays.
CreateThread(function()
    if not config.anims then return end

    for name, anims in pairs(config.anims) do
        if type(anims) == 'table' then
            for _, bucket in ipairs({ 'default', 'class', 'model' }) do
                local value = anims[bucket]
                if bucket == 'default' then
                    anims.default = pruneAnimEntry(value, name .. '.default')
                elseif type(value) == 'table' then
                    for key, entry in pairs(value) do
                        value[key] = pruneAnimEntry(entry, ('%s.%s[%s]'):format(name, bucket, tostring(key)))
                    end
                end
            end
        end
    end
end)

---Resolves one anim entry for a vehicle, picking at random when that entry is
---a list of variants. Everything here has already been validated at startup.
---@param anims { default: table, class: table, model: table }?
---@param vehicle number
---@return { dict: string, clip: string }? nil when nothing usable is configured
function ResolveVehicleAnim(anims, vehicle)
    if not anims then return end

    local entry = anims.model and anims.model[GetEntityModel(vehicle)]
        or anims.class and anims.class[GetVehicleClass(vehicle)]
        or anims.default
    if type(entry) ~= 'table' then return end

    if entry.dict then return entry end
    if #entry == 0 then return end

    return entry[math.random(#entry)]
end

---Grants keys for job shared vehicles
---@param vehicle number The entity number of the vehicle.
---@return boolean? `true` if the vehicle is shared for a player's job, `nil` otherwise.
function AreKeysJobShared(vehicle)
    local job = QBX.PlayerData.job.name
    local jobInfo = config.sharedKeys[job]

    if not jobInfo or (jobInfo.requireOnDuty and not QBX.PlayerData.job.onduty) then return end

    assert(jobInfo.vehicles, string.format('Vehicles not configured for the %s job.', job))
    return jobInfo.vehicles and jobInfo.vehicles[GetEntityModel(vehicle)] or jobInfo.classes and jobInfo.classes[GetVehicleClass(vehicle)]
end

---Checks if player has vehicle keys
---@param vehicle number
---@return boolean `true` if player has vehicle keys, `false` otherwise.
function HasKeys(vehicle)
    vehicle = vehicle or cache.vehicle
    if not vehicle then return false end
    local keysList = LocalPlayer.state.keysList
    if keysList then
        local sessionId = Entity(vehicle).state.sessionId
        if keysList[sessionId] then
            return true
        end
    end

    local owner = Entity(vehicle).state.owner
    if owner and QBX.PlayerData.citizenid == owner then
        lib.callback.await('qbx_vehiclekeys:server:giveKeys', false, VehToNet(vehicle))
        return true
    end

    return false
end

exports('HasKeys', HasKeys)

---Checks if player has vehicle keys of or access to the vehicle is provided as part of his job.
---@param vehicle number The entity number of the vehicle.
---@return boolean? `true` if player has access to the vehicle, `nil` otherwise.
function GetIsVehicleAccessible(vehicle)
    return HasKeys(vehicle) or AreKeysJobShared(vehicle)
end

-- Exported (not just HasKeys above) so ox_target/client/defaults.lua's own
-- door-toggle options can gate on the SAME "do I actually have access"
-- check slimjim.lua's getIsPickable already uses, rather than door-toggle
-- only ever looking at the vehicle's raw lock status. HasKeys alone would
-- miss job-shared access (AreKeysJobShared, not exported -- job-share rules
-- read this resource's own config.client, no reason for another resource
-- to duplicate that), which this combines the same way getIsPickable does.
exports('GetIsVehicleAccessible', GetIsVehicleAccessible)

local alertSend = false --Variable strictly related to sendPoliceAlertAttempt, not used elsewhere
function SendPoliceAlertAttempt(crime, vehicle)
    if alertSend then return end
    alertSend = true

    local hoursOffset = (24 + GetClockHours() - config.policeAlertNightStartHour) % 24; --Hour from the start of the night hours
    local chance = hoursOffset > config.policeAlertNightDuration
        and config.policeAlertChance
        or config.policeNightAlertChance

    if math.random() <= chance then
        config.alertPolice(crime, vehicle)
    end

    SetTimeout(config.alertCooldown, function()
        alertSend = false
    end)
end

---Gets bone coords
---@param entity number The entity index.
---@param boneName string The entity bone name.
---@return vector3 `Bone coords` if exists, `entity coords` otherwise.
local function getBoneCoords(entity, boneName)
    local boneIndex = GetEntityBoneIndexByName(entity, boneName)

    return boneIndex ~= -1
        and GetWorldPositionOfEntityBone(entity, boneIndex)
        or GetEntityCoords(entity)
end

---Checks if any of the bones are close enough to the coords
---@param coords vector3
---@param entity number
---@param bones table
---@param maxDistance number
---@return boolean? `true` if bone exists, `nil` otherwise.
local function getIsCloseToAnyBone(coords, entity, bones, maxDistance)
    for i = 1, #bones do
        local boneCoords = getBoneCoords(entity, bones[i])
        if #(coords - boneCoords) < maxDistance then
            return true
        end
    end
end

local doorBones = {'door_dside_f', 'door_dside_r', 'door_pside_f', 'door_pside_r'}

---Checking whether the character is close enough to the vehicle driver door.
---@param vehicle number The entity number of the vehicle.
---@param maxDistance number The max distance to check.
---@return boolean? `true` if the player ped is next to an open vehicle, `nil` otherwise.
local function getIsVehicleInRange(vehicle, maxDistance)
    local vehicles = GetGamePool('CVehicle')
    local pedCoords = GetEntityCoords(cache.ped)
    for i = 1, #vehicles do
        local v = vehicles[i]
        if not cache.vehicle or v ~= cache.vehicle then
            if vehicle == v and getIsCloseToAnyBone(pedCoords, vehicle, doorBones, maxDistance) then
                return true
            end
        end
    end
end

---Checks whether the player ped is standing close enough to one of a vehicle's
---door bones. Exposed for client/smashwindow.lua, which needs the same
---"am I actually at the door" test LockpickDoor does.
---@param vehicle number The entity number of the vehicle.
---@param maxDistance number
---@return boolean
function GetIsCloseToVehicleDoor(vehicle, maxDistance)
    return getIsCloseToAnyBone(GetEntityCoords(cache.ped), vehicle, doorBones, maxDistance) or false
end

---Chance to destroy lockpick
---@param isAdvancedLockedpick any
---@param vehicle number
local function breakLockpick(isAdvancedLockedpick, vehicle)
    local chance = math.random()
    local vehicleConfig = GetVehicleConfig(vehicle)
    if isAdvancedLockedpick then -- there is no benefit to using an advanced tool in the default configuration.
        if chance <= vehicleConfig.removeAdvancedLockpickChance then
            TriggerServerEvent("qb-vehiclekeys:server:breakLockpick", "advancedlockpick")
        end
    else
        if chance <= vehicleConfig.removeNormalLockpickChance then
            TriggerServerEvent("qb-vehiclekeys:server:breakLockpick", "lockpick")
        end
    end
end

---Will be executed when the lock opening is successful.
---@param vehicle number The entity number of the vehicle.
local function lockpickSuccessCallback(vehicle)
    TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
    exports.qbx_core:Notify(locale("notify.vehicle_lockedpick"), 'success')
    TriggerServerEvent('qb-vehiclekeys:server:setVehLockState', NetworkGetNetworkIdFromEntity(vehicle), 1)
end

---Operations done after the LockpickDoor quickevent done.
---@param vehicle number The entity number of the vehicle.
---@param isAdvancedLockedpick boolean Determines whether an advanced lockpick was used.
---@param isSuccess boolean? Determines whether the lock has been successfully opened.
local function lockpickCallback(vehicle, isAdvancedLockedpick, isSuccess)
    if isSuccess then
        lockpickSuccessCallback(vehicle)
    else -- if player fails quickevent
        SendPoliceAlertAttempt('carjack', vehicle)
        SetVehicleAlarm(vehicle, false)
        SetVehicleAlarmTimeLeft(vehicle, config.vehicleAlarmDuration)
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        exports.qbx_core:Notify(locale('notify.failed_lockedpick'), 'error')
    end

    breakLockpick(isAdvancedLockedpick, vehicle)
end

local islockpickingProcessLocked = false -- lock flag
---Lockpicking quickevent.
---@param isAdvancedLockedpick boolean Determines whether an advanced lockpick was used
---@param maxDistance number? The max distance to check.
---@param customChallenge boolean? lockpick challenge
function LockpickDoor(isAdvancedLockedpick, maxDistance, customChallenge)
    maxDistance = maxDistance or 2
    local pedCoords = GetEntityCoords(cache.ped)
    local vehicle = lib.getClosestVehicle(pedCoords, maxDistance * 2, false) -- The difference between the door and the center of the vehicle

    if not vehicle then return end

    local isDriverSeatFree = IsVehicleSeatFree(vehicle, -1)

    if GetVehicleDoorLockStatus(vehicle) < 2 then exports.qbx_core:Notify(locale('notify.vehicle_is_unlocked'), 'error') return end

    --- player may attempt to open the lock if:
    if not isDriverSeatFree -- no one in the driver's seat
        or not getIsCloseToAnyBone(pedCoords, vehicle, doorBones, maxDistance) -- the player's ped is close enough to the driver's door
        or GetVehicleConfig(vehicle).lockpickImmune
    then return end

    local skillCheckConfig = config.skillCheck[isAdvancedLockedpick and 'advancedLockpick' or 'lockpick']

    skillCheckConfig = skillCheckConfig.model[GetEntityModel(vehicle)]
        or skillCheckConfig.class[GetVehicleClass(vehicle)]
        or skillCheckConfig.default
    if not next(skillCheckConfig) then return end

    if islockpickingProcessLocked then return end -- start of the critical section
    islockpickingProcessLocked = true -- one call per player at a time

    CreateThread(function()
        local anim = ResolveVehicleAnim(config.anims.lockpick, vehicle)
        if anim then
            lib.playAnim(cache.ped, anim.dict, anim.clip, 3.0, 3.0, -1, 16, 0, false, false, false) -- lock opening animation
        end
        local isSuccess = customChallenge or lib.skillCheck(skillCheckConfig.difficulty, skillCheckConfig.inputs)

        if getIsVehicleInRange(vehicle, maxDistance) then -- the action will be aborted if the opened vehicle is too far.
            lockpickCallback(vehicle, isAdvancedLockedpick, isSuccess)
        end

        Wait(config.lockpickCooldown)
        islockpickingProcessLocked = false -- end of the critical section
    end)
end

---Will be executed when the lock opening is successful.
---@param vehicle number The entity number of the vehicle.
local function hotwireSuccessCallback(vehicle)
    TriggerServerEvent('qbx_vehiclekeys:server:hotwiredVehicle', VehToNet(vehicle))
end

---Operations done after the LockpickDoor quickevent done.
---@param vehicle number The entity number of the vehicle.
---@param isAdvancedLockedpick boolean Determines whether an advanced lockpick was used.
---@param isSuccess boolean? Determines whether the lock has been successfully opened.
local function hotwireCallback(vehicle, isAdvancedLockedpick, isSuccess)
    if isSuccess then
        hotwireSuccessCallback(vehicle)
    else -- if player fails quickevent
        SendPoliceAlertAttempt('carjack', vehicle)
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        exports.qbx_core:Notify(locale('notify.failed_lockedpick'), 'error')
    end

    breakLockpick(isAdvancedLockedpick, vehicle)
end

local isHotwiringProcessLocked = false -- lock flag
---Hotwiring with a tool quickevent.
---@param vehicle number The entity number of the vehicle.
---@param isAdvancedLockedpick boolean Determines whether an advanced lockpick was used
---@param customChallenge boolean? lockpick challenge
function Hotwire(vehicle, isAdvancedLockedpick, customChallenge)
    if cache.seat ~= -1 or GetIsVehicleAccessible(vehicle) then return end
    local skillCheckConfig = config.skillCheck[isAdvancedLockedpick and 'advancedHotwire' or 'hotwire']

    skillCheckConfig = skillCheckConfig.model[GetEntityModel(vehicle)]
        or skillCheckConfig.class[GetVehicleClass(vehicle)]
        or skillCheckConfig.default
    if not next(skillCheckConfig) then return end

    if isHotwiringProcessLocked then return end -- start of the critical section
    isHotwiringProcessLocked = true -- one call per player at a time

    CreateThread(function()
        local anim = ResolveVehicleAnim(config.anims.hotwire, vehicle)
        if anim then
            lib.playAnim(cache.ped, anim.dict, anim.clip, 3.0, 3.0, -1, 16, 0, false, false, false) -- hotwire animation
        end
        local isSuccess = customChallenge or lib.skillCheck(skillCheckConfig.difficulty, skillCheckConfig.inputs)

        hotwireCallback(vehicle, isAdvancedLockedpick, isSuccess)

        Wait(config.hotwireCooldown)
        isHotwiringProcessLocked = false -- end of the critical section
    end)
end