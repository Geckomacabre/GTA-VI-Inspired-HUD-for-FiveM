-- Rampage, ported from streetkings modules/events/rampage_c.lua and
-- modules/events/events_rampage_markers_c.lua.
--
-- Drive to a marked start point, take the prompt, then do as much damage as you
-- can before the clock runs out. Hits chain into a combo while they keep coming,
-- and score scales with how fast you were going when you connected.
--
-- Changes from upstream:
--   * The two files are merged. They were split only because the markers half
--     plugged into upstream's daily-events chooser, which is not ported.
--   * The rampage HUD (timer, score, combo) and the results panel were NUI;
--     both are redrawn with SKHud. The start prompt is lib.showTextUI.
--   * Scoring goes to `sk_activity_scores` (activity = 'rampage') instead of
--     the daily-events leaderboard.
--   * `SKC.Wasted()` is dropped — death handling belongs to qbx_core here, so
--     a wasted run just ends with no payout.

if not Config.Modules.rampage then return end

SKRampage = {}

local MPS_TO_MPH = 2.236936

local MIN_SPEED_MPH       = 15.0
local HIT_COOLDOWN_MS     = 8000 -- per target, so one wreck can't be farmed
local COMBO_WINDOW_MS     = 3000
local COMBO_MAX           = 8
local CLEANUP_INTERVAL_MS = 2000
local RESULTS_MS          = 8000

local DETECTION_PED = 6.0
local DETECTION_VEH = 8.0
local DETECTION_OBJ = 5.0

local SCORE_PED    = 100
local SCORE_OBJECT = 50

-- Keyed by GetVehicleClass(). Rarer/heavier metal is worth more.
local VEH_CLASS_SCORES = {
    [0]  = 100, [1]  = 125, [2]  = 150, [3]  = 125,
    [4]  = 175, [5]  = 150, [6]  = 200, [7]  = 250,
    [8]  = 75,  [9]  = 125, [10] = 150, [11] = 100,
    [12] = 150, [13] = 50,  [14] = 300, [15] = 200,
    [16] = 75,  [17] = 75,  [18] = 75,  [19] = 100,
    [20] = 100, [21] = 75,  [22] = 200,
}

local MARKER_RADIUS = 5.0

local rampagePoints    = {}
local rampageBlips     = {}
local rampageWaypoints = {}

local runActive     = false
local markersActive = false

-- ── HUD ─────────────────────────────────────────────────────────────────────

local P       = SKHud.Palette
local RUN_HUD = SKHud.Anchor.bottomCentre
local RESULT  = SKHud.Anchor.centreLow

SKHud.register('rampage', function(data)
    local seconds = math.ceil(data.remaining / 1000)

    SKHud.Panel(RUN_HUD.x, RUN_HUD.y, 0.230, 0.082, P.panelDark)

    -- Clock turns red for the last ten seconds.
    local clockColor = seconds <= 10 and P.danger or P.text
    SKHud.Text(('%d:%02d'):format(math.floor(seconds / 60), seconds % 60),
        RUN_HUD.x, RUN_HUD.y - 0.036, 0.42, clockColor, true)
    SKHud.Text(('%d'):format(data.score), RUN_HUD.x, RUN_HUD.y - 0.014, 0.58, P.accent, true)

    if data.combo and data.combo > 1 then
        SKHud.Text(('x%d COMBO'):format(data.combo), RUN_HUD.x, RUN_HUD.y + 0.022, 0.30, P.warning, true)
    end
end)

SKHud.register('rampageresult', function(data)
    SKHud.Panel(RESULT.x, RESULT.y, 0.310, 0.134, P.panelDark)
    SKHud.Text(data.name, RESULT.x, RESULT.y - 0.060, 0.32, P.textDim, true)
    SKHud.Text(('%d'):format(data.score), RESULT.x, RESULT.y - 0.040, 0.80, P.accent, true)
    if data.summary then
        SKHud.Text(data.summary, RESULT.x, RESULT.y + 0.014, 0.30, P.success, true)
    end
    SKHud.Text(('[%s] dismiss'):format(SKInput.getInteractLabel()), RESULT.x, RESULT.y + 0.040, 0.26, P.textDim, true)
end)

