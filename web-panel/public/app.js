// ============================================================
// WireGuard Web Panel — frontend (live only, no demo data)
// ============================================================
let players = [], feedCache = [], histCache = [], pollTimer = null;
let dbOn = false, currentView = 'overview', myRole = 'viewer', myUser = 'Web-Panel', settingsCache = null;
const RANK = { owner:4, admin:3, moderator:2, viewer:1 };
const roleAtLeast = (min) => (RANK[myRole]||0) >= (RANK[min]||99);
function applyRole(){ document.querySelectorAll('.need-admin').forEach(el=>el.classList.toggle('hidden',!roleAtLeast('admin'))); }
const VIEW_TITLES={overview:'Übersicht',players:'Spieler',feed:'Detections',history:'Verlauf',bans:'Bans',admins:'Admins',whitelist:'Whitelist',analytics:'Statistiken',logs:'Logs',settings:'Einstellungen',users:'Benutzer'};
const SEV_DE={critical:'Kritisch',high:'Hoch',medium:'Mittel',low:'Niedrig'};
const ACT_DE={ban:'Bannen',kick:'Kicken',warn:'Verwarnen',none:'Keine',message:'Nachricht',heal:'Heilen',freeze:'Einfrieren',unfreeze:'Auftauen',kill:'Töten'};
const sevDE=s=>SEV_DE[s]||s||'—';
const actDE=a=>a?(ACT_DE[a]||a):'—';
function setIdentity(user,role){ myUser=user||myUser; const n=$('ucName'),rl=$('ucRole'),av=$('ucAv'); if(n)n.textContent=user||'—'; if(rl)rl.textContent=role||'—'; if(av)av.textContent=(user||'WG').slice(0,2).toUpperCase(); }

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s==null?'':s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

async function api(path, opts = {}) {
    try {
        const res = await fetch('api/' + path, { headers: { 'Content-Type':'application/json' }, ...opts });
        return { status: res.status, body: await res.json().catch(() => ({})) };
    } catch { return { status: 0, body: {} }; }
}
function toast(msg, type='') { const t=$('toast'); t.textContent=msg; t.className='toast '+type; clearTimeout(t._h); t._h=setTimeout(()=>t.classList.add('hidden'),3200); }
function setConn(ok){ const d=$('connDot'),t=$('connText'); d.className='dot '+(ok?'on':'off'); t.textContent=ok?'Server verbunden':'Server offline'; }
function setDb(ok){ const d=$('dbDot'),t=$('dbText'); d.className='dot '+(ok?'on':'off'); t.textContent='DB: '+(ok?'verbunden':'aus'); }

// ── auth ──
$('loginForm').addEventListener('submit', async (e)=>{ e.preventDefault();
    const r=await api('login',{method:'POST',body:JSON.stringify({username:$('user').value,password:$('pass').value})});
    if(r.status===200){ myRole=r.body.role||'viewer'; applyRole(); setIdentity($('user').value,myRole); showDash(); } else $('loginErr').classList.remove('hidden');
});
$('logout').addEventListener('click', async ()=>{ await api('logout',{method:'POST'}); stopPolling(); $('dash').classList.add('hidden'); $('login').classList.remove('hidden'); });
async function checkAuth(){ const r=await api('me'); dbOn=!!(r.body&&r.body.db); setDb(dbOn); myRole=(r.body&&r.body.role)||'viewer'; applyRole(); if(r.body&&r.body.user){ setIdentity(r.body.user,myRole); showDash(); } }
function showDash(){ $('login').classList.add('hidden'); $('dash').classList.remove('hidden'); refreshAll(); startPolling(); }

// ── navigation ──
document.querySelectorAll('.nav').forEach(n=>n.addEventListener('click',()=>{
    document.querySelectorAll('.nav').forEach(x=>x.classList.remove('active')); n.classList.add('active');
    currentView=n.dataset.view;
    const tb=$('tbTitle'); if(tb)tb.textContent=VIEW_TITLES[currentView]||'';
    document.querySelectorAll('.view').forEach(s=>s.classList.add('hidden'));
    const v=$('view-'+currentView); v.classList.remove('hidden'); v.style.animation='none'; void v.offsetWidth; v.style.animation='';
    if(currentView==='history') loadHistory();
    if(currentView==='bans') loadBans();
    if(currentView==='admins') loadAdmins();
    if(currentView==='analytics') loadAnalytics();
    if(currentView==='logs') loadLogs();
    if(currentView==='settings') loadSettings();
    if(currentView==='users') loadUsers();
    if(currentView==='whitelist') loadWhitelist();
}));

// ── count-up ──
function countTo(el,target){ const from=parseInt((el.textContent||'').replace(/\D/g,''))||0; if(from===target){el.textContent=target;return;}
    const dur=600,start=performance.now(); (function step(now){const p=Math.min((now-start)/dur,1);el.textContent=Math.round(from+(target-from)*(1-Math.pow(1-p,3)));if(p<1)requestAnimationFrame(step);})(performance.now()); }

// ── refresh ──
async function refreshAll(){ await Promise.all([loadStats(),loadPlayers(),loadFeed()]); drawSpark();
    if(currentView==='history')loadHistory(); if(currentView==='analytics')loadAnalytics(); }

