--[[ ===========================================================================
     vi_hudoptions — the rows of HUD OPTIONS, shared by every module
     ---------------------------------------------------------------------------
     Every module puts its own switch here, and HUD OPTIONS (hold V) and the
     pause menu's Settings page list them all:

         local options = require 'vi_hudoptions.options'
         local row = options.add({
             id = 'killcam',            -- also its KVP key, vi_extras:killcam
             label = 'KILL CAMERA',     -- as single player's HUD OPTIONS has it
             order = 40,                -- its place in the list (options.ORDER)
             default = true,            -- the module's config decides
             desc = 'A slow-motion shot of your last kill.',   -- for the pause menu
             -- values = { { v = 0, label = '0%' }, { v = 60, label = '60%' } },
             --          a row that steps through values instead of ON / OFF
             onChange = function(value) end,
         })
         if options.get('killcam') then ... end

     A row is saved per player (resource KVP) and comes back the next time
     they join. A row for a feature in another resource (vice_hud's crosshair,
     say) gives get and set instead and keeps nothing here: the resource that
     owns the feature keeps the setting, and the row shows only while that
     resource is started (needs = 'vice_hud').

     Copying a module into another resource: take its folder and this one.
     ========================================================================= ]]

local options = { rows = {} }

-- Where single player's HUD OPTIONS puts each row, top to bottom. A module's
-- row takes its number from here so the list reads the same on both, whatever
-- order the modules load in.
options.ORDER = {
    gunsonback = 10, drawanims = 20, chasemusic = 30, killcam = 40, crashcam = 50,
    mapdaynight = 60, mapvehicleonly = 70, searchcircle = 80, greet = 90, spinouts = 100,
    radiowheel = 110, policelights = 130, crosshair = 140, killmarks = 150,
    wantedstars = 160, wantedbox = 170, camweight = 180, binoculars = 190,
    calmerpolice = 200, storemoney = 210,
}

local function kvpKey(id) return 'vi_extras:' .. id end

local function load(row)
    local raw = GetResourceKvpString(kvpKey(row.id))
    if raw == nil then return row.default end
    if type(row.default) == 'boolean' then return raw == 'true' end
    if type(row.default) == 'number' then return tonumber(raw) or row.default end
    return raw
end

local function save(row, value)
    SetResourceKvp(kvpKey(row.id), tostring(value))
end

--- Adds a row and returns it. A row added twice (a module restarted) replaces
--- the first, keeping the saved value.
function options.add(row)
    assert(type(row.id) == 'string' and type(row.label) == 'string', 'a HUD OPTIONS row needs an id and a label')
    row.order = row.order or options.ORDER[row.id] or 1000
    if not row.get then row.value = load(row) end
    options.rows[row.id] = row
    if row.onChange and not row.get then
        -- the module starts on the player's saved choice
        local ok, err = pcall(row.onChange, row.value)
        if not ok then print(('^1[vi_extras]^7 %s: %s'):format(row.id, err)) end
    end
    return row
end

--- The row is there and its feature's resource is running.
function options.available(row)
    if type(row) == 'string' then row = options.rows[row] end
    if not row then return false end
    if row.needs and GetResourceState(row.needs) ~= 'started' then return false end
    if row.get then
        local ok, value = pcall(row.get)
        return ok and value ~= nil
    end
    return true
end

function options.get(id)
    local row = options.rows[id]
    if not row then return nil end
    if row.get then
        local ok, value = pcall(row.get)
        if ok then return value end
        return nil
    end
    return row.value
end

function options.set(id, value)
    local row = options.rows[id]
    if not row then return end
    if row.set then
        local ok, err = pcall(row.set, value)
        if not ok then print(('^1[vi_extras]^7 %s: %s'):format(id, err)) end
        return
    end
    row.value = value
    save(row, value)
    if row.onChange then
        local ok, err = pcall(row.onChange, value)
        if not ok then print(('^1[vi_extras]^7 %s: %s'):format(id, err)) end
    end
end

--- The next value (dir 1) or the one before (-1): ON / OFF flips, a list steps
--- round, from the last back to the first, as POLICE LIGHTS does in single player.
function options.step(id, dir)
    local row = options.rows[id]
    if not row then return end
    local now = options.get(id)
    if not row.values then
        options.set(id, not now)
        return
    end
    local back = dir and dir < 0
    local at
    for i, option in ipairs(row.values) do
        if option.v == now then at = i end
    end
    if not at and type(now) == 'number' then
        -- a value between the steps (set elsewhere, say vice_hud's editor):
        -- the next step up from it, or down going back, round at the ends
        for i, option in ipairs(row.values) do
            if back and option.v < now then at = i + 1 end
            if not back and option.v > now and not at then at = i - 1 end
        end
        at = at or (back and 1 or #row.values)
    end
    at = at or 1
    options.set(id, row.values[(at - 1 + (back and -1 or 1)) % #row.values + 1].v)
end

--- What the row shows in its badge: ON, OFF or the value's label.
function options.label(id)
    local row = options.rows[id]
    local value = options.get(id)
    if not row or value == nil then return 'N/A' end
    if row.values then
        for _, option in ipairs(row.values) do
            if option.v == value then return option.label end
        end
        if row.format then return row.format(value) end
        return tostring(value)
    end
    return value and 'ON' or 'OFF'
end

--- The rows to show now, in single player's order.
function options.list()
    local list = {}
    for _, row in pairs(options.rows) do
        if options.available(row) then list[#list + 1] = row end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    return list
end

return options
