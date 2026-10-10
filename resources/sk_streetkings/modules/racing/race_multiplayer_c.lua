-- Multiplayer lobby UI + race flow. Mirrors StreetKings' host/join lobby +
-- live standings design, wired to server/multiplayer.lua.
--
-- Staging: on 'starting' each client is teleported into its lane on the start
-- line and frozen through the countdown; the freeze is released on 'go'. Traffic
-- density and (optional) racer-to-racer collision are applied per-frame during
-- the race from the lobby's chosen options.

local myServerId = GetPlayerServerId(PlayerId())

local currentLobby = nil -- last lobby payload from the server
local raceState    = nil -- { checkpoints, index, startedAt, collision, trafficPct, scheme, laps, cpPerLap }
local standings    = nil -- last standings broadcast
local frozenVeh    = nil -- vehicle frozen during the staging countdown

local openHostSetup, openLobbyBrowser -- forward declarations, assigned below

local function unfreezeStagedVehicle()
    if frozenVeh and DoesEntityExist(frozenVeh) then
        FreezeEntityPosition(frozenVeh, false)
    end
    frozenVeh = nil
end

local function endRaceCleanup()
    raceState, standings = nil, nil
    SKCheckpoints.clear()
    unfreezeStagedVehicle()
    SKC.SetGameState(GameState.FREEROAM)
    SKPushLapHud({ show = false })
end

