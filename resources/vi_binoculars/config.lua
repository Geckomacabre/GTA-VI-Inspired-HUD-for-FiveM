Config = {}

-- Whether players have binoculars at all, until they choose for themselves:
-- HUD OPTIONS' BINOCULARS (vi_extras, hold V), or
-- exports.vi_binoculars:SetBinocularsEnabled, kept per player. Off, nothing
-- raises them (command, key, item or export).
Config.Enabled = true

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

-- Zoom is the mouse wheel on a keyboard and mouse, and d-pad up / down on a
-- controller.
--
-- How fast it moves: degrees per second at the wide end while the d-pad is
-- held (it slows as it narrows, so fine adjustment stays fine), and how much
-- one notch of the mouse wheel is worth, as a fraction of the range.
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
Config.Vision = { night = true, thermal = true }

-- A little hand movement, more of it the further in you are. 0 for none.
Config.Sway = 0.35

-- Walking with them up. true: the ped holds them to its face and can walk
-- about, forward being wherever the binoculars point. false: it stands in the
-- stance below until they come down.
Config.Move = true

-- How fast it may go with them up: 1.0 is a walk, 2.0 a run.
Config.MoveSpeed = 1.0

-- What the ped does while it can walk: an upper-body animation, and the prop
-- in its hand.
Config.Anim = {
    dict = 'amb@world_human_binoculars@male@idle_a',
    name = 'idle_c',
    prop = 'prop_binoc_01',
    bone = 28422,   -- right hand
}

-- The stance when it cannot (Config.Move = false). A scenario the ped plays
-- on the spot; false for none.
Config.Scenario = 'WORLD_HUMAN_BINOCULARS'

-- Where the view is taken from: metres forward of and above the ped's root.
Config.EyeForward = 0.35
Config.EyeUp      = 0.72

-- Cannot be raised in a vehicle, in water, while falling, cuffed or dead.
Config.AllowInVehicle = false
