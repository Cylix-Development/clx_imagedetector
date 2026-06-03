local uiOpen = false
local nextRequestId = 0
local pendingRequests = {}

local function notify(data)
    if type(data) ~= 'table' then return end

    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(data.description or '')
    EndTextCommandThefeedPostTicker(false, false)
end

-- Wraps NUI-to-server requests with request ids and a timeout for long scans.
local function requestServer(action, payload, cb)
    nextRequestId = nextRequestId + 1
    local requestId = nextRequestId

    pendingRequests[requestId] = cb
    TriggerServerEvent('clx_imagedetector:server:request', requestId, action, payload or {})

    local timeout = action == 'scan' and 300000 or 10000

    SetTimeout(timeout, function()
        local pending = pendingRequests[requestId]
        if not pending then return end

        pendingRequests[requestId] = nil
        pending({
            ok = false,
            error = 'No response received from the server.',
        })
    end)
end

local function setUiOpen(open, payload)
    uiOpen = open == true
    SetNuiFocus(uiOpen, uiOpen)

    SendNUIMessage({
        action = uiOpen and 'open' or 'close',
        payload = payload or {},
    })
end

RegisterNetEvent('clx_imagedetector:client:openUi', function(payload)
    setUiOpen(true, payload)
end)

RegisterNetEvent('clx_imagedetector:client:notify', function(data)
    notify(data)
end)

RegisterNetEvent('clx_imagedetector:client:response', function(requestId, response)
    local cb = pendingRequests[requestId]
    if not cb then return end

    pendingRequests[requestId] = nil
    cb(response)
end)

RegisterNetEvent('clx_imagedetector:client:scanProgress', function(payload)
    SendNUIMessage({
        action = 'scanProgress',
        payload = payload or {},
    })
end)

RegisterNUICallback('close', function(_, cb)
    setUiOpen(false)
    cb({ ok = true })
end)

RegisterNUICallback('scan', function(_, cb)
    requestServer('scan', {}, function(result)
        cb(result or {
            ok = false,
            error = 'No response received from the server.',
        })
    end)
end)

RegisterNUICallback('cancelScan', function(_, cb)
    requestServer('cancelScan', {}, function(result)
        cb(result or {
            ok = false,
            error = 'No response received from the server.',
        })
    end)
end)

RegisterNUICallback('giveItem', function(data, cb)
    local itemName = type(data) == 'table' and data.item or nil

    requestServer('giveItem', { item = itemName }, function(result)
        cb(result or {
            ok = false,
            error = 'No response received from the server.',
        })
    end)
end)

RegisterNUICallback('ready', function(_, cb)
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() or not uiOpen then return end

    SetNuiFocus(false, false)
end)
