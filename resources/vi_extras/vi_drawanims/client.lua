--[[ ===========================================================================
     vi_drawanims — client
     ---------------------------------------------------------------------------
     DRAW ANIMATIONS, ported from single player (GTA6Hud's equip steps). Draw
     or put away a pistol and your hand goes to your right hip; a long gun
     (rifle, machine gun, shotgun, sniper, launcher) and it goes over your
     shoulder, with the upper-body version of each clip while you're walking
     or running. Going from one gun to another puts the first away, then draws
     the second. Nothing plays when neither gun is a pistol or a long gun, in a
     vehicle, ragdolling, swimming, falling, dead, in first person or while a
     mission is flagged; any of those mid-way, or the row switched off,
     finishes the switch at once. Shooting, aiming and the weapon wheel wait
     until it's done.

     The clips are single player's own (its vihudanims pack): the four
     mech_inventory@equip@fallback@base@unarmed@* dictionaries in the
     resource's stream/vi_drawanims/. If they aren't streamed, nothing plays
     and the switch happens after 1.5 s, as in single player.

     With ox_inventory, the gun is ox_inventory's: it takes the old gun and
     gives the new one at once, so the clips are played around that. The new
     gun is kept out of sight until the clip reaches for it, and a long gun
     being put away stays in the hand (vi_gunsonback) until it reaches the
     back. Without ox_inventory, the ped's weapon is switched here, at the
     point in the clip single player switches it.

     Public API: none. The DRAW ANIMATIONS row of HUD OPTIONS switches it per
     player. Fires the local event vi_drawanims:hand(drawInHand, holding) for
     vi_gunsonback: the long gun to hang in the right hand (nil for none), and
     the gun in sight when it isn't the ped's (nil when it is).
     ========================================================================= ]]

local options = require 'vi_hudoptions.options'
local config = require 'vi_drawanims.config'
if not config.enabled then return end

local function u32(h)
    h = math.tointeger(h)
    return h and h & 0xFFFFFFFF or 0
end

local UNARMED = u32(GetHashKey('WEAPON_UNARMED'))
local GROUP_PISTOL = u32(GetHashKey('GROUP_PISTOL'))
local LONG = {}
for _, group in ipairs({ 'GROUP_HEAVY', 'GROUP_SNIPER', 'GROUP_SHOTGUN', 'GROUP_RIFLE', 'GROUP_MG' }) do
    LONG[u32(GetHashKey(group))] = true
end

-- How long the clips may take to load before the switch just happens.
local LOAD_TIMEOUT_MS = 1500
-- Single player's TASK_PLAY_ANIM flags: upper body only, the player keeps moving.
local ANIM_FLAG = 48
-- Attack, aim and the weapon wheel, held off while a switch plays.
local BLOCKED = { 24, 25, 37 }

-- Single player's four steps (HolsterPistol, DrawPistol, HolsterLong,
-- DrawLong): the clip standing still, or its upper-body "gesture" version on
-- the move. switchAt is where in the clip (0 to 1) the gun changes hands,
-- blendOutAt where the clip lets go.
local RHIP = 'mech_inventory@equip@fallback@base@unarmed@rhip'
local BACK = 'mech_inventory@equip@fallback@base@unarmed@back@longarms'
local STEPS = {
    pistol = {
        holster   = { still = { RHIP, 0.19, 0.40 }, moving = { RHIP .. '_gesture', 0.26, 0.30 } },
        unholster = { still = { RHIP, 0.14, 0.46 }, moving = { RHIP .. '_gesture', 0.15, 0.24 } },
    },
    long = {
        holster   = { still = { BACK, 0.32, 0.72 }, moving = { BACK .. '_gesture', 0.18, 0.30 } },
        unholster = { still = { BACK, 0.16, 0.75 }, moving = { BACK .. '_gesture', 0.11, 0.33 } },
    },
}

-- Single player's KindOf.
local function kindOf(hash)
    hash = u32(hash)
    if hash == UNARMED or hash == 0 then return 'unarmed' end
    local group = u32(GetWeapontypeGroup(hash))
    if group == GROUP_PISTOL then return 'pistol' end
    if LONG[group] then return 'long' end
    return 'other'
end

local function animated(kind) return kind == 'pistol' or kind == 'long' end

local function makeStep(kind, clip, moving, switchTo, from)
    local s = STEPS[kind][clip][moving and 'moving' or 'still']
    RequestAnimDict(s[1])
    return { dict = s[1], clip = clip, switchAt = s[2], blendOutAt = s[3], switchTo = switchTo, from = from }
