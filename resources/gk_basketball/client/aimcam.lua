--[[
    The camera while aiming a 'rings' shot (Config.Shot.style): in over the
    right shoulder and closer than the game's, looking wherever the game's own
    camera looks.

    The player turns it with the mouse or stick as ever. The game's camera goes
    on following that input underneath, and this one is put beside the ped,
    facing the same way, every frame. So the reticle in the middle of the
    screen is on whatever the game's camera is on, and a shot or throw that
    goes "where you are looking" goes where the reticle is.
]]

BB.aimCam = {}

local C = BB.aimCam
local cam = nil

--- Which way a rotation (pitch x, yaw z, degrees) looks.
local function lookOf(rot)
    local yaw, pitch = math.rad(rot.z), math.rad(rot.x)
    local c = math.cos(pitch)

    return vec3(-math.sin(yaw) * c, math.cos(yaw) * c, math.sin(pitch))
end

--- Where the camera that is drawing the picture is, and which way it looks:
--- this one while aiming, the game's otherwise.
--- @return vector3 eye, vector3 look
function C.view()
    local rot = GetGameplayCamRot(2)

    if cam then return GetCamCoord(cam), lookOf(rot) end

    return GetGameplayCamCoord(), lookOf(rot)
end

function C.active() return cam ~= nil end

--- Puts the camera where it goes this frame. Kept out of walls: if something
--- solid is between the ped's head and the place over the shoulder, the camera
--- comes in to just this side of it.
function C.update()
    if not cam then return end

    local cfg   = Config.Shot.rings.camera
    local ped   = PlayerPedId()
    local rot   = GetGameplayCamRot(2)
    local look  = lookOf(rot)
    local yaw   = math.rad(rot.z)
    local at    = GetEntityCoords(ped)

    local head  = vec3(at.x, at.y, at.z + cfg.up)
    local want  = head + vec3(math.cos(yaw), math.sin(yaw), 0.0) * cfg.right - look * cfg.back

    local probe = StartExpensiveSynchronousShapeTestLosProbe(head.x, head.y, head.z, want.x, want.y, want.z,
        1 + 16, ped, 4)
    local status, hit, point = GetShapeTestResult(probe)
    local pos = want

    if status == 2 and (hit == true or hit == 1) then
        local back = head - point
        local len = #back

        pos = len > 0.25 and point + back * (0.2 / len) or head
    end

    SetCamCoord(cam, pos.x, pos.y, pos.z)
    SetCamRot(cam, rot.x, rot.y, rot.z, 2)
end

function C.start()
    local cfg = Config.Shot.rings.camera
    if cam or not cfg.enabled then return end

    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    SetCamFov(cam, cfg.fov)
    C.update()
    SetCamActive(cam, true)
    RenderScriptCams(true, true, cfg.blendMs, true, false)
end

function C.stop()
    if not cam then return end

    local cfg = Config.Shot.rings.camera

    RenderScriptCams(false, true, cfg.blendMs, true, false)
    SetCamActive(cam, false)
    DestroyCam(cam, false)
    cam = nil
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not cam then return end

    RenderScriptCams(false, false, 0, true, false)
    DestroyCam(cam, false)
    cam = nil
end)
