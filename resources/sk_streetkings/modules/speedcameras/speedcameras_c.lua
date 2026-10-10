-- Speed cameras, ported from streetkings modules/freeroam/speed_cameras_c.lua.
--
-- Drive through a camera zone above its trigger speed and the game cuts to a
-- fixed camera on the gantry, flashes, and the player is fined.
--
-- Changes from upstream:
--   * The NUI flash overlay is redrawn as an SKHud widget.
--   * Upstream reported the trigger to its daily-events system for a *reward*.
--     That system is not ported, so the flash goes to a fine instead
--     (Config.SpeedCameras), which is what the camera prop implies anyway.
--   * SKCamera.disable()/delayEnable() calls are dropped — those belonged to
--     upstream's custom chase camera, which is not ported.
--   * The shutter goes through SK.PlaySound, which uses StreetKings' own
--     'speedcamera' sound when the optional streetkings_audio resource is
--     installed and a stock shutter otherwise.

if not Config.Modules.speedCameras then return end

local MPS_TO_MPH  = 2.236936
local COOLDOWN_MS = 30000

-- How long the fixed camera holds before handing control back.
local CINEMATIC_MS = 1250
-- The white blowout at the front of the shot.
local FLASH_MS     = 320

local activeZones = {}
local activeProps = {}
local activeBlips = {}
local cooldowns   = {}

-- ── vice_hud "camera" wanted tell ───────────────────────────────────────────
-- vice_hud draws six tells beside the wanted stars, one of which is a camera:
-- "something has you on film". It has no way to work that out on its own, so
-- it exposes a reporting export for whoever does — and these cameras do.
--
-- Reported as a SIGHTING, not as presence. The camera is only in frame for the
-- second or two it takes to drive past, but the police do not forget the photo
-- when you leave the junction: vice_hud latches the tell and clears it when
-- the wanted level reaches zero, i.e. when the police lose you. An earlier
-- version pushed on-enter/off-exit and the tell was gone almost as fast as it
-- appeared — about as long as the cinematic below.
--
-- Deliberately reports being SEEN, not being SPEEDING: a camera watches every
-- car that passes, and the cinematic/fine is a separate question of how fast
-- you were going. There is no wanted check here either — vice_hud drops every
-- tell at zero stars and discards sightings made while not wanted, so one
-- place decides that and it is not this file.
local TELL_SOURCE = 'sk_streetkings'

local function reportCameraSighting()
    if GetResourceState('vice_hud') ~= 'started' then return end
    pcall(function()
        exports['vice_hud']:ReportWantedTellSighting('camera', TELL_SOURCE)
    end)
end

-- ── Blip cones ──────────────────────────────────────────────────────────────
-- Credit: The scaleform guy (CFX discord). These natives have no official
-- names; they draw the vision cone a camera blip shows on the minimap. They
-- are cosmetic, and an unnamed native is exactly the thing a client update can
-- drop, so a missing one must not take the cameras down with it.

local clonedArrayCleared = false

local function addFakeConeToBlip(blip, minAngle, maxAngle, gazeAngle, peripheralRange, focusRange, rotation, continuous)
    pcall(function()
        if not clonedArrayCleared then
            N_0x8410c5e0cd847b9d()
            clonedArrayCleared = true
        end
        N_0xf83d0febe75e62c9(blip, minAngle, maxAngle, gazeAngle, peripheralRange, focusRange, rotation, continuous)
        SetBlipShowCone(blip, true)
    end)
end

local function removeFakeConeFromBlip(blip)
    pcall(function()
        SetBlipShowCone(blip, false)
        N_0x35a3cd97b2c0a6d2(blip)
    end)
end

-- ── HUD ─────────────────────────────────────────────────────────────────────

local P = SKHud.Palette
local READOUT = SKHud.Anchor.centreLow

SKHud.register('speedcam', function(data)
    local elapsed = GetGameTimer() - data.startedAt

    -- Blowout first, fading to clear over FLASH_MS.
    if elapsed < FLASH_MS then
        local alpha = math.floor(235 * (1.0 - (elapsed / FLASH_MS)))
        if alpha > 0 then
            SKHud.ScreenWash({ 255, 255, 255 }, alpha)
        end
    end

    SKHud.Panel(READOUT.x, READOUT.y, 0.230, 0.098, P.panelDark)
    SKHud.Text('SPEED CAMERA', READOUT.x, READOUT.y - 0.045, 0.34, P.accent, true)
    SKHud.Text(('%d MPH'):format(data.speed), READOUT.x, READOUT.y - 0.025, 0.62, P.danger, true)
    SKHud.Text(data.name or '', READOUT.x, READOUT.y + 0.019, 0.30, P.textDim, true)
end)

