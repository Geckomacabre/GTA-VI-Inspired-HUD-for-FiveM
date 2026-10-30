# vi_chasemusic: CHASE MUSIC

Single player's wanted-level music (GTA6Hud's `MusicPlayer`, ini `[Music]`),
for FiveM. HUD OPTIONS row: `chasemusic`, **CHASE MUSIC**.

## What it does (as single player does)

- While the player has a wanted level (any number of stars), a random track
  from `music/` plays. When it ends, another random one follows, never the
  one that just played. GTA's own wanted music is switched off meanwhile
  (`SET_AUDIO_FLAG("WantedMusicDisabled")`) and back on when the music stops.
- Volume `0.3`. A fade moves the volume by 1 (the full 0 to 1 range) in:
  `1.4 s` for the first frame up from silence (FadeInSeconds), `0.9 s` for
  every other step up (BoostSeconds), `0.25 s` while muffled or stepping down
  while still wanted (MuffleSeconds), and `1.6 s` out (FadeSeconds). Single
  player's code uses FadeInSeconds for that first frame only. So at volume 0.3
  a chase fades in in about 0.27 s and out in 0.48 s.
- It fades out when the wanted level goes, or when the player is dead, is
  being arrested, or the screen is fading or faded out.
- It drops to `0.25` of the volume while the wheel is open.
- It stops at once, with no fade, for the pause menu, when CHASE MUSIC is
  switched off, or while the radio plays the player's own music. The next
  chase starts a new random track.
- If its update stops coming for `400 ms` (single player's stall watchdog),
  the track pauses where it is and goes on when the updates return.
- With no tracks, the HUD OPTIONS row shows NONE.

All of `[Music]` is in `config.lua`, with single player's defaults from the
ini it ships (`Enabled = False`, `Volume = 0.3`).

## What is different on FiveM

- **Where it plays.** Single player plays through Windows' media player.
  Here the audio plays in this resource's NUI page (`html/`). The page never
  takes focus. `client.lua` works out the volume each frame as single player
  does, and the page sets it.
- **The track list.** A FiveM client can't list a folder. So `server.lua`
  reads `music/` when the resource starts (with `io.readdir`, or `dir`/`ls`
  through `io.popen` on older servers) and shares the names in
  `GlobalState.viChaseMusicTracks`. Players download the files through the
  manifest's `files` entries. You can list tracks in `config.lua` `tracks`
  instead. Restart the resource after changing the folder.
- **File types.** Single player takes `.mp3 .wav .wma .m4a`. Browsers can't
  play `.wma`, so it is dropped here. `.ogg` is added. `.m4a` plays only if
  FiveM's browser has the AAC codec; a track that fails is skipped.
- **The wheel.** Single player muffles under its own weapon wheel. Here it
  muffles under GTA's weapon wheel (HUD component 19) or while ox_inventory is
  open (`LocalPlayer.state.invOpen`).
- **The pause menu.** Single player stops the music for GTA's pause menu and
  for its own. Here that means GTA's pause menu or vi_pausemenu
  (`LocalPlayer.state.pauseMenuOpen`).
- **The radio.** Single player plays nothing while its radio has one of the
  player's own music stations selected. vi_radio's match is On Demand:
  `exports.vi_radio:IsOnDemandOn()`, checked four times a second. vi_radio
  only counts it for the vehicle the player sits in, and only for the driver
  if its `DriverOnly` is set.
- **Screens that pause it.** Single player pauses the track through its stall
  watchdog while its kill camera, races, customs, wardrobe, gun store and ATM
  screens skip the music update. Those screens aren't part of this feature.
  A feature that should pause the music calls
  `exports.vi_extras:HoldChaseMusic(key, true)`, then `(key, false)`.
- **Window focus.** Single player also pauses the track while the game window
  isn't in front. FiveM can't tell a resource that, so that part is left out.
- **GTA's music volume.** Single player doesn't follow the game's music volume
  setting; only `[Music] Volume` sets it. The same is true here.
- **Cutscenes.** Single player has no cutscene check of its own. Only the
  screen fading out (and the wanted level, which cutscenes usually clear)
  stops it. That is kept.
- `ActiveVolume` and `DrivingSpeed` are read by single player, but nothing in
  its music uses them. They are in `config.lua` for completeness and have no
  effect.

## Public API

```lua
exports.vi_extras:IsChaseMusicPlaying()     -- a track is playing or fading out
exports.vi_extras:HoldChaseMusic(key, on)   -- pause it where it is while any key holds it
```
