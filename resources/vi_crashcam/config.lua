Config = {}

-- Whether players get the crash cam, until they choose for themselves: HUD
-- OPTIONS' CRASH CAMERA (vi_extras), the pause menu's Crash Camera, or
-- exports.vi_crashcam:SetCrashCamEnabled, kept per player.
Config.Enabled = true

-- ---- what counts as a bad crash ---------------------------------------------
-- A crash is a lot of speed lost in almost no time. Braking cannot do it: the
-- hardest stop a car here manages sheds about 4 km/h per tenth of a second, so
-- anything that loses MinSpeedLoss inside one SampleMs hit something.
--
--   MinSpeed       how fast you had to be going BEFORE the hit, km/h. Below
--                  this a crash is a bump, and a cutscene for a bump is a
--                  cutscene every time you park badly.
--   MinSpeedLoss   km/h lost inside one sample. Raise it for fewer, bigger
--                  crashes; lower it and kerbs start to qualify.
Config.MinSpeed     = 80.0
Config.MinSpeedLoss = 45.0
Config.SampleMs     = 100

-- Only the driver gets the shot. Off, passengers get it too.
Config.DriverOnly = true

-- Real milliseconds before another crash can trigger it again. A pile-up is
-- several qualifying hits in a row, and one cutscene is plenty.
Config.CooldownMs = 20000

-- ---- the shot ---------------------------------------------------------------
-- Timed off the reference crashes, which all go the same way:
--
--   1. the hit itself, already slowed, still seen from where you were sitting
--   2. a hard cut to a camera standing well back from the car, the screen's
--      edges closed in and the HUD gone, for a little over three seconds
--   3. a hard cut back to exactly the view you had before, time running back
--      up to normal, and the HUD returning a moment after that
--
-- All of these are REAL milliseconds, not slowed ones.
Config.TimeScale    = 0.2      -- 1.0 is real time
Config.ImpactHoldMs = 350      -- step 1
Config.DurationMs   = 3400     -- step 2
Config.EaseOutMs    = 450      -- step 3: how long time takes to run back up
Config.HudReturnMs  = 800      -- step 3: how long after the cut the HUD comes back

-- The reference cuts hard both ways. Set these above 0 for a few black frames
-- on the way in, or a fade on the way back.
Config.BlackFlashMs = 0
Config.FadeInMs     = 0

-- What is laid over the picture during the shot. With vice_hud running it is
-- the same kind of effect as its Focus one: the edges of the screen closed in,
-- breathing slowly, in black instead of purple, with thin bars top and
-- bottom. Without vice_hud only the bars are drawn.
Config.Overlay = {
    enabled  = true,
    strength = 1.0,     -- how dark the edges go; 0 to 2
    bars     = 0.032,   -- height of each bar as a fraction of the screen; 0 for none
    pulse    = true,    -- the slow breathing; false for a still vignette
}

-- Where the camera can stand. Each is tried on both sides of the road and
-- closer in if something is in the way, and one with a clear view of the car
-- is picked at random, so two crashes in a row do not look the same.
--
--   ahead    metres further along the way the car was travelling
--   side     metres off to one side of that line
--   height   metres above the ground there
--   fov      field of view; lower is more zoomed in
Config.Shots = {
    { ahead = 6.0,  side = 15.0, height = 0.6, fov = 40.0 },   -- low at the roadside, side on
    { ahead = 16.0, side = 7.0,  height = 0.9, fov = 36.0 },   -- low, further up the road, the car coming to it
    { ahead = 4.0,  side = 19.0, height = 7.5, fov = 42.0 },   -- up and well back, looking down on it
}

-- A little handheld movement on the camera, so the shot is not dead still.
-- 0 turns it off.
Config.HandShake = 0.25

-- /crashcam plays the shot on the car you are sitting in, without a crash.
-- Set to false to register no command at all.
Config.TestCommand = 'crashcam'
