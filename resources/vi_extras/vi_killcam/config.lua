-- KILL CAMERA: single player's slow-motion shot of a kill (GTA6Hud's kill
-- camera, FBICat's 2.1). Every number in client.lua is single player's.
return {
    -- false: no kill camera and no KILL CAMERA row for anyone
    enabled = true,

    -- What the row starts on for a player who has never switched it: off, as
    -- single player ships it (GTA6Hud.ini [Cinematics] KillCamera = False;
    -- GTA6Hud's own default is on). Players switch it on in HUD OPTIONS.
    default = false,

    -- Count kills of other players as well as of people in the world. Single
    -- player has no other players. Off, because a one-shot kill can't be told
    -- reliably on someone else's ped (their health reaches you in steps), and
    -- a slowed shot in the middle of a gunfight with real people is unfair on
    -- the one who sees it.
    players = false,
}
