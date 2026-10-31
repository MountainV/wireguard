/* ============================================================
 * WireGuard Web Panel — file-backed store (users + settings)
 * No database required. Everything persists to web-panel/data/*.json
 * Passwords are salted + scrypt-hashed (never stored in plain text).
 * ========================================================== */
const fs     = require('fs');
const path   = require('path');
const crypto = require('crypto');

const DATA_DIR = path.join(__dirname, 'data');
const USERS_F  = path.join(DATA_DIR, 'users.json');
const SET_F    = path.join(DATA_DIR, 'settings.json');

function ensureDir() { if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true }); }
function readJson(f, fallback) { try { return JSON.parse(fs.readFileSync(f, 'utf8')); } catch { return fallback; } }
function writeJson(f, obj) { ensureDir(); fs.writeFileSync(f, JSON.stringify(obj, null, 2)); }

// ── password hashing ────────────────────────────────
function makeHash(password, salt) {
    salt = salt || crypto.randomBytes(16).toString('hex');
    const hash = crypto.scryptSync(String(password), salt, 64).toString('hex');
    return { salt, hash };
}
function verifyHash(password, salt, hash) {
    try {
        const cand = crypto.scryptSync(String(password), salt, 64).toString('hex');
        return crypto.timingSafeEqual(Buffer.from(cand, 'hex'), Buffer.from(hash, 'hex'));
    } catch { return false; }
}

// ── roles ───────────────────────────────────────────
const ROLES = ['owner', 'admin', 'moderator', 'viewer'];
const RANK  = { owner: 4, admin: 3, moderator: 2, viewer: 1 };
function roleAtLeast(role, min) { return (RANK[role] || 0) >= (RANK[min] || 99); }

// ── users ───────────────────────────────────────────
function allUsers() { return readJson(USERS_F, []); }
function saveUsers(u) { writeJson(USERS_F, u); }

const users = {
    count: () => allUsers().length,
    list: () => allUsers().map(u => ({ username: u.username, role: u.role, createdAt: u.createdAt, createdBy: u.createdBy })),
    find: (username) => allUsers().find(u => u.username.toLowerCase() === String(username || '').toLowerCase()),

    verify(username, password) {
        const u = this.find(username);
        if (!u) return null;
        return verifyHash(password, u.salt, u.hash) ? { username: u.username, role: u.role } : null;
    },

    add({ username, password, role, by }) {
        username = String(username || '').trim();
        if (!username || !password) throw new Error('username and password required');
        if (!ROLES.includes(role)) role = 'moderator';
        const list = allUsers();
        if (list.some(u => u.username.toLowerCase() === username.toLowerCase())) throw new Error('user already exists');
        const { salt, hash } = makeHash(password);
        list.push({ username, salt, hash, role, createdAt: Date.now(), createdBy: by || 'system' });
        saveUsers(list);
        return { username, role };
    },

    setPassword(username, password) {
        const list = allUsers();
        const u = list.find(x => x.username.toLowerCase() === String(username).toLowerCase());
        if (!u) throw new Error('user not found');
        const { salt, hash } = makeHash(password);
        u.salt = salt; u.hash = hash;
        saveUsers(list);
    },

    setRole(username, role) {
        if (!ROLES.includes(role)) throw new Error('invalid role');
        const list = allUsers();
        const u = list.find(x => x.username.toLowerCase() === String(username).toLowerCase());
        if (!u) throw new Error('user not found');
        u.role = role;
        saveUsers(list);
    },

    remove(username) {
        const list = allUsers();
        const u = list.find(x => x.username.toLowerCase() === String(username).toLowerCase());
        if (!u) throw new Error('user not found');
        if (u.role === 'owner' && list.filter(x => x.role === 'owner').length <= 1)
            throw new Error('cannot delete the last owner');
        saveUsers(list.filter(x => x !== u));
    },

    // seed the first owner from .env on first boot
    seed(username, password) {
        if (allUsers().length > 0) return;
        if (!username || !password) return;
        const { salt, hash } = makeHash(password);
        saveUsers([{ username, salt, hash, role: 'owner', createdAt: Date.now(), createdBy: '.env' }]);
        console.log(`  Users     : seeded owner "${username}" from .env`);
    }
};

