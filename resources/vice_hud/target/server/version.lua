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

-- A repository that has never published a release still says what is current:
-- the `version` line of the manifest on its default branch. Without this a
-- fork that ships by pushing, not by cutting releases, would check itself and
-- never hear anything.
local MANIFEST = 'https://raw.githubusercontent.com/%s/HEAD/fxmanifest.lua'

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

  -- GitHub's API rejects requests that send no User-Agent.
  local headers = { ['User-Agent'] = ('%s/%s'):format(resource, installed) }

  local function report(latest, url)
    if not latest or not isNewer(latest, installed) then return end

    print(('^3[osm-target] ' .. Locale('version_outdated') .. '^7'):format(latest, installed))
    if url then print(('^3[osm-target] %s^7'):format(url)) end
  end

  PerformHttpRequest(API:format(repo), function(status, body)
    if status == 200 and body then
      local ok, release = pcall(json.decode, body)
      if not ok or type(release) ~= 'table' then return end

      -- Prereleases are opt-in, not something to nag a running server about.
      if release.prerelease or type(release.tag_name) ~= 'string' then return end

      report(release.tag_name:match('%d+[%d%.]*'),
        type(release.html_url) == 'string' and release.html_url or nil)
      return
    end

    -- 404 is GitHub saying this repository has no release at all. Anything
    -- else (rate limit, outage) is not worth a second request.
    if status ~= 404 then return end

    PerformHttpRequest(MANIFEST:format(repo), function(code, text)
      if code ~= 200 or type(text) ~= 'string' then return end

      -- The line that starts with `version`, which `fx_version` does not.
      local declared = (string.char(10) .. text):match(string.char(10) .. 'version%s+%p([%d%.]+)%p')
      report(declared, ('https://github.com/%s'):format(repo))
    end, 'GET', '', headers)
  end, 'GET', '', headers)
end)
