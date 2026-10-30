-- Behaviour test for vi_chasemusic/client.lua with mocked FiveM natives.
local ROOT = ''

local loaded = {}
function require(name)
    if loaded[name] then return loaded[name] end
    local src = assert(readfile(ROOT .. name:gsub('%.', '/') .. '.lua'), name)
    local v = assert(load(src, '@' .. name))()
    loaded[name] = v
    return v
end

local now = 0
local frame = 1000 / 60
local kvp = {}
local sent = {}
local cbs = {}
local exported = {}
local flag = {}
local threads = {}
local wanted, dead, arrested, fadedOut, pauseMenu, wheel, od = 0, false, false, false, false, false, false
local state = {}

function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
exports = setmetatable({}, {
    __call = function(_, name, fn) exported[name] = fn end,
    __index = function(_, res)
        if res == 'vi_radio' then return { IsOnDemandOn = function() return od end } end
    end,
})
GlobalState = { viChaseMusicTracks = { 'a.mp3', 'b.ogg', 'c.wav' } }
local bagHandler
function AddStateBagChangeHandler(k, b, fn) bagHandler = fn end
function RegisterNUICallback(n, fn) cbs[n] = fn end
function SendNUIMessage(m) sent[#sent + 1] = m end
function SetAudioFlag(n, on) flag[n] = on end
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), at = 0 } end
function Wait(ms) coroutine.yield(ms) end
function GetGameTimer() return math.floor(now) end
function GetFrameTime() return frame / 1000 end
function IsPauseMenuActive() return pauseMenu end
LocalPlayer = { state = state }
function GetResourceState(r) return r == 'vi_radio' and 'started' or 'missing' end
function IsPlayerBeingArrested() return arrested end
function IsScreenFadingOut() return false end
function IsScreenFadedOut() return fadedOut end
function DoesEntityExist() return true end
function IsEntityDead() return dead end
function IsHudComponentActive(c) return c == 19 and wheel end
function GetPlayerWantedLevel() return wanted end
function AddEventHandler() end
function GetCurrentResourceName() return 'vi_extras' end
cache = { ped = 5, playerId = 0 }

local options = require 'vi_hudoptions.options'
assert(load(assert(readfile(ROOT .. 'vi_chasemusic/client.lua')), '@client.lua'))()

local function run(ms)
    local stop = now + ms
    while now < stop do
        now = now + frame
        for _, t in ipairs(threads) do
            if now >= t.at then
                local ok, w = coroutine.resume(t.co)
                assert(ok, w)
                t.at = now + (w or 0)
            end
        end
    end
end
local function last(type_)
    for i = #sent, 1, -1 do if sent[i].type == type_ then return sent[i], i end end
end
local function vol()
    local v = 0
    for _, m in ipairs(sent) do if m.type == 'volume' or m.type == 'play' then v = m.volume end end
    return v
end
local function check(cond, msg) if not cond then error('FAIL: ' .. msg, 2) end print('ok   ' .. msg) end

check(options.label('chasemusic') ~= 'N/A', 'row exists: ' .. options.label('chasemusic'))
check(options.get('chasemusic') == false, 'defaults OFF (shipped ini)')
options.set('chasemusic', true)
check(options.label('chasemusic') == 'ON', 'label ON with tracks')

