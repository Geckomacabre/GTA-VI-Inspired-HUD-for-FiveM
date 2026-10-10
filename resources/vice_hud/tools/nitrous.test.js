/* Does the nitrous pip follow the nitrous resource, and does the tip only show
 * for a kit that was just fitted?
 *
 *   npm i fengari && node tools/nitrous.test.js
 *
 * Runs the REAL Nitrous section lifted out of client.lua (the `do` block that
 * assigns syncNitrous) with the natives stubbed. Three ways in are covered --
 * the tick's read of the state bag, the bag's change handler, and
 * exports.vice_hud:SetVehicleNitrous -- plus the "Hold [key] to activate
 * nitrous" tip, which is a heuristic and so the part most worth pinning down.
 */
const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const src = fs.readFileSync(__dirname + '/../client.lua', 'utf8').split(/\r?\n/);
const first = src.findIndex(l => l === 'local syncNitrous');
if (first < 0) throw new Error('Nitrous section not found in client.lua');
let last = -1;
for (let i = first + 1; i < src.length; i++) {
  if (src[i] === 'end') { last = i; break; }
}
if (last < 0) throw new Error('could not find the end of the Nitrous section');
// Without its `local`, so the harness can call syncNitrous as a global.
const section = src.slice(first + 1, last + 1).join('\n');

// The real button resolver, so the tip is tested against what it will
// actually be handed.
const glyphs = fs.readFileSync(__dirname + '/../client_glyphs.lua', 'utf8');

const harness = `
Config = { NitrousStateBag = 'customs:nitrous', NitrousHintMs = 7000, NitrousHintHoldBag = 'customs:menuOpen' }
LocalPlayer = { state = {} }
cache = { vehicle = nil }
handler, handlers, exported, pushes, hints, timers = nil, {}, {}, {}, {}, {}
now = 0
local onVehicle
lib = { onCache = function(key, fn) assert(key == 'vehicle') onVehicle = fn end }
function AddStateBagChangeHandler(key, bag, fn)
  assert(bag == nil) handlers[key] = fn
  if key == 'customs:nitrous' then handler = fn end
end
function exports(name, fn) exported[name] = fn end
function RegisterCommand() end
function GetPlayerServerId() return 7 end
function PlayerId() return 0 end
function GetGameTimer() return now end
function SetTimeout(ms, fn) timers[#timers+1] = { at = now + ms, fn = fn } end
function GetHashKey(s) return #s end
onPad = false
function IsInputDisabled() return not onPad end   -- "disabled" is keyboard+mouse
function GetControlInstructionalButton(group, control, _)
  -- A key mapping is group 2 with the top bit set; answer like the native:
  -- an icon index on a pad (34 is LB, 30 is A), the key's own text otherwise.
  if group == 2 and (control & 0x80000000) ~= 0 then return onPad and 'b_34' or 't_LSHIFT' end
  -- 179 is the control a resource that polls the pad separately reports.
  if control == 179 then return onPad and 'b_32' or 't_SPACE' end
  return onPad and 'b_30' or 't_E'
end
function GetResourceKvpString() return nil end
function SetResourceKvp() end
function CreateThread() end
function SendNUIMessage() end

${glyphs}

function resolveKey(key) return ViceGlyphs.control(key) end
function usingPad() return ViceGlyphs.usingPad() end
function ui(action, data)
  data.action = action
  if action == 'nitrousHint' then hints[#hints+1] = data else pushes[#pushes+1] = data end
end
vehShown = false
vehicleNitrous = nil

${section}

KEY = 'customs:nitrous'
function bag(v) LocalPlayer.state[KEY] = v end
function fire(v) bag(v) handler('player:7', KEY, v) end
function enter(veh, t) now = t cache.vehicle = veh if veh then onVehicle(veh) end end
function at(t)
  now = t
  for _, tm in ipairs(timers) do if tm.at <= now and not tm.done then tm.done = true tm.fn() end end
end
function kit(level, more)
  local n = { installed = true, level = level, active = false, ready = true }
  for k, v in pairs(more or {}) do n[k] = v end
  return n
end
`;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code, what) {
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) {
    throw new Error((what || code) + ': ' + lua.lua_tojsstring(L, -1));
  }
}
run(harness, 'harness');

function evalLua(expr) {
  run('__r = ' + expr, expr);
  lua.lua_getglobal(L, to_luastring('__r'));
  const t = lua.lua_type(L, -1);
  let v;
  if (t === lua.LUA_TNUMBER) v = lua.lua_tonumber(L, -1);
  else if (t === lua.LUA_TSTRING) v = lua.lua_tojsstring(L, -1);
  else if (t === lua.LUA_TBOOLEAN) v = lua.lua_toboolean(L, -1);
  else if (t === lua.LUA_TNIL) v = null;
  else v = '<' + t + '>';
  lua.lua_pop(L, 1);
  return v;
}

