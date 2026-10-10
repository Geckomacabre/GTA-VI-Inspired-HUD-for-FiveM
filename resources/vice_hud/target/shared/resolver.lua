local Schema = OsmTargetSchema

local Resolver = {}

local EMPTY = {}

local function translator(ctx)
  local fn = ctx.locale or _G.Locale
  if fn then return fn end
  return function(key) return key end
end

local function itemCounter(player)
  local fn = player.items
  if type(fn) == 'function' then return fn end
  if type(fn) == 'table' then
    return function(name) return fn[name] or 0 end
  end
  -- Handle unmanaged inventory: treat items as available if inventory provider absent
  return nil
end

local function labeller(fn, fallback)
  if type(fn) == 'function' then
    return function(name)
      local label = fn(name)
      return (type(label) == 'string' and label ~= '') and label or fallback(name)
    end
  end
  return fallback
end

---@return boolean ok, string? reason
local function evalGroupGate(gate, owned, label, tr)
  local entries = Schema.gateEntries(gate)
  if #entries == 0 then return true end

  owned = owned or EMPTY

  local wrongGradeOnly = true
  local names = {}

  for i = 1, #entries do
    local entry = entries[i]

    -- Evaluate wildcard group: allow any job when 'all' is specified
    if entry.name == 'all' then return true end

    local grade = owned[entry.name]

    if grade ~= nil then
      if entry.value == nil or grade >= entry.value then return true end
    else
      wrongGradeOnly = false
    end

    names[#names + 1] = label(entry.name)
  end

  -- Format rank requirement: report required grade when group matches but grade is insufficient
  if #entries == 1 and wrongGradeOnly and entries[1].value then
    return false, tr('requires_group_grade', names[1], entries[1].value)
  end

  return false, tr('requires_group', Schema.joinNames(names))
end

---Evaluate group gate match: check player membership against gate criteria without reason formatting.
---@return boolean
local function matchesGroup(gate, owned)
  local entries = Schema.gateEntries(gate)
  if #entries == 0 then return false end

  owned = owned or EMPTY

  for i = 1, #entries do
    local entry = entries[i]
    if entry.name == 'all' then return true end

    local grade = owned[entry.name]
    if grade ~= nil and (entry.value == nil or grade >= entry.value) then
      return true
    end
  end

  return false
end

---Evaluate job-type gate match: verify player job type against gate requirements.
---@return boolean
local function matchesJobType(gate, jobType)
  if jobType == nil then return false end

  local entries = Schema.gateEntries(gate)
  for i = 1, #entries do
    local name = entries[i].name
    if name == 'all' or name == jobType then return true end
  end

  return false
end

---@return boolean ok, string? reason
local function evalItemGate(gate, anyItem, count, label, tr)
  local entries = Schema.gateEntries(gate)
  if #entries == 0 then return true end

  -- Bypass item check: treat items as available if item counter function is unavailable
  if not count then return true end

  local missing = {}
  local held = false

  for i = 1, #entries do
    local entry = entries[i]
    local need = entry.value or 1
    if (count(entry.name) or 0) >= need then
      held = true
    else
      missing[#missing + 1] = entry
    end
  end

  if anyItem then
    if held then return true end
    local names = {}
    for i = 1, #entries do names[i] = label(entries[i].name) end
    if #names == 2 then return false, tr('requires_items_any', names[1], names[2]) end
    return false, tr('requires_items_all', Schema.joinNames(names))
  end

  if #missing == 0 then return true end

  if #missing == 1 then
    local entry = missing[1]
    if entry.value and entry.value > 1 then
      return false, tr('requires_item_count', label(entry.name), entry.value)
    end
    return false, tr('requires_item', label(entry.name))
  end

  local names = {}
  for i = 1, #missing do names[i] = label(missing[i].name) end
  return false, tr('requires_items_all', Schema.joinNames(names))
end

---@return boolean ok
local function evalCitizenGate(gate, citizenid)
  if gate == nil then return true end
  if citizenid == nil then return false end
  local entries = Schema.gateEntries(gate)
  if #entries == 0 then return true end
  for i = 1, #entries do
    if entries[i].name == citizenid then return true end
  end
  return false
end

Resolver.OK = 'ok'          -- Option is eligible and actionable
Resolver.GATED = 'gated'    -- Option is ineligible with an explanatory reason
Resolver.HIDDEN = 'hidden'  -- Option is excluded from display

---Evaluate single option against active context.
---@return 'ok'|'gated'|'hidden' verdict, string? reason, number? bone
function Resolver.evaluate(option, ctx, distance)
  local tr = translator(ctx)
  local player = ctx.player or EMPTY
  local policy = ctx.policy or EMPTY

  -- Filter submenu options: exclude options belonging to a different submenu
  if option.menuName ~= ctx.menu then
    return Resolver.HIDDEN
  end

  distance = distance or ctx.distance or 0
  local maxDistance = option.distance or policy.defaultDistance or 7.0
  if distance > maxDistance then
    return Resolver.HIDDEN
  end

  -- Evaluate spatial attachment: verify bone or offset constraints via caller injection
  local bone
  if ctx.spatial and (option.bones or option.offset) then
    local ok, boneId = ctx.spatial(option)
    if not ok then return Resolver.HIDDEN end
    bone = boneId
  end

  -- Evaluate exclusion gates: hide option when player matches excluded groups or job types
  if option.excludeGroups and matchesGroup(option.excludeGroups, player.groups) then
    return Resolver.HIDDEN
  end

  if option.excludeGangs and matchesGroup(option.excludeGangs, player.gangs) then
    return Resolver.HIDDEN
  end

  if option.jobTypes and not matchesJobType(option.jobTypes, player.jobType) then
    return Resolver.HIDDEN
  end

  if option.excludeJobTypes and matchesJobType(option.excludeJobTypes, player.jobType) then
    return Resolver.HIDDEN
  end

  local showDisabled = policy.showDisabled ~= false
  local function gated(reason)
    if not showDisabled then return Resolver.HIDDEN end
    return Resolver.GATED, reason
  end

  -- Handle opaque refusal: check option visibility policy when reason is absent
  local function unexplained()
    local hide = option.hideWhenIneligible
    if hide == nil then hide = policy.hideUnexplained ~= false end
    if hide then return Resolver.HIDDEN end
    return gated(tr('not_eligible'))
  end

  local groupLabel = labeller(player.groupLabel, Schema.prettify)
  local itemLabel = labeller(player.itemLabel, Schema.prettify)

  -- Evaluate declarative gates: evaluate group and item requirements
  local gateReason

  local ok, reason = evalGroupGate(option.groups, player.groups, groupLabel, tr)

  -- Resolve ox group parity: verify gang or citizenid match when job evaluation fails
  if not ok
    and option.dialect ~= Schema.DIALECTS.qb
    and option.dialect ~= Schema.DIALECTS.qtarget
    and (matchesGroup(option.groups, player.gangs)
      or Schema.gateNames(option.groups, player.citizenid))
  then
    ok, reason = true, nil
  end

  if not ok then gateReason = reason end

  if not gateReason then
    ok, reason = evalGroupGate(option.gangs, player.gangs, groupLabel, tr)
    if not ok then gateReason = reason end
  end

  if not gateReason then
    ok, reason = evalItemGate(option.items, option.anyItem, itemCounter(player), itemLabel, tr)
    if not ok then gateReason = reason end
  end

  -- Early exit: skip predicate check if disabled options are hidden by policy
  if gateReason and not showDisabled then return Resolver.HIDDEN end

  if not evalCitizenGate(option.citizenid, player.citizenid) then
    return unexplained()
  end

  -- Execute canInteract predicate: validate target-specific interaction conditions
  if option.canInteract then
    local runner = ctx.interact
    local success, allowed, customReason

    if runner then
      success, allowed, customReason = true, runner(option, distance, bone)
    else
      success, allowed, customReason = pcall(option.canInteract,
        ctx.entity, distance, ctx.coords, option.name, bone)
      if not success then allowed = false end
    end

    if not allowed then
      if type(customReason) == 'string' and customReason ~= '' then
        return gated(customReason)
      end
      return unexplained()
    end
  end

  if gateReason then return gated(gateReason) end

  return Resolver.OK, nil, bone
end

---Unpack candidate structure: extract option table and specific distance.
---@return table option, number distance
local function unpackCandidate(candidate, ctx)
  if candidate.option ~= nil then
    return candidate.option, candidate.distance or ctx.distance or 0
  end
  return candidate, ctx.distance or 0
end

---Resolve a presentation field that may be computed from the target rather
---than fixed when the option was registered.
---
---Some text simply cannot be decided up front: the same lid is an engine cover
---on one car and a luggage compartment on the next, and a door reads "Lock" or
---"Unlock" depending on what it is doing right now. A plain string is returned
---untouched, so nothing about existing options changes; a function is called
---with the same arguments `canInteract` receives, so one closure can serve
---both.
---
---Failure is never fatal: a field that errors or returns something unusable
---resolves to nil and the caller decides what that means.
---@return string?
local function dynamicText(value, option, ctx, distance)
  if not Schema.callable(value) then return value end

  ctx = ctx or EMPTY
  local ok, text = pcall(value, ctx.entity, distance, ctx.coords, option.name)
  if not ok then return nil end

  return (type(text) == 'string' and text ~= '') and text or nil
end

---Resolve an option's display text.
---@return string? label nil when the option has nothing to show and should be hidden
function Resolver.label(option, ctx, distance)
  return dynamicText(option.label, option, ctx, distance)
end

---Resolve an option's icon, which swaps with the label when the label does.
---@return string?
function Resolver.icon(option, ctx, distance)
  return dynamicText(option.icon, option, ctx, distance)
end

---Resolve list of candidates into active option entries.
---@param candidates table[]
---@param ctx table
---@return table[] resolved
function Resolver.resolve(candidates, ctx)
  ctx = ctx or {}
  local policy = ctx.policy or EMPTY
  local focusDisabled = policy.focusDisabled ~= false
  local out = {}

  for i = 1, #candidates do
    local candidate = candidates[i]
    local option, distance = unpackCandidate(candidate, ctx)

    if type(option) == 'table' and option.label then
      local verdict, reason, bone = Resolver.evaluate(option, ctx, distance)

      if verdict ~= Resolver.HIDDEN then
        local label = Resolver.label(option, ctx, distance)
        local icon = Resolver.icon(option, ctx, distance)

        -- A callable label that declines to produce text means "nothing to say
        -- about this target", which is the same thing as not being here.
        if label then
          local enabled = verdict == Resolver.OK
          out[#out + 1] = {
            index = #out + 1,
            option = option,
            ref = candidate,
            enabled = enabled,
            reason = reason,
            focusable = enabled or focusDisabled,
            bone = bone,
            distance = distance,
            label = label,
            icon = icon,
          }
        end
      end
    end
  end

  return out
end

---Iterate visible options: walk candidates efficiently until predicate matches.
---@param fn fun(option: table): any?
---@return boolean any, any result
function Resolver.eachVisible(candidates, ctx, fn)
  ctx = ctx or {}
  local any = false

  for i = 1, #candidates do
    local option, distance = unpackCandidate(candidates[i], ctx)

    if type(option) == 'table' and option.label then
      if Resolver.evaluate(option, ctx, distance) ~= Resolver.HIDDEN then
        any = true
        if fn then
          local result = fn(option)
          if result ~= nil then return true, result end
        end
      end
    end
  end

  return any, nil
end

local function stop() return true end

---Check point eligibility: determine if target has at least one visible option.
---@return boolean
function Resolver.hasAny(candidates, ctx)
  return (Resolver.eachVisible(candidates, ctx, stop))
end

---Revalidate execution eligibility: ensure conditions remain valid at confirmation time.
---@return boolean allowed, string? reason
function Resolver.canExecute(option, ctx, distance)
  local verdict, reason = Resolver.evaluate(option, ctx, distance)
  return verdict == Resolver.OK, reason
end

---Format UI payload: map resolved options into client interface structure.
function Resolver.toPayload(resolved)
  local payload = {}
  for i = 1, #resolved do
    local entry = resolved[i]
    local option = entry.option
    payload[i] = {
      id = i,
      -- entry.label / entry.icon are the resolved values; the option's own
      -- fields may be functions of the target (see Resolver.label).
      label = entry.label or option.label,
      description = option.description,
      icon = entry.icon or option.icon,
      iconColor = option.iconColor,
      badges = option.badges,
      enabled = entry.enabled,
      reason = entry.reason,
      focusable = entry.focusable,
      submenu = option.openMenu ~= nil,
    }
  end
  return payload
end

OsmTargetResolver = Resolver
return Resolver
