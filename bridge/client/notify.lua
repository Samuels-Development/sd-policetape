---@type table Framework descriptor (bridge.shared.framework) exposing name and core handle.
local framework = require 'bridge.shared.framework'

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:notify')

---@type boolean Whether the ox_lib notification backend is preferred when available.
local USE_OX_LIB = true

---@type boolean Whether the lation_ui notification backend is used as an opt-in fallback.
local USE_LATION_UI = false

---@type table Client notify bridge exposing the notification API.
local notify = {}

---Picks the notify backend at module load — frameworks/UIs don't change at
---runtime, so we only branch once and store the chosen function.
---@return fun(data: { title?: string, description: string, type?: string, position?: string, duration?: number })
local function chooseBackend()
    dprint('chooseBackend: lib=%s USE_OX_LIB=%s USE_LATION_UI=%s framework=%s',
        tostring(lib ~= nil), tostring(USE_OX_LIB), tostring(USE_LATION_UI), tostring(framework.name))

    if lib ~= nil and USE_OX_LIB then
        dprint('selected backend: ox_lib (lib.notify)')
        return function(data)
            dprint('notify via ox_lib: title=%s desc=%s type=%s',
                tostring(data.title), tostring(data.description), tostring(data.type))
            lib.notify({
                id = math.random(1, 999999),
                title = data.title,
                description = data.description,
                type = data.type or 'inform',
                position = data.position or 'top-right',
                duration = data.duration or 3000,
            })
        end
    end

    if USE_LATION_UI then
        dprint('selected backend: lation_ui')
        return function(data)
            dprint('notify via lation_ui: title=%s desc=%s type=%s',
                tostring(data.title), tostring(data.description), tostring(data.type))
            exports.lation_ui:notify({
                title = data.title,
                message = data.description,
                type = data.type or 'info',
            })
        end
    end

    if framework.name == 'esx' then
        dprint('selected backend: esx (ShowNotification)')
        return function(data)
            dprint('notify via esx: desc=%s', tostring(data.description))
            framework.core.ShowNotification(data.description)
        end
    elseif framework.name == 'qbx' then
        dprint('selected backend: qbx (exports.qbx_core:Notify)')
        return function(data)
            dprint('notify via qbx: desc=%s type=%s', tostring(data.description), tostring(data.type))
            exports.qbx_core:Notify(data.description, data.type or 'info')
        end
    elseif framework.qb then
        dprint('selected backend: qb (Functions.Notify)')
        return function(data)
            dprint('notify via qb: desc=%s type=%s', tostring(data.description), tostring(data.type))
            framework.core.Functions.Notify(data.description, data.type or 'info')
        end
    end

    dprint('^1no supported notification backend found — will error on use^7')
    return function(data)
        error(('Notification system not supported. message=%s type=%s'):format(
            data.description, data.type))
    end
end

---@type fun(data: table) Active notification backend chosen at module load.
local backend = chooseBackend()

---Show a notification. Accepts a fully-typed payload table or a (text, type)
---pair — both are common in the wild and we don't want to force callers to
---rebuild a table for the common case.
---@param data string|table
---@param notifyType? string
function notify.show(data, notifyType)
    if type(data) == 'string' then
        dprint('show (string): msg=%s type=%s', data, tostring(notifyType))
        backend({ description = data, type = notifyType or 'info' })
    else
        dprint('show (table): desc=%s type=%s', tostring(data.description), tostring(data.type))
        backend(data)
    end
end

---Server -> client notify trigger. Server modules call
---`bridge.server.notify.to(src, ...)` which fires this event.
---@param data string|table Notification payload (passed straight through to `notify.show`).
RegisterNetEvent('sd-policetape:client:notify', function(data)
    dprint('net event sd-policetape:client:notify received: data=%s', tostring(data))
    notify.show(data)
end)

return notify
