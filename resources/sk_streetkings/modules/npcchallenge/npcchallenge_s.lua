-- NPC street challenge validation and payout.
--
-- The race itself is entirely client-side (it is one player against local AI
-- peds), so the only thing worth guarding is the payout. Upstream's checks
-- are kept as-is — destination plausibility on start, then vehicle identity,
-- finish position and elapsed time on claim — with the economy swapped from
-- StreetKings' save document to qbx_core, and the per-class stake roll
-- replaced by Config.NpcChallenge (or Config.StreetPack.rewardsByPlace once
-- the client-rolled pack has extra rivals beyond the primary one).

if not Config.Modules.npcChallenge then return end

local COOLDOWN_MS = 30000

-- Start-position checks. The margin is slack for the client picking a road node
-- near, but not exactly at, the distance it aimed for.
local DEST_MIN    = 800.0
local DEST_MAX    = 1400.0
local DEST_MARGIN = 150.0

local FINISH_RADIUS    = 75.0
local ELAPSED_GRACE_MS = 3000
local CHALLENGE_TIMEOUT_MS = 3 * 60 * 1000

local activeChallenges = {}
local lastChallenge    = {}

---@param src integer
---@return string
local function challengerLabel(src)
    return ('%s (%d)'):format(GetPlayerName(src) or 'unknown', src)
end

---@param message string
local function rejectLog(message)
    print(('^1[sk_streetkings:npc]^0 %s'):format(message))
end

---@param value any
---@return boolean
local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

---@param src integer
---@return integer ped, integer vehicle, vector3 coords
local function getPlayerChallengeState(src)
    local ped     = GetPlayerPed(src)
    local vehicle = ped ~= 0 and GetVehiclePedIsIn(ped, false) or 0
    local coords  = ped ~= 0 and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
    return ped, vehicle, coords
end

-- Extra rivals beyond the primary one, clamped against Config.StreetPack so a
-- tampered client can't inflate the field. Reward tables are indexed by
-- placement, not field size, so this only guards against nonsense values
-- reaching table lookups below — it isn't itself an anti-cheat boundary.
local MAX_TOTAL_RACERS = 2 + (Config.StreetPack and Config.StreetPack.packMax or 0)

RegisterNetEvent('sk_streetkings:npcchallenge:begin', function(x, y, z, totalRacers)
    local src = source
    if not SKSaves.hasActiveSave(src) then return end

    if not isFiniteNumber(x) or not isFiniteNumber(y) or not isFiniteNumber(z) then
        rejectLog(('%s sent a non-finite challenge destination'):format(challengerLabel(src)))
        return
    end

    local ped, vehicle, coords = getPlayerChallengeState(src)
    if ped == 0 or vehicle == 0 then
        rejectLog(('%s started a challenge while not in a vehicle'):format(challengerLabel(src)))
        return
    end

    local destination = vector3(x, y, z)
    local distance    = #(coords - destination)
    if distance < (DEST_MIN - DEST_MARGIN) or distance > (DEST_MAX + DEST_MARGIN) then
        rejectLog(('%s sent an out-of-range destination | distance=%.1f | allowed=%.0f-%.0f'):format(
            challengerLabel(src), distance, DEST_MIN - DEST_MARGIN, DEST_MAX + DEST_MARGIN))
        return
    end

    totalRacers = math.floor(tonumber(totalRacers) or 2)
    totalRacers = math.max(2, math.min(totalRacers, MAX_TOTAL_RACERS))

    activeChallenges[src] = {
        startedAt    = GetGameTimer(),
        destination  = destination,
        vehicleModel = GetEntityModel(vehicle),
        totalRacers  = totalRacers,
    }
end)

RegisterNetEvent('sk_streetkings:npcchallenge:cancel', function()
    activeChallenges[source] = nil
end)

--- Confirms the player really finished where and when they say they did.
---@param src integer
---@param elapsedMs integer
---@return boolean
local function validateWin(src, elapsedMs)
    local challenge = activeChallenges[src]
    if not challenge then
        rejectLog(('%s claimed a win with no active challenge'):format(challengerLabel(src)))
        return false
    end

    local now = GetGameTimer()
    if (now - challenge.startedAt) > CHALLENGE_TIMEOUT_MS then
        rejectLog(('%s claimed a win on an expired challenge'):format(challengerLabel(src)))
        return false
    end

    local ped, vehicle, coords = getPlayerChallengeState(src)
    if ped == 0 or vehicle == 0 then return false end

    if challenge.vehicleModel ~= GetEntityModel(vehicle) then
        rejectLog(('%s swapped vehicles mid-challenge'):format(challengerLabel(src)))
        return false
    end

    local finishDistance = #(coords - challenge.destination)
    if finishDistance > FINISH_RADIUS then
        rejectLog(('%s claimed a win %.1fm from the destination (max %.0f)'):format(
            challengerLabel(src), finishDistance, FINISH_RADIUS))
        return false
    end

    -- The client cannot claim to have taken meaningfully less time than the
    -- server has been counting.
    local serverElapsedMs = now - challenge.startedAt
    if elapsedMs + ELAPSED_GRACE_MS < serverElapsedMs then
        rejectLog(('%s claimed %dms against a server clock of %dms'):format(
            challengerLabel(src), elapsedMs, serverElapsedMs))
        return false
    end

    return true
