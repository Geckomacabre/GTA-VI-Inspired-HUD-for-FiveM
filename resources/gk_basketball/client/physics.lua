--[[
    Ball physics.

    Pure Lua: no natives and no vectors, so this exact file runs in the game and
    under tests/run.py on a desk. The game side (client/ballsim.lua) hands it the
    world through `env`; all this file knows about is a sphere, the forces on it
    and what it ran into.

    What is modelled
    ----------------
    Gravity, air drag, Magnus lift from spin, bounces with restitution and Coulomb
    friction (so spin and travel trade with each other on every contact, which is
    why a shot with backspin checks up and a ball off the side of the rim kicks),
    rolling with resistance on slopes, a rim that is a real ring in space, a net
    that takes speed off the ball, bodies (players) it can bounce off, and water it
    floats in.

    env
    ---
    env.sweep(x1,y1,z1, x2,y2,z2, radius) -> hit, cx,cy,cz, nx,ny,nz, surface
        Sweeps a sphere along the segment. On a hit: where the sphere's CENTRE was
        at first contact, the contact normal (pointing at the ball), and optionally
        a surface { restitution, friction, roll }.
    env.water(x, y, z) -> height of the water surface there, or nil
    env.rims   = { { x, y, z, R, tube, net }, ... }     horizontal rings
    env.bodies = { { x, y, z0, z1, radius, vx, vy, vz, id }, ... }
        Vertical capsules: (x,y,z0)-(x,y,z1) is the axis between the end spheres'
        centres. z0 == z1 is a plain sphere (a hand).
    env.event(kind, ball, a, b)                           optional, see emit()
]]

BB = BB or {}

local P = {}
BB.physics = P

local sqrt, min, max, pi = math.sqrt, math.min, math.max, math.pi

P.defaults = {
    radius  = 0.12,         -- m
    mass    = 0.62,         -- kg
    inertia = 2.0 / 3.0,    -- I = inertia * m * r^2. Thin shell, which a ball is.
    gravity = 9.81,

    airDensity = 1.2,
    dragCoeff  = 0.47,
    magnus     = 1.0,       -- scale on spin lift. 0 turns it off.
    spinDecay  = 0.12,      -- 1/s, in air

    restitution     = 0.80, -- on a hard floor: dropped from 1.8m it comes back to 1.15m
    restitutionLoss = 0.012,-- fraction lost per m/s of impact, so hard bounces are deader
    friction        = 0.65,
    rollResistance  = 0.035,
    restSpeed       = 0.38, -- m/s of rebound below which it stops bouncing and rolls
    floorNormal     = 0.55, -- a surface has to be flatter than this (normal z) to roll on
    sleepSpeed      = 0.07,
    sleepTime       = 0.5,

    waterDensity   = 1000.0,
    waterDrag      = 0.47,
    waterLinear    = 4.5,   -- 1/s, what stops it bobbing for ever
    waterSpinDecay = 5.0,
    waveSlide      = 0.55,  -- how readily it slides down the face of a wave
    waveSample     = 0.4,   -- m either side, for the slope of the water

    rimRestitution = 0.52,
    rimFriction    = 0.35,
    netLength      = 0.40,
    netDragH       = 7.0,   -- 1/s sideways
    netDragV       = 2.4,   -- 1/s downward

    bodyRestitution = 0.35,
    bodyFriction    = 0.5,

    skin        = 0.004,    -- m of slack kept between the ball and what it rests on
    substep     = 1.0 / 120.0,
    rollSubstep = 1.0 / 60.0,
    maxTravel   = 0.05,     -- m per substep, so nothing thin is stepped over
    maxSubsteps = 16,
    maxStep     = 0.1,      -- s. A longer hitch than this plays in slow motion.
}

