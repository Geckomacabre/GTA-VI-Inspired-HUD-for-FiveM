/* Loads the three client chunks the way FXServer does, in manifest order.
 *
 *   npm i fengari && node tools/split.test.js
 *
 * client.lua was split on 2026-08-28 because a Lua chunk may hold at most 200
 * top-level locals and it was at 192 -- going over is a PARSE error, so it
 * takes the whole HUD down rather than one feature, and it only shows in the
 * F8 console. This suite is the standing guard for that, and for the seam the
 * split created:
 *
 *   1. every client chunk parses, and none is near the 200 cap;
 *   2. loading them in manifest order actually works (a missing upvalue only
 *      shows up when the chunk RUNS, not when it parses);
 *   3. ViceVitals ends up populated with exactly the surface client.lua calls.
 *
 * Natives are stubbed with a permissive metatable rather than one by one --
 * the point here is load-time integrity, not behaviour. The individual
 * subsystems have their own suites for that.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
let fails = 0;
const ok = (c, l, e) => c ? console.log('  PASS  ' + l)
  : (console.log('  FAIL  ' + l + (e !== undefined ? '  -> ' + JSON.stringify(e) : '')), fails++);

// Manifest order, read from the manifest rather than hardcoded, so adding a
// client file without adding it here cannot silently skip it.
const manifest = fs.readFileSync(root + 'fxmanifest.lua', 'utf8');
const block = manifest.slice(manifest.indexOf('client_scripts'),
                             manifest.indexOf('}', manifest.indexOf('client_scripts')));
const files = [...block.matchAll(/'([\w./]+\.lua)'/g)].map(m => m[1]);
const core_i = files.indexOf('client.lua');
ok(core_i > 0 &&
   files.indexOf('client_vitals.lua') < core_i &&
   files.indexOf('client_overlays.lua') < core_i,
   'manifest loads the split files before client.lua', files);

function topLocals(src) {
  let n = 0, indo = 0;
  for (const raw of src.split('\n')) {
    const t = raw.replace(/\s+$/, '');
    if (t === 'do') { indo++; continue; }
    if (t === 'end' && indo) { indo--; continue; }
    if (indo || !t.startsWith('local ')) continue;
    const fn = /^local\s+function\s+(\w+)/.exec(t);
    if (fn) { n++; continue; }
    const decl = /^local\s+([^=]+)/.exec(t)[1];
    n += decl.split(',').filter(s => /^[A-Za-z_]\w*$/.test(s.trim())).length;
  }
  return n;
}

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

/* Any global that is not defined becomes a no-op function returning nil, and
   any table index on one is another of the same. That covers the ~200 natives
   these files call between them without listing any of them. */
const prelude = `
  local nilf = setmetatable({}, {
    __call = function() return nil end,
    __index = function(t) return t end,
  })
  setmetatable(_G, { __index = function(_, k)
    if k == 'Config' or k == 'cache' or k == 'lib' or k == 'LocalPlayer' then return nil end
    return nilf
  end })
  Config = Config
  cache = setmetatable({}, { __index = function() return nil end })
  lib = setmetatable({}, { __index = function() return function() end end })
  LocalPlayer = { state = setmetatable({}, { __index = function() return nil end }) }
  -- Used as table KEYS by the shared scripts, so nil will not do.
  joaat = function(s) return s end
  GetHashKey = joaat
`;

function load(file, src) {
  const stripped = src.replace(/`[^`]*`/g, '0');   // FXServer hash literals
  const st = lauxlib.luaL_loadbuffer(L, to_luastring(stripped), null, to_luastring('@' + file));
  if (st !== lua.LUA_OK) return 'parse: ' + lua.lua_tojsstring(L, -1);
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) return 'run: ' + lua.lua_tojsstring(L, -1);
  return null;
}

// The shared_scripts load first on the real client too, in manifest order:
// the HUD's config, then targeting's (target/) and honor's (honor/), which
// add their settings to the same Config table.
let err = load('prelude', prelude);
ok(!err, 'harness prelude loads', err);

function listed(dir, out) {
  for (const e of fs.readdirSync(root + dir, { withFileTypes: true })) {
    const rel = (dir ? dir + '/' : '') + e.name;
    if (e.isDirectory()) listed(rel, out); else out.push(rel);
  }
  return out;
}
const everything = listed('', []);
function expand(entry) {
  if (!entry.includes('*')) return [entry];
  const rx = new RegExp('^' + entry.split('**/').map(part =>
    part.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '[^/]*')).join('(?:.*/)?') + '$');
  return everything.filter(f => rx.test(f)).sort();
}
const sharedBlock = manifest.slice(manifest.indexOf('shared_scripts'),
                                   manifest.indexOf('}', manifest.indexOf('shared_scripts')));
const shared = [...sharedBlock.matchAll(/^\s*'([^'@][^']*\.lua)'/gm)].flatMap(m => expand(m[1]));
ok(shared[0] === 'config.lua' && shared.includes('target/config.lua') && shared.includes('honor/config.lua'),
   'the HUD\'s config loads before the two that add to it', shared);
const seen = new Set();
for (const f of shared) {
  if (seen.has(f)) continue;      // a file named outright and again by a glob loads once
  seen.add(f);
  err = load(f, fs.readFileSync(root + f, 'utf8'));
  ok(!err, f + ' loads', err);
}
err = load('keys', `
  for _, k in ipairs({ 'VehiclePanelMs', 'PadGlyphs', 'Commands', 'Input', 'Hooks', 'ConductWatcher',
                       'Debug', 'TargetDebug', 'HonorDebug' }) do
    assert(Config[k] ~= nil, 'Config.' .. k .. ' is missing')
  end`);
ok(!err, 'one Config carries the HUD\'s, targeting\'s and honor\'s settings', err);

for (const f of files) {
  const src = fs.readFileSync(root + f, 'utf8');
  const n = topLocals(src);
  ok(n < 200, f + ' is under Lua\'s 200 top-level locals (' + n + ')', n);
  ok(n < 185, f + ' still has real headroom (' + (200 - n) + ' left)', n);
  const e = load(f, src);
  ok(!e, f + ' loads in manifest order', e);
}

// The seam itself: client.lua calls exactly these, so they must all be there.
lua.lua_getglobal(L, to_luastring('ViceVitals'));
const present = [];
for (const k of ['readStamina', 'readOxygen', 'readNeeds', 'enforceCap',
                 'updateExhaustion', 'focusMeter', 'focusActive']) {
  lua.lua_getfield(L, -1, to_luastring(k));
  if (lua.lua_isfunction(L, -1)) present.push(k);
  lua.lua_pop(L, 1);
}
ok(present.length === 7, 'ViceVitals publishes all seven entry points as functions', present);

// And that client.lua does not call anything ELSE on it.
const core = fs.readFileSync(root + 'client.lua', 'utf8');
const called = [...core.matchAll(/ViceVitals\.(\w+)/g)].map(m => m[1]);
const unknown = called.filter(n => !present.includes(n));
ok(unknown.length === 0, 'client.lua calls nothing ViceVitals does not publish', unknown);

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
