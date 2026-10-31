--[[ ============================================================
     WireGuard - Safe Events
     Protects your server events from being triggered by cheats.
     Register sensitive events here with a validator; WireGuard
     enforces rate limits and optional server-side checks, and
     flags players who spam/abuse protected events.
     ============================================================ ]]

WG = WG or {}
WG.SafeEvents = {}

local registry = {}          -- [eventName] = { rate=perSec, validator=fn }
local callTracking = {}      -- [src] = { [eventName] = { count, windowStart } }

-- ─────────────────────────────────────────────
--  Public: register a protected event.
--  opts = { rate = maxCallsPerSecond, validator = function(src, ...) return bool end }
-- ─────────────────────────────────────────────
function WG.SafeEvents.register(eventName, opts)
    opts = opts or {}
    registry[eventName] = {
        rate      = opts.rate or 5,
        validator = opts.validator
    }
    WG.log('safe event registered: ' .. eventName)
end

-- ─────────────────────────────────────────────
--  Public: check a call. Call this at the TOP of your event handler.
--  Returns true if the call is allowed.
-- ─────────────────────────────────────────────
function WG.SafeEvents.validate(eventName, src, ...)
    local reg = registry[eventName]
    if not reg then return true end       -- unregistered -> allow (opt-in system)

    callTracking[src] = callTracking[src] or {}
    local t = callTracking[src][eventName]
    local now = GetGameTimer()

    if not t or (now - t.windowStart) > 1000 then
        callTracking[src][eventName] = { count = 1, windowStart = now }
    else
        t.count = t.count + 1
        if t.count > reg.rate then
            WG.Server.punish(src, 'kick', 'SafeEvent', ('rate limit on %s (%d/s)'):format(eventName, t.count))
            return false
        end
    end

    -- custom validator
    if reg.validator then
        local ok = reg.validator(src, ...)
        if not ok then
            WG.Server.punish(src, 'ban', 'SafeEvent', ('validator rejected %s'):format(eventName))
            return false
        end
    end

    return true
end

-- Cleanup tracking on drop
AddEventHandler('playerDropped', function()
    callTracking[source] = nil
end)

--[[ ── EXAMPLE USAGE (in YOUR resources) ─────────────────────────
     In your money/give script:

        RegisterNetEvent('myserver:giveMoney', function(amount)
            if not exports.wireguard:validateEvent('myserver:giveMoney', source, amount) then
                return
            end
            -- ... your logic
        end)

     And register it once on start:

        exports.wireguard:registerSafeEvent('myserver:giveMoney', {
            rate = 2,
            validator = function(src, amount)
                return type(amount) == 'number' and amount > 0 and amount <= 10000
            end
        })
   ──────────────────────────────────────────────────────────── ]]

-- Exports so other resources can use the safe-event system
exports('registerSafeEvent', function(name, opts) WG.SafeEvents.register(name, opts) end)
exports('validateEvent', function(name, src, ...) return WG.SafeEvents.validate(name, src, ...) end)

WG.log('safe events module loaded')
