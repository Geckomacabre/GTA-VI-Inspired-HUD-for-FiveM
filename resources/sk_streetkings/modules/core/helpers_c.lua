-- Asset loading helpers, ported near-verbatim from streetkings
-- modules/core/sk_helpers_c.lua. Pure natives, no framework coupling.

SK = {}

-- Upstream declared this global in modules/freeroam/camera_c.lua, its custom
-- chase camera, which is not ported (the vanilla GTA camera is used instead).
-- Several ported modules still read and write it to mean "a scripted camera is
-- running, stand down" — speed cameras, police, and the stunt devtool. Globals
-- in FiveM are resource-scoped, so the upstream name is kept as-is rather than
-- rewriting every call site.
Cinematic = false

-- ── Custom audio ────────────────────────────────────────────────────────────
--
-- StreetKings' own sounds live in a separate `streetkings_audio` resource
-- (github.com/streetkings-fivem/streetkings_audio), which registers the
-- `sk_soundset` soundset from a custom wavepack. It is optional here: install
-- it and the original sounds play, leave it out and each one falls back to the
-- closest stock equivalent. It is deliberately NOT a manifest dependency —
-- a missing dependency stops the whole resource, and a missing shutter click
-- is not worth that.
--
-- Upstream only ever requested the audio bank from police_c, which is off by
-- default here, so the request is done centrally instead.

local AUDIO_RESOURCE = 'streetkings_audio'
local AUDIO_BANK     = 'audiodirectory/custom_sounds'
local AUDIO_SOUNDSET = 'sk_soundset'

---@type table<string, [string, string]>
local FALLBACK_SOUNDS = {
    speedcamera    = { 'Camera_Shoot', 'Phone_Soundset_Franklin' },
    radar_detector = { 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS' },
}

local customAudioReady = false

CreateThread(function()
    -- Both resources come up from the same `ensure [Scripts]`, so the audio
    -- resource may not have started yet when this runs. Give it a window
    -- rather than deciding on a single check.
    local waitUntil = GetGameTimer() + 20000
    while GetResourceState(AUDIO_RESOURCE) ~= 'started' do
        if GetGameTimer() > waitUntil then return end -- not installed; stock sounds
        Wait(500)
    end

    local deadline = GetGameTimer() + 15000
    while not RequestScriptAudioBank(AUDIO_BANK, false) do
        if GetGameTimer() > deadline then
            lib.print.warn(('%s is running but its audio bank would not load; using stock sounds.')
                :format(AUDIO_RESOURCE))
            return
        end
        Wait(100)
    end

    customAudioReady = true
end)

--- Plays one of StreetKings' named sounds, or its stock stand-in.
---@param name string a sound name from sk_soundset
function SK.PlaySound(name)
    if customAudioReady then
        PlaySoundFrontend(-1, name, AUDIO_SOUNDSET, true)
        return
    end

    local fallback = FALLBACK_SOUNDS[name]
    if fallback then
        PlaySoundFrontend(-1, fallback[1], fallback[2], true)
    end
end

-- ── Blips ───────────────────────────────────────────────────────────────────

local registeredCategories = {}

--- Creates a blip from a `Config.Blips` entry, so sprite/colour/range choices
--- live in config rather than scattered through the modules.
---
--- The `shortRange` flag is the important one: true means the blip is always on
--- the pause map but only appears on the minimap when the player is near it.
--- False pins it to the edge of the minimap from anywhere in the city, which is
--- only wanted for an active objective.
---
---@param spec table an entry from Config.Blips
---@param target vector3|integer world coords, or an entity handle to attach to
---@param label? string overrides spec.label
---@return integer blip
function SK.CreateBlip(spec, target, label)
    local blip
    if type(target) == 'number' then
        blip = AddBlipForEntity(target)
    else
        blip = AddBlipForCoord(target.x, target.y, target.z)
    end

    SetBlipSprite(blip, spec.sprite)
    SetBlipColour(blip, spec.colour)
    SetBlipScale(blip, spec.scale or 1.0)
    SetBlipAsShortRange(blip, spec.shortRange ~= false)

    if spec.category then
        if spec.categoryLabel and not registeredCategories[spec.category] then
            registeredCategories[spec.category] = true
            AddTextEntry(('BLIP_CAT_%d'):format(spec.category), spec.categoryLabel)
        end
        SetBlipCategory(blip, spec.category)
    end

    local name = label or spec.label
    if name then
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(name)
        EndTextCommandSetBlipName(blip)
    end

    return blip
end

---@param model string|number
---@param timeout? integer ms before giving up (default 5000)
---@return integer|nil hash
function SK.LoadModel(model, timeout)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeout or 5000)
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(0)
    end
    return hash
end

---@param model string|number
function SK.UnloadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    SetModelAsNoLongerNeeded(hash)
end

---@param dict string
---@param timeout? integer ms before giving up (default 3000)
---@return boolean
function SK.LoadAnimDict(dict, timeout)
    if type(dict) ~= 'string' or dict == '' then return false end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + (timeout or 3000)
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end
    return true
end

---@param set string
---@param timeout? integer ms before giving up (default 3000)
---@return boolean
function SK.LoadAnimSet(set, timeout)
    if type(set) ~= 'string' or set == '' then return false end
    RequestAnimSet(set)
    local deadline = GetGameTimer() + (timeout or 3000)
    while not HasAnimSetLoaded(set) do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end
    return true
end

---@param asset string
---@param timeout? integer ms before giving up (default 3000)
---@return boolean
function SK.LoadPtfxAsset(asset, timeout)
    if type(asset) ~= 'string' or asset == '' then return false end
    RequestNamedPtfxAsset(asset)
    local deadline = GetGameTimer() + (timeout or 3000)
    while not HasNamedPtfxAssetLoaded(asset) do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end
    return true
end

---@param vehicle integer
---@return string
function SK.GetVehicleModelLabel(vehicle)
    if not vehicle or vehicle == 0 then return '' end
    local hash = GetEntityModel(vehicle)
    local gxt = GetDisplayNameFromVehicleModel(hash)
    if not gxt or gxt == '' or gxt == 'CARNOTFOUND' then return '' end
    local label = GetLabelText(gxt)
    if not label or label == 'NULL' then return gxt end
    return label
end

--- Waits until the local player has control and is not in a cutscene/fade.
---@param timeout? integer
---@return boolean
function SK.WaitForControl(timeout)
    local deadline = GetGameTimer() + (timeout or 10000)
    while not NetworkIsSessionStarted() or IsPlayerSwitchInProgress() do
        if GetGameTimer() > deadline then return false end
        Wait(50)
    end
    return true
end

exports('LoadModel', SK.LoadModel)
exports('UnloadModel', SK.UnloadModel)
exports('LoadAnimDict', SK.LoadAnimDict)
exports('LoadAnimSet', SK.LoadAnimSet)
exports('LoadPtfxAsset', SK.LoadPtfxAsset)
