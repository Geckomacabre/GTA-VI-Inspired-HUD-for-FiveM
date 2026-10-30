--[[ ===========================================================================
     vi_storemoney — client
     ---------------------------------------------------------------------------
     MONEY IN STORES, ported from the fork's ViExtras (single player's
     [Switches] MoneyInStores, Core\StoreMoney.cs). In GTA VI your money is on
     screen from the moment you walk into a store until you walk out, not only
     with a shop's menu open.

     A store is where this server sells things, as single player's is where
     GTA6Hud does:
       - an ox_inventory shop anyone can use (a 24/7's till, an Ammu-Nation
         counter, a liquor store...): its locations and targets;
       - an illenium-appearance clothes store (each of its racks, and the
         store's own spot) or barber's;
     with you indoors and on foot, within 12 m across and 4 m up or down of
     one of those points (single player's reach from its racks and tills).

     vice_hud draws the money. While you're in a store its cash and bank rows
     are held up through its SetMoneyShown export, the way it holds them up
     with the item wheel open; with a shop's menu open it shows them already.

     Public API: none. The MONEY IN STORES row of HUD OPTIONS switches it per
     player.
     ========================================================================= ]]

local options = require 'vi_hudoptions.options'
local config = require 'vi_storemoney.config'
if not config.enabled then return end

-- Single player's numbers.
local REACH, REACH_Z = 12.0, 4.0        -- metres from a store's point, across and up or down
local CHECK_MS = 400
local IDLE_MS = 1000                    -- while the row is off
local SETTLE_MS = 3000                  -- after a loading screen or a switch

local SHOPS, LOOKS, HUD = 'ox_inventory', 'illenium-appearance', 'vice_hud'
local LOOK_STORES = { clothing = true, barber = true }     -- not its tattoo parlours: single player's racks and chairs
local SOURCE = GetCurrentResourceName() .. ':storemoney'    -- this hold, among vice_hud's others

local spots = {}
local dirty = true                      -- the store list is read again before the next check
local held = false
local readySince = nil
local lastError = nil

local function report(err)
    err = tostring(err)
    if err == lastError then return end
    lastError = err
    print(('^1[vi_extras]^7 storemoney: %s'):format(err))
end

-- Not on a loading screen or mid character switch, and settled a moment.
local function ready()
    local ok = not GetIsLoadingScreenActive() and DoesEntityExist(cache.ped) and not IsPlayerSwitchInProgress()
    if not ok then
        readySince = nil
        return false
    end
    local now = GetGameTimer()
    readySince = readySince or now
    return now - readySince >= SETTLE_MS
end

local function add(list, p)
    local t = type(p)
    if t == 'vector3' or t == 'vector4' or (t == 'table' and tonumber(p.x) and tonumber(p.y) and tonumber(p.z)) then
        list[#list + 1] = vector3(p.x + 0.0, p.y + 0.0, p.z + 0.0)
    end
end

-- One of another resource's data files, run in a table of its own so the
-- globals it sets (illenium-appearance's Config) stay out of this resource.
local function loadData(resource, file, env)
    if GetResourceState(resource) ~= 'started' then return nil end
    env = env or setmetatable({}, { __index = _G })
    local ok, result = pcall(lib.load, ('@%s.%s'):format(resource, file), env)
    if not ok then
        report(('%s %s could not be read: %s'):format(resource, file, result))
        return nil
    end
    return result, env
end

local function collect()
    local list = {}

    local shops = loadData(SHOPS, 'data.shops')
    if type(shops) == 'table' then
        for _, shop in pairs(shops) do
            -- a job's or gang's armoury, or a vending machine, is not a store
            if type(shop) == 'table' and not shop.groups and not shop.jobs and not shop.model then
                for _, at in pairs(shop.locations or {}) do add(list, at) end
                for _, target in pairs(shop.targets or {}) do
                    if type(target) == 'table' then add(list, target.loc or target.coords) end
                end
            end
        end
    end

    local _, env = loadData(LOOKS, 'shared.config')
    if env then loadData(LOOKS, 'shared.racks', env) end
    local looks = env and rawget(env, 'Config')
    if type(looks) == 'table' then
        for _, store in pairs(looks.Stores or {}) do
            if type(store) == 'table' and LOOK_STORES[store.type] then
                add(list, store.coords)
                for _, at in pairs(store.points or {}) do add(list, at) end
            end
        end
        for _, racks in pairs(looks.RackSpots or {}) do
            for _, rack in pairs(racks) do
                if type(rack) == 'table' then add(list, rack.coords) end
            end
        end
    end

    return list
end

local function inStore()
    local ped = cache.ped
    if not ped or cache.vehicle or not DoesEntityExist(ped) then return false end
    if GetInteriorFromEntity(ped) == 0 then return false end
    local at = GetEntityCoords(ped)
    local x, y, z = at.x, at.y, at.z
    for i = 1, #spots do
        local s = spots[i]
        if math.abs(s.x - x) < REACH and math.abs(s.y - y) < REACH and math.abs(s.z - z) < REACH_Z then
            return true
        end
    end
    return false
end

-- vice_hud keeps the rows up while any hold is in, so this one says only
-- when it starts and stops (and again if vice_hud restarts).
local function tellHud()
    if GetResourceState(HUD) ~= 'started' then return end
    local ok, err = pcall(function() exports[HUD]:SetMoneyShown(held, SOURCE) end)
    if not ok then report(err) end
end

local function hold(on)
    if on == held then return end
    held = on
    tellHud()
end

options.add({
    id = 'storemoney',
    label = 'MONEY IN STORES',
    default = config.default ~= false,
    desc = "The money at the top right the whole time you're in a store, as in GTA VI.",
    onChange = function(on)
        if not on then hold(false) end  -- on: the next check puts it up
    end,
})

CreateThread(function()
    while true do
        local wait = CHECK_MS
        local ok, err = pcall(function()
            if not options.get('storemoney') then
                hold(false)
                wait = IDLE_MS
                return
            end
            if not ready() then
                hold(false)
                return
            end
            if dirty then
                dirty = false
                spots = collect()
            end
            hold(inStore())
        end)
        if not ok then report(err) end
        Wait(wait)
    end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == SHOPS or res == LOOKS then
        dirty = true
    elseif res == HUD and held then
        tellHud()       -- a restarted vice_hud starts with no holds
    end
end)

AddEventHandler('onClientResourceStop', function(res)
    if res == SHOPS or res == LOOKS then dirty = true end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and held then
        held = false
        tellHud()
    end
end)
