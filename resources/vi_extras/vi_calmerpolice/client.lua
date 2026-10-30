--[[ ===========================================================================
     vi_calmerpolice — client
     ---------------------------------------------------------------------------
     CALMER POLICE, ported from the fork's ViExtras (single player's
     [Switches] CalmerPolice, Wanted\CalmerPolice.cs). Players found GTA's
     police on top of them in seconds, and seeming to know where they were
     when none of them could see them. Toned down:

       * They arrive slower and from further off: the game's dispatch waits
         spawnDelayMultiplier (2) times as long between sending police units,
         and places them around spawnDistance (300) metres away.
       * Once none of them can see you (the stars grey out), the search stays
         where they last saw you. The game moves it to wherever you are every
         so often, which is how they "just know"; it is put back each second.
       * They're easier to lose: hidden for escapeSeconds (10), plus
         escapeSecondsPerStar (5) for each star, and the stars go (25 s at 3).

     All of it is this client's own: on FiveM each player's wanted level, and
     the police the game sends for it, are run by that player's game.

     Not while a resource that runs the police itself is started
     (config.policeResources: fenix-police), or while a script has the mission
     flag up (single player: not on a story mission). The game's own values
     are put back then, when the row is switched off, and when this stops.

     Public API: none. The CALMER POLICE row of HUD OPTIONS switches it per
     player.
     ========================================================================= ]]

local options = require 'vi_hudoptions.options'
local config = require 'vi_calmerpolice.config'
if not config.enabled then return end

-- Single player's numbers.
local CHECK_MS = 1000           -- once a second
local LATE_MS = 5000            -- the game's own escape timer should have let you go by then
local SETTLE_MS = 3000          -- after a loading screen or a switch, before anything is touched
local PIN_SLACK = 5.0           -- metres the search may drift from where they saw you

-- The dispatch services a wanted level sends: police cars, helicopters, SWAT,
-- bikes, backup, roadblocks, the waiting cars, SWAT helicopters, boats and the
-- army. Fire, ambulance, gangs and bikers are not the police.
local POLICE_SERVICES = { 1, 2, 4, 6, 7, 8, 9, 10, 12, 13, 14 }

local delayMul = math.max(1.0, tonumber(config.spawnDelayMultiplier) or 2.0)
local spawnDistance = tonumber(config.spawnDistance) or 300.0
local escapeMs = math.max(0, math.floor(tonumber(config.escapeSeconds) or 10)) * 1000
local escapePerStarMs = math.max(0, math.floor(tonumber(config.escapeSecondsPerStar) or 5)) * 1000

local applied = false
local escapeFor = -1            -- the star count the hidden escape time was last set for
local escapeSet = false         -- a hidden escape time of ours is in the game
local hiddenSince = -1          -- game timer when the stars greyed, -1 while they can see you
local seen = nil                -- where they last saw you, for this time out of sight
local readySince = nil
local pinWorks, pinMisses, pinOff = false, 0, false
local lastError = nil

local function report(err)
    err = tostring(err)
    if err == lastError then return end
    lastError = err
    print(('^1[vi_extras]^7 calmerpolice: %s'):format(err))
end

-- Not on a loading screen or mid character switch, and settled a moment.
local function ready()
    local ok = not GetIsLoadingScreenActive() and DoesEntityExist(cache.ped) and not IsPlayerSwitchInProgress()
    if not ok then
        readySince = nil
        return false
    end
    local now = GetGameTimer()
    readySince = readySince or now
    return now - readySince >= SETTLE_MS
end

local function policeTaken()
    local list = config.policeResources
    if type(list) ~= 'table' then return false end
    for i = 1, #list do
        if GetResourceState(list[i]) == 'started' then return true end
    end
    return false
end

local function busted()
    return IsPlayerBeingArrested(cache.playerId, true) or IsEntityDead(cache.ped)
end

