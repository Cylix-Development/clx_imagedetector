Config = {}

-- Enables the detector, admin UI, command and server export.
Config.Enabled = true

--[[
    Supported inventories are:
    'ox_inventory'
    'qb-inventory'
    'ps-inventory'
    'qs-inventory'
    'esx_inventory'
    'jaksam_inventory'
    'tgiann-inventory'
    'origen_inventory'
    'codem-inventory'
    'core_inventory'
]]
-- The inventory that you are using on your server. Use 'auto' to detect the started inventory resource.
Config.Inventory = 'auto'

-- Delay in milliseconds before scans, giving inventory resources time to finish loading.
Config.ScanDelay = 1000

-- Automatically prints a console scan when this resource starts.
Config.StartupScan = false

-- When true, image names must match item names with the exact same casing.
Config.CaseSensitive = false

-- Prints images that exist in the inventory image folder but are not linked to an item.
Config.ReportUnusedImages = true

Config.Ui = {
    -- Enables the in-game admin UI and server export entrypoint.
    Enabled = true,

    Command = {
        -- Registers an in-game command when enabled.
        Enabled = true,

        -- Command name used by admins to open the UI.
        Name = 'imagedetector',
    },

    Admin = {
        -- ACE permissions accepted for UI access.
        AcePermissions = {
            'clx_imagedetector.admin',
            'command.imagedetector',
            'command.clx_imagedetector',
        },

        -- Optional identifier allowlist for servers that do not use ACE.
        Identifiers = {
            -- 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        },
    },
}

-- Optional item image overrides. Values may include or omit the image extension.
Config.ItemImages = {
    -- ['example_item'] = 'custom_image',
}
