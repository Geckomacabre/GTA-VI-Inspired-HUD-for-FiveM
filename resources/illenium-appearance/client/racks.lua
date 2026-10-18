-- Rack try-on: the clothes racks inside the clothing stores as targets of their own.
--
-- Where the racks are comes from shared/racks.lua (Config.RackSpots, generated for the vanilla store interiors, per
-- index of Config.Stores) plus Config.Racks.extra / override; what a rack browses and what it costs from
-- Config.Racks (shared/config.lua).
--
--   * In a store: while the player is near a clothing store its racks have targets - sphere zones through the
--     Target wrappers (client/target/) when a target script runs, else an [E] prompt on the rack looked at.
--   * Trying on: the ped is turned with its back to the rack and held, a scripted camera frames the part of it the
--     category is worn on, and the first item goes on. Left / right show the previous / next drawable, up / down the
--     item's textures (blacklisted ones are passed over, through the same helpers as the full menu), Enter buys and
--     wears (the server decides: server/racks.lua), Backspace or Esc leaves. The page shows what is on
--     (web/public/files/racks): it is display only, the keys are read here with every other control off.
--     On a server with vice_hud the HUD draws it instead - its shop panel, its prompts, its wallet - and the
--     page stays shut ("The screen" below).
--   * Leaving: what the ped wears in that slot is what was kept - an item that was bought - else what it came in
--     with. Dying, the full menu opening or the resource stopping leave the same way.
--
-- The full menu at the store's own target (client/shops.lua) is not involved.

if not Config.Racks or not Config.Racks.enabled then return end

local client = client
local RC = Config.Racks
local Keys = RC.keys
local Text = RC.text

local Racks = {} -- store index => its racks: { category, coords, heading, radius }
local Session = nil -- the try-on that is on
local Starting = false

-- is a try-on on (client/shopflag.lua: vice_hud's money is off the screen meanwhile)
function RackTryOnOpen()
    return Session ~= nil
end

local NearStore = nil -- the store with racks the player is at
local ZoneStore = nil -- the store whose racks have target zones up, and the zones' names
local ZoneNames = {}

-- the directions the camera tries, off the rack's own heading, when something stands in its way
local Fan = { 0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0 }

-- =============================================================================
-- The racks of each store
-- =============================================================================
local function IsCategoryEnabled(name)
    local category = RC.categories[name]
    if not category then return false end
    if category.disable then
        local switches = category.prop and Config.DisableProps or Config.DisableComponents
        if switches and switches[category.disable] then return false end
    end
    return true
end

local function BuildRacks()
    local spots = Config.RackSpots or {}
    for index, store in pairs(Config.Stores) do
        if store.type == "clothing" then
            local list = {}
            local own = (RC.override and RC.override[index]) or spots[index] or {}
            local extra = (RC.extra and RC.extra[index]) or {}
            for _, source in ipairs({ own, extra }) do
                for i = 1, #source do
                    local rack = source[i]
                    if type(rack) == "table" and type(rack.coords) == "vector3" and IsCategoryEnabled(rack.category) then
                        list[#list + 1] = {
                            category = rack.category,
                            coords = rack.coords,
                            heading = tonumber(rack.heading) or 0.0,
                            radius = tonumber(rack.radius)
                        }
                        if Config.Debug and #(rack.coords - store.coords.xyz) > RC.range then
                            print(("[racks] a %s rack of store %d is farther than Config.Racks.range from the store's coords"):format(rack.category, index))
                        end
                    end
                end
            end
            if #list > 0 then
                Racks[index] = list
            end
        end
    end
end

BuildRacks()

-- =============================================================================
-- Helpers
-- =============================================================================
local function Forward(heading)
    local angle = math.rad(heading)
    return vector3(-math.sin(angle), math.cos(angle), 0.0)
end

local function Notify(description)
    lib.notify({
        description = description,
        type = "error",
        position = Config.NotifyOptions.position
    })
end

-- dead, in last stand or cuffed, as the framework sees it
local function PlayerUnfit()
    if not Framework.CheckPlayerMeta then return false end
    local ok, unfit = pcall(Framework.CheckPlayerMeta)
    return ok and unfit and true or false
end

-- an item's price with tax, as the server will charge it (the server's own figure replaces it on the page)
local function GetTotal(category)
    local price = category.price or RC.defaultPrice or 0
    local taxRate = RC.taxRate or Config.TaxRate or 0
    return math.floor(price * (1 + taxRate) + 0.5)
