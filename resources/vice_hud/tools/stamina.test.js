/* Checks the stamina reader against a native that lies.
 *
 *   npm i fengari && node tools/stamina.test.js
 *
 * GetPlayerSprintStaminaRemaining is documented three different ways --
 * remaining vs depletion, 0..1 vs 0..100 -- and can be pinned outright by any
 * script calling ResetPlayerStamina. readStamina guesses the convention by
 * watching the value move. This exercises that guess against builds that
 * behave, builds that don't, and the one that actually bit:
 *
 *   a reading of -15% that never changes.
 *
 * That one is not cosmetic. exhaustionFrom(-15) clamps to FULL exhaustion, full
 * exhaustion disables the sprint control, and a player who cannot sprint can
 * never move the native -- so the wrong reading holds itself in place and looks
 * exactly like "stamina does not drain".
 *
 * Runs the REAL readStamina lifted out of client.lua, with the natives stubbed.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
// Reads client_vitals.lua, not client.lua: focus/stamina/oxygen/needs/fatigue
// were split out of client.lua on 2026-08-28 (Lua's 200-top-level-locals
// per-chunk limit). The code itself is unchanged -- it was moved, not
// rewritten -- so the slice markers below still match.
const src = fs.readFileSync(root + 'client_vitals.lua', 'utf8');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) console.log('  PASS  ' + label);
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

// Lift the reader and the state it closes over, verbatim, so this tests the
// shipped code rather than a paraphrase of it.
const a = src.indexOf('local staminaMode   = nil');
const b = src.indexOf('-- =============================================================================', src.indexOf('local function readStamina'));
if (a < 0 || b < 0) throw new Error('could not locate readStamina in client.lua');
const chunk = src.slice(a, b);

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

  // source = 'native' throughout: the shipped DEFAULT is the self-managed bar,
  // which resolves before the native is read at all. These cases are about the
  // opt-in interpretation path, so they have to ask for it.
  const stubs = `
    Config = {
      StaminaIsDepletion = true,
      Stamina = { source = 'native', sprintSeconds = 12.0, refillSeconds = 9.0,
                  regenDelayMs = 900, skillBonus = 0.0 },
    }
    __native, __sprinting = 100.0, false
    function GetPlayerSprintStaminaRemaining() return __native end
    function IsPedSprinting() return __sprinting end
  `;
  const full = stubs + chunk + drive;
  if (lauxlib.luaL_loadbuffer(L, to_luastring(full), null, to_luastring('@stamina')) !== lua.LUA_OK) {
    throw new Error('load failed: ' + lua.lua_tojsstring(L, -1));
  }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error('run failed: ' + lua.lua_tojsstring(L, -1));
  }
  return out;
}

/* THE DEFAULT. The self-managed bar, which is what ships and what almost
 * everyone will actually run. It has to be boring and exactly right: drains
 * while sprinting, pauses, refills, and never touches the native at all. */
console.log('\n-- the self-managed bar (the shipped default) --');
{
  const lines = run(`
    -- No source given at all: the default has to be manual without being asked.
    Config.Stamina = { sprintSeconds = 12.0, refillSeconds = 9.0,
                       regenDelayMs = 900, skillBonus = 0.0 }
    staminaMode = nil

    -- The native is deliberately hostile. Nothing below may depend on it.
    __native = -999.0

    local v = readStamina(0, 0, 200)
    print('default|' .. tostring(staminaMode) .. '|' .. string.format('%.1f', v))

    -- Six seconds of sprinting: half of a twelve-second bar.
    __sprinting = true
    for _ = 1, 30 do v = readStamina(0, 0, 200) end
    print('half|' .. string.format('%.1f', v))

    -- Six more empties it, and it must not go below zero.
    for _ = 1, 40 do v = readStamina(0, 0, 200) end
    print('empty|' .. string.format('%.1f', v))

    -- Stop. The hold means nothing comes back for the first 900ms.
    __sprinting = false
    for _ = 1, 4 do v = readStamina(0, 0, 200) end
    print('held|' .. string.format('%.1f', v))

    -- Then it refills, and stops at full.
    for _ = 1, 60 do v = readStamina(0, 0, 200) end
    print('refilled|' .. string.format('%.1f', v))
  `);
  const g = {}; lines.forEach(l => { const p = l.split('|'); g[p[0]] = p.slice(1); });

  ok(g.default[0] === 'manual', 'with no source configured it settles on manual', g.default[0]);
  ok(g.default[1] === '100.0', 'and starts full', g.default[1]);
  ok(g.half[0] === '50.0', 'six seconds of a twelve-second sprint is exactly half', g.half[0]);
  ok(g.empty[0] === '0.0', 'it empties and floors at zero', g.empty[0]);
  ok(g.held[0] === '0.0',
     'stopping does NOT refill immediately — the pause is what stops the bar ' +
     'snapping back and reading as decoration', g.held[0]);
  ok(g.refilled[0] === '100.0', 'then it refills to full and stops there', g.refilled[0]);
}

