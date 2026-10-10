-- /racemaker admin tool: toggles the client-side freecam route placer
-- (modules/racing/route_maker_c.lua) and persists saved routes to
-- sk_race_routes.
--
-- Save/delete go through lib.callback so the client waits for the database
-- write to actually finish before reporting success — the previous version
-- fired a plain TriggerServerEvent at an un-awaited MySQL.insert and told the
-- admin "saved" immediately regardless of whether the write landed.

local adminGroups = { admin = true, god = true, superadmin = true }

local function isAdmin(src)
    if IsPlayerAceAllowed(src, 'command') then return true end
    local player = exports.qbx_core:GetPlayer(src)
    return player ~= nil and adminGroups[player.PlayerData.group] == true
end

local COMMANDS = {
    racemaker       = { event = 'sk_streetkings:racing:admin:toggleRouteMaker', help = 'Open/close the race route maker' },
    racemakeredit   = { event = 'sk_streetkings:racing:admin:editNearest',      help = 'Edit the nearest custom route (within 300m)' },
    racemakerdelete = { event = 'sk_streetkings:racing:admin:deleteNearest',    help = 'Delete the nearest custom route (within 300m)' },
}

for command, spec in pairs(COMMANDS) do
    RegisterCommand(command, function(src)
        if src == 0 then return end
        if not isAdmin(src) then
            TriggerClientEvent('ox_lib:notify', src, { title = 'Race Maker', description = 'Admin only.', type = 'error' })
            return
        end
        TriggerClientEvent(spec.event, src)
    end, false)
end

local function slugify(name)
    local slug = name:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    return slug ~= '' and slug or 'route'
end

lib.callback.register('sk_streetkings:racing:admin:saveRoute', function(source, routeData)
    local src = source
    if not isAdmin(src) then return { ok = false, reason = 'No permission' } end
    if type(routeData) ~= 'table' or not routeData.name or not routeData.start
        or type(routeData.checkpoints) ~= 'table' or #routeData.checkpoints < 1 then
        return { ok = false, reason = 'Invalid route data' }
    end

    local player = exports.qbx_core:GetPlayer(src)
    local citizenid = player and player.PlayerData.citizenid or 'unknown'

    local scheme = routeData.scheme or 'ordered'
    local laps = math.max(Config.LapsMin, math.min(tonumber(routeData.laps) or 1, Config.LapsMax))
    -- Air/offroad fields: checked once, the same way loading a saved row checks them.
    local extras = SKRoutes.extraFields(routeData, #routeData.checkpoints)
    if extras.kind == 'air' then
        -- the plane has to start moving, so a circuit or a return leg (which ends on the start line) makes no sense
        scheme = 'ordered'
        if not extras.vehicle then return { ok = false, reason = 'Pick a plane for an air race' } end
        if not extras.entry then return { ok = false, reason = 'An air race needs a ground entry point' } end
        if not extras.medals then return { ok = false, reason = 'Medal times must run gold < silver < bronze' } end
    end

    local data = json.encode({
        laps              = laps,
        goalTime          = extras.medals and extras.medals.gold or routeData.goalTime,
        unlockRequirement = routeData.unlockRequirement,
        start             = routeData.start,
        checkpoints       = routeData.checkpoints,
        kind              = extras.kind,
        vehicle           = extras.vehicle,
        entry             = routeData.entry,
        medals            = extras.medals,
        gateStunts        = extras.gateStunts,
    })

    local id = type(routeData.editId) == 'string' and routeData.editId or nil

    if id and SKRoutes.isCustom(id) then
        MySQL.query.await('UPDATE `sk_race_routes` SET `name` = ?, `scheme` = ?, `data` = ? WHERE `id` = ?',
            { routeData.name, scheme, data, id })
    else
        local baseId = slugify(routeData.name)
        id = baseId
        local suffix = 1
        while SKRoutes.get(id) do
            suffix = suffix + 1
            id = baseId .. '_' .. suffix
        end

        MySQL.query.await('INSERT INTO `sk_race_routes` (`id`, `name`, `scheme`, `data`, `creator`) VALUES (?, ?, ?, ?, ?)',
            { id, routeData.name, scheme, data, citizenid })
    end

    local checkpoints = {}
    for i, cp in ipairs(routeData.checkpoints) do checkpoints[i] = vec3(cp.x, cp.y, cp.z) end

    local def = {
        id = id, name = routeData.name, scheme = scheme, laps = laps,
        goalTime = extras.medals and extras.medals.gold or routeData.goalTime,
        unlockRequirement = routeData.unlockRequirement,
        start = vec4(routeData.start.x, routeData.start.y, routeData.start.z, routeData.start.w or 0.0),
        startRadius = routeData.start.radius,
        checkpoints = checkpoints, checkpointRadii = SKRoutes.extractRadii(routeData.checkpoints),
        custom = true, creator = citizenid,
    }
    for k, v in pairs(extras) do def[k] = v end
    if def.startRadius == nil or extras.startRadius then def.startRadius = extras.startRadius or routeData.start.radius end
    SKRoutes.addCustom(def)

    TriggerClientEvent('sk_streetkings:racing:admin:routeSaved', -1, id)
    return { ok = true, id = id }
end)

lib.callback.register('sk_streetkings:racing:admin:deleteRoute', function(source, id)
    if not isAdmin(source) then return { ok = false, reason = 'No permission' } end
    if type(id) ~= 'string' or not SKRoutes.isCustom(id) then
        return { ok = false, reason = 'Not a custom route' }
    end

    MySQL.query.await('DELETE FROM `sk_race_routes` WHERE `id` = ?', { id })
    SKRoutes.removeCustom(id)

    TriggerClientEvent('sk_streetkings:racing:admin:routeDeleted', -1, id)
    return { ok = true }
end)
