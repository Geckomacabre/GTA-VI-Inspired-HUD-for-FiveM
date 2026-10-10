-- Qbox player bridge.
--
-- StreetKings ran its own economy and identity out of modules/storage. On Qbox
-- both belong to qbx_core, so every ported module goes through this shim rather
-- than touching SKSaves.economy (which no longer exists).

SKPlayer = {}

---@param src integer
---@return table|nil
function SKPlayer.get(src)
    return exports.qbx_core:GetPlayer(src)
end

---@param src integer
---@return string|nil
function SKPlayer.citizenid(src)
    local player = SKPlayer.get(src)
    return player and player.PlayerData.citizenid or nil
end

--- Display name used on leaderboards.
---@param src integer
---@return string
function SKPlayer.alias(src)
    local player = SKPlayer.get(src)
    if not player then return GetPlayerName(src) or 'Unknown' end
    local charinfo = player.PlayerData.charinfo
    if charinfo and charinfo.firstname then
        return ('%s %s'):format(charinfo.firstname, charinfo.lastname or '')
    end
    return GetPlayerName(src) or 'Unknown'
end

---@param src integer
---@param amount integer
---@param reason string
---@param account? string defaults to Config.MoneyAccount
---@return boolean
function SKPlayer.addMoney(src, amount, reason, account)
    if amount <= 0 then return false end
    return exports.qbx_core:AddMoney(src, account or Config.MoneyAccount, math.floor(amount), reason) and true or false
end

---@param src integer
---@param amount integer
---@param reason string
---@param account? string defaults to Config.MoneyAccount
---@return boolean
function SKPlayer.removeMoney(src, amount, reason, account)
    if amount <= 0 then return true end
    return exports.qbx_core:RemoveMoney(src, account or Config.MoneyAccount, math.floor(amount), reason) and true or false
end

---@param src integer
---@return integer
function SKPlayer.getMoney(src)
    local player = SKPlayer.get(src)
    if not player then return 0 end
    return player.PlayerData.money[Config.MoneyAccount] or 0
end

---@param src integer
---@param title string
---@param description string|nil
---@param ntype string|nil
function SKPlayer.notify(src, title, description, ntype)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = title,
        description = description,
        type        = ntype or 'inform',
        duration    = 6000,
    })
end

local ADMIN_GROUPS = { admin = true, god = true, superadmin = true }

---@param src integer
---@return boolean
function SKPlayer.isAdmin(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, 'command') then return true end
    local player = SKPlayer.get(src)
    return player ~= nil and ADMIN_GROUPS[player.PlayerData.group] == true
end
