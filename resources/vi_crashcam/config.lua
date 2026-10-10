Config = {}

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
-- Timed off the reference clip: a couple of black frames on the cut, about
-- 3.8 seconds of slow motion from a low camera at the roadside that turns to
-- keep the car in frame, then a short fade back into the driver's seat.
Config.TimeScale    = 0.2      -- 1.0 is real time
Config.DurationMs   = 3800     -- REAL time, not slowed time
Config.BlackFlashMs = 60       -- the cut in; 0 for a plain cut
Config.FadeInMs     = 350      -- the cut back

-- Where the camera goes, relative to the way the car was travelling just
-- before it hit: `ahead` metres further down the road, `side` metres off to
-- one side of it, `height` metres above the ground there. Whichever side has
-- a clear view of the car is used.
Config.Camera = {
    ahead  = 5.0,
    side   = 10.0,
    height = 0.7,
    fov    = 45.0,
}

-- /crashcam plays the shot on the car you are sitting in, without a crash.
-- Set to false to register no command at all.
Config.TestCommand = 'crashcam'
