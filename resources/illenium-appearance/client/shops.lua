-- Clothing/barber/tattoo shop interaction.
--
-- Third-eye (ox_target) zone at each store, no ambient ped -- matches how
-- every other interaction point on this server works (shops/stashes/crafting
-- -> ox_target -> vice_hud's always-on prompt). No third-eye targetable clerk
-- was ever here before this pass: the previous design deliberately used an
-- ambient ped (doing its own scenario, third-eye-immune) plus a floor marker
-- you stood in, to mirror real GTA's clothes_shop_mp.c/shop_controller.c,
-- which script no interactable clerk at all. That's been dropped in favour of
-- consistency with the rest of the server -- see git history if the old
-- marker/ped behaviour is ever needed again.
--
-- Falls back to the old floor-marker/E system (no ped either) when
-- Config.UseTarget is false, same graceful-degradation precedent as
-- ClothingRooms/PlayerOutfitRooms (client/target/target.lua vs
-- client/zones.lua).

local MarkerRadius = 6.0
local InteractRadius = 1.5

local function IsShopStore(store)
    return not (Config.RCoreTattoosCompatibility and store.type == "tattoo") and Config.TargetConfig[store.type]
end

local function GetStoreAction(store)
    if store.type == "clothing" then
        return function()
            TriggerEvent("illenium-appearance:client:openClothingShopMenu")
        end
    elseif store.type == "barber" then
        return OpenBarberShop
    elseif store.type == "tattoo" then
        return OpenTattooShop
    end
end

-- the strip a barber or a tattoo parlour has besides its full menu (client/parlour.lua): "hair" / "tattoo", or nil
local function GetParlourKind(store)
    if not Config.Parlour or not Config.Parlour.enabled then return nil end
    if store.type == "barber" then
        return "hair"
    elseif store.type == "tattoo" then
        return "tattoo"
    end
    return nil
end

-- =============================================================================
-- Third-eye path (Config.UseTarget = true)
-- =============================================================================
local function SetupShopTargets()
    for k, v in pairs(Config.Stores) do
        if IsShopStore(v) then
            local targetConfig = Config.TargetConfig[v.type]
            local parameters = {
                options = {{
                    type = "client",
                    action = GetStoreAction(v),
                    icon = targetConfig.icon,
                    label = targetConfig.label,
                }},
                distance = targetConfig.distance,
                rotation = v.rotation
            }

            local kind = GetParlourKind(v)
            if kind then
                local index = k
                parameters.options[2] = {
                    type = "client",
                    action = function()
                        CreateThread(function()
                            OpenParlour(index, kind)
                        end)
                    end,
                    icon = targetConfig.icon,
                    label = kind == "hair" and Config.Parlour.text.hairOption or Config.Parlour.text.tattooOption,
                }
            end

            if v.usePoly then
                Target.AddPolyZone("shop_" .. k, v.points, parameters)
            else
                Target.AddBoxZone("shop_" .. k, v.coords, v.size, parameters)
            end
        end
    end
end

local function RemoveShopTargets()
    for k, v in pairs(Config.Stores) do
        if IsShopStore(v) then
            Target.RemoveZone("shop_" .. k)
        end
    end
end

-- =============================================================================
-- Floor-marker fallback (Config.UseTarget = false)
-- =============================================================================
local function ShopMarkerLoop()
    Wait(1000)
    while true do
        local sleep = 500
        local coords = GetEntityCoords(cache.ped)
        local closestStore, closestDist = nil, MarkerRadius

        for _, v in pairs(Config.Stores) do
            if IsShopStore(v) then
                local dist = #(coords - vector3(v.coords.xyz))
                if dist < closestDist then
                    closestDist = dist
                    closestStore = v
                end
            end
        end

        if closestStore then
            sleep = 0
            local c = closestStore.coords
            DrawMarker(1, c.x, c.y, c.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 0.6, 255, 255, 255, 120, false, false, 2, false, "", "", false)

            if closestDist < InteractRadius then
                lib.showTextUI("[E] " .. Config.TargetConfig[closestStore.type].label, Config.TextUIOptions)
                if IsControlJustReleased(0, 38) then
                    local action = GetStoreAction(closestStore)
                    if action then action() end
                end
            else
                lib.hideTextUI()
            end
        else
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end

if Config.UseTarget then
    CreateThread(SetupShopTargets)
else
    CreateThread(ShopMarkerLoop)
end

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        if Config.UseTarget then RemoveShopTargets() end
        lib.hideTextUI()
    end
end)
