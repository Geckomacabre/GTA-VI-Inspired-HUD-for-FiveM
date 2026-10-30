-- CHASE MUSIC: single player's wanted-level music (GTA6Hud's MusicPlayer,
-- GTA6Hud.ini [Music]). Tracks the server owner drops into music/ play while
-- the player is wanted and fade away when the wanted level goes.
-- Every number is single player's, with its ini key beside it.
return {
    -- false: no chase music on this server at all, and no HUD OPTIONS row
    enabled = true,

    -- The HUD OPTIONS row's value for a player who hasn't set it. [Music]
    -- Enabled: False in the ini single player ships, because no music ships
    -- with it (its code default is True). Set true once music/ has tracks.
    default = false,

    -- The folder inside vi_chasemusic/ the tracks are read from. [Music]
    -- Folder (Music, under scripts\Hud). The manifest's files entries must
    -- name the same folder, or players never download the tracks.
    folder = 'music',

    -- The file types picked up. Single player takes .mp3 .wav .wma .m4a
    -- (Windows' media player). FiveM's browser can't play .wma, so it is left
    -- out; it can play .ogg, so that is in. .m4a plays only if FiveM's browser
    -- has the AAC codec: a track that fails is skipped for the next one. The
    -- manifest's files entries must cover the same types.
    extensions = { '.mp3', '.wav', '.ogg', '.m4a' },

    -- The tracks by file name, e.g. { 'chase1.mp3', 'chase2.ogg' }. Leave it
    -- empty and the server reads the folder when the resource starts, the way
    -- single player does; list them if the folder can't be read on your host.
    tracks = {},

    volume = 0.3,           -- [Music] Volume, 0 to 1 (0.3 in the shipped ini; the code's default is 0.1)
    muffleLevel = 0.25,     -- MuffleLevel: the part of Volume left while the weapon wheel or inventory is open
    -- A fade moves the volume by 1 (the whole 0 to 1 range) in this many
    -- seconds. As in single player, only the first frame up from silence
    -- goes at FadeInSeconds and the rest of the way up at BoostSeconds, so
    -- at Volume 0.3 a chase fades in in about 0.3 x 0.9 = 0.27 s and out in
    -- 0.3 x 1.6 = 0.48 s.
    muffleSeconds = 0.25,   -- MuffleSeconds: any fade while muffled, and any step down while still wanted
    fadeSeconds = 1.6,      -- FadeSeconds: out, when the wanted level goes or something interrupts it
    fadeInSeconds = 1.4,    -- FadeInSeconds: the first frame up from silence
    boostSeconds = 0.9,     -- BoostSeconds: every other step up: the rest of a fade in, and back from muffled
    activeVolume = 0.28,    -- ActiveVolume: single player reads it but nothing uses it; no effect here either
    drivingSpeed = 12,      -- DrivingSpeed (m/s): likewise read and unused in single player; no effect
    stallMs = 400,          -- StallMs: the track pauses where it is when the music hasn't been updated for this long
}
