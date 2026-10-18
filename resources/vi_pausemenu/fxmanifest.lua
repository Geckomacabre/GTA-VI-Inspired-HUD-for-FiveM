fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vi_pausemenu'
description "The pause menu as GTA VI's: a grid of picture tiles (map, brief, stats, Rockstar Editor, game settings, this server's settings, players, report, Discord, disconnect) over the blurred game, with GTA VI's list-and-picture settings screens. The map and the game's settings are the game's own screens, handed the stage and handed back."
version '1.0.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/fonts/*',
    'html/img/*',
}

shared_scripts {
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}
