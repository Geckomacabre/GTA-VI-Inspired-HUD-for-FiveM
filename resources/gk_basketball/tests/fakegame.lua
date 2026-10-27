--[[
    Just enough of the game for client/ballsim.lua to run on a desk.

    Entities are rows in a table. Threads are coroutines stepped a frame at a
    time. The world is tests/world.lua's planes and water, reached through the
    same shape-test and water natives the real thing calls -- so what is under
    test is the glue's reading of those natives, which is the part of the ball
    that can't be seen from inside the physics tests.

    `Fake.sweepMeans` sets what the swept-sphere test reports as its end
    coordinates, because that is the thing the glue has to work out for itself:
        'contact'  the point touched on the surface
        'centre'   where the sphere's centre was
        'pending'  nothing this frame (status 1), which forces the ray fallback
]]

local Fake = {
    now = 1000,             -- ms
    frame = 1.0 / 60.0,
    threads = {},
    entities = {},
    nextEntity = 100,
    sweepMeans = 'contact',
    world = nil,
    events = {},
    player = nil,
}

--------------------------------------------------------------------------------
-- Vectors
--------------------------------------------------------------------------------

local V = {}
V.__index = V

function vec3(x, y, z) return setmetatable({ x = x + 0.0, y = y + 0.0, z = z + 0.0 }, V) end
vector3 = vec3

function vec4(x, y, z, w) return { x = x + 0.0, y = y + 0.0, z = z + 0.0, w = w + 0.0 } end

V.__add = function(a, b) return vec3(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b)
    if type(a) == 'number' then return vec3(b.x * a, b.y * a, b.z * a) end
    return vec3(a.x * b, a.y * b, a.z * b)
end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end

--------------------------------------------------------------------------------
-- Threads and time
--------------------------------------------------------------------------------

