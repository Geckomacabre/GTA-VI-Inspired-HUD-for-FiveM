local Resolver = OsmTargetResolver
local Schema = OsmTargetSchema

Machine = {}

local IDLE, SWEEPING, MAGNETISED, MENU_OPEN, RELEASING = 'IDLE', 'SWEEPING', 'MAGNETISED', 'MENU_OPEN', 'RELEASING'

local state = IDLE
local disabled = false
local requested = false          -- Targeting key is currently down or toggle is active

local target                     -- Active locked or hovered target descriptor
local resolved = {}              -- Resolved options for active target
local focus = 1
local menuName = nil             -- Active submenu identifier
local menuHistory = {}
local menuMode = 'list'          -- 'list' | 'collapsed' | 'direct' -- see computeMode()

-- Entity parts (see Hit.parts): which physical part of the target the menu is
-- showing, and whether the player chose it with the part toggle rather than it
-- simply being nearest the crosshair.
local parts = {}
local partKey = nil              -- Part the menu should stay on
local shownKey = nil             -- Part the menu is actually showing
local partPinned = false         -- Chosen with Config.Input.cyclePart
local pinOffset = nil            -- Entity-local hit point the toggle was pressed at
local lastFollow = 0

local anchor                     -- World position where interface surface is anchored
local stateSince = 0
local releaseSince = nil
local lastRevalidate = 0
local lastScan = 0

-- Indicator hysteresis: angular tolerance preventing texture swapping on minor mouse movement
local NEAR_HYSTERESIS = 3.0

---Track indicator near states: preserve near focus state across discovery passes.
---@type table<any, boolean>
local nearState = {}

local function pointKey(point)
  if point.zone then return 'zone:' .. tostring(point.zone.id) end
  return point.entity or 0
end

local rad = math.rad
local deg = math.deg
local acos = math.acos

local function cameraBasis()
  local origin = GetFinalRenderedCamCoord()
  local rot = GetFinalRenderedCamRot(2)
  local pitch, yaw = rad(rot.x), rad(rot.z)
  local cosPitch = math.abs(math.cos(pitch))

  return origin, vec3(-math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch))
end

local function angleTo(origin, forward, point)
  local dx, dy, dz = point.x - origin.x, point.y - origin.y, point.z - origin.z
  local length = math.sqrt(dx * dx + dy * dy + dz * dz)
  if length < 0.01 then return 0.0 end

  local dot = (dx * forward.x + dy * forward.y + dz * forward.z) / length
  if dot > 1.0 then dot = 1.0 elseif dot < -1.0 then dot = -1.0 end
  return deg(acos(dot))
end

local function setState(next)
  state = next
  stateSince = GetGameTimer()
end

function Machine.isActive()  return state ~= IDLE end
function Machine.hasMenu()   return state == MENU_OPEN end
function Machine.state()     return state end

function Machine.setDisabled(value)
  disabled = value and true or false
  if disabled then Machine.abort() end
end

function Machine.isDisabled() return disabled end

