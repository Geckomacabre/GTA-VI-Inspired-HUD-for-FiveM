fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

author 'gecko'
description 'Car meet + racing super-resource: randol_carmeet, sk_racing, meet_night and ported StreetKings modules'
version '1.0.0'

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
}

-- modules/carbuild/ calls exports.ox_inventory:* and exports.qbx_vehicles:* at
-- runtime. Deliberately NOT listed above: adding them as hard `dependencies`
-- made FXServer's connect-time dependency check fail with "Couldn't start
-- resource sk_streetkings" for every connecting client, even though the
-- resource started cleanly server-side and both were already running
-- (server.cfg ensures [ox] and [qbx] well before [Scripts]). That ordering
-- already guarantees both are up before this resource starts, so the exports
-- work fine without the manifest declaration — leave them out.

-- Load order matters throughout: shared config and the compat layer must exist
-- before any module that reads Config, SKHud, SKPlayer or SKSaves.
shared_scripts {
    '@ox_lib/init.lua',

    'shared/config.lua',
    'shared/format_sh.lua',
    'shared/game_state_sh.lua',
    'shared/route_sh.lua',
    -- Race gate rules from Rockstar's stunt-plane/offroad scripts. Client judges, server re-checks.
    'shared/gates_sh.lua',

    -- Location/definition data. Plain tables, no logic.
    'data/races.lua',
    -- Generated from Rockstar's own race scripts by _tools/race_sim/gen_data.py; adds itself to SKRaceEvents.
    'data/rockstar_races.lua',
    'data/repair_stations.lua',
    'data/hangout_zones.lua',
    'data/stunt_jumps.lua',
    'data/rampages.lua',
    'data/speed_cameras.lua',
    'data/police_traps.lua',
}