async function loadStats(){ const r=await api('stats');
    if(r.status===200){ setConn(true); setDb(dbOn||!!r.body.database);
        $('st-name').textContent=r.body.serverName||'—'; countTo($('st-online'),r.body.online??0); countTo($('st-det'),r.body.detections??0); countTo($('st-bans'),r.body.bans??0);
    } else { setConn(false); $('st-name').textContent='—'; countTo($('st-online'),0); countTo($('st-det'),0); countTo($('st-bans'),0); }
}
async function loadPlayers(){ const r=await api('players'); players=(r.status===200)?(r.body.players||[]):[]; renderPlayers(); }
async function loadFeed(){ const r=await api('feed'); feedCache=(r.status===200)?(r.body.feed||[]):[]; renderFeed(feedCache,'feedFull'); renderFeed(feedCache.slice(0,7),'ov-feed'); }
async function loadHistory(){ const r=await api('history'); histCache=(r.status===200&&r.body.history)?r.body.history:[]; renderHistory(); }
async function loadBans(){ const r=await api('bans'); const bans=(r.status===200&&r.body.bans)?r.body.bans:[];
    $('bBody').innerHTML=bans.map((b,i)=>`<tr style="animation-delay:${i*.03}s"><td>${esc(b.ban_id||b.id)}</td><td>${esc(b.name)}</td><td>${esc(b.reason)}</td><td>${esc(b.bannedBy||b.banned_by)}</td><td>${fmtDate(b.time||b.created_at)}</td><td class="cell-sub">${esc((b.identifiers&&b.identifiers.license)||b.license||'—')}</td><td><button class="actbtn unban" data-id="${esc(b.ban_id||b.id)}">Entbannen</button></td></tr>`).join('')||'<tr><td colspan="7" class="empty">Keine Bans.</td></tr>';
    $('bBody').querySelectorAll('.unban').forEach(btn=>btn.addEventListener('click',async()=>{ const r=await api('unban',{method:'POST',body:JSON.stringify({banId:btn.dataset.id})}); if(r.status===200){toast('Entbannt','ok');loadBans();loadStats();}else toast('Fehler: '+(r.body.error||'Ban nicht gefunden'),'err'); }));
}
async function loadAdmins(){ const r=await api('admins'); const admins=(r.status===200&&r.body.admins)?r.body.admins:[];
    $('aBody').innerHTML=admins.map((a,i)=>`<tr style="animation-delay:${i*.03}s"><td class="cell-sub">${esc(a.license)}</td><td>${esc(a.name)}</td><td><span class="chip">${esc(a.rank)}</span></td><td>${esc(a.added_by)}</td><td>${fmtDate(a.created_at)}</td><td><button class="actbtn ban" data-lic="${esc(a.license)}">Entfernen</button></td></tr>`).join('')||'<tr><td colspan="6" class="empty">Keine Admins.</td></tr>';
    $('aBody').querySelectorAll('.ban').forEach(btn=>btn.addEventListener('click',async()=>{ const r=await api('removeadmin',{method:'POST',body:JSON.stringify({license:btn.dataset.lic})}); if(r.status===200){toast('Admin entfernt','ok');loadAdmins();}else toast('Fehler','err'); }));
}
async function loadLogs(){ const r=await api('logs'); const logs=(r.status===200&&r.body.logs)?r.body.logs:[];
    $('lBody').innerHTML=logs.map((l,i)=>`<tr style="animation-delay:${i*.03}s"><td>${fmtDate(l.created_at||l.time)}</td><td>${esc(l.admin)}</td><td><span class="chip">${esc(l.action)}</span></td><td>${esc(l.target)}</td><td class="cell-sub">${esc(l.detail)}</td></tr>`).join('')||'<tr><td colspan="5" class="empty">Keine Logs.</td></tr>';
}
let anaCache=null;
async function loadAnalytics(){ const r=await api('analytics'); const a=(r.status===200&&r.body.analytics)?r.body.analytics:{}; anaCache=a;
    const perDay=(a.perDay||[]).map(x=>({d:x.d,c:+x.c||0}));
    const avg = perDay.length ? Math.round(perDay.reduce((s,x)=>s+x.c,0)/perDay.length) : 0;
    countTo($('an-total'),a.total||0); countTo($('an-24h'),a.last24h||0); countTo($('an-bans'),a.totalBans||0); countTo($('an-avg'),avg);
    renderBars('an-types',(a.topTypes||[]).map(t=>({label:t.detection,count:t.c})));
    renderBars('an-players',(a.topPlayers||[]).map(t=>({label:t.name||'unbekannt',count:t.c})));
    drawAnaChart(perDay);
}
function drawAnaChart(perDay){ const cv=$('anChart'); if(!cv)return; const ctx=cv.getContext('2d');
    const w=cv.clientWidth||600, h=cv.height; cv.width=w; ctx.clearRect(0,0,w,h);
    const data=perDay||[];
    if(!data.length){ ctx.fillStyle='#8a8f98'; ctx.font='13px Inter,sans-serif'; ctx.textAlign='center'; ctx.fillText('Keine Daten im Zeitraum.',w/2,h/2); return; }
    const padT=20,padB=28,padL=10,padR=10, gap=Math.min(10,Math.max(4,w/data.length*0.25));
    const max=Math.max(1,...data.map(d=>d.c)); const bw=(w-padL-padR)/data.length;
    // gridlines
    ctx.strokeStyle='rgba(255,255,255,.06)'; ctx.lineWidth=1;
    for(let i=0;i<=3;i++){ const y=padT+(h-padT-padB)*i/3; ctx.beginPath(); ctx.moveTo(padL,y); ctx.lineTo(w-padR,y); ctx.stroke(); }
    data.forEach((d,i)=>{ const bh=(d.c/max)*(h-padT-padB); const x=padL+i*bw; const y=h-padB-(bh||0);
        const g=ctx.createLinearGradient(0,y,0,h-padB); g.addColorStop(0,'#f6b43b'); g.addColorStop(1,'rgba(246,169,59,.12)');
        ctx.fillStyle=g; rr(ctx,x+gap/2,y,Math.max(1,bw-gap),Math.max(1,bh),5); ctx.fill();
        if(d.c>0){ ctx.fillStyle='#f0cf8a'; ctx.font='600 11px Inter,sans-serif'; ctx.textAlign='center'; ctx.fillText(d.c,x+bw/2,y-6); }
        const dt=new Date(d.d); const lbl=isNaN(dt)?String(d.d).slice(5):(dt.getDate()+'.'+(dt.getMonth()+1));
        ctx.fillStyle='#8a8f98'; ctx.font='10px Inter,sans-serif'; ctx.textAlign='center'; ctx.fillText(lbl,x+bw/2,h-10);
    });
}

