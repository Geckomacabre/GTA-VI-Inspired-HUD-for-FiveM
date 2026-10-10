-- Shared by client and server so the basket the player sees and the amount the server
-- charges are always worked out by the same code.
-- A "slot" is one thing that can be changed on a vehicle (see config_menu.lua), and a
-- "state" is a table of slot -> value read out of vehicle props.
Customs = {}

-- props key of every standard mod slot ('mod:<index>')
Customs.ModProps = {
	[0] = 'modSpoilers', [1] = 'modFrontBumper', [2] = 'modRearBumper', [3] = 'modSideSkirt', [4] = 'modExhaust',
	[5] = 'modFrame', [6] = 'modGrille', [7] = 'modHood', [8] = 'modFender', [9] = 'modRightFender', [10] = 'modRoof',
	[11] = 'modEngine', [12] = 'modBrakes', [13] = 'modTransmission', [14] = 'modHorns', [15] = 'modSuspension',
	[16] = 'modArmor', [24] = 'modBackWheels', [25] = 'modPlateHolder', [26] = 'modVanityPlate', [27] = 'modTrimA',
	[28] = 'modOrnaments', [29] = 'modDashboard', [30] = 'modDial', [31] = 'modDoorSpeaker', [32] = 'modSeats',
	[33] = 'modSteeringWheel', [34] = 'modShifterLeavers', [35] = 'modAPlate', [36] = 'modSpeakers', [37] = 'modTrunk',
	[38] = 'modHydrolic', [39] = 'modEngineBlock', [40] = 'modAirFilter', [41] = 'modStruts', [42] = 'modArchCover',
	[43] = 'modAerials', [44] = 'modTrimB', [45] = 'modTank', [46] = 'modWindows', [48] = 'modLivery',
}

-- Config.VehicleMod entry that holds the cost, discount and job permission of a slot
local SlotConfigKey = {
	turbo = 18, wheels = 23, wheelcolor = 23, customtire = 23, tyresmoke = 23, drift = 23, bulletproof = 23,
	paint1 = 'paint1', pearl = 'paint1', rgb1 = 'paint1', paint2 = 'paint2', rgb2 = 'paint2',
	xenon = 'headlight', neon = 'neon', plate = 'plate', window = 'window',
	custom_engine = 'custom_engine', custom_turbo = 'custom_turbo', custom_tires = 'custom_tires', nitrous = 'nitrous',
}

function Customs.Truthy(v)
	return v == true or v == 1
end

local function int(v, default)
	return math.floor(tonumber(v) or default)
end

function Customs.Rgb(t)
	if type(t) ~= 'table' then return '0,0,0' end
	return int(t[1], 0) .. ',' .. int(t[2], 0) .. ',' .. int(t[3], 0)
end

function Customs.ParseRgb(s)
	local r, g, b = tostring(s):match('^(%d+),(%d+),(%d+)$')
	if not r then return nil end
	return { math.min(tonumber(r), 255), math.min(tonumber(g), 255), math.min(tonumber(b), 255) }
end

function Customs.PlateKey(plate)
	return (tostring(plate or ''):gsub('^%s*(.-)%s*$', '%1')):upper()
end

function Customs.ModIndex(slot)
	return tonumber(slot:match('^mod:(%d+)$'))
end

function Customs.SlotConfig(slot)
	local mod = Customs.ModIndex(slot)
	if mod then return Config.VehicleMod[mod] end
	if slot:match('^extra:%d+$') then return Config.VehicleMod['extra'] end
	return Config.VehicleMod[SlotConfigKey[slot]]
end

