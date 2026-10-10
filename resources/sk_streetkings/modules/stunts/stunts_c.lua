-- Stunt jumps, ported from streetkings modules/stunts/stunt_jump_c.lua.
--
-- A jump is a pair of zones. Enter one at speed, leave the ground, and the
-- module tracks yaw, barrel rolls and air distance until the car settles. Land
-- clean inside the other zone and the run scores.
--
-- Jumps come from two places, merged at startup: `data/stunt_jumps.lua` (hand
-- written) and the `sk_stunt_jumps` table (placed in-game with `/stuntdev`).
--
-- Changes from upstream:
--   * Upstream posted the score to its daily-events system and then opened two
--     NUI panels (results, then a leaderboard). That system is not ported, so
--     scoring goes to `sk_activity_scores` and the result is a timed SKHud
--     readout — it reports the same numbers without taking the screen.
--   * The airborne debug print is dropped.

if not Config.Modules.stunts then return end

local MPS_TO_MPH           = 2.236936
local MIN_LAUNCH_SPEED_MPH = 15.0
local COOLDOWN_MS          = 3000

-- How long the player has after touching a zone for a launch to still count as
-- coming off that zone.
local ZONE_VISIT_WINDOW_MS  = 5000
local ZONE_EXIT_GRACE_MS    = 1000
local LANDING_ZONE_GRACE_MS = 2000

-- Landing detection. The car has to sit on all four wheels for LANDING_GRACE_MS
-- to count as clean; brief airborne flickers over bumps are forgiven.
local LANDING_GRACE_MS     = 500
local SETTLE_TIMEOUT_MS    = 3000
local AIR_FLICKER_GRACE_MS = 200

local RESULTS_MS = 7000

local activeJumps   = {}
local cooldowns     = {}
local attemptActive = false
local jumpsActive   = false

-- ── Scoring ─────────────────────────────────────────────────────────────────

local SPIN_TIERS = {
    { threshold = 540, bonus = 200 },
    { threshold = 360, bonus = 120 },
    { threshold = 160, bonus = 60  },
    { threshold = 95,  bonus = 25  },
}
local BARREL_ROLL_BONUS = 150

---@param a number
---@return number the angle wrapped to (-180, 180]
local function normalizeAngle(a)
    a = a % 360.0
    if a > 180.0 then a = a - 360.0 end
    if a < -180.0 then a = a + 360.0 end
    return a
end

---@param yawDeg number total yaw swept while airborne
---@param rollDeg number total roll swept while airborne
---@return integer bonus, integer barrelRolls
local function calculateTrickBonus(yawDeg, rollDeg)
    local bonus = 0
    for _, tier in ipairs(SPIN_TIERS) do
        if yawDeg >= tier.threshold then
            bonus = tier.bonus
            break
        end
    end
    local barrelRolls = math.floor(rollDeg / 360.0)
    return bonus + barrelRolls * BARREL_ROLL_BONUS, barrelRolls
end

---@return table
local function calculateScore(launchSpeed, totalYaw, totalRoll, airDistance)
    local base       = 15
    local speedBonus = math.floor(launchSpeed * 0.35)
    local distBonus  = math.floor(airDistance * 0.6)
    local trickBonus, barrelRolls = calculateTrickBonus(totalYaw, totalRoll)

    return {
        base      = base,
        speed     = speedBonus,
        trick     = trickBonus,
        distance  = distBonus,
        total     = base + speedBonus + trickBonus + distBonus,
        rawBarrel = barrelRolls,
        rawSpeed  = launchSpeed,
        rawDist   = airDistance,
    }
end

-- ── Result readout ──────────────────────────────────────────────────────────

local P = SKHud.Palette
local RESULT = SKHud.Anchor.centreLow

SKHud.register('stuntresult', function(data)
    SKHud.Panel(RESULT.x, RESULT.y, 0.310, 0.162, P.panelDark)
    SKHud.Text(data.name or 'Stunt Jump', RESULT.x, RESULT.y - 0.074, 0.32, P.textDim, true)
    SKHud.Text(('%d'):format(data.score.total), RESULT.x, RESULT.y - 0.054, 0.80, P.accent, true)
    SKHud.Text(data.breakdown, RESULT.x, RESULT.y + 0.002, 0.30, P.text, true)
    if data.summary then
        SKHud.Text(data.summary, RESULT.x, RESULT.y + 0.025, 0.30, P.success, true)
    end
    SKHud.Text(('[%s] dismiss'):format(SKInput.getInteractLabel()), RESULT.x, RESULT.y + 0.050, 0.26, P.textDim, true)
end)

