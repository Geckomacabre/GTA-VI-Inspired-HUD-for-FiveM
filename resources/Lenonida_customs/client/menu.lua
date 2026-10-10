-- Upgrade menu: builds the menu for the NUI, previews parts on the vehicle, buys them and
-- runs the orbit camera. Prices come from shared/customs.lua, the same code the server
-- charges with.

local session = nil -- everything about the menu that is open right now
local opening = false
local revving = false
local objective = nil -- { text, slot } from a mission script, see SetMenuObjective

local Labels = {
	['mod:11'] = 'Engine Tune', ['mod:24'] = 'Rear Wheel', ['mod:27'] = 'Trim Design', ['mod:33'] = 'Steering Wheel',
	['mod:34'] = 'Shift Lever', ['mod:41'] = 'Strut Brace', ['mod:44'] = 'Trim Color',
	turbo = 'Turbo Tuning', wheels = 'Rims', wheelcolor = 'Wheel Color', customtire = 'Tire Design',
	tyresmoke = 'Tire Smoke', drift = 'Drift Tires', bulletproof = 'Bulletproof Tires',
	paint1 = 'Primary Color', paint2 = 'Secondary Color', pearl = 'Pearlescent', rgb1 = 'Custom Primary',
	rgb2 = 'Custom Secondary', xenon = 'Headlights', neon = 'Neon Kit', plate = 'Plate Style', window = 'Window Tint',
	custom_engine = 'Engine Swap', custom_turbo = 'Turbo Kit', custom_tires = 'Tire Compound', nitrous = 'Nitrous Kit',
}

-- names of the performance levels, the game has no text labels for these
local LevelLabels = {
	[11] = { 'Engine Upgrade Stage 1', 'Engine Upgrade Stage 2', 'Engine Upgrade Stage 3', 'Engine Upgrade Stage 4' },
	[12] = { 'Street Brakes', 'Sport Brakes', 'Race Brakes' },
	[13] = { 'Transmission Upgrade Level 1', 'Transmission Upgrade Level 2', 'Transmission Upgrade Level 3' },
	[15] = { 'Lowered Suspension', 'Street Suspension', 'Sport Suspension', 'Competition Suspension' },
	[16] = { 'Armor Upgrade 20%', 'Armor Upgrade 40%', 'Armor Upgrade 60%', 'Armor Upgrade 80%', 'Armor Upgrade 100%' },
}

local WheelTypeLabels = { HighEnd = 'High End', BikeWheel = 'Bike', BennysWheel = "Benny's Original", BespokeWheel = "Benny's Bespoke" }

-- camera view of a slot, when it is not the one of its category
local SlotCameras = {
	['mod:0'] = 'rear34', ['mod:1'] = 'front34', ['mod:2'] = 'rear34', ['mod:3'] = 'side', ['mod:4'] = 'rear',
	['mod:5'] = 'side', ['mod:6'] = 'front', ['mod:7'] = 'front34', ['mod:8'] = 'front34', ['mod:10'] = 'top',
	['mod:37'] = 'rear', ['mod:42'] = 'front34', ['mod:43'] = 'rear34', ['mod:44'] = 'cabin', ['mod:46'] = 'side',
	['mod:25'] = 'plate', ['mod:26'] = 'plate', plate = 'plate', window = 'side', neon = 'side', xenon = 'front',
	['mod:13'] = 'side', ['mod:38'] = 'side',
}

local Views = {
	front = { yaw = 0.0, pitch = 8.0, dist = 1.15 },
	front34 = { yaw = -35.0, pitch = 10.0, dist = 1.2 },
	rear = { yaw = 180.0, pitch = 6.0, dist = 1.1 },
	rear34 = { yaw = 215.0, pitch = 10.0, dist = 1.2 },
	side = { yaw = 90.0, pitch = 6.0, dist = 1.15 },
	top = { yaw = 180.0, pitch = 55.0, dist = 1.2 },
	engine = { yaw = -12.0, pitch = 52.0, dist = 0.62, bone = 'engine' },
	wheel = { yaw = 65.0, pitch = 4.0, dist = 0.5, bone = 'wheel_lf' },
	plate = { yaw = 180.0, pitch = 10.0, dist = 0.6 },
	cabin = { yaw = 180.0, pitch = 14.0, metres = 0.95, bone = 'seat_dside_f' },
}

local NeonColors = {
	{ 'White', 222, 222, 255 }, { 'Blue', 2, 21, 255 }, { 'Electric Blue', 3, 83, 255 }, { 'Mint Green', 0, 255, 140 },
	{ 'Lime Green', 94, 255, 1 }, { 'Yellow', 255, 255, 0 }, { 'Golden Shower', 255, 150, 0 }, { 'Orange', 255, 62, 0 },
	{ 'Red', 255, 1, 1 }, { 'Pony Pink', 255, 50, 100 }, { 'Hot Pink', 255, 5, 190 }, { 'Purple', 35, 1, 255 },
	{ 'Blacklight', 15, 3, 255 },
}

local SmokeColors = {
	{ 'White', 254, 254, 254 }, { 'Black', 20, 20, 20 }, { 'Blue', 0, 150, 255 }, { 'Yellow', 255, 255, 50 },
	{ 'Orange', 255, 153, 51 }, { 'Red', 255, 10, 10 }, { 'Green', 10, 255, 10 }, { 'Purple', 153, 10, 153 },
	{ 'Pink', 255, 102, 178 }, { 'Brown', 120, 72, 20 },
}

local XenonColors = {
	[-1] = '#dfeaff', [0] = '#ffffff', [1] = '#0217ff', [2] = '#0353ff', [3] = '#00ff8c', [4] = '#5eff01', [5] = '#ffff00',
	[6] = '#ff9600', [7] = '#ff3e00', [8] = '#ff0101', [9] = '#ff3264', [10] = '#ff05be', [11] = '#2301ff', [12] = '#0f03ff',
}

local function pretty(name) -- 'PURE_BLACK' > 'Pure Black', 'BlueWhite1' > 'Blue White 1'
	local s = tostring(name):gsub('^%s+', ''):gsub('_', ' ')
	s = s:gsub('(%l)(%u)', '%1 %2'):gsub('(%a)(%d)', '%1 %2')
	s = s:lower():gsub('(%a)(%w*)', function(first, rest) return first:upper() .. rest end)
	return s
end