let failed = 0;
function check(name, cond, got) {
  console.log((cond ? '  ok   ' : '  FAIL ') + name + (cond || got === undefined ? '' : '   -> ' + got));
  if (!cond) failed++;
}
const is = (name, expr, want) => { const got = evalLua(expr); check(name, got === want, got); };

console.log('\n-- the state bag, read by the status tick --');
run('syncNitrous()');
is('unset bag: no kit', 'vehicleNitrous', null);
run("bag(kit(0.75, { kit = 'Race', label = 'Race 150 Shot' })) syncNitrous()");
is('the tick picks up a value that was already there (HUD restart mid-drive)', 'vehicleNitrous.level', 0.75);
is('only the fields the pip reads are carried', 'vehicleNitrous.kit', null);
is('the tick alone pushes nothing', '#pushes', 0);
is('and a kit found on the very first reading is not a fitting: no tip', '#hints', 0);

console.log('\n-- the change handler is the fast path --');
run('fire(kit(0.5, { active = true }))');
is('no push while the vehicle panel is down', '#pushes', 0);
run('vehShown = true fire(kit(0.4, { active = true }))');
is('one push once it is up', '#pushes', 1);
is('as a nitrous message', 'pushes[1].action', 'nitrous');
is('carrying the level', 'pushes[1].level', 0.4);
is('and the boost flag', 'pushes[1].active', true);
is('ui() did not stamp `action` onto the stored table', 'vehicleNitrous.action', null);
run("handler('player:9', KEY, kit(0.1))");
is('a bag belonging to another player is ignored', 'vehicleNitrous.level', 0.4);

console.log('\n-- normalising --');
run('fire(kit(3, { ready = false }))');
is('level clamps high', 'vehicleNitrous.level', 1);
is('lockout is carried', 'vehicleNitrous.ready', false);
run('fire({ installed = true, level = -2 })');
is('level clamps low', 'vehicleNitrous.level', 0);
is('an absent `ready` means ready', 'vehicleNitrous.ready', true);
run('fire({ installed = false, level = 0.0, active = false, ready = false })');
is('installed=false clears it (left the car / no kit)', 'vehicleNitrous', null);
run('fire(nil)');
is('nil clears it', 'vehicleNitrous', null);

console.log('\n-- the tip: only for a kit that was JUST fitted --');
// Get into a car that already has nitrous: the kit is there within a moment
// of the door closing, so it was there before it.
run('enter(101, 10000) at(10300) fire(kit(1, { command = "+nitrous" }))');
is('a car that had nitrous all along: no tip', '#hints', 0);
run('fire({ installed = false }) enter(nil, 12000)');

// Sit in a car, THEN have a kit fitted.
run('enter(202, 20000) at(20200) fire({ installed = false })');
run('at(26000) fire(kit(1, { command = "+nitrous" }))');
is('fitted while sitting in the car: the tip shows', '#hints', 1);
is('for the configured time', 'hints[1].holdMs', 7000);
is('with the LIVE bind of the key mapping, not a control id', 'hints[1].glyph', 'LSHIFT');
is('and the input device', 'hints[1].device', 'kbm');
run('fire(kit(0.9, { command = "+nitrous", active = true }))');
is('the tank moving does not show it again', '#hints', 1);
run('fire({ installed = false })');
is('taking the kit off while the tip is up takes the tip down', 'hints[2] and hints[2].show', false);
run('at(27000) fire(kit(1, { command = "+nitrous" }))');
is('and the same car getting its kit back does not show it again -- once per car', '#hints', 2);

run('enter(303, 40000) at(40100) fire({ installed = false }) at(45000) fire(kit(1, { key = 21 }))');
is('a different car is a different fitting', 'hints[#hints].show', true);
is('a control id is resolved like a prompt key', 'hints[#hints].glyph', 'E');
run('at(60000)');
run('fire({ installed = false })');
is('once the tip has timed out there is nothing to hide', 'hints[#hints].show', true);

