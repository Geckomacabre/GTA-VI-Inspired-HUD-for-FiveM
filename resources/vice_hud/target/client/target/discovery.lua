local Resolver = OsmTargetResolver

Discovery = {}

---@type { coords: vector3, distance: number, kind: string, entity: number?, entityType: number?, model: number?, zone: table? }[]
Discovery.points = {}

local lastRun = 0

-- Entity type identifiers: map entity types to pool array indices
local PED, VEHICLE, OBJECT = 1, 2, 3

---Calculate entity anchor point: compute center of model bounding box.
---@return vector3
function Discovery.entityAnchor(entity, model)
  local coords = GetEntityCoords(entity)

  if model then
    local ok, minimum, maximum = pcall(GetModelDimensions, model)
    if ok and minimum and maximum then
      local mid = (minimum.z + maximum.z) * 0.5
      local anchored = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, mid)
      if anchored then coords = anchored end
    end
  end

  local lift = Config.Render.anchorLift or 0.0
  if lift ~= 0.0 then coords = coords + vec3(0.0, 0.0, lift) end
  return coords
end

-- Reusable pass context: preallocate context table to minimize garbage collection
local ctx = {
  distance = 0,
  entity = nil,
  coords = nil,
  player = nil,
  policy = nil,
  menu = nil,
}

local function beginPass()
  ctx.player = Player.state()
  ctx.policy = Config.Options
end

---Populate probe context: set distance, entity handle, and world coordinates.
local function probe(distance, entity, coords)
  ctx.distance = distance
  ctx.entity = entity
  ctx.coords = coords
  return ctx
end

-- Pool requirements: track which game pools require scanning based on registered models
local modelClass = {}
local needsPool = { false, false, false }
local unknownModels = false
local classVersion = -1

---@return number? class
local function classify(model)
  local class = modelClass[model]
  if class then return class end

  if IsModelAPed(model) then
    class = PED
  elseif IsModelAVehicle(model) then
    class = VEHICLE
  elseif IsModelValid(model) then
    class = OBJECT
  end

  modelClass[model] = class
  return class
end

---Update pool scan requirements: check registered model types to determine required entity pools.
local function refreshPoolNeeds()
  if classVersion == Store.modelsVersion and not unknownModels then return end
  classVersion = Store.modelsVersion

  needsPool[PED], needsPool[VEHICLE], needsPool[OBJECT] = false, false, false
  unknownModels = false

  for model in pairs(Store.models) do
    local class = classify(model)
    if class then
      needsPool[class] = true
    else
      unknownModels = true
    end
  end
end

-- Pool scan cache: cache nearby pool entity handles within padded radius
local POOL_NAMES = { 'CPed', 'CVehicle', 'CObject' }
local POOL_BUCKETS = { Store.peds, Store.vehicles, Store.objects }

-- Pool scan order: prioritize objects, peds, and vehicles
local SCAN_ORDER = { OBJECT, PED, VEHICLE }

local shortlist = {}
local shortlistCount = 0

local scanAt = 0
local scanOrigin = nil
local scanRadius = 0
local scanModelsVersion = -1
local scanGlobalsCount = -1

local function globalsCount()
  return #Store.peds + #Store.vehicles + #Store.objects
end

local function rescanPools(origin, radius)
  shortlistCount = 0
  scanAt = GetGameTimer()
  scanOrigin = origin
  scanRadius = radius
  scanModelsVersion = Store.modelsVersion
  scanGlobalsCount = globalsCount()

  local globals = Config.Indicators.includeGlobals
  if not next(Store.models) and not globals then return end

  refreshPoolNeeds()

  local models = Store.models
  local self = cache.ped
  local limit = radius * radius

  for i = 1, #SCAN_ORDER do
    local class = SCAN_ORDER[i]
    local wantsClass = globals and #POOL_BUCKETS[class] > 0

    if wantsClass or unknownModels or needsPool[class] then
      local entities = GetGamePool(POOL_NAMES[class])

      for j = 1, #entities do
        local entity = entities[j]

        if entity ~= self and not (class == PED and IsPedAPlayer(entity)) then
          local coords = GetEntityCoords(entity)
          local dx, dy, dz = coords.x - origin.x, coords.y - origin.y, coords.z - origin.z

          if dx * dx + dy * dy + dz * dz <= limit then
            local model = GetEntityModel(entity)
            local registered = models[model] ~= nil

            if registered or wantsClass then
              -- Cache observed model class: record entity type for model hash
              if registered then modelClass[model] = class end

              shortlistCount = shortlistCount + 1
              local slot = shortlist[shortlistCount]
              if not slot then
                slot = {}
                shortlist[shortlistCount] = slot
              end
              slot.entity, slot.model, slot.entityType = entity, model, class
            end
          end
        end
      end
    end
  end
end

local function ensureShortlist(origin, radius, force)
  local settings = Config.Indicators

  if not force and scanOrigin
    and scanModelsVersion == Store.modelsVersion
    and scanGlobalsCount == globalsCount()
    and GetGameTimer() - scanAt < (settings.scanInterval or 1000)
  then
    -- Validate pool cache: check if player has moved beyond scan slack threshold
    local slack = scanRadius - radius
    if slack > 0.0 then
      local dx, dy, dz = origin.x - scanOrigin.x, origin.y - scanOrigin.y, origin.z - scanOrigin.z
      if dx * dx + dy * dy + dz * dz <= slack * slack then return end
    end
  end

  rescanPools(origin, radius + (settings.scanSlack or 6.0))
