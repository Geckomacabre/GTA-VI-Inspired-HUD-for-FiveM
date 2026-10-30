--[[ ===========================================================================
     vi_chasemusic — CHASE MUSIC
     ---------------------------------------------------------------------------
     Single player's wanted-level music (GTA6Hud's MusicPlayer). While the
     player has a wanted level, a random track from the server's music folder
     plays, fading in; when one ends another random one follows, never the
     same one twice running. GTA's own wanted music is switched off meanwhile.
     It fades out when the wanted level goes, or when the player dies, is
     being arrested or the screen fades out; it drops to a quarter while the
     weapon wheel or the inventory is open. The pause menu, the switch in HUD
     OPTIONS going off, or the radio playing On Demand music stop it outright.

     The audio plays in this resource's NUI page (vi_chasemusic/html), which
     never takes focus. This side decides what plays and how loud, frame by
     frame, as single player's Update does; the page only plays it, and pauses
     the track where it is when this side stops ticking (single player's stall
     watchdog), so a script error can't leave a track playing forever.

     Public API:
         exports.vi_extras:IsChaseMusicPlaying()     -- a track is playing or fading out
         exports.vi_extras:HoldChaseMusic(key, on)   -- pause the track where it is while
                                                     -- any key holds it: single player's
                                                     -- kill camera, races and shop screens
                                                     -- skip the music, which pauses it
     ========================================================================= ]]

local options = require 'vi_hudoptions.options'
local config = require 'vi_chasemusic.config'

