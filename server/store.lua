---Every tape on the server, kept in memory and (with Config.Persist) in data/tapes.json: the ones
---marked to survive a restart. Config.Persist can be switched in the admin menu while the server
---runs; off, the file is emptied, so nothing comes back after the next restart.
local config = require 'configs.config'
local log = require 'shared.log'

local RESOURCE = GetCurrentResourceName()
local FILE = 'data/tapes.json'

local store = {}

---@class TapeRecord
---@field id integer
---@field style string
---@field a { x: number, y: number, z: number }
---@field b { x: number, y: number, z: number }
---@field ap boolean a holder (post or cone) stands under a
---@field bp boolean
---@field ah string|nil which holder (configs/holders.lua id)
---@field bh string|nil
---@field af table|nil that holder is knocked over: { x, y, s } the way it went and how far it slid
---@field bf table|nil
---@field torn number|false
---@field tornAt integer|nil
---@field persist boolean survives a restart of the server (written to data/tapes.json)
---@field owner string|nil identifier of whoever placed it
---@field ownerName string|nil
---@field created integer os.time()

---@type table<integer, TapeRecord>
local tapes = {}
local nextId = 1
local dirty = false

local function round(v) return math.floor(v * 1000 + 0.5) / 1000 end

function store.load()
    tapes, nextId = {}, 1
    if not config.Persist then return end
    local raw = LoadResourceFile(RESOURCE, FILE)
    if not raw or raw == '' then return end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then
        log.error('%s could not be read; starting with no tape (the file was left as it is)', FILE)
        return
    end
    local n = 0
    for _, t in ipairs(data) do
        if type(t) == 'table' and tonumber(t.id) and type(t.a) == 'table' and type(t.b) == 'table' then
            t.id = math.floor(tonumber(t.id))
            t.torn = type(t.torn) == 'number' and t.torn or false
            t.persist = true -- (only what is to survive is ever written)
            -- Saved before there were cones: what stood there was the post.
            if t.ap and not t.ah then t.ah = 'post' end
            if t.bp and not t.bh then t.bh = 'post' end
            tapes[t.id] = t
            if t.id >= nextId then nextId = t.id + 1 end
            n = n + 1
        end
    end
    log.info('%d tapes restored', n)
end

local function flush()
    if not dirty then return end
    dirty = false
    local list = {}
    if config.Persist then
        for _, t in pairs(tapes) do
            if t.persist ~= false then list[#list + 1] = t end
        end
    end
    table.sort(list, function(x, y) return x.id < y.id end)
    SaveResourceFile(RESOURCE, FILE, json.encode(list), -1)
end

---Writes to disk soon (several changes in a row are written once).
local function touch()
    if dirty then return end
    dirty = true
    SetTimeout(2000, flush)
end
store.touch = touch

---@param t TapeRecord without id
---@return TapeRecord
function store.add(t)
    t.id = nextId
    nextId = nextId + 1
    t.a = { x = round(t.a.x), y = round(t.a.y), z = round(t.a.z) }
    t.b = { x = round(t.b.x), y = round(t.b.y), z = round(t.b.z) }
    t.torn = t.torn or false
    t.persist = t.persist ~= false
    t.created = t.created or os.time()
    tapes[t.id] = t
    touch()
    return t
end

function store.get(id)
    return tapes[tonumber(id) or -1]
end

function store.remove(id)
    local t = tapes[id]
    tapes[id] = nil
    if t then touch() end
    return t
end

function store.all()
    return tapes
end

function store.count()
    local n = 0
    for _ in pairs(tapes) do n = n + 1 end
    return n
end

function store.countBy(owner)
    local n = 0
    for _, t in pairs(tapes) do
        if t.owner == owner then n = n + 1 end
    end
    return n
end

---What clients get: no identifiers.
---@param t TapeRecord
function store.public(t)
    return {
        id = t.id, style = t.style, a = t.a, b = t.b, ap = t.ap, bp = t.bp,
        ah = t.ah, bh = t.bh, af = t.af, bf = t.bf, torn = t.torn, persist = t.persist,
    }
end

function store.publicList()
    local list = {}
    for _, t in pairs(tapes) do list[#list + 1] = store.public(t) end
    return list
end

AddEventHandler('onResourceStop', function(res)
    if res == RESOURCE then flush() end
end)

return store