--- Fills in defaults and the constants derived from them.
function P.params(over)
    local p = {}
    for k, v in pairs(P.defaults) do p[k] = v end
    if over then
        for k, v in pairs(over) do
            if P.defaults[k] ~= nil and type(v) == 'number' then p[k] = v end
        end
    end

    local r    = p.radius
    local area = pi * r * r

    p.kDrag      = 0.5 * p.airDensity * p.dragCoeff * area / p.mass
    p.kMagnus    = p.magnus * 0.5 * p.airDensity * area * r / p.mass
    p.kWater     = 0.5 * p.waterDensity * p.waterDrag * area / p.mass
    p.buoyancy   = p.waterDensity * (4.0 / 3.0) * pi * r * r * r * p.gravity / p.mass
    p.rollFactor = 1.0 / (1.0 + p.inertia)

    -- How deep it sits when floating at rest: the depth at which the water it
    -- pushes aside weighs what it does. Solved by bisection, once.
    local want = p.gravity / p.buoyancy
    local lo, hi = 0.0, 2.0 * r
    for _ = 1, 40 do
        local h = 0.5 * (lo + hi)
        if h * h * (3.0 * r - h) / (4.0 * r * r * r) < want then lo = h else hi = h end
    end
    p.draft = want >= 1.0 and 2.0 * r or 0.5 * (lo + hi)

    return p
end

--- A ball at rest in the air at a point. Give it a velocity and let go.
function P.new(x, y, z)
    return {
        x = x, y = y, z = z,
        vx = 0.0, vy = 0.0, vz = 0.0,
        wx = 0.0, wy = 0.0, wz = 0.0,           -- spin, rad/s, world axes
        qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0, -- orientation
        mode = 'air',                           -- 'air' | 'roll' | 'sleep'
        nx = 0.0, ny = 0.0, nz = 1.0,           -- what it's rolling on
        surface = nil,
        still = 0.0,
        wet = false,
        slopeX = 0.0, slopeY = 0.0,
        t = 0.0,
        ignoreId = nil, ignoreUntil = 0.0,      -- a body it may pass through for now
        inNet = nil,
    }
end

function P.wake(b)
    if b.mode == 'sleep' then
        b.mode, b.still = 'air', 0.0
    end
end

local function emit(env, kind, b, a1, a2)
    local fn = env.event
    if fn then fn(kind, b, a1, a2) end
end

--------------------------------------------------------------------------------
-- Forces
--------------------------------------------------------------------------------

--- Acceleration in the air. `dry` is the fraction of the ball out of the water.
local function airAccel(prm, vx, vy, vz, wx, wy, wz, dry)
    local kd = prm.kDrag * sqrt(vx * vx + vy * vy + vz * vz) * dry
    local km = prm.kMagnus * dry

    return -kd * vx + km * (wy * vz - wz * vy),
           -kd * vy + km * (wz * vx - wx * vz),
           -kd * vz + km * (wx * vy - wy * vx) - prm.gravity
end

--- Fraction of the ball's volume below a water surface at height wz.
local function submerged(prm, z, wz)
    local r = prm.radius
    local h = wz - (z - r)

    if h <= 0.0 then return 0.0 end
    if h >= 2.0 * r then return 1.0 end

    return h * h * (3.0 * r - h) / (4.0 * r * r * r)
end

--------------------------------------------------------------------------------
-- Contact
--------------------------------------------------------------------------------

