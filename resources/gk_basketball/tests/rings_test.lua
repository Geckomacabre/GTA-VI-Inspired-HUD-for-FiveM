--[[
    The 'rings' shot's arithmetic (shared/util.lua): which rim is under the
    reticle, how big the yellow ring is, and how far from the moment the rings
    met a release was. No game: these are pure, and tests/carry_test.lua runs
    them in the real client against a fake one.
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

local function near(a, b, tol) return math.abs(a - b) <= tol end

BB = {}
load_game('shared/config.lua')
load_game('shared/util.lua')

local shot, rings = Config.Shot, Config.Shot.rings

--------------------------------------------------------------------------------
-- The yellow ring
--------------------------------------------------------------------------------

check('close in, the yellow ring is its biggest', near(BB.ringSize(shot.closeRange), rings.nearSize, 1e-9))
check('nearer still, no bigger', near(BB.ringSize(0.5), rings.nearSize, 1e-9))
check('at farAt, its smallest', near(BB.ringSize(rings.farAt), rings.farSize, 1e-9))
check('and no smaller beyond', near(BB.ringSize(shot.maxRange), rings.farSize, 1e-9))

local last, shrinks = math.huge, true
for d = shot.closeRange, rings.farAt, 0.5 do
    local s = BB.ringSize(d)
    if s > last then shrinks = false end
    last = s
end
check('it gets smaller the further out the shot', shrinks)
check('and always fits inside the white one', rings.nearSize < 1.0 and rings.farSize > 0.0)

--------------------------------------------------------------------------------
-- Timing
--------------------------------------------------------------------------------

local size = BB.ringSize(6.0)
local meet = (1.0 - size) * rings.closeMs

check('letting go as they meet is no error', near(BB.ringError(meet, size), 0.0, 1e-9))
check('before is early (negative)', BB.ringError(meet - 100, size) < 0)
check('after is late (positive)', BB.ringError(meet + 100, size) > 0)
check('a bigger yellow ring is met sooner, so an easy shot comes sooner',
    (1.0 - BB.ringSize(4.0)) * rings.closeMs < (1.0 - BB.ringSize(10.0)) * rings.closeMs)
check('even the smallest yellow ring is met with time to spare before the white one is gone',
    rings.farSize * rings.closeMs > shot.timing.perfect, rings.farSize * rings.closeMs)

--------------------------------------------------------------------------------
-- The rim under the reticle
--------------------------------------------------------------------------------

local function v(x, y, z) return vec3(x, y, z) end
local function unit(x, y, z) local l = math.sqrt(x * x + y * y + z * z) return v(x / l, y / l, z / l) end

local eye, from = v(0.0, 0.0, 1.6), v(0.0, 0.0, 1.0)
local ahead = { id = 'ahead', coords = v(0.0, 6.0, 3.05) }
local aside = { id = 'aside', coords = v(4.0, 6.0, 3.05) }
local far   = { id = 'far',   coords = v(0.0, 40.0, 3.05) }
local mine  = { id = 'mine',  coords = v(0.0, 6.0, 3.05), team = 'home' }

local look = unit(0.0, 6.0, 3.05 - 1.6)

local hoop, dist, angle = BB.hoopInSights({ aside, ahead }, eye, look, from, shot.maxRange, nil, rings.lockAngle)
check('the rim in the middle of the screen is the one', hoop == ahead, hoop and hoop.id)
check('its distance is along the ground, from the shooter', dist and near(dist, 6.0, 1e-6), dist)
check('and it is dead centre', angle and angle < 0.01, angle)

hoop = BB.hoopInSights({ aside }, eye, look, from, shot.maxRange, nil, rings.lockAngle)
check('one well off to the side is not locked on', hoop == nil, hoop and hoop.id)

hoop = BB.hoopInSights({ far }, eye, unit(0.0, 40.0, 3.05 - 1.6), from, shot.maxRange, nil, rings.lockAngle)
check('nor one out of range, however well aimed at', hoop == nil)

hoop = BB.hoopInSights({ ahead }, eye, unit(0.0, -1.0, 0.0), from, shot.maxRange, nil, rings.lockAngle)
check('nor one behind', hoop == nil)

hoop = BB.hoopInSights({ ahead }, eye, unit(0.0, 1.0, -0.6), from, shot.maxRange, nil, rings.lockAngle)
check('nor one you are looking well below', hoop == nil)

hoop = BB.hoopInSights({ mine }, eye, look, from, shot.maxRange, 'home', rings.lockAngle)
check("nor the basket my own team defends", hoop == nil)

hoop = BB.hoopInSights({ mine }, eye, look, from, shot.maxRange, 'away', rings.lockAngle)
check('which the other team shoots at', hoop == mine)

-- Just inside and just outside the lock.
local function tilted(deg)
    local base = math.atan(3.05 - 1.6, 6.0)
    local a = base + math.rad(deg)
    return unit(0.0, math.cos(a), math.sin(a))
end

check('just inside lockAngle locks on',
    BB.hoopInSights({ ahead }, eye, tilted(rings.lockAngle - 0.5), from, shot.maxRange, nil, rings.lockAngle) == ahead)
check('just outside does not',
    BB.hoopInSights({ ahead }, eye, tilted(rings.lockAngle + 0.5), from, shot.maxRange, nil, rings.lockAngle) == nil)

print(('rings: %d passed, %d failed'):format(passed, failed))

return failed
