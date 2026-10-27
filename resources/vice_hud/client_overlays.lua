--[[
    vice_hud — overlays:  aim crosshair, kill mark, race lap timer, world-action
    prompt, the lockpick check, and the interact menu with its pad input.

    Split out of client.lua on 2026-08-28 for the reason described at the top of
    client_vitals.lua (Lua's 200-top-level-locals-per-chunk limit). Every line
    below is moved, not rewritten.

    This group is the cleanest seam in the whole file: it declares ONE top-level
    local, it needs exactly one name from client.lua (`ui`, duplicated below),
    and NOTHING in the rest of the resource reaches into it. Everything here is
    driven from outside through exports and commands, which is why it can sit in
    its own chunk with no shared state at all.

    Note the native-HUD suppressor that used to sit just above the crosshair
    stayed behind in client.lua: it owns the minimap scaleform, which belongs
    with the map code, not here.
]]

-- Its own copy of the NUI sender, exactly as client_skills.lua carries one:
-- every file here is a separate Lua chunk, so client.lua's `ui` is not in
-- scope, and four lines duplicated beats a global for something this small.
local function ui(action, data)
    data = data or {}
    data.action = action
    SendNUIMessage(data)
end

-- =============================================================================
-- Aim crosshair
-- =============================================================================
-- Two variants: a plain ring+dot while driving (drive-by shooting), a
-- three-tick reticle on foot that widens on each shot. See Config.Crosshair
-- for the reticleComponent caveat.
--
-- ui() is only called on an actual STATE CHANGE (active flips, or the mode
-- flips between foot/vehicle) even though this runs on Wait(0) -- streaming a
-- value every frame would spam SendNUIMessage for no reason, since the
-- widen/settle motion itself lives entirely in CSS (see style.css's
-- --spread). Only the two native calls that must run every frame regardless
-- (HideHudComponentThisFrame, and reading whether a shot fired this frame)
-- are actually in the tight loop.
if Config.Crosshair.enable then
    local crossActive, crossMode = false, 'foot'
    local crossWasShooting = false
    local SNIPER_GROUP = `GROUP_SNIPER`

    CreateThread(function()
        while true do
            Wait(0)
            local ped = cache.ped or PlayerPedId()
            local playerId = PlayerId()
            -- IS_PED_ARMED's flags: 1 melee, 2 thrown, 4 guns. This asked for 2,
            -- so a gun never brought the crosshair up and the game's own reticle
            -- stayed (found putting it side by side with the single-player
            -- port, which asks for 4).
            local armedGun = IsPedArmed(ped, Config.Crosshair.armedWith or 4)
            -- A sniper rifle's scope IS the game's reticle, so hiding it for
            -- our crosshair left nothing to aim through. Those keep the game's.
            local sniper = armedGun and GetWeapontypeGroup(GetSelectedPedWeapon(ped)) == SNIPER_GROUP
            -- Targetting covers Assisted Aim / Traditional lock-on, which is
            -- never "free aiming": without it the crosshair only came up on
            -- the first shot.
            local aiming = armedGun and not sniper
                and (IsPlayerFreeAiming(playerId) or IsPlayerTargettingAnything(playerId) or IsPedShooting(ped))
            local mode = IsPedInAnyVehicle(ped, false) and 'vehicle' or 'foot'

            if aiming then
                HideHudComponentThisFrame(Config.Crosshair.reticleComponent)
                if not crossActive or mode ~= crossMode then
                    crossActive, crossMode = true, mode
                    ui('crosshair', { active = true, mode = mode })
                end
            elseif crossActive then
                crossActive = false
                ui('crosshair', { active = false })
            end

            -- Foot reticle only — the vehicle ring doesn't spread in the
            -- reference, so there's nothing to fire an event for there.
            local shooting = aiming and mode == 'foot' and IsPedShooting(ped)
            if shooting and not crossWasShooting then
                ui('crossFire', {})
            end
            crossWasShooting = shooting
        end
    end)
end

-- =============================================================================
-- Kill mark — the coloured cross that flashes on a kill
-- =============================================================================
-- One rule, written down so it can be retuned rather than re-guessed:
--
--   headshot AND we only ever hit them once   -> red    (clean one-shot headshot)
--   hit them more than once before they died  -> yellow (sloppy, took work)
--   anything else (a clean single non-head hit that still killed) -> white
--
-- "Headshot" asks GET_PED_LAST_DAMAGE_BONE and compares it to SKEL_Head
-- directly, NOT the damage event's own payload — see client_skills.lua's own
-- note on why CEventNetworkEntityDamage's argument layout isn't safe to index
-- by position for anything past victim/attacker.
-- That native returns the bone's TAG (the id GetPedBoneIndex takes), which
-- for SKEL_Head is 31086 -- not joaat('SKEL_Head'). This used to compare
-- against the joaat, which no bone ever reports, so a headshot never
-- classified and the red mark never showed. (Found while diffing against the
-- single-player GTA6Hud, which uses 31086; fenix-police does too.)
-- Not `local`: client.lua is close to Lua's 200-local-per-chunk parse-time
-- cap. A plain global costs nothing against that limit.
HEAD_BONE = 31086

-- victim entity -> hits WE landed on them so far. Cleared the moment they
-- die (or the table would grow forever), so a target that gets away and
-- comes back starts a fresh count rather than inheriting an old one.
-- Not `local` — same reasoning as HEAD_BONE above.
killHits = {}

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    if not Config.Crosshair.enable then return end
    local victim, attacker = args[1], args[2]
    local ped = cache.ped or PlayerPedId()
    if attacker ~= ped or victim == ped then return end
    if not DoesEntityExist(victim) or not IsEntityAPed(victim) then return end

    killHits[victim] = (killHits[victim] or 0) + 1

    if IsPedDeadOrDying(victim, true) then
        local hits = killHits[victim]
        killHits[victim] = nil

        local headshot = false
        local boneOk, bone = GetPedLastDamageBone(victim)
        if boneOk then headshot = bone == HEAD_BONE end

        local quality = 'clean'
        if hits > 1 then quality = 'sloppy'
        elseif headshot then quality = 'headshot'
        end
        ui('crossKill', { quality = quality })
        if Config.Debug then
            print(('^3[vice_hud]^7 kill: hits=%s headshotBone=%s(%s) -> %s')
                :format(hits, tostring(headshot), tostring(bone), quality))
        end
    end
end)

