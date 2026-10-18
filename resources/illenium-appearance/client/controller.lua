--[[
    Gamepad navigation for the appearance UI.

    FiveM's CEF build does not populate the browser Gamepad API, so the NUI
    cannot read a controller itself. This polls the pad with native controls
    and forwards intents as `appearance_nav` messages; the UI turns those into
    focus movement and value changes.

    Pairing note: SetNuiFocusKeepInput(true) is what lets these reads happen
    while the NUI holds focus. It also means the game keeps receiving input,
    so PLAYER_CONTROL is disabled each frame to stop the ped acting in-world.
]]

if not Config.ControllerNavigation then return end

local FRONTEND <const> = 2
local PLAYER_CONTROL <const> = 0

--[[
    Control ids from the FRONTEND group.

    The d-pad, accept and cancel ids below are stable and well documented.
    LB/RB are the two worth confirming on your own pad -- swap them here if
    the shoulder buttons do not cycle categories in game.
]]
local CONTROLS <const> = {
    { control = 188, action = 'up',           repeats = true },
    { control = 187, action = 'down',         repeats = true },
    { control = 189, action = 'left',         repeats = true },
    { control = 190, action = 'right',        repeats = true },
    { control = 191, action = 'activate',     repeats = false }, -- A
    { control = 194, action = 'back',         repeats = false }, -- B
    { control = 205, action = 'section-prev', repeats = false }, -- LB
    { control = 206, action = 'section-next', repeats = false }, -- RB
}

-- Held directions repeat, so a player can run a slider up without mashing.
local REPEAT_DELAY <const> = 400
local REPEAT_RATE <const> = 90

local active = false
local heldSince = {}
local nextRepeat = {}

local function send(action)
    SendNuiMessage(json.encode({
        type = 'appearance_nav',
        payload = { action = action },
    }))
end

--- Returns true when this control should fire on this frame.
local function shouldFire(entry)
    if IsDisabledControlJustPressed(FRONTEND, entry.control) then
        heldSince[entry.control] = GetGameTimer()
        nextRepeat[entry.control] = GetGameTimer() + REPEAT_DELAY
        return true
    end

    if not entry.repeats then
        return false
    end

    if not IsDisabledControlPressed(FRONTEND, entry.control) then
        heldSince[entry.control] = nil
        nextRepeat[entry.control] = nil
        return false
    end

    local due = nextRepeat[entry.control]
    if due and GetGameTimer() >= due then
        nextRepeat[entry.control] = GetGameTimer() + REPEAT_RATE
        return true
    end

    return false
end

local function loop()
    while active do
        -- Keeps the ped from moving, shooting or entering vehicles underneath
        -- the menu while KeepInput is on. FRONTEND is a separate group and
        -- stays readable through the Disabled* natives.
        DisableAllControlActions(PLAYER_CONTROL)

        for i = 1, #CONTROLS do
            local entry = CONTROLS[i]
            if shouldFire(entry) then
                send(entry.action)
            end
        end

        Wait(0)
    end
end

AddEventHandler('illenium-appearance:client:navStart', function()
    if active then return end

    active = true
    heldSince = {}
    nextRepeat = {}

    CreateThread(loop)
end)

AddEventHandler('illenium-appearance:client:navStop', function()
    active = false
end)
