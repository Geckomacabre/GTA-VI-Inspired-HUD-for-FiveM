Config = {}

-- Draws rim circles, scoring cylinders and ball trails near you. Turn on while
-- placing hoops, turn off for production.
Config.Debug = false

--------------------------------------------------------------------------------
-- Ball
--------------------------------------------------------------------------------

Config.Ball = {
    item  = 'basketball',       -- ox_inventory item name. Set to false to disable item use.
    model = `prop_bskball_01`,

    -- Where a ball in the hand sits: out from the palm bone by `offset`, in the
    -- hand's own axes. 28422 = PH_R_Hand, 60309 = PH_L_Hand.
    bone     = 28422,
    boneLeft = 60309,
    offset   = vec3(0.03, 0.0, -0.13),

    radius = 0.12,              -- so a bouncing ball doesn't sink into the floor

    catchRadius   = 1.7,        -- how close you must be to bend down for a ball ([E])
    passCatchRadius = 1.7,      -- a pass thrown to you is caught by itself inside this

    -- A ball that comes to you is caught: a rebound dropping into your arms, a
    -- loose ball bouncing past your hip. No key. Only a ball that is moving, and
    -- that has been loose for `delay` ms, so a shot isn't taken back out of the
    -- shooter's hands as it leaves them and a ball lying still stays where it is
    -- until somebody bends down for it.
    autoCatch = {
        enabled  = true,
        reach    = 0.95,        -- metres from the middle of you, flat
        above    = 1.3,         -- and this far above it: hands over your head
        delay    = 650,
        minSpeed = 0.7,         -- m/s. Slower than this it is lying there: [E]
        maxSpeed = 14.0,        -- faster than this, relative to you, it goes through your hands
    },

    -- Balls lying on every court for anyone to walk up to and pick up ([E]), in
    -- a game or not. A court can say where its own lie (Config.Courts[...].balls);
    -- any other gets this many near its middle. 0 for none. One that has been
    -- picked up is back on the floor after looseRespawn seconds.
    looseBalls   = 2,
    looseRespawn = 12,

    -- Palms closer together than this are holding the ball between them, and
    -- that is where it is drawn. Further apart, it is in the right hand.
    twoHandGap = 0.40,
    renderDistance = 60.0,      -- loose balls further than this are ignored by your client
    despawnAfter  = 180,        -- seconds a loose, untouched ball survives (0 = never)
}

--------------------------------------------------------------------------------
-- Dribbling
--------------------------------------------------------------------------------

-- While you're carrying the ball it isn't glued to your hand: it is dribbled.
--
-- With an animation pack running (Config.Anims.pack) the dribble is the pack's
-- own: a cycle for every pace from standing to a sprint, and the ball leaves
-- the hand, meets the floor and comes back when the animation says it does.
-- Everything from `offset` down to `handAnim` is then unused; those are the
-- settings for the dribble that is made up when there is no pack.
Config.Dribble = {
    enabled = true,             -- false puts the ball back in your hand, statically

    -- How much of the body the pack's dribble takes over.
    --   'auto'  : all of it while you stand still; on the move only the arms
    --             and back, over the game's own walk and run. The game's legs
    --             are what make moving about feel like moving about: they
    --             turn, lean, set off and pull up the way a body does, where a
    --             looped animation can only slide.
    --   'full'  : all of it, always. Feet from the animation, chosen to match
    --             how fast you are moving.
    --   'upper' : arms and back only, always.
    -- /bball_body full | upper | auto switches on the spot, to compare.
    body = 'auto',

    -- How quickly one dribble gives way to another (a change of pace, a stop).
    -- 8 is an eighth of a second and looks like a cut; 2 is half a second.
    blendIn = 3.0,

    -- An opponent this close and you stand lower, over the ball, with the
    -- other arm up (packClips.guarded). Matches only.
    guardRange = 3.2,

    -- How far in front of where the hand let go the ball meets the floor,
    -- metres, standing still and extra per m/s of pace. A dribbler on the move
    -- puts the ball out ahead and runs onto it.
    reach      = 0.05,
    reachSpeed = 0.035,

    -- Where the ball meets the floor, relative to you. y is forward, x is to your
    -- right, z trims the contact point up or down. Floor level is measured from
    -- your feet, not your entity position (which sits about a metre up).
    --
    -- There's no bounce height to set: the top of every bounce is your hand.
    offset = vec3(0.42, 0.22, 0.0),

    idleRate = 1.5,             -- bounces per second standing still
    moveRate = 2.5,             -- bounces per second at a full run
    spin     = 260.0,           -- degrees per second the ball rolls, visual only

    -- Metres the bounce is pushed out in front of you at a full sprint, on top of
    -- offset.y. A dribbler at speed puts the ball ahead and runs onto it; pinned
    -- to your hip it reads as carrying rather than driving. 0 disables.
    lead = 0.9,

    -- Fraction of each bounce the ball rests in your hand before the next push
    -- down. 0 is a continuous bounce with no pause; past about 0.3 you start to
    -- look hesitant on the ball.
    handDwell = 0.18,

    -- Movement set worn while carrying the ball, via SetPedMovementClipset.
    --
    -- 'anim@move_m@trash' walks with one arm hanging low and loose at your side —
    -- the closest thing the base game has to a dribbling stance, and what shipped
    -- basketball resources use for it. 'anim@sports@ballgame@handball@' is the
    -- two-handed carry instead, which looks like you're holding the ball rather
    -- than working it. Set to false to leave your normal walk alone.
    clipset = 'anim@move_m@trash',

    --[[
        Optional extra: pump the arm on top of the clipset.

        GTA has no dribble clip anywhere, so this borrows an unrelated one — it's
        played on the upper body at zero playback rate and its phase is scrubbed
        from the bounce, `from` at the top and `to` at the bottom, locking the arm
        to the ball.

        Off by default, because every stock clip that moves the arm far enough to
        notice also bends the spine, and a ped folding in half after the ball
        looks far worse than a still arm. The bounce already ends in your hand,
        which is what carries the illusion.

        Worth a try anyway if you have an animation pack streamed, or just want to
        experiment: `/bball_hand <dict> <name> [from] [to]` swaps it live while
        you're holding a ball — no restart, no relog — and prints the current
        values to F8 when called bare. Start with a narrow window and widen it
        until the ped starts leaning.

            handAnim = { dict = 'pickup_object', name = 'pickup_low',
                         from = 0.08, to = 0.30 },
    ]]
    handAnim = false,
}

