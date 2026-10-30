--[[
    VI Radio - configuration
    This mirrors the "VI Radio.ini" from the original singleplayer mod, and the
    [Radio] section of the single-player HUD's ViExtras.ini, which was ported
    from this resource and has since moved on; the defaults here are that
    port's. Plus a few FiveM-only options.
]]

Config = {}

-- ---------------------------------------------------------------------------
-- On / off
-- ---------------------------------------------------------------------------
-- The VI radio wheel in place of GTA's own. Off hands everything back to GTA:
-- its radio wheel and station HUD, its next / previous station keys, and no
-- slow motion. Each player can switch it in HUD OPTIONS (VI RADIO WHEEL, or
-- exports['vi_radio']:SetWheelEnabled); their choice is kept on their client.
-- This is the default for anyone who has not chosen.
Config.WheelEnabled = true

-- ---------------------------------------------------------------------------
-- Controls
-- ---------------------------------------------------------------------------
-- The wheel opens on the game's own radio wheel control (INPUT_VEH_RADIO_WHEEL:
-- Q, or D-pad Left, or wherever the player's GTA settings put it), on the
-- keyboard and the pad alike, as GTA's radio wheel does. OpenKey is an extra
-- keyboard key on top of that; players can rebind both keys below in FiveM
-- (Settings -> Key Bindings -> FiveM), these are only the defaults.
Config.OpenKey         = 'Q'    -- also hold to open the radio wheel
Config.MuteKey         = 'O'    -- toggle mute / unmute, in a vehicle

Config.ScrollRadio     = true   -- mouse wheel also cycles stations while open
Config.ArrowAutoRepeat = true   -- holding left/right keeps cycling
Config.AutoRepeatDelay = 350    -- ms before auto repeat kicks in (real time)
Config.AutoRepeatRate  = 120    -- ms between repeats (real time)

-- Controller support.
-- The wheel opens on INPUT_VEH_RADIO_WHEEL (D-pad Left by default), read
-- directly rather than through a FiveM key binding -- key bindings only ever
-- set a *default*, so a pad binding added after the fact never reaches a
-- client that already stored one. Whether the pad or the keyboard steers is
-- decided by whichever the player touched last. Because D-pad Left is held to
-- keep the wheel open, and is also INPUT_CELLPHONE_LEFT, stations are browsed
-- with the right stick (one station a push), D-pad Right and D-pad Up instead.
Config.Controller = {
    enabled    = true,
    deadzone   = 0.5,   -- right stick travel before a station change registers
    lockCamera = true,  -- stop the right stick swinging the camera while browsing

    -- The right stick's vertical axis flips the On Demand switch. Pushing up
    -- normally reads negative, the same way the game's own look control does.
    -- If your pad reports it the other way round, set this to true.
    -- Leave lockCamera on unless you like the view tilting as you flip it.
    invertSwitchAxis = false,

    -- Mute in the wheel is a right-stick click, as in single player. D-pad
    -- Down muted here before that, and still does unless this is false
    -- (single player gave it up because D-pad Down is its character wheel).
    dpadDownMute = true,
}

-- Mute from inside the wheel. Up and down belong to the On Demand switch, so
-- this sits on Spacebar on a keyboard (handbrake, which is not much use while
-- you are reading the radio anyway) and on a right-stick click on a controller.
-- The O binding above works in any vehicle, wheel or not.
Config.MuteInWheel = true

-- Keep the game's own radio wheel shut, so it cannot flash open on the same
-- button. GTA's next / previous station keys still work on a keyboard (the HUD
-- follows the station); on a pad they share D-pad Left with the wheel, so
-- there they are off.
Config.DisableVanillaRadioControls = true

-- Who may open the wheel. The wheel is vehicle-only by default, which is what
-- keeps the controller bindings from clashing with anything on foot.
-- DriverOnly also gates the mute key and every On Demand change server-side
-- (see vehicleNetId in server.lua); passengers still hear whatever is playing.
Config.DriverOnly      = true   -- false = driver or passenger; true = driver only
Config.AllowOnFoot     = false  -- true = also works with the mobile radio on foot

