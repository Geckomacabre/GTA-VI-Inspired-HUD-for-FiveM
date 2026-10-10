-- Stunt jump storage, scoring and payout.
--
-- Upstream (modules/stunts/stunt_jump_s.lua) only persisted the definitions and
-- handed scoring to its daily-events system. That system is not ported, so the
-- payout and the per-jump best score live here instead, against
-- `sk_activity_scores` (activity = 'stunt').

if not Config.Modules.stunts then return end

SKStunts = {}

-- The client computes the score from its own physics readings, so the number
-- cannot be recomputed server-side. It is clamped instead: a legitimate run is
-- comfortably under a thousand points.
local MAX_SCORE          = 5000
local SUBMIT_COOLDOWN_MS = 3000

local cachedJumps = {}
local lastSubmit  = {}

-- ── Definitions ─────────────────────────────────────────────────────────────

local function loadJumps()
    local rows = MySQL.query.await('SELECT `id`, `name`, `data` FROM `sk_stunt_jumps`') or {}
    for _, row in ipairs(rows) do
        local ok, data = pcall(json.decode, row.data)
        if ok and type(data) == 'table' then
            data.id   = row.id
            data.name = row.name
            cachedJumps[row.id] = data
        end
    end
    print(('^2[sk_streetkings]^0 Loaded %d stunt jump(s) from database.'):format(#rows))
end

MySQL.ready(loadJumps)

lib.callback.register('sk_streetkings:stunts:load', function()
    return cachedJumps
end)

---@param jumpId string
---@return table|nil
function SKStunts.get(jumpId)
    return cachedJumps[jumpId] or (SKStuntJumps and SKStuntJumps[jumpId])
end

-- ── Devtool writes ──────────────────────────────────────────────────────────

lib.callback.register('sk_streetkings:stunts:save', function(source, def)
    if not SKPlayer.isAdmin(source) then
        return { ok = false, reason = 'No permission' }
    end
    if type(def) ~= 'table' or type(def.id) ~= 'string' or type(def.name) ~= 'string' then
        return { ok = false, reason = 'Invalid definition' }
    end

    -- id and name are their own columns; everything else is the JSON blob.
    local data = {}
    for k, v in pairs(def) do
        if k ~= 'id' and k ~= 'name' then data[k] = v end
    end

    MySQL.query.await([[
        INSERT INTO `sk_stunt_jumps` (`id`, `name`, `data`, `creator`)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `data` = VALUES(`data`)
    ]], { def.id, def.name, json.encode(data), SKPlayer.citizenid(source) or 'unknown' })

    cachedJumps[def.id] = def
    TriggerClientEvent('sk_streetkings:stunts:sync', -1, def.id, def)
    return { ok = true }
end)

lib.callback.register('sk_streetkings:stunts:delete', function(source, jumpId)
    if not SKPlayer.isAdmin(source) then
        return { ok = false, reason = 'No permission' }
    end
    if type(jumpId) ~= 'string' then
        return { ok = false, reason = 'Invalid jump ID' }
    end

    MySQL.query.await('DELETE FROM `sk_stunt_jumps` WHERE `id` = ?', { jumpId })
    cachedJumps[jumpId] = nil

    TriggerClientEvent('sk_streetkings:stunts:removed', -1, jumpId)
    return { ok = true }
end)

-- ── Scoring ─────────────────────────────────────────────────────────────────

lib.callback.register('sk_streetkings:stunts:submit', function(source, jumpId, score, vehicleLabel)
    local def = SKStunts.get(jumpId)
    if not def then return nil end

    local citizenid = SKPlayer.citizenid(source)
    if not citizenid or not SKSaves.hasActiveSave(source) then return nil end

    local now = GetGameTimer()
    if lastSubmit[source] and now - lastSubmit[source] < SUBMIT_COOLDOWN_MS then return nil end
    lastSubmit[source] = now

    score = math.floor(math.max(0, math.min(tonumber(score) or 0, MAX_SCORE)))

    local previous = MySQL.scalar.await(
        'SELECT `score` FROM `sk_activity_scores` WHERE `citizenid` = ? AND `activity` = ? AND `activity_id` = ?',
        { citizenid, 'stunt', jumpId }
    )
    local firstCompletion = previous == nil
    local isPersonalBest  = firstCompletion or score > previous

    MySQL.query.await([[
        INSERT INTO `sk_activity_scores` (`citizenid`, `alias`, `activity`, `activity_id`, `score`)
        VALUES (?, ?, 'stunt', ?, ?)
        ON DUPLICATE KEY UPDATE `alias` = VALUES(`alias`), `score` = GREATEST(`score`, VALUES(`score`))
    ]], { citizenid, SKPlayer.alias(source), jumpId, score })

    -- Clearing a jump for the first time is what pays; repeats pay a smaller
    -- flat amount so grinding one gap is not the best money in the game.
    local cash = firstCompletion and Config.Stunts.rewardPerJump or Config.Stunts.repeatRewardCash
    local xp   = firstCompletion and Config.Stunts.firstCompletionXp or 0

    if cash > 0 then
        SKPlayer.addMoney(source, cash, 'sk-stunt-jump')
    end

    local level, leveledUp = SKProfiles.awardXp(source, xp)

    if Config.Modules.stats then
        SKStats.increment(source, 'stuntJumpsCompleted', 1)
        SKStats.increment(source, 'totalCashEarned', cash)
    end

    local rank = tonumber(MySQL.scalar.await(
        'SELECT COUNT(*) + 1 FROM `sk_activity_scores` WHERE `activity` = ? AND `activity_id` = ? AND `score` > ?',
        { 'stunt', jumpId, score }
    )) or 1

    local parts = {}
    if firstCompletion then
        parts[#parts + 1] = 'First clear'
    elseif isPersonalBest then
        parts[#parts + 1] = 'New personal best'
    end
    parts[#parts + 1] = ('%s — %s'):format(SKFormatMoney(cash), ('#%d overall'):format(rank))
    if xp > 0 then
        parts[#parts + 1] = ('+%d XP'):format(xp)
    end

    return {
        summary        = table.concat(parts, '  •  '),
        score          = score,
        rank           = rank,
        personalBest   = isPersonalBest,
        firstCompletion = firstCompletion,
        cash           = cash,
        xp             = xp,
        level          = level,
        leveledUp      = leveledUp,
        vehicle        = type(vehicleLabel) == 'string' and vehicleLabel or '',
    }
end)

--- Top scores for one jump, newest-first tiebreak. Used by the stats menu.
---@param jumpId string
---@param limit? integer
---@return table[]
function SKStunts.leaderboard(jumpId, limit)
    return MySQL.query.await([[
        SELECT `alias`, `score`, `created_at`
        FROM `sk_activity_scores`
        WHERE `activity` = 'stunt' AND `activity_id` = ?
        ORDER BY `score` DESC, `created_at` ASC
        LIMIT ?
    ]], { jumpId, limit or Config.LeaderboardLimit }) or {}
end

lib.callback.register('sk_streetkings:stunts:leaderboard', function(_, jumpId)
    if type(jumpId) ~= 'string' then return {} end
    return SKStunts.leaderboard(jumpId)
end)

AddEventHandler('playerDropped', function()
    lastSubmit[source] = nil
end)
