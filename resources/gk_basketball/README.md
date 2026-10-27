# gk_basketball

A playable basketball game for FiveM. Self-contained: ball handling, shot mechanics,
score detection and timed pickup matches, with no throwables dependency.

Built for Qbox (`qbx_core`), using `ox_lib`, `ox_target` and `ox_inventory`.

---

## Install

1. Drop this folder in `resources/[standalone]/`.
2. Add to `server.cfg`, after `ox_lib`, `ox_target` and `ox_inventory`:

   ```
   ensure gk_basketball
   ```

3. Register the `basketball` item in your `ox_inventory`:
   - Copy `ox_inventory-item/basketball.png` into `ox_inventory/web/images/`.
   - Add this entry to `ox_inventory/data/items.lua`:
     ```lua
     ['basketball'] = {
         label       = 'Basketball',
         description = 'Use it to start dribbling. Find a court and put it through the hoop.',
         weight      = 600,
         stack       = true,
         close       = true,
         client      = {
             export = 'gk_basketball.useBasketball',
         },
     },
     ```

4. Grant yourself hoop-placement rights in `permissions.cfg`:

   ```
   add_ace group.admin gk_basketball.manage allow
   ```

5. **Courts.** The Maze Bank Arena's is set up already (next section). Courts out in
   the world are marked by placing their hoops, further down.

---

## The Maze Bank Arena

`mzb_arena` puts a full hardwood court on its floor for its basketball show, with
its own baskets. This resource plays on that court as it stands: it is described
in `Config.Courts.arena`, with the two rims measured from the arena's court model,
so shots meet the iron where you see it.

**The arena decides; this only follows.** What is on the arena's floor is set
from the arena's own `/arena` menu, by whoever is allowed to use it. Nothing here
changes that, and the arena's hoops can't be placed, moved or deleted with the
hoop tools below.

- While the arena is set up for basketball, **an attendant stands at the side of
  the court, half way along**. Talk to them (ox_target) to join a pickup game,
  start a match, add an AI player, take a ball or leave.
- **Basketballs lie on the court** (by each free-throw line and near the
  attendant). Walk up to one and press `E` and you have a ball: shoot around for
  as long as you like, with no game to join. See *Practice balls* below.
- When the arena is changed to anything else, the court, the attendant and the
  balls go, and a game in progress ends.
- Games here are not instanced, so the crowd sees them.

---

## Practice balls

Every court has a few basketballs lying on it. Walk up to one, `E`, and it is in
your hands; a few seconds later another is back on the floor where it was. No
match, no opponent, no item needed. Baskets you make outside a match are called
out but don't go on a scoreboard.

`Config.Ball.looseBalls` is how many a court gets near its middle when it has no
list of its own (`Config.Courts[...].balls`); `0` turns them off.
`Config.Ball.looseRespawn` is how long one takes to come back. During a one-ball
match the players in it can't pick up a second ball; anyone else still can.

---

## Placing hoops (for courts out in the world)

GTA's basketball hoops are part of the map, not props, so there is no way to find a
rim from code. The coordinates have to be measured once per court, by eye. The tool
makes it quick.

Stand on a court, look at a rim, and run:

```
/bball_place chamberlain
```

A green rim outline appears where you're looking, with the scoring cylinder drawn
above it so you can see the volume a shot has to pass through.

| Key | Action |
| --- | --- |
| `W` `A` `S` `D` | move horizontally, relative to your camera |
| `Q` / `E` | lower / raise |
| hold `SHIFT` | fine steps (1cm instead of 5cm) |
| `ENTER` | save |
| `BACKSPACE` | cancel |

Line the outline up with the real rim and hit `ENTER`. It's written to
`data/hoops.json` and pushed to every connected client immediately — no restart.

Repeat for the second hoop, using the **same court id**. A court is just a group of
hoops sharing an id; its centre (blip and interaction point) is averaged from them.

Other commands:

- `/bball_hoops` — list every hoop, with coordinates, in F8
- `/bball_delhoop` — delete the nearest hoop within 15m

Set `Config.Debug = true` to keep rim outlines drawn on every nearby hoop, which is
the fastest way to check your alignment.

### Half court vs full court

- **Leave the team argument off** for pickup rules: both hoops score for whoever
  shoots. This is what you want for most RP courts.
- `/bball_place mycourt home` tags a hoop as the home team's basket. With tagged
  hoops, each team scores on the *other* team's rim, and putting one through your
  own basket credits the opposition.

---

## Playing

**Getting a ball** — pick one up off the court (`E`), use a `basketball` from your
inventory, or target the court centre (or its attendant) and pick *Grab a basketball* (free, no item needed; turn off with
`Config.Match.freeBallsOnCourt`).

**Shooting** is GTA VI's (`Config.Shot.style = 'rings'`). Hold `RMB` (left
trigger) to aim: the camera comes in over your right shoulder with a thin white
ring and a dot in the middle of the screen. Put a rim under it and a smaller
yellow ring locks on: bigger for a shot from close in, smaller from further out.
Hold `LMB` (right trigger) and the white ring closes in; let go as it meets the
yellow one (it turns yellow too at that moment). The ring closes at a steady speed,
so how far it was from the yellow one is a timing error in ms, judged by
`Config.Shot.timing` exactly as the timed shot below is. Hang on until it has
closed to nothing and the ball goes anyway, as late as a release gets. With no
rim under the reticle, letting go throws the ball where you are looking, harder
the longer you held. `LMB` without aiming just throws it that way.

**What's on screen** comes from `vice_hud` when it is running (`Config.Hud`), the
way GTA VI's basketball has it: a ball lying within reach has its name beside the
pickup button, on the ball; while you have one, `THROW` and `AIM` (and `PASS` in a
match) are in the bottom right corner, the ball is where the weapon icon goes, and
the first time each session the help box says how to shoot, with the buttons in
the line. Each basket outside a match is "1 scored", "2 scored" in the feed with a
hoop beside it (the count starts again when you put the ball away or leave the
court), and it trains vice_hud's **Focus** skill, with the card that says so
("Focus +2%"): granted by this resource's server, which is where the basket was
checked. Without `vice_hud`, ox_lib's text box and notifications say the same
things.

Two older ways to shoot are still there:

- `'timed'`: hold `LMB` and you go up for a jump shot there and then, straight out
  of the dribble; let go as the ball leaves your hand, at the top. That moment is
  the green band on the bar, and a word on the screen says whether you were early,
  late or perfect. Needs the animation pack, which is what knows when the ball
  leaves. Once you have landed the follow-through is yours: stand and watch the
  shot and the arm stays up, touch the stick and you are away. While you are going
  up, the rim you're locked onto lights up in green with the points and range over
  the top (`Config.AimMarker = false` turns it off).
- `'meter'`: hold `RMB` to line up, standing still in a two-handed stance while a
  meter swings, and tap `LMB` in the green. What `'timed'` falls back to without
  the pack.

Distance matters independently of your release — a perfect release from the arc is
still a much harder shot than a perfect release from under the rim.

The ball is then real physics, and not the game's: see *The ball* below. Nothing
is scripted to "go in". Rim bounces, in-and-outs and swishes happen because a ball
went through, or didn't go through, a ring of iron.

| Key | Action |
| --- | --- |
| hold `RMB`, hold `LMB`, let go as the rings meet | shot |
| `LMB` | throw the ball where you are looking |
| `E` | pass to the nearest player (they catch it without pressing anything) |
| `G` | put the ball away |
| `E` near a ball lying still | bend down and pick it up |
| `E` next to somebody with a ball | reach in and try to knock it loose |

**Passing and reaching in** use only your arms and back, so neither stops you:
a pass made on the run is made on the run.

