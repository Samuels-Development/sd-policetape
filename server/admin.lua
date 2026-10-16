---The admin menu (/tapeadmin): every tape on the server, the switches of shared/settings.lua, and
---which styles and holders players may put up. Laid out like sd-computers' admin panel: one
---snapshot to open with, one call per action, and every reply carries a fresh snapshot. Every
---call checks again that the caller is an admin.
local config = require 'configs.config'
local locale = require 'bridge.shared.locale'
local log = require 'shared.log'
local holder = require 'shared.holder'
local player = require 'bridge.server.player'
local access = require 'server.access'
local styles = require 'server.styles'
local store = require 'server.store'
local settings = require 'server.settings'

local admin = {}

local function t(key, vars) return locale.t(key, vars) end

local function row(tape)
    local a, b = tape.a, tape.b
    local s = styles.get(tape.style)
    local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
    return {
        id = tape.id,
        style = tape.style,
        label = s and s.label or tape.style,
        owner = tape.ownerName,
        script = tape.owner == nil,
        created = tape.created,
        length = math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) * 10 + 0.5) / 10,
        torn = tape.torn and true or false,
        down = (tape.af or tape.bf) and true or false,
        persist = tape.persist ~= false,
        a = a,
        b = b,
        ah = tape.ap and tape.ah or nil,
        bh = tape.bp and tape.bh or nil,
    }
end

local function snapshot()
    local tapes = {}
    for _, tape in pairs(store.all()) do tapes[#tapes + 1] = row(tape) end
    table.sort(tapes, function(x, y) return x.id > y.id end) -- newest first
    local holders = {}
    for _, def in ipairs(holder.list) do
        holders[#holders + 1] = { id = def.id, label = def.label, model = def.model, image = def.image, height = def.body[3] }
    end
    local pub = settings.public()
    return {
        now = os.time(),
        tapes = tapes,
        toggles = settings.admin(),
        offStyles = pub.offStyles,
        offHolders = pub.offHolders,
        holders = holders,
        total = config.Limits.Total,
    }
end

local function broadcast()
    TriggerClientEvent('sd-policetape:client:settings', -1, settings.public())
end

---@param deps { removeTapes: fun(ids: integer[]), tell: fun(src: integer, key: string, vars?: table, kind?: string), setPersist: fun(tape: TapeRecord, on: boolean) }
function admin.init(deps)
    ---Each returns ok and, for a toast, a message.
    local verbs = {
        toggle = function(src, d)
            if not settings.setToggle(d.key, d.on) then return false, t('notify.admin_invalid') end
            -- Saving switched on or off: data/tapes.json is written again (emptied, or filled).
            if d.key == 'Persist' then store.touch() end
            broadcast()
            log.info('%s set %s to %s', player.getName(src) or src, tostring(d.key), tostring(d.on))
            return true
        end,
        styles = function(src, d)
            local ok, err = settings.setStyles(d.ids, d.on == true)
            if not ok then return false, t('notify.' .. err) end
            broadcast()
            log.info('%s turned %d styles %s', player.getName(src) or src, type(d.ids) == 'table' and #d.ids or 0, d.on and 'on' or 'off')
            return true
        end,
        holders = function(src, d)
            local ok, err = settings.setHolders(d.ids, d.on == true)
            if not ok then return false, t('notify.' .. err) end
            broadcast()
            log.info('%s turned %d holders %s', player.getName(src) or src, type(d.ids) == 'table' and #d.ids or 0, d.on and 'on' or 'off')
            return true
        end,
        remove = function(src, d)
            local tape = store.get(d.id)
            if not tape then return false, t('notify.not_found') end
            deps.removeTapes({ tape.id })
            log.info('%s took down tape #%d', player.getName(src) or src, tape.id)
            return true
        end,
        persist = function(src, d)
            local tape = store.get(d.id)
            if not tape then return false, t('notify.not_found') end
            deps.setPersist(tape, d.on == true)
            log.info('%s set tape #%d to %s', player.getName(src) or src, tape.id, d.on and 'kept' or 'not kept')
            return true
        end,
        removeTorn = function(src)
            local gone = {}
            for id, tape in pairs(store.all()) do
                if tape.torn then gone[#gone + 1] = id end
            end
            deps.removeTapes(gone)
            log.info('%s took down %d torn tapes', player.getName(src) or src, #gone)
            return true, t('notify.cleared', { count = #gone })
        end,
        removeAll = function(src)
            local gone = {}
            for id in pairs(store.all()) do gone[#gone + 1] = id end
            deps.removeTapes(gone)
            log.info('%s took down all %d tapes', player.getName(src) or src, #gone)
            return true, t('notify.cleared', { count = #gone })
        end,
    }

    lib.callback.register('sd-policetape:server:admin:snapshot', function(src)
        if not access.isAdmin(src) then return nil end
        return snapshot()
    end)

    lib.callback.register('sd-policetape:server:admin:act', function(src, verb, data)
        if not access.isAdmin(src) then return { ok = false, message = t('notify.no_permission') } end
        local fn = verbs[verb]
        if not fn then return { ok = false, message = t('notify.admin_invalid'), snapshot = snapshot() } end
        local ran, ok, message = pcall(fn, src, type(data) == 'table' and data or {})
        if not ran then
            log.error('admin action %s failed: %s', tostring(verb), tostring(ok))
            return { ok = false, message = t('notify.admin_invalid'), snapshot = snapshot() }
        end
        return { ok = ok == true, message = message, snapshot = snapshot() }
    end)

    lib.addCommand(config.Commands.Admin, { help = 'Open the police tape admin menu' }, function(src)
        if src <= 0 then return end
        if not access.isAdmin(src) then return deps.tell(src, 'notify.no_permission') end
        TriggerClientEvent('sd-policetape:client:openAdmin', src)
    end)
end

return admin
