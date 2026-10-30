# Chase music tracks

Put your own `.mp3`, `.wav` or `.ogg` files in this folder (`.m4a` too, if
FiveM's browser can play it on your build). They play as wanted-level music
when a player has CHASE MUSIC on in HUD OPTIONS (hold V). No music ships with
VI HUD.

- Restart `vi_extras` after adding or removing tracks: the server reads this
  folder when the resource starts.
- Every player downloads these files when they join, as with any resource
  file, so keep them to a sensible size.
- Plain file names travel best (letters, digits, spaces, `-` and `_`).
- The type must be in `extensions` in `../config.lua` and in the manifest's
  `files` entries for `vi_chasemusic/music/`.
- If your host won't let the server read the folder, list the file names in
  `tracks` in `../config.lua`.
- Players start with it OFF, as in single player; set `default = true` in
  `../config.lua` to start them with it ON.
