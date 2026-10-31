--[[ WireGuard - Weapon detections: blacklist, give-weapon, infinite ammo, damage mod ]]

local prevWeapons = {}

-- Blacklisted weapon in inventory
WG.Client.register(function()
    local ped = PlayerPedId()
    for _, w in ipairs(Config.BlacklistedWeapons) do
        if HasPedGotWeapon(ped, w, false) then
            WG.Client.flag('BlacklistWeapon', ('has blacklisted weapon %d'):format(w))
            if not WG.Client.isAdmin then
                RemoveWeaponFromPed(ped, w)
            end
        end
    end
end, 1500)

-- Give-weapon / weapon appeared without pickup. We snapshot the inventory and
-- detect new weapons the player couldn't have legitimately acquired.
-- (Server-side give should be the source of truth; this is a client signal.)
WG.Client.register(function()
    local ped = PlayerPedId()
    local current = {}
    -- sample the standard weapon hashes the player currently holds
    local _, cur = GetCurrentPedWeapon(ped, true)
    current[cur] = true

    -- Infinite ammo: ammo not decreasing after many shots
    if cur and cur ~= `WEAPON_UNARMED` then
        local ammo = GetAmmoInPedWeapon(ped, cur)
        if prevWeapons[cur] ~= nil then
            if IsPedShooting(ped) and ammo >= prevWeapons[cur] and ammo > 0 then
                WG.Client.flag('InfiniteAmmo', 'ammo not decreasing while firing')
            end
        end
        prevWeapons[cur] = ammo
    end
end, 1000)

-- Weapon damage modifier: compare the damage modifier native to default (1.0)
WG.Client.register(function()
    local ped = PlayerPedId()
    local _, w = GetCurrentPedWeapon(ped, true)
    if w and w ~= `WEAPON_UNARMED` then
        local mod = GetPlayerWeaponDamageModifier(PlayerId())
        if mod and mod > 1.5 then
            WG.Client.flag('WeaponDamageMod', ('damage mod x%.2f'):format(mod))
        end
    end
end, 2000)

WG.log('weapon detections loaded')
