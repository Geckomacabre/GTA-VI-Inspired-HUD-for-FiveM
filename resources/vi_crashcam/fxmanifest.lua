fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vi_crashcam'
description 'GTA VI style crash cam: a hard crash cuts to a roadside camera and plays out in slow motion'
version '1.0.0'

shared_script 'config.lua'
client_script 'client.lua'

-- vice_hud is NOT a dependency. If it is running, its HUD is hidden for the
-- length of the shot through exports.vice_hud:SetHudVisible; if it is not,
-- the native HUD and radar are hidden per frame and that is the whole job.