-- GTA's world gravity. Only change this if you've modified gravity server-side;
-- the shot solver uses it to build the arc.
Config.Gravity = 9.8

--------------------------------------------------------------------------------
-- Ball physics
--------------------------------------------------------------------------------

--[[
    A loose ball is not left to the game's prop physics. It is simulated by
    client/physics.lua: air drag, lift from spin, bounces that trade spin for
    travel, a rim that is a real ring, a net, players it can hit, and water it
    floats in. The game is only asked what the world looks like.

    Everything here is in real units, and the defaults are a real basketball's.
    `python tests/run.py` checks the lot away from the game.
]]
Config.Physics = {
    mass = 0.62,                -- kg

    -- Bounce. Dropped from 1.8m onto a hard court a ball comes back to about
    -- 1.15m, which is 0.80. Friction decides how much spin bites.
    restitution    = 0.80,
    friction       = 0.65,
    rollResistance = 0.035,     -- how soon a rolling ball stops. Higher = sooner.

    -- Air. Set magnus to 0 to stop spin bending the flight.
    dragCoeff = 0.47,
    magnus    = 1.0,

    -- The rim. A dead rim (low restitution) is kind; a lively one spits shots out.
    rimRestitution = 0.52,
    rimFriction    = 0.35,
    rimTube        = 0.009,     -- half the thickness of the iron, metres

    -- false leaves rims to the map's own collision everywhere. Normally each
    -- hoop is checked for collision on its ring the first time a ball comes near,
    -- and only given a calculated one if the map has none (/bball_phys shows
    -- which each hoop got).
    calculatedRim = true,

    -- The net: how hard it grabs a ball dropping through, sideways and downward.
    netLength = 0.40,
    netDragH  = 7.0,
    netDragV  = 2.4,

    -- Water. It floats because of what it weighs and the water it pushes aside,
    -- so there's no "float" switch; these shape how it behaves once it's in.
    waterLinear = 4.5,          -- how quickly it stops bobbing
    waveSlide   = 0.55,         -- how readily it slides down the face of a wave. 0 = stays put

    -- Players. The ball bounces off bodies and hands. A hand that is moving
    -- passes that on, which is all a block or a swat is.
    bodyRestitution = 0.35,
    bodyFriction    = 0.5,
    bodyRadius      = 0.28,
    handRadius      = 0.10,
    throwerGrace    = 0.45,     -- seconds a ball passes through whoever threw it

    -- Per-surface behaviour, picked by the map's material where the ball lands.
    -- Anything not matched uses the hard-court numbers above.
    surfaces = {
        wood  = { restitution = 0.83, friction = 0.60, roll = 0.030 },
        metal = { restitution = 0.74, friction = 0.45, roll = 0.030 },
        fence = { restitution = 0.35, friction = 0.60, roll = 0.080 },
        grass = { restitution = 0.52, friction = 0.75, roll = 0.110 },
        dirt  = { restitution = 0.58, friction = 0.75, roll = 0.080 },
        sand  = { restitution = 0.22, friction = 0.90, roll = 0.450 },
        soft  = { restitution = 0.25, friction = 0.90, roll = 0.400 },
    },

    --[[
        true hands the engine the ball's velocity as well as its position, so
        other players' games can carry it smoothly between network updates.
        If balls ever stutter or drift for *other* players, try false: the ball
        is then pinned in place each frame and only its position is sent.
    ]]
    syncVelocity = true,

    -- A ball further than this from the player simulating it is parked where it
    -- is, rather than dropped through ground that hasn't loaded for them.
    maxDistance = 140.0,
}

