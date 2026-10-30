(function () {
    'use strict';

    var REFERENCE_HEIGHT = 1080; // the layout numbers in config.lua are 1080p

    // The carousel, as the single-player wheel (ViExtras RadioHud) draws it:
    // tiles are whole out to two slots either side of the highlighted one and
    // fade out on the way to three. The track slides on --slide's curve.
    var SOLID_SLOTS = 2;
    var GONE_SLOTS  = 3;

    var root     = document.documentElement;
    var radio    = document.getElementById('radio');
    var track    = document.getElementById('track');
    var iconL    = document.getElementById('icon-left');
    var iconLImg = document.getElementById('icon-left-img');
    var odSwitch = document.getElementById('od-switch-graphic');
    var iconR    = document.getElementById('icon-right');
    var elLine   = document.getElementById('info-line');
    var elStat   = document.getElementById('station');
    var elTitle  = document.getElementById('title');
    var elArtist = document.getElementById('artist');

    var od          = document.getElementById('od');
    var odForm      = document.getElementById('od-form');
    var odUrl       = document.getElementById('od-url');
    var odQueueBtn  = document.getElementById('od-queue-btn');
    var odNotice    = document.getElementById('od-notice');
    var odQueue     = document.getElementById('od-queue');
    var odQueueNum  = document.getElementById('od-queue-count');
    var odNowTitle  = document.getElementById('od-now-title');
    var odNowArtist = document.getElementById('od-now-artist');
    var odTransport = document.getElementById('od-transport');
    var odVolume    = document.getElementById('od-volume');
    var odVolumeVal = document.getElementById('od-volume-value');
    var odMute      = document.getElementById('od-mute');
    var odClose     = document.getElementById('od-close');
    var odPanelSw   = document.getElementById('od-switch');
    var odSwitchTxt = odPanelSw.querySelector('.switch-state');

    var hud       = null;
    var stations  = [];
    var slots     = [];     // one .slot (holding its .tile) per station
    var index     = 0;
    var muted     = false;
    var odOn      = false;
    var label     = null;   // overrides the station name while On Demand owns the audio
    var isOpen    = false;
    var flashTimer = null;

    // -- helpers -----------------------------------------------------------

    function rgba(str, fallback) {
        var parts = String(str || '').split(',').map(function (n) { return parseFloat(n); });
        if (parts.length < 3 || parts.some(isNaN)) return fallback;
        var a = parts.length > 3 ? parts[3] / 255 : 1;
        return 'rgba(' + parts[0] + ',' + parts[1] + ',' + parts[2] + ',' + a.toFixed(3) + ')';
    }

    function scale() {
        return window.innerHeight / REFERENCE_HEIGHT;
    }

    function px(n) { return n + 'px'; }

    // The tile outline's width at this resolution, in whole device pixels the
    // way the browser will draw it, so the tile can be centred on it exactly.
    function borderPx() {
        var dpr = window.devicePixelRatio || 1;
        var b = num(hud && hud.borderSize, 2.5) * scale() * dpr;
        if (b <= 0) return '0px';
        return (Math.max(1, Math.floor(b + 1e-6)) / dpr) + 'px';
    }

    function num(v, fallback) {
        return typeof v === 'number' && isFinite(v) ? v : fallback;
    }

    function applyHud(cfg) {
        hud = cfg;
        var s = root.style;
        var font = cfg.fontPx || 100;

        s.setProperty('--s', scale());
        s.setProperty('--icon', px(cfg.iconSize));
        s.setProperty('--spacing', px(cfg.spacing));
        s.setProperty('--top', px(cfg.top));
        s.setProperty('--border', px(cfg.borderSize));
        s.setProperty('--border-px', borderPx());
        s.setProperty('--box', rgba(cfg.boxColor, 'rgba(0,0,0,0.667)'));
        s.setProperty('--box-active', rgba(cfg.boxActiveColor, 'rgba(0,0,0,0.667)'));
        s.setProperty('--outline', rgba(cfg.borderColor, 'rgba(255,255,255,0)'));
        s.setProperty('--outline-active', rgba(cfg.borderActiveColor, 'rgba(192,194,200,1)'));
        // Unset, the text stays the stylesheet's white (see style.css).
        if (cfg.inkColor) s.setProperty('--ink', rgba(cfg.inkColor, '#ffffff'));
        s.setProperty('--tile-scale-on', num(cfg.activeScale, 1.03));
        s.setProperty('--tile-scale-off', num(cfg.inactiveScale, 1));
        s.setProperty('--tile-opacity-off', num(cfg.inactiveOpacity, 1));
        s.setProperty('--text-shadow', cfg.textShadow
            ? '0 calc(2px * var(--s)) calc(6px * var(--s)) rgba(0, 0, 0, 0.75)' : 'none');
        radio.classList.toggle('shadowed', !!cfg.textShadow);
        s.setProperty('--slide', (cfg.slideTime || 110) + 'ms');
        s.setProperty('--side-gap', px(cfg.sideGap));
        s.setProperty('--left-icon-h', px(cfg.leftIconHeight));
        s.setProperty('--right-icon-h', px(cfg.rightIconHeight));
        s.setProperty('--mute-color', rgba(cfg.muteColor, '#ffffff'));
        s.setProperty('--muted-color', rgba(cfg.mutedColor, '#ff3b30'));
        radio.classList.toggle('dim-off', cfg.muteDim === false);
        s.setProperty('--line-y', px(cfg.infoLineY));
        s.setProperty('--line-w', px(cfg.infoLineWidth));
        s.setProperty('--line-h', px(cfg.infoLineHeight));
        s.setProperty('--station-y', px(cfg.stationY));
        s.setProperty('--station-size', px(font * cfg.stationScale));
        s.setProperty('--title-y', px(cfg.titleY));
        s.setProperty('--title-size', px(font * cfg.titleScale));
        s.setProperty('--artist-y', px(cfg.artistY));
        s.setProperty('--artist-size', px(font * cfg.artistScale));

        // With On Demand on the left icon is a live switch; without it, it is
        // the static artwork the original mod drew there.
        if (cfg.leftIcon) iconLImg.src = cfg.leftIcon;
        iconLImg.hidden = !!cfg.odSwitch;
        odSwitch.hidden = !cfg.odSwitch;
        iconL.style.display = cfg.sideIcons ? '' : 'none';
        iconR.style.display = cfg.sideIcons ? '' : 'none';
        elLine.style.display = cfg.infoLineHeight > 0 ? '' : 'none';
    }

    function buildTrack(list) {
        stations = list || [];
        track.innerHTML = '';
        slots = [];

        stations.forEach(function (station, i) {
            var slot = document.createElement('div');
            slot.className = 'slot';
            var tile = document.createElement('div');
            // New tiles start in their end state, as the single-player wheel's do.
            tile.className = 'tile' + (i === index ? ' active' : '');

            if (station.logo && (!hud || hud.stationLogos !== false)) {
                var img = document.createElement('img');
                img.src = station.logo;
                // A missing PNG should not leave an empty box.
                img.onerror = function () {
                    tile.innerHTML = '';
                    tile.appendChild(fallbackNode(station.label));
                };
                tile.appendChild(img);
            } else {
                tile.appendChild(fallbackNode(station.label));
            }

            slot.appendChild(tile);
            track.appendChild(slot);
            slots.push(slot);
        });
    }

    // Paints a white glyph PNG as a mask so it can be tinted. A div has no
    // intrinsic size, so the aspect ratio is read off the file once and cached.
    var ratioCache = {};

    function setMaskIcon(el, src) {
        if (!src) return;
        el.style.webkitMaskImage = 'url("' + src + '")';
        el.style.maskImage = 'url("' + src + '")';

        if (ratioCache[src]) {
            el.style.aspectRatio = ratioCache[src];
            return;
        }

        var probe = new Image();
        probe.onload = function () {
            if (!probe.naturalHeight) return;
            ratioCache[src] = probe.naturalWidth + ' / ' + probe.naturalHeight;
            el.style.aspectRatio = ratioCache[src];
        };
        probe.src = src;
    }

    function fallbackNode(text) {
        var span = document.createElement('span');
        span.className = 'fallback';
        span.textContent = text || '';
        return span;
    }

    // -- the carousel's slide ----------------------------------------------
    // The track's place is a fractional index, eased from where it was to the
    // new one over --slide on cubic-bezier(0.22, 0.61, 0.36, 1), and every
    // tile is placed and faded off it each frame while that runs (a CSS
    // transition could slide the track, but not fade a tile by where it is
    // mid-slide). The tiles' own scale and outline are CSS transitions.

    var dispFrom = 0, dispTo = 0, dispStart = -1, placed = false, frame = 0;

    function cubic(a, b, t) {
        var u = 1 - t;
        return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t;
    }

    // CSS cubic-bezier(x1, y1, x2, y2) at x, by bisection.
    function bezier(x1, y1, x2, y2, x) {
        if (x <= 0) return 0;
        if (x >= 1) return 1;
        var lo = 0, hi = 1, t = x;
        for (var i = 0; i < 24; i++) {
            t = (lo + hi) / 2;
            if (cubic(x1, x2, t) < x) lo = t; else hi = t;
        }
        return cubic(y1, y2, t);
    }

    function slideMs() { return Math.max(1, (hud && hud.slideTime) || 110); }

    function disp(t) {
        if (dispStart < 0) return dispTo;
        var p = Math.min(1, Math.max(0, (t - dispStart) / slideMs()));
        return dispFrom + (dispTo - dispFrom) * bezier(0.22, 0.61, 0.36, 1, p);
    }

    function layout(t) {
        var d = disp(t);
        var step = (hud ? hud.spacing : 118) * scale();
        for (var i = 0; i < slots.length; i++) {
            var rel = i - d;
            var far = Math.abs(rel);
            var a = far >= GONE_SLOTS ? 0 : far <= SOLID_SLOTS ? 1 : GONE_SLOTS - far;
            var slot = slots[i];
            slot.style.left = (rel * step).toFixed(2) + 'px';
            slot.style.opacity = a.toFixed(3);
            slot.style.visibility = a > 0.001 ? 'visible' : 'hidden';
        }
    }

    function animate() {
        frame = 0;
        var t = performance.now();
        layout(t);
        if (dispStart >= 0 && t - dispStart < slideMs()) frame = requestAnimationFrame(animate);
        else dispStart = -1;
    }

    function slideTo(i) {
        var t = performance.now();
        if (!placed) {
            dispFrom = dispTo = i;
            dispStart = -1;
            placed = true;
        } else if (Math.abs(dispTo - i) > 0.0001) {
            dispFrom = disp(t);
            dispTo = i;
            dispStart = t;
        }
        layout(t);
        if (dispStart >= 0 && !frame) frame = requestAnimationFrame(animate);
    }

    // -- rendering ---------------------------------------------------------

    function render() {
        for (var i = 0; i < slots.length; i++) {
            slots[i].firstChild.classList.toggle('active', i === index);
        }
        slideTo(index);

        var station = stations[index];
        elStat.textContent = label || (station ? station.label : '');

        radio.classList.toggle('muted', muted);
        radio.classList.toggle('od-on', odOn);

        if (hud) setMaskIcon(iconR, muted ? hud.unmuteIcon : hud.rightIcon);
    }

    // The two lines under the station, as the single-player wheel sets them:
    // the song on the first and its artist on the second; with no song, the
    // station's genre on the second; a highlighted RADIO OFF blanks both.
    function renderNowPlaying(title, artist) {
        var station = stations[index];
        // A highlighted "radio off" tile blanks the lines -- unless On Demand
        // is what is actually playing, in which case they are not its lines.
        var isOff = station && station.off && !label;

        if (isOff) {
            elTitle.textContent = '';
            elArtist.textContent = '';
            return;
        }

        // The artist only goes with a song.
        if (title) {
            elTitle.textContent = title;
            elArtist.textContent = artist || '';
            return;
        }

        // No song: the station's genre, as the wheel does in the single-player
        // mod when a track has no name (a talk station).
        elTitle.textContent = '';
        var wantsGenre = !hud || hud.subtitle === 'genre';
        elArtist.textContent = (wantsGenre && station && station.genre) ? station.genre : '';
    }

    function setVisible(visible) {
        radio.classList.toggle('hidden', !visible);
    }

    // -- messages ----------------------------------------------------------

    window.addEventListener('message', function (event) {
        var data = event.data || {};

        if (data.action === 'state') {
            if (data.hud) applyHud(data.hud);
            if (typeof data.index === 'number') index = data.index;
            if (data.list) buildTrack(data.list);

            muted  = !!data.muted;
            odOn   = !!data.odOn;
            label  = data.label || null;
            isOpen = !!data.open;

            render();
            renderNowPlaying(data.title, data.artist);

            if (flashTimer) { clearTimeout(flashTimer); flashTimer = null; }
            setVisible(isOpen);
            return;
        }

        // The song changed (or its name came in): the lines only, so a mute
        // flash on screen is left to run its course.
        if (data.action === 'track') {
            label = data.label || null;
            var station = stations[index];
            elStat.textContent = label || (station ? station.label : '');
            renderNowPlaying(data.title, data.artist);
            return;
        }

        if (data.action === 'flash') {
            muted = !!data.muted;
            render();
            setVisible(true);
            if (flashTimer) clearTimeout(flashTimer);
            flashTimer = setTimeout(function () {
                if (!isOpen) setVisible(false);
                flashTimer = null;
            }, 1400);
            return;
        }

        // The pause menu, a cutscene or a black screen: nothing of the HUD shows
        // over it, as in single player.
        if (data.action === 'hold') {
            radio.classList.toggle('held', !!data.held);
            return;
        }

        if (data.action === 'od') {
            if (typeof data.notice === 'string') { notice(data.notice); return; }
            if (data.state) renderPanel(data.state);
            setPanelOpen(!!data.open);
            return;
        }

        if (data.action === 'sound') {
            var audio = new Audio(data.file);
            audio.volume = Math.max(0, Math.min(1, data.volume));
            audio.play().catch(function () { /* autoplay gate, ignore */ });
            return;
        }
    });

    window.addEventListener('resize', function () {
        root.style.setProperty('--s', scale());
        root.style.setProperty('--border-px', borderPx());
        layout(performance.now());
    });


    // -- On Demand panel ---------------------------------------------------

    // The only part of this page that ever talks back to the client. The wheel
    // itself stays a one-way HUD: it takes no focus and posts nothing.
    var RESOURCE = 'vi_radio';
    var odState  = null;
    var noticeTimer = null;

    function post(name, data, done) {
        fetch('https://' + RESOURCE + '/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (res) {
            return res.json().catch(function () { return null; });
        }).then(function (body) {
            if (done) done(body);
        }).catch(function () { /* not running in game */ });
    }

    function notice(message, ok) {
        odNotice.textContent = message || '';
        odNotice.classList.toggle('ok', !!ok);
        if (noticeTimer) clearTimeout(noticeTimer);
        if (message) {
            noticeTimer = setTimeout(function () {
                odNotice.textContent = '';
                noticeTimer = null;
            }, 5000);
        }
    }

    function duration(seconds) {
        if (!seconds || seconds <= 0) return '';
        var total = Math.round(seconds);
        var mins  = Math.floor(total / 60);
        var secs  = total % 60;
        return mins + ':' + (secs < 10 ? '0' : '') + secs;
    }

    function renderQueue(state) {
        var queue = state.queue || [];
        odQueue.innerHTML = '';
        odQueueNum.textContent = state.stationLabel
            ? state.stationLabel + '  \u00B7  ' + queue.length
            : queue.length + ' / ' + state.limit;

        if (!queue.length) {
            var empty = document.createElement('li');
            empty.className = 'empty';
            empty.textContent = 'Nothing queued. Paste a link to start one.';
            odQueue.appendChild(empty);
            return;
        }

        queue.forEach(function (entry, i) {
            var row = document.createElement('li');
            if (i + 1 === state.index) row.classList.add('playing');

            var pos = document.createElement('span');
            pos.className = 'pos';
            pos.textContent = (i + 1 === state.index) ? '\u25B6' : String(i + 1);

            var name = document.createElement('span');
            name.className = 'name';
            name.textContent = entry.title || 'Track';

            var by = document.createElement('span');
            by.className = 'by';
            by.textContent = [entry.artist, duration(entry.duration)]
                .filter(Boolean).join('  \u00B7  ');

            var remove = document.createElement('button');
            remove.type = 'button';
            remove.textContent = 'Remove';
            remove.addEventListener('click', function () {
                post('odRemove', { index: i + 1 });
            });

            row.appendChild(pos);
            row.appendChild(name);
            row.appendChild(by);
            row.appendChild(remove);
            odQueue.appendChild(row);
        });
    }

    function renderPanel(state) {
        odState = state;

        var playing = !!state.playing;

        odPanelSw.setAttribute('aria-checked', state.engaged ? 'true' : 'false');
        odSwitchTxt.textContent = state.engaged ? 'On' : 'Off';

        odNowTitle.textContent  = playing ? (state.title || 'Track') : 'Nothing queued';
        odNowArtist.textContent = playing
            ? [state.artist, state.paused ? 'Paused' : null].filter(Boolean).join('  \u00B7  ')
            : '';

        Array.prototype.forEach.call(odTransport.children, function (button) {
            button.disabled = !playing;
            if (button.dataset.act === 'pause') {
                button.textContent = state.paused ? 'Resume' : 'Pause';
            }
        });

        renderQueue(state);

        var volume = typeof state.volume === 'number' ? state.volume : 0;
        odVolume.max = state.maxVolume;
        odVolume.value = volume;
        odVolumeVal.textContent = volume + '%';
        odMute.checked = !!state.muted;
    }

    function setPanelOpen(open) {
        od.classList.toggle('hidden', !open);
        if (open) {
            odUrl.value = '';
            notice('');
            setTimeout(function () { odUrl.focus(); }, 30);
        } else if (noticeTimer) {
            clearTimeout(noticeTimer);
            noticeTimer = null;
        }
    }

    function submitLink(playNow) {
        var url = odUrl.value.trim();
        if (!url) { notice('Paste a link first'); return; }

        post('odAdd', { url: url, playNow: playNow }, function (body) {
            if (body && body.ok === false) {
                notice(body.error || 'That link was rejected');
                return;
            }
            odUrl.value = '';
            notice(playNow ? 'Playing' : 'Added to the queue', true);
        });
    }

    odForm.addEventListener('submit', function (event) {
        event.preventDefault();
        submitLink(true);
    });

    odQueueBtn.addEventListener('click', function () { submitLink(false); });
    odClose.addEventListener('click', function () { post('odClose'); });
    odPanelSw.addEventListener('click', function () { post('odDisengage'); });

    odTransport.addEventListener('click', function (event) {
        var act = event.target.dataset && event.target.dataset.act;
        if (!act) return;
        if (act === 'next')  post('odSkip', { dir: 1 });
        if (act === 'prev')  post('odSkip', { dir: -1 });
        if (act === 'pause') post('odPause');
        if (act === 'stop')  post('odStop');
    });

    odVolume.addEventListener('input', function () {
        odVolumeVal.textContent = odVolume.value + '%';
    });
    odVolume.addEventListener('change', function () {
        post('odVolume', { volume: Number(odVolume.value) });
    });

    odMute.addEventListener('change', function () {
        post('odMute', { muted: odMute.checked });
    });

    document.addEventListener('keydown', function (event) {
        if (od.classList.contains('hidden')) return;
        if (event.key === 'Escape') {
            event.preventDefault();
            post('odClose');
        }
    });

    root.style.setProperty('--s', scale());
}());
