/* client_nativetext.lua under fengari: native help messages moved into
 * vice_hud's help box, and subtitles that follow the speech. Ported from the
 * single-player GTA6Hud on 2026-10-18.
 *
 *   npm i fengari && node tools/nativetext.test.js
 *
 * Runs the shipped file whole. CreateThread makes a real coroutine and Wait
 * yields it, so each step() below is one game frame; the game's state (which
 * help label is up, who is speaking, the clock) is plain Lua the drive
 * scripts change between frames.
 */
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.dirname(__dirname).replace(/\\/g, '/') + '/';
const src = fs.readFileSync(root + 'client_nativetext.lua', 'utf8').replace(/`[^`]*`/g, '0');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) console.log('  PASS  ' + label);
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

function run(drive, labelsFile) {
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
    Config = { NativeHelp = { enable = true, labels = { 'MY_LABEL' }, scanPerFrame = 5 } }
    cache = { ped = 1 }
    function PlayerPedId() return 1 end
    __now = 0
    function GetGameTimer() return __now end
    __threads = {}
    function CreateThread(fn) __threads[#__threads + 1] = coroutine.create(fn) end
    function Wait() coroutine.yield() end
    function step(n)
      for _ = 1, n or 1 do
        __now = __now + 16
        for _, co in ipairs(__threads) do
          if coroutine.status(co) ~= 'dead' then
            local okk, err = coroutine.resume(co)
            if not okk then error(err) end
          end
        end
      end
    end
    function GetCurrentResourceName() return 'vice_hud' end
    __labelsFile = ${JSON.stringify(labelsFile || '')}
    function LoadResourceFile() return __labelsFile ~= '' and __labelsFile or nil end
    -- the help box on screen: which label, its text
    __help, __texts, __asks = nil, {}, 0
    function IsHelpMessageBeingDisplayed() return __help ~= nil end
    local __asked
    function BeginTextCommandIsThisHelpMessageBeingDisplayed(l) __asked = l; __asks = __asks + 1 end
    function EndTextCommandIsThisHelpMessageBeingDisplayed() return __asked == __help end
    function GetLabelText(l) return __texts[l] or 'NULL' end
    __hidden10 = 0
    function HideHudComponentThisFrame(c) if c == 10 then __hidden10 = __hidden10 + 1 end end
    -- speech
    __speaking = {}
    __pos = { [1] = vector3 and nil }
    function DoesEntityExist(e) return e ~= nil and e ~= 0 end
    function IsAnySpeechPlaying(p) return __speaking[p] == true end
    __played = {}
    function PlayPedAmbientSpeechNative(p, ctx) __played[#__played + 1] = ctx end
    __dist = 5
    local V = {}
    V.__sub = function() return setmetatable({}, { __len = function() return __dist end }) end
    function GetEntityCoords() return setmetatable({}, V) end
    -- vice_hud's own exports, as the page sees them
    SubtitleSerial, HelpTextSerial = 0, 0
    __helpBox, __sub = nil, nil
    __registered = {}
    exports = setmetatable({ vice_hud = {
      ShowHelpText = function(_, text, ms, opts)
        HelpTextSerial = HelpTextSerial + 1
        __helpBox = text and { text = text, keys = opts and opts.keys } or nil
      end,
      ShowSubtitle = function(_, text)
        SubtitleSerial = SubtitleSerial + 1
        __sub = text
      end,
    } }, { __call = function(_, name, fn) __registered[name] = fn end })
  `;
  const full = stubs + src + '\n' + drive;
  if (lauxlib.luaL_loadbuffer(L, to_luastring(full), null, to_luastring('@nativetext')) !== lua.LUA_OK) {
    throw new Error('load failed: ' + lua.lua_tojsstring(L, -1));
  }
  if (lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error('run failed: ' + lua.lua_tojsstring(L, -1));
  }
  return out;
}

console.log('\n-- converting a help line --');
{
  const r = run(`
    local function show(raw)
      local t, k = ViceHelpConvert(raw)
      print(t == nil and 'nil' or (t .. '|' .. table.concat(k or {}, ',')))
    end
    show('Press ~INPUT_CONTEXT~ to talk.')
    show('Hold ~INPUT_AIM~ and press ~INPUT_ATTACK~ to shoot.')
    show('You have ~a~ left.')
    show('~s~Go to the ~y~garage~s~.~n~Then ~INPUT_VEH_EXIT~ to get out.')
    show('Press ~INPUT_SOMETHING_UNKNOWN~ now')
    show('NULL')
  `);
  ok(r[0] === 'Press [[1]] to talk.|51', 'an input token becomes a button the help box draws', r[0]);
  ok(r[1] === 'Hold [[1]] and press [[2]] to shoot.|25,24', 'buttons are numbered in the order they appear', r[1]);
  ok(r[2] === 'nil', 'a line with a slot the game fills in is not taken', r[2]);
  ok(r[3] === 'Go to the garage.\nThen [[1]] to get out.|75', 'colours dropped, ~n~ kept as a line break', JSON.stringify(r[3]));
  ok(r[4] === 'Press now|', 'an input with no button is dropped, as the original did', r[4]);
  ok(r[5] === 'nil', 'a label with no text is not taken', r[5]);
}

