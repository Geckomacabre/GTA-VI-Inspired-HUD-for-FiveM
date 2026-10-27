/*
    html/sfx.js outside the game: `node tests/sfx_test.js`.

    The browser is replaced by just enough of one to run the file as it is: an
    AudioContext that records what it was asked to play, and a fetch that reads
    html/sounds from disk. What is checked is which recording each kind of sound
    ends up being, indoors and out, soft and hard, and that a kind with no
    recording is still synthesised rather than silent.
*/
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.resolve(__dirname, '..');
const sounds = path.join(root, 'html', 'sounds');

let failed = 0, passed = 0;

function check(name, ok, detail) {
    if (ok) { passed++; return; }
    failed++;
    console.log(`  FAIL  ${name}   ${detail === undefined ? '' : detail}`);
}

function browser(withSounds) {
    const played = [];      // { file } for a recording, { synth: true } for anything synthesised
    const param = () => ({ value: 0, setValueAtTime() {}, exponentialRampToValueAtTime() {} });
    const node = (extra) => Object.assign({ connect(to) { return to; } }, extra);

    class AudioContext {
        constructor() { this.currentTime = 0; this.sampleRate = 48000; this.state = 'running'; this.destination = node({}); }
        resume() {}
        createGain() { return node({ gain: param() }); }
        createStereoPanner() { return node({ pan: param() }); }
        createBiquadFilter() { return node({ frequency: param(), Q: param(), type: '' }); }
        createOscillator() {
            return node({ frequency: param(), start() { played.push({ synth: true }); }, stop() {} });
        }
        createBuffer(_, length) { return { getChannelData: () => new Float32Array(length) }; }
        createBufferSource() {
            const src = node({
                buffer: null, loop: false, playbackRate: param(),
                // A buffer that came from a file is a recording; any other is the synthesiser's noise.
                start() {
                    if (src.buffer && src.buffer.file) played.push({ file: src.buffer.file, rate: src.playbackRate.value });
                    else played.push({ synth: true });
                },
                stop() {},
            });
            return src;
        }
        decodeAudioData(bytes, ok, bad) {
            // A real Ogg starts with "OggS"; anything else is refused, as a browser would.
            const head = Buffer.from(bytes.slice(0, 4)).toString('latin1');
            if (head === 'OggS') ok({ file: bytes.file }); else bad(new Error('not audio'));
        }
    }

    const fetch = async (url) => {
        const file = path.join(root, 'html', url);
        if (!withSounds || !fs.existsSync(file)) return { ok: false, status: 404 };

        const data = fs.readFileSync(file);
        return {
            ok: true,
            status: 200,
            json: async () => JSON.parse(data.toString('utf8')),
            arrayBuffer: async () => {
                const bytes = data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength);
                bytes.file = path.basename(file);
                return bytes;
            },
        };
    };

    const listeners = {};
    const window = { AudioContext, addEventListener(type, fn) { listeners[type] = fn; } };
    const context = { window, fetch, console, Math, Promise, Object, Float32Array, Buffer };

    vm.createContext(context);
    vm.runInContext(fs.readFileSync(path.join(root, 'html', 'sfx.js'), 'utf8') + '\nthis.Sfx = Sfx;', context);

    return { Sfx: context.Sfx, played, send: (data) => listeners.message({ data }) };
}

