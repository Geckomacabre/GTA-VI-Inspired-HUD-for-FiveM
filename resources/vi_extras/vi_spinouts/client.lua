--[[ ===========================================================================
     vi_spinouts — client
     ---------------------------------------------------------------------------
     SPIN-OUTS, ported from FBICat's GTA6Hud (single player's [Driving]
     SpinOuts). Cars lose the back end and spin when something knocks them off
     line, as in GTA VI.

     People's cars within 100 m, going 40 km/h (11 m/s) or more, spin out when
       - one of their tyres bursts (towards the side that burst),
       - their driver dies or gets out,
       - you shoot them (12% a hit at 72 km/h; config.shotChance),
       - they take a hard hit on the side (65%).
     Your own car spins out when it's hit hard on the side at 43 km/h or more.
     Bikes, boats, aircraft and trains never do. Each car spins once while it
     stays in range.

     A spin-out: grip cut for 3.5 s, a driver who loses control (not you), and a
     push sideways at the back of the car, harder the faster it was going. Over
     72 km/h, 35% of them trip over and roll a moment later (config.rollChance).

     On a server, a car's physics run on the client that owns it, so only the
     owner can push it. This client acts on cars it owns, and asks for cars it
     spun out itself (shot or hit). Cars with another player in them, or last
     driven by one, are left alone, as are cars another script spawned (single
     player leaves mission cars alone the same way).

     Public API: none. The SPIN-OUTS row of HUD OPTIONS switches it per player;
     switched off (or the resource stopped) every car gets its grip back.
     ========================================================================= ]]

local options = require 'vi_hudoptions.options'
local config = require 'vi_spinouts.config'
if not config.enabled then return end

