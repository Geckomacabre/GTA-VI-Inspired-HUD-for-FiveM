'use strict';

// ── NUI bridge (works inside FiveM; returns {} outside) ─────────────────────
function fetchNui(event, data) {
    var res = (typeof globalThis !== 'undefined' && globalThis.resourceName)
        || location.host.replace('cfx-nui-', '');
    return fetch('https://' + res + '/' + event, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {})
    }).then(function (r) { return r.json(); }).catch(function () { return {}; });
}

// ── State ─────────────────────────────────────────────────────────────────
var routes        = [];
var classes       = [];
var invitePollId  = null;

var SCHEME_LABEL = { ordered: 'Sprint', circuit: 'Circuit', thereandback: 'There & Back' };

var STAT_TILES = [
    { key: 'topSpeedMph',         label: 'Top Speed',      fmt: function (v) { return Math.round(v) + ' mph'; } },
    { key: 'racesWon',            label: 'Races Won',      fmt: String },
    { key: 'npcChallengesWon',    label: 'Rivals Beaten',  fmt: String },
    { key: 'totalMilesDriven',    label: 'Miles Driven',   fmt: function (v) { return Math.round(v).toLocaleString(); } },
    { key: 'stuntJumpsCompleted', label: 'Stunt Jumps',    fmt: String },
    { key: 'bestDriftScore',      label: 'Best Drift',     fmt: function (v) { return Math.round(v).toLocaleString(); } },
    { key: 'bestWinStreak',       label: 'Best Win Streak', fmt: String },
    { key: 'bestRampageScore',    label: 'Best Rampage',   fmt: function (v) { return Math.round(v).toLocaleString(); } },
    {
        label: 'Win Rate',
        calc: function (stats) {
            var completed = stats.racesCompleted || 0;
            var won = stats.racesWon || 0;
            return completed ? Math.round(won / completed * 100) + '%' : '—';
        },
    },
    {
        label: 'Goal Times Beaten',
        calc: function (stats) { return String(stats.goalTimesBeaten || 0); },
    },
];

// ── Boot ──────────────────────────────────────────────────────────────────
async function boot() {
    var res = await fetchNui('streetkings:boot', {});
    routes  = res.routes || [];
    classes = res.classes || [];

    populateBoardControls();
    bindTabs();

    document.getElementById('loading').style.display = 'none';

    showPanel('profile');
    loadProfile();

    document.getElementById('inv-accept').onclick  = onAcceptInvite;
    document.getElementById('inv-decline').onclick = onDeclineInvite;

    pollInvite();
    invitePollId = setInterval(pollInvite, 4000);
}

// ── Tabs ──────────────────────────────────────────────────────────────────
function bindTabs() {
    document.querySelectorAll('.tab').forEach(function (btn) {
        btn.addEventListener('click', function () { showPanel(btn.dataset.p); });
    });
}

function showPanel(name) {
    document.querySelectorAll('.tab').forEach(function (b) {
        b.classList.toggle('on', b.dataset.p === name);
    });
    document.querySelectorAll('.panel').forEach(function (p) {
        p.classList.toggle('on', p.id === 'p-' + name);
    });
    if (name === 'board' && !document.getElementById('board-route').dataset.loaded) {
        loadLeaderboard();
    }
    if (name === 'races' && !document.getElementById('races-list').dataset.loaded) {
        renderRaces();
    }
}

// ── Races ─────────────────────────────────────────────────────────────────
function renderRaces() {
    var listEl = document.getElementById('races-list');
    listEl.dataset.loaded = '1';

    if (!routes.length) {
        listEl.innerHTML = '<div class="empty">No races configured.</div>';
        return;
    }

    listEl.innerHTML = routes.map(function (r) {
        var meta = [SCHEME_LABEL[r.scheme] || r.scheme];
        if (r.scheme === 'circuit') meta.push(r.laps + (r.laps === 1 ? ' lap' : ' laps'));
        if (r.distance) meta.push(r.distance.toFixed(1) + ' mi');
        if (r.goalTime) meta.push('goal ' + formatRaceTime(r.goalTime * 1000));

        return '<div class="race-card' + (r.gated ? ' locked' : '') + '">'
            + '<div class="race-name">' + r.name + (r.gated ? ' <span class="race-lock">&#128274;</span>' : '') + '</div>'
            + '<div class="race-meta">' + meta.join('  •  ') + '</div>'
            + '</div>';
    }).join('');
}