-- Menus the radio stands down for. Each entry is a state bag key on the LOCAL
-- player that another resource holds true while its full-screen menu is up.
-- The pad is read directly (see Controller above), so without this a menu that
-- steers with the D-pad opens the wheel on every "left". While any key reads
-- true the wheel and the mute key do nothing; whatever is playing carries on.
-- (The pause menu, a cutscene, a black screen, the phone, being dead, the
-- crash cam and the binoculars hold it shut too, as in single player.)
--   'customs:menuOpen'   the mod shop (Lenonida_customs)
Config.BlockedBy = { 'customs:menuOpen' }

-- ---------------------------------------------------------------------------
-- Feel / effects
-- ---------------------------------------------------------------------------
-- NOTE: SetTimeScale is client side only. On a busy server it will visibly
-- desync your vehicle from everyone else while the wheel is open. 1.0 disables
-- the slow-motion entirely and keeps just the HUD.
Config.TimeScale       = 0.075
Config.TimeScaleFade   = 180    -- real ms to ease in/out of slow motion

Config.Timecycle         = 'hud_def_blur'
Config.TimecycleStrength = 1.0
Config.HiDof             = true

Config.HideRadar       = true   -- hide the minimap while the wheel is open
Config.DisableRadioHUD = true   -- permanently hide the vanilla radio station HUD

Config.RadioSounds     = true
Config.OpenSound       = 'sfx/radioopen.wav'
Config.CloseSound      = 'sfx/radioclose.wav'
Config.SoundVolume     = 20     -- 0-100; the open / close clicks, kept subtle

-- Let the car radio carry outside the car, as the game's "big speaker" cars do.
Config.LoudRadio       = true

-- While you are wanted and the game's chase music plays, the car radio goes
-- quiet, and comes back 3 s after the music stops or at once when the stars go.
-- Your own mute is left as it was. false lets them play together.
Config.ChaseMusicTakesOver = true

-- ---------------------------------------------------------------------------
-- HUD layout (values are in 1920x1080 reference pixels and scale with the
-- player resolution, same as the original ini). The defaults are the single-
-- player HUD's look, measured off the user's reference shots: each logo fills
-- its tile, every tile at full size and opacity out to two either side (they
-- fade on the way to the third), the highlighted one a little larger with a
-- thin light outline, and the line and text in a light grey without a shadow.
-- ---------------------------------------------------------------------------
Config.Hud = {
    enabled           = true,
    iconSize          = 103,
    spacing           = 118,
    top               = 32,
    borderSize        = 2.5,                -- the highlighted tile's outline
    boxColor          = '0,0,0,170',        -- behind each logo
    boxActiveColor    = '0,0,0,170',
    borderColor       = '255,255,255,0',    -- outline of the other tiles (none)
    borderActiveColor = '192,194,200,255',  -- outline of the highlighted tile
    inkColor          = '192,194,200,255',  -- the line and the text under it
    activeScale       = 1.03,               -- the highlighted tile
    inactiveScale     = 1.0,                -- the others (the original: 0.9)
    inactiveOpacity   = 1.0,                -- the others (the original: 0.55)
    textShadow        = false,              -- the original's shadow under the text
    slideTime         = 110,    -- ms for the carousel slide animation
    sideIcons         = true,
    sideGap           = 37,
    leftIcon          = 'icons/On_Demand.png',
    rightIcon         = 'icons/Mute.png',
    unmuteIcon        = 'icons/Unmute.png',
    muteColor         = '255,255,255',  -- indicator colour while the radio plays
    mutedColor        = '255,59,48',    -- indicator colour while muted
    muteDim           = true,           -- drain the rest of the HUD of colour when muted
    leftIconHeight    = 55,
    rightIconHeight   = 24,
    infoLineY         = 20,
    infoLineWidth     = 189,
    infoLineHeight    = 4.8,
    stationY          = 34.7,
    stationScale      = 0.253,
    titleY            = 70.6,
    titleScale        = 0.206,
    artistY           = 97.2,
    artistScale       = 0.206,
    fontPx            = 100,    -- base size the *Scale values multiply
    stationLogos      = true,
    -- Under the station name go the song playing and its artist (the game's
    -- own names for them). With no song -- a talk station -- the line under it
    -- is the station's genre from the table below; 'none' leaves it empty.
    subtitle          = 'genre',
}