-- Single player's numbers. Speeds are m/s, as GetEntityVelocity gives them.
local RADIUS = 100.0            -- cars watched around you (150 before the fork's 2.6.0)
local SCAN_MS = 500             -- how often that list is made
local MIN_SPEED = 11.0          -- slower than this a car can't spin out
local GRIP_MS = 3500            -- how long a spun car's grip stays cut
local SIDE_HIT = 7.0            -- speed change in a frame that counts as a hit (people's cars)
local SIDE_CHANCE = 0.65
local ROLL_SPEED = 20.0         -- a spin-out has to be faster than this to roll
local ROLL_DELAY_MS = 350
local IMPACT_GAP_MS = 350       -- between two hits on your own car
local CAR_TYRES = { 0, 1, 4, 5 }        -- front left, front right, rear left, rear right
local LEFT_TYRES = (1 << 0) | (1 << 4)

-- motorcycles, bicycles, boats, helicopters, planes, trains
local NOT_CARS = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }

local rollChance = tonumber(config.rollChance) or 0.35
local shotChance = tonumber(config.shotChance) or 0.12
local impactMin = tonumber(config.impactMin) or 5.0
local controlWaitMs = tonumber(config.controlWaitMs) or 250

local spinCars = {}             -- people's cars in range, from the last scan
local watch = {}                -- [car] = { tyres, alive, vel, spun }: last frame's reading
local lowGrip = {}              -- { veh, untilAt }: grip to give back
local rollQueue = {}            -- { veh, at, speed, halfWidth }: spin-outs that may roll
local scanAt = 0
local driveVeh, driveLastVel, impactAt = 0, nil, 0

-- A world point in the car's own terms: x across it (right +), y along it.
local function localPoint(veh, p)
    return GetOffsetFromEntityGivenWorldCoords(veh, p.x, p.y, p.z)
end

local function clearShot(car)
    ClearEntityLastWeaponDamage(car)
    ClearEntityLastDamageEntity(car)
end

-- Another script's car (or driver): single player's mission cars, here a
-- garage car, a job van, anything a resource spawned.
local function othersEntity(handle)
    return handle ~= 0 and IsEntityAMissionEntity(handle) and not DoesEntityBelongToThisScript(handle, false)
end

local function scriptCar(car)
    if othersEntity(car) then return true end
    if IsVehicleSeatFree(car, -1, false) then return false end
    return othersEntity(GetPedInVehicleSeat(car, -1, false))
end

-- The cars other players are sitting in, any seat.
local function playersCars()
    local cars, me = {}, PlayerId()
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= me then
            local veh = GetVehiclePedIsIn(GetPlayerPed(player), false)
            if veh ~= 0 then cars[veh] = true end
        end
    end
    return cars
end

-- Every half second: the cars to watch. Parked cars are in it (a parked car
-- knocked rolling can spin), people's cars only, not yours.
local function scan(ped, myVeh)
    spinCars = {}
    local seen = {}
    local taken = playersCars()
    local here = GetEntityCoords(ped)
    for _, car in ipairs(GetGamePool('CVehicle')) do
        if car ~= myVeh and not taken[car] and not IsEntityDead(car)
            and not NOT_CARS[GetVehicleClass(car)]
            and #(GetEntityCoords(car) - here) <= RADIUS then
            local driver = GetPedInVehicleSeat(car, -1, false)
            local lastDriver = GetLastPedInVehicleSeat(car, -1)
            -- single player looks at the driver only; here a car another
            -- player drove and left is theirs too
            if (driver == 0 or not IsPedAPlayer(driver))
                and (lastDriver == 0 or lastDriver == ped or not IsPedAPlayer(lastDriver))
                and not scriptCar(car) then
                spinCars[#spinCars + 1] = car
                seen[car] = true
            end
        end
    end
    for car in pairs(watch) do
        if not seen[car] then watch[car] = nil end
    end
end

-- Runs fn once this client may move the car: at once if it owns it, else after
-- asking, but only for a car this player spun out (mine). Two clients pushing
-- the same car would spin it twice.
local function withControl(veh, mine, fn)
    if NetworkHasControlOfEntity(veh) then fn() return end
    if not mine then return end
    NetworkRequestControlOfEntity(veh)
    CreateThread(function()
        local giveUp = GetGameTimer() + controlWaitMs
        repeat
            Wait(0)
            if not DoesEntityExist(veh) then return end
            if NetworkHasControlOfEntity(veh) then
                if options.get('spinouts') then fn() end
                return
            end
        until GetGameTimer() >= giveUp
    end)
end

-- The spin itself. dir 1 pushes the back of the car to the right, -1 to the
-- left, 0 either at random; speed is what it was doing, m/s.
local function spinOut(veh, dir, speed, npc, mine)
    withControl(veh, mine, function()
        if dir == 0 then dir = math.random(2) == 1 and 1 or -1 end
        if npc then SetVehicleOutOfControl(veh, false, false) end
        SetVehicleReduceGrip(veh, true)
        lowGrip[#lowGrip + 1] = { veh = veh, untilAt = GetGameTimer() + GRIP_MS }

        local min, max = GetModelDimensions(GetEntityModel(veh))
        local rear = min.y * 0.85
        local push = math.max(2.0, math.min(4.5, speed * 0.16))
        ApplyForceToEntity(veh, 1, push * dir, 0.0, 0.0, 0.0, rear, 0.0, 0, true, true, true, false, true)

        if speed > ROLL_SPEED and math.random() < rollChance then
            rollQueue[#rollQueue + 1] = {
                veh = veh, at = GetGameTimer() + ROLL_DELAY_MS,
                speed = speed, halfWidth = (max.x - min.x) * 0.5,
            }
        end
    end)
end

-- A moment after a fast spin-out: if the car is sliding sideways (4 m/s or
-- more) and on the ground, the side it trails is lifted and it rolls over the
-- wheels it's sliding on.
local function tripOver(now)
    for i = #rollQueue, 1, -1 do
        local roll = rollQueue[i]
        local veh = roll.veh
        if not DoesEntityExist(veh) or now >= roll.at then
            table.remove(rollQueue, i)
            if DoesEntityExist(veh) and not IsEntityDead(veh) and not IsEntityInAir(veh)
                and NetworkHasControlOfEntity(veh) then
                local x = localPoint(veh, GetEntityCoords(veh) + GetEntityVelocity(veh)).x
                if math.abs(x) >= 4.0 then
                    local up = math.min(5.5, 2.8 + (roll.speed - 20.0) * 0.12)
                    local side = (x > 0.0 and -1.0 or 1.0) * roll.halfWidth
                    ApplyForceToEntity(veh, 1, 0.0, 0.0, up, side, 0.0, -0.1, 0, true, true, true, false, true)
                end
            end
        end
    end
end

-- Grip back once its 3.5 s are up. A car this client no longer owns gets it
-- back too: the flag stays on this client's copy, and would be there again
-- the next time the car came back to it.
local function releaseGrip(now)
    for i = #lowGrip, 1, -1 do
        local entry = lowGrip[i]
        if now >= entry.untilAt or not DoesEntityExist(entry.veh) then
            if DoesEntityExist(entry.veh) then SetVehicleReduceGrip(entry.veh, false) end
            table.remove(lowGrip, i)
        end
    end
end

local function restoreAll()
    for _, entry in ipairs(lowGrip) do
        if DoesEntityExist(entry.veh) then SetVehicleReduceGrip(entry.veh, false) end
    end
    lowGrip, rollQueue, watch, spinCars = {}, {}, {}, {}
    driveVeh, driveLastVel = 0, nil
end

-- Parked, slow, or already spun: nothing to read but its speed.
local function skip(car)
    local w = watch[car]
    if not w then return false end
    if w.spun then
        clearShot(car)
        return true
    end
    if #w.vel < MIN_SPEED then
        local vel = GetEntityVelocity(car)
        if #vel < MIN_SPEED then
            w.vel = vel
            clearShot(car)
            return true
        end
    end
    return false
end

-- This player did it: shot it, or hit it with their car.
local function causedBy(car, ped, myVeh)
    return HasEntityBeenDamagedByEntity(car, ped, true)
        or (myVeh ~= 0 and HasEntityBeenDamagedByEntity(car, myVeh, true))
end

-- Every frame: what changed on each watched car since the frame before.
local function watchCars(ped, myVeh)
    for i = 1, #spinCars do
        local car = spinCars[i]
        if DoesEntityExist(car) and not IsEntityDead(car) and not skip(car) then
            local driver = GetPedInVehicleSeat(car, -1, false)
            local alive = driver ~= 0 and DoesEntityExist(driver) and not IsEntityDead(driver)
            local vel = GetEntityVelocity(car)
            local tyres = 0
            for _, wheel in ipairs(CAR_TYRES) do
                if IsVehicleTyreBurst(car, wheel, false) then tyres = tyres | (1 << wheel) end
            end

            local w = watch[car]
            if not w then
                watch[car] = { tyres = tyres, alive = alive, vel = vel, spun = false }
            else
                local was = #w.vel
                local change = w.vel - vel
                local burst = tyres & ~w.tyres
                local killed = w.alive and not alive
                w.tyres, w.alive, w.vel = tyres, alive, vel

                if w.spun or was < MIN_SPEED then
                    clearShot(car)
                else
                    local spin, dir, mine = false, 0, false
                    if burst ~= 0 then
                        spin = true
                        dir = (burst & LEFT_TYRES) ~= 0 and 1 or -1
                    elseif killed then
                        spin = true
                    elseif HasEntityBeenDamagedByWeapon(car, 0, 2) and HasEntityBeenDamagedByEntity(car, ped, true) then
                        -- shot by you: more likely the faster it's going
                        spin = math.random() < shotChance * math.min(2.0, was / 20.0)
                        mine = true
                    elseif #change > SIDE_HIT and HasEntityCollidedWithAnything(car) then
                        local hit = localPoint(car, GetEntityCoords(car) + change / #change)
                        if math.abs(hit.x) > 0.45 and math.random() < SIDE_CHANCE then
                            spin = true
                            dir = hit.x > 0.0 and -1 or 1
                        end
                    end
                    -- read before the damage flags are cleared below
                    if spin and not mine then mine = causedBy(car, ped, myVeh) end
                    clearShot(car)
                    if spin then
                        w.spun = true
                        spinOut(car, dir, was, true, mine)
                    end
                end
            end
        end
    end
end

-- Your own car: the part of GTA6Hud's crash impacts that spins it. A hit is a
-- speed change of impactMin in one frame while touching something; one on the
-- side (not the nose or tail), over 10 m/s, at over 12 m/s, spins you out.
local function ownCar(veh)
    local vel = GetEntityVelocity(veh)
    local fresh = driveVeh ~= veh
    local lastVel = driveLastVel
    driveVeh, driveLastVel = veh, vel
    local now = GetGameTimer()
    if fresh or now < impactAt then return end

    local change = lastVel - vel
    local hit = #change
    if hit < impactMin or not HasEntityCollidedWithAnything(veh) then return end
    impactAt = now + IMPACT_GAP_MS

    -- where on the car the hit came from, against its size: a side hit is
    -- further out across it than along it
    local at = localPoint(veh, GetEntityCoords(veh) + change / hit)
    local min, max = GetModelDimensions(GetEntityModel(veh))
    local across = math.abs(at.x) / math.max(0.1, (max.x - min.x) * 0.5)
    local along = math.abs(at.y) / math.max(0.1, (max.y - min.y) * 0.5)
    local before = #lastVel
    if across > along * 0.8 and hit > 10.0 and before > 12.0 then
        spinOut(veh, at.x > 0.0 and -1 or 1, before, false, true)
    end
end

options.add({
    id = 'spinouts',
    label = 'SPIN-OUTS',
    default = config.default ~= false,
    desc = 'Cars spin out in crashes, when shot, or when a tyre bursts.',
    onChange = function(on)
        if not on then restoreAll() end
    end,
})

CreateThread(function()
    while true do
        local wait = 500
        if options.get('spinouts') then
            local now = GetGameTimer()
            releaseGrip(now)
            local ped = cache.ped or PlayerPedId()
            -- single player leaves it all alone while you're dead
            if not IsEntityDead(ped) then
                local myVeh = GetVehiclePedIsIn(ped, false)
                if now >= scanAt then
                    scanAt = now + SCAN_MS
                    scan(ped, myVeh)
                end
                watchCars(ped, myVeh)
                tripOver(now)

                local driving = config.impacts ~= false and myVeh ~= 0
                    and GetPedInVehicleSeat(myVeh, -1, false) == ped
                    and not NOT_CARS[GetVehicleClass(myVeh)]
                if driving then ownCar(myVeh) else driveVeh = 0 end

                -- a hit lasts a frame: read every frame while there's anything to read
                if driving or #spinCars > 0 or #rollQueue > 0 then wait = 0 end
            else
                driveVeh = 0
            end
            if #lowGrip > 0 then wait = 0 end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then restoreAll() end
end)
