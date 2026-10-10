-- NPC spectator races: betting menu, racer spawning and the spectate readout.
--
-- Carried over from um_carmeet's cl_carmeet.lua. Changes: the bet limits now
-- come from the resource-wide Config.Betting, the route pool moved under
-- Meet.NpcRace.routes, and the inline spectate HUD is an SKHud widget pinned to
-- the shared top-right anchor so it stays clear of um_hud.

if not (Config.Modules.carmeet and Config.Modules.npcBetting) then return end

local Meet = lib.require('data.carmeet')

SKBetting = {}

local spectateNpcs = {}
local lastRacers   = nil -- retained so the finish event can redraw the list

-- ── Route selection ─────────────────────────────────────────────────────────

local function resolveNpcRaceRoute()
    local all = Meet.NpcRace.routes
    if #all == 0 then return nil end
    if Meet.NpcRace.routeSelection == 'random' then return all[math.random(1, #all)] end
    for _, r in ipairs(all) do
        if r.name == Meet.NpcRace.routeSelection then return r end
    end
    return all[1]
end

--- vector types do not survive the network boundary; flatten to a plain table.
local function serializeCoord(c)
    if not c then return nil end
    return { x = c.x, y = c.y, z = c.z, w = c.w }
end

-- ── Betting menu ────────────────────────────────────────────────────────────

function SKBetting.openMenu()
    local racers = Meet.NpcRace.racers
    local opts = {}

    for i, racer in ipairs(racers) do
        opts[#opts + 1] = {
            title       = racer.name,
            description = ('%.1fx payout  —  bet $%d–$%d'):format(racer.odds, Config.Betting.min, Config.Betting.max),
            icon        = 'flag-checkered',
            onSelect    = function()
                CreateThread(function()
                    local input = lib.inputDialog('Bet on ' .. racer.name, {
                        {
                            type    = 'number',
                            label   = ('Amount ($%d – $%d)'):format(Config.Betting.min, Config.Betting.max),
                            default = Config.Betting.min,
                            min     = Config.Betting.min,
                            max     = Config.Betting.max,
                        },
                    })
                    if not input or not input[1] then return end

                    local amount = math.floor(input[1])
                    local route  = resolveNpcRaceRoute()

                    local racersPayload = {}
                    for _, r in ipairs(racers) do
                        racersPayload[#racersPayload + 1] = { name = r.name, odds = r.odds }
                    end

                    local routePayload = {
                        name        = route and route.name or 'Unknown',
                        startCoords = route and serializeCoord(route.startCoords) or nil,
                        checkpoints = {},
                        racers      = racersPayload,
                    }
                    if route and route.checkpoints then
                        for _, cp in ipairs(route.checkpoints) do
                            routePayload.checkpoints[#routePayload.checkpoints + 1] = serializeCoord(cp)
                        end
                    end

                    TriggerServerEvent('sk_streetkings:carmeet:placeBet', i, amount, routePayload)
                end)
            end,
        }
    end

    lib.registerContext({ id = 'carmeet_npc_bet', title = 'Bet on NPC Race', options = opts })
    lib.showContext('carmeet_npc_bet')
end

-- ── Spectate HUD ────────────────────────────────────────────────────────────

SKHud.register('npcRace', function(data)
    local racers = data.racers
    local n      = #racers
    local rowH   = 0.032
    local panelH = rowH * (n + 1) + 0.01
    local a      = SKHud.Anchor.topRight

    SKHud.Panel(a.x, a.y, 0.18, panelH, SKHud.Palette.panel)

    local header =
        data.status == 'waiting'  and 'BETTING OPEN' or
        data.status == 'racing'   and 'RACE IN PROGRESS' or
        data.status == 'finished' and ('WINNER: ' .. (data.winnerName or '?')) or ''
    SKHud.Text(header, a.x, a.y - panelH / 2 + 0.005, 0.28, SKHud.Palette.accent, true)

    for i, racer in ipairs(racers) do
        local rowY = a.y - panelH / 2 + rowH * i + 0.005
        local colour = SKHud.Palette.text
        if data.status == 'finished' then
            colour = (data.winnerIdx == i) and SKHud.Palette.success or SKHud.Palette.textDim
        end
        SKHud.Text(('%s  %.1fx'):format(racer.name, racer.odds), a.x - 0.085, rowY, 0.26, colour)
    end
end)

-- ── Racer spawning ──────────────────────────────────────────────────────────

local function clearSpectateNpcs()
    for _, r in ipairs(spectateNpcs) do
        if r.ped and DoesEntityExist(r.ped) then
            SetEntityAsMissionEntity(r.ped, false, true)
            DeleteEntity(r.ped)
        end
        if r.veh and DoesEntityExist(r.veh) then
            SetEntityAsMissionEntity(r.veh, false, true)
            DeleteEntity(r.veh)
        end
    end
    spectateNpcs = {}
    lastRacers   = nil
    SKHud.clear('npcRace')
end

local function teleportToSpectatorSpot()
    local sc = Meet.NpcRace.spectatorCoords
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(25) end
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if veh ~= 0 then
        TaskLeaveVehicle(cache.ped, veh, 0)
        Wait(800)
    end
    SetPedCoordsKeepVehicle(cache.ped, sc.x, sc.y, sc.z)
    SetEntityHeading(cache.ped, sc.w or 0.0)
    DoScreenFadeIn(600)
end

local function spawnAndDriveRacers(route, racers, winnerIdx, durationMs)
    clearSpectateNpcs()
    if not route or not route.startCoords then return end

    local sc = route.startCoords -- plain table {x,y,z,w}
    local configRacers = Meet.NpcRace.racers

    for i, racer in ipairs(racers) do
        -- Server payload carries no model hashes; match back to config by index.
        local cfgRacer = configRacers[i] or configRacers[1]
        local model    = cfgRacer.vehicle

        lib.requestModel(model, 10000)
        lib.requestModel(`s_m_y_xmech_01`, 10000)

        -- Stagger lanes perpendicular to the start heading so cars don't stack.
        local laneOffset = (i - 1) * 5.0 - (#racers - 1) * 2.5
        local headRad    = math.rad(-(sc.w or 0))
        local ox = math.sin(headRad + math.pi / 2) * laneOffset
        local oy = math.cos(headRad + math.pi / 2) * laneOffset

        local veh = CreateVehicle(model, sc.x + ox, sc.y + oy, sc.z, sc.w or 0, true, false)
        SetVehicleModKit(veh, 0)
        if cfgRacer.color then SetVehicleColours(veh, cfgRacer.color[1], cfgRacer.color[2]) end
        SetVehicleNumberPlateText(veh, racer.name:upper())
        SetVehicleEngineOn(veh, true, true, false)

        local ped = CreatePed(4, `s_m_y_xmech_01`, sc.x + ox, sc.y + oy, sc.z, sc.w or 0, true, false)
        SetPedIntoVehicle(ped, veh, -1)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedFleeAttributes(ped, 0, false)

        SetModelAsNoLongerNeeded(model)
        SetModelAsNoLongerNeeded(`s_m_y_xmech_01`)

        spectateNpcs[i] = { ped = ped, veh = veh, name = racer.name, idx = i }

        -- The winner is decided server-side; giving them a higher cruise speed
        -- makes them arrive first without teleporting or cheating visibly.
        local speed = (i == winnerIdx) and 62.0 or (48.0 + math.random() * 8.0)
        CreateThread(function()
            if not route.checkpoints then return end
            for _, cp in ipairs(route.checkpoints) do
                TaskVehicleDriveToCoordLongrange(ped, veh, cp.x, cp.y, cp.z, speed, 0xC0035C87, 5.0)
                while DoesEntityExist(ped) do
                    Wait(500)
                    if #(GetEntityCoords(ped) - vec3(cp.x, cp.y, cp.z)) < 20.0 then break end
                end
            end
        end)
    end

    -- Set after clearSpectateNpcs() above, which resets it.
    lastRacers = racers
    SKHud.set('npcRace', { racers = racers, status = 'racing', winnerIdx = nil })

    CreateThread(function()
        Wait(durationMs + 6000)
        clearSpectateNpcs()
    end)
end

-- ── Server events ───────────────────────────────────────────────────────────

RegisterNetEvent('sk_streetkings:carmeet:spectateCurrentRace', function(data)
    CreateThread(function()
        teleportToSpectatorSpot()
        if data.durationMs and data.route then
            -- Sets lastRacers and the widget itself.
            spawnAndDriveRacers(data.route, data.racers, nil, data.durationMs)
        else
            lastRacers = data.racers or {}
            SKHud.set('npcRace', { racers = lastRacers, status = 'waiting', winnerIdx = nil })
        end
    end)
end)

RegisterNetEvent('sk_streetkings:carmeet:npcRaceStart', function(data)
    CreateThread(function()
        spawnAndDriveRacers(data.route, data.racers, data.winnerIdx, data.durationMs)
    end)
end)

-- The finish event only carries {winnerIdx, winnerName} — the racer list has to
-- come from whatever the widget is already showing, so keep a local copy.
RegisterNetEvent('sk_streetkings:carmeet:npcRaceFinished', function(data)
    if lastRacers then
        SKHud.set('npcRace', {
            racers     = lastRacers,
            status     = 'finished',
            winnerIdx  = data.winnerIdx,
            winnerName = data.winnerName,
        })
    end
    CreateThread(function()
        Wait(7000)
        clearSpectateNpcs()
    end)
end)

-- Announced to everyone, not just spectators.
RegisterNetEvent('sk_streetkings:carmeet:bettingOpen', function(data)
    if not (data and data.racers) then return end
    local names = {}
    for _, r in ipairs(data.racers) do names[#names + 1] = r.name .. ' (' .. r.odds .. 'x)' end
    lib.notify({
        title       = 'NPC Race — Betting Open',
        description = 'Talk to the Race Organizer to place your bet!\n' .. table.concat(names, '  |  '),
        type        = 'inform',
        duration    = 10000,
    })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearSpectateNpcs() end
end)
