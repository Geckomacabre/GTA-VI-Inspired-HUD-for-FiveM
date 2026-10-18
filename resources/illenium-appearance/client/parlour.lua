-- Barber chair and tattoo parlour: a barber's hairstyles, or a parlour's tattoos, one at a time on the character,
-- picked from a strip of pictures the way GTA VI's barber does it.
--
--   * Where: a second option on the store's own target (client/shops.lua) - "Hairstyles" at a barber, "Tattoos" at a
--     tattoo parlour. The strip is vice_hud's: where vice_hud does not run, the option opens the store's full menu.
--   * The screen: vice_hud's shop panel in its strip mode - the store and what is browsed over it, the price and the
--     name, a row of pictures with the one on outlined, "3 / 40" over it and a hairline under it, and the status
--     ("Not applied"). The pictures are thumbs/ (_tools/cloth_thumbs hair / tattoos): a hairstyle on a clay head, a
--     tattoo on a clay body.
--   * Keys: left / right the one before / after; up / down a hairstyle's variants, or the next body zone; Enter buys
--     what is on (the server takes the money: server/parlour.lua) - a tattoo already had is taken off instead;
--     Backspace or Esc leaves, and what was not bought goes back.
--   * A tattoo is shown where it is: the character turns the way shared/tattoo_facing.lua says (generated with the
--     pictures), and a zone's tattoos are those of shared/tattoos.lua the game has.
--
-- The full menu (client/shops.lua's first option) is not involved.

if not Config.Parlour or not Config.Parlour.enabled then return end

local client = client
local P = Config.Parlour
local Keys = P.keys
local Text = P.text
local Resource = GetCurrentResourceName()

local Session = nil -- the strip that is up
local Starting = false

-- is the strip up (client/shopflag.lua: vice_hud's money is off the screen meanwhile)
function ParlourOpen()
    return Session ~= nil
end

local PromptIds = { "illenium_parlour_item", "illenium_parlour_more", "illenium_parlour_buy", "illenium_parlour_exit" }

-- the directions the camera tries, off the way the player came in, when something stands in its way
local Fan = { 0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0 }

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

-- a price with tax, as the server charges it (the server's own figure replaces it)
local function Total(price)
    local taxRate = P.taxRate or Config.TaxRate or 0
    return math.floor((price or 0) * (1 + taxRate) + 0.5)
end

-- how many pictures the strip has room for beside vice_hud's prompts (as client/racks.lua: a picture with its gap is
-- 11.2 % of the screen's height wide, the prompts and the margins some 63 %)
local function StripRoom()
    local room = math.floor((GetAspectRatio(false) * 98.2 - 63.0) / 11.2)
    return math.max(3, math.min(P.strip or 6, room))
end

-- a picture of thumbs/, as vice_hud's page loads it
local function Thumb(file)
    return ("https://cfx-nui-%s/thumbs/%s"):format(Resource, file)
end

local function HairFile(gender, style, texture)
    return ("%s_2_%d%s.webp"):format(gender, style, (texture or 0) > 0 and ("_" .. texture) or "")
end

local function TattooHash(tattoo, gender)
    return gender == "male" and tattoo.hashMale or tattoo.hashFemale
end

-- what the ped has, zone by zone, as a table of its own (the lists are copied, the tattoos are shared)
local function CopyTattoos(tattoos)
    local copy = {}
    for zone, list in pairs(tattoos or {}) do
        if type(list) == "table" then
            copy[zone] = {}
            for i = 1, #list do
                copy[zone][i] = list[i]
            end
        end
    end
    return copy
end

-- where a tattoo is in the zone's list of those had, nil when it is not had
local function Owned(tattoos, zone, tattoo)
    local list = tattoos[zone]
    if not list then return nil end
    for i = 1, #list do
        if list[i].name == tattoo.name then return i end
    end
    return nil
end

-- =============================================================================
-- What a strip holds
-- =============================================================================
-- the hairstyles of the player's gender they may have, those with a picture where thumbs/ has any (a hairstyle with
-- none is one cloth_thumbs could not draw: no model)
local Pictured = {} -- gender => { [style] = true, any = bool }

local function ListHair(ped, gender)
    local settings = client.getHairSettings(ped) -- (asks the server for the player's aces: it takes a moment)
    local blocked = {}
    for _, style in pairs(settings.blacklist.drawables) do
        blocked[style] = true
    end

    local pictured = Pictured[gender]
    if not pictured then
        pictured = { any = false }
        for style = 0, settings.style.max do
            if LoadResourceFile(Resource, "thumbs/" .. HairFile(gender, style)) then
                pictured[style] = true
                pictured.any = true
            end
        end
        Pictured[gender] = pictured
    end

    local items = {}
    for style = 0, settings.style.max do
        if not blocked[style] and (not pictured.any or pictured[style]) then
            items[#items + 1] = { style = style, name = Text.hairName:format(style), file = HairFile(gender, style) }
        end
    end
    return items
end

-- the tattoos of each zone, of shared/tattoos.lua, that the player's gender has and the game has
local function ListTattoos(gender)
    local facing = Config.TattooFacing and Config.TattooFacing[gender]
    local zones = {}
    for _, zone in ipairs(P.zones) do
        local items = {}
        local list = Config.Tattoos[zone] or {}
        for i = 1, #list do
            local tattoo = list[i]
            local hash = TattooHash(tattoo, gender)
            if hash and hash ~= "" and tattoo.collection then
                local key = (tattoo.collection .. "/" .. hash):lower()
                local turn = facing and facing[key]
                if not facing or turn then
                    items[#items + 1] = {
                        tattoo = tattoo,
                        zone = zone,
                        name = tattoo.label or tattoo.name,
                        turn = turn or 0,
                        file = ("%s_tattoo_%s.webp"):format(gender, (tattoo.collection .. "_" .. hash):lower())
                    }
                end
            end
        end
        if #items > 0 then
            zones[#zones + 1] = { zone = zone, label = Text.zones[zone] or zone, items = items }
        end
    end
    return zones
end

-- is what is on what the player has: the hairstyle worn (and its variant), the tattoo had
local function Had(session)
    local item = session.items[session.position]
    if session.kind == "hair" then
        return item.style == session.keep.style and session.texture == session.keep.texture
    end
    return Owned(session.owned, item.zone, item.tattoo) ~= nil
end

local function PriceOf(session, item)
    if session.kind == "hair" then
        return session.price
    end
    if Owned(session.owned, item.zone, item.tattoo) then
        return (P.removePrice or 0) > 0 and Total(P.removePrice) or nil
    end
    return Total(item.tattoo.cost or P.tattooPrice)
end

-- =============================================================================
-- The screen: vice_hud's shop panel, in its strip mode
-- =============================================================================
local function SendHud(session)
    local items = session.items
    local count = #items
    local room = StripRoom()

    -- the pictures shown: the one on stays among them, the row only moving when it goes past an end
    if session.position < session.first then
        session.first = session.position
    elseif session.position > session.first + room - 1 then
        session.first = session.position - room + 1
    end
    session.first = math.max(1, math.min(session.first, count - room + 1))
    local last = math.min(count, session.first + room - 1)

    local item = items[session.position]
    local swatches = {}
    for i = session.first, last do
        local file = items[i].file
        if session.kind == "hair" and i == session.position and session.texture > 0 then
            file = HairFile(session.gender, items[i].style, session.texture) -- (the variant on, where it has a picture)
        end
        swatches[#swatches + 1] = { color = "#3a3a42", image = Thumb(file) }
    end

    local had = Had(session)
    local price = (not had or session.kind == "tattoo") and PriceOf(session, item) or nil
    local poor = price ~= nil and not had and session.afford == false
    local status
    if session.kind == "hair" then
        status = had and Text.current or Text.notApplied
    else
        status = had and Text.applied or Text.notApplied
    end

    Vice("ShowShopItem", {
        store = session.store,
        category = session.category,
        price = price,
        pay = price and { "bank", "cash" } or { "none" },
        name = item.name,
        variant = session.kind == "hair" and session.textures > 1 and Text.variant:format(session.texture + 1, session.textures) or nil,
        strip = true,
        swatches = swatches,
        selected = session.position - session.first + 1,
        counter = ("%d / %d"):format(session.position, count),
        more = last < count,
        progress = { first = session.first, shown = last - session.first + 1, total = count },
        status = status,
        afford = not poor
    })

    -- (its prompts lie in a row while its panel is up, on the line of the strip: short labels)
    Vice("ShowActionPrompt", PromptIds[1], Text.browse, Keys.next)
    if session.kind == "hair" then
        Vice("ShowActionPrompt", PromptIds[2], Text.style, Keys.up, { off = session.textures < 2 })
    else
        Vice("ShowActionPrompt", PromptIds[2], Text.zone, Keys.up, { off = #session.zones < 2 })
    end
    local removing = session.kind == "tattoo" and had
    Vice("ShowActionPrompt", PromptIds[3], removing and Text.remove or Text.buy, Keys.buy, { off = (session.kind == "hair" and had) or poor })
    Vice("ShowActionPrompt", PromptIds[4], Text.exit, Keys.exit[1])
end

-- a line for a moment: "Purchased", or why not
local function Toast(text)
    if not Vice("ShowFeed", text) then
        Notify(text)
    end
end

local function ScreenOff()
    Vice("HideShopItem")
    for i = 1, #PromptIds do
        Vice("HideActionPrompt", PromptIds[i])
    end
end

-- =============================================================================
-- The camera
-- =============================================================================
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

-- The way the camera looks from: back the way the player came (they stand facing the counter, the room behind them),
-- else the clearest of a fan round that. Found once, for the farthest the camera goes.
local function FindWay(session)
    local ped = session.ped
    local coords = GetEntityCoords(ped)
    local eye = vector3(coords.x, coords.y, coords.z + 0.6)
    local want = 0.0
    for _, spec in pairs(P.cameras) do
        want = math.max(want, spec.distance)
    end

    local heading = (session.startHeading + 180.0) % 360.0
    local best, bestFree = heading, 0.0
    for i = 1, #Fan do
        local way = (heading + Fan[i]) % 360.0
        local free = FreeAhead(ped, eye, way, want + 0.4)
        if free >= want + 0.35 then
            best, bestFree = way, free
            break
        elseif free > bestFree + 0.05 then
            best, bestFree = way, free
        end
    end
    session.heading, session.free = best, bestFree
end

-- the camera framed for the hair or a zone: from the way found, closer with a wider lens where it is not clear so far
local function FrameCamera(session, spec)
    local coords = GetEntityCoords(session.ped)
    local target = vector3(coords.x, coords.y, coords.z + spec.target)
    local distance = math.max(0.6, math.min(spec.distance, session.free - 0.3))
    local fov = 2.0 * math.deg(math.atan(spec.frame / (2.0 * distance)))
    local ahead = Forward(session.heading)

    if not session.cam then
        session.cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
        SetCamCoord(session.cam, target.x + ahead.x * distance, target.y + ahead.y * distance, target.z + spec.raise)
        PointCamAtCoord(session.cam, target.x, target.y, target.z)
        SetCamFov(session.cam, math.max(20.0, math.min(80.0, fov)))
        RenderScriptCams(true, true, 400, true, false)
        return
    end
    SetCamCoord(session.cam, target.x + ahead.x * distance, target.y + ahead.y * distance, target.z + spec.raise)
    PointCamAtCoord(session.cam, target.x, target.y, target.z)
    SetCamFov(session.cam, math.max(20.0, math.min(80.0, fov)))
end

-- =============================================================================
-- Trying on
-- =============================================================================
-- what is on: the hairstyle (with its variant), or the tattoos had with the one picked, the character turned to show it
local function ShowItem(session)
    local ped = session.ped
    local item = session.items[session.position]

    if session.kind == "hair" then
        session.textures = math.max(1, GetNumberOfPedTextureVariations(ped, 2, item.style))
        if session.texture >= session.textures then
            session.texture = 0
        end
        client.setPedHair(ped, {
            style = item.style,
            texture = session.texture,
            color = session.keep.color,
            highlight = session.keep.highlight
        })
        SetEntityHeading(ped, (session.heading - (P.cameras.hair.turn or 0.0)) % 360.0)
    else
        local preview = CopyTattoos(session.owned)
        if not Owned(preview, item.zone, item.tattoo) then
            preview[item.zone] = preview[item.zone] or {}
            preview[item.zone][#preview[item.zone] + 1] = item.tattoo
        end
        client.addPedTattoo(ped, preview) -- (on the ped only: what is had, client.getPedTattoos, stays as it was)
        SetEntityHeading(ped, (session.heading - item.turn) % 360.0)
    end

    SendHud(session)
end

-- a body zone's strip: its tattoos, the first on, the camera on the zone
local function SelectZone(session, index)
    local zone = session.zones[index]
    session.zoneIndex = index
    session.items = zone.items
    session.position, session.first = 1, 1
    session.category = zone.label
    if session.cam then
        FrameCamera(session, P.cameras[zone.zone] or P.cameras.ZONE_TORSO)
    end
end

-- out of it: the camera back, the ped let go, and on it what the player has (quick: the resource is stopping)
local function Leave(quick)
    local session = Session
    if not session then return end
    Session = nil

    local ped = session.ped
    if DoesEntityExist(ped) then
        if session.kind == "hair" then
            client.setPedHair(ped, session.keep)
        else
            client.setPedTattoos(ped, CopyTattoos(session.owned))
        end
        SetEntityHeading(ped, session.startHeading)
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

-- left / right: so many on
local function StepItem(session, step)
    local count = #session.items
    session.position = (session.position - 1 + step) % count + 1
    session.texture = 0
    ShowItem(session)
end

-- up / down: a hairstyle's next variant, or the next zone
local function StepMore(session, step)
    if session.kind == "hair" then
        if session.textures < 2 then return end
        session.texture = (session.texture + step) % session.textures
        ShowItem(session)
        return
    end
    if #session.zones < 2 then return end
    SelectZone(session, (session.zoneIndex - 1 + step) % #session.zones + 1)
    ShowItem(session)
end

-- Enter: the server takes the money, then what is on is the player's and the look is saved (a tattoo had: off it
-- comes, for the price of that, nothing by default)
local function Buy(session)
    local item = session.items[session.position]
    local had = Had(session)
    if session.kind == "hair" and had then return end
    local removing = session.kind == "tattoo" and had

    local result = lib.callback.await("illenium-appearance:server:parlourPurchase", false, session.storeIndex, session.kind,
        session.kind == "tattoo" and { zone = item.zone, name = item.tattoo.name, remove = removing } or nil)
    if type(result) ~= "table" or not result.ok then
        if Session == session then
            local reason = type(result) == "table" and result.reason
            Toast(reason and Text[reason] or Text.failed)
            if type(result) == "table" and result.afford ~= nil then
                session.afford = result.afford
                SendHud(session)
            end
        end
        return
    end

    -- paid for: it is the player's, also when they have left the strip before the till answered
    local ped = session.ped
    if cache.ped ~= ped or not DoesEntityExist(ped) then return end

    if session.kind == "hair" then
        session.keep = { style = item.style, texture = session.texture, color = session.keep.color, highlight = session.keep.highlight }
        if Session ~= session then
            client.setPedHair(ped, session.keep)
        end
    else
        if removing then
            table.remove(session.owned[item.zone], Owned(session.owned, item.zone, item.tattoo))
        else
            session.owned[item.zone] = session.owned[item.zone] or {}
            session.owned[item.zone][#session.owned[item.zone] + 1] = item.tattoo
        end
        client.setPedTattoos(ped, CopyTattoos(session.owned))
    end
    if result.afford ~= nil then
        session.afford = result.afford
    end

    TriggerServerEvent("illenium-appearance:server:saveAppearance", client.getPedAppearance(ped))
    if Framework.CachePed then
        Framework.CachePed()
    end

    if Session == session then
        Toast(removing and Text.removed or Text.purchased)
        PlaySoundFrontend(-1, "PURCHASE", "HUD_LIQUOR_STORE_SOUNDSET", true)
        ShowItem(session)
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
    elseif Pressed(session, Keys.up) then
        session.stepMore = session.stepMore + 1
    elseif Pressed(session, Keys.down) then
        session.stepMore = session.stepMore - 1
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
    elseif session.stepMore ~= 0 then
        local step = session.stepMore
        session.stepMore = 0
        StepMore(session, step)
    elseif session.buy then
        Buy(session)
        session.stepItem, session.stepMore, session.buy = 0, 0, false -- (keys pressed while the till was busy)
    end
end

-- The strip at a store: kind "hair" (a barber) or "tattoo" (a parlour). Called by client/shops.lua's target option.
function OpenParlour(storeIndex, kind)
    if Session or Starting or client.getConfig() then return end
    if not ViceRunning() then
        return (kind == "hair" and OpenBarberShop or OpenTattooShop)()
    end

    local ped = cache.ped
    if cache.vehicle or IsEntityDead(ped) or IsPedFalling(ped) or PlayerUnfit() then return end
    if not client.isPedFreemodeModel(ped) then
        return Notify(Text.freemodeOnly)
    end

    local store = Config.Stores[storeIndex] or {}
    local gender = client.getPedDecorationType()
    local session = {
        kind = kind,
        storeIndex = storeIndex,
        ped = ped,
        gender = gender,
        position = 1,
        first = 1,
        texture = 0,
        textures = 1,
        startHeading = GetEntityHeading(ped),
        stepItem = 0,
        stepMore = 0
    }

    Starting = true
    local ok, err = pcall(function()
        if kind == "hair" then
            session.items = ListHair(ped, gender)
            session.keep = {
                style = GetPedDrawableVariation(ped, 2),
                texture = GetPedTextureVariation(ped, 2),
                color = GetPedHairColor(ped),
                highlight = GetPedHairHighlightColor(ped)
            }
            session.store = store.label or Text.barber
            session.category = Text.hairstyle
            session.price = Total(P.hairPrice)
            for i = 1, #session.items do
                if session.items[i].style == session.keep.style then
                    session.position, session.texture = i, session.keep.texture
                    break
                end
            end
        else
            session.zones = ListTattoos(gender)
            session.owned = CopyTattoos(client.getPedTattoos())
            session.store = store.label or Text.parlour
        end
    end)
    Starting = false

    if not ok then
        print(("[parlour] %s"):format(err))
        return
    end
    if cache.ped ~= ped or Session or client.getConfig() then return end
    if (kind == "hair" and #session.items == 0) or (kind == "tattoo" and #session.zones == 0) then
        return Notify(Text.nothing)
    end
    if kind == "tattoo" then
        SelectZone(session, 1)
    end
    Session = session

    ClearPedTasksImmediately(ped)
    FindWay(session)
    FrameCamera(session, kind == "hair" and P.cameras.hair or P.cameras[session.zones[1].zone] or P.cameras.ZONE_TORSO)
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

    -- whether it can be paid for, and the price, from the server
    lib.callback("illenium-appearance:server:parlourOpen", false, function(data)
        if Session ~= session or type(data) ~= "table" then return end
        session.afford = data.afford
        if kind == "hair" then
            session.price = tonumber(data.price) or session.price
        end
        SendHud(session)
    end, storeIndex, kind)

    ShowItem(session)

    while Session == session do
        Work(session)
        Wait(0)
    end
end

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        Leave(true)
    end
end)
