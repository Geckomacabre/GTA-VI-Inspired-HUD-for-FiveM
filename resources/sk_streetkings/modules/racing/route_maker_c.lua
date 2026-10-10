-- Admin race route placement tool, rewritten on top of SKFreecam
-- (modules/devtools/freecam_c.lua) so an admin can fly around the map and drop
-- checkpoints via camera raycast, the same workflow as /stuntdev, instead of
-- physically driving to every point.
--
-- Saving goes through a lib.callback round trip to admin_s.lua that awaits the
-- database write before reporting success — the old version fired a plain
-- TriggerServerEvent and told the admin "saved" immediately, regardless of
-- whether the insert actually completed.

local CTRL_LMB       = 24  -- place point
local CTRL_BACKSPACE = 177 -- undo last point
local CTRL_DELETE    = 179 -- clear all points
local CTRL_ENTER     = 191 -- save
local CTRL_ESC       = 200 -- close
local CTRL_LIST      = 45  -- R, open the placed-points list
local CTRL_SCROLL_DN = 14  -- shrink the next point's accept radius
local CTRL_SCROLL_UP = 15  -- grow the next point's accept radius
local CTRL_STUNT     = 47  -- G, air races: cycle the next gate's stunt (none / inverted / left / right)
local CTRL_ALT_UP    = 172 -- arrow up,   air races: raise the next gate
local CTRL_ALT_DOWN  = 173 -- arrow down, air races: lower the next gate

local RADIUS_MIN = 5.0
local RADIUS_MAX = 100.0
local RADIUS_STEP = 2.5

local ALT_MIN, ALT_MAX, ALT_STEP = 10.0, 500.0, 5.0
local STUNT_CYCLE = { false, 'inverted', 'left', 'right' }
local STUNT_LABEL = { [false] = 'no stunt', inverted = 'INVERTED stunt', left = 'KNIFE LEFT stunt', right = 'KNIFE RIGHT stunt' }

local buildMode   = false
local checkpoints = {} -- [1] = start {x,y,z,w,radius}, rest = {x,y,z,radius}
local raycastHit  = nil
local nextRadius  = Config.CheckpointRadius -- scroll-adjustable, for the NEXT point placed

local editingId      = nil
local editingName     = nil
local editingScheme   = 'ordered'
local editingLaps     = 1
local editingGoalTime = nil
local editingUnlock   = nil
-- Air / offroad races (data/rockstar_races.lua shows the shape): what kind, the vehicle handed out,
-- gold/silver/bronze, and where on the ground a player walks up to enter an air race.
local editingKind     = 'road'
local editingVehicle  = nil
local editingMedals   = nil
local editingEntry    = nil
local altOffset       = 60.0  -- air races: height above the aimed-at ground for the next gate
local nextStunt       = false -- air races: stunt the next gate asks for

local P = SKHud.Palette

---@param index integer 1-based position the point would occupy
---@return number
local function defaultRadiusFor(index)
    return index == 1 and Config.StartRadius or Config.CheckpointRadius
end

