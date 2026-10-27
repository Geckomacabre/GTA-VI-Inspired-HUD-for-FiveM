-- Shared namespace. Every client/server file hangs its helpers off this so we
-- don't leak globals into the resource's Lua state.
BB = BB or {}

--- Global state key the hoops are published under. Shared so the server that
--- writes it and the client that reads it cannot disagree about the name.
BB.STATE_HOOPS = 'gk_basketball:hoops'

--- Global state key for which practice balls have been picked up off the floor.
BB.STATE_BALLS = 'gk_basketball:balls'

--- True if a court that only exists some of the time (an arena floor that has to
--- be set up for basketball) is there right now.
function BB.courtReady(courtId)
    local cfg = Config.Courts[courtId]
    local need = cfg and cfg.requires

    return not need or GlobalState[need.state] == need.value
end

--- Where a court's practice balls lie: where Config.Courts says, or failing that
--- a few set down near the middle of it.
--- @return table list of { x, y, z, settle }  settle = the height still has to be found from the floor
function BB.ballSpots(court)
    local cfg = Config.Courts[court.id]
    local spots = {}

    if cfg and cfg.balls then
        for i, at in ipairs(cfg.balls) do
            spots[i] = { x = at.x, y = at.y, z = at.z }
        end

        return spots
    end

    local n = Config.Ball.looseBalls or 0

    for i = 1, n do
        local a = (i - 1) / n * 2.0 * math.pi + 0.6

        spots[i] = {
            x = court.centre.x + math.cos(a) * 1.6,
            y = court.centre.y + math.sin(a) * 1.6,
            z = court.centre.z,
            settle = true,
        }
    end

    return spots
end

function BB.round(n, places)
    local mult = 10 ^ (places or 0)
    return math.floor(n * mult + 0.5) / mult
end

function BB.clamp(n, min, max)
    if n < min then return min end
    if n > max then return max end
    return n
end

--- 2D (ground plane) distance. Basketball is played on a floor, so almost every
--- distance question here wants to ignore height.
function BB.dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function BB.vec(t)
    return vec3(t.x + 0.0, t.y + 0.0, t.z + 0.0)
end

function BB.plain(v)
    return { x = BB.round(v.x, 4), y = BB.round(v.y, 4), z = BB.round(v.z, 4) }
end