console.log('\n-- capturing a native help box --');
{
  const r = run(`
    __texts.MY_LABEL = 'Press ~INPUT_CONTEXT~ to open the trunk'
    step(3)
    print(tostring(__helpBox))                                  -- 1 nothing up
    __help = 'MY_LABEL'
    step(2)
    print(__helpBox and __helpBox.text or 'nil', tostring(__hidden10 > 0)) -- 2 taken
    local asks = __asks
    step(5)
    print(tostring(__asks - asks <= 5))                         -- 3 once found, one ask a frame
    __texts.MY_LABEL = 'Press ~INPUT_CONTEXT~ to close the trunk'
    step(20)
    print(__helpBox.text)                                       -- 4 new words picked up
    __help = nil
    step(2)
    print(tostring(__helpBox))                                  -- 5 gone with the native one
    __texts.FILL = 'Collect ~a~ more'
    __help = 'FILL'
    step(3)
    print(tostring(__helpBox), __hidden10)                      -- 6 not taken, native left alone
  `, 'FILL\nOTHER\n; a comment\n');
  ok(r[0] === 'nil', 'nothing happens while no help is up');
  ok(r[1] === 'Press [[1]] to open the trunk\ttrue', 'a known label is shown in the help box and the native one hidden', r[1]);
  ok(r[2] === 'true', 'once found it is checked once a frame, not rescanned', r[2]);
  ok(r[3] === 'Press [[1]] to close the trunk', 'new words under the same label are picked up', r[3]);
  ok(r[4] === 'nil', 'the box goes when the native help does', r[4]);
  const [box6, hidden6] = (r[5] || '').split('\t');
  ok(box6 === 'nil', 'a line with a slot stays in the native box', r[5]);
}

console.log('\n-- not taking down someone else\'s help --');
{
  const r = run(`
    __texts.MY_LABEL = 'Press ~INPUT_CONTEXT~ to talk'
    __help = 'MY_LABEL'
    step(2)
    exports.vice_hud:ShowHelpText('Somebody else\\'s tip', 5000)
    __help = nil
    step(2)
    print(__helpBox and __helpBox.text or 'nil')
  `);
  ok(r[0] === "Somebody else's tip", 'a help line another script put up after ours is left alone', r[0]);
}

console.log('\n-- spoken subtitles --');
{
  const r = run(`
    local say = __registered.ShowSpokenSubtitle
    say(5, 'Hey.', { context = 'GENERIC_HI' })
    step(5)
    print(tostring(__sub), __played[1])                          -- 1 not before speech starts
    __speaking[5] = true
    step(1)
    print(tostring(__sub))                                       -- 2 up with the voice
    step(30)
    print(tostring(__sub))                                       -- 3 stays while speaking
    __speaking[5] = false
    step(10)
    print(tostring(__sub))                                       -- 4 still up inside 450 ms
    step(40)
    print(tostring(__sub))                                       -- 5 gone after the silence
    say(6, 'Never said')
    step(60)
    print(tostring(__sub))                                       -- 6 never spoke: never shown
    __dist = 50
    __speaking[7] = true
    say(7, 'Too far')
    step(5)
    print(tostring(__sub))                                       -- 7 out of earshot
  `);
  ok(r[0] === 'nil\tGENERIC_HI', 'the context is played, but nothing shows before the ped speaks', r[0]);
  ok(r[1] === 'Hey.', 'the line appears when the speech starts', r[1]);
  ok(r[2] === 'Hey.', 'and stays while it goes on', r[2]);
  ok(r[3] === 'Hey.', 'a short pause does not take it down', r[3]);
  ok(r[4] === 'nil', 'silence past 450 ms does', r[4]);
  ok(r[5] === 'nil', 'speech that never starts within 700 ms never shows', r[5]);
  ok(r[6] === 'nil', 'a ped beyond 30 m is not subtitled', r[6]);
}

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
