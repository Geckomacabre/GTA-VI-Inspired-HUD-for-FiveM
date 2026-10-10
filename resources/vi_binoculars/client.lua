--[[ ===========================================================================
     vi_binoculars — client
     ---------------------------------------------------------------------------
     Binoculars: raise them, look around, zoom smoothly, lower them.

     The view is a scripted camera at the ped's eyes that the player turns
     with the mouse or the right stick; the ped turns with it, so what other
     players see is someone scanning with binoculars, not a statue. Zoom is
     the mouse wheel, or d-pad up / down on a controller, and is eased so it
     glides instead of stepping. The further in, the slower the view turns
     and the more the hands show.

     The ped can walk with them up (Config.Move): forward is wherever the
     binoculars point.

     With vice_hud running, the lens mask, the ZOOM and EXIT prompts and the
     label (what is being looked at) are its own. Without it the game's stock
     binocular overlay is drawn instead.

     Public API:
         exports.vi_binoculars:Use()        -- raise, or lower if they are up
         exports.vi_binoculars:Stop()
         exports.vi_binoculars:IsActive()
         exports.vi_binoculars:GetZoom()    -- 0 (wide) .. 1 (fully in)
         exports.vi_binoculars:GetVision()  -- 'normal' | 'night' | 'thermal'
         exports.vi_binoculars:SetLabel(text, key)
               names what is being looked at, bottom left; `key` (a control
               id) draws its button beside it. nil clears it.
         exports.vi_binoculars:GetTarget(maxDistance)
               -> hit, coords, entity   what the centre of the view is on

     Events (client, local):  vi_binoculars:started   vi_binoculars:stopped
     ========================================================================= ]]

local CONTROL_LOOK_LR, CONTROL_LOOK_UD = 1, 2
local CONTROL_PAD_ZOOM_IN, CONTROL_PAD_ZOOM_OUT = 172, 173   -- d-pad up / down
local CONTROL_WHEEL_UP, CONTROL_WHEEL_DOWN = 241, 242
-- Moving: the two axes, and the four keys a keyboard feeds them from.
local CONTROLS_MOVE = { 30, 31, 32, 33, 34, 35 }
local CONTROL_EXIT = 194                                -- Backspace / B
local CONTROL_VISION_PREV, CONTROL_VISION_NEXT = 174, 175   -- Left / Right
local CONTROL_PUSH_TO_TALK = 249

local PROMPT_ZOOM, PROMPT_EXIT = 'vi_binoculars:zoom', 'vi_binoculars:exit'
local PROMPT_VISION = 'vi_binoculars:vision'

local active = false
local cam = nil
local zoom, zoomTarget = 0.0, 0.0
local heading, pitch = 0.0, 0.0
local label, labelKey = nil, nil
local hudOverlay = false
local scaleform = nil
local vision = 'normal'
local prop = nil             -- the binoculars in the ped's hand, while it can walk
local promptDevice = nil     -- which device the ZOOM prompt was last drawn for

