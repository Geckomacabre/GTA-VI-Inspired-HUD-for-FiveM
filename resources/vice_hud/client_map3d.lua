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
-- one from where it publishes the map's rect, since the drawn map stands
-- where the single-player minimap's panel does:
--
--   ViceMap3D.rect()            that rect while the map could be drawn, else nil
--
-- and one from its wanted readout, which already works out what the police
-- know for the stars:
--
--   ViceMap3D.police(state)     'contact', 'searching', 'red', 'hollow' or nil
--
-- and one from its status readout, which already knows whether the player is
-- spending stamina:
--
--   ViceMap3D.ripple(on)        rings going out from the player's marker
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
local policeState = nil     -- what the police know, as client.lua last said
local wantSent = nil        -- the wanted colouring the page was last told
local pinging = false       -- and whether the chase rings are going
local rippling = false      -- the player is spending stamina, as client.lua last said
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
        if C.clock == false then view.clock = false end
        if C.altitude == false then view.altitude = false end
        msg.config = { view = view, paint = C.paint, paintNight = C.paintNight,
                       ripple = type(C.ripple) == 'table' and C.ripple or nil }
    end
    -- Said again with every "draw": the page may have been reloaded, or the
    -- map may have been down while the police found or lost the player.
    if drawing then
        msg.want = wantSent or false
        msg.ping = pinging
        msg.ripple = rippling
    end
    say('map3d', msg)
    if drawing then routeDirty = true end
end

--- The single-player minimap's panel, which the drawn map stands in: 208
--- by 115 of its units (a 720th of the screen's height), 4 in from the safe
--- zone's left edge and 8.5 up from its bottom. In percent of the screen, as
--- client.lua publishes the map's rect (`bottom` is to the map's TOP): the
--- left and the width of its width, the rest of its height. A unit is as many
--- pixels across as up, so on a screen wider than 16:9 the panel keeps single
--- player's size and shape instead of stretching with the screen.
--- Config.Map3D.panel = 'native' keeps the engine radar's rect instead. Asked
--- whenever the drawn map could stand in, shown or not, so the panels that
--- sit on the map stay put while it is hidden.
function ViceMap3D.rect()
    if C.panel == 'native' or not ViceMap3D.owns() then return nil end
    local rx, ry = GetActiveScreenResolution()
    if not rx or not ry or rx <= 0 or ry <= 0 then rx, ry = 1920, 1080 end
    local u = 100.0 / 720.0                 -- a unit, in percent of the height
    local uw = u * ry / rx                  -- and of the width
    local inset = (1.0 - GetSafeZoneSize()) * 0.5 * 100.0
    local height = 115.0 * u
    return { left = inset + 4.0 * uw, width = 208.0 * uw, height = height, bottom = inset + 8.5 * u + height,
             drawn = true }
end

--- What the police know, in client.lua's own words for it (see wantedState()
--- there). The single-player minimap puts no police on it; what they know
--- shows as the colour of the whole map (the wanted feed below).
function ViceMap3D.police(state)
    if state ~= 'contact' and state ~= 'searching' and state ~= 'red' and state ~= 'hollow' then state = nil end
    policeState = state
end

--- Whether the player is spending stamina. While they are, the reference
--- sends rings out from their marker; the page does the drawing and the
--- timing, this only says when it starts and stops.
function ViceMap3D.ripple(on)
    on = on == true and C.ripple ~= false
    if on == rippling then return end
    rippling = on
    if drawing then say('map3d', { ripple = on }) end
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
-- costs a few native calls a frame and no messages at all. In a helicopter or
-- a plane its height above the ground goes too, which pulls the view back.
local AIRCRAFT = { [15] = true, [16] = true }

