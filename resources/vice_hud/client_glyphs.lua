--[[ =========================================================================
     vice_hud — button glyphs

     One place that answers "which button is this, on the device the player
     is holding right now". Everything that draws a button (action prompts,
     the interact rows, the lockpick ring, the nitrous tip) asks here, so they
     cannot disagree with each other and they all follow a device swap.

     What the page is handed is a TOKEN plus the device it belongs to:

         pad    A B X Y  LB RB LT RT  LS RS (+ _UP _DOWN _LEFT _RIGHT _X _Y)
                DPAD (+ _UP _DOWN _LEFT _RIGHT _X _Y)  START BACK
         kbm    a key's own text ("E", "7"), a named key ("SHIFT", "SPACE"),
                an arrow (UP DOWN LEFT RIGHT) or a mouse button
                (LMB RMB MMB WHEEL_UP WHEEL_DOWN MOUSE4 ...)

     Pad tokens are always the Xbox NAMES. Whether "A" is drawn as an Xbox A
     or a PlayStation cross is the page's business, decided by the pad style:
     Config.PadGlyphs, or the player's own /hudpad choice.

     Loaded before client_overlays.lua and client.lua; deliberately a global
     table rather than locals, because client.lua sits right under Lua's
     200-locals-per-chunk ceiling.
     ========================================================================= ]]

ViceGlyphs = {}

-- GetControlInstructionalButton answers with "<kind>_<body>":
--   t_E      a key that is its own label
--   b_30     an icon, by index
-- and joins alternatives with '%'. The icon indices are the ones the game's
-- own INSTRUCTIONAL_BUTTONS movie draws -- the pad half is the table on
-- docs.fivem.net/docs/game-references/instructional-buttons, the keyboard
-- half the community-documented list of named keys.
local PAD_ICONS = {
    [4] = 'DPAD_UP', [5] = 'DPAD_DOWN', [6] = 'DPAD_LEFT', [7] = 'DPAD_RIGHT',
    [8] = 'DPAD', [9] = 'DPAD', [10] = 'DPAD_Y', [11] = 'DPAD_X',
    [12] = 'LS_UP', [13] = 'LS_DOWN', [14] = 'LS_LEFT', [15] = 'LS_RIGHT',
    [16] = 'LS', [17] = 'LS', [18] = 'LS_Y', [19] = 'LS_X', [20] = 'LS',
    [21] = 'RS_UP', [22] = 'RS_DOWN', [23] = 'RS_LEFT', [24] = 'RS_RIGHT',
    [25] = 'RS', [26] = 'RS', [27] = 'RS_Y', [28] = 'RS_X', [29] = 'RS',
    [30] = 'A', [31] = 'B', [32] = 'X', [33] = 'Y',
    [34] = 'LB', [35] = 'LT', [36] = 'RB', [37] = 'RT',
    [38] = 'START', [39] = 'BACK',
}

local KBM_ICONS = {
    [0] = 'UP', [1] = 'DOWN', [2] = 'LEFT', [3] = 'RIGHT',
    [100] = 'LMB', [101] = 'RMB', [102] = 'MMB',
    [103] = 'MOUSE4', [104] = 'MOUSE5', [105] = 'MOUSE6', [106] = 'MOUSE7', [107] = 'MOUSE8',
    [115] = 'WHEEL_UP', [116] = 'WHEEL_DOWN',
    [130] = 'NUM -', [131] = 'NUM +',
    [136] = 'NUM 0', [137] = 'NUM 1', [138] = 'NUM 2', [139] = 'NUM 3', [140] = 'NUM 4',
    [141] = 'NUM 5', [142] = 'NUM 6', [143] = 'NUM 7', [144] = 'NUM 8', [145] = 'NUM 9',
    [170] = 'F1', [171] = 'F2', [172] = 'F3', [173] = 'F4', [174] = 'F5', [175] = 'F6',
    [176] = 'F7', [177] = 'F8', [178] = 'F9', [179] = 'F10', [180] = 'F11', [181] = 'F12',
    [194] = 'UP', [195] = 'DOWN', [196] = 'LEFT', [197] = 'RIGHT',
    [198] = 'DEL', [199] = 'ESC', [200] = 'INS', [201] = 'END',
    [210] = 'DEL', [211] = 'INS', [212] = 'END',
    [1000] = 'SHIFT', [1001] = 'SHIFT', [1002] = 'TAB', [1003] = 'ENTER', [1004] = 'BKSP',
    [1008] = 'HOME', [1009] = 'PGUP', [1010] = 'PGDN', [1012] = 'CAPS',
    [1013] = 'CTRL', [1014] = 'CTRL', [1015] = 'ALT', [1016] = 'ALT',
    [1055] = 'HOME', [1056] = 'PGUP',
    [2000] = 'SPACE',
}

