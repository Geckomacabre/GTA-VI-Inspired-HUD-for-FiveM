-- Leaderboard persistence + queries. Mirrors StreetKings' event_leaderboards
-- design (per-route, per-vehicle-class, period-filtered, MIN(score) ranking)
-- but keyed by citizenid instead of license, matching qbx conventions.

SKLeaderboard = {}

local PERIOD_SQL = {
    day   = ' AND created_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)',
    week  = ' AND created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)',
    month = ' AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)',
    all   = '',
}

function SKLeaderboard.insert(citizenid, alias, routeId, vehicleClass, scoreMs, vehicleModel)
    MySQL.insert(
        'INSERT INTO sk_race_leaderboards (citizenid, alias, event_id, vehicle_class, score_ms, vehicle_model) VALUES (?, ?, ?, ?, ?, ?)',
        { citizenid, alias, routeId, vehicleClass, scoreMs, vehicleModel }
    )
end

function SKLeaderboard.fetchTop(routeId, vehicleClass, period, limit)
    limit = limit or Config.LeaderboardLimit
    local periodClause = PERIOD_SQL[period] or ''
    local query = ('SELECT citizenid, MAX(alias) AS alias, MIN(score_ms) AS score_ms, MAX(vehicle_model) AS vehicle_model '
        .. 'FROM sk_race_leaderboards WHERE event_id = ? AND vehicle_class = ?%s '
        .. 'GROUP BY citizenid ORDER BY score_ms ASC LIMIT %d'):format(periodClause, limit)
    return MySQL.query.await(query, { routeId, vehicleClass }) or {}
end

-- Personal best + rank + percentile against the full (unlimited) all-time field.
function SKLeaderboard.fetchPersonalStanding(routeId, vehicleClass, citizenid)
    local rows = MySQL.query.await(
        'SELECT citizenid, MIN(score_ms) AS score_ms FROM sk_race_leaderboards '
        .. 'WHERE event_id = ? AND vehicle_class = ? GROUP BY citizenid ORDER BY score_ms ASC',
        { routeId, vehicleClass }
    ) or {}

    local personalBest, rank
    for i, row in ipairs(rows) do
        if row.citizenid == citizenid then
            personalBest, rank = row.score_ms, i
            break
        end
    end

    local percentile = (rank and #rows > 0) and (rank / #rows) or 1.0
    return personalBest, rank, percentile, #rows
end

lib.callback.register('sk_streetkings:racing:getLeaderboard', function(_source, routeId, vehicleClass, period)
    return SKLeaderboard.fetchTop(routeId, vehicleClass, period)
end)
