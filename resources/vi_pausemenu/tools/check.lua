-- vi_pausemenu on the mock: what the page is sent, what the settings do, the map's data, the hand-off to the game's own screens, a pad.
local fails, passes = 0, 0
local function check(cond, what)
    if cond then passes = passes + 1 else fails = fails + 1 io.write('FAIL: ' .. what .. '\n') end
end
local function eq(a, b, what)
    check(a == b, what .. ' (got ' .. tostring(a) .. ', want ' .. tostring(b) .. ')')
end
local function find(rows, key, value)
    for _, r in ipairs(rows or {}) do if r[key] == value then return r end end
end
local function ids(rows)
    local t = {}
    for _, r in ipairs(rows) do t[#t + 1] = r.id or r.label end
    return table.concat(t, ',')
end

Run(2500)
eq(#Errors, 0, 'no thread errors at start')
eq(CrashCam, 'untouched', 'crash camera left alone when never turned off')
check(ServerCalls[1] and ServerCalls[1][1] == 'vi_pausemenu:server:requestPlayers', 'server name asked for at the start')

-- the game's own menu is held shut every frame
Pause.active = true
Frames(1)
eq(Pause.active, false, "game's own pause menu kept shut")

-- ESC opens it
Press(200)
Frames(2)
eq(StateBag.pauseMenuOpen, true, 'pauseMenuOpen set')
eq(Nui.focus, true, 'NUI focus on')
eq(Blur, 1, 'screen blurred')
local open = LastMessage('open')
check(open ~= nil, 'open message sent')
eq(open.fresh, true, 'first open is fresh')
eq(open.screen, 'home', 'opens at home')
eq(open.name, 'Lucia Caminos', "character's first and last name")
eq(open.title, 'Upstate Mafia', "title is the server's name")
eq(open.mode, 'ONLINE', 'mode line')
eq(open.footer.day, 'Saturday', 'day of the week')
eq(open.footer.time, '09:05', 'time')
eq(open.footer.cash, '$1,250', 'cash')
eq(open.footer.bank, '$48,900', 'bank')
eq(#open.tiles, 3, 'three rows')
eq(ids(open.tiles[1]), 'map,brief', 'top row')
eq(ids(open.tiles[2]), 'stats,editor,game,settings', 'middle row')
eq(ids(open.tiles[3]), 'players,report,disconnect', 'bottom row without Discord (no invite set)')
eq(open.tiles[1][1].sub, 'Vespucci Beach', 'map tile names the area')
eq(open.tiles[1][2].sub, 'Mechanic', 'brief tile names the job')
eq(open.tiles[2][2].sub, 'Record a clip', 'editor tile line')
eq(open.tiles[3][1].sub, '2 Online', 'players count')
check(Disabled[200] ~= nil, 'ESC kept from the game while open')

-- the character's face: a headshot of the player's ped, held only until the page has its own copy
local mug = LastMessage('mugshot')
check(mug and mug.txd == 'pedmugshot_01', 'face sent to the page')
eq(Headshot.held, true, 'slot held until the page has copied the face')
Run(300)
eq(Headshot.held, true, 'still held while the page is copying')
NuiCall('mugshot', { ok = true })
Frames(2)
eq(Headshot.held, false, 'slot let go once the page has the copy')
eq(Headshot.unregistered, 1, 'let go once')

-- a second ESC press while open does nothing on the Lua side (the page has the keys)
local before = #Nui.messages
Press(200)
Frames(1)
eq(#Nui.messages, before, 'no second open')

-- money with more digits
PlayerData.money = { cash = 100000, bank = 1234567 }
Run(1100)
local f = LastMessage('footer').footer
eq(f.cash, '$100,000', 'six-digit cash')
eq(f.bank, '$1,234,567', 'seven-digit bank')
PlayerData.money = { cash = 5, bank = 0 }
Run(1100)
eq(LastMessage('footer').footer.cash, '$5', 'one-digit cash')

-- settings
local s = NuiCall('screen', { screen = 'settings' })
eq(s.title, 'Settings', 'settings title')
eq(ids(s.rows), 'crashcam,mapmode,minimap,radio,style,keybinds,gamesettings', 'settings rows')
eq(find(s.rows, 'id', 'crashcam').value, 'On', 'crash camera on by default')
eq(find(s.rows, 'id', 'mapmode').value, 'Auto', 'map mode from gen7_map')
eq(find(s.rows, 'id', 'minimap').value, 'Off', 'map in vehicle only: off while the minimap shows on foot')
eq(find(s.rows, 'id', 'radio').value, 'On', 'radio on while not muted')
eq(find(s.rows, 'id', 'style').value, 'GTA VI', 'pause menu style')
eq(find(s.rows, 'id', 'keybinds').action, true, 'key bindings opens something')

local r = NuiCall('setting', { id = 'mapmode', dir = 1 })
eq(MapMode, 'day', 'map mode on one')
eq(find(r.rows, 'id', 'mapmode').value, 'Day', 'rows come back changed')
NuiCall('setting', { id = 'mapmode', dir = -1 })
NuiCall('setting', { id = 'mapmode', dir = -1 })
eq(MapMode, 'night', 'map mode back round past auto')
NuiCall('setting', { id = 'crashcam', dir = 1 })
eq(Kvp['vi_pausemenu:crashcam'], 'off', 'crash camera off remembered')
eq(CrashCam, false, 'crash camera told')
NuiCall('setting', { id = 'minimap', dir = 1 })
eq(MinimapOnFoot, false, 'map in vehicle only: on hides it on foot')
NuiCall('setting', { id = 'radio', dir = -1 })
eq(Muted, true, 'radio off mutes')

-- a resource not running: its row goes
ResourceStates.vi_radio = nil
s = NuiCall('screen', { screen = 'settings' })
check(find(s.rows, 'id', 'radio') == nil, 'radio row gone without vi_radio')
ResourceStates.vi_radio = 'started'
-- a running resource without the export (an older gen7_map): its row goes, no error
local getMode = exports.gen7_map.GetMapMode
exports.gen7_map.GetMapMode = nil
s = NuiCall('screen', { screen = 'settings' })
check(find(s.rows, 'id', 'mapmode') == nil, 'map mode row gone without the export')
exports.gen7_map.GetMapMode = getMode

-- the crash camera is set again when vi_crashcam restarts
CrashCam = 'untouched'
TriggerEvent('onClientResourceStart', 'vi_crashcam')
Run(600)
eq(CrashCam, false, 'crash camera off re-applied on restart')

-- brief, stats, players
local b = NuiCall('screen', { screen = 'brief' })
eq(find(b.rows, 'label', 'Name').value, 'Lucia Caminos', 'brief name')
eq(find(b.rows, 'label', 'Job').desc, 'Grade: Apprentice', 'brief grade')
eq(find(b.rows, 'label', 'On Duty').value, 'Yes', 'brief duty')
eq(find(b.rows, 'label', 'Hunger').value, '82%', 'brief hunger')
eq(find(b.rows, 'label', 'Server ID').value, '7', 'brief server id')
local st = NuiCall('screen', { screen = 'stats' })
eq(#st.rows, #Config.Skills, 'a row per skill')
eq(st.rows[1].value, '42 / 100', 'stamina level')
eq(st.rows[1].bar, 0.42, 'stamina bar')
check(st.rows[1].desc:find('30%% of the way to level 43') ~= nil, 'stamina progress line: ' .. st.rows[1].desc)
eq(find(st.rows, 'label', 'Wheelie').desc, 'Raised by riding on one wheel.', 'maxed skill has no progress line')
local p = NuiCall('screen', { screen = 'players' })
eq(ids(p.rows), 'Player3,Player7', 'players by id')
eq(p.rows[1].value, '#3', 'player id shown')
-- someone joins while the list is up
Nui.messages = {}
TriggerEvent('vi_pausemenu:client:setPlayers', { { id = 9, name = 'Nova' }, { id = 3, name = 'Player3' } })
local live = LastMessage('list')
check(live and ids(live.rows) == 'Player3,Nova', 'players list follows joins while up')
NuiCall('screen', { screen = 'home' })
Nui.messages = {}
TriggerEvent('vi_pausemenu:client:setPlayers', { { id = 3, name = 'Player3' } })
eq(LastMessage('list'), nil, 'no list sent while another screen is up')

-- the server's name: sv_hostname when there is no sv_projectName, without its colour codes; a new one goes to the
-- page while it is up, the same one does not
Convars.sv_projectName = nil
Convars.sv_hostname = ' ^1Upstate ^7Mafia! '
Nui.messages = {}
TriggerServerEvent('vi_pausemenu:server:requestPlayers')
local t = LastMessage('title')
eq(t and t.title, 'Upstate Mafia!', 'hostname without colour codes, sent while open')
Nui.messages = {}
TriggerServerEvent('vi_pausemenu:server:requestPlayers')
eq(LastMessage('title'), nil, 'no title message when the name has not changed')
Convars.sv_projectName = 'Upstate Mafia'
TriggerServerEvent('vi_pausemenu:server:requestPlayers')

-- the map: single player's, on the page; the game's own menu stays shut
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
check(MapSprites[1] == 1 and MapSprites[2] == 40 and MapSprites[3] == 374, "sprites in single player's order")
check(not has(MapSprites, 2), 'sprite 2 has no picture, so it is not looked for')
Blips = {
    [1] = { { 100.2, 200.7, 2, 3 }, { 110, 210, 5, 5 } },      -- a dot the big map shows, a minimap-only one
    [52] = { { 25.7, -1347.3, 4 }, { -48, -1757, 4 }, { 1163, -323, 4 } },
    [110] = { { 20, -1106, 3 } },
    [361] = {},
    [6] = { { 0, 0, 4 } },                                      -- the player's own arrow
    [2] = { { 5, 5, 4 } },                                      -- a sprite without a picture
}
for i = 1, 301 do Blips[361][i] = { i, -i, 4 } end
Nui.messages = {}
local reply = NuiCall('tile', { id = 'map' })
local m = reply and reply.map
check(m ~= nil, 'the map comes up with what it needs')
eq(Nui.focus, true, "the page keeps the focus: the map is the page's own")
eq(LastMessage('hide'), nil, 'the page is not hidden for it')
eq(Frontend.menu, nil, "no game menu for the map")
Frames(2)
eq(Pause.active, false, "the game's own pause menu still held shut")
eq(reply.mode, 'ONLINE', 'map mode line from the config')
eq(reply.name, 'Lucia Caminos', "map has the character's name")
eq(reply.safezone, 0.95, "the game's safe zone, for the map's frame")
check(m.me.x == -1200.0 and m.me.y == -1500.0 and m.me.h == 90.0, 'where the player is and which way they face')
eq(m.wp, false, 'no waypoint yet')
local bl = m.blips
eq(#bl, 4 * (1 + 3 + 1 + 300), 'blips the big map shows, 300 of a sprite at most')
check(bl[1] == 100 and bl[2] == 201 and bl[3] == 1 and bl[4] == 93 * 65536 + 182 * 256 + 229,
    'a plain dot to the metre, in its own colour')
local sprites = {}
for i = 3, #bl, 4 do sprites[#sprites + 1] = bl[i] end
check(sprites[2] == 52 and sprites[5] == 361 and sprites[#sprites] == 110,
    "then the legend's kinds in single player's order (stores, gas stations, ..., Ammu-Nation)")
eq(bl[8], 0, 'other sprites carry no colour')
check(not has(sprites, 6) and not has(sprites, 2) and not has(sprites, 8), "never the player's arrow or a sprite without a picture")

-- every 100 ms the player and the waypoint, every 400 ms the blips too
Nui.messages = {}
Run(1000)
local withBlips, without = 0, 0
for _, msg in ipairs(Nui.messages) do
    if msg.type == 'mapdata' then
        if msg.map.blips then withBlips = withBlips + 1 else without = without + 1 end
    end
end
check(withBlips >= 2 and withBlips <= 3, 'blips about every 400 ms (' .. withBlips .. ')')
check(withBlips + without >= 7 and withBlips + without <= 10, 'the player about every 100 ms (' .. (withBlips + without) .. ')')
Press(200)
Frames(1)
eq(LastMessage('open'), nil, "ESC on the map is the page's")

-- the waypoint, set and taken off from the page
NuiCall('waypoint', { x = 250.5, y = -800.25 })
check(Waypoint and Waypoint[1] == 250.5 and Waypoint[2] == -800.25, 'waypoint set where the page asked')
eq(Sounds[#Sounds], 'WAYPOINT_SET', 'with the waypoint sound')
Run(150)
local d = LastMessage('mapdata')
check(d and d.map.wp and d.map.wp.x == 250.5 and d.map.wp.y == -800.25, 'the waypoint goes back to the page')
Nui.messages = {}
Run(500)
local scanned, eights = 0, 0
for _, msg in ipairs(Nui.messages) do
    if msg.type == 'mapdata' and msg.map.blips then
        scanned = scanned + 1
        for i = 3, #msg.map.blips, 4 do if msg.map.blips[i] == 8 then eights = eights + 1 end end
    end
end
check(scanned > 0 and eights == 0, 'the waypoint is not one of the blips')
NuiCall('waypoint', { off = true })
eq(Waypoint, false, 'waypoint taken off')
eq(Sounds[#Sounds], 'BACK', 'with the back sound')
NuiCall('waypoint', { x = 'here' })
eq(Waypoint, false, 'no waypoint from nonsense')

-- the area under the cursor
eq(NuiCall('mapzone', { x = 100, y = 200 }).zone, 'Vespucci Beach', 'the area under the cursor')
eq(ZoneAsked[3], 40.0, "asked at single player's height")
eq(NuiCall('mapzone', { x = -3500, y = 0 }).zone, '', 'no name out at sea')
eq(NuiCall('mapzone', {}).zone, '', 'nothing asked, nothing named')

-- back to the tiles: the map's data stops
NuiCall('screen', { screen = 'home' })
Frames(2)
Nui.messages = {}
Run(500)
eq(LastMessage('mapdata'), nil, 'no map data once it is down')
Blips = {}

-- game settings from the settings screen: back to the settings screen
NuiCall('screen', { screen = 'settings' })
Nui.messages = {}
NuiCall('setting', { id = 'gamesettings' })
eq(Frontend.menu, 'hash:FE_MENU_VERSION_LANDING_MENU', 'game settings menu')
eq(LastMessage('hide') ~= nil, true, "page hidden for the game's menu")
eq(Nui.focus, false, "focus dropped before the game's menu")
eq(Pause.active, true, "pause flag raised for the game's menu")
Frames(3)
eq(Pause.active, true, "not held shut while the game's menu is up")
Frontend.ready = false
Frames(2)
eq(Nui.focus, true, 'focus back to the page')
eq(Frontend.kicked, 1, 'PauseMenuceptionTheKick on the way out')
eq(Pause.active, false, 'pause flag down again')
open = LastMessage('open')
check(open and open.fresh == false and open.screen == 'settings', 'back on the settings screen, not fresh')
local list = LastMessage('list')
check(list and list.screen == 'settings' and #list.rows == 7, 'settings rows sent again')
NuiCall('setting', { id = 'keybinds' })
eq(Frontend.menu, 'hash:FE_MENU_VERSION_LANDING_KEYMAPPING_MENU', 'key bindings menu')
Frames(2)
Frontend.ready = false
Frames(2)
NuiCall('screen', { screen = 'home' })

-- a native menu that will not open: the page comes back
local activate = ActivateFrontendMenu
ActivateFrontendMenu = function() error('no') end
Nui.messages = {}
NuiCall('tile', { id = 'game' })
eq(Pause.active, false, 'pause flag down after a failed open')
eq(Nui.focus, true, 'focus back after a failed open')
check(LastMessage('open') ~= nil, 'page shown again after a failed open')
ActivateFrontendMenu = activate

-- the Rockstar Editor: record, then save
NuiCall('tile', { id = 'editor' })
eq(Recording, true, 'recording started')
eq(StateBag.pauseMenuOpen, false, 'menu closed to record')
Run(400)
Press(200)
Frames(2)
open = LastMessage('open')
eq(open.tiles[2][2].sub, 'Stop and save', 'editor tile while recording')
NuiCall('tile', { id = 'editor' })
eq(Recording, false, 'recording stopped')
eq(Saved, 1, 'clip saved')
eq(LastMessage('tiles').tiles[2][2].sub, 'Record a clip', 'editor tile updated')

-- report: to the console without a webhook, once a minute
NuiCall('report', { category = 'Bug', subject = '  Car in wall ', text = ' near the pier ' })
local printed = Printed[#Printed] or ''
check(printed:find('%[Bug%] Car in wall: near the pier') ~= nil, 'report printed: ' .. printed)
local count = #Printed
NuiCall('report', { category = 'Bug', subject = 'again', text = 'again' })
eq(#Printed, count, 'second report within a minute dropped')
local calls = #ServerCalls
NuiCall('report', { category = 'Bug', subject = '   ', text = 'x' })
eq(#ServerCalls, calls, 'empty subject not sent')
-- with a webhook (another player, so not rate limited)
Config.Report.Webhook = 'https://example.invalid/hook'
source = 3
TriggerEvent('vi_pausemenu:server:report', 'Player', 'Subject', 'Text')
source = 0
eq(#Http, 1, 'webhook posted')
eq(Http[1].body.embeds[1].title, '[Player] Subject', 'embed title')
eq(Http[1].body.embeds[1].footer.text, 'Player3 (id 3)', 'embed names the reporter')
-- not strings: ignored
source = 4
TriggerEvent('vi_pausemenu:server:report', 'Player', nil, {})
source = 0
eq(#Http, 1, 'bad report ignored')

-- disconnect
NuiCall('disconnect')
eq(StateBag.pauseMenuOpen, false, 'menu closed on disconnect')
eq(Dropped[1] and Dropped[1][1], 7, 'the player who chose it is dropped')

-- close, and the cooldown before ESC opens it again
Run(400)
Press(200)
Frames(2)
eq(StateBag.pauseMenuOpen, true, 'opened again')
NuiCall('close')
eq(Nui.focus, false, 'focus off on close')
eq(Blur, 0, 'blur faded out')
Frames(2)
Press(200)
Frames(1)
eq(StateBag.pauseMenuOpen, false, 'the ESC that closed it does not reopen it')
Run(400)
Press(199)
Frames(2)
eq(StateBag.pauseMenuOpen, true, 'P opens it too')

-- classic: the game's own menu back, this one closed; /pausemenu brings it back
NuiCall('setting', { id = 'style', dir = 1 })
eq(Kvp['vi_pausemenu:style'], 'classic', 'classic remembered')
Run(300)
eq(StateBag.pauseMenuOpen, false, 'menu closed for classic')
Pause.active = true
Run(300)
eq(Pause.active, true, "game's own menu left alone in classic")
Press(200)
Frames(2)
eq(StateBag.pauseMenuOpen, false, 'ESC does not open this one in classic')
Commands.pausemenu()
eq(Kvp['vi_pausemenu:style'], 'vi', '/pausemenu brings it back')
Run(300)
eq(Pause.active, false, "game's own menu held shut again")

-- a tile whose resource is down is left out; a title in the config wins over the server's name
NuiCall('close')
ResourceStates.vice_hud = nil
Config.Title = 'Fixed Title'
Run(400)
Press(200)
Frames(2)
eq(ids(LastMessage('open').tiles[2]), 'editor,game,settings', 'no Stats tile without vice_hud')
eq(LastMessage('open').title, 'Fixed Title', 'Config.Title wins')
ResourceStates.vice_hud = 'started'
Config.Title = ''
NuiCall('close')

-- without qbx_core: the player's name, no money, a brief of blanks
ResourceStates.qbx_core = nil
Run(400)
Press(200)
Frames(2)
open = LastMessage('open')
eq(open.name, 'GeckoClient', 'name without qbx_core')
eq(open.footer.cash, '$0', 'cash without qbx_core')
b = NuiCall('screen', { screen = 'brief' })
eq(find(b.rows, 'label', 'Job').value, 'Unemployed', 'brief without qbx_core')

-- the resource stopping while open
TriggerEvent('onResourceStop', 'vi_pausemenu')
eq(StateBag.pauseMenuOpen, false, 'flag cleared when the resource stops')
eq(Nui.focus, false, 'focus off when the resource stops')

-- the face, when things go wrong: a page that never answers, and a headshot the game refuses
Run(6000)
eq(Headshot.held, false, 'slot let go even when the page never answers')
local before = Headshot.registered
Run(400)
Press(200)
Frames(2)
eq(Headshot.registered, before + 1, 'a new face each time the menu opens')
Run(5200)
eq(Headshot.held, false, 'let go after the wait for an answer')
NuiCall('close')
Headshot.valid = false
Nui.messages = {}
Run(400)
Press(200)
Frames(3)
eq(LastMessage('mugshot'), nil, 'no face sent when the game refuses one')
eq(Headshot.held, false, 'a refused headshot let go at once')
eq(Headshot.registered, Headshot.unregistered, 'every headshot let go')

-- a pad: its presses reach the page as the keys it knows, not the press that opened it
local function Pads()
    local out = {}
    for i = 1, #Nui.messages do
        if Nui.messages[i].type == 'pad' then out[#out + 1] = Nui.messages[i].button end
    end
    return table.concat(out, ',')
end
NuiCall('close')
Run(400)
UsingPad = true
Nui.messages = {}
Press(199)
Frames(2)
eq(Nui.focus, true, 'Start opens it')
eq(Pads(), '', 'and the press that opened it is not also a press in it')
Run(400)
Nui.messages = {}
Press(201)
Frames(1)
Press(173)
Frames(1)
eq(Pads(), 'accept,down', 'cross and the D-pad reach the page')
Nui.messages = {}
for _ = 1, 40 do PadHeld[175] = true Tick(16) end
local held = Pads()
eq(held:sub(1, 5), 'right', 'a held direction is a press at once')
eq(select(2, held:gsub('right', '')) >= 3, true, 'and repeats while it is held')
Nui.messages = {}
Stick.y = -0.9
Frames(1)
Stick.y = 0.0
eq(Pads(), 'up', 'the left stick moves too')
Nui.messages = {}
UsingPad = false
Press(201)
Frames(1)
eq(Pads(), '', 'nothing from the pad thread while the keyboard is in use')
UsingPad = true
Press(202)
Frames(1)
eq(Pads(), 'back', 'circle goes back')

-- on the map: square, triangle, LB and RB too, and the stick and the triggers as they stand
local function Axes()
    for i = #Nui.messages, 1, -1 do
        local msg = Nui.messages[i]
        if msg.type == 'padaxes' then return ('%g %g %g %g'):format(msg.x, msg.y, msg.lt, msg.rt) end
    end
end
NuiCall('tile', { id = 'map' })
Nui.messages = {}
for _, c in ipairs({ 203, 204, 205, 206, 201 }) do
    Press(c)
    Frames(1)
end
eq(Pads(), 'alt,center,lb,rb,accept', 'square, triangle, LB, RB and cross reach the map')
Nui.messages = {}
Stick.x, Stick.y = 0.8, -0.333
for _ = 1, 30 do Tick(16) end
eq(Pads(), '', 'the stick is not a direction on the map')
eq(Axes(), '0.8 -0.33 0 0', 'the stick goes to the map as it stands')
local sent = 0
for _, msg in ipairs(Nui.messages) do if msg.type == 'padaxes' then sent = sent + 1 end end
eq(sent, 1, 'and only when it changes')
Stick.x, Stick.y = 0.1, 0.12
Frames(1)
eq(Axes(), '0 0 0 0', "inside single player's dead zone it is nothing")
Stick.rt = 0.6
Frames(1)
eq(Axes(), '0 0 0 0.6', 'RT zooms in')
Stick.lt, Stick.rt = 0.05, 0.08
Frames(1)
eq(Axes(), '0 0 0 0', 'both triggers barely pressed is nothing')
Stick.x, Stick.y, Stick.lt, Stick.rt = -1.0, 0.0, 0.0, 0.0
Frames(1)
eq(Axes(), '-1 0 0 0', 'the stick again')
UsingPad = false
Frames(1)
eq(Axes(), '0 0 0 0', 'let go when the keyboard takes over')
UsingPad = true
Stick.x = 0.0
NuiCall('screen', { screen = 'home' })
Nui.messages = {}
Press(205)
Frames(1)
Stick.y = 0.9
Frames(1)
Stick.y = 0.0
eq(Pads(), 'down', 'back at the tiles: no LB, and the stick is a direction again')
UsingPad = false
NuiCall('close')

eq(#Errors, 0, 'no thread errors')
io.write(('%d passed, %d failed\n'):format(passes, fails))
Result = fails
