-- Singleplayer time-trial flow: start, checkpoint hits, finish, reward payout.
-- Reward math (distance-scaled base + goal bonus + percentile ranked bands)
-- ported from StreetKings' events_rewards_s.lua design — pure math, adapted
-- to pay out via qbx_core instead of StreetKings' own economy/progression.

-- ── Cosmetic race XP/level profile ──────────────────────────────────────────
-- Was its own sk_race_profiles table; XP and level now live in the shared
-- profile document (modules/core/saves_s.lua) alongside stats and unlocks, so
-- there is one row per citizen instead of one per subsystem. Keyed by source
-- rather than citizenid because SKSaves caches per-session.
SKProfiles = {}

--- Returns (newLevel, leveledUp)
---@param src integer
---@param xp integer
---@return integer, boolean
function SKProfiles.awardXp(src, xp)
    local currentXp = SKSaves.read(src, 'progression.playerXp') or 0
    if xp <= 0 then return Config.XpToLevel(currentXp), false end

    local oldLevel = Config.XpToLevel(currentXp)
    local newXp    = currentXp + xp
    local newLevel = Config.XpToLevel(newXp)

    SKSaves.write(src, 'progression.playerXp', newXp)
    SKSaves.write(src, 'progression.level', newLevel)
    return newLevel, newLevel > oldLevel
end

-- ── Reward calculation ──────────────────────────────────────────────────────
-- Exposed via SKRewardMath so server/multiplayer.lua can reuse the same
-- distance-based scale for its position-multiplier payouts.
SKRewardMath = {}

function SKRewardMath.getRewardScale(def)
    local rs = Config.RewardScaling
    local distance = SKRouteBuilder.routeDistanceMeters(def)
    local weighted = distance + #def.checkpoints * rs.checkpointWeightMeters
    local scale = weighted / rs.referenceDistance
    return math.max(rs.minimumScale, math.min(1.0, scale))
end

-- Meet Night is now a module in this resource rather than a separate optional
-- one, so this reads it directly. SKMeetNight.getMultiplier() returns 1.0 when
-- the module is disabled, so callers still need no guard.
function SKRewardMath.getMeetNightMultiplier()
    return SKMeetNight.getMultiplier()
end

local function calculateReward(def, goalMet, percentile, earlyBoardEligible)
    local rs    = Config.RewardScaling
    local scale = SKRewardMath.getRewardScale(def) * SKRewardMath.getMeetNightMultiplier()
    local cash  = rs.base.cash * scale
    local xp    = rs.base.xp * scale

    if goalMet then
        cash = cash + rs.goalBonus.cash * scale
        xp   = xp + rs.goalBonus.xp * scale
    end

    if earlyBoardEligible then
        cash = cash + rs.earlyBoardBonus.cash * scale
        xp   = xp + rs.earlyBoardBonus.xp * scale
    end

    for _, band in ipairs(rs.rankedBands) do
        if percentile <= band.maxPercentile then
            cash = cash + band.cash * scale
            xp   = xp + band.xp * scale
            break
        end
    end

    return math.floor(cash), math.floor(xp)
end

-- ── Run flow ─────────────────────────────────────────────────────────────

local function finishRun(src, run)
    local rawMs = GetGameTimer() - run.startedAt
    local def = SKRoutes.get(run.routeId)
    SKValidation.clearRun(src)

    -- Stunt-plane courses are scored on the adjusted clock: gate bonuses come off, penalties go on
    -- (shared/gates_sh.lua). For every other route the bonus is 0 and adjusted == raw.
    local netBonus = run.netBonusSeconds or 0.0
    local elapsedMs = SKGates.adjustedMs(rawMs, netBonus)

    local player = exports.qbx_core:GetPlayer(src)
    if not player or not def then return end

    local citizenid       = player.PlayerData.citizenid
    local alias            = ('%s %s'):format(player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname)
    local vehicleClassName = run.vehicleClassName or 'Unknown'
    local vehicleModelName = run.vehicleModelName or ''

    -- Was this the citizen's first submission on this route/class? (checked before insert)
    local priorBest = SKLeaderboard.fetchPersonalStanding(run.routeId, vehicleClassName, citizenid)
    local isFirstEntry = priorBest == nil

    SKLeaderboard.insert(citizenid, alias, run.routeId, vehicleClassName, elapsedMs, vehicleModelName)

    local _, rank, percentile = SKLeaderboard.fetchPersonalStanding(run.routeId, vehicleClassName, citizenid)
    local goalMet = def.goalTime ~= nil and elapsedMs <= (def.goalTime * 1000)
    local earlyBoardEligible = isFirstEntry and rank ~= nil and rank <= Config.RewardScaling.earlyBoardRankThreshold

    local cash, xp = calculateReward(def, goalMet, percentile or 1.0, earlyBoardEligible)

    -- Gold / silver / bronze, judged on the adjusted time, paid on top.
    local medal = SKGates.medal(def.medals, elapsedMs / 1000.0)
    local medalReward = medal and Config.MedalRewards[medal]
    if medalReward then
        local medalScale = SKRewardMath.getRewardScale(def) * SKRewardMath.getMeetNightMultiplier()
        cash = cash + math.floor(medalReward.cash * medalScale)
        xp   = xp + math.floor(medalReward.xp * medalScale)
    end

    SKPlayer.addMoney(src, cash, 'sk-race-reward')
    local newLevel, leveledUp = SKProfiles.awardXp(src, xp)

    if Config.Modules.stats then
        SKStats.increment(src, 'racesCompleted', 1)
        SKStats.increment(src, 'totalCashEarned', cash)
        if goalMet then
            SKStats.increment(src, 'goalTimesBeaten', 1)
        end
    end

    TriggerClientEvent('sk_streetkings:racing:sp:finished', src, {
        routeId    = run.routeId,
        elapsedMs  = elapsedMs,
        rawMs      = rawMs,
        bonusSeconds = netBonus,
        medal      = medal,
        medals     = def.medals,
        gateResults = run.gateResults,
        cash       = cash,
        xp         = xp,
        rank       = rank,
        percentile = percentile,
        goalMet    = goalMet,
        level      = newLevel,
        leveledUp  = leveledUp,
    })
end

RegisterNetEvent('sk_streetkings:racing:sp:start', function(routeId, vehInfo)
    local src = source
    local ok, result = SKValidation.beginRun(src, routeId, vehInfo)
    if not ok then
        -- Client has already begun its local countdown/run optimistically; tell
        -- it to roll back if the server rejected the start.
        TriggerClientEvent('sk_streetkings:racing:sp:startDenied', src, result)
    end
end)

RegisterNetEvent('sk_streetkings:racing:sp:hitCheckpoint', function(checkpointIndex, status)
    local src = source
    if type(status) ~= 'string' then status = nil end
    local ok, result, scored = SKValidation.validateCheckpointHit(src, checkpointIndex, status)
    if not ok then
        if result == 'no_active_run' or result == 'vehicle_changed' or result == 'out_of_order' or result == 'bad_status' or result == 'bad_miss' then
            TriggerClientEvent('sk_streetkings:racing:sp:runAborted', src, result)
        end
        return
    end
    if scored then
        -- What the server actually scored, so the on-screen bonus is the real one.
        TriggerClientEvent('sk_streetkings:racing:sp:gateScored', src, checkpointIndex, scored, result.netBonusSeconds)
    end
    if SKValidation.isFinished(result) then
        finishRun(src, result)
    end
end)

RegisterNetEvent('sk_streetkings:racing:sp:abort', function()
    SKValidation.clearRun(source)
end)