local function resetRadiusForNext()
    nextRadius = defaultRadiusFor(#checkpoints + 1)
end

---@param title string
---@param nType string
local function notify(title, nType)
    SKNotify({ title = title, type = nType, duration = 2500 })
end

local function resetState()
    checkpoints     = {}
    editingId       = nil
    editingName     = nil
    editingScheme   = 'ordered'
    editingLaps     = 1
    editingGoalTime = nil
    editingUnlock   = nil
    editingKind     = 'road'
    editingVehicle  = nil
    editingMedals   = nil
    editingEntry    = nil
    altOffset       = 60.0
    nextStunt       = false
    resetRadiusForNext()
end

-- ── Drawing ─────────────────────────────────────────────────────────────────

local function drawMarkers()
    for i, cp in ipairs(checkpoints) do
        local color = i == 1 and { 0, 255, 100 } or (i == #checkpoints and { 255, 80, 0 } or { 0, 180, 255 })
        local radius = cp.radius or defaultRadiusFor(i)

        if editingKind == 'air' then
            -- A gate in the sky: a sphere the size of Rockstar's perfect ring (radius ~10.5 m), coloured by
            -- its stunt, with a line down to the ground so its height reads.
            local stuntColour = ({ inverted = { 93, 182, 229 }, left = { 114, 204, 114 }, right = { 114, 204, 114 } })[cp.stunt]
            if stuntColour then color = stuntColour end
            DrawMarker(28, cp.x, cp.y, cp.z, 0, 0, 0, 0, 0, 0, 21.0, 21.0, 21.0,
                color[1], color[2], color[3], 110, false, true, 2, false, nil, nil, false)
            local found, gz = GetGroundZFor_3dCoord(cp.x, cp.y, cp.z, false)
            if found then DrawLine(cp.x, cp.y, gz, cp.x, cp.y, cp.z, color[1], color[2], color[3], 120) end
        else
            DrawMarker(1, cp.x, cp.y, cp.z - 1.0, 0, 0, 0, 0, 0, 0, 5.0, 5.0, 2.5,
                color[1], color[2], color[3], 180, false, true, 2, false, nil, nil, false)
        end
        -- Flat ring sized to the point's actual server-side accept radius, so
        -- what you see while placing is what validation_s.lua will enforce.
        DrawMarker(1, cp.x, cp.y, cp.z, 0, 0, 0, 0, 0, 0, radius * 2, radius * 2, 0.5,
            color[1], color[2], color[3], 35, false, true, 2, false, nil, nil, false)

        local onScreen, sx, sy = World3dToScreen2d(cp.x, cp.y, cp.z + 2.5)
        if onScreen then
            local tag = i == 1 and 'START' or (i == #checkpoints and 'LAST' or tostring(i))
            if cp.stunt then tag = tag .. ' ' .. STUNT_LABEL[cp.stunt]:upper() end
            DrawRect(sx, sy, 0.02 + #tag * 0.007, 0.025, 0, 0, 0, 160)
            SKHud.Text(tag, sx, sy - 0.01, 0.3, { 255, 255, 255, 255 }, true)
        end

        if i > 1 then
            local prev = checkpoints[i - 1]
            DrawLine(prev.x, prev.y, prev.z + 0.3, cp.x, cp.y, cp.z + 0.3, 255, 210, 0, 200)
        end
    end
end

local function drawPreview()
    if not raycastHit then return end
    if #checkpoints > 0 then
        local last = checkpoints[#checkpoints]
        DrawLine(last.x, last.y, last.z + 0.3, raycastHit.x, raycastHit.y, raycastHit.z + 0.3, 150, 150, 150, 150)
    end
    if editingKind == 'air' then
        local z = raycastHit.z + altOffset
        DrawMarker(28, raycastHit.x, raycastHit.y, z, 0, 0, 0, 0, 0, 0, 21.0, 21.0, 21.0,
            255, 255, 0, 70, false, true, 2, false, nil, nil, false)
        DrawLine(raycastHit.x, raycastHit.y, raycastHit.z, raycastHit.x, raycastHit.y, z, 255, 255, 0, 120)
        return
    end
    DrawMarker(1, raycastHit.x, raycastHit.y, raycastHit.z - 1.0, 0, 0, 0, 0, 0, 0, 3.0, 3.0, 1.5,
        255, 255, 0, 120, false, true, 2, false, nil, nil, false)
    DrawMarker(1, raycastHit.x, raycastHit.y, raycastHit.z, 0, 0, 0, 0, 0, 0, nextRadius * 2, nextRadius * 2, 0.5,
        255, 255, 0, 40, false, true, 2, false, nil, nil, false)
end

local function drawStatus()
    SKHud.Panel(0.5, 0.070, 0.560, 0.078, P.panelDark)
    SKHud.Text(editingName and ('Editing: ' .. editingName) or 'New Race Route',
        0.5, 0.044, 0.36, P.accent, true)
    SKHud.Text(('%d point(s) placed — %s race'):format(#checkpoints, editingKind),
        0.5, 0.064, 0.28, P.text, true)
    if editingKind == 'air' then
        SKHud.Text(('Next gate: %.0fm up, %s   (Up/Down height, G stunt)'):format(altOffset, STUNT_LABEL[nextStunt]),
            0.5, 0.084, 0.26, P.textDim, true)
    else
        SKHud.Text(('Next radius: %.0fm (scroll to adjust)'):format(nextRadius),
            0.5, 0.084, 0.26, P.textDim, true)
    end

    SKHud.Panel(0.5, 0.958, 0.860, 0.048, P.panelDark)
    SKHud.Text(editingKind == 'air'
        and 'LMB place   Up/Down height   G stunt   Scroll radius   R list   Backspace undo   Enter save   Esc close'
        or 'LMB place   Scroll radius   R points list   Backspace undo   Delete clear   Enter save   Esc close',
        0.5, 0.948, 0.26, P.textDim, true)
end

-- ── Input ───────────────────────────────────────────────────────────────────

---@return { x: number, y: number, z: number, w: number, radius: number }
local function toVec4Point(pos, heading, radius)
    return { x = pos.x, y = pos.y, z = pos.z, w = heading or 0.0, radius = radius }
end

---@return { x: number, y: number, z: number, radius: number, stunt: string|false|nil }
local function toVec3Point(pos, radius, stunt)
    return { x = pos.x, y = pos.y, z = pos.z, radius = radius, stunt = stunt or nil }
end

local function placePoint()
    if not raycastHit then
        notify('Aim at the ground first', 'error')
        return
    end

    -- An air race's gates hang in the sky: the ground you aim at plus the chosen height.
    local pos = raycastHit
    if editingKind == 'air' then pos = vector3(raycastHit.x, raycastHit.y, raycastHit.z + altOffset) end

    if #checkpoints == 0 then
        checkpoints[1] = toVec4Point(pos, SKFreecam.getHeading(), nextRadius)
    else
        checkpoints[#checkpoints + 1] = toVec3Point(pos, nextRadius, editingKind == 'air' and nextStunt or nil)
    end
    resetRadiusForNext()
    PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', true)
end

local function undoLast()
    if #checkpoints == 0 then
        notify('Nothing to undo', 'warning')
        return
    end
    table.remove(checkpoints)
    resetRadiusForNext()
    PlaySoundFrontend(-1, 'CANCEL', 'HUD_FREEMODE_SOUNDSET', true)
end

local function clearAll()
    if #checkpoints == 0 then return end
    checkpoints = {}
    resetRadiusForNext()
    notify('All points cleared', 'warning')
end

-- ── Points list (edit/delete/recentre any placed point, not just the last) ──

local function openPointActions(i)
    local cp = checkpoints[i]
    if not cp then return end
    local isStart = i == 1
    local radius = cp.radius or defaultRadiusFor(i)

    lib.registerContext({
        id    = 'sk_racemaker_point_actions',
        title = isStart and 'Start Point' or ('Checkpoint ' .. (i - 1)),
        menu  = 'sk_racemaker_points',
        options = {
            {
                title       = ('Radius: %.0fm'):format(radius),
                description = 'Set a custom accept radius for this point',
                icon        = 'circle-notch',
                onSelect    = function()
                    SKFreecam.setPaused(true)
                    local input = lib.inputDialog('Checkpoint Radius', {
                        { type = 'number', label = 'Radius (metres)', default = radius, min = RADIUS_MIN, max = RADIUS_MAX },
                    })
                    SKFreecam.setPaused(false)
                    if input and input[1] then
                        checkpoints[i].radius = math.max(RADIUS_MIN, math.min(RADIUS_MAX, tonumber(input[1]) or radius))
                        notify('Radius updated', 'success')
                    end
                    openPointActions(i)
                end,
            },
            {
                title       = ('Stunt: %s'):format(STUNT_LABEL[cp.stunt or false]),
                description = 'What this gate asks the pilot to do: inverted, or a knife edge left or right',
                icon        = 'rotate',
                disabled    = editingKind ~= 'air' or isStart,
                onSelect    = function()
                    for n, v in ipairs(STUNT_CYCLE) do
                        if v == (cp.stunt or false) then
                            checkpoints[i].stunt = STUNT_CYCLE[n % #STUNT_CYCLE + 1] or nil
                            break
                        end
                    end
                    openPointActions(i)
                end,
            },
            {
                title    = 'Fly camera here',
                icon     = 'video',
                onSelect = function()
                    SKFreecam.setPosition(vector3(cp.x, cp.y, cp.z))
                end,
            },
            {
                title    = 'Delete point',
                icon     = 'trash',
                onSelect = function()
                    table.remove(checkpoints, i)
                    resetRadiusForNext()
                    notify(('Deleted %s'):format(isStart and 'the start point' or ('point ' .. (i - 1))), 'warning')
                end,
            },
        },
        onExit = function() SKFreecam.setPaused(false) end,
    })
    lib.showContext('sk_racemaker_point_actions')
end

local function openPointsList()
    if #checkpoints == 0 then
        notify('No points placed yet', 'warning')
        return
    end

    local options = {}
    for i, cp in ipairs(checkpoints) do
        local tag = i == 1 and 'START' or ('Point ' .. (i - 1))
        options[#options + 1] = {
            title       = tag,
            description = ('%.1f, %.1f, %.1f — radius %.0fm'):format(cp.x, cp.y, cp.z, cp.radius or defaultRadiusFor(i)),
            onSelect    = function() openPointActions(i) end,
        }
    end

    lib.registerContext({
        id      = 'sk_racemaker_points',
        title   = 'Placed Points',
        options = options,
        onExit  = function() SKFreecam.setPaused(false) end,
    })
    SKFreecam.setPaused(true)
    lib.showContext('sk_racemaker_points')
end

-- ── Save ────────────────────────────────────────────────────────────────────

local function saveRoute()
    if #checkpoints < 2 then
        notify('Place a start point and at least one checkpoint', 'error')
        return
    end

    local isAir, isOffroad = editingKind == 'air', editingKind == 'offroad'

    local vehicleOptions = {}
    if isAir or isOffroad then
        for model, info in pairs(Config.RaceVehicles) do
            if info.kind == editingKind then vehicleOptions[#vehicleOptions + 1] = { value = model, label = info.label } end
        end
        table.sort(vehicleOptions, function(a, b) return a.label < b.label end)
    end

    local fields = {
        { type = 'input', label = 'Route Name', default = editingName or '', placeholder = 'Elysian Sprint', required = true },
    }
    if isAir then
        -- Air races are point-to-point: the plane has to be moving, and a lap would end on the start line.
        fields[#fields + 1] = { type = 'number', label = 'Gold time in seconds', default = editingMedals and editingMedals.gold or 70, min = 1 }
        fields[#fields + 1] = { type = 'number', label = 'Silver time in seconds', default = editingMedals and editingMedals.silver or 100, min = 1 }
        fields[#fields + 1] = { type = 'number', label = 'Bronze time in seconds', default = editingMedals and editingMedals.bronze or 130, min = 1 }
        fields[#fields + 1] = { type = 'select', label = 'Plane', default = editingVehicle or vehicleOptions[1].value, options = vehicleOptions }
        fields[#fields + 1] = { type = 'checkbox', label = 'Entry is where I am standing right now', checked = editingEntry == nil }
    else
        fields[#fields + 1] = {
            type = 'select', label = 'Scheme', default = editingScheme,
            options = {
                { value = 'ordered', label = 'Sprint (point to point)' },
                { value = 'circuit', label = 'Circuit (laps back to start)' },
                { value = 'thereandback', label = 'There and Back' },
            },
        }
        fields[#fields + 1] = { type = 'number', label = 'Laps (circuit only)', default = editingLaps, min = Config.LapsMin, max = Config.LapsMax }
        fields[#fields + 1] = { type = 'number', label = 'Goal Time in seconds (optional)', default = editingGoalTime, min = 0 }
        fields[#fields + 1] = {
            type = 'number', label = 'Required Barn Finds (0 = none)',
            default = editingUnlock and editingUnlock.barnFindsCompleted or 0, min = 0,
        }
        if isOffroad then
            fields[#fields + 1] = {
                type = 'select', label = 'Race vehicle (players may use their own too)', default = editingVehicle or vehicleOptions[1].value,
                options = vehicleOptions,
            }
        end
    end

    SKFreecam.setPaused(true)
    local input = lib.inputDialog('Save ' .. (isAir and 'Air Race' or (isOffroad and 'Offroad Race' or 'Race Route')), fields)
    SKFreecam.setPaused(false)

    if not input or not input[1] or input[1] == '' then
        notify('Save cancelled', 'warning')
        return
    end

    local startCoords = checkpoints[1]
    local cps, gateStunts = {}, {}
    for i = 2, #checkpoints do
        cps[#cps + 1] = checkpoints[i]
        gateStunts[#gateStunts + 1] = checkpoints[i].stunt or false
    end

    local payload = {
        editId      = editingId,
        name        = input[1],
        start       = startCoords,
        checkpoints = cps,
        kind        = editingKind,
    }

    if isAir then
        payload.scheme = 'ordered'
        payload.medals = { gold = tonumber(input[2]), silver = tonumber(input[3]), bronze = tonumber(input[4]) }
        payload.vehicle = { model = input[5] }
        payload.gateStunts = gateStunts
        local at = (input[6] or editingEntry == nil) and GetEntityCoords(PlayerPedId()) or nil
        payload.entry = at and { x = at.x, y = at.y, z = at.z } or editingEntry
    else
        payload.scheme = input[2] or 'ordered'
        payload.laps = tonumber(input[3]) or 1
        payload.goalTime = tonumber(input[4])
        local requiredBarnFinds = tonumber(input[5]) or 0
        payload.unlockRequirement = requiredBarnFinds > 0 and { barnFindsCompleted = requiredBarnFinds } or nil
        if isOffroad then payload.vehicle = { model = input[6] } end
    end

    local result = lib.callback.await('sk_streetkings:racing:admin:saveRoute', false, payload)

    if result and result.ok then
        notify(('"%s" saved'):format(input[1]), 'success')
        buildMode = false
    else
        notify(('Save failed: %s'):format(result and result.reason or 'unknown'), 'error')
    end
end

-- ── Build loop ──────────────────────────────────────────────────────────────

local function startBuildLoop()
    CreateThread(function()
        Cinematic = true
        SKFreecam.start()

        CreateThread(function()
            while buildMode do
                raycastHit = SKFreecam.raycast()
                Wait(16)
            end
        end)

        while buildMode do
            Wait(0)
            if not SKFreecam.isEnabled() then break end

            drawMarkers()
            drawPreview()
            drawStatus()

            if IsDisabledControlJustPressed(0, CTRL_SCROLL_DN) then
                nextRadius = math.max(RADIUS_MIN, nextRadius - RADIUS_STEP)
            elseif IsDisabledControlJustPressed(0, CTRL_SCROLL_UP) then
                nextRadius = math.min(RADIUS_MAX, nextRadius + RADIUS_STEP)
            end

            if editingKind == 'air' then
                if IsDisabledControlJustPressed(0, CTRL_ALT_UP) then
                    altOffset = math.min(ALT_MAX, altOffset + ALT_STEP)
                elseif IsDisabledControlJustPressed(0, CTRL_ALT_DOWN) then
                    altOffset = math.max(ALT_MIN, altOffset - ALT_STEP)
                end
                if IsDisabledControlJustPressed(0, CTRL_STUNT) then
                    for n, v in ipairs(STUNT_CYCLE) do
                        if v == nextStunt then nextStunt = STUNT_CYCLE[n % #STUNT_CYCLE + 1]; break end
                    end
                end
            end

            if IsDisabledControlJustPressed(0, CTRL_LMB) then
                placePoint()
            end

            if IsDisabledControlJustPressed(0, CTRL_BACKSPACE) then
                undoLast()
            end

            if IsDisabledControlJustPressed(0, CTRL_DELETE) then
                clearAll()
            end

            if IsDisabledControlJustPressed(0, CTRL_LIST) then
                CreateThread(openPointsList)
            end

            if IsDisabledControlJustPressed(0, CTRL_ENTER) then
                CreateThread(saveRoute)
            end

            if IsDisabledControlJustPressed(0, CTRL_ESC) then
                buildMode = false
                notify('Race Maker closed', 'warning')
                break
            end
        end

        SKFreecam.stop()
        Cinematic = false
        raycastHit = nil
        resetState()
        buildMode = false
    end)
end

-- ── Editing / deleting an existing route ────────────────────────────────────

---@return { id: string, def: table, dist: number }|nil
local function findNearestCustomRoute()
    local routes = lib.callback.await('sk_streetkings:racing:getRoutes', false) or {}
    local myPos = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, 300.0

    for id, def in pairs(routes) do
        if def.custom and def.start then
            local s = def.start
            local d = #(myPos - vector3(s.x, s.y, s.z))
            if d < bestDist then
                bestDist = d
                best = { id = id, def = def, dist = d }
            end
        end
    end

    return best
end

local function loadRouteForEdit(def)
    resetState()
    checkpoints[1] = toVec4Point(vector3(def.start.x, def.start.y, def.start.z), def.start.w, def.startRadius)
    for i, cp in ipairs(def.checkpoints or {}) do
        local radius = def.checkpointRadii and def.checkpointRadii[i]
        checkpoints[i + 1] = toVec3Point(vector3(cp.x, cp.y, cp.z), radius)
    end

    editingScheme   = def.scheme or 'ordered'
    editingLaps     = def.laps or 1
    editingGoalTime = def.goalTime
    editingUnlock   = def.unlockRequirement
    editingKind     = def.kind or 'road'
    editingVehicle  = def.vehicle and def.vehicle.model or nil
    editingMedals   = def.medals
    editingEntry    = def.entry and { x = def.entry.x, y = def.entry.y, z = def.entry.z } or nil
    for i in ipairs(def.checkpoints or {}) do
        local stunt = def.gateStunts and def.gateStunts[i]
        checkpoints[i + 1].stunt = stunt or nil
    end
    resetRadiusForNext()
end

-- ── Entry points (admin-gated server-side) ──────────────────────────────────

RegisterNetEvent('sk_streetkings:racing:admin:toggleRouteMaker', function()
    if buildMode then
        buildMode = false
        return
    end

    resetState()
    CreateThread(function()
        local input = lib.inputDialog('New Race', {
            {
                type = 'select', label = 'Race type', default = 'road', required = true,
                description = 'Air races hang their gates in the sky and hand the pilot a plane; offroad hands out a dirt vehicle',
                options = {
                    { value = 'road', label = 'Road race' },
                    { value = 'offroad', label = 'Offroad race' },
                    { value = 'air', label = 'Air race (stunt plane gates)' },
                },
            },
        })
        if not input or not input[1] then return end
        editingKind = input[1]
        buildMode = true
        notify('Race Maker opened — fly around and place points', 'success')
        startBuildLoop()
    end)
end)

RegisterNetEvent('sk_streetkings:racing:admin:editNearest', function()
    if buildMode then
        notify('Already in the editor', 'error')
        return
    end

    local nearest = findNearestCustomRoute()
    if not nearest then
        notify('No custom route within 300m', 'error')
        return
    end

    loadRouteForEdit(nearest.def)
    editingId   = nearest.id
    editingName = nearest.def.name or nearest.id

    buildMode = true
    notify(('Editing "%s" (%.0fm away)'):format(editingName, nearest.dist), 'success')
    startBuildLoop()
end)

RegisterNetEvent('sk_streetkings:racing:admin:deleteNearest', function()
    if buildMode then
        notify('Close the editor first', 'error')
        return
    end

    local nearest = findNearestCustomRoute()
    if not nearest then
        notify('No custom route within 300m', 'error')
        return
    end

    local routeName = nearest.def.name or nearest.id
    local confirmed = lib.alertDialog({
        header   = 'Delete race route',
        content  = ('Delete **%s**? This cannot be undone.'):format(routeName),
        centered = true,
        cancel   = true,
    })

    if confirmed ~= 'confirm' then
        notify('Delete cancelled', 'warning')
        return
    end

    local result = lib.callback.await('sk_streetkings:racing:admin:deleteRoute', false, nearest.id)
    if result and result.ok then
        notify(('Deleted "%s"'):format(routeName), 'success')
    else
        notify(('Delete failed: %s'):format(result and result.reason or 'unknown'), 'error')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    buildMode = false
    SKFreecam.stop()
    Cinematic = false
end)
