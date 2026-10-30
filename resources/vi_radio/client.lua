--[[
    VI Radio - client
    FiveM port of the singleplayer "VI Radio" mod by sej0bec.

    The original is a ScriptHookVDotNet plugin that drew its HUD with native
    textures. FiveM cannot load SHVDN assemblies, so the HUD is rebuilt as NUI
    and the game side (stations, slow motion, timecycle, mute) lives here.

    The single-player GTA VI-Inspired HUD ported this file to single player
    (ViExtras' Radio.cs) and has moved on since. What it changed is brought
    back here, so the two wheels look and behave alike: the wheel opens on the
    game's own radio wheel control and follows the pad or the keyboard
    touched last, the right stick steps one station a push, a right-stick
    click mutes, browsing unmutes before the station goes on, the wheel's
    timings run on real time rather than the slowed game clock, the song and
    artist come from the game's own labels, the chase music takes over from
    the radio, On Demand lists its stations in the wheel, goes quiet over the
    pause menu, cutscenes and death, and the whole wheel can be switched off
    (VI RADIO WHEEL in HUD OPTIONS) to give GTA's own back.
]]

local RES = GetCurrentResourceName()
local OD  = Config.OnDemand
local ON_DEMAND = 'ONDEMAND'
local KVP_WHEEL = 'vi_radio:wheel'

-- control ids
local C = {
    LOOK_LR = 1, LOOK_UD = 2,
    WHEEL_NEXT = 14, WHEEL_PREV = 15,              -- mouse wheel
    CHARACTER_WHEEL = 19, MULTIPLAYER_INFO = 20,   -- Left Alt / Z, both D-pad Down
    PHONE = 27, HEADLIGHT = 74, HANDBRAKE = 76,
    LOOK_BEHIND = 79,                              -- C, a right-stick click on a pad
    NEXT_RADIO = 81, PREV_RADIO = 82, NEXT_TRACK = 83, PREV_TRACK = 84, RADIO_WHEEL = 85,
    VEH_NEXT_WEAPON = 99, VEH_PREV_WEAPON = 100,   -- the drive-by weapon select, on the mouse wheel too
    CELL_UP = 172, CELL_DOWN = 173, CELL_LEFT = 174, CELL_RIGHT = 175,
    FRONTEND_RS = 210,                             -- the right-stick click again
    RIGHT_X = 220, RIGHT_Y = 221,
}
local HUD_RADIO_STATIONS = 16

-- state ----------------------------------------------------------------------
local wheelEnabled  = Config.WheelEnabled ~= false   -- VI RADIO WHEEL, per player (KVP)
local radioList     = {}     -- ordered list of { name, label, logo, genre, off }
local odList        = {}     -- On Demand's: { name, label, logo, genre, od = station (0: the queue) }
local stations      = radioList   -- the list the wheel shows: one of the two
local index         = 1      -- currently highlighted entry in `stations`
local wheelOpen     = false  -- the hold-to-browse wheel, which owns the effects
local popupOpen     = false  -- the On Demand panel, which owns NUI focus
local keyHeld       = false
local muted         = false  -- the player's own mute
local chaseQuiet    = false  -- the chase music has the car's speakers (not the player's mute)
local chaseSeenAt   = 0
local mutedVehicle  = 0      -- vehicle the mute (or the chase music) was applied to
local nowPlaying    = { title = nil, artist = nil }   -- pushed in through SetNowPlaying
local timeScaleNow  = 1.0
local timeOwned     = false  -- the slow motion is ours, opening or easing back
local navHeldSince  = 0
local navLastStep   = 0
local navDir        = 0
local stickLatched  = false  -- right stick must recentre between station changes
local stickYLatched = false  -- same again vertically, for the On Demand switch
local stationPicked = false  -- a station was browsed to during this wheel session
local panelOnClose  = false  -- On Demand was switched on, so show the panel on release
local openedByControl = false -- steering with the pad (it was the last thing touched)
local muteToggledAt = 0      -- a right-stick click reads as two controls: one toggle a click
local dpadHold      = false  -- D-pad Down kept off after the wheel closes, until let go
local odTookCarAt   = 0      -- when On Demand last switched this car's radio off
local odPick        = nil    -- { id, at }: an On Demand station browsed to, sent once browsing settles
local lastBlock     = nil    -- why the wheel last stayed shut (viradio_debug)

-- On Demand. Sessions are keyed by vehicle network id and are pushed by the
-- server; nothing in here decides what is playing, only whether this client is
-- close enough to hear it.
local odSessions = {}
local odVolume   = math.min(OD.volume, OD.maxVolume) / 100
local odMuted    = false
-- Tracks the last lowpass state sent per sound id, so the muffle toggle
-- below (which runs every OD.syncInterval) only calls SetLowpassSound on an
-- actual change instead of every tick.
local odLowpassState = {}
local odAppliedVolume = {}   -- the same for the volume each sound was last given

local hiddenStations = {}
for _, name in ipairs(Config.HiddenStations or {}) do hiddenStations[tostring(name):upper()] = true end

-- helpers --------------------------------------------------------------------

-- Real milliseconds. GetGameTimer() runs at the slow-motion speed (SetTimeScale
-- slows the game clock with the world; see vice_hud's client_vitals.lua), and
-- this wheel slows the world to 0.075, so its own timings -- the ease, the
-- auto repeat -- stretched 13-fold while it was open. Two clocks, as
-- vi_crashcam keeps them: whichever moved further is the real one.
local clockNet, clockGame, clockNow = nil, nil, 0
local function realMs()
    local net, game = GetNetworkTimeAccurate(), GetGameTimer()
    if clockNet then
        local d = math.max(net - clockNet, game - clockGame)
        if d > 0 then clockNow = clockNow + math.min(d, 5000) end
    end
    clockNet, clockGame = net, game
    return clockNow
end

local function currentVehicle()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return 0 end
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return 0 end
    if Config.DriverOnly and GetPedInVehicleSeat(veh, -1, false) ~= ped then return 0 end
    return veh
end

-- Another resource's full-screen menu is up (Config.BlockedBy): the buttons
-- are that menu's for now.
local function menuHasInput()
    for _, key in ipairs(Config.BlockedBy or {}) do
        if LocalPlayer.state[key] then return true end
    end
    return false
end

-- Another resource's export, asked at most every 250 ms (they are read every
-- frame while the wheel button is held). False when it is not running.
local exportCache = {}
local function exportSays(resource, name)
    local key = resource .. ':' .. name
    local hit = exportCache[key]
    local now = realMs()
    if hit and now - hit.at < 250 then return hit.value end
    local value = false
    if GetResourceState(resource) == 'started' then
        local ok, result = pcall(function()
            local res = exports[resource]
            return res[name](res)
        end)
        value = ok and result == true
    end
    exportCache[key] = { at = now, value = value }
    return value
end

local function paused()
    return IsPauseMenuActive() or LocalPlayer.state.pauseMenuOpen == true
end

-- A cutscene, a character switch or a black screen.
local function busy()
    return IsCutscenePlaying() or IsPlayerSwitchInProgress() or IsScreenFadedOut()
end

local function playerDead()
    return IsPedDeadOrDying(PlayerPedId(), true) or LocalPlayer.state['qbx_medical:deathState'] == 3
end

