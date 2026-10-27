fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'vice_hud'
description 'GTA6-style HUD for Qbox: status bars, minimap slot (zone + vehicle), turn-by-turn navigation, wanted stars, weapon/ammo, money, honor, skills, action prompts, an NUI interact menu, directional police glow and exhaustion effects. Requires ox_lib; qbx_core optional.'
version '2.2.0'

-- The GTA VI HUD set's release (the GitHub tag) this copy is, and where those
-- are published. server_update.lua compares them with GitHub's latest release
-- on start and says in the console when there is a newer one. Bump `release`
-- to the new tag whenever one is cut.
release '1.8.2'
repository 'https://github.com/Geckomacabre/GTA-VI-Inspired-HUD-for-FiveM'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'weapons.lua',
    -- Skill definitions and the level maths, loaded on BOTH sides. The client
    -- awards XP and the server persists it, and the two must not be able to
    -- disagree about what a level means.
    'skills.lua',

    -- Targeting (target/, merged from osm-target) and honor (honor/, merged
    -- from qbx_honor). Their settings go into the same Config table as the
    -- HUD's, so both config files load after config.lua above.
    'target/config.lua',
    'target/locales/locale.lua',
    'target/locales/*.lua',
    'target/shared/schema.lua',
    'target/shared/compat.lua',
    'target/shared/resolver.lua',
    'target/shared/designs.lua',
    'target/designs/**/design.lua',
    'honor/config.lua',
    'honor/alias.lua',
}

client_scripts {
    -- Split out of client.lua, and loaded BEFORE it so their published tables
    -- exist by the time anything can call them. Each .lua file is its own Lua
    -- chunk with its own 200-top-level-locals budget, which is the reason the
    -- split happened at all -- client.lua was at 192 of 200 and a few features
    -- from refusing to load, which takes the entire HUD down, not one feature.
    -- Neither file reaches back into client.lua: see their headers for the
    -- exact surface that crosses.
    -- First of all: the button resolver the two files below both draw on
    -- (which button a control is on, for the device in hand).
    'client_glyphs.lua',
    'client_vitals.lua',
    'client_overlays.lua',
    -- The wanted tells' fallback when fenix-police is not running: the
    -- police memory and the recent-shot clock (ported from the single-player
    -- GTA6Hud). Before client.lua because getWantedTells() there reads both.
    'client_awareness.lua',
    -- The game's own help messages in vice_hud's help box, and subtitles
    -- that follow the speech (ported from the single-player GTA6Hud). After
    -- client_overlays.lua: it uses that file's ShowHelpText/ShowSubtitle.
    'client_nativetext.lua',
    -- The drawn minimap's game side. Before client.lua for the same reason as
    -- the three above: client.lua's setRadar() asks it who is drawing the map.
    'client_map3d.lua',
    'client.lua',
    -- After client.lua only because the exhaustion model there reads
    -- SkillFitness() from here, and that is guarded so load order cannot
    -- actually break it. Nothing else is shared: client.lua's helpers are
    -- file-scoped locals and do not reach across.
    'client_skills.lua',
    -- Gym exercises that pay the Health skill. Needs ViceSkillAward from the
    -- file above, and quietly does nothing if that skills system is off.
    'client_training.lua',
    -- Popup styling. Self-contained: publishes a state bag that ox_lib reads,
    -- and shares nothing with the two files above.
    'theme.lua',

    -- Targeting: the osm-target engine, in its own load order.
    'target/client/framework/init.lua',
    'target/client/framework/esx.lua',
    'target/client/framework/ox.lua',
    'target/client/framework/qbcore.lua',
    'target/client/framework/qbox.lua',
    'target/client/framework/standalone.lua',
    'target/client/target/player.lua',
    'target/client/target/store.lua',
    'target/client/target/layers.lua',
    'target/client/api/native.lua',
    'target/client/api/qb.lua',
    'target/client/api/qtarget.lua',
    'target/client/ui/surfaces.lua',
    'target/client/target/discovery.lua',
    'target/client/target/hit.lua',
    'target/client/target/input.lua',
    'target/client/target/machine.lua',
    'target/client/target/proximity.lua',
    'target/client/target/defaults.lua',
    'target/client/ui/nui.lua',
    'target/client/config_sync.lua',
    'target/client/debug.lua',
    'target/client/main.lua',
    -- Honor: after targeting, whose greet / antagonise options it registers.
    'honor/client/main.lua',
    'honor/client/conduct.lua',
    'honor/client/debug.lua',
}