run(500)
check(#sent == 0, 'nothing sent before the page is ready')
cbs.ready({}, function() end)
run(500)
check(#sent == 0, 'nothing sent with no wanted level')

wanted = 2
local t0 = now
for _ = 1, 30 do run(frame) if last('play') then break end end
check(now - t0 <= 270, ('play within the idle poll: %.0f ms'):format(now - t0))
t0 = now
local play = last('play')
check(play ~= nil and play.file:match('^music/[abc]%.'), 'play on wanted: ' .. tostring(play and play.file))
check(flag.WantedMusicDisabled == true, 'vanilla wanted music off')
-- fade in: 0.3 at 1/1.4 per s = 0.42 s
local reached
for _ = 1, 60 do run(frame) if vol() >= 0.299 then reached = now - t0 break end end
-- single player: only the first step from silence uses FadeInSeconds, the rest BoostSeconds (0.3 x 0.9 = 270 ms)
check(reached and reached > 230 and reached < 320, ('fade in to 0.3 in %.0f ms (expect ~270)'):format(reached or -1))
local nVol = 0
for _, m in ipairs(sent) do if m.type == 'volume' then nVol = nVol + 1 end end
check(nVol > 8 and nVol < 40, 'volume pushes during fade in: ' .. nVol)

-- muffle: down to 0.075 at 1/0.25 per s = 56 ms
wheel = true
run(150)
check(math.abs(vol() - 0.075) < 0.011, ('muffled to %.3f'):format(vol()))
wheel = false
t0 = now
for _ = 1, 60 do run(frame) if vol() >= 0.299 then reached = now - t0 break end end
check(reached and reached > 150 and reached < 300, ('boost back in %.0f ms (expect ~0.225/0.9=250 + poll)'):format(reached))

-- track ends: another, not the same
local first = last('play')
cbs.ended({ serial = first.serial }, function() end)
run(100)
local second = last('play')
check(second.serial == first.serial + 1 and second.file ~= first.file, 'next track differs: ' .. first.file .. ' -> ' .. second.file)
cbs.ended({ serial = first.serial }, function() end)
run(100)
check(last('play').serial == second.serial, 'stale ended ignored')

-- heartbeat while steady
local ticks = 0
local before = #sent
run(1000)
for i = before + 1, #sent do if sent[i].type == 'tick' then ticks = ticks + 1 end end
check(ticks >= 8 and ticks <= 11, 'ticks per second while playing: ' .. ticks)

-- hold: no ticks, nothing sent
exported.HoldChaseMusic('killcam', true)
before = #sent
run(1000)
check(#sent == before, 'held: nothing sent')
exported.HoldChaseMusic('killcam', false)
run(200)
check(last('tick') and select(2, last('tick')) > before, 'released: ticks again')

-- wanted cleared: fade out 0.3 at 1/1.6 per s = 480 ms, then stop
wanted = 0
t0 = now
local stopAt
for _ = 1, 80 do run(frame) local _, i = last('stop') if i and i > before then stopAt = now - t0 break end end
check(stopAt and stopAt > 430 and stopAt < 560, ('fade out then stop in %.0f ms (expect ~480)'):format(stopAt or -1))
check(flag.WantedMusicDisabled == false, 'vanilla wanted music back on')
check(exported.IsChaseMusicPlaying() == false, 'not playing')

-- pause menu stops at once
wanted = 1
run(600)
check(exported.IsChaseMusicPlaying(), 'playing again')
before = #sent
state.pauseMenuOpen = true
run(20)
local _, si = last('stop')
check(si and si > before, 'vi_pausemenu stops it at once')
state.pauseMenuOpen = false
run(100)
check(last('play').volume == 0, 'restarts from silence after pause')

-- On Demand stops it
run(600)
od = true
before = #sent
run(300)
_, si = last('stop')
check(si and si > before, 'On Demand stops it')
od = false
run(300)

-- dead: fade out
dead = true
before = #sent
run(700)
_, si = last('stop')
check(si and si > before, 'dead fades out and stops')
dead = false

-- switched off: stops at once
run(600)
before = #sent
options.set('chasemusic', false)
_, si = last('stop')
check(si and si > before, 'switch off stops at once')

-- no tracks: NONE
bagHandler('global', 'viChaseMusicTracks', {})
check(options.label('chasemusic') == 'NONE', 'no tracks: NONE')
options.step('chasemusic', 1)
check(options.get('chasemusic') == true and options.label('chasemusic') == 'NONE', 'NONE still flips the setting underneath')
wanted = 2
before = #sent
run(500)
local playsNow = 0
for i = before + 1, #sent do
    if sent[i].type ~= 'volume' then playsNow = playsNow + 1 end
    print('     sent', sent[i].type, sent[i].volume)
end
check(playsNow == 0, 'no tracks: nothing plays (a volume 0 to the stopped page is single player PushVolume too)')
bagHandler('global', 'viChaseMusicTracks', { 'x.mp3' })
check(options.label('chasemusic') == 'ON', 'tracks back: ON')
run(100)
check(last('play').file == 'music/x.mp3', 'single track plays')
print('done')
return true
