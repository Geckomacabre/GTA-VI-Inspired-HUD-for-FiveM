Config = {}

-- The pause menu as GTA VI's: ESC (or P, or a pad's Start) opens a grid of picture tiles over the blurred game - the
-- map, a brief of the character, stats, the Rockstar Editor, the game's own settings, this server's settings, the
-- players, a report to staff, Discord and disconnecting - with the day and time, the cash and the bank under it.

-- The title over the grid; empty: the server's name (server.cfg's sv_projectName, else sv_hostname)
Config.Title = ''
-- The line over the character's name at the top right
Config.Mode = 'ONLINE'

-- A Discord invite for its tile (https://discord.gg/...); empty: no Discord tile
Config.Discord = ''

-- Reports (the Report tile) go to this Discord webhook; empty: printed on the server console instead
Config.Report = {
    Webhook = '',
    WebhookName = 'Pause menu report',
    Categories = { 'Player', 'Bug', 'Question', 'Other' },
}

-- Players may switch back to the game's own pause menu (Settings > Pause Menu: Classic); this is the KVP that remembers
Config.StyleKvp = 'vi_pausemenu:style'

-- Controls kept off while the menu is up (ESC, P, Enter reaching the game)
Config.DisableWhileOpen = { 200, 199, 202 }

-- The Stats screen: vice_hud's skills (its skills.lua), each 0..100, with what raises it
Config.Skills = {
    { id = 'stamina', label = 'Stamina', how = 'Raised by sprinting.', image = 'beach' },
    { id = 'strength', label = 'Strength', how = 'Raised by landing melee hits.', image = 'players' },
    { id = 'health', label = 'Health', how = 'Raised by jogging.', image = 'beach' },
    { id = 'lung', label = 'Lung Capacity', how = 'Raised by time spent underwater.', image = 'boat' },
    { id = 'shooting', label = 'Shooting', how = 'Raised by shots on target.', image = 'keybinds' },
    { id = 'focus', label = 'Focus', how = 'Raised by baskets made.', image = 'players' },
    { id = 'stealth', label = 'Stealth', how = 'Raised by moving crouched.', image = 'report' },
    { id = 'driving', label = 'Driving', how = 'Raised by driving without a crash.', image = 'mapvehicle' },
    { id = 'flying', label = 'Flying', how = 'Raised by time in the air.', image = 'map' },
    { id = 'wheelie', label = 'Wheelie', how = 'Raised by riding on one wheel.', image = 'editor' },
}

-- What each tile shows. image: html/img/<image>.webp; `sub`: the line at its right ("$location", "$players",
-- "$job" and "$recording" are filled in as the menu opens). A tile whose `needs` resource is not running is left out.
Config.Tiles = {
    { -- the top row, two big tiles
        { id = 'map', label = 'Map', image = 'map', sub = '$location' },
        { id = 'brief', label = 'Brief', image = 'brief', sub = '$job' },
    },
    {
        { id = 'stats', label = 'Stats', image = 'stats', needs = 'vice_hud' },
        { id = 'editor', label = 'Rockstar Editor', image = 'editor', sub = '$recording' },
        { id = 'game', label = 'Game', image = 'game', sub = 'Display / Audio / Controls' },
        { id = 'settings', label = 'Settings', image = 'settings' },
    },
    {
        { id = 'players', label = 'Players', image = 'players', sub = '$players' },
        { id = 'report', label = 'Report', image = 'report', sub = 'To staff' },
        { id = 'discord', label = 'Discord', image = 'discord', sub = 'Join us' },
        { id = 'disconnect', label = 'Disconnect', image = 'disconnect', sub = 'Leave the server' },
    },
}
