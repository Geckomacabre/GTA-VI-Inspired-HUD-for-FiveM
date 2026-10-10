-- Editor freecam, ported from streetkings
-- modules/devtools/race_editor_freecam_c.lua.
--
-- Detaches the camera from the player so an admin can fly around placing
-- things, and exposes a camera-forward raycast for picking a spot on the world.
-- Used by both the stunt jump devtool and the /racemaker route placer.
--
-- Changes from upstream: the SKCamera.setBlocked() calls are dropped (that was
-- upstream's custom chase camera, which is not ported), and the chat control is
-- left disabled so the devtool can bind T without opening chat.

SKFreecam = {}

local SLOW_SPEED   = 0.02
local NORMAL_SPEED = 0.12
local FAST_SPEED   = 0.5
local FOCUS_UPDATE_INTERVAL_MS = 250

-- Speeds above are tuned against a 60fps tick. Movement is scaled by the
-- actual frame time so a lower/higher framerate flies at the same real-world
-- speed instead of crawling or rocketing off — same idea as the FPS-corrected
-- move step in taoletsgo/custom_races' creator freecam, done per-frame with
-- GetFrameTime() instead of a once-a-second average.
local REFERENCE_FPS = 60.0

local enabled       = false
local paused        = false
local camera        = nil
local rotation      = vector3(0.0, 0.0, 0.0)
local frozenEntity  = nil
local lastFocusAt   = 0

---@param rot vector3
---@return vector3
local function forwardVector(rot)
    local radZ, radX = math.rad(rot.z), math.rad(rot.x)
    return vector3(
        -math.sin(radZ) * math.abs(math.cos(radX)),
        math.cos(radZ) * math.abs(math.cos(radX)),
        math.sin(radX)
    )
end

---@param rot vector3
---@return vector3
local function rightVector(rot)
    local radZ = math.rad(rot.z)
    return vector3(math.cos(radZ), math.sin(radZ), 0.0)
end

local function handleCamera()
    if not camera then return end

    -- Held still while a dialog has NUI focus, so mouse movement aimed at the
    -- dialog does not swing the camera around behind it.
    if paused then return end

    local coords = GetCamCoord(camera)
    local mouseX = GetDisabledControlNormal(0, 1) * 5.0
    local mouseY = GetDisabledControlNormal(0, 2) * 5.0

    rotation = vector3(
        math.max(-89.0, math.min(89.0, rotation.x - mouseY)),
        rotation.y,
        rotation.z - mouseX
    )
    SetCamRot(camera, rotation.x, rotation.y, rotation.z, 2)

    -- Shift for fast, Ctrl for fine positioning.
    local speed = NORMAL_SPEED
    if IsDisabledControlPressed(0, 19) then
        speed = SLOW_SPEED
    elseif IsDisabledControlPressed(0, 21) then
        speed = FAST_SPEED
    end
    speed = speed * (GetFrameTime() * REFERENCE_FPS)

    local forward = forwardVector(rotation)
    local right   = rightVector(rotation)
    local up      = vector3(0.0, 0.0, 1.0)
    local target  = coords

    if IsDisabledControlPressed(0, 32) then target = target + forward * speed end -- W
    if IsDisabledControlPressed(0, 33) then target = target - forward * speed end -- S
    if IsDisabledControlPressed(0, 34) then target = target - right   * speed end -- A
    if IsDisabledControlPressed(0, 35) then target = target + right   * speed end -- D
    if IsDisabledControlPressed(0, 44) then target = target - up      * speed end -- Q
    if IsDisabledControlPressed(0, 38) then target = target + up      * speed end -- E

    SetCamCoord(camera, target.x, target.y, target.z)

    -- Keep the world streaming in around the camera rather than the player.
    local now = GetGameTimer()
    if now >= lastFocusAt then
        SetFocusPosAndVel(target.x, target.y, target.z, 0.0, 0.0, 0.0)
        lastFocusAt = now + FOCUS_UPDATE_INTERVAL_MS
    end

    -- Everything is off except look, move and speed modifiers. Tools read their
    -- own keys with IsDisabledControlJustPressed, which works while disabled.
    DisableAllControlActions(0)
    for _, control in ipairs({ 1, 2, 19, 21, 22, 32, 33, 34, 35, 38, 44 }) do
        EnableControlAction(0, control, true)
    end
end

--- Freezes camera movement without tearing the camera down. Use around any
--- dialog that takes NUI focus.
---@param value boolean
function SKFreecam.setPaused(value)
    paused = value and true or false
end

function SKFreecam.start()
    if enabled then return end
    enabled     = true
    paused      = false
    lastFocusAt = 0

    local camCoords = GetGameplayCamCoord()
    local camRot    = GetGameplayCamRot(2)

    camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(camera, camCoords.x, camCoords.y, camCoords.z)
    SetCamRot(camera, camRot.x, camRot.y, camRot.z, 2)
    SetCamFov(camera, GetGameplayCamFov())
    SetCamActive(camera, true)
    RenderScriptCams(true, false, 0, true, true)

    rotation = camRot

    local ped     = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    frozenEntity = (vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped) and vehicle or ped

    FreezeEntityPosition(frozenEntity, true)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(frozenEntity, false, false)

    CreateThread(function()
        while enabled do
            handleCamera()
            Wait(0)
        end
    end)
end

function SKFreecam.stop()
    if not enabled then return end
    enabled = false
    paused  = false

    if camera then
        RenderScriptCams(false, true, 250, true, true)
        DestroyCam(camera, false)
        camera = nil
    end

    if frozenEntity then
        if DoesEntityExist(frozenEntity) then
            FreezeEntityPosition(frozenEntity, false)
            SetEntityCollision(frozenEntity, true, true)
        end
        frozenEntity = nil
    end

    SetEntityVisible(PlayerPedId(), true, false)
    ClearFocus()
end

---@return boolean
function SKFreecam.isEnabled()
    return enabled
end

--- Current camera heading (z rotation), for orienting placed points.
---@return number
function SKFreecam.getHeading()
    return rotation.z
end

--- Snaps the freecam to a position, keeping its current rotation. Used to jump
--- back to a previously-placed point instead of flying there by hand.
---@param pos vector3
function SKFreecam.setPosition(pos)
    if not camera then return end
    SetCamCoord(camera, pos.x, pos.y, pos.z)
    SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)
end

--- Where the camera is looking, out to 5km.
---@return vector3|nil
function SKFreecam.raycast()
    if not camera then return nil end
    local hit, _, endCoords = lib.raycast.fromCamera(511, 4, 5000.0)
    if not hit then return nil end
    return endCoords
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then SKFreecam.stop() end
end)

exports('StartFreecam', SKFreecam.start)
exports('StopFreecam', SKFreecam.stop)
exports('IsFreecamEnabled', SKFreecam.isEnabled)
exports('GetFreecamHeading', SKFreecam.getHeading)
exports('SetFreecamPosition', SKFreecam.setPosition)
