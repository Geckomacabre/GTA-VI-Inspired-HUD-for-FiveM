-- Makes the item in Config.Item usable on Qbox / QBCore. ox_inventory does
-- not go through here: there the item's own definition names the client
-- export to call (see README.md).
local item = Config.Item
if not item or item == '' then return end

CreateThread(function()
    Wait(1000) -- after the framework has finished starting
    local function raise(source)
        TriggerClientEvent('vi_binoculars:use', source)
    end

    if GetResourceState('qbx_core') == 'started' then
        exports.qbx_core:CreateUseableItem(item, raise)
    elseif GetResourceState('qb-core') == 'started' then
        local ok, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
        if ok and core and core.Functions then core.Functions.CreateUseableItem(item, raise) end
    end
end)