-- ── Run ─────────────────────────────────────────────────────────────────────

---@param vehicle integer
---@return boolean
local function isPlayerWasted(vehicle)
    local ped = PlayerPedId()
    return IsEntityDead(ped)
        or IsPedDeadOrDying(ped, true)
        or IsPedFatallyInjured(ped)
        or not DoesEntityExist(vehicle)
        or IsEntityDead(vehicle)
        or not IsVehicleDriveable(vehicle, false)
end

--- Finds the single best thing the player just hit, in priority order:
--- pedestrians, then vehicles, then loose props.
---@param vehicle integer
---@param ped integer
---@param vehCoords vector3
---@param cooldowns table<integer, integer>
---@param now integer
---@return integer points, integer|nil target
local function findHit(vehicle, ped, vehCoords, cooldowns, now)
    for _, targetPed in ipairs(GetGamePool('CPed')) do
        if targetPed ~= ped
            and DoesEntityExist(targetPed)
            and not IsPedAPlayer(targetPed)
            and not cooldowns[targetPed]
            and #(GetEntityCoords(targetPed) - vehCoords) < DETECTION_PED
        then
            cooldowns[targetPed] = now + HIT_COOLDOWN_MS
            return SCORE_PED, targetPed
        end
    end

    for _, targetVeh in ipairs(GetGamePool('CVehicle')) do
        if targetVeh ~= vehicle
            and DoesEntityExist(targetVeh)
            and not cooldowns[targetVeh]
            and #(GetEntityCoords(targetVeh) - vehCoords) < DETECTION_VEH
        then
            cooldowns[targetVeh] = now + HIT_COOLDOWN_MS
            return VEH_CLASS_SCORES[GetVehicleClass(targetVeh)] or 100, targetVeh
        end
    end

    for _, obj in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(obj)
            and IsEntityAnObject(obj)
            and not IsEntityStatic(obj)
            and not cooldowns[obj]
            and #(GetEntityCoords(obj) - vehCoords) < DETECTION_OBJ
        then
            cooldowns[obj] = now + HIT_COOLDOWN_MS
            return SCORE_OBJECT, obj
        end
    end

    return 0, nil
end

---@param def table
---@param vehicle integer
---@param ped integer
function SKRampage.run(def, vehicle, ped)
    local duration = def.duration or Config.Rampage.durationSec

    local score       = 0
    local combo       = 0
    local lastHitTime = 0
    local lastCleanup = 0
    local cooldowns   = {}
    local endTime     = GetGameTimer() + duration * 1000

    SKC.SetGameState(GameState.EVENT)

    while GetGameTimer() < endTime do
        if SKC.GetGameState() ~= GameState.EVENT then break end
        if isPlayerWasted(vehicle) then break end

        local now       = GetGameTimer()
        local remaining = math.max(0, endTime - now)
        local speed     = GetEntitySpeed(vehicle) * MPS_TO_MPH

        if speed >= MIN_SPEED_MPH and HasEntityCollidedWithAnything(vehicle) then
            local pts = findHit(vehicle, ped, GetEntityCoords(vehicle), cooldowns, now)

            if pts > 0 then
                -- Faster impacts and chained hits both multiply.
                pts = math.floor(pts * (1.0 + math.min(1.0, speed / 60.0)))

                combo = (now - lastHitTime) < COMBO_WINDOW_MS and math.min(combo + 1, COMBO_MAX) or 1
                lastHitTime = now

                pts = math.floor(pts * (1.0 + (combo - 1) * 0.15))
                score = score + pts
            end
        end

        -- The combo lapses on its own once the window closes.
        if combo > 0 and (now - lastHitTime) >= COMBO_WINDOW_MS then
            combo = 0
        end

        SKHud.set('rampage', { remaining = remaining, score = score, combo = combo })

        if now - lastCleanup >= CLEANUP_INTERVAL_MS then
            lastCleanup = now
            for entity, expiry in pairs(cooldowns) do
                if now > expiry then cooldowns[entity] = nil end
            end
        end

        Wait(50)
    end

    SKHud.clear('rampage')

    local wasted = isPlayerWasted(vehicle)
    local aborted = SKC.GetGameState() ~= GameState.EVENT

    if aborted then
        runActive = false
        return
    end

    SKC.SetGameState(GameState.FREEROAM)

    if wasted or score <= 0 then
        runActive = false
        if wasted then
            SKNotify({ title = def.name, description = 'Run over — you wrecked it.', type = 'error' })
        end
        return
    end

    local result = lib.callback.await(
        'sk_streetkings:rampage:submit', false,
        def.id, score, SK.GetVehicleModelLabel(vehicle)
    )

    SKHud.set('rampageresult', {
        name    = def.name,
        score   = score,
        summary = result and result.summary or nil,
    })

    local deadline = GetGameTimer() + RESULTS_MS
    while GetGameTimer() < deadline do
        if SKInput.isInteractJustReleased() then break end
        Wait(0)
    end

    SKHud.clear('rampageresult')
    runActive = false
