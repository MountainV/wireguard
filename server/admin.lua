--[[ ============================================================
     WireGuard - Admin actions (in-game NUI menu + Web API backend)
     Shared action handler used by both the NUI event and the HTTP API.
     ============================================================ ]]

local function buildPlayerList()
    local list = {}
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        local p = WG.Server.get(src)
        local ped = GetPlayerPed(src)
        local coords = ped and GetEntityCoords(ped) or vector3(0,0,0)
        list[#list + 1] = {
            src = src, name = GetPlayerName(src), trust = p.trust, flags = p.flags,
            isAdmin = p.isAdmin, ping = GetPlayerPing(src), license = p.identifiers.license,
            discord = p.identifiers.discord,
            coords = { x = coords.x, y = coords.y, z = coords.z }
        }
    end
    return list
end
WG.Server.buildPlayerList = buildPlayerList

-- ─────────────────────────────────────────────
--  Central action handler. Returns ok, message.
--  adminName: display name of the admin (or 'WebPanel' / 'Console')
--  adminSrc : the admin's server id, or nil for web/console
-- ─────────────────────────────────────────────
function WG.Server.doAction(adminName, adminSrc, actionType, target, reason)
    target = tonumber(target)
    reason = reason or ''

    if actionType == 'kick' then
        if not target or not GetPlayerName(target) then return false, 'invalid target' end
        DropPlayer(target, reason ~= '' and reason or Config.KickMessage)

    elseif actionType == 'ban' then
        if not target or not GetPlayerName(target) then return false, 'invalid target' end
        local p = WG.Server.get(target)
        local id = WG.Bans.add({ identifiers = p.identifiers, name = GetPlayerName(target),
            reason = reason ~= '' and reason or 'Admin-Ban', bannedBy = adminName })
        DropPlayer(target, Config.BanMessage:format(id))

    elseif actionType == 'warn' then
        if not target then return false, 'invalid target' end
        TriggerClientEvent(WG.Events.Punish, target, 'Admin Verwarnung: ' .. (reason ~= '' and reason or 'verhalte dich'))

    elseif actionType == 'heal' then
        TriggerClientEvent('wireguard:heal', target)
    elseif actionType == 'kill' then
        TriggerClientEvent('wireguard:kill', target)
    elseif actionType == 'freeze' then
        TriggerClientEvent('wireguard:freeze', target)
    elseif actionType == 'unfreeze' then
        TriggerClientEvent('wireguard:freeze', target, true)
    elseif actionType == 'message' then
        TriggerClientEvent('wireguard:message', target, reason)
    elseif actionType == 'screenshot' then
        if WG.Screenshot then WG.Screenshot.capture(target, 'Admin requested') end

    elseif actionType == 'spectate' then
        if not adminSrc then return false, 'in-game only' end
        local c = GetEntityCoords(GetPlayerPed(target))
        TriggerClientEvent('wireguard:spectate', adminSrc, { x=c.x, y=c.y, z=c.z })
    elseif actionType == 'tp' or actionType == 'goto' then
        if not adminSrc then return false, 'in-game only' end
        local c = GetEntityCoords(GetPlayerPed(target))
        TriggerClientEvent('wireguard:teleport', adminSrc, { x=c.x, y=c.y, z=c.z })
    elseif actionType == 'tphere' or actionType == 'bring' then
        if not adminSrc then return false, 'in-game only' end
        local c = GetEntityCoords(GetPlayerPed(adminSrc))
        TriggerClientEvent('wireguard:teleport', target, { x=c.x, y=c.y, z=c.z })
    else
        return false, 'unknown action'
    end

    if WG.DB then WG.DB.logAction(adminName, actionType, GetPlayerName(target) or tostring(target), reason) end
    WG.Server.pushFeed({
        time = os.time(), src = target, name = GetPlayerName(target) or ('id'..tostring(target)),
        detection = 'AdminAction:' .. actionType, detail = ('by %s: %s'):format(adminName, reason),
        action = actionType, severity = 'low'
    })
    return true, 'ok'
end

-- NUI event from in-game admin
RegisterNetEvent(WG.Events.AdminAction, function(actionType, target, reason)
    local src = source
    if not WG.Server.isAdmin(src) then
        WG.warn(('non-admin %s tried admin action %s'):format(GetPlayerName(src), tostring(actionType)))
        return
    end
    if actionType == 'getPlayers' then
        TriggerClientEvent(WG.Events.AdminData, src, { players = buildPlayerList(), feed = WG.Server.feed })
        return
    end
    WG.Server.doAction(GetPlayerName(src), src, actionType, target, reason)
end)

WG.log('admin module loaded')
