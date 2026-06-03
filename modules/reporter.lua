PyImageDetector = PyImageDetector or {}

local Logger = PyImageDetector.Logger

local Reporter = {}

-- Adds the expected image name when it differs from the item name.
local function formatMissingEntry(entry)
    local imageFile = entry.imageFile or ('%s.png'):format(entry.image)

    if entry.item == entry.image then
        return imageFile
    end

    return ('%s -> %s'):format(entry.item, imageFile)
end

-- Prints non-fatal scan issues, such as optional files that could not be read.
local function printWarnings(warnings)
    if #warnings == 0 then return end

    print('')
    Logger.warn(('Warnings (%s):'):format(#warnings))
    for i = 1, #warnings do
        print(('  [^5%s^7] %s'):format(i, warnings[i]))
    end
end

-- Prints every missing item image in deterministic order.
local function printMissingItems(items)
    print('')

    if #items == 0 then
        Logger.ok('All items have a corresponding image.')
        return
    end

    print(('^1[MISSING]^7 Items without image (%s):'):format(#items))
    for i = 1, #items do
        print(('  [^5%s^7] %s'):format(i, formatMissingEntry(items[i])))
    end
end

-- Prints unused inventory image files when enabled in config.
local function printUnusedImages(images, enabled)
    print('')

    if not enabled then
        Logger.info('Unused image reporting is disabled in config.')
        return
    end

    if #images == 0 then
        Logger.ok('No unused images found.')
        return
    end

    print(('^1[UNUSED]^7 Images without a linked item (%s):'):format(#images))
    for i = 1, #images do
        print(('  [^5%s^7] %s'):format(i, images[i]))
    end
end

-- Prints a compact scan summary for the server console.
local function printSummary(report)
    print('')
    Logger.info('Summary:')
    print(('  ^7Inventory:       ^3%s^7'):format(report.inventory))
    print(('  ^7Image folder:    ^3%s^7'):format(report.imageDirectory))
    print(('  ^7Items checked:   ^3%s^7'):format(report.itemCount))
    print(('  ^7Images found:    ^3%s^7'):format(report.imageCount))
    print(('  ^7Missing images:  ^1%s^7'):format(#report.missingItems))
    print(('  ^7Unused images:   ^1%s^7'):format(#report.unusedImages))
end

function Reporter.print(report)
    -- Reporter only formats a finished report and does not mutate scan data.
    Logger.info('Scan completed.')
    printWarnings(report.warnings)
    printMissingItems(report.missingItems)
    printUnusedImages(report.unusedImages, report.reportUnusedImages)
    printSummary(report)
end

PyImageDetector.Reporter = Reporter
