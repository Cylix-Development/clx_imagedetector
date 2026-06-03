PyImageDetector = PyImageDetector or {}
PyImageDetector.Providers = PyImageDetector.Providers or {}

local Provider = {}

Provider.Resource = 'jaksam_inventory'
Provider.DisplayName = 'jaksam_inventory'
Provider.ImageWebPath = '_images'
Provider.ImageExtensions = {
    'png',
    'webp',
}
Provider.RequiredResources = {
    'jaksam_core',
}

-- jaksam_inventory stores custom item images in the resource-level _images folder.
function Provider.getImageDirectory()
    local resourcePath = GetResourcePath(Provider.Resource)
    if not resourcePath then return nil end

    return ('%s/%s'):format(resourcePath, Provider.ImageWebPath)
end

-- Adds one item definition into the normalized item index.
local function addItem(target, itemName, itemData)
    if type(itemData) ~= 'table' then itemData = {} end

    if type(itemName) ~= 'string' and type(itemData.name) == 'string' then
        itemName = itemData.name
    end

    if type(itemName) ~= 'string' or itemName == '' then return end

    target[itemName] = itemData
end

-- Reads the static item registry through jaksam_inventory's documented shared export.
function Provider.getItems()
    local ok, items = pcall(function()
        return exports['jaksam_inventory']:getStaticItemsList()
    end)

    if not ok then
        return nil, ('Failed to read jaksam static items: %s'):format(tostring(items))
    end

    if type(items) ~= 'table' then
        return nil, 'jaksam_inventory getStaticItemsList() did not return a table.'
    end

    local allItems = {}
    for itemName, itemData in pairs(items) do
        addItem(allItems, itemName, itemData)
    end

    if not next(allItems) then
        return nil, 'jaksam_inventory returned no static items.'
    end

    return allItems, {}
end

-- jaksam item definitions can define a custom image directly on the item data.
function Provider.getConfiguredImage(itemData)
    if type(itemData) ~= 'table' then return nil end

    if type(itemData.image) == 'string' and itemData.image ~= '' then
        return itemData.image
    end

    local client = itemData.client
    if type(client) == 'table' and type(client.image) == 'string' and client.image ~= '' then
        return client.image
    end

    return nil
end

-- Gives one item to an admin after jaksam_inventory confirms weight and slot limits.
function Provider.giveItemToPlayer(source, itemName, amount)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'invalid_amount' end

    local itemOk, itemData = pcall(function()
        return exports['jaksam_inventory']:getStaticItem(itemName)
    end)

    if not itemOk then
        return false, ('item_lookup_failed:%s'):format(tostring(itemData))
    end

    if type(itemData) ~= 'table' then
        return false, 'invalid_item'
    end

    local canCarryOk, canCarry = pcall(function()
        return exports['jaksam_inventory']:canCarryItem(source, itemName, amount)
    end)

    if not canCarryOk then
        return false, ('can_carry_failed:%s'):format(tostring(canCarry))
    end

    if canCarry ~= true then
        return false, 'inventory_full'
    end

    local addOk, added, resultCode = pcall(function()
        return exports['jaksam_inventory']:addItem(source, itemName, amount)
    end)

    if not addOk then
        return false, ('add_failed:%s'):format(tostring(added))
    end

    if added == true then
        return true, resultCode or 'added'
    end

    return false, resultCode or 'add_failed'
end

PyImageDetector.Providers[Provider.Resource] = Provider
