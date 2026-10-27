--[[
    Ball handling: spawning, holding, shooting, passing and picking up.

    Ownership model
    ---------------
    The ball is a client-created networked object. Whoever holds it owns it, and
    the server tracks two things only: who is currently carrying a ball, and which
    network ids are loose on the floor. That keeps the physics local (so it feels
    responsive) while still stopping a player from conjuring two balls at once.
]]

local held        = nil     -- entity id of the ball attached to my hand
local charging    = false
local charge      = 0.0
local chargeUp    = true
local busy        = false   -- true during an animation we shouldn't interrupt

BB.loose = {}               -- [netId] = { shooter = serverId, at = ms }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function loadModel(model)
    if not IsModelInCdimage(model) then
        print(('^1[gk_basketball]^7 model %s is not in the game files'):format(model))
        return false
    end

    RequestModel(model)

    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(model) do
        if GetGameTimer() > deadline then
            print(('^1[gk_basketball]^7 timed out loading model %s'):format(model))
            return false
        end
        Wait(0)
    end

    return true
end

--- Plays an animation, giving up quietly if the dict never loads. A missing anim
--- should cost you the flourish, not the game.
local function playAnim(cfg, blendIn, onPed)
    if not cfg then return end

    RequestAnimDict(cfg.dict)

    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(cfg.dict) do
        if GetGameTimer() > deadline then return end
        Wait(0)
    end

    TaskPlayAnim(onPed or PlayerPedId(), cfg.dict, cfg.name, blendIn or 4.0, -4.0, cfg.duration or -1, cfg.flag or 48, 0.0, false, false, false)
end

--- Plays one of our animations on any ped. The NPCs use the same strokes you do.
--- @param blendIn number|nil 8.0 for one that starts from the pose the ped is already in
function BB.playAnim(ped, cfg, blendIn)
    playAnim(cfg, blendIn, ped)
end

local function forwardVector()
    local rot = GetGameplayCamRot(2)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local cosX = math.abs(math.cos(x))
    return vec3(-math.sin(z) * cosX, math.cos(z) * cosX, math.sin(x))
end

local function nearestPlayer(radius)
    local me = PlayerPedId()
    local coords = GetEntityCoords(me)
    local best, bestDist

    for _, player in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(player)
        if ped ~= me and DoesEntityExist(ped) then
            local dist = #(coords - GetEntityCoords(ped))
            if dist < (radius or 12.0) and (not bestDist or dist < bestDist) then
                best, bestDist = player, dist
            end
        end
    end

    return best, bestDist
end

function BB.isHolding()
    return held ~= nil and DoesEntityExist(held)
end

--------------------------------------------------------------------------------
-- Shot maths
--------------------------------------------------------------------------------

local P = BB.physics

--[[
    Velocity and spin that bring a ball from `from` down onto `to`.

    The arc is set by the angle the ball arrives at, because that is what decides
    whether it fits: a ball coming in flat sees the rim as a narrow slot and
    clips the front of it, one dropping in steeply sees nearly the whole circle.
    The flight is then solved through the same air and spin the ball will
    actually fly through, so it lands where it was sent.
]]
--- @param arrive number|nil Degrees from the horizontal to arrive at. Defaults to a shot's.
--- @param spinRate number|nil Backspin, rad/s. Defaults to a shot's.
--- @return vector3 velocity, vector3 spin, number time
function BB.solveShot(from, to, arrive, spinRate)
    local shot = Config.Shot
    local prm  = BB.sim.prm

    local dx, dy = to.x - from.x, to.y - from.y
    local dist = math.sqrt(dx * dx + dy * dy)

    local time = BB.clamp(P.flightTime(prm, to.z - from.z, dist, arrive or shot.entryAngle),
        0.25, shot.flightTimeMax)

    local wx, wy, wz = P.backspin(dx, dy, spinRate or shot.spin)
    local vx, vy, vz = P.solveLaunch(prm, from.x, from.y, from.z, to.x, to.y, to.z, time, wx, wy, wz)

    return vec3(vx, vy, vz), vec3(wx, wy, wz), time
end

--- The hoop a shot taken this instant would go to, and how far away it is.
---
--- Shared by the aim marker and the shot itself, and it has to stay that way: run
--- two different queries and the marker becomes a liar, showing you one rim while
--- the ball leaves for another. Lives up here, above shoot(), because a local
--- declared further down the file isn't in scope for it.
local function targetHoop()
    if not Config.Shot.aimAssist then return nil end

    return BB.pickTargetHoop(BB.nearbyHoops(), GetEntityCoords(PlayerPedId()), forwardVector(),
        Config.Shot.maxRange, BB.myTeam)
end

--- Velocity for a loose throw along the camera direction, used when no hoop is
--- targeted and for a pass with nobody to pass to.
local function tossVelocity(fwd, power)
    local toss = Config.Toss

    -- Camera pitch runs to nearly straight up, and multiplying that by full power
    -- launches the ball into orbit — which is most of what "the ball flies too
    -- high" turns out to be whenever aim assist doesn't find a rim.
    local lift = BB.clamp(fwd.z, -0.35, toss.maxLift) + toss.upwardBias

    return vec3(fwd.x * power, fwd.y * power, lift * power)
end

--- What range takes off a release, however good: long range chips away at
--- even a perfect one.
local function rangeFactor(distance)
    local shot = Config.Shot
    local span = math.max(shot.maxRange - shot.closeRange, 0.01)
    local far  = BB.clamp((distance - shot.closeRange) / span, 0.0, 1.0)

    return 1.0 - far * shot.distancePenalty
end

--- Turns a meter release into an accuracy score in 0..1.
local function releaseAccuracy(value, distance)
    local shot = Config.Shot

    local off = math.abs(value - shot.sweetSpot) / shot.sweetWidth
    local acc = BB.clamp(1.0 - off, 0.0, 1.0)

    return acc * rangeFactor(distance)
end

--[[
    Turns the timing of a release into an accuracy score in 0..1.

    `err` is how far from the moment the ball leaves the hand the button was let
    go, in ms: negative early, positive late. Inside `perfect` either way is a
    perfect release; from there it falls away to nothing at `worst`.
]]
function BB.timingAccuracy(err, distance)
    local timing = Config.Shot.timing
    local off = math.abs(err)
    local acc = 1.0

    if off > timing.perfect then
        acc = BB.clamp(1.0 - (off - timing.perfect) / math.max(timing.worst - timing.perfect, 1.0), 0.0, 1.0)
    end

    return acc * rangeFactor(distance)
end

--- Moves the aim point off the rim centre according to how badly you released.
local function scatterAim(from, to, accuracy, distance)
    if accuracy >= 1.0 then return to end

    local dx, dy = to.x - from.x, to.y - from.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then return to end

    local dirX, dirY = dx / len, dy / len
    local perpX, perpY = -dirY, dirX

    -- Same model tests/makes.lua prints its make-percentage table from.
    local lateral, depth = P.scatter(accuracy, distance, Config.Shot.lateralError, Config.Shot.depthError)

    return vec3(
        to.x + perpX * lateral + dirX * depth,
        to.y + perpY * lateral + dirY * depth,
        to.z
    )
end

BB.scatterAim = scatterAim

--------------------------------------------------------------------------------
-- Carrying the ball
--------------------------------------------------------------------------------

--[[
    While you're carrying the ball it isn't parented to your hand: it is put
    where it should be every frame. Attached entities inherit the bone's
    transform exactly, so a glued ball can only ever bob with the hand; it can
    never actually reach the floor.

    With an animation pack the dribble is the pack's. The animation is the clock
    (client/moves.lua): the ball goes down when the hand in the animation pushes
    it and is back when that hand is there to meet it, and which cycle plays
    (standing, walking, jogging, running, sprinting) follows how fast the ped is
    actually moving. Without a pack the ball bounces to a beat of its own beside
    the game's ordinary walk, as it did before there were any basketball
    animations.

    The ball is frozen while carried so engine physics doesn't fight the
    positions we set, and unfrozen the moment it's released.
]]

local M = BB.moves

-- [dict] = ms it was first asked for, or false once given up on. Everything
-- that plays an animation here is called every frame, so a dict that will never
-- load must not be asked for, and waited on, for ever.
local dictAsked = {}

local function dictReady(dict)
    if HasAnimDictLoaded(dict) then return true end

    local asked = dictAsked[dict]
    if asked == false then return false end

    local now = GetGameTimer()

    if not asked then
        dictAsked[dict] = now
        RequestAnimDict(dict)
    elseif now - asked > 10000 then
        dictAsked[dict] = false
        print(('^3[gk_basketball]^7 animation dict %s never loaded'):format(dict))
    end

    return false
end

-- A pack that has just (re)started may have what wasn't there a moment ago.
AddEventHandler('onClientResourceStart', function(resource)
    if resource == Config.Anims.pack then dictAsked = {} end
end)

local clipsetOn     = false
local clipsetToken  = 0

--- Streams the ball-carrying move set in and applies it. Only used for the
--- made-up dribble (no pack): with a pack the legs are either the pack's or the
--- game's ordinary ones, which move better than any carrying walk. The load
--- runs on its own thread: a movement clipset can take several seconds to
--- stream on a cold cache.
local function applyClipset()
    local clipset = Config.Dribble.clipset
    if not clipset or clipsetOn then return end
    if BB.anim.gaits() then return end

    -- Claimed up front so repeated calls don't stack requests. The token lets a
    -- clearClipset() that lands mid-load cancel this apply.
    clipsetOn = true
    clipsetToken = clipsetToken + 1
    local token = clipsetToken

    CreateThread(function()
        RequestAnimSet(clipset)

        local deadline = GetGameTimer() + 10000
        while not HasAnimSetLoaded(clipset) do
            if GetGameTimer() > deadline then
                if token == clipsetToken then clipsetOn = false end
                print(('^3[gk_basketball]^7 movement clipset %s never streamed in'):format(clipset))
                return
            end
            Wait(0)
        end

        if token == clipsetToken and clipsetOn then
            SetPedMovementClipset(PlayerPedId(), clipset, 1.0)
        end
    end)
