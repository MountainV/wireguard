/* ============================================================
 * WireGuard - Web Admin Panel server
 * - LIVE data & actions  -> FiveM HTTP API (token)
 * - persistent data      -> MySQL directly (works offline)
 * - users & settings      -> file store (store.js, no DB needed)
 * ========================================================== */
require('dotenv').config();
const path    = require('path');
const express = require('express');
const session = require('express-session');
const db      = require('./db');
const store   = require('./store');

const {
    PORT = 8080,
    HOST = '0.0.0.0',
    PUBLIC_URL = '',
    FIVEM_API_URL = 'http://127.0.0.1:30120/wireguard',
    API_TOKEN = '',
    PANEL_USER = '',
    PANEL_PASSWORD = '',
    SESSION_SECRET = ''
} = process.env;

for (const [name, value] of Object.entries({ API_TOKEN, PANEL_USER, PANEL_PASSWORD, SESSION_SECRET })) {
    if (!value || value.startsWith('CHANGE_ME')) {
        throw new Error(`Set ${name} to a real value in web-panel/.env before starting the panel.`);
    }
}

// seed the first owner account from .env on first boot
store.users.seed(PANEL_USER, PANEL_PASSWORD);

const app = express();
app.use(express.json());
app.use(session({
    secret: SESSION_SECRET, resave: false, saveUninitialized: false,
    cookie: { maxAge: 1000 * 60 * 60 * 8 }
}));

function requireAuth(req, res, next) {
    if (req.session && req.session.user) return next();
    return res.status(401).json({ error: 'not authenticated' });
}
function requireRole(min) {
    return (req, res, next) => {
        if (!req.session || !req.session.user) return res.status(401).json({ error: 'not authenticated' });
        if (!store.roleAtLeast(req.session.role, min)) return res.status(403).json({ error: 'insufficient role' });
        next();
    };
}