-- Owns the SERVER-WIDE layout: /hudpublish writes layout.json here and mirrors
-- it into GlobalState, so one admin fixing the HUD fixes it for everyone.
server_scripts {
    -- For targeting's saved settings (/targetadmin).
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
    'server_skills.lua',
    -- Gym stations for free weights (data/gym.json), edited from em_toolkit.
    'server_gym.lua',
    -- Server-wide popup theme (/themepublish). Independent of the layout above.
    'server_theme.lua',
    -- Tells the console when GitHub has a newer release of the HUD set.
    'server_update.lua',

    'target/server/framework/init.lua',
    'target/server/framework/esx.lua',
    'target/server/framework/ox.lua',
    'target/server/framework/qbcore.lua',
    'target/server/framework/qbox.lua',
    'target/server/framework/standalone.lua',
    'target/server/db.lua',
    'target/server/config_store.lua',
    'target/server/main.lua',
    'honor/server/main.lua',
    'honor/server/debug.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    -- GTA V's help-message labels, for client_nativetext.lua to identify a
    -- native help box by (LoadResourceFile, so it has to be a client file).
    'data/help_labels.txt',
    -- The drawn minimap (Config.Map3D), and the world it draws. The world
    -- ships with the resource (tools/map3d/build.py and blips.py rebuild it).
    -- If it is ever missing these three lines match nothing, the page says so,
    -- and the engine's radar carries on.
    'html/map3d.js',
    'html/map3d/*.bin',
    'html/map3d/*.png',
    'html/map3d/*.json',
    -- Bone-connected world prompts rendered with real 3D depth (see
    -- client_dui_worldpanel.lua's own header) -- a SEPARATE DUI browser
    -- pointed at this page, not part of the main index.html NUI frame.
    -- Not listed as a client_script: client_dui_worldpanel.lua required
    -- on demand from client_overlays.lua, same as ox_target's client/
    -- api.lua etc. are listed in files{} rather than client_scripts{}.
    'html/dui_worldpanel.html',
    'client_dui_worldpanel.lua',
    -- Generated by tools/make_makes.py from what is in html/logos/. app.js
    -- reads it to pick the vehicle panel's manufacturer badge, so the table and
    -- the marks have to ship together or the panel asks for files that are not
    -- there.
    'html/makes.js',
    -- Rockstar's manufacturer marks: flattened to greyscale by
    -- tools/fetch_logos.py, then evened out to one size and one shared 160px
    -- square canvas by tools/normalize_logos.py (which is what lets style.css
    -- size all fifty-one with a single rule). ~425kB the whole set, which
    -- every player downloads once and then has cached.
    'html/logos/*.png',
    -- BOTH extensions. The Art Deco cuts are TrueType and an otf-only glob
    -- silently does not ship them: the page then falls back to Helvetica and
    -- the font simply "is not in the list" for every player but the one who
    -- dropped the file in.
    'html/fonts/*.otf',
    'html/fonts/*.ttf',
    -- The map badge's source art (#map-badge, a plain <img>). PNG rather than
    -- webp -- webp was the first thing tried and did not render in the
    -- game's own NUI browser. Also covers the status-bar badges (heart/
    -- stamina/eye) and the BuckMe badge -- all from the same reference pack,
    -- see README credit.
    'html/icons/*.png',
    -- The BuckMe ring's 33-frame mask sequence (onCash() in app.js swaps
    -- which frame is the mask) -- a subfolder, so it needs its own glob;
    -- the one above does not recurse.
    'html/icons/buckme_ring/*.png',
    -- weapon/person/people/vehicle tells (TELL_IMG in app.js), cropped
    -- straight out of the reference screenshots -- another subfolder, same
    -- non-recursing caveat as above.
    'html/icons/tells/*.png',
    -- GTA VI police lights: the trailer's 90 light-row pictures and the
    -- arrow's 64 points, each packed into one sheet (app.js polVi).
    'html/icons/police/*.png',
    -- Targeting's own page: the admin panel and preferences (a frame inside
    -- html/index.html) and the in-world DUI surfaces.
    'target/html/index.html',
    'target/html/assets/*.js',
    'target/html/assets/*.css',
    'target/designs/**/design.js',
    'target/locales/*.lua',
}

-- The radar masks in stream/ are picked up AUTOMATICALLY — FiveM streams
-- anything in a stream/ directory, and takes each texture DICTIONARY name from
-- the filename. They must NOT also be listed in files{} above: declaring one in
-- both places registers the asset twice, which is what produced the "access to
-- <asset> is locked" crash. Do not add them.
--
--   vice_mask_00 .. vice_mask_50   one per corner-radius step, swapped live by
--                                  the Corner radius row in /movehud
--   vice_minimap                   the original single mask, kept as the
--                                  fallback if a step fails to stream
--
-- Regenerate the family with `python tools/make_masks.py`, then check it with
-- `node tools/radius.test.js`. tools/ is not in files{} either — it is build
-- and test tooling, and clients have no use for it.

-- Only this resource's own pages may call its NUI callbacks. Targeting's admin
-- callbacks came with this switched on; it now covers the HUD's as well.
nui_callback_strict_mode 'true'

-- vice_hud IS these resources now, and they must not also be installed.
-- `provide` is what satisfies another manifest's `dependency 'ox_target'`.
-- It does NOT alias exports or GetResourceState: exports under the old names
-- are answered by handlers the code registers itself (ExportAs in
-- target/client/api/native.lua, HonorExport in honor/alias.lua), and a script
-- that tests GetResourceState('ox_target') needs changing or a resource of
-- that name -- see the README.
provide 'osm-target'
provide 'ox_target'
provide 'qb-target'
provide 'qtarget'
provide 'qbx_honor'

dependencies {
    'ox_lib',
    'oxmysql',
}
