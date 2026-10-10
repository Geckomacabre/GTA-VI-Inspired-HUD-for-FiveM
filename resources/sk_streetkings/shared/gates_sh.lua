-- Race gate rules, taken from Rockstar's own stunt-plane and offroad race scripts
-- (_devtools/StuntPlaneRaces, _devtools/Offroad_Races). Shared by the client, which judges a
-- gate the instant the vehicle reaches it, and the server, which re-checks every claim.
--
-- Pure maths on {x, y, z} tables (vector3 works too) so the same file runs under the headless
-- checks in _tools/race_sim.
--
-- Rockstar's judge (SPTT_Gate_Check_Pass): take the vector from the plane to the gate, express it in
-- the plane's own frame, and pass when the plane is within 6.5 m of the gate's plane (|forward|) and
-- the gate lies within radius R of its axis: inside 10.5 m (sqrt 110) is the "inner" (perfect) ring,
-- inside 30 m (sqrt 900) is the "outer" ring. Bonuses are seconds taken off the clock, penalties are
-- seconds added.

SKGates = {}

SKGates.Rule = {
    forwardWindow = 6.5,     -- max |dot(planeToGate, planeForward)|
    innerSq       = 110.0,   -- lateral distance squared, perfect ring
    outerSq       = 900.0,   -- lateral distance squared, gate ring
    missScale     = 5.0,     -- a gate is missed inside radius * this ...
    missBehind    = 15.0,    -- ... once the plane is this far past it along the way to the next gate
    invertUpZ     = -0.8660, -- up.z at or below this is inverted (Rockstar: -cos 30)
    -- STUNT_PLANE_KNIFE_THRESHOLD lives in a header that is not in the dump; 0.5 (bank within
    -- 30 deg of vertical) is this port's choice, not Rockstar's number.
    knifeUpZ      = 0.5,
    -- The server sees the plane a network hop after the client judged it, so it accepts a wider band.
    serverKnifeUpZ  = 0.75,
    serverInvertUpZ = -0.5,
    serverInnerSq   = 260.0,
}

-- Seconds. Positive = taken off the clock, negative = added to it.
SKGates.Seconds = {
    perfect      = 1.0,  -- flew the inner ring, level
    pass         = 0.0,  -- flew the outer ring, level
    knife_inner  = 2.5,
    knife_outer  = 1.5,
    invert_inner = 3.0,
    invert_outer = 2.0,
    stunt        = 4.0,  -- did the stunt this gate asked for
    stunt_wrong  = -1.5, -- flew through a stunt gate without doing its stunt
    miss         = -5.0, -- flew past the gate
}

-- Every status a client may report. Anything else is refused by the server.
SKGates.Status = {
    perfect = true, pass = true, knife_inner = true, knife_outer = true,
    invert_inner = true, invert_outer = true, stunt = true, stunt_wrong = true, miss = true,
}

local function dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end

-- 'inverted' | 'left' | 'right' | 'level' from a plane's right and up vectors.
-- Left/right follow Rockstar: knifing left when the right wing is up (right.z > 0).
function SKGates.roll(right, up)
    if up.z <= SKGates.Rule.invertUpZ then return 'inverted' end
    if math.abs(up.z) <= SKGates.Rule.knifeUpZ then
        return right.z > 0.0 and 'left' or 'right'
    end
    return 'level'
end

-- Where the plane is relative to a gate. basis = { pos, fwd, right, up }.
-- Returns 'inner' | 'outer' | nil (not through the gate yet).
function SKGates.ring(gatePos, basis)
    local d = sub(gatePos, basis.pos)
    if math.abs(dot(d, basis.fwd)) > SKGates.Rule.forwardWindow then return nil end
    local u, r = dot(d, basis.up), dot(d, basis.right)
    local lateralSq = u * u + r * r
    if lateralSq > SKGates.Rule.outerSq then return nil end
    return lateralSq > SKGates.Rule.innerSq and 'outer' or 'inner'
end

-- Judge one gate. stunt = 'inverted' | 'left' | 'right' | false/nil for a plain gate.
-- Returns the status string, or nil while the plane has not reached the gate.
function SKGates.judge(gatePos, stunt, basis)
    local ring = SKGates.ring(gatePos, basis)
    if not ring then return nil end
    local roll = SKGates.roll(basis.right, basis.up)

    if stunt then
        return roll == stunt and 'stunt' or 'stunt_wrong'
    end
    if roll == 'inverted' then return 'invert_' .. ring end
    if roll == 'left' or roll == 'right' then return 'knife_' .. ring end
    return ring == 'inner' and 'perfect' or 'pass'
end

-- True when the plane has flown past the gate without going through it.
-- The last gate has no next gate, so it can never be "missed" - it has to be flown.
function SKGates.isMiss(pos, gatePos, nextGatePos, radius)
    if not nextGatePos then return false end
    local dx, dy, dz = nextGatePos.x - gatePos.x, nextGatePos.y - gatePos.y, nextGatePos.z - gatePos.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 0.001 then return false end
    local reach = (radius or 30.0) * SKGates.Rule.missScale
    local off = sub(pos, gatePos)
    if math.abs(off.x) > reach or math.abs(off.y) > reach or math.abs(off.z) > reach then return false end
    return (off.x * dx + off.y * dy + off.z * dz) / len > SKGates.Rule.missBehind
end

