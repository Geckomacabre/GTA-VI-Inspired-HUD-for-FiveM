local Resolver = OsmTargetResolver

Hit = {}

-- Shapetest collider masks, named from eTraceFlags (see the native reference
-- for START_SHAPE_TEST_LOS_PROBE). The values are disjoint bits, so summing
-- them is the same as OR-ing them and reads better in a constant.
local INTERSECT_WORLD   = 1
local INTERSECT_VEHICLE = 2
local INTERSECT_PED     = 4
local INTERSECT_RAGDOLL = 8
local INTERSECT_OBJECT  = 16

local FLAGS = 511      -- INCLUDE_ALL
local IGNORE = 4       -- NO_COLLISION

-- Second-pass mask: entities only. Leaving INTERSECT_WORLD out is the whole
-- trick -- the ray then travels through glass, railings, fences and thin map
-- geometry to reach whatever is behind them, which a 511 ray stops short of.
local FLAGS_ENTITIES = INTERSECT_VEHICLE + INTERSECT_PED + INTERSECT_RAGDOLL + INTERSECT_OBJECT

-- What counts as genuinely blocking for the line-of-sight re-check that keeps
-- the second pass honest: world geometry and solid props, deliberately NOT
-- glass (64) or foliage (256), since seeing through a shop window is the point.
-- 17 is also the trace type Rockstar's own scripts use most.
local LOS_BLOCKERS = INTERSECT_WORLD + INTERSECT_OBJECT

---Resolve what a raycast landed on.
---@return number entity 0 when nothing usable was hit
---@return number entityType 0 when the handle is not a live entity
---@return number? model
---@return vector3? offset hit point in entity-local space
local function describeHit(entity, coords)
  if not entity or entity == 0 then return 0, 0, nil, nil end

  local ok, entityType = pcall(GetEntityType, entity)
  entityType = ok and entityType or 0
  if entityType <= 0 then return 0, 0, nil, nil end

  local model
  local okModel, resultModel = pcall(GetEntityModel, entity)
  if okModel then model = resultModel end

  local offset
  if coords then
    local okOffset, resultOffset =
      pcall(GetOffsetFromEntityGivenWorldCoords, entity, coords.x, coords.y, coords.z)
    if okOffset then offset = resultOffset end
  end

  return entity, entityType, model, offset
end

---Whether the player can actually see an entity the see-through pass reached,
---rather than it merely being on the far side of a wall.
local function visible(entity)
  local ok, clear = pcall(HasEntityClearLosToEntity, entity, cache.ped, LOS_BLOCKERS)
  return ok and clear == true
end

---Scan interaction raycast: perform camera raycast to detect targeted entity.
---@return table? target
function Hit.scan()
  local origin = GetEntityCoords(cache.ped)
  local reach = Config.Interaction.raycastDistance

  local hit, rawEntity, coords = lib.raycast.fromCamera(FLAGS, IGNORE, reach)
  local entity, entityType, model, offset = describeHit(rawEntity, coords)

  -- See-through pass. The primary ray stopped on world geometry or on nothing,
  -- so a ped behind a shop window, an ATM behind a security grille or a car
  -- behind a fence is unreachable right now. Re-cast for entities only and
  -- adopt that hit instead -- gated on line of sight, so this reaches through
  -- a window but never through a wall.
  --
  -- Run only on the miss, not every frame: an unconditional second probe would
  -- make the two passes disagree from tick to tick and flicker the target.
  if entityType == 0 and Config.Interaction.seeThrough ~= false then
    local throughHit, throughEntity, throughCoords = lib.raycast.fromCamera(FLAGS_ENTITIES, IGNORE, reach)

    if throughEntity and throughEntity ~= 0 and throughCoords and visible(throughEntity) then
      local seenEntity, seenType, seenModel, seenOffset = describeHit(throughEntity, throughCoords)

      if seenType > 0 then
        hit, coords = throughHit, throughCoords
        entity, entityType, model, offset = seenEntity, seenType, seenModel, seenOffset
      end
    end
  end

  return {
    hit = hit,
    entity = entity,
    entityType = entityType,
    model = model,
    coords = coords,
    offset = offset,
    -- Measured against the hit point actually being reported, which is the
    -- see-through point when that pass won.
    distance = #(origin - coords),
  }
