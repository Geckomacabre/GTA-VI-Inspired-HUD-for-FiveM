--[[
    Ball bookkeeping.

    The server never touches ball physics — it only decides who is allowed to be
    holding one, and keeps the list of loose balls so clients know what they can
    pick up. That gives us the responsiveness of local physics without letting a
    player spawn an armful of basketballs.

    Holders
    -------
    A holder is whoever has a ball in their hands: a player, by server id, or an
    NPC, by the negative id the match gave it. An NPC only exists as a ped on its
    driver's client, so everything an NPC does arrives from that driver, and the
    first check on any of it is that the sender really is the driver
    (BB.botDriver, in match.lua).
]]

local carrying = {}    -- [holder] = true
local loose    = {}    -- [netId] = { shooter = holder, at = os.time(), passTo? }

--- Who a request is being made for: the sender, or an NPC the sender drives.
--- @return number|nil holder, boolean isBot
local function holderFor(source, aiId)
    if aiId == nil then return source, false end
    if type(aiId) ~= 'number' or aiId >= 0 then return nil, false end
    if BB.botDriver(aiId) ~= source then return nil, false end

    return aiId, true
end

--- Tells everyone who has a ball, so defenders know who to guard and a steal
--- knows who it's aimed at. Players get a state bag; an NPC's ped is tagged by
--- its driver, who is the only one who can see it to tag.
local function setCarrying(holder, value)
    carrying[holder] = value or nil

    if holder > 0 then
        local state = Player(holder).state
        if state then state:set('bbBall', value and true or false, true) end
    end
end

function BB.isCarrying(holder)
    return carrying[holder] == true
end

local function giveBall(source)
    setCarrying(source, true)
    TriggerClientEvent('gk_basketball:giveBall', source)
end

--- Loose balls lying within a court's bounds.
local function looseOnCourt(court)
    local n = 0

    for netId in pairs(loose) do
        local entity = NetworkGetEntityFromNetworkId(netId)

        if entity and entity ~= 0 and DoesEntityExist(entity)
            and #(GetEntityCoords(entity) - court.centre) < Config.Match.courtRadius then
            n = n + 1
        end
    end

    return n
end

--- True if a court in a live one-ball match already has its ball.
local function courtHasBall(courtId)
    local court = BB.courts[courtId]
    if not court then return false end

    for _, holder in ipairs(BB.courtMembers(courtId)) do
        if carrying[holder] then return true end
    end

    return looseOnCourt(court) > 0
end

--- The one-ball rule: during a live match there is a single ball on the court,
--- and nobody conjures a second.
local function blockedByOneBall(source)
    if not Config.Match.oneBall then return false end

    local courtId, live = BB.courtOf(source)
    return courtId ~= nil and live and courtHasBall(courtId)
end

--------------------------------------------------------------------------------
-- Getting a ball
--------------------------------------------------------------------------------

-- ox_inventory item use (client export calls through to here).
RegisterNetEvent('gk_basketball:useItem', function()
    local source = source

    if carrying[source] then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.hands_full, 'error')
        return
    end

    if not Config.Ball.item then return end

    if blockedByOneBall(source) then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.one_ball, 'error')
        return
    end

    if not exports.ox_inventory:RemoveItem(source, Config.Ball.item, 1) then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.no_ball, 'error')
        return
    end

    giveBall(source)
end)

-- Ball rack on a court: no item needed.
RegisterNetEvent('gk_basketball:requestBall', function(courtId, aiId)
    local source = source

    if not Config.Match.freeBallsOnCourt then return end

    local holder, isBot = holderFor(source, aiId)
    if not holder then return end

    if carrying[holder] then
        if not isBot then
            TriggerClientEvent('gk_basketball:notify', source, Config.Text.hands_full, 'error')
        end
        return
    end

    local court = BB.courts[courtId]
    if not court then return end

    -- Must actually be standing on the court.
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end
    if #(GetEntityCoords(ped) - court.centre) > Config.Match.courtRadius then return end

    -- An NPC only ever takes one off the rack when the court has none: it plays
    -- with the ball that's there, like anybody else.
    if isBot then
        if courtHasBall(courtId) then return end

        setCarrying(holder, true)
        TriggerClientEvent('gk_basketball:aiGiveBall', source, holder)
        return
    end

    if blockedByOneBall(source) then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.one_ball, 'error')
        return
    end

    giveBall(source)
