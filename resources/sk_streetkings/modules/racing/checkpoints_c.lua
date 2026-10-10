-- Checkpoint rendering shared by the singleplayer and multiplayer race flows.
-- Pure natives (CreateCheckpoint/blips/GPS route) — no framework dependency,
-- ported near-directly from StreetKings' portable route/preview approach.

SKCheckpoints = {}

local activeCheckpointHandle = nil
local activeBlip = nil
local nextBlip = nil

function SKCheckpoints.clear()
    if activeCheckpointHandle then
        DeleteCheckpoint(activeCheckpointHandle)
        activeCheckpointHandle = nil
    end
    if activeBlip and DoesBlipExist(activeBlip) then RemoveBlip(activeBlip) end
    if nextBlip and DoesBlipExist(nextBlip) then RemoveBlip(nextBlip) end
    activeBlip, nextBlip = nil, nil
end

-- What a race hands the renderer so gates look like Rockstar's (shared/gates_sh.lua):
-- chevrons that thicken with the turn, a lap marker at the end of each lap, green knife and blue
-- inverted stunt rings, the chequered flag at the end.
---@param def table route definition (kind, gateKinds, gateStunts, start)
---@param sourceIndex integer[] SKRouteBuilder.buildSourceIndex for the expanded list being driven
function SKCheckpoints.meta(def, sourceIndex)
    return {
        kind = def.kind or 'road', start = def.start, sourceIndex = sourceIndex,
        gateKinds = def.gateKinds, gateStunts = def.gateStunts,
    }
end

-- checkpoints: array of vec3. index: 1-based current target. isLast: bool.
-- meta (optional, SKCheckpoints.meta): what to draw; without it every gate is the plain road ring.
function SKCheckpoints.show(checkpoints, index, isLast, meta)
    SKCheckpoints.clear()
    local cp = checkpoints[index]
    if not cp then return end

    local nextCp = checkpoints[index + 1]
    local dir = nextCp and (nextCp - cp) or vector3(0.0, 0.0, 0.0)

    local kind = meta and meta.kind or 'road'
    local src = meta and meta.sourceIndex and meta.sourceIndex[index] or 0
    local gateKind = src > 0 and meta and meta.gateKinds and meta.gateKinds[src] or 'default'
    local stunt = src > 0 and meta and meta.gateStunts and meta.gateStunts[src] or nil
    -- Source 0 is the start/finish line the builder puts at the end of every lap: a lap marker
    -- unless it is the very last gate of the race.
    local isLapEnd = src == 0 and not isLast

    local prev = checkpoints[index - 1] or (meta and meta.start and vector3(meta.start.x, meta.start.y, meta.start.z)) or nil
    local chevron = SKGates.chevronForTurn(prev, cp, nextCp)
    local art, r, g, b = SKGates.art(kind, gateKind, stunt, isLast, isLapEnd, chevron)

    local size = Config.CheckpointSize[kind] or Config.CheckpointSize.road
    activeCheckpointHandle = CreateCheckpoint(art, cp.x, cp.y, cp.z, dir.x, dir.y, dir.z, size, r, g, b, 180, 0)

    activeBlip = AddBlipForCoord(cp.x, cp.y, cp.z)
    SetBlipSprite(activeBlip, isLast and 38 or 1)
    SetBlipColour(activeBlip, isLast and 1 or 5)
    SetBlipScale(activeBlip, 1.0)
    -- A GPS line to a gate in the sky is a line to nowhere.
    if kind ~= 'air' then
        SetBlipRoute(activeBlip, true)
        SetBlipRouteColour(activeBlip, 5)
    end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(isLast and 'Finish' or ('Checkpoint ' .. index))
    EndTextCommandSetBlipName(activeBlip)

    if nextCp then
        nextBlip = AddBlipForCoord(nextCp.x, nextCp.y, nextCp.z)
        SetBlipSprite(nextBlip, 1)
        SetBlipColour(nextBlip, 3)
        SetBlipScale(nextBlip, 0.7)
        SetBlipAlpha(nextBlip, 170)
    end
end

-- How close the client must get before it reports a hit. Config.ClientPickupRadius, but never more
-- than three quarters of the gate's own server-side accept radius: Rockstar's offroad gates are 15 m
-- and a custom point can be as tight as 5 m, and a client that reports at 20 m to a 15 m gate is
-- reporting a hit the server will not accept.
function SKCheckpoints.pickupRadius(radii, index)
    local serverRadius = radii and radii[index] or Config.CheckpointRadius
    return math.min(Config.ClientPickupRadius, serverRadius * 0.75)
end

function SKCheckpoints.distanceTo(coords, checkpoints, index)
    local cp = checkpoints[index]
    if not cp then return math.huge end
    return #(coords - cp)
end

-- ── Lap/checkpoint HUD (vice_hud) ────────────────────────────────────────
-- Pushed to vice_hud's own NUI panel instead of drawn with natives here —
-- see exports.vice_hud:SetLapTimer. Guarded so a server without vice_hud
-- installed just doesn't get a lap timer instead of erroring; this was a
-- deliberate, user-approved reversal of this resource's usual "no HUD
-- dependency" rule (see PORTING.md) specifically because getting the
-- reference's rounded plate / pink checkpoint bar / real display font right
-- isn't reachable with native DrawRect/DrawText at all.
function SKPushLapHud(data)
    if GetResourceState('vice_hud') ~= 'started' then return end
    exports.vice_hud:SetLapTimer(data)
