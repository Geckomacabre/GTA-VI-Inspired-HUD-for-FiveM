// Preview harness: stands in for client/main.lua so the page can be looked at in a browser.
(function () {
    var q = new URLSearchParams(location.search);
    document.documentElement.style.background = '#000';
    var bg = document.createElement('div');
    bg.style.cssText = 'position:fixed;inset:-30px;background:url(img/' + (q.get('bg') || 'beach') + '.webp) center/cover;filter:blur(14px) brightness(.9);z-index:-1';
    document.body.prepend(bg);

    var tiles = [
        [{ id: 'map', label: 'Map', image: 'map', sub: 'Vespucci Beach' }, { id: 'brief', label: 'Brief', image: 'brief', sub: 'Mechanic' }],
        [{ id: 'stats', label: 'Stats', image: 'stats', sub: '' }, { id: 'editor', label: 'Rockstar Editor', image: 'editor', sub: 'Record a clip' },
         { id: 'game', label: 'Game', image: 'game', sub: 'Display / Audio / Controls' }, { id: 'settings', label: 'Settings', image: 'settings', sub: '' }],
        [{ id: 'players', label: 'Players', image: 'players', sub: '12 Online' }, { id: 'report', label: 'Report', image: 'report', sub: 'To staff' },
         { id: 'discord', label: 'Discord', image: 'discord', sub: 'Join us' }, { id: 'disconnect', label: 'Disconnect', image: 'disconnect', sub: 'Leave the server' }]
    ];

    var settings = {
        crashcam: { label: 'Crash Camera', image: 'crashcam', values: ['On', 'Off'], at: 0, desc: 'A slow replay from outside the car when you crash.' },
        mapmode: { label: 'Map Day/Night', image: 'mapnight', values: ['Auto', 'Day', 'Night'], at: 0, desc: 'The map by day, by night, or following the clock.' },
        minimap: { label: 'Map in Vehicle Only', image: 'mapvehicle', values: ['On', 'Off'], at: 1, desc: 'The minimap only while you are in a vehicle.' },
        radio: { label: 'Radio', image: 'radio', values: ['On', 'Off'], at: 0, desc: 'The radio in vehicles. Off mutes it.' },
        style: { label: 'Pause Menu', image: 'pausemenu', values: ['GTA VI', 'Classic'], at: 0, desc: "This menu, or the game's own pause menu. /pausemenu brings this one back." }
    };
    function settingRows() {
        var rows = Object.keys(settings).map(function (id) {
            var s = settings[id];
            return { id: id, label: s.label, value: s.values[s.at], image: s.image, title: s.label, desc: s.desc, change: true };
        });
        rows.push({ id: 'keybinds', label: 'Key Bindings', image: 'keybinds', title: 'Key Bindings', desc: "The keys of this server's actions.", action: true });
        rows.push({ id: 'gamesettings', label: 'Game Settings', image: 'gamesettings', title: 'Game Settings', desc: 'Display, graphics, audio and controls.', action: true });
        return rows;
    }
    var lists = {
        settings: { title: 'Settings', rows: settingRows },
        brief: { title: 'Brief', rows: function () {
            return [['Name', 'Lucia Caminos', 'Who you are on this server.'], ['Job', 'Mechanic', 'Grade: Apprentice'], ['On Duty', 'Yes', 'Whether you are on the clock.'],
                ['Cash', '$1,250', 'In your pocket.'], ['Bank', '$48,900', 'At BuckMe.'], ['Hunger', '82%', 'Eat before it runs out.'], ['Thirst', '64%', 'Drink before it runs out.'],
                ['Citizen ID', 'VXN48211', 'Your character on this server.'], ['Server ID', '7', 'Your number on this server today.']]
                .map(function (r) { return { label: r[0], value: r[1], desc: r[2], image: 'brief', title: r[0] }; });
        } },
        stats: { title: 'Stats', rows: function () {
            return [['Stamina', 62, 'beach', 'sprinting'], ['Strength', 40, 'players', 'landing melee hits'], ['Health', 55, 'beach', 'jogging'],
                ['Lung Capacity', 18, 'boat', 'time spent underwater'], ['Shooting', 71, 'keybinds', 'shots on target'], ['Focus', 33, 'players', 'baskets made'],
                ['Stealth', 12, 'report', 'moving crouched'], ['Driving', 88, 'mapvehicle', 'driving without a crash'], ['Flying', 5, 'map', 'time in the air'],
                ['Wheelie', 27, 'editor', 'riding on one wheel']]
                .map(function (r) {
                    return { label: r[0], value: r[1] + ' / 100', bar: r[1] / 100, image: r[2], title: r[0],
                             desc: 'Raised by ' + r[3] + '. 40% of the way to level ' + (r[1] + 1) + '.' };
                });
        } },
        players: { title: 'Players', rows: function () {
            return ['Gecko', 'Vice_Kid', 'Nova', 'Marlowe', 'Big Tony', 'Sunny D', 'Kai', 'Rook', 'Juniper', 'Dex', 'Salt', 'Lemon']
                .map(function (n, i) { return { label: n, value: '#' + (i + 1), image: 'players', title: n, desc: 'Server ID ' + (i + 1) + '.' }; });
        } }
    };

    // The map: the player on Vespucci Beach facing north-west (?h=<heading>), a waypoint at Legion Square, and blips where the game
    // has them (near enough): stores, gas stations, clothes, barbers, tattoo parlours, Ammu-Nations, LS Customs,
    // hospitals, garages, cinemas, the airport, a few plain dots and a couple of other sprites.
    var me = { x: -1200, y: -1500, h: q.get('h') ? +q.get('h') : 45 };
    var wp = { x: 215, y: -810 };
    var places = {
        1: [[100, -900, 0x5DB6E5], [-600, -420, 0x72CC72], [880, -2010, 0xE04040], [-1410, -1650, 0xF0C850]],
        40: [[-14, -1438], [8, 537]],
        52: [[26, -1347], [-48, -1757], [1163, -324], [-708, -914], [374, 326], [-1223, -907], [1136, -982],
             [-1488, -379], [2557, 382], [1961, 3741], [1729, 6414], [547, 2672]],
        361: [[266, -1261], [-725, -935], [1209, -1403], [621, 269], [2581, 362], [1702, 6416], [-2096, -320],
              [-1438, -277], [-70, -1761], [819, -1028]],
        73: [[72, -1399], [-704, -152], [-168, -299], [429, -800], [-829, -1074], [-1448, -242], [12, 6514],
             [124, -219], [1696, 4829], [-1108, 2709], [618, 2760]],
        71: [[-814, -184], [137, -1708], [-1283, -1117], [1932, 3730], [1213, -473], [-33, -152], [-278, 6229]],
        75: [[1323, -1652], [-1154, -1426], [322, 180], [-3170, 1075], [1865, 3748], [-294, 6200]],
        110: [[22, -1107], [252, -50], [842, -1033], [-662, -935], [-1306, -395], [810, -2157], [-330, 6084],
              [1693, 3760], [-1118, 2699], [2568, 294]],
        72: [[-362, -132], [732, -1089], [-1155, -2007], [1175, 2640], [109, 6624]],
        61: [[299, -585], [1840, 3673], [-248, 6331], [-450, -341]],
        357: [[216, -810], [-341, -876], [1738, 3710]],
        135: [[300, 201], [-1423, -213], [394, -711]],
        90: [[-1035, -2734]],
        225: [[-1150, -1520], [-980, -1400]],
        198: [[905, -175]]
    };
    var blips = [];
    Object.keys(places).forEach(function (s) {
        places[s].forEach(function (p) { blips.push(p[0], p[1], +s, p[2] || 0); });
    });
    function mapData(withBlips) {
        return { me: me, wp: wp || false, blips: withBlips ? blips : undefined };
    }
    // the game's area names, roughly, for the line under MAP
    function zoneAt(x, y) {
        if (x < -3300 || y < -3700 || x > 4200 || y > 8000) return '';
        if (y > 5800) return 'Paleto Bay';
        if (y > 2400) return x > 0 ? 'Sandy Shores' : 'Grand Senora Desert';
        if (y > 400) return x < -1500 ? 'Pacific Bluffs' : 'Vinewood Hills';
        if (x < -1050 && y < -1100) return 'Vespucci Beach';
        if (x < -500) return y < -800 ? 'Vespucci Canals' : 'Rockford Hills';
        if (y < -1600) return x < 600 ? 'Davis' : 'La Mesa';
        return x < 500 ? 'Legion Square' : 'Mirror Park';
    }

    window.VIPM_LOG = [];
    window.VIPM_STUB = function (name, data) {
        window.VIPM_LOG.push([name, data]);
        if (name === 'tile' && data.id === 'map') {
            mapUp = true;
            return { map: mapData(true), mode: 'ONLINE', name: 'Lucia Caminos', safezone: 1 };
        }
        if (name === 'screen' && data.screen === 'home') mapUp = false;
        if (name === 'waypoint') {
            wp = data.off ? null : { x: data.x, y: data.y };
            return 1;
        }
        if (name === 'mapzone') return { zone: zoneAt(data.x, data.y) };
        if (name === 'screen') {
            var l = lists[data.screen];
            return l ? { title: l.title, rows: l.rows() } : {};
        }
        if (name === 'setting') {
            var s = settings[data.id];
            if (s) s.at = (s.at + (data.dir < 0 ? -1 : 1) + s.values.length) % s.values.length;
            return { rows: settingRows() };
        }
        return 1;
    };

    // The face: in game a pedheadshot from nui-img; here a crop of Lucia from the Game tile's still (?face=0: none,
    // to see the initials), handed to the page the same way, as a "txd" it fetches.
    var faceData = null;
    window.VIPM_FACE_URL = function () { return faceData; };
    function sendFace() {
        if (q.get('face') === '0') return;
        var still = new Image();
        still.onload = function () {
            var c = document.createElement('canvas');
            c.width = 220;
            c.height = 248;
            c.getContext('2d').drawImage(still, 452, 168, 206, 232, 0, 0, 220, 248);
            faceData = c.toDataURL('image/png');
            send({ type: 'mugshot', txd: 'preview' });
        };
        still.src = 'img/game.webp';
    }

    function send(msg) { window.postMessage(msg, '*'); }

    // while the map is up: the player and the waypoint every 100 ms, the blips every 400, as the client sends them
    var mapUp = false;
    var ticks = 0;
    setInterval(function () {
        if (mapUp) send({ type: 'mapdata', map: mapData(ticks++ % 4 === 0) });
    }, 100);

    window.addEventListener('load', function () {
        sendFace();
        var screen = q.get('screen') || 'home';
        send({ type: 'open', fresh: true, screen: screen, title: 'Upstate Mafia', mode: 'ONLINE', name: 'Lucia Caminos', tiles: tiles,
               footer: { day: 'Saturday', time: '14:32', cash: '$1,250', bank: '$48,900' }, discord: 'https://discord.gg/example',
               categories: ['Player', 'Bug', 'Question', 'Other'] });
        if (lists[screen]) send({ type: 'list', screen: screen, title: lists[screen].title, rows: lists[screen].rows() });
        // ?map=1: the map, as the Map tile opens it; &pad=1 with a pad in hand (RB pressed: the legend's first kind)
        if (q.get('map')) {
            setTimeout(function () {
                document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
                if (q.get('pad')) setTimeout(function () { send({ type: 'pad', button: 'rb' }); }, 300);
            }, 50);
        }
    });
})();
