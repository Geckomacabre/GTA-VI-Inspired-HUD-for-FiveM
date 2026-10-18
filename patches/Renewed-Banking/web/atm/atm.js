// BuckMe ATM screen. Draws whatever client/atm.lua's payload() says, nothing more: no input reaches a DUI page, and
// every message carries the whole state, so a message that went missing is put right by the next one.
(function () {
    'use strict';

    var params = new URLSearchParams(location.search);
    var RES = params.get('res') || 'Renewed-Banking';
    var SLOT = params.get('slot') || '';
    var root = document.getElementById('atm');
    var view = document.getElementById('view');
    var btns = document.getElementById('btns');
    var titleEl = document.getElementById('title');
    var balEl = document.getElementById('bal');

    var MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    var OPTION_TOP = 44.3, OPTION_GAP = 8.15;      // % of the height, off the reference
    var TX_TOP = 22, TX_GAP = 9.6, TX_ROWS = 6;

    var lastJson = '';
    var lastScreen = '';
    var greeted = false;

    function money(n) {
        n = Math.floor(Math.abs(Number(n) || 0));
        return '$' + String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }

    function when(t) {
        if (!t) return '';
        var d = new Date(t * 1000);
        var h = d.getHours(), m = d.getMinutes();
        return MONTHS[d.getMonth()] + ' ' + d.getDate() + ', ' + ((h + 11) % 12 + 1) + ':' + (m < 10 ? '0' : '') + m
            + (h < 12 ? ' AM' : ' PM');
    }

    function logoScreen(tagline) {
        return '<svg class="logo" aria-hidden="true"><use href="#bm-b" width="100%" height="100%"/></svg>'
            + '<div class="word">buckme</div>'
            + (tagline ? '<div class="tag">' + esc(tagline) + '</div>' : '');
    }

    function menu(s) {
        var html = '<div class="sub" style="top:34.3%">Select one of the following options</div>';
        (s.items || []).forEach(function (label, i) {
            html += '<div class="opt' + (i + 1 === s.focus ? ' focus' : '') + '" style="top:'
                + (OPTION_TOP + i * OPTION_GAP) + '%">' + esc(label) + '</div>';
        });
        if (s.account) html += '<div class="acct">Account ' + s.account.index + ' of ' + s.account.count + '</div>';
        return html;
    }

    function amount(s) {
        var empty = !s.max;
        var label = s.label || (empty ? (s.verb === 'deposit' ? 'No cash on you' : 'Nothing to withdraw') : '');
        return '<div class="sub" style="top:33%">Choose how much you would like to ' + esc(s.verb) + '</div>'
            + '<div class="limit" style="top:39%"><span class="card"></span>' + money(s.limit) + ' Limit</div>'
            + '<div class="box' + (s.focus === 'box' ? ' focus' : '') + (empty ? ' empty' : '') + '">'
            +   '<div class="amt">' + money(s.value).replace('$', '$ ') + '</div>'
            +   '<div class="row">'
            +     (s.canDown ? '<i class="chev l"></i>' : '')
            +     '<span class="lbl">' + esc(label) + '</span>'
            +     (s.canUp ? '<i class="chev r"></i>' : '')
            +   '</div>'
            + '</div>'
            + (s.error ? '<div class="err">' + esc(s.error) + '</div>' : '');
    }

    function history(s) {
        var items = s.items || [];
        if (!items.length) return '<div class="sub" style="top:45%">No transactions yet</div>';

        var focus = Math.max(1, Math.min(items.length, s.focus || 1));
        var start = Math.max(0, Math.min(focus - Math.ceil(TX_ROWS / 2), items.length - TX_ROWS));
        var html = '<div class="sub" style="top:14.5%">Recent activity</div>';

        for (var k = 0; k < TX_ROWS && start + k < items.length; k++) {
            var t = items[start + k];
            var incoming = t.kind === 'deposit';
            html += '<div class="tx' + (start + k + 1 === focus ? ' focus' : '') + '" style="top:' + (TX_TOP + k * TX_GAP) + '%">'
                + '<div class="tx-l"><div class="tx-t">' + esc(String(t.text || '').replace(/''/g, "'")) + '</div>'
                + '<div class="tx-d">' + esc(when(t.time)) + '</div></div>'
                + '<div class="tx-a ' + (incoming ? 'in' : 'out') + '">' + (incoming ? '+' : '−') + money(t.amount) + '</div>'
                + '</div>';
        }
        if (start > 0) html += '<i class="more up" style="top:19.4%"></i>';
        if (start + TX_ROWS < items.length) html += '<i class="more down" style="top:' + (TX_TOP + TX_ROWS * TX_GAP - 1.2) + '%"></i>';
        return html;
    }

    function footer(s) {
        if (s.screen === 'menu') return '<div class="fbtn solo">Exit</div>';
        if (s.screen === 'history') return '<div class="fbtn solo focus">Back</div>';
        if (s.screen === 'amount') {
            return '<div class="fbtn left' + (s.focus === 'back' ? ' focus' : '') + '">Back</div>'
                + '<div class="fbtn right' + (s.focus === 'confirm' ? ' focus' : '') + '">Confirm</div>';
        }
        return '';
    }

    function render(s) {
        var screen = s.screen || 'off';
        root.className = 'scr-' + screen + (s.busy ? ' busy' : '');
        titleEl.textContent = s.title || '';
        balEl.textContent = money(s.balance);

        var html = '';
        if (screen === 'menu') html = menu(s);
        else if (screen === 'amount') html = amount(s);
        else if (screen === 'history') html = history(s);
        else if (screen === 'splash') html = logoScreen('Thank you for bucking with us');
        else if (screen === 'welcome') html = logoScreen(s.name ? 'Welcome, ' + s.name : 'Welcome');
        else html = logoScreen('');

        view.innerHTML = html;
        btns.innerHTML = footer(s);

        if (screen !== lastScreen) {
            lastScreen = screen;
            view.classList.remove('enter');
            void view.offsetWidth;   // restart the fade
            view.classList.add('enter');
        }
    }

    function hello() {
        fetch('https://' + RES + '/atm_ready', { method: 'POST', body: JSON.stringify({ slot: SLOT }) }).catch(function () {});
    }

    window.addEventListener('message', function (e) {
        var d = e.data;
        if (typeof d === 'string') { try { d = JSON.parse(d); } catch (err) { return; } }
        if (!d || d.action !== 'render') return;

        if (!greeted) { greeted = true; hello(); }

        var json = JSON.stringify(d);
        if (json === lastJson) return;
        lastJson = json;
        render(d);
    });

    render({ screen: 'off' });
})();