--[[
    One contact, as an impulse.

    Normal part: the usual restitution. Tangential part: friction acts on the
    velocity of the point of the ball that is touching, which is the ball's travel
    plus its spin. It is limited two ways -- it can't exceed friction times the
    normal impulse (the ball skids), and it can't do more than bring that point to
    rest (the ball grips and rolls off the contact). The same impulse changes the
    spin, about the centre, so travel and spin are exchanged rather than one of
    them being invented.

    sv* is the velocity of the thing hit, for a moving body.
    Returns the closing speed, or 0 if the two were already parting.
]]
local function bounce(b, nx, ny, nz, e, mu, prm, svx, svy, svz)
    local rvx, rvy, rvz = b.vx - svx, b.vy - svy, b.vz - svz
    local vn = rvx * nx + rvy * ny + rvz * nz
    if vn >= 0.0 then return 0.0 end

    local r = prm.radius

    -- Velocity of the contact point: v + w x (-r n)
    local cx = b.wy * nz - b.wz * ny
    local cy = b.wz * nx - b.wx * nz
    local cz = b.wx * ny - b.wy * nx
    local ux, uy, uz = rvx - r * cx, rvy - r * cy, rvz - r * cz
    local un = ux * nx + uy * ny + uz * nz
    local tx, ty, tz = ux - un * nx, uy - un * ny, uz - un * nz
    local slip = sqrt(tx * tx + ty * ty + tz * tz)

    local jn = -(1.0 + e) * vn      -- impulses here are per unit mass
    rvx, rvy, rvz = rvx + jn * nx, rvy + jn * ny, rvz + jn * nz

    if slip > 1e-6 then
        local k  = prm.inertia
        local jt = min(mu * jn, slip / (1.0 + 1.0 / k))
        local dx, dy, dz = -tx / slip, -ty / slip, -tz / slip

        rvx, rvy, rvz = rvx + jt * dx, rvy + jt * dy, rvz + jt * dz

        -- dw = (-r n) x J / I
        local s = -jt / (k * r)
        b.wx = b.wx + s * (ny * dz - nz * dy)
        b.wy = b.wy + s * (nz * dx - nx * dz)
        b.wz = b.wz + s * (nx * dy - ny * dx)
    end

    b.vx, b.vy, b.vz = rvx + svx, rvy + svy, rvz + svz

    return -vn
end

--- The rim: a ring of radius R with a tube of metal round it.
local function hitRims(b, prm, env, dt)
    local rims = env.rims
    if not rims then return end

    local r = prm.radius

    for i = 1, #rims do
        local rim = rims[i]
        local dx, dy = b.x - rim.x, b.y - rim.y
        local d = sqrt(dx * dx + dy * dy)

        if d < rim.R + r + 0.05 and b.z < rim.z + r + 0.05 and b.z > rim.z - (rim.net or prm.netLength) - r then
            -- Nearest point of the ring to the ball.
            local qx, qy
            if d < 1e-6 then
                qx, qy = rim.x + rim.R, rim.y
            else
                qx, qy = rim.x + dx / d * rim.R, rim.y + dy / d * rim.R
            end

            local ox, oy, oz = b.x - qx, b.y - qy, b.z - rim.z
            local dist = sqrt(ox * ox + oy * oy + oz * oz)
            local reach = r + (rim.tube or 0.009)

            if not rim.noRing and dist < reach and dist > 1e-6 then
                local nx, ny, nz = ox / dist, oy / dist, oz / dist

                b.x, b.y, b.z = qx + nx * reach, qy + ny * reach, rim.z + nz * reach

                local impact = bounce(b, nx, ny, nz, prm.rimRestitution, prm.rimFriction, prm, 0.0, 0.0, 0.0)
                if impact > 0.0 then emit(env, 'rim', b, impact, rim) end
            end

            -- The net hangs from the ring and takes the pace off whatever drops
            -- through it. A ball that goes in quickly comes out slowly, and one
            -- that goes in at an angle leaves going nearly straight down.
            local depth = rim.z - b.z
            if depth > 0.0 and depth < (rim.net or prm.netLength) and d < rim.R and b.vz < 0.0 then
                local kh = 1.0 / (1.0 + prm.netDragH * dt)
                local kv = 1.0 / (1.0 + prm.netDragV * dt)

                b.vx, b.vy, b.vz = b.vx * kh, b.vy * kh, b.vz * kv

                if b.inNet ~= rim then
                    b.inNet = rim
                    emit(env, 'net', b, sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz), rim)
                end
            elseif b.inNet == rim then
                b.inNet = nil
            end
        elseif b.inNet == rim then
            b.inNet = nil
        end
    end
end

