--[[ ============================================================
     WireGuard - Screenshot evidence
     Uses the screenshot-basic resource (if present) to capture a
     client's screen on detection and post it to Discord.
       Requires: https://github.com/citizenfx/screenshot-basic
     ============================================================ ]]

WG = WG or {}
WG.Screenshot = {}

local hasScreenshotBasic = GetResourceState('screenshot-basic') == 'started'

function WG.Screenshot.capture(src, detectionName)
    if not Config.Screenshots.Enabled then return end
    if GetResourceState('screenshot-basic') ~= 'started' then
        WG.warn('screenshot-basic not started; skipping evidence capture')
        return
    end

    local webhook = Config.Screenshots.Webhook ~= '' and Config.Screenshots.Webhook or Config.Discord.Webhook
    if not webhook or webhook == '' then return end

    exports['screenshot-basic']:requestClientScreenshot(src, {
        encoding = 'jpg',
        quality  = Config.Screenshots.Quality
    }, function(err, data)
        if err then
            WG.warn('screenshot failed: ' .. tostring(err))
            return
        end
        -- data is a data URL; post to Discord as an embed with image
        local name = GetPlayerName(src) or ('id' .. src)
        PerformHttpRequest(webhook, function() end, 'POST', json.encode({
            username = Config.Discord.BotName,
            embeds = {{
                title       = 'WireGuard Evidence',
                description = ('**Player:** %s (%d)\n**Detection:** %s'):format(name, src, detectionName),
                color       = Config.Discord.Color,
                image       = { url = 'attachment://screenshot.jpg' },
                footer      = { text = 'WireGuard Anticheat' },
                timestamp   = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }}
        }), { ['Content-Type'] = 'application/json' })
    end)
end

WG.log('screenshot module loaded (screenshot-basic=' .. tostring(hasScreenshotBasic) .. ')')