// ── render helpers ──
function trustInfo(value){
    if(value===null||value===undefined||value==='')return {score:null,className:'crit',label:'Unbekannt'};
    const raw=Number(value);
    if(!Number.isFinite(raw))return {score:null,className:'crit',label:'Unbekannt'};
    const score=Math.max(0,Math.min(100,raw));
    if(score>=80)return {score,className:'ok',label:'Stabil'};
    if(score>=50)return {score,className:'warn',label:'Beobachten'};
    if(score>=20)return {score,className:'bad',label:'Kritisch'};
    return {score,className:'crit',label:'Sehr kritisch'};
}
function fmtDate(v){ if(!v)return '—'; const d=(typeof v==='number')?new Date(v*1000):new Date(v); return isNaN(d)?esc(v):d.toLocaleString('de-DE'); }
function fmtTime(v){ const d=(typeof v==='number')?new Date(v*1000):new Date(v); return isNaN(d)?'':d.toLocaleTimeString('de-DE'); }

function renderPlayers(){ const q=$('pSearch').value.toLowerCase();
    const list=players.filter(p=>!q||p.name.toLowerCase().includes(q)||String(p.src).includes(q));
    $('pBody').innerHTML=list.map((p,i)=>{ const flags=Object.entries(p.flags||{}).map(([k,v])=>`<span class="chip">${esc(k)}·${v}</span>`).join('')||'<span class="chip">sauber</span>';
        const trust=trustInfo(p.trust);
        const trustDisplay=trust.score===null?'—':trust.score;
        const trustBar=trust.score===null?'':`<span style="width:${trust.score}%"></span>`;
        return `<tr style="animation-delay:${i*.03}s"><td>${p.src}</td><td>${esc(p.name)}${p.isAdmin?' 👑':''}</td><td><div class="trust-cell ${trust.className}" title="Trust-Score: ${trustDisplay} von 100. Sinkt bei aktivierten Detections um deren konfigurierte Strafe."><div class="trust-line"><span class="trust ${trust.className}">${trustDisplay}</span><small>${trust.label}</small></div><div class="trust-meter" aria-label="Trust-Score ${trustDisplay} von 100">${trustBar}</div></div></td><td>${flags}</td><td>${p.ping}ms</td>
        <td class="row-acts">
            <button class="actbtn heal" data-a="heal" data-id="${p.src}">Heilen</button>
            <button class="actbtn freeze" data-a="freeze" data-id="${p.src}">Einfrieren</button>
            <button class="actbtn msg" data-a="message" data-id="${p.src}">Nachricht</button>
            <button class="actbtn kick" data-a="kick" data-id="${p.src}">Kicken</button>
            <button class="actbtn ban" data-a="ban" data-id="${p.src}">Bannen</button>
        </td></tr>`; }).join('')||'<tr><td colspan="6" class="empty">Keine Spieler online.</td></tr>';
    $('pBody').querySelectorAll('.actbtn').forEach(btn=>btn.addEventListener('click',()=>playerAction(btn.dataset.a,parseInt(btn.dataset.id,10))));
}
async function playerAction(type,id){
    let reason=''; if(['ban','kick','warn','message'].includes(type)) reason=prompt(type==='message'?'Nachricht:':`${actDE(type)} – Grund:`,'')??'';
    let ep='action',payload={type,target:id,reason,by:myUser};
    if(type==='kick')ep='kick'; if(type==='ban')ep='ban';
    const r=await api(ep,{method:'POST',body:JSON.stringify(payload)});
    if(r.status===200){toast(`${actDE(type)} ausgeführt`,'ok'); setTimeout(refreshAll,400);} else toast(`Fehler: ${r.body.error||'Server offline'}`,'err');
}

