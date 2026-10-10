fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vi_binoculars'
description 'GTA VI style binoculars: smooth zoom, mouse and controller, the lens mask and prompts drawn by vice_hud when it is running'
version '1.0.0'

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'

-- No dependencies. With vice_hud running the lens mask, the ZOOM prompt and
-- the label are its own (exports.vice_hud:SetBinocularOverlay); without it the
-- game's stock binocular overlay is used. With ox_inventory or qbx_core
-- running, the item named in config.lua becomes usable.
