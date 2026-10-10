ESX = nil
QBCore = nil
RegisterServerCallBack_ = {}
Initialized()
local freemenu = {} -- player > time they ran /freecustoms, good for the menu it opens and nothing after
local inshop = {} -- player > { net, props, admin } of the vehicle they have in the menu
Citizen.CreateThreadNow(function()
    Wait(1000)
    VehicleNames()
    -- parts inventory of each shop. Created here, so there is no SQL file to import first
    CustomsSQL(Config.Mysql,'execute','CREATE TABLE IF NOT EXISTS `renzu_customs` (`shop` VARCHAR(64) NOT NULL, `inventory` LONGTEXT NULL, PRIMARY KEY (`shop`))', {})
    for k,v in pairs(Config.Customs) do
        CustomsSQL(Config.Mysql,'execute',"INSERT IGNORE  INTO renzu_customs (shop, inventory) VALUES (@shop, '[]')", {
            ['@shop']   = k,
        })
    end
end)

RegisterServerCallBack_('renzu_customs:getinventory', function (source, cb, id, share)
    local source = source
    local xPlayer = GetPlayerFromId(source)
    local identifier = xPlayer.identifier
    if share then
        identifier = share.owner
    end
    local result = CustomsSQL(Config.Mysql,'fetchAll','SELECT inventory FROM renzu_customs WHERE shop = @shop', {
        ['@shop'] = id
    })
    local inventory = {}
    if result[1] and result[1].inventory ~= nil then
        inventory = json.decode(result[1].inventory) or {}
    end
    cb(inventory)
end)

RegisterServerCallBack_('renzu_customs:itemavailable', function (source, cb, id, item, share)
    local source = source
    local xPlayer = GetPlayerFromId(source)
    local identifier = xPlayer.identifier
    if share then
        identifier = share.owner
    end
    local result = CustomsSQL(Config.Mysql,'fetchAll','SELECT inventory FROM renzu_customs WHERE shop = @shop', {
        ['@shop'] = id
    })
    local inventory = false
    if json.decode(result[1].inventory) then
        inventory = json.decode(result[1].inventory) or {}
        if inventory[item] ~= nil and inventory[item] > 0 then
            inventory[item] = inventory[item] - 1
            CustomsSQL(Config.Mysql,'execute','UPDATE renzu_customs SET inventory = @inventory WHERE shop = @shop', {
                ['@inventory'] = json.encode(inventory),
                ['@shop'] = id,
            })
            cb(true)
        else
            cb(false)
        end
    else
        cb(false)
    end
end)

RegisterServerEvent('renzu_customs:storemod')
AddEventHandler('renzu_customs:storemod', function(id,mod,lvl,newprop,share,save,savepartsonly)
    local src = source  
    local xPlayer = GetPlayerFromId(src)
    local identifier = xPlayer.identifier
    if share then
        identifier = share.owner
    end
    local success = true
    local vehicles = nil
    local result = CustomsSQL(Config.Mysql,'fetchAll','SELECT inventory FROM renzu_customs WHERE shop = @shop', {
        ['@shop'] = id
    })
    local inventory = json.decode(result[1].inventory) or {}
    if not save then
        local modname = mod.name..'-'..lvl
        if inventory[modname] == nil then
            inventory[modname] = 1
        else
            inventory[modname] = inventory[modname] + 1
        end
    end
    CustomsSQL(Config.Mysql,'execute','UPDATE renzu_customs SET inventory = @inventory WHERE shop = @shop', {
        ['@inventory'] = json.encode(inventory),
        ['@shop'] = id,
    })
    TriggerClientEvent('renzu_notify:Notify', src, 'success','Garage', 'You Successfully store the parts ('..mod.name..')')
end)

-- SOCIETY / JOB MONEY

