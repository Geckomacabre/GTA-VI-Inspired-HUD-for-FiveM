--[[ ── Walk-up prompts (Config.Proximity) ──────────────────────────────────
  Nothing is held, and nothing shows until the player walks up to something.
  Then whatever is within reach and in front of them shows
  what can be done with it, each option beside the key or button that does it,
  and pressing that does it.

  One target at a time: what the crosshair is on if it has anything to offer,
  otherwise the nearest interaction point inside the view cone. One option is
  a button and its name. More than one (Config.Proximity.maxDirect), or an
  option that leads to a submenu, is a button, three dots and a name -- the
  reference's FRIDGE -- and pressing it opens the full list on that target
  (Machine.open), closed by picking something, cancelling or walking away.
  The exception is a set of options that each have a key of their own in
  Config.Input.directKeyByName (Slim Jim and Smash Window): those stand side
  by side, each on its button, as the reference shows that pair.

  Peds are left to the targeting key unless Config.Proximity.peds says
  otherwise: a street full of them would light a prompt on every one that
  walked past. Vehicles show only the options named in
  Config.Input.directKeyByName by default, for the same reason and because the
  pad's interact button is also how a car is entered. An option can settle it
  for itself with `proximity = true` or `proximity = false`.

  The targeting key still works exactly as before and takes over while held.

  Drawn by vice_hud when it is running (exports.vice_hud:ShowWorldActions),
  because its buttons are the player's own key or pad button, redrawn when they
  change device. Without it the prompt is this resource's own design, as a
  direct prompt.
]]

Proximity = {}

local settings = Config.Proximity or {}

local shown = nil        -- { key, candidate, rows, signature, own } while a prompt is up
local quietUntil = 0     -- no prompt before this (one was just used)
local started = false
local loopId = 0         -- which frame loop is the live one

local rad, deg, acos, sqrt = math.rad, math.deg, math.acos, math.sqrt

local PED, VEHICLE = 1, 2

-- vice_hud has one world prompt, shared with any other script that uses it.
-- Naming ours means taking it down never takes down someone else's.
local OWNER = 'osm-target'

local function cameraBasis()
  local origin = GetFinalRenderedCamCoord()
  local rot = GetFinalRenderedCamRot(2)
  local pitch, yaw = rad(rot.x), rad(rot.z)
  local cosPitch = math.abs(math.cos(pitch))

  return origin, vec3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
end

local function angleTo(origin, forward, point)
  local dx, dy, dz = point.x - origin.x, point.y - origin.y, point.z - origin.z
  local length = sqrt(dx * dx + dy * dy + dz * dz)
  if length < 0.01 then return 0.0 end

  local dot = (dx * forward.x + dy * forward.y + dz * forward.z) / length
  if dot > 1.0 then dot = 1.0 elseif dot < -1.0 then dot = -1.0 end
  return deg(acos(dot))
end

---Whether an option may be offered without the targeting key.
---@return boolean
local function offered(option, candidate)
  if option.proximity == false then return false end
  if option.proximity == true then return true end
  if candidate.zone then return true end

  local kind = candidate.entityType
  if kind == PED then return settings.peds == true end

  if kind == VEHICLE then
    local vehicles = settings.vehicles
    if vehicles == true or vehicles == 'all' then return true end
    if vehicles == 'named' then
      local named = Config.Input.directKeyByName
      return named ~= nil and option.name ~= nil and named[option.name] ~= nil
    end
    return false
  end

  return true
end

Proximity.offered = offered