-- SET_PLAYER_WANTED_CENTRE_POSITION takes the position by pointer, and FiveM's
-- Lua wrapper only offers an empty output vector there. The position goes in
-- as the game lays out a vector (three floats, each in an 8-byte slot), and is
-- read back: if it didn't land twice running, the search is left to the game.
local function pinSearch(player, at)
    local ok, err = pcall(Citizen.InvokeNative, 0x520E541A97A13354, player,
        string.pack('<fxxxxfxxxxfxxxx', at.x, at.y, at.z), false, false)
    if ok and #(GetPlayerWantedCentrePosition(player) - at) <= 1.0 then
        pinWorks, pinMisses = true, 0
        return
    end
    pinMisses = pinMisses + 1
    if not pinWorks and pinMisses >= 2 then
        pinOff = true
        report('the search area could not be moved (' .. tostring(ok and 'it did not take' or err)
            .. '); it follows the game from now on')
    end
end

local function apply(player)
    if not applied then
        applied = true
        escapeFor, escapeSet = -1, false
        for i = 1, #POLICE_SERVICES do
            SetDispatchTimeBetweenSpawnAttemptsMultiplier(POLICE_SERVICES[i], delayMul)
        end
        if spawnDistance > 0.0 then SetDispatchIdealSpawnDistance(spawnDistance + 0.0) end
    end
    -- The hidden-escape time is per star count; set again whenever the stars change.
    local level = GetPlayerWantedLevel(player)
    if level ~= escapeFor and level > 0 then
        escapeFor, escapeSet = level, true
        SetWantedLevelHiddenEvasionTime(player, level, escapeMs + escapePerStarMs * level)
    end
end

local function reset()
    hiddenSince, seen = -1, nil
    if not applied then return end
    applied = false
    escapeFor = -1
    for i = 1, #POLICE_SERVICES do
        SetDispatchTimeBetweenSpawnAttemptsMultiplier(POLICE_SERVICES[i], 1.0)
    end
    ResetDispatchIdealSpawnDistance()
    -- Only when one of ours is in: a police resource that has just started
    -- sets escape times of its own, and this would wipe them.
    if escapeSet then
        escapeSet = false
        Citizen.InvokeNative(0x823EC8E82BA45986, cache.playerId)   -- RESET_WANTED_LEVEL_HIDDEN_ESCAPE_TIME
    end
end

local function tick()
    if not ready() then return end
    if not options.get('calmerpolice') or GetMissionFlag() or policeTaken() then
        reset()
        return
    end
    local player = cache.playerId
    apply(player)

    local level = GetPlayerWantedLevel(player)
    if level > 0 and ArePlayerStarsGreyedOut(player) then
        local now = GetGameTimer()
        if hiddenSince < 0 then
            hiddenSince = now
            -- The game centres the search on where it last saw you, and it is
            -- still there the moment they lose sight of you.
            local centre = GetPlayerWantedCentrePosition(player)
            seen = (centre.x ~= 0.0 or centre.y ~= 0.0 or centre.z ~= 0.0) and centre or nil
        end

        -- Where they last saw you, not where you are now: put back only when
        -- the game has moved it, so the search isn't restarted every second.
        if seen and not pinOff and #(GetPlayerWantedCentrePosition(player) - seen) > PIN_SLACK then
            pinSearch(player, seen)
        end

        -- The game's own escape timer should have let you go by now; if
        -- anything held it back, the stars go here, a few seconds late.
        if now - hiddenSince > escapeMs + escapePerStarMs * level + LATE_MS and not busted() then
            SetPlayerWantedLevel(player, 0, false)
            SetPlayerWantedLevelNow(player, false)
            hiddenSince, seen = -1, nil
        end
    else
        hiddenSince, seen = -1, nil
    end
end

options.add({
    id = 'calmerpolice',
    label = 'CALMER POLICE',
    default = config.default ~= false,
    desc = 'The police arrive slower, search where they last saw you, and are easier to lose.',
    onChange = function(on)
        if not on then reset() end      -- on: the next check puts it in
    end,
})

CreateThread(function()
    while true do
        local ok, err = pcall(tick)
        if not ok then report(err) end
        Wait(CHECK_MS)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then reset() end
end)
