--[[
    Runs the ball physics for every loose ball this client owns.

    client/physics.lua knows how a ball moves. This file is the other half: it
    answers the physics' questions about the world with the game's own collision
    and water, moves the entity to where the physics says it is, and turns what
    happened to the ball (a bounce, the rim, the net, a splash) into sound.

    The ball entity itself is inert while it's simulated: no collision, no engine
    gravity. Everything it does, it does because physics.lua said so. That is what
    lets it have a rim that behaves like a rim and water that it floats in --
    neither of which the game's own prop physics will give a basketball.

    Ownership
    ---------
    Whoever owns the network entity simulates it. If the game hands a ball to
    another client (its owner walked off), that client picks it up from the
    entity's position and velocity and carries on.
]]

local P = BB.physics

BB.sim = {}

local cfg = Config.Physics
local prm = P.params(cfg)

prm.radius = Config.Ball.radius
prm.gravity = Config.Gravity
prm = P.params(prm)

BB.sim.prm = prm

local sims = {}             -- [entity] = { ent, ball, bodies = {} }
local running = false

--------------------------------------------------------------------------------
-- Surfaces
--------------------------------------------------------------------------------

-- GTA's collision materials (materials.dat), sorted onto how a ball behaves on
-- them. Anything not listed is hard ground. Values are in Config.Physics.surfaces.
local SURFACE_OF = {}

for kind, names in pairs({
    wood = { 'WOOD_SOLID_SMALL', 'WOOD_SOLID_MEDIUM', 'WOOD_SOLID_LARGE', 'WOOD_SOLID_POLISHED', 'WOOD_FLOOR_DUSTY',
             'WOOD_HOLLOW_SMALL', 'WOOD_HOLLOW_MEDIUM', 'WOOD_HOLLOW_LARGE', 'WOOD_CHIPBOARD', 'WOOD_OLD_CREAKY',
             'WOOD_HIGH_DENSITY', 'WOOD_HIGH_FRICTION', 'LAMINATE', 'LINOLEUM' },
    metal = { 'METAL_SOLID_SMALL', 'METAL_SOLID_MEDIUM', 'METAL_SOLID_LARGE', 'METAL_HOLLOW_SMALL',
              'METAL_HOLLOW_MEDIUM', 'METAL_HOLLOW_LARGE', 'METAL_CORRUGATED_IRON', 'METAL_GRILLE', 'METAL_RAILING',
              'METAL_DUCT', 'METAL_GARAGE_DOOR', 'METAL_MANHOLE', 'METAL_SOLID_ROAD_SURFACE', 'CAR_METAL' },
    fence = { 'METAL_CHAINLINK_SMALL', 'METAL_CHAINLINK_LARGE', 'WOOD_LATTICE', 'PHYS_BARBED_WIRE' },
    grass = { 'GRASS_SHORT', 'GRASS', 'WOODCHIPS', 'CARPET_SOLID', 'CARPET_SOLID_DUSTY', 'CARPET_FLOORBOARD',
              'ROOF_FELT', 'TARPAULIN', 'CLOTH', 'RUBBER' },
    dirt = { 'DIRT_TRACK', 'MUD_HARD', 'SAND_COMPACT', 'SAND_TRACK', 'CLAY_HARD', 'GRAVEL_SMALL',
             'GRAVEL_TRAIN_TRACK', 'GRAVEL_LARGE' },
    sand = { 'SAND_LOOSE', 'SAND_WET', 'SAND_UNDERWATER', 'SAND_DRY_DEEP', 'SAND_WET_DEEP', 'GRAVEL_DEEP' },
    soft = { 'GRASS_LONG', 'MUD_POTHOLE', 'MUD_SOFT', 'MUD_UNDERWATER', 'MUD_DEEP', 'MARSH', 'MARSH_DEEP', 'SOIL',
             'CLAY_SOFT', 'SNOW_LOOSE', 'SNOW_COMPACT', 'SNOW_DEEP', 'HAY', 'BUSHES', 'BUSHES_NOINST', 'TWIGS',
             'LEAVES', 'FOAM' },
}) do
    for _, name in ipairs(names) do
        SURFACE_OF[GetHashKey(name) & 0xFFFFFFFF] = kind
    end
