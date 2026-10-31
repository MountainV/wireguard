--[[ ============================================================
     WireGuard - In-game Admin Menu (NUI)
     Opens with Config.MenuKey (admins only). Lets admins:
       - view online players, trust scores, flags
       - kick / ban / warn / spectate / teleport
       - view live detection feed
     ============================================================ ]]

local menuOpen = false

local function openMenu()
    if not WG.Client.isAdmin then return end
    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', serverName = Config.ServerName })
    TriggerServerEvent(WG.Events.AdminAction, 'getPlayers')
end

local function closeMenu()
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- Open menu on key press
CreateThread(function()
    while true do
        Wait(0)
        if WG.Client.isAdmin then
            if IsControlJustReleased(0, Config.MenuKey) then
                if menuOpen then closeMenu() else openMenu() end
            end
        else
            Wait(1000)
        end
    end
end)

RegisterCommand('wireguard', function() openMenu() end, false)
RegisterCommand('wg', function() openMenu() end, false)

-- NUI callbacks --------------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    closeMenu(); cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    TriggerServerEvent(WG.Events.AdminAction, 'getPlayers')
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    -- data = { type='kick'|'ban'|'warn'|'spectate'|'tp'|'tphere', target=serverId, reason='' }
    TriggerServerEvent(WG.Events.AdminAction, data.type, data.target, data.reason)
    cb({ ok = true })
end)

-- Receive player list / feed from server
RegisterNetEvent(WG.Events.AdminData, function(payload)
    if not menuOpen then return end
    SendNUIMessage({ action = 'data', payload = payload })
end)

-- Spectate handling (client side) -------------------------------------------
local spectating = false
RegisterNetEvent('wireguard:spectate', function(targetCoords)
    spectating = not spectating
    local ped = PlayerPedId()
    if spectating and targetCoords then
        NetworkSetInSpectatorMode(true, ped)
        SetEntityCoords(ped, targetCoords.x, targetCoords.y, targetCoords.z + 1.0)
    else
        NetworkSetInSpectatorMode(false, ped)
    end
end)

RegisterNetEvent('wireguard:teleport', function(coords)
    local ped = PlayerPedId()
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, true)
end)

-- Admin: heal / kill / freeze / message (applied on the target client) ------
RegisterNetEvent('wireguard:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
end)

RegisterNetEvent('wireguard:kill', function()
    SetEntityHealth(PlayerPedId(), 0)
end)

RegisterNetEvent('wireguard:freeze', function(unfreeze)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, not unfreeze)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(unfreeze and 'Du wurdest entfrozen.' or 'Du wurdest eingefroren.')
    EndTextCommandDisplayHelp(0, false, true, 4000)
end)

RegisterNetEvent('wireguard:message', function(msg)
    SetNotificationTextEntry('STRING')
    AddTextComponentSubstringPlayerName('~b~[WireGuard]~w~ ' .. (msg or ''))
    DrawNotification(false, true)
end)

WG.log('NUI admin menu loaded')
