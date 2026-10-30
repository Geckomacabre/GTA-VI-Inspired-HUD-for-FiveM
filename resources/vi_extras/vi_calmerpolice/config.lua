-- CALMER POLICE: GTA's police toned down (single player: the fork's ViExtras,
-- ViExtras.ini [Switches] CalmerPolice and [CalmerPolice]). Every number here
-- is single player's default, with its ini key beside it.
return {
    -- false: GTA's own police for everyone, and no CALMER POLICE row
    enabled = true,

    -- What the row starts on for a player who has never switched it.
    -- Single player: [Switches] CalmerPolice = True.
    default = true,

    -- How much longer the game waits between sending police units (2 = twice
    -- as long; under 1 counts as 1). [CalmerPolice] SpawnDelayMultiplier
    spawnDelayMultiplier = 2.0,

    -- How far away the game puts the units it sends, in metres (0 leaves the
    -- game's own distance). [CalmerPolice] SpawnDistance
    spawnDistance = 300.0,

    -- Out of their sight this long and the stars go: escapeSeconds, plus
    -- escapeSecondsPerStar for each star (10 + 5 x 3 = 25 seconds at 3 stars).
    -- [CalmerPolice] EscapeSeconds, EscapeSecondsPerStar
    escapeSeconds = 10,
    escapeSecondsPerStar = 5,

    -- (FiveM only) Resources that run the police themselves. While one is
    -- started, the game's own police are left to it, as single player leaves
    -- them to Rebalanced Dispatch Enhanced and Los Santos RED. fenix-police
    -- sends its own units and sets its own escape times; take it off this list
    -- only if you want the two to share the wanted level (see README.md).
    policeResources = { 'fenix-police' },
}
