--[[
    The arithmetic behind carrying a ball, kept apart from the game so it can be
    checked on a desk (tests/moves_test.lua). No natives in here.

    A real dribble animation knows its own bounces: when the hand lets the ball
    go, when the ball meets the floor, when the hand has it again. So the
    animation is the clock and the ball does what the animation says, rather
    than the ball bouncing to a beat of its own with an arm waved at it.
]]

BB.moves = {}

local M = BB.moves

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--------------------------------------------------------------------------------
-- Bounces
--------------------------------------------------------------------------------

--- The bounces of a dribble cycle that can be relied on: each one let go of,
--- then on the floor, then caught, in that order and inside the clip.
--- @param bounces table|nil { { push, floor, catch }, ... } in seconds
--- @param duration number Length of the clip, seconds
--- @return table list, sorted by when the ball is let go
function M.cleanBounces(bounces, duration)
    local out = {}

    for _, b in ipairs(bounces or {}) do
        local push, catch = tonumber(b.push), tonumber(b.catch)

        if push and catch and push >= 0.0 and catch > push + 0.05 and catch <= duration + 0.02 then
            local floor = tonumber(b.floor)

            -- A bounce that doesn't say when it reached the floor reached it a
            -- little before half way: the ball is thrown down, and climbs back
            -- against gravity.
            if not floor or floor <= push or floor >= catch then
                floor = push + (catch - push) * 0.44
            end

            out[#out + 1] = { push = push, floor = floor, catch = math.min(catch, duration) }
        end
    end

    table.sort(out, function(a, b) return a.push < b.push end)

    -- No two at once: one that starts before the last has been caught is dropped.
    local kept = {}
    for _, b in ipairs(out) do
        if #kept == 0 or b.push >= kept[#kept].catch then kept[#kept + 1] = b end
    end

    return kept
end

-- How the ball travels between hand and floor. It is thrown down, so it is
-- already quick when it leaves the hand, and it comes back up against gravity,
-- slowing a little into the palm. Both are close to straight lines; a curve
-- that eases in and out at the hand reads as a balloon.
local DOWN_THROW = 0.88     -- share of the way down owed to the throw rather than to gravity
local UP_SLOWING = 0.22

--- Where the ball is in a dribble cycle.
--- @param bounces table From M.cleanBounces
--- @param t number Seconds into the clip
--- @return boolean inHand
--- @return number rise 1 with the ball in the hand, 0 with it on the floor
--- @return boolean falling True on the way down, false on the way up (and in the hand)
--- @return integer k Which bounce (0 if in the hand)
function M.bounceAt(bounces, t)
    for k = 1, #bounces do
        local b = bounces[k]

        if t >= b.push and t < b.catch then
            if t < b.floor then
                local s = (t - b.push) / (b.floor - b.push)
                return false, 1.0 - (DOWN_THROW * s + (1.0 - DOWN_THROW) * s * s), true, k
            end

            local s = (t - b.floor) / (b.catch - b.floor)
            return false, (1.0 + UP_SLOWING) * s - UP_SLOWING * s * s, false, k
        end
    end

    return true, 1.0, false, 0
end

--- A moment in a cycle at which the ball is in the hand and stays there longest:
--- where to come into the cycle from something else.
--- @return number seconds
function M.entryTime(bounces, duration)
    local n = #bounces
    if n == 0 then return 0.0 end

    local best, bestGap = 0.0, -1.0

    for k = 1, n do
        local from = bounces[k].catch
        local to   = k < n and bounces[k + 1].push or (bounces[1].push + duration)
        local gap  = to - from

        if gap > bestGap then
            bestGap = gap
            best = from + math.min(0.02, gap * 0.25)
        end
    end

    return best % duration
end

--------------------------------------------------------------------------------
-- Which cycle for which pace
--------------------------------------------------------------------------------

--[[
    `gaits` is the pack's dribble cycles, slowest first. Each was made at a pace
    (`speed`, metres a second; 0 for the one that stands still), and the one
    nearest to how fast somebody is moving is the one whose feet will fit.

    `current` holds on to the cycle already playing until the pace is clearly
    another's, so a ped moving at a pace half way between two doesn't flicker
    between them.
]]
--- @return integer index into gaits
function M.pickGait(gaits, speed, current, margin)
    local n = #gaits
    if n <= 1 then return 1 end

    margin = margin or 0.3

    -- The edge between one cycle and the next up.
    local function edge(i)
        local a, b = gaits[i].speed, gaits[i + 1].speed

        -- Standing gives way to walking well before half a walk's pace: feet
        -- planted while the body slides is the worst thing this can do.
        if a <= 0.05 then return math.min(0.5, b * 0.35) end

        return (a + b) * 0.5
    end

    if current and current >= 1 and current <= n then
        local lower = current > 1 and edge(current - 1) - margin or -1.0
        local upper = current < n and edge(current) + margin or math.huge

        -- Setting off and coming to a stop are never put off: only a hair of
        -- give either side of that edge, enough not to flicker.
        if gaits[1].speed <= 0.05 then
            if current == 1 then upper = edge(1) + 0.1 end
            if current == 2 then lower = edge(1) * 0.5 end
        end

        if speed >= lower and speed <= upper then return current end
    end

    for i = 1, n - 1 do
        if speed < edge(i) then return i end
    end

    return n
end

--- How fast to play a cycle so that its steps cover the ground actually covered.
function M.gaitRate(gait, speed)
    if not gait.speed or gait.speed <= 0.05 then return 1.0 end

    return clamp(speed / gait.speed, 0.8, 1.3)
end

--------------------------------------------------------------------------------
-- Taking a ball out of the air
--------------------------------------------------------------------------------

--[[
    A ball that comes to somebody is caught. Nobody presses a key to catch a
    rebound that has dropped into their arms; having to is why a ball used to
    bounce off the chest of the player waiting for it.

    Only a ball that is moving, and has been loose for a moment: a shot is not
    taken back out of the shooter's own hands as it leaves them, and one lying
    still on the floor is somebody's to bend down for, not something to be
    hoovered up by walking past.
]]
--- @param ball table { x, y, z, vx, vy, vz }
--- @param me table { x, y, z, vx, vy, vz } A ped's position (the middle of it) and velocity
--- @param age number Seconds since the ball came loose
--- @param cfg table Config.Ball.autoCatch
function M.catchable(ball, me, age, cfg)
    if not cfg or cfg.enabled == false then return false end
    if age < (cfg.delay or 650) / 1000.0 then return false end

    local dx, dy, dz = ball.x - me.x, ball.y - me.y, ball.z - me.z
    if dx * dx + dy * dy > cfg.reach * cfg.reach then return false end

    -- From the floor to as high as hands go.
    if dz < -1.0 or dz > (cfg.above or 1.3) then return false end

    local speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy + ball.vz * ball.vz)
    if speed < (cfg.minSpeed or 0.7) then return false end

    local rx, ry, rz = ball.vx - (me.vx or 0.0), ball.vy - (me.vy or 0.0), ball.vz - (me.vz or 0.0)
    if math.sqrt(rx * rx + ry * ry + rz * rz) > (cfg.maxSpeed or 14.0) then return false end

    return true
end

--------------------------------------------------------------------------------
-- Not jumping from one place to another
--------------------------------------------------------------------------------

--- A point part of the way from one place to another, for a ball that is being
--- gathered in rather than appearing where it is wanted.
--- @param elapsed number ms since it set off
--- @param window number ms it takes
--- @return number x, number y, number z, boolean arrived
function M.ease(fx, fy, fz, tx, ty, tz, elapsed, window)
    if window <= 0 or elapsed >= window then return tx, ty, tz, true end
    if elapsed <= 0 then return fx, fy, fz, false end

    local k = elapsed / window
    k = k * k * (3.0 - 2.0 * k)

    return fx + (tx - fx) * k, fy + (ty - fy) * k, fz + (tz - fz) * k, false
end

--- The shortest turn from one heading to another, degrees, -180..180.
function M.turn(from, to)
    return ((to - from + 540.0) % 360.0) - 180.0
end

--- A heading turned toward another by no more than `step` degrees.
function M.turnToward(from, to, step)
    local diff = M.turn(from, to)

    if math.abs(diff) <= step then return to % 360.0 end

    return (from + (diff > 0.0 and step or -step)) % 360.0
end
