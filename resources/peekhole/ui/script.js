'use strict';

// ── State ─────────────────────────────────────────────────────────────────────
let playerData    = null;
let account       = null;
let myProfile     = null;
let activeTab     = 'feed';

// ── Boot ──────────────────────────────────────────────────────────────────────
async function boot() {
    playerData = await fetchNui('peekhole:getPlayerData', {}).catch(() => ({}));

    window.addEventListener('message', function (e) {
        if (!e.data) return;
        if (e.data.type === 'setTheme') {
            document.documentElement.setAttribute('data-theme', e.data.data.display || 'light');
        }    });

    // Check if this character already has a Peekhole account
    const existing = await fetchNui('peekhole:checkAccount', {}).catch(() => null);

    if (existing && existing.citizenid) {
        account = existing;
        enterApp();
    } else {
        showLoginScreen();
    }
}

// ── Login screen ──────────────────────────────────────────────────────────────
async function showLoginScreen() {
    document.getElementById('login-screen').style.display = 'flex';
    document.getElementById('app-shell').style.display    = 'none';

    // Load all configured social apps (enabled + disabled)
    const apps = await fetchNui('peekhole:getSocialApps', {}).catch(() => []);
    const container = document.getElementById('social-login-btns');

    if (apps.length) {
        container.innerHTML = apps.map(app => {
            if (app.enabled) {
                return `<button class="social-btn" style="background:${esc(app.color)};" data-app="${esc(app.key)}">
                    <i class="fas fa-sign-in-alt"></i> Continue with ${esc(app.label)}
                </button>`;
            } else {
                return `<button class="social-btn social-btn-disabled" style="background:#bbb;" data-app="${esc(app.key)}" data-label="${esc(app.label)}">
                    <i class="fas fa-sign-in-alt"></i> Continue with ${esc(app.label)}
                </button>`;
            }
        }).join('');

        container.querySelectorAll('.social-btn:not(.social-btn-disabled)').forEach(btn => {
            btn.addEventListener('click', () => doSocialLogin(btn.dataset.app, btn));
        });
        container.querySelectorAll('.social-btn-disabled').forEach(btn => {
            btn.addEventListener('click', () => toast(btn.dataset.label + ' login is not yet configured on this server.', 'err'));
        });
    } else {
        container.innerHTML = '<div style="font-size:12px;color:var(--muted);text-align:center;">No social apps configured.<br>Create an account below.</div>';
    }

    document.getElementById('btn-show-register').addEventListener('click', () => {
        document.getElementById('login-screen').querySelector('.login-hero').style.display    = 'none';
        document.getElementById('login-screen').querySelector('.login-body').style.display    = 'none';
        document.getElementById('register-form').style.display = 'flex';
        document.getElementById('register-form').style.flexDirection = 'column';
    });

    document.getElementById('btn-back-to-login').addEventListener('click', () => {
        document.getElementById('register-form').style.display = 'none';
        document.getElementById('login-screen').querySelector('.login-hero').style.display = '';
        document.getElementById('login-screen').querySelector('.login-body').style.display = '';
    });

    document.getElementById('btn-submit-register').addEventListener('click', doCreateAccount);
    document.getElementById('inp-reg-username').addEventListener('keydown', e => {
        if (e.key === 'Enter') doCreateAccount();
    });
}

async function doSocialLogin(appKey, btn) {
    const errEl = document.getElementById('login-error');
    errEl.style.display = 'none';
    btn.disabled = true;
    btn.textContent = 'Signing in…';

    const res = await fetchNui('peekhole:loginWithApp', { appKey }).catch(() => ({}));

    if (res.success) {
        account = res.account;
        enterApp();
    } else {
        errEl.textContent = res.message || 'Login failed.';
        errEl.style.display = 'block';
        btn.disabled = false;
        // restore label
        btn.innerHTML = `<i class="fas fa-sign-in-alt"></i> Continue with ${appKey}`;
    }
}

async function doCreateAccount() {
    const username = document.getElementById('inp-reg-username').value.trim();
    const errEl    = document.getElementById('register-error');
    errEl.style.display = 'none';

    if (!username) { errEl.textContent = 'Enter a username.'; errEl.style.display = 'block'; return; }

    const btn = document.getElementById('btn-submit-register');
    btn.disabled = true;
    btn.textContent = 'Creating…';

    const res = await fetchNui('peekhole:createAccount', { username }).catch(() => ({}));

    btn.disabled = false;
    btn.textContent = 'Create Account';

    if (res.success) {
        account = res.account;
        enterApp();
    } else {
        errEl.textContent = res.message || 'Failed to create account.';
        errEl.style.display = 'block';
    }
}

// ── Enter main app ────────────────────────────────────────────────────────────
function enterApp() {
    document.getElementById('login-screen').style.display = 'none';
    document.getElementById('app-shell').style.display    = 'flex';
    document.getElementById('app-shell').style.flexDirection = 'column';
    document.getElementById('app-shell').style.height    = '100%';

    if (account && account.username) {
        document.getElementById('nav-char-name').textContent = '@' + account.username;
    }

    bindTabs();
    bindModals();
    loadTab('feed');
}

