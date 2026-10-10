-- osm-target - schema. Created automatically at first start; this file is here
-- for owners who prefer to apply schema changes by hand.

CREATE TABLE IF NOT EXISTS `osm_target_config` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `revision` INT UNSIGNED NOT NULL DEFAULT 1,
  `payload` LONGTEXT NOT NULL,
  `author` VARCHAR(64) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_revision` (`revision`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
