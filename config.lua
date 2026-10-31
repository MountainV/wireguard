--[[ ============================================================
     WireGuard - Configuration
     Edit these values to tune the anticheat for your server.
   ============================================================ ]]

Config = {}

-- ─────────────────────────────────────────────
--  GENERAL
-- ─────────────────────────────────────────────
Config.Debug            = false          -- Print verbose debug output to console
Config.ServerName       = 'MountainV'
Config.CheckIntervalMs  = 1000           -- Base loop interval for most detections (ms)
Config.Locale           = 'de'

-- Grace period (seconds) after a player joins during which detections will
-- NOT punish. Prevents false bans/kicks while the client & world are still
-- loading (spawn teleport, speed spikes, temporary godmode, etc.). 0 = off.
Config.JoinGracePeriod  = 45

-- Default punishment applied when a detection has no specific action set.
-- Options: 'ban' | 'kick' | 'warn' | 'none'
Config.DefaultAction    = 'ban'

Config.KickMessage      = '🛡️ MountainV Anticheat\nDu wurdest vom Server entfernt.\nBei Fragen wende dich an unser Support-Team.'
Config.BanMessage       = '🛡️ MountainV Anticheat\n\nDu wurdest dauerhaft von MountainV gesperrt.\n\nBan-ID: %s\n\nSolltest du der Meinung sein, dass dies ein Fehler ist, eröffne mit deiner Ban-ID ein Ticket in unserem Discord.'

-- ─────────────────────────────────────────────
--  ADMINS / WHITELIST
--  Admins bypass detections and can open the in-game menu.
--  Use the player's license identifier (license:xxxxxxxx...)
-- ─────────────────────────────────────────────
Config.Admins = {
    -- ['license:0000000000000000000000000000000000000000'] = true,
}

-- ACE permission that also grants admin (works with txAdmin / vMenu ACEs)
Config.AdminAcePermission = 'wireguard.admin'

-- ─────────────────────────────────────────────
--  WHITELIST (role / group based)
--  Players in any of these groups are FULLY excluded from all
--  anticheat detections (they still can't open the admin menu
--  unless they are also an admin).
--
--  Detection of a player's group works via (in order):
--    1) a framework export you register:
--         exports.wireguard:setPlayerGroup(src, 'administrator')
--       or use the provided export from your framework resource.
--    2) ACE permissions: group.<name> OR wireguard.<name>
--       e.g. add_ace group.administrator wireguard.whitelist allow
--    3) the `rank` column of wireguard_admins (if DB enabled)
-- ─────────────────────────────────────────────
Config.Whitelist = {
    Enabled  = true,
    Groups   = {
        'supporter',
        'moderator',
        'administrator',
        'verwaltung',
        'dev',
        'leitung'
    },
    CheckAce = true    -- also check ACE perms group.<name> / wireguard.<name>
}

-- Key to open the in-game admin menu (default F6 = 167)
Config.MenuKey          = 167

-- ─────────────────────────────────────────────
--  DISCORD LOGGING
-- ─────────────────────────────────────────────
Config.Discord = {
    Enabled    = false,
    Webhook    = '',                    -- Discord webhook URL for detection logs
    BanWebhook = '',                    -- Separate webhook for bans (optional, falls back to Webhook)
    BotName    = 'WireGuard',
    Avatar     = 'https://i.imgur.com/0000000.png',
    Color      = 15158332               -- Red
}

-- ─────────────────────────────────────────────
--  SCREENSHOT EVIDENCE (requires screenshot-basic resource)
-- ─────────────────────────────────────────────
Config.Screenshots = {
    Enabled = false,
    OnDetection = true,                 -- Capture screenshot when a player is flagged
    Webhook = '',                       -- Discord webhook to post screenshots
    Quality = 0.85
}

-- ─────────────────────────────────────────────
--  DATABASE (MySQL via oxmysql)
--  When enabled, bans + detection history + admins + logs are
--  stored in MySQL. Requires the `oxmysql` resource to be started
--  BEFORE wireguard. Tables are auto-created on first start.
--  If disabled, WireGuard falls back to data/bans.json.
-- ─────────────────────────────────────────────
Config.Database = {
    Enabled        = false,   -- set true to use MySQL (oxmysql)
    LogDetections  = true,    -- persist every detection to wireguard_detections
    AutoCreateTables = true,  -- run schema.sql on start
    SyncAdmins     = true     -- also treat wireguard_admins rows as admins
}

-- ─────────────────────────────────────────────
--  WEB PANEL API
--  The included web-panel/ Node app talks to this endpoint.
-- ─────────────────────────────────────────────
Config.WebPanel = {
    Enabled = true
}

-- ─────────────────────────────────────────────
--  TRUST SCORE
--  Players start at 100. Detections subtract points.
--  Below the ban threshold => automatic action.
-- ─────────────────────────────────────────────
Config.TrustScore = {
    Enabled   = true,
    Start     = 100,
    BanBelow  = 0
}

--[[ ============================================================
     DETECTION MODULES
     Each entry:
       enabled  = turn the check on/off
       action   = 'ban' | 'kick' | 'warn' | 'none' (overrides DefaultAction)
       penalty  = trust score points removed when flagged
     ============================================================ ]]
