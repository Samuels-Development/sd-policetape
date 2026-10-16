---@type table Version-checker helper module returned to consumers.
local version = {}

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:version')

---Parses a version string into its numeric components. Tolerant of stray
---characters — only extracts the digits.
---@param raw string
---@return integer[] semver components, e.g. "1.2.3" -> {1, 2, 3}.
local function parse(raw)
    local parts = {}
    for part in raw:gmatch('%d+') do
        parts[#parts + 1] = tonumber(part)
    end
    return parts
end

---Per-component version comparison. Returns -1 / 0 / 1 like strcmp.
---@param a integer[]
---@param b integer[]
---@return -1|0|1
local function compare(a, b)
    for i = 1, math.max(#a, #b) do
        local av, bv = a[i] or 0, b[i] or 0
        if av < bv then return -1 end
        if av > bv then return  1 end
    end
    return 0
end

---Asynchronously checks the resource's `version` metadata against the
---latest GitHub release on `repo` and prints a ▲/✓/▼ message to the console.
---Best-effort — never errors out a live server.
---@param repo string GitHub repo in `owner/name` form.
function version.check(repo)
    -- Always this resource: the module is `require`d, never exported, so
    -- GetInvokingResource() would name whatever triggered the current start
    -- (txAdmin's `monitor`, another script's restart) rather than us.
    local resource = GetCurrentResourceName()
    dprint('check: invoked for resource=%s repo=%s', tostring(resource), tostring(repo))

    local raw = GetResourceMetadata(resource, 'version', 0)
                or GetResourceMetadata(resource, 'Version', 0)
    dprint('check: raw version metadata=%s', tostring(raw))

    local current = raw and raw:match('%d+%.%d+%.%d+')
    if not current then
        dprint('check: could not parse current version from metadata — aborting')
        return print(('^1Unable to determine current resource version for ^2%s^1^0'):format(resource))
    end

    dprint('check: current version parsed as %s — scheduling HTTP request in 1s', tostring(current))
    print(('^3Checking for updates for ^2%s^3...^0'):format(resource))

    SetTimeout(1000, function()
        local url = ('https://api.github.com/repos/%s/releases/latest'):format(repo)
        dprint('check: performing HTTP GET %s', tostring(url))
        PerformHttpRequest(url, function(status, response)
            dprint('check: HTTP response status=%s responseLen=%d', tostring(status), response and #response or 0)
            if status ~= 200 then
                dprint('check: non-200 status — aborting version comparison')
                return print(('^1Failed to fetch release info for ^2%s^1 (HTTP %s)^0'):format(resource, status))
            end

            local data = json.decode(response)
            if not data then
                dprint('check: json.decode returned nil — aborting')
                return print(('^1Failed to parse release info for ^2%s^1^0'):format(resource))
            end
            if data.prerelease then
                dprint('check: latest release is a prerelease — skipping')
                return print(('^3Skipping prerelease for ^2%s^3^0'):format(resource))
            end

            local latest = data.tag_name and data.tag_name:match('%d+%.%d+%.%d+')
            dprint('check: tag_name=%s parsed latest=%s', tostring(data.tag_name), tostring(latest))
            if not latest then
                dprint('check: could not parse latest version tag — aborting')
                return print(('^1Failed to parse latest version tag for ^2%s^1^0'):format(resource))
            end

            local diff = compare(parse(current), parse(latest))
            dprint('check: version compare current=%s latest=%s diff=%d', tostring(current), tostring(latest), diff)
            if diff == 0 then
                print(('^2%s ^3is up to date (^2%s^3)^0'):format(resource, current))
            elseif diff < 0 then
                local notes = data.body or 'No release notes available.'
                local msg = notes:find('\n')
                    and 'Check release page or changelog for details.'
                    or  notes
                dprint('check: update available — current=%s latest=%s', tostring(current), tostring(latest))
                print(('^3An update is available for ^2%s^3 (current: ^2%s^3)\nLatest: ^2%s^3\nRelease Notes: ^7%s'):format(
                    resource, current, latest, msg))
            else
                dprint('check: local version (%s) is ahead of latest public release (%s)', tostring(current), tostring(latest))
                print(('^2%s^3 has newer local version (^2%s^3) than latest public release (^2%s^3)^0'):format(
                    resource, current, latest))
            end
        -- GitHub's REST API rejects requests with no User-Agent (HTTP 403,
        -- "Request forbidden by administrative rules"), so identify ourselves.
        end, 'GET', '', { ['User-Agent'] = resource, ['Accept'] = 'application/vnd.github+json' })
    end)
end

return version