---What a candidate offers right now: the options of the part of it nearest the
---crosshair that can be used and may be shown without the key.
---@return table[]? entries, string? partKey
local function usable(candidate)
  local list = Hit.resolve(candidate, nil)
  if #list == 0 then return nil end

  local part = Hit.parts(candidate, list)[1]
  if not part then return nil end

  local entries = {}
  for i = 1, #part.entries do
    local entry = part.entries[i]
    if entry.enabled and offered(entry.option, candidate) then
      entries[#entries + 1] = entry
    end
  end

  if #entries == 0 then return nil end
  return entries, part.key
end

---Pick the one thing to prompt for.
---@return table? candidate, table[]? entries
local function find()
  local reach = settings.distance or 2.0
  local scan = Hit.scan()
  if not started then return nil end   -- Hit.scan yields

  -- What the crosshair is on.
  if scan.entity ~= 0 and scan.distance <= reach then
    local entries, part = usable(scan)
    if entries then
      scan.anchor = Hit.anchor(scan, entries)
      scan.key = ('%s:%s'):format(scan.entity, part or '')
      return scan, entries
    end
  end

  -- A zone the crosshair is inside.
  local pedCoords = GetEntityCoords(cache.ped)
  local zones = Store.zonesContaining(scan.coords)
  for i = 1, #zones do
    local zone = zones[i]
    local distance = #(pedCoords - zone.coords)

    if distance <= reach or scan.distance <= reach then
      local candidate = {
        entity = 0, entityType = 0, model = nil,
        coords = scan.coords, distance = distance, zone = zone,
      }
      local entries = usable(candidate)
      if entries then
        candidate.anchor = zone.coords
        candidate.key = 'zone:' .. tostring(zone.id)
        return candidate, entries
      end
    end
  end

  -- Otherwise the interaction point nearest the middle of the view. The one
  -- already showing is given a little slack on both limits, so standing on
  -- the edge of its reach or its cone does not flicker it.
  local origin, forward = cameraBasis()
  local cone = settings.angle or 30.0
  local points = Discovery.run(false, true)
  local keep = shown and shown.key
  local best, bestScore, bestKey

  for i = 1, #points do
    local point = points[i]
    local key = point.zone and ('zone:' .. tostring(point.zone.id)) or tostring(point.entity)
    local held = keep ~= nil and (keep == key or keep:sub(1, #key + 1) == key .. ':')
    local angle = angleTo(origin, forward, point.coords)

    if point.distance <= reach + (held and 0.4 or 0.0) and angle <= cone + (held and 8.0 or 0.0) then
      local score = angle - (held and 6.0 or 0.0)
      if not bestScore or score < bestScore then
        best, bestScore, bestKey = point, score, key
      end
    end
  end

  if not best then return nil end

  local candidate
  if best.kind == 'zone' then
    candidate = {
      entity = 0, entityType = 0, model = nil,
      coords = best.coords, distance = best.distance, zone = best.zone,
    }
  else
    candidate = {
      entity = best.entity, entityType = best.entityType, model = best.model,
      coords = best.coords, distance = best.distance,
    }
  end

  local entries, part = usable(candidate)
  if not entries then return nil end

  candidate.anchor = best.coords
  candidate.key = best.zone and bestKey or ('%s:%s'):format(bestKey, part or '')
  return candidate, entries
end

---First control of a key for the device in hand, or nil when it has none there.
local function control(key)
  local list = Input.controlsFor(key)
  if type(list) == 'table' then return list[1] end
  return list
end

---Give every option a key of its own: its named one (Config.Input.directKeyByName)
---where it has one, the next free one of the pool otherwise. nil when there are
---not enough to go round on this device.
---@return table[]? keys parallel to entries
local function assign(entries)
  local pool = settings.keys or {}
  local named = Config.Input.directKeyByName or {}
  local used, keys = {}, {}

  for i = 1, #entries do
    local key = named[entries[i].option.name]
    local id = key and control(key)
    if id and not used[id] then
      used[id] = true
      keys[i] = key
    end
  end

  local at = 1
  for i = 1, #entries do
    if not keys[i] then
      while pool[at] and (not control(pool[at]) or used[control(pool[at])]) do at = at + 1 end
      local key = pool[at]
      if not key then return nil end
      used[control(key)] = true
      keys[i] = key
      at = at + 1
    end
  end

  return keys
end

---Whether every one of several options has a key of its own by name.
local function allNamed(entries)
  if #entries < 2 then return false end
  local named = Config.Input.directKeyByName or {}
  for i = 1, #entries do
    local name = entries[i].option.name
    if not (name and named[name]) then return false end
  end
  return true
end

---The name a list goes by: what one of its options says the thing is
---(`targetName = 'Fridge'`), else the general word.
local function listName(entries)
  for i = 1, #entries do
    local name = entries[i].option.targetName
    if type(name) == 'string' and name ~= '' then return name end
  end
  return Locale('interact')
end

---The rows to draw: a row an option when there are few enough (one, by
---default) or each has its own named key, otherwise one row that opens the
---whole list.
local function build(entries)
  local pool = settings.keys or {}
  local most = math.min(settings.maxDirect or 1, #pool)
  local keys = (#entries <= most or allNamed(entries)) and assign(entries) or nil
  local rows = {}

  if keys then
    for i = 1, #entries do
      local entry = entries[i]
      rows[i] = {
        entry = entry,
        key = keys[i],
        label = entry.label or entry.option.label,
        more = entry.option.openMenu ~= nil,
      }
    end
    return rows
  end

  -- Several: one row that opens the list. (A single option only gets here
  -- with no key free for it, and keeps its own name.)
  local only = #entries == 1 and entries[1] or nil
  rows[1] = {
    entry = only,
    key = pool[1],
    label = only and (only.label or only.option.label) or listName(entries),
    more = true,
    list = only == nil,
  }
  return rows
end

Proximity.build = build

local function hudRunning()
  return GetResourceState('vice_hud') == 'started'
end

---Everything that would make the prompt on screen wrong if it changed: what it
---is on, the device in hand, who is drawing it, and each row.
local function signature(candidate, rows)
  local parts = { candidate.key, Input.usingPad() and 'pad' or 'kbm', hudRunning() and 'hud' or 'own' }
  for i = 1, #rows do
    local row = rows[i]
    parts[#parts + 1] = ('%s|%s|%s'):format(tostring(row.label), tostring(control(row.key)), row.more and 1 or 0)
  end
  return table.concat(parts, '\n')
end


-- ── drawing ────────────────────────────────────────────────────────────────

local function hide()
  if not shown then return end
  local was = shown
  shown = nil

  if was.own then
    Surfaces.send('menu', 'menu:close', {})
  else
    pcall(function() exports.vice_hud:HideWorldActions(OWNER) end)
  end
end

local function present(candidate, rows, sig)
  local own = not hudRunning()

  if shown and shown.own ~= own then hide() end

  if own then
    -- This resource's own design, as the direct prompt it already has.
    Surfaces.init()
    local payload = {}
    for i = 1, #rows do
      local row = rows[i]
      payload[i] = {
        id = i,
        label = row.label,
        icon = row.entry and (row.entry.icon or row.entry.option.icon) or nil,
        enabled = true,
        focusable = true,
        submenu = row.more,
        directKey = Input.keyLabel(row.key),
      }
    end
    Surfaces.send('menu', 'menu:open', { options = payload, focus = 1, empty = false, mode = 'direct' })
  else
    local options = {}
    for i = 1, #rows do
      local row = rows[i]
      options[i] = {
        label = row.label,
        key = control(row.key),
        more = row.more or nil,
        dot = row.entry and row.entry.option.dot or nil,
      }
    end
    local ok = pcall(function()
      exports.vice_hud:ShowWorldActions(options, candidate.anchor, { compact = false, centred = true, id = OWNER })
    end)
    if not ok then return end
  end

  local first = shown == nil
  shown = { key = candidate.key, candidate = candidate, rows = rows, signature = sig, own = own }
  return first
end

-- ── using a prompt ───────────────────────────────────────────────────────────

local function use(row)
  local candidate = shown.candidate
  quietUntil = GetGameTimer() + (settings.cooldown or 600)
  hide()

  local option = row.entry and row.entry.option
  if row.list or (option and option.openMenu) then
    local menu = option and option.openMenu or nil
    if menu == 'home' then menu = nil end
    Machine.open(candidate, menu)
    return
  end

  Machine.execute(candidate, row.entry)
end

---The game controls that share a physical button with the keys on screen, shut
---off while those keys mean something else (Config.Proximity.blocks).
local function suppress(rows)
  local blocks = settings.blocks
  if not blocks then return end

  for i = 1, #rows do
    local list = blocks[control(rows[i].key)]
    if list then
      for j = 1, #list do DisableControlAction(0, list[j], true) end
    end
  end
end

local function frameLoop(id)
  local aspect = GetAspectRatio(true)

  while shown and loopId == id do
    local rows = shown.rows
    suppress(rows)

    if shown.own then
      Input.syncPrompts(GetGameTimer())
      local candidate = shown.candidate
      local scale = Hit.scaleFor(candidate.distance or Config.Render.referenceDistance)
      local factor = ((tonumber(Appearance.tunables.scale) or 100) / 100) * ((Appearance.prefs.scale or 100) / 100)
      local bias = Appearance.anchor
      Surfaces.drawWorld('menu', candidate.anchor, Config.Render.menuSize * scale * factor, aspect, 255,
        bias and bias.x or 0.0, bias and bias.y or 0.0)
    end

    for i = 1, #rows do
      if Input.entryPressed(rows[i].key) then
        use(rows[i])
        break
      end
    end

    Wait(0)
  end
end

-- ── the look-round ─────────────────────────────────────────────────────────

---Not the moment for prompts.
local function standDown()
  if settings.enabled == false or Machine.isActive() or Machine.isDisabled() or Machine.blocked() then return true end
  if GetGameTimer() < quietUntil then return true end
  if cache.vehicle and not settings.inVehicle then return true end
  if IsPlayerFreeAiming(cache.playerId) then return true end
  return false
end

local function tick()
  if standDown() then
    hide()
    return
  end

  local candidate, entries = find()
  -- find() yields: the key may have gone down, or a prompt been used, meanwhile.
  if not started or standDown() then
    hide()
    return
  end

  if not candidate then
    hide()
    return
  end

  local rows = build(entries)
  local sig = signature(candidate, rows)

  if shown and shown.signature == sig then
    -- Same prompt: only where it is may have changed (a door swinging, a
    -- trolley rolling).
    local moved = #(candidate.anchor - shown.candidate.anchor) > 0.02
    shown.candidate, shown.rows = candidate, rows
    if moved and not shown.own then
      pcall(function() exports.vice_hud:SetWorldActionsCoords(candidate.anchor, OWNER) end)
    end
    return
  end

  if present(candidate, rows, sig) then
    loopId = loopId + 1
    local id = loopId
    CreateThread(function() frameLoop(id) end)
  end
end

function Proximity.start()
  if started or settings.enabled == false then return end
  started = true

  CreateThread(function()
    while started do
      tick()
      Wait(shown and (settings.interval or 150) or (settings.idleInterval or settings.interval or 150))
    end
    hide()
  end)
end

function Proximity.stop()
  started = false
  hide()
end

function Proximity.isShowing() return shown ~= nil end

---Take the prompt down now (the targeting key has gone down).
Proximity.hide = hide

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  Proximity.stop()
end)
