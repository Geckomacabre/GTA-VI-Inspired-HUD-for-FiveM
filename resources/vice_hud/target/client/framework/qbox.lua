-- Qbox (qbx_core) client framework adapter
if Bridge.Framework ~= 'qbox' then return end

local function playerData()
  local ok, data = pcall(function() return exports.qbx_core:GetPlayerData() end)
  return ok and data or nil
end

---Aggregate group grades: merge player groups and gangs with active primary group to match qbx_core HasGroup resolution.
local function collect(owned, primary)
  local out = {}

  if type(owned) == 'table' then
    for name, grade in pairs(owned) do
      if type(name) == 'string' then out[name] = tonumber(grade) or 0 end
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

-- Item count fallback: handled via ox_inventory in init.lua
function Adapter.GetItemCount(_name) return nil end

function Adapter.GetGroupLabel(name)
  local data = playerData()
  if data then
    if data.job and data.job.name == name then return data.job.label end
    if data.gang and data.gang.name == name then return data.gang.label end
  end
  local ok, jobs = pcall(function() return exports.qbx_core:GetJobs() end)
  if ok and jobs and jobs[name] then return jobs[name].label end
  local okg, gangs = pcall(function() return exports.qbx_core:GetGangs() end)
  if okg and gangs and gangs[name] then return gangs[name].label end
  return nil
end

function Adapter.GetItemLabel(_name) return nil end

function Adapter.Notify(message, kind)
  exports.qbx_core:Notify(message, kind or 'inform')
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
