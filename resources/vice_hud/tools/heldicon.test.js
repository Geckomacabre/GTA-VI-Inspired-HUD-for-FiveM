/* The icon for something held that is not a weapon (a basketball): which image
 * client.lua picks, from Config.HeldIcons and exports.vice_hud:SetHeldIcon, and
 * that the page hides an image it cannot load.
 *
 *   node tools/heldicon.test.js
 *
 * Not shipped to clients. Runs the real block out of client.lua, the one between
 * its "[held icon]" markers, against a stubbed player state.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const { JSDOM } = require('jsdom');

const root = path.join(__dirname, '..');
let bad = 0;
const ok = (c, m, extra) => { console.log((c ? '  PASS  ' : '  FAIL  ') + m + (c || extra === undefined ? '' : '   -> ' + extra)); if (!c) bad++; };

const src = fs.readFileSync(path.join(root, 'client.lua'), 'utf8').replace(/\r\n/g, '\n');
const a = src.indexOf('-- [held icon]'), b = src.indexOf('-- [/held icon]');
ok(a > 0 && b > a, 'client.lua has the held-icon block');
const block = src.slice(a, b);

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const run = (code) => {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('@t')) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
    throw new Error(lua.lua_tojsstring(L, -1));
};
const get = (expr) => { run('__v = tostring(' + expr + ')'); lua.lua_getglobal(L, to_luastring('__v')); const v = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1); return v; };

run(`
exported = {}
exports = setmetatable({}, { __call = function(_, name, fn) exported[name] = fn end })
LocalPlayer = { state = {} }
Config = {}
` + fs.readFileSync(path.join(root, 'config.lua'), 'utf8').replace(/\r\n/g, '\n').match(/Config\.HeldIcons = \{[\s\S]*?\n\}\n/)[0] + block + `
held = heldIcon
`);

console.log('-- which image --');
ok(get('held()') === 'nil', 'empty hands: no icon');
run('LocalPlayer.state.bbBall = true');
ok(get('held()') === 'nui://ox_inventory/web/images/basketball.png', 'holding the ball: the inventory\'s basketball', get('held()'));
run('LocalPlayer.state.bbBall = false');
ok(get('held()') === 'nil', 'the state going false clears it');
run('exported.SetHeldIcon("nui://x/y.png")');
ok(get('held()') === 'nui://x/y.png', 'a script can set one directly');
run('LocalPlayer.state.bbBall = true');
ok(get('held()') === 'nui://x/y.png', 'which wins over the list');
run('exported.SetHeldIcon(nil)');
ok(get('held()') === 'nui://ox_inventory/web/images/basketball.png', 'and nil hands it back to the list');
run('exported.SetHeldIcon("") LocalPlayer.state.bbBall = nil');
ok(get('held()') === 'nil', 'an empty string is no icon');
run('Config.HeldIcons = nil LocalPlayer.state.bbBall = true');
ok(get('held()') === 'nil', 'no list configured: nothing, and no error');
run('Config.HeldIcons = { { state = "bbBall" }, "junk", { state = "bbBall", icon = "a.png" } }');
ok(get('held()') === 'a.png', 'a malformed entry is skipped, not fatal', get('held()'));

console.log('\n-- where it is used --');
const section = src.slice(src.indexOf('-- ---- weapon + ammo'), src.indexOf('-- ---- money'));
ok(/WEAPON_UNARMED[\s\S]*else\s+--[^\n]*\n\s+local held = heldIcon\(\)/.test(section), 'only when no weapon is out: a weapon in hand always wins');
ok(/ui\('weapon', \{ armed = true, icon = held \}\)/.test(section), 'sent as the weapon icon with no ammo, so the ammo row stays hidden');

console.log('\n-- the page --');
const dom = new JSDOM(fs.readFileSync(path.join(root, 'html', 'index.html'), 'utf8'), { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;
window.fetch = () => Promise.resolve({ json: () => Promise.resolve({}) });
window.GetParentResourceName = () => 'vice_hud';
window.eval(fs.readFileSync(path.join(root, 'html', 'app.js'), 'utf8'));
const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const icon = window.document.getElementById('weapon-icon');
msg({ action: 'weapon', armed: true, icon: 'nui://ox_inventory/web/images/basketball.png' });
ok(!icon.classList.contains('hidden') && /basketball\.png$/.test(icon.getAttribute('src')), 'the icon shows in the weapon slot');
ok(window.document.getElementById('ammo').classList.contains('hidden'), 'with no ammo row beside it');
icon.dispatchEvent(new window.Event('error'));
ok(icon.classList.contains('hidden'), 'an image that will not load is hidden, not left as a broken box');
msg({ action: 'weapon', armed: false });
ok(icon.classList.contains('hidden'), 'and it goes when the hands are empty');

console.log(bad ? '\n' + bad + ' check(s) failed' : '\nall checks passed');
process.exit(bad ? 1 : 0);
