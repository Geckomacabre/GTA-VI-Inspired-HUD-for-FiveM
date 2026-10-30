-- Run from the resource folder (ROOT is the folder the modules are in).
ROOT = ROOT or '.'
-- Headless smoke test of vi_gunsonback + vi_drawanims with stubbed natives.
local fails, total = 0, 0
local function ok(c, msg)
    total = total + 1
    if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end
end

local function joaat(s)
    s = s:lower()
    local h = 0
    for i = 1, #s do
        h = (h + s:byte(i)) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h = (h ~ (h >> 6)) & 0xFFFFFFFF
    end
    h = (h + (h << 3)) & 0xFFFFFFFF
    h = (h ~ (h >> 11)) & 0xFFFFFFFF
    h = (h + (h << 15)) & 0xFFFFFFFF
    if h >= 0x80000000 then h = h - 0x100000000 end
    return h
end
local function u32(h) return h & 0xFFFFFFFF end

local V = {}
V.__index = V
V.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end

local GROUPS = {
    WEAPON_UNARMED = 'GROUP_UNARMED', WEAPON_CARBINERIFLE = 'GROUP_RIFLE', WEAPON_PUMPSHOTGUN = 'GROUP_SHOTGUN',
    WEAPON_SNIPERRIFLE = 'GROUP_SNIPER', WEAPON_PISTOL = 'GROUP_PISTOL', WEAPON_SMG = 'GROUP_SMG',
}
local groupOf = {}
for w, g in pairs(GROUPS) do groupOf[u32(joaat(w))] = joaat(g) end
local W = {}
for w in pairs(GROUPS) do W[w:sub(8):lower()] = joaat(w) end

-- world state ---------------------------------------------------------------
local clock, threads, handlers, bagHandlers
local objects, nextObj, loadedAssets, dicts, anim, animLog, disabled, visible
local pedWeapon, owned, oxState, oxItems, bags, myBag, netObjects

local function reset(ox)
    clock, threads, handlers, bagHandlers = 0, {}, {}, {}
    objects, nextObj, loadedAssets, dicts, anim, animLog, disabled, visible = {}, 1000, {}, {}, nil, {}, {}, true
    pedWeapon = { [100] = W.unarmed, [200] = W.unarmed }
    owned = {}
    oxState = ox and 'started' or 'missing'
    oxItems = {}
    bags = { [2] = {} }
    myBag = {}
    netObjects = 0
end

function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), at = clock } end
function Wait(ms) coroutine.yield(ms or 0) end
function GetGameTimer() return clock end
local function frame()
    clock = clock + 16
    disabled = {}
    local i = 1
    while i <= #threads do
        local th = threads[i]
        if coroutine.status(th.co) ~= 'dead' and th.at <= clock then
            local okr, ms = coroutine.resume(th.co)
            if not okr then error(ms) end
            th.at = clock + (ms or 0)
        end
        i = i + 1
    end
end
local function frames(n) for _ = 1, n do frame() end end