-- Something else has the keys, or the player can't use them: the single-player
-- wheel's list (a pause menu, a cutscene or black screen, the phone, death,
-- the crash cam, the binoculars), plus Config.BlockedBy's menus. Returns why.
local function blockedBy()
    if menuHasInput() then return 'a menu (Config.BlockedBy)' end
    if paused() then return 'the pause menu' end
    if busy() or GetIsLoadingScreenActive() then return 'a cutscene, loading screen or black screen' end
    local ped = PlayerPedId()
    if playerDead() then return 'death' end
    if IsPedRunningMobilePhoneTask(ped) then return 'the phone' end
    if exportSays('vi_crashcam', 'IsCrashCamPlaying') then return 'the crash cam' end
    if exportSays('vi_binoculars', 'IsActive') then return 'the binoculars' end
    return nil
end

local function canUseRadio()
    if currentVehicle() ~= 0 then return true end
    return Config.AllowOnFoot and IsMobilePhoneRadioActive()
end

-- On Demand belongs to a vehicle, so it is only offered while sat in one.
local function odAvailable()
    return OD.enabled and currentVehicle() ~= 0
end

local function myNetId()
    local veh = currentVehicle()
    if veh == 0 then return nil end
    return VehToNet(veh)
end

local function odSessionHere()
    local netId = myNetId()
    return netId and odSessions[netId] or nil
end

local function odSoundId(netId)
    return 'vi_radio_od_' .. netId
end

local function odElapsed(sess)
    if not sess or not sess.recvAt then return 0.0 end
    if sess.paused then return sess.position end
    return sess.position + (GetGameTimer() - sess.recvAt) / 1000.0
end

local function stationInfo(name)
    local cfg = Config.Stations[name]
    if cfg then
        return {
            name  = name,
            label = cfg.label,
            logo  = cfg.logo and ('logos/' .. cfg.logo) or nil,
            genre = cfg.genre,
        }
    end
    -- Unknown / add-on station: fall back to a readable version of the raw name.
    local pretty = name:gsub('^RADIO_%d+_', ''):gsub('^DLC_', ''):gsub('_', ' ')
    return { name = name, label = pretty, logo = nil, genre = nil }
end

