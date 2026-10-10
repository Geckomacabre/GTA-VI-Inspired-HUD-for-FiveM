-- Multiplayer lobby lifecycle: create/join/leave, countdown, race progress,
-- standings broadcast, position-based payout. Design ported from StreetKings'
-- events_lobby_s.lua / events_multiplayer_s.lua (host/join lobby, routing-
-- bucket isolation, 1s standings broadcast, position + player-count reward
-- scaling), rewired onto qbx_core instead of StreetKings' own save/economy.

local lobbies      = {} -- lobbyId -> lobby
local lobbySrcMap  = {} -- source -> lobbyId
local nextBucket   = Config.RoutingBucketBase

-- Forward declarations (assigned below, referenced by earlier handlers).
local closeLobby, broadcastLobbyUpdate, startCountdown, beginRace
local broadcastStandings, finishLobbyRace, notifyLobby, removeMember
local timeoutLobby, createLobbyRecord

local function allocateBucket()
    nextBucket = nextBucket + 1
    return nextBucket
end

-- SetPlayerRoutingBucket only moves the ped's client into that bucket. A
-- vehicle left in a different bucket than its driver never streams in for
-- them, which looked exactly like the car being deleted the moment a lobby
-- bucket switch happened (on join, on leave, on forfeit, on race finish).
-- Every routing-bucket move for a racer needs the same move applied to
-- whatever vehicle they're currently sitting in.
local function syncVehicleBucket(src, bucket)
    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then
        SetEntityRoutingBucket(veh, bucket)
    end
end

local function generateLobbyId()
    local id = 'lobby_' .. tostring(math.random(100000, 999999))
    while lobbies[id] do id = 'lobby_' .. tostring(math.random(100000, 999999)) end
    return id
end

