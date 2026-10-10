/* The world action prompt (Slim Jim / Smash Window) must show the button
 * that ACTUALLY does something, on whichever device the player is using.
 *
 *   node html/worldactions.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. This is a regression
 * test for a real bug: the prompt used to take a hand-picked icon STRING with
 * no connection to the caller's actual keybind, so the icon and the working
 * button drifted apart -- a controller player saw a Triangle for Slim Jim
 * while the real button underneath was Circle, and pressing what was on
 * screen did nothing. Now the page is handed a resolved `glyph` (from Lua's
 * GetControlInstructionalButton against the caller's own keybind hash) and
 * derives the icon from THAT, so the two can no longer disagree.
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
const box = () => d.getElementById('world-actions');
const rows = () => Array.from(box().querySelectorAll('.wa-row'));

const btn = (row) => row.querySelector('.wa-btn');

// ---- pad: the face button the bind is actually on --------------------------
msg({ action: 'worldActions', show: true, options: [
  { label: 'Slim Jim', glyph: 'Y', device: 'pad' },
  { label: 'Smash Window', glyph: 'B', device: 'pad' },
]});
ok(!box().classList.contains('hidden'), 'app.js listener is attached (box shows)');
let r = rows();
ok(r.length === 2, 'both options rendered', r.length);
ok(btn(r[0]).classList.contains('glyph') && btn(r[0]).querySelectorAll('svg').length === 1,
   'the button is the same single-svg drawing a prompt uses');
ok(btn(r[0]).getAttribute('data-glyph') === 'Y' && btn(r[0]).classList.contains('pad-y'),
   'pad Y is drawn as Y', btn(r[0]).className);
ok(btn(r[1]).getAttribute('data-glyph') === 'B' && btn(r[1]).classList.contains('pad-b'),
   'and pad B as B, not swapped', btn(r[1]).className);
ok(r[0].firstElementChild === btn(r[0]) && r[0].lastElementChild.classList.contains('wa-label'),
   'button first, then the label, as the reference has a world prompt');

// ---- a PlayStation pad: the same two binds, drawn as its shapes -------------
msg({ action: 'inputDevice', device: 'pad', pad: 'ps' });
r = rows();
ok(/Z$/.test(btn(r[0]).querySelector('path.g-ink').getAttribute('d')),
   'on a PlayStation pad Y is the triangle, redrawn without being asked');
ok(btn(r[1]).querySelector('circle.g-ink'), 'and B is the circle');
msg({ action: 'inputDevice', device: 'pad', pad: 'xbox' });

// ---- keyboard: the resolved key on a key cap --------------------------------
msg({ action: 'worldActions', show: true, options: [
  { label: 'Slim Jim', glyph: 'R', device: 'kbm' },
  { label: 'Smash Window', glyph: 'F', device: 'kbm' },
]});
r = rows();
ok(btn(r[0]).classList.contains('key') && !btn(r[0]).classList.contains('pad'), 'keyboard draws a key cap, not a pad button');
ok(btn(r[0]).textContent === 'R', 'keyboard shows the real bound letter (R)', btn(r[0]).textContent);
ok(btn(r[1]).textContent === 'F', 'and the other option shows its own letter (F)', btn(r[1]).textContent);

// ---- shoulders, triggers and the D-pad have drawings of their own ----------
// Must not silently render nothing -- the whole point of this fix is that the
// icon always reflects the real binding.
msg({ action: 'worldActions', show: true, options: [
  { label: 'Slim Jim', glyph: 'LB', device: 'pad' },
  { label: 'Smash Window', glyph: 'DPAD_RIGHT', device: 'pad' },
]});
r = rows();
ok(btn(r[0]).classList.contains('bumper') && btn(r[0]).textContent === 'LB',
   'a bumper is drawn as a bumper and says which', btn(r[0]).className);
ok(btn(r[1]).classList.contains('dpad') && btn(r[1]).querySelector('svg .g-dim'),
   'and a D-pad direction as the D-pad with that arm picked out', btn(r[1]).className);

// ---- hides cleanly, and an old-shape payload (pre-fix caller) is inert -----
msg({ action: 'worldActions', show: false });
ok(box().classList.contains('hidden'), 'hides when told to');

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
