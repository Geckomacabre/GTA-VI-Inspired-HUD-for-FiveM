-- Static configuration for osm-target.
-- Visual appearance settings are managed via the in-game admin panel (/targetadmin).

-- Merged into vice_hud: this file is loaded after vice_hud/config.lua and
-- adds the targeting settings to the same Config table. Nothing here shares
-- a name with a HUD setting (the debug switch is Config.TargetDebug for that
-- reason).
Config = Config or {}

Config.Locale = 'en'

-- Framework selection: 'auto' | 'qbox' | 'qbcore' | 'esx' | 'ox' | 'standalone'
Config.Framework = 'auto'

-- Diagnostic overlay: toggle in-world debug visuals and resolver logs.
Config.TargetDebug = false

-- Version check: check GitHub for newer release notices on startup.
-- Off in the merged resource: the check compares the manifest version with
-- osm-target's own GitHub releases, and the manifest is vice_hud's now.
Config.VersionCheck = false

-- Admin permission: ACE permission required for admin panel access.
Config.AcePermission = 'osm_target.admin'

Config.Commands = {
  admin = 'targetadmin',   -- Open server-wide appearance and system configuration panel
  prefs = 'targetui',      -- Open player accessibility preferences
  debug = 'targetdebug',   -- Toggle in-world diagnostics overlay
  test = 'targettest',     -- Spawn test ped with sample options

  -- Diagnostic commands: only answer while diagnostics are enabled (/targetdebug)
  explain = 'targetexplain', -- Print resolver verdicts for the entity under the crosshair
  bench = 'targetbench',     -- Benchmark world anchor calculation paths
}

