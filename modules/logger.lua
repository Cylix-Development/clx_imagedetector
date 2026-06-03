PyImageDetector = PyImageDetector or {}

local Logger = {}

local prefix = '^3[ImageDetector]^7'

-- Prints an informational line with the resource prefix.
function Logger.info(message)
    print(('%s %s'):format(prefix, message))
end

-- Prints a warning line with the resource prefix.
function Logger.warn(message)
    print(('%s ^3[WARN]^7 %s'):format(prefix, message))
end

-- Prints an error line with the resource prefix.
function Logger.error(message)
    print(('%s ^1[ERROR]^7 %s'):format(prefix, message))
end

-- Prints a positive result line without repeating the resource prefix.
function Logger.ok(message)
    print(('^2[OK]^7 %s'):format(message))
end

PyImageDetector.Logger = Logger
