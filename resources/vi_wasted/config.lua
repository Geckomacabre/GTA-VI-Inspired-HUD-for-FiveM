Config = {}

-- The word, the wash over the picture, and how long the screen holds. These
-- are fenix-police's own values. Durations are REAL milliseconds: the screens
-- run in slow motion, which stretches the game's own timer.
Config.Wasted = {
    word     = 'wasted',
    colour   = { 220, 40, 40 },
    duration = 4000,

    -- Play it whenever qbx_medical reports the player dead. Off, it only
    -- plays when exports.vi_wasted:PlayWasted() is called.
    auto = true,
}

Config.Busted = {
    word      = 'busted',
    colour    = { 70, 140, 230 },
    duration  = 6000,
    skippable = true,       -- SPACE or ENTER ends it early
}

-- The red laid over the whole picture while either screen is up (r, g, b, a).
Config.Wash = { 160, 20, 20, 70 }

Config.TimeScale = 0.15

-- fenix-police plays both screens itself. With it running this resource does
-- nothing on its own, so a death is not announced twice; the exports still
-- work if something calls them.
Config.StandDownFor = 'fenix-police'

-- /wasted and /busted play the screens for testing. false registers neither.
Config.TestCommands = true
