--[[ WireGuard - Extended detections
     Additional reliable client checks (low false-positive).
     ============================================================ ]]

-- ── Native invincibility flag ──────────────────────────────
WG.Client.register(function()
    if GetPlayerInvincible(PlayerId()) then
        WG.Client.flag('InvincibleFlag', 'native invincibility flag set')
    end
end, 1500)

-- ── Blacklisted / animal player model (model swap) ─────────
local BLACKLISTED_MODELS = {
    [`a_c_shark`] = true, [`a_c_sharktiger`] = true, [`a_c_humpback`] = true,
    [`a_c_killerwhale`] = true, [`a_c_dolphin`] = true, [`a_c_fish`] = true,
    [`a_c_cow`] = true, [`a_c_deer`] = true, [`a_c_boar`] = true, [`a_c_pig`] = true,
    [`a_c_chimp`] = true, [`a_c_rhesus`] = true, [`a_c_chop`] = true,
    [`a_c_rat`] = true, [`a_c_crow`] = true, [`a_c_cormorant`] = true, [`a_c_chickenhawk`] = true,
    [`slod_human`] = true, [`slod_large_quadped`] = true, [`slod_small_quadped`] = true,
}
WG.Client.register(function()
    if BLACKLISTED_MODELS[GetEntityModel(PlayerPedId())] then
        WG.Client.flag('PlayerModel', 'blacklisted ped model')
    end
end, 2000)

-- ── Vehicle speed hack (faster than physically possible) ───
WG.Client.register(function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end
    local speed    = GetEntitySpeed(veh)                 -- m/s
    local maxSpeed = GetVehicleEstimatedMaxSpeed(veh)    -- m/s
    -- generous margin so boost/downhill never trips it
    if maxSpeed > 1.0 and speed > (maxSpeed * 1.6 + 8.0) then
        WG.Client.flag('VehicleSpeedHack', ('veh speed %.1f > plausible %.1f m/s'):format(speed, maxSpeed))
    end
end, 1000)

-- ── Vehicle godmode (health never drops after being shot) ──
local vgTicks = 0
WG.Client.register(function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then vgTicks = 0; return end
    if HasEntityBeenDamagedByAnyPed(veh) then
        if GetVehicleBodyHealth(veh) >= 1000.0 and GetVehicleEngineHealth(veh) >= 1000.0 then
            vgTicks = vgTicks + 1
            if vgTicks >= 6 then
                WG.Client.flag('VehicleGodMode', 'vehicle health never drops after damage')
                vgTicks = 0
            end
        else
            vgTicks = 0
        end
        ClearEntityLastDamageEntity(veh)
    end
end, 1000)

-- ── Modified magazine size (clip larger than stock max) ────
WG.Client.register(function()
    local ped = PlayerPedId()
    local okw, weapon = GetCurrentPedWeapon(ped, true)
    if not okw or not weapon or weapon == `WEAPON_UNARMED` then return end
    local okc, clip = GetAmmoInClip(ped, weapon)
    local maxClip   = GetMaxAmmoInClip(ped, weapon, true)
    if okc and maxClip and maxClip > 0 and clip > (maxClip + 1) then
        WG.Client.flag('WeaponClipMod', ('clip %d > stock max %d'):format(clip, maxClip))
    end
end, 1200)

-- ── Ragdoll permanently disabled (optional, off by default) ─
WG.Client.register(function()
    if not CanPedRagdoll(PlayerPedId()) then
        WG.Client.flag('NoRagdoll', 'ragdoll permanently disabled')
    end
end, 2500)

WG.log('extended detections loaded')
