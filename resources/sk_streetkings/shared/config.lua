-- Merged configuration for sk_streetkings.
--
-- Carries over shared/config.lua from sk_racing and shared/config.lua from
-- meet_night verbatim, and adds a Modules toggle block for the StreetKings
-- systems ported in. Location data (car meet layout, repair stations, stunt
-- jumps, speed cameras, hangout zones) lives under data/ instead.

Config = {
    MoneyAccount = 'cash',

    -- ── Module toggles ──────────────────────────────────────────────────────
    -- Every ported StreetKings system can be switched off independently. The
    -- ones defaulted to false conflict with a resource this server already
    -- runs; read the note before enabling.
    Modules = {
        carmeet       = true,
        racing        = true,
        meetNight     = true,
        drift         = true,
        npcBetting    = true,

        nitrous       = true,
        gearbox       = true,
        stunts        = true,
        rampage       = true,
        npcChallenge  = true,
        -- A rival texts you a meet-up spot through lb-phone instead of
        -- waiting for a burnout next to the right ambient car. Reuses
        -- npcChallenge's own race engine (SKNpcRace, exposed in
        -- modules/npcchallenge/npcchallenge_c.lua) rather than a second one,
        -- so turning npcChallenge off takes this with it - see the guard at
        -- the top of modules/npcinvite/npcinvite_c.lua.
        npcInvite     = true,
        -- Lets any SKNpcRace (ambient burnout trigger OR an npcInvite rival)
        -- escalate into a 2-4 car pack instead of stopping at 1v1. Off just
        -- means every challenge stays 1v1, same as before this existed.
        streetPack    = true,
        -- Spontaneous multiplayer races: the server opens a short-lived,
        -- unhosted lobby on a random unlocked route and invites nearby
        -- players to join before it auto-starts. See modules/popuprace/.
        popupRace     = true,
        -- Build a race car from scrap, or buy a cheap wreck and restore it in
        -- stages. Deliberately self-contained (own economy hooks against
        -- ox_inventory + qbx_vehicles) rather than reaching into
        -- um_mechanicjob's per-part condition table, which is server-local,
        -- never actually persisted (its own save event is dead code), and
        -- exposes its condition reads only client-side — not something
        -- worth building a new resource's economy on top of. See
        -- modules/carbuild/ and Config.CarBuild.
        carBuild      = true,
        hangoutZones  = true,
        repairPoints  = true,
        stats         = true,
        nametags      = true,
        clothingStore = true,

        speedCameras  = true,

        -- Spawns pursuit AI and runs its own wanted-heat loop. Overlaps the
        -- police RP stack already on this server (ps-dispatch, fenix-police,
        -- lvc, wk_wars2x) — cops get spawned that dispatch knows nothing about.
        -- Left off so it is a deliberate choice, not a surprise.
        police        = false,
    },

    -- ── Blips ───────────────────────────────────────────────────────────────
    -- Every blip this resource puts on the map, in one place. Created through
    -- SK.CreateBlip() (modules/core/helpers_c.lua).
    --
    -- `shortRange = true` is what keeps the minimap readable: the blip always
    -- shows on the big pause map, but only appears on the minimap once you are
    -- close to it, instead of pinning itself to the minimap edge from across
    -- the city. Leave it false only for something the player is actively
    -- driving to right now.
    --
    -- `category` groups the blip under a heading in the pause-map legend;
    -- `categoryLabel` is that heading's text.
    Blips = {
        -- Sprite IDs below are vanilla GTA blips, chosen by name from
        -- docs.fivem.net/docs/game-references/blips. Upstream's own IDs (827,
        -- 500, 378) needed its custom blip sheet to make sense; on the stock
        -- sheet 500 is `radar_production_money` and 378 is
        -- `radar_team_deathmatch`, neither of which reads as what it labels.
        speedCamera = {
            sprite = 184, -- radar_camera
            colour = 3, scale = 0.9, shortRange = true,
            category = 22, categoryLabel = 'Speed Cameras',
            -- Upstream leaves the blip itself unnamed and lets the category
            -- caption do the work.
            label = '',
        },
        stuntJump = {
            sprite = 488, -- radar_stunt
            colour = 46, scale = 0.9, shortRange = true,
            category = 16, categoryLabel = 'Stunt Jumps',
        },
        rampage = {
            sprite = 84, -- radar_rampage
            colour = 1, scale = 0.9, shortRange = true,
            category = 17, categoryLabel = 'Rampage',
        },
        repairStation = {
            sprite = 402, colour = 2, scale = 0.8, shortRange = true,
            label = 'Repair Station',
        },
        policeTrap = {
            sprite = 56, colour = 3, scale = 1.0, shortRange = true,
            label = 'Trap Cop',
        },
        -- The live NPC challenge finish line and the rival car. Both are the
        -- current objective, so both stay long range on purpose.
        challengeDestination = {
            sprite = 38, colour = 66, scale = 1.0, shortRange = false,
        },
        challengeRival = {
            sprite = 225, colour = 47, scale = 1.0, shortRange = false,
        },
    },

    -- ── Validation (server-authoritative) ──────────────────────────────────
    StartRadius        = 15.0,  -- how close to the start line before a run can begin
    CheckpointRadius   = 30.0,  -- server-side accept radius for a checkpoint hit
    ClientPickupRadius = 20.0,  -- client fires the hit event within this radius (grace zone below CheckpointRadius)
    FinishRadius       = 30.0,
    RunTimeoutMs       = 20 * 60 * 1000, -- 20 minutes, abandons a stale singleplayer run

    -- ── Multiplayer lobby ───────────────────────────────────────────────────
    MinMultiplayerPlayers     = 2,
    LobbyCountdownSec         = 10,
    LobbyWaitTimeoutSec       = 180,
    StandingsBroadcastMs      = 1000,
    MultiplayerFinishGraceSec = 60, -- how long stragglers get after the first finisher
    ForfeitCost               = 1000,
    RoutingBucketBase         = 20000, -- lobby buckets start here to stay clear of the default (0) world bucket
    LapsMin = 1,
    LapsMax = 5,

    -- ── Solo time-trial reward scaling ──────────────────────────────────────
    -- Base reward is scaled down for short races and up for long ones, then
    -- stacked with a goal-time bonus and a percentile-based ranked band.
    RewardScaling = {
        checkpointWeightMeters = 140.0, -- artificial per-checkpoint distance weight
        minimumScale           = 0.40,
        referenceDistance      = 1600.0, -- distance (in weighted meters) that maps to scale 1.0
        base       = { cash = 1500, xp = 20 },
        goalBonus  = { cash = 300,  xp = 5 },  -- awarded if the player beats def.goalTime
        earlyBoardBonus         = { cash = 250, xp = 4 }, -- first personal best that also lands top N
        earlyBoardRankThreshold = 50,
        rankedBands = {
            { maxPercentile = 0.05, label = 'Top 5%',  cash = 900, xp = 10 },
            { maxPercentile = 0.10, label = 'Top 10%', cash = 650, xp = 7  },
            { maxPercentile = 0.25, label = 'Top 25%', cash = 400, xp = 5  },
            { maxPercentile = 0.50, label = 'Top 50%', cash = 180, xp = 3  },
            { maxPercentile = 1.00, label = 'Finish',  cash = 60,  xp = 1  },
        },
    },

    -- ── Air / offroad races (data/rockstar_races.lua, /racemaker) ────────────
    -- Medal payout on top of the normal time-trial reward. Only routes that
    -- define `medals` (the stunt-plane courses, or a custom route given gold/
    -- silver/bronze times) pay it. Scaled by the route's reward scale like
    -- every other payout.
    MedalRewards = {
        gold   = { cash = 1200, xp = 14 },
        silver = { cash = 700,  xp = 8 },
        bronze = { cash = 350,  xp = 4 },
    },

    -- The vehicles a race may hand out. The server refuses any other model, so a
    -- route saved from /racemaker cannot make it spawn something arbitrary.
    -- netType is the entity type CreateVehicleServerSetter needs.
    RaceVehicles = {
        stunt   = { netType = 'plane',      label = 'Stunt Plane', kind = 'air' },
        duster  = { netType = 'plane',      label = 'Duster',      kind = 'air' },
        mallard = { netType = 'plane',      label = 'Mallard',     kind = 'air' },
        sanchez = { netType = 'bike',       label = 'Sanchez',     kind = 'offroad' },
        manchez = { netType = 'bike',       label = 'Manchez',     kind = 'offroad' },
        mesa    = { netType = 'automobile', label = 'Mesa',        kind = 'offroad' },
        bifta   = { netType = 'automobile', label = 'Bifta',       kind = 'offroad' },
        kalahari = { netType = 'automobile', label = 'Kalahari',   kind = 'offroad' },
    },
    -- How close (metres, horizontally) you must stand to a race's entry point
    -- (or start, for a race with no separate entry) to be handed its vehicle.
    RaceVehicleEntryRadius = 40.0,

    -- Checkpoint diameters passed to CreateCheckpoint, Rockstar's own numbers
    -- (SPTT_GATE_CHKPNT_SCL 16, ORR_GATE_CHKPNT_SCL 10.25). How big these look
    -- in game was not checked; change them here if a ring looks wrong.
    CheckpointSize = { road = 8.0, offroad = 10.25, air = 16.0 },

    -- Race checkpoint blips on the minimap. With vice_hud running, the blips take the character's
    -- HUD accent exactly (pink / teal, the same colour as the race plate's bar and the waypoint
    -- route). The GPS line to the next checkpoint takes the nearest stock blip colour instead,
    -- because an exact RGBA colour is documented for a blip but not for its route: 8 is Pink
    -- (#fe7ac3) for the pink accent, 30 Dark Cyan (#29a5b8) for teal, 5 the old yellow otherwise.
    -- Set exactRoute = true to try the exact accent on the line too, and check it draws.
    RaceBlips = {
        routeColour = { pink = 8, teal = 30 },
        defaultRouteColour = 5,
        exactRoute = false,
    },

    -- ── Multiplayer reward scaling ──────────────────────────────────────────
    MultiplayerRewardScaling = {
        positionMultipliers      = { 1.00, 0.80, 0.65, 0.55, 0.48, 0.42, 0.38, 0.34, 0.30, 0.28 },
        lastPlaceFloor           = 0.22,
        playerCountBonusPerExtra = 0.08,
        playerCountBonusCap      = 1.00,
        forfeitMultiplier        = 0.0,
    },

    -- ── Leaderboard ─────────────────────────────────────────────────────────
    LeaderboardLimit = 10,

    -- ── Pop-up races (modules/popuprace/) ────────────────────────────────────
    -- A server-picked, unhosted multiplayer lobby: opens on a random unlocked
    -- route, invites nearby players via notify + blip for a short join window,
    -- then auto-starts through the exact same lobby/checkpoint/payout code
    -- modules/racing/multiplayer_s.lua already uses for host-created lobbies.
    PopupRace = {
        intervalMsMin = 10 * 60000,
        intervalMsMax = 20 * 60000,
        joinWindowSec = 75,
        -- Starts with as few as 1 joiner rather than Config.MinMultiplayerPlayers -
        -- a pop-up that needed a full lobby to fire would rarely fire at all.
        minPlayers    = 1,
        -- Only players within this of the route's start line are notified.
        announceRadiusMeters = 1200.0,
        arriveRadiusMeters   = 20.0,

        announceMessage = 'A street race just lit up nearby — %s. Get to the start within %ds to join!',
        startedMessage  = 'Pop-up race under way: %s',
        joinedMessage   = 'You\'re in — %s, waiting for the start.',
    },

    -- ── Meet Night (was the meet_night resource) ────────────────────────────
    -- os.date('*t').wday: 1=Sunday, 2=Monday ... 7=Saturday
    MeetNight = {
        DayOfWeek  = 6,  -- Friday
        StartHour  = 20, -- 24h server time
        EndHour    = 22,
        Multiplier = 1.5, -- race cash/xp multiplier while active

        PollIntervalMs = 30000,

        AnnounceStart = "^3Meet Night^7 is ON at the car meet — race payouts are boosted ^2%.1fx^7 until %02d:00!",
        AnnounceEnd   = "^3Meet Night^7 has ended. Race payouts are back to normal — see you next Friday.",
    },

    -- ── Betting (NPC spectator races) ───────────────────────────────────────
    Betting = {
        min = 100,
        max = 50000,
    },

    -- ── Drift scoring ───────────────────────────────────────────────────────
    -- Active whenever the player is inside the car meet zone in a vehicle.
    -- minSpeed in m/s (~29 km/h at 8.0). minAngle in degrees.
    -- Only the highest threshold hit in a session pays out.
    Drift = {
        minSpeed = 8.0,
        minAngle = 15.0,
        rewards = {
            { points = 2000,  cash = 500 },
            { points = 8000,  cash = 1500 },
            { points = 20000, cash = 4000 },
        },
    },

    -- ── Nitrous (ported from streetkings modules/nitrous) ───────────────────
    Nitrous = {
        -- Upstream read the tier per-vehicle from StreetKings' own tuning shop
        -- (streetkings:shop:getActiveVehicleNitrous). That shop is not ported —
        -- um_customs owns vehicle mods here — so "which vehicles
        -- have nitrous" is decided by the two settings below instead.

        -- Nitrous is bought per vehicle from the Performance menu in
        -- um_customs and stored against the plate in `sk_vehicle_upgrades`.
        -- Raised from upstream's 3,500 / 6,500 / 8,500 on 2026-10-10 so nitrous sits above a
        -- turbo ($15,000) in the mod shop's price list.
        prices = {
            street = 10000,
            sport  = 17500,
            race   = 25000,
        },

        -- Only vehicles registered in `player_vehicles` can be upgraded, so a
        -- player cannot spend money fitting nitrous to a stolen or temporary
        -- car that will never persist. Matches how um_customs saves mods.
        requireOwnedVehicle = true,

        -- Tier every vehicle gets for free, before any purchase. nil means
        -- nitrous must be bought — which is the point of the shop. Set it to
        -- 'street' to hand everyone a bottle again.
        defaultTier = nil,
        tiers = {
            street = { capacity = 3.0, torque = 1.25, label = 'Street NOS' },
            sport  = { capacity = 4.0, torque = 1.35, label = 'Sport NOS'  },
            race   = { capacity = 5.0, torque = 1.45, label = 'Race NOS'   },
        },
        checkpointRefill    = 0.75,
        nearMissRefill      = 0.45,
        driftRefillPerSec   = 0.35,
        oncomingRefillPerSec = 0.22,
    },

    -- ── Gearbox (ported from streetkings modules/gearbox) ───────────────────
    Gearbox = {
        -- 'off' | 'beginner' | 'expert'. Players can change this themselves via
        -- /gearbox; this is only the default for a fresh profile.
        defaultMode = 'off',
    },

    -- ── Stunt jumps ─────────────────────────────────────────────────────────
    Stunts = {
        rewardPerJump      = 750,
        firstCompletionXp  = 10,
        repeatRewardCash   = 150,
    },

    -- ── Rampage ─────────────────────────────────────────────────────────────
    -- durationSec is the fallback for entries in data/rampages.lua that do not
    -- set their own `duration` (the shipped locations all use 150).
    --
    -- WATCH cashPerPoint. A strong 150s run scores somewhere around 40-60k
    -- points, so 0.35 pays $14k-21k for two and a half minutes — several times
    -- a race win. Drop it to ~0.05 if rampage should be pocket money rather
    -- than the best earner on the server.
    Rampage = {
        durationSec   = 90,
        cashPerPoint  = 0.35,
        xpPerThousand = 2,
    },

    -- ── NPC street challenges ───────────────────────────────────────────────
    NpcChallenge = {
        rewardWin  = 2000,
        rewardLose = 0,
        xpWin      = 8,
    },

    -- ── Street pack escalation ───────────────────────────────────────────────
    -- Applied inside SKNpcRace.start (modules/npcchallenge/npcchallenge_c.lua)
    -- whenever a caller (the ambient burnout trigger or an npcInvite rival)
    -- doesn't pass its own pre-built racer list. Rolls whether the 1v1 grows
    -- into a small pack, spawns the extra rivals near the primary one, and
    -- pays out by finish placement instead of a flat win/lose amount. A pure
    -- 1v1 (packChance miss, or packMax rolled to 0 extras) still pays out of
    -- Config.NpcChallenge exactly as before this existed.
    StreetPack = {
        packChance = 40, -- percent chance a triggered challenge grows into a pack
        packMin    = 1,  -- extra rivals beyond the primary one (1 = 2v1, 2 = 3v1)
        packMax    = 2,

        finishRadius = 30.0, -- matches npcchallenge's own FINISH_RADIUS

        -- Reward/xp by finish placement (1st = you crossed first). Placements
        -- beyond the table length pay the last entry. Only used once a pack
        -- actually has extra rivals — see the note above.
        rewardsByPlace = { 3200, 1500, 700, 0 },
        xpByPlace      = { 14,   8,    4,   1 },

        -- Plain vanilla models grouped so pack mates roughly match the
        -- triggering car's class instead of, say, a Kuruma racing sedans.
        -- Falls back to NpcInvite.vehicleModels for any class not listed.
        vehiclePoolsByTier = {
            [1] = { 'banshee', 'elegy2', 'jester', 'massacro' },   -- Super/Sports/Classics/Muscle
            [2] = { 'sultan', 'tailgater', 'asea', 'emperor' },    -- Coupes/Sedans/Compacts/SUVs
            [3] = { 'sultanrs', 'sentinel' },                      -- Off-road/Vans fallback
        },
        driverPedModels = {
            'a_m_y_hipster_01', 'a_m_y_business_03', 'g_m_y_mexgoon_01', 'a_m_y_skater_01',
        },
    },

    -- ── NPC race invites (lb-phone) ─────────────────────────────────────────
    -- Payout is NpcChallenge's own, or StreetPack's if the invite happens to
    -- roll into a pack (same race, same server-side validation in
    -- npcchallenge_s.lua) - nothing here changes what winning or losing is worth.
    NpcInvite = {
        -- How often, while in freeroam with no challenge already running, a
        -- new invite is rolled. Randomised so it doesn't read as a timer.
        intervalMsMin = 8 * 60000,
        intervalMsMax = 15 * 60000,

        -- How long the player has to reach the meet-up point once texted
        -- before the rival gives up and the invite expires.
        responseWindowMs = 6 * 60000,

        -- Same distance band npcchallenge's own ambient destination uses -
        -- keeps the two race shapes consistent.
        meetupDistanceMin = 800,
        meetupDistanceMax = 1400,

        arriveRadius = 25.0,

        -- Plain vanilla models only - guaranteed present without depending on
        -- an add-on car pack this server may or may not have.
        vehicleModels = {
            'sultan', 'kuruma', 'elegy2', 'blista', 'futo',
        },

        -- Flavour only: which rival "texts" the player. No mechanical effect.
        rivalNames = {
            'Unknown Number', 'Rico', 'Dime', 'Sasha "Redline"', 'Vex',
        },

        -- %s is the rival name where used, %d the distance in metres.
        inviteMessages = {
            'pulled up near you. race to the mark before you lose your nerve.',
            'heard you talk a big game. prove it - meet me and we\'ll settle it.',
            'saw your ride. one race, no excuses. you in?',
        },

        acceptedMessage = 'knew you\'d show. first to the mark.',
        expiredMessage  = 'guess that was all talk. maybe next time.',
    },

    -- ── Speed cameras ───────────────────────────────────────────────────────
    SpeedCameras = {
        fine = 500,
        -- Charged to the bank so a player without cash still gets fined.
        fineAccount = 'bank',

        -- Also run camera sites placed with em_toolkit's Speed Cameras builder,
        -- if that resource is running. sk_streetkings works standalone off
        -- data/speed_cameras.lua without it.
        useToolkitCameras = true,
    },

    -- ── Police ──────────────────────────────────────────────────────────────
    -- Only read when Config.Modules.police is on, which it is not by default.
    Police = {
        bustFine            = 1000,  -- charged when a pursuit ends in a bust
        trapSpawnPercent    = 0.20,  -- share of data/police_traps.lua live per restart
        trapTriggerSpeedMph = 60.0,  -- speed past a trap cop that starts a chase
        radarDetector       = true,  -- in-car beeping as you close on a trap
    },

    -- ── Repair stations ─────────────────────────────────────────────────────
    Repair = {
        cost       = 0, -- set above 0 to charge for a roadside repair
        cooldownMs = 5000,
    },

    -- ── Car building (modules/carbuild/) ─────────────────────────────────────
    -- Two ways to get a cheap race car onto the roster, both paid for in the
    -- same raw materials um_scrapyard already hands out for scrapping junk
    -- cars (metalscrap/plastic/copper/iron/aluminum/steel/rubber — all real,
    -- already-live ox_inventory items, not new ones this adds). No new
    -- exports were needed on um_scrapyard's side: the materials already flow
    -- through the shared ox_inventory economy, so turning them in here is no
    -- different from turning them in for any other shop.
    CarBuild = {
        -- Turn a materials bundle in at any existing repair station
        -- (data/repair_stations.lua) for an instant budget racer, fully
        -- registered like any other owned vehicle via qbx_vehicles.
        assemble = {
            vehicleModel = 'blista',
            materials = {
                { item = 'metalscrap', amount = 40 },
                { item = 'steel',      amount = 25 },
                { item = 'aluminum',   amount = 15 },
                { item = 'rubber',     amount = 10 },
            },
            cashCost   = 2500, -- labour/registration, on top of the materials
            cooldownMs = 15 * 60000, -- per player, stops instant re-assembly farming
        },

        -- A cheap, deliberately trashed shell bought from a single Wreck Lot
        -- vendor, then brought back to any repair station across several
        -- paid visits to restore. Slower and cheaper overall than Assemble,
        -- and starts the player owning a real (if rough) car immediately.
        wreckLot = {
            -- ~20m from um_scrapyard's own delivery zone (2351.5, 3132.96,
            -- 48.2) - flat industrial ground by the look of that zone, but
            -- not yet run through mapquery. Flagged unverified the same way
            -- data/races.lua flags its own newer routes; check before
            -- relying on it for anything more than a rough stand-in.
            coords = vec4(2360.7, 3108.4, 48.2, 210.0),

            models       = { 'blista', 'futo', 'premier', 'primo' },
            priceMin     = 400,
            priceMax     = 900,

            -- Engine/body health (native 0-1000 scale) the wreck starts at.
            startHealthMin = 150,
            startHealthMax = 350,

            restoreStages     = 4, -- repair-station visits needed to fully restore
            materialsPerStage = {
                { item = 'metalscrap', amount = 10 },
                { item = 'steel',      amount = 8 },
                { item = 'aluminum',   amount = 5 },
            },
            cashCostPerStage = 400,
        },
    },
}

-- Cosmetic race level from accumulated race XP. No unlocks are gated on this,
-- it's purely a leaderboard bragging-rights number.
function Config.XpToLevel(xp)
    return math.floor(math.sqrt(math.max(0, xp) / 100))
end

-- GetVehicleClass() native returns 0-21; used to segregate leaderboards by class.
Config.VehicleClassNames = {
    [0] = 'Compacts',      [1] = 'Sedans',       [2] = 'SUVs',
    [3] = 'Coupes',        [4] = 'Muscle',       [5] = 'Sports Classics',
    [6] = 'Sports',        [7] = 'Super',        [8] = 'Motorcycles',
    [9] = 'Off-Road',      [10] = 'Industrial',  [11] = 'Utility',
    [12] = 'Vans',         [13] = 'Cycles',      [14] = 'Boats',
    [15] = 'Helicopters',  [16] = 'Planes',      [17] = 'Service',
    [18] = 'Emergency',    [19] = 'Military',    [20] = 'Commercial',
    [21] = 'Trains',
}
