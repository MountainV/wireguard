--[[ WireGuard - Resource & injection protection
     Detects stopped protected resources, injected menus and lua executors.    ]]

-- Protected resource stopped on the client (common with menu "resource stoppers")
WG.Client.register(function()
    for _, res in ipairs(Config.ProtectedResources) do
        local state = GetResourceState(res)
        if state == 'stopped' or state == 'missing' then
            WG.Client.flag('ResourceStop', ('protected resource %s is %s'):format(res, state))
        end
    end
end, 2000)

-- Detect unexpected resources that appeared client-side (injected menus register
-- resources sometimes). Snapshot known resources and watch for additions.
local knownResources = {}
local initialized = false

WG.Client.register(function()
    local count = GetNumResources()
    if not initialized then
        for i = 0, count - 1 do
            knownResources[GetResourceByFindIndex(i)] = true
        end
        initialized = true
        return
    end
    for i = 0, count - 1 do
        local r = GetResourceByFindIndex(i)
        if r and not knownResources[r] then
            knownResources[r] = true
            WG.Client.flag('ResourceStart', ('new resource appeared: %s'):format(r))
        end
    end
end, 2500)

-- Lua executor / menu globals heuristic: known cheat global tables / functions.
-- Many injected menus leave recognizable globals. This is a best-effort signal.
local suspiciousGlobals = {
    'Lynx', 'Eulen', 'Redengine', 'Hammafia', 'Tsunami',
    'd0pamine', 'Absolute', 'Impulse', 'DopeMenu', 'cheat',
    'executor', 'hook', 'triggerbot', '__INJECTED__'
}

WG.Client.register(function()
    for _, g in ipairs(suspiciousGlobals) do
        if _G[g] ~= nil then
            WG.Client.flag('MenuInject', ('suspicious global: %s'):format(g))
        end
    end
    -- Native call overrides: some executors replace common natives
    if type(TriggerServerEvent) ~= 'function' then
        WG.Client.flag('LuaExecutor', 'TriggerServerEvent overridden')
    end
end, 3000)

WG.log('resource detections loaded')
