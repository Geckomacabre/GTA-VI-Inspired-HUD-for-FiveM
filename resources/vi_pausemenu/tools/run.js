// node run.js [vi_pausemenu dir] [fengari dir]: check.lua on the mock, in fengari (Lua 5.3; the files use nothing of
// 5.4). By default the resource this folder is in, and vice_hud's fengari.
const fs = require('fs');
const path = require('path');
const res = process.argv[2] || path.join(__dirname, '..');
const fengariDir = process.argv[3] || path.join(__dirname, '..', '..', 'vice_hud', 'node_modules', 'fengari');
const { lua, lauxlib, lualib, to_luastring } = require(fengariDir);

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(name, code) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('@' + name)) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(name + ': ' + lua.lua_tojsstring(L, -1));
  }
}
const file = (p) => fs.readFileSync(p, 'utf8');
run('mock.lua', file(path.join(__dirname, 'mock.lua')));
run('GetCurrentResourceName', "function GetCurrentResourceName() return 'vi_pausemenu' end");
run('shared/config.lua', file(path.join(res, 'shared/config.lua')));
// strict from here: a global nobody defined is an error (but for the natives this build may not name)
run('strict', `local maybe = { IsReplayRecording = true, StartReplayRecording = true, StopReplayRecording = true }
  setmetatable(_G, { __index = function(_, k) if maybe[k] then return nil end error("undefined global " .. tostring(k), 2) end,
  __newindex = function(t, k, v) rawset(t, k, v) end })`);
run('server/main.lua', file(path.join(res, 'server/main.lua')));
run('client/mapsprites.lua', file(path.join(res, 'client/mapsprites.lua')));
run('client/main.lua', file(path.join(res, 'client/main.lua')));
run('check.lua', file(path.join(__dirname, 'check.lua')));
lua.lua_getglobal(L, to_luastring('Result'));
process.exit(lua.lua_tointeger(L, -1) ? 1 : 0);