function CreateThread(fn)
    Fake.threads[#Fake.threads + 1] = { co = coroutine.create(fn), wake = 0 }
end

function Wait(ms) coroutine.yield(ms or 0) end

function GetGameTimer() return math.floor(Fake.now) end
function GetFrameTime() return Fake.frame end

--- Runs every thread that is due, then moves the clock on one frame.
function Fake.tick()
    local i = 1
    while i <= #Fake.threads do
        local t = Fake.threads[i]

        if Fake.now >= t.wake then
            local ok, wait = coroutine.resume(t.co)
            if not ok then error('thread died: ' .. tostring(wait), 0) end

            if coroutine.status(t.co) == 'dead' then
                table.remove(Fake.threads, i)
                i = i - 1
            else
                t.wake = Fake.now + (wait or 0)
            end
        end

        i = i + 1
    end

    Fake.now = Fake.now + Fake.frame * 1000.0
    if Fake.world then Fake.world.time = (Fake.world.time or 0.0) + Fake.frame end
end

function Fake.run(seconds, each)
    for _ = 1, math.floor(seconds / Fake.frame + 0.5) do
        Fake.tick()
        if each and each() == false then return end
    end
end

--------------------------------------------------------------------------------
-- Entities
--------------------------------------------------------------------------------

function Fake.entity(x, y, z)
    Fake.nextEntity = Fake.nextEntity + 1
    Fake.entities[Fake.nextEntity] = {
        pos = vec3(x, y, z), vel = vec3(0, 0, 0), frozen = false, collision = true, gravity = true,
        quat = { 0, 0, 0, 1 }, owned = true,
    }
    return Fake.nextEntity
end

local function ent(id) return Fake.entities[id] end

function DoesEntityExist(id) return ent(id) ~= nil end
function NetworkHasControlOfEntity(id) return ent(id) ~= nil and ent(id).owned end
function GetEntityCoords(id) local e = ent(id); return vec3(e.pos.x, e.pos.y, e.pos.z) end
function GetEntityVelocity(id) local e = ent(id); return vec3(e.vel.x, e.vel.y, e.vel.z) end
function SetEntityCoordsNoOffset(id, x, y, z) ent(id).pos = vec3(x, y, z) end
function SetEntityVelocity(id, x, y, z) ent(id).vel = vec3(x, y, z) end
function SetEntityQuaternion(id, x, y, z, w) ent(id).quat = { x, y, z, w } end
function SetEntityCollision(id, on) ent(id).collision = on end
function SetEntityHasGravity(id, on) ent(id).gravity = on end
function FreezeEntityPosition(id, on) ent(id).frozen = on end
function DeleteEntity(id) Fake.entities[id] = nil end
function PlayerPedId() return Fake.player end
function IsPedInAnyVehicle() return false end
function GetPedBoneCoords(id, _, ox, oy, oz) local p = ent(id).pos; return vec3(p.x + ox, p.y + oy, p.z + oz + 0.7) end
function GetGamePool() return Fake.peds or {} end
function NetworkDoesNetworkIdExist(id) return ent(id) ~= nil end
function NetToObj(id) return id end

--------------------------------------------------------------------------------
-- Shape tests and water
--------------------------------------------------------------------------------

local handles, nextHandle = {}, 0

local function hashOf(name)
    local h = 0
    for i = 1, #name do h = (h * 31 + name:byte(i)) & 0xFFFFFFFF end
    return h
end

function GetHashKey(name) return hashOf(name) end

local function start(kind, x1, y1, z1, x2, y2, z2, radius, options)
    nextHandle = nextHandle + 1
    handles[nextHandle] = { kind = kind, x1, y1, z1, x2, y2, z2, radius = radius, options = options or 7 }
    return nextHandle
end

function StartShapeTestSweptSphere(x1, y1, z1, x2, y2, z2, radius, _, _, options)
    return start('sweep', x1, y1, z1, x2, y2, z2, radius, options)
end

function StartExpensiveSynchronousShapeTestLosProbe(x1, y1, z1, x2, y2, z2, _, _, options)
    return start('ray', x1, y1, z1, x2, y2, z2, 0.0, options)
end

--- What a test passes through, from its options, as the game has it: 1 skips
--- glass, 2 skips anything see-through (a chain-link fence is), 4 skips what has
--- no collision. A surface says which it is: { glass = true }, { seeThrough = true }.
local function skipper(options)
    return function(surface)
        return (surface.glass and (options & 1) ~= 0) or (surface.seeThrough and (options & 2) ~= 0) or false
    end
end

function GetShapeTestResultIncludingMaterial(handle)
    local q = handles[handle]
    handles[handle] = nil
    if not q then return 0 end

    if q.kind == 'sweep' and Fake.sweepMeans == 'pending' then return 1 end

    local hit, cx, cy, cz, nx, ny, nz, surface = Fake.world.sweep(q[1], q[2], q[3], q[4], q[5], q[6], q.radius,
        skipper(q.options))
    if not hit then return 2, 0, vec3(0, 0, 0), vec3(0, 0, 0), 0, 0 end

    local material = surface and surface.material and hashOf(surface.material) or hashOf('CONCRETE')

    if q.kind == 'sweep' and Fake.sweepMeans == 'contact' then
        cx, cy, cz = cx - nx * q.radius, cy - ny * q.radius, cz - nz * q.radius
    end

    return 2, 1, vec3(cx, cy, cz), vec3(nx, ny, nz), material, 0
end

function GetShapeTestResult(handle)
    local status, hit, pos, normal = GetShapeTestResultIncludingMaterial(handle)
    return status, hit, pos, normal, 0
end

function GetWaterHeight(x, y, z)
    local h = Fake.world.water(x, y, z)
    if h then return true, h end
    return false, 0.0
end

function TestVerticalProbeAgainstAllWater() return 0, 0.0 end

--------------------------------------------------------------------------------
-- Everything else the client files touch on the way in
--------------------------------------------------------------------------------

function RegisterCommand() end
function RegisterNetEvent() end
function AddEventHandler() end
function GetCurrentResourceName() return 'gk_basketball' end

function TriggerServerEvent(name, ...)
    Fake.events[#Fake.events + 1] = { name = name, ... }
end

return Fake
