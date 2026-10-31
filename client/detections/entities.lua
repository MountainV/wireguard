--[[ WireGuard - Entity & explosion protection ]]

-- Illegal explosions: hook the game's explosion event via gameEventTriggered.
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    -- args: victim, attacker, ...isDead, weaponHash, ...
end)

-- Listen for explosions through CEventExplosion via the explosionEvent net event.
AddEventHandler('explosionEvent', function(sender, ev)
    if WG.Client.bypass then return end
    local expType = ev.explosionType
    if Config.BlacklistedExplosions[expType] then
        WG.Client.flag('IllegalExplosion', ('explosion type %d'):format(expType))
    end
    -- Explosion spam: many explosions from same sender in short time handled server-side too
end)

-- Entity spam: too many networked entities owned by local player
WG.Client.register(function()
    local owned = 0
    for veh in EnumerateVehicles() do
        if NetworkGetEntityOwner(veh) == PlayerId() then owned = owned + 1 end
    end
    for ped in EnumeratePeds() do
        if NetworkGetEntityOwner(ped) == PlayerId() and ped ~= PlayerPedId() then owned = owned + 1 end
    end
    for obj in EnumerateObjects() do
        if NetworkGetEntityOwner(obj) == PlayerId() then owned = owned + 1 end
    end
    if owned > 40 then
        WG.Client.flag('EntitySpam', ('%d owned entities'):format(owned))
    end
end, 3000)

WG.log('entity detections loaded')
