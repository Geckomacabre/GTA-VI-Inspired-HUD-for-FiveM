--[[
    client/ball.lua against a fake game (tests/fakegame.lua + tests/fakeped.lua).

    Carrying a ball is all glue: an animation's clock, a hand bone, a floor, and
    a ball put somewhere every frame. None of it can be seen from the physics
    tests, and none of it can be run on this desk in the real game, so it is run
    here: the real client files, with the game underneath them replaced by
    something that keeps time and remembers what it was asked to do.

    What is checked is what was wrong when it was watched in the game: a ball
    that is in the hand when the animation says so and on the floor when it says
    so, that never jumps from one place to another, a ped that is in the right
    animation for how fast it is moving, a shot that starts in a stance, leaves
    from the hands and goes in, and a ball that is caught when it comes to you.
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

local Fake = load_file('tests/fakegame.lua')
FAKE = Fake
load_file('tests/fakeped.lua')

local function read(path)
    local f = io.open(path, 'r')
    if not f then return nil end
    local s = f:read('a')
    f:close()
    return s
end

local packIndex
for _, dir in pairs({ os.getenv('NBA_PACK'), ROOT .. '/../nba2k18_assets',
    'C:/Users/Johna/nba2k18-extract/fivem/nba2k18_assets' }) do
    packIndex = packIndex or (dir and read(dir .. '/clip_index.lua'))
end

local RADIUS

--- A clean game with the client loaded and me stood at the origin on a floor.
--- @param pack boolean With the animation pack running
--- @param tweak function|nil Changes to the config before the client reads it
local function fresh(pack, tweak)
    Fake.threads, Fake.entities, Fake.events = {}, {}, {}
    Fake.now = 1000
    Fake.sweepMeans = 'contact'
    Fake.controls, Fake.pressed, Fake.released, Fake.disabled = {}, {}, {}, {}
    Fake.played, Fake.loaded, Fake.clips = {}, {}, {}
    Fake.cam, Fake.pitch, Fake.asked, Fake.lag = 0.0, 0.0, 0, 0
    Fake.server = { pickup = true }
    Fake.nui, Fake.cams, Fake.rendering, Fake.resources = {}, {}, false, {}

    local W = World.new({})
    W.plane(0, 0, 1, 0)
    Fake.world = W

    BB = {}
    load_file('client/physics.lua')
    load_game('shared/config.lua')
    load_game('shared/util.lua')

    -- The pack's checks are about its jump shot, which is the timed shot; the
    -- 'rings' shot has its own section below.
    if pack then Config.Shot.style = 'timed' end

    if tweak then tweak() end

    BB.loose, BB.hoops, BB.fx, BB.hints = {}, {}, {}, {}

    function BB.nearbyHoops() return BB.hoops end
    function BB.playFx(kind) BB.fx[#BB.fx + 1] = kind end
    function BB.showHint(text) BB.hints[text] = (BB.hints[text] or 0) + 1 end
    function BB.hideHint() end
    BB.notes = {}
    function BB.notify(text) BB.notes[#BB.notes + 1] = text end
    function BB.flashPoints() end
    BB.shots = {}
    function BB.trackShot(netId, origin, hoop, accuracy)
        BB.shots[#BB.shots + 1] = { netId = netId, accuracy = accuracy, hoop = hoop }
    end
    function BB.untrackShot() end

    -- Aim assist: the one hoop there is, if there is one.
    function BB.pickTargetHoop(hoops, from)
        local hoop = hoops[1]
        if not hoop then return nil end
        return hoop, BB.dist2d(from, hoop.coords)
    end

    -- The pack, and anything a test says is running (Fake.resources: vice_hud).
    function GetResourceState(name)
        if name == Config.Anims.pack then return pack and 'started' or 'missing' end
        return Fake.resources[name] or 'missing'
    end
    function LoadResourceFile() return pack and packIndex or nil end

    Fake.player = Fake.ped(0.0, 0.0, 1.0, 0.0)
    Fake.peds = { Fake.player }

    load_game('client/look.lua')
    load_game('client/aimcam.lua')
    load_game('client/moves.lua')
    load_game('client/anim.lua')
    load_game('client/ballsim.lua')
    load_game('client/ball.lua')

    -- How long each of the pack's clips is, for the fake's clocks.
    if pack then
        local index = load(packIndex, '@clip_index.lua', 't', {})()
        for _, e in pairs(index) do Fake.clips[e.dict .. '/' .. e.clip] = e.duration end
    end

    RADIUS = Config.Ball.radius

    return W
end

local function fxCount(kind)
    local n = 0
    for _, k in ipairs(BB.fx) do
        if k == kind then n = n + 1 end
    end
    return n
end

local function ballOf(id) return Fake.entities[id] end

local function palmOf(ped)
    local off = Config.Ball.offset
    return GetPedBoneCoords(ped, Config.Ball.bone, off.x, off.y, off.z)
end

local function playedLast(ped)
    for i = #Fake.played, 1, -1 do
        if Fake.played[i].ped == ped then return Fake.played[i] end
    end
end

local function playingNow(ped, what)
    for _, a in pairs(Fake.entities[ped].anims) do
        if a.name:find(what, 1, true) then return a end
    end
end

--[[
    Dribbles for a while and reports on it.

    `where` is measured against the ped, not the world, so a ball that is simply
    travelling along with a sprinting ped is not mistaken for one that jumped.
]]
local function dribbleFor(ped, ball, st, seconds)
    local r = { low = math.huge, high = -math.huge, jump = 0.0, inHandGap = 0.0, far = 0.0, frames = 0, names = {} }
    local last

    Fake.play(seconds, function()
        BB.dribble(ped, ball, st)

        local b = ballOf(ball).pos
        local rel = GetOffsetFromEntityGivenWorldCoords(ped, b.x, b.y, b.z)

        r.low, r.high = math.min(r.low, b.z), math.max(r.high, b.z)
        r.far = math.max(r.far, math.sqrt(rel.x * rel.x + rel.y * rel.y))

        if last then r.jump = math.max(r.jump, #(rel - last)) end
        last = rel

        -- In the hand means in the hand: where the palm is this very frame.
        if st.inHand and not st.easeFrom then
            r.inHandGap = math.max(r.inHandGap, #(b - palmOf(ped)))
        end

        local a = playingNow(ped, 'dribble')
        if a then r.names[a.name] = (r.names[a.name] or 0) + 1 end

        r.frames = r.frames + 1
    end)

    return r
end

--------------------------------------------------------------------------------
-- With the animation pack
--------------------------------------------------------------------------------
if packIndex then
    ----------------------------------------------------------------------------
    -- Standing still
    ----------------------------------------------------------------------------
    do
        fresh(true)

        local ped = Fake.player
        local ball = BB.createBall(GetEntityCoords(ped))
        local st = { phase = 0.0 }

        local gaits = BB.anim.gaits()
        check('the pack has a dribble for every pace', gaits ~= nil and #gaits >= 4, gaits and #gaits or 'none')
        check('slowest first, the first one standing', gaits and gaits[1].speed == 0.0 and gaits[2].speed > 1.0
            and gaits[#gaits].speed > 5.0)

        local standing = gaits[1]
        local r = dribbleFor(ped, ball, st, standing.duration * 2.0)

        local first = Fake.played[1]
        check('standing with the ball plays the standing dribble', first and first.name == standing.name
            and first.dict == standing.dict, first and first.name)
        check('standing still, with the whole body', first and first.flag == 33, first and first.flag)
        check('the ordinary standing dribble, with nobody on me', first and first.name == Config.Anims.packClips.dribble[1]
            and first.name ~= Config.Anims.packClips.guarded, first and first.name)
        check('started with the ball in the hand', first
            and (BB.moves.bounceAt(standing.bounces, first.start * standing.duration)))
        check('and is not started again every frame', #Fake.played == 1, #Fake.played)

        check('the ball goes down to the floor', near(r.low, RADIUS, 0.03), ('lowest %.3f'):format(r.low))
        check('and never through it', r.low >= RADIUS - 1e-6)
        check('it comes back to the hand, exactly', r.inHandGap < 1e-6, ('gap %.4f'):format(r.inHandGap))
        check('it never jumps', r.jump < 0.16, ('%.3f m in a frame'):format(r.jump))
        check('it stays beside the ped', r.far < 0.9, ('%.2f m away'):format(r.far))

        local bounces = #standing.bounces * 2
        check('every bounce is heard, once', fxCount('dribble') >= bounces - 1 and fxCount('dribble') <= bounces + 1,
            ('%d sounds for %d bounces'):format(fxCount('dribble'), bounces))
    end

    ----------------------------------------------------------------------------
    -- On the move
    ----------------------------------------------------------------------------
    do
        fresh(true)

        local ped = Fake.player
        local ball = BB.createBall(GetEntityCoords(ped))
        local st = { phase = 0.0 }
        local gaits = BB.anim.gaits()

        dribbleFor(ped, ball, st, 0.5)

        -- Heading 0 is up the y axis.
        Fake.entities[ped].vel = vec3(0.0, gaits[3].speed, 0.0)
        local r = dribbleFor(ped, ball, st, 2.5)

        check('at a jog it is the jogging dribble', (r.names[gaits[3].name] or 0) > r.frames * 0.8,
            ('%s of %d frames'):format(tostring(r.names[gaits[3].name]), r.frames))
        check('on the move only its arms and back: the legs are the game\'s own', playingNow(ped, 'dribble').flag == 49,
            playingNow(ped, 'dribble').flag)
        check('played at the pace the ped is going', near(playingNow(ped, 'dribble').speed, 1.0, 0.02),
            playingNow(ped, 'dribble').speed)
        check('the ball goes along with a moving ped', r.far < 1.0 and r.jump < 0.2,
            ('%.2f m away, %.3f m in a frame'):format(r.far, r.jump))
        check('and still reaches the floor', near(r.low, RADIUS, 0.03), ('lowest %.3f'):format(r.low))

        Fake.entities[ped].vel = vec3(0.0, 6.6, 0.0)
        r = dribbleFor(ped, ball, st, 2.5)

        check('at a sprint it is the sprinting dribble', playingNow(ped, 'dribble').name == gaits[#gaits].name,
            playingNow(ped, 'dribble').name)
        check('changing pace does not throw the ball about', r.jump < 0.2, ('%.3f m in a frame'):format(r.jump))
        check('a little quicker than it was made, to keep the feet honest', playingNow(ped, 'dribble').speed > 1.0)

        local before = #Fake.played
        Fake.entities[ped].vel = vec3(0.0, 0.0, 0.0)
        r = dribbleFor(ped, ball, st, 0.1)

        check('stopping is the standing dribble at once', playingNow(ped, 'dribble').name == gaits[1].name
            and #Fake.played == before + 1, playingNow(ped, 'dribble').name)
        check('and the whole body again', playingNow(ped, 'dribble').flag == 33)

        r = dribbleFor(ped, ball, st, 1.0)
        check('and the ball is gathered in, not snapped', r.jump < 0.2, ('%.3f m in a frame'):format(r.jump))

        BB.dribbleStop(ped, st)
        check('the dribble stops when told to', playingNow(ped, 'dribble') == nil and st.gait == nil)
    end

    ----------------------------------------------------------------------------
    -- Arms only, and a pack that won't load
    ----------------------------------------------------------------------------
    do
        fresh(true, function() Config.Dribble.body = 'upper' end)

        local ped = Fake.player
        local ball = BB.createBall(GetEntityCoords(ped))

        dribbleFor(ped, ball, { phase = 0.0 }, 0.3)
        check("body = 'upper' leaves the legs to the game even standing", Fake.played[1] and Fake.played[1].flag == 49,
            Fake.played[1] and Fake.played[1].flag)
    end

    do
        fresh(true, function() Config.Dribble.body = 'full' end)

        local ped = Fake.player
        local ball = BB.createBall(GetEntityCoords(ped))

        Fake.entities[ped].vel = vec3(0.0, 3.0, 0.0)
        dribbleFor(ped, ball, { phase = 0.0 }, 0.5)
        check("body = 'full' takes the whole body on the move too", playingNow(ped, 'dribble').flag == 33,
            playingNow(ped, 'dribble').flag)
    end

    ----------------------------------------------------------------------------
    -- With a defender on me
    ----------------------------------------------------------------------------
    do
        fresh(true)

        local ped = Fake.player
        local ball = BB.createBall(GetEntityCoords(ped))
        local st = { phase = 0.0 }

        local defender = Fake.ped(0.0, 12.0, 1.0, 180.0)
        BB.match = { state = 'live', players = {} }
        BB.botPeds = { [defender] = { id = -1, team = 'away' } }

        dribbleFor(ped, ball, st, 1.0)
        local easy, low = Config.Anims.packClips.dribble[1], Config.Anims.packClips.guarded

        check('a defender across the court does not change how I stand', playingNow(ped, 'dribble').name == easy,
            playingNow(ped, 'dribble').name)

        -- Closes on me.
        Fake.entities[defender].pos = vec3(0.0, 2.0, 1.0)

        local r = {}
        Fake.play(2.5, function()
            BB.dribble(ped, ball, st, 'home')
        end)

        check('one who closes on me puts me lower, over the ball', playingNow(ped, 'dribble').name == low,
            playingNow(ped, 'dribble').name)

        Fake.play(0.5, function() BB.dribble(ped, ball, st, nil) end)
        Fake.play(2.5, function() BB.dribble(ped, ball, st, nil) end)
        check('but only an opponent: with no side of my own, nobody is guarding me',
            playingNow(ped, 'dribble').name == easy, playingNow(ped, 'dribble').name)
    end

    do
        fresh(true)
        Fake.loaded['nba2k18@dribble'] = false

        local ped = Fake.player
        local ball = BB.createBall(GetEntityCoords(ped))
        local st = { phase = 0.0 }
        local r = dribbleFor(ped, ball, st, 3.0)

        check('a dribble that will not stream in is not played', #Fake.played == 0)
        check('but the ball still bounces, on its own clock', near(r.low, RADIUS, 0.03) and r.inHandGap < 1e-6
            and fxCount('dribble') >= 3, ('lowest %.3f, %d bounces'):format(r.low, fxCount('dribble')))
    end

    -- An animation takes a moment to start, and the game can cut across one
    -- that is playing (a stumble, a climb). Either way the ball carries on, and
    -- the dribble is asked for again: once, not sixty times a second.
    do
        fresh(true)
        Fake.lag = 180

        local ped = Fake.player
        local ball = BB.createBall(GetEntityCoords(ped))
        local st = { phase = 0.0 }

        local r = dribbleFor(ped, ball, st, 1.0)
        check('a dribble that is slow to start is asked for once', #Fake.played == 1 and playingNow(ped, 'dribble') ~= nil,
            #Fake.played)
        check('and the ball does not jump when it does start', r.jump < 0.16, ('%.3f m in a frame'):format(r.jump))

        Fake.entities[ped].anims = {}       -- cut across
        r = dribbleFor(ped, ball, st, 1.5)

        check('one that is cut across is asked for again', playingNow(ped, 'dribble') ~= nil)
        check('but not every frame', #Fake.played >= 2 and #Fake.played <= 3, #Fake.played)
        check('and the ball kept going meanwhile', near(r.low, RADIUS, 0.03) and r.jump < 0.16,
            ('lowest %.3f, %.3f m in a frame'):format(r.low, r.jump))
    end

    ----------------------------------------------------------------------------
    -- Lining up and shooting
    ----------------------------------------------------------------------------
    do
        fresh(true, function()
            -- The older way of shooting: line up first, with the meter.
            Config.Shot.style = 'meter'

            -- Any release is a perfect one: this is about where the shot starts
            -- and where it goes, not about the meter.
            Config.Shot.sweetWidth = 10.0
            Config.Shot.distancePenalty = 0.0
        end)

        local ped = Fake.player
        local hoop = { id = 'h', coords = vec3(0.0, 5.0, 3.05) }
        BB.hoops = { hoop }

        -- Facing west, with the basket to the north.
        SetEntityHeading(ped, 90.0)

        BB.takeBall()
        check('given a ball, I have one', BB.isHolding())

        local ball
        for id, e in pairs(Fake.entities) do
            if id ~= ped and not e.anims then ball = id end
        end

        Fake.play(0.6)
        check('and am dribbling it', playingNow(ped, 'dribble') ~= nil)

        -- Aim.
        Fake.hold(Config.Keys.aim)

        local jump, last = 0.0, nil
        Fake.play(0.7, function()
            local b = ballOf(ball).pos
            if last then jump = math.max(jump, #(b - last)) end
            last = b
        end)

        local stance = BB.anim.stance()
        check('the pack has a stance', stance ~= nil)
        check('lining up is the two-handed stance', stance and IsEntityPlayingAnim(ped, stance.dict, stance.name, 3))
        check('in place of the dribble', playingNow(ped, 'dribble') == nil)
        check('the ball is gathered into the hands, not snapped', jump < 0.2, ('%.3f m in a frame'):format(jump))

        local right = GetPedBoneCoords(ped, Config.Ball.bone, 0.0, 0.0, 0.0)
        local left  = GetPedBoneCoords(ped, Config.Ball.boneLeft, 0.0, 0.0, 0.0)
        local mid   = (right + left) * 0.5
        check('and is between the palms', #(ballOf(ball).pos - mid) < 1e-6, ('%.4f off'):format(#(ballOf(ball).pos - mid)))

        check('I am turned to the basket', near(BB.moves.turn(GetEntityHeading(ped), 0.0), 0.0, 0.6), GetEntityHeading(ped))
        check('and planted', (Fake.disabled[30] or 0) > 10 and (Fake.disabled[31] or 0) > 10)
        check('the meter and the hint are up', (BB.hints[Config.Text.aiming_hint] or 0) > 10)

        -- Changing my mind: back to dribbling, the ball let down without a jump.
        Fake.let(Config.Keys.aim)
        jump, last = 0.0, nil
        Fake.play(0.6, function()
            local b = ballOf(ball).pos
            if last then jump = math.max(jump, #(b - last)) end
            last = b
        end)

        check('letting go of aim goes back to the dribble', playingNow(ped, 'dribble') ~= nil
            and not IsEntityPlayingAnim(ped, stance.dict, stance.name, 3))
        check('without throwing the ball about', jump < 0.2, ('%.3f m in a frame'):format(jump))
        check('and I still have it', BB.isHolding())

        -- Aim again and shoot.
        Fake.hold(Config.Keys.aim)
        Fake.play(0.5)

        local pressedAt = Fake.now
        Fake.hold(Config.Keys.shoot)
        Fake.frameOn()
        Fake.let(Config.Keys.shoot)

        local releasedAt, from, handsThen
        local shotClip, releaseMs = BB.anim.action('shoot')

        -- Exactly where the physics is handed the ball, and where the hands
        -- were at that moment.
        local launch = BB.sim.launch
        function BB.sim.launch(ent, pos, ...)
            from = pos
            handsThen = (GetPedBoneCoords(ped, Config.Ball.bone, 0.0, 0.0, 0.0)
                + GetPedBoneCoords(ped, Config.Ball.boneLeft, 0.0, 0.0, 0.0)) * 0.5
            return launch(ent, pos, ...)
        end

        Fake.play(1.2, function()
            if not releasedAt and BB.sim.isSimulated(ball) then
                releasedAt = Fake.now
                return false
            end
        end)

        BB.sim.launch = launch

        check('the shot is the jump shot', playedLast(ped).name == shotClip.name and playedLast(ped).flag == 0,
            playedLast(ped).name)
        check('the stance has given way to it', not IsEntityPlayingAnim(ped, stance.dict, stance.name, 3))
        check('the ball leaves', releasedAt ~= nil)

        if releasedAt then
            check('when the animation lets go of it', near(releasedAt - pressedAt, releaseMs, 70),
                ('%.0f ms after the button, clip says %.0f'):format(releasedAt - pressedAt, releaseMs))

            local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
            check('out of the hands, where the animation has them', from and #(from - handsThen) < 1e-6,
                from and ('%.3f m from them'):format(#(from - handsThen)))
            check('which is over the head by then', from and from.z > head.z + 0.2,
                from and ('z %.2f, head %.2f'):format(from.z, head.z))
        end

        -- And it goes in: follow it down through the ring.
        local through, prev

        Fake.play(3.0, function()
            local b = ballOf(ball)
            if not b then return false end

            if prev and prev.z >= hoop.coords.z and b.pos.z < hoop.coords.z then
                through = BB.dist2d(b.pos, hoop.coords)
            end

            prev = b.pos
        end)

        check('a perfect release from there drops through the ring', through ~= nil and through < 0.12,
            through and ('%.3f m from the middle'):format(through) or 'never came down through rim height')

        Fake.let(Config.Keys.aim)
        Fake.play(1.0)

        check('and I am left empty-handed with my feet back', not BB.isHolding() and next(Fake.entities[ped].anims) == nil)
    end

    ----------------------------------------------------------------------------
    -- The timed shot: hold, go up, let go as the ball leaves
    ----------------------------------------------------------------------------
    --- Takes a timed shot, letting go of the button `holdMs` after pressing it
    --- (nil: never). Returns when the ball left (ms after the press), where
    --- from, the accuracy it was given, and how near the middle of the ring it
    --- came down.
    local function timed(holdMs, tweak)
        fresh(true, function()
            Config.Shot.distancePenalty = 0.0
            if tweak then tweak() end
        end)

        local ped = Fake.player
        local hoop = { id = 'h', coords = vec3(0.0, 5.0, 3.05) }
        BB.hoops = { hoop }

        SetEntityHeading(ped, 90.0)     -- facing west, basket to the north
        BB.takeBall()

        local ball
        for id, e in pairs(Fake.entities) do
            if id ~= ped and not e.anims then ball = id end
        end

        Fake.play(0.5)

        local r = { planted = (Fake.disabled[30] or 0) > 0, ball = ball, ped = ped }
        local pressed = Fake.now

        Fake.hold(Config.Keys.shoot)

        local launch = BB.sim.launch
        function BB.sim.launch(ent, pos, ...)
            r.from = pos
            r.leftAt = Fake.now - pressed
            r.heading = GetEntityHeading(ped)
            return launch(ent, pos, ...)
        end

        local prev

        Fake.play(4.5, function()
            if holdMs and Fake.controls[Config.Keys.shoot] and Fake.now - pressed >= holdMs then
                Fake.let(Config.Keys.shoot)
            end

            if playingNow(ped, 'jumpshot') then r.jumped = playingNow(ped, 'jumpshot') end

            local b = ballOf(ball)
            if b and r.leftAt then
                if prev and prev.z >= hoop.coords.z and b.pos.z < hoop.coords.z and not r.through then
                    r.through = BB.dist2d(b.pos, hoop.coords)
                end
                prev = b.pos
            end
        end)

        BB.sim.launch = launch

        r.accuracy = BB.shots[1] and BB.shots[1].accuracy
        r.holding = BB.isHolding()
        r.idle = next(Fake.entities[ped].anims) == nil

        return r
    end

    do
        local clip, releaseMs = nil, nil

        fresh(true)
        clip, releaseMs = BB.anim.action('shoot')

        -- Let go exactly as the ball leaves.
        local r = timed(releaseMs)

        check('holding shoot goes straight up for a jump shot', r.jumped ~= nil and r.jumped.name == clip.name
            and r.jumped.flag == 0, r.jumped and r.jumped.name)
        check('with no standing about first: nobody is planted before it', not r.planted)
        check('the ball leaves at the moment the animation lets go', r.leftAt and near(r.leftAt, releaseMs, 40),
            ('%s ms, clip says %s'):format(tostring(r.leftAt), tostring(releaseMs)))
        check('turned to the basket on the way up', r.heading and near(BB.moves.turn(r.heading, 0.0), 0.0, 1.0), r.heading)
        check('a release on the moment is a perfect one', r.accuracy and near(r.accuracy, 1.0, 1e-6), r.accuracy)
        check('and drops through the ring', r.through and r.through < 0.12, r.through and ('%.3f m off'):format(r.through) or 'never came down')
        check('afterwards I am empty-handed and on my feet', not r.holding and r.idle)

        -- A little out, still inside the window.
        r = timed(releaseMs - 40)
        check('a hair early is still perfect', r.accuracy and near(r.accuracy, 1.0, 1e-6), r.accuracy)

        -- Let go far too soon.
        r = timed(120)
        check('let go early, the ball still leaves at its moment', r.leftAt and near(r.leftAt, releaseMs, 40), r.leftAt)
        check('but the release was a poor one', r.accuracy and r.accuracy < 0.05, r.accuracy)

        -- Part of the way out: part of the accuracy.
        r = timed(releaseMs - 170)
        check('half way out is half as good', r.accuracy and r.accuracy > 0.3 and r.accuracy < 0.7, r.accuracy)

        -- Never let go.
        r = timed(nil)
        check('held too long, it leaves late and no later', r.leftAt
            and near(r.leftAt, releaseMs + Config.Shot.timing.late, 40), r.leftAt)
        check('and that costs', r.accuracy and r.accuracy < 0.6 and r.accuracy > 0.2, r.accuracy)
        check('with nothing left hanging', not r.holding and r.idle)

        -- Let go a little late: it leaves when I do.
        r = timed(releaseMs + 90)
        check('a little late, it leaves when I let go', r.leftAt and near(r.leftAt, releaseMs + 90, 40), r.leftAt)

        -- The other way of shooting is still there for whoever sets it.
        r = timed(releaseMs, function() Config.Shot.style = 'meter' end)
        check("style = 'meter' does not shoot on that button alone", r.jumped == nil and r.holding)
    end

    ----------------------------------------------------------------------------
    -- The follow-through: held while you watch, dropped when you move
    ----------------------------------------------------------------------------
    for _, moves in ipairs({ false, true }) do
        fresh(true)

        local ped = Fake.player
        BB.hoops = { { id = 'h', coords = vec3(0.0, 5.0, 3.05) } }
        Fake.stick = nil

        local clip, releaseMs, lengthMs, marks = BB.anim.action('shoot')

        BB.takeBall()
        Fake.play(0.4)

        local pressed = Fake.now
        Fake.hold(Config.Keys.shoot)
        Fake.play(releaseMs / 1000.0)
        Fake.let(Config.Keys.shoot)

        -- To just after the landing.
        Fake.play((marks.land + 200 - releaseMs) / 1000.0)

        local name = clip.name
        check('just after landing the shooter is still in the shot', IsEntityPlayingAnim(ped, clip.dict, name, 3))

        -- A ball lying by my feet can be bent down for already: I am not locked
        -- out for the length of the follow-through.
        check('but is free to do the next thing', BB.scoop(vec3(0.5, 0.0, RADIUS)) == true)
        Fake.play(1.0)      -- (nothing arrives; the bend plays out and is cleared)

        fresh(true)
        ped = Fake.player
        BB.hoops = { { id = 'h', coords = vec3(0.0, 5.0, 3.05) } }

        BB.takeBall()
        Fake.play(0.4)
        Fake.hold(Config.Keys.shoot)
        Fake.play(releaseMs / 1000.0)
        Fake.let(Config.Keys.shoot)
        Fake.play((marks.land + 200 - releaseMs) / 1000.0)

        if moves then
            Fake.stick = { 0.0, 1.0 }
            Fake.play(0.1)
            check('touching the stick lets the follow-through go at once', not IsEntityPlayingAnim(ped, clip.dict, name, 3))
        else
            Fake.play(0.5)
            check('stood watching, the follow-through is held', IsEntityPlayingAnim(ped, clip.dict, name, 3))

            Fake.play((lengthMs - marks.land) / 1000.0)
            check('and let go by itself in the end', not IsEntityPlayingAnim(ped, clip.dict, name, 3)
                and next(Fake.entities[ped].anims) == nil)
        end

        Fake.stick = nil
    end

    ----------------------------------------------------------------------------
    -- A pass made on the move doesn't stop you
    ----------------------------------------------------------------------------
    do
        fresh(true)

        local ped = Fake.player
        local cleared = 0
        local clear = ClearPedTasks
        function ClearPedTasks(...) cleared = cleared + 1 return clear(...) end

        BB.takeBall()
        Fake.entities[ped].vel = vec3(0.0, 3.0, 0.0)
        Fake.play(0.6)

        local heading = GetEntityHeading(ped)

        Fake.let(Config.Keys.pass)
        Fake.play(1.2)

        ClearPedTasks = clear

        local passed
        for _, p in ipairs(Fake.played) do
            if p.name:find('pass_', 1, true) then passed = p end
        end

        check('[E] passes', passed ~= nil and not BB.isHolding(), passed and passed.name)
        check('with the arms and back only, so the legs keep running', passed and passed.flag == 48, passed and passed.flag)
        check('and nothing is done to stop them', cleared == 0 and GetEntityHeading(ped) == heading, cleared)
        check('nothing of the dribble is left playing', playingNow(ped, 'dribble') == nil)
    end

    ----------------------------------------------------------------------------
    -- A shot whose animation never played leaves from somewhere sensible
    ----------------------------------------------------------------------------
    do
        fresh(true)

        local ped = Fake.player
        local ball = Fake.entity(0.4, 0.3, RADIUS)       -- on the floor by my foot
        local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)

        local from = BB.releasePoint(ped, ball, vec3(0.0, 1.0, 0.0), 'shot')
        check('a shot never starts from the floor', from.z > head.z and near(from.y, Config.Shot.releaseForward, 1e-6),
            ('%.2f %.2f %.2f'):format(from.x, from.y, from.z))

        SetEntityCoordsNoOffset(ball, 0.1, 0.2, head.z + 0.3)
        from = BB.releasePoint(ped, ball, vec3(0.0, 1.0, 0.0), 'shot')
        check('but does start from hands that are up', near(from.x, 0.1, 1e-6) and near(from.z, head.z + 0.3, 1e-6))

        SetEntityCoordsNoOffset(ball, 0.0, 0.35, head.z - 0.5)
        check('a pass comes out of the chest', near(BB.releasePoint(ped, ball, nil, 'pass').z, head.z - 0.5, 1e-6))
        check('a shot does not', BB.releasePoint(ped, ball, vec3(0.0, 1.0, 0.0), 'shot').z > head.z)
    end

    ----------------------------------------------------------------------------
    -- A ball that comes to me, and one lying on the floor
    ----------------------------------------------------------------------------
    do
        fresh(true)

        local ped = Fake.player
        local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)

        -- A rebound: coming down out of the air towards me.
        local ball = Fake.entity(0.0, 2.6, 3.0)
        BB.sim.launch(ball, vec3(0.0, 2.6, 3.0), vec3(0.0, -3.4, 1.0))
        BB.loose[ball] = { shooter = 2, at = 0 }

        local started, caughtAt = Fake.now, nil

        Fake.play(3.0, function()
            if BB.isHolding() then
                caughtAt = Fake.now
                return false
            end
        end)

        check('a ball that comes to me is caught, with no key', caughtAt ~= nil and Fake.asked == 1,
            ('asked %d times'):format(Fake.asked))
        check('not before it has been loose a moment', caughtAt and caughtAt - started >= Config.Ball.autoCatch.delay)
        check('and the one that was loose is gone', Fake.entities[ball] == nil)

        local mine
        for id, e in pairs(Fake.entities) do
            if id ~= ped and not e.anims then mine = id end
        end

        local jump, last = 0.0, nil
        Fake.play(0.8, function()
            local b = ballOf(mine).pos
            if last then jump = math.max(jump, #(b - last)) end
            last = b
        end)

        check('it is gathered into a dribble from where it was', jump < 0.25 and playingNow(ped, 'dribble') ~= nil,
            ('%.3f m in a frame'):format(jump))
        check('nothing bounced off my chest', fxCount('body') == 0)
        check('my own head is where it was', near(head.z, GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0).z, 1e-9))
    end

    do
        fresh(true)
        Fake.server.pickup = false

        local ball = Fake.entity(0.0, 2.6, 3.0)
        BB.sim.launch(ball, vec3(0.0, 2.6, 3.0), vec3(0.0, -3.4, 1.0))
        BB.loose[ball] = { shooter = 2, at = 0 }

        Fake.play(2.2)

        check('a ball the server will not give me is not caught', not BB.isHolding())
        check('and it is not asked for every frame', Fake.asked >= 1 and Fake.asked <= 4, Fake.asked)
    end

    do
        fresh(true)

        local ped = Fake.player

        -- Lying still, close enough that a moving ball would have been caught.
        local ball = Fake.entity(0.0, 0.6, RADIUS)
        Fake.entities[ball].owned = false
        BB.loose[ball] = { shooter = 2, at = 0 }

        Fake.play(1.5)

        check('a ball lying still is not hoovered up', not BB.isHolding() and Fake.asked == 0)
        check('I am offered it', (BB.hints[Config.Text.pickup_ball] or 0) > 10)

        Fake.let(Config.Keys.pickup)

        local jump, last, bent = 0.0, nil, false
        local low = math.huge

        Fake.play(1.4, function()
            if playingNow(ped, 'pickup') then bent = true end

            for id, e in pairs(Fake.entities) do
                if id ~= ped and not e.anims then
                    if last then jump = math.max(jump, #(e.pos - last)) end
                    last = e.pos
                    low = math.min(low, e.pos.z)
                end
            end
        end)

        check('[E] bends down for it', bent)
        check('and comes up with it', BB.isHolding() and Fake.asked == 1)
        check('turned to face where it lay', near(BB.moves.turn(GetEntityHeading(ped), 0.0), 0.0, 1.0), GetEntityHeading(ped))
        check('the ball comes up off the floor into the hands', near(low, RADIUS, 0.02) and jump < 0.25,
            ('from z %.3f, %.3f m in a frame'):format(low, jump))
        check('and is then dribbled', playingNow(ped, 'dribble') ~= nil and not playingNow(ped, 'pickup'))
    end

    ----------------------------------------------------------------------------
    -- A practice ball: bent down for before the server has said anything
    ----------------------------------------------------------------------------
    do
        fresh(true)

        local ped = Fake.player
        local at = vec3(0.8, 0.0, RADIUS)

        check('bending down for a practice ball starts', BB.scoop(at) == true)
        check('and cannot be started twice', BB.scoop(at) == false)

        Fake.play(0.2)
        BB.takeBall()       -- what gk_basketball:giveBall does

        local mine
        for id, e in pairs(Fake.entities) do
            if id ~= ped and not e.anims then mine = id end
        end

        check('the ball I am given starts where the one on the floor was', mine ~= nil
            and #(ballOf(mine).pos - at) < 0.12, mine and ('%.3f m off'):format(#(ballOf(mine).pos - at)))

        Fake.play(1.5)
        check('and ends up dribbled', BB.isHolding() and playingNow(ped, 'dribble') ~= nil)
    end
else
    print('    (no animation pack found on disk; pack checks skipped)')
end

--------------------------------------------------------------------------------
-- Without a pack: the made-up dribble, as before
--------------------------------------------------------------------------------
do
    fresh(false)

    local ped = Fake.player
    local ball = BB.createBall(GetEntityCoords(ped))
    local st = { phase = 0.0 }

    check('no pack, no dribble cycles', BB.anim.gaits() == nil and BB.anim.stance() == nil)

    local r = dribbleFor(ped, ball, st, 3.0)

    -- (This bounce is quickest at the floor, so a frame rarely lands exactly on it.)
    check('the ball still bounces between the hand and the floor', near(r.low, RADIUS, 0.05) and r.jump < 0.2,
        ('lowest %.3f, %.3f m in a frame'):format(r.low, r.jump))
    check('with no animation played for it', #Fake.played == 0)
    check('and is heard', fxCount('dribble') >= 3)

    -- Lining up without a pack just holds the ball; nobody is planted.
    BB.hoops = { { id = 'h', coords = vec3(0.0, 5.0, 3.05) } }
    DeleteEntity(ball)
    BB.takeBall()

    Fake.hold(Config.Keys.aim)
    Fake.play(0.4)

    check('lining up without a pack does not plant you', Fake.disabled[30] == nil and #Fake.played == 0)

    Fake.hold(Config.Keys.shoot)
    Fake.frameOn()
    Fake.let(Config.Keys.shoot)
    Fake.play(1.5)

    local stand = Config.Anims.shoot
    check('and the shot is the stand-in throw', playedLast(ped) and playedLast(ped).name == stand.name, playedLast(ped) and playedLast(ped).name)
    check('which still leaves the hand', not BB.isHolding())
end

--------------------------------------------------------------------------------
-- The 'rings' shot, GTA VI's: hold AIM, hold THROW, let go as the rings meet
--------------------------------------------------------------------------------
do
    local HOOP = { id = 'h', coords = vec3(0.0, 6.0, 3.05) }
    local DIST = 6.0

    --- The last thing said to the page about the reticle's `field`.
    local function reticle(field)
        for i = #Fake.nui, 1, -1 do
            local m = Fake.nui[i]
            if m.action == 'reticle' and m[field] ~= nil then return m[field] end
        end
    end

    --- Me with a ball, the camera on the rim from where the aim camera sits.
    local function ready(tweak)
        fresh(false, tweak)
        BB.hoops = { HOOP }
        Fake.cam, Fake.pitch = 0.0, 11.4
        BB.takeBall()
        Fake.play(0.3)
        return Fake.player
    end

    --- Aims, holds THROW for `frames` frames, lets go. The shot it made, if any.
    local function release(frames, letAimFirst)
        local before = #BB.shots

        Fake.hold(Config.Keys.aim)
        Fake.play(0.4)
        Fake.hold(Config.Keys.shoot)
        Fake.frameOn()
        if letAimFirst then Fake.let(Config.Keys.aim) end
        Fake.play(frames * Fake.frame)
        Fake.let(Config.Keys.shoot)
        Fake.frameOn()
        Fake.let(Config.Keys.aim)
        Fake.play(1.0)

        return #BB.shots > before and BB.shots[#BB.shots] or nil
    end

    local size = BB.ringSize(DIST)
    local meet = math.floor((1.0 - size) * Config.Shot.rings.closeMs / (Fake.frame * 1000) + 0.5) - 1
    local best = BB.timingAccuracy(0, DIST)

    -- Aiming.
    local ped = ready()
    check('rings: holding a ball, the throw and aim keys are on screen',
        (BB.hints[Config.Text.holding_hint_rings] or 0) > 5)

    Fake.hold(Config.Keys.aim)
    Fake.play(0.4)

    local cam = Fake.cams[#Fake.cams]
    check('rings: aiming looks through a camera of its own', Fake.rendering == true and cam ~= nil)
    check('rings: over the right shoulder and behind', cam and cam.pos.x > 0.25 and cam.pos.y < -0.8,
        cam and ('%.2f %.2f %.2f'):format(cam.pos.x, cam.pos.y, cam.pos.z))
    check('rings: the reticle is up', reticle('show') == true)
    check('rings: the rim under it is locked on, its ring sized for the distance',
        type(reticle('target')) == 'number' and near(reticle('target'), size, 1e-6), reticle('target'))
    check('rings: lining up without a pack does not plant you', Fake.disabled[30] == nil)

    Fake.let(Config.Keys.aim)
    Fake.play(0.4)
    check('rings: letting go of aim puts the camera back', Fake.rendering == false and reticle('show') == false)
    check('rings: and keeps the ball', BB.isHolding())

    -- Let go as they meet.
    local shot = release(meet)
    check('rings: letting go as the rings meet is a perfect release at that rim',
        shot and shot.hoop == HOOP and near(shot.accuracy, best, 1e-6), shot and shot.accuracy)
    check('rings: THROW down closed the ring', reticle('close') == true)
    check('rings: the ball has gone, and the camera and the rings with it',
        not BB.isHolding() and Fake.rendering == false and reticle('show') == false)

    -- Early.
    ready()
    shot = release(math.floor(meet * 0.3))
    check('rings: letting go well before they meet is a bad one', shot and shot.hoop == HOOP and shot.accuracy < 0.3,
        shot and shot.accuracy)

    -- Never let go.
    ready()
    Fake.hold(Config.Keys.aim)
    Fake.play(0.4)
    Fake.hold(Config.Keys.shoot)
    Fake.play(Config.Shot.rings.closeMs / 1000 + 0.6)
    check('rings: hang on and the ball goes anyway once the ring has closed', not BB.isHolding())
    shot = BB.shots[#BB.shots]
    check('rings: late', shot and shot.accuracy < 0.2, shot and shot.accuracy)
    Fake.let(Config.Keys.shoot)
    Fake.let(Config.Keys.aim)
    Fake.play(0.6)

    -- From far out too, where the white ring is gone soon after meeting the small yellow one.
    ready()
    BB.hoops = { { id = 'far', coords = vec3(0.0, 11.0, 3.05) } }
    Fake.pitch = 6.8
    Fake.hold(Config.Keys.aim)
    Fake.play(0.4)
    check('rings: a far rim locks on too, with a smaller ring', type(reticle('target')) == 'number'
        and reticle('target') < size, reticle('target'))
    Fake.hold(Config.Keys.shoot)
    Fake.play(Config.Shot.rings.closeMs / 1000 + 0.6)
    shot = BB.shots[#BB.shots]
    check('rings: and hanging on to the end of it is as late as a release gets', shot and shot.hoop
        and shot.accuracy == 0.0, shot and shot.accuracy)
    Fake.let(Config.Keys.shoot)
    Fake.let(Config.Keys.aim)
    Fake.play(0.6)

    -- AIM let go once THROW is down.
    ready()
    shot = release(meet, true)
    check('rings: letting go of AIM after THROW is down still takes the shot', shot and shot.hoop == HOOP)

    -- No rim under the reticle: a throw where the camera looks.
    ready()
    Fake.pitch = -25.0
    Fake.hold(Config.Keys.aim)
    Fake.play(0.3)
    -- (The page starts every reticle with no target, so none is sent.)
    check('rings: nothing under the reticle, nothing locked on', not reticle('target'), reticle('target'))
    Fake.let(Config.Keys.aim)
    shot = release(10)
    check('rings: and letting go throws it', shot and shot.hoop == nil and not BB.isHolding())

    -- THROW without AIM.
    ped = ready()
    Fake.cam = 90.0
    Fake.hold(Config.Keys.shoot)
    Fake.frameOn()
    Fake.let(Config.Keys.shoot)
    Fake.play(1.0)
    shot = BB.shots[#BB.shots]
    check('rings: THROW alone throws the ball', shot and shot.hoop == nil and not BB.isHolding())
    check('rings: the way the camera looks', near(BB.moves.turn(GetEntityHeading(ped), 90.0), 0.0, 1.0),
        GetEntityHeading(ped))

    -- The help box, once.
    fresh(false)
    BB.hoops = { HOOP }
    BB.takeBall()
    Fake.play(2.0)
    local taught = 0
    for _, note in ipairs(BB.notes) do
        if note == Config.Text.rings_help_text then taught = taught + 1 end
    end
    check('rings: the first ball comes with how to shoot', taught == 1, taught)

    Fake.hold(Config.Keys.shoot)
    Fake.frameOn()
    Fake.let(Config.Keys.shoot)
    Fake.play(1.0)
    BB.takeBall()
    Fake.play(2.0)
    taught = 0
    for _, note in ipairs(BB.notes) do
        if note == Config.Text.rings_help_text then taught = taught + 1 end
    end
    check('rings: and only the first (Config.Hud.tutorial = once)', taught == 1, taught)
end

--------------------------------------------------------------------------------
-- With vice_hud: its prompts, help box and feed
--------------------------------------------------------------------------------
do
    fresh(false)
    BB.hoops = { { id = 'h', coords = vec3(0.0, 6.0, 3.05) } }

    local calls = {}
    Fake.resources.vice_hud = 'started'
    exports.vice_hud = setmetatable({}, { __index = function(_, name)
        return function(_, ...) calls[#calls + 1] = { name = name, args = { ... } } end
    end })

    local function made(name, test)
        local n = 0
        for _, c in ipairs(calls) do
            if c.name == name and (not test or test(table.unpack(c.args))) then n = n + 1 end
        end
        return n
    end

    -- A ball lying there.
    Fake.play(0.3, function() BB.look.ball(vec3(1.0, 1.0, 0.12), 'court:1') end)
    check('vice: a ball lying there has its name on it, beside the pickup key',
        made('ShowWorldActions', function(options, _, opts)
            return options[1].label == Config.Text.ball_name and options[1].key == Config.Keys.pickup
                and opts.centred == true and opts.id == 'gk_basketball'
        end) == 1, made('ShowWorldActions'))
    Fake.play(0.5)
    check('vice: and it goes when the ball is out of reach', made('HideWorldActions', function(id)
        return id == 'gk_basketball'
    end) == 1)

    -- Holding one.
    BB.takeBall()
    Fake.play(1.0)
    local first, second
    for _, c in ipairs(calls) do
        if c.name == 'ShowActionPrompt' then
            if not first then first = c.args elseif not second then second = c.args end
        end
    end
    check('vice: THROW, then AIM, in the corner', first and second
        and first[2] == Config.Text.prompt_throw and first[3] == Config.Keys.shoot
        and second[2] == Config.Text.prompt_aim and second[3] == Config.Keys.aim)
    check('vice: put up once, not every frame', made('ShowActionPrompt') == 2, made('ShowActionPrompt'))

    Fake.play(1.0)
    check('vice: the help box says how, with the aim and throw buttons in the line',
        made('ShowHelpText', function(text, _, opts)
            return text == Config.Text.rings_help and opts.keys[1] == Config.Keys.aim and opts.keys[2] == Config.Keys.shoot
        end) == 1)

    Fake.hold(Config.Keys.shoot)
    Fake.frameOn()
    Fake.let(Config.Keys.shoot)
    Fake.play(1.0)
    check('vice: the prompts go with the ball', made('HideActionPrompt', function(id)
        return id == 'gk_basketball:throw' or id == 'gk_basketball:aim'
    end) >= 2)

    -- Baskets.
    BB.look.scored('h', 2, false)
    BB.look.scored('h', 3, true)
    check('vice: each basket is counted in the feed, with the hoop, as one count that goes up',
        made('ShowFeed', function(text, opts)
            return text == Config.Text.scored_count:format(1) and opts.icon == Config.Hud.scoredIcon
                and opts.counter == 'gk_basketball:scored'
        end) == 1 and made('ShowFeed', function(text) return text == Config.Text.scored_count:format(2) end) == 1)
    check('vice: and nothing pops up besides', #BB.notes == 0, #BB.notes)

    BB.takeBall()
    Fake.play(0.2)
    Fake.let(Config.Keys.stow)
    Fake.play(1.5)
    check('vice: putting the ball away starts the count again', BB.look.count() == 0, BB.look.count())
end

print(('carry: %d passed, %d failed'):format(passed, failed))

return failed