---Decide which of the design's three prompt shapes the current option list
---calls for:
---  - 'collapsed' - one option that itself opens a submenu (e.g. a "Fridge"
---    entry leading to its own drink list): a single expand-key row stands in
---    for the list until the player presses it, per the tunable below.
---  - 'direct' - 1-2 options that are not that single-submenu-opener case
---    (e.g. a car door's "Slim Jim" / "Smash Window"): every option shown at
---    once, each independently keyed.
---  - 'list' - 3+ options, or fewer with the collapsed prompt disabled: the
---    ordinary scrolling rail.
---@return 'list' | 'collapsed' | 'direct'
local function computeMode()
  local count = #resolved
  if count == 0 then return 'list' end

  local singleSubmenu = count == 1 and resolved[1].option.openMenu ~= nil

  if singleSubmenu then
    local tunables = Appearance.tunables or {}
    local enabled = tunables.collapsedPrompt
    if enabled == nil or enabled == true then return 'collapsed' end
    return 'direct'
  end

  if count <= 2 then return 'direct' end
  return 'list'
end

local function sendMenu()
  menuMode = computeMode()

  local payload = Resolver.toPayload(resolved)

  if menuMode == 'direct' then
    for i = 1, #payload do
      payload[i].directKey = Input.directKeyLabel(i, resolved[i] and resolved[i].option.name)
    end
  end

  Surfaces.send('menu', 'menu:open', {
    options = payload,
    focus = focus,
    menu = menuName,
    empty = #resolved == 0,
    emptyLabel = Locale('no_options'),
    mode = menuMode,
    collapseLabel = menuMode == 'collapsed'
      and (resolved[1].label or resolved[1].option.label) or nil,
  })
end

local function sendFocus()
  Surfaces.send('menu', 'menu:focus', { focus = focus })
end

---Find next focusable option: iterate options in direction to locate focusable entry.
local function nextFocusable(from, direction)
  local count = #resolved
  if count == 0 then return 1 end

  local index = from
  for _ = 1, count do
    index = index + direction
    if index > count then index = 1 elseif index < 1 then index = count end
    if resolved[index].focusable then return index end
  end
  return from
end

local function firstFocusable()
  for i = 1, #resolved do
    if resolved[i].focusable then return i end
  end
  return 1
end

---Build callback response table: construct context payload for onSelect handler.
local function buildResponse(option, forServer)
  local response = {}
  for key, value in pairs(option) do
    response[key] = value
  end

  response.entity = target and target.entity ~= 0 and target.entity or nil
  response.coords = anchor or (target and target.coords) or nil
  response.distance = target and target.distance or nil
  response.zone = target and target.zone and target.zone.id or nil

  if forServer then
    if response.entity then
      response.entity = NetworkGetEntityIsNetworked(response.entity)
        and NetworkGetNetworkIdFromEntity(response.entity) or 0
    end

    -- Strip callable fields: prevent serialization errors when transmitting
    -- response to server. Custom option keys are forwarded verbatim (see
    -- carryExtras), so a caller's own callback can be sitting in any field --
    -- and a cross-resource one is a funcref *table*, which a plain
    -- type(value) == 'function' test would wave straight through onto the wire.
    for key, value in pairs(response) do
      if Schema.callable(value) then response[key] = nil end
    end
  end

  response.icon, response.iconColor = nil, nil
  response.groups, response.gangs, response.items, response.anyItem = nil, nil, nil, nil
  response.excludeGroups, response.excludeGangs = nil, nil
  response.jobTypes, response.excludeJobTypes = nil, nil
  response.canInteract, response.onSelect = nil, nil
  response.export, response.event, response.serverEvent = nil, nil, nil
  response.command, response.qbCommand = nil, nil
  response.dialect, response.qb, response.qtarget = nil, nil, nil

  return response
end

---Execute callback: handle dialect-specific parameter requirements.
local function execute(option)
  if option.onSelect then
    if option.qb or option.qtarget then
      option.onSelect(target and target.entity ~= 0 and target.entity or nil)
    else
      option.onSelect(buildResponse(option))
    end
  elseif option.export then
    local resource = option.resource or (target and target.zone and target.zone.resource)
    if resource then
      exports[resource][option.export](nil, buildResponse(option))
    end
  elseif option.event then
    TriggerEvent(option.event, buildResponse(option))
  elseif option.serverEvent then
    TriggerServerEvent(option.serverEvent, buildResponse(option, true))
  elseif option.command then
    ExecuteCommand(option.command)
  elseif option.qbCommand then
    TriggerServerEvent('QBCore:CallCommand', option.qbCommand, buildResponse(option, true))
  end
end

local BACK_OPTION = {
  label = nil,
  name = 'osm:goback',
  icon = 'arrow-left',
  openMenu = 'home',
  distance = math.huge,
  dialect = 'ox',
  resource = 'osm-target',
}

---Pick which of the target's parts to show: the one the player toggled to
---while it is still there, otherwise the one nearest the crosshair -- held
---until another is nearer by Config.Parts.hysteresis, so a hit point sitting
---between a door and a tire does not flip the menu on every revalidation.
local function choosePart()
  if #parts < 2 then return parts[1] end

  local current
  for i = 1, #parts do
    if parts[i].key == partKey then
      current = parts[i]
      break
    end
  end

  if current and partPinned then return current end
  partPinned = false

  local nearest = parts[1]
  if current and current ~= nearest
    and nearest.distance + (Config.Parts.hysteresis or 0.0) >= current.distance
  then
    return current
  end

  partKey = nearest.key
  return nearest
end

---Resolve target options: populate active options from precomputed candidate list.
local function resolveTarget(preserveFocusName, precomputed)
  if not target then
    resolved, parts, shownKey = {}, {}, nil
    return
  end

  parts = Hit.parts(target, precomputed or Hit.resolve(target, menuName))
  local part = choosePart()
  shownKey = part and part.key

  -- Copied rather than aliased: the back row below is inserted into it.
  resolved = {}
  if part then
    for i = 1, #part.entries do resolved[i] = part.entries[i] end
  end

  if menuName then
    BACK_OPTION.label = Locale('go_back')
    table.insert(resolved, 1, {
      index = 1,
      option = BACK_OPTION,
      enabled = true,
      focusable = true,
    })
    for i = 1, #resolved do resolved[i].index = i end
  end

  if preserveFocusName then
    for i = 1, #resolved do
      if resolved[i].option.name == preserveFocusName then
        focus = i
        return
      end
    end
  end

  focus = firstFocusable()
end

---Acquire interactive target: check direct raycast hit, containing zone, or nearest snap indicator.
local function acquire(origin, forward)
  local scan = Hit.scan()
  local reach = Config.Interaction.distance

  if scan.entity ~= 0 and scan.distance <= reach then
    local list = Hit.resolve(scan, menuName)
    if #list > 0 then
      scan.resolved = list
      scan.angle = 0.0
      scan.anchor = Hit.anchor(scan, list)
      return scan
    end
  end

  -- Check containing zones: evaluate zones encompassing the hit coordinates
  local zones = Store.zonesContaining(scan.coords)
  for i = 1, #zones do
    local zone = zones[i]
    local distance = #(GetEntityCoords(cache.ped) - zone.coords)
    if distance <= reach then
      local candidate = {
        entity = 0, entityType = 0, model = nil,
        coords = scan.coords, distance = distance, zone = zone,
      }
      local list = Hit.resolve(candidate, menuName)
      if #list > 0 then
        candidate.resolved = list
        candidate.angle = angleTo(origin, forward, zone.coords)
        candidate.anchor = zone.coords
        return candidate
      end
    end
  end

  -- Evaluate nearby indicators: locate nearest indicator within snap angle threshold
  local points = Discovery.points
  local best, bestAngle

  for i = 1, #points do
    local point = points[i]
    local angle = angleTo(origin, forward, point.coords)
    point.angle = angle

    if angle <= Config.Interaction.snapAngle and (not bestAngle or angle < bestAngle) then
      best, bestAngle = point, angle
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

  local list = Hit.resolve(candidate, menuName)
  if #list == 0 then return nil end

  candidate.resolved = list
  candidate.angle = bestAngle
  candidate.anchor = best.coords
  candidate.point = best
  return candidate
end

local function magnetise(candidate)
  target = candidate
  anchor = candidate.anchor
  menuName = nil
  menuHistory = {}
  releaseSince = nil
  partKey, partPinned, pinOffset = nil, false, nil

  resolveTarget(nil, candidate.resolved)
  if #resolved == 0 then
    target = nil
    return
  end

  -- candidate.anchor was taken from the whole list; anchor on the part that won.
  if target.entity and target.entity ~= 0 then
    anchor = Hit.anchor(target, resolved)
  end

  setState(MAGNETISED)
  Surfaces.send('active', 'indicator:activate', { duration = Config.Interaction.openTime })
  Nui.sfx('magnetise')
end

local function openMenu()
  setState(MENU_OPEN)
  lastRevalidate = GetGameTimer()
  lastFollow = lastRevalidate
  sendMenu()
end

---Release active target: transition state machine to releasing and reset UI.
local releaseToken = 0

local function release()
  if state == IDLE then return end

  releaseToken = releaseToken + 1
  local token = releaseToken

  setState(RELEASING)
  releaseSince = nil
  Surfaces.send('menu', 'menu:close', {})
  Surfaces.send('active', 'indicator:reset', {})

  CreateThread(function()
    Wait(Config.Interaction.closeTime)
    -- Validate release token: ensure release transition has not been superseded
    if state ~= RELEASING or releaseToken ~= token then return end

    target, anchor = nil, nil
    resolved = {}
    menuName, menuHistory = nil, {}
    parts, partKey, shownKey, partPinned, pinOffset = {}, nil, nil, false, nil

    if requested then
      setState(SWEEPING)
      lastScan = 0
    else
      setState(IDLE)
      Machine.teardown()
    end
  end)
end

---Abort interaction immediately: perform immediate state reset and surface cleanup.
function Machine.abort()
  if state == IDLE then return end
  requested = false
  state = IDLE
  target, anchor, resolved = nil, nil, {}
  menuName, menuHistory, releaseSince = nil, {}, nil
  parts, partKey, shownKey, partPinned, pinOffset = {}, nil, nil, false, nil
  Machine.teardown()
end

function Machine.cancel()
  if state == IDLE then return end
  if state == MENU_OPEN or state == MAGNETISED then
    Nui.sfx('cancel')
    release()
  else
    Machine.abort()
  end
end

function Machine.teardown()
  Surfaces.send('menu', 'menu:close', {})
  Surfaces.send('active', 'indicator:reset', {})
  Discovery.clear()
  nearState = {}
end

local function moveFocus(direction)
  if #resolved == 0 then return end

  local index = nextFocusable(focus, direction)
  if index == focus then return end

  focus = index
  sendFocus()
  Nui.sfx(resolved[focus].enabled and 'scroll' or 'reject')
end

---The part toggle: step the menu to the next part of the same entity (driver
---door -> front tire -> ...) and keep it there while the crosshair stays about
---where it was, instead of snapping back to whichever part is nearest.
local function cyclePart()
  if state ~= MENU_OPEN or not target then return end

  -- Parts are split at the top level only: a submenu belongs to the part it
  -- was opened from.
  if menuName or #parts < 2 then
    Nui.sfx('reject')
    return
  end

  local index = 1
  for i = 1, #parts do
    if parts[i].key == shownKey then
      index = i
      break
    end
  end

  partKey = parts[index % #parts + 1].key
  partPinned = true
  pinOffset = target.offset
    or GetOffsetFromEntityGivenWorldCoords(target.entity, target.coords.x, target.coords.y, target.coords.z)

  resolveTarget()
  anchor = Hit.anchor(target, resolved)
  sendMenu()
  Nui.sfx('scroll')
end

---Move the open menu's hit point to where the crosshair is now on the same
---entity, so looking from the door to the tire moves the menu with it instead
---of it staying on wherever the first hit landed.
---@return boolean refreshed options were re-resolved from the new hit
local function followHit(scan)
  if not scan.offset then return false end

  -- A toggled part holds until the crosshair has clearly moved on from where
  -- the toggle was pressed: the choice was about that spot, not the whole car.
  if partPinned then
    if not pinOffset or #(scan.offset - pinOffset) <= (Config.Parts.unpinDistance or 1.0) then
      return false
    end
    partPinned = false
  end

  local list = Hit.resolve({
    entity = target.entity, entityType = target.entityType, model = target.model,
    coords = scan.coords, offset = scan.offset, distance = target.distance,
  }, menuName)

  -- Nothing at the new spot: keep what is showing, the same stickiness the
  -- look-away grace in logicTick already gives the menu.
  if #list == 0 then return false end

  target.coords, target.offset = scan.coords, scan.offset

  local focusName = resolved[focus] and resolved[focus].option.name
  local beforeKey, beforeCount = shownKey, #resolved
  resolveTarget(focusName, list)

  if shownKey ~= beforeKey then
    anchor = Hit.anchor(target, resolved)
    sendMenu()
    Nui.sfx('scroll')
  elseif #resolved ~= beforeCount then
    sendMenu()
  end

  return true
end

local function confirm()
  local entry = resolved[focus]
  if not entry then return end

  if not entry.enabled then
    Nui.sfx('reject')
    Surfaces.send('menu', 'menu:reject', { focus = focus })
    return
  end

  local option = entry.option

  -- Navigate submenu: update menu level without executing external action
  if option.openMenu then
    Nui.sfx('confirm')

    if option.name == 'osm:goback' then
      menuName = table.remove(menuHistory) or nil
    else
      menuHistory[#menuHistory + 1] = menuName
      menuName = option.openMenu ~= 'home' and option.openMenu or nil
    end

    resolveTarget()
    sendMenu()
    return
  end

  -- Revalidate before execution: verify option eligibility before running action
  Player.refresh()
  local allowed, reason = Resolver.canExecute(option, Hit.context(target, menuName), target.distance)

  if not allowed then
    Nui.sfx('reject')
    resolveTarget(option.name)
    sendMenu()
    if reason then Bridge.Notify(reason, 'error') end
    return
  end

  Nui.sfx('confirm')

  -- End the session on execute, even if the key is still held: release() would
  -- otherwise see `requested` still true and drop straight back to SWEEPING,
  -- re-targeting on top of whatever the option just started. Matters most for
  -- an option that opens its own minigame (a lockpick ring, a hacking panel) --
  -- the rail would keep sweeping and re-confirming underneath it. The key has
  -- to be released and pressed again, which is also what ox_target and
  -- qb-target do. Cancelling, or looking away while still holding, is
  -- unaffected and still returns to SWEEPING.
  requested = false

  execute(option)
  release()
end

---Check blocking conditions: verify player is alive and no modal overlays are active.
local function blocked()
  return disabled
    or IsPauseMenuActive()
    or IsPlayerDead(cache.playerId)
    or IsCutsceneActive()
    or IsNuiFocused()
    or not Bridge.IsPlayerLoaded()
    or (type(lib.progressActive) == 'function' and lib.progressActive())
end

local function targetStillValid()
  if not target then return false end

  if target.zone then
    return Store.zones[target.zone.id] ~= nil
  end

  if target.entity and target.entity ~= 0 then
    return DoesEntityExist(target.entity)
  end

  return true
end

local function logicTick()
  local now = GetGameTimer()
  local origin, forward = cameraBasis()

  if state == SWEEPING then
    if now - lastScan >= Config.Interaction.scanInterval then
      lastScan = now
      Discovery.run()

      local candidate = acquire(origin, forward)

      if candidate and candidate.angle <= Config.Interaction.snapAngle then
        magnetise(candidate)
      end
    end
    return
  end

  if state == MAGNETISED then
    if not targetStillValid() then
      release()
      return
    end

    anchor = Hit.anchor(target, resolved)

    if now - stateSince >= Config.Interaction.openTime then
      openMenu()
    end
    return
  end

  if state == MENU_OPEN then
    if not targetStillValid() then
      release()
      return
    end

    -- Update anchor position: track entity coordinates in real-time
    anchor = Hit.anchor(target, resolved)
    target.distance = Hit.distance(target, anchor, resolved)

    if target.distance > Config.Interaction.distance + 1.5 then
      release()
      return
    end

    local angle = angleTo(origin, forward, anchor)
    local onEntity = target.entity and target.entity ~= 0
    local settings = Config.Parts

    local follow = onEntity and settings and settings.enabled and menuName == nil
      and now - lastFollow >= (settings.followInterval or 150)

    -- One scan serves both part following and the look-away grace below.
    local scan
    if onEntity and (follow or angle > Config.Interaction.releaseAngle) then
      local scanned = target
      scan = Hit.scan()

      -- Hit.scan yields a frame: the draw thread may have confirmed, cancelled
      -- or toggled the part in the meantime.
      if state ~= MENU_OPEN or target ~= scanned then return end
      now = GetGameTimer()
    end

    local lookingAtTarget = scan ~= nil and scan.entity == target.entity

    if angle > Config.Interaction.releaseAngle then
      if lookingAtTarget then
        releaseSince = nil
      else
        releaseSince = releaseSince or now
        if now - releaseSince >= Config.Interaction.releaseTime then
          release()
          return
        end
      end
    else
      releaseSince = nil
    end

    if follow then
      lastFollow = now
      if lookingAtTarget and followHit(scan) then
        lastRevalidate = now
      end
    end

    -- Periodically refresh options: revalidate gates while menu remains open
    if now - lastRevalidate >= 400 then
      lastRevalidate = now
      local focusName = resolved[focus] and resolved[focus].option.name
      local before, beforeKey = #resolved, shownKey
      resolveTarget(focusName)

      if #resolved == 0 then
        release()
      elseif #resolved ~= before or shownKey ~= beforeKey then
        sendMenu()
      end
    end
  end
end

local EMPTY_ANCHOR = { x = 0.0, y = 0.0 }

local function drawTick()
  local aspect = GetAspectRatio(true)
  local render = Config.Render
  -- Calculate scale multiplier: combine design tuning scale and player preferences
  local designScale = tonumber(Appearance.tunables.scale) or 100
  local scaleFactor = (designScale / 100) * ((Appearance.prefs.scale or 100) / 100)

  -- Render indicator markers: draw world-space indicator sprites at active discovery points
  if Config.Indicators.enabled then
    local points = Discovery.points
    local nearAngle = Config.Indicators.nearAngle
    local exitAngle = nearAngle + NEAR_HYSTERESIS
    local anchorPoint = anchor
    local origin, forward = cameraBasis()

    for i = 1, #points do
      local point = points[i]

      -- Skip magnetized anchor: avoid rendering idle indicator under active menu
      if not (anchorPoint and #(point.coords - anchorPoint) < 0.05) then
        -- Calculate point angle: compute angle from camera forward vector per frame
        local angle = angleTo(origin, forward, point.coords)
        point.angle = angle

        local key = pointKey(point)
        local near = nearState[key] and angle <= exitAngle or angle <= nearAngle
        nearState[key] = near

        local size = render.indicatorSize * Hit.scaleFor(point.distance) * scaleFactor
        local fade = 1.0 - math.min(point.distance / Config.Indicators.radius, 1.0)
        local alpha = 90 + fade * 140

        Surfaces.drawWorld(near and 'near' or 'idle', point.coords, size, aspect, alpha)
      end
    end
  end

  -- Render aiming cursor: draw screen-space reticle or animate transition on target lock
  if state == SWEEPING then
    Surfaces.drawScreen('cursor', 0.5, 0.5, render.cursorSize * scaleFactor, aspect, 255)
  elseif state == MAGNETISED and anchor and not Appearance.prefs.reducedMotion then
    local openTime = math.max(1, Config.Interaction.openTime)
    local t = (GetGameTimer() - stateSince) / openTime
    if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end

    local eased = t * t * (3.0 - 2.0 * t)
    -- Fade reticle alpha: calculate smooth ease-out opacity during transition
    local alpha = 255.0 * (1.0 - eased * eased)

    if alpha > 1.0 then
      local x, y = 0.5, 0.5
      local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(anchor.x, anchor.y, anchor.z)

      if onScreen then
        x = 0.5 + (screenX - 0.5) * eased
        y = 0.5 + (screenY - 0.5) * eased
      end

      Surfaces.drawScreen('cursor', x, y,
        render.cursorSize * scaleFactor * (1.0 - 0.45 * eased), aspect, alpha)
    end
  end

  if (state == MAGNETISED or state == MENU_OPEN or state == RELEASING) and anchor then
    local scale = Hit.scaleFor(target and target.distance or render.referenceDistance)
    local menuUp = state ~= MAGNETISED

    -- Yield the anchor to the menu: designs that draw their own mark on the world
    -- point would otherwise show the active indicator behind their option list.
    local alpha = 255.0
    if menuUp and OsmTargetDesigns.hidesIndicator(Appearance.design) then
      if state == RELEASING or Appearance.prefs.reducedMotion then
        alpha = 0.0
      else
        -- Fades over the same window the menu opens in, so the indicator is
        -- absorbed by the list rather than cut away from under it.
        local t = (GetGameTimer() - stateSince) / math.max(1, Config.Interaction.openTime)
        if t > 1.0 then t = 1.0 elseif t < 0.0 then t = 0.0 end
        alpha = 255.0 * (1.0 - t)
      end
    end

    if alpha > 1.0 then
      Surfaces.drawWorld('active', anchor, render.indicatorSize * scale * scaleFactor, aspect, alpha)
    end

    if menuUp then
      local bias = Appearance.anchor or EMPTY_ANCHOR
      Surfaces.drawWorld('menu', anchor, render.menuSize * scale * scaleFactor, aspect, 255,
        bias.x, bias.y)
    end
  end
end

function Machine.start()
  if disabled then return end
  requested = true
  if state ~= IDLE then return end
  if blocked() then return end

  Surfaces.init()
  Discovery.run(true)
  setState(SWEEPING)
  lastScan = 0
  Nui.sfx('sweep')

  CreateThread(function()
    while state ~= IDLE do
      Input.suppress()
      -- Throttled inside, and only sends when the binding or the device
      -- actually changed, so the prompt follows a controller being unplugged
      -- mid-session without polling three natives every frame.
      Input.syncPrompts(GetGameTimer())
      drawTick()

      if state == MENU_OPEN then
        -- The shared scroll+confirm cursor always still works, in every mode:
        -- it is the only way a pad player reaches a 'direct' prompt's second
        -- option (see Config.Input.directOptionKeys), and it is exactly what
        -- drives a 'collapsed' prompt already, since that mode is always
        -- exactly one focusable option -- confirming it is what expands the
        -- submenu into the ordinary list.
        local delta = Input.scrollDelta()
        if delta ~= 0 then moveFocus(delta) end
        if Input.confirmPressed() then confirm() end
        if Input.cyclePartPressed() then cyclePart() end

        -- Cancel is skipped here, not suppressed globally, when a direct-mode
        -- option's own key happens to double as the shared cancel button --
        -- Slim Jim/Smash Window's Circle/B is exactly this (see config.lua's
        -- directKeyByName comment). Suppressing 194 in Config.Input.suppress
        -- would break Circle/B as cancel on every OTHER menu; skipping the
        -- check only while this specific mode is showing does not. Backing
        -- out of a direct prompt is done by aiming away from the target,
        -- same as the reference has no separate "back" affordance here.
        if menuMode ~= 'direct' and Input.cancelPressed() then Machine.cancel() end

        -- 'direct' additionally answers to each option's own dedicated key,
        -- independently of the shared cursor above, so every option really is
        -- simultaneously pressable rather than needing to be scrolled onto
        -- first.
        if menuMode == 'direct' then
          for i = 1, #resolved do
            if Input.directKeyPressed(i, resolved[i].option.name) then
              if i ~= focus then
                focus = i
                sendFocus()
              end
              confirm()
              break
            end
          end
        end
      elseif state == SWEEPING then
        if Input.cancelPressed() then Machine.abort() end
      end

      Wait(0)
    end
  end)

  CreateThread(function()
    while state ~= IDLE do
      if blocked() then
        Machine.abort()
        break
      end
      logicTick()
      Wait(state == MENU_OPEN and 30 or 0)
    end
  end)
end

---Stop interaction: initiate release transition or abort sweep.
function Machine.stop()
  requested = false

  if state == SWEEPING then
    Machine.abort()
  elseif state == MAGNETISED or state == MENU_OPEN then
    release()
  end
end

CreateThread(function()
  while true do
    if state ~= IDLE and (IsPauseMenuActive() or IsPlayerDead(cache.playerId) or IsCutsceneActive()) then
      Machine.abort()
    end
    Wait(250)
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  Machine.abort()
end)