end

local BONE_TOLERANCE = 2.0

local EMPTY = {}

---Bone names by model, then bone index, recorded as makeSpatial matches them.
---There is no native going from index back to name, and Hit.parts needs the
---name to know door_dside_f and window_lf are the same door.
---@type table<number, table<number, string>>
local boneNames = {}

---Resolve hit point: re-project the hit through the entity's own offset, so a
---moving vehicle keeps the point on the panel that was actually hit.
---@return vector3
local function hitPoint(target)
  local coords = target.coords
  if target.entity and target.entity ~= 0 and DoesEntityExist(target.entity) and target.offset then
    local ok, worldCoords = pcall(GetOffsetFromEntityInWorldCoords, target.entity, target.offset.x, target.offset.y, target.offset.z)
    if ok and worldCoords then coords = worldCoords end
  end
  return coords
end

---World position of an option's offset: model-relative unless absoluteOffset.
---@return vector3
local function offsetWorld(entity, model, option)
  local offset = option.offset
  if not option.absoluteOffset then
    local minimum, maximum = GetModelDimensions(model)
    offset = (maximum - minimum) * offset + minimum
  end

  return GetOffsetFromEntityInWorldCoords(entity, offset.x, offset.y, offset.z)
end

---Create spatial attachment evaluator: verify bone or model offset matching for hit target.
function Hit.makeSpatial(target)
  local entity = target.entity
  local endCoords = hitPoint(target)

  local names = EMPTY
  if target.model then
    names = boneNames[target.model]
    if not names then
      names = {}
      boneNames[target.model] = names
    end
  end

  return function(option)
    if entity == 0 then return false end

    if option.bones then
      local bones = option.bones
      if type(bones) == 'string' then bones = { bones } end

      local bestId, bestDistance
      for i = 1, #bones do
        local boneId = GetEntityBoneIndexByName(entity, bones[i])
        if boneId ~= -1 then
          names[boneId] = bones[i]
          local distance = #(endCoords - GetEntityBonePosition_2(entity, boneId))
          if distance <= BONE_TOLERANCE and (not bestDistance or distance < bestDistance) then
            bestId, bestDistance = boneId, distance
          end
        end
      end

      if not bestId then return false end
      if not option.offset then return true, bestId end
    end

    if option.offset then
      if not target.model then return false end

      local world = offsetWorld(entity, target.model, option)
      if #(endCoords - world) > (option.offsetSize or 1.0) then return false end
    end

    return true
  end
end

---Create interaction predicate runner: execute canInteract safely within pcall wrapper.
function Hit.makeInteract(target)
  local coords = hitPoint(target)

  return function(option, distance, bone)
    local ok, allowed, reason = pcall(option.canInteract,
      target.entity ~= 0 and target.entity or nil, distance, coords, option.name, bone)
    if not ok then return false end
    return allowed, reason
  end
end

---Build resolution context: assemble player state, spatial checker, and interaction runner.
function Hit.context(target, menu)
  return {
    distance = target.distance,
    entity = target.entity ~= 0 and target.entity or nil,
    coords = hitPoint(target),
    menu = menu,
    player = Player.state(),
    policy = Config.Options,
    spatial = Hit.makeSpatial(target),
    interact = Hit.makeInteract(target),
  }
end

---@return table[] resolved, table candidates
function Hit.resolve(target, menu)
  local candidates

  if target.zone then
    candidates = Store.candidatesForZone(target.zone, target.distance)
  else
    candidates = Store.candidatesForEntity(target.entity, target.entityType, target.model, target.distance)
  end

  return Resolver.resolve(candidates, Hit.context(target, menu)), candidates
end

