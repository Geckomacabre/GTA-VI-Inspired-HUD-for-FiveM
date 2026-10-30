--[[ ===========================================================================
     vi_hudoptions — HUD OPTIONS (hold V)
     ---------------------------------------------------------------------------
     Single player's settings menu, as it draws it (GTA6Hud's
     ViDrawSettingsPanel): hold the camera button for half a second (V, or the
     back / view button on a pad) and a column of switches comes up at the
     bottom right, each name with its value in a small box, a line, and HUD
     OPTIONS under it. Up / down choose a row, Enter / A changes it, Backspace /
     B (or holding the camera button again) closes it. A tap of the camera
     button still changes the view: a hold that opened the menu puts back the
     view the game moved to.

     The rows come from vi_hudoptions/options.lua: every module adds its own,
     and bridges.lua adds the ones whose feature lives in another resource
     (vice_hud's crosshair, vi_radio's wheel...), shown only while it runs.

     Public API:
         exports.vi_extras:GetHudOptions()         -- { { id, label, value, desc, values? }, ... }
         exports.vi_extras:StepHudOption(id, dir)  -- next value (1) or the one before (-1)
         exports.vi_extras:SetHudOption(id, value)
         exports.vi_extras:IsHudOptionsOpen()
         /hudoptions                               -- open or close it
     ========================================================================= ]]

local config = require 'vi_hudoptions.config'
local options = require 'vi_hudoptions.options'
require 'vi_hudoptions.bridges'

-- ---------------------------------------------------------------------------
-- Exports: vi_pausemenu's Settings page lists the same rows
-- ---------------------------------------------------------------------------
exports('GetHudOptions', function()
    local out = {}
    for _, row in ipairs(options.list()) do
        out[#out + 1] = { id = row.id, label = row.label, value = options.label(row.id), desc = row.desc, stepped = row.values ~= nil }
    end
    return out
end)
exports('StepHudOption', function(id, dir) options.step(id, tonumber(dir) or 1) end)
exports('SetHudOption', function(id, value) options.set(id, value) end)

if not config.enabled then
    exports('IsHudOptionsOpen', function() return false end)
    return
end

local open = false
local index = 1         -- the chosen row, 1-based
local top = 1           -- the first row on screen when the list scrolls
exports('IsHudOptionsOpen', function() return open end)

-- ---------------------------------------------------------------------------
-- Drawing, in single player's numbers
-- ---------------------------------------------------------------------------
-- Single player draws on a 1080-high canvas as wide as the screen's aspect;
-- its reference units are 1080 / 674 px.
local CANVAS_H = 1080.0
local UNIT = 1.6023738
local function U(v) return v * UNIT end

local canvasW = CANVAS_H * 16 / 9
local function refreshCanvas() canvasW = CANVAS_H * GetAspectRatio(false) end

-- GTA's text scale for a given cap height: single player's ScaleForCapHeight.
local charHeight = nil
local function scaleFor(cap)
    charHeight = charHeight or GetRenderedCharacterHeight(1.0, config.font)
    if charHeight < 0.0001 then return 0.5 end
    return cap / 674.0 / config.capToLine / charHeight
end

-- Where a line of text starts so its capitals' top sits at capTop.
local function textTop(capTop, cap) return U(capTop - cap / config.capToLine * config.topPad) end

local JUSTIFY = { center = 0, left = 1, right = 2 }

local function drawOne(s, x, y, scale, r, g, b, a, justify)
    SetTextFont(config.font)
    SetTextScale(1.0, scale)
    SetTextColour(r, g, b, a)
    SetTextJustification(justify)
    if justify == 2 then SetTextWrap(0.0, x / canvasW) end
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(s)
    EndTextCommandDisplayText(x / canvasW, y / CANVAS_H)
end

-- Single player's outline: the text eight times in black around itself,
-- max(1, 0.1 cap) units out, then the text.
local function drawText(s, x, y, cap, c, align, outline)
    local scale = scaleFor(cap)
    local justify = JUSTIFY[align]
    if outline and c[4] > 8 then
        local o = math.max(U(1), U(cap * 0.1))
        for i = 0, 7 do
            local a = i * math.pi / 4
            drawOne(s, x + math.cos(a) * o, y + math.sin(a) * o, scale, 0, 0, 0, c[4], justify)
        end
    end
    drawOne(s, x, y, scale, c[1], c[2], c[3], c[4], justify)
end

local function rect(x, y, w, h, c)
    DrawRect((x + w * 0.5) / canvasW, (y + h * 0.5) / CANVAS_H, w / canvasW, h / CANVAS_H, c[1], c[2], c[3], c[4])
end

local function draw(rows)
    local col = config.colours
    local n = #rows
    local shown = math.min(n, config.visibleRows)
    if index < top then top = index end
    if index >= top + shown then top = index - shown + 1 end
    top = math.max(1, math.min(n - shown + 1, top))

    local rowH = U(config.rowH)
    local cap = config.cap
    local badgeW = U(config.badgeW)
    local right = canvasW - U(config.right)
    local listH = shown * rowH
    local ruleGap = U(config.ruleGap)
    local listTop = CANVAS_H - U(config.bottom) - (U(config.titleCap) + ruleGap) - ruleGap - listH
    local labelX = right - badgeW - U(config.badgeGap)
    local badgeX = right - badgeW

    for i = 0, shown - 1 do
        local at = top + i
        local row = rows[at]
        local chosen = at == index
        local y = listTop + i * rowH
        local textY = textTop(0, cap) + y + (rowH - U(cap)) * 0.5
        drawText(row.label, labelX, textY, cap, chosen and col.text or col.dim, 'right', true)
        rect(badgeX, y + (rowH - U(cap + 7)) * 0.5, badgeW, U(cap + 7), chosen and col.badgeOn or col.badgeOff)
        drawText(options.label(row.id), badgeX + badgeW * 0.5, textY, cap - 1, chosen and col.textSelected or col.dim, 'center', false)
    end

    if n > shown then
        local barX, barW = right + U(5), U(2)
        rect(barX, listTop, barW, listH, col.track)
        rect(barX, listTop + listH * (top - 1) / n, barW, listH * shown / n, col.rule)
    end

    local ruleY = listTop + listH + ruleGap
    local ruleW = U(config.ruleW)
    rect(right - ruleW, ruleY, ruleW, U(1), col.rule)
    drawText('HUD OPTIONS', right, textTop(0, config.titleCap) + ruleY + ruleGap, config.titleCap, col.text, 'right', true)
end

-- ---------------------------------------------------------------------------
-- Holding the camera button, as single player reads it
-- ---------------------------------------------------------------------------
-- What blocks the menu: the pause menu, an NUI page with focus (inventory,
-- phone, vi_pausemenu), a fade, a cutscene, a character switch, the HUD
-- hidden, and the kill camera's shot (single player won't open it then).
local function killCamPlaying()
    local ok, playing = pcall(function() return exports.vi_extras:IsKillCamPlaying() end)
    return ok and playing == true