local function qbAccounts()
    if GetResourceState('Renewed-Banking') == 'started' then
        return function(job) return exports['Renewed-Banking']:getAccountMoney(job) end,
            function(job, amount) exports['Renewed-Banking']:addAccountMoney(job, amount) end,
            function(job, amount) exports['Renewed-Banking']:removeAccountMoney(job, amount) end
    elseif GetResourceState('qb-banking') == 'started' then
        return function(job) return exports['qb-banking']:GetAccountBalance(job) end,
            function(job, amount) exports['qb-banking']:AddMoney(job, amount, 'customs') end,
            function(job, amount) exports['qb-banking']:RemoveMoney(job, amount, 'customs') end
    end
    return function(job) return exports['qb-management']:GetAccount(job) end,
        function(job, amount) exports['qb-management']:AddMoney(job, amount) end,
        function(job, amount) exports['qb-management']:RemoveMoney(job, amount) end
end

-- Money in a job account, or nil when the server has no account for it
function Jobmoney(job,xPlayer)
    local value = -1
    local count = 0
    if Config.UseRenzu_jobs then
        value = exports.renzu_jobs:JobMoney(job).money
    elseif Config.framework == 'ESX' then
        TriggerEvent('esx_addonaccount:getSharedAccount', 'society_'..job, function(account)
            if account then value = account.money end
        end)
        while value == -1 and count < 50 do count = count + 1 Wait(0) end
    else
        local balance = qbAccounts()
        local ok, result = pcall(balance, job)
        if ok then value = result end
    end
    value = tonumber(value)
    if not value or value < 0 then return nil end
    return value
end

Society = function(job,amount,method,src)
    if Config.UseRenzu_jobs then
        if method == 'remove' then
            exports.renzu_jobs:removeMoney(amount,job,src,'money',true)
        else
            exports.renzu_jobs:addMoney(amount,job,src,'money',true)
        end
    elseif Config.framework == 'ESX' then
        TriggerEvent('esx_addonaccount:getSharedAccount', 'society_'..job, function(account)
            if account and method == 'remove' then
                account.removeMoney(amount)
            elseif account then
                account.addMoney(amount)
            end
        end)
    else
        local _, add, remove = qbAccounts()
        pcall(method == 'remove' and remove or add, job, amount)
    end
end

-- OWNED VEHICLES

local function VehicleRow(plate)
    local result = CustomsSQL(Config.Mysql,'fetchAll','SELECT * FROM '..vehicletable..' WHERE UPPER(plate) = @plate', {
        ['@plate'] = tostring(plate):upper()
    })
    return result and result[1]
end

local function SavedProps(row)
    local ok, saved = pcall(json.decode, row and row[vehiclemod] or '{}')
    return ok and type(saved) == 'table' and saved or {}
end

-- Same lookup the client does in GetVehicleValue, for Config.VehicleValuetoFormula
local function VehicleValue(model)
    if not Config.VehicleValuetoFormula or not model then return 0 end
    model = model & 0xFFFFFFFF
    for k,v in pairs(Config.VehicleValueList) do
        if GetHashKey(v.model) & 0xFFFFFFFF == model then return (tonumber(v.value) or 0) * Config.VehicleValuePercent end
    end
    for k,v in pairs(vehiclesname or {}) do
        if v.model and GetHashKey(v.model) & 0xFFFFFFFF == model then return (tonumber(v.price) or 0) * Config.VehicleValuePercent end
    end
    return 0
end

-- NITROUS (by plate, kept across restarts)

local customnitrous = json.decode(GetResourceKvpString('nitrous') or '{}') or {}

function SetVehicleNitrous(plate, kit)
    plate = Customs.PlateKey(plate)
    if kit == 'Default' then kit = nil end
    if kit and not (Config.VehicleMod['nitrous'] and Config.VehicleMod['nitrous'].list[kit]) then return false end
    customnitrous[plate] = kit
    SetResourceKvp('nitrous',json.encode(customnitrous))
    TriggerClientEvent('renzu_customs:nitrous',-1,false,plate,kit)
    return true
end

exports('SetVehicleNitrous', SetVehicleNitrous)

exports('GetVehicleNitrous', function(plate)
    return customnitrous[Customs.PlateKey(plate)] or 'Default'
end)

-- UPGRADE MENU