/* The stamina SKILL has to lengthen the sprint, or a maxed skill would move the
 * GTA stat while this bar emptied at exactly its day-one rate. */
console.log('\n-- the stamina skill lengthens the bar --');
{
  const lines = run(`
    Config.Stamina = { sprintSeconds = 12.0, refillSeconds = 9.0,
                       regenDelayMs = 0, skillBonus = 1.0 }
    staminaMode = nil
    function SkillFitness() return 1.0 end       -- a maxed stamina skill

    __sprinting = true
    local v
    for _ = 1, 30 do v = readStamina(0, 0, 200) end   -- six seconds
    print('r|' .. string.format('%.1f', v))
  `);
  const g = lines[lines.length - 1].split('|');
  ok(g[1] === '75.0',
     'at skillBonus 1.0 a maxed skill doubles the sprint, so six seconds costs a quarter',
     g[1]);
}

/* A build that reports REMAINING on 0..100 and behaves. */
console.log('\n-- a native that behaves (remaining, 0..100) --');
{
  const lines = run(`
    local v, trusted
    -- Not sprinting yet: nothing is latched, so nothing is trusted.
    v, trusted = readStamina(0, 0, 200)
    print('idle|' .. v .. '|' .. tostring(trusted) .. '|' .. tostring(staminaMode))
    __sprinting = true
    for i = 1, 6 do
      __native = 100.0 - (i * 10)
      v, trusted = readStamina(0, 0, 200)
    end
    print('sprint|' .. string.format('%.1f', v) .. '|' .. tostring(trusted)
          .. '|' .. tostring(staminaMode) .. '|' .. tostring(staminaScale))
  `);
  const g = {}; lines.forEach(l => { const p = l.split('|'); g[p[0]] = p.slice(1); });
  ok(g.idle[1] === 'false' && g.idle[0] === '100.0',
     'before anything is latched it reports full and says so is NOT trustworthy', g.idle.join(','));
  ok(g.sprint[2] === 'remaining', 'a falling value while sprinting latches REMAINING', g.sprint[2]);
  ok(g.sprint[0] === '40.0', 'and 40 of a learned range of 100 reads as 40%', g.sprint[0]);
}

/* A build that reports DEPLETION on 0..1. */
console.log('\n-- a native that behaves (depletion, 0..1) --');
{
  const lines = run(`
    __sprinting = true
    local v
    for i = 0, 5 do
      __native = i * 0.15
      v = readStamina(0, 0, 200)
    end
    print('r|' .. string.format('%.1f', v) .. '|' .. tostring(staminaMode) .. '|' .. tostring(staminaScale))
  `);
  // The LAST line: readStamina prints its own detection message when it
  // latches, which lands ahead of anything the drive code prints.
  const g = lines[lines.length - 1].split('|');
  ok(g[2] === 'depletion', 'a rising value while sprinting latches DEPLETION', g[2]);
  ok(g[1] === '0.0', '0.75 of a learned range of 0.75 reads as empty', g[1]);
}

/* The native is pinned by something calling ResetPlayerStamina. */
console.log('\n-- a native something else is holding --');
{
  const lines = run(`
    __sprinting = true
    __native = 100.0
    local v
    for _ = 1, 20 do v = readStamina(0, 0, 200) end
    print('r|' .. tostring(staminaMode) .. '|' .. string.format('%.1f', v))
  `);
  const g = lines[lines.length - 1].split('|');
  ok(g[1] === 'manual', 'a frozen native falls back to the self-managed bar', g[1]);
  ok(+g[2] < 100, 'which then actually drains while sprinting', g[2]);
}

/* THE BUILD THIS WAS ACTUALLY REPORTED ON.
 * From /hudstamina in the wild: depletion, raw 0 .. 9.1 over a full sprint.
 * Not 0..1, not 0..100. Under the old fixed-scale maths a full sprint moved the
 * bar from 100% to 91%, which is exactly "stamina doesn't drain". */
