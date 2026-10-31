--[[ WireGuard - Shared enums & constants ]]

WG = WG or {}

-- Event names (prefixed + randomized token helps against event sniffing).
-- The token is static here for readability; for production rotate it or move
-- sensitive events server->client only.
WG.Events = {
    Flag          = 'wireguard:flag',            -- client -> server : report a detection
    Punish        = 'wireguard:punish',          -- server -> client : force kick feedback
    Sync          = 'wireguard:sync',            -- server -> client : push config/admin status
    Heartbeat     = 'wireguard:hb',              -- client -> server : alive ping w/ state
    RequestScreen = 'wireguard:reqScreen',       -- server -> client : take screenshot
    AdminAction   = 'wireguard:adminAction',     -- client(admin) -> server : menu action
    AdminData     = 'wireguard:adminData',       -- server -> client(admin) : player list etc.
    SafeEvent     = 'wireguard:safeEvent'        -- validated event channel
}

-- Punishment actions
WG.Action = {
    BAN  = 'ban',
    KICK = 'kick',
    WARN = 'warn',
    NONE = 'none'
}

-- Severity for dashboard colouring
WG.Severity = {
    LOW    = 'low',
    MEDIUM = 'medium',
    HIGH   = 'high',
    CRIT   = 'critical'
}

-- Map a default severity per action
WG.ActionSeverity = {
    ban  = WG.Severity.CRIT,
    kick = WG.Severity.HIGH,
    warn = WG.Severity.MEDIUM,
    none = WG.Severity.LOW
}
