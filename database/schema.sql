-- ============================================================
--  WireGuard — MySQL schema
--  Import into your database (or let the resource auto-create
--  the tables on first start when Config.Database.Enabled = true).
--    mysql -u root -p your_db < schema.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS `wireguard_bans` (
    `id`          INT AUTO_INCREMENT PRIMARY KEY,
    `ban_id`      VARCHAR(16) NOT NULL UNIQUE,
    `name`        VARCHAR(128) DEFAULT NULL,
    `reason`      TEXT,
    `banned_by`   VARCHAR(128) DEFAULT 'WireGuard',
    `license`     VARCHAR(128) DEFAULT NULL,
    `discord`     VARCHAR(64)  DEFAULT NULL,
    `steam`       VARCHAR(64)  DEFAULT NULL,
    `ip`          VARCHAR(64)  DEFAULT NULL,
    `identifiers` JSON         DEFAULT NULL,
    `tokens`      JSON         DEFAULT NULL,
    `created_at`  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `expires_at`  TIMESTAMP NULL DEFAULT NULL,
    INDEX idx_license (`license`),
    INDEX idx_discord (`discord`),
    INDEX idx_ban_id  (`ban_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `wireguard_detections` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `name`       VARCHAR(128) DEFAULT NULL,
    `license`    VARCHAR(128) DEFAULT NULL,
    `detection`  VARCHAR(64)  NOT NULL,
    `detail`     TEXT,
    `action`     VARCHAR(16)  DEFAULT NULL,
    `severity`   VARCHAR(16)  DEFAULT 'medium',
    `trust`      INT          DEFAULT NULL,
    `pos_x`      FLOAT        DEFAULT NULL,
    `pos_y`      FLOAT        DEFAULT NULL,
    `pos_z`      FLOAT        DEFAULT NULL,
    `screenshot` VARCHAR(512) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_detection (`detection`),
    INDEX idx_license   (`license`),
    INDEX idx_created   (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `wireguard_admins` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `license`    VARCHAR(128) NOT NULL UNIQUE,
    `name`       VARCHAR(128) DEFAULT NULL,
    `rank`       VARCHAR(32)  DEFAULT 'admin',
    `added_by`   VARCHAR(128) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `wireguard_logs` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `admin`      VARCHAR(128) DEFAULT NULL,
    `action`     VARCHAR(64)  NOT NULL,
    `target`     VARCHAR(128) DEFAULT NULL,
    `detail`     TEXT,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_created (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `wireguard_whitelist` (
    `id`         INT AUTO_INCREMENT PRIMARY KEY,
    `license`    VARCHAR(128) NOT NULL UNIQUE,
    `name`       VARCHAR(128) DEFAULT NULL,
    `added_by`   VARCHAR(128) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_license (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