end

local function clearClipset()
    if not clipsetOn then return end
    clipsetOn = false
    clipsetToken = clipsetToken + 1
    ResetPedMovementClipset(PlayerPedId(), 0.0)
end

--- Floor level under the ped.
---
--- A ped's entity position is the centre of its collision capsule, about a metre
--- off the ground, not its feet. The foot bones are the cheap, reliable way back
--- down, and they stay correct on stairs, slopes and while crouched.
local function feetZ(ped)
    local pedZ = GetEntityCoords(ped).z
    local left  = GetPedBoneCoords(ped, 14201, 0.0, 0.0, 0.0).z     -- SKEL_L_Foot
    local right = GetPedBoneCoords(ped, 52301, 0.0, 0.0, 0.0).z     -- SKEL_R_Foot

    -- Bones sit at the ankle; drop to the sole.
    local z = math.min(left, right) - 0.07

    -- If a bone lookup ever comes back as nonsense, fall back to the nominal
    -- capsule offset rather than dropping the ball through the map.
    if z > pedZ or pedZ - z > 1.6 then return pedZ - 0.98 end

    return z
end

--- Where a ball in the right hand is: out from the palm.
local function palm(ped)
    local off = Config.Ball.offset
    return GetPedBoneCoords(ped, Config.Ball.bone, off.x, off.y, off.z)
end

--- Sets a carried ball down where it belongs this frame, by way of wherever it
--- was if it is still being gathered in (BB.easeBall).
local function put(ball, st, x, y, z)
    local from = st and st.easeFrom

    if from then
        local arrived
        x, y, z, arrived = M.ease(from.x, from.y, from.z, x, y, z, GetGameTimer() - st.easeAt, st.easeFor)
        if arrived then st.easeFrom = nil end
    end

    SetEntityCoordsNoOffset(ball, x, y, z, false, false, false)
end

--[[
    Has a carried ball travel to wherever it is wanted next, rather than turn up
    there: off the floor into the hands, out of a bounce into a two-handed hold.
    A ball that jumps from one place to another between frames is most of what
    makes carrying it look like a prop being moved about.
]]
--- @param st table The carrier's state ({ phase = 0.0 } to begin with)
--- @param ms number How long it takes
--- @param from vector3|nil Where from. Defaults to where the ball is now.
function BB.easeBall(st, ball, ms, from)
    st.easeFrom = from or GetEntityCoords(ball)
    st.easeAt, st.easeFor = GetGameTimer(), ms
end

--------------------------------------------------------------------------------
-- The made-up dribble: no pack
--------------------------------------------------------------------------------

--[[
    Optional arm pump for the made-up dribble, off by default. See
    Config.Dribble.handAnim.

    An upper-body clip is played at zero playback rate and its phase is scrubbed
    from the bounce every frame, which pins the arm to the ball exactly. The
    mechanism works; the problem is the material. GTA has no dribble clip, and
    every stock clip that moves the arm far enough to read also flexes the
    spine. /bball_hand auditions clips.
]]
--- @param st table The bounce state ({ phase })
--- @param rise number 0 with the ball on the floor, 1 with it in the hand
function BB.scrubArm(ped, st, rise)
    local cfg = Config.Dribble.handAnim
    if not cfg then return end

    -- Held still by us and stepped by hand: its own clock mustn't run as well.
    SetEntityAnimSpeed(ped, cfg.dict, cfg.name, 0.0)
    SetEntityAnimCurrentTime(ped, cfg.dict, cfg.name, cfg.from + (cfg.to - cfg.from) * (1.0 - rise))
end

--- @return boolean started
function BB.armStart(ped)
    local cfg = Config.Dribble.handAnim
    if not cfg or not dictReady(cfg.dict) then return false end

    -- 49 = looping + upper body + secondary. Start phase 0; the phase is ours.
    TaskPlayAnim(ped, cfg.dict, cfg.name, 8.0, -8.0, -1, 49, 0.0, false, false, false)

    return true
end

function BB.armStop(ped)
    local cfg = Config.Dribble.handAnim
    if cfg and DoesEntityExist(ped) then StopAnimTask(ped, cfg.dict, cfg.name, -4.0) end
end

local function beatDribble(ped, ball, st)
    local cfg = Config.Dribble

    -- Bounce faster the quicker they're moving, so a sprint looks driven rather
    -- than like the ball is idling alongside.
    local drive = BB.clamp(GetEntitySpeed(ped) / 7.0, 0.0, 1.0)
    local rate  = cfg.idleRate + (cfg.moveRate - cfg.idleRate) * drive

    local before = st.phase
    st.phase = (before + GetFrameTime() * rate) % 1.0

    -- The floor is the midpoint of the part of the bounce that isn't hand.
    local floorAt = (1.0 - cfg.handDwell) * 0.5
    if before < floorAt and st.phase >= floorAt then
        local at = GetEntityCoords(ball)
        BB.playFx('dribble', at.x, at.y, at.z, 3.0 + drive * 2.0)
        TriggerServerEvent('gk_basketball:fx', 'dribble', at.x, at.y, at.z, 3.0 + drive * 2.0)
    end

    -- Hand at phase 0, floor at the midpoint, hand again at the end, then a
    -- short rest in the hand before the next push. Height under gravity is
    -- parabolic in time: slow out of the hand, quickest at the floor.
    local active = 1.0 - cfg.handDwell
    local rise   = 1.0

    if st.phase < active then
        local q = math.abs(2.0 * (st.phase / active) - 1.0)
        rise = 1.0 - (1.0 - q) * (1.0 - q)
    end

    -- The contact point is pushed out ahead as they get moving, and the top of
    -- every bounce is the hand itself, not a fixed height beside them.
    local lead  = cfg.offset.y + drive * cfg.lead
    local hand  = palm(ped)
    local down  = GetOffsetFromEntityInWorldCoords(ped, cfg.offset.x, lead, 0.0)
    local floor = feetZ(ped) + Config.Ball.radius + cfg.offset.z

    put(ball, st,
        down.x + (hand.x - down.x) * rise,
        down.y + (hand.y - down.y) * rise,
        floor  + (hand.z - floor)  * rise)

    SetEntityRotation(ball, (st.phase * cfg.spin) % 360.0, 0.0, GetEntityHeading(ped), 2, true)

    if cfg.handAnim then
        st.arm = st.arm or BB.armStart(ped)
        if st.arm then BB.scrubArm(ped, st, rise) end
    end

    return rise
end

--------------------------------------------------------------------------------
-- The pack's dribble
--------------------------------------------------------------------------------

--[[
    Whose legs a dribble cycle is played on.

    Standing still, the pack's: there is nothing for the game's legs to do, and
    the stance is half of what makes it look like basketball. On the move, the
    game's own. Its walk and run turn, lean into a change of direction, set off
    and pull up the way a body does; a looped animation laid over the whole
    body can only be slid about and spun on the spot, and that is what "stiff"
    looks like. Only the arms and back of the pack's cycle are used then.
]]
local function wholeBody(gait)
    local body = Config.Dribble.body

    if body == 'full' then return true end
    if body == 'upper' then return false end

    return gait.speed <= 0.05
end

--- Starts a dribble cycle on a ped, `at` seconds into it.
local function startCycle(ped, gait, at)
    if not dictReady(gait.dict) then return false end

    -- 33 = looping, and layered over whatever the ped is otherwise doing, so it
    -- can still be walked and run about by its player or its task. 49 adds
    -- "upper body only", which leaves the legs to the game.
    local flag  = wholeBody(gait) and 33 or 49
    local blend = Config.Dribble.blendIn or 3.0

    -- The eighth argument is where in the clip to start, 0..1.
    TaskPlayAnim(ped, gait.dict, gait.name, blend, -blend, -1, flag, at / gait.duration, false, false, false)

    return true
end

--- The cycle for a place in the list: the standing one gives way to the low,
--- guarded one when there is a defender on its ped.
local function gaitAt(gaits, index, guarded)
    local gait = gaits[index]

    if guarded and gait and gait.speed <= 0.05 and gaits.guarded then return gaits.guarded end

    return gait
end