end

local gathered = {}
local gatheredCount = 0

local order = {}
local orderCount = 0

local function gather(kind, distance, coords, entity, entityType, model, zone)
  gatheredCount = gatheredCount + 1

  local slot = gathered[gatheredCount]
  if not slot then
    slot = {}
    gathered[gatheredCount] = slot
  end

  slot.kind, slot.distance, slot.coords = kind, distance, coords
  slot.entity, slot.entityType, slot.model, slot.zone = entity, entityType, model, zone
end

local function gatherZones(origin, radius)
  local nearby = lib.zones.getNearbyZones()

  for i = 1, #nearby do
    local zone = nearby[i]
    if zone.osmTarget and zone.options and #zone.options > 0 then
      local distance = #(origin - zone.coords)
      if distance <= radius then
        gather('zone', distance, zone.coords, nil, nil, nil, zone)
      end
    end
  end
end

local function considerRegistered(origin, radius, seen, entity)
  if not entity or entity == 0 or seen[entity] then return end
  if not DoesEntityExist(entity) then return end
  seen[entity] = true

  local coords = GetEntityCoords(entity)
  local distance = #(origin - coords)
  if distance > radius then return end

  gather('entity', distance, coords, entity, nil, nil, nil)
end

local function gatherRegistered(origin, radius, seen)
  for handle in pairs(Store.localEntities) do
    considerRegistered(origin, radius, seen, handle)
  end

  for netId in pairs(Store.entities) do
    if NetworkDoesNetworkIdExist(netId) then
      considerRegistered(origin, radius, seen, NetworkGetEntityFromNetworkId(netId))
    end
  end
end

local function gatherShortlisted(origin, radius, seen)
  local limit = radius * radius

  for i = 1, shortlistCount do
    local slot = shortlist[i]
    local entity = slot.entity

    if not seen[entity] and DoesEntityExist(entity) then
      local coords = GetEntityCoords(entity)
      local dx, dy, dz = coords.x - origin.x, coords.y - origin.y, coords.z - origin.z
      local squared = dx * dx + dy * dy + dz * dz

      if squared <= limit then
        seen[entity] = true
        gather('model', math.sqrt(squared), coords, entity, slot.entityType, slot.model, nil)
      end
    end
  end
end

local boneEntity = 0

---Resolve bone world position: check entity bones and return first matching bone position.
local function boneAnchor(option)
  local bones = option.bones
  if not bones then return nil end
  if type(bones) == 'string' then bones = { bones } end

  for i = 1, #bones do
    local boneId = GetEntityBoneIndexByName(boneEntity, bones[i])
    if boneId ~= -1 then
      return GetWorldPositionOfEntityBone(boneEntity, boneId)
    end
  end

  return nil
end

---@return vector3? anchor
local function accept(slot)
  local distance = slot.distance

  if slot.kind == 'zone' then
    local zone = slot.zone
    local candidates = Store.candidatesForZone(zone, distance)
    if Resolver.hasAny(candidates, probe(distance, nil, zone.coords)) then
      return zone.coords
    end
    return nil
  end

  local entity = slot.entity
  local entityType = slot.entityType or GetEntityType(entity)
  local model = slot.model or GetEntityModel(entity)
  slot.entityType, slot.model = entityType, model

  local candidates = Store.candidatesForEntity(entity, entityType, model, distance,
    not Config.Indicators.includeGlobals)
  if #candidates == 0 then return nil end

  boneEntity = entity
  local any, bone = Resolver.eachVisible(candidates, probe(distance, entity, slot.coords), boneAnchor)
  if not any then return nil end

  return bone or Discovery.entityAnchor(entity, model)
end

local function nearest(a, b) return a.distance < b.distance end

---Run discovery pass: evaluate nearby points and populate visible indicator list.
function Discovery.run(force)
  local settings = Config.Indicators
  if not settings.enabled then
    Discovery.points = {}
    return Discovery.points
  end

  local now = GetGameTimer()
  if not force and now - lastRun < settings.discoveryInterval then
    return Discovery.points
  end
  lastRun = now

  beginPass()

  local origin = GetEntityCoords(cache.ped)
  local radius = settings.radius
  local seen = {}

  gatheredCount = 0
  gatherZones(origin, radius)
  gatherRegistered(origin, radius, seen)
  ensureShortlist(origin, radius, force)
  gatherShortlisted(origin, radius, seen)

  local count = gatheredCount
  for i = 1, count do order[i] = gathered[i] end
  for i = count + 1, orderCount do order[i] = nil end
  orderCount = count
  table.sort(order, nearest)

  -- Cap visible points: limit visible indicators to frame rendering budget
  local cap = math.min(settings.cap, 24)
  local points = {}
  local kept = 0

  for i = 1, count do
    if kept >= cap then break end

    local slot = order[i]
    local anchorCoords = accept(slot)

    if anchorCoords then
      kept = kept + 1
      points[kept] = {
        coords = anchorCoords,
        distance = slot.distance,
        kind = slot.kind,
        entity = slot.entity,
        entityType = slot.entityType,
        model = slot.model,
        zone = slot.zone,
      }
    end
  end

  Discovery.points = points
  return points
end

function Discovery.clear()
  Discovery.points = {}
  lastRun = 0
  shortlistCount = 0
  scanOrigin = nil
end
