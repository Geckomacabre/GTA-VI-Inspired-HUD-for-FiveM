--[[
    NPC players.

    Driving model
    -------------
    An NPC is a normal member of the match: it has a team, it's on the scoreboard,
    its baskets count. Its ped is created and run by the client of whoever added
    it, because a ped needs a local owner to move and animate smoothly, and is a
    networked ped so everyone else on the court sees it. The server records that
    the slot is an NPC and who drives it, and treats it as a ball-holder like any
    other (server/ball.lua).

    Playing model
    -------------
    It plays the ball that's there. Each think, in order:

        has the ball      work to a spot it can shoot from, and shoot; sooner and
                          worse if somebody is on it
        ball is loose     go and get it
        opponent has it   get between them and the basket; hands up when they
                          line up a shot, and reach in now and then
        team-mate has it  find space near the basket
        nobody has one    take one off the rack

    Its shot goes through the same solver and scatter as yours, with accuracy from
    its difficulty instead of from a meter, and the ball is the same physical ball:
    it misses off the iron, its misses are there to be rebounded, and a hand in
    the way of its shot blocks it.
]]

local bots = {}     -- [aiId] = bot, the NPCs this client drives

-- Every NPC player this client can see, its own or anyone else's:
-- [ped] = { id = aiId, team = team }. Defending and steals need to know which
-- peds are players.
BB.botPeds = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function loadModel(model)
    if not IsModelInCdimage(model) then return false end

    RequestModel(model)

    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end

    return true
end

local function skillById(id)
    for _, entry in ipairs(Config.AI.difficulties) do
        if entry.id == id then return entry end
    end

    return Config.AI.difficulties[1]
end

--- The basket somebody on `team` standing at `at` is going for: nearest hoop on
--- my court that isn't their own to defend.
local function basketFor(team, at)
    local best, bestDist

    for _, hoop in ipairs(BB.hoops) do
        if hoop.court == BB.court and not (hoop.team and hoop.team == team) then
            local dist = BB.dist2d(at, hoop.coords)
            if not bestDist or dist < bestDist then best, bestDist = hoop, dist end
        end
    end

    return best
end

--- Somewhere to shoot from: a random bearing at a distance the bot is good from.
local function pickSpot(bot, hoop, floorZ)
    local min, max = bot.skill.range[1], bot.skill.range[2]
    local dist = min + math.random() * (max - min)
    local angle = math.random() * math.pi * 2.0

    return vec3(hoop.coords.x + math.cos(angle) * dist, hoop.coords.y + math.sin(angle) * dist, floorZ)
end

--- Walks or runs to a point, without re-issuing the task every think: a ped
--- that is told to go somewhere ten times a second never gets into its stride.
local function go(bot, x, y, z, speed, now)
    local last = bot.going

    if last and now - last.at < 900 and last.speed == speed
        and (x - last.x) ^ 2 + (y - last.y) ^ 2 < 0.3 then
        return
    end

    bot.going = { x = x, y = y, at = now, speed = speed }
    TaskGoStraightToCoord(bot.ped, x, y, z, speed, 8000, 40000.0, 0.3)
end

local function halt(bot)
    if bot.going then
        bot.going = nil
        ClearPedTasks(bot.ped)
    end
end

local function face(ped, x, y)
    local at = GetEntityCoords(ped)
    SetEntityHeading(ped, (math.deg(math.atan(y - at.y, x - at.x)) - 90.0) % 360.0)
end

local function tag(bot, key, value)
    if DoesEntityExist(bot.ped) then
        Entity(bot.ped).state:set(key, value, true)
    end
end

--------------------------------------------------------------------------------
-- What's going on around it
--------------------------------------------------------------------------------