function renderFeed(feed,elId){ $(elId).innerHTML=(feed||[]).map((f,i)=>`
    <div class="feed-item ${f.severity||'low'}" data-idx="${i}" style="animation-delay:${i*.04}s">
        <div class="fi-top"><span>${esc(f.detection)} — ${esc(f.name)} <span class="muted">(${f.src??''})</span></span><span class="fi-time">${fmtTime(f.time)}</span></div>
        <div class="fi-sub">${esc(f.detail||'')} ${f.action?'· '+esc(f.action):''}${f.screenshot?' · 📷':''}</div>
    </div>`).join('')||'<p class="empty">Noch keine Detections.</p>';
    $(elId).querySelectorAll('.feed-item').forEach(el=>el.addEventListener('click',()=>{ const arr=(elId==='ov-feed')?feedCache.slice(0,7):feedCache; openDetail(arr[+el.dataset.idx]); }));
}
function renderHistory(){ const q=($('hSearch').value||'').toLowerCase();
    const rows=histCache.filter(h=>!q||(h.detection||'').toLowerCase().includes(q)||(h.name||'').toLowerCase().includes(q));
    $('hBody').innerHTML=rows.map((h,i)=>`<tr style="animation-delay:${i*.02}s" data-idx="${i}"><td class="cell-sub">${fmtDate(h.created_at||h.time)}</td><td><b>${esc(h.detection)}</b></td><td>${esc(h.name)}</td><td><span class="sev ${h.severity||'low'}">${esc(sevDE(h.severity||'low'))}</span></td><td>${esc(actDE(h.action))}</td><td><button class="actbtn view">Details</button></td></tr>`).join('')||'<tr><td colspan="6" class="empty">Kein Verlauf (DB leer oder nicht verbunden).</td></tr>';
    $('hBody').querySelectorAll('tr[data-idx]').forEach(tr=>tr.addEventListener('click',()=>openDetail(rows[+tr.dataset.idx])));
}
function renderBars(elId,items){ const max=Math.max(1,...items.map(i=>i.count));
    $(elId).innerHTML=items.map(i=>`<div class="bar-row"><span class="bar-label">${esc(i.label)}</span><div class="bar-track"><div class="bar-fill" style="width:${(i.count/max*100)}%"></div></div><span class="bar-val">${i.count}</span></div>`).join('')||'<p class="empty">Keine Daten.</p>';
}

// ── detail modal (case info + screenshot) ──
function normCase(c){ return { detection:c.detection, name:c.name, license:c.license, detail:c.detail, severity:c.severity||'low',
    action:c.action, trust:c.trust, src:c.src, time:c.time||c.created_at,
    coords:c.coords||(c.pos_x!=null?{x:c.pos_x,y:c.pos_y,z:c.pos_z}:null), screenshot:c.screenshot||null }; }
function openDetail(raw){ if(!raw)return; const c=normCase(raw);
    const shot=c.screenshot?`<img src="${esc(c.screenshot)}" class="shot" onerror="this.parentNode.innerHTML='<div class=&quot;shot-none&quot;>Screenshot nicht ladbar</div>'"/>`:`<div class="shot-none">Kein Screenshot vorhanden<br><span class="muted">(screenshot-basic in config.lua aktivieren)</span></div>`;
    const pos=c.coords?`${c.coords.x?.toFixed?.(1)??c.coords.x}, ${c.coords.y?.toFixed?.(1)??c.coords.y}, ${c.coords.z?.toFixed?.(1)??c.coords.z}`:'—';
    $('modalInner').innerHTML=`
        <div class="modal-head"><div><span class="sev ${c.severity}">${esc(sevDE(c.severity))}</span><h3>${esc(c.detection)}</h3></div><button class="modal-x" onclick="closeModal()">✕</button></div>
        <div class="modal-grid">
            <div class="mg"><span>Spieler</span><b>${esc(c.name)} ${c.src!=null?`<span class="muted">(${c.src})</span>`:''}</b></div>
            <div class="mg"><span>Lizenz</span><b class="cell-sub">${esc(c.license||'—')}</b></div>
            <div class="mg"><span>Aktion</span><b>${esc(actDE(c.action))}</b></div>
            <div class="mg"><span>Trust-Score</span><b>${c.trust??'—'}</b></div>
            <div class="mg"><span>Zeitpunkt</span><b>${fmtDate(c.time)}</b></div>
            <div class="mg"><span>Position</span><b>${esc(pos)}</b></div>
            <div class="mg full"><span>Details</span><b>${esc(c.detail||'—')}</b></div>
        </div>
        <div class="shot-wrap"><div class="shot-title">📷 Beweis-Screenshot</div>${shot}</div>
        <div class="modal-foot">
            ${c.src!=null?`<button class="btn-primary sm" onclick="modalAction('ban',${c.src})">Spieler bannen</button><button class="actbtn kick" onclick="modalAction('kick',${c.src})">Kicken</button>`:''}
            <button class="actbtn" onclick="closeModal()">Schließen</button>
        </div>`;
    $('modal').classList.remove('hidden');
}
window.closeModal=()=>$('modal').classList.add('hidden');
window.modalAction=(type,id)=>{ closeModal(); playerAction(type,id); };
$('modal').addEventListener('click',e=>{ if(e.target.id==='modal')closeModal(); });
document.addEventListener('keyup',e=>{ if(e.key==='Escape')closeModal(); });

