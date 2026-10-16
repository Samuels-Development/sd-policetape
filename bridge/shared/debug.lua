---@type table Global resource config table (configs.config). Read live on every
---call so the DebugPrints master switch / DebugCategories filter reflect whatever
---the server owner configured (and any admin-merged overrides) without caching.
local config = require 'configs.config'

---@type table Debug-logging module. Exposes a per-file tagged-logger factory plus
---a runtime predicate so hot per-tick paths can skip argument work when off.
local debug = {}

---@type string Console colour code for the tag (Cfx ^5 = cyan), distinct from
---the ^2 green used by the normal startup banner so debug lines stand out.
local TAG_COLOR = '^5'
---@type string Colour reset back to the default console colour.
local RESET = '^0'

---Decides whether `category` should print right now. Honours the master switch
---first, then the optional per-category override table. Rules:
---  * DebugPrints ~= true                      → never (master kill switch)
---  * DebugPrints == true, no/empty overrides  → every category prints
---  * overrides contain at least one `true`    → allowlist: only the `true` ones
---  * overrides contain only `false` values    → denylist: listed ones are off
---@param category string
---@return boolean
function debug.enabled(category)
    if config.DebugPrints ~= true then return false end

    local cats = config.DebugCategories
    if type(cats) ~= 'table' then return true end

    local explicit = cats[category]
    if explicit ~= nil then return explicit == true end

    -- Category not listed: if the table names any category to KEEP (`true`),
    -- treat it as an allowlist and suppress everything else; otherwise it is a
    -- pure denylist of `false`s, so unlisted categories stay on.
    for _, v in pairs(cats) do
        if v == true then return false end
    end
    return true
end

---Builds a logger bound to `category`. Call the returned value printf-style;
---it prints a tagged line only when the category is enabled. Formatting is
---wrapped so a malformed format string degrades to a safe line instead of
---raising — debug output must never crash gameplay. The returned object also
---carries an `.on()` predicate for guarding expensive per-tick logging:
---`if dprint.on() then dprint('speed %.1f', GetEntitySpeed(veh)) end`.
---@param category string Subsystem tag, e.g. 'shop', 'mailbox', 'bridge:fuel'.
---@return table dprint Callable logger; also has `.on()` → boolean.
function debug.tag(category)
    local prefix = ('%s[sd-policetape:%s]%s '):format(TAG_COLOR, category, RESET)

    local logger = setmetatable({}, {
        __call = function(_, fmt, ...)
            if not debug.enabled(category) then return end
            local msg
            if select('#', ...) > 0 then
                local ok, formatted = pcall(string.format, fmt, ...)
                msg = ok and formatted or (tostring(fmt) .. ' ^1[debugPrint: bad format]' .. RESET)
            else
                msg = tostring(fmt)
            end
            print(prefix .. msg)
        end,
    })

    ---Whether this logger's category is currently enabled. Guard per-tick calls
    ---with this so their format arguments aren't computed while debug is off.
    ---@return boolean
    function logger.on() return debug.enabled(category) end

    return logger
end

return debug
