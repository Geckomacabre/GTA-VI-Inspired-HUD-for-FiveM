-- Speed camera fines.
--
-- Upstream had no server half for this — the client posted the trigger to the
-- daily-events system for a reward. That system is not ported and the flash
-- pays a fine here instead, so the charge has to be authoritative: the client
-- only says *which* camera fired, and everything else is looked up server-side.

if not Config.Modules.speedCameras then return end

-- Slightly under the client's 30s so a legitimate re-trigger is never rejected
-- for being marginally early.
local COOLDOWN_MS = 25000

local lastFlash = {} -- src -> { [camId] = timestamp }

-- Built server-side so a spoofed camera id can't produce a fine. Cameras placed
-- with em_toolkit are folded in the same way — the client only ever names a
-- camera, and the name/trigger speed used in the fine come from here.
local camerasById = {}

local function rebuildIndex()
    camerasById = {}

    for _, cam in ipairs(SKSpeedCameras or {}) do
        camerasById[cam.id] = cam
    end

    if Config.SpeedCameras.useToolkitCameras == false then return end

    local ok, extra = pcall(function()
        return exports['em_toolkit']:getSpeedCameras()
    end)
    if not ok or type(extra) ~= 'table' then return end

    for _, rec in ipairs(extra) do
        if rec.id then
            camerasById[rec.id] = {
                id              = rec.id,
                name            = rec.name or 'Speed Camera',
                triggerSpeedMph = rec.speed or 60,
            }
        end
    end
end

-- em_toolkit fires this after any change, including once on its own start, so
-- the two resources can come up in either order.
AddEventHandler('em_toolkit:speedCamerasChanged', rebuildIndex)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    rebuildIndex()
end)

--- Takes the fine from the configured account, falling back to the other one so
--- an empty bank isn't a free pass.
---@param src integer
---@param amount integer
---@return boolean paid, string account
local function collect(src, amount)
    local primary  = Config.SpeedCameras.fineAccount or Config.MoneyAccount
    local fallback = primary == 'cash' and 'bank' or 'cash'

    if SKPlayer.removeMoney(src, amount, 'sk-speed-camera', primary) then
        return true, primary
    end
    if SKPlayer.removeMoney(src, amount, 'sk-speed-camera', fallback) then
        return true, fallback
    end
    return false, primary
end

lib.callback.register('sk_streetkings:speedcameras:flash', function(source, camId, speedMph)
    local cam = camerasById[camId]
    if not cam then return nil end
    if not SKSaves.hasActiveSave(source) then return nil end

    local now = GetGameTimer()
    local seen = lastFlash[source]
    if not seen then
        seen = {}
        lastFlash[source] = seen
    end
    if seen[camId] and now - seen[camId] < COOLDOWN_MS then return nil end
    seen[camId] = now

    -- Reported speed is cosmetic (it only ever appears in the summary), but a
    -- client value still shouldn't reach a notification unclamped.
    speedMph = math.floor(math.max(cam.triggerSpeedMph, math.min(tonumber(speedMph) or 0, 400)))

    if Config.Modules.stats then
        SKStats.increment(source, 'speedCameraFlashes', 1)
    end

    local fine = Config.SpeedCameras.fine or 0
    if fine <= 0 then
        return { summary = ('%s — clocked at %d mph.'):format(cam.name, speedMph) }
    end

    local paid, account = collect(source, fine)
    if not paid then
        return {
            summary = ('%s — clocked at %d mph. %s fine could not be collected.')
                :format(cam.name, speedMph, SKFormatMoney(fine)),
        }
    end

    if Config.Modules.stats then
        SKStats.increment(source, 'totalCashSpent', fine)
    end

    return {
        summary = ('%s — clocked at %d mph. %s taken from your %s.')
            :format(cam.name, speedMph, SKFormatMoney(fine), account),
    }
end)

AddEventHandler('playerDropped', function()
    lastFlash[source] = nil
end)
