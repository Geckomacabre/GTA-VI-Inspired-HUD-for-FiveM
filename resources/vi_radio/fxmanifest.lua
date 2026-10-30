fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vi_radio'
author 'sej0bec (original GTA V mod) / FiveM port'
description 'GTA VI inspired radio HUD, mute system, slow-motion radio wheel and On Demand playback'
version '1.2.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/fonts/Anton.ttf',
    'html/fonts/Anton-OFL.txt',
    'html/logos/*.png',
    'html/icons/*.png',
    'html/sfx/*.wav',
    -- On Demand stations' own tracks (Config.OnDemand.stations), if the
    -- server ships any. Every player downloads these when they join.
    'html/music/**/*.mp3',
    'html/music/**/*.ogg',
    'html/music/**/*.wav',
    'html/music/**/*.m4a',
    'html/music/**/*.aac',
    'html/music/**/*.flac',
}

-- On Demand plays its audio through xsound. It is not declared as a hard
-- dependency on purpose: without xsound the resource still runs, On Demand just
-- switches itself off (see Config.OnDemand.enabled).