// ── add ban / add admin modals ──
$('addBanBtn').addEventListener('click',()=>{ $('modalInner').innerHTML=formHTML('Manueller Ban',[
    ['name','Name'],['license','Lizenz (license:...)'],['discord','Discord ID (optional)'],['reason','Grund']],'submitBan'); $('modal').classList.remove('hidden'); });
$('addAdminBtn').addEventListener('click',()=>{ $('modalInner').innerHTML=formHTML('Admin hinzufügen',[
    ['license','Lizenz (license:...)'],['name','Name'],['rank','Rang (z.B. admin / mod)']],'submitAdmin'); $('modal').classList.remove('hidden'); });
function formHTML(title,fields,fn){ return `<div class="modal-head"><h3>${title}</h3><button class="modal-x" onclick="closeModal()">✕</button></div>
    <div class="form">${fields.map(f=>`<label class="fl">${f[1]}<input id="f_${f[0]}" placeholder="${f[1]}"/></label>`).join('')}
    <button class="btn-primary" onclick="${fn}()">Speichern</button></div>`; }
window.submitBan=async()=>{ const b={name:$('f_name').value,license:$('f_license').value,discord:$('f_discord').value,reason:$('f_reason').value,by:myUser};
    if(!b.license&&!b.discord)return toast('Lizenz oder Discord nötig','err'); const r=await api('addban',{method:'POST',body:JSON.stringify(b)}); if(r.status===200){toast('Ban erstellt','ok');closeModal();loadBans();}else toast('Fehler: '+(r.body.error||''),'err'); };
window.submitAdmin=async()=>{ const a={license:$('f_license').value,name:$('f_name').value,rank:$('f_rank').value||'admin',by:myUser};
    if(!a.license)return toast('Lizenz nötig','err'); const r=await api('addadmin',{method:'POST',body:JSON.stringify(a)}); if(r.status===200){toast('Admin hinzugefügt','ok');closeModal();loadAdmins();}else toast('Fehler','err'); };

// ── sparkline ──
function drawSpark(){ const cv=$('spark'); if(!cv)return; const ctx=cv.getContext('2d'); const w=cv.clientWidth,h=cv.height; cv.width=w; ctx.clearRect(0,0,w,h);
    const col={critical:'#ff5d72',high:'#ff9d4d',medium:'#f5cb47',low:'#f6a93b'};
    const data=feedCache.slice(0,20).reverse(); if(!data.length)return; const bw=w/data.length;
    data.forEach((f,i)=>{ const s=f.severity||'low'; const bh={critical:1,high:.75,medium:.5,low:.3}[s]*(h-20); const x=i*bw+3,y=h-bh-4;
        const g=ctx.createLinearGradient(0,y,0,h); g.addColorStop(0,col[s]); g.addColorStop(1,col[s]+'22'); ctx.fillStyle=g; rr(ctx,x,y,bw-6,bh,4); ctx.fill(); }); }
function rr(c,x,y,w,h,r){ if(w<2*r)r=w/2; if(h<2*r)r=h/2; c.beginPath(); c.moveTo(x+r,y); c.arcTo(x+w,y,x+w,y+h,r); c.arcTo(x+w,y+h,x,y+h,r); c.arcTo(x,y+h,x,y,r); c.arcTo(x,y,x+w,y,r); c.closePath(); }
window.addEventListener('resize',drawSpark);
window.addEventListener('resize',()=>{ if(currentView==='analytics'&&anaCache) drawAnaChart((anaCache.perDay||[]).map(x=>({d:x.d,c:+x.c||0}))); });
$('pSearch').addEventListener('input',renderPlayers);
$('hSearch').addEventListener('input',renderHistory);

function startPolling(){ stopPolling(); pollTimer=setInterval(refreshAll,5000); }
function stopPolling(){ if(pollTimer)clearInterval(pollTimer); }

