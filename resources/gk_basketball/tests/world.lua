--[[
    A world for the physics to run in away from the game: planes, a water level,
    rims and bodies. Sweeps against planes are exact.

    overlap = false is the pessimistic reading of the game's shape tests: a sweep
    that starts already touching something doesn't report it. The physics has to
    work either way, so the suite runs under both.
]]

local World = {}

function World.new(opts)
    opts = opts or {}

    local W = {
        planes = {},
        rims   = {},
        bodies = {},
        log    = {},
        overlap = opts.overlap or false,
        waterFn = nil,
        sweeps  = 0,
    }

    --- Solid below the plane n.p = d. `within(x,y,z)` limits it to a region.
    function W.plane(nx, ny, nz, d, surface, within)
        local len = math.sqrt(nx * nx + ny * ny + nz * nz)
        W.planes[#W.planes + 1] = {
            nx = nx / len, ny = ny / len, nz = nz / len, d = d / len,
            surface = surface, within = within,
        }
    end

    --- @param skip function|nil skip(surface) is true for a surface this test passes through
    function W.sweep(x1, y1, z1, x2, y2, z2, radius, skip)
        W.sweeps = W.sweeps + 1

        local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
        local best, plane

        for _, pl in ipairs(W.planes) do
            local s0 = pl.nx * x1 + pl.ny * y1 + pl.nz * z1 - pl.d
            local sd = pl.nx * dx + pl.ny * dy + pl.nz * dz
            local t

            if s0 <= radius then
                if W.overlap and sd < 0.0 and s0 > -1.0 then t = 0.0 end
            elseif sd < 0.0 then
                t = (radius - s0) / sd
                if t > 1.0 then t = nil end
            end

            if t and pl.within and not pl.within(x1 + dx * t, y1 + dy * t, z1 + dz * t) then t = nil end
            if t and skip and pl.surface and skip(pl.surface) then t = nil end

            if t and (not best or t < best) then best, plane = t, pl end
        end

        if not best then return false end

        return true, x1 + dx * best, y1 + dy * best, z1 + dz * best, plane.nx, plane.ny, plane.nz, plane.surface
    end

    function W.water(x, y, z)
        if W.waterFn then return W.waterFn(x, y, z, W.time or 0.0) end
        return nil
    end

    function W.event(kind, ball, a, b)
        W.log[#W.log + 1] = { kind = kind, t = ball.t, a = a, b = b }
    end

    function W.count(kind)
        local n = 0
        for _, e in ipairs(W.log) do
            if e.kind == kind then n = n + 1 end
        end
        return n
    end

    --- Runs a ball for `seconds` at `fps`, calling each(ball, t) after every frame.
    function W.run(ball, prm, seconds, fps, each)
        local dt = 1.0 / fps
        local frames = math.floor(seconds * fps + 0.5)

        for i = 1, frames do
            W.time = (W.time or 0.0) + dt
            BB.physics.step(ball, dt, W, prm)
            if each and each(ball, i * dt) == false then return i * dt end
        end

        return seconds
    end

    return W
end

return World