-- Plain first, then whichever of night and thermal config.lua turns on.
local function visionModes()
    local modes = { 'normal' }
    local v = Config.Vision
    if type(v) == 'table' then
        if v.night then modes[#modes + 1] = 'night' end
        if v.thermal then modes[#modes + 1] = 'thermal' end
    end
    return modes
end

local function setVision(mode)
    vision = mode
    SetNightvision(mode == 'night')
    SetSeethrough(mode == 'thermal')
end

-- Only undone if it was changed here, so goggles another script switched on
-- are left alone.
local function clearVision()
    if vision ~= 'normal' then setVision('normal') end
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function usingKeyboard()
    local ok, kbm = pcall(IsUsingKeyboardAndMouse, 2)
    if ok and kbm ~= nil then return kbm end
    return IsInputDisabled(2)
end

-- Zoom is spread evenly by RATIO, not by degrees: half way along is the
-- geometric middle of the two fields of view. A linear spread spends almost
-- all of its travel at the wide end and then lurches in.
local function fovAt(z)
    return Config.FovWide * (Config.FovNarrow / Config.FovWide) ^ z
end

local function hudRunning()
    return GetResourceState('vice_hud') == 'started'
end

-- The ZOOM prompt names what zooms on the device in hand: the wheel, or d-pad up.
local function zoomKey()
    if usingKeyboard() then return 'WHEEL_UP' end
    return CONTROL_PAD_ZOOM_IN
end

local function showZoomPrompt()
    promptDevice = usingKeyboard()
    pcall(function() exports.vice_hud:ShowActionPrompt(PROMPT_ZOOM, 'Zoom', zoomKey()) end)
end

local function pushOverlay()
    if not hudOverlay then return end
    pcall(function()
        exports.vice_hud:SetBinocularOverlay(true, { label = label, key = labelKey })
    end)
end

local function startOverlay()
    hudOverlay = false
    if hudRunning() then
        hudOverlay = pcall(function()
            exports.vice_hud:SetBinocularOverlay(true, { label = label, key = labelKey })
            exports.vice_hud:ShowActionPrompt(PROMPT_EXIT, 'Exit', CONTROL_EXIT)
            exports.vice_hud:ShowActionPrompt(PROMPT_ZOOM, 'Zoom', zoomKey())
            promptDevice = usingKeyboard()
            if #visionModes() > 1 then
                exports.vice_hud:ShowActionPrompt(PROMPT_VISION, 'Vision', CONTROL_VISION_NEXT)
            end
        end)
    end
    if not hudOverlay then
        -- The stock overlay, for a server without vice_hud (or with an older
        -- one that has no binocular mask).
        scaleform = RequestScaleformMovie('BINOCULARS')
        local deadline = GetGameTimer() + 1500
        while not HasScaleformMovieLoaded(scaleform) and GetGameTimer() < deadline do Wait(0) end
    end
end

local function stopOverlay()
    if hudOverlay then
        pcall(function()
            exports.vice_hud:SetBinocularOverlay(false)
            exports.vice_hud:HideActionPrompt(PROMPT_ZOOM)
            exports.vice_hud:HideActionPrompt(PROMPT_EXIT)
            exports.vice_hud:HideActionPrompt(PROMPT_VISION)
        end)
        hudOverlay = false
    end
    if scaleform then
        SetScaleformMovieAsNoLongerNeeded(scaleform)
        scaleform = nil
    end
end

-- Not the moment for binoculars.
local function blockedReason(ped)
    if IsEntityDead(ped) then return 'dead' end
    if IsPedInAnyVehicle(ped, false) and not Config.AllowInVehicle then return 'in a vehicle' end
    if IsPedSwimming(ped) or IsPedSwimmingUnderWater(ped) then return 'in water' end
    if IsPedFalling(ped) or IsPedRagdoll(ped) or IsPedInParachuteFreeFall(ped) then return 'falling' end
    if IsPedCuffed(ped) then return 'cuffed' end
    if IsPauseMenuActive() then return 'paused' end
    return nil
end

local function hasItem()
    local item = Config.Item
    if not item or item == '' then return true end
    if GetResourceState('ox_inventory') == 'started' then
        local ok, count = pcall(function() return exports.ox_inventory:Search('count', item) end)
        if ok then return (tonumber(count) or 0) > 0 end
    end
    -- No inventory to ask: the item only matters through server.lua's usable
    -- item, and the command stays open.
    return true
end

local function stop()
    if not active then return end
    active = false   -- the loop below sees this and unwinds
end

local function canMove()
    return Config.Move ~= false and type(Config.Anim) == 'table'
end

local function playingAnim(ped)
    return IsEntityPlayingAnim(ped, Config.Anim.dict, Config.Anim.name, 3)
end

-- Up to the face. Walking: an upper-body animation and the prop, so the legs
-- are free. Standing: the game's own stance, which brings its own prop.
local function raise(ped)
    if not canMove() then
        if Config.Scenario then TaskStartScenarioInPlace(ped, Config.Scenario, 0, true) end
        return
    end

    local anim = Config.Anim
    RequestAnimDict(anim.dict)
    local deadline = GetGameTimer() + 1500
    while not HasAnimDictLoaded(anim.dict) and GetGameTimer() < deadline do Wait(0) end
    -- 51: looped, upper body only, and the player keeps control of the legs.
    TaskPlayAnim(ped, anim.dict, anim.name, 5.0, 5.0, -1, 51, 0.0, false, false, false)

    if anim.prop then
        local model = GetHashKey(anim.prop)
        RequestModel(model)
        deadline = GetGameTimer() + 1500
        while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
        if HasModelLoaded(model) then
            local at = GetEntityCoords(ped)
            prop = CreateObject(model, at.x, at.y, at.z, true, true, false)
            AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, anim.bone or 28422),
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(model)
        end
    end
end

local function lower(ped)
    if prop then
        if DoesEntityExist(prop) then DeleteEntity(prop) end
        prop = nil
    end
    if IsEntityDead(ped) then return end

    if canMove() then
        StopAnimTask(ped, Config.Anim.dict, Config.Anim.name, 2.0)
    elseif Config.Scenario and not IsPedInAnyVehicle(ped, false) then
        ClearPedTasks(ped)
    end
end

local function run()
    local ped = PlayerPedId()
    active = true
    zoom, zoomTarget = 0.0, 0.0
    heading = GetEntityHeading(ped)
    pitch = clamp(GetGameplayCamRelativePitch(), Config.PitchMin, Config.PitchMax)

    if not IsPedInAnyVehicle(ped, false) then raise(ped) end

    -- The plain scripted camera, which goes only where it is told. The FLY
    -- camera moves itself with the triggers and the sticks -- the same inputs
    -- that zoom and look here -- and floated off into the sky with them.
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local at0, turn0 = GetEntityCoords(ped), math.rad(heading)
    SetCamCoord(cam, at0.x - math.sin(turn0) * Config.EyeForward, at0.y + math.cos(turn0) * Config.EyeForward, at0.z + Config.EyeUp)
    SetCamRot(cam, pitch, 0.0, heading, 2)
    SetCamFov(cam, fovAt(0.0))
    if (Config.Sway or 0) > 0 then ShakeCam(cam, 'HAND_SHAKE', Config.Sway * 0.4) end
    RenderScriptCams(true, false, 0, true, false)
    startOverlay()
    TriggerEvent('vi_binoculars:started')

    -- Per z-unit, the field of view changes by Wide * ln(Wide / Narrow) degrees
    -- at the wide end; ZoomSpeed is given in degrees per second there.
    local zoomRate = Config.ZoomSpeed / (Config.FovWide * math.log(Config.FovWide / Config.FovNarrow))
    local modes, modeAt = visionModes(), 1

    while active do
        ped = PlayerPedId()
        if blockedReason(ped) then break end

        local onFoot = not IsPedInAnyVehicle(ped, false)
        local walking = onFoot and canMove()

        DisableAllControlActions(0)
        EnableControlAction(0, CONTROL_PUSH_TO_TALK, true)
        if walking then
            for i = 1, #CONTROLS_MOVE do EnableControlAction(0, CONTROLS_MOVE[i], true) end
            SetPedMaxMoveBlendRatio(ped, Config.MoveSpeed or 1.0)
            -- Something else may have taken the arms (a stumble, another script).
            if not playingAnim(ped) then
                TaskPlayAnim(ped, Config.Anim.dict, Config.Anim.name, 5.0, 5.0, -1, 51, 0.0, false, false, false)
            end
        end
        if IsDisabledControlJustPressed(0, CONTROL_EXIT) then break end

        -- The prompt follows the device: the wheel on a mouse, the d-pad on a pad.
        if hudOverlay and promptDevice ~= usingKeyboard() then showZoomPrompt() end

        local dt = GetFrameTime()
        local fov = fovAt(zoom)
        local fine = fov / Config.FovWide      -- 1 at the wide end, small when zoomed in

        -- look
        local lx = GetDisabledControlNormal(0, CONTROL_LOOK_LR)
        local ly = GetDisabledControlNormal(0, CONTROL_LOOK_UD)
        if usingKeyboard() then
            heading = heading - lx * Config.LookSpeedMouse * fine
            pitch = pitch - ly * Config.LookSpeedMouse * fine
        else
            heading = heading - lx * Config.LookSpeedPad * dt * fine
            pitch = pitch - ly * Config.LookSpeedPad * dt * fine
        end
        heading = heading % 360.0
        pitch = clamp(pitch, Config.PitchMin, Config.PitchMax)

        -- zoom: stepped on the mouse wheel, held on d-pad up / down. Each only
        -- on its own device: the same controls are other keys on the other one.
        if usingKeyboard() then
            if IsDisabledControlJustPressed(0, CONTROL_WHEEL_UP) then zoomTarget = zoomTarget + Config.WheelStep end
            if IsDisabledControlJustPressed(0, CONTROL_WHEEL_DOWN) then zoomTarget = zoomTarget - Config.WheelStep end
        else
            local held = GetDisabledControlNormal(0, CONTROL_PAD_ZOOM_IN) - GetDisabledControlNormal(0, CONTROL_PAD_ZOOM_OUT)
            zoomTarget = zoomTarget + held * zoomRate * dt
        end
        zoomTarget = clamp(zoomTarget, 0.0, 1.0)
        zoom = zoom + (zoomTarget - zoom) * math.min(1.0, Config.Smoothing * dt)

        -- vision: Right steps on, Left steps back, round the list
        if #modes > 1 then
            local step = (IsDisabledControlJustPressed(0, CONTROL_VISION_NEXT) and 1 or 0)
                - (IsDisabledControlJustPressed(0, CONTROL_VISION_PREV) and 1 or 0)
            if step ~= 0 then
                modeAt = (modeAt - 1 + step) % #modes + 1
                setVision(modes[modeAt])
            end
        end

        -- Standing still, the ped turns with the view. Walking, its legs take
        -- it where the stick says, and "forward" is kept meaning where the
        -- binoculars point: movement is steered off the game's own camera,
        -- which is held on the view's heading behind the scenes.
        local moving = walking and (math.abs(GetControlNormal(0, 30)) > 0.15 or math.abs(GetControlNormal(0, 31)) > 0.15)
        if walking then
            SetGameplayCamRelativeHeading(((heading - GetEntityHeading(ped) + 540.0) % 360.0) - 180.0)
            SetGameplayCamRelativePitch(pitch, 1.0)
        end
        if onFoot and not moving then SetEntityHeading(ped, heading) end

        -- The view sits at the eyes, looking where it is turned rather than
        -- where the body faces.
        local at = GetEntityCoords(ped)
        local turn = math.rad(heading)
        SetCamCoord(cam, at.x - math.sin(turn) * Config.EyeForward, at.y + math.cos(turn) * Config.EyeForward, at.z + Config.EyeUp)
        SetCamRot(cam, pitch, 0.0, heading, 2)
        SetCamFov(cam, fovAt(zoom))
        if (Config.Sway or 0) > 0 then
            SetCamShakeAmplitude(cam, Config.Sway * (0.4 + 0.6 * zoom))
        end

        -- Its own body and the prop in its hands would fill the frame.
        SetEntityLocallyInvisible(ped)
        if prop then SetEntityLocallyInvisible(prop) end
        HideHudAndRadarThisFrame()
        if scaleform and HasScaleformMovieLoaded(scaleform) then
            DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)
        end

        Wait(0)
    end

    active = false
    clearVision()
    stopOverlay()
    RenderScriptCams(false, false, 0, true, false)
    if cam then DestroyCam(cam, false) cam = nil end
    lower(PlayerPedId())
    TriggerEvent('vi_binoculars:stopped')
