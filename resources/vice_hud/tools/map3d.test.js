/* The drawn minimap (Config.Map3D): when it stands in for the engine's radar,
 * what client_map3d.lua feeds the page, what the page does before it has been
 * asked for anything, and that tools/map3d/build.py turns a map in the mod's
 * format into the file the page reads.
 *
 *   node tools/map3d.test.js
 *
 * Not shipped to clients. Runs the real client_map3d.lua against stubbed
 * natives, the real html/map3d.js in jsdom (which has no WebGL, so this is the
 * "cannot draw" path), and the real build.py on a three-building map made up
 * here. The last part is skipped, and says so, on a machine without Python or
 * the three libraries build.py uses.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');
const { JSDOM } = require('jsdom');

const root = path.join(__dirname, '..');
let bad = 0;
const ok = (c, m, extra) => { console.log((c ? '  PASS  ' : '  FAIL  ') + m + (c || extra === undefined ? '' : '   -> ' + extra)); if (!c) bad++; };
const read = (f) => fs.readFileSync(path.join(root, f), 'utf8').replace(/\r\n/g, '\n');

/* ---- the game side ------------------------------------------------------ */
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const run = (code) => {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('@t')) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK)
    throw new Error(lua.lua_tojsstring(L, -1));
};
const get = (expr) => { run('__v = tostring(' + expr + ')'); lua.lua_getglobal(L, to_luastring('__v')); const v = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1); return v; };

const STUBS = `
sent, printed, kvp, cbs, cmds, threads = {}, {}, {}, {}, {}, {}
interior, waypoint, speed = 0, false, 0.0
function SendNUIMessage(d) sent[#sent + 1] = d end
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
function RegisterNUICallback(n, f) cbs[n] = f end
function RegisterCommand(n, f) cmds[n] = f end
function CreateThread(f) threads[#threads + 1] = coroutine.create(f) end
function Wait(ms) coroutine.yield(ms) end
exports = setmetatable({}, { __call = function() end })
print = function(s) printed[#printed + 1] = s end
function PlayerPedId() return 1 end
function GetInteriorFromEntity() return interior end
function GetVehiclePedIsIn() return 0 end
function GetEntityCoords() return { x = 10.0, y = 20.0, z = 30.0 } end
function GetFinalRenderedCamRot() return { x = 0.0, y = 0.0, z = 45.0 } end
function GetEntityHeading() return 90.0 end
function GetEntitySpeed() return speed end
function IsWaypointActive() return waypoint end
function GetHudColour(i) return i, 2, 3, 255 end
-- A road running north for 120 m, a 300 m gap, then 40 m more.
function GetPosAlongGpsTypeRoute(fromPlayer, d, slot)
    if slot ~= 0 then return false, nil end
    if d <= 120.0 then return true, { x = 0.0, y = d, z = 0.0 } end
    if d <= 160.0 then return true, { x = 0.0, y = d + 300.0, z = 0.0 } end
    return true, { x = 0.0, y = 460.0, z = 0.0 }
end
blipsBySprite, blipInfo, cursor = {}, {}, {}
function GetMainPlayerBlipId() return 99 end
function GetFirstBlipInfoId(s) cursor[s] = 1; return (blipsBySprite[s] or {})[1] or 0 end
function GetNextBlipInfoId(s) cursor[s] = cursor[s] + 1; return (blipsBySprite[s] or {})[cursor[s]] or 0 end
function DoesBlipExist(b) return blipInfo[b] ~= nil end
function GetBlipAlpha(b) return blipInfo[b].alpha or 255 end
function GetBlipInfoIdDisplay(b) return blipInfo[b].display or 2 end
function GetBlipInfoIdType(b) return blipInfo[b].kind or 4 end
function GetBlipInfoIdCoord(b) return { x = blipInfo[b].x or 0.0, y = blipInfo[b].y or 0.0, z = 0.0 } end
function GetBlipHudColour(b) return blipInfo[b].colour or 0 end
function IsBlipShortRange(b) return blipInfo[b].short == true end
function GetBlipRotation(b) return blipInfo[b].rot or 0 end
function DoesBlipHaveGpsRoute(b) return blipInfo[b].route == true end
function last(action) for i = #sent, 1, -1 do if sent[i].action == action then return sent[i] end end end
function count(action) local n = 0 for i = 1, #sent do if sent[i].action == action then n = n + 1 end end return n end
-- Run thread i until it has slept n times.
function step(i, n) for _ = 1, n or 1 do if coroutine.status(threads[i]) == 'dead' then return end local okay, err = coroutine.resume(threads[i]) if not okay then error(err) end end end
`;
const fresh = (config, before) => run(STUBS + (before || '') + '\nConfig = { Map3D = ' + config + ' }\n' + read('client_map3d.lua'));

