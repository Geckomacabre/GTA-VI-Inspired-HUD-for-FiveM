(() => {
    'use strict';

    const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : null;
    const LIST_ROWS = 8; // rows of a list on screen at once
    const SWATCH_ROW = 7; // swatches on screen at once
    const STATS = [['speed', 'Speed'], ['acceleration', 'Acceleration'], ['asphalt', 'Asphalt Handling'], ['offroad', 'Off-Road Handling'], ['strength', 'Strength']];

    let D = null; // the menu, as sent by client/menu.lua
    let stack = []; // open views, the last one is on screen
    let dialog = null; // { title, lines, ok, back }
    let shown = null; // stats of what is being looked at
    let cardOverride = null; // card page picked with the card key, null = automatic
    let busy = false; // waiting for the client script
    let toastTimer = null;
    let previewTimer = null;
    let previewSeq = 0;
    let playing = '';
    let padMode = false; // a controller is in use: its button names go in the prompts

    const $ = (id) => document.getElementById(id);
    const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const cash = (n) => '$' + Math.round(n || 0).toLocaleString('en-US');
    const top = () => stack[stack.length - 1];
    const tab = () => D.tabs[stack[0].tab];

    function post(name, data) {
        if (RES) {
            return fetch(`https://${RES}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data || {}),
            }).then((r) => r.json()).catch(() => ({}));
        }
        let mock = null; // browser preview only
        try { mock = window.parent !== window && window.parent.CustomsMock; } catch (e) { /* not our parent */ }
        return Promise.resolve(mock ? mock(name, data || {}) : {});
    }

    function sfx(name, volume) {
        const audio = new Audio(`audio/${name}.ogg`);
        audio.volume = volume;
        audio.play().catch(() => {});
    }

    const ICONS = {
        tag: '<svg class="tag" viewBox="0 0 24 24"><path d="M3 12.6V4.5A1.5 1.5 0 0 1 4.5 3h8.1a1.5 1.5 0 0 1 1.06.44l7.4 7.4a1.5 1.5 0 0 1 0 2.12l-8.1 8.1a1.5 1.5 0 0 1-2.12 0l-7.4-7.4A1.5 1.5 0 0 1 3 12.6Z" fill="none" stroke="currentColor" stroke-width="2.2"/><circle cx="8.2" cy="8.2" r="1.9" fill="currentColor"/></svg>',
        check: '<svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>',
        dirt: '<svg class="rate" viewBox="0 0 24 24"><rect x="1.5" y="1.5" width="21" height="21" fill="none" stroke="currentColor" stroke-width="2"/><path d="M3 18l5-9 3.5 5 3-7 6.5 11z" fill="currentColor"/></svg>',
        road: '<svg class="rate" viewBox="0 0 24 24"><rect x="1" y="1" width="22" height="22" fill="currentColor"/><path d="M8.5 3L5 21h4.6l.6-5h3.6l.6 5H19L15.5 3z" fill="#22222b"/><path d="M11.4 5.5h1.2v3h-1.2zM11.2 10.5h1.6v3.5h-1.6z" fill="currentColor"/></svg>',
    };
    const have = `<i class="have">${ICONS.check}</i>`;

    const keyLabel = (code) => String(code || '').replace(/^Key|^Digit/, '').replace('Tab', 'TAB').toUpperCase();

    // what is drawn in the circle next to a prompt, for the keyboard or for the controller in use
    const PAD_GLYPHS = {
        xbox: { ok: 'A', back: 'B', rev: 'X', card: 'Y', prev: 'LB', next: 'RB' },
        playstation: { ok: '&#10005;', back: '&#9675;', rev: '&#9633;', card: '&#9651;', prev: 'L1', next: 'R1' },
    };

    function glyph(action) {
        if (padMode) return (PAD_GLYPHS[D.pad && D.pad.style] || PAD_GLYPHS.xbox)[action];
        const keys = D.keys || {};
        return { ok: '&#8629;', back: 'ESC', rev: keyLabel(keys.rev), card: keyLabel(keys.card), prev: 'Q', next: 'E' }[action];
    }

    function keyHtml(action, cls, tag) {
        const text = glyph(action);
        const wide = text.length > 1 && text.charAt(0) !== '&';
        return `<${tag || 'i'} class="key${wide ? ' wide' : ''}${cls || ''}">${text}</${tag || 'i'}>`;
    }

    // STATE HELPERS

    // applied = on the vehicle, stock = the factory option (never "not owned"), none = for sale
    function statusOf(slot, option) {
        if (option.value === null) return 'none';
        if (option.value === D.owned[slot]) return 'applied';
        return option.stock ? 'stock' : 'none';
    }

    const kitStatus = (id) => (D.owned.kit === id ? 'applied' : 'none');
    // a mission can point at a slot (see SetMenuObjective): tag on its tab, dot on its category
    const isMarked = (slot) => !!D.objective && D.objective.slot === slot;
    const markedCategory = (category) => !category.kits && category.slots.some(isMarked);

    function optionLabel(slot, value) {
        const found = slot.options.find((o) => o.value === value);
        if (found) return found.label;
        return slot.kind === 'wheels' ? 'Custom Wheels' : 'Custom';
    }

    // the swatch for a colour that is not one of the presets (picked with the colour picker)
    function customOption(slot) {
        const value = D.owned[slot.id];
        const preset = slot.options.some((o) => o.value === value);
        const rgb = !preset && typeof value === 'string' && /^\d+,\d+,\d+$/.test(value) ? value : null;
        return { custom: true, value: rgb, label: 'Custom Colour', price: slot.options[slot.options.length - 1].price, hex: rgb ? `rgb(${rgb})` : null };
    }

    function currentOption(view) {
        if (view.type === 'item') return view.options[view.sel];
        if (view.type === 'swatch') return view.groups[view.g].options[view.sel];
        return null;
    }

    // VIEWS

    function swatchView(slot) {
        const groups = [];
        for (const option of slot.options) {
            const look = swatchOf(option);
            let group = groups.find((g) => g.name === look.family);
            if (!group) groups.push(group = { name: look.family, options: [] });
            group.options.push(Object.assign({ look }, option));
        }
        groups.sort((a, b) => {
            const ia = FAMILY_ORDER.indexOf(a.name), ib = FAMILY_ORDER.indexOf(b.name);
            return ia === -1 || ib === -1 ? 0 : ia - ib;
        });
        if (slot.custom) groups.push({ name: 'Custom', options: [customOption(slot)] });
        const view = { type: 'swatch', slot, groups, g: 0, sel: 0 };
        groups.forEach((group, g) => group.options.forEach((option, i) => {
            if (option.value !== null && option.value === D.owned[slot.id]) { view.g = g; view.sel = i; }
        }));
        return view;
    }

    function openSlot(id, crumb, title, camera) {
        const slot = D.slots[id];
        const head = { slot, crumb, title, camera: slot.camera || camera };
        if (slot.kind === 'swatch') {
            push(Object.assign(swatchView(slot), head));
        } else if (slot.kind === 'wheels') {
            const current = String(D.owned[id]).split(':')[0];
            push(Object.assign({ type: 'groups', sel: Math.max(0, slot.groups.findIndex((g) => String(g.id) === current)) }, head));
        } else {
            push(Object.assign({ type: 'item', options: slot.options, sel: Math.max(0, slot.options.findIndex((o) => o.value === D.owned[id])) }, head));
        }
    }

    function openCategory(category) {
        const crumb = tab().label;
        const camera = category.camera || tab().camera;
        if (category.kits) {
            push({ type: 'kits', sel: Math.max(0, D.kits.findIndex((k) => k.id === D.owned.kit)), crumb, title: category.label, camera });
            preview();
        } else if (category.slots.length === 1) {
            openSlot(category.slots[0], crumb, category.label, camera);
        } else {
            push({ type: 'slots', category, sel: 0, crumb, title: category.label, camera });
        }
    }

    function openGroup(view) {
        const group = view.slot.groups[view.sel];
        busy = true;
        post('Options', { slot: view.slot.id, group: group.id }).then((r) => {
            busy = false;
            const options = (r && r.options) || [];
            if (!options.length || top() !== view) return render();
            const sel = Math.max(0, options.findIndex((o) => o.value === D.owned[view.slot.id]));
            push({ type: 'item', slot: view.slot, options, sel, crumb: view.title, title: group.label, camera: view.camera });
        });
    }

    function push(view) {
        stack.push(view);
        enter();
    }

    // camera and screen for the view that just came to the front
    function enter() {
        const view = top();
        post('Camera', { view: view.type === 'root' ? tab().camera : view.camera || tab().camera });
        render();
    }

    function setStats(r) {
        if (r && r.stats) {
            shown = r.stats;
            renderCard();
        }
    }

    function preview() {
        const view = top();
        clearTimeout(previewTimer);
        previewTimer = setTimeout(() => {
            const seq = ++previewSeq;
            let request = null;
            if (view.type === 'kits') {
                request = post('KitPreview', { id: D.kits[view.sel].id });
            } else {
                const option = currentOption(view);
                if (option && option.value !== null) request = post('Preview', { slot: view.slot.id, value: option.value });
            }
            if (request) request.then((r) => { if (seq === previewSeq) setStats(r); });
        }, 70);
    }

    function purchased(r) {
        D.owned = r.owned;
        if (Array.isArray(r.kits)) D.kits = r.kits;
        D.stats = r.stats;
        shown = r.stats;
        const view = top();
        if (view.type === 'swatch' && view.slot.custom) {
            view.groups[view.groups.length - 1].options = [customOption(view.slot)];
        }
        $('toast').hidden = false;
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => { $('toast').hidden = true; }, 2600);
        render();
    }

    // value is given when it comes from the colour picker, otherwise the option on screen is bought
    function buy(value) {
        const view = top();
        let request;
        if (view.type === 'kits') {
            const kit = D.kits[view.sel];
            if (kitStatus(kit.id) === 'applied') return;
            request = post('KitBuy', { id: kit.id });
        } else {
            if (value === undefined) {
                const option = currentOption(view);
                if (!option) return;
                if (option.custom) return padMode ? null : $('picker').click();
                value = option.value;
            }
            if (value === D.owned[view.slot.id]) return; // already on the vehicle
            request = post('Buy', { slot: view.slot.id, value });
        }
        sfx('click', 0.5);
        busy = true;
        request.then((r) => {
            busy = false;
            if (r && r.ok) return purchased(r);
            ask('Payment declined', [(r && r.message) || 'The payment did not go through.'], () => { dialog = null; render(); });
        });
    }

    function select() {
        const view = top();
        if (view.type === 'root') {
            sfx('click', 0.5);
            openCategory(tab().categories[view.sel[view.tab]]);
        } else if (view.type === 'slots') {
            sfx('click', 0.5);
            openSlot(view.category.slots[view.sel], view.title, D.slots[view.category.slots[view.sel]].label, view.camera);
        } else if (view.type === 'groups') {
            sfx('click', 0.5);
            openGroup(view);
        } else {
            buy();
        }
    }

    function back() {
        const view = top();
        if (stack.length === 1) return post('Close');
        stack.pop();
        clearTimeout(previewTimer);
        previewSeq++;
        shown = D.stats;
        if (view.type === 'item' || view.type === 'swatch') post('Revert', { slot: view.slot.id }).then(setStats);
        if (view.type === 'kits') post('KitRevert', { id: D.kits[view.sel].id }).then(setStats);
        enter();
    }

    function move(delta) {
        const view = top();
        let count = 0;
        if (view.type === 'root') count = tab().categories.length;
        else if (view.type === 'slots') count = view.category.slots.length;
        else if (view.type === 'groups') count = view.slot.groups.length;
        else if (view.type === 'item') count = view.options.length;
        else if (view.type === 'kits') count = D.kits.length;
        else if (view.type === 'swatch') count = view.groups[view.g].options.length;
        if (count < 2) return;
        const now = view.type === 'root' ? view.sel[view.tab] : view.sel;
        const next = (now + delta + count) % count;
        if (view.type === 'root') view.sel[view.tab] = next; else view.sel = next;
        sfx('menu', 0.35);
        if (view.type === 'item' || view.type === 'swatch' || view.type === 'kits') preview();
        render();
    }

    // tabs of the root view, colour groups of a swatch view
    function shift(delta) {
        const view = top();
        if (view.type === 'root' && D.tabs.length > 1) {
            view.tab = (view.tab + delta + D.tabs.length) % D.tabs.length;
            cardOverride = null;
            sfx('menu', 0.35);
            enter();
        } else if (view.type === 'swatch' && view.groups.length > 1) {
            view.g = (view.g + delta + view.groups.length) % view.groups.length;
            view.sel = 0;
            sfx('menu', 0.35);
            preview();
            render();
        }
    }

    // DIALOGS

    function ask(title, lines, ok, backAction) {
        dialog = { title, lines, ok, back: backAction };
        render();
    }

    const close = () => post('Close');

    function repairDialog() {
        const lines = ["You'll need to repair this vehicle before making modifications."];
        if (!D.vehicle.owned) lines.push("Since you don't own this vehicle, any money spent on it may be lost.");
        ask(`Repair for ${D.repair.cost ? cash(D.repair.cost) : 'free'}?`, lines, () => {
            busy = true;
            post('Repair').then((r) => {
                busy = false;
                if (r && r.ok) {
                    dialog = null;
                    enter();
                } else {
                    ask('Repair declined', [(r && r.message) || 'The vehicle could not be repaired.'], close);
                }
            });
        }, close);
    }

    // RENDER

    function tabsHtml(labels, active, act, tagged) {
        const several = labels.length > 1; // the bumpers (or Q / E) step through them
        return `<nav class="tabs${several ? '' : ' single'}">` + (several ? `<span data-act="prev">${keyHtml('prev', ' bump')}</span>` : '') + labels.map((label, i) =>
            `<button type="button" class="tab${i === active ? ' on' : ''}" data-act="${act}:${i}">${tagged && tagged(i) ? ICONS.tag : ''}<span>${esc(label)}</span></button>`).join('') +
            (several ? `<span data-act="next">${keyHtml('next', ' bump')}</span>` : '') + '</nav>';
    }

    function renderHead() {
        const view = top();
        if (view.type === 'root') {
            $('head').className = 'root';
            $('head').innerHTML = `<h1 class="shop">${esc(D.shop.label)}</h1>` +
                tabsHtml(D.tabs.map((t) => t.label), view.tab, 'tab', (i) => D.tabs[i].categories.some(markedCategory));
        } else {
            $('head').className = 'sub';
            $('head').innerHTML = `<div class="crumb">${esc(view.crumb)} <i>/</i></div><h1 class="title">${esc(view.title)}</h1>`;
        }
    }

    function renderMenu() {
        const view = top();
        let rows = [];
        let sel = view.sel;
        if (view.type === 'root') {
            rows = tab().categories.map((c) => ({ label: c.label, dot: markedCategory(c) }));
            sel = view.sel[view.tab];
        } else if (view.type === 'slots') {
            rows = view.category.slots.map((id) => ({ label: D.slots[id].label, dot: isMarked(id), right: optionLabel(D.slots[id], D.owned[id]) }));
        } else if (view.type === 'groups') {
            const current = String(D.owned[view.slot.id]).split(':')[0];
            rows = view.slot.groups.map((g) => ({ label: g.label, have: String(g.id) === current }));
        }
        let offset = view.offset || 0;
        if (sel < offset) offset = sel;
        if (sel >= offset + LIST_ROWS) offset = sel - LIST_ROWS + 1;
        view.offset = offset;
        $('menu').innerHTML = rows.slice(offset, offset + LIST_ROWS).map((row, n) => {
            const i = offset + n;
            const right = row.have ? have : row.right ? `<span class="now">${esc(row.right)}</span>` : '';
            return `<li class="${i === sel ? 'sel' : ''}" data-act="row:${i}">${row.dot ? '<i class="dot"></i>' : ''}<span class="label">${esc(row.label)}</span><span class="right">${right}</span></li>`;
        }).join('');
        $('count').textContent = rows.length > LIST_ROWS ? `${sel + 1} / ${rows.length}` : '';
    }

    function statusHtml(status, price, marked) {
        if (status === 'stock') return '';
        if (status === 'applied') return `<div class="line"></div><div class="status">${have}<span>Applied</span></div>`;
        return `<div class="line"></div><div class="status">${marked ? '<i class="dot"></i>' : ''}<span>Not owned</span><span class="price">${price ? cash(price) : 'Free'}</span></div>`;
    }

    function swatchHtml(view, option, i) {
        const look = option.look || swatchOf(option);
        const status = statusOf(view.slot.id, option);
        let inner = '';
        if (option.custom && !option.hex) inner = '<span class="plus">+</span>';
        else if (!look.hex && !option.custom) inner = '<span class="none"></span>';
        if (status === 'applied') inner += have;
        else if (status === 'none') inner += '<i class="mark">%</i>';
        const background = option.custom ? (option.hex || 'conic-gradient(#e0245e,#f3d21f,#2fb24c,#19c8f0,#5b2be0,#e0245e)') : look.background;
        return `<button type="button" class="swatch${i === view.sel ? ' sel' : ''}" style="background:${background}" data-act="sw:${i}">${inner}</button>`;
    }

    function renderDetail() {
        const view = top();
        const el = $('detail');
        if (view.type === 'item' || view.type === 'kits') {
            const kit = view.type === 'kits' ? D.kits[view.sel] : null;
            const option = kit || view.options[view.sel];
            const count = kit ? D.kits.length : view.options.length;
            const status = kit ? kitStatus(kit.id) : statusOf(view.slot.id, option);
            el.className = 'item';
            el.innerHTML = `<h2 class="name">${esc(option.label)}</h2>` +
                (count > 1 ? `<div class="counter" data-act="down">${view.sel + 1}<i>/</i>${count}</div>` : '') +
                statusHtml(status, option.price, !kit && isMarked(view.slot.id));
        } else if (view.type === 'swatch') {
            const group = view.groups[view.g];
            const option = group.options[view.sel];
            const look = option.look || swatchOf(option);
            let offset = view.offset || 0;
            if (view.sel < offset) offset = view.sel;
            if (view.sel >= offset + SWATCH_ROW) offset = view.sel - SWATCH_ROW + 1;
            if (offset + SWATCH_ROW > group.options.length) offset = Math.max(0, group.options.length - SWATCH_ROW);
            view.offset = offset;
            const more = group.options.length > SWATCH_ROW ? `<span class="pager">${view.sel + 1} / ${group.options.length}</span>` : '';
            el.className = 'paint';
            el.innerHTML = `<h2 class="name">${esc(option.label)}</h2><h3 class="sub">${esc(look.finish || view.slot.label)}</h3>` +
                `<div class="swatches">${group.options.slice(offset, offset + SWATCH_ROW).map((o, n) => swatchHtml(view, o, offset + n)).join('')}${more}</div>` +
                (view.groups.length > 1 ? tabsHtml(view.groups.map((g) => g.name), view.g, 'grp') : '<div class="tabs"></div>') +
                (statusHtml(statusOf(view.slot.id, option), option.price, isMarked(view.slot.id)) || '<div class="status"></div>');
        } else {
            el.className = '';
            el.innerHTML = '';
        }
    }

    // parts on the vehicle that are not factory, for the third page of the card
    function fitted() {
        const rows = [];
        for (const id of Object.keys(D.slots)) {
            const slot = D.slots[id];
            const stock = slot.options.find((o) => o.stock);
            if (stock && D.owned[id] !== stock.value) rows.push([slot.label, optionLabel(slot, D.owned[id])]);
        }
        return rows;
    }

    const hasDelta = (stats) => STATS.some(([key]) => Math.abs(stats[key].value - stats[key].owned) >= 0.05);

    function cardPage() {
        if (cardOverride) return cardOverride;
        return tab().id === 'performance' || top().type === 'kits' || hasDelta(shown) ? 'stats' : 'name';
    }

    const arrow = (delta) => `<b>${delta > 0 ? '&uarr;' : '&darr;'}</b>`;

    function statHtml(label, s) {
        const delta = Math.round((s.value - s.owned) * 10) / 10;
        const low = Math.min(s.value, s.owned) * 10;
        const high = Math.max(s.value, s.owned) * 10;
        const tick = Math.abs(s.stock - s.value) >= 0.05 ? `<i class="tick" style="left:${s.stock * 10}%"></i>` : '';
        const change = delta ? `<span class="delta ${delta > 0 ? 'up' : 'down'}">${arrow(delta)}${Math.abs(delta).toFixed(1)}</span>` : '';
        return `<div class="stat"><span class="stat-label">${label}</span><span class="stat-val">${change}<span class="num">${s.value.toFixed(1)}</span></span>` +
            `<div class="bar"><i class="fill" style="width:${low}%"></i>${delta ? `<i class="seg ${delta > 0 ? 'up' : 'down'}" style="left:${low}%;width:${high - low}%"></i>` : ''}${tick}</div></div>`;
    }

    function ratingHtml(rating, icon) {
        const delta = rating.value - rating.owned;
        return (delta ? `<span class="delta ${delta > 0 ? 'up' : 'down'}">${arrow(delta)}${Math.abs(delta)}</span>` : '') + `<span>${rating.value}</span>${icon}`;
    }

    function renderCard() {
        const page = cardPage();
        // manufacturer mark behind the name, from the same table and files vice_hud uses
        const make = window.VICE_MAKES ? window.VICE_MAKES.lookup(D.vehicle.brand) : null;
        const emblem = make && make.logo ? `<img class="emblem" src="${make.logo}" alt="">` : '';
        let html = `<div class="dots" data-act="card">${keyHtml('card', ' mini', 'kbd')}${['name', 'stats', 'parts'].map((p) => `<i class="${p === page ? 'on' : ''}"></i>`).join('')}</div>` +
            `<div class="card-head"><div class="brand">${esc(D.vehicle.brand)}</div><div class="model">${esc(D.vehicle.name)}</div>` +
            `${emblem}</div>`;
        if (page === 'stats') {
            html += '<div class="card-body">' + STATS.map(([key, label]) => statHtml(label, shown[key])).join('') + '</div>' +
                `<div class="card-foot"><span>Rating</span><span class="ratings">${ratingHtml(shown.dirt, ICONS.dirt)}${ratingHtml(shown.road, ICONS.road)}</span></div>`;
        } else if (page === 'parts') {
            const rows = fitted();
            html += '<div class="card-body parts">' + (rows.length ? rows.slice(0, 9).map(([label, option]) =>
                `<div class="part"><span>${esc(label)}</span><em>${esc(option)}</em></div>`).join('') : '<div class="part">This vehicle is factory standard.</div>') +
                (rows.length > 9 ? `<div class="part">and ${rows.length - 9} more</div>` : '') + '</div>' +
                `<div class="card-foot"><span>Fitted</span><span class="ratings"><span>${rows.length}</span></span></div>`;
        }
        $('card').innerHTML = html;
    }

    function promptList() {
        const view = top();
        const list = [];
        const leaf = view.type === 'item' || view.type === 'swatch' || view.type === 'kits';
        const engine = tab().id === 'performance' && !(view.slot && view.slot.id === 'nitrous');
        if (view.type === 'kits' || (engine && (view.type === 'root' || view.type === 'item'))) {
            list.push({ label: 'Rev', act: 'rev' });
        }
        if (!leaf) {
            list.push({ label: 'Select', act: 'ok' });
        } else if (view.type === 'kits') {
            if (kitStatus(D.kits[view.sel].id) !== 'applied') list.push({ label: 'Buy', act: 'ok' });
        } else {
            const option = currentOption(view);
            // the colour picker needs a mouse
            if (option.custom ? !padMode : statusOf(view.slot.id, option) !== 'applied') list.push({ label: option.custom ? 'Pick' : 'Buy', act: 'ok' });
        }
        list.push(stack.length > 1 ? { label: 'Back', act: 'back' } : { label: 'Exit', act: 'back', hold: true });
        return list;
    }

    function promptsHtml(list) {
        return list.map((p) => `<button type="button" data-act="${p.act}"><span>${esc(p.label)}</span>${keyHtml(p.act, p.hold ? ' hold' : '')}</button>`).join('');
    }

    function render() {
        if (!D) return;
        $('app').classList.toggle('dialog-open', !!dialog);
        if (dialog) {
            $('dialog').hidden = false;
            $('dialog-title').textContent = dialog.title;
            $('dialog-body').innerHTML = dialog.lines.map((line) => `<p>${esc(line)}</p>`).join('');
            const list = [{ label: 'OK', act: 'ok' }];
            if (dialog.back) list.push({ label: 'Back', act: 'back' });
            $('dialog-prompts').innerHTML = promptsHtml(list);
            return;
        }
        $('dialog').hidden = true;
        const view = top();
        renderHead();
        renderMenu();
        renderDetail();
        renderCard();
        $('objective').innerHTML = D.objective && D.objective.text ? esc(D.objective.text).replace(/~([^~]+)~/g, '<b>$1</b>') : '';
        $('hint').textContent = view.type === 'root' ? tab().categories[view.sel[view.tab]].hint : view.type === 'slots' ? view.category.hint : '';
        $('prompts').innerHTML = promptsHtml(promptList());
    }

    // INPUT

    function act(action, held) {
        if (!D || busy) return;
        if (dialog) {
            if (held) return;
            if (action === 'ok') { sfx('click', 0.5); dialog.ok(); } else if (action === 'back') { (dialog.back || dialog.ok)(); }
            return;
        }
        const view = top();
        const leaf = view.type === 'item' || view.type === 'swatch' || view.type === 'kits';
        switch (action) {
            case 'up': return view.type === 'swatch' ? shift(-1) : move(-1);
            case 'down': return view.type === 'swatch' ? shift(1) : move(1);
            case 'left': return leaf ? move(-1) : shift(-1);
            case 'right': return leaf ? move(1) : shift(1);
            case 'prev': return shift(-1);
            case 'next': return shift(1);
            case 'ok': return held ? null : select();
            case 'back': return held ? null : back();
            case 'card': {
                if (held) return null;
                const pages = ['name', 'stats', 'parts'];
                cardOverride = pages[(pages.indexOf(cardPage()) + 1) % pages.length];
                return renderCard();
            }
            default: return null;
        }
    }

    const KEYS = {
        ArrowUp: 'up', KeyW: 'up', ArrowDown: 'down', KeyS: 'down', ArrowLeft: 'left', KeyA: 'left', ArrowRight: 'right', KeyD: 'right',
        KeyQ: 'prev', KeyE: 'next', Enter: 'ok', NumpadEnter: 'ok', Space: 'ok', Backspace: 'back', Escape: 'back',
    };

    function actionOf(code) {
        const keys = (D && D.keys) || {};
        if (code === keys.rev) return 'rev';
        if (code === keys.card) return 'card';
        return KEYS[code];
    }

    let revving = false;
    function rev(on) {
        if (on === revving || (on && (!D || dialog || busy))) return;
        revving = on;
        post('Rev', { on });
    }

    // keyboard or mouse touched: back to their prompts, and the cursor comes back
    function usedKeyboard() {
        if (!padMode) return;
        padMode = false;
        post('Input', { pad: false });
        render();
    }

    document.addEventListener('keydown', (e) => {
        if (!D) return;
        usedKeyboard();
        const action = actionOf(e.code);
        if (!action) return;
        e.preventDefault();
        if (action === 'rev') return rev(true);
        act(action, e.repeat);
    });

    document.addEventListener('keyup', (e) => {
        if (D && actionOf(e.code) === 'rev') rev(false);
    });

    document.addEventListener('click', (e) => {
        const target = e.target.closest('[data-act]');
        if (!target || !D || busy) return;
        const [kind, arg] = target.dataset.act.split(':');
        const index = Number(arg);
        const view = top();
        if (dialog) {
            act(kind, false);
        } else if (kind === 'tab') {
            if (index !== view.tab) shift(index - view.tab);
        } else if (kind === 'grp') {
            if (index !== view.g) shift(index - view.g);
        } else if (kind === 'row' || kind === 'sw') {
            const now = view.type === 'root' ? view.sel[view.tab] : view.sel;
            if (index === now) select(); else move(index - now);
        } else if (kind === 'rev') {
            rev(true);
            setTimeout(() => rev(false), 900);
        } else {
            act(kind, false);
        }
    });

    // drag the background to look around the vehicle, scroll to zoom
    let drag = null;
    let orbit = { dx: 0, dy: 0, zoom: 0 };
    let orbitQueued = false;
    function sendOrbit() {
        orbitQueued = false;
        if (D && (orbit.dx || orbit.dy || orbit.zoom)) post('Orbit', orbit);
        orbit = { dx: 0, dy: 0, zoom: 0 };
    }
    function queueOrbit() {
        if (!orbitQueued) {
            orbitQueued = true;
            requestAnimationFrame(sendOrbit);
        }
    }
    document.addEventListener('mousedown', (e) => {
        if (D) usedKeyboard();
        if (D && !dialog && (e.target.id === 'app' || e.target.classList.contains('shade'))) drag = { x: e.clientX, y: e.clientY };
    });
    document.addEventListener('mousemove', (e) => {
        if (!drag) return;
        orbit.dx += e.clientX - drag.x;
        orbit.dy += e.clientY - drag.y;
        drag = { x: e.clientX, y: e.clientY };
        queueOrbit();
    });
    document.addEventListener('mouseup', () => { drag = null; });
    document.addEventListener('wheel', (e) => {
        if (!D || dialog || busy) return;
        if (e.target.closest('#menu, #detail')) return move(e.deltaY > 0 ? 1 : -1);
        orbit.zoom += e.deltaY > 0 ? 1 : -1;
        queueOrbit();
    }, { passive: true });

    // colour picker for custom RGB paint, neon and tire smoke
    const rgbOf = (hex) => hexToRgb(hex).join(',');
    $('picker').addEventListener('input', (e) => {
        if (D && top().type === 'swatch') post('Preview', { slot: top().slot.id, value: rgbOf(e.target.value) }).then(setStats);
    });
    $('picker').addEventListener('change', (e) => {
        if (D && top().type === 'swatch') buy(rgbOf(e.target.value));
    });

    // spray can of the paint room
    $('spray-color').addEventListener('input', (e) => {
        const [r, g, b] = hexToRgb(e.target.value);
        post('CustomPaint', { r, g, b });
    });
    $('spray-done').addEventListener('click', () => {
        $('spray').hidden = true;
        post('CustomPaintDone');
    });

    function open(data) {
        D = data;
        D.kits = Array.isArray(D.kits) ? D.kits : [];
        D.tabs = Array.isArray(D.tabs) ? D.tabs : [];
        D.slots = D.slots && !Array.isArray(D.slots) ? D.slots : {};
        D.objective = D.objective || null;
        padMode = !!(D.pad && D.pad.active);
        shown = D.stats;
        dialog = null;
        busy = false;
        cardOverride = null;
        stack = [{ type: 'root', tab: 0, sel: D.tabs.map(() => 0) }];
        $('toast').hidden = true;
        $('app').hidden = false;
        if (!D.tabs.length) {
            D.tabs = [{ id: 'none', label: '', camera: 'rear34', categories: [{ label: '', hint: '', slots: [] }] }];
            ask('Nothing to fit', ['This shop has no parts for this vehicle.'], close);
        } else if (D.repair && D.repair.needed) {
            repairDialog();
        } else {
            render();
        }
    }

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        if (data.type === 'open') {
            open(data);
        } else if (data.type === 'close') {
            D = null;
            revving = false;
            $('app').hidden = true;
        } else if (data.type === 'objective' && D) {
            D.objective = data.objective || null;
            render();
        } else if (data.type === 'pad' && D) {
            // the game reads the controller (NUI does not get it) and passes it on
            const was = padMode;
            padMode = data.mode !== undefined ? data.mode : true;
            if (padMode !== was) render();
            if (data.action === 'rev') rev(data.on === true);
            else if (data.action) act(data.action, false);
        } else if (data.type === 'playsound') {
            const file = data.content.file;
            if (playing !== file) {
                playing = file;
                setTimeout(() => {
                    sfx(file, data.content.volume === undefined ? 0.2 : Math.max(0, Math.min(1, data.content.volume)));
                    playing = '';
                }, 100);
            }
        }
        if (data.custompaint) $('spray').hidden = false;
    });
})();