// ── settings ────────────────────────────────────────
// Editable subset of the FiveM Config. Defaults mirror config.lua so the
// settings page always has a full form even before the server connects.
const SETTINGS_DEFAULTS = {
    general: {
        ServerName: 'MountainV',
        DefaultAction: 'ban',
        KickMessage: '🛡️ MountainV Anticheat\nDu wurdest vom Server entfernt.\nBei Fragen wende dich an unser Support-Team.',
        BanMessage: '🛡️ MountainV Anticheat\n\nDu wurdest dauerhaft von MountainV gesperrt.\n\nBan-ID: %s\n\nSolltest du der Meinung sein, dass dies ein Fehler ist, eröffne mit deiner Ban-ID ein Ticket in unserem Discord.',
        Debug: false,
        MenuKey: 167,
        JoinGracePeriod: 45
    },
    TrustScore: { Enabled: true, Start: 100, BanBelow: 0 },
    Thresholds: {
        MaxRunSpeed: 10.0, MaxSwimSpeed: 4.5, MaxOnFootSpeed: 12.0, TeleportDistance: 75.0,
        MaxEntitiesPerSec: 8, MaxHealth: 200, MaxArmour: 100, MinShotIntervalMs: 40
    },
    Discord:     { Enabled: false, Webhook: '', BanWebhook: '', BotName: 'WireGuard', Color: 15158332 },
    Screenshots: { Enabled: false, OnDetection: true, Webhook: '', Quality: 0.85 },
    Whitelist:   { Enabled: true, CheckAce: true },
    Detections: {
        Aimbot:{enabled:true,action:'ban',penalty:100}, Triggerbot:{enabled:true,action:'ban',penalty:100},
        ExplosiveAmmo:{enabled:true,action:'ban',penalty:100}, RapidFire:{enabled:true,action:'kick',penalty:50},
        GodMode:{enabled:true,action:'ban',penalty:100}, Invisible:{enabled:true,action:'kick',penalty:60},
        SuperJump:{enabled:true,action:'kick',penalty:40}, FastRun:{enabled:true,action:'kick',penalty:40},
        FastSwim:{enabled:true,action:'kick',penalty:40}, NoClip:{enabled:true,action:'ban',penalty:100},
        SpeedHack:{enabled:true,action:'kick',penalty:60}, Teleport:{enabled:true,action:'kick',penalty:70},
        Ragdoll:{enabled:false,action:'warn',penalty:20}, SpawnVehicle:{enabled:true,action:'kick',penalty:60},
        SpawnObject:{enabled:true,action:'kick',penalty:60}, SpawnPed:{enabled:true,action:'kick',penalty:60},
        SpawnLimit:{enabled:true,action:'kick',penalty:40}, GiveWeapon:{enabled:true,action:'ban',penalty:100},
        BlacklistWeapon:{enabled:true,action:'kick',penalty:80}, InfiniteAmmo:{enabled:true,action:'kick',penalty:50},
        WeaponDamageMod:{enabled:true,action:'ban',penalty:100}, IllegalExplosion:{enabled:true,action:'ban',penalty:100},
        EntitySpam:{enabled:true,action:'kick',penalty:50}, Blips:{enabled:false,action:'warn',penalty:10},
        ExtendedRadar:{enabled:true,action:'warn',penalty:20}, NightVision:{enabled:false,action:'warn',penalty:10},
        ThermalVision:{enabled:false,action:'warn',penalty:10}, ResourceStop:{enabled:true,action:'ban',penalty:100},
        ResourceStart:{enabled:true,action:'ban',penalty:100}, MenuInject:{enabled:true,action:'ban',penalty:100},
        LuaExecutor:{enabled:true,action:'ban',penalty:100}, Spectate:{enabled:false,action:'warn',penalty:20},
        BlacklistCommand:{enabled:true,action:'kick',penalty:40}, PlayerBlips:{enabled:false,action:'warn',penalty:10},
        VehicleGodMode:{enabled:true,action:'kick',penalty:60}, VehicleSpeedHack:{enabled:true,action:'kick',penalty:60},
        PlayerModel:{enabled:true,action:'kick',penalty:50}, InvincibleFlag:{enabled:true,action:'ban',penalty:100},
        NoRagdoll:{enabled:false,action:'warn',penalty:20}, WeaponClipMod:{enabled:true,action:'kick',penalty:60}
    }
};

function deepMerge(target, patch) {
    for (const k of Object.keys(patch || {})) {
        if (patch[k] && typeof patch[k] === 'object' && !Array.isArray(patch[k]) && typeof target[k] === 'object') {
            deepMerge(target[k], patch[k]);
        } else {
            target[k] = patch[k];
        }
    }
    return target;
}

const settings = {
    defaults: () => JSON.parse(JSON.stringify(SETTINGS_DEFAULTS)),
    get() { return deepMerge(this.defaults(), readJson(SET_F, {})); },
    save(patch) {
        const merged = deepMerge(this.get(), patch || {});
        writeJson(SET_F, merged);
        return merged;
    }
};

module.exports = { users, settings, roleAtLeast, ROLES, deepMerge };
