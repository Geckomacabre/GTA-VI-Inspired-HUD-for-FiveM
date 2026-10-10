Bridge = {}
Bridge.Framework = nil
Bridge.Ready = false

---Framework adapter interface: define required methods for framework compatibility.
---@class OsmTargetAdapter
Adapter = {
  ---@return table<string, number> job/group name -> grade
  GetGroups = function() return {} end,
  ---@return table<string, number> gang name -> grade
  GetGangs = function() return {} end,
  ---@return string? citizen / character identifier
  GetCitizenId = function() return nil end,
  ---@return string? qb-target job type ('leo', 'ems', ...) for jobType gates
  GetJobType = function() return nil end,
  ---@return string? name of the job the player is working right now, not every
  ---job they own -- GetGroups merges those, which is right for gates but would
  ---put a multi-job player in another job's Config.Layers focus mode
  GetJobName = function() return nil end,
  ---@return number count of an item in the player's inventory, or nil if unknown
  GetItemCount = function(_name) return nil end,
  ---@return string? display label for a group name
  GetGroupLabel = function(_name) return nil end,
  ---@return string? display label for an item name
  GetItemLabel = function(_name) return nil end,
  ---Whether the player's character is actually in the world and playable.
  ---Default is permissive on purpose: an adapter that has no reliable signal
  ---must not lock targeting out forever, so only adapters that can genuinely
  ---answer this override it.
  ---@return boolean
  IsPlayerLoaded = function() return true end,
  ---@param message string
  ---@param kind 'inform'|'success'|'error'|'warning'
  Notify = function(_message, _kind) end,
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

-- Query ox_inventory: check if ox_inventory resource is active
Bridge.UseOxInventory = resourceStarted('ox_inventory')

local oxItemLabels = {}

function Bridge.GetItemCount(name)
  if Bridge.UseOxInventory then
    local ok, count = pcall(function()
      return exports.ox_inventory:Search('count', name)
    end)
    if ok then return count or 0 end
  end
  return Adapter.GetItemCount(name)
end

function Bridge.GetItemLabel(name)
  if Bridge.UseOxInventory then
    if oxItemLabels[name] ~= nil then return oxItemLabels[name] or nil end
    local ok, item = pcall(function()
      return exports.ox_inventory:Items(name)
    end)
    local label = ok and item and item.label or false
    oxItemLabels[name] = label
    if label then return label end
  end
  return Adapter.GetItemLabel(name)
end

--- 'health'/'stamina'/'focus' categories for an item, derived from its own
--- client.export by ox_inventory's GetConsumableBadges export -- ox_inventory
--- specific (like the label cache above, no other Adapter knows what a
--- consumable even is), so nil outside it rather than a fake Adapter path.
function Bridge.GetConsumableBadges(name)
  if not Bridge.UseOxInventory then return nil end
  local ok, badges = pcall(function()
    return exports.ox_inventory:GetConsumableBadges(name)
  end)
  return ok and badges or nil
end

---Invalidate player cache: placeholder replaced by player module at startup.
function Bridge.InvalidatePlayerState() end

function Bridge.GetGroups()      return Adapter.GetGroups() or {} end
function Bridge.GetGangs()       return Adapter.GetGangs() or {} end
function Bridge.GetCitizenId()   return Adapter.GetCitizenId() end
function Bridge.GetJobType()     return Adapter.GetJobType() end
function Bridge.GetJobName()     return Adapter.GetJobName() end
function Bridge.GetGroupLabel(n) return Adapter.GetGroupLabel(n) end

---Whether targeting should be allowed at all yet. Never lets an adapter fault
---wedge the player out of interacting: anything other than an explicit `false`
---is treated as loaded.
function Bridge.IsPlayerLoaded()
  local ok, loaded = pcall(Adapter.IsPlayerLoaded)
  if not ok then return true end
  return loaded ~= false
end

---Dispatch notification: route message to active framework notification handler.
function Bridge.Notify(message, kind)
  Adapter.Notify(message, kind or 'inform')
end

CreateThread(function()
  local waited = 0
  while not Bridge.Ready and waited < 100 do
    Wait(100)
    waited = waited + 1
  end
  if not Bridge.Ready and Config.TargetDebug then
    print(('^3[osm-target] No client bridge adapter became ready for framework "%s"; running unfiltered.^7'):format(Bridge.Framework))
  end
end)
