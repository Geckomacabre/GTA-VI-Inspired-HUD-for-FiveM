---@alias Difficulty 'easy' | 'medium' | 'hard' | {areaSize: number, speedMultiplier: number}

---Arguments of https://overextended.dev/ox_lib/Modules/Interface/Client/skillcheck
---@class SkillCheckConfig
---@field difficulty Difficulty[]
---@field inputs? string[]

---@type SkillCheckConfig
local easyLockpickSkillCheck = {
    difficulty = { 'easy', 'easy', { areaSize = 60, speedMultiplier = 1 }, 'easy' },
    inputs = { '1' }
}

---@type SkillCheckConfig
local normalLockpickSkillCheck = {
    difficulty = { 'easy', 'easy', { areaSize = 60, speedMultiplier = 1 }, 'easy' },
    inputs = { '1' }
}

---@type SkillCheckConfig
local hardLockpickSkillCheck = {
    difficulty = { 'easy', 'easy', { areaSize = 60, speedMultiplier = 1 }, 'medium' },
    inputs = { '1' }
}

return {
    vehicleMaximumLockingDistance = 5.0, -- Minimum distance for vehicle locking
    getKeysWhenEngineIsRunning = true, -- when enabled, gives keys to a player who doesn't have them if they enter the driver seat when the engine is running
    keepEngineOnWhenAbandoned = true, -- when enabled, keeps a vehicle's engine running after exiting

    -- Carjack Settings
    carjackEnable = true,                -- Enables the ability to carjack pedestrian vehicles, stealing them by pointing a weapon at them
    carjackingTimeInMs = 7500,           -- Time it takes to successfully carjack in miliseconds
    delayBetweenCarjackingsInMs = 10000, -- Time before you can attempt another carjack in miliseconds

    -- Hotwire Settings
    timeBetweenHotwires = 5000, -- Time in milliseconds between hotwire attempts
    minKeysSearchTime = 10000,  -- Minimum hotwire time in milliseconds
    maxKeysSearchTime = 20000,  -- Maximum hotwire time in milliseconds

    -- ------------------------------------------------------------------
    -- Window Smash Settings (Upstate Mafia addition, see client/smashwindow.lua)
    -- Third-eye the driver door of a locked vehicle you have no keys for to get
    -- a "Smash Window" option. Succeeding unlocks the doors, so the normal
    -- hotwire path (search for keys with [H], or a lockpick) takes over from
    -- there. No item is required - the cost is noise, stress, honor and a
    -- police alert.
    -- ------------------------------------------------------------------
    smashWindow = {
        enable = true,
        maxDistance = 2.5,            -- ox_target interaction distance

        -- Which bones the option appears on. Driver side only: you should have
        -- to go to the door you intend to climb through.
        targetBones = { 'door_dside_f', 'window_lf' },

        baseDurationMs = 4500,        -- total time at neutral honor, before the tier multiplier
        alarmDurationMs = 15000,      -- how long the vehicle alarm wails after a smash
        stressGain = { 2, 6 },        -- min/max stress applied on a successful smash

        ---How far through the forced-entry clip (0-1) the elbow actually
        ---connects with the glass. SMASH_VEHICLE_WINDOW is called at exactly
        ---this point of the animation instead of when the progress bar ends,
        ---which is what stopped the glass and the swing from lining up.
        ---Raise it if the glass goes before the strike lands, lower it if it
        ---goes after.
        smashAtPhase = 0.35,

        ---Walks the player onto the driver's door before the break-in plays,
        ---using the engine's own entry point for that door
        ---(GET_ENTRY_POINT_POSITION) and facing the car side-on -- the clips
        ---themselves carry almost no offset, so without this the player just
        ---plays the swing wherever they happen to be stood. See
        ---solveBreakInScene in client/smashwindow.lua for how it is solved.
        ---Set false to skip the walk and play them in place if an addon
        ---vehicle ends up looking wrong.
        alignToVehicle = true,

        ---Honor tuning. Tier comes from qbx_honor (angel / devil / nil for neutral);
        ---if qbx_honor isn't running, every player is treated as neutral and the
        ---honor loss below is simply never applied.
        ---`durationMultiplier` scales baseDurationMs - a career criminal is quicker
        ---about it, a clean-handed character fumbles.
        ---`alertChanceMultiplier` is rolled before the resource's normal police-alert
        ---roll, so it only ever reduces the odds relative to that baseline.
        honor = {
            angel = { durationMultiplier = 1.4, alertChanceMultiplier = 1.0 },
            neutral = { durationMultiplier = 1.0, alertChanceMultiplier = 0.85 },
            devil = { durationMultiplier = 0.65, alertChanceMultiplier = 0.6 },
        },

        ---Note: the honor *cost* of a smash is not set here. server/main.lua calls
        ---qbx_honor's ApplyHook, so the amount lives in qbx_honor/config.lua
        ---(Config.Hooks.window_smash) along with every other hook amount.
    },

    -- ------------------------------------------------------------------
    -- Slim Jim Settings (see client/slimjim.lua)
    -- Third-eye the driver door of a locked vehicle for a "Slim Jim" option
    -- alongside Smash Window, playing out on vice_hud's own GTA6-styled
    -- lockpick ring rather than LockpickDoor's ox_lib lib.skillCheck
    -- (client/functions.lua) -- that function, and the item-use event
    -- (lockpicks:UseLockpick) that triggers it, are untouched and still
    -- exist as a separate, unconnected path (no item currently fires it —
    -- see items.lua's 'lockpick' entry). This is a second, parallel front
    -- end for the same kind of theft, not a replacement.
    --
    -- Needs a lockpick or advancedlockpick item. Quieter than smashing (no
    -- alarm, lower alert chance) but costs the tool on a failed attempt,
    -- same as LockpickDoor's own breakLockpick. Succeeding unlocks the
    -- doors, same hand-off to the normal hotwire path smashWindow uses.
    -- ------------------------------------------------------------------
    slimJim = {
        enable = true,
        maxDistance = 2.5,             -- ox_target interaction distance
        targetBones = { 'door_dside_f' },

        -- The vice_hud lockpick ring: hold, release inside the highlighted
        -- zone. zoneLen is the win window's width as a percentage of the
        -- ring (0-100) -- wider is easier. advancedlockpick gets the wider
        -- zone; a plain lockpick gets the baseline one.
        ringDurationMs = 3000,
        zoneLenBase = 10,
        zoneLenAdvanced = 16,

        -- Break chance on a FAILED attempt reuses vehicleConfig's own
        -- removeNormalLockpickChance / removeAdvancedLockpickChance
        -- (shared/vehicle-config.lua) rather than a second, separately-
        -- tuned pair here -- those already exist for exactly this, and
        -- LockpickDoor (client/functions.lua) already reads them the same
        -- way, so a vehicle tuned harder to lockpick is harder for BOTH
        -- flows to walk away from, not just one of them.

        stressGain = { 2, 5 },         -- min/max stress on a successful pick

        -- While the ring runs, he bends to the window and works a slim jim
        -- (a 50 cm strip, in his fists) into the door, with the single-
        -- player version's own clips (stream/vi_slimjim.ycd,
        -- stream/vi_prop_slimjim). false: config.anims.slimJim instead.
        animation = true,

        -- Same honor-tuning shape as smashWindow, scaling the ring's fill
        -- duration -- a career criminal works the lock faster.
        honor = {
            angel = { durationMultiplier = 1.3, alertChanceMultiplier = 1.0 },
            neutral = { durationMultiplier = 1.0, alertChanceMultiplier = 0.6 },
            devil = { durationMultiplier = 0.75, alertChanceMultiplier = 0.35 },
        },

        ---Honor cost lives in qbx_honor/config.lua like window_smash's does --
        ---see Config.Hooks.window_smash; slim_jim reuses that same hook rather
        ---than needing its own entry, since both represent the same act
        ---(illegally entering someone else's vehicle).
    },

    -- Clone Key (client/keyclone.lua): the single-player HUD's key cloning on
    -- a locked car's driver door, for a player carrying a key cloner (an
    -- ox_inventory item, never used up). The timing game is vice_hud's key
    -- clone check: three hits clone the key with no alarm, three misses set
    -- the car's alarm off (smashWindow.alarmDurationMs).
    keyClone = {
        enable = true,
        maxDistance = 2.5,             -- ox_target interaction distance
        targetBones = { 'door_dside_f' },
        item = 'key_cloner',
        stressGain = { 1, 3 },         -- min/max stress on a clean clone
    },

    -- Police Alert Settings
    alertCooldown = 10000,         -- Cooldown period in milliseconds (10 seconds)
    -- Lowered from 0.75 / 0.50: every alert becomes a 1-star fenix-police
    -- response via um_fenix_bridge, so most break-ins were drawing cops.
    policeAlertChance = 0.40,      -- Chance of alerting the police during the day
    policeNightAlertChance = 0.25, -- Chance of alerting the police at night (times: 01-06)
    policeAlertNightStartHour = 1,
    policeAlertNightDuration = 5,

    ---Sends an alert to police
    ---@param crime string
    ---@param vehicle number entity
    alertPolice = function(crime, vehicle)
        TriggerServerEvent('police:server:policeAlert', locale("info.vehicle_theft") .. crime)
    end,

    vehicleAlarmDuration = 10000,
    lockpickCooldown = 1000,
    hotwireCooldown = 1000,

    -- Job Settings
    ---@class SharedKeysConfig
    ---@field enableAutolock? boolean auto-lock door on driver exit
    ---@field requireOnDuty? boolean requires player to be on duty to access the vehicle
    ---@field classes? table<VehicleClass, boolean> vehicle classes to enable shared keys on
    ---@field vehicles? table<number, boolean> vehicle hashes to enable shared keys on

    ---@alias JobName string
    ---@type table<JobName, SharedKeysConfig>
    sharedKeys = { -- Share keys amongst employees. Employees can lock/unlock any job-listed vehicle
        police = { -- Job name
            enableAutolock = true,
            requireOnduty = true,
            classes = {},
            vehicles = {
                [`police`] = true,  -- Vehicle model
                [`police2`] = true, -- Vehicle model
            }
        },
        ambulance = {
            enableAutolock = true,
            requireOnduty = true,
            classes = {},
            vehicles = {
                [`ambulance`] = true,
            },
        },
        mechanic = {
            requireOnduty = false,
            vehicles = {
                [`towtruck`] = true,
            }
        }
    },

    ---@class SkillCheckConfigEntry
    ---@field default SkillCheckConfig
    ---@field class table<VehicleClass, SkillCheckConfig | {}>
    ---@field model table<number, SkillCheckConfig>

    ---@class SkillCheckEntities
    ---@field lockpick SkillCheckConfigEntry
    ---@field advancedLockpick SkillCheckConfigEntry
    ---@field hotwire SkillCheckConfigEntry
    ---@field advancedHotwire SkillCheckConfigEntry

    ---@type SkillCheckEntities
    skillCheck = {
        lockpick = {
            default = normalLockpickSkillCheck,
            class = {
                [VehicleClass.PLANES] = hardLockpickSkillCheck,
                [VehicleClass.HELICOPTERS] = hardLockpickSkillCheck,
                [VehicleClass.EMERGENCY] = hardLockpickSkillCheck,
                [VehicleClass.MILITARY] = {}, -- cannot be lockpicked
                [VehicleClass.TRAINS] = {}, -- cannot be lockpicked
                [VehicleClass.OPEN_WHEEL] = easyLockpickSkillCheck,
            },
            model = {}
        },
        advancedLockpick = {
            default = easyLockpickSkillCheck,
            class = {
                [VehicleClass.PLANES] = hardLockpickSkillCheck,
                [VehicleClass.HELICOPTERS] = hardLockpickSkillCheck,
                [VehicleClass.EMERGENCY] = hardLockpickSkillCheck,
                [VehicleClass.MILITARY] = {}, -- cannot be lockpicked
                [VehicleClass.TRAINS] = {}, -- cannot be lockpicked
            },
            model = {}
        },
        hotwire = {
            default = normalLockpickSkillCheck,
            class = {
                [VehicleClass.PLANES] = hardLockpickSkillCheck,
                [VehicleClass.HELICOPTERS] = hardLockpickSkillCheck,
                [VehicleClass.EMERGENCY] = hardLockpickSkillCheck,
                [VehicleClass.MILITARY] = {}, -- cannot be hotwired
                [VehicleClass.TRAINS] = {}, -- cannot be hotwired
                [VehicleClass.OPEN_WHEEL] = easyLockpickSkillCheck,
            },
            model = {}
        },
        advancedHotwire = {
            default = easyLockpickSkillCheck,
            class = {
                [VehicleClass.PLANES] = hardLockpickSkillCheck,
                [VehicleClass.HELICOPTERS] = hardLockpickSkillCheck,
                [VehicleClass.EMERGENCY] = hardLockpickSkillCheck,
                [VehicleClass.MILITARY] = {}, -- cannot be hotwired
                [VehicleClass.TRAINS] = {}, -- cannot be hotwired
            },
            model = {}
        }
    },

    ---@class AnimConfigEntry
    ---@field default Anim
    ---@field class table<VehicleClass, Anim | {}>
    ---@field model table<number, Anim>

    ---@class AnimConfigEntities
    ---@field hotwire AnimConfigEntry
    ---@field smashTryDoor AnimConfigEntry
    ---@field smashImpact AnimConfigEntry
    ---@field searchKeys AnimConfigEntry
    ---@field lockpick AnimConfigEntry
    ---@field holdup AnimConfigEntry
    ---@field toggleEngine AnimConfigEntry

    ---@type AnimConfigEntities
    anims = {
        hotwire = {
            default = {
                dict = 'anim@veh@plane@howard@front@ds@base',
                clip = 'hotwire'
            },
            class = {},
            model = {}
        },
        searchKeys = {
            default = {
                dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
                clip = 'machinic_loop_mechandplayer',
            },
            class = {},
            model = {}
        },
        lockpick = {
            -- Any of default/class/model may be ONE { dict, clip } or a LIST
            -- of them, in which case one is picked at random per attempt. See
            -- ResolveVehicleAnim in client/functions.lua. A variant whose dict
            -- does not exist on this build is dropped and reported once in the
            -- console, so a bad entry degrades to the ones that do work rather
            -- than playing nothing at all.
            --
            -- The dict is named for the player model the clips were authored
            -- on (p_m_one is Franklin, whose break-in reads as working a door
            -- with a tool rather than wrenching it open). They are plain
            -- skeletal animation and play on freemode peds fine, which the
            -- rest of the server already relies on.
            --
            -- REAL clip list for this dict, from DurtyFree's animDictsCompact
            -- dump (not guesswork): low_force_entry_ds/ps, low_locked_ds/ps,
            -- std_force_entry_ds/ps/rds/rps, std_locked_ds/ps/rds/rps. Note
            -- the naming: `force_entry` is the break-in itself and `locked`
            -- is the shorter "tried the handle, it's locked" clip -- there is
            -- no `force_entry_locked` variant, which is why the second entry
            -- here used to be dropped at startup and every lockpick played
            -- the same single clip.
            --
            -- `ds` = driver side, `ps` = passenger, `rds`/`rps` = the rear
            -- doors; `std` vs `low` is the vehicle's entry height (see
            -- smashImpact below). An invalid clip makes TaskPlayAnim silently
            -- no-op, so do not add one that is not on that list.
            default = {
                { dict = 'veh@break_in@0h@p_m_one@', clip = 'low_force_entry_ds' },
                { dict = 'veh@break_in@0h@p_m_one@', clip = 'low_locked_ds' },
            },
            class = {},
            model = {}
        },
        -- Slim jim is the same act as the lockpick above with a different tool
        -- in hand, so it shares those gentler working-the-door clips rather
        -- than the one-shot strike smashImpact plays below.
        slimJim = {
            default = {
                { dict = 'veh@break_in@0h@p_m_one@', clip = 'low_force_entry_ds' },
                { dict = 'veh@break_in@0h@p_m_one@', clip = 'low_locked_ds' },
            },
            class = {},
            model = {}
        },
        -- ------------------------------------------------------------------
        -- The two halves of a window smash, both taken straight from the
        -- clips Rockstar's own vehiclelayouts.meta hands the enter-vehicle
        -- task for a locked car:
        --
        --   <AlternateTryLockedDoorClipId>STD_Locked_DS
        --   <AlternateForcedEntryClipId>STD_Force_Entry_DS
        --
        -- so `smashTryDoor` below is literally the game's "tried the handle,
        -- it's locked" clip and `smashImpact` is its break-in. Running them
        -- in that order is what the engine does, and is why the sequence now
        -- reads as a vanilla break-in rather than one clip on repeat.
        --
        -- p_m_zero is Michael's break-in set. That choice matters: Michael
        -- and Trevor put an elbow through the glass, Franklin (p_m_one, used
        -- by lockpick/slimJim above) works the door with a tool instead --
        -- which is exactly the split those two options want.
        --
        -- std vs low is the vehicle's entry height. The engine picks it per
        -- entry point in vehiclelayouts.meta, which script cannot read, so
        -- the low-slung classes are listed under `class` as the practical
        -- approximation -- on a Comet the std clip swings above the glass.
        -- A specific model that reads wrong can be pinned under `model`.
        --
        -- 'veh@common@car@ds' / 'smash' (an earlier guess) is NOT real --
        -- confirmed dropped in the F8 console on 2026-09-13. The clip names
        -- used here are from DurtyFree's animDictsCompact dump; see the
        -- lockpick entry above for the dict's full contents.
        -- ------------------------------------------------------------------
        smashTryDoor = {
            default = {
                dict = 'veh@break_in@0h@p_m_zero@',
                clip = 'std_locked_ds',
            },
            class = {
                [VehicleClass.COUPES] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_locked_ds' },
                [VehicleClass.SPORTS_CLASSICS] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_locked_ds' },
                [VehicleClass.SPORTS] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_locked_ds' },
                [VehicleClass.SUPER] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_locked_ds' },
                [VehicleClass.OPEN_WHEEL] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_locked_ds' },
            },
            model = {}
        },
        smashImpact = {
            default = {
                dict = 'veh@break_in@0h@p_m_zero@',
                clip = 'std_force_entry_ds',
            },
            class = {
                [VehicleClass.COUPES] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_force_entry_ds' },
                [VehicleClass.SPORTS_CLASSICS] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_force_entry_ds' },
                [VehicleClass.SPORTS] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_force_entry_ds' },
                [VehicleClass.SUPER] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_force_entry_ds' },
                [VehicleClass.OPEN_WHEEL] = { dict = 'veh@break_in@0h@p_m_zero@', clip = 'low_force_entry_ds' },
            },
            model = {}
        },
        holdup = {
            default = {
                dict = 'mp_am_hold_up',
                clip = 'holdup_victim_20s'
            },
            class = {},
            model = {}
        },
        toggleEngine = {
            default = {
                dict = 'oddjobs@towing',
                clip = 'start_engine',
                delay = 400, -- how long it takes to start the engine
            },
            class = {
                [VehicleClass.MOTORCYCLES] = {
                    dict = 'veh@bike@quad@front@base',
                    clip = 'start_engine',
                    delay = 1000,
                },
                [VehicleClass.CYCLES] = {}, -- does not have an engine
            },
            model = {},
        },
    },
    -- Weapons that cannot be used for carjacking
    noCarjackWeapons = {
        `WEAPON_UNARMED`,
        `WEAPON_KNIFE`,
        `WEAPON_NIGHTSTICK`,
        `WEAPON_HAMMER`,
        `WEAPON_BAT`,
        `WEAPON_CROWBAR`,
        `WEAPON_GOLFCLUB`,
        `WEAPON_BOTTLE`,
        `WEAPON_DAGGER`,
        `WEAPON_HATCHET`,
        `WEAPON_KNUCKLE`,
        `WEAPON_MACHETE`,
        `WEAPON_FLASHLIGHT`,
        `WEAPON_SWITCHBLADE`,
        `WEAPON_POOLCUE`,
        `WEAPON_WRENCH`,
        `WEAPON_BATTLEAXE`,
        `WEAPON_GRENADE`,
        `WEAPON_STOCKYBOMB`,
        `WEAPON_PROXIMITYMINE`,
        `WEAPON_BZGAS`,
        `WEAPON_MOLOTOV`,
        `WEAPON_FIREEXTINGUISHER`,
        `WEAPON_PETROLCAN`,
        `WEAPON_FLARE`,
        `WEAPON_BALL`,
        `WEAPON_SNOWBALL`,
        `WEAPON_SMOKEGRENADE`,
        -- Add more weapon names as needed
    },
}
