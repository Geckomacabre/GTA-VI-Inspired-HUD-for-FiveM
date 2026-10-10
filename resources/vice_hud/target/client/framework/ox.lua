-- ox_core client framework adapter
if Bridge.Framework ~= 'ox' then return end

local player

local function getPlayer()
  if player then return player end
  local ok, result = pcall(function()
    return exports.ox_core:GetPlayer()
  end)
  player = ok and result or nil
  return player
end

---Query player groups: retrieve group map from ox_core player object.
function Adapter.GetGroups()
  local p = getPlayer()
  if not p then return {} end

  local ok, groups = pcall(function()
    if p.getGroups then return p.getGroups() end
    if p.get then return p.get('groups') end
    return p.groups
  end)

  return (ok and type(groups) == 'table') and groups or {}
end

-- Gang alias: return groups as ox_core treats gangs as groups
function Adapter.GetGangs() return Adapter.GetGroups() end

function Adapter.GetCitizenId()
  local p = getPlayer()
  if not p then return nil end
  local ok, id = pcall(function()
    return p.stateId or (p.get and p.get('stateId')) or p.charId
  end)
  return ok and id or nil
end

-- Item count fallback: handled via ox_inventory in init.lua
function Adapter.GetItemCount(_name) return nil end
function Adapter.GetGroupLabel(_name) return nil end
function Adapter.GetItemLabel(_name) return nil end

function Adapter.Notify(message, kind)
  exports.ox_lib:notify({ description = message, type = kind or 'inform' })
end

local function invalidate()
  player = nil
  Bridge.InvalidatePlayerState()
end

RegisterNetEvent('ox:playerLoaded', invalidate)
RegisterNetEvent('ox:setGroup', invalidate)
RegisterNetEvent('ox:playerLogout', invalidate)
AddEventHandler('ox_inventory:itemCount', invalidate)

Bridge.Ready = true