// ── Profile ───────────────────────────────────────────────────────────────
async function loadProfile() {
    var body = document.getElementById('profile-body');
    var res = await fetchNui('streetkings:getProfile', {});
    var stats = res.stats || {};

    var xpForNext = 100 + (res.level || 0) * 50; // display estimate only, mirrors the level curve loosely
    var pct = Math.min(100, Math.round(((res.xp || 0) % xpForNext) / xpForNext * 100));

    var html = ''
        + '<div class="level-card">'
        + '  <div class="level-num">' + (res.level || 0) + '</div>'
        + '  <div class="level-label">Career Level</div>'
        + '  <div class="xp-label">' + (res.xp || 0).toLocaleString() + ' XP</div>'
        + '</div>'
        + '<div class="stat-grid">'
        + STAT_TILES.map(function (t) {
            var display = t.calc ? t.calc(stats) : t.fmt(stats[t.key] || 0);
            return '<div class="stat-tile"><div class="stat-val">' + display + '</div><div class="stat-lbl">' + t.label + '</div></div>';
        }).join('')
        + '</div>';

    body.innerHTML = html;
}

// ── Leaderboard ───────────────────────────────────────────────────────────
function populateBoardControls() {
    var routeSel = document.getElementById('board-route');
    var classSel = document.getElementById('board-class');

    routeSel.innerHTML = routes.map(function (r) {
        return '<option value="' + r.id + '">' + r.name + '</option>';
    }).join('') || '<option value="">No routes</option>';

    classSel.innerHTML = classes.map(function (c) {
        return '<option value="' + c.id + '">' + c.label + '</option>';
    }).join('');

    routeSel.addEventListener('change', loadLeaderboard);
    classSel.addEventListener('change', loadLeaderboard);
}

function formatRaceTime(ms) {
    var totalSec = Math.floor(ms / 1000);
    var min = Math.floor(totalSec / 60);
    var sec = totalSec % 60;
    var hundredths = Math.floor((ms % 1000) / 10);
    return min + ':' + String(sec).padStart(2, '0') + '.' + String(hundredths).padStart(2, '0');
}

async function loadLeaderboard() {
    var routeSel = document.getElementById('board-route');
    var classSel = document.getElementById('board-class');
    routeSel.dataset.loaded = '1';

    var rowsEl = document.getElementById('board-rows');
    rowsEl.innerHTML = '<div class="spin" style="margin:30px auto;"></div>';

    if (!routeSel.value) {
        rowsEl.innerHTML = '<div class="empty">No routes configured.</div>';
        return;
    }

    var rows = await fetchNui('streetkings:getLeaderboard', {
        routeId: routeSel.value,
        vehicleClass: parseInt(classSel.value, 10),
        period: 'all',
    });

    if (!rows || !rows.length) {
        rowsEl.innerHTML = '<div class="empty">No times set on this route/class yet.<br>Be the first.</div>';
        return;
    }

    var rankClass = ['first', 'second', 'third'];
    rowsEl.innerHTML = rows.map(function (row, i) {
        return '<div class="board-row ' + (rankClass[i] || '') + '">'
            + '<div class="board-rank">' + (i + 1) + '</div>'
            + '<div class="board-info">'
            + '  <div class="board-alias">' + (row.alias || 'Unknown') + '</div>'
            + '  <div class="board-vehicle">' + (row.vehicle_model || '') + '</div>'
            + '</div>'
            + '<div class="board-time">' + formatRaceTime(row.score_ms) + '</div>'
            + '</div>';
    }).join('');
}

// ── Rival invite ──────────────────────────────────────────────────────────
async function pollInvite() {
    var invite = await fetchNui('streetkings:getInvite', {});
    var card = document.getElementById('invite-card');

    if (!invite) {
        card.style.display = 'none';
        return;
    }

    card.style.display = 'block';
    document.getElementById('inv-rival').textContent = invite.rival;
    document.getElementById('inv-msg').textContent = invite.message;

    var minutes = Math.max(0, Math.ceil(invite.expiresInMs / 60000));
    document.getElementById('inv-timer').textContent = minutes <= 1
        ? 'Expiring any moment'
        : minutes + ' min to show up';
}

async function onAcceptInvite() {
    await fetchNui('streetkings:acceptInvite', {});
    pollInvite();
}

async function onDeclineInvite() {
    await fetchNui('streetkings:declineInvite', {});
    pollInvite();
}

boot();
