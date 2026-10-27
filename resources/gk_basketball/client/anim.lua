--[[
    Animations from a streamed pack, where there is one.

    The base game has no basketball animations, so Config.Anims is base-game
    clips pressed into service (an overhand throw for a shot, and so on). A
    separate resource can stream real ones: a jump shot, a chest pass, a dribble
    for every pace from standing to a sprint. It ships a clip_index.lua that
    maps names like `jumpshot` to its clips, with the things only it knows: how
    long each clip is, when in it the ball leaves the hand, and for a dribble
    when each bounce is let go, lands and is caught.

    This file reads that index and answers the rest of the client's questions:
    "what do I play for this action, and when does the ball leave?", "what does
    somebody dribbling at this pace look like?", "how do they stand with the
    ball in both hands?". With no pack running the answers are Config.Anims and
    Config.Shot.windUp, exactly as before, and no dribble cycles at all.
]]

BB.anim = {}

local M = BB.moves

local index = nil
local gaits = nil       -- false once looked for and not found
local stance = nil

local function loadIndex()
    index, gaits, stance = nil, nil, nil

    local pack = Config.Anims.pack
    if not pack or GetResourceState(pack) ~= 'started' then return end

    local raw = LoadResourceFile(pack, 'clip_index.lua')
    if not raw then return end

    local chunk, err = load(raw, '@' .. pack .. '/clip_index.lua', 't', {})
    if not chunk then
        print(('^1[gk_basketball]^7 could not read %s/clip_index.lua: %s'):format(pack, err))
        return
    end

    local ok, result = pcall(chunk)
    if not ok or type(result) ~= 'table' then return end

    index = result

    local n = 0
    for _ in pairs(index) do n = n + 1 end
    print(('^2[gk_basketball]^7 animation pack %s: %d clips'):format(pack, n))
end

--- A pack clip by its name in the pack, if the pack has it and is sure enough
--- about what it is. The pack's clips were identified by their motion, not by
--- name, and each carries how confident that identification is.
local function clip(name)
    local entry = index and name and index[name]
    if not entry then return nil end

    if entry.confidence == 'low' and not Config.Anims.useLowConfidence then return nil end

    return entry
end

local function ms(seconds)
    return seconds and math.floor(seconds * 1000.0) or nil
end

--[[
    What to play for an action, and when the ball leaves the hand.

    `key` is a Config.Anims key (shoot, pass, pickup, stow, steal, contest).
    Returns an entry in Config.Anims' own shape, the release time in ms (nil if
    the action has none or the pack doesn't say), the clip's length in ms, and
    a table of whatever else the pack knows about it, all in ms: `land` (feet
    back on the floor after a jump), `catch` (hands on the ball).
]]
--- @return table|false|nil cfg, number|nil releaseMs, number|nil lengthMs, table|nil marks
function BB.anim.action(key)
    -- A pack clip is named either plainly, or with how to play it:
    -- { clip = 'def_contest_2', flag = 49, duration = 1100 }.
    local spec = Config.Anims.packClips[key]
    local name = type(spec) == 'table' and spec.clip or spec
    local entry = clip(name)

    if entry then
        local length = ms(entry.duration)
        local how = type(spec) == 'table' and spec or {}

        return {
            dict = entry.dict,
            name = entry.clip,
            -- Unless told otherwise a real clip is the whole body, played once through.
            flag = how.flag or 0,
            duration = how.duration or length or -1,
        }, ms(entry.release), length, {
            takeoff = ms(entry.takeoff), land = ms(entry.land), catch = ms(entry.catch),
        }
    end

    return Config.Anims[key], nil, nil, nil
end

--[[
    The dribble, as the pack has it: one cycle for each pace, slowest first.

    Each is { dict, name, duration, bounces, speed, hand }. `speed` is the pace
    the cycle was made at, metres a second, 0 for the one that stands still;
    `bounces` is every bounce in the loop as the seconds at which the hand lets
    go, the ball meets the floor, and the hand has it again.

    nil when there is no pack, or it has no dribble that can be used.
]]
--- One dribble cycle from the pack, in the shape the client plays it from, or
--- nil if the pack hasn't it or it has no bounce that can be used.
local function gaitFrom(name)
    local entry = clip(name)
    if not entry or not entry.duration or entry.duration <= 0.2 then return nil end

    local bounces = M.cleanBounces(entry.bounces or (entry.bounce and { entry.bounce }), entry.duration)
    if #bounces == 0 then return nil end

    return {
        dict = entry.dict,
        name = entry.clip,
        duration = entry.duration,
        bounces = bounces,
        entry = M.entryTime(bounces, entry.duration),
        speed = entry.ground_speed or 0.0,
        hand = entry.hand == 'l' and 'l' or 'r',
    }
end

function BB.anim.gaits()
    if gaits ~= nil then return gaits or nil end

    gaits = false

    local spec = Config.Anims.packClips.dribble
    if type(spec) == 'string' then spec = { spec } end
    if type(spec) ~= 'table' then return nil end

    local list = {}

    for _, name in ipairs(spec) do
        list[#list + 1] = gaitFrom(name)
    end

    if #list == 0 then return nil end

    table.sort(list, function(a, b) return a.speed < b.speed end)

    -- Standing with a defender on you: lower, over the ball. Kept beside the
    -- list rather than in it, because it is another way of standing still, not
    -- another pace. Only any use if the list has a standing cycle to swap it for.
    local guarded = Config.Anims.packClips.guarded
    guarded = guarded and gaitFrom(type(guarded) == 'table' and guarded.clip or guarded)

    if guarded and guarded.speed <= 0.05 and list[1].speed <= 0.05 then
        list.guarded = guarded
    end

    gaits = list

    return list
end

--- Standing with the ball in both hands, looking for a shot: { dict, name }, or
--- nil without a pack.
function BB.anim.stance()
    if stance ~= nil then return stance or nil end

    local spec = Config.Anims.packClips.stance
    local entry = clip(type(spec) == 'table' and spec.clip or spec)

    stance = entry and { dict = entry.dict, name = entry.clip } or false

    return stance or nil
end

loadIndex()

AddEventHandler('onClientResourceStart', function(resource)
    if resource == Config.Anims.pack then loadIndex() end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == Config.Anims.pack then
        index, gaits, stance = nil, nil, nil
    end
end)
