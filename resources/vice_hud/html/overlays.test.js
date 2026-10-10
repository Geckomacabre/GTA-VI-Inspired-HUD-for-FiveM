/* The screen text and overlays: subtitle, objective, help box, feed, title
 * cards, the binocular mask, the shop panel, the vehicle stats panel and the
 * cinematic overlay.
 *
 *   node html/overlays.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Drives the real page
 * with the messages client_overlays.lua sends.
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
// The page's own timers, run on demand.
const timers = [];
window.setTimeout = (fn, ms) => { timers.push({ fn, ms: ms || 0 }); return timers.length; };
window.clearTimeout = (id) => { if (timers[id - 1]) timers[id - 1].fn = null; };
const runTimers = (upTo) => timers.forEach((t) => { if (t.fn && t.ms <= upTo) { const f = t.fn; t.fn = null; f(); } });
window.eval(fs.readFileSync(base + 'app.js', 'utf8'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const $ = (id) => d.getElementById(id);
const hidden = (id) => $(id).classList.contains('hidden');
const stage = $('stage');

console.log('-- subtitle and objective --');
ok(hidden('subtitle') && hidden('objective'), 'both are down until asked for');
msg({ action: 'subtitle', show: true, text: 'Excuse me, sir.\ngas needs to go in the tank.', holdMs: 0 });
ok(!hidden('subtitle') && $('subtitle').querySelector('br'), 'a subtitle shows, and a line break in it is a line break');
msg({ action: 'objective', show: true, text: 'Return to {Lucia}', holdMs: 0 });
ok(!hidden('objective') && $('objective').querySelector('em').textContent === 'Lucia', 'the thing an objective points at is marked out', $('objective').innerHTML);
ok($('objective').textContent === 'Return to Lucia', 'and the braces themselves are not printed');
msg({ action: 'subtitle', show: true, text: '<img src=x onerror=alert(1)> **bold**', holdMs: 0 });
ok(!$('subtitle').querySelector('img') && $('subtitle').querySelector('b').textContent === 'bold', 'text is text: markup in it is not run, only the two marks mean anything');
msg({ action: 'subtitle', show: true, text: 'gone soon', holdMs: 1500 });
runTimers(1500);
ok(hidden('subtitle'), 'a subtitle takes itself down after its time');
msg({ action: 'objective', show: false });
ok(hidden('objective'), 'an objective stays until it is hidden');

console.log('\n-- help box and feed --');
msg({ action: 'helpText', show: true, text: 'Repeated use of **Zombix** will have a weaker effect.', holdMs: 0 });
ok(!hidden('help-text') && $('help-text').querySelector('b').textContent === 'Zombix', 'the help box bolds its key word');
msg({ action: 'helpText', show: true, text: 'The cops are searching for you', tells: ['outfit', 'voice'], holdMs: 0 });
ok($('help-text').querySelectorAll('.help-tells .tell').length === 2, 'and can carry the wanted tells under the line');
msg({ action: 'helpText', show: false });
ok(hidden('help-text'), 'it hides');
msg({ action: 'feed', text: 'Crime reported', holdMs: 0 });
msg({ action: 'feed', text: '+ $6', icon: 'icons/cash.png', holdMs: 3500 });
let lines = $('feed').querySelectorAll('.feed-line');
ok(lines.length === 2 && lines[0].textContent === 'Crime reported', 'feed lines stack in the order they arrive');
ok(lines[1].querySelector('img') && /cash\.png$/.test(lines[1].querySelector('img').getAttribute('src')), 'a line can carry an icon after it');
runTimers(3500);
ok($('feed').querySelectorAll('.feed-line').length === 1, 'and each leaves on its own clock');
for (let i = 0; i < 8; i++) msg({ action: 'feed', text: 'line ' + i, holdMs: 0 });
ok($('feed').querySelectorAll('.feed-line').length === 5, 'the feed never grows past five lines');

console.log('\n-- title cards --');
msg({ action: 'titleCard', show: true, text: 'Prologue', holdMs: 0 });
ok(!hidden('title-card') && $('title-card').classList.contains('center') && $('title-card').textContent === 'Prologue', 'a card is centred unless told otherwise');
msg({ action: 'titleCard', show: true, text: 'Nine months ago.', style: 'stack', holdMs: 0 });
ok($('title-card').classList.contains('stack') && $('title-card').textContent === 'Nine\nmonths\nago.', 'a stacked card is one word a line', $('title-card').textContent);
msg({ action: 'titleCard', show: true, text: 'Port Gellhorn', style: 'location', holdMs: 0 });
ok($('title-card').classList.contains('location') && $('title-card').querySelector('svg.title-sparkle'), 'a place name gets its sparkles');
msg({ action: 'titleCard', show: false });
ok(hidden('title-card'), 'a card can be taken down');

console.log('\n-- binoculars --');
msg({ action: 'binoculars', show: true, label: 'Phone cases', glyph: 'A', device: 'pad' });
ok(!hidden('binoculars') && stage.classList.contains('bino'), 'the lens comes up and the rest of the HUD stands aside');
ok(!hidden('bino-label') && $('bino-label-text').textContent === 'Phone cases' && $('bino-label-btn').classList.contains('pad'),
   'what is being looked at is named, with its button first');
msg({ action: 'inputDevice', device: 'pad', pad: 'ps' });
ok($('bino-label-btn').classList.contains('face') && !$('bino-label-btn').classList.contains('pad-a'), 'and that button follows the controller in hand');
msg({ action: 'inputDevice', device: 'pad', pad: 'xbox' });
msg({ action: 'binoculars', show: true });
ok(hidden('bino-label'), 'no label, no label row');
msg({ action: 'binoculars', show: false });
ok(hidden('binoculars') && !stage.classList.contains('bino'), 'lowering them brings the HUD back');

console.log('\n-- shop panel --');
msg({ action: 'shop', show: true, store: 'Game Horde', category: 'Earbuds', price: 139, name: 'Clef Earbuds', variant: 'Green',
      swatches: [{ color: '#111', locked: true }, { color: '#1f8a45', locked: true }, { color: '#7a45ad' }], selected: 2, afford: false });
ok(!hidden('shop') && $('shop-store').textContent === 'Game Horde' && $('shop-category').textContent === 'Earbuds', 'store and category head the screen');
ok($('shop-price').textContent === '$139' && $('shop').classList.contains('cant'), 'the price is shown, dimmed when it cannot be afforded', $('shop-price').textContent);
const sw = $('shop-swatches').querySelectorAll('.shop-swatch');
ok(sw.length === 3 && sw[1].classList.contains('on') && !sw[0].classList.contains('on'), 'the chosen swatch is outlined');
ok(sw[0].classList.contains('locked') && !sw[2].classList.contains('locked'), 'an unowned one is marked');
ok(!hidden('shop-note') && $('shop-note-text').textContent === 'Not enough money', 'and the reason it cannot be bought is said');
ok(stage.classList.contains('shopping'), 'the prompts lie in a row while the panel is up');
msg({ action: 'prompt', id: 'buy', show: true, label: 'Buy', glyph: 'X', device: 'pad', off: true });
ok(d.querySelector('#prompts .prompt').classList.contains('off'), 'a prompt that cannot be used right now is greyed');
msg({ action: 'prompt', id: 'buy', show: false });
msg({ action: 'shop', show: true, price: 20, name: 'Cap', afford: true });
ok(!$('shop').classList.contains('cant') && hidden('shop-note'), 'an affordable item has no warning');
msg({ action: 'shop', show: false });
ok(hidden('shop') && !stage.classList.contains('shopping'), 'closing it puts the prompts back in their column');

console.log('\n-- vehicle stats --');
msg({ action: 'vehStats', show: true, make: 'Maibatsu', model: 'Sanchez',
      stats: [{ label: 'Speed', value: 4.5 }, { label: 'Strength', value: 30, max: 40 }, { label: 'Over', value: 14 }],
      ratings: [{ value: 649, kind: 'offroad' }, { value: 520, kind: 'road' }] });
ok(!hidden('veh-stats') && $('vs-make').textContent === 'Maibatsu' && $('vs-model').textContent === 'Sanchez', 'make over model');
const rows = $('vs-rows').querySelectorAll('.vs-row');
ok(rows.length === 3 && rows[0].querySelector('.vs-value').textContent === '4.5', 'a row per figure, to one decimal');
const frac = (r) => r.querySelector('.vs-fill').style.getPropertyValue('--vs');
ok(frac(rows[0]) === '0.45' && frac(rows[1]) === '0.75' && frac(rows[2]) === '1', 'each bar is filled to value over its maximum, never past the end', [frac(rows[0]), frac(rows[1]), frac(rows[2])]);
ok($('vs-ratings').querySelectorAll('svg').length === 2 && /649/.test($('vs-ratings').textContent), 'the two ratings sit in the foot with their icons');
msg({ action: 'vehStats', show: false });
ok(hidden('veh-stats'), 'it hides');

console.log('\n-- cinematic overlay --');
const cine = $('cine-fx');
ok(cine && !stage.contains(cine), 'it lives outside the stage, so it survives the HUD being hidden');
msg({ action: 'cineFx', show: true, strength: 1.4, bars: 0.05 });
ok(cine.classList.contains('active') && cine.classList.contains('pulse'), 'it comes up breathing');
ok(cine.style.getPropertyValue('--cine-strength') === '1.4' && cine.style.getPropertyValue('--cine-bars') === '5vh', 'at the strength and bar height asked for',
   [cine.style.getPropertyValue('--cine-strength'), cine.style.getPropertyValue('--cine-bars')]);
msg({ action: 'hudVisible', show: false });
ok(cine.classList.contains('active') && stage.style.display === 'none', 'hiding the HUD leaves it up');
msg({ action: 'hudVisible', show: true });
msg({ action: 'cineFx', show: true, pulse: false });
ok(!cine.classList.contains('pulse'), 'it can be held still');
msg({ action: 'cineFx', show: false });
ok(!cine.classList.contains('active'), 'and it goes with the shot');

console.log(fails ? '\n' + fails + ' check(s) failed' : '\nall checks passed');
process.exit(fails ? 1 : 0);
