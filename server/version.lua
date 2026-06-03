local Version = {}

local PREFIX = '^3[ImageDetector]^7'
local CHECK_DELAY = 5000
local LOG_FAILURES = false
local REPOSITORY = 'Cylix-Development/clx_imagedetector'
local API_URL = 'https://api.github.com/repos/' .. REPOSITORY .. '/releases/latest'
local RELEASE_URL = 'https://github.com/' .. REPOSITORY .. '/releases/latest'

-- Normalizes GitHub tags and fxmanifest versions before comparing them.
local function normalizeVersion(version)
    version = tostring(version or ''):lower()
    version = version:gsub('^%s+', ''):gsub('%s+$', '')
    version = version:gsub('^v', '')

    return version
end

-- Splits a semver-like string into numeric parts. Suffixes such as -beta are ignored for update checks.
local function parseVersion(version)
    local normalized = normalizeVersion(version)
    local parts = {}

    for part in normalized:gmatch('(%d+)') do
        parts[#parts + 1] = tonumber(part) or 0
    end

    return parts
end

-- Returns -1 when left is older, 0 when equal and 1 when left is newer.
local function compareVersions(left, right)
    local leftParts = parseVersion(left)
    local rightParts = parseVersion(right)
    local count = math.max(#leftParts, #rightParts)

    for i = 1, count do
        local leftValue = leftParts[i] or 0
        local rightValue = rightParts[i] or 0

        if leftValue < rightValue then
            return -1
        end

        if leftValue > rightValue then
            return 1
        end
    end

    return 0
end

local function getLocalVersion()
    local resourceName = GetCurrentResourceName()
    local version = GetResourceMetadata(resourceName, 'version', 0)

    if type(version) ~= 'string' or version == '' then
        return '0.0.0'
    end

    return version
end

local function printFailure(message)
    if LOG_FAILURES then
        print(('%s Version check failed: %s'):format(PREFIX, tostring(message or 'unknown error')))
    end
end

local function printUpdateAvailable(currentVersion, latestVersion, releaseUrl)
    print(('%s ^3A new release is available for this script.^7'):format(PREFIX))
    print(('%s ^3Installed: v%s | Latest: v%s^7'):format(PREFIX, currentVersion, latestVersion))
    print(('%s ^3Download: %s^7'):format(PREFIX, releaseUrl))
end

local function decodeRelease(body)
    if type(json) ~= 'table' or type(json.decode) ~= 'function' then
        return nil, 'json.decode is unavailable'
    end

    local ok, decoded = pcall(json.decode, body or '')

    if not ok or type(decoded) ~= 'table' then
        return nil, 'GitHub response could not be decoded'
    end

    return decoded
end

function Version.check()
    if type(PerformHttpRequest) ~= 'function' then
        printFailure('PerformHttpRequest is unavailable')
        return
    end

    local currentVersion = getLocalVersion()

    PerformHttpRequest(API_URL, function(statusCode, body)
        statusCode = tonumber(statusCode) or 0

        -- GitHub returns 404 when no releases exist yet. That is not an actionable update warning.
        if statusCode == 404 then
            return
        end

        if statusCode < 200 or statusCode >= 300 then
            printFailure(('GitHub returned HTTP %s'):format(statusCode))
            return
        end

        local release, decodeError = decodeRelease(body)

        if not release then
            printFailure(decodeError)
            return
        end

        local latestVersion = release.tag_name or release.name

        if type(latestVersion) ~= 'string' or latestVersion == '' then
            printFailure('GitHub release does not contain a version tag')
            return
        end

        if compareVersions(currentVersion, latestVersion) < 0 then
            local releaseUrl = release.html_url or RELEASE_URL
            printUpdateAvailable(normalizeVersion(currentVersion), normalizeVersion(latestVersion), releaseUrl)
        end
    end, 'GET', '', {
        ['Accept'] = 'application/vnd.github+json',
        ['User-Agent'] = GetCurrentResourceName()
    })
end

CreateThread(function()
    if CHECK_DELAY > 0 then
        Wait(CHECK_DELAY)
    end

    Version.check()
end)

PyImageDetector = PyImageDetector or {}
PyImageDetector.Version = Version