Config.Input = {
  -- Keybinding: default activation key for ox_lib keybind
  key = 'LMENU',

  -- Controller binding for the same action, as a PAD_DIGITALBUTTONANY input
  -- parameter id. nil leaves targeting keyboard-only.
  --
  -- The ids are NOT the names they look like. The full valid set, from
  -- docs.fivem.net/docs/game-references/input-mapper-parameter-ids/
  -- pad_digitalbuttonany/ :
  --
  --   L1_INDEX     R1_INDEX      shoulder buttons
  --   L2_INDEX     R2_INDEX      triggers (pressed at half travel)
  --   L3_INDEX     R3_INDEX      stick presses
  --   LUP_INDEX    LDOWN_INDEX   d-pad up / down
  --   LLEFT_INDEX  LRIGHT_INDEX  d-pad left / right
  --   RUP_INDEX    Y / Triangle      RDOWN_INDEX   A / Cross
  --   RLEFT_INDEX  X / Square        RRIGHT_INDEX  B / Circle
  --   SELECT_INDEX START_INDEX   TOUCH_INDEX
  --
  -- An id outside that set does not fail: the mapper is DIGITALBUTTON*ANY*, so
  -- with nothing specific to bind, every button on the pad triggers the action.
  -- Input.register checks the name for that reason.
  --
  -- A shoulder button, not a trigger and not the d-pad, because on a pad both
  -- of those are already carrying the game: the triggers are accelerate and
  -- aim, and the d-pad is the radio while driving. Avoid LUP_INDEX/LDOWN_INDEX
  -- for the same reason the confirm list avoids the triggers -- up and down
  -- already move the focus through the list.
  --
  -- Both this and the keyboard key are rebindable by the player in FiveM's
  -- keybind settings, and like the keyboard key, a change here only takes
  -- effect next session: ox_lib registers the bind once, at start.
  padKey = 'L1_INDEX',  -- LB / L1

  -- Interaction mode: 'hold' or 'toggle'
  mode = 'hold',

  -- Split per device, not merged into one list, because a single GTA control id
  -- is a DIFFERENT physical button depending on what the player is holding.
  -- INPUT_ATTACK is a left click on a mouse and the right trigger on a pad --
  -- which is also accelerate, so reading it on a pad confirmed an option every
  -- time the player touched the throttle. INPUT_AIM is the left trigger, with
  -- the same problem on foot. Neither is read on a pad any more.
  --
  -- Each entry may still be a plain id or a list, which is read on any device.
  confirm = {
    kbm = { 24 },        -- Left click (INPUT_ATTACK)
    pad = { 201 },       -- A / Cross (INPUT_FRONTEND_ACCEPT)
  },
  cancel = {
    kbm = { 25, 194 },   -- Right click (INPUT_AIM), Backspace (INPUT_FRONTEND_CANCEL)
    pad = { 194 },       -- B / Circle
  },
  -- The pad's up and down are the d-pad and the left stick. Rockstar's own
  -- menus treat these and the wheel as one intent (clothes_shop pairs 188/187,
  -- the car meet groups 241 with 188), so they are the same action here too --
  -- just never read on the wrong device. Note the d-pad changes radio station
  -- while driving; the game does that, not this, and it is why activation sits
  -- on a shoulder button.
  scrollUp = {
    kbm = { 241 },       -- Wheel up (INPUT_CURSOR_SCROLL_UP)
    pad = { 188 },       -- D-pad / stick up (INPUT_FRONTEND_UP)
  },
  scrollDown = {
    kbm = { 242 },       -- Wheel down
    pad = { 187 },       -- D-pad / stick down (INPUT_FRONTEND_DOWN)
  },

  -- Part toggle. When the crosshair is within reach of more than one part of
  -- the same entity -- a car's driver door and its front tire sit well inside
  -- the 2m bone tolerance of each other -- the menu shows only the part nearest
  -- the crosshair (see Config.Parts) and this steps it to the next one.
  --
  -- Middle mouse because the wheel already walks the rows, and the obvious
  -- keys are taken on this server: TAB opens ox_inventory (inventory:keys), Q
  -- is vi_radio's wheel and parkour, Z is ox_lib's radial, E/G are the
  -- direct-prompt keys below. D-pad right on a pad, next to the up/down that
  -- already walk the rows.
  cyclePart = {
    kbm = { 348 },       -- Middle mouse (INPUT_MAP_POI)
    pad = { 190 },       -- D-pad right (INPUT_FRONTEND_RIGHT)
  },

  -- Direct multi-key prompt (1-2 option entities, e.g. a car door offering
  -- "Slim Jim" / "Smash Window"): each option in view gets its own entry from
  -- this pool, by position, so every option is its own independently and
  -- simultaneously pressable key instead of sharing one focus+confirm cursor.
  --
  -- Pad entries were left out for a long time because the only two
  -- *frontend-safe* pad buttons -- ones that do not already double as
  -- something else while free-aiming or driving -- looked like exactly the
  -- two INPUT_FRONTEND_ACCEPT/CANCEL already spent on confirm/cancel above.
  -- That undersold what "frontend-safe" actually rules out, though: GTA's
  -- control list (docs.fivem.net/docs/game-references/controls/) has TWO
  -- more buttons in the same INPUT_FRONTEND_* family as accept/cancel --
  --
  --   203  INPUT_FRONTEND_X   -- X (Xbox) / Square (PlayStation)
  --   204  INPUT_FRONTEND_Y   -- Y (Xbox) / Triangle (PlayStation)
  --
  -- -- neither used anywhere else in this table (confirm/cancel/scrollUp/
  -- scrollDown/padKey above, or suppress below), so they're free the same
  -- way 201/202 (accept/cancel) already were.
  --
  -- "Free" only covers the id itself, not the physical button behind it --
  -- exactly the INPUT_ATTACK/INPUT_AIM lesson from the confirm/cancel
  -- comment above. Physical X also carries INPUT_JUMP (22) on foot; physical
  -- Y also carries INPUT_ENTER (23, get in the nearest vehicle) and
  -- INPUT_VEH_EXIT (75, get out of one), plus INPUT_WEAPON_SPECIAL (53) and
  -- INPUT_DROP_WEAPON (56). INPUT_ENTER in particular would have bitten
  -- immediately: the flagship use of this very prompt is a car door, so a
  -- pad player pressing "Smash Window" would have also tried to get in the
  -- car normally. All five are now in Input.suppress below, closed off the
  -- same way INPUT_FRONTEND_ACCEPT (201) already is for confirm -- suppressed
  -- controls still reach Input.directKeyPressed via IsDisabledControlJustPressed,
  -- they just stop reaching the game underneath it.
  --
  -- L3/R3 (INPUT_FRONTEND_LS 209 / INPUT_FRONTEND_RS 210 -- also unused
  -- elsewhere) were the other candidate: their real-world collisions
  -- (INPUT_DUCK 36, INPUT_LOOK_BEHIND 26, INPUT_SPECIAL_ABILITY 28/29,
  -- INPUT_ACCURATE_AIM 50) are individually milder than jump/enter-vehicle
  -- and just as closeable via suppress. X/Y won out for a reason outside the
  -- input system entirely: this change is also what first draws real button
  -- art for a pad player instead of bare text (see BUTTON_ICONS in
  -- ui/src/designs/rail/index.tsx), and the art supplied for it only covers
  -- face buttons (Xbox X/Y/A/B, PlayStation Square/Triangle/Circle/Cross) --
  -- nothing for a stick click. Picking L3/R3 would have meant the exact
  -- players this change is for still seeing a generic fallback mark instead
  -- of a real button. That gap (no stick-click art yet) is real and worth
  -- closing later if a future change wants L3/R3 for something else, but it
  -- isn't a reason to leave pad off the direct prompt entirely when a
  -- fully-covered pair of buttons was available right now.
  --
  -- Positional pool, kept as the fallback for any 'direct' pair that has not
  -- opted into a fixed identity below (osm:test:car's debug dummy, or any
  -- future 1-2 option case nobody has named yet).
  directOptionKeys = {
    { kbm = { 51 }, pad = { 203 } },  -- E (INPUT_CONTEXT) / X, Square (INPUT_FRONTEND_X)
    { kbm = { 47 }, pad = { 204 } },  -- G (INPUT_DETONATE) / Y, Triangle (INPUT_FRONTEND_Y)
  },

  -- ADDED 2026-09-13: fixed per-option identity, looked up by the option's own
  -- `name` before directOptionKeys' pool position is even considered (see
  -- Input.directKeyLabel/directKeyPressed). The pool above answers "whichever
  -- option ended up first/second in the resolved list gets this key" -- fine
  -- until two callers register options whose ORDER isn't guaranteed (one
  -- resource's canInteract can hide/show independently of the other's), or
  -- until a specific action needs a specific real-world button regardless of
  -- position. Slim Jim / Smash Window is exactly that: the GTA VI trailer this
  -- whole target system is modeled on shows Triangle for Slim Jim and Circle
  -- for Smash Window specifically, on PlayStation (Y / B on Xbox) -- not
  -- "whichever is first."
  --
  -- Keyboard keeps the E binding already verified live in-game for Slim Jim
  -- (Config.Input.directOptionKeys' old pool position 1) rather than
  -- reshuffling something already confirmed working; only the pad side is a
  -- real fix here, since the trailer reference is pad-specific to begin with.
  --
  -- Smash Window's pad button (194) is the SAME control id as Config.Input.
  -- cancel.pad (B/Circle already means "back out of the menu" everywhere
  -- else) -- deliberately not suppressed globally, since cancel has to keep
  -- working for every OTHER menu. client/target/machine.lua's MENU_OPEN loop
  -- skips the ordinary Input.cancelPressed() check specifically while
  -- menuMode == 'direct' instead, so Circle only ever means Smash Window on
  -- this one prompt -- backing out of it is done by aiming away from the car,
  -- same as the trailer has no separate "back" affordance on this prompt.
  directKeyByName = {
    ['qbx_vehiclekeys:slimjim']     = { kbm = { 51 }, pad = { 204 } }, -- E / Y, Triangle
    ['qbx_vehiclekeys:smashwindow'] = { kbm = { 47 }, pad = { 194 } }, -- G / B, Circle (== cancel.pad)
  },

  -- Control suppression: disable weapon and vehicle cycling during interaction.
  -- Suppressing a control does not stop this resource reading it -- the input
  -- layer checks IsDisabledControlJustPressed too -- so the ids used above can
  -- safely appear here, and the pad ones need to: the d-pad and A are bound to
  -- game actions of their own that should not fire while a menu is up. Same
  -- reasoning for X and Y now that directOptionKeys uses them -- see the
  -- comment on that table for exactly which real actions 22/23/53/56/75
  -- share a physical button with.
  suppress = {
    14, 15,          -- Weapon wheel next / prev
    16, 17,          -- Select next / prev weapon
    22,              -- Jump (physical X, shared with direct-prompt option 1)
    23,              -- Enter vehicle (physical Y, shared with direct-prompt option 2)
    24, 25,          -- Attack / aim
    27,              -- Phone (physical middle mouse / d-pad up, shared with cyclePart and scrollUp)
    53,              -- Weapon special ability (physical Y)
    56,              -- Drop weapon (physical Y)
    74,              -- Vehicle headlight (physical d-pad right, shared with cyclePart)
    75,              -- Exit vehicle (physical Y)
    81, 82, 83, 84,  -- Vehicle radio and weapon cycling
    99, 100,         -- Vehicle select next / prev weapon
    115, 116,        -- Vehicle cycle weapon
    140, 141, 142,   -- Melee attacks
    187, 188,        -- Frontend up / down (d-pad, left stick)
    201,             -- Frontend accept (A / Cross)
    203, 204,        -- Frontend X / Y (X-Square, Y-Triangle -- direct prompt options)
    257, 263, 264,   -- Alternate attack controls
    331,             -- Vehicle radio wheel
  },
}

