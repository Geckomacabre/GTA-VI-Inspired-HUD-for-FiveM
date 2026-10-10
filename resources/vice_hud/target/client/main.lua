-- Hard dependency gate. osm-target is built on ox_lib's zones, raycast,
-- keybind and progress APIs, none of which fail loudly on their own -- an
-- ox_lib too old to provide them produces a resource that loads clean and then
-- silently does nothing. Checked here rather than at the top of the file list
-- because this is the script that registers the keybind: refusing to register
-- it leaves the player with no targeting and one clear line in console, which
-- is a far better failure than a dead key and no explanation.
local DEPENDENCY, MIN_VERSION = 'ox_lib', '3.30.0'

CreateThread(function()
  -- Initialize client state: wait for ox_lib point grid and cache readiness
  Wait(0)

  if not lib.checkDependency(DEPENDENCY, MIN_VERSION, true) then return end

  Nui.loadPrefs()
  Input.register()

  -- Pre-warm DUI surfaces: initialize browsers asynchronously in background
  SetTimeout(8000, function()
    if not Surfaces.isReady() then Surfaces.init() end
  end)

  -- Client console stays silent unless diagnostics are enabled in config.lua
  if Config.TargetDebug then
    print(('^2[osm-target] ready (framework: %s, design: %s)^7')
      :format(Bridge.Framework, Appearance.design))
  end
end)

-- Clean up runtime resources: destroy DUI instances and reset state on resource stop
AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end

  Machine.abort()
  Surfaces.destroy()
  SetNuiFocus(false, false)
end)

-- Invalidate cached player state: refresh player state on client resource start
AddEventHandler('onClientResourceStart', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  Bridge.InvalidatePlayerState()
end)