end)

--------------------------------------------------------------------------------
-- Practice balls lying on a court
--------------------------------------------------------------------------------

--[[
    A court has a few balls lying on it. Anyone can walk up to one and pick it up,
    in a game or not, and it is back on the floor a few seconds later. Which ones
    are gone is kept here so that everybody sees the same floor.
]]
local taken = {}    -- [courtId] = { [index] = os.time() at which it is back }

local function publishBalls()
    local out = {}

    for courtId, spots in pairs(taken) do
        local list = {}

        -- Keyed by text: a table with holes in its numbering doesn't travel well.
        for index in pairs(spots) do list[tostring(index)] = true end

        out[courtId] = list
    end

    GlobalState[BB.STATE_BALLS] = out
end

RegisterNetEvent('gk_basketball:takeLooseBall', function(courtId, index)
    local source = source

    if type(courtId) ~= 'string' or type(index) ~= 'number' then return end

    local court = BB.courts[courtId]
    if not court then return end

    local spot = BB.ballSpots(court)[index]
    if not spot or (taken[courtId] and taken[courtId][index]) then return end

    if carrying[source] then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.hands_full, 'error')
        return
    end

    -- Has to be stood by it.
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end

    local at = GetEntityCoords(ped)
    if (at.x - spot.x) ^ 2 + (at.y - spot.y) ^ 2 > 3.5 ^ 2 then return end

    if blockedByOneBall(source) then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.one_ball, 'error')
        return
    end

    taken[courtId] = taken[courtId] or {}
    taken[courtId][index] = os.time() + Config.Ball.looseRespawn

    publishBalls()
    giveBall(source)
end)

CreateThread(function()
    publishBalls()

    while true do
        Wait(2000)

        local now = os.time()
        local changed = false

        for courtId, spots in pairs(taken) do
            for index, back in pairs(spots) do
                if now >= back then
                    spots[index] = nil
                    changed = true
                end
            end

            if not next(spots) then taken[courtId] = nil end
        end

        if changed then publishBalls() end
    end
end)

--------------------------------------------------------------------------------
-- Losing a ball
--------------------------------------------------------------------------------

--- Shot, passed, tossed, fumbled: the ball is now loose and anyone may grab it.
--- @param passTo number|nil Server id the ball was thrown to, so their game can
---        catch it without a key press. Only ever a hint: catching still goes
---        through pickupBall like any other pickup.
--- @param aiId number|nil Set when it was an NPC of the sender's that let go.
RegisterNetEvent('gk_basketball:ballReleased', function(netId, passTo, aiId)
    local source = source

    local holder = holderFor(source, aiId)
    if not holder or not carrying[holder] then return end
    if type(netId) ~= 'number' then return end

    setCarrying(holder, false)

    local data = { shooter = holder, at = os.time() }

    if type(passTo) == 'number' and passTo ~= source and passTo > 0 and GetPlayerName(passTo) then
        data.passTo = passTo
    end

    loose[netId] = data

    TriggerClientEvent('gk_basketball:setLooseBall', -1, netId, data)
end)

-- Put away: returns the inventory item if we can.
RegisterNetEvent('gk_basketball:stowBall', function(aiId)
    local source = source

    local holder, isBot = holderFor(source, aiId)
    if not holder or not carrying[holder] then return end

    setCarrying(holder, false)

    if not isBot and Config.Ball.item then
        exports.ox_inventory:AddItem(source, Config.Ball.item, 1)
    end
end)

