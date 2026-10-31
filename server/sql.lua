--[[ ============================================================
     WireGuard - MySQL layer (oxmysql)
     Optional. Active only when Config.Database.Enabled = true and
     the `oxmysql` resource is started. Uses oxmysql EXPORTS with an
     await wrapper, so no hard dependency on the oxmysql lib file.
     ============================================================ ]]

WG = WG or {}
WG.DB = { ready = false, enabled = false }

-- await a oxmysql export call inside a coroutine
local function await(method, query, params)
    local p = promise.new()
    exports.oxmysql[method](exports.oxmysql, query, params or {}, function(result)
        p:resolve(result)
    end)
    return Citizen.Await(p)
end

function WG.DB.query(q, params)  return await('query',  q, params) end
function WG.DB.execute(q, params) return await('execute', q, params) end
function WG.DB.insert(q, params) return await('insert', q, params) end
function WG.DB.scalar(q, params) return await('scalar', q, params) end
function WG.DB.single(q, params) return await('single', q, params) end

-- ─────────────────────────────────────────────
--  Table creation
-- ─────────────────────────────────────────────
local SCHEMA = {
[[CREATE TABLE IF NOT EXISTS `wireguard_bans` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `ban_id` VARCHAR(16) NOT NULL UNIQUE,
    `name` VARCHAR(128) DEFAULT NULL,
    `reason` TEXT,
    `banned_by` VARCHAR(128) DEFAULT 'WireGuard',
    `license` VARCHAR(128) DEFAULT NULL,
    `discord` VARCHAR(64) DEFAULT NULL,
    `steam` VARCHAR(64) DEFAULT NULL,
    `ip` VARCHAR(64) DEFAULT NULL,
    `identifiers` JSON DEFAULT NULL,
    `tokens` JSON DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `expires_at` TIMESTAMP NULL DEFAULT NULL,
    INDEX idx_license (`license`), INDEX idx_discord (`discord`), INDEX idx_ban_id (`ban_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
[[CREATE TABLE IF NOT EXISTS `wireguard_detections` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(128) DEFAULT NULL,
    `license` VARCHAR(128) DEFAULT NULL,
    `detection` VARCHAR(64) NOT NULL,
    `detail` TEXT,
    `action` VARCHAR(16) DEFAULT NULL,
    `severity` VARCHAR(16) DEFAULT 'medium',
    `trust` INT DEFAULT NULL,
    `pos_x` FLOAT DEFAULT NULL, `pos_y` FLOAT DEFAULT NULL, `pos_z` FLOAT DEFAULT NULL,
    `screenshot` VARCHAR(512) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_detection (`detection`), INDEX idx_license (`license`), INDEX idx_created (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
[[CREATE TABLE IF NOT EXISTS `wireguard_admins` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `license` VARCHAR(128) NOT NULL UNIQUE,
    `name` VARCHAR(128) DEFAULT NULL,
    `rank` VARCHAR(32) DEFAULT 'admin',
    `added_by` VARCHAR(128) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
[[CREATE TABLE IF NOT EXISTS `wireguard_logs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `admin` VARCHAR(128) DEFAULT NULL,
    `action` VARCHAR(64) NOT NULL,
    `target` VARCHAR(128) DEFAULT NULL,
    `detail` TEXT,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_created (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]],
[[CREATE TABLE IF NOT EXISTS `wireguard_whitelist` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `license` VARCHAR(128) NOT NULL UNIQUE,
    `name` VARCHAR(128) DEFAULT NULL,
    `added_by` VARCHAR(128) DEFAULT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_license (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]]
}

-- ─────────────────────────────────────────────
--  Detection / log helpers (safe no-ops if DB off)
-- ─────────────────────────────────────────────
function WG.DB.logDetection(e)
    if not WG.DB.ready or not Config.Database.LogDetections then return end
    local c = e.coords or {}
    WG.DB.insert([[INSERT INTO wireguard_detections
        (name, license, detection, detail, action, severity, trust, pos_x, pos_y, pos_z)
        VALUES (?,?,?,?,?,?,?,?,?,?)]], {
        e.name, e.license, e.detection, e.detail, e.action, e.severity, e.trust,
        c.x, c.y, c.z
    })
end

function WG.DB.logAction(admin, action, target, detail)
    if not WG.DB.ready then return end
    WG.DB.insert('INSERT INTO wireguard_logs (admin, action, target, detail) VALUES (?,?,?,?)',
        { admin, action, target, detail })
end

function WG.DB.getAdmins()
    if not WG.DB.ready then return {} end
    return WG.DB.query('SELECT license, name, rank, added_by, created_at FROM wireguard_admins') or {}
end

function WG.DB.getHistory(limit, detection)
    if not WG.DB.ready then return {} end
    limit = math.min(tonumber(limit) or 100, 1000)
    if detection and detection ~= '' then
        return WG.DB.query('SELECT * FROM wireguard_detections WHERE detection = ? ORDER BY id DESC LIMIT ?', { detection, limit }) or {}
    end
    return WG.DB.query('SELECT * FROM wireguard_detections ORDER BY id DESC LIMIT ?', { limit }) or {}
end

function WG.DB.getLogs(limit)
    if not WG.DB.ready then return {} end
    return WG.DB.query('SELECT * FROM wireguard_logs ORDER BY id DESC LIMIT ?', { math.min(tonumber(limit) or 100, 500) }) or {}
end

function WG.DB.getAnalytics()
    if not WG.DB.ready then return {} end
    return {
        total      = WG.DB.scalar('SELECT COUNT(*) FROM wireguard_detections') or 0,
        last24h    = WG.DB.scalar('SELECT COUNT(*) FROM wireguard_detections WHERE created_at > NOW() - INTERVAL 1 DAY') or 0,
        totalBans  = WG.DB.scalar('SELECT COUNT(*) FROM wireguard_bans') or 0,
        topTypes   = WG.DB.query('SELECT detection, COUNT(*) AS c FROM wireguard_detections GROUP BY detection ORDER BY c DESC LIMIT 8') or {},
        perDay     = WG.DB.query('SELECT DATE(created_at) AS d, COUNT(*) AS c FROM wireguard_detections WHERE created_at > NOW() - INTERVAL 14 DAY GROUP BY DATE(created_at) ORDER BY d') or {},
        topPlayers = WG.DB.query('SELECT name, license, COUNT(*) AS c FROM wireguard_detections GROUP BY license, name ORDER BY c DESC LIMIT 8') or {}
    }
end

function WG.DB.addAdmin(license, name, rank, by)
    if not WG.DB.ready then return false end
    WG.DB.execute([[INSERT INTO wireguard_admins (license, name, rank, added_by)
        VALUES (?,?,?,?) ON DUPLICATE KEY UPDATE name=VALUES(name), rank=VALUES(rank)]],
        { license, name, rank or 'admin', by })
    return true
end

function WG.DB.removeAdmin(license)
    if not WG.DB.ready then return false end
    WG.DB.execute('DELETE FROM wireguard_admins WHERE license = ?', { license })
    return true
end

function WG.DB.getWhitelist()
    if not WG.DB.ready then return {} end
    return WG.DB.query('SELECT license, name, added_by, created_at FROM wireguard_whitelist ORDER BY created_at DESC') or {}
end

function WG.DB.addWhitelist(license, name, by)
    if not WG.DB.ready then return false end
    WG.DB.execute([[INSERT INTO wireguard_whitelist (license, name, added_by)
        VALUES (?,?,?) ON DUPLICATE KEY UPDATE name=VALUES(name)]], { license, name, by })
    return true
end

function WG.DB.removeWhitelist(license)
    if not WG.DB.ready then return false end
    WG.DB.execute('DELETE FROM wireguard_whitelist WHERE license = ?', { license })
    return true
end

-- ─────────────────────────────────────────────
--  Init
-- ─────────────────────────────────────────────
CreateThread(function()
    if not Config.Database.Enabled then
        WG.log('database disabled - using JSON storage')
        return
    end
    WG.DB.enabled = true

    -- wait for oxmysql
    local tries = 0
    while GetResourceState('oxmysql') ~= 'started' and tries < 50 do
        Wait(200); tries = tries + 1
    end
    if GetResourceState('oxmysql') ~= 'started' then
        WG.err('Config.Database.Enabled=true but oxmysql is not started! Falling back to JSON.')
        WG.DB.enabled = false
        return
    end

    if Config.Database.AutoCreateTables then
        for _, stmt in ipairs(SCHEMA) do
            local ok, err = pcall(WG.DB.execute, stmt)
            if not ok then WG.err('schema error: ' .. tostring(err)) end
        end
    end

    WG.DB.ready = true
    print('^5[WireGuard]^7 MySQL connected & tables ready')
end)