-- A key's own text is drawn as-is, so it has to be something the page's fonts
-- can draw. Anything that is not plain printable ASCII becomes a neutral
-- marker, and a bare multi-digit number is refused outright: that is an icon
-- index that lost its "b_", never a key (single digits stay -- 1-9 are keys).
local function keyText(str)
    if not str or str == '' then return nil end
    if #str > 1 and str:match('^%d+$') then return nil end
    for i = 1, #str do
        local b = str:byte(i)
        if b < 0x20 or b > 0x7E then return '•' end
    end
    return str
end

--- true while the last thing the player touched was a controller.
---
--- IS_USING_KEYBOARD_AND_MOUSE, not IsInputDisabled(2): with a controller
--- merely plugged in, the older check reported a pad and sent mouse prompts
--- down the pad branch. The fallback is for builds without the native.
function ViceGlyphs.usingPad()
    local ok, kbm = pcall(IsUsingKeyboardAndMouse, 2)
    if ok and kbm ~= nil then return not kbm end
    return not IsInputDisabled(2)
end

function ViceGlyphs.device()
    return ViceGlyphs.usingPad() and 'pad' or 'kbm'
end

--- "b_30" -> 'A', 'pad'      "t_E" -> 'E', 'kbm'      "b_1000" -> 'SHIFT', 'kbm'
--- The second result is the device the GLYPH belongs to, which is not always
--- the device in hand: a key mapping with no controller binding answers with
--- its keyboard key even on a pad, and must be drawn as that key rather than
--- as the pad button that happens to share its letter. nil when the kind
--- gives nothing away, so the caller falls back to the device in hand.
function ViceGlyphs.parse(raw)
    if type(raw) ~= 'string' or #raw < 3 then return nil end
    local first = raw:match('^[^%%]+') or raw
    local kind, body = first:sub(1, 2), first:sub(3)

    if kind == 'b_' then
        local n = tonumber(body)
        if not n then return nil end
        if PAD_ICONS[n] then return PAD_ICONS[n], 'pad' end
        if KBM_ICONS[n] then return KBM_ICONS[n], 'kbm' end
        return nil -- an icon nobody has named: the label alone, no button
    end

    local text = keyText(body)
    if not text then return nil end
    return text, ((kind == 't_' or kind == 'T_') and 'kbm' or nil)
end

-- INPUT_ATTACK / INPUT_AIM are what ox_target passes for its prompts. On
-- keyboard and mouse they are answered here rather than left to the native,
-- which has been seen to hand back a bare index for them.
local MOUSE_CONTROLS = { [24] = 'LMB', [25] = 'RMB' }

