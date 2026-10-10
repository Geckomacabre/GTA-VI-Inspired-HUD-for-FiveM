---Design registry: manages design pack registration, shared schemas, and validation.
local Designs = {}

---Define shared tunable schema: common properties across all designs.
---Exposed on the registry so a design pack can build on it without the
---host having to export a local.
function Designs.commonSchema()
  return {
    -- Palette
    { key = 'accent', label = 'Accent', type = 'color', default = '#14b8a6', group = 'Palette',
      tier = 'basic', affects = 'menu',
      help = 'Primary highlight color for active selection and focus states.' },
    { key = 'surface', label = 'Surface', type = 'color', default = '#0b0d0e', group = 'Palette',
      tier = 'basic', affects = 'menu',
      help = 'Background surface color for interface cards and plates.' },
    { key = 'surfaceAlpha', label = 'Surface opacity', type = 'number', default = 88, min = 30, max = 100, step = 1, group = 'Palette', unit = '%',
      tier = 'basic', affects = 'menu',
      help = 'Opacity level for background panels.' },
    { key = 'text', label = 'Text', type = 'color', default = '#f2f4f5', group = 'Palette',
      tier = 'advanced', affects = 'menu',
      help = 'Primary text color for actionable options.' },
    { key = 'textMuted', label = 'Secondary text', type = 'color', default = '#8f979c', group = 'Palette',
      tier = 'advanced', affects = 'menu',
      help = 'Secondary text color for descriptions and unfocused rows.' },
    { key = 'disabled', label = 'Disabled', type = 'color', default = '#6b7377', group = 'Palette',
      tier = 'advanced', affects = 'locked',
      help = 'Text color for disabled options.' },

    -- Surface treatment
    { key = 'corner', label = 'Corner radius', type = 'number', default = 12, min = 0, max = 32, step = 1, group = 'Surface', unit = 'px',
      tier = 'basic', affects = 'menu',
      help = 'Corner curvature radius for panels and plates.' },
    { key = 'gradient', label = 'Gradient', type = 'select', default = 'linear', group = 'Surface',
      tier = 'advanced', affects = 'menu',
      help = 'Background shading gradient mode.',
      options = { { value = 'none', label = 'None' }, { value = 'linear', label = 'Linear' }, { value = 'radial', label = 'Radial' } } },
    { key = 'gradientDepth', label = 'Gradient depth', type = 'number', default = 32, min = 0, max = 100, step = 1, group = 'Surface', unit = '%',
      tier = 'advanced', affects = 'menu',
      help = 'Intensity of the surface gradient illumination.' },
    { key = 'outline', label = 'Outline', type = 'number', default = 14, min = 0, max = 100, step = 1, group = 'Surface', unit = '%',
      tier = 'advanced', affects = 'menu',
      help = 'Brightness of border outlines and divider lines.' },
    { key = 'shadow', label = 'Contact shadow', type = 'number', default = 40, min = 0, max = 100, step = 1, group = 'Surface', unit = '%',
      tier = 'advanced', affects = 'menu',
      help = 'Drop shadow depth and elevation behind focused elements.' },

    -- Typography
    { key = 'typeScale', label = 'Type scale', type = 'number', default = 100, min = 80, max = 130, step = 1, group = 'Typography', unit = '%',
      tier = 'basic', affects = 'menu',
      help = 'Overall font size scaling factor.' },
    { key = 'labelLines', label = 'Label wrapping', type = 'select', default = '2', group = 'Typography',
      tier = 'basic', affects = 'menu',
      help = 'Maximum allowed lines before text truncation occurs.',
      options = { { value = '1', label = '1 line' }, { value = '2', label = '2 lines' }, { value = '3', label = '3 lines' } } },
    { key = 'subtext', label = 'Option sub-text', type = 'boolean', default = true, group = 'Typography',
      tier = 'basic', affects = 'locked',
      help = 'Show descriptions and requirement reasons below option labels.' },
    { key = 'typeWeight', label = 'Label weight', type = 'select', default = '600', group = 'Typography',
      tier = 'advanced', affects = 'menu',
      help = 'Font stroke weight for option labels.',
      options = { { value = '500', label = 'Medium' }, { value = '600', label = 'Semibold' }, { value = '700', label = 'Bold' } } },
    { key = 'typeCase', label = 'Label case', type = 'select', default = 'normal', group = 'Typography',
      tier = 'advanced', affects = 'menu',
      help = 'Text casing format.',
      options = { { value = 'normal', label = 'Sentence' }, { value = 'upper', label = 'Uppercase' } } },

    -- Motion
    { key = 'motion', label = 'Motion intensity', type = 'number', default = 100, min = 0, max = 150, step = 5, group = 'Motion', unit = '%',
      tier = 'basic', affects = 'motion',
      help = 'Travel distance multiplier for interface animations.' },
    { key = 'motionSpeed', label = 'Motion speed', type = 'number', default = 100, min = 60, max = 180, step = 5, group = 'Motion', unit = '%',
      tier = 'advanced', affects = 'motion',
      help = 'Animation speed rate.' },

    -- Parts
    { key = 'disabledStyle', label = 'Gated options look', type = 'select', default = 'lock', group = 'Parts',
      tier = 'basic', affects = 'locked',
      help = 'Visual presentation style for disabled options.',
      options = { { value = 'lock', label = 'Lock + reason' }, { value = 'dim', label = 'Dim + reason' }, { value = 'strike', label = 'Struck through' } } },
    { key = 'indicatorStyle', label = 'Indicator', type = 'select', default = 'ring', group = 'Parts',
      tier = 'advanced', affects = 'indicator',
      help = 'Shape geometry for world-anchored indicator markers.',
      options = { { value = 'ring', label = 'Ring' }, { value = 'diamond', label = 'Diamond' }, { value = 'bracket', label = 'Bracket' }, { value = 'dot', label = 'Dot' } } },
    { key = 'indicatorAccent', label = 'Indicator uses accent', type = 'boolean', default = false, group = 'Parts',
      tier = 'advanced', affects = 'indicator',
      help = 'Apply accent color to idle world markers.' },
    { key = 'cursorStyle', label = 'Cursor', type = 'select', default = 'reticle', group = 'Parts',
      tier = 'advanced', affects = 'cursor',
      help = 'Visual style for the screen aiming reticle.',
      options = { { value = 'reticle', label = 'Reticle' }, { value = 'crosshair', label = 'Crosshair' }, { value = 'dot', label = 'Dot' } } },

    -- Sound
    { key = 'soundPack', label = 'Sound pack', type = 'select', default = 'signature', group = 'Sound',
      tier = 'basic', affects = 'sound',
      help = 'Sound theme for interaction audio cues.',
      options = { { value = 'signature', label = 'Signature' }, { value = 'soft', label = 'Soft' }, { value = 'mechanical', label = 'Mechanical' }, { value = 'off', label = 'Silent' } } },
    { key = 'soundVolume', label = 'Sound volume', type = 'number', default = 70, min = 0, max = 100, step = 1, group = 'Sound', unit = '%',
      tier = 'advanced', affects = 'sound',
      help = 'Master audio volume limit for interaction sounds.' },

    -- Scale
    { key = 'scale', label = 'Interface scale', type = 'number', default = 100, min = 60, max = 160, step = 1, group = 'Scale', unit = '%',
      tier = 'basic', affects = 'menu',
      help = 'Base scaling factor for world-space interface sprites.' },
  }