lib.callback.register('gk_basketball:pickupBall', function(source, netId, aiId)
    local holder, isBot = holderFor(source, aiId)
    if not holder then return false end

    if carrying[holder] then return false end
    if not loose[netId] then return false end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 then
        loose[netId] = nil
        TriggerClientEvent('gk_basketball:setLooseBall', -1, netId, nil)
        return false
    end

    -- Range check against the real entity position, not a client claim. For an
    -- NPC the only position the server has is its driver's, so the driver has
    -- to be on the same court as the ball; where on it the NPC is, the driver
    -- is trusted for, as they are for everything else about it.
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false end

    local reach = isBot and Config.Match.courtRadius * 2.0 or (Config.Ball.catchRadius + 1.5)
    if #(GetEntityCoords(ped) - GetEntityCoords(entity)) > reach then
        return false
    end

    loose[netId] = nil
    DeleteEntity(entity)
    TriggerClientEvent('gk_basketball:setLooseBall', -1, netId, nil)

    setCarrying(holder, true)
    return true
end)

--------------------------------------------------------------------------------
-- Steals
--------------------------------------------------------------------------------

--[[
    Reaching in.

    Whoever is on the ball is told to drop it, and it comes loose as a live ball
    for either side: a steal is a chance at the ball, not the ball. The odds are
    worse against somebody who is protecting it (lined up to shoot, both hands on
    it) than against a dribble, and a reach that misses costs the reacher a
    moment before they can try again.
]]
local lastSteal = {}    -- [thief] = ms

RegisterNetEvent('gk_basketball:steal', function(victim, aiId, victimAiming)
    local source = source
    local cfg = Config.Steal

    if not cfg or not cfg.enabled then return end
    if type(victim) ~= 'number' then return end

    local thief, thiefIsBot = holderFor(source, aiId)
    if not thief or thief == victim then return end
    if carrying[thief] or not carrying[victim] then return end

    local now = GetGameTimer()
    if lastSteal[thief] and now - lastSteal[thief] < cfg.cooldown then return end
    lastSteal[thief] = now

    -- Who has to be told to let go: the victim, or the driver of the NPC that is.
    local victimOwner = victim > 0 and victim or BB.botDriver(victim)
    if not victimOwner or not GetPlayerName(victimOwner) then return end

    -- Both ends have to be on the same court, or close by in the open.
    local thiefPed, victimPed = GetPlayerPed(source), GetPlayerPed(victimOwner)
    if not thiefPed or thiefPed == 0 or not victimPed or victimPed == 0 then return end

    local apart = #(GetEntityCoords(thiefPed) - GetEntityCoords(victimPed))
    local bots = thiefIsBot or victim < 0

    -- Player on player, the server has both positions and holds them to arm's
    -- reach. With an NPC at either end it has only the driver's.
    if apart > (bots and Config.Match.courtRadius * 2.0 or cfg.reach + 1.5) then return end

    -- Team-mates don't pick each other's pockets.
    if BB.sameTeam(thief, victim) then return end
    if cfg.matchOnly and not BB.sameMatch(thief, victim) then return end

    local chance = (thiefIsBot and (BB.botSkill(thief) or {}).steal or cfg.chance) or 0.0
    if victimAiming == true then chance = chance * cfg.protectedFactor end

    if math.random() >= chance then
        if not thiefIsBot then
            TriggerClientEvent('gk_basketball:notify', source, Config.Text.steal_missed, 'error')
        end
        return
    end

    if victim > 0 then
        TriggerClientEvent('gk_basketball:stripped', victim, nil)
    else
        TriggerClientEvent('gk_basketball:stripped', victimOwner, victim)
    end

    if not thiefIsBot then
        TriggerClientEvent('gk_basketball:notify', source, Config.Text.steal_made, 'success')
    end
end)

--------------------------------------------------------------------------------
-- Tip-off
--------------------------------------------------------------------------------