local function buildRadioList()
    local list = {}
    local seenOff = false

    for i = 0, GetNumUnlockedRadioStations() - 1 do
        local name = GetRadioStationName(i)
        if name and name ~= '' then
            if name == 'OFF' then
                seenOff = true
            elseif not name:find('^HIDDEN_') and not hiddenStations[name:upper()] then
                local cfg = Config.Stations[name]
                if not (cfg and cfg.hidden) then
                    list[#list + 1] = stationInfo(name)
                end
            end
        end
    end
    if Config.IncludeOff or seenOff then
        list[#list + 1] = { name = 'OFF', label = Config.OffLabel, logo = nil, genre = nil, off = true }
    end
    return list
end

-- On Demand's stations, as the single-player wheel lists your own music's: the
-- vehicle's own queue (the links pasted into the panel) first, then the
-- server's stations (Config.OnDemand.stations).
local function buildOdList()
    local list = { { name = 'OD:0', label = OD.label, od = 0 } }
    for i, st in ipairs(OD.stations or {}) do
        list[#list + 1] = {
            name  = 'OD:' .. i,
            label = st.label or ('STATION ' .. i),
            logo  = st.logo,
            genre = st.genre,
            od    = i,
        }
    end
    return list
end

-- With the switch down (and Config.OnDemand.stationsInWheel) the wheel lists
-- On Demand's stations; otherwise the radio's.
local function odListed()
    return OD.enabled and OD.stationsInWheel and odSessionHere() ~= nil
end

-- The entry for what is playing, or nil when it is not in the list. `hint`
-- is a station just put on, which the game may not name yet.
local function playingIndex(list, hint)
    if list == odList then
        local sess = odSessionHere()
        local want = sess and (sess.station or 0) or 0
        for i, s in ipairs(list) do
            if s.od == want then return i end
        end
        return 1
    end
    local playing = hint or GetPlayerRadioStationName()
    if not playing or playing == '' then playing = 'OFF' end
    for i, s in ipairs(list) do
        if s.name == playing then return i end
    end
    return nil
end

-- Points the wheel at the list it should show. True when that changed.
local function syncList(hint)
    local want = odListed() and odList or radioList
    if want == stations then return false end
    stations = want
    index = playingIndex(stations, hint) or 1
    return true
end

local function buildStations()
    radioList = buildRadioList()
    odList = buildOdList()
    stations = odListed() and odList or radioList

    -- keep the highlight on whatever is actually playing
    index = playingIndex(stations) or index
    if index > #stations or index < 1 then index = 1 end
end

local function setStation(name)
    local veh = currentVehicle()
    if veh ~= 0 then
        SetVehRadioStation(veh, name)
        -- The vanilla radio is otherwise near-silent the moment you step
        -- outside the vehicle -- SET_VEHICLE_RADIO_LOUD is the same native
        -- used for "big speaker" vehicles (audible outside with the game's
        -- own real distance falloff), so this gives the normal station wheel
        -- the same "carries outside the car" behaviour On Demand already has
        -- via xsound, using the real engine audio instead of reimplementing it.
        -- Also covers odEngage's setStation('OFF') (silences the loud vanilla
        -- radio while On Demand takes over) and odDisengage's restore.
        if Config.LoudRadio ~= false then SetVehicleRadioLoud(veh, name ~= 'OFF') end
    end
    SetRadioToStationName(name)
end

local function applyStation(entry)
    setStation(entry.name)
end

-- The player's mute, or the chase music's turn. The car muted before gets its
-- radio back on unmute, and when the mute moves to another car (unmuting on
-- foot or from another car used to leave it silent for good). The mobile radio
-- is only this resource's business when the wheel may be used on foot;
-- otherwise unmuting switched the on-foot radio on.
local function applyMute()
    local veh = currentVehicle()
    local silent = muted or chaseQuiet
    if mutedVehicle ~= 0 and (not silent or veh ~= mutedVehicle) then
        if DoesEntityExist(mutedVehicle) then SetVehicleRadioEnabled(mutedVehicle, true) end
        mutedVehicle = 0
    end
    if veh ~= 0 then
        SetVehicleRadioEnabled(veh, not silent)
        mutedVehicle = silent and veh or 0
    end
    if Config.AllowOnFoot then SetMobileRadioEnabledDuringGameplay(not silent) end
end

-- AUDIO_IS_MUSIC_PLAYING: the game's score, the wanted music among it.
local function gameMusicPlaying()
    local r = Citizen.InvokeNative(0x845FFC3A4FEEFA3E, Citizen.ReturnResultAnyway())
    return r == true or (type(r) == 'number' and r ~= 0)
end

-- The chase music takes over from the radio: while you are wanted and the
-- game's wanted music plays, the car radio is off. It stays off until the
-- music has been gone 3 s, so a gap between tracks doesn't bring it back, and
-- comes back at once when the stars go.
local function chaseMusic()
    if not Config.ChaseMusicTakesOver then return end
    local now = realMs()
    local wanted = GetPlayerWantedLevel(PlayerId()) > 0
    local music = wanted and gameMusicPlaying()
    if music then chaseSeenAt = now end
    local quiet = wanted and (music or (chaseQuiet and now - chaseSeenAt < 3000))
    if quiet == chaseQuiet then return end
    chaseQuiet = quiet
    applyMute()
end

-- NUI ------------------------------------------------------------------------

local function nuiPayload()
    local items = {}
    for i, s in ipairs(stations) do
        items[i] = {
            label = s.label,
            logo  = s.logo,
            genre = s.genre,
            off   = s.off or false,
        }
    end
    return items
end

-- The song playing on the highlighted station, from the game's own labels for
-- the audible track (<id>S is its title, <id>A its artist), as the single-
-- player wheel reads them. Just after a change of station the old station's
-- track can still be the one heard, so for up to 3 s the track heard before
-- the change shows nothing.
local trk = { station = false, since = 0, audible = -1, atSwitch = -1, id = -1 }
local shownTrack = { title = nil, artist = nil }

local function trackLabel(key)
    if not DoesTextLabelExist(key) then return nil end
    local text = GetLabelText(key)
    if not text or text == '' or text == 'NULL' then return nil end
    return (text:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function updateTrack(now)
    local playing = canUseRadio() and GetPlayerRadioStationName() or nil
    local id = GetAudibleMusicTrackTextId() or -1
    if playing ~= trk.station then
        trk.station = playing
        trk.atSwitch = trk.audible
        trk.since = now
    end
    trk.audible = id
    local at = stations[index]
    local show = at ~= nil and not at.off and at.od == nil and id > 0
        and playing == at.name
        and not (id == trk.atSwitch and now - trk.since < 3000)
    if show and id ~= trk.id then
        trk.id = id
        trk.title = trackLabel(id .. 'S')
        trk.artist = trackLabel(id .. 'A')
    end
    shownTrack.title = show and trk.title or nil
    shownTrack.artist = show and trk.artist or nil
end

-- An On Demand session's two lines.
local function odLines(sess)
    if not sess.playing then return 'Nothing queued', nil end
    return sess.title, sess.paused and 'Paused' or sess.artist
end

-- The title/artist lines come from whatever is playing: an On Demand track when
-- one is, else whatever another resource has pushed in through SetNowPlaying,
-- else the game's own song names. Returns the station name to show (nil: the
-- highlighted entry's), then the two lines under it.
--
-- With On Demand's stations in the wheel, the highlighted entry has its lines
-- when it is the one playing. With the radio's stations listed instead
-- (Config.OnDemand.stationsInWheel = false), the highlighted station is not
-- what anyone is hearing while On Demand is on, so the lines say On Demand --
-- until the player starts browsing, at which point the carousel is a station
-- picker again and the name under it is the one they are about to choose.
local function currentLines()
    local sess = odSessionHere()

    if sess then
        if stations == odList then
            local entry = stations[index]
            if entry and entry.od == (sess.station or 0) then return nil, odLines(sess) end
            return nil, nil, nil
        elseif not stationPicked then
            return OD.label, odLines(sess)
        end
    end

    if nowPlaying.title or nowPlaying.artist then
        return nil, nowPlaying.title, nowPlaying.artist
    end
    return nil, shownTrack.title, shownTrack.artist
end

-- The left icon is the radio/On Demand switch when On Demand is available, and
-- the original static artwork when it is not.
local function hudPayload()
    local copy = {}
    for k, v in pairs(Config.Hud) do copy[k] = v end
    copy.odSwitch = OD.enabled
    return copy
end

local lastLines = {}

local function pushState(withList)
    if not Config.Hud.enabled then return end
    local label, title, artist = currentLines()
    lastLines = { label = label, title = title, artist = artist }
    SendNUIMessage({
        action  = 'state',
        open    = wheelOpen or (popupOpen and wheelEnabled),
        hud     = withList and hudPayload() or nil,
        list    = withList and nuiPayload() or nil,
        index   = index - 1,
        muted   = muted,
        odOn    = odSessionHere() ~= nil,
        label   = label,
        title   = title,
        artist  = artist,
    })
end

-- The lines alone, when only the song changed: a mute flash on screen is left
-- to run its course.
local function pushLines()
    if not Config.Hud.enabled then return end
    local label, title, artist = currentLines()
    if label == lastLines.label and title == lastLines.title and artist == lastLines.artist then return end
    lastLines = { label = label, title = title, artist = artist }
    SendNUIMessage({ action = 'track', label = label, title = title, artist = artist })
end

local function playSound(file)
    if not Config.RadioSounds or not file then return end
    SendNUIMessage({ action = 'sound', file = file, volume = Config.SoundVolume / 100 })
end

-- On Demand panel ------------------------------------------------------------

--[[
    Keeping the vanilla radio audible after you step out of your own car.

    SET_VEHICLE_RADIO_LOUD alone (above) does NOT do this on its own --
    confirmed against real reports, not assumed: forum.cfx.re/t/203276 (a
    2018 thread building the exact same feature) found "when I'm outside and
    my friend's inside the vehicle, I can hear his radio loudly, but doesn't
    work when no one's inside" -- an EMPTY vehicle's radio audio stops
    rendering entirely in the game engine, regardless of the loud flag or the
    engine still running. The only working fix anyone's found for this is
    keeping a ped seated in the vehicle so it never actually reads as empty.

    So: the moment you get out of a vehicle whose station isn't OFF, an
    invisible, harmless placeholder ped is put in your old seat to keep the
    radio "occupied" and therefore audible. It's cleaned up the moment you
    get back in (real ped takes the seat back), the vehicle is gone, or
    you've walked far enough that nothing would be audible anyway.
]]
local radioKeepAlive = {} -- [vehicle] = pedHandle
local lastVehicle = 0
local KEEP_ALIVE_MODEL = GetHashKey('a_m_y_business_01') -- never actually seen -- see SetEntityVisible below

local function despawnRadioKeepAlive(veh)
    local ped = radioKeepAlive[veh]
    if ped then
        if DoesEntityExist(ped) then DeletePed(ped) end
        radioKeepAlive[veh] = nil
    end
end

local function spawnRadioKeepAlive(veh)
    if radioKeepAlive[veh] or not DoesEntityExist(veh) then return end
    if GetPedInVehicleSeat(veh, -1) ~= 0 then return end -- someone real already driving

    local model = KEEP_ALIVE_MODEL
    RequestModel(model)
    local waited = 0
    while not HasModelLoaded(model) and waited < 500 do Wait(0) waited = waited + 1 end
    if not HasModelLoaded(model) then return end

    local ped = CreatePedInsideVehicle(veh, 6, model, -1, true, true)
    SetModelAsNoLongerNeeded(model)
    if not ped or ped == 0 then return end

    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)

    radioKeepAlive[veh] = ped
end

-- The 500ms poll below is too slow to beat GTA's own seat-assignment: if a
-- keep-alive ped is still sitting in seat -1 the instant you start climbing
-- back in, the game reroutes you to another seat before the poll ever gets
-- a chance to despawn it. GET_VEHICLE_PED_IS_TRYING_TO_ENTER catches the
-- entry attempt itself, so the seat is freed before that resolution happens.
CreateThread(function()
    while true do
        Wait(0)
        local tryingVeh = GetVehiclePedIsTryingToEnter(PlayerPedId())
        if tryingVeh ~= 0 and radioKeepAlive[tryingVeh] then
            despawnRadioKeepAlive(tryingVeh)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(500)

        local veh = currentVehicle()
        if veh ~= lastVehicle then
            if lastVehicle ~= 0 and GetPlayerRadioStationName() ~= 'OFF' then
                spawnRadioKeepAlive(lastVehicle)
            end
            if veh ~= 0 then despawnRadioKeepAlive(veh) end -- getting back in
            lastVehicle = veh
        end

        -- Clean up anything too far away to matter, gone, or that picked up a
        -- real driver in the meantime (someone else got in and drove off).
        local here = GetEntityCoords(PlayerPedId())
        for keepVeh, ped in pairs(radioKeepAlive) do
            local gone = not DoesEntityExist(keepVeh)
                or #(GetEntityCoords(keepVeh) - here) > 80.0
                or (DoesEntityExist(ped) and GetPedInVehicleSeat(keepVeh, -1) ~= ped)
            if gone then despawnRadioKeepAlive(keepVeh) end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RES then return end
    for veh in pairs(radioKeepAlive) do despawnRadioKeepAlive(veh) end
end)

local function odPanelState()
    local sess = odSessionHere()
    local station = sess and (sess.station or 0) or 0
    local stationCfg = station > 0 and (OD.stations or {})[station] or nil
    return {
        inVehicle = currentVehicle() ~= 0,
        engaged   = sess ~= nil,
        playing   = sess ~= nil and sess.playing or false,
        paused    = sess and sess.paused or false,
        index     = sess and sess.index or 0,
        title     = sess and sess.title or nil,
        artist    = sess and sess.artist or nil,
        queue     = sess and sess.queue or {},
        limit     = OD.queueLimit,
        stationLabel = stationCfg and stationCfg.label or nil,
        volume    = math.floor(odVolume * 100 + 0.5),
        maxVolume = OD.maxVolume,
        muted     = odMuted,
    }
end

local function pushPanel()
    if not popupOpen then return end
    SendNUIMessage({ action = 'od', open = true, state = odPanelState() })
end

local function openPanel()
    if popupOpen or not odAvailable() then return end
    popupOpen = true
    -- The wheel is hold-to-open and takes no focus, so the panel cannot live
    -- inside it. It latches the HUD open instead -- without the slow motion,
    -- which follows browsing, not the HUD being on screen.
    SetNuiFocus(true, true)
    pushState(false)
    pushPanel()
    TriggerServerEvent('vi_radio:od:sync')
end

local function closePanel()
    if not popupOpen then return end
    popupOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'od', open = false })
    pushState(false)