Config.Interaction = {
  -- Max distance: interaction range limit in meters
  distance = 7.0,

  -- Raycast length: camera raycast range in meters
  raycastDistance = 12.0,

  -- See-through targeting. When the crosshair ray stops on world geometry, run
  -- a second entity-only pass that travels through glass, railings and fences,
  -- and take that hit if the player has genuine line of sight to it. Lets a
  -- player target a shopkeeper through a shop window or an ATM behind a
  -- grille, without ever reaching through a solid wall.
  --
  -- The extra pass only runs on the frames the first one found no entity, so
  -- looking at anything targetable costs exactly what it did before.
  seeThrough = true,

  -- Scan rate: raycast interval in milliseconds while sweeping
  scanInterval = 50,

  -- Hysteresis thresholds: angular limits and hold duration for target lock stability
  snapAngle = 4.0,      -- Degrees: angle threshold to acquire target
  releaseAngle = 6.0,   -- Degrees: angle threshold to initiate release
  releaseTime = 180,    -- Milliseconds: duration beyond release angle before menu closes

  -- Animation timings: open and close transition durations in milliseconds
  openTime = 220,
  closeTime = 160,
}

-- Entity parts: split one entity's options by the physical part they are
-- anchored to, so looking at a car window does not also list the tire beside
-- it. Only the part nearest the crosshair is shown, the menu follows the
-- crosshair from part to part on the same entity, and Config.Input.cyclePart
-- steps to the next part by hand. Options with no bone or offset show on every
-- part.
Config.Parts = {
  enabled = true,

  -- Metres another part must be nearer the crosshair than the one showing
  -- before the menu moves to it, so a point between two parts does not flicker
  hysteresis = 0.25,

  -- Milliseconds between re-reading the crosshair while a menu is open
  followInterval = 150,

  -- Metres (entity-local) the crosshair must move from where the part toggle
  -- was pressed before the menu goes back to following the crosshair
  unpinDistance = 1.0,

  -- Bones that are one part. Resources anchor to different bones on the same
  -- door -- osm-target's own door option uses door_dside_f/seat_dside_f,
  -- qbx_vehiclekeys' Smash Window door_dside_f/window_lf -- and without these
  -- that one door would split into separate parts. Unlisted bones are a part each.
  aliases = {
    door_dside_f = 'dside_f', seat_dside_f = 'dside_f', window_lf = 'dside_f', handle_dside_f = 'dside_f',
    door_pside_f = 'pside_f', seat_pside_f = 'pside_f', window_rf = 'pside_f', handle_pside_f = 'pside_f',
    door_dside_r = 'dside_r', seat_dside_r = 'dside_r', window_lr = 'dside_r', handle_dside_r = 'dside_r',
    door_pside_r = 'pside_r', seat_pside_r = 'pside_r', window_rr = 'pside_r', handle_pside_r = 'pside_r',
  },
}