console.log('-- who draws the map --');
fresh('{ enabled = true, view = { zoom = 3 }, paint = { land = { 1, 2, 3 } } }');
ok(get('ViceMap3D.owns()') === 'false', 'not before the page has said anything');
run('ViceMap3D.show(true, true)');
ok(get('last("map3d").show') === 'false' && get('last("map3d").config.view.zoom') === '3', 'the page is told "not yet", and given the config once');
run('cbs.map3dHello({}, function() end)');
ok(get('last("map3d").load') === 'true', 'the page saying hello is answered with "fetch the world"');
ok(get('ViceMap3D.owns()') === 'false', 'still the engine\'s radar while it loads');
run('cbs.map3dReady({ ok = true }, function() end)');
ok(get('ViceMap3D.owns()') === 'true', 'the drawn map takes over once the world is in');
run('ViceMap3D.show(true, true)');
ok(get('last("map3d").show') === 'true', 'and the page is told to draw');
ok(get('last("map3d").config.view.north') === 'true' && get('last("map3d").config.view.buildings') === 'true' && get('last("map3d").config.paint.land[3]') === '3', 'with the view, the north badge, buildings and colours');
run('n = #sent; ViceMap3D.show(true, true)');
ok(get('#sent - n') === '0', 'saying the same thing again sends nothing');
run('ViceMap3D.show(true, false)');
ok(get('last("map3d").config.view.north') === 'false', 'the north toggle is passed on when it changes');
run('ViceMap3D.show(false, false)');
ok(get('last("map3d").show') === 'false', 'no minimap wanted: the drawn one goes too');

console.log('\n-- indoors --');
run('interior = 77; ViceMap3D.show(true, false)');
ok(get('ViceMap3D.owns()') === 'false' && get('last("map3d").show') === 'false', 'inside an interior the engine\'s floor plan is the map');
run('interior = 0; ViceMap3D.show(true, false)');
ok(get('ViceMap3D.owns()') === 'true' && get('last("map3d").show') === 'true', 'and back outside it is drawn again');
fresh('{ enabled = true, engineIndoors = false }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) interior = 77');
ok(get('ViceMap3D.owns()') === 'true', 'engineIndoors = false keeps the drawn map indoors');

console.log('\n-- off, and unavailable --');
fresh('{ enabled = false }');
run('cbs.map3dHello({}, function() end)');
ok(get('count("map3d")') === '0', 'switched off in the config: the page is not asked to fetch anything');
run('cmds.hudmap3d()');
ok(get('kvp["vice_hud:map3d"]') === 'on' && get('last("map3d").load') === 'true', '/hudmap3d switches it on for this player, remembers, and fetches');
run('cbs.map3dReady({ ok = false, why = "map3d/world.bin is not there" }, function() end)');
ok(get('ViceMap3D.owns()') === 'false' && /world\.bin is not there/.test(get('printed[#printed]')), 'no world built: the engine\'s radar stays, and the console says why');
fresh('{ enabled = true }', 'kvp["vice_hud:map3d"] = "off"');
run('cbs.map3dHello({}, function() end)');
ok(get('count("map3d")') === '0' && get('ViceMap3D.owns()') === 'false', 'a player who chose the game radar keeps it across restarts');

console.log('\n-- what the page is fed --');
fresh('{ enabled = true }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) ViceMap3D.show(true, true)');
run('step(1, 1)');
ok(get('last("map3dPos").x') === '10.0' && get('last("map3dPos").c') === '45.0' && get('last("map3dPos").h') === '90.0', 'position, camera heading and facing');
ok(get('last("map3dPos").s') === '0.0', 'on foot the speed is zero: walking does not pull the view back');
run('n = count("map3dPos"); step(1, 5)');
ok(get('count("map3dPos") - n') === '0', 'standing still sends nothing more');

