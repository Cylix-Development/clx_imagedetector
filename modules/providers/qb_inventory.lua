PyImageDetector = PyImageDetector or {}
PyImageDetector.Providers = PyImageDetector.Providers or {}

local Provider = {}

Provider.Resource = 'qb-inventory'
Provider.DisplayName = 'qb-inventory'
Provider.ImageWebPath = 'html/images'
Provider.RequiredResources = {
    'qb-core',
}

-- qb-inventory keeps item images inside its html image folder.
function Provider.getImageDirectory()
    local resourcePath = GetResourcePath(Provider.Resource)
    if not resourcePath then return nil end

    return ('%s/%s'):format(resourcePath, Provider.ImageWebPath)
end

-- Reads QBCore shared items through the server export.
function Provider.getItems()
    local ok, items = pcall(function()
        return exports['qb-core']:GetSharedItems()
    end)

    if not ok then
        return nil, ('Failed to read qb-core shared items: %s'):format(items)
    end

    if type(items) ~= 'table' then
        return nil, 'qb-core GetSharedItems() did not return a table.'
    end

    local allItems = {}
    for itemName, itemData in pairs(items) do
        allItems[itemName] = itemData or {}
    end

    return allItems, {}
end

-- qb item definitions can define a custom image directly on the item data.
function Provider.getConfiguredImage(itemData)
    if type(itemData) == 'table' and type(itemData.image) == 'string' and itemData.image ~= '' then
        return itemData.image
    end

    return nil
end

-- Item giving is intentionally limited to providers with a safe server implementation.
function Provider.giveItemToPlayer()
    return false, 'unsupported_inventory'
end

PyImageDetector.Providers[Provider.Resource] = Provider