end
local function blocked()
    return IsPauseMenuActive() or IsNuiFocused() or IsScreenFadedOut() or IsScreenFadingOut()
        or IsCutsceneActive() or IsPlayerSwitchInProgress() or IsHudHidden() or killCamPlaying()
end

local function viewMode(inVehicle)
    if inVehicle then return GetFollowVehicleCamViewMode() end
    return GetFollowPedCamViewMode()
end
local function setViewMode(inVehicle, mode)
    if inVehicle then SetFollowVehicleCamViewMode(mode) else SetFollowPedCamViewMode(mode) end
end

-- While the menu is up: no shooting, aiming, phone or weapon wheel, so the
-- arrows and Enter only move and change rows.
local BLOCKED_CONTROLS = { 24, 25, 257, 263, 264, 140, 141, 142, 143, 37, 27, 172, 173, 174, 175, 176, 177, 199, 200 }

local held, holdUsed, heldFor = false, false, 0.0
local tapMode, tapVehicle = nil, false
local restoreUntil = 0
local navHeld, toggleHeld, closeHeld = false, false, false

local function close() open = false end

local function frame(dt)
    local ped = cache.ped or PlayerPedId()
    if blocked() then
        held, heldFor, open = false, 0.0, false
        return
    end
    if config.replacesInteractionMenu then DisableControlAction(0, 244, true) end

    local inVehicle = IsPedInAnyVehicle(ped, false)
    local pressed = IsControlPressed(0, config.control) or IsDisabledControlPressed(0, config.control)
    if pressed then
        if not held then
            tapMode, tapVehicle = viewMode(inVehicle), inVehicle
        end
        heldFor = heldFor + dt
        if not holdUsed and heldFor >= config.holdSeconds then
            open = not open
            index, top = 1, 1
            holdUsed = true
            if open then refreshCanvas() end
        end
        if holdUsed then DisableControlAction(0, config.control, true) end
    else
        -- the game changes the view when the button comes up: a hold that
        -- opened or closed the menu puts it back for the next 300 ms
        if held and holdUsed then restoreUntil = GetGameTimer() + 300 end
        heldFor, holdUsed = 0.0, false
    end
    if not pressed and GetGameTimer() < restoreUntil and tapVehicle == inVehicle and tapMode and viewMode(inVehicle) ~= tapMode then
        setViewMode(inVehicle, tapMode)
    end
    held = pressed

    if not open then return end
    local rows = options.list()
    if #rows == 0 then close() return end
    if index > #rows then index = #rows end

    DisableControlAction(0, 202, true)
    local closing = IsDisabledControlPressed(0, 202)
    if closing and not closeHeld then
        closeHeld = true
        close()
        return
    end
    closeHeld = closing

    for _, c in ipairs(BLOCKED_CONTROLS) do DisableControlAction(0, c, true) end
    DisableControlAction(0, 188, true)
    DisableControlAction(0, 187, true)
    local up, down = IsDisabledControlPressed(0, 188), IsDisabledControlPressed(0, 187)
    if (up or down) and not navHeld then
        index = index + (down and 1 or -1)
        if index < 1 then index = #rows end
        if index > #rows then index = 1 end
    end
    navHeld = up or down

    DisableControlAction(0, 201, true)
    local toggle = IsDisabledControlPressed(0, 201)
    if toggle and not toggleHeld then options.step(rows[index].id, 1) end
    toggleHeld = toggle

    draw(rows)
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        local now = GetGameTimer()
        -- single player caps a frame's step at 0.1 s
        frame(math.min(0.1, (now - last) / 1000.0))
        last = now
        -- every frame: a hold is timed from the frame the button goes down,
        -- and the menu's controls are blocked frame by frame
        Wait(0)
    end
end)

RegisterCommand('hudoptions', function()
    open = not open
    index, top = 1, 1
    if open then refreshCanvas() end
end, false)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then open = false end
end)