end

-- the switch -----------------------------------------------------------------
-- On is a session existing on the server for this vehicle. The station playing
-- at the moment it goes on is handed over with it, so that whoever turns it off
-- again -- which need not be the same player -- puts back the right station.

local function odEngage(withPanel)
    if not odAvailable() or odSessionHere() then return end

    TriggerServerEvent('vi_radio:od:engage', GetPlayerRadioStationName() or 'OFF')
    setStation('OFF')
    odTookCarAt = realMs()
    if withPanel then openPanel() end
end

local function odDisengage(restore)
    if not odSessionHere() then return end

    odPick = nil
    TriggerServerEvent('vi_radio:od:disengage', restore ~= false)
    closePanel()
end

local function odSkip(dir)
    TriggerServerEvent('vi_radio:od:skip', dir < 0 and -1 or 1)
end

-- An On Demand station browsed to. The server takes one command every
-- OD.commandCooldown ms, so stepping through them sends only the one the
-- player stops on, once they have stopped (or let go of the wheel).
local function sendOdPick()
    if not odPick then return end
    local id = odPick.id
    odPick = nil
    local sess = odSessionHere()
    if sess and (sess.station or 0) ~= id then
        TriggerServerEvent('vi_radio:od:station', id)
    end
end

-- wheel ----------------------------------------------------------------------

local function step(dir)
    if #stations == 0 then return end
    stationPicked = true
    index = index + dir
    if index < 1 then index = #stations elseif index > #stations then index = 1 end

    -- Browsing unmutes. Done before the station is applied (it used to be
    -- after), so the new station is not set on a radio still switched off.
    if muted then
        muted = false
        applyMute()
    end

    local entry = stations[index]
    if entry.od ~= nil then
        -- one of On Demand's: it plays as it is reached, once browsing settles
        odPick = { id = entry.od, at = realMs() }
    elseif not odSessionHere() then
        applyStation(entry)
    end
    -- (With the radio's stations listed while On Demand is on, applying each
    -- one as it is scrolled past would start the radio over the top of the
    -- track, so browsing only previews and the choice lands on release.)
    updateTrack(realMs())
    pushState(false)
end

local function openWheel()
    if wheelOpen or popupOpen or not canUseRadio() then return end
    buildStations()
    wheelOpen = true
    stationPicked, panelOnClose = false, false
    navDir, navHeldSince, navLastStep = 0, 0, 0
    playSound(Config.OpenSound)
    LocalPlayer.state:set('vi_radio:open', true, false)
    updateTrack(realMs())
    pushState(true)
end

local function closeWheel()
    if not wheelOpen then return end
    wheelOpen = false
    stickLatched = false
    stickYLatched = false
    openedByControl = false
    playSound(Config.CloseSound)
    LocalPlayer.state:set('vi_radio:open', false, false)

    if Config.Timecycle ~= '' then ClearTimecycleModifier() end
    if Config.HideRadar then DisplayRadar(true) end

    sendOdPick()

    -- Releasing the key is the commit. Skipped when the wheel closed because
    -- the player got out, which is not a choice they made.
    if OD.enabled and currentVehicle() ~= 0 then
        if not OD.stationsInWheel and stationPicked and odSessionHere() and stations[index] then
            applyStation(stations[index])
            -- Browsing to a station is the other way of switching On Demand
            -- off, and the station they just landed on is the one they want --
            -- not the one that was playing before the switch went on. Merely
            -- opening and closing the wheel is not browsing, so it leaves an
            -- On Demand queue alone.
            odDisengage(false)
        elseif panelOnClose and odSessionHere()
               and (stations ~= odList or (stations[index] and stations[index].od == 0)) then
            -- Down asked for the panel. It cannot open while the wheel key is
            -- still held -- NUI focus and hold-to-open cannot share a key --
            -- so it waits here for the release. Not when the player went on to
            -- one of the server's stations: that is not the queue.
            openPanel()
        end
    end

    stationPicked, panelOnClose = false, false

    pushState(false)
end

local function toggleMute()
    if not canUseRadio() then return end
    muted = not muted
    applyMute()
    pushState(false)
    if not wheelOpen and not popupOpen and Config.Hud.enabled then
        -- brief HUD flash so the player sees the mute state change
        SendNUIMessage({ action = 'flash', muted = muted })
    end
end

-- Switched off (VI RADIO WHEEL): GTA's own radio wheel is back, so this one
-- lets go of everything it holds, and a car playing On Demand gets back the
-- station it had before, as the single-player wheel does.
local function standDown()
    if wheelOpen then closeWheel() end
    odPick = nil
    if timeOwned then
        SetTimeScale(1.0)
        timeScaleNow = 1.0
        timeOwned = false
    end
    if odSessionHere() then odDisengage(true) end
    if muted or chaseQuiet then
        muted, chaseQuiet = false, false
        applyMute()
    end
    if dpadHold then dpadHold = false end
    SendNUIMessage({ action = 'state', open = false, index = index - 1, muted = false })
end

local function setWheelEnabled(on)
    on = on and true or false
    SetResourceKvp(KVP_WHEEL, on and '1' or '0')
    if on == wheelEnabled then return end
    wheelEnabled = on
    if on then
        buildStations()
        pushState(true)
    else
        standDown()
    end
end

-- keybinds -------------------------------------------------------------------

RegisterCommand('+vi_radio', function() keyHeld = true end, false)
RegisterCommand('-vi_radio', function() keyHeld = false end, false)
RegisterKeyMapping('+vi_radio', 'VI Radio: hold to open the radio wheel', 'keyboard', Config.OpenKey)

RegisterCommand('vi_radio_mute', function()
    if not wheelEnabled or blockedBy() then return end
    toggleMute()
end, false)
RegisterKeyMapping('vi_radio_mute', 'VI Radio: mute / unmute the radio', 'keyboard', Config.MuteKey)

-- main loop ------------------------------------------------------------------

local function pressed(control) return IsDisabledControlPressed(0, control) end
local function justPressed(control) return IsDisabledControlJustPressed(0, control) end
local function disable(control) DisableControlAction(0, control, true) end

