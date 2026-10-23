local QBCore = exports['qb-core']:GetCoreObject()

-- ─── App Registration ────────────────────────────────────────────────────────

local function RegisterApp()
    local res = GetCurrentResourceName()
    exports['lb-phone']:AddCustomApp({
        identifier  = Config.AppIdentifier,
        name        = Config.AppName,
        description = Config.AppDescription,
        developer   = 'Peekhole Inc.',

        icon = 'nui://' .. res .. '/ui/icon.svg',
        ui   = res .. '/ui/index.html',

        -- Screenshots shown on the app store listing page
        images = {
            'nui://' .. res .. '/ui/screenshots/screen_feed.svg',
            'nui://' .. res .. '/ui/screenshots/screen_discover.svg',
            'nui://' .. res .. '/ui/screenshots/screen_studio.svg',
        },

        price = 0,     -- free to download from the store
        size  = 512,   -- displayed size in KB

        -- defaultApp is intentionally NOT set to true.
        -- Omitting it means the app appears in the App Store and players
        -- must tap Download before it appears on their home screen.
    })
end

CreateThread(function()
    while GetResourceState('lb-phone') ~= 'started' do
        Wait(500)
    end
    RegisterApp()
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == 'lb-phone' then
        Wait(100)
        RegisterApp()
    end
end)

-- ─── NUI Callbacks ───────────────────────────────────────────────────────────

-- Called on app boot instead of a login screen.
-- Returns the player's GTA character identity so the UI knows who they are.
RegisterNUICallback('peekhole:getPlayerData', function(_, cb)
    local PlayerData = QBCore.Functions.GetPlayerData()
    cb({
        citizenid = PlayerData.citizenid,
        charName  = PlayerData.charinfo.firstname .. ' ' .. PlayerData.charinfo.lastname,
        phone     = PlayerData.charinfo.phone or '',
    })
end)

RegisterNUICallback('peekhole:getConfig', function(_, cb)
    cb({
        minSubPrice  = Config.MinSubPrice,
        maxSubPrice  = Config.MaxSubPrice,
        maxPostPrice = Config.MaxPostPrice,
        creatorCut   = Config.CreatorCut,
    })
end)

RegisterNUICallback('peekhole:getFeed', function(_, cb)
    QBCore.Functions.TriggerCallback('peekhole:getFeed', function(result)
        cb(result or {})
    end)
end)

RegisterNUICallback('peekhole:getCreators', function(_, cb)
    QBCore.Functions.TriggerCallback('peekhole:getCreators', function(result)
        cb(result or {})
    end)
end)

RegisterNUICallback('peekhole:getCreatorProfile', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:getCreatorProfile', function(result)
        cb(result or {})
    end, data.creatorId)
end)

RegisterNUICallback('peekhole:getMyProfile', function(_, cb)
    QBCore.Functions.TriggerCallback('peekhole:getMyProfile', function(result)
        cb(result or {})
    end)
end)

RegisterNUICallback('peekhole:subscribe', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:subscribe', function(result)
        cb(result or { success = false, message = 'No response from server.' })
    end, data.creatorId)
end)

RegisterNUICallback('peekhole:unlockPost', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:unlockPost', function(result)
        cb(result or { success = false, message = 'No response from server.' })
    end, data.postId)
end)

RegisterNUICallback('peekhole:createProfile', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:createProfile', function(result)
        cb(result or { success = false, message = 'No response from server.' })
    end, data)
end)

RegisterNUICallback('peekhole:updateProfile', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:updateProfile', function(result)
        cb(result or { success = false, message = 'No response from server.' })
    end, data)
end)

RegisterNUICallback('peekhole:createPost', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:createPost', function(result)
        cb(result or { success = false, message = 'No response from server.' })
    end, data)
end)

RegisterNUICallback('peekhole:deletePost', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:deletePost', function(result)
        cb(result or { success = false, message = 'No response from server.' })
    end, data.postId)
end)

-- ─── Login / Account ─────────────────────────────────────────────────────────

-- Returns all configured social apps with their enabled status
RegisterNUICallback('peekhole:getSocialApps', function(_, cb)
    local list = {}
    for key, cfg in pairs(Config.SocialApps or {}) do
        list[#list + 1] = {
            key     = key,
            label   = cfg.Label,
            color   = cfg.Color,
            enabled = cfg.Enabled,
        }
    end
    cb(list)
end)

RegisterNUICallback('peekhole:checkAccount', function(_, cb)
    QBCore.Functions.TriggerCallback('peekhole:checkAccount', function(result)
        cb(result or {})
    end)
end)

RegisterNUICallback('peekhole:loginWithApp', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:loginWithApp', function(result)
        cb(result or { success = false, message = 'No response from server.' })
    end, data.appKey)
end)

RegisterNUICallback('peekhole:createAccount', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:createAccount', function(result)
        cb(result or { success = false, message = 'No response from server.' })
    end, data)
end)

RegisterNUICallback('peekhole:logout', function(_, cb)
    QBCore.Functions.TriggerCallback('peekhole:logout', function(result)
        cb(result or { success = false })
    end)
end)

RegisterNUICallback('peekhole:toggleLike', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:toggleLike', function(result)
        cb(result or { success = false })
    end, data.postId)
end)

RegisterNUICallback('peekhole:getComments', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:getComments', function(result)
        cb(result or {})
    end, data.postId)
end)

RegisterNUICallback('peekhole:addComment', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:addComment', function(result)
        cb(result or { success = false })
    end, data)
end)

RegisterNUICallback('peekhole:getCreatorPhone', function(data, cb)
    QBCore.Functions.TriggerCallback('peekhole:getCreatorPhone', function(result)
        cb(result)
    end, data.creatorId)
end)