// ============================================================
//  SETTINGS  (everything configurable from the dashboard)
// ============================================================
const ACTIONS=['ban','kick','warn','none'];
const DET_INFO={
    Aimbot:'Automatisches Zielen auf Gegner (Aimbot).',
    Triggerbot:'Schießt automatisch, sobald das Fadenkreuz auf einem Spieler liegt.',
    ExplosiveAmmo:'Explosive Munition.',
    RapidFire:'Unmöglich schnelle Schussfolge.',
    GodMode:'Unverwundbarkeit, überhöhtes Leben oder Rüstung.',
    Invisible:'Spieler macht sich unsichtbar.',
    SuperJump:'Übermenschliche Sprunghöhe.',
    FastRun:'Zu schnelles Laufen.',
    FastSwim:'Zu schnelles Schwimmen.',
    NoClip:'Bewegen durch Wände / fliegen (NoClip).',
    SpeedHack:'Künstlich beschleunigte Bewegung.',
    Teleport:'Sofortiges Versetzen über große Distanz.',
    Ragdoll:'Ragdoll-Missbrauch.',
    SpawnVehicle:'Unerlaubtes Fahrzeug-Spawnen.',
    SpawnObject:'Unerlaubtes Objekt-Spawnen.',
    SpawnPed:'Unerlaubtes Ped-Spawnen.',
    SpawnLimit:'Zu viele Entities in kurzer Zeit (Flooding).',
    GiveWeapon:'Spieler gibt sich selbst eine Waffe.',
    BlacklistWeapon:'Verbotene Waffe in der Hand.',
    InfiniteAmmo:'Unendlich Munition.',
    WeaponDamageMod:'Veränderter Waffenschaden.',
    IllegalExplosion:'Verbotene / unmögliche Explosionsart.',
    EntitySpam:'Entity-Spam zum Lag-Erzeugen.',
    Blips:'Unerlaubte Karten-Blips.',
    ExtendedRadar:'Künstlich vergrößerter Radar.',
    NightVision:'Nachtsicht aktiviert.',
    ThermalVision:'Wärmesicht aktiviert.',
    ResourceStop:'Geschützte Resource wurde gestoppt.',
    ResourceStart:'Unerwartete Resource gestartet.',
    MenuInject:'Mod-Menü-Injection erkannt.',
    LuaExecutor:'Lua-Executor / Script-Injection.',
    Spectate:'Spieler beobachtet heimlich andere.',
    BlacklistCommand:'Verbotener Konsolenbefehl ausgeführt.',
    PlayerBlips:'ESP: zeigt alle Spieler auf der Karte.',
    VehicleGodMode:'Unzerstörbares / selbstreparierendes Fahrzeug.',
    VehicleSpeedHack:'Fahrzeug schneller als physikalisch möglich.',
    PlayerModel:'Verbotenes oder Tier-Spielermodell (Model-Swap).',
    InvincibleFlag:'Native Unverwundbarkeits-Flag gesetzt.',
    NoRagdoll:'Ragdoll dauerhaft deaktiviert.',
    WeaponClipMod:'Vergrößertes Magazin (Clip-Modifikation).'
};
function sw(path,val){ return `<label class="switch"><input type="checkbox" data-k="${path}" data-t="bool" ${val?'checked':''}><span class="slider"></span></label>`; }
function inp(path,val,type){ return `<input class="sin" data-k="${path}" data-t="${type==='number'?'num':'str'}" type="${type||'text'}" value="${esc(val)}">`; }
function sel(path,val){ return `<select class="sin" data-k="${path}" data-t="str">${ACTIONS.map(a=>`<option value="${a}" ${a===val?'selected':''}>${actDE(a)}</option>`).join('')}</select>`; }
function frow(label,control){ return `<div class="srow"><span class="slabel">${label}</span>${control}</div>`; }