CreateThread(function()
    local pickSettle = (OD.commandCooldown or 400) + 50

    while true do
        local wait = 200

        if not wheelEnabled then
            if wheelOpen then closeWheel() end
            wait = 500
        else
            local now = realMs()

            -- The game's own radio wheel control, on the keyboard and the pad
            -- alike, so it follows the player's binds as GTA's radio does (the
            -- vanilla thread below keeps GTA's own wheel shut). Controllers do
            -- not go through RegisterKeyMapping: a pad binding there is only a
            -- *default*, so it never reaches anyone whose client already
            -- stored a binding for this command. OpenKey is an extra keyboard
            -- key on top. Pad or keyboard is whichever was touched last.
            local usingPad = not IsUsingKeyboard(2)
            local ctrlHeld = (Config.Controller.enabled or not usingPad) and pressed(C.RADIO_WHEEL)
            local held = keyHeld or ctrlHeld
            local blocked = held and blockedBy() or nil
            local wantOpen = held and not blocked and not popupOpen
            if held and blocked and not wheelOpen then lastBlock = blocked end

            if wantOpen and not wheelOpen then
                -- a pad steps with the stick and D-pad; a keyboard with the arrows
                openedByControl = usingPad
                openWheel()
            elseif wheelOpen and (not wantOpen or not canUseRadio()) then
                closeWheel()
            end

            if IsPedInAnyVehicle(PlayerPedId(), false) then
                wait = 0  -- poll every frame so the pad opens without lag
            end

            -- D-pad Down (and Left Alt / Z) stays off while the wheel is open,
            -- and after it closes until it is let go, so a press that muted in
            -- the wheel does not carry on into the game.
            if wheelOpen or dpadHold then
                dpadHold = wheelOpen or pressed(C.CHARACTER_WHEEL) or pressed(C.MULTIPLAYER_INFO)
                if dpadHold then
                    disable(C.CHARACTER_WHEEL)
                    disable(C.MULTIPLAYER_INFO)
                end
            end

            -- An On Demand station browsed to, once browsing has settled.
            if odPick and now - odPick.at >= pickSettle then sendOdPick() end

            local sess = odSessionHere()

            -- GTA's next / previous track keys skip On Demand's songs with the
            -- wheel shut too, while it plays in this car.
            if not wheelOpen and sess and sess.playing and not muted and not chaseQuiet then
                disable(C.NEXT_TRACK)
                disable(C.PREV_TRACK)
                if justPressed(C.NEXT_TRACK) then odSkip(1)
                elseif justPressed(C.PREV_TRACK) then odSkip(-1) end
            end

            if wheelOpen then
                wait = 0

                -- effects
                if Config.Timecycle ~= '' then
                    SetTimecycleModifier(Config.Timecycle)
                    SetTimecycleModifierStrength(Config.TimecycleStrength + 0.0)
                end
                if Config.HiDof then SetUseHiDof() end
                if Config.HideRadar then DisplayRadar(false) end

                -- swallow the inputs we are replacing
                disable(C.RADIO_WHEEL)
                disable(C.NEXT_RADIO)
                disable(C.PREV_RADIO)
                disable(C.NEXT_TRACK)
                disable(C.PREV_TRACK)
                disable(C.PHONE)
                disable(C.HANDBRAKE)    -- Spacebar = mute here
                disable(C.CELL_UP)
                disable(C.CELL_DOWN)
                disable(C.CELL_LEFT)    -- arrow left
                disable(C.CELL_RIGHT)   -- arrow right
                if Config.ScrollRadio then
                    disable(C.WHEEL_NEXT)
                    disable(C.WHEEL_PREV)
                    disable(C.VEH_NEXT_WEAPON)   -- the drive-by weapon select is on the wheel too
                    disable(C.VEH_PREV_WEAPON)
                end
                disable(C.HEADLIGHT)    -- D-pad Right steps here, not the lights

                local pad = openedByControl
                if pad then disable(C.LOOK_BEHIND) end   -- a right-stick click mutes in here

                if pad and Config.Controller.lockCamera then
                    disable(C.LOOK_LR)
                    disable(C.LOOK_UD)
                    disable(C.RIGHT_X)
                    disable(C.RIGHT_Y)
                end

                -- The radio / On Demand switch, reachable from anywhere in the
                -- wheel -- there is nothing to scroll to. It is thrown the way
                -- the artwork reads: RADIO is the top position and ON DEMAND
                -- the bottom one, so down engages On Demand and up hands the
                -- radio back. Split by device, because the same control id is
                -- different hardware depending on what is being held: 172/173
                -- are the arrow keys on a keyboard and the D-pad on a pad, and
                -- 221 is the right stick on a pad but the *mouse* on a
                -- keyboard, which would throw the switch every time the player
                -- looked around.
                if OD.enabled and OD.switchKeys then
                    local up, down = false, false

                    if pad then
                        -- Pushing up reads negative, the same way the game's own
                        -- look control does; a pad that reports it the other way
                        -- round is what invertSwitchAxis is for. One throw a push.
                        local y = GetDisabledControlNormal(0, C.RIGHT_Y)
                        if Config.Controller.invertSwitchAxis then y = -y end

                        if math.abs(y) >= Config.Controller.deadzone then
                            if not stickYLatched then
                                stickYLatched = true
                                if y < 0 then up = true else down = true end
                            end
                        else
                            stickYLatched = false
                        end
                    else
                        stickYLatched = false
                        up   = justPressed(C.CELL_UP)
                        down = justPressed(C.CELL_DOWN)
                    end

                    if down then
                        -- Unmuted first, as browsing does: a muted car's radio
                        -- names no station, so the one handed over to be put
                        -- back would be RADIO OFF.
                        if muted and not odSessionHere() then
                            muted = false
                            applyMute()
                        end
                        odEngage(false)
                        -- Throwing it to On Demand is almost always followed by
                        -- wanting to queue something. Throwing it down again while
                        -- it is already there is therefore how the panel is
                        -- reopened without a command.
                        panelOnClose  = true
                        stationPicked = false
                    elseif up then
                        odDisengage(true)
                        panelOnClose = false
                    end
                end

                -- Mute: Spacebar on a keyboard, a right-stick click on a pad
                -- (the click reads as two controls: one toggle a click however
                -- they arrive). D-pad Down too, unless dpadDownMute is off.
                if Config.MuteInWheel then
                    if pad then
                        if (justPressed(C.FRONTEND_RS) or justPressed(C.LOOK_BEHIND)) and now - muteToggledAt > 250 then
                            muteToggledAt = now
                            toggleMute()
                        elseif Config.Controller.dpadDownMute and justPressed(C.CELL_DOWN) then
                            toggleMute()
                        end
                    elseif justPressed(C.HANDBRAKE) then
                        toggleMute()
                    end
                end

                -- navigation. Left / Right (the right stick on a pad) step
                -- through the stations, the radio's and On Demand's alike;
                -- while On Demand plays, the mouse wheel (D-pad Right / Up on a
                -- pad) and GTA's next / previous track keys change the song.
                sess = odSessionHere()
                local songs = stations == odList and sess ~= nil and sess.playing
                local dir, held, song = 0, 0, 0

                if pad then
                    -- D-pad Left holds the wheel open, so it cannot also mean
                    -- "previous": the right stick, D-pad Right and D-pad Up. The
                    -- stick steps once a push, never again while it's held (held,
                    -- it cycled on and on); a held D-pad still repeats. Clicking
                    -- the stick in to mute nudges it too, and a step unmutes, so
                    -- a click latches the stick until it comes back to the middle.
                    if pressed(C.FRONTEND_RS) or pressed(C.LOOK_BEHIND) then stickLatched = true end
                    local axis = GetDisabledControlNormal(0, C.RIGHT_X)
                    if math.abs(axis) >= Config.Controller.deadzone then
                        if not stickLatched then
                            dir = axis > 0 and 1 or -1
                            stickLatched = true
                        end
                    else
                        stickLatched = false
                        local dpad = justPressed(C.CELL_RIGHT) and 1 or (justPressed(C.CELL_UP) and -1 or 0)
                        if songs then
                            song = dpad
                        else
                            dir = dpad
                            if pressed(C.CELL_RIGHT) then held = 1
                            elseif pressed(C.CELL_UP) then held = -1 end
                        end
                    end
                else
                    stickLatched = false
                    local wheel = 0
                    if Config.ScrollRadio then
                        wheel = justPressed(C.WHEEL_NEXT) and 1 or (justPressed(C.WHEEL_PREV) and -1 or 0)
                    end
                    if justPressed(C.CELL_RIGHT) then dir = 1
                    elseif justPressed(C.CELL_LEFT) then dir = -1
                    elseif songs then song = wheel
                    else dir = wheel end

                    if pressed(C.CELL_RIGHT) then held = 1
                    elseif pressed(C.CELL_LEFT) then held = -1 end
                end
                if songs and song == 0 then
                    song = justPressed(C.NEXT_TRACK) and 1 or (justPressed(C.PREV_TRACK) and -1 or 0)
                end

                if song ~= 0 then odSkip(song) end

                if dir ~= 0 then
                    step(dir)
                    navDir, navHeldSince, navLastStep = dir, now, now
                elseif Config.ArrowAutoRepeat and held ~= 0 and held == navDir then
                    if now - navHeldSince > Config.AutoRepeatDelay
                       and now - navLastStep > Config.AutoRepeatRate then
                        step(held)
                        navLastStep = now
                    end
                elseif held == 0 then
                    navDir = 0
                end
            end
        end

        Wait(wait)
    end
end)