Config.Indicators = {
  -- World markers: enable floating indicator markers on interactive points
  enabled = true,

  radius = 5.0,          -- Maximum indicator visibility radius in meters
  cap = 8,               -- Maximum visible indicators per frame
  discoveryInterval = 250, -- Interval in milliseconds between discovery passes

  -- Pool caching: scan nearby entity pools with distance padding
  scanInterval = 1000,
  scanSlack = 6.0,

  -- Near state threshold: angle to transition indicator to near-focused state
  nearAngle = 12.0,

  -- Global inclusion: whether global ped/vehicle/object options generate indicators
  includeGlobals = false,
}

Config.Render = {
  -- Sprite heights: fraction of screen height at reference distance
  menuSize = 0.40,
  indicatorSize = 0.042,
  cursorSize = 0.030,

  -- Distance scaling: non-linear scaling bounds for world-space sprites
  referenceDistance = 2.5,
  scaleExponent = 0.5,
  scaleMin = 0.75,
  scaleMax = 1.15,

  -- DUI texture resolution: dimensions for runtime textures
  menuResolution = 1024,
  indicatorResolution = 256,
  cursorResolution = 128,

  -- Vertical anchor offset: vertical adjustment in meters for menu placement
  anchorLift = 0.0,
}

Config.Options = {
  -- Disabled states: render ineligible options with requirement explanation
  showDisabled = true,

  -- Opaque gates: hide options that return false without an explanatory reason
  hideUnexplained = true,

  -- Default distance: fallback range in meters for options without distance
  defaultDistance = 7.0,

  -- Focus disabled: allow navigating to disabled options to inspect requirements
  focusDisabled = true,
}

-- Default vehicle interactions: register built-in vehicle door options (ox_target parity)
-- Matches ox_target's `setr ox_target:defaults 1`. Off, a plain car shows only
-- whatever third-party resources registered on it, which on most vehicles is
-- nothing at all. On, every vehicle carries four doors, the bonnet and the
-- trunk, each anchored to its own bone so it appears only when you look at it.
Config.Defaults = {
  vehicleDoors = true,
}

-- Default design: initial design fallback used before database sync or if selected pack is missing
Config.Design = 'rail'