-- Bounces, the rim, the backboard, the net, catches and splashes; heard by
-- everyone nearby. Recorded sounds are played where html/sounds has them (its
-- manifest.json says which, with indoor and outdoor sets); anything it has none
-- for is synthesised in the browser layer.
Config.Sound = {
    enabled = true,
    volume  = 0.9,              -- 0..1, on top of the player's own SFX volume
    falloff = 9.0,              -- metres at which a sound is at half volume... roughly
    range   = 55.0,             -- not heard (or sprayed) beyond this

    -- Shoes on the court: a squeak (indoors) or a scrape (outdoors) when you
    -- pull up hard or cut sharply with a hoop anywhere near.
    squeaks = true,
}

--------------------------------------------------------------------------------
-- Shooting
--------------------------------------------------------------------------------

Config.Shot = {
    --[[
        How a shot is taken.

        'rings' : GTA VI's. Hold AIM (RMB / left trigger) and the camera comes
                  in over your shoulder with a ring in the middle of the screen;
                  put it on the basket and a smaller yellow ring locks on. Hold
                  THROW (LMB / right trigger) and the white ring closes in; let
                  go as it meets the yellow one. THROW without aiming just
                  throws the ball where you are looking. See `rings` below.
        'timed' : hold SHOOT (LMB / right trigger) and you go up for a jump
                  shot there and then; let go at the top, as the ball leaves
                  your hand. Let go early or hang on too long and it strays.
                  One motion, straight out of the dribble, the way a basketball
                  game plays. Needs the animation pack, which is what knows
                  when the ball leaves; without one this is 'meter'.
        'meter' : the older way. Line up first (see aimToShoot), standing still
                  with a meter swinging up and down, and shoot when it is in
                  the green.
    ]]
    style = 'rings',

    --[[
        For 'rings'. The white ring closes at a steady speed, so letting go
        before or after it meets the yellow one is a timing error in ms like
        the timed shot's, and is judged by `timing` below: inside `perfect`
        is a perfect release, out at `worst` as bad as one gets. The yellow
        ring is bigger close in and smaller far out, so the moment comes
        sooner on an easy shot.

        Measured off the reference footage (1440p): the white ring's radius
        is 45 px; the yellow one's was 22 px on a shot from close in and
        14 px on one from further back down the drive; the white one takes
        about three quarters of a second to close.
    ]]
    rings = {
        radius   = 0.031,       -- the white ring, as a share of screen height
        nearSize = 0.50,        -- the yellow ring at closeRange, as a share of the white one
        farSize  = 0.24,        -- and at farAt metres and beyond
        farAt    = 12.0,
        closeMs  = 750,         -- the white ring, from full size to a point
        settleMs = 350,         -- the yellow ring takes this long to lock on once the basket is under it
        lockAngle = 9.0,        -- degrees off the middle of the screen a rim can be and still be locked on

        -- The camera while aiming: over the right shoulder, closer in.
        camera = {
            enabled = true,
            fov     = 38.0,
            right   = 0.48,     -- metres right of the ped
            up      = 0.58,     -- above the ped's middle
            back    = 1.30,     -- behind, along the line you are looking
            blendMs = 260,
        },
    },

    -- For 'timed': milliseconds either side of the moment the ball leaves.
    timing = {
        perfect = 60,           -- within this, a perfect release
        worst   = 280,          -- this far out or more is as bad as a release gets
        late    = 170,          -- the ball is held no longer than this past its moment
    },

    -- For 'meter':
    -- true  : hold AIM (RMB / left trigger) to line up, then tap SHOOT (LMB / right
    --         trigger) when the meter is in the green. Letting go of aim cancels.
    -- false : hold SHOOT to charge and release it in the green, with no aim step.
    aimToShoot = true,

    -- The meter rises to 1.0 over chargeTime seconds, then falls back down, and
    -- keeps oscillating until you take the shot.
    chargeTime = 0.9,

    -- Release with the meter inside the sweet band for a perfect shot. Accuracy
    -- falls off linearly to 0 at the edges of the band.
    sweetSpot  = 0.82,
    sweetWidth = 0.14,

    -- With aim assist on, the ball is solved onto the hoop you're facing and then
    -- nudged off-target by your accuracy. With it off, the ball just launches
    -- along your camera direction and you aim manually (hard mode).
    aimAssist = true,

    maxRange   = 26.0,          -- beyond this, no hoop is targeted (free throw toss)
    closeRange = 4.0,           -- shots inside this distance ignore the distance penalty

    -- How much raw distance eats into a perfect release. 0 = distance is free,
    -- 1 = a max-range shot is a coin flip even on a perfect release.
    distancePenalty = 0.45,

    -- How far a shot strays from the middle of the rim: metres of spread per
    -- metre of distance at zero accuracy, sideways and long/short. Bell-shaped,
    -- so most misses are near misses.
    --
    -- Tuned against the real rim with `python tests/run.py makes`, which prints
    -- the make percentage for every release quality and distance. At these
    -- values a perfect release is automatic out to the three-point line and
    -- about 85% from 10m; a release 0.8 good is 3 in 4 from the line; a bad one
    -- is a brick from anywhere but under the basket.
    lateralError = 0.040,       -- left/right
    depthError   = 0.046,       -- short/long

    --[[
        Arc shape: the angle, in degrees from the horizontal, that a shot comes
        down onto the rim at.

        This is what decides whether a ball fits. The rim is a real ring now, and
        a ball arriving flat sees it as a narrow slot: below about 35 degrees even
        a dead-centre shot clips the front of the iron. 46 leaves a few
        centimetres either side, which is where real shooters live. Higher is
        more forgiving and hangs in the air longer; lower is quicker and rims out.

        The flight time follows from the angle and the distance (about 1.0s from
        4m, 1.3s from the three-point line) and is capped by flightTimeMax, which
        only matters for heaves from the far end of the court.
    ]]
    entryAngle    = 46.0,
    flightTimeMax = 2.6,

    -- Raises the point the shot is solved onto above the middle of the ring.
    -- Leave at 0: the ball is solved through air and spin exactly, and anything
    -- added here just moves every shot long.
    aimHeightOffset = 0.0,

    -- A defender within contestReach metres, on the basket side of you, takes
    -- this much off your accuracy whether or not they touch the ball. Matches
    -- only; in a kickabout nobody is a defender. 1.0 turns it off.
    contestFactor = 0.70,
    contestReach  = 1.7,

    -- Backspin, radians a second. About two turns a second, like a real shot.
    -- It isn't decoration any more: it lifts the ball slightly in flight, and it
    -- is why a shot that catches the rim or the board dies and drops instead of
    -- kicking away.
    spin = 12.0,

    -- Where the ball leaves you, measured from your head bone and pushed out
    -- along the line of the shot. Not off the hand bone: that ties the release to
    -- whatever the animation is doing and can put the ball behind your shoulder.
    --
    -- The ball passes through its own thrower for the first moment of flight
    -- (Config.Physics.throwerGrace), so this is about looks, not collisions.
    releaseHeight  = 0.22,
    releaseForward = 0.42,

    -- Milliseconds between the shot animation starting and the ball leaving your
    -- hand, so the arm swings first. Your target and accuracy are locked in the
    -- instant you release the key, so this never changes where the shot goes —
    -- only when it looks like it left. /bball_windup <ms> tries values live.
    windUp = 220,
}

