--[[
    VI Radio - server

    Owns On Demand playback. The client is never trusted with what is playing:
    it asks for a link to be queued, and the server decides what the track is,
    when it started and who hears about it. Everything is keyed by the
    vehicle's network id, so passengers and late joiners land on the same track
    at the same point in it.
]]

if not Config.OnDemand.enabled then return end

if GetResourceState('xsound') ~= 'started' then
    Config.OnDemand.enabled = false
    print('[vi_radio] xsound is not started, On Demand is disabled')
    return
end

local OD = Config.OnDemand
local RES = GetCurrentResourceName()

-- state ----------------------------------------------------------------------
-- A session existing at all means the vehicle's On Demand switch is ON. It
-- outlives the queue: switching on with nothing queued is a valid state, and so
-- is playing the last track in the queue and running out.
--
-- sessions[netId] = {
--   queue    = { { url, kind, title, artist, duration }, ... },
--   index    = current track, 0 when nothing is playing,
--   station  = 0 for the vehicle's own queue, else the Config.OnDemand.stations
--              entry playing (queue is then a copy of its tracks),
--   own      = the vehicle's own queue and its place, kept while a station plays,
--   previousStation = the radio station to put back when the switch goes off,
--   token    = bumped on every track change, so a late duration report for the
--              previous track can be thrown away,
--   startedAt/pausedAt = the playback clock, see elapsed(),
-- }
local sessions = {}
local lastCommand = {}   -- [src] = GetGameTimer() of their last command

-- Where each station was, per vehicle, kept past the switch going off:
-- places[netId][station] = { index, position, at }. Single player's own music
-- remembers a station's place for half an hour; so does this.
local places = {}

-- On Demand stations ---------------------------------------------------------
-- Single player's On Demand plays your own music: a folder of tracks on your
-- disk is a station. A server can only play what it ships or what a link
-- points at, so here a station is Config.OnDemand.stations' list of tracks: a
-- path under html/ (streamed with the resource, see fxmanifest.lua), a direct
-- audio link, or a YouTube link. Server config, so trusted; still checked.

local function fileTitle(url)
    local name = url:match('([^/?#]+)%.%w+$') or url:match('([^/?#]+)$') or 'Track'
    name = name:gsub('%%20', ' '):gsub('_', ' ')
    return name
end

local function resolveTrack(entry)
    local t = type(entry) == 'table' and entry or { url = entry }
    if type(t.url) ~= 'string' or t.url == '' then return nil end

    local url, kind
    if t.url:match('^https?://') then
        url, kind = Config.NormalizeUrl(t.url)
        if not url then
            print(('[vi_radio] On Demand station track skipped (%s): %s'):format(tostring(kind), t.url))
            return nil
        end
    else
        -- shipped with the resource, under html/
        local path = t.url:gsub('\\', '/'):gsub('^/+', ''):gsub('^html/', '')
        local ext = (path:match('%.(%w+)$') or ''):lower()
        local known = false
        for _, allowed in ipairs(OD.fileExtensions or {}) do
            if ext == allowed then known = true break end
        end
        if path:find('%.%.') or not known then
            print(('[vi_radio] On Demand station track skipped (not an audio file under html/): %s'):format(t.url))
            return nil
        end
        url = ('https://cfx-nui-%s/html/%s'):format(RES, (path:gsub(' ', '%%20')))
        kind = 'file'
    end

    return {
        url    = url,
        kind   = kind,
        title  = t.title or (kind == 'youtube' and 'YouTube' or fileTitle(url)),
        artist = t.artist,
        fixedTitle = t.title ~= nil,
    }
end

local fetchTitle   -- titles, below