function OpenLobbyMenu()
    if not currentLobby then return end
    local isHost = currentLobby.hostSrc == myServerId

    local memberNames = {}
    for _, m in ipairs(currentLobby.members) do memberNames[#memberNames + 1] = m.alias end

    local options = {
        { title = ('Players (%d)'):format(currentLobby.memberCount), description = table.concat(memberNames, ', '), disabled = true },
    }
    if isHost then
        options[#options + 1] = {
            title       = 'Start Race',
            description = ('Need at least %d players.'):format(Config.MinMultiplayerPlayers),
            onSelect    = function() TriggerServerEvent('sk_streetkings:racing:mp:startLobby') end,
        }
    end
    options[#options + 1] = {
        title    = 'Leave Lobby',
        onSelect = function() TriggerServerEvent('sk_streetkings:racing:mp:leaveLobby') end,
    }

    lib.registerContext({ id = 'sk_racing_mp_lobby', title = currentLobby.routeName, options = options })
    lib.showContext('sk_racing_mp_lobby')
end

-- Called by client/race_singleplayer.lua's chooser menu.
function OpenMultiplayerSetup(routeId, def)
    if currentLobby then
        OpenLobbyMenu()
        return
    end

    lib.registerContext({
        id    = 'sk_racing_mp_setup',
        title = 'Multiplayer — ' .. def.name,
        options = {
            {
                title       = 'Host a Lobby',
                description = 'Configure race options and wait for others to join.',
                onSelect    = function() CreateThread(function() openHostSetup(routeId, def) end) end,
            },
            {
                title       = 'Browse Open Lobbies',
                description = 'Join a lobby someone else is hosting.',
                onSelect    = function() CreateThread(openLobbyBrowser) end,
            },
        },
    })
    lib.showContext('sk_racing_mp_setup')
end

openHostSetup = function(routeId, def)
    local fields = {}
    if def.scheme == 'circuit' then
        fields[#fields + 1] = { type = 'number', label = 'Laps', default = def.laps or 1, min = Config.LapsMin, max = Config.LapsMax }
    end
    fields[#fields + 1] = { type = 'checkbox', label = 'Player Collision', checked = true }
    fields[#fields + 1] = { type = 'slider', label = 'Traffic Density %', default = 20, min = 0, max = 100 }
    fields[#fields + 1] = {
        type = 'select', label = 'Lobby Wait Timeout', default = 180,
        options = {
            { value = 180, label = '3 minutes' },
            { value = 300, label = '5 minutes' },
            { value = 600, label = '10 minutes' },
        },
    }

    local input = lib.inputDialog('Host: ' .. def.name, fields)
    if not input then return end

    local i = 1
    local laps = def.laps or 1
    if def.scheme == 'circuit' then laps = tonumber(input[i]) or laps; i = i + 1 end
    local collision = input[i]; i = i + 1
    local trafficDensityPct = tonumber(input[i]) or 20; i = i + 1
    local lobbyTimeoutSeconds = tonumber(input[i]) or 180

    local resp = lib.callback.await('sk_streetkings:racing:mp:createLobby', false, routeId, {
        laps = laps, collision = collision ~= false, trafficDensityPct = trafficDensityPct, lobbyTimeoutSeconds = lobbyTimeoutSeconds,
    })
    if not resp or not resp.ok then
        lib.notify({ title = 'Racing', description = 'Could not create lobby: ' .. (resp and resp.reason or 'error'), type = 'error' })
        return
    end

    currentLobby = resp.lobby
    lib.notify({ title = 'Lobby Created', description = 'Waiting for players to join...', type = 'success' })
    OpenLobbyMenu()
end

openLobbyBrowser = function()
    local list = lib.callback.await('sk_streetkings:racing:mp:getOpenLobbies', false) or {}
    if #list == 0 then
        lib.notify({ title = 'Racing', description = 'No open lobbies right now.', type = 'inform' })
        return
    end

    local options = {}
    for _, lobby in ipairs(list) do
        options[#options + 1] = {
            title       = lobby.routeName,
            description = ('Host: %s  |  %d player(s)'):format(lobby.hostAlias, lobby.memberCount),
            onSelect    = function()
                CreateThread(function()
                    local resp = lib.callback.await('sk_streetkings:racing:mp:joinLobby', false, lobby.id)
                    if not resp or not resp.ok then
                        lib.notify({ title = 'Racing', description = 'Could not join: ' .. (resp and resp.reason or 'error'), type = 'error' })
                        return
                    end
                    currentLobby = resp.lobby
                    lib.notify({ title = 'Lobby Joined', description = lobby.routeName, type = 'success' })
                    OpenLobbyMenu()
                end)
            end,
        }
    end

    lib.registerContext({ id = 'sk_racing_mp_browse', title = 'Open Lobbies', options = options })
    lib.showContext('sk_racing_mp_browse')
end

-- Entry point for other resources (e.g. um_carmeet's Race Organizer hub) to
-- open the "browse open lobbies" menu without going through a specific route.
function BrowseOpenLobbies()
    if currentLobby then
        OpenLobbyMenu()
        return
    end
    CreateThread(openLobbyBrowser)
end

-- currentLobby above is a file-local upvalue, invisible to other files even
-- within this same resource — this getter is how modules/popuprace/
-- popuprace_c.lua checks "am I already in/racing a lobby" before showing a
-- new invite.
function IsInMultiplayerLobby()
    return currentLobby ~= nil
end

-- Entry point for modules/popuprace/popuprace_c.lua: joins a specific lobby
-- id directly (arrival-triggered, no menu) instead of browsing. Every event
-- this file already listens for (lobbyUpdated/starting/go/standings/results)
-- fires the same way regardless of how currentLobby got set, so nothing else
-- needs to change for a popup-joined race to play out identically to a
-- manually-joined one.
function JoinPopupLobby(lobbyId)
    if currentLobby then return false end
    local resp = lib.callback.await('sk_streetkings:racing:mp:joinLobby', false, lobbyId)
    if not resp or not resp.ok then
        lib.notify({ title = 'Racing', description = 'Could not join: ' .. (resp and resp.reason or 'error'), type = 'error' })
        return false
    end
    currentLobby = resp.lobby
    lib.notify({ title = 'Pop-up Race', description = 'Joined: ' .. currentLobby.routeName, type = 'success' })
    return true
end

-- ── Lobby state sync ─────────────────────────────────────────────────────

RegisterNetEvent('sk_streetkings:racing:mp:lobbyUpdated', function(payload)
    if not currentLobby or currentLobby.id ~= payload.id then return end
    currentLobby = payload
end)

RegisterNetEvent('sk_streetkings:racing:mp:left', function()
    currentLobby = nil
    endRaceCleanup()
end)

RegisterNetEvent('sk_streetkings:racing:mp:closed', function(reason)
    if not currentLobby then return end
    currentLobby = nil
    endRaceCleanup()
    lib.notify({ title = 'Racing', description = 'Lobby closed: ' .. reason, type = 'error' })
end)

-- Staging: teleport into lane, freeze, run the visual countdown. The freeze is
-- released by the authoritative 'go' event below.
RegisterNetEvent('sk_streetkings:racing:mp:starting', function(payload, countdownSec, laneIndex, laneCount)
    currentLobby = payload
    SKC.SetGameState(GameState.MULTIPLAYER_LOBBY)
    CreateThread(function()
        local routes = lib.callback.await('sk_streetkings:racing:getRoutes', false) or {}
        local def = routes[currentLobby.routeId]
        local veh = GetVehiclePedIsIn(cache.ped, false)
        if def and veh ~= 0 then
            local laneOffset = (laneIndex - 1) * 4.0 - (laneCount - 1) * 2.0
            SKTeleportToStart(veh, def.start, laneOffset)
            FreezeEntityPosition(veh, true)
            frozenVeh = veh
        end
        SKRaceCountdown(countdownSec, nil) -- visual only; GO is driven by mp:go
    end)
end)

-- ── Race flow ────────────────────────────────────────────────────────────

RegisterNetEvent('sk_streetkings:racing:mp:go', function(lobbyId)
    if not currentLobby or currentLobby.id ~= lobbyId then return end
    CreateThread(function()
        local routes = lib.callback.await('sk_streetkings:racing:getRoutes', false) or {}
        local def = routes[currentLobby.routeId]
        if not def then return end

        unfreezeStagedVehicle()
        SKC.SetGameState(GameState.MULTIPLAYER_EVENT)

        -- Same reasoning as the singleplayer flow: only 'circuit' has a real
        -- lap count, and the host's chosen lap count (currentLobby.laps) is
        -- what buildCheckpointList was actually expanded with above.
        local laps = (def.scheme == 'circuit') and (currentLobby.laps or def.laps or 1) or 1
        raceState = {
            checkpoints = SKRouteBuilder.buildCheckpointList(def, currentLobby.laps),
            radii       = SKRouteBuilder.buildCheckpointRadii(def, currentLobby.laps),
            meta        = SKCheckpoints.meta(def, SKRouteBuilder.buildSourceIndex(def, currentLobby.laps)),
            index       = 1,
            startedAt   = GetGameTimer(),
            collision   = currentLobby.collision,
            trafficPct  = currentLobby.trafficDensityPct or 20,
            scheme      = def.scheme,
            laps        = laps,
            -- +1: buildCheckpointList appends a start/finish checkpoint at the
            -- end of every circuit lap (route_sh.lua), so the flattened list
            -- has one more entry per lap than def.checkpoints itself.
            cpPerLap    = (def.scheme == 'circuit') and (#def.checkpoints + 1) or #def.checkpoints,
        }
        SKCheckpoints.show(raceState.checkpoints, 1, #raceState.checkpoints == 1, raceState.meta)
        SKPushLapHud({
            lap = 1, laps = raceState.laps,
            cp = 0, cpTotal = raceState.cpPerLap,
            elapsedMs = 0, running = true,
        })

        local veh = GetVehiclePedIsIn(cache.ped, false)
        if veh ~= 0 then
            TriggerServerEvent('sk_streetkings:racing:mp:vehicleInfo', SKVehicleInfo(veh))
        end
    end)
end)

RegisterNetEvent('sk_streetkings:racing:mp:standings', function(snapshot)
    standings = snapshot
end)

RegisterNetEvent('sk_streetkings:racing:mp:youFinished', function(elapsedMs)
    SKCheckpoints.clear()
    lib.notify({ title = 'Finished!', description = 'Time: ' .. SKFormatTime(elapsedMs) .. ' — waiting for results...', type = 'success' })
end)

RegisterNetEvent('sk_streetkings:racing:mp:youForfeited', function()
    endRaceCleanup()
    lib.notify({ title = 'Racing', description = 'You forfeited the race.', type = 'error' })
end)

RegisterNetEvent('sk_streetkings:racing:mp:results', function(result)
    currentLobby = nil
    endRaceCleanup()

    local lines
    if result.forfeited then
        lines = { 'You forfeited.' }
    else
        SKRaceResult(result.position, result.elapsedMs)
        lines = {
            ('Position: #%d / %d'):format(result.position, result.totalPlayers),
            ('Time: %s'):format(SKFormatTime(result.elapsedMs)),
            ('Reward: $%d  (+%d XP)'):format(result.cash, result.xp),
        }
    end
    if result.leveledUp then lines[#lines + 1] = ('Race level up! Now level %d'):format(result.level) end

    lib.notify({
        title = 'Race Results', description = table.concat(lines, '\n'),
        type = result.forfeited and 'error' or 'success', duration = 9000,
    })
end)

RegisterCommand('forfeitrace', function()
    if not raceState then return end
    TriggerServerEvent('sk_streetkings:racing:mp:forfeit')
end, false)

-- Resolve another racer's current vehicle (same routing bucket), or 0.
local function racerVehicle(serverId)
    local plid = GetPlayerFromServerId(serverId)
    if plid == -1 then return 0 end
    local ped = GetPlayerPed(plid)
    if ped == 0 then return 0 end
    return GetVehiclePedIsIn(ped, false)
end

-- Checkpoint proximity loop + per-frame race options (traffic / collision)
CreateThread(function()
    while true do
        local sleep = 1000
        if raceState then
            sleep = 0

            -- Traffic density set by the lobby host.
            local pct = (raceState.trafficPct or 20) / 100.0
            SetVehicleDensityMultiplierThisFrame(pct)
            SetRandomVehicleDensityMultiplierThisFrame(pct)
            SetParkedVehicleDensityMultiplierThisFrame(pct)
            SetPedDensityMultiplierThisFrame(pct)

            -- Ghost other racers when the host disabled collision.
            if raceState.collision == false and standings then
                local myVeh = GetVehiclePedIsIn(cache.ped, false)
                if myVeh ~= 0 then
                    for _, row in ipairs(standings) do
                        if row.src ~= myServerId then
                            local otherVeh = racerVehicle(row.src)
                            if otherVeh ~= 0 then
                                SetEntityNoCollisionEntity(myVeh, otherVeh, true)
                            end
                        end
                    end
                end
            end

            local dist = SKCheckpoints.distanceTo(GetEntityCoords(cache.ped), raceState.checkpoints, raceState.index)
            if dist < SKCheckpoints.pickupRadius(raceState.radii, raceState.index) then
                TriggerServerEvent('sk_streetkings:racing:mp:hitCheckpoint', raceState.index)

                -- Same "progress for the checkpoint just completed" call as
                -- the singleplayer flow — see its comment for why this reads
                -- raceState.index BEFORE incrementing it.
                local lap, cpInLap = SKLapProgress(raceState.index, raceState.cpPerLap, raceState.laps)
                local finished = raceState.index >= #raceState.checkpoints

                raceState.index = raceState.index + 1
                if raceState.index > #raceState.checkpoints then
                    SKCheckpoints.clear()
                else
                    SKCheckpoints.show(raceState.checkpoints, raceState.index, raceState.index == #raceState.checkpoints, raceState.meta)
                end

                -- Freezes on this player's own finish; endRaceCleanup (via
                -- the eventual mp:results broadcast once everyone's done, or
                -- a forfeit) is what actually hides the panel.
                -- Where this player stands in the field, from the server's
                -- last standings broadcast (sorted, one row per racer).
                local position, racers
                if standings then
                    racers = #standings
                    for i = 1, racers do
                        if standings[i].src == myServerId then position = i break end
                    end
                end
                SKPushLapHud({
                    lap = lap, laps = raceState.laps,
                    cp = cpInLap, cpTotal = raceState.cpPerLap,
                    position = position, racers = position and racers or nil,
                    elapsedMs = GetGameTimer() - raceState.startedAt,
                    running = not finished,
                })
                SKLapSplit(raceState, lap, cpInLap, raceState.cpPerLap, raceState.laps,
                    GetGameTimer() - raceState.startedAt)
            end
        end
        Wait(sleep)
    end
end)

-- Live standings HUD (idles when there's nothing to show)
CreateThread(function()
    while true do
        local sleep = 500
        if standings and #standings > 0 then
            sleep = 0
            local rowH   = 0.032
            local panelH = rowH * (#standings + 1) + 0.01
            local panelY = 0.14

            DrawRect(0.88, panelY, 0.18, panelH, 0, 0, 0, 160)
            SetTextFont(4) SetTextScale(0.0, 0.28) SetTextColour(255, 215, 0, 255) SetTextCentre(true) SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName('STANDINGS')
            EndTextCommandDisplayText(0.88, panelY - panelH / 2 + 0.004)

            for i, row in ipairs(standings) do
                local rowY = panelY - panelH / 2 + rowH * i + 0.004
                local isMe = row.src == myServerId
                local r, g, b = isMe and 0 or 255, isMe and 255 or 255, isMe and 0 or 255
                local statusText = row.forfeited and 'DNF' or (row.finished and SKFormatTime(row.elapsedMs) or ('CP ' .. row.cpIndex))

                SetTextFont(4) SetTextScale(0.0, 0.26) SetTextColour(r, g, b, 255) SetTextCentre(false) SetTextOutline()
                BeginTextCommandDisplayText('STRING')
                AddTextComponentSubstringPlayerName(('%d. %s — %s'):format(i, row.alias, statusText))
                EndTextCommandDisplayText(0.795, rowY)
            end
        end
        Wait(sleep)
    end
end)