async function loadSettings(){
    const r=await api('settings');
    const s=(r.status===200&&r.body.settings)?r.body.settings:null;
    $('setSource').textContent = (r.body&&r.body.source==='fivem')?'live vom Server':'gespeichert (Server offline)';
    if(!s){ $('setBody').innerHTML='<div class="panel"><p class="empty">Einstellungen konnten nicht geladen werden.</p></div>'; return; }
    settingsCache=s;
    const g=s.general||{}, t=s.TrustScore||{}, th=s.Thresholds||{}, d=s.Discord||{}, sc=s.Screenshots||{}, wl=s.Whitelist||{};
    const det=s.Detections||{};
    $('setBody').innerHTML=`
    <div class="set-grid">
      <div class="panel"><div class="panel-head"><h3>Allgemein</h3></div>
        ${frow('Servername',inp('general.ServerName',g.ServerName,'text'))}
        ${frow('Standard-Aktion',sel('general.DefaultAction',g.DefaultAction))}
        ${frow('Kick-Nachricht',inp('general.KickMessage',g.KickMessage,'text'))}
        ${frow('Ban-Nachricht',inp('general.BanMessage',g.BanMessage,'text'))}
        ${frow('Menü-Taste (Keycode)',inp('general.MenuKey',g.MenuKey,'number'))}
        ${frow('Ban-Schonzeit nach Join (Sek.)',inp('general.JoinGracePeriod',g.JoinGracePeriod,'number'))}
        ${frow('Debug-Modus',sw('general.Debug',g.Debug))}
      </div>
      <div class="panel"><div class="panel-head"><h3>Trust-Score</h3></div>
        <p class="setting-help">Jeder Spieler startet mit dem Startwert. Eine Detection zieht ihre konfigurierte Strafe ab. Erreicht der Score den Ban-Schwellenwert, wird gebannt. Eine Detection mit eigener Aktion „Bannen“ kann unabhängig davon sofort bannen. Der Score ist keine Wahrscheinlichkeit und kein Beweis.</p>
        ${frow('Aktiviert',sw('TrustScore.Enabled',t.Enabled))}
        ${frow('Startwert',inp('TrustScore.Start',t.Start,'number'))}
        ${frow('Ban unter',inp('TrustScore.BanBelow',t.BanBelow,'number'))}
      </div>
      <div class="panel"><div class="panel-head"><h3>Schwellenwerte</h3></div>
        ${frow('Max. Laufgeschw. (m/s)',inp('Thresholds.MaxRunSpeed',th.MaxRunSpeed,'number'))}
        ${frow('Max. Schwimmgeschw.',inp('Thresholds.MaxSwimSpeed',th.MaxSwimSpeed,'number'))}
        ${frow('Max. Geschw. zu Fuß',inp('Thresholds.MaxOnFootSpeed',th.MaxOnFootSpeed,'number'))}
        ${frow('Teleport-Distanz (m)',inp('Thresholds.TeleportDistance',th.TeleportDistance,'number'))}
        ${frow('Max. Entities/Sek.',inp('Thresholds.MaxEntitiesPerSec',th.MaxEntitiesPerSec,'number'))}
        ${frow('Max. Leben',inp('Thresholds.MaxHealth',th.MaxHealth,'number'))}
        ${frow('Max. Rüstung',inp('Thresholds.MaxArmour',th.MaxArmour,'number'))}
        ${frow('Min. Schussintervall (ms)',inp('Thresholds.MinShotIntervalMs',th.MinShotIntervalMs,'number'))}
      </div>
      <div class="panel"><div class="panel-head"><h3>Discord-Logging</h3></div>
        ${frow('Aktiviert',sw('Discord.Enabled',d.Enabled))}
        ${frow('Webhook (Detections)',inp('Discord.Webhook',d.Webhook,'text'))}
        ${frow('Webhook (Bans)',inp('Discord.BanWebhook',d.BanWebhook,'text'))}
        ${frow('Bot-Name',inp('Discord.BotName',d.BotName,'text'))}
      </div>
      <div class="panel"><div class="panel-head"><h3>Screenshots</h3></div>
        ${frow('Aktiviert',sw('Screenshots.Enabled',sc.Enabled))}
        ${frow('Bei Detection',sw('Screenshots.OnDetection',sc.OnDetection))}
        ${frow('Webhook',inp('Screenshots.Webhook',sc.Webhook,'text'))}
        ${frow('Qualität (0–1)',inp('Screenshots.Quality',sc.Quality,'number'))}
      </div>
      <div class="panel"><div class="panel-head"><h3>Whitelist</h3></div>
        ${frow('Aktiviert',sw('Whitelist.Enabled',wl.Enabled))}
        ${frow('ACE-Rechte prüfen',sw('Whitelist.CheckAce',wl.CheckAce))}
      </div>
    </div>
    <div class="panel no-pad" style="margin-top:16px">
      <div class="panel-head" style="padding:18px 20px 0"><h3>Detections</h3><span class="hint">An/Aus · Aktion · Strafe</span></div>
      <table class="tbl det-tbl"><thead><tr><th>Detection</th><th>Aktiv</th><th>Aktion</th><th>Strafe</th></tr></thead><tbody>
      ${Object.keys(det).map(name=>{const c=det[name]||{};return `<tr><td><b>${esc(name)}</b><div class="cell-sub">${esc(DET_INFO[name]||'')}</div></td><td>${sw('Detections.'+name+'.enabled',c.enabled)}</td><td>${sel('Detections.'+name+'.action',c.action)}</td><td style="width:120px">${inp('Detections.'+name+'.penalty',c.penalty,'number')}</td></tr>`;}).join('')}
      </tbody></table>
    </div>`;
}
function collectSettings(){
    const out={};
    $('setBody').querySelectorAll('[data-k]').forEach(el=>{
        const parts=el.dataset.k.split('.'); const t=el.dataset.t;
        let val = t==='bool'?el.checked : t==='num'?Number(el.value) : el.value;
        if(t==='num'&&Number.isNaN(val)) val=0;
        let o=out; for(let i=0;i<parts.length-1;i++){ o[parts[i]]=o[parts[i]]||{}; o=o[parts[i]]; }
        o[parts[parts.length-1]]=val;
    });
    return out;
}
$('saveSettings').addEventListener('click',async()=>{
    if(!roleAtLeast('admin'))return toast('Keine Berechtigung','err');
    const patch=collectSettings();
    const r=await api('settings',{method:'POST',body:JSON.stringify(patch)});
    if(r.status===200){ toast('Gespeichert · '+(r.body.fivem==='applied'?'live angewendet':'Server offline, lokal gespeichert'),'ok'); loadSettings(); }
    else toast('Fehler: '+(r.body.error||'keine Berechtigung'),'err');
});

