-- Headless check of vi_killcam/client.lua with stubbed natives.
-- Run: node luarun.js <vi_extras folder> tools/killcam.test.lua, or lua tools/killcam.test.lua from it
local fails, total = 0, 0
local function ok(c, msg) total = total + 1 if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end end

-- ---- vectors
local V = {}
V.__index = V
local function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
V.__add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b)
    if type(a) == 'number' then a, b = b, a end
    return vector3(a.x * b, a.y * b, a.z * b)
end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
_G.vector3 = vector3

-- ---- world
local now = { net = 0, game = 0 }
local timeScale = 1.0
local PLAYER = 1
local peds = {}   -- [handle] = { pos, health, max, armour, dead, source, cause, player }
local function addPed(h, x, y, health)
    peds[h] = { pos = vector3(x, y, 0.0), health = health or 200, max = 200, armour = 0, dead = false }
end
local armed = true
local tcIndex = -1
local cams, nextCam, rendering = {}, 100, -1
local hudVisible = true
local hudCalls = {}
local state = {}

local function hash(s)  -- stable fake hash, signed like GetHashKey
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end
    if h >= 2147483648 then h = h - 4294967296 end
    return h
end
_G.GetHashKey = hash
local WEAPON_PISTOL, WEAPON_KNIFE = 111, 222
_G.GetWeapontypeGroup = function(w)
    if w == WEAPON_PISTOL then return hash('GROUP_PISTOL') end
    if w == WEAPON_KNIFE then return hash('GROUP_MELEE') end
    return 0
end

