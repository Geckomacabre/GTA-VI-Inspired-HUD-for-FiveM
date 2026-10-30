-- HUD OPTIONS: single player's hold-V settings menu, drawn the same way.
-- Every number is single player's (GTA6Hud.ini [SettingsMenu] and [Colors]).
return {
    -- false: no menu (the rows still show on vi_pausemenu's Settings page)
    enabled = true,

    -- The menu opens when the camera button is held this long (V on a
    -- keyboard, the back / view button on a pad); a tap still changes the
    -- camera. Single player: [SettingsMenu] HoldSeconds.
    holdSeconds = 0.5,
    control = 0,                 -- INPUT_NEXT_CAMERA

    -- Single player blocks GTA's interaction menu (M) while it runs. On a
    -- server M is usually someone else's key, so it stays free here.
    replacesInteractionMenu = false,

    -- Layout in single player's reference units (1 unit = 1080 / 674 px on a
    -- 1080-high screen), from the bottom right corner.
    right = 26,                  -- [SettingsMenu] Right
    bottom = 44,                 -- Bottom
    rowH = 22,                   -- RowH
    cap = 13,                    -- CapHeight: a row's capital letters
    titleCap = 14,               -- TitleCapHeight: HUD OPTIONS
    badgeW = 26,                 -- BadgeWidth: the ON / OFF box
    badgeGap = 7,                -- BadgeGap: between a row's name and its box
    ruleGap = 8,                 -- RuleGap: above and below the line over the title
    ruleW = 120,                 -- RuleWidth
    visibleRows = 13,            -- more than this scroll, with a bar at the right

    -- Text: GTA's font 4 (Chalet Comprime), a cap height turned into a text
    -- scale the way single player does it ([Text] CapToLineRatio, TextTopPadRatio).
    font = 4,
    capToLine = 0.72,
    topPad = 0.16,

    -- r, g, b, a: single player's [Colors] (the ini gives r, g, b; a stays its own)
    colours = {
        text = { 242, 242, 244, 255 },          -- SettingsText: the chosen row, the title
        dim = { 154, 154, 160, 190 },           -- SettingsDim: the other rows
        textSelected = { 26, 26, 30, 255 },     -- the chosen row's value, on its light box
        badgeOn = { 232, 232, 234, 235 },       -- the chosen row's box
        badgeOff = { 58, 58, 64, 120 },         -- the other rows' boxes
        rule = { 208, 208, 212, 190 },          -- SettingsRule: the line, the scroll thumb
        track = { 255, 255, 255, 60 },          -- the scroll bar behind the thumb
    },
}