--[[
    Drawn on the rim you're locked onto while you line up, so aim assist stops
    being invisible — you can see which basket you have and what it's worth before
    you commit, instead of finding out from the ball.

    Kept deliberately thin. This is not the placement tool's rim rendering: that
    draws the whole scoring cylinder, which is useful stood next to a hoop and
    turns into a green slab over the backboard from anywhere you'd actually shoot
    from. Set to false to aim blind.
]]
Config.AimMarker = {
    colour = { 90, 220, 130 },  -- rgb, matched to the meter's sweet band
    alpha  = 130,               -- rim disc opacity. Higher reads better in daylight

    label       = true,         -- points and range, above the backboard
    labelHeight = 1.35,         -- metres above the rim — needs to clear the board
    labelScale  = 0.5,
}

--[[
    What is on the screen. With vice_hud running, gk_basketball uses its pieces
    and looks like GTA VI's basketball: the ball's name next to a button on a
    ball you can pick up, THROW and AIM in the corner while you have one, the
    help box the first time, "2 scored" in the feed on the right and the
    Focus card for each basket you make outside a match. The rings are drawn
    by this resource either way. Without vice_hud, ox_lib's text box and
    notifications say the same things.
]]
Config.Hud = {
    vice = true,                -- use vice_hud when it is running

    tutorial = 'once',          -- the help box: 'once' a session, 'always' on every pickup, or false
    tutorialMs = 7000,

    scoredFeed = true,          -- "N scored" in the feed for each basket outside a match
    scoredIcon = 'nui://gk_basketball/html/img/hoop.svg',
    scoredMs   = 3500,

    -- Each basket outside a match is this much XP in vice_hud's Focus skill,
    -- with the card that says so ("Focus +2%"). 200 is 2% at the start and
    -- less as the skill climbs, by vice_hud's own curve. 0 for none.
    focusXp = 200,

    -- The "+2" rising over the rim, which the reference has none of. Matches
    -- still get it whatever this says: nothing else there says who scored.
    floatingPoints = false,
}

