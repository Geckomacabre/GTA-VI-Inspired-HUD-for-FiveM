-- Update check.
--
-- This used to poll a `version.json` at the repository root. No such file has
-- ever existed there, so the request 404'd and the check silently did nothing
-- on every server running this resource. It now reads the repository's actual
-- releases, which is the thing that gets published when a version ships.
--
-- The repository is taken from the manifest rather than hardcoded, so a fork
-- checks itself against its own releases instead of reporting upstream's
-- version numbers as updates to code it does not have.

local API = 'https://api.github.com/repos/%s/releases/latest'

---Split a version string into comparable numeric parts.
local function parse(version)
  local parts = {}
  for chunk in tostring(version):gmatch('%d+') do
    parts[#parts + 1] = tonumber(chunk)
  end
  return parts
end

---Compare version numbers: return true if candidate is newer than installed.
---@return boolean
local function isNewer(candidate, installed)
  local a, b = parse(candidate), parse(installed)
  for i = 1, math.max(#a, #b) do
    local left, right = a[i] or 0, b[i] or 0
    if left ~= right then return left > right end
  end
  return false
end

---owner/repo from the manifest's `repository` field, with or without a
---trailing .git or slash.
---@return string?
local function repository(resource)
  local url = GetResourceMetadata(resource, 'repository', 0)
  if not url then return nil end

  local owner, name = url:match('github%.com[/:]([%w%-%._]+)/([%w%-%._]+)')
  if not owner or not name then return nil end

  return ('%s/%s'):format(owner, (name:gsub('%.git$', '')))
end

CreateThread(function()
  if not Config.VersionCheck then return end
  Wait(5000)

  local resource = GetCurrentResourceName()
  local installed = GetResourceMetadata(resource, 'version', 0)
  if not installed then return end

  local repo = repository(resource)
  if not repo then return end

  PerformHttpRequest(API:format(repo), function(status, body)
    if status ~= 200 or not body then return end

    local ok, release = pcall(json.decode, body)
    if not ok or type(release) ~= 'table' then return end

    -- Prereleases are opt-in, not something to nag a running server about.
    if release.prerelease or type(release.tag_name) ~= 'string' then return end

    local latest = release.tag_name:match('%d+[%d%.]*')
    if not latest or not isNewer(latest, installed) then return end

    print(('^3[osm-target] ' .. Locale('version_outdated') .. '^7'):format(latest, installed))
    if type(release.html_url) == 'string' then
      print(('^3[osm-target] %s^7'):format(release.html_url))
    end
  -- GitHub's API rejects requests that send no User-Agent.
  end, 'GET', '', { ['User-Agent'] = ('%s/%s'):format(resource, installed) })
end)
