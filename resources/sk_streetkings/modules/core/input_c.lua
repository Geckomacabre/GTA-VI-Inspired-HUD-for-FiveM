-- Keyboard/controller input resolution, ported verbatim from streetkings
-- modules/core/input_c.lua. Lets prompts show the right button label and lets
-- the ported modules read the correct interact control for the active pad.

---@class SKInputModule
SKInput = {}

local PAD_INDICES = { 0, 1, 2 }
local KEYBOARD_INTERACT_CONTROL = 38 -- E
local CONTROLLER_INTERACT_CONTROL = 70 -- A
local KEYBOARD_INTERACT_LABEL = 'E'
local CONTROLLER_INTERACT_LABEL = 'A'

---@return integer
function SKInput.getActivePadIndex()
    local bestPad = PAD_INDICES[1]
    local bestTime = GetTimeSinceLastInput(bestPad)

    for i = 2, #PAD_INDICES do
        local padIndex = PAD_INDICES[i]
        local inputAge = GetTimeSinceLastInput(padIndex)
        if inputAge < bestTime then
            bestPad = padIndex
            bestTime = inputAge
        end
    end

    return bestPad
end

---@param padIndex integer|nil
---@return integer
function SKInput.getTimeSinceLastInput(padIndex)
    return GetTimeSinceLastInput(padIndex or SKInput.getActivePadIndex())
end

---@param padIndex integer|nil
---@return boolean
function SKInput.isUsingKeyboard(padIndex)
    return IsUsingKeyboard(padIndex or SKInput.getActivePadIndex())
end

---@param timeoutMs integer
---@param padIndex integer|nil
---@return boolean
function SKInput.hasRecentPadInput(timeoutMs, padIndex)
    local resolvedPadIndex = padIndex or SKInput.getActivePadIndex()
    if SKInput.isUsingKeyboard(resolvedPadIndex) then
        return false
    end

    return SKInput.getTimeSinceLastInput(resolvedPadIndex) <= timeoutMs
end

---@param padIndex integer|nil
---@return integer
function SKInput.getInteractControl(padIndex)
    if SKInput.isUsingKeyboard(padIndex) then
        return KEYBOARD_INTERACT_CONTROL
    end

    return CONTROLLER_INTERACT_CONTROL
end

---@param padIndex integer|nil
---@return string
function SKInput.getInteractLabel(padIndex)
    if SKInput.isUsingKeyboard(padIndex) then
        return KEYBOARD_INTERACT_LABEL
    end

    return CONTROLLER_INTERACT_LABEL
end

---@return boolean
function SKInput.isInteractJustReleased()
    local padIndex = SKInput.getActivePadIndex()
    local control = SKInput.getInteractControl(padIndex)
    return IsControlJustReleased(padIndex, control)
        or IsDisabledControlJustReleased(padIndex, control)
end

---@return boolean
function SKInput.isInteractJustPressed()
    local padIndex = SKInput.getActivePadIndex()
    local control = SKInput.getInteractControl(padIndex)
    return IsControlJustPressed(padIndex, control)
        or IsDisabledControlJustPressed(padIndex, control)
end
