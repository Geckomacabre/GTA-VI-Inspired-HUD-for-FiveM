Config = Config or {}

-- ====================================================================
--                      ILLENIUM APPEARANCE THEME CONFIG
-- ====================================================================
-- Select active theme preset:
-- "default"       -> Clean White & Dark (Original High Contrast)
-- "cyan-neon"     -> Cyberpunk Cyan Neon & Dark Blue
-- "red-dark"      -> Crimson Red & Charcoal
-- "gold-luxury"   -> Gold & Metallic Black
-- "emerald-green" -> Emerald Green & Deep Teal
-- "purple-night"  -> Royal Purple & Midnight Black
-- "custom"        -> Uses the custom table below
-- ====================================================================

Config.Theme = {
    currentTheme = "custom",

    -- Custom theme settings (active when currentTheme = "custom")
    -- Ported from this server's old "um" theme (pre-redesign shared/theme.lua),
    -- which matched the customised ox_lib 3.32.3 build's Mantine theme so the
    -- clothing menu read as the same UI family as every ox_lib dialog:
    --   accent  oxred.5   #ff3b3b   selected oxred.6 #e62727
    --   surface dark.5    #1d1618   text     dark.0  #ede4e4
    -- That old schema (borderRadius/primaryBackground/etc.) doesn't map 1:1
    -- onto this redesign's header/card/text token schema, so headerBg and
    -- subTextColor below are approximations, not exact carryovers -- adjust
    -- to taste.
    custom = {
        fontTitle = "Roboto",                    -- Title Font ("Bebas Neue", "Oswald", "Inter", "Poppins", "Roboto")
        fontBody = "Roboto",                     -- Body Font ("Oswald", "Inter", "Roboto", "Montserrat", "Poppins")
        headerBg = "#ff3b3b",                    -- Header Bar Background Color (oxred.5)
        headerText = "#ffffff",                  -- Header Bar Text Color
        accentColor = "#ff3b3b",                 -- Primary Accent / Active Ring / Selected Track Color (oxred.5)
        accentText = "#ffffff",                  -- Text Color on Accent Elements
        cardBg = "#1d1618",                      -- Card & Slider Background (dark.5 surface)
        cardBorder = "rgba(255, 59, 59, 0.2)",   -- Card Border Color
        mainTextColor = "#ede4e4",               -- Main Text Color (dark.0)
        subTextColor = "#c9a8a8",                -- Secondary / Muted Text Color
    },

    -- Theme Presets List
    themes = {
        {
            id = "default",
            name = "Default Clean White",
            fontTitle = "Bebas Neue",
            fontBody = "Oswald",
            headerBg = "#ffffff",
            headerText = "#000000",
            accentColor = "#ffffff",
            accentText = "#000000",
            cardBg = "#16181f",
            cardBorder = "rgba(255, 255, 255, 0.08)",
            mainTextColor = "#ffffff",
            subTextColor = "#a1a1aa"
        },
        {
            id = "cyan-neon",
            name = "Cyan Cyberpunk",
            fontTitle = "Bebas Neue",
            fontBody = "Oswald",
            headerBg = "#00c8ff",
            headerText = "#000000",
            accentColor = "#00c8ff",
            accentText = "#000000",
            cardBg = "#0e131b",
            cardBorder = "rgba(0, 200, 255, 0.2)",
            mainTextColor = "#ffffff",
            subTextColor = "#7dd3fc"
        },
        {
            id = "red-dark",
            name = "Crimson QBCore",
            fontTitle = "Bebas Neue",
            fontBody = "Oswald",
            headerBg = "#dc2626",
            headerText = "#ffffff",
            accentColor = "#dc2626",
            accentText = "#ffffff",
            cardBg = "#181214",
            cardBorder = "rgba(220, 38, 38, 0.2)",
            mainTextColor = "#ffffff",
            subTextColor = "#fca5a5"
        },
        {
            id = "gold-luxury",
            name = "Gold Luxury",
            fontTitle = "Bebas Neue",
            fontBody = "Oswald",
            headerBg = "#eab308",
            headerText = "#000000",
            accentColor = "#eab308",
            accentText = "#000000",
            cardBg = "#17150e",
            cardBorder = "rgba(234, 179, 8, 0.2)",
            mainTextColor = "#ffffff",
            subTextColor = "#fde047"
        },
        {
            id = "emerald-green",
            name = "Emerald Green",
            fontTitle = "Bebas Neue",
            fontBody = "Oswald",
            headerBg = "#10b981",
            headerText = "#000000",
            accentColor = "#10b981",
            accentText = "#000000",
            cardBg = "#0c1814",
            cardBorder = "rgba(16, 185, 129, 0.2)",
            mainTextColor = "#ffffff",
            subTextColor = "#6ee7b7"
        },
        {
            id = "purple-night",
            name = "Purple Night",
            fontTitle = "Bebas Neue",
            fontBody = "Oswald",
            headerBg = "#a855f7",
            headerText = "#ffffff",
            accentColor = "#a855f7",
            accentText = "#ffffff",
            cardBg = "#150e1b",
            cardBorder = "rgba(168, 85, 247, 0.2)",
            mainTextColor = "#ffffff",
            subTextColor = "#d8b4fe"
        }
    }
}
