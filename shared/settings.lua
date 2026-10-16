---The switches in the admin menu: Config values an admin can change while the server runs. Each is
---`Section.Field` of configs/config.lua, or a top-level `Field`. What an admin sets is kept in data/settings.json and wins
---over the file (server/settings.lua); both sides write it into their own copy of the config, so
---everything that reads the config sees it at once.
local settings = {}

---@type { key: string, group: string }[] in the order the admin menu shows them
settings.toggles = {
    { key = 'Tear.Enabled', group = 'tape' },
    { key = 'Tear.People', group = 'tape' },
    { key = 'Physics.Enabled', group = 'tape' },
    { key = 'Wind.Enabled', group = 'tape' },
    { key = 'Holders.Knock', group = 'holders' },
    { key = 'Holders.Vehicles', group = 'holders' },
    { key = 'Holders.Kick', group = 'holders' },
    { key = 'Holders.Run', group = 'holders' },
    { key = 'Holders.StandUp', group = 'holders' },
    { key = 'Placement.Posts', group = 'placing' },
    { key = 'Placement.Chain', group = 'placing' },
    { key = 'Access.OthersTapes', group = 'placing' },
    { key = 'Item.Enabled', group = 'item' },
    { key = 'Item.Consume', group = 'item' },
    { key = 'Item.Refund', group = 'item' },
    { key = 'Persist', group = 'saving' },
    { key = 'PersistChoice', group = 'saving' },
}

local known = {}
for _, t in ipairs(settings.toggles) do known[t.key] = true end

function settings.known(key)
    return known[key] == true
end

---`Section.Field` as section, field; a top-level `Field` as nil, field.
local function split(key)
    key = tostring(key)
    local section, field = key:match('^(%w+)%.(%w+)$')
    if section then return section, field end
    return nil, key:match('^(%w+)$')
end

---The value of `key` in `config`.
function settings.read(config, key)
    local section, field = split(key)
    if not field then return nil end
    if not section then return config[field] end
    local t = config[section]
    if type(t) ~= 'table' then return nil end
    return t[field]
end

function settings.write(config, key, value)
    local section, field = split(key)
    if not field then return end
    if not section then
        config[field] = value
        return
    end
    config[section] = config[section] or {}
    config[section][field] = value
end

---Writes every known switch in `values` ({ [key] = boolean }) into `config`.
function settings.apply(config, values)
    if type(values) ~= 'table' then return end
    for key, value in pairs(values) do
        if known[key] and type(value) == 'boolean' then settings.write(config, key, value) end
    end
end

return settings
