-- Default vehicle doors: register built-in vehicle door options for ox_target parity
if not (Config.Defaults and Config.Defaults.vehicleDoors) then return end

local DOOR_BONES = {
  [0] = 'dside_f',
  [1] = 'pside_f',
  [2] = 'dside_r',
  [3] = 'pside_r',
}

---Toggle vehicle door: open or close specified door index if vehicle is unlocked.
local function toggleDoor(vehicle, door)
  if GetVehicleDoorLockStatus(vehicle) == 2 then return end

  if GetVehicleDoorAngleRatio(vehicle, door) > 0.0 then
    SetVehicleDoorShut(vehicle, door, false)
  else
    SetVehicleDoorOpen(vehicle, door, false, false)
  end
end

---Whether the player actually has access to this vehicle (keys, or
---job-shared keys) -- not just whether it happens to be unlocked right now.
---Deliberately soft-dependent on qbx_vehiclekeys: that resource exports
---GetIsVehicleAccessible specifically so this file can gate on it (see its
---own comment on that export), but osm-target ships framework-agnostic and
---must not hard-fail on a server that doesn't have qbx_vehiclekeys at all --
---such a server has no other way to grant/revoke vehicle access in the
---first place, so "permissive" is the only sane fallback, not "locked out".
local function hasVehicleAccess(vehicle)
  if GetResourceState('qbx_vehiclekeys') ~= 'started' then return true end

  local ok, accessible = pcall(function()
    return exports.qbx_vehiclekeys:GetIsVehicleAccessible(vehicle)
  end)
  if not ok then return true end

  return accessible == true
end

---Validate door interaction: verify distance to door bone or offset coordinates.
local function canInteractWithDoor(entity, coords, door, useOffset)
  if not GetIsDoorValid(entity, door)
    or GetVehicleDoorLockStatus(entity) > 1
    or IsVehicleDoorDamaged(entity, door)
    or cache.vehicle
    or not hasVehicleAccess(entity)
  then
    return false
  end

  if useOffset then return true end

  local boneName = DOOR_BONES[door]
  if not boneName then return false end

  local doorBone = GetEntityBoneIndexByName(entity, 'door_' .. boneName)
  if doorBone == -1 then return false end

  if #(coords - GetEntityBonePosition_2(entity, doorBone)) < 0.5 then return true end

  local seatBone = GetEntityBoneIndexByName(entity, 'seat_' .. boneName)
  if seatBone == -1 then return false end

  return #(coords - GetEntityBonePosition_2(entity, seatBone)) < 0.72
end

---Dispatch door toggle: execute locally on owned entities or relay to network owner via server event.
local function onSelectDoor(data, door)
  local entity = data.entity
  if not entity or entity == 0 then return end

  if NetworkGetEntityOwner(entity) == cache.playerId then
    return toggleDoor(entity, door)
  end

  TriggerServerEvent('ox_target:toggleEntityDoor', VehToNet(entity), door)
end

RegisterNetEvent('ox_target:toggleEntityDoor', function(netId, door)
  local entity = NetToVeh(netId)
  if entity and entity ~= 0 then toggleDoor(entity, door) end
end)

---Entity-local Y of a bone, +forward. nil when the model has no such bone.
local function boneForwardOffset(vehicle, boneName)
  local bone = GetEntityBoneIndexByName(vehicle, boneName)
  if bone == -1 then return nil end

  local ok, world = pcall(GetWorldPositionOfEntityBone, vehicle, bone)
  if not ok or not world then return nil end

  local okOffset, offset = pcall(GetOffsetFromEntityGivenWorldCoords, vehicle, world.x, world.y, world.z)
  if not okOffset or not offset then return nil end

  return offset.y
end

---Whether this model carries its engine in the back half.
---
---Mid- and rear-engined cars -- Infernus, Adder, Zentorno, and every addon
---built the same way -- put the engine under the rear lid and the luggage
---space under the front one, so "Hood" and "Trunk" swap ends. qb-target
---handles this with a hardcoded list of about sixty stock models; ox_target
---does not handle it at all. A list cannot survive contact with a server that
---adds its own cars, so measure it from the model instead.
---
---Measured against the midpoint of the model's own dimensions, which is the
---same frame the lid options are anchored in (see the `offset` fractions
---below), so the answer describes the end of the car the player is actually
---looking at. Deliberately not derived from the `bonnet`/`boot` bone names:
---which of those sits at which end is exactly the thing in question.
---
---Cached per model, being a property of the model rather than the instance.
---@type table<number, boolean>
local rearEngineCache = {}

