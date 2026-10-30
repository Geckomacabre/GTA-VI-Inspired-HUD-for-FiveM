-- CAMERA WEIGHT: the driving camera dips with your car or bike when you land a
-- jump, hit a bump hard or crash (single player: the fork's ViExtras,
-- ViExtras.ini [WeightedCam]). Every number here is single player's default.
return {
    -- false: no camera weight and no CAMERA WEIGHT row for anyone
    enabled = true,

    -- What the row starts on for a player who has never switched it.
    -- Single player: ViExtras.ini [Switches] CameraWeight = True.
    default = true,

    -- How far it dips: 1 as made, 0.5 half as far, 2 twice as far. 0 is off.
    strength = 1.0,

    -- Landings and bumps: the speed the vehicle was coming down at (km/h).
    -- Nothing under landMin, the full landDip (degrees) from landFull. landMs
    -- is how long it takes to reach the bottom; the way back up takes about
    -- six times that.
    landMin = 9.0,
    landFull = 45.0,
    landDip = 4.5,
    landMs = 110.0,

    -- Crashes: speed lost, or gained being hit, in a fifth of a second
    -- (km/h). Braking and cornering never come close to crashMin.
    crashMin = 20.0,
    crashFull = 80.0,
    crashDip = 3.5,
    crashMs = 75.0,

    -- Prints every dip, and the camera frame by frame while it moves, to the
    -- F8 console.
    debug = false,
}
