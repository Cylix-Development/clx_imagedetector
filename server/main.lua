local Access = PyImageDetector.Access
local Logger = PyImageDetector.Logger
local Reporter = PyImageDetector.Reporter
local Scanner = PyImageDetector.Scanner
local scanInProgress = false
local activeScan = nil

local function isUiEnabled()
    return Config.Enabled and type(Config.Ui) == 'table' and Config.Ui.Enabled ~= false
end

local function runScan(progressCallback, cancelCallback)
    local report, err = Scanner.run(Config, progressCallback, cancelCallback)
    if not report then
        return false, err or 'Scan failed without an error message.'
    end

    return true, report
end

local function getProvider()
    local provider, providerErr = Scanner.resolveProvider(Config)
    if not provider then
        return nil, providerErr or ('Unsupported inventory: %s'):format(tostring(Config.Inventory))
    end

    return provider
end

local function isMissingItem(report, itemName)
    for i = 1, #report.missingItems do
        if report.missingItems[i].item == itemName then
            return true
        end
    end

    return false
end

local function notifyPlayer(source, description, notifyType)
    if source and source > 0 then
        TriggerClientEvent('clx_imagedetector:client:notify', source, {
            description = description,
            type = notifyType or 'inform',
        })
    end
end

local function openAdminUi(source, reason)
    source = tonumber(source)

    if not source or source <= 0 then
        return false, 'A valid player source is needed to open the UI.'
    end

    if not isUiEnabled() then
        return false, 'The image detector UI is disabled.'
    end

    if not Access.isAllowed(source, Config) then
        Logger.warn(('Denied UI access for player %s via %s.'):format(source, reason or 'unknown'))
        return false, 'You do not have access to this tool.'
    end

    TriggerClientEvent('clx_imagedetector:client:openUi', source, {
        inventory = Config.Inventory,
        caseSensitive = Config.CaseSensitive == true,
        reportUnusedImages = Config.ReportUnusedImages ~= false,
    })

    return true
end

if not Config.Enabled then
    Logger.warn('Image detector is disabled in config.')
elseif Config.StartupScan ~= false then
    CreateThread(function()
        -- Delay avoids racing inventory resources during server startup.
        local delay = tonumber(Config.ScanDelay) or 0
        if delay > 0 then
            Wait(delay)
        end

        Logger.info(('Starting %s image scan...'):format(tostring(Config.Inventory)))

        local ok, reportOrErr = runScan()
        if not ok then
            Logger.error(reportOrErr)
            return
        end

        -- Keep output formatting separate from scan logic.
        Reporter.print(reportOrErr)
    end)
end

local commandConfig = type(Config.Ui) == 'table' and type(Config.Ui.Command) == 'table' and Config.Ui.Command or nil
if Config.Enabled and commandConfig and commandConfig.Enabled == true and type(commandConfig.Name) == 'string' and commandConfig.Name ~= '' then
    RegisterCommand(commandConfig.Name, function(source)
        if source <= 0 then
            local ok, reportOrErr = runScan()
            if not ok then
                Logger.error(reportOrErr)
                return
            end

            Reporter.print(reportOrErr)
            return
        end

        local ok, err = openAdminUi(source, 'command')
        if not ok then
            notifyPlayer(source, err, 'error')
        end
    end, false)
end

local function handleRunScan(source)
    if not isUiEnabled() then
        return {
            ok = false,
            error = 'The image detector is currently unavailable.',
        }
    end

    if not Access.isAllowed(source, Config) then
        Logger.warn(('Denied scan request for player %s.'):format(source))

        return {
            ok = false,
            error = 'You do not have access to this tool.',
        }
    end

    if scanInProgress then
        return {
            ok = false,
            error = 'An image scan is already running.',
        }
    end

    scanInProgress = true
    activeScan = {
        source = source,
        cancelRequested = false,
    }

    local delay = tonumber(Config.ScanDelay) or 0
    if delay > 0 then
        Wait(delay)
    end

    local ok, scanOk, reportOrErr = pcall(function()
        return runScan(function(progress)
            if source and source > 0 then
                TriggerClientEvent('clx_imagedetector:client:scanProgress', source, progress)
            end
        end, function()
            return type(activeScan) == 'table' and activeScan.cancelRequested == true
        end)
    end)
    activeScan = nil
    scanInProgress = false

    if not ok then
        Logger.error(reportOrErr)

        return {
            ok = false,
            error = tostring(reportOrErr or 'Scan failed.'),
        }
    end

    if not scanOk then
        Logger.error(reportOrErr)

        return {
            ok = false,
            error = reportOrErr,
        }
    end

    return {
        ok = true,
        report = reportOrErr,
    }
end

local function handleCancelScan(source)
    if not isUiEnabled() then
        return {
            ok = false,
            error = 'The image detector is currently unavailable.',
        }
    end

    if not Access.isAllowed(source, Config) then
        Logger.warn(('Denied cancel scan request for player %s.'):format(source))

        return {
            ok = false,
            error = 'You do not have access to this tool.',
        }
    end

    if not scanInProgress or not activeScan then
        return {
            ok = false,
            error = 'No image scan is running.',
        }
    end

    if tonumber(activeScan.source) ~= tonumber(source) then
        return {
            ok = false,
            error = 'You can only cancel your own image scan.',
        }
    end

    activeScan.cancelRequested = true

    return {
        ok = true,
        message = 'Cancel requested.',
    }
end

local function handleGiveMissingItem(source, itemName)
    if not isUiEnabled() then
        return {
            ok = false,
            error = 'The image detector is currently unavailable.',
        }
    end

    if not Access.isAllowed(source, Config) then
        Logger.warn(('Denied give item request for player %s.'):format(source))

        return {
            ok = false,
            error = 'You do not have access to this tool.',
        }
    end

    if type(itemName) ~= 'string' or itemName == '' then
        return {
            ok = false,
            error = 'Invalid item.',
        }
    end

    local ok, reportOrErr = runScan()
    if not ok then
        Logger.error(reportOrErr)

        return {
            ok = false,
            error = reportOrErr,
        }
    end

    if not isMissingItem(reportOrErr, itemName) then
        return {
            ok = false,
            error = 'This item is not in the missing images list.',
        }
    end

    local provider, providerErr = getProvider()
    if not provider or type(provider.giveItemToPlayer) ~= 'function' then
        return {
            ok = false,
            error = providerErr or 'This inventory does not support this action.',
        }
    end

    local added, response = provider.giveItemToPlayer(source, itemName, 1)
    if not added then
        return {
            ok = false,
            error = ('Giving item failed: %s'):format(response or 'unknown'),
        }
    end

    local dropped = response == 'dropped'
    return {
        ok = true,
        message = dropped and 'You could not carry this item, so it was placed on the ground.' or 'Item added.',
    }
end

RegisterNetEvent('clx_imagedetector:server:request', function(requestId, action, payload)
    local src = source
    local response

    if action == 'scan' then
        response = handleRunScan(src)
    elseif action == 'cancelScan' then
        response = handleCancelScan(src)
    elseif action == 'giveItem' then
        local itemName = type(payload) == 'table' and payload.item or nil
        response = handleGiveMissingItem(src, itemName)
    else
        response = {
            ok = false,
            error = 'Unknown action.',
        }
    end

    TriggerClientEvent('clx_imagedetector:client:response', src, requestId, response)
end)

exports('OpenAdminUi', function(source)
    return openAdminUi(source, 'export')
end)
