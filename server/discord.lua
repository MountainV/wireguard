--[[ ============================================================
     WireGuard - Discord webhook logging
     ============================================================ ]]

WG = WG or {}
WG.Discord = {}

local function send(webhook, embed)
    if not Config.Discord.Enabled then return end
    if not webhook or webhook == '' then return end
    PerformHttpRequest(webhook, function(code)
        if code ~= 200 and code ~= 204 then
            WG.warn('discord webhook returned ' .. tostring(code))
        end
    end, 'POST', json.encode({
        username   = Config.Discord.BotName,
        avatar_url = Config.Discord.Avatar,
        embeds     = { embed }
    }), { ['Content-Type'] = 'application/json' })
end

local severityColor = {
    low      = 3447003,    -- blue
    medium   = 16776960,   -- yellow
    high     = 15105570,   -- orange
    critical = 15158332    -- red
}

function WG.Discord.logDetection(entry)
    local color = severityColor[entry.severity] or Config.Discord.Color
    send(Config.Discord.Webhook, {
        title  = '🚨 Erkennung: ' .. entry.detection,
        color  = color,
        fields = {
            { name = 'Spieler',   value = ('%s (%d)'):format(entry.name, entry.src), inline = true },
            { name = 'Aktion',    value = entry.action or 'keine',                   inline = true },
            { name = 'Trust',     value = tostring(entry.trust),                     inline = true },
            { name = 'Details',   value = entry.detail or 'n. v.',                   inline = false },
            { name = 'License',   value = entry.license or 'n. v.',                  inline = false }
        },
        footer    = { text = 'MountainV Anticheat' },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    })
end

function WG.Discord.logBan(record)
    local webhook = Config.Discord.BanWebhook ~= '' and Config.Discord.BanWebhook or Config.Discord.Webhook
    send(webhook, {
        title  = '⛔ Spieler gesperrt',
        color  = 15158332,
        fields = {
            { name = 'Spieler',  value = record.name,                     inline = true },
            { name = 'Ban-ID',   value = record.id,                       inline = true },
            { name = 'Von',      value = record.bannedBy,                 inline = true },
            { name = 'Grund',    value = record.reason,                   inline = false },
            { name = 'License',  value = record.identifiers.license or 'n. v.', inline = false },
            { name = 'Discord',  value = record.identifiers.discord or 'n. v.', inline = true }
        },
        footer    = { text = 'MountainV Anticheat' },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
    })
end

WG.log('discord module loaded')
