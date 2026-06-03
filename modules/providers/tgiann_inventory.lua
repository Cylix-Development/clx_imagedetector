PyImageDetector = PyImageDetector or {}
PyImageDetector.Providers = PyImageDetector.Providers or {}

local Provider = {}

Provider.Resource = 'tgiann-inventory'
Provider.DisplayName = 'tgiann-inventory'
Provider.ImageResource = 'inventory_images'
Provider.ImageWebPath = 'images'
Provider.ImageExtensions = {
    'webp',
    'png',
}
Provider.DefaultImageExtension = 'webp'
Provider.RequiredResources = {}

-- tgiann-inventory serves item images from the separate inventory_images resource.
function Provider.getImageDirectory()
    local resourcePath = GetResourcePath(Provider.ImageResource)
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

-- Reads item definitions through tgiann-inventory's documented server exports.
local function readItemList()
    local rawOk, rawItems = pcall(function()
        return exports['tgiann-inventory']:ItemsRaw()
    end)

    if rawOk and type(rawItems) == 'table' then
        return rawItems
    end

    local listOk, listItems = pcall(function()
        return exports['tgiann-inventory']:GetItemList()
    end)

    if listOk and type(listItems) == 'table' then
        return listItems
    end

    local itemsOk, items = pcall(function()
        return exports['tgiann-inventory']:Items()
    end)

    if itemsOk and type(items) == 'table' then
        return items
    end

    return nil, ('Failed to read tgiann item list: %s / %s / %s'):format(tostring(rawItems), tostring(listItems), tostring(items))
end

function Provider.getItems()
    local items, err = readItemList()
    if not items then return nil, err end

    local allItems = {}
    for itemName, itemData in pairs(items) do
        addItem(allItems, itemName, itemData)
    end

    if not next(allItems) then
        return nil, 'tgiann-inventory returned no items.'
    end

    return allItems, {}
end

-- tgiann defaults to itemName.webp, but item definitions can override image.
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

-- Gives one item to an admin after tgiann-inventory confirms they can carry it.
function Provider.giveItemToPlayer(source, itemName, amount)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'invalid_amount' end

    local itemOk, itemData = pcall(function()
        return exports['tgiann-inventory']:ItemsRaw(itemName)
    end)

    if not itemOk or type(itemData) ~= 'table' then
        local fallbackOk, fallbackItem = pcall(function()
            return exports['tgiann-inventory']:GetItemList(itemName)
        end)

        if not fallbackOk or type(fallbackItem) ~= 'table' then
            return false, itemOk and 'invalid_item' or ('item_lookup_failed:%s'):format(tostring(itemData))
        end
    end

    local canCarryOk, canCarry = pcall(function()
        return exports['tgiann-inventory']:CanCarryItem(source, itemName, amount)
    end)

    if not canCarryOk then
        return false, ('can_carry_failed:%s'):format(tostring(canCarry))
    end

    if canCarry ~= true then
        return false, 'inventory_full'
    end

    local addOk, added = pcall(function()
        return exports['tgiann-inventory']:AddItem(source, itemName, amount)
    end)

    if addOk and added == true then
        return true, 'added'
    end

    return false, addOk and 'add_failed' or ('add_failed:%s'):format(tostring(added))
end

PyImageDetector.Providers[Provider.Resource] = Provider
