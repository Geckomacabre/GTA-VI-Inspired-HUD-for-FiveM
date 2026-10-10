-- World blips + proximity prompts at each race's start location, matching
-- StreetKings' freeroam-marker discovery pattern (races are found scattered
-- across the map, not funneled through a single NPC).

local points = {}

local function schemeBlipSprite(scheme, kind)
    -- Sprite 16 is the airport marker; there is no separate offroad sprite, so offroad keeps the
    -- sprint icon and is told apart by its colour and its name.
    if kind == 'air' then return 16 end
    if scheme == 'circuit' then return 306 end
    if scheme == 'thereandback' then return 307 end
    return 350
end

-- Returns (isLocked, reasonText) for a route given the player's current progress.
local function lockStateFor(def, progress)
    local req = def.unlockRequirement
    if not req then return false end

    if req.barnFindsCompleted then
        local have = progress.barnFindsCompleted or 0
        if have < req.barnFindsCompleted then
            return true, ('Locked — find %d barn finds first (%d/%d)'):format(req.barnFindsCompleted, have, req.barnFindsCompleted)
        end
    end

    return false
end

-- Routes entered from the same spot (all five stunt-plane courses share the Sandy Shores hangar)
-- get one blip and one prompt that opens a list, instead of five on top of each other.
local function spotKey(def, entry)
    if def.entry then return ('%d:%d'):format(math.floor(entry.x), math.floor(entry.y)) end
    return def.id or tostring(def)
end

local function kindLabel(kind)
    return kind == 'air' and 'Air Race' or (kind == 'offroad' and 'Offroad Race' or 'Race')
end

local function openSpotMenu(spot, progress)
    local options = {}
    for _, item in ipairs(spot.items) do
        local locked, reason = lockStateFor(item.def, progress)
        options[#options + 1] = {
            title       = item.def.name,
            description = locked and reason or (item.def.medals
                and ('Gold %s  |  %d gates'):format(SKFormatTime(item.def.medals.gold * 1000), #item.def.checkpoints)
                or ('%d gates'):format(#item.def.checkpoints)),
            disabled    = locked,
            onSelect    = function() OpenRaceChooser(item.id) end,
        }
    end
    table.sort(options, function(a, b) return a.title < b.title end)
    lib.registerContext({ id = 'sk_racing_spot', title = spot.title, options = options })
    lib.showContext('sk_racing_spot')
end

local function refreshRoutes()
    local routes = lib.callback.await('sk_streetkings:racing:getRoutes', false) or {}
    local progress = lib.callback.await('sk_streetkings:racing:getPlayerProgress', false) or { barnFindsCompleted = 0 }

    for _, point in ipairs(points) do point:remove() end
    points = {}

    local spots, order = {}, {}
    for id, def in pairs(routes) do
        def.id = def.id or id
        -- An air race starts in the sky, so it is entered from the ground at its own entry point.
        local entry = SKRaceVehicle.entryPoint(def)
        local key = spotKey(def, entry)
        if not spots[key] then
            spots[key] = { coords = entry, kind = def.kind, scheme = def.scheme, items = {} }
            order[#order + 1] = key
        end
        local spot = spots[key]
        spot.items[#spot.items + 1] = { id = id, def = def }
    end

    for _, key in ipairs(order) do
        local spot = spots[key]
        local single = #spot.items == 1 and spot.items[1] or nil
        local isLocked, lockReason = false, nil
        if single then isLocked, lockReason = lockStateFor(single.def, progress) end

        local label = kindLabel(spot.kind)
        spot.title = single and single.def.name or (label .. 's')

        local blip = AddBlipForCoord(spot.coords.x, spot.coords.y, spot.coords.z)
        SetBlipSprite(blip, schemeBlipSprite(spot.scheme, spot.kind))
        -- 4 = grey, 5 = yellow, 2 = green (offroad), 3 = light blue (air)
        SetBlipColour(blip, isLocked and 4 or (spot.kind == 'air' and 3 or (spot.kind == 'offroad' and 2 or 5)))
        SetBlipScale(blip, isLocked and 0.65 or 0.8)
        SetBlipAsShortRange(blip, true)
        SetBlipCategory(blip, 7)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(single
            and (isLocked and ('%s: %s (Locked)'):format(label, single.def.name) or ('%s: %s'):format(label, single.def.name))
            or spot.title)
        EndTextCommandSetBlipName(blip)

        local promptText = single
            and (isLocked and ('%s — %s'):format(single.def.name, lockReason) or ('[E] %s: %s'):format(label, single.def.name))
            or ('[E] %s'):format(spot.title)

        points[#points + 1] = lib.points.new({
            coords = vec3(spot.coords.x, spot.coords.y, spot.coords.z),
            distance = 25.0,
            onEnter = function()
                lib.showTextUI(promptText, { position = 'left-center' })
            end,
            onExit = function()
                lib.hideTextUI()
            end,
            nearby = function(self)
                if self.currentDistance < 8.0 and IsControlJustPressed(0, 38) then
                    lib.hideTextUI()
                    if not single then
                        openSpotMenu(spot, progress)
                    elseif isLocked then
                        lib.notify({ title = 'Racing', description = lockReason, type = 'error' })
                    else
                        OpenRaceChooser(single.id)
                    end
                end
            end,
        })
    end
end

RegisterNetEvent('sk_streetkings:racing:admin:routeSaved', refreshRoutes)
RegisterNetEvent('sk_streetkings:racing:admin:routeDeleted', refreshRoutes)

CreateThread(function()
    Wait(1000)
    refreshRoutes()
end)