-- Fixed-power toss used for passes and for shots with no hoop in range.
Config.Toss = {
    minPower = 6.0,
    maxPower = 19.0,            -- at a full meter
    upwardBias = 0.16,          -- lifts the arc so passes don't drill into the floor

    -- Ceiling on how much of your camera pitch feeds the throw. Looking near
    -- straight up would otherwise send a full-power toss into orbit. 0.45 is
    -- about 24 degrees.
    maxLift = 0.45,
}

--------------------------------------------------------------------------------
-- Scoring geometry
--------------------------------------------------------------------------------

Config.Scoring = {
    -- Radius of the rim, to the middle of the iron. This is the ring the ball
    -- physically has to fit through AND the circle a made shot is judged
    -- against; they are the same thing now. A regulation rim is 0.229. A little
    -- over makes up for the hoop markers having been placed by eye. Raise
    -- toward 0.27 for arcade.
    rimRadius = 0.235,

    threePointDistance = 7.0,   -- shot origin at or beyond this scores 3

    cooldown = 1200,            -- ms between scores from one player, anti double-count
    maxTrackTime = 20,          -- seconds a shot stays attributed to its shooter
}

--------------------------------------------------------------------------------
-- Instancing
--------------------------------------------------------------------------------

--[[
    A match runs in its own routing bucket. See server/instance.lua for the bucket range
    and how it was chosen against the rest of this server.

    This has a visible consequence worth knowing before you turn it on: while you are on
    the court you cannot see anyone who is not playing, and they cannot see you. That is
    the trade -- a court with no traffic driving across it, at the cost of not being able
    to watch a match from the sidelines.
]]
Config.Instance = {
    enabled = true,

    -- Ambient peds and traffic inside the instance. Off is the reason to instance.
    population = false,

    -- 'inactive' | 'relaxed' | 'strict'. Leave on 'inactive' unless you have also set
    -- Config.AI.enabled = false -- see the long note in server/instance.lua for why the
    -- stricter settings stop the NPC opponent appearing.
    lockdown = 'inactive',
}

--------------------------------------------------------------------------------
-- Match rules
--------------------------------------------------------------------------------

Config.Match = {
    minPlayers      = 2,
    maxPerTeam      = 5,
    duration        = 300,      -- seconds. 0 = no clock, play to the score limit
    scoreLimit      = 21,       -- first team here wins. 0 = clock only
    countdown       = 5,        -- seconds between start being called and tip-off
    courtRadius     = 40.0,     -- wander further than this and you're dropped
    endScreenTime   = 12,       -- seconds the final score stays up
    winReward       = 0,        -- cash per winning player. 0 = disabled

    -- Let anyone standing on a court grab a ball from the rack without owning the
    -- item. Set false to make the inventory item the only way to get one.
    freeBallsOnCourt = true,

    --[[
        One ball to a match.

        true is a game of basketball: at tip-off the court is cleared down to a
        single ball in somebody's hands, nobody can pull a second one off the rack
        or out of a pocket while one is in play, and after every basket the side
        that was scored on is handed it. Lose it over a fence or out to sea and
        the rack will give out another.

        false is the old shooting contest: everybody has their own ball and
        whoever makes the most wins.
    ]]
    oneBall      = true,
    inboundDelay = 1800,        -- ms between a basket and the other side getting the ball
    teams = {
        home = { label = 'Home', colour = '#4a9eff' },
        away = { label = 'Away', colour = '#ff6b4a' },
    },
}

--------------------------------------------------------------------------------
-- Steals
--------------------------------------------------------------------------------

-- Reaching in on somebody with the ball: [E] when you are empty-handed and
-- close to them. It knocks the ball loose rather than handing it to you.
Config.Steal = {
    enabled = true,

    reach    = 1.9,             -- metres
    chance   = 0.30,            -- per reach, against a dribble
    cooldown = 1400,            -- ms before the same player can reach again

    -- false lets anyone reach in on anyone with a ball, anywhere. true keeps it
    -- to opponents in the same match.
    matchOnly = false,

    -- Against somebody lined up to shoot the ball is in both hands and up high.
    -- The chance is multiplied by this; the place to stop a shot is in the air.
    protectedFactor = 0.35,
}

--------------------------------------------------------------------------------
-- NPC opponent
--------------------------------------------------------------------------------

--[[
    The AI joins a team and plays: it goes after loose balls, works to a spot and
    shoots when it has one, gets between you and the basket when you have it,
    puts its hands up when you line up a shot, and reaches in now and then. It is
    driven by the client of whoever asked for it, because a ped needs a local
    owner to move and animate smoothly; everyone else on the court sees it.

    Honest limits: it doesn't pass, it doesn't set screens, and it defends the
    ball rather than a zone. It is a decent one-on-one opponent and a willing
    team-mate, not a five-man offence.
]]

