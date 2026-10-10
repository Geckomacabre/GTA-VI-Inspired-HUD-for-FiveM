-- SKSaves shim.
--
-- StreetKings kept a full save-slot system (modules/storage/saves_s.lua) that
-- owned the player's identity, economy, garage, properties and mission state.
-- On Qbox all of that already has an owner:
--
--   economy    -> qbx_core money      (see SKPlayer)
--   garage     -> qbx_garages / night_garage_system
--   properties -> sn_properties
--   profile    -> qbx_core charinfo
--
-- So this keeps only the documents no other resource owns — progression, stats,
-- settings, unlocks and daily-event state — in one JSON row per citizenid. The
-- read/write dotted-path API is unchanged, so ported modules that call
-- SKSaves.read(src, 'stats') or SKSaves.write(src, 'progression.level', n)
-- work as written.

SKSaves = {}

local cache = {} -- src -> document
local dirty = {} -- src -> true

local AUTOSAVE_INTERVAL_MS = 120000

---@return table
function SKSaves.defaultStats()
    return {
        totalMilesDriven    = 0.0,
        topSpeedMph         = 0.0,
        totalCashEarned     = 0,
        totalCashSpent      = 0,
        racesCompleted      = 0,
        racesWon            = 0,
        npcChallengesWon    = 0,
        rampagesCompleted   = 0,
        stuntJumpsCompleted = 0,
        speedCameraFlashes  = 0,
        policeBusts         = 0,
        policeEscapes       = 0,
        totalRepairs        = 0,
        clothingPurchased   = 0,
        driftPointsTotal    = 0,
        bestDriftScore      = 0,
        racesLost           = 0,
        npcChallengesLost   = 0,
        bestRampageScore    = 0,
        currentWinStreak    = 0,
        bestWinStreak       = 0,
        goalTimesBeaten     = 0,
        betsWon             = 0,
    }
end

---@return table
local function defaultDocument()
    return {
        progression = {
            level               = 0,
            playerXp            = 0,
            bestActivityScores  = {},
        },
        stats    = SKSaves.defaultStats(),
        settings = {},
        unlocks  = {},
        events   = {
            dayKey          = '',
            claimedRewards  = {},
        },
    }
end

--- Fills in any keys added since the row was written.
---@param doc table
---@return table
local function migrate(doc)
    local defaults = defaultDocument()
    for section, defaultValue in pairs(defaults) do
        if type(doc[section]) ~= 'table' then
            doc[section] = defaultValue
        elseif type(defaultValue) == 'table' then
            for key, value in pairs(defaultValue) do
                if doc[section][key] == nil then doc[section][key] = value end
            end
        end
    end
    return doc
end

---@param src integer
---@return table|nil
local function load(src)
    local citizenid = SKPlayer.citizenid(src)
    if not citizenid then return nil end

    local row = MySQL.single.await('SELECT document FROM sk_profiles WHERE citizenid = ?', { citizenid })
    local doc
    if row and row.document then
        local ok, decoded = pcall(json.decode, row.document)
        doc = (ok and type(decoded) == 'table') and migrate(decoded) or defaultDocument()
    else
        doc = defaultDocument()
        MySQL.insert('INSERT INTO sk_profiles (citizenid, document) VALUES (?, ?)', { citizenid, json.encode(doc) })
    end

    cache[src] = doc
    return doc
end

---@param src integer
---@return boolean
function SKSaves.hasActiveSave(src)
    return cache[src] ~= nil or load(src) ~= nil
end

---@param src integer
---@return table|nil
function SKSaves.getDocument(src)
    return cache[src] or load(src)
end

--- Reads a dotted path, e.g. 'stats' or 'progression.level'.
---@param src integer
---@param key string
---@return any
function SKSaves.read(src, key)
    local doc = SKSaves.getDocument(src)
    if not doc then return nil end

    local node = doc
    for part in key:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[part]
    end
    return node
end

--- Writes a dotted path. Intermediate tables are created as needed.
---@param src integer
---@param key string
---@param value any
---@return boolean
function SKSaves.write(src, key, value)
    local doc = SKSaves.getDocument(src)
    if not doc then return false end

    local parts = {}
    for part in key:gmatch('[^%.]+') do parts[#parts + 1] = part end
    if #parts == 0 then return false end

    local node = doc
    for i = 1, #parts - 1 do
        local part = parts[i]
        if type(node[part]) ~= 'table' then node[part] = {} end
        node = node[part]
    end

    node[parts[#parts]] = value
    dirty[src] = true
    return true
end

---@param src integer
function SKSaves.persist(src)
    if not dirty[src] then return end
    local doc = cache[src]
    local citizenid = SKPlayer.citizenid(src)
    if not doc or not citizenid then return end

    dirty[src] = nil
    MySQL.update('UPDATE sk_profiles SET document = ? WHERE citizenid = ?', { json.encode(doc), citizenid })
end

---@param src integer
function SKSaves.clearActive(src)
    SKSaves.persist(src)
    cache[src] = nil
    dirty[src] = nil
end

AddEventHandler('playerDropped', function()
    SKSaves.clearActive(source)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for src in pairs(cache) do SKSaves.persist(src) end
end)

CreateThread(function()
    while true do
        Wait(AUTOSAVE_INTERVAL_MS)
        for src in pairs(dirty) do SKSaves.persist(src) end
    end
end)
