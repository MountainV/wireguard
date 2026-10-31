// WireGuard - NUI admin menu logic
const app      = document.getElementById('app');
const rows     = document.getElementById('playerRows');
const feedList = document.getElementById('feedList');
const search   = document.getElementById('search');
const count    = document.getElementById('count');
const modal    = document.getElementById('modal');

let players = [];
let pending = null; // { type, target, name }

const RES = (() => {
    try { return window.GetParentResourceName ? GetParentResourceName() : 'wireguard'; }
    catch (e) { return 'wireguard'; }
})();

function post(cb, data = {}) {
    return fetch(`https://${RES}/${cb}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    }).catch(() => {});
}

// ── tabs ───────────────────────────────────────────
document.querySelectorAll('.tab').forEach(t => {
    t.addEventListener('click', () => {
        document.querySelectorAll('.tab').forEach(x => x.classList.remove('active'));
        t.classList.add('active');
        const name = t.dataset.tab;
        document.getElementById('tab-players').classList.toggle('hidden', name !== 'players');
        document.getElementById('tab-feed').classList.toggle('hidden', name !== 'feed');
    });
});

// ── trust colour ───────────────────────────────────
function trustInfo(value) {
    if (value === null || value === undefined || value === '') return { score: null, className: 'crit', label: 'Unknown' };
    const raw = Number(value);
    if (!Number.isFinite(raw)) return { score: null, className: 'crit', label: 'Unknown' };
    const score = Math.max(0, Math.min(100, raw));
    if (score >= 80) return { score, className: 'ok', label: 'Stable' };
    if (score >= 50) return { score, className: 'warn', label: 'Watch' };
    if (score >= 20) return { score, className: 'bad', label: 'Critical' };
    return { score, className: 'crit', label: 'Very critical' };
}

// ── render players ─────────────────────────────────
function renderPlayers() {
    const q = search.value.toLowerCase();
    const filtered = players.filter(p => !q || p.name.toLowerCase().includes(q) || String(p.src).includes(q));
    count.textContent = `${players.length} online`;
    rows.innerHTML = filtered.map(p => {
        const flags = Object.entries(p.flags || {})
            .map(([k, v]) => `<span class="flag-chip">${k}:${v}</span>`).join('') || '<span class="flag-chip">clean</span>';
        const trust = trustInfo(p.trust);
        const trustDisplay = trust.score === null ? '—' : trust.score;
        const trustBar = trust.score === null ? '' : `<span style="width:${trust.score}%"></span>`;
        return `<tr>
            <td>${p.src}</td>
            <td>${escapeHtml(p.name)}${p.isAdmin ? ' 👑' : ''}</td>
            <td><div class="trust-cell ${trust.className}" title="Trust score: ${trustDisplay} of 100. Active detections subtract their configured penalty."><div class="trust-line"><span class="trust ${trust.className}">${trustDisplay}</span><small>${trust.label}</small></div><div class="trust-meter" aria-label="Trust score ${trustDisplay} of 100">${trustBar}</div></div></td>
            <td>${flags}</td>
            <td>${p.ping}ms</td>
            <td class="row-actions">
                <button class="spec" data-a="spectate" data-id="${p.src}">Spectate</button>
                <button class="tp"   data-a="tp"       data-id="${p.src}">TP</button>
                <button class="warn" data-a="warn"     data-id="${p.src}">Warn</button>
                <button class="kick" data-a="kick"     data-id="${p.src}">Kick</button>
                <button class="ban"  data-a="ban"      data-id="${p.src}">Ban</button>
            </td>
        </tr>`;
    }).join('');

    rows.querySelectorAll('button').forEach(b => {
        b.addEventListener('click', () => {
            const type = b.dataset.a;
            const id   = parseInt(b.dataset.id, 10);
            const pl   = players.find(p => p.src === id);
            if (type === 'spectate' || type === 'tp') {
                post('action', { type, target: id, reason: '' });
                return;
            }
            openModal(type, id, pl ? pl.name : ('ID ' + id));
        });
    });
}

function renderFeed(feed) {
    feedList.innerHTML = (feed || []).map(f => `
        <div class="feed-item ${f.severity || 'low'}">
            <div class="fi-top">
                <span class="fi-det">${escapeHtml(f.detection)} — ${escapeHtml(f.name)} (${f.src})</span>
                <span class="fi-time">${new Date(f.time * 1000).toLocaleTimeString()}</span>
            </div>
            <div class="fi-sub">${escapeHtml(f.detail || '')} ${f.action ? '· action: ' + f.action : ''}</div>
        </div>`).join('') || '<p style="color:var(--muted)">No detections yet.</p>';
}

// ── modal ──────────────────────────────────────────
function openModal(type, target, name) {
    pending = { type, target, name };
    document.getElementById('modalTitle').textContent = type.toUpperCase() + ' player';
    document.getElementById('modalSub').textContent = `${name} (ID ${target})`;
    document.getElementById('reasonInput').value = '';
    modal.classList.remove('hidden');
}
document.getElementById('modalCancel').addEventListener('click', () => modal.classList.add('hidden'));
document.getElementById('modalConfirm').addEventListener('click', () => {
    if (pending) {
        post('action', { type: pending.type, target: pending.target,
            reason: document.getElementById('reasonInput').value });
    }
    modal.classList.add('hidden');
    pending = null;
    setTimeout(() => post('refresh'), 400);
});

// ── controls ───────────────────────────────────────
search.addEventListener('input', renderPlayers);
document.getElementById('refreshBtn').addEventListener('click', () => post('refresh'));
document.getElementById('closeBtn').addEventListener('click', close);

function close() { app.classList.add('hidden'); post('close'); }

document.addEventListener('keyup', e => { if (e.key === 'Escape') close(); });

// ── NUI message bus ────────────────────────────────
window.addEventListener('message', e => {
    const msg = e.data;
    if (msg.action === 'open') {
        app.classList.remove('hidden');
        if (msg.serverName) document.getElementById('serverName').textContent = msg.serverName;
    } else if (msg.action === 'close') {
        app.classList.add('hidden');
    } else if (msg.action === 'data') {
        players = msg.payload.players || [];
        renderPlayers();
        renderFeed(msg.payload.feed);
    }
});

function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, c =>
        ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]));
}