Config.AI = {
    enabled = true,

    model = `a_m_y_downtown_01`,
    fallbackModel = `a_m_y_beach_01`,

    maxPerCourt = 3,            -- how many NPCs one court will take

    difficulties = {
        {
            id    = 'easy',
            label = 'Easy — Streetballer',
            name  = 'Streetballer',

            moveSpeed = 1.3,        -- ped move blend ratio
            setupTime = 2.6,        -- seconds spent lining up before shooting
            restTime  = 2.2,        -- seconds after a shot before going again

            -- Feeds straight into the same accuracy the human release produces, so
            -- 1.0 is a dead-centre shot and 0.0 is the worst possible release.
            accuracy = 0.42,
            range    = { 2.0, 7.0 },   -- how far out it will shoot from

            -- How often it leaves its feet to contest a shot, and its chance of
            -- knocking the ball loose each time it reaches in on a dribble.
            contest = 0.25,
            steal   = 0.06,
        },
        {
            id    = 'normal',
            label = 'Normal — Baller',
            name  = 'Baller',

            moveSpeed = 2.0,
            setupTime = 1.9,
            restTime  = 1.6,

            accuracy = 0.68,
            range    = { 2.0, 9.0 },

            -- How often it leaves its feet to contest a shot, and its chance of
            -- knocking the ball loose each time it reaches in on a dribble.
            contest = 0.55,
            steal   = 0.13,
        },
        {
            id    = 'hard',
            label = 'Hard — Pro',
            name  = 'Pro',

            moveSpeed = 2.8,
            setupTime = 1.3,
            restTime  = 1.1,

            accuracy = 0.84,
            range    = { 3.0, 11.0 },

            -- How often it leaves its feet to contest a shot, and its chance of
            -- knocking the ball loose each time it reaches in on a dribble.
            contest = 0.85,
            steal   = 0.22,
        },
    },
}

--------------------------------------------------------------------------------
-- Courts
--------------------------------------------------------------------------------

-- Courts are defined by their hoops, which you place in-game with /bball_place
-- and which live in data/hoops.json. A court's centre is the average of its
-- hoops, so you don't configure positions here at all.
--
-- This table is optional and only supplies display names and blips.
--
-- A court that is part of a map rather than something an admin marked out can be
-- described here in full, and then nobody places or removes anything for it:
--
--     requires = { state = ..., value = ... }
--                 the court only exists while that global state has that value
--     hoops    = { { id, team?, coords = vec3 }, ... }
--                 its rims, measured from the map
--     ped      = { model?, coords = vec4(x, y, z, heading) }
--                 somebody stood there to talk to (join, start, add an AI, leave)
--                 instead of a spot on the floor. z is where their feet are.
--     balls    = { vec3, ... }      where its practice balls lie
--     instance = false              play in the open, so people can watch
Config.Courts = {
    -- ['chamberlain'] = { label = 'Chamberlain Hills', blip = true },

    --[[
        The Maze Bank Arena (mzb_arena), when its floor is set up for basketball.

        The arena decides what is on its floor (its own /arena menu, staff only);
        this only follows it. While the show is 'basketball' the court is here,
        with the arena's own baskets as its hoops; when the show changes it is
        gone, and a game in progress ends.

        The rims are measured from the arena's court model: 12.7255 m either side
        of centre on the long axis, 3.05 m above the floor.
    ]]
    ['arena'] = {
        label = 'Maze Bank Arena',
        blip  = false,
        requires = { state = 'mzbShow', value = 'basketball' },
        instance = false,

        hoops = {
            { id = 'arena_home', team = 'home', coords = vec3(-334.0583, -1960.4202, 22.60) },
            { id = 'arena_away', team = 'away', coords = vec3(-314.5617, -1976.7798, 22.60) },
        },

        -- At the side of the court, half way along, facing it.
        ped = { coords = vec4(-329.838, -1975.188, 19.59, 320.0) },

        -- By each free-throw line, and a pair near the attendant.
        balls = {
            vec3(-332.8114, -1964.7300, 19.71),
            vec3(-329.5974, -1960.8998, 19.71),
            vec3(-319.0226, -1976.3002, 19.71),
            vec3(-315.8086, -1972.4700, 19.71),
            vec3(-329.7288, -1973.1910, 19.71),
            vec3(-327.8903, -1974.7337, 19.71),
        },
    },
}

-- Who stands at a court that has a `ped`, unless the court names a model of its own.
Config.Attendant = {
    model    = `a_m_y_runner_01`,
    scenario = 'WORLD_HUMAN_CLIPBOARD',     -- false to just stand there
}

Config.Blip = {
    enabled = true,
    sprite  = 313,
    colour  = 2,
    scale   = 0.75,
}

-- Ace permission needed for /bball_place, /bball_delhoop and /bball_hoops.
-- Grant with: add_ace group.admin gk_basketball.manage allow
Config.ManageAce = 'gk_basketball.manage'

