-- Odometer/top-speed reporting and the career stats menu.
--
-- StreetKings rendered stats through its NUI pause menu; here it is an ox_lib
-- context menu opened from the Race Organizer or /racestats.

if not Config.Modules.stats then return end

local SYNC_INTERVAL_MS = 30000
local METRES_TO_MILES  = 0.000621371
local MPS_TO_MPH       = 2.236936

local pendingMiles  = 0.0
local pendingTopMph = 0.0

CreateThread(function()
    local lastCoords = GetEntityCoords(cache.ped)

    while true do
        Wait(1000)

        local coords = GetEntityCoords(cache.ped)

        if cache.vehicle and cache.vehicle ~= 0 and GetPedInVehicleSeat(cache.vehicle, -1) == cache.ped then
            local metres = #(coords - lastCoords)
            -- A teleport or a respawn would otherwise register as miles driven.
            if metres < 200.0 then
                pendingMiles = pendingMiles + (metres * METRES_TO_MILES)
            end

            local mph = GetEntitySpeed(cache.vehicle) * MPS_TO_MPH
            if mph > pendingTopMph then pendingTopMph = mph end
        end

        lastCoords = coords
    end
end)

CreateThread(function()
    while true do
        Wait(SYNC_INTERVAL_MS)
        if pendingMiles > 0 or pendingTopMph > 0 then
            TriggerServerEvent('sk_streetkings:stats:sync', pendingMiles, pendingTopMph)
            pendingMiles  = 0.0
            pendingTopMph = 0.0
        end
    end
end)

-- ── Menu ────────────────────────────────────────────────────────────────────

local ROWS = {
    { key = 'racesCompleted',      label = 'Races Completed' },
    { key = 'racesWon',            label = 'Races Won' },
    { key = 'racesLost',           label = 'Races Lost' },
    { key = 'bestWinStreak',       label = 'Best Win Streak' },
    { key = 'goalTimesBeaten',     label = 'Goal Times Beaten' },
    { key = 'npcChallengesWon',    label = 'Street Challenges Won' },
    { key = 'npcChallengesLost',   label = 'Street Challenges Lost' },
    { key = 'betsWon',             label = 'NPC Race Bets Won' },
    { key = 'stuntJumpsCompleted', label = 'Stunt Jumps Landed' },
    { key = 'rampagesCompleted',   label = 'Rampages Completed' },
    { key = 'bestRampageScore',    label = 'Best Rampage Score' },
    { key = 'bestDriftScore',      label = 'Best Drift Score' },
    { key = 'driftPointsTotal',    label = 'Total Drift Points' },
    { key = 'topSpeedMph',         label = 'Top Speed (mph)', decimals = 1 },
    { key = 'totalMilesDriven',    label = 'Miles Driven',    decimals = 1 },
    { key = 'speedCameraFlashes',  label = 'Speed Camera Flashes' },
    { key = 'policeEscapes',       label = 'Police Escapes' },
    { key = 'policeBusts',         label = 'Times Busted' },
    { key = 'totalRepairs',        label = 'Roadside Repairs' },
    { key = 'clothingPurchased',   label = 'Clothing Bought' },
    { key = 'totalCashEarned',     label = 'Cash Earned',  money = true },
    { key = 'totalCashSpent',      label = 'Cash Spent',   money = true },
}

function OpenStatsMenu()
    CreateThread(function()
        local data = lib.callback.await('sk_streetkings:stats:get', false)
        if not data then
            lib.notify({ title = 'Stats', description = 'No profile loaded.', type = 'error' })
            return
        end

        local options = {
            {
                title       = ('Race Level %d'):format(data.level or 0),
                description = ('%d XP total'):format(data.xp or 0),
                icon        = 'medal',
                disabled    = true,
            },
        }

        for _, row in ipairs(ROWS) do
            local value = data.stats[row.key] or 0
            local text
            if row.money then
                text = SKFormatMoney(value)
            elseif row.decimals then
                text = ('%.*f'):format(row.decimals, value)
            else
                text = tostring(math.floor(value))
            end

            options[#options + 1] = { title = row.label, description = text, disabled = true }
        end

        lib.registerContext({ id = 'sk_stats', title = 'Career Stats', options = options })
        lib.showContext('sk_stats')
    end)
end

RegisterCommand('racestats', OpenStatsMenu, false)
exports('openStatsMenu', OpenStatsMenu)
