Layers = {}

--[[ ── Option layers ────────────────────────────────────────────────────────────
  See Config.Layers for what this is for. Everything here is client state for the
  one thing that changes at runtime -- which layer the player has asked to see --
  plus the two questions the rest of the resource asks about it: is layering on
  for this player at all, and which layer does this option belong to.

  The answers reach the resolver through its context (`layer`, `layerOf`), so
  the menu, the world indicators and the re-check made when an option is
  confirmed can never disagree about what is showing.
]]

local PRIMARY, SECONDARY = 'primary', 'secondary'

---Whether the player asked for the secondary layer this time targeting was
---opened. Deliberately not remembered between holds of the key.
local revealed = false

local secondaryNames = {}

do
  local list = Config.Layers and Config.Layers.secondary or {}
  for i = 1, #list do secondaryNames[list[i]] = true end
end

---Whether the player's active job puts the rail in focus mode.
---@param player table? Player.state(), when the caller already has one
---@return boolean
function Layers.focus(player)
  local settings = Config.Layers
  if not settings or not settings.enabled then return false end

  local job = (player or Player.state()).jobName
  if not job then return false end

  local jobs = settings.focusJobs or {}
  for i = 1, #jobs do
    if jobs[i] == job then return true end
  end

  return false
end

---The layer that should be showing, or nil when layering does not apply and
---every option shows together.
---@param player table? Player.state(), when the caller already has one
---@return 'primary' | 'secondary' | nil
function Layers.active(player)
  if not Layers.focus(player) then return nil end
  return revealed and SECONDARY or PRIMARY
end

---@param option table
---@return 'primary' | 'secondary'
function Layers.of(option)
  if option.layer == SECONDARY or (option.name and secondaryNames[option.name]) then
    return SECONDARY
  end

  return PRIMARY
end

---@return boolean revealed the secondary layer is now the one showing
function Layers.toggle()
  revealed = not revealed
  return revealed
end

function Layers.reset()
  revealed = false
end