end

local function use()
    if active then stop() return true end
    local ped = PlayerPedId()
    if blockedReason(ped) then return false end
    CreateThread(function()
        local ok, err = pcall(run)
        if not ok then
            print('^1[vi_binoculars]^7 ' .. tostring(err))
            active = false
            clearVision()
            stopOverlay()
            RenderScriptCams(false, false, 0, true, false)
            if cam then DestroyCam(cam, false) cam = nil end
            pcall(lower, PlayerPedId())
        end
    end)
    return true
end

exports('Use', use)
exports('Stop', stop)
exports('IsActive', function() return active end)
exports('GetZoom', function() return active and zoom or 0.0 end)
exports('GetVision', function() return active and vision or 'normal' end)

exports('SetLabel', function(text, key)
    label = (text ~= nil and text ~= '') and tostring(text) or nil
    labelKey = label and key or nil
    if active then pushOverlay() end
end)

--- What the centre of the view is on: hit (bool), coords (vector3), entity.
exports('GetTarget', function(maxDistance)
    if not active or not cam then return false, nil, 0 end
    local from = GetCamCoord(cam)
    local rot = GetCamRot(cam, 2)
    local rz, rx = math.rad(rot.z), math.rad(rot.x)
    local dir = vector3(-math.sin(rz) * math.cos(rx), math.cos(rz) * math.cos(rx), math.sin(rx))
    local to = from + dir * (tonumber(maxDistance) or 600.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(
        from.x, from.y, from.z, to.x, to.y, to.z, -1, PlayerPedId(), 4)
    local _, hit, coords, _, entity = GetShapeTestResult(ray)
    return hit == 1 or hit == true, coords, entity or 0
end)

-- The inventory item (server.lua for qbx_core / qb-core; ox_inventory calls
-- the export named in its item definition).
RegisterNetEvent('vi_binoculars:use', function() use() end)
exports('useItem', function() use() end)

local function fromCommand()
    if not active and not hasItem() then
        print('^3[vi_binoculars]^7 you are not carrying binoculars.')
        return
    end
    use()
end

if Config.Command then
    RegisterCommand(Config.Command, fromCommand, false)
end
if Config.Key then
    local command = Config.Command or 'vi_binoculars_toggle'
    if not Config.Command then RegisterCommand(command, fromCommand, false) end
    RegisterKeyMapping(command, 'Binoculars', 'keyboard', Config.Key)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not active then return end
    active = false
    clearVision()
    stopOverlay()
    RenderScriptCams(false, false, 0, true, false)
    if cam then DestroyCam(cam, false) end
    lower(PlayerPedId())
end)