-- slow motion ----------------------------------------------------------------
-- Kept in its own thread so the easing is smooth and so it can be switched off
-- entirely (Config.TimeScale = 1.0) without touching the rest of the script.
-- It follows `wheelOpen` only: the On Demand panel leaves the world at normal
-- speed, because nobody should be typing a link in 0.075x time. Eased on real
-- time, TimeScaleFade ms either way at any frame rate (it stepped 16 /
-- TimeScaleFade a frame, which is only that at 60 fps), and left alone while
-- the crash cam (vi_crashcam) is running time itself.

CreateThread(function()
    if Config.TimeScale >= 1.0 then return end
    local last = realMs()
    while true do
        local now = realMs()
        local dt = math.max(0, math.min(100, now - last))
        last = now

        if not timeOwned and not wheelOpen then
            Wait(200)
        elseif exportSays('vi_crashcam', 'IsCrashCamPlaying') then
            timeOwned = false
            Wait(0)
        else
            if not timeOwned then
                -- Taken fresh (or back from the crash cam, which leaves it at
                -- normal speed): ease down from 1. There is no native to ask.
                timeOwned = true
                timeScaleNow = 1.0
            end
            local target = wheelOpen and Config.TimeScale or 1.0
            if math.abs(timeScaleNow - target) > 0.001 then
                local stepSize = dt / math.max(Config.TimeScaleFade, 1)
                if timeScaleNow < target then
                    timeScaleNow = math.min(target, timeScaleNow + stepSize)
                else
                    timeScaleNow = math.max(target, timeScaleNow - stepSize)
                end
                SetTimeScale(timeScaleNow + 0.0)
            elseif not wheelOpen then
                if timeScaleNow ~= 1.0 then SetTimeScale(1.0) end
                timeScaleNow = 1.0
                timeOwned = false
            end
            Wait(0)
        end
    end
end)

-- vanilla radio HUD and controls ---------------------------------------------
-- The stock wheel shares its button with ours on both keyboard (Q) and pad
-- (D-pad Left), so it has to be suppressed every frame, not only while open.
-- GTA's next / previous station keys keep working on a keyboard (the HUD
-- follows the station); on a pad they share D-pad Left with the wheel. With
-- the wheel switched off, all of it is GTA's again.

