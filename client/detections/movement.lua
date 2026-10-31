--[[ WireGuard - Movement: speedhack, teleport, noclip, superjump, fastrun/swim ]]

local lastCoords = nil
local lastTime   = 0

WG.Client.register(function()
    local ped    = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local now    = GetGameTimer()
    local inVeh  = IsPedInAnyVehicle(ped, false)

    if lastCoords and lastTime > 0 then
        local dt = (now - lastTime) / 1000.0
        if dt > 0 then
            local d     = #(coords - lastCoords)
            local speed = d / dt   -- m/s

            -- Teleport: large jump while on foot and not falling / in vehicle
            if not inVeh and d > Config.Thresholds.TeleportDistance
               and not IsPedFalling(ped) and not IsPedRagdoll(ped) then
                WG.Client.flag('Teleport', ('%.1fm in %.2fs'):format(d, dt))
            end

            -- On-foot speed hack
            if not inVeh and not IsPedFalling(ped) and not IsPedRagdoll(ped) then
                if speed > Config.Thresholds.MaxOnFootSpeed then
                    WG.Client.flag('SpeedHack', ('%.1f m/s on foot'):format(speed))
                end
            end
        end
    end

    lastCoords = coords
    lastTime   = now
end, 500)

-- Super jump
WG.Client.register(function()
    local pid = PlayerId()
    if GetPlayerHasReserveParachute == nil then end
    -- Super jump is a stat/flag; detect by jump height over short time
    local ped = PlayerPedId()
    if IsPedJumping(ped) then
        local z0 = GetEntityCoords(ped).z
        Wait(600)
        local z1 = GetEntityCoords(ped).z
        if (z1 - z0) > 3.5 and not IsPedInAnyVehicle(ped, false) then
            WG.Client.flag('SuperJump', ('+%.1fm jump'):format(z1 - z0))
        end
    end
end, 300)

-- Fast run / swim via movement rate multiplier
WG.Client.register(function()
    local pid = PlayerId()
    local run = GetRunSprintMultiplierForPlayer and 1.0 or 1.0
    -- There's no direct getter; infer from actual sprint speed
    local ped = PlayerPedId()
    if IsPedRunning(ped) or IsPedSprinting(ped) then
        local vel = GetEntityVelocity(ped)
        local spd = math.sqrt(vel.x^2 + vel.y^2)
        if not IsPedInAnyVehicle(ped, false) and not IsPedSwimming(ped) then
            if spd > Config.Thresholds.MaxRunSpeed then
                WG.Client.flag('FastRun', ('%.1f m/s'):format(spd))
            end
        elseif IsPedSwimming(ped) then
            if spd > Config.Thresholds.MaxSwimSpeed then
                WG.Client.flag('FastSwim', ('%.1f m/s'):format(spd))
            end
        end
    end
end, 800)

-- NoClip: ped is not in a vehicle, collision disabled and moving through air,
-- or frozen+translating. Heuristic: not ragdolling/falling, collisions off.
WG.Client.register(function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end

    local collisionOff = not GetEntityCollisionDisabled(ped) -- true means collision ENABLED
    if GetEntityCollisionDisabled(ped) and not IsPedFalling(ped) then
        -- moving while collisions disabled on foot => noclip
        local vel = GetEntityVelocity(ped)
        local spd = math.sqrt(vel.x^2 + vel.y^2 + vel.z^2)
        if spd > 1.0 then
            WG.Client.flag('NoClip', 'collision disabled while moving')
        end
    end
end, 700)

WG.log('movement detections loaded')
