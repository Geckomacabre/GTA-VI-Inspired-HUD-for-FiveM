/*
    Ball sounds.

    The ball's physics is ours, not the game's, so the game never plays its own
    impact sounds for it. They are played from here.

    Recorded sounds are used where there are any: html/sounds/manifest.json
    lists, for each kind of sound, the files that are takes of it, and one is
    picked at random each time (never the same one twice running), at a pitch a
    few percent either side of true so that ten bounces are not one bounce ten
    times. A kind can have separate sets for indoors (`_arena`: the hall is in
    the recording) and for a soft or a hard contact (`_soft`, `_hard`); the most
    specific set there is gets used.

    With no manifest, or no file for a kind, that kind is synthesised instead,
    as all of them were before there were recordings: a bounce is a low thump
    with a short slap on the front of it, the rim is a handful of partials that
    don't line up, the net and a splash are shaped noise.
*/
const Sfx = (() => {
    let ctx = null;
    let hiss = null;

    const bank = {};        // kind -> [AudioBuffer]
    const last = {};        // kind -> index played last
    let levels = {};        // kind -> gain, from the manifest
    let loading = null;

    // A kind with no recording of its own borrows another's before it is synthesised.
    const BORROW = { dribble: 'bounce', board: 'bounce', catch: 'body' };

    // How hard (0..1) a contact has to be not to count as a soft one. A dribble
    // is never gentle by this measure, so its line is drawn higher: walking the
    // ball up is the soft take, driving with it the hard one.
    const SOFT_BELOW = { dribble: 0.75 };

    // The set to play for a kind: indoors before out, then how hard, then plain.
    function setFor(kind, indoor, hard) {
        const how = hard < (SOFT_BELOW[kind] || 0.45) ? '_soft' : hard > 0.88 ? '_hard' : '';

        for (const base of [kind, BORROW[kind]]) {
            if (!base) continue;

            const tries = indoor
                ? [base + '_arena' + how, base + '_arena', base + how, base]
                : [base + how, base];

            for (const key of tries) {
                if (bank[key] && bank[key].length) return key;
            }
        }

        return null;
    }

    function audio() {
        if (!ctx) {
            const Ctor = window.AudioContext || window.webkitAudioContext;
            if (!Ctor) return null;
            ctx = new Ctor();
        }
        if (ctx.state === 'suspended') ctx.resume();
        return ctx;
    }

    //--------------------------------------------------------------------------
    // Recordings
    //--------------------------------------------------------------------------

    async function fetchBuffer(c, file) {
        const res = await fetch('sounds/' + file);
        if (!res.ok) throw new Error(file + ': ' + res.status);

        const bytes = await res.arrayBuffer();

        // The callback form: older embedded Chromiums don't return a promise.
        return new Promise((resolve, reject) => c.decodeAudioData(bytes, resolve, reject));
    }

    function load() {
        if (loading) return loading;

        loading = (async () => {
            const c = audio();
            if (!c) return;

            let manifest;

            try {
                const res = await fetch('sounds/manifest.json');
                if (!res.ok) return;
                manifest = await res.json();
            } catch (err) {
                return;     // no recordings: everything is synthesised
            }

            levels = manifest.levels || {};

            for (const [kind, files] of Object.entries(manifest.sounds || {})) {
                for (const file of files) {
                    try {
                        (bank[kind] = bank[kind] || []).push(await fetchBuffer(c, file));
                    } catch (err) {
                        console.warn('[gk_basketball] sound not loaded:', err && err.message || err);
                    }
                }
            }
        })();

        return loading;
    }

    function take(kind) {
        const takes = bank[kind];
        if (!takes || takes.length === 0) return null;

        let i = Math.floor(Math.random() * takes.length);
        if (takes.length > 1 && i === last[kind]) i = (i + 1) % takes.length;
        last[kind] = i;

        return takes[i];
    }

    //--------------------------------------------------------------------------
    // Synthesis, for whatever has no recording
    //--------------------------------------------------------------------------

    function noise(c) {
        if (!hiss) {
            hiss = c.createBuffer(1, c.sampleRate, c.sampleRate);
            const data = hiss.getChannelData(0);
            for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
        }
        const src = c.createBufferSource();
        src.buffer = hiss;
        src.loop = true;
        return src;
    }

    // One decaying sine, optionally sliding in pitch.
    function tone(c, out, t, from, to, peak, length) {
        const osc = c.createOscillator();
        const gain = c.createGain();
        osc.frequency.setValueAtTime(from, t);
        if (to !== from) osc.frequency.exponentialRampToValueAtTime(to, t + length);
        gain.gain.setValueAtTime(0.0001, t);
        gain.gain.exponentialRampToValueAtTime(peak, t + 0.004);
        gain.gain.exponentialRampToValueAtTime(0.0001, t + length);
        osc.connect(gain).connect(out);
        osc.start(t);
        osc.stop(t + length + 0.02);
    }

    // A burst of filtered noise, the filter sliding from one frequency to another.
    function burst(c, out, t, type, from, to, q, peak, attack, length) {
        const src = noise(c);
        const filter = c.createBiquadFilter();
        const gain = c.createGain();
        filter.type = type;
        filter.Q.value = q;
        filter.frequency.setValueAtTime(from, t);
        filter.frequency.exponentialRampToValueAtTime(to, t + length);
        gain.gain.setValueAtTime(0.0001, t);
        gain.gain.exponentialRampToValueAtTime(peak, t + attack);
        gain.gain.exponentialRampToValueAtTime(0.0001, t + length);
        src.connect(filter).connect(gain).connect(out);
        src.start(t, Math.random() * 0.5);
        src.stop(t + length + 0.02);
    }

    const synth = {
        bounce(c, out, t) {
            tone(c, out, t, 210, 78, 0.9, 0.17);
            tone(c, out, t, 430, 300, 0.22, 0.09);              // the ring of the air in it
            burst(c, out, t, 'bandpass', 1500, 700, 0.8, 0.35, 0.002, 0.035);
        },
        dribble(c, out, t) {
            tone(c, out, t, 190, 74, 0.8, 0.15);
            burst(c, out, t, 'bandpass', 1300, 650, 0.8, 0.28, 0.002, 0.03);
        },
        board(c, out, t) {
            tone(c, out, t, 160, 70, 0.9, 0.2);
            tone(c, out, t, 320, 240, 0.25, 0.12);
            burst(c, out, t, 'lowpass', 1200, 400, 0.6, 0.3, 0.002, 0.06);
        },
        rim(c, out, t) {
            for (const [freq, peak, length] of [[523, 0.45, 0.34], [1318, 0.3, 0.26], [2043, 0.2, 0.2], [2910, 0.12, 0.14]]) {
                tone(c, out, t, freq, freq * 0.995, peak, length);
            }
            tone(c, out, t, 150, 90, 0.5, 0.08);                // the ball's part of it
            burst(c, out, t, 'highpass', 3000, 2000, 0.5, 0.12, 0.001, 0.05);
        },
        net(c, out, t) {
            burst(c, out, t, 'bandpass', 3200, 1100, 0.9, 0.5, 0.03, 0.3);
        },
        splash(c, out, t) {
            burst(c, out, t, 'lowpass', 2600, 500, 0.4, 0.8, 0.01, 0.55);
            burst(c, out, t + 0.05, 'bandpass', 4200, 1800, 0.7, 0.25, 0.04, 0.5);
            tone(c, out, t, 120, 55, 0.5, 0.16);
        },
        body(c, out, t) {
            tone(c, out, t, 135, 62, 0.75, 0.1);
            burst(c, out, t, 'lowpass', 900, 300, 0.5, 0.25, 0.002, 0.05);
        },
        catch(c, out, t) {
            tone(c, out, t, 150, 80, 0.5, 0.07);
            burst(c, out, t, 'bandpass', 1800, 900, 0.7, 0.4, 0.002, 0.04);
        },
    };

    //--------------------------------------------------------------------------

    function play(kind, volume, pan, indoor, hard) {
        const c = audio();
        if (!c || !(volume > 0.003)) return;

        load();

        const from = setFor(kind, indoor === true, typeof hard === 'number' ? hard : 0.6);
        const buffer = from && take(from);
        const make = synth[kind] || synth[BORROW[kind]];

        if (!buffer && !make) return;

        const master = c.createGain();
        master.gain.value = Math.min(1, volume * (buffer ? (levels[from] || 1) : 1));

        if (c.createStereoPanner) {
            const panner = c.createStereoPanner();
            panner.pan.value = Math.max(-1, Math.min(1, pan || 0));
            master.connect(panner).connect(c.destination);
        } else {
            master.connect(c.destination);
        }

        if (!buffer) {
            make(c, master, c.currentTime + 0.005);
            return;
        }

        const src = c.createBufferSource();
        src.buffer = buffer;

        // A few percent either side of true, and a soft touch a shade lower:
        // the same recording never sounds quite the same twice.
        src.playbackRate.value = (0.96 + Math.random() * 0.08) * (volume < 0.25 ? 0.97 : 1);

        src.connect(master);
        src.start(c.currentTime + 0.005);
    }

    return { play, load };
})();

window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'sfx') Sfx.play(msg.kind, msg.volume, msg.pan, msg.indoor, msg.hard);
});

// Fetched and decoded up front, so the first bounce isn't late.
Sfx.load();
