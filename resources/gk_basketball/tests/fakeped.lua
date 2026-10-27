--[[
    The rest of the game that client/ball.lua needs, on top of tests/fakegame.lua:
    a ped with a heading, a few bones and animations that keep time, a player
    with buttons, and a server that answers.

    Animations here are clocks and nothing else: a clip that is playing has a
    phase that moves on with the frame at whatever speed it was set to, which is
    exactly the part the dribble depends on. Where the hands are is made up from
    what is playing (the stance brings them together, a shot puts them overhead),
    so that the ball can be checked against them.
]]

local Fake = FAKE       -- tests/fakegame.lua's table, put there by whoever loads this

Fake.clips     = {}     -- ['dict/name'] = seconds long
Fake.loaded    = {}     -- [dict] = false to refuse to load it
Fake.controls  = {}     -- [control] = true while held
Fake.pressed   = {}     -- [control] = true for the frame it went down
Fake.released  = {}     -- [control] = true for the frame it came up
Fake.disabled  = {}     -- [control] = frames it was disabled on
Fake.cam       = 0.0    -- camera heading
Fake.server    = { pickup = true }
Fake.played    = {}     -- every TaskPlayAnim, in order: { ped, dict, name, flag, start }

local function key(dict, name) return dict .. '/' .. name end

--------------------------------------------------------------------------------
-- A ped
--------------------------------------------------------------------------------

function Fake.ped(x, y, z, heading)
    local id = Fake.entity(x, y, z)
    local e = Fake.entities[id]

    e.heading = heading or 0.0
    e.anims = {}        -- [key] = { phase, speed, flag, dict, name }

    return id
end

local function basis(h)
    local r = math.rad(h)
    -- forward, right
    return -math.sin(r), math.cos(r), math.cos(r), math.sin(r)
end

function GetEntityHeading(id) return Fake.entities[id].heading or 0.0 end
function SetEntityHeading(id, h) Fake.entities[id].heading = h % 360.0 end
function GetEntitySpeed(id) local v = Fake.entities[id].vel; return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end

function GetOffsetFromEntityInWorldCoords(id, ox, oy, oz)
    local e = Fake.entities[id]
    local fx, fy, rx, ry = basis(e.heading or 0.0)

    return vec3(e.pos.x + rx * ox + fx * oy, e.pos.y + ry * ox + fy * oy, e.pos.z + oz)
end

function GetOffsetFromEntityGivenWorldCoords(id, x, y, z)
    local e = Fake.entities[id]
    local fx, fy, rx, ry = basis(e.heading or 0.0)
    local dx, dy = x - e.pos.x, y - e.pos.y

    return vec3(dx * rx + dy * ry, dx * fx + dy * fy, z - e.pos.z)
end

function GetHeadingFromVector_2d(dx, dy)
    return math.deg(math.atan(-dx, dy)) % 360.0
end

local function playing(e, what)
    for _, a in pairs(e.anims) do
        if a.name:find(what, 1, true) then return a end
    end
end

--- Where a bone is, in the ped's own frame (right, forward, up from its middle).
local function bone(e, id)
    if id == 14201 then return -0.10, 0.0, -0.93 end      -- left foot (ankle)
    if id == 52301 then return 0.10, 0.0, -0.93 end       -- right foot
    if id == 31086 then return 0.0, 0.0, 0.65 end         -- head

    local right = id == 28422 or id == 57005

    if playing(e, 'jumpshot') then return right and 0.10 or -0.10, 0.12, 0.98 end
    if playing(e, 'idle_ball') or playing(e, 'pass_') then return right and 0.12 or -0.12, 0.32, 0.05 end
    if playing(e, 'pickup') then return right and 0.12 or -0.12, 0.35, -0.75 end

    -- Dribbling, or nothing: the right hand out to the side and bobbing, the
    -- left one hanging.
    local a = playing(e, 'dribble')
    local bob = a and 0.12 * math.sin(a.phase * 2.0 * math.pi * 3.0) or 0.0

    if right then return 0.36, 0.34, -0.02 + bob end
    return -0.34, 0.05, -0.12
end

