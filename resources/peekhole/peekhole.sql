-- Run this SQL once before starting the resource.

CREATE TABLE IF NOT EXISTS `lonelymans_profiles` (
    `citizenid`          VARCHAR(50)  NOT NULL,
    `display_name`       VARCHAR(50)  NOT NULL,
    `bio`                TEXT         DEFAULT NULL,
    `profile_pic`        TEXT         DEFAULT NULL,
    `banner_pic`         TEXT         DEFAULT NULL,
    `subscription_price` INT(11)      NOT NULL DEFAULT 0,
    `total_earnings`     INT(11)      NOT NULL DEFAULT 0,
    `created_at`         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`)
);

CREATE TABLE IF NOT EXISTS `lonelymans_posts` (
    `id`                 INT(11)      NOT NULL AUTO_INCREMENT,
    `creator_citizenid`  VARCHAR(50)  NOT NULL,
    `caption`            TEXT         DEFAULT NULL,
    `media_url`          TEXT         NOT NULL,
    `media_type`         VARCHAR(10)  NOT NULL DEFAULT 'image',
    `unlock_price`       INT(11)      NOT NULL DEFAULT 0,
    `created_at`         TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_creator` (`creator_citizenid`)
);

CREATE TABLE IF NOT EXISTS `lonelymans_subscriptions` (
    `id`                   INT(11)     NOT NULL AUTO_INCREMENT,
    `subscriber_citizenid` VARCHAR(50) NOT NULL,
    `creator_citizenid`    VARCHAR(50) NOT NULL,
    `created_at`           TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_sub` (`subscriber_citizenid`, `creator_citizenid`)
);

CREATE TABLE IF NOT EXISTS `lonelymans_unlocked_posts` (
    `id`         INT(11)     NOT NULL AUTO_INCREMENT,
    `citizenid`  VARCHAR(50) NOT NULL,
    `post_id`    INT(11)     NOT NULL,
    `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_unlock` (`citizenid`, `post_id`)
);

CREATE TABLE IF NOT EXISTS `lonelymans_streams` (
    `id`                INT(11)      NOT NULL AUTO_INCREMENT,
    `creator_citizenid` VARCHAR(50)  NOT NULL,
    `title`             VARCHAR(100) NOT NULL DEFAULT 'Live Stream',
    `instapic_user`     VARCHAR(50)  NOT NULL DEFAULT '',
    `price`             INT(11)      NOT NULL DEFAULT 0,
    `viewer_count`      INT(11)      NOT NULL DEFAULT 0,
    `created_at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `ended_at`          TIMESTAMP    NULL DEFAULT NULL,
    PRIMARY KEY (`id`),
    KEY `idx_live` (`creator_citizenid`, `ended_at`)
);

CREATE TABLE IF NOT EXISTS `lonelymans_stream_access` (
    `id`         INT(11)     NOT NULL AUTO_INCREMENT,
    `stream_id`  INT(11)     NOT NULL,
    `citizenid`  VARCHAR(50) NOT NULL,
    `created_at` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `unique_access` (`stream_id`, `citizenid`)
);
