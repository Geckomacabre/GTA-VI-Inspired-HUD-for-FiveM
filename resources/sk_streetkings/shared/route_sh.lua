-- Route expansion.
--
-- Shared between client (rendering) and server (validation) so both always
-- agree on the exact checkpoint sequence for a given route/lap count. The route
-- definitions themselves live in data/races.lua.
SKRouteBuilder = {}

-- Expands a route definition into the full ordered checkpoint list a run must
-- complete. `lapsOverride` lets a multiplayer host pick 1-Config.LapsMax laps
-- on 'circuit' routes; ignored for other schemes.
function SKRouteBuilder.buildCheckpointList(def, lapsOverride)
    local cps = {}

    if def.scheme == 'thereandback' then
        for i = 1, #def.checkpoints do cps[#cps + 1] = def.checkpoints[i] end
        for i = #def.checkpoints - 1, 1, -1 do cps[#cps + 1] = def.checkpoints[i] end
        cps[#cps + 1] = vec3(def.start.x, def.start.y, def.start.z)
        return cps
    end

    if def.scheme == 'circuit' then
        local laps = math.max(Config.LapsMin, math.min(lapsOverride or def.laps or 1, Config.LapsMax))
        -- Close every lap back at the start/finish line instead of jumping
        -- straight from the last checkpoint into the next lap's first one.
        -- Without this, a route whose last checkpoint doesn't sit right next
        -- to `start` produces a long stray leg at every lap boundary (and the
        -- race never actually finishes back at the start line either).
        for _ = 1, laps do
            for i = 1, #def.checkpoints do cps[#cps + 1] = def.checkpoints[i] end
            cps[#cps + 1] = vec3(def.start.x, def.start.y, def.start.z)
        end
        return cps
    end

    -- 'ordered' (default): single point-to-point sprint
    for i = 1, #def.checkpoints do cps[#cps + 1] = def.checkpoints[i] end
    return cps
end

-- Per-checkpoint accept radius, expanded in lockstep with buildCheckpointList
-- so index i in one list always corresponds to index i in the other. Missing
-- per-point radii (the common case — hand-authored data/races.lua routes never
-- set these) fall back to the global config default. Lets the /racemaker
-- editor widen or tighten individual checkpoints without touching every route.
function SKRouteBuilder.buildCheckpointRadii(def, lapsOverride)
    local radii = {}
    local perPoint = def.checkpointRadii

    local function pushRadius(i)
        radii[#radii + 1] = (perPoint and perPoint[i]) or Config.CheckpointRadius
    end

    if def.scheme == 'thereandback' then
        for i = 1, #def.checkpoints do pushRadius(i) end
        for i = #def.checkpoints - 1, 1, -1 do pushRadius(i) end
        radii[#radii + 1] = def.startRadius or Config.StartRadius
        return radii
    end

    if def.scheme == 'circuit' then
        local laps = math.max(Config.LapsMin, math.min(lapsOverride or def.laps or 1, Config.LapsMax))
        for _ = 1, laps do
            for i = 1, #def.checkpoints do pushRadius(i) end
            radii[#radii + 1] = def.startRadius or Config.StartRadius
        end
        return radii
    end

    -- 'ordered' (default): single point-to-point sprint
    for i = 1, #def.checkpoints do pushRadius(i) end
    return radii
end

-- For every entry of buildCheckpointList, the index of the def.checkpoints entry it came from, or
-- 0 for the start/finish line the builder appends. Lets per-gate data (gateKinds, gateStunts,
-- gateHeadings, which are indexed by def.checkpoints) follow the expanded list through laps.
function SKRouteBuilder.buildSourceIndex(def, lapsOverride)
    local src = {}
    local n = #def.checkpoints

    if def.scheme == 'thereandback' then
        for i = 1, n do src[#src + 1] = i end
        for i = n - 1, 1, -1 do src[#src + 1] = i end
        src[#src + 1] = 0
        return src
    end

    if def.scheme == 'circuit' then
        local laps = math.max(Config.LapsMin, math.min(lapsOverride or def.laps or 1, Config.LapsMax))
        for _ = 1, laps do
            for i = 1, n do src[#src + 1] = i end
            src[#src + 1] = 0
        end
        return src
    end

    for i = 1, n do src[#src + 1] = i end
    return src
end

-- Start point + one lap of checkpoints, for distance measurement and map previews.
function SKRouteBuilder.buildPreviewRoute(def)
    local route = { vec3(def.start.x, def.start.y, def.start.z) }
    for i = 1, #def.checkpoints do route[#route + 1] = def.checkpoints[i] end
    return route
end

function SKRouteBuilder.routeDistanceMeters(def)
    local route = SKRouteBuilder.buildPreviewRoute(def)
    local dist = 0.0
    for i = 2, #route do dist = dist + #(route[i] - route[i - 1]) end
    return dist
end