-- =============================================================================
-- Third eye — the 2+-option interact reticle
-- =============================================================================
-- A SEPARATE element from #crosshair above, not a new mode on it: that one
-- is gated to an armed weapon actually being aimed (see its own header
-- comment), and this has to show while unarmed too -- opening a vehicle's
-- interact menu is usually not done with a gun out. Purely a display, same
-- as ShowWorldActions: ox_target/client/main.lua's driveUi is what decides
-- when 2+ options have resolved from an actual aim hit (never proximity
-- alone -- see that file's probeOptionCount), this just shows/hides the
-- marker on command.
exports('SetThirdEyeActive', function(active)
    ui('thirdEye', { active = active and true or false })
end)

-- =============================================================================
-- /hudcrosshair, /hudkillmark, /hudthirdeye — preview without needing a real fight
-- =============================================================================
RegisterCommand('hudthirdeye', function()
    exports.vice_hud:SetThirdEyeActive(true)
    print('^3[vice_hud]^7 /hudthirdeye — /hudthirdeyeoff to clear.')
end, false)
RegisterCommand('hudthirdeyeoff', function() exports.vice_hud:SetThirdEyeActive(false) end, false)

RegisterCommand('hudcrosshair', function(_, args)
    local mode = (args[1] == 'vehicle') and 'vehicle' or 'foot'
    ui('crosshair', { active = true, mode = mode })
    print(('^3[vice_hud]^7 /hudcrosshair %s — /hudcrosshair off to clear, or fire a weapon to override it.'):format(mode))
end, false)
RegisterCommand('hudcrosshairoff', function() ui('crosshair', { active = false }) end, false)

RegisterCommand('hudkillmark', function(_, args)
    local quality = args[1]
    if quality ~= 'headshot' and quality ~= 'sloppy' and quality ~= 'clean' then
        print('^3[vice_hud]^7 usage: /hudkillmark headshot|sloppy|clean')
        return
    end
    ui('crosshair', { active = true, mode = 'foot' })
    ui('crossKill', { quality = quality })
end, false)

-- =============================================================================
-- Race HUD
-- =============================================================================
-- Fed entirely by whatever race resource is running — sk_streetkings today
-- (see its race_singleplayer_c.lua / race_multiplayer_c.lua), via plain data.
-- vice_hud draws it and does not know sk_streetkings exists.
--
-- Three rows, bottom right: PROGRESS and a percentage, the chequered plate,
-- the clock. All of it optional except the clock:
--
--   position, racers   place in the field, "1 / 6" on the plate. Leave both
--                      out (a solo run has no field) and the plate shows the
--                      checkpoint count instead, as it always used to.
--   progress           0.0 .. 1.0 along the route, for the PROGRESS figure.
--                      Left out, it is worked out from lap / cp / cpTotal,
--                      which is right but moves a checkpoint at a time.
--   lap, laps          "LAP 1/2", drawn only when laps > 1.
--   cp, cpTotal        checkpoints cleared this lap, and per lap.
--
-- elapsedMs is a snapshot, not a stream: the caller is expected to push this
-- only on real events (run start, a checkpoint hit, a change of position,
-- finish/abort) — the NUI side ticks the displayed time smoothly on its own
-- between pushes (see onLapHud in app.js) rather than needing this called
-- every frame. A resource that does send `progress` will want to push a
-- little more often than that; a couple of times a second is plenty.
exports('SetLapTimer', function(data)
    if not data or data.show == false then
        ui('lapHud', { show = false })
        return
    end
    ui('lapHud', {
        show = true,
        lap = data.lap,
        laps = data.laps,
        cp = data.cp,
        cpTotal = data.cpTotal,
        position = data.position,
        racers = data.racers,
        progress = data.progress,
        elapsedMs = data.elapsedMs,
        running = data.running,
    })
end)

RegisterCommand('hudlaptimer', function()
    exports.vice_hud:SetLapTimer({ position = 1, racers = 6, progress = 0.30,
        lap = 1, laps = 1, cp = 5, cpTotal = 16, elapsedMs = 30390, running = true })
    print('^3[vice_hud]^7 /hudlaptimer — sample data, /hudlaptimeroff to clear.')
end, false)
RegisterCommand('hudlaptimeroff', function() exports.vice_hud:SetLapTimer({ show = false }) end, false)

-- ---- race cards and countdown -------------------------------------------------
-- The pieces of a race that are not the running block: the title card before
-- the start, the 3-2-1-go, and the placing at the finish. Plain data in, same
-- as SetLapTimer; the page holds each one up for as long as the reference does
-- unless told otherwise, so a race resource can call these and forget them.

--- The title card: a small line, the race's name, a small line.
--- @param data { series?: string, name: string, type?: string, duration?: number }|nil
---        duration in ms (default 1900, 0 = until hidden). nil hides it.
exports('ShowRaceTitle', function(data)
    if type(data) ~= 'table' then ui('raceCard', { show = false }) return end
    ui('raceCard', {
        show = true, kind = 'title',
        series = data.series, name = data.name, type = data.type,
        holdMs = tonumber(data.duration),
    })
end)

--- The result card: "1ST" over the finishing time.
--- @param data { position: number, timeMs?: number, label?: string, duration?: number }|nil
---        label replaces the ordinal ("DNF", "WASTED"). duration in ms
---        (default 2000, 0 = until hidden). nil hides it.
exports('ShowRaceResult', function(data)
    if type(data) ~= 'table' then ui('raceCard', { show = false }) return end
    ui('raceCard', {
        show = true, kind = 'result',
        position = data.position, timeMs = data.timeMs, label = data.label,
        holdMs = tonumber(data.duration),
    })
end)

--- A line across the top with a time under it: FINAL LAP over the lap just
--- finished. data: { text = 'FINAL LAP', timeMs = last lap, duration = ms
--- (default 3000) }. nil hides it.
exports('ShowRaceBanner', function(data)
    if type(data) ~= 'table' then ui('raceCard', { show = false }) return end
    ui('raceCard', {
        show = true, kind = 'banner',
        text = data.text, timeMs = data.timeMs,
        holdMs = tonumber(data.duration),
    })
end)

--- 3, 2, 1, go.
---   ShowRaceCountdown()            the whole run from 3, timed by the page
---   ShowRaceCountdown({ from = 5 })
---   ShowRaceCountdown(3) / ('go')  one beat, for a resource keeping its own clock
---   ShowRaceCountdown(false)       stop and clear
--- "go" appears `from` seconds after the call when the page runs it.
exports('ShowRaceCountdown', function(data)
    if data == false then ui('raceCountdown', { show = false }) return end
    if type(data) == 'table' then
        ui('raceCountdown', {
            show = true, from = data.from, value = data.value,
            stepMs = data.stepMs, digitMs = data.digitMs, goMs = data.goMs,
        })
    elseif data ~= nil then
        ui('raceCountdown', { show = true, value = data })
    else
        ui('raceCountdown', { show = true, from = 3 })
    end
end)

-- ---- race marker ------------------------------------------------------------
-- The next checkpoint, out in the world, as the dirt-bike race draws it: a
-- thin light pillar standing on the track in the accent colour, a dot over
-- it with the distance in feet under that ("453 ft"), and at the finish a
-- chequered tile instead of the dot and coloured smoke across the line.
-- Like the race block, it is fed by the race resource (sk_streetkings) and
-- knows nothing about races: a point on the ground, what kind it is, and for
-- the finish which way the road runs through it.
--
-- Measured off the reference at 1080p:
--   pillar   about 0.8 m across at every range (14 px at 80 m, 4 px at 250 m);
--            ~13 m tall at 260 ft and ~35 m at ~800 ft, so its height grows
--            with distance (0.15 x range, kept between 10 and 45 m) rather
--            than being a fixed size;
--   icon     sits on top of the pillar; dot ~14 px, the distance's centre
--            30 px under the dot's, the pillar starting just under the text;
--   finish   no pillar: the chequered tile hangs ~8 m over the line, the line
--            itself a bank of coloured smoke across the road.
-- The pillar and the smoke are world-space (DrawMarker / a looped particle);
-- the icon is the page's, projected here every frame, the same way the
-- world-anchored action prompt below is.
local RM_PILLAR_WIDTH = 0.85
local RM_PILLAR_PER_METRE, RM_PILLAR_MIN, RM_PILLAR_MAX = 0.15, 10.0, 45.0
local RM_FINISH_ICON_HEIGHT = 8.0
-- Rockstar's own coloured ground smoke (Smuggler's Run's package flare, tinted
-- with SET_PARTICLE_FX_LOOPED_COLOUR in fm_content_generic_misc.sch). One
-- emitter every few metres across the line; started inside RM_SMOKE_ON and
-- stopped past RM_SMOKE_OFF so a finish across the map costs nothing.
local RM_SMOKE_ASSET, RM_SMOKE_FX = 'scr_sm', 'scr_sm_hl_package_flare'
local RM_SMOKE_SPACING, RM_SMOKE_SCALE = 4.5, 1.5
local RM_SMOKE_ON, RM_SMOKE_OFF = 300.0, 350.0

local raceMarker = nil   -- { coords, kind, heading, width, pillar, iconHeight, rgb, smoke, ... }
local rmSent = nil       -- what the page was last told, to push changes only

--- "453 ft" under 1,000 ft, then "0.3 mi": whole feet, as the reference
--- prints them (unlike the nav badge, which rounds to the nearest 5).
local function raceMarkerDistance(m)
    local ft = m * 3.28084
    if ft < 1000.0 then return ('%d ft'):format(math.floor(ft + 0.5)) end
    return ('%.1f mi'):format(m / 1609.344)
end

local function stopRaceSmoke(m)
    if not m or not m.smoke then return end
    for _, fx in ipairs(m.smoke) do StopParticleFxLooped(fx, false) end
    m.smoke = nil
    RemoveNamedPtfxAsset(RM_SMOKE_ASSET)
end

