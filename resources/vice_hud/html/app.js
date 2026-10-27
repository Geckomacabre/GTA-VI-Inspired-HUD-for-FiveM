/* =============================================================================
   vice_hud NUI
   -----------------------------------------------------------------------------
   Receives messages from client.lua and updates the DOM. No framework, no build
   step — what is on disk is what runs, so there is no way for a stale bundle to
   silently ship.

   Every handler is defensive about missing fields: client.lua may extend the
   payloads later, and a missing key must never throw and take the whole HUD out.
   ========================================================================== */
(function () {
    'use strict';

    var $ = function (id) { return document.getElementById(id); };
    var stage = $('stage');

    /* --- helpers --------------------------------------------------------- */

    function show(el, visible) {
        if (!el) return;
        el.classList.toggle('hidden', !visible);
    }

    // The two glyphs drawn as pictures rather than letters. Keyed by the
    // sentinel resolveKey (client.lua) returns for INPUT_ATTACK / INPUT_AIM --
    // GetControlInstructionalButton has no text glyph for a mouse button, so
    // there is nothing to letter even if we wanted to.
    var MOUSE_GLYPHS = { LMB: 'icons/LMB.png', RMB: 'icons/RMB.png' };

    /* ---- button glyphs -------------------------------------------------------
       Every button on the HUD is drawn here, from a TOKEN and the device that
       token belongs to. client_glyphs.lua resolves both from the player's
       live bind and re-sends them when the player changes device.

         pad    the Xbox NAMES: A B X Y, LB RB LT RT, LS RS, DPAD, START BACK,
                with _UP _DOWN _LEFT _RIGHT _X _Y on the sticks and the D-pad.
                `padStyle` decides whether "A" is an Xbox A or a PlayStation
                cross (Config.PadGlyphs, or the player's own /hudpad).
         kbm    a key cap carrying the key's own text, an arrow, or the mouse.

       Each button is ONE svg, face and ink together in a 36-unit box centred
       on (18,18). Separate boxes stacked on top of each other get snapped to
       the pixel grid one by one, and the ink ends up a pixel off its face.
       ------------------------------------------------------------------------ */
    var padStyle = 'xbox';
    var PAD_TONE = { A: 'pad-a', B: 'pad-b', X: 'pad-x', Y: 'pad-y' };

    var G_DISC = '<circle class="g-face" cx="18" cy="18" r="16.4"/>';
    var G_KEY = '<rect class="g-face" x="2.4" y="2.4" width="31.2" height="31.2" rx="6.6"/>';
    var G_LINES = '<path class="g-ink g-s" d="M11.4 12.6h13.2M11.4 18h13.2M11.4 23.4h13.2"/>';

    var G_FACE = {
        xbox: {
            A: '<path class="g-ink" d="M11.6 25.2 18 10.8l6.4 14.4M14 20.2h8"/>',
            B: '<path class="g-ink" d="M12.9 10.8v14.4h6.2a4 4 0 0 0 0-8h-6.2m5.5 0a3.2 3.2 0 0 0 0-6.4h-5.5"/>',
            X: '<path class="g-ink" d="M12.4 10.8l11.2 14.4M23.6 10.8 12.4 25.2"/>',
            Y: '<path class="g-ink" d="M12.2 10.8 18 18.6l5.8-7.8M18 18.6v6.6"/>'
        },
        ps: {
            A: '<path class="g-ink" d="M12.3 12.3l11.4 11.4M23.7 12.3 12.3 23.7"/>',
            B: '<circle class="g-ink" cx="18" cy="18" r="6.9"/>',
            X: '<rect class="g-ink" x="11.6" y="11.6" width="12.8" height="12.8" rx="0.8"/>',
            // An equilateral triangle sits in a circle by its centroid, not by
            // the middle of its bounding box; that is where a pad prints it.
            Y: '<path class="g-ink" d="M18 9.6 25.39 22.4H10.61Z"/>'
        }
    };
    var G_SHOULDER = {
        xbox: { LB: 'LB', RB: 'RB', LT: 'LT', RT: 'RT' },
        ps: { LB: 'L1', RB: 'R1', LT: 'L2', RT: 'R2' }
    };
    var G_MENU = {
        xbox: {
            START: G_LINES,
            BACK: '<rect class="g-ink g-s" x="10" y="10.6" width="11.2" height="9" rx="1.2"/>'
                + '<path class="g-ink g-s" d="M14.8 22.4v1.8a1.2 1.2 0 0 0 1.2 1.2h8.8a1.2 1.2 0 0 0 '
                + '1.2-1.2v-6.6a1.2 1.2 0 0 0-1.2-1.2h-.9"/>'
        },
        ps: {
            START: G_LINES,
            BACK: '<rect class="g-ink g-s" x="8.6" y="11.6" width="18.8" height="12.8" rx="3.2"/>'
        }
    };
    // Which way a stick or the D-pad is being asked for. _X is left+right,
    // _Y is up+down.
    var G_DIRS = { UP: ['UP'], DOWN: ['DOWN'], LEFT: ['LEFT'], RIGHT: ['RIGHT'],
                   X: ['LEFT', 'RIGHT'], Y: ['UP', 'DOWN'] };
    var G_STICK_MARK = { UP: 'M18 3.3l3 3.5h-6z', DOWN: 'M18 32.7l3-3.5h-6z',
                         LEFT: 'M3.3 18l3.5-3v6z', RIGHT: 'M32.7 18l-3.5-3v6z' };
    var G_STICK_LETTER = {
        L: '<path class="g-ink g-s" d="M15.2 13.4v9.2h5.6"/>',
        R: '<path class="g-ink g-s" d="M14.9 22.6v-9.2h3.5a2.7 2.7 0 0 1 0 5.4h-3.5m3.3 0 2.9 3.8"/>'
    };
    var G_DPAD = 'M14.7 7.2h6.6v7.5h7.5v6.6h-7.5v7.5h-6.6v-7.5H7.2v-6.6h7.5z';
    var G_DPAD_ARM = { UP: 'M14.7 7.2h6.6v7.5h-6.6z', DOWN: 'M14.7 21.3h6.6v7.5h-6.6z',
                       LEFT: 'M7.2 14.7h7.5v6.6H7.2z', RIGHT: 'M21.3 14.7h7.5v6.6h-7.5z' };
    var G_ARROW = { UP: 0, RIGHT: 90, DOWN: 180, LEFT: 270 };
    var G_MOUSE_BODY = '<rect class="g-ink g-t" x="12.2" y="9" width="11.6" height="18" rx="5.8"/>'
        + '<path class="g-ink g-t" d="M12.2 16.6h11.6"/>'
        + '<rect class="g-solid" x="16.6" y="10.8" width="2.8" height="4.2" rx="1.4"/>';
    var G_MOUSE = {
        MMB: G_MOUSE_BODY,
        WHEEL_UP: G_MOUSE_BODY + '<path class="g-ink g-t" d="M15.4 23.4l2.6-2.6 2.6 2.6"/>',
        WHEEL_DOWN: G_MOUSE_BODY + '<path class="g-ink g-t" d="M15.4 21.4l2.6 2.6 2.6-2.6"/>'
    };

    function glyphEscape(s) {
        return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }

    // Capitals are centred on their own height, not on the line box: the
    // baseline goes half a cap-height (0.35 em in Bahnschrift) below centre.
    function glyphText(text, cx, cy, size) {
        return '<text class="g-text" x="' + cx + '" y="' + (cy + size * 0.35).toFixed(2)
            + '" font-size="' + size + '" text-anchor="middle">' + glyphEscape(text) + '</text>';
    }

    function glyphMarks(dirs, table, cls) {
        return (dirs || []).map(function (d) {
            return '<path class="' + cls + '" d="' + table[d] + '"/>';
        }).join('');
    }

    // -> { w, svg, cls } for a button, or null when there is none to draw.
    // `w` is the width of its box in the same units as the 36 it is tall.
    function glyphArt(token, device) {
        var t = token == null ? '' : String(token);
        if (!t) return null;
        var style = padStyle === 'ps' ? 'ps' : 'xbox';

        if (device === 'pad') {
            if (G_FACE[style][t]) {
                return { w: 36, svg: G_DISC + G_FACE[style][t],
                         cls: 'pad face' + (style === 'xbox' ? ' ' + PAD_TONE[t] : '') };
            }
            if (G_SHOULDER[style][t]) {
                var trigger = t.charAt(1) === 'T';
                return { w: 48, cls: 'pad ' + (trigger ? 'trigger' : 'bumper'),
                         svg: (trigger
                             ? '<path class="g-face" d="M8.6 29.4V15.2Q8.6 5.6 18.2 5.6h11.6q9.6 0 9.6 '
                               + '9.6v14.2q0 1-1 1H9.6q-1 0-1-1z"/>'
                             : '<rect class="g-face" x="3.6" y="8" width="40.8" height="20" rx="7.2"/>')
                             + glyphText(G_SHOULDER[style][t], 24, trigger ? 18.8 : 18, 13.6) };
            }
            var m = /^(LS|RS|DPAD)(?:_(UP|DOWN|LEFT|RIGHT|X|Y))?$/.exec(t);
            if (m && m[1] === 'DPAD') {
                var arms = G_DIRS[m[2]];
                return { w: 36, cls: 'pad dpad',
                         svg: G_DISC + '<path class="g-solid' + (arms ? ' g-dim' : '') + '" d="' + G_DPAD + '"/>'
                             + glyphMarks(arms, G_DPAD_ARM, 'g-solid') };
            }
            if (m) {
                return { w: 36, cls: 'pad stick',
                         svg: G_DISC + '<circle class="g-rim" cx="18" cy="18" r="10.4"/>'
                             + G_STICK_LETTER[m[1].charAt(0)]
                             + glyphMarks(G_DIRS[m[2]], G_STICK_MARK, 'g-solid') };
            }
            if (G_MENU[style][t]) return { w: 36, svg: G_DISC + G_MENU[style][t], cls: 'pad menu' };
        }

        // Keyboard and mouse -- and anything a pad token had no drawing for,
        // which is better shown as its own name on a cap than not at all.
        if (MOUSE_GLYPHS[t]) {
            return { w: 36, cls: 'key mouse',
                     svg: G_KEY + '<image class="g-img" href="' + MOUSE_GLYPHS[t]
                         + '" x="5.4" y="5.4" width="25.2" height="25.2"/>' };
        }
        if (G_MOUSE[t]) return { w: 36, svg: G_KEY + G_MOUSE[t], cls: 'key mouse' };
        if (G_ARROW[t] != null) {
            return { w: 36, cls: 'key',
                     svg: G_KEY + '<path class="g-ink" transform="rotate(' + G_ARROW[t]
                         + ' 18 18)" d="M18 25.4V10.6M12 16.6l6-6 6 6"/>' };
        }
        if (t.length === 1) return { w: 36, svg: G_KEY + glyphText(t, 18, 18, 19.5), cls: 'key' };
        var w = Math.round(15 + t.length * 9.2);
        return { w: w, cls: 'key wide',
                 svg: '<rect class="g-face" x="2.4" y="2.4" width="' + (w - 4.8)
                     + '" height="31.2" rx="6.6"/>' + glyphText(t, w / 2, 18, 15.5) };
    }

    // The ring a hold-to-confirm button fills. It follows the button's own
    // outline -- a circle round a disc, a rounded box round anything else --
    // and lives in the button's svg, so the two share one centre exactly.
    // The fill starts at twelve o'clock and runs clockwise; how far is
    // --prompt-frac, written by onPromptProgress.
    var G_RING_PAD = 6;

    function glyphRing(art) {
        var shape;
        if (/\b(face|stick|dpad|menu)\b/.test(art.cls)) {
            shape = function (cls, extra) {
                return '<circle class="' + cls + '" cx="18" cy="18" r="20.4"' + (extra || '') + '/>';
            };
            return shape('g-ring-edge') + shape('g-ring-track')
                + shape('g-ring-fill', ' pathLength="100" transform="rotate(-90 18 18)"');
        }
        // A rect's outline starts after its top-left corner, which is close
        // enough to "the top" that it needs no turning.
        shape = function (cls, extra) {
            return '<rect class="' + cls + '" x="-1.6" y="-1.6" width="' + (art.w + 3.2)
                + '" height="39.2" rx="10.6"' + (extra || '') + '/>';
        };
        return shape('g-ring-edge') + shape('g-ring-track') + shape('g-ring-fill', ' pathLength="100"');
    }

    // Turn `el` into the button for token + device. `base` is the class the
    // element keeps whatever it is showing ('glyph' unless told otherwise).
    // `ring` is true for the hold ring round it, or 'space' to leave the
    // ring's room without drawing one -- which is how a column of prompts,
    // some held and some pressed, keeps every button on one centre line: the
    // boxes are all the same size. With nothing to draw the element is left
    // empty and marked .none, so a row can show its label alone.
    function setGlyph(el, token, device, base, ring) {
        var art = glyphArt(token, device);
        el.textContent = '';
        el.removeAttribute('data-glyph');
        el.className = (base || 'glyph') + (art ? ' ' + art.cls : ' none');
        el.style.removeProperty('--g-w');
        el.style.removeProperty('--g-s');
        if (!art) return el;

        var pad = ring ? G_RING_PAD : 0;
        el.setAttribute('data-glyph', String(token));
        if (ring === true) el.classList.add('ringed');
        // The box grows by the ring's margin on every side, so the button
        // inside it stays exactly the size it is without one.
        el.style.setProperty('--g-w', (art.w + pad * 2) / 36);
        el.style.setProperty('--g-s', (36 + pad * 2) / 36);
        el.innerHTML = '<svg class="g-art" viewBox="' + (-pad) + ' ' + (-pad) + ' '
            + (art.w + pad * 2) + ' ' + (36 + pad * 2) + '" aria-hidden="true">'
            + (ring === true ? glyphRing(art) : '') + art.svg + '</svg>';
        return el;
    }

    function setFill(rowId, value) {
        var row = $(rowId);
        if (!row) return;
        var fill = row.querySelector('.sfill');
        if (fill) {
            // Set the transform DIRECTLY. Driving it through a custom property
            // silently froze the bar: a transition on a property whose value
            // comes from an unregistered var() never re-evaluates when that var
            // changes, so --fill updated while the rendered transform stayed put.
            var pct = Math.max(0, Math.min(100, value || 0));
            fill.style.transform = 'scaleX(' + (pct / 100).toFixed(4) + ')';
        }
    }

    /* Auto-hide with anti-flicker: showing is immediate, hiding is deferred.
       Values arrive from a poll and oscillate on their thresholds during normal
       play (health regenerating 99<->100, stamina ticking back up), which
       without this hold would strobe the bars on and off. */
    var HIDE_HOLD_MS = 1200;
    var hideTimers = {};

    function setVisible(key, el, shouldShow) {
        if (!el) return;
        if (shouldShow) {
            if (hideTimers[key]) { clearTimeout(hideTimers[key]); delete hideTimers[key]; }
            show(el, true);
        } else if (!hideTimers[key] && !el.classList.contains('hidden')) {
            hideTimers[key] = setTimeout(function () {
                delete hideTimers[key];
                show(el, false);
            }, HIDE_HOLD_MS);
        }
    }

    /* --- status bars ----------------------------------------------------- */

    /* Oxygen is its own row (#s-oxygen), not a stamina-bar reskin -- the
       presence of `oxygen` in the payload IS the show/hide switch, same "one
       value decides the state" reasoning the old shared-track version used. */

    /* Health used to show continuously whenever it was below 100 -- which in
       practice meant almost always, since a scratch of chip damage sits there
       for minutes with nothing else to clear it, unlike stamina/focus which
       mostly return to full within a second or two of letting off the key.
       So this now reveals on an actual CHANGE (a hit or a heal) and holds for
       HEALTH_FLASH_MS, the same "a STATE is not a LEVEL" fix already applied
       to the vehicle lock pip -- see vice-hud-nav-popup memory. `null` on the
       first payload so a fresh page load does not treat "no history yet" as
       a change. */
    var HEALTH_FLASH_MS = 3000;
    var lastHealthVal = null;
    var healthFlashTimer = null;
    var healthRecentlyChanged = false;

    /* The bolt beside the stamina bar, in red. Two things can ask for it.
       A flash (`staminaBolt`, which client_vitals.lua sends every 0.9 s for
       as long as the bar is going down -- what the reference does): the bolt
       is red at once and fades back to teal over `ms`. That is .bolt-flash,
       whose animation in style.css is the fade; it is taken off and put back
       so each flash starts from full red. And `boltRed` in the status payload
       (Config.Stamina.boltRed = 'drain'), which holds it red: .bolt-red. */
    var boltTimer = null;

    function onStaminaBolt(d) {
        var row = $('s-stamina');
        if (boltTimer) { clearTimeout(boltTimer); boltTimer = null; }
        if (!row) return;
        row.classList.remove('bolt-flash');
        if (!d || !d.red) return;
        var ms = Number(d.ms);
        if (!isFinite(ms) || ms <= 0) ms = 210;
        ms = Math.min(ms, 5000);
        row.style.setProperty('--bolt-ms', ms + 'ms');
        void row.offsetWidth;       // the animation restarts only if the page has seen the class gone
        row.classList.add('bolt-flash');
        boltTimer = setTimeout(function () {
            boltTimer = null;
            row.classList.remove('bolt-flash');
        }, ms);
    }

    function onStatus(d) {
        var health = d.health == null ? 100 : d.health;
        var focus = d.focus == null ? 100 : d.focus;
        var focusActive = !!d.focusActive;
        var stamina = d.stamina == null ? 100 : d.stamina;
        var oxygen = d.oxygen == null ? null : d.oxygen;
        var submerged = oxygen !== null;
        var staminaRow = $('s-stamina');
        var focusRow = $('s-focus');
        var oxygenRow = $('s-oxygen');
        var wheelOpen = !!d.wheel;

        // d.cap/d.capCause (the hunger/thirst regen cap) used to force this
        // row up unconditionally -- see onStatus's own visibility comment
        // below for why that was dropped. Nothing else reads them; the
        // .scap tail they once drove was already disconnected from live
        // game state by an earlier, explicit request (see .scap in
        // style.css), so there is nothing left in the payload worth keeping
        // a variable for.

        if (lastHealthVal !== null && health !== lastHealthVal) {
            healthRecentlyChanged = true;
            if (healthFlashTimer) clearTimeout(healthFlashTimer);
            healthFlashTimer = setTimeout(function () {
                healthFlashTimer = null;
                healthRecentlyChanged = false;
            }, HEALTH_FLASH_MS);
        }
        lastHealthVal = health;

        // Bar LENGTH follows max health (client_skills.lua raises it with the
        // Health skill). Only the health and oxygen rows read these; stamina and
        // focus are fixed. Clamped so a bad payload cannot make a screen-wide bar.
        var statusEl = $('status');
        if (statusEl) {
            var hpLen = Number(d.hpLen);
            var hpMax = Number(d.hpMaxLen);
            if (isFinite(hpLen) && hpLen > 0) statusEl.style.setProperty('--hp-len', Math.max(0.5, Math.min(3, hpLen)).toFixed(4));
            if (isFinite(hpMax) && hpMax > 0) statusEl.style.setProperty('--hp-max-len', Math.max(1, Math.min(3, hpMax)).toFixed(4));
        }

        setFill('s-health', health);
        setFill('s-focus', focus);
        if (focusRow) focusRow.classList.toggle('active', focusActive);
        var focusFx = $('focus-fx');
        if (focusFx) focusFx.classList.toggle('active', focusActive);
        setFill('s-stamina', stamina);
        if (staminaRow) staminaRow.classList.toggle('bolt-red', d.boltRed === true);
        if (submerged) setFill('s-oxygen', oxygen);

        // Nominal state is an empty top-left corner, matching the reference.
        // Shown on a recent change (a hit or a heal) or while the weapon/item
        // wheel is open (Tab -- client.lua reads the control directly, so
        // this works regardless of which inventory owns the wheel).
        //
        // needsWarning USED to also force this row up, on the reasoning that
        // full health you cannot heal back into is worth knowing about before
        // something takes a bite out of it. In practice Config.Needs.warnAt
        // (25) means hunger or thirst dips under it during perfectly ordinary
        // play -- nobody eats/drinks on a strict schedule -- so this held the
        // row up almost permanently, the exact "always visible" complaint the
        // switch to change-only flashing (see healthRecentlyChanged above)
        // was supposed to fix in the first place, just reached through the
        // cap instead of the raw health value. Dropped so health behaves like
        // every other row: quiet until something actually happens to it.
        setVisible('health', $('s-health'), healthRecentlyChanged || wheelOpen);
        // Focus is nominal at FULL (the opposite of armour's nominal-at-zero),
        // so it shows whenever it's spent at all, or actively draining.
        // `wheelOpen` also force-shows the other three rows now -- the same
        // "you're actively looking at your own stats" reveal health already
        // got, so a full inventory or character switch shows every bar
        // rather than leaving stamina/focus/oxygen hidden at their nominal
        // values while everything else on screen is deliberately expanded.
        setVisible('focus', focusRow, focusActive || focus < 100 || wheelOpen);
        setVisible('stamina', staminaRow, stamina < 100 || wheelOpen);
        // Underwater the row shows unconditionally: full breath still means a
        // clock is running, and that is exactly when you want to see it. The
        // hide-hold then carries it a beat past surfacing rather than
        // blinking out the instant oxygen stops being sent.
        setVisible('oxygen', oxygenRow, submerged || wheelOpen);
    }

    /* --- wanted ---------------------------------------------------------- */

    var STAR_PATH = 'M50 5 L61 38 L96 38 L68 59 L79 92 L50 71 L21 92 L32 59 L4 38 L39 38 Z';
    /* The "tells" are red ROUNDED SQUARES with white line-art, measured off the
       original reference at ~0.88% of width by ~1.94% of height — not emoji in
       circles. Drawn as inline SVG so they stay crisp and match the reference
       weight.

       A later, more complete reference set ("GRAND THEFT AUTO VI: HUD
       DEFINITIONS") replaced the placeholder five with six specific police-
       knowledge tells; see getWantedTells() in client.lua for what drives
       each one:
         camera  — CCTV: you're on camera and revisiting the spot risks being
                   made. No detector wired to this yet; see
                   exports.vice_hud:SetWantedTellOverride
         weapon  — police know exactly which weapon you're carrying
         person  — one suspect identified (fenix-police's `voice` signal,
                   nobody else nearby when it fired)
         people  — MULTIPLE suspects identified (same `voice` signal, but
                   another player was nearby when it fired) — the reference
                   frame's "Lucia & Jason" duo-specific icon, generalised to
                   any group rather than hardcoded to a pair
         hanger  — clothing identified (fenix-police's `outfit` signal)
         vehicle — the vehicle used in the crime is identified */
    /* All six are cropped straight out of the actual HUD DEFINITIONS
       reference screenshots (not hand-traced) -- see
       tools/extract_tell_icons.py. .tell's plate colour is matched to the
       plate red baked into these PNGs (#8d161c) so the transparent edges
       blend with no fringing. */
    var TELL_IMG = {
        camera: 'icons/tells/tell_camera.png',
        weapon: 'icons/tells/tell_weapon.png',
        person: 'icons/tells/tell_person.png',
        people: 'icons/tells/tell_people.png',
        vehicle: 'icons/tells/tell_vehicle.png',
        hanger: 'icons/tells/tell_hanger.png'
    };

    /* Four star states, matching the reference frames exactly, all literal
       colours (client.lua's wantedState() decides which one applies, see
       the comment there for what each actually means):
         contact   solid white fill, static, they can see you right now.
         searching flashes between hollow and white fill, lost you, still
                   hunting.
         hollow    outline only, static, brighter than an unearned star but
                   never filled, reported, nobody's found you yet.
         red       solid red fill, static, shaken them, still in the zone.
       `filled` is how many stars the level has earned; `state` decides how
       those earned stars render. None of this is the pink/teal character
       accent, that's the waypoint/nav bar's own thing, not the stars'. */
    function renderStars(container, filled, total, state) {
        if (!container) return;
        container.innerHTML = '';
        for (var i = 0; i < total; i++) {
            var svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            svg.setAttribute('viewBox', '0 0 100 100');
            var cls = 'star';
            // Filled from the RIGHT: the reference lights the rightmost star
            // first and fills leftward, so a single star sits at the right end
            // of the row rather than the left.
            if (i >= total - filled && state) cls += ' ' + state;
            svg.setAttribute('class', cls);
            var p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
            p.setAttribute('d', STAR_PATH);
            svg.appendChild(p);
            container.appendChild(svg);
        }
    }

    function renderTells(container, tells) {
        if (!container) return;
        container.innerHTML = '';
        (tells || []).forEach(function (t) {
            var d = document.createElement('div');
            d.className = 'tell';
            d.title = t;
            if (TELL_IMG[t]) {
                var img = document.createElement('img');
                img.src = TELL_IMG[t];
                img.alt = t;
                d.appendChild(img);
            }
            container.appendChild(d);
        });
    }

    /* GTA VI's wanted box says one thing -- "The cops are searching for you
       / and they have your description" (it's in index.html) -- and only
       while that is true: you are wanted AND the police have at least one
       tell on you. The other three messages this box used to cycle through
       were never in GTA VI. The box's own star keeps the corner row's class,
       but style.css paints it GTA VI's dark red in every state. */

    // A notification, not a standing readout: it pops up when a NEW tell
    // lights or the stars go up, holds WANTED_HOLD_MS, and goes. A tell going
    // out, the stars dropping or the search state changing is not news.
    var WANTED_HOLD_MS = 7200;
    var wantedHideTimer = null;
    var wantedLastStars = 0;
    var wantedLastTells = {};

    function onWanted(d) {
        var stars = d.stars || 0;
        var maxStars = d.maxStars || 6;
        var state = d.state || null;
        renderStars($('stars'), stars, stars > 0 ? maxStars : 0, state);

        // Same class renderStars uses, so it matches the corner row exactly.
        var wstar = $('wanted-star');
        if (wstar) wstar.setAttribute('class', 'star' + (state ? ' ' + state : ''));

        // The tells track independently of the notification box -- the
        // reference shows them top-right under the stars as well as inside
        // the box.
        var tells = d.tells || [];
        show($('tells'), stars > 0 && tells.length > 0);
        renderTells($('tells'), tells);
        renderTells($('wanted-tells'), tells);

        var wanted = !!d.active && stars > 0;
        var fresh = wanted && stars > wantedLastStars;
        var seen = {};
        tells.forEach(function (t) {
            seen[t] = true;
            if (wanted && !wantedLastTells[t]) fresh = true;
        });
        wantedLastStars = wanted ? stars : 0;
        wantedLastTells = wanted ? seen : {};

        if (!wanted || tells.length === 0) {
            if (wantedHideTimer) { clearTimeout(wantedHideTimer); wantedHideTimer = null; }
            setVisible('wanted', $('wanted'), false);
            return;
        }
        if (!fresh) return; // nothing new -- leave it exactly as it was

        setVisible('wanted', $('wanted'), true);
        if (wantedHideTimer) clearTimeout(wantedHideTimer);
        wantedHideTimer = setTimeout(function () {
            wantedHideTimer = null;
            // Same guard as honor/reputation's hide timers: the editor forces
            // this panel visible with sample content, and a timer left over
            // from before it opened must not yank it back out from under it.
            if (editorOpen) return;
            setVisible('wanted', $('wanted'), false);
        }, WANTED_HOLD_MS);
    }

    /* --- money / weapon -------------------------------------------------- */

    /* 28163 -> "$28,163". Grouped with commas; the reference shows thousands
       separated rather than a bare run of digits. */
    function money(n) {
        n = Math.floor(Math.abs(Number(n) || 0));
        return '$' + String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    // The reference ring art is a 33-frame white mask sequence, frame 00
    // (empty) through frame 32 (full) -- see #cash-ring-fill/#buckme-ring-fill
    // in style.css.
    var MONEY_RING_FRAMES = 32;

    function setMoneyRing(id, pct) {
        var ring = $(id);
        if (!ring) return;
        var frame = ('0' + Math.round(pct * MONEY_RING_FRAMES)).slice(-2);
        var url = 'url("icons/buckme_ring/radial_ring_' + frame + '.png")';
        ring.style.webkitMaskImage = url;
        ring.style.maskImage = url;
    }

    // Centre-screen change indicator, same EVENT/STATE split as honor/
    // reputation above: this is "money just moved", the corner rows are the
    // STATE. `null` on the first read of each currency so a fresh page load
    // or a resource restart does not treat "no history yet" as a $12,163
    // windfall.
    var moneyPopTimer = null;
    var lastCashSeen = null;
    var lastBankSeen = null;

    // Same "quiet until something happens" treatment as the health row (see
    // healthRecentlyChanged above): the wallet/bank rows used to sit on
    // screen permanently, then got hidden permanently in favour of the
    // centre popup alone -- this is the middle ground the popup was missing,
    // a brief "here's the new total" next to the icon it belongs to, timed
    // to roughly outlast the popup's own 2.2s fade so the two read as one
    // event rather than the number outliving the announcement or vanishing
    // before it. Cash and bank flash independently -- a cash pickup has no
    // reason to also light up a bank balance that did not move.
    var MONEY_FLASH_MS = 3000;
    var cashFlashTimer = null;
    var bankFlashTimer = null;
    var cashRecentlyChanged = false;
    var bankRecentlyChanged = false;

    function onMoneyPop(delta, icon) {
        var el = $('money-pop');
        if (!el || !delta) return;
        var up = delta > 0;
        el.className = up ? 'up' : 'down';
        var sign = $('money-pop-sign');
        if (sign) sign.textContent = (up ? '+ ' : '− ') + money(delta);
        var img = $('money-pop-icon');
        if (img && icon) img.src = icon;
        show(el, true);
        if (moneyPopTimer) clearTimeout(moneyPopTimer);
        moneyPopTimer = setTimeout(function () { show(el, false); }, 2200);
    }

    // A deposit or withdrawal takes the same amount out of one and puts it in
    // the other -- in one push, or split across two when the framework sets
    // cash and bank separately. Either way it is one event, "$23 → BuckMe",
    // as the reference shows an ATM deposit, rather than a "− $23" that a
    // "+ $23" overwrites a moment later.
    var TRANSFER_PAIR_MS = 1500;
    var lastMoneyMove = null;   // { cur: 'cash'|'bank', delta, at }
    var MONEY_ICON = { cash: 'icons/cash.png', bank: 'icons/buckme.png' };

    function onMoneyTransfer(amount, icon) {
        var el = $('money-pop');
        if (!el) return;
        el.className = 'transfer';
        var sign = $('money-pop-sign');
        if (sign) sign.textContent = money(amount) + ' →';
        var img = $('money-pop-icon');
        if (img) img.src = icon;
        show(el, true);
        if (moneyPopTimer) clearTimeout(moneyPopTimer);
        moneyPopTimer = setTimeout(function () { show(el, false); }, 2200);
    }

    function onMoneyMove(cur, delta) {
        var now = Date.now();
        var prev = lastMoneyMove;
        if (prev && prev.cur !== cur && prev.delta === -delta && now - prev.at < TRANSFER_PAIR_MS) {
            lastMoneyMove = null;
            onMoneyTransfer(Math.abs(delta), MONEY_ICON[delta > 0 ? cur : prev.cur]);
            return;
        }
        lastMoneyMove = { cur: cur, delta: delta, at: now };
        onMoneyPop(delta, MONEY_ICON[cur]);
    }

    // Last payload the money rows' visibility was computed from -- ui('cash')
    // only pushes on a dedup-key change (see the `key` diff in client.lua),
    // unlike ui('status') which pushes every tick, so the flash timers below
    // can't rely on a future push to re-run the visibility check once
    // *RecentlyChanged flips back to false. They call this directly instead.
    var lastMoneyExpanded = false;
    var lastMoneyShowOk = true;

    function updateMoneyRowVisibility() {
        show($('cash-row'), (lastMoneyExpanded || cashRecentlyChanged) && lastMoneyShowOk && lastCashSeen != null);
        show($('bank-row'), (lastMoneyExpanded || bankRecentlyChanged) && lastMoneyShowOk && lastBankSeen != null);
    }

    function onCash(d) {
        var c = $('cash'), b = $('bank');
        if (d.cash != null && c) c.textContent = money(d.cash);
        if (d.bank != null && b) b.textContent = money(d.bank);

        if (d.cash != null) {
            if (lastCashSeen !== null && d.cash !== lastCashSeen) {
                onMoneyMove('cash', d.cash - lastCashSeen);
                cashRecentlyChanged = true;
                if (cashFlashTimer) clearTimeout(cashFlashTimer);
                cashFlashTimer = setTimeout(function () {
                    cashFlashTimer = null;
                    cashRecentlyChanged = false;
                    updateMoneyRowVisibility();
                }, MONEY_FLASH_MS);
            }
            lastCashSeen = d.cash;
        }
        if (d.bank != null) {
            if (lastBankSeen !== null && d.bank !== lastBankSeen) {
                onMoneyMove('bank', d.bank - lastBankSeen);
                bankRecentlyChanged = true;
                if (bankFlashTimer) clearTimeout(bankFlashTimer);
                bankFlashTimer = setTimeout(function () {
                    bankFlashTimer = null;
                    bankRecentlyChanged = false;
                    updateMoneyRowVisibility();
                }, MONEY_FLASH_MS);
            }
            lastBankSeen = d.bank;
        }

        // Otherwise the rows only surface while there is a reason to read a
        // standing balance -- the item wheel/full inventory (d.wheel, same
        // flag the health row uses) or a character switch. See wheelHeld()
        // in client.lua.
        lastMoneyExpanded = !!d.wheel;
        lastMoneyShowOk = d.show !== false;
        updateMoneyRowVisibility();

        // Neither ring is decoration -- both fill as the CASH wallet
        // approaches d.cashCap (Config.CashCap), the same "deposit before
        // you're capped" nudge the reference art shows on both icons.
        var pct = d.cashCap ? Math.max(0, Math.min(1, (Number(d.cash) || 0) / d.cashCap)) : 0;
        setMoneyRing('cash-ring-fill', pct);
        setMoneyRing('buckme-ring-fill', pct);
    }

    /* What the duffle bag on the player's back is worth at a fence/pawn shop
       right now (see wasabi_backpack's server-side value sum). `value` absent
       means "not carrying one" -- the row hides rather than showing $0, same
       convention as cash/bank above. `value === 0` (carrying an empty or
       all-junk bag) still shows, so the number itself answers "worth robbing
       me for this?" at a glance. */
    function onDuffle(d) {
        var v = $('duffle');
        if (d.value != null && v) v.textContent = money(d.value);
        show($('duffle-row'), d.value != null);
    }

    /* rcore_casino's own chip balance, comma-grouped like money but with no $
       sign, chips aren't cash. Hidden at 0 same as vice_hud's client.lua only
       pushes a value once it's above 0 in the first place. */
    function onChips(d) {
        var v = $('chips');
        if (d.value != null && v) v.textContent = String(Math.floor(Math.abs(Number(d.value) || 0))).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        show($('chips-row'), d.value != null);
    }

    /* Equipped weapon: icon plus, for ranged weapons, clip/reserve counts.
       Melee shows the icon alone — the frames confirm no ammo row for a wrench. */
    function onWeapon(d) {
        var icon = $('weapon-icon');
        if (icon) {
            // An image that is not there (an inventory without that item's
            // art) is hidden rather than left as a broken-picture box.
            if (!icon.onerror) icon.onerror = function () { show(icon, false); };
            if (d.icon) { icon.src = d.icon; show(icon, true); }
            else show(icon, false);
        }
        var hasAmmo = d.clip != null && d.reserve != null;
        show($('ammo'), !!d.armed && hasAmmo);
        if (hasAmmo) {
            var c = $('ammo-clip'), r = $('ammo-reserve');
            if (c) c.textContent = d.clip;
            if (r) r.textContent = d.reserve;
        }
    }

    /* --- aim crosshair ---------------------------------------------------
       Three small, mostly-independent pieces:
         onCrosshair  — show/hide + which variant (vehicle ring vs foot ticks)
         onCrossFire  — a discrete "a shot just fired" ping; the widen/settle
                        motion itself is a CSS transition on --spread (see
                        style.css), not anything animated from here
         onKillMark   — a discrete "a kill just happened, here's how clean"
                        ping, coloured by client.lua's classifier */
    function onCrosshair(d) {
        var box = $('crosshair');
        if (!box) return;
        if (!d || !d.active) { show(box, false); return; }
        box.dataset.mode = d.mode === 'vehicle' ? 'vehicle' : 'foot';
        show(box, true);
    }

    // 2+-option interact reticle -- a separate element from #crosshair
    // (see #third-eye's own comment in index.html/style.css for why), so
    // this is a plain on/off, no mode switch needed.
    function onThirdEye(d) {
        show($('third-eye'), !!(d && d.active));
    }

    var crossFireTimer = null;
    function onCrossFire() {
        var tips = $('cross-tips');
        if (!tips) return;
        tips.style.setProperty('--spread', 'calc(0.35 * var(--w))');
        // Rapid fire keeps re-arming this rather than letting it settle
        // between shots, so sustained fire holds the wide reticle and only
        // eases back once the shooting actually stops.
        clearTimeout(crossFireTimer);
        crossFireTimer = setTimeout(function () {
            tips.style.setProperty('--spread', '0px');
        }, 220);
    }

    var KILL_CLASSES = ['kill-red', 'kill-yellow', 'kill-white'];
    var KILL_CLASS_FOR = { headshot: 'kill-red', sloppy: 'kill-yellow', clean: 'kill-white' };
    var killMarkTimer = null;
    function onKillMark(d) {
        var x = $('cross-kill');
        if (!x || !d || !d.quality) return;
        var cls = KILL_CLASS_FOR[d.quality] || 'kill-white';
        // A kill can land in the instant the crosshair itself is about to be
        // told it's inactive (the shot that killed is usually the last one
        // fired) -- force it visible for the flash rather than let a
        // same-tick "active: false" hide the thing that's supposed to flash.
        show($('crosshair'), true);
        x.classList.remove.apply(x.classList, KILL_CLASSES.concat('show'));
        void x.offsetWidth; // restart the transition even on back-to-back kills
        x.classList.add(cls, 'show');
        clearTimeout(killMarkTimer);
        killMarkTimer = setTimeout(function () { x.classList.remove('show'); }, 550);
    }

    /* --- race lap / checkpoint HUD -----------------------------------------
       Lua pushes only on discrete events (run start, each checkpoint hit,
       finish/abort) rather than streaming elapsedMs every frame -- see
       client.lua's exports.vice_hud:SetLapTimer. The visible ticking is
       entirely local: every push re-bases (lapTimerBasisMs, performance.now())
       and a requestAnimationFrame loop interpolates from there, so the
       number stays smooth without SendNUIMessage being called anywhere near
       that often. Self-correcting: the next real push re-bases again, so
       small drift between pushes never accumulates. */
    var raf = typeof requestAnimationFrame === 'function'
        ? requestAnimationFrame
        : function (cb) { return setTimeout(cb, 16); };
    var caf = typeof cancelAnimationFrame === 'function' ? cancelAnimationFrame : clearTimeout;

    var lapTimerRAF = null;
    var lapTimerBasisMs = 0;
    var lapTimerBasisPerf = 0;
    var lapTimerRunning = false;

    function formatLapTime(ms) {
        ms = Math.max(0, ms || 0);
        var totalSeconds = ms / 1000;
        var minutes = Math.floor(totalSeconds / 60);
        var seconds = totalSeconds - minutes * 60;
        var m = (minutes < 10 ? '0' : '') + minutes;
        var s = seconds.toFixed(2);
        if (seconds < 10) s = '0' + s;
        return m + ':' + s;
    }

    function lapTimerTick() {
        if (!lapTimerRunning) return;
        var el = $('lap-timer');
        if (el) el.textContent = formatLapTime(lapTimerBasisMs + (performance.now() - lapTimerBasisPerf));
        lapTimerRAF = raf(lapTimerTick);
    }

    /* How far through the race, 0..100, for the PROGRESS chip.
       `progress` (0..1) wins when the race resource sends one -- it knows the
       distance along the route, which is what the reference's figure climbs
       by. Without it the figure is worked out from checkpoints cleared across
       every lap, which moves in steps but is never wrong. */
    function lapProgressPct(d) {
        var p;
        if (d.progress != null) {
            p = +d.progress;
        } else {
            var laps = Math.max(1, +d.laps || 1);
            var per = +d.cpTotal || 0;
            if (!per) return 0;
            var lap = Math.max(1, +d.lap || 1);
            p = ((lap - 1) * per + (+d.cp || 0)) / (laps * per);
        }
        if (!(p > 0)) return 0;
        return Math.round(Math.min(1, p) * 100);
    }

    function onLapHud(d) {
        var box = $('lap-hud');
        if (!box) return;
        // Lifts the prompts and the honor toast clear of the corner this
        // block takes; see #stage.racing in style.css.
        if (stage) stage.classList.toggle('racing', !!(d && d.show));
        if (!d || !d.show) {
            show(box, false);
            lapTimerRunning = false;
            if (lapTimerRAF) caf(lapTimerRAF);
            return;
        }

        var laps = d.laps != null ? d.laps : 1;
        var cur = $('lap-cur'), tot = $('lap-total');
        if (cur) cur.textContent = d.lap != null ? d.lap : 1;
        if (tot) tot.textContent = laps;
        // The first row is LAP for a race that has laps and PROGRESS for a
        // point to point: the reference draws one or the other.
        show($('lap-badge'), +laps > 1);
        show($('lap-progress'), !(+laps > 1));

        var pct = $('lap-progress-pct');
        if (pct) pct.textContent = lapProgressPct(d);

        // The plate is POSITION in the field, as in the reference. A race
        // resource that sends none (a solo time trial has no field) gets the
        // checkpoint count there instead, which is what this plate used to be.
        var hasPos = d.position != null;
        var cpCur = $('lap-cp-cur'), cpTot = $('lap-cp-total');
        if (cpCur) cpCur.textContent = hasPos ? d.position : (d.cp != null ? d.cp : 0);
        if (cpTot) {
            cpTot.textContent = hasPos ? (d.racers != null ? d.racers : d.position)
                : (d.cpTotal != null ? d.cpTotal : 0);
        }

        if (d.elapsedMs != null) {
            lapTimerBasisMs = d.elapsedMs;
            lapTimerBasisPerf = performance.now();
        }
        if (d.running) {
            if (!lapTimerRunning) {
                lapTimerRunning = true;
                lapTimerTick();
            }
        } else {
            lapTimerRunning = false;
            if (lapTimerRAF) caf(lapTimerRAF);
            var t = $('lap-timer');
            if (t) t.textContent = formatLapTime(lapTimerBasisMs);
        }

        show(box, true);
    }

    /* --- race cards and countdown -----------------------------------------
       The top-centre cards (the title before the start, the placing at the
       finish) and the 3-2-1-go. Everything here CUTS in and out, as it does
       in the reference: the only timing is how long each thing stays up. */

    /* 1ST, 2ND, 3RD, 4TH ... 11TH, 12TH, 13TH ... 21ST. */
    function ordinal(n) {
        n = Math.max(1, Math.round(+n) || 1);
        var tens = n % 100;
        if (tens >= 11 && tens <= 13) return n + 'TH';
        return n + (['TH', 'ST', 'ND', 'RD'][n % 10] || 'TH');
    }

    /* A finishing time, to the millisecond: 01:28.893. The running clock in
       the race block shows hundredths; the result card shows thousandths. */
    function formatResultTime(ms) {
        ms = Math.max(0, Math.round(+ms) || 0);
        var minutes = Math.floor(ms / 60000);
        var seconds = Math.floor((ms % 60000) / 1000);
        var millis = ms % 1000;
        return (minutes < 10 ? '0' : '') + minutes + ':'
            + (seconds < 10 ? '0' : '') + seconds + '.'
            + ('00' + millis).slice(-3);
    }

    var raceCardTimer = null;

    /* kind 'title':  { series, name, type }     chip / big line / chip
       kind 'result': { position, timeMs }       big line / chip
       `holdMs` is how long it stays; 0 leaves it up until hidden. */
    function onRaceCard(d) {
        var card = $('race-card');
        if (!card) return;
        if (raceCardTimer) { clearTimeout(raceCardTimer); raceCardTimer = null; }
        if (!d || d.show === false) { show(card, false); return; }

        var result = d.kind === 'result';
        // 'banner' is a line across the top with a time under it: FINAL LAP
        // over the lap just finished.
        var banner = d.kind === 'banner';
        var top = '', main = '', sub = '';
        if (result) {
            main = d.label != null ? String(d.label) : ordinal(d.position);
            if (d.timeMs != null) sub = formatResultTime(d.timeMs);
        } else if (banner) {
            main = d.text != null ? String(d.text) : 'Final lap';
            if (d.timeMs != null) sub = formatResultTime(d.timeMs);
        } else {
            top = d.series || '';
            main = d.name || '';
            sub = d.type || '';
        }
        var set = function (id, text) { var el = $(id); if (el) el.textContent = text; };
        set('race-card-top', top);
        set('race-card-main', main);
        set('race-card-sub', sub);
        card.classList.toggle('result', result);
        card.classList.toggle('banner', banner);
        show(card, true);

        // 1900 ms and 2000 ms are what the reference holds them for.
        var hold = typeof d.holdMs === 'number' ? d.holdMs : (result ? 2000 : banner ? 3000 : 1900);
        if (hold > 0) {
            raceCardTimer = setTimeout(function () {
                raceCardTimer = null;
                show($('race-card'), false);
            }, hold);
        }
    }

    var raceCountTimers = [];

    function clearRaceCount() {
        raceCountTimers.forEach(clearTimeout);
        raceCountTimers = [];
    }

    function showRaceCount(text, holdMs) {
        var el = $('race-count');
        if (!el) return;
        el.textContent = text;
        show(el, true);
        raceCountTimers.push(setTimeout(function () { show($('race-count'), false); }, holdMs));
    }

    /* Either one beat -- { value: 3 } or { value: 'go' } -- for a race
       resource that keeps its own clock, or the whole run -- { from: 3 } --
       timed here the way the reference times it: a digit every second, each
       up for 300 ms, then "go" for 1100 ms. */
    function onRaceCountdown(d) {
        clearRaceCount();
        if (!d || d.show === false) { show($('race-count'), false); return; }

        var digitMs = typeof d.digitMs === 'number' ? d.digitMs : 300;
        var goMs = typeof d.goMs === 'number' ? d.goMs : 1100;
        var isGo = function (v) { return String(v).toLowerCase() === 'go' || v === 0; };

        if (d.value != null) {
            showRaceCount(isGo(d.value) ? 'go' : String(d.value), isGo(d.value) ? goMs : digitMs);
            return;
        }

        var from = Math.max(1, Math.round(+d.from) || 3);
        var stepMs = typeof d.stepMs === 'number' ? d.stepMs : 1000;
        var beat = function (i) {
            var n = from - i;
            raceCountTimers.push(setTimeout(function () {
                showRaceCount(n > 0 ? String(n) : 'go', n > 0 ? digitMs : goMs);
            }, i * stepMs));
        };
        for (var i = 0; i <= from; i++) beat(i);
    }

    /* --- interact menu (Phase 1 of the ox_target-replacement project) -----
       A plain data-driven option list -- no targeting geometry, no raycast
       highlight, see the comment on #interact in index.html for why that
       engine is a separate, later project. Options: array of
       { label, badges: ['health'|'stamina'|'focus', ...], selected } (selected
       marks the ONE row that gets the X-in-circle marker; every other row
       gets a hollow dot). Keyboard-navigable: arrows move, Enter confirms,
       Escape cancels -- posted back to Lua as interactSelect / interactClose. */
    var INTERACT_MARKER_DOT = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/></svg>';
    var INTERACT_MARKER_X = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"/>' +
        '<path d="M8.5 8.5l7 7M15.5 8.5l-7 7"/></svg>';
    var INTERACT_BADGE_SVG = {
        // Same heart silhouette as the health status row's badge_heart.png,
        // redrawn as a stroke path so it matches the other chips here (flat
        // raster art next to vector strokes would look out of place at this
        // size).
        health: '<svg viewBox="0 0 24 24"><path d="M12 20S4 14.5 4 9.2C4 6.3 6.2 4 9 4c1.6 0 3 .9 3 .9S13.4 4 15 4c2.8 0 5 2.3 5 5.2 0 5.3-8 10.8-8 10.8z"/></svg>',
        stamina: '<svg viewBox="0 0 24 24"><path d="M13 2 4.5 14h6L10 22l9.5-13h-6z"/></svg>',
        focus: '<svg viewBox="0 0 24 24"><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/>' +
            '<circle cx="12" cy="12" r="3"/></svg>'
    };

    var interactOptions = [];
    var interactSel = 0;

    function renderInteract() {
        var list = $('interact-list');
        if (!list) return;
        list.innerHTML = '';
        interactOptions.forEach(function (opt, i) {
            var row = document.createElement('div');
            row.className = 'interact-row' + (i === interactSel ? ' selected' : '');
            row.dataset.index = i;

            var marker = document.createElement('span');
            marker.className = 'interact-marker ' + (i === interactSel ? 'interact-marker-x' : 'interact-marker-dot');
            marker.innerHTML = i === interactSel ? INTERACT_MARKER_X : INTERACT_MARKER_DOT;
            row.appendChild(marker);

            var label = document.createElement('span');
            label.className = 'interact-label item-select-outline';
            label.textContent = opt.label || '';
            row.appendChild(label);

            if (opt.badges && opt.badges.length) {
                var badges = document.createElement('span');
                badges.className = 'interact-badges';
                opt.badges.forEach(function (b) {
                    var chip = document.createElement('span');
                    chip.className = 'interact-badge ' + b;
                    chip.innerHTML = INTERACT_BADGE_SVG[b] || '';
                    badges.appendChild(chip);
                });
                row.appendChild(badges);
            }

            list.appendChild(row);
        });
    }

    function onInteract(d) {
        var box = $('interact');
        if (!box) return;
        if (!d || !d.show) { show(box, false); return; }

        interactOptions = d.options || [];
        // `selected` on the data wins if given; otherwise the row already
        // flagged selected: true in the option list itself, otherwise 0.
        interactSel = d.selected != null ? d.selected
            : Math.max(0, interactOptions.findIndex(function (o) { return o.selected; }));
        if (interactSel < 0) interactSel = 0;

        renderInteract();
        show(box, true);
    }

    function moveInteractSel(delta) {
        if (!interactOptions.length) return;
        interactSel = (interactSel + delta + interactOptions.length) % interactOptions.length;
        renderInteract();
        // Lua also drives this menu directly for controller input (see
        // client.lua) and keeps its own selected-index cache so a
        // controller Accept press knows what to confirm. Without this, a
        // keyboard nudge here would leave that cache pointing at whatever
        // was highlighted before — telling it every move is what keeps the
        // two input paths agreeing regardless of which one the player
        // actually used last.
        post('interactMove', { index: interactSel });
    }

    function confirmInteract() {
        if (!interactOptions.length) return;
        post('interactSelect', { index: interactSel });
    }

    function closeInteract() {
        show($('interact'), false);
        post('interactClose', {});
    }

    /* --- world action prompt ------------------------------------------------
       A short list of button-glyph + label options, e.g. Slim Jim / Smash
       Window. Not the scrollable #interact list — see the comment on
       #world-actions in index.html for why this is its own component.

       Each option arrives as { label, glyph, device } -- glyph is the LIVE
       resolved button (client_glyphs.lua), the same way an action prompt gets
       its own, and setGlyph draws it the same way too. This used to take a
       hand-picked `button: 'triangle'|'circle'` string with nothing
       connecting it to what was actually bound, which is exactly how it went
       stale: the shown icon and the working button drifted apart (see the
       fix note in vice_hud/client_overlays.lua and
       qbx_vehiclekeys/client/slimjim.lua). Deriving the icon FROM the
       resolved glyph is what makes that drift impossible now. */

    function onWorldActions(d) {
        var box = $('world-actions');
        if (!box) return;
        lastWorldActions = d || null;
        if (!d || !d.show) { show(box, false); return; }

        box.innerHTML = '';
        (d.options || []).forEach(function (opt) {
            var row = document.createElement('div');
            row.className = 'wa-row';

            var btn = setGlyph(document.createElement('span'), opt.glyph, opt.device, 'wa-btn glyph');
            row.appendChild(btn);

            // Between the button and the name: three dots on a dark disc for
            // an option that opens a list, or a coloured dot.
            if (opt.more) {
                var more = document.createElement('span');
                more.className = 'wa-more';
                more.innerHTML = '<svg viewBox="0 0 36 36" aria-hidden="true">'
                    + '<circle class="wa-more-disc" cx="18" cy="18" r="16.4"/>'
                    + '<circle cx="18" cy="11" r="2"/><circle cx="18" cy="18" r="2"/><circle cx="18" cy="25" r="2"/></svg>';
                row.appendChild(more);
            } else if (opt.dot) {
                var dot = document.createElement('span');
                dot.className = 'wa-dot';
                if (typeof opt.dot === 'string' && /^#[0-9a-f]{3,8}$/i.test(opt.dot)) dot.style.background = opt.dot;
                row.appendChild(dot);
            }

            var label = document.createElement('span');
            label.className = 'wa-label';
            label.textContent = opt.label || '';
            row.appendChild(label);

            box.appendChild(row);
        });
        box.classList.toggle('wa-centred', !!d.centred);
        show(box, true);
    }

    // World-anchoring: pushed every frame by client_overlays.lua's own
    // world-anchoring thread while a coords-bearing ShowWorldActions is
    // active (see that thread's comment) -- a SEPARATE, lightweight message
    // from onWorldActions above so a caller that never passes coords
    // (qbx_vehiclekeys today) never triggers this at all, and so tracking
    // the projection every tick doesn't also rebuild the whole row list
    // every tick. d.show === false means GetScreenCoordFromWorldCoord
    // reported the point is behind the camera, not that the prompt itself
    // should close -- that's still onWorldActions/HideWorldActions's job.
    function onWorldActionsPos(d) {
        var box = $('world-actions');
        if (!box) return;
        if (!d || d.show === false) {
            box.classList.add('wa-offscreen');
            return;
        }
        box.classList.remove('wa-offscreen');
        box.classList.toggle('wa-compact', !!d.compact);
        box.style.left = (d.x * 100) + 'cqw';
        box.style.top = (d.y * 100) + 'cqh';
    }

    /* --- race marker -----------------------------------------------------
       The next checkpoint's icon over its pillar (client_overlays.lua's race
       marker section draws the pillar and works out where its top lands on
       screen). d: { show, kind: 'checkpoint'|'finish', x, y (0..1 of the
       screen), text: '453 ft' }. show:false with no position is the marker
       going away or the point being behind the camera; either way nothing is
       drawn until a position comes back. */
    function onRaceMarker(d) {
        var box = $('race-marker');
        if (!box) return;
        if (d && d.kind) box.classList.toggle('finish', d.kind === 'finish');
        if (!d || !d.show || d.x == null || d.y == null) { show(box, false); return; }
        box.style.left = (d.x * 100) + 'cqw';
        box.style.top = (d.y * 100) + 'cqh';
        var dist = $('race-marker-dist');
        if (dist && d.text != null && dist.textContent !== String(d.text)) dist.textContent = String(d.text);
        show(box, true);
    }

    /* --- lockpick check -------------------------------------------------
       Analog direction-fill ring. Lua owns the input reading and the
       direction/completion decision entirely (see exports.vice_hud:
       StartLockpickCheck in client_overlays.lua) — this only ever draws
       whatever it's told: the glyph once per check, the fill arc (which
       side it grows from, and how far) on every progress push, and a
       brief success flash or alarm state at the end.

       REWORKED 2026-09-12 per the user-approved lockpick_preview.html
       mockup: no more target zone, no more release-based win/lose. See
       that file's own JS for the exact arc math ported below (arcPoint/
       arcPath), and client_overlays.lua's lockpick section for the
       dir/pct values these are fed. */

    // Same CX/CY/R as index.html's baked-in #lp-capacity path (kept in sync
    // by hand -- there are only the two numbers, R and the fixed 0-100 t
    // range, and index.html's own comment points back here). t=0..100 walks
    // the BOTTOM half of the circle only, left point -> bottom -> right
    // point, exactly like the mockup's own comment describes: theta runs
    // 180deg (left) down to 0deg (right) through 90deg (bottom, since SVG y
    // increases downward, sin(theta) there is positive = below centre).
    var LP_CX = 50, LP_CY = 50, LP_R = 29;
    function lpArcPoint(t) {
        var theta = (180 - 1.8 * t) * Math.PI / 180;
        return { x: LP_CX + LP_R * Math.cos(theta), y: LP_CY + LP_R * Math.sin(theta) };
    }
    function lpArcPath(t0, t1) {
        // Sampled polyline instead of a single SVG arc command -- ported
        // verbatim from the mockup: an "A" command's large-arc/sweep flags
        // depend on getting their direction semantics right, and walking
        // arcPoint(t) in small steps and connecting the dots can't
        // misinterpret direction the way that did.
        var steps = Math.max(2, Math.ceil(Math.abs(t1 - t0) / 2));
        var d = '';
        for (var i = 0; i <= steps; i++) {
            var t = t0 + (t1 - t0) * (i / steps);
            var p = lpArcPoint(t);
            d += (i === 0 ? 'M ' : 'L ') + p.x.toFixed(3) + ' ' + p.y.toFixed(3) + ' ';
        }
        return d;
    }

    var lockpickResultTimer = null;

    function setLockpickGlyph(text) {
        var box = $('lp-glyph-text');
        if (!box) return;
        text = text == null ? '' : String(text);
        // Same "mouse button drawn as the button itself" swap the world
        // action rows and action prompts already do (see MOUSE_GLYPHS
        // above) -- resolveKey/waResolveKey hand down 'LMB'/'RMB' as
        // sentinels precisely so this page can make that swap, rather than
        // ever lettering "LMB" inside the disc.
        var mouse = MOUSE_GLYPHS[text];
        box.innerHTML = '';
        if (mouse) {
            var img = document.createElement('img');
            img.src = mouse;
            img.alt = text;
            img.width = 22;
            img.height = 22;
            box.appendChild(img);
        } else {
            box.textContent = text;
        }
    }

    function onLockpick(d) {
        var box = $('lockpick');
        if (!box) return;
        if (!d || !d.show) { show(box, false); return; }

        box.classList.remove('lp-win', 'lp-alarm', 'lp-clone', 'lp-miss');
        var fill = $('lp-fill');
        if (fill) fill.setAttribute('d', '');
        var glyphBox = $('lp-glyph');
        if (glyphBox) glyphBox.style.setProperty('--lp-dx', 0);
        setLockpickGlyph(d.glyph || 'R');

        show(box, true);
    }

    function onLockpickProgress(d) {
        var fill = $('lp-fill');
        var glyphBox = $('lp-glyph');
        if (!d) return;

        var pct = Math.max(0, Math.min(100, d.pct != null ? d.pct : 0));
        var dir = d.dir != null && d.dir < 0 ? -1 : 1;

        if (fill) {
            if (pct <= 0) {
                fill.setAttribute('d', '');
            } else {
                // Mirrors depending on which way it's currently filling --
                // anchored at the RIGHT growing left for the real
                // (right-to-left) pick, anchored at the LEFT growing right
                // for the decoy (left-to-right) direction. Both look like
                // identical "progress" so there's no visual tell between
                // them, same as the mockup.
                fill.setAttribute('d', dir < 0 ? lpArcPath(100 - pct, 100) : lpArcPath(0, pct));
            }
        }
        // Moves the centre glyph itself toward the drag direction -- reads
        // as the actual stick/mouse nub being pushed, not just an abstract
        // progress number filling a bar. Simplified from the mockup's own
        // 2D nub (which also wobbled vertically with raw mouse dy): Lua's
        // dir/pct here are horizontal-only by design (see
        // client_overlays.lua's lockpickTick), so --lp-dx just carries the
        // signed fraction directly; style.css's own comment has the travel
        // distance this multiplies against.
        if (glyphBox) glyphBox.style.setProperty('--lp-dx', dir * (pct / 100));
    }

    function onLockpickResult(d) {
        var box = $('lockpick');
        if (!box) return;
        if (d && d.success) box.classList.add('lp-win');
        clearTimeout(lockpickResultTimer);
        lockpickResultTimer = setTimeout(function () { show(box, false); }, 450);
    }

    // Fired instead of onLockpickResult when the check was completed the
    // WRONG way (left-to-right) -- see client_overlays.lua's own comment on
    // why that's a distinct event/message rather than success:false. Flashes
    // the alarm state (see #lockpick.lp-alarm in style.css) then closes,
    // same timing as a normal result.
    function onLockpickAlarm() {
        var box = $('lockpick');
        if (!box) return;
        box.classList.add('lp-alarm');
        clearTimeout(lockpickResultTimer);
        lockpickResultTimer = setTimeout(function () { show(box, false); }, 450);
    }

    /* --- key clone check -------------------------------------------------
       The same ring in its lp-clone mode, for client_overlays.lua's key
       clone check (the single-player HUD's CLONE KEY): the pink window, the
       white dot sweeping the bottom half, a third of the band filled for
       each hit, green and "Key cloned" when it's done, the lockpick's own
       alarm when it isn't. Lua decides everything; this draws it. */
    var keyCloneTimer = null;
    var keyCloneMissTimer = null;

    function onKeyClone(d) {
        var box = $('lockpick');
        if (!box) return;
        clearTimeout(lockpickResultTimer);
        clearTimeout(keyCloneTimer);
        box.classList.remove('lp-win', 'lp-alarm', 'lp-miss');
        if (!d || !d.show) { box.classList.remove('lp-clone'); show(box, false); return; }

        box.classList.add('lp-clone');
        ['lp-fill', 'lp-window'].forEach(function (id) { var el = $(id); if (el) el.setAttribute('d', ''); });
        var glyphBox = $('lp-glyph');
        if (glyphBox) glyphBox.style.setProperty('--lp-dx', 0);
        // A pad's face button is drawn as its own mark (Xbox X, PlayStation
        // square) in dark ink on the white disc; anything else is the key's text.
        var face = d.device === 'pad' && G_FACE[padStyle === 'ps' ? 'ps' : 'xbox'][d.glyph];
        if (face) {
            var text = $('lp-glyph-text');
            if (text) text.innerHTML = '<svg class="lp-pad-ink" viewBox="0 0 36 36" width="22" height="22" aria-hidden="true">' + face + '</svg>';
        } else {
            setLockpickGlyph(d.glyph || 'E');
        }
        show(box, true);
    }

    function onKeyCloneProgress(d) {
        if (!d) return;
        var w = d.window || 24 / 1.8;
        var t = Math.max(w / 2, Math.min(100 - w / 2, d.target != null ? d.target : 50));
        var win = $('lp-window');
        if (win) win.setAttribute('d', lpArcPath(t - w / 2, t + w / 2));
        var dot = $('lp-dot');
        if (dot) {
            var p = lpArcPoint(Math.max(0, Math.min(100, d.pos || 0)));
            dot.setAttribute('cx', p.x.toFixed(3));
            dot.setAttribute('cy', p.y.toFixed(3));
        }
        var hits = Math.max(0, Math.min(3, d.hits || 0));
        var fill = $('lp-fill');
        if (fill) fill.setAttribute('d', hits > 0 ? lpArcPath(0, hits * 100 / 3) : '');
    }

    // A miss: the track goes red for a quarter of a second.
    function onKeyCloneMiss() {
        var box = $('lockpick');
        if (!box) return;
        box.classList.add('lp-miss');
        clearTimeout(keyCloneMissTimer);
        keyCloneMissTimer = setTimeout(function () { box.classList.remove('lp-miss'); }, 250);
    }

    function onKeyCloneResult(d) {
        var box = $('lockpick');
        if (!box) return;
        var won = !!(d && d.success);
        if (won) {
            box.classList.add('lp-win');
            var fill = $('lp-fill');
            if (fill) fill.setAttribute('d', lpArcPath(0, 100));
        } else {
            box.classList.add('lp-alarm');
        }
        clearTimeout(keyCloneTimer);
        keyCloneTimer = setTimeout(function () {
            box.classList.remove('lp-clone', 'lp-win', 'lp-alarm', 'lp-miss');
            show(box, false);
        }, won ? 700 : 900);
    }

    /* --- minimap slot geometry ------------------------------------------- */

    var mapFrameOn = false;
    var mapCrossOn = false;
    /* Is the ENGINE drawing the radar right now? The frame, the corner badge
       and the nav compass are all NUI drawn over where the map is, so they have
       to come down with it -- otherwise hiding the map on foot leaves an empty
       outlined box with a logo in it. client.lua's setRadar() is the single
       place that toggles the radar and it reports every transition here. */
    var mapVisible = true;
    /* What the badge would show if the map were up. onNav owns this (it steps
       aside for the compass); applyMapChrome owns whether it is ACTUALLY shown,
       so the two cannot fight over the same element. */
    var mapBadgeWanted = true;

    function applyMapChrome() {
        var fr = $('map-frame');
        if (fr) show(fr, mapVisible && mapFrameOn);
        show($('map-cross'), mapVisible && mapCrossOn);
        show($('map-badge'), mapVisible && mapBadgeWanted);
        // The compass rides the map's own top edge, so it goes too. Vanish, not
        // hide: it is a .slot and fades like the rest of that family.
        if (!mapVisible) slotVanish($('nav-compass'));
        // The zone bar / vehicle panel are anchored to the (snapshotted) map
        // rect -- see applyPanelRect above -- which is exactly right while the
        // map is visible and exactly wrong the moment it isn't: with no map
        // to sit next to, the panel just floats wherever that rect happened
        // to be (often not near any screen edge at all, see style.css's own
        // note on #slots.map-hidden). Docking them bottom-centre instead is
        // the same "give it a sane place to be" treatment #map-frame/
        // #map-badge already get by hiding outright -- these can't just hide,
        // they're still live notifications (zone changes, vehicle status).
        var slots = $('slots');
        if (slots) slots.classList.toggle('map-hidden', !mapVisible && footDockEnabled());
    }

    // Dock on foot (PROPS' `footdock` row) -- on by default (undefined AND
    // null both mean "never touched" / the shipped default, see that row's
    // own comment on why OFF is spelled 0 rather than null), off only once
    // the player has explicitly picked "stay at Position X/Y".
    function footDockEnabled() {
        var v = offsets.slots && offsets.slots.footdock;
        return v !== 0;
    }

    /* The last map rect we were told about, kept so the panel stack can be
       re-snapshotted on demand (Follow map, or Reset on the Map panels row)
       without waiting for the map to move again. */
    var lastMapRect = null;
    /* Has the panel stack been given its geometry yet this session? The map
       rect arrives repeatedly — the watchdog republishes it whenever it
       changes — and the whole point of the snapshot is that only the FIRST one
       counts. See applyPanelRect. */
    var panelSnapped = false;
    /* Which map the last full rect was: the drawn minimap's panel (true) or
       the engine radar's (false); null before the first. */
    var mapDrawn = null;

    /* Writes the panel stack's own geometry.

       Three sources, in priority order:
         1. an explicit value saved on the `slots` element (Panel left/width/
            bottom in the editor) — wins always, at any map size;
         2. Follow map turned on — track the map rect live, which is what this
            HUD did unconditionally before;
         3. otherwise the SNAPSHOT: the first map rect of the session, written
            once and then left alone.

       (3) is what fixes "resizing the map resizes the panels". An untouched
       layout still lands on the map's edge, because that is where the first
       rect puts it; every rect after that is ignored, so the map can be scaled
       freely and the panels stay where they are. */
    function applyPanelRect(rect) {
        if (!stage) return;
        var o = offsets.slots || {};
        var follow = o.pfollow === 1 || o.pfollow === true;

        function put(cssVar, own, mapVal, unit) {
            if (own != null) {
                stage.style.setProperty(cssVar, own + unit);
            } else if (follow || !panelSnapped) {
                if (mapVal != null) stage.style.setProperty(cssVar, mapVal + unit);
            }
            // else: leave whatever the snapshot already wrote.
        }

        var r = rect || lastMapRect || {};
        put('--panel-left',   o.pl, r.left,   'cqw');
        put('--panel-width',  o.pw, r.width,  'cqw');
        put('--panel-bottom', o.pb, r.bottom, 'cqh');

        // Only a rect that actually carried the numbers counts as the snapshot,
        // so a partial message cannot burn it.
        if (r.left != null && r.width != null && r.bottom != null) panelSnapped = true;
    }

    /* Throws the snapshot away and takes a fresh one from wherever the map is
       now. Used by Follow map and by Reset on the Map panels row -- both mean
       "put them back on the map", and without this they would re-attach to a
       snapshot taken before the map was resized. */
    function resnapPanelRect() {
        panelSnapped = false;
        applyPanelRect(lastMapRect);
    }

    function onMapRect(d) {
        if (!stage) return;
        // Values arrive as percentages of the viewport, matching the reference
        // measurements. They are applied to the stage as cq units so they stay
        // correct inside the centred 16:9 box on an ultrawide.
        //
        //   --map-bottom       distance from screen bottom to the map's TOP
        //                      edge; the slot stack anchors to this.
        //   --map-bottom-edge  distance from screen bottom to the map's BOTTOM
        //                      edge, which is what the frame needs.
        if (d.left != null) stage.style.setProperty('--map-left', d.left + 'cqw');
        if (d.width != null) stage.style.setProperty('--map-width', d.width + 'cqw');
        if (d.bottom != null) stage.style.setProperty('--map-bottom', d.bottom + 'cqh');
        if (d.height != null) stage.style.setProperty('--map-height', d.height + 'cqh');
        if (d.bottom != null && d.height != null) {
            // Rounded: the subtraction is binary float arithmetic, so an honest
            // 2.5 arrives as 2.4999999999999982 and lands in the stylesheet
            // that way.
            stage.style.setProperty(
                '--map-bottom-edge', +(d.bottom - d.height).toFixed(4) + 'cqh');
        }
        // Remember it, then let the panel stack decide for itself whether this
        // rect is any of its business. Before the split it simply WAS the panel
        // stack's geometry, which is the coupling this removes.
        lastMapRect = {
            left: d.left != null ? d.left : (lastMapRect && lastMapRect.left),
            width: d.width != null ? d.width : (lastMapRect && lastMapRect.width),
            bottom: d.bottom != null ? d.bottom : (lastMapRect && lastMapRect.bottom),
            height: d.height != null ? d.height : (lastMapRect && lastMapRect.height)
        };
        // The snapshot belongs to one map. The first rect of a session is the
        // radar's, from before the drawn minimap is ready, and on a screen wider
        // than 16:9 the drawn one's panel is far narrower: the zone bar stayed
        // at the radar's width over it. So when the map on screen changes from
        // one to the other, the snapshot is taken again.
        if (d.drawn != null) {
            var drawn = d.drawn === true;
            if (mapDrawn !== null && drawn !== mapDrawn) panelSnapped = false;
            mapDrawn = drawn;
        }
        applyPanelRect(lastMapRect);

        // The frame only helps when it sits exactly on the map; off by default.
        if (d.showFrame != null) mapFrameOn = d.showFrame === true;
        if (d.showCross != null) mapCrossOn = d.showCross === true;
        if (d.visible != null) mapVisible = d.visible === true;
        applyMapChrome();
    }

    /* --- component outlines (/hudrects) -----------------------------------
       Draws one labelled outline per engine minimap component, positioned in
       the same stage units the published map rect uses. Each carries its own
       measurements, because "the green box stops here" is only useful next to
       the number that put it there. */
    function onMapDebug(d) {
        var box = $('map-rects');
        if (!box) return;
        if (!d || d.show === false || !d.rects) { show(box, false); box.innerHTML = ''; return; }

        box.innerHTML = '';
        d.rects.forEach(function (item) {
            var r = item && item.r;
            if (!r) return;
            var el = document.createElement('div');
            el.className = 'mrect m-' + item.name;
            el.style.left = r.left + 'cqw';
            el.style.width = r.width + 'cqw';
            // `bottom` is the distance from the screen bottom to the rect's TOP
            // edge, matching --map-bottom, so the box hangs down from there.
            el.style.bottom = (r.bottom - r.height) + 'cqh';
            el.style.height = r.height + 'cqh';

            var tag = document.createElement('span');
            tag.innerHTML = '<b>' + item.name + '</b> ' +
                r.left.toFixed(2) + ',' + r.bottom.toFixed(2) +
                '  ' + r.width.toFixed(2) + '×' + r.height.toFixed(2);
            el.appendChild(tag);
            box.appendChild(el);
        });
        show(box, true);
    }

    /* --- skills ------------------------------------------------------------
       Two separate things, and the split matters. The TOAST is transient: it
       fires on a level-up and clears itself, and it is the only part most
       players will ever see. The PANEL is a screen you deliberately open to
       read where you stand, and it is pushed on every change so that opening it
       never shows a stale number. */
    var skillUpTimer = null;

    function onSkillUp(d) {
        var el = $('skillup');
        if (!el || !d || !d.label) return;
        var lab = $('skillup-label'), lvl = $('skillup-level'), blurb = $('skillup-blurb');
        if (lab) lab.textContent = d.label;
        if (lvl) lvl.textContent = d.level;
        if (blurb) blurb.textContent = d.blurb || '';

        // Restart the animation on a fresh level-up, so two in quick succession
        // read as two events rather than one that never finished.
        el.classList.remove('slot-in');
        show(el, true);
        void el.offsetWidth;
        el.classList.add('slot-in');

        if (skillUpTimer) clearTimeout(skillUpTimer);
        skillUpTimer = setTimeout(function () { show(el, false); }, 4200);
    }

    /* The gain card: "Focus +2%" bottom right, for a skill that goes up a
       little at a time in front of the player (client_skills.lua, award's
       `card`). The ring is the skill's standing, 0 at twelve o'clock and
       round clockwise: what there was before in the skill's colour, what this
       just added in white. A gain too small to see is drawn as a sliver, the
       way the reference's +2% is. */
    var statGainTimer = null;

    function onStatGain(d) {
        var el = $('statgain');
        if (!el || !d || !d.label) return;
        var clamp = function (v) { return Math.max(0, Math.min(1, Number(v) || 0)); };
        var from = clamp(d.from), to = Math.max(from, clamp(d.to));
        var gain = Math.max(to - from, 0.015);

        $('statgain-label').textContent = d.label;
        $('statgain-text').textContent = d.text || '';
        $('statgain-fill').setAttribute('stroke-dasharray', (from * 100).toFixed(2) + ' 100');
        $('statgain-gain').setAttribute('stroke-dasharray', (gain * 100).toFixed(2) + ' 100');
        $('statgain-gain').setAttribute('stroke-dashoffset', (-from * 100).toFixed(2));

        el.classList.remove('slot-in');
        show(el, true);
        void el.offsetWidth;
        el.classList.add('slot-in');

        if (statGainTimer) clearTimeout(statGainTimer);
        statGainTimer = setTimeout(function () { show(el, false); }, 4000);
    }

    function onSkills(d) {
        var box = $('skills');
        var list = $('skills-list');
        if (!box || !list) return;

        if (d && d.skills) {
            list.innerHTML = '';
            d.skills.forEach(function (s) {
                var li = document.createElement('li');
                li.className = 'sk' + (s.max ? ' maxed' : '');

                var head = document.createElement('div');
                head.className = 'sk-head';
                var name = document.createElement('span');
                name.className = 'sk-name';
                name.textContent = s.label;
                var lvl = document.createElement('span');
                lvl.className = 'sk-level';
                lvl.textContent = s.max ? 'MAX' : s.level;
                head.appendChild(name); head.appendChild(lvl);

                var track = document.createElement('div');
                track.className = 'sk-track';
                var fill = document.createElement('div');
                fill.className = 'sk-fill';
                fill.style.transform = 'scaleX(' + Math.max(0, Math.min(1, s.frac || 0)).toFixed(4) + ')';
                track.appendChild(fill);

                var sub = document.createElement('div');
                sub.className = 'sk-sub';
                // The unit is named because "1240 / 1900" tells you nothing on
                // its own — what you want to know is what to go and DO.
                sub.textContent = s.max
                    ? s.blurb
                    : s.into + ' / ' + s.need + '  ·  ' + s.unit;

                li.appendChild(head); li.appendChild(track); li.appendChild(sub);
                list.appendChild(li);
            });
        }

        // `show` is only obeyed when it is true, or every background refresh
        // would slam the panel shut while the player was reading it.
        if (d && d.show) show(box, true);
    }

    /* --- map panel arrival ------------------------------------------------
       The two map panels announce themselves the way a phone announces a
       message: a springy rise into place. Going away is left exactly as it was
       — an instant hide — so only the arrival is staged.

       `.hidden` is `display: none`, which cancels an animation outright, so the
       class cannot simply be toggled alongside it: the element has to be made
       displayable, laid out once, and only then given the animation class.

       `restart` is not a detail. onZone fires on a genuine zone CHANGE, so
       re-announcing is right there. onVehicle is re-pushed by the poll loop
       roughly four times a second for as long as the panel is up (it carries
       live fuel and lock state), so restarting on every call would leave the
       vehicle panel permanently mid-animation. Pass it deliberately. */
    /* Going away is a fade, so it has to be STAGED rather than toggled: the
       `hidden` class is `display: none`, which cancels an animation outright
       instead of playing it. The element fades first and is hidden after.
       Kept in step with the CSS by hand — a transition the JS thinks is shorter
       than it is would cut the fade off part-way. */
    /* 460 against a 420ms animation, on purpose. The fill-mode holds opacity at
       0 once the animation ends, so hiding LATE is invisible — hiding early
       cuts the fade off mid-way. The margin absorbs timer drift in the only
       direction that can be seen. */
    var SLOT_OUT_MS = 460;
    var slotOutTimers = {};

    /* Reduced motion means no fade, and therefore nothing to wait for: leaving
       the element up for 460 invisible milliseconds would be a delay the player
       never asked for in exchange for an animation they turned off. */
    var reduceMotion = window.matchMedia
        && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    function slotLeaving(el) {
        return !!(el && slotOutTimers[el.id]);
    }

    function slotCancelExit(el) {
        if (!el || !slotOutTimers[el.id]) return;
        clearTimeout(slotOutTimers[el.id]);
        slotOutTimers[el.id] = null;
        el.classList.remove('slot-out');
    }

    function slotAppear(el, restart) {
        if (!el) return;
        // Mid-fade counts as gone, whatever the caller asked for: catching a
        // panel on its way out and leaving it half-faded looks like a bug.
        var wasLeaving = slotLeaving(el);
        slotCancelExit(el);

        var wasHidden = el.classList.contains('hidden');
        if (!wasHidden && !wasLeaving && !restart) { show(el, true); return; }

        el.classList.remove('slot-in');
        show(el, true);
        // Force a layout read between removing the class and re-adding it.
        // Without it both changes collapse into one style recalculation and the
        // browser has no "before" to animate from, so nothing plays.
        void el.offsetWidth;
        el.classList.add('slot-in');
    }

    function slotVanish(el) {
        if (!el || el.classList.contains('hidden')) return;
        if (slotOutTimers[el.id]) return;      // already on its way out
        if (reduceMotion) { el.classList.remove('slot-in'); show(el, false); return; }
        el.classList.remove('slot-in');
        el.classList.add('slot-out');
        slotOutTimers[el.id] = setTimeout(function () {
            slotOutTimers[el.id] = null;
            el.classList.remove('slot-out');
            show(el, false);
        }, SLOT_OUT_MS);
    }

    /* --- zone bar -------------------------------------------------------- */

    var zoneTimer = null;
    var ZONE_MS = 4500;

    /* --- shrink-to-fit ----------------------------------------------------
       "South Vice-Dale County" is wider than the zone bar, and the bar's answer
       was to clip it to "South Vice-Dale C…". An ellipsis is the right last
       resort and the wrong first one: the panel is a fixed width tied to the
       minimap, the names are not, and a name you cannot read is not doing its
       job.

       So the text is measured against the box it is in and given a scale factor
       that makes it fit. --fit multiplies the font size rather than replacing
       it, so it composes with whatever size was tuned in the editor. The
       nowrap/ellipsis rules stay as the floor: past FIT_MIN the text would be
       too small to read, and clipping is better than illegible.  */
    var FIT_MIN = 0.5;
    var fitting = false;          // a pass is running right now
    var fitQueued = false;        // a pass is already scheduled for next frame

    function overflows(items) {
        var worst = 1;
        for (var i = 0; i < items.length; i++) {
            var el = items[i];
            if (!el || !el.textContent) continue;
            var avail = el.clientWidth;
            var need = el.scrollWidth;
            if (avail > 0 && need > avail) worst = Math.min(worst, avail / need);
        }
        return worst;
    }

    function fitBox(box, items) {
        if (!box) return;
        // Start from a clean slate. Leaving the previous factor on would make
        // each pass shrink relative to the last and walk the text to nothing.
        box.classList.remove('fit-wrap');
        box.style.removeProperty('--fit');

        var scale = 1;
        /* Iterated, not one division.
           scrollWidth is an integer and letter-spacing leaves a trailing gap
           the ratio does not know about, so a single pass lands a pixel or two
           over and the text is STILL clipped — which looks exactly like the
           fitting never having run. Two or three passes converge. */
        for (var pass = 0; pass < 3; pass++) {
            var worst = overflows(items);
            if (worst >= 1) break;
            // One factor for the whole box, so a long model is never set
            // smaller than the make sitting directly above it.
            scale = Math.max(FIT_MIN, scale * worst);
            box.style.setProperty('--fit', scale.toFixed(4));
            if (scale <= FIT_MIN) break;
        }

        /* Past the floor, wrap rather than cut.
           "Western Motorcycle Company" does not fit this panel at any size you
           could still read, and shrinking further just trades one unreadable
           result for another. Both panels size from their content (the vehicle
           panel has a min-height, not a height), so letting the words wrap
           costs a taller panel and keeps the whole name. */
        if (scale <= FIT_MIN && overflows(items) < 1) box.classList.add('fit-wrap');
    }

    function fitNow() {
        fitting = true;
        try {
            fitBox($('zone'), [$('zone-text')]);
            fitBox($('vehicle'), [$('veh-make'), $('veh-model')]);
            /* The nav bar needs this for the opposite reason the other two do.
               Its type is sized off viewport HEIGHT (--w, so it holds its
               proportion on an ultrawide) while its WIDTH comes from the map
               panel -- so on a narrow, tall aspect like 4:3 the bar is short
               on width and the longest instruction is the one that no longer
               fits. fitBox is measured, not guessed, so it covers whatever
               aspect a player actually runs.
               `fit-wrap` is deliberately not styled for this box: the bar has a
               fixed height and wrapping would overflow it, so past the floor it
               keeps ellipsing. */
            fitBox($('nav-turn'), [$('nav-turn-text'), $('nav-turn-dist')]);
        } finally {
            fitting = false;
        }
    }

    /* COALESCED, not dropped.
       An earlier version of this refused to run while another pass was in
       flight, which looks like the same thing and is not: onZone and onVehicle
       fire back to back, so the second call was thrown away and the vehicle
       names went unfitted while the zone bar fitted correctly. Queueing one
       pass per frame lets every caller ask and still costs one reflow. */
    function fitAll() {
        if (fitQueued) return;
        fitQueued = true;
        requestAnimationFrame(function () { fitQueued = false; fitNow(); });
    }

    // Re-fit whenever the box changes width (resolution change, the editor
    // resizing the panel, the minimap rect moving under it) and once the real
    // fonts have loaded — measuring against the fallback face gives an answer
    // that is wrong the moment Helvetica arrives.
    if (window.ResizeObserver) {
        // `fitting` keeps the observer out while a pass is mid-flight: fitBox
        // removes --fit to measure, which resizes the box and would otherwise
        // wake the observer that is watching it.
        var ro = new ResizeObserver(function () { if (!fitting) fitAll(); });
        ['zone', 'vehicle', 'slots', 'nav-turn'].forEach(function (id) {
            var el = $(id); if (el) ro.observe(el);
        });
    }
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitAll);

    function onZone(d) {
        var el = $('zone');
        var txt = $('zone-text');
        if (!el || !txt || !d.zone) return;
        txt.textContent = d.zone;
        el.classList.toggle('water', !!d.water);
        // restart: a new zone is a new announcement, even if the bar is still
        // up from the last one.
        slotAppear(el, true);
        // After it is displayable, so the box has a width to measure against.
        fitAll();
        if (zoneTimer) clearTimeout(zoneTimer);
        zoneTimer = setTimeout(function () { slotVanish(el); }, d.duration || ZONE_MS);
    }

    /* --- nav popup --------------------------------------------------------
       Mirrors whatever client.lua computed, but only actually shows it while
       `near` is true -- client.lua only sets that once the next turn (or the
       destination) is close, same "appear for the thing that matters, then
       get out of the way" rule the zone bar already follows. slotAppear/
       slotVanish (not a plain show) so it fades like every other slot panel
       instead of snapping on/off; both are safe to call every tick regardless
       of current state, they no-op if already in the state asked for. */
    function onNav(d) {
        var el = $('nav-popup');
        var compass = $('nav-compass');
        // The compass figure sits up in the map's corner, same neighbourhood
        // as the badge -- so the badge steps aside rather than fighting it
        // for the same real estate.
        if (!el) return;
        if (!d || !d.active || !d.near) {
            slotVanish(el);
            slotVanish(compass);
            mapBadgeWanted = true;
            applyMapChrome();
            return;
        }
        var turnText = $('nav-turn-text');
        if (turnText) turnText.textContent = d.instruction || '';
        var distText = $('nav-turn-dist');
        if (distText) distText.textContent = d.distance || '';
        var arrow = $('nav-turn-arrow');
        if (arrow) arrow.setAttribute('data-dir', d.dir || 'straight');
        var compassDist = $('nav-compass-dist');
        if (compassDist) compassDist.textContent = d.remaining || '';
        // New copy means a new measurement -- "Continue Straight" and "Arrive"
        // are very different widths in the same bar.
        fitAll();
        slotAppear(el);
        slotAppear(compass);
        mapBadgeWanted = false;
        applyMapChrome();
    }

    /* The nav-turn tile's character-gender default, teal for a male
       character, pink for a female one, same accent client.lua repaints the
       native waypoint cross/route with (see applyWaypointPalette there),
       pushed once it resolves. Written to its OWN --*-gender-default
       properties, not --nav-accent/--nav-accent-ink directly, so that
       applyOffsets() clearing an unset editor customisation on every layout
       load (onLayout -> applyOffsets, including at resource start) cannot
       wipe this out along with it, see the fallback chain on #nav-turn-arrow
       in style.css. An explicit /movehud "Turn tile colour" customisation
       still wins over this either way, via the same var() chain. */
    function onNavAccent(d) {
        if (!stage || !d) return;
        if (d.accent) stage.style.setProperty('--nav-accent-gender-default', d.accent);
        if (d.ink) stage.style.setProperty('--nav-accent-ink-gender-default', d.ink);
    }

    /* --- vehicle panel --------------------------------------------------- */

    /* The tone class, and the gauge reading if this pip has a ring.
       `pct` is null for a pip that is a state rather than a quantity. */
    function tone(el, t, pct) {
        if (!el) return;
        var gauge = el.classList.contains('gauge');
        el.className = 'pip ' + (t || 'unknown') + (gauge ? ' gauge' : '');
        if (pct == null) return;
        var v = Math.max(0, Math.min(100, pct));
        el.style.setProperty('--pct', v.toFixed(1));
        // A round linecap paints a dot even at zero, which would show a pip of
        // fuel in an empty tank.
        var fill = el.querySelector('.pip-fill');
        if (fill) {
            if (v < 0.5) fill.setAttribute('data-empty', '1');
            else fill.removeAttribute('data-empty');
        }
    }

    /* Engine wear, as a tone.
       GetVehicleEngineHealth is 1000 factory-fresh down to 0 seized, and keeps
       going NEGATIVE for an engine past that, which is why the last test is
       `< WORN` rather than a range: a destroyed engine reads -4000 and would
       fall out of any band with a floor on it. */
    var ENG_GOOD = 700, ENG_WORN = 300;

    function engineTone(health) {
        // Missing rather than damaged: an older client.lua, or /hudtest before
        // it learned to send this. Treat silence as "nothing to report".
        if (health == null) return 'good';
        if (health >= ENG_GOOD) return 'good';
        if (health >= ENG_WORN) return 'warn';
        return 'bad';
    }

    /* The three pips.
       Fuel and engine are the two that carry a real reading; the tracker is a
       state rather than a health.

       A SHUT-OFF CAR IS MONOCHROME on fuel and engine. Not an oversight and not
       a missing reading: green / amber / red on a parked car is the HUD
       shouting about a fuel level nothing is currently burning, and once you
       have seen a whole car park of them light up you stop reading any of them.
       Turning the key is what makes those two pips mean something, so turning
       the key is what gives them colour. */
    /* Engine health as a percentage for the ring. The native runs 1000 down to
       0 and then keeps going negative for an engine past seized, so the floor
       is a clamp rather than a range. */
    function enginePct(health) {
        if (health == null) return 100;
        return Math.max(0, Math.min(100, health / 10));
    }

    /* A pip EARNS its place on the panel by having something to report.
       'warn' and 'bad' are the two tones that mean "look at this"; 'good' and
       'unknown' are not worth a permanent icon, so those are hidden outright
       rather than shown in a colour that says nothing. A full tank and a
       healthy engine are the normal case, and two discs that are lit green
       for the entire time you are driving are two discs nobody reads by the
       second day. */
    function pipShows(t) { return t === 'warn' || t === 'bad'; }

    /* The tracker is the odd one out and cannot use pipShows or the engine
       gate: door lock status moved to qbx_vehiclekeys, so vice_hud has no
       opinion left on what should light this pip up. It is whatever the
       LAST call to exports.vice_hud:SetVehicleTracker said -- 'clear',
       'searching' or 'spotted' -- and stays hidden until something has
       actually called it at least once, engine on or off. */
    function trackerTone(state) {
        if (state === 'clear') return 'good';
        if (state === 'searching') return 'warn';
        if (state === 'spotted') return 'bad';
        return 'unknown';
    }

    /* Nitrous is the other odd one out, in the opposite direction: it is the
       only pip that is a CONTROL rather than a warning. `n` is whatever
       client.lua's Nitrous section last normalised -- { installed, level 0..1,
       active, ready } -- or nothing at all for a car with no kit.

       Its tone is deliberately off the good / warn / bad scale. Those three
       answer "is this a problem", and a nitrous tank is never a problem, only
       more or less available: usable, or locked out refilling. The second
       borrows 'unknown', the same grey a parked car's gauges use, for the
       same reason -- the reading is real and nothing can currently act on it.

       `active` (boosting right now) deliberately changes NOTHING here. The
       ring draining is the boost indicator, as it is in the reference; the
       disc and the mark do not light up, pulse or move. */
    function nitroInstalled(n) { return !!(n && n.installed); }

    function nitroTone(n) {
        if (!nitroInstalled(n)) return 'unknown';
        return n.ready === false ? 'unknown' : 'nitro';
    }

    function nitroPct(n) {
        var level = n && +n.level;
        // NaN from a missing or malformed level reads as an empty tank rather
        // than reaching the ring as a dash offset of NaN.
        return level > 0 ? level * 100 : 0;
    }

    /* The fast path. The vehicle push carries the same table four times a
       second; this arrives whenever the tank actually changes -- ten times a
       second mid-boost. It writes the new reading into the last vehicle
       payload and runs the panel again, so the ring moves between ticks and a
       row that had gone quiet and away comes straight back the moment the
       tank starts to move, rather than up to a quarter of a second later. */
    var lastVehicle = null;

    function onNitrous(d) {
        if (!lastVehicle || !lastVehicle.show) return;
        lastVehicle.nitrous = nitroInstalled(d)
            ? { installed: true, level: d.level, active: d.active, ready: d.ready }
            : null;
        onVehicle(lastVehicle);
    }

    /* The "Hold [key] to activate nitrous" tip. client.lua decides WHEN (a kit
       was just fitted, or something called ShowNitrousHint) and resolves the
       key; this draws it and takes it down again after `holdMs`. The cap is
       built the way renderPrompts builds one, so a mouse bind is a picture
       and a pad face button gets its colour. No glyph at all hides the cap
       and the line reads "Hold to activate nitrous". */
    var nitroHintTimer = null;

    function onNitrousHint(d) {
        var el = $('nitro-hint');
        if (!el) return;
        if (d && d.refresh && el.classList.contains('hidden')) return;
        if (nitroHintTimer && !(d && d.refresh)) { clearTimeout(nitroHintTimer); nitroHintTimer = null; }
        if (!d || d.show === false) { show(el, false); return; }

        lastNitrousHint = { glyph: d.glyph, device: d.device };
        var cap = $('nitro-hint-key');
        if (cap) setGlyph(cap, d.glyph, d.device);
        // A device swap while the tip is up: the same tip with a new button
        // on it, and the clock it is already running on.
        if (d.refresh) return;

        show(el, true);
        var hold = typeof d.holdMs === 'number' ? d.holdMs : 7000;
        if (hold > 0) {
            nitroHintTimer = setTimeout(function () {
                nitroHintTimer = null;
                show($('nitro-hint'), false);
            }, hold);
        }
    }

    /* ---- change-driven pips --------------------------------------------------
       The collapsed row is about CHANGE, not about state.

         a reading changes        its pip lights up: its colour, its ring
         PIP_LIT_MS later         it drops back to QUIET (dim, grey, no ring)
         PIP_DIM_MS after that    with nothing else changing, the row goes

       Why not "lit while there is a warning", which is what this used to do:
       the reference shows a pump with a part-drained green ring on the name
       plate and, a minute later, the same pump dim and ringless beside a
       nitrous ring that is being used. Read as state that is a contradiction
       -- is the tank low or not? Read as change it is not one: the plate is
       an announcement (everything lit), the nitrous is what is changing now
       (lit), and the fuel has not moved lately (dim). A dim pip never means
       "fine" and a lit one never means "bad"; lit means "this just moved".

       What counts as moving is per pip, because fuel creeps down all the time
       and an icon that relights for every tenth of a percent is an icon that
       never goes dim:
         fuel      5 points down or 2 up since it last lit, or a change of band
         engine    50 health either way, a change of band, or the key turning
         tracker   any change of state
         nitrous   any change at all: fitted, burning, locked out, level        */
    var PIP_LIT_MS = 4000;
    var PIP_DIM_MS = 6000;
    var FUEL_STEP_DOWN = 5, FUEL_STEP_UP = 2, ENGINE_STEP = 50, NITRO_STEP = 0.005;

    /* What each pip looked like when it last lit, and when that was. Kept per
       vehicle: a different car is all news, and so is the same car again. */
    var pipMemory = null;

    function pipSlots(d) {
        var key = (d.make || '') + '|' + (d.model || '');
        if (!pipMemory || pipMemory.key !== key) pipMemory = { key: key };
        return pipMemory;
    }

    /* Milliseconds since `name` last changed. The stored sample only moves
       when `differs` says so, which is what lets a slow drain add up to a
       step instead of being forgotten a tick at a time. */
    function pipAge(mem, name, sample, differs) {
        var now = Date.now();
        var prev = mem[name];
        if (!prev || differs(prev.sample, sample)) prev = mem[name] = { sample: sample, at: now };
        return now - prev.at;
    }

    function fuelMoved(a, b) {
        return a.band !== b.band || a.v - b.v >= FUEL_STEP_DOWN || b.v - a.v >= FUEL_STEP_UP;
    }
    function engineMoved(a, b) {
        return a.band !== b.band || Math.abs(a.v - b.v) >= ENGINE_STEP;
    }
    function trackerMoved(a, b) { return a !== b; }
    function nitroMoved(a, b) {
        return a.inst !== b.inst || a.act !== b.act || a.rdy !== b.rdy
            || Math.abs(a.lvl - b.lvl) >= NITRO_STEP;
    }

    function setPips(d, expanded) {
        var fuel = d.fuel == null ? 0 : d.fuel;
        var running = !!d.engineOn;
        var health = d.engineHealth == null ? 1000 : d.engineHealth;

        var fuelTone = !running ? 'unknown'
            : fuel <= 10 ? 'bad' : fuel <= 25 ? 'warn' : 'good';
        var engTone = !running ? 'unknown' : engineTone(d.engineHealth);
        var trackTone = trackerTone(d.trackerState);
        var n = d.nitrous;
        var hasTrack = pipShows(trackTone);   // searching or spotted
        var hasNitro = nitroInstalled(n);

        var mem = pipSlots(d);
        var ageFuel = pipAge(mem, 'fuel', { v: fuel, band: fuelTone }, fuelMoved);
        var ageEng = pipAge(mem, 'engine', { v: health, band: engTone }, engineMoved);
        var ageTrack = pipAge(mem, 'tracker', d.trackerState || '', trackerMoved);
        var ageNitro = pipAge(mem, 'nitrous', {
            inst: hasNitro, lvl: nitroPct(n) / 100,
            act: !!(n && n.active), rdy: !(n && n.ready === false)
        }, nitroMoved);

        /* The RING keeps its real reading whenever the pip is lit at all --
           it is a measurement, and a lit disc with no figure behind it just
           says "something". */
        tone($('pip-fuel'), fuelTone, fuel);
        tone($('pip-engine'), engTone, enginePct(d.engineHealth));
        tone($('pip-tracker'), trackTone);
        tone($('pip-nitrous'), nitroTone(n), nitroPct(n));

        /* NOTE: tone() above rewrites className wholesale, which drops both
           `hidden` and `quiet` -- so everything below has to run AFTER it. */

        /* A CAR THAT IS SWITCHED OFF IS DIM. Its engine, fuel and nitrous pips
           are there but quiet, on the name plate and off it, however recently
           anything moved: lit means the car is doing something, and a parked
           car is not. Turning the key is itself a change, so they light the
           moment it starts. The tracker is not the car's -- it is the police
           -- and keeps its own clock either way. */
        var asleep = function (id) { return !running && id !== 'pip-tracker'; };

        /* A bicycle has no tank and no engine, a train no tank: client.lua
           says so (noFuel / noEngine, from the vehicle class), and those pips
           are not seats on that vehicle -- a grey fuel pump on a BMX was a
           reading of nothing. Nothing new is drawn; the pips that do not
           apply are simply left out. */
        var hasFuel = d.noFuel !== true;
        var hasEngine = d.noEngine !== true;

        /* The name plate is an announcement: here is the car, here is the
           state it is in. Everything it has -- lit if the car is running. */
        if (expanded) {
            show($('pip-fuel'), hasFuel);
            show($('pip-engine'), hasEngine);
            show($('pip-tracker'), hasTrack);
            show($('pip-nitrous'), hasNitro);
            ['pip-fuel', 'pip-engine', 'pip-nitrous'].forEach(function (id) {
                if (asleep(id)) $(id).classList.add('quiet');
            });
            show($('veh-foot'), hasFuel || hasEngine || hasTrack || hasNitro);
            return true;
        }

        /* Collapsed. Engine and fuel are always seats in the row (when the
           vehicle has them); the tracker and nitrous are in it only while
           there is something to track or a kit on the car. The row is up
           while ANY of the pips in it has moved recently, and each pip is lit
           or quiet on its own clock. */
        var row = [];
        if (hasFuel) row.push(['pip-fuel', ageFuel]);
        if (hasEngine) row.push(['pip-engine', ageEng]);
        if (hasTrack) row.push(['pip-tracker', ageTrack]);
        if (hasNitro) row.push(['pip-nitrous', ageNitro]);

        var freshest = row.length
            ? Math.min.apply(null, row.map(function (p) { return p[1]; }))
            : Infinity;
        var rowUp = freshest < PIP_LIT_MS + PIP_DIM_MS;

        show($('pip-fuel'), rowUp && hasFuel);
        show($('pip-engine'), rowUp && hasEngine);
        show($('pip-tracker'), rowUp && hasTrack);
        show($('pip-nitrous'), rowUp && hasNitro);
        if (rowUp) {
            row.forEach(function (p) {
                if (p[1] >= PIP_LIT_MS || asleep(p[0])) $(p[0]).classList.add('quiet');
            });
        }

        /* With every pip hidden the strip is an empty band, so drop it. */
        show($('veh-foot'), rowUp);
        return rowUp;
    }

    /* Manufacturer badge ----------------------------------------------------
       The vehicle panel carries the mark of the marque you are sitting in.
       html/makes.js turns the make into a file in html/logos/; everything about
       how the mark is DRAWN is in style.css, and this only decides which one
       and whether there is one at all.

       Two of the sixty-six manufacturers have no mark, and addon vehicles
       frequently have no resolvable make. Both are ordinary, not errors: they
       clear the class and the panel keeps the plain plate it always had. */
    var badgeKey = null;

    function setBadge(make) {
        var panel = $('vehicle');
        var img = $('veh-logo');
        if (!panel || !img) return;

        var table = window.VICE_MAKES;
        var m = table && table.lookup ? table.lookup(make) : null;
        var key = m && m.logo ? m.key : null;
        /* Cheap guard, not correctness: the poll loop re-pushes this payload
           about four times a second to keep the fuel and lock pips live, and
           reassigning an identical src makes the browser re-decode the image
           every time. */
        if (key === badgeKey) return;
        badgeKey = key;

        if (key) {
            img.src = m.logo;
            img.alt = m.name;
        } else {
            // Cleared, not just hidden. A src left behind is a mark that
            // flashes for one frame the next time the panel is shown.
            img.removeAttribute('src');
            img.alt = '';
        }
        panel.classList.toggle('badged', !!key);
    }

    function onVehicle(d) {
        var el = $('vehicle');
        if (!el) return;
        setBadge(d.make);
        lastVehicle = d.show ? d : null;
        // Out of the car: the next one, or this one again, is all news.
        if (!d.show) { pipMemory = null; slotVanish(el); return; }

        /* Collapsed: the announcement is over, the readings are not.
           Set BEFORE the names are measured -- fitAll() measures against a box
           whose head is collapsed to max-height:0 in this state, and a fit
           computed against a collapsed panel would be wrong the moment it
           expanded again. */
        var collapsed = !!d.collapsed;
        /* Getting into a car while the strip is already up is still an
           ANNOUNCEMENT, and it should arrive like one. Without this the panel
           pops from three icons to a full plate with no motion at all, because
           the element was never hidden and slotAppear has nothing to restart
           from. The reverse edge -- full plate down to icons -- needs no JS
           push like this one: the CSS transition on #veh-head/#veh-foot plays
           off the plain class toggle below, so simply flipping .collapsed is
           enough to animate it. */
        var expanding = !collapsed && el.classList.contains('collapsed');
        el.classList.toggle('collapsed', collapsed);
        if (collapsed) {
            /* Collapsed, the pip row IS the panel -- so with nothing left to
               report there is no panel, and a healthy car simply stops drawing
               one once its announcement is over. Showing an empty plate
               instead is what left a bare box sitting on the map. */
            if (!setPips(d, false)) { slotVanish(el); return; }
            slotAppear(el, false);
            return;
        }

        var make = (d.make || '').toUpperCase();
        var model = (d.model || '').toUpperCase();
        var makeEl = $('veh-make');
        var modelEl = $('veh-model');

        // Addon vehicles often have no resolvable make. Rather than leave a blank
        // row, hide the make line entirely and let the model stand alone.
        show(makeEl, !!make);
        if (makeEl) makeEl.textContent = make;
        if (modelEl) modelEl.textContent = model || 'VEHICLE';

        setPips(d, true);

        // NO restart, EXCEPT on the collapsed -> full edge: the poll loop
        // re-pushes this payload ~4x a second to keep the gauges live, and
        // restarting on each one would hold the panel in a permanent animation.
        slotAppear(el, expanding);
        // After it is displayable, so the panel has a width to measure the
        // names against.
        fitAll();
    }

    /* Minimap mask export (/hudpublish).
       Draws the SAME rounded-rect the native mask texture is baked to --
       identical W/H/INSET math to tools/make_masks.py's coverage() function,
       just rasterised by the canvas's own anti-aliasing instead of 4x4
       supersampling -- so the PNG that comes back is a faithful preview of
       whatever corner radius is actually live right now, not a guess drawn
       from the config number alone. White fill on black, no alpha: this is
       for eyeballing the shape (and feeding an external tool a clean source
       image), not for streaming back into the game as a texture. */
    var MASK_W = 512, MASK_H = 256, MASK_INSET = 3.0;

    function onExportMinimapMask(d) {
        var canvas = document.createElement('canvas');
        canvas.width = MASK_W;
        canvas.height = MASK_H;
        var ctx = canvas.getContext('2d');

        ctx.fillStyle = '#000';
        ctx.fillRect(0, 0, MASK_W, MASK_H);

        var radiusPct = Number(d && d.radiusPct) || 0;
        var r = Math.max(0, Math.min(MASK_H / 2, (radiusPct / 100) * MASK_H));
        var x = MASK_INSET, y = MASK_INSET;
        var w = MASK_W - MASK_INSET * 2, h = MASK_H - MASK_INSET * 2;

        ctx.fillStyle = '#fff';
        ctx.beginPath();
        if (ctx.roundRect) {
            ctx.roundRect(x, y, w, h, r);
        } else {
            // Safari/old-CEF fallback -- same shape, drawn by hand.
            ctx.moveTo(x + r, y);
            ctx.arcTo(x + w, y,     x + w, y + h, r);
            ctx.arcTo(x + w, y + h, x,     y + h, r);
            ctx.arcTo(x,     y + h, x,     y,     r);
            ctx.arcTo(x,     y,     x + w, y,     r);
        }
        ctx.closePath();
        ctx.fill();

        var dataUrl = canvas.toDataURL('image/png');
        post('minimapMaskExport', {
            radiusPct: radiusPct,
            png: dataUrl.slice(dataUrl.indexOf(',') + 1),
        });
    }

    /* Badge diagnostic (/hudlogos).
       Three completely different faults look identical from the driver's seat --
       the marks did not ship, the page cannot see them, or they loaded fine and
       something in the CSS is hiding them -- and they have three different
       fixes. This tries to load every mark in the table and reports what
       actually happened, along with the state of the one element that draws
       them, so the answer comes back as evidence rather than as a guess. */
    function onLogoCheck() {
        var table = window.VICE_MAKES;
        var panel = $('vehicle');
        var img = $('veh-logo');
        /* Name the missing piece. "page not ready" was true and useless: the
           three things it covers fail for completely different reasons, and the
           one that actually happens -- makes.js not being served, so the table
           never exists -- is invisible from the driver's seat because the HUD
           carries on working perfectly without it. */
        if (!table || !panel || !img) {
            post('logoReport', {
                fatal: !table ? 'no-table' : (!panel ? 'no-panel' : 'no-img')
            });
            return;
        }

        var keys = Object.keys(table.makes).filter(function (k) { return !!table.makes[k][1]; });
        var okCount = 0, failed = [], done = 0;
        var cs = window.getComputedStyle(img);
        var clip = $('veh-logo-clip');
        var clipRect = clip ? clip.getBoundingClientRect() : { width: 0, height: 0 };

        function finish() {
            post('logoReport', {
                total: keys.length,
                ok: okCount,
                // Only the first few: this goes to a console, not a log file.
                failed: failed.slice(0, 8),
                // Absolute, so the console shows exactly what the page asked the
                // resource for. A wrong prefix here is the whole answer.
                sampleUrl: new URL(table.makes[keys[0]][1], document.baseURI).href,
                badged: panel.classList.contains('badged'),
                src: img.getAttribute('src') || '',
                display: cs.display,
                opacity: cs.opacity,
                imgW: img.clientWidth,
                imgH: img.clientHeight,
                clipW: Math.round(clipRect.width),
                clipH: Math.round(clipRect.height)
            });
        }

        keys.forEach(function (k) {
            var probe = new Image();
            probe.onload = function () {
                okCount++;
                if (++done === keys.length) finish();
            };
            probe.onerror = function () {
                failed.push(k);
                if (++done === keys.length) finish();
            };
            probe.src = table.makes[k][1];
        });
        if (!keys.length) finish();
    }

    /* Roster walk (/hudbrand with no argument).
       Driven from here rather than from Lua because the table is here: the
       page holds the only copy and can therefore never walk a roster that has
       drifted from the marks it is actually drawing. Running it
       again stops the one in flight — two tours pushing at each other would
       just flicker. */
    var tourTimer = null;

    function onBrandTour(d) {
        if (tourTimer) { clearTimeout(tourTimer); tourTimer = null; onVehicle({ show: false }); return; }
        var table = window.VICE_MAKES;
        if (!table) return;
        var keys = Object.keys(table.makes).sort();
        var ms = d && d.ms > 0 ? d.ms : 4000;
        var i = 0;

        (function step() {
            if (i >= keys.length) { tourTimer = null; onVehicle({ show: false }); return; }
            var m = table.makes[keys[i++]];
            // The MARQUE on the model line, so the tour answers the question you
            // are actually asking of it: whose badge is this, and does it look
            // like the real-world one it is standing in for.
            onVehicle({ show: true, make: m[0], model: m[2],
                        fuel: 70, engineOn: true, engineHealth: 1000 });
            tourTimer = setTimeout(step, ms);
        }());
    }

    /* --- honor toast ----------------------------------------------------- */

    // Centre-screen change indicator. Separate from the corner panel: this is
    // the EVENT (honor just moved), the corner is the STATE (where it stands).
    var honorPopTimer = null;
    var honorHideTimer = null;

    function onHonorPop(delta, icon, broken, up) {
        var el = $('honor-pop');
        if (!el) return;
        var sign = $('honor-pop-sign');
        var face = $('honor-pop-face');
        var crack = $('honor-pop-crack');

        if (broken) {
            // Broken isn't a direction -- no sign. The face is the terrible-
            // deed art itself now (see honorEmoji() in client.lua), not a
            // greyed-out copy of the standing badge.
            el.className = 'broken';
            if (sign) sign.textContent = '';
            show(crack, true);
        } else {
            // `up` is passed explicitly by onHonor now rather than always
            // being derived from delta's sign -- once honor is clamped at
            // Config.MinHonor/MaxHonor, further hooks still fire (and still
            // deserve a popup) but move the NUMBER by zero, so delta alone
            // can no longer say which way the deed pointed. Falls back to
            // delta's sign for any older/direct caller that doesn't pass it.
            if (up === undefined) up = delta > 0;
            el.className = up ? 'up' : 'down';
            if (sign) sign.textContent = up ? '+' : '−';
            show(crack, false);
        }
        if (face) {
            if (icon) { face.src = icon; show(face, true); } else { show(face, false); }
        }

        show(el, true);
        if (honorPopTimer) clearTimeout(honorPopTimer);
        honorPopTimer = setTimeout(function () { show(el, false); }, 2200);
    }

    function onHonor(d) {
        // A change fires the centre indicator; the corner panel then just
        // reflects the current standing and stays put. Gated on delta OR
        // severity/broken, NOT delta alone -- once honor is clamped at
        // Config.MinHonor/MaxHonor, qbx_honor's own gate (client/main.lua)
        // can still push a notable deed through (a kill is still 'terrible',
        // a floor-hit is still worth showing) with the NUMBER unchanged, so
        // gating strictly on a non-zero delta would silently swallow every
        // one of those once you're maxed out. severity supplies the
        // direction delta can no longer show in that case.
        if (d.delta || d.severity || d.broken) {
            var up = d.delta ? d.delta > 0 : d.severity === 'good';
            var dirIcon = d.broken ? d.terribleEmoji
                : d.severity === 'terrible' ? d.terribleEmoji
                : (up ? d.angelEmoji : d.devilEmoji);
            onHonorPop(d.delta, dirIcon, d.broken, up);
        }

        // A DEED push (exports.vice_hud:ShowHonorDeed) is the centre indicator
        // and nothing else -- it must not touch, show, or re-time the corner
        // panel. The panel is the STANDING readout and only qbx_honor's
        // tier-change path (ShowHonorToast) is allowed to raise it.
        if (d.popOnly) return;

        var el = $('honor');
        if (!el) return;
        var img = $('honor-img');
        if (img) {
            if (d.mugshot) { img.src = d.mugshot; img.style.display = 'block'; }
            else { img.removeAttribute('src'); img.style.display = 'none'; }
        }
        // The badge is the face for the CURRENT honor level, not for the
        // change -- except once broken, which overrides it with the
        // terrible-deed face regardless of tier (see qbx_honor's
        // unrepairable-floor comment below). Also desaturated once broken --
        // same "spent, not merely low" treatment ox_inventory's and
        // qbx_relog's own honor chips use (see their .broken/.honor-broken
        // rules) -- so all three honor displays read the same way.
        var badge = $('honor-badge');
        var badgeIcon = d.broken ? (d.terribleEmoji || d.emoji) : d.emoji;
        if (badge) {
            if (badgeIcon) { badge.src = badgeIcon; show(badge, true); } else { show(badge, false); }
            badge.classList.toggle('broken', !!d.broken);
        }

        // qbx_honor's unrepairable floor: once broken, always broken for this
        // session -- this only ever turns the crack overlay ON here because
        // the caller (ShowHonorToast/SetHonorStanding in client.lua) already
        // enforces the same one-way latch, so `d.broken` is never sent false
        // after having been sent true.
        if (d.broken) {
            show($('honor-crack'), true);
        }

        // With showValue off this is the reference treatment: the corner panel
        // is the mugshot and its face, nothing else. With it on the panel also
        // reads out the standing, which is the only place the exact number is
        // visible in game.
        var titleText = (d.showValue && typeof d.honor === 'number')
            ? ((d.valueLabel || 'HONOR') + ' ' + d.honor)
            : '';
        var subText = (d.showValue && d.reason) ? d.reason : '';

        var title = $('honor-title');
        if (title) title.textContent = titleText;

        var sub = $('honor-sub');
        if (sub) sub.textContent = subText;

        // With both lines empty (Config.Honor.showValue = false -- the
        // reference treatment, where the panel is just the mugshot and its
        // face) the copy column has to come OUT of the flex row, not merely
        // go blank. A zero-width child still takes the row's 0.8cqw gap, and
        // #honor's padding is deliberately asymmetric -- 1.3cqw on the copy
        // side against 0.5cqw on the mug side -- so leaving an empty column
        // in place draws a lopsided box with dead space where the text was.
        var hasCopy = !!(titleText || subText);
        show($('honor-copy'), hasCopy);
        el.classList.toggle('bare', !hasCopy);

        if (honorHideTimer) { clearTimeout(honorHideTimer); honorHideTimer = null; }

        if (d.show === false) { show(el, false); return; }

        show(el, true);

        // The panel is a readout you get when something happens, not furniture
        // parked in the corner all session. holdMs of 0 (or missing) keeps the
        // old behaviour of leaving it up until something hides it.
        var hold = typeof d.holdMs === 'number' ? d.holdMs : 0;
        if (hold > 0) {
            honorHideTimer = setTimeout(function () {
                honorHideTimer = null;
                // The layout editor forces every panel visible with sample
                // content; a timer left over from before it opened must not
                // yank this one back out from under it.
                if (editorOpen) return;
                show($('honor'), false);
            }, hold);
        }
    }

    /* --- reputation toast --------------------------------------------------
       Same EVENT/STATE split as honor above, minus the direction: reputation
       only ever goes up (qbx_reputation's tracks are floor-0), so the popup is
       a single "+N icon", not an up/down pair. */
    var reputationPopTimer = null;
    var reputationHideTimer = null;

    function onReputationPop(delta, icon) {
        var el = $('reputation-pop');
        if (!el || !delta) return;
        var sign = $('reputation-pop-sign');
        if (sign) sign.textContent = '+' + Math.abs(delta);
        var face = $('reputation-pop-face');
        if (face) face.textContent = icon || '';
        show(el, true);
        if (reputationPopTimer) clearTimeout(reputationPopTimer);
        reputationPopTimer = setTimeout(function () { show(el, false); }, 2200);
    }

    function onReputation(d) {
        if (d.delta) onReputationPop(d.delta, d.icon);

        var el = $('reputation');
        if (!el) return;

        var icon = $('reputation-icon');
        if (icon) icon.textContent = d.icon || '';

        // Same reference treatment as honor: with showValue off the panel is
        // just the icon and the track name, nothing else.
        var title = $('reputation-title');
        if (title) {
            var name = d.label || 'REPUTATION';
            title.textContent = (d.showValue && typeof d.value === 'number')
                ? (name + ' ' + d.value + (d.tier ? ' · T' + d.tier : ''))
                : name;
        }

        var sub = $('reputation-sub');
        if (sub) sub.textContent = (d.showValue && d.reason) ? d.reason : '';

        if (reputationHideTimer) { clearTimeout(reputationHideTimer); reputationHideTimer = null; }

        if (d.show === false) { show(el, false); return; }

        show(el, true);

        var hold = typeof d.holdMs === 'number' ? d.holdMs : 0;
        if (hold > 0) {
            reputationHideTimer = setTimeout(function () {
                reputationHideTimer = null;
                if (editorOpen) return;
                show($('reputation'), false);
            }, hold);
        }
    }

    /* --- action prompts -------------------------------------------------- */

    var prompts = {};
    // id -> the .prompt-glyph-wrap element for whichever rows are currently
    // hold-enabled, so a promptProgress tick can write --prompt-frac onto
    // just that one wrapper instead of tearing down and rebuilding every
    // prompt row every frame a hold is in progress (renderPrompts only runs
    // on show/hide/glyph-refresh, not per-tick).
    var promptGlyphWraps = {};

    function renderPrompts() {
        var box = $('prompts');
        if (!box) return;
        box.innerHTML = '';
        promptGlyphWraps = {};
        Object.keys(prompts).forEach(function (id) {
            var p = prompts[id];
            var row = document.createElement('div');
            row.className = 'prompt' + (p.off ? ' off' : '');

            var label = document.createElement('span');
            label.className = 'prompt-label';
            label.textContent = p.label || '';

            var g = setGlyph(document.createElement('span'), p.glyph, p.device, 'glyph',
                             p.hold ? true : 'space');

            row.appendChild(label);

            // No button at all (nothing bound, or a "you cannot do this" row):
            // the label stands alone.
            if (g.classList.contains('none')) {
                row.classList.add('bare');
            } else {
                // The cell is what a hold's progress is written onto, and what
                // keeps a row's height the same with or without a button.
                var wrap = document.createElement('span');
                wrap.className = 'prompt-glyph-wrap';
                wrap.appendChild(g);
                row.appendChild(wrap);
                if (p.hold) {
                    wrap.classList.add('holdable');
                    wrap.style.setProperty('--prompt-frac', 0);
                    promptGlyphWraps[id] = wrap;
                }
            }

            box.appendChild(row);
        });
    }

    function onPrompt(d) {
        if (!d.id) return;
        if (d.show === false) delete prompts[d.id];
        else prompts[d.id] = { label: d.label, glyph: d.glyph, device: d.device, hold: !!d.hold, off: !!d.off };
        renderPrompts();
    }

    // Fired every tick client.lua's hold-poll thread sees a frac change for
    // a held prompt -- NOT routed through renderPrompts/onPrompt, both of
    // which rebuild the whole #prompts box; a hold can fire many times a
    // second and rebuilding every row that often would be needless churn.
    function onPromptProgress(d) {
        var wrap = d && d.id && promptGlyphWraps[d.id];
        if (!wrap) return;
        wrap.style.setProperty('--prompt-frac', Math.max(0, Math.min(1, d.frac || 0)));
    }

    // client_glyphs.lua says which device is in hand and which pad the player
    // has. The device half arrives with freshly resolved buttons for whatever
    // is on screen; the pad style does not, so that one redraws from here.
    var lastWorldActions = null;
    var lastNitrousHint = null;

    function onInputDevice(d) {
        var style = d && d.pad === 'ps' ? 'ps' : 'xbox';
        if (style === padStyle) return;
        padStyle = style;
        renderPrompts();
        if (lastWorldActions && lastWorldActions.show) onWorldActions(lastWorldActions);
        if (lastBinoculars) onBinoculars(lastBinoculars);
        if (lastNitrousHint) {
            onNitrousHint({ show: true, refresh: true,
                            glyph: lastNitrousHint.glyph, device: lastNitrousHint.device });
        }
    }

    /* --- screen text and overlays ------------------------------------------
       Subtitle, objective, help box, feed, title cards, the binocular mask
       and the shop item panel. Each is one export in client_overlays.lua
       and one handler here; none of them animates, they cut in and out as the
       reference does.

       Text takes two marks: **bold** for a key word, {braces} for the thing
       the line is about (drawn pink, as the reference draws a destination). */
    function richText(el, text) {
        var s = String(text == null ? '' : text)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        s = s.replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
             .replace(/\{([^}]+)\}/g, '<em>$1</em>')
             .replace(/\n/g, '<br>');
        el.innerHTML = s;
    }

    var overlayTimers = {};
    // Show `el` now and take it down after `holdMs` (0 or less: until told).
    function holdFor(key, el, holdMs, fallbackMs, onDown) {
        if (overlayTimers[key]) { clearTimeout(overlayTimers[key]); overlayTimers[key] = null; }
        show(el, true);
        var ms = typeof holdMs === 'number' ? holdMs : fallbackMs;
        if (ms > 0) {
            overlayTimers[key] = setTimeout(function () {
                overlayTimers[key] = null;
                show(el, false);
                if (onDown) onDown();
            }, ms);
        }
    }
    function takeDown(key, el) {
        if (overlayTimers[key]) { clearTimeout(overlayTimers[key]); overlayTimers[key] = null; }
        show(el, false);
    }

    function onSubtitle(d) {
        var el = $('subtitle');
        if (!el) return;
        if (!d || d.show === false || !d.text) { takeDown('subtitle', el); return; }
        richText(el, d.text);
        holdFor('subtitle', el, d.holdMs, 4000);
    }

    function onObjective(d) {
        var el = $('objective');
        if (!el) return;
        var down = function () { if (stage) stage.classList.remove('has-objective'); };
        if (!d || d.show === false || !d.text) { takeDown('objective', el); down(); return; }
        richText(el, d.text);
        if (stage) stage.classList.add('has-objective');
        holdFor('objective', el, d.holdMs, 0, down);
    }

    function onHelpText(d) {
        var el = $('help-text');
        if (!el) return;
        if (!d || d.show === false || !d.text) { takeDown('helpText', el); return; }
        richText(el, d.text);
        // [[1]], [[2]]: the buttons client_overlays.lua resolved from opts.keys,
        // in the line where the text names them ('aim with [[1]] and hold [[2]]').
        if (d.glyphs && d.glyphs.length) {
            el.innerHTML = el.innerHTML.replace(/\[\[(\d+)\]\]/g, '<span class="help-glyph" data-key="$1"></span>');
            el.querySelectorAll('.help-glyph').forEach(function (span) {
                var g = d.glyphs[Number(span.getAttribute('data-key')) - 1];
                if (g) setGlyph(span, g.glyph, g.device, 'glyph help-glyph');
            });
        }
        // The reference puts the wanted tells under a line about the police.
        if (d.tells && d.tells.length) {
            var row = document.createElement('div');
            row.className = 'help-tells';
            renderTells(row, d.tells);
            el.appendChild(row);
        }
        holdFor('helpText', el, d.holdMs, 7000);
    }

    // One line in the feed on the right: "Crime reported", "+ $6" with the
    // wallet beside it. Lines stack downward and leave on their own.
    function onFeed(d) {
        var box = $('feed');
        if (!box || !d || !d.text) return;
        var line = document.createElement('div');
        line.className = 'feed-line';
        // A count ("2 scored"): a size up, and in place of the last one.
        if (d.counter) {
            line.classList.add('counter');
            line.setAttribute('data-counter', d.counter);
            Array.prototype.forEach.call(box.querySelectorAll('.feed-line.counter'), function (old) {
                if (old.getAttribute('data-counter') === d.counter) box.removeChild(old);
            });
        }
        var text = document.createElement('span');
        richText(text, d.text);
        line.appendChild(text);
        if (d.icon) {
            var img = document.createElement('img');
            img.src = d.icon;
            img.alt = '';
            line.appendChild(img);
        }
        box.appendChild(line);
        while (box.children.length > 5) box.removeChild(box.firstChild);
        var ms = typeof d.holdMs === 'number' ? d.holdMs : 3500;
        if (ms > 0) setTimeout(function () { if (line.parentNode) line.parentNode.removeChild(line); }, ms);
    }

    var TITLE_SPARKLE = '<svg class="title-sparkle" viewBox="0 0 30 34" aria-hidden="true">'
        + '<path d="M11 12q1 9 10 10-9 1-10 10-1-9-10-10 9-1 10-10z"/>'
        + '<path d="M23 0q.6 5.2 5.8 5.8-5.2.6-5.8 5.8-.6-5.2-5.8-5.8 5.2-.6 5.8-5.8z"/></svg>';

    function onTitleCard(d) {
        var el = $('title-card');
        if (!el) return;
        if (!d || d.show === false || !d.text) { takeDown('titleCard', el); return; }
        var style = d.style === 'stack' || d.style === 'location' ? d.style : 'center';
        el.className = style;
        // A stacked card is one word a line unless the caller broke it itself.
        var text = String(d.text);
        if (style === 'stack' && text.indexOf('\n') < 0) text = text.split(/\s+/).join('\n');
        el.textContent = text;
        if (style === 'location') el.insertAdjacentHTML('beforeend', TITLE_SPARKLE);
        holdFor('titleCard', el, d.holdMs, 3500);
    }

    var lastBinoculars = null;

    function onBinoculars(d) {
        var el = $('binoculars');
        if (!el) return;
        // Through binoculars there is the lens, what it is on, the prompts and
        // any speech; the rest of the HUD waits (see #stage.bino).
        if (stage) stage.classList.toggle('bino', !!(d && d.show !== false));
        if (!d || d.show === false) { lastBinoculars = null; show(el, false); return; }
        lastBinoculars = d;
        var label = $('bino-label');
        if (label) {
            show(label, !!d.label);
            $('bino-label-text').textContent = d.label || '';
            setGlyph($('bino-label-btn'), d.glyph, d.device, 'wa-btn glyph');
        }
        show(el, true);
    }

    // { store, category, price, pay: ['bank','cash'], name, variant,
    //   swatches: [{ color, image, locked }], selected (1-based), note, afford,
    //   strip, counter, more, progress: { first, shown, total }, status }
    // A swatch with an image (an https address) shows that picture of the
    // variant on a plain tile; one without is its colour.
    // strip: the row is the items themselves, as the GTA VI barber shows its
    // hairstyles - each picture fills its tile, "counter" ("1 / 9") over the
    // row's end, "more" an arrow after it when the list goes on, "progress" a
    // hairline under it as long and as far along as the tiles shown are of the
    // whole list, and "status" ("Not applied") a plain line under that.
    var SHOP_PAY = { cash: 'icons/cash.png', bank: 'icons/buckme.png' };
    var SHOP_IMAGE = /^https:\/\/[\w.\-\/]+$/;

    function onShop(d) {
        var el = $('shop');
        if (!el) return;
        if (!d || d.show === false) {
            show(el, false);
            if (stage) stage.classList.remove('shopping');
            return;
        }
        $('shop-store').textContent = d.store || '';
        $('shop-category').textContent = d.category || '';
        $('shop-price').textContent = d.price == null ? '' : money(d.price);
        $('shop-name').textContent = d.name || '';
        $('shop-variant').textContent = d.variant || '';

        var pay = $('shop-pay');
        pay.innerHTML = '';
        (d.pay || ['bank', 'cash']).forEach(function (kind) {
            if (!SHOP_PAY[kind]) return;
            var img = document.createElement('img');
            img.src = SHOP_PAY[kind];
            img.alt = kind;
            pay.appendChild(img);
        });

        var row = $('shop-swatches');
        row.innerHTML = '';
        (d.swatches || []).forEach(function (sw, i) {
            var cell = document.createElement('div');
            cell.className = 'shop-swatch' + (i + 1 === d.selected ? ' on' : '') + (sw && sw.locked ? ' locked' : '');
            if (sw && typeof sw.image === 'string' && SHOP_IMAGE.test(sw.image)) {
                cell.className += ' pic';
                cell.style.backgroundImage = 'url("' + sw.image + '")';
            } else {
                cell.style.backgroundColor = (sw && sw.color) || '#888';
            }
            row.appendChild(cell);
        });

        el.classList.toggle('strip', !!d.strip);
        show($('shop-strip'), (d.swatches || []).length > 0);
        $('shop-counter').textContent = d.counter || '';
        show($('shop-more'), !!d.more);
        var prog = d.progress, total = prog && Number(prog.total);
        var showBar = !!(total && Number(prog.shown) < total);
        show($('shop-progress'), showBar);
        if (showBar) {
            // (no shorter than a twentieth, so that it shows on a long list, and kept inside its track)
            var thumb = $('shop-progress-thumb');
            var width = Math.max(Number(prog.shown) / total, 0.05);
            var left = Math.min(Math.max(0, Number(prog.first) - 1) / total, 1 - width);
            thumb.style.left = (left * 100) + '%';
            thumb.style.width = (width * 100) + '%';
        }
        show($('shop-status'), !!d.status);
        $('shop-status').textContent = d.status || '';

        var cant = d.afford === false;
        el.classList.toggle('cant', cant);
        var note = d.note || (cant ? 'Not enough money' : '');
        show($('shop-note'), !!note);
        $('shop-note-text').textContent = note;

        if (stage) stage.classList.add('shopping');
        show(el, true);
    }

    // { make, model, stats: [{ label, value, max (default 10) }],
    //   ratings: [{ value, kind: 'offroad' | 'road' }] }
    var VS_RATING_ICON = {
        offroad: '<svg viewBox="0 0 28 28" aria-hidden="true"><rect class="vs-tile" width="28" height="28"/>'
            + '<path class="vs-mark" d="M4 21 10.500 9l4.500 7 3.500-4.500L24 21"/></svg>',
        road: '<svg viewBox="0 0 28 28" aria-hidden="true"><rect class="vs-tile" width="28" height="28"/>'
            + '<path class="vs-solid" d="M10.500 4h2l-1 20H6zM15.500 4h2l4.500 20h-5.500z"/></svg>'
    };

    function onVehStats(d) {
        var el = $('veh-stats');
        if (!el) return;
        if (!d || d.show === false) { show(el, false); return; }
        $('vs-make').textContent = d.make || '';
        $('vs-model').textContent = d.model || '';

        var rows = $('vs-rows');
        rows.innerHTML = '';
        (d.stats || []).forEach(function (s) {
            var max = typeof s.max === 'number' && s.max > 0 ? s.max : 10;
            var value = typeof s.value === 'number' ? s.value : 0;
            var row = document.createElement('div');
            row.className = 'vs-row';
            var label = document.createElement('span');
            label.className = 'vs-label';
            label.textContent = s.label || '';
            var num = document.createElement('span');
            num.className = 'vs-value';
            num.textContent = value.toFixed(1);
            var bar = document.createElement('div');
            bar.className = 'vs-bar';
            var fill = document.createElement('div');
            fill.className = 'vs-fill';
            fill.style.setProperty('--vs', Math.max(0, Math.min(1, value / max)));
            bar.appendChild(fill);
            row.appendChild(label);
            row.appendChild(num);
            row.appendChild(bar);
            rows.appendChild(row);
        });

        var ratings = $('vs-ratings');
        ratings.innerHTML = '';
        (d.ratings || []).forEach(function (r) {
            var n = document.createElement('span');
            n.textContent = r.value == null ? '' : String(r.value);
            ratings.appendChild(n);
            if (VS_RATING_ICON[r.kind]) ratings.insertAdjacentHTML('beforeend', VS_RATING_ICON[r.kind]);
        });
        show($('vs-foot'), (d.ratings || []).length > 0);
        show(el, true);
    }

    // { show, strength (0..2), bars (fraction of the screen's height), pulse }
    function onCineFx(d) {
        var el = $('cine-fx');
        if (!el) return;
        var on = !!(d && d.show);
        el.classList.toggle('active', on);
        if (!on) return;
        var strength = typeof d.strength === 'number' ? Math.max(0, Math.min(2, d.strength)) : 1;
        var bars = typeof d.bars === 'number' ? Math.max(0, Math.min(0.2, d.bars)) : 0.032;
        el.style.setProperty('--cine-strength', strength);
        el.style.setProperty('--cine-bars', (bars * 100) + 'vh');
        el.classList.toggle('pulse', d.pulse !== false);
    }

    // Targeting's page is a frame (#target-ui). Its Lua side wraps what it
    // would have sent to a page of its own in 'target:nui'; the payload goes
    // through untouched. The frame takes clicks only between a panel opening
    // and closing.
    function onTargetNui(d) {
        var frame = $('target-ui');
        var msg = d && d.payload;
        if (!frame || !msg) return;
        if (msg.action === 'admin:open' || msg.action === 'prefs:open') frame.classList.add('open');
        if (msg.action === 'admin:close' || msg.action === 'prefs:close') frame.classList.remove('open');
        if (frame.contentWindow) frame.contentWindow.postMessage(msg, '*');
    }

    function onPromptGlyphs(d) {
        // Device or bindings changed — refresh labels on anything already shown.
        // `glyphs` is the whole answer for the new device: a prompt missing
        // from it has no button there, and must not keep the old device's.
        Object.keys(prompts).forEach(function (id) {
            if (d.glyphs) prompts[id].glyph = d.glyphs[id] == null ? null : d.glyphs[id];
            prompts[id].device = (d.devices && d.devices[id]) || d.device || prompts[id].device;
        });
        renderPrompts();
    }

    /* --- directional police glow ------------------------------------------ */

    var POL_EDGES = ['top', 'right', 'bottom', 'left'];

    // Keys map straight onto the CSS custom properties the lamp shapes and
    // sweep animation read (see the "Directional police glow" block in
    // style.css) — one entry point for both the live scan and the editor.
    var POL_VARS = {
        lampA: '--pol-lamp-a', lampB: '--pol-lamp-b', spread: '--pol-spread',
        sweepAmt: '--pol-sweep', softness: '--pol-softness', whiteA: '--pol-white-a',
        whiteLampA: '--pol-white-w', whiteLampB: '--pol-white-h'
    };

    var POL_RADIUS_VARS = ['rx', 'ry', 'bx', 'by', 'wx', 'wy'];

    function onPolice(d) {
        // Shared vars go on the document root rather than #police, because
        // #police-radius (the alternative render mode) is a SIBLING, not a
        // descendant, and would not inherit anything set on #police alone.
        var root = document.documentElement;
        if (d.flashMs) root.style.setProperty('--pol-flash', d.flashMs + 'ms');
        if (d.sweepMs) root.style.setProperty('--pol-sweep-ms', d.sweepMs + 'ms');
        Object.keys(POL_VARS).forEach(function (k) {
            if (d[k] != null) root.style.setProperty(POL_VARS[k], String(d[k]));
        });

        // Edges mode. When the payload is from radius mode there is no
        // `edges` field, so every edge's opacity naturally falls to 0 here —
        // no explicit mode check needed to keep the two visuals from
        // overlapping.
        // The GTA VI shape draws on its own canvas (polVi below), so the
        // classic lamps stay at 0 rather than doubling up under it.
        var classic = d.shape === 'wide';
        var edges = d.edges || {};
        var box = $('police');
        if (box) box.classList.toggle('no-white', d.white === false);
        for (var i = 0; i < POL_EDGES.length; i++) {
            var name = POL_EDGES[i];
            var el = document.querySelector('.pol-' + name);
            if (!el) continue;
            var v = d.active === false || !classic ? 0 : (edges[name] || 0);
            el.style.opacity = String(Math.max(0, Math.min(1, v)));
        }

        // Radius mode. Same reasoning in reverse: with no `rx`/`strength`
        // fields from an edges-mode payload, this collapses to invisible.
        var radiusBox = $('police-radius');
        if (radiusBox) {
            radiusBox.classList.toggle('no-white', d.white === false);
            POL_RADIUS_VARS.forEach(function (k) {
                if (d[k] != null) radiusBox.style.setProperty('--pol-' + k, d[k] + '%');
            });
            var rv = d.active === false || !classic ? 0 : (d.strength || 0);
            radiusBox.style.opacity = String(Math.max(0, Math.min(1, rv)));
        }

        polViUpdate(d);
    }

    /* --- GTA VI police lights + arrow ---------------------------------------
       Ported from the single-player HUD 2.6.2 (ViExtras PoliceLights). Lua
       pushes targets a few times a second; everything that moves -- the
       trailer frames, the 420ms fades, the bearing and size easing, the arrow
       -- runs here on one canvas, and only while something is showing.

       All drawing is in the single-player HUD's units: 1080 tall, as wide as
       the aspect ratio makes it, then scaled to the window. */

    // Which of row.png's 90 pictures shows on each frame of the trailer's
    // 30fps loop; -1 is a frame with the lights off.
    var POL_PICTURE = [
        0, 0, 0, 0, -1, -1, -1, -1, -1, -1, -1, 1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 26, 27, 28,
        28, 29, 30, 30, 31, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45,
        46, 47, 48, 49, 50, 51, 52, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64,
        65, 66, 67, 68, 69, 69, 70, 71, 72, 73, 74, 75, 76, 77, 77, 78, 79, 80, 81, 82,
        83, 83, 84, 85, 86, 87, 88, 89
    ];
    var POL_ROW_W = 140, POL_ROW_H = 52, POL_ROW_COLS = 10;   // icons/police/row.png
    var POL_TIP = 24, POL_TIP_COLS = 8;                      // icons/police/tips.png, 64 directions
    // Same order and angles as client.lua's EDGE_ANGLE: top, right, bottom, left.
    var POL_EDGE_ANGLE = [0, -90, 180, 90];
    var POL_ARROW_WHITE = [240, 240, 240, 230];
    var POL_ARROW_BLUE = [62, 98, 222, 242];

    var polVi = {
        shape: 'round', mode: 'radius', size: 1, arrowOn: true,
        maxOpacity: 0.55, nearSize: 19, farSize: 8, roundOpacity: 1,
        from: [0, 0, 0, 0], to: [0, 0, 0, 0], since: [0, 0, 0, 0],
        rel: 0, relTarget: 0, relSet: false,
        near: 0, nearTarget: 0, nearSet: false,
        arrowSeen: false, arrowBeside: false, arrowRel: 0, arrowRelTarget: 0,
        arrowFill: 0, arrowFillTarget: 0, arrowA: 0,
        clock0: 0, running: false, last: 0, ctx: null, row: null, tips: null, tint: {}
    };

    function polClamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
    function polNormalise(a) { a = (a + 180) % 360; if (a < 0) a += 360; return a - 180; }

    // CSS-style cubic-bezier easing, solved the same way the single-player
    // HUD does it, so the fades land on the same curve.
    function polBezier(x1, y1, x2, y2, x) {
        if (x <= 0) return 0;
        if (x >= 1) return 1;
        function cubic(p1, p2, t) { var u = 1 - t; return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t; }
        var lo = 0, hi = 1, t = x;
        for (var i = 0; i < 24; i++) {
            t = (lo + hi) * 0.5;
            if (cubic(x1, x2, t) < x) lo = t; else hi = t;
        }
        return cubic(y1, y2, t);
    }

    function polNow() { return typeof performance !== 'undefined' ? performance.now() : Date.now(); }

    function polOpacity(i, now) {
        var x = polClamp01((now - polVi.since[i]) / 420);
        return polVi.from[i] + (polVi.to[i] - polVi.from[i]) * polBezier(0.4, 0, 0.2, 1, x);
    }

    function polViUpdate(d) {
        var s = polVi, now = polNow();
        if (d.shape) s.shape = d.shape;
        if (d.mode) s.mode = d.mode;
        if (d.size != null) s.size = d.size <= 0 ? 0 : Math.max(0.4, Math.min(2, d.size / 100));
        if (d.arrowOn != null) s.arrowOn = !!d.arrowOn;
        if (d.maxOpacity) s.maxOpacity = d.maxOpacity;
        if (d.nearSize) s.nearSize = d.nearSize;
        if (d.farSize) s.farSize = d.farSize;
        if (d.roundOpacity != null) s.roundOpacity = polClamp01(d.roundOpacity);

        var on = d.active !== false && s.shape !== 'wide';
        var targets = [0, 0, 0, 0];
        var strongest = 0;
        if (on && d.edges) {
            var e = d.edges;
            targets = [e.top || 0, e.right || 0, e.bottom || 0, e.left || 0];
            strongest = Math.max.apply(null, targets);
        } else if (on && d.strength) {
            targets = [d.strength, 0, 0, 0];
            strongest = d.strength;
        }

        if (strongest > 0 && d.rel != null) {
            s.relTarget = d.rel;
            if (!s.relSet || polOpacity(0, now) < 0.01) s.rel = d.rel;
            s.relSet = true;
        }
        if (strongest > 0 && d.near != null) {
            var dark = true;
            for (var k = 0; k < 4; k++) if (polOpacity(k, now) >= 0.01) dark = false;
            if (!s.nearSet || dark) s.near = d.near;
            s.nearTarget = d.near;
            s.nearSet = true;
        }

        var a = d.arrow || {};
        s.arrowSeen = d.active !== false && !!a.seen;
        if (s.arrowSeen) {
            s.arrowRelTarget = a.rel || 0;
            s.arrowFillTarget = polClamp01(a.fill || 0);
            s.arrowBeside = !!a.beside;
        }

        for (var i = 0; i < 4; i++) {
            var v = Math.round(targets[i] * 100) / 100;
            if (Math.abs(v - s.to[i]) < 0.005) continue;
            s.from[i] = polOpacity(i, now);
            s.to[i] = v;
            s.since[i] = now;
        }

        if (!s.running && (s.arrowSeen || s.to.some(function (o) { return o > 0; }))) polViStart();
    }

    function polViStart() {
        var canvas = $('police-vi');
        if (!canvas || !canvas.getContext) return;
        var s = polVi;
        if (!s.ctx) {
            s.ctx = canvas.getContext('2d');
            if (!s.ctx) return;
            s.row = new Image(); s.row.src = 'icons/police/row.png';
            s.tips = new Image(); s.tips.src = 'icons/police/tips.png';
            s.clock0 = polNow();
        }
        s.running = true;
        s.last = polNow();
        raf(polViFrame);
    }

    // Top/bottom/left/right of the screen's rectangle at bearing `rel`, so a
    // car to the south-west lands in the bottom-left corner.
    function polPerimeter(rel, W) {
        var r = rel * Math.PI / 180, dx = -Math.sin(r), dy = -Math.cos(r);
        var t = 1 / Math.max(Math.abs(dx), Math.abs(dy), 0.0001);
        return [(50 + dx * t * 50) / 100 * W, (50 + dy * t * 50) / 100 * 1080];
    }

    // Which edge that point is on, as the inward normal.
    function polNormal(rel) {
        var r = rel * Math.PI / 180, dx = -Math.sin(r), dy = -Math.cos(r);
        if (Math.abs(dx) >= Math.abs(dy)) return [dx < 0 ? 1 : -1, 0];
        return [0, dy < 0 ? 1 : -1];
    }

    // A white sprite drawn in a colour: tinted once into a small canvas and
    // kept, keyed by colour, since the arrow only ever uses a handful.
    function polTinted(img, sx, sy, sw, sh, rgb, key) {
        var c = polVi.tint[key];
        if (c) return c;
        c = document.createElement('canvas');
        c.width = sw; c.height = sh;
        var g = c.getContext('2d');
        g.drawImage(img, sx, sy, sw, sh, 0, 0, sw, sh);
        g.globalCompositeOperation = 'source-in';
        g.fillStyle = 'rgb(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ')';
        g.fillRect(0, 0, sw, sh);
        polVi.tint[key] = c;
        return c;
    }

    function polLerpColor(t) {
        var a = POL_ARROW_WHITE, b = POL_ARROW_BLUE, out = [];
        for (var i = 0; i < 4; i++) out.push(Math.round(a[i] + (b[i] - a[i]) * t));
        return out;
    }

    function polRow(ctx, p, n, scale, o, f) {
        var pic = POL_PICTURE[f];
        if (pic < 0) return;
        // The trailer's own flicker: a hair brighter or dimmer frame to frame.
        var grain = ((1749218071 >>> f) & 1) === 0 ? 0.996 : 1.004;
        var alpha = polClamp01(o / Math.max(0.01, polVi.maxOpacity) * polVi.roundOpacity * grain);
        if (alpha <= 0.003 || !polVi.row.complete || !polVi.row.naturalWidth) return;
        var along = 560 * scale, tall = 208 * scale, inset = 72 * scale;
        // row.png is the bottom edge's picture; the others are it turned.
        var angle = n[0] !== 0 ? (n[0] > 0 ? 90 : -90) : (n[1] < 0 ? 0 : 180);
        ctx.save();
        ctx.globalAlpha = alpha;
        ctx.translate(p[0] + n[0] * inset, p[1] + n[1] * inset);
        ctx.rotate(angle * Math.PI / 180);
        ctx.drawImage(polVi.row,
            (pic % POL_ROW_COLS) * POL_ROW_W, Math.floor(pic / POL_ROW_COLS) * POL_ROW_H, POL_ROW_W, POL_ROW_H,
            -along / 2, -tall / 2, along, tall);
        ctx.restore();
    }

    function polDrawRound(ctx, now, dt, W) {
        var s = polVi, any = false;
        var scale = (s.farSize + (s.nearSize - s.farSize) * s.near) / 19 * s.size;
        var frame = Math.floor((now - s.clock0) * 30 / 1000) % POL_PICTURE.length;
        if (s.mode === 'radius' || s.mode === 'custom') {
            var o = polOpacity(0, now);
            if (o < 0.003) return s.to[0] > 0;
            s.rel += polNormalise(s.relTarget - s.rel) * Math.min(1, dt * 8);
            polRow(ctx, polPerimeter(s.rel, W), polNormal(s.rel), scale, o, frame);
            return true;
        }
        for (var i = 0; i < 4; i++) {
            var oi = polOpacity(i, now);
            if (s.to[i] > 0) any = true;
            if (oi < 0.003) continue;
            any = true;
            polRow(ctx, polPerimeter(POL_EDGE_ANGLE[i], W), polNormal(POL_EDGE_ANGLE[i]), scale, oi,
                (frame + i * POL_PICTURE.length / 4) % POL_PICTURE.length);
        }
        return any;
    }

    function polDrawArrow(ctx, dt, W) {
        var s = polVi;
        var show = s.arrowSeen && !s.arrowBeside;
        if (show && s.arrowA <= 0) { s.arrowRel = s.arrowRelTarget; s.arrowFill = s.arrowFillTarget; }
        s.arrowA = polClamp01(s.arrowA + (show ? dt * 1000 / 420 : -dt / 0.3));
        if (s.arrowA <= 0.003) return show;
        s.arrowRel += polNormalise(s.arrowRelTarget - s.arrowRel) * Math.min(1, dt * 8);
        s.arrowFill += (s.arrowFillTarget - s.arrowFill) * Math.min(1, dt * 4);

        // In radius mode the arrow follows the row's own smoothed bearing so
        // the two never disagree about where the car is.
        var rel = (s.mode !== 'edges' && s.relSet && s.shape !== 'wide') ? s.rel : s.arrowRel;
        var r = rel * Math.PI / 180, dx = -Math.sin(r), dy = -Math.cos(r);
        // A 190-unit arc whose middle sits 427.68 out from the screen's centre.
        var cx = W / 2 + 237.68 * dx, cy = 540 + 237.68 * dy;
        var alpha = polBezier(0.25, 0.1, 0.25, 1, s.arrowA);
        var fill = polClamp01(s.arrowFill);
        var half = 26 / 95, base = Math.atan2(dy, dx), steps = 86, step = 1 / steps;

        // The line: tapered dots, blue spreading out from the point as the
        // police close in.
        for (var i = 0; i <= steps; i++) {
            var u = i * step, e = Math.abs(2 * u - 1);
            var thick = 3.2 * Math.pow(polClamp01((1 - e) / 0.25), 0.7);
            if (thick < 0.6) continue;
            var ang = base + (u - 0.5) * 2 * half;
            var c = polLerpColor(polClamp01((fill - e) / (2 * step) + 0.5));
            ctx.globalAlpha = c[3] / 255 * alpha;
            ctx.fillStyle = 'rgb(' + c[0] + ',' + c[1] + ',' + c[2] + ')';
            ctx.beginPath();
            ctx.arc(cx + 190 * Math.cos(ang), cy + 190 * Math.sin(ang), thick / 2, 0, Math.PI * 2);
            ctx.fill();
        }

        // The point, one of 64 pictures facing the car.
        if (s.tips.complete && s.tips.naturalWidth) {
            var idx = ((Math.round(Math.atan2(dx, -dy) / (Math.PI * 2) * 64) % 64) + 64) % 64;
            var tc = polLerpColor(polClamp01(fill / 0.05));
            var img = polTinted(s.tips, (idx % POL_TIP_COLS) * POL_TIP, Math.floor(idx / POL_TIP_COLS) * POL_TIP,
                POL_TIP, POL_TIP, tc, 'tip' + idx + ':' + tc.join(','));
            ctx.globalAlpha = tc[3] / 255 * alpha;
            ctx.drawImage(img, cx + 191 * dx - POL_TIP / 2, cy + 191 * dy - POL_TIP / 2, POL_TIP, POL_TIP);
        }
        ctx.globalAlpha = 1;
        return true;
    }

    function polViFrame() {
        var s = polVi, canvas = $('police-vi'), ctx = s.ctx;
        if (!canvas || !ctx) { s.running = false; return; }
        var now = polNow();
        var dt = Math.min(0.1, Math.max(0, (now - s.last) / 1000));
        s.last = now;

        var w = window.innerWidth || 1920, h = window.innerHeight || 1080;
        if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, w, h);
        var k = h / 1080, W = 1080 * w / h;
        ctx.setTransform(k, 0, 0, k, 0, 0);

        s.near += (s.nearTarget - s.near) * Math.min(1, dt * 4);
        var busy = false;
        // Size 0 is the GTA VI row switched off; the arrow below is separate.
        if (s.shape !== 'wide' && s.size > 0) busy = polDrawRound(ctx, now, dt, W) || busy;
        if (s.arrowOn) busy = polDrawArrow(ctx, dt, W) || busy;

        if (busy) { raf(polViFrame); return; }
        // Nothing left on screen and nothing on its way: stop until the next
        // siren rather than clearing an empty canvas 60 times a second.
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, w, h);
        s.running = false;
    }

    /* --- police light editor (/hudpolice edit) ----------------------------- */
    /* One decimal for the small fractional sliders, whole numbers for
       everything else — matches what each range's step actually produces. */
    var POL_ED_DEC = { sweepAmt: 1, focus: 1 };

    var POL_ED_PCT = { customRx: 1, customRy: 1, customBx: 1, customBy: 1, customWx: 1, customWy: 1 };

    function polEdFormat(k, v) {
        if (k === 'flashMs' || k === 'sweepMs') return Math.round(v) + 'ms';
        if (k === 'maxOpacity' || k === 'whiteA') return Math.round(v * 100) + '%';
        if (k === 'maxDistance' || k === 'fullDistance') return Math.round(v) + 'm';
        if (k === 'previewAngle') return Math.round(v) + '°';
        if (k === 'size') return v <= 0 ? 'Off' : Math.round(v) + '%';
        if (POL_ED_PCT[k]) return Math.round(v) + '%';
        var dec = POL_ED_DEC[k] != null ? POL_ED_DEC[k] : 0;
        return v.toFixed(dec);
    }

    // Rows that only make sense in one mode. Everything else (brightness,
    // lamp shape, movement, detection) shapes all three modes identically, so
    // it stays visible no matter which is picked.
    var POL_MODE_ONLY = { radius: 'pol-ed-radius-only', custom: 'pol-ed-custom-only' };

    function setPoliceEditorMode(mode) {
        document.querySelectorAll('.pol-mode-btn').forEach(function (btn) {
            btn.classList.toggle('active', btn.getAttribute('data-mode') === mode);
        });
        Object.keys(POL_MODE_ONLY).forEach(function (m) {
            var cls = POL_MODE_ONLY[m];
            document.querySelectorAll('.' + cls).forEach(function (el) {
                el.style.display = (mode === m) ? '' : 'none';
            });
        });
    }

    // The size slider only shapes the GTA VI row; the lamp sliders only the
    // classic lamps -- but those stay visible, since the white flash and
    // brightness rows shape both.
    function setPoliceEditorShape(shape) {
        document.querySelectorAll('.pol-shape-btn').forEach(function (btn) {
            btn.classList.toggle('active', btn.getAttribute('data-shape') === shape);
        });
        document.querySelectorAll('.pol-ed-round-only').forEach(function (el) {
            el.style.display = shape === 'wide' ? 'none' : '';
        });
    }

    function onPoliceEditor(d) {
        var panel = $('police-editor');
        if (!panel) return;
        show(panel, !!d.open);
        if (!d.open) return;
        var values = d.values || {};
        document.querySelectorAll('#pol-ed-body .pol-ed-row[data-k]').forEach(function (row) {
            var k = row.getAttribute('data-k');
            var input = row.querySelector('input');
            var out = row.querySelector('.pol-ed-val');
            var v = k === 'previewAngle' ? d.previewAngle : values[k];
            if (!input || v == null) return;
            input.value = String(v);
            if (out) out.textContent = polEdFormat(k, +v);
        });
        var white = $('pol-ed-white');
        if (white) white.checked = values.white !== false;
        var arrow = $('pol-ed-arrow');
        if (arrow) arrow.checked = values.arrow !== false;
        setPoliceEditorShape(values.shape === 'wide' ? 'wide' : 'round');
        setPoliceEditorMode(values.mode === 'radius' || values.mode === 'custom' ? values.mode : 'edges');
    }

    document.addEventListener('DOMContentLoaded', function () {
        document.querySelectorAll('#pol-ed-body .pol-ed-row[data-k]').forEach(function (row) {
            var k = row.getAttribute('data-k');
            var input = row.querySelector('input');
            var out = row.querySelector('.pol-ed-val');
            if (!input) return;
            input.addEventListener('input', function () {
                var v = +input.value;
                // The row is either off (0) or 60-140%: nothing in between.
                if (k === 'size' && v > 0 && v < 60) { v = v < 30 ? 0 : 60; input.value = String(v); }
                if (out) out.textContent = polEdFormat(k, v);
                // previewAngle is a testing aid, not a saved setting — it has
                // its own endpoint so it never ends up written to the KVP.
                if (k === 'previewAngle') post('policePreviewAngle', { angle: v });
                else post('policeTune', { key: k, value: v });
            });
        });
        var whiteBox = $('pol-ed-white');
        if (whiteBox) whiteBox.addEventListener('change', function () {
            post('policeTune', { key: 'white', value: whiteBox.checked });
        });
        var arrowBox = $('pol-ed-arrow');
        if (arrowBox) arrowBox.addEventListener('change', function () {
            post('policeTune', { key: 'arrow', value: arrowBox.checked });
        });
        document.querySelectorAll('.pol-shape-btn').forEach(function (btn) {
            btn.addEventListener('click', function () {
                var shape = btn.getAttribute('data-shape');
                setPoliceEditorShape(shape);
                post('policeTune', { key: 'shape', value: shape });
            });
        });
        document.querySelectorAll('.pol-mode-btn').forEach(function (btn) {
            btn.addEventListener('click', function () {
                var mode = btn.getAttribute('data-mode');
                setPoliceEditorMode(mode);
                post('policeMode', { mode: mode });
            });
        });
        var b;
        if ((b = $('pol-ed-reset'))) b.addEventListener('click', function () {
            post('policeReset', {}, function (values) { onPoliceEditor({ open: true, values: values }); });
        });
        if ((b = $('pol-ed-close'))) b.addEventListener('click', function () {
            post('policeEditorClose', {});
            show($('police-editor'), false);
        });
    });

    /* --- exhaustion vignette ---------------------------------------------- */

    function onExhaustion(d) {
        var el = $('exhaust');
        if (!el) return;
        var lvl = Math.max(0, Math.min(1, d.level || 0));
        el.style.opacity = String(Math.max(0, Math.min(1, d.vignette || 0)));
        if (d.pulseMs) el.style.setProperty('--exhaust-pulse', d.pulseMs + 'ms');

        // Close the aperture as exhaustion climbs — the clear centre shrinks
        // from 74%/68% down to 40%/34%, so the edges visibly creep inward
        // rather than the screen merely getting darker.
        el.style.setProperty('--exhaust-w', (74 - 34 * lvl).toFixed(1) + '%');
        el.style.setProperty('--exhaust-h', (68 - 34 * lvl).toFixed(1) + '%');

        // Only breathe once genuinely winded, so a light jog doesn't throb.
        el.classList.toggle('breathing', lvl > 0.55);
        // Past the point of no return it starts costing health — a harder,
        // faster pulse marks that threshold so it isn't a silent penalty.
        el.classList.toggle('critical', lvl >= 0.995);
    }

    /* --- offset preference ----------------------------------------------- */

    function onOffset(d) {
        if (stage) stage.style.setProperty('--hud-offset-x', (d.x || 0) + 'px');
    }

    /* --- HUD editor offsets ------------------------------------------------ */

    function onLayout(d) {
        if (!stage || !d.offsets) return;
        offsets = asOffsetMap(d.offsets);
        // Must go through applyOffsets: an earlier version wrote only the two
        // --off-* translation vars here, so every saved SCALE was dropped the
        // moment Lua pushed the layout back (which it does on save, on reset
        // and on resource start). That made scaling look like it did nothing.
        applyOffsets(true);
    }

    /* --- HUD editor -------------------------------------------------------- */

    /* [key, label, selector, description, group]
       `group` only drives the headings in the list. Grouping matters here
       because the three kinds behave differently and used to be shuffled
       together: page elements are pure CSS, the minimap rows are forwarded to
       the engine, and the last two live in other resources entirely. */
    var EDITOR_ELEMENTS = [
        ['status',   'Status bars',    '#status',    'health / stamina, top-left',      'HUD'],
        ['topright', 'Wanted stars',   '#topright',  'stars (also moves ammo/tells/money together)', 'HUD'],
        ['tells',    'Wanted tells',   '#tells',     'the six round tell icons',       'HUD'],
        // Its own row, separate from the wanted stars above. It previously
        // shared #topright's position (and its Font/Icon size rows), which
        // meant nudging the ammo readout also nudged the stars.
        ['ammo',     'Ammo',           '#ammo-wrap', 'clip/reserve numbers + weapon icon', 'HUD'],
        ['money',    'Money',          '#money',     'cash and bank',                   'HUD'],
        ['moneypop', 'Money +/- popup', '#money-pop', 'centre-screen change indicator', 'HUD'],
        ['slots',    'Map panels',     '#slots',     'both panels together',            'HUD'],
        /* The two panels are separate elements as well as being movable
           together. They are different kinds of text — a place name that can be
           long, and a make/model set in wide caps — and sharing one font, size
           and weight meant tuning either one to fit wrecked the other. `slots`
           still moves and scales the pair. */
        ['vehicle',  'Vehicle panel',  '#vehicle',   'make + model (upper panel)',      'HUD'],
        ['zone',     'Zone bar',       '#zone',      'place name (lower panel)',        'HUD'],
        // The pip row is its own element rather than something the vehicle
        // panel scales. Scaling it from the panel grew the three discs and left
        // the gap between them alone, which is the "wonky" — the icons need
        // their own spacing, position and scale to stay a proportionate row.
        ['vehpips',  'Vehicle icons',  '#veh-pips',  'tracker / engine / fuel / nitrous pips', 'HUD'],
        /* The manufacturer badge is its own element for the same reason the pip
           row is: it is behind the names rather than part of them, and the two
           things people will want from it — how big it is and how strongly it
           shows — are settings the panel itself has no row for. Opacity
           multiplies the shipped 0.42, so 1.00 is the design as drawn and
           anything below it fades the mark back. */
        ['vehlogo',  'Vehicle badge',  '#veh-logo',  'manufacturer mark behind the names', 'HUD'],
        ['wanted',   'Wanted box',     '#wanted',    '"cops are searching for you"',    'HUD'],
        ['honor',    'Honor standing', '#honor',     'mugshot + current honor face',    'HUD'],
        ['honorpop', 'Honor +/- popup', '#honor-pop', 'centre-screen change indicator', 'HUD'],
        ['reputation',    'Reputation standing', '#reputation',     'icon + current track value', 'HUD'],
        ['reputationpop', 'Reputation +N popup', '#reputation-pop', 'centre-screen change indicator', 'HUD'],
        ['prompts',  'Action prompts', '#prompts',   'bottom-right prompts',            'HUD'],
        ['skillup',  'Skill level-up', '#skillup',   'the card shown when a skill levels', 'HUD'],
        // No box of its own -- a full-screen vignette, not a positioned
        // panel -- so Position/Width/Height/Font rows are dropped for it in
        // NO_ROWS below and all it offers are its three custom rows.
        ['focusfx',  'Focus screen effect', '#focus-fx', 'vignette + pulse while Focus is active', 'HUD'],
        // The native minimap is drawn by the ENGINE, not this page — arrows are
        // forwarded to Lua, which re-applies SetMinimapComponentPosition and
        // rebuilds the scaleform. The frame is ours, but it belongs beside them.
        ['mapframe',    'Minimap frame',    '#map-frame', 'outline around the map',            'Minimap'],
        // Purely decorative -- no game state toggles it -- so unlike every
        // other row here it has nothing driving it besides the editor.
        ['mapbadge',    'Map badge',        '#map-badge', 'glyph in the map\'s top-left corner', 'Minimap'],
        // Own row rather than riding on mapframe: it is a text bar, not an
        // outline, and only ever shows while a waypoint is set — Reset/Save
        // still has to reach it even when nobody happens to have one right now.
        ['navpopup',    'Nav popup',        '#nav-popup', 'turn-by-turn bar shown above the map near a turn', 'Minimap'],
        ['navcompass',  'Nav distance',     '#nav-compass', 'the remaining-distance figure on the map', 'Minimap'],
        ['minimap',     'Minimap position', null, 'arrows move the native map',                'Minimap'],
        ['minimapsize', 'Minimap size',     null, 'left/right = width, up/down = height',      'Minimap'],
        // These live in OTHER resources (speedlimits / zseatbelt), each with its
        // own NUI page — CSS can't reach across, so vice_hud stores the offset
        // and those resources apply it to their own page.
        ['speedlimit', 'Speed limit sign', null, 'from the speedlimits resource', 'Other resources'],
        ['seatbelt',   'Seatbelt icon',    null, 'from the zseatbelt resource',   'Other resources'],
        // Notifications are drawn on ox_lib's OWN page, which this page cannot
        // reach with CSS. The values go to Lua, which puts them in a state bag
        // that a hook inside ox_lib reads — so one row here moves the popups of
        // every resource on the server at once.
        ['notify',     'Notifications',    null, 'ox_lib popups, from every resource', 'Other resources']
    ];

    // Elements the engine owns; nudges go to Lua rather than to CSS.
    var NATIVE_ELEMENTS = { minimap: 'move', minimapsize: 'size' };

    // Elements another resource draws, tuned by corner + nudge rather than CSS.
    var NOTIFY_ELEMENTS = { notify: 1 };

    /* Everything tunable per element. Each writes one CSS custom property on
       .stage; style.css reads it with the ORIGINAL value as the var() fallback,
       so an unset property renders exactly as designed. `def: null` means
       "leave the stylesheet alone" rather than a number. */
    /* The first four are SHIPPED with the resource, so they render the same for
       every player. The rest are whatever the player's OS provides and will
       differ machine to machine — fine for a personal tweak, a poor choice for
       anything you intend to /hudpublish. */
    var FONTS = [
        [null,                                    'Default'],
        ["'HelveticaNeueHUD', 'Helvetica Neue', sans-serif", 'Helvetica'],
        ["'GTAArtDeco', 'HelveticaNeueHUD', sans-serif",     'GTA Art Deco'],
        ["'Pricedown', sans-serif",               'Pricedown'],
        ['system-ui, sans-serif',                 'System'],
        ['Arial, Helvetica, sans-serif',          'Arial'],
        ["'Segoe UI', system-ui, sans-serif",     'Segoe UI'],
        ['Verdana, Geneva, sans-serif',           'Verdana'],
        ["'Trebuchet MS', system-ui, sans-serif", 'Trebuchet'],
        ["'Franklin Gothic Medium', Arial, sans-serif", 'Franklin Gothic'],
        ['Impact, Haettenschweiler, sans-serif',  'Impact'],
        ['Georgia, "Times New Roman", serif',     'Georgia'],
        ['Consolas, "Courier New", monospace',    'Monospace']
    ];
    /* Weight is only honest where a REAL cut exists. Thin (100/200), Roman
       (400), Medium (500) and Bold (700) are installed in html/fonts; anything
       else is synthesised, and a synthesised light in particular is the ragged,
       pixelated-looking text people blame on the screen. Art Deco has Regular
       and Medium, so 400 and 500+ are real there too.
       Add a weight here only alongside a real .otf/.ttf and an @font-face. */
    var WEIGHTS = [
        [null, 'Default'],
        [100, '100 Thin'],
        [200, '200 Thin'],
        [400, '400 Roman'],
        [500, '500 Medium'],
        [700, '700 Bold']
    ];

    /* Text alignment. The stored value is the text-align keyword; style.css
       also wants a flex keyword for the same intent, and FLEX_ALIGN is the
       translation. Both are written in applyOffsets — see the note there. */
    var ALIGN = [
        [null,     'Default'],
        ['left',   'Left'],
        ['center', 'Center'],
        ['right',  'Right']
    ];
    var FLEX_ALIGN = { left: 'flex-start', center: 'center', right: 'flex-end' };

    /* How glyph edges are rasterised. Hardcoded to `antialiased` for the whole
       page before this; which setting looks best depends on the display, so it
       is the player's call rather than the stylesheet's. */
    var SMOOTHING = [
        [null,          'Default'],
        ['auto',        'Subpixel'],
        ['antialiased', 'Grayscale'],
        ['none',        'Hard edges']
    ];

    /* About min / max.
       These are GUARD RAILS, not opinions. Every one of them used to be a taste
       judgement, and taste judgements in a tuning tool are just walls: Width
       stopped at 3.0, which is not enough to fit the minimap frame onto a map
       that has itself been scaled up, and there was nothing inside the editor
       that could get past it.

       So anything that is a matter of taste now runs far past any plausible
       use, and what is left is the point where the element stops existing in a
       recoverable way — a scale of zero collapses it to nothing, an offset of
       five screens puts it somewhere you cannot see to drag it back.

       The one real exception is Opacity: CSS clamps it to 1 itself, so a bigger
       number here would be a control that silently does nothing.

       The ceilings matter less than this, though: every numeric row can now be
       TYPED into. Stepping to 12.0 at 0.05 a click was never going to happen. */
    var SC_MIN = 0.01, SC_MAX = 50;

    var PROPS = [
        { k: 'fs',  label: 'Font size',      v: '--fs-',    def: 1,    step: 0.05,  min: 0.02, max: 50,  dec: 2 },
        { k: 'ic',  label: 'Icon size',      v: '--ic-',    def: 1,    step: 0.05,  min: 0.02, max: 50,  dec: 2,
          hint: 'Changes the icons’ real SIZE, so the panel around them grows to '
              + 'fit. Prefer this over Width/Height for making icons bigger — '
              + 'Width/Height only scales how they are PAINTED.' },
        { k: 'ff',  label: 'Font',           v: '--ff-',    def: null, list: FONTS },
        { k: 'fw',  label: 'Font weight',    v: '--fw-',    def: null, list: WEIGHTS },
        { k: 'sm',  label: 'Font smoothing', v: '--sm-',    def: null, list: SMOOTHING,
          hint: 'How glyph edges are rasterised. If text looks rough, try each — '
              + 'which one wins depends on your display.' },
        { k: 'ls',  label: 'Letter spacing', v: '--ls-',    def: 0,    step: 0.005, min: -2,   max: 10,  dec: 3, unit: 'em' },
        { k: 'al',  label: 'Text align',    v: '--al-',    def: null, list: ALIGN },
        /* A CSS transform, which means it changes how the element is PAINTED and
           not the box it occupies. Nothing around it moves out of the way, and
           an ancestor that clips (the map panels do -- .slot sets
           overflow: hidden so a child's square corners cannot escape the
           plate's rounded ones) will cut off whatever now paints outside it.
           That is not a bug to fix here: scaling in place is exactly what these
           two are for. It IS worth saying on the row, because "Width" and
           "Icon size" both read as "make it bigger" and only one of them makes
           room for the result. */
        { k: 'sx',  label: 'Width',          v: '--sc-',    def: 1,    step: 0.05,  min: SC_MIN, max: SC_MAX, dec: 2, suffix: '-x',
          hint: 'Scales how the element is PAINTED, in place — the space it takes '
              + 'up does not change. To make something bigger AND push its '
              + 'neighbours out of the way, use Font size or Icon size instead.' },
        { k: 'sy',  label: 'Height',         v: '--sc-',    def: 1,    step: 0.05,  min: SC_MIN, max: SC_MAX, dec: 2, suffix: '-y',
          hint: 'Scales how the element is PAINTED, in place — the space it takes '
              + 'up does not change. To make something bigger AND push its '
              + 'neighbours out of the way, use Font size or Icon size instead.' },
        { k: 'op',  label: 'Opacity',        v: '--op-',    def: 1,    step: 0.05,  min: 0,    max: 1,   dec: 2 },
        { k: 'rad', label: 'Corner radius',  v: '--rad-',   def: 1,    step: 0.1,   min: 0,    max: 100, dec: 2 },
        /* Multiplier on the gap between an element's own children. Size alone
           could never produce a proportionate stack: scale the icons up and the
           spacing between them stayed where it was, so the row read as crowded
           however good the icon size was. */
        { k: 'sp',  label: 'Spacing',        v: '--sp-',    def: 1,    step: 0.05,  min: 0,    max: 50,  dec: 2,
          hint: 'Multiplies the gap between this element’s own children. '
              + 'Scaling icons without it is what makes a row look crowded.' },

        /* ---- the panel stack's own geometry --------------------------------
           `only: { slots: 1 }` — these are offered on Map panels and nowhere
           else. `panel: true` keeps them out of the CSS-writing loop in
           applyOffsets: everything else there writes one custom property from
           its own `v` prefix, while these three are applied together by
           applyPanelRect, which has to weigh them against the map rect and the
           snapshot before it can know what to write.

           Unset means "use the snapshot" rather than a number, which is why
           `def` is null on all four. A default of, say, 1.75 would be a lie the
           moment anyone moved their minimap. */
        { k: 'pl',  label: 'Panel left',   def: null, step: 0.25, min: -500, max: 500, dec: 2, panel: true, only: { slots: 1 },
          hint: 'Left edge of the two map panels, in % of screen width. '
              + 'Unset follows the minimap as it was when you spawned.' },
        { k: 'pw',  label: 'Panel width',  def: null, step: 0.25, min: 0.01, max: 500, dec: 2, panel: true, only: { slots: 1 },
          hint: 'Width of the two map panels, in % of screen width. '
              + 'Set this and resizing the minimap will not touch them.' },
        { k: 'pb',  label: 'Panel bottom', def: null, step: 0.25, min: -500, max: 500, dec: 2, panel: true, only: { slots: 1 },
          hint: 'Distance from the bottom of the screen to the BOTTOM of the '
              + 'panel stack, in % of screen height. The stack grows upward.' },
        /* The way back to the old behaviour, kept because "sit on the map and
           stay there" and "sit on the map and follow it" are both reasonable
           and only one of them can be the default. Stored as 1/null rather than
           true/false so it round-trips through Lua's json as a number like
           every other value in the layout. */
        { k: 'pfollow', label: 'Follow map', def: null, panel: true, only: { slots: 1 },
          list: [[null, 'No — stay put'], [1, 'Yes — track the map']],
          hint: 'Off: the panels keep the position they had when you spawned, '
              + 'whatever the minimap does afterwards. On: they track the map '
              + 'live, which is what this HUD did before.' },

        /* ---- the on-foot dock -----------------------------------------------
           The three rows above place the panels relative to the MAP. Whenever
           the map itself is not drawn (on foot with /hudminimap off, dead, a
           full inventory, the character switcher — see applyMapChrome's own
           comment), that reference point does not exist, so #slots.map-hidden
           in style.css docks the stack to a fixed bottom-centre spot instead.
           These two rows nudge THAT spot, independent of Position X/Y above
           (which only ever apply while the map is up) — see #off-slots-foot-*
           in style.css. markTarget() previews the dock the moment Map panels
           is the selected row, even though the editor otherwise always forces
           the map visible, or there would be no way to see what you're
           tuning. */
        // def: null / off: 0, not the more obvious def: 1 / off: null --
        // offsetsForSave drops a prop whose value is null OR undefined (its
        // "this wasn't touched, don't bother writing it" rule), so if OFF
        // were spelled null it would silently fail to survive a save/reload:
        // it would read back as undefined, and valueOf() hands undefined
        // straight to `def`. null has to be the shipped DEFAULT's value
        // (matching what "never touched" already resolves to) for the same
        // reason pfollow above is null/1 rather than 1/null -- its default
        // really is "No".
        { k: 'footdock', label: 'Dock on foot', v: '--footdock-', def: null, only: { slots: 1 },
          list: [[null, 'On — bottom centre when map is hidden'], [0, 'Off — stay at Position X/Y']],
          hint: 'Whenever the minimap is not shown, move the zone bar and '
              + 'vehicle panel to their own dock instead of leaving them '
              + 'wherever they sit relative to the now-invisible map. Off '
              + 'restores the old behaviour — they just stay put.' },
        { k: 'footx', label: 'Foot position X', v: '--off-', suffix: '-foot-x', unit: 'cqw',
          // -500/500, not POS_MAX -- POS_MAX (POS_PROPS' own guard rail) is
          // declared further down in the file and would still be undefined
          // at the point this array literal is evaluated. Same numbers,
          // just spelled out (pl/pw/pb above do the same for the same
          // reason).
          def: 0, step: 0.1, min: -500, max: 500, dec: 2, only: { slots: 1 },
          hint: 'Nudges the ON-FOOT dock horizontally — independent of the '
              + 'normal Position X/Y above, which only applies while the map '
              + 'is up.' },
        { k: 'footy', label: 'Foot position Y', v: '--off-', suffix: '-foot-y', unit: 'cqh',
          def: 0, step: 0.1, min: -500, max: 500, dec: 2, only: { slots: 1 },
          hint: 'Nudges the ON-FOOT dock vertically — independent of the '
              + 'normal Position X/Y above, which only applies while the map '
              + 'is up.' },

        /* ---- the focus vignette's own tuning -------------------------------
           `only: { focusfx: 1 }` — same opt-in pattern as the panel trio
           above. Position/scale/font rows mean nothing for a full-screen
           effect with no box, so those are dropped for this element in
           NO_ROWS instead of offered and doing nothing. */
        { k: 'fxstrength', label: 'Vignette strength', v: '--fxstrength-', def: 1, step: 0.1, min: 0, max: 3, dec: 2, only: { focusfx: 1 },
          hint: 'Multiplies how dark and how far the vignette reaches. 1.00 is '
              + 'shipped strength; 0 turns the vignette itself off while the '
              + 'pulse and bar keep working.' },
        { k: 'fxpulse', label: 'Pulse size', v: '--fxpulse-', def: 1, step: 0.1, min: 0, max: 4, dec: 2, only: { focusfx: 1 },
          hint: 'Multiplies the pulse\'s brightness swing AND how much it visibly '
              + 'grows each beat. 0 is a flat, non-pulsing vignette.' },
        { k: 'fxspeed', label: 'Pulse speed', v: '--fxspeed-', def: 1100, step: 50, min: 200, max: 4000, dec: 0, unit: 'ms', only: { focusfx: 1 },
          hint: 'How long one pulse takes, in milliseconds. Lower is faster.' },

        /* ---- the nav bar's own tuning --------------------------------------
           `only: { navpopup: 1 }`, same opt-in as the two groups above.

           Bar height is its own row because the nav bar is built off a single
           --nav-h: the bar, the square turn tile and the type all size off
           it, so this is the one control that grows the whole bar as a unit.
           The generic Width/Height rows only scale how it is PAINTED and
           would squash the tile out of square. */
        { k: 'navbar', label: 'Bar height', v: '--sc-navbar', def: 1, step: 0.05, min: 0.2, max: 4, dec: 2, only: { navpopup: 1 }, raw: true,
          hint: 'Grows the whole nav bar as a unit — height, the turn tile and '
              + 'the text together. Use this rather than Width/Height, which '
              + 'only rescale how it is painted.' },
        { k: 'navaccent', label: 'Turn tile colour', v: '--nav-accent', def: null, only: { navpopup: 1 }, raw: true,
          list: [[null, 'Default — mint'], ['#6fd5c3', 'Mint'], ['#57c8f5', 'Sky'],
                 ['#f5c451', 'Amber'], ['#f2795f', 'Coral'], ['#b48cf0', 'Violet'],
                 ['#8bd45f', 'Lime'], ['#ffffff', 'White']],
          hint: 'The colour of the square turn tile at the right of the bar.' },
        { k: 'navbg', label: 'Bar colour', v: '--nav-bg', def: null, only: { navpopup: 1 }, raw: true,
          list: [[null, 'Default — charcoal'], ['rgba(35,37,46,0.95)', 'Charcoal'],
                 ['rgba(18,19,24,0.95)', 'Near black'], ['rgba(24,32,48,0.95)', 'Navy'],
                 ['rgba(40,32,48,0.95)', 'Plum'], ['rgba(0,0,0,0.72)', 'Translucent']],
          hint: 'The dark bar behind the instruction text.' }
    ];
    /* Position was arrow-keys-only, which made it the one thing you could not
       do with the mouse and the one thing with no readable current value in the
       settings column. It is the same offsets[key].x / .y the arrows write, so
       the two stay in step automatically. Kept out of PROPS because PROPS is
       also the loop that writes CSS custom properties, and x/y are applied as
       the translate instead. */
    var POS_MAX = 500;
    var POS_PROPS = [
        { k: 'x', label: 'Position X', def: 0, step: 0.1, min: -POS_MAX, max: POS_MAX, dec: 2, pos: true },
        { k: 'y', label: 'Position Y', def: 0, step: 0.1, min: -POS_MAX, max: POS_MAX, dec: 2, pos: true }
    ];

    var propSel = 0;

    /* The minimap is drawn by the ENGINE, so none of the CSS properties above
       apply to it. It gets its own list instead, sent up from client.lua with
       real current values. Everything here used to be reachable only through
       chat commands, which put the fiddliest part of the HUD outside the tool
       built for fiddling. */
    var NATIVE_PROPS = [
        { k: 'cropT',  label: 'Crop top',    step: 5,    min: 0,     max: 2000,  dec: 0 },
        { k: 'cropB',  label: 'Crop bottom', step: 5,    min: 0,     max: 2000,  dec: 0 },
        { k: 'cropL',  label: 'Crop left',   step: 5,    min: 0,     max: 2000,  dec: 0 },
        { k: 'cropR',  label: 'Crop right',  step: 5,    min: 0,     max: 2000,  dec: 0 },
        { k: 'blipX',  label: 'Blip X',      step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'Moves the map PLANE inside its window. Use it to centre the player arrow.' },
        { k: 'blipY',  label: 'Blip Y',      step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'Moves the map PLANE inside its window. Use it to centre the player arrow.' },
        { k: 'scaleW', label: 'Map width',   step: 0.02, min: 0.01,  max: 20,    dec: 3,
          hint: 'Scales the map, its mask and its blur TOGETHER. This is "make the minimap bigger".' },
        { k: 'scaleH', label: 'Map height',  step: 0.02, min: 0.01,  max: 20,    dec: 3,
          hint: 'Scales the map, its mask and its blur TOGETHER. This is "make the minimap bigger".' },
        /* The plane on its own. Map width / height above scale the map, mask
           and blur as one, so they cannot change the plane's ASPECT relative to
           its window — and a plane with the wrong aspect is what draws a radius
           blip's circle as an oval. These two are the only control that can.
           Long-standing values (/hudblip size), persisted and printed by
           /mapinfo, that simply had no row here. */
        { k: 'blipW',  label: 'Plane width', step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'Stretches the map plane ONLY, leaving the mask window where it is. '
              + 'This is what makes a squashed radius circle round again.' },
        { k: 'blipH',  label: 'Plane height',step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'Stretches the map plane ONLY, leaving the mask window where it is. '
              + 'This is what makes a squashed radius circle round again.' },
        /* The blur component. It had no rows at all, which made it the one part
           of the minimap you could not touch — and on the shipped config it is
           1.6x the size of the map component, a ratio every scale preserves
           because all three are multiplied together. When the drawn map turns
           out to fill the BLUR rect while blips clip to the MAP rect, closing
           that gap is the fix and this is the only way to do it. /hudrects
           shows which rect the map is actually sitting on; /hudmatch does the
           arithmetic. */
        { k: 'blurX',  label: 'Blur X',      step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'The minimap_blur component. Run /hudrects — if the drawn map '
              + 'fills the YELLOW outline rather than the green one, this is the '
              + 'rect that is really deciding how big the map looks.' },
        { k: 'blurY',  label: 'Blur Y',      step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'The minimap_blur component. See Blur X.' },
        { k: 'blurW',  label: 'Blur width',  step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'The minimap_blur component. See Blur X.' },
        { k: 'blurH',  label: 'Blur height', step: 4,    min: -5000, max: 5000,  dec: 0,
          hint: 'The minimap_blur component. See Blur X.' },
        /* Not a 2D/3D switch, and deliberately not labelled as one. GTA draws
           the radar as a tilted plane in its own renderer; nothing reachable
           from here flattens that. Zoom changes how MUCH of the plane you see,
           which is what actually decides whether it reads flat or skewed. */
        /* Vanilla map information. These are not vice_hud drawing something of
           its own — they are GTA's own map furniture, which this resource was
           suppressing with no setting behind it. */
        { k: 'north',  label: 'North marker', step: 1,   min: 0,     max: 1,     dec: 0,
          names: ['hidden', 'shown'],
          hint: 'GTA’s north indicator on the map edge. vice_hud used to hide it '
              + 'unconditionally; vanilla shows it.' },
        { k: 'blipScale', label: 'Player arrow', step: 0.05, min: 0, max: 8,     dec: 2,
          hint: 'Size of your own blip. 0 leaves GTA’s alone. The arrow does NOT '
              + 'scale with the map, so a resized minimap needs this to keep the '
              + 'proportion vanilla had.' },
        { k: 'zoom',   label: 'Radar zoom',  step: 25,   min: 0,     max: 1500,  dec: 0,
          hint: 'How far the radar is zoomed in. 0 leaves GTA’s own zoom alone. '
              + 'Pulled in you see the flat middle of the map; pulled out you see '
              + 'its steeply-angled far edge, which is what reads as "3D".' },
        { k: 'nudgeX', label: 'Map X',       step: 4,    min: -20000, max: 20000, dec: 0 },
        { k: 'nudgeY', label: 'Map Y',       step: 4,    min: -20000, max: 20000, dec: 0 },
        { k: 'rectL',  label: 'Panel left',  step: 0.25, min: -500,  max: 500,   dec: 2 },
        { k: 'rectW',  label: 'Panel width', step: 0.25, min: 0.01,  max: 500,   dec: 2 },
        { k: 'rectB',  label: 'Panel bottom',step: 0.25, min: -500,  max: 500,   dec: 2 },
        { k: 'rectH',  label: 'Panel height',step: 0.25, min: 0.01,  max: 500,   dec: 2 },
        // Corner radius, as a percentage of the mask's height.
        //
        // Stepped rather than continuous because the rounding lives in the mask
        // TEXTURE and the engine cannot build one at runtime -- each step is a
        // pre-baked file in stream/ (see tools/make_masks.py). Lua snaps
        // whatever it is sent to the nearest baked step and reports the snapped
        // value back, so this row always shows a radius that really exists.
        { k: 'radius',   label: 'Corner radius',   step: 4, min: 0, max: 50, dec: 0,
          unitLabel: '%' },
        // Toggles, stepped like numbers so one control type covers everything.
        // 'Custom mask' off means GTA's own square-cornered mask, where the
        // radius above has nothing to act on.
        { k: 'rounded',  label: 'Custom mask',     step: 1, min: 0, max: 1, dec: 0,
          names: ['stock', 'custom'] },
        { k: 'maskMap',  label: 'Mask = map',      step: 1, min: 0, max: 1, dec: 0,
          names: ['qbx crop', 'full map'] },
        /* The same idea as Mask = map, for the component that turns out to
           decide the map's DRAWN size. The arrow and every radius blip are
           drawn on the plane, so a blur that is a different rect puts the arrow
           off centre and stops radius blips at an invisible edge. `follows map`
           recomputes it from the plane on every apply, so resizing later cannot
           pull them apart again. */
        { k: 'blurMap',  label: 'Blur = map',      step: 1, min: 0, max: 1, dec: 0,
          names: ['own rect', 'follows map'],
          hint: 'The blur component decides how big the map is DRAWN, while the '
              + 'arrow and radius blips are drawn on the plane. Following the map '
              + 'keeps them the same rect at every scale.' }
    ];

    // Mirror of the engine-side values, refreshed from every callback reply so
    // the panel can never drift from what the map is actually doing.
    var nativeVals = {};

    /* Notifications get a CORNER plus a nudge, not a free position: ox_lib
       anchors its notification stack to one of eight points and the offset is
       measured from there. Picking the corner first is also what keeps a
       placement sane at every aspect ratio — the corner does the work, the
       nudge is the fine tuning. */
    var NOTIFY_ANCHORS = [
        ['top-left',     'Top left'],
        ['top',          'Top centre'],
        ['top-right',    'Top right'],
        ['center-left',  'Left'],
        ['center-right', 'Right'],
        ['bottom-left',  'Bottom left'],
        ['bottom',       'Bottom centre'],
        ['bottom-right', 'Bottom right']
    ];
    /* def is 'top-right', not null: that is where ox_lib puts notifications
       when nobody has said otherwise, so an unset row should READ as Top right
       rather than as a meaningless "Default" that steps somewhere unrelated. */
    var NOTIFY_PROPS = [
        { k: 'anchor', label: 'Corner', def: 'top-right', list: NOTIFY_ANCHORS }
    ].concat(POS_PROPS);

    /* The speed limit sign and the seatbelt light can be taken off the HUD
       altogether. Both are drawn by their own resources, which read `hide` off
       the layout broadcast the same way they read their position (client.lua,
       isElementHidden); /hudspeedlimit and /hudseatbelt flip the same value.
       1 / null like Follow map, so it round-trips through Lua's json. First in
       those two elements' rows, so it is the first thing you see on them. */
    var HIDEABLE = { speedlimit: 1, seatbelt: 1 };
    var HIDE_PROP = { k: 'hide', label: 'Show on HUD', def: null,
        list: [[null, 'Shown'], [1, 'Hidden']],
        hint: 'Hidden takes it off the HUD altogether. Also /hudspeedlimit and /hudseatbelt.' };

    // Keys that are neither a CSS property nor a position, and so are not in
    // PROPS — but still have to survive the trip to Lua.
    var EXTRA_KEYS = ['anchor', 'hide'];

    /* Money is Pricedown and stays Pricedown — GTA's own display face, and the
       one piece of this HUD whose identity is the typeface. So it gets no Font
       row at all, rather than a row that can be set to something the design
       does not want. Weight, size and the rest are still tunable. */
    var NO_FONT_ROW = { money: 1, moneypop: 1 };

    /* Rows that would be dead controls on a given element. The badge is an
       IMAGE: a font, a weight, letter spacing, text alignment, glyph smoothing
       and a corner radius have nothing to act on, and a row that visibly does
       nothing is worse than no row -- it reads as a bug in the editor. What it
       keeps is what an image actually has: where it sits, how big it is, and
       how strongly it shows. */
    var NO_ROWS = {
        vehlogo: { ff: 1, fw: 1, sm: 1, ls: 1, al: 1, fs: 1, ic: 1, rad: 1, sp: 1 },
        mapbadge: { ff: 1, fw: 1, sm: 1, ls: 1, al: 1, fs: 1, ic: 1, rad: 1, sp: 1 },
        // A full-screen effect has no box: nothing here has a font, a
        // position, or a width/height to speak of. Only the three fx* rows
        // this element actually owns are left standing.
        focusfx: { ff: 1, fw: 1, sm: 1, ls: 1, al: 1, fs: 1, ic: 1, rad: 1, sp: 1,
                    sx: 1, sy: 1, op: 1, x: 1, y: 1 }
    };

    /* ---- inheritance, made explicit ---------------------------------------
       Three elements sit INSIDE the map panel stack and, for a handful of
       properties, style.css reads the child's variable with the PARENT's as the
       fallback:

           font-family: var(--ff-zone, var(--ff-slots, inherit));

       So an untouched Zone bar takes its font from Map panels, and setting the
       Zone bar's own font silently detaches it. That is a good default and it
       was completely invisible: nothing in the editor said the value you were
       looking at came from somewhere else, and the only way back was to guess
       that "Reset this" would re-attach it.

       PARENT_OF/INHERITS name the eleven declarations that actually do this, so
       each of those rows can carry a Follow/Own switch. The list is not a
       guess — it is every `var(--x-child, var(--x-parent` in style.css. If you
       add another such fallback there, add it here too or the row will keep
       detaching silently.

       Follow  -> the stored value is deleted, and CSS falls through to the
                  parent. This is exactly what an untouched element already did.
       Own     -> the value is SEEDED from whatever the row is rendering right
                  now and written explicitly, so switching to Own never changes
                  what you are looking at. It just stops the parent moving it. */
    var INHERITS = {
        zone:    { parent: 'slots', props: { ff: 1, fs: 1, fw: 1, ls: 1 } },
        vehicle: { parent: 'slots', props: { ff: 1, fs: 1, fw: 1, ls: 1 } },
        vehpips: { parent: 'slots', props: { ic: 1, fs: 1 } }
    };

    /* An element's display label, so the Follow tooltip can name the parent it
       is following rather than saying "the parent". */
    function labelOf(key) {
        for (var i = 0; i < EDITOR_ELEMENTS.length; i++) {
            if (EDITOR_ELEMENTS[i][0] === key) return EDITOR_ELEMENTS[i][1];
        }
        return key;
    }

    function inheritsProp(key, pk) {
        var inh = INHERITS[key];
        return !!(inh && inh.props[pk]);
    }

    /* Is this row currently taking its value from the parent? Absence of a
       stored value IS the following state — there is no separate flag, because
       a flag could disagree with the CSS and then one of the two would be
       lying. */
    function isFollowing(key, pk) {
        if (!inheritsProp(key, pk)) return false;
        var o = offsets[key];
        return !o || o[pk] === undefined || o[pk] === null;
    }

    /* What the row shows while it is following: the parent's value if the
       parent has one, otherwise the property's shipped default. */
    function inheritedValue(key, p) {
        var inh = INHERITS[key];
        var po = (inh && offsets[inh.parent]) || {};
        var pv = po[p.k];
        return (pv === undefined || pv === null) ? p.def : pv;
    }

    function setFollow(key, p, follow) {
        offsets[key] = offsets[key] || { x: 0, y: 0 };
        if (follow) {
            delete offsets[key][p.k];
        } else {
            // Seed from what is on screen, so Own is a no-op until you change
            // something. Detaching an element and having it jump at the same
            // moment would make the switch feel like it did two things.
            offsets[key][p.k] = inheritedValue(key, p);
        }
        applyOffsets(); renderEditor();
    }

    // The engine-owned rows already carry their own position and size fields
    // (Map X / Map Y / Map width / Map height), so they do not get POS_PROPS.
    function propsFor(key) {
        if (NATIVE_ELEMENTS[key]) return NATIVE_PROPS;
        if (NOTIFY_ELEMENTS[key]) return NOTIFY_PROPS;
        var list = POS_PROPS.concat(PROPS);
        if (NO_FONT_ROW[key]) list = list.filter(function (p) { return p.k !== 'ff'; });
        // `only` is opt-IN: a prop that carries one is offered on those
        // elements alone. Props without one are offered everywhere, which is
        // every prop but Brand tint.
        list = list.filter(function (p) { return !p.only || p.only[key]; });
        var drop = NO_ROWS[key];
        if (drop) list = list.filter(function (p) { return !drop[p.k]; });
        if (HIDEABLE[key]) list = [HIDE_PROP].concat(list);
        return list;
    }

    function propOf(k) {
        for (var i = 0; i < PROPS.length; i++) if (PROPS[i].k === k) return PROPS[i];
        return null;
    }
    function valueOf(o, p) {
        var raw = o[p.k];
        if (raw === undefined) {
            // sx/sy fall back to the legacy uniform `s`.
            if ((p.k === 'sx' || p.k === 'sy') && o.s != null) return o.s;
            return p.def;
        }
        return raw;
    }
    /* Show a number at its DESIGNED precision when it is sitting on it, and at
       full precision when it is not.
       A flat toFixed(p.dec) was fine while every value came from a step, but a
       typed 1.4375 would have been displayed as "1.44" — and the next time the
       row was read back, that display value is what got committed. The number
       you typed would quietly become a different number. */
    function fmtNum(v, p) {
        if (v == null || !isFinite(v)) return '-';
        var dec = p.dec == null ? 2 : p.dec;
        if (Math.abs(v - +v.toFixed(dec)) < 1e-9) return v.toFixed(dec);
        return String(+v.toFixed(6));
    }

    function labelFor(p, val) {
        if (p.list) {
            for (var i = 0; i < p.list.length; i++) if (p.list[i][0] === val) return p.list[i][1];
            return 'Default';
        }
        if (val == null) return '-';
        return fmtNum(val, p) + (p.unit || '');
    }

    /* Set a property to an ABSOLUTE value, as opposed to bumpProp's relative
       step. This is what the typed fields commit through, and it is deliberately
       the same code path the buttons end up in, so a number reached by typing
       and a number reached by clicking cannot behave differently. */
    function setProp(p, value, key) {
        if (!isFinite(value)) return false;
        var v = Math.max(p.min, Math.min(p.max, value));

        if (NATIVE_ELEMENTS[key]) {
            nativeVals[p.k] = v;                 // optimistic, corrected on reply
            renderProps();
            post('mapTune', { key: p.k, value: v }, function (state) {
                if (state && typeof state === 'object') { nativeVals = state; renderProps(); }
            });
            return true;
        }

        offsets[key] = offsets[key] || { x: 0, y: 0 };
        offsets[key][p.k] = v;
        applyOffsets(); renderEditor();
        return true;
    }

    // An EMPTY Lua table has no way to say whether it is a list or a map, so
    // SendNUIMessage serialises `layout = {}` as a JSON *array*. Editing that
    // array by key (offsets.slots = ...) appears to work in JS, but named
    // properties on an array are dropped by JSON.stringify — so the editor
    // posted `{"offsets":[]}` back and every move and scale was thrown away on
    // save. That hit any player whose layout was still empty, i.e. anyone who
    // had never saved one or had just run /hudreset.
    function asOffsetMap(v) {
        var out = {};
        if (!v || typeof v !== 'object') return out;
        Object.keys(v).forEach(function (k) {
            var o = v[k];
            if (o && typeof o === 'object') out[k] = o;
        });
        return out;
    }

    // Build a plain, fully-populated object to hand back to Lua, rather than
    // shipping the live working copy and hoping its shape survives.
    function offsetsForSave() {
        var out = {};
        Object.keys(offsets).forEach(function (k) {
            var o = offsets[k] || {};
            // `s` is still written so anything reading the old key keeps working;
            // it carries the width scale, which is the uniform one in the common
            // case where the two axes match.
            var e = { x: o.x || 0, y: o.y || 0, sx: scaleX(o), sy: scaleY(o), s: scaleX(o) };
            PROPS.forEach(function (p) {
                if (p.k === 'sx' || p.k === 'sy') return;
                if (o[p.k] !== undefined && o[p.k] !== null) e[p.k] = o[p.k];
            });
            // Without this the notification corner was silently dropped on
            // save: offsetsForSave builds a fresh object from PROPS, and
            // `anchor` is not one of them.
            EXTRA_KEYS.forEach(function (k2) {
                if (o[k2] !== undefined && o[k2] !== null) e[k2] = o[k2];
            });
            out[k] = e;
        });
        return out;
    }

    var editorOpen = false;
    var editorSel = 0;
    var offsets = {};
    var editorPopTimer = null;

    /* The centre indicator is transient by nature — it fires on a change and
       fades. That makes it impossible to position, so while the editor is open
       it is cycled between the + and the - face, on a period shorter than its
       own hide timer so it never disappears. It also shows BOTH states, which
       is what you actually want to see when placing it. */
    /* The level-up card clears itself after four seconds, which makes it
       impossible to position. While the editor is open it is re-fired on a
       period shorter than its own hide timer so it simply stays put — the same
       treatment the honor indicator gets, and for the same reason. */
    var editorSkillTimer = null;

    function editorSkillUpHold(on) {
        if (editorSkillTimer) { clearInterval(editorSkillTimer); editorSkillTimer = null; }
        if (!on) { show($('skillup'), false); return; }
        var beat = function () {
            onSkillUp({ id: 'stamina', label: 'Stamina', level: 42,
                        blurb: 'Sprint further before you redline.' });
        };
        beat();
        editorSkillTimer = setInterval(beat, 3000);
    }

    function editorHonorCycle(on) {
        if (editorPopTimer) { clearInterval(editorPopTimer); editorPopTimer = null; }
        if (!on) { show($('honor-pop'), false); return; }
        var up = false;
        var beat = function () {
            up = !up;
            onHonorPop(up ? 12 : -12, up ? 'icons/honor_good.png' : 'icons/honor_bad.png');
        };
        beat();
        editorPopTimer = setInterval(beat, 1600);
    }

    /* No up/down cycle needed here, unlike honor: reputation only ever moves
       one direction, so re-firing the same "+N" is enough to hold it visible
       while it is being positioned. */
    var editorRepPopTimer = null;

    function editorReputationCycle(on) {
        if (editorRepPopTimer) { clearInterval(editorRepPopTimer); editorRepPopTimer = null; }
        if (!on) { show($('reputation-pop'), false); return; }
        var beat = function () { onReputationPop(15, '\uD83D\uDDE1\uFE0F'); };
        beat();
        editorRepPopTimer = setInterval(beat, 1600);
    }

    /* Scale is per-AXIS. `s` is the legacy uniform value and is still read as
       the fallback, so a layout saved before this existed still loads. */
    function scaleX(o) { return o.sx == null ? (o.s == null ? 1 : o.s) : o.sx; }
    function scaleY(o) { return o.sy == null ? (o.s == null ? 1 : o.s) : o.sy; }

    function applyOffsets(quiet) {
        if (!stage) return;
        EDITOR_ELEMENTS.forEach(function (e) {
            if (!e[2]) return;                 // external, handled over an event
            var o = offsets[e[0]] || { x: 0, y: 0 };
            stage.style.setProperty('--off-' + e[0] + '-x', (o.x || 0) + 'cqw');
            stage.style.setProperty('--off-' + e[0] + '-y', (o.y || 0) + 'cqh');
            PROPS.forEach(function (p) {
                // Same opt-in as propsFor. Without it a Brand tint left in a
                // hand-edited layout.json would write --tint-money, which
                // nothing reads but which isModified would still light a dot
                // for — a change you could see and not find a row to undo.
                if (p.only && !p.only[e[0]]) return;
                // Applied by applyPanelRect, not here: these three have to be
                // weighed against the map rect and the snapshot before anything
                // can be written, which this loop has no way to express.
                if (p.panel) return;
                /* `raw` rows own their whole property name. The normal rows
                   are one property PER ELEMENT (--fs-zone, --fs-wanted, ...)
                   so the element key is appended; a raw row is scoped to a
                   single element by `only` already and names a property that
                   style.css reads literally (--nav-accent), so appending the
                   key would write --nav-accentnavpopup, which nothing reads. */
                var name = p.raw ? p.v : (p.v + e[0] + (p.suffix || ''));
                var val = valueOf(o, p);
                // Unset -> remove, so style.css's own value wins through the
                // var() fallback. Writing an empty string would not do that.
                if (val == null || val === p.def) {
                    if (p.k === 'sx' || p.k === 'sy') stage.style.setProperty(name, 1);
                    else stage.style.removeProperty(name);
                    // Alignment is two properties, so unsetting it has to clear
                    // both — leaving --ai-* behind would keep the box aligned
                    // after the text had gone back to default.
                    if (p.k === 'al') stage.style.removeProperty('--ai-' + e[0]);
                    return;
                }
                stage.style.setProperty(name, p.unit ? (val + p.unit) : val);
                // The flex half of the same intent. style.css needs both: one
                // moves the copy, the other moves the box the copy sits in.
                if (p.k === 'al') stage.style.setProperty('--ai-' + e[0], FLEX_ALIGN[val] || 'flex-start');
            });
        });
        // The panel stack, whose three rows the loop above deliberately skips.
        applyPanelRect(lastMapRect);
        // A new font, size or width changes the box the names have to fit into,
        // so the fit factor is stale the moment any of them is touched.
        if (typeof fitAll === 'function') fitAll();
        // Live-update the other resources as you nudge, so external elements
        // move under the arrow keys exactly like the local ones.
        if (!quiet) post('layoutLive', { offsets: offsetsForSave() });
    }

    /* Has this element been changed from the shipped default? Drives the dot
       in the list, so "what have I actually touched" is answerable at a glance
       instead of by reading fourteen rows of numbers. */
    function isModified(key) {
        var o = offsets[key];
        if (!o) return false;
        if ((o.x || 0) !== 0 || (o.y || 0) !== 0) return true;
        if (scaleX(o) !== 1 || scaleY(o) !== 1) return true;
        for (var i = 0; i < PROPS.length; i++) {
            var p = PROPS[i];
            if (p.k === 'sx' || p.k === 'sy') continue;
            // A prop this element is not offered cannot be a change to it.
            if (p.only && !p.only[key]) continue;
            var v = o[p.k];
            if (v !== undefined && v !== null && v !== p.def) return true;
        }
        // 'top-right' is ox_lib's own default corner, so a layout sitting on it
        // has not been touched — treating any anchor as a change would light
        // this dot for every player from the moment they opened the editor.
        if (o.anchor != null && o.anchor !== 'top-right') return true;
        if (o.hide != null) return true;
        return false;
    }

    function renderEditor() {
        var ul = $('editor-list');
        if (!ul) return;
        ul.innerHTML = '';
        var group = null;
        var selLi = null;

        EDITOR_ELEMENTS.forEach(function (e, i) {
            if (e[4] && e[4] !== group) {
                group = e[4];
                var head = document.createElement('li');
                head.className = 'ed-group';
                head.textContent = group;
                ul.appendChild(head);
            }

            var o = offsets[e[0]] || { x: 0, y: 0 };
            var li = document.createElement('li');
            li.className = 'ed-item' + (i === editorSel ? ' sel' : '');
            if (i === editorSel) selLi = li;

            var native = !!NATIVE_ELEMENTS[e[0]];
            // Engine and cross-resource rows have no CSS scale to report, so
            // showing "x1.00 / 1.00" for them was noise that read as a value.
            var val = native || !e[2]
                ? ''
                : (o.x || 0).toFixed(2) + ', ' + (o.y || 0).toFixed(2) +
                  '  &times;' + scaleX(o).toFixed(2) + ' / ' + scaleY(o).toFixed(2);

            li.innerHTML =
                '<span class="ed-dot' + (isModified(e[0]) ? ' on' : '') + '"></span>' +
                '<span class="ed-name">' + e[1] +
                '<span class="ed-desc">' + e[3] + '</span></span>' +
                '<span class="ed-val">' + val + '</span>';

            li.addEventListener('click', function () { editorSel = i; renderEditor(); markTarget(); });
            ul.appendChild(li);
        });

        // Tab can walk the selection past the bottom of a scrolling list; without
        // this it disappears and the panel looks frozen.
        if (selLi && selLi.scrollIntoView) selLi.scrollIntoView({ block: 'nearest' });

        renderProps();
    }

    function markTarget() {
        document.querySelectorAll('.ed-target').forEach(function (n) { n.classList.remove('ed-target'); });
        var sel = EDITOR_ELEMENTS[editorSel];
        // The editor otherwise forces the map visible the whole time it is
        // open (editorPreview(true) above), so #slots.map-hidden never
        // naturally applies and the Foot position X/Y rows would be tuning
        // something nobody can see. Preview the dock ONLY while Map panels
        // is the row actually selected -- forcing it for the whole session
        // would hide that #slots has two different resting spots and leave
        // no way to see (or tune) the normal, map-anchored one at all.
        var slots = $('slots');
        if (slots) {
            slots.classList.toggle('map-hidden',
                !!sel && sel[0] === 'slots' && footDockEnabled());
        }
        if (!sel || !sel[2]) return;          // lives in another resource
        var el = document.querySelector(sel[2]);
        if (el) el.classList.add('ed-target');
    }

    function nudge(dx, dy) {
        var key = EDITOR_ELEMENTS[editorSel][0];

        if (NATIVE_ELEMENTS[key]) {
            if (NATIVE_ELEMENTS[key] === 'size') {
                // Multipliers on the configured component size, not raw
                // safe-zone units: 0.1 step = 0.5%, Shift = 5%.
                post('mapAdjust', { dw: dx * 0.05, dh: -dy * 0.05 }, function (state) {
                    if (state && typeof state === 'object') { nativeVals = state; renderProps(); }
                });
            } else {
                // dy is INVERTED on the way to Lua. The minimap components are
                // anchored 'B' (bottom), where a larger y sits HIGHER up the
                // screen, while the arrow keys use the screen convention of
                // down-is-positive. Passing dy straight through made Up push
                // the map down.
                post('mapAdjust', { dx: dx * 8, dy: -dy * 8 }, function (state) {
                    if (state && typeof state === 'object') { nativeVals = state; renderProps(); }
                });
            }
            offsets[key] = offsets[key] || { x: 0, y: 0 };
            offsets[key].x = +((offsets[key].x || 0) + dx).toFixed(2);
            offsets[key].y = +((offsets[key].y || 0) + dy).toFixed(2);
            renderEditor();
            return;
        }

        offsets[key] = offsets[key] || { x: 0, y: 0 };
        offsets[key].x = +((offsets[key].x || 0) + dx).toFixed(2);
        offsets[key].y = +((offsets[key].y || 0) + dy).toFixed(2);
        applyOffsets(); renderEditor();
    }

    // Resize the selected element. Reachable from several keys AND from the
    // on-screen -/+ buttons: Ctrl+Arrow alone was too easy to miss, and any
    // single key combination that the game or the browser eats leaves scaling
    // looking broken.
    /* axis: 'x', 'y', or 'both'. The minimap frame in particular needs height
       on its own — it is sized from the map's rect, which is a different shape
       from the frame that has to sit on it. */
    function scaleBy(delta, axis) {
        axis = axis || 'both';
        var key = EDITOR_ELEMENTS[editorSel][0];
        offsets[key] = offsets[key] || { x: 0, y: 0 };
        var o = offsets[key];

        if (NATIVE_ELEMENTS[key]) {
            // The engine draws the map, so its scale is applied in Lua.
            post('mapAdjust', axis === 'x' ? { dw: delta }
                            : axis === 'y' ? { dh: delta }
                            : { ds: delta });
            var clampN = function (v) { return +Math.max(0.01, Math.min(20, v)).toFixed(4); };
            if (axis !== 'y') o.sx = clampN(scaleX(o) * (1 + delta));
            if (axis !== 'x') o.sy = clampN(scaleY(o) * (1 + delta));
            renderEditor();
            return;
        }

        // Bounded by the Width / Height rows themselves rather than by its own
        // numbers. Ctrl+Arrow used to stop at 2.5 while those rows went to 3,
        // so one element had two different ceilings depending on how you
        // reached for it.
        var clamp = function (v) { return +Math.max(SC_MIN, Math.min(SC_MAX, v)).toFixed(4); };
        if (axis !== 'y') o.sx = clamp(scaleX(o) + delta);
        if (axis !== 'x') o.sy = clamp(scaleY(o) + delta);
        applyOffsets(); renderEditor();
    }

    /* Step the selected property. `dir` is -1 or +1; list properties cycle. */
    function bumpProp(dir, big) {
        var key = EDITOR_ELEMENTS[editorSel][0];
        var p = propsFor(key)[propSel];
        if (!p) return;

        // The engine owns the minimap, so its values go to Lua as absolutes and
        // the reply is what the panel then shows.
        if (NATIVE_ELEMENTS[key]) {
            var cur = nativeVals[p.k] == null ? 0 : Number(nativeVals[p.k]);
            var next = cur + dir * p.step * (big ? 5 : 1);
            next = Math.max(p.min, Math.min(p.max, next));
            next = +next.toFixed(p.dec);
            nativeVals[p.k] = next;              // optimistic, corrected on reply
            renderProps();
            post('mapTune', { key: p.k, value: next }, function (state) {
                if (state && typeof state === 'object') {
                    nativeVals = state;
                    renderProps();
                }
            });
            return;
        }

        offsets[key] = offsets[key] || { x: 0, y: 0 };
        var o = offsets[key];

        /* A following row has no stored value, so valueOf would hand back the
           shipped default and the first nudge would JUMP from whatever the
           parent is doing to default±step. Starting from the inherited value
           makes stepping continue from what is on screen — and writing it is
           what detaches the row, which is the same rule as before: setting a
           value takes over from the parent. */
        var base = isFollowing(key, p.k) ? inheritedValue(key, p) : valueOf(o, p);

        if (p.list) {
            var cur = base;
            var i = 0;
            for (var n = 0; n < p.list.length; n++) if (p.list[n][0] === cur) i = n;
            i = (i + dir + p.list.length) % p.list.length;
            o[p.k] = p.list[i][0];
        } else {
            var step = p.step * (big ? 4 : 1);
            var v = (base == null ? p.def : base) + dir * step;
            v = Math.max(p.min, Math.min(p.max, v));
            // Position rounds to 2dp, matching what the arrow keys write, so
            // stepping a row and nudging with the keyboard cannot disagree.
            o[p.k] = +v.toFixed(p.pos ? 2 : p.dec + 1);
        }
        applyOffsets(); renderEditor();
        // Cycling Map panels' own Dock on foot row has to update the preview
        // immediately, not just on the next reselect -- markTarget is what
        // decides whether #slots.map-hidden is showing right now.
        markTarget();
    }

    /* Move the selection WITHOUT rebuilding the settings column.
       renderProps replaces every node it owns, which would tear the focused
       text field out from under the caret the moment you clicked into it. */
    function selectRow(i) {
        propSel = i;
        var rows = document.querySelectorAll('#editor-props .ed-prop');
        for (var n = 0; n < rows.length; n++) rows[n].classList.toggle('sel', n === i);
    }

    function renderProps() {
        var box = $('editor-props');
        if (!box) return;
        var sel = EDITOR_ELEMENTS[editorSel];
        var key = sel[0];
        var o = offsets[key] || {};
        var native = !!NATIVE_ELEMENTS[key];
        var list = propsFor(key);
        if (propSel >= list.length) propSel = list.length - 1;

        // Name the thing being tuned above its own settings. With fourteen
        // elements and two scrolling columns it was otherwise easy to lose track
        // of which one the -/+ buttons were about to change.
        var head = $('editor-propfor');
        if (head) head.textContent = sel[1];

        box.innerHTML = '';
        var selRow = null;

        list.forEach(function (p, i) {
            var row = document.createElement('div');
            row.className = 'ed-prop' + (i === propSel ? ' sel' : '');
            if (i === propSel) selRow = row;

            var lab = document.createElement('span');
            lab.className = 'ed-plabel'; lab.textContent = p.label;
            // Some rows cannot say what they do in two words — "Map width" and
            // "Plane width" are a case in point, and picking the wrong one is
            // how the map ends up the right size and the wrong shape.
            if (p.hint) { lab.title = p.hint; lab.classList.add('has-hint'); }

            // The minus, the value and the plus are wrapped as ONE control
            // rather than three loose ones, which is what makes it obvious the
            // buttons act on the number between them.
            var step = document.createElement('span');
            step.className = 'ed-step';

            var minus = document.createElement('button');
            minus.type = 'button'; minus.textContent = '\u2212';
            minus.setAttribute('aria-label', 'decrease ' + p.label);

            var plus = document.createElement('button');
            plus.type = 'button'; plus.textContent = '+';
            plus.setAttribute('aria-label', 'increase ' + p.label);

            /* A row whose value is a plain number gets a real text field, not a
               label. Stepping is fine for finding a value and hopeless for
               reaching one: at 0.05 a click, a Width of 12 is 220 clicks away,
               and no ceiling generous enough to allow it would make that
               usable. `p.list` rows (Font, Text align, Corner) and the native
               on/off rows have no number to type, so those stay labels. */
            var typeable = !p.list && !(native && p.names);
            var val = document.createElement(typeable ? 'input' : 'span');
            val.className = 'ed-pval';

            var current;
            if (native) {
                var nv = nativeVals[p.k];
                current = nv == null ? null : Number(nv);
                if (p.names) {
                    val.textContent = current == null ? '-'
                        : p.names[Math.max(0, Math.min(p.names.length - 1, Math.round(current)))];
                }
            } else {
                current = valueOf(o, p);
                // A following row has no stored value, so valueOf returns the
                // shipped default — which is not what is on screen if the
                // parent has been tuned. Show what the element is actually
                // rendering, or the row reads as wrong.
                var following = isFollowing(key, p.k);
                if (following) current = inheritedValue(key, p);
                if (!typeable) val.textContent = labelFor(p, current);
                // A quiet marker on rows that are no longer at their default, so
                // "what did I change on this element" is visible without diffing
                // against the stylesheet in your head.
                //
                // Not on a FOLLOWING row. Its value can differ from the shipped
                // default while this element is untouched -- the difference
                // belongs to the parent -- and marking it here would put a
                // change indicator on a row with nothing to undo.
                if (!following && current != null && current !== p.def) row.classList.add('changed');
            }

            if (typeable) {
                val.type = 'text';
                val.setAttribute('inputmode', 'decimal');
                val.setAttribute('aria-label', p.label);
                val.value = current == null ? ''
                    : fmtNum(current, p) + (native ? (p.unitLabel || '') : (p.unit || ''));
                val.title = 'Type a value, then Enter. Range ' + p.min + ' to ' + p.max;

                var commit = function () {
                    // Tolerate what people actually type: a unit they can see in
                    // the box ("0.045em", "8%"), a comma decimal, stray spaces.
                    var raw = String(val.value).replace(',', '.').replace(/[^0-9eE.+-]/g, '');
                    var n = parseFloat(raw);
                    // Not a number at all: put the real value back rather than
                    // guessing, so a mistyped row never silently becomes zero.
                    if (!isFinite(n)) { renderProps(); return; }
                    if (!setProp(p, n, key)) renderProps();
                };

                // The editor's global keydown owns the arrows, +, -, H and
                // Space. Every one of those is something you might type into a
                // number field, so while this has focus the field keeps them.
                val.addEventListener('keydown', function (ev) {
                    ev.stopPropagation();
                    if (ev.key === 'Enter') { ev.preventDefault(); commit(); }
                    else if (ev.key === 'Escape') { ev.preventDefault(); renderProps(); }
                });
                val.addEventListener('keyup', function (ev) { ev.stopPropagation(); });
                val.addEventListener('blur', commit);
                // Clicking in must not re-render the row out from under the
                // caret, and must not select the whole field mid-edit.
                val.addEventListener('mousedown', function (ev) { ev.stopPropagation(); });
                val.addEventListener('click', function (ev) { ev.stopPropagation(); selectRow(i); });
                val.addEventListener('focus', function () { val.select(); });
            }

            minus.addEventListener('click', function (ev) { ev.stopPropagation(); propSel = i; bumpProp(-1); });
            plus.addEventListener('click', function (ev) { ev.stopPropagation(); propSel = i; bumpProp(1); });
            row.addEventListener('click', function () { propSel = i; renderProps(); });

            step.appendChild(minus); step.appendChild(val); step.appendChild(plus);
            row.appendChild(lab); row.appendChild(step);

            /* The Follow/Own switch, on the eleven rows that really do inherit.
               Rendered as one button that names the CURRENT state and toggles
               it, rather than a pair of radio-ish buttons: there are only two
               states and the row is already three controls wide. */
            if (!native && inheritsProp(key, p.k)) {
                var isFol = isFollowing(key, p.k);
                var fol = document.createElement('button');
                fol.type = 'button';
                fol.className = 'ed-follow' + (isFol ? ' on' : '');
                fol.textContent = isFol ? 'Follow' : 'Own';
                fol.title = isFol
                    ? 'Taking this from ' + labelOf(INHERITS[key].parent)
                      + '. Click to give this element its own value.'
                    : 'This element has its own value. Click to go back to '
                      + 'following ' + labelOf(INHERITS[key].parent) + '.';
                fol.setAttribute('aria-pressed', isFol ? 'true' : 'false');
                fol.addEventListener('click', function (ev) {
                    ev.stopPropagation();
                    propSel = i;
                    setFollow(key, p, !isFollowing(key, p.k));
                });
                row.appendChild(fol);
                if (isFol) row.classList.add('following');
            }

            box.appendChild(row);
        });

        if (selRow && selRow.scrollIntoView) selRow.scrollIntoView({ block: 'nearest' });
    }

    function resetSelected() {
        var key = EDITOR_ELEMENTS[editorSel][0];
        offsets[key] = { x: 0, y: 0, s: 1, sx: 1, sy: 1 };
        PROPS.forEach(function (p) { delete offsets[key][p.k]; });
        offsets[key].sx = 1; offsets[key].sy = 1;
        // Resetting the panel stack means "put them back on the map", and the
        // map may well have been resized since the snapshot was taken. Without
        // this the rows clear but the panels stay at their old size, which
        // reads as Reset not working.
        if (key === 'slots') resnapPanelRect();
        if (NATIVE_ELEMENTS[key]) {
            post('mapReset', {}, function (state) {
                if (state && typeof state === 'object') { nativeVals = state; renderProps(); }
            });
        }
        applyOffsets(); renderEditor();
    }

    function closeEditor(save) {
        editorOpen = false;
        editorPreview(false);
        show($('editor'), false);
        document.querySelectorAll('.ed-target').forEach(function (n) { n.classList.remove('ed-target'); });
        post(save ? 'saveLayout' : 'closeEditor', save ? { offsets: offsetsForSave() } : {});
    }

    /* While the editor is open every element is forced visible with
       representative content, so you can see exactly what you're positioning
       instead of moving invisible boxes. Restored on close. */
    function editorPreview(on) {
        if (on) {
            onStatus({ health: 62, focus: 45, stamina: 54 });
            onWanted({ active: true, stars: 3, maxStars: 6, state: 'contact',
                       tells: ['camera', 'weapon', 'person', 'people', 'hanger', 'vehicle'] });
            // A real icon, not just the clip/reserve numbers, so the ammo row
            // has actual art to line up against instead of an empty box.
            // weapon_pistol is ox_inventory's own art, the same nui:// path
            // client.lua's WeaponIcons table points at in game.
            onWeapon({ armed: true, icon: 'nui://ox_inventory/web/images/weapon_pistol.png', clip: 12, reserve: 84 });
            // wheel: true -- the balance rows are hidden by default now (see
            // onCash), so the preview has to ask for the expanded view same
            // as opening the inventory would, or Money would render as an
            // empty box with nothing to position.
            onCash({ cash: 12163, bank: 154200, cashCap: 20000, show: true, wheel: true });
            onDuffle({ value: 4820 });
            onChips({ value: 3450 });
            onZone({ zone: 'Mirror Park', duration: 9e6 });
            /* Fuel and engine are pushed into their WARNING bands, the tracker
               is forced into 'spotted' and the car is given a nitrous kit, so
               all four discs are on screen to be positioned. In normal play
               each only appears when it has something to say (see setPips),
               which would otherwise leave the pip row unpositionable in a
               healthy car. */
            onVehicle({ show: true, make: 'Nagasaki', model: 'Chimera',
                        fuel: 18, engineOn: true, engineHealth: 420,
                        trackerState: 'spotted',
                        nitrous: { installed: true, level: 0.62, active: false, ready: true } });
            onHonor({ emoji: 'icons/honor_bad.png', terribleEmoji: 'icons/honor_terrible.png',
                      honor: -50, showValue: true,
                      reason: 'Killed a bystander', duration: 9e6, broken: true });
            onReputation({ icon: '🗡️', label: 'CRIMINAL', value: 240, tier: 3,
                            showValue: true, reason: 'Robbed an armoured truck',
                            holdMs: 9e6 });
            editorHonorCycle(true);
            editorReputationCycle(true);
            editorMoneyPopCycle(true);
            editorSkillUpHold(true);
            onPrompt({ id: '_ed', label: 'Interact', glyph: 'E',
                       device: 'kbm', show: true });
            var fr = $('map-frame'); if (fr) show(fr, true);
            onNav({ active: true, near: true, street: 'Bayside', remaining: '0.69 mi',
                    instruction: 'Turn Left', dir: 'left', distance: '130 ft' });
            // onNav just hid the badge the way it does whenever nav is active
            // -- correct in normal play, wrong here: editor preview wants
            // every piece on screen at once, badge included, so it can be
            // selected and positioned like everything else. Same for the frame
            // above: applyMapChrome would otherwise re-hide both, since the
            // editor forces the radar on regardless of what setRadar last said.
            show($('map-badge'), true);
            // Forced ON for the duration of editing, same reasoning as the
            // rest of this function: an effect that only shows for a few
            // seconds mid-fight is unpositionable/untunable otherwise.
            var ffx = $('focus-fx'); if (ffx) ffx.classList.add('active');
            var frow = $('s-focus'); if (frow) frow.classList.add('active');
        } else {
            editorHonorCycle(false);
            editorReputationCycle(false);
            editorMoneyPopCycle(false);
            editorSkillUpHold(false);
            onPrompt({ id: '_ed', show: false });
            var ffxOff = $('focus-fx'); if (ffxOff) ffxOff.classList.remove('active');
            var frowOff = $('s-focus'); if (frowOff) frowOff.classList.remove('active');
            ['zone', 'vehicle', 'honor', 'wanted', 'honor-pop',
             'reputation', 'reputation-pop', 'money-pop', 'skillup'].forEach(function (id) {
                show($(id), false);
            });
            // Not just a show(el, false) like the ids above: onNav's own
            // "inactive" branch is what clears mapBadgeWanted back to true.
            // editorPreview(true) called onNav({active:true, near:true, ...})
            // to preview the nav bar, which sets mapBadgeWanted = false (the
            // badge steps aside for the compass) -- hiding nav-popup/
            // nav-compass by id here without going back through onNav left
            // that flag stuck at false, so the badge stayed hidden after
            // every close from then on, not just during the preview.
            onNav({ active: false });
            // The frame and badge were forced on for the preview; put the whole
            // map chrome back to whatever the config and the live radar state
            // actually ask for.
            applyMapChrome();
            // Clear the fake money/weapon/duffle/chips readouts. The client
            // re-pushes the real values on its next tick (see
            // resetPushCaches in client.lua) -- duffle and chips only poll
            // every few seconds, so without this they'd sit at the preview's
            // fake numbers until that timer next fires.
            onCash({ show: false });
            onWeapon({ armed: false });
            onDuffle({ value: null });
            onChips({ value: null });
            // The preview's fake $12,163/$154,200 must not become the
            // baseline a real push is diffed against -- without this, the
            // first real 'cash' message after closing the editor reads as a
            // huge, bogus loss and fires a money-pop for it.
            lastCashSeen = null;
            lastBankSeen = null;
            // Same reasoning for the wanted box: the preview's sample stars
            // and tells must not count as already seen, or the next real
            // wanted push would look like nothing new and never pop.
            wantedLastStars = 0;
            wantedLastTells = {};
        }
    }

    /* The pop fades on its own timer, which makes it impossible to position
       (same problem editorHonorCycle solves for honor-pop). Alternates a gain
       and a loss so both colours can be checked while placing it. */
    var editorMoneyPopTimer = null;

    function editorMoneyPopCycle(on) {
        if (editorMoneyPopTimer) { clearInterval(editorMoneyPopTimer); editorMoneyPopTimer = null; }
        if (!on) { show($('money-pop'), false); return; }
        var up = false;
        var beat = function () {
            up = !up;
            onMoneyPop(up ? 50 : -50, up ? 'icons/cash.png' : 'icons/buckme.png');
        };
        beat();
        editorMoneyPopTimer = setInterval(beat, 1600);
    }

    function openEditor(d) {
        offsets = asOffsetMap(d.offsets);
        if (d.native && typeof d.native === 'object') nativeVals = d.native;
        editorOpen = true; editorSel = 0;
        editorPreview(true);
        applyOffsets(); renderEditor(); markTarget();
        show($('editor'), true);
        // Always reopen expanded and un-peeked; only the POSITION persists,
        // because a panel that comes back collapsed reads as broken.
        setCollapsed(false); setPeek(false); restorePanelPos(); restorePanelSize();
    }

    /* --- the panel itself: drag, collapse, peek ---------------------------
       The editor is a tool laid OVER the thing it edits, so it will always be
       in the way of something. Three ways out, none of which need the editor
       closed and reopened:
         · drag it by its title bar, and the position is remembered
         · H (or the button in the title bar) folds it down to the title bar
         · hold Space to make it near-invisible for as long as you hold it
       Together with the removed scrim (see style.css) this is what makes it
       possible to fine-tune a corner element while looking at it. */
    var PANEL_POS_KEY = 'vice_hud:editorPanelPos';
    var PANEL_SIZE_KEY = 'vice_hud:editorPanelSize';

    /* Floors, not opinions — the same rule as the property min/max. Below these
       the panel stops being a panel: the two columns collapse into each other
       and the grip ends up under the action buttons. The ceiling is the
       viewport, applied at drag time rather than as a constant. */
    var PANEL_MIN_W = 520, PANEL_MIN_H = 260;

    function panelEl() { return $('editor-panel'); }

    function clampPanel(x, y) {
        var el = panelEl();
        var w = (el && el.offsetWidth) || 0;
        var h = (el && el.offsetHeight) || 0;
        var maxX = Math.max(0, (window.innerWidth || 0) - w);
        var maxY = Math.max(0, (window.innerHeight || 0) - h);
        return { x: Math.min(Math.max(0, x), maxX), y: Math.min(Math.max(0, y), maxY) };
    }

    /* `remember` is false during a drag: writing to storage on every mousemove
       is pointless, and the drop is the only position worth keeping. */
    function placePanel(x, y, remember) {
        var el = panelEl();
        if (!el) return;
        var c = clampPanel(x, y);
        el.classList.add('dragged');
        el.style.left = c.x + 'px';
        el.style.top = c.y + 'px';
        if (remember) {
            try { localStorage.setItem(PANEL_POS_KEY, JSON.stringify(c)); } catch (e) {}
        }
    }

    /* `remember` is false during a resize drag, for the same reason it is
       during a move: only the final size is worth storing. */
    function sizePanel(w, h, remember) {
        var el = panelEl();
        if (!el) return;
        var maxW = Math.max(PANEL_MIN_W, (window.innerWidth || 0) - 8);
        var maxH = Math.max(PANEL_MIN_H, (window.innerHeight || 0) - 8);
        var cw = Math.min(Math.max(PANEL_MIN_W, w), maxW);
        var ch = Math.min(Math.max(PANEL_MIN_H, h), maxH);
        el.classList.add('resized');
        el.style.width = cw + 'px';
        el.style.height = ch + 'px';
        if (remember) {
            try {
                localStorage.setItem(PANEL_SIZE_KEY, JSON.stringify({ w: cw, h: ch }));
            } catch (e) {}
        }
    }

    function restorePanelSize() {
        var el = panelEl();
        if (!el) return;
        var saved = null;
        try { saved = JSON.parse(localStorage.getItem(PANEL_SIZE_KEY) || 'null'); } catch (e) {}
        if (saved && typeof saved.w === 'number' && typeof saved.h === 'number') {
            sizePanel(saved.w, saved.h, false);
        } else {
            // Back to the stylesheet's starting size.
            el.classList.remove('resized');
            el.style.width = '';
            el.style.height = '';
        }
    }

    function initPanelResize() {
        var grip = $('ed-resize');
        var el = panelEl();
        if (!grip || !el) return;
        var sizing = false, sx = 0, sy = 0, sw = 0, sh = 0;

        grip.addEventListener('mousedown', function (ev) {
            if (ev.button !== 0) return;
            var r = el.getBoundingClientRect();
            sx = ev.clientX; sy = ev.clientY;
            sw = r.width; sh = r.height;
            sizing = true;
            el.classList.add('resizing');
            // Stop the head's drag handler and the row click-through both.
            ev.preventDefault();
            ev.stopPropagation();
        });
        // On document for the same reason the move drag is: a fast drag outruns
        // the cursor and the pointer ends up over the game.
        document.addEventListener('mousemove', function (ev) {
            if (!sizing) return;
            sizePanel(sw + (ev.clientX - sx), sh + (ev.clientY - sy), false);
        });
        document.addEventListener('mouseup', function (ev) {
            if (!sizing) return;
            sizing = false;
            el.classList.remove('resizing');
            sizePanel(sw + (ev.clientX - sx), sh + (ev.clientY - sy), true);
        });
        // Double-click the grip to go back to the stylesheet's size, so a panel
        // dragged to something unusable is always one gesture from sane.
        grip.addEventListener('dblclick', function (ev) {
            ev.preventDefault(); ev.stopPropagation();
            try { localStorage.removeItem(PANEL_SIZE_KEY); } catch (e) {}
            restorePanelSize();
        });
    }

    function restorePanelPos() {
        var el = panelEl();
        if (!el) return;
        var saved = null;
        try { saved = JSON.parse(localStorage.getItem(PANEL_POS_KEY) || 'null'); } catch (e) {}
        if (saved && typeof saved.x === 'number' && typeof saved.y === 'number') {
            placePanel(saved.x, saved.y, false);
        } else {
            // Back to the CSS centring.
            el.classList.remove('dragged');
            el.style.left = '';
            el.style.top = '';
        }
    }

    function setCollapsed(on) {
        var el = panelEl();
        if (!el) return;
        el.classList.toggle('collapsed', !!on);
        var b = $('ed-collapse');
        if (b) {
            b.textContent = on ? '▾' : '▴';
            b.setAttribute('aria-label', on ? 'expand the editor' : 'collapse the editor');
            b.title = on ? 'Expand (H)' : 'Collapse (H)';
        }
        var sub = $('editor-sub');
        if (sub) {
            sub.textContent = on
                ? 'Collapsed — arrows still move the selected piece. H to reopen.'
                : 'Pick a piece on the left, tune it on the right.';
        }
    }

    function togglePanel() {
        var el = panelEl();
        setCollapsed(!(el && el.classList.contains('collapsed')));
    }

    function setPeek(on) {
        var el = panelEl();
        if (el) el.classList.toggle('peek', !!on);
    }

    function initPanelDrag() {
        var head = $('editor-head');
        var el = panelEl();
        if (!head || !el) return;
        var dragging = false, ox = 0, oy = 0;

        head.addEventListener('mousedown', function (ev) {
            if (ev.button !== 0) return;
            // The collapse button lives in the head; dragging must not eat it.
            if (ev.target && ev.target.closest && ev.target.closest('button')) return;
            var r = el.getBoundingClientRect();
            ox = ev.clientX - r.left;
            oy = ev.clientY - r.top;
            dragging = true;
            el.classList.add('dragging');
            ev.preventDefault();
        });
        // On document, not on the head: a fast drag outruns the cursor and the
        // pointer ends up over the game, which would strand the panel mid-move.
        document.addEventListener('mousemove', function (ev) {
            if (!dragging) return;
            placePanel(ev.clientX - ox, ev.clientY - oy, false);
        });
        document.addEventListener('mouseup', function (ev) {
            if (!dragging) return;
            dragging = false;
            el.classList.remove('dragging');
            placePanel(ev.clientX - ox, ev.clientY - oy, true);
        });
    }

    // Space is held, not tapped, so the release has to be caught even when the
    // editor has already closed underneath it.
    document.addEventListener('keydown', function (ev) {
        if (ev.key !== 'Escape') return;
        var sk = $('skills');
        if (!sk || sk.classList.contains('hidden')) return;
        show(sk, false);
        post('closeSkills', {});
        // Stops here so a skills panel open on top of the editor does not also
        // cancel the edit underneath it.
        ev.stopPropagation();
        ev.preventDefault();
    }, true);

    document.addEventListener('keydown', function (ev) {
        var box = $('interact');
        if (!box || box.classList.contains('hidden')) return;
        if (ev.key === 'ArrowUp')        { moveInteractSel(-1); }
        else if (ev.key === 'ArrowDown') { moveInteractSel(1); }
        else if (ev.key === 'Enter')     { confirmInteract(); }
        else if (ev.key === 'Escape')    { closeInteract(); }
        else return;
        ev.stopPropagation();
        ev.preventDefault();
    }, true);

    document.addEventListener('keyup', function (ev) {
        if (ev.target && ev.target.tagName === 'INPUT') return;
        if (ev.key === ' ' || ev.key === 'Spacebar') setPeek(false);
    });

    /* Is the player typing into one of the value fields right now? Those fields
       need the arrows, the digits, `-`, `.` and Space — every one of which this
       handler otherwise claims. The fields stopPropagation as well; this is the
       backstop, because a single missed listener here turns typing a negative
       number into "shrink the element". */
    function typingInField(ev) {
        var t = ev.target;
        return !!t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable);
    }

    document.addEventListener('keydown', function (ev) {
        if (!editorOpen || typingInField(ev)) return;
        var step = ev.shiftKey ? 1.0 : 0.1;
        var sstep = ev.shiftKey ? 0.20 : 0.05;

        // Panel chrome. Checked before everything else so they work whatever
        // is selected and whichever property row is in focus.
        if (ev.key === 'h' || ev.key === 'H') { togglePanel(); ev.preventDefault(); return; }
        if (ev.key === ' ' || ev.key === 'Spacebar') { setPeek(true); ev.preventDefault(); return; }

        // Ctrl + arrows resize ALONG THAT AXIS: left/right = width,
        // up/down = height. Holding them apart is the only way to make an
        // element that is the wrong shape (rather than the wrong size) fit.
        if (ev.ctrlKey) {
            if (ev.key === 'ArrowUp')    { scaleBy(sstep, 'y');  ev.preventDefault(); return; }
            if (ev.key === 'ArrowDown')  { scaleBy(-sstep, 'y'); ev.preventDefault(); return; }
            if (ev.key === 'ArrowRight') { scaleBy(sstep, 'x');  ev.preventDefault(); return; }
            if (ev.key === 'ArrowLeft')  { scaleBy(-sstep, 'x'); ev.preventDefault(); return; }
        }

        // [ and ] choose which property + / - acts on.
        //
        // These wrapped on PROPS.length, which is only correct for a page
        // element. On the two engine-owned rows the list is NATIVE_PROPS and is
        // longer, so everything past the ninth entry -- Panel left/width/bottom/
        // height, Rounded corners and Mask = map -- was unreachable from the
        // keyboard. Clicking still worked, which is why it read as "the keys are
        // ignored down there" rather than as a bug.
        var plist = propsFor(EDITOR_ELEMENTS[editorSel][0]);
        if (ev.key === '[') { propSel = (propSel - 1 + plist.length) % plist.length; renderProps(); ev.preventDefault(); return; }
        if (ev.key === ']') { propSel = (propSel + 1) % plist.length; renderProps(); ev.preventDefault(); return; }

        // + / - (and PageUp/PageDown) step the SELECTED property, which starts
        // on Font size. Shift takes bigger steps.
        if (ev.key === '+' || ev.key === '=' || ev.key === 'PageUp') {
            bumpProp(1, ev.shiftKey); ev.preventDefault(); return;
        }
        if (ev.key === '-' || ev.key === '_' || ev.key === 'PageDown') {
            bumpProp(-1, ev.shiftKey); ev.preventDefault(); return;
        }

        switch (ev.key) {
            case 'ArrowLeft':  nudge(-step, 0); break;
            case 'ArrowRight': nudge(step, 0);  break;
            case 'ArrowUp':    nudge(0, -step); break;
            case 'ArrowDown':  nudge(0, step);  break;
            case 'Tab':
                editorSel = (editorSel + (ev.shiftKey ? -1 : 1) + EDITOR_ELEMENTS.length) % EDITOR_ELEMENTS.length;
                renderEditor(); markTarget(); break;
            case 'Enter':  closeEditor(true);  break;
            case 'Escape': closeEditor(false); break;
            default: return;
        }
        ev.preventDefault();
    });

    function post(name, data, onReply) {
        if (typeof GetParentResourceName === 'undefined') return;
        fetch('https://' + GetParentResourceName() + '/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {})
        }).then(function (r) {
            // Native rows read their values back out of the reply, so the panel
            // shows what the engine actually did rather than what was asked for.
            return onReply ? r.json() : null;
        }).then(function (j) {
            if (onReply && j) onReply(j);
        }).catch(function () {});
    }

    document.addEventListener('DOMContentLoaded', function () {
        var b;
        if ((b = $('ed-save')))     b.addEventListener('click', function () { closeEditor(true); });
        if ((b = $('ed-cancel')))   b.addEventListener('click', function () { closeEditor(false); });
        if ((b = $('ed-reset')))    b.addEventListener('click', resetSelected);
        if ((b = $('ed-collapse')))  b.addEventListener('click', togglePanel);
        if ((b = $('skills-close'))) b.addEventListener('click', function () {
            show($('skills'), false);
            post('closeSkills', {});
        });
        var interactList = $('interact-list');
        if (interactList) interactList.addEventListener('click', function (ev) {
            var row = ev.target.closest('.interact-row');
            if (!row) return;
            interactSel = Number(row.dataset.index);
            confirmInteract();
        });
        initPanelDrag();
        initPanelResize();
        if ((b = $('ed-resetall'))) b.addEventListener('click', function () {
            offsets = {}; post('mapReset', {}); applyOffsets(); renderEditor();
        });
        // Size / font buttons used to live down here too. They are gone: every
        // one of them duplicated a property row's own - / + , and eleven
        // buttons overflowed the action bar and clipped "Save & close".
    });

    /* --- dispatch -------------------------------------------------------- */

    var HANDLERS = {
        status: onStatus,
        staminaBolt: onStaminaBolt,
        wanted: onWanted,
        cash: onCash,
        duffle: onDuffle,
        chips: onChips,
        weapon: onWeapon,
        crosshair: onCrosshair,
        thirdEye: onThirdEye,
        crossFire: onCrossFire,
        crossKill: onKillMark,
        lapHud: onLapHud,
        raceCard: onRaceCard,
        raceCountdown: onRaceCountdown,
        raceMarker: onRaceMarker,
        interact: onInteract,
        worldActions: onWorldActions,
        worldActionsPos: onWorldActionsPos,
        lockpick: onLockpick,
        lockpickProgress: onLockpickProgress,
        lockpickResult: onLockpickResult,
        lockpickAlarm: onLockpickAlarm,
        keyClone: onKeyClone,
        keyCloneProgress: onKeyCloneProgress,
        keyCloneMiss: onKeyCloneMiss,
        keyCloneResult: onKeyCloneResult,
        mapRect: onMapRect,
        mapDebug: onMapDebug,
        zone: onZone,
        nav: onNav,
        navAccent: onNavAccent,
        vehicle: onVehicle,
        nitrous: onNitrous,
        nitrousHint: onNitrousHint,
        brandTour: onBrandTour,
        logoCheck: onLogoCheck,
        honor: onHonor,
        reputation: onReputation,
        prompt: onPrompt,
        promptProgress: onPromptProgress,
        promptGlyphs: onPromptGlyphs,
        inputDevice: onInputDevice,
        'target:nui': onTargetNui,
        subtitle: onSubtitle,
        objective: onObjective,
        helpText: onHelpText,
        feed: onFeed,
        titleCard: onTitleCard,
        binoculars: onBinoculars,
        shop: onShop,
        cineFx: onCineFx,
        vehStats: onVehStats,
        police: onPolice,
        policeEditor: onPoliceEditor,
        skills: onSkills,
        skillUp: onSkillUp,
        statGain: onStatGain,
        exhaustion: onExhaustion,
        hudOffset: onOffset,
        layout: onLayout,
        openEditor: openEditor,
        hudVisible: function (d) { if (stage) stage.style.display = d.show === false ? 'none' : ''; },
        // (the money and its pop off the screen while a clothing / barber / tattoo store is open: client.lua)
        moneyHidden: function (d) { if (stage) stage.classList.toggle('money-off', d.hidden === true); },
        exportMinimapMask: onExportMinimapMask
    };

    /* Everything the editor preview draws itself. client.lua keeps polling the
       real game state while /movehud is open and pushes it every 250ms, which
       overwrote the preview almost immediately — at full health and no wanted
       level that meant the status bars and the top-right stack vanished a
       quarter-second after the editor opened, so there was nothing to place. */
    var PREVIEW_OWNED = {
        status: 1, wanted: 1, cash: 1, weapon: 1,
        zone: 1, vehicle: 1, nitrous: 1, honor: 1, reputation: 1, prompt: 1, nav: 1
    };

    /* makes.js is a separate file and index.html loads it BEFORE this one. If it
       is missing the page still works in every other respect -- the panel draws,
       the names are right, nothing throws -- and simply never shows a badge,
       which is a fault that can sit there for a long time looking like a design
       decision. Say so once, out loud, in the client console.

       In practice this means the file is not being SERVED rather than absent:
       adding files to fxmanifest needs `refresh` on the server before `ensure`,
       or the server keeps handing out the file list it scanned last. */
    if (!window.VICE_MAKES) {
        console.error('[vice_hud] html/makes.js did not load — no manufacturer '
                    + 'badges will be drawn. On the SERVER console: refresh, then '
                    + 'ensure vice_hud.');
        post('logoReport', { fatal: 'no-table' });
    }

    window.addEventListener('message', function (e) {
        var d = e.data || {};
        if (editorOpen && PREVIEW_OWNED[d.action]) return;
        var fn = HANDLERS[d.action];
        if (!fn) return;
        try { fn(d); }
        catch (err) { console.error('[vice_hud] handler "' + d.action + '" failed:', err); }
    });

    /* --- tell the client the page is listening ---------------------------- */
    /* The NUI page takes appreciably longer to come up than client.lua does, so
       anything the client pushes during those first moments lands nowhere --
       there is no listener yet and NUI messages are not queued. That is a
       silent failure: the state is correct on the Lua side and simply never
       reached the page.

       It bit the minimap. A player whose saved preference is "no map on foot"
       got the map hidden correctly, but the one `visible: false` that hides the
       frame and the corner badge with it was sent before this file existed, and
       setRadar only reports CHANGES -- so after every restart the frame and
       logo sat on screen outlining an empty box until the player got into a car
       and out again.

       This ping is the fix: the client invalidates its "already sent that"
       caches when it arrives, and the next poll tick re-asserts everything
       against a page that is now listening. Inert outside FiveM -- post()
       returns immediately when GetParentResourceName is undefined. */
    post('uiReady', {});

    /* --- browser demo mode ----------------------------------------------- */
    /* When opened outside FiveM (no GetParentResourceName) populate the HUD with
       representative data so the layout can be verified in a normal browser.
       This is inert in game. */
    if (typeof GetParentResourceName === 'undefined') {
        onStatus({ health: 66, focus: 40, stamina: 58 });
        onCash({ cash: 12163, bank: 154200, cashCap: 20000, show: true, wheel: true });
        onDuffle({ value: 4820 });
        onChips({ value: 3450 });
        onWanted({ active: true, stars: 2, maxStars: 6, state: 'searching', tells: ['camera', 'weapon', 'person', 'people', 'hanger', 'vehicle'] });
        onWeapon({ armed: true, clip: 20, reserve: 80 });
        // Keep these in step with Config.Minimap in config.lua.
        onMapRect({ left: 1.75, width: 15.8, bottom: 17.9, height: 15.4 });
        onZone({ zone: 'South Vice-Dale County', duration: 999999 });
        onNav({ active: true, near: true, street: 'Bayside', remaining: '0.69 mi',
                instruction: 'Turn Left', dir: 'left', distance: '130 ft' });
        onVehicle({ show: true, make: 'Pegassi', model: 'Bati 801', fuel: 72,
                    engineOn: true, engineHealth: 900, trackerState: 'searching',
                    nitrous: { installed: true, level: 0.7, active: false, ready: true } });
        onHonor({ emoji: 'icons/honor_bad.png', terribleEmoji: 'icons/honor_terrible.png',
                  honor: -50, showValue: true, reason: 'Wanted by police', duration: 999999, broken: true });
        onReputation({ icon: '🗡️', label: 'CRIMINAL', value: 240, tier: 3,
                        showValue: true, reason: 'Robbed an armoured truck', holdMs: 999999 });
        // Nothing wires an action prompt today — the export exists for other
        // resources to call. Shown here only so the slot can be eyeballed.
        onPrompt({ id: 'demo', label: 'Interact', glyph: 'E', device: 'kbm', show: true });
        onPolice({ active: true, edges: { top: 0, right: 0.45, bottom: 0, left: 0 } });
        onCrosshair({ active: true, mode: 'foot' });
        onLapHud({ show: true, lap: 1, laps: 2, cp: 10, cpTotal: 16, elapsedMs: 19950, running: true });
        // Real ox_inventory items and their actual badges -- see
        // client_overlays.lua's /hudinteractitems, which shows this exact
        // list in-game by calling ox_inventory's Items/GetConsumableBadges
        // exports instead of hardcoding it the way this browser-only demo
        // has to. IFAK is included deliberately badge-less (no client.export
        // on that item) as the contrast case.
        onInteract({
            show: true, selected: 0,
            options: [
                { label: 'Sandwich', badges: ['stamina'] },
                { label: 'Green Tea', badges: ['focus'] },
                { label: 'Medikit', badges: ['health'] },
                { label: 'IFAK' }
            ]
        });
        onWorldActions({
            show: true,
            options: [
                { label: 'Slim Jim', button: 'triangle' },
                { label: 'Smash Window', button: 'circle' }
            ]
        });
        onLockpick({ show: true, glyph: 'R' });
        onLockpickProgress({ pct: 48, dir: -1 });

    }
})();
