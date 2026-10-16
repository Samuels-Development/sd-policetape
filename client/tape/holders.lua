---The posts and cones tape is tied to, as things in this client's world: stood under tie points,
---shared by every tape tied at the same point, knocked over and stood back up.
---
---Each client stands its own copy (a local, frozen object), so a holder costs the network
---nothing; what is shared is whether it is down and which way, which the server keeps with the
---tapes and sends to everyone. Standing, a holder stops peds but not vehicles: a car knocks it
---over rather than stopping dead against a 3 cm pole. Lying, it stops nothing.
---
---What knocks one over is decided like tearing: by the client whose ped kicked it or ran into
---it, or that owns the vehicle that hit it. It goes down there at once, the server checks it,
---and every other client plays the same fall.
local config = require 'configs.config'
local log = require 'shared.log'
local holder = require 'shared.holder'
local sim = require 'client.tape.sim'
local colliders = require 'client.tape.colliders'

local sqrt, min, max = math.sqrt, math.min, math.max

local HOLD = config.Holders or {}
local FALL_TIME, STAND_TIME = 0.6, 0.45

local holders = {}

---@class HolderEntry
---@field key string
---@field def HolderDef
---@field x number the tie point, standing
---@field y number
---@field z number
---@field gx number the ground under it: the model's origin, standing
---@field gy number
---@field gz number
---@field heading number radians
---@field obj integer|false
---@field refs integer
---@field ties table<integer, string> tape id -> 'a' | 'b'
---@field fall table|nil { x, y, s }: down, the way it went and how far it slid
---@field anim table|nil { t0, kind = 'fall' | 'stand', from }
---@field pose HolderPose where it is now
---@field upright HolderPose where it stands
---@field version integer goes up whenever it moves
---@field sent integer|nil when this client last reported knocking it

---@type table<string, HolderEntry>
local entries = {}
local warned = {}

---The key of a tie point: every tape tied there shares one holder.
local function key(x, y, z)
    return ('%.2f:%.2f:%.2f'):format(x, y, z)
end
holders.key = key

local function loadModel(model)
    if not IsModelInCdimage(model) then return false end
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(model)
end

---Puts the entity where the entry's pose says.
local function place(e)
    if not e.obj then return end
    local p = e.pose
    SetEntityCoordsNoOffset(e.obj, p.x, p.y, p.z, false, false, false)
    local qx, qy, qz, qw = holder.quat(p)
    SetEntityQuaternion(e.obj, qx, qy, qz, qw)
end

local function setSolid(e, solid)
    if e.obj then SetEntityCollision(e.obj, solid, solid) end
end

---Stands a holder under a tie point, or counts one more tape tied to the one already there.
---@param fall table|nil down already (it appears lying where it fell)
---@return string key
function holders.take(x, y, z, heading, holderId, fall, tapeId, endName)
    local k = key(x, y, z)
    local e = entries[k]
    if e then
        e.refs = e.refs + 1
        e.ties[tapeId] = endName
        return k
    end
    local def = holder.resolve(holderId)
    e = {
        key = k, def = def, x = x, y = y, z = z, gx = x, gy = y, gz = z - def.tie, heading = heading,
        obj = false, refs = 1, ties = { [tapeId] = endName }, fall = fall, version = 1,
    }
    e.upright = holder.pose(def, e.gx, e.gy, e.gz, heading, nil)
    e.pose = fall and holder.pose(def, e.gx, e.gy, e.gz, heading, fall, 1.0, 1.0) or e.upright
    entries[k] = e
    CreateThread(function()
        local model = joaat(def.model)
        if not loadModel(model) then
            if not warned[def.model] then
                warned[def.model] = true
                log.warn('model %s is not streamed: is stream/ complete (and the resource restarted since)?', def.model)
            end
            return
        end
        if entries[k] ~= e then return end
        local obj = CreateObjectNoOffset(model, e.gx, e.gy, e.gz, false, false, false)
        FreezeEntityPosition(obj, true)
        SetEntityLodDist(obj, 200)
        SetModelAsNoLongerNeeded(model)
        e.obj = obj
        place(e)
        setSolid(e, not e.fall)
    end)
    return k
end

---One tape fewer tied to it; the last one takes it away.
function holders.drop(k, tapeId)
    local e = k and entries[k]
    if not e then return end
    e.refs = e.refs - 1
    e.ties[tapeId] = nil
    if e.refs > 0 then return end
    entries[k] = nil
    if e.obj and DoesEntityExist(e.obj) then DeleteEntity(e.obj) end
end

---@return HolderEntry|nil
function holders.get(k)
    return k and entries[k] or nil
end

function holders.all()
    return entries
end