end

---Filter shared schema: exclude unsupported controls for specific design.
function Designs.commonSchemaExcept(...)
  local drop = {}
  for i = 1, select('#', ...) do drop[(select(i, ...))] = true end

  local all, out = Designs.commonSchema(), {}
  for i = 1, #all do
    if not drop[all[i].key] then out[#out + 1] = all[i] end
  end
  return out
end

---Customize control labels: override label or help text for specific design.
function Designs.retune(list, wording)
  for i = 1, #list do
    local said = wording[list[i].key]
    if said then
      local copy = {}
      for k, v in pairs(list[i]) do copy[k] = v end
      copy.label = said.label or copy.label
      copy.help = said.help or copy.help
      list[i] = copy
    end
  end
  return list
end

function Designs.extend(base, extra)
  for i = 1, #extra do base[#base + 1] = extra[i] end
  return base
end


---Host SDK contract version for design packs.
Designs.SDK = 1

---Installed designs registry mapping ID to design specification.
Designs.list = {}

---Registration order list of installed design IDs.
Designs.order = {}

---Report a registry problem. Always surfaced server-side, where it helps an
---owner diagnose a bad pack; client-side it is gated by Config.TargetDebug so players
---never see console noise.
local function warn(message)
  if IsDuplicityVersion() or Config.TargetDebug then
    print(('[osm-target] %s'):format(message))
  end
end

---Register design pack: validate and insert pack specification into registry.
function Designs.define(spec)
  if type(spec) ~= 'table' or type(spec.id) ~= 'string' then
    return warn('a design descriptor is malformed and was ignored')
  end

  if Designs.list[spec.id] then
    return warn(('two design packs claim the id "%s"; the second was ignored'):format(spec.id))
  end

  if spec.sdk ~= Designs.SDK then
    return warn(('design "%s" was built against SDK %s, this build of osm-target provides SDK %d. Update the pack.')
      :format(spec.id, tostring(spec.sdk), Designs.SDK))
  end

  if type(spec.schema) ~= 'table' or #spec.schema == 0 then
    return warn(('design "%s" declares no tunables and was ignored'):format(spec.id))
  end

  -- Validate UI bundle presence: verify design.js exists before registering pack
  if not LoadResourceFile(GetCurrentResourceName(), ('target/designs/%s/design.js'):format(spec.id)) then
    return warn(('design "%s" is missing designs/%s/design.js. The pack is incomplete and was not registered.')
      :format(spec.id, spec.id))
  end

  Designs.list[spec.id] = spec
  Designs.order[#Designs.order + 1] = spec.id
end

---Retrieve fallback design: get configured design or first registered design.
function Designs.fallback()
  if Config and Config.Design and Designs.list[Config.Design] then return Config.Design end
  return Designs.order[1]
end

-- Validate registry state on startup: warn in console if no design packs are loaded
CreateThread(function()
  if #Designs.order > 0 then return end

  local expected = (Config and Config.Design) or 'rail'
  local onDisk = LoadResourceFile(GetCurrentResourceName(), ('target/designs/%s/design.lua'):format(expected))

  if onDisk then
    warn(('no designs registered, yet designs/%s/design.lua exists. The resource is not loading it: check that fxmanifest.lua lists "designs/**/design.lua" in shared_scripts, then restart the resource.'):format(expected))
  else
    warn('no designs are installed. Put at least one design pack folder in designs/.')
  end
end)

---Calculate design anchor: retrieve anchor offset with dynamic rule evaluation.
function Designs.anchorFor(id, tunables)
  local design = Designs.list[id]
  if not design then return { x = 0.0, y = 0.0 } end

  local base = design.anchor or { x = 0.0, y = 0.0 }
  local rule = design.anchorRule

  if rule and type(tunables) == 'table' then
    local chosen = rule.values and rule.values[tunables[rule.key]]
    if chosen then return { x = chosen.x, y = chosen.y } end
  end

  return { x = base.x, y = base.y }
end

---Check indicator override: determine if design draws custom anchor marker.
function Designs.hidesIndicator(id)
  local design = Designs.list[id]
  return design ~= nil and design.hidesIndicator == true
end

function Designs.exists(id)
  return Designs.list[id] ~= nil
end

function Designs.get(id)
  return Designs.list[id]
end

---Get design pack version: retrieve version string for bundle cache-busting.
function Designs.versionOf(id)
  local design = Designs.list[id]
  return design and design.version or nil
end

---Retrieve default settings: get baseline schema values with design overrides.
function Designs.defaults(id)
  local design = Designs.list[id]
  if not design then return {} end

  local out = {}
  for i = 1, #design.schema do
    local control = design.schema[i]
    out[control.key] = control.default
  end

  -- Apply design overrides: merge design-specific defaults over baseline schema
  if type(design.overrides) == 'table' then
    for k, v in pairs(design.overrides) do out[k] = v end
  end

  return out
end

local function clamp(value, min, max)
  if min and value < min then return min end
  if max and value > max then return max end
  return value
end

---Sanitize design settings: validate and clamp values against schema definitions.
function Designs.sanitise(id, values)
  local design = Designs.list[id]
  if not design then return {} end

  values = type(values) == 'table' and values or {}
  local out = Designs.defaults(id)

  for i = 1, #design.schema do
    local control = design.schema[i]
    local given = values[control.key]

    if given ~= nil then
      if control.type == 'number' then
        local n = tonumber(given)
        if n then out[control.key] = clamp(n, control.min, control.max) end
      elseif control.type == 'boolean' then
        out[control.key] = given and true or false
      elseif control.type == 'color' then
        if type(given) == 'string' and given:match('^#%x%x%x%x%x%x$') then
          out[control.key] = given
        end
      elseif control.type == 'select' then
        for j = 1, #(control.options or {}) do
          if control.options[j].value == given then
            out[control.key] = given
            break
          end
        end
      end
    end
  end

  return out
end

---Generate design manifest: compile metadata and schemas for administration UI.
function Designs.manifest()
  local out = {}
  for i = 1, #Designs.order do
    local id = Designs.order[i]
    local design = Designs.list[id]
    out[i] = {
      id = design.id,
      label = design.label,
      tagline = design.tagline,
      accent = design.accent,
      anchor = design.anchor,
      anchorRule = design.anchorRule,
      exclusive = design.exclusive or nil,
      version = design.version,
      schema = design.schema,
      defaults = Designs.defaults(id),
    }
  end
  return out
end

OsmTargetDesigns = Designs
return Designs
