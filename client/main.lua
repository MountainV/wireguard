--[[ ============================================================
     WireGuard - Client core
     Provides the detection framework used by all modules:
       - WG.Client.flag()        report a detection to the server
       - WG.Client.register()    register a periodic check
       - admin bypass handling
     ============================================================ ]]

WG = WG or {}
WG.Client = {
    isAdmin   = false,   -- can open the admin menu
    bypass    = false,   -- exempt from detections (admins + whitelisted groups)
    checks    = {},      -- registered periodic checks
    lastFlag  = {},      -- debounce: detection -> last time flagged
    booted    = false
}

local FLAG_DEBOUNCE_MS = 3000

-- ─────────────────────────────────────────────
--  Flag a detection. Called by every module.
--  name  : detection key from Config.Detections
--  detail: human readable string for logs / evidence
-- ─────────────────────────────────────────────
function WG.Client.flag(name, detail)
    if WG.Client.bypass then return end  -- admins & whitelisted groups bypass

    local cfg = Config.Detections[name]
    if not cfg or not cfg.enabled then return end

    -- debounce identical flags so we don't spam the server
    local now = GetGameTimer()
    if WG.Client.lastFlag[name] and (now - WG.Client.lastFlag[name]) < FLAG_DEBOUNCE_MS then
        return
    end
    WG.Client.lastFlag[name] = now

    WG.log('FLAG', name, detail or '')

    TriggerServerEvent(WG.Events.Flag, name, detail or '', {
        coords = GetEntityCoords(PlayerPedId()),
        health = GetEntityHealth(PlayerPedId()),
        armour = GetPedArmour(PlayerPedId())
    })
end

-- ─────────────────────────────────────────────
--  Register a periodic check.
--  fn        : function run every `interval` ms
--  interval  : ms (defaults to Config.CheckIntervalMs)
-- ─────────────────────────────────────────────
function WG.Client.register(fn, interval)
    table.insert(WG.Client.checks, { fn = fn, interval = interval or Config.CheckIntervalMs, last = 0 })
end

-- ─────────────────────────────────────────────
--  Central scheduler - runs all registered checks.
--  Using one thread keeps CPU predictable.
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(0)
        if WG.Client.booted and not WG.Client.bypass then
            local now = GetGameTimer()
            for _, c in ipairs(WG.Client.checks) do
                if (now - c.last) >= c.interval then
                    c.last = now
                    local ok, errMsg = pcall(c.fn)
                    if not ok then WG.err('check failed:', errMsg) end
                end
            end
        else
            Wait(500)
        end
    end
end)

-- ─────────────────────────────────────────────
--  Heartbeat: periodically send state so the server can
--  cross-check (e.g. server-side godmode / coords validation).
-- ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(5000)
        if WG.Client.booted then
            local ped = PlayerPedId()
            TriggerServerEvent(WG.Events.Heartbeat, {
                health = GetEntityHealth(ped),
                armour = GetPedArmour(ped),
                coords = GetEntityCoords(ped)
            })
        end
    end
end)

-- ─────────────────────────────────────────────
--  Receive sync from server (admin status + any pushed config).
-- ─────────────────────────────────────────────
RegisterNetEvent(WG.Events.Sync, function(data)
    if type(data) ~= 'table' then return end

    -- live config push from the web panel (detections on/off, thresholds)
    if type(data.detections) == 'table' then
        for name, cfg in pairs(data.detections) do
            Config.Detections[name] = cfg
        end
        WG.log('detection config synced from panel')
    end
    if type(data.thresholds) == 'table' then
        for k, v in pairs(data.thresholds) do
            Config.Thresholds[k] = v
        end
    end

    -- status sync (admin / bypass / boot)
    if data.isAdmin ~= nil or data.bypass ~= nil then
        if data.isAdmin ~= nil then WG.Client.isAdmin = data.isAdmin end
        if data.bypass  ~= nil then WG.Client.bypass  = data.bypass  end
        WG.log('admin =', tostring(WG.Client.isAdmin), 'bypass =', tostring(WG.Client.bypass))
        WG.Client.booted = true
    end
end)

-- Forced feedback before drop
RegisterNetEvent(WG.Events.Punish, function(msg)
    SetNuiFocus(false, false)
    -- brief on-screen note; the actual drop happens server-side
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(msg or 'WireGuard')
    EndTextCommandDisplayHelp(0, false, true, 5000)
end)

-- Ask the server for our status once everything is loaded.
AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(2000)
    TriggerServerEvent(WG.Events.Heartbeat, { boot = true })
end)

WG.log('client core loaded')
