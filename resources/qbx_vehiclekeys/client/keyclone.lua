-- Clone Key: the single-player HUD's key cloning (2.7), the FiveM way.
--
-- A row on a locked car's driver door, on the same target rail as Slim Jim and
-- Smash Window, for a player carrying a key cloner (ox_inventory 'key_cloner',
-- a tool: never used up). He holds a phone, the cloner, while vice_hud's key
-- clone check runs on the lockpick ring: press E (Square / X on a pad) while
-- the dot is in the pink window. Three hits and the key is his, the doors open
-- and there's no alarm; three misses and the car's alarm goes off. Backspace
-- (Circle / B) backs out with nothing either way.
--
-- Gated on vice_hud like slimjim.lua: the ring is its export.
if GetResourceState('vice_hud') ~= 'started' then return end

local config = require 'config.client'
local kcConfig = config.keyClone
if not kcConfig or not kcConfig.enable then return end

local isCloning = false

local PHONE_DICT, PHONE_CLIP = 'cellphone@', 'cellphone_text_read_base'
local PHONE_MODEL = `prop_npc_phone_02`
local RIGHT_HAND = 28422 -- PH_R_Hand

---The same test as slimjim.lua's getIsPickable: locked, the driver's seat
---empty, no keys or job access, not flagged noLock/shared/lockpickImmune.
---@param vehicle number
---@return boolean
local function getIsClonable(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if cache.vehicle then return false end
    if GetVehicleDoorLockStatus(vehicle) < 2 then return false end
    if not IsVehicleSeatFree(vehicle, -1) then return false end
    if GetIsVehicleAccessible(vehicle) then return false end

    local vehicleConfig = GetVehicleConfig(vehicle)
    if vehicleConfig.noLock or vehicleConfig.shared or vehicleConfig.lockpickImmune then return false end

    return true
end

local function hasCloner()
    local ok, count = pcall(function() return exports.ox_inventory:Search('count', kcConfig.item) end)
    return ok and (count or 0) > 0
end

---The phone in his right hand, read the way GTA's own texting is.
---@return number? prop
local function phoneOn(ped)
    lib.requestAnimDict(PHONE_DICT)
    lib.requestModel(PHONE_MODEL)
    TaskPlayAnim(ped, PHONE_DICT, PHONE_CLIP, 4.0, -4.0, -1, 49, 0.0, false, false, false)
    local prop = CreateObject(PHONE_MODEL, GetEntityCoords(ped), true, true, false)
    SetModelAsNoLongerNeeded(PHONE_MODEL)
    if not prop or prop == 0 then return nil end
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, RIGHT_HAND), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    return prop
end

local function phoneOff(ped, prop)
    StopAnimTask(ped, PHONE_DICT, PHONE_CLIP, 1.0)
    RemoveAnimDict(PHONE_DICT)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
end

---@param vehicle number
local function cloneKey(vehicle)
    if isCloning then return end
    if not hasCloner() then
        exports.qbx_core:Notify(locale('notify.no_key_cloner'), 'error')
        return
    end
    isCloning = true

    local ped = cache.ped
    -- Same reason as the slim jim: osm-target's confirm is the left mouse
    -- button too, and a press here must time the ring, not pick another row.
    exports['osm-target']:disableTargeting(true)
    local prop = phoneOn(ped)

    local done = false
    local handlers = {}

    -- Every way it ends hands back what it took: targeting and his hands.
    local function finish()
        if done then return false end
        done = true
        for _, h in ipairs(handlers) do RemoveEventHandler(h) end
        isCloning = false
        exports['osm-target']:disableTargeting(false)
        phoneOff(ped, prop)
        return true
    end

    -- vice_hud fires these locally (TriggerEvent), like the lockpick's.
    handlers[#handlers + 1] = AddEventHandler('vice_hud:keyCloneResult', function(success)
        if not finish() or not success then return end
        if DoesEntityExist(vehicle) and GetIsCloseToVehicleDoor(vehicle, kcConfig.maxDistance) then
            TriggerServerEvent('qbx_vehiclekeys:server:keyCloned', NetworkGetNetworkIdFromEntity(vehicle))
            TriggerServerEvent('hud:server:GainStress', math.random(kcConfig.stressGain[1], kcConfig.stressGain[2]))
            exports.qbx_core:Notify(locale('notify.key_cloned'), 'success')
        end
    end)

    handlers[#handlers + 1] = AddEventHandler('vice_hud:keyCloneAlarm', function()
        if not finish() then return end
        if DoesEntityExist(vehicle) then
            SetVehicleAlarm(vehicle, true)
            SetVehicleAlarmTimeLeft(vehicle, config.smashWindow.alarmDurationMs)
            StartVehicleAlarm(vehicle)
        end
        exports.qbx_core:Notify(locale('notify.key_clone_failed'), 'error')
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
    end)

    handlers[#handlers + 1] = AddEventHandler('vice_hud:keyCloneCancel', function()
        finish()
    end)

    -- Cancel outright if the car drives off or despawns, or he goes.
    CreateThread(function()
        while isCloning and not done do
            if not DoesEntityExist(vehicle) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false)
                or not GetIsCloseToVehicleDoor(vehicle, kcConfig.maxDistance * 2) then
                exports.vice_hud:CancelKeyCloneCheck()
                finish()
                return
            end
            Wait(200)
        end
    end)

    exports.vice_hud:StartKeyCloneCheck({})
end

-- On the door, beside Slim Jim (slimjim.lua) and Smash Window
-- (smashwindow.lua), with the same bones and distance. Only for a player with
-- a cloner, and silently otherwise (unlike Slim Jim's "Requires slim jim"): a
-- third row turns the door's two-button prompt (the trailer's Triangle /
-- Circle) into a list, and that should only happen for someone who can use it.
exports.ox_target:addGlobalVehicle({
    {
        name = 'qbx_vehiclekeys:clonekey',
        label = locale('target.clone_key'),
        icon = 'fas fa-key',
        distance = kcConfig.maxDistance,
        bones = kcConfig.targetBones,
        canInteract = function(entity)
            if isCloning or not getIsClonable(entity) then return false end
            return hasCloner()
        end,
        onSelect = function(data)
            cloneKey(data.entity)
        end,
    },
})

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if isCloning then exports.vice_hud:CancelKeyCloneCheck() end
end)
