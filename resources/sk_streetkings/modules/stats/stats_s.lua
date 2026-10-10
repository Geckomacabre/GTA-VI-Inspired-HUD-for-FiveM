-- Career stat tracking, ported from streetkings modules/stats/stats_s.lua.
--
-- Same keys and same anti-spam clamps; storage moved from StreetKings' save
-- slots to the shared profile document. Every writer goes through here rather
-- than touching SKSaves directly, so an unknown key can never create junk
-- fields on the document.

SKStats = {}

local MAX_MILES_PER_SYNC = 5.0
local MAX_TOP_SPEED_MPH  = 350.0
local SYNC_COOLDOWN_MS   = 25000

local lastSync = {}

-- Built from the defaults so a new stat only has to be added in one place.
local VALID_KEYS = {}
for key in pairs(SKSaves.defaultStats()) do VALID_KEYS[key] = true end

---@param src integer
---@param key string
---@param amount number
function SKStats.increment(src, key, amount)
    if not VALID_KEYS[key] then return end
    if not SKSaves.hasActiveSave(src) then return end

    local stats = SKSaves.read(src, 'stats') or SKSaves.defaultStats()
    stats[key] = (stats[key] or 0) + (amount or 1)
    SKSaves.write(src, 'stats', stats)
end

---@param src integer
---@param key string
---@param value number
function SKStats.setMax(src, key, value)
    if not VALID_KEYS[key] then return end
    if not SKSaves.hasActiveSave(src) then return end

    local stats = SKSaves.read(src, 'stats') or SKSaves.defaultStats()
    if value > (stats[key] or 0) then
        stats[key] = value
        SKSaves.write(src, 'stats', stats)
    end
end

--- Unconditional set, e.g. resetting a streak counter back to zero.
---@param src integer
---@param key string
---@param value number
function SKStats.setValue(src, key, value)
    if not VALID_KEYS[key] then return end
    if not SKSaves.hasActiveSave(src) then return end

    local stats = SKSaves.read(src, 'stats') or SKSaves.defaultStats()
    stats[key] = value
    SKSaves.write(src, 'stats', stats)
end

---@param src integer
---@param miles number
function SKStats.addMiles(src, miles)
    SKStats.increment(src, 'totalMilesDriven', miles)
end

if not Config.Modules.stats then return end

-- Client reports distance travelled and top speed periodically. Both are
-- clamped and rate-limited, since a client can send anything.
RegisterNetEvent('sk_streetkings:stats:sync', function(miles, topSpeedMph)
    local src = source
    local now = GetGameTimer()

    if lastSync[src] and now - lastSync[src] < SYNC_COOLDOWN_MS then return end
    lastSync[src] = now

    miles = tonumber(miles) or 0
    if miles > 0 then
        SKStats.addMiles(src, math.min(miles, MAX_MILES_PER_SYNC))
    end

    topSpeedMph = tonumber(topSpeedMph) or 0
    if topSpeedMph > 0 then
        SKStats.setMax(src, 'topSpeedMph', math.min(topSpeedMph, MAX_TOP_SPEED_MPH))
    end
end)

lib.callback.register('sk_streetkings:stats:get', function(source)
    if not SKSaves.hasActiveSave(source) then return nil end
    return {
        stats = SKSaves.read(source, 'stats') or SKSaves.defaultStats(),
        level = SKSaves.read(source, 'progression.level') or 0,
        xp    = SKSaves.read(source, 'progression.playerXp') or 0,
    }
end)

AddEventHandler('playerDropped', function()
    lastSync[source] = nil
end)