console.log('\n-- a 0..9.1 depletion native (the reported build) --');
{
  const lines = run(`
    __sprinting = true
    local seen = {}
    -- One full sprint: the counter climbs 0 -> 9.1 and the ped gives up.
    for i = 0, 91 do
      __native = i * 0.1
      local v = readStamina(0, 0, 100)
      if i == 0 or i == 45 or i == 91 then seen[#seen+1] = string.format('%.1f', v) end
    end
    print('first|' .. table.concat(seen, ','))
    print('range|' .. string.format('%.2f', staminaRange) .. '|' .. tostring(staminaMode))

    -- A SECOND sprint, now that the range is known, must track properly.
    __native = 0.0;  local a = readStamina(0, 0, 100)
    __native = 4.55; local b = readStamina(0, 0, 100)
    __native = 9.1;  local c = readStamina(0, 0, 100)
    print('second|' .. string.format('%.0f,%.0f,%.0f', a, b, c))
  `);
  const g = {}; lines.forEach(l => { const p = l.split('|'); g[p[0]] = p.slice(1); });

  ok(g.range[0] === '9.10', 'the range is learned from what the native actually did', g.range[0]);
  ok(g.range[1] === 'depletion', 'and the mode is still read correctly', g.range[1]);
  ok(g.second[0] === '100,50,0',
     'a later sprint reads full -> half -> empty, instead of 100 -> 99 -> 91',
     g.second[0]);
  // The old maths on this build: 100 - 9.1 = 90.9. That is the bug, stated as
  // a number so nobody reintroduces the assumption.
  ok(g.second[0].split(',')[2] === '0',
     'a fully depleted native reads as EMPTY, not as 91%', g.second[0]);
}

/* The -15% that started all this.
 *
 * It can no longer HAPPEN, which is a better outcome than detecting it. The old
 * maths subtracted the native from a fixed 100, so a native reading 115 gave
 * -15%. Normalising against the observed range gives "115 out of a range of
 * 115" = fully depleted = 0%. The pathological value is not caught and
 * recovered from; it is simply not producible. */
console.log('\n-- a native that runs past the assumed scale --');
{
  const lines = run(`
    __sprinting = true
    __native = 10.0; readStamina(0, 0, 200)
    __native = 40.0; readStamina(0, 0, 200)      -- rising => depletion
    print('latched|' .. tostring(staminaMode))

    __native = 115.0
    local v, sawNegative = nil, false
    for _ = 1, 25 do
      v = readStamina(0, 0, 200)
      if v < 0 then sawNegative = true end
    end
    print('r|' .. string.format('%.1f', v) .. '|' .. tostring(sawNegative)
          .. '|' .. tostring(staminaMode) .. '|' .. string.format('%.1f', staminaRange))
  `);
  const g = {}; lines.forEach(l => { const p = l.split('|'); g[p[0]] = p.slice(1); });

  ok(g.latched[0] === 'depletion', 'the mode latches as it did in the wild', g.latched[0]);
  ok(g.r[1] === 'false',
     'a native past the assumed scale never produces a negative reading — the old ' +
     '100-minus-native maths is what turned 115 into -15%', g.r[1]);
  ok(g.r[0] === '0.0', 'it reads as fully depleted, which is what it means', g.r[0]);
  ok(g.r[2] === 'depletion',
     'and there is nothing to fall back FROM, because nothing went wrong', g.r[2]);
  ok(g.r[3] === '115.0', 'the range simply widened to fit it', g.r[3]);
}

/* A genuinely impossible reading still has to be caught. Normalisation cannot
 * save a NEGATIVE native: that is neither a remaining value nor a depletion
 * one, and no range makes it mean anything. */
console.log('\n-- a native that goes negative --');
{
  const lines = run(`
    __sprinting = true
    __native = 10.0; readStamina(0, 0, 200)
    __native = 40.0; readStamina(0, 0, 200)
    __native = -60.0
    local v
    for _ = 1, 25 do v = readStamina(0, 0, 200) end
    print('r|' .. tostring(staminaMode) .. '|' .. string.format('%.1f', v))
  `);
  const g = lines[lines.length - 1].split('|');
  ok(g[1] === 'manual',
     'held long enough, an impossible reading falls back to the self-managed bar', g[1]);
  ok(+g[2] >= 0 && +g[2] <= 100, 'and the player is left with a usable number', g[2]);
}

/* A depletion native that overshoots slightly at the bottom of a sprint is
 * legitimate and must NOT trigger the fallback. */