---A standing holder whose tie point is near (x, y, z), to tie another tape to.
---@return HolderEntry|nil
function holders.at(x, y, z, radius)
    local best, bd
    for _, e in pairs(entries) do
        if not e.fall and not e.anim then
            local dx, dy = e.x - x, e.y - y
            local d = sqrt(dx * dx + dy * dy)
            if d < radius and z > e.gz - 0.3 and z < e.z + 0.4 and (not bd or d < bd) then best, bd = e, d end
        end
    end
    return best
end

function holders.isHolder(ent)
    for _, e in pairs(entries) do
        if e.obj == ent then return true end
    end
    return false
end

-- Where things are on it now ------------------------------------------------------------------

---The tie point as it is now (it moves with the holder when it goes down).
function holders.endPoint(e)
    if not e.fall and not e.anim then return e.x, e.y, e.z end
    return holder.point(e.pose, 0.0, 0.0, e.def.tie)
end

---The axis of the holder now, as a unit vector (up, standing).
function holders.axis(e)
    return holder.dir(e.pose, 0.0, 0.0, 1.0)
end

---Where a torn tape's end leaves the holder, `r` out from its axis on the side towards (ox, oy)
---(where the tape ran), and which way its face looks: the shape sim.tieOff takes.
function holders.tieOff(e, ox, oy, r)
    local hx, hy = ox - e.x, oy - e.y
    local l = sqrt(hx * hx + hy * hy)
    if l > 1e-3 then hx, hy = hx / l, hy / l else hx, hy = 1.0, 0.0 end
    local lx, ly = holder.local_(e.upright, hx, hy, 0.0)
    local x, y, z = holder.point(e.pose, lx * r, ly * r, e.def.tie)
    local nx, ny, nz = holder.dir(e.pose, lx, ly, 0.0)
    return { x = x, y = y, z = z, nx = nx, ny = ny, nz = nz }
end

---The holder's body as a (tapered) solid for torn tape to hang against.
function holders.collider(e)
    local b = e.def.body
    local ax, ay, az = holder.point(e.pose, 0.0, 0.0, b[1])
    local bx, by, bz = holder.point(e.pose, 0.0, 0.0, b[3])
    return sim.staticCapsule(ax, ay, az, bx, by, bz, b[2], b[4])
end

---The top of its base as raised ground ({ x, y, z, r }), while it stands; nil lying.
function holders.baseTop(e)
    if e.fall or e.anim then return nil end
    return { e.gx, e.gy, e.gz + e.def.base[2], e.def.base[1] }
end

-- Going down and getting up ---------------------------------------------------------------------

---Knocks a holder over: `fall` = { x, y, s }, the unit direction and the slide.
function holders.knock(k, fall)
    local e = entries[k]
    if not e or e.fall then return end
    e.fall = fall
    e.anim = { t0 = GetGameTimer(), kind = 'fall' }
    e.version = e.version + 1
    setSolid(e, false)
end

---Stands a knocked-over holder back up where it was.
function holders.standUp(k)
    local e = entries[k]
    if not e or not e.fall then return end
    e.anim = { t0 = GetGameTimer(), kind = 'stand', from = e.fall }
    e.fall = nil
    e.version = e.version + 1
end

---Moves every holder that is falling or getting up. Call once a frame.
function holders.update()
    local now = GetGameTimer()
    for _, e in pairs(entries) do
        local a = e.anim
        if a then
            local t = (now - a.t0) / 1000.0
            if a.kind == 'fall' then
                local fa, fs, done = holder.ease(t, FALL_TIME)
                e.pose = holder.pose(e.def, e.gx, e.gy, e.gz, e.heading, e.fall, fa, fs)
                if done then e.anim = nil end
            else
                local u = min(1.0, t / STAND_TIME)
                local f = 1.0 - u * u * (3.0 - 2.0 * u)
                e.pose = holder.pose(e.def, e.gx, e.gy, e.gz, e.heading, a.from, f, f)
                if u >= 1.0 then
                    e.anim = nil
                    e.pose = e.upright
                    setSolid(e, true)
                end
            end
            e.version = e.version + 1
            place(e)
        end
    end
end

---Lets the vehicles near standing holders through them (they knock them over instead). The
---game wants this every frame.
function holders.passVehicles(px, py)
    local list, n = colliders.list, colliders.count
    if n == 0 then return end
    for _, e in pairs(entries) do
        if e.obj and not e.fall then
            local dx, dy = e.gx - px, e.gy - py
            if dx * dx + dy * dy < 3600 then
                for i = 1, n do
                    local c = list[i]
                    if c.kind == 2 then
                        local vx, vy = e.gx - c.ox, e.gy - c.oy
                        local r = c.prof.radius + 2.0
                        if vx * vx + vy * vy < r * r then SetEntityNoCollisionEntity(e.obj, c.entity, true) end
                    end
                end
            end
        end
    end
end

-- Being knocked over ------------------------------------------------------------------------------