---Split resolved options by the physical part of the entity they are anchored
---to, nearest the crosshair first.
---
---Bones match anywhere within BONE_TOLERANCE of the hit point, which on a car
---is wide enough that looking at the driver window also matches the front
---tire: wasabi_tireslash's Slash Tire on wheel_lf landed in the same list as
---qbx_vehiclekeys' Slim Jim / Smash Window, and the menu anchored on whichever
---had registered first. Only one part is shown at a time (machine.lua), and
---Config.Input.cyclePart steps to the next.
---
---Options with no bone or offset belong to the entity as a whole and are kept
---in every part. Order inside a part is the resolved order, which is what `num`
---sorted.
---@return { key: string?, distance: number?, entries: table[] }[] parts
function Hit.parts(target, resolved)
  local settings = Config.Parts
  local entity = target.entity
  if not (settings and settings.enabled) or #resolved < 2
    or not entity or entity == 0 or not DoesEntityExist(entity)
  then
    return { { entries = resolved } }
  end

  local hit = hitPoint(target)
  local names = target.model and boneNames[target.model] or EMPTY
  local aliases = settings.aliases or EMPTY
  local keys, parts, byKey = {}, {}, {}

  for i = 1, #resolved do
    local entry = resolved[i]
    local option = entry.option
    local key, point

    if entry.bone then
      local name = names[entry.bone]
      key = name and aliases[name] or name or ('bone:' .. entry.bone)
      point = GetEntityBonePosition_2(entity, entry.bone)
    elseif option.offset and target.model then
      local offset = option.offset
      key = ('offset:%s:%.3f:%.3f:%.3f'):format(option.absoluteOffset and 'abs' or 'rel', offset.x, offset.y, offset.z)
      point = offsetWorld(entity, target.model, option)
    end

    if key then
      keys[i] = key
      local distance = #(hit - point)
      local part = byKey[key]
      if not part then
        part = { key = key, distance = distance, entries = {} }
        byKey[key] = part
        parts[#parts + 1] = part
      elseif distance < part.distance then
        part.distance = distance
      end
    end
  end

  if #parts < 2 then
    return { { key = parts[1] and parts[1].key, entries = resolved } }
  end

  for i = 1, #resolved do
    local key = keys[i]
    for j = 1, #parts do
      local part = parts[j]
      if key == nil or key == part.key then
        part.entries[#part.entries + 1] = resolved[i]
      end
    end
  end

  table.sort(parts, function(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.key < b.key
  end)

  return parts
end

---Calculate world anchor: resolve bone coordinate, model bounding center, or zone position.
---@return vector3
function Hit.anchor(target, resolved)
  if target.entity and target.entity ~= 0 and DoesEntityExist(target.entity) then
    if resolved then
      for i = 1, #resolved do
        local bone = resolved[i].bone
        if bone then
          return GetWorldPositionOfEntityBone(target.entity, bone)
        end
      end

      -- An offset-anchored part (bonnet, trunk) sits on its own offset rather
      -- than the model centre, so stepping between parts visibly moves the menu.
      if target.model then
        for i = 1, #resolved do
          local option = resolved[i].option
          if option.offset then
            return offsetWorld(target.entity, target.model, option)
          end
        end
      end
    end

    return Discovery.entityAnchor(target.entity, target.model)
  end

  if target.zone then return target.zone.coords end

  return target.coords
end

---Calculate interaction distance: measure physical distance to bone, surface contact point, or anchor.
---@param target table
---@param anchor vector3?
---@param resolved table[]?
---@return number
function Hit.distance(target, anchor, resolved)
  local origin = GetEntityCoords(cache.ped)

  if resolved then
    for i = 1, #resolved do
      local bone = resolved[i].bone
      if bone and target.entity and target.entity ~= 0 and DoesEntityExist(target.entity) then
        local boneCoords = GetWorldPositionOfEntityBone(target.entity, bone)
        if boneCoords then return #(origin - boneCoords) end
      end
    end
  end

  if target.entity and target.entity ~= 0 and DoesEntityExist(target.entity) and target.offset then
    local ok, worldCoords = pcall(GetOffsetFromEntityInWorldCoords, target.entity, target.offset.x, target.offset.y, target.offset.z)
    if ok and worldCoords then
      return #(origin - worldCoords)
    end
  end

  if anchor then
    return #(origin - anchor)
  end

  if target.coords then
    return #(origin - target.coords)
  end

  return 0.0
end

---Calculate distance scale factor: compute non-linear scale multiplier based on target distance.
---@return number
function Hit.scaleFor(distance)
  local render = Config.Render
  if distance <= 0.01 then return render.scaleMax end

  local ratio = render.referenceDistance / distance
  local scale = ratio ^ render.scaleExponent

  if scale < render.scaleMin then return render.scaleMin end
  if scale > render.scaleMax then return render.scaleMax end
  return scale
end
