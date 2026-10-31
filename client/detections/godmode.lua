--[[ WireGuard - Godmode / health / armour / invincibility ]]

-- Godmode via SetEntityInvincible / proofs
WG.Client.register(function()
    local ped = PlayerPedId()

    -- Entity proofs (bullet/fire/explosion/etc). Flags combine into a bitmask.
    -- A player with all proofs set is not legitimate gameplay.
    local hasProofs = GetEntityProofs and false or false
    -- Fallback manual check: take no damage while health stays max under fire
    local hp = GetEntityHealth(ped)
    local maxHp = GetEntityMaxHealth(ped)
    if hp > (maxHp + 5) or hp > Config.Thresholds.MaxHealth then
        WG.Client.flag('GodMode', ('health %d > max %d'):format(hp, maxHp))
    end

    -- Armour overflow
    local armour = GetPedArmour(ped)
    if armour > Config.Thresholds.MaxArmour then
        WG.Client.flag('GodMode', ('armour %d > %d'):format(armour, Config.Thresholds.MaxArmour))
    end
end, 1500)

-- Track sudden health regeneration while taking damage (soft godmode)
local lastHealth = 200
local regenTicks = 0
WG.Client.register(function()
    local ped = PlayerPedId()
    local hp  = GetEntityHealth(ped)

    if HasEntityBeenDamagedByAnyPed(ped) or IsPedInMeleeCombat(ped) or IsPedShooting(ped) then
        if hp >= lastHealth and hp >= GetEntityMaxHealth(ped) then
            regenTicks = regenTicks + 1
            if regenTicks >= 5 then
                WG.Client.flag('GodMode', 'health never drops under combat')
                regenTicks = 0
            end
        else
            regenTicks = 0
        end
        ClearEntityLastDamageEntity(ped)
    end
    lastHealth = hp
end, 1000)

WG.log('godmode detections loaded')