--- Clears a court down to no balls at all.
--- @param refund boolean Give an inventory ball back to anyone who had one taken
---        out of their hands. For tip-off, when what they're holding may be
---        their own; never mid-match, when it is the match ball.
function BB.clearCourtBalls(courtId, refund)
    local court = BB.courts[courtId]
    if not court then return end

    for _, holder in ipairs(BB.courtMembers(courtId)) do
        if carrying[holder] then
            setCarrying(holder, false)

            if holder > 0 then
                TriggerClientEvent('gk_basketball:takeAway', holder, nil)

                if refund and Config.Ball.item then
                    exports.ox_inventory:AddItem(holder, Config.Ball.item, 1)
                end
            else
                local driver = BB.botDriver(holder)
                if driver then TriggerClientEvent('gk_basketball:takeAway', driver, holder) end
            end
        end
    end

    for netId in pairs(loose) do
        local entity = NetworkGetEntityFromNetworkId(netId)
        local here = entity and entity ~= 0 and DoesEntityExist(entity)
            and #(GetEntityCoords(entity) - court.centre) < Config.Match.courtRadius

        if here then
            DeleteEntity(entity)
            loose[netId] = nil
            TriggerClientEvent('gk_basketball:setLooseBall', -1, netId, nil)
        end
    end
end

--- Puts the match ball in somebody's hands.
function BB.giveMatchBall(holder)
    if carrying[holder] then return end

    if holder > 0 then
        giveBall(holder)
    else
        local driver = BB.botDriver(holder)
        if not driver then return end

        setCarrying(holder, true)
        TriggerClientEvent('gk_basketball:aiGiveBall', driver, holder)
    end
end

--- An NPC has been removed; forget anything it was holding.
function BB.forgetHolder(holder)
    carrying[holder] = nil
    lastSteal[holder] = nil
end

--------------------------------------------------------------------------------
-- Sound
--------------------------------------------------------------------------------

--[[
    A ball is simulated by one client, so only that client knows when it bounced.
    It says so here and everyone else in earshot is told. Purely cosmetic, so the
    checks are about not being a megaphone: known kinds only, a budget per
    player, and the sender has to be somewhere near the sound they are reporting.
]]
local FX_KINDS  = { bounce = true, dribble = true, rim = true, board = true, net = true, splash = true, body = true,
    catch = true, squeak = true }
local FX_RANGE  = 55.0
local fxBudget  = {}    -- [src] = { windowStart, count }

RegisterNetEvent('gk_basketball:fx', function(kind, x, y, z, strength)
    local source = source

    if not FX_KINDS[kind] then return end
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end
    if type(strength) ~= 'number' then strength = 3.0 end

    local now = GetGameTimer()
    local budget = fxBudget[source]

    if not budget or now - budget[1] > 1000 then
        budget = { now, 0 }
        fxBudget[source] = budget
    end

    budget[2] = budget[2] + 1
    if budget[2] > 24 then return end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end

    local at = vec3(x, y, z)
    if #(GetEntityCoords(ped) - at) > 150.0 then return end

    local bucket = GetPlayerRoutingBucket(source)

    for _, id in ipairs(GetPlayers()) do
        local other = tonumber(id)

        if other ~= source and GetPlayerRoutingBucket(other) == bucket then
            local otherPed = GetPlayerPed(other)

            if otherPed and otherPed ~= 0 and #(GetEntityCoords(otherPed) - at) < FX_RANGE then
                TriggerClientEvent('gk_basketball:fx', other, kind, x, y, z, strength)
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Housekeeping
--------------------------------------------------------------------------------

-- Sweep balls whose entity has gone (client left, stream-out) or that have sat
-- untouched for too long.
CreateThread(function()
    while true do
        Wait(15000)

        local now = os.time()
        local expiry = Config.Ball.despawnAfter

        for netId, data in pairs(loose) do
            local entity = NetworkGetEntityFromNetworkId(netId)
            local gone   = not entity or entity == 0 or not DoesEntityExist(entity)
            local stale  = expiry > 0 and (now - data.at) > expiry

            if gone or stale then
                if not gone then DeleteEntity(entity) end
                loose[netId] = nil
                TriggerClientEvent('gk_basketball:setLooseBall', -1, netId, nil)
            end
        end
    end
end)

AddEventHandler('playerJoining', function()
    TriggerClientEvent('gk_basketball:syncLooseBalls', source, loose)
end)

AddEventHandler('playerDropped', function()
    local source = source

    -- Straight out of the table: their state bag has gone with them.
    carrying[source] = nil
    fxBudget[source] = nil
    lastSteal[source] = nil
end)
