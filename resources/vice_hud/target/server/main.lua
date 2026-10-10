local Designs = OsmTargetDesigns

-- Surfaced on the server console as well as each client's, because the server
-- owner is the one who can actually fix an out-of-date ox_lib. See
-- client/main.lua for why this is a hard requirement rather than a warning.
lib.checkDependency('ox_lib', '3.30.0', true)

local function denied(source)
  Bridge.Notify(source, Locale('admin_no_perm'), 'error')
end

RegisterCommand(Config.Commands.admin, function(source)
  if source == 0 then
    return print(Locale('admin_ingame_only', Config.Commands.admin))
  end

  if not Bridge.IsAdmin(source, Config.Commands.admin) then return denied(source) end

  local config = ConfigStore.get()
  if not config then return Bridge.Notify(source, Locale('admin_loading'), 'error') end

  TriggerClientEvent('osm-target:cl:openAdmin', source, config)
end, false)

RegisterCommand(Config.Commands.debug, function(source, args)
  if source == 0 then return print(Locale('admin_ingame_only', Config.Commands.debug)) end
  if not Bridge.IsAdmin(source, Config.Commands.debug) then return denied(source) end

  local enabled = args[1] ~= 'off'
  TriggerClientEvent('osm-target:cl:setDebug', source, enabled)
end, false)

---Test subject command: spawn test ped for UI verification.
RegisterCommand(Config.Commands.test, function(source, args)
  if source == 0 then return print(Locale('admin_ingame_only', Config.Commands.test)) end
  if not Bridge.IsAdmin(source, Config.Commands.test) then return denied(source) end

  TriggerClientEvent('osm-target:cl:testSubject', source, args[1] ~= 'off', args[1])
end, false)

RegisterNetEvent('osm-target:sv:saveConfig', function(payload)
  local source = source
  if not Bridge.IsAdmin(source, Config.Commands.admin) then return denied(source) end
  if type(payload) ~= 'table' then return end

  ConfigStore.save(payload, GetPlayerName(source) or tostring(source))
  Bridge.Notify(source, Locale('admin_saved'), 'success')
end)

RegisterNetEvent('osm-target:sv:revertDesign', function(designId)
  local source = source
  if not Bridge.IsAdmin(source, Config.Commands.admin) then return denied(source) end
  if not Designs.exists(designId) then return end

  ConfigStore.revertDesign(designId, GetPlayerName(source) or tostring(source))
  Bridge.Notify(source, Locale('admin_reverted'), 'success')
  TriggerClientEvent('osm-target:cl:openAdmin', source, ConfigStore.get())
end)

RegisterNetEvent('osm-target:sv:importConfig', function(blob)
  local source = source
  if not Bridge.IsAdmin(source, Config.Commands.admin) then return denied(source) end
  if type(blob) ~= 'string' or #blob > 262144 then
    return Bridge.Notify(source, Locale('admin_import_failed'), 'error')
  end

  local ok, decoded = pcall(json.decode, blob)
  if not ok or type(decoded) ~= 'table' then
    return Bridge.Notify(source, Locale('admin_import_failed'), 'error')
  end

  ConfigStore.save(decoded, ('import by %s'):format(GetPlayerName(source) or source))
  Bridge.Notify(source, Locale('admin_imported'), 'success')
  TriggerClientEvent('osm-target:cl:openAdmin', source, ConfigStore.get())
end)

exports('GetConfig', function()
  return ConfigStore.get()
end)

exports('GetDesigns', function()
  return Designs.manifest()
end)

-- Statebag compatibility: sync entity target option statebag
RegisterNetEvent('ox_target:setEntityHasOptions', function(netId)
  local entity = NetworkGetEntityFromNetworkId(netId)
  if entity and entity ~= 0 then
    Entity(entity).state:set('hasTargetOptions', true, true)
  end
end)

-- Relay vehicle door event: route door toggle request to network entity owner (ox_target parity)
RegisterNetEvent('ox_target:toggleEntityDoor', function(netId, door)
  local entity = NetworkGetEntityFromNetworkId(netId)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return end

  local owner = NetworkGetEntityOwner(entity)
  if owner and owner ~= -1 then
    TriggerClientEvent('ox_target:toggleEntityDoor', owner, netId, door)
  end
end)