end

-- The two cards vice_hud shows around a race: the name of it before the
-- countdown, and the placing over the time at the finish. Nothing without it.
-- SKRaceTitle waits out the card's 1.9 s (it and the countdown share the
-- same part of the screen), so call it from a thread, before the countdown.
function SKRaceTitle(def, kind)
    if GetResourceState('vice_hud') ~= 'started' or not def then return end
    exports.vice_hud:ShowRaceTitle({ series = 'STREET KINGS', name = def.name, type = kind })
    Wait(1900)
end

function SKRaceResult(position, elapsedMs)
    if GetResourceState('vice_hud') ~= 'started' then return end
    exports.vice_hud:ShowRaceResult({ position = position, timeMs = elapsedMs })
end

-- FINAL LAP over the lap just finished, as the last lap of a circuit starts.
-- Called with the progress of the checkpoint just hit; `state` is the run's
-- own table, which keeps the split between calls. Nothing on a route without
-- laps, and nothing but the split without vice_hud.
function SKLapSplit(state, lap, cpInLap, cpPerLap, laps, elapsedMs)
    laps = laps or 1
    if laps < 2 or cpInLap ~= cpPerLap or lap >= laps then return end
    local lapMs = elapsedMs - (state.lapSplitMs or 0)
    state.lapSplitMs = elapsedMs
    if lap + 1 ~= laps or GetResourceState('vice_hud') ~= 'started' then return end
    exports.vice_hud:ShowRaceBanner({ text = 'FINAL LAP', timeMs = lapMs })
end

-- Recovers "which lap, which checkpoint within that lap" from the flattened
-- index SKRouteBuilder.buildCheckpointList produced, rather than tracking
-- either separately — a 'circuit' route repeats def.checkpoints back to back
-- (see route_sh.lua), so dividing the running index back out can never
-- disagree with the checkpoint list actually being driven.
--
-- cpPerLap: #def.checkpoints (the ROUTE DEFINITION, not the flattened list).
-- laps: def.laps for 'circuit' routes; 1 for 'ordered'/'thereandback', which
-- have no lap concept at all.
function SKLapProgress(index, cpPerLap, laps)
    cpPerLap = math.max(1, cpPerLap or 1)
    laps = math.max(1, laps or 1)
    local lap = math.min(laps, math.ceil(index / cpPerLap))
    local cpInLap = ((index - 1) % cpPerLap) + 1
    return lap, cpInLap
end

-- ── Shared race helpers (used by both the SP and MP flows) ──────────────────

-- Vehicle class/model resolved client-side, where these natives actually work,
-- and reported to the server for leaderboard storage (the server cannot read
-- GetVehicleClass / GetDisplayNameFromVehicleModel itself).
function SKVehicleInfo(veh)
    if not veh or veh == 0 then return { class = -1, model = '' } end
    return {
        class = GetVehicleClass(veh),
        model = GetDisplayNameFromVehicleModel(GetEntityModel(veh)),
    }
end

-- Fades out, snaps the player's vehicle to the start line (+ optional lane
-- offset perpendicular to the start heading), then fades back in.
function SKTeleportToStart(veh, start, laneOffset)
    laneOffset = laneOffset or 0.0
    local hRad = math.rad(-(start.w or 0.0))
    local ox = math.sin(hRad + math.pi / 2) * laneOffset
    local oy = math.cos(hRad + math.pi / 2) * laneOffset

    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(10) end

    SetEntityVelocity(veh, 0.0, 0.0, 0.0)
    SetPedCoordsKeepVehicle(cache.ped, start.x + ox, start.y + oy, start.z)
    SetEntityHeading(veh, start.w or 0.0)
    SetVehicleOnGroundProperly(veh)

    DoScreenFadeIn(400)
end

local function drawBigCentered(text, r, g, b)
    SetTextFont(7) SetTextScale(0.0, 3.0)
    SetTextColour(r, g, b, 255) SetTextCentre(true) SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.4)
end

-- Draws a big centred N..1 countdown then GO!. `onGo` fires the instant the
-- count reaches GO (caller unfreezes / begins timing there).
--
-- With vice_hud running the digits are its own (a digit for 0.3 s at each
-- second, then GO for 1.1 s). The timing here does not change, so onGo fires
-- on the same frame either way.
function SKRaceCountdown(seconds, onGo)
    local hud = GetResourceState('vice_hud') == 'started'
    CreateThread(function()
        for i = seconds, 1, -1 do
            if hud then exports.vice_hud:ShowRaceCountdown({ value = i }) end
            local t = GetGameTimer()
            while GetGameTimer() - t < 1000 do
                Wait(0)
                if not hud then drawBigCentered(tostring(i), 255, 200, 0) end
            end
        end
        if onGo then onGo() end
        if hud then
            exports.vice_hud:ShowRaceCountdown({ value = 'go' })
            return
        end
        local t = GetGameTimer()
        while GetGameTimer() - t < 1000 do
            Wait(0)
            drawBigCentered('GO!', 0, 255, 0)
        end
    end)
end
