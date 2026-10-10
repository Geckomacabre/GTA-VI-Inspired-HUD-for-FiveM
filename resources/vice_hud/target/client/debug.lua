local Resolver = OsmTargetResolver

Debug = {}

local zoneDebugApplied = {}

local function applyZoneDebug(enabled)
  for id, zone in pairs(Store.zones) do
    if enabled and not zoneDebugApplied[id] then
      if zone.setDebug then zone:setDebug(true, { r = 20, g = 184, b = 166, a = 60 }) end
      zoneDebugApplied[id] = true
    elseif not enabled and zoneDebugApplied[id] then
      if zone.setDebug then zone:setDebug(false) end
      zoneDebugApplied[id] = nil
    end
  end
end

function Debug.setEnabled(enabled)
  Config.TargetDebug = enabled and true or false
  applyZoneDebug(Config.TargetDebug)
  Bridge.Notify(Locale(Config.TargetDebug and 'debug_on' or 'debug_off'), 'inform')
end

RegisterNetEvent('osm-target:cl:setDebug', function(enabled)
  Debug.setEnabled(enabled)
end)

local function drawText3d(coords, text)
  SetTextScale(0.30, 0.30)
  SetTextFont(4)
  SetTextColour(255, 255, 255, 215)
  SetTextCentre(true)
  SetTextEntry('STRING')
  AddTextComponentString(text)

  SetDrawOrigin(coords.x, coords.y, coords.z, 0)
  DrawText(0.0, 0.0)
  ClearDrawOrigin()
end

