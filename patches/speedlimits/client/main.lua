local enabled = true
local UIOpen = false
local currentStreet = nil
local frequency = Config.updateFrequency * 1000

-- The sign stands beside vice_hud's minimap, and goes when the minimap goes:
-- the pause menu, the inventory, a cutscene. vice_hud says so (see the handler
-- at the bottom of this file). True until told otherwise, so without vice_hud
-- nothing here changes.
local mapShown = true
-- Taken off the HUD by the player: the sign's "Show on HUD" row in vice_hud's
-- /movehud, or /hudspeedlimit. It rides in the same layout broadcast as the
-- sign's position (`hide` on layout.speedlimit).
local hudHidden = false

CreateThread(function()
    local savedState = GetResourceKvpString("speedLimit")
    if savedState then
        enabled = savedState == "true"
    else
        SetResourceKvp("speedLimit", "true")
    end
end)

RegisterCommand(Config.toggleCommand, function(source, args)
    local toggle = not enabled
    if toggle then
        SendNUIMessage({action = "show"})
        UIOpen = true
    else
        SendNUIMessage({action = "hide"})
        UIOpen = false
        currentStreet = nil
    end
    enabled = toggle
    SetResourceKvp("speedLimit", tostring(enabled))
end)

-- Exports ---------------------------------------------------------------------
-- fenix-police's ambient officers enforce the posted limit through these, so the
-- limits stay defined here in Config.SpeedLimits rather than being copied into
-- another resource and drifting out of sync.
--
-- Both return nil where a street has no posted limit, which the caller treats as
-- "unposted" rather than "no limit".

--- @param street string street name, as GetStreetNameFromHashKey returns it
--- @return number|nil mph
local function limitForStreet(street)
    if type(street) ~= 'string' then return nil end
    return Config.SpeedLimits[street]
end

exports('getSpeedLimitForStreet', limitForStreet)

--- @return number|nil mph, string|nil street
exports('getSpeedLimitAtCoords', function(x, y, z)
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(x + 0.0, y + 0.0, z + 0.0))
    return limitForStreet(street), street
end)

Citizen.CreateThread(function()
    while true do
        Wait(frequency)
        if IsPedInAnyVehicle(PlayerPedId()) and enabled and mapShown and not hudHidden then
            if not UIOpen then
                SendNUIMessage({action = "show"})
                UIOpen = true
            end
            
            local newStreet = GetStreetNameFromHashKey(GetStreetNameAtCoord(table.unpack(GetEntityCoords(PlayerPedId()))))
                
            if newStreet ~= currentStreet then
                currentStreet = newStreet
                local speed = Config.SpeedLimits[currentStreet]
                if speed then
                    SendNUIMessage({action = "setlimit", speed = speed})
                end
            end
        elseif UIOpen then
            SendNUIMessage({action = "hide"})
            UIOpen = false
        end
    end
end)

-- Position pushed from vice_hud's HUD editor (/movehud). This sign has its own
-- NUI page, so CSS cannot reach it from vice_hud — the offset is broadcast and
-- applied here instead.
-- The page's message handler switches on `action`, not `type` — sending `type`
-- here meant the offset message matched no case at all and was dropped, so the
-- sign never moved from /movehud. Both keys are sent now: `action` is the one
-- this page reads, `type` keeps any other listener working.
-- Shows or hides the sign at once for whatever just changed (the map, the
-- player's hide choice) rather than waiting for the loop above, which only
-- looks every few seconds: the sign should be gone the moment the pause menu
-- is up, not after it.
local function refresh()
    if not mapShown or hudHidden then
        if UIOpen then
            SendNUIMessage({ action = 'hide' })
            UIOpen = false
            currentStreet = nil   -- so the limit is re-sent when it is back
        end
    elseif enabled and not UIOpen and IsPedInAnyVehicle(PlayerPedId()) then
        SendNUIMessage({ action = 'show' })
        UIOpen = true
    end
end

AddEventHandler('vice_hud:layout', function(layout)
    local o = layout and layout.speedlimit
    SendNUIMessage({
        action = 'offset', type = 'offset',
        x = o and o.x or 0.0,
        y = o and o.y or 0.0,
        s = o and o.s or 1.0,
    })
    hudHidden = o ~= nil and (o.hide == 1 or o.hide == true)
    refresh()
end)

-- vice_hud raises this each time its minimap comes or goes.
local function followMap(shown)
    mapShown = shown ~= false
    refresh()
end

AddEventHandler('vice_hud:minimap', followMap)

CreateThread(function()
    Wait(2500)
    if GetResourceState('vice_hud') == 'started' then
        local ok, x, y, s, hidden = pcall(function() return exports.vice_hud:GetHudOffset('speedlimit') end)
        if ok then
            SendNUIMessage({ action = 'offset', type = 'offset', x = x or 0.0, y = y or 0.0, s = s or 1.0 })
            -- (an older vice_hud returns no fourth value: shown, as before)
            hudHidden = hidden == true
            refresh()
        end
        -- Started after vice_hud: the event has already been and gone, so ask.
        -- An older vice_hud has no such export, and then the sign simply stays.
        local asked, shown = pcall(function() return exports.vice_hud:IsMinimapShown() end)
        if asked and shown ~= nil then followMap(shown) end
    end
end)
