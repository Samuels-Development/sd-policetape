---Server entry. Every change to the tape in the world goes through here and is checked: who is
---asking, whether they may, whether they are where the tape is, and how often they ask.
local config = require 'configs.config'
local log = require 'shared.log'
local locale = require 'bridge.shared.locale'
local framework = require 'bridge.shared.framework'
local inventory = require 'bridge.server.inventory'
local notify = require 'bridge.server.notify'
local player = require 'bridge.server.player'
local access = require 'server.access'
local styles = require 'server.styles'
local store = require 'server.store'
local holder = require 'shared.holder'

local PLACE = config.Placement
local ITEM = config.Item
local TEAR = config.Tear
local HOLD = config.Holders or {}
local LIMITS = config.Limits

styles.load()
store.load()

-- Tapes whose style was deleted fall back to the first style.
for _, t in pairs(store.all()) do
    if not styles.get(t.style) then t.style = styles.fallback() end
end

local itemOn = ITEM.Enabled and (inventory.system ~= nil or framework.name ~= 'standalone')
if ITEM.Enabled and not itemOn then
    log.warn('Config.Item is on but there is no inventory to check it with; tape needs no item')
end

local function t(key, vars) return locale.t(key, vars) end

local function tell(src, key, vars, kind)
    if src and src > 0 then
        notify.to(src, { title = t('notify.title'), description = t(key, vars), type = kind or 'error' })
    end
end

local function vec(v)
    if type(v) ~= 'table' and type(v) ~= 'vector3' then return nil end
    local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
    if not x or not y or not z then return nil end
    if x ~= x or y ~= y or z ~= z or math.abs(x) > 1e5 or math.abs(y) > 1e5 or math.abs(z) > 1e4 then return nil end
    return vector3(x, y, z)
end

local function pedPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped), ped
end

---Distance from p to the segment ab.
local function toSegment(p, a, b)
    local ab = b - a
    local ll = #ab
    if ll < 1e-6 then return #(p - a) end
    local tt = math.max(0.0, math.min(1.0, ((p - a).x * ab.x + (p - a).y * ab.y + (p - a).z * ab.z) / (ll * ll)))
    return #(p - (a + ab * tt))
end

local function tapeVecs(tape)
    return vector3(tape.a.x, tape.a.y, tape.a.z), vector3(tape.b.x, tape.b.y, tape.b.z)
end

-- Rate limits -----------------------------------------------------------------------------------

local hits = {} ---@type table<string, table<integer, integer[]>>

