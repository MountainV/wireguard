--[[ ============================================================
     WireGuard - Server core
     - receives flags, applies trust score + punishment
     - tracks player state for server-side validation
     - exposes WG.Server API used by other server files
     ============================================================ ]]

WG = WG or {}
WG.Server = {
    players = {},   -- [src] = { trust, flags={}, identifiers={}, name, lastState }
    feed    = {}    -- recent detections for the admin menu / web panel
}

local MAX_FEED = 200
local function clampTrust(score)
    return math.max(0, math.min(100, score))
end

-- True while a player is still within the post-join grace period.
-- During this window detections are ignored so loading artifacts
-- (spawn teleport, speed spikes, temporary godmode) never cause a ban.
local function inJoinGrace(p)
    return Config.JoinGracePeriod and Config.JoinGracePeriod > 0
        and p and p.joinedAt and (os.time() - p.joinedAt) < Config.JoinGracePeriod
end

-- ─────────────────────────────────────────────
--  Identifiers / admin helpers
-- ─────────────────────────────────────────────
function WG.Server.getIdentifiers(src)
    local ids = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id then
            local kind = id:match('^(%w+):')
            if kind then ids[kind] = id end
        end
    end
    ids.tokens = {}
    for i = 0, GetNumPlayerTokens(src) - 1 do
        ids.tokens[#ids.tokens + 1] = GetPlayerToken(src, i)
    end
    return ids
end

WG.Server.dbAdmins    = {}  -- license -> true (from wireguard_admins)
WG.Server.dbRanks     = {}  -- license -> rank (from wireguard_admins)
WG.Server.dbWhitelist = {}  -- license -> true (from wireguard_whitelist)
WG.Server.playerGroup = {}  -- src -> group (set by framework via export)

function WG.Server.isAdmin(src)
    local lic = GetPlayerIdentifierByType(src, 'license')
    if lic and Config.Admins[lic] then return true end
    if lic and WG.Server.dbAdmins[lic] then return true end
    if IsPlayerAceAllowed(src, Config.AdminAcePermission) then return true end
    return false
end

-- Resolve a player's group/rank from framework export, ACE, or DB rank.
function WG.Server.getGroup(src)
    if WG.Server.playerGroup[src] then return WG.Server.playerGroup[src] end
    local lic = GetPlayerIdentifierByType(src, 'license')
    if lic and WG.Server.dbRanks[lic] then return WG.Server.dbRanks[lic] end
    if Config.Whitelist.CheckAce then
        for _, g in ipairs(Config.Whitelist.Groups) do
            if IsPlayerAceAllowed(src, 'group.' .. g) or IsPlayerAceAllowed(src, 'wireguard.' .. g) then
                return g
            end
        end
    end
    return nil
end

-- Is the player exempt from all detections?
function WG.Server.isWhitelisted(src)
    -- per-player whitelist (DB) — always honoured, independent of group whitelist
    local lic = GetPlayerIdentifierByType(src, 'license')
    if lic and WG.Server.dbWhitelist[lic] then return true end

    if not Config.Whitelist.Enabled then return false end
    local g = WG.Server.getGroup(src)
    if not g then return false end
    g = tostring(g):lower()
    for _, allowed in ipairs(Config.Whitelist.Groups) do
        if g == allowed:lower() then return true end
    end
    return false
end

-- Frameworks (ESX/QBCore/custom) can push the player's group here.
exports('setPlayerGroup', function(src, group)
    WG.Server.playerGroup[src] = group
    local p = WG.Server.players[src]
    if p then
        p.group   = group
        p.bypass  = p.isAdmin or WG.Server.isWhitelisted(src)
        TriggerClientEvent(WG.Events.Sync, src, { isAdmin = p.isAdmin, bypass = p.bypass })
    end
end)

-- Refresh the DB admin cache (called on start and after admin changes)
function WG.Server.refreshAdmins()
    if not (Config.Database.SyncAdmins and WG.DB and WG.DB.ready) then return end
    WG.Server.dbAdmins = {}
    WG.Server.dbRanks  = {}
    local rows = WG.DB.getAdmins()
    for _, row in ipairs(rows) do
        if row.license then
            WG.Server.dbAdmins[row.license] = true
            WG.Server.dbRanks[row.license]  = row.rank
        end
    end
    WG.log(('loaded %d DB admins'):format(#rows))
end

-- Refresh the per-player whitelist cache from the DB (called on start + periodically)
function WG.Server.refreshWhitelist()
    if not (WG.DB and WG.DB.ready) then return end
    local wl = {}
    local rows = WG.DB.getWhitelist()
    for _, row in ipairs(rows) do
        if row.license then wl[row.license] = true end
    end
    WG.Server.dbWhitelist = wl
    WG.log(('loaded %d whitelist entries'):format(#rows))
end

CreateThread(function()
    Wait(4000)
    while true do
        WG.Server.refreshAdmins()
        WG.Server.refreshWhitelist()
        Wait(60000)   -- refresh every 60s
    end
end)

-- ─────────────────────────────────────────────
--  Player registry
-- ─────────────────────────────────────────────
local function initPlayer(src)
    if WG.Server.players[src] then return WG.Server.players[src] end
    local p = {
        src         = src,
        name        = GetPlayerName(src) or ('player_' .. src),
        trust       = clampTrust(Config.TrustScore.Start),
        flags       = {},
        identifiers = WG.Server.getIdentifiers(src),
        isAdmin     = WG.Server.isAdmin(src),
        group       = WG.Server.getGroup(src),
        joinedAt    = os.time(),
        lastState   = {}
    }
    p.bypass = p.isAdmin or WG.Server.isWhitelisted(src)   -- exempt from detections
    WG.Server.players[src] = p
    return p
end

function WG.Server.get(src)
    return WG.Server.players[src] or initPlayer(src)
end

-- ─────────────────────────────────────────────
--  Feed (for dashboard & in-game menu)
-- ─────────────────────────────────────────────
local function pushFeed(entry)
    table.insert(WG.Server.feed, 1, entry)
    while #WG.Server.feed > MAX_FEED do table.remove(WG.Server.feed) end
end
WG.Server.pushFeed = pushFeed

-- ─────────────────────────────────────────────
--  Punishment
-- ─────────────────────────────────────────────
function WG.Server.punish(src, action, detectionName, detail)
    local p = WG.Server.get(src)
    action = action or Config.DefaultAction

    if action == WG.Action.NONE then return end

    if action == WG.Action.WARN then
        TriggerClientEvent(WG.Events.Punish, src, ('⚠️ MountainV Anticheat » Verwarnung: %s'):format(detectionName))
        return
    end

    if action == WG.Action.KICK then
        TriggerClientEvent(WG.Events.Punish, src, Config.KickMessage)
        Wait(250)
        DropPlayer(src, Config.KickMessage)
        return
    end

    if action == WG.Action.BAN then
        local banId = WG.Bans.add({
            identifiers = p.identifiers,
            name        = p.name,
            reason      = ('[%s] %s'):format(detectionName, detail or ''),
            bannedBy    = 'MountainV Anticheat',
            expires     = 0  -- permanent
        })
        TriggerClientEvent(WG.Events.Punish, src, Config.BanMessage:format(banId))
        Wait(250)
        DropPlayer(src, Config.BanMessage:format(banId))
        return
    end
end

-- ─────────────────────────────────────────────
--  Core: handle a flag from a client
-- ─────────────────────────────────────────────
RegisterNetEvent(WG.Events.Flag, function(detectionName, detail, state)
    local src = source
    local p   = WG.Server.get(src)
    if p.bypass then return end  -- admins & whitelisted groups are exempt
    if inJoinGrace(p) then return end  -- don't punish right after joining

    local cfg = Config.Detections[detectionName]
    if not cfg or not cfg.enabled then return end

    -- record
    p.flags[detectionName] = (p.flags[detectionName] or 0) + 1
    if Config.TrustScore.Enabled then
        p.trust = clampTrust(p.trust - (cfg.penalty or 10))
    end

    local severity = WG.ActionSeverity[cfg.action] or WG.Severity.MEDIUM
    local entry = {
        time      = os.time(),
        src       = src,
        name      = p.name,
        detection = detectionName,
        detail    = detail,
        action    = cfg.action,
        severity  = severity,
        trust     = p.trust,
        coords    = state and state.coords or nil,
        license   = p.identifiers.license
    }
    pushFeed(entry)

    WG.warn(('%s (%d) flagged: %s | %s | trust=%d'):format(p.name, src, detectionName, detail or '', p.trust))

    -- Persist to DB + Discord + screenshot
    if WG.DB then WG.DB.logDetection(entry) end
    if WG.Discord then WG.Discord.logDetection(entry) end
    if Config.Screenshots.Enabled and Config.Screenshots.OnDetection and WG.Screenshot then
        WG.Screenshot.capture(src, detectionName)
    end

    -- Decide punishment: explicit action, or trust threshold
    local act = cfg.action
    if Config.TrustScore.Enabled and p.trust <= Config.TrustScore.BanBelow then
        act = WG.Action.BAN
    end
    WG.Server.punish(src, act, detectionName, detail)
end)

-- ─────────────────────────────────────────────
--  Heartbeat: server-side validation + boot sync
-- ─────────────────────────────────────────────
RegisterNetEvent(WG.Events.Heartbeat, function(state)
    local src = source
    local p   = WG.Server.get(src)

    -- send admin/bypass/boot sync
    TriggerClientEvent(WG.Events.Sync, src, { isAdmin = p.isAdmin, bypass = p.bypass })

    if type(state) ~= 'table' then return end
    p.lastState = state

    -- server-side godmode sanity: ped health reported above max over time
    if state.health and state.health > (Config.Thresholds.MaxHealth + 5) and not p.bypass and not inJoinGrace(p) then
        WG.Server.punish(src, Config.Detections.GodMode.action, 'GodMode', 'server-side health ' .. state.health)
    end
end)

-- ─────────────────────────────────────────────
--  Connection lifecycle
-- ─────────────────────────────────────────────
AddEventHandler('playerConnecting', function(name, setKick, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update('🛡️ MountainV Anticheat » Dein Account wird überprüft...')

    local ids = WG.Server.getIdentifiers(src)
    local ban = WG.Bans.check(ids)
    if ban then
        deferrals.done(('🛡️ MountainV Anticheat\n\nDu bist von diesem Server gesperrt.\n\nGrund: %s\nBan-ID: %s\n\nBei einem Einspruch wende dich mit deiner Ban-ID an unser Support-Team.'):format(ban.reason or 'Kein Grund angegeben', ban.id))
        return
    end
    deferrals.done()
end)

AddEventHandler('playerDropped', function()
    local src = source
    WG.Server.players[src]     = nil
    WG.Server.playerGroup[src] = nil
end)

-- ─────────────────────────────────────────────
--  Console commands
-- ─────────────────────────────────────────────
RegisterCommand('wg_status', function(src)
    if src ~= 0 and not WG.Server.isAdmin(src) then return end
    local n = 0
    for _ in pairs(WG.Server.players) do n = n + 1 end
    print(('^5[WireGuard]^7 tracking %d players, %d feed entries'):format(n, #WG.Server.feed))
end, true)

print('^5[WireGuard]^7 server core loaded - '.. Config.ServerName)
