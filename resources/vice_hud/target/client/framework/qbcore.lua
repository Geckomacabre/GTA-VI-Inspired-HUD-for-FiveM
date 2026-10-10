-- QBCore (qb-core) client framework adapter
if Bridge.Framework ~= 'qbcore' then return end

local QBCore = exports['qb-core']:GetCoreObject()

local function playerData()
  return QBCore.Functions.GetPlayerData()
end

---Extract group grade: parse numeric level or grade table value across framework forks.
local function gradeOf(value)
  local kind = type(value)
  if kind == 'number' then return value end
  if kind == 'table' then return tonumber(value.level or value.grade) or 0 end
  return 0
end

---Aggregate group grades: merge secondary and primary groups keeping highest grade for gate resolution.
local function collect(owned, primary)
  local out = {}

  if type(owned) == 'table' then
    for name, value in pairs(owned) do
      if type(name) == 'string' then out[name] = gradeOf(value) end
    end
  end

  if primary and primary.name then
    local grade = primary.grade and primary.grade.level or 0
    if not out[primary.name] or out[primary.name] < grade then
      out[primary.name] = grade
    end
  end

  return out
end

function Adapter.GetGroups()
  local data = playerData()
  if not data then return {} end
  return collect(data.jobs, data.job)
end

function Adapter.GetGangs()
  local data = playerData()
  if not data then return {} end
  return collect(data.gangs, data.gang)
end

function Adapter.GetCitizenId()
  local data = playerData()
  return data and data.citizenid or nil
end

function Adapter.GetJobType()
  local data = playerData()
  local job = data and data.job
  return job and job.type or nil
end

---Count inventory items: aggregate item quantity across player inventory slots.
function Adapter.GetItemCount(name)
  local data = playerData()
  local inventory = data and data.items
  if not inventory then return nil end

  local total = 0
  for _, slot in pairs(inventory) do
    if slot and slot.name == name then
      total = total + (slot.amount or slot.count or 0)
    end
  end
  return total
end

function Adapter.GetGroupLabel(name)
  local data = playerData()
  if data then
    if data.job and data.job.name == name then return data.job.label end
    if data.gang and data.gang.name == name then return data.gang.label end
  end
  local shared = QBCore.Shared
  if shared then
    if shared.Jobs and shared.Jobs[name] then return shared.Jobs[name].label end
    if shared.Gangs and shared.Gangs[name] then return shared.Gangs[name].label end
  end
  return nil
end

function Adapter.GetItemLabel(name)
  local items = QBCore.Shared and QBCore.Shared.Items
  local item = items and items[name]
  return item and (item.label or item.name) or nil
end

function Adapter.Notify(message, kind)
  QBCore.Functions.Notify(message, kind == 'inform' and 'primary' or kind)
end

---Character in-world state, as qbx_core/qb-core replicate it: the server sets
---`isLoggedIn` on the player statebag at spawn and clears it on drop, so this
---is false on the character-select and spawn screens where a target menu has
---nothing to act on.
function Adapter.IsPlayerLoaded()
  return LocalPlayer.state.isLoggedIn == true
end

-- Invalidate cache helper: call latest InvalidatePlayerState reference
local function invalidate() Bridge.InvalidatePlayerState() end

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', invalidate)
RegisterNetEvent('QBCore:Client:OnJobUpdate', invalidate)
RegisterNetEvent('QBCore:Client:OnGangUpdate', invalidate)
RegisterNetEvent('QBCore:Player:SetPlayerData', invalidate)
AddEventHandler('ox_inventory:itemCount', invalidate)

Bridge.Ready = true
