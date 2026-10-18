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

    window.VIPM_LOG = [];
    window.VIPM_STUB = function (name, data) {
        window.VIPM_LOG.push([name, data]);
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
    window.addEventListener('load', function () {
        sendFace();
        if (q.get('map')) {
            send({ type: 'map', show: true, location: 'Vespucci Beach', mode: 'ONLINE', name: 'Lucia Caminos' });
            return;
        }
        var screen = q.get('screen') || 'home';
        send({ type: 'open', fresh: true, screen: screen, title: 'Upstate Mafia', mode: 'ONLINE', name: 'Lucia Caminos', tiles: tiles,
               footer: { day: 'Saturday', time: '14:32', cash: '$1,250', bank: '$48,900' }, discord: 'https://discord.gg/example',
               categories: ['Player', 'Bug', 'Question', 'Other'] });
        if (lists[screen]) send({ type: 'list', screen: screen, title: lists[screen].title, rows: lists[screen].rows() });
    });
})();