--- Players, as upright capsules, and their hands, as spheres.
--- @return boolean touched
local function hitBodies(b, prm, env)
    local bodies = env.bodies
    if not bodies then return false end

    local r = prm.radius
    local touched = false

    for i = 1, #bodies do
        local body = bodies[i]

        if not (b.ignoreId and body.id == b.ignoreId and b.t < b.ignoreUntil) then
            local qz = b.z
            if qz < body.z0 then qz = body.z0 elseif qz > body.z1 then qz = body.z1 end

            local ox, oy, oz = b.x - body.x, b.y - body.y, b.z - qz
            local dist = sqrt(ox * ox + oy * oy + oz * oz)
            local reach = r + body.radius

            if dist < reach then
                local nx, ny, nz

                if dist > 1e-5 then
                    nx, ny, nz = ox / dist, oy / dist, oz / dist
                else
                    nx, ny, nz = 1.0, 0.0, 0.0
                end

                b.x, b.y, b.z = body.x + nx * reach, body.y + ny * reach, qz + nz * reach

                local impact = bounce(b, nx, ny, nz, prm.bodyRestitution, prm.bodyFriction, prm,
                    body.vx or 0.0, body.vy or 0.0, body.vz or 0.0)

                if impact > 0.0 then
                    touched = true
                    emit(env, 'body', b, impact, body)
                end
            end
        end
    end

    return touched
end

--[[
    The moment a ball stops bouncing and starts rolling.

    It arrives sliding: its travel and its spin don't agree about how fast the
    point touching the floor is going. Friction closes that gap, taking from one
    and giving to the other, and what is left is rolling. A ball thrown along the
    floor with no spin ends up rolling at 3/5 of the speed it was thrown; one with
    backspin on it can stop dead or come back.
]]
local function settleRoll(b, prm)
    local r, k = prm.radius, prm.inertia
    local nx, ny, nz = b.nx, b.ny, b.nz

    local vn = b.vx * nx + b.vy * ny + b.vz * nz
    local vx, vy, vz = b.vx - vn * nx, b.vy - vn * ny, b.vz - vn * nz

    -- Slip of the contact point: v - r (w x n), along the surface.
    local ux = vx - r * (b.wy * nz - b.wz * ny)
    local uy = vy - r * (b.wz * nx - b.wx * nz)
    local uz = vz - r * (b.wx * ny - b.wy * nx)
    local un = ux * nx + uy * ny + uz * nz
    ux, uy, uz = ux - un * nx, uy - un * ny, uz - un * nz

    local share = k / (1.0 + k)
    vx, vy, vz = vx - ux * share, vy - uy * share, vz - uz * share

    b.vx, b.vy, b.vz = vx, vy, vz
    b.wx = (ny * vz - nz * vy) / r
    b.wy = (nz * vx - nx * vz) / r
    b.wz = (nx * vy - ny * vx) / r
end

--------------------------------------------------------------------------------
-- Flight (and floating, which is flight with water in the way)
--------------------------------------------------------------------------------

