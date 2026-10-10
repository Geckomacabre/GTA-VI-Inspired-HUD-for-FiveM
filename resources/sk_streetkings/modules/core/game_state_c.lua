-- Client game state machine.
--
-- Ported from streetkings modules/core/game_state_c.lua, with the server
-- round-trip removed: StreetKings validated every transition against its own
-- authoritative session server, which does not exist here. Transitions are
-- local, and the resulting state is mirrored onto the player statebag so other
-- resources (and our own server modules) can read it.

SKC = SKC or {}

local definitions    = {}
local currentState   = nil
local tickGeneration = 0

---@class GameStateDefinition
---@field onEnter fun(prevState: string|nil)|nil
---@field onExit fun(nextState: string)|nil
---@field onTick fun()|nil
---@field tickWait integer|nil wait ms after each onTick; default 0

---@param id string
---@param def GameStateDefinition
function SKC.RegisterGameState(id, def)
    definitions[id] = def
end

---@return string|nil
function SKC.GetGameState()
    return currentState
end

---@param id string
---@return boolean
function SKC.SetGameState(id)
    local def = definitions[id]
    if not def then
        error(('sk_streetkings: unknown game state %q'):format(id))
    end

    local prev = currentState
    if prev == id then return true end

    if prev and definitions[prev] and definitions[prev].onExit then
        definitions[prev].onExit(id)
    end

    currentState = id
    LocalPlayer.state:set('skGameState', id, true)

    tickGeneration = tickGeneration + 1
    local myGen = tickGeneration

    if def.onEnter then
        def.onEnter(prev)
    end

    if def.onTick then
        local tickWait = def.tickWait or 0
        CreateThread(function()
            while currentState == id and myGen == tickGeneration do
                def.onTick()
                Wait(tickWait)
            end
        end)
    end

    return true
end

--- True when the player is in any state where a scored run is underway.
---@return boolean
function SKC.IsRacing()
    return SKRacingStates[currentState] == true
end

--- True when driving-feel modules (nitrous, gearbox) may engage.
---@return boolean
function SKC.IsDrivingState()
    return SKDrivingStates[currentState] == true
end

-- Every state the ported modules can be in needs a definition registered before
-- SetGameState will accept it. Modules that own a state (racing, carmeet) may
-- re-register it with their own onEnter/onExit; the last registration wins.
for _, id in pairs(GameState) do
    SKC.RegisterGameState(id, {})
end

CreateThread(function()
    SKC.SetGameState(GameState.FREEROAM)
end)

exports('GetGameState', SKC.GetGameState)
exports('SetGameState', SKC.SetGameState)
exports('RegisterGameState', SKC.RegisterGameState)
