-- Persists the player's chosen gearbox mode on their character profile and
-- restores it on spawn. StreetKings stored this per vehicle as a shop upgrade;
-- here it is a per-character preference, so it survives vehicle changes.

if not Config.Modules.gearbox then return end

local VALID_MODES = { off = true, beginner = true, expert = true }

RegisterNetEvent('sk_streetkings:gearbox:setMode', function(mode)
    local src = source
    if not VALID_MODES[mode] then return end
    if not SKSaves.hasActiveSave(src) then return end
    SKSaves.write(src, 'settings.gearboxMode', mode)
end)

local function pushMode(src)
    local mode = SKSaves.read(src, 'settings.gearboxMode') or Config.Gearbox.defaultMode
    if mode == 'off' then return end
    TriggerClientEvent('sk_streetkings:gearbox:applyMode', src, mode)
end

-- qbx_core emits this locally (server/player.lua) once the character object is
-- built, which is when SKSaves can resolve a citizenid to read the profile row.
AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player and player.PlayerData and player.PlayerData.source
    if not src then return end
    -- Small delay so the client has its modules running before the mode lands.
    SetTimeout(2000, function() pushMode(src) end)
end)
