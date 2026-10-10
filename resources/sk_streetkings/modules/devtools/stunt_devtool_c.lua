-- Stunt jump placement tool, ported from streetkings
-- modules/devtools/stunt_devtool_c.lua.
--
-- A jump is a pair of zones with optional ramp props. Fly the freecam, aim at
-- the ground, click to drop zone A then zone B, switch to ramp mode to place
-- props, then save. Saved jumps go to `sk_stunt_jumps` and sync to everyone
-- live, so the jump is playable without a restart.
--
-- Opened from the server (`/stuntdev`, `/stuntedit`, `/stuntdelete`), which is
-- where the admin check lives — same shape as /racemaker.
--
-- Changes from upstream:
--   * The NUI status panel is redrawn with SKHud, and the NUI input/confirm
--     dialogs are lib.inputDialog / lib.alertDialog.
--   * Upstream registered five key mappings, which show up in every player's
--     FiveM keybind settings. All keys are read directly instead.
--   * Upstream gated the whole file behind a `streetkings_enableDevtools`
--     convar; the server-side admin check replaces it.

if not Config.Modules.stunts then return end

local RAMP_MODELS = {
    'stt_prop_ramp_jump_s',
    'stt_prop_ramp_jump_m',
    'stt_prop_ramp_jump_l',
    'stt_prop_ramp_jump_xl',
    'stt_prop_ramp_jump_xxl',
    'lts_prop_lts_ramp_01',
    'lts_prop_lts_ramp_02',
    'lts_prop_lts_ramp_03',
    'prop_mp_ramp_01_tu',
    'prop_mp_ramp_02_tu',
    'prop_mp_ramp_03_tu',
}

-- Controls. Everything is read with IsDisabledControlJustPressed, which fires
-- whether or not the freecam has the control enabled.
local CTRL_LMB       = 24
local CTRL_SCROLL_DN = 14
local CTRL_SCROLL_UP = 15
local CTRL_R         = 45  -- toggle zone/ramp mode
local CTRL_G         = 47  -- cycle ramp model
local CTRL_1         = 157
local CTRL_2         = 158
local CTRL_M         = 244 -- place spawn marker
local CTRL_T         = 245 -- test the jump
local CTRL_BACKSPACE = 177 -- undo
local CTRL_DELETE    = 179 -- clear all
local CTRL_ENTER     = 191 -- save
local CTRL_ESC       = 200 -- close
local CTRL_F9        = 56  -- export to clipboard
local CTRL_PGDN      = 208 -- (test mode) set spawn marker here
local CTRL_PGUP      = 207 -- (test mode) return to spawn marker

local TEST_JUMP_ID = '_stuntdev_test'

local buildMode  = false
local testMode   = false
local rampMode   = false
local rampTarget = 'a'

local rampModelIndex = 1
local currentHeading = 0.0
local zoneRadius     = 12.0
local sessionMarker  = nil
local raycastHit     = nil

local editingJumpId   = nil
local editingJumpName = nil

local stuntDef = { zoneA = nil, zoneARamp = nil, zoneB = nil, zoneBRamp = nil }

local previewProp      = nil
local previewModelName = nil
local placedPreviews   = {}
local debugZoneA, debugZoneB

---@param title string
---@param nType string
local function notify(title, nType)
    SKNotify({ title = title, type = nType, duration = 2500 })
end

-- ── Preview props ───────────────────────────────────────────────────────────

local function deletePreviewProp()
    if previewProp then
        if DoesEntityExist(previewProp) then DeleteEntity(previewProp) end
        previewProp      = nil
        previewModelName = nil
    end
end

local function clearPlacedPreviews()
    for i = 1, #placedPreviews do
        if DoesEntityExist(placedPreviews[i]) then DeleteEntity(placedPreviews[i]) end
    end
    placedPreviews = {}
end

---@param model string
---@param pos vector3
---@param heading number
local function createPreviewProp(model, pos, heading)
    deletePreviewProp()
    local hash = SK.LoadModel(model)
    if not hash then return end
    previewProp = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(previewProp, heading)
    PlaceObjectOnGroundProperly(previewProp)
    FreezeEntityPosition(previewProp, true)
    SetEntityAlpha(previewProp, 150, false)
    SetEntityCollision(previewProp, false, false)
    previewModelName = model
    SK.UnloadModel(hash)
