PyImageDetector = PyImageDetector or {}

local Filesystem = PyImageDetector.Filesystem

local Scanner = {}

local progressInterval = 250

local function getTimerMs()
    if type(GetGameTimer) == 'function' then
        return GetGameTimer()
    end

    if type(os) == 'table' and type(os.clock) == 'function' then
        return math.floor(os.clock() * 1000)
    end

    return 0
end

local function readProgressNumber(value)
    return math.max(0, math.floor(tonumber(value) or 0))
end

local function createCancelChecker(cancelCallback)
    local hasCancelCallback = type(cancelCallback) == 'function'
    local state = {
        canceled = false,
        checks = 0,
    }

    function state:shouldCancel()
        if self.canceled then
            return true
        end

        if not hasCancelCallback then
            return false
        end

        self.checks = self.checks + 1

        if self.checks >= 25 then
            self.checks = 0
            Wait(0)
        end

        local ok, canceled = pcall(cancelCallback)
        if ok and canceled == true then
            self.canceled = true
        end

        return self.canceled
    end

    return state
end

-- Tracks scan progress in the same payload shape as clx_collisiondetector.
local function createProgressReporter(progressCallback)
    local progress = {
        phase = 'idle',
        scannedRoots = 0,
        totalRoots = 0,
        scannedPaths = 0,
        missingItems = 0,
        unusedImages = 0,
        lastEmit = 0,
    }

    local function emit(phase, force)
        progress.phase = phase or progress.phase or 'running'

        if type(progressCallback) ~= 'function' then
            return
        end

        local now = getTimerMs()
        if not force and progressInterval > 0 and progress.lastEmit > 0 and (now - progress.lastEmit) < progressInterval then
            return
        end

        progress.lastEmit = now

        pcall(progressCallback, {
            phase = progress.phase,
            scannedRoots = progress.scannedRoots,
            totalRoots = progress.totalRoots,
            scannedPaths = progress.scannedPaths,
            missingItems = progress.missingItems,
            unusedImages = progress.unusedImages,
        })
    end

    function progress:start(totalRoots)
        self.phase = 'running'
        self.scannedRoots = 0
        self.totalRoots = readProgressNumber(totalRoots)
        self.scannedPaths = 0
        self.missingItems = 0
        self.unusedImages = 0
        emit('running', true)
    end

    function progress:setCounts(missingItems, unusedImages)
        if missingItems ~= nil then
            self.missingItems = readProgressNumber(missingItems)
        end

        if unusedImages ~= nil then
            self.unusedImages = readProgressNumber(unusedImages)
        end
    end

    function progress:add(scannedRoots, scannedPaths)
        self.scannedRoots = math.min(self.totalRoots, self.scannedRoots + readProgressNumber(scannedRoots))
        self.scannedPaths = self.scannedPaths + readProgressNumber(scannedPaths)
        emit('running')
    end

    function progress:finish()
        self.scannedRoots = self.totalRoots
        emit('complete', true)
    end

    function progress:cancel()
        emit('canceled', true)
    end

    return progress
end

function Scanner.getProvider(inventory)
    return PyImageDetector.Providers and PyImageDetector.Providers[inventory] or nil
end

local autoInventoryPriority = {
    'ox_inventory',
    'qb-inventory',
    'ps-inventory',
    'qs-inventory',
    'esx_inventory',
    'jaksam_inventory',
    'tgiann-inventory',
    'origen_inventory',
    'codem-inventory',
    'core_inventory',
}

-- Returns true only when a resource is actively started.
local function isResourceStarted(resourceName)
    return GetResourceState(resourceName) == 'started'
end

local function normalizeKey(value, caseSensitive)
    value = tostring(value)
    if caseSensitive then return value end

    return value:lower()
end

