Nui = {}

local adminOpen = false
local prefsOpen = false

-- The screen-space page (admin panel, preferences, sound) is a frame inside
-- vice_hud's own page now, since a resource has one ui_page. The HUD page
-- hands anything under 'target:nui' straight to that frame.
local function send(action, data)
  SendNUIMessage({ action = 'target:nui', payload = { action = action, data = data } })
end

-- Xbox or PlayStation buttons is one setting for the whole HUD (ViceGlyphs,
-- client_glyphs.lua: Config.PadGlyphs, /hudpad). The rail reads it as
-- prefs.padBrand, and its own preferences panel writes it back.
local function padBrand()
  return ViceGlyphs.padStyle() == 'ps' and 'playstation' or 'xbox'
end

ViceGlyphs.onPadStyle(function()
  Appearance.prefs.padBrand = padBrand()
  if Surfaces.isReady() then Surfaces.applyAppearance() end
end)

---@param name 'sweep'|'magnetise'|'scroll'|'confirm'|'reject'|'cancel'
function Nui.sfx(name)
  if Appearance.prefs.muted then return end
  send('sfx', { name = name })
end

RegisterNetEvent('osm-target:cl:notify', function(message, kind)
  Bridge.Notify(message, kind)
end)

local function setFocus(enabled)
  SetNuiFocus(enabled, enabled)
  if enabled then Machine.abort() end
end

function Nui.closeAll()
  if adminOpen then
    adminOpen = false
    send('admin:close')
  end
  if prefsOpen then
    prefsOpen = false
    send('prefs:close')
  end
  setFocus(false)
end

RegisterNetEvent('osm-target:cl:openAdmin', function(payload)
  adminOpen = true
  setFocus(true)
  send('admin:open', {
    config = payload,
    designs = Appearance.designs,
    prefs = Appearance.prefs,
  })
end)

RegisterNUICallback('saveConfig', function(data, cb)
  TriggerServerEvent('osm-target:sv:saveConfig', data)
  cb(1)
end)

RegisterNUICallback('revertDesign', function(data, cb)
  TriggerServerEvent('osm-target:sv:revertDesign', data and data.design)
  cb(1)
end)

RegisterNUICallback('importConfig', function(data, cb)
  TriggerServerEvent('osm-target:sv:importConfig', data and data.blob)
  cb(1)
end)

---Live preview callback: update in-world DUI surfaces with unsaved preview settings.
RegisterNUICallback('previewAppearance', function(data, cb)
  if data and data.design then
    Appearance.design = data.design
    Appearance.tunables = data.tunables or Appearance.tunables
    Appearance.anchor = OsmTargetDesigns.anchorFor(Appearance.design, Appearance.tunables)
    Surfaces.applyAppearance()
  end
  cb(1)
end)

-- Player preferences: load accessibility settings from client KVP storage
local KVP_KEY = 'osm_target:prefs'

function Nui.loadPrefs()
  Appearance.prefs.padBrand = padBrand()
  local stored = GetResourceKvpString(KVP_KEY)
  if not stored then return end

  local ok, decoded = pcall(json.decode, stored)
  if not ok or type(decoded) ~= 'table' then return end

  Appearance.prefs.scale = tonumber(decoded.scale) or Appearance.prefs.scale
  Appearance.prefs.volume = tonumber(decoded.volume) or Appearance.prefs.volume
  Appearance.prefs.reducedMotion = decoded.reducedMotion and true or false
  Appearance.prefs.muted = decoded.muted and true or false
  Appearance.prefs.padBrand = padBrand()
end

local function savePrefs()
  SetResourceKvp(KVP_KEY, json.encode(Appearance.prefs))
end

RegisterNUICallback('savePrefs', function(data, cb)
  if type(data) == 'table' then
    if data.scale then Appearance.prefs.scale = math.max(50, math.min(200, tonumber(data.scale) or 100)) end
    if data.volume then Appearance.prefs.volume = math.max(0, math.min(100, tonumber(data.volume) or 70)) end
    if data.reducedMotion ~= nil then Appearance.prefs.reducedMotion = data.reducedMotion and true or false end
    if data.muted ~= nil then Appearance.prefs.muted = data.muted and true or false end
    if data.padBrand == 'xbox' or data.padBrand == 'playstation' then
      Appearance.prefs.padBrand = data.padBrand
      ViceGlyphs.setPadStyle(data.padBrand)
    end

    savePrefs()
    Surfaces.applyAppearance()
    Bridge.Notify(Locale('prefs_saved'), 'success')
  end
  cb(1)
end)

---Cancel preview: restore active stored configuration from server.
RegisterNUICallback('cancelPreview', function(_, cb)
  TriggerServerEvent('osm-target:sv:clientReady')
  cb(1)
end)

RegisterNUICallback('closeUI', function(_, cb)
  Nui.closeAll()
  cb(1)
end)

RegisterCommand(Config.Commands.prefs, function()
  prefsOpen = true
  setFocus(true)
  send('prefs:open', { prefs = Appearance.prefs })
end, false)

-- Handle escape key: close active admin or preferences dialog on ESC press
CreateThread(function()
  while true do
    if adminOpen or prefsOpen then
      DisableControlAction(0, 200, true)
      if IsDisabledControlJustPressed(0, 200) or IsControlJustPressed(0, 202) then
        Nui.closeAll()
      end
      Wait(0)
    else
      Wait(250)
    end
  end
end)