---@param score table
---@return string
local function formatBreakdown(score)
    local parts = { ('SPEED +%d'):format(score.speed) }
    if score.trick > 0 then
        parts[#parts + 1] = ('TRICK +%d'):format(score.trick)
    end
    parts[#parts + 1] = ('AIR +%d'):format(score.distance)
    if score.rawBarrel > 0 then
        parts[#parts + 1] = ('%d BARREL ROLL%s'):format(score.rawBarrel, score.rawBarrel > 1 and 'S' or '')
    end
    return table.concat(parts, '   ')
end

---@param def table
---@param score table
---@param result table|nil server response
local function showResult(def, score, result)
    SKHud.set('stuntresult', {
        name      = def.name,
        score     = score,
        breakdown = formatBreakdown(score),
        summary   = result and result.summary or nil,
    })

    local deadline = GetGameTimer() + RESULTS_MS
    while GetGameTimer() < deadline do
        if SKInput.isInteractJustReleased() then break end
        if SKC.GetGameState() ~= GameState.FREEROAM then break end
        Wait(0)
    end

    SKHud.clear('stuntresult')
end

-- ── Definition normalising ──────────────────────────────────────────────────
--
-- Jumps saved by the devtool can carry box zones; everything downstream works
-- in spheres, so they are flattened on load.

local function toVec3(v)
    if type(v) == 'vector3' then return v end
    if type(v) == 'table' then
        if v.x  then return vector3(v.x,  v.y,  v.z)  end
        if v[1] then return vector3(v[1], v[2], v[3]) end
    end
    return v
end

local function normalizeZone(zone)
    if not zone then return nil end
    zone.center = toVec3(zone.center)
    if zone.shape == 'box' and zone.size then
        local sz = toVec3(zone.size)
        zone.radius = math.max(sz.x, sz.y) * 0.5
        zone.shape, zone.size, zone.rotation = nil, nil, nil
    end
    if zone.ramp and zone.ramp.coords then
        zone.ramp.coords = toVec3(zone.ramp.coords)
    end
    return zone
end

local function normalizeDef(def)
    if def.zoneA then normalizeZone(def.zoneA) end
    if def.zoneB then normalizeZone(def.zoneB) end
    return def
end

-- ── Airborne tracking ───────────────────────────────────────────────────────

---@param jumpId string
---@param def table
---@param state table
---@param vehicle integer
---@param ped integer
local function runAirborneTracking(jumpId, def, state, vehicle, ped)
    local launchZoneKey = state.lastVisitedZone
    local targetZone    = launchZoneKey == 'a' and def.zoneB or def.zoneA
    local targetCenter  = targetZone.center
    local targetRadius  = targetZone.radius or 10.0

    local launchSpeed = state.launchSpeed
    local launchPos   = GetEntityCoords(vehicle)

    local prevHeading   = GetEntityHeading(vehicle)
    local prevRoll      = GetEntityRoll(vehicle)
    local totalYaw      = 0.0
    local totalRoll     = 0.0
    local phase         = 'air'
    local cleanLanding  = false
    local crashDetected = false
    local settleStart   = nil
    local wheelsAccum   = 0
    local lastWheelsTime = nil
    local airGapStart   = nil

    while true do
        if SKC.GetGameState() ~= GameState.FREEROAM then
            state.phase = 'idle'
            state.lastVisitedZone = nil
            attemptActive = false
            return
        end

        if IsEntityDead(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= ped then break end

        local now      = GetGameTimer()
        local onWheels = IsVehicleOnAllWheels(vehicle)
        local grounded = not IsEntityInAir(vehicle) or onWheels

        if IsEntityUpsidedown(vehicle) then
            crashDetected = true
        end

        -- Rotation is swept in both phases, so a spin that finishes just after
        -- the wheels touch still counts.
        local heading = GetEntityHeading(vehicle)
        local roll    = GetEntityRoll(vehicle)
        totalYaw    = totalYaw + math.abs(normalizeAngle(heading - prevHeading))
        totalRoll   = totalRoll + math.abs(normalizeAngle(roll - prevRoll))
        prevHeading = heading
        prevRoll    = roll

        if phase == 'air' then
            if grounded then
                phase          = 'settling'
                settleStart    = now
                wheelsAccum    = 0
                lastWheelsTime = onWheels and now or nil
                airGapStart    = nil
            end
        elseif phase == 'settling' then
            if grounded then
                airGapStart = nil
                if onWheels then
                    if lastWheelsTime then
                        wheelsAccum = wheelsAccum + (now - lastWheelsTime)
                    end
                    lastWheelsTime = now
                else
                    lastWheelsTime = nil
                end
            else
                lastWheelsTime = nil
                if not airGapStart then
                    airGapStart = now
                elseif now - airGapStart > AIR_FLICKER_GRACE_MS then
                    -- Back in the air for real: this was a bounce, not a landing.
                    phase       = 'air'
                    settleStart = nil
                    wheelsAccum = 0
                    airGapStart = nil
                end
            end

            if wheelsAccum >= LANDING_GRACE_MS then
                cleanLanding = true
                break
            end
            if settleStart and now - settleStart > SETTLE_TIMEOUT_MS then
                break
            end
        end

        DrawMarker(1, targetCenter.x, targetCenter.y, targetCenter.z, 0, 0, 0, 0, 0, 0,
            targetRadius * 2, targetRadius * 2, 1.0, 0, 200, 255, 80, false, true, 2, false, nil, nil, false)

        Wait(0)
    end

    local now = GetGameTimer()
    local inTarget
    if launchZoneKey == 'a' then
        inTarget = state.inZoneB or (state.exitTimeB and (now - state.exitTimeB) < LANDING_ZONE_GRACE_MS)
    else
        inTarget = state.inZoneA or (state.exitTimeA and (now - state.exitTimeA) < LANDING_ZONE_GRACE_MS)
    end
    if not inTarget then
        inTarget = #(GetEntityCoords(vehicle) - targetCenter) < targetRadius
    end

    local alive = not IsEntityDead(vehicle) and GetPedInVehicleSeat(vehicle, -1) == ped

    cooldowns[jumpId]     = GetGameTimer() + COOLDOWN_MS
    state.phase           = 'idle'
    state.lastVisitedZone = nil
    state.wasGrounded     = false

    if not inTarget or not alive or crashDetected or not cleanLanding then
        attemptActive = false
        return
    end

    local airDistance = #(GetEntityCoords(vehicle) - launchPos)
    local score = calculateScore(launchSpeed, totalYaw, totalRoll, airDistance)

    local result = lib.callback.await(
        'sk_streetkings:stunts:submit', false,
        jumpId, score.total, SK.GetVehicleModelLabel(vehicle)
    )

    showResult(def, score, result)
    attemptActive = false
end

-- ── Jump setup ──────────────────────────────────────────────────────────────

---@param rampDef table|nil
---@return integer|nil prop
local function spawnRampProp(rampDef)
    if not rampDef or not rampDef.model or not rampDef.coords then return nil end

    local hash = SK.LoadModel(rampDef.model, 10000)
    if not hash then
        lib.print.warn(('stunt jump ramp model failed to load: %s'):format(tostring(rampDef.model)))
        return nil
    end

    local c = rampDef.coords
    local obj = CreateObjectNoOffset(hash, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(obj, rampDef.heading or 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SK.UnloadModel(hash)
    return obj
end

---@param jumpId string
local function teardownJump(jumpId)
    local entry = activeJumps[jumpId]
    if not entry then return end

    if entry.outerPoint then entry.outerPoint:remove() end
    if entry.innerZoneA then entry.innerZoneA:remove() end
    if entry.innerZoneB then entry.innerZoneB:remove() end

    for i = 1, #entry.props do
        if DoesEntityExist(entry.props[i]) then DeleteEntity(entry.props[i]) end
    end

    if entry.blip and DoesBlipExist(entry.blip) then RemoveBlip(entry.blip) end

    activeJumps[jumpId] = nil
end

---@param jumpId string
---@param def table
local function setupJump(jumpId, def)
    if activeJumps[jumpId] then teardownJump(jumpId) end
    if not def.zoneA or not def.zoneB then return end
    if not def.zoneA.center or not def.zoneB.center then return end

    normalizeDef(def)

    local props = {}
    local propA = spawnRampProp(def.zoneA.ramp)
    if propA then props[#props + 1] = propA end
    local propB = spawnRampProp(def.zoneB.ramp)
    if propB then props[#props + 1] = propB end

    local ac, bc = def.zoneA.center, def.zoneB.center

    local blip = SK.CreateBlip(Config.Blips.stuntJump, ac, def.name)

    local radiusA = def.zoneA.radius or 10.0
    local radiusB = def.zoneB.radius or 10.0

    local state = {
        inZoneA         = false,
        inZoneB         = false,
        exitTimeA       = nil,
        exitTimeB       = nil,
        lastVisitedZone = nil,
        lastVisitTime   = 0,
        launchSpeed     = 0,
        phase           = 'idle',
        wasGrounded     = false,
    }

    local innerZoneA = lib.zones.sphere({
        coords  = ac,
        radius  = radiusA,
        onEnter = function()
            state.inZoneA         = true
            state.lastVisitedZone = 'a'
            state.lastVisitTime   = GetGameTimer()
        end,
        onExit = function()
            state.inZoneA   = false
            state.exitTimeA = GetGameTimer()
        end,
    })

    local innerZoneB = lib.zones.sphere({
        coords  = bc,
        radius  = radiusB,
        onEnter = function()
            state.inZoneB         = true
            state.lastVisitedZone = 'b'
            state.lastVisitTime   = GetGameTimer()
        end,
        onExit = function()
            state.inZoneB   = false
            state.exitTimeB = GetGameTimer()
        end,
    })

    -- One point covering both ends, so the per-frame launch check only runs
    -- when the player is actually near the jump.
    local halfDist    = #(ac - bc) / 2
    local outerRadius = halfDist + math.max(radiusA, radiusB) + 50.0

    local outerPoint = lib.points.new({
        coords   = vector3((ac.x + bc.x) / 2, (ac.y + bc.y) / 2, (ac.z + bc.z) / 2),
        distance = outerRadius,
        onEnter  = function()
            if state.phase == 'idle' then
                state.lastVisitedZone = nil
            end
        end,
        nearby = function()
            if state.phase ~= 'idle' then return end
            if attemptActive or Cinematic then return end
            if SKC.GetGameState() ~= GameState.FREEROAM then return end

            local now = GetGameTimer()
            if cooldowns[jumpId] and now < cooldowns[jumpId] then return end
            if not state.lastVisitedZone then return end
            if (now - state.lastVisitTime) > ZONE_VISIT_WINDOW_MS then return end

            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 then return end

            local speed = GetEntitySpeed(veh) * MPS_TO_MPH

            local recentlyInZone = state.inZoneA or state.inZoneB
                or (state.exitTimeA and (now - state.exitTimeA) < ZONE_EXIT_GRACE_MS)
                or (state.exitTimeB and (now - state.exitTimeB) < ZONE_EXIT_GRACE_MS)

            if not IsEntityInAir(veh) then
                -- Still on the ramp. Remember the speed so the launch value is
                -- the speed leaving the ground, not mid-flight.
                if speed >= MIN_LAUNCH_SPEED_MPH and recentlyInZone then
                    state.wasGrounded = true
                    state.launchSpeed = speed
                end
                return
            end

            if not state.wasGrounded then
                if speed < MIN_LAUNCH_SPEED_MPH then return end
                state.launchSpeed = speed
            end

            state.phase   = 'airborne'
            attemptActive = true

            CreateThread(function()
                local ok, err = pcall(runAirborneTracking, jumpId, def, state, veh, ped)
                if not ok then
                    lib.print.error(('stunt jump %s: %s'):format(jumpId, tostring(err)))
                    SKHud.clear('stuntresult')
                    state.phase       = 'idle'
                    state.wasGrounded = false
                    attemptActive     = false
                end
            end)
        end,
    })

    activeJumps[jumpId] = {
        def        = def,
        outerPoint = outerPoint,
        innerZoneA = innerZoneA,
        innerZoneB = innerZoneB,
        state      = state,
        props      = props,
        blip       = blip,
    }
end

local function clearAllJumps()
    for jumpId in pairs(activeJumps) do teardownJump(jumpId) end
    cooldowns = {}
end

local function setupAllJumps()
    clearAllJumps()

    -- Devtool-placed jumps are merged over the hand-written ones in
    -- data/stunt_jumps.lua, so an id defined in both takes the DB version.
    local dbJumps = lib.callback.await('sk_streetkings:stunts:load', false)
    SKStuntJumps = SKStuntJumps or {}
    if dbJumps then
        for id, def in pairs(dbJumps) do
            def.id = def.id or id
            SKStuntJumps[id] = def
        end
    end

    for id, def in pairs(SKStuntJumps) do
        setupJump(id, def)
    end
end

-- ── Devtool sync ────────────────────────────────────────────────────────────

RegisterNetEvent('sk_streetkings:stunts:sync', function(jumpId, def)
    SKStuntJumps = SKStuntJumps or {}
    SKStuntJumps[jumpId] = def
    if jumpsActive then setupJump(jumpId, def) end
end)

RegisterNetEvent('sk_streetkings:stunts:removed', function(jumpId)
    teardownJump(jumpId)
    if SKStuntJumps then SKStuntJumps[jumpId] = nil end
end)

-- ── Lifecycle ───────────────────────────────────────────────────────────────
--
-- Jumps only exist in freeroam: the props and zones would otherwise sit in the
-- middle of a race route or the car meet.

CreateThread(function()
    SK.WaitForControl()
    Wait(500)
    while true do
        if SKC.GetGameState() == GameState.FREEROAM then
            if not jumpsActive then
                jumpsActive = true
                setupAllJumps()
            end
        elseif jumpsActive then
            jumpsActive = false
            clearAllJumps()
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearAllJumps() end
end)

-- Used by the /stuntdev placement tool to preview a jump before saving it.
exports('SetupTestJump', function(id, def) setupJump(id, def) end)
exports('TeardownTestJump', function(id) teardownJump(id) end)
