/* The drawn minimap: the island as flat colour seen at a slant, with its
 * buildings standing up, where the engine's radar would otherwise be.
 *
 * The look, the projection and the numbers in VIEW and PAINT are those of the
 * "GTA-VI MiniMap (3D Buildings)" mod by @moddims, read out of it; the world it
 * draws is that mod's survey, converted by tools/map3d/build.py. The mod paints
 * its picture straight onto the game's frame from a plugin, which a server
 * cannot hand to its players, so here the same picture is drawn by WebGL on
 * the HUD's own page.
 *
 * What it costs: the geometry is uploaded once and never touched again. A
 * frame is a few dozen draw calls over the 256 m squares around the player,
 * and a frame is only drawn when client_map3d.lua says something moved.
 *
 *   map3d       { load, show, config, night, police, ripple }
 *               fetch the world; on or off; Config.Map3D's view and paints;
 *               how far into the night it is, 0-1; what the police know:
 *               'contact' (they can see the player), 'searching' (they have
 *               lost sight and are looking), 'red' (shaken off, still wanted),
 *               or false; and whether the player is spending stamina, which
 *               sends rings out from their marker
 *   map3dPos    { x, y, c, h, s }           position, camera and ped heading
 *                                           (degrees), speed (m/s)
 *   map3dRoute  { routes: [{ pts, rgb, rim, head }], ends: [{ x, y, rgb, ring, icon, iconRgb }] }
 *               the GPS line(s) as world x,y pairs, `head` on the one that
 *               starts at the player; and where each ends -- ringed, with the
 *               place's blip picture in the ring if it ends at one
 *   map3dBlips  { list: [[x, y, sprite, r, g, b, a, flags], ...] }
 *               flags: 1 = stays on the edge when out of view. A blip's icon
 *               is always drawn upright, as the engine's radar draws it
 *   map3dMoving { list }                    the same, for blips that ride an
 *                                           entity and so are sent more often
 *
 * And back: map3dHello once the page is listening, map3dReady { ok, why }
 * once the world is in (or will not go in). Nothing is fetched and no WebGL
 * context exists until the first `load` or `show`: a server or a player with
 * the drawn map switched off pays for none of it.
 */
