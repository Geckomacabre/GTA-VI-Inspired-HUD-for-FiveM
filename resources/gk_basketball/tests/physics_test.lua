--[[
    Checks on client/physics.lua. Every one runs twice: with sweeps that report a
    start already in contact, and with sweeps that don't.
]]

local P = BB.physics
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

local RIM_Z, RIM_R = 3.05, 0.2286

local function suite(overlap)
    local tag = overlap and '[overlap] ' or '[no overlap] '
    local prm = P.params()
    local r = prm.radius

    local function world()
        local W = World.new({ overlap = overlap })
        W.plane(0, 0, 1, 0)     -- floor at z = 0
        return W
    end

    ----------------------------------------------------------------------------
    -- Dropped from 1.8 m (bottom of the ball) it should come back to about 1.1 m.
    do
        local W = world()
        local b = P.new(0, 0, 1.8 + r)
        local apex, phase, lowest = 0.0, 'fall', 10.0

        W.run(b, prm, 1.6, 60, function(ball)
            lowest = math.min(lowest, ball.z)
            if phase == 'fall' and ball.vz > 0.0 then phase = 'rise' end
            if phase == 'rise' then
                apex = math.max(apex, ball.z - r)
                if ball.vz < 0.0 then return false end
            end
        end)

        check(tag .. 'drop rebound height', apex > 0.95 and apex < 1.25, ('apex %.3f'):format(apex))
        check(tag .. 'drop never sinks into floor', lowest > r - prm.skin - 0.001, ('lowest centre %.4f'):format(lowest))
    end

    ----------------------------------------------------------------------------
    -- Left alone it settles and goes to sleep, and nothing gains height on the way.
    do
        local W = world()
        local b = P.new(0, 0, 2.5)
        b.vx = 1.5

        local lastApex, rising, grew, lowest = 10.0, false, false, 10.0
        local peak = 0.0

        W.run(b, prm, 25.0, 60, function(ball)
            lowest = math.min(lowest, ball.z)
            if ball.vz > 0.0 then
                rising, peak = true, math.max(peak, ball.z)
            elseif rising then
                rising = false
                if peak > lastApex + 0.002 then grew = true end
                lastApex, peak = peak, 0.0
            end
        end)

        check(tag .. 'settles to sleep', b.mode == 'sleep', 'mode ' .. b.mode)
        check(tag .. 'no bounce higher than the last', not grew)
        check(tag .. 'rests on the floor', near(b.z, r + prm.skin, 0.004), ('z %.4f'):format(b.z))
        check(tag .. 'never under the floor', lowest > r - prm.skin - 0.001, ('lowest %.4f'):format(lowest))
    end

    ----------------------------------------------------------------------------
    -- The same throw at any frame rate ends up in the same place.
    do
        local at = {}

        for _, fps in ipairs({ 24, 60, 144, 240 }) do
            local W = World.new({ overlap = overlap })
            local b = P.new(0, 0, 2.0)
            b.vx, b.vz = 6.0, 7.0
            b.wy = -12.0
            W.run(b, prm, 1.0, fps)
            at[#at + 1] = { fps = fps, x = b.x, z = b.z }
        end

        local worst = 0.0
        for i = 2, #at do
            worst = math.max(worst, math.abs(at[i].x - at[1].x), math.abs(at[i].z - at[1].z))
        end

        check(tag .. 'flight independent of frame rate', worst < 0.004, ('worst %.4f m'):format(worst))
    end

    ----------------------------------------------------------------------------
    -- The solver lands the ball where it was asked to, air and spin included.
    do
        local worst = 0.0

        for _, dist in ipairs({ 1.5, 4.0, 7.0, 12.0, 22.0 }) do
            for _, fps in ipairs({ 30, 60, 144 }) do
                local time = P.flightTime(prm, RIM_Z - 2.1, dist, 46.0)
                local wx, wy, wz = P.backspin(1.0, 0.0, 12.0)
                local vx, vy, vz = P.solveLaunch(prm, 0, 0, 2.1, dist, 0, RIM_Z, time, wx, wy, wz)

                local W = World.new({ overlap = overlap })
                local b = P.new(0, 0, 2.1)
                b.vx, b.vy, b.vz = vx, vy, vz
                b.wx, b.wy, b.wz = wx, wy, wz

                -- Stop on the frame the flight time is reached and close the gap exactly.
                local dt = 1.0 / fps
                local t = 0.0
                while t + dt < time do
                    P.step(b, dt, W, prm)
                    t = t + dt
                end
                P.step(b, time - t, W, prm)

                worst = math.max(worst, math.abs(b.x - dist), math.abs(b.y), math.abs(b.z - RIM_Z))
            end
        end

        check(tag .. 'solver hits the target', worst < 0.004, ('worst %.4f m'):format(worst))
    end

    ----------------------------------------------------------------------------
    -- A shot solved onto the middle of the rim goes through it untouched, from anywhere.
    do
        for _, dist in ipairs({ 1.2, 2.5, 4.5, 7.0, 10.0, 16.0, 24.0 }) do
            local W = world()
            W.rims[1] = { x = dist, y = 0.0, z = RIM_Z, R = RIM_R, tube = 0.009 }

            local time = P.flightTime(prm, RIM_Z - 2.1, dist, 46.0)
            local wx, wy, wz = P.backspin(1.0, 0.0, 12.0)
            local vx, vy, vz = P.solveLaunch(prm, 0, 0, 2.1, dist, 0, RIM_Z, time, wx, wy, wz)

            local b = P.new(0, 0, 2.1)
            b.vx, b.vy, b.vz = vx, vy, vz
            b.wx, b.wy, b.wz = wx, wy, wz

            local prev, through = b.z, false
            W.run(b, prm, time + 0.6, 60, function(ball)
                if prev > RIM_Z and ball.z <= RIM_Z then
                    local d = math.sqrt((ball.x - dist) ^ 2 + ball.y ^ 2)
                    if d < RIM_R then through = true end
                end
                prev = ball.z
            end)

            check(tag .. ('clean shot from %.1f m drops'):format(dist), through)
            check(tag .. ('clean shot from %.1f m touches no iron'):format(dist), W.count('rim') == 0,
                ('%d rim contacts'):format(W.count('rim')))
            check(tag .. ('clean shot from %.1f m finds the net'):format(dist), W.count('net') == 1)
        end
    end

    ----------------------------------------------------------------------------
    -- Thrown at the iron it hits the iron, and is never left inside it.
    do
        local W = world()
        local rim = { x = 5.0, y = 0.0, z = RIM_Z, R = RIM_R, tube = 0.009 }
        W.rims[1] = rim

        local time = P.flightTime(prm, RIM_Z - 2.1, 5.0, 46.0)
        -- Aimed at the front of the ring.
        local vx, vy, vz = P.solveLaunch(prm, 0, 0, 2.1, 5.0 - RIM_R, 0, RIM_Z + 0.05, time)

        local b = P.new(0, 0, 2.1)
        b.vx, b.vy, b.vz = vx, vy, vz

        local inside = false
        W.run(b, prm, 3.0, 60, function(ball)
            local dx, dy = ball.x - rim.x, ball.y - rim.y
            local d = math.sqrt(dx * dx + dy * dy)
            local gap = math.sqrt((d - rim.R) ^ 2 + (ball.z - rim.z) ^ 2)
            if gap < r + rim.tube - 0.002 then inside = true end
        end)

        check(tag .. 'front-rim shot hits the rim', W.count('rim') >= 1)
        check(tag .. 'ball never left inside the iron', not inside)
    end

    ----------------------------------------------------------------------------
    -- Backspin checks the ball up on the floor; topspin runs it on.
    do
        local function after(spin)
            local W = world()
            local b = P.new(0, 0, 1.0)
            b.vx, b.vz = 4.0, -3.0
            b.wy = spin
            W.run(b, prm, 2.0, 120, function(ball)
                if W.count('bounce') >= 1 then return false end
            end)
            return b.vx
        end

        local back, none, top = after(-25.0), after(0.0), after(25.0)
        -- Backspin about +y for travel along +x is negative: d x up = (0, -1, 0).
        check(tag .. 'backspin slows the ball off the floor', back < none - 0.2,
            ('back %.2f  none %.2f'):format(back, none))
        check(tag .. 'topspin runs it on', top > none + 0.2, ('top %.2f  none %.2f'):format(top, none))
    end

    ----------------------------------------------------------------------------
    -- Rolling: stops on the flat, runs away down a slope, turns as fast as it travels.
    do
        local W = world()
        local b = P.new(0, 0, r + 0.02)
        b.vx = 3.0

        local rolledAt, spinOk
        W.run(b, prm, 40.0, 60, function(ball)
            if ball.mode == 'roll' and not rolledAt and ball.t > 0.5 then
                rolledAt = ball.x
                spinOk = near(ball.wy * r, ball.vx, 0.02)
            end
        end)

        check(tag .. 'rolling ball stops', b.mode == 'sleep', 'mode ' .. b.mode)
        -- Thrown along the floor with no spin it is sliding; friction turns that into
        -- rolling at 3/5 of the speed, and rolling resistance does the rest.
        local expect = (0.6 * 3.0) ^ 2 / (2.0 * prm.rollResistance * prm.gravity)
        check(tag .. 'rolled the distance a sliding start gives', near(b.x, expect, 0.6),
            ('x %.2f expected %.2f'):format(b.x, expect))
        check(tag .. 'rolls without slipping', spinOk == true)
    end

    do
        -- A 6 degree slope falling away along +x.
        local W = World.new({ overlap = overlap })
        local s = math.sin(math.rad(6.0))
        local c = math.cos(math.rad(6.0))
        W.plane(s, 0, c, 0)

        local b = P.new(0, 0, r + 0.01)
        W.run(b, prm, 3.0, 60)

        check(tag .. 'rolls downhill from rest', b.x > 1.0 and b.vx > 0.5, ('x %.2f vx %.2f'):format(b.x, b.vx))

        -- Uniform acceleration should be 3/5 g sin(theta) less the rolling resistance.
        local expect = 0.6 * prm.gravity * s - prm.rollResistance * prm.gravity * c
        local speed = math.sqrt(b.vx ^ 2 + b.vz ^ 2)
        check(tag .. 'downhill speed is a rolling shell\'s', near(speed, expect * 3.0, 0.25),
            ('speed %.2f expected %.2f'):format(speed, expect * 3.0))
    end

    ----------------------------------------------------------------------------
    -- Off the edge of a ledge it falls; into a wall it comes back.
    do
        local W = World.new({ overlap = overlap })
        W.plane(0, 0, 1, 0, nil, function(x) return x < 3.0 end)    -- floor ends at x = 3
        W.plane(0, 0, 1, -2.0)                                       -- ground 2 m below

        local b = P.new(0, 0, r + 0.01)
        b.vx = 2.5
        W.run(b, prm, 6.0, 60)

        check(tag .. 'rolls off a ledge and lands below', b.z < -1.8 and b.z > -2.0 + r - 0.01, ('z %.3f'):format(b.z))
    end

    do
        local W = world()
        W.plane(-1, 0, 0, -4.0)     -- wall at x = 4, facing back down x

        local b = P.new(0, 0, r + 0.01)
        b.vx = 5.0

        local furthest = 0.0
        W.run(b, prm, 4.0, 60, function(ball) furthest = math.max(furthest, ball.x) end)

        check(tag .. 'rolling ball stops at the wall', furthest < 4.0 - r + 0.01, ('furthest %.3f'):format(furthest))
        check(tag .. 'and comes back off it', b.x < 3.5, ('x %.3f'):format(b.x))
    end

    ----------------------------------------------------------------------------
    -- Water: it goes in, comes up, and floats at its draft.
    do
        local W = World.new({ overlap = overlap })
        W.plane(0, 0, 1, -10.0)                 -- sea bed a long way down
        W.waterFn = function() return 0.0 end   -- flat water at z = 0

        local b = P.new(0, 0, 3.0)
        b.vx = 2.0

        local deepest = 10.0
        W.run(b, prm, 8.0, 60, function(ball) deepest = math.min(deepest, ball.z) end)

        local sits = r - prm.draft      -- centre height when floating
        check(tag .. 'does not sink', deepest > -0.45, ('deepest centre %.3f'):format(deepest))
        check(tag .. 'floats at its draft', near(b.z, sits, 0.01), ('z %.4f want %.4f'):format(b.z, sits))
        check(tag .. 'mostly out of the water', prm.draft > 0.02 and prm.draft < 0.07, ('draft %.3f'):format(prm.draft))
        check(tag .. 'stays awake afloat', b.mode == 'air', 'mode ' .. b.mode)
        local big = 0
        for _, e in ipairs(W.log) do
            if e.kind == 'splash' and e.a > 2.0 then big = big + 1 end
        end
        check(tag .. 'one real splash', big == 1, ('%d'):format(big))
        check(tag .. 'water takes its travel off', math.abs(b.vx) < 0.1, ('vx %.3f'):format(b.vx))
    end

    do
        -- A swell: 0.4 m waves, 5 s period, 12 m long.
        local W = World.new({ overlap = overlap })
        W.plane(0, 0, 1, -10.0)
        W.waterFn = function(x, _, _, t)
            return 0.4 * math.sin(2.0 * math.pi * (t / 5.0 - x / 12.0))
        end

        local b = P.new(0, 0, 0.5)
        local worst = 0.0

        W.run(b, prm, 30.0, 60, function(ball, t)
            if t > 4.0 then
                local surface = W.waterFn(ball.x, ball.y, ball.z, W.time)
                worst = math.max(worst, math.abs((ball.z - r + prm.draft) - surface))
            end
        end)

        check(tag .. 'rides the swell', worst < 0.06, ('worst off the surface %.3f m'):format(worst))
        check(tag .. 'stays near where it was dropped', math.abs(b.x) < 12.0, ('drifted %.2f m'):format(b.x))
    end

    do
        -- Lying on a beach when the water comes up over it.
        local W = world()
        local level = -1.0
        W.waterFn = function() return level end

        local b = P.new(0, 0, r + 0.01)
        W.run(b, prm, 6.0, 60)
        local slept = b.mode == 'sleep'

        level = 0.5
        W.run(b, prm, 6.0, 60)

        check(tag .. 'asleep on the sand', slept)
        check(tag .. 'floats off when the water rises', near(b.z, 0.5 + r - prm.draft, 0.02), ('z %.3f'):format(b.z))
    end

    ----------------------------------------------------------------------------
    -- Bodies: it comes back off a player, passes through the one who threw it,
    -- and a foot sets a resting ball going.
    do
        local W = world()
        W.bodies[1] = { x = 3.0, y = 0.0, z0 = 0.3, z1 = 1.6, radius = 0.3, vx = 0, vy = 0, vz = 0, id = 7 }

        local b = P.new(0, 0, 1.2)
        b.vx, b.vz = 8.0, 1.0

        local furthest = 0.0
        W.run(b, prm, 1.0, 60, function(ball) furthest = math.max(furthest, ball.x) end)

        check(tag .. 'bounces off a player', furthest < 3.0 - 0.3 and b.vx < 0.0, ('furthest %.2f vx %.2f'):format(furthest, b.vx))

        local W2 = world()
        W2.bodies[1] = W.bodies[1]
        local b2 = P.new(0, 0, 1.2)
        b2.vx, b2.vz = 8.0, 1.0
        b2.ignoreId, b2.ignoreUntil = 7, 0.7
        W2.run(b2, prm, 0.6, 60)

        check(tag .. 'passes through its thrower', b2.x > 3.5, ('x %.2f'):format(b2.x))
    end

    do
        local W = world()
        local b = P.new(0, 0, r + 0.01)
        W.run(b, prm, 3.0, 60)
        local slept = b.mode == 'sleep'

        -- Somebody walks through it at 2 m/s.
        local foot = { x = -1.0, y = 0.0, z0 = 0.3, z1 = 1.5, radius = 0.3, vx = 2.0, vy = 0, vz = 0, id = 1 }
        W.bodies[1] = foot

        W.run(b, prm, 2.0, 60, function(_, t)
            foot.x = -1.0 + 2.0 * t
            if t > 0.6 then foot.vx = 0.0; foot.x = 0.2 end
        end)

        check(tag .. 'was asleep before the kick', slept)
        check(tag .. 'a foot sets it rolling', b.x > 1.0, ('x %.2f'):format(b.x))
    end

    ----------------------------------------------------------------------------
    -- A hitch (a long frame) doesn't put it through the floor.
    do
        local W = world()
        local b = P.new(0, 0, 4.0)
        b.vz = -12.0

        local lowest = 10.0
        for _ = 1, 40 do
            P.step(b, 0.25, W, prm)     -- four frames a second
            lowest = math.min(lowest, b.z)
        end

        check(tag .. 'survives a 250 ms frame', lowest > r - prm.skin - 0.001, ('lowest %.3f'):format(lowest))
    end
end

suite(false)
suite(true)

print(('physics: %d passed, %d failed'):format(passed, failed))

return failed
