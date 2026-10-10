Bridge = {}
Bridge.Framework = nil
Bridge.Ready = false

---@class OsmTargetServerAdapter
Adapter = {
  ---@param source number
  ---@param message string
  ---@param kind 'inform'|'success'|'error'|'warning'
  Notify = function(_source, _message, _kind) end,
}

local function resourceStarted(name)
  return GetResourceState(name) == 'started'
end

local function detectFramework()
  if Config.Framework and Config.Framework ~= 'auto' then
    return Config.Framework
  end
  if resourceStarted('qbx_core') then return 'qbox' end
  if resourceStarted('qb-core') then return 'qbcore' end
  if resourceStarted('es_extended') then return 'esx' end
  if resourceStarted('ox_core') then return 'ox' end
  return 'standalone'
end

Bridge.Framework = detectFramework()

---Verify administrative permission: accept the dedicated ACE object or the
---standard per-command ACE (`command.<name>`) so either grant style works.
---@param source number
---@param command string? command name being authorised, when applicable
---@return boolean
function Bridge.IsAdmin(source, command)
  if source == 0 then return true end

  local player = tostring(source)
  if Config.AcePermission and IsPlayerAceAllowed(player, Config.AcePermission) then
    return true
  end

  return command ~= nil and IsPlayerAceAllowed(player, ('command.%s'):format(command))
end

function Bridge.Notify(source, message, kind)
  if not source or source == 0 then
    print(('[osm-target] %s'):format(message))
    return
  end
  Adapter.Notify(source, message, kind or 'inform')
end

CreateThread(function()
  local waited = 0
  while not Bridge.Ready and waited < 100 do
    Wait(100)
    waited = waited + 1
  end
  print(('[osm-target] Server framework: %s%s'):format(
    Bridge.Framework, Bridge.Ready and '' or ' (adapter not ready)'))
end)
