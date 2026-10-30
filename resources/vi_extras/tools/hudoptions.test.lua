-- Headless check of HUD OPTIONS (vi_hudoptions/client.lua): a tap of the camera button changes the
-- view and opens nothing, half a second opens the menu and puts the view back, up / down / accept
-- move and change rows, back closes it, and it draws where single player's numbers put it.
-- Run from the resource folder:   lua tools/hudoptions.test.lua
local fails, total = 0, 0
local function ok(c, msg) total = total + 1 if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.01) end

local function source(path)
    if io and io.open then
        local f = io.open(path, 'rb')
        if not f then return nil end
        local s = f:read('a') f:close()
        return s
    end
    return readfile(path)
end
-- ox_lib's require: 'vi_hudoptions.options' is vi_hudoptions/options.lua, loaded once
local loaded = {}
function require(name)
    if loaded[name] == nil then
        local path = name:gsub('%.', '/') .. '.lua'
        loaded[name] = assert(load(assert(source(path), path), '@' .. path))() or true
    end
    return loaded[name]
end

-- the game
local clock, threads, frameDraws = 0, {}, nil
local pressed, disabled, viewMode, inVehicle = {}, {}, 1, false
local kvp, cmds, exported = {}, {}, {}
function GetGameTimer() return clock end
function CreateThread(f) threads[#threads + 1] = { co = coroutine.create(f), at = clock } end
function Wait(ms) coroutine.yield(ms or 0) end
function RegisterCommand(n, f) cmds[n] = f end
function AddEventHandler() end
function GetCurrentResourceName() return 'vi_extras' end
function GetResourceState(r) return r == 'vice_hud' and 'started' or 'missing' end
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
exports = setmetatable({}, { __call = function(_, name, fn) exported[name] = fn end, __index = function() return nil end })
cache = { ped = 1 }
function PlayerPedId() return 1 end
function IsPedInAnyVehicle() return inVehicle end
function GetFollowPedCamViewMode() return viewMode end
function SetFollowPedCamViewMode(m) viewMode = m end
function GetFollowVehicleCamViewMode() return viewMode end
function SetFollowVehicleCamViewMode(m) viewMode = m end
for _, n in ipairs({ 'IsPauseMenuActive', 'IsNuiFocused', 'IsScreenFadedOut', 'IsScreenFadingOut', 'IsCutsceneActive',
                     'IsPlayerSwitchInProgress', 'IsHudHidden' }) do _G[n] = function() return false end end
function IsControlPressed(_, c) return pressed[c] == true and not disabled[c] end
function IsDisabledControlPressed(_, c) return pressed[c] == true end
function DisableControlAction(_, c) disabled[c] = true end
function GetAspectRatio() return 16 / 9 end
function GetRenderedCharacterHeight() return 0.05 end
local text = {}
function SetTextFont(f) text.font = f end
function SetTextScale(_, s) text.scale = s end
function SetTextColour(r, g, b, a) text.c = { r, g, b, a } end
function SetTextJustification(j) text.j = j end
function SetTextWrap(_, x) text.wrap = x end
function BeginTextCommandDisplayText() text.s = nil end
function AddTextComponentSubstringPlayerName(s) text.s = s end
function EndTextCommandDisplayText(x, y)
    if frameDraws then frameDraws.texts[#frameDraws.texts + 1] = { s = text.s, x = x, y = y, c = text.c, j = text.j, scale = text.scale, font = text.font } end
    text = {}
end
function DrawRect(x, y, w, h, r, g, b, a)
    if frameDraws then frameDraws.rects[#frameDraws.rects + 1] = { x = x, y = y, w = w, h = h, c = { r, g, b, a } } end
end

-- three modules' rows (and the bridges', whose resources don't answer here, so they don't show)
local options = require 'vi_hudoptions.options'
options.add({ id = 'gunsonback', label = 'GUNS ON BACK', default = true })
options.add({ id = 'killcam', label = 'KILL CAMERA', default = true })
options.add({ id = 'camweight', label = 'CAMERA WEIGHT', default = false })
assert(load(assert(source('vi_hudoptions/client.lua')), '@vi_hudoptions/client.lua'))()

local function frame()
    disabled = {}
    frameDraws = { texts = {}, rects = {} }
    for _, t in ipairs(threads) do
        if coroutine.status(t.co) ~= 'dead' and clock >= t.at then
            local okr, ms = coroutine.resume(t.co)
            if not okr then error(ms) end
            t.at = clock + (ms or 0)
        end
    end
    clock = clock + 16
    return frameDraws
end
local function frames(n) local d for _ = 1, n do d = frame() end return d end
local function texts(d) local out = {} for _, t in ipairs(d.texts) do if t.c[1] ~= 0 or t.c[4] == 0 then out[#out + 1] = t.s end end return table.concat(out, ',') end

-- a tap: the view changes when the button comes up, the menu stays shut
pressed[0] = true frames(10) pressed[0] = nil
viewMode = 2 frames(5)
ok(exported.IsHudOptionsOpen() == false, 'a tap opens nothing')
ok(viewMode == 2, "a tap's view change stays")

-- a hold: open after half a second, the view put back when the game changes it on release
viewMode = 1
pressed[0] = true
frames(20)
ok(exported.IsHudOptionsOpen() == false, 'not open at 0.32 s')
local d = frames(15)
ok(exported.IsHudOptionsOpen() == true, 'open by 0.56 s')
ok(disabled[0] == true, 'the camera button is blocked while the hold is used')
pressed[0] = nil
viewMode = 2
d = frames(2)
ok(viewMode == 1, 'the view the hold left is put back')
ok(texts(d) == 'GUNS ON BACK,ON,KILL CAMERA,ON,CAMERA WEIGHT,OFF,HUD OPTIONS', 'rows, values and the title: ' .. texts(d))

-- single player's layout on a 1920 x 1080 screen: 1 unit = 1.6023738 px
local U = 1.6023738
local right = 1920 - 26 * U
local badges = {}
for _, r in ipairs(d.rects) do if near(r.w * 1920, 26 * U, 0.05) then badges[#badges + 1] = r end end
ok(#badges == 3, 'a badge per row')
local listH = 3 * 22 * U
local listTop = 1080 - 44 * U - (14 * U + 8 * U) - 8 * U - listH
-- DrawRect takes the centre
ok(near(badges[1].x * 1920, right - 13 * U, 0.05), 'badges against the right edge, 26 units in')
ok(near((badges[1].y - badges[1].h / 2) * 1080, listTop + (22 * U - 20 * U) / 2, 0.05), 'the first badge where single player puts it')
ok(near(badges[1].h * 1080, 20 * U, 0.05), 'badge as tall as cap + 7 units')
ok(badges[1].c[4] == 235 and badges[2].c[4] == 120, 'the chosen row light, the others dark')
local title
for _, t in ipairs(d.texts) do if t.s == 'HUD OPTIONS' and t.c[1] ~= 0 then title = t end end
ok(title and title.j == 2 and near(title.x * 1920, right, 0.05), 'HUD OPTIONS right-aligned to the edge')
ok(title and title.font == 4, "GTA's font 4")
local outlines = 0
for _, t in ipairs(d.texts) do if t.s == 'HUD OPTIONS' and t.c[1] == 0 then outlines = outlines + 1 end end
ok(outlines == 8, 'the title outlined eight ways, as single player')

-- down, accept: the second row changes and is saved
pressed[187] = true frames(1) pressed[187] = nil frames(1)
pressed[201] = true frames(1) pressed[201] = nil
d = frames(1)
ok(options.get('killcam') == false and kvp['vi_extras:killcam'] == 'false', 'down then accept switches KILL CAMERA off and saves it')
ok(texts(d):find('KILL CAMERA,OFF') ~= nil, 'and shows OFF')
pressed[188] = true frames(1) pressed[188] = nil frames(1)
pressed[188] = true frames(1) pressed[188] = nil frames(1)
pressed[201] = true frames(1) pressed[201] = nil frames(1)
ok(options.get('camweight') == true, 'up from the top goes round to the last row')

-- back closes it
pressed[202] = true frames(1) pressed[202] = nil
d = frames(1)
ok(exported.IsHudOptionsOpen() == false and #d.texts == 0, 'back closes it and nothing is drawn')

-- the pause menu's view of the same rows
local rows = exported.GetHudOptions()
ok(#rows == 3 and rows[2].id == 'killcam' and rows[2].value == 'OFF', 'GetHudOptions lists the rows with their values')
exported.StepHudOption('killcam', 1)
ok(options.get('killcam') == true, 'StepHudOption changes one')

-- the command opens it too
cmds.hudoptions()
ok(exported.IsHudOptionsOpen() == true, '/hudoptions opens it')

print(('%d/%d passed'):format(total - fails, total))
return fails == 0