local function stepAir(b, dt, prm, env)
    local r = prm.radius
    local px, py, pz = b.x, b.y, b.z

    -- Water under, around or over the ball.
    local f, waterV = 0.0, 0.0
    local wz = env.water and env.water(px, py, pz) or nil

    if wz then
        f = submerged(prm, pz, wz)

        if b.waterZ and f > 0.0 then
            -- The surface itself is moving, with the swell. Drag is against the
            -- water, not against the world, so the ball rides it.
            waterV = (wz - b.waterZ) / dt
            if waterV > 3.0 then waterV = 3.0 elseif waterV < -3.0 then waterV = -3.0 end
        end
    end

    b.waterZ = wz

    local ax, ay, az = airAccel(prm, b.vx, b.vy, b.vz, b.wx, b.wy, b.wz, 1.0 - f)

    if f > 0.0 then
        az = az + prm.buoyancy * f

        -- Down the face of the wave it's on.
        local grip = min(1.0, f * 6.0) * prm.waveSlide * prm.gravity
        ax = ax - b.slopeX * grip
        ay = ay - b.slopeY * grip

        if not b.wet then
            b.wet = true
            emit(env, 'splash', b, sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz))
        end
    elseif b.wet then
        b.wet = false
    end

    -- Second order, and exact for a constant acceleration whatever the step, so
    -- the flight of a shot doesn't depend on the frame rate it was watched at.
    local h2 = 0.5 * dt * dt
    b.x = px + b.vx * dt + ax * h2
    b.y = py + b.vy * dt + ay * h2
    b.z = pz + b.vz * dt + az * h2

    local bx, by, bz = airAccel(prm, b.vx + ax * dt, b.vy + ay * dt, b.vz + az * dt, b.wx, b.wy, b.wz, 1.0 - f)
    local ex, ey, ez = airAccel(prm, b.vx, b.vy, b.vz, b.wx, b.wy, b.wz, 1.0 - f)

    -- Only the air terms are re-evaluated at the far end of the step; buoyancy and
    -- the wave slope are taken as constant across it.
    b.vx = b.vx + (ax + 0.5 * (bx - ex)) * dt
    b.vy = b.vy + (ay + 0.5 * (by - ey)) * dt
    b.vz = b.vz + (az + 0.5 * (bz - ez)) * dt

    if f > 0.0 then
        -- Water drag, solved implicitly: it is stiff enough to overshoot and
        -- reverse the ball if it's applied as a plain force at these steps.
        local rvz = b.vz - waterV
        local speed = sqrt(b.vx * b.vx + b.vy * b.vy + rvz * rvz)
        local k = 1.0 / (1.0 + (prm.waterLinear * min(1.0, f * 4.0) + prm.kWater * f * speed) * dt)

        b.vx, b.vy = b.vx * k, b.vy * k
        b.vz = waterV + rvz * k

        local ks = 1.0 / (1.0 + prm.waterSpinDecay * min(1.0, f * 4.0) * dt)
        b.wx, b.wy, b.wz = b.wx * ks, b.wy * ks, b.wz * ks
    else
        local ks = 1.0 / (1.0 + prm.spinDecay * dt)
        b.wx, b.wy, b.wz = b.wx * ks, b.wy * ks, b.wz * ks
    end

    hitRims(b, prm, env, dt)
    hitBodies(b, prm, env)

    -- The world.
    local hit, cx, cy, cz, nx, ny, nz, surf = env.sweep(px, py, pz, b.x, b.y, b.z, r - prm.skin)
    if not hit then return end

    local vn = b.vx * nx + b.vy * ny + b.vz * nz
    if vn >= 0.0 then return end

    local slack = 2.0 * prm.skin
    b.x, b.y, b.z = cx + nx * slack, cy + ny * slack, cz + nz * slack

    local e  = surf and surf.restitution or prm.restitution
    local mu = surf and surf.friction or prm.friction

    e = max(0.05, e * (1.0 - prm.restitutionLoss * -vn))

    local impact = bounce(b, nx, ny, nz, e, mu, prm, 0.0, 0.0, 0.0)
    emit(env, 'bounce', b, impact, surf)

    local out = b.vx * nx + b.vy * ny + b.vz * nz

    -- Standing the ball back off the surface lifted it, and height is energy.
    -- Take the same amount out of the rebound, or a ball that should be settling
    -- is handed a little more on every bounce and never stops.
    if nz > 0.0 and out > 0.0 then
        local left = out * out - 2.0 * prm.gravity * nz * slack
        local slower = left > 0.0 and sqrt(left) or 0.0

        b.vx, b.vy, b.vz = b.vx + (slower - out) * nx, b.vy + (slower - out) * ny, b.vz + (slower - out) * nz
        out = slower
    end

    if out < prm.restSpeed then
        -- Too little left to leave the surface: it has stopped bouncing.
        b.vx, b.vy, b.vz = b.vx - out * nx, b.vy - out * ny, b.vz - out * nz

        if nz > prm.floorNormal and f < prm.gravity / prm.buoyancy then
            b.mode = 'roll'
            b.nx, b.ny, b.nz = nx, ny, nz
            b.surface = surf
            b.still = 0.0
            settleRoll(b, prm)
        end
    end
end

--------------------------------------------------------------------------------
-- Rolling
--------------------------------------------------------------------------------

