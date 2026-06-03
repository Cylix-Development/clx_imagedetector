# CLX Image Detector

CLX Image Detector is a FiveM admin utility for checking whether inventory items have matching image files. It helps server owners and developers keep inventory assets clean by reporting missing item images and unused image files from a simple in-game admin UI.

## Ownership

This resource is owned and maintained by **Cylix Development**.

## About Cylix Development

Cylix Development creates practical FiveM resources with a focus on stable server behavior, clean user interfaces, and maintainable code. Our scripts are built for real server workflows, with attention to performance, admin tooling, and long-term readability.

## Links

Support Discord:

https://discord.gg/MrWM4RxEc2

GitHub repository:

https://github.com/Cylix-Development/clx_imagedetector

Script preview:

https://medal.tv/games/gta-v/clips/mQmvLqzcnKLC-Rk8z?invite=cr-MSxiRFUsNTA3MzAxNTYz

## Features

- Admin-only NUI panel for image scanning.
- Manual scan button from the UI.
- Optional console scan on resource start.
- Server-side permission checks before opening the UI and before scanning.
- Compares inventory item definitions with the configured inventory image folder.
- Reports items that are missing an image.
- Reports image files that are not used by any item.
- Shows item labels in the missing image report when the inventory exposes them.
- Search support with `*` wildcards.
- Live scan progress with estimated remaining time.
- Live counters for missing images and unused images.
- Cancel scan support.
- Optional plus action to give a missing item for testing when the active inventory provider supports it.
- Case-sensitive or case-insensitive matching.
- Optional item image overrides through config.
- GitHub release check.

## Supported Inventories

The script can auto-detect a started supported inventory resource, or you can set the inventory manually in `config.lua`.

Supported values:

- `auto`
- `ox_inventory`
- `qb-inventory`
- `ps-inventory`
- `qs-inventory`
- `esx_inventory`
- `jaksam_inventory`
- `tgiann-inventory`
- `origen_inventory`
- `codem-inventory`
- `core_inventory`

## Requirements

- FiveM server artifact with Lua 5.4 enabled.
- NUI support.
- One supported inventory resource.
- Inventory item definitions and image folder access through the selected provider.
- No database is required.

## Installation

1. Place the resource in your FiveM resources folder.
2. Use the intended resource name:

```cfg
clx_imagedetector
```

3. Make sure your inventory resource starts before this resource.
4. Add the resource to your `server.cfg`:

```cfg
ensure clx_imagedetector
```

5. Configure the inventory provider and admin permissions.

## Usage

Open the admin UI in-game:

```text
/imagedetector
```

From the UI you can:

- Start a scan.
- Cancel a running scan.
- Search missing items by item name, label, or image name.
- Search unused images by image name or file name.
- Use `*` as a wildcard in search fields.
- Use the plus button on a missing item to receive that item for testing, when supported by the active inventory provider.

The command can also be executed from the server console. In that case the report is printed to the console instead of opening the UI.

## Permissions

Access to the UI and scan actions is checked server-side.

Default accepted ACE permissions:

```cfg
add_ace group.admin clx_imagedetector.admin allow
add_ace group.admin command.imagedetector allow
add_ace group.admin command.clx_imagedetector allow
```

You can also allow specific player identifiers through `Config.Ui.Admin.Identifiers`.

## Server Exports

Open the admin UI for a specific player from another trusted server-side script:

```lua
exports.clx_imagedetector:OpenAdminUi(source)
```

The export still validates access server-side.

## Configuration

Main settings are in `config.lua`.

Useful options:

- `Config.Enabled`: enables or disables the resource.
- `Config.Inventory`: inventory provider to use. Use `auto` for automatic detection.
- `Config.ScanDelay`: delay before scans, useful during server startup.
- `Config.StartupScan`: runs a console scan when the resource starts.
- `Config.CaseSensitive`: requires image names to match item names with exact casing.
- `Config.ReportUnusedImages`: includes unused image files in the report.
- `Config.Ui.Enabled`: enables or disables the in-game admin UI.
- `Config.Ui.Command.Name`: command used to open the UI.
- `Config.Ui.Admin.AcePermissions`: accepted ACE permissions.
- `Config.Ui.Admin.Identifiers`: optional identifier allowlist.
- `Config.ItemImages`: optional image name overrides per item.

Example item image override:

```lua
Config.ItemImages = {
    ['water'] = 'bottle_water',
}
```

## Notes

- The tool does not modify item definitions or image files.
- Image matching depends on the active inventory provider and its configured image path.
- If `Config.Inventory` is set to `auto` and multiple supported inventories are started, the script uses its provider priority order.
- The plus action checks whether the item is actually missing from the current report before trying to give it.
- Use this tool as a review helper before manually fixing inventory image files.

## Support

Need help, updates, or want to report an issue?

Join the Cylix Development Discord:

https://discord.gg/MrWM4RxEc2
