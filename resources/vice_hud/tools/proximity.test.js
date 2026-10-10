/* The merged targeting's walk-up prompts (target/client/target/proximity.lua,
 * Config.Proximity) against stubbed natives and neighbours: what gets a prompt,
 * which key, when it is a list, and when it stands down.
 *
 *   node tools/proximity.test.js
 *
 * Not shipped to clients.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const dir = process.argv[2] || path.join(__dirname, '..', 'target');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const run = (code, name) => {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('@' + (name || 'chunk'))) !== lua.LUA_OK
      || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) throw new Error((name || 'chunk') + ': ' + lua.lua_tojsstring(L, -1));
};
const get = (expr) => { run('__v = tostring(' + expr + ')'); lua.lua_getglobal(L, to_luastring('__v')); const v = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1); return v; };

run(`
log, threads, now, pressed, disabledControls = {}, {}, 0, {}, {}
hud, pad, machineActive, blockedNow, aiming = true, false, false, false, false
local function note(s) log[#log + 1] = s end
local V = {}
V.__index = V
V.__sub = function(a, b) return vec3(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, V) end
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), at = 0 } end
function Wait(ms) coroutine.yield(ms or 0) end
function step(n) for _ = 1, n do now = now + 16
  local i = 1
  while i <= #threads do local t = threads[i]
    if coroutine.status(t.co) == 'suspended' and t.at <= now then
      local ok, w = coroutine.resume(t.co) if not ok then error(w) end t.at = now + (w or 0) end
    i = i + 1 end
  pressed = {} disabledControls = {} end end
function GetGameTimer() return now end
function GetCurrentResourceName() return 'osm-target' end
function GetResourceState(r) return (r == 'vice_hud' and hud) and 'started' or 'missing' end
function AddEventHandler() end
function GetFinalRenderedCamCoord() return vec3(0.0, -1.0, 1.0) end
function GetFinalRenderedCamRot() return { x = 0.0, y = 0.0, z = 0.0 } end   -- looking along +y
function GetEntityCoords() return vec3(0.0, 0.0, 0.0) end
function GetAspectRatio() return 1.7778 end
function IsPlayerFreeAiming() return aiming end
function DisableControlAction(_, c) disabledControls[c] = true blockedSeen = blockedSeen or {} blockedSeen[c] = true end
function Locale(k) return k == 'interact' and 'Interact' or k end
cache = { ped = 1, playerId = 0, vehicle = false }
exports = setmetatable({}, { __index = function(_, res) return setmetatable({}, { __index = function(_, fn)
  return function(_, a, b, c)
    if fn == 'ShowWorldActions' then
      local rows = {}
      for i, o in ipairs(a) do rows[i] = o.label .. '=' .. tostring(o.key) .. (o.more and '+more' or '') .. (o.dot and '+dot' or '') end
      shownAt = b
      note('show[' .. table.concat(rows, ', ') .. ']' .. ((c and c.compact == false) and ' full' or '') .. ((c and c.centred) and ' centred' or ''))
    elseif fn == 'SetWorldActionsCoords' then movedTo = a note('move')
    else note(fn) end
  end end }) end })

Config = {
  Proximity = {
    enabled = true, distance = 2.0, angle = 30.0, interval = 150, idleInterval = 150, cooldown = 600,
    peds = false, vehicles = 'named', inVehicle = false, maxDirect = 1,
    keys = { { kbm = { 51 }, pad = { 204 } }, { kbm = { 47 }, pad = { 203 } }, { kbm = { 74 }, pad = { 194 } } },
    blocks = { [204] = { 23, 75 }, [203] = { 22 }, [47] = { 58 } },
  },
  Input = { directKeyByName = { ['keys:slimjim'] = { kbm = { 51 }, pad = { 204 } }, ['keys:smash'] = { kbm = { 47 }, pad = { 194 } } } },
  Render = { menuSize = 0.4, referenceDistance = 2.5 },
}
Appearance = { tunables = {}, prefs = {}, anchor = { x = 0.0, y = 0.0 } }

-- The world: what the crosshair is on, the zones round it, the points about.
world = { scan = nil, zones = {}, points = {}, options = {} }
local function opt(o) return { option = o, enabled = o.enabled ~= false, focusable = true, label = o.label } end
Hit = {}
function Hit.scan() Wait(0) return world.scan or { entity = 0, entityType = 0, coords = vec3(0.0, 9.0, 1.0), distance = 9.0 } end
function Hit.resolve(target)
  local list = {}
  for _, o in ipairs(world.options[target.zone and ('zone:' .. target.zone.id) or target.entity] or {}) do list[#list + 1] = opt(o) end
  return list
end
function Hit.parts(_, list) return { { key = 'p', entries = list } } end
function Hit.anchor(target) return target.coords end
function Hit.scaleFor() return 1.0 end
Store = { zonesContaining = function() return world.zones end }
Discovery = { run = function(force, always) ranAlways = always return world.points end }
Input = {}
function Input.usingPad() return pad end
function Input.controlsFor(e) return pad and e.pad or e.kbm end
function Input.entryPressed(e) for _, c in ipairs(Input.controlsFor(e)) do if pressed[c] then return true end end return false end
function Input.keyLabel(e) return 'K' .. Input.controlsFor(e)[1] end
function Input.syncPrompts() end
Machine = {}
function Machine.isActive() return machineActive end
function Machine.isDisabled() return false end
function Machine.blocked() return blockedNow end
function Machine.open(c, menu) note('open(' .. tostring(c.key) .. ',' .. tostring(menu) .. ')') return true end
function Machine.execute(c, entry) note('run(' .. entry.option.label .. ')') return true end
Surfaces = {}
function Surfaces.init() end
function Surfaces.send(name, action, data)
  if action == 'menu:open' then
    local rows = {}
    for i, o in ipairs(data.options) do rows[i] = o.label .. '=' .. o.directKey end
    note('own[' .. table.concat(rows, ', ') .. '] ' .. data.mode)
  else note(action) end
end
function Surfaces.drawWorld(name) drawn = (drawn or 0) + 1 end
`, 'stubs');
run(fs.readFileSync(path.join(dir, 'client/target/proximity.lua'), 'utf8').replace(/^﻿/, ''), 'proximity.lua');

let bad = 0;
const ok = (c, m, extra) => { console.log((c ? '  ok   ' : '  FAIL ') + m + (c || extra === undefined ? '' : '   -> ' + extra)); if (!c) bad++; };
const log = () => get('table.concat(log, " > ")');
const reset = (extra) => run('log = {} ' + (extra || ''));
const settle = 'step(40)';
// An object 1.5 m ahead under the crosshair.
const thing = (id, type, d) => `world.scan = { entity = ${id}, entityType = ${type}, coords = vec3(0.0, ${d}, 1.0), distance = ${d} }`;

run('Proximity.start() ' + settle);
ok(log() === '' && get('Proximity.isShowing()') === 'false', 'nothing near: nothing on screen', log());
ok(get('ranAlways') === 'true', 'the points are looked for whether or not markers are drawn');

console.log('\n-- walking up to a prop --');
reset(`world.options[10] = { { label = 'Bag', name = 'bag' } } ${thing(10, 3, 3.0)} ${settle}`);
ok(log() === '', 'three metres off: still nothing', log());
reset(`${thing(10, 3, 1.5)} ${settle}`);
ok(log() === 'show[Bag=51] full centred', 'in reach: its option, on E, with the name kept and the button on the prop', log());
ok(get('shownAt.y') === '1.5', 'drawn at the prop');
reset(`${thing(10, 3, 1.4)} ${settle}`);
ok(log() === 'move', 'the same prompt is moved, not rebuilt, when its point shifts', log());
reset(`${thing(10, 3, 3.0)} ${settle}`);
ok(log() === 'HideWorldActions', 'walking away takes it down', log());

console.log('\n-- using it --');
reset(`${thing(10, 3, 1.5)} ${settle} pressed[51] = true step(1)`);
ok(log() === 'show[Bag=51] full centred > HideWorldActions > run(Bag)', 'E runs it and the prompt goes', log());
reset('step(20)');
ok(log() === '', 'and stays away for a moment, so one press is one use', log());
reset('step(40)');
ok(log() === 'show[Bag=51] full centred', 'then comes back if you are still there', log());

console.log('\n-- several options --');
reset(`world.options[10] = { { label = 'Open', name = 'a' }, { label = 'Lock', name = 'b' } } ${settle}`);
ok(log() === 'show[Interact=51+more] full centred', 'two options: one button, the three dots, one name', log());
reset('pressed[51] = true step(1)');
ok(/open\(10:p,nil\)$/.test(log()), 'and the button opens the list on that target', log());
reset(`world.options[10][2].targetName = 'Fridge' step(80)`);
ok(log() === 'show[Fridge=51+more] full centred', 'the list is named after the thing when an option says what it is', log());
reset(`world.options[10][3] = { label = 'Knock', name = 'c' } Config.Proximity.maxDirect = 3 world.options[10][2].targetName = nil step(80)`);
ok(log() === 'show[Open=51, Lock=47, Knock=74] full centred', 'with maxDirect raised they stand side by side: E, G, H', log());
reset('pressed[47] = true step(1)');
ok(/run\(Lock\)$/.test(log()), 'each key running its own', log());
run('Config.Proximity.maxDirect = 1 step(80)');
reset(`world.options[10] = { { label = 'Fridge', name = 'fridge', openMenu = 'fridge' } } step(80)`);
ok(log() === 'show[Fridge=51+more] full centred', 'an option that is a submenu keeps its name and carries the mark', log());
reset('pressed[51] = true step(1)');
ok(/open\(10:p,fridge\)$/.test(log()), 'and opens straight into it', log());
reset(`world.options[10] = { { label = 'Use', name = 'u' }, { label = 'Needs a key', name = 'k', enabled = false }, { label = 'Staff only', name = 's', proximity = false } } step(80)`);
ok(log() === 'show[Use=51] full centred', 'what cannot be used, and what asked to stay behind the key, is left out', log());
reset(`world.options[10] = { { label = 'Shorts', name = 's', dot = true } } step(80)`);
ok(log() === 'show[Shorts=51+dot] full centred', 'an option can carry the for-sale dot', log());

console.log('\n-- peds and vehicles --');
reset(`world.options[20] = { { label = 'Greet', name = 'greet' } } ${thing(20, 1, 1.2)} step(80)`);
ok(log() === 'HideWorldActions', 'a ped under the crosshair gets no prompt: that is what the key is for', log());
reset(`world.options[20][2] = { label = 'Clerk', name = 'clerk', proximity = true } step(80)`);
ok(log() === 'show[Clerk=51] full centred', 'unless one of its options asks to be shown', log());
reset(`world.options[30] = { { label = 'Toggle door', name = 'door' }, { label = 'Slim Jim', name = 'keys:slimjim' }, { label = 'Smash Window', name = 'keys:smash' } } ${thing(30, 2, 1.2)} step(80)`);
ok(log() === 'show[Slim Jim=51, Smash Window=47] full centred', 'a vehicle shows only its named options, side by side on their own keys', log());
reset('Config.Proximity.vehicles = false step(80)');
ok(log() === 'HideWorldActions', 'or nothing at all', log());
reset('Config.Proximity.vehicles = "all" step(80)');
ok(log() === 'show[Interact=51+more] full centred', 'or everything, which with an unnamed one among them is a list', log());
run('Config.Proximity.vehicles = "named"');

console.log('\n-- a controller --');
reset('pad = true step(80)');
ok(log() === 'show[Slim Jim=204, Smash Window=194] full centred', 'picking up a pad redraws it with the pad buttons', log());
run('blockedSeen = {} step(3)');
ok(get('blockedSeen[23]') === 'true' && get('blockedSeen[22]') === 'nil', 'while Y is a prompt it does not also get you in the car; buttons not on screen are left alone');
reset(`${thing(10, 3, 1.5)} world.options[10] = { { label = 'Bag', name = 'bag' } } step(80)`);
ok(log() === 'show[Bag=204] full centred', 'the first key on a pad is Y / Triangle', log());
run('pad = false step(80)');

console.log('\n-- points near the middle of the view --');
reset(`world.scan = nil world.options[40] = { { label = 'Turn on', name = 'sw' } } world.points = { { kind = 'entity', entity = 40, entityType = 3, coords = vec3(0.3, 0.6, 1.0), distance = 1.6 } } step(80)`);
ok(log() === 'show[Turn on=51] full centred', 'not looked at exactly, but close and in front: it gets its prompt', log());
reset('world.points[1].coords = vec3(3.0, 0.2, 1.0) step(80)');
ok(log() === 'HideWorldActions', 'off to the side it does not', log());
reset(`world.points = {} world.zones = { { id = 7, coords = vec3(0.0, 1.0, 1.0) } } world.options['zone:7'] = { { label = 'Sit', name = 'sit' } } step(80)`);
ok(log() === 'show[Sit=51] full centred', 'a zone the crosshair is in works the same way', log());

console.log('\n-- standing down --');
reset('machineActive = true step(40)');
ok(log() === 'HideWorldActions', 'the targeting key takes over', log());
reset('machineActive = false step(40) blockedNow = true step(40)');
ok(log() === 'show[Sit=51] full centred > HideWorldActions', 'a menu, the pause screen or being dead hides it', log());
reset('blockedNow = false cache.vehicle = 99 step(40)');
ok(log() === '', 'nothing while driving', log());
reset('cache.vehicle = false aiming = true step(40)');
ok(log() === '', 'nor while aiming', log());
run('aiming = false step(40)');

console.log('\n-- without vice_hud --');
reset('hud = false drawn = 0 step(40)');
ok(/^HideWorldActions > own\[Sit=K51\] direct$/.test(log()) && Number(get('drawn')) > 5, 'the design draws it itself, as a direct prompt, every frame', log() + ' drawn ' + get('drawn'));
reset('pressed[51] = true step(1)');
ok(log() === 'menu:close > run(Sit)', 'and the key still runs it', log());
run('Proximity.stop() step(5)');
ok(get('Proximity.isShowing()') === 'false', 'stopping takes everything down');

console.log(bad ? '\n' + bad + ' check(s) failed' : '\nall checks passed');
process.exit(bad ? 1 : 0);
