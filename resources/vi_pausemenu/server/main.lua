--[[
    The pause menu's server side: the list of players for its Players screen, reports to staff, and disconnecting
    (gk_pausemenu's, renamed).
]]

local function Players()
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        list[#list + 1] = { id = tonumber(id), name = GetPlayerName(id) }
    end
    return list
end

-- the menu's title: server.cfg's sv_projectName (else sv_hostname), without FiveM's ^colour codes
local function ServerName()
    local name = GetConvar('sv_projectName', '')
    if name == '' then name = GetConvar('sv_hostname', '') end
    name = name:gsub('%^%d', '')
    return (name:match('^%s*(.-)%s*$'))
end

RegisterNetEvent('vi_pausemenu:server:requestPlayers', function()
    TriggerClientEvent('vi_pausemenu:client:setPlayers', source, Players(), ServerName())
end)

AddEventHandler('playerJoining', function()
    TriggerClientEvent('vi_pausemenu:client:setPlayers', -1, Players(), ServerName())
end)

AddEventHandler('playerDropped', function()
    -- (one tick on: on some builds the leaver is still in GetPlayers() here)
    SetTimeout(0, function()
        TriggerClientEvent('vi_pausemenu:client:setPlayers', -1, Players(), ServerName())
    end)
end)

-- a report from the Report screen: to Config.Report.Webhook, or the console when that is empty
local lastReport = {}
RegisterNetEvent('vi_pausemenu:server:report', function(category, subject, text)
    local src = source
    if type(subject) ~= 'string' or type(text) ~= 'string' then return end
    category = type(category) == 'string' and category:sub(1, 32) or 'Other'
    subject, text = subject:sub(1, 120), text:sub(1, 1500)

    -- one a minute each
    local now = os.time()
    if lastReport[src] and now - lastReport[src] < 60 then return end
    lastReport[src] = now

    local who = ('%s (id %s)'):format(GetPlayerName(src) or '?', src)
    if (Config.Report.Webhook or '') == '' then
        print(('[vi_pausemenu] report from %s [%s] %s: %s'):format(who, category, subject, text))
        return
    end

    PerformHttpRequest(Config.Report.Webhook, function() end, 'POST', json.encode({
        username = Config.Report.WebhookName,
        embeds = {
            {
                title = ('[%s] %s'):format(category, subject),
                description = text,
                color = 0xF06A9E,
                footer = { text = who },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            },
        },
    }), { ['Content-Type'] = 'application/json' })
end)

AddEventHandler('playerDropped', function()
    lastReport[source] = nil
end)

-- Disconnect, asked for by the player themself (the page confirms first): `source` is always whoever chose it
RegisterNetEvent('vi_pausemenu:server:disconnect', function()
    DropPlayer(source, 'You left the server.')
end)
