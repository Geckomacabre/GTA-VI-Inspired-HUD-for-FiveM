--[[
    client/ballsim.lua against a fake game (tests/fakegame.lua).

    The physics tests prove the ball behaves given a correct picture of the
    world. These prove the glue gives it one: that it reads the game's shape
    tests correctly whichever of the three ways they turn out to answer, moves
    the entity, puts it to sleep, floats it, and picks up and lets go of balls as
    ownership changes.
]]

local failed, passed = 0, 0

local function check(name, ok, detail)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s   %s'):format(name, detail or ''))
    end
end

local function near(a, b, tol) return math.abs(a - b) <= tol end

local Fake = load_file('tests/fakegame.lua')

--- A clean game with the client files loaded, and the swept test answering in
--- the given way.
local function fresh(mode)
    Fake.threads, Fake.entities, Fake.events = {}, {}, {}
    Fake.now = 1000
    Fake.sweepMeans = mode

    local W = World.new({})
    W.plane(0, 0, 1, 0)
    Fake.world = W

    BB = {}
    load_file('client/physics.lua')
    load_game('shared/config.lua')
    load_game('shared/util.lua')

    BB.loose = {}
    BB.hoops = {}
    BB.fx = {}
    function BB.nearbyHoops() return BB.hoops end
    function BB.playFx(kind) BB.fx[#BB.fx + 1] = kind end

    Fake.player = Fake.entity(0, 0, 1.0)
    Fake.peds = {}

    load_game('client/ballsim.lua')

    return W
end

local function fxCount(kind)
    local n = 0
    for _, k in ipairs(BB.fx) do
        if k == kind then n = n + 1 end
    end
    return n
end

for _, mode in ipairs({ 'contact', 'centre', 'pending' }) do
    local tag = '[' .. mode .. '] '
    -- A ray stands in for the swept sphere when it won't answer in-frame, and
    -- is a centimetre or two less exact about where the ball touches.
    local slop = mode == 'pending' and 0.03 or 0.008

    ----------------------------------------------------------------------------
    -- Thrown, bounces, comes to rest on the floor and is put to sleep.
    do
        fresh(mode)
        local r = BB.sim.prm.radius

        local ball = Fake.entity(2, 0, 3)
        BB.sim.launch(ball, vec3(2, 0, 3), vec3(1.0, 0.0, 0.0))

        local lowest = 10.0
        Fake.run(14.0, function() lowest = math.min(lowest, Fake.entities[ball].pos.z) end)

        local e = Fake.entities[ball]
        local want = mode == 'pending' and 'ray' or mode
        check(tag .. 'worked out how the swept test answers', BB.sim.sweepMode() == want, tostring(BB.sim.sweepMode()))
        check(tag .. 'comes to rest on the floor', near(e.pos.z, r + BB.sim.prm.skin, slop), ('z %.4f'):format(e.pos.z))
        check(tag .. 'never under the floor', lowest > r - slop - 0.006, ('lowest %.4f'):format(lowest))
        check(tag .. 'frozen once asleep', e.frozen == true)
        check(tag .. 'collision off, gravity off', e.collision == false and e.gravity == false)
        check(tag .. 'bounces were heard', fxCount('bounce') >= 3, ('%d'):format(fxCount('bounce')))
        check(tag .. 'travelled the way it was thrown', e.pos.x > 3.0, ('x %.2f'):format(e.pos.x))
    end

    ----------------------------------------------------------------------------
    -- A wall stops it.
    do
        local W = fresh(mode)
        local r = BB.sim.prm.radius
        W.plane(-1, 0, 0, -5.0)

        local ball = Fake.entity(2, 0, 1.5)
        BB.sim.launch(ball, vec3(2, 0, 1.5), vec3(8.0, 0.0, 2.0))

        local furthest = 0.0
        Fake.run(3.0, function() furthest = math.max(furthest, Fake.entities[ball].pos.x) end)

        check(tag .. 'stops at a wall', furthest < 5.0 - r + slop + 0.006, ('furthest %.3f'):format(furthest))
        check(tag .. 'comes back off it', Fake.entities[ball].pos.x < 4.5, ('x %.3f'):format(Fake.entities[ball].pos.x))
    end

    ----------------------------------------------------------------------------
    -- A shot solved onto a hoop goes through the calculated rim and the net.
    do
        fresh(mode)
        local P, prm = BB.physics, BB.sim.prm
        local rimZ = 3.05

        BB.hoops[1] = { id = 'h1', court = 'c', coords = vec3(6.0, 0.0, rimZ) }

        local time = P.flightTime(prm, rimZ - 2.0, 6.0, Config.Shot.entryAngle)
        local wx, wy, wz = P.backspin(1.0, 0.0, Config.Shot.spin)
        local vx, vy, vz = P.solveLaunch(prm, 0, 0, 2.0, 6.0, 0, rimZ, time, wx, wy, wz)

        local ball = Fake.entity(0, 0, 2.0)
        BB.sim.launch(ball, vec3(0, 0, 2.0), vec3(vx, vy, vz), vec3(wx, wy, wz), Fake.player)

        local prev, through = 2.0, false
        Fake.run(time + 0.8, function()
            local p = Fake.entities[ball].pos
            if prev > rimZ and p.z <= rimZ and math.sqrt((p.x - 6.0) ^ 2 + p.y ^ 2) < Config.Scoring.rimRadius then
                through = true
            end
            prev = p.z
        end)

        check(tag .. 'solved shot drops through the hoop', through)
        check(tag .. 'no iron', fxCount('rim') == 0, ('%d'):format(fxCount('rim')))
        check(tag .. 'net heard once', fxCount('net') == 1, ('%d'):format(fxCount('net')))
        check(tag .. 'hoop given a calculated rim', BB.hoops[1].rim ~= nil and not BB.hoops[1].rim.noRing)
    end

    ----------------------------------------------------------------------------
    -- Into water: floats, stays awake, one splash.
    do
        local W = fresh(mode)
        local prm = BB.sim.prm

        W.planes = {}
        W.plane(0, 0, 1, -8.0)
        W.waterFn = function() return 0.0 end
        Fake.entities[Fake.player].pos = vec3(0, 0, -7.0)   -- stood on the sea bed, for calibration's sake

        local ball = Fake.entity(1, 0, 2.5)
        BB.sim.launch(ball, vec3(1, 0, 2.5), vec3(1.5, 0.0, 0.0))
        Fake.run(8.0)

        local e = Fake.entities[ball]
        check(tag .. 'floats at its draft', near(e.pos.z, prm.radius - prm.draft, 0.012), ('z %.4f'):format(e.pos.z))
        check(tag .. 'not frozen while afloat', e.frozen == false)
        check(tag .. 'splash heard', fxCount('splash') >= 1)
    end

    ----------------------------------------------------------------------------
    -- A loose ball we own but aren't simulating is picked up; one we lose is let go.
    do
        fresh(mode)
        local r = BB.sim.prm.radius

        local ball = Fake.entity(3, 0, 2.0)
        BB.loose[ball] = { shooter = 1 }
        Fake.run(6.0)

        check(tag .. 'adopts an owned loose ball', BB.sim.isSimulated(ball))
        check(tag .. 'and settles it', near(Fake.entities[ball].pos.z, r + BB.sim.prm.skin, slop),
            ('z %.4f'):format(Fake.entities[ball].pos.z))

        Fake.entities[ball].owned = false
        Fake.run(1.0)
        check(tag .. 'lets go of one it no longer owns', not BB.sim.isSimulated(ball))
    end

    ----------------------------------------------------------------------------
    -- One that has got under the floor is put back on it.
    do
        fresh(mode)
        local r = BB.sim.prm.radius

        local ball = Fake.entity(4, 0, -3.0)
        BB.sim.launch(ball, vec3(4, 0, -3.0), vec3(0.0, 0.0, -2.0))
        Fake.run(6.0)

        check(tag .. 'rescued from under the map', near(Fake.entities[ball].pos.z, r + BB.sim.prm.skin, slop),
            ('z %.3f'):format(Fake.entities[ball].pos.z))
    end

    ----------------------------------------------------------------------------
    -- A chain-link fence and a glass backboard are see-through, not thin air.
    for _, what in ipairs({
        { 'a chain-link fence', { material = 'METAL_CHAINLINK_SMALL', seeThrough = true } },
        { 'a glass backboard', { material = 'GLASS_SHOOT_THROUGH', glass = true } },
    }) do
        local W = fresh(mode)

        -- Everything beyond x = 4 is behind it.
        W.plane(-1, 0, 0, -4.0, what[2])

        local ball = Fake.entity(2, 0, 1.5)
        BB.sim.launch(ball, vec3(2, 0, 1.5), vec3(7.0, 0.0, 2.0))

        local furthest = 0.0
        Fake.run(4.0, function() furthest = math.max(furthest, Fake.entities[ball].pos.x) end)

        check(tag .. what[1] .. ' stops the ball', furthest < 4.0, ('got to x = %.2f'):format(furthest))
        check(tag .. 'which comes back off it', Fake.entities[ball].pos.x < 3.7, ('x %.2f'):format(Fake.entities[ball].pos.x))
    end

    ----------------------------------------------------------------------------
    -- But a net is not a floor: the same kind of surface inside a basket is
    -- dropped through, and anywhere else it holds the ball up.
    for _, hooped in ipairs({ true, false }) do
        local W = fresh(mode)
        local r = BB.sim.prm.radius
        local rim = vec3(6, 0, 3.05)

        if hooped then BB.hoops = { { id = 'h', coords = rim } } end

        W.plane(0, 0, 1, rim.z - 0.2, { material = 'METAL_CHAINLINK_SMALL', seeThrough = true }, function(x, y)
            return (x - rim.x) ^ 2 + (y - rim.y) ^ 2 < 0.15 ^ 2
        end)

        local ball = Fake.entity(rim.x, rim.y, rim.z + 0.6)
        BB.sim.launch(ball, vec3(rim.x, rim.y, rim.z + 0.6), vec3(0.0, 0.0, 0.0))
        Fake.run(6.0)

        local z = Fake.entities[ball].pos.z

        if hooped then
            check(tag .. 'a ball drops through a net that has collision', near(z, r + BB.sim.prm.skin, slop + 0.01),
                ('z %.3f'):format(z))
        else
            check(tag .. 'the same thing with no basket round it is solid', z > rim.z - 0.3, ('z %.3f'):format(z))
        end
    end

    ----------------------------------------------------------------------------
    -- Off the backboard is heard as the backboard, not as the floor.
    for _, hooped in ipairs({ true, false }) do
        local W = fresh(mode)
        local rim = vec3(6, 0, 3.05)

        if hooped then BB.hoops = { { id = 'h', coords = rim } } end

        -- A board behind where the ring is (or would be), from just under it up.
        W.plane(-1, 0, 0, -(rim.x + 0.4), nil, function(_, y, z) return math.abs(y) < 0.9 and z > rim.z - 0.2 end)

        local ball = Fake.entity(rim.x - 1.2, 0.5, rim.z + 0.5)
        BB.sim.launch(ball, vec3(rim.x - 1.2, 0.5, rim.z + 0.5), vec3(6.0, 0.0, 1.0))
        Fake.run(0.6)

        if hooped then
            check(tag .. 'a ball off the backboard sounds like the backboard', fxCount('board') >= 1 and fxCount('bounce') == 0,
                ('%d board, %d bounce'):format(fxCount('board'), fxCount('bounce')))
        else
            check(tag .. 'the same wall with no basket on it is just a bounce', fxCount('bounce') >= 1 and fxCount('board') == 0,
                ('%d board, %d bounce'):format(fxCount('board'), fxCount('bounce')))
        end
    end

    ----------------------------------------------------------------------------
    -- Somebody walking into a resting ball knocks it on.
    do
        fresh(mode)

        local ball = Fake.entity(2, 0, 0.5)
        BB.sim.launch(ball, vec3(2, 0, 0.5), vec3(0.0, 0.0, 0.0))
        Fake.run(5.0)
        local rested = Fake.entities[ball].frozen

        local ped = Fake.entity(0.5, 0, 1.0)
        Fake.peds = { ped }
        Fake.entities[ped].vel = vec3(2.0, 0, 0)

        Fake.run(1.2, function()
            local p = Fake.entities[ped].pos
            Fake.entities[ped].pos = vec3(p.x + 2.0 * Fake.frame, 0, 1.0)
        end)
        Fake.entities[ped].vel = vec3(0, 0, 0)
        Fake.run(1.0)

        check(tag .. 'was at rest', rested == true)
        check(tag .. 'kicked along by a walker', Fake.entities[ball].pos.x > 3.2, ('x %.2f'):format(Fake.entities[ball].pos.x))
    end
end

print(('glue: %d passed, %d failed'):format(passed, failed))

return failed
