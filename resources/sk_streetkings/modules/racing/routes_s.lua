-- Merges the static SKRaceEvents (shared/events.lua) with admin-created routes
-- saved to the sk_race_routes table (via /racemaker, see server/admin.lua).

SKRoutes = {}

local customRoutes = {}

local function toVec4(t) return vec4(t.x, t.y, t.z, t.w or 0.0) end
local function toVec3(t) return vec3(t.x, t.y, t.z) end

-- Per-point `radius` is optional on each checkpoint (only present when placed
-- with a custom accept radius in /racemaker). Returns nil, not a table of
-- nils, when no point in the route set one — SKRouteBuilder.buildCheckpointRadii
-- reads a nil def.checkpointRadii as "use the config default everywhere".
local function extractRadii(checkpoints)
    local radii, any = {}, false
    for i, cp in ipairs(checkpoints) do
        if cp.radius then any = true end
        radii[i] = cp.radius
    end
    return any and radii or nil
end

-- Reused by admin_s.lua when building the in-memory def straight off a just-
-- saved routeData table (same shape as the JSON-decoded `data.checkpoints`
-- above), so a save takes effect live without waiting on loadCustomRoutes.
SKRoutes.extractRadii = extractRadii

local STUNTS = { inverted = true, left = true, right = true }

-- The air/offroad fields of a saved route, checked. Used both when loading rows and when an admin
-- saves one, so a hand-edited row or a tampered save cannot put an unknown vehicle, an inverted
-- medal table or a gate array of the wrong length into a live route.
---@param data table decoded route data
---@param n integer number of checkpoints
---@return table fields merged into the route definition
local function extraFields(data, n)
    local out = { kind = 'road' }
    if data.kind == 'air' or data.kind == 'offroad' then out.kind = data.kind end

    local allowed = data.vehicle and Config.RaceVehicles[data.vehicle.model]
    if out.kind ~= 'road' and allowed and allowed.kind == out.kind then
        out.vehicle = {
            model = data.vehicle.model, netType = allowed.netType,
            type = out.kind == 'air' and 'plane' or 'land',
            spawn = out.kind == 'offroad', airborne = out.kind == 'air',
            speed = out.kind == 'air' and 40.0 or nil,
        }
    end

    if out.kind == 'air' then
        out.solo = true
        out.startRadius = 60.0
        if type(data.entry) == 'table' and tonumber(data.entry.x) and tonumber(data.entry.y) and tonumber(data.entry.z) then
            out.entry = vec3(data.entry.x + 0.0, data.entry.y + 0.0, data.entry.z + 0.0)
        end
        local kinds, stunts = {}, {}
        for i = 1, n do
            local st = data.gateStunts and data.gateStunts[i]
            if STUNTS[st] then kinds[i], stunts[i] = 'stunt', st else kinds[i], stunts[i] = 'default', false end
        end
        out.gateKinds, out.gateStunts = kinds, stunts

        local m = data.medals
        if type(m) == 'table' and tonumber(m.gold) and tonumber(m.silver) and tonumber(m.bronze)
            and m.gold > 0 and m.gold < m.silver and m.silver < m.bronze then
            out.medals = { gold = m.gold + 0.0, silver = m.silver + 0.0, bronze = m.bronze + 0.0 }
        end
    end
    return out
end
SKRoutes.extraFields = extraFields

local function loadCustomRoutes()
    local rows = MySQL.query.await('SELECT * FROM sk_race_routes', {}) or {}
    for _, row in ipairs(rows) do
        local ok, data = pcall(json.decode, row.data)
        if ok and type(data) == 'table' and data.checkpoints then
            local checkpoints = {}
            for i, cp in ipairs(data.checkpoints) do checkpoints[i] = toVec3(cp) end
            customRoutes[row.id] = {
                id                = row.id,
                name              = row.name,
                scheme            = row.scheme,
                laps              = data.laps or 1,
                goalTime          = data.goalTime,
                unlockRequirement = data.unlockRequirement,
                start             = toVec4(data.start),
                startRadius       = data.start.radius,
                checkpoints       = checkpoints,
                checkpointRadii   = extractRadii(data.checkpoints),
                custom            = true,
                creator           = row.creator,
            }
            for k, v in pairs(extraFields(data, #checkpoints)) do customRoutes[row.id][k] = v end
            -- extraFields only overrides startRadius for air routes
            if customRoutes[row.id].startRadius == nil then customRoutes[row.id].startRadius = data.start.radius end
        end
    end
    print(('^2[sk_streetkings]^0 Loaded %d custom route(s) from database.'):format(#rows))
end

MySQL.ready(function()
    loadCustomRoutes()
end)

function SKRoutes.getAll()
    local all = {}
    for id, def in pairs(SKRaceEvents) do all[id] = def end
    for id, def in pairs(customRoutes) do all[id] = def end
    return all
end

function SKRoutes.get(id)
    return SKRaceEvents[id] or customRoutes[id]
end

-- Called by server/admin.lua once a new route has been inserted into the DB.
function SKRoutes.addCustom(def)
    customRoutes[def.id] = def
end

-- Called by admin_s.lua after a custom route's row has been deleted.
function SKRoutes.removeCustom(id)
    customRoutes[id] = nil
end

---@param id string
---@return boolean
function SKRoutes.isCustom(id)
    return customRoutes[id] ~= nil
end

-- Client-facing payload: strip internal fields, send raw coord data.
local function toClientPayload(def)
    return {
        id = def.id, name = def.name, scheme = def.scheme, laps = def.laps,
        goalTime = def.goalTime, unlockRequirement = def.unlockRequirement,
        start = def.start, startRadius = def.startRadius,
        checkpoints = def.checkpoints, checkpointRadii = def.checkpointRadii,
        kind = def.kind, vehicle = def.vehicle, entry = def.entry, solo = def.solo,
        medals = def.medals, gateKinds = def.gateKinds, gateStunts = def.gateStunts,
        gateHeadings = def.gateHeadings, custom = def.custom,
    }
end

lib.callback.register('sk_streetkings:racing:getRoutes', function(_source)
    local out = {}
    for id, def in pairs(SKRoutes.getAll()) do
        out[id] = toClientPayload(def)
    end
    return out
end)

-- Checks def.unlockRequirement against the citizen's progress. Returns true if
-- unmet requirements block the run, so callers can reject with a clear reason.
function SKRoutes.checkUnlockRequirement(def, citizenid)
    local req = def.unlockRequirement
    if not req then return true end

    if req.barnFindsCompleted then
        local completed = tonumber(MySQL.scalar.await(
            'SELECT COUNT(*) FROM barn_finds WHERE citizenid = ? AND status = ?', { citizenid, 'completed' }
        )) or 0
        if completed < req.barnFindsCompleted then
            return false, ('Complete %d barn finds first (%d/%d so far)'):format(req.barnFindsCompleted, completed, req.barnFindsCompleted)
        end
    end

    return true
end

-- Lets the client compute lock/unlock state for every route locally instead of
-- round-tripping per route. qbox_barnfinds owns the `barn_finds` table; this is
-- a read-only query against it, no dependency on qbox_barnfinds being started.
lib.callback.register('sk_streetkings:racing:getPlayerProgress', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return { barnFindsCompleted = 0 } end

    local completed = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) FROM barn_finds WHERE citizenid = ? AND status = ?', { player.PlayerData.citizenid, 'completed' }
    )) or 0
    return { barnFindsCompleted = completed }
end)
