-- Singleplayer <-> multiplayer chooser + solo time-trial run flow.
--
-- Flow: pick SP -> teleport to the start line -> 3-2-1 countdown with the car
-- frozen -> on GO, tell the server to start (its clock starts here, aligned with
-- the player) and begin local checkpoint tracking. Checkpoint hits are fired
-- optimistically within Config.ClientPickupRadius (a tighter grace zone nested
-- inside the server's Config.CheckpointRadius) and rolled back if the server
-- rejects the run.
--
-- Air and offroad routes (data/rockstar_races.lua) differ in two ways. The race hands you its own
-- vehicle (racevehicle_c.lua), and an air race is judged the way Rockstar's stunt plane races are:
-- each gate is flown through, not touched, and how you fly it is worth seconds (shared/gates_sh.lua).

function SKFormatTime(ms)
    ms = math.max(0, ms or 0)
    local totalSeconds = ms / 1000
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return ('%02d:%05.2f'):format(minutes, seconds)
end

local activeRun = nil -- { routeId, checkpoints, radii, index, startedAt, scheme, laps, cpPerLap, kind, ... }

local MEDAL_LABEL = { gold = 'Gold', silver = 'Silver', bronze = 'Bronze' }

-- ── On-screen gate feedback (air races) ──────────────────────────────────────
-- Rockstar shows what a gate was worth as it happens. Short-lived lines under the HUD.

local feedback = {} -- { text, colour, expires }
local STATUS_TEXT = {
    perfect      = { 'PERFECT', { 114, 204, 114 } },
    pass         = { 'GATE', { 255, 255, 255 } },
    knife_inner  = { 'PERFECT KNIFE EDGE', { 114, 204, 114 } },
    knife_outer  = { 'KNIFE EDGE', { 114, 204, 114 } },
    invert_inner = { 'PERFECT INVERTED', { 93, 182, 229 } },
    invert_outer = { 'INVERTED', { 93, 182, 229 } },
    stunt        = { 'STUNT!', { 255, 215, 0 } },
    stunt_wrong  = { 'WRONG STUNT', { 240, 150, 80 } },
    miss         = { 'MISSED GATE', { 224, 50, 50 } },
}

local function pushFeedback(status)
    local info = STATUS_TEXT[status]
    if not info then return end
    local secs = SKGates.seconds(status)
    local text = info[1]
    if secs > 0 then text = ('%s  -%.1fs'):format(text, secs)
    elseif secs < 0 then text = ('%s  +%.1fs'):format(text, -secs) end
    feedback[#feedback + 1] = { text = text, colour = info[2], expires = GetGameTimer() + 2500 }
    if #feedback > 4 then table.remove(feedback, 1) end
end

CreateThread(function()
    while true do
        if #feedback == 0 then
            Wait(50) -- short: a gate result should be on screen within a few frames of the gate
        else
            Wait(0)
            local now = GetGameTimer()
            for i = #feedback, 1, -1 do
                if feedback[i].expires < now then table.remove(feedback, i) end
            end
            for i, f in ipairs(feedback) do
                SKHud.Text(f.text, 0.5, 0.72 + (i - 1) * 0.034, 0.5, f.colour, true)
            end
        end
    end
end)

-- ── Chooser ──────────────────────────────────────────────────────────────────

local function describe(def)
    local parts = { ('%d gates'):format(#def.checkpoints) }
    if def.kind == 'air' then parts[#parts + 1] = 'stunt plane, handed to you' end
    if def.kind == 'offroad' then parts[#parts + 1] = 'offroad' end
    if def.medals then
        parts[#parts + 1] = ('Gold %s / Silver %s / Bronze %s'):format(
            SKFormatTime(def.medals.gold * 1000), SKFormatTime(def.medals.silver * 1000), SKFormatTime(def.medals.bronze * 1000))
    end
    return table.concat(parts, '  |  ')
end

-- Called by client/discovery.lua when a player interacts with a race blip.
function OpenRaceChooser(routeId)
    local routes = lib.callback.await('sk_streetkings:racing:getRoutes', false) or {}
    local def = routes[routeId]
    if not def then return end

    local vehicleLabel = def.vehicle and Config.RaceVehicles[def.vehicle.model] and Config.RaceVehicles[def.vehicle.model].label or nil
    local options = {}

    if def.kind == 'air' then
        options[#options + 1] = {
            title = 'Time Trial',
            description = 'Fly the gates. Clean flying and stunts take seconds off your clock; missed gates add them. '
                .. describe(def),
            icon = 'plane',
            onSelect = function() StartSingleplayerRun(routeId, def, false) end,
        }
    elseif def.kind == 'offroad' and vehicleLabel then
        options[#options + 1] = {
            title = 'Time Trial — ' .. vehicleLabel,
            description = 'Race the clock on the race vehicle, provided. ' .. describe(def),
            icon = 'motorcycle',
            onSelect = function() StartSingleplayerRun(routeId, def, false) end,
        }
        options[#options + 1] = {
            title = 'Time Trial — My Vehicle',
            description = 'Race the clock in your own vehicle. Rewards scale with your finish time and rank.',
            icon = 'car',
            onSelect = function() StartSingleplayerRun(routeId, def, true) end,
        }
    else
        options[#options + 1] = {
            title = 'Singleplayer Time Trial',
            description = 'Race the clock solo. Rewards scale with your finish time and rank.',
            onSelect = function() StartSingleplayerRun(routeId, def, true) end,
        }
    end

    if not def.solo then
        options[#options + 1] = {
            title = 'Multiplayer Race',
            description = 'Host or join a lobby with other players.',
            onSelect = function() OpenMultiplayerSetup(routeId, def) end,
        }
    end

    lib.registerContext({ id = 'sk_racing_chooser', title = def.name, options = options })
    lib.showContext('sk_racing_chooser')
end

-- ── Run state ────────────────────────────────────────────────────────────────

local function endRun()
    activeRun = nil
    feedback = {}
    SKCheckpoints.clear()
    SKC.SetGameState(GameState.FREEROAM)
    SKPushLapHud({ show = false })
    SKRaceVehicle.giveBack()
end

local function abortLocalRun(reason)
    if not activeRun then return end
    endRun()
    if reason then
        lib.notify({ title = 'Racing', description = reason, type = 'error' })
    end
end

-- The clock the player should see: raw time with the gate bonuses/penalties so far applied.
local function shownElapsed(run)
    return GetGameTimer() - run.startedAt - math.floor((run.netSeconds or 0.0) * 1000.0)
end

local function stuntAt(run, index)
    local src = run.sourceIndex[index]
    return (src and src > 0 and run.gateStunts and run.gateStunts[src]) or false
end

local REASONS = {
    not_in_vehicle = 'You need to be in a vehicle.',
    too_far_from_start = 'Get closer to the start line.',
    too_far_from_entry = 'Get closer to the start line.',
    no_vehicle_for_route = 'This race has no vehicle to hand out.',
    vehicle_timeout = 'The race vehicle did not arrive. Try again.',
    unknown_route = 'That race no longer exists.',
}

function StartSingleplayerRun(routeId, def, useOwnVehicle)
    if activeRun then
        lib.notify({ title = 'Racing', description = 'You are already racing.', type = 'error' })
        return
    end

    local handOut = not useOwnVehicle and SKRaceVehicle.handsOut(def)

    if not handOut then
        local veh = GetVehiclePedIsIn(cache.ped, false)
        if veh == 0 then
            lib.notify({ title = 'Racing', description = 'You need to be in a vehicle to race.', type = 'error' })
            return
        end
        local startCoords = vec3(def.start.x, def.start.y, def.start.z)
        if #(GetEntityCoords(cache.ped) - startCoords) > (def.startRadius or Config.StartRadius) then
            lib.notify({ title = 'Racing', description = 'Get closer to the start line.', type = 'error' })
            return
        end
    end

    CreateThread(function()
        local veh, launchInfo
        if handOut then
            DoScreenFadeOut(400)
            while not IsScreenFadedOut() do Wait(10) end

            local reason
            veh, reason, launchInfo = SKRaceVehicle.acquire(routeId, def, 0.0)
            if not veh then
                DoScreenFadeIn(400)
                lib.notify({ title = 'Racing', description = REASONS[reason] or ('Could not start: ' .. tostring(reason)), type = 'error' })
                return
            end
            -- Already on the start line, in the air for a plane: nothing to teleport.
            SetEntityHeading(veh, def.start.w or 0.0)
            DoScreenFadeIn(400)
        else
            veh = GetVehiclePedIsIn(cache.ped, false)
            SKTeleportToStart(veh, def.start, 0.0)
            FreezeEntityPosition(veh, true)
        end

        SKRaceTitle(def, 'TIME TRIAL')
        SKRaceCountdown(3, function()
            if handOut then
                SKRaceVehicle.launch(veh, launchInfo)
            else
                FreezeEntityPosition(veh, false)
            end
            -- Server clock starts on this event, aligned with the player's GO.
            TriggerServerEvent('sk_streetkings:racing:sp:start', routeId, SKVehicleInfo(veh))
            -- Freeroam systems (speed cameras, stunt jumps, police) stand down
            -- for the duration of a scored run.
            SKC.SetGameState(GameState.EVENT)
            -- 'circuit' is the only scheme with a real lap count; 'ordered'
            -- and 'thereandback' are single-pass, so they report as 1/1
            -- rather than the lap badge showing a lap count that means
            -- nothing for that route type.
            local laps = (def.scheme == 'circuit') and (def.laps or 1) or 1
            local sourceIndex = SKRouteBuilder.buildSourceIndex(def)
            activeRun = {
                routeId     = routeId,
                kind        = def.kind or 'road',
                checkpoints = SKRouteBuilder.buildCheckpointList(def),
                radii       = SKRouteBuilder.buildCheckpointRadii(def),
                sourceIndex = sourceIndex,
                gateStunts  = def.gateStunts,
                meta        = SKCheckpoints.meta(def, sourceIndex),
                netSeconds  = 0.0,
                index       = 1,
                startedAt   = GetGameTimer(),
                scheme      = def.scheme,
                laps        = laps,
                -- +1: buildCheckpointList appends a start/finish checkpoint at
                -- the end of every circuit lap (route_sh.lua), so the flattened
                -- list has one more entry per lap than def.checkpoints itself.
                cpPerLap    = (def.scheme == 'circuit') and (#def.checkpoints + 1) or #def.checkpoints,
            }
            SKCheckpoints.show(activeRun.checkpoints, 1, #activeRun.checkpoints == 1, activeRun.meta)

            -- Nothing completed yet — cp starts at 0, not SKLapProgress(1,
            -- ...)'s "heading to checkpoint 1" reading, which is a different
            -- question (see the completed-checkpoint push in the proximity
            -- loop below for why that function is called on the HIT index).
            SKPushLapHud({
                lap = 1, laps = activeRun.laps,
                cp = 0, cpTotal = activeRun.cpPerLap,
                elapsedMs = 0, running = true,
            })
        end)
    end)
end

RegisterNetEvent('sk_streetkings:racing:sp:startDenied', function(reason)
    abortLocalRun('Could not start: ' .. reason)
end)

RegisterNetEvent('sk_streetkings:racing:sp:runAborted', function(reason)
    abortLocalRun('Run cancelled: ' .. reason)
end)

-- What the server actually scored for a gate: the number on screen follows this, not the local guess.
RegisterNetEvent('sk_streetkings:racing:sp:gateScored', function(_, status, netSeconds)
    if not activeRun then return end
    activeRun.netSeconds = netSeconds or activeRun.netSeconds
    if activeRun.kind == 'air' and activeRun.lastLocalStatus ~= status then
        pushFeedback(status) -- the server disagreed with the client's read of the gate
    end
end)

RegisterNetEvent('sk_streetkings:racing:sp:finished', function(result)
    endRun()
    SKRaceResult(result.rank, result.elapsedMs)

    local lines = {
        ('Time: %s'):format(SKFormatTime(result.elapsedMs)),
    }
    if result.bonusSeconds and result.bonusSeconds ~= 0 then
        lines[#lines + 1] = ('Clock %s, %s%.1fs from gates'):format(
            SKFormatTime(result.rawMs), result.bonusSeconds > 0 and '-' or '+', math.abs(result.bonusSeconds))
    end
    if result.medal then lines[#lines + 1] = ('%s medal!'):format(MEDAL_LABEL[result.medal]) end
    lines[#lines + 1] = ('Reward: $%d  (+%d XP)'):format(result.cash, result.xp)
    if result.rank then lines[#lines + 1] = ('Rank #%d'):format(result.rank) end
    if result.goalMet and not result.medal then lines[#lines + 1] = 'Goal time beaten!' end
    if result.leveledUp then lines[#lines + 1] = ('Race level up! Now level %d'):format(result.level) end

    lib.notify({ title = 'Race Finished', description = table.concat(lines, '\n'), type = 'success', duration = 9000 })
end)

RegisterCommand('cancelrace', function()
    if not activeRun then return end
    TriggerServerEvent('sk_streetkings:racing:sp:abort')
    abortLocalRun('Run cancelled.')
end, false)

-- ── Checkpoint tracking ──────────────────────────────────────────────────────

-- Reports gate `index` to the server and moves the run on to the next one.
local function completeGate(run, status)
    TriggerServerEvent('sk_streetkings:racing:sp:hitCheckpoint', run.index, status)

    if status then
        run.netSeconds = (run.netSeconds or 0.0) + SKGates.seconds(status)
        run.lastLocalStatus = status
        pushFeedback(status)
    end

    -- Progress for the checkpoint JUST completed, not the next
    -- target — SKLapProgress on run.index (pre-increment)
    -- reports "how far into its lap was the checkpoint we just
    -- hit", which is exactly the pip count that should light up.
    local lap, cpInLap = SKLapProgress(run.index, run.cpPerLap, run.laps)
    local finished = run.index >= #run.checkpoints

    run.index = run.index + 1
    if run.index > #run.checkpoints then
        SKCheckpoints.clear()
    else
        SKCheckpoints.show(run.checkpoints, run.index, run.index == #run.checkpoints, run.meta)
    end

    -- The clock stops the instant the last checkpoint is hit —
    -- sp:finished (server-confirmed) hides the panel outright a
    -- moment later; this just freezes the display in the
    -- meantime instead of ticking through the confirmation
    -- window the way the old per-frame native draw did.
    SKPushLapHud({
        lap = lap, laps = run.laps,
        cp = cpInLap, cpTotal = run.cpPerLap,
        elapsedMs = shownElapsed(run),
        running = not finished,
    })
end

-- Air gates are flown through, not touched: judged against the plane's own frame every frame.
local function airGateStatus(run)
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if veh == 0 then return nil end

    -- The plane's own axes as world vectors. GetEntityMatrix returns the same four vectors, but its
    -- documented order and the order it really comes back in are not the same in every write-up, and
    -- getting it wrong would judge every gate against the wrong axis; an offset from the entity is unambiguous.
    local pos = GetEntityCoords(veh)
    local r = GetOffsetFromEntityInWorldCoords(veh, 1.0, 0.0, 0.0) - pos
    local fwd = GetOffsetFromEntityInWorldCoords(veh, 0.0, 1.0, 0.0) - pos
    local up = GetOffsetFromEntityInWorldCoords(veh, 0.0, 0.0, 1.0) - pos
    local gate = run.checkpoints[run.index]
    local status = SKGates.judge(gate, stuntAt(run, run.index), { pos = pos, fwd = fwd, right = r, up = up })
    if status then return status end

    if SKGates.isMiss(pos, gate, run.checkpoints[run.index + 1], run.radii[run.index]) then
        return 'miss'
    end
    return nil
end

-- Checkpoint proximity loop (sleeps while idle)
CreateThread(function()
    while true do
        local sleep = 1000
        if activeRun then
            sleep = 0
            if activeRun.index > #activeRun.checkpoints then
                -- Every gate is flown; waiting for the server to confirm the finish.
            elseif activeRun.kind == 'air' then
                local status = airGateStatus(activeRun)
                if status then completeGate(activeRun, status) end
            else
                local dist = SKCheckpoints.distanceTo(GetEntityCoords(cache.ped), activeRun.checkpoints, activeRun.index)
                if dist < SKCheckpoints.pickupRadius(activeRun.radii, activeRun.index) then
                    completeGate(activeRun, nil)
                end
            end
        end
        Wait(sleep)
    end
end)
