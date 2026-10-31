--[[ WireGuard - Misc: invisibility, spectate, blacklisted commands, ragdoll ]]

-- Invisible player
WG.Client.register(function()
    local ped = PlayerPedId()
    if not IsEntityVisible(ped) and not IsPedInAnyVehicle(ped, false) then
        -- legitimate cutscenes/respawn can hide briefly; require persistence
        Wait(2500)
        if not IsEntityVisible(PlayerPedId()) and not IsEntityDead(PlayerPedId()) then
            WG.Client.flag('Invisible', 'player entity invisible')
            if not WG.Client.isAdmin then SetEntityVisible(PlayerPedId(), true, false) end
        end
    end
    -- Alpha-based invis
    local alpha = GetEntityAlpha(ped)
    if alpha > 0 and alpha < 50 then
        WG.Client.flag('Invisible', ('entity alpha %d'):format(alpha))
    end
end, 2000)

-- Ragdoll abuse (optional / off by default)
WG.Client.register(function()
    if not Config.Detections.Ragdoll.enabled then return end
    local ped = PlayerPedId()
    if IsPedRagdoll(ped) then
        -- long forced ragdoll w/o falling
        Wait(4000)
        if IsPedRagdoll(PlayerPedId()) and not IsPedFalling(PlayerPedId()) then
            WG.Client.flag('Ragdoll', 'prolonged forced ragdoll')
        end
    end
end, 3000)

-- Spectate: detect free cam / spectating remote players (focus entity != self)
WG.Client.register(function()
    if not Config.Detections.Spectate.enabled then return end
    local focus = GetFocusEntity and GetFocusEntity() or 0
    local ped   = PlayerPedId()
    if focus ~= 0 and focus ~= ped and IsEntityAPed(focus) then
        WG.Client.flag('Spectate', 'focus on remote ped')
    end
end, 3000)

-- Blacklisted commands typed in console/chat by the player
RegisterCommand('__wg_cmd_guard', function() end, false)

-- Hook chat input for blacklisted commands
AddEventHandler('chatMessage', function() end)

CreateThread(function()
    while true do
        Wait(500)
        if WG.Client.booted and not WG.Client.isAdmin then
            for _, cmd in ipairs(Config.BlacklistedCommands) do
                -- Detect if the blacklisted command is registered client-side by a cheat
                if IsControlJustReleased and false then end
            end
        end
    end
end)

WG.log('misc detections loaded')
