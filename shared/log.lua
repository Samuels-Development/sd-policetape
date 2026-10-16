---Console output for sd-policetape. `debug` only prints with Config.Debug on.
local config = require 'configs.config'

local log = {}

local side = IsDuplicityVersion() and 'server' or 'client'

function log.debug(tag, fmt, ...)
    if not config.Debug then return end
    local ok, msg = pcall(string.format, fmt, ...)
    print(('^5[sd-policetape:%s:%s]^0 %s'):format(side, tag, ok and msg or tostring(fmt)))
end

function log.info(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print(('^2[sd-policetape]^0 %s'):format(ok and msg or tostring(fmt)))
end

function log.warn(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print(('^3[sd-policetape]^0 %s'):format(ok and msg or tostring(fmt)))
end

function log.error(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print(('^1[sd-policetape]^0 %s'):format(ok and msg or tostring(fmt)))
end

return log
