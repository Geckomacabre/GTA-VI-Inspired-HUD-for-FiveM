# GTA VI Radio for FiveM

A FiveM port of **VI Radio**, the GTA V Legacy singleplayer mod by *sej0bec*: a
GTA VI–styled radio carousel, a mute system, station logos, and a slow-motion
effect while you browse stations. Plus **On Demand** — play YouTube links
through the car radio, as a shared queue everyone in earshot hears, and the
server's own stations.

The single-player GTA VI-Inspired HUD carries a port of this resource
(ViExtras' radio). The two look and behave the same: the layout, colours,
controls and timings here are that port's, measured off the same reference
shots.

No framework dependency. On Demand needs [xsound](https://github.com/Xogy/xsound)
installed; without it the wheel still works and On Demand switches itself off.

![The radio wheel open in a vehicle, the switch at RADIO](docs/radio.png)

![The same wheel with the radio muted](docs/radiomuted.png)

> The pictures in `docs/` show the earlier look (framed tiles, faded
> neighbours, white text). The wheel now looks like the single-player one:
> see [The HUD](#the-hud).

## Install

1. Copy the `vi_radio` folder into your server's `resources/` directory.

   > The folder **must** be named `vi_radio`. If you cloned this repo, rename the
   > checkout — the resource name is what `exports['vi_radio']` resolves to.

2. Add to `server.cfg`:

   ```
   ensure vi_radio
   ```

3. Tune `config.lua` to taste.

4. For On Demand, make sure `xsound` is started **before** `vi_radio`. Set
   `Config.OnDemand.enabled = false` if you do not want it at all.

## Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Open the radio wheel | Hold GTA's radio wheel key (**Q**), or `Config.OpenKey` | Hold GTA's radio wheel button (**D-pad Left**) |
| Previous / next station | **←** / **→**, or the mouse wheel | **Right stick** left / right (one station a push), or **D-pad Up** / **D-pad Right** |
| Change the song (On Demand playing) | The mouse wheel, or GTA's next / previous track keys | **D-pad Right** / **D-pad Up**, or GTA's track buttons |
| Mute / unmute | **O** in a vehicle, or **Space** while the wheel is open | **Click the right stick** (or **D-pad Down**) while the wheel is open |
| Throw the radio / On Demand switch | **↓** for On Demand, **↑** for radio | **Right stick** down / up |
| Open the On Demand panel | **↓**, then release the wheel — or `/ondemand` | Same |

The wheel opens on the game's own radio wheel control, on the keyboard and the
pad alike, so it follows wherever the player's GTA settings put it, as GTA's
radio wheel does. `Config.OpenKey` (Q) is an extra keyboard key on top. Whether
the pad or the keyboard steers is whichever the player touched last. GTA's next
/ previous station keys keep working on a keyboard, and the HUD follows the
station; on a pad they share D-pad Left with the wheel, so there they are off.

The switch works from anywhere in the wheel; there is nothing to scroll to. It
is thrown the way the artwork reads — `RADIO` is the top position, `ON DEMAND`
the bottom one — so down engages On Demand and up hands the radio back.

Up and down therefore belong to the switch, which is why mute sits on Space on a
keyboard (the handbrake, no great loss while you are reading the radio) and on a
right-stick click on a pad. D-pad Down still mutes too
(`Config.Controller.dpadDownMute = false` drops it, as single player did because
D-pad Down is its character wheel). `O` works in any vehicle, wheel open or not,
and flashes the HUD to show the new state. Set `Config.OnDemand.switchKeys =
false` to leave up and down alone and reach On Demand through the panel and
`/ondemand` only.

Browsing unmutes, and so does throwing the switch to On Demand; the station is
put on after the radio is back on.

The wheel is **vehicle-only** and, by default, **driver-only**. Set
`Config.DriverOnly = false` to let passengers use it too, or
`Config.AllowOnFoot = true` to extend it to the mobile radio on foot.

Nothing opens or mutes while something else has the buttons: the pause menu
(GTA's or `vi_pausemenu`'s), a cutscene, a loading screen or black screen, the
phone, being dead, the crash cam (`vi_crashcam`), the binoculars
(`vi_binoculars`), and any menu listed in `Config.BlockedBy`.

The keyboard keys are rebindable under **Settings → Key Bindings → FiveM**.

### VI RADIO WHEEL (on / off)

Each player can switch the wheel off in HUD OPTIONS (**VI RADIO WHEEL**, from
`vi_extras`), and GTA's own radio wheel comes back: its wheel and station HUD,
its station keys, no slow motion. A car playing On Demand gets back the station
it had, and the radio is unmuted. The choice is kept on the player's client;
`Config.WheelEnabled` is the default for anyone who has not chosen. Listening to
On Demand from other cars, `/ondemand` and the exports keep working.

### How the controller binding works

The controller does **not** go through FiveM's key-binding system. A binding
registered with `RegisterKeyMapping` is only a *default*: once a client has
stored a binding for a command, a default added later never reaches it. So the
wheel reads `INPUT_VEH_RADIO_WHEEL` directly — the game's own radio wheel
control, Q and D-pad Left out of the box, and whatever the player has rebound it
to otherwise. The stock wheel is suppressed every frame so it cannot open on the
same button.

Because that button is *held* to keep the wheel open, and is simultaneously
`INPUT_CELLPHONE_LEFT` and `INPUT_WEAPON_WHEEL_PREV`, it cannot also mean
"previous station" — holding it would step the station every frame. Browsing on a
pad is therefore the right stick (as in the vanilla wheel), one station a push
however long it is held, with D-pad Up and D-pad Right as alternates that repeat
when held. A right-stick click nudges the stick, so a click holds the stick
still until it comes back to the middle. While browsing on a pad the camera is
locked so the right stick does not swing the view; set
`Config.Controller.lockCamera = false` if you would rather it did.

While the wheel is open, the buttons it uses do nothing else: the headlights
(D-pad Right), the drive-by weapon select (the mouse wheel), look behind (the
right-stick click), and D-pad Down / Left Alt / Z, which stay off until let go.
Set `Config.Controller.enabled = false` to drop controller support entirely.

### Troubleshooting

Run `viradio_debug` in the client console (F8) while sitting in a vehicle. It
prints whether the wheel is switched on, whether you are in a valid seat, how
many stations were found, which list the wheel shows, whether it thinks it is
open, what is holding it shut (and what held it shut last), the song it found,
and the live state of the radio wheel control and every On Demand session.

## The HUD

The single-player look, by numbers (1080p pixels, scaled to the player's
resolution; all of it in `Config.Hud`):

* **Tiles** 103 square, 118 apart, the highlighted one on the screen's centre
  line, 32 from the top. Each logo fills its tile (the box colour shows only
  behind transparent corners). Every tile is at full size and opacity out to
  two either side; they fade out on the way to the third. The highlighted one
  is 1.03 times larger with a 2.5 outline in the text grey.
* **Side icons** 37 either side of the five-tile carousel, centred on the
  tiles, at 0.9 opacity: the radio / On Demand switch on the left, the mute
  indicator (24 tall) on the right.
* **Under the tiles** a 189 × 4.8 line 20 below them, then the station name
  (25.3 px), the song (20.6 px) and its artist (20.6 px) at 34.7, 70.6 and 97.2,
  all in light grey (192, 194, 200) without a shadow, cut with an ellipsis at
  642.6 wide.
* **Timings** the carousel slides in 110 ms on `cubic-bezier(0.22, 0.61, 0.36,
  1)`; the HUD fades in 160 ms; the mute indicator changes colour in 140 ms; a
  mute flash stays up 1.4 s. The open / close clicks play at 20%.

The song and its artist are the game's own names for the track playing, read
from its labels. Just after a change of station the old song's name stays off
for up to 3 s, until the new station's song is the one playing. With no song (a
talk station) the line under the station is its genre (`Config.Hud.subtitle =
'none'` leaves it empty). A highlighted RADIO OFF shows only its name.

When the radio is muted the indicator turns red (`Config.Hud.mutedColor`) and
the rest of the HUD drops to greyscale, so the two states cannot be mistaken for
each other at a glance. Set `Config.Hud.muteDim = false` to keep the colour and
recolour only the indicator. Nothing of the HUD shows over the pause menu, a
cutscene or a black screen.

The earlier look is still in reach: `inactiveScale = 0.9`, `inactiveOpacity =
0.55`, `activeScale = 1.0`, `borderSize = 3.5` with `borderColor =
'255,255,255,90'` and `borderActiveColor = '255,255,255,255'`, `inkColor =
'255,255,255,255'` and `textShadow = true`.

While the wheel is open the local player's state bag `vi_radio:open` is true,
for a HUD that wants to hide its own minimap then.

## Chase music

While you are wanted and the game's chase music plays, the car radio goes quiet,
and comes back 3 s after the music stops (so a gap between tracks doesn't bring
it back) or at once when the stars go. The player's own mute is left as it was,
so `IsMuted` stays false. `Config.ChaseMusicTakesOver = false` lets them play
together.

## On Demand

![The switch thrown to ON DEMAND, with the panel open](docs/radio_on_demand.png)

The icon to the left of the carousel is a two-position switch, `RADIO` over
`ON DEMAND`. It is the original mod's own artwork, redrawn so the knob can
actually move between the two positions — it slides down and `ON DEMAND` lights
up while `RADIO` dims, and back again. (With `Config.OnDemand.enabled = false`
the static artwork is shown instead, exactly as the original drew it.)

* **Down — On Demand.** The station that was playing is remembered, the game
  radio goes quiet, and the wheel lists On Demand's stations instead of the
  radio's: first `ON DEMAND`, this vehicle's own queue, then the server's
  stations (`Config.OnDemand.stations`). Letting go of the wheel on the queue
  opens the panel: paste a YouTube link (or a direct `.mp3` / `.ogg` / `.wav`
  URL) and either play it straight away or add it to the vehicle's queue.
* **Left / Right** (the right stick) step through On Demand's stations, as they
  do the radio's, and each plays as it is reached. While one plays, the mouse
  wheel (D-pad Right / Up) and GTA's next / previous track keys change the song;
  the track keys skip with the wheel shut too.
* **Up — radio.** Playback stops and the remembered station comes back.

A station put on any other way (GTA's station keys, or GTA's own wheel with VI
RADIO WHEEL off) switches On Demand off and keeps that station.

The switch stays down when the queue runs out or is emptied — the vehicle is
simply silent until something else is queued — so "nothing playing" and
"switched off" are two different states. Reopen the panel at any time by
throwing the switch down again, with `/ondemand`, or from inside the panel.

`Config.OnDemand.stationsInWheel = false` keeps the radio's stations listed
while On Demand is on, as before: scrolling then only *previews* stations, the
one you let go on is applied, and that is what switches On Demand off (keeping
the station you picked rather than the remembered one).

### The server's stations

The single-player HUD's On Demand plays the player's own music: each folder of
tracks on their disk is a station. A server can only play what it ships or what
a link points at, so here a station is a list of tracks in `config.lua`:

```lua
Config.OnDemand.stations = {
    {
        label  = 'CHILL',
        genre  = 'Lo-fi',                -- the line under it, optional
        logo   = 'logos/Chill.png',      -- a tile picture under html/, optional
        tracks = {
            'music/chill/01 Morning.mp3',                          -- shipped, under html/
            'https://example.com/night.mp3',                       -- a direct link
            { url = 'https://youtu.be/xxxxxxxxxxx', title = 'Song', artist = 'Someone' },
        },
    },
}
```

Shipped files go in `html/music/<station>/` (mp3, ogg, wav, m4a, aac, flac);
`fxmanifest.lua` streams that folder, so **every player downloads them when they
join** — a web host and links keep the download small. A track without a title
is named after its file (or YouTube's title). A station plays its tracks in
order, round and round, and each vehicle remembers where each station was for
`resumeMinutes` (30). Pasting a link while a station plays puts it on the
vehicle's own queue; Stop goes back to that queue, empty.

### Everyone nearby hears it

* **Everyone nearby hears it.** The audio is positioned at the vehicle, so
  passengers and anyone stood close by hear the same track at the same point in
  it. `Config.OnDemand.distance` sets how far it carries.
* **Everyone can use it.** Whoever may drive the radio (the driver, or anyone
  sitting in the vehicle with `Config.DriverOnly = false`) can queue, skip,
  pause or stop — there is no job check and no permission gate. That is
  deliberate.
* **The server owns playback**, keyed by the vehicle's network id, so a
  passenger who joins halfway through a track hears it from the right place
  rather than starting it again.
* **Track titles** are looked up through YouTube's oEmbed endpoint (no API key)
  and drive the HUD's title and artist lines. Set
  `Config.OnDemand.fetchTitles = false` to stop the server making that request.

Because anyone can play anything, the panel also carries the two controls that
protect a listener without restricting who may broadcast: **your own volume**
(capped by `Config.OnDemand.maxVolume`) and a **mute all On Demand audio**
toggle. Both are per player, saved on that client, and affect nobody else.

Your volume is also scaled by the game's radio volume setting, as single
player's own music is (`Config.OnDemand.followRadioVolume = false` stops that).
On Demand goes quiet for you over the pause menu, cutscenes, black screens and
while you are dead, and the car you are in goes quiet for you while you have the
radio muted or the chase music has it; the track carries on in step, so it comes
back where everyone else is.

> **Worth knowing:** xsound plays YouTube through the IFrame API, which is not
> what YouTube's terms of service intend it for. It is how effectively every
> FiveM audio resource does it, and it is not enforced in practice, but it is
> your call to make before running this on a public server.

## Configuration

Everything lives in `config.lua`, mirroring the original mod's `VI Radio.ini`
and the single-player HUD's `[Radio]` section:

* **On / off** — `WheelEnabled`, the default for VI RADIO WHEEL.
* **Controls** — keys, mouse-wheel scrolling, arrow auto-repeat (on real time,
  not the slowed game clock), controller options, whether passengers and on-foot
  players can use it, and the menus it stands down for.
* **Feel** — `TimeScale` (eased in and out over `TimeScaleFade` real ms),
  timecycle modifier and strength, hi-DOF, radar hiding, open/close sounds and
  volume, `LoudRadio`, `ChaseMusicTakesOver`.
* **HUD** — tile size, spacing, colours, outline, scales, slide time, side
  icons, the info-line and text positions. Values are authored at 1920x1080 and
  scale to the player's resolution.
* **Stations** — display label, logo and genre per station, `HiddenStations`.
* **On Demand** — stations in the wheel, the server's stations, queue limit,
  audible distance, default and maximum listener volume, following the radio
  volume, title lookup, accepted link types, and the sync/rate-limit timings.

## Adding or hiding stations

`Config.Stations` maps a game station name to its display label, logo file and
genre. Stations the game reports as unlocked but that are missing from the table
still appear, using a tidied version of their raw name and a text tile instead
of a logo. To drop one from the wheel, list it in `Config.HiddenStations`, or:

```lua
['RADIO_05_TALK_01'] = { label = 'West Coast Talk Radio', hidden = true },
```

Logos live in `html/logos/` — drop in a PNG and reference it by filename.

## Exports

```lua
exports['vi_radio']:SetNowPlaying(title, artist)
exports['vi_radio']:IsOpen()        --> boolean
exports['vi_radio']:IsMuted()       --> boolean, the player's own mute
exports['vi_radio']:SetMuted(bool)
exports['vi_radio']:GetStation()    --> current station name, or 'ONDEMAND'

-- VI RADIO WHEEL (client): this wheel, or GTA's own. Saved per player.
exports['vi_radio']:GetWheelEnabled()      --> boolean
exports['vi_radio']:SetWheelEnabled(bool)  -- takes effect at once

-- On Demand (client)
exports['vi_radio']:IsOnDemandOn()       --> boolean, the switch position
exports['vi_radio']:IsOnDemandPlaying()  --> boolean, a track is actually running
exports['vi_radio']:SetOnDemand(bool)    --> flip the switch
exports['vi_radio']:GetOnDemandTrack()   --> { title, artist, paused, position } or nil
exports['vi_radio']:OpenOnDemand()

-- On Demand (server)
exports['vi_radio']:GetOnDemandSession(vehicleNetId)  --> session table or nil
                                                      --  (with station: 0 the queue, else Config.OnDemand.stations[n])
exports['vi_radio']:StopOnDemand(vehicleNetId)
```

`SetNowPlaying` overrides the game's own song names on the title and artist
lines, for a server whose stations the game cannot name (custom streamed
stations, xsound, a metadata feed); `SetNowPlaying(nil, nil)` hands the lines
back to the game. From the server:

```lua
TriggerClientEvent('vi_radio:setNowPlaying', src, 'Track title', 'Artist')
```

## Differences from the singleplayer mod

The original is a compiled ScriptHookVDotNet plugin. FiveM cannot load SHVDN
assemblies, so this is a rewrite rather than a drop-in conversion. The
behaviour, layout values, station list and artwork carry over; the
implementation does not.

* **HUD** — drawn with NUI (`html/`) instead of native textures. Every value
  from the `[HUD]` section of the original `.ini` is passed to the page as CSS
  variables, so the layout stays fully tunable.
* **Slow motion** — `SetTimeScale` is client-side only. While the wheel is open
  the player's vehicle drifts out of sync with what everyone else sees, and the
  longer the wheel is held the more visible that is. It is on by default to
  match the original feel; set `Config.TimeScale = 1.0` to keep only the HUD.
* **Mute** — uses `SetVehicleRadioEnabled` (and, only with
  `Config.AllowOnFoot`, `SetMobileRadioEnabledDuringGameplay`) so the station is
  preserved, is re-applied when the player changes vehicle, and gives the car
  muted before its radio back on unmute.
* **In-game settings editor (F10)** — dropped. Edit `config.lua` instead.
* **Non-Stop-Pop song replacement** — the optional part of the original download
  is an OpenIV `.rpf` swap. On a server that would have to ship as a streamed
  audio pack for every client, so it is not included.

### Compared with the single-player HUD's port

* **On Demand** — single player's plays the player's own music from their disk;
  here it is the shared YouTube queue and the server's stations (above).
* **Audio scenes** — single player stops scenes that silence the radio
  (`[Radio] RadioMutingScenes`). On FiveM an audio scene belongs to the resource
  that started it, so the resource that starts it has to lift it (see the note
  in `config.lua`).
* **Keeping the radio audible outside the car** — here an invisible stand-in
  driver keeps an empty car's radio playing after you get out; single player
  leaves that to GTA6Hud's `[Radio] OutsideCar`.
* **The minimap** — single player hides its drawn minimap while the wheel is
  open; here the engine's radar is hidden, and the `vi_radio:open` state bag is
  there for a HUD that draws its own.

## Credits

* **sej0bec** (GTA5-Mods user `sbc17`) — VI Radio for GTA V Legacy Edition: the
  concept, HUD design, station logos, icons and sound effects. This port would
  not exist without it.
  Original mod: <https://www.gta5-mods.com/scripts/vi-radio-v1-0>
* **Vernon Adams** and The Anton Project Authors — the Anton typeface, SIL Open
  Font License 1.1 (`html/fonts/Anton-OFL.txt`).
* **Logopedia** (logos.fandom.com) — the station logos the original mod did not
  ship artwork for: West Coast Talk Radio, Blonded Los Santos 97.8, LS
  Underground Radio, iFruit Radio, Still Slipping Los Santos, Kult FM, The Music
  Locker, Media Player and MOTOMAMI Los Santos.
* **xsound** — the audio backend On Demand plays through.

## License

Code is released under the [PolyForm Noncommercial License 1.0.0](LICENSE.md).
You may use, modify and share it for any noncommercial purpose. You may **not**
use it, or anything derived from it, for commercial advantage or monetary
compensation — that includes selling it, bundling it into a paid package, and
putting it behind donation perks, subscriptions or any other paid tier.

The artwork and sound effects in `html/` are the work of **sej0bec** and are
redistributed here with credit; they are not covered by this license. Ask the
original author before reusing them elsewhere.

The nine station logos sourced from Logopedia are Rockstar Games' trademarks,
included here the same way any GTA fan resource includes them. They are not
covered by this license either.

The Anton font is under the SIL Open Font License 1.1, whose text ships beside
it in `html/fonts/Anton-OFL.txt`.