end

-- Single player's EquipAnimationsAllowed.
local function allowed(ped)
    return ped and DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) and not IsPedRagdoll(ped)
        and not IsPedSwimming(ped) and not IsPedFalling(ped) and not IsEntityDead(ped)
        and not GetMissionFlag() and GetFollowPedCamViewMode() ~= 4
end

local function currentWeapon(ped)
    local _, weapon = GetCurrentPedWeapon(ped, true)
    weapon = u32(weapon)
    return weapon == 0 and UNARMED or weapon
end

-- ---------------------------------------------------------------------------
-- The switch in progress
-- ---------------------------------------------------------------------------

local oxUp = GetResourceState('ox_inventory') == 'started'
local queue = {}            -- steps still to play
local step = nil            -- the step playing
local target = UNARMED      -- the gun the whole switch ends on
local requested = 0         -- GetGameTimer() the steps were asked for
local switched, started = false, 0
local moving = false        -- chosen once per switch, as single player does
local hidden = false        -- ox_inventory: the new gun is in the hand, kept out of sight
local drawInHand = nil      -- the long gun vi_gunsonback hangs in the right hand
local oxHeld = UNARMED      -- ox_inventory: the gun it last gave
local lastSeen = nil        -- without ox_inventory: the gun last seen in the hand
local running = false

local function busy() return step ~= nil or #queue > 0 end

local sentHand, sentHidden = nil, false
local function tell()
    if drawInHand == sentHand and hidden == sentHidden then return end
    sentHand, sentHidden = drawInHand, hidden
    TriggerEvent('vi_drawanims:hand', drawInHand, hidden and UNARMED or nil)
end

local function setHand(hash)
    drawInHand = hash
    tell()
end

local function show(ped)
    if not hidden then return end
    hidden = false
    if DoesEntityExist(ped) then SetPedCurrentWeaponVisible(ped, true, false, false, false) end
    tell()
end

