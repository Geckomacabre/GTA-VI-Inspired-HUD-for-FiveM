--[[
    Make percentage by release accuracy and distance, with the real rim, a
    backboard and the same scatter the game uses. Not a pass/fail test: it is the
    table Config.Shot.lateralError / depthError were tuned against.

        python tests/run.py makes [lateral] [depth] [rimRadius] [entryAngle]
]]

local P = BB.physics

local lateral = tonumber(ARGS[1]) or 0.040
local depth   = tonumber(ARGS[2]) or 0.046
local RIM_R   = tonumber(ARGS[3]) or 0.235
local ANGLE   = tonumber(ARGS[4]) or 46.0
local SHOTS   = 300
local RIM_Z, RELEASE_Z = 3.05, 2.1

-- Config.Shot's distance penalty, as releaseAccuracy applies it.
local CLOSE, MAXR, PENALTY = 4.0, 26.0, 0.45

local prm = P.params()
math.randomseed(1234)

local function shot(dist, accuracy)
    local W = World.new({})
    W.plane(0, 0, 1, 0)
    -- Backboard: 0.15 m behind the back of the ring, 1.83 wide, 1.07 tall.
    W.plane(-1, 0, 0, -(dist + RIM_R + 0.15), nil, function(_, y, z)
        return math.abs(y) < 0.915 and z > RIM_Z - 0.15 and z < RIM_Z + 0.92
    end)
    W.rims[1] = { x = dist, y = 0.0, z = RIM_Z, R = RIM_R, tube = 0.009 }

    local far = math.max(0.0, math.min(1.0, (dist - CLOSE) / (MAXR - CLOSE)))
    local acc = accuracy * (1.0 - far * PENALTY)
    local side, long = P.scatter(acc, dist, lateral, depth)

    local time = P.flightTime(prm, RIM_Z - RELEASE_Z, dist, ANGLE)
    local wx, wy, wz = P.backspin(1.0, 0.0, 12.0)
    local vx, vy, vz = P.solveLaunch(prm, 0, 0, RELEASE_Z, dist + long, side, RIM_Z, time, wx, wy, wz)

    local b = P.new(0, 0, RELEASE_Z)
    b.vx, b.vy, b.vz = vx, vy, vz
    b.wx, b.wy, b.wz = wx, wy, wz

    local prev, made, primed = b.z, false, false
    W.run(b, prm, time + 2.5, 60, function(ball)
        local d = math.sqrt((ball.x - dist) ^ 2 + ball.y ^ 2)
        if ball.z > RIM_Z + 0.08 and d > RIM_R then primed = true end
        if primed and prev > RIM_Z and ball.z <= RIM_Z and d < RIM_R then
            made = true
            return false
        end
        prev = ball.z
        if ball.z < 1.5 and ball.vz < 0 then return false end
    end)

    return made, W.count('rim') == 0
end

print(('lateral %.3f  depth %.3f  rim radius %.3f  entry angle %.0f   (%d shots a cell; made%% / swish%%)')
    :format(lateral, depth, RIM_R, ANGLE, SHOTS))

local dists = { 1.5, 3.0, 4.5, 7.0, 10.0, 14.0, 20.0 }
local head = 'release  '
for _, d in ipairs(dists) do head = head .. ('%7.1fm  '):format(d) end
print(head)

for _, accuracy in ipairs({ 1.0, 0.9, 0.8, 0.65, 0.5, 0.3, 0.0 }) do
    local line = ('  %.2f   '):format(accuracy)

    for _, d in ipairs(dists) do
        local made, clean = 0, 0
        for _ = 1, SHOTS do
            local m, c = shot(d, accuracy)
            if m then
                made = made + 1
                if c then clean = clean + 1 end
            end
        end
        line = line .. ('%3d/%3d   '):format(math.floor(100 * made / SHOTS + 0.5), math.floor(100 * clean / SHOTS + 0.5))
    end

    print(line)
end

return 0
