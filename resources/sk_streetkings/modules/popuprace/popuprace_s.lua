-- Pop-up races: periodically opens an unhosted lobby on a random unlocked
-- route (via SKMultiplayer.createPopupLobby, modules/racing/multiplayer_s.lua)
-- and invites whoever is near that route's start line to join before it
-- auto-starts. Everything about actually running the race — checkpoints,
-- standings, position payout, leaderboard — is the existing multiplayer
-- lobby's own code; this file only ever decides WHEN, WHERE, and WHO gets
-- asked.
--
-- Gated routes (unlockRequirement) are skipped for route selection so an
-- invite never goes out for a race half the server can't actually join.
-- So are air and offroad routes: those hand out their own vehicle or need one
-- built for the terrain, which an invite to whoever happens to be nearby in a
-- street car cannot promise.

if not Config.Modules.popupRace then return end

local cfg = Config.PopupRace

---@return table ids of every unlockRequirement-free route (static + custom)
local function eligibleRouteIds()
    local ids = {}
    for id, def in pairs(SKRoutes.getAll()) do
        if not def.unlockRequirement and not def.solo and (def.kind or 'road') == 'road' then
            ids[#ids + 1] = id
        end
    end
    return ids
end

---@param lobby table
---@param def table route definition
local function announceToNearbyPlayers(lobby, def)
    local startCoords = vector3(def.start.x, def.start.y, def.start.z)
    local message = cfg.announceMessage:format(def.name, cfg.joinWindowSec)

    for _, srcStr in ipairs(GetPlayers()) do
        local src = tonumber(srcStr)
        local ped = src and GetPlayerPed(src) or 0
        if ped ~= 0 then
            local dist = #(GetEntityCoords(ped) - startCoords)
            if dist <= cfg.announceRadiusMeters then
                TriggerClientEvent('sk_streetkings:popuprace:announce', src, {
                    lobbyId       = lobby.id,
                    routeName     = def.name,
                    message       = message,
                    coords        = { x = startCoords.x, y = startCoords.y, z = startCoords.z },
                    joinWindowSec = cfg.joinWindowSec,
                    arriveRadius  = cfg.arriveRadiusMeters,
                })
            end
        end
    end
end

local function trySpawnPopup()
    local ids = eligibleRouteIds()
    if #ids == 0 then return end

    local routeId = ids[math.random(#ids)]
    local def = SKRoutes.get(routeId)
    if not def then return end

    local lobby = SKMultiplayer.createPopupLobby(routeId, { lobbyTimeoutSeconds = cfg.joinWindowSec })
    if not lobby then return end

    announceToNearbyPlayers(lobby, def)
end

CreateThread(function()
    while true do
        Wait(math.random(cfg.intervalMsMin, cfg.intervalMsMax))
        if #GetPlayers() > 0 then
            trySpawnPopup()
        end
    end
end)