(function () {
    'use strict';

    // How the ground is seen. A point `g` pixels ahead of the player is drawn
    // 1 / (1 + T * g) as large, with T = tilt / (anchor * panel height).
    var VIEW = {
        zoom: 2.58,         // pixels per metre, on a panel 115 pixels tall
        speedZoom: 0.25,    // how much of that is given up at full speed
        speedFull: 50,      // m/s that counts as full speed
        zoomEase: 7,        // per second
        tilt: 0.8,
        anchor: 0.725,      // the player, as a fraction of the way down the panel
        lift: 0.3,          // a metre of height is this much of a metre on screen
        liftCap: 400,       // tall buildings stop growing, in panel pixels
        opacity: 0.87,
        fade: { rx: 30, ry: 40, up: 6, min: 0.18, near: 0.3 },
        // The line starts `gap` metres ahead of the player and comes in over
        // the next `fade`, as the reference's does; it never touches the marker.
        route: { lane: 3.5, minWidth: 6, rim: 1.2, gap: 5, fade: 10 },
        end: { ring: 27.6, pin: 16.2 },     // a route's end: the ring, and the disc in it
        marker: 12.4,       // diameter, panel pixels
        blip: 16.5,
        north: true
    };

    var PAINT = {
        land: [160, 155, 149], water: [118, 152, 158], sand: [178, 162, 134],
        footprint: [158, 159, 166], rail: [148, 144, 140], road: [172, 167, 161],
        lot: [182, 177, 170], lane: [120, 117, 114, 70 / 255],
        roof: [158, 159, 166], wall: [146, 150, 160], shadow: 20 / 255,
        route: [250, 116, 165]
    };

    // The same things after dark, sampled off the reference's night footage:
    // the land goes to slate and the roads stand out of it, lighter. `night`
    // runs from 0 (day) to 1 and every colour is mixed by it, so dusk and dawn
    // are a slow change and not a switch.
    var NIGHT = {
        land: [42, 42, 62], water: [27, 35, 58], sand: [58, 56, 70],
        footprint: [50, 50, 72], rail: [60, 59, 76], road: [90, 86, 100],
        lot: [66, 64, 82], lane: [132, 130, 146, 0.2],
        roof: [62, 62, 86], wall: [36, 36, 54], shadow: 34 / 255
    };
    var night = 0;

    // Wanted. The reference draws no police on its minimap at all: it floods
    // the ground round the player with one flat colour, roads and all, and
    // leaves the buildings and the blips standing on it. Red while the police
    // can see the player, blue while they are searching, measured off the
    // footage; each holds for as long as that stays true, and one gives way to
    // the other in a fraction of a second. `cover` is how much of the ground's
    // own colour it replaces.
    var POLICE = {
        contact: { rgb: [178, 54, 68], cover: 1 },
        searching: { rgb: [32, 96, 206], cover: 1 },
        red: { rgb: [178, 54, 68], cover: 0.45 },
        radius: 270,        // metres round the player: the whole panel at rest,
                            // its far edge coming into view at speed
        soft: 30,           // the edge of it, metres
        buildings: 0.78,    // how far a building is taken toward it: in the
                            // reference they show as a slightly lighter shape
        ease: 6             // per second
    };
    var flood = { rgb: [178, 54, 68], cover: 0, to: null };
    function setPolice(kind) {
        var want = (typeof kind === 'string' && POLICE[kind] && POLICE[kind].rgb) ? POLICE[kind] : null;
        flood.to = want;
        // Coming up from nothing there is no colour to cross-fade from.
        if (want && flood.cover < 0.01) flood.rgb = want.rgb.slice();
    }
    // One step of the fade. True while it still has somewhere to go.
    function stepFlood(dt, snap) {
        var to = flood.to, cover = to ? to.cover : 0, k = snap ? 1 : 1 - Math.exp(-dt * POLICE.ease), moving = false, i;
        if (Math.abs(cover - flood.cover) > 0.004) { flood.cover += (cover - flood.cover) * k; moving = true; } else flood.cover = cover;
        if (to) {
            for (i = 0; i < 3; i++) {
                if (Math.abs(to.rgb[i] - flood.rgb[i]) > 0.6) { flood.rgb[i] += (to.rgb[i] - flood.rgb[i]) * k; moving = true; } else flood.rgb[i] = to.rgb[i];
            }
        }
        return moving;
    }
    // Stamina. While the player is spending it the reference sends rings out
    // from their marker: thin and light, a new one from the marker's rim every
    // 0.4 s, each growing at a steady 2.65 marker radii a second and thinning
    // away to nothing at 4, so two or three are on the map at once and the
    // last of them is gone a second after the running stops. Tracked through
    // seventeen frames of the footage, and its brightness set against the
    // same frames; every length here is in marker radii.
    var RIPPLE = {
        every: 0.4,         // seconds between one ring and the next
        speed: 2.65,        // marker radii a second
        from: 1.0,          // where a ring starts: the marker's rim
        to: 4.0,            // and where it has faded out (the last seen is at 3.5)
        alpha: 0.72,        // at the rim; a straight line down to nothing at `to`
        width: 0.14,        // of the line
        wake: 0.3,          // the faint wash a ring leaves inside itself, as a
        wakeLength: 1.1,    //   part of its own brightness, and how far in
        rgb: [255, 255, 255]
    };
    var ripple = { on: false, rings: [], next: 0 };     // rings: when each was born, ms
    function setRipple(on) { ripple.on = on === true; }
    function rippleLife() { return (RIPPLE.to - RIPPLE.from) / Math.max(0.01, RIPPLE.speed) * 1000; }
    // Lets the old rings go and starts the next one when it is due. True while
    // there is anything to animate.
    function stepRipple(now) {
        var life = rippleLife(), gap = Math.max(0.05, RIPPLE.every) * 1000;
        while (ripple.rings.length && now - ripple.rings[0] >= life) ripple.rings.shift();
        if (ripple.on && now >= ripple.next) {
            // On the beat if this frame is only a little late for it; from
            // now if the rings are starting up again.
            var born = now - ripple.next < gap ? ripple.next : now;
            ripple.rings.push(born);
            ripple.next = born + gap;
        }
        return ripple.on || ripple.rings.length > 0;
    }
    // How far out each live ring is, newest first, in marker radii.
    function rippleRadii(now) {
        var out = [];
        for (var i = ripple.rings.length - 1; i >= 0; i--) out.push(RIPPLE.from + RIPPLE.speed * (now - ripple.rings[i]) / 1000);
        return out;
    }

    function ink(name) {
        var d = PAINT[name], n = NIGHT[name];
        if (n == null || night <= 0) return d;
        if (typeof d === 'number') return d + (n - d) * night;
        var out = [];
        for (var i = 0; i < d.length; i++) out.push(d[i] + ((n[i] != null ? n[i] : d[i]) - d[i]) * night);
        return out;
    }

    var PANEL_H = 115;          // the panel height every size above is measured on
    var canvas, gl, world, glFailed = false;
    var progs = {}, layers = {}, bld, groundTex, uiTex, atlasTex, atlas;
    var routeBuf, routeCount = 0, routes = [];
    var spriteBuf, spriteData = new Float32Array(8 * 6 * 512);
    var blips = [], fixed = [], moving = [], routeSrc = [], ends = [];
    var booted = false;
    var shown = false, wanted = false, loaded = false, dirty = false, queued = false;
    var pos = { x: 0, y: 0, c: 0, h: 0, s: 0 };
    var zoomNow = -1, lastDraw = 0;

    function post(name, data) {
        try {
            var res = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'vice_hud';
            fetch('https://' + res + '/' + name, { method: 'POST', body: JSON.stringify(data || {}) }).catch(function () {});
        } catch (e) { /* a browser preview has nobody to tell */ }
    }

    // An empty Lua table crosses to the page as {} as readily as [], so a
    // list is only ever taken as one when it is one.
    function list(v) { return Array.isArray(v) ? v : []; }

    function merge(into, from) {
        if (!from) return;
        Object.keys(from).forEach(function (k) {
            if (from[k] && typeof from[k] === 'object' && !Array.isArray(from[k]) && typeof into[k] === 'object') merge(into[k], from[k]);
            else if (from[k] != null) into[k] = from[k];
        });
    }

    /* --- shaders ----------------------------------------------------------
       Every one of them places a world point the same way, so that part is
       written once. `u` is pixels to the right of the player, `g` pixels
       ahead; the divide by `w` is the slant. */
    var PLACE = [
        'uniform vec2 uCentre; uniform vec2 uRot; uniform float uScale;',
        'uniform vec2 uPanel; uniform vec2 uOrigin; uniform float uT;',
        'vec4 place(vec2 p, float lift) {',
        '    vec2 d = p - uCentre;',
        '    float u = uScale * (d.x * uRot.x + d.y * uRot.y);',
        '    float g = uScale * (d.y * uRot.x - d.x * uRot.y);',
        '    float w = 1.0 + uT * g;',
        '    float up = lift * (w < 1.0 ? w : 1.0);',
        '    float z = clamp((g + 1.5 * uPanel.y) / (8.0 * uPanel.y), 0.0, 1.0) * 2.0 - 1.0;',
        '    return vec4((2.0 * uOrigin.x / uPanel.x - 1.0) * w + 2.0 * u / uPanel.x,',
        '                (1.0 - 2.0 * uOrigin.y / uPanel.y) * w + 2.0 * (g + up) / uPanel.y,',
        '                z * w, w);',
        '}'
    ].join('\n');

    var SHADERS = {
        flat: {
            vs: PLACE + '\nlayout(location = 0) in vec2 aPos; out vec2 vFrom;' +
                'void main() { vFrom = aPos - uCentre; gl_Position = place(aPos, 0.0); }',
            // Under the wanted flood a road is not a road: it is the flood.
            fs: 'in vec2 vFrom; uniform vec4 uColour; uniform vec4 uFlood; uniform vec2 uFloodEdge; out vec4 o;' +
                'void main() { float f = uFlood.a * (1.0 - smoothstep(uFloodEdge.x, uFloodEdge.y, length(vFrom)));' +
                ' o = vec4(mix(uColour.rgb, uFlood.rgb, f), mix(uColour.a, 1.0, f)); }'
        },
        ground: {
            vs: 'layout(location = 0) in vec2 aPos; void main() { gl_Position = vec4(aPos, 0.0, 1.0); }',
            fs: [
                'uniform vec2 uCentre; uniform vec2 uRot; uniform float uScale;',
                'uniform vec2 uPanel; uniform vec2 uOrigin; uniform float uT; uniform vec2 uMargin;',
                'uniform sampler2D uGround; uniform vec2 uGroundAt; uniform vec2 uGroundSize;',
                'uniform vec3 uLand; uniform vec3 uWater; uniform vec3 uSand; uniform float uAlpha;',
                'uniform vec4 uFlood; uniform vec2 uFloodEdge;',
                'out vec4 o;',
                'float edge(float v) { float e = max(fwidth(v) * 0.7, 0.02); return smoothstep(0.5 - e, 0.5 + e, v); }',
                'void main() {',
                '    vec2 f = gl_FragCoord.xy - uMargin;',
                '    float q = uOrigin.y - (uPanel.y - f.y);',
                '    float k = max(1.0 - uT * q, 0.001);',
                '    float g = q / k;',
                '    float u = (f.x - uOrigin.x) / k;',
                '    vec2 p = uCentre + vec2(u * uRot.x - g * uRot.y, u * uRot.y + g * uRot.x) / uScale;',
                '    vec2 uv = (p - uGroundAt) / uGroundSize;',
                '    vec2 t = texture(uGround, uv).rg;',
                // Past the survey's edge there is only sea.
                '    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) t = vec2(1.0, 0.0);',
                '    vec3 c = mix(uLand, uSand, edge(t.g));',
                '    c = mix(c, uWater, edge(t.r));',
                '    c = mix(c, uFlood.rgb, uFlood.a * (1.0 - smoothstep(uFloodEdge.x, uFloodEdge.y, length(p - uCentre))));',
                '    o = vec4(c * uAlpha, uAlpha);',
                '}'
            ].join('\n')
        },
        route: {
            vs: PLACE + '\nlayout(location = 0) in vec2 aPos; layout(location = 1) in vec2 aOff; layout(location = 2) in float aAlong;' +
                'layout(location = 3) in vec2 aTan; uniform float uHalf; uniform float uZ; out float vAlong;' +
                // How far along the line this vertex is -- for a round join,
                // including how far forward of its centre the vertex sits.
                'void main() { vAlong = aAlong + dot(aOff, aTan) * uHalf; gl_Position = place(aPos + aOff * uHalf, 0.0);' +
                ' gl_Position.z = uZ * gl_Position.w; }',
            // Nothing of the line is drawn behind the player, and it comes in
            // gradually ahead of them.
            fs: 'in float vAlong; uniform float uStart; uniform float uFade; uniform vec4 uColour; out vec4 o;' +
                'void main() { float a = smoothstep(uStart, uStart + uFade, vAlong); if (a < 0.004) discard; o = vec4(uColour.rgb, a); }'
        },
        building: {
            vs: PLACE + [
                '',
                'layout(location = 0) in vec4 aVert; layout(location = 1) in float aOwner;',
                'uniform float uLift; uniform float uLiftCap; uniform float uInside;',
                'uniform vec3 uRoof; uniform vec3 uWall; out vec3 vColour; out float vFade; out vec2 vFrom;',
                'void main() {',
                '    vFade = abs(aOwner - uInside) < 0.5 ? 1.0 : 0.0;',
                '    vFrom = aVert.xy - uCentre;',
                '    float h = aVert.z * uScale * uLift;',
                '    h = h / (1.0 + h / uLiftCap);',
                '    gl_Position = place(aVert.xy, h);',
                '    if (aVert.w > 8.0) { vColour = uRoof; }',
                '    else {',
                '        vec2 n = vec2(cos(aVert.w), sin(aVert.w));',
                '        float nx = n.x * uRot.x + n.y * uRot.y;',
                '        float ny = n.y * uRot.x - n.x * uRot.y;',
                '        float lum = 0.72 + 0.3 * (0.5 + 0.5 * (-0.75 * nx - 0.35 * ny));',
                '        vColour = uWall * lum * (aVert.z > 0.01 ? 1.0 : 0.95);',
                '    }',
                '}'
            ].join('\n'),
            fs: [
                'in vec3 vColour; in float vFade; in vec2 vFrom; uniform vec2 uPanel; uniform vec2 uFadeAt; uniform vec2 uFadeSize;',
                'uniform float uFadeMin; uniform float uFadeNear; uniform float uAlpha; uniform vec2 uMargin;',
                'uniform vec4 uFlood; uniform vec2 uFloodEdge; out vec4 o;',
                'void main() {',
                '    vec2 p = vec2(gl_FragCoord.x - uMargin.x, uPanel.y - (gl_FragCoord.y - uMargin.y));',
                '    float d = length((p - uFadeAt) / uFadeSize);',
                '    float t = clamp((d - uFadeNear) / (1.0 - uFadeNear), 0.0, 1.0);',
                '    float a = uFadeMin + (1.0 - uFadeMin) * t * t * (3.0 - 2.0 * t);',
                '    float f = uFlood.a * (1.0 - smoothstep(uFloodEdge.x, uFloodEdge.y, length(vFrom)));',
                '    o = vec4(mix(vColour, uFlood.rgb, f) * uAlpha, mix(1.0, a, vFade));',
                '}'
            ].join('\n')
        },
        // A roof's shadow: the roof again, on the ground, pushed down and right.
        // Drawn at one fixed depth, so where a building's shadows overlap the
        // ground is darkened once and not once per layer.
        shadow: {
            vs: PLACE + [
                '',
                'layout(location = 0) in vec4 aVert; uniform float uLift; uniform float uLiftCap; uniform float uShadowMax;',
                'void main() {',
                '    float h = aVert.z * uScale * uLift;',
                '    h = min(h / (1.0 + h / uLiftCap), uShadowMax);',
                '    gl_Position = place(aVert.xy, 0.0);',
                '    float k = min(1.0 / gl_Position.w, 1.0);',
                '    gl_Position.xy += vec2(0.55, -0.3) * h * k * 2.0 / uPanel * gl_Position.w;',
                '    gl_Position.z = 0.0;',
                '}'
            ].join('\n'),
            fs: 'uniform vec4 uColour; out vec4 o; void main() { o = uColour; }'
        },
        // Rounds the panel's corners off: everything outside the outline is
        // multiplied away, with the edge itself left soft.
        corners: {
            vs: 'layout(location = 0) in vec2 aPos; void main() { gl_Position = vec4(aPos, 0.0, 1.0); }',
            fs: 'uniform vec2 uPanel; uniform vec2 uMargin; uniform float uCorner; out vec4 o;' +
                'void main() { vec2 q = abs(gl_FragCoord.xy - uMargin - uPanel * 0.5) - (uPanel * 0.5 - uCorner);' +
                ' float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - uCorner; o = vec4(clamp(0.5 - d, 0.0, 1.0)); }'
        },
        // The rings round the player's marker. Every pixel asks how far it is
        // from the marker, in marker radii, and adds up what each live ring
        // puts there: a thin soft line, and a faint wash on its inner side.
        // Worked out per pixel so a ring keeps its thinness as it grows.
        ripple: {
            vs: 'layout(location = 0) in vec2 aPos; void main() { gl_Position = vec4(aPos, 0.0, 1.0); }',
            fs: 'uniform vec2 uAt; uniform float uR; uniform float uRings[6]; uniform vec4 uColour; uniform vec2 uSpan; uniform vec3 uLine; out vec4 o;' +
                'void main() { float d = length(gl_FragCoord.xy - uAt) / uR, a = 0.0;' +
                ' if (d > uSpan.y + 4.0 * uLine.x) discard;' +
                ' for (int i = 0; i < 6; i++) { float r = uRings[i]; if (r <= 0.0) continue;' +
                '  float x = d - r, line = exp(-x * x / (uLine.x * uLine.x));' +
                '  float wake = x < 0.0 ? uLine.y * clamp(1.0 + x / uLine.z, 0.0, 1.0) : 0.0;' +
                '  a += max(line, wake) * clamp((uSpan.y - r) / (uSpan.y - uSpan.x), 0.0, 1.0); }' +
                ' a = min(a, 1.0) * uColour.a; o = vec4(uColour.rgb * a, a); }'
        },
        sprite: {
            vs: 'layout(location = 0) in vec2 aPx; layout(location = 1) in vec2 aUv; layout(location = 2) in vec4 aTint; uniform vec2 uPanel; out vec2 vUv; out vec4 vTint;' +
                'void main() { vUv = aUv; vTint = aTint; gl_Position = vec4(2.0 * aPx.x / uPanel.x - 1.0, 1.0 - 2.0 * aPx.y / uPanel.y, 0.0, 1.0); }',
            fs: 'in vec2 vUv; in vec4 vTint; uniform sampler2D uTex; out vec4 o;' +
                'void main() { vec4 t = texture(uTex, vUv); o = vec4(t.rgb * vTint.rgb, t.a) * vTint.a; }'
        }
    };

    function compile(name) {
        var src = SHADERS[name];
        function sh(type, body) {
            var s = gl.createShader(type);
            gl.shaderSource(s, '#version 300 es\nprecision highp float;\n' + body);
            gl.compileShader(s);
            if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(name + ': ' + gl.getShaderInfoLog(s));
            return s;
        }
        var p = gl.createProgram();
        gl.attachShader(p, sh(gl.VERTEX_SHADER, src.vs));
        gl.attachShader(p, sh(gl.FRAGMENT_SHADER, src.fs));
        gl.linkProgram(p);
        if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(name + ': ' + gl.getProgramInfoLog(p));
        var u = {}, n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
        for (var i = 0; i < n; i++) {
            var info = gl.getActiveUniform(p, i);
            u[info.name] = gl.getUniformLocation(p, info.name);
        }
        return { p: p, u: u };
    }

    /* --- the world -------------------------------------------------------- */

    function parseWorld(buf) {
        var dv = new DataView(buf);
        if (dv.getUint32(0, true) !== 0x314d4856) throw new Error('world.bin: not a map');   // "VHM1"
        var headLen = dv.getUint32(4, true);
        var head = JSON.parse(new TextDecoder().decode(new Uint8Array(buf, 8, headLen)));
        var base = 8 + headLen;
        head.f32 = function (r) { return new Float32Array(buf, base + r.at, r.n); };
        head.u32 = function (r) { return new Uint32Array(buf, base + r.at, r.n); };
        return head;
    }

    function upload(target, data) {
        var b = gl.createBuffer();
        gl.bindBuffer(target, b);
        gl.bufferData(target, data, gl.STATIC_DRAW);
        return b;
    }

    function buildWorld(head) {
        world = head;
        Object.keys(head.layers).forEach(function (name) {
            var L = head.layers[name];
            var vao = gl.createVertexArray();
            gl.bindVertexArray(vao);
            upload(gl.ARRAY_BUFFER, head.f32(L.xy));
            gl.enableVertexAttribArray(0);
            gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
            upload(gl.ELEMENT_ARRAY_BUFFER, head.u32(L.tri));
            layers[name] = { vao: vao, starts: head.u32(L.starts) };
        });
        if (head.buildings) {
            var B = head.buildings;
            var verts = upload(gl.ARRAY_BUFFER, head.f32(B.verts));
            bld = {};
            ['roof', 'wall'].forEach(function (part) {
                var vao = gl.createVertexArray();
                gl.bindVertexArray(vao);
                gl.bindBuffer(gl.ARRAY_BUFFER, verts);
                gl.enableVertexAttribArray(0);
                gl.vertexAttribPointer(0, 4, gl.FLOAT, false, 20, 0);
                gl.enableVertexAttribArray(1);
                gl.vertexAttribPointer(1, 1, gl.FLOAT, false, 20, 16);
                upload(gl.ELEMENT_ARRAY_BUFFER, head.u32(B[part]));
                bld[part] = { vao: vao, starts: head.u32(B[part + 'Starts']) };
            });
            bld.verts = head.f32(B.verts);
            bld.roofTris = head.u32(B.roof);
        }
        gl.bindVertexArray(null);
    }

    function texture(image, smooth) {
        var t = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, t);
        gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, smooth ? gl.LINEAR_MIPMAP_LINEAR : gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        if (smooth) gl.generateMipmap(gl.TEXTURE_2D);
        return t;
    }

    function loadImage(src) {
        return new Promise(function (ok, bad) {
            var im = new Image();
            im.onload = function () { ok(im); };
            im.onerror = function () { bad(new Error(src + ' would not load')); };
            im.src = src;
        });
    }

    /* The three things drawn that are not the island: the player, the north
       badge and a plain dot. Painted once, at a size no screen will outgrow.
       The player is the marker measured off the reference footage -- the same
       one tools/minimap_marker puts into the game's own minimap. */
    var UI = { cell: 128, cells: 5, player: 0, north: 1, dot: 2, ring: 3, pin: 4 };
    function paintUi() {
        var c = document.createElement('canvas');
        c.width = UI.cell * UI.cells; c.height = UI.cell;
        var x = c.getContext('2d'), R = UI.cell * 0.46, m = UI.cell / 2;

        x.fillStyle = '#000000'; x.beginPath(); x.arc(m, m, R, 0, 7); x.fill();
        x.fillStyle = '#322b2c'; x.beginPath(); x.arc(m, m, R * 0.818, 0, 7); x.fill();
        x.fillStyle = '#ebd9dd'; x.beginPath();
        x.moveTo(m, m - 0.51 * R); x.lineTo(m + 0.425 * R, m + 0.365 * R);
        x.lineTo(m, m + 0.245 * R); x.lineTo(m - 0.425 * R, m + 0.365 * R);
        x.closePath(); x.fill();

        var nx = UI.cell + m;
        x.fillStyle = '#0c0b0d'; x.beginPath(); x.arc(nx, m, R, 0, 7); x.fill();
        x.fillStyle = '#ffffff';
        x.font = '700 ' + Math.round(R * 1.25) + 'px Arial, sans-serif';
        x.textAlign = 'center'; x.textBaseline = 'middle';
        x.fillText('N', nx, m + R * 0.06);

        var dx = UI.cell * 2 + m;
        x.fillStyle = 'rgba(0,0,0,0.55)'; x.beginPath(); x.arc(dx, m, R, 0, 7); x.fill();
        x.fillStyle = '#ffffff'; x.beginPath(); x.arc(dx, m, R * 0.8, 0, 7); x.fill();

        // The ring round a route's end, measured off the reference: four arcs
        // of about 66 degrees, up, right, down and left, light with a dark
        // edge all round. White here; the tint makes it the route's colour
        // and leaves the edge dark.
        var rx = UI.cell * 3 + m, span = 66 * Math.PI / 180, k;
        x.lineCap = 'butt';
        for (k = 0; k < 4; k++) {
            var mid = k * Math.PI / 2 - Math.PI / 2;
            x.strokeStyle = '#000000'; x.lineWidth = R * 0.215;
            x.beginPath(); x.arc(rx, m, R * 0.885, mid - span / 2 - 0.05, mid + span / 2 + 0.05); x.stroke();
            x.strokeStyle = '#ffffff'; x.lineWidth = R * 0.115;
            x.beginPath(); x.arc(rx, m, R * 0.885, mid - span / 2, mid + span / 2); x.stroke();
        }

        // And what sits in it when the route ends on open ground: a disc, dark
        // edged, to be tinted the route's colour.
        var px = UI.cell * 4 + m;
        x.fillStyle = '#000000'; x.beginPath(); x.arc(px, m, R, 0, 7); x.fill();
        x.fillStyle = '#ffffff'; x.beginPath(); x.arc(px, m, R * 0.84, 0, 7); x.fill();
        return c;
    }

    function boot() {
        if (booted) return;
        booted = true;
        canvas = document.getElementById('map3d');
        if (!canvas) return;
        gl = canvas.getContext('webgl2', { alpha: true, premultipliedAlpha: true, antialias: true, depth: true, stencil: false });
        if (!gl) { glFailed = true; post('map3dReady', { ok: false, why: 'this browser has no WebGL2' }); return; }

        try {
            Object.keys(SHADERS).forEach(function (n) { progs[n] = compile(n); });
        } catch (e) { glFailed = true; post('map3dReady', { ok: false, why: String(e.message || e) }); return; }

        var quad = gl.createVertexArray();
        gl.bindVertexArray(quad);
        upload(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]));
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
        progs.quad = quad;

        var rv = gl.createVertexArray();
        gl.bindVertexArray(rv);
        routeBuf = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, routeBuf);
        gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 28, 0);
        gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 28, 8);
        gl.enableVertexAttribArray(2); gl.vertexAttribPointer(2, 1, gl.FLOAT, false, 28, 16);
        gl.enableVertexAttribArray(3); gl.vertexAttribPointer(3, 2, gl.FLOAT, false, 28, 20);
        progs.routeVao = rv;

        var sv = gl.createVertexArray();
        gl.bindVertexArray(sv);
        spriteBuf = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, spriteBuf);
        gl.bufferData(gl.ARRAY_BUFFER, spriteData.byteLength, gl.DYNAMIC_DRAW);
        gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 32, 0);
        gl.enableVertexAttribArray(1); gl.vertexAttribPointer(1, 2, gl.FLOAT, false, 32, 8);
        gl.enableVertexAttribArray(2); gl.vertexAttribPointer(2, 4, gl.FLOAT, false, 32, 16);
        progs.spriteVao = sv;
        gl.bindVertexArray(null);

        uiTex = texture(paintUi(), true);
        setRoutes(routeSrc);

        fetch('map3d/world.bin')
            .then(function (r) { if (!r.ok) throw new Error('map3d/world.bin is not there: build it with tools/map3d/build.py'); return r.arrayBuffer(); })
            .then(function (buf) {
                var head = parseWorld(buf);
                buildWorld(head);
                return loadImage('map3d/' + head.ground.file);
            })
            .then(function (im) {
                gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
                groundTex = texture(im, true);
                loaded = true;
                post('map3dReady', { ok: true });
                setShown(wanted);
            })
            .catch(function (e) { post('map3dReady', { ok: false, why: String(e.message || e) }); });

        // The blip pictures are optional: without them a blip is a dot.
        fetch('map3d/blips.json')
            .then(function (r) { if (!r.ok) throw 0; return r.json(); })
            .then(function (j) { return loadImage('map3d/' + j.file).then(function (im) { atlas = j; atlasTex = texture(im, true); invalidate(); }); })
            .catch(function () {});

        if (typeof ResizeObserver === 'function') new ResizeObserver(function () { cornerCss = -1; invalidate(); }).observe(canvas);
    }

    /* --- a frame ---------------------------------------------------------- */

    var snapNext = false;      // the next frame jumps to the end of any fade

    function invalidate() {
        dirty = true;
        if (queued || !shown || !loaded || !gl) return;
        queued = true;
        requestAnimationFrame(frame);
    }

    // The canvas is a tenth of the panel's height bigger than the panel on
    // every side, so a blip pinned to the edge can sit across it the way the
    // reference's do. style.css makes it so; this is the same sum backwards.
    var OVERHANG = 0.1;
    var cornerCss = -1;

    function view(Wc, Hc, dt) {
        var m = Math.round(Hc * OVERHANG / (1 + 2 * OVERHANG)), H = Hc - 2 * m, W = Wc - 2 * m;
        var unit = H / PANEL_H;
        var target = VIEW.zoom * (1 - VIEW.speedZoom * Math.min(1, pos.s / VIEW.speedFull));
        zoomNow = zoomNow < 0 ? target : zoomNow + (target - zoomNow) * (1 - Math.exp(-dt * VIEW.zoomEase));
        var rad = pos.c * Math.PI / 180;
        var oy = H * VIEW.anchor;
        if (cornerCss < 0) cornerCss = parseFloat(getComputedStyle(canvas).letterSpacing) || 0;
        var corner = canvas.clientHeight ? cornerCss * Hc / canvas.clientHeight : 0;
        return { W: W, H: H, Wc: Wc, Hc: Hc, m: m, corner: corner, unit: unit, s: zoomNow * unit,
                 cos: Math.cos(rad), sin: Math.sin(rad), ox: W / 2, oy: oy, T: VIEW.tilt / oy, rad: rad };
    }

    function shared(prog, V) {
        var u = prog.u;
        gl.useProgram(prog.p);
        gl.uniform2f(u.uCentre, pos.x, pos.y);
        gl.uniform2f(u.uRot, V.cos, V.sin);
        gl.uniform1f(u.uScale, V.s);
        gl.uniform2f(u.uPanel, V.W, V.H);
        gl.uniform2f(u.uMargin, V.m, V.m);
        gl.uniform2f(u.uOrigin, V.ox, V.oy);
        gl.uniform1f(u.uT, V.T);
        return u;
    }

    // Which squares of the world can be on the panel: everything within reach
    // of its far top corners, and one square more for what stands tall.
    function reach(V) {
        var far = 1 / Math.max(0.05, 1 - VIEW.tilt);
        var r = Math.hypot(V.oy * far, V.W / 2 * far) / V.s + world.chunk;
        var b = world.bounds, c = world.chunk;
        return {
            x0: Math.max(0, Math.floor((pos.x - r - b[0]) / c)), x1: Math.min(world.gw - 1, Math.floor((pos.x + r - b[0]) / c)),
            y0: Math.max(0, Math.floor((pos.y - r - b[1]) / c)), y1: Math.min(world.gh - 1, Math.floor((pos.y + r - b[1]) / c))
        };
    }

    function drawChunks(mesh, R) {
        if (R.x1 < R.x0) return;
        gl.bindVertexArray(mesh.vao);
        for (var cy = R.y0; cy <= R.y1; cy++) {
            var from = mesh.starts[cy * world.gw + R.x0], to = mesh.starts[cy * world.gw + R.x1 + 1];
            if (to > from) gl.drawElements(gl.TRIANGLES, to - from, gl.UNSIGNED_INT, from * 4);
        }
    }

    // Which building the player is inside, or -1. Only that one is seen
    // through around the marker; the rest of the street stays solid. Looked up
    // again once the player has moved half a metre, over the roofs of the
    // squares around them.
    var inside = { x: 1e9, y: 1e9, id: -1 };
    function standingIn() {
        if (Math.abs(pos.x - inside.x) + Math.abs(pos.y - inside.y) < 0.5) return inside.id;
        inside.x = pos.x; inside.y = pos.y; inside.id = -1;
        var b = world.bounds, c = world.chunk, v = bld.verts, t = bld.roofTris, s = bld.roof.starts;
        var cx = Math.floor((pos.x - b[0]) / c), cy = Math.floor((pos.y - b[1]) / c), px = pos.x, py = pos.y;
        for (var y = Math.max(0, cy - 1); y <= Math.min(world.gh - 1, cy + 1); y++) {
            var x0 = Math.max(0, cx - 1), x1 = Math.min(world.gw - 1, cx + 1);
            if (x1 < x0) continue;
            for (var i = s[y * world.gw + x0], end = s[y * world.gw + x1 + 1]; i < end; i += 3) {
                var a = t[i] * 5, d = t[i + 1] * 5, e = t[i + 2] * 5;
                var d1 = (px - v[d]) * (v[a + 1] - v[d + 1]) - (v[a] - v[d]) * (py - v[d + 1]);
                var d2 = (px - v[e]) * (v[d + 1] - v[e + 1]) - (v[d] - v[e]) * (py - v[e + 1]);
                var d3 = (px - v[a]) * (v[e + 1] - v[a + 1]) - (v[e] - v[a]) * (py - v[a + 1]);
                if (!((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))) { inside.id = v[a + 4]; return inside.id; }
            }
        }
        return -1;
    }

    function frame(now) {
        queued = false;
        if (!shown || !loaded || !dirty) return;
        dirty = false;

        var dpr = window.devicePixelRatio || 1;
        var W = Math.max(2, Math.round(canvas.clientWidth * dpr)), H = Math.max(2, Math.round(canvas.clientHeight * dpr));
        if (canvas.width !== W || canvas.height !== H) { canvas.width = W; canvas.height = H; }
        var dt = Math.min(0.25, lastDraw ? (now - lastDraw) / 1000 : 0.25);
        var fading = stepFlood(dt, snapNext);
        var rippling = stepRipple(now);
        snapNext = false;
        var floodEdge = [POLICE.radius - POLICE.soft, POLICE.radius];
        lastDraw = now;
        var V = view(W, H, dt), A = VIEW.opacity, R = reach(V), u;

        gl.disable(gl.SCISSOR_TEST);
        gl.clearColor(0, 0, 0, 0);
        gl.clearDepth(1);
        gl.depthMask(true);
        gl.colorMask(true, true, true, true);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        gl.disable(gl.DEPTH_TEST);
        // The island is drawn into the panel and nowhere else.
        gl.viewport(V.m, V.m, V.W, V.H);
        gl.scissor(V.m, V.m, V.W, V.H);
        gl.enable(gl.SCISSOR_TEST);
        gl.disable(gl.BLEND);

        // The ground: land, with the survey's sand and sea over it.
        u = shared(progs.ground, V);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, groundTex);
        gl.uniform1i(u.uGround, 0);
        gl.uniform2f(u.uGroundAt, world.ground.x0, world.ground.y0);
        gl.uniform2f(u.uGroundSize, world.ground.w * world.ground.cell, world.ground.h * world.ground.cell);
        var land = ink('land'), water = ink('water'), sand = ink('sand');
        gl.uniform3f(u.uLand, land[0] / 255, land[1] / 255, land[2] / 255);
        gl.uniform3f(u.uWater, water[0] / 255, water[1] / 255, water[2] / 255);
        gl.uniform3f(u.uSand, sand[0] / 255, sand[1] / 255, sand[2] / 255);
        gl.uniform4f(u.uFlood, flood.rgb[0] / 255, flood.rgb[1] / 255, flood.rgb[2] / 255, flood.cover);
        gl.uniform2f(u.uFloodEdge, floodEdge[0], floodEdge[1]);
        gl.uniform1f(u.uAlpha, A);
        gl.bindVertexArray(progs.quad);
        gl.drawArrays(gl.TRIANGLES, 0, 3);

        // From here the panel's own see-through is settled; nothing below
        // changes it, so what is drawn over the ground replaces it cleanly.
        gl.colorMask(true, true, true, false);
        gl.enable(gl.BLEND);
        gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        u = shared(progs.flat, V);
        gl.uniform4f(u.uFlood, flood.rgb[0] / 255 * A, flood.rgb[1] / 255 * A, flood.rgb[2] / 255 * A, flood.cover);
        gl.uniform2f(u.uFloodEdge, floodEdge[0], floodEdge[1]);
        ['footprint', 'rail', 'road', 'bridge', 'lot', 'lane'].forEach(function (name) {
            if (!layers[name]) return;
            var c = ink(name === 'bridge' ? 'road' : name);
            gl.uniform4f(u.uColour, c[0] / 255 * A, c[1] / 255 * A, c[2] / 255 * A, c.length > 3 ? c[3] : 1);
            drawChunks(layers[name], R);
        });

        if (routeCount) {
            u = shared(progs.route, V);
            gl.bindVertexArray(progs.routeVao);
            var half = Math.max(VIEW.route.lane, VIEW.route.minWidth * V.unit / V.s) / 2;
            // The line is made of overlapping pieces. Depth lets each pixel be
            // painted by one of them only, so where it is fading in it fades
            // evenly and not in patches: the rim first, then the fill nearer.
            gl.enable(gl.DEPTH_TEST);
            gl.depthFunc(gl.LESS);
            gl.uniform1f(u.uFade, Math.max(0.01, VIEW.route.fade));
            routes.forEach(function (r) {
                var rim = r.rim, fill = r.rgb;
                gl.uniform1f(u.uStart, r.head ? startOf(r, pos.x, pos.y) + VIEW.route.gap : -1e6);
                gl.uniform1f(u.uZ, 0.2);
                gl.uniform1f(u.uHalf, half + VIEW.route.rim * V.unit / V.s);
                gl.uniform4f(u.uColour, rim[0] / 255 * A, rim[1] / 255 * A, rim[2] / 255 * A, 1);
                gl.drawArrays(gl.TRIANGLES, r.from, r.count);
                gl.uniform1f(u.uZ, 0.0);
                gl.uniform1f(u.uHalf, half);
                gl.uniform4f(u.uColour, fill[0] / 255 * A, fill[1] / 255 * A, fill[2] / 255 * A, 1);
                gl.drawArrays(gl.TRIANGLES, r.from, r.count);
                gl.clear(gl.DEPTH_BUFFER_BIT);
            });
            gl.disable(gl.DEPTH_TEST);
        }

        if (bld && VIEW.buildings !== false) {
            var cap = VIEW.liftCap * V.unit;
            u = shared(progs.shadow, V);
            gl.uniform1f(u.uLift, VIEW.lift);
            gl.uniform1f(u.uLiftCap, cap);
            gl.uniform1f(u.uShadowMax, 20 * V.unit);
            gl.uniform4f(u.uColour, 0, 0, 0, ink('shadow'));
            gl.enable(gl.DEPTH_TEST);
            gl.depthFunc(gl.LESS);
            drawChunks(bld.roof, R);
            gl.clear(gl.DEPTH_BUFFER_BIT);

            // Depth first, colour second: whatever is nearest at a pixel is
            // laid over the ground once, however many walls stand behind it.
            u = shared(progs.building, V);
            gl.uniform1f(u.uLift, VIEW.lift);
            gl.uniform1f(u.uLiftCap, cap);
            var roof = ink('roof'), wall = ink('wall');
            gl.uniform3f(u.uRoof, roof[0] / 255, roof[1] / 255, roof[2] / 255);
            gl.uniform3f(u.uWall, wall[0] / 255, wall[1] / 255, wall[2] / 255);
            gl.uniform2f(u.uFadeAt, V.ox, V.oy - VIEW.fade.up * V.unit);
            gl.uniform2f(u.uFadeSize, VIEW.fade.rx * V.unit, VIEW.fade.ry * V.unit);
            gl.uniform1f(u.uFadeMin, VIEW.fade.min);
            gl.uniform1f(u.uFadeNear, VIEW.fade.near);
            gl.uniform1f(u.uAlpha, A);
            gl.uniform1f(u.uInside, standingIn());
            gl.uniform4f(u.uFlood, flood.rgb[0] / 255, flood.rgb[1] / 255, flood.rgb[2] / 255, flood.cover * POLICE.buildings);
            gl.uniform2f(u.uFloodEdge, floodEdge[0], floodEdge[1]);
            gl.colorMask(false, false, false, false);
            drawChunks(bld.roof, R); drawChunks(bld.wall, R);
            gl.colorMask(true, true, true, false);
            gl.depthFunc(gl.EQUAL);
            gl.depthMask(false);
            drawChunks(bld.roof, R); drawChunks(bld.wall, R);
            gl.depthMask(true);
            gl.disable(gl.DEPTH_TEST);
        }

        gl.colorMask(true, true, true, true);
        gl.blendFunc(gl.ZERO, gl.SRC_ALPHA);
        u = shared(progs.corners, V);
        gl.uniform1f(u.uCorner, V.corner);
        gl.bindVertexArray(progs.quad);
        gl.drawArrays(gl.TRIANGLES, 0, 3);

        gl.disable(gl.SCISSOR_TEST);
        gl.viewport(0, 0, W, H);
        drawSprites(V, now);
        gl.bindVertexArray(null);
        // A fade has to be carried through even if the player is standing
        // still, and the rings keep moving for as long as there are any.
        if (fading || rippling) invalidate();
    }

    /* --- what sits on top: blips, north, the player ----------------------- */

    function project(V, x, y) {
        var dx = x - pos.x, dy = y - pos.y;
        var u = V.s * (dx * V.cos + dy * V.sin), g = V.s * (dy * V.cos - dx * V.sin);
        var w = 1 + V.T * g;
        return { u: u, g: g, w: w, x: V.ox + u / w, y: V.oy - g / w };
    }

    // Distance outside the panel's rounded outline (negative inside).
    function outline(V, x, y, r) {
        var qx = Math.abs(x - V.W / 2) - (V.W / 2 - r), qy = Math.abs(y - V.H / 2) - (V.H / 2 - r);
        return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
    }

    // Where a ray from the player meets the outline, `inset` pixels in.
    function edgePoint(V, dx, dy, r, inset) {
        var len = Math.hypot(dx, dy) || 1, lo = 0, hi = V.W + V.H;
        dx /= len; dy /= len;
        for (var i = 0; i < 18; i++) {
            var mid = (lo + hi) / 2;
            if (outline(V, V.ox + dx * mid, V.oy + dy * mid, r) < -inset) lo = mid; else hi = mid;
        }
        return { x: V.ox + dx * lo, y: V.oy + dy * lo };
    }

    var spriteN = 0;
    function sprite(cx, cy, size, rot, u0, v0, u1, v1, tint) {
        if (spriteN >= 512) return;
        var h = size / 2, c = Math.cos(rot), s = Math.sin(rot), o = spriteN * 48, d = spriteData;
        var corners = [[-h, -h, u0, v0], [h, -h, u1, v0], [h, h, u1, v1], [-h, -h, u0, v0], [h, h, u1, v1], [-h, h, u0, v1]];
        for (var i = 0; i < 6; i++) {
            var k = corners[i];
            d[o++] = cx + k[0] * c - k[1] * s; d[o++] = cy + k[0] * s + k[1] * c;
            d[o++] = k[2]; d[o++] = k[3];
            d[o++] = tint[0]; d[o++] = tint[1]; d[o++] = tint[2]; d[o++] = tint[3];
        }
        spriteN++;
    }

    function flush(tex, V) {
        if (!spriteN) return;
        gl.useProgram(progs.sprite.p);
        gl.uniform2f(progs.sprite.u.uPanel, V.Wc, V.Hc);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.uniform1i(progs.sprite.u.uTex, 0);
        gl.bindVertexArray(progs.spriteVao);
        gl.bindBuffer(gl.ARRAY_BUFFER, spriteBuf);
        gl.bufferSubData(gl.ARRAY_BUFFER, 0, spriteData.subarray(0, spriteN * 48));
        gl.drawArrays(gl.TRIANGLES, 0, spriteN * 6);
        spriteN = 0;
    }

    function uiCell(i) { return [i / UI.cells, 0, (i + 1) / UI.cells, 1]; }

    // The HUD's own panels sit on the map's top edge, so nothing pinned to the
    // edge is allowed to hang over that one: it would be half hidden.
    //
    // And the distance to the waypoint is written in the map's top-left corner,
    // which is exactly where a waypoint ahead and to the left gets pinned. So
    // a pinned thing that would land on the figure is slid out from under it,
    // along the top edge or down the side, whichever is the shorter way.
    var keepOut = null, keepOutAt = -1e9;
    function findKeepOut(V, now) {
        if (now - keepOutAt < 400) return;
        keepOutAt = now;
        keepOut = null;
        var el = document.getElementById('nav-compass');
        if (!el || el.classList.contains('hidden') || !el.offsetWidth || !canvas.clientHeight) return;
        var a = el.getBoundingClientRect(), c = canvas.getBoundingClientRect(), k = V.Hc / c.height;
        keepOut = { x0: (a.left - c.left) * k - V.m, y0: (a.top - c.top) * k - V.m,
                    x1: (a.right - c.left) * k - V.m, y1: (a.bottom - c.top) * k - V.m };
    }
    function clear(at, size) {
        var r = size * 0.46, x = at.x, y = Math.max(at.y, r), k = keepOut;
        if (k && x + r > k.x0 && x - r < k.x1 && y + r > k.y0 && y - r < k.y1) {
            var right = k.x1 + r - x, down = k.y1 + r - y;
            if (right <= down) x = k.x1 + r; else y = k.y1 + r;
        }
        return (x === at.x && y === at.y) ? at : { x: x, y: y };
    }

    // The rings stamina sends out, drawn under the marker so each one comes
    // out from behind its rim. Six is twice what the reference ever shows.
    var ringSlots = new Float32Array(6);
    function drawRipples(V, now) {
        var radii = rippleRadii(now), u = progs.ripple.u, i;
        if (!radii.length) return;
        for (i = 0; i < 6; i++) ringSlots[i] = i < radii.length ? radii[i] : 0;
        var R = 0.46 * VIEW.marker * V.unit;        // the marker's rim, as paintUi() draws it
        gl.useProgram(progs.ripple.p);
        gl.uniform2f(u.uAt, V.ox + V.m, V.Hc - (V.oy + V.m));
        gl.uniform1f(u.uR, R);
        gl.uniform1fv(u['uRings[0]'], ringSlots);
        gl.uniform4f(u.uColour, RIPPLE.rgb[0] / 255, RIPPLE.rgb[1] / 255, RIPPLE.rgb[2] / 255, RIPPLE.alpha);
        gl.uniform2f(u.uSpan, RIPPLE.from, RIPPLE.to);
        // Never thinner than the screen can show: under about a pixel and a
        // half across a ring breaks up into dashes as it grows.
        gl.uniform3f(u.uLine, Math.max(RIPPLE.width / 1.665, 0.7 / R), RIPPLE.wake, Math.max(0.01, RIPPLE.wakeLength));
        gl.bindVertexArray(progs.quad);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
    }

    function drawSprites(V, now) {
        gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
        var corner = V.corner, m = V.m;
        var size = VIEW.blip * V.unit, dots = [], marks = [], i, b, p, at, on, cell, cols, rows, cx, cy;
        findKeepOut(V, performance.now());

        // Where each route ends. Worked out first, because a blip standing on
        // one is drawn as part of it and not a second time beside it.
        for (i = 0; i < ends.length; i++) {
            p = project(V, ends[i].x, ends[i].y);
            on = p.w > 0.25 && outline(V, p.x, p.y, corner) < -size * 0.25;
            marks.push({ end: ends[i], at: on ? p : clear(edgePoint(V, p.u, -p.g, corner, 0), VIEW.end.ring * V.unit * 0.9) });
        }
        function taken(blip) {
            for (var k = 0; k < ends.length; k++) {
                if (ends[k].icon === blip[2] && Math.abs(ends[k].x - blip[0]) + Math.abs(ends[k].y - blip[1]) < 8) return true;
            }
            return false;
        }

        // Blips with a picture go first, in one batch; the rest are dots.
        for (i = 0; i < blips.length; i++) {
            b = blips[i];
            if (ends.length && taken(b)) continue;
            p = project(V, b[0], b[1]);
            on = p.w > 0.25 && outline(V, p.x, p.y, corner) < -size * 0.25;
            if (!on) {
                if (!(b[7] & 1)) continue;
                at = clear(edgePoint(V, p.u, -p.g, corner, 0), size * 0.8);
            } else at = p;
            var tint = [b[3] / 255, b[4] / 255, b[5] / 255, b[6] / 255];
            cell = atlas && atlas.cells[b[2]];
            if (cell == null) { dots.push([at.x, at.y, tint]); continue; }
            cols = atlas.cols; rows = atlas.rows; cx = cell % cols; cy = Math.floor(cell / cols);
            sprite(at.x + m, at.y + m, size, 0, cx / cols, cy / rows, (cx + 1) / cols, (cy + 1) / rows, tint);
        }
        // A route that ends at a place: the place's own picture in the ring.
        for (i = 0; i < marks.length; i++) {
            var e = marks[i].end;
            cell = (atlas && e.icon != null) ? atlas.cells[e.icon] : null;
            marks[i].pictured = cell != null;
            if (cell == null) continue;
            cols = atlas.cols; rows = atlas.rows; cx = cell % cols; cy = Math.floor(cell / cols);
            sprite(marks[i].at.x + m, marks[i].at.y + m, size, 0, cx / cols, cy / rows, (cx + 1) / cols, (cy + 1) / rows,
                   [e.iconRgb[0] / 255, e.iconRgb[1] / 255, e.iconRgb[2] / 255, 1]);
        }
        if (atlasTex) flush(atlasTex, V);

        var c = uiCell(UI.dot);
        for (i = 0; i < dots.length; i++) sprite(dots[i][0] + m, dots[i][1] + m, size * 0.62, 0, c[0], c[1], c[2], c[3], dots[i][2]);

        // The ring round a route's end: four arcs, as the reference marks a
        // destination. In it, the place's picture (above) or, for a waypoint
        // dropped on open ground, a plain disc in the route's colour.
        for (i = 0; i < marks.length; i++) {
            var end = marks[i].end, q = marks[i].at;
            if (!marks[i].pictured) {
                c = uiCell(UI.pin);
                sprite(q.x + m, q.y + m, VIEW.end.pin * V.unit, 0, c[0], c[1], c[2], c[3], [end.rgb[0] / 255, end.rgb[1] / 255, end.rgb[2] / 255, 1]);
            }
            c = uiCell(UI.ring);
            sprite(q.x + m, q.y + m, VIEW.end.ring * V.unit, 0, c[0], c[1], c[2], c[3], [end.ring[0] / 255, end.ring[1] / 255, end.ring[2] / 255, 1]);
        }

        // North gives way to a route's end: heading north, the two are pinned
        // to the same spot, and the destination is the one worth seeing.
        if (VIEW.north) {
            at = clear(edgePoint(V, Math.sin(V.rad), -Math.cos(V.rad), corner, 0), 10.8 * V.unit);
            var room = (VIEW.end.ring + 10.8) * V.unit * 0.5, crowded = false;
            for (i = 0; i < marks.length; i++) {
                if (Math.hypot(marks[i].at.x - at.x, marks[i].at.y - at.y) < room) crowded = true;
            }
            if (!crowded) {
                c = uiCell(UI.north);
                sprite(at.x + m, at.y + m, 10.8 * V.unit, 0, c[0], c[1], c[2], c[3], [1, 1, 1, 1]);
            }
        }
        flush(uiTex, V);
        drawRipples(V, now);
        c = uiCell(UI.player);
        sprite(V.ox + m, V.oy + m, VIEW.marker * V.unit, (pos.c - pos.h) * Math.PI / 180, c[0], c[1], c[2], c[3], [1, 1, 1, 1]);
        flush(uiTex, V);
    }

    /* --- the route -------------------------------------------------------- */

    // The game hands the line over as points along its road network: unevenly
    // spaced, a lane to one side where two stretches of road meet, and begun
    // at the last junction behind the player rather than at the player. Left
    // as it comes, that is a line with kinks in it and a tail. So:
    //
    //   tidy()     the same line as points two metres apart, then smoothed --
    //              hard where smoothing barely moves it (a lane's sidestep),
    //              lightly where it would cut a real corner off the road.
    //   startOf()  where along it the player is, found again every frame, so
    //              the line always begins under the marker and never behind.
    var ROUTE = { step: 2, heavy: 8, light: 3, look: 80, hook: 40, near: 12 };

    function resample(p, step) {
        var out = [p[0], p[1]], carry = 0;
        for (var i = 0; i + 3 < p.length; i += 2) {
            var ax = p[i], ay = p[i + 1], dx = p[i + 2] - ax, dy = p[i + 3] - ay, len = Math.hypot(dx, dy);
            if (len < 1e-6) continue;
            var t = step - carry;
            while (t <= len) { out.push(ax + dx * t / len, ay + dy * t / len); t += step; }
            carry = len - (t - step);
        }
        var n = out.length, lx = p[p.length - 2], ly = p[p.length - 1];
        if (Math.hypot(lx - out[n - 2], ly - out[n - 1]) > step * 0.25) out.push(lx, ly);
        return out;
    }

    // A Gaussian along the line. Past either end the line is carried on as its
    // own mirror image through the end point, which leaves the ends in place.
    function blur(p, sigma, step) {
        var n = p.length / 2, r = Math.max(1, Math.ceil(sigma * 2.5 / step)), k = [], out = new Array(p.length), i, j;
        for (j = -r; j <= r; j++) k.push(Math.exp(-0.5 * Math.pow(j * step / sigma, 2)));
        for (i = 0; i < n; i++) {
            var sx = 0, sy = 0, sw = 0;
            for (j = -r; j <= r; j++) {
                var q = i + j, x, y, w = k[j + r];
                if (q < 0) { q = Math.min(n - 1, -q); x = 2 * p[0] - p[q * 2]; y = 2 * p[1] - p[q * 2 + 1]; }
                else if (q >= n) { q = Math.max(0, 2 * (n - 1) - q); x = 2 * p[2 * n - 2] - p[q * 2]; y = 2 * p[2 * n - 1] - p[q * 2 + 1]; }
                else { x = p[q * 2]; y = p[q * 2 + 1]; }
                sx += x * w; sy += y * w; sw += w;
            }
            out[i * 2] = sx / sw; out[i * 2 + 1] = sy / sw;
        }
        return out;
    }

    function tidy(raw) {
        var p = [], i;
        for (i = 0; i + 1 < raw.length; i += 2) {
            if (!p.length || Math.hypot(raw[i] - p[p.length - 2], raw[i + 1] - p[p.length - 1]) > 0.05) p.push(raw[i], raw[i + 1]);
        }
        if (p.length < 4) return null;
        p = resample(p, ROUTE.step);
        var heavy = blur(p, ROUTE.heavy, ROUTE.step), light = blur(p, ROUTE.light, ROUTE.step);
        var n = p.length / 2, line = new Float32Array(n * 2), arc = new Float32Array(n);
        for (i = 0; i < n; i++) {
            // How far the hard smoothing would move this point: up to a couple
            // of metres is a sidestep or a merge being ironed out, five and
            // more is a corner being cut off the road.
            var moved = Math.hypot(heavy[i * 2] - p[i * 2], heavy[i * 2 + 1] - p[i * 2 + 1]);
            var t = Math.min(1, Math.max(0, (moved - 2.0) / 3.0)), w = t * t * (3 - 2 * t);
            line[i * 2] = heavy[i * 2] * (1 - w) + light[i * 2] * w;
            line[i * 2 + 1] = heavy[i * 2 + 1] * (1 - w) + light[i * 2 + 1] * w;
            if (i) arc[i] = arc[i - 1] + Math.hypot(line[i * 2] - line[i * 2 - 2], line[i * 2 + 1] - line[i * 2 - 1]);
        }
        return { line: line, arc: arc };
    }

    // How far along the line the player is. The nearest point, with one
    // exception: off the road the game's line first runs BACK to the road and
    // only then forward, passing the player a second time on its way. The line
    // should start at that second pass, so a later nearest-approach wins over
    // an earlier one -- but only close by and early on, or a route that loops
    // round the block would be cut short at the point it comes back past.
    function startOf(r, px, py) {
        var p = r.line, s = r.arc, n = s.length, best = 0, bestD = Infinity, pick = -1, i;
        function dsq(k) { var dx = p[k * 2] - px, dy = p[k * 2 + 1] - py; return dx * dx + dy * dy; }
        var before = Infinity, here = dsq(0), after;
        for (i = 0; i < n && s[i] <= ROUTE.look; i++) {
            after = i + 1 < n ? dsq(i + 1) : Infinity;
            if (here < bestD) { bestD = here; best = i; }
            if (here <= before && here < after && here <= ROUTE.near * ROUTE.near && s[i] <= ROUTE.hook) pick = i;
            before = here; here = after;
        }
        var at = pick >= 0 ? pick : best, out = s[at], near = dsq(at);
        // Between the points either side of it, exactly.
        [at - 1, at].forEach(function (k) {
            if (k < 0 || k + 1 >= n) return;
            var ax = p[k * 2], ay = p[k * 2 + 1], dx = p[k * 2 + 2] - ax, dy = p[k * 2 + 3] - ay, len = dx * dx + dy * dy;
            if (len < 1e-9) return;
            var t = Math.min(1, Math.max(0, ((px - ax) * dx + (py - ay) * dy) / len));
            var ex = ax + dx * t - px, ey = ay + dy * t - py, d = ex * ex + ey * ey;
            if (d <= near) { near = d; out = s[k] + (s[k + 1] - s[k]) * t; }
        });
        return out;
    }

    function setRoutes(src) {
        var v = [], FAN = 8;
        routeSrc = list(src);
        if (!gl) return;
        routes = [];
        routeSrc.forEach(function (r) {
            var made = tidy(list(r.pts));
            if (!made) return;
            var p = made.line, s = made.arc, n = s.length, from = v.length / 7;
            for (var i = 0; i < n; i++) {
                var x = p[i * 2], y = p[i * 2 + 1], d = s[i];
                // Which way the line is going here, for the round join.
                var i0 = Math.max(0, i - 1), i1 = Math.min(n - 1, i + 1);
                var tx = p[i1 * 2] - p[i0 * 2], ty = p[i1 * 2 + 1] - p[i0 * 2 + 1], tl = Math.hypot(tx, ty) || 1;
                tx /= tl; ty /= tl;
                for (var f = 0; f < FAN; f++) {
                    var a0 = f / FAN * 6.2832, a1 = (f + 1) / FAN * 6.2832;
                    v.push(x, y, 0, 0, d, tx, ty, x, y, Math.cos(a0), Math.sin(a0), d, tx, ty, x, y, Math.cos(a1), Math.sin(a1), d, tx, ty);
                }
                if (i + 1 >= n) break;
                var bx = p[i * 2 + 2], by = p[i * 2 + 3], dx = bx - x, dy = by - y, len = Math.hypot(dx, dy), e = s[i + 1];
                if (len < 1e-4) continue;
                var nx = -dy / len, ny = dx / len;
                v.push(x, y, nx, ny, d, 0, 0, x, y, -nx, -ny, d, 0, 0, bx, by, -nx, -ny, e, 0, 0,
                       x, y, nx, ny, d, 0, 0, bx, by, -nx, -ny, e, 0, 0, bx, by, nx, ny, e, 0, 0);
            }
            var rgb = list(r.rgb).length === 3 ? r.rgb : PAINT.route;
            routes.push({ from: from, count: v.length / 7 - from, line: p, arc: s, head: r.head === true,
                          rgb: rgb, rim: list(r.rim).length === 3 ? r.rim : lighten(rgb) });
        });
        routeCount = v.length / 7;
        gl.bindBuffer(gl.ARRAY_BUFFER, routeBuf);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(v), gl.DYNAMIC_DRAW);
    }

    function lighten(c) {
        return [c[0] + (255 - c[0]) * 0.45, c[1] + (255 - c[1]) * 0.45, c[2] + (255 - c[2]) * 0.45];
    }

    /* --- messages --------------------------------------------------------- */

    function setShown(on) {
        shown = on && !glFailed;
        if (canvas) canvas.classList.toggle('hidden', !(shown && loaded));
        if (shown) { zoomNow = -1; lastDraw = 0; cornerCss = -1; invalidate(); }
    }

    window.addEventListener('message', function (e) {
        var d = e.data;
        if (!d || typeof d.action !== 'string' || d.action.indexOf('map3d') !== 0) return;
        if (d.action === 'map3dPos') {
            pos.x = d.x; pos.y = d.y; pos.c = d.c; pos.h = d.h; pos.s = d.s || 0;
        } else if (d.action === 'map3d') {
            if (d.config) { merge(VIEW, d.config.view); merge(PAINT, d.config.paint); merge(NIGHT, d.config.paintNight); }
            if (typeof d.night === 'number') night = Math.min(1, Math.max(0, d.night));
            if (d.police !== undefined) setPolice(d.police);
            if (d.ripple !== undefined) setRipple(d.ripple);
            if (d.config) { merge(POLICE, d.config.police); merge(RIPPLE, d.config.ripple); }
            if (d.load || d.show) boot();
            if (d.show != null) { wanted = d.show === true; setShown(wanted); }
        } else if (d.action === 'map3dRoute') {
            setRoutes(d.routes);
            ends = list(d.ends).filter(function (e) { return e && typeof e.x === 'number' && typeof e.y === 'number'; }).map(function (e) {
                var rgb = list(e.rgb).length === 3 ? e.rgb : PAINT.route;
                var pictured = typeof e.icon === 'number' && list(e.iconRgb).length === 3;
                return { x: e.x, y: e.y, rgb: rgb, ring: list(e.ring).length === 3 ? e.ring : lighten(rgb),
                         icon: pictured ? e.icon : null, iconRgb: pictured ? e.iconRgb : null };
            });
        } else if (d.action === 'map3dBlips') {
            fixed = list(d.list);
            blips = fixed.concat(moving);
        } else if (d.action === 'map3dMoving') {
            moving = list(d.list);
            blips = fixed.concat(moving);
        }
        invalidate();
    });

    // For tests and the browser preview.
    window.ViceMap3D = {
        state: function () { return { booted: booted, shown: shown, loaded: loaded, failed: glFailed, zoom: zoomNow, routes: routes.length, ends: ends, night: night, flood: { rgb: flood.rgb.slice(), cover: flood.cover, to: flood.to }, blips: blips.length, hasAtlas: !!atlasTex }; },
        project: function (x, y) { var V = view(canvas.width, canvas.height, 0); return project(V, x, y); },
        // A frame right now, without waiting for the browser to offer one: a
        // page nobody is looking at is never offered any.
        draw: function () { dirty = true; queued = false; snapNext = true; frame(performance.now()); },
        POLICE: POLICE, stepFlood: stepFlood,
        // `rings` puts rings where a picture wants them: seconds since each was born.
        RIPPLE: RIPPLE, stepRipple: stepRipple, rippleRadii: rippleRadii,
        rippling: function () { return ripple.on; },
        rings: function (ages, now) { ripple.rings = ages.map(function (a) { return (now == null ? performance.now() : now) - a * 1000; }).sort(function (a, b) { return a - b; }); },
        route: { tidy: tidy, startOf: startOf },
        VIEW: VIEW, PAINT: PAINT, NIGHT: NIGHT, ink: ink
    };

    post('map3dHello');
})();