function Customs.StateFromProps(p)
	local s = {}
	for mod, key in pairs(Customs.ModProps) do
		s['mod:' .. mod] = int(p[key], -1)
	end
	s['turbo'] = Customs.Truthy(p.modTurbo)
	local wheel = int(p.modFrontWheels, -1)
	s['wheels'] = wheel < 0 and 'stock' or (int(p.wheels, 0) .. ':' .. wheel)
	s['wheelcolor'] = int(p.wheelColor, 0)
	s['paint1'] = int(p.color1, 0)
	s['paint2'] = int(p.color2, 0)
	s['pearl'] = int(p.pearlescentColor, 0)
	s['rgb1'] = Customs.Truthy(p.customPrimary) and Customs.Rgb(p.rgb) or 'off'
	s['rgb2'] = Customs.Truthy(p.customSecondary) and Customs.Rgb(p.rgb2) or 'off'
	local xenon = int(p.xenonColor, 255)
	s['xenon'] = Customs.Truthy(p.modXenon) and ((xenon < 0 or xenon > 12) and -1 or xenon) or 'off'
	local neon = false
	if type(p.neonEnabled) == 'table' then
		for i = 1, 4 do
			if Customs.Truthy(p.neonEnabled[i]) then neon = true end
		end
	end
	s['neon'] = neon and Customs.Rgb(p.neonColor) or 'off'
	s['plate'] = int(p.plateIndex, 0)
	s['window'] = math.max(int(p.windowTint, 0), 0)
	if type(p.extras) == 'table' then
		for id, on in pairs(p.extras) do
			s['extra:' .. id] = Customs.Truthy(on)
		end
	end
	s['tyresmoke'] = Customs.Truthy(p.modSmokeEnabled) and Customs.Rgb(p.tyreSmokeColor) or 'off'
	s['drift'] = Customs.Truthy(p.drift_tire)
	s['bulletproof'] = Customs.Truthy(p.bulletProofTyres)
	s['customtire'] = Customs.Truthy(p.modCustomTiresF)
	s['custom_engine'] = p.custom_engine or 'Default'
	s['custom_turbo'] = p.custom_turbo or 'Default'
	s['custom_tires'] = p.custom_tire or 'Default'
	s['nitrous'] = p.custom_nitrous or 'Default'
	s['kit'] = p.pro_build or 'none'
	return s
end

-- Inverse of StateFromProps for a single slot
function Customs.WriteSlot(p, slot, value)
	local mod = Customs.ModIndex(slot)
	if mod then
		p[Customs.ModProps[mod]] = value
	elseif slot == 'turbo' then p.modTurbo = value
	elseif slot == 'wheels' then
		local wtype, index = tostring(value):match('^(%d+):(%d+)$')
		if wtype then
			p.wheels = tonumber(wtype)
			p.modFrontWheels = tonumber(index)
		else
			p.modFrontWheels = -1
		end
	elseif slot == 'wheelcolor' then p.wheelColor = value
	elseif slot == 'paint1' then p.color1 = value
	elseif slot == 'paint2' then p.color2 = value
	elseif slot == 'pearl' then p.pearlescentColor = value
	elseif slot == 'rgb1' then
		p.customPrimary = value ~= 'off'
		if value ~= 'off' then p.rgb = Customs.ParseRgb(value) end
	elseif slot == 'rgb2' then
		p.customSecondary = value ~= 'off'
		if value ~= 'off' then p.rgb2 = Customs.ParseRgb(value) end
	elseif slot == 'xenon' then
		p.modXenon = value ~= 'off'
		if value ~= 'off' then p.xenonColor = value < 0 and 255 or value end
	elseif slot == 'neon' then
		local on = value ~= 'off'
		p.neonEnabled = { on, on, on, on }
		if on then p.neonColor = Customs.ParseRgb(value) end
	elseif slot == 'plate' then p.plateIndex = value
	elseif slot == 'window' then p.windowTint = value
	elseif slot == 'tyresmoke' then
		p.modSmokeEnabled = value ~= 'off'
		if value ~= 'off' then p.tyreSmokeColor = Customs.ParseRgb(value) end
	elseif slot == 'drift' then p.drift_tire = value
	elseif slot == 'bulletproof' then p.bulletProofTyres = value
	elseif slot == 'customtire' then p.modCustomTiresF = value
	elseif slot == 'custom_engine' then p.custom_engine = value
	elseif slot == 'custom_turbo' then p.custom_turbo = value
	elseif slot == 'custom_tires' then p.custom_tire = value
	elseif slot == 'nitrous' then p.custom_nitrous = value
	elseif slot == 'kit' then p.pro_build = value ~= 'none' and value or nil
	else
		local extra = slot:match('^extra:(%d+)$')
		if extra then
			p.extras = p.extras or {}
			p.extras[extra] = value
		end
	end
end

local function modCost(cfg, ctx)
	local cost = tonumber(cfg.cost) or 0
	if Config.VehicleValuetoFormula and tonumber(cfg.percent_cost) then
		cost = cost + ((ctx.vehicleValue or 0) / cfg.percent_cost)
	end
	return cost
end

local chameleon = nil -- paint indexes of the chameleon finishes
local function isChameleon(index)
	if not chameleon then
		chameleon = {}
		for _, paint in pairs(Config.Chameleon or {}) do
			chameleon[paint] = true
		end
	end
	return chameleon[index] == true
end

local function isRgb(value)
	return type(value) == 'string' and Customs.ParseRgb(value) ~= nil
end

