--[[ WireGuard - Shared utilities ]]

WG = WG or {}

function WG.log(...)
    if Config and Config.Debug then
        print('^5[WireGuard]^7', ...)
    end
end

function WG.warn(...)
    print('^3[WireGuard:WARN]^7', ...)
end

function WG.err(...)
    print('^1[WireGuard:ERROR]^7', ...)
end

-- Distance between two vector3
function WG.dist(a, b)
    return #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z))
end

-- Check table contains value
function WG.contains(t, val)
    if not t then return false end
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

-- Round number
function WG.round(n, d)
    d = d or 0
    local m = 10 ^ d
    return math.floor(n * m + 0.5) / m
end

-- Generate a pseudo-random ban id
function WG.genId(len)
    len = len or 10
    local chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'
    local id = ''
    for _ = 1, len do
        local i = math.random(1, #chars)
        id = id .. chars:sub(i, i)
    end
    return id
end

-- Safe JSON decode with fallback
function WG.jsonDecode(str, fallback)
    if not str or str == '' then return fallback end
    local ok, res = pcall(json.decode, str)
    if ok and res ~= nil then return res end
    return fallback
end
