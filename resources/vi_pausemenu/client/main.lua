--[[
    vi_pausemenu - the pause menu as GTA VI's.

    ESC, P or a pad's Start opens a grid of picture tiles over the blurred game (html/): the map, a brief of the
    character, stats, the Rockstar Editor, the game's own settings, this server's settings, the players, a report to
    staff, Discord and disconnecting, with the day and time, the cash and the bank under it. Settings, Brief, Stats,
    Players and Report are GTA VI's settings screen - a list on the left, a picture and a line about the row on the
    right.

    How it takes over the game's own menu is gk_pausemenu's (_Retired/gk_pausemenu, which ran on this server): the
    game's menu is kept shut with SetPauseMenuActive(false) every frame - except while one of its own screens is
    handed the stage - and the key is caught as a control press, not by watching that flag (the two fight over the
    same flag every frame and the watcher loses). The game's settings and the key bindings are the game's own screens
    (ActivateFrontendMenu), entered with this page's focus dropped and left back to it when the player backs out.

    The map is single player's (FBICat's GTA6Hud pause map), drawn by the page with its art: this side tells the page
    where the player is, the waypoint and the blips, names the area under its cursor and sets the waypoint.

    LocalPlayer.state.pauseMenuOpen is true while it is up: vice_hud hides its minimap frame then.
]]

local open = false          -- this page is up
local openedAt = 0          -- when it last came up, or came back from one of the game's own screens
local screen = 'home'       -- what it shows: home, the map, or a list (settings, brief, stats, players, report)
local nativeOpen = false    -- one of the game's own screens has taken over (settings, key bindings)
local closedAt = 0
local style = GetResourceKvpString(Config.StyleKvp) or 'vi'
local players = {}          -- the server's list: { id, name }
local serverName = ''       -- the server's sv_projectName, sent with that list