console.log('\n-- a kit fitted behind a shop menu: the tip waits for the HUD --');
// The customs shop hides the HUD (SetHudVisible(false)) while its menu is open
// and fits the kit inside it. hudHiddenByExport / onHudShown are the two
// file-level names the SetHudVisible export drives.
run('enter(505, 80000) at(80100) fire({ installed = false })');
run('__before = #hints hudHiddenByExport = true at(86000) fire(kit(1, { command = "+customsnitrous" }))');
is('nothing is shown on a hidden HUD', '#hints - __before', 0);
run('at(99000) hudHiddenByExport = false onHudShown()');
is('it shows when the HUD comes back, however long the menu was open', '#hints - __before', 1);
is('with its full time still to run', 'hints[#hints].holdMs', 7000);
run('onHudShown()');
is('and only once', '#hints - __before', 1);
run('enter(606, 100000) at(100100) fire({ installed = false })');
run('__before = #hints hudHiddenByExport = true at(106000) fire(kit(1)) fire({ installed = false })');
run('hudHiddenByExport = false onHudShown()');
is('a kit taken off again before the menu closes leaves no tip behind', '#hints - __before', 0);

console.log('\n-- a kit fitted inside the shop menu, which leaves the HUD up --');
// The customs shop marks its menu with a state bag instead of hiding the HUD.
run('enter(707, 120000) at(120100) fire({ installed = false })');
run('__before = #hints LocalPlayer.state["customs:menuOpen"] = true at(126000) fire(kit(1, { command = "+customsnitrous" }))');
is('nothing is shown over the open menu', '#hints - __before', 0);
// The handler runs before the bag takes its new value, exactly as in game.
run('at(140000) handlers["customs:menuOpen"]("player:7", "customs:menuOpen", false)');
is('nor in the same tick the menu starts to close', '#hints - __before', 0);
run('LocalPlayer.state["customs:menuOpen"] = false at(140001)');
is('it shows once the menu is shut', '#hints - __before', 1);
is('with its full time still to run', 'hints[#hints].holdMs', 7000);
run('handlers["customs:menuOpen"]("player:9", "customs:menuOpen", false) at(140002)');
is('and another player closing theirs changes nothing', '#hints - __before', 1);

console.log('\n-- the export takes the pip over, and gives it back --');
run('enter(404, 70000)');
run('local n = #pushes exported.SetVehicleNitrous(kit(0.9)) __n = #pushes - n');
is('SetVehicleNitrous stores', 'vehicleNitrous.level', 0.9);
is('and pushes', '__n', 1);
run('fire(kit(0.2)) syncNitrous()');
is('the bag is ignored while the export owns the pip', 'vehicleNitrous.level', 0.9);
run('bag(kit(0.3)) exported.SetVehicleNitrous(nil)');
is('nil hands it back to the bag', 'vehicleNitrous.level', 0.3);
run('bag(nil) exported.SetVehicleNitrous(kit(1)) exported.SetVehicleNitrous(nil)');
is('released with an empty bag: no stale pip', 'vehicleNitrous', null);

console.log('\n-- the tip on demand --');
run('local n = #hints exported.ShowNitrousHint({ key = "X", duration = 3000 }) __h = hints[n + 1]');
is('ShowNitrousHint shows it', '__h.show', true);
is('with the label it was given', '__h.glyph', 'X');
is('for the time it was given', '__h.holdMs', 3000);
run('exported.HideNitrousHint()');
is('HideNitrousHint takes it down', 'hints[#hints].show', false);

console.log('\n-- the tip follows the device in hand --');
run('ViceGlyphs.poll()');
run('exported.ShowNitrousHint({ command = "+nitrous", duration = 5000 }) __n = #hints');
is('on the keyboard it is the key', 'hints[#hints].glyph', 'LSHIFT');
run('onPad = true ViceGlyphs.poll()');
is('picking up the pad re-sends the tip', '#hints - __n', 1);
is('as a refresh, so its clock is not restarted', 'hints[#hints].refresh', true);
is('with the pad button the same command is on', 'hints[#hints].glyph', 'LB');
is('marked as a pad button', 'hints[#hints].device', 'pad');
run('exported.HideNitrousHint() __n = #hints onPad = false ViceGlyphs.poll()');
is('a swap with no tip up sends nothing', '#hints - __n', 0);

console.log('\n-- one control on the keyboard, another on the pad --');
run('onPad = true ViceGlyphs.poll()');
run('enter(909, 300000) at(300100) fire({ installed = false }) at(306000) fire(kit(1, { key = 19, padKey = 179 }))');
is('on a pad the tip shows the control the resource polls on a pad', 'hints[#hints].glyph', 'X');
is('as a pad button', 'hints[#hints].device', 'pad');
run('onPad = false ViceGlyphs.poll()');
is('and the keyboard one when the pad is put down', 'hints[#hints].glyph', 'E');
is('as a key', 'hints[#hints].device', 'kbm');
run('exported.HideNitrousHint()');

console.log(failed ? `\n${failed} check(s) FAILED` : '\nall checks passed');
process.exit(failed ? 1 : 0);
