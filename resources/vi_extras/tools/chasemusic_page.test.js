// app.js with a fake Audio, fetch and clock.
const fs = require('fs');
const vm = require('vm');
const src = fs.readFileSync(require('path').join(__dirname, '..', 'vi_chasemusic', 'html', 'app.js'), 'utf8');

let now = 0;
const timers = [];
const posts = [];
let readyAnswered = false;
class FakeAudio {
    constructor() { this.listeners = {}; this.paused = true; this.ended = false; this.volume = 1; this.src = ''; this.plays = 0; }
    addEventListener(n, f) { (this.listeners[n] = this.listeners[n] || []).push(f); }
    emit(n) { (this.listeners[n] || []).forEach((f) => f()); }
    play() { this.paused = false; this.plays++; return Promise.resolve(); }
    pause() { this.paused = true; }
    removeAttribute(a) { if (a === 'src') this.src = ''; }
    load() {}
}
let audio;
let onMessage;
const ctx = {
    Audio: function () { audio = new FakeAudio(); return audio; },
    GetParentResourceName: () => 'vi_extras',
    fetch: (url, opts) => { posts.push({ url, body: JSON.parse(opts.body) }); return Promise.resolve({ ok: readyAnswered }); },
    window: { addEventListener: (n, f) => { if (n === 'message') onMessage = f; } },
    setInterval: (f, ms) => timers.push({ f, ms, at: ms, repeat: true }),
    setTimeout: (f, ms) => timers.push({ f, ms, at: now + ms, repeat: false }),
    Date: { now: () => now },
    encodeURIComponent, JSON, Math, Number, String, Promise, console,
};
vm.createContext(ctx);
vm.runInContext(src, ctx);

function advance(ms) {
    const end = now + ms;
    while (now < end) {
        now += 10;
        for (const t of timers.slice()) {
            if (now >= t.at) {
                t.f();
                if (t.repeat) t.at += t.ms; else timers.splice(timers.indexOf(t), 1);
            }
        }
    }
}
const send = (m) => onMessage({ data: m });
const check = (c, m) => { if (!c) { console.log('FAIL: ' + m); process.exit(1); } console.log('ok   ' + m); };

(async () => {
    await new Promise((r) => setImmediate(r));
    check(posts[0].url === 'https://vi_extras/ready', 'says ready');
    advance(1100);
    await new Promise((r) => setImmediate(r));
    check(posts.filter((p) => p.url.endsWith('/ready')).length >= 2, 'retries ready until answered');
    readyAnswered = true;

    send({ type: 'play', file: 'music/b Chase#1.mp3', volume: 0, serial: 3, stallMs: 400 });
    check(audio.src === '../music/b%20Chase%231.mp3' && !audio.paused && audio.volume === 0, 'plays ' + audio.src);
    send({ type: 'volume', volume: 0.3 });
    check(audio.volume === 0.3, 'volume 0.3');

    for (let i = 0; i < 10; i++) { advance(100); send({ type: 'tick' }); }
    check(!audio.paused, 'ticks keep it playing');
    advance(600);
    check(audio.paused, 'no ticks for 400 ms: paused where it is');
    send({ type: 'tick' });
    advance(260);
    check(!audio.paused, 'ticks back: plays on');

    audio.emit('ended');
    check(posts[posts.length - 1].url.endsWith('/ended') && posts[posts.length - 1].body.serial === 3, 'ended reported with serial');
    send({ type: 'stop' });
    check(audio.paused && audio.src === '', 'stop');
    audio.emit('error');
    check(!posts[posts.length - 1].url.endsWith('/failed'), 'error after stop not reported');
    send({ type: 'play', file: 'music/x.mp3', volume: 0, serial: 4, stallMs: 400 });
    audio.emit('error');
    check(posts[posts.length - 1].url.endsWith('/failed') && posts[posts.length - 1].body.serial === 4, 'failed reported');
    console.log('done');
})();