local STATIONS = {}
for i, st in ipairs(OD.stations or {}) do
    local tracks = {}
    for _, entry in ipairs(st.tracks or {}) do
        local track = resolveTrack(entry)
        if track then tracks[#tracks + 1] = track end
    end
    STATIONS[i] = { label = st.label or ('STATION ' .. i), tracks = tracks }
    if #tracks == 0 then
        print(('[vi_radio] On Demand station %s has no playable tracks'):format(STATIONS[i].label))
    end
end

-- helpers --------------------------------------------------------------------

local function elapsed(s)
    if s.index == 0 or not s.startedAt then return 0.0 end
    if s.paused then return s.pausedAt end
    return (GetGameTimer() - s.startedAt) / 1000.0
end

local function vehicleNetId(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then return nil end
    -- Mirrors the client's Config.DriverOnly check, so a passenger can't
    -- drive the playlist by firing the events directly either.
    if Config.DriverOnly and GetPedInVehicleSeat(veh, -1) ~= ped then return nil end
    return NetworkGetNetworkIdFromEntity(veh)
end

local function vehicleExists(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    return veh and veh ~= 0 and DoesEntityExist(veh)
end

-- Whoever vehicleNetId accepts (the driver, or anyone with Config.DriverOnly
-- off) may drive its playlist. That is scope, not permission:
-- there is deliberately no job or ace check anywhere in here.
local function sessionFor(src)
    local netId = vehicleNetId(src)
    if not netId then return nil, nil end
    return sessions[netId], netId
end

local function rateLimited(src)
    local now = GetGameTimer()
    if lastCommand[src] and now - lastCommand[src] < OD.commandCooldown then
        return true
    end
    lastCommand[src] = now
    return false
end

local function notify(src, message)
    if message then TriggerClientEvent('vi_radio:od:notify', src, message) end
end

-- broadcast ------------------------------------------------------------------

local function payload(netId, s)
    local queue = {}
    for i, t in ipairs(s.queue) do
        queue[i] = { title = t.title, artist = t.artist, duration = t.duration }
    end

    local track = s.queue[s.index]
    return {
        netId    = netId,
        engaged  = true,
        station  = s.station or 0,
        index    = s.index,
        token    = s.token,
        playing  = track ~= nil,
        paused   = s.paused or false,
        -- audioUrl (once resolveAudioStream fills it in) is a plain audio
        -- stream URL, playable -- and filterable -- as a direct file; url is
        -- the original youtube.com link, used until/unless that resolves.
        url      = track and (track.audioUrl or track.url) or nil,
        title    = track and track.title or nil,
        artist   = track and track.artist or nil,
        duration = track and track.duration or nil,
        position = elapsed(s),
        queue    = queue,
    }
end

-- Sent to everyone: any player may end up in earshot of any vehicle, and the
-- client only starts audio for vehicles that are actually near it.
local function broadcast(netId, target)
    local s = sessions[netId]
    if not s then
        TriggerClientEvent('vi_radio:od:state', target or -1, { netId = netId, playing = false, gone = true })
        return
    end
    TriggerClientEvent('vi_radio:od:state', target or -1, payload(netId, s))
end

-- playback -------------------------------------------------------------------

--[[
    Resolves a YouTube link to a raw playable audio-stream URL via a public
    Piped API instance (no API key, no yt-dlp binary/subprocess on this
    machine -- FXServer's Lua sandbox has no os.execute/io.popen for that
    anyway). Once a track plays through a resolved stream URL instead of the
    embedded YouTube iframe, xsound treats it as a plain audio file and the
    lowpass/muffle filter (SoundPlayer.js's initLowpass) can actually attach
    to it -- the embedded iframe's audio is a cross-origin video player, which
    a Web Audio filter node can never reach.

    Community-run instances, independent of anything in this codebase -- can
    go down or rate-limit on their own schedule. Tried in order; if every one
    fails, `callback(nil)` and the caller falls back to the plain youtube.com
    URL (the original iframe-embed behaviour, unfiltered but always works).
]]
local PIPED_INSTANCES = {
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.adminforge.de',
    'https://api.piped.yt',
}

local function extractVideoId(url)
    return url and url:match('[?&]v=([%w_%-]+)')
end

local function resolveAudioStream(track, callback, instanceIndex)
    instanceIndex = instanceIndex or 1
    local instance = PIPED_INSTANCES[instanceIndex]
    local videoId = extractVideoId(track.url)
    if not instance or not videoId then
        callback(nil)
        return
    end

    PerformHttpRequest(('%s/streams/%s'):format(instance, videoId), function(status, body)
        if status ~= 200 or not body then
            resolveAudioStream(track, callback, instanceIndex + 1)
            return
        end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' or type(data.audioStreams) ~= 'table' then
            resolveAudioStream(track, callback, instanceIndex + 1)
            return
        end

        -- Highest-bitrate audio-only stream on offer.
        local best = nil
        for _, stream in ipairs(data.audioStreams) do
            if type(stream.url) == 'string'
               and (not best or (tonumber(stream.bitrate) or 0) > (tonumber(best.bitrate) or 0)) then
                best = stream
            end
        end
        callback(best and best.url or nil)
    end, 'GET')
end

-- `from` is a place in the track to start at, in seconds (a station resumed).
local function startTrack(netId, s, i, from)
    s.index     = i
    s.token     = (s.token or 0) + 1
    s.startedAt = GetGameTimer() - math.floor((from or 0) * 1000)
    s.paused    = false
    s.pausedAt  = 0.0

    local track = s.queue[i]

    -- A station's tracks last as long as the server does, and a resolved
    -- stream link expires after a few hours: an hour old, it is looked up again.
    if track and (s.station or 0) ~= 0 and track.audioUrlAt
       and GetGameTimer() - track.audioUrlAt > 3600000 then
        track.audioUrl, track.audioUrlAt, track.audioResolveFailed = nil, nil, nil
    end

    -- Broadcast immediately with the plain YouTube URL (the pre-existing
    -- iframe-embed behaviour -- nobody waits in silence for the resolver),
    -- then swap to a resolved, filterable stream URL once/if one shows up.
    broadcast(netId)

    -- A station's YouTube track gets its title the first time it plays (a
    -- queued link asks when it is added).
    if track and (s.station or 0) ~= 0 and track.kind == 'youtube'
       and not track.fixedTitle and not track.titleAsked then
        track.titleAsked = true
        fetchTitle(netId, track)
    end

    if track and track.kind == 'youtube' and not track.audioUrl and not track.audioResolveFailed then
        resolveAudioStream(track, function(streamUrl)
            -- The queue may have moved on (skipped, removed, session ended)
            -- by the time an HTTP callback lands -- only act if this track
            -- is still the one actually playing.
            if sessions[netId] ~= s or s.index ~= i then return end

            if streamUrl then
                track.audioUrl = streamUrl
                track.audioUrlAt = GetGameTimer()
            else
                track.audioResolveFailed = true
                return -- stays on the already-playing iframe embed, nothing to swap to
            end

            -- Bumping the token forces the client to treat this as a fresh
            -- track (see client.lua's `if not prev or prev.token ~= data.token
            -- then sess.restart = true end`) so it tears down the iframe
            -- embed and restarts on the resolved stream instead of just
            -- updating position on the sound that's already playing. This is
            -- a real, audible restart-from-zero, once, a second or two into
            -- a YouTube track -- the trade-off for the filter being able to
            -- attach at all.
            s.token     = (s.token or 0) + 1
            s.startedAt = GetGameTimer()
            broadcast(netId)
        end)
    end
end

-- `restore` is the station to hand the vehicle radio back to, and is only sent
-- when the switch was deliberately turned off. A vehicle that simply stopped
-- existing restores nothing.
local function stopSession(netId, restore)
    sessions[netId] = nil
    TriggerClientEvent('vi_radio:od:state', -1, {
        netId   = netId,
        gone    = true,
        playing = false,
        restore = restore,
    })
end

-- Nothing playing is a state, not the end of the session: the switch stays on
-- and the panel stays useful, there is just silence until something is queued.
local function idle(netId, s)
    s.index    = 0
    s.paused   = false
    s.pausedAt = 0.0
    s.token    = (s.token or 0) + 1
    broadcast(netId)
end

local function advance(netId, s, dir)
    local nextIndex = s.index + (dir or 1)
    -- A station plays round and round, as single player's own music does.
    if (s.station or 0) ~= 0 and #s.queue > 0 then
        if nextIndex > #s.queue then nextIndex = 1 elseif nextIndex < 1 then nextIndex = #s.queue end
        startTrack(netId, s, nextIndex)
        return
    end
    if nextIndex < 1 then nextIndex = 1 end
    if nextIndex > #s.queue then
        idle(netId, s)
        return
    end
    startTrack(netId, s, nextIndex)
end

-- titles ---------------------------------------------------------------------
-- YouTube's oEmbed endpoint needs no key and returns the video title and the
-- channel name, which is as close to "title / artist" as this gets.

fetchTitle = function(netId, track)
    if not OD.fetchTitles or track.kind ~= 'youtube' then return end

    PerformHttpRequest('https://www.youtube.com/oembed?format=json&url=' .. track.url, function(status, body)
        if status ~= 200 or not body then return end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' then return end

        if type(data.title) == 'string' then track.title = data.title end
        if type(data.author_name) == 'string' then track.artist = data.author_name end

        if sessions[netId] then broadcast(netId) end
    end, 'GET')
end

-- stations -------------------------------------------------------------------
-- The wheel steps through On Demand's entries the way it does the radio's: the
-- vehicle's own queue (station 0) and each of the server's stations. Leaving
-- one keeps its place; coming back to a station within resumeMinutes carries
-- on from there, and the vehicle's own queue always does.

local function keepPlace(netId, s)
    local place = { index = s.index, position = elapsed(s), at = GetGameTimer() }
    if (s.station or 0) == 0 then
        place.queue = s.queue
        s.own = place
    else
        places[netId] = places[netId] or {}
        places[netId][s.station] = place
    end
end

local function tuneStation(netId, s, i)
    keepPlace(netId, s)
    s.station = i

    local place
    if i == 0 then
        place = s.own
        s.own = nil
        s.queue = place and place.queue or {}
    else
        s.queue = {}
        for n, track in ipairs(STATIONS[i].tracks) do s.queue[n] = track end
        place = places[netId] and places[netId][i]
        if place and GetGameTimer() - place.at > (OD.resumeMinutes or 30) * 60000 then place = nil end
    end

    if place and place.index > 0 and s.queue[place.index] then
        local track = s.queue[place.index]
        local from = place.position
        if track.duration and from >= track.duration - 1 then from = 0 end
        startTrack(netId, s, place.index, from)
    elseif i ~= 0 and #s.queue > 0 then
        startTrack(netId, s, 1)
    else
        idle(netId, s)
    end
end

-- events ---------------------------------------------------------------------

-- An On Demand entry picked in the wheel: 0 for the vehicle's own queue, else
-- one of Config.OnDemand.stations. Only with the switch already on.
RegisterNetEvent('vi_radio:od:station', function(i)
    local src = source
    if rateLimited(src) then return end
    if type(i) ~= 'number' then return end
    i = math.floor(i)
    if i ~= 0 and not STATIONS[i] then return end

    local s, netId = sessionFor(src)
    if not s then return end

    if (s.station or 0) == i then
        broadcast(netId)
        return
    end
    tuneStation(netId, s, i)
end)

-- The switch itself. Turning it on creates the session -- that is what "on"
-- means -- and remembers the station to put back when it goes off again.
RegisterNetEvent('vi_radio:od:engage', function(previousStation)
    local src = source
    if rateLimited(src) then return end

    local netId = vehicleNetId(src)
    if not netId then return notify(src, 'You have to be in a vehicle') end

    if sessions[netId] then
        broadcast(netId)
        return
    end

    if type(previousStation) ~= 'string' or #previousStation > 64
       or not previousStation:match('^[%w_]+$') then
        previousStation = 'OFF'
    end

    sessions[netId] = {
        queue = {}, index = 0, token = 0, station = 0,
        paused = false, pausedAt = 0.0,
        previousStation = previousStation,
    }
    broadcast(netId)
end)

-- `restore` is false when the player switched off by picking a radio station:
-- they have already chosen what they want to hear, so putting the old station
-- back would undo it.
RegisterNetEvent('vi_radio:od:disengage', function(restore)
    local src = source
    if rateLimited(src) then return end

    local s, netId = sessionFor(src)
    if not s then return end

    stopSession(netId, restore ~= false and s.previousStation or nil)
end)

RegisterNetEvent('vi_radio:od:add', function(link, playNow)
    local src = source
    if rateLimited(src) then return end

    local netId = vehicleNetId(src)
    if not netId then return notify(src, 'You have to be in a vehicle') end

    local url, kind = Config.NormalizeUrl(link)
    if not url then return notify(src, kind) end

    -- /ondemand <url> can queue something without the switch having been
    -- flipped first, so this still creates the session when there is none.
    local s = sessions[netId]
    if not s then
        s = {
            queue = {}, index = 0, token = 0, station = 0,
            paused = false, pausedAt = 0.0,
            previousStation = 'OFF',
        }
        sessions[netId] = s
    end

    -- A link goes on the vehicle's own queue: one of the server's stations
    -- playing is put aside for it, and keeps its place.
    if (s.station or 0) ~= 0 then tuneStation(netId, s, 0) end

    if #s.queue >= OD.queueLimit then
        return notify(src, ('The queue is full (%d tracks)'):format(OD.queueLimit))
    end

    local track = {
        url   = url,
        kind  = kind,
        title = kind == 'youtube' and 'YouTube' or (url:match('([^/]+)$') or 'Track'),
    }
    s.queue[#s.queue + 1] = track

    if playNow or s.index == 0 then
        startTrack(netId, s, #s.queue)
    else
        broadcast(netId)
    end

    fetchTitle(netId, track)
end)

RegisterNetEvent('vi_radio:od:remove', function(i)
    local src = source
    if rateLimited(src) then return end
    if type(i) ~= 'number' then return end

    local s, netId = sessionFor(src)
    if not s then return end

    i = math.floor(i)
    if not s.queue[i] then return end

    table.remove(s.queue, i)

    if #s.queue == 0 then
        idle(netId, s)
    elseif i == s.index then
        -- The track that was playing is gone: play whatever slid into its place.
        startTrack(netId, s, math.min(i, #s.queue))
    else
        if i < s.index then s.index = s.index - 1 end
        broadcast(netId)
    end
end)

RegisterNetEvent('vi_radio:od:skip', function(dir)
    local src = source
    if rateLimited(src) then return end

    local s, netId = sessionFor(src)
    if not s or s.index == 0 then return end

    advance(netId, s, dir == -1 and -1 or 1)
end)

RegisterNetEvent('vi_radio:od:pause', function()
    local src = source
    if rateLimited(src) then return end

    local s, netId = sessionFor(src)
    if not s or s.index == 0 then return end

    if s.paused then
        s.startedAt = GetGameTimer() - math.floor(s.pausedAt * 1000)
        s.paused = false
    else
        s.pausedAt = elapsed(s)
        s.paused = true
    end
    broadcast(netId)
end)

-- Stop clears the queue but leaves the switch on. Turning the switch off is
-- vi_radio:od:disengage, which is a different thing to want.
RegisterNetEvent('vi_radio:od:stop', function()
    local src = source
    if rateLimited(src) then return end

    local s, netId = sessionFor(src)
    if not s then return end

    -- On one of the server's stations, Stop goes back to the vehicle's own
    -- queue and clears that (the station keeps its place for later).
    if (s.station or 0) ~= 0 then keepPlace(netId, s) end
    s.station = 0
    s.own = nil
    s.queue = {}
    idle(netId, s)
end)

-- A listener tells us how long the current track is. Nothing on the server can
-- know that, so it comes from whoever is actually playing it -- but only for
-- the track playing right now, and only if the number is plausible.
RegisterNetEvent('vi_radio:od:duration', function(netId, token, seconds)
    if type(netId) ~= 'number' or type(token) ~= 'number' or type(seconds) ~= 'number' then return end

    local s = sessions[netId]
    if not s or s.token ~= token or s.index == 0 then return end
    if seconds <= 0 or seconds > 21600 then return end

    local track = s.queue[s.index]
    if not track or track.duration then return end

    track.duration = seconds
    broadcast(netId)
end)

RegisterNetEvent('vi_radio:od:sync', function()
    local src = source
    for netId, s in pairs(sessions) do
        TriggerClientEvent('vi_radio:od:state', src, payload(netId, s))
    end
end)

-- upkeep ---------------------------------------------------------------------
-- Advance finished tracks, drop sessions whose vehicle no longer exists, and
-- rebroadcast the playback position so listeners cannot drift far.

CreateThread(function()
    local lastBroadcast = 0

    while true do
        Wait(1000)

        local now = GetGameTimer()
        local resend = now - lastBroadcast >= OD.broadcastInterval
        if resend then lastBroadcast = now end

        if resend then
            for netId in pairs(places) do
                if not sessions[netId] and not vehicleExists(netId) then places[netId] = nil end
            end
        end

        for netId, s in pairs(sessions) do
            if not vehicleExists(netId) then
                stopSession(netId)
                places[netId] = nil
            else
                local track = s.queue[s.index]
                if track and track.duration and not s.paused and elapsed(s) >= track.duration then
                    advance(netId, s, 1)
                elseif resend then
                    broadcast(netId)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    lastCommand[source] = nil
end)

-- exports --------------------------------------------------------------------

exports('GetOnDemandSession', function(netId)
    local s = sessions[netId]
    return s and payload(netId, s) or nil
end)

exports('StopOnDemand', function(netId)
    if sessions[netId] then stopSession(netId) end
end)
