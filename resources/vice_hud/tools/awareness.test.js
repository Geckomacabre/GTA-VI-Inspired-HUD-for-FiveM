/* client_awareness.lua under fengari: the police memory the wanted tells read
 * when fenix-police is not running, and the recent-shot clock. Ported from
 * the single-player GTA6Hud on 2026-10-18.
 *
 *   npm i fengari && node tools/awareness.test.js
 *
 * Runs the shipped file itself (whole, not a slice): natives are stubbed with
 * plain Lua tables the drive scripts below change between calls, and
 * CreateThread is captured rather than run, so only the parts under test
 * execute.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client_awareness.lua', 'utf8');
// FXServer hash literals (`COP`) are not Lua; same stand-in split.test.js uses.
const runnable = src.replace(/`[^`]*`/g, '0');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) console.log('  PASS  ' + label);
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

function run(drive) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const out = [];
  lua.lua_pushjsfunction(L, (S) => {
    const n = lua.lua_gettop(S);
    const parts = [];
    for (let i = 1; i <= n; i++) parts.push(lua.lua_tojsstring(S, i));
    out.push(parts.join('\t'));
    return 0;
  });
  lua.lua_setglobal(L, to_luastring('print'));

  const stubs = `
    Config = {}
    cache = { ped = 1 }
    function PlayerPedId() return 1 end
    function CreateThread() end
    function AddEventHandler() end
    function SendNUIMessage() end
    -- the ped: drawable/texture per component, prop index/texture per prop
    __draw, __tex, __prop, __ptex = {}, {}, {}, {}
    for c = 0, 11 do __draw[c], __tex[c] = 0, 0 end
    for p = 0, 7 do __prop[p], __ptex[p] = -1, -1 end
    __veh, __plate = 0, nil
    function GetPedDrawableVariation(_, c) return __draw[c] end
    function GetPedTextureVariation(_, c) return __tex[c] end
    function GetPedPropIndex(_, p) return __prop[p] end
    function GetPedPropTextureIndex(_, p) return __ptex[p] end
    function GetVehiclePedIsIn() return __veh end
    function GetVehicleNumberPlateText() return __plate end
    function __t(m)
      if not m then return 'nil' end
      return (m.outfit and 'O' or '-') .. (m.face and 'F' or '-') .. (m.vehicle and 'V' or '-')
    end
  `;
  const full = stubs + runnable + drive;
  if (lauxlib.luaL_loadbuffer(L, to_luastring(full), null, to_luastring('@awareness')) !== lua.LUA_OK) {
    throw new Error('load failed: ' + lua.lua_tojsstring(L, -1));
  }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error('run failed: ' + lua.lua_tojsstring(L, -1));
  }
  return out;
}

console.log('\n-- police memory --');
{
  const r = run(`
    print(__t(ViceWantedMemory.tells(1)))                 -- 1 nobody has seen anything
    __draw[11], __veh, __plate = 4, 77, ' ab12cd  '
    ViceWantedMemory.note(1)                               -- seen: jacket 4, face out, car AB12CD
    print(__t(ViceWantedMemory.tells(1)))                 -- 2
    __draw[11] = 5
    print(__t(ViceWantedMemory.tells(1)))                 -- 3 changed jacket
    __draw[11] = 4; __draw[1] = 2
    print(__t(ViceWantedMemory.tells(1)))                 -- 4 masked up
    __draw[1] = 0; __plate = 'ZZ99ZZ'
    print(__t(ViceWantedMemory.tells(1)))                 -- 5 different car
    __veh, __plate = 0, nil
    print(__t(ViceWantedMemory.tells(1)))                 -- 6 on foot
    __veh, __plate = 77, 'AB12CD'
    print(__t(ViceWantedMemory.tells(1)))                 -- 7 back in it
    __veh, __plate = 0, nil
    ViceWantedMemory.note(1)                               -- seen again on foot
    __veh, __plate = 77, 'AB12CD'
    print(__t(ViceWantedMemory.tells(1)))                 -- 8 the car is still remembered
    ViceWantedMemory.clear()
    print(__t(ViceWantedMemory.tells(1)))                 -- 9 wanted level gone
    __draw[1] = 3
    ViceWantedMemory.note(1)                               -- seen only while masked
    __draw[1] = 0
    print(__t(ViceWantedMemory.tells(1)))                 -- 10 unmasking does not light the face
  `);
  ok(r[0] === 'nil', 'nothing is lit before anyone has seen you', r[0]);
  ok(r[1] === 'OFV', 'what a cop saw lights clothes, face and vehicle', r[1]);
  ok(r[2] === '-FV', 'changing clothes clears the clothing tell', r[2]);
  ok(r[3] === 'O-V', 'a mask clears the face tell', r[3]);
  ok(r[4] === 'OF-', 'another car (by plate) is not the one they saw', r[4]);
  ok(r[5] === 'OF-', 'on foot there is no vehicle to match', r[5]);
  ok(r[6] === 'OFV', 'plates match trimmed and case-insensitively', r[6]);
  ok(r[7] === 'OFV', 'a later sighting on foot does not forget the car', r[7]);
  ok(r[8] === 'nil', 'clear() forgets everything', r[8]);
  ok(r[9] === 'O-V', 'a face only ever seen masked is not known (and a mask is not clothing)', r[9]);
}

console.log('\n-- recent shot clock --');
{
  const r = run(`print(type(LastShotAt), tostring(LastShotAt < -1e8))`);
  ok(r[0] === 'number\ttrue', 'LastShotAt starts long ago, so nothing reads as recently fired', r[0]);
}

// Nothing on the page: these globals only pick between the existing tells.
ok(!/SendNUIMessage/.test(src), 'the file sends nothing to the page');

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