local function isRearEngined(vehicle)
  local okModel, model = pcall(GetEntityModel, vehicle)
  if okModel and model then
    local cached = rearEngineCache[model]
    if cached ~= nil then return cached end
  end

  -- No engine bone to measure means no reason to depart from the conventional
  -- front-engine layout.
  local result = false
  local engineY = boneForwardOffset(vehicle, 'engine')

  if engineY then
    -- The model's own midpoint is the divider the lid anchors use. Falling
    -- back to the entity origin is close enough when dimensions are missing.
    result = engineY < 0.0

    if okModel and model then
      local okDim, minimum, maximum = pcall(GetModelDimensions, model)
      if okDim and minimum and maximum then
        result = engineY < (minimum.y + maximum.y) * 0.5
      end
    end
  end

  if okModel and model then rearEngineCache[model] = result end
  return result
end

---Label and icon for one of the two lids, resolved against the vehicle being
---looked at rather than fixed at registration, so a mid-engined car reads
---"Hood" at the back and "Trunk" at the front with the icons following the
---words instead of contradicting them.
---@param front boolean whether this is the lid at the front of the vehicle
local function lidIsEngineCover(front)
  return function(entity)
    if not entity or entity == 0 then return front end
    return isRearEngined(entity) ~= front
  end
end

local function lidLabel(front)
  local isEngineCover = lidIsEngineCover(front)
  return function(entity)
    return Locale(isEngineCover(entity) and 'door_hood' or 'door_trunk')
  end
end

local function lidIcon(front)
  local isEngineCover = lidIsEngineCover(front)
  return function(entity)
    return isEngineCover(entity) and 'car' or 'trunk'
  end
end

---@param useOffset boolean whether the option is anchored by model offset
---  rather than by a door bone. Passed explicitly rather than inferred from
---  `spatial.offset`, so the two stay independent.
local function doorOption(name, label, door, spatial, useOffset)
  local option = {
    name = 'ox_target:' .. name,
    label = label,
    icon = spatial.icon,
    distance = 2.0,
    bones = spatial.bones,
    offset = spatial.offset,
    canInteract = function(entity, _distance, coords)
      return canInteractWithDoor(entity, coords, door, useOffset)
    end,
    onSelect = function(data)
      onSelectDoor(data, door)
    end,
  }
  return option
end

CreateThread(function()
  -- Delay registration: ensure locale strings and targeting store are initialized
  Wait(0)

  Api.addGlobalVehicle({
    doorOption('driverF', Locale('door_front_driver'), 0,
      { icon = 'door', bones = { 'door_dside_f', 'seat_dside_f' } }, false),
    doorOption('passengerF', Locale('door_front_passenger'), 1,
      { icon = 'door', bones = { 'door_pside_f', 'seat_pside_f' } }, false),
    doorOption('driverR', Locale('door_rear_driver'), 2,
      { icon = 'door', bones = { 'door_dside_r', 'seat_dside_r' } }, false),
    doorOption('passengerR', Locale('door_rear_passenger'), 3,
      { icon = 'door', bones = { 'door_pside_r', 'seat_pside_r' } }, false),

    -- Both lids stay anchored by model offset, which is what has always
    -- located them; only the wording now follows the engine. Bone anchoring
    -- would be more precise, but bones and offsets are AND-ed in
    -- Hit.makeSpatial, so adding one to these would narrow where they can be
    -- hit rather than improve it.
    doorOption('bonnet', lidLabel(true), 4,
      { icon = lidIcon(true), offset = vec3(0.5, 1.0, 0.5) }, true),
    doorOption('trunk', lidLabel(false), 5,
      { icon = lidIcon(false), offset = vec3(0.5, 0.0, 0.5) }, true),
  })
end)