--------------------------------------------------------------------------------
-- Placement tool
--------------------------------------------------------------------------------

Config.Placement = {
    step     = 0.05,    -- metres the marker moves per frame on a nudge
    fineStep = 0.01,    -- while holding LEFT ALT

    flySpeed = 11.0,    -- noclip speed in m/s
    flyBoost = 4.0,     -- multiplier while holding SHIFT
}

--------------------------------------------------------------------------------
-- Controls (see https://docs.fivem.net/docs/game-references/controls/)
--------------------------------------------------------------------------------

-- These are FiveM control ids, not key codes, so every one is already bound to both
-- a key and a gamepad button by the game. The controller equivalents are noted
-- below; nothing extra is needed for pad support.
Config.Keys = {
    aim    = 25,    -- INPUT_AIM       RMB    / left trigger
    shoot  = 24,    -- INPUT_ATTACK    LMB    / right trigger
    pass   = 51,    -- INPUT_CONTEXT   E      / dpad right
    stow   = 47,    -- INPUT_DETONATE  G      / dpad down
    pickup = 51,    -- INPUT_CONTEXT   E      / dpad right
}

--------------------------------------------------------------------------------
-- Animations
--------------------------------------------------------------------------------

-- Every name here was checked against the GTA V animation database (patch v1734)
-- rather than guessed. Set any entry to false to play no animation for that action.
--
-- 'anim@sports@ballgame@handball@' is real and does contain 'ball_idle', a proper
-- holding-a-ball idle. It contains no throw, though — the whole dict is 14 clips of
-- idle/walk/run/sprint/stop while carrying a ball — so the shot falls back to an
-- overhand melee throw, which is what pickle_throwables uses too.
--
-- Also in that dict if you ever want to go further: ball_walk, ball_run, ball_sprint
-- and the ball_wstop_*/ball_rstop_* stops. Driving those off player speed would make
-- carrying the ball look considerably better than a static idle.
--
-- A dict that fails to load is skipped rather than hung on, and an anim name that
-- doesn't exist is given up on after a few attempts instead of retried every frame.
-- There's no `idle` entry any more: carrying the ball is handled by the movement
-- clipset in Config.Dribble, which covers idle, walk, run, sprint and the stops
-- rather than freezing you in a single pose.
Config.Anims = {
    --[[
        A separate resource streaming real basketball animations, if you have
        one. Its clip_index.lua names its clips; packClips says which of them
        stands in for which action here. With the pack running, those replace
        the base-game stand-ins below, and the ball leaves the hand when the
        clip says it does instead of after Config.Shot.windUp. Without it,
        nothing changes.

        The pack's clips were identified by their motion rather than by name,
        and each records how sure that is. Clips it is unsure of are left out
        unless useLowConfidence is true.
    ]]
    pack = 'basketball_assets',
    useLowConfidence = false,

    -- A name on its own is played once through with the whole body. A table
    -- says how: flag 49 is upper body, looping, legs left to the game.
    packClips = {
        -- 'jumpshot_3' gathers for longest before it leaves the floor, which
        -- reads as a jump shot rather than a hop and gives the release a
        -- rhythm to time. 'jumpshot_2' is quicker and the most on-the-spot.
        shoot   = 'jumpshot_3',
        pickup  = 'pickup_1',

        -- Flag 48 is arms and back only, played once: a pass or a reach made on
        -- the move doesn't stop you dead, your legs carry on underneath it.
        pass    = { clip = 'pass_chest_1', flag = 48 },
        steal   = { clip = 'steal_reach_1', flag = 48 },
        contest = { clip = 'def_contest_2', flag = 49, duration = 1100 },

        -- Lining up a shot: knees bent, ball in both hands in front of the hip.
        -- The jump shot starts from this pose, so one runs into the other.
        stance  = 'idle_ball_1',

        -- The dribble, one cycle for each pace. Which is played is decided by
        -- how fast you are moving and the pace each was made at (the pack says),
        -- so the order here doesn't matter. The standing one leans over the
        -- ball with the knees bent ('dribble_idle_1' is bolt upright, if you
        -- would rather stand tall); `guarded` is the low one, right down over
        -- the ball with the other arm up, for when a defender is on you.
        dribble = { 'dribble_idle_3', 'dribble_move_1', 'dribble_move_2', 'dribble_run_1', 'dribble_run_2' },
        guarded = 'dribble_idle_2',
    },

    -- An overhand throw. Tried 'amb@prop_human_movie_bulb@exit' / 'exit' here —
    -- the lightbulb scenario exit that gusti-basketball shoots with — and it
    -- doesn't work: it's a *scenario exit*, so it opens in the raised pose and
    -- unwinds from it, with the hand tracking back over the head rather than
    -- pushing forward. Shots read as being flung from behind you.
    --
    -- /bball_anim shoot <dict> <name> tries others live.
    shoot  = { dict = 'melee@thrown@streamed_core',     name = 'plyr_takedown_front', flag = 48, duration = 700 },
    pass   = { dict = 'mp_common',                      name = 'givetake1_b',         flag = 48, duration = 600 },
    pickup = { dict = 'pickup_object',                  name = 'pickup_low',          flag = 48, duration = 700 },
    stow   = { dict = 'pickup_object',                  name = 'putdown_low',         flag = 48, duration = 700 },
    steal  = { dict = 'mp_common',                      name = 'givetake1_a',         flag = 48, duration = 500 },

    -- An NPC getting its hands up at a shot.
    contest = { dict = 'missminuteman_1ig_2',           name = 'handsup_base',        flag = 49, duration = 1100 },
}

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

Config.Text = {
    pickup_ball     = '[E] Pick up basketball',
    holding_hint    = 'Hold [RMB] Aim  •  [LMB] Shoot  •  [E] Pass  •  [G] Put away',
    holding_hint_timed = 'Hold [LMB] to shoot, let go at the top  •  [E] Pass  •  [G] Put away',
    timing_hint     = 'Let go of [LMB] as the ball leaves your hand',
    timing_perfect  = 'PERFECT RELEASE',
    timing_early    = 'EARLY',
    timing_late     = 'LATE',
    aiming_hint     = 'Press [LMB] in the green  •  let go of [RMB] to cancel',
    aiming_hint_hold = 'Let go of [LMB] in the green',
    aiming_notarget = 'No hoop in your sights  •  this will be a loose throw',

    -- The 'rings' shot and the vice_hud pieces. [[1]] and [[2]] in the help box
    -- are the AIM and THROW buttons, drawn the way vice_hud draws its prompts.
    ball_name       = 'Basketball',
    prompt_throw    = 'Throw',
    prompt_aim      = 'Aim',
    prompt_pass     = 'Pass',
    prompt_steal    = 'Steal',
    rings_help      = 'To shoot, aim with [[1]] and hold [[2]] until the rings overlap, then release.',
    rings_help_text = 'To shoot, aim with [RMB] and hold [LMB] until the rings overlap, then release.',
    holding_hint_rings = '[LMB] Throw  •  Hold [RMB] Aim  •  [E] Pass  •  [G] Put away',
    scored_count    = '%d scored',
    court_join      = 'Join pickup game',
    court_leave     = 'Leave game',
    court_start     = 'Start match',
    court_ball      = 'Grab a basketball',
    court_ai        = 'Add an AI player',

    ai_menu_title   = 'Add an AI player',
    ai_description  = 'Plays for the smaller team: shoots, rebounds, defends.',
    ai_joined       = '%s joined the %s team.',
    ai_full         = 'This court already has enough AI players.',
    ai_failed       = 'Could not spawn the AI player.',
    court_label     = 'Basketball Court',

    joined          = 'You joined the %s team.',
    left            = 'You left the game.',
    already_in      = 'You are already in a game.',
    court_full      = 'That team is full.',
    need_players    = 'Need at least %s players to start.',
    match_starting  = 'Tip-off in %s...',
    match_live      = 'Game on!',
    match_won       = '%s wins %s - %s!',
    match_draw      = 'Draw, %s - %s.',
    left_court      = 'You left the court and were removed from the game.',
    scored          = '%s scores %s!',
    scored_self     = 'You scored %s points!',
    swish           = 'Swish!',
    no_ball         = 'You need a basketball.',
    hands_full      = 'You are already holding a ball.',
    reward          = 'You earned $%s for the win.',

    one_ball        = 'There is already a ball in play on this court.',
    court_closed    = 'The court has been taken up. Game over.',
    possession      = '%s has the ball.',
    steal_hint      = '[E] Steal',
    steal_made      = 'You knocked it loose!',
    steal_missed    = 'You reached and missed.',
    stripped        = 'Stripped!',

    -- Drawn natively as a panel on the left of the screen for the whole placement
    -- session, one array entry per line. Empty strings are spacers.
    --
    -- ~y~ ~w~ ~c~ ~g~ ~r~ are GTA's text colour codes (yellow, white, grey, green,
    -- red). This is deliberately not ox_lib's text UI: that renders markdown and is
    -- built for one-line transient prompts, not a dozen lines that must stay up.
    placement_panel = {
        '~y~PLACING A RIM',
        '',
        '~w~W A S D~c~   fly around',
        '~w~SPACE / CTRL~c~   fly up / down',
        '~w~SHIFT~c~   fly faster',
        '',
        '~w~Arrows~c~ or ~w~NUM 8 2 4 6~c~   move rim',
        '~w~PgUp PgDn~c~ or ~w~NUM + -~c~   rim height',
        '~w~ALT~c~   hold for fine steps',
        '',
        '~g~ENTER~c~ save      ~r~BACKSPACE~c~ cancel',
    },
}
