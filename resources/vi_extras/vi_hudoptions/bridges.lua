--[[ ===========================================================================
     vi_hudoptions — rows for features that live in other resources
     ---------------------------------------------------------------------------
     These features were on FiveM before vi_extras; HUD OPTIONS only switches
     them. Each row reads and changes the setting through its resource's own
     exports, and that resource keeps it per player, so the switch works the
     same from here, from vi_pausemenu's Settings page or on its own. A row
     shows only while its resource is started.
     ========================================================================= ]]

local options = require 'vi_hudoptions.options'

-- exports[resource][name](...), or nil when the resource or export isn't there
local function call(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, value = pcall(function()
        local res = exports[resource]
        return res[name](res, table.unpack(args, 1, args.n))
    end)
    if not ok then return nil end
    return value
end

local function bridge(row, resource, getter, setter)
    row.needs = resource
    row.get = function() return call(resource, getter) end
    row.set = function(value) call(resource, setter, value) end
    options.add(row)
end

local function percent(list)
    local values = {}
    for i, v in ipairs(list) do values[i] = { v = v, label = v .. '%' } end
    return values
end

bridge({ id = 'crashcam', label = 'CRASH CAMERA',
         desc = 'A slow replay from outside the car when you crash.' },
       'vi_crashcam', 'IsCrashCamEnabled', 'SetCrashCamEnabled')

bridge({ id = 'mapdaynight', label = 'MAP DAY/NIGHT',
         values = { { v = 'auto', label = 'AUTO' }, { v = 'day', label = 'DAY' }, { v = 'night', label = 'NIGHT' } },
         desc = 'The map by day, by night, or following the clock.' },
       'gen7_map', 'GetMapMode', 'SetMapMode')

-- vice_hud keeps it the other way round: the minimap on foot
options.add({
    id = 'mapvehicleonly', label = 'MAP IN VEHICLE ONLY', needs = 'vice_hud',
    desc = 'The minimap only while you are in a vehicle.',
    get = function()
        local onFoot = call('vice_hud', 'GetMinimapOnFoot')
        if onFoot == nil then return nil end
        return not onFoot
    end,
    set = function(value) call('vice_hud', 'SetMinimapOnFoot', not value) end,
})

bridge({ id = 'searchcircle', label = 'SEARCH CIRCLE',
         desc = "Where the police are searching for you, on the minimap." },
       'vice_hud', 'GetSearchCircle', 'SetSearchCircle')

-- honor comes bundled in vice_hud, or on its own as qbx_honor
local function honor()
    if GetResourceState('vice_hud') == 'started' and call('vice_hud', 'GetGreetEnabled') ~= nil then return 'vice_hud' end
    if GetResourceState('qbx_honor') == 'started' then return 'qbx_honor' end
    return nil
end
options.add({
    id = 'greet', label = 'GREET / ANTAGONIZE',
    desc = 'Greet or antagonize the people around you.',
    get = function()
        local res = honor()
        return res and call(res, 'GetGreetEnabled')
    end,
    set = function(value)
        local res = honor()
        if res then call(res, 'SetGreetEnabled', value) end
    end,
})

bridge({ id = 'radiowheel', label = 'VI RADIO WHEEL',
         desc = "This radio's wheel. Off gives GTA's own radio wheel back." },
       'vi_radio', 'GetWheelEnabled', 'SetWheelEnabled')

-- single player's steps; a size between them (vice_hud's /hudpolice editor
-- takes 40-200) shows as it is and steps to the next one up
bridge({ id = 'policelights', label = 'POLICE LIGHTS', values = percent({ 0, 60, 80, 100, 120, 140 }),
         format = function(v) return math.floor(v + 0.5) .. '%' end,
         desc = "The police lights at the screen's edge, and how big. 0% is none." },
       'vice_hud', 'GetPoliceLightsSize', 'SetPoliceLightsSize')

bridge({ id = 'crosshair', label = 'CROSSHAIR', desc = 'The crosshair while you aim.' },
       'vice_hud', 'GetCrosshairEnabled', 'SetCrosshairEnabled')

bridge({ id = 'killmarks', label = 'KILL MARKS', desc = 'A mark on the crosshair when you take someone down.' },
       'vice_hud', 'GetKillMarksEnabled', 'SetKillMarksEnabled')

bridge({ id = 'wantedstars', label = 'VI WANTED STARS',
         desc = 'Stars that show what the police know: seen, searching, lost or reported.' },
       'vice_hud', 'GetWantedStarsEnabled', 'SetWantedStarsEnabled')

bridge({ id = 'wantedbox', label = 'WANTED BOX', desc = 'The box that says when the police have your description.' },
       'vice_hud', 'GetWantedBoxEnabled', 'SetWantedBoxEnabled')

bridge({ id = 'binoculars', label = 'BINOCULARS', desc = 'The binoculars.' },
       'vi_binoculars', 'GetBinocularsEnabled', 'SetBinocularsEnabled')