local function startRaceSmoke(m)
    m.smoke = {}
    RequestNamedPtfxAsset(RM_SMOKE_ASSET)
    local deadline = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(RM_SMOKE_ASSET) do
        if GetGameTimer() > deadline or raceMarker ~= m then return end
        Wait(0)
    end
    if raceMarker ~= m then return end
    -- Across the road: GTA's heading h faces (-sin h, cos h), so its right
    -- hand is (cos h, sin h). No heading given: one bank on the point.
    local h = math.rad(m.heading or 0.0)
    local rx, ry = math.cos(h), math.sin(h)
    local n = m.heading and math.max(2, math.floor(m.width / RM_SMOKE_SPACING + 0.5)) or 1
    local c = m.coords
    for i = 1, n do
        local off = (i - (n + 1) / 2) * (m.width / n)
        UseParticleFxAsset(RM_SMOKE_ASSET)
        local fx = StartParticleFxLoopedAtCoord(RM_SMOKE_FX, c.x + rx * off, c.y + ry * off, c.z,
            0.0, 0.0, 0.0, RM_SMOKE_SCALE, false, false, false, true)
        if fx and fx ~= 0 then
            SetParticleFxLoopedColour(fx, m.rgb[1] / 255.0, m.rgb[2] / 255.0, m.rgb[3] / 255.0, true)
            m.smoke[#m.smoke + 1] = fx
        end
    end
end

local function clearRaceMarker()
    if raceMarker then stopRaceSmoke(raceMarker) end
    raceMarker, rmSent = nil, nil
    ui('raceMarker', { show = false })
end

--- The next checkpoint. data:
---   coords      vector3 on the ground where the checkpoint stands (the road
---               surface; the pillar rises from here)
---   kind        'checkpoint' (dot, pillar) or 'finish' (chequered tile, smoke)
---   heading     which way the route runs through it, GTA degrees; lays the
---               finish smoke across the road. Optional.
---   width       metres of road the finish smoke spans (default 14)
---   pillar      false to leave the pillar out (an air gate draws its own ring)
---   iconHeight  metres over coords for the icon when there is no pillar
---   smoke       false for a finish with no smoke (a finish gate in the sky)
---   snap        false to keep coords.z as given; otherwise, once the ground
---               there has streamed in, the marker settles onto it (a point
---               a metre off still stands on the road)
--- nil or false takes it down. Call again for the next one.
exports('SetRaceMarker', function(data)
    if type(data) ~= 'table' or not data.coords then clearRaceMarker() return end
    local accent = exports.vice_hud:GetAccentColour()
    local kind = data.kind == 'finish' and 'finish' or 'checkpoint'
    if raceMarker then stopRaceSmoke(raceMarker) end
    raceMarker = {
        coords = vector3(data.coords.x + 0.0, data.coords.y + 0.0, data.coords.z + 0.0),
        kind = kind,
        heading = tonumber(data.heading),
        width = tonumber(data.width) or 14.0,
        pillar = data.pillar ~= false and kind ~= 'finish',
        iconHeight = tonumber(data.iconHeight) or RM_FINISH_ICON_HEIGHT,
        smokeWanted = kind == 'finish' and data.smoke ~= false,
        snapped = data.snap == false,
        nextSnap = 0,
        rgb = { accent.r, accent.g, accent.b },
    }
    rmSent = nil
    ui('raceMarker', { show = false, kind = kind })
end)
exports('ClearRaceMarker', clearRaceMarker)

CreateThread(function()
    while true do
        if not raceMarker then
            Wait(250)
        else
            Wait(0)
        end
        -- read after the wait: the marker may have been replaced or taken down while yielding
        local m = raceMarker
        if m then
            local c = m.coords
            local dist = #(GetEntityCoords(cache.ped or PlayerPedId()) - c)

            -- Onto the ground, once there is ground to find: collision only
            -- streams in near the player, so a far checkpoint is tried again
            -- every half second until it answers. Only ever a small move.
            if not m.snapped and dist < 400.0 and GetGameTimer() >= m.nextSnap then
                m.nextSnap = GetGameTimer() + 500
                local found, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 2.0, false)
                if found then
                    m.snapped = true
                    if math.abs(gz - c.z) <= 3.0 then
                        m.coords = vector3(c.x, c.y, gz)
                        c = m.coords
                    end
                end
            end

            local top = c.z + m.iconHeight

            if m.pillar then
                local h = math.max(RM_PILLAR_MIN, math.min(RM_PILLAR_MAX, dist * RM_PILLAR_PER_METRE))
                local r, g, b = m.rgb[1], m.rgb[2], m.rgb[3]
                -- A soft halo round a brighter core. Type 1 is the vertical
                -- cylinder, which the game already fades out towards its top.
                -- Sunk half a metre so it never floats over a dip in the road.
                DrawMarker(1, c.x, c.y, c.z - 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    RM_PILLAR_WIDTH * 2.2, RM_PILLAR_WIDTH * 2.2, h + 0.5, r, g, b, 40,
                    false, false, 2, false, nil, nil, false)
                DrawMarker(1, c.x, c.y, c.z - 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    RM_PILLAR_WIDTH, RM_PILLAR_WIDTH, h + 0.5, r, g, b, 165,
                    false, false, 2, false, nil, nil, false)
                top = c.z + h
            end

            if m.smokeWanted and (m.snapped or dist < 120.0) then
                if not m.smoke and dist < RM_SMOKE_ON then
                    m.smoke = {}
                    CreateThread(function() startRaceSmoke(m) end)
                elseif m.smoke and dist > RM_SMOKE_OFF then
                    stopRaceSmoke(m)
                end
            end

            local onScreen, sx, sy = GetScreenCoordFromWorldCoord(c.x, c.y, top)
            local text = raceMarkerDistance(dist)
            local last = rmSent
            if not last or last.show ~= onScreen or last.text ~= text
                or math.abs(last.x - sx) > 0.0004 or math.abs(last.y - sy) > 0.0004 then
                rmSent = { show = onScreen, x = sx, y = sy, text = text }
                ui('raceMarker', { show = onScreen, kind = m.kind, x = sx, y = sy, text = text })
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and raceMarker then stopRaceSmoke(raceMarker) end
end)

RegisterCommand('hudracemarker', function(_, args)
    local ped = cache.ped or PlayerPedId()
    local ahead = GetOffsetFromEntityInWorldCoords(ped, 0.0, 80.0, 0.0)
    local found, gz = GetGroundZFor_3dCoord(ahead.x, ahead.y, ahead.z + 10.0, false)
    exports.vice_hud:SetRaceMarker({
        coords = vector3(ahead.x, ahead.y, found and gz or ahead.z),
        kind = args[1] == 'finish' and 'finish' or 'checkpoint',
        heading = GetEntityHeading(ped),
    })
    print('^3[vice_hud]^7 /hudracemarker [finish] — a race marker 80 m ahead. /hudracemarkeroff to clear.')
end, false)
RegisterCommand('hudracemarkeroff', function() exports.vice_hud:ClearRaceMarker() end, false)

-- =============================================================================
-- Screen text and overlays
-- =============================================================================
-- Subtitles, the objective line, the help box, the feed, title cards, the
-- binocular mask and the shop item panel. (WASTED and BUSTED are not here:
-- they are the vi_wasted resource, taken from fenix-police.) Each is drawn by the page from
-- one message; nothing here polls. Text takes two marks: **bold** for a key
-- word and {braces} for the thing the line is about, which is drawn pink.
--
-- A duration is in ms. Where one is optional, nil means the element's own
-- default and 0 means "until hidden"; passing nil / false as the text hides it.

local function textMessage(action, text, durationMs, extra)
    if text == nil or text == false or text == '' then
        ui(action, { show = false })
        return
    end
    local data = extra or {}
    data.show = true
    data.text = tostring(text)
    data.holdMs = tonumber(durationMs)
    ui(action, data)
end

-- Bumped on every ShowSubtitle / ShowHelpText call, so something that put
-- text up and later wants it gone (client_nativetext.lua) can tell whether
-- anyone else has used the box since, and leave theirs alone. Globals for
-- the 200-local reason at the top of this file.
SubtitleSerial = 0
HelpTextSerial = 0

--- One or two lines of speech, bottom centre. Default 4 s.
exports('ShowSubtitle', function(text, durationMs)
    SubtitleSerial = SubtitleSerial + 1
    textMessage('subtitle', text, durationMs)
end)

--- What to do next, under the subtitle: 'Return to {Lucia}'. Stays until
--- hidden unless a duration is given.
exports('ShowObjective', function(text, durationMs)
    textMessage('objective', text, durationMs)
end)

--- The help box, top left. opts.tells = { 'outfit', 'voice', ... } draws that
--- row of wanted tells under the text. opts.keys = { 25, 24 } puts those
--- controls' buttons in the line where it says [[1]], [[2]] ('aim with [[1]]
--- and hold [[2]]'), drawn as the action prompts draw them, for the device in
--- hand. Default 7 s.
exports('ShowHelpText', function(text, durationMs, opts)
    HelpTextSerial = HelpTextSerial + 1
    opts = type(opts) == 'table' and opts or {}

    local glyphs
    if type(opts.keys) == 'table' then
        glyphs = {}
        for i, key in ipairs(opts.keys) do
            local glyph, device = ViceGlyphs.control(key)
            glyphs[i] = { glyph = glyph, device = device }
        end
    end

    textMessage('helpText', text, durationMs, { tells = opts.tells, glyphs = glyphs })
end)

--- A line in the feed on the right ('Crime reported'). opts.icon is an image
--- in html/ to draw after it; opts.duration defaults to 3.5 s. opts.counter =
--- a name ('gk_basketball:scored') makes it a count of something going on:
--- a size up, as the reference draws "2 scored", and each one with that name
--- replaces the last instead of stacking under it.
exports('ShowFeed', function(text, opts)
    if text == nil or text == '' then return end
    opts = type(opts) == 'table' and opts or {}
    ui('feed', { text = tostring(text), icon = opts.icon, holdMs = tonumber(opts.duration),
        counter = type(opts.counter) == 'string' and opts.counter or nil })
end)

--- A title card. style: 'center' (PROLOGUE), 'stack' (NINE MONTHS AGO., one
--- word a line) or 'location' (a place name at the top). Default 3.5 s.
exports('ShowTitleCard', function(text, style, durationMs)
    textMessage('titleCard', text, durationMs, { style = style })
end)

--- The cinematic overlay: the Focus effect's vignette in black, with bars. It
--- stays up while the HUD is hidden, which is the point of it. opts:
--- { strength = 0..2 (default 1), bars = fraction of screen height (default
--- 0.032, 0 for none), pulse = false for a still vignette }.
exports('SetCinematicFx', function(active, opts)
    if not active then ui('cineFx', { show = false }) return end
    opts = type(opts) == 'table' and opts or {}
    ui('cineFx', {
        show = true,
        strength = tonumber(opts.strength),
        bars = tonumber(opts.bars),
        pulse = opts.pulse ~= false,
    })
end)