local function stepRoll(b, dt, prm, env)
    local r, g = prm.radius, prm.gravity
    local nx, ny, nz = b.nx, b.ny, b.nz
    local surf = b.surface

    -- Water come up over it (a wave up the beach, a tide): it floats off.
    local wz = env.water and env.water(b.x, b.y, b.z) or nil
    if wz and wz - (b.z - r) > prm.draft then
        b.mode = 'air'
        return stepAir(b, dt, prm, env)
    end

    -- Somebody's foot.
    if hitBodies(b, prm, env) then
        local out = b.vx * nx + b.vy * ny + b.vz * nz
        if out > prm.restSpeed then
            b.mode = 'air'
            return
        end
    end

    -- Gravity along the surface. A rolling shell only gets 3/5 of it as travel;
    -- the rest goes into turning.
    local gn = -g * nz
    local gtx, gty, gtz = -gn * nx, -gn * ny, -g - gn * nz
    local k = prm.rollFactor
    local pull = sqrt(gtx * gtx + gty * gty + gtz * gtz) * k

    local resist = (surf and surf.roll or prm.rollResistance) * g * nz
    local speed  = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)

    if speed < prm.sleepSpeed and pull <= resist then
        b.vx, b.vy, b.vz = 0.0, 0.0, 0.0
        b.wx, b.wy, b.wz = 0.0, 0.0, 0.0
        b.still = b.still + dt

        if b.still > prm.sleepTime then
            b.mode = 'sleep'
            emit(env, 'sleep', b)
        end

        return
    end

    b.still = 0.0

    b.vx, b.vy, b.vz = b.vx + gtx * k * dt, b.vy + gty * k * dt, b.vz + gtz * k * dt

    speed = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
    if speed > 1e-5 then
        local drop = min(speed, (resist + prm.kDrag * speed * speed) * dt)
        local keep = (speed - drop) / speed
        b.vx, b.vy, b.vz = b.vx * keep, b.vy * keep, b.vz * keep
    end

    local px, py, pz = b.x, b.y, b.z
    b.x, b.y, b.z = px + b.vx * dt, py + b.vy * dt, pz + b.vz * dt

    -- Anything in the way: a wall, a kerb, a post. Swept a little above the
    -- ground so the ground itself isn't what it finds.
    local lift = 3.0 * prm.skin + 0.006
    local hit, cx, cy, cz, hx, hy, hz, hsurf = env.sweep(
        px + nx * lift, py + ny * lift, pz + nz * lift,
        b.x + nx * lift, b.y + ny * lift, b.z + nz * lift, r - prm.skin)

    if hit and (b.vx * hx + b.vy * hy + b.vz * hz) < 0.0 and (hx * nx + hy * ny + hz * nz) < 0.92 then
        b.x, b.y, b.z = cx - nx * lift + hx * prm.skin, cy - ny * lift + hy * prm.skin, cz - nz * lift + hz * prm.skin

        local e  = hsurf and hsurf.restitution or prm.restitution
        local mu = hsurf and hsurf.friction or prm.friction
        local impact = bounce(b, hx, hy, hz, e, mu, prm, 0.0, 0.0, 0.0)
        emit(env, 'bounce', b, impact, hsurf)

        -- Off a kerb it can come away upwards; then it's in the air again.
        local out = b.vx * nx + b.vy * ny + b.vz * nz
        if out > prm.restSpeed then
            b.mode = 'air'
            return
        end

        b.vx, b.vy, b.vz = b.vx - out * nx, b.vy - out * ny, b.vz - out * nz
    end

    -- Find the ground again under where it has got to.
    local up, down = 0.08, 0.25
    local ghit, gx, gy, gz, mx, my, mz, gsurf = env.sweep(
        b.x + nx * up, b.y + ny * up, b.z + nz * up,
        b.x - nx * down, b.y - ny * down, b.z - nz * down, r - prm.skin)

    if not ghit or mz < prm.floorNormal then
        -- Rolled off an edge, or onto something too steep to roll on.
        b.mode = 'air'
        return
    end

    local slack = 2.0 * prm.skin
    b.x, b.y, b.z = gx + mx * slack, gy + my * slack, gz + mz * slack
    b.nx, b.ny, b.nz = mx, my, mz
    b.surface = gsurf

    -- Keep the speed over a crease in the ground, turn it to lie along the new face.
    local out = b.vx * mx + b.vy * my + b.vz * mz
    local tx, ty, tz = b.vx - out * mx, b.vy - out * my, b.vz - out * mz
    local tlen = sqrt(tx * tx + ty * ty + tz * tz)
    speed = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)

    if tlen > 1e-5 then
        local s = speed / tlen
        b.vx, b.vy, b.vz = tx * s, ty * s, tz * s
    end

    -- Rolling without slipping: w = n x v / r
    b.wx = (my * b.vz - mz * b.vy) / r
    b.wy = (mz * b.vx - mx * b.vz) / r
    b.wz = (mx * b.vy - my * b.vx) / r
