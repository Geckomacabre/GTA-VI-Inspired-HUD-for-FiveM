-- Game state machine (ported from streetkings modules/core/game_state_sh.lua).
--
-- StreetKings is a standalone gamemode, so its states covered the whole player
-- lifecycle (main menu -> avatar -> initiation -> freeroam). On Qbox the player
-- lifecycle belongs to qbx_core, so only the states that actually gate gameplay
-- behaviour in the ported modules are kept. The names are unchanged so ported
-- module code that reads `GameState.FREEROAM` etc. works without edits.

GameState = {
    -- Default. Player is loaded and driving around the city normally.
    FREEROAM          = 'freeroam',

    -- Solo timed run (modules/racing/race_singleplayer_c.lua).
    EVENT             = 'event',

    -- Sitting in a multiplayer race lobby, pre-countdown.
    MULTIPLAYER_LOBBY = 'multiplayer_lobby',

    -- Multiplayer race underway.
    MULTIPLAYER_EVENT = 'multiplayer_event',

    -- Inside the car meet interior (modules/carmeet). Drift scoring and passive
    -- mode are active here; nitrous/gearbox are not.
    CARMEET           = 'carmeet',

    -- Browsing a menu that should suppress driving-feel modules.
    MENU              = 'menu',
}

-- States in which the driving-feel modules (nitrous, gearbox) are allowed to
-- engage. Ported modules reference this directly instead of each defining its
-- own ALLOWED_STATES table.
SKDrivingStates = {
    [GameState.FREEROAM]          = true,
    [GameState.EVENT]             = true,
    [GameState.MULTIPLAYER_LOBBY] = true,
    [GameState.MULTIPLAYER_EVENT] = true,
}

-- States that count as "in a race", used by police/speed cameras/npc challenge
-- to stand down so they don't interfere with a scored run.
SKRacingStates = {
    [GameState.EVENT]             = true,
    [GameState.MULTIPLAYER_EVENT] = true,
}
