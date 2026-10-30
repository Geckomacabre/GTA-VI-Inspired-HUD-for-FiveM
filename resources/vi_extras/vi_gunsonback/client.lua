--[[ ===========================================================================
     vi_gunsonback — client
     ---------------------------------------------------------------------------
     GUNS ON BACK, ported from single player (GTA6Hud's WeaponsOnBack). The
     long guns you carry but aren't holding (rifles, machine guns, shotguns,
     snipers, launchers) hang on your back, the first angled one way across
     the upper spine and the second the other way, two at most. Pistols, SMGs,
     melee weapons and throwables never show. Dead or in a vehicle, none show.
     While DRAW ANIMATIONS carries a long gun to or from the back, that gun is
     in the right hand instead.

     What you carry: your ox_inventory weapons while ox_inventory runs (it only
     ever gives the ped the gun in hand), else the ped's own weapons. Which two
     show is single player's choice too: the first two by weapon hash.

     Everyone sees them. Your list goes in your player state bag (viBack), and
     every client hangs its own local, non-networked weapon objects on the
     players near it, so no networked objects are made. Switching the row off
     clears your state bag.

     Public API: none. The GUNS ON BACK row of HUD OPTIONS switches it per
     player. vi_drawanims says which gun is in the hand through the local
     event vi_drawanims:hand(drawInHand, holding).
     ========================================================================= ]]

local options = require 'vi_hudoptions.options'
local config = require 'vi_gunsonback.config'
if not config.enabled then return end

local BAG = 'viBack'                -- { w = { weapon hashes }, h = the one in the hand }
local SPINE3 = 24817                -- SKEL_Spine3: the back
local R_HAND = 57005                -- SKEL_R_Hand: a gun on its way to or from the back
local MAX = math.max(0, math.floor(tonumber(config.max) or 2))
local RECHECK_MS = (tonumber(config.recheckSeconds) or 0.5) * 1000
local DRAW_DISTANCE = tonumber(config.drawDistance) or 50.0
-- ox_inventory's list is read again whenever it changes; this is only a
-- safety net for a change it didn't announce.
local OX_REREAD_MS = 5000

-- Hashes come back signed from some natives and unsigned from others, so
-- every comparison is on the unsigned value.
local function u32(h)
    h = math.tointeger(h)
    return h and h & 0xFFFFFFFF or 0
end

local UNARMED = u32(GetHashKey('WEAPON_UNARMED'))

-- Single player's Slingable: the weapon groups that go on the back.
local SLINGABLE = {}
for _, group in ipairs({ 'GROUP_RIFLE', 'GROUP_MG', 'GROUP_SHOTGUN', 'GROUP_SNIPER', 'GROUP_HEAVY' }) do
    SLINGABLE[u32(GetHashKey(group))] = true
end

local function slingable(hash)
    return SLINGABLE[u32(GetWeapontypeGroup(hash))] == true
end

