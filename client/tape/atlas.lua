---The texture every tape is drawn from: one browser page (web/build/atlas.html) in a DUI, read
---by the game as a runtime texture.
---
---The page holds 40 styles at a time, each with four sizes of its print (a mip chain made by
---hand, because a DUI texture has none). Styles are painted into slots when a tape needs them and
---the least recently drawn one gives up its slot when a new style needs one, so a server can have
---any number of styles; 40 different ones in sight at once is the only limit.
---
---The layout numbers here and in web/src/paint/layout.ts must match.
local log = require 'shared.log'

local atlas = {}

-- A runtime dictionary cannot be made again under a name already used this game session, even
-- once its page is gone (found in sd-wraps). So a new name every time the resource starts, or a
-- restart would leave every tape drawing from nothing.
local TXD = ('sdtape_%d'):format(GetGameTimer())
local TXN = 'atlas'
local SIZE = 2048
local SLOT_W, SLOT_H, PER_ROW = 1024, 100, 2
local SLOTS = PER_ROW * (SIZE // SLOT_H)

---x, y, w, h of each level inside a slot (layout.ts LODS).
local LODS = {
    { 0, 0, 1024, 64 },
    { 0, 66, 512, 32 },
    { 514, 66, 256, 16 },
    { 772, 66, 128, 8 },
}
atlas.LEVELS = #LODS

local RESOURCE = GetCurrentResourceName()

local dui, ready, created = nil, false, false
local serial = 0

---@type table<string, integer> style id -> slot (0-based)
local slotOf = {}
---@type table<integer, { id: string, used: number, style: table }>
local slots = {}

---@type table<string, table> every style by id, set by the client from the server's list
local styles = {}

---@type table<integer, table<integer, number[]>> slot -> level -> { u0, v0, u1, v1 }
local uvCache = {}

local function uvFor(slot)
    local cached = uvCache[slot]
    if cached then return cached end
    local sx = (slot % PER_ROW) * SLOT_W
    local sy = (slot // PER_ROW) * SLOT_H
    local out = {}
    for l = 1, #LODS do
        local r = LODS[l]
        -- Half a texel in from every edge: linear filtering then never reads a neighbour or the
        -- transparent gutter, and the repeat meets itself exactly at the seam.
        out[l] = {
            (sx + r[1] + 0.5) / SIZE, (sy + r[2] + 0.5) / SIZE,
            (sx + r[1] + r[3] - 0.5) / SIZE, (sy + r[2] + r[4] - 0.5) / SIZE,
        }
    end
    uvCache[slot] = out
    return out
end

local function send(msg)
    if dui then SendDuiMessage(dui, json.encode(msg)) end
end

local function paintSlot(slot)
    local s = slots[slot]
    if not s then return end
    serial = serial + 1
    send({ action = 'paint', slot = slot, serial = serial, style = s.style })
end

local function repaintAll()
    for slot in pairs(slots) do paintSlot(slot) end
end

---Opens the page. Safe to call more than once.
function atlas.create()
    if created then return end
    created = true

    local txd = CreateRuntimeTxd(TXD)
    dui = CreateDui(('nui://%s/web/build/atlas.html'):format(RESOURCE), SIZE, SIZE)
    CreateRuntimeTextureFromDuiHandle(txd, TXN, GetDuiHandle(dui))

    -- Nothing says when a DUI page has loaded and can hear messages. The page says so itself
    -- (atlasReady, client/nui.lua), but whether a DUI page's request ever reaches the resource is
    -- not something to bet on, so everything is also sent again on a timer for a while.
    CreateThread(function()
        for _, wait in ipairs({ 600, 1200, 2500, 5000, 10000 }) do
            Wait(wait)
            if not dui then return end
            repaintAll()
        end
        ready = true
    end)
end

---The page said it is listening.
function atlas.onReady()
    ready = true
    repaintAll()
end

---Replaces the style list. Slots whose style changed are repainted; slots of styles that no
---longer exist are freed.
---@param list table[]
function atlas.setStyles(list)
    local new = {}
    for i = 1, #list do new[list[i].id] = list[i] end

    for slot, s in pairs(slots) do
        local style = new[s.id]
        if not style then
            slots[slot] = nil
            slotOf[s.id] = nil
            send({ action = 'clear', slot = slot, serial = serial + 1 })
            serial = serial + 1
        elseif json.encode(style) ~= json.encode(s.style) then
            s.style = style
            paintSlot(slot)
        end
    end

    styles = new
end

---@param id string
---@return table|nil
function atlas.style(id)
    return styles[id]
end

---The slot a style is painted in, painting it into one first if needed. Call once per frame for
---every style about to be drawn: it also marks the style as recently used.
---@param id string
---@return integer|nil slot, table|nil uv per level
function atlas.acquire(id)
    local now = GetGameTimer()
    local slot = slotOf[id]
    if slot then
        slots[slot].used = now
        return slot, uvFor(slot)
    end

    local style = styles[id]
    if not style then return nil end

    -- A free slot, or the one drawn longest ago.
    local pick, oldest = nil, math.huge
    for i = 0, SLOTS - 1 do
        local s = slots[i]
        if not s then pick = i break end
        if s.used < oldest then pick, oldest = i, s.used end
    end

    local prev = slots[pick]
    if prev then
        slotOf[prev.id] = nil
        log.debug('atlas', 'slot %d: %s -> %s', pick, prev.id, id)
    end

    slots[pick] = { id = id, used = now, style = style }
    slotOf[id] = pick
    paintSlot(pick)
    return pick, uvFor(pick)
end

atlas.TXD = TXD
atlas.TXN = TXN

---Closes the page. Call only once nothing draws from it any more.
function atlas.destroy()
    if dui then
        DestroyDui(dui)
        dui = nil
    end
end

---Whether the page has been heard from (or given up waiting for).
function atlas.isReady()
    return ready
end

return atlas
