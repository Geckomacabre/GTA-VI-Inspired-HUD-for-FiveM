--[[
    client/moves.lua: the arithmetic of a dribble that follows its animation,
    of which cycle suits which pace, and of what counts as a ball coming to you.
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

local function near(a, b, tol) return math.abs(a - b) <= (tol or 1e-9) end

BB = {}
load_game('client/moves.lua')

local M = BB.moves

--------------------------------------------------------------------------------
-- Bounces
--------------------------------------------------------------------------------
do
    local raw = {
        { push = 1.15, floor = 1.30, catch = 1.55 },
        { push = 0.38, floor = 0.53, catch = 0.72 },
        { push = 1.98, floor = 2.11, catch = 2.28 },
        { push = 2.42, floor = 2.55, catch = 2.75 },    -- runs off the end of a 2.37 s clip
        { push = 0.50, floor = 0.60, catch = 0.70 },    -- starts before the first has been caught
        { push = 0.80, catch = 1.00 },                  -- doesn't say when it landed
        { push = 0.9, floor = 0.95, catch = 0.92 },     -- nonsense
    }

    local b = M.cleanBounces(raw, 2.367)

    check('bounces come out in order', #b == 4 and b[1].push == 0.38 and b[2].push == 0.80
        and b[3].push == 1.15 and b[4].push == 1.98, ('%d kept'):format(#b))
    check('one that runs past the end of the clip is dropped', b[#b].catch <= 2.367)
    check('one without a floor time is given one', b[2].floor > 0.80 and b[2].floor < 1.00)
    check('no clip, no bounces', #M.cleanBounces(nil, 2.0) == 0)

    local inHand, rise, falling, k = M.bounceAt(b, 0.10)
    check('before the first push the ball is in the hand', inHand and rise == 1.0 and not falling and k == 0)

    inHand, rise, falling, k = M.bounceAt(b, 0.38)
    check('at the push it has only just left', not inHand and near(rise, 1.0, 1e-6) and falling and k == 1)

    inHand, rise, falling = M.bounceAt(b, 0.529999)
    check('it reaches the floor at the floor time', not inHand and rise < 0.01 and falling, ('rise %.4f'):format(rise))

    inHand, rise, falling = M.bounceAt(b, 0.53)
    check('and is on the way up from then', not inHand and near(rise, 0.0, 1e-6) and not falling)

    inHand, rise = M.bounceAt(b, 0.7199)
    check('it is nearly back at the catch', not inHand and rise > 0.98)

    inHand = M.bounceAt(b, 0.72)
    check('and in the hand from the catch', inHand)

    -- Never outside the hand and the floor, and always going one way at a time.
    local ok, monotone = true, true
    local last

    for i = 0, 340 do
        local t = 0.38 + (0.72 - 0.38) * i / 340.0 - 1e-9
        local _, r, f = M.bounceAt(b, math.max(t, 0.38))

        if r < -1e-9 or r > 1.0 + 1e-9 then ok = false end
        if last and f and r > last + 1e-9 then monotone = false end
        if last and not f and r < last - 1e-9 and i > 151 then monotone = false end

        last = r
    end

    check('the ball stays between the floor and the hand', ok)
    check('it only goes down, then only up', monotone)

    -- Thrown down: half way through the fall it has covered more than a ball that was dropped would have.
    local _, half = M.bounceAt(b, 0.38 + (0.53 - 0.38) * 0.5)
    check('it is thrown down, not dropped', half < 0.56 and half > 0.44, ('rise %.3f half way down'):format(half))

    local entry = M.entryTime(b, 2.367)
    check('a cycle is come into with the ball in the hand', (M.bounceAt(b, entry)))
    check('and at the longest stay there', entry > 2.28 or entry < 0.38, ('entry %.3f'):format(entry))
end

--------------------------------------------------------------------------------
-- Which cycle for which pace
--------------------------------------------------------------------------------
do
    local gaits = {
        { name = 'idle', speed = 0.0 },
        { name = 'walk', speed = 1.65 },
        { name = 'jog',  speed = 3.06 },
        { name = 'run',  speed = 4.46 },
        { name = 'sprint', speed = 6.13 },
    }

    local function name(speed, current) return gaits[M.pickGait(gaits, speed, current)].name end

    check('standing still is the standing cycle', name(0.0) == 'idle')
    check('a walk is the walk', name(1.5) == 'walk')
    check('a jog is the jog', name(3.2) == 'jog')
    check('a run is the run', name(4.6) == 'run')
    check('a sprint is the sprint', name(7.0) == 'sprint')

    check('setting off leaves the standing cycle at once', name(0.7, 1) == 'walk', name(0.7, 1))
    check('a walker who slows a little is still walking', name(0.45, 2) == 'walk')
    check('one who stops is standing', name(0.1, 2) == 'idle')

    -- Half way between a walk and a jog: whichever is playing carries on.
    check('between two paces the one playing is kept (slower)', name(2.4, 2) == 'walk')
    check('between two paces the one playing is kept (faster)', name(2.3, 3) == 'jog')
    check('but not once the pace is clearly the other', name(3.0, 2) == 'jog' and name(1.7, 3) == 'walk')

    -- No flicker: sweep the pace up and down and count the changes.
    local current, changes = 1, 0
    for i = 0, 2000 do
        local speed = 3.5 + 3.5 * math.sin(i / 2000.0 * 2.0 * math.pi) + 0.12 * math.sin(i * 1.7)
        local next = M.pickGait(gaits, speed, current)
        if next ~= current then changes = changes + 1 end
        current = next
    end
    check('a wavering pace does not flicker between cycles', changes <= 10, ('%d changes'):format(changes))

    check('one cycle is always that cycle', M.pickGait({ gaits[1] }, 5.0) == 1)

    check('a cycle is played at the pace the ped is going', near(M.gaitRate(gaits[3], 3.06), 1.0)
        and near(M.gaitRate(gaits[3], 3.366), 1.1, 1e-6))
    check('within reason', M.gaitRate(gaits[2], 0.2) == 0.8 and M.gaitRate(gaits[2], 9.0) == 1.3)
    check('and the standing one at its own', M.gaitRate(gaits[1], 0.3) == 1.0)
end

--------------------------------------------------------------------------------
-- A ball that comes to you
--------------------------------------------------------------------------------
do
    local cfg = { enabled = true, reach = 0.95, above = 1.3, delay = 650, minSpeed = 0.7, maxSpeed = 14.0 }
    local me = { x = 0, y = 0, z = 1.0, vx = 0, vy = 0, vz = 0 }

    local function ball(x, y, z, vx, vy, vz) return { x = x, y = y, z = z, vx = vx, vy = vy, vz = vz } end

    check('a rebound dropping into your arms is caught', M.catchable(ball(0.3, 0.2, 1.4, 0.5, 0.0, -3.0), me, 2.0, cfg))
    check('one bouncing past your hip is caught', M.catchable(ball(0.6, 0.0, 0.6, -2.0, 1.0, 1.5), me, 1.0, cfg))
    check('not one out of reach', not M.catchable(ball(1.2, 0.0, 1.2, -2.0, 0.0, 0.0), me, 2.0, cfg))
    check('not one over your head', not M.catchable(ball(0.1, 0.0, 2.6, 0.0, 0.0, -4.0), me, 2.0, cfg))
    check('not one lying still at your feet', not M.catchable(ball(0.3, 0.0, 0.12, 0.0, 0.0, 0.0), me, 5.0, cfg))
    check('not the shot you have only just let go of', not M.catchable(ball(0.3, 0.0, 2.2, 3.0, 0.0, 6.0), me, 0.2, cfg))
    check('not one going past like a bullet', not M.catchable(ball(0.3, 0.0, 1.2, 20.0, 0.0, 0.0), me, 2.0, cfg))
    check('but one you are running alongside is', M.catchable(ball(0.3, 0.0, 1.2, 9.0, 0.0, 0.5),
        { x = 0, y = 0, z = 1.0, vx = 6.0, vy = 0, vz = 0 }, 2.0, cfg))
    check('nothing is caught with it switched off', not M.catchable(ball(0.3, 0.2, 1.4, 0.5, 0.0, -3.0), me, 2.0,
        { enabled = false, reach = 0.95 }))
    check('or with no settings at all', not M.catchable(ball(0.3, 0.2, 1.4, 0.5, 0.0, -3.0), me, 2.0, nil))
end

--------------------------------------------------------------------------------
-- Easing and turning
--------------------------------------------------------------------------------
do
    local x, y, z, arrived = M.ease(0, 0, 0, 1, 2, 4, 0, 200)
    check('a gathered ball starts where it was', x == 0 and y == 0 and z == 0 and not arrived)

    x, y, z, arrived = M.ease(0, 0, 0, 1, 2, 4, 100, 200)
    check('is half way at half time', near(x, 0.5) and near(y, 1.0) and near(z, 2.0) and not arrived)

    x, y, z, arrived = M.ease(0, 0, 0, 1, 2, 4, 200, 200)
    check('and has arrived at the end', x == 1 and y == 2 and z == 4 and arrived)

    local prev, smooth = 0.0, true
    for ms = 0, 200, 5 do
        local ex = M.ease(0, 0, 0, 1, 0, 0, ms, 200)
        if ex < prev - 1e-12 then smooth = false end
        prev = ex
    end
    check('without ever going back on itself', smooth)

    check('the short way round, left', near(M.turn(350.0, 10.0), 20.0))
    check('the short way round, right', near(M.turn(10.0, 350.0), -20.0))
    check('a turn is taken a step at a time', near(M.turnToward(350.0, 10.0, 5.0), 355.0))
    check('across north', near(M.turnToward(358.0, 10.0, 5.0), 3.0))
    check('and stops where it was going', near(M.turnToward(8.0, 10.0, 5.0), 10.0))
end

print(('moves: %d passed, %d failed'):format(passed, failed))

return failed
