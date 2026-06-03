PyImageDetector = PyImageDetector or {}
PyImageDetector.Providers = PyImageDetector.Providers or {}

local Provider = {}

Provider.Resource = 'ox_inventory'
Provider.DisplayName = 'ox_inventory'
Provider.ImageWebPath = 'web/images'
Provider.RequiredResources = {}

local weaponCategories = {
    'Weapons',
    'Components',
    'Ammo',
}

-- Loads a Lua data file from ox_inventory without caching the result.
local function loadDataFile(path)
    local file = LoadResourceFile(Provider.Resource, ('%s.lua'):format(path))
    if not file then
        return nil, ('Failed to load @%s/%s.lua'):format(Provider.Resource, path)
    end

    local chunk, chunkErr = load(file, ('@@%s/%s.lua'):format(Provider.Resource, path), 't', _ENV)
    if not chunk then
        return nil, ('Failed to parse @%s/%s.lua: %s'):format(Provider.Resource, path, chunkErr)
    end

    local ok, result = pcall(chunk)
    if not ok then
        return nil, ('Failed to execute @%s/%s.lua: %s'):format(Provider.Resource, path, result)
    end

    if type(result) ~= 'table' then
        return nil, ('@%s/%s.lua did not return a table.'):format(Provider.Resource, path)
    end

    return result
end

-- Merges a table into the item index by item name.
local function mergeItems(target, source)
    for itemName, itemData in pairs(source) do
        target[itemName] = itemData or {}
    end
end

function Provider.getImageDirectory()
    local resourcePath = GetResourcePath(Provider.Resource)
    if not resourcePath then return nil end

    return ('%s/%s'):format(resourcePath, Provider.ImageWebPath)
end

function Provider.getItems()
    local items, err = loadDataFile('data/items')
    if not items then return nil, err end

    local allItems = {}
    local warnings = {}
    mergeItems(allItems, items)

    local weapons, weaponsErr = loadDataFile('data/weapons')
    if weapons then
        for i = 1, #weaponCategories do
            local category = weapons[weaponCategories[i]]
            if type(category) == 'table' then
                mergeItems(allItems, category)
            end
        end
    else
        warnings[#warnings + 1] = weaponsErr
    end

    return allItems, warnings
end

function Provider.getConfiguredImage(itemData)
    if type(itemData) ~= 'table' then return nil end

    local client = itemData.client
    if type(client) == 'table' and type(client.image) == 'string' and client.image ~= '' then
        return client.image
    end

    return nil
end

-- Gives one item to an admin, or drops it at their feet when their inventory is full.
function Provider.giveItemToPlayer(source, itemName, amount)
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false, 'invalid_amount' end

    local itemData = exports.ox_inventory:Items(itemName)
    if not itemData then return false, 'invalid_item' end

    if exports.ox_inventory:CanCarryItem(source, itemName, amount) then
        local added, response = exports.ox_inventory:AddItem(source, itemName, amount)
        if added then
            return true, response or 'added'
        end
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return false, 'invalid_player' end

    local coords = GetEntityCoords(ped)
    local dropItems = { { itemName, amount } }
    local ok, dropId = pcall(function()
        return exports.ox_inventory:CustomDrop(
            itemData.label or itemName,
            dropItems,
            vector3(coords.x, coords.y, coords.z - 0.2),
            #dropItems,
            nil,
            Player(source).state.instance
        )
    end)

    if ok and dropId then
        return true, 'dropped'
    end

    return false, 'inventory_full'
end

PyImageDetector.Providers[Provider.Resource] = Provider