-- Without ox_inventory: the game's own guns in those groups, looked for on the
-- ped. Single player goes through every weapon the game has in hash order, so
-- these are put in that order once.
local VANILLA = {
    'WEAPON_ADVANCEDRIFLE', 'WEAPON_ASSAULTRIFLE', 'WEAPON_ASSAULTRIFLE_MK2', 'WEAPON_BATTLERIFLE',
    'WEAPON_BULLPUPRIFLE', 'WEAPON_BULLPUPRIFLE_MK2', 'WEAPON_CARBINERIFLE', 'WEAPON_CARBINERIFLE_MK2',
    'WEAPON_COMPACTRIFLE', 'WEAPON_HEAVYRIFLE', 'WEAPON_MILITARYRIFLE', 'WEAPON_SPECIALCARBINE',
    'WEAPON_SPECIALCARBINE_MK2', 'WEAPON_STRICKLER', 'WEAPON_TACTICALRIFLE',
    'WEAPON_COMBATMG', 'WEAPON_COMBATMG_MK2', 'WEAPON_GUSENBERG', 'WEAPON_MG', 'WEAPON_RAYCARBINE',
    'WEAPON_ASSAULTSHOTGUN', 'WEAPON_AUTOSHOTGUN', 'WEAPON_BULLPUPSHOTGUN', 'WEAPON_COMBATSHOTGUN',
    'WEAPON_DBSHOTGUN', 'WEAPON_HEAVYSHOTGUN', 'WEAPON_PUMPSHOTGUN', 'WEAPON_PUMPSHOTGUN_MK2',
    'WEAPON_SAWNOFFSHOTGUN',
    'WEAPON_HEAVYSNIPER', 'WEAPON_HEAVYSNIPER_MK2', 'WEAPON_MARKSMANRIFLE', 'WEAPON_MARKSMANRIFLE_MK2',
    'WEAPON_MUSKET', 'WEAPON_PRECISIONRIFLE', 'WEAPON_SNIPERRIFLE',
    'WEAPON_COMPACTLAUNCHER', 'WEAPON_EMPLAUNCHER', 'WEAPON_FIREWORK', 'WEAPON_GRENADELAUNCHER',
    'WEAPON_GRENADELAUNCHER_SMOKE', 'WEAPON_HOMINGLAUNCHER', 'WEAPON_MINIGUN', 'WEAPON_RAILGUN',
    'WEAPON_RAILGUNXM3', 'WEAPON_RAYMINIGUN', 'WEAPON_RPG', 'WEAPON_SNOWLAUNCHER',
}
for i, name in ipairs(VANILLA) do VANILLA[i] = GetHashKey(name) end
table.sort(VANILLA, function(a, b) return u32(a) < u32(b) end)

-- ---------------------------------------------------------------------------
-- What the local player carries
-- ---------------------------------------------------------------------------

local oxUp = GetResourceState('ox_inventory') == 'started'
local oxList, oxReadAt, oxStale = {}, 0, true

