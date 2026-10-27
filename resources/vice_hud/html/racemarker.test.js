/* Headless test for the race marker (the icon over the next checkpoint).
 *
 *   node html/racemarker.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Run it after
 * touching #race-marker's markup, CSS or onRaceMarker in app.js. */
const fs = require('fs');
const { JSDOM } = require('jsdom');

const base = __dirname + '/';
const html = fs.readFileSync(base + 'index.html', 'utf8');
const css = fs.readFileSync(base + 'style.css', 'utf8');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) { console.log('  PASS  ' + label); }
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + JSON.stringify(extra) : '')); fails++; }
}

const dom = new JSDOM(html, { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;
const d = window.document;

const st = d.createElement('style');
st.textContent = css;
d.head.appendChild(st);

window.fetch = function () { return Promise.resolve({ json: () => Promise.resolve({}) }); };
window.GetParentResourceName = () => 'vice_hud';

window.eval(fs.readFileSync(base + 'app.js', 'utf8'));
d.dispatchEvent(new window.Event('DOMContentLoaded'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const $ = (id) => d.getElementById(id);
const box = () => $('race-marker');
const hidden = () => box().classList.contains('hidden');

console.log('\n-- the markup --');
ok(box() && $('race-marker-icon') && $('race-marker-dist'), 'icon and distance exist');
ok(box().parentElement === $('stage'), 'it lives on the stage with the race block, so it hides with the HUD');
ok(hidden(), 'hidden until a race puts one up');

console.log('\n-- a checkpoint 453 ft away, on screen --');
msg({ action: 'raceMarker', show: false, kind: 'checkpoint' });
ok(hidden(), 'a new marker stays hidden until it has a position');
msg({ action: 'raceMarker', show: true, kind: 'checkpoint', x: 0.27, y: 0.33, text: '453 ft' });
ok(!hidden(), 'shown once projected');
ok(box().style.left === '27cqw' && box().style.top === '33cqh', 'at the projected point, in stage units',
   [box().style.left, box().style.top]);
ok($('race-marker-dist').textContent === '453 ft', 'the distance under the dot', $('race-marker-dist').textContent);
ok(!box().classList.contains('finish'), 'a plain checkpoint is the dot, not the chequered tile');

console.log('\n-- each frame moves it; the text follows the distance --');
msg({ action: 'raceMarker', show: true, kind: 'checkpoint', x: 0.5, y: 0.4, text: '260 ft' });
ok(box().style.left === '50cqw' && $('race-marker-dist').textContent === '260 ft', 'moved and re-read');
msg({ action: 'raceMarker', show: true, x: 0.51, y: 0.4, text: '259 ft' });
ok(!box().classList.contains('finish'), 'a position push with no kind keeps the kind it had');

console.log('\n-- behind the camera, then back --');
msg({ action: 'raceMarker', show: false, kind: 'checkpoint', x: 0, y: 0, text: '250 ft' });
ok(hidden(), 'off screen hides it');
msg({ action: 'raceMarker', show: true, kind: 'checkpoint', x: 0.6, y: 0.4, text: '240 ft' });
ok(!hidden() && box().style.left === '60cqw', 'and it comes back where the point is');

console.log('\n-- the finish --');
msg({ action: 'raceMarker', show: false, kind: 'finish' });
msg({ action: 'raceMarker', show: true, kind: 'finish', x: 0.54, y: 0.28, text: '294 ft' });
ok(box().classList.contains('finish') && !hidden(), 'the finish is the chequered tile');
ok($('race-marker-dist').textContent === '294 ft', 'still with its distance');
msg({ action: 'raceMarker', show: false, kind: 'checkpoint' });
ok(!box().classList.contains('finish'), 'the next race starts back on dots');

console.log('\n-- bad input never throws --');
let threw = false;
try {
  msg({ action: 'raceMarker' });
  msg({ action: 'raceMarker', show: true });
  msg({ action: 'raceMarker', show: true, x: 0.5 });
} catch (e) { threw = e; }
ok(!threw && hidden(), 'missing fields just leave it hidden', String(threw));

console.log('\n-- the CSS carries the measured shapes --');
ok(/#race-marker\s*\{[^}]*translate\(-50%,\s*-100%\)/.test(css), 'its bottom centre is the anchor (the pillar top)');
ok(/#race-marker\s*\{[^}]*--rm-accent:\s*var\(--nav-accent/.test(css), 'coloured by the same accent as the race plate bar');
ok(/#race-marker-icon\s*\{[^}]*border-radius:\s*50%/.test(css), 'the checkpoint icon is a round dot');
ok(/#race-marker\.finish #race-marker-icon::after\s*\{[^}]*conic-gradient/.test(css), 'the finish tile is chequered');

console.log(fails ? `\n${fails} FAILED` : '\nall passed');
process.exit(fails ? 1 : 0);