local function cycleDribble(ped, ball, st, gaits)
    local cfg   = Config.Dribble
    local now   = GetGameTimer()
    local speed = GetEntitySpeed(ped)
    local want  = M.pickGait(gaits, speed, st.gait)
    local gait  = st.gait and gaitAt(gaits, st.gait, st.low)
    local wanted = gaitAt(gaits, want, st.guarded)

    if gait and wanted ~= gait then
        -- Between two paces the change waits for the ball to be in the hand, so
        -- a bounce is never cut off half way. To or from standing still it
        -- can't wait: feet that stay planted while the body moves off look far
        -- worse than a ball gathered in a little early.
        local stopStart = (gait.speed <= 0.05) ~= (wanted.speed <= 0.05)

        if stopStart or (st.inHand and now - (st.changedAt or 0) > 300) then
            if not st.inHand then BB.easeBall(st, ball, 140) end
            gait = nil
        end
    end

    if not gait then
        st.gait, st.low, gait = want, st.guarded == true, wanted
        st.changedAt, st.askedAt = now, now
        st.t = gait.entry
        st.inHand, st.away, st.wasFalling, st.playing = true, false, false, false

        startCycle(ped, gait, st.t)
    end

    local rate = M.gaitRate(gait, speed)

    if IsEntityPlayingAnim(ped, gait.dict, gait.name, 3) then
        if st.playing then
            st.t = GetEntityAnimCurrentTime(ped, gait.dict, gait.name) * gait.duration
        else
            -- It has only now started (or started again). It is brought to
            -- where the ball has got to in the meantime, not the ball to it:
            -- an arm that is still blending in can skip a beat unnoticed, a
            -- ball can't.
            st.playing = true
            SetEntityAnimCurrentTime(ped, gait.dict, gait.name, ((st.t or 0.0) % gait.duration) / gait.duration)
        end

        st.askedAt = now

        SetEntityAnimSpeed(ped, gait.dict, gait.name, rate)
    else
        -- Still streaming in, or something of the game's own has cut across it
        -- (a stumble, a climb). Keep time ourselves so the ball carries on, and
        -- ask again.
        st.playing = false
        st.t = ((st.t or 0.0) + GetFrameTime() * rate) % gait.duration

        if now - (st.askedAt or 0) > 350 then
            st.askedAt = now
            startCycle(ped, gait, st.t)
        end
    end

    local inHand, rise, falling = M.bounceAt(gait.bounces, st.t)
    local hand = palm(ped)
    local x, y, z = hand.x, hand.y, hand.z

    if inHand then
        st.away = false
    else
        if not st.away then
            -- Let go this frame. Where from is kept against the ped rather than
            -- the world: the ball goes along with whoever is dribbling it.
            st.away  = true
            st.push  = GetOffsetFromEntityGivenWorldCoords(ped, hand.x, hand.y, hand.z)
            st.reach = cfg.reach + cfg.reachSpeed * speed
        end

        local from  = GetOffsetFromEntityInWorldCoords(ped, st.push.x, st.push.y, st.push.z)
        local spot  = GetOffsetFromEntityInWorldCoords(ped, st.push.x, st.push.y + st.reach, st.push.z)
        local floor = feetZ(ped) + Config.Ball.radius

        if falling then
            -- Down from where the hand let go to its spot on the floor.
            local k = 1.0 - rise

            x = from.x + (spot.x - from.x) * k
            y = from.y + (spot.y - from.y) * k
            z = floor + (math.max(from.z, floor) - floor) * rise
        else
            -- And up to wherever the hand is now. That it ends in the hand, and
            -- not at some height beside it, is what makes it a dribble.
            x = spot.x + (hand.x - spot.x) * rise
            y = spot.y + (hand.y - spot.y) * rise
            z = floor + (math.max(hand.z, floor) - floor) * rise
        end

        if st.wasFalling and not falling then
            local loud = 3.0 + BB.clamp(speed / 7.0, 0.0, 1.0) * 2.0

            BB.playFx('dribble', x, y, floor, loud)
            TriggerServerEvent('gk_basketball:fx', 'dribble', x, y, floor, loud)
        end
    end

    st.inHand, st.wasFalling = inHand, (not inHand) and falling

    put(ball, st, x, y, z)

    st.roll = ((st.roll or 0.0) + GetFrameTime() * cfg.spin) % 360.0
    SetEntityRotation(ball, st.roll, 0.0, GetEntityHeading(ped), 2, true)

    return rise
end

--[[
    Dribbles: advances the bounce and puts the ball where it should be this
    frame, and sees that the ped is doing the dribbling to go with it.

    For anybody with a ball: you, or an NPC this client is driving. `st` carries
    it between frames ({ phase = 0.0 } to begin with).
]]
--- @param team string|nil The dribbler's team in a match, so they can tell when they are being guarded
--- @return number rise 0 with the ball on the floor, 1 with it in the hand
function BB.dribble(ped, ball, st, team)
    local gaits = BB.anim.gaits()

    if not gaits then return beatDribble(ped, ball, st) end

    -- Looked at a few times a second: is there a defender on them?
    local now = GetGameTimer()

    if now - (st.lookedAt or 0) > 300 then
        st.lookedAt = now
        st.guarded = gaits.guarded ~= nil and BB.guarded(ped, team)
    end

    return cycleDribble(ped, ball, st, gaits)
end

--[[
    Is there a defender on this ped?

    An opponent within a couple of strides. It changes how they stand with the
    ball: lower, over it, the other arm up. Only opponents count, so only in a
    match; shooting around on your own you stand easy.
]]
function BB.guarded(ped, team)
    if not team or not BB.match then return false end

    local at = GetEntityCoords(ped)
    local reach = Config.Dribble.guardRange or 3.2

    local function close(other)
        if other == ped or not DoesEntityExist(other) then return false end

        local o = GetEntityCoords(other)
        local dx, dy = o.x - at.x, o.y - at.y

        return dx * dx + dy * dy < reach * reach and math.abs(o.z - at.z) < 1.5
    end

    for _, member in ipairs(BB.match.players or {}) do
        if member.team ~= team and member.id > 0 then
            local player = GetPlayerFromServerId(member.id)
            if player ~= -1 and close(GetPlayerPed(player)) then return true end
        end
    end

    for other, bot in pairs(BB.botPeds or {}) do
        if bot.team ~= team and close(other) then return true end
    end

    return false
end

--- Stops the dribbling a ped is doing for `st`, for whatever comes next: a
--- shot, a pass, the ball going loose.
--- @param quick boolean|nil For when the next thing starts straight away
function BB.dribbleStop(ped, st, quick)
    local gaits = BB.anim.gaits()
    local gait  = gaits and st.gait and gaitAt(gaits, st.gait, st.low)

    if gait and DoesEntityExist(ped) then
        StopAnimTask(ped, gait.dict, gait.name, quick and -8.0 or -4.0)
    end

    st.gait, st.away, st.inHand, st.wasFalling, st.playing = nil, false, true, false, false

    if st.arm then
        st.arm = false
        BB.armStop(ped)
    end
end

--- Puts a ball in somebody's hands: lining up a shot, in the middle of one,
--- coming up off the floor with it.
--- @param st table|nil Their carry state, so a ball being gathered in is eased there
--- @param both boolean|nil true when what they are doing is known to have both hands on the ball
function BB.holdInHand(ped, ball, st, both)
    local right = GetPedBoneCoords(ped, Config.Ball.bone, 0.0, 0.0, 0.0)
    local left  = GetPedBoneCoords(ped, Config.Ball.boneLeft or 60309, 0.0, 0.0, 0.0)

    -- With the palms brought together (a jump shot on its way up, a chest
    -- pass) the ball is between them, not hung off the right one.
    if both or #(right - left) < Config.Ball.twoHandGap then
        put(ball, st, (right.x + left.x) * 0.5, (right.y + left.y) * 0.5, (right.z + left.z) * 0.5)
        return
    end

    local hand = palm(ped)
    put(ball, st, hand.x, hand.y, hand.z)
end

--- Retune the made-up dribble's arm clip without a restart:
--- /bball_hand <dict> <name> [from] [to]
RegisterCommand('bball_hand', function(_, args)
    if BB.anim.gaits() then
        print('^3[gk_basketball]^7 the animation pack is doing the dribbling; /bball_hand is for when there is no pack')
        return
    end

    if not Config.Dribble.handAnim then
        if not args[1] then
            print('^3[gk_basketball]^7 hand anim is off. Turn it on with: /bball_hand <dict> <name> [from] [to]')
            return
        end

        -- Naming a clip is how you switch it on.
        Config.Dribble.handAnim = { dict = '', name = '', from = 0.0, to = 1.0 }
    end

    local cfg = Config.Dribble.handAnim

    if args[1] then
        BB.armStop(PlayerPedId())
        if BB.myCarry then BB.myCarry.arm = false end

        cfg.dict = args[1]
        cfg.name = args[2] or cfg.name
        cfg.from = tonumber(args[3]) or cfg.from
        cfg.to   = tonumber(args[4]) or cfg.to

        -- New clip, so a previous dead end doesn't count against it.
        dictAsked[cfg.dict] = nil
    end

    print(('^2[gk_basketball]^7 hand anim: %s / %s   phase %.2f..%.2f')
        :format(cfg.dict, cfg.name, cfg.from, cfg.to))
end, false)

