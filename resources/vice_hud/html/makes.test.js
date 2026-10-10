/* Headless test for the manufacturer badge and the vehicle pips.
 *
 *   npm i jsdom && node html/makes.test.js
 *
 * Not shipped to clients -- it is not in fxmanifest's files{}, so FiveM never
 * sends it. Run it after touching html/makes.js, tools/make_makes.py, or the
 * pip rules in app.js.
 *
 * Two halves:
 *   1. VICE_MAKES.lookup on its own -- the spawn-code tokens, the accents, the
 *      two prefix passes, and the pairs that must not resolve to each other.
 *   2. the real page, driven through onVehicle the way client.lua drives it. */
const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const base = __dirname + '/';
const html = fs.readFileSync(base + 'index.html', 'utf8');

let fails = 0;
function ok(cond, label, extra) {
  if (cond) { console.log('  PASS  ' + label); }
  else { console.log('  FAIL  ' + label + (extra !== undefined ? '   -> ' + extra : '')); fails++; }
}

const dom = new JSDOM(html, { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
const { window } = dom;
const d = window.document;
window.Element.prototype.scrollIntoView = function () { this.__scrolled = true; };

const st = d.createElement('style');
st.textContent = fs.readFileSync(base + 'style.css', 'utf8');
d.head.appendChild(st);

window.eval(fs.readFileSync(base + 'makes.js', 'utf8'));
window.eval(fs.readFileSync(base + 'app.js', 'utf8'));
d.dispatchEvent(new window.Event('DOMContentLoaded'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const $ = (id) => d.getElementById(id);
const MAKES = window.VICE_MAKES;
const key = (name) => { const m = MAKES.lookup(name); return m ? m.key : null; };

console.log('\n-- the table loaded --');
ok(!!MAKES, 'VICE_MAKES is on window');
ok(Object.keys(MAKES.makes).length === 66, '66 manufacturers', Object.keys(MAKES.makes).length);

console.log('\n-- display names resolve --');
ok(key('Truffade') === 'TRUFFADE', 'Truffade');
ok(key('Pegassi') === 'PEGASSI', 'Pegassi, even with no mark of its own');
ok(key('Übermacht') === 'UBERMACHT', 'accents are stripped: Übermacht');
ok(key('Överflöd') === 'OVERFLOD', 'two accents: Överflöd');
ok(key('Western Motorcycle Company') === 'WESTERNMOTORCYCLECOMPANY', 'spaces are dropped');
ok(key('Jack Sheepe') === 'JACKSHEEPE', 'Jack Sheepe');

console.log('\n-- truncated spawn tokens resolve --');
// GetMakeNameFromVehicleModel hands back an eight-character token when the GXT
// lookup misses. These are the shapes that actually occur.
[['UBERMACH', 'UBERMACHT'], ['DEWBAUCH', 'DEWBAUCHEE'], ['BENEFAC', 'BENEFACTOR'],
 ['DUNDREAR', 'DUNDREARY'], ['ZIRCONIU', 'ZIRCONIUM'], ['BUCKING', 'BUCKINGHAM'],
 ['LAMPADAT', 'LAMPADATI'], ['CLASSIQUE', 'CLASSIQUE'], ['INVETERO', 'INVETERO']
].forEach(([token, want]) => ok(key(token) === want, token + ' -> ' + want, key(token)));

console.log('\n-- aliases cover what a prefix cannot --');
[['GALIVANT', 'GALLIVANTER'], ['JACKSHEE', 'JACKSHEEPE'], ['SPEEDOPH', 'SPEEDOPHILE'],
 ['LCC', 'LIBERTYCITYCYCLES'], ['PED', 'PEDCYCLES']
].forEach(([token, want]) => ok(key(token) === want, token + ' -> ' + want, key(token)));

console.log('\n-- the two Western divisions do not collide --');
ok(key('WESTERN') === 'WESTERNCOMPANY', 'bare WESTERN is the aircraft company');
ok(key('WESTMIN') === 'WESTERNMOTORCYCLECOMPANY', 'WESTMIN is the motorcycle company');
ok(key('WesternMC') === 'WESTERNMOTORCYCLECOMPANY', 'so is WesternMC');
// The longest-match pass is the thing being checked here: a shortest-match
// rule would answer this with WESTERNCOMPANY.
ok(key('WesternMotorcycleCompanyCustoms') === 'WESTERNMOTORCYCLECOMPANY',
   'a decorated name takes the LONGEST marque it starts with', key('WesternMotorcycleCompanyCustoms'));

console.log('\n-- unknown makes stay unknown --');
ok(key('') === null, 'empty string');
ok(key(null) === null, 'null');
ok(key('Mansory') === null, 'an addon manufacturer');
ok(key('SEGWAYCIV') === null, 'a raw spawn code that is not a marque');
ok(key('XYZ') === null, 'a short token matches nothing rather than guessing');

console.log('\n-- every mark named in the table is on disk --');
let missingFiles = [];
let withMark = 0;
Object.keys(MAKES.makes).forEach(function (k) {
  const file = MAKES.makes[k][1];
  if (!file) return;
  withMark++;
  if (!fs.existsSync(path.join(base, 'logos', file))) missingFiles.push(file);
  if (file !== k + '.png') missingFiles.push(file + ' (does not match its key)');
});
ok(missingFiles.length === 0, 'no dangling logo references', missingFiles.join(', '));
ok(withMark >= 50, 'at least 50 manufacturers have a mark', withMark);

console.log('\n-- the panel wires the mark up --');
msg({ action: 'vehicle', show: true, make: 'Truffade', model: 'Thrax',
      fuel: 70, engineOn: true, engineHealth: 1000 });
ok($('vehicle').classList.contains('badged'), 'a known marque badges the panel');
ok($('veh-logo').getAttribute('src') === 'logos/TRUFFADE.png', 'and points at its mark',
   $('veh-logo').getAttribute('src'));
ok($('veh-make').textContent === 'TRUFFADE', 'make line still set');

msg({ action: 'vehicle', show: true, make: 'Vapid', model: 'Dominator',
      fuel: 70, engineOn: true, engineHealth: 1000 });
ok(!$('vehicle').classList.contains('badged'),
   'a marque whose only mark is its own name gets no badge');
ok(!$('veh-logo').getAttribute('src'), 'and the src is cleared, not left stale',
   $('veh-logo').getAttribute('src'));

msg({ action: 'vehicle', show: true, make: '', model: 'SEGWAYCIV',
      fuel: 70, engineOn: true, engineHealth: 1000 });
ok(!$('vehicle').classList.contains('badged'), 'an addon with no make gets no badge');

console.log('\n-- pip tones --');
// Just the tone token. The class list also carries `pip` and, on the two that
// have a ring, `gauge` -- neither of which is what these cases are about.
const tones = () => ['pip-tracker', 'pip-engine', 'pip-fuel']
  .map((id) => $(id).className.split(/\s+/)
    .filter((c) => c && c !== 'pip' && c !== 'gauge')[0] || '')
  .join(' ');

function pips(label, payload, want) {
  payload.action = 'vehicle';
  payload.show = true;
  payload.make = 'Karin';
  payload.model = 'Kuruma';
  msg(payload);
  ok(tones() === want, label + ' -> ' + want, tones());
}

pips('running, healthy, tracker clear, full tank',
     { fuel: 70, engineOn: true, engineHealth: 1000, trackerState: 'clear' },
     'good good good');
pips('worn engine, tracker searching',
     { fuel: 70, engineOn: true, engineHealth: 450, trackerState: 'searching' },
     'warn warn good');
pips('broken engine, a quarter tank, tracker spotted',
     { fuel: 20, engineOn: true, engineHealth: 80, trackerState: 'spotted' },
     'bad bad warn');
// GetVehicleEngineHealth goes NEGATIVE past seized, so the bad band cannot
// have a floor on it.
pips('destroyed engine reads negative, still bad, tracker spotted',
     { fuel: 5, engineOn: true, engineHealth: -4000, trackerState: 'spotted' },
     'bad bad bad');
// Fuel and engine go monochrome with the engine off; the tracker does not --
// it is owned entirely by whatever called SetVehicleTracker, and a driver
// killing the engine to hide from a search should not also blind the HUD.
pips('SHUT OFF still leaves the tracker lit, unlike fuel and engine',
     { fuel: 5, engineOn: false, engineHealth: -4000, trackerState: 'spotted' },
     'bad unknown unknown');
pips('an older client.lua sending no engineHealth is not "broken"',
     { fuel: 70, engineOn: true, trackerState: 'clear' },
     'good good good');
pips('no tracker state set at all -- reads as unknown',
     { fuel: 70, engineOn: true, engineHealth: 1000, trackerState: null },
     'unknown good good');

console.log('\n-- the tracker shows ONLY while actually active --');
// Unlike fuel/engine, the tracker gets no expanded bypass and no "healthy is
// still worth a glance on entry" grace -- 'clear' and unset both mean there
// is nothing to report, so it stays hidden even during the announcement.
// Only 'searching'/'spotted' earn it a place on screen.
msg({ action: 'vehicle', show: true, collapsed: true, make: 'Karin', model: 'Kuruma',
      fuel: 70, engineOn: true, engineHealth: 1000, trackerState: null });
ok($('pip-tracker').classList.contains('hidden'), 'collapsed, unset: hidden');
msg({ action: 'vehicle', show: true, collapsed: true, make: 'Karin', model: 'Kuruma',
      fuel: 70, engineOn: true, engineHealth: 1000, trackerState: 'clear' });
ok($('pip-tracker').classList.contains('hidden'), 'collapsed, clear: still hidden');
msg({ action: 'vehicle', show: true, collapsed: true, make: 'Karin', model: 'Kuruma',
      fuel: 70, engineOn: true, engineHealth: 1000, trackerState: 'searching' });
ok(!$('pip-tracker').classList.contains('hidden'), 'collapsed, searching: shows');
msg({ action: 'vehicle', show: true, collapsed: false, make: 'Karin', model: 'Kuruma',
      fuel: 70, engineOn: true, engineHealth: 1000, trackerState: null });
ok($('pip-tracker').classList.contains('hidden'), 'expanded, unset: still hidden -- no free pass on entry');
msg({ action: 'vehicle', show: true, collapsed: false, make: 'Karin', model: 'Kuruma',
      fuel: 70, engineOn: true, engineHealth: 1000, trackerState: 'spotted' });
ok(!$('pip-tracker').classList.contains('hidden'), 'expanded, spotted: shows');

console.log('\n-- pip glyphs are drawn, not typed --');
// They were emoji, and Windows renders the padlock orange and the pump red
// whatever `color` says. Inline SVG is what keeps the trio one colour.
const glyphs = ['pip-tracker', 'pip-engine', 'pip-fuel'].map((id) => $(id).querySelector('.pip-glyph'));
ok(glyphs.every(Boolean), 'every pip holds a glyph svg');
ok(['pip-tracker', 'pip-engine', 'pip-fuel'].every((id) => !$(id).textContent.trim()),
   'and no text content that a font could colour');

console.log('\n-- the gauge rings read the real numbers --');
const pct = (id) => $(id).style.getPropertyValue('--pct');
const ring = (id) => $(id).querySelector('.pip-fill');

ok(ring('pip-fuel') && ring('pip-engine'), 'fuel and engine have a ring');
// The tracker is a STATE, not a quantity. A ring on it would be a gauge that
// only ever reads full or empty, which is a worse way of saying what the
// colour already says.
ok(!ring('pip-tracker'), 'the tracker does not');

msg({ action: 'vehicle', show: true, make: 'Karin', model: 'Kuruma',
      fuel: 64, engineOn: true, engineHealth: 730 });
ok(pct('pip-fuel') === '64.0', 'fuel ring reads the fuel level', pct('pip-fuel'));
ok(pct('pip-engine') === '73.0', 'engine ring reads health/10', pct('pip-engine'));

msg({ action: 'vehicle', show: true, make: 'Karin', model: 'Kuruma',
      fuel: 0, engineOn: true, engineHealth: -4000 });
ok(pct('pip-fuel') === '0.0', 'an empty tank reads zero', pct('pip-fuel'));
// The native goes far below zero for a destroyed engine; the ring must clamp
// rather than compute a negative dash offset.
ok(pct('pip-engine') === '0.0', 'a destroyed engine clamps to zero, not negative',
   pct('pip-engine'));
// A round linecap paints a dot even at zero, which would show a pip of fuel in
// an empty tank.
ok(ring('pip-fuel').getAttribute('data-empty') === '1',
   'and zero switches the cap so it draws nothing at all');

msg({ action: 'vehicle', show: true, make: 'Karin', model: 'Kuruma',
      fuel: 140, engineOn: true, engineHealth: 4000 });
ok(pct('pip-fuel') === '100.0', 'over-full clamps to 100', pct('pip-fuel'));
ok(pct('pip-engine') === '100.0', 'so does a better-than-new engine', pct('pip-engine'));

// The reading survives the engine being off: only the COLOUR goes monochrome.
msg({ action: 'vehicle', show: true, make: 'Karin', model: 'Kuruma',
      fuel: 42, engineOn: false, engineHealth: 800 });
ok(pct('pip-fuel') === '42.0', 'a parked car still shows how much fuel it has',
   pct('pip-fuel'));
ok($('pip-fuel').classList.contains('unknown'), 'but says it in grey');

console.log('\n-- the panel collapses to just the icons --');
msg({ action: 'vehicle', show: true, collapsed: false, make: 'Truffade', model: 'Thrax',
      fuel: 70, engineOn: true, engineHealth: 1000 });
ok(!$('vehicle').classList.contains('collapsed'), 'the announcement draws the whole plate');
ok($('veh-make').textContent === 'TRUFFADE', 'names are filled in');

msg({ action: 'vehicle', show: true, collapsed: true, make: 'Truffade', model: 'Thrax',
      fuel: 55, engineOn: true, engineHealth: 900 });
ok($('vehicle').classList.contains('collapsed'), 'and then collapses');
ok(!$('vehicle').classList.contains('hidden'), 'without hiding the element');
ok(pct('pip-fuel') === '55.0', 'the gauges keep updating while collapsed',
   pct('pip-fuel'));

msg({ action: 'vehicle', show: false });
ok($('vehicle').classList.contains('slot-out') || $('vehicle').classList.contains('hidden'),
   'leaving the vehicle takes the whole thing away');

console.log('\n-- the collapsed row is about CHANGE: lit, then dim, then gone --');
// A pip lights when its reading changes, drops back to quiet a few seconds
// after the last change, and the row goes if nothing changes for a while
// longer. The clock is the page's Date.now, stepped by hand here.
const cssN = fs.readFileSync(base + 'style.css', 'utf8');
let clock = window.Date.now() + 60000;
window.Date.now = () => clock;
const later = (ms) => { clock += ms; };
const LIT = 4000, DIM = 6000;

let car = { make: 'Karin', model: 'Sultan' };
const newCar = (model) => { msg({ action: 'vehicle', show: false }); car = { make: 'Karin', model }; };
const drive = (extra) => msg(Object.assign({
  action: 'vehicle', show: true, collapsed: true, fuel: 70, engineOn: true, engineHealth: 1000 }, car, extra));
const cls = (id, c) => $(id).classList.contains(c);
const up = (id) => !cls(id, 'hidden');
const lit = (id) => up(id) && !cls(id, 'quiet');
const quiet = (id) => up(id) && cls(id, 'quiet');
const nitroHidden = () => cls('pip-nitrous', 'hidden');
const panelGone = () => cls('vehicle', 'slot-out') || cls('vehicle', 'hidden');
const kit = (level, more) => Object.assign(
  { installed: true, level: level, active: false, ready: true }, more);
const state = () => ['pip-tracker', 'pip-engine', 'pip-fuel', 'pip-nitrous']
  .map((id) => (!up(id) ? '-' : lit(id) ? 'LIT' : 'dim')).join(' ');

ok(ring('pip-nitrous'), 'the nitrous pip has a ring -- the tank is a quantity');
ok($('pip-nitrous').querySelector('.pip-glyph') && !$('pip-nitrous').textContent.trim(),
   'and a drawn glyph, not a typed one');

console.log('\n   getting in');
newCar('Sultan');
drive({ collapsed: false });
ok(state() === '- LIT LIT -', 'engine running: the plate shows engine and fuel lit', state());
ok(nitroHidden(), 'no kit: no nitrous pip, even on the plate');
drive({ collapsed: false, nitrous: { installed: false, level: 0 } });
ok(nitroHidden(), 'installed:false is no kit either');
newCar('Sultan RS');
drive({ collapsed: false, engineOn: false, nitrous: kit(1) });
ok(state() === '- dim dim dim', 'engine OFF: the same plate shows them dim, nitrous included', state());
ok(pct('pip-fuel') === '70.0', 'the reading is still kept underneath');
later(800);
drive({ collapsed: false, nitrous: kit(1) });
ok(state() === '- LIT LIT LIT', 'turn the key and they light', state());
newCar('Kuruma');
drive({ engineOn: false, trackerState: 'spotted' });
ok(lit('pip-tracker') && quiet('pip-engine') && quiet('pip-fuel'),
   'the tracker is the police, not the car: it lights with the engine off', state());

console.log('\n   lit, then dim, then gone');
newCar('Futo');
drive({});
ok(state() === '- LIT LIT -', 'a car just entered is all news', state());
later(LIT - 100); drive({});
ok(state() === '- LIT LIT -', 'still lit just inside the window', state());
later(200); drive({});
ok(state() === '- dim dim -', 'then both drop back to dim', state());
ok(!panelGone(), 'the row is still there while it is dim');
later(DIM); drive({});
ok(panelGone() && state() === '- - - -', 'and with nothing changing it goes away entirely', state());
ok(!cls('pip-fuel', 'quiet') && !cls('pip-engine', 'quiet'), 'leaving nothing marked quiet behind it');
later(60000); drive({});
ok(panelGone(), 'and stays away for as long as nothing moves');

console.log('\n   what counts as a change');
drive({ fuel: 68 });
ok(panelGone(), 'fuel creeping down two points is not news', state());
drive({ fuel: 65 });
ok(state() === '- dim LIT -', 'five points down is: fuel lights, engine sits dim beside it', state());
ok(pct('pip-fuel') === '65.0', 'with its ring at the real reading', pct('pip-fuel'));
later(LIT + DIM + 100); drive({ fuel: 65 });
ok(panelGone(), 'and the row goes again');
drive({ fuel: 67 });
ok(state() === '- dim LIT -', 'two points UP is a refuel: lit', state());
later(LIT + DIM + 100); drive({ fuel: 67 });
drive({ fuel: 67, engineHealth: 960 });
ok(panelGone(), 'a scratch (40 health) is not news', state());
drive({ fuel: 67, engineHealth: 940 });
ok(state() === '- LIT dim -', 'a real knock is: engine lights', state());
later(LIT + DIM + 100); drive({ fuel: 67, engineHealth: 940 });
drive({ fuel: 24, engineHealth: 940 });
ok(lit('pip-fuel') && cls('pip-fuel', 'warn'), 'crossing into the amber band lights the pump amber', $('pip-fuel').className);
later(LIT + 100); drive({ fuel: 24, engineHealth: 940 });
ok(quiet('pip-fuel'), 'and a warning that has been said goes dim like anything else', $('pip-fuel').className);
later(DIM); drive({ fuel: 24, engineHealth: 940 });
ok(panelGone(), 'then away: lit means it just moved, not that it is bad');
drive({ fuel: 24, engineHealth: 940, trackerState: 'searching' });
ok(state() === 'LIT dim dim -', 'the tracker changing state brings the row back', state());
later(LIT + 100); drive({ fuel: 24, engineHealth: 940, trackerState: 'searching' });
ok(state() === 'dim dim dim -', 'and dims with the rest when it stops changing', state());
drive({ fuel: 24, engineHealth: 940, trackerState: 'spotted' });
ok(lit('pip-tracker') && cls('pip-tracker', 'bad'), 'spotted is a change: lit again, red');
drive({ fuel: 24, engineHealth: 940, trackerState: 'clear' });
ok(!up('pip-tracker'), 'clear takes the tracker out of the row altogether');

console.log('\n   nitrous: the ring is the tank');
newCar('Elegy');
drive({}); later(LIT + DIM + 100); drive({});
ok(panelGone(), '(a healthy car, settled: nothing showing)');
drive({ nitrous: kit(1) });
ok(state() === '- dim dim LIT', 'a kit being fitted lights the nitrous pip and brings engine and fuel in dim', state());
ok(cls('pip-nitrous', 'nitro'), 'in its own tone rather than green', $('pip-nitrous').className);
ok(pct('pip-nitrous') === '100.0', 'a full tank reads full', pct('pip-nitrous'));
ok([...$('veh-pips').children].map((n) => n.id).join(' ')
     === 'pip-tracker pip-engine pip-fuel pip-nitrous', 'in the reference order, nitrous last');
ok(/\.pip\.quiet \.pip-ring \{[^}]*display:\s*none/.test(cssN),
   'a quiet pip has no ring: one gauge in the row, not three');
later(LIT + 100); drive({ nitrous: kit(1) });
ok(state() === '- dim dim dim', 'an untouched tank goes dim too', state());
later(DIM); drive({ nitrous: kit(1) });
ok(panelGone(), 'and the row goes: a full tank nobody is using is not news');

drive({ nitrous: kit(0.6, { active: true }) });
ok(state() === '- dim dim LIT', 'boosting brings it straight back, lit, the others dim', state());
ok(pct('pip-nitrous') === '60.0', 'and drains the ring', pct('pip-nitrous'));
ok($('pip-nitrous').className === 'pip nitro gauge',
   'and changes nothing else -- the ring is the boost indicator', $('pip-nitrous').className);
ok(!/#pip-nitrous[^{]*\{[^}]*animation/.test(cssN) && !/@keyframes nitro/.test(cssN),
   'no animation on the pip or its glyph, boosting or not');
ok(/#pip-nitrous \.pip-fill \{ transition: stroke-dashoffset [^,;]*; \}/.test(cssN),
   'the ring\'s dash offset is the one thing that transitions');

// The fast path: the tank moves ten times a second and the vehicle push only
// four, so the row is run again between them.
later(100);
msg(Object.assign({ action: 'nitrous' }, kit(0.25, { active: true })));
ok(pct('pip-nitrous') === '25.0' && lit('pip-nitrous'), 'a nitrous push repaints between vehicle pushes',
   pct('pip-nitrous'));
msg(Object.assign({ action: 'nitrous' }, kit(0, { ready: false })));
ok(pct('pip-nitrous') === '0.0', 'run dry reads zero', pct('pip-nitrous'));
ok(ring('pip-nitrous').getAttribute('data-empty') === '1', 'with no dot left at twelve o\'clock');
ok(lit('pip-nitrous') && cls('pip-nitrous', 'unknown'), 'locked out: lit because it is moving, grey because it cannot be used',
   $('pip-nitrous').className);
later(1500);
msg(Object.assign({ action: 'nitrous' }, kit(0.45, { ready: false })));
ok(pct('pip-nitrous') === '45.0' && lit('pip-nitrous') && cls('pip-nitrous', 'unknown'),
   'the ring refills while still locked out', pct('pip-nitrous'));
later(1500);
msg(Object.assign({ action: 'nitrous' }, kit(1)));
ok(pct('pip-nitrous') === '100.0' && cls('pip-nitrous', 'nitro'), 'and comes back in colour once it is usable again',
   $('pip-nitrous').className);
later(LIT + 100); drive({ nitrous: kit(1) });
ok(state() === '- dim dim dim', 'full again and left alone: dim', state());
later(DIM); drive({ nitrous: kit(1) });
ok(panelGone(), 'then gone');
// The fast path alone is enough to bring a hidden row back: no waiting for
// the next vehicle push.
msg(Object.assign({ action: 'nitrous' }, kit(0.9, { active: true })));
ok(!panelGone() && state() === '- dim dim LIT', 'a nitrous push on its own brings the row straight back', state());

drive({ nitrous: { installed: true, level: 0.5 } });
ok(cls('pip-nitrous', 'nitro'), 'no `ready` field means ready, not locked out', $('pip-nitrous').className);
drive({ nitrous: kit(1.4) });
ok(pct('pip-nitrous') === '100.0', 'over-full clamps to 100', pct('pip-nitrous'));
drive({ nitrous: { installed: true } });
ok(pct('pip-nitrous') === '0.0', 'a missing level is an empty tank, not NaN', pct('pip-nitrous'));
drive({});
ok(nitroHidden(), 'the kit coming off takes the pip out of the row');

console.log('\n   a different car is all news');
later(LIT + DIM + 100); drive({});
ok(panelGone(), '(settled)');
newCar('Jester');
drive({});
ok(state() === '- LIT LIT -', 'getting into another car lights everything again', state());
msg({ action: 'vehicle', show: false });

console.log('\n-- the glyph is the reference mark: a big chevron over a small one --');
{
  const paths = [...$('pip-nitrous').querySelectorAll('.pip-glyph path')]
    .map((p) => p.getAttribute('d').match(/-?\d+(\.\d+)?/g).map(Number));
  const width = (n) => { const xs = n.filter((_, i) => i % 2 === 0); return Math.max(...xs) - Math.min(...xs); };
  const top = (n) => Math.min(...n.filter((_, i) => i % 2 === 1));
  ok(paths.length === 2, 'two chevrons');
  ok(top(paths[0]) < top(paths[1]), 'the first is the upper one');
  ok(width(paths[0]) > width(paths[1]) * 1.6, 'and the upper one is much the larger',
     width(paths[0]) + ' vs ' + width(paths[1]));
}

console.log('\n-- every glyph is centred on its disc --');
// Two things had to be true and were not, and both are pinned here.
//
// 1. ONE SVG PER PIP. The ring and the glyph used to be separate elements, and
//    the browser rounds each element to whole pixels on its own -- so a glyph
//    the layout called centred was painted up to a pixel off its ring. Inside
//    one SVG there is a single coordinate system, 36 units to the disc.
// 2. THE PUMP IS BALANCED BY WEIGHT, ACROSS. Every glyph has equal space
//    above and below it and equal space either side -- except the pump,
//    whose outline runs out to a thin nozzle on the right while nearly all of
//    its ink is the body on the left. Centred on that outline it reads as
//    sitting left, so across it goes on its centre of mass instead.
//
// jsdom has no layout, so this is the geometry itself: the middle of each
// glyph in its own 24-unit art, pushed through the transform that places it,
// has to land on (18, 18).
{
  const CENTRE = 18;
  const place = (g) => {
    const t = g.getAttribute('transform');
    const tr = t.match(/translate\(\s*(-?[\d.]+)[\s,]+(-?[\d.]+)\s*\)/).slice(1).map(Number);
    const sc = Number(t.match(/scale\(\s*(-?[\d.]+)\s*\)/)[1]);
    return (p) => [tr[0] + p[0] * sc, tr[1] + p[1] * sc];
  };
  // Straight-edged polygons only (M x y x y ... Z): the pairs are the corners,
  // and the middle is the middle of everything they span.
  const middle = (g) => {
    const xs = [], ys = [];
    g.querySelectorAll('path').forEach((p) => {
      const n = p.getAttribute('d').match(/-?\d+(\.\d+)?/g).map(Number);
      for (let i = 0; i + 1 < n.length; i += 2) { xs.push(n[i]); ys.push(n[i + 1]); }
    });
    return [(Math.min(...xs) + Math.max(...xs)) / 2, (Math.min(...ys) + Math.max(...ys)) / 2];
  };
  const near = (p) => Math.abs(p[0] - CENTRE) < 0.05 && Math.abs(p[1] - CENTRE) < 0.05;
  const inner = (id) => $(id).querySelector('.pip-glyph > g');

  ['pip-tracker', 'pip-engine', 'pip-fuel', 'pip-nitrous'].forEach((id) => {
    const art = $(id).querySelectorAll('svg');
    ok(art.length === 1 && art[0].getAttribute('viewBox') === '0 0 36 36'
       && art[0].querySelector('.pip-glyph'),
       id + ': ring and glyph share one 36-unit svg', art.length);
  });
  ok(['pip-engine', 'pip-fuel', 'pip-nitrous'].every((id) =>
       $(id).querySelector('svg .pip-ring .pip-fill')
       && /rotate\(-90 18 18\)/.test($(id).querySelector('.pip-ring').getAttribute('transform'))),
     'the ring is in that svg too, turned about the same centre');
  ok(/\.pip-art \{[^}]*inset:\s*0;[^}]*width:\s*100%;[^}]*height:\s*100%/.test(cssN.replace(/\n/g, ' ')),
     'and the svg is the disc: it fills the pip exactly');
  // (?<![-\w]) so that stroke-width does not count as a width.
  ok(!/\.pip-glyph \{[^}]*(?<![-\w])(width|height|left|top):/.test(cssN.replace(/\n/g, ' ')),
     'the glyph is no longer a box of its own for the browser to round');

  const nit = place(inner('pip-nitrous'))(middle(inner('pip-nitrous')));
  ok(near(nit), 'nitrous: the chevrons have equal space all round',
     nit.map((v) => v.toFixed(3)).join(', '));
  const tipMark = $('nitro-hint-icon').querySelector('.nitro-hint-mark');
  const tip = place(tipMark)(middle(tipMark));
  ok($('nitro-hint-icon').tagName.toLowerCase() === 'svg'
     && $('nitro-hint-icon').querySelector('circle.nitro-hint-disc') && near(tip),
     'and the same in the tip, whose disc and mark are one svg as well',
     tip.map((v) => v.toFixed(3)).join(', '));

  // The engine and the pump are bitmaps, so where their ink is was measured
  // off the files rather than worked out. Both have their ink's bounding box
  // in the middle of the canvas (the 24-unit square the image is drawn in).
  // The pump's alpha-weighted centre of mass is 8.9% of the canvas LEFT of
  // that. Re-measure and update the markup and this line if the art changes.
  const FUEL_WEIGHT_X = 12 - 0.089 * 24;
  const eng = place(inner('pip-engine'))([12, 12]);
  ok(near(eng), 'engine: equal space all round', eng.map((v) => v.toFixed(3)).join(', '));
  const fuel = place(inner('pip-fuel'))([FUEL_WEIGHT_X, 12]);
  ok(near(fuel), 'fuel: balanced on its weight across, equal space above and below',
     fuel.map((v) => v.toFixed(3)).join(', '));
  ok(place(inner('pip-fuel'))([12, 12])[0] > CENTRE + 1,
     'which puts the middle of its outline visibly RIGHT of centre, as it should be');
  ['pip-engine', 'pip-fuel'].forEach((id) => {
    const img = $(id).querySelector('mask image');
    const rect = $(id).querySelector('.pip-glyph rect');
    ok(img && fs.existsSync(base + img.getAttribute('href'))
       && rect.getAttribute('fill') === 'currentColor'
       && rect.getAttribute('mask') === 'url(#' + $(id).querySelector('mask').id + ')',
       id + ': the reference art masks a currentColor rect, and the file is there');
  });

  // The tracker is curves, so its extent is read off the art itself: the pin
  // tops out at y=2.5, and the ring it stands on is an ellipse about
  // (12, 17.6), 7.6 x 3.1 with a 2.2 stroke, so the two together run
  // x 3.3..20.7, y 2.5..21.8. Centred on that outline.
  const stand = inner('pip-tracker').querySelector('ellipse');
  const half = Number(stand.getAttribute('stroke-width')) / 2;
  const bottom = Number(stand.getAttribute('cy')) + Number(stand.getAttribute('ry')) + half;
  const pin = place(inner('pip-tracker'))([Number(stand.getAttribute('cx')), (2.5 + bottom) / 2]);
  ok(near(pin), 'tracker: the pin and its ring are centred on the disc', pin.map((v) => v.toFixed(3)).join(', '));
  ok(inner('pip-tracker').querySelector('path[fill-rule="evenodd"]'),
     'and the pin is the solid one from the reference, hole cut out of the path');

  ok(/#veh-foot \{[^}]*justify-content:\s*center/.test(cssN.replace(/\n/g, ' ')),
     'and the row itself is centred in the strip');
}

console.log('\n-- the "Hold [key] to activate nitrous" tip --');
const hint = $('nitro-hint');
const hintText = () => hint.textContent.replace(/\s+/g, ' ').trim();
ok(hint.classList.contains('hidden'), 'hidden until asked for');
msg({ action: 'nitrousHint', show: true, glyph: 'X', device: 'kbm', holdMs: 0 });
ok(!hint.classList.contains('hidden'), 'shows');
ok(hintText() === 'Hold X to activate nitrous', 'reads as the reference does', hintText());
const cap = () => $('nitro-hint-key');
ok(cap().classList.contains('key') && cap().getAttribute('data-glyph') === 'X',
   'the key is a key cap', cap().className);
ok(cap().querySelectorAll('svg').length === 1 && cap().querySelector('svg .g-face') && cap().querySelector('svg text'),
   'cap and letter are one drawing, so the letter cannot sit off its cap');
ok(hint.querySelectorAll('#nitro-hint-icon path').length === 2, 'and the nitrous mark closes the line');
msg({ action: 'nitrousHint', show: true, glyph: 'LSHIFT', device: 'kbm', holdMs: 0 });
ok(cap().classList.contains('wide'), 'a long bind gets the wide cap');
msg({ action: 'nitrousHint', show: true, glyph: 'RMB', device: 'kbm', holdMs: 0 });
ok(cap().classList.contains('mouse') && cap().querySelector('svg image'),
   'a mouse bind is drawn as the button');
msg({ action: 'nitrousHint', show: true, glyph: 'A', device: 'pad', holdMs: 0 });
ok(cap().classList.contains('pad-a') && cap().querySelector('svg circle.g-face'),
   'a pad face button is round, like the button on the pad, and gets its colour');
msg({ action: 'inputDevice', device: 'pad', pad: 'ps' });
ok(cap().classList.contains('face') && !cap().classList.contains('pad-a')
   && (cap().querySelector('path.g-ink').getAttribute('d').match(/M/g) || []).length === 2,
   'on a PlayStation pad the same bind is redrawn as the cross', cap().className);
ok(!hint.classList.contains('hidden'), 'and the tip stays up while it is');
msg({ action: 'inputDevice', device: 'pad', pad: 'xbox' });
msg({ action: 'nitrousHint', show: true, refresh: true, glyph: 'X', device: 'kbm' });
ok(cap().classList.contains('key') && cap().textContent === 'X',
   'putting the pad down swaps the button for the key');
msg({ action: 'nitrousHint', show: true, device: 'kbm', holdMs: 0 });
ok($('nitro-hint-key').textContent === '' && hintText() === 'Hold to activate nitrous',
   'no bind: no cap, and the line still reads', hintText());
msg({ action: 'nitrousHint', show: false });
ok(hint.classList.contains('hidden'), 'and it can be taken down');

const css2 = fs.readFileSync(base + 'style.css', 'utf8');
const collapsedRule = css2.slice(css2.indexOf('#vehicle.collapsed {'));
ok(/background:\s*none/.test(collapsedRule.slice(0, 200)),
   'collapsed has no plate behind it');
// max-height/opacity rather than `display: none`: the head has to ANIMATE
// away and display is not animatable. Asserting the exact property pinned this
// to one implementation of "gone"; assert the outcome instead.
const headCollapse = css2.slice(css2.indexOf('#vehicle.collapsed #veh-head {'), );
ok(/max-height:\s*0/.test(headCollapse.slice(0, 240))
   && /opacity:\s*0/.test(headCollapse.slice(0, 240)),
   'and the announcement half is gone entirely');

console.log('\n-- the panel is two bands, and the badge stops at the barrier --');
// jsdom has no layout, so these check the STRUCTURE and the rules that produce
// the banding rather than measuring it. Between them they are what stops a
// future edit quietly putting the badge back over the status strip.
ok($('veh-logo').parentElement.id === 'veh-logo-clip', 'the badge sits inside its clip window');
ok($('veh-logo-clip').parentElement.id === 'veh-head', 'and the clip window is inside the head');
ok($('veh-pips').parentElement.id === 'veh-foot', 'the pips are in the foot band, not the head');
ok($('veh-make').parentElement.id === 'veh-head', 'the names are in the head band');

const css = fs.readFileSync(base + 'style.css', 'utf8');
// The selector must start a LINE. `#veh-foot` also appears inside
// `#vehicle.collapsed #veh-foot`, and a bare indexOf finds whichever comes
// first in the file rather than the base rule being asked about.
// A selector can legitimately appear MORE THAN ONCE at the top level --
// #veh-foot has a transition-only block early on and its real block later --
// so returning the first match asks the wrong block about `border-top` and
// reports a property missing that is plainly there. Concatenate every
// top-level block for the selector instead.
const rule = (sel) => {
  const out = [];
  const needle = '\n' + sel + ' {';
  let i = css.indexOf(needle);
  while (i >= 0) {
    out.push(css.slice(i, css.indexOf('}', i)));
    i = css.indexOf(needle, i + 1);
  }
  return out.join('\n');
};
ok(/overflow:\s*hidden/.test(rule('#veh-logo-clip')),
   'the clip window clips -- without this the mark bleeds into the status strip');
ok(/inset:\s*0/.test(rule('#veh-logo-clip')), 'and it spans the head exactly');
ok(/border-top:/.test(rule('#veh-foot')),
   'the barrier is the foot band border, so it reaches both edges by construction');
ok(/align-self:\s*stretch/.test(rule('#veh-foot')),
   'and the band is full width rather than centred on its content');
ok(/background:\s*rgba/.test(rule('#veh-foot')),
   'the strip is a different shade from the plate above it');
ok(/padding:\s*0;/.test(rule('#vehicle')),
   'the plate has no padding of its own -- it would show as a gap the barrier could not span');

console.log('\n-- the map panels are set in GTA Art Deco by default --');
ok(/--ff-slots,\s*'GTAArtDeco'/.test(css),
   'Art Deco is the shipped default for the slot stack, not just a Font row option');

console.log('\n-- the editor offers the badge as its own element --');
msg({ action: 'openEditor', offsets: {}, native: { scaleW: 0.663, rounded: 1 } });
const labels = [...d.querySelectorAll('#editor-list .ed-item')]
  .map((n) => n.querySelector('.ed-name') ? n.querySelector('.ed-name').textContent : n.textContent);
ok(labels.some((t) => /Vehicle badge/.test(t)), 'a "Vehicle badge" row exists',
   labels.join(' | '));

// Select it and check it is offered the rows an IMAGE has, and none of the
// text ones -- a Font row on a picture is a control that does nothing.
const badgeIdx = [...d.querySelectorAll('#editor-list .ed-item')]
  .findIndex((n) => /Vehicle badge/.test(n.textContent));
[...d.querySelectorAll('#editor-list .ed-item')][badgeIdx].dispatchEvent(
  new window.MouseEvent('click', { bubbles: true }));
const rows = [...d.querySelectorAll('#editor-props .ed-prop .ed-plabel')]
  .map((n) => n.textContent.trim());
const has = (t) => rows.indexOf(t) >= 0;
ok(has('Position X') && has('Position Y'), 'badge has Position rows', rows.join(' | '));
ok(has('Width') && has('Height'), 'badge has Width and Height');
ok(has('Opacity'), 'badge has Opacity');
ok(!has('Font') && !has('Letter spacing') && !has('Text align'),
   'and none of the text rows', rows.join(' | '));

console.log('\n-- the page survives makes.js not being served --');
// This is the fault that actually happened in game: makes.js is a separate file
// and a server that has not rescanned the resource folder 404s it. Everything
// else has to keep working, silently and without throwing -- a HUD that dies
// because a decoration is missing is far worse than one with no badges.
{
  const d2 = new JSDOM(html, { url: 'http://localhost/', runScripts: 'outside-only', pretendToBeVisual: true });
  const w2 = d2.window;
  w2.Element.prototype.scrollIntoView = function () {};
  let threw = null;
  try {
    // app.js ONLY -- makes.js deliberately not loaded.
    w2.eval(fs.readFileSync(base + 'app.js', 'utf8'));
    w2.document.dispatchEvent(new w2.Event('DOMContentLoaded'));
    w2.dispatchEvent(new w2.MessageEvent('message', { data: {
      action: 'vehicle', show: true, make: 'Truffade', model: 'Thrax',
      fuel: 70, engineOn: true, engineHealth: 1000 } }));
  } catch (e) { threw = e; }
  ok(!threw, 'app.js loads and runs without the table', threw && threw.message);
  ok(w2.document.getElementById('veh-model').textContent === 'THRAX',
     'the panel still fills in, badge or no badge',
     w2.document.getElementById('veh-model').textContent);
  ok(!w2.document.getElementById('vehicle').classList.contains('badged'),
     'and simply does not badge');
}

console.log(fails ? '\n' + fails + ' FAILING\n' : '\nall checks passed\n');
process.exit(fails ? 1 : 0);