run('waypoint = true; step(2, 40)');
ok(get('#last("map3dRoute").routes') === '2', 'the GPS line, split where the route jumps', get('#last("map3dRoute").routes'));
ok(get('last("map3dRoute").routes[1].pts[2]') === '0.0' && get('last("map3dRoute").routes[1].pts[#last("map3dRoute").routes[1].pts]') === '118.0', 'the first run is the road up to the gap', get('last("map3dRoute").routes[1].pts[#last("map3dRoute").routes[1].pts]'));
ok(get('last("map3dRoute").routes[1].rgb[1]') === '142' && get('last("map3dRoute").routes[1].rim[1]') === '150', 'in the waypoint\'s own colours, which the HUD has already repainted');
run('waypoint = false; step(2, 3)');
ok(get('#last("map3dRoute").routes') === '0', 'and it is cleared when the waypoint goes');

run(`
blipsBySprite = { [1] = { 11, 12, 99 }, [8] = { 13 }, [9] = { 14 }, [52] = { 15, 16, 17 } }
blipInfo = {
    [11] = { kind = 2, x = 5.0, y = 6.0 },                 -- on a ped: follows it
    [12] = { kind = 4, x = 1.0, y = 2.0, short = true, colour = 3 },
    [99] = { kind = 2 },                                   -- the player's own
    [13] = { kind = 4, x = 100.0, y = 200.0, route = true, colour = 5 },
    [14] = { kind = 7 },                                   -- a radius circle
    [15] = { kind = 4, display = 3 },                      -- pause map only
    [16] = { kind = 4, alpha = 0 },                        -- invisible
    [17] = { kind = 4, rot = 90 },
}
step(3, 8)
`);
ok(get('#last("map3dBlips").list') === '3', 'blips: the three that belong on a minimap', get('#last("map3dBlips").list'));
ok(get('last("map3dBlips").list[1][3]') === '1' && get('last("map3dBlips").list[1][8]') === '0' && get('last("map3dBlips").list[1][4]') === '3', 'a short-range blip is not pinned to the edge, and carries its colour');
ok(get('last("map3dBlips").list[2][3]') === '8' && get('last("map3dBlips").list[2][8]') === '1', 'the waypoint is, so it stays in sight');
ok(get('last("map3dBlips").list[3][8]') === '3' && get('last("map3dBlips").list[3][9]') === '90', 'a turned blip says so');
run('step(4, 2)');
ok(get('#last("map3dMoving").list') === '1' && get('last("map3dMoving").list[1][1]') === '5.0', 'a blip on a ped is followed separately, and the player\'s own is left out');

console.log('\n-- client.lua --');
const client = read('client.lua');
const setRadar = client.slice(client.indexOf('local function setRadar(on)'), client.indexOf('-- DISPLAY_RADAR is a single global flag'));
ok(/local drawn = on and ViceMap3D ~= nil and ViceMap3D\.owns\(\)/.test(setRadar), 'setRadar asks who is drawing');
ok(/local engine = on and not drawn\s+radarWanted = engine\s+DisplayRadar\(engine\)/.test(setRadar), 'the engine\'s radar is shown only when the drawn one is not, and held to that');
ok(/ui\('mapRect', \{ visible = on \}\)/.test(setRadar), 'the frame and badge still follow the HUD\'s own decision');
const manifest = read('fxmanifest.lua');
ok(manifest.indexOf("'client_map3d.lua'") > 0 && manifest.indexOf("'client_map3d.lua'") < manifest.indexOf("'client.lua'"), 'client_map3d.lua loads before client.lua');
ok(/'html\/map3d\.js'/.test(manifest) && /'html\/map3d\/\*\.bin'/.test(manifest), 'the manifest ships the script and whatever world has been built');

