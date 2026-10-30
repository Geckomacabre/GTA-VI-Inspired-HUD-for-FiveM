--[[ ===========================================================================
     vi_chasemusic — server: the list of tracks
     ---------------------------------------------------------------------------
     Single player lists its Music folder when it starts. A FiveM client can't
     list a folder (LoadResourceFile needs a name), but the server can, so it
     reads vi_chasemusic/music/ once when the resource starts and hands the
     names to every client in GlobalState.viChaseMusicTracks, which reaches
     players who join later without any event. The tracks themselves reach the
     players through the manifest's files entries, as any NUI file does.

     config.tracks, when it names any, is used instead of the folder.
     ========================================================================= ]]

local config = require 'vi_chasemusic.config'
if not config.enabled then return end

local RES = GetCurrentResourceName()
local DIR = ('%s/vi_chasemusic/%s'):format(GetResourcePath(RES), config.folder or 'music')

local function wanted(name)
    local ext = name:match('(%.[^.]+)$')
    if not ext then return false end
    ext = ext:lower()
    for _, e in ipairs(config.extensions or {}) do
        if e:lower() == ext then return true end
    end
    return false
end

-- The folder's file names. io.readdir is the sandboxed server's listing;
-- servers from before the sandbox have io.popen with dir or ls instead (the
-- sandbox lets those two through as well).
local function listFolder()
    local names = {}
    if io.readdir then
        local ok, dir = pcall(io.readdir, DIR)
        if ok and dir then
            for name in dir:lines() do names[#names + 1] = name end
            pcall(dir.close, dir)
            return names
        end
    end
    if not io.popen then return nil end
    local windows = DIR:match('^%a:') ~= nil
    local cmd = windows and ('dir "%s" /b'):format((DIR:gsub('/', '\\'))) or ('ls "%s"'):format(DIR)
    local ok, pipe = pcall(io.popen, cmd)
    if not ok or not pipe then return nil end
    for line in pipe:lines() do
        line = line:gsub('[\r\n]+$', '')
        if line ~= '' then names[#names + 1] = line end
    end
    pipe:close()
    return names
end

local function exists(name)
    local f = io.open(DIR .. '/' .. name, 'rb')
    if not f then return false end
    f:close()
    return true
end

local function findTracks()
    local tracks = {}
    if type(config.tracks) == 'table' and #config.tracks > 0 then
        for _, name in ipairs(config.tracks) do
            if type(name) == 'string' and wanted(name) and exists(name) then
                tracks[#tracks + 1] = name
            else
                print(('^1[vi_extras]^7 chase music: %s is not a playable file in vi_chasemusic/%s'):format(tostring(name), config.folder))
            end
        end
    else
        local names = listFolder()
        if not names then
            print(('^1[vi_extras]^7 chase music: could not read vi_chasemusic/%s; list the tracks in its config.lua instead'):format(config.folder))
            names = {}
        end
        for _, name in ipairs(names) do
            -- a name only: anything with a path in it is not one of this folder's files
            if not name:find('[/\\]') and wanted(name) then tracks[#tracks + 1] = name end
        end
    end
    -- single player plays its list sorted by name, ignoring case
    table.sort(tracks, function(a, b) return a:lower() < b:lower() end)
    return tracks
end

GlobalState.viChaseMusicTracks = findTracks()
