---Client entry: gets the world from the server, keeps it in step, and owns the commands.
local config = require 'configs.config'
local log = require 'shared.log'
local locale = require 'bridge.shared.locale'
local notify = require 'bridge.client.notify'
local state = require 'client.state'
local atlas = require 'client.tape.atlas'
local world = require 'client.tape.world'
local nui = require 'client.nui'
local place = require 'client.place'
require 'client.look'

local function t(key, vars) return locale.t(key, vars) end

local function setStyles(list)
    state.setStyles(list)
    atlas.setStyles(list)
    nui.setStyles(list, state.perms.studio)
end

local function setPerms(perms)
    if type(perms) ~= 'table' then return end
    state.perms = { use = perms.use == true, studio = perms.studio == true, admin = perms.admin == true }
    nui.setCanStudio(state.perms.studio)
    if not state.perms.use and place.active then place.cancel() end
end

local function loadState()
    local s = lib.callback.await('sd-policetape:server:state', false)
    if type(s) ~= 'table' then
        log.warn('no state from the server')
        return
    end
    setPerms(s.perms)
    setStyles(s.styles or {})
    world.load(s.tapes or {})
    log.debug('main', '%d styles, %d tapes', #(s.styles or {}), #(s.tapes or {}))
end

CreateThread(function()
    atlas.create()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(250) end
    loadState()
end)

-- What the server says -------------------------------------------------------------------------

RegisterNetEvent('sd-policetape:client:add', function(tape) world.add(tape) end)

RegisterNetEvent('sd-policetape:client:remove', function(ids)
    if type(ids) ~= 'table' then ids = { ids } end
    for i = 1, #ids do world.remove(ids[i]) end
end)

RegisterNetEvent('sd-policetape:client:restyle', function(id, style) world.restyle(id, style) end)

RegisterNetEvent('sd-policetape:client:tear', function(id, frac) world.tear(id, frac) end)

-- A post or cone at a tie point went down (`fall` = { x, y, s }) or was stood back up.
RegisterNetEvent('sd-policetape:client:knock', function(x, y, z, fall) world.knock(x, y, z, fall) end)
RegisterNetEvent('sd-policetape:client:standup', function(x, y, z) world.standUp(x, y, z) end)

RegisterNetEvent('sd-policetape:client:styles', function(list) setStyles(list or {}) end)

RegisterNetEvent('sd-policetape:client:perms', setPerms)

RegisterNetEvent('sd-policetape:client:startPlacing', function(style) place.start(style) end)

-- Job changes change what a player may do. Every framework announces it its own way; asking the
-- server again is cheap.
local function refreshPerms()
    SetTimeout(500, function()
        setPerms(lib.callback.await('sd-policetape:server:perms', false))
    end)
end
for _, ev in ipairs({ 'QBCore:Client:OnJobUpdate', 'QBCore:Client:OnPlayerLoaded', 'qbx_core:client:playerLoggedIn', 'esx:setJob', 'esx:playerLoaded' }) do
    RegisterNetEvent(ev, refreshPerms)
end
CreateThread(function()
    while true do
        Wait(60000)
        setPerms(lib.callback.await('sd-policetape:server:perms', false))
    end
end)

-- Commands --------------------------------------------------------------------------------------

RegisterCommand(config.Commands.Place, function()
    if place.active then
        place.cancel()
        return
    end
    -- With the item required, the server checks it and starts placing (same as using the item).
    if config.Item.Enabled then
        TriggerServerEvent('sd-policetape:server:requestPlace')
    else
        place.start()
    end
end, false)

RegisterCommand(config.Commands.Styles, function()
    if nui.busy() then return end
    nui.openPicker(state.defaultStyle(), function(id)
        if id then
            state.setDefaultStyle(id)
            local s = state.style(id)
            notify.show({ title = t('notify.title'), description = s and s.label or id, type = 'inform' })
        end
    end)
end, false)

local function openStudio(from)
    if not lib.callback.await('sd-policetape:server:canStudio', false) then
        notify.show({ title = t('notify.title'), description = t('notify.no_permission'), type = 'error' })
        return
    end
    nui.openStudio(from or state.defaultStyle())
end

RegisterCommand(config.Commands.Studio, function() openStudio() end, false)
AddEventHandler('sd-policetape:client:openStudio', openStudio)

TriggerEvent('chat:addSuggestion', '/' .. config.Commands.Place, 'Place police tape')
TriggerEvent('chat:addSuggestion', '/' .. config.Commands.Styles, 'Choose the police tape style you place with')
TriggerEvent('chat:addSuggestion', '/' .. config.Commands.Studio, 'Make new police tape styles')

-- Diagnostics: `sdtape_dbg` prints what the client has; `sdtape_dbg winding ccw|cw|both` changes how tape is drawn, for this session only. Harmless to leave in: it
-- only ever changes what this one player sees.
RegisterCommand('sdtape_dbg', function(_, args)
    local render = require 'client.tape.render'
    if args[1] == 'winding' and (args[2] == 'ccw' or args[2] == 'cw' or args[2] == 'both') then
        render.winding = args[2]
    end
    local s = world.stats()
    print(('[sd-policetape] tapes %d, built %d, awake chains %d, push %.2f m, strain %.3f, resist %.2f, posts %d, colliders %d, preview %s | atlas %s ready %s | winding %s | styles %d | perms use=%s studio=%s admin=%s'):format(
        s.total, s.built, s.awakeChains, s.push, s.strain, s.resist, s.posts, s.colliders, tostring(s.preview), atlas.TXD, tostring(atlas.isReady()),
        render.winding, #state.styles,
        tostring(state.perms.use), tostring(state.perms.studio), tostring(state.perms.admin)))
end, false)

-- Exports ---------------------------------------------------------------------------------------

exports('StartPlacing', function(style) place.start(style) end)
exports('IsPlacing', function() return place.active end)
exports('GetLookedAtTape', function()
    local tape = require('client.look').tape
    return tape and tape.id or nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    world.clear()
    atlas.destroy()
end)
