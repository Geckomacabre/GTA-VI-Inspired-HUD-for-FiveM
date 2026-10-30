-- server.lua's folder listing, with io mocked (fengari has none).
local ROOT = ''
local loaded = {}
function require(name)
    if loaded[name] then return loaded[name] end
    local v = assert(load(assert(readfile(ROOT .. name:gsub('%.', '/') .. '.lua')), '@' .. name))()
    loaded[name] = v
    return v
end
local function check(cond, msg) if not cond then error('FAIL: ' .. msg, 2) end print('ok   ' .. msg) end
local function lines(list) local i = 0 return function() i = i + 1 return list[i] end end

GetCurrentResourceName = function() return 'vi_extras' end
GetResourcePath = function() return 'C:/txData/resources/[vi]/vi_extras' end
local printed = {}
print = (function(p) return function(...) printed[#printed + 1] = table.concat({ ... }, ' ') p(...) end end)(print)

-- 1: io.readdir
local asked
GlobalState = {}
io = { readdir = function(d) asked = d return { lines = function() return lines({ '.', '..', 'README.md', 'b Chase.MP3', 'a.ogg', 'x.wma', 'C.wav' }) end, close = function() end } end }
assert(load(assert(readfile(ROOT .. 'vi_chasemusic/server.lua')), '@server.lua'))()
check(asked == 'C:/txData/resources/[vi]/vi_extras/vi_chasemusic/music', 'reads ' .. tostring(asked))
check(table.concat(GlobalState.viChaseMusicTracks, '|') == 'a.ogg|b Chase.MP3|C.wav', 'filtered and sorted: ' .. table.concat(GlobalState.viChaseMusicTracks, '|'))

-- 2: io.popen fallback on Windows
local cmd
GlobalState = {}
io = { popen = function(c) cmd = c return { lines = function() return lines({ 'one.mp3\r', 'two.txt' }) end, close = function() end } end }
assert(load(assert(readfile(ROOT .. 'vi_chasemusic/server.lua')), '@server.lua'))()
check(cmd == 'dir "C:\\txData\\resources\\[vi]\\vi_extras\\vi_chasemusic\\music" /b', 'popen: ' .. tostring(cmd))
check(table.concat(GlobalState.viChaseMusicTracks, '|') == 'one.mp3', 'popen list: ' .. table.concat(GlobalState.viChaseMusicTracks, '|'))

-- 3: nothing to list with
GlobalState = {}
io = {}
assert(load(assert(readfile(ROOT .. 'vi_chasemusic/server.lua')), '@server.lua'))()
check(#GlobalState.viChaseMusicTracks == 0 and printed[#printed]:find('could not read', 1, true), 'no io: empty list and one error')
return true