--- Retune any Config.Anims entry live: /bball_anim <key> <dict> <name> [duration]
--- Auditioning a shot clip otherwise means a resource restart and a walk back to
--- a court for every guess.
RegisterCommand('bball_anim', function(_, args)
    local key = args[1]

    if not key or Config.Anims[key] == nil or type(Config.Anims[key]) == 'string' or key == 'packClips' then
        local keys = {}
        for name, value in pairs(Config.Anims) do
            if name ~= 'packClips' and (value == false or (type(value) == 'table' and value.dict)) then
                keys[#keys + 1] = name
            end
        end
        table.sort(keys)

        print(('^3[gk_basketball]^7 /bball_anim <%s> <dict> <name> [duration]')
            :format(table.concat(keys, '|')))
        return
    end

    if args[2] then
        -- An entry set to false is off; naming a clip switches it back on, but
        -- then there's no existing clip name to fall back on.
        if not Config.Anims[key] then
            if not args[3] then
                print(('^3[gk_basketball]^7 %s is off — give both a dict and a clip name to turn it on'):format(key))
                return
            end

            Config.Anims[key] = { flag = 48, duration = 700 }
        end

        local cfg = Config.Anims[key]
        cfg.dict = args[2]
        cfg.name = args[3] or cfg.name
        cfg.duration = tonumber(args[4]) or cfg.duration
    end

    local cfg = Config.Anims[key]

    if not cfg then
        print(('^3[gk_basketball]^7 %s is off'):format(key))
        return
    end

    print(('^2[gk_basketball]^7 %s: %s / %s   duration %s'):format(key, cfg.dict, cfg.name, cfg.duration))
end, false)

--- How long after the shot animation starts the ball leaves: /bball_windup <ms>
RegisterCommand('bball_windup', function(_, args)
    local ms = tonumber(args[1])
    if ms then Config.Shot.windUp = math.floor(BB.clamp(ms, 0.0, 3000.0)) end

    print(('^2[gk_basketball]^7 shot wind-up: %sms'):format(Config.Shot.windUp))
end, false)

--------------------------------------------------------------------------------
-- Me, with the ball
--------------------------------------------------------------------------------

local myCarry = { phase = 0.0 }

BB.myCarry = myCarry

--- How much of the body the pack's dribble takes over, changed on the spot:
--- /bball_body auto | full | upper. For looking at the difference without a
--- restart; Config.Dribble.body is what is used after one.
RegisterCommand('bball_body', function(_, args)
    local want = args[1]

    if want == 'full' or want == 'upper' or want == 'auto' then
        local ped = PlayerPedId()

        -- Stopped with the old setting, so the next frame starts it with the new.
        BB.dribbleStop(ped, myCarry)
        clearClipset()

        Config.Dribble.body = want

        if BB.isHolding() and Config.Dribble.enabled then applyClipset() end
    end

    print(('^2[gk_basketball]^7 dribble body: %s%s'):format(Config.Dribble.body,
        BB.anim.gaits() and '' or '   (no animation pack running: this has no effect)'))
end, false)

local function updateDribble()
    BB.dribble(PlayerPedId(), held, myCarry, BB.myTeam)
end

local stanceAsked = 0

--[[
    Lining up a shot, one frame of it.

    The dribble is picked up: both hands on the ball, knees bent, squared to the
    basket (the pack's stance; the jump shot starts from the same pose, so one
    runs into the other). And like anybody who has picked up their dribble, you
    are planted until the ball leaves.

    Without a pack none of that exists and the ball is simply held.
]]
--- @param hoop table|nil The basket being lined up, if there is one in range
local function lineUp(ped, hoop)
    local clip = BB.anim.stance()

    if not clip then
        BB.holdInHand(ped, held, myCarry)
        return
    end

    DisableControlAction(0, 30, true)       -- move left / right
    DisableControlAction(0, 31, true)       -- move forward / back
    DisableControlAction(0, 21, true)       -- sprint

    local set = IsEntityPlayingAnim(ped, clip.dict, clip.name, 3)

    if not set then
        local now = GetGameTimer()

        if dictReady(clip.dict) and now - stanceAsked > 300 then
            stanceAsked = now
            TaskPlayAnim(ped, clip.dict, clip.name, 4.0, -4.0, -1, 33, 0.0, false, false, false)
        end
    end

    -- Turned to the basket; with none in range, to where the camera is looking,
    -- since that is where a loose throw will go.
    local at   = GetEntityCoords(ped)
    local want = hoop and GetHeadingFromVector_2d(hoop.coords.x - at.x, hoop.coords.y - at.y)
        or (GetGameplayCamRot(2).z % 360.0)
    local have = GetEntityHeading(ped)

    if math.abs(M.turn(have, want)) > 0.5 then
        SetEntityHeading(ped, M.turnToward(have, want, 540.0 * GetFrameTime()))
    end

    BB.holdInHand(ped, held, myCarry, set)
end

--- Picks the dribble up to line a shot up.
local function gather(ped)
    -- The stance takes the dribble's place when it starts; here the dribble is
    -- only forgotten, so there is no moment with neither.
    myCarry.gait, myCarry.away, myCarry.inHand, myCarry.playing = nil, false, true, false

    if myCarry.arm then
        myCarry.arm = false
        BB.armStop(ped)
    end

    stanceAsked = 0
    BB.easeBall(myCarry, held, 140)
end

--- Stops standing with the ball in both hands.
--- @param quick boolean|nil For a shot, which starts straight away from the same pose
local function leaveStance(ped, quick)
    local clip = BB.anim.stance()

    if clip and IsEntityPlayingAnim(ped, clip.dict, clip.name, 3) then
        StopAnimTask(ped, clip.dict, clip.name, quick and -8.0 or -4.0)
    end
end

--- Changed your mind: back to dribbling.
local function ungather()
    if held and DoesEntityExist(held) then BB.easeBall(myCarry, held, 140) end
end

--------------------------------------------------------------------------------
-- Ball lifecycle
--------------------------------------------------------------------------------

--- Makes a ball for somebody to hold. It is inert until it's thrown: whoever
--- holds it puts it where it should be every frame.
--- @param at vector3
--- @param exact boolean|nil Make it exactly there (a ball being picked up from where it lay)
--- @return number|nil entity
function BB.createBall(at, exact)
    local model = Config.Ball.model
    if not loadModel(model) then return nil end

    local ball = CreateObject(model, at.x, at.y, at.z + (exact and 0.0 or 0.5), true, true, false)
    SetModelAsNoLongerNeeded(model)

    if not ball or ball == 0 then return nil end

    SetNetworkIdCanMigrate(ObjToNet(ball), true)
    SetEntityCollision(ball, false, false)
    FreezeEntityPosition(ball, true)

    if exact then SetEntityCoordsNoOffset(ball, at.x, at.y, at.z, false, false, false) end

    return ball
end

-- Where the next ball I am given is coming from (the floor I am bending down
-- to), for a moment after I started bending: { at, since, grab }.
local reaching = nil

--- Gives me a ball. Called after the server has agreed I may have one.
--- @param from vector3|nil Where it was: it is gathered in from there rather
---        than appearing in the hand. Defaults to wherever I am reaching for one.
--- @param ms number|nil How long the gathering takes
function BB.takeBall(from, ms)
    if BB.isHolding() then return end

    local now = GetGameTimer()

    if not from and reaching and now - reaching.since < 2500 then
        from = reaching.at
        -- In the hands by the time the hands in the animation close on it.
        ms = ms or math.max(120, reaching.grab - (now - reaching.since))
    end

    reaching = nil

    local ball = BB.createBall(from or GetEntityCoords(PlayerPedId()), from ~= nil)
    if not ball then return end

    held = ball

    myCarry.phase = 0.0
    myCarry.gait, myCarry.away, myCarry.inHand, myCarry.arm = nil, false, true, false
    myCarry.easeFrom = nil

    if from then BB.easeBall(myCarry, ball, ms or 200, from) end

    if Config.Dribble.enabled then applyClipset() end

    BB.startHoldLoop()

    if Config.Shot.style == 'rings' then BB.look.tutorial() end
end

--[[
    Bends down for a ball lying on the floor and comes up with it.

    The ball itself is the server's to give. `ask` asks for it and says whether
    the answer was yes; without one it is expected to turn up by itself (the
    practice balls: the server sends gk_basketball:giveBall). Either way it is
    gathered in from `at`, timed to the hands in the animation.
]]
--- @param at vector3 Where the ball is lying
--- @param ask function|nil
--- @return boolean started False if I am in the middle of something else
function BB.scoop(at, ask)
    if busy or BB.isHolding() then return false end

    busy = true

    CreateThread(function()
        local ped = PlayerPedId()
        local me  = GetEntityCoords(ped)

        if BB.dist2d(me, at) > 0.35 then
            SetEntityHeading(ped, GetHeadingFromVector_2d(at.x - me.x, at.y - me.y))
        end

        local clip, _, length, marks = BB.anim.action('pickup')
        local started = GetGameTimer()

        reaching = { at = at, since = started, grab = marks and marks.catch or 300 }

        playAnim(clip)

        if ask then
            if ask() then BB.takeBall() else reaching = nil end
        end

        -- Up with it. The ball may arrive at any point in this, or not at all.
        local ends = started + math.min(length or (clip and clip.duration) or 600, 1200)

        while GetGameTimer() < ends do
            if BB.isHolding() then BB.holdInHand(ped, held, myCarry) end
            Wait(0)
        end

        ClearPedTasks(ped)

        -- Out of both hands and into a dribble without a jump.
        if BB.isHolding() then BB.easeBall(myCarry, held, 120) end

        busy = false
    end)

    return true
end

--[[
    Where the ball leaves you.

    With a real animation it leaves from where the animation has it: out of the
    hands, at the top of the jump. That is checked rather than trusted, because a
    clip that never started (still streaming, cut across by something) leaves
    the ball wherever the dribble had got to, and a shot must not start from the
    floor beside your foot.

    Failing that, and always for the base-game stand-ins, it is anchored to your
    own body and pushed out along the line of the throw. Driving it off the hand
    bone tied the release to the clip, and a stand-in whose hand tracks back over
    the head put the ball behind the shoulder, so shots looked flung from behind.

    Flattened to the ground plane on purpose: "out in front of me" shouldn't move
    up and down with camera pitch, and the offset has to stay big enough
    horizontally to clear your own collision capsule or the throw gets eaten.
]]
--- @param ball number|nil The ball, if what is being played knows where it is
--- @param towards vector3|nil Direction it is going. Defaults to the camera's.
--- @param kind string|nil 'shot' leaves from above the head, 'pass' from anywhere in the hands
function BB.releasePoint(ped, ball, towards, kind)
    local shot = Config.Shot
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)      -- SKEL_Head

    if ball and DoesEntityExist(ball) then
        local at = GetEntityCoords(ball)
        local dx, dy = at.x - head.x, at.y - head.y
        local flat = math.sqrt(dx * dx + dy * dy)

        if kind == 'shot' and at.z > head.z - 0.12 and at.z < head.z + 0.9 and flat < 0.75 then
            return at
        end

        if kind == 'pass' and at.z > head.z - 0.85 and at.z < head.z + 0.7 and flat < 1.0 then
            return at
        end
    end

    local dir = towards or forwardVector()
    local len = math.sqrt(dir.x * dir.x + dir.y * dir.y)

    if len < 0.0001 then
        return vec3(head.x, head.y, head.z + shot.releaseHeight)
    end

    return vec3(
        head.x + (dir.x / len) * shot.releaseForward,
        head.y + (dir.y / len) * shot.releaseForward,
        head.z + shot.releaseHeight
    )
end