end

--- A ball at rest costs nothing, but has to notice being kicked or floated off.
local function stepSleep(b, dt, prm, env)
    b.still = b.still + dt

    local bodies = env.bodies
    if bodies then
        local r = prm.radius

        for i = 1, #bodies do
            local body = bodies[i]
            local qz = b.z
            if qz < body.z0 then qz = body.z0 elseif qz > body.z1 then qz = body.z1 end

            local ox, oy, oz = b.x - body.x, b.y - body.y, b.z - qz
            local reach = r + body.radius

            if ox * ox + oy * oy + oz * oz < reach * reach then
                local sv = (body.vx or 0.0) ^ 2 + (body.vy or 0.0) ^ 2 + (body.vz or 0.0) ^ 2
                if sv > 0.04 then
                    b.mode, b.still = 'roll', 0.0
                    return
                end
            end
        end
    end

    if b.still > 0.5 then
        b.still = 0.0

        local wz = env.water and env.water(b.x, b.y, b.z) or nil
        if wz and wz - (b.z - prm.radius) > prm.draft then
            b.mode = 'air'
        end
    end
end

--------------------------------------------------------------------------------
-- Stepping
--------------------------------------------------------------------------------

--- Moves the ball on by dt seconds.
function P.step(b, dt, env, prm)
    if dt <= 0.0 then return end
    if dt > prm.maxStep then dt = prm.maxStep end

    b.t = b.t + dt

    if b.mode == 'sleep' then
        return stepSleep(b, dt, prm, env)
    end

    -- Slope of the water it's in, once a call: four lookups is plenty per frame.
    if b.wet and env.water then
        local d = prm.waveSample
        local e, w = env.water(b.x + d, b.y, b.z), env.water(b.x - d, b.y, b.z)
        local n, s = env.water(b.x, b.y + d, b.z), env.water(b.x, b.y - d, b.z)

        b.slopeX = (e and w) and (e - w) / (2.0 * d) or 0.0
        b.slopeY = (n and s) and (n - s) / (2.0 * d) or 0.0
    else
        b.slopeX, b.slopeY = 0.0, 0.0
    end

    local left, count = dt, 0

    while left > 1e-6 and count < prm.maxSubsteps do
        local h

        if b.mode == 'roll' then
            h = prm.rollSubstep
        elseif b.mode == 'air' then
            h = prm.substep
        else
            break
        end

        local speed = sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
        if speed * h > prm.maxTravel then h = prm.maxTravel / speed end
        if h > left then h = left end

        if b.mode == 'roll' then
            stepRoll(b, h, prm, env)
        else
            stepAir(b, h, prm, env)
        end

        left  = left - h
        count = count + 1
    end

    -- Turn the ball by its spin.
    local hx, hy, hz = 0.5 * b.wx * dt, 0.5 * b.wy * dt, 0.5 * b.wz * dt
    local qx, qy, qz, qw = b.qx, b.qy, b.qz, b.qw

    local nqx = qx + (hx * qw + hy * qz - hz * qy)
    local nqy = qy + (hy * qw + hz * qx - hx * qz)
    local nqz = qz + (hz * qw + hx * qy - hy * qx)
    local nqw = qw - (hx * qx + hy * qy + hz * qz)
    local len = sqrt(nqx * nqx + nqy * nqy + nqz * nqz + nqw * nqw)

    if len > 1e-9 then
        b.qx, b.qy, b.qz, b.qw = nqx / len, nqy / len, nqz / len, nqw / len
    end
end

--------------------------------------------------------------------------------
-- Shot solving
--------------------------------------------------------------------------------

