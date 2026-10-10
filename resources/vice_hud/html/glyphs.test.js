/* Does a prompt show the button the player would actually press -- their own
 * controller's, or the keyboard's -- and does it follow them when they switch?
 *
 *   node html/glyphs.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Drives the real page
 * with the messages client.lua sends: a prompt carries a button TOKEN and the
 * device it belongs to, and `inputDevice` says whether the pad in hand is an
 * Xbox one or a PlayStation one.
 */
const fs = require('fs');
const { JSDOM } = require('jsdom');

const base = __dirname + '/';
let fails = 0;
function ok(cond, label, extra) {
  if (cond) { console.log('  PASS  ' + label); }
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + JSON.stringify(extra) : '')); fails++; }
}

const dom = new JSDOM(fs.readFileSync(base + 'index.html', 'utf8'),
  { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;
const d = window.document;
window.fetch = () => Promise.resolve({ json: () => Promise.resolve({}) });
window.GetParentResourceName = () => 'vice_hud';
window.eval(fs.readFileSync(base + 'app.js', 'utf8'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const rows = () => Array.from(d.querySelectorAll('#prompts .prompt'));
const clear = () => rows().length && Object.keys(shown).forEach((id) => { msg({ action: 'prompt', id, show: false }); delete shown[id]; });
const shown = {};
// One prompt on screen, and its button element back.
function button(glyph, device, more) {
  clear();
  shown.t = 1;
  msg(Object.assign({ action: 'prompt', id: 't', show: true, label: 'Talk', glyph, device }, more || {}));
  return rows()[0].querySelector('.glyph');
}
const has = (el, ...names) => names.every((n) => el.classList.contains(n));
const pad = (style) => msg({ action: 'inputDevice', device: 'pad', pad: style });

console.log('-- one button, one drawing --');
let g = button('A', 'pad');
ok(g && has(g, 'pad', 'face'), 'a pad face button is drawn as one', g && g.className);
ok(g.querySelectorAll('svg').length === 1, 'as a single svg');
ok(g.querySelector('svg').getAttribute('viewBox') === '-6 -6 48 48',
   'in the 36-unit box, plus the room a hold ring would take', g.querySelector('svg').getAttribute('viewBox'));
ok(g.querySelector('svg circle.g-face') && g.querySelector('svg .g-ink'),
   'face and ink inside the same svg, so they share one centre');
ok(g.getAttribute('data-glyph') === 'A', 'and says which button it is', g.getAttribute('data-glyph'));
ok(rows()[0].querySelector('.prompt-glyph-wrap > .glyph') === g, 'in the cell every button sits in');
ok(rows()[0].firstElementChild.classList.contains('prompt-label'), 'with the label before it, as the reference has it');

console.log('\n-- an Xbox pad --');
ok(has(button('A', 'pad'), 'pad-a') && has(button('B', 'pad'), 'pad-b')
   && has(button('X', 'pad'), 'pad-x') && has(button('Y', 'pad'), 'pad-y'),
   'A B X Y each get their colour');
ok(button('A', 'pad').querySelector('path.g-ink') && !button('B', 'pad').querySelector('circle.g-ink'),
   'and are lettered, not drawn as shapes');
g = button('LB', 'pad');
ok(has(g, 'pad', 'bumper') && g.textContent === 'LB', 'the left bumper reads LB', g.textContent);
ok(g.querySelector('svg').getAttribute('viewBox') === '-6 -6 60 48', 'on a wider button', g.querySelector('svg').getAttribute('viewBox'));
ok(g.style.getPropertyValue('--g-w') === String(60 / 36), 'whose width the stylesheet is told', g.style.getPropertyValue('--g-w'));
ok(button('RT', 'pad').textContent === 'RT' && has(button('RT', 'pad'), 'trigger'), 'the right trigger reads RT');

console.log('\n-- a PlayStation pad --');
pad('ps');
g = rows()[0].querySelector('.glyph');
ok(g.textContent === 'R2', 'what is already on screen is redrawn for it', g.textContent);
g = button('A', 'pad');
ok(has(g, 'pad', 'face') && !has(g, 'pad-a'), 'the face buttons lose the Xbox colours', g.className);
ok((g.querySelector('path.g-ink').getAttribute('d').match(/M/g) || []).length === 2, 'A is the cross');
ok(button('B', 'pad').querySelector('circle.g-ink'), 'B is the circle');
ok(button('X', 'pad').querySelector('rect.g-ink'), 'X is the square');
ok(/Z$/.test(button('Y', 'pad').querySelector('path.g-ink').getAttribute('d')), 'Y is the triangle');
ok(button('LB', 'pad').textContent === 'L1' && button('RB', 'pad').textContent === 'R1', 'the bumpers are L1 and R1');
ok(button('LT', 'pad').textContent === 'L2' && button('RT', 'pad').textContent === 'R2', 'the triggers are L2 and R2');
pad('xbox');
ok(has(button('A', 'pad'), 'pad-a'), 'and switching back brings the Xbox ones back');

console.log('\n-- sticks, D-pad, Start and Back --');
g = button('LS', 'pad');
ok(has(g, 'pad', 'stick') && g.querySelectorAll('.g-solid').length === 0, 'a stick on its own has no direction marked');
ok(button('LS_UP', 'pad').querySelectorAll('.g-solid').length === 1, 'one direction is one mark');
ok(button('RS_X', 'pad').querySelectorAll('.g-solid').length === 2, 'left-and-right is two');
ok(button('LS', 'pad').querySelector('.g-ink').getAttribute('d')
   !== button('RS', 'pad').querySelector('.g-ink').getAttribute('d'), 'left and right sticks are lettered apart');
g = button('DPAD', 'pad');
ok(has(g, 'pad', 'dpad') && !g.querySelector('.g-dim'), 'the D-pad on its own is all one tone');
g = button('DPAD_RIGHT', 'pad');
ok(g.querySelector('.g-dim') && g.querySelectorAll('.g-solid:not(.g-dim)').length === 1,
   'a direction dims the cross and picks out its arm');
ok(has(button('START', 'pad'), 'pad', 'menu') && has(button('BACK', 'pad'), 'pad', 'menu'), 'Start and Back are drawn');

console.log('\n-- keyboard and mouse --');
g = button('E', 'kbm');
ok(has(g, 'key') && !has(g, 'pad'), 'a key is a key cap', g.className);
ok(g.textContent === 'E' && g.querySelector('svg rect.g-face') && g.querySelector('svg text'),
   'with its own letter on it, cap and letter in one svg', g.textContent);
g = button('SHIFT', 'kbm');
ok(has(g, 'key', 'wide') && g.textContent === 'SHIFT', 'a named key gets a wider cap', g.className);
ok(Number(g.style.getPropertyValue('--g-w')) > 1, 'that grows with the name', g.style.getPropertyValue('--g-w'));
g = button('UP', 'kbm');
ok(has(g, 'key') && g.textContent === '' && g.querySelector('path.g-ink'), 'an arrow key is an arrow, not the word');
g = button('LMB', 'kbm');
ok(has(g, 'mouse') && g.textContent === '' && /icons\/LMB\.png$/.test(g.querySelector('svg image').getAttribute('href')),
   'a mouse button is the picture of the mouse', g.className);
ok(has(button('MMB', 'kbm'), 'mouse') && has(button('WHEEL_UP', 'kbm'), 'mouse'), 'the wheel has one too');
g = button('A', 'kbm');
ok(has(g, 'key') && !has(g, 'pad') && g.textContent === 'A', 'the A KEY is not the A button', g.className);
g = button('K', 'pad');
ok(has(g, 'key') && g.textContent === 'K', 'and a pad player shown a keyboard-only bind sees the key', g.className);

console.log('\n-- nothing bound --');
button(null, 'kbm');
ok(rows()[0].classList.contains('bare') && !rows()[0].querySelector('.glyph'), 'no button: the label stands alone');
ok(rows()[0].querySelector('.prompt-label').textContent === 'Talk', 'and still reads');

console.log('\n-- hold to confirm --');
g = button('A', 'pad', { hold: true });
ok(has(g, 'ringed') && g.querySelector('svg circle.g-ring-fill'), 'a round button gets a round ring');
ok(g.querySelectorAll('svg').length === 1, 'drawn in the button\'s own svg');
const plain = button('A', 'pad');
g = button('A', 'pad', { hold: true });
ok(g.querySelector('svg').getAttribute('viewBox') === plain.querySelector('svg').getAttribute('viewBox')
   && g.style.getPropertyValue('--g-s') === plain.style.getPropertyValue('--g-s'),
   'in a box the same size as a plain one, so held and pressed rows share one centre line');
ok(!plain.querySelector('.g-ring-fill') && !plain.classList.contains('ringed'), 'which leaves the room and draws no ring');
const cell = rows()[0].querySelector('.prompt-glyph-wrap');
ok(cell.classList.contains('holdable') && cell.style.getPropertyValue('--prompt-frac') === '0', 'the ring starts empty');
msg({ action: 'promptProgress', id: 't', frac: 0.4 });
ok(cell.style.getPropertyValue('--prompt-frac') === '0.4', 'and fills as the hold runs', cell.style.getPropertyValue('--prompt-frac'));
ok(rows()[0].querySelector('.glyph') === g, 'without the row being rebuilt');
g = button('E', 'kbm', { hold: true });
ok(g.querySelector('svg rect.g-ring-fill') && !g.querySelector('svg circle.g-ring-fill'), 'a key cap gets a ring of its own shape');
ok(!button('E', 'kbm').classList.contains('ringed'), 'and a plain press has none');

console.log('\n-- switching device with prompts up --');
clear();
shown.a = shown.b = 1;
msg({ action: 'prompt', id: 'a', show: true, label: 'Talk', glyph: 'E', device: 'kbm' });
msg({ action: 'prompt', id: 'b', show: true, label: 'Taunt', glyph: 'G', device: 'kbm' });
msg({ action: 'promptGlyphs', device: 'pad', glyphs: { a: 'Y' }, devices: { a: 'pad' } });
ok(has(rows()[0].querySelector('.glyph'), 'pad', 'pad-y'), 'a prompt takes its new button');
ok(rows()[1].classList.contains('bare'), 'and one with no button on the new device does not keep the old one');
msg({ action: 'promptGlyphs', device: 'kbm', glyphs: { a: 'E', b: 'G' }, devices: { a: 'kbm', b: 'kbm' } });
ok(rows()[0].querySelector('.glyph').textContent === 'E' && rows()[1].querySelector('.glyph').textContent === 'G',
   'back on the keyboard both keys return');

console.log('\n-- the look, as measured --');
const css = fs.readFileSync(base + 'style.css', 'utf8').replace(/\r?\n/g, ' ');
const rule = (sel) => { const m = css.match(new RegExp('(?:^|[}/])\\s*' + sel.replace(/[.#]/g, '\\$&') + '\\s*\\{([^}]*)\\}')); return m ? m[1] : ''; };
ok(/right:\s*calc\(1\.31 \* var\(--w\)\)/.test(rule('#prompts')) && /bottom:\s*3\.75cqh/.test(rule('#prompts')),
   'the column sits 25px in and 40px up at 1080p', rule('#prompts'));
ok(/--g-h:\s*calc\(3\.05cqh/.test(rule('.glyph')), 'a button is the reference\'s 30px');
ok(/height:\s*calc\(3\.89cqh/.test(rule('.prompt-glyph-wrap')), 'in a 42px cell, the size of a ringed one');
ok(/text-transform:\s*uppercase/.test(css.slice(css.indexOf('.prompt-label,'), css.indexOf('.prompt-label,') + 900)),
   'and labels are capitals');

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
