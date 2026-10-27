const board = document.getElementById('board');
const el = {
    homeName: document.getElementById('home-name'),
    awayName: document.getElementById('away-name'),
    homeScore: document.getElementById('home-score'),
    awayScore: document.getElementById('away-score'),
    clock: document.getElementById('clock'),
    status: document.getElementById('status'),
    roster: document.getElementById('roster'),
    home: document.querySelector('.team.home'),
    away: document.querySelector('.team.away'),
};

function formatClock(seconds) {
    if (seconds === null || seconds === undefined) return '--:--';
    const s = Math.max(0, Math.floor(seconds));
    return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

function statusFor(data) {
    switch (data.state) {
        case 'lobby':
            return { text: 'Lobby', cls: '' };
        case 'countdown':
            return { text: `Tip-off ${data.countdown ?? ''}`.trim(), cls: '' };
        case 'live':
            return { text: 'Live', cls: 'live' };
        case 'ended':
            return { text: 'Final', cls: 'final' };
        default:
            return { text: 'Waiting', cls: '' };
    }
}

function render(data) {
    const teams = data.teams || {};
    const home = teams.home || { label: 'Home', colour: '#4a9eff' };
    const away = teams.away || { label: 'Away', colour: '#ff6b4a' };

    el.home.style.setProperty('--accent', home.colour);
    el.away.style.setProperty('--accent', away.colour);

    el.homeName.textContent = home.label;
    el.awayName.textContent = away.label;
    el.homeScore.textContent = data.score?.home ?? 0;
    el.awayScore.textContent = data.score?.away ?? 0;

    el.home.classList.toggle('mine', data.myTeam === 'home');
    el.away.classList.toggle('mine', data.myTeam === 'away');

    // With no clock configured, show progress toward the score limit instead of
    // an empty timer. A nil clock on the Lua side arrives as undefined rather than
    // null, so these checks are deliberately loose.
    if (data.state === 'live' && data.clock == null && data.scoreLimit > 0) {
        el.clock.textContent = `to ${data.scoreLimit}`;
        el.clock.classList.remove('urgent');
    } else {
        el.clock.textContent = formatClock(data.state === 'countdown' ? data.countdown : data.clock);
        el.clock.classList.toggle('urgent', data.state === 'live' && data.clock != null && data.clock <= 30);
    }

    const status = statusFor(data);
    el.status.textContent = status.text;
    el.status.className = `status ${status.cls}`;

    el.roster.replaceChildren();

    for (const player of data.players || []) {
        const colour = (teams[player.team] || {}).colour || '#666';

        const li = document.createElement('li');
        if (player.id === data.myId) li.classList.add('me');

        const dot = document.createElement('span');
        dot.className = 'dot';
        dot.style.setProperty('--accent', colour);

        const who = document.createElement('span');
        who.className = 'who';
        who.textContent = player.name;

        const pts = document.createElement('span');
        pts.className = 'pts';
        pts.textContent = player.points;

        li.append(dot, who, pts);
        el.roster.append(li);
    }
}

/*
 * The 'rings' shot (client/look.lua sends these). The white ring closes from
 * its full size to nothing in closeMs once THROW goes down; the yellow one is
 * `target` of its size and fades in over settleMs, from a little bigger, when
 * a basket comes under it. When the two are within `perfect` of each other
 * the white one turns yellow: that is the moment the game is judging against.
 */
const reticle = {
    el: document.getElementById('reticle'),
    white: document.getElementById('ring-white'),
    yellow: document.getElementById('ring-yellow'),
    closing: null,      // performance.now() when THROW went down
    closeMs: 750,
    perfect: 0.08,
    target: null,       // the yellow ring's size, or null with no basket under it
    lockedAt: 0,
    settleMs: 350,
    frame: 0,
};

function drawReticle() {
    // The same clock the messages were stamped with: a frame's own timestamp
    // can be from before the message that started the close arrived.
    const now = performance.now();
    const r = reticle.closing === null ? 1
        : Math.min(1, Math.max(0, 1 - (now - reticle.closing) / reticle.closeMs));
    let met = false;

    reticle.white.setAttribute('r', r.toFixed(4));

    if (reticle.target) {
        const t = Math.min(1, (now - reticle.lockedAt) / reticle.settleMs);
        const ease = 1 - Math.pow(1 - t, 3);

        reticle.yellow.setAttribute('r', (reticle.target * (1 + 0.35 * (1 - ease))).toFixed(4));
        reticle.yellow.style.opacity = ease.toFixed(3);
        met = reticle.closing !== null && Math.abs(r - reticle.target) <= reticle.perfect;
    } else {
        reticle.yellow.style.opacity = '0';
    }

    reticle.white.classList.toggle('met', met);
    reticle.frame = requestAnimationFrame(drawReticle);
}

function onReticle(msg) {
    if (msg.show === false) {
        cancelAnimationFrame(reticle.frame);
        reticle.frame = 0;
        reticle.el.classList.add('hidden');
        return;
    }

    if (msg.show) {
        reticle.closing = null;
        reticle.target = null;
        if (msg.radius) reticle.el.style.setProperty('--ring', `${msg.radius * 100}vh`);
        reticle.el.classList.remove('hidden');
        if (!reticle.frame) reticle.frame = requestAnimationFrame(drawReticle);
    }

    if (msg.target !== undefined) {
        // A basket newly under it fades in; one walked closer to just resizes.
        if (msg.target && !reticle.target) reticle.lockedAt = performance.now();
        reticle.target = msg.target || null;
        if (msg.settleMs) reticle.settleMs = msg.settleMs;
    }

    if (msg.close) {
        reticle.closing = performance.now();
        reticle.closeMs = msg.closeMs || reticle.closeMs;
        reticle.perfect = msg.perfect || reticle.perfect;
    }
}

window.addEventListener('message', (event) => {
    const msg = event.data || {};

    if (msg.action === 'reticle') {
        onReticle(msg);
        return;
    }

    if (msg.action === 'update') {
        render(msg.data || {});
        board.classList.remove('hidden');
    } else if (msg.action === 'hide') {
        board.classList.add('hidden');
    }
});