(async () => {
    const manifest = JSON.parse(fs.readFileSync(path.join(sounds, 'manifest.json'), 'utf8'));
    const listed = Object.values(manifest.sounds).flat();

    // ---- every file the manifest names is there, is an Ogg, and nothing is there unnamed
    const onDisk = fs.readdirSync(sounds).filter((f) => f.endsWith('.ogg'));
    const missing = listed.filter((f) => !onDisk.includes(f));
    const extra = onDisk.filter((f) => !listed.includes(f));

    check('every file the manifest names exists', missing.length === 0, missing.join(', '));
    check('and there is no file it does not name', extra.length === 0, extra.join(', '));
    check('each is an Ogg', onDisk.every((f) => fs.readFileSync(path.join(sounds, f)).slice(0, 4).toString('latin1') === 'OggS'));
    check('every set has a level', Object.keys(manifest.sounds).every((k) => typeof manifest.levels[k] === 'number'));

    if (listed.length > 0) {
        const b = browser(true);
        await b.Sfx.load();

        const one = (kind, indoor, hard) => {
            b.played.length = 0;
            b.send({ action: 'sfx', kind, volume: 0.5, pan: 0, indoor, hard });
            return b.played[0] || {};
        };
        const from = (kind, indoor, hard) => {
            const file = one(kind, indoor, hard).file;
            return file ? Object.keys(manifest.sounds).find((k) => manifest.sounds[k].includes(file)) : null;
        };

        check('a hard bounce outdoors is the dry bounce', from('bounce', false, 0.7) === 'bounce', from('bounce', false, 0.7));
        check('a soft one the soft take', from('bounce', false, 0.2) === 'bounce_soft', from('bounce', false, 0.2));
        check('indoors the arena has its say', from('bounce', true, 0.7) === 'bounce_arena', from('bounce', true, 0.7));
        check('a dribble is a bounce', from('dribble', false, 0.95) === 'bounce', from('dribble', false, 0.95));
        check('walked up, a soft one', from('dribble', false, 0.6) === 'bounce_soft', from('dribble', false, 0.6));
        check('in the arena, the arena\'s', from('dribble', true, 0.6) === 'bounce_arena_soft', from('dribble', true, 0.6));
        check('the rim is the rim', from('rim', false, 0.7) === 'rim' && from('rim', true, 0.3) === 'rim_arena_soft');
        check('the backboard has its own sound', from('board', false, 0.7) === 'board' && from('board', true, 0.7) === 'board_arena');
        check('a net ripped is the hard take', from('net', false, 0.95) === 'net_hard', from('net', false, 0.95));
        check('a net with no hard indoor take... has one', from('net', true, 0.95) === 'net_arena_hard', from('net', true, 0.95));
        check('a soft net indoors falls back to the arena net', from('net', true, 0.2) === 'net_arena', from('net', true, 0.2));
        check('a catch is a catch', from('catch', false, 0.7) === 'catch' && from('catch', true, 0.7) === 'catch_arena');
        check('shoes squeak indoors', from('squeak', true, 0.6) === 'squeak_arena', from('squeak', true, 0.6));
        check('and scrape outdoors', from('squeak', false, 0.6) === 'squeak', from('squeak', false, 0.6));
        check('a splash has no recording and is synthesised', one('splash', false, 0.8).synth === true);
        check('an unknown kind is silence, not an error', Object.keys(one('nonsense', false, 0.8)).length === 0);

        // Not the same take twice running, and never far off true pitch.
        const files = [], rates = [];
        for (let i = 0; i < 40; i++) {
            const p = one('bounce', false, 0.7);
            files.push(p.file); rates.push(p.rate);
        }
        check('never the same take twice running', files.every((f, i) => i === 0 || f !== files[i - 1]));
        check('all the takes get used', new Set(files).size === manifest.sounds.bounce.length, new Set(files).size);
        check('each at very nearly its true pitch', rates.every((r) => r > 0.92 && r < 1.05));

        b.played.length = 0;
        b.send({ action: 'sfx', kind: 'bounce', volume: 0.001, pan: 0 });
        check('too quiet to hear is not played', b.played.length === 0);
    }

    // ---- with no recordings at all, everything is still heard
    const bare = browser(false);
    await bare.Sfx.load();

    for (const kind of ['bounce', 'dribble', 'rim', 'board', 'net', 'catch', 'body', 'splash']) {
        bare.played.length = 0;
        bare.send({ action: 'sfx', kind, volume: 0.5, pan: 0, indoor: true, hard: 0.7 });
        check(`without recordings a ${kind} is synthesised`, bare.played.length > 0 && bare.played.every((p) => p.synth));
    }

    console.log(`sfx: ${passed} passed, ${failed} failed`);
    process.exit(failed ? 1 : 0);
})().catch((err) => { console.error(err); process.exit(1); });
