-- MENU / UI CONFIG (loaded after config.lua, on client and server)

-- Shop title shown top-left of the menu. Shops not listed here show their Config.Customs id.
Config.ShopLabels = {
	['LSC Vinewood'] = 'Los Santos Customs',
	['LSC Airport'] = 'Los Santos Customs',
	['LSC East'] = 'Los Santos Customs',
	['LSC Sandy Shores'] = 'Los Santos Customs',
	['LSC Paleto'] = 'Los Santos Customs',
	['Bennys'] = "Benny's Original Motor Works",
}

-- Keyboard controls inside the menu (KeyboardEvent.code values, shown in the prompt circles)
Config.MenuKeys = {
	rev = 'KeyR', -- hold to rev the engine
	card = 'Tab', -- cycle the vehicle card (name / stats / fitted parts)
}

-- Controller: d-pad / left stick move, A select / buy, B back, X (hold) rev, Y card page,
-- LB / RB tabs, right stick look around, LT / RT zoom.
-- Button names shown in the prompts while a controller is in use: 'xbox' or 'playstation'
Config.PadGlyphs = 'xbox'

-- Blur the background behind the vehicle while the menu is open (needs PostFX on High or above)
Config.MenuDepthOfField = true

-- Customers pay with these accounts, in this order (used when the shop society is not paying)
Config.PayAccounts = { 'cash', 'bank' }

-- Prices for options that have no entry of their own in Config.VehicleMod
Config.ExtraPrices = {
	wheelcolor = 1500,
	pearl = 3000,
	chameleon = 15000, -- a chameleon primary colour, in place of the normal respray cost
	rgb = 12000, -- custom RGB respray (primary or secondary)
	tyresmoke = 2000,
	customtire = 1500, -- branded tire sidewalls
	drift = 8000, -- drift tires
	bulletproof = 20000, -- bulletproof tires
}

-- NITROUS
-- power    = engine torque multiplier while boosting
-- duration = seconds of boost in a full tank
-- recharge = seconds to refill an empty tank
-- value    = Cost
-- Where nitrous comes from:
--   'builtin'      the kits below, boosted and stored by this resource
--   'streetkings'  sk_streetkings' nitrous: the Nitrous category sells its tiers, and it does the
--                  boosting, refilling, storing and HUD reporting itself
--   'auto'         'streetkings' when sk_streetkings is installed, otherwise 'builtin'
Config.NitrousSystem = 'auto'
if Config.NitrousSystem == 'auto' then
	Config.NitrousSystem = GetResourceState('sk_streetkings') ~= 'missing' and 'streetkings' or 'builtin'
