-- NPC race invites via lb-phone.
--
-- A rival "texts" the player through lb-phone.SendNotification with a
-- meet-up point on the map. Show up in a vehicle within the response window
-- and a rival ped + car are spawned right there, then handed to
-- SKNpcRace.start (exposed at the bottom of npcchallenge_c.lua) - the exact
-- same countdown/lockdown/race-loop/server-validated-payout engine the
-- ambient burnout trigger already uses. This file only ever decides WHEN and
-- WHERE a race offer appears; everything about running the race itself is
-- npcchallenge's — including whether Config.StreetPack rolls the rival into
-- a pack of 2-4 cars, which SKNpcRace.start does on its own without this
-- file needing to know or care.

if not Config.Modules.npcChallenge then return end
if not Config.Modules.npcInvite then return end

local cfg = Config.NpcInvite

local DRIVER_PED_MODELS = {
    'a_m_y_hipster_01', 'a_m_y_business_03', 'g_m_y_mexgoon_01', 'a_m_y_skater_01',
}

---@type {rival: string, message: string, coords: vector3, expiresAt: number, blip: number}|nil
local pendingInvite = nil
local watching       = false

local function clearInvite()
    if pendingInvite and pendingInvite.blip and DoesBlipExist(pendingInvite.blip) then
        RemoveBlip(pendingInvite.blip)
    end
    pendingInvite = nil
    watching = false
end

local function notify(rival, content)
    pcall(function()
        exports['lb-phone']:SendNotification({ app = 'Street Kings', title = rival, content = content })
    end)
end

-- ── Meet-up point ────────────────────────────────────────────────────────────

--- Same distance band npcchallenge's own ambient destination uses, but from
--- an arbitrary bearing rather than always "in front of the player right
--- now" - a texted meet-up should read as a place, not a direction.
---@return vector3
local function pickMeetupPoint()
    local pos    = GetEntityCoords(PlayerPedId())
    local angle  = math.random() * 2 * math.pi
    local dist   = math.random(cfg.meetupDistanceMin, cfg.meetupDistanceMax)
    local target = pos + vector3(math.cos(angle) * dist, math.sin(angle) * dist, 0.0)

    local found, roadPos = GetClosestVehicleNodeWithHeading(target.x, target.y, target.z, 0, 3.0, 0)
    if found then return vector3(roadPos.x, roadPos.y, roadPos.z) end
    return target
end

-- ── Sending an invite ────────────────────────────────────────────────────────

local function sendInvite()
    local rival   = cfg.rivalNames[math.random(#cfg.rivalNames)]
    local message = cfg.inviteMessages[math.random(#cfg.inviteMessages)]
    local coords  = pickMeetupPoint()

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 501)
    SetBlipColour(blip, 1)
    -- No auto-route: the blip marks where the meetup is, finding your own way
    -- there is on you.
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(rival .. ' - Meet Up')
    EndTextCommandSetBlipName(blip)

    pendingInvite = {
        rival     = rival,
        message   = message,
        coords    = coords,
        expiresAt = GetGameTimer() + cfg.responseWindowMs,
        blip      = blip,
    }

    notify(rival, message)
end

-- ── Spawning the rival once the player shows up ─────────────────────────────

---@param coords vector3
---@return integer|nil vehicle, integer|nil ped
local function spawnRival(coords)
    local vehHash = GetHashKey(cfg.vehicleModels[math.random(#cfg.vehicleModels)])
    local pedHash = GetHashKey(DRIVER_PED_MODELS[math.random(#DRIVER_PED_MODELS)])

    RequestModel(vehHash)
    RequestModel(pedHash)
    local timeout = GetGameTimer() + 4000
    while (not HasModelLoaded(vehHash) or not HasModelLoaded(pedHash)) and GetGameTimer() < timeout do
        Wait(0)
    end
    if not HasModelLoaded(vehHash) or not HasModelLoaded(pedHash) then return nil, nil end

    local heading = math.random(0, 359) + 0.0
    local vehicle = CreateVehicle(vehHash, coords.x, coords.y, coords.z, heading, true, false)
    SetModelAsNoLongerNeeded(vehHash)

    local ped = CreatePedInsideVehicle(vehicle, 4, pedHash, -1, true, false)
    SetModelAsNoLongerNeeded(pedHash)

    return vehicle, ped
end

-- ── Watching for arrival ─────────────────────────────────────────────────────

local function startWatching()
    if watching then return end
    watching = true

    CreateThread(function()
        while pendingInvite and watching do
            Wait(1000)
            if not pendingInvite then break end

            if GetGameTimer() > pendingInvite.expiresAt then
                notify(pendingInvite.rival, cfg.expiredMessage)
                clearInvite()
                break
            end

            -- A race is already running (this invite or the ambient burnout
            -- trigger) - don't spawn a second rival on top of it.
            if SKNpcRace.isActive() then goto continue end

            local ped = PlayerPedId()
            if not IsPedInAnyVehicle(ped, false) then goto continue end

            if #(GetEntityCoords(ped) - pendingInvite.coords) <= cfg.arriveRadius then
                local coords = pendingInvite.coords
                local rival  = pendingInvite.rival
                clearInvite() -- consumed before starting, so arrival can't double-trigger

                local vehicle, rivalPed = spawnRival(coords)
                if vehicle and rivalPed then
                    notify(rival, cfg.acceptedMessage)
                    SKNpcRace.start(vehicle, rivalPed)
                end

                break
            end

            ::continue::
        end
    end)
end

-- ── Scheduler ────────────────────────────────────────────────────────────────

CreateThread(function()
    SK.WaitForControl()

    while true do
        Wait(math.random(cfg.intervalMsMin, cfg.intervalMsMax))

        if SKC.GetGameState() ~= GameState.FREEROAM then goto continue end
        if pendingInvite or SKNpcRace.isActive() then goto continue end
        if GetResourceState('lb-phone') ~= 'started' then goto continue end

        sendInvite()
        startWatching()

        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearInvite()
end)

-- ── Phone app API ────────────────────────────────────────────────────────────
-- Read by modules/phoneapp/phoneapp_c.lua. Arrival is still what actually
-- starts a race (see startWatching above) - accept() here just re-sets the
-- waypoint in case the player cleared it, and decline() lets the player call
-- off an invite they don't want without having to ignore it out to expiry.

SKNpcInvite = {
    getPending = function()
        if not pendingInvite then return nil end
        return {
            rival       = pendingInvite.rival,
            message     = pendingInvite.message,
            expiresInMs = math.max(0, pendingInvite.expiresAt - GetGameTimer()),
        }
    end,

    accept = function()
        if not pendingInvite then return false end
        SetNewWaypoint(pendingInvite.coords.x, pendingInvite.coords.y)
        return true
    end,

    decline = function()
        if not pendingInvite then return false end
        notify(pendingInvite.rival, 'Chicken.')
        clearInvite()
        return true
    end,
}