--- Groups a flat hoop list into courts and works out each court's centre.
--- Used identically on both sides, so it lives here.
--- @param hoops table Array of { id, court, coords, team? }
--- @return table courts Keyed by court id: { id, label, hoops = {}, centre = vec3 }
function BB.buildCourts(hoops)
    local courts = {}

    for _, hoop in ipairs(hoops or {}) do
        local id = hoop.court or 'court'
        local court = courts[id]

        if not court then
            court = {
                id    = id,
                label = (Config.Courts[id] and Config.Courts[id].label) or Config.Text.court_label,
                hoops = {},
            }
            courts[id] = court
        end

        court.hoops[#court.hoops + 1] = hoop
    end

    for _, court in pairs(courts) do
        local sx, sy, sz = 0.0, 0.0, 0.0
        for _, hoop in ipairs(court.hoops) do
            sx, sy, sz = sx + hoop.coords.x, sy + hoop.coords.y, sz + hoop.coords.z
        end
        local n = #court.hoops
        -- Drop the centre to roughly floor level; rims sit ~3m up and the centre
        -- is used for blips and the interaction zone.
        court.centre = vec3(sx / n, sy / n, (sz / n) - 2.6)
    end

    return courts
end

--- Picks the hoop a shot should target.
--- @param hoops table Array of hoops
--- @param from vector3 Shooter position
--- @param forward vector3 Shooter facing (normalised, z ignored)
--- @param maxRange number
--- @param team string|nil When set, hoops locked to the shooter's own team are skipped
--- @return table|nil hoop, number|nil distance
function BB.pickTargetHoop(hoops, from, forward, maxRange, team)
    local best, bestScore, bestDist

    --[[
        Flatten the aim direction onto the ground plane before comparing.

        Callers pass a camera vector whose x/y are already scaled by cos(pitch),
        and the facing test below dots it against a unit direction — so `facing`
        could never exceed cos(pitch). Looking up 60 degrees capped it at 0.5;
        past about 78 it could never clear the 0.2 threshold at all.

        Which meant aim assist got harder the more you aimed at the basket, and
        eventually dropped out entirely — sending the shot down the no-target
        path as a full-power loose toss, straight up and back down on your head.
    ]]
    local fLen = math.sqrt(forward.x * forward.x + forward.y * forward.y)
    if fLen < 0.0001 then return nil end

    local fx, fy = forward.x / fLen, forward.y / fLen

    for _, hoop in ipairs(hoops) do
        -- A hoop tagged with a team is that team's basket to defend, so you
        -- score on the other one. Untagged hoops are fair game (pickup rules).
        if not (team and hoop.team and hoop.team == team) then
            local dist = BB.dist2d(from, hoop.coords)

            if dist <= maxRange then
                local dx, dy = hoop.coords.x - from.x, hoop.coords.y - from.y
                local len = math.sqrt(dx * dx + dy * dy)
                -- Favour hoops in front of the player, then nearer ones. Both
                -- sides of this dot product are unit vectors on the ground plane,
                -- so it's a straight cosine of the angle off your aim — camera
                -- pitch doesn't enter into it.
                local facing = len > 0.01 and ((dx / len) * fx + (dy / len) * fy) or 1.0

                if facing > 0.2 then
                    local score = facing - (dist / maxRange) * 0.5
                    if not bestScore or score > bestScore then
                        best, bestScore, bestDist = hoop, score, dist
                    end
                end
            end
        end
    end

    return best, bestDist
end

--[[
    The 'rings' shot (Config.Shot.style). Pure, like the rest of this file, so
    tests/rings_test.lua runs it as the game does.
]]

--- The rim under the reticle: the one nearest the middle of the screen, within
--- `maxAngle` degrees of it, in range of the shooter. Unlike pickTargetHoop this
--- is about where you are looking, pitch and all, because the reticle is.
--- @param eye vector3 Where the camera is
--- @param look vector3 Which way it looks (normalised)
--- @param from vector3 The shooter, for the range
--- @return table|nil hoop, number|nil distance (on the ground, from the shooter), number|nil degrees off
function BB.hoopInSights(hoops, eye, look, from, maxRange, team, maxAngle)
    local best, bestDist, bestAngle
    local limit = math.cos(math.rad(maxAngle))

    for _, hoop in ipairs(hoops) do
        if not (team and hoop.team and hoop.team == team) then
            local dist = BB.dist2d(from, hoop.coords)

            if dist <= maxRange then
                local dx, dy, dz = hoop.coords.x - eye.x, hoop.coords.y - eye.y, hoop.coords.z - eye.z
                local len = math.sqrt(dx * dx + dy * dy + dz * dz)

                if len > 0.01 then
                    local cos = (dx * look.x + dy * look.y + dz * look.z) / len

                    if cos >= limit then
                        local angle = math.deg(math.acos(math.min(cos, 1.0)))

                        if not bestAngle or angle < bestAngle then
                            best, bestDist, bestAngle = hoop, dist, angle
                        end
                    end
                end
            end
        end
    end

    return best, bestDist, bestAngle
end

--- How big the yellow ring is for a shot from `distance`, as a share of the
--- white one: nearSize up to closeRange, down to farSize at farAt and beyond.
function BB.ringSize(distance)
    local rings = Config.Shot.rings
    local close = Config.Shot.closeRange
    local t = BB.clamp((distance - close) / math.max(rings.farAt - close, 0.01), 0.0, 1.0)

    return rings.nearSize + (rings.farSize - rings.nearSize) * t
end

--- How far from the moment the rings met a release was, in ms: negative early,
--- positive late. The white ring closes from 1 to 0 in closeMs at a steady
--- speed, so it meets one of `size` (1 - size) * closeMs after it starts.
--- @param heldMs number How long THROW was held
--- @param size number The yellow ring, as from BB.ringSize
function BB.ringError(heldMs, size)
    return heldMs - (1.0 - size) * Config.Shot.rings.closeMs
end
