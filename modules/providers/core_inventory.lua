PyImageDetector = PyImageDetector or {}
PyImageDetector.Providers = PyImageDetector.Providers or {}

local Filesystem = PyImageDetector.Filesystem

local Provider = {}

Provider.Resource = 'core_inventory'
Provider.DisplayName = 'core_inventory'
Provider.ImageWebPath = 'html/img'
Provider.ImageExtensions = {
    'png',
    'webp',
}
Provider.DefaultImageExtension = 'png'
Provider.RequiredResources = {}

local imagePathCandidates = {
    'html/img',
    'html/images',
    'web/images',
    'images',
}

local itemFileCandidates = {
    'data/items.lua',
    'data/weapons.lua',
    'shared/items.lua',
    'items.lua',
}

-- core_inventory normally stores item images in html/img, with fallbacks for edited builds.
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
            or type(value.description) == 'string'
            or type(value.category) == 'string'
            or type(value.x) == 'number'
            or type(value.y) == 'number'
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
        appendCandidate(candidates, result.Weapons)
        appendCandidate(candidates, result.Components)
        appendCandidate(candidates, result.Ammo)
        appendCandidate(candidates, result)
    end

    appendCandidate(candidates, env.Config and env.Config.Items)
    appendCandidate(candidates, env.Config and env.Config.ItemList)
    appendCandidate(candidates, env.Items)
    appendCandidate(candidates, env.ItemList)
    appendCandidate(candidates, env.Shared and env.Shared.Items)
    appendCandidate(candidates, env.QBCore and env.QBCore.Shared and env.QBCore.Shared.Items)

    return candidates
end

-- Loads optional core_inventory item files when the registered item export is unavailable.
local function loadItemFile(path)
    local file = LoadResourceFile(Provider.Resource, path)
    if not file then
        return nil, ('@%s/%s was not found.'):format(Provider.Resource, path), true
    end

    local env = setmetatable({
        Config = {
            Items = {},
            ItemList = {},
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

-- Reads Core Inventory's registered items through its documented server export.
local function readItemsFromExports()
    local ok, items = pcall(function()
        return exports['core_inventory']:getItemsList()
    end)

    if ok and type(items) == 'table' then
        local allItems = {}
        mergeItems(allItems, items)

        if next(allItems) then
            return allItems
        end

        return nil, 'getItemsList returned a table without recognizable item definitions.'
    end

    return nil, ok and 'getItemsList did not return a table.' or ('getItemsList failed: %s'):format(tostring(items))
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
            warnings[#warnings + 1] = exportErr
        end

        return nil, 'core_inventory did not expose item definitions through getItemsList or known item config files.'
    end

    return allItems, warnings
end

-- core_inventory generally uses itemName.png, but dynamic items may set an explicit image filename.
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

-- Gives one item to an admin after core_inventory confirms there is enough grid space.
function Provider.giveItemToPlayer(source, itemName, amount)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'invalid_amount' end

    local canCarryOk, canCarry = pcall(function()
        return exports['core_inventory']:canCarry(source, itemName, amount)
    end)

    if not canCarryOk then
        return false, ('can_carry_failed:%s'):format(tostring(canCarry))
    end

    if canCarry ~= true then
        return false, 'inventory_full'
    end

    local addOk, added = pcall(function()
        return exports['core_inventory']:addItem(source, itemName, amount)
    end)

    if addOk and added == true then
        return true, 'added'
    end

    return false, addOk and 'add_failed' or ('add_failed:%s'):format(tostring(added))
end

PyImageDetector.Providers[Provider.Resource] = Provider
