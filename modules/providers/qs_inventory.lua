PyImageDetector = PyImageDetector or {}
PyImageDetector.Providers = PyImageDetector.Providers or {}

local Provider = {}

Provider.Resource = 'qs-inventory'
Provider.DisplayName = 'qs-inventory'
Provider.ImageWebPath = 'html/images'
Provider.RequiredResources = {}

-- qs-inventory keeps item images inside its html image folder.
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

-- Merges Quasar item and weapon export lists into one scan index.
local function mergeList(target, source)
    if type(source) ~= 'table' then return end

    for itemName, itemData in pairs(source) do
        addItem(target, itemName, itemData)
    end
end

-- Reads qs-inventory item definitions through its documented server exports.
function Provider.getItems()
    local allItems = {}
    local warnings = {}

    local okItems, items = pcall(function()
        return exports['qs-inventory']:GetItemList()
    end)

    if okItems and type(items) == 'table' then
        mergeList(allItems, items)
    else
        warnings[#warnings + 1] = ('GetItemList failed: %s'):format(tostring(items))
    end

    local okWeapons, weapons = pcall(function()
        return exports['qs-inventory']:GetWeaponList()
    end)

    if okWeapons and type(weapons) == 'table' then
        mergeList(allItems, weapons)
    elseif not okWeapons then
        warnings[#warnings + 1] = ('GetWeaponList failed: %s'):format(tostring(weapons))
    end

    if not next(allItems) then
        return nil, 'qs-inventory did not return any items through GetItemList or GetWeaponList.'
    end

    return allItems, warnings
end

-- qs item definitions can define a custom image directly on the item data.
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

-- Gives one item to an admin when qs-inventory confirms they can carry it.
function Provider.giveItemToPlayer(source, itemName, amount)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'invalid_amount' end

    local canCarryOk, canCarry = pcall(function()
        return exports['qs-inventory']:CanCarryItem(source, itemName, amount)
    end)

    if not canCarryOk then
        return false, ('can_carry_failed:%s'):format(tostring(canCarry))
    end

    if canCarry ~= true then
        return false, 'inventory_full'
    end

    local addOk, added = pcall(function()
        return exports['qs-inventory']:AddItem(source, itemName, amount)
    end)

    if addOk and added ~= false then
        return true, 'added'
    end

    return false, ('add_failed:%s'):format(tostring(added))
end

PyImageDetector.Providers[Provider.Resource] = Provider