end

local function surfaceFor(material)
    if not material then return nil end

    local kind = SURFACE_OF[material & 0xFFFFFFFF]
    return kind and cfg.surfaces[kind] or nil
end

--------------------------------------------------------------------------------
-- The world, as the physics asks about it
--------------------------------------------------------------------------------

local FLAGS = 1 | 2 | 16 | 64   -- map, vehicles, objects, glass. Peds are handled as bodies.

--[[
    What a test is allowed to pass through. The game's usual setting (7) skips
    glass and anything "see-through", which is right for a line of sight and
    wrong for a ball: a chain-link fence is see-through, and so is a glass
    backboard. With those skipped a missed shot sailed through the fence round
    the court and off down the hill. 4 skips only what has no collision at all.
]]
local SOLID = 4

local sqrt = math.sqrt

local function isHit(hit) return hit == 1 or hit == true end

local rimList = {}      -- the rims near the ball being stepped; filled by rimsNear()

--[[
    Is this point inside a basket: under the ring, within it?

    Now that the ball is stopped by see-through things, it would be stopped by a
    net too, on any hoop whose net was given collision, and no shot could ever
    drop. Nothing solid belongs in that space, so whatever a test finds there is
    the net, and the ball's own net (physics.lua) is what deals with it.
]]
local function inNet(x, y, z)
    for i = 1, #rimList do
        local rim = rimList[i]
        local dz = z - rim.z

        if dz < -0.03 and dz > -0.65 then
            local dx, dy = x - rim.x, y - rim.y
            local inner = rim.R - 0.05

            if dx * dx + dy * dy < inner * inner then return true end
        end
    end

    return false
end

--[[
    What the swept-sphere test hands back as "end coords" is the point of contact
    on the thing it hit. The physics wants the centre of the ball at that moment,
    which is one radius back from there, on the path.

    That reading is checked once against a plain ray, in calibrate() below, rather
    than taken on trust. 'centre' is the other possibility; 'ray' is the fallback
    if the swept test turns out not to answer in the same frame on this build.
]]
local sweepMode = nil

local function rayAlong(x1, y1, z1, x2, y2, z2, radius)
    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local len = sqrt(dx * dx + dy * dy + dz * dz)
    if len < 1e-5 then return false end

    local ux, uy, uz = dx / len, dy / len, dz / len
    local reach = len + radius

    local handle = StartExpensiveSynchronousShapeTestLosProbe(x1, y1, z1,
        x1 + ux * reach, y1 + uy * reach, z1 + uz * reach, FLAGS, 0, SOLID)
    local status, hit, pos, normal, material = GetShapeTestResultIncludingMaterial(handle)

    if status ~= 2 or not isHit(hit) then return false end
    if inNet(pos.x, pos.y, pos.z) then return false end

    -- The ball touches the surface before its centre gets there: one radius
    -- back along the surface's normal, which is further back along the path the
    -- more it is glancing.
    local into = -(ux * normal.x + uy * normal.y + uz * normal.z)
    if into < 0.08 then into = 0.08 end

    local along = (pos.x - x1) * ux + (pos.y - y1) * uy + (pos.z - z1) * uz - radius / into
    if along < 0.0 then along = 0.0 end
    if along > len then return false end

    return true, x1 + ux * along, y1 + uy * along, z1 + uz * along, normal.x, normal.y, normal.z, surfaceFor(material)
end

