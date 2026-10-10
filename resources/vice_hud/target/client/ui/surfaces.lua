Surfaces = {}

local RESOURCE = GetCurrentResourceName()

---@type table<string, { dui: number, txd: number, dict: string, texture: string, size: number }>
local live = {}
local ready = false

local DEFINITIONS = {
  menu      = { query = 'surface=menu',                     size = function() return Config.Render.menuResolution end },
  idle      = { query = 'surface=indicator&state=idle',     size = function() return Config.Render.indicatorResolution end },
  near      = { query = 'surface=indicator&state=near',     size = function() return Config.Render.indicatorResolution end },
  active    = { query = 'surface=indicator&state=active',   size = function() return Config.Render.indicatorResolution end },
  cursor    = { query = 'surface=cursor',                   size = function() return Config.Render.cursorResolution end },
}

local ORDER = { 'menu', 'idle', 'near', 'active', 'cursor' }

local function create(name, definition)
  local size = definition.size()
  local dict = ('osm_target_%s'):format(name)
  local version = OsmTargetDesigns.versionOf(Appearance.design) or '0'
  local url = ('nui://%s/target/html/index.html?%s&design=%s&v=%s')
    :format(RESOURCE, definition.query, Appearance.design, version)

  local dui = CreateDui(url, size, size)
  local txd = CreateRuntimeTxd(dict)
  CreateRuntimeTextureFromDuiHandle(txd, name, GetDuiHandle(dui))

  live[name] = { dui = dui, txd = txd, dict = dict, texture = name, size = size }
end

function Surfaces.init()
  if ready then return end
  ready = true

  for i = 1, #ORDER do
    local name = ORDER[i]
    create(name, DEFINITIONS[name])
  end

  -- Broadcast appearance retry: sync appearance payload repeatedly during startup initialization
  CreateThread(function()
    for _, delay in ipairs({ 0, 250, 750, 2000, 5000 }) do
      Wait(delay)
      if not ready then return end
      Surfaces.applyAppearance()
      -- Along the same retry ladder: a surface that comes up after the last
      -- device change would otherwise draw the wrong button until the next one.
      if Input and Input.resendPrompts then Input.resendPrompts() end
    end
  end)
end

function Surfaces.destroy()
  for name, surface in pairs(live) do
    DestroyDui(surface.dui)
    live[name] = nil
  end
  ready = false
end

function Surfaces.isReady() return ready end

function Surfaces.send(name, action, data)
  local surface = live[name]
  if not surface then return end
  SendDuiMessage(surface.dui, json.encode({ action = action, data = data }))
end

function Surfaces.broadcast(action, data)
  local encoded = json.encode({ action = action, data = data })
  for _, surface in pairs(live) do
    SendDuiMessage(surface.dui, encoded)
  end
end

---Apply appearance payload: broadcast design and preference settings to all active DUI surfaces.
function Surfaces.applyAppearance()
  local payload = {
    design = Appearance.design,
    -- Design version cache-buster: pass pack version to prevent stale CEF bundle caching
    version = OsmTargetDesigns.versionOf(Appearance.design),
    tunables = Appearance.tunables,
    anchor = Appearance.anchor,
    prefs = Appearance.prefs,
    timings = {
      open = Config.Interaction.openTime,
      close = Config.Interaction.closeTime,
    },
  }

  -- Sync audio configuration: send appearance settings to NUI sound bus
  SendNUIMessage({ action = 'appearance', data = payload })

  if not ready then return end
  Surfaces.broadcast('appearance', payload)
end

local SetDrawOrigin = SetDrawOrigin
local ClearDrawOrigin = ClearDrawOrigin
local DrawSprite = DrawSprite

---Calculate aspect-corrected width: maintain square texture proportions across screen aspect ratios.
function Surfaces.widthFor(height, aspect)
  return height / aspect
end

---Draw surface in world space: render 3D world-anchored sprite.
---@param name string
---@param coords vector3
---@param height number screen-height fraction
---@param aspect number GetAspectRatio(true)
---@param alpha number 0-255
---@param biasX number? anchor bias fraction of sprite width
---@param biasY number? anchor bias fraction of sprite height
function Surfaces.drawWorld(name, coords, height, aspect, alpha, biasX, biasY)
  local surface = live[name]
  if not surface then return end

  local width = height / aspect

  SetDrawOrigin(coords.x, coords.y, coords.z, 0)
  DrawSprite(surface.dict, surface.texture,
    (biasX or 0.0) * width, (biasY or 0.0) * height,
    width, height, 0.0, 255, 255, 255, math.floor(alpha))
  ClearDrawOrigin()
end

---Draw surface in screen space: render 2D overlay sprite.
function Surfaces.drawScreen(name, x, y, height, aspect, alpha)
  local surface = live[name]
  if not surface then return end

  DrawSprite(surface.dict, surface.texture, x, y,
    height / aspect, height, 0.0, 255, 255, 255, math.floor(alpha))
end