--- Lets go of the ball and hands it to the physics.
--- @param velocity vector3
--- @param from vector3 Release point, from BB.releasePoint
--- @param spin vector3|nil
--- @return number|nil netId
local function launch(velocity, from, spin)
    if not BB.isHolding() then return end

    local ball = held
    local ped  = PlayerPedId()
    held = nil

    clearClipset()
    BB.dribbleStop(ped, myCarry)

    DetachEntity(ball, true, true)

    -- Check there is actually clear air between your head and the release
    -- point, or a shot with a wall in front of you starts on the other side of
    -- the wall.
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    from = BB.sim.clearPoint(vec3(head.x, head.y, head.z + 0.1), from)

    -- The ball passes through its thrower for a moment (Config.Physics.throwerGrace);
    -- it starts inside arm's reach of them, and would otherwise come straight
    -- back off their own hands.
    BB.sim.launch(ball, from, velocity, spin, ped)

    return ObjToNet(ball)
end

--- Lets the ball fall out of your hands: into the water with you, because
--- something knocked you over, or because somebody reached in and got a hand on
--- it. It keeps the speed you were moving at.
--- @param knock vector3|nil Extra velocity, for a ball that was knocked rather than dropped
local function fumble(knock)
    if not BB.isHolding() then return end

    local ped = PlayerPedId()
    local at  = GetEntityCoords(held)
    local vel = GetEntityVelocity(ped)

    if knock then vel = vel + knock end

    local netId = launch(vec3(vel.x, vel.y, vel.z + 0.5), at)

    if netId then
        TriggerServerEvent('gk_basketball:ballReleased', netId)
    end
end

--- A knocked-loose ball goes somewhere nobody chose: out sideways, a little up.
function BB.knockVelocity()
    local a = math.random() * 2.0 * math.pi
    local speed = 1.8 + math.random() * 1.6

    return vec3(math.cos(a) * speed, math.sin(a) * speed, 1.2 + math.random() * 1.0)
end

--[[
    Is somebody in this shooter's face?

    A defender within arm's reach and on the basket side takes something off the
    shot whether or not they get a hand on the ball. Only opponents count, which
    means only in a match: in a kickabout there are no sides.
]]
--- @param ped number The shooter
--- @param team string|nil The shooter's team
--- @param toward vector3 Where the shot is going
function BB.contested(ped, team, toward)
    if not team or not BB.match then return false end

    local at = GetEntityCoords(ped)
    local dx, dy = toward.x - at.x, toward.y - at.y
    local reach = Config.Shot.contestReach

    local function inFace(other)
        if other == ped or not DoesEntityExist(other) then return false end

        local o = GetEntityCoords(other)
        local ox, oy = o.x - at.x, o.y - at.y

        return ox * ox + oy * oy < reach * reach and math.abs(o.z - at.z) < 1.5 and ox * dx + oy * dy > 0.0
    end

    for _, member in ipairs(BB.match.players or {}) do
        if member.team ~= team and member.id > 0 then
            local player = GetPlayerFromServerId(member.id)
            if player ~= -1 and inFace(GetPlayerPed(player)) then return true end
        end
    end

    for other, bot in pairs(BB.botPeds or {}) do
        if bot.team ~= team and inFace(other) then return true end
    end

    return false
end

--- The moment between starting a throw and the ball leaving. The ball is in the
--- hands for it, following them, rather than left hanging wherever the last
--- bounce of the dribble had got to.
--- @param ms number
local function windUp(ms)
    local leaves = GetGameTimer() + ms
    local ped = PlayerPedId()

    while GetGameTimer() < leaves do
        if not BB.isHolding() then return end       -- knocked out of your hands mid-shot
        BB.holdInHand(ped, held, myCarry)
        Wait(0)
    end
end

--- /bball_shotdebug prints what each shot actually solved. A missed shot looks
--- the same from outside whether aim assist picked the wrong rim, picked nothing,
--- or picked correctly and the arc was off — this says which.
local shotDebug = false

RegisterCommand('bball_shotdebug', function()
    shotDebug = not shotDebug
    print(('^2[gk_basketball]^7 shot debug %s'):format(shotDebug and 'on' or 'off'))
end, false)

--- Turns a ped to face a point, at once.
local function faceTo(ped, x, y)
    local at = GetEntityCoords(ped)
    local dx, dy = x - at.x, y - at.y

    if dx * dx + dy * dy > 0.04 then SetEntityHeading(ped, GetHeadingFromVector_2d(dx, dy)) end
end

--[[
    The end of a shot.

    Once the shooter's feet are back on the floor the rest is theirs. Stand and
    watch it and the follow-through is held, arm up, the way a shooter holds it;
    touch the stick and it is let go at once, eased out rather than cut. A real
    clip only: a base-game stand-in has no follow-through and is cut off as it
    always was.

    `busy` is given up at the landing, not at the end, so a rebound that comes
    straight back can be caught while the arm is still up.
]]
--- @param started number GetGameTimer() when the shot's animation was started
local function followThrough(ped, clip, started, releaseAt, clipLength, marks)
    if not (clip and releaseAt and clipLength) then
        Wait(400)
        ClearPedTasks(ped)
        busy = false
        return
    end

    local land = started + (marks and marks.land or releaseAt + 300) + 120

    while GetGameTimer() < land do Wait(0) end

    busy = false

    local ends = started + clipLength - 250

    while GetGameTimer() < ends and IsEntityPlayingAnim(ped, clip.dict, clip.name, 3) do
        local x, y = GetControlNormal(0, 30), GetControlNormal(0, 31)

        -- Wanting to move, or having a ball again, ends it.
        if x * x + y * y > 0.09 or busy or BB.isHolding() then break end

        Wait(0)
    end

    StopAnimTask(ped, clip.dict, clip.name, -3.0)
end