local function sweep(x1, y1, z1, x2, y2, z2, radius)
    if sweepMode == 'ray' then return rayAlong(x1, y1, z1, x2, y2, z2, radius) end

    local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
    local a = dx * dx + dy * dy + dz * dz
    if a < 1e-10 then return false end

    local handle = StartShapeTestSweptSphere(x1, y1, z1, x2, y2, z2, radius, FLAGS, 0, SOLID)
    local status, hit, pos, normal, material = GetShapeTestResultIncludingMaterial(handle)

    if status ~= 2 then return rayAlong(x1, y1, z1, x2, y2, z2, radius) end
    if not isHit(hit) then return false end
    if inNet(pos.x, pos.y, pos.z) then return false end

    local surface = surfaceFor(material)

    if sweepMode == 'centre' then
        return true, pos.x, pos.y, pos.z, normal.x, normal.y, normal.z, surface
    end

    -- Where on the path is the centre exactly one radius from the contact point?
    local fx, fy, fz = x1 - pos.x, y1 - pos.y, z1 - pos.z
    local b = 2.0 * (dx * fx + dy * fy + dz * fz)
    local c = fx * fx + fy * fy + fz * fz - radius * radius
    local disc = b * b - 4.0 * a * c

    if disc >= 0.0 then
        local t = (-b - sqrt(disc)) / (2.0 * a)
        if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end

        local cx, cy, cz = x1 + dx * t, y1 + dy * t, z1 + dz * t
        local nx, ny, nz = cx - pos.x, cy - pos.y, cz - pos.z
        local len = sqrt(nx * nx + ny * ny + nz * nz)

        if len > 1e-4 then
            nx, ny, nz = nx / len, ny / len, nz / len

            -- From contact point to centre is the true normal for a sphere, and
            -- the only right one on an edge or a corner. Believe it unless it
            -- disagrees wildly with the face the game says was hit.
            if nx * normal.x + ny * normal.y + nz * normal.z > 0.25 then
                return true, cx, cy, cz, nx, ny, nz, surface
            end
        end
    end

    return true, pos.x + normal.x * radius, pos.y + normal.y * radius, pos.z + normal.z * radius,
        normal.x, normal.y, normal.z, surface
end

--- Settles what the swept test's result means, against a ray that can't be
--- misread. Needs ground under the player; tries again later if there isn't any.
local function calibrate()
    if sweepMode then return end

    local at = GetEntityCoords(PlayerPedId())
    local radius = 0.2

    local ray = StartExpensiveSynchronousShapeTestLosProbe(at.x, at.y, at.z + 0.6, at.x, at.y, at.z - 4.0, 1, 0, 7)
    local rayStatus, rayHit, rayPos = GetShapeTestResult(ray)
    if rayStatus ~= 2 or not isHit(rayHit) then return end

    local swept = StartShapeTestSweptSphere(at.x, at.y, at.z + 0.6, at.x, at.y, at.z - 4.0, radius, 1, 0, 7)
    local status, hit, pos = GetShapeTestResult(swept)

    if status ~= 2 or not isHit(hit) then
        sweepMode = 'ray'
    elseif pos.z - rayPos.z > radius * 0.6 then
        sweepMode = 'centre'
    else
        sweepMode = 'contact'
    end

    if Config.Debug then
        print(('^2[gk_basketball]^7 sweep calibration: %s (status %s, ray z %.3f, swept z %.3f)')
            :format(sweepMode, status, rayPos.z, pos and pos.z or 0.0))
    end
end

--[[
    Water height at a point, swell included, or nil.

    GET_WATER_HEIGHT covers the sea and everything else drawn from the water map
    (lakes, pools, canals). Rivers and streams are collision water and need the
    probe. Both come back empty over dry land, and asking the second one on every
    step of every ball on a street would be a waste, so a "dry" answer is kept for
    a moment.
]]
local current           -- the sim being stepped, for per-ball caches

local function water(x, y, z)
    local found, height = GetWaterHeight(x, y, z)
    if found then return height end

    local sim = current
    local now = GetGameTimer()

    if sim then
        if sim.dryUntil and now < sim.dryUntil then return nil end
    end

    -- Straight down from above the ball, stopped by the map: a ball on a bridge
    -- is not in the river under it. 1 is "found water"; 2 is "something solid
    -- was in the way first".
    local probed, level = TestVerticalProbeAgainstAllWater(x, y, z + 2.0, 1)
    if probed == 1 and level and level > z - 3.0 then
        return level
    end

    if sim then sim.dryUntil = now + 400 end

    return nil
end

--------------------------------------------------------------------------------
-- Rims
--------------------------------------------------------------------------------

