-- =============================================================================
-- Update check
-- =============================================================================
-- On start, and once a day while the server runs, asks GitHub for the
-- repository's latest release and says in the console whether this server
-- has it. One check for the whole HUD set: vice_hud is the resource every
-- server in this set runs, so its manifest carries the set's release number
-- (`release`) and where it is published (`repository`).
--
-- The release number is not vice_hud's own `version`: that counts vice_hud's
-- changes, while releases count the whole repository's. Cutting a release
-- means bumping `release` in fxmanifest.lua to the new tag, or every server on
-- it is told about an update it already has.
--
-- The repository is read from the manifest rather than hardcoded, so a fork
-- checks itself against its own releases.

local API = 'https://api.github.com/repos/%s/releases/latest'
local RECHECK_MS = 24 * 60 * 60 * 1000

---Split a version string into comparable numeric parts: 'v1.8.0' -> {1, 8, 0}.
local function parse(version)
    local parts = {}
    for chunk in tostring(version):gmatch('%d+') do
        parts[#parts + 1] = tonumber(chunk)
    end
    return parts
end

---True if `candidate` is a newer version than `installed`.
local function isNewer(candidate, installed)
    local a, b = parse(candidate), parse(installed)
    for i = 1, math.max(#a, #b) do
        local left, right = a[i] or 0, b[i] or 0
        if left ~= right then return left > right end
    end
    return false
end

---owner/repo from a GitHub URL, with or without a trailing .git or slash.
local function ownerRepo(url)
    local owner, name = tostring(url or ''):match('github%.com[/:]([%w%-%._]+)/([%w%-%._]+)')
    if not owner then return nil end
    return ('%s/%s'):format(owner, (name:gsub('%.git$', '')))
end

if Config.UpdateCheck ~= false then
    local resource  = GetCurrentResourceName()
    local installed = GetResourceMetadata(resource, 'release', 0)
    local repo      = ownerRepo(GetResourceMetadata(resource, 'repository', 0))

    CreateThread(function()
        if not installed or not repo then return end
        -- Let the rest of the start-up text print first, so this line is not
        -- lost in the middle of it.
        Wait(5000)

        local told -- the newest release already announced, so the daily check does not repeat it

        local function check(atStart)
            -- GitHub's API turns away requests without a User-Agent.
            local headers = { ['User-Agent'] = ('%s/%s'):format(resource, installed) }
            PerformHttpRequest(API:format(repo), function(status, body)
                -- Rate limits and outages are not worth a word: the next
                -- start or the next day's check will get through.
                if status ~= 200 or not body then return end
                local ok, release = pcall(json.decode, body)
                if not ok or type(release) ~= 'table' or type(release.tag_name) ~= 'string' then return end

                local latest = release.tag_name
                if isNewer(latest, installed) then
                    if told == latest then return end
                    told = latest
                    print(('^3[%s] Update available: GTA VI HUD %s is out (this server runs v%s).^7')
                        :format(resource, latest, installed))
                    print(('^3[%s] %s^7'):format(resource,
                        type(release.html_url) == 'string' and release.html_url
                        or ('https://github.com/%s/releases/latest'):format(repo)))
                elseif atStart then
                    print(('^2[%s] GTA VI HUD v%s is up to date.^7'):format(resource, installed))
                end
            end, 'GET', '', headers)
        end

        check(true)
        while true do
            Wait(RECHECK_MS)
            check(false)
        end
    end)
end