-- Out of an aircraft the camera rides at the player's height instead. Two
-- readings, because neither is right alone (the page puts them together, with
-- what it knows of the building under the player; see altitudeWanted() in
-- html/map3d.js):
--
--   over what is beneath them    nothing at all on a roof; everything in the air
--   over the nearest street      right on a roof; anything at all on a hillside
--
-- An entity's own origin is about a metre off the ground it stands on, which
-- is taken off. No street found is nil, and the page goes without it.
local function heightOf(ent, p)
    local over = math.max(0.0, (GetEntityHeightAboveGround(ent) or 0.0) - 1.0)
    local street = nil
    local found, node = GetClosestVehicleNode(p.x, p.y, p.z, 1, 3.0, 0)
    if found and node then street = p.z - node.z end
    return over, street
end

feed('position', function()
    local lx, ly, lc, lh, ls, lv, la = 0.0, 0.0, 0.0, 0.0, -1.0, false, -1.0
    local over, street, lo, lst = 0.0, nil, -1.0, nil
    local heightAt = 0
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
            local air = 0.0
            if veh ~= 0 and AIRCRAFT[GetVehicleClass(veh)] then air = GetEntityHeightAboveGround(veh) or 0.0 end
            -- Height is asked for five times a second, not every frame: the
            -- street lookup is a search, and the page eases between answers.
            local now = GetGameTimer()
            if C.altitude ~= false and (not sentFor or now - heightAt >= 200) then
                heightAt = now
                over, street = heightOf(ent, p)
            end
            if not sentFor
                or math.abs(p.x - lx) + math.abs(p.y - ly) > 0.03
                or math.abs(cam - lc) > 0.05 or math.abs(head - lh) > 0.4
                or math.abs(speed - ls) > 0.4 or (veh ~= 0) ~= lv
                or math.abs(air - la) > 1.0
                or math.abs(over - lo) > 0.4 or (street == nil) ~= (lst == nil)
                or (street ~= nil and math.abs(street - lst) > 0.4) then
                sentFor = true
                lx, ly, lc, lh, ls, lv, la, lo, lst = p.x, p.y, cam, head, speed, veh ~= 0, air, over, street
                say('map3dPos', { x = round(p.x, 2), y = round(p.y, 2), c = round(cam, 2), h = round(head, 1), s = round(speed, 1),
                                  v = veh ~= 0, air = air > 0.0 and round(air, 0) or nil,
                                  g = round(over, 1), a = street and round(street, 1) or nil })
            end
            Wait(0)
        end
    end
end)

-- ---- day and night, and the clock --------------------------------------------
-- The map has a daytime look and a night one, and the page mixes between them
-- by a number from 0 to 1. This is that number, off the game's clock: night
-- from `night` o'clock until `day`, coming on over the half hour before
-- `night` and the hour after it, and going over the hour before `day` and the
-- half hour after it (19:30 to 21:00, 5:00 to 6:30). Single player does the
-- same. The page also gets the time, for the clock it shows on the half hour.
local function nightNow()
    if C.night == false then return 0.0 end
    if C.night == 'always' then return 1.0 end
    local h = C.nightHours or {}
    local day, dark = h.day or 6, h.night or 20
    local dusk, black, dawn, light = dark - 0.5, dark + 1.0, day - 1.0, day + 0.5
    local t = GetClockHours() + GetClockMinutes() / 60.0
    if t >= black or t < dawn then return 1.0 end
    if t >= dusk then return (t - dusk) / (black - dusk) end
    if t < light then return 1.0 - (t - dawn) / (light - dawn) end
    return 0.0
end

feed('clock', function()
    local sentNight, sentMinute = -1, -1
    while true do
        if drawing then
            local n, h, m = round(nightNow(), 3), GetClockHours(), GetClockMinutes()
            if n ~= sentNight or m ~= sentMinute then
                sentNight, sentMinute = n, m
                say('map3d', { night = n, clock = { h, m } })
            end
            Wait(500)
        else
            sentNight, sentMinute = -1, -1
            Wait(2000)
        end
    end
end)