--- Where a ball launched with this velocity and spin is after `time` in clear air.
local function fly(prm, x, y, z, vx, vy, vz, wx, wy, wz, time)
    local left = time

    while left > 1e-9 do
        -- Same step rule as P.step, so what was solved is what gets flown.
        local h = prm.substep
        local speed = sqrt(vx * vx + vy * vy + vz * vz)
        if speed * h > prm.maxTravel then h = prm.maxTravel / speed end
        if h > left then h = left end
        local ax, ay, az = airAccel(prm, vx, vy, vz, wx, wy, wz, 1.0)
        local bx, by, bz = airAccel(prm, vx + ax * h, vy + ay * h, vz + az * h, wx, wy, wz, 1.0)
        local h2 = 0.5 * h * h

        x, y, z = x + vx * h + ax * h2, y + vy * h + ay * h2, z + vz * h + az * h2
        vx, vy, vz = vx + 0.5 * (ax + bx) * h, vy + 0.5 * (ay + by) * h, vz + 0.5 * (az + bz) * h

        local ks = 1.0 / (1.0 + prm.spinDecay * h)
        wx, wy, wz = wx * ks, wy * ks, wz * ks

        left = left - h
    end

    return x, y, z, vx, vy, vz
end

P.fly = fly

--[[
    The velocity that puts the ball at a point after `time` seconds.

    Without air this has a one-line answer. With drag and spin lift it doesn't, so
    start from the one-line answer, fly it with the same integrator the game uses,
    see how far off it landed, and correct. A few rounds gets a normal shot to a
    tenth of a millimetre; a full-court heave, where drag is doing a lot, takes more.
]]
function P.solveLaunch(prm, fx, fy, fz, tx, ty, tz, time, wx, wy, wz)
    wx, wy, wz = wx or 0.0, wy or 0.0, wz or 0.0

    local vx = (tx - fx) / time
    local vy = (ty - fy) / time
    local vz = (tz - fz) / time + 0.5 * prm.gravity * time

    for _ = 1, 30 do
        local x, y, z = fly(prm, fx, fy, fz, vx, vy, vz, wx, wy, wz, time)
        local ex, ey, ez = tx - x, ty - y, tz - z

        vx, vy, vz = vx + ex / time, vy + ey / time, vz + ez / time

        if ex * ex + ey * ey + ez * ez < 1e-8 then break end
    end

    return vx, vy, vz
end

--- How long a shot has to be in the air to come down onto its target at `angle`
--- degrees from the horizontal. `rise` is target height minus release height.
function P.flightTime(prm, rise, distance, angle)
    local need = rise + distance * math.tan(math.rad(angle))
    if need < 0.05 then need = 0.05 end

    return sqrt(2.0 * need / prm.gravity)
end

--- A sample from a bell curve, mean 0 and spread 1.
local function gauss()
    local u = math.random()
    if u < 1e-12 then u = 1e-12 end
    return sqrt(-2.0 * math.log(u)) * math.cos(2.0 * pi * math.random())
end

--[[
    How far off the middle of the rim a shot is aimed, for a given accuracy.

    Bell-shaped rather than flat: most of a decent shooter's misses are near
    misses. Spread grows with distance (a degree of error is more rim the further
    out you are) and with how badly the release was timed. Clipped at three
    spreads so nothing leaves for the car park.

    Returns sideways and long/short error in metres.
]]
function P.scatter(accuracy, distance, lateralPerMetre, depthPerMetre)
    local miss = 1.0 - accuracy
    if miss <= 0.0 then return 0.0, 0.0 end

    local a, d = gauss(), gauss()
    if a > 3.0 then a = 3.0 elseif a < -3.0 then a = -3.0 end
    if d > 3.0 then d = 3.0 elseif d < -3.0 then d = -3.0 end

    return a * miss * distance * lateralPerMetre, d * miss * distance * depthPerMetre
end

--- Backspin for a ball leaving along (dx, dy): top of the ball coming back at you.
function P.backspin(dx, dy, rate)
    local len = sqrt(dx * dx + dy * dy)
    if len < 1e-6 then return 0.0, 0.0, 0.0 end

    -- d x up
    return dy / len * rate, -dx / len * rate, 0.0
end

return P
