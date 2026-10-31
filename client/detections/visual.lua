--[[ WireGuard - Visual cheats: radar, night/thermal vision, blips ]]

-- Night vision / thermal vision toggles
WG.Client.register(function()
    if GetUsingnightvision and GetUsingnightvision() then
        if Config.Detections.NightVision.enabled then
            WG.Client.flag('NightVision', 'nightvision active')
            if not WG.Client.isAdmin then SetNightvision(false) end
        end
    end
    if GetUsingseethrough and GetUsingseethrough() then
        if Config.Detections.ThermalVision.enabled then
            WG.Client.flag('ThermalVision', 'thermal vision active')
            if not WG.Client.isAdmin then SetSeethrough(false) end
        end
    end
end, 2000)

-- Extended radar / big map kept on permanently (ESP-style minimap)
local bigmapTicks = 0
WG.Client.register(function()
    if IsBigmapActive and IsBigmapActive() then
        bigmapTicks = bigmapTicks + 1
        if bigmapTicks >= 8 then  -- ~16s continuously expanded
            WG.Client.flag('ExtendedRadar', 'minimap forced expanded')
            bigmapTicks = 0
        end
    else
        bigmapTicks = 0
    end
end, 2000)

-- Player blips injected on the map (ESP). Detect blips attached to remote players.
WG.Client.register(function()
    if not Config.Detections.PlayerBlips.enabled then return end
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local ped  = GetPlayerPed(pid)
            local blip = GetBlipFromEntity(ped)
            if blip and blip ~= 0 and DoesBlipExist(blip) then
                WG.Client.flag('PlayerBlips', 'blip attached to remote player')
                break
            end
        end
    end
end, 3000)

WG.log('visual detections loaded')
