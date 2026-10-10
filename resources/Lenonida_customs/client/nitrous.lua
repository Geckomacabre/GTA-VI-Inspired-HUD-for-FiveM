-- Nitrous kits. Bought in the upgrade menu (Performance > Nitrous) and stored by plate on the server.
-- With Config.NitrousSystem = 'streetkings' none of this runs: sk_streetkings boosts and writes the
-- state bag below itself, and the menu only sells its tiers (see client/menu.lua).
--
-- HUD interface, for any resource that wants to draw a nitrous gauge:
--   LocalPlayer.state['customs:nitrous'] (not replicated) and the local event 'customs:nitrous'
--   both carry { installed, kit, label, level, active, ready, command }
--     installed  the player is driving a vehicle with a nitrous kit (false > hide the gauge)
--     kit/label  Config.VehicleMod['nitrous'].list key and its display name
--     level      tank fill 0.0 - 1.0
--     active     boosting right now
--     ready      false while locked out after running the tank dry
--     command    the key mapping command of the boost key, to look up what the player bound it to
--   exports[resource]:GetNitrousState() returns the same table.

local kits = {} -- plate > kit name
local levels = {} -- plate > tank level, kept so swapping cars does not refill the tank
local held = false
local COMMAND = '+customsnitrous'
local state = { installed = false, level = 0.0, active = false, ready = false, command = COMMAND }
local lastPublish = 0

NitrousPower = 1.0 -- read by the custom turbo loop so the two boosts multiply

function GetVehicleNitrous(vehicle)
	return kits[Customs.PlateKey(GetVehicleNumberPlateText(vehicle))] or 'Default'
end

exports('GetVehicleNitrous', function(vehicle)
	return GetVehicleNitrous(vehicle)
end)

exports('GetNitrousState', function()
	return state
end)

RegisterNetEvent('renzu_customs:nitrous')
AddEventHandler('renzu_customs:nitrous', function(all, plate, kit)
	if all then
		kits = all
	elseif plate then
		kits[plate] = kit
		if not kit then levels[plate] = nil end
	end
end)

local function publish(installed, kit, label, level, active, ready)
	local changed = state.installed ~= installed or state.kit ~= kit or state.active ~= active or state.ready ~= ready
	local now = GetGameTimer()
	if not changed and (state.level == level or now - lastPublish < 100) then return end
	lastPublish = now
	state = { installed = installed, kit = kit, label = label, level = level, active = active, ready = ready, command = COMMAND }
	LocalPlayer.state:set('customs:nitrous', state, false)
	TriggerEvent('customs:nitrous', state)
end

local function exhaustOffsets(vehicle)
	local offsets = {}
	for i = 1, 16 do
		local bone = GetEntityBoneIndexByName(vehicle, i == 1 and 'exhaust' or ('exhaust_' .. i))
		if bone ~= -1 then
			offsets[#offsets + 1] = GetOffsetFromEntityGivenWorldCoords(vehicle, GetWorldPositionOfEntityBone(vehicle, bone))
		end
	end
	return offsets
end

local function setBoostFx(vehicle, on)
	SetVehicleBoostActive(vehicle, on)
	if not Config.Nitrous.screenfx then return end
	if on then
		AnimpostfxPlay('RaceTurbo', 0, false)
	else
		AnimpostfxStop('RaceTurbo')
	end
end

-- the custom turbo sets the same power multiplier, so both loops have to agree on the product
local function turboPower(vehicle)
	local name = customturbo[GetVehicleNumberPlateText(vehicle)]
	local turbo = name and name ~= 'Default' and Config.VehicleMod['custom_turbo'] and Config.VehicleMod['custom_turbo'].list[name]
	if turbo and turbo.Power and IsControlPressed(0, 32) and GetVehicleTurboPressure(vehicle) >= turbo.Power then
		return turbo.Power * GetVehicleTurboPressure(vehicle)
	end
	return 1.0
end

local function drive(vehicle, plate, name, kit)
	local settings = Config.Nitrous
	local level = levels[plate] or 1.0
	local ready = level >= settings.minLevel
	local active = false
	local lastUse, lastFlame = 0, 0
	local exhausts = settings.flames and exhaustOffsets(vehicle) or {}
	while kits[plate] == name and GetVehiclePedIsIn(PlayerPedId(), false) == vehicle and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() do
		local dt = GetFrameTime()
		local now = GetGameTimer()
		local boost = held and ready and level > 0.0 and GetIsVehicleEngineRunning(vehicle) and not LocalPlayer.state['customs:menuOpen']
		if boost then
			if not active then
				active = true
				NitrousPower = kit.power
				setBoostFx(vehicle, true)
			end
			level = math.max(0.0, level - dt / kit.duration)
			lastUse = now
			SetVehicleCheatPowerIncrease(vehicle, kit.power * turboPower(vehicle))
			if now - lastFlame > 90 then
				lastFlame = now
				for _, offset in ipairs(exhausts) do
					UseParticleFxAssetNextCall('core')
					StartNetworkedParticleFxNonLoopedOnEntity('veh_backfire', vehicle, offset.x, offset.y, offset.z, 0.0, 0.0, 0.0, 1.4, false, false, false)
				end
			end
			if level <= 0.0 then ready = false end
		else
			if active then
				active = false
				NitrousPower = 1.0
				setBoostFx(vehicle, false)
			end
			if now - lastUse > settings.refillDelay * 1000 then
				level = math.min(1.0, level + dt / kit.recharge)
			end
			if not ready and level >= settings.minLevel then ready = true end
		end
		levels[plate] = level
		publish(true, name, kit.label or name, math.floor(level * 1000 + 0.5) / 1000, active, ready)
		Wait(0)
	end
	if active then
		NitrousPower = 1.0
		setBoostFx(vehicle, false)
	end
end

if Config.UseNitrous then
	RegisterCommand(COMMAND, function() held = true end, false)
	RegisterCommand('-customsnitrous', function() held = false end, false)
	RegisterKeyMapping(COMMAND, 'Nitrous boost', 'keyboard', Config.Nitrous.key)
	if Config.Nitrous.padButton then -- ~! registers a second binding of the same command
		RegisterKeyMapping('~!' .. COMMAND, 'Nitrous boost (controller)', 'PAD_DIGITALBUTTON', Config.Nitrous.padButton)
	end

	CreateThread(function()
		RequestNamedPtfxAsset('core')
		while true do
			local ped = PlayerPedId()
			local vehicle = GetVehiclePedIsIn(ped, false)
			local plate = vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped and Customs.PlateKey(GetVehicleNumberPlateText(vehicle))
			local name = plate and kits[plate]
			local kit = name and Config.VehicleMod['nitrous'].list[name]
			if kit and kit.power then
				drive(vehicle, plate, name, kit)
			else
				publish(false, nil, nil, 0.0, false, false)
			end
			Wait(500)
		end
	end)
end

AddEventHandler('onResourceStop', function(resource)
	if resource == GetCurrentResourceName() and Config.UseNitrous then
		LocalPlayer.state:set('customs:nitrous', { installed = false, level = 0.0, active = false, ready = false }, false)
	end
end)
