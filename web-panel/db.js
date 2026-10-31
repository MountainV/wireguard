/* ============================================================
 * WireGuard Web Panel — MySQL layer (mysql2)
 * Connects directly to the same database the FiveM resource uses,
 * so bans / history / admins / logs / analytics are available even
 * when the FiveM server is offline. Disabled when DB_HOST is empty.
 * ========================================================== */
const mysql = require('mysql2/promise');

const {
    DB_HOST = '', DB_PORT = 3306, DB_USER = 'root',
    DB_PASSWORD = '', DB_NAME = 'fivem'
} = process.env;

let pool = null;
const enabled = !!DB_HOST;

if (enabled) {
    pool = mysql.createPool({
        host: DB_HOST, port: Number(DB_PORT), user: DB_USER,
        password: DB_PASSWORD, database: DB_NAME,
        waitForConnections: true, connectionLimit: 6, queueLimit: 0
    });
}

async function q(sql, params = []) {
    const [rows] = await pool.query(sql, params);
    return rows;
}

module.exports = {
    enabled,

    async ping() { if (!enabled) return false; try { await q('SELECT 1'); return true; } catch { return false; } },

    // ── bans ──
    bans: () => q('SELECT * FROM wireguard_bans ORDER BY id DESC LIMIT 500'),
    unban: (banId) => q('DELETE FROM wireguard_bans WHERE ban_id = ?', [banId]),
    addBan: ({ name, reason, by, license, discord, steam }) => {
        const banId = Math.random().toString(36).slice(2, 12).toUpperCase();
        return q(`INSERT INTO wireguard_bans (ban_id, name, reason, banned_by, license, discord, steam, identifiers)
                  VALUES (?,?,?,?,?,?,?,?)`,
            [banId, name || 'manual', reason || 'Manual ban (panel)', by || 'WebPanel',
             license || null, discord || null, steam || null,
             JSON.stringify({ license, discord, steam })]).then(() => banId);
    },

    // ── detection history ──
    history: (limit = 200, detection = '') => detection
        ? q('SELECT * FROM wireguard_detections WHERE detection = ? ORDER BY id DESC LIMIT ?', [detection, Number(limit)])
        : q('SELECT * FROM wireguard_detections ORDER BY id DESC LIMIT ?', [Number(limit)]),

    // ── admins ──
    admins: () => q('SELECT license, name, `rank`, added_by, created_at FROM wireguard_admins ORDER BY created_at DESC'),
    addAdmin: ({ license, name, rank, by }) =>
        q(`INSERT INTO wireguard_admins (license, name, \`rank\`, added_by) VALUES (?,?,?,?)
           ON DUPLICATE KEY UPDATE name=VALUES(name), \`rank\`=VALUES(\`rank\`)`,
            [license, name || null, rank || 'admin', by || 'WebPanel']),
    removeAdmin: (license) => q('DELETE FROM wireguard_admins WHERE license = ?', [license]),

    // ── whitelist (per-player, permanent) ──
    whitelist: () => q('SELECT license, name, added_by, created_at FROM wireguard_whitelist ORDER BY created_at DESC'),
    addWhitelist: ({ license, name, by }) =>
        q(`INSERT INTO wireguard_whitelist (license, name, added_by) VALUES (?,?,?)
           ON DUPLICATE KEY UPDATE name=VALUES(name)`, [license, name || null, by || 'Web-Panel']),
    removeWhitelist: (license) => q('DELETE FROM wireguard_whitelist WHERE license = ?', [license]),

    // ── logs ──
    logs: (limit = 200) => q('SELECT * FROM wireguard_logs ORDER BY id DESC LIMIT ?', [Number(limit)]),

    // ── analytics ──
    async analytics() {
        const [total]   = await q('SELECT COUNT(*) AS c FROM wireguard_detections');
        const [last24h] = await q('SELECT COUNT(*) AS c FROM wireguard_detections WHERE created_at > NOW() - INTERVAL 1 DAY');
        const [bans]    = await q('SELECT COUNT(*) AS c FROM wireguard_bans');
        const topTypes  = await q('SELECT detection, COUNT(*) AS c FROM wireguard_detections GROUP BY detection ORDER BY c DESC LIMIT 8');
        const perDay    = await q('SELECT DATE(created_at) AS d, COUNT(*) AS c FROM wireguard_detections WHERE created_at > NOW() - INTERVAL 14 DAY GROUP BY DATE(created_at) ORDER BY d');
        const topPlayers= await q('SELECT name, license, COUNT(*) AS c FROM wireguard_detections GROUP BY license, name ORDER BY c DESC LIMIT 8');
        return { total: total.c, last24h: last24h.c, totalBans: bans.c, topTypes, perDay, topPlayers };
    }
};