-- ---------------------------------------------------------------------------
-- Stations
-- ---------------------------------------------------------------------------
-- Stations not listed here still appear (using their raw name) as long as the
-- game reports them unlocked. Add hidden = true to drop one from the wheel, or
-- list game names in HiddenStations.
Config.IncludeOff = true        -- include the "Radio Off" entry
Config.HiddenStations = {}      -- e.g. { 'RADIO_05_TALK_01', 'RADIO_11_TALK_02' }

-- Note: an audio scene left running for the whole session can silence the car
-- radio while the HUD still shows the station (CHARACTER_CHANGE_IN_SKY_SCENE,
-- which qbx_smallresources' `disable.ambience` starts, does exactly that). An
-- audio scene belongs to the resource that started it, so this resource cannot
-- stop it; the resource that starts the scene has to lift it while a station
-- plays (um_smallresources does, in qbx_ignore/client.lua).
Config.OffLabel   = 'RADIO OFF'

Config.Stations = {
    ['RADIO_01_CLASS_ROCK']            = { label = 'Los Santos Rock Radio',     logo = 'LosSantosRockRadio.png',     genre = 'Classic Rock' },
    ['RADIO_02_POP']                   = { label = 'Non-Stop-Pop FM',           logo = 'Non-Stop-PopFM.png',         genre = 'Pop' },
    ['RADIO_03_HIPHOP_NEW']            = { label = 'Radio Los Santos',          logo = 'RadioLosSantos.png',         genre = 'Contemporary Hip Hop' },
    ['RADIO_04_PUNK']                  = { label = 'Channel X',                 logo = 'ChannelX.png',               genre = 'Punk' },
    ['RADIO_05_TALK_01']               = { label = 'West Coast Talk Radio',     logo = 'WestCoastTalkRadio.png',     genre = 'Talk' },
    ['RADIO_06_COUNTRY']               = { label = 'Rebel Radio',               logo = 'RebelRadio.png',             genre = 'Country' },
    ['RADIO_07_DANCE_01']              = { label = 'Soulwax FM',                logo = 'SoulwaxFM.png',              genre = 'Dance' },
    ['RADIO_08_MEXICAN']               = { label = 'East Los FM',               logo = 'EastLosFM.png',              genre = 'Mexican' },
    ['RADIO_09_HIPHOP_OLD']            = { label = 'West Coast Classics',       logo = 'WestCoastClassics.png',      genre = 'Classic Hip Hop' },
    ['RADIO_11_TALK_02']               = { label = 'Blaine County Radio',       logo = 'BlaineCountyRadio.png',      genre = 'Talk' },
    ['RADIO_12_REGGAE']                = { label = 'Blue Ark',                  logo = 'TheBlueArk.png',             genre = 'Reggae' },
    ['RADIO_13_JAZZ']                  = { label = 'Worldwide FM',              logo = 'WorldWideFM.png',            genre = 'Jazz' },
    ['RADIO_14_DANCE_02']              = { label = 'FlyLo FM',                  logo = 'FlyloFM.png',                genre = 'Electronic' },
    ['RADIO_15_MOTOWN']                = { label = 'The Lowdown 91.1',          logo = 'TheLowdown91.1.png',         genre = 'Motown' },
    ['RADIO_16_SILVERLAKE']            = { label = 'Radio Mirror Park',         logo = 'RadioMirrorPark.png',        genre = 'Indie' },
    ['RADIO_17_FUNK']                  = { label = 'Space 103.2',               logo = 'Space103.2.png',             genre = 'Funk' },
    ['RADIO_18_90s_ROCK']              = { label = 'Vinewood Boulevard Radio',  logo = 'VinewoodBoulevardRadio.png', genre = 'Alternative Rock' },
    ['RADIO_19_USER']                  = { label = 'Self Radio',                logo = 'SelfRadio.png',              genre = 'Your Music' },
    ['RADIO_20_THELAB']                = { label = 'The Lab',                   logo = 'TheLab.png',                 genre = 'Experimental' },
    ['RADIO_21_DLC_XM17']              = { label = 'Blonded Los Santos 97.8',   logo = 'BlondedLosSantos.png',       genre = 'Contemporary' },
    ['RADIO_22_DLC_BATTLE_MIX1_RADIO'] = { label = 'LS Underground Radio',      logo = 'LSUndergroundRadio.png',     genre = 'House' },
    ['RADIO_23_DLC_XM19_RADIO']        = { label = 'iFruit Radio',              logo = 'iFruitRadio.png',            genre = 'Alternative' },
    ['RADIO_27_DLC_PRHEI4']            = { label = 'Still Slipping Los Santos', logo = 'StillSlipping.png',          genre = 'Hip Hop' },
    ['RADIO_34_DLC_HEI4_KULT']         = { label = 'Kult FM',                   logo = 'KultFM.png',                 genre = 'Post-Punk' },
    ['RADIO_35_DLC_HEI4_MLR']          = { label = 'The Music Locker',          logo = 'TheMusicLocker.png',         genre = 'House' },
    ['RADIO_36_AUDIOPLAYER']           = { label = 'Media Player',              logo = 'MediaPlayer.png',            genre = 'Custom' },
    ['RADIO_37_MOTOMAMI']              = { label = 'MOTOMAMI Los Santos',       logo = 'MOTOMAMI.png',               genre = 'Latin' },
}

-- ---------------------------------------------------------------------------
-- On Demand
-- ---------------------------------------------------------------------------
-- The On Demand entry plays YouTube links (and direct audio files) through the
-- car radio using xsound. Audio is positioned at the vehicle, so passengers and
-- anyone stood nearby hear the same thing at the same point in the track.
--
-- Note: xsound plays YouTube through the IFrame API. That is not what YouTube's
-- terms of service intend it for. It is how effectively every FiveM audio
-- resource does it, but it is worth knowing before you ship this on a server.
Config.OnDemand = {
    enabled    = true,
    label      = 'ON DEMAND',

    -- The left side icon is a two-position switch, RADIO over ON DEMAND, and it
    -- is thrown the way it reads: down for On Demand, up to hand the radio
    -- back. It works from anywhere in the wheel -- there is nothing to scroll
    -- to. Arrow keys on a keyboard, the right stick on a controller (on a
    -- keyboard the right-stick axis is the mouse). Down also opens the panel
    -- once the wheel is released. Set false to leave up and down alone and
    -- reach the switch only through the panel and /ondemand.
    switchKeys = true,

    -- With the switch down, the wheel lists On Demand's stations, as single
    -- player's lists your own music's: first this vehicle's own queue (the
    -- links pasted into the panel, under `label` above), then each of
    -- `stations` below. Left / Right (the right stick) step through them and
    -- each one plays as it is reached; the mouse wheel (D-pad Right / Up) and
    -- GTA's next / previous track keys change the song. false keeps the radio's
    -- stations listed instead: browsing them only previews, and the one you
    -- let go on switches On Demand off.
    stationsInWheel = true,

    -- On Demand stations. Single player's are folders of your own music on
    -- your disk; a server can only play what it ships or what a link points
    -- at, so here each station is a list of tracks: a path under this
    -- resource's html/ folder (put the files in html/music/<station>/, which
    -- fxmanifest.lua streams -- every player downloads them when they join),
    -- an https:// link to an audio file, or a YouTube link. A track can also
    -- be { url = ..., title = ..., artist = ... }; without a title, a file's
    -- name (or YouTube's title) is used. A station plays its tracks in order,
    -- round and round, and remembers where it was for resumeMinutes.
    --   {
    --       label  = 'CHILL',
    --       genre  = 'Lo-fi',                  -- the line under it, optional
    --       logo   = 'logos/Chill.png',        -- a tile picture, optional
    --       tracks = {
    --           'music/chill/01 Morning.mp3',
    --           { url = 'https://example.com/night.mp3', title = 'Night', artist = 'Someone' },
    --       },
    --   },
    stations = {},
    resumeMinutes = 30,

    queueLimit = 20,       -- tracks a single vehicle may have queued
    -- Lowered from 20.0/35/70 (2026-09-15): reported as too loud, especially
    -- once you'd stepped away from the vehicle. Paired with the xsound
    -- engine's own falloff fix (html/scripts/SoundPlayer.js's updateVolume,
    -- linear -> squared), which is the bigger lever on how it fades with
    -- distance -- this just brings the ceiling down too.
    distance   = 12.0,     -- metres the audio carries from the vehicle
    volume     = 20,       -- default listener volume, 0-100
    maxVolume  = 45,       -- hard cap on what a listener can turn it up to

    -- Your volume is scaled by the game's radio volume setting, as single
    -- player's own music is. false plays it at your volume whatever that is.
    followRadioVolume = true,

    -- Look the track title up through YouTube's oEmbed endpoint so the HUD's
    -- title/artist lines show something real. No API key needed. Set false to
    -- keep the server from making any outbound request.
    fetchTitles = true,

    -- Accept plain audio file links as well as YouTube.
    allowDirectFiles = true,
    fileExtensions   = { 'mp3', 'ogg', 'wav', 'm4a', 'aac', 'flac' },

    -- Playback sync. The server tells clients how far into the track it is;
    -- these control how often that is refreshed and how far a listener may
    -- drift before being seeked back into place.
    broadcastInterval = 10000,  -- ms between position rebroadcasts
    syncInterval      = 400,    -- ms between vehicle-position updates
    resyncDrift       = 3.0,    -- seconds of drift before a reseek

    commandCooldown = 400,      -- ms a player must wait between commands
}