end
Config.UseNitrous = Config.NitrousSystem == 'builtin'
Config.Nitrous = {
	key = 'LSHIFT', -- default key, players can rebind it in Settings > Key Bindings > FiveM
	padButton = 'L3_INDEX', -- default controller button (left stick press, the game's own boost button), false = none
	refillDelay = 1.5, -- seconds after boosting before the tank starts to refill
	minLevel = 0.25, -- after running the tank dry it must refill to this level (0.0-1.0) before it works again
	flames = true, -- exhaust flames while boosting
	screenfx = true, -- speed blur while boosting
}
if Config.UseNitrous then
	Config.VehicleMod['nitrous'] = {
		job_grade = { -- default job grade to access this Upgrade Feature (this option will work only if Config.JobPermissionAll is true
			['mechanic'] = 0,
			['police'] = 0,-- police is sample only change this!
		},
		discount = {
			['mechanic'] = 0.2, -- 20%
			['ambulance'] = 0.1, -- 10%
			['police'] = 0.15, -- 15%
		},
		label = 'Nitrous',
		name = 'nitrous',
		index = 109,
		cost = 20000,
		percent_cost = 20,
		bone = 'exhaust',
		type = 'Nitrous',
		list = {
			Default = {}, -- needed for uninstall
			Street = {label = 'Street 50 Shot', power = 1.6, duration = 4.0, recharge = 22.0, value = 10000},
			Sport = {label = 'Sport 100 Shot', power = 2.2, duration = 5.5, recharge = 18.0, value = 17500},
			Race = {label = 'Race 150 Shot', power = 3.0, duration = 7.0, recharge = 14.0, value = 25000},
		}
	}
end

-- MENU LAYOUT
-- Tabs > categories > slots. A slot is one thing you can change on the vehicle. A category with
-- one slot opens straight on its options, one with several lists them first.
--   'mod:<index>'  standard mod from Config.VehicleMod (0 spoiler, 11 engine ...)
--   'turbo' 'wheels' 'wheelcolor' 'customtire' 'tyresmoke' 'drift' 'bulletproof'
--   'paint1' 'paint2' 'pearl' 'rgb1' 'rgb2' 'xenon' 'neon' 'plate' 'window' 'extras'
--   'custom_engine' 'custom_turbo' 'custom_tires' 'nitrous'
-- Slots the vehicle has no parts for (or the player has no permission for) are hidden,
-- and so are categories and tabs that end up empty.
-- camera = 'front' 'rear' 'rear34' 'front34' 'side' 'top' 'engine' 'wheel' 'cabin' 'plate'
Config.Menu = {
	{
		id = 'probuilds', label = 'Pro Builds', camera = 'rear',
		categories = {
			{ label = 'Full Kits', hint = 'Complete builds fitted in one visit.', kits = true },
		},
	},
	{
		id = 'cosmetics', label = 'Cosmetics', camera = 'rear34',
		categories = {
			{ label = 'Respray', hint = 'Change the paint job.', slots = { 'paint1' } },
			{ label = 'Secondary Color', hint = 'Paint the trim and accents.', slots = { 'paint2' } },
			{ label = 'Pearlescent', hint = 'Add a pearl coat over the paint.', slots = { 'pearl' } },
			{ label = 'Custom Paint', hint = 'Mix a colour of your own.', slots = { 'rgb1', 'rgb2' } },
			{ label = 'Bodywork', hint = 'Bumpers, skirts, hood, spoiler and more.', slots = { 'mod:0', 'mod:1', 'mod:2', 'mod:3', 'mod:4', 'mod:6', 'mod:7', 'mod:8', 'mod:10', 'mod:5', 'mod:37', 'mod:42', 'mod:43', 'mod:44' } },
			{ label = 'Wheels', hint = 'Rims, wheel paint and tires.', camera = 'wheel', slots = { 'wheels', 'mod:24', 'wheelcolor', 'customtire', 'tyresmoke', 'drift', 'bulletproof' } },
			{ label = 'Lights', hint = 'Headlights and underglow.', camera = 'front34', slots = { 'xenon', 'neon' } },
			{ label = 'Livery', hint = 'Wraps and decals.', camera = 'side', slots = { 'mod:48' } },
			{ label = 'Interior', hint = 'Seats, dash, wheel and trim.', camera = 'cabin', slots = { 'mod:27', 'mod:28', 'mod:29', 'mod:30', 'mod:31', 'mod:32', 'mod:33', 'mod:34', 'mod:35', 'mod:36' } },
			{ label = 'Plates & Glass', hint = 'Plates and window tint.', camera = 'plate', slots = { 'plate', 'mod:25', 'mod:26', 'window', 'mod:46' } },
			{ label = 'Horn', hint = 'Change the horn.', camera = 'front', slots = { 'mod:14' } },
			{ label = 'Extras', hint = 'Toggle factory extras.', slots = { 'extras' } },
		},
	},
	{
		id = 'performance', label = 'Performance', camera = 'engine',
		categories = {
			{ label = 'Full Engine', hint = 'Adjust the torque and top speed.', slots = { 'mod:11' } },
			{ label = 'Intakes', hint = 'Help the engine breathe.', slots = { 'mod:40' } },
			{ label = 'Induction', hint = 'Increase air density flowing to the engine.', slots = { 'turbo' } },
			{ label = 'Transmission', hint = 'Change the speed of gear shifts.', slots = { 'mod:13' } },
			{ label = 'Nitrous', hint = 'Give your vehicle a momentary speed boost.', slots = { 'nitrous' } },
			{ label = 'Brakes', hint = 'Stop harder and later.', camera = 'wheel', slots = { 'mod:12' } },
			{ label = 'Suspension', hint = 'Lower the car and stiffen the ride.', camera = 'side', slots = { 'mod:15' } },
			{ label = 'Armor', hint = 'Reinforce the body.', camera = 'front34', slots = { 'mod:16' } },
			{ label = 'Engine Swap', hint = 'Fit the engine of another vehicle.', slots = { 'custom_engine' } },
			{ label = 'Turbo Kit', hint = 'Bigger turbos with their own blow off valve.', slots = { 'custom_turbo' } },
			{ label = 'Tires', hint = 'Change the tire compound.', camera = 'wheel', slots = { 'custom_tires' } },
			{ label = 'Engine Bay', hint = 'Dress up what is under the hood.', slots = { 'mod:39', 'mod:41', 'mod:45', 'mod:38' } },
		},
	},
}

-- PRO BUILDS (Full Kits)
-- One purchase that fits a whole set of parts. price covers every slot listed and is set about
-- 10% under what those parts cost one by one on a typical car. A vehicle that takes fewer of the
-- parts (or already has some) pays the cost of the parts it actually gets instead, never more.
-- slots: 'max' = best part the vehicle has for that slot, a number = that option (0 is the first upgrade),
-- anything else is the option value itself (true for toggles, a list name for custom upgrades).
-- Slots a vehicle does not have (or that are disabled in config) are skipped.
Config.ProBuilds = {
	{
		id = 'street', label = 'Custom Street Racing Build', price = 250000,
		slots = {
			['mod:11'] = 'max', ['mod:12'] = 'max', ['mod:13'] = 'max', ['mod:15'] = 2, ['turbo'] = true,
			['mod:0'] = 'max', ['mod:1'] = 'max', ['mod:2'] = 'max', ['mod:3'] = 'max', ['mod:4'] = 'max', ['mod:7'] = 'max',
			['custom_tires'] = 'Sports', ['nitrous'] = 'Street',
		},
	},
	{
		id = 'drift', label = 'Custom Drift Build', price = 205000,
		slots = {
			['mod:11'] = 'max', ['mod:13'] = 'max', ['mod:15'] = 'max', ['turbo'] = true, ['drift'] = true,
			['mod:0'] = 0, ['mod:1'] = 0, ['mod:3'] = 0, ['mod:4'] = 0,
			['custom_tires'] = 'Street',
		},
	},
	{
		id = 'drag', label = 'Custom Drag Build', price = 325000,
		slots = {
			['mod:11'] = 'max', ['mod:13'] = 'max', ['mod:12'] = 1, ['turbo'] = true,
			['mod:4'] = 'max', ['mod:7'] = 'max',
			['custom_turbo'] = 'Racing', ['custom_tires'] = 'Drag', ['nitrous'] = 'Race',
		},
	},
	{
		id = 'armored', label = 'Custom Armored Build', price = 155000,
		slots = {
			['mod:16'] = 'max', ['mod:12'] = 'max', ['mod:11'] = 1, ['bulletproof'] = true, ['window'] = 1,
		},
	},
}

-- VEHICLE CARD STATS
-- How much each upgrade moves the 0-10 bars on the vehicle card. These numbers only change
-- what the card shows, not how the vehicle drives.
-- Standard mods are per level, toggles are flat.
Config.StatEffects = {
	['mod:11'] = { speed = 0.22, acceleration = 0.30 }, -- engine
	['mod:12'] = { asphalt = 0.25 }, -- brakes
	['mod:13'] = { acceleration = 0.18, speed = 0.05 }, -- transmission
	['mod:15'] = { asphalt = 0.20, offroad = -0.30 }, -- suspension
	['mod:16'] = { strength = 1.0, acceleration = -0.08 }, -- armor
	['turbo'] = { speed = 0.45, acceleration = 0.60 },
	['drift'] = { asphalt = -2.0 },
	['bulletproof'] = { strength = 0.4 },
	-- custom upgrades, by list name. Entries missing here are worked out from their handling values.
	['custom_tires'] = {
		Street = { asphalt = 0.2, offroad = 0.2 },
		Sports = { asphalt = 0.6, offroad = -0.4 },
		Racing = { asphalt = 1.4, offroad = -1.3 },
		Drag = { acceleration = 0.8, asphalt = -2.5, offroad = -2.0 },
	},
	['nitrous'] = {
		Street = { acceleration = 0.3 },
		Sport = { acceleration = 0.5, speed = 0.1 },
		Race = { acceleration = 0.8, speed = 0.2 },
		-- sk_streetkings tiers
		street = { acceleration = 0.3 },
		sport = { acceleration = 0.5, speed = 0.1 },
		race = { acceleration = 0.8, speed = 0.2 },
	},
}
