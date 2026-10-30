-- Headless run of vi_camweight against mocked natives.
local HERE = 'tools/'
local H = assert(load(readfile(HERE .. 'driving_harness.lua'), '@harness.lua'))()
local vec = H.vec
local fails, total = 0, 0
local function ok(c, msg) total = total + 1 if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end end

-- world
local W = {
    veh = 10, class = 0, pos = vec(0, 0, 0), vel = vec(0, 20, 0), inAir = false,
    camRot = vec(-5, 0, 90), camCoord = vec(0, -6, 2), fov = 50.0,
    rendering = -1, cams = {}, nextCam = 5, active = nil,
    viewMode = 1, dead = false, crashcam = false, control = true, nui = false,
}
function PlayerPedId() return 1 end
function PlayerId() return 0 end
function GetVehiclePedIsIn() return W.veh end
function GetVehicleClass() return W.class end
function IsEntityDead() return W.dead end
function DoesEntityExist() return true end
function GetIsLoadingScreenActive() return false end
function IsPlayerSwitchInProgress() return false end
function IsPauseMenuActive() return false end
function IsNuiFocused() return W.nui end
function GetFrameTime() return H.frameMs / 1000 end
function GetEntityCoords() return W.pos end
function GetEntityVelocity() return W.vel end
function IsEntityInAir() return W.inAir end
function GetGameplayCamRot() return W.camRot end
function GetGameplayCamCoord() return W.camCoord end
function GetGameplayCamFov() return W.fov end
function IsCutscenePlaying() return false end
function IsScreenFadedOut() return false end
function IsPlayerControlOn() return W.control end
function GetRenderingCam() return W.rendering end
function IsAimCamActive() return false end
function IsFirstPersonAimCamActive() return false end
function IsPlayerFreeAiming() return false end
function IsGameplayCamLookingBehind() return false end
function GetCamActiveViewModeContext() return 0 end
function GetCamViewModeForContext() return W.viewMode end
function IsGameplayCamRendering() return W.rendering == -1 end
function IsCinematicCamRendering() return false end
function IsFollowVehicleCamActive() return true end
function IsGameplayCamShaking() return false end
function CreateCam() local c = W.nextCam W.nextCam = W.nextCam + 1 W.cams[c] = {} H.log('CreateCam', c) return c end
function DoesCamExist(c) return W.cams[c] ~= nil end
function DestroyCam(c) W.cams[c] = nil H.log('DestroyCam', c) end
function SetCamCoord(c, x, y, z) end
function SetCamRot(c, x, y, z) H.log('SetCamRot', c, x, y, z) end
function SetCamFov() end
function SetCamActive(c, on) if on then W.active = c end end
function RenderScriptCams(on) H.log('RenderScriptCams', on) W.rendering = on and W.active or -1 end
H.resources.vi_crashcam = 'started'
H.exports = { vi_crashcam = { IsCrashCamPlaying = function() return W.crashcam end } }

H.load('vi_camweight/client.lua')

local function step(ms, f) local stop = H.now + ms while H.now < stop do if f then f() end H.frame() end end

-- settle (GameReady's 3 s), driving along
step(3500, function() W.pos = W.pos + W.vel * (H.frameMs / 1000) end)
ok(#H.find('CreateCam') == 0, 'no camera while just driving')

-- a jump: up, a second in the air, down at 10 m/s, then a landing
local function jump()
    W.inAir = true
    local vz = 5.0
    step(1000, function() vz = vz - 15 * H.frameMs / 1000 W.vel = vec(0, 20, vz) W.pos = W.pos + W.vel * (H.frameMs / 1000) end)
    W.inAir = false
    W.vel = vec(0, 20, 0)
end
local mark = #H.calls + 1
jump()
step(50)
local created = H.find('CreateCam', mark)
ok(#created == 1, 'a landing makes the dip camera')
ok(W.rendering == (created[1] and created[1].args[1]), 'and it is on screen')
local lowest = 0
step(1200, function()
    for _, c in ipairs(H.find('SetCamRot', #H.calls)) do end
end)
for _, c in ipairs(H.find('SetCamRot', mark)) do
    local d = W.camRot.x - c.args[2]
    if d > lowest then lowest = d end
end
print(('        deepest dip %.2f deg'):format(lowest))
ok(lowest > 2.5 and lowest < 4.6, 'dips by a few degrees (fall 10 m/s -> about 3.4)')
ok(W.rendering == -1 and next(W.cams) == nil, 'eases back, camera gone, game camera back')

-- leaving the vehicle mid-dip
mark = #H.calls + 1
jump()
step(60)
ok(W.rendering ~= -1, 'dip again')
W.veh = 0
step(300)
ok(W.rendering == -1 and next(W.cams) == nil, 'leaving the vehicle hands the view back')
W.veh = 10
step(500)

-- dying mid-dip (Qbox keeps the ped alive)
jump()
step(60)
LocalPlayer.state.isDead = true
step(300)
ok(W.rendering == -1 and next(W.cams) == nil, 'dying hands the view back')
LocalPlayer.state.isDead = nil
step(500)

-- crash cam starting mid-dip
jump()
step(60)
W.crashcam = true
step(50)
ok(W.rendering == -1 and next(W.cams) == nil, 'the crash cam takes over')
mark = #H.calls + 1
jump()
step(60)
ok(#H.find('CreateCam', mark) == 0, 'nothing while the crash cam plays')
W.crashcam = false
step(500)

-- another resource's camera taking over mid-dip
jump()
step(60)
local mine = W.rendering
W.cams[99] = {} W.active = 99 W.rendering = 99
mark = #H.calls + 1
step(50)
ok(W.cams[mine] == nil, 'our camera destroyed when another takes the screen')
ok(W.rendering == 99 and #H.find('RenderScriptCams', mark) == 0, 'and theirs left on screen')
W.cams[99] = nil W.rendering = -1
step(500)

-- first person: nothing
W.viewMode = 4
mark = #H.calls + 1
jump()
step(100)
ok(#H.find('CreateCam', mark) == 0, 'first person: no dip')
W.viewMode = 1
step(500)

-- row off mid-dip
local options = require 'vi_hudoptions.options'
jump()
step(60)
ok(W.rendering ~= -1, 'dip again')
options.set('camweight', false)
ok(W.rendering == -1 and next(W.cams) == nil, 'row off hands the view back at once')
mark = #H.calls + 1
jump()
step(100)
ok(#H.find('CreateCam', mark) == 0, 'row off: no dip')
options.set('camweight', true)

-- resource stop mid-dip
jump()
step(60)
H.trigger('onResourceStop', 'vi_extras')
ok(W.rendering == -1 and next(W.cams) == nil, 'resource stop hands the view back')

-- a crash: 60 km/h lost in a frame (the stopped thread above
-- would be gone in FiveM; here it finishes its dip first)
step(1500)
mark = #H.calls + 1
W.vel = vec(0, 20, 0)
step(100)
W.vel = vec(0, 3.3, 0)
step(100)
ok(#H.find('CreateCam', mark) == 1, 'a crash dips the camera')

print(('%d/%d passed'):format(total - fails, total))
return fails == 0
