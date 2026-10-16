---The things tape is tied to on open ground (configs/holders.lua), and where every part of one
---is when it stands, falls and lies. Pure Lua, no natives: the server reads the list, the client
---the poses, and tests/sim_harness.lua both.
---
---A holder's own frame: origin at the centre of its base's underside, +Z up its axis. Standing,
---that frame is the ground point turned to its heading. Knocked down, it tips over the edge of its
---base in the direction it was pushed until it rests on the top edge of the base and the tip of
---its body (a square base turns on the way, so it lands on a side, not a corner), and slides on
---a little if a vehicle sent it.
local config = require 'configs.config'

local sqrt, sin, cos, atan, pi, min, max = math.sqrt, math.sin, math.cos, math.atan, math.pi, math.min, math.max

local holder = {}

---@class HolderDef
---@field id string
---@field label string
---@field model string
---@field tie number
---@field tieRadius number
---@field body number[] { z0, r0, z1, r1 }
---@field base table { r, h, square }
---@field rest number radians it turns through to lie down
---@field lift number metres it is raised by, lying, so nothing is under the ground

---@type HolderDef[]
holder.list = {}
---@type table<string, HolderDef>
local byId = {}

---Where it lies once down: the angle it has turned through about the edge of its base, and how
---far it is then lifted so no part is below the ground.
---@param def HolderDef
---@return number angle, number lift
function holder.restOf(def)
    local p, h = def.base[1], def.base[2]
    local z0, r0, z1, r1 = def.body[1], def.body[2], def.body[3], def.body[4]
    -- Resting on the top edge of its base and the tip of its body (seen side on, in the plane it
    -- falls in, about the bottom edge of the base it tipped over).
    local angle = pi - atan((z1 - h) / max(1e-3, p - r1))
    local c, s = cos(angle), sin(angle)
    local lowest = 0.0
    for _, q in ipairs({ { p, h }, { -p, 0.0 }, { -p, h }, { r0, z0 }, { -r0, z0 }, { r1, z1 }, { -r1, z1 } }) do
        local z = -(q[1] - p) * s + q[2] * c
        if z < lowest then lowest = z end
    end
    return angle, -lowest
end

