SKHangoutZones = {}

SKHangoutZones.ZONE_ENTER_FADE_MS   = 500
SKHangoutZones.ZONE_EXIT_FADE_MS    = 500
SKHangoutZones.BLACKOUT_MS          = 700
SKHangoutZones.INTERACT_DISTANCE    = 3.0
SKHangoutZones.WAYPOINT_MAX_RENDER  = 250.0

---@class HangoutInterior
---@field ipl string          IPL to request ('' if none)
---@field interiorId number|nil  Known interior ID (use instead of GetInteriorAtCoords)
---@field spawn vector4       Interior spawn position + heading
---@field exit vector4        Interior exit marker position + heading
---@field entranceCoords vector3  World entrance marker position
---@field entranceHeading number  Heading for entrance marker

---@class HangoutZone
---@field id string
---@field name string
---@field description string
---@field waypointColor string
---@field waypointIcon string
---@field waypointCoords vector3|nil  Custom waypoint/blip position (auto-calculated if nil)
---@field poly vector3[]       Polygon vertices for the passive zone
---@field minZ number
---@field maxZ number
---@field interior HangoutInterior|nil

local function zone(id, name, description, waypointColor, waypointIcon, waypointCoords, poly, minZ, maxZ, interior)
    return {
        id              = id,
        name            = name,
        description     = description,
        waypointColor   = waypointColor or '#00d474',
        waypointIcon    = waypointIcon or 'house',
        waypointCoords  = waypointCoords,
        poly            = poly,
        minZ            = minZ,
        maxZ            = maxZ,
        interior        = interior,
    }
end

SKHangoutZones.CATALOG = {
    zone(
        'legion_square_parking',
        'Legion Square Parking',
        'A chill spot near Legion Square. No fighting allowed.',
        '#00d474',
        'house',
        vector3(233.0132, -786.9882, 30.6339),
        {
            vector3(199.1607, -806.2891, 30.0),
            vector3(229.1510, -723.6052, 30.0),
            vector3(275.2454, -740.5149, 30.0),
            vector3(245.1001, -823.1705, 30.0),
        },
        20.0,
        45.0,
        nil
    ),

    zone(
        'record_a_records',
        'Record A Records',
        'Dr. Dre\'s recording studio. Hang out and chill.',
        '#e040fb',
        'house',
        vector3(-852.1227, -217.3336, 37.1750),
        nil,
        nil,
        nil,
        {
            ipl             = '',
            interiorId      = 286977,
            spawn           = vector4(-1021.8349, -92.3000, -99.4031, 358.6079),
            exit            = vector4(-1021.8349, -92.3000, -99.4031, 178.6079),
            entranceCoords  = vector3(-852.1227, -217.3336, 37.1750),
            entranceHeading = 297.1514,
        }
    ),
}

--- Get the center of a zone polygon for waypoints / blips.
--- Interior-only zones (record_a_records) carry no poly, so fall back to the
--- explicit waypointCoords or the interior entrance rather than dividing by
--- zero on an empty vertex list.
---@param z HangoutZone
---@return vector3
function SKHangoutZones.getCenter(z)
    if z.waypointCoords then return z.waypointCoords end

    if not z.poly or #z.poly == 0 then
        return z.interior and z.interior.entranceCoords or vector3(0.0, 0.0, 0.0)
    end

    local cx, cy, cz = 0.0, 0.0, ((z.minZ or 0.0) + (z.maxZ or 0.0)) / 2.0
    for _, v in ipairs(z.poly) do
        cx = cx + v.x
        cy = cy + v.y
    end
    cx = cx / #z.poly
    cy = cy / #z.poly
    return vector3(cx, cy, cz)
end