end

local function GetWorn(ped, category)
    if category.prop then
        return {
            drawable = GetPedPropIndex(ped, category.prop),
            texture = GetPedPropTextureIndex(ped, category.prop)
        }
    end
    return {
        drawable = GetPedDrawableVariation(ped, category.component),
        texture = GetPedTextureVariation(ped, category.component)
    }
end

local function Wear(ped, category, drawable, texture)
    if category.prop then
        client.setPedProp(ped, { prop_id = category.prop, drawable = drawable, texture = texture })
    else
        client.setPedComponent(ped, { component_id = category.component, drawable = drawable, texture = texture })
    end
end

-- the range and the blacklist for the slot, its textures being those of the drawable that is on (this asks the
-- server for the player's aces: it takes a moment)
local function GetSettings(ped, category)
    if category.prop then
        return client.getPropSettings(ped, category.prop)
    end
    return client.getComponentSettings(ped, category.component)
end

local function ListDrawables(settings, category)
    local blocked = {}
    for _, drawable in pairs(settings.blacklist.drawables) do
        blocked[drawable] = true
    end

    local list = {}
    for drawable = math.max(settings.drawable.min, 0), settings.drawable.max do
        if not blocked[drawable] and drawable ~= category.empty then
            list[#list + 1] = drawable
        end
    end
    return list
end

local function ListTextures(settings)
    local blocked = {}
    for _, texture in pairs(settings.blacklist.textures) do
        blocked[texture] = true
    end

    local list = {}
    for texture = 0, math.max(settings.texture.max, 0) do
        if not blocked[texture] then
            list[#list + 1] = texture
        end
    end
    return list
end

-- =============================================================================
-- The screen
-- =============================================================================
-- Who draws the try-on. A server with vice_hud has a HUD that keeps the wallet (it shows the new total and the
-- "- $80" itself when money goes) and has a shop panel of its own, made after the same game's stores. There the
-- try-on is the HUD's to draw - its panel (ShowShopItem), its action prompts, its feed - and this resource's overlay
-- stays shut: one wallet on the screen, the HUD's. Else the overlay draws it (web/public/files/racks/racks.js), with
-- the cash only when no vice_hud is there to show it. Config.Racks.hud = "own" keeps the overlay whatever runs.
local PromptIds = { "illenium_rack_item", "illenium_rack_colour", "illenium_rack_buy", "illenium_rack_exit" }
local ViceUp = false -- vice_hud's panel is up

local function ViceRunning()
    return GetResourceState("vice_hud") == "started"
end

-- one of vice_hud's exports: false when it does not run, or is one that has no such export
local function Vice(name, ...)
    if not ViceRunning() then return false end
    local args = table.pack(...)
    return (pcall(function()
        exports.vice_hud[name](nil, table.unpack(args, 1, args.n))
    end))
end

-- how many of vice_hud's swatches fit on the screen's bottom line beside its row of prompts (a swatch with its gap
-- is 11.2 % of the screen's height wide, the prompts and the margins some 63 %): eight on 16:9 and 16:10, six on 4:3
local function SwatchRoom()
    return math.max(3, math.min(8, math.floor((GetAspectRatio(false) * 98.2 - 63.0) / 11.2)))
end

local function IsWorn(session)
    return session.drawables[session.position] == session.keep.drawable and session.texture == session.keep.texture
end

local function SendHud(session)
    local category = session.category
    local drawable = session.drawables[session.position]
    local label = category.label:upper()
    local count = #session.textures
    local at = 1
    for i = 1, count do
        if session.textures[i] == session.texture then
            at = i
            break
        end
    end

    local worn = IsWorn(session)
    local poor = not worn and session.afford == false
    local name = ("%s %d"):format(label, drawable)
    local colour = Text.colour:format(at, count)
    local store = (Config.Stores[session.store] or {}).label or Text.store or "Clothing Store"
    local kind, id = category.prop and "prop" or "component", category.prop or category.component

    if RC.hud ~= "own" then
        -- vice_hud's panel. A swatch there is the texture's thumbnail (thumbs/, shot off the game with
        -- fivem-greenscreener, else the public set) or, on a vice_hud that shows none, a colour taken off it: the
        -- overlay finds both (racks.js answers a `sample` once the flicking through the rack has stopped), grey
        -- until then and where there is no thumbnail. Its row holds as many as the screen has room for: the ones
        -- around the texture that is on. Its "$" is on all but the one that is kept.
        local key = ("%s:%s:%s:%d:%d"):format(kind, id, session.gender, drawable, count)
        local colours = session.colours and session.colours.key == key and session.colours.list or nil
        local images = colours and session.colours.images or nil
        local room = SwatchRoom()
        local first = math.max(1, math.min(at - math.floor(room / 2), count - room + 1))
        local swatches = {}
        for i = first, math.min(count, first + room - 1) do
            swatches[#swatches + 1] = {
                color = colours and colours[i] or "#3a3a42",
                image = images and images[i] or nil,
                locked = not (worn and i == at)
            }
        end

        if Vice("ShowShopItem", {
            store = store,
            category = category.label,
            price = not worn and session.price or nil, -- (what is kept has no price on it)
            pay = worn and { "none" } or { "bank", "cash" },
            name = name,
            variant = worn and ("%s - %s"):format(colour, Text.wearing) or colour,
            swatches = swatches,
            selected = at - first + 1,
            afford = not poor
        }) then
            if not ViceUp then
                ViceUp = true
                SendNUIMessage({ racks = { open = false } })
            end

            -- (its prompts lie in a row while its panel is up, in the order they first came - on the same line as
            -- the swatches, so their labels are short)
            Vice("ShowActionPrompt", PromptIds[1], (Text.item or "Item %d/%d"):format(session.position, #session.drawables), Keys.next)
            Vice("ShowActionPrompt", PromptIds[2], Text.colourKey or "Colour", Keys.colourNext, { off = count < 2 })
            Vice("ShowActionPrompt", PromptIds[3], Text.buy or "Buy & wear", Keys.buy, { off = worn or poor })
            Vice("ShowActionPrompt", PromptIds[4], Text.exit or "Exit", Keys.exit[1])

            if not colours and session.asked ~= key then
                session.asked = key
                SendNUIMessage({
                    racks = {
                        sample = {
                            key = key,
                            kind = kind,
                            id = id,
                            gender = session.gender,
                            drawable = drawable,
                            textures = session.textures
                        }
                    }
                })
            end
            return
        end
    end

    if ViceUp then -- (vice_hud went in the middle of it: the overlay takes over)
        ViceUp = false
        for i = 1, #PromptIds do
            Vice("HideActionPrompt", PromptIds[i])
        end
    end

    SendNUIMessage({
        racks = {
            open = true,
            store = store,
            title = label,
            name = name,
            colour = colour,
            price = session.price,
            cash = not ViceRunning() and session.cash or false, -- (the wallet is vice_hud's to show where it runs)
            status = worn and Text.wearing or (poor and (Text.poor or "Not enough money") or Text.notOwned),
            poor = poor,
            wearing = worn,
            index = session.position,
            count = #session.drawables,
            kind = kind,
            id = id,
            gender = session.gender,
            drawable = drawable,
            textures = session.textures,
            texture = session.texture
        }
    })
end

-- a line for a moment: "Purchased", or why not
local function Toast(text, failed)
    if ViceUp then
        if not Vice("ShowFeed", text) then
            Notify(text)
        end
        return
    end

    SendNUIMessage({
        racks = {
            toast = text,
            failed = failed or false
        }
    })
end

-- all of it off the screen
local function ScreenOff()
    if ViceUp then
        ViceUp = false
        Vice("HideShopItem")
        for i = 1, #PromptIds do
            Vice("HideActionPrompt", PromptIds[i])
        end
    end

    SendNUIMessage({
        racks = {
            open = false
        }
    })
end

-- the overlay's answer to a `sample`: a colour and the thumbnail there is for each of the item's textures, onto
-- vice_hud's panel
RegisterNUICallback("racksColours", function(data, cb)
    cb(1)
    local session = Session
    if not session or type(data) ~= "table" or type(data.colours) ~= "table" or data.key ~= session.asked then return end

    local list, images = {}, {}
    for i = 1, #session.textures do
        local colour = data.colours[i]
        list[i] = type(colour) == "string" and colour:match("^#%x%x%x%x%x%x$") or false
        local image = type(data.images) == "table" and data.images[i]
        images[i] = type(image) == "string" and #image < 200 and image:match("^https://[%w%-%._/]+$") or false
    end
    session.colours = { key = data.key, list = list, images = images }
    if ViceUp then
        SendHud(session)
    end
end)

-- =============================================================================
-- Trying on
-- =============================================================================
-- out of it: the camera back, the ped let go, and on it what was kept (quick: the resource is stopping)
local function Leave(quick)
    local session = Session
    if not session then return end
    Session = nil

    local ped = session.ped
    if DoesEntityExist(ped) then
        Wear(ped, session.category, session.keep.drawable, session.keep.texture)
        FreezeEntityPosition(ped, false)
        if session.invincible then
            SetEntityInvincible(ped, false)
        end
    end

    if session.cam then
        RenderScriptCams(false, not quick, quick and 0 or 400, true, false)
        DestroyCam(session.cam, false)
    end

    ScreenOff()
end

-- how far the way is clear from a point, along a heading
local function FreeAhead(ped, from, heading, distance)
    local to = from + Forward(heading) * distance
    local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 17, ped, 7)
    local _, hit, hitCoords = GetShapeTestResult(handle)
    if hit and hit ~= 0 then
        return #(hitCoords - from)
    end
    return distance
end

-- the ped: its back to the rack. The camera: in front of it, framed for the category - straight out of the rack
-- where there is room, else the clearest way of a fan around that, and closer with a wider lens where there is none
local function PlaceCamera(session, rack)
    local ped = session.ped
    local spec = RC.cameras[session.category.camera] or RC.cameras.torso
    local coords = GetEntityCoords(ped)
    local target = vector3(coords.x, coords.y, coords.z + spec.target)
    local eye = vector3(coords.x, coords.y, target.z + spec.raise)

    -- a rail in the middle of the floor has two sides: the heading is turned to the one the customer is on
    local heading = rack.heading
    local out = Forward(heading)
    if (coords.x - rack.coords.x) * out.x + (coords.y - rack.coords.y) * out.y < -0.25 then
        heading = heading + 180.0
    end

    local best, bestFree = heading % 360.0, 0.0
    for i = 1, #Fan do
        local way = (heading + Fan[i]) % 360.0
        local free = FreeAhead(ped, eye, way, spec.distance + 0.4)
        if free >= spec.distance + 0.35 then
            best, bestFree = way, free
            break
        elseif free > bestFree + 0.05 then
            best, bestFree = way, free
        end
    end

    local distance = math.max(0.6, math.min(spec.distance, bestFree - 0.3))
    local fov = 2.0 * math.deg(math.atan(spec.frame / (2.0 * distance)))
    local ahead = Forward(best)

    SetEntityHeading(ped, (best + (session.category.turn or 0.0)) % 360.0)

    local cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(cam, target.x + ahead.x * distance, target.y + ahead.y * distance, eye.z)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamFov(cam, math.max(20.0, math.min(80.0, fov)))
    RenderScriptCams(true, true, 400, true, false)
    session.cam = cam
end

-- the rack's item at a place of its list on the ped, in the texture asked for if it may be worn, else the first
-- that may: false when the item has no texture left for this player
local function ShowItem(session, position, texture)
    local ped, category = session.ped, session.category
    local drawable = session.drawables[position]

    Wear(ped, category, drawable, texture or 0)
    local settings = GetSettings(ped, category)
    if Session ~= session then return true end -- (left while the server was asked: what was kept is back on)

    local textures = ListTextures(settings)
    if #textures == 0 then return false end

    local pick = textures[1]
    for i = 1, #textures do
        if textures[i] == texture then
            pick = texture
            break
        end
    end
    if pick ~= (texture or 0) then
        Wear(ped, category, drawable, pick)
    end

    session.position, session.textures, session.texture = position, textures, pick
    SendHud(session)
    return true
end

-- left / right: so many items on, past the ones that cannot be worn
local function StepItem(session, step)
    local count = #session.drawables
    local position = session.position
    for _ = 1, count do
        position = (position - 1 + step) % count + 1
        if ShowItem(session, position) then return end
        step = step > 0 and 1 or -1
    end
end

-- up / down: the item's next texture
local function StepColour(session, step)
    local count = #session.textures
    if count < 2 then return end

    local at = 1
    for i = 1, count do
        if session.textures[i] == session.texture then
            at = i
            break
        end
    end

    session.texture = session.textures[(at - 1 + step) % count + 1]
    Wear(session.ped, session.category, session.drawables[session.position], session.texture)
    SendHud(session)
end

-- Enter: the server takes the money, then the item is the one that is kept and the look is saved
local function Buy(session)
    if IsWorn(session) then return end

    local ped, category = session.ped, session.category
    local bought = {
        drawable = session.drawables[session.position],
        texture = session.texture
    }

    local result = lib.callback.await("illenium-appearance:server:rackPurchase", false, session.store, session.name)
    if type(result) ~= "table" or not result.ok then
        if Session == session then
            local reason = type(result) == "table" and result.reason
            Toast(reason and Text[reason] or Text.failed, true)
            if type(result) == "table" and (tonumber(result.cash) or result.afford ~= nil) then
                session.cash = tonumber(result.cash) or session.cash
                if result.afford ~= nil then
                    session.afford = result.afford
                end
                SendHud(session)
            end
        end
        return
    end

    -- paid for: it stays on, also when the player has left the rack before the till answered
    if cache.ped ~= ped or not DoesEntityExist(ped) then return end

    if Session == session then
        session.keep = bought
        session.cash = tonumber(result.cash) or session.cash
        if result.afford ~= nil then
            session.afford = result.afford
        end
    else
        Wear(ped, category, bought.drawable, bought.texture)
        if Session and Session.category == category then
            Session.keep = bought
        end
    end

    TriggerServerEvent("illenium-appearance:server:saveAppearance", client.getPedAppearance(ped))
    if Framework.CachePed then
        Framework.CachePed()
    end

    if Session == session then
        Toast(Text.purchased)
        PlaySoundFrontend(-1, "PURCHASE", "HUD_LIQUOR_STORE_SOUNDSET", true)
        SendHud(session)
    end
end

-- an arrow: once when it goes down, then again and again while it is held
local function Pressed(session, control)
    if IsDisabledControlJustPressed(0, control) then
        session.held, session.heldAt = control, GetGameTimer() + (Keys.repeatDelay or 400)
        return true
    elseif session.held == control and IsDisabledControlPressed(0, control) then
        local now = GetGameTimer()
        if now >= session.heldAt then
            session.heldAt = now + (Keys.repeatRate or 110)
            return true
        end
    end
    return false
end

-- one frame of it: nothing but its own keys. What a key asks for is done by the session's other thread, which may
-- wait on the server
local function Frame(session)
    local ped = cache.ped
    if ped ~= session.ped or IsEntityDead(ped) or PlayerUnfit() or client.getConfig() then
        return Leave()
    end

    DisableAllControlActions(0)
    EnableControlAction(0, 249, true) -- push to talk
    HideHudAndRadarThisFrame()

    if Pressed(session, Keys.previous) then
        session.stepItem = session.stepItem - 1
    elseif Pressed(session, Keys.next) then
        session.stepItem = session.stepItem + 1
    elseif Pressed(session, Keys.colourNext) then
        session.stepColour = session.stepColour + 1
    elseif Pressed(session, Keys.colourPrevious) then
        session.stepColour = session.stepColour - 1
    elseif IsDisabledControlJustPressed(0, Keys.buy) then
        session.buy = true
    else
        for i = 1, #Keys.exit do
            if IsDisabledControlJustPressed(0, Keys.exit[i]) then
                return Leave()
            end
        end
    end
end

local function Work(session)
    if session.stepItem ~= 0 then
        local step = session.stepItem
        session.stepItem = 0
        StepItem(session, step)
    elseif session.stepColour ~= 0 then
        local step = session.stepColour
        session.stepColour = 0
        StepColour(session, step)
    elseif session.buy then
        Buy(session)
        session.stepItem, session.stepColour, session.buy = 0, 0, false -- (keys pressed while the till was busy)
    end
end

local function StartTryOn(storeIndex, rackIndex)
    local rack = Racks[storeIndex] and Racks[storeIndex][rackIndex]
    if not rack or Session or Starting or client.getConfig() then return end

    local category = RC.categories[rack.category]
    local ped = cache.ped
    if cache.vehicle or IsEntityDead(ped) or IsPedFalling(ped) or PlayerUnfit() then return end

    if not client.isPedFreemodeModel(ped) then
        return Notify(Text.freemodeOnly)
    end

    if category.component == 7 and Config.PreventTrackerRemoval and Framework.HasTracker and Framework.HasTracker() then
        return Notify(Text.tracker)
    end

    Starting = true
    local worn = GetWorn(ped, category)
    local ok, settings = pcall(GetSettings, ped, category)
    Starting = false

    if not ok or cache.ped ~= ped or Session or client.getConfig() then return end
    local drawables = ListDrawables(settings, category)
    if #drawables == 0 then
        return Notify(Text.nothing)
    end

    -- what is on first: what the ped wears if it is one of the rack's, else the rack's first item
    local position, texture = 1, nil
    for i = 1, #drawables do
        if drawables[i] == worn.drawable then
            position, texture = i, worn.texture
            break
        end
    end

    local session = {
        store = storeIndex,
        name = rack.category,
        category = category,
        ped = ped,
        gender = client.getPedDecorationType(),
        drawables = drawables,
        position = position,
        textures = { 0 },
        texture = 0,
        keep = worn,
        price = GetTotal(category),
        stepItem = 0,
        stepColour = 0
    }
    Session = session

    ClearPedTasksImmediately(ped)
    PlaceCamera(session, rack)
    FreezeEntityPosition(ped, true)
    if Config.InvincibleDuringCustomization then
        SetEntityInvincible(ped, true)
        session.invincible = true
    end

    CreateThread(function()
        while Session == session do
            Frame(session)
            Wait(0)
        end
    end)

    -- the player's cash, whether an item can be paid for, and the price, from the server
    lib.callback("illenium-appearance:server:rackOpen", false, function(data)
        if Session ~= session or type(data) ~= "table" then return end
        session.cash = tonumber(data.cash)
        session.afford = data.afford
        session.price = tonumber(data.price) or session.price
        SendHud(session)
    end, storeIndex, rack.category)

    if not ShowItem(session, position, texture) then
        StepItem(session, 1)
    end

    while Session == session do
        Work(session)
        Wait(0)
    end
end

-- =============================================================================
-- Third-eye path: a sphere zone on every rack of the store the player is at
-- =============================================================================
local function CanUseTargets()
    return Config.UseTarget and Target ~= nil and Target.AddSphereZone ~= nil and Target.IsTargetStarted ~= nil and Target.IsTargetStarted()
end

local function RemoveRackTargets()
    if ZoneStore and Target and Target.IsTargetStarted and Target.IsTargetStarted() then
        for i = 1, #ZoneNames do
            Target.RemoveZone(ZoneNames[i])
        end
    end
    ZoneStore, ZoneNames = nil, {}
end

local function AddRackTargets(index)
    for i, rack in ipairs(Racks[index]) do
        local name = ("rack_%d_%d"):format(index, i)
        Target.AddSphereZone(name, rack.coords, rack.radius or RC.radius, {
            options = {{
                type = "client",
                name = "illenium_" .. name,
                action = function()
                    CreateThread(function()
                        StartTryOn(index, i)
                    end)
                end,
                icon = RC.icon,
                label = Text.browse:format(RC.categories[rack.category].label),
                canInteract = function()
                    return Session == nil
                end
            }},
            distance = RC.distance
        })
        ZoneNames[#ZoneNames + 1] = name
    end
    ZoneStore = index
end

-- up while the player is at a store with racks, down when they go
CreateThread(function()
    while true do
        local coords = GetEntityCoords(cache.ped)
        local nearest, nearestDist = nil, RC.range

        for index in pairs(Racks) do
            local dist = #(coords - Config.Stores[index].coords.xyz)
            if dist < nearestDist then
                nearest, nearestDist = index, dist
            end
        end
        NearStore = nearest

        local want = nearest and CanUseTargets() and nearest or nil
        if want ~= ZoneStore then
            RemoveRackTargets()
            if want then
                AddRackTargets(want)
            end
        end

        Wait(1000)
    end
end)

-- the target script went: its zones went with it
AddEventHandler("onClientResourceStop", function(resource)
    if resource == "ox_target" or resource == "qb-target" then
        ZoneStore, ZoneNames = nil, {}
    end
end)

-- =============================================================================
-- [E] fallback (Config.UseTarget = false, or no target script): the rack looked at
-- =============================================================================
local function LookDirection()
    local rotation = GetFinalRenderedCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    return vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
end

-- of the racks within reach, the one nearest the middle of the screen (within some 25 degrees of it)
local function LookedAt(racks, coords)
    local camCoords, look = GetFinalRenderedCamCoord(), LookDirection()
    local best, bestDot = nil, 0.9

    for i = 1, #racks do
        local rack = racks[i]
        if #(coords - rack.coords) <= RC.distance then
            local to = rack.coords - camCoords
            local length = #to
            local dot = length > 0.01 and (to.x * look.x + to.y * look.y + to.z * look.z) / length or 0.0
            if dot > bestDot then
                best, bestDot = i, dot
            end
        end
    end
    return best
end

local function ShowPrompt(label)
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

CreateThread(function()
    local glyph = Keys.interact == 51 and "~INPUT_CONTEXT~" or "~INPUT_PICKUP~"
    while true do
        local sleep = 500
        local racks = NearStore and not ZoneStore and not Session and not Starting and Racks[NearStore]

        if racks and not client.getConfig() and not cache.vehicle then
            local coords = GetEntityCoords(cache.ped)
            local nearestDist = RC.distance + 3.0
            for i = 1, #racks do
                nearestDist = math.min(nearestDist, #(coords - racks[i].coords))
            end

            -- (at the store's own floor marker E opens the full menu: client/shops.lua)
            local atClerk = not Config.UseTarget and #(coords - Config.Stores[NearStore].coords.xyz) < 1.6
            if nearestDist <= RC.distance and not atClerk then
                sleep = 0
                local picked = LookedAt(racks, coords)
                if picked then
                    local rack = racks[picked]
                    DrawMarker(28, rack.coords.x, rack.coords.y, rack.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.04, 0.04, 0.04, 255, 255, 255, 220, false, false, 2, false, nil, nil, false)
                    ShowPrompt(glyph .. " " .. Text.browse:format(RC.categories[rack.category].label))
                    if IsControlJustReleased(0, Keys.interact) then
                        local index = NearStore
                        CreateThread(function()
                            StartTryOn(index, picked)
                        end)
                    end
                end
            elseif nearestDist < RC.distance + 3.0 then
                sleep = 100
            end
        end

        Wait(sleep)
    end
end)

-- =============================================================================
-- Config.Debug: the racks drawn as spheres, and /rackspot to fix one
-- =============================================================================
if Config.Debug then
    local Colours = {
        tops = { 255, 80, 80 },
        pants = { 80, 140, 255 },
        shoes = { 255, 200, 0 },
        hats = { 0, 220, 120 },
        glasses = { 0, 230, 230 },
        masks = { 160, 160, 160 },
        bags = { 255, 120, 255 },
        accessories = { 255, 255, 255 },
        watches = { 255, 150, 60 }
    }

    local function DrawLabel(coords, label)
        SetDrawOrigin(coords.x, coords.y, coords.z, 0)
        SetTextFont(4)
        SetTextScale(0.3, 0.3)
        SetTextColour(255, 255, 255, 235)
        SetTextOutline()
        SetTextCentre(true)
        BeginTextCommandDisplayText("STRING")
        AddTextComponentSubstringPlayerName(label)
        EndTextCommandDisplayText(0.0, 0.0)
        ClearDrawOrigin()
    end

    -- every rack of the store: its sphere, its name, and a line the way the customer will face
    CreateThread(function()
        while true do
            local sleep = 1000
            local racks = NearStore and Racks[NearStore]

            if racks then
                sleep = 0
                for i = 1, #racks do
                    local rack = racks[i]
                    local colour = Colours[rack.category] or Colours.accessories
                    local radius = rack.radius or RC.radius
                    local tip = rack.coords + Forward(rack.heading) * (radius + 0.5)
                    DrawMarker(28, rack.coords.x, rack.coords.y, rack.coords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, radius, radius, radius, colour[1], colour[2], colour[3], 70, false, false, 2, false, nil, nil, false)
                    DrawLine(rack.coords.x, rack.coords.y, rack.coords.z, tip.x, tip.y, tip.z, colour[1], colour[2], colour[3], 255)
                    DrawLabel(rack.coords, ("%s #%d"):format(rack.category, i))
                end
            end

            Wait(sleep)
        end
    end)

    -- /rackspot <category>: an entry for the point aimed at, to paste into Config.Racks.extra (or override). Stand
    -- where a customer would, facing the rack: the entry's heading is the way they will face with their back to it
    RegisterCommand("rackspot", function(_, args)
        local category = args[1] and args[1]:lower()
        if not category or not RC.categories[category] then
            local names = {}
            for name in pairs(RC.categories) do
                names[#names + 1] = name
            end
            table.sort(names)
            print("[racks] usage: /rackspot <category>  -  " .. table.concat(names, ", "))
            return
        end

        local ped = cache.ped
        local from = GetFinalRenderedCamCoord()
        local to = from + LookDirection() * 12.0
        local handle = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 511, ped, 7)
        local _, hit, hitCoords = GetShapeTestResult(handle)
        if not hit or hit == 0 then
            print("[racks] nothing aimed at within 12 m")
            return
        end

        local coords = GetEntityCoords(ped)
        local nearest, nearestDist
        for index, store in pairs(Config.Stores) do
            if store.type == "clothing" then
                local dist = #(coords - store.coords.xyz)
                if not nearestDist or dist < nearestDist then
                    nearest, nearestDist = index, dist
                end
            end
        end

        local entry = ("{ category = \"%s\", coords = vector3(%.2f, %.2f, %.2f), heading = %.1f },"):format(category, hitCoords.x, hitCoords.y, hitCoords.z, (GetEntityHeading(ped) + 180.0) % 360.0)
        print(("[racks] store %s (%.1f m from its coords) - for Config.Racks.extra[%s]:"):format(nearest, nearestDist or -1.0, nearest))
        print(entry)
        lib.setClipboard(entry)
        lib.notify({
            description = "Rack entry printed to the console (F8) and copied",
            type = "inform",
            position = Config.NotifyOptions.position
        })
    end, false)
end

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        Leave(true)
        RemoveRackTargets()
    end
end)
