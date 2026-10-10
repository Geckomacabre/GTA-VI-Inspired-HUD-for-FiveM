--[[ ===========================================================================
     vi_wasted — client
     ---------------------------------------------------------------------------
     The WASTED and BUSTED screens from the fenix-police fork
     (github.com/Geckomacabre/fenix-police, client/client.lua), lifted out so a
     server can have them without the rest of it. The look and the numbers are
     that resource's: the stock death effect, slow motion, a camera that starts
     close behind and pulls back and up while drifting round, a red wash over
     the picture, and the bare word in Pricedown with no band behind it.

     What is NOT here is everything either screen leads to. fenix-police's
     arrest goes on to cuffs, a ride and a cell; here BUSTED is the screen and
     an event at the fade, and whoever called it decides what happens next.

     Public API:
         exports.vi_wasted:PlayWasted()
         exports.vi_wasted:PlayBusted({ coords = vector3, duration = ms, skippable = bool })
         exports.vi_wasted:IsPlaying()

     Events (client, local):
         vi_wasted:wastedFadedOut   the screen is black after WASTED
         vi_wasted:bustedFadedOut   the screen is black after BUSTED; it STAYS
                                    black until the caller fades it back in
     ========================================================================= ]]

local playing = false

-- FONT_STYLE_PRICEDOWN (font id 7), no background band: a scaleform is the
-- only thing that could draw a real band, and its band cannot be hidden.
local function drawBigWord(word, colour)
    SetTextFont(7)
    SetTextScale(1.35, 1.35)
    SetTextColour(colour[1], colour[2], colour[3], 255)
    SetTextCentre(true)
    SetTextDropShadow()
    SetTextEdge(2, 0, 0, 0, 160)
    SetTextEntry('STRING')
    AddTextComponentString(word)
    DrawText(0.5, 0.44)
end

local function drawSkipHint()
    SetTextFont(4)
    SetTextScale(0.42, 0.42)
    SetTextColour(255, 255, 255, 180)
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentString('Press ~b~SPACE~w~ to skip')
    DrawText(0.5, 0.88)
end

local function standingDown()
    local other = Config.StandDownFor
    return type(other) == 'string' and other ~= '' and GetResourceState(other) == 'started'
end

-- The shared cinematic. `at` is the point the camera circles. Timed on
-- GetNetworkTime, which slow motion does not stretch. Returns with the
-- scripted camera still up, so the caller can fade before dropping it.
local function cinematic(at, word, colour, duration, skippable)
    local ped = PlayerPedId()

    StartScreenEffect('DeathFailOut', 0, false)
    PlaySoundFrontend(-1, 'ScreenFlash', 'MissionFailedSounds', true)
    SetTimeScale(Config.TimeScale or 0.15)

    -- Starts close behind and to one side, ends further back and higher.
    local rad = math.rad(GetEntityHeading(ped) + 160.0)
    local startDist, endDist = 2.0, 6.0
    local startZ, endZ = 0.8, 3.0

    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    local startPos = at + vector3(math.sin(rad) * startDist, math.cos(rad) * startDist, startZ)
    SetCamCoord(cam, startPos.x, startPos.y, startPos.z)
    PointCamAtCoord(cam, at.x, at.y, at.z + 0.4)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 800, true, true)

    local wash = Config.Wash or { 160, 20, 20, 70 }
    local t0 = GetNetworkTime()
    local skipped = false
    while (GetNetworkTime() - t0) < duration and not skipped do
        local progress = (GetNetworkTime() - t0) / duration
        local ease = 1.0 - (1.0 - progress) * (1.0 - progress)

        if skippable then
            if IsDisabledControlJustPressed(0, 201) or IsDisabledControlJustPressed(0, 22) then
                skipped = true
            end
            drawSkipHint()
        end

        local dist = startDist + (endDist - startDist) * ease
        local z = startZ + (endZ - startZ) * ease
        local angle = rad + math.rad(15.0 * ease)
        local pos = at + vector3(math.sin(angle) * dist, math.cos(angle) * dist, z)
        SetCamCoord(cam, pos.x, pos.y, pos.z)
        PointCamAtCoord(cam, at.x, at.y, at.z + 0.3)

        DrawRect(0.5, 0.5, 1.0, 1.0, wash[1], wash[2], wash[3], wash[4])
        drawBigWord(word, colour)
        if skippable then DisableAllControlActions(0) end
        Wait(0)
    end

    SetTimeScale(1.0)
    StopScreenEffect('DeathFailOut')
    return cam