--- Shoots at the hoop you're facing, or tosses the ball if there isn't one.
--- @param value number 0..1, the meter where it was let go (and a toss's power)
--- @param ring table|nil A 'rings' release, already judged: { hoop, distance, accuracy }
---   for a shot at the basket under the reticle, or { toss = 0..1 } for a throw
---   where the camera looks
local function shoot(value, ring)
    if not BB.isHolding() then
        busy = false
        return
    end

    busy = true

    local ped    = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local fwd    = forwardVector()
    local shot   = Config.Shot

    -- Target and accuracy are locked in at the moment you released the key, before
    -- the wind-up, so the animation delay can't change the outcome of your shot.
    -- Same lookup the aim marker was drawing, so you get the rim you were shown.
    local hoop, distance, accuracy

    if ring then
        hoop, distance, accuracy = ring.hoop, ring.distance, ring.accuracy or 0.0
        if ring.toss then value = ring.toss end
    else
        hoop, distance = targetHoop()
        accuracy = hoop and releaseAccuracy(value, distance) or 0.0
    end

    -- A hand in your face costs you, however good the release was.
    if hoop and BB.contested(ped, BB.myTeam, hoop.coords) then
        accuracy = accuracy * shot.contestFactor
    end

    -- A real jump shot knows when the ball leaves the hand. A stand-in doesn't,
    -- and gets the configured wind-up.
    local clip, releaseAt, clipLength, marks = BB.anim.action('shoot')

    -- A jump shot goes where the shooter is facing. A throw goes where the
    -- camera is looking, so the thrower turns that way.
    if hoop then
        faceTo(ped, hoop.coords.x, hoop.coords.y)
    elseif ring and ring.toss then
        faceTo(ped, origin.x + fwd.x, origin.y + fwd.y)
    end

    -- Whatever was being done with the ball gives way to the shot: out of the
    -- two-handed stance (which the jump shot starts in, so quickly), or
    -- straight out of a dribble, the ball gathered in on the way.
    leaveStance(ped, true)
    BB.dribbleStop(ped, myCarry, true)
    BB.easeBall(myCarry, held, 110)

    local began = GetGameTimer()

    playAnim(clip, releaseAt and 8.0 or nil)
    windUp(releaseAt or shot.windUp)

    -- Out of the hands where the animation has them; otherwise from a point on
    -- the line to the basket, so it can never look like it left from behind you.
    local release = BB.releasePoint(ped, releaseAt and held or nil, hoop
        and vec3(hoop.coords.x - origin.x, hoop.coords.y - origin.y, 0.0)
        or nil, 'shot')

    local netId
    local v, flight = vec3(0.0, 0.0, 0.0), 0.0

    if hoop then
        local target = vec3(hoop.coords.x, hoop.coords.y, hoop.coords.z + shot.aimHeightOffset)
        local aim    = scatterAim(release, target, accuracy, distance)
        local spin

        v, spin, flight = BB.solveShot(release, aim)
        netId = launch(v, release, spin)
    else
        -- No hoop in range: straight camera-direction toss, power from the meter.
        local toss  = Config.Toss
        local power = toss.minPower + (toss.maxPower - toss.minPower) * value

        v = tossVelocity(fwd, power)
        netId = launch(v, release, vec3(P.backspin(fwd.x, fwd.y, shot.spin * 0.5)))
    end

    if netId then
        BB.trackShot(netId, origin, hoop, accuracy)
        TriggerServerEvent('gk_basketball:ballReleased', netId)
    end

    if shotDebug then
        if hoop then
            print(('^2[gk_basketball]^7 hoop %s  dist %.1fm  rim z %.2f  release z %.2f  flight %.2fs  accuracy %.2f  vel %.1f/%.1f/%.1f')
                :format(hoop.id, distance, hoop.coords.z, release.z, flight, accuracy, v.x, v.y, v.z))
        else
            print(('^3[gk_basketball]^7 NO TARGET — loose toss at meter %.2f  vel %.1f/%.1f/%.1f')
                :format(value, v.x, v.y, v.z))
        end
    end

    followThrough(ped, clip, began, releaseAt, clipLength, marks)
end

--- Is this animation one that is laid over whatever the ped is doing (the
--- "secondary" flag), rather than taking the ped over?
local function layered(cfg)
    return cfg and ((cfg.flag or 48) & 32) ~= 0 or false
end

--- Passes to the nearest player.
local function pass()
    if not BB.isHolding() then return end

    busy = true

    local target = nearestPlayer(20.0)
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local toPed  = target and GetEntityCoords(GetPlayerPed(target)) or nil

    local clip, releaseAt = BB.anim.action('pass')

    -- A pass comes out of both hands. Stood still, the passer turns to who it
    -- is for; on the run they pass off the move and keep going.
    if toPed and GetEntitySpeed(ped) < 1.0 then faceTo(ped, toPed.x, toPed.y) end

    BB.dribbleStop(ped, myCarry, true)
    BB.easeBall(myCarry, held, 100)

    playAnim(clip, releaseAt and 8.0 or nil)
    windUp(releaseAt or Config.Shot.windUp)

    local fwd = forwardVector()

    -- Same rule as a shot: out of the hands, or failing that along the line the
    -- ball is going.
    local release = BB.releasePoint(ped, releaseAt and held or nil, toPed
        and vec3(toPed.x - coords.x, toPed.y - coords.y, 0.0)
        or nil, 'pass')

    local netId

    if target then
        -- A chest pass: flat and quick up close, more air under it over distance.
        -- Led by where they'll be when it gets there, so a pass to a runner
        -- arrives in front of them rather than behind.
        local targetPed = GetPlayerPed(target)

        toPed = GetEntityCoords(targetPed)

        local lead = GetEntityVelocity(targetPed) * BB.clamp(#(toPed - coords) / 12.0, 0.0, 0.8)
        local dest = toPed + lead + vec3(0.0, 0.0, 0.35)
        local arrive = BB.clamp(#(dest - release) * 2.5 + 6.0, 10.0, 35.0)
        local v, spin = BB.solveShot(release, dest, arrive, Config.Shot.spin * 0.4)

        netId = launch(v, release, spin)
    else
        netId = launch(tossVelocity(fwd, Config.Toss.minPower), release)
    end

    if netId then
        BB.trackShot(netId, GetEntityCoords(ped), nil, 0.0)

        -- Naming who it was for lets their game catch it without a key press.
        TriggerServerEvent('gk_basketball:ballReleased', netId, target and GetPlayerServerId(target) or nil)
    end

    Wait(350)

    -- An animation that was only laid over the arms plays itself out; clearing
    -- the ped's tasks for it would trip up legs that never stopped.
    if not layered(clip) then ClearPedTasks(ped) end

    busy = false
end

--- Puts the ball back in your inventory, or just drops it if that fails.
local function stow()
    if not BB.isHolding() then return end

    busy = true

    local ped = PlayerPedId()

    clearClipset()
    BB.dribbleStop(ped, myCarry)
    BB.easeBall(myCarry, held, 140)

    playAnim((BB.anim.action('stow')))
    windUp(650)

    local ball = held
    held = nil

    if ball and DoesEntityExist(ball) then
        DeleteEntity(ball)
        TriggerServerEvent('gk_basketball:stowBall')
    end

    -- Done shooting around: the next basket is "1 scored" again.
    BB.look.resetCount()

    ClearPedTasks(ped)
    busy = false
end

--------------------------------------------------------------------------------
-- Hold loop: draws the power meter and reads the controls
--------------------------------------------------------------------------------

--[[
    Lights up the rim you're locked onto.

    Deliberately not BB.drawRim. That one stacks six translucent spheres to show
    the scoring cylinder, which is exactly right when you're stood a metre away
    placing a hoop — and from out on the arc those spheres pack into a solid slab
    that covers the backboard you're trying to aim at.

    An aiming marker has one job and a hard constraint: say which rim without
    hiding it. So: a thin disc on the rim plane itself, and a label parked above
    the backboard where there's nothing to obscure.
]]
local function drawAimMarker(hoop, distance)
    local cfg = Config.AimMarker
    if not cfg or not hoop then return end

    local c = hoop.coords
    local r, g, b = cfg.colour[1], cfg.colour[2], cfg.colour[3]
    local size = Config.Scoring.rimRadius * 2.0

    -- Sits in the rim plane, so from below — where you shoot from — it outlines
    -- the hole rather than blocking it.
    DrawMarker(25, c.x, c.y, c.z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        size, size, size, r, g, b, cfg.alpha, false, false, 2, false)

    if not cfg.label then return end

    SetTextScale(0.0, cfg.labelScale)
    SetTextFont(4)
    SetTextColour(r, g, b, 225)
    SetTextOutline()
    SetTextCentre(true)
    SetDrawOrigin(c.x, c.y, c.z + cfg.labelHeight, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(('%d PT   %.1fm'):format(
        distance >= Config.Scoring.threePointDistance and 3 or 2, distance))
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

--- @param value number 0..1, how full
--- @param spot number 0..1, the middle of the green band
--- @param width number Half the width of the green band, as a share of the bar
--- @param mark number|nil 0..1, where the button was let go, once it has been
local function drawMeter(value, spot, width, mark)
    local w, h = 0.16, 0.014
    local x, y = 0.5, 0.86

    -- Track
    DrawRect(x, y, w + 0.006, h + 0.006, 0, 0, 0, 160)
    DrawRect(x, y, w, h, 40, 40, 44, 220)

    -- Sweet band
    local bandW = (width * 2.0) * w
    local bandX = (x - w / 2) + spot * w
    DrawRect(bandX, y, bandW, h, 90, 220, 130, 110)

    -- Fill
    if value > 0.0 then
        DrawRect((x - w / 2) + (value * w) / 2, y, value * w, h, 255, 190, 60, 235)
    end

    -- Release marker: where the fill has got to, or where it was let go.
    DrawRect((x - w / 2) + (mark or value) * w, y, 0.0025, h + 0.008, 255, 255, 255, 255)
end

--- Advances the oscillating meter one frame.
local function tickMeter()
    local step = GetFrameTime() / Config.Shot.chargeTime
    charge = charge + (chargeUp and step or -step)

    if charge >= 1.0 then
        charge, chargeUp = 1.0, false
    elseif charge <= 0.0 then
        charge, chargeUp = 0.0, true
    end
end

--- Everything drawn while you're lining a shot up: the meter, the rim you have,
--- and a hint that tells you which of those two situations you're in.
--- @return table|nil hoop The basket being lined up
local function showAim()
    drawMeter(charge, Config.Shot.sweetSpot, Config.Shot.sweetWidth)

    local hoop, distance = targetHoop()

    if hoop then
        drawAimMarker(hoop, distance)
        BB.showHint(Config.Shot.aimToShoot and Config.Text.aiming_hint
            or Config.Text.aiming_hint_hold or Config.Text.aiming_hint)
    else
        BB.showHint(Config.Text.aiming_notarget)
    end

    return hoop
end

--- A word on the screen for a moment after a timed shot: how the release was.
local function flashRelease(text, r, g, b)
    CreateThread(function()
        local until_ = GetGameTimer() + 900

        while GetGameTimer() < until_ do
            SetTextScale(0.0, 0.42)
            SetTextFont(4)
            SetTextColour(r, g, b, 235)
            SetTextOutline()
            SetTextCentre(true)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(text)
            EndTextCommandDisplayText(0.5, 0.875)
            Wait(0)
        end
    end)
end

--[[
    The timed shot: hold the button and you go up, let go as the ball leaves.

    One motion straight out of the dribble: the ball is gathered into both
    hands as the jump shot starts, you turn to the basket on the way up, and
    the ball goes when the animation lets it go. What your thumb decides is how
    good the release was. Let go early and the ball still leaves at its moment,
    but astray; hang on and it leaves late, when you do let go, and no later
    than `late` after its moment.
]]
local function timedShot()
    if not BB.isHolding() then
        busy = false
        return
    end

    busy = true

    local ped    = PlayerPedId()
    local keys   = Config.Keys
    local shot   = Config.Shot
    local timing = shot.timing
    local origin = GetEntityCoords(ped)
    local fwd    = forwardVector()

    -- The basket is the one you were facing when you went up.
    local hoop, distance = targetHoop()

    local clip, releaseAt, clipLength, marks = BB.anim.action('shoot')
    releaseAt = releaseAt or shot.windUp

    leaveStance(ped, true)
    BB.dribbleStop(ped, myCarry, true)
    BB.easeBall(myCarry, held, 140)

    playAnim(clip, 6.0)

    -- Eyes on the rim.
    if hoop then
        TaskLookAtCoord(ped, hoop.coords.x, hoop.coords.y, hoop.coords.z, clipLength or 1500, 0, 2)
    end

    local started = GetGameTimer()
    local latest  = releaseAt + timing.late
    local upAt    = nil

    while true do
        if not BB.isHolding() then      -- knocked out of your hands on the way up
            ClearPedTasks(ped)
            busy = false
            return
        end

        local e = GetGameTimer() - started

        -- Nothing else this button, or the ones beside it, would do just now.
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)
        DisableControlAction(0, 22, true)

        if hoop then
            -- Squared up over the first part of the gather, not snapped round.
            if e < 320 then
                local at   = GetEntityCoords(ped)
                local want = GetHeadingFromVector_2d(hoop.coords.x - at.x, hoop.coords.y - at.y)
                local have = GetEntityHeading(ped)

                if math.abs(M.turn(have, want)) > 0.5 then
                    SetEntityHeading(ped, M.turnToward(have, want, 720.0 * GetFrameTime()))
                end
            end

            drawAimMarker(hoop, distance)
        end

        BB.holdInHand(ped, held, myCarry)

        if not upAt and not IsDisabledControlPressed(0, keys.shoot) then upAt = e end

        drawMeter(math.min(e / latest, 1.0), releaseAt / latest, timing.perfect / latest, upAt and upAt / latest)
        BB.showHint(Config.Text.timing_hint)

        -- It leaves at its moment, or when you let go if that is later.
        if e >= releaseAt and (upAt or e >= latest) then break end

        Wait(0)
    end

    local err = (upAt or latest) - releaseAt
    local accuracy = hoop and BB.timingAccuracy(err, distance) or 0.0

    -- A hand in your face costs you, however good the release was.
    if hoop and BB.contested(ped, BB.myTeam, hoop.coords) then
        accuracy = accuracy * shot.contestFactor
    end

    if math.abs(err) <= timing.perfect then
        flashRelease(Config.Text.timing_perfect, 90, 220, 130)
    else
        flashRelease(err < 0 and Config.Text.timing_early or Config.Text.timing_late, 255, 190, 60)
    end

    local release = BB.releasePoint(ped, held, hoop
        and vec3(hoop.coords.x - origin.x, hoop.coords.y - origin.y, 0.0)
        or nil, 'shot')

    local netId
    local v, flight = vec3(0.0, 0.0, 0.0), 0.0

    if hoop then
        local target = vec3(hoop.coords.x, hoop.coords.y, hoop.coords.z + shot.aimHeightOffset)
        local aim    = scatterAim(release, target, accuracy, distance)
        local spin

        v, spin, flight = BB.solveShot(release, aim)
        netId = launch(v, release, spin)
    else
        -- No hoop in range: a middling throw to where the camera is looking.
        local toss  = Config.Toss
        local power = toss.minPower + (toss.maxPower - toss.minPower) * 0.5

        v = tossVelocity(fwd, power)
        netId = launch(v, release, vec3(P.backspin(fwd.x, fwd.y, shot.spin * 0.5)))
    end

    if netId then
        BB.trackShot(netId, origin, hoop, accuracy)
        TriggerServerEvent('gk_basketball:ballReleased', netId)
    end

    if shotDebug then
        print(('^2[gk_basketball]^7 timed shot: let go %+d ms from the moment (%s)  accuracy %.2f  hoop %s  dist %.1fm  release z %.2f  flight %.2fs')
            :format(math.floor(err), upAt and 'by hand' or 'held too long', accuracy, hoop and hoop.id or 'none',
                distance or 0.0, release.z, flight))
    end

    followThrough(ped, clip, started, releaseAt, clipLength, marks)

    TaskClearLookAt(ped)
end

local function takeShot()
    local value = charge
    charging, charge = false, 0.0

    -- Claimed here rather than when the shot's own thread gets going, so the
    -- loop below can't start lining up another one in the frame between.
    busy = true

    CreateThread(function() shoot(value) end)
end

--[[
    The 'rings' shot (Config.Shot.style), as GTA VI has it.

    Hold AIM: the camera comes in over the shoulder (client/aimcam.lua) with a
    white ring in the middle of the screen. Put a rim under it and a smaller
    yellow ring locks on, bigger the closer the shot. Hold THROW and the white
    ring closes in; let go as it meets the yellow one. It closes at a steady
    speed, so how far it was from the yellow one when you let go is a timing
    error in ms, judged exactly as the timed shot's is (BB.timingAccuracy).
    With no rim under it, letting go throws the ball where you are looking,
    harder the longer THROW was held. Hang on until the white ring has closed
    to nothing and the ball goes anyway, late.
]]
local aim = nil     -- while aiming: { hoop, distance, size, closing = ms THROW went down }

--- The rim under the reticle, if there is one in range.
local function inSights()
    local shot = Config.Shot
    if not shot.aimAssist then return nil end

    local eye, look = BB.aimCam.view()

    return BB.hoopInSights(BB.nearbyHoops(), eye, look, GetEntityCoords(PlayerPedId()),
        shot.maxRange, BB.myTeam, shot.rings.lockAngle)
end

local function aimStart(ped)
    aim = {}
    gather(ped)
    BB.aimCam.start()
    BB.look.reticle()
end

local function aimStop()
    if not aim then return end

    aim = nil
    BB.aimCam.stop()
    BB.look.reticleOff()
end

--- One frame of aiming.
--- @return table|nil ring The release, once THROW has been let go (see shoot)
local function aimFrame(ped)
    BB.aimCam.update()
    HideHudComponentThisFrame(14)           -- the game's own reticle

    local hoop, distance = inSights()

    if hoop ~= aim.hoop then
        aim.hoop, aim.distance = hoop, distance
        aim.size = hoop and BB.ringSize(distance) or nil
        BB.look.reticleTarget(aim.size)
    elseif hoop then
        aim.distance = distance

        -- Walked in or out while aiming: the ring follows, but it is only
        -- sent on when it has changed enough to see.
        local size = BB.ringSize(distance)
        if math.abs(size - aim.size) > 0.02 then
            aim.size = size
            BB.look.reticleTarget(size)
        end
    end

    lineUp(ped, hoop)

    local keys = Config.Keys
    local rings = Config.Shot.rings
    local now = GetGameTimer()

    if not aim.closing then
        if IsDisabledControlJustPressed(0, keys.shoot) then
            aim.closing = now
            BB.look.reticleClose()
        end

        return nil
    end

    local ms = now - aim.closing
    if IsDisabledControlPressed(0, keys.shoot) and ms < rings.closeMs then return nil end

    if aim.hoop then
        local err = BB.ringError(ms, aim.size)

        -- Held until the white ring had gone: as late as a release gets, even
        -- from far out, where the yellow ring is small and the white one is
        -- gone not long after meeting it.
        if ms >= rings.closeMs then err = math.max(err, Config.Shot.timing.worst) end

        if shotDebug then
            print(('^2[gk_basketball]^7 rings: let go %+d ms from where they meet (yellow ring %.2f)')
                :format(math.floor(err), aim.size))
        end

        return { hoop = aim.hoop, distance = aim.distance, accuracy = BB.timingAccuracy(err, aim.distance) }
    end

    return { toss = BB.clamp(ms / rings.closeMs, 0.25, 1.0) }
end

function BB.startHoldLoop()
    CreateThread(function()
        local keys = Config.Keys
        local aimShown = false

        -- The timed shot needs to know when the ball leaves, which only a real
        -- jump shot from a pack says.
        local timed = Config.Shot.style == 'timed' and select(2, BB.anim.action('shoot')) ~= nil
        local rings = Config.Shot.style == 'rings'

        --- Stops lining a shot up without taking it.
        local function standDown(ped)
            charging, charge = false, 0.0
            ungather()
        end

        --- A frame of the 'rings' shot: aiming while AIM is held (or while
        --- THROW is, once it has gone down: letting go of AIM then does not
        --- take the shot away), and otherwise THROW throws, E passes, G puts
        --- the ball away.
        local function ringsFrame(ped)
            if IsDisabledControlPressed(0, keys.aim) or (aim and aim.closing) then
                if not aim then
                    charging = true
                    aimStart(ped)
                end

                local ring = aimFrame(ped)

                if ring then
                    charging = false
                    busy = true
                    aimStop()
                    CreateThread(function() shoot(nil, ring) end)
                    return
                end
            else
                if aim then
                    aimStop()
                    standDown(ped)
                end

                if IsDisabledControlJustPressed(0, keys.shoot) then
                    busy = true
                    CreateThread(function() shoot(nil, { toss = 0.5 }) end)
                    return
                elseif IsDisabledControlJustReleased(0, keys.pass) then
                    CreateThread(pass)
                elseif IsDisabledControlJustReleased(0, keys.stow) then
                    CreateThread(stow)
                end

                if Config.Dribble.enabled then
                    updateDribble()
                else
                    BB.holdInHand(ped, held, myCarry)
                end
            end

            BB.look.holding(BB.myTeam ~= nil and BB.match ~= nil and BB.match.state == 'live')
        end

        while BB.isHolding() do
            local ped = PlayerPedId()

            -- Lining up a shot is something everyone else gets to see: it is what
            -- a defender jumps at, and it makes the ball harder to steal.
            if charging ~= aimShown then
                aimShown = charging
                LocalPlayer.state:set('bbAim', charging, true)
            end

            if not busy and (IsPedSwimming(ped) or IsPedRagdoll(ped)
                or IsEntityDead(ped) or IsPedInAnyVehicle(ped, true)) then
                -- You can't keep a dribble going while swimming, flat on your
                -- back or climbing into a car. The ball goes its own way, and
                -- in water that means it floats off.
                leaveStance(ped)
                fumble()
                break
            end

            if not busy then
                -- These would otherwise throw a punch every time you shoot.
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)

                -- Leaving your feet with the ball is a shot, and there is a
                -- button for that. (A hop would also carry the dribble through
                -- the air with it.)
                DisableControlAction(0, 22, true)
            end

            if rings then
                if not busy then ringsFrame(ped) end
            elseif not busy then
                -- With the meter, which input lines a shot up: aim held, or
                -- (older still) shoot held, with the shot taken when it is let
                -- go. Timed, nothing does: shoot is the shot.
                local lining = false

                if timed then
                    if IsDisabledControlJustPressed(0, keys.shoot) then
                        -- Claimed here rather than when its own thread gets going.
                        busy = true
                        CreateThread(timedShot)
                    end
                elseif Config.Shot.aimToShoot then
                    lining = IsDisabledControlPressed(0, keys.aim)
                else
                    lining = IsDisabledControlPressed(0, keys.shoot)
                end

                if busy then
                    -- The shot has just been started; it has the ball from here.
                elseif lining then
                    if not charging then
                        charging, charge, chargeUp = true, 0.0, true
                        gather(ped)
                    end

                    tickMeter()
                    lineUp(ped, showAim())

                    if Config.Shot.aimToShoot and IsDisabledControlJustPressed(0, keys.shoot) then
                        takeShot()
                    end
                elseif charging and not Config.Shot.aimToShoot then
                    -- Let go of shoot: that is the shot.
                    takeShot()
                else
                    if charging then standDown(ped) end

                    if IsDisabledControlJustReleased(0, keys.pass) then
                        CreateThread(pass)
                    elseif IsDisabledControlJustReleased(0, keys.stow) then
                        CreateThread(stow)
                    else
                        BB.showHint(timed and Config.Text.holding_hint_timed or Config.Text.holding_hint)
                    end

                    if Config.Dribble.enabled then
                        updateDribble()
                    else
                        BB.holdInHand(ped, held, myCarry)
                    end
                end
            end

            Wait(0)
        end

        charging, charge = false, 0.0
        clearClipset()

        -- Taken off me mid-aim: the camera and the rings go with the ball.
        aimStop()

        local ped = PlayerPedId()

        -- Nothing of the dribble or the stance is left playing on somebody who
        -- no longer has a ball. (A shot or a pass has already stopped both and
        -- is playing itself out; this is for a ball that was taken away.)
        if not busy then
            leaveStance(ped)
            BB.dribbleStop(ped, myCarry)
        end

        BB.hideHint()
        BB.look.holdingOff()

        if aimShown then LocalPlayer.state:set('bbAim', false, true) end
    end)
end

--------------------------------------------------------------------------------
-- Empty-handed: picking up loose balls, catching passes, reaching in
--------------------------------------------------------------------------------

--- The team a server id is playing for in my match, or nil.
function BB.teamOf(id)
    if not BB.match or not BB.match.players then return nil end

    for _, member in ipairs(BB.match.players) do
        if member.id == id then return member.team end
    end
end

--- Somebody within reach who has a ball and isn't on my side.
--- @return table|nil { id, aiming } where id is a server id, or an NPC's negative id
local function stealTarget(coords)
    local cfg = Config.Steal
    if not cfg or not cfg.enabled then return nil end
    if cfg.matchOnly and not BB.court then return nil end

    local best, bestDist

    local function consider(ped, id, aiming, team)
        if BB.myTeam and team == BB.myTeam then return end
        if cfg.matchOnly and not team then return end

        local dist = #(coords - GetEntityCoords(ped))

        if dist < cfg.reach and (not bestDist or dist < bestDist) then
            best, bestDist = { id = id, aiming = aiming }, dist
        end
    end

    local me = PlayerId()

    for _, player in ipairs(GetActivePlayers()) do
        if player ~= me then
            local id = GetPlayerServerId(player)
            local state = Player(id).state

            if state.bbBall then
                consider(GetPlayerPed(player), id, state.bbAim == true, BB.teamOf(id))
            end
        end
    end

    for ped, bot in pairs(BB.botPeds or {}) do
        if DoesEntityExist(ped) then
            local state = Entity(ped).state

            if state.bbBall then
                consider(ped, bot.id, state.bbAim == true, bot.team)
            end
        end
    end

    return best
end

--[[
    What this client knows of each loose ball beyond the server's list: when it
    first heard of it, and how it is moving. A ball somebody else's game is
    simulating may or may not carry a velocity with it over the network, so its
    movement is read off where it was a moment ago, which is always there.
]]
local seen = {}     -- [netId] = { since, x, y, z, at, vx, vy, vz, retry }

local function watch(netId, at, now)
    local w = seen[netId]

    if not w then
        w = { since = now, x = at.x, y = at.y, z = at.z, at = now, vx = 0.0, vy = 0.0, vz = 0.0, retry = 0 }
        seen[netId] = w
        return w
    end

    local dt = (now - w.at) / 1000.0

    if dt >= 0.03 then
        w.vx, w.vy, w.vz = (at.x - w.x) / dt, (at.y - w.y) / dt, (at.z - w.z) / dt
        w.x, w.y, w.z, w.at = at.x, at.y, at.z, now
    end

    return w
end

--- Asks the server for a loose ball. An answer that never comes (the callback
--- gives up with an error) is a no, not a client left unable to touch a ball
--- for the rest of the session.
local function askFor(netId)
    local fine, ok = pcall(lib.callback.await, 'gk_basketball:pickupBall', false, netId)

    return fine and ok == true
end

--- Takes a ball that has come to me: no key, no bending down.
local function catch(netId, from)
    busy = true

    local ok = askFor(netId)
    busy = false

    if ok then
        -- Hands on leather.
        BB.playFx('catch', from.x, from.y, from.z, 4.0)
        TriggerServerEvent('gk_basketball:fx', 'catch', from.x, from.y, from.z, 4.0)

        BB.takeBall(from, 130)
    elseif seen[netId] then
        -- Somebody got there first, or it isn't mine to take yet. Not every frame.
        seen[netId].retry = GetGameTimer() + 500
    end

    return ok
end

CreateThread(function()
    while true do
        local wait = 350

        if not BB.isHolding() and not busy and not BB.placing then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local me = GetPlayerServerId(PlayerId())
            local now = GetGameTimer()
            local nearest, nearestDist, thrown, falling
            local body

            for netId, data in pairs(BB.loose) do
                if NetworkDoesNetworkIdExist(netId) then
                    local ball = NetToObj(netId)
                    if ball ~= 0 and DoesEntityExist(ball) then
                        local at = GetEntityCoords(ball)
                        local dist = #(coords - at)

                        if dist < Config.Ball.renderDistance then
                            wait = 0

                            local w = watch(netId, at, now)

                            if dist < Config.Ball.catchRadius and (not nearestDist or dist < nearestDist) then
                                nearest, nearestDist = netId, dist
                            end

                            if now >= w.retry then
                                -- A pass that was thrown to me, arriving.
                                if data.passTo == me and dist < Config.Ball.passCatchRadius then
                                    thrown = netId
                                elseif dist < 3.0 and not falling then
                                    -- Or any ball that has simply come to me.
                                    if not body then
                                        local vel = GetEntityVelocity(ped)
                                        body = { x = coords.x, y = coords.y, z = coords.z, vx = vel.x, vy = vel.y, vz = vel.z }
                                    end

                                    if M.catchable(w, body, (now - w.since) / 1000.0, Config.Ball.autoCatch) then
                                        falling = netId
                                    end
                                end
                            end
                        end
                    end
                end
            end

            -- Hands that can't take a ball: in a car, in the water, on the floor.
            local able = not (IsPedInAnyVehicle(ped, true) or IsPedSwimming(ped) or IsPedRagdoll(ped) or IsEntityDead(ped))

            if thrown and able then
                -- One go at it. If the server says no (somebody got there
                -- first), it's a loose ball like any other.
                BB.loose[thrown].passTo = nil
                catch(thrown, GetEntityCoords(NetToObj(thrown)))
            elseif falling and able then
                catch(falling, GetEntityCoords(NetToObj(falling)))
            elseif nearest and able then
                BB.look.ball(GetEntityCoords(NetToObj(nearest)), nearest)

                if IsControlJustReleased(0, Config.Keys.pickup) then
                    local netId = nearest

                    BB.scoop(GetEntityCoords(NetToObj(netId)), function() return askFor(netId) end)
                end
            else
                -- No ball to pick up, but somebody close by has one.
                local target = stealTarget(coords)

                if target then
                    wait = 0
                    BB.look.steal()

                    if IsControlJustReleased(0, Config.Keys.pickup) then
                        busy = true

                        local reach = BB.anim.action('steal')
                        playAnim(reach)

                        -- The server decides whether it came off. Either way the
                        -- reach costs a moment.
                        TriggerServerEvent('gk_basketball:steal', target.id, nil, target.aiming)

                        Wait(450)

                        if not layered(reach) then ClearPedTasks(PlayerPedId()) end

                        busy = false
                    end
                end
            end
        end

        Wait(wait)
    end
end)

--------------------------------------------------------------------------------
-- Server messages
--------------------------------------------------------------------------------

-- The server has approved a ball for me (item use, court rack, or a catch).
RegisterNetEvent('gk_basketball:giveBall', function()
    BB.takeBall()
end)

-- Somebody got a hand on it. `aiId` is set when it was an NPC of mine they
-- reached in on rather than me.
RegisterNetEvent('gk_basketball:stripped', function(aiId)
    if aiId then
        BB.botStripped(aiId)
        return
    end

    if not BB.isHolding() then return end

    fumble(BB.knockVelocity())
    BB.notify(Config.Text.stripped, 'error')
end)

-- The ball is being taken out of play (tip-off, change of possession). The
-- server has already stopped counting it as held.
RegisterNetEvent('gk_basketball:takeAway', function(aiId)
    if aiId then
        BB.botTakeAway(aiId)
        return
    end

    if held and DoesEntityExist(held) then DeleteEntity(held) end
    held = nil
end)

RegisterNetEvent('gk_basketball:setLooseBall', function(netId, data)
    BB.loose[netId] = data

    -- Newly loose or gone, what was known of the ball under this id is stale:
    -- ids are handed out again.
    seen[netId] = nil

    if not data then
        BB.untrackShot(netId)
    end
end)

RegisterNetEvent('gk_basketball:syncLooseBalls', function(balls)
    BB.loose = balls or {}
    seen = {}
end)

-- ox_inventory item use.
exports('useBasketball', function()
    if BB.isHolding() then
        BB.notify(Config.Text.hands_full, 'error')
        return false
    end

    TriggerServerEvent('gk_basketball:useItem')
    return true
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    -- Leaving the ball-carrying walk, a dribble or the stance applied would
    -- follow you around after a restart.
    clearClipset()

    local ped = PlayerPedId()

    leaveStance(ped)
    BB.dribbleStop(ped, myCarry)

    if held and DoesEntityExist(held) then DeleteEntity(held) end

    for netId in pairs(BB.loose) do
        if NetworkDoesNetworkIdExist(netId) then
            local ball = NetToObj(netId)
            if ball ~= 0 and DoesEntityExist(ball) then DeleteEntity(ball) end
        end
    end
end)