-- The gun changes hands (single player's Weapons.Select). Without
-- ox_inventory that is the ped's weapon; with it, ox_inventory has already
-- made the switch and only the new gun coming into sight is left.
local function give(ped, hash)
    if oxUp then
        if u32(hash) ~= UNARMED then show(ped) end
        return
    end
    lastSeen = u32(hash)
    SetCurrentPedWeapon(ped, hash, true)
end

-- Single player's FinishEquip: stop where it is and end on the target gun.
local function finish(ped)
    if step and ped and DoesEntityExist(ped) then StopAnimTask(ped, step.dict, step.clip, 4.0) end
    local was = busy()
    step, queue = nil, {}
    drawInHand = nil
    if was and ped and DoesEntityExist(ped) and not IsEntityDead(ped) then give(ped, target) end
    show(ped)
    tell()
end

-- Single player's UpdateEquip, once a frame while a switch plays.
local function update(ped)
    if not allowed(ped) then
        finish(ped)
        return
    end
    for i = 1, #BLOCKED do DisableControlAction(0, BLOCKED[i], true) end
    if hidden then SetPedCurrentWeaponVisible(ped, false, false, false, false) end

    local now = GetGameTimer()
    if not step then
        local nextStep = queue[1]
        if not nextStep.dict then
            -- a gun with no clip of its own (an SMG, a knife): straight into the hand
            table.remove(queue, 1)
            give(ped, nextStep.switchTo)
            return
        end
        if not HasAnimDictLoaded(nextStep.dict) then
            if now - requested > LOAD_TIMEOUT_MS then finish(ped) end
            return
        end
        step = table.remove(queue, 1)
        switched, started = false, now
        TaskPlayAnim(ped, step.dict, step.clip, 4.0, -4.0, -1, ANIM_FLAG, 0.0, false, false, false)
        if step.clip == 'unholster' and kindOf(step.switchTo) == 'long' then
            setHand(step.switchTo)
        elseif oxUp and step.clip == 'holster' and kindOf(step.from) == 'long' then
            -- ox_inventory has already taken it: the hand holds it from the start
            setHand(step.from)
        end
        return
    end

    local duration = GetAnimDuration(step.dict, step.clip)
    local t
    if IsEntityPlayingAnim(ped, step.dict, step.clip, 3) then
        t = GetEntityAnimCurrentTime(ped, step.dict, step.clip)
    elseif duration > 0 then
        t = (now - started) / (duration * 1000)
    else
        t = 1.0
    end
    if not switched and t >= step.switchAt then
        local prev = oxUp and step.from or currentWeapon(ped)
        give(ped, step.switchTo)
        switched = true
        -- a long gun put away goes to the back in the hand; anything else is done
        setHand((step.clip == 'holster' and kindOf(prev) == 'long') and prev or nil)
    end
    if switched and (t >= step.blendOutAt or now - started > duration * 1000 + 500) then
        StopAnimTask(ped, step.dict, step.clip, 4.0)
        step = nil
        setHand(nil)
    end
end

local function run()
    if running or not busy() then return end
    running = true
    CreateThread(function()
        while busy() do
            update(cache.ped)
            Wait(0)
        end
        running = false
    end)
end

local function queueDraw(ped, to)
    local kind = kindOf(to)
    if animated(kind) then
        queue[#queue + 1] = makeStep(kind, 'unholster', moving, to)
    elseif kind == 'other' then
        queue[#queue + 1] = { switchTo = to }
    end
    target = to
    if oxUp and kind ~= 'unarmed' and busy() then
        -- ox_inventory has put it in the hand already: out of sight until its step
        hidden = true
        SetPedCurrentWeaponVisible(ped, false, false, false, false)
        tell()
    end
end

-- Single player's RequestEquip: from the gun in the hand to `to`.
local function request(ped, from, to)
    if busy() then finish(ped) end
    if u32(to) == u32(from) then return end
    local kFrom, kTo = kindOf(from), kindOf(to)
    if not options.get('drawanims') or not allowed(ped) or not (animated(kFrom) or animated(kTo)) then
        give(ped, to)
        return
    end
    moving = IsPedWalking(ped) or IsPedRunning(ped) or IsPedSprinting(ped)
    if animated(kFrom) then
        queue[#queue + 1] = makeStep(kFrom, 'holster', moving, UNARMED, from)
    elseif kFrom == 'other' then
        give(ped, UNARMED)
    end
    queueDraw(ped, to)
    requested = GetGameTimer()
    run()
end

-- ---------------------------------------------------------------------------
-- What starts a switch
-- ---------------------------------------------------------------------------

-- ox_inventory: it says every time the gun in the hand changes, and again
-- whenever that gun's ammo or durability does.
AddEventHandler('ox_inventory:currentWeapon', function(item)
    local to = type(item) == 'table' and u32(item.hash) or UNARMED
    if to == 0 then to = UNARMED end
    if to == u32(oxHeld) then return end
    local ped = cache.ped
    -- the gun in sight, not the one waiting to be drawn
    local from = hidden and UNARMED or u32(oxHeld)
    oxHeld = to
    if to ~= UNARMED and from == UNARMED and busy() and u32(target) == UNARMED then
        -- ox_inventory switches in two goes, the old gun taken and the new
        -- one given a server round trip later: the new one is drawn once the
        -- old one is away, as one switch
        queueDraw(ped, to)
        requested = GetGameTimer()
        run()
        return
    end
    request(ped, from, to)
end)

-- Without ox_inventory: the game's own weapon wheel, or a script, switched the
-- gun. Put the old one back and switch with the clips instead, as single
-- player's own wheel does.
local function watch(ped)
    if not ped or not DoesEntityExist(ped) then return end
    local now = currentWeapon(ped)
    if lastSeen == nil or now == lastSeen then
        lastSeen = now
        return
    end
    local from = lastSeen
    lastSeen = now
    if allowed(ped) and (animated(kindOf(from)) or animated(kindOf(now))) and HasPedGotWeapon(ped, from, false) then
        give(ped, from)
        request(ped, from, now)
    end
end

CreateThread(function()
    while true do
        local wait = 500
        if not oxUp and options.get('drawanims') then
            wait = 0
            watch(cache.ped)
        else
            lastSeen = nil
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= 'ox_inventory' then return end
    finish(cache.ped)
    oxUp, oxHeld = true, UNARMED
end)

AddEventHandler('onResourceStop', function(res)
    if res == 'ox_inventory' then
        finish(cache.ped)
        oxUp = false
    elseif res == GetCurrentResourceName() then
        finish(cache.ped)
    end
end)

if oxUp and cache.ped then oxHeld = currentWeapon(cache.ped) end

options.add({
    id = 'drawanims',
    label = 'DRAW ANIMATIONS',
    default = config.default ~= false,
    desc = 'Draw and holster animations when you switch guns.',
    onChange = function(on)
        if not on then finish(cache.ped) end
    end,
})