--- A control id (or an ox_lib keybind's .hash) -> token, device.
--- A string is a caller's own literal label and is passed through.
function ViceGlyphs.control(key)
    local device = ViceGlyphs.device()
    if type(key) == 'string' then return key, device end
    if type(key) ~= 'number' then return nil, device end

    if device == 'kbm' and MOUSE_CONTROLS[key] then return MOUSE_CONTROLS[key], 'kbm' end

    local ok, raw = pcall(GetControlInstructionalButton, 0, key, true)
    if not ok or not raw then return nil, device end
    local token, owner = ViceGlyphs.parse(raw)
    return token, owner or device
end

--- A RegisterKeyMapping command -> token, device. A mapping is asked for by
--- the hash of its command with the top bit set, in control group 2; group 0
--- with a plain control id cannot see it at all.
function ViceGlyphs.mapping(command)
    local device = ViceGlyphs.device()
    if type(command) ~= 'string' or command == '' then return nil, device end
    local ok, raw = pcall(GetControlInstructionalButton, 2, GetHashKey(command) | 0x80000000, true)
    if not ok or not raw then return nil, device end
    local token, owner = ViceGlyphs.parse(raw)
    return token, owner or device
end

-- =============================================================================
-- Pad style: Xbox or PlayStation
-- =============================================================================

local KVP_PAD = 'vice_hud:padGlyphs'

local function padStyleOf(value)
    local v = type(value) == 'string' and value:lower() or ''
    if v:find('^ps') or v:find('playstation', 1, true) or v:find('sony', 1, true)
        or v:find('dual', 1, true) then
        return 'ps'
    end
    if v:find('xbox', 1, true) or v == 'xb' or v == 'x' then return 'xbox' end
    return nil
end

local padStyle = padStyleOf(GetResourceKvpString(KVP_PAD))
    or padStyleOf(Config and Config.PadGlyphs) or 'xbox'

function ViceGlyphs.padStyle() return padStyle end

local styleListeners = {}

--- fn(style) runs when the player changes between Xbox and PlayStation
--- buttons, so anything that draws its own (the targeting rail) follows.
function ViceGlyphs.onPadStyle(fn)
    styleListeners[#styleListeners + 1] = fn
end

--- The player's own choice: 'xbox' or 'playstation' (any spelling
--- Config.PadGlyphs takes). Remembered for them, and drawn at once.
function ViceGlyphs.setPadStyle(value)
    local want = padStyleOf(value)
    if not want then return false end
    padStyle = want
    SetResourceKvp(KVP_PAD, want)
    ViceGlyphs.announce()
    for i = 1, #styleListeners do styleListeners[i](want) end
    return true
end

-- =============================================================================
-- Following the device in hand
-- =============================================================================

local listeners = {}
local lastDevice = nil

--- fn(device) runs whenever the player moves between pad and keyboard+mouse,
--- so whatever is on screen can re-resolve its buttons.
function ViceGlyphs.onDevice(fn)
    listeners[#listeners + 1] = fn
end

--- Tell the page which device and which pad style to draw. Safe to call at
--- any time; the page's uiReady calls it so a fresh page is never left on its
--- defaults.
function ViceGlyphs.announce()
    lastDevice = ViceGlyphs.device()
    SendNUIMessage({ action = 'inputDevice', device = lastDevice, pad = padStyle })
end

--- One look at the device in hand. If it is not the one the page was last
--- told about, the page is told and so is everything that asked to be.
function ViceGlyphs.poll()
    local device = ViceGlyphs.device()
    if device == lastDevice then return end
    ViceGlyphs.announce()
    for i = 1, #listeners do listeners[i](device) end
end

CreateThread(function()
    while true do
        Wait(250)
        ViceGlyphs.poll()
    end
end)

-- The server owner picks the default in config.lua; a player with the other
-- kind of controller picks their own here. Stored per player.
RegisterCommand('hudpad', function(_, args)
    if not ViceGlyphs.setPadStyle(args[1]) then
        print(('^3[vice_hud]^7 controller buttons: %s. Use /hudpad xbox or /hudpad playstation.')
            :format(padStyle == 'ps' and 'PlayStation' or 'Xbox'))
        return
    end
    print(('^2[vice_hud]^7 controller buttons: %s'):format(padStyle == 'ps' and 'PlayStation' or 'Xbox'))
end, false)
