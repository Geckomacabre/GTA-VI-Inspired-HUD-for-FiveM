/* vi_chasemusic page: plays the track client.lua names, at the volume it
   names. The fades are client.lua's (single player steps the volume from its
   script each frame and so does that side); this page is single player's
   media player and its stall watchdog. It never asks for focus. */
'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'vi_extras';

const audio = new Audio();
audio.preload = 'auto';

let playing = false;    // a track was started and not stopped
let serial = 0;         // client.lua's number for the current play
let stallMs = 400;      // [Music] StallMs, sent with each play
let lastTick = 0;       // when client.lua last said anything
let stallPaused = false;

function post(name, body) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body || {}),
    });
}

function setVolume(v) {
    audio.volume = Math.max(0, Math.min(1, Number(v) || 0));
}

// The track ran out, or couldn't be played: client.lua picks the next.
audio.addEventListener('ended', () => {
    if (playing) post('ended', { serial }).catch(() => {});
});
audio.addEventListener('error', () => {
    if (!playing) return;
    playing = false;
    post('failed', { serial }).catch(() => {});
});

window.addEventListener('message', (event) => {
    const m = event.data;
    if (!m || typeof m !== 'object') return;
    lastTick = Date.now();
    switch (m.type) {
        case 'play':
            serial = m.serial;
            stallMs = Number(m.stallMs) || stallMs;
            playing = true;
            stallPaused = false;
            // music/<name>, next to this page's folder; each part URL-encoded
            // so names with spaces or # still load
            audio.src = '../' + String(m.file).split('/').map(encodeURIComponent).join('/');
            setVolume(m.volume);
            // a failure to load comes as the error event above
            audio.play().catch(() => {});
            break;
        case 'volume':
            setVolume(m.volume);
            break;
        case 'stop':
            playing = false;
            audio.pause();
            audio.removeAttribute('src');
            audio.load();
            break;
        // 'tick': only keeps lastTick fresh
    }
});

// Single player's watchdog, every 250 ms: when its script hasn't updated the
// music for StallMs, the track pauses where it is, and goes on when the
// updates come back. (Single player also pauses while the game window isn't
// in front; a FiveM page can't tell, so that part isn't here.)
setInterval(() => {
    const fresh = Date.now() - lastTick < stallMs;
    if (!fresh && !stallPaused) {
        audio.pause();
        stallPaused = true;
    } else if (fresh && stallPaused) {
        if (playing && !audio.ended) audio.play().catch(() => {});
        stallPaused = false;
    }
}, 250);

// client.lua sends nothing until the page says it is here, so a play can't
// be lost while the page loads. Tried again until the callback answers.
(function hello() {
    post('ready').then((r) => { if (!r.ok) throw new Error(); }).catch(() => setTimeout(hello, 1000));
})();