--[[
    Is there already a rim here?

    Some of the map's hoops have collision on the ring and some are only drawn.
    Where the map has one, the swept test above collides with it exactly as built
    and a second, calculated ring a few centimetres off would only narrow the
    hoop. Where it doesn't, ours is the rim.

    Found by dropping a small sphere onto sixteen points round where the ring
    should be. Runs once per hoop, the first time a ball is live near it.
]]
local function probeMapRim(hoop)
    if hoop.rimProbed or sweepMode ~= 'contact' and sweepMode ~= 'centre' then return end

    local c = hoop.coords
    local R = Config.Scoring.rimRadius

    -- Nothing to learn until the court's collision has streamed in.
    local floor = StartExpensiveSynchronousShapeTestLosProbe(c.x, c.y, c.z - 0.6, c.x, c.y, c.z - 6.0, 1, 0, 7)
    local floorStatus, floorHit = GetShapeTestResult(floor)
    if floorStatus ~= 2 or not isHit(floorHit) then return end

    local found = 0

    for i = 0, 15 do
        local a = i / 16.0 * 2.0 * math.pi
        local x, y = c.x + math.cos(a) * R, c.y + math.sin(a) * R

        local handle = StartShapeTestSweptSphere(x, y, c.z + 0.22, x, y, c.z - 0.14, 0.035, 1 | 16, 0, SOLID)
        local status, hit, pos = GetShapeTestResult(handle)

        if status == 2 and isHit(hit) and math.abs(pos.z - c.z) < 0.12 then
            found = found + 1
        end
    end

    hoop.rimProbed = true
    hoop.mapRim = found >= 9

    if Config.Debug then
        print(('^2[gk_basketball]^7 hoop %s: map collision on %d of 16 points round the ring -> %s')
            :format(hoop.id, found, hoop.mapRim and 'using the map\'s rim' or 'using a calculated rim'))
    end
end

