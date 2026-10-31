fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'WireGuard'
author 'WireGuard'
description 'WireGuard - Advanced FiveM Anticheat & Web Admin Panel'
version '1.0.0'

-- Shared
shared_scripts {
    'shared/enums.lua',
    'shared/utils.lua',
    'config.lua'
}

-- Client
client_scripts {
    'client/main.lua',
    'client/nui.lua',
    'client/detections/aimbot.lua',
    'client/detections/godmode.lua',
    'client/detections/movement.lua',
    'client/detections/spawn.lua',
    'client/detections/weapons.lua',
    'client/detections/entities.lua',
    'client/detections/visual.lua',
    'client/detections/resources.lua',
    'client/detections/misc.lua',
    'client/detections/extra.lua'
}

-- Server
server_scripts {
    'server/sql.lua',
    'server/settings.lua',
    'server/main.lua',
    'server/bans.lua',
    'server/events.lua',
    'server/admin.lua',
    'server/screenshot.lua',
    'server/discord.lua',
    'server/api.lua'
}

-- NUI Admin Menu
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'data/bans.json'
}

-- Dependencies (optional screenshot-basic for evidence)
-- ensure screenshot-basic BEFORE this resource if you want screenshots