function GetPedBoneCoords(id, boneId, ox, oy, oz)
    local e = Fake.entities[id]
    local bx, by, bz = bone(e, boneId)
    local fx, fy, rx, ry = basis(e.heading or 0.0)

    bx, by, bz = bx + (ox or 0.0), by + (oy or 0.0), bz + (oz or 0.0)

    return vec3(e.pos.x + rx * bx + fx * by, e.pos.y + ry * bx + fy * by, e.pos.z + bz)
end

--------------------------------------------------------------------------------
-- Animations
--------------------------------------------------------------------------------

function RequestAnimDict() end
function HasAnimDictLoaded(dict) return Fake.loaded[dict] ~= false end

-- ms between an animation being asked for and it actually playing. In the game
-- that is a frame or two; a test can make it longer to see what the client does
-- in the meantime.
Fake.lag = 0

local function begin(e, a)
    local secondary = (a.flag & 32) ~= 0

    -- One at a time in each of the two places an animation can be.
    for k, other in pairs(e.anims) do
        if ((other.flag & 32) ~= 0) == secondary then e.anims[k] = nil end
    end

    e.anims[key(a.dict, a.name)] = a
end

function TaskPlayAnim(id, dict, name, _, _, _, flag, start)
    local e = Fake.entities[id]
    if not e or Fake.loaded[dict] == false then return end

    local a = { dict = dict, name = name, flag = flag, speed = 1.0, phase = start or 0.0 }

    Fake.played[#Fake.played + 1] = { ped = id, dict = dict, name = name, flag = flag, start = start or 0.0 }

    if Fake.lag > 0 then
        e.pending = { anim = a, at = Fake.now + Fake.lag }
    else
        begin(e, a)
    end
end

function StopAnimTask(id, dict, name)
    local e = Fake.entities[id]
    if e and e.anims then e.anims[key(dict, name)] = nil end
end

function ClearPedTasks(id)
    local e = Fake.entities[id]
    if not e or not e.anims then return end

    -- A ped's tasks are cleared; what is layered on top of them is not.
    for k, a in pairs(e.anims) do
        if (a.flag & 32) == 0 then e.anims[k] = nil end
    end
end

function IsEntityPlayingAnim(id, dict, name)
    local e = Fake.entities[id]
    return e ~= nil and e.anims ~= nil and e.anims[key(dict, name)] ~= nil
end

function GetEntityAnimCurrentTime(id, dict, name)
    local a = Fake.entities[id].anims[key(dict, name)]
    return a and a.phase or 0.0
end

function SetEntityAnimCurrentTime(id, dict, name, phase)
    local a = Fake.entities[id].anims[key(dict, name)]
    if a then a.phase = phase end
end

function SetEntityAnimSpeed(id, dict, name, speed)
    local a = Fake.entities[id].anims[key(dict, name)]
    if a then a.speed = speed end
end

--- Moves every playing animation on by a frame. Called once a frame by the test.
function Fake.animate()
    for _, e in pairs(Fake.entities) do
        if e.anims and e.pending and Fake.now >= e.pending.at then
            begin(e, e.pending.anim)
            e.pending = nil
        end

        if e.anims then
            for k, a in pairs(e.anims) do
                local length = Fake.clips[k] or 1.0
                a.phase = a.phase + Fake.frame * a.speed / length

                if a.phase >= 1.0 then
                    if (a.flag & 1) ~= 0 then a.phase = a.phase % 1.0 else e.anims[k] = nil end
                end
            end
        end

        -- And everything moves at the speed it was given.
        if e.anims and not e.frozen then
            e.pos = vec3(e.pos.x + e.vel.x * Fake.frame, e.pos.y + e.vel.y * Fake.frame, e.pos.z + e.vel.z * Fake.frame)
        end
    end
end

--------------------------------------------------------------------------------
-- The player
--------------------------------------------------------------------------------

function PlayerId() return 0 end
function GetPlayerServerId() return 1 end
function GetActivePlayers() return {} end
function GetPlayerPed() return Fake.player end
function GetPlayerFromServerId() return -1 end

function GetGameplayCamRot() return vec3(Fake.pitch or 0.0, 0.0, Fake.cam) end

-- The game's camera, three metres behind the player along the way it looks.
function GetGameplayCamCoord()
    local p = Fake.entities[Fake.player].pos
    local yaw = math.rad(Fake.cam)
    return vec3(p.x + math.sin(yaw) * 3.0, p.y - math.cos(yaw) * 3.0, p.z + 0.8)
end

-- Scripted cameras: where they are and whether one is being looked through
-- (Fake.rendering).
Fake.cams = {}
function CreateCam() local id = #Fake.cams + 1; Fake.cams[id] = { pos = vec3(0, 0, 0) }; return id end
function SetCamFov(cam, fov) Fake.cams[cam].fov = fov end
function SetCamActive(cam, on) Fake.cams[cam].active = on end
function SetCamCoord(cam, x, y, z) Fake.cams[cam].pos = vec3(x, y, z) end
function SetCamRot(cam, x, y, z) Fake.cams[cam].rot = vec3(x, y, z) end
function GetCamCoord(cam) return Fake.cams[cam].pos end
function DestroyCam(cam) Fake.cams[cam].destroyed = true end
function RenderScriptCams(on) Fake.rendering = on end
function HideHudComponentThisFrame() end

-- What was sent to the page, oldest first.
Fake.nui = {}
function SendNUIMessage(msg) Fake.nui[#Fake.nui + 1] = msg end

function DisableControlAction(_, control) Fake.disabled[control] = (Fake.disabled[control] or 0) + 1 end
function IsDisabledControlPressed(_, control) return Fake.controls[control] == true end
function IsDisabledControlJustPressed(_, control) return Fake.pressed[control] == true end
function IsDisabledControlJustReleased(_, control) return Fake.released[control] == true end
function IsControlJustReleased(_, control) return Fake.released[control] == true end

-- The stick: Fake.stick = { x, y } pushes it.
function GetControlNormal(_, control)
    local stick = Fake.stick or {}
    if control == 30 then return stick[1] or 0.0 end
    if control == 31 then return stick[2] or 0.0 end
    return 0.0
end

function Fake.hold(control) Fake.controls[control], Fake.pressed[control] = true, true end
function Fake.let(control) Fake.controls[control], Fake.released[control] = nil, true end

function IsPedSwimming() return false end
function IsPedRagdoll() return false end
function IsEntityDead() return false end

LocalPlayer = { state = { set = function() end } }

function Player() return { state = {} } end
function Entity() return { state = {} } end

--------------------------------------------------------------------------------
-- Objects, and the things a client file does that don't matter here
--------------------------------------------------------------------------------

function IsModelInCdimage() return true end
function RequestModel() end
function HasModelLoaded() return true end
function SetModelAsNoLongerNeeded() end
function CreateObject(_, x, y, z) return Fake.entity(x, y, z) end
function ObjToNet(id) return id end
function SetNetworkIdCanMigrate() end
function DetachEntity() end
function SetEntityRotation() end
function TaskLookAtCoord() end
function TaskClearLookAt() end
function SetEntityVisible() end
function RequestAnimSet() end
function HasAnimSetLoaded() return true end
function SetPedMovementClipset() end
function ResetPedMovementClipset() end
function GetResourceState() return 'started' end

for _, name in ipairs({ 'DrawRect', 'DrawMarker', 'SetTextScale', 'SetTextFont', 'SetTextColour', 'SetTextOutline',
    'SetTextCentre', 'SetDrawOrigin', 'BeginTextCommandDisplayText', 'AddTextComponentSubstringPlayerName',
    'EndTextCommandDisplayText', 'ClearDrawOrigin' }) do
    _G[name] = function() end
end

exports = setmetatable({}, { __call = function() end })

lib = {
    callback = {
        -- The server, asked for a loose ball. When it says yes the ball is its
        -- to delete, as it is in the game.
        await = function(name, _, netId)
            Fake.asked = (Fake.asked or 0) + 1

            if name ~= 'gk_basketball:pickupBall' or not Fake.server.pickup then return false end

            Fake.entities[netId] = nil
            if BB and BB.loose then BB.loose[netId] = nil end

            return true
        end,
    },
}

--- One frame of everything: the scripts' threads, then the animations, and the
--- buttons that were only down or up for that frame are forgotten.
function Fake.frameOn()
    Fake.tick()
    Fake.animate()
    Fake.pressed, Fake.released = {}, {}
end

function Fake.play(seconds, each)
    for _ = 1, math.floor(seconds / Fake.frame + 0.5) do
        Fake.frameOn()
        if each and each() == false then return end
    end
end

return Fake
