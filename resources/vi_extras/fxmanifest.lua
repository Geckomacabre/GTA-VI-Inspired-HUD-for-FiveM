fx_version 'cerulean'
game 'gta5'
lua54 'yes'
use_experimental_fxv2_oal 'yes'

name 'vi_extras'
description "Single player's GTA VI-Inspired HUD features for FiveM: HUD OPTIONS (hold V) and the switches it lists"
version '1.0.0'

-- Built like qbx_smallresources: each folder is one feature, with its own
-- client.lua (and server.lua, config.lua) loaded by the globs below. To take a
-- feature into another resource, copy its folder and vi_hudoptions (the rows
-- every feature adds its switch to). A feature's config.lua says whether it
-- runs at all; HUD OPTIONS is where each player switches it on or off.

shared_script '@ox_lib/init.lua'

client_script '**/client.lua'

server_script '**/server.lua'

-- vi_chasemusic plays the server's tracks (dropped into vi_chasemusic/music/)
-- in this page; no other feature has one.
ui_page 'vi_chasemusic/html/index.html'

files {
    '**/config.lua',
    'vi_hudoptions/options.lua',
    'vi_hudoptions/bridges.lua',
    'vi_chasemusic/html/index.html',
    'vi_chasemusic/html/app.js',
    'vi_chasemusic/music/*.mp3',
    'vi_chasemusic/music/*.wav',
    'vi_chasemusic/music/*.ogg',
    'vi_chasemusic/music/*.m4a',
}

dependency 'ox_lib'
