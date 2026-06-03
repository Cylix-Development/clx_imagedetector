PyImageDetector = PyImageDetector or {}
PyImageDetector.Providers = PyImageDetector.Providers or {}

local Filesystem = PyImageDetector.Filesystem

local Provider = {}

Provider.Resource = 'origen_inventory'
Provider.DisplayName = 'origen_inventory'
Provider.ImageWebPath = 'html/images'
Provider.ImageExtensions = {
    'png',
    'webp',
}
Provider.DefaultImageExtension = 'png'
Provider.RequiredResources = {}

local imagePathCandidates = {
    'html/images',
    'web/images',
    'images',
}

local itemFileCandidates = {
    'config/items.lua',
    'shared/items.lua',
    'items.lua',
}

-- origen_inventory normally serves icons from html/images, but this keeps older layouts detectable.
function Provider.getImageDirectory()
    local resourcePath = GetResourcePath(Provider.Resource)
    if not resourcePath then return nil end

    for i = 1, #imagePathCandidates do
        local relativePath = imagePathCandidates[i]
        local fullPath = ('%s/%s'):format(resourcePath, relativePath)
        local _, err = Filesystem.listFiles(fullPath)

        if not err then
            Provider.ImageWebPath = relativePath
            return fullPath
        end
    end

    return ('%s/%s'):format(resourcePath, Provider.ImageWebPath)
end

-- Adds one item definition into the normalized item index.
local function addItem(target, itemName, itemData)
    if type(itemData) ~= 'table' then return 0 end

    if type(itemName) ~= 'string' and type(itemData.name) == 'string' then
        itemName = itemData.name
    end

    if type(itemName) ~= 'string' or itemName == '' then return 0 end

    target[itemName] = itemData
    return 1
end

local function looksLikeItemData(value)
    return type(value) == 'table'
        and (
            type(value.name) == 'string'
            or type(value.label) == 'string'
            or type(value.image) == 'string'
            or type(value.weight) == 'number'
            or type(value.type) == 'string'
        )
end

local function looksLikeItemList(source)
    if type(source) ~= 'table' then return false end

    local checked = 0
    for _, value in pairs(source) do
        checked = checked + 1

        if looksLikeItemData(value) then
            return true
        end

        if checked >= 20 then
            break
        end
    end

    return false
end

local function mergeItems(target, source)
    if not looksLikeItemList(source) then return 0 end

    local added = 0
    for itemName, itemData in pairs(source) do
        added = added + addItem(target, itemName, itemData)
    end

    return added
end

