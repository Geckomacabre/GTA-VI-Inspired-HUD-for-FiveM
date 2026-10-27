/* GTA VI's pause menu: the page. client/main.lua sends what to show (open, list, tiles, footer, hide, close, mapdata)
   and a pad's presses (pad, padaxes), and is told what was chosen (close, screen, tile, setting, report, disconnect,
   sound, waypoint, mapzone). Arrow keys or the mouse move, Enter chooses, Esc or Backspace goes back, and at home
   closes. The map is single player's, drawn on a canvas (the map's section below). */
(function () {
    'use strict';

    var RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'vi_pausemenu';

    function post(name, data) {
        if (typeof window.VIPM_STUB === 'function') {
            return Promise.resolve(window.VIPM_STUB(name, data || {}) || {});
        }
        return fetch('https://' + RES + '/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (r) { return r.json(); }).catch(function () { return {}; });
    }

    function $(id) { return document.getElementById(id); }

    function el(tag, cls) {
        var e = document.createElement(tag);
        if (cls) e.className = cls;
        return e;
    }

    function sound(name) { post('sound', { name: name }); }

    /* -------------------------------------------------------------------------
       Keys, drawn as white discs with dark ink (vice_hud's prompts, the same 36-unit box)
       ---------------------------------------------------------------------- */
    function glyphText(text, size) {
        return '<text class="g-text" x="18" y="' + (18 + size * 0.35).toFixed(2) + '" font-size="' + size
            + '" text-anchor="middle">' + text + '</text>';
    }

    var GLYPHS = {
        enter: '<path class="g-ink" d="M24.4 10.8v6.2a2.6 2.6 0 0 1-2.6 2.6H11.8M15.6 15.8l-3.8 3.8 3.8 3.8"/>',
        esc: glyphText('ESC', 10.4),
        lr: '<path class="g-ink" d="M10.6 18h14.8M14 14.6 10.6 18l3.4 3.4M22 14.6l3.4 3.4-3.4 3.4"/>',
        ud: '<path class="g-ink" d="M18 10.6v14.8M14.6 14 18 10.6l3.4 3.4M14.6 22l3.4 3.4 3.4-3.4"/>',
        tab: glyphText('TAB', 10.4),
        // a pad's buttons, as single player's hints draw them
        cross: '<path class="g-ink" d="M12.6 12.6l10.8 10.8M23.4 12.6 12.6 23.4"/>',
        circle: '<circle class="g-ink g-t" cx="18" cy="18" r="6.4"/>'
    };

    // With a pad in hand the keys become its buttons: Enter is cross, Esc circle, Tab the D-pad's down.
    var PAD_GLYPH = { enter: 'cross', esc: 'circle', tab: 'ud' };
    function glyph(name) {
        if (state.pad && PAD_GLYPH[name]) name = PAD_GLYPH[name];
        return '<svg class="glyph" viewBox="0 0 36 36"><circle class="g-face" cx="18" cy="18" r="16.4"/>'
            + (GLYPHS[name] || '') + '</svg>';
    }

    // [[glyph, label, onclick]] into a row of prompts, each its word then its key ("SELECT (o)  CLOSE (o)")
    function prompts(target, list) {
        target.innerHTML = '';
        list.forEach(function (p) {
            var e = el('div', 'pr');
            e.innerHTML = '<span></span>' + glyph(p[0]);
            e.querySelector('span').textContent = p[1];
            if (p[2]) e.addEventListener('click', p[2]);
            target.appendChild(e);
        });
    }

    var CHEVRON_L = '<svg class="arr al" viewBox="0 0 16 16"><path d="M10.4 2.8 5.2 8l5.2 5.2"/></svg>';
    var CHEVRON_R = '<svg class="arr ar" viewBox="0 0 16 16"><path d="M5.6 2.8 10.8 8l-5.6 5.2"/></svg>';

    /* -------------------------------------------------------------------------
       State
       ---------------------------------------------------------------------- */
    var state = {
        on: false,
        pad: false,         // the last thing used was a pad (client/main.lua says so with each press)
        screen: 'home',     // home, map, settings, brief, stats, players, report
        title: '',
        tiles: [],
        sel: { r: 0, c: 0 },
        navX: null,         // where a run of up/down moves started, so going back up lands where it began
        rows: [],
        rowSel: 0,
        rowSelOf: {},       // each list's last row, for coming back to it
        footer: {},
        discord: '',
        categories: ['Other'],
        report: { cat: 0, subject: '', text: '' },
        confirm: false,
        busy: false
    };

    var root = $('root');

    /* -------------------------------------------------------------------------
       Home: the tiles
       ---------------------------------------------------------------------- */
    function tileEl(r, c) {
        var row = $('grid').children[r];
        return row ? row.children[c] : null;
    }

    function sameShape(a, b) {
        if (a.length !== b.length) return false;
        for (var r = 0; r < a.length; r++) {
            if (a[r].length !== b[r].length) return false;
            for (var c = 0; c < a[r].length; c++) {
                if (a[r][c].id !== b[r][c].id) return false;
            }
        }
        return true;
    }

    function setTiles(tiles) {
        var old = state.tiles;
        state.tiles = Array.isArray(tiles) ? tiles : [];
        if (old.length && sameShape(old, state.tiles) && $('grid').children.length) {
            // the same tiles: just their lines (the editor's, the players' count)
            state.tiles.forEach(function (row, r) {
                row.forEach(function (t, c) {
                    var e = tileEl(r, c);
                    e.querySelector('.lbl').textContent = t.label;
                    e.querySelector('.sub').textContent = t.sub || '';
                });
            });
            return;
        }
        buildGrid();
    }

    function buildGrid() {
        var grid = $('grid');
        grid.innerHTML = '';
        state.tiles.forEach(function (row, r) {
            var rowEl = el('div', 'row r' + (r + 1));
            row.forEach(function (t, c) {
                var tile = el('div', 'tile');
                tile.dataset.id = t.id;
                var img = el('img');
                img.src = 'img/' + t.image + '.webp';
                img.alt = '';
                img.draggable = false;
                var cap = el('div', 'cap');
                var lbl = el('div', 'lbl');
                lbl.textContent = t.label;
                var sub = el('div', 'sub');
                sub.textContent = t.sub || '';
                cap.appendChild(lbl);
                cap.appendChild(sub);
                tile.appendChild(img);
                tile.appendChild(cap);
                tile.addEventListener('mouseenter', function () {
                    if (state.sel.r !== r || state.sel.c !== c) {
                        state.sel = { r: r, c: c };
                        state.navX = null;
                        markTile();
                        sound('nav');
                    }
                });
                tile.addEventListener('click', function () {
                    state.sel = { r: r, c: c };
                    markTile();
                    activateTile();
                });
                rowEl.appendChild(tile);
            });
            grid.appendChild(rowEl);
        });
        clampSel();
        markTile();
    }

    function clampSel() {
        var rows = state.tiles;
        if (!rows.length) { state.sel = { r: 0, c: 0 }; return; }
        var r = Math.max(0, Math.min(rows.length - 1, state.sel.r));
        var c = Math.max(0, Math.min(rows[r].length - 1, state.sel.c));
        state.sel = { r: r, c: c };
    }

    function markTile() {
        var tiles = $('grid').querySelectorAll('.tile.sel');
        for (var i = 0; i < tiles.length; i++) tiles[i].classList.remove('sel');
        var e = tileEl(state.sel.r, state.sel.c);
        if (e) e.classList.add('sel');
    }

    function centreX(e) {
        var b = e.getBoundingClientRect();
        return b.left + b.width / 2;
    }

    function moveTile(dr, dc) {
        var r = state.sel.r;
        var c = state.sel.c;
        if (!state.tiles.length) return;
        if (dc) {
            c = Math.max(0, Math.min(state.tiles[r].length - 1, c + dc));
            state.navX = null;
        }
        if (dr) {
            var nr = r + dr;
            if (nr < 0 || nr >= state.tiles.length) return;
            var from = tileEl(r, c);
            if (state.navX == null && from) state.navX = centreX(from);
            var best = 0;
            var bestD = Infinity;
            for (var i = 0; i < state.tiles[nr].length; i++) {
                var d = Math.abs(centreX(tileEl(nr, i)) - state.navX);
                if (d < bestD - 0.5) { bestD = d; best = i; }
            }
            r = nr;
            c = best;
        }
        if (r !== state.sel.r || c !== state.sel.c) {
            state.sel = { r: r, c: c };
            markTile();
            sound('nav');
        }
    }

    function selectedTile() {
        var row = state.tiles[state.sel.r];
        return row && row[state.sel.c];
    }

    function activateTile() {
        var t = selectedTile();
        if (!t || state.busy) return;
        switch (t.id) {
            case 'brief':
            case 'stats':
            case 'settings':
            case 'players':
                sound('select');
                openList(t.id);
                break;
            case 'report':
                sound('select');
                openReport();
                break;
            case 'discord':
                sound('select');
                openDiscord();
                break;
            case 'disconnect':
                sound('select');
                showConfirm();
                break;
            case 'map':
                // the client answers with where the player is, the waypoint and the blips
                sound('select');
                state.busy = true;
                post('tile', { id: 'map' }).then(function (r) {
                    state.busy = false;
                    if (state.on && state.screen === 'home' && r && r.map) openMap(r);
                });
                break;
            default:
                // the game's settings, the Rockstar Editor: the client's
                post('tile', { id: t.id });
        }
    }

    /* -------------------------------------------------------------------------
       The list screens
       ---------------------------------------------------------------------- */
    function setScreen(name, title) {
        state.screen = name;
        var list = name !== 'home';
        root.classList.toggle('list', list);
        $('title').textContent = state.title;
        $('heading').textContent = list ? title : '';
        updatePrompts();
    }

    function openList(name) {
        state.busy = true;
        post('screen', { screen: name }).then(function (r) {
            state.busy = false;
            if (!state.on) return;
            state.rowSel = state.rowSelOf[name] || 0;
            setScreen(name, (r && r.title) || name);
            setRows((r && r.rows) || []);
        });
    }

    function goHome() {
        if (state.screen !== 'home') {
            state.rowSelOf[state.screen] = state.rowSel;
        }
        $('report-text').blur();
        var focused = document.activeElement;
        if (focused && focused.blur) focused.blur();
        setScreen('home');
        markTile();
        post('screen', { screen: 'home' });
    }

    var EMPTY = {
        players: 'Nobody else is on.',
        stats: 'No stats to show.',
        brief: 'Nothing to show yet.',
        settings: 'Nothing to set.'
    };

    function setRows(rows) {
        state.rows = Array.isArray(rows) ? rows : [];
        state.rowSel = Math.max(0, Math.min(state.rows.length - 1, state.rowSel));
        renderRows();
    }

    function renderRows() {
        var box = $('rows');
        box.innerHTML = '';
        if (!state.rows.length) {
            var none = el('div', 'lrow empty');
            none.textContent = EMPTY[state.screen] || '';
            box.appendChild(none);
            preview({});
            updatePrompts();
            return;
        }
        state.rows.forEach(function (row, i) {
            var e = el('div', 'lrow' + (row.change ? ' change' : '') + (row.action ? ' action' : ''));
            var l = el('span', 'l');
            l.textContent = row.label;
            e.appendChild(l);

            if (row.kind === 'subject') {
                e.appendChild(subjectInput());
            } else {
                var v = el('span', 'v');
                v.innerHTML = CHEVRON_L + '<span class="vt"></span>' + CHEVRON_R;
                v.querySelector('.vt').textContent = row.value == null ? '' : row.value;
                v.querySelector('.al').addEventListener('click', function (ev) {
                    ev.stopPropagation();
                    pickRow(i);
                    change(-1);
                });
                v.querySelector('.ar').addEventListener('click', function (ev) {
                    ev.stopPropagation();
                    pickRow(i);
                    change(1);
                });
                e.appendChild(v);
            }
            if (row.bar != null) {
                var bar = el('span', 'bar');
                bar.innerHTML = '<b></b>';
                bar.firstChild.style.width = Math.round(Math.max(0, Math.min(1, row.bar)) * 100) + '%';
                e.appendChild(bar);
            }
            e.addEventListener('mouseenter', function () {
                if (state.rowSel !== i) {
                    pickRow(i);
                    sound('nav');
                }
            });
            e.addEventListener('click', function () {
                pickRow(i);
                activateRow();
            });
            box.appendChild(e);
        });
        markRow();
    }

    function pickRow(i) {
        state.rowSel = i;
        markRow();
    }

    function markRow() {
        var rows = $('rows').children;
        for (var i = 0; i < rows.length; i++) rows[i].classList.toggle('sel', i === state.rowSel);
        var e = rows[state.rowSel];
        if (e) scrollIntoList(e);
        var row = state.rows[state.rowSel] || {};
        preview(row);
        updatePrompts();

        // the report's fields take the keys while they are chosen
        if (state.screen === 'report') {
            if (row.kind === 'subject') {
                var input = e && e.querySelector('input');
                if (input && document.activeElement !== input) input.focus();
            } else if (row.kind === 'text') {
                var area = $('report-text');
                if (document.activeElement !== area) area.focus();
            } else if (document.activeElement && document.activeElement.blur) {
                document.activeElement.blur();
            }
        }
    }

    function scrollIntoList(e) {
        var list = $('list');
        var top = e.offsetTop;
        var bottom = top + e.offsetHeight;
        if (top < list.scrollTop) list.scrollTop = top;
        else if (bottom > list.scrollTop + list.clientHeight) list.scrollTop = bottom - list.clientHeight;
    }

    function preview(row) {
        var pv = $('preview');
        $('pic').style.backgroundImage = row.image ? 'url("img/' + row.image + '.webp")' : '';
        $('pv-title').textContent = row.title || row.label || '';
        $('pv-desc').textContent = row.desc || '';
        pv.classList.toggle('has-bar', row.bar != null);
        if (row.bar != null) {
            $('pv-bar').firstChild.style.width = Math.round(Math.max(0, Math.min(1, row.bar)) * 100) + '%';
        }
        pv.classList.toggle('typing', row.kind === 'text');
    }

    function moveRow(d) {
        var n = state.rows.length;
        if (!n) return;
        var i = (state.rowSel + d + n) % n;
        if (i !== state.rowSel) {
            pickRow(i);
            sound('nav');
        }
    }

    // left/right on a setting (or the report's category)
    function change(dir) {
        var row = state.rows[state.rowSel];
        if (!row || !row.change || state.busy) return;
        if (state.screen === 'report') {
            var n = state.categories.length;
            state.report.cat = (state.report.cat + dir + n) % n;
            row.value = state.categories[state.report.cat];
            renderRows();
            sound('nav');
            return;
        }
        state.busy = true;
        post('setting', { id: row.id, dir: dir }).then(function (r) {
            state.busy = false;
            if (r && Array.isArray(r.rows) && state.screen === 'settings') setRows(r.rows);
        });
    }

    function activateRow() {
        var row = state.rows[state.rowSel];
        if (!row) return;
        if (state.screen === 'report') {
            if (row.kind === 'send') sendReport();
            else if (row.kind === 'cat') change(1);
            return;
        }
        if (row.action) {
            sound('select');
            post('setting', { id: row.id });
        } else if (row.change) {
            change(1);
        }
    }

    /* -------------------------------------------------------------------------
       Report
       ---------------------------------------------------------------------- */
    function reportRows() {
        return [
            { kind: 'cat', label: 'Category', change: true, value: state.categories[state.report.cat] || 'Other',
              image: 'report', desc: 'What the report is about.' },
            { kind: 'subject', label: 'Subject', image: 'report', desc: 'A line for staff to read first.' },
            { kind: 'text', label: 'Message', title: 'Message', desc: 'Tab or the arrows at either end of the text move on.' },
            { kind: 'send', label: 'Send Report', action: true, image: 'report',
              desc: 'Staff get it straight away. One report a minute.' }
        ];
    }

    var subjectEl = null;
    function subjectInput() {
        if (!subjectEl) {
            subjectEl = el('input');
            subjectEl.type = 'text';
            subjectEl.maxLength = 120;
            subjectEl.placeholder = 'Type here';
            subjectEl.spellcheck = false;
            subjectEl.addEventListener('input', function () { state.report.subject = subjectEl.value; });
            subjectEl.addEventListener('keydown', fieldKeys);
        }
        subjectEl.value = state.report.subject;
        return subjectEl;
    }

    $('report-text').addEventListener('input', function () { state.report.text = $('report-text').value; });
    $('report-text').addEventListener('keydown', fieldKeys);

    // in the subject or the message: Esc goes back, Tab and Enter (subject) move on, an arrow past either end of the
    // text moves to the next row; everything else is typing
    function fieldKeys(e) {
        var f = e.target;
        var area = f.tagName === 'TEXTAREA';
        e.stopPropagation();
        if (e.key === 'Escape') {
            e.preventDefault();
            sound('back');
            goHome();
        } else if (e.key === 'Tab') {
            e.preventDefault();
            moveRow(e.shiftKey ? -1 : 1);
        } else if (e.key === 'Enter' && !area) {
            e.preventDefault();
            moveRow(1);
        } else if (e.key === 'ArrowUp' && (!area || f.selectionStart === 0)) {
            e.preventDefault();
            moveRow(-1);
        } else if (e.key === 'ArrowDown' && (!area || f.selectionEnd === f.value.length)) {
            e.preventDefault();
            moveRow(1);
        }
    }

    function openReport() {
        state.rowSel = 0;
        setScreen('report', 'Report');
        $('report-text').value = state.report.text;
        setRows(reportRows());
        post('screen', { screen: 'report' });
    }

    function sendReport() {
        var subject = state.report.subject.trim();
        var text = state.report.text.trim();
        if (!subject || !text) {
            toast(!subject ? 'Give the report a subject first.' : 'Write what happened first.');
            pickRow(!subject ? 1 : 2);
            return;
        }
        sound('select');
        post('report', { category: state.categories[state.report.cat], subject: subject, text: text });
        state.report.subject = '';
        state.report.text = '';
        $('report-text').value = '';
        if (subjectEl) subjectEl.value = '';
        toast('Report sent to staff.');
        goHome();
    }

    /* -------------------------------------------------------------------------
       Discord, Disconnect, the toast
       ---------------------------------------------------------------------- */
    function openDiscord() {
        if (!state.discord) return;
        if (typeof window.invokeNative === 'function') window.invokeNative('openUrl', state.discord);
        else window.open(state.discord, '_blank');
        toast('Discord opened in your browser.');
    }

    function showConfirm() {
        state.confirm = true;
        $('confirm').classList.add('on');
        updatePrompts();
    }

    function hideConfirm() {
        state.confirm = false;
        $('confirm').classList.remove('on');
        updatePrompts();
    }

    function confirmYes() {
        hideConfirm();
        post('disconnect');
    }

    /* -------------------------------------------------------------------------
       The character's face, top right
       ---------------------------------------------------------------------- */
    // a pedheadshot is served from the game's own texture memory; the txd and its texture share the name
    var faceUrl = typeof window.VIPM_FACE_URL === 'function' ? window.VIPM_FACE_URL : function (txd) {
        return 'https://nui-img/' + txd + '/' + txd;
    };
    var face = null;        // this page's own copy of the picture (an object URL)

    function setInitials(name) {
        var letters = String(name || '').trim().split(/\s+/).map(function (w) { return w.charAt(0); }).join('');
        letters = letters.length > 2 ? letters.charAt(0) + letters.charAt(letters.length - 1) : letters;
        $('mug').querySelector('.initials').textContent = letters.toUpperCase();
    }

    function showFace(url) {
        var img = $('mug').querySelector('img');
        img.src = url;
        img.hidden = false;
        $('mug').classList.add('has-face');
    }

    // Copied out of the game's texture into a blob this page owns, then the client is told it may let the headshot
    // slot go: everything after reads the copy. A failure keeps whatever face (or initials) was there.
    function copyFace(txd) {
        if (!txd) { post('mugshot', { ok: false }); return; }
        fetch(faceUrl(txd))
            .then(function (r) {
                if (!r.ok) throw new Error('nui-img ' + r.status);
                return r.blob();
            })
            .then(function (blob) {
                var old = face;
                face = URL.createObjectURL(blob);
                showFace(face);
                if (old) URL.revokeObjectURL(old);
                post('mugshot', { ok: true });
            })
            .catch(function () { post('mugshot', { ok: false }); });
    }

    var toastTimer = null;
    function toast(text) {
        var t = $('toast');
        t.textContent = text;
        t.classList.add('on');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(function () { t.classList.remove('on'); }, 2600);
    }

    /* -------------------------------------------------------------------------
       The bottom
       ---------------------------------------------------------------------- */
    function setFooter(f) {
        state.footer = f || {};
        $('st-day').textContent = state.footer.day || '';
        $('st-time').textContent = state.footer.time || '';
        $('st-cash').textContent = state.footer.cash || '';
        $('st-bank').textContent = state.footer.bank || '';
    }

    function back() {
        if (state.confirm) {
            sound('back');
            hideConfirm();
        } else if (state.screen !== 'home') {
            sound('back');
            goHome();
        } else {
            post('close');
        }
    }

    function select() {
        if (state.confirm) confirmYes();
        else if (state.screen === 'home') activateTile();
        else activateRow();
    }

    function updatePrompts() {
        var list = [];
        var backLabel = state.screen === 'home' ? 'Close' : 'Back';
        if (state.screen === 'home') {
            list.push(['enter', 'Select', select]);
        } else {
            var row = state.rows[state.rowSel] || {};
            if (row.change) list.push(['lr', 'Change', function () { change(1); }]);
            if (row.action) list.push(['enter', row.kind === 'send' ? 'Send' : 'Select', select]);
            if (row.kind === 'subject' || row.kind === 'text') list.push(['tab', 'Next', function () { moveRow(1); }]);
            if (state.rows.length > 1 && !row.change && !row.action && !row.kind) {
                list.push(['ud', 'Scroll', null]);
            }
        }
        list.push(['esc', backLabel, back]);
        prompts($('prompts'), list);
        prompts($('confirm-prompts'), [['enter', 'Disconnect', confirmYes], ['esc', 'Cancel', back]]);
    }

    // a pad in hand, or not: the keys drawn change, and a pad let go of stops moving the map
    function setPad(on) {
        if (!on) map.axes = { x: 0, y: 0, lt: 0, rt: 0 };
        if (state.pad === on) return;
        state.pad = on;
        updatePrompts();
    }

    /* -------------------------------------------------------------------------
       The map: single player's (FBICat's GTA6Hud pause map), drawn on a canvas as its DrawPauseMap draws it and
       moved as its PauseMapInput moves it, in its units: a screen 1080 high and 1080 x the aspect ratio wide, with
       its frame (PauseLayout.Fit) inside. client/main.lua sends where the player is and which way they face, the
       waypoint and the blips, names the area under the cursor and sets the waypoint.
       ---------------------------------------------------------------------- */
    var MAP = {
        ox: -4118.697, oy: 8361.491, k: 8.724844,   // world to map units: (x - ox) / k across, (oy - y) / k down
        w: 1024, h: 1536,                           // six 512-unit tiles (m_<row>_<col>), three rows of two
        minZoom: 0.646875, maxZoom: 14, startZoom: 2.4, legendZoom: 3.2,
        detail: 1.15,                               // the detail tiles (d_*) fade in above this zoom, over 0.6 more
        fade: 280,                                  // ms the map takes to come up
        legendRows: 15,
        near: 34                                    // px: a click this close to the waypoint takes it off
    };
    var SEA = [72, 160, 192];
    var PM_WHITE = [250, 250, 252];
    var PM_GREY = [176, 176, 186];
    var PM_INK = [26, 26, 32];
    var PM_HINT = [246, 246, 246];
    var PM_PINK = [255, 156, 180];
    var PM_PANEL = [20, 22, 34];
    var PM_BAR = [6, 6, 12];
    var BLACK = [0, 0, 0];
    var WHITE = [255, 255, 255];

    // GTA6Hud's LegendKinds, in its order. 374 is its "STASH THE BAG" too, but only for its own robbery blips
    // (ViLegendSplit); with none of those every 374 is a business, as it names them.
    var LEGEND_KINDS = [
        [40, 'SAFEHOUSES'], [374, 'BUSINESSES'], [500, 'BANKS'], [617, 'JEWELLER'], [677, 'PORT CONTAINERS'],
        [616, 'VAN SHIPMENT'], [140, 'DEALER'], [618, 'STALLED BOAT'], [544, 'YOU TOOL'], [52, 'STORES'],
        [361, 'GAS STATIONS'], [73, 'CLOTHES'], [71, 'BARBERS'], [75, 'TATTOO'], [110, 'AMMU-NATION'],
        [72, 'LOS SANTOS CUSTOMS'], [93, 'BARS'], [121, 'STRIP CLUBS'], [135, 'CINEMAS'], [61, 'HOSPITALS'],
        [357, 'GARAGES'], [50, 'CAR RENTALS'], [309, 'RACES'], [109, 'GOLF'], [122, 'TENNIS'], [266, 'FAIRGROUND'],
        [356, 'MARINAS'], [377, 'PARACHUTING'], [90, 'AIRPORT']
    ];

    // where each picture is in the sheets (img/map/atlas.js, built from single player's vipause atlas)
    var ATLAS = window.VIPM_MAP_ATLAS || { ui: {}, blips: {}, font: { cap: 50, glyphs: {} } };
    var GLYPH = ATLAS.font.glyphs;
    var FONT_CAP = ATLAS.font.cap;

    var map = {
        on: false,
        at: 0,              // when it came up
        tick: 0,            // the last frame
        raf: 0,
        cx: 0, cy: 0,       // the map point in the middle of the screen
        zoom: MAP.startZoom, zoomTo: MAP.startZoom,
        drag: false, dragMoved: false, dragX: 0, dragY: 0,
        down: false,        // the left button is held
        cursorStyle: '',
        me: { x: 0, y: 0, h: 0 },
        wp: null,           // the waypoint, world x and y
        wpHold: 0,          // one set or taken off here stands until then, over the client's next reports
        blips: [],
        // the legend, kept from one visit to the next as single player keeps it
        legend: [], sel: -1, step: 0, scroll: 0,
        target: null,       // where the legend last jumped to, ringed
        zone: '', zoneKey: '', zoneAt: 0, zoneBusy: false,
        targetZone: '', targetKey: '',
        mode: '', name: '', safezone: 1,
        keys: {},           // held: left, right, up, down, zoomIn, zoomOut
        axes: { x: 0, y: 0, lt: 0, rt: 0 },     // a pad's left stick and triggers
        input: {}           // what was pressed since the last frame
    };
    var mouse = { x: -1, y: -1 };   // the cursor in the window's pixels, once the page has seen it

    var mapPics = {};
    function mapPic(name) {
        var im = mapPics[name];
        if (!im) {
            im = mapPics[name] = new Image();
            im.src = 'img/map/' + name + '.webp';
        }
        return im.complete && im.naturalWidth ? im : null;
    }

    // a picture tinted as DRAW_SPRITE tints (its colours times the tint), made once: the font in its few colours,
    // the plain dots' discs in theirs
    var tints = {};
    function tinted(sheet, r, rgb) {
        var key = sheet.src + '|' + r.join(',') + '|' + rgb.join(',');
        var c = tints[key];
        if (c) return c;
        c = document.createElement('canvas');
        c.width = r[2];
        c.height = r[3];
        var x = c.getContext('2d');
        x.drawImage(sheet, r[0], r[1], r[2], r[3], 0, 0, r[2], r[3]);
        x.globalCompositeOperation = 'multiply';
        x.fillStyle = 'rgb(' + rgb.join(',') + ')';
        x.fillRect(0, 0, r[2], r[3]);
        x.globalCompositeOperation = 'destination-in';
        x.drawImage(sheet, r[0], r[1], r[2], r[3], 0, 0, r[2], r[3]);
        tints[key] = c;
        return c;
    }

    function now() { return window.performance ? performance.now() : Date.now(); }
    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
    function ease(t) { t = clamp(t, 0, 1); return 1 - (1 - t) * (1 - t) * (1 - t); }

    // GTA6Hud's PauseLayout.Fit: a 1920-wide frame at most, in the middle, smaller on narrower screens and inside
    // the game's safe zone
    function mapFrame() {
        var W = 1080 * window.innerWidth / Math.max(1, window.innerHeight);
        var zone = map.safezone > 0.5 && map.safezone <= 1 ? map.safezone : 1;
        var s = Math.min(W, 1920) / 1920 * zone;
        var X = (W - 1920 * s) * 0.5;
        var M = 1080 * (1 - zone) * 0.5;
        return {
            W: W,
            PX: function (dx) { return X + dx * s; },
            PT: function (dy) { return M + dy * s; },
            PB: function (dy) { return 1080 - M - (1080 - dy) * s; },
            L: function (v) { return v * s; }
        };
    }

    function toMapX(x) { return (x - MAP.ox) / MAP.k; }
    function toMapY(y) { return (MAP.oy - y) / MAP.k; }
    function toWorldX(mx) { return MAP.ox + mx * MAP.k; }
    function toWorldY(my) { return MAP.oy - my * MAP.k; }
    function screenX(f, mx) { return f.W * 0.5 + (mx - map.cx) * map.zoom; }
    function screenY(my) { return 540 + (my - map.cy) * map.zoom; }
    function unscreenX(f, sx) { return map.cx + (sx - f.W * 0.5) / map.zoom; }
    function unscreenY(sy) { return map.cy + (sy - 540) / map.zoom; }

    // the mouse in the map's units (the middle of the screen until the page has seen it)
    function mousePt(f) {
        if (mouse.x < 0) return { x: f.W * 0.5, y: 540 };
        return { x: mouse.x / window.innerWidth * f.W, y: mouse.y / window.innerHeight * 1080 };
    }

    // where the map is pointed: the middle of the screen with a pad, the mouse without
    function cursorPt(f) {
        return state.pad ? { x: f.W * 0.5, y: 540 } : mousePt(f);
    }

    function inRect(r, x, y) { return x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h; }

    /* the drawing: GTA6Hud's PmIcon, PmStretch, PmText and PmHint ---------- */
    function fill(ctx, x, y, w, h, rgb, a) {
        if (a <= 0) return;
        ctx.globalAlpha = Math.min(1, a);
        ctx.fillStyle = 'rgb(' + rgb.join(',') + ')';
        ctx.fillRect(x, y, w, h);
    }

    function sheetFor(key) {
        return key.charAt(0) === 'B' && key.charAt(1) === ':'
            ? { pic: mapPic('blips'), r: ATLAS.blips[key.slice(2)] }
            : { pic: mapPic('ui'), r: ATLAS.ui[key] };
    }

    // an icon centred on cx, cy, size across, turned rot degrees clockwise; false when the sheets have no such icon
    function pmIcon(ctx, key, cx, cy, size, a, rot, tint) {
        var s = sheetFor(key);
        if (!s.r) return false;
        if (!s.pic || a <= 0) return true;
        var src = tint ? tinted(s.pic, s.r, tint) : s.pic;
        var sx = tint ? 0 : s.r[0];
        var sy = tint ? 0 : s.r[1];
        ctx.globalAlpha = Math.min(1, a);
        if (rot) {
            ctx.save();
            ctx.translate(cx, cy);
            ctx.rotate(rot * Math.PI / 180);
            ctx.drawImage(src, sx, sy, s.r[2], s.r[3], -size * 0.5, -size * 0.5, size, size);
            ctx.restore();
        } else {
            ctx.drawImage(src, sx, sy, s.r[2], s.r[3], cx - size * 0.5, cy - size * 0.5, size, size);
        }
        return true;
    }

    function pmStretch(ctx, key, x, y, w, h, a) {
        var s = sheetFor(key);
        if (!s.pic || !s.r || a <= 0) return;
        ctx.globalAlpha = Math.min(1, a);
        ctx.drawImage(s.pic, s.r[0], s.r[1], s.r[2], s.r[3], x, y, w, h);
    }

    function glyphOf(ch) {
        return GLYPH[ch.charCodeAt(0)] || GLYPH[ch.toUpperCase().charCodeAt(0)];
    }

    // Single player's font 100 is Staatliches, drawn here from its own sprite sheet as it draws it; a name with a
    // letter the sheet lacks goes to the page's Art Deco instead, as single player falls back to the game's font.
    function spriteable(s) {
        for (var i = 0; i < s.length; i++) {
            if (s.charCodeAt(i) > 127 && !glyphOf(s.charAt(i))) return false;
        }
        return true;
    }

    function textRun(ctx, sheet, s, pen, base, k, cap, rgb, a, font) {
        if (a <= 0) return;
        ctx.globalAlpha = Math.min(1, a);
        if (!sheet) {
            // GTA Art Deco, its capitals cap tall (they are 50 of 72 at its size, as in single player's font sheets)
            ctx.font = (font === 'S' ? '700 ' : '500 ') + (cap * 72 / 50).toFixed(2) + "px 'GTAArtDeco', sans-serif";
            ctx.textAlign = 'left';
            ctx.textBaseline = 'alphabetic';
            ctx.fillStyle = 'rgb(' + rgb.join(',') + ')';
            ctx.fillText(s, pen, base);
            return;
        }
        var src = tinted(sheet, [0, 0, sheet.naturalWidth, sheet.naturalHeight], rgb);
        for (var i = 0; i < s.length; i++) {
            var g = glyphOf(s.charAt(i));
            if (!g) {
                pen += FONT_CAP * 0.5 * k;
                continue;
            }
            if (g[2] > 0) ctx.drawImage(src, g[0], g[1], g[2], g[3], pen + g[4] * k, base + g[5] * k, g[2] * k, g[3] * k);
            pen += g[6] * k;
        }
    }

    // GTA6Hud's PmText: font 'S' (its 100, Staatliches) or 'M' (its 103, GTA Art Deco Medium); capTop is where the
    // capitals' tops go and cap their height. shadow: 'label' always (its ready-made labels have one), true only for
    // 14 letters or fewer (its sprite text's rule). Returns the width.
    function pmText(ctx, s, x, capTop, cap, rgb, a, align, font, shadow) {
        s = s == null ? '' : String(s);
        if (!s) return 0;
        var sheet = font === 'S' && spriteable(s) ? mapPic('font') : null;
        var k = cap / FONT_CAP;
        var w = 0;
        if (sheet) {
            for (var i = 0; i < s.length; i++) {
                var g = GLYPH[s.charCodeAt(i)];
                w += (g ? g[6] : FONT_CAP * 0.5) * k;
            }
        } else {
            ctx.font = (font === 'S' ? '700 ' : '500 ') + (cap * 72 / 50).toFixed(2) + "px 'GTAArtDeco', sans-serif";
            w = ctx.measureText(s).width;
        }
        if (a * 255 < 4) return w;
        var left = align === 'right' ? x - w : align === 'center' ? x - w * 0.5 : x;
        if (shadow === 'label' || (shadow && s.length <= 14)) {
            var o = Math.max(1.2, cap * 0.06);
            textRun(ctx, sheet, s, left + o, capTop + cap + o, k, cap, BLACK, a * 120 / 255, font);
        }
        textRun(ctx, sheet, s, left, capTop + cap, k, cap, rgb, a, font);
        return w;
    }

    // one of the hints along the bottom, right to left: its key (a pad's button with a pad in hand), then its word
    function pmHint(ctx, right, y, label, pad, key, a) {
        var size = 46;
        if (!pmIcon(ctx, state.pad ? 'glyph_' + pad : 'key_vi_' + key, right - size * 0.33, y, size, a)) {
            pmText(ctx, state.pad ? pad.toUpperCase() : key, right, y - 9, 18, WHITE, a, 'right', 'S', false);
        }
        var x = right - size * 0.66 - 10;
        var w = pmText(ctx, label, x, y - 9, 18, PM_HINT, a, 'right', 'M', 'label');
        return x - w - 30;
    }

    /* what the client says ------------------------------------------------- */
    function setMapData(d) {
        if (!d) return;
        if (d.me) map.me = { x: +d.me.x || 0, y: +d.me.y || 0, h: +d.me.h || 0 };
        if (now() >= map.wpHold) map.wp = d.wp ? { x: +d.wp.x, y: +d.wp.y } : null;
        if (d.blips && typeof d.blips === 'object') {
            // four numbers a blip: x, y, sprite, and a plain dot's colour as 0xRRGGBB
            var flat = Array.isArray(d.blips) ? d.blips : [];
            var list = [];
            for (var i = 0; i + 3 < flat.length; i += 4) {
                var c = flat[i + 3] | 0;
                list.push({ x: flat[i], y: flat[i + 1], s: flat[i + 2], rgb: [(c >> 16) & 255, (c >> 8) & 255, c & 255] });
            }
            map.blips = list;
            buildLegend();
        }
    }

    // the area under the cursor, asked for again once the cursor has moved ten metres, ten times a second at most
    function askZone(t, f) {
        var c = cursorPt(f);
        var x = toWorldX(unscreenX(f, c.x));
        var y = toWorldY(unscreenY(c.y));
        var key = Math.round(x / 10) + ',' + Math.round(y / 10);
        if (key === map.zoneKey || map.zoneBusy || t - map.zoneAt < 100) return;
        map.zoneBusy = true;
        map.zoneAt = t;
        post('mapzone', { x: x, y: y }).then(function (r) {
            map.zoneBusy = false;
            map.zoneKey = key;
            map.zone = (r && r.zone) || '';
        });
    }

    function askTargetZone() {
        var key = map.target.x + ',' + map.target.y;
        if (key === map.targetKey) return;
        map.targetKey = key;
        map.targetZone = '';
        post('mapzone', { x: map.target.x, y: map.target.y }).then(function (r) {
            if (map.targetKey === key) map.targetZone = (r && r.zone) || '';
        });
    }

    /* the legend: GTA6Hud's BuildLegend, LegendJump, LegendInput, DrawLegend - */
    function buildLegend() {
        var count = {};
        map.blips.forEach(function (b) { count[b.s] = (count[b.s] || 0) + 1; });
        map.legend = [];
        LEGEND_KINDS.forEach(function (kind) {
            if (count[kind[0]]) map.legend.push({ sprite: kind[0], name: kind[1], count: count[kind[0]] });
        });
        if (map.sel >= map.legend.length) map.sel = map.legend.length - 1;
    }

    function legendRow(f, i) {
        return { x: f.PX(1440), y: f.PT(266) + i * f.L(44), w: f.L(384), h: f.L(40) };
    }

    function legendKeepVisible() {
        if (map.sel < map.scroll) map.scroll = map.sel;
        if (map.sel >= map.scroll + MAP.legendRows) map.scroll = map.sel - MAP.legendRows + 1;
        map.scroll = clamp(map.scroll, 0, Math.max(0, map.legend.length - MAP.legendRows));
    }

    // to the nearest place of a kind; again on the same kind (next), to the next nearest
    function legendJump(sel, next) {
        if (sel < 0 || sel >= map.legend.length) return;
        var sprite = map.legend[sel].sprite;
        var me = map.me;
        var list = map.blips.filter(function (b) { return b.s === sprite; });
        if (!list.length) return;
        function d2(b) { return (b.x - me.x) * (b.x - me.x) + (b.y - me.y) * (b.y - me.y); }
        list.sort(function (p, q) { return d2(p) - d2(q); });
        map.step = next && sel === map.sel ? (map.step + 1) % list.length : 0;
        map.sel = sel;
        legendKeepVisible();
        var b = list[map.step];
        map.target = { x: b.x, y: b.y };
        map.cx = toMapX(b.x);
        map.cy = toMapY(b.y);
        if (map.zoomTo < MAP.legendZoom) map.zoomTo = MAP.legendZoom;
        sound('nav');
    }

    // LB / RB (Q / E) a kind back or on, square (Delete) the next place of the kind; the mouse scrolls the legend
    // and picks a row (the chosen row again: its next place). True when it took the frame's input.
    function legendInput(i, f) {
        var n = map.legend.length;
        if (!n) return false;
        if (i.lb) { legendJump(map.sel <= 0 ? n - 1 : map.sel - 1, false); return true; }
        if (i.rb) { legendJump(map.sel >= 0 && map.sel < n - 1 ? map.sel + 1 : 0, false); return true; }
        if (i.alt && map.sel >= 0) { legendJump(map.sel, true); return true; }
        if (!state.pad) {
            var rows = Math.min(MAP.legendRows, n - map.scroll);
            var m = mousePt(f);
            var panel = { x: f.PX(1440), y: f.PT(214), w: f.L(384), h: f.L(52) + rows * f.L(44) };
            if (mouse.x >= 0 && inRect(panel, m.x, m.y)) {
                if (i.scrollUp) { map.scroll = Math.max(0, map.scroll - 1); return true; }
                if (i.scrollDown) { map.scroll = Math.min(Math.max(0, n - MAP.legendRows), map.scroll + 1); return true; }
                if (i.click) {
                    for (var j = 0; j < rows; j++) {
                        if (inRect(legendRow(f, j), m.x, m.y)) {
                            var k = map.scroll + j;
                            legendJump(k, k === map.sel);
                            return true;
                        }
                    }
                    return true;
                }
            }
        }
        return false;
    }

    function drawLegend(ctx, f, a) {
        var n = map.legend.length;
        if (!n) return;
        var x = f.PX(1440);
        var y = f.PT(214);
        var w = f.L(384);
        map.scroll = clamp(map.scroll, 0, Math.max(0, n - MAP.legendRows));
        var rows = Math.min(MAP.legendRows, n - map.scroll);
        var h = f.L(52) + rows * f.L(44) + f.L(8);
        pmStretch(ctx, 'shadow', x - f.L(24), y - f.L(14), w + f.L(48), h + f.L(40), a * 0.55);
        fill(ctx, x, y, w, h, PM_PANEL, a * 214 / 255);
        fill(ctx, x, y, w, Math.max(2, f.L(3)), PM_PINK, a);
        pmText(ctx, 'ON THE MAP', x + f.L(18), y + f.L(16), f.L(24), PM_WHITE, a, 'left', 'S', 'label');
        var total = 0;
        map.legend.forEach(function (row) { total += row.count; });
        pmText(ctx, String(total), x + w - f.L(18), y + f.L(16), f.L(24), PM_GREY, a, 'right', 'S', false);
        var m = mousePt(f);
        for (var i = 0; i < rows; i++) {
            var k = map.scroll + i;
            var r = legendRow(f, i);
            var chosen = k === map.sel;
            if (chosen) pmStretch(ctx, 'grad', r.x, r.y, r.w, r.h, a);
            else if (!state.pad && mouse.x >= 0 && inRect(r, m.x, m.y)) fill(ctx, r.x, r.y, r.w, r.h, WHITE, a * 60 / 255);
            var mid = r.y + r.h * 0.5;
            var cap = f.L(19);
            pmIcon(ctx, 'B:' + map.legend[k].sprite, r.x + f.L(26), mid, f.L(30), a);
            var ink = chosen ? PM_INK : PM_WHITE;
            pmText(ctx, map.legend[k].name, r.x + f.L(52), mid - cap * 0.5, cap, ink, a, 'left', 'S', false);
            pmText(ctx, String(map.legend[k].count), r.x + r.w - f.L(16), mid - cap * 0.5, cap, chosen ? ink : PM_GREY, a,
                'right', 'S', false);
        }
        if (map.scroll + rows < n) {
            pmText(ctx, 'MORE', x + w * 0.5, y + h - f.L(6), f.L(13), PM_GREY, a, 'center', 'S', false);
        }
        // where the legend went: the area and how far, in miles
        if (map.sel >= 0 && map.target) {
            askTargetZone();
            var dx = map.target.x - map.me.x;
            var dy = map.target.y - map.me.y;
            var y2 = y + h + f.L(14);
            fill(ctx, x, y2, w, f.L(46), PM_PANEL, a * 200 / 255);
            pmText(ctx, map.targetZone + '  ' + (Math.sqrt(dx * dx + dy * dy) / 1609.34).toFixed(1) + ' mi',
                x + f.L(18), y2 + f.L(14), f.L(18), PM_WHITE, a, 'left', 'M', false);
        }
    }

    /* the waypoint --------------------------------------------------------- */
    // a click on (or near) the waypoint takes it off; anywhere else puts it there
    function toggleWaypoint(f, sx, sy) {
        if (map.wp) {
            var dx = screenX(f, toMapX(map.wp.x)) - sx;
            var dy = screenY(toMapY(map.wp.y)) - sy;
            if (dx * dx + dy * dy < MAP.near * MAP.near) {
                waypointOff();
                return;
            }
        }
        map.wp = { x: toWorldX(unscreenX(f, sx)), y: toWorldY(unscreenY(sy)) };
        map.wpHold = now() + 600;
        post('waypoint', { x: map.wp.x, y: map.wp.y });
    }

    function waypointOff() {
        map.wp = null;
        map.wpHold = now() + 600;
        post('waypoint', { off: true });
    }

    function nearWaypoint(f, c) {
        if (!map.wp) return false;
        var dx = screenX(f, toMapX(map.wp.x)) - c.x;
        var dy = screenY(toMapY(map.wp.y)) - c.y;
        return dx * dx + dy * dy < MAP.near * MAP.near;
    }

    /* open, close, each frame ---------------------------------------------- */
    function openMap(r) {
        map.mode = r.mode || '';
        map.name = String(r.name || '').toUpperCase();
        map.safezone = Number(r.safezone) || 1;
        map.wpHold = 0;
        setMapData(r.map);
        map.cx = toMapX(map.me.x);
        map.cy = toMapY(map.me.y);
        map.zoom = map.zoomTo = MAP.startZoom;
        map.drag = false;
        map.keys = {};
        map.input = {};
        map.zoneKey = '';
        map.at = map.tick = now();
        map.on = true;
        state.screen = 'map';
        root.classList.add('map');
        $('pmap').classList.add('on');
        if (!map.raf) map.raf = requestAnimationFrame(mapLoop);
    }

    function closeMap() {
        if (!map.on) return;
        map.on = false;
        map.drag = false;
        map.down = false;
        map.keys = {};
        map.input = {};
        if (map.raf) cancelAnimationFrame(map.raf);
        map.raf = 0;
        root.classList.remove('map');
        $('pmap').classList.remove('on');
        if (state.screen === 'map') state.screen = 'home';
    }

    // back to the tiles, as single player's BackToHome
    function mapBack() {
        sound('back');
        closeMap();
        setScreen('home');
        markTile();
        post('screen', { screen: 'home' });
    }

    function mapLoop() {
        map.raf = 0;
        if (!map.on) return;
        var t = now();
        if (!mapInput(t)) return;
        drawMap(t);
        if (map.on) map.raf = requestAnimationFrame(mapLoop);
    }

    // GTA6Hud's PauseMapInput, a frame of it. False when the map closed.
    function mapInput(t) {
        var f = mapFrame();
        var dt = clamp((t - map.tick) / 1000, 0.001, 0.05);
        map.tick = t;
        var i = map.input;
        map.input = {};
        var pad = state.pad;
        if (i.back || (i.rightClick && !map.drag)) {
            mapBack();
            return false;
        }
        if (legendInput(i, f)) return true;

        // zoom: the wheel a step at a time, the triggers (Page Up / Page Down) smoothly
        var wheel = (i.scrollUp ? 1 : 0) - (i.scrollDown ? 1 : 0);
        var lt = map.axes.lt;
        var rt = map.axes.rt;
        if (map.keys.zoomIn) rt = 1;
        if (map.keys.zoomOut) lt = 1;
        if (wheel) map.zoomTo *= wheel > 0 ? 1.35 : 20 / 27;
        if (rt > 0.1 || lt > 0.1) map.zoomTo *= Math.pow(2.2, (rt - lt) * dt);
        map.zoomTo = clamp(map.zoomTo, MAP.minZoom, MAP.maxZoom);
        // eased, about the mouse (a pad: the middle, where its ring is)
        var m = mousePt(f);
        var c = pad ? { x: f.W * 0.5, y: 540 } : m;
        var ax = unscreenX(f, c.x);
        var ay = unscreenY(c.y);
        map.zoom += (map.zoomTo - map.zoom) * Math.min(1, dt * 14);
        if (!pad) {
            map.cx += ax - unscreenX(f, c.x);
            map.cy += ay - unscreenY(c.y);
        }

        // pan: the left stick, the arrows or WASD, faster the further the stick
        var px = map.axes.x;
        var py = map.axes.y;
        if (map.keys.left) px = -1; else if (map.keys.right) px = 1;
        if (map.keys.up) py = -1; else if (map.keys.down) py = 1;
        if (Math.abs(px) > 0.15 || Math.abs(py) > 0.15) {
            var step = 820 * dt / map.zoom;
            map.cx += px * Math.abs(px) * step;
            map.cy += py * Math.abs(py) * step;
        }

        // the mouse: drag to pan; a click that does not move sets or takes off the waypoint
        if (!pad) {
            if (i.click) {
                map.drag = true;
                map.dragMoved = false;
                map.dragX = m.x;
                map.dragY = m.y;
            }
            if (map.drag && map.down) {
                var dx = m.x - map.dragX;
                var dy = m.y - map.dragY;
                if (Math.abs(dx) + Math.abs(dy) > 3 || map.dragMoved) {
                    map.dragMoved = true;
                    map.cx -= dx / map.zoom;
                    map.cy -= dy / map.zoom;
                    map.dragX = m.x;
                    map.dragY = m.y;
                }
            } else {
                if (map.drag && !map.dragMoved) toggleWaypoint(f, m.x, m.y);
                map.drag = false;
            }
            var style = map.drag && map.dragMoved ? 'grabbing' : 'grab';
            if (style !== map.cursorStyle) {
                map.cursorStyle = style;
                $('pmap').style.cursor = style;
            }
        }
        map.cx = clamp(map.cx, 0, MAP.w);
        map.cy = clamp(map.cy, 0, MAP.h);

        if (i.accept) toggleWaypoint(f, c.x, c.y);
        if (i.alt && map.sel < 0 && map.wp) waypointOff();
        if (i.center) {
            map.cx = toMapX(map.me.x);
            map.cy = toMapY(map.me.y);
            sound('nav');
        }
        return true;
    }

    // GTA6Hud's DrawPauseMap
    function drawMap(t) {
        var cv = $('pmap-canvas');
        var dpr = window.devicePixelRatio || 1;
        var pw = Math.round(window.innerWidth * dpr);
        var ph = Math.round(window.innerHeight * dpr);
        if (cv.width !== pw || cv.height !== ph) {
            cv.width = pw;
            cv.height = ph;
        }
        var ctx = cv.getContext('2d');
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, pw, ph);
        ctx.setTransform(ph / 1080, 0, 0, ph / 1080, 0, 0);
        ctx.imageSmoothingEnabled = true;
        ctx.imageSmoothingQuality = 'high';

        var f = mapFrame();
        var W = f.W;
        var a = ease((t - map.at) / MAP.fade);

        // the sea, then the tiles, the detail over them once close enough
        fill(ctx, 0, 0, W, 1080, SEA, a);
        var size = 512 * map.zoom;
        var detail = map.zoom > MAP.detail ? a * Math.min(1, (map.zoom - MAP.detail) / 0.6) : 0;
        for (var r = 0; r < 3; r++) {
            for (var col = 0; col < 2; col++) {
                var tx = screenX(f, col * 512);
                var ty = screenY(r * 512);
                if (tx > W || ty > 1080 || tx + size < 0 || ty + size < 0) continue;
                var base = mapPic('m_' + r + '_' + col);
                if (base) {
                    ctx.globalAlpha = a;
                    ctx.drawImage(base, tx, ty, size + 0.5, size + 0.5);
                }
                var fine = detail > 0 && mapPic('d_' + r + '_' + col);
                if (fine) {
                    ctx.globalAlpha = detail;
                    ctx.drawImage(fine, tx, ty, size + 0.5, size + 0.5);
                }
            }
        }

        // the blips, 300 on screen at most; a plain dot is a disc of its colour in a dark ring
        var bs = clamp(18 + map.zoom * 3, 22, 34);
        var shown = 0;
        for (var b = 0; b < map.blips.length; b++) {
            var blip = map.blips[b];
            var bx = screenX(f, toMapX(blip.x));
            var by = screenY(toMapY(blip.y));
            if (bx < -bs || by < -bs || bx > W + bs || by > 1080 + bs) continue;
            if (++shown > 300) break;
            if (blip.s === 1) {
                pmIcon(ctx, 'disc', bx, by, bs * 0.62, a * 0.8, 0, BLACK);
                pmIcon(ctx, 'disc', bx, by, bs * 0.5, a, 0, blip.rgb);
            } else {
                pmIcon(ctx, 'B:' + blip.s, bx, by, bs, a);
            }
        }

        // the waypoint, pulsing, its point on the place; the legend's place, ringed; the player
        if (map.wp) {
            pmIcon(ctx, 'waypoint', screenX(f, toMapX(map.wp.x)), screenY(toMapY(map.wp.y)) - 18, 40,
                a * (0.2 + 0.8 * (0.5 + 0.5 * Math.cos(t * Math.PI / 450))));
        }
        if (map.target) {
            pmIcon(ctx, 'target_ring', screenX(f, toMapX(map.target.x)), screenY(toMapY(map.target.y)),
                (bs + 18) * (1 + 0.08 * Math.sin(t / 180)), a);
        }
        pmIcon(ctx, 'navigation_light', screenX(f, toMapX(map.me.x)), screenY(toMapY(map.me.y)), 38, a, 360 - map.me.h);
        if (state.pad) pmIcon(ctx, 'target_ring', W * 0.5, 540, 44, a * 0.9);

        // the bars, the title, the area under the cursor, the character
        fill(ctx, 0, 0, W, f.PT(190), PM_BAR, a * 130 / 255);
        fill(ctx, 0, f.PB(950), W, 1080 - f.PB(950), PM_BAR, a * 130 / 255);
        pmText(ctx, 'MAP', f.PX(96), f.PT(70), f.L(46), PM_WHITE, a, 'left', 'S', 'label');
        var c = cursorPt(f);
        askZone(t, f);
        if (map.zone) pmText(ctx, map.zone, f.PX(96), f.PT(130), f.L(24), PM_GREY, a, 'left', 'M', true);
        if (map.name) pmText(ctx, map.name, f.PX(1824), f.PT(81), f.L(29), PM_WHITE, a, 'right', 'S', true);
        pmText(ctx, map.mode, f.PX(1824), f.PT(58), f.L(15), PM_GREY, a, 'right', 'S', true);

        // the hints, right to left
        var right = f.PX(1824);
        var hy = f.PB(1009);
        right = pmHint(ctx, right, hy, 'BACK', 'circle', 'ESC', a);
        right = pmHint(ctx, right, hy, nearWaypoint(f, c) ? 'REMOVE WAYPOINT' : 'SET WAYPOINT', 'cross', 'LMB', a);
        right = pmHint(ctx, right, hy, 'ZOOM', 'r2', 'MMB', a);
        right = pmHint(ctx, right, hy, 'CENTER', 'triangle', 'C', a);
        if (map.legend.length) {
            pmHint(ctx, right, hy, map.sel >= 0 ? 'NEXT PLACE' : 'LEGEND', map.sel >= 0 ? 'square' : 'r1',
                map.sel >= 0 ? 'DEL' : 'E', a);
        }
        drawLegend(ctx, f, a);
        ctx.globalAlpha = 1;
    }

    // the map's keys: presses for the frame to take, held ones for as long as they are down
    var MAP_HELD = {
        ArrowLeft: 'left', a: 'left', A: 'left', ArrowRight: 'right', d: 'right', D: 'right',
        ArrowUp: 'up', w: 'up', W: 'up', ArrowDown: 'down', s: 'down', S: 'down',
        PageUp: 'zoomIn', PageDown: 'zoomOut'
    };
    var MAP_PRESS = {
        Enter: 'accept', Escape: 'back', Backspace: 'back', Delete: 'alt',
        q: 'lb', Q: 'lb', e: 'rb', E: 'rb', c: 'center', C: 'center'
    };
    // and a pad's, from client/main.lua
    var MAP_PAD = { accept: 'accept', back: 'back', alt: 'alt', center: 'center', lb: 'lb', rb: 'rb' };

    function mapKey(e) {
        var k = e.key;
        if (k === 'p' || k === 'P') {
            post('close');
        } else if (MAP_HELD[k]) {
            map.keys[MAP_HELD[k]] = true;
        } else if (MAP_PRESS[k]) {
            if (!e.repeat) map.input[MAP_PRESS[k]] = true;
        } else {
            return false;
        }
        return true;
    }

    document.addEventListener('keyup', function (e) {
        if (MAP_HELD[e.key]) map.keys[MAP_HELD[e.key]] = false;
    });
    window.addEventListener('blur', function () {
        map.keys = {};
        map.down = false;
    });
    $('pmap').addEventListener('mousedown', function (e) {
        mouse.x = e.clientX;
        mouse.y = e.clientY;
        setPad(false);
        if (e.button === 0) {
            map.down = true;
            map.input.click = true;
        }
    });
    document.addEventListener('mouseup', function (e) {
        if (e.button === 0) map.down = false;
    });
    $('pmap').addEventListener('wheel', function (e) {
        e.preventDefault();
        if (e.deltaY < 0) map.input.scrollUp = true;
        else if (e.deltaY > 0) map.input.scrollDown = true;
    }, { passive: false });

    /* -------------------------------------------------------------------------
       Keys
       ---------------------------------------------------------------------- */
    document.addEventListener('keydown', function (e) {
        if (!state.on) return;
        // a real key: the prompts go back to the keyboard's
        if (e.isTrusted) setPad(false);
        if (state.screen === 'map') {
            if (mapKey(e)) e.preventDefault();
            return;
        }
        var k = e.key;
        if (state.confirm) {
            e.preventDefault();
            if (k === 'Enter') confirmYes();
            else if (k === 'Escape' || k === 'Backspace') back();
            return;
        }
        switch (k) {
            case 'ArrowUp': case 'w': case 'W':
                if (state.screen === 'home') moveTile(-1, 0); else moveRow(-1);
                break;
            case 'ArrowDown': case 's': case 'S':
                if (state.screen === 'home') moveTile(1, 0); else moveRow(1);
                break;
            case 'ArrowLeft': case 'a': case 'A':
                if (state.screen === 'home') moveTile(0, -1); else change(-1);
                break;
            case 'ArrowRight': case 'd': case 'D':
                if (state.screen === 'home') moveTile(0, 1); else change(1);
                break;
            case 'Enter': case ' ':
                select();
                break;
            case 'Escape': case 'Backspace':
                back();
                break;
            case 'p': case 'P':
                post('close');
                break;
            case 'Tab':
                if (state.screen === 'report') moveRow(e.shiftKey ? -1 : 1);
                break;
            default:
                return;
        }
        e.preventDefault();
    });

    // the right mouse button goes back, as in the game's own menu (on the map: unless it is being dragged)
    document.addEventListener('contextmenu', function (e) {
        e.preventDefault();
        if (!state.on) return;
        if (state.screen === 'map') map.input.rightClick = true;
        else back();
    });

    /* -------------------------------------------------------------------------
       From the client
       ---------------------------------------------------------------------- */
    function show(on) {
        state.on = on;
        root.classList.toggle('on', on);
    }

    // A pad's press, read by client/main.lua and handed over as the key this page already knows (on the map, as
    // the map's own press).
    var PAD_KEYS = { up: 'ArrowUp', down: 'ArrowDown', left: 'ArrowLeft', right: 'ArrowRight', accept: 'Enter', back: 'Escape', close: 'p' };
    document.addEventListener('mousemove', function (e) {
        mouse.x = e.clientX;
        mouse.y = e.clientY;
        setPad(false);
    });

    var handlers = {
        pad: function (d) {
            if (state.screen === 'map' && state.on) {
                setPad(true);
                if (d.button === 'close') post('close');
                else if (MAP_PAD[d.button]) map.input[MAP_PAD[d.button]] = true;
                return;
            }
            var key = PAD_KEYS[d.button];
            if (!key) return;
            setPad(true);
            document.dispatchEvent(new KeyboardEvent('keydown', { key: key, bubbles: true, cancelable: true }));
        },
        // the map's stick and triggers, as they stand
        padaxes: function (d) {
            var x = +d.x || 0;
            var y = +d.y || 0;
            var lt = +d.lt || 0;
            var rt = +d.rt || 0;
            if (x || y || lt || rt) setPad(true);
            map.axes = { x: x, y: y, lt: lt, rt: rt };
        },
        mapdata: function (d) {
            if (map.on) setMapData(d.map);
        },
        open: function (d) {
            closeMap();
            state.title = d.title || '';
            state.discord = d.discord || '';
            if (Array.isArray(d.categories) && d.categories.length) state.categories = d.categories;
            $('mode').textContent = d.mode || '';
            $('name').textContent = d.name || '';
            setInitials(d.name);
            setFooter(d.footer);
            if (d.fresh) {
                state.sel = { r: 0, c: 0 };
                state.navX = null;
                state.rowSelOf = {};
                hideConfirm();
                $('list').scrollTop = 0;
            }
            setTiles(d.tiles);
            var screen = d.screen || 'home';
            if (screen === 'home') {
                setScreen('home');
                markTile();
            } else if (screen === 'report') {
                openReport();
            } else {
                // the rows follow in a 'list' message
                setScreen(screen, $('heading').textContent);
            }
            show(true);
        },
        list: function (d) {
            if (d.screen !== state.screen) return;
            setScreen(d.screen, d.title);
            setRows(d.rows);
        },
        tiles: function (d) {
            setTiles(d.tiles);
            markTile();
        },
        footer: function (d) { setFooter(d.footer); },
        // the server's name, when it arrives after the menu opened
        title: function (d) {
            state.title = d.title || '';
            $('title').textContent = state.title;
        },
        mugshot: function (d) { copyFace(d.txd); },
        hide: function () {
            closeMap();
            show(false);
        },
        close: function () {
            closeMap();
            show(false);
            hideConfirm();
            var focused = document.activeElement;
            if (focused && focused.blur) focused.blur();
        }
    };

    window.addEventListener('message', function (e) {
        var d = e.data;
        if (d && handlers[d.type]) handlers[d.type](d);
    });

    updatePrompts();

    // the map's pictures too: its tiles, its blips and icons, its font
    ['m_0_0', 'm_0_1', 'm_1_0', 'm_1_1', 'm_2_0', 'm_2_1', 'd_0_0', 'd_0_1', 'd_1_0', 'd_1_1', 'd_2_0', 'd_2_1',
        'blips', 'ui', 'font'].forEach(mapPic);

    // every picture decoded now, while the game loads, so no tile opens black
    window.VIPM_PRELOAD = ['map', 'brief', 'stats', 'editor', 'game', 'settings', 'players', 'report', 'discord',
        'disconnect', 'crashcam', 'mapnight', 'mapvehicle', 'radio', 'pausemenu', 'keybinds', 'gamesettings', 'beach',
        'boat'].map(function (name) {
        var img = new Image();
        img.src = 'img/' + name + '.webp';
        if (img.decode) img.decode().catch(function () {});
        return img;
    });
})();
