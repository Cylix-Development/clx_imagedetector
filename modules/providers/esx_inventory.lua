PyImageDetector = PyImageDetector or {}
PyImageDetector.Providers = PyImageDetector.Providers or {}

local Provider = {}

Provider.Resource = 'esx_inventory'
Provider.DisplayName = 'esx_inventory'
Provider.ImageWebPath = 'html/img/items'
Provider.RequiredResources = {
    'es_extended',
}

local cachedEsx = nil

-- esx_inventory uses item ids directly in html/img/items/<item>.png.
function Provider.getImageDirectory()
    local resourcePath = GetResourcePath(Provider.Resource)
    if not resourcePath then return nil end

    return ('%s/%s'):format(resourcePath, Provider.ImageWebPath)
end

-- Resolves the ESX shared object through the export first, then the legacy event.
local function getEsxObject()
    if type(cachedEsx) == 'table' then return cachedEsx end

    local exportOk, exportResult = pcall(function()
        return exports['es_extended']:getSharedObject()
    end)

    if exportOk and type(exportResult) == 'table' then
        cachedEsx = exportResult
        return cachedEsx
    end

    local eventResult = nil
    local eventOk = pcall(function()
        TriggerEvent('esx:getSharedObject', function(object)
            eventResult = object
        end)
    end)

    if eventOk and type(eventResult) == 'table' then
        cachedEsx = eventResult
        return cachedEsx
    end

    return nil, ('Failed to resolve ESX shared object: %s'):format(tostring(exportResult))
end

-- Adds one ESX item definition into the normalized item index.
local function addItem(target, itemName, itemData)
    if type(itemData) ~= 'table' then itemData = {} end

    if type(itemName) ~= 'string' and type(itemData.name) == 'string' then
        itemName = itemData.name
    end

    if type(itemName) ~= 'string' or itemName == '' then return end

    target[itemName] = itemData
end

-- Reads item definitions from ESX, which is the public source used by this inventory.
function Provider.getItems()
    local esx, err = getEsxObject()
    if not esx then return nil, err end

    if type(esx.Items) ~= 'table' then
        return nil, 'es_extended did not expose ESX.Items as a table.'
    end

    local allItems = {}
    for itemName, itemData in pairs(esx.Items) do
        addItem(allItems, itemName, itemData)
    end

    if not next(allItems) then
        return nil, 'es_extended returned no items. Ensure es_extended has loaded its items table before scanning.'
    end

    return allItems, {}
end

-- Some ESX forks add custom image fields; the inspected esx_inventory does not.
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

-- Returns the current count for verification after an ESX add operation.
local function getInventoryCount(xPlayer, itemName)
    if type(xPlayer.getInventoryItem) ~= 'function' then return nil end

    local ok, item = pcall(function()
        return xPlayer.getInventoryItem(itemName)
    end)

    if ok and type(item) == 'table' and type(item.count) == 'number' then
        return item.count
    end

    return nil
end

-- Gives one item to an admin through ESX so esx_inventory receives its normal events.
function Provider.giveItemToPlayer(source, itemName, amount)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'invalid_amount' end

    local esx, err = getEsxObject()
    if not esx then return false, err or 'esx_unavailable' end

    if type(esx.Items) ~= 'table' or not esx.Items[itemName] then
        return false, 'invalid_item'
    end

    -- This inspected ESX build chunks adds by item.limit; non-positive limits are unsafe here.
    local itemData = esx.Items[itemName]
    if type(itemData) == 'table' and type(itemData.limit) == 'number' and itemData.limit <= 0 then
        return false, 'invalid_item_limit'
    end

    if type(esx.GetPlayerFromId) ~= 'function' then
        return false, 'missing_get_player'
    end

    local xPlayer = esx.GetPlayerFromId(source)
    if type(xPlayer) ~= 'table' then return false, 'invalid_player' end

    if type(xPlayer.canCarryItem) == 'function' then
        local canCarryOk, canCarry = pcall(function()
            return xPlayer.canCarryItem(itemName, amount)
        end)

        if not canCarryOk then
            return false, ('can_carry_failed:%s'):format(tostring(canCarry))
        end

        if canCarry ~= true then
            return false, 'inventory_full'
        end
    end

    if type(xPlayer.addInventoryItem) ~= 'function' then
        return false, 'missing_add_item'
    end

    local beforeCount = getInventoryCount(xPlayer, itemName)
    local addOk, addErr = pcall(function()
        xPlayer.addInventoryItem(itemName, amount)
    end)

    if not addOk then
        return false, ('add_failed:%s'):format(tostring(addErr))
    end

    local afterCount = getInventoryCount(xPlayer, itemName)
    if beforeCount and afterCount and afterCount < beforeCount + amount then
        return false, 'add_failed'
    end

    return true, 'added'
end

PyImageDetector.Providers[Provider.Resource] = Provider
