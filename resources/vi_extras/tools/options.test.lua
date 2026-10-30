-- Headless check of vi_hudoptions/options.lua: rows load their saved value, step and save, list in
-- single player's order whatever order they're added in, and a row for another resource shows only
-- while that resource runs and answers. Run from the resource folder:   lua tools/options.test.lua
local fails, total = 0, 0
local function ok(c, msg) total = total + 1 if not c then fails = fails + 1 print('  FAIL  ' .. msg) else print('  PASS  ' .. msg) end end

local kvp, states = {}, { vice_hud = 'started' }
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
function GetResourceState(r) return states[r] or 'missing' end

-- a fresh copy of the module, as a reconnect gets (readfile: the fengari runner has no io)
local function fresh()
    local src
    if io and io.open then
        local f = assert(io.open('vi_hudoptions/options.lua', 'rb'))
        src = f:read('a') f:close()
    else
        src = assert(readfile('vi_hudoptions/options.lua'))
    end
    return assert(load(src, '@vi_hudoptions/options.lua'))()
end

local options = fresh()
local changed = {}
options.add({ id = 'spinouts', label = 'SPIN-OUTS', default = true, onChange = function(v) changed[#changed + 1] = v end })
options.add({ id = 'gunsonback', label = 'GUNS ON BACK', default = false })
local crosshair = true
options.add({ id = 'crosshair', label = 'CROSSHAIR', needs = 'vice_hud',
              get = function() return crosshair end, set = function(v) crosshair = v end })
local size = 100
options.add({ id = 'policelights', label = 'POLICE LIGHTS', needs = 'vice_hud',
              values = { { v = 0, label = '0%' }, { v = 60, label = '60%' }, { v = 100, label = '100%' }, { v = 140, label = '140%' } },
              get = function() return size end, set = function(v) size = v end })
options.add({ id = 'binoculars', label = 'BINOCULARS', needs = 'vi_binoculars',
              get = function() return true end, set = function() end })

ok(changed[1] == true, 'a module starts on its default (onChange at add)')
local ids = {}
for _, r in ipairs(options.list()) do ids[#ids + 1] = r.id end
ok(table.concat(ids, ',') == 'gunsonback,spinouts,policelights,crosshair', "single player's order, rows of stopped resources left out: " .. table.concat(ids, ','))

options.step('spinouts')
ok(options.get('spinouts') == false and kvp['vi_extras:spinouts'] == 'false' and changed[2] == false, 'ON / OFF flips, saves and tells the module')
ok(options.label('spinouts') == 'OFF' and options.label('gunsonback') == 'OFF', 'OFF in the badge')

options.step('crosshair')
ok(crosshair == false and options.get('crosshair') == false and options.label('crosshair') == 'OFF', "another resource's row changes it there; false stays false")
ok(kvp['vi_extras:crosshair'] == nil, "another resource's setting isn't kept here")

options.step('policelights') ok(size == 140, 'a list steps to the next value')
options.step('policelights') ok(size == 0, 'from the last back to the first, as single player')
options.step('policelights', -1) ok(size == 140, 'and back')
ok(options.label('policelights') == '140%', 'the value label in the badge')
-- a size between the steps (vice_hud's editor takes 40-200)
options.rows.policelights.format = function(v) return v .. '%' end
size = 75
ok(options.label('policelights') == '75%', 'a size between the steps shows as it is')
options.step('policelights') ok(size == 100, 'and steps up to the next one')
size = 75 options.step('policelights', -1) ok(size == 60, 'or down to the one before')
size = 200 options.step('policelights') ok(size == 0, 'above the last step: round to the first')
size = 140

states.vice_hud = 'stopped'
ok(#options.list() == 2, 'its rows go when the resource stops')
ok(options.available('crosshair') == false, 'unavailable')

options = fresh()
local back = {}
options.add({ id = 'spinouts', label = 'SPIN-OUTS', default = true, onChange = function(v) back[#back + 1] = v end })
ok(options.get('spinouts') == false and back[1] == false, 'the saved choice comes back after a reconnect')

print(('%d/%d passed'):format(total - fails, total))
return fails == 0
