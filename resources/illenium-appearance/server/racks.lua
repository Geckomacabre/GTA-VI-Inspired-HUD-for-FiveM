-- Rack try-on, the till (client/racks.lua): one item of a rack's category for that category's price.
-- Nothing the client says is charged: the price is Config.Racks' own (plus tax, like the store's checkout), and the
-- player has to stand at a rack of that category in that store.

if not Config.Racks or not Config.Racks.enabled then return end

local RC = Config.Racks
local lastPurchase = {}

-- (without OneSync the server does not know where a ped is: the place is then taken on trust, the price never is)
local knowsPositions = GetConvar("onesync", "off") ~= "off"

local function getRackPrice(category)
    local price = RC.categories[category].price or RC.defaultPrice or 0
    local taxRate = RC.taxRate or Config.TaxRate or 0
    return math.floor(price * (1 + taxRate) + 0.5)
end

-- the cash in the player's pocket, for the page (nil where the framework cannot be asked)
local function getCash(src)
    local ok, cash = pcall(function()
        if Framework.QBCore() then
            local Player = exports["qb-core"]:GetCoreObject().Functions.GetPlayer(src)
            return Player and Player.PlayerData.money.cash
        elseif Framework.ESX() then
            local Player = exports["es_extended"]:getSharedObject().GetPlayerFromId(src)
            return Player and Player.getAccount("money").money
        elseif Framework.Ox() then
            return exports.ox_inventory:GetItemCount(src, "money")
        end
    end)
    return ok and tonumber(cash) or nil
end

-- can the player pay that, from the pocket or the bank (nil where the framework cannot be asked)
local function canAfford(src, total)
    if total <= 0 then return true end
    local ok, can = pcall(function()
        return Framework.HasMoney(src, "cash", total) or Framework.HasMoney(src, "bank", total)
    end)
    if not ok then return nil end
    return can and true or false
end

-- the racks of a store, as the client has them: the generated ones (or their override) and the extra ones
local function getStoreRacks(storeIndex)
    local racks = {}
    local own = (RC.override and RC.override[storeIndex]) or (Config.RackSpots and Config.RackSpots[storeIndex]) or {}
    local extra = (RC.extra and RC.extra[storeIndex]) or {}
    for _, source in ipairs({ own, extra }) do
        for i = 1, #source do
            racks[#racks + 1] = source[i]
        end
    end
    return racks
end

-- is the player at a rack of that category in that clothing store?
local function isAtRack(src, storeIndex, category)
    local store = type(storeIndex) == "number" and Config.Stores[storeIndex]
    if not store or store.type ~= "clothing" then return false end
    if type(category) ~= "string" or not RC.categories[category] then return false end

    local ped = knowsPositions and GetPlayerPed(src)
    if knowsPositions and (not ped or ped == 0) then return false end

    local coords = ped and GetEntityCoords(ped)
    local racks = getStoreRacks(storeIndex)
    for i = 1, #racks do
        local rack = racks[i]
        if rack.category == category and (not coords or #(coords - rack.coords) <= RC.purchaseRange) then
            return true
        end
    end
    return false
end

lib.callback.register("illenium-appearance:server:rackOpen", function(source, storeIndex, category)
    if type(category) ~= "string" or not RC.categories[category] then return nil end
    local price = getRackPrice(category)
    return {
        cash = getCash(source),
        afford = canAfford(source, price),
        price = price
    }
end)

lib.callback.register("illenium-appearance:server:rackPurchase", function(source, storeIndex, category)
    local src = source
    if not isAtRack(src, storeIndex, category) then
        return { ok = false, reason = "tooFar" }
    end

    -- (one purchase at a time: Enter held down is not a spree)
    local now = GetGameTimer()
    if lastPurchase[src] and now - lastPurchase[src] < 500 then
        return { ok = false, reason = "failed" }
    end
    lastPurchase[src] = now

    -- cash first, then the bank
    local total = getRackPrice(category)
    local ok, paid = pcall(function()
        if total <= 0 then
            return "free"
        elseif Framework.HasMoney(src, "cash", total) and Framework.RemoveMoney(src, "cash", total) then
            return "cash"
        elseif Framework.HasMoney(src, "bank", total) and Framework.RemoveMoney(src, "bank", total) then
            return "bank"
        end
    end)

    if not ok then
        return { ok = false, reason = "failed" }
    elseif not paid then
        return { ok = false, reason = "noMoney", cash = getCash(src), afford = false }
    end

    return {
        ok = true,
        paid = paid,
        total = total,
        cash = getCash(src),
        afford = canAfford(src, total)
    }
end)

AddEventHandler("playerDropped", function()
    lastPurchase[source] = nil
end)
