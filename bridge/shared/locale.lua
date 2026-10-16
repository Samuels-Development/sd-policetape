---@type table Locale bridge exposing the translation lookup and dictionary loader.
local locale = {}

---@type table|nil Loaded resource config (configs.config), or nil if it failed to require.
local config = (function()
    local ok, c = pcall(require, 'configs.config')
    return ok and c or nil
end)()

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:locale')

---@type table<string, any> Flattened dot-path translation dictionary for the loaded language.
local dict = {}

---Recursively flattens a nested JSON-decoded table into dot-notation keys
---written into `target` (e.g. `{ menu = { buy = 'Buy' } }` →
---`target['menu.buy'] = 'Buy'`).
---@param prefix string|nil
---@param source table
---@param target table<string, any>
local function flatten(prefix, source, target)
    for key, value in pairs(source) do
        local newKey = prefix and (prefix .. '.' .. key) or key
        if type(value) == 'table' then
            flatten(newKey, value, target)
        else
            target[newKey] = value
        end
    end
end

---Localised lookup. Falls back to `key` when not present so missing
---translations are visible in the UI rather than rendering empty strings.
---@param key string
---@param replacements? table<string, any>
---@return string
function locale.t(key, replacements)
    local lstr = dict[key]
    if not lstr then
        dprint('t: missing key=%s — returning key as fallback', tostring(key))
    end
    if lstr and replacements then
        for k, v in pairs(replacements) do
            local safe = tostring(v):gsub('%%', '%%%%')
            lstr = lstr:gsub('{' .. tostring(k) .. '}', safe)
        end
    end
    return lstr or key
end

---Loads `locales/<lang>.json` into the dictionary. Falls back to English if
---the requested language file is missing; passes through silently if even
---English is absent (locale support is optional).
---@param lang string
function locale.load(lang)
    lang = lang or 'en'
    dprint('load: requested lang=%s', lang)
    local path = ('locales/%s.json'):format(lang)
    local file = LoadResourceFile(GetCurrentResourceName(), path)

    if not file and lang ~= 'en' then
        dprint('load: file not found for lang=%s — falling back to en', lang)
        print('^3[SD-POLICETAPE] Falling back to English locale^0')
        path = 'locales/en.json'
        file = LoadResourceFile(GetCurrentResourceName(), path)
    end
    if not file then
        dprint('load: no locale file found for lang=%s (and no English fallback) — skipping', lang)
        return
    end

    local decoded = json.decode(file)
    if not decoded then
        dprint('load: json.decode failed for path=%s', path)
        print('^1[SD-POLICETAPE] Failed to parse the locale JSON.^0')
        return
    end

    for k in pairs(dict) do dict[k] = nil end
    flatten(nil, decoded, dict)

    local count = 0
    for _ in pairs(dict) do count = count + 1 end
    dprint('load: dictionary populated with %d entries for lang=%s', count, lang)
    print(('^2[SD-POLICETAPE] Loaded locale: %s^0'):format(lang))
end

---Boot thread — waits 100 ms for `configs.config` to finish loading, then
---triggers the locale loader with the configured language (defaulting to
---English when no override is set).
CreateThread(function()
    Wait(100)
    local lang = config and config.Locale or 'en'
    dprint('boot thread: config resolved lang=%s (config loaded=%s)', lang, tostring(config ~= nil))
    locale.load(lang)
end)

return locale