end

---@param placement integer 1-based finish position
---@param totalRacers integer field size including the player
---@return integer cash, integer xp
local function rewardForPlacement(placement, totalRacers)
    local packSize = totalRacers - 2 -- extra rivals beyond the primary one
    if packSize > 0 and Config.Modules.streetPack and Config.StreetPack then
        local sp = Config.StreetPack
        local cash = sp.rewardsByPlace[placement] or sp.rewardsByPlace[#sp.rewardsByPlace] or 0
        local xp   = sp.xpByPlace[placement] or sp.xpByPlace[#sp.xpByPlace] or 0
        return cash, xp
    end
    -- Plain 1v1: unchanged from before pack racing existed.
    if placement == 1 then
        return Config.NpcChallenge.rewardWin or 0, Config.NpcChallenge.xpWin or 0
    end
    return Config.NpcChallenge.rewardLose or 0, 0
end

lib.callback.register('sk_streetkings:npcchallenge:finish', function(source, placement, totalRacers, elapsedMs, _vehClass, vehicleLabel)
    if not SKSaves.hasActiveSave(source) then return nil end

    local now = GetGameTimer()
    if lastChallenge[source] and (now - lastChallenge[source]) < COOLDOWN_MS then return nil end

    local challenge = activeChallenges[source]
    local hadChallenge = challenge ~= nil
    elapsedMs   = math.floor(tonumber(elapsedMs) or 0)
    placement   = math.floor(tonumber(placement) or 0)
    totalRacers = math.floor(tonumber(totalRacers) or (challenge and challenge.totalRacers) or 2)
    totalRacers = math.max(2, math.min(totalRacers, MAX_TOTAL_RACERS))
    placement   = math.max(1, math.min(placement, totalRacers))

    local won = placement == 1

    if won then
        if elapsedMs <= 0 or not validateWin(source, elapsedMs) then
            activeChallenges[source] = nil
            return nil
        end
    elseif not hadChallenge then
        return nil
    end

    lastChallenge[source]    = now
    activeChallenges[source] = nil

    local cash, xp = rewardForPlacement(placement, totalRacers)

    if not won then
        local deducted = 0
        if cash < 0 then
            deducted = math.min(-cash, SKPlayer.getMoney(source))
            if deducted > 0 then SKPlayer.removeMoney(source, deducted, 'sk-npc-challenge') end
        elseif cash > 0 then
            SKPlayer.addMoney(source, cash, 'sk-npc-challenge')
        end

        if Config.Modules.stats then
            if deducted > 0 then SKStats.increment(source, 'totalCashSpent', deducted) end
            SKStats.increment(source, 'npcChallengesLost', 1)
        end

        local placeLabel = totalRacers > 2 and (' (#%d/%d)'):format(placement, totalRacers) or ''
        if cash > 0 then
            return { won = false, summary = ('Still earned %s%s.'):format(SKFormatMoney(cash), placeLabel) }
        elseif deducted > 0 then
            return { won = false, summary = ('Lost %s on that one%s.'):format(SKFormatMoney(deducted), placeLabel) }
        end
        return { won = false, summary = 'Better luck next time' .. placeLabel .. '.' }
    end

    if cash > 0 then
        SKPlayer.addMoney(source, cash, 'sk-npc-challenge')
    end

    local level, leveledUp = SKProfiles.awardXp(source, xp)

    if Config.Modules.stats then
        SKStats.increment(source, 'npcChallengesWon', 1)
        SKStats.increment(source, 'totalCashEarned', cash)
    end

    local parts = { SKFormatMoney(cash) }
    if xp > 0 then parts[#parts + 1] = ('+%d XP'):format(xp) end

    return {
        won       = true,
        summary   = table.concat(parts, '  •  '),
        cash      = cash,
        xp        = xp,
        level     = level,
        leveledUp = leveledUp,
        vehicle   = type(vehicleLabel) == 'string' and vehicleLabel or '',
    }
end)

AddEventHandler('playerDropped', function()
    activeChallenges[source] = nil
    lastChallenge[source]    = nil
end)
