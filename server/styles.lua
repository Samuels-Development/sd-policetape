---The styles every client paints: the built-ins (configs/styles.lua) and the ones made in the
---Tape Studio (data/styles.json). Everything passes through shared/schema.lua first.
local config = require 'configs.config'
local schema = require 'shared.schema'
local log = require 'shared.log'

local RESOURCE = GetCurrentResourceName()
local FILE = 'data/styles.json'

local styles = {}

local builtins = {} ---@type table[]
local custom = {} ---@type table[]
local byId = {} ---@type table<string, table>
local listCache = nil

local function rebuild()
    byId = {}
    local list = {}
    for _, s in ipairs(builtins) do
        list[#list + 1] = s
        byId[s.id] = s
    end
    for _, s in ipairs(custom) do
        list[#list + 1] = s
        byId[s.id] = s
    end
    listCache = list
end

local function loadBuiltins()
    builtins = {}
    local seen = {}
    for i, raw in ipairs(require 'configs.styles') do
        local s, why = schema.normalise(raw)
        if not s then
            log.warn('configs/styles.lua entry %d skipped: %s', i, why)
        elseif seen[s.id] then
            log.warn('configs/styles.lua: duplicate id "%s" skipped', s.id)
        else
            s.custom = false
            seen[s.id] = true
            builtins[#builtins + 1] = s
        end
    end
end

local function loadCustom()
    custom = {}
    local raw = LoadResourceFile(RESOURCE, FILE)
    if not raw or raw == '' then return end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        log.error('%s could not be read; custom styles not loaded (the file was left as it is)', FILE)
        return
    end
    for _, raw in ipairs(data) do
        local s = schema.normalise(raw)
        if s then
            s.custom = true
            -- (who made it is not part of the style, so normalise leaves it out: keep it)
            s.author = type(raw.author) == 'string' and raw.author or nil
            s.authorKey = type(raw.authorKey) == 'string' and raw.authorKey or nil
            custom[#custom + 1] = s
        end
    end
end

local function saveCustom()
    SaveResourceFile(RESOURCE, FILE, json.encode(custom, { indent = true }), -1)
end

function styles.load()
    loadBuiltins()
    loadCustom()
    rebuild()
    log.info('%d tape styles (%d built in, %d from the Tape Studio)', #listCache, #builtins, #custom)
end

function styles.list()
    return listCache
end

function styles.get(id)
    return byId[id]
end

---Who `identifier` is, as a short hash: enough to tell a player's own styles apart, nothing to
---look them up by.
function styles.authorKey(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return nil end
    local h = GetHashKey('sd-policetape:' .. identifier)
    if h < 0 then h = h + 4294967296 end
    return ('%08x'):format(h)
end

---The style a tape falls back to when its own is gone.
function styles.fallback()
    return listCache[1] and listCache[1].id or 'police_line'
end

local function broadcast()
    TriggerClientEvent('sd-policetape:client:styles', -1, listCache)
end

local function newId()
    local chars = 'abcdefghijkmnpqrstuvwxyz23456789'
    for _ = 1, 50 do
        local id = 'c_'
        for _ = 1, 6 do
            local i = math.random(1, #chars)
            id = id .. chars:sub(i, i)
        end
        if not byId[id] then return id end
    end
    return ('c_%d'):format(os.time())
end

---Saves a studio style. A style with no id, or the id of a built-in, is saved as a new one.
---`author` is the maker's name, `authorKey` a hash of who they are (styles.authorKey), so a
---player's own styles can be told apart without sending anyone's identifier to everyone.
---@return table|nil style, string|nil error key, table|nil error vars
function styles.save(raw, author, authorKey)
    if type(raw) ~= 'table' then return nil, 'studio_invalid', { reason = 'empty' } end

    local existing = type(raw.id) == 'string' and byId[raw.id] or nil
    local editing = existing and existing.custom
    if not editing and #custom >= config.Limits.CustomStyles then
        return nil, 'studio_full', { max = config.Limits.CustomStyles }
    end

    local copy = {}
    for k, v in pairs(raw) do copy[k] = v end
    copy.id = editing and existing.id or newId()

    local s, why = schema.normalise(copy)
    if not s then return nil, 'studio_invalid', { reason = why } end
    s.custom = true
    -- Editing keeps who first made it; a new one is the saver's. A style from before there were
    -- keys gets its maker's key the first time they edit it themselves.
    author = type(author) == 'string' and author or nil
    authorKey = type(authorKey) == 'string' and authorKey or nil
    if editing then
        s.author = existing.author or author
        s.authorKey = existing.authorKey or (existing.author == author and authorKey or nil)
    else
        s.author, s.authorKey = author, authorKey
    end

    if editing then
        for i, c in ipairs(custom) do
            if c.id == s.id then custom[i] = s end
        end
    else
        custom[#custom + 1] = s
    end

    rebuild()
    saveCustom()
    broadcast()
    return s
end

---Deletes a studio style. Built-ins cannot be deleted here (edit configs/styles.lua instead).
---@return table|nil the deleted style
function styles.delete(id)
    for i, c in ipairs(custom) do
        if c.id == id then
            table.remove(custom, i)
            rebuild()
            saveCustom()
            broadcast()
            return c
        end
    end
    return nil
end

return styles