--- The binocular mask. opts: { label = 'PHONE CASES', key = control id for
--- the button drawn beside the label }. A binocular script does the camera;
--- this is only the picture (see resources/vi_binoculars).
exports('SetBinocularOverlay', function(active, opts)
    if not active then ui('binoculars', { show = false }) return end
    opts = type(opts) == 'table' and opts or {}
    local glyph, device
    if opts.key ~= nil then glyph, device = ViceGlyphs.control(opts.key) end
    ui('binoculars', { show = true, label = opts.label, glyph = glyph, device = device })
end)

--- The shop item panel. data: { store, category, price, pay = { 'bank',
--- 'cash' }, name, variant, swatches = { { color = '#1f8a45', locked = true },
--- ... }, selected = index, afford = false, note }. BUY / EXIT are ordinary
--- action prompts; they sit in a row while the panel is up, and
--- ShowActionPrompt's opts.off greys one that cannot be used.
--- Strip mode, as GTA VI's barber shows its hairstyles (illenium-appearance's
--- client/parlour.lua): strip = true makes the swatches the items themselves,
--- each picture filling its tile; counter = '3 / 40' over the row's end,
--- more = true an arrow after it, progress = { first, shown, total } a
--- hairline under it, status = 'Not applied' a plain line under that.
exports('ShowShopItem', function(data)
    if type(data) ~= 'table' then ui('shop', { show = false }) return end
    data.show = true
    ui('shop', data)
end)
exports('HideShopItem', function()
    ui('shop', { show = false })
end)

--- The vehicle stats panel, as shown beside a bike you can rent. data:
--- { make = 'Maibatsu', model = 'Sanchez',
---   stats = { { label = 'Speed', value = 4.5 }, ... },   -- value out of 10, or give max
---   ratings = { { value = 649, kind = 'offroad' }, { value = 520, kind = 'road' } } }
exports('ShowVehicleStats', function(data)
    if type(data) ~= 'table' then ui('vehStats', { show = false }) return end
    data.show = true
    ui('vehStats', data)
end)
exports('HideVehicleStats', function()
    ui('vehStats', { show = false })
end)

RegisterCommand('hudvehstats', function()
    exports.vice_hud:ShowVehicleStats({
        make = 'Maibatsu', model = 'Sanchez',
        stats = {
            { label = 'Speed', value = 4.5 }, { label = 'Acceleration', value = 5.4 },
            { label = 'Asphalt handling', value = 5.2 }, { label = 'Off-road handling', value = 4.9 },
            { label = 'Strength', value = 4.0 },
        },
        ratings = { { value = 649, kind = 'offroad' }, { value = 520, kind = 'road' } },
    })
    SetTimeout(8000, function() exports.vice_hud:HideVehicleStats() end)
    print('^3[vice_hud]^7 /hudvehstats — sample vehicle stats panel for eight seconds.')
end, false)

RegisterCommand('hudtext', function()
    exports.vice_hud:ShowSubtitle('Excuse me, sir. Sir. Owner of the pickup,\ngas needs to go in the tank.', 6000)
    exports.vice_hud:ShowObjective('Return to {Lucia}', 6000)
    exports.vice_hud:ShowHelpText('Repeated use of **Zombix** will temporarily have a weaker effect on your health.', 6000)
    exports.vice_hud:ShowFeed('Crime reported')
    print('^3[vice_hud]^7 /hudtext — subtitle, objective, help box and a feed line for six seconds.')
end, false)

RegisterCommand('hudtitle', function(_, args)
    local style = args[1] or 'center'
    local text = style == 'stack' and 'Nine months ago.' or style == 'location' and 'Port Gellhorn' or 'Prologue'
    exports.vice_hud:ShowTitleCard(text, style)
    print('^3[vice_hud]^7 /hudtitle [center|stack|location] — sample title card.')
end, false)

RegisterCommand('hudshop', function()
    exports.vice_hud:ShowShopItem({
        store = 'Game Horde', category = 'Earbuds', price = 139, name = 'Clef Earbuds', variant = 'Green',
        swatches = {
            { color = '#1c1c1e', locked = true }, { color = '#f1eef0', locked = true },
            { color = '#f4ee2c', locked = true }, { color = '#a51c24', locked = true },
            { color = '#1f8a45', locked = true }, { color = '#7a45ad', locked = true },
        },
        selected = 5, afford = false,
    })
    print('^3[vice_hud]^7 /hudshop — sample shop panel. /hudshopoff to clear.')
end, false)
RegisterCommand('hudshopoff', function() exports.vice_hud:HideShopItem() end, false)

RegisterCommand('hudrace', function()
    print('^3[vice_hud]^7 /hudrace — title card, countdown, race block, FINAL LAP, then the result card.')
    exports.vice_hud:ShowRaceTitle({ series = "HIT 'N' RUN VC", name = 'SALTON TO WANING SANDS', type = 'GROUP RACE' })
    SetTimeout(5500, function() exports.vice_hud:ShowRaceCountdown() end)
    SetTimeout(8500, function()
        exports.vice_hud:SetLapTimer({ position = 8, racers = 14, lap = 1, laps = 2, elapsedMs = 0, running = true })
    end)
    SetTimeout(12500, function()
        exports.vice_hud:SetLapTimer({ position = 7, racers = 14, lap = 2, laps = 2, elapsedMs = 89290, running = true })
        exports.vice_hud:ShowRaceBanner({ text = 'FINAL LAP', timeMs = 89290 })
    end)
    SetTimeout(18500, function()
        exports.vice_hud:SetLapTimer({ show = false })
        exports.vice_hud:ShowRaceResult({ position = 1, timeMs = 178893 })
    end)
end, false)

