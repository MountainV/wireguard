--[[ WireGuard - Spawn protection: vehicles, objects, peds + rate limiting
     Detects entities the local player created and reports blacklisted /
     excessive spawns. Server-side also validates entity creation.          ]]

local spawnTimestamps = {}

local function registerSpawn()
    local now = GetGameTimer()
    table.insert(spawnTimestamps, now)
    -- drop entries older than 1s
    for i = #spawnTimestamps, 1, -1 do
        if now - spawnTimestamps[i] > 1000 then table.remove(spawnTimestamps, i) end
    end
    if #spawnTimestamps > Config.Thresholds.MaxEntitiesPerSec then
        WG.Client.flag('SpawnLimit', ('%d entities/sec'):format(#spawnTimestamps))
    end
end

-- Watch vehicles owned by local player
WG.Client.register(function()
    local playerPed = PlayerPedId()
    for veh in EnumerateVehicles() do
        if NetworkGetEntityOwner(veh) == PlayerId() and DoesEntityExist(veh) then
            local model = GetEntityModel(veh)
            if WG.contains(Config.BlacklistedVehicles, model) then
                WG.Client.flag('SpawnVehicle', ('blacklisted veh %s'):format(GetDisplayNameFromVehicleModel(model)))
                if not WG.Client.isAdmin then
                    DeleteEntity(veh)
                end
            end
        end
    end
end, 1500)

-- Watch objects created near the player that we own
WG.Client.register(function()
    for obj in EnumerateObjects() do
        if NetworkGetEntityOwner(obj) == PlayerId() then
            local model = GetEntityModel(obj)
            if WG.contains(Config.BlacklistedObjects, model) then
                WG.Client.flag('SpawnObject', ('blacklisted object %d'):format(model))
                if not WG.Client.isAdmin then DeleteEntity(obj) end
            end
        end
    end
end, 2000)

-- Hook CreateVehicle / CreateObject / CreatePed indirectly is not possible in
-- client Lua; instead we count net entity creation bursts via enumeration deltas.
local knownVehicles = 0
WG.Client.register(function()
    local count = 0
    for _ in EnumerateVehicles() do count = count + 1 end
    if count > knownVehicles then
        for _ = 1, (count - knownVehicles) do registerSpawn() end
    end
    knownVehicles = count
end, 1000)

-- ─────────────────────────────────────────────
--  Entity enumerators (standard FiveM pattern)
-- ─────────────────────────────────────────────
local function enumerate(initFunc, moveFunc, disposeFunc)
    return coroutine.wrap(function()
        local iter, id = initFunc()
        if not id or id == 0 then disposeFunc(iter) return end
        local ok = true
        repeat
            coroutine.yield(id)
            ok, id = moveFunc(iter)
        until not ok
        disposeFunc(iter)
    end)
end

function EnumerateVehicles()
    return enumerate(FindFirstVehicle, FindNextVehicle, EndFindVehicle)
end

function EnumerateObjects()
    return enumerate(FindFirstObject, FindNextObject, EndFindObject)
end

function EnumeratePeds()
    return enumerate(FindFirstPed, FindNextPed, EndFindPed)
end

WG.log('spawn detections loaded')