// ── Tab navigation ────────────────────────────────────────────────────────────
function bindTabs() {
    document.querySelectorAll('.tab').forEach(function (btn) {
        btn.addEventListener('click', function () {
            closeCreatorView();
            loadTab(btn.dataset.tab);
        });
    });

    document.getElementById('btn-back-creator').addEventListener('click', closeCreatorView);
}

function loadTab(name) {
    activeTab = name;
    document.querySelectorAll('.tab').forEach(function (b) {
        b.classList.toggle('active', b.dataset.tab === name);
    });
    document.querySelectorAll('.tab-panel').forEach(function (p) {
        if (p.id === 'tab-creator') return;
        p.classList.toggle('active', p.id === 'tab-' + name);
    });

    if (name === 'feed')     loadFeed();
    if (name === 'discover') loadDiscover();
    if (name === 'studio')   loadStudio();
}

function openCreatorView(creatorId) {
    document.querySelectorAll('.tab-panel').forEach(function (p) { p.classList.remove('active'); });
    var el = document.getElementById('tab-creator');
    el.style.display = 'block';
    el.classList.add('active');
    fetchCreatorProfile(creatorId);
}

function closeCreatorView() {
    var el = document.getElementById('tab-creator');
    el.style.display = 'none';
    el.classList.remove('active');
    loadTab(activeTab);
}

// ── Toast ─────────────────────────────────────────────────────────────────────
var toastTimer;
function toast(msg, type) {
    var el = document.getElementById('toast');
    el.textContent = msg;
    el.className = 'show' + (type ? ' ' + type : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.className = ''; }, 3000);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// Always call this instead of el.remove() for any sheet/modal.
// Blurs any focused input FIRST so lb-phone's toggleInput(false) fires and
// game controls (arrow keys, ESC, P) are restored before the element is gone.
function dismissSheet(el) {
    if (document.activeElement && el && el.contains(document.activeElement)) {
        document.activeElement.blur();
    }
    if (el && el.parentNode) el.remove();
}