**A ball that comes to you is caught.** A rebound dropping into your arms, a loose
ball bouncing past your hip: no key. It has to be moving and to have been loose
for a moment (`Config.Ball.autoCatch`), so a shot isn't taken back out of the
shooter's hands and a ball lying still stays put until somebody bends down for it.

**Defence.** Stand between a shooter and the basket, within arm's reach, and their
shot gets worse (`Config.Shot.contestFactor`) whether or not you touch the ball.
Get a hand or a body actually in its path and it is blocked, because the ball
bounces off players. A reach-in (`Config.Steal`) knocks the ball loose for
whoever gets to it; it works far less often on somebody lined up to shoot than on
a dribble.

**Water, falls, cars.** You can't dribble while swimming, ragdolled or getting
into a car: the ball leaves your hands. In water it floats.

**Matches** — target the court centre to *Join pickup game*. Teams auto-balance onto
the smaller side. Once `Config.Match.minPlayers` have joined, anyone in the lobby can
*Start match*. A scoreboard appears top-centre with the clock, both scores and a
per-player points list.

Baskets score 2, or 3 from beyond `Config.Scoring.threePointDistance` measured from
where you released. The game ends on the clock or at `Config.Match.scoreLimit`,
whichever comes first, then resets to a lobby.

A match is played with **one ball** (`Config.Match.oneBall`). At tip-off the court
is cleared and somebody is handed it; after each basket the side that was scored
on gets it; nobody can take a second off the rack while one is in play. Set it to
`false` for the older shooting contest where everyone has their own.

**NPCs** — target the court centre, *Add an AI player*, pick a difficulty. It joins
the smaller team and plays: chases loose balls, works to a spot and shoots,
gets between you and the basket when you have it, puts its hands up (and sometimes
jumps) when you line up, and reaches in on a dribble. Everyone on the court sees
it. It doesn't pass or set screens.

Shooting outside a live match still works and still tells you what you scored — it
just doesn't touch a scoreboard.

`/bball leave` and `/bball start` work if you'd rather not use the target.

---

## The ball

A loose ball is not left to the game's prop physics. `client/physics.lua`
simulates it, in real units with a real basketball's numbers:

- **Flight**: gravity, air drag, and lift from spin. A shot carries backspin.
- **Bounces**: restitution plus friction at the point of contact, so spin and
  travel are traded on every bounce. Backspin makes a ball check up; a ball off
  the side of the rim kicks. Dropped from 1.8m it comes back to about 1.15m.
- **Surfaces**: read from the map where it lands. Lively on a hard court or
  wood, dead in sand and long grass, and it rolls a long way on concrete and
  hardly at all on a beach.
- **The rim**: a ring of iron in space that the ball has to fit through. A flat
  shot clips the front of it. Hoops whose map model already has collision on
  the ring use that; the rest get a calculated one (`/bball_phys` says which).
- **The net** takes the pace off a ball dropping through.
- **Players**: it bounces off bodies and hands. A moving hand passes its speed
  on, which is all a block is. Walk into a ball on the floor and you kick it.
- **Fences and glass** stop it. A chain-link fence round a court and a glass
  backboard are "see-through" to the game's usual collision tests; the ball's
  tests don't skip them, so a missed shot stays in the cage.
- **Water**: it floats, because of what it weighs and the water it pushes
  aside: about 4cm deep, bobbing on the swell and sliding down the faces of
  waves. A ball on the beach floats off when the tide reaches it.
- **Sound**: bounces, the rim, the backboard, the net, a catch, shoes on the
  court and splashes, heard by everyone nearby, quieter with distance and on the
  side they are on. They are recordings (`html/sounds`, 126 files): one take
  picked at random each time, at a slightly different pitch, from the set that
  fits. There is a dry outdoor set and an indoor one with the hall in it, used
  wherever the sound happens under a roof, and soft and hard takes for how hard
  the contact was. A dribble at a walk is the soft bounce; a hard stop or a sharp
  cut with a hoop near squeaks indoors and scrapes outdoors
  (`Config.Sound.squeaks`). A kind with no recording (a splash) is synthesised
  in the browser layer, as everything is if the folder is emptied.

  The recordings are converted from a retail game disc you own, like the
  animation pack, and are that game's publisher's property: fine for your own
  use, your call on a server other people join. `manifest.json` says which file
  is what; delete the `.ogg` files and empty its `sounds` to go back to
  synthesised ones.