---Whether `src` may do `what` again: at most `max` times in the last `window` seconds.
local function allow(src, what, max, window)
    local now = os.time()
    hits[what] = hits[what] or {}
    local list = hits[what][src] or {}
    local kept = {}
    for i = 1, #list do
        if now - list[i] < window then kept[#kept + 1] = list[i] end
    end
    if #kept >= max then
        hits[what][src] = kept
        return false
    end
    kept[#kept + 1] = now
    hits[what][src] = kept
    return true
end

AddEventHandler('playerDropped', function()
    local src = source
    for _, per in pairs(hits) do per[src] = nil end
end)

-- Broadcasting ----------------------------------------------------------------------------------

local function sendAdd(tape) TriggerClientEvent('sd-policetape:client:add', -1, store.public(tape)) end
local function sendRemove(ids) TriggerClientEvent('sd-policetape:client:remove', -1, ids) end

local function removeTapes(ids)
    if #ids == 0 then return end
    for i = 1, #ids do store.remove(ids[i]) end
    sendRemove(ids)
end

-- State -----------------------------------------------------------------------------------------

lib.callback.register('sd-policetape:server:state', function(src)
    return { styles = styles.list(), tapes = store.publicList(), perms = access.perms(src) }
end)

lib.callback.register('sd-policetape:server:perms', function(src)
    return access.perms(src)
end)

lib.callback.register('sd-policetape:server:canStudio', function(src)
    return access.canStudio(src)
end)

-- Placing ---------------------------------------------------------------------------------------

local function hasItem(src)
    if not itemOn then return true end
    return (inventory.count(src, ITEM.Name) or 0) > 0
end

local function startPlacing(src)
    if not access.canUse(src) then return tell(src, 'notify.no_permission') end
    if not hasItem(src) then return tell(src, 'notify.no_item') end
    TriggerClientEvent('sd-policetape:client:startPlacing', src)
end

RegisterNetEvent('sd-policetape:server:requestPlace', function()
    startPlacing(source)
end)

if itemOn then
    local ok, err = pcall(inventory.registerUsable, ITEM.Name, function(src)
        startPlacing(src)
    end)
    if not ok then log.warn('could not register the %s item: %s', ITEM.Name, tostring(err)) end
end

---Every tape end tied to a holder at tie point p, each as (tape, 'a' | 'b'): the tapes sharing
---one post or cone.
local function endsAt(p)
    local out = {}
    for _, t in pairs(store.all()) do
        for _, w in ipairs({ 'a', 'b' }) do
            local q = t[w]
            if t[w .. 'p'] and math.abs(q.x - p.x) < 0.03 and math.abs(q.y - p.y) < 0.03 and math.abs(q.z - p.z) < 0.03 then
                out[#out + 1] = { t, w }
            end
        end
    end
    return out
end

---Whether the holder at tie point p is down, and how (a new tape tied to it goes down with it).
local function fallAt(p)
    for _, te in ipairs(endsAt(p)) do
        local f = te[1][te[2] .. 'f']
        if f then return f end
    end
    return nil
end

---Places a stretch of tape. Shared by the client request and the PlaceTape export.
---@return TapeRecord|nil, string|nil error (localised)
local function placeTape(src, data, skipChecks)
    if type(data) ~= 'table' then return nil, t('notify.too_far') end
    local a, b = vec(data.a), vec(data.b)
    if not a or not b then return nil, t('notify.too_far') end

    local len = #(b - a)
    if len > PLACE.MaxLength + 0.05 then return nil, t('notify.too_long', { max = math.floor(PLACE.MaxLength) }) end
    if len < PLACE.MinLength - 0.05 then return nil, t('notify.too_short') end

    local style = type(data.style) == 'string' and styles.get(data.style) and data.style or styles.fallback()

    local owner, ownerName
    if not skipChecks then
        if not access.canUse(src) then return nil, t('notify.no_permission') end
        local me, ped = pedPos(src)
        if not me then return nil, t('notify.too_far') end
        if PLACE.OnFoot and GetVehiclePedIsIn(ped, false) ~= 0 then return nil, t('notify.in_vehicle') end
        -- The end just clicked is near the player; the other end is at most one stretch away.
        if #(me - b) > PLACE.Reach + 4.0 or #(me - a) > PLACE.Reach + PLACE.MaxLength + 4.0 then
            return nil, t('notify.too_far')
        end
        if not allow(src, 'place', LIMITS.PlacePerMinute, 60) then return nil, t('notify.rate_limited') end
        if not hasItem(src) then return nil, t('notify.no_item') end

        owner = player.getIdentifier(src) or ('src:' .. src)
        ownerName = player.getName(src)
        if store.countBy(owner) >= LIMITS.PerPlayer then return nil, t('notify.limit_player', { max = LIMITS.PerPlayer }) end
    end
    if store.count() >= LIMITS.Total then return nil, t('notify.limit_server') end

    if not skipChecks and itemOn and ITEM.Consume then
        if not inventory.remove(src, ITEM.Name, 1) then return nil, t('notify.no_item') end
    end

    local ap = data.ap == true and PLACE.Posts == true
    local bp = data.bp == true and PLACE.Posts == true
    local tape = store.add({
        style = style,
        a = { x = a.x, y = a.y, z = a.z },
        b = { x = b.x, y = b.y, z = b.z },
        ap = ap,
        bp = bp,
        ah = ap and holder.resolve(data.ah).id or nil,
        bh = bp and holder.resolve(data.bh).id or nil,
        af = ap and fallAt(a) or nil,
        bf = bp and fallAt(b) or nil,
        owner = owner,
        ownerName = ownerName,
    })
    sendAdd(tape)
    log.debug('tape', '#%d %s by %s (%.1f m)', tape.id, style, tostring(ownerName or 'script'), len)
    return tape
end

lib.callback.register('sd-policetape:server:place', function(src, data)
    local tape, err = placeTape(src, data, false)
    if not tape then return { ok = false, reason = err } end
    return { ok = true, id = tape.id }
end)

-- Taking down, restyling --------------------------------------------------------------------------

local function nearTape(src, tape, slack)
    local me = pedPos(src)
    if not me then return false end
    local a, b = tapeVecs(tape)
    return toSegment(me, a, b) <= 6.0 + (slack or 0) + (tape.torn and #(b - a) * 0.5 or 0)
end

local function mayTouch(src, tape)
    if access.isAdmin(src) then return true end
    if not access.canUse(src) then return false end
    if config.Access.OthersTapes then return true end
    return tape.owner == (player.getIdentifier(src) or ('src:' .. src))
end

RegisterNetEvent('sd-policetape:server:remove', function(id)
    local src = source
    local tape = store.get(id)
    if not tape then return tell(src, 'notify.not_found') end
    if not mayTouch(src, tape) then return tell(src, 'notify.no_permission') end
    if not nearTape(src, tape) then return tell(src, 'notify.too_far') end
    if not allow(src, 'remove', 60, 60) then return tell(src, 'notify.rate_limited') end

    removeTapes({ tape.id })
    tell(src, 'notify.removed', nil, 'success')

    if itemOn and ITEM.Consume and ITEM.Refund and tape.owner == (player.getIdentifier(src) or ('src:' .. src)) then
        if inventory.add(src, ITEM.Name, 1) then tell(src, 'notify.refunded', nil, 'inform') end
    end
end)

RegisterNetEvent('sd-policetape:server:restyle', function(id, style)
    local src = source
    local tape = store.get(id)
    if not tape then return tell(src, 'notify.not_found') end
    if type(style) ~= 'string' or not styles.get(style) then return tell(src, 'notify.unknown_style') end
    if not mayTouch(src, tape) then return tell(src, 'notify.no_permission') end
    if not nearTape(src, tape) then return tell(src, 'notify.too_far') end
    if not allow(src, 'restyle', 30, 60) then return tell(src, 'notify.rate_limited') end

    tape.style = style
    store.touch()
    TriggerClientEvent('sd-policetape:client:restyle', -1, tape.id, style)
end)

-- Tearing ---------------------------------------------------------------------------------------

---A client says it just tore a tape: with a vehicle it owns (believed only if that vehicle
---exists, is theirs, is at the tape and is moving), or by pushing through it on foot (believed
---only if people may, and their ped is on foot right at the tape).
RegisterNetEvent('sd-policetape:server:tear', function(id, frac, net, byPed)
    local src = source
    local tape = store.get(id)
    if not TEAR.Enabled or not tape then return end
    if tape.torn then return end

    local function refuse(why)
        log.debug('tear', 'refused #%s from %d: %s', tostring(id), src, why)
        TriggerClientEvent('sd-policetape:client:add', src, store.public(tape)) -- put theirs back
    end

    frac = tonumber(frac)
    if not frac or frac ~= frac then return refuse('fraction') end
    frac = math.max(0.02, math.min(0.98, frac))
    if not allow(src, 'tear', 20, 60) then return refuse('rate') end

    local a, b = tapeVecs(tape)

    if byPed == true then
        if TEAR.People == false then return refuse('people cannot tear tape') end
        local me, ped = pedPos(src)
        if not me then return refuse('no ped') end
        if GetVehiclePedIsIn(ped, false) ~= 0 then return refuse('in a vehicle') end
        -- The tape bows (TEAR.PeoplePush) before it snaps; allow for that and for latency.
        if toSegment(me, a, b) > (TEAR.PeoplePush or 1.0) + 2.0 then return refuse('not at the tape') end
        tape.torn = frac
        tape.tornAt = os.time()
        store.touch()
        TriggerClientEvent('sd-policetape:client:tear', -1, tape.id, frac)
        return
    end

    local veh = tonumber(net) and net ~= 0 and NetworkGetEntityFromNetworkId(net) or 0
    if veh == 0 or not DoesEntityExist(veh) then
        local _, ped = pedPos(src)
        veh = ped and GetVehiclePedIsIn(ped, false) or 0
    end
    if veh == 0 or not DoesEntityExist(veh) then return refuse('no vehicle') end
    if NetworkGetEntityOwner(veh) ~= src then return refuse('not theirs') end

    -- A vehicle drags tape up to Tear.VehiclePush before it snaps; allow for that and latency.
    local radius = 6.0 + (TEAR.VehiclePush or 1.8)
    if toSegment(GetEntityCoords(veh), a, b) > radius then return refuse('not at the tape') end
    local v = GetEntityVelocity(veh)
    if #v < 1.0 then return refuse('not moving') end

    tape.torn = frac
    tape.tornAt = os.time()
    store.touch()
    TriggerClientEvent('sd-policetape:client:tear', -1, tape.id, frac)
end)

-- Knocking holders over, standing them up -----------------------------------------------------

---A client says it just knocked over the post or cone at one end of a tape: with its own ped
---(a kick, or running into it: believed only if that ped is on foot right there) or with a
---vehicle it owns (believed only if that vehicle exists, is theirs, is there and is moving).
---Every tape tied to that holder goes down with it.
RegisterNetEvent('sd-policetape:server:knock', function(id, which, dx, dy, slide, net, byPed)
    local src = source
    if HOLD.Knock == false then return end
    local tape = store.get(id)
    if not tape or (which ~= 'a' and which ~= 'b') or not tape[which .. 'p'] then return end
    local p = tape[which]
    if tape[which .. 'f'] then return end

    local function refuse(why)
        log.debug('knock', 'refused #%s %s from %d: %s', tostring(id), which, src, why)
        TriggerClientEvent('sd-policetape:client:standup', src, p.x, p.y, p.z) -- put theirs back up
    end

    dx, dy, slide = tonumber(dx), tonumber(dy), tonumber(slide) or 0.0
    if not dx or not dy or dx ~= dx or dy ~= dy then return refuse('direction') end
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 0.5 or l > 1.5 then return refuse('direction') end
    dx, dy = dx / l, dy / l
    slide = math.max(0.0, math.min(3.0, slide == slide and slide or 0.0))
    if not allow(src, 'knock', 30, 60) then return refuse('rate') end

    local at = vector3(p.x, p.y, p.z)
    local function near(v, r)
        local d = v - at
        return d.x * d.x + d.y * d.y < r * r and math.abs(d.z) < 3.0
    end

    if byPed == true then
        if HOLD.Kick == false and HOLD.Run == false then return refuse('people cannot knock holders over') end
        local me, ped = pedPos(src)
        if not me then return refuse('no ped') end
        if GetVehiclePedIsIn(ped, false) ~= 0 then return refuse('in a vehicle') end
        if not near(me, 3.5) then return refuse('not at it') end
        slide = math.min(slide, 0.5)
    else
        if HOLD.Vehicles == false then return refuse('vehicles cannot knock holders over') end
        local veh = tonumber(net) and net ~= 0 and NetworkGetEntityFromNetworkId(net) or 0
        if veh == 0 or not DoesEntityExist(veh) then
            local _, ped = pedPos(src)
            veh = ped and GetVehiclePedIsIn(ped, false) or 0
        end
        if veh == 0 or not DoesEntityExist(veh) then return refuse('no vehicle') end
        if NetworkGetEntityOwner(veh) ~= src then return refuse('not theirs') end
        if not near(GetEntityCoords(veh), 9.0) then return refuse('not at it') end
        if #GetEntityVelocity(veh) < 0.5 then return refuse('not moving') end
    end

    local fall = { x = dx, y = dy, s = slide }
    for _, te in ipairs(endsAt(p)) do te[1][te[2] .. 'f'] = fall end
    store.touch()
    TriggerClientEvent('sd-policetape:client:knock', -1, p.x, p.y, p.z, fall)
end)

---A player stands a knocked-over holder back up. Anyone allowed to use tape may.
RegisterNetEvent('sd-policetape:server:standup', function(id, which)
    local src = source
    if HOLD.StandUp == false then return end
    local tape = store.get(id)
    if not tape or (which ~= 'a' and which ~= 'b') or not tape[which .. 'p'] then return end
    local p = tape[which]
    if not tape[which .. 'f'] then return end
    if not access.canUse(src) then return tell(src, 'notify.no_permission') end
    local me = pedPos(src)
    if not me or #(me - vector3(p.x, p.y, p.z)) > 4.5 then return tell(src, 'notify.too_far') end
    if not allow(src, 'standup', 30, 60) then return tell(src, 'notify.rate_limited') end

    for _, te in ipairs(endsAt(p)) do te[1][te[2] .. 'f'] = nil end
    store.touch()
    TriggerClientEvent('sd-policetape:client:standup', -1, p.x, p.y, p.z)
end)

-- Coming down by themselves ---------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(20000)
        local now = os.time()
        local gone = {}
        for id, tape in pairs(store.all()) do
            if config.Lifetime > 0 and now - (tape.created or now) > config.Lifetime * 60 then
                gone[#gone + 1] = id
            elseif tape.torn and TEAR.RemoveAfter > 0 and now - (tape.tornAt or now) > TEAR.RemoveAfter then
                gone[#gone + 1] = id
            end
        end
        removeTapes(gone)
    end
end)

-- Tape Studio -----------------------------------------------------------------------------------

lib.callback.register('sd-policetape:server:saveStyle', function(src, raw)
    if not access.canStudio(src) then return { ok = false, error = t('notify.no_permission') } end
    if not allow(src, 'studio', 20, 60) then return { ok = false, error = t('notify.rate_limited') } end
    local s, errKey, vars = styles.save(raw, player.getName(src))
    if not s then return { ok = false, error = t('notify.' .. errKey, vars) } end
    log.info('style "%s" (%s) saved by %s', s.label, s.id, player.getName(src))
    return { ok = true, id = s.id }
end)

lib.callback.register('sd-policetape:server:deleteStyle', function(src, id)
    if not access.canStudio(src) then return { ok = false, error = t('notify.no_permission') } end
    if type(id) ~= 'string' then return { ok = false, error = t('notify.unknown_style') } end
    local s = styles.delete(id)
    if not s then return { ok = false, error = t('notify.unknown_style') } end

    -- Tape still printed with it takes the first style.
    local fallback = styles.fallback()
    for _, tape in pairs(store.all()) do
        if tape.style == id then
            tape.style = fallback
            TriggerClientEvent('sd-policetape:client:restyle', -1, tape.id, fallback)
        end
    end
    store.touch()
    log.info('style "%s" (%s) deleted by %s', s.label, s.id, player.getName(src))
    return { ok = true }
end)

-- Admin -----------------------------------------------------------------------------------------

local function clearNear(coords, radius)
    local ids = {}
    for id, tape in pairs(store.all()) do
        if not coords then
            ids[#ids + 1] = id
        else
            local a, b = tapeVecs(tape)
            if toSegment(coords, a, b) <= radius then ids[#ids + 1] = id end
        end
    end
    removeTapes(ids)
    return #ids
end

lib.addCommand(config.Commands.Clear, {
    help = 'Take down police tape near you, or everywhere',
    params = { { name = 'radius', type = 'string', help = 'metres (default 25), or "all"', optional = true } },
}, function(src, args)
    if src > 0 and not access.isAdmin(src) then return tell(src, 'notify.no_permission') end
    local arg = args.radius and tostring(args.radius):lower() or nil
    local count
    if arg == 'all' or src == 0 then
        count = clearNear(nil)
    else
        local me = pedPos(src)
        count = clearNear(me, tonumber(arg) or 25.0)
    end
    if src == 0 then
        log.info('took down %d tapes', count)
    elseif count > 0 then
        tell(src, 'notify.cleared', { count = count }, 'success')
    else
        tell(src, 'notify.cleared_none', nil, 'inform')
    end
end)

-- Exports ---------------------------------------------------------------------------------------

---Places tape from another resource, with no player checks. `a` and `b` are the tie points.
---@return integer|nil id
exports('PlaceTape', function(style, a, b, opts)
    opts = opts or {}
    local tape = placeTape(0, {
        style = style, a = a, b = b, ap = opts.postA, bp = opts.postB, ah = opts.holderA, bh = opts.holderB,
    }, true)
    return tape and tape.id or nil
end)

exports('RemoveTape', function(id)
    if not store.get(id) then return false end
    removeTapes({ id })
    return true
end)

---Takes down all tape within `radius` of `coords`, or everywhere when coords is nil.
exports('ClearTapes', function(coords, radius)
    return clearNear(coords and vector3(coords.x, coords.y, coords.z) or nil, tonumber(radius) or 25.0)
end)

exports('TearTape', function(id, frac)
    local tape = store.get(id)
    if not tape or tape.torn then return false end
    tape.torn = math.max(0.02, math.min(0.98, tonumber(frac) or 0.5))
    tape.tornAt = os.time()
    store.touch()
    TriggerClientEvent('sd-policetape:client:tear', -1, tape.id, tape.torn)
    return true
end)

exports('GetTapes', function() return store.publicList() end)
exports('GetStyles', function() return styles.list() end)

-- If the resource restarted with players on, they ask for the state themselves on start.
log.info('ready: %d tapes, %d styles', store.count(), #styles.list())
