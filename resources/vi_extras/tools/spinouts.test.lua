-- Headless run of vi_spinouts against mocked natives.
local HERE = 'tools/'
local H = assert(load(readfile(HERE .. 'driving_harness.lua'), '@harness.lua'))()
local vec = H.vec
local fails, total = 0, 0
local function ok(c, msg) total = total + 1 if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end end
local function near(a, b) return math.abs(a - b) < 0.01 end

-- entities: 1 = you, 10 = your car; cars 20.. with drivers 21..
local E = {}
local function car(id, t)
    t.kind = 'car' t.class = t.class or 0 t.pos = t.pos or vec(0, 20, 0) t.vel = t.vel or vec(0, 20, 0)
    t.tyres = {} t.owned = t.owned ~= false t.dmgBy = {} t.weapon = false t.collided = false
    E[id] = t
    if t.driver then E[t.driver] = { kind = 'ped', dead = false, player = false } end
end
E[1] = { kind = 'ped', dead = false, player = true, pos = vec(0, 0, 0) }
car(10, { pos = vec(0, 0, 0), vel = vec(0, 0, 0), driver = nil })
local myVeh = 0

function PlayerPedId() return 1 end
function PlayerId() return 0 end
function GetActivePlayers() return { 0 } end
function GetPlayerPed() return 1 end
function GetVehiclePedIsIn(ped) return ped == 1 and myVeh or 0 end
function DoesEntityExist(e) return E[e] ~= nil end
function IsEntityDead(e) return E[e] and E[e].dead or false end
function GetVehicleClass(e) return E[e].class end
function GetEntityCoords(e) return E[e].pos end
function GetEntityVelocity(e) return E[e].vel end
function GetEntityModel() return 1 end
function GetModelDimensions() return vec(-1, -2.5, -0.5), vec(1, 2.5, 1) end
function GetGamePool()
    local out = {}
    for id, e in pairs(E) do if e.kind == 'car' then out[#out + 1] = id end end
    table.sort(out)
    return out
end
function GetPedInVehicleSeat(v, seat) if v == 10 and myVeh == 10 then return 1 end return E[v].driver or 0 end
function GetLastPedInVehicleSeat(v) return E[v].last or 0 end
function IsVehicleSeatFree(v) return (E[v].driver or 0) == 0 end
function IsPedAPlayer(p) return E[p] and E[p].player or false end
function IsEntityAMissionEntity(e) return E[e] and E[e].mission or false end
function DoesEntityBelongToThisScript() return false end
function IsVehicleTyreBurst(v, w) return E[v].tyres[w] == true end
function HasEntityBeenDamagedByWeapon(v) return E[v].weapon end
function HasEntityBeenDamagedByEntity(v, by) return E[v].dmgBy[by] == true end
function HasEntityCollidedWithAnything(v) return E[v].collided end
function ClearEntityLastWeaponDamage(v) E[v].weapon = false end
function ClearEntityLastDamageEntity(v) E[v].dmgBy = {} end
function GetOffsetFromEntityGivenWorldCoords(v, x, y, z)
    local p = type(x) == 'table' and x or vec(x, y, z)
    return p - E[v].pos               -- every car faces north here
end
function IsEntityInAir() return false end
function NetworkHasControlOfEntity(v) return E[v].owned end
function NetworkRequestControlOfEntity(v) H.log('Request', v) E[v].grant = true end
function SetVehicleOutOfControl(v) H.log('OutOfControl', v) end
function SetVehicleReduceGrip(v, on) H.log('Grip', v, on) end
function ApplyForceToEntity(v, flag, x, y, z, ox, oy, oz) H.log('Force', v, x, y, z, ox, oy, oz) end

H.load('vi_spinouts/client.lua')
local options = require 'vi_hudoptions.options'

-- control requests are granted a couple of frames later
local function frames(n)
    for _ = 1, n do
        for _, e in pairs(E) do if e.grant then e.grantIn = (e.grantIn or 3) - 1 if e.grantIn <= 0 then e.owned = true e.grant = nil end end end
        H.frame()
    end
end

car(20, { driver = 21 })
frames(40)
ok(#H.find('Force') == 0, 'nothing happens to cars just driving')

-- a burst tyre (rear left)
local mark = #H.calls + 1
E[20].tyres[4] = true
frames(1)
local f = H.find('Force', mark)[1]
ok(#H.find('OutOfControl', mark) == 1 and #H.find('Grip', mark) == 1, 'burst tyre: out of control, grip cut')
ok(f and near(f.args[2], 3.2) and near(f.args[6], -2.125), 'pushed 3.2 (20 m/s * 0.16) right, at the back (-2.5 * 0.85)')
frames(10)
E[20].tyres[0] = true
mark = #H.calls + 1
frames(5)
ok(#H.find('Force', mark) == 0, 'spins once while in range')
frames(220)
local back = H.find('Grip', mark)
ok(#back == 1 and back[1].args[2] == false, 'grip back after 3.5 s')

-- slow car: nothing
car(30, { driver = 31, vel = vec(0, 8, 0) })
frames(40)
mark = #H.calls + 1
E[30].tyres[1] = true
frames(2)
ok(#H.find('Force', mark) == 0, 'under 11 m/s: no spin-out')

-- driver killed
car(40, { driver = 41 })
frames(40)
mark = #H.calls + 1
E[41].dead = true
frames(1)
ok(#H.find('Force', mark) == 1, 'driver killed: spin-out')

-- someone else's client owns it and you did nothing: left to them
car(50, { driver = 51, owned = false })
frames(40)
mark = #H.calls + 1
E[50].tyres[5] = true
frames(10)
ok(#H.find('Force', mark) == 0 and #H.find('Request', mark) == 0, 'not ours, not caused by us: left to its owner')

-- not owned, shot by you: asked for, then spun
car(60, { driver = 61, owned = false })
frames(40)
mark = #H.calls + 1
local rnd = math.random
math.random = function(n) if n then return 1 end return 0.05 end
E[60].weapon = true E[60].dmgBy[1] = true
frames(1)
ok(#H.find('Request', mark) == 1 and #H.find('Force', mark) == 0, 'shot, not ours: control asked for first')
frames(6)
ok(#H.find('Force', mark) == 1, 'then spun once control comes')
math.random = rnd

-- a car another player is driving
car(70, { driver = 71 })
E[71].player = true
frames(40)
mark = #H.calls + 1
E[70].tyres[0] = true
frames(2)
ok(#H.find('Force', mark) == 0, 'a car a player drives is left alone')

-- a script's car
car(80, { driver = 81, mission = true })
frames(40)
mark = #H.calls + 1
E[80].tyres[0] = true
frames(2)
ok(#H.find('Force', mark) == 0, "another script's car is left alone")

-- your own car, hit on the right side at 20 m/s
myVeh = 10
E[10].vel = vec(0, 20, 0)
frames(5)
mark = #H.calls + 1
E[10].vel = vec(-11, 15, 0)
E[10].collided = true
frames(1)
E[10].collided = false
local own = H.find('Force', mark)
ok(#own == 1 and own[1].args[1] == 10 and near(own[1].args[2], -3.2), 'own car hit on the right: back pushed left')
ok(#H.find('OutOfControl', mark) == 0, 'you keep control of your own car')
myVeh = 0

-- fast spin-out that rolls
car(90, { driver = 91, vel = vec(0, 30, 0) })
frames(40)
math.random = function(n) if n then return 1 end return 0.1 end
mark = #H.calls + 1
E[90].tyres[4] = true
frames(1)
E[90].vel = vec(8, 25, 0)              -- sliding sideways
math.random = rnd
frames(30)
local rolls = H.find('Force', mark)
ok(#rolls == 2 and near(rolls[2].args[4], math.min(5.5, 2.8 + 10 * 0.12)) and near(rolls[2].args[5], -1.0),
   'over 20 m/s it can trip over and roll')

-- switched off with grip still cut
car(100, { driver = 101 })
frames(40)
E[101].dead = true
frames(1)
mark = #H.calls + 1
options.set('spinouts', false)
local restored = H.find('Grip', mark)
local ids = {}
for _, c in ipairs(restored) do if c.args[2] == false then ids[c.args[1]] = true end end
ok(ids[100] and ids[90], 'row off: every car still spinning gets its grip back')
mark = #H.calls + 1
car(110, { driver = 111 })
frames(40)
E[110].tyres[0] = true
frames(2)
ok(#H.find('Force', mark) == 0, 'row off: no spin-outs')
options.set('spinouts', true)

-- resource stop
frames(40)
E[111].dead = true
frames(1)
mark = #H.calls + 1
H.trigger('onResourceStop', 'vi_extras')
local s = H.find('Grip', mark)
ok(#s == 1 and s[1].args[1] == 110 and s[1].args[2] == false, 'resource stop gives the grip back')

print(('%d/%d passed'):format(total - fails, total))
return fails == 0
