-- Repair station authorisation, charging and stat tracking.
--
-- The client asks before it repairs, so a player who cannot pay is refused
-- rather than fixed for free.

if not Config.Modules.repairPoints then return end

local COOLDOWN_MS = 4000
local lastRepair = {}

lib.callback.register('sk_streetkings:repair:request', function(source)
    local now = GetGameTimer()

    -- The client gates on its own cooldown too; this stops a spoofed request
    -- from draining the stat counter or double-charging.
    if lastRepair[source] and now - lastRepair[source] < COOLDOWN_MS then
        return false, 'Still cooling down.'
    end

    if Config.Repair.cost > 0 then
        if not SKPlayer.removeMoney(source, Config.Repair.cost, 'sk-repair-station') then
            return false, ('You need %s for a repair.'):format(SKFormatMoney(Config.Repair.cost))
        end
        if Config.Modules.stats then
            SKStats.increment(source, 'totalCashSpent', Config.Repair.cost)
        end
    end

    lastRepair[source] = now

    if Config.Modules.stats then
        SKStats.increment(source, 'totalRepairs', 1)
    end

    return true
end)

AddEventHandler('playerDropped', function()
    lastRepair[source] = nil
end)
