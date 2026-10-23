fx_version 'cerulean'
game 'gta5'

name 'Peekhole'
description 'OnlyFans-style content subscription platform for LB Phone'
author 'Custom'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/colors.css',
    'ui/icons.css',
    'ui/script.js',
    'ui/icon.svg',
    'ui/screenshots/screen_feed.svg',
    'ui/screenshots/screen_discover.svg',
    'ui/screenshots/screen_studio.svg'
}

dependency 'lb-phone'
dependency 'oxmysql'
