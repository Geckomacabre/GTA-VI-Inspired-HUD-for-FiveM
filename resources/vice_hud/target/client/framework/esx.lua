-- ESX (es_extended) client framework adapter
if Bridge.Framework ~= 'esx' then return end

local ESX = exports.es_extended:getSharedObject()

-- Job keys: check primary job and secondary job2 properties
local JOB_KEYS = { 'job', 'job2' }

local function playerData()
  return ESX.PlayerData or ESX.GetPlayerData and ESX.GetPlayerData() or nil
end

function Adapter.GetGroups()
  local data = playerData()
  if not data then return {} end

  local groups = {}
  for i = 1, #JOB_KEYS do
    local job = data[JOB_KEYS[i]]
    if job and job.name then
      groups[job.name] = job.grade or 0
    end
  end
  return groups
end

-- Gang fallback: return empty map as ESX lacks native gang structure
function Adapter.GetGangs() return {} end

function Adapter.GetCitizenId()
  local data = playerData()
  return data and (data.identifier or data.citizenid) or nil
end

function Adapter.GetItemCount(name)
  local data = playerData()
  local inventory = data and data.inventory
  if not inventory then return nil end

  local total = 0
  for _, slot in pairs(inventory) do
    if slot and slot.name == name then
      total = total + (slot.count or slot.amount or 0)
    end
  end
  return total
end

function Adapter.GetGroupLabel(name)
  local data = playerData()
  if data then
    for i = 1, #JOB_KEYS do
      local job = data[JOB_KEYS[i]]
      if job and job.name == name then
        return job.label or job.grade_label
      end
    end
  end
  return nil
end

function Adapter.GetItemLabel(name)
  local ok, label = pcall(function()
    return ESX.GetItemLabel and ESX.GetItemLabel(name) or nil
  end)
  return ok and label or nil
end

function Adapter.Notify(message, kind)
  ESX.ShowNotification(message, kind)
end

local function invalidate() Bridge.InvalidatePlayerState() end

RegisterNetEvent('esx:playerLoaded', invalidate)
RegisterNetEvent('esx:setJob', invalidate)
RegisterNetEvent('esx:setJob2', invalidate)
RegisterNetEvent('esx:onPlayerLogout', invalidate)
RegisterNetEvent('esx:addInventoryItem', invalidate)
RegisterNetEvent('esx:removeInventoryItem', invalidate)
AddEventHandler('esx:setPlayerData', invalidate)
AddEventHandler('ox_inventory:itemCount', invalidate)

Bridge.Ready = true
