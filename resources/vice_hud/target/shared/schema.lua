local Schema = {}

Schema.DIALECTS = { ox = 'ox', qb = 'qb', qtarget = 'qtarget' }

-- Reserved schema keys: protect internal option properties from caller override
Schema.RESERVED = {
  label = true, description = true, name = true,
  icon = true, iconColor = true, badges = true,
  distance = true,

  groups = true, gangs = true, items = true, anyItem = true, citizenid = true,
  excludeGroups = true, excludeGangs = true,
  jobTypes = true, excludeJobTypes = true,

  bones = true, offset = true, offsetSize = true, absoluteOffset = true,

  canInteract = true, hideWhenIneligible = true,

  onSelect = true, export = true, event = true, serverEvent = true,
  command = true, qbCommand = true, openMenu = true, menuName = true,

  order = true, index = true, resource = true,
  dialect = true, qb = true, qtarget = true,
}

---Best-effort source location of the code that called into osm-target, so a
---warning about a bad registration can point at the line that made it rather
---than at osm-target's own internals.
---
---FORMAT_STACK_TRACE is an internal native with no documented output shape, so
---every step here is treated as optional: if anything about it looks different
---than expected the location is simply omitted, and the warning still names
---the resource. It must never be the reason a warning fails to print.
---@return string?
local function callSite()
  local ok, trace = pcall(function()
    return Citizen.InvokeNative(`FORMAT_STACK_TRACE` & 0xFFFFFFFF, nil, 0, Citizen.ResultAsString())
  end)

  if not ok or type(trace) ~= 'string' then return nil end

  local here = GetCurrentResourceName()

  -- The frames above the caller are osm-target's own, so the first one naming
  -- a file outside this resource is the one worth reporting.
  for line in trace:gmatch('[^\r\n]+') do
    local src = line:match('([%w%-_%./@]+%.lua:%d+)')
    if src and not src:find(here, 1, true) then return src end
  end

  return nil
end

---Warn about a caller's mistake, attributed to the caller.
---
---Entirely wrapped: this runs inside registration calls made by other
---resources, and a diagnostic must never be the reason one of those throws.
function Schema.warn(message)
  pcall(function()
    local where = callSite()
    lib.print.warn(where and ('%s (%s)'):format(message, where) or message)
  end)
end

---Determine table structure type: distinguish array, hash, empty, and nil.
---@return 'array' | 'hash' | 'empty' | 'nil'
function Schema.tableType(t)
  if type(t) ~= 'table' then return 'nil' end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return 'empty' end
  return #t == n and 'array' or 'hash'
end

function Schema.isArray(t)
  return Schema.tableType(t) == 'array'
end

---Whether a value can actually be called.
---
---`type(v) == 'function'` is NOT sufficient: a callback handed over a resource
---boundary (`exports['osm-target']:addBoxZone{ options = { onSelect = fn } }`)
---arrives as a funcref -- a table carrying the reference with a `__call`
---metamethod -- so a plain type check silently drops every cross-resource
---callback. ox_lib makes the same distinction in its own callback layer.
---
---Bare truthiness is the other failure mode: `action = 'something'` would then
---be installed as `onSelect` and throw when clicked, masking a perfectly good
---`event` on the same option. Both cases have to be excluded.
---@return boolean
function Schema.callable(v)
  if type(v) == 'function' then return true end
  if type(v) ~= 'table' then return false end
  local mt = getmetatable(v)
  return mt ~= nil and mt.__call ~= nil
end

---Normalize gate entries: convert string, array, or map into structured entry list.
---@return { name: string, value: number? }[]
function Schema.gateEntries(gate)
  local out = {}
  local t = type(gate)

  if t == 'string' then
    out[1] = { name = gate }
  elseif t == 'table' then
    if Schema.isArray(gate) then
      for i = 1, #gate do
        local v = gate[i]
        if type(v) == 'string' then out[#out + 1] = { name = v } end
      end
    else
      for k, v in pairs(gate) do
        if type(k) == 'string' then
          out[#out + 1] = { name = k, value = type(v) == 'number' and v or nil }
        elseif type(v) == 'string' then
          out[#out + 1] = { name = v }
        end
      end
      -- Sort gate entries: ensure deterministic reason string output
      table.sort(out, function(a, b) return a.name < b.name end)
    end
  end

  return out
end

---Check gate membership: determine if gate declarations match the specified identifier.
---@return boolean
function Schema.gateNames(gate, value)
  if value == nil then return false end
  local entries = Schema.gateEntries(gate)
  for i = 1, #entries do
    if entries[i].name == value then return true end
  end
  return false
end

---Prettify identifier: format snake_case or camelCase names into title case.
function Schema.prettify(name)
  if type(name) ~= 'string' or name == '' then return tostring(name) end
  local words = {}
  for word in name:gmatch('[^%s_%-]+') do
    words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2)
  end
  return #words > 0 and table.concat(words, ' ') or name
end

---Format name list: join names with commas and append overflow count when exceeding limit.
function Schema.joinNames(names, limit)
  limit = limit or 3
  local n = #names
  if n == 0 then return '' end
  if n <= limit then return table.concat(names, ', ') end
  local head = {}
  for i = 1, limit do head[i] = names[i] end
  return table.concat(head, ', ') .. ' +' .. tostring(n - limit)
end

function Schema.deepCopy(value)
  if type(value) ~= 'table' then return value end
  -- Callables are copied by reference: a funcref is a table, but recursing into
  -- it would yield a dead `{ __data = ... }` husk with no metatable.
  if Schema.callable(value) then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = Schema.deepCopy(v) end
  return out
end

OsmTargetSchema = Schema
return Schema
