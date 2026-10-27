-- Headless check of the race marker in client_overlays.lua (exports.vice_hud:SetRaceMarker):
-- the pillar, the projected icon and its distance, settling onto the ground, and the finish
-- smoke, on a virtual clock. Run from the resource folder:   lua tools/racemarker.test.lua
--
-- client_overlays.lua carries every overlay, so natives the race marker does not use are
-- answered by a do-nothing stub; the ones it does use are recorded below. Whether every name is
-- a real FiveM global is a separate check (see _tools/race_sim/natives_used.py).
local fails, total = 0, 0
local function ok(c, msg) total = total + 1 if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 0.001) end

local clock, threads = 0, {}
local W = { player = { x = 0.0, y = 0.0, z = 10.0 }, ground = nil, markers = {}, nui = {}, fx = {}, stopped = {},
    fxColour = {}, assetLoaded = false, assetRemoved = 0, cmds = {}, exp = {} }

local V = {}
V.__index = V
V.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, V) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
vec3 = vector3

function GetGameTimer() return clock end
function CreateThread(f) threads[#threads + 1] = { co = coroutine.create(f), at = clock } end
function Wait(ms) coroutine.yield(ms or 0) end
function RegisterCommand(n, f) W.cmds[n] = f end
function AddEventHandler() end
function RegisterNetEvent() end
function RegisterNUICallback() end
function GetCurrentResourceName() return 'vice_hud' end
function GetResourceState() return 'started' end
function SendNUIMessage(d) if d.action == 'raceMarker' then W.nui[#W.nui + 1] = d end end
function PlayerPedId() return 1 end
function GetEntityCoords() return vector3(W.player.x, W.player.y, W.player.z) end
function DrawMarker(t, x, y, z, _, _, _, _, _, _, sx, sy, sz, r, g, b, a)
    W.markers[#W.markers + 1] = { t = t, x = x, y = y, z = z, sx = sx, sy = sy, sz = sz, r = r, g = g, b = b, a = a }
end
-- a flat screen: x along world x, y down the screen with height, always on screen
function GetScreenCoordFromWorldCoord(x, _, z) return true, 0.5 + x / 1000.0, 0.5 - z / 1000.0 end
function GetGroundZFor_3dCoord(x, y, z) if W.ground then return true, W.ground end return false, 0.0 end
function RequestNamedPtfxAsset() W.assetLoaded = true end
function HasNamedPtfxAssetLoaded() return W.assetLoaded end
function RemoveNamedPtfxAsset() W.assetRemoved = W.assetRemoved + 1 end
function UseParticleFxAsset(a) W.lastAsset = a end
function StartParticleFxLoopedAtCoord(name, x, y, z, _, _, _, scale)
    W.fx[#W.fx + 1] = { name = name, asset = W.lastAsset, x = x, y = y, z = z, scale = scale }
    return #W.fx
end
function SetParticleFxLoopedColour(h, r, g, b) W.fxColour[h] = { r, g, b } end
function StopParticleFxLooped(h) W.stopped[#W.stopped + 1] = h end

cache = { ped = 1 }
-- exports(name, fn) registers; exports.vice_hud:GetAccentColour() is client.lua's
_G.exports = setmetatable({}, {
    __call = function(_, n, f) W.exp[n] = f end,
    __index = function(_, k)
        if k == 'vice_hud' then
            return setmetatable({ GetAccentColour = function() return { key = 'pink', r = 252, g = 116, b = 164 } end },
                { __index = function(_, fn) return function(_, ...) return W.exp[fn](...) end end })
        end
    end,
})
-- every other overlay is switched off; anything else they reach for at load is a no-op
Config = setmetatable({}, { __index = function() return { enable = false } end })
ViceGlyphs = { onDevice = function() end, control = function() end, device = function() return 'kbm' end }
-- a stub that can be called, indexed or indexed-and-called (BadgeStyle.x(...)), returning nothing
local stub
stub = setmetatable({}, { __call = function() return nil end, __index = function() return stub end })
setmetatable(_G, { __index = function(_, k)
    if type(k) == 'string' and k:match('^[A-Z]') then return stub end
end })

-- CfxLua backtick hashes are not Lua; this file only needs them to parse
local src = io.open('client_overlays.lua', 'rb'):read('a'):gsub('`[^`]*`', '0')
assert(load(src, '@client_overlays.lua'))()

local function run(ms)
    local stop = clock + ms
    while clock < stop do
        for _, t in ipairs(threads) do
            if coroutine.status(t.co) ~= 'dead' and t.at <= clock then
                local okc, wait = coroutine.resume(t.co)
                assert(okc, wait)
                t.at = clock + math.max(wait or 0, 16)
            end
        end
        clock = clock + 16
    end
end
local function lastNui() return W.nui[#W.nui] end
local function frameMarkers() local m = W.markers W.markers = {} return m end

print('\n-- a checkpoint 100 m up the road --')
W.exp.SetRaceMarker({ coords = vector3(0.0, 100.0, 10.0), kind = 'checkpoint' })
W.ground = 10.0
run(100)
local m = frameMarkers()
local core = m[#m]
ok(core and core.t == 1, 'the pillar is the vertical cylinder marker (type 1)')
ok(core and near(core.sx, 0.85) and near(core.sy, 0.85), 'about 0.85 m across, as measured on the reference')
ok(core and near(core.sz, 100 * 0.15 + 0.5), '0.15 x range tall (15 m at 100 m), sunk half a metre', core and core.sz)
ok(core and near(core.z, 9.5), 'standing on the road, from half a metre under it', core and core.z)
ok(core and core.r == 252 and core.g == 116 and core.b == 164, 'in the accent colour')
ok(m[#m - 1] and m[#m - 1].sx > core.sx and m[#m - 1].a < core.a, 'with a wider, fainter halo round it')
local n = lastNui()
ok(n and n.show and n.kind == 'checkpoint' and n.text == '328 ft', 'the icon reads 328 ft (100 m)', n and n.text)
ok(n and near(n.y, 0.5 - (10.0 + 15.0) / 1000.0), 'and sits on the top of the pillar', n and n.y)

print('\n-- nothing changes, nothing is sent --')
local count = #W.nui
run(200)
ok(#W.nui == count, 'no message while the picture is the same', #W.nui - count)

print('\n-- the pillar grows with range, within limits --')
W.player = { x = 0.0, y = 80.0, z = 10.0 }   -- 20 m off
run(50); m = frameMarkers()
ok(near(m[#m].sz, 10.5), 'close up it is never shorter than 10 m', m[#m].sz)
W.player = { x = 0.0, y = -400.0, z = 10.0 }  -- 500 m off
run(50); m = frameMarkers()
ok(near(m[#m].sz, 45.5), 'far away it stops at 45 m', m[#m].sz)
ok(lastNui().text == '0.3 mi', 'past 1,000 ft the distance is in miles', lastNui().text)
W.player = { x = 0.0, y = 100.0 - 137.9, z = 10.0 }
run(50)
ok(lastNui().text == '452 ft', 'whole feet, not rounded to fives like the nav badge', lastNui().text)

print('\n-- settling onto the road --')
W.exp.SetRaceMarker({ coords = vector3(0.0, 100.0, 11.2), kind = 'checkpoint' })
W.ground = 10.0
run(100); m = frameMarkers()
ok(near(m[#m].z, 9.5), 'a point 1.2 m up is put down on the ground once it streams in', m[#m].z)
W.exp.SetRaceMarker({ coords = vector3(0.0, 100.0, 30.0), kind = 'checkpoint' })
W.ground = 10.0
run(100); m = frameMarkers()
ok(near(m[#m].z, 29.5), 'but a 20 m difference is another level (a bridge), and it stays where it was given', m[#m].z)
W.exp.SetRaceMarker({ coords = vector3(0.0, 100.0, 11.2), kind = 'checkpoint', snap = false })
run(100); m = frameMarkers()
ok(near(m[#m].z, 10.7), 'snap = false keeps the height it was given', m[#m].z)

print('\n-- the finish --')
W.player = { x = 0.0, y = -500.0, z = 10.0 }
W.ground = 10.0
W.exp.SetRaceMarker({ coords = vector3(0.0, 100.0, 10.0), kind = 'finish', heading = 90.0, width = 14.0 })
run(100); m = frameMarkers()
ok(#m == 0, 'no pillar at the finish')
ok(lastNui().kind == 'finish', 'the icon is the chequered tile')
ok(near(lastNui().y, 0.5 - (10.0 + 8.0) / 1000.0), 'hanging 8 m over the line')
ok(#W.fx == 0, 'no smoke 600 m out')
W.player = { x = 0.0, y = -150.0, z = 10.0 }
run(200)
ok(#W.fx == 3, 'smoke inside 300 m: three banks across 14 m of road', #W.fx)
ok(W.fx[1] and W.fx[1].asset == 'scr_sm' and W.fx[1].name == 'scr_sm_hl_package_flare',
    "Rockstar's coloured ground smoke (Smuggler's Run package flare)")
-- heading 90 faces -x, so across the road is along y
local ys = {}
for i, f in ipairs(W.fx) do ys[i] = f.y end
ok(near(W.fx[1].x, 0.0) and near(ys[1], 100 - 14 / 3) and near(ys[2], 100) and near(ys[3], 100 + 14 / 3),
    'laid across the road, centred on the line', ys)
ok(W.fxColour[1] and near(W.fxColour[1][1], 252 / 255) and near(W.fxColour[1][3], 164 / 255), 'tinted the accent')
W.player = { x = 0.0, y = -400.0, z = 10.0 }
run(100)
ok(#W.stopped == 3 and W.assetRemoved >= 1, 'and put out again past 350 m', #W.stopped)

print('\n-- taking it down --')
W.player = { x = 0.0, y = 0.0, z = 10.0 }
W.exp.SetRaceMarker({ coords = vector3(0.0, 100.0, 10.0), kind = 'finish', heading = 0.0 })
run(200)
local before = #W.stopped
W.exp.ClearRaceMarker()
ok(#W.stopped == before + 3, 'clearing it puts the smoke out')
ok(lastNui().show == false, 'and hides the icon')
run(100)
ok(#frameMarkers() == 0, 'nothing is drawn once it is gone')
W.exp.SetRaceMarker({ coords = vector3(0.0, 100.0, 10.0), kind = 'finish', smoke = false })
run(200)
ok(#W.stopped == before + 3 and W.fx[#W.fx].y ~= nil, 'smoke = false (a gate in the sky) lights none', #W.fx)
W.exp.SetRaceMarker(nil)
ok(lastNui().show == false, 'SetRaceMarker(nil) takes it down too')

print(fails == 0 and ('\nALL PASS (%d)'):format(total) or ('\n%d of %d FAILED'):format(fails, total))
os.exit(fails == 0 and 0 or 1)