local function appendCandidate(candidates, source)
    if type(source) == 'table' then
        candidates[#candidates + 1] = source
    end
end

local function collectCandidateTables(result, env)
    local candidates = {}

    if type(result) == 'table' then
        appendCandidate(candidates, result.Items)
        appendCandidate(candidates, result.items)
        appendCandidate(candidates, result.ItemList)
        appendCandidate(candidates, result.Itemlist)
        appendCandidate(candidates, result.CustomItems)
        appendCandidate(candidates, result)
    end

    appendCandidate(candidates, env.Config and env.Config.Items)
    appendCandidate(candidates, env.Config and env.Config.items)
    appendCandidate(candidates, env.Config and env.Config.ItemList)
    appendCandidate(candidates, env.Config and env.Config.CustomItems)
    appendCandidate(candidates, env.Items)
    appendCandidate(candidates, env.ItemList)
    appendCandidate(candidates, env.Shared and env.Shared.Items)
    appendCandidate(candidates, env.QBCore and env.QBCore.Shared and env.QBCore.Shared.Items)
    appendCandidate(candidates, env.OrgItems)

    return candidates
end

-- Loads Origen item config files without requiring the external resource to expose a full item-list export.
local function loadItemFile(path)
    local file = LoadResourceFile(Provider.Resource, path)
    if not file then
        return nil, ('@%s/%s was not found.'):format(Provider.Resource, path), true
    end

    local env = setmetatable({
        Config = {
            Items = {},
            ItemList = {},
            CustomItems = {},
        },
        Items = {},
        ItemList = {},
        Shared = {
            Items = {},
        },
        QBCore = {
            Shared = {
                Items = {},
            },
        },
        OrgItems = {},
    }, { __index = _ENV })

    local chunk, chunkErr = load(file, ('@@%s/%s'):format(Provider.Resource, path), 't', env)
    if not chunk then
        return nil, ('Failed to parse @%s/%s: %s'):format(Provider.Resource, path, chunkErr)
    end

    local ok, result = pcall(chunk)
    if not ok then
        return nil, ('Failed to execute @%s/%s: %s'):format(Provider.Resource, path, result)
    end

    local allItems = {}
    local candidates = collectCandidateTables(result, env)

    for i = 1, #candidates do
        mergeItems(allItems, candidates[i])
    end

    if not next(allItems) then
        return nil, ('@%s/%s did not expose an item list.'):format(Provider.Resource, path)
    end

    return allItems
end

local function mergeExportItems(target, source)
    return mergeItems(target, source)
end

-- Tries common item-list exports used by inventory bridges and older Origen builds.
local function readItemsFromExports()
    local exportReaders = {
        {
            name = 'GetItemList',
            read = function()
                return exports['origen_inventory']:GetItemList()
            end,
        },
        {
            name = 'Items',
            read = function()
                return exports['origen_inventory']:Items()
            end,
        },
        {
            name = 'ItemsRaw',
            read = function()
                return exports['origen_inventory']:ItemsRaw()
            end,
        },
    }

    local allItems = {}
    local errors = {}

    for i = 1, #exportReaders do
        local reader = exportReaders[i]
        local ok, result = pcall(reader.read)

        if ok and type(result) == 'table' then
            mergeExportItems(allItems, result)
        elseif not ok then
            errors[#errors + 1] = ('%s failed: %s'):format(reader.name, tostring(result))
        end
    end

    if next(allItems) then
        return allItems
    end

    return nil, table.concat(errors, ' / ')
end

function Provider.getItems()
    local allItems = {}
    local warnings = {}

    local exportItems, exportErr = readItemsFromExports()
    if exportItems then
        mergeItems(allItems, exportItems)
    end

    for i = 1, #itemFileCandidates do
        local path = itemFileCandidates[i]
        local fileItems, fileErr, fileMissing = loadItemFile(path)

        if fileItems then
            mergeItems(allItems, fileItems)
        elseif not fileMissing then
            warnings[#warnings + 1] = fileErr
        end
    end

    if not next(allItems) then
        if exportErr and exportErr ~= '' then
            warnings[#warnings + 1] = ('Origen item exports were unavailable: %s'):format(exportErr)
        end

        return nil, 'origen_inventory did not expose item definitions through exports or known item config files.'
    end

    return allItems, warnings
end

-- Origen item definitions and custom items can define an explicit image filename.
function Provider.getConfiguredImage(itemData)
    if type(itemData) ~= 'table' then return nil end

    if type(itemData.image) == 'string' and itemData.image ~= '' then
        return itemData.image
    end

    local client = itemData.client
    if type(client) == 'table' and type(client.image) == 'string' and client.image ~= '' then
        return client.image
    end

    if type(itemData.img) == 'string' and itemData.img ~= '' then
        return itemData.img
    end

    if type(itemData.icon) == 'string' and itemData.icon ~= '' then
        return itemData.icon
    end

    return nil
end

local function getPlayerCoords(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return nil end

    local coords = GetEntityCoords(ped)
    return vector3(coords.x, coords.y, coords.z - 0.2)
end

-- Gives one item to an admin, or creates an Origen ground drop when their inventory is full.
function Provider.giveItemToPlayer(source, itemName, amount)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'invalid_amount' end

    local canCarryOk, canCarry = pcall(function()
        return exports['origen_inventory']:canCarryItem(source, itemName, amount)
    end)

    if not canCarryOk then
        return false, ('can_carry_failed:%s'):format(tostring(canCarry))
    end

    if canCarry == true then
        local addOk, added = pcall(function()
            return exports['origen_inventory']:addItem(source, itemName, amount)
        end)

        if addOk and added == true then
            return true, 'added'
        end

        return false, addOk and 'add_failed' or ('add_failed:%s'):format(tostring(added))
    end

    local coords = getPlayerCoords(source)
    if not coords then return false, 'invalid_player' end

    local dropItems = {
        {
            name = itemName,
            amount = amount,
            info = {},
        },
    }

    local dropOk, dropId = pcall(function()
        return exports['origen_inventory']:customDrop(coords, dropItems)
    end)

    if dropOk and dropId then
        return true, 'dropped'
    end

    return false, 'inventory_full'
end

PyImageDetector.Providers[Provider.Resource] = Provider
