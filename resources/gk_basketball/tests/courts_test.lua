--[[
    Courts that come and go: the arena's, which exists only while the arena's own
    floor is set up for basketball. Runs server/hoops.lua against a stand-in for
    the server, with whatever hoops an admin has placed left alone.
]]

local failed, passed = 0, 0

local function check(name, ok, detail)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print(('  FAIL  %s   %s'):format(name, detail or ''))
    end
end

BB = {}
load_game('shared/config.lua')
load_game('shared/util.lua')

-- A server with one hoop already placed by an admin, and the arena doing wrestling.
GlobalState = { mzbShow = 'wrestling' }

local handlers = {}
local closed = {}
local placed = '[{"id":"park_1","court":"park","coords":{"x":10.0,"y":20.0,"z":33.0}}]'

function AddStateBagChangeHandler(key, _, fn) handlers[key] = fn end
function SetTimeout(_, fn) fn() end
function GetCurrentResourceName() return 'gk_basketball' end
function LoadResourceFile() return placed end
function SaveResourceFile() end
function RegisterCommand() end
function RegisterNetEvent() end
function IsPlayerAceAllowed() return true end
function TriggerClientEvent() end

json = {
    -- Just enough to read the one hoop above.
    decode = function(raw)
        local list = {}
        for id, court, x, y, z in raw:gmatch('"id":"([^"]+)","court":"([^"]+)","coords":{"x":([%d%.-]+),"y":([%d%.-]+),"z":([%d%.-]+)}') do
            list[#list + 1] = { id = id, court = court, coords = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } }
        end
        return list
    end,
    encode = function() return '[]' end,
}

load_game('server/hoops.lua')

function BB.closeCourt(id) closed[#closed + 1] = id end

local function published()
    local ids = {}
    for _, hoop in ipairs(GlobalState[BB.STATE_HOOPS] or {}) do ids[hoop.id] = hoop end
    return ids
end

--------------------------------------------------------------------------------
check('an admin-placed court is there whatever the arena is doing', BB.courts.park ~= nil and published().park_1 ~= nil)
check('the arena has no court while it is set up for wrestling', BB.courts.arena == nil and published().arena_home == nil)
check('and its hoops can\'t be scored on', BB.findHoop('arena_home') == nil)
check('something is listening for the arena changing', handlers.mzbShow ~= nil)

-- The arena's own menu puts the basketball floor down.
GlobalState.mzbShow = 'basketball'
handlers.mzbShow()

local arena = BB.courts.arena
check('the court appears when the floor goes down', arena ~= nil and #arena.hoops == 2)
check('with both of the arena\'s baskets', published().arena_home ~= nil and published().arena_away ~= nil)
check('each a team\'s to defend', BB.findHoop('arena_home').team == 'home' and BB.findHoop('arena_away').team == 'away')
check('the placed court is untouched', BB.courts.park ~= nil and #closed == 0)

if arena then
    local home, away = BB.findHoop('arena_home').coords, BB.findHoop('arena_away').coords
    local apart = math.sqrt((home.x - away.x) ^ 2 + (home.y - away.y) ^ 2)
    check('the rims are a court apart', math.abs(apart - 2 * 12.7255) < 0.01, ('%.3f m'):format(apart))
    check('and ten feet up', math.abs(home.z - (19.55 + 3.05)) < 0.001 and home.z == away.z)

    -- Centre court is the arena's own centre.
    check('centre court is the middle of the arena', math.abs(arena.centre.x - -324.31) < 0.01 and math.abs(arena.centre.y - -1968.6) < 0.01,
        ('%.3f %.3f'):format(arena.centre.x, arena.centre.y))

    local spots = BB.ballSpots(arena)
    check('its practice balls are where the config puts them', #spots == #Config.Courts.arena.balls and not spots[1].settle)

    local onCourt = true
    for _, spot in ipairs(spots) do
        if math.sqrt((spot.x - arena.centre.x) ^ 2 + (spot.y - arena.centre.y) ^ 2) > 15.0 then onCourt = false end
    end
    check('all of them on the court', onCourt)

    local ped = Config.Courts.arena.ped.coords
    local side = math.sqrt((ped.x - arena.centre.x) ^ 2 + (ped.y - arena.centre.y) ^ 2)
    check('the attendant is at the side of the court', side > 7.62 and side < 9.9, ('%.2f m from centre'):format(side))
end

local park = BB.ballSpots(BB.courts.park)
check('a court with no list of its own gets a few near its middle', #park == Config.Ball.looseBalls and park[1].settle == true)
check('the arena court isn\'t instanced', Config.Courts.arena.instance == false)
check('readiness follows the arena', BB.courtReady('arena') == true and BB.courtReady('park') == true)

-- The floor is changed to something else.
GlobalState.mzbShow = 'hockey'
handlers.mzbShow()

check('the court goes when the floor is taken up', BB.courts.arena == nil and published().arena_home == nil)
check('and any game on it is ended', #closed == 1 and closed[1] == 'arena')
check('readiness follows that too', BB.courtReady('arena') == false)

print(('courts: %d passed, %d failed'):format(passed, failed))

return failed
