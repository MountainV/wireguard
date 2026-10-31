--[[ ============================================================
     WireGuard - HTTP API for the web panel
     Exposes a small JSON API on the FiveM server's HTTP endpoint:
        GET  /players   -> online players w/ trust & flags
        GET  /feed      -> recent detections
        GET  /bans      -> ban list
        POST /kick      -> { target, reason }
        POST /ban       -> { target, reason }
        POST /unban     -> { banId }
     Auth: header  Authorization: Bearer <wireguard_api_token from server.cfg>
     Reachable at:  http://<server-ip>:<txPort>/wireguard/<route>
     ============================================================ ]]

local function json_res(res, status, body)
    res.writeHead(status, {
        ['Content-Type']                 = 'application/json',
        ['Access-Control-Allow-Origin']  = '*',
        ['Access-Control-Allow-Headers'] = 'Content-Type, Authorization',
        ['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    })
    res.send(json.encode(body))
end

local function authorized(req)
    local token = GetConvar('wireguard_api_token', '')
    if token == '' then return false end
    local auth = req.headers['Authorization'] or req.headers['authorization']
    if not auth then return false end
    return auth == ('Bearer ' .. token)
end

local function buildPlayers()
    local list = {}
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        local p = WG.Server.get(src)
        list[#list + 1] = {
            src     = src,
            name    = GetPlayerName(src),
            trust   = p.trust,
            flags   = p.flags,
            ping    = GetPlayerPing(src),
            isAdmin = p.isAdmin,
            license = p.identifiers.license,
            discord = p.identifiers.discord
        }
    end
    return list
end

local function handleRequest(req, res)
    if not Config.WebPanel.Enabled then
        return json_res(res, 503, { error = 'web panel disabled' })
    end

    -- CORS preflight
    if req.method == 'OPTIONS' then
        return json_res(res, 204, {})
    end

    local path = req.path:gsub('^/', ''):gsub('/$', '')

    if not authorized(req) then
        return json_res(res, 401, { error = 'unauthorized' })
    end

    -- GET routes
    if req.method == 'GET' then
        if path == 'players' then
            return json_res(res, 200, { players = buildPlayers() })
        elseif path == 'feed' then
            return json_res(res, 200, { feed = WG.Server.feed })
        elseif path == 'bans' then
            return json_res(res, 200, { bans = WG.Bans.list() })
        elseif path == 'stats' then
            return json_res(res, 200, {
                serverName = Config.ServerName,
                online     = #GetPlayers(),
                bans       = #WG.Bans.list(),
                detections = #WG.Server.feed,
                database   = (WG.DB and WG.DB.ready) and true or false
            })
        elseif path == 'history' then
            return json_res(res, 200, { history = WG.DB and WG.DB.getHistory(200) or {} })
        elseif path == 'analytics' then
            return json_res(res, 200, { analytics = WG.DB and WG.DB.getAnalytics() or {} })
        elseif path == 'admins' then
            return json_res(res, 200, { admins = WG.DB and WG.DB.getAdmins() or {} })
        elseif path == 'logs' then
            return json_res(res, 200, { logs = WG.DB and WG.DB.getLogs(200) or {} })
        elseif path == 'config' then
            return json_res(res, 200, WG.Settings and WG.Settings.snapshot() or {})
        elseif path == 'whitelist' then
            return json_res(res, 200, { whitelist = WG.DB and WG.DB.getWhitelist() or {} })
        end
        return json_res(res, 404, { error = 'not found' })
    end

    -- POST routes
    if req.method == 'POST' then
        req.setDataHandler(function(body)
            local data = WG.jsonDecode(body, {})
            if path == 'kick' then
                local t = tonumber(data.target)
                if t and GetPlayerName(t) then
                    DropPlayer(t, data.reason or Config.KickMessage)
                    return json_res(res, 200, { ok = true })
                end
                return json_res(res, 400, { error = 'invalid target' })

            elseif path == 'ban' then
                local t = tonumber(data.target)
                if t and GetPlayerName(t) then
                    local p = WG.Server.get(t)
                    local id = WG.Bans.add({
                        identifiers = p.identifiers,
                        name        = GetPlayerName(t),
                        reason      = data.reason or 'Ban über Web-Panel',
                        bannedBy    = data.by or 'Web-Panel'
                    })
                    DropPlayer(t, Config.BanMessage:format(id))
                    return json_res(res, 200, { ok = true, banId = id })
                end
                return json_res(res, 400, { error = 'invalid target' })

            elseif path == 'unban' then
                if WG.Bans.remove(data.banId) then
                    return json_res(res, 200, { ok = true })
                end
                return json_res(res, 404, { error = 'ban not found' })

            elseif path == 'action' then
                -- generic player action: heal/kill/freeze/unfreeze/message/warn/screenshot/kick/ban
                local ok, msg = WG.Server.doAction(data.by or 'WebPanel', nil, data.type, data.target, data.reason)
                return json_res(res, ok and 200 or 400, { ok = ok, message = msg })

            elseif path == 'addban' then
                -- manual ban by identifier (player may be offline)
                local ids = {}
                if data.license then ids.license = data.license end
                if data.discord then ids.discord = data.discord end
                if data.steam   then ids.steam   = data.steam end
                if not next(ids) then return json_res(res, 400, { error = 'need at least one identifier' }) end
                local id = WG.Bans.add({ identifiers = ids, name = data.name or 'Manuell',
                    reason = data.reason or 'Manueller Ban (Panel)', bannedBy = data.by or 'Web-Panel' })
                return json_res(res, 200, { ok = true, banId = id })

            elseif path == 'addadmin' then
                if not data.license then return json_res(res, 400, { error = 'license required' }) end
                WG.DB.addAdmin(data.license, data.name, data.rank, data.by or 'WebPanel')
                WG.Server.refreshAdmins()
                return json_res(res, 200, { ok = true })

            elseif path == 'removeadmin' then
                if not data.license then return json_res(res, 400, { error = 'license required' }) end
                WG.DB.removeAdmin(data.license)
                WG.Server.refreshAdmins()
                return json_res(res, 200, { ok = true })

            elseif path == 'settings' then
                if not WG.Settings then return json_res(res, 503, { error = 'settings module unavailable' }) end
                local ok = WG.Settings.apply(data)
                return json_res(res, ok and 200 or 400, { ok = ok })

            elseif path == 'addwl' then
                if not data.license then return json_res(res, 400, { error = 'license required' }) end
                WG.DB.addWhitelist(data.license, data.name, data.by or 'Web-Panel')
                WG.Server.refreshWhitelist()
                return json_res(res, 200, { ok = true })

            elseif path == 'removewl' then
                if not data.license then return json_res(res, 400, { error = 'license required' }) end
                WG.DB.removeWhitelist(data.license)
                WG.Server.refreshWhitelist()
                return json_res(res, 200, { ok = true })
            end
            return json_res(res, 404, { error = 'not found' })
        end)
        return
    end

    return json_res(res, 405, { error = 'method not allowed' })
end

SetHttpHandler(function(req, res)
    local ok, err = pcall(handleRequest, req, res)
    if not ok then
        WG.err('api error: ' .. tostring(err))
        pcall(json_res, res, 500, { error = 'internal error' })
    end
end)

print('^5[WireGuard]^7 HTTP API ready (token-protected)')
WG.log('api module loaded')
