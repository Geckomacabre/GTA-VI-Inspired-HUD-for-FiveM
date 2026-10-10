-- Rampage payout and per-location best scores.
--
-- Upstream routed this through its daily-events reward pipeline
-- (modules/events/events_rewards_s.lua). That is not ported, so the payout is
-- the straight `Config.Rampage` conversion and the best score per location goes
-- to `sk_activity_scores` (activity = 'rampage').

if not Config.Modules.rampage then return end

SKRampageServer = {}

-- The client scores the run locally, so the total cannot be recomputed here.
-- A full 150s run tops out somewhere around 60k; this is headroom above that,
-- not a target.
local MAX_SCORE          = 150000
local SUBMIT_COOLDOWN_MS = 5000

local lastSubmit = {}

lib.callback.register('sk_streetkings:rampage:submit', function(source, rampageId, score, vehicleLabel)
    local def = SKRampages and SKRampages[rampageId]
    if not def then return nil end

    local citizenid = SKPlayer.citizenid(source)
    if not citizenid or not SKSaves.hasActiveSave(source) then return nil end

    local now = GetGameTimer()
    if lastSubmit[source] and now - lastSubmit[source] < SUBMIT_COOLDOWN_MS then return nil end
    lastSubmit[source] = now

    score = math.floor(math.max(0, math.min(tonumber(score) or 0, MAX_SCORE)))
    if score <= 0 then return nil end

    local previous = MySQL.scalar.await(
        'SELECT `score` FROM `sk_activity_scores` WHERE `citizenid` = ? AND `activity` = ? AND `activity_id` = ?',
        { citizenid, 'rampage', rampageId }
    )
    local isPersonalBest = previous == nil or score > previous

    MySQL.query.await([[
        INSERT INTO `sk_activity_scores` (`citizenid`, `alias`, `activity`, `activity_id`, `score`)
        VALUES (?, ?, 'rampage', ?, ?)
        ON DUPLICATE KEY UPDATE `alias` = VALUES(`alias`), `score` = GREATEST(`score`, VALUES(`score`))
    ]], { citizenid, SKPlayer.alias(source), rampageId, score })

    local cash = math.floor(score * Config.Rampage.cashPerPoint)
    local xp   = math.floor(score / 1000 * Config.Rampage.xpPerThousand)

    if cash > 0 then
        SKPlayer.addMoney(source, cash, 'sk-rampage')
    end

    local level, leveledUp = SKProfiles.awardXp(source, xp)

    if Config.Modules.stats then
        SKStats.increment(source, 'rampagesCompleted', 1)
        SKStats.increment(source, 'totalCashEarned', cash)
        SKStats.setMax(source, 'bestRampageScore', score)
    end

    local rank = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) + 1 FROM `sk_activity_scores` WHERE `activity` = ? AND `activity_id` = ? AND `score` > ?',
        { 'rampage', rampageId, score }
    )) or 1

    local parts = {}
    if isPersonalBest then parts[#parts + 1] = 'New personal best' end
    parts[#parts + 1] = ('%s — #%d overall'):format(SKFormatMoney(cash), rank)
    if xp > 0 then parts[#parts + 1] = ('+%d XP'):format(xp) end

    return {
        summary      = table.concat(parts, '  •  '),
        score        = score,
        rank         = rank,
        personalBest = isPersonalBest,
        cash         = cash,
        xp           = xp,
        level        = level,
        leveledUp    = leveledUp,
        vehicle      = type(vehicleLabel) == 'string' and vehicleLabel or '',
    }
end)

--- Top scores for one rampage location.
---@param rampageId string
---@param limit? integer
---@return table[]
function SKRampageServer.leaderboard(rampageId, limit)
    return MySQL.query.await([[
        SELECT `alias`, `score`, `created_at`
        FROM `sk_activity_scores`
        WHERE `activity` = 'rampage' AND `activity_id` = ?
        ORDER BY `score` DESC, `created_at` ASC
        LIMIT ?
    ]], { rampageId, limit or Config.LeaderboardLimit }) or {}
end

lib.callback.register('sk_streetkings:rampage:leaderboard', function(_, rampageId)
    if type(rampageId) ~= 'string' then return {} end
    return SKRampageServer.leaderboard(rampageId)
end)

AddEventHandler('playerDropped', function()
    lastSubmit[source] = nil
end)