end

---@param rampageId string
local function startRampage(rampageId)
    if runActive then return end

    local def = SKRampages[rampageId]
    if not def then return end

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then
        lib.notify({ title = 'Rampage', description = 'You need to be driving to start a rampage.', type = 'error' })
        return
    end

    runActive = true
    lib.hideTextUI()

    CreateThread(function()
        local ok, err = pcall(SKRampage.run, def, veh, ped)
        if not ok then
            lib.print.error(('rampage %s: %s'):format(rampageId, tostring(err)))
            SKHud.clear('rampage')
            SKHud.clear('rampageresult')
            SKC.SetGameState(GameState.FREEROAM)
            runActive = false
        end
    end)
end

-- ── World markers ───────────────────────────────────────────────────────────

local function clearMarkers()
    for _, p in ipairs(rampagePoints) do p:remove() end
    rampagePoints = {}

    for _, wpId in ipairs(rampageWaypoints) do SKWaypoint.Remove(wpId) end
    rampageWaypoints = {}

    for _, b in ipairs(rampageBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    rampageBlips = {}

    lib.hideTextUI()
end

local function setupMarkers()
    clearMarkers()

    for rampageId, def in pairs(SKRampages) do
        local coords = vector3(def.start.x, def.start.y, def.start.z)

        rampageBlips[#rampageBlips + 1] = SK.CreateBlip(Config.Blips.rampage, coords, def.name)

        rampageWaypoints[#rampageWaypoints + 1] = SKWaypoint.Create({
            coords = coords,
            label  = def.name,
            color  = '#fa5252', -- ox_lib red.6
            size   = 1.4,
        })

        local showing = false

        rampagePoints[#rampagePoints + 1] = lib.points.new({
            coords   = coords,
            distance = MARKER_RADIUS,
            onExit   = function()
                if showing then
                    showing = false
                    lib.hideTextUI()
                end
            end,
            nearby = function()
                if runActive or SKC.GetGameState() ~= GameState.FREEROAM then
                    if showing then
                        showing = false
                        lib.hideTextUI()
                    end
                    return
                end

                if not showing then
                    showing = true
                    lib.showTextUI(
                        ('[%s] %s  —  %ds'):format(
                            SKInput.getInteractLabel(),
                            def.name,
                            def.duration or Config.Rampage.durationSec
                        ),
                        { position = 'left-center' }
                    )
                end

                if SKInput.isInteractJustReleased() then
                    showing = false
                    startRampage(rampageId)
                end
            end,
        })
    end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

CreateThread(function()
    SK.WaitForControl()
    Wait(1500)
    while true do
        -- Markers stay up during a run (the run itself is GameState.EVENT), but
        -- come down inside the car meet and during a race.
        local gs = SKC.GetGameState()
        local shouldShow = gs == GameState.FREEROAM or (runActive and gs == GameState.EVENT)

        if shouldShow and not markersActive then
            markersActive = true
            setupMarkers()
        elseif not shouldShow and markersActive then
            markersActive = false
            clearMarkers()
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then clearMarkers() end
end)