-- ---------------------------------------------------------------------------
-- Link parsing (shared, so the client and the server agree on what is valid)
-- ---------------------------------------------------------------------------
-- Returns a canonical URL and its kind ('youtube' | 'file'), or nil plus a
-- reason. xsound's own YouTube parser only understands "?v=" and "youtu.be/",
-- so everything is normalised to the "?v=" form before it is handed over.

local function youtubeId(chunk)
    if not chunk then return nil end
    local id = chunk:sub(1, 11)
    if #id == 11 and id:match('^[%w_%-]+$') then return id end
    return nil
end

function Config.NormalizeUrl(input)
    if type(input) ~= 'string' then return nil, 'No link given' end

    local url = input:gsub('^%s+', ''):gsub('%s+$', '')
    if url == '' then return nil, 'No link given' end
    if #url > 512 then return nil, 'That link is too long' end
    if url:find('[%s"<>]') or url:find("'") or url:find('\\') then
        return nil, 'That does not look like a link'
    end
    if not url:match('^https?://') then url = 'https://' .. url end

    local host, rest = url:match('^https?://([^/?#]+)(.*)$')
    if not host then return nil, 'That does not look like a link' end
    host = host:lower():gsub('^www%.', '')
    rest = rest or ''

    if host == 'youtu.be' then
        local id = youtubeId(rest:match('^/([^/?#&]+)'))
        if id then return 'https://www.youtube.com/watch?v=' .. id, 'youtube' end
        return nil, 'That YouTube link has no video in it'
    end

    if host == 'youtube.com' or host == 'm.youtube.com' or host == 'music.youtube.com'
       or host == 'youtube-nocookie.com' then
        local id = youtubeId(rest:match('[?&]v=([^&#]+)'))
              or youtubeId(rest:match('^/shorts/([^/?#&]+)'))
              or youtubeId(rest:match('^/embed/([^/?#&]+)'))
              or youtubeId(rest:match('^/live/([^/?#&]+)'))
        if id then return 'https://www.youtube.com/watch?v=' .. id, 'youtube' end
        return nil, 'That YouTube link has no video in it'
    end

    if Config.OnDemand.allowDirectFiles then
        local path = rest:match('^([^?#]*)') or ''
        local ext  = path:match('%.(%w+)$')
        if ext then
            ext = ext:lower()
            for _, allowed in ipairs(Config.OnDemand.fileExtensions) do
                if ext == allowed then return url, 'file' end
            end
        end
        return nil, 'Only YouTube links and direct audio files are supported'
    end

    return nil, 'Only YouTube links are supported'
end
