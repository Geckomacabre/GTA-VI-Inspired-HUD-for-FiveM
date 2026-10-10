-- Scheduled recurring "Meet Night" window, ported from the meet_night resource.
--
-- Now that racing lives in the same resource, the payout multiplier is read
-- through SKMeetNight.getMultiplier() directly instead of the old
-- exports.meet_night:GetMultiplier() cross-resource call guarded by
-- GetResourceState. The exports are kept so anything else on the server that
-- was already calling them keeps working.

SKMeetNight = {}

local active = false

if not Config.Modules.meetNight then
    -- Racing still calls getMultiplier() unconditionally; keep it well-defined.
    function SKMeetNight.getMultiplier() return 1.0 end
    function SKMeetNight.isActive() return false end
    return
end

local MN = Config.MeetNight

local function isWithinWindow()
    local t = os.date('*t')
    if t.wday ~= MN.DayOfWeek then return false end
    -- Simple same-day window (StartHour < EndHour); doesn't handle midnight wrap.
    return t.hour >= MN.StartHour and t.hour < MN.EndHour
end

local function broadcast(message)
    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'Meet Night', description = message, type = 'inform', duration = 10000, position = 'top',
    })
    TriggerClientEvent('chat:addMessage', -1, { args = { '^3[Meet Night]', message } })
end

local function setActive(value)
    if active == value then return end
    active = value
    GlobalState.meetNightActive = active

    if active then
        broadcast(MN.AnnounceStart:format(MN.Multiplier, MN.EndHour))
    else
        broadcast(MN.AnnounceEnd)
    end
end

---@return boolean
function SKMeetNight.isActive()
    return active
end

--- Config.MeetNight.Multiplier while active, 1.0 otherwise, so callers can
--- multiply payouts unconditionally.
---@return number
function SKMeetNight.getMultiplier()
    return active and MN.Multiplier or 1.0
end

CreateThread(function()
    while true do
        setActive(isWithinWindow())
        Wait(MN.PollIntervalMs)
    end
end)

exports('IsActive', SKMeetNight.isActive)
exports('GetMultiplier', SKMeetNight.getMultiplier)