console.log('\n-- a small, honest overshoot --');
{
  const lines = run(`
    __sprinting = true
    __native = 10.0; readStamina(0, 0, 200)
    __native = 40.0; readStamina(0, 0, 200)
    __native = 101.0
    local v
    for _ = 1, 30 do v = readStamina(0, 0, 200) end
    print('r|' .. string.format('%.1f', v) .. '|' .. tostring(staminaMode))
  `);
  const g = lines[lines.length - 1].split('|');
  ok(g[2] === 'depletion', 'one point past the end does not throw away a working native', g[2]);
  ok(g[1] === '0.0', 'it just reads as empty', g[1]);
}

/* Stamina being SPENT, as opposed to how much is left. Two things on the HUD
 * follow it: the rings round the player's marker on the drawn minimap, and the
 * bolt beside the bar, which the reference flashes red every 0.9 s for as long
 * as the bar is going down. */
console.log('\n-- stamina being spent --');
{
  const c = src.indexOf('local staminaSpending = false');
  const d = src.indexOf('-- =============================================================================', c);
  if (c < 0 || d < 0) throw new Error('could not locate spendingStamina in client_vitals.lua');
  // Threads start at once and stop at their Wait, as the game's do; __beat()
  // is that wait being over.
  const spend = `
    __sent, __threads, __waited = {}, {}, nil
    function ui(action, data) data.action = action; __sent[#__sent + 1] = data end
    function CreateThread(f) local co = coroutine.create(f); __threads[#__threads + 1] = co; assert(coroutine.resume(co)) end
    function Wait(ms) __waited = ms; coroutine.yield() end
    function __beat() for _, co in ipairs(__threads) do if coroutine.status(co) ~= 'dead' then assert(coroutine.resume(co)) end end end
  ` + src.slice(c, d);
  const say = (...parts) => "print(table.concat({ " + parts.join(', ') + " }, '|'))";
  const table = (lines) => { const g = {}; lines.forEach(l => { const p = l.split('|'); g[p[0]] = p.slice(1); }); return g; };

  let g = table(run(spend + `
    Config.Stamina = {}
    ${say("'idle'", 'tostring(spendingStamina(0, 100.0, 250))', '#__sent')}
    __sprinting = true
    ${say("'begins'", 'tostring(spendingStamina(0, 98.0, 250))', '#__sent', 'tostring(__sent[1] and __sent[1].action)',
          'tostring(__sent[1] and __sent[1].red)', 'tostring(__sent[1] and __sent[1].ms)', 'tostring(__waited)')}
    for _ = 1, 3 do spendingStamina(0, 90.0, 250) end
    ${say("'between'", 'tostring(spendingStamina(0, 88.0, 250))', '#__sent')}
    __beat()
    ${say("'second'", '#__sent')}
    __beat() __beat()
    ${say("'fourth'", '#__sent')}
    spendingStamina(0, 0.0, 250)
    ${say("'onempty'", 'tostring(spendingStamina(0, 0.0, 250))')}
    __sprinting = false
    ${say("'stops'", 'tostring(spendingStamina(0, 0.0, 250))', '#__sent', 'tostring(staminaSpending and boltMode() == "drain")')}
    __sprinting = true
    ${say("'pickedup'", 'tostring(spendingStamina(0, 0.0, 250))', '#__sent')}
    __beat()
    ${say("'ontime'", '#__sent')}
    __sprinting = false spendingStamina(0, 0.0, 250)
    __beat()
    ${say("'over'", '#__sent', 'tostring(boltFlashing)')}
    spendingStamina(0, 5.0, 250)
    ${say("'refilling'", 'tostring(spendingStamina(0, 10.0, 250))', '#__sent')}
    __sprinting = true
    ${say("'again'", 'tostring(spendingStamina(0, 9.0, 250))', '#__sent')}
  `));
  ok(g.idle.join() === 'false,0', 'standing about spends nothing and sends nothing', g.idle.join());
  ok(g.begins[0] === 'true' && g.begins[1] === '1' && g.begins[2] === 'staminaBolt' && g.begins[3] === 'true',
     'a sprint beginning is stamina being spent, and the bolt flashes red at once', g.begins.join());
  ok(g.begins[4] === '210' && g.begins[5] === '910', 'a flash 210 ms long, the next due 910 ms on: the reference\'s own time', g.begins.join());
  ok(g.between.join() === 'true,1', 'the polls in between do not add flashes of their own', g.between.join());
  ok(g.second[0] === '2' && g.fourth[0] === '4', 'it flashes again each time that comes round, for as long as the bar is going down', g.second[0] + ' ' + g.fourth[0]);
  ok(g.onempty[0] === 'true', 'sprinting on an empty bar still counts: the ped is running', g.onempty[0]);
  ok(g.stops.join() === 'false,4,false', 'on foot it ends the moment the sprint does', g.stops.join());
  ok(g.pickedup.join() === 'true,4', 'a sprint picked straight back up does not flash early: stop-start running cannot make it stutter', g.pickedup.join());
  ok(g.ontime[0] === '5', 'it flashes when the next one was due anyway', g.ontime[0]);
  ok(g.over.join() === '5,false', 'and once the running has stopped the flashes stop with it', g.over.join());
  ok(g.refilling.join() === 'false,5', 'a bar coming back up is not being spent', g.refilling.join());
  ok(g.again.join() === 'true,6', 'the next sprint starts them again, at once', g.again.join());

  // Not on foot: nothing says "sprinting", so the falling bar is all there is
  // to go on -- and the native does not move on every poll.
  g = table(run(spend + `
    Config.Stamina = {}
    spendingStamina(0, 100.0, 250)
    ${say("'falls'", 'tostring(spendingStamina(0, 96.0, 250))', '#__sent')}
    ${say("'pause'", 'tostring(spendingStamina(0, 96.0, 250))', '#__sent')}
    ${say("'falls2'", 'tostring(spendingStamina(0, 93.0, 250))', '#__sent')}
    spendingStamina(0, 93.0, 250) spendingStamina(0, 93.0, 250)
    ${say("'over'", 'tostring(spendingStamina(0, 93.0, 250))', '#__sent')}
  `));
  ok(g.falls.join() === 'true,1', 'swimming or pedalling flat out: a falling bar is spending too', g.falls.join());
  ok(g.pause.join() === 'true,1' && g.falls2.join() === 'true,1',
     'a poll that lands between two steps of the native does not end it, or start the flashes twice', g.pause.join() + ' ' + g.falls2.join());
  ok(g.over.join() === 'false,1', 'but 600 ms with nothing falling does', g.over.join());

  g = table(run(spend + `
    Config.Stamina = { boltRed = 'drain' }
    __sprinting = true
    ${say("'drain'", 'tostring(spendingStamina(0, 98.0, 250))', '#__sent', 'tostring(staminaSpending and boltMode() == "drain")')}
    Config.Stamina.boltRed = false
    ${say("'never'", 'tostring(spendingStamina(0, 97.0, 250))', '#__sent', 'tostring(staminaSpending and boltMode() == "drain")')}
    Config.Stamina = { boltRed = 'flash', boltRedEvery = 500, boltRedMs = 400 }
    spendingStamina(0, 96.0, 250)
    ${say("'own'", 'tostring(__sent[1] and __sent[1].ms)', 'tostring(__waited)')}
    Config.Stamina.boltRed = false
    __beat()
    ${say("'off'", '#__sent', 'tostring(boltFlashing)')}
  `));
  ok(g.drain.join() === 'true,0,true', "boltRed = 'drain' sends no flashes: the bolt is held red while it lasts", g.drain.join());
  ok(g.never.join() === 'true,0,false', 'boltRed = false leaves the bolt alone, and the rings still get their answer', g.never.join());
  ok(g.own.join() === '400,500', 'boltRedMs and boltRedEvery set how long a flash is and how often', g.own.join());
  ok(g.off.join() === '1,false', 'and switching it off part-way stops the run', g.off.join());

  ok(/boltRed\s*=\s*function\(\) return staminaSpending and boltMode\(\) == 'drain' end/.test(src) && /spendingStamina\s*=\s*spendingStamina/.test(src),
     'both are published on ViceVitals');
  const client = fs.readFileSync(root + 'client.lua', 'utf8');
  ok(/local spending = ViceVitals\.spendingStamina\(ped, stamina, Config\.Tick\)\s+if ViceMap3D and ViceMap3D\.ripple then pcall\(ViceMap3D\.ripple, spending\) end/.test(client),
     'the status poll asks once a tick and tells the drawn minimap');
  ok(/boltRed = ViceVitals\.boltRed\(\) or nil,/.test(client), 'and the held bolt rides in the status payload, absent unless it is on');
  const config = fs.readFileSync(root + 'config.lua', 'utf8');
  ok(/boltRed = 'flash',/.test(config) && /boltRedEvery = 910,/.test(config) && /boltRedMs = 210,/.test(config), 'the config ships the reference\'s flash');
}

