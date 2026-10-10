Config = {}

-- ---- how you get them out ---------------------------------------------------
-- /binoculars toggles them. Set to false to register no command.
Config.Command = 'binoculars'

-- A key for the same thing, rebindable by each player in FiveM's key
-- settings. false for none.
Config.Key = false

-- An inventory item that brings them up when used. false to need no item (the
-- command and key then work for everyone); with a name set, the command and
-- key only work while the player is carrying one.
--
-- ox_inventory: add the item to data/items.lua. qbx_core / qb-core: the
-- usable item is registered for you (server.lua).
Config.Item = 'binoculars'

-- ---- the view ---------------------------------------------------------------
-- Field of view in degrees: Wide is what you see when they come up, Narrow is
-- fully zoomed in. Lower is more zoom.
Config.FovWide   = 42.0
Config.FovNarrow = 4.0

-- How fast the zoom moves: degrees per second at the wide end while a zoom
-- button is held (it slows as it narrows, so fine adjustment stays fine), and
-- how much one notch of the mouse wheel is worth, as a fraction of the range.
Config.ZoomSpeed  = 38.0
Config.WheelStep  = 0.12

-- How quickly the picture settles on where the zoom and the stick are asking
-- for. Higher is snappier; lower is floatier.
Config.Smoothing = 9.0

-- Look speed at the wide end, in degrees per second at full stick / per unit
-- of mouse. It is scaled down with the zoom so a small movement stays small.
Config.LookSpeedPad   = 85.0
Config.LookSpeedMouse = 7.0

-- How far up and down you can look.
Config.PitchMin = -55.0
Config.PitchMax = 55.0

-- Night and thermal vision, stepped through with Left / Right (arrow keys or
-- the d-pad) while they are up. Both off is plain binoculars, with no extra
-- prompt on screen.
Config.Vision = { night = false, thermal = false }

-- A little hand movement, more of it the further in you are. 0 for none.
Config.Sway = 0.35

-- The stance. A scenario the ped plays while they are up; false for none.
Config.Scenario = 'WORLD_HUMAN_BINOCULARS'

-- Where the view is taken from: metres forward of and above the ped's root.
Config.EyeForward = 0.35
Config.EyeUp      = 0.72

-- Cannot be raised in a vehicle, in water, while falling, cuffed or dead.
Config.AllowInVehicle = false
