-- Hangout zones (passive mode), ported from streetkings
-- modules/hangoutzones/hangoutzones_c.lua.
--
-- Inside a zone the player and their vehicle go semi-transparent and stop
-- colliding with other players, and combat controls are suppressed — so a busy
-- meet spot does not turn into a demolition derby.
--
-- The StreetKings original also handled IPL interior teleports for zones that
-- have one. That part is not carried over: this server already has MLO/IPL
-- entry handled elsewhere (bob74_ipl, the car meet module), and duplicating it
-- would fight those. Interior-only zones therefore get a blip and waypoint but
-- no passive polygon, which is all they can offer without the teleport.

if not Config.Modules.hangoutZones then return end

SKHangoutZonesClient = {}

local PASSIVE_GHOST_ALPHA = 160

-- Attack, aim, melee, and vehicle drive-by controls.
local PASSIVE_DISABLE_CONTROLS = {
    24, 25, 47, 58, 140, 141, 142, 143, 263, 264,
}

local activeZones      = {}
local waypointIds      = {}
local blips            = {}

local insidePassiveZone = false
local passiveGhosted    = false
local zoneEntryVehicle  = nil
local currentZoneName   = nil

---@return boolean
function SKHangoutZonesClient.isInsideZone()
    return insidePassiveZone
end

-- ── HUD ─────────────────────────────────────────────────────────────────────

SKHud.register('hangoutZone', function(data)
    SKHud.Panel(0.5, 0.055, 0.20, 0.040, SKHud.Palette.panel)
    SKHud.Text(data.name, 0.5, 0.036, 0.32, SKHud.Palette.accent, true)
    SKHud.Text('PASSIVE MODE', 0.5, 0.058, 0.26, SKHud.Palette.textDim, true)
end)

-- ── Ghosting ────────────────────────────────────────────────────────────────

local function applyGhostAlpha(ped)
    local inVeh = IsPedInAnyVehicle(ped, false)

    if inVeh and not passiveGhosted then
        passiveGhosted = true
        SetEntityAlpha(ped, PASSIVE_GHOST_ALPHA, false)
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 then
            SetEntityAlpha(veh, PASSIVE_GHOST_ALPHA, false)
            zoneEntryVehicle = veh
        end
    elseif not inVeh and passiveGhosted then
        passiveGhosted = false
        ResetEntityAlpha(ped)
        if zoneEntryVehicle and DoesEntityExist(zoneEntryVehicle) then
            ResetEntityAlpha(zoneEntryVehicle)
        end
    end
end

local function clearGhosting()
    local ped = cache.ped
    passiveGhosted = false
    ResetEntityAlpha(ped)
    SetEntityNoCollisionEntity(ped, ped, true)

    if zoneEntryVehicle and DoesEntityExist(zoneEntryVehicle) then
        ResetEntityAlpha(zoneEntryVehicle)
    end
    zoneEntryVehicle = nil
end

--- Turns off collision between the local player (and their car) and every other
--- player nearby, re-applied each tick because new players stream in.
local function updatePlayerCollisions()
    local ped = cache.ped
    local myVeh = GetVehiclePedIsIn(ped, false)

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local otherPed = GetPlayerPed(playerId)
            if otherPed ~= 0 and DoesEntityExist(otherPed) then
                SetEntityNoCollisionEntity(ped, otherPed, true)

                local otherVeh = GetVehiclePedIsIn(otherPed, false)
                if otherVeh ~= 0 then
                    SetEntityNoCollisionEntity(ped, otherVeh, true)
                    if myVeh ~= 0 then
                        SetEntityNoCollisionEntity(myVeh, otherVeh, true)
                        SetEntityNoCollisionEntity(myVeh, otherPed, true)
                    end
                end
            end
        end
    end
end

local passiveTickGen = 0

local function startPassiveTick()
    passiveTickGen = passiveTickGen + 1
    local myGen = passiveTickGen

    CreateThread(function()
        while insidePassiveZone and myGen == passiveTickGen do
            local ped = cache.ped

            applyGhostAlpha(ped)
            updatePlayerCollisions()

            for _, control in ipairs(PASSIVE_DISABLE_CONTROLS) do
                DisableControlAction(0, control, true)
            end

            Wait(0)
        end

        clearGhosting()
    end)
end

local function enterZone(zoneDef)
    if insidePassiveZone then return end
    insidePassiveZone = true
    currentZoneName   = zoneDef.name

    SKHud.set('hangoutZone', { name = zoneDef.name })
    lib.notify({
        title       = zoneDef.name,
        description = zoneDef.description,
        type        = 'inform',
        duration    = 6000,
    })

    startPassiveTick()
end

local function exitZone()
    if not insidePassiveZone then return end
    insidePassiveZone = false
    currentZoneName   = nil
    passiveTickGen    = passiveTickGen + 1

    SKHud.clear('hangoutZone')
    clearGhosting()
end

-- ── Setup ───────────────────────────────────────────────────────────────────

local function setup()
    for _, zoneDef in ipairs(SKHangoutZones.CATALOG) do
        local centre = SKHangoutZones.getCenter(zoneDef)

        local blip = AddBlipForCoord(centre.x, centre.y, centre.z)
        SetBlipSprite(blip, 492)
        SetBlipColour(blip, 27)
        SetBlipScale(blip, 0.75)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(zoneDef.name)
        EndTextCommandSetBlipName(blip)
        blips[#blips + 1] = blip

        waypointIds[#waypointIds + 1] = SKWaypoint.Create({
            coords    = centre,
            label     = zoneDef.name:upper(),
            color     = zoneDef.waypointColor,
            maxRender = SKHangoutZones.WAYPOINT_MAX_RENDER,
        })

        -- Interior-only zones have no polygon to stand inside.
        if zoneDef.poly and #zoneDef.poly > 0 then
            activeZones[#activeZones + 1] = lib.zones.poly({
                points   = zoneDef.poly,
                thickness = (zoneDef.maxZ - zoneDef.minZ),
                debug    = false,
                onEnter  = function() enterZone(zoneDef) end,
                onExit   = exitZone,
            })
        end
    end
end

CreateThread(function()
    Wait(1500)
    setup()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    exitZone()
    for _, zone in ipairs(activeZones) do zone:remove() end
    for _, wpId in ipairs(waypointIds) do SKWaypoint.Remove(wpId) end
    for _, blip in ipairs(blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
end)

exports('isInHangoutZone', SKHangoutZonesClient.isInsideZone)
