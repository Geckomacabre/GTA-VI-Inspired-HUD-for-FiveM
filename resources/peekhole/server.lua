local QBCore = exports['qb-core']:GetCoreObject()

-- ─── Auto-migrate: create tables if they don't exist ─────────────────────────
-- This runs once on resource start so the peekhole.sql file never needs
-- to be manually imported into the database.

CreateThread(function()
    -- The tables keep Lonely Mans' names, so a server that ran it before the
    -- rename keeps every creator, post and subscription.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lonelymans_profiles` (
            `citizenid`          VARCHAR(50)  NOT NULL,
            `display_name`       VARCHAR(50)  NOT NULL,
            `bio`                TEXT         DEFAULT NULL,
            `profile_pic`        TEXT         DEFAULT NULL,
            `banner_pic`         TEXT         DEFAULT NULL,
            `subscription_price` INT(11)      NOT NULL DEFAULT 0,
            `total_earnings`     INT(11)      NOT NULL DEFAULT 0,
            `created_at`         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`citizenid`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lonelymans_posts` (
            `id`                INT(11)      NOT NULL AUTO_INCREMENT,
            `creator_citizenid` VARCHAR(50)  NOT NULL,
            `caption`           TEXT         DEFAULT NULL,
            `media_url`         TEXT         NOT NULL,
            `media_type`        VARCHAR(10)  NOT NULL DEFAULT 'image',
            `unlock_price`      INT(11)      NOT NULL DEFAULT 0,
            `created_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_creator` (`creator_citizenid`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lonelymans_subscriptions` (
            `id`                   INT(11)     NOT NULL AUTO_INCREMENT,
            `subscriber_citizenid` VARCHAR(50) NOT NULL,
            `creator_citizenid`    VARCHAR(50) NOT NULL,
            `created_at`           TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `unique_sub` (`subscriber_citizenid`, `creator_citizenid`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lonelymans_unlocked_posts` (
            `id`         INT(11)     NOT NULL AUTO_INCREMENT,
            `citizenid`  VARCHAR(50) NOT NULL,
            `post_id`    INT(11)     NOT NULL,
            `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `unique_unlock` (`citizenid`, `post_id`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lonelymans_accounts` (
            `citizenid`   VARCHAR(50)  NOT NULL,
            `username`    VARCHAR(50)  NOT NULL,
            `avatar_url`  TEXT         DEFAULT NULL,
            `linked_app`  VARCHAR(20)  NOT NULL DEFAULT 'custom',
            `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`citizenid`),
            UNIQUE KEY `unique_username` (`username`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lonelymans_likes` (
            `id`         INT(11)     NOT NULL AUTO_INCREMENT,
            `post_id`    INT(11)     NOT NULL,
            `citizenid`  VARCHAR(50) NOT NULL,
            `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `unique_like` (`post_id`, `citizenid`),
            KEY `idx_post` (`post_id`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lonelymans_comments` (
            `id`         INT(11)      NOT NULL AUTO_INCREMENT,
            `post_id`    INT(11)      NOT NULL,
            `citizenid`  VARCHAR(50)  NOT NULL,
            `username`   VARCHAR(50)  NOT NULL,
            `comment`    TEXT         NOT NULL,
            `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_post` (`post_id`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lonelymans_streams` (
            `id`                INT(11)      NOT NULL AUTO_INCREMENT,
            `creator_citizenid` VARCHAR(50)  NOT NULL,
            `title`             VARCHAR(100) NOT NULL DEFAULT 'Live Stream',
            `instapic_user`     VARCHAR(50)  NOT NULL DEFAULT '',
            `price`             INT(11)      NOT NULL DEFAULT 0,
            `viewer_count`      INT(11)      NOT NULL DEFAULT 0,
            `created_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `ended_at`          TIMESTAMP    NULL DEFAULT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_live` (`creator_citizenid`, `ended_at`)
        )
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lonelymans_stream_access` (
            `id`         INT(11)     NOT NULL AUTO_INCREMENT,
            `stream_id`  INT(11)     NOT NULL,
            `citizenid`  VARCHAR(50) NOT NULL,
            `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `unique_access` (`stream_id`, `citizenid`)
        )
    ]])

    print('^2[Peekhole]^7 Database tables ready.')
end)

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function NotifyPlayer(citizenid, title, content)
    local player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if not player then return end
    exports['lb-phone']:SendNotification(player.PlayerData.source, {
        app     = 'Peekhole',
        title   = title,
        content = content,
        icon    = 'nui://peekhole/ui/icon.svg',
    })
end

local function GetCitizenId(source)
    local Player = QBCore.Functions.GetPlayer(source)
    return Player and Player.PlayerData.citizenid or nil
end

local function GetPlayerBank(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return 0 end
    return Player.PlayerData.money['bank'] or 0
end

local function RemoveBank(source, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end
    return Player.Functions.RemoveMoney('bank', amount, 'peekhole-payment')
end

-- Pay a creator — works whether they are online or offline
local function PayCreator(creatorCitizenId, amount)
    local cut = math.floor(amount * Config.CreatorCut)
    if cut <= 0 then return end

    local onlinePlayer = QBCore.Functions.GetPlayerByCitizenId(creatorCitizenId)
    if onlinePlayer then
        onlinePlayer.Functions.AddMoney('bank', cut, 'peekhole-earnings')
    else
        local moneyJson = MySQL.scalar.await('SELECT money FROM players WHERE citizenid = ?', { creatorCitizenId })
        if moneyJson then
            local money = json.decode(moneyJson)
            money.bank = (money.bank or 0) + cut
            MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?', { json.encode(money), creatorCitizenId })
        end
    end

    MySQL.update.await('UPDATE lonelymans_profiles SET total_earnings = total_earnings + ? WHERE citizenid = ?', { cut, creatorCitizenId })
end

-- ─── Feed ─────────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:getFeed', function(source, cb)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({}) end

    local posts = MySQL.query.await([[
        SELECT
            p.id,
            p.creator_citizenid,
            p.caption,
            p.media_type,
            p.unlock_price,
            p.created_at,
            pr.display_name  AS creator_name,
            pr.profile_pic   AS creator_pic,
            p.media_url,
            (p.creator_citizenid = ? OR ul.id IS NOT NULL OR p.unlock_price = 0) AS is_unlocked,
            (SELECT COUNT(*) FROM lonelymans_likes    WHERE post_id = p.id)                      AS like_count,
            (SELECT COUNT(*) FROM lonelymans_likes    WHERE post_id = p.id AND citizenid = ?)    AS is_liked,
            (SELECT COUNT(*) FROM lonelymans_comments WHERE post_id = p.id)                      AS comment_count
        FROM lonelymans_posts p
        INNER JOIN lonelymans_profiles pr
            ON pr.citizenid = p.creator_citizenid
        LEFT JOIN lonelymans_subscriptions s
            ON s.creator_citizenid = p.creator_citizenid
            AND s.subscriber_citizenid = ?
        LEFT JOIN lonelymans_unlocked_posts ul
            ON ul.post_id = p.id AND ul.citizenid = ?
        WHERE s.id IS NOT NULL
           OR p.creator_citizenid = ?
        ORDER BY p.created_at DESC
        LIMIT 50
    ]], { citizenid, citizenid, citizenid, citizenid, citizenid })

    cb(posts or {})
end)

-- ─── Discover ────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:getCreators', function(source, cb)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({}) end

    local creators = MySQL.query.await([[
        SELECT
            pr.citizenid,
            pr.display_name,
            pr.bio,
            pr.profile_pic,
            pr.banner_pic,
            pr.subscription_price,
            (SELECT COUNT(*) FROM lonelymans_posts WHERE creator_citizenid = pr.citizenid)         AS post_count,
            (SELECT COUNT(*) FROM lonelymans_subscriptions WHERE creator_citizenid = pr.citizenid) AS sub_count,
            (SELECT id FROM lonelymans_subscriptions
             WHERE creator_citizenid = pr.citizenid AND subscriber_citizenid = ? LIMIT 1) IS NOT NULL AS is_subscribed
        FROM lonelymans_profiles pr
        WHERE pr.citizenid != ?
        ORDER BY sub_count DESC
    ]], { citizenid, citizenid })

    cb(creators or {})
end)

-- ─── Creator Profile ─────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:getCreatorProfile', function(source, cb, creatorId)
    local citizenid = GetCitizenId(source)
    if not citizenid or not creatorId then return cb({}) end

    local profile = MySQL.single.await([[
        SELECT
            pr.citizenid,
            pr.display_name,
            pr.bio,
            pr.profile_pic,
            pr.banner_pic,
            pr.subscription_price,
            (SELECT COUNT(*) FROM lonelymans_posts WHERE creator_citizenid = pr.citizenid)         AS post_count,
            (SELECT COUNT(*) FROM lonelymans_subscriptions WHERE creator_citizenid = pr.citizenid) AS sub_count,
            (SELECT id FROM lonelymans_subscriptions
             WHERE creator_citizenid = ? AND subscriber_citizenid = ? LIMIT 1) IS NOT NULL AS is_subscribed
        FROM lonelymans_profiles pr
        WHERE pr.citizenid = ?
    ]], { creatorId, citizenid, creatorId })

    if not profile then return cb({}) end

    local isSubscribed  = profile.is_subscribed == 1
    -- A subscriber can view unlock_price=0 posts.
    -- A free creator's (subscription_price=0) posts are visible to anyone.
    -- PPV posts (unlock_price > 0) ALWAYS require individual payment — subscription never unlocks them.
    local canViewFree   = isSubscribed or (profile.subscription_price or 0) == 0

    local posts = MySQL.query.await([[
        SELECT
            p.id,
            p.caption,
            p.media_type,
            p.unlock_price,
            p.created_at,
            p.media_url,
            (ul.id IS NOT NULL OR (p.unlock_price = 0 AND ? = 1)) AS is_unlocked,
            (SELECT COUNT(*) FROM lonelymans_likes    WHERE post_id = p.id)                   AS like_count,
            (SELECT COUNT(*) FROM lonelymans_likes    WHERE post_id = p.id AND citizenid = ?) AS is_liked,
            (SELECT COUNT(*) FROM lonelymans_comments WHERE post_id = p.id)                   AS comment_count
        FROM lonelymans_posts p
        LEFT JOIN lonelymans_unlocked_posts ul
            ON ul.post_id = p.id AND ul.citizenid = ?
        WHERE p.creator_citizenid = ?
        ORDER BY p.created_at DESC
    ]], { canViewFree and 1 or 0, citizenid, citizenid, creatorId })

    profile.posts = posts or {}
    cb(profile)
end)

-- ─── My Profile ──────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:getMyProfile', function(source, cb)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({}) end

    local profile = MySQL.single.await([[
        SELECT
            citizenid, display_name, bio, profile_pic, banner_pic,
            subscription_price, total_earnings,
            (SELECT COUNT(*) FROM lonelymans_subscriptions WHERE creator_citizenid = ?) AS sub_count
        FROM lonelymans_profiles
        WHERE citizenid = ?
    ]], { citizenid, citizenid })

    if not profile then return cb({ exists = false }) end

    local posts = MySQL.query.await([[
        SELECT id, caption, media_url, media_type, unlock_price, created_at
        FROM lonelymans_posts
        WHERE creator_citizenid = ?
        ORDER BY created_at DESC
    ]], { citizenid })

    profile.exists = true
    profile.posts  = posts or {}
    cb(profile)
end)

-- ─── Subscribe ───────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:subscribe', function(source, cb, creatorId)
    local citizenid = GetCitizenId(source)
    if not citizenid or not creatorId then
        return cb({ success = false, message = 'Invalid request.' })
    end

    if citizenid == creatorId then
        return cb({ success = false, message = 'You cannot subscribe to yourself.' })
    end

    local existing = MySQL.scalar.await(
        'SELECT id FROM lonelymans_subscriptions WHERE subscriber_citizenid = ? AND creator_citizenid = ?',
        { citizenid, creatorId }
    )
    if existing then
        return cb({ success = false, message = 'You are already subscribed.' })
    end

    local creator = MySQL.single.await(
        'SELECT subscription_price, display_name FROM lonelymans_profiles WHERE citizenid = ?',
        { creatorId }
    )
    if not creator then
        return cb({ success = false, message = 'Creator not found.' })
    end

    local price = creator.subscription_price or 0

    -- Check funds up front so we do not write a row we are about to delete.
    if price > 0 and GetPlayerBank(source) < price then
        return cb({ success = false, message = 'Insufficient bank funds.' })
    end

    -- Claim the subscription FIRST. The unique_sub index is what actually stops
    -- a double subscribe, so letting the insert be the thing that wins or loses
    -- the race is safer than checking and then charging: two requests that both
    -- passed the earlier `existing` check would otherwise both take money.
    local subId = MySQL.insert.await(
        'INSERT INTO lonelymans_subscriptions (subscriber_citizenid, creator_citizenid) VALUES (?, ?)',
        { citizenid, creatorId }
    )

    if not subId then
        return cb({ success = false, message = 'You are already subscribed.' })
    end

    if price > 0 then
        if not RemoveBank(source, price) then
            MySQL.update.await('DELETE FROM lonelymans_subscriptions WHERE id = ?', { subId })
            return cb({ success = false, message = 'Payment failed.' })
        end
        PayCreator(creatorId, price)
    end

    -- Notify creator
    local subAccount = MySQL.single.await('SELECT username FROM lonelymans_accounts WHERE citizenid = ?', { citizenid })
    local subName = subAccount and ('@' .. subAccount.username) or 'Someone'
    NotifyPlayer(creatorId, 'New Subscriber! 🎉', subName .. ' subscribed to your page.')

    cb({ success = true, message = 'Subscribed to ' .. creator.display_name .. '!' })
end)

-- ─── Unlock Post ─────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:unlockPost', function(source, cb, postId)
    local citizenid = GetCitizenId(source)
    if not citizenid or not postId then
        return cb({ success = false, message = 'Invalid request.' })
    end

    local already = MySQL.scalar.await(
        'SELECT id FROM lonelymans_unlocked_posts WHERE citizenid = ? AND post_id = ?',
        { citizenid, postId }
    )
    if already then
        return cb({ success = false, message = 'Already unlocked.' })
    end

    local post = MySQL.single.await(
        'SELECT id, unlock_price, creator_citizenid, media_url FROM lonelymans_posts WHERE id = ?',
        { postId }
    )
    if not post then
        return cb({ success = false, message = 'Post not found.' })
    end

    if post.unlock_price > 0 and GetPlayerBank(source) < post.unlock_price then
        return cb({ success = false, message = 'Insufficient bank funds.' })
    end

    -- Claim the unlock first; unique_unlock decides the race. Charging first
    -- meant a lost race took the money and recorded nothing.
    local unlockId = MySQL.insert.await(
        'INSERT INTO lonelymans_unlocked_posts (citizenid, post_id) VALUES (?, ?)',
        { citizenid, postId }
    )

    if not unlockId then
        -- Already unlocked: hand over the media rather than charging again.
        return cb({ success = true, mediaUrl = post.media_url })
    end

    if post.unlock_price > 0 then
        if not RemoveBank(source, post.unlock_price) then
            MySQL.update.await('DELETE FROM lonelymans_unlocked_posts WHERE id = ?', { unlockId })
            return cb({ success = false, message = 'Payment failed.' })
        end
        PayCreator(post.creator_citizenid, post.unlock_price)
    end

    cb({ success = true, mediaUrl = post.media_url })
end)

-- ─── Create Profile ──────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:createProfile', function(source, cb, data)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({ success = false, message = 'Not logged in.' }) end

    local existing = MySQL.scalar.await(
        'SELECT citizenid FROM lonelymans_profiles WHERE citizenid = ?', { citizenid }
    )
    if existing then
        return cb({ success = false, message = 'You already have a creator profile.' })
    end

    if not data.displayName or #data.displayName < 3 then
        return cb({ success = false, message = 'Display name must be at least 3 characters.' })
    end

    local price = tonumber(data.subPrice) or 0
    price = math.max(Config.MinSubPrice, math.min(Config.MaxSubPrice, price))

    -- Write the profile BEFORE taking payment, and check that the write
    -- actually happened. Doing it the other way round -- which is what this
    -- used to do -- means a failed insert leaves the player charged with
    -- nothing to show for it, and there is no rollback to undo it with.
    local profileId = MySQL.insert.await([[
        INSERT INTO lonelymans_profiles
            (citizenid, display_name, bio, profile_pic, banner_pic, subscription_price)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { citizenid, data.displayName, data.bio or '', data.profilePic or '', data.bannerPic or '', price })

    if not profileId then
        return cb({ success = false, message = 'Could not create your profile. You have not been charged.' })
    end

    if Config.ProfileCreationFee > 0 then
        -- RemoveBank returns false if the charge failed. That return was being
        -- discarded here, so a failed payment still produced a profile.
        if not RemoveBank(source, Config.ProfileCreationFee) then
            MySQL.update.await('DELETE FROM lonelymans_profiles WHERE id = ?', { profileId })
            return cb({ success = false, message = 'Payment failed. Profile not created.' })
        end
    end

    cb({ success = true, message = 'Creator profile created!' })
end)

-- ─── Update Profile ──────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:updateProfile', function(source, cb, data)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({ success = false, message = 'Not logged in.' }) end

    local price = tonumber(data.subPrice) or 0
    price = math.max(Config.MinSubPrice, math.min(Config.MaxSubPrice, price))

    MySQL.update.await([[
        UPDATE lonelymans_profiles
        SET display_name = ?, bio = ?, profile_pic = ?, banner_pic = ?, subscription_price = ?
        WHERE citizenid = ?
    ]], { data.displayName, data.bio or '', data.profilePic or '', data.bannerPic or '', price, citizenid })

    cb({ success = true, message = 'Profile updated!' })
end)

-- ─── Create Post ─────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:createPost', function(source, cb, data)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({ success = false, message = 'Not logged in.' }) end

    local profile = MySQL.scalar.await(
        'SELECT citizenid FROM lonelymans_profiles WHERE citizenid = ?', { citizenid }
    )
    if not profile then
        return cb({ success = false, message = 'You need a creator profile first.' })
    end

    if not data.mediaUrl or data.mediaUrl == '' then
        return cb({ success = false, message = 'No media provided.' })
    end

    local unlockPrice = tonumber(data.unlockPrice) or 0
    unlockPrice = math.max(0, math.min(Config.MaxPostPrice, unlockPrice))

    MySQL.insert.await([[
        INSERT INTO lonelymans_posts (creator_citizenid, caption, media_url, media_type, unlock_price)
        VALUES (?, ?, ?, ?, ?)
    ]], { citizenid, data.caption or '', data.mediaUrl, data.mediaType or 'image', unlockPrice })

    -- Notify online subscribers
    local creatorProfile = MySQL.single.await('SELECT display_name FROM lonelymans_profiles WHERE citizenid = ?', { citizenid })
    local creatorName = creatorProfile and creatorProfile.display_name or 'Someone'
    local subs = MySQL.query.await('SELECT subscriber_citizenid FROM lonelymans_subscriptions WHERE creator_citizenid = ?', { citizenid })
    for _, sub in ipairs(subs or {}) do
        NotifyPlayer(sub.subscriber_citizenid, creatorName .. ' posted! 📸', data.caption or 'New post')
    end

    cb({ success = true, message = 'Post uploaded!' })
end)

-- ─── Delete Post ─────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:deletePost', function(source, cb, postId)
    local citizenid = GetCitizenId(source)
    if not citizenid or not postId then
        return cb({ success = false, message = 'Invalid request.' })
    end

    local post = MySQL.scalar.await(
        'SELECT id FROM lonelymans_posts WHERE id = ? AND creator_citizenid = ?',
        { postId, citizenid }
    )
    if not post then
        return cb({ success = false, message = 'Post not found or not yours.' })
    end

    MySQL.update.await('DELETE FROM lonelymans_posts WHERE id = ?', { postId })
    MySQL.update.await('DELETE FROM lonelymans_unlocked_posts WHERE post_id = ?', { postId })

    cb({ success = true, message = 'Post deleted.' })
end)

-- ─── Login: Check existing account ───────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:checkAccount', function(source, cb)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb(nil) end

    local account = MySQL.single.await(
        'SELECT citizenid, username, avatar_url, linked_app FROM lonelymans_accounts WHERE citizenid = ?',
        { citizenid }
    )
    cb(account or nil)
end)

-- ─── Login: Social app import ─────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:loginWithApp', function(source, cb, appKey)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({ success = false, message = 'Not logged in.' }) end

    local appCfg = Config.SocialApps and Config.SocialApps[appKey]
    if not appCfg or not appCfg.Enabled then
        return cb({ success = false, message = 'That login method is not enabled.' })
    end

    -- Check if already has a Peekhole account
    local existing = MySQL.scalar.await(
        'SELECT citizenid FROM lonelymans_accounts WHERE citizenid = ?', { citizenid }
    )
    if existing then
        local account = MySQL.single.await(
            'SELECT citizenid, username, avatar_url, linked_app FROM lonelymans_accounts WHERE citizenid = ?',
            { citizenid }
        )
        return cb({ success = true, account = account })
    end

    -- Look up profile in the social app's table
    -- lb-phone stores accounts linked via phone_phones.owner_id (citizenid),
    -- not directly — so we JOIN through phone_number to find the player's account.
    local query = string.format([[
        SELECT a.`%s` AS username, a.`%s` AS avatar
        FROM `%s` a
        INNER JOIN `phone_phones` p ON p.phone_number = a.phone_number
        WHERE p.owner_id = ?
        LIMIT 1
    ]], appCfg.UsernameCol, appCfg.AvatarCol, appCfg.Table)

    local ok, row = pcall(function()
        return MySQL.single.await(query, { citizenid })
    end)

    if not ok then
        return cb({ success = false, message = appCfg.Label .. ' is not installed on this server.' })
    end

    if not row then
        return cb({ success = false, message = 'No ' .. appCfg.Label .. ' account found for your character.' })
    end

    local username  = row.username
    local avatarUrl = row.avatar or ''

    -- Make username unique if taken
    local taken = MySQL.scalar.await(
        'SELECT citizenid FROM lonelymans_accounts WHERE username = ?', { username }
    )
    if taken then
        username = username .. '_' .. string.sub(citizenid, -4)
    end

    MySQL.insert.await(
        'INSERT INTO lonelymans_accounts (citizenid, username, avatar_url, linked_app) VALUES (?, ?, ?, ?)',
        { citizenid, username, avatarUrl, appKey }
    )

    cb({ success = true, account = { citizenid = citizenid, username = username, avatar_url = avatarUrl, linked_app = appKey } })
end)

-- ─── Login: Create custom account ────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:createAccount', function(source, cb, data)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({ success = false, message = 'Not logged in.' }) end

    -- Check if already has an account
    local existing = MySQL.scalar.await(
        'SELECT citizenid FROM lonelymans_accounts WHERE citizenid = ?', { citizenid }
    )
    if existing then
        local account = MySQL.single.await(
            'SELECT citizenid, username, avatar_url, linked_app FROM lonelymans_accounts WHERE citizenid = ?',
            { citizenid }
        )
        return cb({ success = true, account = account })
    end

    local username = tostring(data.username or ''):match('^%s*(.-)%s*$')
    if not username or #username < 3 then
        return cb({ success = false, message = 'Username must be at least 3 characters.' })
    end
    if #username > 30 then
        return cb({ success = false, message = 'Username cannot exceed 30 characters.' })
    end
    if not username:match('^[%w_%.]+$') then
        return cb({ success = false, message = 'Username can only contain letters, numbers, _ and .' })
    end

    local taken = MySQL.scalar.await(
        'SELECT citizenid FROM lonelymans_accounts WHERE username = ?', { username }
    )
    if taken then
        return cb({ success = false, message = 'That username is already taken.' })
    end

    MySQL.insert.await(
        'INSERT INTO lonelymans_accounts (citizenid, username, avatar_url, linked_app) VALUES (?, ?, ?, ?)',
        { citizenid, username, '', 'custom' }
    )

    cb({ success = true, account = { citizenid = citizenid, username = username, avatar_url = '', linked_app = 'custom' } })
end)

-- ─── Logout ──────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:logout', function(source, cb)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({ success = false }) end

    MySQL.update.await('DELETE FROM lonelymans_accounts WHERE citizenid = ?', { citizenid })
    cb({ success = true })
end)

-- ─── Likes ───────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:toggleLike', function(source, cb, postId)
    local citizenid = GetCitizenId(source)
    if not citizenid or not postId then return cb({ success = false }) end

    local existing = MySQL.scalar.await(
        'SELECT id FROM lonelymans_likes WHERE post_id = ? AND citizenid = ?', { postId, citizenid }
    )

    if existing then
        MySQL.update.await('DELETE FROM lonelymans_likes WHERE post_id = ? AND citizenid = ?', { postId, citizenid })
        cb({ success = true, liked = false })
    else
        MySQL.insert.await('INSERT INTO lonelymans_likes (post_id, citizenid) VALUES (?, ?)', { postId, citizenid })

        -- Notify creator
        local post = MySQL.single.await('SELECT creator_citizenid FROM lonelymans_posts WHERE id = ?', { postId })
        if post and post.creator_citizenid ~= citizenid then
            local acc = MySQL.single.await('SELECT username FROM lonelymans_accounts WHERE citizenid = ?', { citizenid })
            local name = acc and ('@' .. acc.username) or 'Someone'
            NotifyPlayer(post.creator_citizenid, 'New Like ❤️', name .. ' liked your post.')
        end

        cb({ success = true, liked = true })
    end
end)

-- ─── Comments ─────────────────────────────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:getComments', function(source, cb, postId)
    if not postId then return cb({}) end
    local comments = MySQL.query.await([[
        SELECT id, citizenid, username, comment, created_at
        FROM lonelymans_comments
        WHERE post_id = ?
        ORDER BY created_at ASC
        LIMIT 100
    ]], { postId })
    cb(comments or {})
end)

QBCore.Functions.CreateCallback('peekhole:addComment', function(source, cb, data)
    local citizenid = GetCitizenId(source)
    if not citizenid or not data.postId or not data.comment then return cb({ success = false }) end

    local comment = tostring(data.comment):match('^%s*(.-)%s*$')
    if #comment < 1 or #comment > 300 then
        return cb({ success = false, message = 'Comment must be 1–300 characters.' })
    end

    local acc = MySQL.single.await('SELECT username FROM lonelymans_accounts WHERE citizenid = ?', { citizenid })
    local username = acc and acc.username or citizenid

    MySQL.insert.await(
        'INSERT INTO lonelymans_comments (post_id, citizenid, username, comment) VALUES (?, ?, ?, ?)',
        { data.postId, citizenid, username, comment }
    )

    -- Notify creator
    local post = MySQL.single.await('SELECT creator_citizenid FROM lonelymans_posts WHERE id = ?', { data.postId })
    if post and post.creator_citizenid ~= citizenid then
        NotifyPlayer(post.creator_citizenid, 'New Comment 💬', '@' .. username .. ': ' .. comment)
    end

    cb({ success = true, username = username, comment = comment })
end)

-- ─── Get creator phone number for DMs ────────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:getCreatorPhone', function(source, cb, creatorId)
    if not creatorId then return cb(nil) end
    local row = MySQL.single.await(
        'SELECT phone_number FROM phone_phones WHERE owner_id = ? LIMIT 1', { creatorId }
    )
    cb(row and row.phone_number or nil)
end)

-- ─── (Live streaming removed) ────────────────────────────────────────────────

local liveStreams       = {} -- [streamId] = { hostSource, hostCitizenid, viewers, price, instapicUsername }
local streamAccessCache = {} -- [streamId][citizenid] = true  (paid access, synchronous check)

QBCore.Functions.CreateCallback('peekhole:startStream', function(source, cb, data)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({ success = false, message = 'Not logged in.' }) end

    local profile = MySQL.single.await('SELECT display_name FROM lonelymans_profiles WHERE citizenid = ?', { citizenid })
    if not profile then return cb({ success = false, message = 'You need a creator profile first.' }) end

    local existing = MySQL.scalar.await('SELECT id FROM lonelymans_streams WHERE creator_citizenid = ? AND ended_at IS NULL', { citizenid })
    if existing then return cb({ success = false, message = 'You are already live.' }) end

    local price = math.max(0, math.min(Config.MaxPostPrice, tonumber(data.price) or 0))

    local streamId = MySQL.insert.await(
        'INSERT INTO lonelymans_streams (creator_citizenid, title, instapic_user, price) VALUES (?, ?, ?, ?)',
        { citizenid, data.title or 'Live Stream', data.instapicUser or '', price }
    )

    liveStreams[streamId] = { hostSource = source, hostCitizenid = citizenid, viewers = {}, price = price, instapicUsername = data.instapicUser or '' }

    -- Notify subscribers
    local subs = MySQL.query.await('SELECT subscriber_citizenid FROM lonelymans_subscriptions WHERE creator_citizenid = ?', { citizenid })
    for _, sub in ipairs(subs or {}) do
        NotifyPlayer(sub.subscriber_citizenid, profile.display_name .. ' is LIVE! 🔴', data.title or 'Live Stream')
    end

    cb({ success = true, streamId = streamId })
end)

QBCore.Functions.CreateCallback('peekhole:endStream', function(source, cb)
    local citizenid = GetCitizenId(source)
    if not citizenid then return cb({ success = false }) end

    local stream = MySQL.single.await('SELECT id FROM lonelymans_streams WHERE creator_citizenid = ? AND ended_at IS NULL LIMIT 1', { citizenid })
    if not stream then return cb({ success = false, message = 'No active stream.' }) end

    MySQL.update.await('UPDATE lonelymans_streams SET ended_at = NOW() WHERE id = ?', { stream.id })

    local sd = liveStreams[stream.id]
    if sd then
        for _, vs in ipairs(sd.viewers) do
            TriggerClientEvent('peekhole:streamEnded', vs, stream.id)
        end
        liveStreams[stream.id] = nil
        streamAccessCache[stream.id] = nil
    end

    cb({ success = true })
end)

QBCore.Functions.CreateCallback('peekhole:getLiveStreams', function(source, cb)
    local streams = MySQL.query.await([[
        SELECT s.id, s.creator_citizenid, s.title, s.instapic_user, s.price, s.viewer_count, s.created_at,
               p.display_name, p.profile_pic
        FROM lonelymans_streams s
        INNER JOIN lonelymans_profiles p ON p.citizenid = s.creator_citizenid
        WHERE s.ended_at IS NULL
        ORDER BY s.viewer_count DESC
    ]])
    cb(streams or {})
end)

QBCore.Functions.CreateCallback('peekhole:joinStream', function(source, cb, streamId)
    local citizenid = GetCitizenId(source)
    if not citizenid or not streamId then return cb({ success = false }) end

    local stream = MySQL.single.await('SELECT * FROM lonelymans_streams WHERE id = ? AND ended_at IS NULL', { streamId })
    if not stream then return cb({ success = false, message = 'Stream has ended.' }) end

    local isHost = stream.creator_citizenid == citizenid
    local hasAccess = isHost or MySQL.scalar.await(
        'SELECT id FROM lonelymans_stream_access WHERE stream_id = ? AND citizenid = ?', { streamId, citizenid }
    )

    if not hasAccess then
        if stream.price > 0 and GetPlayerBank(source) < stream.price then
            return cb({ success = false, message = 'Insufficient bank funds.' })
        end

        -- Same ordering as the other paid paths: record access, then charge,
        -- and undo the record if the charge fails.
        local accessId = MySQL.insert.await('INSERT INTO lonelymans_stream_access (stream_id, citizenid) VALUES (?, ?)', { streamId, citizenid })

        if stream.price > 0 and accessId then
            if not RemoveBank(source, stream.price) then
                MySQL.update.await('DELETE FROM lonelymans_stream_access WHERE id = ?', { accessId })
                return cb({ success = false, message = 'Payment failed.' })
            end
            PayCreator(stream.creator_citizenid, stream.price)
        end
        streamAccessCache[streamId] = streamAccessCache[streamId] or {}
        streamAccessCache[streamId][citizenid] = true
    end

    local sd = liveStreams[streamId]
    if sd and not isHost then
        local already = false
        for _, s in ipairs(sd.viewers) do if s == source then already = true break end end
        if not already then table.insert(sd.viewers, source) end
        local count = #sd.viewers
        MySQL.update.await('UPDATE lonelymans_streams SET viewer_count = ? WHERE id = ?', { count, streamId })
        TriggerClientEvent('peekhole:streamViewerUpdate', sd.hostSource, count)
    end

    cb({ success = true, stream = stream, isHost = isHost })
end)

QBCore.Functions.CreateCallback('peekhole:leaveStream', function(source, cb, streamId)
    local sd = liveStreams[streamId]
    if sd then
        for i, s in ipairs(sd.viewers) do
            if s == source then table.remove(sd.viewers, i) break end
        end
        local count = #sd.viewers
        MySQL.update.await('UPDATE lonelymans_streams SET viewer_count = ? WHERE id = ?', { count, streamId })
        TriggerClientEvent('peekhole:streamViewerUpdate', sd.hostSource, count)
    end
    cb(true)
end)

QBCore.Functions.CreateCallback('peekhole:sendStreamMessage', function(source, cb, data)
    local citizenid = GetCitizenId(source)
    if not citizenid or not data.streamId or not data.message then return cb(false) end

    local sd = liveStreams[data.streamId]
    if not sd then return cb(false) end

    local acc = MySQL.single.await('SELECT username FROM lonelymans_accounts WHERE citizenid = ?', { citizenid })
    local username = acc and acc.username or 'anon'
    local msg = { username = username, message = tostring(data.message):sub(1, 200) }

    TriggerClientEvent('peekhole:streamMessage', sd.hostSource, msg)
    for _, vs in ipairs(sd.viewers) do
        if vs ~= source then TriggerClientEvent('peekhole:streamMessage', vs, msg) end
    end
    cb(true)
end)

QBCore.Functions.CreateCallback('peekhole:tipStream', function(source, cb, data)
    local citizenid = GetCitizenId(source)
    if not citizenid or not data.streamId or not data.amount then return cb({ success = false }) end

    local amount = math.max(1, math.min(Config.MaxPostPrice, tonumber(data.amount) or 0))
    local stream  = MySQL.single.await('SELECT creator_citizenid FROM lonelymans_streams WHERE id = ? AND ended_at IS NULL', { data.streamId })
    if not stream then return cb({ success = false, message = 'Stream not found.' }) end

    local bank = GetPlayerBank(source)
    if bank < amount then return cb({ success = false, message = 'Insufficient bank funds.' }) end
    if not RemoveBank(source, amount) then return cb({ success = false, message = 'Payment failed.' }) end
    PayCreator(stream.creator_citizenid, amount)

    local acc = MySQL.single.await('SELECT username FROM lonelymans_accounts WHERE citizenid = ?', { citizenid })
    local username = acc and acc.username or 'anon'
    local tipMsg = { username = username, message = 'sent a $' .. amount .. ' tip! 💰', isTip = true }

    local sd = liveStreams[data.streamId]
    if sd then
        TriggerClientEvent('peekhole:streamMessage', sd.hostSource, tipMsg)
        for _, vs in ipairs(sd.viewers) do TriggerClientEvent('peekhole:streamMessage', vs, tipMsg) end
    end

    cb({ success = true })
end)

-- ─── Get enabled social apps (sent to UI) ────────────────────────────────────

QBCore.Functions.CreateCallback('peekhole:getSocialApps', function(source, cb)
    local list = {}
    for key, cfg in pairs(Config.SocialApps or {}) do
        list[#list + 1] = { key = key, label = cfg.Label, color = cfg.Color, enabled = cfg.Enabled }
    end
    cb(list)
end)

-- ─── InstaPic Live Integration ────────────────────────────────────────────────
-- When a Peekhole creator goes live on InstaPic, auto-create the stream
-- and notify all their subscribers.

exports['lb-phone']:AddCheck('startInstaPicLive', function(source, instapicUsername)
    CreateThread(function()
        local citizenid = GetCitizenId(source)
        if not citizenid then return end

        local profile = MySQL.single.await('SELECT display_name FROM lonelymans_profiles WHERE citizenid = ?', { citizenid })
        if not profile then return end -- not a Peekhole creator, ignore

        -- Check for a stream the creator already set up via Go Live in Peekhole
        local existing = MySQL.single.await(
            'SELECT id, price FROM lonelymans_streams WHERE creator_citizenid = ? AND ended_at IS NULL LIMIT 1',
            { citizenid }
        )

        if existing then
            -- Link the InstaPic username to the already-configured stream and update notify message
            MySQL.update.await('UPDATE lonelymans_streams SET instapic_user = ? WHERE id = ?', { instapicUsername, existing.id })
            local sd = liveStreams[existing.id]
            if sd then sd.instapicUsername = instapicUsername end
            -- Subscribers were already notified when they tapped Go Live — no duplicate notification
            return
        end

        -- Creator went live on InstaPic without going through Peekhole first — create a free stream
        local streamId = MySQL.insert.await(
            'INSERT INTO lonelymans_streams (creator_citizenid, title, instapic_user, price) VALUES (?, ?, ?, ?)',
            { citizenid, profile.display_name .. ' is Live!', instapicUsername, 0 }
        )

        liveStreams[streamId] = {
            hostSource       = source,
            hostCitizenid    = citizenid,
            viewers          = {},
            price            = 0,
            instapicUsername = instapicUsername,
        }

        local subs = MySQL.query.await('SELECT subscriber_citizenid FROM lonelymans_subscriptions WHERE creator_citizenid = ?', { citizenid })
        for _, sub in ipairs(subs or {}) do
            NotifyPlayer(sub.subscriber_citizenid, profile.display_name .. ' is LIVE! 🔴', 'Watch on Instapic: @' .. instapicUsername)
        end
    end)
end)

-- Gate InstaPic live joins for paid Peekhole streams.
-- Uses only in-memory cache — no DB queries, so it's fully synchronous.

exports['lb-phone']:AddCheck('joinInstaPicLive', function(source, instapicUsername, inviter)
    -- Find a matching active Peekhole stream by Instapic username
    local matchedId, matchedSd = nil, nil
    for sid, sd in pairs(liveStreams) do
        if sd.instapicUsername == instapicUsername then
            matchedId, matchedSd = sid, sd
            break
        end
    end

    if not matchedId then return end                          -- Not a Peekhole stream
    if not matchedSd.price or matchedSd.price <= 0 then return end  -- Free stream

    local citizenid = GetCitizenId(source)
    if not citizenid then return end
    if matchedSd.hostCitizenid == citizenid then return end  -- Host always allowed

    -- Check payment cache (populated when they pay via Peekhole UI)
    if streamAccessCache[matchedId] and streamAccessCache[matchedId][citizenid] then return end

    -- Block and instruct them to pay on Peekhole
    exports['lb-phone']:SendNotification(source, {
        app     = 'Peekhole',
        title   = 'Premium Stream 🔒',
        content = 'Open Peekhole and pay $' .. matchedSd.price .. ' to unlock this live stream.',
        icon    = 'nui://peekhole/ui/icon.svg',
    })

    return false -- Block the InstaPic join
end)
