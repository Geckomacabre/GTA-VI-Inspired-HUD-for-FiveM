--[[
    client/anim.lua against a real clip index.

    Reads the animation pack's clip_index.lua from disk if it can be found (next
    to this resource as ../nba2k18_assets, or wherever NBA_PACK points), and
    checks that every clip Config.Anims.packClips asks for is in it, with the
    timing the client relies on. Without a pack on disk it checks the other
    half: that with no pack, everything is exactly the stand-ins.
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

local function read(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local s = f:read('a')
    f:close()
    return s
end

local candidates = {
    os.getenv('NBA_PACK'),
    ROOT .. '/../nba2k18_assets',
    'C:/Users/Johna/nba2k18-extract/fivem/nba2k18_assets',
}

local packIndex
for _, dir in pairs(candidates) do
    packIndex = packIndex or (dir and read(dir .. '/clip_index.lua'))
end

local function fresh(withPack)
    BB = {}
    load_game('shared/config.lua')

    function GetResourceState() return withPack and 'started' or 'missing' end
    function LoadResourceFile() return withPack and packIndex or nil end
    function AddEventHandler() end

    load_game('client/moves.lua')
    load_game('client/anim.lua')
end

--------------------------------------------------------------------------------
-- No pack: nothing changes
--------------------------------------------------------------------------------
do
    fresh(false)

    local cfg, release, length, marks = BB.anim.action('shoot')
    check('without a pack the shot is the stand-in', cfg == Config.Anims.shoot and release == nil and length == nil
        and marks == nil)
    check('and the pass', (BB.anim.action('pass')) == Config.Anims.pass)
    check('and the contest', (BB.anim.action('contest')) == Config.Anims.contest)
    check('there are no dribble cycles', BB.anim.gaits() == nil)
    check('and no stance', BB.anim.stance() == nil)
    check('an action nobody defined is just nil', BB.anim.action('nonsense') == nil)
    check('a stand-in arm clip is still only what the owner set', Config.Dribble.handAnim == false)
end

--------------------------------------------------------------------------------
-- With the pack
--------------------------------------------------------------------------------
if packIndex then
    fresh(true)

    local raw = load(packIndex, '@clip_index.lua', 't', {})()
    local M = BB.moves

    local cfg, release, length, marks = BB.anim.action('shoot')
    check('the shot comes from the pack', cfg ~= Config.Anims.shoot and cfg.dict:match('^nba2k18@') ~= nil, cfg and cfg.dict)
    check('it is a whole-body clip played once', cfg.flag == 0 and cfg.duration == length)
    check('and says when the ball leaves', release ~= nil and release > 150 and release < length,
        ('release %s of %s ms'):format(tostring(release), tostring(length)))
    check('and when the shooter lands', marks ~= nil and marks.land ~= nil and marks.land > release
        and marks.land < length, marks and tostring(marks.land))

    for _, key in ipairs({ 'pass', 'pickup', 'steal' }) do
        local c, _, len = BB.anim.action(key)
        check(('the %s comes from the pack'):format(key), c ~= Config.Anims[key] and c.name ~= nil and len ~= nil and len > 100)
    end

    local _, _, pickLength, pickMarks = BB.anim.action('pickup')
    check('the pick-up says when the hands close on the ball', pickMarks ~= nil and pickMarks.catch ~= nil
        and pickMarks.catch > 50 and pickMarks.catch < pickLength, pickMarks and tostring(pickMarks.catch))

    local contest = BB.anim.action('contest')
    check('the contest is played the way packClips says', contest.flag == 49 and contest.duration == 1100,
        ('flag %s duration %s'):format(tostring(contest.flag), tostring(contest.duration)))

    local stance = BB.anim.stance()
    check('there is a two-handed stance', stance ~= nil and stance.dict ~= nil and stance.name ~= nil)

    ----------------------------------------------------------------------------
    -- The dribble
    ----------------------------------------------------------------------------
    local gaits = BB.anim.gaits()
    check('there is a dribble', type(gaits) == 'table' and #gaits >= 1)

    if type(gaits) == 'table' then
        check('for every pace from standing to a sprint', #gaits >= 4 and gaits[1].speed == 0.0
            and gaits[#gaits].speed > 5.5, ('%d cycles, fastest %.2f'):format(#gaits, gaits[#gaits].speed))

        local ascending, ordered, inHandAtEntry, sane, allRight = true, true, true, true, true

        for i, gait in ipairs(gaits) do
            if i > 1 and gait.speed <= gaits[i - 1].speed then ascending = false end
            if gait.hand ~= 'r' then allRight = false end

            for k, bounce in ipairs(gait.bounces) do
                if not (bounce.push < bounce.floor and bounce.floor < bounce.catch and bounce.catch <= gait.duration + 1e-6) then
                    ordered = false
                end

                if k > 1 and bounce.push < gait.bounces[k - 1].catch then ordered = false end

                -- A hand-height dribble is in the air for a few tenths of a second.
                local away = bounce.catch - bounce.push
                if away < 0.15 or away > 0.6 then sane = false end
            end

            if not (M.bounceAt(gait.bounces, gait.entry)) then inHandAtEntry = false end
        end

        check('slowest first', ascending)
        check('every bounce is let go, lands and is caught, in that order and inside its clip', ordered)
        check('every bounce is in the air about as long as a real one', sane)
        check('each cycle is come into with the ball in the hand', inHandAtEntry)
        check('all of them right-handed (the only hand a carried ball is drawn in)', allRight)

        -- Nothing the pack was told to use was thrown away on the quiet.
        local asked = Config.Anims.packClips.dribble
        check('every cycle packClips names is being used', #gaits == #asked,
            ('%d named, %d usable'):format(#asked, #gaits))

        -- The paces are far enough apart to be told from each other.
        local apart = true
        for i = 2, #gaits do
            if gaits[i].speed - gaits[i - 1].speed < 0.8 then apart = false end
        end
        check('the paces are distinct', apart)
    end

    -- Every clip named in packClips exists in the index under that exact name.
    local missing = {}

    for key, spec in pairs(Config.Anims.packClips) do
        local names = spec

        if type(spec) == 'table' and spec.clip then names = { spec.clip } end
        if type(names) == 'string' then names = { names } end

        for _, name in ipairs(names) do
            if not raw[name] then missing[#missing + 1] = key .. '=' .. name end
        end
    end

    check('every clip packClips names is in the pack', #missing == 0, table.concat(missing, ', '))

    -- The pack's own times have to be inside its own clips. (They weren't, for
    -- the clips the source game plays back slowed down, until the converter
    -- learned about the slowing.)
    local late = {}

    for name, e in pairs(raw) do
        if e.clip == name then
            for _, field in ipairs({ 'release', 'takeoff', 'land', 'catch', 'contact', 'apex' }) do
                if e[field] and e[field] > e.duration + 1e-6 then late[#late + 1] = name .. '.' .. field end
            end

            for _, bounce in ipairs(e.bounces or {}) do
                if bounce.catch > e.duration + 1e-6 then late[#late + 1] = name .. '.bounce' end
            end
        end
    end

    table.sort(late)
    check('no clip in the pack has a mark after its own end', #late == 0, table.concat(late, ', '))

    print(('    pack: shot %s release %d ms, lands %d of %d; %d dribble cycles at %s m/s')
        :format(cfg.name, release or -1, marks and marks.land or -1, length or -1, gaits and #gaits or 0,
            gaits and table.concat((function()
                local s = {}
                for i, g in ipairs(gaits) do s[i] = ('%.1f'):format(g.speed) end
                return s
            end)(), ' / ') or '-'))
else
    print('    (no animation pack found on disk; pack checks skipped)')
end

print(('anim: %d passed, %d failed'):format(passed, failed))

return failed
