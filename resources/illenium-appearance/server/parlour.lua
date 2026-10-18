-- Barber chair and tattoo parlour, the till (client/parlour.lua): a hairstyle, or a tattoo of shared/tattoos.lua, for
-- Config.Parlour's price plus tax (a tattoo's own `cost` wins). Nothing the client says is charged: the price is the
-- server's, the tattoo has to be one of the list, and the player has to be at a store of that kind.

if not Config.Parlour or not Config.Parlour.enabled then return end

local P = Config.Parlour
local StoreType = { hair = "barber", tattoo = "tattoo" }
local lastPurchase = {}

-- (without OneSync the server does not know where a ped is: the place is then taken on trust, the price never is)
local knowsPositions = GetConvar("onesync", "off") ~= "off"

local function total(price)
    local taxRate = P.taxRate or Config.TaxRate or 0
    return math.floor((price or 0) * (1 + taxRate) + 0.5)
end

-- the tattoo of shared/tattoos.lua that a purchase names, nil when there is none
local function findTattoo(zone, name)
    local list = type(zone) == "string" and Config.Tattoos[zone]
    if not list or type(name) ~= "string" then return nil end
    for i = 1, #list do
        if list[i].name == name then return list[i] end
    end
    return nil
end

local function priceOf(kind, tattoo, remove)
    if kind == "hair" then
        return total(P.hairPrice)
    elseif remove then
        return total(P.removePrice or 0)
    end
    return total(tattoo and tattoo.cost or P.tattooPrice)
end

-- can the player pay that, from the pocket or the bank (nil where the framework cannot be asked)
local function canAfford(src, amount)
    if amount <= 0 then return true end
    local ok, can = pcall(function()
        return Framework.HasMoney(src, "cash", amount) or Framework.HasMoney(src, "bank", amount)
    end)
    if not ok then return nil end
    return can and true or false
end

-- is the player at a store of the kind (a barber for hair, a tattoo parlour for a tattoo)?
local function isAtStore(src, storeIndex, kind)
    local store = type(storeIndex) == "number" and Config.Stores[storeIndex]
    if not store or store.type ~= StoreType[kind] then return false end
    if not knowsPositions then return true end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - store.coords.xyz) <= P.purchaseRange
end

lib.callback.register("illenium-appearance:server:parlourOpen", function(source, storeIndex, kind)
    if not StoreType[kind] then return nil end
    local price = priceOf(kind)
    return {
        afford = canAfford(source, price),
        price = price
    }
end)

lib.callback.register("illenium-appearance:server:parlourPurchase", function(source, storeIndex, kind, what)
    local src = source
    if not StoreType[kind] or not isAtStore(src, storeIndex, kind) then
        return { ok = false, reason = "tooFar" }
    end

    local tattoo, remove = nil, false
    if kind == "tattoo" then
        tattoo = type(what) == "table" and findTattoo(what.zone, what.name)
        if not tattoo then
            return { ok = false, reason = "failed" }
        end
        remove = what.remove == true
    end

    -- (one purchase at a time: Enter held down is not a spree)
    local now = GetGameTimer()
    if lastPurchase[src] and now - lastPurchase[src] < 500 then
        return { ok = false, reason = "failed" }
    end
    lastPurchase[src] = now

    -- cash first, then the bank
    local amount = priceOf(kind, tattoo, remove)
    local ok, paid = pcall(function()
        if amount <= 0 then
            return "free"
        elseif Framework.HasMoney(src, "cash", amount) and Framework.RemoveMoney(src, "cash", amount) then
            return "cash"
        elseif Framework.HasMoney(src, "bank", amount) and Framework.RemoveMoney(src, "bank", amount) then
            return "bank"
        end
    end)

    if not ok then
        return { ok = false, reason = "failed" }
    elseif not paid then
        return { ok = false, reason = "noMoney", afford = false }
    end

    return {
        ok = true,
        paid = paid,
        total = amount,
        afford = canAfford(src, priceOf(kind))
    }
end)

AddEventHandler("playerDropped", function()
    lastPurchase[source] = nil
end)