-- Price before discounts. nil = not something this shop sells (the server refuses those).
function Customs.BasePrice(slot, value, ctx)
	local cfg = Customs.SlotConfig(slot)
	if not cfg then return nil end
	local extra = Config.ExtraPrices
	if Customs.ModIndex(slot) then
		if type(value) ~= 'number' then return nil end
		if value < 0 then return 0 end
		local cost = modCost(cfg, ctx)
		return cfg.multicostperlvl and cost * (value + 1) or cost
	elseif slot == 'turbo' then
		return value == true and modCost(cfg, ctx) or 0
	elseif slot == 'wheels' then
		if value == 'stock' then return 0 end
		return type(value) == 'string' and value:match('^%d+:%d+$') and modCost(cfg, ctx) or nil
	elseif slot == 'paint1' then
		if type(value) ~= 'number' then return nil end
		return isChameleon(value) and extra.chameleon or modCost(cfg, ctx)
	elseif slot == 'paint2' or slot == 'plate' then
		return type(value) == 'number' and modCost(cfg, ctx) or nil
	elseif slot == 'pearl' then
		return type(value) == 'number' and extra.pearl or nil
	elseif slot == 'wheelcolor' then
		return type(value) == 'number' and extra.wheelcolor or nil
	elseif slot == 'rgb1' or slot == 'rgb2' then
		if value == 'off' then return 0 end
		return isRgb(value) and extra.rgb or nil
	elseif slot == 'tyresmoke' then
		if value == 'off' then return 0 end
		return isRgb(value) and extra.tyresmoke or nil
	elseif slot == 'neon' then
		if value == 'off' then return 0 end
		return isRgb(value) and modCost(cfg, ctx) or nil
	elseif slot == 'xenon' then
		if value == 'off' then return 0 end
		return type(value) == 'number' and modCost(cfg, ctx) or nil
	elseif slot == 'window' then
		if type(value) ~= 'number' then return nil end
		return value > 0 and modCost(cfg, ctx) or 0
	elseif slot == 'drift' or slot == 'bulletproof' or slot == 'customtire' then
		return value == true and extra[slot] or 0
	elseif slot == 'custom_engine' then
		if value == 'Default' then return 0 end
		for _, entry in pairs(cfg.list) do
			if entry.model == value then return tonumber(entry.value) or 0 end
		end
		return nil
	elseif slot == 'custom_turbo' or slot == 'custom_tires' or slot == 'nitrous' then
		if value == 'Default' then return 0 end
		local entry = type(value) == 'string' and cfg.list[value]
		return entry and (tonumber(entry.value) or 0) or nil
	end
	-- extra:<id>, turning an extra off is free
	return value == true and modCost(cfg, ctx) or 0
end

function Customs.Discount(cfg, ctx)
	if not Config.EnableDiscounts or not ctx.job then return 0 end
	if cfg and cfg.discount and cfg.discount[ctx.job] ~= nil then
		return tonumber(cfg.discount[ctx.job]) or 0
	end
	return tonumber(Config.JobDiscounts[ctx.job]) or 0
end

-- ctx = { job = job name, vehicleValue = vehicle value * Config.VehicleValuePercent, free = bool }
function Customs.Price(slot, value, ctx)
	local base = Customs.BasePrice(slot, value, ctx)
	if not base then return nil end
	if ctx.free or base <= 0 then return 0 end
	return math.floor(base * (1 - Customs.Discount(Customs.SlotConfig(slot), ctx)) + 0.5)
end

function Customs.Kit(id)
	for _, kit in ipairs(Config.ProBuilds or {}) do
		if kit.id == id then return kit end
	end
end

function Customs.KitPrice(kit, ctx)
	if ctx.free then return 0 end
	return math.floor((tonumber(kit.price) or 0) * (1 - Customs.Discount(nil, ctx)) + 0.5)
end

-- Everything that changed between two states, priced.
-- Returns items = { {slot, value, price}, ... } and the total, or nil if a change is not for sale.
function Customs.Cart(old, new, ctx)
	local items, total, covered = {}, 0, {}
	if new['kit'] ~= old['kit'] and new['kit'] ~= 'none' then
		local kit = Customs.Kit(new['kit'])
		if not kit then return nil end
		covered = kit.slots
		-- a kit never costs more than the parts it actually changes on this vehicle
		local parts = 0
		for slot in pairs(covered) do
			if new[slot] ~= nil and old[slot] ~= new[slot] then
				local part = Customs.Price(slot, new[slot], ctx)
				if not part then return nil end
				parts = parts + part
			end
		end
		local price = math.min(Customs.KitPrice(kit, ctx), parts)
		items[#items + 1] = { slot = 'kit', value = new['kit'], price = price }
		total = total + price
	end
	for slot, value in pairs(new) do
		if slot ~= 'kit' and old[slot] ~= value and covered[slot] == nil then
			local price = Customs.Price(slot, value, ctx)
			if not price then return nil end
			items[#items + 1] = { slot = slot, value = value, price = price }
			total = total + price
		end
	end
	return items, total
end
