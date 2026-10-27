-- Thin bridge to the NUI scoreboard. All the layout lives in html/.

local visible = false

--- @param state table|nil Match state from the server, or nil to hide the board
function BB.updateHud(state)
    if not state then
        if visible then
            visible = false
            SendNUIMessage({ action = 'hide' })
        end
        return
    end

    visible = true

    SendNUIMessage({
        action = 'update',
        data = {
            state     = state.state,
            score     = state.score,
            clock     = state.clock,
            countdown = state.countdown,
            players   = state.players,
            myTeam    = BB.myTeam,
            myId      = GetPlayerServerId(PlayerId()),
            result    = state.result,
            teams     = Config.Match.teams,
            scoreLimit = Config.Match.scoreLimit,
        },
    })
end

--- Floating "+2" over the hoop, so a basket reads even if you're not watching the board.
function BB.flashPoints(hoopId, points, clean)
    local hoop
    for _, candidate in ipairs(BB.hoops) do
        if candidate.id == hoopId then
            hoop = candidate
            break
        end
    end

    if not hoop then return end

    CreateThread(function()
        local text = ('+%s'):format(points)
        if clean then text = text .. '  ' .. Config.Text.swish end

        local finish = GetGameTimer() + 1800

        while GetGameTimer() < finish do
            local rise = 1.0 - (finish - GetGameTimer()) / 1800.0

            SetTextScale(0.0, 0.42)
            SetTextFont(4)
            SetTextColour(255, 205, 80, math.floor(255 * (1.0 - rise)))
            SetTextOutline()
            SetTextCentre(true)
            SetDrawOrigin(hoop.coords.x, hoop.coords.y, hoop.coords.z + 0.5 + rise * 0.8, 0)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(text)
            EndTextCommandDisplayText(0.0, 0.0)
            ClearDrawOrigin()

            Wait(0)
        end
    end)
end

-- A basket in a match: everyone in it sees the "+2".
RegisterNetEvent('gk_basketball:scoreFlash', function(hoopId, points, clean)
    BB.flashPoints(hoopId, points, clean)
end)

-- A basket of mine outside a match: client/look.lua says so.
RegisterNetEvent('gk_basketball:practiceBasket', function(hoopId, points, clean)
    BB.look.scored(hoopId, points, clean)
end)

--------------------------------------------------------------------------------
-- Ball sounds and spray
--------------------------------------------------------------------------------

-- Impact speed, in m/s, at which each sound is at full volume.
local FULL = { bounce = 6.0, dribble = 5.0, rim = 5.0, board = 6.0, net = 6.0, splash = 7.0, body = 6.0, catch = 5.0,
    squeak = 5.0 }

local function spray(x, y, z, strength)
    if not HasNamedPtfxAssetLoaded('core') then
        RequestNamedPtfxAsset('core')
        return
    end

    UseParticleFxAssetNextCall('core')
    StartParticleFxNonLoopedAtCoord('ent_sht_water', x, y, z, 0.0, 0.0, 0.0,
        BB.clamp(strength / 5.0, 0.5, 1.6), false, false, false)
end

--- Something happened to a ball at a point in the world. Heard from wherever the
--- camera is: quieter with distance, and to the side it is actually on.
--- @param strength number How hard, in m/s of impact
function BB.playFx(kind, x, y, z, strength)
    local sound = Config.Sound
    local cam = GetFinalRenderedCamCoord()
    local dx, dy, dz = x - cam.x, y - cam.y, z - cam.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

    if dist > sound.range then return end

    if kind == 'splash' then spray(x, y, z, strength) end

    if not sound.enabled then return end

    -- Camera's right-hand side, on the ground plane.
    local yaw = math.rad(GetFinalRenderedCamRot(2).z)
    local pan = dist > 0.5 and (dx * math.cos(yaw) + dy * math.sin(yaw)) / dist or 0.0

    local near = 1.0 / (1.0 + (dist / sound.falloff) ^ 2)
    local hard = BB.clamp(strength / (FULL[kind] or 6.0), 0.15, 1.0)

    -- The player's own effects-volume setting, 0 to 10.
    local setting = GetProfileSetting(300)
    local level = (setting and setting >= 0) and setting / 10.0 or 1.0

    SendNUIMessage({
        action = 'sfx',
        kind   = kind,
        volume = sound.volume * near * hard * level,
        pan    = pan * 0.85,

        -- Which recording, where there is a choice: how hard it was, and
        -- whether it happened under a roof (an arena rings; a street doesn't).
        hard   = hard,
        indoor = GetInteriorAtCoords(x, y, z) ~= 0,
    })
end

--------------------------------------------------------------------------------
-- Shoes
--------------------------------------------------------------------------------

--[[
    A hard stop or a sharp cut on a court is heard: a squeak on an indoor floor,
    a scrape outdoors. Mine only; everybody else's reach me the way a bounce
    does, from the game that made them.

    Read off how I am actually moving, a few times a second while there is a
    hoop anywhere near, so it costs nothing away from a court.
]]
CreateThread(function()
    local trail = {}        -- the last few { vx, vy, speed }, oldest first
    local quietUntil = 0

    while true do
        local wait = 1000
        local sound = Config.Sound

        if sound.enabled and sound.squeaks ~= false and #BB.nearbyHoops() > 0 then
            local ped = PlayerPedId()

            wait = 50

            if IsPedOnFoot(ped) and not IsPedRagdoll(ped) and not IsPedFalling(ped) then
                local v = GetEntityVelocity(ped)
                local speed = math.sqrt(v.x * v.x + v.y * v.y)
                local was = trail[1]
                local now = GetGameTimer()

                if was and #trail >= 3 and now >= quietUntil then
                    local hard = 0.0

                    -- Pulling up: a lot of pace gone in a sixth of a second.
                    if was.speed > 3.0 and was.speed - speed > 2.2 then
                        hard = math.max(hard, was.speed - speed)
                    end

                    -- Cutting: still moving, in a different direction.
                    if was.speed > 2.8 and speed > 2.0 then
                        local along = (was.vx * v.x + was.vy * v.y) / (was.speed * speed)

                        if along < 0.55 then hard = math.max(hard, 2.5 + (0.55 - along) * 3.0) end
                    end

                    if hard > 0.0 then
                        local at = GetEntityCoords(ped)

                        BB.playFx('squeak', at.x, at.y, at.z - 0.95, hard)
                        TriggerServerEvent('gk_basketball:fx', 'squeak', at.x, at.y, at.z - 0.95, hard)

                        quietUntil = now + 450
                    end
                end

                trail[#trail + 1] = { vx = v.x, vy = v.y, speed = speed }
                if #trail > 3 then table.remove(trail, 1) end
            else
                trail = {}
            end
        end

        Wait(wait)
    end
end)

-- The same, for a ball somebody else's game is simulating.
RegisterNetEvent('gk_basketball:fx', function(kind, x, y, z, strength)
    if type(kind) ~= 'string' or type(x) ~= 'number' then return end
    BB.playFx(kind, x, y, z, strength or 3.0)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SendNUIMessage({ action = 'hide' })
end)
