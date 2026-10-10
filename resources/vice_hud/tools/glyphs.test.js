/* Which button is a control on, for the device in the player's hands?
 *
 *   npm i fengari && node tools/glyphs.test.js
 *
 * Runs the real client_glyphs.lua with the natives stubbed. The thing under
 * test is the translation from what GetControlInstructionalButton answers
 * ("b_30", "t_E", "b_1000") to the token and device the page draws from, plus
 * the two things that decide HOW it is drawn: the device used last, and the
 * Xbox / PlayStation choice.
 */
const fs = require('fs');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const glyphs = fs.readFileSync(__dirname + '/../client_glyphs.lua', 'utf8');

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code, what) {
  if (lauxlib.luaL_dostring(L, to_luastring(code)) !== lua.LUA_OK) {
    throw new Error((what || 'lua') + ': ' + lua.lua_tojsstring(L, -1));
  }
}

run(`
failed = 0
function is(name, got, want)
  local good = got == want
  print((good and '  ok   ' or '  FAIL ') .. name .. (good and '' or ('   -> ' .. tostring(got))))
  if not good then failed = failed + 1 end
end

onPad, native, asked = false, {}, {}
kvp, sent, commands, threads = {}, {}, {}, 0
function IsInputDisabled() return not onPad end        -- "disabled" is keyboard+mouse
function GetHashKey(s) return #s end
function GetControlInstructionalButton(group, control, _)
  asked[#asked + 1] = { group = group, control = control }
  return native[control]
end
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
function SendNUIMessage(m) sent[#sent + 1] = m end
function CreateThread() threads = threads + 1 end
function RegisterCommand(name, fn) commands[name] = fn end
`, 'harness');

// The module again from the top, as a resource restart would run it.
const load = () => run(glyphs, 'client_glyphs.lua');

run('Config = {}');
load();

run(`
print('-- what the native answers, and what it means --')
local function both(raw) local t, d = ViceGlyphs.parse(raw) return tostring(t) .. '/' .. tostring(d) end
is('b_30 is A',            both('b_30'), 'A/pad')
is('b_31 is B',            both('b_31'), 'B/pad')
is('b_32 is X',            both('b_32'), 'X/pad')
is('b_33 is Y',            both('b_33'), 'Y/pad')
is('b_34 is the left bumper',   both('b_34'), 'LB/pad')
is('b_35 is the left trigger',  both('b_35'), 'LT/pad')
is('b_36 is the right bumper',  both('b_36'), 'RB/pad')
is('b_37 is the right trigger', both('b_37'), 'RT/pad')
is('b_4 is D-pad up',      both('b_4'),  'DPAD_UP/pad')
is('b_7 is D-pad right',   both('b_7'),  'DPAD_RIGHT/pad')
is('b_11 is D-pad left and right', both('b_11'), 'DPAD_X/pad')
is('b_12 is left stick up', both('b_12'), 'LS_UP/pad')
is('b_25 is the right stick', both('b_25'), 'RS/pad')
is('b_38 is Start',        both('b_38'), 'START/pad')
is('b_39 is Back',         both('b_39'), 'BACK/pad')

is('t_E is the E key',     both('t_E'), 'E/kbm')
is('a digit key stays a key', both('t_7'), '7/kbm')
is('b_1000 is Shift',      both('b_1000'), 'SHIFT/kbm')
is('b_2000 is Space',      both('b_2000'), 'SPACE/kbm')
is('b_194 is the up arrow', both('b_194'), 'UP/kbm')
is('b_100 is the left mouse button', both('b_100'), 'LMB/kbm')
is('b_102 is the middle one', both('b_102'), 'MMB/kbm')

is('an icon nobody has named draws no button', both('b_999'), 'nil/nil')
is('a bare index that lost its prefix is refused, not drawn as a number', both('t_100'), 'nil/nil')
is('the first alternative is the one shown', both('b_30%b_31'), 'A/pad')
is('nothing in, nothing out', both(''), 'nil/nil')
is('text the page has no letters for becomes a neutral mark',
   (ViceGlyphs.parse('t_' .. string.char(0xE2, 0x86, 0x91))), '•')

print('-- a control, on the device in hand --')
local function ctl(key) local t, d = ViceGlyphs.control(key) return tostring(t) .. '/' .. tostring(d) end
onPad = false
native[51] = 't_E'
is('keyboard: the key it is on', ctl(51), 'E/kbm')
asked = {}
is('keyboard: attack is the left mouse button', ctl(24), 'LMB/kbm')
is('and that one is answered without asking the native', #asked, 0)
is('a caller\\'s own label is passed straight through', ctl('F'), 'F/kbm')
is('no key at all is no button', ctl(nil), 'nil/kbm')

onPad = true
native[51] = 'b_7'
native[24] = 'b_37'
is('pad: the button it is on', ctl(51), 'DPAD_RIGHT/pad')
is('pad: attack is the right trigger', ctl(24), 'RT/pad')
native[77] = 't_K'
is('a control with only a keyboard bind is still drawn as that key on a pad', ctl(77), 'K/kbm')
native[78] = string.char(0, 0) .. 'Y'
is('an answer of an unknown kind is taken as the device in hand', ctl(78), 'Y/pad')

print('-- a key mapping --')
asked = {}
native[#'+nitrous' | 0x80000000] = 'b_34'
local t, d = ViceGlyphs.mapping('+nitrous')
is('resolves to its pad button', tostring(t) .. '/' .. tostring(d), 'LB/pad')
is('asked for in control group 2', asked[1].group, 2)
is('by the hash of the command with the top bit set', asked[1].control, #'+nitrous' | 0x80000000)
is('no command, no button', (ViceGlyphs.mapping(nil)), nil)
onPad = false
`, 'resolving');

