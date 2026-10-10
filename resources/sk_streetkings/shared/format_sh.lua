-- Formatting shared by client HUDs/menus and server notifications, so a time or
-- a payout reads identically wherever it is shown.

--- ms -> "m:ss.mmm", the format used on every leaderboard and race readout.
---@param ms integer
---@return string
function SKFormatTime(ms)
    if not ms or ms < 0 then return '--:--.---' end
    local totalSeconds = ms / 1000
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    return ('%d:%06.3f'):format(minutes, seconds)
end

---@param n integer
---@return string
function SKFormatMoney(n)
    local formatted = tostring(math.floor(n or 0))
    local k
    repeat
        formatted, k = formatted:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
    until k == 0
    return '$' .. formatted
end