local function aliasFor(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return GetPlayerName(src) end
    return ('%s %s'):format(player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname)
end

local function buildLobbyPayload(lobby)
    local members = {}
    for _, src in ipairs(lobby.memberOrder) do
        members[#members + 1] = { src = src, alias = lobby.members[src].alias }
    end
    return {
        id = lobby.id, routeId = lobby.routeId, routeName = lobby.routeName,
        hostSrc = lobby.hostSrc, hostAlias = lobby.hostAlias, phase = lobby.phase,
        laps = lobby.laps, collision = lobby.collision, trafficDensityPct = lobby.trafficDensityPct,
        memberCount = #lobby.memberOrder, members = members,
    }
end

notifyLobby = function(lobby, event, ...)
    for _, src in ipairs(lobby.memberOrder) do
        TriggerClientEvent(event, src, ...)
    end
end

broadcastLobbyUpdate = function(lobby)
    notifyLobby(lobby, 'sk_streetkings:racing:mp:lobbyUpdated', buildLobbyPayload(lobby))
end

removeMember = function(lobby, src)
    lobby.members[src] = nil
    for i, s in ipairs(lobby.memberOrder) do
        if s == src then table.remove(lobby.memberOrder, i) break end
    end
    lobbySrcMap[src] = nil
end

closeLobby = function(id, reason)
    local lobby = lobbies[id]
    if not lobby then return end
    if reason ~= 'race_finished' then
        notifyLobby(lobby, 'sk_streetkings:racing:mp:closed', reason)
    end
    for _, src in ipairs(lobby.memberOrder) do
        lobbySrcMap[src] = nil
        -- Always return members to the world bucket. On the 'race_finished' path
        -- finishLobbyRace already did this per-player, but for every other close
        -- reason (invalid route, timeout after staging, etc.) this is what frees
        -- players who were moved into the lobby's isolated bucket.
        SetPlayerRoutingBucket(src, 0)
        syncVehicleBucket(src, 0)
    end
    lobbies[id] = nil
end

-- ── Lobby creation / membership ─────────────────────────────────────────────

--- Builds and registers a lobby record. `hostSrc = false` makes it a system
-- lobby with no player host (see SKMultiplayer.createPopupLobby below) —
-- everything else about it (joining, checkpoints, payout) is identical.
---@param hostSrc integer|false
---@param hostAlias string
---@param routeId string
---@param options table|nil
---@return table|nil lobby, string|nil reason
createLobbyRecord = function(hostSrc, hostAlias, routeId, options)
    local def = SKRoutes.get(routeId)
    if not def then return nil, 'unknown_route' end
    if def.solo then return nil, 'solo_only' end

    options = options or {}
    local laps = def.scheme == 'circuit'
        and math.max(Config.LapsMin, math.min(tonumber(options.laps) or def.laps or 1, Config.LapsMax))
        or 1
    local timeoutSec = tonumber(options.lobbyTimeoutSeconds) or Config.LobbyWaitTimeoutSec

    local id = generateLobbyId()
    local lobby = {
        id = id, routeId = routeId, routeName = def.name,
        hostSrc = hostSrc, hostAlias = hostAlias,
        phase = 'waiting',
        bucket = allocateBucket(),
        laps = laps,
        collision = options.collision ~= false,
        trafficDensityPct = math.max(0, math.min(tonumber(options.trafficDensityPct) or 20, 100)),
        lobbyTimeoutSeconds = timeoutSec,
        isPopup = options.isPopup == true,
        members = {},
        memberOrder = {},
        createdAt = os.time(),
    }
    if hostSrc then
        lobby.members[hostSrc] = { alias = hostAlias }
        lobby.memberOrder = { hostSrc }
        lobbySrcMap[hostSrc] = id
    end
    lobbies[id] = lobby

    SetTimeout(timeoutSec * 1000, function() timeoutLobby(id) end)

    return lobby
end

-- A lobby still 'waiting' once its join window elapses. A normal (player-
-- hosted) lobby just closes, same as always. A popup lobby instead starts
-- with whoever showed up, as long as it met Config.PopupRace.minPlayers —
-- that minimum is deliberately as low as 1, since a pop-up race that needed
-- a full lobby to ever fire would rarely fire at all.
timeoutLobby = function(id)
    local lobby = lobbies[id]
    if not lobby or lobby.phase ~= 'waiting' then return end

    if lobby.isPopup and #lobby.memberOrder >= (Config.PopupRace and Config.PopupRace.minPlayers or 1) then
        lobby.phase = 'starting'
        broadcastLobbyUpdate(lobby)
        startCountdown(lobby)
    else
        closeLobby(id, lobby.isPopup and 'popup_no_joiners' or 'timed_out')
    end
end

lib.callback.register('sk_streetkings:racing:mp:createLobby', function(source, routeId, options)
    if lobbySrcMap[source] then return { ok = false, reason = 'already_in_lobby' } end

    local def = SKRoutes.get(routeId)
    if not def then return { ok = false, reason = 'unknown_route' } end
    if def.unlockRequirement then
        local player = exports.qbx_core:GetPlayer(source)
        if not player then return { ok = false, reason = 'not_loaded' } end
        local unlocked, reason = SKRoutes.checkUnlockRequirement(def, player.PlayerData.citizenid)
        if not unlocked then return { ok = false, reason = reason } end
    end

    local lobby, err = createLobbyRecord(source, aliasFor(source), routeId, options)
    if not lobby then return { ok = false, reason = err } end

    return { ok = true, lobby = buildLobbyPayload(lobby) }
end)

-- Exposed to modules/popuprace/popuprace_s.lua (same resource, same Lua
-- state, loaded after this file — see fxmanifest.lua). Route selection and
-- the "who gets invited" broadcast are entirely popuprace's job; this only
-- opens an unhosted lobby the exact same way a player's would be opened.
SKMultiplayer = {
    createPopupLobby = function(routeId, options)
        options = options or {}
        options.isPopup = true
        return createLobbyRecord(false, 'Street Kings', routeId, options)
    end,
}

lib.callback.register('sk_streetkings:racing:mp:joinLobby', function(source, lobbyId)
    local lobby = lobbies[lobbyId]
    if not lobby then return { ok = false, reason = 'not_found' } end
    if lobby.phase ~= 'waiting' then return { ok = false, reason = 'already_started' } end
    if lobbySrcMap[source] then return { ok = false, reason = 'already_in_lobby' } end

    local def = SKRoutes.get(lobby.routeId)
    if def and def.unlockRequirement then
        local player = exports.qbx_core:GetPlayer(source)
        if not player then return { ok = false, reason = 'not_loaded' } end
        local unlocked, reason = SKRoutes.checkUnlockRequirement(def, player.PlayerData.citizenid)
        if not unlocked then return { ok = false, reason = reason } end
    end

    lobby.members[source] = { alias = aliasFor(source) }
    lobby.memberOrder[#lobby.memberOrder + 1] = source
    lobbySrcMap[source] = lobbyId

    broadcastLobbyUpdate(lobby)
    return { ok = true, lobby = buildLobbyPayload(lobby) }
end)

lib.callback.register('sk_streetkings:racing:mp:getOpenLobbies', function(_source)
    local out = {}
    for _, lobby in pairs(lobbies) do
        if lobby.phase == 'waiting' then out[#out + 1] = buildLobbyPayload(lobby) end
    end
    return out
end)

RegisterNetEvent('sk_streetkings:racing:mp:leaveLobby', function()
    local src = source
    local lobbyId = lobbySrcMap[src]
    local lobby = lobbyId and lobbies[lobbyId]
    if not lobby then return end

    removeMember(lobby, src)
    SetPlayerRoutingBucket(src, 0)
    syncVehicleBucket(src, 0)
    TriggerClientEvent('sk_streetkings:racing:mp:left', src)

    if #lobby.memberOrder == 0 then
        lobbies[lobbyId] = nil
        return
    end
    if lobby.hostSrc == src then
        lobby.hostSrc, lobby.hostAlias = lobby.memberOrder[1], aliasFor(lobby.memberOrder[1])
    end
    broadcastLobbyUpdate(lobby)
end)

-- ── Countdown + race start ──────────────────────────────────────────────────

RegisterNetEvent('sk_streetkings:racing:mp:startLobby', function()
    local src = source
    local lobbyId = lobbySrcMap[src]
    local lobby = lobbyId and lobbies[lobbyId]
    if not lobby or lobby.hostSrc ~= src or lobby.phase ~= 'waiting' then return end

    if #lobby.memberOrder < Config.MinMultiplayerPlayers then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Racing', type = 'error',
            description = ('Need at least %d players to start.'):format(Config.MinMultiplayerPlayers),
        })
        return
    end

    lobby.phase = 'starting'
    broadcastLobbyUpdate(lobby)
    startCountdown(lobby)
end)

startCountdown = function(lobby)
    local payload = buildLobbyPayload(lobby)
    local laneCount = #lobby.memberOrder
    -- Move everyone into the lobby's isolated bucket and hand each player a lane
    -- index so the client can stage them side-by-side on the start line.
    for laneIndex, src in ipairs(lobby.memberOrder) do
        SetPlayerRoutingBucket(src, lobby.bucket)
        syncVehicleBucket(src, lobby.bucket)
        TriggerClientEvent('sk_streetkings:racing:mp:starting', src, payload, Config.LobbyCountdownSec, laneIndex, laneCount)
    end
    SetTimeout(Config.LobbyCountdownSec * 1000, function()
        beginRace(lobby)
    end)
end

beginRace = function(lobby)
    local def = SKRoutes.get(lobby.routeId)
    if not def then closeLobby(lobby.id, 'invalid_route') return end

    lobby.phase = 'racing'
    lobby.race = {
        checkpoints     = SKRouteBuilder.buildCheckpointList(def, lobby.laps),
        checkpointRadii = SKRouteBuilder.buildCheckpointRadii(def, lobby.laps),
        startedAt       = GetGameTimer(),
        players     = {},
        finishOrder = {},
    }
    for _, src in ipairs(lobby.memberOrder) do
        lobby.race.players[src] = { nextIndex = 1, finished = false, forfeited = false, elapsedMs = 0 }
    end

    notifyLobby(lobby, 'sk_streetkings:racing:mp:go', lobby.id)

    CreateThread(function()
        while lobbies[lobby.id] and lobby.phase == 'racing' do
            Wait(Config.StandingsBroadcastMs)
            broadcastStandings(lobby)
        end
    end)
end

broadcastStandings = function(lobby)
    if not lobby.race then return end
    local snapshot = {}
    for _, src in ipairs(lobby.memberOrder) do
        local p = lobby.race.players[src]
        if p then
            snapshot[#snapshot + 1] = {
                src = src, alias = lobby.members[src] and lobby.members[src].alias or '?',
                cpIndex = p.nextIndex - 1, finished = p.finished, forfeited = p.forfeited,
                elapsedMs = p.finished and p.elapsedMs or (GetGameTimer() - lobby.race.startedAt),
            }
        end
    end
    table.sort(snapshot, function(a, b)
        if a.finished ~= b.finished then return a.finished end
        if a.finished then return a.elapsedMs < b.elapsedMs end
        return a.cpIndex > b.cpIndex
    end)
    notifyLobby(lobby, 'sk_streetkings:racing:mp:standings', snapshot)
end

-- ── Checkpoint progress / finish / forfeit ──────────────────────────────────

-- Client reports its vehicle class/model at GO (server can't read those natives).
-- Stored per-player so the winner's row can be logged to the leaderboard.
RegisterNetEvent('sk_streetkings:racing:mp:vehicleInfo', function(info)
    local src = source
    local lobbyId = lobbySrcMap[src]
    local lobby = lobbyId and lobbies[lobbyId]
    if not lobby or not lobby.race then return end
    local p = lobby.race.players[src]
    if not p then return end
    local classId = info and tonumber(info.class) or -1
    p.vehClassName = Config.VehicleClassNames[classId] or 'Unknown'
    p.vehModelName = info and tostring(info.model or '') or ''
end)

local function allPlayersDone(lobby)
    for _, src in ipairs(lobby.memberOrder) do
        local p = lobby.race.players[src]
        if p and not p.finished and not p.forfeited then return false end
    end
    return true
end

RegisterNetEvent('sk_streetkings:racing:mp:hitCheckpoint', function(checkpointIndex)
    local src = source
    local lobbyId = lobbySrcMap[src]
    local lobby = lobbyId and lobbies[lobbyId]
    if not lobby or not lobby.race then return end

    local p = lobby.race.players[src]
    if not p or p.finished or p.forfeited then return end
    if checkpointIndex ~= p.nextIndex then return end

    local ped = GetPlayerPed(src)
    if ped == 0 then return end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return end

    local target = lobby.race.checkpoints[checkpointIndex]
    local radius = lobby.race.checkpointRadii[checkpointIndex] or Config.CheckpointRadius
    if not target or not SKValidation.withinRadius(GetEntityCoords(ped), target, radius) then return end

    p.nextIndex = p.nextIndex + 1

    if p.nextIndex > #lobby.race.checkpoints then
        p.finished = true
        p.elapsedMs = GetGameTimer() - lobby.race.startedAt
        lobby.race.finishOrder[#lobby.race.finishOrder + 1] = src
        TriggerClientEvent('sk_streetkings:racing:mp:youFinished', src, p.elapsedMs)

        if not lobby.race.finishDeadlineSet then
            lobby.race.finishDeadlineSet = true
            SetTimeout(Config.MultiplayerFinishGraceSec * 1000, function()
                finishLobbyRace(lobby)
            end)
        end

        if allPlayersDone(lobby) then finishLobbyRace(lobby) end
    end
end)

RegisterNetEvent('sk_streetkings:racing:mp:forfeit', function()
    local src = source
    local lobbyId = lobbySrcMap[src]
    local lobby = lobbyId and lobbies[lobbyId]
    if not lobby or not lobby.race then return end

    local p = lobby.race.players[src]
    if not p or p.finished or p.forfeited then return end

    SKPlayer.removeMoney(src, Config.ForfeitCost, 'sk-race-forfeit')

    p.forfeited = true
    p.elapsedMs = GetGameTimer() - lobby.race.startedAt
    SetPlayerRoutingBucket(src, 0)
    syncVehicleBucket(src, 0)
    TriggerClientEvent('sk_streetkings:racing:mp:youForfeited', src)

    if allPlayersDone(lobby) then finishLobbyRace(lobby) end
end)

finishLobbyRace = function(lobby)
    if not lobby.race or lobby.phase == 'finished' then return end
    lobby.phase = 'finished'

    -- Finishers first (in finish order), then non-finishers (forfeits/DNFs) last.
    local ranking = {}
    for _, src in ipairs(lobby.race.finishOrder) do ranking[#ranking + 1] = src end
    for _, src in ipairs(lobby.memberOrder) do
        local p = lobby.race.players[src]
        if p and not p.finished then ranking[#ranking + 1] = src end
    end

    local def = SKRoutes.get(lobby.routeId)
    local scale = (def and SKRewardMath.getRewardScale(def) or Config.RewardScaling.minimumScale)
        * SKRewardMath.getMeetNightMultiplier()
    local mrs = Config.MultiplayerRewardScaling
    local playerCount = #lobby.memberOrder
    local playerCountBonus = math.min(mrs.playerCountBonusCap, math.max(0, playerCount - 1) * mrs.playerCountBonusPerExtra)

    for position, src in ipairs(ranking) do
        local p = lobby.race.players[src]
        local positionMult = p.forfeited and mrs.forfeitMultiplier
            or (mrs.positionMultipliers[position] or mrs.lastPlaceFloor)

        local cash = math.floor(Config.RewardScaling.base.cash * scale * positionMult * (1.0 + playerCountBonus))
        local xp   = math.floor(Config.RewardScaling.base.xp   * scale * positionMult * (1.0 + playerCountBonus))

        if cash > 0 then
            SKPlayer.addMoney(src, cash, 'sk-race-mp-reward')
        end

        local newLevel, leveledUp = nil, false
        if SKPlayer.get(src) and xp > 0 then
            newLevel, leveledUp = SKProfiles.awardXp(src, xp)
        end

        if Config.Modules.stats then
            SKStats.increment(src, 'racesCompleted', 1)
            SKStats.increment(src, 'totalCashEarned', cash)
            if position == 1 and not p.forfeited then
                SKStats.increment(src, 'racesWon', 1)
                local stats = SKSaves.read(src, 'stats') or {}
                local streak = (stats.currentWinStreak or 0) + 1
                SKStats.setValue(src, 'currentWinStreak', streak)
                SKStats.setMax(src, 'bestWinStreak', streak)
            else
                SKStats.increment(src, 'racesLost', 1)
                SKStats.setValue(src, 'currentWinStreak', 0)
            end
        end

        SetPlayerRoutingBucket(src, 0)
        syncVehicleBucket(src, 0)
        TriggerClientEvent('sk_streetkings:racing:mp:results', src, {
            position = position, totalPlayers = playerCount, cash = cash, xp = xp,
            forfeited = p.forfeited, elapsedMs = p.elapsedMs, level = newLevel, leveledUp = leveledUp,
        })
    end

    -- Log the winner's time to the route leaderboard too, if they actually
    -- finished. Class/model come from the client-reported vehicle info (see the
    -- mp:vehicleInfo handler above).
    local winnerSrc = ranking[1]
    local winnerState = winnerSrc and lobby.race.players[winnerSrc]
    if def and winnerSrc and winnerState and winnerState.finished then
        local player = exports.qbx_core:GetPlayer(winnerSrc)
        if player then
            local alias = ('%s %s'):format(player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname)
            SKLeaderboard.insert(
                player.PlayerData.citizenid, alias, lobby.routeId,
                winnerState.vehClassName or 'Unknown', winnerState.elapsedMs, winnerState.vehModelName or ''
            )
        end
    end

    closeLobby(lobby.id, 'race_finished')
end

AddEventHandler('playerDropped', function()
    local src = source
    local lobbyId = lobbySrcMap[src]
    local lobby = lobbyId and lobbies[lobbyId]
    if not lobby then return end

    if lobby.race and lobby.race.players[src] and not lobby.race.players[src].finished then
        lobby.race.players[src].forfeited = true
    end
    removeMember(lobby, src)

    if #lobby.memberOrder == 0 then
        lobbies[lobbyId] = nil
        return
    end
    if lobby.hostSrc == src then
        lobby.hostSrc, lobby.hostAlias = lobby.memberOrder[1], aliasFor(lobby.memberOrder[1])
    end
    if lobby.race and allPlayersDone(lobby) then
        finishLobbyRace(lobby)
    else
        broadcastLobbyUpdate(lobby)
    end
end)