CreateThread(function()
  while true do
    if not Config.TargetDebug then
      Wait(500)
    else
      applyZoneDebug(true)

      local origin = GetEntityCoords(cache.ped)

      for _, zone in pairs(Store.zones) do
        if #(origin - zone.coords) < 30.0 then
          drawText3d(zone.coords + vec3(0.0, 0.0, 0.4),
            ('zone #%s  %s  %d opt'):format(zone.id, zone.name or '-', #(zone.options or {})))
        end
      end

      for handle, options in pairs(Store.localEntities) do
        if DoesEntityExist(handle) then
          local coords = GetEntityCoords(handle)
          if #(origin - coords) < 30.0 then
            DrawMarker(28, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
              0.12, 0.12, 0.12, 20, 184, 166, 90, false, false, 0, true, nil, nil, false)
            drawText3d(coords + vec3(0.0, 0.0, 0.5), ('entity %d  %d opt'):format(handle, #options))
          end
        end
      end

      local points = Discovery.points
      for i = 1, #points do
        local point = points[i]
        DrawMarker(28, point.coords.x, point.coords.y, point.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
          0.08, 0.08, 0.08, 226, 180, 71, 120, false, false, 0, true, nil, nil, false)
      end

      Wait(0)
    end
  end
end)

---Debug explain command: print resolver evaluation details for current raycast hit.
function Debug.explain()
  local scan = Hit.scan()
  local context = Hit.context(scan, nil)
  local candidates = Store.candidatesForEntity(scan.entity, scan.entityType, scan.model, scan.distance)

  local zones = Store.zonesContaining(scan.coords)
  for i = 1, #zones do
    local zoneCandidates = Store.candidatesForZone(zones[i], scan.distance)
    for j = 1, #zoneCandidates do candidates[#candidates + 1] = zoneCandidates[j] end
  end

  -- Archetype name turns an anonymous model hash into the prop's actual name,
  -- which is the difference between "1337214862" and "prop_atm_01" when the
  -- question is what to write addModel against.
  local archetype
  if scan.entity and scan.entity ~= 0 then
    local ok, name = pcall(GetEntityArchetypeName, scan.entity)
    if ok and type(name) == 'string' and name ~= '' then archetype = name end
  end

  print(('^5[osm-target] hit entity=%s type=%s model=%s%s distance=%.2f candidates=%d^7')
    :format(scan.entity, scan.entityType, tostring(scan.model),
      archetype and (' (' .. archetype .. ')') or '', scan.distance, #candidates))

  if #candidates == 0 then
    print('^3  nothing is registered for this target^7')
    return
  end

  for i = 1, #candidates do
    local candidate = candidates[i]
    local option = candidate.option or candidate
    local verdict, reason = Resolver.evaluate(option, context, candidate.distance or scan.distance)

    local colour = verdict == Resolver.OK and '^2' or verdict == Resolver.GATED and '^3' or '^9'
    print(('%s  [%s] %s  (%s)%s%s^7'):format(
      colour, verdict, Resolver.label(option, context, candidate.distance or scan.distance) or '?',
      option.resource or '?',
      reason and '  reason: ' or '', reason or ''))
  end
end

---Reject diagnostic command: diagnostics are gated by the admin-only debug toggle.
local function diagnosticsReady()
  if Config.TargetDebug then return true end
  Bridge.Notify(Locale('debug_required', Config.Commands.debug), 'error')
  return false
end

RegisterCommand(Config.Commands.explain, function()
  if not diagnosticsReady() then return end
  Debug.explain()
end, false)

---Benchmark anchor calculation: compare Discovery.entityAnchor vs direct GetEntityCoords.
---@param count number? iterations count (default 50000)
function Debug.benchmark(count)
  local iterations = tonumber(count) or 50000
  if iterations < 1000 then iterations = 1000 elseif iterations > 1000000 then iterations = 1000000 end

  local scan = Hit.scan()
  local entity = (scan.entity ~= 0 and DoesEntityExist(scan.entity)) and scan.entity or cache.ped
  local model = GetEntityModel(entity)
  local entityType = GetEntityType(entity)
  local typeName = entityType == 1 and 'Ped' or entityType == 2 and 'Vehicle' or entityType == 3 and 'Object' or 'Unknown'

  local function getNow()
    if os.nanotime then return os.nanotime() end
    return os.clock() * 1e9
  end

  -- Warmup pass
  for _ = 1, 1000 do
    GetEntityCoords(entity)
    Discovery.entityAnchor(entity, model)
  end

  -- 1. Direct GetEntityCoords
  local t0 = getNow()
  for _ = 1, iterations do
    local _ = GetEntityCoords(entity)
  end
  local t1 = getNow()
  local directNanos = (t1 - t0)

  -- 2. Current Discovery.entityAnchor
  local t2 = getNow()
  for _ = 1, iterations do
    local _ = Discovery.entityAnchor(entity, model)
  end
  local t3 = getNow()
  local currentNanos = (t3 - t2)

  -- 3. Cached Dimensions (GetOffsetFromEntityInWorldCoords only)
  local ok, minimum, maximum = pcall(GetModelDimensions, model)
  local mid = (ok and minimum and maximum) and ((minimum.z + maximum.z) * 0.5) or 0.0
  local t4 = getNow()
  for _ = 1, iterations do
    local _ = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, mid)
  end
  local t5 = getNow()
  local cachedNanos = (t5 - t4)

  local directMs = directNanos / 1e6
  local currentMs = currentNanos / 1e6
  local cachedMs = cachedNanos / 1e6

  local directPerCallUs = (directNanos / iterations) / 1e3
  local currentPerCallUs = (currentNanos / iterations) / 1e3
  local cachedPerCallUs = (cachedNanos / iterations) / 1e3

  local directOps = math.floor((iterations / (directNanos / 1e9)) + 0.5)
  local currentOps = math.floor((iterations / (currentNanos / 1e9)) + 0.5)
  local cachedOps = math.floor((iterations / (cachedNanos / 1e9)) + 0.5)

  local ratio = currentNanos / math.max(1, directNanos)

  print('^5========================================================================^7')
  print(('^5[osm-target] Anchor Calculation Benchmark (%s iterations)^7'):format(iterations))
  print(('^7Target Entity: ^3#%s^7 | Type: ^3%s^7 | Model: ^30x%X^7'):format(entity, typeName, model))
  print('^5------------------------------------------------------------------------^7')
  print('^21. Direct GetEntityCoords:^7')
  print(('   Total Time : ^2%.3f ms^7'):format(directMs))
  print(('   Per Call   : ^2%.3f us^7 (%.1f ns)'):format(directPerCallUs, directNanos / iterations))
  print(('   Throughput : ^2%s ops/sec^7'):format(directOps))
  print('')
  print('^32. Current Discovery.entityAnchor (GetModelDimensions + GetOffset):^7')
  print(('   Total Time : ^3%.3f ms^7'):format(currentMs))
  print(('   Per Call   : ^3%.3f us^7 (%.1f ns)'):format(currentPerCallUs, currentNanos / iterations))
  print(('   Throughput : ^3%s ops/sec^7'):format(currentOps))
  print(('   Overhead   : ^3%.2fx^7 vs direct'):format(ratio))
  print('')
  print('^63. With Cached Dimensions (GetOffsetFromEntityInWorldCoords only):^7')
  print(('   Total Time : ^6%.3f ms^7'):format(cachedMs))
  print(('   Per Call   : ^6%.3f us^7 (%.1f ns)'):format(cachedPerCallUs, cachedNanos / iterations))
  print(('   Throughput : ^6%s ops/sec^7'):format(cachedOps))
  print('^5------------------------------------------------------------------------^7')
  print('^7Performance Analysis (at 60 FPS = 16.6ms frame budget):')
  local tenPointsCost = (currentPerCallUs * 10) / 1000
  print((' - Cost for 10 nearby entities in a discovery pass: ^2%.4f ms^7 (~%.4f%% of 1 frame)'):format(
    tenPointsCost, (tenPointsCost / 16.6) * 100))
  print('^5========================================================================^7')

  Bridge.Notify(('Benchmark finished (%d iterations). Check F8 console.'):format(iterations), 'inform')
end

RegisterCommand(Config.Commands.bench, function(_, args)
  if not diagnosticsReady() then return end
  Debug.benchmark(args and args[1])
end, false)

local TEST_MENU = 'osm:test:medical'
local FRIDGE_MENU = 'osm:test:fridge'
local testPed

---Generate test options: build full matrix of option types for visual verification.
local function testOptions()
  local function announce(label)
    return function() Bridge.Notify(Locale('test_selected', label), 'inform') end
  end

  return {
    {
      name = 'osm:test:talk',
      label = Locale('test_talk'),
      description = Locale('test_talk_desc'),
      icon = 'chat',
      onSelect = announce(Locale('test_talk')),
    },
    {
      name = 'osm:test:search',
      label = Locale('test_search'),
      description = Locale('test_search_desc'),
      icon = 'search',
      onSelect = announce(Locale('test_search')),
    },
    {
      name = 'osm:test:cuff',
      label = Locale('test_cuff'),
      icon = 'lock',
      items = { 'handcuffs' },
      onSelect = announce(Locale('test_cuff')),
    },
    {
      name = 'osm:test:fine',
      label = Locale('test_fine'),
      icon = 'gavel',
      groups = { 'police' },
      onSelect = announce(Locale('test_fine')),
    },
    {
      name = 'osm:test:move',
      label = Locale('test_move'),
      icon = 'navigate',
      canInteract = function()
        return false, Locale('test_move_reason')
      end,
      onSelect = announce(Locale('test_move')),
    },
    {
      name = 'osm:test:medical',
      label = Locale('test_medical'),
      icon = 'medkit',
      openMenu = TEST_MENU,
    },
    {
      name = 'osm:test:pulse',
      label = Locale('test_pulse'),
      icon = 'heartbeat',
      menuName = TEST_MENU,
      onSelect = announce(Locale('test_pulse')),
    },
    {
      name = 'osm:test:treat',
      label = Locale('test_treat'),
      icon = 'bandage',
      menuName = TEST_MENU,
      items = { 'bandage' },
      onSelect = announce(Locale('test_treat')),
    },
  }
end

---Generate fridge test options: build reference option hierarchy for submenu layout.
local function fridgeOptions()
  local function announce(label)
    return function() Bridge.Notify(Locale('test_selected', label), 'inform') end
  end

  -- Configure visual badges: define icon chips for test entries
  local chilled = { { icon = 'eye', color = '#a06cff' } }

  return {
    {
      name = 'osm:test:fridge',
      label = Locale('test_fridge'),
      openMenu = FRIDGE_MENU,
    },
    {
      name = 'osm:test:fridge:logger',
      label = Locale('test_fridge_logger'),
      menuName = FRIDGE_MENU,
      onSelect = announce(Locale('test_fridge_logger')),
    },
    {
      name = 'osm:test:fridge:lavazas',
      label = Locale('test_fridge_lavazas'),
      menuName = FRIDGE_MENU,
      onSelect = announce(Locale('test_fridge_lavazas')),
    },
    {
      name = 'osm:test:fridge:berry',
      label = Locale('test_fridge_berry'),
      icon = 'power',
      iconColor = '#3ddc97',
      badges = chilled,
      menuName = FRIDGE_MENU,
      onSelect = announce(Locale('test_fridge_berry')),
    },
    {
      name = 'osm:test:fridge:green',
      label = Locale('test_fridge_green'),
      icon = 'power',
      iconColor = '#3ddc97',
      badges = chilled,
      menuName = FRIDGE_MENU,
      onSelect = announce(Locale('test_fridge_green')),
    },
    {
      -- Gated test option: simulate predicate refusal with custom reason
      name = 'osm:test:fridge:protein',
      label = Locale('test_fridge_protein'),
      menuName = FRIDGE_MENU,
      canInteract = function()
        return false, Locale('test_fridge_protein_reason')
      end,
      onSelect = announce(Locale('test_fridge_protein')),
    },
  }
end

---Generate two-option test options: exercises the 'direct' multi-key prompt
---(1-2 plain options, shown at once, each its own key) -- the one render
---path neither the default nor fridge test variant ever reaches, since both
---resolve to 3+ options. Mirrors qbx_vehiclekeys' own Slim Jim/Smash Window
---shape (two plain options, no openMenu) so this is what actually exercises
---that path before a real locked/keyless vehicle is available to test with.
local function carOptions()
  local function announce(label)
    return function() Bridge.Notify(Locale('test_selected', label), 'inform') end
  end

  return {
    {
      name = 'osm:test:car:slimjim',
      label = Locale('test_car_slimjim'),
      icon = 'screwdriver',
      onSelect = announce(Locale('test_car_slimjim')),
    },
    {
      name = 'osm:test:car:smashwindow',
      label = Locale('test_car_smashwindow'),
      icon = 'hammer',
      onSelect = announce(Locale('test_car_smashwindow')),
    },
  }
end

-- Badge visuals for the three consumable categories ox_inventory's
-- GetConsumableBadges export can return -- same colors vice_hud's own
-- health/stamina/focus status rows use, so an item that restores one reads
-- consistently whether you're looking at the HUD or this menu.
local BADGE_STYLE = {
  health  = { icon = 'heart', color = '#f5acc6' },
  stamina = { icon = 'power', color = '#5fd8c8' },
  focus   = { icon = 'eye',   color = '#b98bd6' },
}

---Real ox_inventory item as a target option -- label from Bridge.GetItemLabel,
---badges from Bridge.GetConsumableBadges (both wrapping ox_inventory exports
---added alongside this feature). Returns nil if ox_inventory doesn't know the
---item (not running, or a typo'd name), so a caller can just skip it.
---@param name string ox_inventory item name
local function realItemOption(name)
  local label = Bridge.GetItemLabel(name)
  if not label then return nil end

  local badges
  for _, category in ipairs(Bridge.GetConsumableBadges(name) or {}) do
    local style = BADGE_STYLE[category]
    if style then
      badges = badges or {}
      badges[#badges + 1] = style
    end
  end

  return {
    name = 'osm:test:consumables:' .. name,
    label = label,
    badges = badges,
    -- Real consumption, not an announcement: useItem takes a slot, not a
    -- bare name (see modules/inventory/client.lua's Search('slots', ...)),
    -- so the actual slot is looked up on select rather than cached -- the
    -- player could pick one up or use their last one between menu opens.
    -- If it plays out (anim, hunger/thirst,
    -- vice_hud.restoreStamina*/restoreFocus*/health_items.* and all), that's
    -- proof the badge shown here matches what the item actually does. If the
    -- player doesn't have one, ox_inventory's own notify says so.
    onSelect = function()
      local ok, slots = pcall(function() return exports.ox_inventory:Search('slots', name) end)
      local slot = ok and slots and slots[1]
      if slot then
        exports.ox_inventory:useItem(slot)
      else
        Bridge.Notify(("You don't have a %s"):format(label), 'error')
      end
    end,
  }
end

---Generate consumables test options: real food/drink/medkit items pulled
---straight out of ox_inventory, badges computed from what they actually
---restore -- proof the badge wiring tracks real item data instead of a
---hand-typed fixture. 'ifaks' is included deliberately badge-less (no
---client.export on that item) as the contrast case. Falls back to a single
---notice row if ox_inventory isn't running.
local function consumablesOptions()
  local names = { 'sandwich', 'green_tea', 'medikit', 'ifaks' }
  local options = {}

  for _, name in ipairs(names) do
    local option = realItemOption(name)
    if option then options[#options + 1] = option end
  end

  if #options == 0 then
    return {
      {
        name = 'osm:test:consumables:none',
        label = 'ox_inventory is not running',
        canInteract = function() return false end,
      },
    }
  end

  return options
end

local function removeTestSubject()
  if not testPed then return false end

  if DoesEntityExist(testPed) then
    Api.removeLocalEntity(testPed)
    DeleteEntity(testPed)
  end

  testPed = nil
  return true
end

---Spawn test subject: create test ped carrying representative options.
---@param variant string? 'fridge' | 'car' | 'consumables' | standard
function Debug.spawnTestSubject(variant)
  removeTestSubject()

  local model = `a_m_m_business_01`
  if not lib.requestModel(model, 10000) then
    Bridge.Notify(Locale('test_failed'), 'error')
    return
  end

  local spot = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 1.8, 0.0)
  local found, ground = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 1.0, false)
  local z = found and ground or spot.z

  testPed = CreatePed(4, model, spot.x, spot.y, z, GetEntityHeading(cache.ped) + 180.0, false, false)
  SetModelAsNoLongerNeeded(model)

  if not testPed or testPed == 0 then
    testPed = nil
    Bridge.Notify(Locale('test_failed'), 'error')
    return
  end

  SetEntityInvincible(testPed, true)
  SetBlockingOfNonTemporaryEvents(testPed, true)
  FreezeEntityPosition(testPed, true)
  SetPedCanRagdoll(testPed, false)
  SetPedDiesWhenInjured(testPed, false)

  local options = testOptions()
  if variant == 'fridge' then options = fridgeOptions()
  elseif variant == 'car' then options = carOptions()
  elseif variant == 'consumables' then options = consumablesOptions() end
  Api.addLocalEntity(testPed, options)
  Bridge.Notify(Locale('test_spawned', Config.Commands.test), 'success')
end

RegisterNetEvent('osm-target:cl:testSubject', function(enabled, variant)
  if enabled then
    Debug.spawnTestSubject(variant)
  elseif removeTestSubject() then
    Bridge.Notify(Locale('test_removed'), 'inform')
  else
    Bridge.Notify(Locale('test_none'), 'error')
  end
end)

-- Clean up test ped: delete spawned entity on resource stop
AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  removeTestSubject()
end)
