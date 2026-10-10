-- Police server half, ported from streetkings modules/freeroam/police_s.lua.
--
-- Picks which speed traps are live this restart and authorises the bust fine.
-- Upstream deducted straight from its own save document; money is qbx_core's
-- here, so the charge goes through SKPlayer.

if not Config.Modules.police then return end

local BUST_COOLDOWN_MS = 8000

local lastBustAt = {} -- src -> timestamp

-- ── Active traps ────────────────────────────────────────────────────────────
--
-- Only a fraction of the locations in data/police_traps.lua run at once, so the
-- map isn't blanketed in cops and the layout changes between restarts.

local activeTraps = {}

local function selectActiveTraps()
    local locations = SKPoliceTrapLocations or {}
    if #locations == 0 then return end

    local count = math.max(1, math.ceil(#locations * Config.Police.trapSpawnPercent))
    count = math.min(count, #locations)

    local pool = {}
    for i = 1, #locations do pool[i] = i end

    activeTraps = {}
    for i = 1, count do
        local pick = math.random(i, #pool)
        pool[i], pool[pick] = pool[pick], pool[i]
        activeTraps[#activeTraps + 1] = locations[pool[i]]
    end
end

selectActiveTraps()

lib.callback.register('sk_streetkings:police:getActiveTraps', function()
    return activeTraps
end)

-- ── Bust ────────────────────────────────────────────────────────────────────

lib.callback.register('sk_streetkings:police:confirmBust', function(source)
    if not SKSaves.hasActiveSave(source) then return { ok = false } end

    local now = GetGameTimer()
    if lastBustAt[source] and now - lastBustAt[source] < BUST_COOLDOWN_MS then
        return { ok = false }
    end
    lastBustAt[source] = now

    -- Take what they have rather than refusing the bust outright, so being
    -- broke isn't a way to drive off clean.
    local fine     = Config.Police.bustFine or 0
    local deducted = math.min(fine, SKPlayer.getMoney(source))
    if deducted > 0 then
        SKPlayer.removeMoney(source, deducted, 'sk-police-bust')
        if Config.Modules.stats then
            SKStats.increment(source, 'totalCashSpent', deducted)
        end
    end

    if Config.Modules.stats then
        SKStats.increment(source, 'policeBusts', 1)
    end

    local summary
    if deducted <= 0 then
        summary = 'Pulled over. Nothing on you to take.'
    elseif deducted < fine then
        summary = ('Pulled over. %s taken — all you were carrying.'):format(SKFormatMoney(deducted))
    else
        summary = ('Pulled over and fined %s.'):format(SKFormatMoney(deducted))
    end

    return { ok = true, summary = summary }
end)

RegisterNetEvent('sk_streetkings:police:escaped', function()
    if not Config.Modules.stats then return end
    SKStats.increment(source, 'policeEscapes', 1)
end)

AddEventHandler('playerDropped', function()
    lastBustAt[source] = nil
end)