-- ---- wanted ---------------------------------------------------------------------
-- The single-player minimap's wanted colouring, decided here and painted by
-- the page: blue for the first five seconds of being wanted, red for a moment
-- and a half after the player shoots or aims at someone, red and blue a
-- second each (red first) while the police can see them or are searching,
-- blue under hollow stars, nothing under red ones. And while the stars are
-- not greyed out -- the police are on the player -- rings go out from the
-- marker. Config.Map3D.police = false switches both off.
local wantedSince, crimeAt, chaseSince = 0, -1e9, nil

local function wantedNow(ped, pid, now)
    if C.police == false or GetPlayerWantedLevel(pid) <= 0 then
        wantedSince, chaseSince = 0, nil
        return nil, false
    end
    if wantedSince == 0 then wantedSince = now end
    local shooting = IsPedShooting(ped)
    if not shooting and IsPlayerFreeAiming(pid) then
        local ok, ent = GetEntityPlayerIsFreeAimingAt(pid)
        shooting = ok and ent ~= 0 and IsEntityAPed(ent)
    end
    if shooting then crimeAt = now end
    local ping = not ArePlayerStarsGreyedOut(pid)
    local age = now - wantedSince
    if age < 5000 then chaseSince = nil return 'blue', ping end
    if now - crimeAt < 1500 then chaseSince = nil return 'red', ping end
    if policeState == 'contact' or policeState == 'searching' then
        chaseSince = chaseSince or now
        return ((now - chaseSince) // 1000) % 2 == 0 and 'red' or 'blue', ping
    end
    chaseSince = nil
    return policeState == 'hollow' and 'blue' or nil, ping
end

feed('wanted', function()
    while true do
        if not drawing then
            Wait(250)
        else
            local pid = PlayerId()
            local now = GetGameTimer()
            local kind, ping = wantedNow(PlayerPedId(), pid, now)
            local msg = nil
            if kind ~= (wantSent and wantSent.kind) then
                wantSent = kind and { kind = kind, age = now - wantedSince } or nil
                msg = { want = wantSent or false }
            end
            if ping ~= pinging then
                pinging = ping
                msg = msg or {}
                msg.ping = ping
            end
            if msg then say('map3d', msg) end
            -- Every frame while wanted, to catch a shot; four times a second
            -- otherwise.
            Wait(wantedSince ~= 0 and 0 or 250)
        end
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

-- The single-player HUD's route colours: a waypoint's line teal, a
-- mission's (some script's route) pink, each with a lighter rim.
local TEAL, TEAL_RIM = { 71, 171, 167 }, { 172, 217, 215 }
local PINK, PINK_RIM = { 252, 116, 164 }, { 254, 192, 214 }

-- Both set by the blip scan further down.
local routedBlip = nil      -- the blip some script has given a route
local places = {}           -- every still blip, as the page gets them

--- The still blip a point is on, if any. A waypoint set on a place in the
--- pause map lands on that place's blip, so "is the waypoint on a place?" is
--- "is there a blip within 6 m of it?".
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
            -- The line, on foot as in a vehicle, and where it ends. A waypoint
            -- set on a place carries that place's picture and colour, which
            -- the page draws in place of the pin.
            local ped = PlayerPedId()
            local routes, ends, remaining = {}, {}, nil
            if IsWaypointActive() then
                for _, run in ipairs(walkRoute(0)) do
                    routes[#routes + 1] = { pts = run, rgb = TEAL, rim = TEAL_RIM }
                end
                -- The stock waypoint sprite is left out of the blips: this is it.
                local blip = GetFirstBlipInfoId(8)
                if DoesBlipExist(blip) then
                    local at = GetBlipInfoIdCoord(blip)
                    local e = { x = round(at.x, 1), y = round(at.y, 1), kind = 'waypoint' }
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
                for _, run in ipairs(walkRoute(1)) do
                    routes[#routes + 1] = { pts = run, rgb = PINK, rim = PINK_RIM }
                end
                local at = GetBlipInfoIdCoord(routed.blip)
                ends[#ends + 1] = { x = round(at.x, 1), y = round(at.y, 1), kind = 'mission' }
            end
            if #routes > 0 then
                local length = GetGpsBlipRouteLength()
                if length and length > 0 then remaining = length + 0.0 end
            end
            if #routes > 0 or #ends > 0 or hadRoute or routeDirty then
                routeDirty = false
                hadRoute = #routes > 0 or #ends > 0
                say('map3dRoute', { routes = routes, ends = ends, remaining = remaining })
            end
            -- The page finds the player on the line every frame, so the line
            -- itself only has to be fetched often enough to follow a re-plan.
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
-- SET_BLIP_DISPLAY values that keep a blip off the radar: 0, 1 and 7 hide it
-- everywhere, 3 is the pause map only. NOT 4. FiveM's documentation lists 4 as
-- "main map only", but it is what almost every script passes
-- (SetBlipDisplay(blip, 4)) and the engine's radar shows those blips; leaving
-- 4 in this list threw away nearly every blip on a real server.
local NOT_ON_MINIMAP = { [0] = true, [1] = true, [3] = true, [7] = true }
-- Config.Map3D.hiddenBlips, as a set.
local HIDDEN_SPRITE = {}
for _, sprite in ipairs(C.hiddenBlips or {}) do HIDDEN_SPRITE[sprite] = true end
local BLIP_CAP = 400

-- Police are not drawn, only the colour of the whole map (the wanted feed
-- above), so the blips the game hangs on officers, their cars and their
-- helicopters are left out: by sprite, and for a blip riding a ped or a
-- vehicle, by who that is. Stations (60, 137, 526) are places, not police,
-- and stay. So does another player, whatever their job.
local POLICE_SPRITE = { [3] = true, [15] = true, [16] = true, [41] = true, [42] = true, [43] = true,
                        [56] = true, [58] = true, [128] = true, [227] = true, [233] = true, [672] = true }
local POLICE_PED = { [6] = true, [27] = true, [29] = true }     -- cop, SWAT, army

local function isPolice(blip, sprite, kind)
    if C.policeBlips == true then return false end
    if POLICE_SPRITE[sprite] then return true end
    if kind ~= 1 and kind ~= 2 then return false end
    local ent = GetBlipInfoIdEntityIndex(blip)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return false end
    if IsEntityAVehicle(ent) then ent = GetPedInVehicleSeat(ent, -1) end
    if not ent or ent == 0 or not IsEntityAPed(ent) or IsPedAPlayer(ent) then return false end
    return POLICE_PED[GetPedType(ent)] == true
end

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

--- `riding` for a blip on an entity: is it a vehicle, or someone in one?
--- (The page draws those dots half as big again.) The handle goes last, so
--- the page can follow a blip from one list to the next.
local function describe(blip, sprite, riding)
    local p = GetBlipInfoIdCoord(blip)
    local c = blipColour(blip)
    -- Nothing about which way the blip is turned: the radar draws every icon
    -- upright, and turning them with the camera made them spin on the map.
    local flags = IsBlipShortRange(blip) and 0 or 1
    if riding then
        local ent = GetBlipInfoIdEntityIndex(blip)
        if ent and ent ~= 0 and DoesEntityExist(ent)
            and (IsEntityAVehicle(ent) or (IsEntityAPed(ent) and IsPedInAnyVehicle(ent, false))) then
            flags = flags + 2
        end
    end
    return { round(p.x, 1), round(p.y, 1), sprite, c[1], c[2], c[3], GetBlipAlpha(blip), flags, blip }
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
                            if HIDDEN_SPRITE[sprite] or isPolice(blip, sprite, kind) then
                                -- not drawn
                            elseif kind == 1 or kind == 2 or kind == 3 then
                                found[blip] = sprite
                            elseif kind ~= 7 then
                                static[#static + 1] = describe(blip, sprite)
                            end
                            if DoesBlipHaveGpsRoute(blip) then routed = { blip = blip } end
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
                if DoesBlipExist(blip) then list[#list + 1] = describe(blip, sprite, true) end
            end
            if #list > 0 or had then
                had = #list > 0
                say('map3dMoving', { list = list })
            end
            Wait(120)
        end
    end
end)