end

local function dropCam(cam)
    SetCamActive(cam, false)
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
end

local function guarded(name, body)
    if playing then return false end
    playing = true
    CreateThread(function()
        -- pcall round the cinematic itself: an error half way through would
        -- otherwise leave the game in slow motion behind a scripted camera.
        local ok, err = pcall(body)
        if not ok then
            print(('^1[vi_wasted]^7 %s errored: %s'):format(name, tostring(err)))
            SetTimeScale(1.0)
            StopScreenEffect('DeathFailOut')
            RenderScriptCams(false, false, 0, true, true)
            if IsScreenFadedOut() then DoScreenFadeIn(500) end
        end
        playing = false
    end)
    return true
end

local function playWasted()
    return guarded('WASTED', function()
        local cfg = Config.Wasted
        local cam = cinematic(GetEntityCoords(PlayerPedId()), cfg.word or 'wasted',
            cfg.colour or { 220, 40, 40 }, cfg.duration or 4000, false)

        DoScreenFadeOut(1000)
        while not IsScreenFadedOut() do Wait(50) end
        TriggerEvent('vi_wasted:wastedFadedOut')
        dropCam(cam)
        DoScreenFadeIn(1000)
        while not IsScreenFadedIn() do Wait(50) end
    end)
end

--- opts: { coords = where the camera circles (default: the player),
--- duration = ms, skippable = bool }. Ends on a black screen and fires
--- vi_wasted:bustedFadedOut; fading back in is the caller's, once it has put
--- the player wherever being busted puts them.
local function playBusted(opts)
    opts = type(opts) == 'table' and opts or {}
    return guarded('BUSTED', function()
        local cfg = Config.Busted
        local skippable = opts.skippable
        if skippable == nil then skippable = cfg.skippable ~= false end
        local cam = cinematic(opts.coords or GetEntityCoords(PlayerPedId()), cfg.word or 'busted',
            cfg.colour or { 70, 140, 230 }, tonumber(opts.duration) or cfg.duration or 6000, skippable)

        DoScreenFadeOut(1500)
        while not IsScreenFadedOut() do Wait(50) end
        dropCam(cam)
        TriggerEvent('vi_wasted:bustedFadedOut')
    end)
end

exports('PlayWasted', playWasted)
exports('PlayBusted', playBusted)
exports('IsPlaying', function() return playing end)

-- qbx_medical announces a death with this event; it is what fenix-police
-- listens for too, which is why this stands down while that is running.
AddEventHandler('qbx_medical:client:onPlayerDied', function()
    if not (Config.Wasted and Config.Wasted.auto) or standingDown() then return end
    playWasted()
end)

if Config.TestCommands then
    RegisterCommand('wasted', function() playWasted() end, false)
    RegisterCommand('busted', function()
        if playBusted() then
            -- Nothing else is listening in a test, so fade back in here.
            local handler
            handler = AddEventHandler('vi_wasted:bustedFadedOut', function()
                RemoveEventHandler(handler)
                DoScreenFadeIn(1000)
            end)
        end
    end, false)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not playing then return end
    SetTimeScale(1.0)
    StopScreenEffect('DeathFailOut')
    RenderScriptCams(false, false, 0, true, true)
    if IsScreenFadedOut() then DoScreenFadeIn(0) end
end)