Whoever owns the ball's network entity simulates it; if that player walks away
the next owner carries on from where it was.

### Checking it without the game

```
python tests/run.py            everything below
python tests/run.py physics    the ball itself (112 checks)
python tests/run.py glue       the ball against a fake game world (90)
python tests/run.py moves      dribble timing, pace matching, catching (50)
python tests/run.py carry      the real client carrying, shooting and catching in a fake game (115 with the pack;
                               39 without it, the rings shot and the vice_hud pieces among them)
python tests/run.py rings      the rings shot's arithmetic: which rim is under the reticle, ring sizes, timing (22)
python tests/run.py anim       the animation pack's index and what is taken from it (28)
python tests/run.py makes      make percentage by release quality and distance
node tests/sfx_test.js         the sound script against the sound files: which recording each sound is (32)
python tests/syntax.py         every Lua file parses
python tests/natives.py        every native call exists and has the right argument count
```

Needs Python with `lupa`. `tests/natives.py` also needs the devtools kit's native
database. The physics file contains no natives, so what the tests run is exactly
what the game runs; `tests/fakegame.lua` stands in for the game to test the file
that connects the two, and `tests/fakeped.lua` adds a ped with animations that
keep time, so `client/ball.lua` can be run as it is: dribbled at every pace,
lined up, shot and caught. None of that replaces looking at it in the game. It
shows the ball is where the animation says it should be; it can't show what the
animation looks like on a ped.

---

## Tuning

Everything is in `shared/config.lua`. The knobs worth knowing:

