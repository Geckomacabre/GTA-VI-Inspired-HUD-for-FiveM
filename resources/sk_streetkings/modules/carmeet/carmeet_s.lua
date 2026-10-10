-- Car meet server: drift payouts and the NPC spectator race / betting pool.
--
-- Ported from um_carmeet's sv_carmeet.lua with three fixes:
--   * qb-core exports replaced with the qbx_core bridge in SKPlayer. The old
--     file called exports['qb-core']:GetCoreObject(), which only worked because
--     qbx:enableBridge is on; going through SKPlayer removes that dependency.
--   * bet limits and the betting window now read Config instead of being
--     hardcoded to 100 / 50000 / 30s, so the config values actually apply.
--   * race duration is a named constant rather than a magic 90000 repeated in
--     three places.

if not Config.Modules.carmeet then return end

local Meet = lib.require('data.carmeet')

local RACE_DURATION_MS   = 90000
local RESOLVE_DELAY_MS   = 5000  -- grace after the drive time before paying out
local NEXT_RACE_DELAY_MS = 8000

local pendingRace = nil
local activeRace  = nil

-- ── Drift reward ────────────────────────────────────────────────────────────

RegisterNetEvent('sk_streetkings:carmeet:driftReward', function(points, cashAmount)
    local src = source
    if not Config.Modules.drift then return end

    -- Client-reported, so clamp hard. The highest configured tier is the cap.
    local maxReward = 0
    for _, tier in ipairs(Config.Drift.rewards) do
        if tier.cash > maxReward then maxReward = tier.cash end
    end

    cashAmount = math.floor(math.max(0, math.min(tonumber(cashAmount) or 0, maxReward)))
    if cashAmount == 0 then return end

    if not SKPlayer.addMoney(src, cashAmount, 'carmeet-drift') then return end

    points = math.floor(tonumber(points) or 0)
    SKPlayer.notify(src, 'Drift Reward', ('%d pts — %s earned.'):format(points, SKFormatMoney(cashAmount)), 'success')

    if Config.Modules.stats then
        SKStats.increment(src, 'driftPointsTotal', points)
        SKStats.setMax(src, 'bestDriftScore', points)
    end
end)

-- ── NPC spectator race ──────────────────────────────────────────────────────

--- Picks a winner weighted by inverse odds, so a 2.0x favourite wins about
--- twice as often as a 4.0x underdog.
local function pickWinner(racers)
    local total = 0
    for _, r in ipairs(racers) do total = total + (1 / r.odds) end

    local rand, cum = math.random() * total, 0
    for i, r in ipairs(racers) do
        cum = cum + (1 / r.odds)
        if rand <= cum then return i end
    end
    return #racers
end

local launchNpcRace

local function resolveNpcRace()
    if not activeRace then return end

    local race = activeRace
    activeRace = nil

    local winnerName = race.racers[race.winnerIdx] and race.racers[race.winnerIdx].name or '?'

    for src, bet in pairs(race.bets) do
        if SKPlayer.get(src) then
            if bet.racerIdx == race.winnerIdx then
                local racer  = race.racers[bet.racerIdx]
                local payout = math.floor(bet.amount * racer.odds)
                SKPlayer.addMoney(src, payout, 'carmeet-npc-race-win')
                SKPlayer.notify(src, 'You Won!',
                    ('%s won! +%s (%.1fx)'):format(winnerName, SKFormatMoney(payout), racer.odds), 'success')
                if Config.Modules.stats then
                    SKStats.increment(src, 'totalCashEarned', payout)
                    SKStats.increment(src, 'betsWon', 1)
                end
            else
                SKPlayer.notify(src, 'Race Over', ('%s won. Better luck next time.'):format(winnerName), 'error')
            end
        end
    end

    TriggerClientEvent('sk_streetkings:carmeet:npcRaceFinished', -1, {
        winnerIdx = race.winnerIdx,
        winnerName = winnerName,
    })

    if pendingRace then
        Wait(NEXT_RACE_DELAY_MS)
        if pendingRace then
            local pr = pendingRace
            pendingRace = nil
            launchNpcRace(pr)
        end
    end
end