// ============================================================
//  USERS
// ============================================================
async function loadUsers(){
    const r=await api('users'); const list=(r.status===200&&r.body.users)?r.body.users:[];
    const roles=(r.body&&r.body.roles)||['owner','admin','moderator','viewer'];
    $('uBody').innerHTML=list.map((u,i)=>`<tr style="animation-delay:${i*.03}s">
        <td><b>${esc(u.username)}</b></td>
        <td><span class="chip role-${esc(u.role)}">${esc(u.role)}</span></td>
        <td class="cell-sub">${esc(u.createdBy||'—')}</td>
        <td class="cell-sub">${fmtDate(u.createdAt)}</td>
        <td class="row-acts">
            <button class="actbtn" data-pw="${esc(u.username)}">Passwort</button>
            <button class="actbtn ban" data-del="${esc(u.username)}">Löschen</button>
        </td></tr>`).join('')||'<tr><td colspan="5" class="empty">Keine Benutzer.</td></tr>';
    $('uBody').querySelectorAll('[data-del]').forEach(b=>b.addEventListener('click',async()=>{
        if(!confirm('Benutzer "'+b.dataset.del+'" wirklich löschen?'))return;
        const r=await api('users/delete',{method:'POST',body:JSON.stringify({username:b.dataset.del})});
        if(r.status===200){toast('Benutzer gelöscht','ok');loadUsers();}else toast('Fehler: '+(r.body.error||''),'err');
    }));
    $('uBody').querySelectorAll('[data-pw]').forEach(b=>b.addEventListener('click',async()=>{
        const pw=prompt('Neues Passwort für "'+b.dataset.pw+'":'); if(!pw)return;
        const r=await api('users/password',{method:'POST',body:JSON.stringify({username:b.dataset.pw,password:pw})});
        if(r.status===200)toast('Passwort geändert','ok');else toast('Fehler: '+(r.body.error||''),'err');
    }));
    window._roles=roles;
}
$('addUserBtn').addEventListener('click',()=>{
    const roles=window._roles||['admin','moderator','viewer'];
    $('modalInner').innerHTML=`<div class="modal-head"><h3>Benutzer hinzufügen</h3><button class="modal-x" onclick="closeModal()">✕</button></div>
    <div class="form">
      <label class="fl">Benutzername<input id="f_uname" placeholder="z.B. max"/></label>
      <label class="fl">Passwort<input id="f_upass" type="password" placeholder="Passwort"/></label>
      <label class="fl">Rolle<select id="f_urole" class="sin">${roles.filter(r=>r!=='owner').map(r=>`<option value="${r}">${r}</option>`).join('')}</select></label>
      <button class="btn-primary" onclick="submitUser()">Erstellen</button>
    </div>`;
    $('modal').classList.remove('hidden');
});
window.submitUser=async()=>{
    const b={username:$('f_uname').value,password:$('f_upass').value,role:$('f_urole').value};
    if(!b.username||!b.password)return toast('Benutzername & Passwort nötig','err');
    const r=await api('users',{method:'POST',body:JSON.stringify(b)});
    if(r.status===200){toast('Benutzer erstellt','ok');closeModal();loadUsers();}else toast('Fehler: '+(r.body.error||''),'err');
};

// ============================================================
//  WHITELIST  (permanent, DB)
// ============================================================
async function loadWhitelist(){
    const r=await api('whitelist'); const list=(r.status===200&&r.body.whitelist)?r.body.whitelist:[];
    $('wlBody').innerHTML=list.map((w,i)=>`<tr style="animation-delay:${i*.03}s">
        <td class="cell-sub">${esc(w.license)}</td>
        <td>${esc(w.name||'—')}</td>
        <td class="cell-sub">${esc(w.added_by||'—')}</td>
        <td class="cell-sub">${fmtDate(w.created_at)}</td>
        <td><button class="actbtn ban" data-wl="${esc(w.license)}">Entfernen</button></td></tr>`).join('')
        ||'<tr><td colspan="5" class="empty">Keine Spieler auf der Whitelist.</td></tr>';
    $('wlBody').querySelectorAll('[data-wl]').forEach(b=>b.addEventListener('click',async()=>{
        const r=await api('removewl',{method:'POST',body:JSON.stringify({license:b.dataset.wl})});
        if(r.status===200){toast('Von Whitelist entfernt','ok');loadWhitelist();}else toast('Fehler: '+(r.body.error||''),'err');
    }));
}
$('addWlBtn').addEventListener('click',()=>{
    $('modalInner').innerHTML=`<div class="modal-head"><h3>Spieler whitelisten</h3><button class="modal-x" onclick="closeModal()">✕</button></div>
    <div class="form">
      <label class="fl">Lizenz <small style="font-weight:400">(license:xxxx…)</small><input id="f_wllic" placeholder="license:0000000000000000"/></label>
      <label class="fl">Name (optional)<input id="f_wlname" placeholder="Spielername"/></label>
      <button class="btn-primary" onclick="submitWl()">Zur Whitelist hinzufügen</button>
    </div>`;
    $('modal').classList.remove('hidden');
});
window.submitWl=async()=>{
    const b={license:$('f_wllic').value.trim(),name:$('f_wlname').value.trim(),by:myUser};
    if(!b.license)return toast('Lizenz nötig','err');
    const r=await api('addwl',{method:'POST',body:JSON.stringify(b)});
    if(r.status===200){toast('Spieler gewhitelistet','ok');closeModal();loadWhitelist();}else toast('Fehler: '+(r.body.error||''),'err');
};

checkAuth();
