-- Drift scoring inside the car meet.
--
-- Carried over from um_carmeet's cl_carmeet.lua. Two changes: the inline
-- DrawRect/DrawText HUD is now an SKHud widget (so it sits in the shared
-- bottom-centre band and stays clear of um_hud), and the "am I at the meet"
-- check is shared with carmeet_c.lua instead of duplicating the distance test.
--
-- Scoring model is unchanged: points accrue per frame from speed x slip angle
-- x a combo multiplier that grows the longer a single drift is held. Only the
-- highest reward threshold crossed in a session pays out, once.

if not (Config.Modules.carmeet and Config.Modules.drift) then return end

local driftPoints    = 0
local driftCombo     = 1.0
local driftActive    = false
local driftTimer     = 0
local sessionPts     = 0
local driftRewarded  = false
local wasNearCarMeet = false

SKHud.register('drift', function(data)
    local a = SKHud.Anchor.bottomCentre
    SKHud.Panel(a.x, a.y, 0.24, 0.075, SKHud.Palette.panel)
    SKHud.Text(('%d  pts'):format(data.points), a.x, a.y - 0.025, 0.55, SKHud.Palette.accent, true, 7)
    SKHud.Text(('x%.1f  COMBO'):format(data.combo), a.x, a.y + 0.015, 0.32, SKHud.Palette.textDim, true)
end)

local function endDrift()
    if not driftActive then return end
    if driftPoints > 200 then
        lib.notify({
            title       = 'Drift',
            description = ('+%d pts  x%.1f'):format(driftPoints, driftCombo),
            type        = 'inform',
            duration    = 2500,
        })
    end
    driftActive = false
    driftPoints = 0
    driftCombo  = 1.0
    SKHud.clear('drift')
end

local function resetDriftSession()
    sessionPts    = 0
    driftRewarded = false
    driftActive   = false
    driftPoints   = 0
    driftCombo    = 1.0
    SKHud.clear('drift')
end

CreateThread(function()
    while true do
        Wait(0)

        local near = SKCarMeet.isInside()
        if not near then
            if wasNearCarMeet then resetDriftSession() end
            wasNearCarMeet = false
            Wait(1000)
            goto continue
        end
        wasNearCarMeet = true

        local veh = GetVehiclePedIsIn(cache.ped, false)
        if veh == 0 or not IsThisModelACar(GetEntityModel(veh)) then
            if driftActive then
                driftActive = false
                driftPoints = 0
                driftCombo  = 1.0
                SKHud.clear('drift')
            end
            Wait(200)
            goto continue
        end

        local speed = GetEntitySpeed(veh)
        if speed < Config.Drift.minSpeed then
            endDrift()
            goto continue
        end

        -- Slip angle: angle between the vehicle's facing vector and the
        -- direction it is actually travelling.
        local vel = GetEntityVelocity(veh)
        local hRad = math.rad(-GetEntityHeading(veh))
        local fwdX, fwdY = math.sin(hRad), math.cos(hRad)
        local vLen = math.sqrt(vel.x^2 + vel.y^2)
        local angle = 0.0
        if vLen > 0.5 then
            local dot = math.max(-1.0, math.min(1.0, (vel.x / vLen) * fwdX + (vel.y / vLen) * fwdY))
            angle = math.deg(math.acos(dot))
        end

        if angle >= Config.Drift.minAngle then
            if not driftActive then
                driftActive = true
                driftTimer  = GetGameTimer()
                driftCombo  = 1.0
            end
            local elapsed = (GetGameTimer() - driftTimer) / 1000.0
            driftCombo = math.min(6.0, 1.0 + elapsed * 0.4)
            local framePts = math.floor(speed * angle * 0.003 * driftCombo)
            driftPoints = driftPoints + framePts
            sessionPts  = sessionPts  + framePts
            SKHud.set('drift', { points = driftPoints, combo = driftCombo })
        else
            endDrift()
        end

        -- Highest threshold crossed pays out once per session.
        if not driftRewarded then
            local reward = 0
            for _, tier in ipairs(Config.Drift.rewards) do
                if sessionPts >= tier.points then reward = tier.cash end
            end
            if reward > 0 then
                driftRewarded = true
                TriggerServerEvent('sk_streetkings:carmeet:driftReward', sessionPts, reward)
            end
        end

        ::continue::
    end
end)
