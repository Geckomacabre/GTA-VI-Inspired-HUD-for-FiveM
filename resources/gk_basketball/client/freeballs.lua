--[[
    Basketballs lying about on a court.

    Walk up to one and pick it up, and you have a ball: no match to join, no
    opponent, nothing to set up. Shoot around for as long as you like.

    Where they lie comes from BB.ballSpots (the court's own list in Config.Courts,
    or a couple near the middle of any court that hasn't one). Which of them have
    been picked up is the server's to say, so everybody sees the same balls; one
    that's been taken is back a few seconds later.

    These are props, not balls in play: they don't roll or bounce. The one in
    your hands after you pick one up is the real thing.
]]

local props = {}    -- ['court:index'] = { obj, x, y, z, court, index }

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

--- The height a ball rests at on a spot. A spot from the config says; one worked
--- out from the middle of a court has to find the floor, and can't until the
--- floor is there to find.
local function restingZ(spot)
    if not spot.settle then return spot.z end

    local found, z = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 1.5, false)
    if not found then return nil end

    return z + Config.Ball.radius
end

local function remove(key)
    local prop = props[key]
    if not prop then return end

    if DoesEntityExist(prop.obj) then DeleteEntity(prop.obj) end
    props[key] = nil
end

local function put(key, courtId, index, spot)
    local z = restingZ(spot)
    if not z then return end

    local model = Config.Ball.model
    if not loadModel(model) then return end

    local obj = CreateObject(model, spot.x, spot.y, z, false, false, false)
    SetModelAsNoLongerNeeded(model)

    if not obj or obj == 0 then return end

    -- Something to look at and pick up, not something to trip over.
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    SetEntityCoordsNoOffset(obj, spot.x, spot.y, z, false, false, false)

    props[key] = { obj = obj, x = spot.x, y = spot.y, z = z, court = courtId, index = index }
end

CreateThread(function()
    while true do
        local wait = 1000
        local me = GetEntityCoords(PlayerPedId())
        local taken = GlobalState[BB.STATE_BALLS] or {}
        local wanted = {}
        local nearest, nearestDist

        for courtId, court in pairs(BB.courts) do
            if #(me - court.centre) < 90.0 then
                local gone = taken[courtId] or {}

                for index, spot in ipairs(BB.ballSpots(court)) do
                    if not gone[tostring(index)] then
                        local key = courtId .. ':' .. index
                        wanted[key] = true

                        if not props[key] then put(key, courtId, index, spot) end

                        local prop = props[key]

                        -- One I bent down for and didn't get (somebody else
                        -- did, or the server said no) is put back in view.
                        if prop and prop.hiddenUntil and GetGameTimer() > prop.hiddenUntil then
                            prop.hiddenUntil = nil
                            SetEntityVisible(prop.obj, true, false)
                        end

                        if prop and not prop.hiddenUntil then
                            local dist = #(me - vec3(prop.x, prop.y, prop.z))
                            if dist < Config.Ball.catchRadius and (not nearestDist or dist < nearestDist) then
                                nearest, nearestDist = prop, dist
                            end
                        end
                    end
                end
            end
        end

        for key in pairs(props) do
            if not wanted[key] then remove(key) end
        end

        if nearest and not BB.isHolding() and not BB.placing then
            wait = 0
            BB.look.ball(vec3(nearest.x, nearest.y, nearest.z), nearest.court .. ':' .. nearest.index)

            -- Bend down for it. The one lying there goes out of sight at once and
            -- the one that arrives in the hands is gathered in from the same
            -- spot, so it is one ball coming up off the floor rather than one
            -- vanishing a moment after another has appeared.
            if IsControlJustReleased(0, Config.Keys.pickup)
                and BB.scoop(vec3(nearest.x, nearest.y, nearest.z)) then
                nearest.hiddenUntil = GetGameTimer() + 2500
                SetEntityVisible(nearest.obj, false, false)

                TriggerServerEvent('gk_basketball:takeLooseBall', nearest.court, nearest.index)
            end
        end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for key in pairs(props) do remove(key) end
end)
