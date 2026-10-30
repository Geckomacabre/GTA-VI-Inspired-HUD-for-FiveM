/* The drawn minimap (Config.Map3D): when it stands in for the engine's radar,
 * what client_map3d.lua feeds the page, what the page does before it has been
 * asked for anything, how the route is tidied, and that tools/map3d/build.py
 * and blips.py turn what they are given into the files the page reads.
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
interior, waypoint, speed, inVeh, vehClass, safeZone = 0, false, 0.0, 0, 0, 1.0
clockH, clockM = 12, 0
wanted, shooting, aimingAt, greyed, gpsLength = 0, false, 0, false, 640
function GetClockHours() return clockH end
function GetClockMinutes() return clockM end
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
function GetVehiclePedIsIn() return inVeh end
function GetVehicleClass() return vehClass end
function GetSafeZoneSize() return safeZone end
screen = { 1920, 1080 }
function GetActiveScreenResolution() return screen[1], screen[2] end
function PlayerId() return 1 end
function GetPlayerServerId() return 7 end
bags = {}
function AddStateBagChangeHandler(key, _, f) bags[key] = f end
function GetPlayerWantedLevel() return wanted end
function IsPedShooting() return shooting end
function IsPlayerFreeAiming() return aimingAt ~= 0 end
function GetEntityPlayerIsFreeAimingAt() return aimingAt ~= 0, aimingAt end
function ArePlayerStarsGreyedOut() return greyed end
function GetGpsBlipRouteLength() return gpsLength end
function IsPedInAnyVehicle(e) return ents[e] ~= nil and ents[e].inVehicle == true end
function GetEntityCoords() return { x = 10.0, y = 20.0, z = 30.0 } end
function GetFinalRenderedCamRot() return { x = 0.0, y = 0.0, z = 45.0 } end
function GetEntityHeading() return 90.0 end
function GetEntitySpeed() return speed end
-- Height: over what is beneath the player (an entity's origin is a metre up),
-- and where the nearest street is. gameMs is the game's clock.
overGround, streetZ, gameMs = 1.0, 30.0, 0
function GetEntityHeightAboveGround() return overGround end
function GetClosestVehicleNode(x, y, z) if streetZ == nil then return false, nil end return true, { x = x, y = y, z = streetZ } end
function GetGameTimer() return gameMs end
function IsWaypointActive() return waypoint end
function GetHudColour(i) return i, 2, 3, 255 end
-- The waypoint's: a road running north for 120 m, a 300 m gap, then 40 m
-- more. A script's: 60 m east.
function GetPosAlongGpsTypeRoute(fromPlayer, d, slot)
    if slot == 1 then return true, { x = math.min(d, 60.0), y = 0.0, z = 0.0 } end
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
function DoesBlipHaveGpsRoute(b) return blipInfo[b].route == true end
-- What a blip rides: ents[id] = { vehicle = bool, driver = id, player = bool, kind = ped type }
ents = {}
function GetBlipInfoIdEntityIndex(b) return blipInfo[b].ent or 0 end
function DoesEntityExist(e) return ents[e] ~= nil end
function IsEntityAVehicle(e) return ents[e] ~= nil and ents[e].vehicle == true end
function IsEntityAPed(e) return ents[e] ~= nil and not ents[e].vehicle end
function GetPedInVehicleSeat(e) return ents[e].driver or 0 end
function IsPedAPlayer(e) return ents[e].player == true end
function GetPedType(e) return ents[e].kind or 4 end
function last(action) for i = #sent, 1, -1 do if sent[i].action == action then return sent[i] end end end
function count(action) local n = 0 for i = 1, #sent do if sent[i].action == action then n = n + 1 end end return n end
-- Run thread i until it has slept n times.
-- Step the blip scan until it has finished a scan that began after now.
function rescan() local n = count("map3dBlips") while count("map3dBlips") < n + 2 do step(5, 1) end end
function step(i, n) for _ = 1, n or 1 do if coroutine.status(threads[i]) == 'dead' then return end local okay, err = coroutine.resume(threads[i]) if not okay then error(err) end end end
`;
const fresh = (config, before) => run(STUBS + (before || '') + '\nConfig = { Map3D = ' + config + ' }\n' + read('client_map3d.lua'));

console.log('-- who draws the map --');
fresh('{ enabled = true, view = { zoom = 3 }, paint = { land = { 1, 2, 3 } } }');
ok(get('ViceMap3D.owns()') === 'false', 'not before the page has said anything');
run('ViceMap3D.show(false, true)');
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
run('ViceMap3D.show(true, false)');
run('bags["vi_radio:open"]("player:7", "vi_radio:open", true)');
ok(get('last("map3d").show') === 'false', "vi_radio's wheel open: the drawn map goes, as single player's does");
run('n = #sent; ViceMap3D.show(true, false)');
ok(get('#sent - n') === '0' && get('last("map3d").show') === 'false', 'and stays gone while client.lua keeps asking for it');
run('bags["vi_radio:open"]("player:9", "vi_radio:open", false)');
ok(get('last("map3d").show') === 'false', "someone else's wheel closing changes nothing");
run('bags["vi_radio:open"]("player:7", "vi_radio:open", false)');
ok(get('last("map3d").show') === 'true', 'the wheel shut: it comes back');
run('ViceMap3D.show(false, false)');
ok(get('last("map3d").show') === 'false', 'no minimap wanted: the drawn one goes too');

console.log('\n-- indoors --');
run('interior = 77; ViceMap3D.show(ViceMap3D.owns(), false)');
ok(get('ViceMap3D.owns()') === 'false' && get('last("map3d").show') === 'false', 'inside an interior the engine\'s floor plan is the map');
run('interior = 0; ViceMap3D.show(ViceMap3D.owns(), false)');
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
ok(get('last("map3dPos").v') === 'false' && get('last("map3dPos").air') === 'nil', 'on foot: not in a vehicle, and no height');
run('n = count("map3dPos"); step(1, 5)');
ok(get('count("map3dPos") - n') === '0', 'standing still sends nothing more');
ok(get('last("map3dPos").g') === '0.0' && get('last("map3dPos").a') === '0.0', 'standing in the street: nothing under them but the ground, and level with the road');
// Up a tower: the roof is right under their feet, the street is a long way down.
run('streetZ = -70.0; gameMs = gameMs + 250; n = count("map3dPos"); step(1, 1)');
ok(get('count("map3dPos") - n') === '1' && get('last("map3dPos").g') === '0.0' && get('last("map3dPos").a') === '100.0', 'on a roof: still nothing under them, but 100 m over the street', get('last("map3dPos").a'));
run('overGround = 61.0; gameMs = gameMs + 250; step(1, 1)');
ok(get('last("map3dPos").g') === '60.0', 'stepping off it: 60 m over whatever is below', get('last("map3dPos").g'));
run('overGround = 31.0; n = count("map3dPos"); step(1, 3)');
ok(get('count("map3dPos") - n') === '0', 'height is asked for five times a second, not every frame');
run('gameMs = gameMs + 250; step(1, 1)');
ok(get('last("map3dPos").g') === '30.0', 'and passed on when it is', get('last("map3dPos").g'));
run('streetZ = nil; gameMs = gameMs + 250; step(1, 1)');
ok(get('last("map3dPos").a') === 'nil' && get('last("map3dPos").g') === '30.0', 'nowhere near a road: the street is left out, and the page goes without it');
run('overGround, streetZ = 1.0, 30.0; gameMs = gameMs + 250; step(1, 1)');
run('inVeh, vehClass, overGround = 7, 15, 120.0; n = count("map3dPos"); gameMs = gameMs + 250; step(1, 1)');
ok(get('count("map3dPos") - n') === '1' && get('last("map3dPos").v') === 'true' && get('last("map3dPos").air') === '120.0', 'in a helicopter its height above the ground goes too, to pull the view back', get('last("map3dPos").air'));
run('vehClass = 2; step(1, 1)');
ok(get('last("map3dPos").air') === 'nil', 'in a car it does not');
run('inVeh, vehClass, overGround = 0, 0, 1.0; gameMs = gameMs + 250; step(1, 1)');

run('blipsBySprite = { [8] = { 13 } } blipInfo = { [13] = { kind = 4, x = 100.0, y = 200.0 } }');
run('n = count("map3dRoute"); waypoint = true; step(4, 1)');
ok(get('count("map3dRoute") - n') === '1', 'the GPS line is walked in one go, not over several frames');
ok(get('#last("map3dRoute").routes') === '2' && get('last("map3dRoute").remaining') === '640.0', 'on foot as well as in a vehicle, with the distance left', get('#last("map3dRoute").routes'));
ok(get('#last("map3dRoute").ends') === '1' && get('last("map3dRoute").ends[1].kind') === 'waypoint' && get('last("map3dRoute").ends[1].x') === '100.0' && get('last("map3dRoute").ends[1].y') === '200.0', 'and where the waypoint is goes with it');
ok(get('last("map3dRoute").ends[1].icon') === 'nil', 'a waypoint on open ground has no picture');
run('inVeh = 7; n = count("map3dRoute"); step(4, 1)');
ok(get('#last("map3dRoute").routes') === '2', 'and split where the route jumps', get('#last("map3dRoute").routes'));
ok(get('last("map3dRoute").routes[1].pts[2]') === '0.0' && get('last("map3dRoute").routes[1].pts[#last("map3dRoute").routes[1].pts]') === '120.0', 'the first run is the road up to the gap', get('last("map3dRoute").routes[1].pts[#last("map3dRoute").routes[1].pts]'));
ok(get('last("map3dRoute").routes[1].rgb[1]') === '71' && get('last("map3dRoute").routes[1].rim[1]') === '172', 'in single player\'s teal, with its lighter rim');
ok(get('last("map3dRoute").remaining') === '640.0', 'with the distance left to drive', get('last("map3dRoute").remaining'));
run('waypoint = false; step(4, 3)');
ok(get('#last("map3dRoute").routes') === '0' && get('#last("map3dRoute").ends') === '0', 'and both are cleared when the waypoint goes');
run('inVeh = 0');

run(`
blipsBySprite = { [1] = { 11, 12, 99 }, [8] = { 13 }, [9] = { 14 }, [52] = { 15, 16, 17 } }
blipInfo = {
    [11] = { kind = 2, x = 5.0, y = 6.0 },                 -- on a ped: follows it
    [12] = { kind = 4, x = 1.0, y = 2.0, short = true, colour = 3, display = 4 },   -- what nearly every script passes
    [99] = { kind = 2 },                                   -- the player's own
    [13] = { kind = 4, x = 100.0, y = 200.0, route = true, colour = 5 },
    [14] = { kind = 7 },                                   -- a radius circle
    [15] = { kind = 4, display = 3 },                      -- pause map only
    [16] = { kind = 4, alpha = 0 },                        -- invisible
    [17] = { kind = 4 },
}
step(5, 8)
`);
ok(get('#last("map3dBlips").list') === '2', 'blips: the two that belong on a minimap', get('#last("map3dBlips").list'));
ok(get('last("map3dBlips").list[1][1]') === '1.0' && get('last("map3dBlips").list[1][2]') === '2.0', 'a blip set to display 4 is one of them: scripts pass 4 for an ordinary blip, whatever the documentation says');
ok(get('last("map3dBlips").list[1][3]') === '1' && get('last("map3dBlips").list[1][8]') === '0' && get('last("map3dBlips").list[1][4]') === '3', 'a short-range blip is not pinned to the edge, and carries its colour');
ok(get('last("map3dBlips").list[2][3]') === '52' && get('last("map3dBlips").list[2][8]') === '1' && get('#last("map3dBlips").list[2]') === '9', 'a blip that is not short-range is pinned, and nothing is sent about turning its icon: icons stay upright');
ok(get('last("map3dBlips").list[2][9]') === '17', 'each carries its handle, for the page to follow it by');
ok(get('last("map3dBlips").list[1][3]') !== '8' && get('last("map3dBlips").list[2][3]') !== '8','the stock waypoint sprite is left out: the page draws the route\'s end itself');
run('step(6, 2)');
ok(get('#last("map3dMoving").list') === '1' && get('last("map3dMoving").list[1][1]') === '5.0', 'a blip on a ped is followed separately, and the player\'s own is left out');
// The waypoint moved onto blip 17 (sprite 52), which the scan above has seen.
run('blipInfo[13] = { kind = 4, x = 60.0, y = 70.0 } blipInfo[17].x, blipInfo[17].y, blipInfo[17].colour = 60.0, 70.0, 7; rescan(); waypoint = true; step(4, 1)');
ok(get('last("map3dRoute").ends[1].icon') === '52' && get('last("map3dRoute").ends[1].iconRgb[1]') === '7', 'a waypoint set on a place carries that place\'s picture and colour', get('last("map3dRoute").ends[1].icon'));
run('blipInfo[13].x, blipInfo[13].y = 40.0, 40.0; step(4, 1)');
ok(get('last("map3dRoute").ends[1].icon') === 'nil', 'and loses it when moved off the place');
run('waypoint = false; step(4, 2)');

console.log('\n-- police --');
// Single player draws no police on its minimap, stations included.
run(`
ents = { [501] = { kind = 6 }, [502] = { vehicle = true, driver = 503 }, [503] = { kind = 27 },
         [504] = { kind = 6, player = true }, [505] = { vehicle = true, driver = 506 }, [506] = { kind = 4 },
         [507] = { kind = 4, inVehicle = true } }
blipsBySprite[3] = { 30 }      blipInfo[30] = { kind = 2 }                           -- the game's own police-ped blip
blipsBySprite[1] = { 11, 12, 99, 31, 32, 36 }
blipInfo[31] = { kind = 2, ent = 501, x = 7.0 }                                      -- a plain dot on an officer
blipInfo[32] = { kind = 2, ent = 504, x = 8.0 }                                      -- a plain dot on a PLAYER who is police
blipInfo[36] = { kind = 2, ent = 507, x = 11.0 }                                     -- on someone in a car
blipsBySprite[225] = { 33, 34 }
blipInfo[33] = { kind = 1, ent = 502, x = 9.0 }                                      -- a car driven by SWAT
blipInfo[34] = { kind = 1, ent = 505, x = 10.0 }                                     -- a car driven by anybody else
blipsBySprite[60] = { 35 }     blipInfo[35] = { kind = 4, x = 300.0, y = 300.0 }     -- a police station
rescan() step(6, 2)
`);
const riding = {};
for (let i = 1; i <= Number(get('#last("map3dMoving").list')); i++) riding[get('last("map3dMoving").list[' + i + '][1]')] = get('last("map3dMoving").list[' + i + '][8]');
ok(Object.keys(riding).sort().join() === '10.0,11.0,5.0,8.0', 'officers and the cars they drive are left off; a player who is police, and anyone else\'s car, are not', Object.keys(riding).join());
ok(riding['10.0'] === '3' && riding['11.0'] === '3' && riding['5.0'] === '1', 'a car, and someone in one, are marked as riding: their dots are drawn bigger', JSON.stringify(riding));
const places = [];
for (let i = 1; i <= Number(get('#last("map3dBlips").list')); i++) places.push(get('last("map3dBlips").list[' + i + '][3]'));
ok(places.indexOf('60') >= 0 && places.indexOf('3') < 0, 'the game\'s own police blip is left off by its sprite, and a police station stays', places.join());
run('n = #sent ViceMap3D.police("contact")');
ok(get('#sent - n') === '0', 'what the police know is kept, not sent: the page is told the colour');

console.log('\n-- stamina --');
fresh('{ enabled = true, ripple = { every = 0.5 } }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) ViceMap3D.show(true, true)');
ok(get('last("map3d").ripple') === 'false' && get('last("map3d").config.ripple.every') === '0.5', 'the first "draw" says nobody is running, and carries the rings\' settings');
run('n = count("map3d") ViceMap3D.ripple(true)');
ok(get('count("map3d") - n') === '1' && get('last("map3d").ripple') === 'true', 'stamina being spent is passed on');
run('n = count("map3d") ViceMap3D.ripple(true) ViceMap3D.ripple(true)');
ok(get('count("map3d") - n') === '0', 'once, not every tick of it');
run('ViceMap3D.show(false, true) n = count("map3d") ViceMap3D.ripple(false) ViceMap3D.ripple(true)');
ok(get('count("map3d") - n') === '0', 'and not at all to a page that is not drawing');
run('ViceMap3D.show(true, true)');
ok(get('last("map3d").ripple') === 'true' && get('last("map3d").show') === 'true', 'it goes with the next "draw"');
run('ViceMap3D.ripple(false)');
ok(get('last("map3d").ripple') === 'false', 'and so does it stopping');
run('ViceMap3D.ripple(nil) ViceMap3D.ripple("yes")');
ok(get('last("map3d").ripple') === 'false', 'anything but true is not running');
fresh('{ enabled = true, ripple = false }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) ViceMap3D.show(true, true) n = count("map3d") ViceMap3D.ripple(true)');
ok(get('count("map3d") - n') === '0' && get('last("map3d").config.ripple') === 'nil', 'ripple = false switches the rings off');

console.log('\n-- wanted --');
fresh('{ enabled = true }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) ViceMap3D.show(true, true)');
ok(get('last("map3d").want') === 'false' && get('last("map3d").ping') === 'false', 'the first "draw" says nobody is wanted');
const want = () => get('last("map3d").want and last("map3d").want.kind or "none"');
run('wanted, gameMs = 2, 1000; step(3, 1)');
ok(want() === 'blue' && get('last("map3d").want.age') === '0' && get('last("map3d").ping') === 'true', 'wanted: blue for the first five seconds, from the moment it began, and the chase rings while the stars are lit');
run('gameMs = 3000; ViceMap3D.police("contact"); shooting = true; n = count("map3d"); step(3, 1); shooting = false');
ok(get('count("map3d") - n') === '0', 'still blue then, even with the police on them and a shot fired');
run('gameMs = 6500; step(3, 1)');
ok(want() === 'red', 'after five seconds, with the police on them: red first');
run('gameMs = 7600; step(3, 1)');
ok(want() === 'blue', 'then a second of blue');
run('gameMs = 8600; step(3, 1)');
ok(want() === 'red', 'and red again: a second each');
run('ViceMap3D.police("red"); gameMs = 9000; step(3, 1)');
ok(get('last("map3d").want') === 'false', 'red stars: no colour');
run('ViceMap3D.police("hollow"); gameMs = 9100; step(3, 1)');
ok(want() === 'blue', 'hollow stars: blue');
run('ents = { [600] = { kind = 4 } } aimingAt = 600; gameMs = 9200; step(3, 1)');
ok(want() === 'red', 'aiming at someone: red');
run('aimingAt = 0; gameMs = 10800; step(3, 1)');
ok(want() === 'blue', 'and a moment and a half later it is over');
run('greyed = true; gameMs = 10900; step(3, 1)');
ok(get('last("map3d").ping') === 'false', 'stars greyed out: the police have lost the player, and the rings stop');
run('wanted = 0; gameMs = 11000; step(3, 1)');
ok(get('last("map3d").want') === 'false', 'and the colour ends with the wanted level');
run('ViceMap3D.show(false, true) wanted, greyed = 3, false; gameMs = 12000; n = count("map3d"); step(3, 2)');
ok(get('count("map3d") - n') === '0', 'nothing is sent to a page that is not drawing');
fresh('{ enabled = true, police = false }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) ViceMap3D.show(true, true) wanted = 3; n = count("map3d"); step(3, 2)');
ok(get('count("map3d") - n') === '0', 'police = false: neither the colour nor the rings');

console.log('\n-- the search circle --');
// fenix-police, while it is running, and the exports the file makes. The
// circle's feed is the seventh thread.
const SEARCH_STUBS = `
resState, exported = {}, {}
function GetResourceState(r) return resState[r] or 'missing' end
fx = { contact = false, centre = nil, radius = 0.0 }
exports = setmetatable({ ['fenix-police'] = {
    HasContact = function() return fx.contact end,
    SearchCentre = function() return fx.centre end,
    SearchRadius = function() return fx.radius end,
    SearchRadiusBounds = function() return { start = 40.0, max = 180.0 } end,
} }, { __call = function(_, name, fn) exported[name] = fn end })
me = { x = 10.0, y = 20.0, z = 30.0 }
function GetEntityCoords() return me end
function lastSearch() for i = #sent, 1, -1 do if sent[i].action == 'map3d' and sent[i].search ~= nil then return sent[i].search end end end
function searches() local n = 0 for i = 1, #sent do if sent[i].search ~= nil then n = n + 1 end end return n end
`;
const up = 'cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) ViceMap3D.show(true, true)';
const ls = (k) => get('lastSearch().' + k);
fresh('{ enabled = true }', SEARCH_STUBS);
run(up);
ok(get('lastSearch()') === 'false' && get('exported.GetSearchCircle()') === 'true', 'the first "draw" says there is no circle, and the switch is on, as single player\'s is');
run('wanted, greyed, gameMs = 2, true, 1000; n = searches(); step(7, 3)');
ok(get('searches() - n') === '0', 'under the wanted colouring the circle stands aside, as single player\'s does under GTA VI\'s colours');

fresh('{ enabled = true, police = false }', SEARCH_STUBS);
run(up + '; n = searches(); step(7, 2)');
ok(get('searches() - n') === '0', 'police = false, nobody wanted: no circle');
run('wanted, gameMs = 2, 1000; step(7, 1)');
ok(ls('chase') === 'true' && ls('r') === '180.0' && ls('age') === '0', 'wanted, the stars lit: 180 m round the player, timed from the moment it began');
run('gameMs = 1500; n = searches(); step(7, 3)');
ok(get('searches() - n') === '0', 'and nothing more while it stays so: the page keeps it round the player');
run('me = { x = 50.0, y = 60.0, z = 0.0 } greyed, gameMs = true, 3000; step(7, 1)');
ok(ls('x') === '50.0' && ls('y') === '60.0' && ls('r') === '180.0' && ls('rate') === '-4.0' && ls('lo') === '60.0' && ls('hi') === '180.0' && ls('age') === '2000',
   'the stars grey out: where the player was then, closing in from 180 m at 4 m a second to 60', ['x', 'y', 'r', 'rate', 'lo', 'hi', 'age'].map(ls).join());
run('me = { x = 90.0, y = 90.0, z = 0.0 } gameMs = 13000; n = searches(); step(7, 2)');
ok(get('searches() - n') === '0', 'it stays there as the player moves on, and closes in on the page without being sent again');
run('gameMs = 60000; step(7, 1)');
ok(get('searches() - n') === '0', 'nor once it is down to 60 m');
run('greyed, gameMs = false, 61000; step(7, 1)');
ok(ls('chase') === 'true', 'seen again: round the player');
run('greyed, gameMs = true, 62000; step(7, 1)');
ok(ls('x') === '90.0' && ls('r') === '180.0', 'lost again: a new circle where they were lost this time, from 180 m');
run('n = searches(); was = exported.SetSearchCircle(false)');
ok(get('lastSearch()') === 'false' && get('searches() - n') === '1' && get('was') === 'false' && get('kvp["vice_hud:map3d:search"]') === 'off' && get('exported.GetSearchCircle()') === 'false',
   'SetSearchCircle(false) takes it off at once, and is remembered');
run('gameMs = 63000; n = searches(); step(7, 2)');
ok(get('searches() - n') === '0', 'and it stays off');
run('exported.SetSearchCircle(true)');
ok(ls('x') === '90.0' && get('kvp["vice_hud:map3d:search"]') === 'on' && get('exported.GetSearchCircle()') === 'true', 'back on: at once, where it was');
run('wanted, gameMs = 0, 64000; step(7, 1)');
ok(get('lastSearch()') === 'false', 'the wanted level gone: so is the circle');
run('wanted, greyed, gameMs = 1, false, 65000; step(7, 1); ViceMap3D.show(false, true); n = searches(); step(7, 2)');
ok(get('searches() - n') === '0', 'nothing is sent to a page that is not drawing');
run('ViceMap3D.show(true, true)');
ok(get('last("map3d").show') === 'true' && get('last("map3d").search.chase') === 'true', 'the next "draw" carries it, worked out afresh');

fresh('{ enabled = true, police = false }', SEARCH_STUBS + 'kvp["vice_hud:map3d:search"] = "off"');
ok(get('exported.GetSearchCircle()') === 'false', 'a player who switched it off keeps it off across restarts');
fresh('{ enabled = true, police = false, searchCircle = false }', SEARCH_STUBS);
ok(get('exported.GetSearchCircle()') === 'false', 'Config.Map3D.searchCircle = false is the default');
fresh('{ enabled = true, police = false, searchCircle = false }', SEARCH_STUBS + 'kvp["vice_hud:map3d:search"] = "on"');
ok(get('exported.GetSearchCircle()') === 'true', 'and a player\'s own choice beats it');

fresh('{ enabled = true, police = false }', SEARCH_STUBS + 'resState["fenix-police"] = "started"');
run(up + '; wanted, greyed, gameMs = 2, true, 1000; fx.contact = true; step(7, 1)');
ok(ls('chase') === 'true', 'with fenix-police: round the player while a unit can see them, whatever the stars say');
run('fx.contact = false; gameMs = 1100; step(7, 1)');
ok(get('lastSearch()') === 'false', 'nobody sees them and nobody is searching (not seen yet, or given up): none');
run('fx.centre, fx.radius = { x = 100.0, y = 200.0, z = 0.0 }, 40.0; gameMs = 2000; step(7, 1)');
ok(ls('x') === '100.0' && ls('y') === '200.0' && ls('r') === '40.0' && ls('hi') === '180.0', 'searching: its search area, round where they were last seen, growing to its cap', ['x', 'y', 'r', 'hi'].map(ls).join());
run('fx.radius = 40.4; gameMs = 2100; step(7, 1)');
ok(ls('rate') === '4.0', 'how fast it grows is taken from two readings', ls('rate'));
run('fx.radius = 40.8; gameMs = 2200; n = searches(); step(7, 1)');
ok(get('searches() - n') === '0', 'and from then the page grows it itself');
run('fx.centre, fx.radius = { x = 130.0, y = 200.0, z = 0.0 }, 41.2; gameMs = 2300; step(7, 1)');
ok(ls('x') === '130.0', 'a new last sighting moves it');

console.log('\n-- a mission\'s route --');
fresh('{ enabled = true }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) ViceMap3D.show(true, true)');
run('blipsBySprite = { [1] = { 12 } } blipInfo = { [12] = { kind = 4, x = 60.0, y = 0.0, route = true } } rescan() inVeh = 7; step(4, 1)');
ok(get('#last("map3dRoute").ends') === '1' && get('last("map3dRoute").ends[1].kind') === 'mission' && get('last("map3dRoute").ends[1].x') === '60.0', 'a blip a script gave a route ends as a mission\'s');
ok(get('last("map3dRoute").routes[1].rgb[1]') === '252' && get('last("map3dRoute").routes[1].rim[1]') === '254', 'and its line is pink');
run('inVeh = 0');

console.log('\n-- day and night, and the clock --');
run('clockH, clockM = 12, 0; step(2, 1)');
ok(get('last("map3d").night') === '0.0' && get('last("map3d").clock[1]') === '12' && get('last("map3d").clock[2]') === '0', 'noon is day, and the time goes with it');
run('clockH, clockM = 23, 30; step(2, 1)');
ok(get('last("map3d").night') === '1.0', 'half past eleven is night');
run('clockH, clockM = 20, 15; step(2, 1)');
ok(get('last("map3d").night') === '0.5', 'dusk is half way, not a switch', get('last("map3d").night'));
run('clockH, clockM = 5, 45; step(2, 1)');
ok(get('last("map3d").night') === '0.5', 'and so is dawn', get('last("map3d").night'));
run('clockH, clockM = 6, 30; step(2, 1)');
ok(get('last("map3d").night') === '0.0', 'half past six is day again');
run('n = count("map3d"); step(2, 3)');
ok(get('count("map3d") - n') === '0', 'the same minute is not sent twice');
run('clockM = 31; step(2, 1)');
ok(get('last("map3d").clock[2]') === '31', 'a new one is');
fresh('{ enabled = true, night = false }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) ViceMap3D.show(true, true) clockH = 23; step(2, 1)');
ok(get('last("map3d").night') === '0.0', 'night = false keeps the daytime map');
fresh('{ enabled = true, night = "always" }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end) ViceMap3D.show(true, true) clockH = 12; step(2, 1)');
ok(get('last("map3d").night') === '1.0', 'and "always" the night one');

console.log('\n-- the panel --');
fresh('{ enabled = true }');
ok(get('ViceMap3D.rect()') === 'nil', 'before the page can draw, the map is the radar\'s rect');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end)');
const panel = () => ['left', 'width', 'bottom', 'height'].map((k) => Number(get('ViceMap3D.rect().' + k)));
const close = (a, b) => Math.abs(a - b) < 1e-6;
let P = panel();
ok(close(P[1], 208 / 720 * 9 / 16 * 100) && close(P[3], 115 / 720 * 100), 'then it is single player\'s panel, 208 by 115 of a 720th of the screen\'s height', P.join());
ok(close(P[0], 4 / 720 * 9 / 16 * 100) && close(P[2] - P[3], 8.5 / 720 * 100), '4 in from the left and 8.5 up from the bottom, at the full safe zone', P.join());
run('safeZone = 0.9');
P = panel();
ok(close(P[0], 5 + 4 / 720 * 9 / 16 * 100) && close(P[2] - P[3], 5 + 8.5 / 720 * 100), 'and as far inside a smaller safe zone', P.join());
run('safeZone = 1.0 screen = { 3440, 1440 }');
P = panel();
ok(close(P[1] / 100 * 3440, 416) && close(P[3] / 100 * 1440, 230), 'on a 21:9 screen it is single player\'s 416 by 230 pixels at 1440p, not stretched wider', P.join());
ok(close(P[0] / 100 * 3440, 8) && close((P[2] - P[3]) / 100 * 1440, 17), 'and 8 pixels in, 17 up, as single player places it', P.join());
run('screen = { 0, 0 }');
P = panel();
ok(close(P[1], 208 / 720 * 9 / 16 * 100), 'a screen that gives no size is taken as 16:9', P.join());
run('screen = { 1920, 1080 }');
ok(get('drawing == nil and ViceMap3D.rect() ~= nil') === 'true', 'the same while the map is hidden, so what sits on it stays put');
run('interior = 77');
ok(get('ViceMap3D.rect()') === 'nil', 'indoors, where the engine\'s radar is the map, it is the radar\'s rect');
fresh('{ enabled = true, panel = "native" }');
run('cbs.map3dHello({}, function() end) cbs.map3dReady({ ok = true }, function() end)');
ok(get('ViceMap3D.rect()') === 'nil', 'panel = "native" keeps the radar\'s rect');

console.log('\n-- client.lua --');
const client = read('client.lua');
const setRadar = client.slice(client.indexOf('local function setRadar(on)'), client.indexOf('-- DISPLAY_RADAR is a single global flag'));
ok(/pcall\(ViceMap3D\.owns\)/.test(setRadar) && /drawn = on and okay and owns == true/.test(setRadar), 'setRadar asks who is drawing');
ok(/if not pcall\(ViceMap3D\.show, on and drawn, northBlip\) then drawn = false end/.test(setRadar), 'and a fault in the drawn map leaves the engine\'s radar in charge');
ok(/local engine = on and not drawn\s+radarWanted = engine\s+DisplayRadar\(engine\)/.test(setRadar), 'the engine\'s radar is shown only when the drawn one is not, and held to that');
ok(/ui\('mapRect', \{ visible = on \}\)/.test(setRadar), 'the frame and badge still follow the HUD\'s own decision');
ok(/local wstate = wantedState\(ped, wanted\)[\s\S]{0,260}pcall\(ViceMap3D\.police, wstate\)/.test(client), 'the wanted readout tells the drawn map what the police know');
ok(/local okay, panel = pcall\(ViceMap3D\.rect\)\s+if okay and type\(panel\) == 'table' then rect = panel end\s+end\s+rect\.showFrame/.test(client), 'and the map\'s published rect is the drawn map\'s panel while it can be drawn, over any other');
ok(/Config\.PoliceSearch = \{[\s\S]{0,420}enable = false,/.test(read('config.lua')), 'the two search rings are off: the reference has none');
const page = read('html/map3d.js');
ok(/float w = 1\.0 \+ uT \* g \+ uLeanZ;/.test(page) && /2\.0 \* \(g - uAlt \+ lift \* min\(w, 1\.0\)\) \/ uPanel\.y/.test(page), 'every shader places a point through the one camera, raised by its height no more than at the player, with the ground lowered by the player\'s');
ok(/var w = 1 \+ V\.T \* g \+ V\.leanZ;/.test(page) && /y: V\.oy - \(g - V\.alt\) \/ w/.test(page), 'and what is drawn over the map goes through the same one');
ok(/float g = \(q \* \(1\.0 \+ uLeanZ\) \+ uAlt\) \/ max\(1\.0 - uT \* q, 0\.05\);/.test(page), 'the ground is found by running it backwards, from however high the player is');
ok(/if \(vMine > 0\.5\) \{/.test(page) && /vMine = abs\(aId - uInside\) < 0\.5/.test(page), 'only the building the player is in or on is seen through');
const manifest = read('fxmanifest.lua');
ok(manifest.indexOf("'client_map3d.lua'") > 0 && manifest.indexOf("'client_map3d.lua'") < manifest.indexOf("'client.lua'"), 'client_map3d.lua loads before client.lua');
ok(/'html\/map3d\.js'/.test(manifest) && /'html\/map3d\/\*\.bin'/.test(manifest) && /'html\/map3d\/\*\.png'/.test(manifest), 'the manifest ships the script, the pictures and whatever world has been built');
ok(fs.existsSync(path.join(root, 'html', 'map3d', 'sp.png')), 'single player\'s minimap pictures are there');

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
const M3 = window.ViceMap3D, near = (a, b, e) => Math.abs(a - b) < (e || 1e-6), now = () => window.performance.now();
ok(!!canvas && canvas.classList.contains('hidden'), 'the canvas is in the page, hidden');
ok(posts.some((p) => p.name === 'map3dHello'), 'the page says hello');
ok(M3.state().booted === false && fetched.length === 0, 'and has fetched nothing and made no WebGL context');
// The zone bar and the vehicle panel stand on a snapshot of the map's rect:
// the first one (the radar's), then the drawn map's panel once it takes over.
const stageEl = window.document.getElementById('stage');
const pw = () => stageEl.style.getPropertyValue('--panel-width');
msg({ action: 'mapRect', left: 1.75, width: 15.8, bottom: 17.9, height: 15.4, drawn: false });
ok(pw() === '15.8cqw', 'the panel stack takes the first rect, the radar\'s', pw());
msg({ action: 'mapRect', left: 1.75, width: 15, bottom: 17.9, height: 15.4, drawn: false });
ok(pw() === '15.8cqw', 'and stays put while the radar is resized', pw());
msg({ action: 'mapRect', left: 0.23, width: 12.09, bottom: 17.15, height: 15.97, drawn: true });
ok(pw() === '12.09cqw', 'it moves onto the drawn map\'s panel when the drawn map takes over', pw());
msg({ action: 'mapRect', visible: true });
ok(pw() === '12.09cqw', 'a message without a rect leaves it there', pw());
msg({ action: 'mapRect', left: 1.75, width: 15, bottom: 17.9, height: 15.4, drawn: false });
ok(pw() === '15cqw', 'and back onto the radar\'s rect when the radar does (indoors)', pw());
msg({ action: 'map3dPos', x: 1, y: 2, c: 0, h: 0, s: 0, v: true });
msg({ action: 'map3dRoute', routes: [{ pts: [0, 0, 0, 50], rgb: [1, 2, 3] }], ends: [{ x: 0, y: 50, kind: 'waypoint' }, { x: 9, y: 9, kind: 'mission' }, { x: 5, y: 5, kind: 'waypoint', icon: 52, iconRgb: [7, 8, 9] }, { nope: true }], remaining: 640 });
msg({ action: 'map3dBlips', list: [[1, 2, 1, 255, 255, 255, 255, 0, 5]] });
msg({ action: 'map3dMoving', list: [[3, 4, 1, 255, 255, 255, 255, 2, 6]] });
ok(M3.state().booted === false && M3.state().blips === 2, 'being fed before being asked to draw is harmless');
const E = M3.state().ends;
ok(E.length === 3 && E[0].kind === 'waypoint' && E[0].icon === null && E[1].kind === 'mission' && E[2].icon === 52 && E[2].iconRgb[0] === 7 && M3.state().remaining === 640, 'route ends, a waypoint\'s, a mission\'s and one on a place with its picture, a malformed one dropped, and the distance left');
msg({ action: 'map3dRoute', routes: {}, ends: {} });
ok(M3.state().ends.length === 0 && M3.state().remaining === -1, 'an empty Lua table for either is no routes and no ends, and no distance');
ok(M3.miles(2.5 * 1609.344) === '2.50 mi' && M3.miles(12.34 * 1609.344) === '12.3 mi' && M3.miles(150.4 * 1609.344) === '150 mi', 'the distance in miles, as single player writes it');

ok(M3.ink('land')[0] === M3.PAINT.land[0] && M3.PAINT.land.join() === '160,155,149' && M3.PAINT.road.join() === '172,167,161', 'by day the map is single player\'s daytime colours');
msg({ action: 'map3d', night: 1 });
ok(M3.ink('land').join() === '34,38,54' && M3.ink('roof').join() === '60,71,99' && M3.ink('road')[0] === M3.PAINT.road[0], 'at night its night ones; the roads and yards keep theirs');
msg({ action: 'map3d', night: 0.5 });
ok(near(M3.ink('land')[0], (160 + 34) / 2) && near(M3.ink('haze')[2], (186 + 84) / 2) && M3.ink('lane').length === 4, 'at dusk every colour with a night one is half way to it, the haze and lane lines too');
msg({ action: 'map3d', night: 0 });
ok(M3.PAINT.lane.slice(0, 3).join() === '120,117,114' && near(M3.PAINT.lane[3], 70 / 255) && M3.VIEW.haze.most === 0.34 && M3.VIEW.haze.to === 0.42, 'lane lines in single player\'s own lane colour, and the haze along the top');

// Wanted: the colour, how much of it, and from when.
ok(M3.state().want === null && M3.wantNow(now()).c[3] === 0, 'not wanted: no colour');
msg({ action: 'map3d', want: { kind: 'red', age: 150 } });
M3.stepWant(0, true);
let W = M3.wantNow(now());
ok(M3.state().want.join() === '169,47,56' && W.c[3] > 0.45 && W.c[3] < 0.6 && W.rising === true && near(W.c[0], 169 / 255), 'red, coming up over 300 ms from the moment the player became wanted', W.c[3]);
msg({ action: 'map3d', want: { kind: 'blue', age: 6000 } });
const mid = M3.stepWant(0.1, false);
W = M3.wantNow(now());
ok(mid === true && W.c[2] > 56 / 255 && W.c[2] < 200 / 255 && W.c[3] === 1, 'red turns to blue through the colours between, not in one jump', W.c.map((v) => Math.round(v * 255)).join());
M3.stepWant(0, true);
W = M3.wantNow(now());
ok(near(W.c[2], 200 / 255) && W.c[3] === 1 && W.rising === false && M3.stepWant(0.1, false) === false, 'and once it is blue there is nothing left to animate');
msg({ action: 'map3d', want: false });
ok(M3.state().want === null && M3.stepWant(0.1, false) === true && M3.wantNow(now()).c[3] > 0 && M3.wantNow(now()).c[3] < 1, 'when it is over it drains away');
M3.stepWant(0, true);
ok(M3.wantNow(now()).c[3] === 0, 'to nothing');
msg({ action: 'map3d', want: { kind: 'nonsense' } });
ok(M3.state().want === null, 'a colour it does not know is none');

// The clock: on the hour and the half hour, for six seconds.
(function () {
  const t0 = now();
  M3.setClock([20, 0]);
  ok(M3.clockText() === '8:00 pm', 'the time, as single player writes it', M3.clockText());
  ok(near(M3.clockAlpha(t0 + 250), 0.5, 0.05) && M3.clockAlpha(t0 + 3000) === 1 && near(M3.clockAlpha(t0 + 6750), 0.5, 0.05) && M3.clockAlpha(t0 + 8000) === 0, 'half a second in, six seconds up, half a second out');
  M3.setClock([20, 29]);
  ok(M3.clockAlpha(t0 + 8000) === 0, 'not again within the same half hour');
  M3.setClock([20, 30]);
  ok(M3.clockAlpha(now() + 3000) === 1, 'and back on the half hour');
  M3.setClock([0, 5]);
  const a = M3.clockText();
  M3.setClock([12, 0]);
  ok(a === '12:05 am' && M3.clockText() === '12:00 pm', 'midnight and noon are twelve', a + ' ' + M3.clockText());
})();

// The chase rings. Time is handed in.
ok(M3.pinging() === false && M3.stepPing(1000) === false && M3.pingRadii(1000).length === 0, 'no chase: no rings, nothing to animate');
msg({ action: 'map3d', ping: true });
ok(M3.pinging() === true && M3.stepPing(1000) === true && M3.pingRadii(1000).length === 1 && near(M3.pingRadii(1000)[0], 1.05), 'a chase: the first ring starts at once, just outside the marker');
M3.stepPing(1600);
const two = M3.pingRadii(1600);
ok(two.length === 2 && near(two[0], 1.05) && near(two[1], 1.05 + 1.25 * 0.5), 'the next follows half a cycle later, the first half way out', two.join());
M3.stepPing(2201);
ok(M3.pingRadii(2201).every((r) => r < 2.3) && M3.pingRadii(2201).length === 2, 'a ring is let go at 2.3 radii, 1.2 s on, where it has faded to nothing', M3.pingRadii(2201).join());
msg({ action: 'map3d', ping: false });
ok(M3.stepPing(2300) === false && M3.pingRadii(2300).length === 0, 'the chase stops: so do its rings, at once');
msg({ action: 'map3d', ping: 'yes' });
ok(M3.pinging() === false, 'anything but true is off');

// Stamina: rings out from the marker, on the reference's clock.
ok(M3.rippling() === false && M3.stepRipple(1000) === false && M3.rippleRadii(1000).length === 0, 'nobody running: no rings, nothing to animate');
msg({ action: 'map3d', ripple: true });
ok(M3.rippling() === true && M3.stepRipple(1000) === true && M3.rippleRadii(1000).length === 1 && near(M3.rippleRadii(1000)[0], 1), 'stamina being spent: the first ring starts at once, at the marker\'s rim');
M3.stepRipple(1200);
ok(M3.rippleRadii(1200).length === 1 && near(M3.rippleRadii(1200)[0], 1 + 2.65 * 0.2), 'it grows 2.65 marker radii a second', M3.rippleRadii(1200).join());
M3.stepRipple(1410);
ok(M3.rippleRadii(1410).length === 2 && near(M3.rippleRadii(1410)[0], 1 + 2.65 * 0.01), 'the next follows 0.4 s after it, on the beat and not on the frame that noticed', M3.rippleRadii(1410).join());
M3.stepRipple(1800);
const three = M3.rippleRadii(1800);
ok(three.length === 3 && near(three[1] - three[0], 2.65 * 0.4) && near(three[2] - three[1], 2.65 * 0.4), 'three at once, 1.06 radii apart, as the reference has them', three.join());
const gone = 1000 + (M3.RIPPLE.to - 1) / 2.65 * 1000 + 1;
M3.stepRipple(gone);
ok(M3.RIPPLE.to === 4 && M3.rippleRadii(gone).every((r) => r < 4) && M3.rippleRadii(gone).length === 2, 'a ring is let go at 4 radii, where it has faded to nothing', M3.rippleRadii(gone).join());
msg({ action: 'map3d', ripple: false });
ok(M3.stepRipple(2300) === true && M3.rippleRadii(2300).length === 2, 'the running stops: no new ring, and the ones already out carry on');
ok(M3.stepRipple(3000) === false && M3.rippleRadii(3000).length === 0, 'and a second or so later they are gone and the map is still again');
msg({ action: 'map3d', ripple: true });
M3.stepRipple(9000);
ok(M3.rippleRadii(9000).length === 1 && near(M3.rippleRadii(9000)[0], 1), 'starting again later starts from now, not from where the old beat would have been');
msg({ action: 'map3d', ripple: 'yes' });
ok(M3.rippling() === false, 'anything but true is off');
M3.rings([]);
msg({ action: 'map3d', config: { ripple: { every: 1, rgb: [1, 2, 3] } } });
ok(M3.RIPPLE.every === 1 && M3.RIPPLE.rgb[0] === 1 && M3.RIPPLE.speed === 2.65, 'the rings\' settings come from the config, over the defaults');
msg({ action: 'map3d', config: { ripple: { every: 0.4, rgb: [255, 255, 255] } } });

msg({ action: 'map3d', load: true, config: { view: { zoom: 4.5 }, paint: { land: [9, 9, 9] } } });
ok(M3.VIEW.zoom === 4.5 && M3.PAINT.land[0] === 9 && M3.VIEW.anchor === 0.85, 'config is laid over the defaults, not in place of them');
M3.VIEW.zoom = 2.58; M3.PAINT.land = [160, 155, 149];

// The camera: single player's View.
(function () {
  const V = M3.VIEW, oy = 115 * V.anchor, T = M3.camera(115, oy).T;
  ok(V.anchor === 0.85 && near(T, 0.8 / oy), 'the player sits 85% of the way down the panel, and T is 0.8 over that');
  const g = oy / (1 - T * oy);
  ok(near(1 / (1 + T * g), 0.2), 'so the panel\'s top edge is drawn at a fifth of the scale at the player');
  ok(V.opacity === 0.85 && V.roadOpacity === 0.9 && V.lift === 0.3 && V.liftCap === 400, 'the map hides 85% of the game, its roads 90%, and buildings rise 0.3 a pixel, capped at 400');
  msg({ action: 'map3dPos', x: 1, y: 2, c: 0, h: 0, s: 0, v: true, air: 5 });
  ok(M3.airScale() === 1, 'an aircraft near the ground: the view as it is');
  msg({ action: 'map3dPos', x: 1, y: 2, c: 0, h: 0, s: 0, v: true, air: 1500 });
  ok(near(M3.airScale(), 0.01), '1500 m up: a hundredth of it');
  msg({ action: 'map3dPos', x: 1, y: 2, c: 0, h: 0, s: 0, v: true, air: 755 });
  ok(near(M3.airScale(), Math.exp(Math.log(0.01) * Math.pow(0.5, 0.6))), 'and between, eased', M3.airScale());
  msg({ action: 'map3dPos', x: 1, y: 2, c: 0, h: 0, s: 0, v: false });
  ok(M3.airScale() === 1, 'on the ground, none of it');
})();

// How high the player is. No world is loaded here, so no building is under
// them: what is beneath them and the street are all there is to go on.
(function () {
  const at = (g, a, air) => { msg({ action: 'map3dPos', x: 1, y: 2, c: 0, h: 0, s: 0, g: g, a: a, air: air }); return M3.altitudeWanted(); };
  ok(at(0, 0) === 0, 'on the ground the camera is on the ground');
  ok(at(2, 2) === 0, 'a kerb, a jump, a car\'s own height: under 3 m is still the ground');
  ok(at(150, 150) === 150, 'under a parachute: as high as they are');
  ok(at(0, 40) === 0, 'on a hillside path far above the nearest road, with the ground under their feet: the ground');
  ok(at(80, 300) === 80, 'over hills: over what is beneath them, whatever the road is doing');
  ok(at(120, undefined) === 120, 'no street to go by: what is beneath them is enough');
  ok(at(9000, 9000) === M3.VIEW.altitude.max, 'and there is a ceiling');
  ok(at(150, 150, 150) === 0, 'in a helicopter or a plane the view pulls back instead, and the camera stays down');
  at(150, 150);
  ok(M3.stepAltitude(0.1, false) === true && M3.altitude() > 0 && M3.altitude() < 150, 'the camera goes up to them over a moment, not in one jump', M3.altitude());
  M3.stepAltitude(0, true);
  ok(M3.altitude() === 150 && M3.stepAltitude(0.1, false) === false, 'and once it is there, there is nothing left to animate');
  M3.VIEW.altitude = false;
  ok(M3.altitudeWanted() === 0, 'altitude = false keeps the camera on the ground');
  M3.VIEW.altitude = { ease: 3, floor: 3, max: 500, lean: 0.904 };
  at(0, 0); M3.stepAltitude(0, true);
})();

// The search circle, as single player draws it. Time is handed in.
(function () {
  const S = M3.SEARCH;
  msg({ action: 'map3dPos', x: 0, y: 0, c: 0, h: 0, s: 0, v: false });
  ok(M3.searchAt(now()) === null && M3.searchOnPanel() === null, 'no circle until one is sent');
  msg({ action: 'map3d', search: { chase: true, r: 180, age: 0 } });
  const t = now(), at = (ms) => M3.searchAt(t + ms);
  ok(at(0).x === 0 && at(0).r === 180 && at(1000).rgb.join() === '38,88,204' && at(1000).fill === 205 && at(1000).rim === 120,
     'the police on the player: 180 m round them, blue, its fill 205/255 and its rim 120');
  ok(at(2300).rgb.join() === '206,54,74' && at(3100).rgb.join() === '38,88,204' && at(3800).rgb.join() === '206,54,74' && at(4600).rgb.join() === '38,88,204',
     'from the second second, red and blue 0.75 s each, red first');
  ok(at(5100).rgb.join() === '206,54,74' && at(5100).moving === false && at(4900).moving === true, 'and from the fifth, red and still');
  msg({ action: 'map3dPos', x: 5, y: 7, c: 0, h: 0, s: 0, v: false });
  ok(at(6000).x === 5 && at(6000).y === 7, 'it goes where the player goes');

  msg({ action: 'map3d', search: { x: 50, y: 60, r: 180, rate: -4, lo: 60, hi: 180, age: 3000 } });
  const g = now(), A = M3.searchAt(g + 1000);
  ok(A.x === 50 && A.y === 60 && near(A.r, 176, 0.05) && A.fill === 105 && A.rim === 84 && A.moving === true,
     'the police searching: where they are looking, closing in at 4 m a second, at 0.7 of 150 and 120', JSON.stringify(A));
  ok(M3.searchAt(g + 40000).r === 60, 'down to 60 m and no further');
  const T = 2 * Math.PI / S.pulse, base = Math.ceil(g / T) * T, col = (phase) => M3.searchAt(base + phase * T).rgb;
  const like = (a, b) => a.every((v, i) => Math.abs(v - b[i]) <= 1);
  ok(like(col(0.75), [226, 52, 52]) && like(col(0.25), [52, 120, 226]) && near(T, 1396, 1), 'its colour from red to blue and back every 1.4 s', col(0.75).join() + ' / ' + col(0.25).join());

  // On the panel: its radius at the scale its centre is drawn at.
  msg({ action: 'map3dPos', x: 0, y: 0, c: 0, h: 0, s: 0, v: false });
  msg({ action: 'map3d', search: { x: 0, y: 0, r: 100, rate: 0, lo: 0, hi: 100, age: 0 } });
  const s = M3.project(1, 0).x - M3.project(0, 0).x;          // pixels a metre at the player
  const Hc = canvas.height, mm = Math.round(Hc * 0.1 / 1.2), unit = (Hc - 2 * mm) / 115;
  let P = M3.searchOnPanel();
  ok(near(P.R, 100 * s) && near(P.x, M3.project(0, 0).x) && near(P.y, M3.project(0, 0).y) && near(P.width, 1.1 * unit), 'on the panel: round where its centre is drawn, 100 m at the scale there, its rim 1.1 panel pixels', P.R + ' ' + 100 * s);
  msg({ action: 'map3d', search: { x: 0, y: 80, r: 100, rate: 0, lo: 0, hi: 100, age: 0 } });
  P = M3.searchOnPanel();
  ok(near(P.R, 100 * s / M3.project(0, 80).w) && P.R < 100 * s * 0.9, 'further off, smaller: a circle on the panel, not laid on the ground', P.R);
  msg({ action: 'map3d', search: { x: 0, y: -100000, r: 100, rate: 0, lo: 0, hi: 100, age: 0 } });
  ok(M3.searchOnPanel().R === undefined, 'its centre past the horizon: not drawn');
  msg({ action: 'map3d', search: { x: 0, y: 0, r: 0.2, rate: 0, lo: 0, hi: 0.2, age: 0 } });
  ok(M3.searchOnPanel().R === undefined, 'under 2 pixels: not drawn');
  msg({ action: 'map3d', search: { x: 'here', y: 0, r: 5 } });
  ok(M3.searchAt(now()) === null, 'a circle it cannot place is none');
  msg({ action: 'map3d', search: { x: 0, y: 0, r: 100, rate: 0, lo: 0, hi: 100, age: 0 } });
  msg({ action: 'map3d', search: false });
  ok(M3.searchAt(now()) === null && M3.searchOnPanel() === null, 'and false is none');
  const page = read('html/map3d.js');
  const lanes = page.indexOf("['footprint', 'rail', 'road', 'bridge', 'lot', 'lane']"), drawn = page.indexOf('var searching = drawSearch(V, now);');
  ok(lanes > 0 && drawn > lanes && drawn < page.indexOf('if (bld && VIEW.buildings !== false) {'), 'it is painted after the lane lines and under the buildings, as single player paints it');
  ok(/gl\.colorMask\(true, true, true, false\);\s+gl\.bindVertexArray\(progs\.quad\);\s+gl\.drawArrays/.test(page.slice(page.indexOf('function drawSearch'))), 'and leaves a road under it a road to the see-through');
})();
const ready = posts.find((p) => p.name === 'map3dReady');
ok(ready && ready.body.ok === false && /WebGL2/.test(ready.body.why), 'a browser that cannot draw it says so, and why', JSON.stringify(ready));
msg({ action: 'map3d', show: true });
ok(canvas.classList.contains('hidden') && !window.document.body.classList.contains('map3d-on'), 'and the canvas stays hidden rather than sitting empty over the radar, the HUD\'s own frame left in its place');

console.log('\n-- the route, tidied --');
(function () {
  const R = M3.route;
  const turn = (line) => {                       // the sharpest change of direction along it, in degrees
    let worst = 0;
    for (let i = 1; i + 1 < line.length / 2; i++) {
      const a = Math.atan2(line[i * 2 + 1] - line[i * 2 - 1], line[i * 2] - line[i * 2 - 2]);
      const b = Math.atan2(line[i * 2 + 3] - line[i * 2 + 1], line[i * 2 + 2] - line[i * 2]);
      let d = Math.abs(b - a) * 180 / Math.PI; if (d > 180) d = 360 - d;
      worst = Math.max(worst, d);
    }
    return worst;
  };
  // North for 100 m, a lane's sidestep (3.5 m over 3 m), north for 100 m more.
  const jog = [];
  for (let y = 0; y <= 100; y += 5) jog.push(0, y);
  for (let y = 103; y <= 200; y += 5) jog.push(3.5, y);
  const t = R.tidy(jog);
  ok(t && Math.abs(t.line[0]) < 0.05 && Math.abs(t.line[1]) < 0.05 && Math.abs(t.line[t.line.length - 2] - 3.5) < 0.05, 'the ends stay where the game put them');
  ok(turn(t.line) < 6, 'a lane\'s sidestep comes out as a curve, not a kink', turn(t.line).toFixed(1) + ' degrees');
  ok(Math.abs(t.arc[t.arc.length - 1] - 200) < 3 && Math.abs(t.arc[1] - t.arc[0] - 1.5) < 0.2, 'as points a metre and a half apart, each knowing how far along it is', (t.arc[1] - t.arc[0]).toFixed(2));
  // North 100 m, then east 100 m: a real corner.
  const corner = [];
  for (let y = 0; y <= 100; y += 4) corner.push(0, y);
  for (let x = 4; x <= 100; x += 4) corner.push(x, 100);
  const c = R.tidy(corner);
  let cut = Infinity;
  for (let i = 0; i < c.line.length / 2; i++) cut = Math.min(cut, Math.hypot(c.line[i * 2], c.line[i * 2 + 1] - 100));
  ok(cut < 2.5, 'a real corner is rounded but not cut off the road', cut.toFixed(2) + ' m from the corner');

  const straight = R.tidy([0, 0, 0, 200]);
  const at61 = R.startOf(straight, 1, 61);
  ok(Math.abs(at61.s - 61) < 0.2 && Math.abs(at61.y - 61) < 0.2 && Math.abs(at61.x) < 0.01, 'the line starts where the player is along it, not where the game began it', at61.s.toFixed(2));
  ok(R.startOf(straight, 0, -30).s === 0, 'and at its beginning when the player is more than 22 m from it');
  ok(R.startOf(straight, 21, 100).s > 99 && R.startOf(straight, 23, 100).s === 0, 'within 22 m it is trimmed, past that it is not');
  // Round the block: out 100 m, across, and back past the start.
  const loop = R.tidy([0, 0, 0, 100, 10, 100, 10, 0, 10, -100]);
  ok(R.startOf(loop, 0, 2).s < 5, 'a route that comes back past the player later on is not cut short there', R.startOf(loop, 0, 2).s.toFixed(1));
  // Beside two stretches of it, 1 m and 3.5 m away: the first pass within 3 m of the nearest wins.
  const back = R.tidy([3.5, -50, 3.5, 50, 20, 50, 20, 1, -40, 1]);
  const first = R.startOf(back, 0, 0);
  ok(Math.abs(first.x - 3.5) < 0.5 && first.s < 60, 'and of two passes close by, it starts at the first', first.s.toFixed(1) + ' m along at ' + first.x.toFixed(1));
  ok(R.tidy([5, 5]) === null && R.tidy([]) === null, 'a line of one point is no line');
})();

const css = read('html/style.css');
const rule = css.slice(css.indexOf('\n#map3d {'), css.indexOf('}', css.indexOf('\n#map3d {')));
ok(/height:\s*calc\(var\(--map-height[^;]*\* 1\.2\)/.test(rule) && /--m3d:[^;]*\* 0\.1\)/.test(rule) && /OVERHANG = 0\.1;/.test(read('html/map3d.js')), 'the canvas overhangs the frame by the tenth the script expects');
ok(!/--sc-mapframe|--off-mapframe/.test(rule), 'and takes none of the frame\'s /movehud nudges: it is single player\'s panel');
ok(/\.map3d-on #map-frame,\s*\.map3d-on #map-badge,\s*\.map3d-on #nav-compass \{\s*display: none !important;/.test(css), 'while it draws, the HUD\'s own frame, badge and distance step aside for its own');

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

  // tools/map3d/blips.py, on a three-picture stand-in for the documentation:
  // a white blip, a black one, and the red square that means "no picture".
  console.log('\n-- tools/map3d/blips.py --');
  const docs = fs.mkdtempSync(path.join(os.tmpdir(), 'map3d-docs-'));
  fs.mkdirSync(path.join(docs, 'content', 'docs', 'game-references'), { recursive: true });
  fs.mkdirSync(path.join(docs, 'static', 'blips'), { recursive: true });
  fs.writeFileSync(path.join(docs, 'content', 'docs', 'game-references', 'blips.md'),
    ['a', 'b', 'c'].map((n, i) => '<div class="blip"><img src="/blips/radar_' + n + '.png" alt=""><span><strong>' + (i + 5) + '</strong><br>radar_' + n + '</span></div>').join('\n'));
  const make = [
    'import sys', 'from PIL import Image, ImageDraw', 'd = sys.argv[1]',
    'def blip(name, fill, edge):',
    '    im = Image.new("RGBA", (32, 32), (0, 0, 0, 0)); g = ImageDraw.Draw(im)',
    '    g.ellipse((2, 2, 29, 29), fill=edge); g.ellipse((5, 5, 26, 26), fill=fill); im.save(d + "/radar_" + name + ".png")',
    'blip("a", (255, 255, 255, 255), (0, 0, 0, 255))',
    'blip("b", (0, 0, 0, 255), (255, 255, 255, 255))',
    'Image.new("RGBA", (32, 32), (255, 0, 0, 255)).save(d + "/radar_c.png")',
  ].join('\n');
  spawnSync(py, ['-c', make, path.join(docs, 'static', 'blips')]);
  const out = path.join(docs, 'out');
  const made = spawnSync(py, [path.join(root, 'tools', 'map3d', 'blips.py'), '--docs', docs, '--out', out], { encoding: 'utf8' });
  ok(made.status === 0, 'runs on a clone of the documentation', (made.stderr || '').slice(-300));
  if (made.status === 0) {
    const sheet = JSON.parse(fs.readFileSync(path.join(out, 'blips.json'), 'utf8'));
    ok(sheet.cells['5'] === 0 && sheet.cells['6'] === 1 && sheet.cells['7'] === undefined, 'a red placeholder is not a blip: it is left to be a dot', JSON.stringify(sheet.cells));
    const centre = spawnSync(py, ['-c', 'import sys\nfrom PIL import Image\nim = Image.open(sys.argv[1]).convert("RGBA")\nprint(im.getpixel((18, 18))[0], im.getpixel((54, 18))[0], im.getpixel((54, 5))[0])', path.join(out, 'blips.png')], { encoding: 'utf8' });
    ok(centre.stdout.trim() === '255 255 0', 'a black picture comes out white with a dark edge, like the rest', centre.stdout.trim());
  }
  fs.rmSync(docs, { recursive: true, force: true });
})();

console.log(bad ?'\n' + bad + ' check(s) failed' : '\nall checks passed');
process.exit(bad ? 1 : 0);