--- Nearest loose ball on the court, and where it is.
local function nearestLoose(at)
    local court = BB.courts[BB.court]
    if not court then return nil end

    local best, bestAt, bestDist

    for netId in pairs(BB.loose) do
        if NetworkDoesNetworkIdExist(netId) then
            local ball = NetToObj(netId)

            if ball ~= 0 and DoesEntityExist(ball) then
                local pos = GetEntityCoords(ball)

                if #(pos - court.centre) < Config.Match.courtRadius then
                    local dist = BB.dist2d(at, pos)
                    if not bestDist or dist < bestDist then best, bestAt, bestDist = netId, pos, dist end
                end
            end
        end
    end

    return best, bestAt, bestDist
end

--- Everyone in the match who has a ball in their hands right now.
--- @return table list of { ped, id, team, aiming }
local function holders()
    local list = {}

    if BB.match and BB.match.players then
        for _, member in ipairs(BB.match.players) do
            if member.id > 0 then
                local player = GetPlayerFromServerId(member.id)

                if player ~= -1 then
                    local state = Player(member.id).state

                    if state.bbBall then
                        list[#list + 1] = {
                            ped = GetPlayerPed(player), id = member.id, team = member.team,
                            aiming = state.bbAim == true,
                        }
                    end
                end
            end
        end
    end

    for ped, info in pairs(BB.botPeds) do
        if DoesEntityExist(ped) then
            local state = Entity(ped).state

            if state.bbBall then
                list[#list + 1] = { ped = ped, id = info.id, team = info.team, aiming = state.bbAim == true }
            end
        end
    end

    return list
end

--------------------------------------------------------------------------------
-- Having the ball
--------------------------------------------------------------------------------

local function giveBall(bot)
    if bot.held and DoesEntityExist(bot.held) then return end

    local ball = BB.createBall(GetEntityCoords(bot.ped))
    if not ball then
        -- The server thinks it has one. Tell it otherwise, or this bot is
        -- "holding" a ball that doesn't exist for the rest of the match.
        TriggerServerEvent('gk_basketball:stowBall', bot.aiId)
        return
    end

    bot.held = ball
    bot.dribble = { phase = 0.0 }
    bot.hoop, bot.spot = nil, nil
    bot.gotBallAt = GetGameTimer()

    tag(bot, 'bbBall', true)

    -- The ball-carrying walk is only for when there is no animation pack: with
    -- one, the legs are the pack's or the game's ordinary ones.
    if not BB.anim.gaits() and Config.Dribble.clipset and HasAnimSetLoaded(Config.Dribble.clipset) then
        SetPedMovementClipset(bot.ped, Config.Dribble.clipset, 0.5)
    end
end

--- The ball has left its hands, one way or another.
local function emptyHanded(bot)
    bot.held = nil
    bot.hoop, bot.spot = nil, nil

    tag(bot, 'bbBall', false)
    tag(bot, 'bbAim', false)

    if DoesEntityExist(bot.ped) then
        BB.dribbleStop(bot.ped, bot.dribble)
        ResetPedMovementClipset(bot.ped, 0.5)
    end
end

--- Lets go of the ball as a live ball.
local function release(bot, pos, vel, spin)
    local ball = bot.held
    if not ball or not DoesEntityExist(ball) then
        emptyHanded(bot)
        return nil
    end

    emptyHanded(bot)
    BB.sim.launch(ball, pos, vel, spin, bot.ped)

    local netId = ObjToNet(ball)
    TriggerServerEvent('gk_basketball:ballReleased', netId, nil, bot.aiId)

    return netId
end

local function shoot(bot, pressured)
    local ped, hoop = bot.ped, bot.hoop
    if not hoop or bot.busy then return end

    bot.busy = true
    halt(bot)

    CreateThread(function()
        local origin = GetEntityCoords(ped)
        local dist   = BB.dist2d(origin, hoop.coords)

        face(ped, hoop.coords.x, hoop.coords.y)
        tag(bot, 'bbAim', true)

        -- Out of the dribble and into the shot, the ball gathered in on the way.
        BB.dribbleStop(ped, bot.dribble, true)
        BB.easeBall(bot.dribble, bot.held, 110)

        local clip, releaseAt = BB.anim.action('shoot')
        BB.playAnim(ped, clip, releaseAt and 8.0 or nil)

        -- The wind-up, ball in hand. It can be knocked out of them in this time.
        local leaves = GetGameTimer() + (releaseAt or Config.Shot.windUp + 180)
        while GetGameTimer() < leaves and bot.held and DoesEntityExist(ped) do
            BB.holdInHand(ped, bot.held, bot.dribble)
            Wait(0)
        end

        if bot.held and DoesEntityExist(ped) then
            -- Released from where a player's is: out of the hands at the top of
            -- a real jump shot, otherwise over the head along the line of the shot.
            local from = BB.releasePoint(ped, releaseAt and bot.held or nil,
                vec3(hoop.coords.x - origin.x, hoop.coords.y - origin.y, 0.0), 'shot')

            local accuracy = bot.skill.accuracy
            if pressured or BB.contested(ped, bot.team, hoop.coords) then
                accuracy = accuracy * Config.Shot.contestFactor
            end

            -- Same solver and the same scatter as a human shot, so an NPC makes
            -- and misses the way you do.
            local target = vec3(hoop.coords.x, hoop.coords.y, hoop.coords.z + Config.Shot.aimHeightOffset)
            local aim    = BB.scatterAim(from, target, accuracy, dist)
            local vel, spin = BB.solveShot(from, aim)

            local netId = release(bot, from, vel, spin)
            if netId then BB.trackShot(netId, origin, hoop, accuracy, bot.aiId) end
        end

        Wait(math.floor(bot.skill.restTime * 400.0))

        if DoesEntityExist(ped) then ClearPedTasks(ped) end
        bot.busy = false
    end)
end

local function attack(bot, now, at)
    if not bot.hoop then
        bot.hoop = basketFor(bot.team, at)
        if not bot.hoop then return halt(bot) end

        bot.spot = pickSpot(bot, bot.hoop, at.z)
        bot.attackSince = now
    end

    local toSpot = BB.dist2d(at, bot.spot)
    local toRim  = BB.dist2d(at, bot.hoop.coords)
    local onIt   = BB.contested(bot.ped, bot.team, bot.hoop.coords)
    local elapsed = now - bot.attackSince

    -- Gets its shot off once it is where it wanted to be, or it has run out of
    -- patience getting there. With somebody on it, it doesn't hang about: any
    -- look inside its range will do.
    local patience = bot.skill.setupTime * 1000.0 + 2500.0
    local inRange  = toRim <= bot.skill.range[2] + 1.0

    if toSpot < 1.1 or elapsed > patience or (onIt and inRange and elapsed > 900) then
        return shoot(bot, onIt)
    end

    go(bot, bot.spot.x, bot.spot.y, at.z, bot.skill.moveSpeed, now)
end

--------------------------------------------------------------------------------
-- Not having the ball
--------------------------------------------------------------------------------

local function chase(bot, now, at, netId, ballAt, dist)
    -- Flat out for a loose ball, whatever its usual pace.
    go(bot, ballAt.x, ballAt.y, at.z, math.max(bot.skill.moveSpeed, 2.2), now)

    if dist < 1.5 and ballAt.z - at.z < 1.5 and not bot.grabbing then
        bot.grabbing = true

        CreateThread(function()
            local ok = lib.callback.await('gk_basketball:pickupBall', false, netId, bot.aiId)

            if ok and bots[bot.aiId] == bot and DoesEntityExist(bot.ped) then
                giveBall(bot)
            elseif ok then
                TriggerServerEvent('gk_basketball:stowBall', bot.aiId)
            end

            bot.grabbing = false
        end)
    end
end

local function defend(bot, now, at, holder)
    local theirs = GetEntityCoords(holder.ped)
    local basket = basketFor(holder.team, theirs)
    if not basket then return halt(bot) end

    -- Between them and where they are going, a step off.
    local dx, dy = basket.coords.x - theirs.x, basket.coords.y - theirs.y
    local len = math.max(math.sqrt(dx * dx + dy * dy), 0.01)
    local gap = math.min(1.25, len * 0.5)
    local gx, gy = theirs.x + dx / len * gap, theirs.y + dy / len * gap

    local apart = BB.dist2d(at, theirs)
    go(bot, gx, gy, at.z, apart > 3.5 and math.max(bot.skill.moveSpeed, 2.2) or bot.skill.moveSpeed, now)

    if apart > 2.4 then return end

    if holder.aiming then
        -- Contest it. Arms up puts real hands in the path of a real ball; whether
        -- that turns into a block is up to where the ball goes.
        if now - (bot.contestAt or 0) > 1300 then
            bot.contestAt = now
            bot.going = nil

            face(bot.ped, theirs.x, theirs.y)

            BB.playAnim(bot.ped, (BB.anim.action('contest')))

            if math.random() < bot.skill.contest then TaskJump(bot.ped, true) end
        end
    elseif apart < Config.Steal.reach and now - (bot.reachAt or 0) > Config.Steal.cooldown + 300 then
        bot.reachAt = now
        TriggerServerEvent('gk_basketball:steal', holder.id, bot.aiId, false)
    end
end

--- A team-mate has it: find some room near the basket and wait for the miss.
local function support(bot, now, at)
    if not bot.spot or now - (bot.spotAt or 0) > 4500 then
        local basket = basketFor(bot.team, at)
        if not basket then return halt(bot) end

        bot.spot, bot.spotAt = pickSpot(bot, basket, at.z), now
    end

    if BB.dist2d(at, bot.spot) > 1.0 then
        go(bot, bot.spot.x, bot.spot.y, at.z, bot.skill.moveSpeed, now)
    end
end

--------------------------------------------------------------------------------
-- Brain
--------------------------------------------------------------------------------

local function think(bot, now)
    local at = GetEntityCoords(bot.ped)

    if bot.held then return attack(bot, now, at) end

    local netId, ballAt, dist = nearestLoose(at)
    if netId then return chase(bot, now, at, netId, ballAt, dist) end

    local theirs, ours, theirDist

    for _, holder in ipairs(holders()) do
        if holder.ped ~= bot.ped then
            if holder.team == bot.team then
                ours = true
            else
                local d = BB.dist2d(at, GetEntityCoords(holder.ped))
                if not theirDist or d < theirDist then theirs, theirDist = holder, d end
            end
        end
    end

    if theirs then return defend(bot, now, at, theirs) end
    if ours then return support(bot, now, at) end

    -- No ball anywhere. Give it a moment (one may be on its way to somebody's
    -- hands after a basket), then fetch one.
    halt(bot)

    if now - (bot.askedAt or 0) > 3000 then
        bot.askedAt = now
        TriggerServerEvent('gk_basketball:requestBall', BB.court, bot.aiId)
    end
end

local function despawn(aiId)
    local bot = bots[aiId]
    if not bot then return end

    bots[aiId] = nil

    if bot.held and DoesEntityExist(bot.held) then DeleteEntity(bot.held) end

    if bot.ped and DoesEntityExist(bot.ped) then
        BB.botPeds[bot.ped] = nil
        SetEntityAsMissionEntity(bot.ped, true, true)
        DeleteEntity(bot.ped)
    end
end

CreateThread(function()
    while true do
        local wait = 500

        if next(bots) then
            wait = 100

            local live = BB.match and BB.match.state == 'live'
            local now  = GetGameTimer()

            for aiId, bot in pairs(bots) do
                if not bot.ped or not DoesEntityExist(bot.ped) then
                    despawn(aiId)
                else
                    if bot.held then
                        if not DoesEntityExist(bot.held) then
                            emptyHanded(bot)
                        else
                            -- The ball is wherever its holder puts it, every frame.
                            wait = 0
                            -- Dribbled exactly as a player's is, body and all.
                            if not bot.busy then BB.dribble(bot.ped, bot.held, bot.dribble, bot.team) end
                        end
                    end

                    if not bot.busy and now >= bot.thinkAt then
                        bot.thinkAt = now + 150

                        if live then
                            think(bot, now)
                        else
                            halt(bot)
                        end
                    end
                end
            end
        end

        Wait(wait)
    end
end)

--------------------------------------------------------------------------------
-- Everyone's NPCs, as seen from here
--------------------------------------------------------------------------------

-- Other players' NPCs arrive as ordinary networked peds. Their driver tags them,
-- and this picks the tags up, so this client knows which peds are in the game.
CreateThread(function()
    while true do
        Wait(700)

        for ped in pairs(BB.botPeds) do
            if not DoesEntityExist(ped) then BB.botPeds[ped] = nil end
        end

        if BB.court or #BB.nearbyHoops() > 0 then
            for _, ped in ipairs(GetGamePool('CPed')) do
                if not BB.botPeds[ped] and not IsPedAPlayer(ped) then
                    local info = Entity(ped).state.bbBot
                    if info then BB.botPeds[ped] = { id = info.id, team = info.team } end
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

RegisterNetEvent('gk_basketball:startAI', function(aiId, team, difficultyId)
    local court = BB.courts[BB.court]
    if not court then return end

    despawn(aiId)

    local model = Config.AI.model
    if not loadModel(model) then
        model = Config.AI.fallbackModel
        if not loadModel(model) then
            TriggerServerEvent('gk_basketball:aiFailed', aiId)
            return
        end
    end

    -- Networked, so the other players on the court can see who they're playing.
    local at = court.centre
    local ped = CreatePed(4, model, at.x, at.y, at.z, 0.0, true, true)
    SetModelAsNoLongerNeeded(model)

    if not ped or ped == 0 then
        TriggerServerEvent('gk_basketball:aiFailed', aiId)
        return
    end

    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedCanBeTargetted(ped, false)
    SetEntityAsMissionEntity(ped, true, true)

    -- It has to stay ours: a ped only does what its owner's game tells it.
    SetNetworkIdCanMigrate(PedToNet(ped), false)

    local contest = BB.anim.action('contest')
    if contest then RequestAnimDict(contest.dict) end
    if Config.Dribble.clipset then RequestAnimSet(Config.Dribble.clipset) end

    local bot = {
        aiId    = aiId,
        ped     = ped,
        team    = team,
        skill   = skillById(difficultyId),
        thinkAt = GetGameTimer() + 1500,
        dribble = { phase = 0.0 },
    }

    bots[aiId] = bot
    BB.botPeds[ped] = { id = aiId, team = team }

    tag(bot, 'bbBot', { id = aiId, team = team })
    tag(bot, 'bbBall', false)
end)

RegisterNetEvent('gk_basketball:stopAI', function(aiId)
    if aiId then
        despawn(aiId)
        return
    end

    for id in pairs(bots) do despawn(id) end
end)

-- The server has put a ball in one of my NPCs' hands (rack, tip-off, possession).
RegisterNetEvent('gk_basketball:aiGiveBall', function(aiId)
    local bot = bots[aiId]

    if not bot or not DoesEntityExist(bot.ped) then
        -- Not here to take it: hand it straight back so it isn't lost.
        TriggerServerEvent('gk_basketball:stowBall', aiId)
        return
    end

    giveBall(bot)
end)

--- Somebody reached in on one of my NPCs and got it.
function BB.botStripped(aiId)
    local bot = bots[aiId]
    if not bot or not bot.held then return end

    local vel = GetEntityVelocity(bot.ped) + BB.knockVelocity()
    release(bot, GetEntityCoords(bot.held), vel)
end

--- The ball is being taken out of one of my NPCs' hands, out of play.
function BB.botTakeAway(aiId)
    local bot = bots[aiId]
    if not bot then return end

    if bot.held and DoesEntityExist(bot.held) then DeleteEntity(bot.held) end
    emptyHanded(bot)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for id in pairs(bots) do despawn(id) end
end)