run(`
print('-- Xbox or PlayStation --')
is('nothing configured: Xbox', ViceGlyphs.padStyle(), 'xbox')
`);
for (const [value, want] of [['playstation', 'ps'], ['PlayStation', 'ps'], ['ps5', 'ps'],
                             ['dualsense', 'ps'], ['xbox', 'xbox'], ['Xbox', 'xbox'], ['nonsense', 'xbox']]) {
  run(`Config = { PadGlyphs = '${value}' }`);
  load();
  run(`is("Config.PadGlyphs = '${value}'", ViceGlyphs.padStyle(), '${want}')`);
}

run(`Config = { PadGlyphs = 'xbox' } kvp['vice_hud:padGlyphs'] = 'ps'`);
load();
run(`
is('a player\\'s own choice wins over the server default', ViceGlyphs.padStyle(), 'ps')

kvp = {}
`);
run(`Config = { PadGlyphs = 'xbox' }`);
load();
run(`
sent = {}
commands.hudpad(0, { 'playstation' })
is('/hudpad playstation switches', ViceGlyphs.padStyle(), 'ps')
is('remembers it for the player', kvp['vice_hud:padGlyphs'], 'ps')
is('and tells the page', sent[#sent].action .. '/' .. sent[#sent].pad, 'inputDevice/ps')
commands.hudpad(0, { 'xbox' })
is('/hudpad xbox switches back', ViceGlyphs.padStyle(), 'xbox')
local n = #sent
commands.hudpad(0, {})
is('/hudpad on its own only reports', ViceGlyphs.padStyle() .. '/' .. (#sent - n), 'xbox/0')

print('-- following the device in hand --')
is('one watcher thread', threads > 0, true)
onPad = false
sent = {}
ViceGlyphs.announce()
is('the page is told the device', sent[1].device, 'kbm')
is('and the pad style with it', sent[1].pad, 'xbox')

local heard = {}
ViceGlyphs.onDevice(function(device) heard[#heard + 1] = device end)
sent = {}
ViceGlyphs.poll()
is('nothing changed: nothing is sent', #sent, 0)
is('and nobody is told', #heard, 0)
onPad = true
ViceGlyphs.poll()
is('picking up the pad tells the page', sent[1] and sent[1].device, 'pad')
is('and whoever asked to know', heard[1], 'pad')
ViceGlyphs.poll()
is('once, not on every look', #sent .. '/' .. #heard, '1/1')
onPad = false
ViceGlyphs.poll()
is('and putting it down again does the same', heard[2], 'kbm')
`, 'style and device');

lua.lua_getglobal(L, to_luastring('failed'));
const failed = lua.lua_tonumber(L, -1);
console.log(failed ? `\n${failed} check(s) FAILED` : '\nall checks passed');
process.exit(failed ? 1 : 0);
