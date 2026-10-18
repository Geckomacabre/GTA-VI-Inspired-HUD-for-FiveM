-- vice_hud's money off the screen while one of this resource's stores is open: the full menu (a store's, a clothing
-- room's, character creation), a rack's try-on (client/racks.lua) or the barber / tattoo strip (client/parlour.lua).
-- LocalPlayer.state.appearanceShop is true meanwhile (not replicated); vice_hud reads it as it reads ox_inventory's
-- invOpen, and hides its money and its "- $80" pop while it is. Config.HideHudMoneyInShops = false: never set.

if not Config.HideHudMoneyInShops then return end

local client = client
local Open = false

local function ShopOpen()
    if client.getConfig() then return true end
    if RackTryOnOpen and RackTryOnOpen() then return true end
    return ParlourOpen ~= nil and ParlourOpen()
end

local function Set(open)
    Open = open
    LocalPlayer.state:set("appearanceShop", open, false)
end

CreateThread(function()
    Set(false) -- (a restart of the resource with a store open left it on)
    while true do
        local open = ShopOpen() and true or false
        if open ~= Open then
            Set(open)
        end
        Wait(100)
    end
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() and Open then
        Set(false)
    end
end)