for _, raw in ipairs(require 'configs.holders') do
    if type(raw) == 'table' and type(raw.id) == 'string' and not byId[raw.id] then
        local def = {
            id = raw.id, label = raw.label or raw.id, model = raw.model,
            tie = raw.tie, tieRadius = raw.tieRadius, body = raw.body, base = raw.base,
        }
        def.rest, def.lift = holder.restOf(def)
        holder.list[#holder.list + 1] = def
        byId[def.id] = def
    end
end

---@param id any
---@return HolderDef|nil
function holder.get(id)
    return byId[id]
end

---The holder new tape stands on unless the player picks another.
---@return HolderDef
function holder.default()
    return byId[config.Placement.Holder] or holder.list[1]
end

---The holder `id`, or the default when there is none of that name (removed from the config).
---@return HolderDef
function holder.resolve(id)
    return byId[id] or holder.default()
end

-- Poses ----------------------------------------------------------------------------------------

---Rotation about the unit axis (ax, ay, az) by `a`, as nine numbers, row by row.
local function axisAngle(ax, ay, az, a)
    local c, s = cos(a), sin(a)
    local t = 1.0 - c
    return {
        t * ax * ax + c, t * ax * ay - s * az, t * ax * az + s * ay,
        t * ax * ay + s * az, t * ay * ay + c, t * ay * az - s * ax,
        t * ax * az - s * ay, t * ay * az + s * ax, t * az * az + c,
    }
end

local function mul(A, B)
    local R = {}
    for r = 0, 2 do
        for c = 0, 2 do
            R[r * 3 + c + 1] = A[r * 3 + 1] * B[c + 1] + A[r * 3 + 2] * B[c + 4] + A[r * 3 + 3] * B[c + 7]
        end
    end
    return R
end

---Wraps an angle into (-pi, pi].
local function wrap(a)
    a = (a + pi) % (2 * pi) - pi
    return a <= -pi and a + 2 * pi or a
end

---@class HolderPose
---@field x number origin (centre of the base's underside)
---@field y number
---@field z number
---@field m number[] rotation, row by row: world = m * local

---Where a holder is. `heading` is its standing heading in radians (GTA's: 0 faces +Y). `fall`
---is nil standing, else { x, y } the unit direction it was knocked and `s` the metres it slides.
---`fa` (0..1) is how far it has tipped and `fs` (0..1) how far it has slid, so a caller can ease
---each its own way while it falls.
---@param def HolderDef
---@return HolderPose
function holder.pose(def, gx, gy, gz, heading, fall, fa, fs)
    local yaw = heading
    if not fall then
        return { x = gx, y = gy, z = gz, m = axisAngle(0.0, 0.0, 1.0, yaw) }
    end
    fa, fs = fa or 1.0, fs or 1.0
    local dx, dy = fall.x, fall.y
    if def.base[3] then
        -- A square base turns so a side, not a corner, goes over first.
        local side = wrap(atan(dy, dx) - yaw)
        side = side - (pi / 2) * math.floor(side / (pi / 2) + 0.5)
        yaw = yaw + side * fa
    end
    local p = def.base[1]
    local tip = axisAngle(-dy, dx, 0.0, def.rest * fa)
    local m = mul(tip, axisAngle(0.0, 0.0, 1.0, yaw))
    -- The pivot is the edge of the base on the side it falls to, on the ground. Only the tipping
    -- moves the origin round it: turning on its own axis (the yaw) leaves the origin where it is.
    local px, py = gx + dx * p, gy + dy * p
    local ox, oy = -dx * p, -dy * p
    local x = px + tip[1] * ox + tip[2] * oy
    local y = py + tip[4] * ox + tip[5] * oy
    local z = gz + tip[7] * ox + tip[8] * oy
    local slide = (fall.s or 0.0) * fs
    return { x = x + dx * slide, y = y + dy * slide, z = z + def.lift * fa, m = m }
end

---A point in the holder's frame, in the world.
---@param pose HolderPose
function holder.point(pose, lx, ly, lz)
    local m = pose.m
    return pose.x + m[1] * lx + m[2] * ly + m[3] * lz,
        pose.y + m[4] * lx + m[5] * ly + m[6] * lz,
        pose.z + m[7] * lx + m[8] * ly + m[9] * lz
end

---A direction in the holder's frame, in the world.
function holder.dir(pose, lx, ly, lz)
    local m = pose.m
    return m[1] * lx + m[2] * ly + m[3] * lz, m[4] * lx + m[5] * ly + m[6] * lz, m[7] * lx + m[8] * ly + m[9] * lz
end

---A world direction in the holder's frame (the inverse of dir: m is a rotation).
function holder.local_(pose, wx, wy, wz)
    local m = pose.m
    return m[1] * wx + m[4] * wy + m[7] * wz, m[2] * wx + m[5] * wy + m[8] * wz, m[3] * wx + m[6] * wy + m[9] * wz
end

---The pose's rotation as a quaternion (x, y, z, w), for SetEntityQuaternion.
function holder.quat(pose)
    local m = pose.m
    local tr = m[1] + m[5] + m[9]
    local x, y, z, w
    if tr > 0 then
        local s = sqrt(tr + 1.0) * 2
        w, x, y, z = 0.25 * s, (m[8] - m[6]) / s, (m[3] - m[7]) / s, (m[4] - m[2]) / s
    elseif m[1] > m[5] and m[1] > m[9] then
        local s = sqrt(1.0 + m[1] - m[5] - m[9]) * 2
        w, x, y, z = (m[8] - m[6]) / s, 0.25 * s, (m[2] + m[4]) / s, (m[3] + m[7]) / s
    elseif m[5] > m[9] then
        local s = sqrt(1.0 + m[5] - m[1] - m[9]) * 2
        w, x, y, z = (m[3] - m[7]) / s, (m[2] + m[4]) / s, 0.25 * s, (m[6] + m[8]) / s
    else
        local s = sqrt(1.0 + m[9] - m[1] - m[5]) * 2
        w, x, y, z = (m[4] - m[2]) / s, (m[3] + m[7]) / s, (m[6] + m[8]) / s, 0.25 * s
    end
    return x, y, z, w
end

---Eases a fall that started `t` seconds ago: it tips slowly at first and then fast, as a thing
---falling over does, and slides out and slows. Returns tip, slide (0..1 each) and whether done.
function holder.ease(t, duration)
    local u = min(1.0, max(0.0, t / duration))
    return u * u, 1.0 - (1.0 - u) * (1.0 - u), u >= 1.0
end

return holder
