/* Headless test for the race HUD (PROGRESS / position plate / clock).
 *
 *   node html/laptimer.test.js
 *
 * Not shipped to clients -- not in fxmanifest's files{}. Run it after
 * touching #lap-hud's markup, CSS or the lap-hud functions in app.js. */
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
window.Element.prototype.scrollIntoView = function () { this.__scrolled = true; };

const st = d.createElement('style');
st.textContent = css;
d.head.appendChild(st);

window.fetch = function () { return Promise.resolve({ json: () => Promise.resolve({}) }); };
window.GetParentResourceName = () => 'vice_hud';

window.eval(fs.readFileSync(base + 'app.js', 'utf8'));
d.dispatchEvent(new window.Event('DOMContentLoaded'));

const msg = (data) => window.dispatchEvent(new window.MessageEvent('message', { data }));
const $ = (id) => d.getElementById(id);
const plate = () => $('lap-cp-row').textContent.replace(/\s+/g, ' ').trim();
const progress = () => $('lap-progress').textContent.replace(/\s+/g, ' ').trim();
const race = (extra) => msg(Object.assign({ action: 'lapHud', show: true }, extra));

console.log('\n-- hidden until shown --');
msg({ action: 'lapHud', show: false });
ok($('lap-hud').classList.contains('hidden'), 'race hud hidden when show:false');

console.log('\n-- the reference frame: PROGRESS 30%, 1 / 6, 00:30.39 --');
race({ position: 1, racers: 6, progress: 0.30, lap: 1, laps: 1, cp: 5, cpTotal: 16,
       elapsedMs: 30390, running: false });
ok(!$('lap-hud').classList.contains('hidden'), 'race hud visible');
ok(progress() === 'PROGRESS 30%', 'progress row', progress());
ok(plate() === '1 / 6', 'the plate is position in the field', plate());
ok($('lap-timer').textContent === '00:30.39', 'the clock', $('lap-timer').textContent);
ok([...$('lap-hud').children].map((n) => n.id).join(' ')
     === 'lap-badge lap-progress lap-cp-plate lap-timer',
   'rows in the reference order: progress, plate, clock');

console.log('\n-- the lap badge is only for races that have laps --');
ok($('lap-badge').classList.contains('hidden'), 'point to point (laps: 1): no LAP row');
race({ position: 2, racers: 6, lap: 2, laps: 3, cp: 4, cpTotal: 10, elapsedMs: 0 });
ok(!$('lap-badge').classList.contains('hidden'), 'three laps: LAP row shown');
ok($('lap-cur').textContent === '2' && $('lap-total').textContent === '3', 'and it reads 2/3',
   [$('lap-cur').textContent, $('lap-total').textContent]);

console.log('\n-- progress without a route fraction is worked out from checkpoints --');
// lap 2 of 3, 4 of 10 this lap: (10 + 4) / 30 = 46.7%
ok(progress() === 'PROGRESS 47%', 'checkpoints cleared across every lap', progress());
race({ lap: 1, laps: 1, cp: 0, cpTotal: 16, elapsedMs: 0 });
ok(progress() === 'PROGRESS 0%', 'nothing cleared is 0%', progress());
race({ lap: 1, laps: 1, cp: 16, cpTotal: 16, elapsedMs: 0 });
ok(progress() === 'PROGRESS 100%', 'all of them is 100%', progress());
race({ lap: 1, laps: 1, elapsedMs: 0 });
ok(progress() === 'PROGRESS 0%', 'no checkpoint data at all is 0%, not NaN', progress());

console.log('\n-- an explicit progress wins, and clamps --');
race({ progress: 0.074, cp: 9, cpTotal: 10, elapsedMs: 0 });
ok(progress() === 'PROGRESS 7%', '0.074 reads 7%, whatever the checkpoints say', progress());
race({ progress: 1.6, elapsedMs: 0 });
ok(progress() === 'PROGRESS 100%', 'over 1 clamps to 100%', progress());
race({ progress: -0.2, elapsedMs: 0 });
ok(progress() === 'PROGRESS 0%', 'below 0 clamps to 0%', progress());

console.log('\n-- no position sent: the plate falls back to checkpoints --');
race({ lap: 1, laps: 2, cp: 10, cpTotal: 16, elapsedMs: 19950, running: true });
ok(plate() === '10 / 16', 'checkpoint count on the plate', plate());
ok($('lap-timer').textContent === '00:19.95', 'timer text matches elapsedMs', $('lap-timer').textContent);
race({ position: 4, elapsedMs: 0 });
ok(plate() === '4 / 4', 'a position with no field size does not print "undefined"', plate());

console.log('\n-- stopping (running:false) freezes the timer at the last pushed value --');
race({ position: 1, racers: 6, progress: 1, elapsedMs: 88893, running: false });
ok($('lap-timer').textContent === '01:28.89', 'timer frozen at final elapsedMs', $('lap-timer').textContent);

console.log('\n-- it is drawn the way the reference draws it --');
const rule = (sel) => {
  const i = css.indexOf('\n' + sel + ' {');
  return i < 0 ? '' : css.slice(i, css.indexOf('}', i));
};
ok(/right:/.test(rule('#lap-hud')) && /bottom:/.test(rule('#lap-hud'))
   && /align-items:\s*flex-end/.test(rule('#lap-hud')),
   'bottom right, rows right-aligned');