_G.cache = { ped = PLAYER }
_G.LocalPlayer = { state = state }
_G.PlayerPedId = function() return PLAYER end
_G.GetNetworkTimeAccurate = function() return math.floor(now.net) end
_G.GetGameTimer = function() return math.floor(now.game) end
_G.GetResourceState = function(r) if r == 'vice_hud' then return 'started' end return 'missing' end
_G.GetCurrentResourceName = function() return 'vi_extras' end
_G.exports = setmetatable({
    vice_hud = { SetHudVisible = function(_, v) hudVisible = v hudCalls[#hudCalls + 1] = v end },
}, { __call = function(_, name, fn) _G['EXPORT_' .. name] = fn end })
local handlers = {}
_G.AddEventHandler = function(name, fn) handlers[name] = fn end

local threads = {}
_G.CreateThread = function(fn) threads[#threads + 1] = coroutine.create(fn) end
_G.Wait = function(ms) coroutine.yield(ms) end

_G.GetEntityCoords = function(e) if e == PLAYER then return vector3(0.0, 0.0, 0.0) end return peds[e].pos end
_G.GetEntityForwardVector = function() return vector3(0.0, 1.0, 0.0) end
_G.GetPedBoneCoords = function(e) local p = GetEntityCoords(e) return vector3(p.x, p.y, p.z + 1.2) end
_G.DoesEntityExist = function(e) return e == PLAYER or peds[e] ~= nil end
_G.IsEntityDead = function(e) if e == PLAYER then return state.playerDead == true end return peds[e].dead end
_G.IsPedFatallyInjured = function(e) return peds[e].health < 100 end
_G.GetEntityHealth = function(e) return peds[e].health end
_G.GetEntityMaxHealth = function(e) return peds[e].max end
_G.GetPedArmour = function(e) return peds[e].armour end
_G.IsPedAPlayer = function(e) return peds[e] and peds[e].player == true end
_G.GetPedSourceOfDeath = function(e) return peds[e].source or 0 end
_G.GetPedCauseOfDeath = function(e) return peds[e].cause or 0 end
_G.GetGamePool = function()
    local list = { PLAYER }
    for h in pairs(peds) do list[#list + 1] = h end
    table.sort(list)
    return list
end
_G.IsPedArmed = function() return armed end
_G.IsPauseMenuActive = function() return false end
_G.IsHudComponentActive = function() return false end
_G.IsCutsceneActive = function() return false end
_G.IsCutscenePlaying = function() return false end
_G.IsPlayerSwitchInProgress = function() return false end
_G.IsScreenFadedOut = function() return false end
_G.HideHudAndRadarThisFrame = function() end
_G.SetTimeScale = function(s) timeScale = s end
_G.GetTimecycleModifierIndex = function() return tcIndex end
_G.SetTimecycleModifier = function(name) tcIndex = (name == 'rply_saturation_neg') and 42 or 7 end
_G.SetTimecycleModifierStrength = function() end
_G.ClearTimecycleModifier = function() tcIndex = -1 end
_G.GetGameplayCamCoord = function() return vector3(0.0, -3.0, 1.5) end
_G.GetGameplayCamRot = function() return vector3(0.0, 0.0, 0.0) end
_G.CreateCamWithParams = function(_, x, y, z, rx, ry, rz, fov)
    nextCam = nextCam + 1
    cams[nextCam] = { pos = vector3(x, y, z), fov = fov }
    return nextCam
end
_G.DoesCamExist = function(c) return cams[c] ~= nil end
_G.DestroyCam = function(c) cams[c] = nil end
_G.SetCamActive = function() end
_G.RenderScriptCams = function(on) rendering = on and nextCam or -1 end
_G.GetRenderingCam = function() return rendering end
_G.SetCamFov = function(c, f) cams[c].fov = f end
_G.SetCamCoord = function(c, x, y, z) cams[c].pos = vector3(x, y, z) end
_G.PointCamAtCoord = function(c, x, y, z) cams[c].aim = vector3(x, y, z) end
_G.StartExpensiveSynchronousShapeTestLosProbe = function() return 1 end
_G.GetShapeTestResult = function() return 2, false, vector3(0, 0, 0), vector3(0, 0, 0), 0 end

-- ---- modules (require as ox_lib does it)
local function loadfile_(path)
    local src = readfile and readfile(path)
    if not src and io and io.open then local f = io.open(path, 'rb') src = f:read('a') f:close() end
    return assert(load(src, '@' .. path))
end
local mods = {}
local killcamDefault = true
_G.require = function(name)
    if mods[name] then return mods[name] end
    local m
    if name == 'vi_killcam.config' then
        m = loadfile_('vi_killcam/config.lua')()
        m.default = killcamDefault
    else
        m = loadfile_(name:gsub('%.', '/') .. '.lua')()
    end
    mods[name] = m
    return m
end
_G.GetResourceKvpString = function() return nil end
_G.SetResourceKvp = function() end

loadfile_('vi_killcam/client.lua')()
local options = mods['vi_hudoptions.options']
local playing = function() return _G.EXPORT_IsKillCamPlaying() end

-- ---- running frames
local wakeAt = {}
local function frame(dtReal)
    dtReal = dtReal or 16
    now.net = now.net + dtReal
    now.game = now.game + dtReal * timeScale
    for i, co in ipairs(threads) do
        if coroutine.status(co) ~= 'dead' and (wakeAt[i] or 0) <= now.net then
            local okr, ms = coroutine.resume(co)
            if not okr then error(ms) end
            wakeAt[i] = now.net + (ms or 0)
        end
    end
end
local function run(ms) local t = 0 while t < ms do frame(16) t = t + 16 end end
local function oneShotKill(h, weapon)
    peds[h].health = 0
    peds[h].dead = true
    peds[h].source = PLAYER
    peds[h].cause = weapon or WEAPON_PISTOL
end

ok(options.get('killcam') == true, 'the row exists and starts on its default')

-- three peds, watched while armed
addPed(10, 0, 10) addPed(11, 5, 10) addPed(12, -5, 10) addPed(13, 3, 12) addPed(14, 3, 30)
run(600)
oneShotKill(10) run(100)
ok(not playing(), 'one one-shot kill: no shot')
oneShotKill(11) run(100)
ok(not playing(), 'two one-shot kills: no shot')
-- a wounded ped: hurt a frame before it dies
peds[12].health = 150 run(100)
oneShotKill(12) run(100)
ok(not playing(), 'a kill on someone already hurt does not count')
-- a knife kill
oneShotKill(13, WEAPON_KNIFE) run(100)
ok(not playing(), 'a knife kill does not count')
-- someone else's kill
peds[14].health = 0 peds[14].dead = true peds[14].source = 999 peds[14].cause = WEAPON_PISTOL
run(100)
ok(not playing(), 'a kill by someone else does not count')

addPed(20, 0, 8)
run(300)
oneShotKill(20) frame(16)
ok(playing(), 'the third one-shot kill plays the shot')
ok(timeScale == 0.25, 'quarter speed')
ok(tcIndex == 42, 'washed-out filter on')
ok(hudVisible == false, 'vice_hud HUD hidden')
local cam = rendering
ok(cams[cam] and cams[cam].fov == 40.0, 'cut 0 at FOV 40')
local c0 = cams[cam].pos
ok(math.abs(#(c0 - vector3(0.0, 8.0, 1.2)) - math.sqrt(2.3 ^ 2 + 1.1 ^ 2 + 0.15 ^ 2)) < 0.01, 'cut 0 stands 2.3 m back, 1.1 m aside, 0.15 m up from the chest')
ok(cams[cam].aim and math.abs(cams[cam].aim.z - 1.3) < 0.001, 'cut 0 aims at the victim chest + 0.1')
run(1000)
ok(playing() and cams[cam].fov == 40.0, 'still on the victim at 1 s')
local c1 = cams[cam].pos
ok(#(c1 - vector3(0.0, 8.0, 1.2)) - #(c0 - vector3(0.0, 8.0, 1.2)) < 0.01 and #(c1 - c0) > 0.1, 'the camera swings round the victim at a fixed distance')
run(500)
ok(playing() and cams[cam].fov == 46.0, 'cut 1 on you at FOV 46 after 1.456 s')
ok(math.abs(cams[cam].aim.z - 1.45) < 0.001, 'cut 1 aims at your chest + 0.25')
run(1400)
ok(not playing(), 'the shot ends at 2.8 s real time')
ok(timeScale == 1.0 and tcIndex == -1 and rendering == -1, 'speed, colour and camera back')
ok(hudVisible == true, 'HUD back')
ok(cams[cam] == nil, 'camera destroyed')

-- cooldown: three more inside 7 s of the start
addPed(30, 0, 9) addPed(31, 1, 9) addPed(32, 2, 9) addPed(33, 3, 9)
run(300)
oneShotKill(30) run(50) oneShotKill(31) run(50) oneShotKill(32) run(50)
ok(not playing(), 'no shot within 7 s of the last one starting')
run(4000)
oneShotKill(33) frame(16)
ok(playing(), 'the next one-shot kill after the cooldown plays (count held at 3)')

-- the row switched off mid-shot
options.set('killcam', false)
ok(not playing() and timeScale == 1.0 and rendering == -1 and hudVisible == true, 'switching the row off ends the shot and puts everything back')
options.set('killcam', true)

-- death mid-shot
peds = {}
addPed(40, 0, 9) addPed(41, 1, 9) addPed(42, 2, 9)
run(8000)
oneShotKill(40) run(50) oneShotKill(41) run(50) oneShotKill(42) frame(16)
ok(playing(), 'another shot after three more')
state.playerDead = true
run(50)
ok(not playing() and timeScale == 1.0 and rendering == -1, 'dying ends the shot')
ok(hudVisible == false, 'the HUD waits while you are dead')
state.playerDead = false
run(600)
ok(hudVisible == true, 'the HUD comes back once you are up')

-- resource stop mid-shot
peds = {}
addPed(50, 0, 9) addPed(51, 1, 9) addPed(52, 2, 9)
run(8000)
oneShotKill(50) run(50) oneShotKill(51) run(50) oneShotKill(52) frame(16)
ok(playing(), 'and another')
handlers.onResourceStop('vi_extras')
ok(not playing() and timeScale == 1.0 and rendering == -1 and hudVisible == true and tcIndex == -1, 'resource stop puts the game back')

-- another script's camera on screen blocks it
peds = {}
addPed(60, 0, 9) addPed(61, 1, 9) addPed(62, 2, 9)
run(8000)
cams[999] = {} rendering = 999
oneShotKill(60) run(50) oneShotKill(61) run(50) oneShotKill(62) frame(16)
ok(not playing(), 'no shot while another script camera renders')
cams[999] = nil rendering = -1

-- unarmed: nothing watched
peds = {}
armed = false
addPed(70, 0, 9)
run(2000)
oneShotKill(70) run(100)
ok(not playing(), 'unarmed: nothing is watched (a one-shot needs a gun)')

print(('%d/%d passed'):format(total - fails, total))
return fails == 0
