-- vi_pausemenu on the mock: what the page is sent, what the settings do, the hand-off to the game's own screens.
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

-- the map: the game's own, with the header plain and the bars on
Nui.messages = {}
Header = {}
NuiCall('tile', { id = 'map' })
eq(LastMessage('hide') ~= nil, true, 'page hidden for the map')
eq(Nui.focus, false, 'focus dropped before the native menu')
eq(Pause.active, true, 'pause flag raised for the native menu')
eq(Frontend.menu, 'hash:FE_MENU_VERSION_MP_PAUSE', 'map menu')
Frames(3)
eq(Pause.active, true, 'not held shut while the map is up')
local m = LastMessage('map')
check(m and m.show == true and m.location == 'Vespucci Beach', 'map bars shown with the area')
eq(m and m.name, 'Lucia Caminos', "map bar has the character's name")
local shown = {}
for _, h in ipairs(Header) do shown[h[1]] = h end
check(shown.SHOW_MENU and shown.SHOW_MENU[2] == false, 'tabs hidden')
check(shown.SHOW_HEADING_DETAILS and shown.SHOW_HEADING_DETAILS[2] == false, 'player details hidden')
check(shown.SET_HEADER_TITLE and shown.SET_HEADER_TITLE[2] == '', 'header title blanked')
local n = #Header
Run(300)
check(#Header > n, 'header kept plain while the map is up')
Press(200)
Frames(1)
eq(LastMessage('open'), nil, 'ESC on the map is the map\'s')
-- backing out of the map
Frontend.ready = false
Frames(2)
eq(Frontend.kicked, 1, 'PauseMenuceptionTheKick on the way out')
eq(Pause.active, false, 'pause flag down again')
eq(LastMessage('map').show, false, 'map bars off')
eq(Nui.focus, true, 'focus back to the page')
open = LastMessage('open')
check(open and open.fresh == false and open.screen == 'home', 'page back at home, not fresh')

-- game settings from the settings screen: back to the settings screen
NuiCall('screen', { screen = 'settings' })
Nui.messages = {}
NuiCall('setting', { id = 'gamesettings' })
eq(Frontend.menu, 'hash:FE_MENU_VERSION_LANDING_MENU', 'game settings menu')
Frames(2)
Frontend.ready = false
Frames(2)
open = LastMessage('open')
check(open and open.screen == 'settings', 'back on the settings screen')
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

eq(#Errors, 0, 'no thread errors')
io.write(('%d passed, %d failed\n'):format(passes, fails))
Result = fails