function esc(s) {
    return String(s == null ? '' : s)
        .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
        .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

function ago(ts) {
    var d = Date.now() - new Date(ts).getTime();
    var m = Math.floor(d / 60000);
    if (m < 1)  return 'Just now';
    if (m < 60) return m + 'm';
    var h = Math.floor(m / 60);
    if (h < 24) return h + 'h';
    return Math.floor(h / 24) + 'd';
}

function money(n) { return '$' + Number(n || 0).toLocaleString(); }

function avatarEl(url, cls, size) {
    size = size || 36;
    if (url) {
        return '<img class="' + esc(cls) + '" src="' + esc(url) + '" width="' + size + '" height="' + size + '" style="border-radius:50%;object-fit:cover;display:block;" onerror="this.src=\'\'" />';
    }
    return '<div class="' + esc(cls) + '" style="width:' + size + 'px;height:' + size + 'px;border-radius:50%;background:#ddd;display:flex;align-items:center;justify-content:center;font-size:' + Math.floor(size * .45) + 'px;flex-shrink:0;">👤</div>';
}

function bannerEl(url) {
    if (url) return '<img class="profile-banner" src="' + esc(url) + '" onerror="this.src=\'\'" />';
    return '<div class="profile-banner"></div>';
}

// ── FEED ──────────────────────────────────────────────────────────────────────
async function loadFeed() {
    var el = document.getElementById('feed-list');
    el.innerHTML = '<div class="spinner"></div>';

    var posts = await fetchNui('peekhole:getFeed', {}).catch(function () { return []; });

    if (!posts.length) {
        el.innerHTML = '<div class="empty"><div class="big">💙</div><h3>Nothing here yet</h3><p>Subscribe to creators in Discover to see their posts.</p></div>';
        return;
    }

    el.innerHTML = posts.map(buildPostCard).join('');
    wirePostCards(el);

}

function buildLockedOverlay(p, isSub) {
    if (isSub) {
        return '<div class="locked-overlay">'
            + '<div class="lock-icon">🔒</div>'
            + '<div class="lock-lbl">Subscribe to view</div>'
            + '<button class="subscribe-to-view-btn" data-cid="' + esc(p.creator_citizenid) + '">Subscribe</button>'
            + '</div>';
    }
    return '<div class="locked-overlay">'
        + '<div class="lock-icon">💰</div>'
        + '<div class="lock-lbl">Tip to unlock</div>'
        + '<button class="unlock-btn" data-pid="' + p.id + '" data-price="' + p.unlock_price + '">' + money(p.unlock_price) + '</button>'
        + '</div>';
}

function buildMediaEl(p, isLocked, isSub) {
    if (isLocked) {
        var preview = p.media_url
            ? (p.media_type === 'video'
                ? '<video src="' + esc(p.media_url) + '" class="media-blur"></video>'
                : '<img src="' + esc(p.media_url) + '" class="media-blur" />')
            : '<div class="media-blur-placeholder"></div>';
        return '<div class="post-media-wrap locked">' + preview + buildLockedOverlay(p, isSub) + '</div>';
    }
    if (p.media_type === 'video') {
        return '<div class="post-media-wrap"><video src="' + esc(p.media_url) + '" controls playsinline></video></div>';
    }
    return '<div class="post-media-wrap"><img src="' + esc(p.media_url) + '" /></div>';
}

function buildPostCard(p) {
    var isLocked = !p.is_unlocked;
    var media = buildMediaEl(p, isLocked, false);

    return '<div class="post-card" data-pid="' + p.id + '">'
        + '<div class="post-head">'
        + '<div data-cid="' + esc(p.creator_citizenid) + '" style="cursor:pointer">' + avatarEl(p.creator_pic, 'post-avatar', 36) + '</div>'
        + '<div>'
        + '<div class="post-creator" data-cid="' + esc(p.creator_citizenid) + '">' + esc(p.creator_name) + '</div>'
        + '<div class="post-time">' + ago(p.created_at) + '</div>'
        + '</div></div>'
        + (p.caption ? '<div class="post-caption">' + esc(p.caption) + '</div>' : '')
        + media
        + buildPostActions(p)
        + '<div class="comment-section" id="comments-' + p.id + '" style="display:none;"></div>'
        + '</div>';
}

function buildPostActions(p) {
    var liked = p.is_liked == 1 || p.is_liked === true;
    return '<div class="post-actions">'
        + '<button class="action-btn like-btn' + (liked ? ' liked' : '') + '" data-pid="' + p.id + '">'
        + '<i class="fas fa-heart"></i> <span class="like-count">' + (p.like_count || 0) + '</span>'
        + '</button>'
        + '<button class="action-btn comment-btn" data-pid="' + p.id + '">'
        + '<i class="fas fa-comment"></i> <span class="comment-count">' + (p.comment_count || 0) + '</span>'
        + '</button>'
        + '</div>';
}

function wirePostCards(container) {
    container.querySelectorAll('[data-cid]').forEach(function (el) {
        el.addEventListener('click', function () { openCreatorView(el.dataset.cid); });
    });
    container.querySelectorAll('.unlock-btn').forEach(function (btn) {
        btn.addEventListener('click', function (e) { e.stopPropagation(); doUnlock(btn.dataset.pid, btn.dataset.price, btn); });
    });
    container.querySelectorAll('.subscribe-to-view-btn').forEach(function (btn) {
        btn.addEventListener('click', function (e) { e.stopPropagation(); openCreatorView(btn.dataset.cid); });
    });
    container.querySelectorAll('.like-btn').forEach(function (btn) {
        btn.addEventListener('click', function (e) { e.stopPropagation(); doToggleLike(btn); });
    });
    container.querySelectorAll('.comment-btn').forEach(function (btn) {
        btn.addEventListener('click', function (e) { e.stopPropagation(); toggleComments(btn.dataset.pid); });
    });
}

function doUnlock(postId, price, btn) {
    showConfirm(
        'Tip to Unlock',
        'Pay ' + money(price) + ' from your bank to unlock this post.',
        'Pay ' + money(price),
        async function () {
            btn.disabled = true;
            btn.textContent = 'Processing…';
            var res = await fetchNui('peekhole:unlockPost', { postId: +postId }).catch(function () { return {}; });
            if (res.success) {
                toast('Post unlocked!', 'ok');
                var wrap = btn.closest('.post-media-wrap');
                if (wrap && res.mediaUrl) {
                    wrap.classList.remove('locked');
                    if (/\.(mp4|webm|mov)/i.test(res.mediaUrl)) {
                        wrap.innerHTML = '<video src="' + esc(res.mediaUrl) + '" controls playsinline></video>';
                    } else {
                        wrap.innerHTML = '<img src="' + esc(res.mediaUrl) + '" />';
                    }
                }
            } else {
                toast(res.message || 'Failed to unlock.', 'err');
                btn.disabled = false;
                btn.textContent = money(price);
            }
        }
    );
}

// ── Likes ─────────────────────────────────────────────────────────────────────
async function doToggleLike(btn) {
    var postId = btn.dataset.pid;
    var countEl = btn.querySelector('.like-count');
    var isLiked = btn.classList.contains('liked');

    // Optimistic update
    btn.classList.toggle('liked');
    countEl.textContent = parseInt(countEl.textContent) + (isLiked ? -1 : 1);

    var res = await fetchNui('peekhole:toggleLike', { postId: +postId }).catch(function () { return {}; });
    if (!res.success) {
        // Revert
        btn.classList.toggle('liked');
        countEl.textContent = parseInt(countEl.textContent) + (isLiked ? 1 : -1);
    }
}

// ── Comments ──────────────────────────────────────────────────────────────────
async function toggleComments(postId) {
    var section = document.getElementById('comments-' + postId);
    if (!section) return;

    if (section.style.display !== 'none') {
        section.style.display = 'none';
        return;
    }

    section.style.display = 'block';
    section.innerHTML = '<div class="spinner" style="margin:10px auto;"></div>';

    var comments = await fetchNui('peekhole:getComments', { postId: +postId }).catch(function () { return []; });
    renderComments(section, postId, comments);
}

function renderComments(section, postId, comments) {
    var list = comments.map(function (c) {
        return '<div class="comment-row">'
            + '<span class="comment-user">@' + esc(c.username) + '</span>'
            + '<span class="comment-text">' + esc(c.comment) + '</span>'
            + '</div>';
    }).join('');

    section.innerHTML = (list || '<div style="padding:8px 12px;font-size:12px;color:var(--muted);">No comments yet. Be the first!</div>')
        + '<div class="comment-input-row">'
        + '<input class="comment-inp" type="text" placeholder="Add a comment…" maxlength="300" id="cinp-' + postId + '" />'
        + '<button class="comment-send-btn" data-pid="' + postId + '"><i class="fas fa-paper-plane"></i></button>'
        + '</div>';

    var inp = section.querySelector('.comment-inp');
    var sendBtn = section.querySelector('.comment-send-btn');

    sendBtn.addEventListener('click', function () { submitComment(postId, inp, section); });
    inp.addEventListener('keydown', function (e) { if (e.key === 'Enter') submitComment(postId, inp, section); });
}

async function submitComment(postId, inp, section) {
    var text = inp.value.trim();
    if (!text) return;

    inp.disabled = true;
    var res = await fetchNui('peekhole:addComment', { postId: +postId, comment: text }).catch(function () { return {}; });
    inp.disabled = false;

    if (res.success) {
        inp.value = '';
        inp.blur();
        // Append new comment optimistically
        var newRow = document.createElement('div');
        newRow.className = 'comment-row';
        newRow.innerHTML = '<span class="comment-user">@' + esc(res.username) + '</span>'
            + '<span class="comment-text">' + esc(res.comment) + '</span>';
        section.querySelector('.comment-input-row').before(newRow);

        // Update comment count on button
        var card = section.closest('.post-card');
        if (card) {
            var countEl = card.querySelector('.comment-count');
            if (countEl) countEl.textContent = parseInt(countEl.textContent) + 1;
        }
    } else {
        toast(res.message || 'Failed to post comment.', 'err');
    }
}

// ── DISCOVER ──────────────────────────────────────────────────────────────────
async function loadDiscover() {
    var el = document.getElementById('discover-list');
    el.innerHTML = '<div class="spinner"></div>';

    var creators = await fetchNui('peekhole:getCreators', {}).catch(function () { return []; });

    if (!creators.length) {
        el.innerHTML = '<div class="empty"><div class="big">🔍</div><h3>No creators yet</h3><p>Set up your page in My Page to be the first!</p></div>';
        return;
    }

    var grid = document.createElement('div');
    grid.className = 'creator-grid';

    creators.forEach(function (c) {
        var isSubbed    = c.is_subscribed == 1 || c.is_subscribed === true;
        var isFree      = !c.subscription_price || +c.subscription_price === 0;
        var priceClass  = isSubbed ? 'cc-price subbed' : isFree ? 'cc-price free' : 'cc-price';
        var priceTxt    = isSubbed ? '✓ Subscribed' : isFree ? 'Free' : money(c.subscription_price) + '/mo';

        var card = document.createElement('div');
        card.className = 'creator-card';
        card.innerHTML = (c.banner_pic
            ? '<img class="cc-banner" src="' + esc(c.banner_pic) + '" onerror="this.src=\'\'" />'
            : '<div class="cc-banner"></div>')
            + '<div class="cc-body">'
            + '<div class="cc-avatar-wrap">' + avatarEl(c.profile_pic, 'cc-avatar', 36) + '</div>'
            + '<div class="cc-name">' + esc(c.display_name) + '</div>'
            + '<div class="cc-meta">' + c.post_count + ' posts · ' + c.sub_count + ' fans</div>'
            + '<div class="' + priceClass + '">' + priceTxt + '</div>'
            + '</div>';
        card.addEventListener('click', function () { openCreatorView(c.citizenid); });
        grid.appendChild(card);
    });

    el.innerHTML = '';
    el.appendChild(grid);
}

// ── CREATOR PROFILE ───────────────────────────────────────────────────────────
async function fetchCreatorProfile(creatorId) {
    var el = document.getElementById('creator-detail');
    el.innerHTML = '<div class="spinner"></div>';

    var data = await fetchNui('peekhole:getCreatorProfile', { creatorId: creatorId }).catch(function () { return null; });

    if (!data || !data.citizenid) {
        el.innerHTML = '<div class="empty"><div class="big">😕</div><h3>Profile not found</h3></div>';
        return;
    }

    document.getElementById('creator-nav-name').textContent = data.display_name;

    var isSubbed = data.is_subscribed == 1 || data.is_subscribed === true;
    var isFree   = !data.subscription_price || +data.subscription_price === 0;
    var subTxt, subCls;
    if (isSubbed)   { subTxt = '✓ Already Subscribed'; subCls = 'subscribe-btn subbed'; }
    else if (isFree){ subTxt = 'Subscribe (Free)';      subCls = 'subscribe-btn'; }
    else            { subTxt = 'Subscribe · ' + money(data.subscription_price) + '/mo'; subCls = 'subscribe-btn'; }

    el.innerHTML = bannerEl(data.banner_pic)
        + '<div class="profile-body">'
        + '<div class="profile-avatar-wrap">' + avatarEl(data.profile_pic, 'profile-avatar', 52) + '</div>'
        + '<div class="profile-name">' + esc(data.display_name) + '</div>'
        + (data.bio ? '<div class="profile-bio">' + esc(data.bio) + '</div>' : '')
        + '<div class="profile-stats">'
        + '<div class="pstat"><div class="val">' + data.post_count + '</div><div class="lbl">Posts</div></div>'
        + '<div class="pstat"><div class="val">' + data.sub_count + '</div><div class="lbl">Fans</div></div>'
        + '</div>'
        + '<div style="display:flex;gap:8px;margin-top:10px;">'
        + '<button class="' + subCls + '" id="sub-btn" style="flex:1;"' + (isSubbed ? ' disabled' : '') + '>' + subTxt + '</button>'
        + '<button class="btn btn-ghost dm-btn" id="dm-btn" data-cid="' + esc(data.citizenid) + '" style="padding:10px 14px;"><i class="fas fa-envelope"></i></button>'
        + '</div>'
        + '</div>'
        + '<div class="divider"></div>'
        + '<div id="creator-posts">' + buildCreatorPostList(data.posts || [], isSubbed) + '</div>';

    if (!isSubbed) {
        el.querySelector('#sub-btn').addEventListener('click', function () { doSubscribe(data); });
    }

    el.querySelectorAll('.unlock-btn').forEach(function (btn) {
        btn.addEventListener('click', function (e) { e.stopPropagation(); doUnlock(btn.dataset.pid, btn.dataset.price, btn); });
    });
    el.querySelectorAll('.subscribe-to-view-btn').forEach(function (btn) {
        btn.addEventListener('click', function (e) { e.stopPropagation(); doSubscribe(data); });
    });
    el.querySelectorAll('.like-btn').forEach(function (btn) {
        btn.addEventListener('click', function (e) { e.stopPropagation(); doToggleLike(btn); });
    });
    el.querySelectorAll('.comment-btn').forEach(function (btn) {
        btn.addEventListener('click', function (e) { e.stopPropagation(); toggleComments(btn.dataset.pid); });
    });

    var dmBtn = el.querySelector('#dm-btn');
    if (dmBtn) {
        dmBtn.addEventListener('click', async function () {
            var phone = await fetchNui('peekhole:getCreatorPhone', { creatorId: data.citizenid }).catch(function () { return null; });
            if (phone) {
                try { SetContactModal(phone); } catch (e) { toast('Could not open messages.', 'err'); }
            } else {
                toast('This creator has no phone number on file.', 'err');
            }
        });
    }
}

function buildCreatorPostList(posts, isSubbed) {
    if (!posts.length) return '<div class="empty"><div class="big">📭</div><h3>No posts yet</h3></div>';

    return posts.map(function (p) {
        var isLocked = !p.is_unlocked;
        // If not subscribed and post has no individual price, it's sub-locked
        var isSubLocked = isLocked && (!p.unlock_price || +p.unlock_price === 0);
        var media = buildMediaEl(p, isLocked, isSubLocked);

        return '<div class="post-card" data-pid="' + p.id + '">'
            + '<div class="post-head" style="justify-content:space-between;">'
            + '<span class="post-time">' + ago(p.created_at) + '</span>'
            + (isLocked && +p.unlock_price > 0 ? '<span style="font-size:11px;font-weight:700;color:var(--blue);">Tip: ' + money(p.unlock_price) + '</span>' : '')
            + '</div>'
            + (p.caption && !isSubLocked ? '<div class="post-caption">' + esc(p.caption) + '</div>' : '')
            + media
            + (!isLocked ? buildPostActions(p) : '')
            + (!isLocked ? '<div class="comment-section" id="comments-' + p.id + '" style="display:none;"></div>' : '')
            + '</div>';
    }).join('');
}

function doSubscribe(creator) {
    var isFree = !creator.subscription_price || +creator.subscription_price === 0;
    var label  = isFree ? 'Subscribe (Free)' : 'Pay ' + money(creator.subscription_price);
    var msg    = isFree
        ? 'Subscribe to ' + creator.display_name + ' for free.'
        : 'Pay ' + money(creator.subscription_price) + '/mo from your bank to subscribe to ' + creator.display_name + '.';

    showConfirm('Subscribe', msg, label, async function () {
        var res = await fetchNui('peekhole:subscribe', { creatorId: creator.citizenid }).catch(function () { return {}; });
        if (res.success) {
            toast(res.message, 'ok');
            fetchCreatorProfile(creator.citizenid);
        } else {
            toast(res.message || 'Failed to subscribe.', 'err');
        }
    });
}

// ── STUDIO ────────────────────────────────────────────────────────────────────
async function loadStudio() {
    var el = document.getElementById('studio-content');
    el.innerHTML = '<div class="spinner"></div>';

    var data = await fetchNui('peekhole:getMyProfile', {}).catch(function () { return null; });
    myProfile = data && data.exists ? data : null;

    if (!myProfile) {
        el.innerHTML = '<button class="logout-btn" id="btn-logout"><i class="fas fa-sign-out-alt"></i> Log Out</button>'
            + '<div style="background:var(--blue);padding:28px 20px;text-align:center;">'
            + '<div style="font-size:22px;font-weight:900;font-style:italic;color:#fff;margin-bottom:6px;">Peekhole</div>'
            + '<div style="font-size:12px;color:rgba(255,255,255,.85);">Creator Studio</div>'
            + '</div>'
            + '<div class="empty" style="padding-top:36px;">'
            + '<div class="big">🌟</div>'
            + '<h3>Become a Creator</h3>'
            + '<p>Set up your page and start earning from subscriptions and posts.</p>'
            + '<button class="btn btn-blue" id="btn-create-page" style="margin-top:18px;padding:11px 28px;">Create My Page</button>'
            + '</div>'
            + '<div class="of-footer">© 2024 Peekhole</div>';
        document.getElementById('btn-logout').addEventListener('click', doLogout);
        document.getElementById('btn-create-page').addEventListener('click', function () { openProfileModal(false); });
        return;
    }

    el.innerHTML = '<button class="logout-btn" id="btn-logout"><i class="fas fa-sign-out-alt"></i> Log Out</button>'
        + '<div class="studio-head">'
        + avatarEl(data.profile_pic, 'studio-avatar', 50)
        + '<div style="flex:1">'
        + '<div class="studio-name">' + esc(data.display_name) + '</div>'
        + '<div class="studio-sub">' + money(data.subscription_price) + '/mo · ' + data.sub_count + ' fans</div>'
        + '</div>'
        + '<button class="btn btn-ghost" id="btn-edit-profile" style="font-size:12px;padding:7px 12px;">Edit</button>'
        + '</div>'
        + '<div class="stat-row">'
        + '<div class="stat-box"><div class="val">' + data.posts.length + '</div><div class="lbl">Posts</div></div>'
        + '<div class="stat-box"><div class="val">' + data.sub_count + '</div><div class="lbl">Fans</div></div>'
        + '<div class="stat-box"><div class="val">' + money(data.total_earnings) + '</div><div class="lbl">Earned</div></div>'
        + '</div>'
        + '<div style="padding:12px;display:flex;flex-direction:column;gap:8px;">'
        + '<button class="btn btn-blue btn-full" id="btn-new-post"><i class="fas fa-plus"></i> New Post</button>'
        + '</div>'
        + '<div class="section-lbl">My Posts</div>'
        + '<div class="my-posts-grid" id="my-posts-grid">' + buildMyGrid(data.posts) + '</div>'
        + '<div class="of-footer">© 2024 Peekhole</div>';

    document.getElementById('btn-logout').addEventListener('click', doLogout);
    document.getElementById('btn-edit-profile').addEventListener('click', function () { openProfileModal(true); });
    document.getElementById('btn-new-post').addEventListener('click', openPostModal);
    document.querySelectorAll('.mpost-thumb').forEach(function (t) {
        t.addEventListener('click', function () { confirmDeletePost(t.dataset.pid); });
    });
}

function buildMyGrid(posts) {
    if (!posts.length) {
        return '<div style="grid-column:1/-1"><div class="empty"><div class="big">📷</div><h3>No posts yet</h3><p>Tap New Post to upload your first.</p></div></div>';
    }
    return posts.map(function (p) {
        var thumb = p.media_type === 'video'
            ? '<video src="' + esc(p.media_url) + '" muted></video>'
            : '<img src="' + esc(p.media_url) + '" />';
        return '<div class="mpost-thumb" data-pid="' + p.id + '">'
            + thumb
            + (+p.unlock_price > 0 ? '<div class="mpost-price">' + money(p.unlock_price) + '</div>' : '')
            + '</div>';
    }).join('');
}

function confirmDeletePost(postId) {
    showConfirm('Delete Post', 'This cannot be undone.', 'Delete', async function () {
        var res = await fetchNui('peekhole:deletePost', { postId: +postId }).catch(function () { return {}; });
        if (res.success) { toast('Post deleted.', 'ok'); loadStudio(); }
        else             { toast(res.message || 'Error.', 'err'); }
    });
}

// ── PROFILE MODAL ─────────────────────────────────────────────────────────────
function openProfileModal(editing) {
    document.getElementById('profile-sheet-title').textContent = editing ? 'Edit My Page' : 'Create My Page';

    if (editing && myProfile) {
        document.getElementById('inp-dname').value    = myProfile.display_name || '';
        document.getElementById('inp-bio').value      = myProfile.bio || '';
        document.getElementById('inp-subprice').value = myProfile.subscription_price || 0;
        document.getElementById('val-pfp').value      = myProfile.profile_pic || '';
        document.getElementById('val-banner').value   = myProfile.banner_pic || '';
        if (myProfile.profile_pic) {
            document.getElementById('pick-pfp').innerHTML = '<img src="' + esc(myProfile.profile_pic) + '" style="width:100%;max-height:100px;object-fit:cover;border-radius:6px;" />';
        } else {
            resetPicker('pick-pfp', 'fas fa-image', 'Tap to pick profile photo');
        }
        if (myProfile.banner_pic) {
            document.getElementById('pick-banner').innerHTML = '<img src="' + esc(myProfile.banner_pic) + '" style="width:100%;max-height:70px;object-fit:cover;border-radius:6px;" />';
        } else {
            resetPicker('pick-banner', 'fas fa-mountain', 'Tap to pick banner image');
        }
    } else {
        document.getElementById('inp-dname').value    = '';
        document.getElementById('inp-bio').value      = '';
        document.getElementById('inp-subprice').value = '';
        document.getElementById('val-pfp').value      = '';
        document.getElementById('val-banner').value   = '';
        resetPicker('pick-pfp',    'fas fa-image',    'Tap to pick profile photo');
        resetPicker('pick-banner', 'fas fa-mountain', 'Tap to pick banner image');
    }

    document.getElementById('modal-profile').style.display = 'flex';
}

function bindModals() {
    document.getElementById('pick-pfp').addEventListener('click', async function () {
        var url = await pickImageUrl();
        if (!url) return;
        document.getElementById('val-pfp').value = url;
        document.getElementById('pick-pfp').innerHTML = '<img src="' + esc(url) + '" style="width:100%;max-height:100px;object-fit:cover;border-radius:6px;" />';
    });

    document.getElementById('pick-banner').addEventListener('click', async function () {
        var url = await pickImageUrl();
        if (!url) return;
        document.getElementById('val-banner').value = url;
        document.getElementById('pick-banner').innerHTML = '<img src="' + esc(url) + '" style="width:100%;max-height:70px;object-fit:cover;border-radius:6px;" />';
    });

    document.getElementById('btn-cancel-profile').addEventListener('click', function () {
        if (document.activeElement) document.activeElement.blur();
        document.getElementById('modal-profile').style.display = 'none';
    });

    document.getElementById('btn-save-profile').addEventListener('click', saveProfile);

    document.getElementById('pick-post-media').addEventListener('click', async function () {
        var result = await pickAnyMedia();
        if (!result) return;
        document.getElementById('val-post-url').value  = result.url;
        document.getElementById('val-post-type').value = result.type;
        var el = document.getElementById('pick-post-media');
        if (result.type === 'video') {
            el.innerHTML = '<video src="' + esc(result.url) + '" controls></video>';
        } else {
            el.innerHTML = '<img src="' + esc(result.url) + '" />';
        }
    });

    document.getElementById('btn-cancel-post').addEventListener('click', function () {
        if (document.activeElement) document.activeElement.blur();
        document.getElementById('modal-post').style.display = 'none';
    });

    document.getElementById('btn-submit-post').addEventListener('click', submitPost);
}

// ── Media picker sheet (no lb-phone SetContextMenu dependency) ────────────────
function showMediaOptions(includeVideos, callback) {
    var existing = document.getElementById('media-picker-sheet');
    if (existing) existing.remove();

    var el = document.createElement('div');
    el.id = 'media-picker-sheet';
    el.className = 'modal-back';
    el.style.display = 'flex';
    el.innerHTML =
        '<div class="sheet">'
        + '<div class="sheet-handle"></div>'
        + '<h2 class="sheet-title">Add Media</h2>'
        + '<button class="media-option-btn" id="mopt-camera"><i class="fas fa-camera"></i> Take Photo' + (includeVideos ? ' / Video' : '') + '</button>'
        + '<button class="media-option-btn" id="mopt-gallery"><i class="fas fa-images"></i> Choose from Gallery</button>'
        + '<button class="btn btn-ghost btn-full" id="mopt-cancel" style="margin-top:8px;">Cancel</button>'
        + '</div>';

    document.getElementById('content').appendChild(el);

    document.getElementById('mopt-cancel').addEventListener('click', function () {
        dismissSheet(el); callback(null);
    });

    document.getElementById('mopt-camera').addEventListener('click', function () {
        dismissSheet(el);
        try {
            UseComponent(function (result) {
                callback(parseMediaResult(result));
            }, { component: 'camera' });
        } catch (e) { callback(null); }
    });

    document.getElementById('mopt-gallery').addEventListener('click', function () {
        dismissSheet(el);
        try {
            SelectGallery({
                cb: function (result) {
                    callback(parseMediaResult(result));
                },
                includeVideos: includeVideos,
            });
        } catch (e) { callback(null); }
    });
}

function pickImageUrl() {
    return new Promise(function (resolve) {
        showMediaOptions(false, function (result) {
            resolve(result ? result.src : null);
        });
    });
}

function pickAnyMedia() {
    return new Promise(function (resolve) {
        showMediaOptions(true, function (result) {
            if (!result) return resolve(null);
            resolve({ url: result.src, type: result.isVideo ? 'video' : 'image' });
        });
    });
}

function parseMediaResult(result) {
    if (!result) return null;
    // lb-phone may return a plain string, or an object with src/url/image
    var src = typeof result === 'string'
        ? result
        : (result.src || result.url || result.image || result.photo || null);
    if (!src) return null;
    var isVideo = result.isVideo
        || result.video
        || /\.(mp4|webm|mov|avi)/i.test(src);
    return { src: src, isVideo: !!isVideo };
}

function resetPicker(id, iconClass, label) {
    document.getElementById(id).innerHTML = '<i class="' + iconClass + '"></i> ' + label;
}

async function saveProfile() {
    var editing     = document.getElementById('profile-sheet-title').textContent.startsWith('Edit');
    var displayName = document.getElementById('inp-dname').value.trim();
    var bio         = document.getElementById('inp-bio').value.trim();
    var subPrice    = parseInt(document.getElementById('inp-subprice').value) || 0;
    var profilePic  = document.getElementById('val-pfp').value;
    var bannerPic   = document.getElementById('val-banner').value;

    if (!displayName || displayName.length < 3) {
        toast('Display name must be at least 3 characters.', 'err');
        return;
    }

    var btn = document.getElementById('btn-save-profile');
    btn.disabled = true;
    btn.textContent = 'Saving…';

    var event = editing ? 'peekhole:updateProfile' : 'peekhole:createProfile';
    var res = await fetchNui(event, { displayName: displayName, bio: bio, subPrice: subPrice, profilePic: profilePic, bannerPic: bannerPic }).catch(function () { return {}; });

    btn.disabled = false;
    btn.textContent = 'Save';

    if (res.success) {
        toast(res.message, 'ok');
        if (document.activeElement) document.activeElement.blur();
        document.getElementById('modal-profile').style.display = 'none';
        loadStudio();
    } else {
        toast(res.message || 'Save failed.', 'err');
    }
}

// ── POST MODAL ────────────────────────────────────────────────────────────────
function openPostModal() {
    document.getElementById('inp-caption').value    = '';
    document.getElementById('inp-post-price').value = '';
    document.getElementById('val-post-url').value   = '';
    document.getElementById('val-post-type').value  = 'image';
    resetPicker('pick-post-media', 'fas fa-camera', 'Tap to pick photo or video');
    document.getElementById('modal-post').style.display = 'flex';
}

async function submitPost() {
    var mediaUrl    = document.getElementById('val-post-url').value;
    var mediaType   = document.getElementById('val-post-type').value || 'image';
    var caption     = document.getElementById('inp-caption').value.trim();
    var unlockPrice = parseInt(document.getElementById('inp-post-price').value) || 0;

    if (!mediaUrl) { toast('Pick a photo or video first.', 'err'); return; }

    var btn = document.getElementById('btn-submit-post');
    btn.disabled = true;
    btn.textContent = 'Posting…';

    var res = await fetchNui('peekhole:createPost', { mediaUrl: mediaUrl, mediaType: mediaType, caption: caption, unlockPrice: unlockPrice }).catch(function () { return {}; });

    btn.disabled = false;
    btn.textContent = 'Post';

    if (res.success) {
        toast(res.message, 'ok');
        if (document.activeElement) document.activeElement.blur();
        document.getElementById('modal-post').style.display = 'none';
        loadStudio();
    } else {
        toast(res.message || 'Failed to post.', 'err');
    }
}

// ── Logout ────────────────────────────────────────────────────────────────────
function doLogout() {
    showConfirm(
        'Log Out',
        'You will need to sign in again next time you open the app.',
        'Log Out',
        async function () {
            await fetchNui('peekhole:logout', {}).catch(function () {});
            account   = null;
            myProfile = null;
            activeTab = 'feed';
            showLoginScreen();
        }
    );
}

// ── In-app confirm sheet (no lb-phone dependency) ─────────────────────────────
function showConfirm(title, body, confirmLabel, onConfirm) {
    var existing = document.getElementById('confirm-sheet');
    if (existing) dismissSheet(existing);

    var el = document.createElement('div');
    el.id = 'confirm-sheet';
    el.className = 'modal-back';
    el.innerHTML =
        '<div class="sheet" style="text-align:center;">'
        + '<div class="sheet-handle"></div>'
        + '<h2 class="sheet-title">' + esc(title) + '</h2>'
        + '<p style="font-size:13px;color:var(--muted);margin-bottom:18px;">' + esc(body) + '</p>'
        + '<div class="btn-row">'
        + '<button class="btn btn-ghost" id="confirm-cancel">Cancel</button>'
        + '<button class="btn btn-danger" id="confirm-ok">' + esc(confirmLabel) + '</button>'
        + '</div></div>';

    document.getElementById('content').appendChild(el);

    document.getElementById('confirm-cancel').addEventListener('click', function () { dismissSheet(el); });
    document.getElementById('confirm-ok').addEventListener('click', function () {
        dismissSheet(el);
        onConfirm();
    });
}

// ── Entry point ───────────────────────────────────────────────────────────────
boot();