// ── FiveM API helper ────────────────────────────────
async function fivem(pathPart, options = {}) {
    const url = `${FIVEM_API_URL.replace(/\/$/, '')}/${pathPart}`;
    const res = await fetch(url, {
        ...options,
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${API_TOKEN}`, ...(options.headers || {}) }
    });
    const text = await res.text();
    let body; try { body = JSON.parse(text); } catch { body = { raw: text }; }
    return { status: res.status, body };
}
const safeFivem = async (p, o) => { try { return await fivem(p, o); } catch { return { status: 502, body: { error: 'fivem offline' } }; } };

// ── auth routes ─────────────────────────────────────
app.post('/api/login', (req, res) => {
    const { username, password } = req.body || {};
    const u = store.users.verify(username, password);
    if (u) { req.session.user = u.username; req.session.role = u.role; return res.json({ ok: true, role: u.role }); }
    return res.status(401).json({ error: 'invalid credentials' });
});
app.post('/api/logout', (req, res) => req.session.destroy(() => res.json({ ok: true })));
app.get('/api/me', (req, res) => res.json({
    user: (req.session && req.session.user) || null,
    role: (req.session && req.session.role) || null,
    db: db.enabled
}));

// ── live data (FiveM API) ───────────────────────────
app.get('/api/stats',   requireAuth, async (_q, r) => { const x = await safeFivem('stats');   r.status(x.status).json(x.body); });
app.get('/api/players', requireAuth, async (_q, r) => { const x = await safeFivem('players'); r.status(x.status).json(x.body); });
app.get('/api/feed',    requireAuth, async (_q, r) => { const x = await safeFivem('feed');    r.status(x.status).json(x.body); });

// ── persistent data (DB first, else FiveM API) ──────
async function dbFirst(dbFn, apiPath, key, res) {
    if (db.enabled) {
        try { const rows = await dbFn(); return res.json({ [key]: rows, source: 'db' }); }
        catch (e) { /* fall through to api */ }
    }
    const x = await safeFivem(apiPath);
    return res.status(x.status).json({ ...x.body, source: 'api' });
}
app.get('/api/bans',      requireAuth, (_q, r) => dbFirst(() => db.bans(),      'bans',      'bans',      r));
app.get('/api/history',   requireAuth, (q, r)  => dbFirst(() => db.history(300, q.query.type || ''), 'history', 'history', r));
app.get('/api/admins',    requireAuth, (_q, r) => dbFirst(() => db.admins(),    'admins',    'admins',    r));
app.get('/api/logs',      requireAuth, (_q, r) => dbFirst(() => db.logs(300),   'logs',      'logs',      r));
app.get('/api/analytics', requireAuth, async (_q, r) => {
    if (db.enabled) { try { return r.json({ analytics: await db.analytics(), source: 'db' }); } catch {} }
    const x = await safeFivem('analytics'); return r.status(x.status).json({ ...x.body, source: 'api' });
});

// ── settings (editable from the dashboard) ──────────
// GET: defaults <- local store <- live FiveM config (if reachable)
app.get('/api/settings', requireAuth, async (_q, r) => {
    let merged = store.settings.get();
    let source = db.enabled ? 'store' : 'store';
    const live = await safeFivem('config');
    if (live.status === 200 && live.body && typeof live.body === 'object') {
        merged = store.deepMerge(merged, live.body);
        source = 'fivem';
    }
    r.json({ settings: merged, source });
});
// POST: persist locally + push live to the FiveM server (admin+)
app.post('/api/settings', requireRole('admin'), async (req, res) => {
    const patch = req.body || {};
    let saved;
    try { saved = store.settings.save(patch); } catch (e) { return res.status(500).json({ error: String(e) }); }
    const live = await safeFivem('settings', { method: 'POST', body: JSON.stringify(patch) });
    res.json({ ok: true, settings: saved, fivem: live.status === 200 ? 'applied' : 'offline' });
});

// ── whitelist (per-player, permanent — DB first) ────
app.get('/api/whitelist', requireAuth, (_q, r) => dbFirst(() => db.whitelist(), 'whitelist', 'whitelist', r));
app.post('/api/addwl', requireRole('moderator'), async (q, r) => {
    if (db.enabled) { try { await db.addWhitelist(q.body); await safeFivem('addwl', { method:'POST', body: JSON.stringify(q.body) }); return r.json({ ok: true, source: 'db' }); } catch (e) { return r.status(500).json({ error: String(e) }); } }
    const x = await safeFivem('addwl', { method:'POST', body: JSON.stringify(q.body) }); r.status(x.status).json(x.body);
});
app.post('/api/removewl', requireRole('moderator'), async (q, r) => {
    if (db.enabled) { try { await db.removeWhitelist(q.body.license); await safeFivem('removewl', { method:'POST', body: JSON.stringify(q.body) }); return r.json({ ok: true, source: 'db' }); } catch (e) { return r.status(500).json({ error: String(e) }); } }
    const x = await safeFivem('removewl', { method:'POST', body: JSON.stringify(q.body) }); r.status(x.status).json(x.body);
});

// ── user management (admin+) ────────────────────────
app.get('/api/users', requireRole('admin'), (_q, r) => r.json({ users: store.users.list(), roles: store.ROLES }));
app.post('/api/users', requireRole('admin'), (req, r) => {
    try { const u = store.users.add({ ...req.body, by: req.session.user }); r.json({ ok: true, user: u }); }
    catch (e) { r.status(400).json({ error: String(e.message || e) }); }
});
app.post('/api/users/password', requireRole('admin'), (req, r) => {
    try { store.users.setPassword(req.body.username, req.body.password); r.json({ ok: true }); }
    catch (e) { r.status(400).json({ error: String(e.message || e) }); }
});
app.post('/api/users/role', requireRole('owner'), (req, r) => {
    try { store.users.setRole(req.body.username, req.body.role); r.json({ ok: true }); }
    catch (e) { r.status(400).json({ error: String(e.message || e) }); }
});
app.post('/api/users/delete', requireRole('admin'), (req, r) => {
    if (String(req.body.username).toLowerCase() === String(req.session.user).toLowerCase())
        return r.status(400).json({ error: 'you cannot delete your own account' });
    try { store.users.remove(req.body.username); r.json({ ok: true }); }
    catch (e) { r.status(400).json({ error: String(e.message || e) }); }
});

// ── player actions (moderator+) ─────────────────────
app.post('/api/kick',   requireRole('moderator'), async (q, r) => { const x = await safeFivem('kick',   { method:'POST', body: JSON.stringify(q.body) }); r.status(x.status).json(x.body); });
app.post('/api/ban',    requireRole('moderator'), async (q, r) => { const x = await safeFivem('ban',    { method:'POST', body: JSON.stringify(q.body) }); r.status(x.status).json(x.body); });
app.post('/api/action', requireRole('moderator'), async (q, r) => { const x = await safeFivem('action', { method:'POST', body: JSON.stringify(q.body) }); r.status(x.status).json(x.body); });

// writes that work offline (DB) ------------------------
app.post('/api/unban', requireRole('moderator'), async (q, r) => {
    if (db.enabled) {
        try {
            const res = await db.unban(q.body.banId);
            if (res && res.affectedRows > 0) return r.json({ ok: true, source: 'db' });
            return r.status(404).json({ error: 'Ban nicht gefunden' });
        } catch (e) { return r.status(500).json({ error: String(e) }); }
    }
    const x = await safeFivem('unban', { method:'POST', body: JSON.stringify(q.body) }); r.status(x.status).json(x.body);
});
app.post('/api/addban', requireRole('moderator'), async (q, r) => {
    if (db.enabled) { try { const id = await db.addBan(q.body); return r.json({ ok: true, banId: id, source: 'db' }); } catch (e) { return r.status(500).json({ error: String(e) }); } }
    const x = await safeFivem('addban', { method:'POST', body: JSON.stringify(q.body) }); r.status(x.status).json(x.body);
});
app.post('/api/addadmin', requireRole('admin'), async (q, r) => {
    if (db.enabled) { try { await db.addAdmin(q.body); await safeFivem('addadmin', { method:'POST', body: JSON.stringify(q.body) }); return r.json({ ok: true }); } catch (e) { return r.status(500).json({ error: String(e) }); } }
    const x = await safeFivem('addadmin', { method:'POST', body: JSON.stringify(q.body) }); r.status(x.status).json(x.body);
});
app.post('/api/removeadmin', requireRole('admin'), async (q, r) => {
    if (db.enabled) { try { await db.removeAdmin(q.body.license); await safeFivem('removeadmin', { method:'POST', body: JSON.stringify(q.body) }); return r.json({ ok: true }); } catch (e) { return r.status(500).json({ error: String(e) }); } }
    const x = await safeFivem('removeadmin', { method:'POST', body: JSON.stringify(q.body) }); r.status(x.status).json(x.body);
});

app.use(express.static(path.join(__dirname, 'public')));

app.listen(PORT, HOST, async () => {
    console.log(`\n  🛡️  WireGuard Web Panel  →  ${PUBLIC_URL || `http://localhost:${PORT}`}`);
    console.log(`  Listening : ${HOST}:${PORT}`);
    console.log(`  FiveM API : ${FIVEM_API_URL}`);
    console.log(`  Users     : ${store.users.count()} account(s)`);
    if (db.enabled) {
        const ok = await db.ping();
        console.log(`  Database  : ${ok ? 'connected ✓' : 'CONFIGURED BUT UNREACHABLE ✗'} (${process.env.DB_NAME}@${process.env.DB_HOST})`);
    } else {
        console.log('  Database  : disabled (set DB_HOST in .env to enable)');
    }
});
