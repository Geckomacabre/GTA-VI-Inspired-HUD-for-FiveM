--[[
    vice_hud — awareness:  what decides which of the wanted tells light when
    fenix-police is not running. The police memory (what a cop actually saw)
    and the "fired recently" clock the weapon tell reads.

    Ported from FBICat's single-player GTA6Hud (a ScriptHookVDotNet mod) on
    2026-10-18. Neither draws anything: they only choose between the tells
    the page already has, which stay exactly as the reference shows them.

    Its own chunk for the reason at the top of client_overlays.lua (Lua's
    200-top-level-locals limit). It needs nothing from client.lua; client.lua
    reads its two globals, LastShotAt and ViceWantedMemory.
]]

-- =============================================================================
-- Fired recently
-- =============================================================================
-- GetGameTimer() of the player's last shot. The weapon tell lights only for a
-- gun the police have reason to know about -- one fired in the last
-- Config.WantedTells.weaponMemoryMs -- rather than for anything merely held
-- (getWantedTells in client.lua). IsPedShooting is true for the one frame a
-- shot leaves the barrel, so it has to be polled every frame; the 250 ms main
-- loop misses most of them. Idles at 250 ms while unarmed.
-- Not `local`: client.lua reads it, and a global costs it nothing against the
-- 200-local cap.
LastShotAt = -1e9

CreateThread(function()
    while true do
        local ped = cache.ped or PlayerPedId()
        if IsPedArmed(ped, 4) then
            Wait(0)
            if IsPedShooting(ped) then LastShotAt = GetGameTimer() end
        else
            Wait(250)
        end
    end
end)

-- =============================================================================
-- Police memory (the wanted tells' fallback)
-- =============================================================================
-- From the single-player GTA6Hud's PoliceMemory. Used by getWantedTells() in
-- client.lua only when fenix-police is NOT running; before this, that path
-- simply lit the clothing and face tells for the whole of any wanted level,
-- whether or not anyone had seen you, which told the player nothing.
--
-- note() is called while a cop has line of sight (wantedState's fallback in
-- client.lua). It records what they saw: the outfit, whether the face was
-- uncovered, and the plate of the vehicle you were in. tells() then lights
--   outfit   while what you wear still matches what they saw
--   face     while they have seen your face and it is still uncovered
--   vehicle  while you sit in the vehicle with that plate
-- so changing clothes, masking up or swapping cars visibly works. Plates, not
-- models: a second car of the same model is not the one they saw. clear()
-- when the wanted level is gone. (The original also remembered across wanted
-- levels for in-game hours and could re-want you on sight; that is police
-- gameplay, fenix-police's job, not the HUD's.)
-- Global: client.lua reads it, and this file is its own chunk.
do
-- The original's set minus component 1, the mask: a mask is the face tell's
-- business, and counting it here too meant masking up also "changed your
-- clothes" in the police's eyes.
local OUTFIT_COMPONENTS = { 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local OUTFIT_PROPS = { 0, 1 }
local mem = nil

local function outfitSig(ped)
    local parts = {}
    for _, c in ipairs(OUTFIT_COMPONENTS) do
        parts[#parts + 1] = GetPedDrawableVariation(ped, c) .. ':' .. GetPedTextureVariation(ped, c)
    end
    for _, p in ipairs(OUTFIT_PROPS) do
        parts[#parts + 1] = 'p' .. GetPedPropIndex(ped, p) .. ':' .. GetPedPropTextureIndex(ped, p)
    end
    return table.concat(parts, ',')
end

-- Component 1 is the mask slot; anything but the empty drawable covers the face.
local function faceHidden(ped) return GetPedDrawableVariation(ped, 1) > 0 end

local function plateOf(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then return nil end
    local plate = GetVehicleNumberPlateText(veh)
    if not plate then return nil end
    plate = plate:gsub('^%s+', ''):gsub('%s+$', ''):upper()
    return plate ~= '' and plate or nil
end

ViceWantedMemory = {
    note = function(ped)
        mem = mem or {}
        mem.outfit = outfitSig(ped)
        if not faceHidden(ped) then mem.faceSeen = true end
        mem.plate = plateOf(ped) or mem.plate
    end,
    tells = function(ped)
        if not mem then return nil end
        local plate = mem.plate and plateOf(ped)
        return {
            outfit = mem.outfit ~= nil and mem.outfit == outfitSig(ped),
            face = mem.faceSeen == true and not faceHidden(ped),
            vehicle = plate ~= nil and plate == mem.plate,
        }
    end,
    clear = function() mem = nil end,
}
end
