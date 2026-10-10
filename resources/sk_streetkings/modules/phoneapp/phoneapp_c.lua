-- LB-Phone app for sk_streetkings. Mirrors geocaching_phone's structure
-- exactly (AddCustomApp + RegisterNUICallback bridging to server callbacks
-- that already exist elsewhere in this resource) - this file adds no new
-- server-side data access beyond what stats_s.lua and racing/leaderboard_s.lua
-- already expose, and reads the pending-invite state straight out of
-- SKNpcInvite (npcinvite_c.lua, loaded just before this file) rather than
-- round-tripping to the server for something that's already local.

local CURATED_CLASSES = {
    { id = 7, label = 'Super' },
    { id = 6, label = 'Sports' },
    { id = 5, label = 'Sports Classics' },
    { id = 4, label = 'Muscle' },
    { id = 2, label = 'SUVs' },
    { id = 8, label = 'Motorcycles' },
}

local function registerPhoneApp()
    local res = GetCurrentResourceName()
    local added, errMsg = exports['lb-phone']:AddCustomApp({
        identifier   = 'streetkings',
        name         = 'Street Kings',
        description  = 'Career stats, leaderboards, and rivals looking for a race',
        developer    = 'Street Kings',
        icon         = 'https://cfx-nui-' .. res .. '/modules/phoneapp/ui/icon.svg',
        ui           = res .. '/modules/phoneapp/ui/index.html',
        resourceName = res,
        price        = 0,
        size         = 512,
    })
    if not added then
        print('^1[sk_streetkings/phoneapp] lb-phone app failed to register: ' .. tostring(errMsg) .. '^7')
    end
end

CreateThread(function()
    while GetResourceState('lb-phone') ~= 'started' do Wait(500) end
    registerPhoneApp()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'lb-phone' then registerPhoneApp() end
end)

-- ── NUI callbacks ────────────────────────────────────────────────────────────

RegisterNUICallback('streetkings:boot', function(_, cb)
    local pd   = exports.qbx_core:GetPlayerData()
    local info = pd and pd.charinfo
    local name = info and (info.firstname .. ' ' .. info.lastname) or GetPlayerName(PlayerId())

    -- SKRaceEvents is a shared script, already loaded client-side - no
    -- server round-trip needed for the route list. SKRouteBuilder (shared/
    -- route_sh.lua) is loaded before this file too, so the distance/lap
    -- math the Races panel shows comes from the same source the race
    -- flows themselves use.
    local routes = {}
    for id, route in pairs(SKRaceEvents or {}) do
        routes[#routes + 1] = {
            id       = id,
            name     = route.name,
            scheme   = route.scheme or 'ordered',
            laps     = route.laps or 1,
            goalTime = route.goalTime,
            distance = SKRouteBuilder.routeDistanceMeters(route) * 0.000621371,
            gated    = route.unlockRequirement ~= nil,
        }
    end
    table.sort(routes, function(a, b) return a.name < b.name end)

    cb({ ok = true, charName = name, routes = routes, classes = CURATED_CLASSES })
end)

RegisterNUICallback('streetkings:getProfile', function(_, cb)
    local result = lib.callback.await('sk_streetkings:stats:get', false)
    cb(result or { stats = {}, level = 0, xp = 0 })
end)

RegisterNUICallback('streetkings:getLeaderboard', function(data, cb)
    local result = lib.callback.await(
        'sk_streetkings:racing:getLeaderboard', false,
        data.routeId, data.vehicleClass, data.period or 'all'
    )
    cb(result or {})
end)

RegisterNUICallback('streetkings:getInvite', function(_, cb)
    cb(SKNpcInvite.getPending() or false)
end)

RegisterNUICallback('streetkings:acceptInvite', function(_, cb)
    local ok = SKNpcInvite.accept()
    if ok then SetNuiFocus(false, false) end -- get out of the way so the player can drive
    cb({ ok = ok })
end)

RegisterNUICallback('streetkings:declineInvite', function(_, cb)
    cb({ ok = SKNpcInvite.decline() })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
