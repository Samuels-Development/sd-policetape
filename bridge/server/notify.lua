---@type table Notification helper module returned to consumers.
local notify = {}

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:notify')

dprint('module load — notify bridge ready')

---Send a notification to a specific player.
---@param source number Target player id.
---@param data string|table Either a (description) string or a payload table.
---@param notifyType? 'info'|'success'|'error' Used when `data` is a string.
function notify.to(source, data, notifyType)
    if type(data) == 'string' then
        dprint('to: src=%s type=%s message=%s', tostring(source), tostring(notifyType or 'info'), tostring(data))
        TriggerClientEvent('sd-policetape:client:notify', source,
            { description = data, type = notifyType or 'info' })
    else
        dprint('to: src=%s table payload type=%s description=%s', tostring(source), tostring(type(data) == 'table' and data.type or '?'), tostring(type(data) == 'table' and data.description or data))
        TriggerClientEvent('sd-policetape:client:notify', source, data)
    end
end

return notify