---The body's radius at height z above its ground.
local function radiusAt(def, z)
    local b = def.body
    if z <= b[1] then return def.base[1] end
    local t = min(1.0, (z - b[1]) / max(1e-3, b[3] - b[1]))
    return b[2] + (b[4] - b[2]) * t
end

---What this client knocks over this frame: holders hit by a vehicle it owns, or kicked or run
---into by its own ped. Each comes back once (`sent`), as
---{ entry, x, y, s, net, byPed }; the caller knocks it down here and tells the server.
---@return table[]|nil
function holders.detect(ped, now)
    if HOLD.Knock == false then return nil end
    local p = GetEntityCoords(ped)
    local onFoot = not IsPedInAnyVehicle(ped, false) and not IsEntityDead(ped)
    local melee, fx, fy = false, 0.0, 0.0
    local vx, vy, speed = 0.0, 0.0, 0.0
    if onFoot then
        if HOLD.Kick ~= false then
            melee = IsPedPerformingMeleeAction(ped) or IsControlJustPressed(0, 140) or IsControlJustPressed(0, 141)
                or IsControlJustPressed(0, 142)
            local f = GetEntityForwardVector(ped)
            fx, fy = f.x, f.y
        end
        if HOLD.Run ~= false then
            local v = GetEntityVelocity(ped)
            vx, vy = v.x, v.y
            speed = sqrt(vx * vx + vy * vy)
        end
    end
    local minVeh = (HOLD.VehicleSpeedKmh or 3.0) / 3.6
    local me = PlayerId()
    local out

    for _, e in pairs(entries) do
        if e.obj and not e.fall and not e.anim and (not e.sent or now - e.sent > 1500) then
            local dx, dy = e.gx - p.x, e.gy - p.y
            local d2 = dx * dx + dy * dy
            if d2 < 400 then
                local hit
                if HOLD.Vehicles ~= false then
                    for i = 1, colliders.count do
                        local c = colliders.list[i]
                        if c.kind == 2 and c.speed >= minVeh then
                            local ox, oy = e.gx - c.ox, e.gy - c.oy
                            local r = c.prof.radius + 0.6
                            if ox * ox + oy * oy < r * r and NetworkGetEntityOwner(c.entity) == me then
                                local top = e.def.body[3]
                                for _, f in ipairs({ 0.12, 0.3, 0.55, 0.85 }) do
                                    local z = top * f
                                    if sim.insideVehicle(c, e.gx, e.gy, e.gz + z, radiusAt(e.def, z) + 0.03) then
                                        local l = sqrt(c.vx * c.vx + c.vy * c.vy)
                                        if l > 0.1 then
                                            local ent = c.entity
                                            hit = {
                                                x = c.vx / l, y = c.vy / l, s = min(3.0, max(0.3, c.speed * 0.15)),
                                                net = NetworkGetEntityIsNetworked(ent) and VehToNet(ent) or 0, byPed = false,
                                            }
                                        end
                                        break
                                    end
                                end
                                if hit then break end
                            end
                        end
                    end
                end
                if not hit and onFoot and d2 < 4.0 then
                    local d = sqrt(d2)
                    local ux, uy = dx / max(d, 1e-3), dy / max(d, 1e-3)
                    if melee and d < 1.35 and fx * ux + fy * uy > 0.5 then
                        hit = { x = fx, y = fy, s = 0.25, net = 0, byPed = true }
                    elseif speed > 3.0 and d < e.def.base[1] + 0.55 and (vx * ux + vy * uy) / speed > 0.55 then
                        hit = { x = vx / speed, y = vy / speed, s = 0.15, net = 0, byPed = true }
                    end
                end
                if hit then
                    e.sent = now
                    hit.entry = e
                    out = out or {}
                    out[#out + 1] = hit
                end
            end
        end
    end
    return out
end

---The nearest knocked-over holder in front of a player at (x, y, z) facing (fx, fy), within
---`reach` metres, with one tape tied to it (what the server is told about).
---@return HolderEntry|nil, integer|nil tapeId, string|nil endName
function holders.fallenNear(x, y, z, fx, fy, reach)
    local best, bd
    for _, e in pairs(entries) do
        if e.fall and not e.anim then
            local cx, cy, cz = holder.point(e.pose, 0.0, 0.0, e.def.body[3] * 0.5)
            local dx, dy = cx - x, cy - y
            local d = sqrt(dx * dx + dy * dy)
            if d < reach and math.abs(cz - z) < 2.0 and (d < 0.6 or (dx * fx + dy * fy) / d > 0.2) and (not bd or d < bd) then
                best, bd = e, d
            end
        end
    end
    if not best then return nil end
    for id, which in pairs(best.ties) do return best, id, which end
    return nil
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, e in pairs(entries) do
        if e.obj and DoesEntityExist(e.obj) then DeleteEntity(e.obj) end
    end
end)

return holders
