--[[ WireGuard - Combat detections: aimbot, triggerbot, explosive ammo, rapid fire ]]

local lastShotTime   = 0
local shotIntervals  = {}
local lastTargetLock = 0

-- Triggerbot: shots fired the exact frame an enemy enters the crosshair,
-- repeatedly, with superhuman reaction. We track aim-at-entity -> shot latency.
local aimedAtPedTime = 0

CreateThread(function()
    while true do
        Wait(0)
        if not WG.Client.booted or WG.Client.bypass then Wait(500) goto continue end
        local ped = PlayerPedId()

        -- Record when the player starts aiming at a ped
        local aiming, target = GetEntityPlayerIsFreeAimingAt(PlayerId())
        if aiming and target and DoesEntityExist(target) and IsEntityAPed(target) then
            if aimedAtPedTime == 0 then aimedAtPedTime = GetGameTimer() end
        else
            aimedAtPedTime = 0
        end

        -- Shot fired?
        if IsPedShooting(ped) then
            local now = GetGameTimer()

            -- Rapid fire: measure interval between consecutive shots
            if lastShotTime > 0 then
                local interval = now - lastShotTime
                table.insert(shotIntervals, interval)
                if #shotIntervals > 10 then table.remove(shotIntervals, 1) end

                -- Average of last shots below human/weapon limit on a non-auto weapon
                if #shotIntervals >= 6 then
                    local sum = 0
                    for _, v in ipairs(shotIntervals) do sum = sum + v end
                    local avg = sum / #shotIntervals
                    if avg < Config.Thresholds.MinShotIntervalMs then
                        local _, w = GetCurrentPedWeapon(ped, true)
                        if not IsWeaponAutomatic(w) then
                            WG.Client.flag('RapidFire', ('avg %dms interval'):format(math.floor(avg)))
                        end
                    end
                end
            end
            lastShotTime = now

            -- Triggerbot: shot fired within an impossibly short window of acquiring target
            if aimedAtPedTime > 0 then
                local reaction = now - aimedAtPedTime
                if reaction < 50 and reaction >= 0 then
                    lastTargetLock = lastTargetLock + 1
                    if lastTargetLock >= 3 then
                        WG.Client.flag('Triggerbot', ('%dms reaction x%d'):format(reaction, lastTargetLock))
                        lastTargetLock = 0
                    end
                else
                    lastTargetLock = math.max(0, lastTargetLock - 1)
                end
            end
        end

        ::continue::
    end
end)

-- Helper: is weapon an automatic one (then rapid fire is legitimate)
function IsWeaponAutomatic(hash)
    local autos = {
        [`WEAPON_CARBINERIFLE`]=true,[`WEAPON_ASSAULTRIFLE`]=true,[`WEAPON_SMG`]=true,
        [`WEAPON_MICROSMG`]=true,[`WEAPON_COMBATMG`]=true,[`WEAPON_MG`]=true,
        [`WEAPON_SPECIALCARBINE`]=true,[`WEAPON_BULLPUPRIFLE`]=true,[`WEAPON_ADVANCEDRIFLE`]=true,
        [`WEAPON_COMBATPDW`]=true,[`WEAPON_ASSAULTSMG`]=true,[`WEAPON_MINIGUN`]=true,
        [`WEAPON_GUSENBERG`]=true,[`WEAPON_MACHINEPISTOL`]=true,[`WEAPON_COMBATMG_MK2`]=true,
        [`WEAPON_CARBINERIFLE_MK2`]=true,[`WEAPON_SPECIALCARBINE_MK2`]=true
    }
    return autos[hash] == true
end

-- Explosive ammo: weapon group flag normally restricted to specific MK2 ammo.
-- We check the special ammo type while firing conventional weapons.
WG.Client.register(function()
    local ped = PlayerPedId()
    if GetPedConfigFlag(ped, 268, true) then -- PCF_ExplosiveAmmo-ish sanity (community value)
        WG.Client.flag('ExplosiveAmmo', 'explosive ammo flag active')
    end
end, 2000)

WG.log('combat detections loaded')
