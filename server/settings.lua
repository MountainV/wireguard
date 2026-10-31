--[[ ============================================================
     WireGuard - Runtime settings overlay
     Lets the web panel change configuration live, without editing
     config.lua or restarting the resource.

       - On start: load data/settings.json and merge into Config.
       - On change (POST /settings): merge into live Config, persist
         to data/settings.json, and re-sync detection config to all
         connected clients.

     The file stores the editable SUBSET of Config in this shape:
       { general = {...}, TrustScore, Thresholds, Discord,
         Screenshots, Whitelist, Detections }
     ============================================================ ]]

WG = WG or {}
WG.Settings = {}

local SETTINGS_FILE = 'data/settings.json'

-- deep merge patch into an existing table (tables merge, scalars overwrite)
local function deepMerge(target, patch)
    if type(target) ~= 'table' or type(patch) ~= 'table' then return end
    for k, v in pairs(patch) do
        if type(v) == 'table' and type(target[k]) == 'table' then
            deepMerge(target[k], v)
        else
            target[k] = v
        end
    end
end

-- apply a snapshot-shaped table onto Config
local function applyShape(data)
    if type(data) ~= 'table' then return end

    -- general.* maps to top-level Config keys
    if type(data.general) == 'table' then
        for k, v in pairs(data.general) do Config[k] = v end
    end

    for _, key in ipairs({ 'TrustScore', 'Thresholds', 'Discord', 'Screenshots', 'Whitelist' }) do
        if type(data[key]) == 'table' then
            Config[key] = Config[key] or {}
            deepMerge(Config[key], data[key])
        end
    end

    if type(data.Detections) == 'table' then
        Config.Detections = Config.Detections or {}
        for name, d in pairs(data.Detections) do
            if type(d) == 'table' then
                Config.Detections[name] = Config.Detections[name] or {}
                deepMerge(Config.Detections[name], d)
            end
        end
    end
end

-- the editable subset we expose to / accept from the panel
function WG.Settings.snapshot()
    return {
        general = {
            ServerName      = Config.ServerName,
            DefaultAction   = Config.DefaultAction,
            KickMessage     = Config.KickMessage,
            BanMessage      = Config.BanMessage,
            Debug           = Config.Debug,
            MenuKey         = Config.MenuKey,
            JoinGracePeriod = Config.JoinGracePeriod
        },
        TrustScore  = Config.TrustScore,
        Thresholds  = Config.Thresholds,
        Discord     = Config.Discord,
        Screenshots = Config.Screenshots,
        Whitelist   = Config.Whitelist,
        Detections  = Config.Detections
    }
end

-- push the live detection config + thresholds to every client
function WG.Settings.broadcast()
    TriggerClientEvent(WG.Events.Sync, -1, {
        detections = Config.Detections,
        thresholds = Config.Thresholds
    })
end

-- persist the current editable config to disk
function WG.Settings.persist()
    local ok, encoded = pcall(json.encode, WG.Settings.snapshot())
    if ok then
        SaveResourceFile(GetCurrentResourceName(), SETTINGS_FILE, encoded, -1)
    else
        WG.err('settings persist failed: ' .. tostring(encoded))
    end
end

-- apply a patch coming from the web panel (live + persist + resync)
function WG.Settings.apply(patch)
    if type(patch) ~= 'table' then return false, 'invalid payload' end
    applyShape(patch)
    WG.Settings.persist()
    WG.Settings.broadcast()
    WG.warn('settings updated from web panel')
    return true
end

-- load overrides on start
function WG.Settings.load()
    local raw  = LoadResourceFile(GetCurrentResourceName(), SETTINGS_FILE)
    local data = WG.jsonDecode(raw, nil)
    if type(data) == 'table' then
        applyShape(data)
        WG.log('runtime settings loaded from ' .. SETTINGS_FILE)
    end
end

WG.Settings.load()

-- re-sync config to a client shortly after they boot
AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(6000, function()
        if GetPlayerName(src) then
            TriggerClientEvent(WG.Events.Sync, src, {
                detections = Config.Detections,
                thresholds = Config.Thresholds
            })
        end
    end)
end)

print('^5[WireGuard]^7 settings overlay ready')