local function readOx()
    local ok, items = pcall(function() return exports.ox_inventory:GetPlayerItems() end)
    if not ok or type(items) ~= 'table' then return end     -- keep the last list
    local seen, list = {}, {}
    for _, item in pairs(items) do
        local name = type(item) == 'table' and item.name
        if type(name) == 'string' and name:upper():sub(1, 7) == 'WEAPON_' then
            local hash = GetHashKey(name)
            if not seen[u32(hash)] and IsWeaponValid(hash) then
                seen[u32(hash)] = true
                list[#list + 1] = hash
            end
        end
    end
    table.sort(list, function(a, b) return u32(a) < u32(b) end)
    oxList = list
end

local function carried(ped)
    if oxUp then
        local now = GetGameTimer()
        if oxStale or now - oxReadAt > OX_REREAD_MS then
            readOx()
            oxReadAt, oxStale = now, false
        end
        return oxList
    end
    local list = {}
    for i = 1, #VANILLA do
        if HasPedGotWeapon(ped, VANILLA[i], false) then list[#list + 1] = VANILLA[i] end
    end
    return list
end

-- Single player's Wanted: in carried order, the first MAX slingable guns
-- other than the one in hand. `any` says whether there is a slingable gun at
-- all, in hand or not, which decides how closely the loop has to watch.
local function wanted(ped, current)
    local list, any = {}, false
    for _, hash in ipairs(carried(ped)) do
        if slingable(hash) then
            any = true
            if #list < MAX and u32(hash) ~= current and u32(hash) ~= UNARMED then
                list[#list + 1] = hash
            end
        end
    end
    return list, any
end

-- ---------------------------------------------------------------------------
-- Rigs: the props on one ped, made the way single player makes them
-- ---------------------------------------------------------------------------

local function newRig() return { ped = 0, props = {} } end

local function clearRig(rig)
    for i = 1, #rig.props do
        local obj = rig.props[i]
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    rig.props = {}
    rig.sig = nil
end

-- Where along its model a gun is gripped (single player's AnchorOffset).
local function anchorOffset(hash)
    local model = GetWeapontypeModel(hash)
    if not model or model == 0 then return 0.0 end
    local min, max = GetModelDimensions(model)
    return min.x + (max.x - min.x) * config.anchorFrac
end

local function attach(rig, ped, hash, slot, inHand)
    if not HasWeaponAssetLoaded(hash) then
        -- single player asks for it and tries the whole set again next time
        RequestWeaponAsset(hash, 31, 0)
        rig.retry = true
        return
    end
    local pos = GetEntityCoords(ped)
    -- not networked (single player's last three arguments): each client hangs its own
    local obj = CreateWeaponObject(hash, 1, pos.x, pos.y, pos.z, true, 1.0, 0, false, false)
    if not obj or obj == 0 then return end
    local bone = GetPedBoneIndex(ped, inHand and R_HAND or SPINE3)
    if bone == -1 then
        DeleteEntity(obj)
        return
    end
    SetEntityCollision(obj, false, false)
    if inHand then
        AttachEntityToEntity(obj, ped, bone, config.handGripX - anchorOffset(hash), 0.0, 0.0,
            0.0, 0.0, 0.0, false, false, false, true, 2, true)
    else
        local p = slot % 2 == 0 and config.primary or config.secondary
        AttachEntityToEntity(obj, ped, bone, p.x, p.y, p.z, p.pitch, p.yaw, p.roll,
            false, false, false, true, 2, true)
    end
    rig.props[#rig.props + 1] = obj
end

local function signature(entry)
    if not entry then return nil end
    local parts = {}
    for i = 1, #entry.w do parts[i] = u32(entry.w[i]) end
    return table.concat(parts, ',') .. '|' .. u32(entry.h)
end

-- Hang `entry` on `ped`. As in single player, any change takes every prop
-- down and puts the new set up.
local function apply(rig, ped, entry)
    local sig = signature(entry)
    if rig.ped == ped and rig.sig == sig and not rig.retry then return end
    clearRig(rig)
    rig.ped, rig.sig, rig.retry = ped, sig, false
    if not entry then return end
    local hand = entry.h and u32(entry.h) or UNARMED
    for i = 1, #entry.w do
        local hash = entry.w[i]
        attach(rig, ped, hash, i - 1, hand ~= UNARMED and u32(hash) == hand)
    end
end

-- Single player takes them down dead or in a vehicle. An invisible ped (an
-- admin's noclip, a spawn screen) would leave guns hanging in the air, so
-- that counts too.
local function canShow(ped)
    return ped and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped)
        and not IsPedInAnyVehicle(ped, false) and IsEntityVisible(ped)
end

-- ---------------------------------------------------------------------------
-- The local player (single player's Update)
-- ---------------------------------------------------------------------------

local me = {
    rig = newRig(),
    dirty = true,
    nextCheck = 0,
    current = nil,
    any = false,
    published = nil,    -- signature of what the state bag holds
    drawInHand = nil,   -- from vi_drawanims
    holding = nil,      -- from vi_drawanims: the gun in sight, when not the ped's
}

local function publish(entry)
    local sig = signature(entry)
    if sig == me.published then return end
    me.published = sig
    LocalPlayer.state:set(BAG, entry, true)
end

local function hideSelf()
    clearRig(me.rig)
    me.rig.ped = 0
    publish(nil)
    me.dirty = true
end

local function contains(list, hash)
    for i = 1, #list do
        if u32(list[i]) == u32(hash) then return true end
    end
    return false
end

-- Returns how long to wait before the next look.
local function updateSelf()
    local ped = cache.ped
    if not canShow(ped) then
        if me.rig.sig or me.published then hideSelf() end
        return 250
    end
    if ped ~= me.rig.ped then me.dirty = true end      -- respawned or a new model

    local current = me.holding and u32(me.holding) or nil
    if not current then
        local _, weapon = GetCurrentPedWeapon(ped, true)
        current = u32(weapon)
        if current == 0 then current = UNARMED end
    end

    local now = GetGameTimer()
    if not me.dirty and not me.rig.retry and now < me.nextCheck and current == me.current then
        return me.any and 0 or 250
    end
    me.dirty = false
    me.nextCheck = now + RECHECK_MS
    me.current = current

    local list, any = wanted(ped, current)
    me.any = any
    local entry = nil
    if #list > 0 then
        local hand = me.drawInHand and contains(list, me.drawInHand) and me.drawInHand or nil
        entry = { w = list, h = hand }
    end
    apply(me.rig, ped, entry)
    publish(entry)
    return any and 0 or 250
end

-- ---------------------------------------------------------------------------
-- Other players: their state bag, hung locally
-- ---------------------------------------------------------------------------

local rigs = {}         -- [server id] = rig

-- A state bag is whatever that client chose to send: keep only real guns of
-- the slung kind, and no more than this server shows.
local function sanitize(value)
    if type(value) ~= 'table' or type(value.w) ~= 'table' then return nil end
    local w = {}
    for i = 1, math.min(#value.w, MAX) do
        local hash = math.tointeger(value.w[i])
        if not hash or not IsWeaponValid(hash) or not slingable(hash) then return nil end
        w[i] = hash
    end
    if #w == 0 then return nil end
    local hand = math.tointeger(value.h)
    if hand and not contains(w, hand) then hand = nil end
    return { w = w, h = hand }
end

local function showPlayer(pid, value)
    local sid = GetPlayerServerId(pid)
    local ped = GetPlayerPed(pid)
    local entry = sanitize(value)
    local rig = rigs[sid]
    if not entry or not canShow(ped) then
        if rig then
            clearRig(rig)
            rigs[sid] = nil
        end
        return
    end
    if not rig then
        rig = newRig()
        rigs[sid] = rig
    end
    apply(rig, ped, entry)
end

local function near(ped)
    return ped ~= 0 and #(GetEntityCoords(ped) - GetEntityCoords(cache.ped)) <= DRAW_DISTANCE
end

-- A change shows at once (a gun going to the hand mid-animation can't wait
-- for the loop below).
AddStateBagChangeHandler(BAG, nil, function(bagName, _, value)
    local pid = GetPlayerFromStateBagName(bagName)
    if not pid or pid == 0 or pid == cache.playerId then return end
    if not near(GetPlayerPed(pid)) then return end
    showPlayer(pid, value)
end)

-- Players coming into range, going out of it, dying, getting into vehicles,
-- respawning: looked at four times a second while anyone near has guns
-- hanging, once a second otherwise.
CreateThread(function()
    while true do
        local seen = {}
        for _, pid in ipairs(GetActivePlayers()) do
            if pid ~= cache.playerId then
                local ped = GetPlayerPed(pid)
                if near(ped) then
                    local sid = GetPlayerServerId(pid)
                    seen[sid] = true
                    showPlayer(pid, Player(sid).state[BAG])
                end
            end
        end
        for sid, rig in pairs(rigs) do
            if not seen[sid] then
                clearRig(rig)
                rigs[sid] = nil
            end
        end
        Wait(next(rigs) and 250 or 1000)
    end
end)

-- ---------------------------------------------------------------------------
-- Events and the row
-- ---------------------------------------------------------------------------

AddEventHandler('vi_drawanims:hand', function(drawInHand, holding)
    drawInHand, holding = math.tointeger(drawInHand), math.tointeger(holding)
    me.drawInHand = drawInHand and drawInHand ~= 0 and drawInHand or nil
    me.holding = holding and holding ~= 0 and holding or nil
    me.dirty = true
end)

AddEventHandler('ox_inventory:updateInventory', function()
    oxStale = true
    me.dirty = true
end)

AddEventHandler('ox_inventory:currentWeapon', function()
    me.dirty = true
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= 'ox_inventory' then return end
    oxUp, oxStale = true, true
    me.dirty = true
end)

AddEventHandler('onResourceStop', function(res)
    if res == 'ox_inventory' then
        oxUp = false
        me.dirty = true
    elseif res == GetCurrentResourceName() then
        clearRig(me.rig)
        for _, rig in pairs(rigs) do clearRig(rig) end
        LocalPlayer.state:set(BAG, nil, true)
    end
end)

options.add({
    id = 'gunsonback',
    label = 'GUNS ON BACK',
    default = config.default ~= false,
    desc = "Guns you're not holding show on your back.",
    onChange = function(on)
        if on then me.dirty = true else hideSelf() end
    end,
})

CreateThread(function()
    -- whatever a previous run of this resource left in the state bag
    LocalPlayer.state:set(BAG, nil, true)
    me.published = nil
    while true do
        local wait = 500
        if options.get('gunsonback') then wait = updateSelf() end
        Wait(wait)
    end
end)