-- ── Cinematic ───────────────────────────────────────────────────────────────

local function cleanupCinematic(cinCam)
    Cinematic = false
    SKHud.clear('speedcam')
    pcall(StopCamShaking, cinCam, true)
    ClearTimecycleModifier()
    if cinCam and DoesCamExist(cinCam) then
        SetCamActive(cinCam, false)
        DestroyCam(cinCam, false)
    end
    RenderScriptCams(false, true, 0, true, true)
end

---@param cam table entry from SKSpeedCameras
---@param speedMph number
local function runCinematic(cam, speedMph)
    if Cinematic then return end
    Cinematic = true

    local playerVeh = GetVehiclePedIsIn(PlayerPedId(), false)
    if playerVeh == 0 then
        Cinematic = false
        return
    end

    local cinCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cinCam, cam.camCoords.x, cam.camCoords.y, cam.camCoords.z)
    PointCamAtEntity(cinCam, playerVeh, 0.0, 0.2, 0.0, true)
    SetCamFov(cinCam, 38.0)
    SetCamActive(cinCam, true)
    RenderScriptCams(true, true, 0, true, true)

    -- Misspelling is GTA's, not a typo.
    SetTimecycleModifier('CAMERA_secuirity_FUZZ')
    SetTimecycleModifierStrength(0.65)
    pcall(ShakeCam, cinCam, 'HAND_SHAKE', 0.08)

    SKHud.set('speedcam', {
        speed     = math.floor(speedMph),
        name      = cam.name,
        startedAt = GetGameTimer(),
    })
    SK.PlaySound('speedcamera')

    local result = lib.callback.await(
        'sk_streetkings:speedcameras:flash', false,
        cam.id, math.floor(speedMph), SK.GetVehicleModelLabel(playerVeh)
    )

    Wait(CINEMATIC_MS)
    cleanupCinematic(cinCam)

    if result and result.summary then
        SKNotify({
            type     = 'error',
            title    = 'Speed Camera',
            description = result.summary,
            duration = 5000,
        })
    end
end

-- ── Zone entry ──────────────────────────────────────────────────────────────

---@param cam table
local function onCamEnter(cam)
    -- Cameras stand down during a scored run, and anywhere that is not the
    -- open world (car meet interior, menus).
    if SKC.GetGameState() ~= GameState.FREEROAM then return end
    if Cinematic then return end

    local now = GetGameTimer()
    if cooldowns[cam.id] and now < cooldowns[cam.id] then return end

    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return end

    local speedMph = GetEntitySpeed(veh) * MPS_TO_MPH
    if speedMph < cam.triggerSpeedMph then return end

    cooldowns[cam.id] = now + COOLDOWN_MS

    CreateThread(function()
        local ok = pcall(runCinematic, cam, speedMph)
        if not ok then
            -- Never leave the player stuck behind a scripted camera.
            Cinematic = false
            SKHud.clear('speedcam')
            ClearTimecycleModifier()
            RenderScriptCams(false, true, 0, true, true)
        end
    end)
end

-- ── em_toolkit connector (optional) ─────────────────────────────────────────
-- Extra camera sites placed in-game with em_toolkit's Speed Cameras builder.
-- sk_streetkings runs standalone off data/speed_cameras.lua without it; this is
-- purely additive.

local toolkitCameras = nil

local function refreshToolkitCameras()
    if Config.SpeedCameras.useToolkitCameras == false then
        toolkitCameras = nil
        return
    end
    local ok, result = pcall(function()
        return exports['em_toolkit']:getSpeedCameras()
    end)
    toolkitCameras = (ok and type(result) == 'table') and result or nil
end

