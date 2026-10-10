-- SKRaceEvents: static race definitions.
--
-- scheme:
--   'ordered'      — hit checkpoints 1..N in order, finish at the last one (point-to-point sprint)
--   'circuit'      — same as ordered, but the last checkpoint loops back to the start; `laps` repeats it
--   'thereandback' — ordered out to the last checkpoint, then the same checkpoints run in reverse back to start
--
-- start.w is the heading the player/NPC vehicle is snapped to on the start line.
-- goalTime (seconds) is optional; beating it grants the goal-time reward bonus (see shared/config.lua).
--
-- Seeded from um_carmeet's Config.Race.routes and carmeet_routes.json (the previous NPC-challenge /
-- circuit race system this resource replaces). Old world-record holder text from the `lapraces` table
-- is not carried forward — add new routes with /racemaker.
--
-- The five routes below (del_perro_promenade through cypress_flats_circuit) are new additions spreading
-- the roster out past the original La Mesa/Elysian cluster. Every start/checkpoint was snapped to the
-- nearest real road node with _tools/gtav_reference's `road` lookup (ground Z, heading and lane count
-- come from the game's own vehicle path nodes, not guessed) — see _tools/CLAUDE.md at the server root
-- for that tool. Still worth a pass with /racemaker in-game before relying on them for lap geometry.

SKRaceEvents = {
    elysian_sprint = {
        id       = 'elysian_sprint',
        name     = 'Elysian Sprint',
        scheme   = 'ordered',
        laps     = 1,
        goalTime = 90,
        start    = vec4(775.0, -1875.0, 29.0, 270.0),
        checkpoints = {
            vec3(645.0, -1895.0, 30.0),
            vec3(610.0, -1990.0, 28.0),
            vec3(775.0, -2055.0, 7.0),
        },
    },

    la_mesa_circuit = {
        id       = 'la_mesa_circuit',
        name     = 'La Mesa Circuit',
        scheme   = 'circuit',
        laps     = 3,
        goalTime = nil,
        start    = vec4(775.0, -1875.0, 29.0, 270.0),
        checkpoints = {
            vec3(595.0, -1875.0, 32.0),
            vec3(540.0, -1930.0, 34.0),
            vec3(565.0, -2090.0, 30.0),
            vec3(685.0, -2160.0, 7.0),
            vec3(785.0, -2080.0, 7.0),
        },
    },

    popular_st_circuit = {
        id       = 'popular_st_circuit',
        name     = 'Popular St Circuit',
        scheme   = 'circuit',
        laps     = 3,
        goalTime = nil,
        -- Prestige route: gated behind barn find progress (see server/validation.lua
        -- and server/multiplayer.lua, which check the qbox_barnfinds `barn_finds`
        -- table for completed count before allowing a run/lobby on a gated route).
        unlockRequirement = { barnFindsCompleted = 2 },
        start    = vec4(816.3778, -1765.3501, 28.7604, 175.0592),
        checkpoints = {
            vec3(797.3138, -1879.5432, 28.8217),
            vec3(768.2711, -2039.1715, 28.7852),
            vec3(739.5825, -2053.5818, 28.8569),
            vec3(497.6349, -2042.6689, 25.4395),
            vec3(380.5903, -1935.8994, 24.1509),
            vec3(375.5529, -1918.3574, 24.0133),
            vec3(462.4737, -1832.5505, 27.4548),
            vec3(512.2836, -1713.2059, 28.8215),
            vec3(537.2160, -1706.9404, 28.8448),
            vec3(811.0251, -1751.9961, 28.8586),
        },
    },

    del_perro_promenade = {
        id       = 'del_perro_promenade',
        name     = 'Del Perro Promenade',
        scheme   = 'ordered',
        laps     = 1,
        goalTime = 75,
        start    = vec4(-1348.75, -597.0, 27.84, 212.7),
        checkpoints = {
            vec3(-1447.0, -429.75, 34.69),
            vec3(-1616.75, -280.0, 51.56),
            vec3(-1698.25, -138.0, 56.72),
            vec3(-1849.0, 52.0, 76.34),
        },
    },

    vinewood_hills_climb = {
        id       = 'vinewood_hills_climb',
        name     = 'Vinewood Hills Climb',
        scheme   = 'thereandback',
        laps     = 1,
        goalTime = 110,
        start    = vec4(-377.25, 72.5, 58.62, 268.3),
        checkpoints = {
            vec3(-498.25, 245.0, 82.06),
            vec3(-651.75, 497.75, 108.47),
            vec3(-790.25, 709.75, 144.78),
        },
    },

    route_68_desert_run = {
        id       = 'route_68_desert_run',
        name     = 'Route 68 Desert Run',
        scheme   = 'ordered',
        laps     = 1,
        goalTime = 150,
        start    = vec4(1682.0, 3241.5, 39.78, 102.7),
        checkpoints = {
            vec3(1466.75, 3064.75, 39.53),
            vec3(1100.75, 2973.0, 39.59),
            vec3(694.5, 2950.0, 43.94),
            vec3(343.75, 2854.75, 42.41),
        },
    },

    paleto_bay_loop = {
        id       = 'paleto_bay_loop',
        name     = 'Paleto Bay Loop',
        scheme   = 'circuit',
        laps     = 2,
        goalTime = nil,
        start    = vec4(-290.0, 6216.75, 30.5, 225.9),
        checkpoints = {
            vec3(-172.25, 6279.25, 30.47),
            vec3(78.25, 6418.5, 30.31),
            vec3(82.75, 6314.25, 30.25),
            vec3(-191.5, 6186.0, 30.19),
        },
    },

    cypress_flats_circuit = {
        id       = 'cypress_flats_circuit',
        name     = 'Cypress Flats Circuit',
        scheme   = 'circuit',
        laps     = 3,
        goalTime = nil,
        -- Prestige route, same gating pattern as popular_st_circuit above.
        -- Checked against gtav_reference's Cypress Flats zone bounds
        -- (X 505..1048, Y -2718..-1708) and snapped to real road nodes so
        -- the loop sits in the industrial zone, not the dock water south of it.
        unlockRequirement = { barnFindsCompleted = 4 },
        start    = vec4(655.25, -2495.75, 17.59, 272.0),
        checkpoints = {
            vec3(834.25, -2356.0, 29.31),
            vec3(953.5, -2489.25, 27.41),
            vec3(825.5, -2628.25, 51.5),
            vec3(657.5, -2643.75, 47.31),
        },
    },
}