/* The page's half: a class on the stamina row, and the fade is the style sheet's. */
console.log('\n-- the bolt, on the page --');
{
  const { JSDOM } = require('jsdom');
  const dom = new JSDOM(fs.readFileSync(root + 'html/index.html', 'utf8'),
                        { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
  const { window } = dom;
  window.Element.prototype.scrollIntoView = function () {};
  window.GetParentResourceName = () => 'vice_hud';
  window.fetch = () => Promise.resolve({ json: () => Promise.resolve({}) });
  // Timers are held here and fired by hand, so a flash is checked without
  // waiting for it.
  const timers = [];
  window.setTimeout = (fn, ms) => { timers.push({ fn, ms }); return timers.length; };
  window.clearTimeout = (id) => { if (timers[id - 1]) timers[id - 1].fn = null; };
  const fire = (ms) => timers.forEach((t) => { if (t.fn && t.ms === ms) { const f = t.fn; t.fn = null; f(); } });
  const live = (ms) => timers.filter((t) => t.fn && t.ms === ms).length;
  window.eval(fs.readFileSync(root + 'html/app.js', 'utf8'));
  window.document.dispatchEvent(new window.Event('DOMContentLoaded'));
  const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
  const row = window.document.getElementById('s-stamina');
  const flashing = () => row.classList.contains('bolt-flash');
  const held = () => row.classList.contains('bolt-red');

  const imgs = row.querySelectorAll('.sic.has-badge img');
  ok(imgs.length === 2 && /badge_stamina\.png$/.test(imgs[0].getAttribute('src')) && imgs[1].className === 'sic-alt'
     && /badge_stamina_red\.png$/.test(imgs[1].getAttribute('src')), 'the row carries both badges: the teal bolt and, over it, the red');
  ok(fs.existsSync(root + 'html/icons/badge_stamina_red.png'), 'and the red one is there to be shown');
  const css = fs.readFileSync(root + 'html/style.css', 'utf8');
  ok(/\.sic\.has-badge \.sic-alt \{[^}]*position: absolute;[^}]*visibility: hidden;[^}]*\}/.test(css), 'the red one is hidden until the row asks for it');
  ok(/@keyframes bolt-flash \{ 0%, 19% \{ opacity: 1; \} 100% \{ opacity: 0; \} \}/.test(css)
     && /#s-stamina\.bolt-flash \.sic-alt \{ visibility: visible; animation: bolt-flash var\(--bolt-ms, 210ms\) linear both; \}/.test(css),
     'a flash is full red for its first fifth and then fades away, which is the red crossing back to teal');
  ok(/#s-stamina\.bolt-red \.sic-alt \{ visibility: visible; animation: none; opacity: 1; \}/.test(css), 'and held is red with no fade');

  msg({ action: 'status', health: 100, stamina: 97 });
  ok(!flashing() && !held(), 'a bar going down is, by itself, a teal bolt');
  msg({ action: 'staminaBolt', red: true, ms: 210 });
  ok(flashing() && row.style.getPropertyValue('--bolt-ms') === '210ms', 'a flash puts the red on, and says how long the fade is');
  msg({ action: 'status', health: 100, stamina: 95 });
  ok(flashing(), 'the next status poll does not cut it short');
  fire(210);
  ok(!flashing(), 'it is off again when its time is up');
  msg({ action: 'staminaBolt', red: true, ms: 210 });
  msg({ action: 'staminaBolt', red: true, ms: 210 });
  ok(flashing() && live(210) === 1, 'a flash on the heels of another starts over, with one timer and not two');
  fire(210);
  ok(!flashing(), 'and ends once');
  msg({ action: 'staminaBolt', red: true });
  ok(flashing() && row.style.getPropertyValue('--bolt-ms') === '210ms', 'no length given is the reference\'s 210 ms');
  msg({ action: 'staminaBolt', red: false });
  ok(!flashing(), 'and a flash can be called off');

  msg({ action: 'status', health: 100, stamina: 90, boltRed: true });
  ok(held(), "held ('drain'): red for as long as the status says so");
  msg({ action: 'status', health: 100, stamina: 88, boltRed: true });
  ok(held(), 'through every poll of it');
  msg({ action: 'status', health: 100, stamina: 88 });
  ok(!held(), 'and teal the moment it stops');
}

console.log('\n' + (fails ? fails + ' FAILING' : 'all checks passed'));
process.exit(fails ? 1 : 0);
