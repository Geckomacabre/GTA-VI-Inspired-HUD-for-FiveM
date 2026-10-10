/* setRadar() is the single gate between the engine's radar and the page.
 *
 *   npm i fengari && node tools/radarchrome.test.js
 *
 * Two of its four callers sit inside the 250ms poll loop, so the thing worth
 * pinning is that it reports TRANSITIONS, not ticks -- otherwise the page would
 * take a mapRect message four times a second forever. Runs the real setRadar
 * lifted out of client.lua.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client.lua', 'utf8').replace(/\r\n/g, '\n'); // normalise CRLF: client.lua is CRLF on disk, and this file's \n-only string searches below assumed LF

let fails = 0;
const ok = (c, l, e) => c ? console.log('  PASS  ' + l)
  : (console.log('  FAIL  ' + l + (e !== undefined ? '  -> ' + JSON.stringify(e) : '')), fails++);

const a = src.indexOf('local radarShown = nil');
const b = src.indexOf('\nend\n', src.indexOf('local function setRadar')) + 5;
if (a < 0 || b < 5) throw new Error('could not locate setRadar in client.lua');
const chunk = src.slice(a, b) + '\n__test = { setRadar = setRadar }\n';

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const radar = [];   // every DisplayRadar call
const sent = [];    // every ui() push
const told = [];    // every vice_hud:minimap event
const game = { cutscene: false, switching: false, faded: false };
const push = (n, f) => { lua.lua_pushjsfunction(L, f); lua.lua_setglobal(L, to_luastring(n)); };
push('DisplayRadar', (S) => { radar.push(lua.lua_toboolean(S, 1)); return 0; });
push('ui', (S) => {
  const action = lua.lua_tojsstring(S, 1);
  lua.lua_getfield(S, 2, to_luastring('visible'));
  sent.push({ action, visible: lua.lua_toboolean(S, -1) });
  return 0;
});
push('TriggerEvent', (S) => { told.push({ name: lua.lua_tojsstring(S, 1), shown: lua.lua_toboolean(S, 2) }); return 0; });
push('IsCutscenePlaying', (S) => { lua.lua_pushboolean(S, game.cutscene); return 1; });
push('IsPlayerSwitchInProgress', (S) => { lua.lua_pushboolean(S, game.switching); return 1; });
push('IsScreenFadedOut', (S) => { lua.lua_pushboolean(S, game.faded); return 1; });

if (lauxlib.luaL_loadstring(L, to_luastring(chunk)) !== lua.LUA_OK)
  throw new Error('load: ' + lua.lua_tojsstring(L, -1));
if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
  throw new Error('run: ' + lua.lua_tojsstring(L, -1));

function call(on) {
  lua.lua_getglobal(L, to_luastring('__test'));
  lua.lua_getfield(L, -1, to_luastring('setRadar'));
  lua.lua_pushboolean(L, on);
  if (lua.lua_pcall(L, 1, 0, 0) !== lua.LUA_OK)
    throw new Error('setRadar: ' + lua.lua_tojsstring(L, -1));
  lua.lua_pop(L, 1);
}

// First call: the native fires and the page is told, since nil is not false.
call(false);
ok(radar.length === 1 && radar[0] === false, 'the native is called every time');
ok(sent.length === 1 && sent[0].action === 'mapRect' && sent[0].visible === false,
   'the first call reports to the page on the mapRect action', sent);

// The poll loop hammering the same state must not keep pushing.
sent.length = 0;
call(false); call(false); call(false);
ok(radar.length === 4, 'the native still gets every call (it is cheap and idempotent)');
ok(sent.length === 0, 'but an unchanged state pushes nothing', sent);

// A real transition does push, once.
call(true); call(true);
ok(sent.length === 1 && sent[0].visible === true, 'a transition pushes exactly once', sent);

// And back again.
sent.length = 0;
call(false);
ok(sent.length === 1 && sent[0].visible === false, 'and again on the way back', sent);

// Whatever stands beside the map (a speed-limit sign, a seatbelt light) is told
// the same thing the page is, at the same moments and no others.
ok(told.length === 3 && told.every((t) => t.name === 'vice_hud:minimap') && told.map((t) => t.shown).join() === 'false,true,false',
   'vice_hud:minimap is raised once per transition, with the new state', told);

// The game hides its own radar for these three. The drawn map, the frame and
// the panels are not the game's to hide, so setRadar answers for them.
for (const [what, label] of [['cutscene', 'a cutscene'], ['switching', 'a character switch'], ['faded', 'a faded-out screen']]) {
  call(true);
  sent.length = 0; told.length = 0;
  game[what] = true;
  call(true);
  ok(radar[radar.length - 1] === false && sent.length === 1 && sent[0].visible === false && told.length === 1 && told[0].shown === false,
     label + ' takes the map down even though the HUD still wants it', { radar: radar[radar.length - 1], sent, told });
  game[what] = false;
  call(true);
  ok(sent.length === 2 && sent[1].visible === true, 'and it comes back after', sent);
  call(false);
}

// The drawn map standing in: the page still shows a map, the engine's is hidden.
if (lauxlib.luaL_dostring(L, to_luastring('shows = {}; ViceMap3D = { owns = function() return true end, show = function(on) shows[#shows + 1] = on end }')) !== lua.LUA_OK)
  throw new Error(lua.lua_tojsstring(L, -1));
sent.length = 0;
call(true);
lua.lua_getglobal(L, to_luastring('shows')); lua.lua_rawgeti(L, -1, 1);
const drawn = lua.lua_toboolean(L, -1); lua.lua_pop(L, 2);
ok(radar[radar.length - 1] === false && sent[0].visible === true && drawn === true,
   'with the drawn map standing in, the engine\'s radar is hidden and the page still has a map', { radar: radar[radar.length - 1], sent, drawn });
if (lauxlib.luaL_dostring(L, to_luastring('ViceMap3D.owns = function() error("boom") end')) !== lua.LUA_OK)
  throw new Error(lua.lua_tojsstring(L, -1));
call(true);
ok(radar[radar.length - 1] === true, 'and a fault in it puts the engine\'s radar back rather than taking the HUD down');

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
