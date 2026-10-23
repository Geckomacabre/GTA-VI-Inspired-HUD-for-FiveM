# Peekhole — LB Phone Custom App

An OnlyFans-style content platform built as a downloadable LB Phone app, named
after GTA VI's own. Players use their in-game **bank account** to subscribe to
creators, unlock posts and watch live streams.

> **Coming from LonelyMans?** This is the same app, renamed. Stop `lonelymans`
> and `ensure peekhole` instead. The database tables keep their `lonelymans_*`
> names, so every creator, post and subscription carries over. The app's id
> changed, so players download **Peekhole** from the App Store once.

---

## Installation

1. Place the `peekhole` folder inside your `resources/[Scripts]/` directory.
2. Add `ensure peekhole` to your `server.cfg` **after** `ensure lb-phone` and `ensure oxmysql`.
3. Start/restart your server. The resource auto-creates all of its database tables on first boot — no SQL import needed.
4. You should see `[Peekhole] Database tables ready.` in the server console.

---

## How to Get the App In-Game

The app is **not auto-installed** on every player's phone. It lives in the LB Phone App Store and must be downloaded once per character.

1. Open your phone in-game (`F1` or your phone key).
2. Go to the **App Store** (the store icon).
3. Search for **Peekhole** or scroll until you find it.
4. Tap **Get** (it's free to download).
5. The app icon will appear on your phone's home screen.

---

## App Structure

The app has three tabs:

| Tab | Icon | Purpose |
|-----|------|---------|
| **Home** | 🏠 | Feed of posts from creators you subscribe to |
| **Discover** | 🔍 | Browse all creators, see their sub price, subscribe |
| **My Page** | 👤 | Your creator studio — manage your profile and posts |

---

## Testing Guide

Work through each section below in order. Each section tells you what to do, what to look for, and what a passing result looks like.

---

### 1. App Store Download

**What to do:**
- Open the phone → App Store → find Peekhole → tap Get.

**Pass:** The app appears on your home screen with the Peekhole icon.
**Fail:** App doesn't appear in the store → check `ensure peekhole` is in server.cfg and the resource started cleanly (`[Peekhole] Database tables ready.` in console).

---

### 2. App Opens Correctly (No Black Screen / No Full-Screen Takeover)

**What to do:**
- Tap the Peekhole icon on your phone home screen.

**Pass:** The app opens *inside the phone screen* showing the three-tab navigation bar and a feed that says "Nothing here yet."
**Fail — Black screen:** Run `restart peekhole` in server console and reopen.
**Fail — Full screen takeover:** `#phone-wrapper { display: none; }` is missing from style.css — check the file.

---

### 3. Creating a Creator Profile

**What to do:**
1. Open the app → tap **My Page** tab.
2. You should see a "Become a Creator" screen.
3. Tap **Create My Page**.
4. Fill in:
   - **Display Name** — at least 3 characters (e.g. `TestCreator`)
   - **Bio** — optional (e.g. `Welcome to my page`)
   - **Subscription Price** — set `0` for free, or e.g. `500` for $500/mo
   - **Profile Picture** — tap the picker, choose a photo from lb-phone's gallery
   - **Banner** — tap the picker, choose a banner image
5. Tap **Save**.

**Pass:** Toast says "Creator profile created!" and My Page now shows your stats (0 posts, 0 fans, $0 earned).
**Fail:** "Display name must be at least 3 characters" — make sure the name is long enough.
**Fail:** "Insufficient bank funds" — only appears if `Config.ProfileCreationFee` is set above 0 in config.lua. Default is 0, so this shouldn't trigger.

---

### 4. Creating Posts

*Requires a creator profile (Step 3 done first).*

**What to do:**
1. My Page tab → tap **New Post**.
2. Tap the media picker → choose a photo or video from the gallery.
3. Write a caption (optional).
4. Set **Extra Unlock Price**:
   - `0` = visible to all subscribers for free
   - e.g. `250` = subscribers must pay an extra $250 to see this specific post
5. Tap **Post**.

**Pass:** Toast says "Post uploaded!" and the post thumbnail appears in your My Page grid.
**Fail:** "No media provided" — you must pick a photo/video before posting.
**Fail:** "You need a creator profile first" — complete Step 3 first.

**Test both post types:**
- Create one post with unlock price `0` (free for subscribers).
- Create one post with unlock price `250` (paid unlock).

---

### 5. Deleting a Post

**What to do:**
- My Page tab → tap any post thumbnail in your grid.
- A confirmation popup appears: "Delete this post? This cannot be undone."
- Tap **Delete**.

**Pass:** Post disappears from the grid, toast says "Post deleted."
**Fail:** Nothing happens → the lb-phone popup component may not be available; check server console for Lua errors.

---

### 6. Editing Your Profile

**What to do:**
- My Page tab → tap the **Edit** button next to your name.
- Change your bio or subscription price.
- Tap **Save**.

**Pass:** Toast says "Profile updated!" and the changes reflect immediately.

---

### 7. Discovering Creators (from a second character / second player)

*You need a second in-game character or a second player to test this properly.*

**What to do:**
1. On the second character/player, open Peekhole → **Discover** tab.
2. You should see the creator card for the account that completed Steps 3–4.
3. The card shows: display name, post count, fan count, subscription price.

**Pass:** Creator card appears with correct info.
**Fail:** Discover tab is empty → make sure the creator's profile was saved (check `lonelymans_profiles` table in your DB).

---

### 8. Subscribing to a Creator

**What to do (on the second character):**
1. Discover tab → tap the creator's card.
2. The creator's profile page opens: banner, avatar, bio, stats.
3. Tap **Subscribe** (or **Subscribe · $X/mo** if they have a price set).
4. A confirmation popup appears. Tap **Subscribe**.

**Pass (free sub):** Toast says "Subscribed to [name]!" and the button changes to "✓ Already Subscribed."
**Pass (paid sub):** Same as above, but bank money is deducted. Check `/bank` or the player's bank balance.
**Fail:** "Insufficient bank funds" → add money to the test character's bank first.
**Fail:** "You cannot subscribe to yourself" → use a different character.

---

### 9. Feed After Subscribing

**What to do:**
1. Still on the second character → tap the **Home** tab.
2. Posts from the creator you just subscribed to should appear.

**Pass:** Post cards show up with the creator's name/avatar.
- Free posts (`unlock_price = 0`) show the image/video directly.
- Paid posts show a 🔒 locked placeholder with an **Unlock** button.

---

### 10. Unlocking a Paid Post

*Requires a post with an unlock price > 0 (created in Step 4).*

**What to do:**
1. Home or creator profile page → find a locked post with the Unlock button.
2. Tap **Unlock · $250** (or whatever price you set).
3. Confirmation popup → tap **Pay & Unlock**.

**Pass:** The locked placeholder is replaced by the actual image/video. Toast says "Post unlocked!" The subscriber's bank is debited. The creator's bank receives 80% of the unlock price (configurable via `Config.CreatorCut` in config.lua).
**Fail:** "Insufficient bank funds" → add money to the subscriber's bank.
**Fail:** "Already unlocked" → you already unlocked it in this session.

---

### 11. Creator Earnings

**What to do:**
1. After a paid subscription or post unlock, switch back to the creator character.
2. Open Peekhole → **My Page** tab.
3. Check the **Earned** stat in the stats row.

**Pass:** The "Earned" figure reflects 80% of all payments received (the creator's cut).
**Note:** If the creator was offline when the payment happened, their bank is updated directly in the database. They'll see the money when they next log in.

---

## Configuration (config.lua)

| Setting | Default | Description |
|---------|---------|-------------|
| `Config.ProfileCreationFee` | `0` | Bank cost to create a creator profile. Set to e.g. `1000` to charge creators. |
| `Config.MinSubPrice` | `0` | Minimum subscription price a creator can set. |
| `Config.MaxSubPrice` | `50000` | Maximum subscription price a creator can set. |
| `Config.MaxPostPrice` | `10000` | Maximum extra unlock price per post. |
| `Config.CreatorCut` | `0.80` | Percentage of each payment the creator receives (80% default). The other 20% is simply removed from the economy. |

---

## Database Tables

All tables are created automatically on first resource start.

| Table | What it stores |
|-------|---------------|
| `lonelymans_profiles` | Creator profiles (display name, bio, pics, sub price, earnings) |
| `lonelymans_posts` | All posts (media URL, caption, unlock price, creator) |
| `lonelymans_subscriptions` | Who is subscribed to who |
| `lonelymans_unlocked_posts` | Which players have individually unlocked which paid posts |
| `lonelymans_accounts` | Peekhole logins linked to a player |
| `lonelymans_likes` / `lonelymans_comments` | Likes and comments on posts |
| `lonelymans_streams` / `lonelymans_stream_access` | Live streams and who has paid to watch them |

The tables keep the `lonelymans_` prefix from before the app was renamed, so an
existing server keeps its data.

---

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Black screen on open | `componentsLoaded` event missed | Run `restart peekhole`, reopen app |
| App takes over full screen | `#phone-wrapper` not hidden | Verify `#phone-wrapper { display: none; }` is in style.css |
| App not in App Store | Resource not started | Check `ensure peekhole` in server.cfg, check console for errors |
| "Table doesn't exist" errors | DB tables not created | Check server console for `[Peekhole] Database tables ready.` — if missing, check oxmysql is running |
| Popup / Gallery not working | lb-phone components not available | Make sure you downloaded the app from the App Store first (not just opened the URL directly) |
| Creator not visible in Discover | Profile not saved | Check `lonelymans_profiles` table — run `SELECT * FROM lonelymans_profiles;` in your DB client |
| Money not deducted | QBCore player object not found | Check that the player is fully loaded (`PlayerData.citizenid` exists) before using the app |