end

---@param model string
---@param pos vector3
---@param heading number
local function updatePreviewProp(model, pos, heading)
    if not previewProp or not DoesEntityExist(previewProp) or previewModelName ~= model then
        createPreviewProp(model, pos, heading)
        return
    end
    SetEntityCoordsNoOffset(previewProp, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(previewProp, heading)
    PlaceObjectOnGroundProperly(previewProp)
end

---@param model string
---@param pos vector3
---@param heading number
local function spawnPlacedPreview(model, pos, heading)
    local hash = SK.LoadModel(model)
    if not hash then return end
    local obj = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
    SetEntityHeading(obj, heading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityAlpha(obj, 200, false)
    SetEntityCollision(obj, false, false)
    SK.UnloadModel(hash)
    placedPreviews[#placedPreviews + 1] = obj
end

local function rebuildPlacedPreviews()
    clearPlacedPreviews()
    if stuntDef.zoneARamp then
        spawnPlacedPreview(stuntDef.zoneARamp.model, stuntDef.zoneARamp.coords, stuntDef.zoneARamp.heading)
    end
    if stuntDef.zoneBRamp then
        spawnPlacedPreview(stuntDef.zoneBRamp.model, stuntDef.zoneBRamp.coords, stuntDef.zoneBRamp.heading)
    end
end

-- ── Zone debug volumes ──────────────────────────────────────────────────────

local function removeDebugZones()
    if debugZoneA then debugZoneA:remove() debugZoneA = nil end
    if debugZoneB then debugZoneB:remove() debugZoneB = nil end
end

---@param zoneDef table|nil
---@param colour table
---@return table|nil
local function createDebugZone(zoneDef, colour)
    if not zoneDef then return nil end
    return lib.zones.sphere({
        coords      = zoneDef.center,
        radius      = zoneDef.radius,
        debug       = true,
        debugColour = colour,
    })
end

local function refreshDebugZones()
    removeDebugZones()
    debugZoneA = createDebugZone(stuntDef.zoneA, { 0, 255, 100, 70 })
    debugZoneB = createDebugZone(stuntDef.zoneB, { 100, 100, 255, 70 })
end

-- ── Definition ──────────────────────────────────────────────────────────────

---@param name string
---@return string
local function slugify(name)
    local slug = name:lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    return 'stunt_' .. (slug ~= '' and slug or 'jump')
end

---@param id string
---@param name string
---@return table
local function buildDefForSave(id, name)
    return {
        id    = id,
        name  = name,
        zoneA = { center = stuntDef.zoneA.center, radius = stuntDef.zoneA.radius, ramp = stuntDef.zoneARamp },
        zoneB = { center = stuntDef.zoneB.center, radius = stuntDef.zoneB.radius, ramp = stuntDef.zoneBRamp },
    }
end

--- A data/stunt_jumps.lua-shaped snippet, for pasting a jump into source
--- control instead of leaving it in the database.
---@return string
local function buildExport()
    local function fv3(v) return ('vector3(%.4f, %.4f, %.4f)'):format(v.x, v.y, v.z) end

    local function zoneLine(key, z, rampDef)
        local parts = { ('center = %s'):format(fv3(z.center)), ('radius = %.1f'):format(z.radius) }
        if rampDef then
            parts[#parts + 1] = ("ramp = { model = '%s', coords = %s, heading = %.1f }")
                :format(rampDef.model, fv3(rampDef.coords), rampDef.heading)
        end
        return ('    %s = { %s },'):format(key, table.concat(parts, ', '))
    end

    local lines = { '{' }
    if stuntDef.zoneA then lines[#lines + 1] = zoneLine('zoneA', stuntDef.zoneA, stuntDef.zoneARamp) end
    if stuntDef.zoneB then lines[#lines + 1] = zoneLine('zoneB', stuntDef.zoneB, stuntDef.zoneBRamp) end
    lines[#lines + 1] = '}'
    return table.concat(lines, '\n')
end

local function resetDef()
    stuntDef = { zoneA = nil, zoneARamp = nil, zoneB = nil, zoneBRamp = nil }
    clearPlacedPreviews()
    deletePreviewProp()
    removeDebugZones()
    rampMode        = false
    rampTarget      = 'a'
    zoneRadius      = 12.0
    currentHeading  = 0.0
    rampModelIndex  = 1
    sessionMarker   = nil
    editingJumpId   = nil
    editingJumpName = nil
end

local function undoLast()
    for _, key in ipairs({ 'zoneBRamp', 'zoneB', 'zoneARamp', 'zoneA' }) do
        if stuntDef[key] then
            stuntDef[key] = nil
            rebuildPlacedPreviews()
            refreshDebugZones()
            notify(('Undid %s'):format(key), 'warning')
            return
        end
    end
    notify('Nothing to undo', 'warning')
end

-- ── Status overlay ──────────────────────────────────────────────────────────

local P = SKHud.Palette

local function drawStatus()
    local placed = ('A %s   Ramp A %s   B %s   Ramp B %s'):format(
        stuntDef.zoneA     and 'set' or '—',
        stuntDef.zoneARamp and 'set' or '—',
        stuntDef.zoneB     and 'set' or '—',
        stuntDef.zoneBRamp and 'set' or '—'
    )

    local detail
    if rampMode then
        detail = ('RAMP MODE  •  target %s  •  %s  •  heading %.0f°')
            :format(rampTarget:upper(), RAMP_MODELS[rampModelIndex], currentHeading)
    else
        detail = ('ZONE MODE  •  radius %.0fm'):format(zoneRadius)
    end

    SKHud.Panel(0.5, 0.070, 0.560, 0.080, P.panelDark)
    SKHud.Text(editingJumpName and ('Editing: ' .. editingJumpName) or 'New Stunt Jump',
        0.5, 0.038, 0.36, P.accent, true)
    SKHud.Text(detail, 0.5, 0.058, 0.30, rampMode and P.warning or P.info, true)
    SKHud.Text(placed, 0.5, 0.078, 0.30, P.text, true)

    SKHud.Panel(0.5, 0.958, 0.860, 0.062, P.panelDark)
    SKHud.Text('LMB place   Scroll ' .. (rampMode and 'rotate' or 'radius') ..
        '   R mode   G model   1/2 ramp target   M spawn marker   T test',
        0.5, 0.937, 0.28, P.textDim, true)
    SKHud.Text('Backspace undo   Delete clear   F9 export   Enter save   Esc close',
        0.5, 0.957, 0.28, P.textDim, true)
end

local function drawConnectionLine()
    if stuntDef.zoneA and stuntDef.zoneB then
        local ac, bc = stuntDef.zoneA.center, stuntDef.zoneB.center
        DrawLine(ac.x, ac.y, ac.z + 0.3, bc.x, bc.y, bc.z + 0.3, 255, 210, 0, 200)
    end
end

local function drawSessionMarker()
    if not sessionMarker then return end
    local c = sessionMarker.coords
    DrawMarker(2, c.x, c.y, c.z + 1.5, 0, 0, 0, 180.0, 0, 0,
        0.4, 0.4, 0.4, 255, 210, 0, 200, true, true, 2, true, nil, nil, false)
end

-- ── Placement input ─────────────────────────────────────────────────────────

local function handleZoneModeInput()
    if IsDisabledControlJustPressed(0, CTRL_SCROLL_DN) then
        zoneRadius = math.max(2.0, zoneRadius - 1.0)
    elseif IsDisabledControlJustPressed(0, CTRL_SCROLL_UP) then
        zoneRadius = math.min(50.0, zoneRadius + 1.0)
    end

    if raycastHit then
        -- Green while placing A, blue while placing B.
        local r, g, b = 0, 255, 100
        if stuntDef.zoneA and not stuntDef.zoneB then r, g, b = 100, 100, 255 end
        DrawMarker(1, raycastHit.x, raycastHit.y, raycastHit.z, 0, 0, 0, 0, 0, 0,
            zoneRadius * 2, zoneRadius * 2, 0.5, r, g, b, 50, false, true, 2, false, nil, nil, false)
    end

    if IsDisabledControlJustPressed(0, CTRL_LMB) and raycastHit then
        local pos = vec3(raycastHit.x, raycastHit.y, raycastHit.z)
        if not stuntDef.zoneA then
            stuntDef.zoneA = { center = pos, radius = zoneRadius }
            notify('Zone A placed', 'success')
        elseif not stuntDef.zoneB then
            stuntDef.zoneB = { center = pos, radius = zoneRadius }
            notify('Zone B placed', 'success')
        else
            -- Both already set: shuffle B into A and start a new B, so a chain
            -- of jumps can be walked along without clearing every time.
            stuntDef.zoneA     = stuntDef.zoneB
            stuntDef.zoneARamp = stuntDef.zoneBRamp
            stuntDef.zoneB     = { center = pos, radius = zoneRadius }
            stuntDef.zoneBRamp = nil
            rebuildPlacedPreviews()
            notify('Zones shifted, new Zone B placed', 'success')
        end
        refreshDebugZones()
    end
end

local function handleRampModeInput()
    if IsDisabledControlJustPressed(0, CTRL_SCROLL_DN) then
        currentHeading = (currentHeading - 5.0) % 360.0
    elseif IsDisabledControlJustPressed(0, CTRL_SCROLL_UP) then
        currentHeading = (currentHeading + 5.0) % 360.0
    end

    if IsDisabledControlJustPressed(0, CTRL_G) then
        rampModelIndex = (rampModelIndex % #RAMP_MODELS) + 1
        deletePreviewProp()
        notify(RAMP_MODELS[rampModelIndex], 'inform')
    end

    if IsDisabledControlJustPressed(0, CTRL_1) then
        rampTarget = 'a'
        notify('Ramp target: Zone A', 'inform')
    elseif IsDisabledControlJustPressed(0, CTRL_2) then
        rampTarget = 'b'
        notify('Ramp target: Zone B', 'inform')
    end

    if raycastHit then
        updatePreviewProp(RAMP_MODELS[rampModelIndex], raycastHit, currentHeading)
    end

    if IsDisabledControlJustPressed(0, CTRL_LMB) and raycastHit then
        local rampDef = {
            model   = RAMP_MODELS[rampModelIndex],
            coords  = vec3(raycastHit.x, raycastHit.y, raycastHit.z),
            heading = currentHeading,
        }
        if rampTarget == 'a' then
            stuntDef.zoneARamp = rampDef
            notify('Ramp A placed', 'success')
        else
            stuntDef.zoneBRamp = rampDef
            notify('Ramp B placed', 'success')
        end
        rebuildPlacedPreviews()
    end
end

-- ── Test mode ───────────────────────────────────────────────────────────────

---@param pos vector3
---@param heading number
local function teleportPlayerTo(pos, heading)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local entity = veh ~= 0 and veh or ped
    SetEntityCoordsNoOffset(entity, pos.x, pos.y, pos.z + 1.0, false, false, false)
    SetEntityHeading(entity, heading)
    if veh ~= 0 then SetVehicleOnGroundProperly(veh) end
end

local function enterTestMode()
    if not stuntDef.zoneA or not stuntDef.zoneB then
        notify('Place both zones before testing', 'error')
        return
    end

    deletePreviewProp()
    SKFreecam.stop()
    Cinematic = false

    exports[GetCurrentResourceName()]:SetupTestJump(TEST_JUMP_ID, buildDefForSave(TEST_JUMP_ID, 'Test Session'))

    teleportPlayerTo(
        sessionMarker and sessionMarker.coords or stuntDef.zoneA.center,
        sessionMarker and sessionMarker.heading or 0.0
    )

    testMode = true
    notify('Test mode — Esc returns to the editor', 'inform')

    CreateThread(function()
        while testMode do
            if IsDisabledControlJustPressed(0, CTRL_ESC) then
                testMode = false
            end

            -- PgDn drops a spawn point here; PgUp jumps back to it, so a jump
            -- can be re-run without driving back round.
            if IsDisabledControlJustPressed(0, CTRL_PGDN) then
                local ped = PlayerPedId()
                local veh = GetVehiclePedIsIn(ped, false)
                local entity = veh ~= 0 and veh or ped
                local pos = GetEntityCoords(entity)
                sessionMarker = { coords = vec3(pos.x, pos.y, pos.z), heading = GetEntityHeading(entity) }
                notify('Spawn marker placed', 'success')
            end

            if IsDisabledControlJustPressed(0, CTRL_PGUP) and sessionMarker then
                teleportPlayerTo(sessionMarker.coords, sessionMarker.heading)
                notify('Returned to marker', 'inform')
            end

            Wait(0)
        end

        exports[GetCurrentResourceName()]:TeardownTestJump(TEST_JUMP_ID)

        if buildMode then
            Cinematic = true
            SKFreecam.start()
            notify('Back in the editor', 'inform')
        end
    end)
end

-- ── Save ────────────────────────────────────────────────────────────────────

local function saveJump()
    if not stuntDef.zoneA or not stuntDef.zoneB then
        notify('Place both zones before saving', 'error')
        return
    end

    SKFreecam.setPaused(true)
    local input = lib.inputDialog('Save Stunt Jump', {
        {
            type     = 'input',
            label    = 'Name',
            default  = editingJumpName or '',
            required = true,
            placeholder = 'Vinewood Gap',
        },
    })
    SKFreecam.setPaused(false)

    if not input or not input[1] or input[1] == '' then
        notify('Save cancelled', 'warning')
        return
    end

    local name   = input[1]
    local id     = editingJumpId or slugify(name)
    local result = lib.callback.await('sk_streetkings:stunts:save', false, buildDefForSave(id, name))

    if result and result.ok then
        notify(('Saved "%s"'):format(name), 'success')
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
                if not testMode then
                    raycastHit = SKFreecam.raycast()
                end
                Wait(16)
            end
        end)

        while buildMode do
            Wait(0)
            if testMode then goto continue end
            if not SKFreecam.isEnabled() then break end

            drawConnectionLine()
            drawSessionMarker()
            drawStatus()

            if rampMode then
                handleRampModeInput()
            else
                deletePreviewProp()
                handleZoneModeInput()
            end

            if IsDisabledControlJustPressed(0, CTRL_R) then
                rampMode = not rampMode
                if not rampMode then deletePreviewProp() end
                notify(rampMode and 'Ramp mode' or 'Zone mode', 'inform')
            end

            if IsDisabledControlJustPressed(0, CTRL_M) then
                if raycastHit then
                    sessionMarker = {
                        coords  = vec3(raycastHit.x, raycastHit.y, raycastHit.z),
                        heading = GetGameplayCamRot(2).z,
                    }
                    notify('Spawn marker placed', 'success')
                else
                    notify('Aim at the ground first', 'error')
                end
            end

            if IsDisabledControlJustPressed(0, CTRL_T) then
                enterTestMode()
            end

            if IsDisabledControlJustPressed(0, CTRL_BACKSPACE) then
                undoLast()
            end

            if IsDisabledControlJustPressed(0, CTRL_F9) then
                if stuntDef.zoneA or stuntDef.zoneB then
                    lib.setClipboard(buildExport())
                    notify('Copied to clipboard', 'success')
                else
                    notify('Nothing to export', 'error')
                end
            end

            if IsDisabledControlJustPressed(0, CTRL_DELETE) then
                if rampMode then
                    local key = rampTarget == 'a' and 'zoneARamp' or 'zoneBRamp'
                    if stuntDef[key] then
                        stuntDef[key] = nil
                        rebuildPlacedPreviews()
                        notify(('Ramp %s deleted'):format(rampTarget:upper()), 'warning')
                    else
                        notify('No ramp to delete', 'warning')
                    end
                else
                    resetDef()
                    notify('All placements cleared', 'warning')
                end
            end

            if IsDisabledControlJustPressed(0, CTRL_ENTER) then
                CreateThread(saveJump)
            end

            if IsDisabledControlJustPressed(0, CTRL_ESC) then
                buildMode = false
                notify('Stunt dev tool closed', 'warning')
                break
            end

            ::continue::
        end

        testMode = false
        deletePreviewProp()
        clearPlacedPreviews()
        removeDebugZones()
        SKFreecam.stop()
        Cinematic = false
        raycastHit = nil

        -- Editing takes the live jump down so its props do not double up with
        -- the editor previews. Put it back on the way out, whether the edit was
        -- saved (setupJump replaces cleanly) or abandoned.
        if editingJumpId and SKStuntJumps and SKStuntJumps[editingJumpId] then
            exports[GetCurrentResourceName()]:SetupTestJump(editingJumpId, SKStuntJumps[editingJumpId])
        end

        editingJumpId   = nil
        editingJumpName = nil
    end)
end

-- ── Editing an existing jump ────────────────────────────────────────────────

---@return { id: string, def: table, dist: number }|nil
local function findNearestJump()
    if not SKStuntJumps then return nil end

    local myPos = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, 200.0

    for id, def in pairs(SKStuntJumps) do
        if def.zoneA and def.zoneA.center then
            local c = def.zoneA.center
            if type(c) ~= 'vector3' then c = vector3(c.x, c.y, c.z) end
            local d = #(myPos - c)
            if d < bestDist then
                bestDist = d
                best = { id = id, def = def, dist = d }
            end
        end
    end

    return best
end

---@param z table|nil
---@return table|nil
local function loadZoneFromDef(z)
    if not z then return nil end
    local zone = { center = z.center, radius = z.radius or 10.0 }
    if z.shape == 'box' and z.size then
        local sz = z.size
        if type(sz) ~= 'vector3' then
            sz = vec3(tonumber(sz.x or sz[1]) or 24.0, tonumber(sz.y or sz[2]) or 24.0, tonumber(sz.z or sz[3]) or 4.0)
        end
        zone.radius = math.max(sz.x, sz.y) * 0.5
    end
    return zone
end

---@param def table
local function loadDefFromSaved(def)
    stuntDef = { zoneA = nil, zoneARamp = nil, zoneB = nil, zoneBRamp = nil }

    if def.zoneA then
        stuntDef.zoneA = loadZoneFromDef(def.zoneA)
        if def.zoneA.ramp then
            stuntDef.zoneARamp = {
                model   = def.zoneA.ramp.model,
                coords  = def.zoneA.ramp.coords,
                heading = def.zoneA.ramp.heading or 0.0,
            }
        end
        zoneRadius = stuntDef.zoneA.radius or 12.0
    end

    if def.zoneB then
        stuntDef.zoneB = loadZoneFromDef(def.zoneB)
        if def.zoneB.ramp then
            stuntDef.zoneBRamp = {
                model   = def.zoneB.ramp.model,
                coords  = def.zoneB.ramp.coords,
                heading = def.zoneB.ramp.heading or 0.0,
            }
        end
    end

    rebuildPlacedPreviews()
    refreshDebugZones()
end

-- ── Entry points (admin-gated server-side) ──────────────────────────────────

RegisterNetEvent('sk_streetkings:stunts:admin:open', function()
    if buildMode then
        buildMode = false
        notify('Stunt dev tool closed', 'warning')
        return
    end

    resetDef()
    buildMode = true
    notify('Stunt jump creator opened', 'success')
    startBuildLoop()
end)

RegisterNetEvent('sk_streetkings:stunts:admin:editNearest', function()
    if buildMode then
        notify('Already in the editor', 'error')
        return
    end

    local nearest = findNearestJump()
    if not nearest then
        notify('No stunt jump within 200m', 'error')
        return
    end

    resetDef()
    editingJumpId   = nearest.id
    editingJumpName = nearest.def.name or nearest.id

    -- Take the live jump down so its props do not overlap the editor previews.
    exports[GetCurrentResourceName()]:TeardownTestJump(nearest.id)
    loadDefFromSaved(nearest.def)

    buildMode = true
    notify(('Editing "%s" (%.0fm away)'):format(editingJumpName, nearest.dist), 'success')
    startBuildLoop()
end)

RegisterNetEvent('sk_streetkings:stunts:admin:deleteNearest', function()
    local nearest = findNearestJump()
    if not nearest then
        notify('No stunt jump within 200m', 'error')
        return
    end

    local jumpName = nearest.def.name or nearest.id

    SKFreecam.setPaused(true)
    local confirmed = lib.alertDialog({
        header   = 'Delete stunt jump',
        content  = ('Delete **%s**? This cannot be undone.'):format(jumpName),
        centered = true,
        cancel   = true,
    })
    SKFreecam.setPaused(false)

    if confirmed ~= 'confirm' then
        notify('Delete cancelled', 'warning')
        return
    end

    local result = lib.callback.await('sk_streetkings:stunts:delete', false, nearest.id)
    if result and result.ok then
        notify(('Deleted "%s"'):format(jumpName), 'success')
    else
        notify(('Delete failed: %s'):format(result and result.reason or 'unknown'), 'error')
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    buildMode = false
    testMode  = false
    deletePreviewProp()
    clearPlacedPreviews()
    removeDebugZones()
    Cinematic = false
end)
