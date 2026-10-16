---What admins change in the admin menu, kept in data/settings.json: the switches of
---shared/settings.lua, and which tape styles and holders players may put up. The config is the
---default; a switch is only kept while it differs from it, so editing the config still works.
local config = require 'configs.config'
local shared = require 'shared.settings'
local holder = require 'shared.holder'
local log = require 'shared.log'
local styles = require 'server.styles'

local RESOURCE = GetCurrentResourceName()
local FILE = 'data/settings.json'

local settings = {}

local defaults = {} ---@type table<string, any> what the config file says
local toggles = {} ---@type table<string, boolean> what an admin set, where it differs from the file
local offStyles = {} ---@type table<string, true> styles players cannot put up
local offHolders = {} ---@type table<string, true> holders players cannot put up

for _, t in ipairs(shared.toggles) do defaults[t.key] = shared.read(config, t.key) end

local function ids(set)
    local out = {}
    for id in pairs(set) do out[#out + 1] = id end
    table.sort(out)
    return out
end

local function save()
    SaveResourceFile(RESOURCE, FILE, json.encode({ toggles = toggles, styles = ids(offStyles), holders = ids(offHolders) }, { indent = true }), -1)
end

local function list(v)
    return type(v) == 'table' and v or {}
end

function settings.load()
    local raw = LoadResourceFile(RESOURCE, FILE)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            for key, value in pairs(list(data.toggles)) do
                if shared.known(key) and type(value) == 'boolean' and value ~= defaults[key] then toggles[key] = value end
            end
            for _, id in ipairs(list(data.styles)) do
                if type(id) == 'string' then offStyles[id] = true end
            end
            for _, id in ipairs(list(data.holders)) do
                if holder.get(id) then offHolders[id] = true end
            end
        else
            log.error('%s could not be read; the config is used as it is (the file was left as it is)', FILE)
        end
    end
    -- Never nothing to put up (configs/holders.lua may have changed under the file).
    if not settings.firstHolder() then offHolders = {} end
    shared.apply(config, toggles)
    local n = 0
    for _ in pairs(toggles) do n = n + 1 end
    if n > 0 or next(offStyles) or next(offHolders) then
        log.info('admin settings: %d switches changed, %d styles and %d holders turned off', n, #ids(offStyles), #ids(offHolders))
    end
end

---Sets a switch. Its new value is in the config at once.
---@return boolean
function settings.setToggle(key, value)
    if not shared.known(key) or type(value) ~= 'boolean' then return false end
    shared.write(config, key, value)
    if value == defaults[key] then toggles[key] = nil else toggles[key] = value end
    save()
    return true
end

function settings.styleAllowed(id)
    return type(id) == 'string' and not offStyles[id]
end

function settings.holderAllowed(id)
    return type(id) == 'string' and not offHolders[id]
end

---The first style players may put up, in the order of the style list.
function settings.firstStyle()
    for _, s in ipairs(styles.list() or {}) do
        if not offStyles[s.id] then return s.id end
    end
    return nil
end

---@return HolderDef|nil
function settings.firstHolder()
    for _, def in ipairs(holder.list) do
        if not offHolders[def.id] then return def end
    end
    return nil
end

---Turns `idList` on or off for players. Refuses to leave nothing at all to put up.
---@return boolean ok, string|nil error key
local function setSome(set, idList, on, exists, all, lastKey)
    local after = {}
    for id in pairs(set) do after[id] = true end
    for _, id in ipairs(list(idList)) do
        if type(id) == 'string' and exists(id) then after[id] = (not on) or nil end
    end
    local left = 0
    for _, id in ipairs(all()) do
        if not after[id] then left = left + 1 end
    end
    if left == 0 then return false, lastKey end
    for id in pairs(set) do set[id] = nil end
    for id in pairs(after) do set[id] = true end
    save()
    return true
end

function settings.setStyles(idList, on)
    return setSome(offStyles, idList, on, function(id) return styles.get(id) ~= nil end, function()
        local out = {}
        for _, s in ipairs(styles.list() or {}) do out[#out + 1] = s.id end
        return out
    end, 'admin_last_style')
end

function settings.setHolders(idList, on)
    return setSome(offHolders, idList, on, function(id) return holder.get(id) ~= nil end, function()
        local out = {}
        for _, def in ipairs(holder.list) do out[#out + 1] = def.id end
        return out
    end, 'admin_last_holder')
end

---What every client is told: the switches as they are, and what players cannot put up.
function settings.public()
    local values = {}
    for _, t in ipairs(shared.toggles) do values[t.key] = shared.read(config, t.key) == true end
    return { toggles = values, offStyles = ids(offStyles), offHolders = ids(offHolders) }
end

---The switches for the admin menu: each with its group, value and what the config file says.
function settings.admin()
    local out = {}
    for _, t in ipairs(shared.toggles) do
        out[#out + 1] = { key = t.key, group = t.group, on = shared.read(config, t.key) == true, default = defaults[t.key] == true }
    end
    return out
end

return settings