/* ---- the page ----------------------------------------------------------- */
console.log('\n-- the page --');
const dom = new JSDOM(read('html/index.html'), { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;
const posts = [], fetched = [];
window.fetch = (url, opt) => {
  if (opt && opt.method === 'POST') posts.push({ name: String(url).split('/').pop(), body: JSON.parse(opt.body || '{}') });
  else fetched.push(String(url));
  return Promise.resolve({ ok: false, json: () => Promise.resolve({}), arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)) });
};
window.GetParentResourceName = () => 'vice_hud';
window.eval(read('html/app.js'));
window.eval(read('html/map3d.js'));
const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const canvas = window.document.getElementById('map3d');
ok(!!canvas && canvas.classList.contains('hidden'), 'the canvas is in the page, hidden');
ok(posts.some((p) => p.name === 'map3dHello'), 'the page says hello');
ok(window.ViceMap3D.state().booted === false && fetched.length === 0, 'and has fetched nothing and made no WebGL context');
msg({ action: 'map3dPos', x: 1, y: 2, c: 0, h: 0, s: 0 });
msg({ action: 'map3dRoute', routes: [{ pts: [0, 0, 0, 50], rgb: [1, 2, 3] }] });
msg({ action: 'map3dBlips', list: [[1, 2, 1, 255, 255, 255, 255, 0, 0]] });
msg({ action: 'map3dMoving', list: [[3, 4, 1, 255, 255, 255, 255, 0, 0]] });
ok(window.ViceMap3D.state().booted === false && window.ViceMap3D.state().blips === 2, 'being fed before being asked to draw is harmless');
msg({ action: 'map3d', load: true, config: { view: { zoom: 4.5 }, paint: { land: [9, 9, 9] } } });
ok(window.ViceMap3D.VIEW.zoom === 4.5 && window.ViceMap3D.PAINT.land[0] === 9 && window.ViceMap3D.VIEW.tilt === 0.8, 'config is laid over the defaults, not in place of them');
const ready = posts.find((p) => p.name === 'map3dReady');
ok(ready && ready.body.ok === false && /WebGL2/.test(ready.body.why), 'a browser that cannot draw it says so, and why', JSON.stringify(ready));
msg({ action: 'map3d', show: true });
ok(canvas.classList.contains('hidden'), 'and the canvas stays hidden rather than sitting empty over the radar');
const css = read('html/style.css');
const rule = css.slice(css.indexOf('\n#map3d {'), css.indexOf('}', css.indexOf('\n#map3d {')));
ok(/height:\s*calc\(var\(--map-height[^;]*\* 1\.2\)/.test(rule) && /--m3d:[^;]*\* 0\.1\)/.test(rule) && /OVERHANG = 0\.1;/.test(read('html/map3d.js')), 'the canvas overhangs the frame by the tenth the script expects');

