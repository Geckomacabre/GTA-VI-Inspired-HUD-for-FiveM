-- Top-10 leaderboard browser (route -> vehicle class -> period -> results)
-- and a combined "racing hub" menu, exported for um_carmeet's Race Organizer
-- NPC to link into without duplicating any menu logic.

local PERIODS = {
    { key = 'day',   label = 'Today' },
    { key = 'week',  label = 'This Week' },
    { key = 'month', label = 'This Month' },
    { key = 'all',   label = 'All Time' },
}

local function showResults(routeId, routeName, className, periodKey, periodLabel)
    local rows = lib.callback.await('sk_streetkings:racing:getLeaderboard', false, routeId, className, periodKey) or {}

    local options = {}
    if #rows == 0 then
        options[1] = { title = 'No times recorded yet', disabled = true }
    else
        for i, row in ipairs(rows) do
            options[#options + 1] = {
                title       = ('#%d — %s'):format(i, row.alias),
                description = ('%s  |  %s'):format(SKFormatTime(row.score_ms), row.vehicle_model or ''),
                disabled    = true,
            }
        end
    end

    lib.registerContext({
        id = 'sk_racing_lb_results', menu = 'sk_racing_lb_period',
        title = ('%s — %s (%s)'):format(routeName, className, periodLabel),
        options = options,
    })
    lib.showContext('sk_racing_lb_results')
end

local function showPeriods(routeId, routeName, className)
    local options = {}
    for _, p in ipairs(PERIODS) do
        options[#options + 1] = {
            title    = p.label,
            onSelect = function() CreateThread(function() showResults(routeId, routeName, className, p.key, p.label) end) end,
        }
    end
    lib.registerContext({ id = 'sk_racing_lb_period', menu = 'sk_racing_lb_class', title = 'Time Period', options = options })
    lib.showContext('sk_racing_lb_period')
end

local function showClasses(routeId, routeName)
    local options = {}
    for classId = 0, 12 do -- land vehicle classes only (excludes boats/air/rail/emergency/military)
        local name = Config.VehicleClassNames[classId]
        if name then
            options[#options + 1] = { title = name, onSelect = function() showPeriods(routeId, routeName, name) end }
        end
    end
    lib.registerContext({ id = 'sk_racing_lb_class', menu = 'sk_racing_lb_routes', title = 'Vehicle Class', options = options })
    lib.showContext('sk_racing_lb_class')
end

function OpenLeaderboardHub()
    CreateThread(function()
        local routes = lib.callback.await('sk_streetkings:racing:getRoutes', false) or {}
        local options = {}
        for id, def in pairs(routes) do
            options[#options + 1] = { title = def.name, onSelect = function() showClasses(id, def.name) end }
        end
        lib.registerContext({ id = 'sk_racing_lb_routes', title = 'Race Leaderboards', options = options })
        lib.showContext('sk_racing_lb_routes')
    end)
end

-- Combined entry point for the Race Organizer NPC / other resources.
function OpenRacingHub()
    lib.registerContext({
        id = 'sk_racing_hub',
        title = 'Racing',
        options = {
            { title = 'Leaderboards', onSelect = OpenLeaderboardHub },
            { title = 'Browse Open Lobbies', onSelect = BrowseOpenLobbies },
        },
    })
    lib.showContext('sk_racing_hub')
end

RegisterCommand('raceleaderboard', OpenLeaderboardHub, false)

exports('openRacingHub', OpenRacingHub)
exports('openLeaderboardHub', OpenLeaderboardHub)
