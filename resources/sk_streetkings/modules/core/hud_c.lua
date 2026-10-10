-- Native HUD primitives, styled to match ox_lib.
--
-- StreetKings drew every gameplay readout (nitrous bar, gear indicator, rampage
-- score, drift score, stunt results, speed camera flash, zone banner) through
-- its own NUI page. That page is part of the standalone gamemode's UI shell and
-- is not carried over, so those readouts are redrawn here with natives instead.
--
-- Menus, dialogs, prompts and toasts do NOT live here — those use ox_lib
-- directly (lib.registerContext / lib.inputDialog / lib.alertDialog /
-- lib.showTextUI / lib.notify), so they inherit the server's ox_lib theme for
-- free. This file only covers the persistent overlays ox_lib has no widget for.
--
-- Palette below is the single place to retheme. Values track ox_lib's default
-- dark theme, with the server's loadscreen accent (#f1e542) as the highlight.
--
-- ── Screen real estate ──────────────────────────────────────────────────────
-- um_hud owns the bottom-right corner and renders as NUI, which composites
-- ABOVE anything drawn with natives — so anything placed there is invisible.
-- Keep this region clear:
--
--   speedometer   right: 12vh, bottom: 5vh   (20vh x 20vh)
--   status bars   right: 3vh,  bottom: 0
--   ammo          right: 6vw,  bottom: 4vh
--
-- Roughly x > 0.78, y > 0.72 in screen space. Widgets below therefore live in
-- the bottom-centre and upper-right bands, which um_hud leaves free.

SKHud = {}

--- Shared anchors, so widgets stay consistent and out of um_hud's corner.
SKHud.Anchor = {
    bottomCentre     = { x = 0.500, y = 0.890 }, -- drift / rampage score
    bottomCentreLeft = { x = 0.325, y = 0.930 }, -- nitrous gauge
    bottomCentreGear = { x = 0.435, y = 0.930 }, -- gear indicator
    topRight         = { x = 0.880, y = 0.120 }, -- standings / racer lists
    centreLow        = { x = 0.500, y = 0.780 }, -- run timer
}

SKHud.Palette = {
    panel      = { 37,  38,  43,  200 }, -- ox_lib surface  #25262b
    panelDark  = { 26,  27,  30,  225 }, -- ox_lib darker   #1a1b1e
    text       = { 193, 194, 197, 255 }, -- ox_lib text     #c1c2c5
    textDim    = { 144, 146, 150, 255 }, -- ox_lib dimmed   #909296
    accent     = { 241, 229, 66,  255 }, -- server accent   #f1e542
    success    = { 64,  192, 87,  255 }, -- ox_lib green.6  #40c057
    danger     = { 250, 82,  82,  255 }, -- ox_lib red.6    #fa5252
    warning    = { 253, 126, 20,  255 }, -- ox_lib orange.6 #fd7e14
    info       = { 34,  139, 230, 255 }, -- ox_lib blue.6   #228be6
}

local P = SKHud.Palette

-- ── Primitives ──────────────────────────────────────────────────────────────

---@param x number screen-space centre X (0-1)
---@param y number screen-space centre Y (0-1)
---@param w number width (0-1)
---@param h number height (0-1)
---@param color number[]|nil rgba, defaults to the panel colour
function SKHud.Panel(x, y, w, h, color)
    local c = color or P.panel
    DrawRect(x, y, w, h, c[1], c[2], c[3], c[4] or 255)
end

---@param text string
---@param x number
---@param y number
---@param scale number
---@param color number[]|nil
---@param centre boolean|nil
---@param font integer|nil
function SKHud.Text(text, x, y, scale, color, centre, font)
    local c = color or P.text
    SetTextFont(font or 4)
    SetTextScale(0.0, scale)
    SetTextColour(c[1], c[2], c[3], c[4] or 255)
    if centre then SetTextCentre(true) end
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

--- Horizontal fill bar with a dark track, used for the nitrous gauge.
---@param x number centre X
---@param y number centre Y
---@param w number full width
---@param h number height
---@param fill number 0.0-1.0
---@param color number[]|nil fill colour
function SKHud.Bar(x, y, w, h, fill, color)
    fill = math.max(0.0, math.min(1.0, fill or 0.0))
    SKHud.Panel(x, y, w + 0.003, h + 0.005, P.panelDark)
    if fill <= 0.0 then return end
    local c = color or P.accent
    -- Grow from the left edge: shrink the width and shift the centre with it.
    DrawRect(x - (w * 0.5) + (w * fill * 0.5), y, w * fill, h, c[1], c[2], c[3], c[4] or 255)
end

--- Big centred text, used for countdowns and run results.
---@param text string
---@param color number[]|nil
---@param y number|nil defaults to 0.4
function SKHud.BigCentre(text, color, y)
    local c = color or P.accent
    SetTextFont(7)
    SetTextScale(0.0, 3.0)
    SetTextColour(c[1], c[2], c[3], c[4] or 255)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, y or 0.4)
end

--- Full-screen colour wash, used for the speed camera flash.
---@param color number[]
---@param alpha integer
function SKHud.ScreenWash(color, alpha)
    DrawRect(0.5, 0.5, 1.0, 1.0, color[1], color[2], color[3], alpha)
end

-- ── Widget registry ─────────────────────────────────────────────────────────
--
-- Modules register a draw function once, then push data to it. A single render
-- thread runs only while at least one widget holds data, so an idle player pays
-- nothing.

local widgets = {} -- id -> { draw = fun(data), data = table|nil }
local activeCount = 0
local renderRunning = false

local function startRenderLoop()
    if renderRunning then return end
    renderRunning = true
    CreateThread(function()
        while activeCount > 0 do
            for _, widget in pairs(widgets) do
                if widget.data then
                    widget.draw(widget.data)
                end
            end
            Wait(0)
        end
        renderRunning = false
    end)
end

---@param id string
---@param draw fun(data: table)
function SKHud.register(id, draw)
    widgets[id] = { draw = draw, data = nil }
end

--- Push data to a widget, making it visible. Pass nil to hide it.
---@param id string
---@param data table|nil
function SKHud.set(id, data)
    local widget = widgets[id]
    if not widget then return end

    local wasActive = widget.data ~= nil
    widget.data = data

    if data and not wasActive then
        activeCount = activeCount + 1
        startRenderLoop()
    elseif not data and wasActive then
        activeCount = activeCount - 1
    end
end

---@param id string
function SKHud.clear(id)
    SKHud.set(id, nil)
end

function SKHud.clearAll()
    for id in pairs(widgets) do SKHud.clear(id) end
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then SKHud.clearAll() end
end)

-- SKFormatTime / SKFormatMoney live in shared/format_sh.lua so the server can
-- use the same formatting in its notifications.
