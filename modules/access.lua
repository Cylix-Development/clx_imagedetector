PyImageDetector = PyImageDetector or {}

local Access = {}

-- Checks whether an identifier is explicitly allowed in config.
local function hasAllowedIdentifier(source, identifiers)
    if type(identifiers) ~= 'table' or #identifiers == 0 then return false end

    local allowed = {}
    for i = 1, #identifiers do
        allowed[identifiers[i]] = true
    end

    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local identifier = GetPlayerIdentifier(source, i)
        if identifier and allowed[identifier] then
            return true
        end
    end

    return false
end

-- Checks configured ACE permissions and identifier allowlists.
function Access.isAllowed(source, config)
    source = tonumber(source)
    if not source or source <= 0 then return false end

    local uiConfig = type(config.Ui) == 'table' and config.Ui or {}
    local adminConfig = type(uiConfig.Admin) == 'table' and uiConfig.Admin or {}

    local acePermissions = adminConfig.AcePermissions
    if type(acePermissions) == 'table' then
        for i = 1, #acePermissions do
            local permission = acePermissions[i]
            if type(permission) == 'string' and permission ~= '' and IsPlayerAceAllowed(source, permission) then
                return true
            end
        end
    end

    return hasAllowedIdentifier(source, adminConfig.Identifiers)
end

PyImageDetector.Access = Access
