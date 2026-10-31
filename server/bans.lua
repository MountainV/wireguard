--[[ ============================================================
     WireGuard - Ban system
     Backend: MySQL (oxmysql) when Config.Database.Enabled & ready,
     otherwise JSON file (data/bans.json). Same public API either way.
     Ban-evasion hardened: matches on ANY identifier + hardware tokens.
     ============================================================ ]]

WG = WG or {}
WG.Bans = {}

local BAN_FILE = 'data/bans.json'
local bans = {}   -- JSON cache (only used when DB off)

local function usingDB() return WG.DB and WG.DB.ready end

-- ── JSON persistence ────────────────────────────────
local function loadJson()
    local raw = LoadResourceFile(GetCurrentResourceName(), BAN_FILE)
    bans = WG.jsonDecode(raw, {})
    if type(bans) ~= 'table' then bans = {} end
end
local function saveJson()
    SaveResourceFile(GetCurrentResourceName(), BAN_FILE, json.encode(bans, { indent = true }), -1)
end

-- ── add ─────────────────────────────────────────────
function WG.Bans.add(data)
    local banId = WG.genId(10)
    local ids   = data.identifiers or {}

    if usingDB() then
        WG.DB.execute([[INSERT INTO wireguard_bans
            (ban_id, name, reason, banned_by, license, discord, steam, ip, identifiers, tokens, expires_at)
            VALUES (?,?,?,?,?,?,?,?,?,?, ?)]], {
            banId, data.name or 'Unbekannt', data.reason or 'Kein Grund angegeben', data.bannedBy or 'MountainV Anticheat',
            ids.license, ids.discord, ids.steam, ids.ip,
            json.encode(ids), json.encode(ids.tokens or {}),
            (data.expires and data.expires ~= 0) and os.date('%Y-%m-%d %H:%M:%S', data.expires) or nil
        })
    else
        table.insert(bans, {
            id = banId, name = data.name or 'Unbekannt', reason = data.reason or 'Kein Grund angegeben',
            bannedBy = data.bannedBy or 'MountainV Anticheat', identifiers = ids,
            tokens = ids.tokens or {}, time = os.time(), expires = data.expires or 0
        })
        saveJson()
    end

    WG.warn(('BAN added: %s (%s) - %s'):format(data.name or '?', banId, data.reason or ''))
    if WG.Discord then WG.Discord.logBan({ id = banId, name = data.name, reason = data.reason,
        bannedBy = data.bannedBy or 'MountainV Anticheat', identifiers = ids }) end
    if WG.DB then WG.DB.logAction(data.bannedBy or 'MountainV Anticheat', 'ban', data.name, data.reason) end
    return banId
end

-- ── check (on connect) ──────────────────────────────
function WG.Bans.check(ids)
    if usingDB() then
        local conds, params = {}, {}
        for _, k in ipairs({ 'license', 'discord', 'steam', 'ip' }) do
            if ids[k] then conds[#conds+1] = k .. ' = ?'; params[#params+1] = ids[k] end
        end
        if #conds == 0 then return nil end
        local sql = ('SELECT * FROM wireguard_bans WHERE (%s) AND (expires_at IS NULL OR expires_at > NOW()) LIMIT 1')
            :format(table.concat(conds, ' OR '))
        local row = WG.DB.single(sql, params)
        if row then return { id = row.ban_id, reason = row.reason, name = row.name } end

        -- token match (anti-evasion) — scan recent bans
        if ids.tokens and #ids.tokens > 0 then
            local rows = WG.DB.query('SELECT ban_id, reason, name, tokens FROM wireguard_bans WHERE tokens IS NOT NULL ORDER BY id DESC LIMIT 500') or {}
            for _, r in ipairs(rows) do
                local tks = WG.jsonDecode(r.tokens, {})
                for _, t1 in ipairs(tks) do
                    for _, t2 in ipairs(ids.tokens) do
                        if t1 == t2 then return { id = r.ban_id, reason = r.reason, name = r.name } end
                    end
                end
            end
        end
        return nil
    end

    -- JSON path
    local now = os.time()
    for _, b in ipairs(bans) do
        if b.expires ~= 0 and b.expires < now then goto continue end
        if b.identifiers then
            for kind, value in pairs(b.identifiers) do
                if kind ~= 'tokens' and value and ids[kind] == value then return b end
            end
        end
        if b.tokens and ids.tokens then
            for _, t1 in ipairs(b.tokens) do
                for _, t2 in ipairs(ids.tokens) do
                    if t1 == t2 then return b end
                end
            end
        end
        ::continue::
    end
    return nil
end

-- ── remove ──────────────────────────────────────────
function WG.Bans.remove(banId)
    if usingDB() then
        local res = WG.DB.execute('DELETE FROM wireguard_bans WHERE ban_id = ?', { banId })
        local affected = (type(res) == 'table' and res.affectedRows) or res or 0
        if affected and affected > 0 then
            WG.DB.logAction('WebPanel', 'unban', banId, nil)
            WG.warn('UNBAN: ' .. banId); return true
        end
        return false
    end
    for i = #bans, 1, -1 do
        if bans[i].id == banId then table.remove(bans, i); saveJson(); WG.warn('UNBAN: ' .. banId); return true end
    end
    return false
end

-- ── list ────────────────────────────────────────────
function WG.Bans.list()
    if usingDB() then
        local rows = WG.DB.query('SELECT * FROM wireguard_bans ORDER BY id DESC LIMIT 500') or {}
        local out = {}
        for _, r in ipairs(rows) do
            out[#out+1] = {
                id = r.ban_id, name = r.name, reason = r.reason, bannedBy = r.banned_by,
                time = r.created_at, identifiers = { license = r.license, discord = r.discord },
            }
        end
        return out
    end
    return bans
end

-- ── commands ────────────────────────────────────────
RegisterCommand('wg_ban', function(src, args)
    if src ~= 0 and not WG.Server.isAdmin(src) then return end
    local target = tonumber(args[1])
    if not target or not GetPlayerName(target) then print('usage: wg_ban <serverId> <reason...>'); return end
    local reason = table.concat(args, ' ', 2)
    local id = WG.Bans.add({
        identifiers = WG.Server.getIdentifiers(target), name = GetPlayerName(target),
        reason = reason ~= '' and reason or 'Manueller Ban',
        bannedBy = src == 0 and 'Konsole' or GetPlayerName(src)
    })
    DropPlayer(target, Config.BanMessage:format(id))
end, true)

RegisterCommand('wg_unban', function(src, args)
    if src ~= 0 and not WG.Server.isAdmin(src) then return end
    print(WG.Bans.remove(args[1]) and ('^2[WireGuard]^7 unbanned '..tostring(args[1])) or '^1[WireGuard]^7 ban id not found')
end, true)

-- Only load JSON if DB stays off (give DB a moment to init)
CreateThread(function()
    Wait(3000)
    if not usingDB() then loadJson(); WG.log(('loaded %d bans (JSON)'):format(#bans)) end
end)