CreateThread(function()
    while true do
        if wheelEnabled and (Config.DisableRadioHUD or Config.DisableVanillaRadioControls) then
            if Config.DisableRadioHUD then
                HideHudComponentThisFrame(HUD_RADIO_STATIONS)
            end
            if Config.DisableVanillaRadioControls then
                disable(C.RADIO_WHEEL)
                if not IsUsingKeyboard(2) then
                    disable(C.NEXT_RADIO)
                    disable(C.PREV_RADIO)
                end
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- the song, and the HUD held off ---------------------------------------------
-- The song and artist are looked up every 250 ms, and the lines sent when they
-- change. Nothing of the HUD shows over the pause menu, a cutscene or a black
-- screen, as in single player.

CreateThread(function()
    local held = false
    while true do
        if wheelEnabled and Config.Hud.enabled then
            updateTrack(realMs())
            pushLines()
            local hold = paused() or busy()
            if hold ~= held then
                held = hold
                SendNUIMessage({ action = 'hold', held = held })
            end
        elseif held then
            held = false
            SendNUIMessage({ action = 'hold', held = false })
        end
        Wait(250)
    end
end)

-- housekeeping ---------------------------------------------------------------
-- Re-apply mute when the player changes vehicle, and keep the idle HUD in sync
-- with whatever else on the server might have changed the station.

-- On Demand has the car while its radio stays off. A station put on another
-- way (GTA's next / previous station keys, or GTA's own wheel with VI RADIO
-- WHEEL off) throws the switch back to the radio, keeping that station. A
-- muted (or chase-quiet) car keeps naming the station it had, and a car whose
-- radio has only just been put off can still name it for a moment: neither is
-- someone tuning in, so in those first 2 s the radio is put off again instead.
local function odGuardRadio(playing)
    if not odSessionHere() or currentVehicle() == 0 then return end
    if not playing or playing == '' or playing == 'OFF' then return end
    if muted or chaseQuiet then return end
    if realMs() - odTookCarAt < 2000 then
        setStation('OFF')
        return
    end
    odDisengage(false)
end

CreateThread(function()
    local lastStation = nil
    while true do
        if (muted or chaseQuiet) and currentVehicle() ~= mutedVehicle then applyMute() end
        if wheelEnabled then chaseMusic() end

        local playing = GetPlayerRadioStationName()
        odGuardRadio(playing)

        if playing ~= lastStation then
            lastStation = playing
            if wheelEnabled and not wheelOpen and stations == radioList and #stations > 0 then
                index = playingIndex(radioList) or index
                pushState(false)
            end
        end

        -- the list follows the switch, whoever threw it
        if wheelEnabled and syncList() then pushState(true) end

        if popupOpen and currentVehicle() == 0 then closePanel() end

        Wait(500)
    end
end)

-- On Demand ------------------------------------------------------------------
-- The server says what is playing and how far into it; this side only decides
-- whether this player is close enough to hear it, and keeps xsound pointed at
-- the vehicle. xsound itself handles the falloff and the silencing at range.

local function odDestroy(netId)
    if not OD.enabled then return end
    local id = odSoundId(netId)
    if exports['xsound']:soundExists(id) then
        exports['xsound']:Destroy(id)
    end
    odLowpassState[id] = nil
    odAppliedVolume[id] = nil
end

-- Quiet over the pause menu, a cutscene, a black screen and death, as the
-- single-player wheel's own music is. The sounds keep running at no volume,
-- so they come back in step.
local function odQuietEverywhere()
    return paused() or busy() or playerDead()
end

-- The game's radio volume (0-10), which single player plays its own music at.
local function radioVolumeFactor()
    if not OD.followRadioVolume then return 1.0 end
    local v = GetProfileSetting(301)
    if type(v) ~= 'number' then return 1.0 end
    return math.max(0, math.min(10, v)) / 10
end

-- What this listener hears a session at: their volume, times the game's radio
-- volume, or nothing while it is quiet (everywhere, or for this car while it is
-- muted or the chase music has it).
local function odVolumeFor(netId, quietAll, factor, mine)
    if quietAll then return 0.0 end
    if netId == mine and (muted or chaseQuiet) then return 0.0 end
    return odVolume * factor
end

RegisterNetEvent('vi_radio:od:state', function(data)
    if type(data) ~= 'table' or type(data.netId) ~= 'number' then return end
    local netId = data.netId
    local mine = netId == myNetId()

    -- `gone` is the switch going off. Anything else is the switch being on,
    -- whether or not a track happens to be playing right now.
    if data.gone then
        odDestroy(netId)
        odSessions[netId] = nil

        if data.restore and mine then setStation(data.restore) end
    else
        local prev = odSessions[netId]
        local sess = prev or { netId = netId }

        -- A new token means a different track, which needs a fresh player.
        if not prev or prev.token ~= data.token then sess.restart = true end
        if not prev and mine then odTookCarAt = realMs() end

        sess.playing  = data.playing and true or false
        sess.token    = data.token
        sess.url      = data.url
        sess.title    = data.title
        sess.artist   = data.artist
        sess.duration = data.duration
        sess.index    = data.index
        sess.queue    = data.queue or {}
        sess.station  = tonumber(data.station) or 0
        sess.paused   = data.paused or false
        sess.position = data.position or 0.0
        sess.recvAt   = GetGameTimer()

        odSessions[netId] = sess
    end

    if mine then
        local changed = wheelEnabled and syncList(data.gone and data.restore or nil)
        if not wheelOpen and stations == odList then index = playingIndex(odList) or index end
        pushState(changed)
        pushPanel()
    end
end)

RegisterNetEvent('vi_radio:od:notify', function(message)
    if popupOpen then
        SendNUIMessage({ action = 'od', notice = message })
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('~y~VI Radio~s~: ' .. tostring(message))
        EndTextCommandThefeedPostTicker(false, true)
    end
end)

CreateThread(function()
    -- Far enough out that xsound's own caching (which silences and restores a
    -- sound around its falloff radius) does the fine-grained work, and this
    -- only decides whether a player exists at all.
    local keepAlive = OD.distance + 60.0

    -- OD.enabled is re-read every pass rather than once: the startup check
    -- below can switch On Demand off after this thread has already begun.
    while true do
        local here = OD.enabled and GetEntityCoords(PlayerPedId()) or nil
        local quietAll = here and odQuietEverywhere() or false
        local factor = here and radioVolumeFactor() or 1.0
        local mine = here and myNetId() or nil

        for netId, sess in pairs(here and odSessions or {}) do
            local id  = odSoundId(netId)
            local veh = NetworkDoesNetworkIdExist(netId) and NetToVeh(netId) or 0
            local pos = (veh ~= 0 and DoesEntityExist(veh)) and GetEntityCoords(veh) or nil
            local audible = sess.playing and pos ~= nil and not odMuted
                            and odVolume * factor > 0.0 and #(pos - here) <= keepAlive
            local volume = odVolumeFor(netId, quietAll, factor, mine)

            if audible then
                -- Muffle once outside a tight "in/right next to the vehicle"
                -- radius. No-op for YouTube tracks played through the
                -- embedded iframe (SoundPlayer.js's initLowpass refuses to
                -- run for those) -- this only actually does anything once a
                -- track is playing through the Howl/file path, i.e. a direct
                -- file link or a YouTube link resolved to a raw audio stream
                -- by server.lua's resolveAudioStream.
                local distFromVeh = #(pos - here)
                local shouldMuffle = distFromVeh > (OD.distance * 0.4)
                if odLowpassState[id] ~= shouldMuffle then
                    odLowpassState[id] = shouldMuffle
                    exports['xsound']:SetLowpassSound(id, shouldMuffle)
                end

                local exists = exports['xsound']:soundExists(id)

                if sess.restart or not exists then
                    sess.restart = nil
                    if exists then exports['xsound']:Destroy(id) end

                    local token = sess.token
                    exports['xsound']:PlayUrlPos(id, sess.url, volume, pos, false, {
                        -- Seeking before the player has loaded does nothing, so
                        -- the catch-up happens once it reports it is playing.
                        onPlayStart = function()
                            local live = odSessions[netId]
                            if not live or live.token ~= token then return end
                            exports['xsound']:setTimeStamp(id, odElapsed(live))
                            if live.paused then exports['xsound']:Pause(id) end

                            local duration = exports['xsound']:getMaxDuration(id)
                            if duration and duration > 0 and not live.duration then
                                TriggerServerEvent('vi_radio:od:duration', netId, token, duration + 0.0)
                            end
                        end,
                    })
                    exports['xsound']:Distance(id, OD.distance)
                    exports['xsound']:destroyOnFinish(id, false)
                    odAppliedVolume[id] = volume
                else
                    exports['xsound']:Position(id, pos)

                    if odAppliedVolume[id] ~= volume then
                        odAppliedVolume[id] = volume
                        exports['xsound']:setVolumeMax(id, volume)
                    end

                    local isPaused = exports['xsound']:isPaused(id)
                    if sess.paused and not isPaused then
                        exports['xsound']:Pause(id)
                    elseif not sess.paused and isPaused then
                        exports['xsound']:Resume(id)
                        exports['xsound']:setTimeStamp(id, odElapsed(sess))
                    end

                    if not sess.paused then
                        local at = exports['xsound']:getTimeStamp(id)
                        if at and at >= 0 and math.abs(at - odElapsed(sess)) > OD.resyncDrift then
                            exports['xsound']:setTimeStamp(id, odElapsed(sess))
                        end
                    end

                    if not sess.duration then
                        local duration = exports['xsound']:getMaxDuration(id)
                        if duration and duration > 0 then
                            TriggerServerEvent('vi_radio:od:duration', netId, sess.token, duration + 0.0)
                        end
                    end
                end
            else
                odDestroy(netId)
            end
        end

        Wait(OD.syncInterval)
    end
end)

-- panel callbacks ------------------------------------------------------------

RegisterNUICallback('odClose', function(_, cb)
    closePanel()
    cb('ok')
end)

RegisterNUICallback('odAdd', function(data, cb)
    local url, err = Config.NormalizeUrl(data and data.url)
    if not url then
        cb({ ok = false, error = err })
        return
    end
    TriggerServerEvent('vi_radio:od:add', url, data.playNow and true or false)
    cb({ ok = true })
end)

RegisterNUICallback('odRemove', function(data, cb)
    if data and type(data.index) == 'number' then
        TriggerServerEvent('vi_radio:od:remove', data.index)
    end
    cb('ok')
end)

RegisterNUICallback('odSkip', function(data, cb)
    TriggerServerEvent('vi_radio:od:skip', (data and data.dir == -1) and -1 or 1)
    cb('ok')
end)

RegisterNUICallback('odPause', function(_, cb)
    TriggerServerEvent('vi_radio:od:pause')
    cb('ok')
end)

RegisterNUICallback('odStop', function(_, cb)
    TriggerServerEvent('vi_radio:od:stop')
    cb('ok')
end)

