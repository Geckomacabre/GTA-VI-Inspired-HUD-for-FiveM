fx_version 'cerulean'
game 'gta5'

description 'vehicle key management system'
repository 'https://github.com/Qbox-project/qbx_vehiclekeys'
version '1.0.2'

ox_lib 'locale'

shared_scripts {
    '@ox_lib/init.lua',
    '@qbx_core/modules/lib.lua',
    'shared/types.lua',
    'shared/vehicle-config.lua',
    'bridge/qb/shared.lua',
}

client_scripts {
    '@qbx_core/modules/playerdata.lua',
    'client/functions.lua',
    'client/searchkeys.lua',
    'client/main.lua',
    'client/carjack.lua',
    'client/smashwindow.lua',
    'client/slimjim.lua',
    'client/keyclone.lua',
    'bridge/qb/client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/version.lua',
    'server/keys.lua',
    'server/main.lua',
    'server/commands.lua',
    'bridge/qb/server.lua',
}

files {
    'locales/*.json',
    'config/client.lua',
    'config/shared.lua'
}

-- the slim jim's clips (vi_slimjim.ycd) and strip (vi_prop_slimjim) in stream/;
-- the strip's .ytyp has to be requested to be spawnable
data_file 'DLC_ITYP_REQUEST' 'stream/vi_prop_slimjim.ytyp'

lua54 'yes'
use_experimental_fxv2_oal 'yes'
provide 'qb-vehiclekeys'