client_scripts {
    -- Compat layer. Everything below depends on these.
    'modules/core/helpers_c.lua',
    'modules/core/input_c.lua',
    'modules/core/hud_c.lua',
    'modules/core/notify_c.lua',
    'modules/core/waypoints_c.lua',
    'modules/core/game_state_c.lua',

    -- Freecam. Loads early because racing/route_maker_c below flies it, ahead
    -- of the stunt devtool that also uses it.
    'modules/devtools/freecam_c.lua',

    -- Racing. checkpoints_c defines helpers the SP/MP flows use, and
    -- leaderboard_c defines OpenRacingHub, which carmeet_c links to.
    'modules/racing/checkpoints_c.lua',
    -- Hands out the vehicle an air/offroad race is built around. Discovery and the SP flow use it.
    'modules/racing/racevehicle_c.lua',
    'modules/racing/race_singleplayer_c.lua',
    'modules/racing/race_multiplayer_c.lua',
    'modules/racing/leaderboard_c.lua',
    'modules/racing/discovery_c.lua',
    'modules/racing/route_maker_c.lua',

    -- Reuses JoinPopupLobby/IsInMultiplayerLobby from race_multiplayer_c above.
    'modules/popuprace/popuprace_c.lua',

    -- Stats defines OpenStatsMenu, also linked from the Race Organizer.
    'modules/stats/stats_c.lua',

    -- Car meet. carmeet_c defines SKCarMeet.isInside(), used by drift_c.
    'modules/carmeet/carmeet_c.lua',
    'modules/carmeet/betting_c.lua',
    'modules/carmeet/drift_c.lua',

    -- Driving feel.
    'modules/nitrous/nitrous_c.lua',
    'modules/gearbox/gearbox_c.lua',

    -- Adds the Nitrous row to um_customs' Performance menu. See the module
    -- header for the hook um_customs carries.
    'modules/tuning/tuning_c.lua',

    -- World activities.
    'modules/repair/repair_c.lua',
    -- Reuses SKRepairStations, loaded above (shared/config.lua is shared, but
    -- data/repair_stations.lua is one of the shared_scripts at the top of
    -- this manifest, so it's already a global by the time this loads).
    'modules/carbuild/carbuild_c.lua',
    'modules/hangoutzones/hangoutzones_c.lua',
    'modules/stunts/stunts_c.lua',
    'modules/rampage/rampage_c.lua',

    -- Reuses SKRaceCountdown from racing/checkpoints_c, loaded above.
    'modules/npcchallenge/npcchallenge_c.lua',

    -- Reuses SKNpcRace, exposed at the bottom of npcchallenge_c above.
    'modules/npcinvite/npcinvite_c.lua',

    -- Reuses SKNpcInvite, exposed at the bottom of npcinvite_c above.
    'modules/phoneapp/phoneapp_c.lua',

    -- Admin tooling. stunt_devtool_c calls the SetupTestJump/TeardownTestJump
    -- exports that stunts_c registers, so it loads after it. freecam_c itself
    -- loads earlier, above, because route_maker_c needs it too.
    'modules/devtools/stunt_devtool_c.lua',

    -- Traffic enforcement. Both read the `Cinematic` flag declared in
    -- helpers_c, and police_c is off unless Config.Modules.police is turned on.
    'modules/speedcameras/speedcameras_c.lua',
    'modules/police/police_c.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',

    -- Compat layer. saves_s reads citizenids through SKPlayer, so player_s
    -- loads first; stats_s builds its key list from SKSaves.defaultStats().
    'modules/core/player_s.lua',
    'modules/core/saves_s.lua',
    'modules/stats/stats_s.lua',

    -- Meet Night must load before racing: singleplayer_s calls
    -- SKMeetNight.getMultiplier() when computing payouts.
    'modules/meetnight/meetnight_s.lua',

    -- Racing. routes_s owns SKRoutes, validation_s owns SKValidation, and
    -- singleplayer_s owns SKRewardMath/SKProfiles that multiplayer_s reuses.
    'modules/racing/routes_s.lua',
    'modules/racing/validation_s.lua',
    'modules/racing/leaderboard_s.lua',
    'modules/racing/singleplayer_s.lua',
    'modules/racing/multiplayer_s.lua',
    'modules/racing/admin_s.lua',
    -- Server side of the race vehicle hand-out. Needs SKRoutes (routes_s above).
    'modules/racing/racevehicle_s.lua',

    -- Reuses SKMultiplayer.createPopupLobby from multiplayer_s above and
    -- SKRoutes from routes_s.
    'modules/popuprace/popuprace_s.lua',

    'modules/carmeet/carmeet_s.lua',
    'modules/gearbox/gearbox_s.lua',
    'modules/repair/repair_s.lua',
    -- Uses SKPlayer/SKStats (core/stats_s above) and qbx_vehicles/ox_inventory
    -- exports; independent of repair_s itself despite sharing repair stations.
    'modules/carbuild/carbuild_s.lua',
    'modules/tuning/tuning_s.lua',

    -- Both charge money and bump stats, so they load after stats_s.
    'modules/speedcameras/speedcameras_s.lua',
    'modules/police/police_s.lua',

    -- Scored world activities. Both award XP through SKProfiles, which
    -- racing/singleplayer_s owns, so they load after it.
    'modules/stunts/stunts_s.lua',
    'modules/rampage/rampage_s.lua',
    'modules/npcchallenge/npcchallenge_s.lua',
    'modules/devtools/stunt_devtool_s.lua',
}

-- data/carmeet.lua is pulled in with lib.require rather than being loaded as a
-- script, because it returns a table instead of setting a global. ox_lib reads
-- it off disk, so it has to be listed here.
files {
    'data/carmeet.lua',
    'data/alt_configs/*.lua',
    'sql/install.sql',

    'modules/phoneapp/ui/index.html',
    'modules/phoneapp/ui/style.css',
    'modules/phoneapp/ui/app.js',
    'modules/phoneapp/ui/icon.svg',
}
