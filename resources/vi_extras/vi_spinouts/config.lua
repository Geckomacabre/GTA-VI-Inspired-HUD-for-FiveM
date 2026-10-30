-- SPIN-OUTS: cars lose the back end and spin when something knocks them off
-- line (single player: FBICat's GTA6Hud, GTA6Hud.ini [Driving]). Every number
-- in client.lua is single player's; these are the ones its ini lets you set.
return {
    -- false: no spin-outs and no SPIN-OUTS row for anyone
    enabled = true,

    -- What the row starts on for a player who has never switched it.
    -- Single player: [Driving] SpinOuts = True.
    default = true,

    -- [Driving] SpinRollChance: how often a spin-out over 72 km/h trips over
    -- and rolls, 0 to 1.
    rollChance = 0.35,

    -- [Driving] SpinShotChance: the chance a shot spins a car out, per hit at
    -- 72 km/h. Half that at 36 km/h, twice that from 144 km/h up.
    shotChance = 0.12,

    -- [Driving] Impacts: your own car spins out when it's hit hard on the
    -- side. In single player this is part of GTA6Hud's crash impacts.
    impacts = true,

    -- [Driving] ImpactMin: the speed change in one frame (m/s) that counts as
    -- a hit on your own car at all. A spin-out needs over 10 m/s of it, and
    -- 43 km/h on the clock before the hit.
    impactMin = 5.0,

    -- FiveM only. Only the client that owns a car can push it. When you
    -- spin out a car someone else's client owns (you shot it or hit it), it is
    -- asked for and the spin-out waits this long (ms) at most before giving up.
    controlWaitMs = 250,
}
