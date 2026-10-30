-- Shared stubs for spinouts.test.lua and camweight.test.lua.
-- Minimal FiveM client mock for headless runs of a vi_extras feature (fengari, Lua 5.3).
-- Run from the vi_extras folder with luarun.js. Provides vector3, a frame scheduler,
-- require for '<folder>.<file>', and a `calls` log of the natives a test cares about.
local H = {}

local V = {}
V.__index = V
local function vec(x, y, z) return setmetatable({ x = x + 0.0, y = y + 0.0, z = z + 0.0 }, V) end
V.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
V.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__mul = function(a, b)
    if type(a) == 'number' then a, b = b, a end
    return vec(a.x * b, a.y * b, a.z * b)
end
V.__div = function(a, b) return vec(a.x / b, a.y / b, a.z / b) end
V.__unm = function(a) return vec(-a.x, -a.y, -a.z) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
V.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
vector3 = vec
H.vec = vec

H.now = 0
H.frameMs = 1000 / 60
H.calls = {}
function H.log(name, ...) H.calls[#H.calls + 1] = { name = name, args = { ... } } end
function H.find(name, from)
    local out = {}
    for i = from or 1, #H.calls do
        if H.calls[i].name == name then out[#out + 1] = H.calls[i] end
    end
    return out
end

-- threads
local threads = {}
function CreateThread(fn)
    threads[#threads + 1] = { co = coroutine.create(fn), wake = H.now }
end
Citizen = { CreateThread = CreateThread }
function Wait(ms) coroutine.yield(ms or 0) end
function GetGameTimer() return math.floor(H.now) end
function H.frame()
    H.now = H.now + H.frameMs
    for _, t in ipairs(threads) do
        if coroutine.status(t.co) ~= 'dead' and H.now >= t.wake then
            local ok, ms = coroutine.resume(t.co)
            if not ok then error(ms) end
            t.wake = H.now + (ms or 0)
        end
    end
end
function H.run(ms) local stop = H.now + ms while H.now < stop do H.frame() end end

-- events
local handlers = {}
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {} table.insert(handlers[name], fn) end
function H.trigger(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
function GetCurrentResourceName() return 'vi_extras' end
H.resources = {}
function GetResourceState(r) return H.resources[r] or 'missing' end

-- kvp
local kvp = {}
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end

-- require
local loaded = {}
function require(name)
    if loaded[name] ~= nil then return loaded[name] end
    local file = name:gsub('%.', '/') .. '.lua'
    local src = assert(readfile(file), 'no file ' .. file)
    local value = assert(load(src, '@' .. file))()
    loaded[name] = value == nil and true or value
    return loaded[name]
end
function H.forget(name) loaded[name] = nil end

function H.load(file)
    local src = assert(readfile(file), 'no file ' .. file)
    assert(load(src, '@' .. file))()
end

-- statebags, cache
LocalPlayer = { state = {} }
cache = { ped = 1 }
exports = setmetatable({}, { __index = function(_, res) return H.exports and H.exports[res] end })

return H
