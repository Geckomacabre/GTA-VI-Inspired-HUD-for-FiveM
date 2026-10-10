-- The drawn minimap's game side (Config.Map3D).
--
-- html/map3d.js paints the island in flat colour with its buildings standing,
-- where the engine's radar would be. This file decides when it stands in for
-- the radar, and feeds it what the engine would have drawn on its own: where
-- the player is and which way the camera looks, the GPS line, and the blips.
--
-- What crosses to client.lua is two calls, both made from its setRadar():
--
--   ViceMap3D.owns()            could the drawn map stand in for the radar
--                               right now? (not inside a building's interior,
--                               where the engine's floor plan is the better
--                               map; not before the page has its world; not
--                               after its feed has failed)
--   ViceMap3D.show(on, north)   draw it or do not, and whether north is marked
--
-- Loaded before client.lua so the table exists by the time setRadar runs.
-- Nothing here reaches back into client.lua.
--
-- The engine's radar is only ever hidden by client.lua, through DisplayRadar,
-- and only while owns() is true: switch this off (/hudmap3d, or the page
-- failing to load its world) and the next setRadar puts the real one back.

ViceMap3D = {}

local C = Config.Map3D or {}
local KVP = 'vice_hud:map3d'

-- The player's own choice (/hudmap3d) beats the config default.
local chosen = C.enabled == true
do
    local saved = GetResourceKvpString(KVP)
    if saved == 'on' then chosen = true elseif saved == 'off' then chosen = false end
end

local broken = false        -- the feed below has failed: hand the map back
local pageUp = false        -- the page is listening
local pageOk = false        -- the page has loaded its world and can draw
local pageWhy = nil         -- and if it cannot, what it said
local drawing = false       -- what the page was last told
local north = true
local configSent = false
local routeDirty = true

