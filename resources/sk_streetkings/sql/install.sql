-- sk_streetkings schema. Run once before starting the resource.
--
-- Carries over the two tables sk_racing already used (unchanged, so existing
-- lap times and admin-built routes survive the merge) and replaces
-- sk_race_profiles with a single JSON profile document per citizen.

CREATE TABLE IF NOT EXISTS `sk_race_leaderboards` (
    `id`            INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid`     VARCHAR(50)  NOT NULL,
    `alias`         VARCHAR(64)  NOT NULL,
    `event_id`      VARCHAR(64)  NOT NULL,
    `vehicle_class` VARCHAR(32)  NOT NULL DEFAULT '',
    `score_ms`      INT          NOT NULL,
    `vehicle_model` VARCHAR(64)  NOT NULL DEFAULT '',
    `created_at`    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_event_class_score` (`event_id`, `vehicle_class`, `score_ms`),
    KEY `idx_event_created` (`event_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `sk_race_routes` (
    `id`         VARCHAR(64) NOT NULL PRIMARY KEY,
    `name`       VARCHAR(64) NOT NULL,
    `scheme`     VARCHAR(16) NOT NULL DEFAULT 'ordered',
    `data`       LONGTEXT    NOT NULL,
    `creator`    VARCHAR(50) NOT NULL,
    `created_at` TIMESTAMP   DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Progression, stats, settings, unlocks and daily-event state.
-- Money, garage, properties and identity are NOT stored here — those stay with
-- qbx_core, qbx_garages and sn_properties respectively.
CREATE TABLE IF NOT EXISTS `sk_profiles` (
    `citizenid`  VARCHAR(50) NOT NULL PRIMARY KEY,
    `document`   LONGTEXT    NOT NULL,
    `updated_at` TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Per-activity best scores that need cross-player ranking (stunt jumps,
-- rampage). Kept relational rather than inside the profile document so a
-- leaderboard query does not have to scan every profile.
CREATE TABLE IF NOT EXISTS `sk_activity_scores` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid`   VARCHAR(50) NOT NULL,
    `alias`       VARCHAR(64) NOT NULL,
    `activity`    VARCHAR(32) NOT NULL, -- 'stunt' | 'rampage' | 'drift'
    `activity_id` VARCHAR(64) NOT NULL DEFAULT '', -- e.g. a stunt jump id
    `score`       INT         NOT NULL,
    `created_at`  TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uniq_citizen_activity` (`citizenid`, `activity`, `activity_id`),
    KEY `idx_activity_score` (`activity`, `activity_id`, `score`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Stunt jumps placed in-game with /stuntdev. `data` holds the zone pair and
-- ramp props; `id` and `name` are columns so they can be listed without
-- decoding every row. Jumps written by hand in data/stunt_jumps.lua are merged
-- with these at startup, with the database winning on a clash.
CREATE TABLE IF NOT EXISTS `sk_stunt_jumps` (
    `id`         VARCHAR(64)  NOT NULL PRIMARY KEY,
    `name`       VARCHAR(128) NOT NULL,
    `data`       LONGTEXT     NOT NULL,
    `creator`    VARCHAR(50)  NOT NULL DEFAULT '',
    `created_at` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Per-vehicle upgrades that are not native GTA vehicle mods, so um_customs'
-- `player_vehicles.mods` blob cannot carry them. Keyed by plate, matching how
-- um_customs identifies a vehicle.
CREATE TABLE IF NOT EXISTS `sk_vehicle_upgrades` (
    `plate`        VARCHAR(12) NOT NULL PRIMARY KEY,
    `nitrous_tier` VARCHAR(16) NOT NULL DEFAULT '',
    `updated_at`   TIMESTAMP   DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ── Optional: migration from sk_racing ──────────────────────────────────────
-- Run this ONLY if you previously ran sk_racing and its sk_race_profiles table
-- still exists. It is deliberately left out of the statements above because
-- MySQL resolves table names at parse time, so referencing a table that was
-- never created aborts the whole script.
--
-- Check first:
--     SHOW TABLES LIKE 'sk_race_profiles';
--
-- Then, if it returned a row, fold the old xp/level rows into the new profile
-- document. INSERT IGNORE makes it safe to re-run; citizens who already have an
-- sk_profiles row are left untouched.
--
--     INSERT IGNORE INTO `sk_profiles` (`citizenid`, `document`)
--     SELECT
--         `citizenid`,
--         JSON_OBJECT(
--             'progression', JSON_OBJECT('level', `level`, 'playerXp', `xp`, 'bestActivityScores', JSON_OBJECT()),
--             'stats',       JSON_OBJECT(),
--             'settings',    JSON_OBJECT(),
--             'unlocks',     JSON_OBJECT(),
--             'events',      JSON_OBJECT('dayKey', '', 'claimedRewards', JSON_OBJECT())
--         )
--     FROM `sk_race_profiles`;
--
-- Once you have confirmed the migration, drop the old table:
--
--     DROP TABLE `sk_race_profiles`;
