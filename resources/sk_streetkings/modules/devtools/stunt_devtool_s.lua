-- Admin commands for the stunt jump placement tool.
--
-- Upstream gated the devtool on a `streetkings_enableDevtools` convar, which is
-- an on/off switch for the whole server rather than a permission check. These
-- go through SKPlayer.isAdmin instead, matching /racemaker. The save and delete
-- callbacks in modules/stunts/stunts_s.lua re-check on their own, so a client
-- that fakes the open event still cannot write anything.

if not Config.Modules.stunts then return end

local COMMANDS = {
    stuntdev    = { event = 'sk_streetkings:stunts:admin:open',          help = 'Open the stunt jump placement tool' },
    stuntedit   = { event = 'sk_streetkings:stunts:admin:editNearest',   help = 'Edit the nearest stunt jump (within 200m)' },
    stuntdelete = { event = 'sk_streetkings:stunts:admin:deleteNearest', help = 'Delete the nearest stunt jump (within 200m)' },
}

for command, spec in pairs(COMMANDS) do
    RegisterCommand(command, function(src)
        if src == 0 then return end
        if not SKPlayer.isAdmin(src) then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Stunt Jumps', description = 'Admin only.', type = 'error',
            })
            return
        end
        TriggerClientEvent(spec.event, src)
    end, false)
end