/* ---- the converter ------------------------------------------------------ */
console.log('\n-- tools/map3d/build.py --');
(function () {
  const py = ['python', 'python3'].find((p) => spawnSync(p, ['-c', 'import numpy, scipy, PIL'], { stdio: 'ignore' }).status === 0);
  if (!py) { console.log('  SKIP  no Python with numpy, scipy and Pillow here'); return; }

  // A map in the mod's format: 512 m square, three square buildings in layer 0,
  // one road triangle in layer 2, and a survey with one tile of sea.
  const f32 = (...v) => Buffer.from(new Float32Array(v).buffer);
  const i32 = (...v) => Buffer.from(new Int32Array(v).buffer);
  const u32 = (...v) => Buffer.from(new Uint32Array(v).buffer);
  const squares = [[20, 20], [300, 40], [300, 300]], side = 10;
  const xy = [], tri = [], owner = [], pts = [], rings = [];
  squares.forEach(([x, y], b) => {
    const c = [[x, y], [x + side, y], [x + side, y + side], [x, y + side]];
    const base = xy.length / 2;
    [c[0], c[1], c[2], c[0], c[2], c[3]].forEach((p) => xy.push(p[0], p[1]));
    tri.push(base, base + 1, base + 2, base + 3, base + 4, base + 5);
    owner.push(b, b);
    rings.push(b, pts.length / 2, 4);
    c.forEach((p) => pts.push(p[0], p[1]));
  });
  const layer = (id, v, t) => Buffer.concat([Buffer.from([id]), i32(v.length / 2, t.length / 3), f32(...v), i32(...t)]);
  const head = Buffer.concat([Buffer.from('MMV1'), f32(0, 0, 512, 512), i32(2), layer(0, xy, tri), layer(2, [0, 100, 512, 100, 256, 110], [0, 1, 2])]);
  const bld = Buffer.concat([Buffer.from('BLD1'), u32(3), f32(5, 12, 40), u32(tri.length / 3), u32(...owner),
    u32(pts.length / 2), f32(...pts), u32(rings.length / 3), u32(...rings)]);
  const tile = Buffer.alloc(1024, 2);                       // all water
  const wat = Buffer.concat([Buffer.from('MMW4'), i32(0, 1), i32(0), tile]);
  const body = Buffer.concat([head, bld]);
  const map = Buffer.concat([body, Buffer.from('WAT1'), i32(wat.length), wat, i32(body.length), Buffer.from('WEND')]);

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'map3d-'));
  const src = path.join(dir, 'MiniMap.Data');
  // Inside something else, gzipped, the way it sits in the mod's DLL.
  fs.writeFileSync(src, Buffer.concat([Buffer.from('not the map'), require('zlib').gzipSync(map), Buffer.from('trailing')]));
  const res = spawnSync(py, [path.join(root, 'tools', 'map3d', 'build.py'), '--mod', src, '--out', dir], { encoding: 'utf8' });
  ok(res.status === 0, 'runs on a map found inside another file', (res.stderr || '').slice(-300));
  if (res.status !== 0) return;

  const buf = fs.readFileSync(path.join(dir, 'world.bin'));
  ok(buf.slice(0, 4).toString() === 'VHM1', 'world.bin starts with its name');
  const headLen = buf.readUInt32LE(4), h = JSON.parse(buf.slice(8, 8 + headLen).toString()), base = 8 + headLen;
  const f = (r) => new Float32Array(buf.buffer.slice(buf.byteOffset + base + r.at, buf.byteOffset + base + r.at + r.n * 4));
  const u = (r) => new Uint32Array(buf.buffer.slice(buf.byteOffset + base + r.at, buf.byteOffset + base + r.at + r.n * 4));
  ok(headLen % 4 === 0 && h.gw === 2 && h.gh === 2 && h.chunk === 256, 'a 512 m map is four 256 m squares');
  ok(h.buildings.count === 3 && h.layers.footprint && h.layers.road && !h.layers.rail, 'three buildings, and only the layers the map had');
  const verts = f(h.buildings.verts), roof = u(h.buildings.roof), roofStarts = u(h.buildings.roofStarts), wall = u(h.buildings.wall), wallStarts = u(h.buildings.wallStarts);
  ok(verts.length === (18 + 48) * 5 && roof.length === 18 && wall.length === 72, 'two roof triangles and four walls each', verts.length + ' ' + roof.length + ' ' + wall.length);
  ok(Array.from(roofStarts).join() === '0,6,12,12,18' && Array.from(wallStarts).join() === '0,24,48,48,72', 'sorted into the squares they stand in', Array.from(roofStarts).join());
  const v = (i) => Array.from(verts.slice(i * 5, i * 5 + 5));
  ok(v(roof[0])[2] === 5 && v(roof[0])[3] === 9 && v(roof[0])[4] === 0 && v(roof[12])[2] === 40 && v(roof[12])[4] === 2, 'a roof carries its height and its building');
  // A wall is six indices; the south wall of the first building is the one
  // whose every corner is on y = 20.
  const quads = [];
  for (let i = 0; i < wall.length; i += 6) quads.push(Array.from(wall.slice(i, i + 6), v));
  const south = quads.filter((q) => q.every((p) => p[4] === 0 && p[1] === 20))[0];
  ok(south && south.every((p) => Math.abs(p[3] + Math.PI / 2) < 1e-5) && south.some((p) => p[2] === 0) && south.some((p) => p[2] === 5), 'the south wall faces south, from the ground to the roof', JSON.stringify(south));
  const png = fs.readFileSync(path.join(dir, 'ground.png'));
  ok(png.readUInt32BE(16) === h.ground.w && png.readUInt32BE(20) === h.ground.h && h.ground.cell === 4 && h.ground.w === 160, 'ground.png is the survey, a pixel to a 4 m cell', h.ground.w + 'x' + h.ground.h);
  fs.rmSync(dir, { recursive: true, force: true });
})();

console.log(bad ? '\n' + bad + ' check(s) failed' : '\nall checks passed');
process.exit(bad ? 1 : 0);