-- =============================================================================
-- What the page shows
-- =============================================================================
local DAYS = { [0] = 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday' }

local function PlayerData()
    if GetResourceState('qbx_core') ~= 'started' then return nil end
    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    return ok and type(pd) == 'table' and pd or nil
end

local function Money(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return '$' .. out:gsub('^,', '')
end

-- a place as the game names its area ("Vespucci Beach"); empty where it has no name
local function Zone(x, y, z)
    local zone = GetLabelText(GetNameOfZone(x, y, z))
    return (zone == 'NULL' or zone == nil) and '' or zone
end

-- where the player is
local function Location()
    local c = GetEntityCoords(PlayerPedId())
    return Zone(c.x, c.y, c.z)
end

-- a native by whichever name this build has it, else by its hash
local function Native(names, hash, ...)
    for i = 1, #names do
        local f = _G[names[i]]
        if type(f) == 'function' then return f(...) end
    end
    return Citizen.InvokeNative(hash, ...)
end

local function Recording()
    local r = Native({ 'IsReplayRecording', 'IsRecording' }, 0x1897CA71995A90B4)
    return r == true or r == 1
end

local function Footer()
    local pd = PlayerData()
    local money = pd and pd.money or {}
    return {
        day = DAYS[GetClockDayOfWeek()] or '',
        time = ('%02d:%02d'):format(GetClockHours(), GetClockMinutes()),
        cash = Money(money.cash),
        bank = Money(money.bank),
    }
end

-- the character's first and last name; the player's own name only without a character
local function CharacterName()
    local pd = PlayerData()
    local info = pd and pd.charinfo or {}
    local name = ((info.firstname or '') .. ' ' .. (info.lastname or '')):match('^%s*(.-)%s*$')
    return name ~= '' and name or GetPlayerName(PlayerId())
end

-- the title at the top left: Config.Title, or else the server's name
local function Title()
    if (Config.Title or '') ~= '' then return Config.Title end
    return serverName
end

local function ResourceUp(name)
    return name == nil or GetResourceState(name) == 'started'
end

-- the tiles, each row's those that can be used, their lines filled in
local function Tiles()
    local pd = PlayerData()
    local subs = {
        ['$location'] = Location(),
        ['$players'] = ('%d Online'):format(math.max(#players, #GetActivePlayers())),
        ['$job'] = pd and pd.job and pd.job.label or '',
        ['$recording'] = Recording() and 'Stop and save' or 'Record a clip',
    }
    local rows = {}
    for r = 1, #Config.Tiles do
        local row = {}
        for _, tile in ipairs(Config.Tiles[r]) do
            local usable = ResourceUp(tile.needs) and (tile.id ~= 'discord' or (Config.Discord or '') ~= '')
            if usable then
                row[#row + 1] = {
                    id = tile.id,
                    label = tile.label,
                    image = tile.image,
                    sub = tile.sub and (subs[tile.sub] or tile.sub) or '',
                }
            end
        end
        if #row > 0 then rows[#rows + 1] = row end
    end
    return rows
end

-- =============================================================================
-- Settings: this server's own, each kept by the resource it belongs to
-- =============================================================================
local CRASHCAM_KVP = 'vi_pausemenu:crashcam'

local function Export(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, value = pcall(function()
        local res = exports[resource]
        return res[name](res, table.unpack(args, 1, args.n))
    end)
    if not ok then return nil end
    return value
end

local ON_OFF = { { v = true, label = 'On' }, { v = false, label = 'Off' } }

local Settings = {
    {
        id = 'crashcam', label = 'Crash Camera', image = 'crashcam', needs = 'vi_crashcam', values = ON_OFF,
        desc = 'A slow replay from outside the car when you crash.',
        get = function() return GetResourceKvpString(CRASHCAM_KVP) ~= 'off' end,
        set = function(v)
            SetResourceKvp(CRASHCAM_KVP, v and 'on' or 'off')
            Export('vi_crashcam', 'SetCrashCamEnabled', v)
        end,
    },
    {
        id = 'mapmode', label = 'Map Day/Night', image = 'mapnight', needs = 'gen7_map',
        values = { { v = 'auto', label = 'Auto' }, { v = 'day', label = 'Day' }, { v = 'night', label = 'Night' } },
        desc = 'The map by day, by night, or following the clock.',
        get = function() return Export('gen7_map', 'GetMapMode') end,
        set = function(v) Export('gen7_map', 'SetMapMode', v) end,
    },
    {
        id = 'minimap', label = 'Map in Vehicle Only', image = 'mapvehicle', needs = 'vice_hud', values = ON_OFF,
        desc = 'The minimap only while you are in a vehicle.',
        get = function()
            local onFoot = Export('vice_hud', 'GetMinimapOnFoot')
            if onFoot == nil then return nil end
            return not onFoot
        end,
        set = function(v) Export('vice_hud', 'SetMinimapOnFoot', not v) end,
    },
    {
        id = 'radio', label = 'Radio', image = 'radio', needs = 'vi_radio', values = ON_OFF,
        desc = 'The radio in vehicles. Off mutes it.',
        get = function()
            local muted = Export('vi_radio', 'IsMuted')
            if muted == nil then return nil end
            return not muted
        end,
        set = function(v) Export('vi_radio', 'SetMuted', not v) end,
    },
    {
        id = 'style', label = 'Pause Menu', image = 'pausemenu',
        values = { { v = 'vi', label = 'GTA VI' }, { v = 'classic', label = 'Classic' } },
        desc = "This menu, or the game's own pause menu. /pausemenu brings this one back.",
        get = function() return style end,
        set = function(v)
            style = v
            SetResourceKvp(Config.StyleKvp, v)
        end,
    },
    { id = 'keybinds', label = 'Key Bindings', image = 'keybinds', action = 'keybinds', desc = "The keys of this server's actions." },
    { id = 'gamesettings', label = 'Game Settings', image = 'gamesettings', action = 'gamesettings', desc = 'Display, graphics, audio and controls.' },
}

local function ValueLabel(setting, value)
    for _, option in ipairs(setting.values) do
        if option.v == value then return option.label end
    end
    return tostring(value)
end

local function SettingsRows()
    local rows = {}
    for _, s in ipairs(Settings) do
        if ResourceUp(s.needs) then
            if s.action then
                rows[#rows + 1] = { id = s.id, label = s.label, image = s.image, title = s.label, desc = s.desc, action = true }
            else
                local value = s.get()
                if value ~= nil then
                    rows[#rows + 1] = { id = s.id, label = s.label, value = ValueLabel(s, value), image = s.image, title = s.label, desc = s.desc, change = true }
                end
            end
        end
    end
    return rows
end

-- a setting one along (dir 1) or back (-1)
local function ChangeSetting(id, dir)
    for _, s in ipairs(Settings) do
        if s.id == id and s.values then
            local value = s.get()
            local at = 1
            for i, option in ipairs(s.values) do
                if option.v == value then at = i end
            end
            s.set(s.values[(at - 1 + (dir < 0 and -1 or 1)) % #s.values + 1].v)
            return
        end
    end
end

-- the crash camera as the player left it, whenever vi_crashcam (re)starts
local function ApplyCrashCam()
    if GetResourceKvpString(CRASHCAM_KVP) == 'off' then
        Export('vi_crashcam', 'SetCrashCamEnabled', false)
    end
end
AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'vi_crashcam' then
        SetTimeout(500, ApplyCrashCam)
    end
end)
CreateThread(function()
    Wait(1000)
    ApplyCrashCam()
end)

-- =============================================================================
-- The other lists: brief, stats, players, report
-- =============================================================================
local function BriefRows()
    local pd = PlayerData() or {}
    local info = pd.charinfo or {}
    local job = pd.job or {}
    local money = pd.money or {}
    local meta = pd.metadata or {}
    local rows = {
        { label = 'Name', value = ((info.firstname or '') .. ' ' .. (info.lastname or '')):gsub('^%s+', ''), desc = 'Who you are on this server.' },
        { label = 'Job', value = job.label or 'Unemployed', desc = job.grade and job.grade.name and ('Grade: ' .. job.grade.name) or '' },
        { label = 'On Duty', value = job.onduty and 'Yes' or 'No', desc = 'Whether you are on the clock.' },
        { label = 'Cash', value = Money(money.cash), desc = 'In your pocket.' },
        { label = 'Bank', value = Money(money.bank), desc = 'At BuckMe.' },
        { label = 'Hunger', value = ('%d%%'):format(math.floor(meta.hunger or 100)), desc = 'Eat before it runs out.' },
        { label = 'Thirst', value = ('%d%%'):format(math.floor(meta.thirst or 100)), desc = 'Drink before it runs out.' },
        { label = 'Citizen ID', value = pd.citizenid or '', desc = 'Your character on this server.' },
        { label = 'Server ID', value = tostring(GetPlayerServerId(PlayerId())), desc = 'Your number on this server today.' },
    }
    for _, row in ipairs(rows) do
        row.image = 'brief'
        row.title = row.label
    end
    return rows
end

local function StatsRows()
    local rows = {}
    for _, skill in ipairs(Config.Skills) do
        local s = Export('vice_hud', 'GetSkill', skill.id)
        if type(s) == 'table' then
            local level = math.floor(tonumber(s.level) or 0)
            local desc = skill.how
            if level < 100 and tonumber(s.need) and tonumber(s.into) then
                desc = ('%s %d%% of the way to level %d.'):format(skill.how, math.floor((tonumber(s.frac) or 0) * 100), level + 1)
            end
            rows[#rows + 1] = { label = skill.label, value = ('%d / 100'):format(level), bar = level / 100, image = skill.image, title = skill.label, desc = desc }
        end
    end
    return rows
end

local function PlayersRows()
    local list = {}
    for _, p in ipairs(players) do list[#list + 1] = p end
    table.sort(list, function(a, b) return a.id < b.id end)
    local rows = {}
    for _, p in ipairs(list) do
        rows[#rows + 1] = { label = p.name, value = ('#%d'):format(p.id), image = 'players', title = p.name, desc = ('Server ID %d.'):format(p.id) }
    end
    return rows
end

local LISTS = {
    settings = { title = 'Settings', rows = SettingsRows },
    brief = { title = 'Brief', rows = BriefRows },
    stats = { title = 'Stats', rows = StatsRows },
    players = { title = 'Players', rows = PlayersRows },
}

-- =============================================================================
-- Open and close
-- =============================================================================
-- fresh: just opened (the page starts at the first tile), not back from one of the game's own screens
local function Show(what, fresh)
    SendNUIMessage({
        type = 'open',
        fresh = fresh == true,
        screen = what or screen,
        title = Title(),
        mode = Config.Mode,
        name = CharacterName(),
        tiles = Tiles(),
        footer = Footer(),
        discord = Config.Discord,
        categories = Config.Report.Categories,
    })
    if LISTS[screen] then
        SendNUIMessage({ type = 'list', screen = screen, title = LISTS[screen].title, rows = LISTS[screen].rows() })
    end
end

-- The character's face for the top right, as the character switcher (qbx_relog) and the honor panel show it: a
-- transparent pedheadshot of the player's own ped. The game has ONE slot for those (citizenfx/fivem#2611), so it is
-- borrowed, never held: the page copies the picture out of nui-img and says so, and the slot is let go at once.
local mugBusy = false
local mugCopied = nil       -- the page's answer: true copied, false failed, nil not yet

RegisterNUICallback('mugshot', function(data, cb)
    mugCopied = type(data) == 'table' and data.ok == true
    cb(1)
end)

local function TakeMugshot()
    if mugBusy then return end
    mugBusy = true
    CreateThread(function()
        local handle = RegisterPedheadshotTransparent(PlayerPedId())
        local deadline = GetGameTimer() + 5000
        while not IsPedheadshotReady(handle) and GetGameTimer() < deadline do Wait(0) end
        if IsPedheadshotReady(handle) and IsPedheadshotValid(handle) then
            mugCopied = nil
            SendNUIMessage({ type = 'mugshot', txd = GetPedheadshotTxdString(handle) })
            deadline = GetGameTimer() + 5000
            while mugCopied == nil and GetGameTimer() < deadline do Wait(0) end
        end
        -- whatever happened, before anything else: holding the slot breaks every other headshot in the game
        UnregisterPedheadshot(handle)
        mugBusy = false
    end)
end

local function OpenMenu()
    if open then return end
    local ok, err = pcall(function()
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(false)
        TriggerScreenblurFadeIn(400)
    end)
    if not ok then
        print(('[vi_pausemenu] opening failed: %s'):format(err))
        SetNuiFocus(false, false)
        return
    end
    open = true
    openedAt = GetGameTimer()
    screen = 'home'
    LocalPlayer.state:set('pauseMenuOpen', true, false)
    TriggerServerEvent('vi_pausemenu:server:requestPlayers')
    Show('home', true)
    -- a new picture every time: the clothes, the hair, the mask may have changed since the last
    TakeMugshot()
    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

local function CloseMenu()
    if not open then return end
    open = false
    closedAt = GetGameTimer()
    SetNuiFocus(false, false)
    TriggerScreenblurFadeOut(400)
    LocalPlayer.state:set('pauseMenuOpen', false, false)
    SendNUIMessage({ type = 'close' })
    PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

-- =============================================================================
-- The game's own screens: its settings, the key bindings
-- =============================================================================
local function OpenNative(menu)
    if nativeOpen then return end
    nativeOpen = true

    -- (this page's focus off first: a native menu up under an NUI with focus is what locked gk_pausemenu up)
    SendNUIMessage({ type = 'hide' })
    SetNuiFocus(false, false)
    -- (togglePause false below: the menu's flag is ours to raise, or its loading never finishes)
    SetPauseMenuActive(true)

    local ok, err = pcall(ActivateFrontendMenu, GetHashKey(menu), false, -1)
    if not ok then
        print(('[vi_pausemenu] ActivateFrontendMenu %s failed: %s'):format(menu, err))
        nativeOpen = false
        SetPauseMenuActive(false)
        if open then
            SetNuiFocus(true, true)
            Show(screen)
        end
        return
    end

    CreateThread(function()
        local start = GetGameTimer()
        while not IsFrontendReadyForControl() and GetGameTimer() - start < 5000 do
            Wait(0)
        end
        while IsFrontendReadyForControl() do
            Wait(0)
        end

        pcall(PauseMenuceptionTheKick)
        pcall(SetFrontendActive, false)
        SetPauseMenuActive(false)
        nativeOpen = false

        if open then
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
            openedAt = GetGameTimer()
            Show(screen)
        end
    end)
end

-- =============================================================================
-- The map: single player's, drawn by the page
-- =============================================================================
-- The page draws it as GTA6Hud's DrawPauseMap does and takes its keys, its mouse and (through the pad thread below)
-- a pad. From here it gets the player's place and heading and the waypoint every MAP_EVERY ms, and the blips every
-- MAP_BLIPS_EVERY, scanned as GTA6Hud's RefreshMapBlips scans them: each sprite the map has a picture for
-- (client/mapsprites.lua, in its order), up to 300 of each, only those the big map shows (display 2, 3, 4, 6, 8 or
-- 9), never the player's own arrow (6) or the waypoint (8), which it draws itself; a plain dot (1) keeps its colour.
local MAP_EVERY = 100
local MAP_BLIPS_EVERY = 400
local MAP_DISPLAYS = { [2] = true, [3] = true, [4] = true, [6] = true, [8] = true, [9] = true }

local function MapMe()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    return { x = c.x, y = c.y, h = GetEntityHeading(ped) }
end

local function MapWaypoint()
    if not IsWaypointActive() then return false end
    local blip = GetFirstBlipInfoId(8)
    if blip == 0 or not DoesBlipExist(blip) then return false end
    local c = GetBlipInfoIdCoord(blip)
    return { x = c.x, y = c.y }
end

-- four numbers a blip, flat: x, y (to the metre), sprite, and a plain dot's colour as 0xRRGGBB (0 for the rest)
local function MapBlips()
    local out = {}
    for _, sprite in ipairs(MapSprites) do
        if sprite ~= 6 and sprite ~= 8 then
            local blip = GetFirstBlipInfoId(sprite)
            for _ = 1, 300 do
                if blip == 0 or not DoesBlipExist(blip) then break end
                if MAP_DISPLAYS[GetBlipInfoIdDisplay(blip)] then
                    local c = GetBlipInfoIdCoord(blip)
                    local colour = 0
                    if sprite == 1 then
                        local r, g, b = GetHudColour(GetBlipHudColour(blip))
                        colour = (r or 0) * 65536 + (g or 0) * 256 + (b or 0)
                    end
                    out[#out + 1] = math.floor(c.x + 0.5)
                    out[#out + 1] = math.floor(c.y + 0.5)
                    out[#out + 1] = sprite
                    out[#out + 1] = colour
                end
                blip = GetNextBlipInfoId(sprite)
            end
        end
    end
    return out
end

local function MapData(withBlips)
    return { me = MapMe(), wp = MapWaypoint(), blips = withBlips and MapBlips() or nil }
end

CreateThread(function()
    local blipsAt = 0
    while true do
        if open and not nativeOpen and screen == 'map' then
            local now = GetGameTimer()
            local withBlips = now >= blipsAt
            if withBlips then blipsAt = now + MAP_BLIPS_EVERY end
            SendNUIMessage({ type = 'mapdata', map = MapData(withBlips) })
            Wait(MAP_EVERY)
        else
            blipsAt = 0
            Wait(open and 50 or 250)
        end
    end
end)

-- the page's waypoint: set where it was asked, or taken off, with single player's sounds
RegisterNUICallback('waypoint', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    local x, y = tonumber(data.x), tonumber(data.y)
    if data.off == true then
        SetWaypointOff()
        PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    elseif x and y then
        SetNewWaypoint(x + 0.0, y + 0.0)
        PlaySoundFrontend(-1, 'WAYPOINT_SET', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
end)

-- the area under the page's cursor, as single player asks for it (at a height of 40)
RegisterNUICallback('mapzone', function(data, cb)
    local x = type(data) == 'table' and tonumber(data.x)
    local y = type(data) == 'table' and tonumber(data.y)
    cb({ zone = (x and y) and Zone(x + 0.0, y + 0.0, 40.0) or '' })
end)

-- =============================================================================
-- The page's calls
-- =============================================================================
RegisterNUICallback('close', function(_, cb)
    cb(1)
    CloseMenu()
end)

RegisterNUICallback('screen', function(data, cb)
    screen = type(data) == 'table' and LISTS[data.screen] and data.screen or 'home'
    if LISTS[screen] then
        cb({ title = LISTS[screen].title, rows = LISTS[screen].rows() })
    else
        cb({})
    end
end)

RegisterNUICallback('tile', function(data, cb)
    local id = type(data) == 'table' and data.id
    if id == 'map' then
        -- the map comes up on the page with everything it needs to start: the player, the waypoint, the blips
        screen = 'map'
        return cb({ map = MapData(true), mode = Config.Mode, name = CharacterName(), safezone = GetSafeZoneSize() })
    end
    cb(1)
    if id == 'game' then
        OpenNative('FE_MENU_VERSION_LANDING_MENU')
    elseif id == 'editor' then
        if Recording() then
            Native({ 'StopReplayRecording', 'StopRecordingAndSaveClip' }, 0x071A5197D6AFC8B3)
            SendNUIMessage({ type = 'tiles', tiles = Tiles() })
        else
            CloseMenu()
            Native({ 'StartReplayRecording', 'StartRecording' }, 0xC3AC2FFF9612AC81, 1)
        end
    end
end)

RegisterNUICallback('setting', function(data, cb)
    if type(data) ~= 'table' then return cb({}) end
    if data.id == 'keybinds' then
        cb({})
        return OpenNative('FE_MENU_VERSION_LANDING_KEYMAPPING_MENU')
    elseif data.id == 'gamesettings' then
        cb({})
        return OpenNative('FE_MENU_VERSION_LANDING_MENU')
    end
    ChangeSetting(data.id, tonumber(data.dir) or 1)
    PlaySoundFrontend(-1, 'NAV_LEFT_RIGHT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    cb({ rows = SettingsRows() })
end)

RegisterNUICallback('report', function(data, cb)
    cb(1)
    if type(data) ~= 'table' then return end
    local subject = type(data.subject) == 'string' and data.subject:match('^%s*(.-)%s*$') or ''
    local text = type(data.text) == 'string' and data.text:match('^%s*(.-)%s*$') or ''
    if subject ~= '' and text ~= '' then
        TriggerServerEvent('vi_pausemenu:server:report', tostring(data.category or 'Other'), subject:sub(1, 120), text:sub(1, 1500))
    end
end)

RegisterNUICallback('disconnect', function(_, cb)
    cb(1)
    CloseMenu()
    TriggerServerEvent('vi_pausemenu:server:disconnect')
end)

RegisterNUICallback('sound', function(data, cb)
    cb(1)
    local name = type(data) == 'table' and data.name
    if name == 'nav' then
        PlaySoundFrontend(-1, 'NAV_UP_DOWN', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    elseif name == 'select' then
        PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    elseif name == 'back' then
        PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
end)

RegisterNetEvent('vi_pausemenu:client:setPlayers', function(list, name)
    players = type(list) == 'table' and list or {}
    if open and screen == 'players' then
        SendNUIMessage({ type = 'list', screen = 'players', title = 'Players', rows = PlayersRows() })
    end
    if type(name) == 'string' and name ~= serverName then
        serverName = name
        if open then SendNUIMessage({ type = 'title', title = Title() }) end
    end
end)

-- the list and the server's name once at the start, so the first open has the name
CreateThread(function()
    Wait(2000)
    TriggerServerEvent('vi_pausemenu:server:requestPlayers')
end)

-- /pausemenu: this menu back, after Settings > Pause Menu: Classic
RegisterCommand('pausemenu', function()
    style = style == 'vi' and 'classic' or 'vi'
    SetResourceKvp(Config.StyleKvp, style)
    print(('[vi_pausemenu] pause menu: %s'):format(style == 'vi' and 'GTA VI' or "the game's own"))
end, false)

-- =============================================================================
-- Keeping the game's own menu shut, and the key
-- =============================================================================
CreateThread(function()
    while true do
        Wait(0)
        if style == 'vi' then
            if not nativeOpen then
                SetPauseMenuActive(false)
            end

            if not open and not nativeOpen and GetGameTimer() - closedAt > 300
                and (IsControlJustPressed(0, 200) or IsControlJustPressed(0, 199)) then
                OpenMenu()
            end

            if open and not nativeOpen then
                for _, control in ipairs(Config.DisableWhileOpen) do
                    DisableControlAction(0, control, true)
                end
            end
        else
            if open then CloseMenu() end
            Wait(250)
        end
    end
end)

-- =============================================================================
-- A pad
-- =============================================================================
-- The page holds the focus while it is up, and a page only hears the keyboard and
-- the mouse. A pad is read here instead, off the game's own frontend controls
-- (which go on reporting as disabled controls while the page has the focus), and
-- handed to the page as the keys it already knows: the D-pad or the left stick
-- moves, cross selects, circle goes back, Start closes. Held, a direction
-- repeats as the game's own menus do. Only while a pad is what the player is
-- using, so the keyboard is never heard twice.
--
-- On the map the pad is single player's instead: square, triangle, LB and RB
-- are presses too, and the left stick and the triggers are handed over as they
-- stand (when they change), for the page to pan and zoom with as GTA6Hud's
-- PauseMapInput does with controls 30/31 (218/219: the same stick) and 207/208.
local PAD_BUTTONS = { { 201, 'accept' }, { 202, 'back' }, { 199, 'close' } }
local PAD_MAP_BUTTONS = {
    { 201, 'accept' }, { 202, 'back' }, { 199, 'close' },
    { 203, 'alt' }, { 204, 'center' }, { 205, 'lb' }, { 206, 'rb' },
}
local PAD_DIRS = { { 172, 'up' }, { 173, 'down' }, { 174, 'left' }, { 175, 'right' } }
local PAD_GRACE = 300       -- ms after it comes up: the press that opened it is not also a press in it
local PAD_REPEAT = { first = 400, every = 110 }
local STICK = 0.5
local MAP_STICK, MAP_TRIGGER = 0.15, 0.1    -- below these on both, single player leaves the map alone

local function Hundredths(v) return math.floor((tonumber(v) or 0) * 100 + 0.5) / 100 end

-- the map's stick and triggers, nothing at all while both are in their dead zones
local function PadAxes()
    local x, y = Hundredths(GetDisabledControlNormal(0, 218)), Hundredths(GetDisabledControlNormal(0, 219))
    local lt, rt = Hundredths(GetDisabledControlNormal(0, 207)), Hundredths(GetDisabledControlNormal(0, 208))
    if math.abs(x) <= MAP_STICK and math.abs(y) <= MAP_STICK then x, y = 0, 0 end
    if lt <= MAP_TRIGGER and rt <= MAP_TRIGGER then lt, rt = 0, 0 end
    return x, y, lt, rt
end

CreateThread(function()
    local held, heldAt, nextAt = nil, 0, 0
    local axes = { 0, 0, 0, 0 }     -- what the page was last told
    local function SendAxes(x, y, lt, rt)
        if x == axes[1] and y == axes[2] and lt == axes[3] and rt == axes[4] then return end
        axes = { x, y, lt, rt }
        SendNUIMessage({ type = 'padaxes', x = x, y = y, lt = lt, rt = rt })
    end
    while true do
        if not open or nativeOpen or IsUsingKeyboard(2) then
            held = nil
            SendAxes(0, 0, 0, 0)
            Wait(open and 0 or 250)
        else
            local now = GetGameTimer()
            local onMap = screen == 'map'
            if now - openedAt >= PAD_GRACE then
                for _, b in ipairs(onMap and PAD_MAP_BUTTONS or PAD_BUTTONS) do
                    if IsDisabledControlJustPressed(0, b[1]) then
                        SendNUIMessage({ type = 'pad', button = b[2] })
                    end
                end
            end
            if onMap then
                held = nil
                SendAxes(PadAxes())
            elseif now - openedAt >= PAD_GRACE then
                SendAxes(0, 0, 0, 0)
                -- the direction held: the D-pad, else the left stick
                local dir = nil
                for _, d in ipairs(PAD_DIRS) do
                    if IsDisabledControlPressed(0, d[1]) then dir = d[2] end
                end
                if not dir then
                    local x, y = GetDisabledControlNormal(0, 218), GetDisabledControlNormal(0, 219)
                    if math.abs(x) >= STICK and math.abs(x) >= math.abs(y) then dir = x > 0 and 'right' or 'left'
                    elseif math.abs(y) >= STICK then dir = y > 0 and 'down' or 'up' end
                end
                if dir ~= held then
                    held, heldAt, nextAt = dir, now, now + PAD_REPEAT.first
                    if dir then SendNUIMessage({ type = 'pad', button = dir }) end
                elseif dir and now >= nextAt then
                    nextAt = now + PAD_REPEAT.every
                    SendNUIMessage({ type = 'pad', button = dir })
                end
            end
            Wait(0)
        end
    end
end)

-- the day and time, the money: once a second while it is up
CreateThread(function()
    while true do
        Wait(1000)
        if open and not nativeOpen then
            SendNUIMessage({ type = 'footer', footer = Footer() })
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if open then CloseMenu() end
    LocalPlayer.state:set('pauseMenuOpen', false, false)
end)
