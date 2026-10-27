-- Checkpoint rendering shared by the singleplayer and multiplayer race flows.
--
-- With vice_hud running, a road or offroad checkpoint is drawn the way the
-- GTA VI race footage draws one: a light pillar standing on the track with a
-- dot and the distance over it, a chequered tile and coloured smoke at the
-- finish, all in the character's HUD accent (exports.vice_hud:SetRaceMarker).
-- Air gates keep Rockstar's rings, since a stunt-plane gate is flown THROUGH
-- and the ring is the gate; they get the icon and distance over them too.
-- Without vice_hud, every gate is Rockstar's CreateCheckpoint art, as before.

SKCheckpoints = {}

local activeCheckpointHandle = nil
local activeBlip = nil
local nextBlip = nil
local markerUp = false

local function viceHud() return GetResourceState('vice_hud') == 'started' end

-- The character's HUD accent (pink / teal), or Rockstar's race yellow without vice_hud.
local function accent()
    if viceHud() then
        local ok, a = pcall(function() return exports.vice_hud:GetAccentColour() end)
        if ok and type(a) == 'table' and a.r then return a end
    end
    return { r = 254, g = 207, b = 12 }
end

-- SET_BLIP_COLOUR takes an RGBA colour as one int (0xRRGGBBAA), not only a palette index. Signed:
-- the native's int is 32-bit.
local function rgbaInt(c, alpha)
    local v = (math.floor(c.r) << 24) | (math.floor(c.g) << 16) | (math.floor(c.b) << 8) | (alpha or 255)
    if v >= 0x80000000 then v = v - 0x100000000 end
    return v
end

-- The GPS line. A custom RGBA colour is documented for a blip but not for its route, so the line
-- takes the nearest stock colour to the accent unless Config.RaceBlips.exactRoute says to try it.
local function routeColour(c)
    local cfg = Config.RaceBlips or {}
    if c.key and cfg.exactRoute then return rgbaInt(c) end
    return (c.key and cfg.routeColour and cfg.routeColour[c.key]) or cfg.defaultRouteColour or 5
end

-- GTA heading (degrees) of travel from a to b.
local function headingOf(a, b)
    return math.deg(math.atan(-(b.x - a.x), b.y - a.y)) % 360.0
end

function SKCheckpoints.clear()
    if activeCheckpointHandle then
        DeleteCheckpoint(activeCheckpointHandle)
        activeCheckpointHandle = nil
    end
    if activeBlip and DoesBlipExist(activeBlip) then RemoveBlip(activeBlip) end
    if nextBlip and DoesBlipExist(nextBlip) then RemoveBlip(nextBlip) end
    activeBlip, nextBlip = nil, nil
    if markerUp then
        markerUp = false
        if viceHud() then exports.vice_hud:ClearRaceMarker() end
    end
end

-- A checkpoint was reached: Rockstar's race checkpoint sound (net_races.sch, Country_Race.sc).
function SKCheckpoints.passed()
    PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', true)
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

    local hud = viceHud()
    if kind == 'air' or not hud then
        local size = Config.CheckpointSize[kind] or Config.CheckpointSize.road
        activeCheckpointHandle = CreateCheckpoint(art, cp.x, cp.y, cp.z, dir.x, dir.y, dir.z, size, r, g, b, 180, 0)
    end

    if hud then
        -- Which way the road runs through the finish lays its smoke across it: the way the cars
        -- come in, or for a circuit's start/finish line the way the grid faces.
        local heading
        if isLast or isLapEnd then
            if src == 0 and meta and meta.start and meta.start.w then
                heading = meta.start.w + 0.0
            elseif prev then
                heading = headingOf(prev, cp)
            end
        end
        exports.vice_hud:SetRaceMarker({
            coords = vector3(cp.x, cp.y, cp.z),
            kind = isLast and 'finish' or 'checkpoint',
            heading = heading,
            -- an air gate is a ring in the sky: no pillar, no smoke, no settling onto the ground
            pillar = kind ~= 'air', smoke = kind ~= 'air', snap = kind ~= 'air',
            iconHeight = kind == 'air' and 14.0 or nil,
        })
        markerUp = true
    end

    -- The minimap: the next checkpoint as an accent dot (the finish as the chequered flag), the GPS
    -- line to it, and the one after as a smaller, fainter dot.
    local c = accent()
    activeBlip = AddBlipForCoord(cp.x, cp.y, cp.z)
    SetBlipSprite(activeBlip, isLast and 38 or 1)
    SetBlipColour(activeBlip, rgbaInt(c))
    SetBlipScale(activeBlip, isLast and 1.0 or 0.9)
    -- A GPS line to a gate in the sky is a line to nowhere.
    if kind ~= 'air' then
        SetBlipRoute(activeBlip, true)
        SetBlipRouteColour(activeBlip, routeColour(c))
    end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(isLast and 'Finish' or ('Checkpoint ' .. index))
    EndTextCommandSetBlipName(activeBlip)

    if nextCp then
        nextBlip = AddBlipForCoord(nextCp.x, nextCp.y, nextCp.z)
        SetBlipSprite(nextBlip, 1)
        SetBlipColour(nextBlip, rgbaInt(c))
        SetBlipScale(nextBlip, 0.6)
        SetBlipAlpha(nextBlip, 150)
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

-- The objective line at GO, the way the reference opens its race with one ("Beat a member of
-- Billy's crew"): a lobby race names the field, a time trial the time to beat. Braces are the
-- word vice_hud draws in the accent.
function SKRaceObjective(def, multiplayer)
    if not viceHud() or not def then return end
    local function clock(sec)
        sec = math.floor(sec + 0.5)
        return ('%d:%02d'):format(sec // 60, sec % 60)
    end
    local text
    if multiplayer then
        text = 'Beat the other {racers}'
    elseif def.medals then
        text = ('Beat {%s} for gold'):format(clock(def.medals.gold))
    elseif def.goalTime then
        text = ('Beat {%s}'):format(clock(def.goalTime))
    else
        text = 'Set your best {time}'
    end
    exports.vice_hud:ShowObjective(text, 6000)
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