| Setting | Effect |
| --- | --- |
| `Config.Scoring.rimRadius` | the size of the rim, physically and for scoring. `0.235` default; regulation is `0.229`, arcade is `0.27` |
| `Config.Shot.entryAngle` | the angle shots come down at, which is the arc. `46` default. Lower is flatter and quicker and rims out; below about 35 even a perfect shot hits the front of the iron |
| `Config.Shot.lateralError` / `depthError` | how far a mistimed release strays, per metre of distance. Lower = more shots go in. `python tests/run.py makes <lateral> <depth>` prints what a change does before you try it |
| `Config.Shot.style` | `'rings'` (GTA VI's, the default), `'timed'` or `'meter'` |
| `Config.Shot.rings` | the reticle: ring sizes near and far, how fast the white ring closes (`closeMs`), how far off a rim can be and lock on, the aiming camera |
| `Config.Shot.timing` | for the rings and the timed shot: how many ms either side of the moment is perfect, and where it is as bad as it gets |
| `Config.Hud` | what is shown and how when `vice_hud` runs: the help box, "N scored", Focus XP per basket |
| `Config.Shot.sweetWidth` | how wide the green band is. Wider = easier timing |
| `Config.Shot.distancePenalty` | how much raw distance eats into a perfect release |
| `Config.Shot.contestFactor` | what a defender in your face takes off a shot |
| `Config.Physics.restitution` | how lively the ball is off the floor |
| `Config.Physics.rimRestitution` | a dead rim (low) is kind, a lively one spits shots out |
| `Config.Physics.surfaces` | bounce, grip and roll for sand, grass, dirt, wood, metal |
| `Config.Physics.waveSlide` | how readily a floating ball drifts with the waves |
| `Config.Steal.chance` | odds of a reach-in knocking the ball loose |
| `Config.Toss.maxLift` | ceiling on camera pitch for throws with no hoop targeted, so looking up doesn't launch one into orbit |
| `Config.Shot.aimAssist` | `false` makes every shot a manual camera-direction throw (hard mode) |
| `Config.Match.oneBall` | one ball to a match, or a ball each |
| `Config.Match.duration` / `scoreLimit` | set either to `0` to play purely to the other one |

If a hoop was placed a few centimetres off the real rim, shots will look as if
they pass through the iron or bounce off thin air. Set `Config.Debug = true` to
draw the rims and re-place it with `/bball_place`.

### Animations

**With an animation pack.** If a resource named in `Config.Anims.pack`
(`basketball_assets` by default) is running, its clips replace the stand-ins
described below, and the animation is in charge of the ball rather than the other
way round:

- **The dribble** is a cycle for each pace: standing, walking, jogging, running,
  sprinting. Which one plays follows how fast you are actually moving. The pack
  says when in each cycle the hand lets the ball go, when it meets the floor and
  when the hand has it again, and the ball does exactly that: down from where
  the hand pushed it, back up to wherever the hand is.
- **Whose legs.** Standing still the whole body is the pack's: leaning over the
  ball, knees bent. On the move only the arms and back are, laid over the game's
  own walk and run. The game's legs turn, lean into a change of direction, set
  off and pull up the way a body does; a looped animation over the whole body
  can only be slid about and spun on the spot, which is what stiff looks like.
  `Config.Dribble.body` is `'auto'` for that, `'full'` for the pack's legs
  always, `'upper'` for the game's always; `/bball_body auto|full|upper`
  switches on the spot, to compare.
- **Guarded**, you stand lower: in a match, with an opponent within
  `Config.Dribble.guardRange`, the standing dribble becomes the protective one,
  down over the ball with the other arm up.
- **The shot** is a jump shot. The ball is gathered into both hands as it starts,
  follows them up, and leaves from them when the clip says it does, not after
  `Config.Shot.windUp`.
- **Picking a ball up** bends down for it, and the ball comes up off the floor
  into the hands instead of appearing in them.

`Config.Anims.packClips` says which pack clip is used for what. Changing between
paces waits for the ball to be in the hand and is blended over
`Config.Dribble.blendIn`, and nothing the ball does is a jump from one place to
another: it is eased wherever it changes hands.

The pack is converted from a retail game disc you own by tools outside this
resource; the clips are that game's publisher's property. Fine for your own use;
streaming them to other people who join your server is redistribution, and your
call.

**Without one**, which is how the resource ships:


Every name in `Config.Anims` was checked against the GTA V animation database
(patch v1734), not guessed.

There is no basketball animation set in the game, so every clip here is something
else pressed into service. The shot is `melee@thrown@streamed_core` /
`plyr_takedown_front`, an overhand throw.

`amb@prop_human_movie_bulb@exit` — the change-a-lightbulb scenario exit that
gusti-basketball shoots with — looks right on paper and isn't. It's a scenario
*exit*, so it opens already in the raised pose and unwinds out of it, with the
hand tracking back over the head instead of pushing forward. Shots read as being
flung from behind you.

`Config.Shot.windUp` is how long after the clip starts the ball actually leaves.
Your target and accuracy are locked the instant you release the key, so this only
changes when the shot *looks* like it left, never where it goes.

Both are tunable without a restart, which saves a walk back to the court per guess:

```
/bball_anim shoot melee@thrown@streamed_core plyr_takedown_front
```

```
/bball_windup 220
```

`/bball_anim` with no arguments lists the keys you can retune.

### Dribbling without a pack

There is no dribble animation in GTA V. Not in that dict, not anywhere — every
basketball animation you've seen in a server is a streamed add-on. This section
is what happens when no pack is running.

So the dribble is sold two other ways. The stance comes from the movement clipset:
`anim@move_m@trash` walks with one arm hanging low and loose at your side, which is
as close to working a ball as the base game gets. And the bounce **ends in your
hand** — the top of every bounce is the hand bone, not a fixed height beside you.
That second part is what actually does the work. A ball that bounces on its own
private path next to you reads as floating no matter what the arm is doing; a ball
that arrives where your hand is reads as a dribble even if the arm never moves.

`Config.Dribble.offset` sets where it meets the floor. There's no bounce height to
set, because the hand is the apex. Two knobs shape the rest of it:

| Setting | Effect |
| --- | --- |
| `lead` | metres the bounce is pushed out in front of you at a sprint. A dribbler at speed puts the ball ahead and runs onto it; pinned to your hip it reads as carrying, not driving |
| `handDwell` | fraction of each bounce the ball rests in your hand before the next push |

The bounce curve is the real one — height under gravity is parabolic in *time*, so
the ball leaves the hand slowly, moves quickest at the floor and decays again on
the way up. Getting that backwards is most of what makes a scripted bounce look
floaty.

If you do want the arm pumping on top of that, `Config.Dribble.handAnim` scrubs an
upper-body clip's phase off the bounce. It's off by default: every stock clip that
moves the arm far enough to notice also bends the spine, and a ped folding in half
after the ball looks much worse than a still one.

```
/bball_hand
```

prints the current clip, and

```
/bball_hand pickup_object pickup_low 0.05 0.40
```

swaps it live while you're holding a ball — no restart. Start narrow and widen
until the ped starts leaning.

Set any entry to `false` to skip its animation. A dict that fails to load is skipped
rather than hung on, and an anim name that doesn't exist is abandoned after a few
attempts instead of re-tasking the ped every frame.

---

## How it works

**Score detection** (`client/scoring.lua`) treats each hoop as a horizontal circle.
Rather than asking "is the ball inside the rim right now" — which a fast shot would
tunnel straight past between frames — it takes the segment between the ball's
previous and current position and solves for where that segment crossed the rim
plane. Detection is therefore frame-rate independent. A shot also has to have been
above the rim *while outside* the cylinder to count, so you can't score by punching
one up through the net from underneath.

**Authority.** Ball physics run on the client that owns the ball, which is what
makes it feel responsive. The server owns everything that matters: who may hold a
ball (players and NPCs alike), which balls are loose, whether a reach-in came
off, and the score. Only the client that released a ball tracks it for scoring,
so exactly one client reports each basket, and the server still range-checks the
shooter against the hoop and rate-limits scoring per player.

**Hoops** live in `data/hoops.json`, written by the placement tool at runtime and
re-broadcast on every change.

---

## File map

```
shared/config.lua      all tuning
shared/util.lua        court grouping, hoop targeting, maths helpers
client/court.lua       courts from hoops, blips, ox_target zones, notify/hint helpers
client/physics.lua     the ball: flight, bounces, rim, net, bodies, water. No natives
client/ballsim.lua     runs the physics against the game's world and moves the entity
client/moves.lua       dribble timing from an animation, pace matching, catching. No natives
client/ball.lua        hold, dribble, charge meter, shot solve, pass, pickup, catch, steal
client/scoring.lua     rim-plane crossing detection
client/ai.lua          NPC players
client/freeballs.lua   practice balls lying on a court, to pick up
client/hud.lua         NUI bridge, floating "+2" over the rim, ball sounds
client/look.lua        prompts, help box, reticle messages, "N scored": vice_hud's pieces, or ox_lib's
client/aimcam.lua      the over-the-shoulder camera while aiming a rings shot
client/anim.lua        animation pack support: real clips, their timing, the dribble cycles and the stance
client/placement.lua   /bball_place tool and debug rendering
server/hoops.lua       hoops.json persistence, ace-gated add/remove
server/ball.lua        who is carrying, which balls are loose, steals, sound relay
server/match.lua       match state machine, teams, clock, possession, scoring authority
server/instance.lua    routing bucket per court
html/                  scoreboard, the rings, the hoop after "N scored" (img/), and sfx.js: the ball
                       sounds (recorded from html/sounds, else synthesised)
tests/                 offline checks, not loaded by the game
```
