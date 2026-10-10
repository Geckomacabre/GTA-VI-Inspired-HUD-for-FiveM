local Schema = OsmTargetSchema

local DIALECT = 'ox'

Api = {}

---Register export handler: bind CFX export handler synchronously on chunk load.
function ExportAs(resourceName, exportName, fn)
  AddEventHandler(('__cfx_export_%s_%s'):format(resourceName, exportName), function(setCB)
    setCB(fn)
  end)
end

---Metatable proxy: publish functions automatically to global API and exports.
local api = setmetatable({}, {
  __newindex = function(self, key, value)
    rawset(self, key, value)
    rawset(Api, key, value)
    exports(key, value)
    ExportAs('ox_target', key, value)
  end,
})

local function ctxFor(distance)
  return { resource = GetInvokingResource() or GetCurrentResourceName(), distance = distance }
end

---Zones created with `debug = true` draw their outline permanently, for every
---player. It is the single most common thing left switched on by accident when
---a resource ships, and nothing else ever mentions it.
local function warnZoneDebug(data, ctx)
  if data.debug then
    Schema.warn(("%s created a zone with debug drawing enabled.")
      :format(ctx.resource or 'unknown'))
  end
end

local function zoneCtx(data)
  return {
    resource = data.resource or GetInvokingResource() or GetCurrentResourceName(),
    distance = data.distance,
  }
end

function api.addBoxZone(data)
  local ctx = zoneCtx(data)
  warnZoneDebug(data, ctx)
  local options = data.options
  data.options = nil
  return Store.attachZone(lib.zones.box(data), options, DIALECT, ctx).id
end

function api.addSphereZone(data)
  local ctx = zoneCtx(data)
  warnZoneDebug(data, ctx)
  local options = data.options
  data.options = nil
  return Store.attachZone(lib.zones.sphere(data), options, DIALECT, ctx).id
end

function api.addPolyZone(data)
  local ctx = zoneCtx(data)
  warnZoneDebug(data, ctx)
  local options = data.options
  data.options = nil
  return Store.attachZone(lib.zones.poly(data), options, DIALECT, ctx).id
end

---@param id number | string zone id, or the name it was registered with
function api.zoneExists(id)
  if type(id) == 'number' then return Store.zones[id] ~= nil end
  if type(id) == 'string' then return #Store.findZonesByName(id) > 0 end
  return false
end

---@param id number | string
---@param suppressWarning boolean?
function api.removeZone(id, suppressWarning)
  if type(id) == 'string' then
    local found = Store.findZonesByName(id)
    for i = 1, #found do Store.removeZone(found[i].id) end
    if #found > 0 then return end
  elseif Store.removeZone(id) then
    return
  end

  if not suppressWarning then
    lib.print.warn(('attempted to remove a zone that does not exist (id: %s)'):format(tostring(id)))
  end
end

function api.addGlobalOption(options)
  Store.add(Store.global, options, DIALECT, ctxFor())
end

function api.removeGlobalOption(options)
  Store.remove(Store.global, options, GetInvokingResource() or GetCurrentResourceName())
end

local GLOBAL_BUCKETS = {
  Ped = 'peds',
  Vehicle = 'vehicles',
  Object = 'objects',
  Player = 'players',
}

for suffix, field in pairs(GLOBAL_BUCKETS) do
  api['addGlobal' .. suffix] = function(options)
    Store.add(Store[field], options, DIALECT, ctxFor())
  end

  api['removeGlobal' .. suffix] = function(options)
    Store.remove(Store[field], options, GetInvokingResource() or GetCurrentResourceName())
  end
end

local function toArray(value)
  if type(value) ~= 'table' then return { value } end
  return value
end

function api.addModel(models, options)
  local ctx = ctxFor()
  models = toArray(models)
  for i = 1, #models do
    local model = tonumber(models[i]) or joaat(models[i])
    Store.addKeyed(Store.models, model, options, DIALECT, ctx)
  end
end

function api.removeModel(models, options)
  local resource = GetInvokingResource() or GetCurrentResourceName()
  models = toArray(models)
  for i = 1, #models do
    local model = tonumber(models[i]) or joaat(models[i])
    Store.removeKeyed(Store.models, model, options, resource)
  end
end

function api.addEntity(netIds, options)
  local ctx = ctxFor()
  netIds = toArray(netIds)

  for i = 1, #netIds do
    local netId = netIds[i]
    if NetworkDoesNetworkIdExist(netId) then
      local isNew = Store.entities[netId] == nil
      Store.addKeyed(Store.entities, netId, options, DIALECT, ctx)

      -- Sync entity statebag: notify server to set hasTargetOptions for ox_target watcher compatibility
      if isNew and Store.entities[netId] then
        local entity = NetworkGetEntityFromNetworkId(netId)
        if entity and entity ~= 0 and not Entity(entity).state.hasTargetOptions then
          TriggerServerEvent('ox_target:setEntityHasOptions', netId)
        end
      end
    end
  end
end

function api.removeEntity(netIds, options)
  local resource = GetInvokingResource() or GetCurrentResourceName()
  netIds = toArray(netIds)
  for i = 1, #netIds do
    Store.removeKeyed(Store.entities, netIds[i], options, resource)
  end
end

RegisterNetEvent('ox_target:removeEntity', function(netIds, options)
  local list = toArray(netIds)
  for i = 1, #list do
    Store.removeKeyed(Store.entities, list[i], options, nil)
  end
end)

function api.addLocalEntity(entities, options)
  local ctx = ctxFor()
  entities = toArray(entities)

  for i = 1, #entities do
    local handle = entities[i]
    if DoesEntityExist(handle) then
      Store.addKeyed(Store.localEntities, handle, options, DIALECT, ctx)
    else
      lib.print.warn(('No entity with id "%s" exists (from %s).'):format(tostring(handle), ctx.resource))
    end
  end
end

function api.removeLocalEntity(entities, options)
  local resource = GetInvokingResource() or GetCurrentResourceName()
  entities = toArray(entities)
  for i = 1, #entities do
    Store.removeKeyed(Store.localEntities, entities[i], options, resource)
  end
end

---Retrieve registered options: query options for specific entity or model.
function api.getTargetOptions(entity, entityType, model)
  if not entity then
    return {
      global = Store.global,
      peds = Store.peds,
      vehicles = Store.vehicles,
      objects = Store.objects,
      players = Store.players,
    }
  end

  if IsPedAPlayer(entity) then return { global = Store.players } end

  local netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or nil

  return {
    global = entityType == 1 and Store.peds or entityType == 2 and Store.vehicles or Store.objects,
    model = model and Store.models[model] or nil,
    entity = netId and Store.entities[netId] or nil,
    localEntity = Store.localEntities[entity],
  }
end

function api.disableTargeting(value)
  Machine.setDisabled(value and true or false)
end

function api.isActive()
  return Machine.isActive()
end
