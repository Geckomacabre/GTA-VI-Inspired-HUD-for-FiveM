fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name        'gk_basketball'
description 'Playable basketball: hoops, shot mechanics, scoring detection and timed pickup matches.'
version     '1.0.0'

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',

    -- Routing buckets and state bags are both state-awareness features. Without
    -- OneSync they fail silently rather than loudly, so say so up front.
    '/onesync',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/sfx.js',

    -- The hoop drawn after "2 scored" in vice_hud's feed (Config.Hud.scoredIcon).
    'html/img/hoop.svg',

    -- Recorded ball sounds, if there are any (html/sounds/manifest.json says
    -- which). Without them every sound is synthesised.
    'html/sounds/*.json',
    'html/sounds/*.ogg',
    'data/hoops.json',
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/util.lua',
}

client_scripts {
    'client/court.lua',      -- defines BB.notify/showHint used by the rest
    'client/hud.lua',
    'client/look.lua',       -- prompts, help box, reticle, "N scored": vice_hud's pieces when it is running
    'client/aimcam.lua',     -- the over-the-shoulder camera while aiming a 'rings' shot
    'client/moves.lua',      -- pure Lua, no natives: dribble timing, catching; tests/moves_test.lua
    'client/anim.lua',       -- the animation pack, if one is running
    'client/physics.lua',    -- pure Lua, no natives: the same file tests/run.py runs
    'client/ballsim.lua',    -- feeds the physics the game's world; defines BB.sim
    'client/scoring.lua',
    'client/ball.lua',
    'client/ai.lua',
    'client/freeballs.lua',  -- balls lying on a court to pick up and shoot
    'client/placement.lua',
}

server_scripts {
    'server/hoops.lua',      -- loads hoops before match/ball reference BB.courts
    'server/instance.lua',   -- routing buckets; match.lua moves players with these
    'server/ball.lua',
    'server/match.lua',
}