-- =============================================================================
-- World action prompt — a short list of button-glyph + label choices
-- =============================================================================
-- Purely a display: it has no selection logic of its own, because the
-- reference itself pairs each option with its OWN dedicated button (Slim
-- Jim = Triangle, Smash Window = Circle) rather than a highlight-and-
-- confirm list — so the caller is expected to poll its own keybind per
-- option (lib.addKeybind, same as qbx_vehiclekeys already does elsewhere)
-- and just tell this what to show. World-anchored when the caller passes
-- coords (see waCoords, below) — a caller that omits it (qbx_vehiclekeys
-- today) still gets the original fixed screen position.
--
-- FIXED 2026-08-28: this used to take a hand-picked `button` STRING
-- ('triangle'/'circle') with nothing tying it to what the caller's keybind
-- was actually bound to. That let the two drift apart -- and they had:
-- qbx_vehiclekeys showed a triangle for Slim Jim while the working pad
-- button underneath it was Circle, and Smash Window's real button (Circle)
-- had no controller binding at all. Pressing the icon the player was
-- LOOKING AT did nothing, because that icon was never connected to any
-- input in the first place. See qbx_vehiclekeys/client/slimjim.lua for the
-- other half of this fix.
--
-- Now `key` (a control ID, or an ox_lib keybind's own `.hash`) is what the
-- caller passes, and the glyph shown is RESOLVED from it, live, the exact
-- same way the Action Prompts system above does for its own prompts
-- (resolveKey/usingPad, duplicated here rather than reached for across the
-- client.lua/client_overlays.lua split -- see the `ui()` helper at the top
-- of this file for the established precedent). The icon can no longer
-- disagree with the binding: it IS the binding, resolved.

-- The resolving is ViceGlyphs' (client_glyphs.lua), the same one the action
-- prompts use, so a world action and a prompt bound to the same control can
-- never show different buttons.
local function waUsingPad() return ViceGlyphs.usingPad() end

-- A control id -> token, device. See ViceGlyphs.control.
local function waResolveKey(key) return ViceGlyphs.control(key) end

local waOptions = nil     -- the last { label, key } list shown, for the refresh thread
local waDevice = nil

-- Each option carries the device its OWN button belongs to, which is the
-- device in hand except for a bind that only exists on the other one.
local function waResolveAll()
    local resolved = {}
    if waOptions then
        for i, opt in ipairs(waOptions) do
            local glyph, device = waResolveKey(opt.key)
            resolved[i] = { label = opt.label, glyph = glyph, device = device,
                            more = opt.more and true or nil, dot = opt.dot or nil }
        end
    end
    return resolved, ViceGlyphs.device()
end

-- World-anchoring -- closes the gap #world-actions in index.html and the
-- comment above `#world-actions` in style.css both flag: this used to be a
-- fixed screen position with no connection to the world point it's about.
--
-- `coords` (optional, a vector3) is the third piece: when given, a
-- per-frame thread below projects it every tick via
-- GetScreenCoordFromWorldCoord and pushes the result as its own lightweight
-- message (worldActionsPos) rather than folding it into ShowWorldActions's
-- own ui('worldActions', ...) push -- that message rebuilds the whole
-- options list DOM (see onWorldActions in app.js), which running it every
-- frame would do for nothing; same reasoning as onPromptProgress writing
-- the action-prompt hold ring as its own direct style update instead of a
-- full renderPrompts() every tick. A caller that omits `coords`
-- (qbx_vehiclekeys today) gets nothing from that thread at all --
-- #world-actions just stays on its own CSS fixed position, unchanged from
-- before this existed.
local waCoords = nil
local waCompact = true    -- the label drops away at range, unless the caller says otherwise
local waCentred = false   -- the first button sits ON the point instead of beside it
local waOwner = nil       -- who put the prompt up, when they said (opts.id)

-- Also drives the icon-only-at-range / full-label-up-close split ("both" of
-- the two prop-prompt options considered): computed locally here each frame
-- against the live player position rather than requiring ox_target to keep
-- re-pushing its own distance, since this thread already has to run every
-- tick anyway to track the projection. Roughly ox_target's own default
-- interact range (see ox_target:proximityRadius); not pixel/gameplay tuned.
local WA_COMPACT_DISTANCE = 1.5

--- options: array of { label, key } -- key is a native GTA control ID
--- (see PAD::IS_CONTROL_PRESSED's `action` param) or an ox_lib keybind's
--- own `.hash` field, exactly as ShowActionPrompt's `key` already works.
--- An option may also carry `more = true` (it opens a list: three dots on a
--- dark disc between the button and its name, FRIDGE in the reference) and
--- `dot = true` or a '#rrggbb' (a coloured dot there instead, the reference's
--- mark for something on sale).
--- coords (optional): vector3 world point to anchor the prompt to -- see
--- the world-anchoring comment above. Omit it for the old fixed-position
--- behaviour.
--- opts (optional): { compact = false } keeps the label at any distance;
--- { centred = true } puts the first button on the point itself, as the
--- reference does, rather than beside it; { id = 'my_resource' } names who
--- put it up, so that HideWorldActions('my_resource') only takes down a
--- prompt that is still theirs. There is one world prompt, and the last one
--- shown is the one on screen.
exports('ShowWorldActions', function(options, coords, opts)
    waOptions = options or {}
    waCoords = coords
    waCompact = not (type(opts) == 'table' and opts.compact == false)
    waCentred = type(opts) == 'table' and opts.centred == true
    waOwner = type(opts) == 'table' and opts.id or nil
    local resolved, device = waResolveAll()
    waDevice = device
    ui('worldActions', { show = true, options = resolved, centred = waCentred })
end)
--- Move a prompt that is up to a new point, without rebuilding it (a door
--- swinging, something being carried). Nothing if no prompt is up.
exports('SetWorldActionsCoords', function(coords, id)
    if id ~= nil and waOwner ~= id then return end
    if waOptions and coords then waCoords = coords end
end)
--- id (optional): only hide a prompt put up under that id; another script's
--- prompt, shown since, is left alone. No id hides whatever is up.
exports('HideWorldActions', function(id)
    if id ~= nil and waOwner ~= id then return end
    waOptions = nil
    waCoords = nil
    waOwner = nil
    ui('worldActions', { show = false })
end)

-- Re-resolve when the input device changes, the same way the action prompts
-- do -- so a mid-prompt controller/keyboard swap updates the icon instead of
-- leaving it wrong until the caller happens to re-push.
ViceGlyphs.onDevice(function(device)
    if not waOptions then return end
    waDevice = device
    ui('worldActions', { show = true, options = (waResolveAll()), centred = waCentred })
end)

-- The world-anchoring thread itself -- see waCoords's own comment above for
-- why this is a separate push from ShowWorldActions/the refresh thread.
-- Idles at Wait(200) while nothing is world-anchored (still cheap enough to
-- just poll rather than restructure around an event) and only runs every
-- frame while waCoords is actually set.
CreateThread(function()
    while true do
        if waCoords then
            local playerCoords = GetEntityCoords(cache.ped or PlayerPedId())
            local onScreen, sX, sY = GetScreenCoordFromWorldCoord(waCoords.x, waCoords.y, waCoords.z)
            ui('worldActionsPos', {
                show = onScreen,
                x = sX,
                y = sY,
                compact = waCompact and #(playerCoords - waCoords) > WA_COMPACT_DISTANCE,
            })
            Wait(0)
        else
            Wait(200)
        end
    end
end)

RegisterCommand('hudworldactions', function()
    -- 51 = INPUT_CONTEXT ('E' on keyboard), 47 = INPUT_DETONATE ('Y'/Triangle
    -- on pad) -- real GTA control IDs, purely so this demo resolves to
    -- something real on both devices without needing a live ox_lib keybind.
    exports.vice_hud:ShowWorldActions({
        { label = 'Slim Jim', key = 47 },
        { label = 'Smash Window', key = 51 },
        { label = 'Fridge', key = 74, more = true },
    })
    print('^3[vice_hud]^7 /hudworldactions — sample data. /hudworldactionsoff to clear.')
end, false)
RegisterCommand('hudworldactionsoff', function() exports.vice_hud:HideWorldActions() end, false)

-- =============================================================================
-- Lockpick check — analog direction-fill ring
-- =============================================================================
-- The caller owns the button (its own lib.addKeybind, same pattern
-- qbx_vehiclekeys already uses for searching a car for keys) and just tells
-- this when the hold started and ended; this owns the ring, the direction/
-- completion decision, and hands the result back as an event — the same
-- "plain data in, plain event out" shape the wheels use.
--
-- REWORKED AGAIN 2026-09-12, this time replacing the "release inside a
-- target zone" mechanic entirely, per the user-approved HTML mockup
-- (lockpick_preview.html) worked out over many rounds of feedback against
-- the GTA VI: An Extended Look trailer footage. There is no more zone and
-- no more release-based resolution at all:
--   * dragging right-to-left fills the ring, anchored growing from the
--     right; dragging left-to-right fills it identically, anchored growing
--     from the left -- both LOOK the same the whole time you're mid-drag.
--   * reaching 100% right-to-left is the real pick (success).
--   * reaching 100% left-to-right is a trap: it trips an "alarm" outcome
--     instead, meant to eventually wire into a car alarm elsewhere (see
--     exports('LockpickAlarm'-adjacent event below) -- NOT built here.
-- Direction/fill are derived live every tick from where the input currently
-- sits, not from an accumulated "effort" score -- see lockpickTick() below.
--
-- Wrapped in do...end for the same reason the interact-menu/controller
-- section is — see the comment there.
do
local lockpickActive = false
local lockpickPct = 0   -- current fill, 0-100, always re-derived live (see lockpickTick)
local lockpickDir = -1  -- -1 = right-to-left (the real pick), 1 = left-to-right (the trap)

-- INPUT_LOOK_LR (control ID 1 — confirmed against _tools/fivem_docs' own
-- game-references/controls table, NOT guessed: that page lists it as bound
-- to "RIGHT STICK X" on a pad AND to raw mouse-movement ("MOUSE RIGHT") on
-- keyboard, which is exactly the dual pad-stick/mouse-delta signal this
-- minigame needs). Only the horizontal axis matters now -- the mockup's own
-- `dir`/`pct` logic is driven purely by dx, never dy (dy only ever moved
-- the mockup's centre glyph for visual noise, which this port simplifies
-- away, see lockpickTick's comment below). INPUT_ATTACK (24) is the same
-- LMB control already used elsewhere in this file (see
-- MOUSE_CONTROLS[24] = 'LMB' in client_glyphs.lua) — reused here as the "is the
-- mouse player dragging" gate.
local LOCKPICK_CONTROL_LOOK_LR = 1
local LOCKPICK_CONTROL_ATTACK  = 24

-- Below this stick deflection, the pad isn't meaningfully steering — reads
-- as centred/idle rather than "barely pushed", absorbing analog deadzone
-- noise so a resting pad doesn't register a phantom direction.
local LOCKPICK_IDLE_THRESHOLD = 0.12

-- GET_CONTROL_NORMAL's mouse-driven value for LOOK_LR is a raw per-frame
-- look-camera delta (tuned for camera turn speed), not a position — unlike
-- a pad's stick, which reports where it physically IS this frame. The
-- mockup's `dx = current.x - dragStart.x` needs an actual position, so for
-- mouse it's reconstructed by summing that per-frame delta for as long as
-- LMB is held — arithmetically this sum always equals "how far the mouse
-- has moved since LMB went down", i.e. a genuine net position, not an
-- "integrated effort" score. Scaled up for the same reason the old
-- effort-based build scaled it: nowhere near a usable range unscaled on a
-- deliberate drag.
--
-- RETUNED 2026-09-13 (first real in-game feel test, via qbx_vehiclekeys'
-- Slim Jim): felt noticeably less responsive than the browser mockup at the
-- original 6.0. First pass tripled it to 18.0 -- still "needs to move
-- quicker, should follow the mouse exactly" on the second test, so this is
-- a second, bigger jump rather than another small nudge (each retune costs
-- a real playtest, not a local one -- see this repo's own note on why:
-- FiveM client crashes on this dev PC). If THIS overshoots (twitchy,
-- reaches 100% on a small flick), the fix is still to bring this one value
-- back down, not LOCKPICK_MOUSE_SENSITIVITY, so "distance to 100%" stays
-- the one knob for difficulty and this one stays purely "how much mouse
-- movement equals how much reconstructed distance".
local LOCKPICK_MOUSE_SCALE = 45.0

-- How far the reconstructed mouse position (in LOCKPICK_MOUSE_SCALE-d
-- units, see above) has to travel from centre to reach a full 100% fill —
-- the direct analog of the mockup's "Fill sensitivity" slider (default
-- 160, in raw drag pixels). There is no equivalent slider here, just this
-- one constant; a caller wanting an easier/harder check no longer has a
-- knob for it now that the mechanic is purely positional (see
-- StartLockpickCheck's own comment on why cfg.durationMs/zoneLen are gone).
local LOCKPICK_MOUSE_SENSITIVITY = 220

-- How fast the reconstructed mouse position decays back toward centre once
-- LMB is released mid-check (the mockup's own "Decay rate" slider, in the
-- same units as LOCKPICK_MOUSE_SENSITIVITY per second) — letting go doesn't
-- freeze progress in place, it drains back down, same read as the mockup's
-- own tick() "not dragging" branch.
local LOCKPICK_MOUSE_DECAY_PER_SEC = 90

local lockpickMouseDx = 0 -- reconstructed net mouse position since LMB was last (re)pressed, see comment above

--- Reads this frame's signed, normalised drag position as -1.0..1.0
--- (negative = pushed toward right-to-left / the real pick, positive =
--- pushed toward left-to-right / the trap), disabling the controls it
--- reads so a lockpick doesn't ALSO spin the camera or fire a weapon while
--- it's being worked (DisableControlAction has to be called every frame it
--- should apply, and read back via GetDisabledControlNormal/
--- IsDisabledControlPressed instead of the un-disabled natives once it has
--- — see PAD::DISABLE_CONTROL_ACTION / PAD::GET_DISABLED_CONTROL_NORMAL /
--- PAD::IS_DISABLED_CONTROL_PRESSED, all confirmed via _tools/nativedb).
---
--- Pad: the stick's OWN current x-deflection IS a position already (a
--- physical stick doesn't need reconstructing the way a mouse delta does)
--- — read directly, no accumulation, matching the mockup's "current
--- position relative to where the hold started, not integrated effort over
--- time" requirement to the letter.
--- Mouse: gated on LMB actually being held (waUsingPad()'s counterpart,
--- client_glyphs.lua's MOUSE_CONTROLS[24], is the established "24 = LMB" precedent in
--- this file); while held, LOOK_LR's per-frame delta accumulates into
--- lockpickMouseDx (see its own comment above); while not held, that
--- accumulator decays back toward 0 instead of freezing.
local function lockpickReadDx(dtMs)
    DisableControlAction(0, LOCKPICK_CONTROL_LOOK_LR, true)
    DisableControlAction(0, LOCKPICK_CONTROL_ATTACK, true)

    if waUsingPad() then
        local sx = GetDisabledControlNormal(0, LOCKPICK_CONTROL_LOOK_LR)
        if math.abs(sx) < LOCKPICK_IDLE_THRESHOLD then return 0 end
        return math.max(-1, math.min(1, sx))
    end

    if not IsDisabledControlPressed(0, LOCKPICK_CONTROL_ATTACK) then
        -- LMB not held: drain the reconstructed position back toward 0,
        -- same feel as the mockup's own decay-while-not-dragging branch.
        local decayStep = LOCKPICK_MOUSE_DECAY_PER_SEC * (dtMs / 1000)
        if lockpickMouseDx > 0 then
            lockpickMouseDx = math.max(0, lockpickMouseDx - decayStep)
        else
            lockpickMouseDx = math.min(0, lockpickMouseDx + decayStep)
        end
        return lockpickMouseDx / LOCKPICK_MOUSE_SENSITIVITY
    end

    local mx = GetDisabledControlNormal(0, LOCKPICK_CONTROL_LOOK_LR)
    lockpickMouseDx = lockpickMouseDx + mx * LOCKPICK_MOUSE_SCALE
    lockpickMouseDx = math.max(-LOCKPICK_MOUSE_SENSITIVITY, math.min(LOCKPICK_MOUSE_SENSITIVITY, lockpickMouseDx))
    return lockpickMouseDx / LOCKPICK_MOUSE_SENSITIVITY
end

--- Re-derives lockpickPct/lockpickDir for this frame from the current input
--- position (dtMs = real elapsed time, used only for the mouse's own
--- decay-while-released branch above) and returns both. Positional, not
--- effort-accumulated, exactly like the mockup's own tick(): pct is always
--- `abs(dx) * 100`, dir is always `dx < 0 and -1 or 1`, recomputed fresh
--- every frame rather than built up over time.
local function lockpickTick(dtMs)
    local dx = lockpickReadDx(dtMs)
    lockpickDir = dx < 0 and -1 or 1
    lockpickPct = math.max(0, math.min(100, math.abs(dx) * 100))
    return lockpickPct, lockpickDir
end

--- cfg: { key (a control ID, or an ox_lib keybind's own `.hash` — resolved
--- LIVE into a text glyph via waResolveKey, the same "the icon IS the
--- binding, resolved" pattern ShowWorldActions/action prompts already use
--- elsewhere in this file, rather than a hand-picked string that can drift
--- out of sync with what's actually bound), glyph (legacy raw string
--- fallback for a caller not yet passing `key` — kept so
--- qbx_vehiclekeys/client/slimjim.lua's existing `glyph = 'R'` call keeps
--- working unchanged).
---
--- zoneLen/zoneStart are GONE: there is no more target zone at all (see the
--- do...end's own header comment for the mechanic this replaced). A caller
--- still passing them is harmless — they're just never read.
---
--- durationMs is ALSO gone as a fill-rate knob: the fill is now purely
--- positional (see lockpickTick), so there is no rate or duration left to
--- size. A caller still passing it is likewise harmless.
---
--- FIXED 2026-09-13 (first real in-game test): cfg.glyph's 'R' fallback
--- predates this file's own rework above -- filling the ring was moved to a
--- raw LOOK_LR/ATTACK read (lockpickReadDx) that has nothing to do with any
--- keybind, but the caller (qbx_vehiclekeys/client/slimjim.lua) still passes
--- the old key-hold mechanic's glyph. On a pad that happens to still read
--- right ("R" = right stick), but on keyboard/mouse it showed the letter R
--- while the actual input is dragging with LMB held -- the player is shown a
--- key that does nothing for filling (R only cancels, on release). Device is
--- what decides which input actually drives the fill, so it decides the
--- glyph too, same as everywhere else in this file (waUsingPad()) -- a
--- caller-supplied `key` still wins outright since that IS a real binding.
--- Call the instant the player PRESSES the button.
exports('StartLockpickCheck', function(cfg)
    cfg = cfg or {}
    lockpickActive = true
    lockpickPct = 0
    lockpickDir = -1
    lockpickMouseDx = 0
    local glyph = cfg.key ~= nil and waResolveKey(cfg.key)
        or (waUsingPad() and (cfg.glyph or 'R') or 'LMB')
    ui('lockpick', { show = true, glyph = glyph })
end)

--- Call the instant the button is RELEASED. There is no more release-based
--- win/lose check at all — completion is purely "pct reached 100, which
--- direction was it" (see the CreateThread loop below), decided mid-hold,
--- not on release. Releasing before that just abandons the attempt with no
--- outcome, same as CancelLockpickCheck — kept as its own export (rather
--- than folded into Cancel) because "the player let go" and "the caller is
--- force-ending this" are different callers' events even though they now
--- do the same thing here.
exports('ReleaseLockpickCheck', function()
    if not lockpickActive then return end
    lockpickActive = false
    ui('lockpick', { show = false })
end)

--- Aborts with no result event at all — for e.g. the vehicle driving off or
--- the player being interrupted mid-hold, where neither success nor the
--- alarm is the right read.
exports('CancelLockpickCheck', function()
    lockpickActive = false
    ui('lockpick', { show = false })
end)

-- Wait(0) now, not a slower poll: reading analog stick/mouse deflection and
-- disabling its controls both need to happen every rendered frame to feel
-- responsive and to keep DisableControlAction actually in effect (it only
-- holds for the frame it's called on) — a slower poll would both miss fast
-- stick flicks and let the camera/weapon controls sneak back in for most
-- frames at 60fps.
CreateThread(function()
    local lastTick = GetGameTimer()
    while true do
        Wait(lockpickActive and 0 or 200)
        local now = GetGameTimer()
        local dtMs = now - lastTick
        lastTick = now
        if lockpickActive then
            local pct, dir = lockpickTick(dtMs)
            ui('lockpickProgress', { pct = pct, dir = dir })
            if pct >= 100 then
                lockpickActive = false
                if dir < 0 then
                    -- Right-to-left to 100% — the real pick.
                    ui('lockpickResult', { success = true })
                    TriggerEvent('vice_hud:lockpickResult', true)
                else
                    -- Left-to-right to 100% — looked identical to progress
                    -- the whole time, but this is the trap: fire a
                    -- DISTINCT outcome rather than folding it into
                    -- lockpickResult's boolean, so a caller can tell "you
                    -- finished it the wrong way" apart from "you didn't
                    -- finish it" and eventually wire a real car alarm to
                    -- it — that wiring is a different resource's job, not
                    -- built here. Bare TriggerEvent, no payload: there's
                    -- nothing to report beyond "it happened".
                    ui('lockpickAlarm', {})
                    TriggerEvent('vice_hud:lockpickAlarm')
                end
            end
        end
    end
end)

RegisterCommand('hudlockpick', function()
    exports.vice_hud:StartLockpickCheck({ key = 51 })
    print('^3[vice_hud]^7 /hudlockpick — ring started, drag right-to-left to pick it (left-to-right traps the alarm instead). /hudlockpickrelease to abandon it now.')
end, false)
RegisterCommand('hudlockpickrelease', function() exports.vice_hud:ReleaseLockpickCheck() end, false)
end -- close the do opened above local lockpickActive

-- =============================================================================
-- Key clone check
-- =============================================================================
-- The single-player HUD's CLONE KEY (2.7) on the same ring (#lockpick, in its
-- lp-clone mode): a dot sweeps back and forth along the bottom half, and the
-- player presses while it is inside the pink window. Each hit fills a third
-- of the band, moves the window and speeds the dot up (55, 75 then 100% of
-- the half ring a second). Three hits and the key is cloned, three misses and
-- it is the alarm. E or the left mouse button; Square / X on a pad (jump, so
-- he can't also hop); Backspace / Circle / B backs out with no result.
--
-- Results are local events, like the lockpick's: vice_hud:keyCloneResult
-- (true), vice_hud:keyCloneAlarm, vice_hud:keyCloneCancel. The caller
-- (qbx_vehiclekeys/client/keyclone.lua) owns the car, the phone and what
-- each result means. Its own do...end, for the same 200-locals reason as the
-- block above.
do
local cloneActive = false
local clone = { pos = 0, dir = 1, target = 50, hits = 0, misses = 0, startedAt = 0 }

local CLONE_HITS, CLONE_MISSES = 3, 3
local CLONE_WINDOW = 24 / 1.8      -- the window is 24 degrees of the ring, in the half ring's 0-100
local CLONE_SPEEDS = { 55, 75, 100 }
local CLONE_GRACE_MS = 300         -- the press that started it can't count as a try
local CLONE_SOUNDS = 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS'

-- Somewhere from 10 to 90, at least a quarter of the ring from the dot
-- (twenty tries, then wherever the last one fell), as the mock and the
-- single-player HUD place it.
local function cloneNewTarget()
    local t = 50
    for _ = 1, 20 do
        t = 10 + math.random() * 80
        if math.abs(t - clone.pos) >= 25 then break end
    end
    clone.target = t
end

local function clonePressed()
    if waUsingPad() then return IsDisabledControlJustPressed(0, 22) end
    return IsDisabledControlJustPressed(0, 38) or IsDisabledControlJustPressed(0, 24)
end

-- He stands at the door with the phone: no walking off, shooting or jumping
-- while it runs. The camera stays free.
local CLONE_HELD = { 21, 22, 24, 25, 30, 31, 32, 33, 34, 35, 38, 44, 51, 140, 141, 142, 177, 257, 263, 264 }

local function cloneEnd(name, value)
    cloneActive = false
    if name then TriggerEvent(name, value) end
end

--- cfg: { key (a control ID to show instead of E / jump), glyph (raw text) }.
exports('StartKeyCloneCheck', function(cfg)
    cfg = cfg or {}
    clone.pos, clone.dir, clone.hits, clone.misses = 0, 1, 0, 0
    clone.startedAt = GetGameTimer()
    cloneNewTarget()
    cloneActive = true
    local glyph, device
    if cfg.key ~= nil then glyph, device = waResolveKey(cfg.key)
    elseif cfg.glyph then glyph = cfg.glyph
    else glyph, device = waResolveKey(waUsingPad() and 22 or 38) end
    ui('keyClone', { show = true, glyph = glyph or 'E', device = device })
end)

--- Ends it with no result event, e.g. the car drove off or he walked away.
exports('CancelKeyCloneCheck', function()
    if not cloneActive then return end
    cloneEnd()
    ui('keyClone', { show = false })
end)

CreateThread(function()
    local last = GetGameTimer()
    while true do
        Wait(cloneActive and 0 or 250)
        local now = GetGameTimer()
        local dt = math.min(now - last, 100) / 1000.0
        last = now
        if cloneActive then
            for _, control in ipairs(CLONE_HELD) do DisableControlAction(0, control, true) end
            if IsDisabledControlJustPressed(0, 177) then
                cloneEnd('vice_hud:keyCloneCancel')
                ui('keyClone', { show = false })
            else
                local speed = CLONE_SPEEDS[math.min(clone.hits + 1, #CLONE_SPEEDS)]
                clone.pos = clone.pos + clone.dir * speed * dt
                if clone.pos >= 100 then clone.pos, clone.dir = 100, -1
                elseif clone.pos <= 0 then clone.pos, clone.dir = 0, 1 end

                if now - clone.startedAt >= CLONE_GRACE_MS and clonePressed() then
                    if math.abs(clone.pos - clone.target) <= CLONE_WINDOW * 0.5 then
                        clone.hits = clone.hits + 1
                        if clone.hits >= CLONE_HITS then
                            PlaySoundFrontend(-1, 'Hack_Success', CLONE_SOUNDS, true)
                            ui('keyCloneResult', { success = true })
                            cloneEnd('vice_hud:keyCloneResult', true)
                        else
                            PlaySoundFrontend(-1, 'Pin_Good', CLONE_SOUNDS, true)
                            cloneNewTarget()
                        end
                    else
                        clone.misses = clone.misses + 1
                        PlaySoundFrontend(-1, 'Pin_Bad', CLONE_SOUNDS, true)
                        if clone.misses >= CLONE_MISSES then
                            ui('keyCloneResult', { success = false })
                            cloneEnd('vice_hud:keyCloneAlarm')
                        else
                            ui('keyCloneMiss', {})
                        end
                    end
                end
                if cloneActive then
                    ui('keyCloneProgress', { pos = clone.pos, target = clone.target, window = CLONE_WINDOW, hits = clone.hits })
                end
            end
        end
    end
end)

RegisterCommand('hudkeyclone', function()
    exports.vice_hud:StartKeyCloneCheck({})
    print('^3[vice_hud]^7 /hudkeyclone — press E (Square / X on a pad) while the dot is in the pink window: 3 hits clone it, 3 misses are the alarm. Backspace backs out.')
end, false)
end -- close the do opened above local cloneActive

-- =============================================================================
-- Interact menu — Phase 1 of the ox_target-replacement project
-- =============================================================================
-- Just a data-driven option list. No targeting geometry, no raycast, no
-- zones — that engine, and any real migration of the 166 files this server
-- has calling ox_target today, is a separate, later project; reimplementing
-- all of that blind in one pass with no live game to test against was
-- explicitly ruled out. This resource has no idea what calls it.
--
-- Holds NUI focus while open — arrow keys / Enter / Escape drive the list —
-- released the same three ways /movehud's own focus is: on select/close,
-- on this resource (re)starting, and a watchdog in case whatever opened it
-- never tells it to close.

-- Wrapped in one do...end: this and the whole controller-support section
-- below it together add 14 top-level locals, all read/written only within
-- this combined region (nothing outside it references any of them). Lua's
-- 200-local-per-main-chunk cap is a hard PARSE-TIME limit — a script that
-- crosses it fails to load at all, silently, with nothing visible
-- server-side and only a client-console error to go on. A do...end block
-- lets these registers be reused once the block ends instead of staying
-- live for the rest of the file, which is what keeps client.lua under
-- that cap as it grows.
-- This panel used to be an NUI page with its own keyboard/controller polling
-- and SetNuiFocus juggling. ScaleformUI's UIMenu/MenuHandler owns all of
-- that itself now (input polling, Up/Down/Accept/Cancel, weapon-wheel/
-- attack/aim disabling while a menu is open) via the CreateThread loop
-- already running in vendor/ScaleformUI_Lua/src/ScaleformUI/mainScaleform.lua,
-- and reads controls natively rather than through NUI focus, so none of the
-- old SetNuiFocus/DisableControlAction/polling-thread machinery is needed
-- here any more.
do
local interactMenu = nil -- rebuilt fresh on every OpenInteractMenu call
-- true while THIS file is the one closing the menu (a select, or an explicit
-- CloseInteractMenu/releaseFocus) -- the old NUI version fired
-- vice_hud:interactClose ONLY for Cancel/Back, never for those, and
-- OnMenuClose below fires for every close path so it needs to tell them apart.
local suppressCloseEvent = false

-- Opaque value the current menu's OPENER passed to OpenInteractMenu, echoed
-- back on both events. Two callers (qbx_vehiclekeys and, as of the ox_target
-- migration, ox_target itself) can now both have a menu open across
-- different moments; without a token, a caller has no way to tell "was that
-- interactSelect/interactClose meant for MY menu" and a force-close-by-a-
-- new-opener used to look identical to nothing having happened at all --
-- the previous caller's own state (e.g. ox_target's uiMode) would go stale,
-- silently misattributing the NEXT select it saw to the wrong option. A
-- caller that doesn't pass a token gets nil back, same as before this
-- existed, so this is backward compatible with any caller ignoring it.
local currentToken = nil

-- ScaleformUI has no exact 'stamina'/'focus' badge -- these are the closest
-- built-in BadgeStyle icons (see vendor/ScaleformUI_Lua/src/Elements/Badge.lua)
-- until real custom icons are worth the runtime-texture-dict setup. 'health'
-- needs no substitute -- HEALTH_HEART is the exact icon for it, the same one
-- 'stamina' above only ever borrowed for lack of a better option.
local BADGE_MAP = {
    health  = BadgeStyle.HEALTH_HEART,
    stamina = BadgeStyle.HEALTH_HEART,
    focus   = BadgeStyle.STAR,
}

--[[ ---------------------------------------------------------------------------
     mz_textui-style reskin  --  BEGIN  (added by vice_hud; safe to delete, see
     git history for the pre-patch OpenInteractMenu)
     ---------------------------------------------------------------------------
     ScaleformUI's UIMenu is a compiled native scaleform, not an NUI page --
     there is no CSS here, so this can only push it AS CLOSE as its documented
     Lua API allows toward the naked-text, hard-outline look #prompts already
     uses for the single-option case (see this file's header comment and
     html/style.css's `.prompt`/`.glyph`, both of which credit the same
     reference textui by name). The banner image and the item list's own
     background panel are baked into the scaleform itself -- SetBannerColor
     only tints the banner, it does not remove it, and nothing in the
     documented API removes the list panel at all. What IS reachable:
       - HasInstructionalButtons(false): drops the bottom control-glyph bar,
         which is native GTA menu chrome mz_textui has none of.
       - MenuAlignment(RIGHT): anchors to the same side of the screen the
         single-option prompt and mz_textui itself both sit on, rather than
         the engine's left-aligned default -- so a player doesn't see the
         prompt jump from one corner to a completely different one depending
         on whether one option or several are on offer. True bottom-anchoring
         is not exposed by the API; the vertical position stays wherever
         ScaleformUI itself places a right-aligned menu.
       - Per-item HighlightColor: recoloured to the same live accent every
         other popup on this server already themes from (see resolveAccentColor
         below), so the one row a player is about to confirm reads as the
         same "accent means selected" language, not GTA's default blue
         highlight. There is no HighlightedTextColor (or even TextColor) in
         THIS Lua port despite both being documented -- only MainColor and
         HighlightColor exist on vendor/ScaleformUI_Lua's own UIMenuItem (see
         Items/_UIMenuItem.lua) -- so the text-on-highlight contrast is
         whatever ScaleformUI's compiled scaleform already does natively,
         same as every other UIMenu on this server.
     ]] --

--- Reads the same 'vice_hud:theme' state bag ox_lib/resource/client.lua and
--- (formerly) ox_target/client/vice_theme.lua already read -- personal
--- choice winning over the server-wide default, same convention as this
--- file's own theme.lua. Falls back to theme.lua's own DEFAULT.preset
--- ('earned') accent for the one tick before theme.lua's startup thread has
--- published anything yet.
local ACCENT_FALLBACK = '#5fd8c8'

local function resolveAccentColor()
    local ok, personal = pcall(function() return LocalPlayer.state['vice_hud:theme'] end)
    local t = (ok and type(personal) == 'table') and personal or GlobalState['vice_hud:theme']
    local hex = (type(t) == 'table' and type(t.accent) == 'string') and t.accent or ACCENT_FALLBACK
    return SColor.FromHex('#FF' .. hex:gsub('#', ''))
end
-- vice_hud: mz_textui-style reskin -- END (see below for the three more call
-- sites inside OpenInteractMenu itself) ---------------------------------

local function closeInteractMenuSilently()
    if interactMenu and interactMenu:Visible() then
        suppressCloseEvent = true
        interactMenu:Visible(false)
        suppressCloseEvent = false
    end
end

--- options: array of { label, badges: {'health'|'stamina'|'focus', ...}, selected }
--- selected (top-level, optional, 0-based): which row starts highlighted;
--- defaults to whichever option has selected=true, or the first one.
--- token (optional): opaque value echoed back on interactSelect/interactClose
--- so a caller can tell those events apart from another caller's menu (see
--- currentToken's comment above). Omit it and behaviour is exactly as before.
exports('OpenInteractMenu', function(options, selected, token)
    options = options or {}

    -- A caller opening over an already-open menu force-closes the PREVIOUS
    -- one -- that owner needs a real (non-suppressed) interactClose with ITS
    -- token so it resets instead of going stale, unlike the other
    -- closeInteractMenuSilently() call sites below (select/CloseInteractMenu/
    -- releaseFocus/onResourceStop), which are the current owner closing its
    -- own menu and already fire their own event or intentionally don't.
    if interactMenu and interactMenu:Visible() then
        local previousToken = currentToken
        suppressCloseEvent = true
        interactMenu:Visible(false)
        suppressCloseEvent = false
        TriggerEvent('vice_hud:interactClose', previousToken)
    end

    currentToken = token

    local startIndex = tonumber(selected)
    if startIndex == nil then
        startIndex = 0
        for i, o in ipairs(options) do
            if o.selected then startIndex = i - 1 break end
        end
    end

    -- Rebuilt on every open rather than reused: ScaleformUI menus are cheap
    -- to throw away, and a fresh menu means a caller changing `options`
    -- between calls can never see a stale item left over from the last one.
    -- Offset comes from Config.InteractMenu (ScaleformUI's 1280x720 space, see
    -- that block's comment). Read defensively so a config predating it still
    -- loads -- falling back to the old 0,0 top-of-screen placement rather than
    -- erroring on a nil index.
    local menuCfg = Config.InteractMenu or {}
    interactMenu = UIMenu.New('', '', menuCfg.offsetX or 0, menuCfg.offsetY or 0, false, '', '', false)
    interactMenu:CanPlayerCloseMenu(true)
    -- mz_textui-style reskin -- see this function's header comment above.
    interactMenu:MenuAlignment(MenuAlignment.RIGHT)
    interactMenu:HasInstructionalButtons(false)

    local accent = resolveAccentColor()

    for _, opt in ipairs(options) do
        local item = UIMenuItem.New(tostring(opt.label or ''), '')
        item:HighlightColor(accent)
        for _, badge in ipairs(opt.badges or {}) do
            local style = BADGE_MAP[badge]
            if style then item:LeftBadge(style) end
        end
        interactMenu:AddItem(item)
    end

    interactMenu.OnItemSelect = function(_, _, index)
        -- Old NUI version closed BEFORE firing the select event; keep that
        -- order in case a caller opens a new menu from inside its handler.
        closeInteractMenuSilently()
        -- ScaleformUI indices are 1-based; the public event contract here
        -- has always been 0-based (qbx_vehiclekeys already depends on it).
        TriggerEvent('vice_hud:interactSelect', index - 1, token)
    end
    interactMenu.OnMenuClose = function()
        -- Fires for EVERY close (Cancel/Back included) -- suppressCloseEvent
        -- is what keeps this matching the old contract of "only a Cancel
        -- fires interactClose".
        if not suppressCloseEvent then
            TriggerEvent('vice_hud:interactClose', token)
        end
    end

    interactMenu:Visible(true)
    interactMenu:CurrentSelection(startIndex + 1)

    -- Light rumble on open, matching ShowActionPrompt's own appear pulse
    -- (client.lua) so both textui pieces give the same "something just
    -- appeared" feedback. No sound here on purpose -- ScaleformUI's own
    -- menu-open cue already plays natively; adding vice_hud's would double up.
    --
    -- Invoked by hash, not the generated `SetControlShake` global -- see
    -- client.lua's promptRumble for why (confirmed nil live in-game despite
    -- being a real, long-standing native). This particular call site errored
    -- AFTER Visible(true) above had already run, so the menu was opened and
    -- then immediately torn down when the error propagated up through
    -- ox_target's driveUi and its pcall'd supervisor closed it again --
    -- looked like the menu never appeared at all.
    Citizen.InvokeNative(0x48B3886C1358D0D5, 0, 80, 15)
end)

exports('CloseInteractMenu', function()
    closeInteractMenuSilently()
end)

-- /hudfocus already broadcasts this to clear every focus-holding panel in
-- the resource, not just the editor — the interact menu is another one.
AddEventHandler('vice_hud:releaseFocus', function()
    closeInteractMenuSilently()
end)

RegisterCommand('hudinteract', function()
    exports.vice_hud:OpenInteractMenu({
        { label = 'Logger Beer' },
        { label = 'Lavazas Beer' },
        { label = 'Blitz Berry Smoothie', badges = { 'stamina', 'focus' } },
        { label = 'Blitz Green Smoothie', badges = { 'stamina' } },
        { label = 'Medkit', badges = { 'health' } },
    }, 0)
    print('^3[vice_hud]^7 /hudinteract — sample data. Arrows to move, Enter to pick, Esc to cancel.')
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    closeInteractMenuSilently()
end)
end -- close the do opened above
