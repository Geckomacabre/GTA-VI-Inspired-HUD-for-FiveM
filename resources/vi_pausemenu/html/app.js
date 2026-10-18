/* GTA VI's pause menu: the page. client/main.lua sends what to show (open, list, tiles, footer, hide, close, map) and
   is told what was chosen (close, screen, tile, setting, report, disconnect, sound). Arrow keys or the mouse move,
   Enter chooses, Esc or Backspace goes back, and at home closes. */
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
        wheel: '<rect class="g-ink g-t" x="12.6" y="9.2" width="10.8" height="17.6" rx="5.4"/>'
            + '<path class="g-ink g-t" d="M12.6 16.4h10.8"/>'
            + '<rect class="g-solid" x="16.7" y="11" width="2.6" height="4" rx="1.3"/>'
    };

    function glyph(name) {
        return '<svg class="glyph" viewBox="0 0 36 36"><circle class="g-face" cx="18" cy="18" r="16.4"/>'
            + (GLYPHS[name] || '') + '</svg>';
    }

    // [[glyph, label, onclick]] into a row of prompts
    function prompts(target, list) {
        target.innerHTML = '';
        list.forEach(function (p) {
            var e = el('div', 'pr');
            e.innerHTML = glyph(p[0]) + '<span></span>';
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
        screen: 'home',     // home, settings, brief, stats, players, report
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
            default:
                // the map, the game's settings, the Rockstar Editor: the client's
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
        $('kicker').textContent = state.title;
        $('heading').textContent = list ? title : state.title;
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

    /* -------------------------------------------------------------------------
       Keys
       ---------------------------------------------------------------------- */
    document.addEventListener('keydown', function (e) {
        if (!state.on) return;
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

    // the right mouse button goes back, as in the game's own menu
    document.addEventListener('contextmenu', function (e) {
        e.preventDefault();
        if (state.on) back();
    });

    /* -------------------------------------------------------------------------
       From the client
       ---------------------------------------------------------------------- */
    function show(on) {
        state.on = on;
        root.classList.toggle('on', on);
    }

    var handlers = {
        open: function (d) {
            state.title = d.title || '';
            state.discord = d.discord || '';
            if (Array.isArray(d.categories) && d.categories.length) state.categories = d.categories;
            $('mode').textContent = d.mode || '';
            $('name').textContent = d.name || '';
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
            $('kicker').textContent = state.title;
            if (state.screen === 'home') $('heading').textContent = state.title;
        },
        hide: function () { show(false); },
        close: function () {
            show(false);
            hideConfirm();
            var focused = document.activeElement;
            if (focused && focused.blur) focused.blur();
        },
        map: function (d) {
            $('map').classList.toggle('on', !!d.show);
            if (d.show) {
                $('map-loc').textContent = d.location || '';
                $('map-mode').textContent = d.mode || '';
                $('map-name').textContent = d.name || '';
            }
        }
    };

    window.addEventListener('message', function (e) {
        var d = e.data;
        if (d && handlers[d.type]) handlers[d.type](d);
    });

    prompts($('map-prompts'), [['enter', 'Set Waypoint'], ['wheel', 'Zoom'], ['esc', 'Back']]);
    updatePrompts();

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