-- Returns the image extensions this provider should scan, without leading dots.
local function getImageExtensions(provider)
    local configuredExtensions = type(provider.ImageExtensions) == 'table' and provider.ImageExtensions or { 'png' }
    local extensions = {}

    for i = 1, #configuredExtensions do
        local extension = tostring(configuredExtensions[i] or ''):lower():gsub('^%.', '')
        if extension ~= '' then
            extensions[#extensions + 1] = extension
        end
    end

    if #extensions == 0 then
        extensions[1] = 'png'
    end

    return extensions
end

local function buildExtensionLookup(extensions)
    local lookup = {}

    for i = 1, #extensions do
        lookup[extensions[i]] = true
    end

    return lookup
end

-- Converts paths or filenames to an image basename without the configured image extension.
local function normalizeImageName(value, extensions)
    if type(value) ~= 'string' or value == '' then return nil end

    local normalized = value:gsub('\\', '/')
    normalized = normalized:match('([^/]+)$') or normalized

    local extensionLookup = buildExtensionLookup(extensions or { 'png' })
    local basename, extension = normalized:match('^(.*)%.([^%.]+)$')
    if basename and extensionLookup[extension:lower()] then
        normalized = basename
    end

    if normalized == '' then return nil end
    return normalized
end

local function getConfiguredExtension(value, extensions)
    if type(value) ~= 'string' or value == '' then return nil end

    local extensionLookup = buildExtensionLookup(extensions or { 'png' })
    local extension = value:gsub('\\', '/'):match('%.([^%.\\/]+)$')
    if extension and extensionLookup[extension:lower()] then
        return extension:lower()
    end

    return nil
end

local function formatExpectedImageName(imageName, extensions, expectedExtension)
    if expectedExtension then
        return ('%s.%s'):format(imageName, expectedExtension)
    end

    if #extensions == 1 then
        return ('%s.%s'):format(imageName, extensions[1])
    end

    local values = {}
    for i = 1, #extensions do
        if i == 1 then
            values[#values + 1] = ('%s.%s'):format(imageName, extensions[i])
        else
            values[#values + 1] = ('.%s'):format(extensions[i])
        end
    end

    return table.concat(values, ' / ')
end

local function getSupportedInventories()
    local names = { 'auto' }
    local providers = PyImageDetector.Providers or {}

    for providerName in pairs(providers) do
        names[#names + 1] = providerName
    end

    table.sort(names, function(left, right)
        if left == 'auto' then return true end
        if right == 'auto' then return false end

        return left:lower() < right:lower()
    end)

    return table.concat(names, ', ')
end

local function getProviderName(provider)
    return provider and (provider.DisplayName or provider.Resource) or nil
end

local function formatProviderNames(values, startIndex)
    local names = {}

    for i = startIndex or 1, #values do
        names[#names + 1] = values[i].name
    end

    return table.concat(names, ', ')
end

local function getAutoStartedProviders()
    local providers = PyImageDetector.Providers or {}
    local priorityLookup = {}
    local started = {}

    for i = 1, #autoInventoryPriority do
        local providerName = autoInventoryPriority[i]
        priorityLookup[providerName] = true

        local provider = providers[providerName]
        if provider and isResourceStarted(provider.Resource) then
            started[#started + 1] = {
                name = getProviderName(provider),
                provider = provider,
            }
        end
    end

    local remainingNames = {}
    for providerName in pairs(providers) do
        if not priorityLookup[providerName] then
            remainingNames[#remainingNames + 1] = providerName
        end
    end

    table.sort(remainingNames, function(left, right)
        return left:lower() < right:lower()
    end)

    for i = 1, #remainingNames do
        local provider = providers[remainingNames[i]]
        if provider and isResourceStarted(provider.Resource) then
            started[#started + 1] = {
                name = getProviderName(provider),
                provider = provider,
            }
        end
    end

    return started
end

local function loadProvider(inventory)
    if inventory == 'auto' then
        local startedProviders = getAutoStartedProviders()
        if #startedProviders == 0 then
            return nil, ('Config.Inventory is set to auto, but no supported inventory resource is started. Supported values: %s.'):format(getSupportedInventories())
        end

        local warnings = {}
        if #startedProviders > 1 then
            warnings[#warnings + 1] = ('Auto detected %s. Other supported inventory resources are also started: %s. Set Config.Inventory explicitly if this is not the active inventory.'):format(startedProviders[1].name, formatProviderNames(startedProviders, 2))
        end

        return startedProviders[1].provider, nil, startedProviders[1].name, warnings
    end

    local provider = Scanner.getProvider(inventory)
    if not provider then
        return nil, ("Unsupported inventory '%s'. Supported values: %s."):format(tostring(inventory), getSupportedInventories())
    end

    return provider, nil, getProviderName(provider), {}
end

function Scanner.resolveProvider(configOrInventory)
    local inventory = type(configOrInventory) == 'table' and configOrInventory.Inventory or configOrInventory
    return loadProvider(inventory)
end

local function appendWarnings(target, warnings)
    if type(warnings) ~= 'table' then return end

    for i = 1, #warnings do
        target[#target + 1] = warnings[i]
    end
end

local function buildImageIndex(files, caseSensitive, extensions, progress, cancelChecker)
    local imageIndex = {}
    local imageCount = 0
    local extensionLookup = buildExtensionLookup(extensions)

    for i = 1, #files do
        if cancelChecker and cancelChecker:shouldCancel() then
            break
        end

        local extension = files[i]:match('%.([^%.]+)$')
        local imageName = normalizeImageName(files[i], extensions)
        if imageName and extension and extensionLookup[extension:lower()] then
            local key = normalizeKey(imageName, caseSensitive)
            imageIndex[key] = imageIndex[key] or {}
            imageIndex[key][#imageIndex[key] + 1] = {
                name = imageName,
                extension = extension:lower(),
                fileName = files[i],
            }
            imageCount = imageCount + 1
        end

        if progress then
            progress:add(1, 1)
        end
    end

    return imageIndex, imageCount
end

-- Encodes a single URL path segment for nui:// image sources.
local function encodePathSegment(value)
    return tostring(value):gsub('([^%w%-%_%.~])', function(char)
        return ('%%%02X'):format(char:byte())
    end)
end

local function getImageUrl(provider, fileName)
    if type(provider.ImageWebPath) ~= 'string' or provider.ImageWebPath == '' then
        return nil
    end

    return ('nui://%s/%s/%s'):format(provider.ImageResource or provider.Resource, provider.ImageWebPath, encodePathSegment(fileName))
end

local base64Characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

-- Encodes binary image data so previews do not depend on external resource file globs or extension casing.
local function base64Encode(data)
    if type(data) ~= 'string' or data == '' then return nil end

    local encoded = {}
    for index = 1, #data, 3 do
        local first, second, third = data:byte(index, index + 2)
        local value = (first * 65536) + ((second or 0) * 256) + (third or 0)

        local firstChar = math.floor(value / 262144) % 64
        local secondChar = math.floor(value / 4096) % 64
        local thirdChar = math.floor(value / 64) % 64
        local fourthChar = value % 64

        encoded[#encoded + 1] = base64Characters:sub(firstChar + 1, firstChar + 1)
        encoded[#encoded + 1] = base64Characters:sub(secondChar + 1, secondChar + 1)
        encoded[#encoded + 1] = second and base64Characters:sub(thirdChar + 1, thirdChar + 1) or '='
        encoded[#encoded + 1] = third and base64Characters:sub(fourthChar + 1, fourthChar + 1) or '='
    end

    return table.concat(encoded)
end

local function getMimeType(fileName)
    local extension = tostring(fileName):match('%.([^%.]+)$')
    extension = extension and extension:lower() or ''

    if extension == 'jpg' or extension == 'jpeg' then return 'image/jpeg' end
    if extension == 'png' then return 'image/png' end
    if extension == 'webp' then return 'image/webp' end
    if extension == 'gif' then return 'image/gif' end
    if extension == 'svg' then return 'image/svg+xml' end

    return 'application/octet-stream'
end

local function getImageDataUrl(provider, fileName)
    if type(provider.ImageWebPath) ~= 'string' or provider.ImageWebPath == '' then
        return nil
    end

    local resourceName = provider.ImageResource or provider.Resource
    local resourcePath = ('%s/%s'):format(provider.ImageWebPath, fileName)
    local fileData = LoadResourceFile(resourceName, resourcePath)
    if type(fileData) ~= 'string' or fileData == '' then
        return nil
    end

    local encoded = base64Encode(fileData)
    if not encoded then return nil end

    return ('data:%s;base64,%s'):format(getMimeType(fileName), encoded)
end

local function getPreviewUrl(provider, fileName)
    return getImageDataUrl(provider, fileName) or getImageUrl(provider, fileName)
end

local function getExpectedImageName(config, provider, itemName, itemData, extensions)
    local itemImages = type(config.ItemImages) == 'table' and config.ItemImages or nil
    local override = itemImages and itemImages[itemName]

    if type(override) == 'string' and override ~= '' then
        return normalizeImageName(override, extensions) or override, getConfiguredExtension(override, extensions)
    end

    if type(provider.getConfiguredImage) == 'function' then
        local configuredImage = provider.getConfiguredImage(itemData, itemName, config)
        if type(configuredImage) == 'string' and configuredImage ~= '' then
            return normalizeImageName(configuredImage, extensions) or configuredImage, getConfiguredExtension(configuredImage, extensions)
        end
    end

    return tostring(itemName), provider.DefaultImageExtension
end

-- Reads a human-friendly item label from common inventory item definitions.
local function getItemLabel(itemData, itemName)
    if type(itemData) ~= 'table' then return nil end

    local candidates = {
        itemData.label,
        itemData.displayName,
        itemData.display,
        itemData.title,
    }

    local client = type(itemData.client) == 'table' and itemData.client or nil
    if client then
        candidates[#candidates + 1] = client.label
        candidates[#candidates + 1] = client.displayName
        candidates[#candidates + 1] = client.title
    end

    for i = 1, #candidates do
        local label = candidates[i]

        if type(label) == 'string' then
            label = label:gsub('^%s+', ''):gsub('%s+$', '')

            if label ~= '' and label ~= tostring(itemName) then
                return label
            end
        end
    end

    return nil
end

local function getMatchingImageEntries(imageEntries, expectedExtension)
    if not imageEntries then return nil end

    if not expectedExtension then
        return imageEntries
    end

    local matchingEntries = {}
    for i = 1, #imageEntries do
        if imageEntries[i].extension == expectedExtension then
            matchingEntries[#matchingEntries + 1] = imageEntries[i]
        end
    end

    if #matchingEntries == 0 then return nil end
    return matchingEntries
end

local function sortMissing(items)
    table.sort(items, function(left, right)
        return left.item:lower() < right.item:lower()
    end)
end

local function sortStrings(values)
    table.sort(values, function(left, right)
        return left:lower() < right:lower()
    end)
end

function Scanner.run(config, progressCallback, cancelCallback)
    local inventory = config.Inventory
    if type(inventory) ~= 'string' or inventory == '' then
        return nil, 'Config.Inventory must be a non-empty string.'
    end

    local provider, providerErr, resolvedInventory, autoWarnings = loadProvider(inventory)
    if not provider then return nil, providerErr end

    if not isResourceStarted(provider.Resource) then
        return nil, ('%s must be started before clx_imagedetector. Current state: %s.'):format(provider.Resource, GetResourceState(provider.Resource))
    end

    if provider.ImageResource and not isResourceStarted(provider.ImageResource) then
        return nil, ('%s must be started before clx_imagedetector. Current state: %s.'):format(provider.ImageResource, GetResourceState(provider.ImageResource))
    end

    for i = 1, #(provider.RequiredResources or {}) do
        local resourceName = provider.RequiredResources[i]
        if not isResourceStarted(resourceName) then
            return nil, ('%s must be started before clx_imagedetector. Current state: %s.'):format(resourceName, GetResourceState(resourceName))
        end
    end

    local items, itemWarnings = provider.getItems(config)
    if not items then return nil, itemWarnings end

    local imageDirectory = provider.getImageDirectory(config)
    if type(imageDirectory) ~= 'string' or imageDirectory == '' then
        return nil, ('Could not resolve image directory for %s.'):format(provider.DisplayName or provider.Resource)
    end

    local warnings = {}
    appendWarnings(warnings, autoWarnings)
    appendWarnings(warnings, itemWarnings)

    local imageFiles, imageErr = Filesystem.listFiles(imageDirectory)
    if imageErr then
        warnings[#warnings + 1] = imageErr
    end

    local totalItems = 0
    for _ in pairs(items) do
        totalItems = totalItems + 1
    end

    local imageExtensions = getImageExtensions(provider)
    local progress = createProgressReporter(progressCallback)
    local cancelChecker = createCancelChecker(cancelCallback)
    local unusedImageWork = config.ReportUnusedImages ~= false and #imageFiles or 0
    progress:start(math.max(1, #imageFiles + totalItems + unusedImageWork))

    local imageIndex, imageCount = buildImageIndex(imageFiles, config.CaseSensitive == true, imageExtensions, progress, cancelChecker)
    local usedImages = {}
    local missingItems = {}
    local itemCount = 0

    for itemName, itemData in pairs(items) do
        if cancelChecker:shouldCancel() then
            break
        end

        itemCount = itemCount + 1

        local expectedImage, expectedExtension = getExpectedImageName(config, provider, itemName, itemData, imageExtensions)
        local key = normalizeKey(expectedImage, config.CaseSensitive == true)
        local matchingEntries = getMatchingImageEntries(imageIndex[key], expectedExtension)

        if matchingEntries then
            for i = 1, #matchingEntries do
                usedImages[matchingEntries[i].fileName] = true
            end
        else
            missingItems[#missingItems + 1] = {
                item = tostring(itemName),
                label = getItemLabel(itemData, itemName),
                image = expectedImage,
                imageFile = formatExpectedImageName(expectedImage, imageExtensions, expectedExtension),
            }
        end

        progress:setCounts(#missingItems, nil)
        progress:add(1, 1)
    end

    local unusedImages = {}
    local unusedImageEntries = {}
    if config.ReportUnusedImages ~= false and not cancelChecker.canceled then
        for key, imageEntries in pairs(imageIndex) do
            for i = 1, #imageEntries do
                if cancelChecker:shouldCancel() then
                    break
                end

                local imageEntry = imageEntries[i]
                if not usedImages[imageEntry.fileName] then
                    unusedImages[#unusedImages + 1] = imageEntry.fileName
                    unusedImageEntries[#unusedImageEntries + 1] = {
                        name = imageEntry.name,
                        fileName = imageEntry.fileName,
                        url = getPreviewUrl(provider, imageEntry.fileName),
                    }
                end

                progress:setCounts(nil, #unusedImages)
                progress:add(1, 1)
            end

            if cancelChecker.canceled then
                break
            end
        end
    end

    sortMissing(missingItems)
    sortStrings(unusedImages)
    table.sort(unusedImageEntries, function(left, right)
        return left.name:lower() < right.name:lower()
    end)

    if cancelChecker.canceled then
        progress:cancel()
    else
        progress:finish()
    end

    return {
        inventory = resolvedInventory or provider.DisplayName or provider.Resource,
        configuredInventory = inventory,
        imageDirectory = imageDirectory,
        itemCount = itemCount,
        imageCount = imageCount,
        missingItems = missingItems,
        unusedImages = unusedImages,
        unusedImageEntries = unusedImageEntries,
        warnings = warnings,
        reportUnusedImages = config.ReportUnusedImages ~= false,
        scannedRoots = progress.scannedRoots,
        totalRoots = progress.totalRoots,
        scannedPaths = progress.scannedPaths,
        canceled = cancelChecker.canceled,
    }
end

PyImageDetector.Scanner = Scanner