RegisterNUICallback('odDisengage', function(_, cb)
    odDisengage(true)
    cb('ok')
end)

-- Volume and mute are per listener and never leave this client. They are the
-- one protection that does not restrict who may play something: anyone can
-- broadcast, but nobody has to listen at a volume they did not choose.
local function setOdVolume(value)
    value = math.max(0, math.min(OD.maxVolume, tonumber(value) or 0))
    odVolume = value / 100
    SetResourceKvp('vi_radio:od_volume', tostring(value))

    local quietAll, factor, mine = odQuietEverywhere(), radioVolumeFactor(), myNetId()
    for netId in pairs(odSessions) do
        local id = odSoundId(netId)
        if exports['xsound']:soundExists(id) then
            local volume = odVolumeFor(netId, quietAll, factor, mine)
            odAppliedVolume[id] = volume
            exports['xsound']:setVolumeMax(id, volume)
        end
    end
end

RegisterNUICallback('odVolume', function(data, cb)
    setOdVolume(data and data.volume)
    pushPanel()
    cb('ok')
end)

RegisterNUICallback('odMute', function(data, cb)
    odMuted = data and data.muted and true or false
    SetResourceKvp('vi_radio:od_muted', odMuted and '1' or '0')
    if odMuted then
        for netId in pairs(odSessions) do odDestroy(netId) end
    end
    pushPanel()
    cb('ok')
end)

-- commands -------------------------------------------------------------------

RegisterCommand('ondemand', function(_, args)
    if not OD.enabled then return end
    if currentVehicle() == 0 then
        TriggerEvent('vi_radio:od:notify', 'You have to be in a vehicle')
        return
    end

    if args[1] then
        local url, err = Config.NormalizeUrl(table.concat(args, ' '))
        if not url then
            TriggerEvent('vi_radio:od:notify', err)
            return
        end
        if not odSessionHere() then
            setStation('OFF')
            odTookCarAt = realMs()
        end
        TriggerServerEvent('vi_radio:od:add', url, false)
        return
    end

    -- With the switch already on this just reopens the panel; with it off it
    -- flips it on, which opens the panel anyway.
    if odSessionHere() then openPanel() else odEngage(true) end
end, false)

-- debug ----------------------------------------------------------------------
-- /viradio_debug prints why the wheel is or is not responding.

RegisterCommand('viradio_debug', function()
    local ok, kbm = pcall(function() return IsUsingKeyboard(2) end)
    print(('[vi_radio] wheelEnabled=%s inVehicle=%s seatAllowed=%s stations=%d list=%s open=%s panel=%s viaPad=%s keyHeld=%s ctrl85=%s keyboardAndMouse=%s muted=%s chaseQuiet=%s blockedNow=%s lastBlocked=%s'):format(
        tostring(wheelEnabled),
        tostring(IsPedInAnyVehicle(PlayerPedId(), false)),
        tostring(currentVehicle() ~= 0),
        #stations,
        stations == odList and 'ondemand' or 'radio',
        tostring(wheelOpen),
        tostring(popupOpen),
        tostring(openedByControl),
        tostring(keyHeld),
        tostring(IsDisabledControlPressed(0, C.RADIO_WHEEL)),
        ok and tostring(kbm) or 'n/a',
        tostring(muted),
        tostring(chaseQuiet),
        tostring(blockedBy()),
        tostring(lastBlock)))
    print(('[vi_radio] song: id=%s title=%s artist=%s'):format(
        tostring(trk.audible), tostring(shownTrack.title), tostring(shownTrack.artist)))

    local sessionCount = 0
    for netId, sess in pairs(odSessions) do
        sessionCount = sessionCount + 1
        print(('[vi_radio] on demand netId=%d station=%d track=%s at=%.1fs paused=%s queue=%d sound=%s'):format(
            netId,
            sess.station or 0,
            tostring(sess.title),
            odElapsed(sess),
            tostring(sess.paused),
            #(sess.queue or {}),
            tostring(OD.enabled and exports['xsound']:soundExists(odSoundId(netId)))))
    end
    print(('[vi_radio] on demand sessions=%d volume=%.2f radioVolume=%.1f localMute=%s'):format(
        sessionCount, odVolume, radioVolumeFactor(), tostring(odMuted)))
end, false)

-- exports --------------------------------------------------------------------
-- FiveM has no native that resolves the current track title, so the title and
-- artist lines are driven from outside. Any resource that knows what is playing
-- (custom streamed stations, xsound, a metadata feed) can push it in here.
-- (The game's own stations name their songs themselves now, from the game's
-- labels; what is pushed in here wins over those. SetNowPlaying(nil, nil)
-- hands the lines back to the game.)

local function setNowPlaying(title, artist)
    nowPlaying.title  = title
    nowPlaying.artist = artist
    pushState(false)
end

exports('SetNowPlaying', setNowPlaying)
RegisterNetEvent('vi_radio:setNowPlaying', setNowPlaying)

exports('IsOpen', function() return wheelOpen end)
exports('IsMuted', function() return muted end)
exports('SetMuted', function(state)
    if state == muted then return end
    muted = state and true or false
    applyMute()
    pushState(false)
end)
exports('GetStation', function()
    if odSessionHere() then return ON_DEMAND end
    return GetPlayerRadioStationName()
end)

exports('IsOnDemandOn', function() return odSessionHere() ~= nil end)
exports('IsOnDemandPlaying', function()
    local sess = odSessionHere()
    return sess ~= nil and sess.playing == true
end)
exports('SetOnDemand', function(on)
    if on then odEngage(false) else odDisengage(true) end
end)
exports('GetOnDemandTrack', function()
    local sess = odSessionHere()
    if not sess then return nil end
    return { title = sess.title, artist = sess.artist, paused = sess.paused, position = odElapsed(sess) }
end)
exports('OpenOnDemand', openPanel)

-- VI RADIO WHEEL (HUD OPTIONS): this wheel, or GTA's own. Kept per player.
exports('GetWheelEnabled', function() return wheelEnabled end)
exports('SetWheelEnabled', setWheelEnabled)

-- cleanup --------------------------------------------------------------------

AddEventHandler('onResourceStop', function(name)
    if name ~= RES then return end
    SetTimeScale(1.0)
    ClearTimecycleModifier()
    DisplayRadar(true)
    SetNuiFocus(false, false)
    LocalPlayer.state:set('vi_radio:open', false, false)
    if muted or chaseQuiet then
        muted, chaseQuiet = false, false
        applyMute()
    end
    for netId in pairs(odSessions) do odDestroy(netId) end
end)

CreateThread(function()
    -- On Demand is the only part of this resource that needs anything else
    -- installed. Without xsound it switches itself off rather than erroring on
    -- every export call; the radio wheel carries on working.
    if OD.enabled and GetResourceState('xsound') ~= 'started' then
        OD.enabled = false
        print('[vi_radio] xsound is not started, On Demand is disabled')
    end

    local storedVolume = GetResourceKvpString('vi_radio:od_volume')
    if storedVolume then
        odVolume = math.max(0, math.min(OD.maxVolume, tonumber(storedVolume) or OD.volume)) / 100
    end
    odMuted = GetResourceKvpString('vi_radio:od_muted') == '1'

    local storedWheel = GetResourceKvpString(KVP_WHEEL)
    if storedWheel == '1' then wheelEnabled = true
    elseif storedWheel == '0' then wheelEnabled = false end

    while not NetworkIsSessionStarted() do Wait(250) end
    buildStations()
    if wheelEnabled then pushState(true) end
    if OD.enabled then TriggerServerEvent('vi_radio:od:sync') end
end)