function launchNpcRace(pr)
    if activeRace then return end

    local winnerIdx = pickWinner(pr.racers)
    activeRace = {
        route      = pr.route,
        racers     = pr.racers,
        winnerIdx  = winnerIdx,
        bets       = pr.bets,
        spectators = pr.spectators,
        endTime    = RACE_DURATION_MS,
    }

    for src in pairs(pr.spectators) do
        TriggerClientEvent('sk_streetkings:carmeet:npcRaceStart', src, {
            route      = pr.route,
            racers     = pr.racers,
            winnerIdx  = winnerIdx,
            durationMs = RACE_DURATION_MS,
        })
    end

    TriggerClientEvent('sk_streetkings:carmeet:bettingOpen', -1, { racers = pr.racers, started = true })

    CreateThread(function()
        Wait(RACE_DURATION_MS + RESOLVE_DELAY_MS)
        resolveNpcRace()
    end)
end

local function startBettingCountdown(sec)
    CreateThread(function()
        Wait(sec * 1000)
        if pendingRace and not activeRace then
            local pr = pendingRace
            pendingRace = nil
            launchNpcRace(pr)
        end
    end)
end

RegisterNetEvent('sk_streetkings:carmeet:placeBet', function(racerIdx, amount, clientRoute)
    local src = source
    if not (Config.Modules.npcBetting and Meet.NpcRace.enabled) then return end
    if not SKPlayer.get(src) then return end

    racerIdx = math.floor(tonumber(racerIdx) or 0)
    if racerIdx < 1 or racerIdx > #Meet.NpcRace.racers then return end

    amount = math.floor(tonumber(amount) or 0)
    if amount < Config.Betting.min then
        SKPlayer.notify(src, 'Betting', ('Minimum bet is %s.'):format(SKFormatMoney(Config.Betting.min)), 'error')
        return
    end
    if amount > Config.Betting.max then
        SKPlayer.notify(src, 'Betting', ('Maximum bet is %s.'):format(SKFormatMoney(Config.Betting.max)), 'error')
        return
    end

    if not SKPlayer.removeMoney(src, amount, 'carmeet-npc-race-bet') then
        SKPlayer.notify(src, 'Betting', 'Not enough cash.', 'error')
        return
    end

    -- A race is already running: queue the bet for the next one and let the
    -- player watch the current race in the meantime.
    if activeRace then
        if not pendingRace then
            pendingRace = {
                route      = clientRoute or activeRace.route,
                racers     = activeRace.racers,
                bets       = {},
                spectators = {},
            }
        end
        pendingRace.bets[src] = { racerIdx = racerIdx, amount = amount }
        pendingRace.spectators[src] = true

        TriggerClientEvent('sk_streetkings:carmeet:spectateCurrentRace', src, {
            route      = activeRace.route,
            racers     = activeRace.racers,
            durationMs = activeRace.endTime,
            betQueued  = true,
        })

        local racer = activeRace.racers[racerIdx]
        SKPlayer.notify(src, 'Bet Queued',
            ('%s on %s (%.1fx) — queued for next race.'):format(
                SKFormatMoney(amount), racer and racer.name or '?', racer and racer.odds or 1), 'inform')
        return
    end

    if not pendingRace then
        pendingRace = {
            route      = clientRoute,
            racers     = (clientRoute and clientRoute.racers) or {},
            bets       = {},
            spectators = {},
        }
        startBettingCountdown(Meet.NpcRace.bettingWindowSec)
        TriggerClientEvent('sk_streetkings:carmeet:bettingOpen', -1, {
            racers    = pendingRace.racers,
            windowSec = Meet.NpcRace.bettingWindowSec,
        })
    end

    -- Changing your mind refunds the previous stake rather than stacking it.
    if pendingRace.bets[src] then
        SKPlayer.addMoney(src, pendingRace.bets[src].amount, 'carmeet-bet-replace')
    end

    pendingRace.bets[src] = { racerIdx = racerIdx, amount = amount }
    pendingRace.spectators[src] = true

    TriggerClientEvent('sk_streetkings:carmeet:spectateCurrentRace', src, {
        route  = pendingRace.route,
        racers = pendingRace.racers,
    })

    local racer = pendingRace.racers[racerIdx]
    SKPlayer.notify(src, 'Bet Placed',
        ('%s on %s (%.1fx). Race starts soon.'):format(
            SKFormatMoney(amount), racer and racer.name or '?', racer and racer.odds or 1), 'success')
end)

-- A player who disconnects mid-window forfeits their stake rather than leaving
-- a dangling source key in the bet table.
AddEventHandler('playerDropped', function()
    local src = source
    if pendingRace then
        pendingRace.bets[src] = nil
        pendingRace.spectators[src] = nil
    end
    if activeRace then
        activeRace.bets[src] = nil
        activeRace.spectators[src] = nil
    end
end)
