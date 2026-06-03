fx_version "adamant"
game "gta5"
use_fxv2_oal "yes"
lua54 "yes"

name "clx_imagedetector"
author "Cylix Development"
version "1.0.0"

client_scripts {
    "client/main.lua"
}

server_scripts {
    "config.lua",
    "modules/logger.lua",
    "modules/access.lua",
    "modules/filesystem.lua",
    "modules/providers/ox_inventory.lua",
    "modules/providers/qb_inventory.lua",
    "modules/providers/ps_inventory.lua",
    "modules/providers/qs_inventory.lua",
    "modules/providers/esx_inventory.lua",
    "modules/providers/jaksam_inventory.lua",
    "modules/providers/tgiann_inventory.lua",
    "modules/providers/origen_inventory.lua",
    "modules/providers/codem_inventory.lua",
    "modules/providers/core_inventory.lua",
    "modules/scanner.lua",
    "modules/reporter.lua",
    "server/version.lua",
    "server/main.lua"
}

ui_page "web/index.html"

files {
    "web/index.html",
    "web/dist/app.css",
    "web/dist/main.js"
}