ok(/conic-gradient/.test(rule('#lap-cp-plate')), 'the plate is chequered');
ok(/--nav-accent/.test(rule('#lap-cp-plate::after')), 'with the accent bar down its right edge');
ok(/background:\s*rgba/.test(rule('#lap-progress-chip')), 'the percentage sits in its own dark chip');
ok(!/background/.test(rule('#lap-timer')), 'and the clock is unboxed');
ok(!$('lap-cp-track'), 'the old row of checkpoint pips is gone');

console.log('\n-- the prompts and the honor toast stand clear of it --');
// The race block takes the bottom-right corner both of them normally use.
ok($('stage').classList.contains('racing'), 'the stage is marked as racing while it is up');
ok(/#stage\.racing #prompts,\s*#stage\.racing #honor \{ bottom:/.test(css),
   'and that lifts the prompts and the honor toast above the block');

console.log('\n-- hides on show:false --');
msg({ action: 'lapHud', show: false });
ok($('lap-hud').classList.contains('hidden'), 'race hud hidden again');
ok(!$('stage').classList.contains('racing'), 'and the corner is handed back');

console.log('\n-- the title card: chip, big line, chip --');
const card = $('race-card');
const row = (id) => $(id).textContent;
ok(card.classList.contains('hidden'), 'hidden until shown');
msg({ action: 'raceCard', show: true, kind: 'title', holdMs: 0,
      series: "HIT 'N' RUN VC", name: 'SALTON TO WANING SANDS', type: 'GROUP RACE' });
ok(!card.classList.contains('hidden') && !card.classList.contains('result'), 'shows as a title card');
ok(row('race-card-top') === "HIT 'N' RUN VC" && row('race-card-main') === 'SALTON TO WANING SANDS'
   && row('race-card-sub') === 'GROUP RACE', 'the three rows of the reference',
   [row('race-card-top'), row('race-card-main'), row('race-card-sub')]);
msg({ action: 'raceCard', show: true, kind: 'title', holdMs: 0, name: 'SALTON TO WANING SANDS' });
ok(row('race-card-top') === '' && row('race-card-sub') === '', 'rows left out are emptied, not left stale');
ok(/\.race-chip:empty \{ display: none; \}/.test(css), 'and an empty chip is not drawn');

console.log('\n-- the result card: placing over time --');
msg({ action: 'raceCard', show: true, kind: 'result', holdMs: 0, position: 1, timeMs: 88893 });
ok(card.classList.contains('result'), 'shows as a result card');
ok(row('race-card-main') === '1ST' && row('race-card-sub') === '01:28.893' && row('race-card-top') === '',
   'the reference frame: 1ST over 01:28.893', [row('race-card-main'), row('race-card-sub')]);
const place = (n) => { msg({ action: 'raceCard', show: true, kind: 'result', holdMs: 0, position: n }); return row('race-card-main'); };
ok([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map(place).join(' ')
     === '1ST 2ND 3RD 4TH 11TH 12TH 13TH 21ST 22ND 23RD 101ST 111TH', 'ordinals, including the teens');
ok(row('race-card-sub') === '', 'no time sent: no time chip');
msg({ action: 'raceCard', show: true, kind: 'result', holdMs: 0, label: 'DNF', timeMs: 0 });
ok(row('race-card-main') === 'DNF' && row('race-card-sub') === '00:00.000', 'a label replaces the ordinal');
msg({ action: 'raceCard', show: false });
ok(card.classList.contains('hidden'), 'and it can be hidden');
ok(!/#race-card[^{]*\{[^}]*(transition|animation)/.test(css) && !/\.race-chip[^{]*\{[^}]*(transition|animation)/.test(css),
   'no transition: the reference cuts both cards in and out');

console.log('\n-- 3, 2, 1, go --');
const count = $('race-count');
msg({ action: 'raceCountdown', show: true, value: 3 });
ok(!count.classList.contains('hidden') && count.textContent === '3', 'one beat: a digit');
msg({ action: 'raceCountdown', show: true, value: 'GO' });
ok(count.textContent === 'go', 'one beat: go, lower case as in the reference', count.textContent);
msg({ action: 'raceCountdown', show: false });
ok(count.classList.contains('hidden'), 'and it can be cleared');
// The whole run, on the page's own clock: 3 at 0 ms, 2 at 1000, 1 at 2000, go
// at 3000; digits up for 300 ms, go for 1100 ms. Fake timers, real handler.
{
  const real = window.setTimeout, realClear = window.clearTimeout;
  let now = 0, id = 0; const q = [];
  window.setTimeout = (fn, ms) => { q.push({ id: ++id, at: now + (ms || 0), fn }); return id; };
  window.clearTimeout = (h) => { const i = q.findIndex((e) => e.id === h); if (i >= 0) q.splice(i, 1); };
  const advance = (to) => {
    for (;;) {
      q.sort((a, b) => a.at - b.at);
      if (!q.length || q[0].at > to) break;
      const e = q.shift(); now = e.at; e.fn();
    }
    now = to;
  };
  const seen = () => (count.classList.contains('hidden') ? '-' : count.textContent);
  msg({ action: 'raceCountdown', show: true, from: 3 });
  const samples = [0, 150, 299, 301, 999, 1001, 1299, 1301, 2001, 2301, 3001, 4099, 4101]
    .map((t) => { advance(t); return seen(); }).join(' ');
  ok(samples === '3 3 3 - - 2 2 - 1 - go go -',
     'the reference cadence: 300 ms digits a second apart, then go for 1100 ms', samples);
  window.setTimeout = real; window.clearTimeout = realClear;
}

console.log(fails === 0 ? '\nALL PASS' : ('\n' + fails + ' FAILURES'));
process.exit(fails === 0 ? 0 : 1);