function AddEventHandler(name, fn) handlers[name] = handlers[name] or {} table.insert(handlers[name], fn) end
function TriggerEvent(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
function AddStateBagChangeHandler(key, _, fn) bagHandlers[#bagHandlers + 1] = { key = key, fn = fn } end
local function bagChanged(name, key, value) for _, h in ipairs(bagHandlers) do if h.key == key then h.fn(name, key, value, 0, true) end end end
LocalPlayer = { state = { set = function(_, k, v) myBag[k] = v bagChanged('player:1', k, v) end } }
function Player(sid) return { state = bags[sid] or {} } end
function GetPlayerFromStateBagName(n) return tonumber(n:match('player:(%d+)')) or 0 end
function GetActivePlayers() return { 1, 2 } end
function GetPlayerServerId(pid) return pid end
function GetPlayerPed(pid) return pid * 100 end
cache = { ped = 100, playerId = 1 }

GetHashKey = joaat
function GetWeapontypeGroup(h) return groupOf[u32(h)] or 0 end
function IsWeaponValid(h) return groupOf[u32(h)] ~= nil end
function HasPedGotWeapon(ped, h) return u32(h) == u32(W.unarmed) or owned[u32(h)] == true end
function GetResourceState(n) if n == 'ox_inventory' then return oxState end return 'missing' end
function GetCurrentResourceName() return 'vi_extras' end
function GetResourceKvpString() return nil end
function SetResourceKvp() end
exports = setmetatable({}, { __index = function(_, res)
    return { GetPlayerItems = function() return oxItems end }
end })
function GetWeapontypeModel() return 1 end
function GetModelDimensions() return vector3(-0.3, -0.05, -0.1), vector3(0.5, 0.05, 0.1) end
function HasWeaponAssetLoaded(h) return loadedAssets[u32(h)] == true end
function RequestWeaponAsset(h) loadedAssets[u32(h)] = true end
function CreateWeaponObject(h, ammo, x, y, z, show, scale, p7, net, host)
    if net then netObjects = netObjects + 1 end
    nextObj = nextObj + 1
    objects[nextObj] = { hash = u32(h) }
    return nextObj
end
function DoesEntityExist(e) return e == 100 or e == 200 or objects[e] ~= nil end
function DeleteEntity(e) objects[e] = nil end
function GetPedBoneIndex(_, bone) return bone end
function SetEntityCollision() end
function AttachEntityToEntity(o, ped, bone, x, y, z, rx, ry, rz) objects[o].att = { ped = ped, bone = bone, x = x, yaw = ry } end
function GetEntityCoords(e) if e == 200 then return vector3(5, 0, 0) end return vector3(0, 0, 0) end
function IsEntityDead() return false end
function IsPedInAnyVehicle() return false end
function IsEntityVisible() return true end
function IsPedRagdoll() return false end
function IsPedSwimming() return false end
function IsPedFalling() return false end
function GetMissionFlag() return false end
function GetFollowPedCamViewMode() return 1 end
function IsPedWalking() return false end
function IsPedRunning() return false end
function IsPedSprinting() return false end
function GetCurrentPedWeapon(ped) return true, pedWeapon[ped] end
function SetCurrentPedWeapon(ped, h) pedWeapon[ped] = h end
function SetPedCurrentWeaponVisible(_, v) visible = v end
function DisableControlAction(_, c) disabled[c] = true end
function RequestAnimDict(d) dicts[d] = true end
function HasAnimDictLoaded(d) return dicts[d] == true end
function TaskPlayAnim(_, d, c) anim = { d = d, c = c, start = clock } animLog[#animLog + 1] = 'play ' .. d:match('unarmed@(.*)') .. ' ' .. c end
function StopAnimTask(_, d, c) if anim and anim.d == d and anim.c == c then anim = nil end animLog[#animLog + 1] = 'stop ' .. c end
function GetAnimDuration() return 1.0 end
function IsEntityPlayingAnim(_, d, c) return anim ~= nil and anim.d == d and anim.c == c end
function GetEntityAnimCurrentTime() return math.min(1.0, (clock - anim.start) / 1000) end

local loaded
function require(name)
    if loaded[name] == nil then
        local path = ROOT .. '/' .. name:gsub('%.', '/') .. '.lua'
        loaded[name] = assert(load(assert(readfile(path), path), '@' .. path))() or true
    end
    return loaded[name]
end
local function boot(ox)
    reset(ox)
    loaded = {}
    for _, f in ipairs({ 'vi_drawanims/client.lua', 'vi_gunsonback/client.lua' }) do
        assert(load(assert(readfile(ROOT .. '/' .. f)), '@' .. f))()
    end
    local options = require 'vi_hudoptions.options'
    options.set('gunsonback', true)
    options.set('drawanims', true)
    return options
end

-- what hangs where on a ped: { back = { [hash] = yaw }, hand = hash }
local function rig(ped)
    local r = { back = {}, n = 0 }
    for _, o in pairs(objects) do
        if o.att and o.att.ped == ped then
            r.n = r.n + 1
            if o.att.bone == 57005 then r.hand = o.hash else r.back[o.hash] = o.att.yaw end
        end
    end
    return r
end
local S, C, P = u32(W.sniperrifle), u32(W.carbinerifle), u32(W.pistol)

-- =========================================================================
print('ox_inventory')
local options = boot(true)
oxItems = { [1] = { name = 'WEAPON_CARBINERIFLE' }, [2] = { name = 'WEAPON_PISTOL' }, [5] = { name = 'WEAPON_SNIPERRIFLE' } }
TriggerEvent('ox_inventory:updateInventory', {})
frames(5)
local r = rig(100)
-- fengari's integers are 32-bit, so its 'unsigned' order is the signed one; Lua 5.4 puts the sniper first
local lo, hi = (S < C) and S or C, (S < C) and C or S
ok(r.n == 2 and r.back[lo] == 168.0 and r.back[hi] == 192.0, 'unarmed: lower hash primary (yaw 168), the other secondary (yaw 192)')
ok(myBag.viBack and #myBag.viBack.w == 2 and myBag.viBack.h == nil, 'state bag holds both, nothing in the hand')
ok(netObjects == 0, 'no networked objects')

-- ox_inventory equips the carbine
pedWeapon[100] = W.carbinerifle
visible = true
TriggerEvent('ox_inventory:currentWeapon', { hash = W.carbinerifle, slot = 1 })
ok(visible == false, 'drawn gun out of sight straight away')
frames(2)
r = rig(100)
ok(animLog[1] == 'play back@longarms unholster', 'long-gun draw clip: ' .. tostring(animLog[1]))
ok(r.hand == C and r.back[S] ~= nil, 'carbine moves from the back to the hand as the clip starts')
ok(disabled[24] and disabled[25] and disabled[37], 'attack, aim and wheel held off')
frames(10)  -- past 0.16
r = rig(100)
ok(visible == true, 'carbine in sight at the switch point')
ok(r.n == 1 and r.back[S] and not r.hand, 'only the sniper left on the back')
frames(40)  -- past 0.75
ok(animLog[2] == 'stop unholster', 'clip lets go: ' .. tostring(animLog[2]))
frames(3)
ok(not disabled[24], 'controls back once done')

-- carbine -> pistol: ox takes the carbine, then gives the pistol a little later
pedWeapon[100] = W.unarmed
TriggerEvent('ox_inventory:currentWeapon', nil)
frames(2)
r = rig(100)
ok(animLog[3] == 'play back@longarms holster', 'long-gun holster clip: ' .. tostring(animLog[3]))
ok(r.hand == C and r.back[S], 'carbine in the hand on its way back')
frames(5)
pedWeapon[100] = W.pistol
visible = true
TriggerEvent('ox_inventory:currentWeapon', { hash = W.pistol, slot = 2 })
ok(visible == false, 'pistol out of sight while the carbine goes away')
frames(45)  -- holster past 0.72
r = rig(100)
ok(animLog[4] == 'stop holster', 'holster lets go: ' .. tostring(animLog[4]))
frames(2)
ok(animLog[5] == 'play rhip unholster', 'pistol draw clip next: ' .. tostring(animLog[5]))
r = rig(100)
ok(r.n == 2 and r.back[C] and r.back[S] and not r.hand, 'carbine on the back again')
frames(10)  -- past 0.14
ok(visible == true, 'pistol in sight at its switch point')
frames(30)
ok(animLog[6] == 'stop unholster', 'pistol clip lets go')

-- ammo update for the same gun: nothing plays
local n = #animLog
TriggerEvent('ox_inventory:currentWeapon', { hash = W.pistol, slot = 2, metadata = { ammo = 3 } })
frames(5)
ok(#animLog == n, 'same gun again (ammo/durability) plays nothing')

-- another player
bags[2].viBack = { w = { W.sniperrifle, W.carbinerifle }, h = W.carbinerifle }
bagChanged('player:2', 'viBack', bags[2].viBack)
r = rig(200)
ok(r.n == 2 and r.hand == C and r.back[S] == 168.0, "other player's guns hung locally, hand included")
bags[2].viBack = { w = { W.pistol } }
bagChanged('player:2', 'viBack', bags[2].viBack)
ok(rig(200).n == 0, 'a pistol in a state bag is refused')
bags[2].viBack = nil
bagChanged('player:2', 'viBack', nil)
frames(20)
ok(rig(200).n == 0, 'cleared bag, nothing hung')

-- row off
options.set('gunsonback', false)
ok(rig(100).n == 0 and myBag.viBack == nil, 'row off: props gone, state bag cleared')
options.set('gunsonback', true)
frames(3)
ok(rig(100).n == 2, 'row on again: back')

-- =========================================================================
print('no ox_inventory')
options = boot(false)
owned[C], owned[S], owned[P] = true, true, true
frames(5)
r = rig(100)
ok(r.n == 2 and r.back[S] and r.back[C], 'ped weapons: sniper and carbine on the back')
-- the game's wheel switches to the carbine
pedWeapon[100] = W.carbinerifle
frame()
ok(u32(pedWeapon[100]) == u32(W.unarmed), 'switch taken back to play the clip')
frames(2)
ok(animLog[1] == 'play back@longarms unholster', 'draw clip: ' .. tostring(animLog[1]))
ok(rig(100).hand == C, 'carbine in the hand during the draw')
frames(10)
ok(u32(pedWeapon[100]) == C, 'carbine selected at the switch point')
frames(45)
-- now to the pistol
pedWeapon[100] = W.pistol
frame()
ok(u32(pedWeapon[100]) == C, 'carbine back in hand for its holster')
frames(2)
ok(animLog[3] == 'play back@longarms holster', 'holster clip: ' .. tostring(animLog[3]))
ok(rig(100).hand == nil, 'real carbine in hand before the switch point')
frames(20)  -- past 0.32
ok(u32(pedWeapon[100]) == u32(W.unarmed) and rig(100).hand == C, 'at the switch: unarmed, carbine prop in the hand')
frames(30)
frames(15)
ok(u32(pedWeapon[100]) == P, 'pistol drawn: ' .. tostring(animLog[5]))
local r2 = rig(100)
ok(r2.n == 2 and r2.back[C] and r2.back[S], 'carbine back on the back')

-- clips not streamed: the switch just happens after 1.5 s
options = boot(false)
owned[C], owned[S], owned[P] = true, true, true
function HasAnimDictLoaded() return false end
frames(3)
pedWeapon[100] = W.pistol
frame()
frames(60)
ok(u32(pedWeapon[100]) == u32(W.unarmed), 'still waiting at 1 s')
frames(40)
ok(u32(pedWeapon[100]) == P, 'given up and switched after 1.5 s')
function HasAnimDictLoaded(d) return dicts[d] == true end

print(('%d/%d passed'):format(total - fails, total))
if fails > 0 then error('failures') end
return fails == 0