RegisterServerCallBack_('renzu_customs:getmoney', function (source, cb, net, props)
    local src = source
    local xPlayer = GetPlayerFromId(src)
    if not xPlayer or type(props) ~= 'table' then cb(false) return end
    local row = VehicleRow(props.plate)
    props.pro_build = SavedProps(row).pro_build
    local admin = freemenu[src] ~= nil and os.time() - freemenu[src] <= 5
    freemenu[src] = nil
    inshop[src] = {net = net , props = props, admin = admin}
    local info = {}
    info.owned = row ~= nil
    info.kit = props.pro_build
    info.admin = admin
    cb(info)
end)

-- The basket is not sent by the client: it is worked out here from the props the vehicle
-- came in with and the props it leaves with, using the same code the menu shows prices with.
RegisterServerCallBack_('renzu_customs:pay', function (source, cb, data)
    local src = source
    local xPlayer = GetPlayerFromId(src)
    local sess = inshop[src]
    local function fail(message)
        cb({ok = false, message = message})
    end
    if not xPlayer or not sess or type(data) ~= 'table' or type(data.prop) ~= 'table' then
        fail('Your session expired, open the menu again.') return
    end
    local prop = data.prop
    if Customs.PlateKey(prop.plate) ~= Customs.PlateKey(sess.props.plate) or prop.model ~= sess.props.model then
        fail('That is not the vehicle you came in with.') return
    end
    local admin = sess.admin == true
    local shop = Config.Customs[data.shop] and data.shop or nil
    local job = xPlayer.job and xPlayer.job.name
    local staff = shop ~= nil and Config.Customs[shop].job == job
    if not admin and (not shop or Config.JobPermissionAll and not staff) then
        fail('Only shop staff can fit upgrades here.') return
    end
    local model = prop.model
    local entity = sess.net and NetworkGetEntityFromNetworkId(sess.net)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        model = GetEntityModel(entity)
    end
    local ctx = {
        job = job,
        vehicleValue = VehicleValue(tonumber(model)),
        free = admin or Config.FreeUpgradeToClass[tonumber(data.class)] == true,
    }
    local old, new = Customs.StateFromProps(sess.props), Customs.StateFromProps(prop)
    local items, total = Customs.Cart(old, new, ctx)
    if not items then
        fail('Something in your basket is not sold here.') return
    end
    local row = VehicleRow(prop.plate)
    if not row and Config.OwnedVehiclesOnly and not admin then
        fail('Only owned vehicles can be upgraded here.') return
    end
    if total > 0 then
        local paid = false
        if Config.JobPermissionAll then -- staff only shop, the parts come out of the shop account
            local funds = Jobmoney(job,xPlayer)
            if funds then
                if funds < total then
                    fail('The shop account cannot cover $'..total..'.') return
                end
                Society(job,total,'remove',src)
                paid = true
            end
        end
        if not paid then
            if not ChargePlayer(xPlayer,total) then
                fail('Not enough money, $'..total..' required.') return
            end
            if shop and Config.Customs[shop].job and not Config.JobPermissionAll then
                Society(Config.Customs[shop].job,total,'add',src)
            end
        end
    end
    if row then
        -- keep whatever other resources store in the same column
        local saved = SavedProps(row)
        for k,v in pairs(prop) do saved[k] = v end
        saved.pro_build = prop.pro_build
        CustomsSQL(Config.Mysql,'execute','UPDATE '..vehicletable..' SET `'..vehiclemod..'` = @'..vehiclemod..' WHERE UPPER(plate) = @plate', {
            ['@'..vehiclemod..''] = json.encode(saved),
            ['@plate'] = tostring(prop.plate):upper()
        })
    end
    if old['nitrous'] ~= new['nitrous'] then
        SetVehicleNitrous(prop.plate,new['nitrous'])
    end
    sess.props = prop
    cb({ok = true, total = total})
end)

RegisterServerCallBack_('renzu_customs:repair', function (source, cb, shop)
    local src = source
    local xPlayer = GetPlayerFromId(src)
    if not xPlayer then cb(false) return end
    local owner = Config.Customs[shop] and Config.Customs[shop].job
    local free = inshop[src] ~= nil and inshop[src].admin == true or owner ~= nil and xPlayer.job ~= nil and owner == xPlayer.job.name -- job permission access is free repair
    if not free then
        if not ChargePlayer(xPlayer,Config.RepairCost) then cb(false) return end
        if owner then Society(owner,Config.RepairCost,'add',src) end
    end
    cb(true)
end)

