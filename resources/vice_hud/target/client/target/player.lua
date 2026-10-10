Player = {}

local TTL = 3000

local groups, gangs, citizenid, jobType
local itemCounts = {}
local expiry = 0

local function rebuild()
  groups = Bridge.GetGroups() or {}
  gangs = Bridge.GetGangs() or {}
  citizenid = Bridge.GetCitizenId()
  jobType = Bridge.GetJobType()
  expiry = GetGameTimer() + TTL
end

function Bridge.InvalidatePlayerState()
  expiry = 0
  itemCounts = {}
end

local function ensure()
  if not groups or GetGameTimer() > expiry then rebuild() end
end

---Query item count: check cached count or query inventory provider.
local function itemCount(name)
  local cached = itemCounts[name]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end

  local count = Bridge.GetItemCount(name)
  itemCounts[name] = count == nil and false or count
  return count
end

function Player.state()
  ensure()
  return {
    groups = groups,
    gangs = gangs,
    citizenid = citizenid,
    jobType = jobType,
    items = itemCount,
    groupLabel = Bridge.GetGroupLabel,
    itemLabel = Bridge.GetItemLabel,
  }
end

---Refresh cached player state: invalidate cache and fetch latest framework data.
function Player.refresh()
  Bridge.InvalidatePlayerState()
  ensure()
end
