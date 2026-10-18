Radial = {}

Radial.MenuID = "open_clothing_menu"

local radialOptionAdded = false

function Radial.IsOX()
    local resName = "ox_lib"
    if GetResourceState(resName) ~= "missing" and Config.UseOxRadial then
        Radial.ResourceName = resName
        return true
    end
    return false
end

function Radial.IsQB()
    local resName = "qb-radialmenu"
    if GetResourceState(resName) ~= "missing" then
        Radial.ResourceName = resName
        return true
    end
    return false
end

function Radial.IsQBX()
    local resName = "um_radialmenu"
    if GetResourceState(resName) ~= "missing" then
        Radial.ResourceName = resName
        return true
    end
    return false
end

function Radial.AddOption(currentZone)
    if not Config.UseRadialMenu then return end

    if not currentZone then
        Radial.Remove()
        return
    end
    local event, title
    -- Shops (clothing/barber/tattoo) are handled by client/shops.lua's floor-marker
    -- interaction now, not the currentZone system, so only the job/outfit-room
    -- zones (still target/zone-driven) ever reach this.
    local zoneEvents = {
        clothingRoom = {"illenium-appearance:client:OpenClothingRoom", _L("menu.title")},
        playerOutfitRoom = {"illenium-appearance:client:OpenPlayerOutfitRoom", _L("menu.outfitsTitle")},
    }
    if zoneEvents[currentZone.name] then
        event, title = table.unpack(zoneEvents[currentZone.name])
    end

    Radial.Add(title, event)
    radialOptionAdded = true
end

function Radial.RemoveOption()
    if radialOptionAdded then
        Radial.Remove()
        radialOptionAdded = false
    end
end

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        if Config.UseOxRadial and GetResourceState("ox_lib") == "started" or GetResourceState("qb-radialmenu") == "started" then
            Radial.RemoveOption()
        end
    end
end)
