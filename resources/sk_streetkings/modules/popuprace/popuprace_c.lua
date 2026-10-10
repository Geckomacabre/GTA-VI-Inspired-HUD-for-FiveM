-- Client half of pop-up races: shows the invite blip/notify the server sent
-- (modules/popuprace/popuprace_s.lua) and auto-joins via JoinPopupLobby
-- (modules/racing/race_multiplayer_c.lua) once the player actually drives up
-- to the start line, the same "show up and you're in" pattern npcinvite uses
-- for its own rival meet-ups.

if not Config.Modules.popupRace then return end

---@type {lobbyId: string, coords: vector3, blip: number, expiresAt: number, arriveRadius: number}|nil
local pending  = nil
local watching = false

local function clearPending()
    if pending and pending.blip and DoesBlipExist(pending.blip) then
        RemoveBlip(pending.blip)
    end
    pending  = nil
    watching = false
end

local function startWatching()
    if watching then return end
    watching = true

    CreateThread(function()
        while pending and watching do
            Wait(1000)
            if not pending then break end

            if GetGameTimer() > pending.expiresAt then
                clearPending()
                break
            end

            local ped = PlayerPedId()
            if IsPedInAnyVehicle(ped, false)
                and #(GetEntityCoords(ped) - pending.coords) <= pending.arriveRadius
            then
                local lobbyId = pending.lobbyId
                clearPending() -- consumed before joining, so arrival can't double-trigger
                JoinPopupLobby(lobbyId)
                break
            end
        end
    end)
end

RegisterNetEvent('sk_streetkings:popuprace:announce', function(data)
    -- Already chasing one invite, mid-race, or mid a local AI challenge —
    -- don't stack a second thing to react to on top of it.
    if pending or IsInMultiplayerLobby() then return end
    if SKNpcRace and SKNpcRace.isActive() then return end

    local coords = vector3(data.coords.x, data.coords.y, data.coords.z)

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 225)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 1.0)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(data.routeName .. ' - Pop-up Race')
    EndTextCommandSetBlipName(blip)

    pending = {
        lobbyId      = data.lobbyId,
        coords       = coords,
        blip         = blip,
        expiresAt    = GetGameTimer() + (tonumber(data.joinWindowSec) or 60) * 1000,
        arriveRadius = tonumber(data.arriveRadius) or 20.0,
    }

    lib.notify({ title = 'Pop-up Race', description = data.message, type = 'inform', duration = 8000 })
    startWatching()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearPending()
end)