local function say(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

local function round(v, places)
    local m = 10 ^ (places or 0)
    return math.floor(v * m + 0.5) / m
end

function ViceMap3D.owns()
    if not chosen or not pageOk or broken then return false end
    if C.engineIndoors ~= false and GetInteriorFromEntity(PlayerPedId()) ~= 0 then return false end
    return true
end

--- `on` is "draw it": client.lua has already asked owns(), so this does not
--- ask again (and cannot disagree with what the engine's radar was told).
function ViceMap3D.show(on, showNorth)
    local want = on and true or false
    if showNorth ~= nil and (showNorth and true or false) ~= north then
        north = showNorth and true or false
        configSent = false
    end
    if want == drawing and configSent then return end
    drawing = want

    local msg = { show = drawing }
    if not configSent then
        configSent = true
        local view = {}
        for k, v in pairs(C.view or {}) do view[k] = v end
        view.north = north and view.north ~= false
        view.buildings = C.buildings ~= false
        msg.config = { view = view, paint = C.paint, paintNight = C.paintNight }
    end
    say('map3d', msg)
    if drawing then routeDirty = true end
end

-- The page says hello each time it loads, which is also each time it
-- RE-loads: everything it was told before is gone. It fetches nothing until
-- asked, so a player who has the drawn map off never downloads its world.
RegisterNUICallback('map3dHello', function(_, cb)
    pageUp, pageOk, pageWhy = true, false, nil
    drawing, configSent = false, false
    if chosen then say('map3d', { load = true }) end
    cb({})
end)

RegisterNUICallback('map3dReady', function(d, cb)
    pageOk = d and d.ok == true
    pageWhy = d and d.why or nil
    drawing, configSent = false, false
    routeDirty = true
    if not pageOk and chosen then
        print(('^3[vice_hud]^7 the drawn minimap is off, the engine\'s radar stays: %s')
            :format(tostring(pageWhy or 'the page gave no reason')))
    end
    cb({})
end)

RegisterCommand('hudmap3d', function()
    chosen = not chosen
    SetResourceKvp(KVP, chosen and 'on' or 'off')
    if chosen and pageUp and not pageOk then say('map3d', { load = true }) end
    local state = chosen and (pageOk and 'on' or ('on, but unavailable: ' .. tostring(pageWhy or 'not loaded yet'))) or 'off'
    print(('^2[vice_hud]^7 drawn minimap %s'):format(state))
    if lib and lib.notify then
        lib.notify({ title = 'Minimap', description = chosen and 'Drawn 3D minimap' or 'Game radar', type = 'inform' })
    end
end, false)

exports('IsMap3D', function() return drawing end)

-- Each of the three feeds below runs in its own thread, and none of them is
-- allowed to fail quietly. If the position feed stops, the drawn map would sit
-- frozen over a hidden radar, so that one hands the map back to the engine.
local function feed(name, fn)
    CreateThread(function()
        local okay, err = pcall(fn)
        if okay then return end
        print(('^1[vice_hud]^7 drawn minimap: the %s feed stopped: %s'):format(name, tostring(err)))
        if name == 'position' then
            broken = true
            print('^3[vice_hud]^7 the engine\'s radar is back in its place.')
        end
    end)
end

-- ---- where the player is -----------------------------------------------------
-- Every frame while the map is up, and only what changed: a parked player
-- costs four native calls a frame and no messages at all.
feed('position', function()
    local lx, ly, lc, lh, ls = 0.0, 0.0, 0.0, 0.0, -1.0
    local sentFor = false
    while true do
        if not drawing then
            sentFor = false
            Wait(200)
        else
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            local ent = veh ~= 0 and veh or ped
            local p = GetEntityCoords(ent)
            local cam = GetFinalRenderedCamRot(2).z
            local head = GetEntityHeading(ent)
            -- Only a vehicle's speed pulls the view back, as on the radar.
            local speed = veh ~= 0 and GetEntitySpeed(veh) or 0.0
            if not sentFor
                or math.abs(p.x - lx) + math.abs(p.y - ly) > 0.03
                or math.abs(cam - lc) > 0.05 or math.abs(head - lh) > 0.4
                or math.abs(speed - ls) > 0.4 then
                sentFor = true
                lx, ly, lc, lh, ls = p.x, p.y, cam, head, speed
                say('map3dPos', { x = round(p.x, 2), y = round(p.y, 2), c = round(cam, 2), h = round(head, 1), s = round(speed, 1) })
            end
            Wait(0)
        end
    end
end)

-- ---- day and night ---------------------------------------------------------------
-- The map has a daytime look and a night one, and the page mixes between them
-- by a number from 0 to 1. This is that number, off the game's own clock: fully
-- night from `dark` to `dawn`, changing gradually either side of it.
local function nightNow()
    if C.night == false then return 0.0 end
    if C.night == 'always' then return 1.0 end
    local h = C.nightHours or {}
    local dusk, dark, dawn, light = h.dusk or 19.5, h.dark or 21.0, h.dawn or 5.0, h.light or 6.5
    local t = GetClockHours() + GetClockMinutes() / 60.0
    if t >= dark or t < dawn then return 1.0 end
    if t >= dusk then return (t - dusk) / (dark - dusk) end
    if t < light then return 1.0 - (t - dawn) / (light - dawn) end
    return 0.0
end

feed('clock', function()
    local sent = -1.0
    while true do
        if drawing then
            local n = nightNow()
            if math.abs(n - sent) > 0.01 then
                sent = n
                say('map3d', { night = round(n, 3) })
            end
        else
            sent = -1.0
        end
        Wait(2000)
    end
end)

-- ---- the GPS line --------------------------------------------------------------
-- The engine will not hand a route over, but it will say where a point so many
-- metres along it is. Walk that out to routeLength and there is the line.
-- Slot 0 is the player's own waypoint, slot 1 a blip some script gave a route.
local ROUTE_LENGTH = (C.route and C.route.length) or 500.0

local function stepAt(d)
    if d < 150.0 then return 3.0 elseif d < 300.0 then return 5.0 end
    return 8.0
end

--- One slot's route as runs of x,y pairs. More than one run when the route
--- jumps (a ferry, a tunnel the road network does not connect across).
---
--- All of it in one frame, on purpose: the game re-plans the route as the
--- player turns, and a walk spread over several frames could come back with
--- the front of one plan joined to the back of another -- a line with a step
--- in it. It is about a hundred cheap calls.
local function walkRoute(slot)
    local runs, run = {}, {}
    local dist, same = 0.0, 0
    local lastx, lasty
    while dist <= ROUTE_LENGTH do
        local ok, pos = GetPosAlongGpsTypeRoute(true, dist, slot)
        if not ok or not pos then break end
        dist = dist + stepAt(dist)
        if lastx then
            local dx, dy = pos.x - lastx, pos.y - lasty
            local d2 = dx * dx + dy * dy
            if d2 < 0.25 then
                -- The same point twice running, past the start: the route's end.
                if dist > 12.0 then
                    same = same + 1
                    if same >= 2 then break end
                end
                goto continue
            end
            same = 0
            if d2 > 2025.0 then                 -- 45 m in one step: a jump
                if #run >= 4 then runs[#runs + 1] = run end
                run = {}
            end
        end
        run[#run + 1] = round(pos.x, 1)
        run[#run + 1] = round(pos.y, 1)
        lastx, lasty = pos.x, pos.y
        ::continue::
    end
    if #run >= 4 then runs[#runs + 1] = run end
    return runs
end

local function hudRgb(index)
    local r, g, b = GetHudColour(index)
    return { r, g, b }
end

-- Both set by the blip scan further down.
local routedBlip = nil      -- the blip some script has given a route
local places = {}           -- every still blip, as the page gets them

--- The still blip a point is on, if any. A waypoint set on a place in the
--- pause map lands on that place's blip, so "is the waypoint on a place?" is
--- "is there a blip within a few metres of it?".
local function placeAt(x, y)
    local best, bestD = nil, 36.0
    for i = 1, #places do
        local b = places[i]
        local dx, dy = b[1] - x, b[2] - y
        local d = dx * dx + dy * dy
        if d < bestD then best, bestD = b, d end
    end
    return best
end

feed('route', function()
    if C.route == false then return end
    local hadRoute = false
    while true do
        if not drawing then
            Wait(500)
        else
            -- Each route ends in a ring: four arcs in the route's light
            -- colour. What sits in the ring is the page's business, from what
            -- it is told here -- the picture of the place the route ends at,
            -- or, for a waypoint dropped on open ground, nothing but colour.
            local routes, ends = {}, {}
            if IsWaypointActive() then
                -- 142 / 150 are the waypoint's own purple and its light, which
                -- client.lua has already repainted in the HUD's accent.
                local fill, light = hudRgb(142), hudRgb(150)
                for i, run in ipairs(walkRoute(0)) do
                    routes[#routes + 1] = { pts = run, rgb = fill, rim = light, head = i == 1 }
                end
                -- The stock waypoint sprite is left out of the blips: this is it.
                local blip = GetFirstBlipInfoId(8)
                if DoesBlipExist(blip) then
                    local at = GetBlipInfoIdCoord(blip)
                    local e = { x = round(at.x, 1), y = round(at.y, 1), rgb = fill, ring = light }
                    local place = placeAt(at.x, at.y)
                    if place then
                        e.icon = place[3]
                        e.iconRgb = { place[4], place[5], place[6] }
                    end
                    ends[#ends + 1] = e
                end
            end
            local routed = routedBlip
            if routed and DoesBlipExist(routed.blip) then
                for i, run in ipairs(walkRoute(1)) do
                    routes[#routes + 1] = { pts = run, rgb = routed.rgb, head = i == 1 }
                end
                local at = GetBlipInfoIdCoord(routed.blip)
                ends[#ends + 1] = { x = round(at.x, 1), y = round(at.y, 1), rgb = routed.rgb,
                                    icon = routed.sprite, iconRgb = routed.rgb }
            end
            if #routes > 0 or #ends > 0 or hadRoute or routeDirty then
                routeDirty = false
                hadRoute = #routes > 0 or #ends > 0
                say('map3dRoute', { routes = routes, ends = ends })
            end
            -- The page finds the player on the line every frame, so the line
            -- itself only has to be fetched often enough to follow a re-plan.
            local ped = PlayerPedId()
            Wait(GetEntitySpeed(ped) > 5.0 and 250 or 600)
        end
    end
end)

-- ---- blips -----------------------------------------------------------------------
-- The engine keeps no list a script can read; it can only be asked, sprite by
-- sprite, for the blips wearing that sprite. So: ask for all of them every two
-- seconds, a slice a frame, and in between only follow the ones that move.
local SPRITE_MAX = 1000
local SPRITES_PER_FRAME = 150
-- 4, 5, 9: radius and area shapes. 6, 7: the player and north, which the page
-- draws itself. 8: the waypoint, which the page draws as the route's end.
local SKIP_SPRITE = { [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true }
local NOT_ON_MINIMAP = { [0] = true, [1] = true, [3] = true, [4] = true }
local BLIP_CAP = 400

local colourCache = {}
local function blipColour(blip)
    local index = GetBlipHudColour(blip)
    local c = colourCache[index]
    if not c then
        local r, g, b = GetHudColour(index)
        c = { r, g, b }
        colourCache[index] = c
    end
    return c
end

local function describe(blip, sprite)
    local p = GetBlipInfoIdCoord(blip)
    local c = blipColour(blip)
    local flags = IsBlipShortRange(blip) and 0 or 1
    local rot = GetBlipRotation(blip) or 0
    if rot ~= 0 then flags = flags + 2 end
    return { round(p.x, 1), round(p.y, 1), sprite, c[1], c[2], c[3], GetBlipAlpha(blip), flags, rot }
end

local moving = {}       -- blip handle -> sprite, for blips riding an entity

feed('blip', function()
    if C.blips == false then return end
    while true do
        if not drawing then
            Wait(500)
        else
            local static, found, routed = {}, {}, nil
            local mine = GetMainPlayerBlipId()
            for sprite = 0, SPRITE_MAX do
                if not SKIP_SPRITE[sprite] then
                    local blip = GetFirstBlipInfoId(sprite)
                    while DoesBlipExist(blip) do
                        if blip ~= mine and GetBlipAlpha(blip) > 0
                            and not NOT_ON_MINIMAP[GetBlipInfoIdDisplay(blip)] then
                            local kind = GetBlipInfoIdType(blip)
                            if kind == 1 or kind == 2 or kind == 3 then
                                found[blip] = sprite
                            elseif kind ~= 7 then
                                static[#static + 1] = describe(blip, sprite)
                            end
                            if DoesBlipHaveGpsRoute(blip) then
                                routed = { blip = blip, sprite = sprite, rgb = blipColour(blip) }
                            end
                        end
                        blip = GetNextBlipInfoId(sprite)
                    end
                end
                if sprite % SPRITES_PER_FRAME == SPRITES_PER_FRAME - 1 then Wait(0) end
            end
            moving = found
            routedBlip = routed
            places = static

            local shown = static
            if #static > BLIP_CAP then
                -- Too many to be worth drawing: the nearest are drawn. (All of
                -- them are still places a waypoint can be on.)
                local me = GetEntityCoords(PlayerPedId())
                shown = {}
                for i = 1, #static do shown[i] = static[i] end
                table.sort(shown, function(a, b)
                    return (a[1] - me.x) ^ 2 + (a[2] - me.y) ^ 2 < (b[1] - me.x) ^ 2 + (b[2] - me.y) ^ 2
                end)
                for i = #shown, BLIP_CAP + 1, -1 do shown[i] = nil end
            end
            if drawing then
                say('map3dBlips', { list = shown })
            end
            Wait(2000)
        end
    end
end)

feed('moving blip', function()
    if C.blips == false then return end
    local had = false
    while true do
        if not drawing then
            Wait(500)
        else
            local list = {}
            for blip, sprite in pairs(moving) do
                if DoesBlipExist(blip) then list[#list + 1] = describe(blip, sprite) end
            end
            if #list > 0 or had then
                had = #list > 0
                say('map3dMoving', { list = list })
            end
            Wait(120)
        end
    end
end)