local function rimsNear()
    local hoops = BB.nearbyHoops()

    for i = #rimList, 1, -1 do rimList[i] = nil end

    for i = 1, #hoops do
        local hoop = hoops[i]

        probeMapRim(hoop)

        local rim = hoop.rim
        if not rim then
            rim = {}
            hoop.rim = rim
        end

        rim.x, rim.y, rim.z = hoop.coords.x, hoop.coords.y, hoop.coords.z
        rim.R      = Config.Scoring.rimRadius
        rim.tube   = cfg.rimTube
        rim.net    = prm.netLength
        rim.noRing = hoop.mapRim or cfg.calculatedRim == false

        rimList[#rimList + 1] = rim
    end

    return rimList
end

--------------------------------------------------------------------------------
-- Bodies
--------------------------------------------------------------------------------

local nearPeds, nearPedsAt = {}, 0
local handWas = {}      -- [ped .. bone] = { x, y, z, at }

--- Every ped within reach of a simulated ball. Refreshed a few times a second;
--- positions are read fresh each frame from this short list.
local function refreshPeds(now)
    if now - nearPedsAt < 200 then return end
    nearPedsAt = now

    for i = #nearPeds, 1, -1 do nearPeds[i] = nil end

    for _, ped in ipairs(GetGamePool('CPed')) do
        local at = GetEntityCoords(ped)

        for _, sim in pairs(sims) do
            local b = sim.ball
            local dx, dy, dz = at.x - b.x, at.y - b.y, at.z - b.z

            if dx * dx + dy * dy + dz * dz < 36.0 then
                nearPeds[#nearPeds + 1] = ped
                break
            end
        end
    end

    -- Hands that have gone away don't need remembering.
    for key, was in pairs(handWas) do
        if now - was.at > 1000 then handWas[key] = nil end
    end
end

local HANDS = { 57005, 18905 }      -- SKEL_R_Hand, SKEL_L_Hand

local function bodiesFor(sim, now)
    local list = sim.bodies
    local b = sim.ball
    local count = 0

    for i = 1, #nearPeds do
        local ped = nearPeds[i]

        if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
            local at = GetEntityCoords(ped)
            local dx, dy = at.x - b.x, at.y - b.y

            if dx * dx + dy * dy < 6.25 and math.abs(at.z - b.z) < 3.5 then
                local vel  = GetEntityVelocity(ped)
                local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
                local radius = cfg.bodyRadius
                local feet = at.z - 0.98

                count = count + 1
                local body = list[count] or {}
                list[count] = body

                body.x, body.y = at.x, at.y
                body.z0 = feet + radius
                body.z1 = math.max(body.z0, head.z + 0.12 - radius)
                body.radius = radius
                body.vx, body.vy, body.vz = vel.x, vel.y, vel.z
                body.id = ped

                -- Hands, moving as fast as they are actually moving: an arm
                -- swung at the ball swats it, a hand held up just gets in the way.
                for h = 1, 2 do
                    local bone = HANDS[h]
                    local hand = GetPedBoneCoords(ped, bone, 0.0, 0.0, 0.0)
                    local key  = ped * 4 + h
                    local was  = handWas[key]
                    local hvx, hvy, hvz = vel.x, vel.y, vel.z

                    if was and now > was.at and now - was.at < 200 then
                        local dt = (now - was.at) / 1000.0
                        hvx, hvy, hvz = (hand.x - was.x) / dt, (hand.y - was.y) / dt, (hand.z - was.z) / dt

                        local speed = sqrt(hvx * hvx + hvy * hvy + hvz * hvz)
                        if speed > 9.0 then
                            local s = 9.0 / speed
                            hvx, hvy, hvz = hvx * s, hvy * s, hvz * s
                        end
                    end

                    if not was then
                        was = {}
                        handWas[key] = was
                    end

                    if now > (was.at or 0) then
                        was.x, was.y, was.z, was.at = hand.x, hand.y, hand.z, now
                    end

                    count = count + 1
                    local fist = list[count] or {}
                    list[count] = fist

                    fist.x, fist.y, fist.z0, fist.z1 = hand.x, hand.y, hand.z, hand.z
                    fist.radius = cfg.handRadius
                    fist.vx, fist.vy, fist.vz = hvx, hvy, hvz
                    fist.id = ped
                end
            end
        end
    end

    for i = #list, count + 1, -1 do list[i] = nil end

    return list
end

--------------------------------------------------------------------------------
-- What happened to the ball, as sound and spray
--------------------------------------------------------------------------------

local lastFx = {}       -- [kind] = ms, so a ball chattering on the rim isn't a machine gun

local function fx(kind, x, y, z, strength)
    local now = GetGameTimer()
    if lastFx[kind] and now - lastFx[kind] < 70 then return end
    lastFx[kind] = now

    BB.playFx(kind, x, y, z, strength)
    TriggerServerEvent('gk_basketball:fx', kind, x, y, z, strength)
end

--[[
    A bounce up at a basket is not a bounce on the floor.

    The physics only knows it hit something the game's collision tests found.
    Where that was says what: with the ball's middle a ball's width from the
    ring itself, it was the rim (a hoop whose ring is the map's own collision
    never raises the physics' own 'rim' event); anywhere else up there, the
    backboard or its frame.
]]
local function hoopPart(b)
    for i = 1, #rimList do
        local rim = rimList[i]
        local dz = b.z - rim.z

        if dz > -0.45 and dz < 1.5 then
            local dx, dy = b.x - rim.x, b.y - rim.y
            local d = sqrt(dx * dx + dy * dy)

            if d < 1.3 then
                if math.abs(d - rim.R) < 0.17 and math.abs(dz) < 0.2 then return 'rim' end
                return 'board'
            end
        end
    end

    return nil
end

local function onEvent(kind, b, a)
    if kind == 'bounce' then
        if a > 0.7 then fx(hoopPart(b) or 'bounce', b.x, b.y, b.z, a) end
    elseif kind == 'rim' then
        if a > 0.4 then fx('rim', b.x, b.y, b.z, a) end
    elseif kind == 'net' then
        fx('net', b.x, b.y, b.z, a)
    elseif kind == 'splash' then
        if a > 1.2 then fx('splash', b.x, b.y, b.z, a) end
    elseif kind == 'body' then
        if a > 1.5 then fx('body', b.x, b.y, b.z, a) end
    end
end

local env = {
    sweep = sweep,
    water = water,
    event = onEvent,
    rims  = rimList,
    bodies = nil,
}

--------------------------------------------------------------------------------
-- Driving the entity
--------------------------------------------------------------------------------

--- Makes the prop inert: from here on it goes where it is put.
local function takeOver(ent)
    SetEntityCollision(ent, false, cfg.syncVelocity and true or false)
    SetEntityHasGravity(ent, false)
    FreezeEntityPosition(ent, not cfg.syncVelocity)
end

local function place(sim)
    local b, ent = sim.ball, sim.ent

    SetEntityCoordsNoOffset(ent, b.x, b.y, b.z, false, false, false)
    SetEntityQuaternion(ent, b.qx, b.qy, b.qz, b.qw)

    -- The position is ours either way. Giving the engine the velocity too means
    -- it is sent to other players with the position, and their game can carry
    -- the ball smoothly between updates instead of stepping it.
    if cfg.syncVelocity then
        SetEntityVelocity(ent, b.vx, b.vy, b.vz)
    end
end

--[[
    Last line of defence: a ball that has got under the map.

    It shouldn't happen, but everything above rests on reading the game's shape
    tests correctly, and a ball that slips through the floor falls for ever where
    nobody can get it back. So twice a second, for a ball that is falling: if
    there is nothing at all beneath it and there is ground above it, it is under
    the world, and it's put back on top.
]]
local function rescue(sim, now)
    if now < (sim.rescueAt or 0) then return end
    sim.rescueAt = now + 500

    local b = sim.ball
    if b.mode ~= 'air' or b.vz > -1.0 or b.waterZ then return end

    local below = StartExpensiveSynchronousShapeTestLosProbe(b.x, b.y, b.z, b.x, b.y, b.z - 60.0, 1, 0, 7)
    local status, hit = GetShapeTestResult(below)
    if status ~= 2 or isHit(hit) then return end

    local above = StartExpensiveSynchronousShapeTestLosProbe(b.x, b.y, b.z + 80.0, b.x, b.y, b.z + 0.5, 1, 0, 7)
    local aboveStatus, aboveHit, top = GetShapeTestResult(above)
    if aboveStatus ~= 2 or not isHit(aboveHit) then return end

    b.x, b.y, b.z = top.x, top.y, top.z + prm.radius + 0.05
    b.vx, b.vy, b.vz = 0.0, 0.0, 0.0
    b.wx, b.wy, b.wz = 0.0, 0.0, 0.0

    if Config.Debug then
        print(('^3[gk_basketball]^7 ball %d was under the map; put back at %.2f %.2f %.2f (sweep mode %s)')
            :format(sim.ent, b.x, b.y, b.z, tostring(sweepMode)))
    end
end

local function run()
    if running then return end
    running = true

    CreateThread(function()
        local last = GetGameTimer()
        local everyFrame = true

        while next(sims) do
            local now = GetGameTimer()

            -- Ticking every frame, the frame's own length is the exact step (and
            -- slows with the game if it is slowed). Ticking slowly over resting
            -- balls, it's however long we were away.
            local dt = everyFrame and GetFrameTime() or (now - last) / 1000.0
            last = now

            calibrate()
            refreshPeds(now)
            env.rims = rimsNear()

            local me = GetEntityCoords(PlayerPedId())
            local awake = false

            for ent, sim in pairs(sims) do
                if not DoesEntityExist(ent) or not NetworkHasControlOfEntity(ent) then
                    -- Picked up, deleted, or handed to another player's game.
                    sims[ent] = nil
                else
                    local b = sim.ball
                    local was = b.mode

                    local dx, dy = b.x - me.x, b.y - me.y

                    if dx * dx + dy * dy > cfg.maxDistance * cfg.maxDistance then
                        -- Too far off for there to be any world under it on this
                        -- client. Leave it where it is rather than drop it through
                        -- ground that hasn't loaded.
                        if was ~= 'sleep' then
                            b.mode = 'sleep'
                            b.vx, b.vy, b.vz = 0.0, 0.0, 0.0
                            sim.parked = true
                        end
                    else
                        -- Back in range of one that was stopped wherever it had
                        -- got to, possibly in mid-air: let it go again.
                        if sim.parked then
                            sim.parked = nil
                            P.wake(b)
                        end

                        current = sim
                        env.bodies = bodiesFor(sim, now)
                        P.step(b, dt, env, prm)
                        current = nil

                        rescue(sim, now)
                    end

                    if b.mode ~= 'sleep' then
                        awake = true
                        if was == 'sleep' and cfg.syncVelocity then FreezeEntityPosition(ent, false) end
                        place(sim)
                    elseif was ~= 'sleep' then
                        place(sim)
                        SetEntityVelocity(ent, 0.0, 0.0, 0.0)
                        FreezeEntityPosition(ent, true)
                    end
                end
            end

            -- A resting ball only needs looking at often enough to notice a foot.
            everyFrame = awake
            Wait(awake and 0 or (#nearPeds > 0 and 50 or 250))
        end

        running = false
    end)
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

--- Hands a ball to the physics.
--- @param ent number The ball entity. This client must own it.
--- @param pos vector3
--- @param vel vector3
--- @param spin vector3|nil rad/s, world axes
--- @param thrower number|nil A ped the ball may pass through for a moment
function BB.sim.launch(ent, pos, vel, spin, thrower)
    takeOver(ent)

    local b = P.new(pos.x, pos.y, pos.z)
    b.vx, b.vy, b.vz = vel.x, vel.y, vel.z

    if spin then b.wx, b.wy, b.wz = spin.x, spin.y, spin.z end

    if thrower then
        b.ignoreId, b.ignoreUntil = thrower, cfg.throwerGrace
    end

    local sim = { ent = ent, ball = b, bodies = {} }
    sims[ent] = sim

    place(sim)
    run()

    return sim
end

function BB.sim.release(ent)
    sims[ent] = nil
end

function BB.sim.isSimulated(ent)
    return sims[ent] ~= nil
end

--- How the swept test was found to answer: 'contact', 'centre', 'ray', or nil
--- if there has been no ground under the player to check it against yet.
function BB.sim.sweepMode()
    return sweepMode
end

--- A point to start the ball from: `to` if there's nothing between, otherwise
--- just short of whatever is. Stops a shot taken with your back foot against a
--- wall from starting on the far side of it.
function BB.sim.clearPoint(from, to)
    calibrate()

    local hit, cx, cy, cz = sweep(from.x, from.y, from.z, to.x, to.y, to.z, prm.radius)
    if not hit then return to end

    return vec3(cx, cy, cz)
end

--- /bball_phys prints what the physics is doing with each ball this client owns.
RegisterCommand('bball_phys', function()
    calibrate()

    print(('^2[gk_basketball]^7 physics: sweep mode %s, velocity sync %s, draft %.3f m')
        :format(tostring(sweepMode), tostring(cfg.syncVelocity), prm.draft))

    local count = 0

    for ent, sim in pairs(sims) do
        local b = sim.ball
        count = count + 1

        print(('  ball %d  %s  pos %.2f %.2f %.2f  speed %.2f  spin %.1f  water %s')
            :format(ent, b.mode, b.x, b.y, b.z,
                sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz),
                sqrt(b.wx * b.wx + b.wy * b.wy + b.wz * b.wz),
                b.waterZ and ('%.2f'):format(b.waterZ) or 'none'))
    end

    if count == 0 then print('  no balls simulated by this client') end

    for _, hoop in ipairs(BB.nearbyHoops()) do
        print(('  hoop %s  rim: %s'):format(hoop.id,
            not hoop.rimProbed and 'not checked yet' or hoop.mapRim and 'map collision' or 'calculated'))
    end
end, false)

--------------------------------------------------------------------------------
-- Balls that become ours without being thrown by us
--------------------------------------------------------------------------------

-- A loose ball this client owns but isn't simulating: its last owner left or
-- walked away, or this resource was restarted under it.
CreateThread(function()
    while true do
        Wait(500)

        for netId in pairs(BB.loose or {}) do
            if NetworkDoesNetworkIdExist(netId) then
                local ent = NetToObj(netId)

                if ent ~= 0 and DoesEntityExist(ent) and not sims[ent] and NetworkHasControlOfEntity(ent) then
                    BB.sim.launch(ent, GetEntityCoords(ent), GetEntityVelocity(ent))
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    sims = {}
end)
