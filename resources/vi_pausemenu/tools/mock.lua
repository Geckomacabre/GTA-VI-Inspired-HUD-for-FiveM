-- A small FiveM for vi_pausemenu's client and server in one state: natives that record what was done, a scheduler for
-- CreateThread / Wait, NUI callbacks and messages, net events looped client <-> server, exports of the other resources.

function vector3(x, y, z) return { x = x, y = y, z = z } end

-- time and threads
Now = 0
local threads = {}
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = Now } end
Citizen = { CreateThread = CreateThread, Wait = function(ms) coroutine.yield(ms) end }
function Wait(ms) coroutine.yield(ms or 0) end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
function GetGameTimer() return Now end
Errors = {}
function Tick(ms)
    local list = threads
    threads = {}
    for i = 1, #list do
        local t = list[i]
        if coroutine.status(t.co) ~= 'dead' then
            if t.wake <= Now then
                local ok, res = coroutine.resume(t.co)
                if not ok then
                    Errors[#Errors + 1] = tostring(res)
                    print('THREAD ERROR: ' .. tostring(res))
                elseif coroutine.status(t.co) ~= 'dead' then
                    t.wake = Now + (res or 0)
                    threads[#threads + 1] = t
                end
            else
                threads[#threads + 1] = t
            end
        end
    end
    -- controls are "just pressed" for one frame
    JustPressed = {}
    PadHeld = {}
    Now = Now + (ms or 16)
end
function Frames(n) for _ = 1, n or 1 do Tick(16) end end
function Run(ms) local t = Now + ms while Now < t do Tick(16) end end

-- KVP
Kvp = {}
function GetResourceKvpString(k) return Kvp[k] end
function SetResourceKvp(k, v) Kvp[k] = v end
function DeleteResourceKvp(k) Kvp[k] = nil end

-- the player
function PlayerPedId() return 100 end
function PlayerId() return 0 end
function GetPlayerServerId() return 7 end
function GetPlayerName(id) return id == 0 and 'GeckoClient' or ('Player' .. tostring(id)) end
function GetActivePlayers() return { 0, 1 } end
function GetEntityCoords() return vector3(-1200.0, -1500.0, 4.0) end
function GetEntityHeading() return 90.0 end
-- the zone: Vespucci Beach, but for the ocean far to the west (no name there, as in the game)
ZoneAsked = false
function GetNameOfZone(x, y, z) ZoneAsked = { x, y, z } return x < -3000 and 'OCEANA' or 'BEACH' end
function GetLabelText(l) return l == 'BEACH' and 'Vespucci Beach' or 'NULL' end
function GetSafeZoneSize() return 0.95 end

-- blips, by sprite: { x, y, display, hud colour }; GetFirstBlipInfoId / GetNextBlipInfoId walk one sprite's list
Blips = {}
HudColours = { [3] = { 93, 182, 229 }, [5] = { 114, 204, 114 } }
local blipWalk = {}
local function blipId(sprite, i) return sprite * 1000 + i end
local function blipOf(id) local list = Blips[id // 1000] return list and list[id % 1000] end
function GetFirstBlipInfoId(sprite)
    blipWalk[sprite] = 1
    return Blips[sprite] and Blips[sprite][1] and blipId(sprite, 1) or 0
end
function GetNextBlipInfoId(sprite)
    blipWalk[sprite] = (blipWalk[sprite] or 0) + 1
    local i = blipWalk[sprite]
    return Blips[sprite] and Blips[sprite][i] and blipId(sprite, i) or 0
end
function DoesBlipExist(id) return blipOf(id) ~= nil end
function GetBlipInfoIdDisplay(id) return blipOf(id)[3] end
function GetBlipInfoIdCoord(id) local b = blipOf(id) return vector3(b[1], b[2], 30.0) end
function GetBlipHudColour(id) return blipOf(id)[4] or 0 end
function GetHudColour(c) local t = HudColours[c] or { 255, 255, 255 } return t[1], t[2], t[3], 255 end
-- the waypoint: a sprite 8 blip of its own
Waypoint = false
function IsWaypointActive() return Waypoint ~= false end
function SetNewWaypoint(x, y) Waypoint = { x, y } Blips[8] = { { x, y, 4 } } end
function SetWaypointOff() Waypoint = false Blips[8] = nil end
function GetClockDayOfWeek() return 6 end
function GetClockHours() return 9 end
function GetClockMinutes() return 5 end
function GetHashKey(s) return 'hash:' .. s end
function print(...) local t = {} for i = 1, select('#', ...) do t[#t + 1] = tostring(select(i, ...)) end Printed[#Printed + 1] = table.concat(t, ' ') end
Printed = {}

-- recording
Recording = false
function IsRecording() return Recording end
function StartRecording(mode) assert(mode == 1) Recording = true end
function StopRecordingAndSaveClip() Recording = false Saved = Saved + 1 end
function Citizen.InvokeNative() error('InvokeNative should not be needed: the names exist') end

-- resources and their exports
ResourceStates = { qbx_core = 'started', vice_hud = 'started', gen7_map = 'started', vi_crashcam = 'started', vi_radio = 'started' }
function GetResourceState(name) return ResourceStates[name] or 'missing' end
PlayerData = {
    citizenid = 'ABC123', charinfo = { firstname = 'Lucia', lastname = 'Caminos' },
    job = { label = 'Mechanic', onduty = true, grade = { name = 'Apprentice' } },
    money = { cash = 1250, bank = 48900 }, metadata = { hunger = 82.4, thirst = 64 },
}
MapMode = 'auto'
MinimapOnFoot = true
Muted = false
CrashCam = 'untouched'
Saved = 0
source = 0
local function api(t)
    -- the first argument is the resource's own table (a `exports.res:fn()` call); anything else is a mistake
    local proxy = {}
    for k, fn in pairs(t) do
        proxy[k] = function(self, ...)
            assert(self == proxy, 'export ' .. k .. ' called without its resource table as self')
            return fn(...)
        end
    end
    return proxy
end
exports = {
    qbx_core = api({ GetPlayerData = function() return PlayerData end }),
    vice_hud = api({
        GetSkill = function(id)
            if id == 'stamina' then return { id = id, xp = 1000, level = 42, into = 30, need = 100, frac = 0.3 } end
            if id == 'wheelie' then return { id = id, xp = 1, level = 100, into = 0, need = 0, frac = 1 } end
            return { id = id, xp = 0, level = 0, into = 0, need = 50, frac = 0 }
        end,
        GetMinimapOnFoot = function() return MinimapOnFoot end,
        SetMinimapOnFoot = function(v) MinimapOnFoot = v end,
    }),
    gen7_map = api({ GetMapMode = function() return MapMode end, SetMapMode = function(v) MapMode = v end }),
    vi_crashcam = api({ SetCrashCamEnabled = function(v) CrashCam = v end }),
    vi_radio = api({ IsMuted = function() return Muted end, SetMuted = function(v) Muted = v end }),
}

-- state bags
StateBag = {}
LocalPlayer = { state = { set = function(_, k, v, rep) assert(rep == false) StateBag[k] = v end } }

-- NUI
Nui = { focus = false, messages = {} }
function SetNuiFocus(a, b) Nui.focus = a and b end
function SetNuiFocusKeepInput(v) Nui.keep = v end
function SendNUIMessage(m) Nui.messages[#Nui.messages + 1] = m end
local nuiCallbacks = {}
function RegisterNUICallback(name, fn) nuiCallbacks[name] = fn end
-- the page calling back: -> what the client answered
function NuiCall(name, data)
    local answer
    nuiCallbacks[name](data, function(v) answer = v end)
    return answer
end
function LastMessage(kind)
    for i = #Nui.messages, 1, -1 do
        if Nui.messages[i].type == kind then return Nui.messages[i] end
    end
end

-- the screen
Blur = 0
function TriggerScreenblurFadeIn() Blur = Blur + 1 end
function TriggerScreenblurFadeOut() Blur = Blur - 1 end
Sounds = {}
function PlaySoundFrontend(_, name, set) Sounds[#Sounds + 1] = name end

-- controls
JustPressed = {}
Disabled = {}
function IsControlJustPressed(_, c) return JustPressed[c] == true end
function DisableControlAction(_, c) Disabled[c] = Now end
function Press(c) JustPressed[c] = true end
-- a pad: the keyboard unless UsingPad is set; a held control stays held for the frame it is set in
UsingPad = false
PadHeld = {}
Stick = { x = 0.0, y = 0.0, lt = 0.0, rt = 0.0 }
function IsUsingKeyboard() return not UsingPad end
function IsDisabledControlJustPressed(_, c) return JustPressed[c] == true end
function IsDisabledControlPressed(_, c) return PadHeld[c] == true or JustPressed[c] == true end
function GetDisabledControlNormal(_, c)
    if c == 218 then return Stick.x elseif c == 219 then return Stick.y
    elseif c == 207 then return Stick.lt elseif c == 208 then return Stick.rt end
    return 0.0
end

-- the game's own menu
Pause = { active = false, setTrueCount = 0 }
function SetPauseMenuActive(v) Pause.active = v if v then Pause.setTrueCount = Pause.setTrueCount + 1 end end
Frontend = { menu = nil, ready = false, kicked = 0 }
function ActivateFrontendMenu(hash, toggle, comp)
    assert(toggle == false and comp == -1)
    Frontend.menu = hash
    Frontend.ready = true
end
function IsFrontendReadyForControl() return Frontend.ready end
function PauseMenuceptionTheKick() Frontend.kicked = Frontend.kicked + 1 end
function SetFrontendActive(v) if not v then Frontend.menu = nil end end
Header = {}
local headerCall
function BeginScaleformMovieMethodOnFrontendHeader(m) headerCall = { m } return true end
function ScaleformMovieMethodAddParamBool(v) headerCall[#headerCall + 1] = v end
function ScaleformMovieMethodAddParamTextureNameString(v) headerCall[#headerCall + 1] = v end
function EndScaleformMovieMethod() Header[#Header + 1] = headerCall end

-- events: client and server in one place, `source` set for the server's
local handlers = {}
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {} table.insert(handlers[name], fn) end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
ServerCalls = {}
function TriggerServerEvent(name, ...)
    ServerCalls[#ServerCalls + 1] = { name, ... }
    local before = source
    source = 7
    TriggerEvent(name, ...)
    source = before
end
function TriggerClientEvent(name, target, ...)
    assert(target == 7 or target == -1, 'client event to ' .. tostring(target))
    TriggerEvent(name, ...)
end
Commands = {}
function RegisterCommand(name, fn) Commands[name] = fn end

-- the pedheadshot slot (one, as in the game: registering while it is held fails)
Headshot = { registered = 0, unregistered = 0, held = false, ready = true, valid = true }
function RegisterPedheadshotTransparent(ped)
    assert(ped == 100, 'headshot of the player ped')
    assert(not Headshot.held, 'headshot registered while the slot was still held')
    Headshot.held = true
    Headshot.registered = Headshot.registered + 1
    return 5
end
function IsPedheadshotReady(h) return Headshot.ready end
function IsPedheadshotValid(h) return Headshot.valid end
function GetPedheadshotTxdString(h) return 'pedmugshot_01' end
function UnregisterPedheadshot(h)
    assert(h == 5)
    Headshot.held = false
    Headshot.unregistered = Headshot.unregistered + 1
end

-- server
Convars = { sv_projectName = 'Upstate Mafia', sv_hostname = 'Upstate Mafia!' }
function GetConvar(k, default) return Convars[k] or default end
function GetPlayers() return { '7', '3' } end
Dropped = {}
function DropPlayer(id, why) Dropped[#Dropped + 1] = { id, why } end
Http = {}
function PerformHttpRequest(url, cb, method, body, headers) Http[#Http + 1] = { url = url, method = method, body = body } end
json = { encode = function(t) return t end }