-- Basis vectors from a GTA entity rotation in degrees (rotation order 2, what the server can
-- read: rx pitch, ry roll, rz yaw).
function SKGates.basisFromRotation(pos, rx, ry, rz)
    local sx, cx = math.sin(math.rad(rx)), math.cos(math.rad(rx))
    local sy, cy = math.sin(math.rad(ry)), math.cos(math.rad(ry))
    local sz, cz = math.sin(math.rad(rz)), math.cos(math.rad(rz))
    return {
        pos   = pos,
        right = { x = cz * cy - sz * sx * sy, y = sz * cy + cz * sx * sy, z = -cx * sy },
        fwd   = { x = -sz * cx,               y = cz * cx,                z = sx },
        up    = { x = cz * sy + sz * sx * cy, y = sz * sy - cz * sx * cy, z = cx * cy },
    }
end

-- The server's version of a client claim. It cannot trust the reported status, so it re-derives
-- what it can from its own reading of the plane: the ring from distance, the tilt from up.z.
-- (Left vs right is not re-derived: the sign of a roll under GetEntityRotation was not checked
-- against a live plane, so only *that* the plane is banked is verified, not which wing is up.)
-- Returns the status to score - the claim, or a downgrade of it - or nil for a claim it refuses.
function SKGates.verifyClaim(claim, stunt, pos, gatePos, upZ)
    if not SKGates.Status[claim] or claim == 'miss' then return nil end

    local d = sub(pos, gatePos)
    local distSq = d.x * d.x + d.y * d.y + d.z * d.z
    local inner = distSq <= SKGates.Rule.serverInnerSq

    local tilt = 'level'
    if upZ <= SKGates.Rule.serverInvertUpZ then
        tilt = 'inverted'
    elseif math.abs(upZ) <= SKGates.Rule.serverKnifeUpZ then
        tilt = 'knife'
    end

    if stunt then
        local ok = (stunt == 'inverted' and tilt == 'inverted')
            or ((stunt == 'left' or stunt == 'right') and tilt == 'knife')
        return (claim == 'stunt' and ok) and 'stunt' or 'stunt_wrong'
    end

    -- Plain gate: what the server sees decides the bonus, the claim only has to be a real status.
    local ring = inner and 'inner' or 'outer'
    if tilt == 'inverted' then return 'invert_' .. ring end
    if tilt == 'knife' then return 'knife_' .. ring end
    return inner and 'perfect' or 'pass'
end

-- Seconds a status is worth (positive = off the clock).
function SKGates.seconds(status)
    return SKGates.Seconds[status] or 0.0
end

-- Adjusted clock in ms: raw time with every bonus taken off and every penalty added.
function SKGates.adjustedMs(rawMs, netBonusSeconds)
    return math.max(0, math.floor(rawMs - netBonusSeconds * 1000.0 + 0.5))
end

-- 'gold' | 'silver' | 'bronze' | nil for an adjusted time in seconds.
function SKGates.medal(medals, adjustedSec)
    if not medals then return nil end
    if adjustedSec <= medals.gold then return 'gold' end
    if adjustedSec <= medals.silver then return 'silver' end
    if adjustedSec <= medals.bronze then return 'bronze' end
    return nil
end

-- ── Checkpoint art, from the game's own CHECKPOINT_TYPE enum ─────────────────
-- (numbers as of game build 2189, the FiveM docs' current table)
SKGates.Art = {
    groundChevron1Base = 0, groundChevron2Base = 1, groundChevron3Base = 2,
    groundLapBase = 3, groundFlagBase = 4,
    airChevron1 = 12, airChevron2 = 13, airChevron3 = 14, airLap = 15, airFlag = 16,
    planeFlat = 37, planeSideLeft = 38, planeSideRight = 39, planeInverted = 40,
}

-- Rockstar picks 1, 2 or 3 chevrons by how sharply the route turns at the gate: the angle between
-- the way back and the way on. >= 140 deg is a straight (1), 80-140 a bend (2), tighter is a hairpin (3).
function SKGates.chevronForTurn(prev, pos, nxt)
    if not prev or not nxt then return 1 end
    local ax, ay = prev.x - pos.x, prev.y - pos.y
    local bx, by = nxt.x - pos.x, nxt.y - pos.y
    local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
    if la < 0.001 or lb < 0.001 then return 1 end
    local c = math.max(-1.0, math.min(1.0, (ax * bx + ay * by) / (la * lb)))
    local angle = math.deg(math.acos(c))
    if angle < 80.0 then return 3 end
    if angle < 140.0 then return 2 end
    return 1
end

-- Checkpoint art id + RGB for a gate.
--   kind: 'road' | 'offroad' | 'air'      gateKind: 'default' | 'stunt'
--   stunt: 'inverted' | 'left' | 'right'  isLast / isLapEnd
-- Colours are Rockstar's: yellow for the route, green knife gates, blue inverted gates.
function SKGates.art(kind, gateKind, stunt, isLast, isLapEnd, chevron)
    local A = SKGates.Art
    chevron = chevron or 1
    if kind == 'air' then
        if isLast then return A.airFlag, 254, 207, 12 end
        if gateKind == 'stunt' then
            if stunt == 'left' then return A.planeSideLeft, 114, 204, 114 end
            if stunt == 'right' then return A.planeSideRight, 114, 204, 114 end
            return A.planeInverted, 93, 182, 229
        end
        if isLapEnd then return A.airLap, 254, 207, 12 end
        return A.airChevron1 + (chevron - 1), 254, 207, 12
    end
    -- road / offroad: the base variants sit on the ground, which is where route points are
    if isLast then return A.groundFlagBase, 254, 207, 12 end
    if isLapEnd then return A.groundLapBase, 254, 207, 12 end
    return A.groundChevron1Base + (chevron - 1), 254, 207, 12
end
