PyImageDetector = PyImageDetector or {}

local Filesystem = {}

local isWindows = (os.getenv('OS') or ''):find('Windows') ~= nil

-- Quotes paths for simple shell directory commands.
local function quotePath(path)
    return ('"%s"'):format(tostring(path):gsub('"', '\\"'))
end

-- Runs a directory listing command and returns the raw filenames.
local function runListCommand(command)
    local handle = io.popen(command)
    if not handle then return nil, false end

    local files = {}
    for line in handle:lines() do
        if line and line ~= '' and line ~= '.' and line ~= '..' then
            files[#files + 1] = line
        end
    end

    local ok = handle:close()
    return files, ok == true
end

-- Lists files in a directory on Windows and Linux servers.
function Filesystem.listFiles(path)
    if type(path) ~= 'string' or path == '' then
        return {}, 'Invalid directory path.'
    end

    local quotedPath = quotePath(path)
    local commands

    if isWindows or path:match('^%a:[/\\]') then
        commands = {
            ('dir /b /a-d %s 2>nul'):format(quotedPath),
            ('find %s -maxdepth 1 -type f -printf "%%f\\n" 2>/dev/null'):format(quotedPath),
        }
    else
        commands = {
            ('find %s -maxdepth 1 -type f -printf "%%f\\n" 2>/dev/null'):format(quotedPath),
            ('dir /b /a-d %s 2>nul'):format(quotedPath),
        }
    end

    for i = 1, #commands do
        local files, ok = runListCommand(commands[i])
        if files and ok then
            return files
        end
    end

    return {}, ('Unable to list directory: %s'):format(path)
end

PyImageDetector.Filesystem = Filesystem
