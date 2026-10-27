--[[
    What the player sees of the ball, apart from the ball: the prompts, the help
    box, the reticle, the "N scored" line and the Focus card.

    With vice_hud running (Config.Hud.vice) these are its pieces, which is what
    makes this look like GTA VI's basketball: the ball's name beside a button on
    a ball lying there, THROW and AIM in the corner while you have one, the help
    box top left, "2 scored" in the feed on the right. Without it, ox_lib's
    text box and notifications say the same things. The reticle is this
    resource's own page (html/) either way.

    The prompts are asked for every frame they are wanted, like BB.showHint,
    and go away by themselves a moment after the asking stops. vice_hud's are
    only sent when something changes: putting one up is a message to its page
    and a buzz of the pad.
]]

BB.look = {}

local L = BB.look
local VICE = 'vice_hud'
local OWNER = GetCurrentResourceName()

local function vice()
    return Config.Hud.vice and GetResourceState(VICE) == 'started'
end

L.vice = vice

--------------------------------------------------------------------------------
-- Prompts that last while they are asked for
--------------------------------------------------------------------------------

local up = {}           -- [name] = { at = ms last asked for, key = what is showing, take = function to take it down }
local watching = false

local function watch()
    if watching then return end
    watching = true

    CreateThread(function()
        while next(up) do
            local now = GetGameTimer()

            for name, entry in pairs(up) do
                if now - entry.at > 250 then
                    up[name] = nil
                    entry.take()
                end
            end

            Wait(100)
        end

        watching = false
    end)
end

--- Keeps `name` up for another moment, putting it up (or changing it) with
--- `put` when `key` is not what is already showing.
local function keep(name, key, put, take)
    local entry = up[name]

    if entry and entry.key == key then
        entry.at = GetGameTimer()
        return
    end

    if entry then entry.take() end

    put()
    up[name] = { at = GetGameTimer(), key = key, take = take }
    watch()
end

local function drop(name)
    local entry = up[name]
    if not entry then return end

    up[name] = nil
    entry.take()
end

--- A ball lying within reach: its name beside the pickup button, on the ball.
--- @param at vector3 Where the ball is
--- @param id any Which ball, so the prompt only moves when it is another one
function L.ball(at, id)
    if not vice() then
        BB.showHint(Config.Text.pickup_ball)
        return
    end

    keep('ball', id, function()
        exports[VICE]:ShowWorldActions({ { label = Config.Text.ball_name, key = Config.Keys.pickup } },
            at, { centred = true, compact = false, id = OWNER })
    end, function()
        exports[VICE]:HideWorldActions(OWNER)
    end)

    -- A loose ball may still be rolling.
    exports[VICE]:SetWorldActionsCoords(at, OWNER)
end

local function prompt(id, label, key)
    exports[VICE]:ShowActionPrompt(OWNER .. ':' .. id, label, key)
end

local function unprompt(id)
    exports[VICE]:HideActionPrompt(OWNER .. ':' .. id)
end

--- Somebody close by has a ball: reach in for it.
function L.steal()
    if not vice() then
        BB.showHint(Config.Text.steal_hint)
        return
    end

    keep('steal', true, function() prompt('steal', Config.Text.prompt_steal, Config.Keys.pickup) end,
        function() unprompt('steal') end)
end

--- Holding a ball with the 'rings' shot: THROW and AIM in the corner, as the
--- reference has them, and PASS too in a match (there is somebody to pass to).
--- @param match boolean
function L.holding(match)
    if not vice() then
        BB.showHint(Config.Text.holding_hint_rings)
        return
    end

    keep('holding', match and 'match' or 'free', function()
        prompt('throw', Config.Text.prompt_throw, Config.Keys.shoot)
        prompt('aim', Config.Text.prompt_aim, Config.Keys.aim)
        if match then prompt('pass', Config.Text.prompt_pass, Config.Keys.pass) end
    end, function()
        unprompt('throw')
        unprompt('aim')
        unprompt('pass')
    end)
end

--- The ball has gone: THROW and AIM go at once rather than a moment later.
function L.holdingOff() drop('holding') end

--- Everything above, down at once (the resource is stopping).
function L.clear()
    for name in pairs(up) do drop(name) end
end

--------------------------------------------------------------------------------
-- The help box
--------------------------------------------------------------------------------

local taught = false

--- How the 'rings' shot works, a moment after the ball is in your hands: once
--- a session, or every time (Config.Hud.tutorial).
function L.tutorial()
    local when = Config.Hud.tutorial
    if not when or (when == 'once' and taught) then return end

    taught = true

    CreateThread(function()
        Wait(1500)

        -- Gone again already (a quick throw): the lesson waits for next time.
        if not BB.isHolding() then
            taught = false
            return
        end

        if vice() then
            exports[VICE]:ShowHelpText(Config.Text.rings_help, Config.Hud.tutorialMs,
                { keys = { Config.Keys.aim, Config.Keys.shoot } })
        else
            BB.notify(Config.Text.rings_help_text)
        end
    end)
end

--------------------------------------------------------------------------------
-- The reticle (html/app.js draws it)
--------------------------------------------------------------------------------

--- Up, with no basket under it yet.
function L.reticle()
    local rings = Config.Shot.rings

    SendNUIMessage({ action = 'reticle', show = true, radius = rings.radius })
end

--- A basket under it (`size` the yellow ring, as a share of the white one), or
--- none (nil).
function L.reticleTarget(size)
    SendNUIMessage({ action = 'reticle', target = size or false, settleMs = Config.Shot.rings.settleMs })
end

--- THROW is held: the white ring closes.
function L.reticleClose()
    local rings = Config.Shot.rings

    SendNUIMessage({ action = 'reticle', close = true, closeMs = rings.closeMs,
        perfect = Config.Shot.timing.perfect / rings.closeMs })
end

function L.reticleOff()
    SendNUIMessage({ action = 'reticle', show = false })
end

--------------------------------------------------------------------------------
-- Baskets outside a match
--------------------------------------------------------------------------------

local scored = 0

--- How many baskets in a row have been counted since the count last started
--- again (a ball put away, or the court left behind).
function L.count() return scored end

function L.resetCount() scored = 0 end

--- A basket I made outside a match. In the reference that is "1 scored", "2
--- scored" in the feed with a hoop beside it and, with each, a little Focus
--- (vice_hud's Focus skill, and its card).
function L.scored(hoopId, points, clean)
    local hud = Config.Hud

    if not vice() then
        BB.notify(Config.Text.scored_self:format(points), 'success')
        BB.flashPoints(hoopId, points, clean)
        return
    end

    scored = scored + 1

    if hud.scoredFeed then
        exports[VICE]:ShowFeed(Config.Text.scored_count:format(scored),
            { icon = hud.scoredIcon, duration = hud.scoredMs, counter = OWNER .. ':scored' })
    else
        BB.notify(Config.Text.scored_self:format(points), 'success')
    end

    if hud.floatingPoints then BB.flashPoints(hoopId, points, clean) end

    -- (The Focus card comes with the XP, which server/match.lua grants.)
end

-- The count starts again once there is no basket anywhere near.
CreateThread(function()
    while true do
        Wait(3000)
        if scored > 0 and not BB.isHolding() and #BB.nearbyHoops() == 0 then scored = 0 end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= OWNER then return end

    L.clear()
    SendNUIMessage({ action = 'reticle', show = false })
end)
