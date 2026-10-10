-- SKWaypoint shim.
--
-- StreetKings' waypoints module (modules/waypoints/waypoints_c.lua, ~940 lines)
-- renders floating 3D signpost panels by pooling DUI surfaces backed by an HTML
-- page. That page is part of the gamemode UI shell that is not carried over, so
-- the same public API (Create/Update/Remove/RemoveAll/Get/GetAll) is reproduced
-- here on top of native world markers plus an optional map blip.
--
-- Ported modules (repair stations, race discovery, invites) call this without
-- knowing the difference.

SKWaypoint = SKWaypoint or {}

local waypoints = {}
local nextId    = 1
local rendering = false

local DEFAULTS = {
    color      = '#f1e542', -- server accent
    size       = 1.0,
    maxRender  = 120.0,
    fadeStart  = 80.0,
    markerType = 21,        -- upside-down cone
    bobUpDown  = true,
}

---@param hex string
---@return integer, integer, integer
local function hexToRgb(hex)
    if type(hex) ~= 'string' then return 241, 229, 66 end
    hex = hex:gsub('#', '')
    if #hex ~= 6 then return 241, 229, 66 end
    return tonumber(hex:sub(1, 2), 16) or 241,
           tonumber(hex:sub(3, 4), 16) or 229,
           tonumber(hex:sub(5, 6), 16) or 66
end

local function toVec3(v)
    if type(v) == 'vector3' then return v end
    if type(v) == 'vector4' then return vec3(v.x, v.y, v.z) end
    if type(v) == 'table' then
        if v.x then return vec3(v.x, v.y, v.z) end
        if v[1] then return vec3(v[1], v[2], v[3]) end
    end
    return vec3(0.0, 0.0, 0.0)
end

local function startRendering()
    if rendering then return end
    rendering = true

    CreateThread(function()
        while next(waypoints) do
            local playerCoords = GetEntityCoords(cache.ped)
            local sleep = 500

            for _, wp in pairs(waypoints) do
                local dist = #(playerCoords - wp.coords)
                local maxRender = wp.maxRender or DEFAULTS.maxRender

                if dist <= maxRender then
                    sleep = 0
                    local fadeStart = wp.fadeStart or DEFAULTS.fadeStart
                    local alpha = 200
                    if dist > fadeStart then
                        alpha = math.floor(200 * (1.0 - ((dist - fadeStart) / (maxRender - fadeStart))))
                    end

                    if alpha > 0 then
                        local size = (wp.size or DEFAULTS.size)
                        DrawMarker(
                            wp.markerType or DEFAULTS.markerType,
                            wp.coords.x, wp.coords.y, wp.coords.z + 1.0,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            size, size, size,
                            wp.r, wp.g, wp.b, alpha,
                            wp.bobUpDown ~= false, true, 2, false, nil, nil, false
                        )

                        -- Label only inside a tight radius, so a dense set of
                        -- waypoints does not spam text across the screen.
                        if wp.label and dist < 25.0 then
                            local onScreen, sx, sy = World3dToScreen2d(wp.coords.x, wp.coords.y, wp.coords.z + 2.2)
                            if onScreen then
                                SKHud.Panel(sx, sy, 0.016 + (#wp.label * 0.0072), 0.026, SKHud.Palette.panelDark)
                                SKHud.Text(wp.label, sx, sy - 0.011, 0.32, { wp.r, wp.g, wp.b, 255 }, true)
                            end
                        end
                    end
                end
            end

            Wait(sleep)
        end

        rendering = false
    end)
end

---@param data { coords: vector3|table, label: string?, color: string?, size: number?, blip: table?, maxRender: number?, fadeStart: number?, markerType: integer?, bobUpDown: boolean? }
---@return integer id
function SKWaypoint.Create(data)
    local id = nextId
    nextId = nextId + 1

    local r, g, b = hexToRgb(data.color or DEFAULTS.color)
    local wp = {
        id         = id,
        coords     = toVec3(data.coords),
        label      = data.label,
        color      = data.color or DEFAULTS.color,
        r = r, g = g, b = b,
        size       = data.size or DEFAULTS.size,
        maxRender  = data.maxRender or DEFAULTS.maxRender,
        fadeStart  = data.fadeStart or DEFAULTS.fadeStart,
        markerType = data.markerType or DEFAULTS.markerType,
        bobUpDown  = data.bobUpDown,
    }

    if data.blip then
        local blip = AddBlipForCoord(wp.coords.x, wp.coords.y, wp.coords.z)
        SetBlipSprite(blip, data.blip.sprite or 1)
        SetBlipColour(blip, data.blip.color or 5)
        SetBlipScale(blip, data.blip.scale or 0.8)
        SetBlipAsShortRange(blip, data.blip.shortRange ~= false)
        if data.blip.category then SetBlipCategory(blip, data.blip.category) end
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(data.blip.name or wp.label or 'Waypoint')
        EndTextCommandSetBlipName(blip)
        wp.blip = blip
    end

    waypoints[id] = wp
    startRendering()
    return id
end

---@param id integer
function SKWaypoint.Remove(id)
    local wp = waypoints[id]
    if not wp then return end
    if wp.blip and DoesBlipExist(wp.blip) then RemoveBlip(wp.blip) end
    waypoints[id] = nil
end

function SKWaypoint.RemoveAll()
    for id in pairs(waypoints) do SKWaypoint.Remove(id) end
end

---@param id integer
---@param data table partial fields to merge
function SKWaypoint.Update(id, data)
    local wp = waypoints[id]
    if not wp or type(data) ~= 'table' then return end

    if data.color then
        wp.color = data.color
        wp.r, wp.g, wp.b = hexToRgb(data.color)
    end
    if data.coords then wp.coords = toVec3(data.coords) end
    if data.label ~= nil then wp.label = data.label end
    if data.size then wp.size = data.size end
end

---@param id integer
---@return table|nil
function SKWaypoint.Get(id)
    return waypoints[id]
end

---@return table
function SKWaypoint.GetAll()
    return waypoints
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then SKWaypoint.RemoveAll() end
end)