local function hex(r, g, b)
	return ('#%02x%02x%02x'):format(r, g, b)
end

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = type(v) == 'table' and copy(v) or v
	end
	return out
end

local function sortedByValue(list)
	local out = {}
	for name, value in pairs(list) do
		out[#out + 1] = { name = name, value = value }
	end
	table.sort(out, function(a, b) return a.value < b.value end)
	return out
end

local function slotLabel(slot)
	if Labels[slot] then return Labels[slot] end
	local extra = slot:match('^extra:(%d+)$')
	if extra then return 'Extra ' .. extra end
	local cfg = Customs.SlotConfig(slot)
	return cfg and cfg.label or slot
end

local function allowed(cfg, admin)
	if admin or not Config.JobPermissionAll then return true end
	if not cfg.job_grade then return false end
	if cfg.job_grade['all'] ~= nil then return true end
	local job = PlayerData and PlayerData.job
	return job ~= nil and cfg.job_grade[job.name] ~= nil and (tonumber(job.grade) or 0) >= cfg.job_grade[job.name]
end

local function gameLabel(key)
	if not key then return nil end
	local label = GetLabelText(key)
	if not label or label == 'NULL' or label == '' then return nil end
	return label
end

-- OPTIONS OF EVERY SLOT

local function modOptions(vehicle, mod, cfg)
	local count = GetNumVehicleMods(vehicle, mod)
	local livery = false
	if mod == 48 and count <= 0 then
		count = GetVehicleLiveryCount(vehicle)
		livery = true
	end
	if count <= 0 then return nil end
	local options = { { value = -1, label = mod == 48 and 'No Livery' or ('Stock ' .. cfg.label) } }
	for i = 0, count - 1 do
		local label = gameLabel(livery and GetLiveryName(vehicle, i) or GetModTextLabel(vehicle, mod, i))
		if not label then
			label = LevelLabels[mod] and LevelLabels[mod][i + 1] or (cfg.label .. ' ' .. (i + 1))
		end
		options[#options + 1] = { value = i, label = label }
	end
	return options
end

local function toggleOptions(label, stock)
	return { { value = false, label = stock or 'None' }, { value = true, label = label } }
end

local function colorPresets(colors, group)
	local options = {}
	for _, c in ipairs(colors) do
		options[#options + 1] = { value = c[2] .. ',' .. c[3] .. ',' .. c[4], label = c[1], hex = hex(c[2], c[3], c[4]), group = group }
	end
	return options
end

local function hsv(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local r, g, b
	i = i % 6
	if i == 0 then r, g, b = v, t, p
	elseif i == 1 then r, g, b = q, v, p
	elseif i == 2 then r, g, b = p, v, t
	elseif i == 3 then r, g, b = p, q, v
	elseif i == 4 then r, g, b = t, p, v
	else r, g, b = v, p, q end
	return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

local function rgbOptions()
	local hues = { 'Red', 'Orange', 'Amber', 'Yellow', 'Lime', 'Green', 'Mint', 'Teal', 'Cyan', 'Azure', 'Blue', 'Violet', 'Purple', 'Magenta', 'Pink', 'Rose' }
	local tones = { { 'Vivid', '', 0.95, 0.95 }, { 'Deep', 'Deep ', 0.9, 0.5 }, { 'Pastel', 'Pale ', 0.4, 1.0 } }
	local options = { { value = 'off', label = 'Factory Paint', group = 'Vivid' } }
	for _, tone in ipairs(tones) do
		for i, hue in ipairs(hues) do
			local r, g, b = hsv((i - 1) / #hues, tone[3], tone[4])
			options[#options + 1] = { value = r .. ',' .. g .. ',' .. b, label = tone[2] .. hue, hex = hex(r, g, b), group = tone[1] }
		end
	end
	for _, c in ipairs({ { 'Jet', 8, 8, 10 }, { 'Graphite', 45, 47, 52 }, { 'Slate', 96, 100, 108 }, { 'Silver', 170, 174, 180 }, { 'Pearl White', 245, 245, 240 } }) do
		options[#options + 1] = { value = c[2] .. ',' .. c[3] .. ',' .. c[4], label = c[1], hex = hex(c[2], c[3], c[4]), group = 'Mono' }
	end
	return options
end

local finishOf = nil -- paint index > finish
local function paintOptions(lists, keys, finish)
	if not finishOf then
		finishOf = {}
		for name, list in pairs({ metallic = Config.Metallic, matte = Config.Matte, metal = Config.Metals, chrome = Config.Crome, chameleon = Config.Chameleon }) do
			for _, index in pairs(list) do
				finishOf[index] = name
			end
		end
	end
	local options, seen = {}, {}
	for _, key in ipairs(keys) do
		for name, index in pairs(lists[key] or {}) do
			if type(index) == 'number' and not seen[index] then
				seen[index] = true
				options[#options + 1] = { value = index, label = (tostring(name):gsub('^%s+', '')), finish = finish or finishOf[index] or 'metallic' }
			end
		end
	end
	table.sort(options, function(a, b) return a.value < b.value end)
	return options
end

local function listOptions(cfg, stock, valueOf)
	local options = { { value = 'Default', label = stock } }
	local rest = {}
	for name, entry in pairs(cfg.list) do
		if name ~= 'Default' then
			rest[#rest + 1] = { value = valueOf and entry[valueOf] or name, label = entry.label or name, cost = tonumber(entry.value) or 0 }
		end
	end
	table.sort(rest, function(a, b)
		if a.cost ~= b.cost then return a.cost < b.cost end
		return a.label < b.label
	end)
	for _, option in ipairs(rest) do
		options[#options + 1] = { value = option.value, label = option.label }
	end
	return options
end

local function wheelGroups(vehicle, cfg)
	local bike = GetVehicleClass(vehicle) == 8
	local groups = {}
	for _, entry in ipairs(sortedByValue(cfg.list.WheelType or {})) do
		if (entry.value == 6) == bike then
			groups[#groups + 1] = { id = entry.value, label = WheelTypeLabels[entry.name] or entry.name }
		end
	end
	return groups
end

local function wheelOptions(vehicle, wheelType)
	local oldType, oldIndex, custom = GetVehicleWheelType(vehicle), GetVehicleMod(vehicle, 23), GetVehicleModVariation(vehicle, 23)
	SetVehicleWheelType(vehicle, wheelType)
	Wait(0)
	local options = { { value = 'stock', label = 'Stock Wheels' } }
	for i = 0, GetNumVehicleMods(vehicle, 23) - 1 do
		options[#options + 1] = { value = wheelType .. ':' .. i, label = gameLabel(GetModTextLabel(vehicle, 23, i)) or ('Wheel ' .. (i + 1)) }
	end
	SetVehicleWheelType(vehicle, oldType)
	SetVehicleMod(vehicle, 23, oldIndex, custom)
	return options
end

-- Returns the slot as the NUI wants it, or nil when the vehicle has nothing for it
local function buildSlot(vehicle, slot, cfg)
	local def = { id = slot, label = slotLabel(slot), kind = 'list' }
	local list = cfg.list or {}
	local mod = Customs.ModIndex(slot)
	if mod then
		def.options = modOptions(vehicle, mod, cfg)
	elseif slot == 'turbo' then
		def.options = toggleOptions('Turbo Upgrade', 'Stock Induction')
	elseif slot == 'wheels' then
		def.kind = 'wheels'
		def.groups = wheelGroups(vehicle, cfg)
		def.options = { { value = 'stock', label = 'Stock Wheels' } }
		if #def.groups == 0 then return nil end
	elseif slot == 'wheelcolor' then
		def.kind = 'swatch'
		def.options = paintOptions(list, { 'WheelColor' })
	elseif slot == 'customtire' then
		if not (list.Accessories and list.Accessories.CustomTire) then return nil end
		def.options = toggleOptions('Custom Tires')
	elseif slot == 'bulletproof' then
		if not (list.Accessories and list.Accessories.BulletProof) then return nil end
		def.options = toggleOptions('Bulletproof Tires')
	elseif slot == 'drift' then
		if not (list.Accessories and list.Accessories.DriftTires) or GetGameBuildNumber() < 2372 then return nil end
		def.options = toggleOptions('Drift Tires')
	elseif slot == 'tyresmoke' then
		if not (list.Accessories and list.Accessories.SmokeColor) then return nil end
		def.kind = 'swatch'
		def.custom = true
		def.options = colorPresets(SmokeColors, 'Smoke')
		table.insert(def.options, 1, { value = 'off', label = 'None', group = 'Smoke' })
	elseif slot == 'paint1' then
		def.kind = 'swatch'
		def.options = paintOptions(list, { 'Metallic', 'Matte', 'Metals', 'Crome', 'Chameleon' })
	elseif slot == 'paint2' then
		def.kind = 'swatch'
		def.options = paintOptions(list, { 'Metallic', 'Matte', 'Metals', 'Crome' })
	elseif slot == 'pearl' then
		def.kind = 'swatch'
		def.options = paintOptions(list, { 'Pearlescent' }, 'pearl')
	elseif slot == 'rgb1' or slot == 'rgb2' then
		def.kind = 'swatch'
		def.custom = true
		def.options = rgbOptions()
	elseif slot == 'xenon' then
		def.kind = 'swatch'
		def.options = { { value = 'off', label = 'Stock Lights', group = 'Xenon' }, { value = -1, label = 'Xenon Lights', hex = XenonColors[-1], group = 'Xenon' } }
		for _, entry in ipairs(sortedByValue(list.XenonColor or {})) do
			if entry.value >= 0 then
				def.options[#def.options + 1] = { value = entry.value, label = pretty(entry.name), hex = XenonColors[entry.value] or '#ffffff', group = 'Xenon' }
			end
		end
	elseif slot == 'neon' then
		def.kind = 'swatch'
		def.custom = true
		def.options = colorPresets(NeonColors, 'Neon')
		table.insert(def.options, 1, { value = 'off', label = 'None', group = 'Neon' })
	elseif slot == 'plate' or slot == 'window' then
		def.options = {}
		for _, entry in ipairs(sortedByValue(list)) do
			def.options[#def.options + 1] = { value = entry.value, label = pretty(entry.name) }
		end
	elseif slot == 'custom_engine' then
		def.options = listOptions(cfg, 'Stock Engine', 'model')
	elseif slot == 'custom_turbo' then
		def.options = listOptions(cfg, 'Stock Turbo')
	elseif slot == 'custom_tires' then
		def.options = listOptions(cfg, 'Stock Tires')
	elseif slot == 'nitrous' then
		def.options = listOptions(cfg, 'No Nitrous')
	else -- extra:<id>
		def.options = { { value = false, label = 'Off' }, { value = true, label = 'On' } }
	end
	if not def.options or #def.options < 2 and def.kind ~= 'wheels' then return nil end
	for _, option in ipairs(def.options) do
		option.price = Customs.Price(slot, option.value, session.ctx) or 0
		option.stock = Customs.BasePrice(slot, option.value, session.ctx) == 0 -- the factory option, never "not owned"
	end
	def.camera = SlotCameras[slot]
	return def
end

-- APPLYING SLOTS TO THE VEHICLE
-- view = the state the vehicle should show (what it owns, or that + the option being looked at)

local function applyPaint(vehicle, view)
	ClearVehicleCustomPrimaryColour(vehicle)
	ClearVehicleCustomSecondaryColour(vehicle)
	SetVehicleColours(vehicle, view['paint1'], view['paint2'])
	local c = view['rgb1'] ~= 'off' and Customs.ParseRgb(view['rgb1'])
	if c then SetVehicleCustomPrimaryColour(vehicle, c[1], c[2], c[3]) end
	c = view['rgb2'] ~= 'off' and Customs.ParseRgb(view['rgb2'])
	if c then SetVehicleCustomSecondaryColour(vehicle, c[1], c[2], c[3]) end
end

local function applySlot(vehicle, slot, view)
	local value = view[slot]
	local mod = Customs.ModIndex(slot)
	if mod == 48 then
		if GetNumVehicleMods(vehicle, 48) > 0 then
			SetVehicleMod(vehicle, 48, value, false)
		else
			SetVehicleLivery(vehicle, value)
		end
	elseif mod then
		SetVehicleMod(vehicle, mod, value, mod == 24 and view['customtire'] == true)
	elseif slot == 'turbo' then
		ToggleVehicleMod(vehicle, 18, value == true)
	elseif slot == 'wheels' or slot == 'customtire' then
		local wheelType, index = tostring(view['wheels']):match('^(%d+):(%d+)$')
		if wheelType then
			SetVehicleWheelType(vehicle, tonumber(wheelType))
			SetVehicleMod(vehicle, 23, tonumber(index), view['customtire'] == true)
		else
			SetVehicleWheelType(vehicle, oldprop.wheels)
			SetVehicleMod(vehicle, 23, -1, view['customtire'] == true)
		end
	elseif slot == 'wheelcolor' then
		local pearl = GetVehicleExtraColours(vehicle)
		SetVehicleExtraColours(vehicle, pearl, value)
	elseif slot == 'pearl' then
		local _, wheel = GetVehicleExtraColours(vehicle)
		SetVehicleExtraColours(vehicle, value, wheel)
	elseif slot == 'paint1' or slot == 'paint2' or slot == 'rgb1' or slot == 'rgb2' then
		applyPaint(vehicle, view)
	elseif slot == 'xenon' then
		ToggleVehicleMod(vehicle, 22, value ~= 'off')
		if value ~= 'off' then SetVehicleXenonLightsColour(vehicle, value < 0 and 255 or value) end
		SetVehicleLights(vehicle, 2)
	elseif slot == 'neon' then
		local c = value ~= 'off' and Customs.ParseRgb(value)
		for i = 0, 3 do
			SetVehicleNeonLightEnabled(vehicle, i, c ~= false and c ~= nil)
		end
		if c then SetVehicleNeonLightsColour(vehicle, c[1], c[2], c[3]) end
	elseif slot == 'plate' then
		SetVehicleNumberPlateTextIndex(vehicle, value)
	elseif slot == 'window' then
		SetVehicleWindowTint(vehicle, value)
	elseif slot == 'tyresmoke' then
		local c = value ~= 'off' and Customs.ParseRgb(value)
		ToggleVehicleMod(vehicle, 20, c ~= false and c ~= nil)
		if c then SetVehicleTyreSmokeColor(vehicle, c[1], c[2], c[3]) end
	elseif slot == 'drift' then
		if GetGameBuildNumber() >= 2372 then SetDriftTyresEnabled(vehicle, value == true) end
	elseif slot == 'bulletproof' then
		SetVehicleTyresCanBurst(vehicle, value ~= true)
	else
		local extra = slot:match('^extra:(%d+)$')
		if extra then SetVehicleExtra(vehicle, tonumber(extra), value == true and 0 or 1) end
	end
	-- custom engine, turbo, tires and nitrous are fitted after payment
end

-- a respray covers the custom RGB paint on the same panel
local PaintLinks = { paint1 = 'rgb1', paint2 = 'rgb2' }

local function viewWith(slot, value)
	local view = copy(session.owned)
	view[slot] = value
	if PaintLinks[slot] then view[PaintLinks[slot]] = 'off' end
	return view
end

local function normalize(value)
	if type(value) == 'number' then return math.floor(value) end
	return value
end

-- VEHICLE CARD STATS

local function handlingFloat(vehicle, field)
	return GetVehicleHandlingFloat(vehicle, 'CHandlingData', field)
end

local function baseSpec(vehicle)
	local spec = GetHandlingfromModel('Default', vehicle) or {}
	local maxVel = spec.fInitialDriveMaxFlatVel or handlingFloat(vehicle, 'fInitialDriveMaxFlatVel')
	if maxVel < 75.0 then maxVel = maxVel * 3.6 end
	return {
		maxVel = maxVel,
		force = spec.fInitialDriveForce or handlingFloat(vehicle, 'fInitialDriveForce'),
		mass = spec.fMass or handlingFloat(vehicle, 'fMass'),
		tcMax = spec.fTractionCurveMax or handlingFloat(vehicle, 'fTractionCurveMax'),
		lossMult = spec.fTractionLossMult or handlingFloat(vehicle, 'fTractionLossMult'),
		brake = handlingFloat(vehicle, 'fBrakeForce'),
		travel = handlingFloat(vehicle, 'fSuspensionUpperLimit') - handlingFloat(vehicle, 'fSuspensionLowerLimit'),
	}
end

local function computeStats(view)
	local base = session.base
	local maxVel, force = base.maxVel, base.force
	local engine = view['custom_engine']
	if engine and engine ~= 'Default' then
		if session.donors[engine] == nil then
			session.donors[engine] = GetHandlingfromModel(engine, session.vehicle) or false
		end
		local donor = session.donors[engine]
		if donor then
			maxVel = donor.fInitialDriveMaxFlatVel
			force = donor.fInitialDriveForce * math.max(0.5, math.min(2.0, donor.fMass / base.mass))
		end
	end
	local s = {
		speed = (maxVel - 80.0) / 12.0,
		acceleration = (force - 0.065) / 0.05,
		asphalt = (base.tcMax - 1.1) * 4.0 + base.brake,
		offroad = 2.2 + (1.0 - base.lossMult) * 4.5 + base.travel * 12.5,
		strength = math.sqrt(base.mass) / 13.75,
	}
	local function add(effect, times)
		for stat, amount in pairs(effect) do
			if s[stat] and type(amount) == 'number' then s[stat] = s[stat] + amount * times end
		end
	end
	for slot, effect in pairs(Config.StatEffects) do
		local value = view[slot]
		if Customs.ModIndex(slot) then
			if type(value) == 'number' and value >= 0 then add(effect, value + 1) end
		elseif value == true then
			add(effect, 1)
		elseif type(value) == 'string' and type(effect[value]) == 'table' then
			add(effect[value], 1)
		end
	end
	local turbos = Config.VehicleMod['custom_turbo']
	local turbo = turbos and view['custom_turbo'] and turbos.list[view['custom_turbo']]
	if turbo and turbo.Power and not (Config.StatEffects['custom_turbo'] and Config.StatEffects['custom_turbo'][view['custom_turbo']]) then
		s.speed = s.speed + (turbo.Power - 1.0) * 0.8
		s.acceleration = s.acceleration + ((turbo.Torque or 1.0) - 1.0) * 1.2
	end
	for stat, value in pairs(s) do
		s[stat] = math.floor(math.max(0.1, math.min(10.0, value)) * 10 + 0.5) / 10
	end
	return s
end

local function ratings(s)
	return math.floor((s.speed + s.acceleration + s.asphalt * 1.1) / 3.1 * 100 + 0.5),
		math.floor((s.offroad * 0.5 + s.strength * 0.2 + s.acceleration * 0.15 + s.speed * 0.15) * 100 + 0.5)
end

-- stock = factory vehicle (the tick on the bar), owned = as it is now, value = with the option being looked at
local function statsPayload(view)
	local stock = computeStats({ ['custom_engine'] = 'Default' })
	local owned = computeStats(session.owned)
	local now = computeStats(view)
	local stats = {}
	for _, stat in ipairs({ 'speed', 'acceleration', 'asphalt', 'offroad', 'strength' }) do
		stats[stat] = { stock = stock[stat], owned = owned[stat], value = now[stat] }
	end
	local road, dirt = ratings(now)
	local ownedRoad, ownedDirt = ratings(owned)
	stats.road = { owned = ownedRoad, value = road }
	stats.dirt = { owned = ownedDirt, value = dirt }
	return stats
end

-- NITROUS FROM STREETKINGS
-- With Config.NitrousSystem = 'streetkings', sk_streetkings is the server's nitrous: it keeps the
-- tier by plate, takes the money, boosts and reports to the HUD. The menu only sells it, through
-- the two exports sk_streetkings has for this (modules/tuning/tuning_c.lua).

-- The Nitrous slot as the NUI wants it, and the tier the vehicle has now
local function streetkingsNitrous(vehicle)
	if GetResourceState('sk_streetkings') ~= 'started' then return nil end
	local ok, shop = pcall(function() return exports.sk_streetkings:GetNitrousShop(vehicle) end)
	if not ok or type(shop) ~= 'table' or type(shop.tiers) ~= 'table' then return nil end
	local def = {
		id = 'nitrous', label = slotLabel('nitrous'), kind = 'list', external = true,
		options = { { value = 'Default', label = 'No Nitrous', price = 0, stock = true } },
	}
	for _, tier in ipairs(shop.tiers) do
		def.options[#def.options + 1] = { value = tier.id, label = tier.label, price = tonumber(tier.price) or 0, stock = false }
	end
	return def, shop.current or 'Default'
end

local function buyStreetkingsNitrous(tier, cb)
	local vehicle = session.vehicle
	local ok, result = pcall(function() return exports.sk_streetkings:BuyNitrous(vehicle, tier ~= 'Default' and tier or nil) end)
	if not session then return cb({ ok = false }) end
	if not ok or type(result) ~= 'table' or not result.ok then
		return cb({ ok = false, message = ok and type(result) == 'table' and result.reason or 'The purchase did not go through.' })
	end
	session.owned = copy(session.owned)
	session.owned['nitrous'] = result.tier or 'Default'
	TriggerEvent('customs:purchased', { nitrous = session.owned['nitrous'] })
	cb({ ok = true, owned = session.owned, stats = statsPayload(session.owned) })
end

-- PRO BUILDS

-- the parts of a kit this vehicle can take: slot > value
local function resolveKit(kit)
	local out, count = {}, 0
	for slot, want in pairs(kit.slots) do
		local def = session.slots[slot]
		local value = nil
		if def and Customs.ModIndex(slot) then
			local best = def.options[#def.options].value
			value = want == 'max' and best or math.min(tonumber(want) or 0, best)
		elseif def and def.kind == 'wheels' then
			value = want
		elseif def then
			for _, option in ipairs(def.options) do
				if option.value == want then value = want end
			end
		end
		if value ~= nil then
			out[slot] = value
			count = count + 1
		end
	end
	return out, count
end

-- what the kit costs on this vehicle right now: its price, or less when the parts it would fit cost less
local function kitPrice(kit, parts)
	local view = copy(session.owned)
	for slot, value in pairs(parts) do
		view[slot] = value
	end
	view['kit'] = kit.id
	for _, item in ipairs(Customs.Cart(session.owned, view, session.ctx) or {}) do
		if item.slot == 'kit' then return item.price end
	end
	return Customs.KitPrice(kit, session.ctx)
end

local function buildKits()
	local kits = {}
	for _, kit in ipairs(Config.ProBuilds or {}) do
		local parts, count = resolveKit(kit)
		if count > 0 then
			session.kits[kit.id] = parts
			kits[#kits + 1] = { id = kit.id, label = kit.label, price = kitPrice(kit, parts), parts = count }
		end
	end
	return kits
end

-- CAMERA

local camera = nil

local function boneOffset(vehicle, bone)
	local index = GetEntityBoneIndexByName(vehicle, bone)
	if index == -1 then return nil end
	return GetOffsetFromEntityGivenWorldCoords(vehicle, GetWorldPositionOfEntityBone(vehicle, index))
end

local function setView(name)
	local view = Views[name] or Views.rear34
	local vehicle = session.vehicle
	local min, max = GetModelDimensions(GetEntityModel(vehicle))
	local length, height = max.y - min.y, max.z - min.z
	local goal = { yaw = view.yaw, pitch = view.pitch, dist = (view.dist or 1.0) * length + 1.4, x = 0.0, y = 0.0, z = height * 0.12 }
	local hood, boot = false, false
	if name == 'engine' then
		local engine = boneOffset(vehicle, 'engine') or vector3(0.0, length * 0.3, 0.2)
		goal.x, goal.y, goal.z = 0.0, engine.y, engine.z + 0.15
		if engine.y < 0.0 then -- engine in the back
			goal.yaw = 192.0
			boot = true
		else
			hood = true
		end
	elseif name == 'wheel' then
		local wheel = boneOffset(vehicle, 'wheel_lf') or vector3(-0.8, length * 0.3, -0.2)
		goal.x, goal.y, goal.z = wheel.x, wheel.y, wheel.z
		goal.dist = length * view.dist + 1.0
	elseif name == 'plate' then
		goal.y, goal.z = min.y, 0.0
	elseif name == 'cabin' then
		local seat = boneOffset(vehicle, 'seat_dside_f') or vector3(-0.4, 0.0, 0.0)
		goal.x, goal.y, goal.z = 0.0, seat.y + 0.55, seat.z + 0.45
		goal.dist = view.metres
	end
	if hood then SetVehicleDoorOpen(vehicle, 4, false, false) else SetVehicleDoorShut(vehicle, 4, false) end
	if boot then SetVehicleDoorOpen(vehicle, 5, false, false) else SetVehicleDoorShut(vehicle, 5, false) end
	goal.min = name == 'cabin' and 0.5 or math.max(1.2, goal.dist * 0.55)
	goal.max = name == 'cabin' and 1.4 or goal.dist * 1.9
	if camera.goal then -- turn the short way round
		while goal.yaw - camera.yaw > 180.0 do goal.yaw = goal.yaw - 360.0 end
		while goal.yaw - camera.yaw < -180.0 do goal.yaw = goal.yaw + 360.0 end
	else
		camera.yaw, camera.pitch, camera.dist, camera.x, camera.y, camera.z = goal.yaw + 25.0, goal.pitch + 6.0, goal.dist * 1.25, goal.x, goal.y, goal.z
	end
	camera.goal = goal
	camera.name = name
end

local function cameraLoop()
	local vehicle = session.vehicle
	local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
	camera.cam = cam
	SetCamFov(cam, 45.0)
	if Config.MenuDepthOfField ~= false then
		SetCamUseShallowDofMode(cam, true)
		SetCamNearDof(cam, 0.6)
		SetCamDofStrength(cam, 0.7)
	end
	RenderScriptCams(true, true, 700, true, true)
	while session and camera.cam == cam do
		local goal = camera.goal
		local k = math.min(1.0, GetFrameTime() * 7.0)
		for _, field in ipairs({ 'yaw', 'pitch', 'dist', 'x', 'y', 'z' }) do
			camera[field] = camera[field] + (goal[field] - camera[field]) * k
		end
		local target = GetOffsetFromEntityInWorldCoords(vehicle, camera.x, camera.y, camera.z)
		local heading = math.rad(GetEntityHeading(vehicle) + camera.yaw)
		local pitch = math.rad(camera.pitch)
		local flat = camera.dist * math.cos(pitch)
		local pos = vector3(target.x - math.sin(heading) * flat, target.y + math.cos(heading) * flat, target.z + camera.dist * math.sin(pitch))
		-- keep the camera on this side of the shop walls
		local ray = StartExpensiveSynchronousShapeTestLosProbe(target.x, target.y, target.z, pos.x, pos.y, pos.z, 1, vehicle, 4)
		local _, hit, hitCoords = GetShapeTestResult(ray)
		if (hit == 1 or hit == true) and #(hitCoords - target) > 0.8 then
			pos = hitCoords + (target - hitCoords) / #(target - hitCoords) * 0.25
		end
		SetCamCoord(cam, pos.x, pos.y, pos.z)
		PointCamAtCoord(cam, target.x, target.y, target.z)
		if Config.MenuDepthOfField ~= false then
			SetCamFarDof(cam, #(pos - target) + 3.5)
			SetUseHiDof()
		end
		HideHudAndRadarThisFrame()
		Wait(0)
	end
	RenderScriptCams(false, true, 600, true, true)
	DestroyCam(cam, false)
end

-- CONTROLLER
-- With NUI focus the game still receives the gamepad (the menu page does not), so it is read
-- here and handed to the menu. The same loop keeps the pad from driving the vehicle, leaving
-- it or opening the pause menu behind the menu.

local PadButtons = { ok = 201, back = 202, card = 204, prev = 205, next = 206 } -- A, B, Y, LB, RB

local function padPressed(control)
	return IsControlPressed(2, control) or IsDisabledControlPressed(2, control)
end

local function padJustPressed(control)
	return IsControlJustPressed(2, control) or IsDisabledControlJustPressed(2, control)
end

local function setPadMode(on)
	session.pad = on
	SetNuiFocus(true, not on) -- no mouse cursor while a controller is in use
	SendNUIMessage({ type = 'pad', mode = on })
end

local function padLoop()
	local direction, nextRepeat, revHeld = nil, 0, false
	while session do
		DisableAllControlActions(0)
		DisableControlAction(2, 199, true) -- pause
		DisableControlAction(2, 200, true)
		local usingPad = not IsUsingKeyboard(2)
		if session.pad and not usingPad then setPadMode(false) end -- the mouse moved
		local actions, rev = {}, false
		if usingPad then
			-- d-pad or left stick, repeating while held
			local lx, ly = GetDisabledControlNormal(2, 195), GetDisabledControlNormal(2, 196)
			local want = (padPressed(188) or ly < -0.6) and 'up' or (padPressed(187) or ly > 0.6) and 'down'
				or (padPressed(189) or lx < -0.6) and 'left' or (padPressed(190) or lx > 0.6) and 'right' or nil
			local now = GetGameTimer()
			if want ~= direction then
				direction = want
				nextRepeat = now + 380
				if want then actions[#actions + 1] = want end
			elseif want and now >= nextRepeat then
				nextRepeat = now + 130
				actions[#actions + 1] = want
			end
			for action, control in pairs(PadButtons) do
				if padJustPressed(control) then actions[#actions + 1] = action end
			end
			rev = padPressed(203) -- X, held
			-- right stick looks around the vehicle, the triggers zoom
			local rx, ry = GetDisabledControlNormal(2, 197), GetDisabledControlNormal(2, 198)
			local zoom = GetDisabledControlNormal(2, 208) - GetDisabledControlNormal(2, 207)
			local looking = math.abs(rx) > 0.15 or math.abs(ry) > 0.15 or math.abs(zoom) > 0.1
			if looking and camera and camera.goal then
				local goal, dt = camera.goal, GetFrameTime()
				if math.abs(rx) > 0.15 then goal.yaw = goal.yaw - rx * 150.0 * dt end
				if math.abs(ry) > 0.15 then goal.pitch = math.max(-4.0, math.min(70.0, goal.pitch - ry * 80.0 * dt)) end
				if math.abs(zoom) > 0.1 then goal.dist = math.max(goal.min, math.min(goal.max, goal.dist * (1.0 - zoom * 1.2 * dt))) end
			end
			if not session.pad and (#actions > 0 or rev or looking) then setPadMode(true) end
		end
		for _, action in ipairs(actions) do
			SendNUIMessage({ type = 'pad', action = action })
		end
		if rev ~= revHeld then
			revHeld = rev
			SendNUIMessage({ type = 'pad', action = 'rev', on = rev })
		end
		Wait(0)
	end
end

-- OPEN / CLOSE

-- Tells other resources the menu is open. The HUD decides what it keeps on screen (the menu
-- has no money display of its own), the game's own HUD and radar are hidden by the camera loop.
local function setMenuOpen(open)
	LocalPlayer.state:set('customs:menuOpen', open, false)
	TriggerEvent('customs:menu', open)
end

local function buildMenu(vehicle)
	local built, tabs = {}, {}
	local function slotFor(slot)
		if built[slot] ~= nil then return built[slot] end
		if slot == 'nitrous' and Config.NitrousSystem == 'streetkings' then
			local def, current = streetkingsNitrous(vehicle)
			built[slot] = def or false
			if def then
				session.slots[slot] = def
				session.owned[slot] = current
			end
			return built[slot]
		end
		local cfg = Customs.SlotConfig(slot)
		local def = cfg and allowed(cfg, session.admin) and buildSlot(vehicle, slot, cfg) or false
		built[slot] = def
		if def then session.slots[slot] = def end
		return def
	end
	local layout = {}
	for t, tab in ipairs(Config.Menu) do
		layout[t] = {}
		for c, category in ipairs(tab.categories) do
			local ids = {}
			for _, slot in ipairs(category.slots or {}) do
				if slot == 'extras' then
					for extra = 0, 12 do
						if DoesExtraExist(vehicle, extra) and slotFor('extra:' .. extra) then ids[#ids + 1] = 'extra:' .. extra end
					end
				elseif slotFor(slot) then
					ids[#ids + 1] = slot
				end
			end
			layout[t][c] = ids
		end
	end
	local kits = buildKits()
	for t, tab in ipairs(Config.Menu) do
		local categories = {}
		for c, category in ipairs(tab.categories) do
			local entry = { label = category.label, hint = category.hint or '', camera = category.camera or tab.camera }
			if category.kits then
				if #kits > 0 then
					entry.kits = true
					categories[#categories + 1] = entry
				end
			elseif #layout[t][c] > 0 then
				entry.slots = layout[t][c]
				categories[#categories + 1] = entry
			end
		end
		if #categories > 0 then
			tabs[#tabs + 1] = { id = tab.id, label = tab.label, camera = tab.camera, categories = categories }
		end
	end
	return tabs, kits
end

function OpenCustomsMenu(vehicle, shop, admin)
	if session or opening or vehicle == 0 then return end
	opening = true
	SetTimeout(5000, function() opening = false end) -- in case the server never answers
	oldprop = GetVehicleProperties(vehicle)
	TriggerServerCallback_('renzu_customs:getmoney', function(info)
		opening = false
		if session or type(info) ~= 'table' or not DoesEntityExist(vehicle) then return end
		oldprop.pro_build = info.kit
		SetModable(vehicle)
		local job = PlayerData and PlayerData.job
		session = {
			vehicle = vehicle,
			shop = shop,
			admin = info.admin == true,
			owned = Customs.StateFromProps(oldprop),
			slots = {}, kits = {}, donors = {},
			ctx = {
				job = job and job.name,
				vehicleValue = GetVehicleValue(GetEntityModel(vehicle)) * Config.VehicleValuePercent,
				free = info.admin == true or Config.FreeUpgradeToClass[GetVehicleClass(vehicle)] == true,
			},
		}
		session.base = baseSpec(vehicle)
		local tabs, kits = buildMenu(vehicle)
		local health = GetVehicleBodyHealth(vehicle)
		local staff = shop ~= nil and job ~= nil and Config.Customs[shop].job == job.name
		local brand, name = '', GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
		local make = GetMakeNameFromVehicleModel(GetEntityModel(vehicle))
		brand = make and gameLabel(make) or make or ''
		name = gameLabel(name) or name
		if brand:upper() == name:upper() then brand = '' end -- addon vehicles often give the spawn name for both

		FreezeEntityPosition(vehicle, true)
		SetVehicleEngineOn(vehicle, true, true, false)
		camera = {}
		setView(tabs[1] and tabs[1].camera or 'rear34')
		CreateThread(cameraLoop)
		CreateThread(padLoop)
		setMenuOpen(true)
		session.pad = not IsUsingKeyboard(2) -- drove in with a controller
		SetNuiFocus(true, not session.pad)
		SendNUIMessage({
			type = 'open',
			shop = { id = shop or 'admin', label = Config.ShopLabels[shop] or shop or 'Customs' },
			vehicle = { brand = brand, name = name, owned = info.owned == true },
			tabs = tabs,
			slots = session.slots,
			kits = kits,
			owned = session.owned,
			stats = statsPayload(session.owned),
			objective = objective,
			repair = {
				needed = health < 1000 and not Config.DisableRepair,
				cost = (session.admin or staff) and 0 or Config.RepairCost,
			},
			keys = Config.MenuKeys,
			pad = { style = Config.PadGlyphs, active = session.pad },
		})
	end, NetworkGetNetworkIdFromEntity(vehicle), oldprop)
end

local function closeMenu(restore)
	if not session then return end
	local vehicle = session.vehicle
	revving = false
	if DoesEntityExist(vehicle) then
		if restore then
			-- back to what the vehicle had when it rolled in (or what was last paid for)
			local props = copy(oldprop)
			props.custom_turbo, props.custom_engine, props.custom_tire = nil, nil, nil
			SetVehicleProp(vehicle, props)
		end
		for door = 0, 5 do
			SetVehicleDoorShut(vehicle, door, false)
		end
		SetVehicleLights(vehicle, 0)
		FreezeEntityPosition(vehicle, false)
	end
	session = nil
	camera = nil
	inmark = false
	SetNuiFocus(false, false)
	SendNUIMessage({ type = 'close' })
	setMenuOpen(false)
	TriggerServerEvent('renzu_customs:leaveshop')
end

-- For mission scripts that send the player to the mod shop: a line at the bottom of the menu
-- (~words~ are highlighted) and, with a slot, a tag on its tab and a dot on its category.
-- SetMenuObjective() with nothing clears it. The 'customs:purchased' event tells you what was bought.
exports('SetMenuObjective', function(text, slot)
	objective = text and { text = tostring(text), slot = slot } or nil
	if session then SendNUIMessage({ type = 'objective', objective = objective }) end
end)

AddEventHandler('onResourceStop', function(resource)
	if resource == GetCurrentResourceName() and session then
		closeMenu(true)
		RenderScriptCams(false, false, 0, true, true)
	end
end)

-- NUI

RegisterNUICallback('Preview', function(data, cb)
	if not session or not data.slot then return cb({}) end
	local view = viewWith(data.slot, normalize(data.value))
	applySlot(session.vehicle, data.slot, view)
	cb({ stats = statsPayload(view) })
end)

RegisterNUICallback('Revert', function(data, cb)
	if not session or not data.slot then return cb({}) end
	applySlot(session.vehicle, data.slot, session.owned)
	cb({ stats = statsPayload(session.owned) })
end)

-- Pays for a set of slot changes and, once the server has taken the money, makes them the vehicle's own
local function purchase(changes, cb)
	local vehicle = session.vehicle
	local props = copy(oldprop)
	for slot, value in pairs(changes) do
		Customs.WriteSlot(props, slot, value)
	end
	TriggerServerCallback_('renzu_customs:pay', function(result)
		if not session then return cb({ ok = false }) end
		if type(result) ~= 'table' or not result.ok then
			return cb({ ok = false, message = type(result) == 'table' and result.message or 'The payment did not go through.' })
		end
		local was = session.owned
		session.owned = copy(was)
		for slot, value in pairs(changes) do
			session.owned[slot] = value
		end
		oldprop = props
		for slot in pairs(changes) do
			applySlot(vehicle, slot, session.owned)
		end
		-- these three live on the server by plate and reach the vehicle from there
		if was['custom_engine'] ~= session.owned['custom_engine'] then SetVehicleEngine(vehicle, session.owned['custom_engine']) end
		if was['custom_turbo'] ~= session.owned['custom_turbo'] then SetVehicleTurbo(vehicle, session.owned['custom_turbo']) end
		if was['custom_tires'] ~= session.owned['custom_tires'] then SetVehicleTireType(vehicle, session.owned['custom_tires']) end
		TriggerEvent('customs:purchased', changes) -- slot > value of what was just bought
		-- kits are sent again: buying a part can lower what a kit containing it costs
		cb({ ok = true, paid = result.total, owned = session.owned, stats = statsPayload(session.owned), kits = buildKits() })
	end, { prop = props, shop = session.shop, class = GetVehicleClass(vehicle) })
end

RegisterNUICallback('Buy', function(data, cb)
	if not session or not data.slot or not session.slots[data.slot] then return cb({ ok = false }) end
	if session.slots[data.slot].external then return buyStreetkingsNitrous(data.value, cb) end
	local changes = { [data.slot] = normalize(data.value) }
	if PaintLinks[data.slot] then changes[PaintLinks[data.slot]] = 'off' end
	purchase(changes, cb)
end)

RegisterNUICallback('KitPreview', function(data, cb)
	local parts = session and session.kits[data.id]
	if not parts then return cb({}) end
	-- a kit that was being looked at has to come off before the next one goes on
	for slot in pairs(session.kits[session.previewKit] or {}) do
		applySlot(session.vehicle, slot, session.owned)
	end
	session.previewKit = data.id
	local view = copy(session.owned)
	for slot, value in pairs(parts) do
		view[slot] = value
	end
	for slot in pairs(parts) do
		applySlot(session.vehicle, slot, view)
	end
	cb({ stats = statsPayload(view) })
end)

RegisterNUICallback('KitRevert', function(data, cb)
	local parts = session and session.kits[data.id]
	if not parts then return cb({}) end
	session.previewKit = nil
	for slot in pairs(parts) do
		applySlot(session.vehicle, slot, session.owned)
	end
	cb({ stats = statsPayload(session.owned) })
end)

RegisterNUICallback('KitBuy', function(data, cb)
	local parts = session and session.kits[data.id]
	if not parts then return cb({ ok = false }) end
	local changes = copy(parts)
	changes['kit'] = data.id
	purchase(changes, cb)
end)

RegisterNUICallback('Options', function(data, cb)
	if not session or data.slot ~= 'wheels' then return cb({ options = {} }) end
	local options = wheelOptions(session.vehicle, math.floor(tonumber(data.group) or 0))
	for _, option in ipairs(options) do
		option.price = Customs.Price('wheels', option.value, session.ctx) or 0
		option.stock = option.value == 'stock'
	end
	applySlot(session.vehicle, 'wheels', session.owned)
	cb({ options = options })
end)

RegisterNUICallback('Camera', function(data, cb)
	if session and camera and data.view and data.view ~= camera.name then setView(data.view) end
	cb(1)
end)

RegisterNUICallback('Orbit', function(data, cb)
	if session and camera and camera.goal then
		local goal = camera.goal
		goal.yaw = goal.yaw - (tonumber(data.dx) or 0) * 0.3
		goal.pitch = math.max(-4.0, math.min(70.0, goal.pitch + (tonumber(data.dy) or 0) * 0.2))
		goal.dist = math.max(goal.min, math.min(goal.max, goal.dist * (1.0 + (tonumber(data.zoom) or 0) * 0.1)))
	end
	cb(1)
end)

RegisterNUICallback('Rev', function(data, cb)
	cb(1)
	if not session then return end
	if not data.on then
		revving = false
	elseif not revving then
		revving = true
		CreateThread(function()
			local vehicle = session.vehicle
			local rpm = 0.2
			while revving and session do
				rpm = math.min(rpm + 0.03, 1.0)
				SetVehicleCurrentRpm(vehicle, rpm)
				Wait(0)
			end
		end)
	end
end)

RegisterNUICallback('Repair', function(_, cb)
	if not session then return cb({ ok = false }) end
	local vehicle = session.vehicle
	TriggerServerCallback_('renzu_customs:repair', function(ok)
		if not ok then
			return cb({ ok = false, message = ('You need $%s to repair this vehicle.'):format(numWithCommas(Config.RepairCost)) })
		end
		if Config.UseRenzu_progressbar then
			exports.renzu_progressbar:CreateProgressBar(25, '<i class="fas fa-tools"></i>')
		end
		SetVehicleFixed(vehicle)
		SetVehicleDirtLevel(vehicle, 0.0)
		SetVehicleBodyHealth(vehicle, 1000.0)
		SetVehicleEngineHealth(vehicle, 1000.0)
		SetVehiclePetrolTankHealth(vehicle, 1000.0)
		SetVehicleEngineOn(vehicle, true, true, false)
		oldprop.bodyHealth, oldprop.engineHealth, oldprop.tankHealth, oldprop.dirtLevel = 1000.0, 1000.0, 1000.0, 0.0
		cb({ ok = true })
	end, session.shop)
end)

-- a key or the mouse was used in the menu: give the cursor back
RegisterNUICallback('Input', function(data, cb)
	if session and session.pad and data.pad == false then setPadMode(false) end
	cb(1)
end)

RegisterNUICallback('Close', function(_, cb)
	closeMenu(true)
	cb(1)
end)