RegisterServerEvent('playerDropped')
AddEventHandler('playerDropped', function(reason)
	for k,v in pairs(inshop) do
        if tonumber(source) == tonumber(k) then
            TriggerClientEvent('renzu_customs:restoremod',-1 , v.net, v.props)
            --DeleteEntity(v)
        end
    end
    inshop[source] = nil
    freemenu[source] = nil
end)

RegisterServerEvent('renzu_customs:leaveshop')
AddEventHandler('renzu_customs:leaveshop', function()
	inshop[source] = nil
	freemenu[source] = nil
end)

function GetVehicleNetWorkIdByPlate(plate,source,dist)
    local source = source
    for k,v in ipairs(GetAllVehicles()) do
        if GetVehicleNumberPlateText(v) == plate and #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(v)) < 5 then -- support only near vehicle , means spawn and teleport the ped to vehicle seat
            return NetworkGetNetworkIdFromEntity(v)
        end
    end
    for k,v in ipairs(GetAllVehicles()) do
        if GetVehicleNumberPlateText(v) == plate then -- no range restriction if above loop does not find (but this does not support multiple duplicated plates in area)
            return NetworkGetNetworkIdFromEntity(v)
        end
    end
    return -1
end

RegisterServerEvent('renzu_customs:syncdel')
AddEventHandler('renzu_customs:syncdel', function(net)
    local source = source
    local entity = NetworkGetEntityFromNetworkId(net)
    if DoesEntityExist(entity) then
        DeleteEntity(entity)
    end
end)

local customengine = {}
RegisterServerEvent('renzu_customs:custom_engine')
AddEventHandler('renzu_customs:custom_engine', function(netid,plate,model)
    customengine[plate] = model
    local source = source
    if model == 'Default' then customengine[plate] = nil end
    Wait(1500) -- added wait for other garage script compatibility (setprop before ped is in vehicle)
    TriggerClientEvent('renzu_customs:receivenetworkid',-1,GetVehicleNetWorkIdByPlate(plate,source),model)
    SetResourceKvp('engine',json.encode(customengine))
end)

local customturbo = {}
RegisterServerEvent('renzu_customs:custom_turbo')
AddEventHandler('renzu_customs:custom_turbo', function(plate,turbo)
    customturbo[plate] = turbo
    if turbo == 'Default' then customturbo[plate] = nil end
    TriggerClientEvent('renzu_customs:receiveturboupgrade',-1,customturbo)
    SetResourceKvp('turbo',json.encode(customturbo))
end)

local customtire = {}
RegisterServerEvent('renzu_customs:custom_tire')
AddEventHandler('renzu_customs:custom_tire', function(plate,tire)
    customtire[plate] = tire
    local source = source
    if tire == 'Default' then customtire[plate] = nil end
    Wait(1500) -- added wait for other garage script compatibility (setprop before ped is in vehicle)
    TriggerClientEvent('renzu_customs:custom_tire',-1,customtire,GetVehicleNetWorkIdByPlate(plate,source),tire)
    SetResourceKvp('tire',json.encode(customtire))
end)

RegisterServerEvent('renzu_customs:soundsync')
AddEventHandler('renzu_customs:soundsync', function(table)
    TriggerClientEvent('renzu_customs:soundsync',-1,table)
end)

RegisterServerEvent('renzu_customs:loaded')
AddEventHandler('renzu_customs:loaded', function()
    local source = source
    TriggerClientEvent('renzu_customs:receivedata',source,customturbo,customengine,vehiclesname)
    TriggerClientEvent('renzu_customs:nitrous',source,customnitrous)
end)

RegisterCommand('freecustoms', function (source, args)
    local source = tonumber(source)
    local xPlayer = GetPlayerFromId(source)
    local playerGroup = xPlayer.getGroup(source)
    if Config.framework == 'ESX' and playerGroup == "superadmin" or playerGroup == "mod" or playerGroup == "admin" or Config.framework == 'QBCORE' and playerGroup then
        freemenu[source] = os.time()
        TriggerClientEvent('renzu_customs:openmenu',source, true)
    end
end)