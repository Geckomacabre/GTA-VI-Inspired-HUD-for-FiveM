local DIALECT = 'qtarget'
local RESOURCE = 'qtarget'

local exportList = {}

---Register export helper: bind qtarget export handler.
local function register(name, fn)
  exportList[name] = fn
  ExportAs(RESOURCE, name, fn)
end

local function ctxFor(distance, bones)
  return {
    resource = GetInvokingResource() or GetCurrentResourceName(),
    distance = distance or Config.Options.defaultDistance,
    bones = bones,
  }
end

local function unwrap(parameters, bones)
  parameters = parameters or {}
  local options = parameters.options or parameters
  return options, ctxFor(parameters.distance, bones)
end

local function toVec3(value)
  local kind = type(value)
  if kind == 'vector3' then return value end
  if kind == 'vector4' or kind == 'table' then
    return vec3(value[1] or value.x, value[2] or value.y, value[3] or value.z)
  end
  return value
end

local zonesByName = {}

local function trackZone(name, id)
  local list = zonesByName[name]
  if not list then
    list = {}
    zonesByName[name] = list
  end
  list[#list + 1] = id
  return { name = name, id = id }
end

register('AddCircleZone', function(name, center, radius, options, targetoptions)
  local raw, ctx = unwrap(targetoptions)
  local zone = Store.attachZone(lib.zones.sphere({
    name = name,
    coords = toVec3(center),
    radius = (radius or 1.0) + 0.0,
    debug = options and options.debugPoly,
  }), raw, DIALECT, ctx)
  return trackZone(name, zone.id)
end)

register('AddBoxZone', function(name, center, length, width, options, targetoptions)
  local raw, ctx = unwrap(targetoptions)
  center = toVec3(center)
  options = options or {}

  local minZ = options.minZ
  local maxZ = options.maxZ
  local z, thickness

  if options.useZ or not (minZ and maxZ) then
    z, thickness = center.z, options.useZ and 2.0 or 100.0
  else
    z, thickness = (minZ + maxZ) / 2, math.abs(maxZ - minZ)
  end

  local zone = Store.attachZone(lib.zones.box({
    name = name,
    coords = vec3(center.x, center.y, z),
    size = vec3(width or 2.0, length or 2.0, thickness),
    rotation = options.heading or 0,
    debug = options.debugPoly,
  }), raw, DIALECT, ctx)

  return trackZone(name, zone.id)
end)

register('AddPolyZone', function(name, points, options, targetoptions)
  local raw, ctx = unwrap(targetoptions)
  options = options or {}

  local minZ = options.minZ or 0.0
  local maxZ = options.maxZ or (minZ + 100.0)
  local thickness = math.abs(maxZ - minZ)
  local z = maxZ - thickness / 2

  local converted = {}
  for i = 1, #points do
    local point = points[i]
    converted[i] = vec3(point[1] or point.x, point[2] or point.y, z)
  end

  local zone = Store.attachZone(lib.zones.poly({
    name = name,
    points = converted,
    thickness = thickness,
    debug = options.debugPoly,
  }), raw, DIALECT, ctx)

  return trackZone(name, zone.id)
end)

register('AddComboZone', function(zones, options, targetoptions)
  local name = (options and options.name) or ('combo:' .. tostring(math.random(1, 1e9)))
  for i = 1, #(zones or {}) do
    local part = zones[i]
    if type(part) == 'table' and part.id then
      local zone = Store.zones[part.id]
      if zone then
        local raw, ctx = unwrap(targetoptions)
        zone.options = {}
        Store.add(zone.options, raw, DIALECT, ctx)
        trackZone(name, part.id)
      end
    end
  end
  return { name = name, ids = zonesByName[name] }
end)

register('AddEntityZone', function(name, entity, _options, targetoptions)
  local raw, ctx = unwrap(targetoptions)
  Store.addKeyed(Store.localEntities, entity, raw, DIALECT, ctx)
  return { name = name, entity = entity }
end)

register('RemoveZone', function(id)
  if type(id) == 'number' then
    Store.removeZone(id)
    return
  end

  local ids = zonesByName[id]
  if ids then
    for i = 1, #ids do Store.removeZone(ids[i]) end
    zonesByName[id] = nil
    return
  end

  local found = Store.findZonesByName(id)
  for i = 1, #found do Store.removeZone(found[i].id) end
end)

register('AddTargetBone', function(bones, parameters)
  if type(bones) ~= 'table' then bones = { bones } end
  local raw, ctx = unwrap(parameters, bones)
  Store.add(Store.vehicles, raw, DIALECT, ctx)
end)

register('RemoveTargetBone', function(_bones, labels)
  Store.remove(Store.vehicles, labels, GetInvokingResource() or GetCurrentResourceName())
end)

register('AddTargetEntity', function(entities, parameters)
  if type(entities) ~= 'table' then entities = { entities } end
  local raw, ctx = unwrap(parameters)

  for i = 1, #entities do
    local entity = entities[i]
    if NetworkGetEntityIsNetworked(entity) then
      Store.addKeyed(Store.entities, NetworkGetNetworkIdFromEntity(entity), raw, DIALECT, ctx)
    else
      Store.addKeyed(Store.localEntities, entity, raw, DIALECT, ctx)
    end
  end
end)

register('RemoveTargetEntity', function(entities, labels)
  if type(entities) ~= 'table' then entities = { entities } end
  local resource = GetInvokingResource() or GetCurrentResourceName()

  for i = 1, #entities do
    local entity = entities[i]
    if NetworkGetEntityIsNetworked(entity) then
      Store.removeKeyed(Store.entities, NetworkGetNetworkIdFromEntity(entity), labels, resource)
    else
      Store.removeKeyed(Store.localEntities, entity, labels, resource)
    end
  end
end)

register('AddTargetModel', function(models, parameters)
  if type(models) ~= 'table' then models = { models } end
  local raw, ctx = unwrap(parameters)

  for i = 1, #models do
    local model = tonumber(models[i]) or joaat(models[i])
    Store.addKeyed(Store.models, model, raw, DIALECT, ctx)
  end
end)

register('RemoveTargetModel', function(models, labels)
  if type(models) ~= 'table' then models = { models } end
  local resource = GetInvokingResource() or GetCurrentResourceName()

  for i = 1, #models do
    local model = tonumber(models[i]) or joaat(models[i])
    Store.removeKeyed(Store.models, model, labels, resource)
  end
end)

local GLOBALS = {
  Ped = 'peds',
  Vehicle = 'vehicles',
  Object = 'objects',
  Player = 'players',
}

for suffix, field in pairs(GLOBALS) do
  register(suffix, function(parameters)
    local raw, ctx = unwrap(parameters)
    Store.add(Store[field], raw, DIALECT, ctx)
  end)

  register('Remove' .. suffix, function(labels)
    Store.remove(Store[field], labels, GetInvokingResource() or GetCurrentResourceName())
  end)

  register('Get' .. suffix, function(label)
    local bucket = Store[field]
    for i = 1, #bucket do
      if bucket[i].name == label or bucket[i].label == label then return bucket[i] end
    end
  end)

  register('Update' .. suffix, function(label, data)
    local bucket = Store[field]
    local normalised = OsmTargetCompat.normalise({ data }, DIALECT, ctxFor())
    if not normalised[1] then return end
    for i = 1, #bucket do
      if bucket[i].name == label or bucket[i].label == label then
        bucket[i] = normalised[1]
        return
      end
    end
    bucket[#bucket + 1] = normalised[1]
  end)
end

local TYPE_SUFFIX = { [1] = 'Ped', [2] = 'Vehicle', [3] = 'Object' }

register('GetType', function(entityType, label)
  local suffix = TYPE_SUFFIX[entityType]
  return suffix and exportList['Get' .. suffix](label) or nil
end)

register('UpdateType', function(entityType, label, data)
  local suffix = TYPE_SUFFIX[entityType]
  if suffix then exportList['Update' .. suffix](label, data) end
end)

local function findAny(bucket, label)
  if not bucket then return nil end
  for i = 1, #bucket do
    if bucket[i].name == label or bucket[i].label == label then return bucket[i] end
  end
end

register('GetZone', function(name) return zonesByName[name] end)
register('GetTargetBone', function(_bone, label) return findAny(Store.vehicles, label) end)
register('GetTargetEntity', function(entity, label)
  return findAny(Store.localEntities[entity] or Store.entities[entity], label)
end)
register('GetTargetModel', function(model, label)
  return findAny(Store.models[tonumber(model) or joaat(model)], label)
end)

register('UpdateZoneOptions', function(name, targetoptions)
  local ids = zonesByName[name]
  if not ids then return end
  local raw, ctx = unwrap(targetoptions)
  for i = 1, #ids do
    local zone = Store.zones[ids[i]]
    if zone then
      zone.options = {}
      Store.add(zone.options, raw, DIALECT, ctx)
    end
  end
end)

register('UpdateTargetBone', function(_bone, label, data)
  local normalised = OsmTargetCompat.normalise({ data }, DIALECT, ctxFor())
  if not normalised[1] then return end
  for i = 1, #Store.vehicles do
    if Store.vehicles[i].name == label then Store.vehicles[i] = normalised[1] return end
  end
  Store.vehicles[#Store.vehicles + 1] = normalised[1]
end)

register('UpdateTargetEntity', function(entity, label, data)
  local bucket = Store.localEntities[entity] or Store.entities[entity]
  if not bucket then return end
  local normalised = OsmTargetCompat.normalise({ data }, DIALECT, ctxFor())
  if not normalised[1] then return end
  for i = 1, #bucket do
    if bucket[i].name == label then bucket[i] = normalised[1] return end
  end
  bucket[#bucket + 1] = normalised[1]
end)

register('UpdateTargetModel', function(model, label, data)
  local bucket = Store.models[tonumber(model) or joaat(model)]
  if not bucket then return end
  local normalised = OsmTargetCompat.normalise({ data }, DIALECT, ctxFor())
  if not normalised[1] then return end
  for i = 1, #bucket do
    if bucket[i].name == label then bucket[i] = normalised[1] return end
  end
  bucket[#bucket + 1] = normalised[1]
end)

register('raycast', function(flag)
  local hit, entity, coords = lib.raycast.fromCamera(flag or 511, 4, Config.Interaction.raycastDistance)
  local distance = #(GetEntityCoords(cache.ped) - coords)
  local entityType = 0
  if entity and entity ~= 0 then
    local ok, result = pcall(GetEntityType, entity)
    entityType = ok and result or 0
  end
  return coords, distance, entity, entityType, hit
end)

register('DisableNUI', function() Machine.cancel() end)
register('LeaveTarget', function() Machine.cancel() end)
register('DisableTarget', function(force) if force ~= false then Machine.cancel() end end)
register('AllowTargeting', function(allow) Machine.setDisabled(not allow) end)
register('IsTargetActive', function() return Machine.isActive() end)
register('IsTargetSuccess', function() return Machine.hasMenu() end)
register('CheckEntity', function() end)

register('DrawOutlineEntity', function(entity, enable)
  if not entity or entity == 0 then return end
  SetEntityDrawOutline(entity, enable and true or false)
end)

register('CheckBones', function(coords, entity, boneList)
  return ClosestBone(coords, entity, boneList)
end)
