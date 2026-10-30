-- GUNS ON BACK: the long guns you carry but aren't holding show on your back
-- (single player: GTA6Hud's WeaponsOnBack, GTA6Hud.ini [WeaponsOnBack]).
-- Every number here is single player's default.
return {
    -- false: no guns on anyone's back and no GUNS ON BACK row
    enabled = true,

    -- What the row starts on for a player who has never switched it.
    -- Single player: [WeaponsOnBack] Enabled = False as shipped (GTA6Hud's own
    -- default, with no ini, is True).
    default = false,

    -- Max: how many guns show at once.
    max = 2,

    -- RecheckSeconds: how often the guns you carry are looked at again. A
    -- change of the gun in your hand is seen at once.
    recheckSeconds = 0.5,

    -- Primary* and Secondary*: where the 1st (3rd...) and the 2nd (4th...) gun
    -- hang, from the upper spine bone (SKEL_Spine3). Metres, then degrees.
    primary   = { x = 0.17, y = -0.14, z = 0.11,  pitch = 0.0, yaw = 168.0, roll = 0.0 },
    secondary = { x = 0.17, y = -0.14, z = -0.11, pitch = 0.0, yaw = 192.0, roll = 0.0 },

    -- HandGripX and AnchorFrac: a long gun on its way to or from the back
    -- (DRAW ANIMATIONS) is held in the right hand at the point AnchorFrac of
    -- the way along its model, HandGripX along the hand bone.
    handGripX = 0.102,
    anchorFrac = 0.62,

    -- FiveM only: other players' guns are hung for players this close (metres).
    drawDistance = 50.0,
}
