// illenium-appearance - the rack try-on (client/racks.lua): what is on the screen while an item of a clothes rack is
// on trial. Messages with a `racks` key bring all of it - { open, store, title, name, colour, price, cash, poor,
// status, wearing, index, count, kind: 'component' | 'prop', id, gender, drawable, textures: [..], texture } -
// { toast, failed } a line on the right for a moment ("Purchased", or why not) and { open: false } takes it off.
// Every other message is the React page's and is left alone. Display only: the game reads the keys (the arrows,
// Enter, Backspace), this takes no input and asks for no focus.
// cash is false where a HUD keeps the wallet (vice_hud): then there is no second one here. With vice_hud's own shop
// panel this is not opened at all - it is only asked, with { sample: { key, kind, id, gender, drawable, textures } },
// for a colour of each texture (off its thumbnail) and the thumbnail's address, which it posts back to the game as
// racksColours.
// A plain script of public/ (Vite copies it to dist/files/racks as it is): the page needs no rebuild for it.
(() => {
  // the thumbnails the page's own grid uses (web/src/utils.ts, getClothImageCandidates). This server's own come
  // first: the resource's thumbs/ folder, shot off the game with fivem-greenscreener (every slot, addon clothes
  // too, numbered as this server numbers them). Then the public set: the folder of a slot, and whether it has one
  // per gender - only the slots it really has are listed (no torsos, bags, armour, decals or props of any kind),
  // and it knows no addon clothes
  const RESOURCE = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'illenium-appearance';
  const LOCAL = `https://cfx-nui-${RESOURCE}/thumbs`;
  const CDN = 'https://cdn.jsdelivr.net/gh/ShortByte/GTA5-Cloth-Assets/assets';
  const FOLDERS = {
    component: { 1: ['masks', false], 4: ['legs', true], 6: ['shoes', true], 7: ['accessories', true], 8: ['undershirts', true], 11: ['tops', true] },
    prop: {},
  };
  const MARKUP = `
    <div id="racks-head"><div id="racks-store"></div><div id="racks-title"></div></div>
    <div id="racks-cash"></div>
    <div id="racks-item">
      <div id="racks-price"></div>
      <div id="racks-name"></div>
      <div id="racks-colour"></div>
      <div id="racks-swatches"></div>
      <div id="racks-status"></div>
    </div>
    <div id="racks-keys">
      <div><span id="racks-show">Show item</span><kbd>&#9668;</kbd><kbd>&#9658;</kbd></div>
      <div id="racks-colours"><span>Colour</span><kbd>&#9650;</kbd><kbd>&#9660;</kbd></div>
      <div id="racks-buy"><span>Buy &amp; wear</span><kbd>Enter</kbd></div>
      <div><span>Exit</span><kbd>Backspace</kbd></div>
    </div>
    <div id="racks-toast" class="racks-off"><span id="racks-toast-text"></span> <b id="racks-toast-tick">&#10003;</b></div>`;

  let root = null;
  let cash = null;
  let toastTimer = null;
  let thumbTimer = null;
  let sampleTimer = null;

  const $ = (id) => document.getElementById(id);
  const money = (n) => `$${Math.round(n).toLocaleString('en-US')}`;
  // an answer to the game (client/racks.lua), under the resource's own name
  const post = (name, data) => {
    const resource = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : 'illenium-appearance';
    fetch(`https://${resource}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data),
    }).catch(() => {});
  };

  // the overlay's own element, made the first time it is needed
  function mount() {
    if (root) return root;
    root = document.createElement('div');
    root.id = 'racks';
    root.className = 'racks-off';
    root.innerHTML = MARKUP;
    document.body.appendChild(root);
    return root;
  }

  // where a texture's thumbnail may be, the likeliest first (the greenscreener leaves the texture off the name of
  // an item's first one). Last, the picture of the item's first texture: the shape is right if the colour is not,
  // which is what there is after a quick `/screenshot first`
  function thumbs(m, texture) {
    const gender = m.gender === 'female' ? 'female' : 'male';
    const item = `${LOCAL}/${gender}_${m.kind === 'prop' ? 'prop_' : ''}${m.id}_${m.drawable}`;
    // (.webp is what _tools/cloth_thumbs draws, .png what the greenscreener shoots)
    const own = `${item}${texture ? `_${texture}` : ''}`;
    const urls = [`${own}.webp`, `${own}.png`];
    const folder = (FOLDERS[m.kind] || {})[m.id];
    if (folder) urls.push(`${CDN}/${folder[0]}${folder[1] ? `/${gender}` : ''}/${m.drawable}/${texture}.webp`);
    if (texture) urls.push(`${item}.webp`, `${item}.png`);
    return urls;
  }

  // the first of them there is: done(img, url), or done(null) when there is none. readable: its pixels are wanted
  // (a picture from elsewhere has to be asked for that way)
  function load(urls, readable, done) {
    let at = 0;
    const next = () => {
      if (at >= urls.length) return done(null);
      const url = urls[at];
      at += 1;
      const img = new Image();
      img.alt = '';
      if (readable) img.crossOrigin = 'anonymous';
      img.onload = () => done(img, url);
      img.onerror = next;
      img.src = url;
    };
    next();
  }

  // one chip per texture the item may be worn in, the one that is on framed. A chip is its number until its
  // picture has loaded, and stays a number when there is none; the pictures are asked for once the flicking
  // through the rack has stopped for a moment
  function swatches(m) {
    const box = $('racks-swatches');
    const key = [m.kind, m.id, m.gender, m.drawable, m.textures.join('.')].join(':');
    if (box.dataset.key !== key) {
      box.dataset.key = key;
      box.textContent = '';
      m.textures.forEach((texture, i) => {
        const chip = document.createElement('i');
        chip.textContent = String(i + 1);
        box.appendChild(chip);
      });
      clearTimeout(thumbTimer);
      thumbTimer = setTimeout(() => {
        if (box.dataset.key !== key) return;
        m.textures.forEach((texture, i) => {
          const chip = box.children[i];
          if (!chip) return;
          load(thumbs(m, texture), false, (img) => {
            if (img && box.dataset.key === key) chip.appendChild(img);
          });
        });
      }, 220);
    }
    Array.from(box.children).forEach((chip, i) => chip.classList.toggle('racks-on', m.textures[i] === m.texture));
  }

  // the colour of a thumbnail: the mean of what is not see-through in it (null when it cannot be read)
  function colourOf(img) {
    const size = 24;
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d');
    let data;
    try {
      ctx.drawImage(img, 0, 0, size, size);
      data = ctx.getImageData(0, 0, size, size).data;
    } catch (e) {
      return null;
    }
    let r = 0;
    let g = 0;
    let b = 0;
    let n = 0;
    for (let i = 0; i < data.length; i += 4) {
      if (data[i + 3] >= 200) {
        r += data[i];
        g += data[i + 1];
        b += data[i + 2];
        n += 1;
      }
    }
    if (!n) return null;
    const hex = (v) => Math.round(v / n).toString(16).padStart(2, '0');
    return `#${hex(r)}${hex(g)}${hex(b)}`;
  }

  // vice_hud's shop panel shows a texture as its thumbnail, or as a colour where it cannot: which thumbnail there
  // is and its colour are found here, once the flicking through the rack has stopped for a moment, and posted back
  // to the game
  function sample(m) {
    clearTimeout(sampleTimer);
    sampleTimer = setTimeout(() => {
      const colours = m.textures.map(() => null);
      const images = m.textures.map(() => null);
      let left = colours.length;
      if (!left) return;
      const done = () => {
        left -= 1;
        if (left === 0) post('racksColours', { key: m.key, colours, images });
      };
      m.textures.forEach((texture, i) => {
        load(thumbs(m, texture), true, (img, url) => {
          if (img) {
            colours[i] = colourOf(img);
            images[i] = url;
          }
          done();
        });
      });
    }, 220);
  }

  function show(m) {
    mount();
    $('racks-store').textContent = m.store || '';
    $('racks-title').textContent = m.title || '';
    $('racks-price').textContent = m.price > 0 ? money(m.price) : 'FREE';
    $('racks-name').textContent = m.name || '';
    $('racks-colour').textContent = m.colour || '';
    const status = $('racks-status');
    status.textContent = m.status || '';
    status.classList.toggle('racks-wearing', !!m.wearing);
    status.classList.toggle('racks-poor', !!m.poor);
    $('racks-show').textContent = `Show item (${m.index || 1}/${m.count || 1})`;
    $('racks-colours').classList.toggle('racks-dim', m.textures.length < 2);
    $('racks-buy').classList.toggle('racks-dim', !!m.wearing);
    // the cash: there when the server has a framework to ask and no HUD of its own showing it; it drops with a
    // flash when something was bought
    const box = $('racks-cash');
    const now = typeof m.cash === 'number' ? m.cash : null;
    box.textContent = now === null ? '' : money(now);
    if (now !== null && cash !== null && now < cash) {
      box.classList.remove('racks-spent');
      void box.offsetWidth; // (so the flash starts again)
      box.classList.add('racks-spent');
    }
    cash = now;
    swatches(m);
    root.classList.remove('racks-off');
  }

  function toast(text, failed) {
    mount();
    const box = $('racks-toast');
    $('racks-toast-text').textContent = text;
    $('racks-toast-tick').classList.toggle('racks-off', !!failed);
    box.classList.toggle('racks-failed', !!failed);
    box.classList.remove('racks-off');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => box.classList.add('racks-off'), failed ? 4000 : 2500);
  }

  function hide() {
    cash = null;
    clearTimeout(toastTimer);
    clearTimeout(thumbTimer);
    clearTimeout(sampleTimer);
    if (!root) return;
    $('racks-toast').classList.add('racks-off');
    root.classList.add('racks-off');
  }

  window.addEventListener('message', (e) => {
    const m = e.data && e.data.racks;
    if (!m || typeof m !== 'object') return;
    if (m.sample && Array.isArray(m.sample.textures)) return sample(m.sample);
    if (m.toast) return toast(String(m.toast), m.failed);
    if (m.open && Array.isArray(m.textures)) return show(m);
    hide();
  });
})();
