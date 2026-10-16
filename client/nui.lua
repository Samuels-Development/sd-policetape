---The bridge to web/build/ui.html: the HUD prompt (no focus), the style picker and the Tape
---Studio (both with focus). Also hears the atlas page say it is ready (atlas.html posts to this
---resource's NUI callbacks like any other page of ours).
local config = require 'configs.config'
local atlas = require 'client.tape.atlas'

local nui = {}

local ready = false
local queue = {}
local styles, canStudio = {}, false
local picker = nil ---@type { choose: fun(id: string|nil), hover: fun(id: string)|nil }|nil
local studioOpen = false
local lastHud = nil

local function send(msg)
    if ready then
        SendNUIMessage(msg)
    else
        queue[#queue + 1] = msg
    end
end

---The "ui" part of the configured locale (the page has English built in for anything missing).
local function uiWords()
    local res = GetCurrentResourceName()
    local raw = LoadResourceFile(res, ('locales/%s.json'):format(config.Locale))
        or LoadResourceFile(res, 'locales/en.json')
    local ok, data = pcall(json.decode, raw or '{}')
    return ok and type(data) == 'table' and data.ui or {}
end

RegisterNUICallback('uiReady', function(_, cb)
    cb(1)
    ready = true
    SendNUIMessage({ action = 'init', locale = uiWords(), styles = styles, canStudio = canStudio })
    for i = 1, #queue do SendNUIMessage(queue[i]) end
    queue = {}
end)

RegisterNUICallback('atlasReady', function(_, cb)
    cb(1)
    atlas.onReady()
end)

function nui.setStyles(list, studio)
    styles, canStudio = list, studio == true
    send({ action = 'styles', styles = list, canStudio = canStudio })
end

function nui.setCanStudio(studio)
    if canStudio == (studio == true) then return end
    canStudio = studio == true
    send({ action = 'styles', styles = styles, canStudio = canStudio })
end

---Shows (or with nil, hides) the prompt. Repeated identical states are not re-sent.
---@param hud table|nil
function nui.hud(hud)
    local key = hud and json.encode(hud) or nil
    if key == lastHud then return end
    lastHud = key
    send({ action = 'hud', hud = hud or false })
end

local lastProgress = -1
function nui.progress(value)
    value = math.floor(value * 50 + 0.5) / 50
    if value == lastProgress then return end
    lastProgress = value
    send({ action = 'progress', value = value })
end

-- Picker ----------------------------------------------------------------------------------------

---Opens the picker. `choose` is called with the chosen id, or nil when it is closed without one.
---@param selected string
---@param choose fun(id: string|nil)
---@param hover? fun(id: string)
function nui.openPicker(selected, choose, hover)
    -- The page draws nothing without styles, and focus with nothing on screen is a stuck cursor.
    if #styles == 0 then
        choose(nil)
        return
    end
    if picker then picker.choose(nil) end
    picker = { choose = choose, hover = hover }
    nui.hud(nil)
    SetNuiFocus(true, true)
    send({ action = 'picker', open = true, selected = selected })
end

local function closePicker(id)
    local p = picker
    picker = nil
    if not studioOpen then SetNuiFocus(false, false) end
    send({ action = 'picker', open = false })
    if p then p.choose(id) end
end
nui.closePicker = function() closePicker(nil) end

RegisterNUICallback('pickerChoose', function(data, cb)
    cb(1)
    closePicker(type(data) == 'table' and type(data.id) == 'string' and data.id or nil)
end)

RegisterNUICallback('pickerHover', function(data, cb)
    cb(1)
    if picker and picker.hover and type(data) == 'table' and type(data.id) == 'string' then picker.hover(data.id) end
end)

RegisterNUICallback('pickerClose', function(_, cb)
    cb(1)
    closePicker(nil)
end)

-- Studio ----------------------------------------------------------------------------------------

function nui.openStudio(startFrom)
    if #styles == 0 then return end
    if picker then closePicker(nil) end
    studioOpen = true
    nui.hud(nil)
    SetNuiFocus(true, true)
    send({ action = 'studio', open = true, startFrom = startFrom })
end

function nui.closeStudio()
    studioOpen = false
    SetNuiFocus(false, false)
    send({ action = 'studio', open = false })
end

RegisterNUICallback('studioOpen', function(data, cb)
    cb(1)
    TriggerEvent('sd-policetape:client:openStudio', type(data) == 'table' and data.from or nil)
end)

RegisterNUICallback('studioClose', function(_, cb)
    cb(1)
    studioOpen = false
    SetNuiFocus(false, false)
end)

RegisterNUICallback('studioSave', function(data, cb)
    cb(1)
    local res = lib.callback.await('sd-policetape:server:saveStyle', false, type(data) == 'table' and data.style or nil)
    res = type(res) == 'table' and res or { ok = false, error = 'no answer' }
    send({ action = 'studioResult', ok = res.ok == true, id = res.id, error = res.error })
end)

RegisterNUICallback('studioDelete', function(data, cb)
    cb(1)
    local res = lib.callback.await('sd-policetape:server:deleteStyle', false, type(data) == 'table' and data.id or nil)
    res = type(res) == 'table' and res or { ok = false, error = 'no answer' }
    send({ action = 'studioResult', ok = res.ok == true, error = res.error })
end)

---Whether the picker or the studio has the mouse.
function nui.busy()
    return picker ~= nil or studioOpen
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and nui.busy() then SetNuiFocus(false, false) end
end)

return nui