--- One em_toolkit record expanded into the SKSpeedCameras shape. The prop sits
--- 2m under the cinematic camera and its cone is drawn at propHeading + 180, so
--- storing the direction traffic travels is enough to aim both — which is why
--- every shipped camera has propHeading == heading.
---@param rec table
---@return table
local function toolkitToCam(rec)
    local camCoords = vector3(rec.cx, rec.cy, rec.cz)
    return {
        id              = rec.id,
        name            = rec.name or 'Speed Camera',
        coords          = vector3(rec.x, rec.y, rec.z),
        radius          = rec.radius or 20,
        heading         = rec.h or 0.0,
        camCoords       = camCoords,
        propCoords      = vector3(camCoords.x, camCoords.y, camCoords.z - 2.0),
        propHeading     = rec.h or 0.0,
        coneMinAngle    = -2.0,
        coneMaxAngle    = 2.0,
        coneFocusRange  = rec.cone or 50.0,
        triggerSpeedMph = rec.speed or 60,
        debug           = false,
    }
end

local function allCameras()
    local out = {}
    for _, cam in ipairs(SKSpeedCameras or {}) do out[#out + 1] = cam end
    for _, rec in ipairs(toolkitCameras or {}) do out[#out + 1] = toolkitToCam(rec) end
    return out
end

-- ── Zones, props and blips ──────────────────────────────────────────────────

local function clearZones()
    for _, zone in ipairs(activeZones) do zone:remove() end
    activeZones = {}

    for _, blip in ipairs(activeBlips) do
        if DoesBlipExist(blip) then
            removeFakeConeFromBlip(blip)
            RemoveBlip(blip)
        end
    end
    activeBlips = {}

    for _, prop in ipairs(activeProps) do
        if DoesEntityExist(prop) then DeleteEntity(prop) end
    end
    activeProps = {}

    cooldowns = {}
end

local function setupZones()
    -- Clear first, unconditionally: this also runs when em_toolkit's list
    -- changes, and deleting the last camera has to tear its zone down.
    clearZones()

    local cameras = allCameras()
    if #cameras == 0 then return end

    local propHash = SK.LoadModel(`p_tv_cam_02_s`)

    for _, cam in ipairs(cameras) do
        if propHash then
            local prop = CreateObjectNoOffset(
                propHash,
                cam.propCoords.x, cam.propCoords.y, cam.propCoords.z,
                false, false, false
            )
            PlaceObjectOnGroundProperly(prop)
            SetEntityHeading(prop, cam.propHeading or 0.0)
            FreezeEntityPosition(prop, true)
            SetEntityCollision(prop, false, false)
            activeProps[#activeProps + 1] = prop

            local blip = SK.CreateBlip(Config.Blips.speedCamera, prop)

            addFakeConeToBlip(
                blip, cam.coneMinAngle, cam.coneMaxAngle, 0.36, 1.0, cam.coneFocusRange,
                (math.pi / 180.0) * (GetEntityHeading(prop) + 180.0), true
            )

            activeBlips[#activeBlips + 1] = blip
        end

        activeZones[#activeZones + 1] = lib.zones.sphere({
            coords  = cam.coords,
            radius  = cam.radius or 12,
            debug   = cam.debug or false,
            onEnter = function()
                -- Unconditional: the camera photographs you whether or not you
                -- are speeding. onCamEnter is the separate speeding question
                -- and has its own guards. No onExit -- the sighting is latched
                -- by vice_hud and ends when the police lose you, not when you
                -- leave the junction.
                reportCameraSighting()
                onCamEnter(cam)
            end,
        })
    end

    if propHash then SK.UnloadModel(propHash) end
end

-- ── Lifecycle ───────────────────────────────────────────────────────────────

CreateThread(function()
    SK.WaitForControl()
    Wait(1500)
    refreshToolkitCameras()
    setupZones()
end)

-- em_toolkit fires this after placing, moving, editing or deleting a camera.
RegisterNetEvent('em_toolkit:speedCamerasChanged', function()
    refreshToolkitCameras()
    setupZones()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearZones()
    ClearTimecycleModifier()
    RenderScriptCams(false, true, 0, true, true)

    -- Drop any latched sighting: with these cameras gone there is nothing left
    -- to justify the tell, and vice_hud would otherwise keep showing it for the
    -- rest of the pursuit on behalf of a resource that is no longer running.
    if GetResourceState('vice_hud') == 'started' then
        pcall(function() exports['vice_hud']:ClearWantedTellOverrides(TELL_SOURCE) end)
    end
end)