Config.Detections = {
    -- Combat / aimbot
    Aimbot            = { enabled = true,  action = 'ban',  penalty = 100 },
    Triggerbot        = { enabled = true,  action = 'ban',  penalty = 100 },
    ExplosiveAmmo     = { enabled = true,  action = 'ban',  penalty = 100 },
    RapidFire         = { enabled = true,  action = 'kick', penalty = 50  },

    -- Player state
    GodMode           = { enabled = true,  action = 'ban',  penalty = 100 },
    Invisible         = { enabled = true,  action = 'kick', penalty = 60  },
    SuperJump         = { enabled = true,  action = 'kick', penalty = 40  },
    FastRun           = { enabled = true,  action = 'kick', penalty = 40  },
    FastSwim          = { enabled = true,  action = 'kick', penalty = 40  },
    NoClip            = { enabled = true,  action = 'ban',  penalty = 100 },
    SpeedHack         = { enabled = true,  action = 'kick', penalty = 60  },
    Teleport          = { enabled = true,  action = 'kick', penalty = 70  },
    Ragdoll           = { enabled = false, action = 'warn', penalty = 20  },

    -- Spawning
    SpawnVehicle      = { enabled = true,  action = 'kick', penalty = 60  },
    SpawnObject       = { enabled = true,  action = 'kick', penalty = 60  },
    SpawnPed          = { enabled = true,  action = 'kick', penalty = 60  },
    SpawnLimit        = { enabled = true,  action = 'kick', penalty = 40  }, -- too many entities in a short time

    -- Weapons
    GiveWeapon        = { enabled = true,  action = 'ban',  penalty = 100 },
    BlacklistWeapon   = { enabled = true,  action = 'kick', penalty = 80  },
    InfiniteAmmo      = { enabled = true,  action = 'kick', penalty = 50  },
    WeaponDamageMod   = { enabled = true,  action = 'ban',  penalty = 100 },

    -- Explosions / entities
    IllegalExplosion  = { enabled = true,  action = 'ban',  penalty = 100 },
    EntitySpam        = { enabled = true,  action = 'kick', penalty = 50  },

    -- Visual
    Blips             = { enabled = false, action = 'warn', penalty = 10  },
    ExtendedRadar     = { enabled = true,  action = 'warn', penalty = 20  },
    NightVision       = { enabled = false, action = 'warn', penalty = 10  },
    ThermalVision     = { enabled = false, action = 'warn', penalty = 10  },

    -- Resources / injection
    ResourceStop      = { enabled = true,  action = 'ban',  penalty = 100 },
    ResourceStart     = { enabled = true,  action = 'ban',  penalty = 100 },
    MenuInject        = { enabled = true,  action = 'ban',  penalty = 100 },
    LuaExecutor       = { enabled = true,  action = 'ban',  penalty = 100 },

    -- Misc
    Spectate          = { enabled = false, action = 'warn', penalty = 20  },
    BlacklistCommand  = { enabled = true,  action = 'kick', penalty = 40  },
    PlayerBlips       = { enabled = false, action = 'warn', penalty = 10  },

    -- Extended checks
    VehicleGodMode    = { enabled = true,  action = 'kick', penalty = 60  }, -- invincible / self-repairing vehicle
    VehicleSpeedHack  = { enabled = true,  action = 'kick', penalty = 60  }, -- vehicle faster than physically possible
    PlayerModel       = { enabled = true,  action = 'kick', penalty = 50  }, -- player using a blacklisted/animal ped model
    InvincibleFlag    = { enabled = true,  action = 'ban',  penalty = 100 }, -- native invincibility flag set
    NoRagdoll         = { enabled = false, action = 'warn', penalty = 20  }, -- ped ragdoll permanently disabled
    WeaponClipMod     = { enabled = true,  action = 'kick', penalty = 60  }  -- magazine size beyond stock maximum
}

-- ─────────────────────────────────────────────
--  THRESHOLDS
-- ─────────────────────────────────────────────
Config.Thresholds = {
    -- Movement (m/s). Normal sprint ~ 7 m/s, fastest vehicles considered separately.
    MaxRunSpeed        = 10.0,
    MaxSwimSpeed       = 4.5,
    MaxOnFootSpeed     = 12.0,    -- teleport/speed detection on foot
    TeleportDistance   = 75.0,    -- meters moved in one tick (on foot) => teleport
    -- Spawn rate limiting
    MaxEntitiesPerSec  = 8,
    -- Health
    MaxHealth          = 200,
    MaxArmour          = 100,
    -- Rapid fire: minimum ms between shots for a semi-auto weapon
    MinShotIntervalMs  = 40
}

-- ─────────────────────────────────────────────
--  BLACKLISTS
-- ─────────────────────────────────────────────
Config.BlacklistedWeapons = {
    `WEAPON_RAILGUN`,
    `WEAPON_RPG`,
    `WEAPON_GRENADELAUNCHER`,
    `WEAPON_MINIGUN`,
    `WEAPON_RAYMINIGUN`,
    `WEAPON_STICKYBOMB`,
    `WEAPON_PROXMINE`,
    `WEAPON_FLARE`,
    `WEAPON_RAYPISTOL`,
    `WEAPON_COMPACTLAUNCHER`
}

Config.BlacklistedVehicles = {
    `rhino`,
    `khanjali`,
    `hydra`,
    `lazer`,
    `savage`,
    `oppressor`,
    `oppressor2`,
    `scramjet`,
    `thruster`,
    `deluxo`,
    `strikeforce`
}

Config.BlacklistedObjects = {
    -- model hashes of griefing props, e.g. large walls
    -- `prop_fnclink_02gate3`,
}

Config.BlacklistedCommands = {
    'quit',
    'disconnect',
    'netgraph',
    'sv_maxclients',
    'txadmin'
}

-- Explosion types that are never legitimate from a client
Config.BlacklistedExplosions = {
    [2]  = true,   -- MOLOTOV
    [4]  = true,   -- TANKSHELL
    [59] = true,   -- RAYGUN
    [60] = true,   -- BURIEDMINE
    [61] = true,   -- SCRIPT_DRONE
}

-- Resources that must never be stopped by a client (your core resources)
Config.ProtectedResources = {
    'wireguard',
    'spawnmanager',
    'sessionmanager'
}

return Config
