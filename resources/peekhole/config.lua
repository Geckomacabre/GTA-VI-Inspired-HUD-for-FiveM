Config = {}

-- 'qbcore' or 'esx'
Config.Framework = 'qbcore'

Config.AppIdentifier  = 'peekhole'
Config.AppName        = 'Peekhole'
Config.AppDescription = 'Subscribe to creators & unlock exclusive content'

-- Pricing limits (in-game currency)
Config.ProfileCreationFee = 0        -- fee to become a creator (0 = free)
Config.MinSubPrice        = 0        -- minimum subscription price (0 allows free pages)
Config.MaxSubPrice        = 50000    -- maximum subscription price
Config.MaxPostPrice       = 10000    -- maximum per-post unlock price

-- Creator receives this cut of every payment (remainder is a silent platform fee)
Config.CreatorCut = 0.80

-- ─── Social Login Integration ─────────────────────────────────────────────────
-- Set Enabled = true once the app is installed on your server.
-- Adjust Table/UsernameCol/AvatarCol to match that app's actual DB schema.

-- lb-phone vanilla social apps.
-- Accounts are linked to players via phone_phones.owner_id (citizenid),
-- joined through the phone_number column on each app's account table.
Config.SocialApps = {
    trendy = {
        Enabled     = true,
        Label       = 'Trendy',
        Color       = '#010101',   -- TikTok black
        Table       = 'phone_tiktok_accounts',
        UsernameCol = 'username',
        AvatarCol   = 'avatar',
    },
    instapic = {
        Enabled     = true,
        Label       = 'InstaPic',
        Color       = '#E1306C',   -- Instagram pink
        Table       = 'phone_instagram_accounts',
        UsernameCol = 'username',
        AvatarCol   = 'profile_image',
    },
    birdy = {
        Enabled     = true,
        Label       = 'Birdy',
        Color       = '#1DA1F2',   -- Twitter blue
        Table       = 'phone_twitter_accounts',
        UsernameCol = 'username',
        AvatarCol   = 'profile_image',
    },
}
