PyImageDetector = PyImageDetector or {}
PyImageDetector.Providers = PyImageDetector.Providers or {}

local Provider = {}

Provider.Resource = 'ps-inventory'
Provider.DisplayName = 'ps-inventory'
Provider.ImageWebPath = 'html/images'
Provider.ImageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'svg',
    'webp',
}
Provider.DefaultImageExtension = 'png'
Provider.RequiredResources = {
    'qb-core',
}

local inventoryLimits

-- ps-inventory keeps item images inside its html image folder.
function Provider.getImageDirectory()
    local resourcePath = GetResourcePath(Provider.Resource)
    if not resourcePath then return nil end

    return ('%s/%s'):format(resourcePath, Provider.ImageWebPath)
end

local function getQBCore()
    local ok, core = pcall(function()
        return exports['qb-core']:GetCoreObject()
    end)

    if ok and type(core) == 'table' then
        return core
    end

    return nil, ('Failed to read qb-core object: %s'):format(tostring(core))
end

-- Reads ps-inventory's configured weight and slot limits without requiring this resource to depend on it.
local function getInventoryLimits()
    if inventoryLimits then return inventoryLimits end

    local defaults = {
        maxWeight = 120000,
        maxSlots = 41,
    }

    local file = LoadResourceFile(Provider.Resource, 'config.lua')
    if not file then
        inventoryLimits = defaults
        return inventoryLimits
    end

    local env = setmetatable({
        Config = {},
    }, { __index = _ENV })

    local chunk = load(file, ('@@%s/config.lua'):format(Provider.Resource), 't', env)
    if not chunk then
        inventoryLimits = defaults
        return inventoryLimits
    end

    local ok = pcall(chunk)
    if not ok then
        inventoryLimits = defaults
        return inventoryLimits
    end

    inventoryLimits = {
        maxWeight = tonumber(env.Config.MaxInventoryWeight) or defaults.maxWeight,
        maxSlots = tonumber(env.Config.MaxInventorySlots) or defaults.maxSlots,
    }

    return inventoryLimits
end

-- Reads QBCore shared items, which is the item source used by ps-inventory.
function Provider.getItems()
    local ok, items = pcall(function()
        return exports['qb-core']:GetSharedItems()
    end)

    if not ok or type(items) ~= 'table' then
        local core, coreErr = getQBCore()
        if not core then return nil, coreErr end

        items = core.Shared and core.Shared.Items
    end

    if type(items) ~= 'table' then
        return nil, 'qb-core did not expose shared items for ps-inventory.'
    end

    local allItems = {}
    for itemName, itemData in pairs(items) do
        if type(itemData) == 'table' then
            allItems[itemName] = itemData
        end
    end

    if not next(allItems) then
        return nil, 'qb-core shared items table is empty.'
    end

    return allItems, {}
end

-- ps-inventory item definitions can define a custom image directly on the QBCore item data.
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

local function getTotalWeight(items)
    local weight = 0
    if type(items) ~= 'table' then return weight end

    for _, item in pairs(items) do
        if type(item) == 'table' then
            local itemWeight = tonumber(item.weight) or 0
            local itemAmount = tonumber(item.amount) or 0
            weight = weight + (itemWeight * itemAmount)
        end
    end

    return weight
end

local function hasStackSlot(items, itemName)
    if type(items) ~= 'table' then return false end

    itemName = itemName:lower()
    for _, item in pairs(items) do
        if type(item) == 'table' and type(item.name) == 'string' and item.name:lower() == itemName then
            local itemInfo = type(item.info) == 'table' and item.info or nil
            if item.type == 'item' and item.unique ~= true and itemInfo and itemInfo.quality == 100 then
                return true
            end
        end
    end

    return false
end

local function hasEmptySlot(items, maxSlots)
    if type(items) ~= 'table' then return true end

    for slot = 1, maxSlots do
        if items[slot] == nil then
            return true
        end
    end

    return false
end

local function canCarryItem(source, itemName, amount, itemData)
    local core, coreErr = getQBCore()
    if not core then return false, coreErr end

    if type(core.Functions) ~= 'table' or type(core.Functions.GetPlayer) ~= 'function' then
        return false, 'qb_core_missing_get_player'
    end

    local player = core.Functions.GetPlayer(source)
    if not player or type(player.PlayerData) ~= 'table' then
        return false, 'invalid_player'
    end

    local limits = getInventoryLimits()
    local items = player.PlayerData.items or {}
    local itemWeight = tonumber(itemData.weight) or 0

    if (getTotalWeight(items) + (itemWeight * amount)) > limits.maxWeight then
        return false, 'inventory_full'
    end

    if itemData.unique ~= true and itemData.type == 'item' and hasStackSlot(items, itemName) then
        return true
    end

    if hasEmptySlot(items, limits.maxSlots) then
        return true
    end

    return false, 'inventory_full'
end

-- Gives one item to an admin after checking ps-inventory's weight and slot limits server-side.
function Provider.giveItemToPlayer(source, itemName, amount)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'invalid_amount' end

    local items, err = Provider.getItems()
    if not items then return false, err end

    local itemData = items[itemName] or items[itemName:lower()]
    if type(itemData) ~= 'table' then return false, 'invalid_item' end

    local canCarry, carryErr = canCarryItem(source, itemName, amount, itemData)
    if not canCarry then
        return false, carryErr or 'inventory_full'
    end

    local addOk, added = pcall(function()
        return exports['ps-inventory']:AddItem(source, itemName, amount)
    end)

    if addOk and added == true then
        return true, 'added'
    end

    return false, addOk and 'add_failed' or ('add_failed:%s'):format(tostring(added))
end

PyImageDetector.Providers[Provider.Resource] = Provider
