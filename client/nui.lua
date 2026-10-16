---The bridge to web/build/ui.html: the HUD prompt (no focus); the style picker, the holder menu,
---the Tape Studio and the admin menu (all with focus). Also hears the atlas page say it is ready
---(atlas.html posts to this resource's NUI callbacks like any other page of ours).
local config = require 'configs.config'
local atlas = require 'client.tape.atlas'

local nui = {}

local ready = false
local queue = {}
local styles, canStudio, offStyles = {}, false, {}
local me = nil ---@type { key: string|nil, name: string|nil }|nil who this player is to the picker's "Yours"
local picker = nil ---@type { choose: fun(id: string|nil), hover: fun(id: string)|nil }|nil
local holders = nil ---@type { choose: fun(id: string|nil), hover: fun(id: string)|nil }|nil
local studioOpen = false
local adminOpen = false
local lastHud = nil

local function send(msg)
    if ready then
        SendNUIMessage(msg)
    else
        queue[#queue + 1] = msg
    end
end
nui.send = send

---Lets go of the mouse once nothing that needs it is open any more.
local function releaseFocus()
    if not picker and not holders and not studioOpen and not adminOpen then SetNuiFocus(false, false) end
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
    SendNUIMessage({ action = 'init', locale = uiWords(), styles = styles, canStudio = canStudio, off = offStyles, me = me })
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

---Who this player is, so the picker can show the styles they made.
function nui.setMe(who)
    me = type(who) == 'table' and who or nil
    send({ action = 'me', me = me })
end

---The styles players cannot put up (the picker leaves them out).
function nui.setOff(list)
    offStyles = list or {}
    send({ action = 'off', styles = offStyles })
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
    releaseFocus()
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

-- Holder menu: the post or cone a new end stands on, with a picture of each ---------------------

---Opens the holder menu over `list` ({ id, label, image, height }[]). `choose` gets the chosen id,
---or nil when it is closed without one; `hover` the one under the pointer, as it moves.
function nui.openHolders(list, selected, choose, hover)
    if #list == 0 then
        choose(nil)
        return
    end
    if holders then holders.choose(nil) end
    holders = { choose = choose, hover = hover }
    nui.hud(nil)
    SetNuiFocus(true, true)
    send({ action = 'holders', open = true, list = list, selected = selected })
end

local function closeHolders(id)
    local h = holders
    holders = nil
    releaseFocus()
    send({ action = 'holders', open = false })
    if h then h.choose(id) end
end

RegisterNUICallback('holdersChoose', function(data, cb)
    cb(1)
    closeHolders(type(data) == 'table' and type(data.id) == 'string' and data.id or nil)
end)

RegisterNUICallback('holdersHover', function(data, cb)
    cb(1)
    if holders and holders.hover and type(data) == 'table' and type(data.id) == 'string' then holders.hover(data.id) end
end)

RegisterNUICallback('holdersClose', function(_, cb)
    cb(1)
    closeHolders(nil)
end)

---Closes the picker or the holder menu, whichever is open, as if closed without a choice.
function nui.closeMenus()
    if picker then closePicker(nil) end
    if holders then closeHolders(nil) end
end

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
    releaseFocus()
    send({ action = 'studio', open = false })
end

RegisterNUICallback('studioOpen', function(data, cb)
    cb(1)
    TriggerEvent('sd-policetape:client:openStudio', type(data) == 'table' and data.from or nil)
end)

RegisterNUICallback('studioClose', function(_, cb)
    cb(1)
    studioOpen = false
    releaseFocus()
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

-- Admin menu (its callbacks are in client/admin.lua) ---------------------------------------------

function nui.openAdmin(snapshot)
    nui.closeMenus()
    adminOpen = true
    nui.hud(nil)
    SetNuiFocus(true, true)
    send({ action = 'admin', open = true, snapshot = snapshot })
end

function nui.adminSnapshot(snapshot)
    if adminOpen then send({ action = 'adminSnapshot', snapshot = snapshot }) end
end

function nui.closeAdmin()
    adminOpen = false
    releaseFocus()
    send({ action = 'admin', open = false })
end

function nui.adminIsOpen()
    return adminOpen
end

---Whether the picker, the holder menu, the studio or the admin menu has the mouse.
function nui.busy()
    return picker ~= nil or holders ~= nil or studioOpen or adminOpen
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and nui.busy() then SetNuiFocus(false, false) end
end)

return nui