local playing = false       -- a track has been started and not stopped (single player's _playing)
local holds = {}

exports('IsChaseMusicPlaying', function() return playing end)
exports('HoldChaseMusic', function(key, on) holds[tostring(key)] = on and true or nil end)

if not config.enabled then return end

-- single player clamps every [Music] ...Volume key to 0..1
local function volumeKey(v, def) return math.max(0.0, math.min(1.0, tonumber(v) or def)) end
local VOLUME = volumeKey(config.volume, 0.3)
local MUFFLE = tonumber(config.muffleLevel) or 0.25
local MUFFLE_S = tonumber(config.muffleSeconds) or 0.25
local FADE_S = tonumber(config.fadeSeconds) or 1.6
local FADE_IN_S = tonumber(config.fadeInSeconds) or 1.4
local BOOST_S = tonumber(config.boostSeconds) or 0.9
local STALL_MS = math.floor(tonumber(config.stallMs) or 400)
local FOLDER = config.folder or 'music'

local tracks = {}
local lastTrack = 0
local ended = false         -- the track finished or failed; the next frame picks another
local serial = 0            -- which play the page's ended / failed is about
local level = 0.0           -- the volume now, 0..1
local pushedLevel = -1.0    -- the volume the page was last given
local suppressed = false    -- GTA's wanted music is off
local pageReady = false
local nextBeat = 0

-- ---------------------------------------------------------------------------
-- HUD OPTIONS: ON / OFF, or NONE while the server has no tracks, as single
-- player shows it with an empty Music folder (pressing it still flips the
-- setting underneath, as there).
-- ---------------------------------------------------------------------------
local NONE = { { v = true, label = 'NONE' }, { v = false, label = 'NONE' } }

local stop  -- below

local row = options.add({
    id = 'chasemusic', label = 'CHASE MUSIC', default = config.default ~= false,
    desc = 'Music plays while the police are after you.',
    onChange = function(on) if not on and stop then stop() end end,
})
row.values = NONE

local function setTracks(list)
    tracks = {}
    if type(list) == 'table' then
        for _, name in ipairs(list) do
            if type(name) == 'string' then tracks[#tracks + 1] = name end
        end
    end
    lastTrack = 0
    row.values = #tracks == 0 and NONE or nil
end

setTracks(GlobalState.viChaseMusicTracks)
AddStateBagChangeHandler('viChaseMusicTracks', 'global', function(_, _, value) setTracks(value) end)

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
RegisterNUICallback('ready', function(_, cb)
    pageReady = true
    cb(1)
end)
RegisterNUICallback('ended', function(data, cb)
    if data and data.serial == serial then ended = true end
    cb(1)
end)
RegisterNUICallback('failed', function(data, cb)
    if data and data.serial == serial then ended, playing = true, false end
    cb(1)
end)

local function suppressVanilla(on)
    if on == suppressed then return end
    SetAudioFlag('WantedMusicDisabled', on)
    suppressed = on
end

local function halt()
    suppressVanilla(false)
    if not playing then return end
    playing, ended = false, false
    SendNUIMessage({ type = 'stop' })
end

stop = function()
    level = 0.0
    halt()
end

-- Only a change of a hundredth or more goes to the page, and nothing before
-- the first track, as single player does it.
local function pushVolume()
    if serial == 0 or math.abs(level - pushedLevel) < 0.01 then return end
    pushedLevel = level
    SendNUIMessage({ type = 'volume', volume = level })
end

-- A random track, but never the one that just played.
local function playRandom()
    local n = #tracks
    local i = n ~= 1 and math.random(n) or 1
    if n > 1 and i == lastTrack then i = i % n + 1 end
    lastTrack = i
    ended, playing = false, true
    serial = serial + 1
    pushedLevel = level
    SendNUIMessage({ type = 'play', file = FOLDER .. '/' .. tracks[i], volume = level, serial = serial, stallMs = STALL_MS })
end

-- ---------------------------------------------------------------------------
-- What single player checks, frame by frame
-- ---------------------------------------------------------------------------
-- GTA's pause menu, or vi_pausemenu (which keeps GTA's shut and says so in
-- this state bag): single player's pause menu stops the music.
local function paused()
    return IsPauseMenuActive() or LocalPlayer.state.pauseMenuOpen == true
end

-- Single player plays nothing while its radio plays the player's own music.
-- vi_radio's match is On Demand. An export call costs more than a native, so
-- it is asked four times a second.
local radioAskedAt, radioOwn = 0, false
local function radioOwnMusic()
    local now = GetGameTimer()
    if now < radioAskedAt then return radioOwn end
    radioAskedAt = now + 250
    radioOwn = false
    if GetResourceState('vi_radio') == 'started' then
        local ok, on = pcall(function() return exports.vi_radio:IsOnDemandOn() end)
        radioOwn = ok and on == true
    end
    return radioOwn
end

-- Dead, being arrested, or the screen fading or faded out.
local function interrupted(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then return true end
    if IsPlayerBeingArrested(cache.playerId, false) then return true end
    return IsScreenFadingOut() or IsScreenFadedOut()
end

-- Single player muffles under its weapon wheel. Here that is GTA's weapon
-- wheel, or ox_inventory open (it says so in this state bag).
local function muffled()
    return IsHudComponentActive(19) or LocalPlayer.state.invOpen == true
end

-- Single player's MusicPlayer.Update. Returns whether the volume is still on
-- its way somewhere (so the next frame is wanted).
local function update(dt)
    if not (options.get('chasemusic') and not radioOwnMusic()) or paused() then
        stop()
        return false
    end

    local active = #tracks > 0 and GetPlayerWantedLevel(cache.playerId) > 0 and not interrupted(cache.ped)
    if active then
        suppressVanilla(true)
        if not playing or ended then playRandom() end
    end

    local muffle = muffled()
    local target = 0.0
    if active then target = muffle and VOLUME * MUFFLE or VOLUME end

    -- a fade moves the level by 1 in this many seconds
    local seconds
    if not active then seconds = FADE_S
    elseif muffle or level > target then seconds = MUFFLE_S
    elseif level <= 0.001 then seconds = FADE_IN_S
    else seconds = BOOST_S end
    local step = dt / math.max(0.01, seconds)
    if level < target then
        level = math.min(target, level + step)
    elseif level > target then
        level = math.max(target, level - step)
    end
    pushVolume()

    if not active and level <= 0.001 then halt() end

    -- the page's stall watchdog: it pauses the track when these stop coming
    if playing then
        local now = GetGameTimer()
        if now >= nextBeat then
            nextBeat = now + math.max(50, STALL_MS // 4)
            SendNUIMessage({ type = 'tick' })
        end
    end
    return level ~= target
end

CreateThread(function()
    while true do
        local wait = 250
        if pageReady then
            if next(holds) then
                -- held: no update and no tick, so the page pauses the track
                -- where it is, as single player's screens that skip the music
                -- do; the pause menu still stops it
                if paused() then stop() end
                wait = 100
            elseif update(GetFrameTime()) then
                wait = 0        -- fading: every frame, as single player steps it
            elseif playing then
                wait = 50       -- steady: soon enough to catch the wheel opening
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then suppressVanilla(false) end
end)
