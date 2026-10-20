---Every tape this client knows of, and the loop that simulates and draws the ones nearby.
---
---The server sends tapes as data (two tie points, a style, whether a post stands under each
---end, whether and where it is torn). A tape within Render.StreamDistance is BUILT: its chain
---is made (sim.lua), its holders are stood up (holders.lua), and the ground under it is sampled.
---Further away it is only data.
---
---A built tape costs nothing per frame while it sleeps: it is drawn at its rest shape with the
---wind added (render.lua). It wakes when a ped or vehicle comes near, is simulated until it has
---been still for a moment, and goes back to sleep.
local config = require 'configs.config'
local log = require 'shared.log'
local sim = require 'client.tape.sim'
local render = require 'client.tape.render'
local atlas = require 'client.tape.atlas'
local colliders = require 'client.tape.colliders'
local holders = require 'client.tape.holders'

local world = {}

local sqrt, min, max, sin, cos, floor, atan, rad, tan = math.sqrt, math.min, math.max, math.sin, math.cos, math.floor, math.atan, math.rad, math.tan

local TAPE = config.Tape
local PHYS = config.Physics
local RENDER = config.Render
local PLACE = config.Placement

---@type TapeSimParams
local P = {
    dt = 1 / 60,
    iterations = PHYS.Iterations or sim.defaults.iterations,
    damping = PHYS.Damping or sim.defaults.damping,
    freeDamping = sim.defaults.freeDamping,
    restK = PHYS.RestSpring or sim.defaults.restK,
    stiffness = PHYS.Stiffness or sim.defaults.stiffness,
    gravity = sim.defaults.gravity,
    friction = PHYS.Friction or sim.defaults.friction,
    groundFriction = sim.defaults.groundFriction,
    margin = sim.defaults.margin,
}
world.params = P

---@class Tape
---@field id integer
---@field style string
---@field a { x: number, y: number, z: number } tie point
---@field b { x: number, y: number, z: number }
---@field ap boolean a post stands under a
---@field bp boolean
---@field torn number|false where along it the tape broke (0..1)
---@field persist boolean survives a restart of the server
---@field chains table[]|nil built chains
---@field phase number random sway phase
---@field holderA string|nil key of the holder at a (holders.lua)
---@field holderB string|nil
---@field cx number centre of its bounding sphere
---@field cy number
---@field cz number
---@field radius number
---@field posts table|nil what its torn halves hang from (postsOf)
---@field seenD number this frame: how far in front of the camera, when in sight
---@field uv table|nil this frame: its style's atlas rectangles
---@field detail integer|nil this frame: the detail it is drawn at (nil: not drawn)
---@field cost integer this frame: draw calls at that detail
---@field wraps boolean this frame: whether the turns round its posts are drawn

---@type table<integer, Tape>
local tapes = {}
---@type Tape[] built tapes
local live = {}
---@type Tape[] the built tapes in sight this frame
local seen = {}

---@type table|nil the tape being aimed while placing
local preview = nil

local function sagFor(len)
    return TAPE.SagBase + TAPE.SagPerMeter * len
end

-- Holders -------------------------------------------------------------------------------------

---The holder entry at end 'a' or 'b' of a tape (nil when that end is tied to a wall, a pole...).
local function holderOf(t, which)
    return holders.get(which == 'a' and t.holderA or t.holderB)
end

---Where a tape's ends are now: its tie points, unless a holder it is tied to has gone down and
---taken that end with it.
local function endsOf(t)
    local a, b = t.a, t.b
    local ax, ay, az, bx, by, bz = a.x, a.y, a.z, b.x, b.y, b.z
    local ha, hb = holderOf(t, 'a'), holderOf(t, 'b')
    if ha then ax, ay, az = holders.endPoint(ha) end
    if hb then bx, by, bz = holders.endPoint(hb) end
    return ax, ay, az, bx, by, bz
end

---Sum of the versions of a tape's holders: changes whenever either moves.
local function holdersVersion(t)
    local ha, hb = holderOf(t, 'a'), holderOf(t, 'b')
    return (ha and ha.version or 0) + (hb and hb.version or 0) * 65536
end

---How far a tape hangs between ends `d` apart. A tape keeps its length: when a holder going down
---brings its ends closer, it hangs (and lies) slacker.
local function sagBetween(t, d)
    local s0 = sagFor(t.length)
    if d >= t.length then return s0 end
    return sqrt(s0 * s0 + 3.0 * d * (t.length - d) / 8.0)
end

-- Building ------------------------------------------------------------------------------------

local function groundAt(x, y, z)
    local found, gz = GetGroundZFor_3dCoord(x, y, z + 0.5, false)
    if found then return gz end
    found, gz = GetGroundZFor_3dCoord(x, y, z + 3.0, false)
    return found and gz or -1e9
end

local NO_GROUND = -1e8

---Fills in the ground under every node that has none yet. Collision only exists near the
---player, so a tape built at the edge of the stream distance usually has no ground to start
---with. Returns whether every node now has some.
local function fillGround(c)
    local all = true
    for i = 1, c.n do
        if c.ground[i] <= NO_GROUND then
            c.ground[i] = groundAt(c.x[i], c.y[i], c.z[i])
            if c.ground[i] <= NO_GROUND then all = false end
        end
    end
    return all
end

---How far out from a holder's axis a tape's turns round it are drawn. Two tapes tied round one
---holder would draw their turns in exactly the same place and flicker against each other: each
---tape's sit a hair further out.
local function wrapRadius(t, def)
    return def.tieRadius + 0.003 + (t.id % 4) * 0.0012
end

---What the halves of a torn tape hang from and lie on, at the holders it is tied to. A holder's
---tie point is on its axis, right for the turns drawn round it but not for a torn end, which hung
---from there inside the post and lay under its base: practically invisible. So each torn end is
---tied off at the turns, on the side the tape ran, facing out; the holder is a solid it hangs
---down the outside of; and its base, while it stands, is ground it lies on top of. Made again
---whenever a holder moves.
---@return { tieA: table|nil, tieB: table|nil, cols: table[], ncols: integer, groundAt: function }
local function postsOf(t)
    local version = holdersVersion(t)
    if t.posts and t.postsVersion == version then return t.posts end
    local out = { cols = {}, ncols = 0, groundAt = groundAt }
    local bases = {}
    local ax, ay, _, bx, by = endsOf(t)
    local function tie(e, ox, oy)
        out.ncols = out.ncols + 1
        out.cols[out.ncols] = holders.collider(e)
        local base = holders.baseTop(e)
        if base then bases[#bases + 1] = base end
        return holders.tieOff(e, ox, oy, wrapRadius(t, e.def))
    end
    local ha, hb = holderOf(t, 'a'), holderOf(t, 'b')
    if ha then out.tieA = tie(ha, bx, by) end
    if hb then out.tieB = tie(hb, ax, ay) end
    if #bases > 0 then
        out.groundAt = function(x, y, z)
            local g = groundAt(x, y, z)
            for i = 1, #bases do
                local s = bases[i]
                local dx, dy, rr = x - s[1], y - s[2], s[4] + 0.005
                if dx * dx + dy * dy < rr * rr and g < s[3] then g = s[3] end
            end
            return g
        end
    end
    t.posts, t.postsVersion = out, version
    return out
end

---Builds the two halves of a tape that is already torn, lying where they fell.
local function newTorn(t)
    local ax, ay, az, bx, by, bz = endsOf(t)
    local ties = postsOf(t)
    return sim.newTorn(ax, ay, az, bx, by, bz, TAPE.SegmentLength, sagFor(t.length), t.torn, ties.groundAt, P, ties)
end

---Builds the span of a tape that is not torn, between its ends as they are now.
local function newSpan(t)
    local ax, ay, az, bx, by, bz = endsOf(t)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local d = sqrt(dx * dx + dy * dy + dz * dz)
    local c = sim.newSpan(ax, ay, az, bx, by, bz, TAPE.SegmentLength, sagBetween(t, d), sim.nodeCount(t.length, TAPE.SegmentLength))
    local ok = fillGround(c)
    sim.rest(c)
    return c, ok
end

---Called as a tape comes within 60 m: finds the ground it was built without. A torn tape built
---without ground hangs straight down through the road, so once the ground is there its halves
---are made again, lying where they fell.
local function settleGround(t)
    if t.torn then
        local a, b = t.a, t.b
        local mid = groundAt((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5)
        if mid <= NO_GROUND or groundAt(a.x, a.y, a.z) <= NO_GROUND or groundAt(b.x, b.y, b.z) <= NO_GROUND then return false end
        local h1, h2 = newTorn(t)
        t.chains = { h1, h2 }
        return true
    end
    local all = true
    for _, c in ipairs(t.chains) do
        if not fillGround(c) then all = false end
        sim.rest(c)
    end
    return all
end

---Where the tape is, for streaming, culling and picking colliders: around its ends as they are now.
local function bounds(t)
    local ax, ay, az, bx, by, bz = endsOf(t)
    local len = t.length
    local down = (holderOf(t, 'a') and holderOf(t, 'a').fall) or (holderOf(t, 'b') and holderOf(t, 'b').fall)
    t.cx, t.cy, t.cz = (ax + bx) * 0.5, (ay + by) * 0.5, (az + bz) * 0.5 - sagFor(len) * 0.5
    -- A torn tape's halves hang and lie anywhere within half its length of the ties.
    t.radius = len * 0.5 + (t.torn and len * 0.5 or 0.0) + sagFor(len) + 0.4 + (down and 1.0 or 0.0)
    local r = (t.torn and len * 0.5 + 0.5 or 1.0) + (down and 1.0 or 0.0)
    t.minx, t.maxx = min(ax, bx) - r, max(ax, bx) + r
    t.miny, t.maxy = min(ay, by) - r, max(ay, by) + r
    t.minz, t.maxz = min(az, bz) - sagFor(len) - (t.torn and 2.5 or 1.2), max(az, bz) + 1.0
end

---A holder the tape is tied to has moved (it is going down, or getting up): the tape's ends go
---with it. A span keeps its nodes and springs towards its new shape; a torn half's tied end is
---moved to where it now leaves the holder.
local function followHolders(t)
    local version = holdersVersion(t)
    if t.holdersVersion == version then return end
    t.holdersVersion = version
    bounds(t)
    if not t.chains then return end
    if t.torn then
        local ties = postsOf(t)
        local h1, h2 = t.chains[1], t.chains[2]
        if ties.tieA and h1 then sim.tieOff(h1, 1, ties.tieA) end
        if ties.tieB and h2 then sim.tieOff(h2, h2.n, ties.tieB) end
        for _, c in ipairs(t.chains) do sim.wake(c) end
        return
    end
    local c = t.chains[1]
    local ax, ay, az, bx, by, bz = endsOf(t)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local d = sqrt(dx * dx + dy * dy + dz * dz)
    local nodes = sim.nodeCount(t.length, TAPE.SegmentLength)
    if not sim.retarget(c, ax, ay, az, bx, by, bz, TAPE.SegmentLength, sagBetween(t, d), nodes) then
        t.chains = { (newSpan(t)) }
        c = t.chains[1]
    end
    sim.reground(c, groundAt, 0.1)
    sim.wake(c)
end

local function build(t)
    local a, b = t.a, t.b
    t.phase = math.random() * 6.283
    local hdg = atan(b.y - a.y, b.x - a.x) - math.pi * 0.5
    t.holderA = t.ap and holders.take(a.x, a.y, a.z, hdg, t.ah, t.af, t.id, 'a') or nil
    t.holderB = t.bp and holders.take(b.x, b.y, b.z, hdg, t.bh, t.bf, t.id, 'b') or nil
    t.holdersVersion = holdersVersion(t)
    bounds(t)
    if t.torn then
        local h1, h2 = newTorn(t)
        t.chains = { h1, h2 }
    else
        local c, ok = newSpan(t)
        t.chains = { c }
        t.groundOk = ok
    end
    live[#live + 1] = t
end

local function unbuild(t)
    if not t.chains then return end
    t.chains = nil
    holders.drop(t.holderA, t.id)
    holders.drop(t.holderB, t.id)
    t.holderA, t.holderB = nil, nil
    t.posts = nil
    for i = #live, 1, -1 do
        if live[i] == t then table.remove(live, i) end
    end
end

---A holder's fall as the server sends it: { x, y, s } or nothing.
local function decodeFall(f)
    if type(f) ~= 'table' then return nil end
    local x, y = tonumber(f.x), tonumber(f.y)
    if not x or not y then return nil end
    local l = sqrt(x * x + y * y)
    if l < 1e-3 then return nil end
    return { x = x / l, y = y / l, s = min(3.0, max(0.0, tonumber(f.s) or 0.0)) }
end

local function decode(data)
    local t = {
        id = data.id,
        style = data.style,
        a = { x = data.a.x or data.a[1], y = data.a.y or data.a[2], z = data.a.z or data.a[3] },
        b = { x = data.b.x or data.b[1], y = data.b.y or data.b[2], z = data.b.z or data.b[3] },
        ap = data.ap == true,
        bp = data.bp == true,
        ah = data.ah or (data.ap == true and 'post' or nil),
        bh = data.bh or (data.bp == true and 'post' or nil),
        af = decodeFall(data.af),
        bf = decodeFall(data.bf),
        torn = type(data.torn) == 'number' and data.torn or false,
        persist = data.persist ~= false, -- survives a restart of the server
        owner = data.owner,
    }
    local dx, dy, dz = t.b.x - t.a.x, t.b.y - t.a.y, t.b.z - t.a.z
    t.length = sqrt(dx * dx + dy * dy + dz * dz)
    return t
end

-- Public: what the server says ----------------------------------------------------------------

---Adds (or replaces) a tape.
function world.add(data)
    local t = decode(data)
    world.remove(t.id)
    bounds(t)
    tapes[t.id] = t
    local me = GetEntityCoords(PlayerPedId())
    local dx, dy = me.x - t.cx, me.y - t.cy
    if sqrt(dx * dx + dy * dy) < RENDER.StreamDistance then build(t) end
end

function world.remove(id)
    local t = tapes[id]
    if not t then return end
    unbuild(t)
    tapes[id] = nil
end

function world.clear()
    for id in pairs(tapes) do world.remove(id) end
end

---Replaces the whole set (on joining, and after a restart of the resource).
function world.load(list)
    world.clear()
    for i = 1, #list do world.add(list[i]) end
end

function world.restyle(id, style)
    local t = tapes[id]
    if t then t.style = style end
end

function world.setPersist(id, on)
    local t = tapes[id]
    if t then t.persist = on == true end
end

---Tears a tape at fraction `frac` of its length. Its chain splits where it is, keeping how it
---was moving, so it flies apart the way it was hit.
function world.tear(id, frac)
    local t = tapes[id]
    if not t or t.torn then return end
    t.torn = frac
    bounds(t)
    if t.chains and #t.chains == 1 then
        local c = t.chains[1]
        local k = max(2, min(c.n - 1, floor(frac * (c.n - 1) + 1.5)))
        local h1, h2 = sim.split(c, k)
        local ties = postsOf(t)
        if ties.tieA then sim.tieOff(h1, 1, ties.tieA) end
        if ties.tieB then sim.tieOff(h2, h2.n, ties.tieB) end
        -- Torn right in front of someone: the ground under them is loaded now if ever. Measured
        -- where each node is now (a vehicle may have dragged it), and again as it falls (simulate).
        sim.reground(h1, ties.groundAt, 0.0)
        sim.reground(h2, ties.groundAt, 0.0)
        t.chains = { h1, h2 }
        t.groundOk = true
    end
end

---Every tape end tied to a holder at the tie point (x, y, z), each as (tape, 'a' | 'b').
local function endsAt(x, y, z)
    local out = {}
    for _, t in pairs(tapes) do
        for _, which in ipairs({ 'a', 'b' }) do
            local p = t[which]
            if t[which .. 'p'] and math.abs(p.x - x) < 0.03 and math.abs(p.y - y) < 0.03 and math.abs(p.z - z) < 0.03 then
                out[#out + 1] = { t, which }
            end
        end
    end
    return out
end

---A holder at the tie point (x, y, z) goes down: `fall` = { x, y, s } (direction, slide). Every
---tape tied to it remembers, so it is built lying if it comes into view later.
function world.knock(x, y, z, fall)
    fall = decodeFall(fall)
    if not fall then return end
    for _, te in ipairs(endsAt(x, y, z)) do te[1][te[2] .. 'f'] = fall end
    holders.knock(holders.key(x, y, z), fall)
end

---A knocked-over holder at the tie point (x, y, z) is stood back up.
function world.standUp(x, y, z)
    for _, te in ipairs(endsAt(x, y, z)) do te[1][te[2] .. 'f'] = nil end
    holders.standUp(holders.key(x, y, z))
end

---A standing holder near (x, y, z), to tie another tape to: its entry, or nil.
function world.holderAt(x, y, z, radius)
    return holders.at(x, y, z, radius)
end

---Whether an entity is one of the holders tape is tied to.
function world.isPost(ent)
    return holders.isHolder(ent)
end

---The nearest knocked-over holder in front of a player (see holders.fallenNear).
function world.fallenNear(x, y, z, fx, fy, reach)
    return holders.fallenNear(x, y, z, fx, fy, reach)
end

function world.get(id)
    return tapes[id]
end

---Counts for the debug command.
function world.stats()
    local total, awake, postCount = 0, 0, 0
    for _ in pairs(tapes) do total = total + 1 end
    for _, t in ipairs(live) do
        for _, c in ipairs(t.chains or {}) do
            if c.awake then awake = awake + 1 end
        end
    end
    for _, e in pairs(holders.all()) do
        if e.obj then postCount = postCount + 1 end
    end
    -- How far the nearest tape is pushed off its rest shape, and how stretched it is.
    local me = GetEntityCoords(PlayerPedId())
    local nearest, nd = nil, math.huge
    for _, t in ipairs(live) do
        local d = #(me - vector3(t.cx, t.cy, t.cz))
        if d < nd then nearest, nd = t, d end
    end
    local push, strain = 0.0, 1.0
    if nearest and nearest.chains then
        for _, c in ipairs(nearest.chains) do
            strain = math.max(strain, c.strain or 1.0)
            if c.rx then
                for i = 1, c.n do
                    local dx, dy, dz = c.x[i] - c.rx[i], c.y[i] - c.ry[i], c.z[i] - c.rz[i]
                    push = math.max(push, sqrt(dx * dx + dy * dy + dz * dz))
                end
            end
        end
    end
    local rs = world.resist
    local resisting = rs and GetGameTimer() < rs.untilT and rs.r or 0.0
    return {
        total = total, built = #live, awakeChains = awake, posts = postCount, colliders = colliders.count, preview = preview ~= nil,
        push = push, strain = strain, resist = resisting, seen = #seen, drawn = world.drawn or 0,
    }
end

function world.all()
    return tapes
end

-- Preview -------------------------------------------------------------------------------------

---Shows (or with nil, hides) the tape being aimed while placing.
---@param p { style: string, a: vector3, b: vector3, ok: boolean }|nil
function world.setPreview(p)
    if not p then
        preview = nil
        return
    end
    local a, b = p.a, p.b
    local len = #(b - a)
    local sag = sagFor(len)
    if preview and preview.chain and sim.retarget(preview.chain, a.x, a.y, a.z, b.x, b.y, b.z, TAPE.SegmentLength, sag) then
        preview.style, preview.ok = p.style, p.ok
    else
        local c = sim.newSpan(a.x, a.y, a.z, b.x, b.y, b.z, TAPE.SegmentLength, sag)
        if preview and preview.chain then
            -- Keep the wobble going across a change of node count.
            for i = 2, c.n - 1 do
                local j = max(2, min(preview.chain.n - 1, floor((i - 1) / (c.n - 1) * (preview.chain.n - 1) + 1.5)))
                c.x[i], c.y[i], c.z[i] = preview.chain.x[j], preview.chain.y[j], preview.chain.z[j]
                c.px[i], c.py[i], c.pz[i] = preview.chain.px[j], preview.chain.py[j], preview.chain.pz[j]
            end
        end
        sim.wake(c)
        preview = { chain = c, style = p.style, ok = p.ok, phase = 1.0 }
    end
end

-- Picking -------------------------------------------------------------------------------------

---Closest distance between the ray segment O + D*t (t in 0..L) and segment AB.
local function raySegment(ox, oy, oz, dx, dy, dz, L, ax, ay, az, bx, by, bz)
    local ex, ey, ez = bx - ax, by - ay, bz - az
    local wx, wy, wz = ox - ax, oy - ay, oz - az
    local a = L * L
    local b = (dx * ex + dy * ey + dz * ez) * L
    local c = ex * ex + ey * ey + ez * ez
    local d = (dx * wx + dy * wy + dz * wz) * L
    local e = ex * wx + ey * wy + ez * wz
    local den = a * c - b * b
    local s, t
    if den < 1e-9 then s, t = 0.0, (c > 1e-9 and e / c or 0.0) else
        s = (b * e - c * d) / den
        t = (a * e - b * d) / den
    end
    s = min(1.0, max(0.0, s))
    t = min(1.0, max(0.0, t))
    local px, py, pz = ox + dx * L * s, oy + dy * L * s, oz + dz * L * s
    local qx, qy, qz = ax + ex * t, ay + ey * t, az + ez * t
    local mx, my, mz = px - qx, py - qy, pz - qz
    return sqrt(mx * mx + my * my + mz * mz), s * L
end

---The tape the camera is pointing at, if any within `reach` metres.
---@return Tape|nil, number|nil distance along the ray
function world.pick(origin, dir, reach, tolerance)
    local best, bestAlong
    tolerance = tolerance or 0.2
    for _, t in ipairs(live) do
        local vx, vy, vz = t.cx - origin.x, t.cy - origin.y, t.cz - origin.z
        local along = vx * dir.x + vy * dir.y + vz * dir.z
        local px, py, pz = vx - dir.x * along, vy - dir.y * along, vz - dir.z * along
        if px * px + py * py + pz * pz < (t.radius + 0.5) ^ 2 and along > -t.radius and along < reach + t.radius then
            for _, c in ipairs(t.chains) do
                for i = 1, c.n - 1 do
                    local d, s = raySegment(origin.x, origin.y, origin.z, dir.x, dir.y, dir.z, reach,
                        c.x[i], c.y[i], c.z[i], c.x[i + 1], c.y[i + 1], c.z[i + 1])
                    if d < tolerance and (not bestAlong or s < bestAlong) then best, bestAlong = t, s end
                end
            end
        end
    end
    return best, bestAlong
end

-- Per frame -----------------------------------------------------------------------------------

local frame = render.frame
frame.txd, frame.txn = atlas.TXD, atlas.TXN
frame.halfWidth = TAPE.Width * 0.5
frame.repeatLen = TAPE.Repeat
frame.shading = RENDER.Shading ~= false
frame.mirror = RENDER.MirrorBack ~= false

local function setupFrame()
    local cam = GetFinalRenderedCamCoord()
    frame.cx, frame.cy, frame.cz = cam.x, cam.y, cam.z
    local fov = GetFinalRenderedCamFov()
    local _, h = GetActiveScreenResolution()
    frame.lodK = (1024 / TAPE.Repeat) * 2.0 * tan(rad(fov) * 0.5) / max(h, 480)
    frame.time = GetGameTimer() / 1000.0

    local ped = PlayerPedId()
    local inside = GetInteriorFromEntity(ped) ~= 0

    if config.Wind.Enabled and not inside then
        local dir = GetWindDirection()
        local l = sqrt(dir.x * dir.x + dir.y * dir.y)
        if l > 1e-4 then frame.windX, frame.windY = dir.x / l, dir.y / l else frame.windX, frame.windY = 0.0, 1.0 end
        -- Never quite still outdoors: even "no wind" moves a ribbon a little.
        frame.windSpeed = max(0.9, GetWindSpeed()) * (config.Wind.Strength or 1.0)
        frame.flutter = min(0.9, frame.windSpeed * 0.07) * (config.Wind.Flutter or 1.0)
    else
        frame.windX, frame.windY, frame.windSpeed, frame.flutter = 0.0, 1.0, 0.0, 0.0
    end

    local hour = GetClockHours() + GetClockMinutes() / 60.0
    local elevation = sin((hour - 6.0) / 12.0 * math.pi)
    if inside then
        frame.light = RENDER.InteriorBrightness or 0.8
        frame.lx, frame.ly, frame.lz = 0.0, 0.0, 1.0
    else
        local day = min(1.0, max(0.0, elevation * 2.5 + 0.15))
        frame.light = RENDER.NightBrightness + (1.0 - RENDER.NightBrightness) * day
        if GetRainLevel() > 0.1 then frame.light = frame.light * 0.86 end
        local az = (hour / 24.0) * 2.0 * math.pi
        local el = max(0.25, elevation)
        local ce = cos(el)
        frame.lx, frame.ly, frame.lz = cos(az) * ce, sin(az) * ce, sin(el)
    end
end

---Colliders whose box meets a tape's box, into a reused list.
local near = {}
local function gather(t)
    local list, n = colliders.list, 0
    for i = 1, colliders.count do
        local c = list[i]
        if c.maxx > t.minx and c.minx < t.maxx and c.maxy > t.miny and c.miny < t.maxy and c.maxz > t.minz and c.minz < t.maxz then
            n = n + 1
            near[n] = c
        end
    end
    for i = n + 1, #near do near[i] = nil end
    return near, n
end

local tearCfg = config.Tear
local PEOPLE_PUSH = tearCfg.PeoplePush or 1.0
local VEHICLE_PUSH = tearCfg.VehiclePush or 1.8

---Tears a tape here at once and tells the server, which checks it and tells everyone else.
local function snap(t, c, node, net, byPed)
    if t.torn or (t.tearSent and GetGameTimer() - t.tearSent < 2000) then return end
    t.tearSent = GetGameTimer()
    local frac = (c.s[node] - c.s[1]) / max(0.01, c.s[c.n] - c.s[1])
    TriggerServerEvent('sd-policetape:server:tear', t.id, frac, net or 0, byPed == true)
    world.tear(t.id, frac)
end

---A vehicle is pushing a tape: it tears when the vehicle is fast, or has dragged it too far.
local function onVehicle(t, c, veh, node)
    local pushed = veh.depth or 0.0
    if not tearCfg.Enabled or t.torn or c.kind ~= 'span' then
        -- Unbreakable tape still cannot stretch for ever: past the limit it lets the vehicle by.
        if c.strain > tearCfg.Stretch or pushed > VEHICLE_PUSH then c.slip, c.slipAll = 1.0, true end
        return
    end
    if veh.speed * 3.6 < tearCfg.SpeedKmh and c.strain < tearCfg.Stretch and pushed < VEHICLE_PUSH then return end

    local ent = veh.entity
    if NetworkGetEntityOwner(ent) == PlayerId() then
        snap(t, c, veh.node or node, NetworkGetEntityIsNetworked(ent) and VehToNet(ent) or 0, false)
    elseif c.strain > tearCfg.Stretch * 1.25 or pushed > VEHICLE_PUSH * 1.5 then
        -- The vehicle's owner has not torn it (lag, or out of their range): do not stretch for ever.
        c.slip, c.slipAll = 0.8, true
    end
end

---How hard this player's own ped is pushing into tape: the deepest push of the last moment.
---Held for a short while, because physics does not step on every frame and the slowing must.
local resist = { r = 0.0, depth = 0.0, dx = 0.0, dy = 0.0, hold = false, untilT = 0 }
world.resist = resist

---People touching a tape. This client decides only for its own ped: it is held back the further
---it pushes, and the tape snaps when pushed past Tear.PeoplePush (with Tear.Enabled off it slips
---off them and springs back instead; with Tear.People off it stops them there). Passers-by
---neither respect tape nor get to break it: it slides off them.
local function onPeople(t, c)
    -- (read each time: an admin can switch tearing on and off while the server runs)
    local PEOPLE_BREAK = tearCfg.Enabled and tearCfg.People ~= false
    local PEOPLE_HOLD = tearCfg.People == false
    for k = 1, c.ntouched do
        local col = c.touched[k]
        if col.kind == 1 then
            local depth = col.depth or 0.0
            if col.mine then
                if depth >= PEOPLE_PUSH and PEOPLE_BREAK then
                    snap(t, c, col.node, 0, true)
                    return
                end
                if depth >= PEOPLE_PUSH and not PEOPLE_HOLD then
                    c.slip, c.slipAll = 0.7, false
                    return
                end
                local r = min(1.0, max(0.0, (depth - 0.12) / (PEOPLE_PUSH - 0.12)))
                if r >= resist.r or GetGameTimer() > resist.untilT then
                    local i = col.node
                    local dx, dy = c.x[i] - c.rx[i], c.y[i] - c.ry[i]
                    local l = sqrt(dx * dx + dy * dy)
                    if l > 1e-4 then
                        resist.r, resist.depth, resist.dx, resist.dy = r, depth, dx / l, dy / l
                        resist.hold = PEOPLE_HOLD
                        resist.untilT = GetGameTimer() + 150
                    end
                end
            elseif (not col.player and depth >= PEOPLE_PUSH) or depth >= PEOPLE_PUSH * 1.5 then
                -- (another player's own client tears it; this is only if that never arrives)
                c.slip, c.slipAll = 0.7, false
            end
        end
    end
end

local resisting = false

---Slows this player down while they push into tape, and with unbreakable tape holds them at
---the limit. Called once a frame, after the physics.
local function applyResistance()
    local ped = PlayerPedId()
    if PHYS.Resistance ~= false and GetGameTimer() < resist.untilT and resist.r > 0.0 then
        local v = GetEntityVelocity(ped)
        if v.x * resist.dx + v.y * resist.dy > 0.05 then
            -- The move blend ratio is what actually slows a walking ped (1 is a walk, 0 is
            -- standing): the animation rate alone took 1.63 m/s only down to 1.13 in game.
            local mbr = max(0.12, 1.0 - 0.88 * resist.r)
            if resist.hold and resist.depth >= PEOPLE_PUSH then mbr = 0.0 end
            SetPedMaxMoveBlendRatio(ped, mbr)
            SetPedMoveRateOverride(ped, max(0.6, 1.0 - 0.4 * resist.r))
            DisableControlAction(0, 21, true) -- no sprinting through tape
            DisableControlAction(0, 22, true) -- nor jumping it
            resisting = true
        end
        if resist.hold and resist.depth > PEOPLE_PUSH then
            local back = min(0.05, resist.depth - PEOPLE_PUSH)
            local p = GetEntityCoords(ped)
            SetEntityCoordsNoOffset(ped, p.x - resist.dx * back, p.y - resist.dy * back, p.z, false, false, false)
        end
    elseif resisting then
        SetPedMoveRateOverride(ped, 1.0)
        resisting = false
    end
end

local function simulate(t, dt, ncols, cols)
    -- A torn tape's holders are solid to its halves (postsOf). Only peds and vehicles wake it.
    local nall = ncols
    local ties = t.torn and t.chains and postsOf(t)
    if ties then
        for k = 1, ties.ncols do cols[ncols + k] = ties.cols[k] end
        nall = ncols + ties.ncols
    end
    local ground = ties and ties.groundAt or groundAt
    for _, c in ipairs(t.chains) do
        if ncols > 0 then sim.wake(c) end
        if c.awake then
            -- A torn half lies on the ground where it lands, not the ground under where it hung.
            if c.kind == 'free' then sim.reground(c, ground, 0.1) end
            c.acc = c.acc + min(dt, 0.1)
            local steps = 0
            while c.acc >= P.dt and steps < 3 do
                c.acc = c.acc - P.dt
                steps = steps + 1
                local slipping = c.slip > 0.0
                local veh, node = sim.step(c, P, cols, (slipping and c.slipAll) and 0 or nall, slipping)
                if t.id and c.kind == 'span' then
                    if veh then onVehicle(t, c, veh, node) end
                    if not t.torn and c.ntouched > 0 then onPeople(t, c) end
                end
                -- Torn just now: this chain has been replaced by its two halves.
                if t.chains and t.chains[1] ~= c and t.chains[2] ~= c then break end
            end
            if c.acc > P.dt * 3 then c.acc = 0.0 end
            if c.slip > 0.0 then c.slip = c.slip - dt end

            if ncols == 0 and (c.moved or 1) < 0.0006 then
                c.quiet = c.quiet + dt
                if c.quiet > 0.8 then
                    c.awake = false
                    sim.rest(c)
                end
            else
                c.quiet = 0.0
            end
        end
    end
end

---The turns of tape round the holders it is tied to, wherever they are (standing or down).
local function drawPosts(t, uv)
    local ax, ay, _, bx, by = endsOf(t)
    for _, which in ipairs({ 'a', 'b' }) do
        local e = holderOf(t, which)
        if e then
            local x, y, z = holders.endPoint(e)
            local ox, oy = which == 'a' and bx or ax, which == 'a' and by or ay
            local ux, uy, uz = holders.axis(e)
            render.wrap(x, y, z, wrapRadius(t, e.def), atan(oy - y, ox - x), uv, 255, ux, uy, uz)
        end
    end
end

local function nearer(a, b) return a.seenD < b.seenD end

---The detail a tape is drawn at this far away, room allowing: every node close up, every other
---one further out, seam to seam (render.TILE) far away.
local function detailFor(d)
    if d < 20.0 then return 1 end
    if d < 45.0 then return 2 end
    return render.TILE
end

local function costOf(t, detail)
    local n = 0
    for _, c in ipairs(t.chains) do n = n + render.cost(c, detail) end
    return n
end

local function holderCount(t)
    return (holderOf(t, 'a') and 1 or 0) + (holderOf(t, 'b') and 1 or 0)
end

---Draws the tape being placed and every tape in sight in at most Render.MaxTriangles draw calls
---between them (render.lua says why there must be a limit). The tape being placed comes first.
---Then every tape in sight at its cheapest, nearest first, so a crowded scene loses its furthest
---tapes instead of crashing the game. Whatever room is left goes to the nearest tapes, each in
---turn drawn finer and then given the turns round its posts.
local function draw()
    local budget = RENDER.MaxTriangles or 600
    frame.left = budget

    local p = preview
    if p and p.chain then
        local _, uv = atlas.acquire(p.style)
        if uv then
            local detail = render.cost(p.chain, 1) <= frame.left and 1 or render.TILE
            render.chain(p.chain, uv, p.phase, p.ok and 215 or 120, detail)
        end
    end

    table.sort(seen, nearer)
    local room = frame.left
    for k = 1, #seen do
        local t = seen[k]
        t.detail, t.wraps = nil, false
        local _, uv = atlas.acquire(t.style)
        if uv then
            local cost = costOf(t, render.TILE)
            if cost <= room then
                room = room - cost
                t.uv, t.detail, t.cost = uv, render.TILE, cost
            end
        end
    end
    for k = 1, #seen do
        local t = seen[k]
        local want = detailFor(t.seenD)
        if t.detail and want ~= render.TILE then
            for detail = want, 2 do
                local cost = costOf(t, detail)
                if cost - t.cost <= room then
                    room = room - (cost - t.cost)
                    t.detail, t.cost = detail, cost
                    break
                end
            end
        end
        if t.detail and t.seenD < 40.0 then
            local cost = render.wrapCost(t.seenD) * holderCount(t)
            if cost <= room then
                room = room - cost
                t.wraps = true
            end
        end
    end

    for k = 1, #seen do
        local t = seen[k]
        if t.detail then
            for _, c in ipairs(t.chains) do render.chain(c, t.uv, t.phase, 255, t.detail) end
        end
    end
    for k = 1, #seen do
        local t = seen[k]
        if t.wraps then drawPosts(t, t.uv) end
    end
    world.drawn = budget - frame.left
end

---Knocks over what this client's ped or vehicles ran into: at once here, and tells the server,
---which checks it and has everyone else's go down the same way.
local function knockOver(ped, now)
    local list = holders.detect(ped, now)
    if not list then return end
    for _, k in ipairs(list) do
        local e = k.entry
        local tapeId, which = next(e.ties)
        if tapeId then
            world.knock(e.x, e.y, e.z, { x = k.x, y = k.y, s = k.s })
            TriggerServerEvent('sd-policetape:server:knock', tapeId, which, k.x, k.y, k.s, k.net, k.byPed)
        end
    end
end

-- Streaming and the collider scan, a few times a second.
CreateThread(function()
    local spheres = {}
    local tidy = 0
    while true do
        local me = GetEntityCoords(PlayerPedId())
        local stream, drop = RENDER.StreamDistance, RENDER.StreamDistance + 25.0
        for _, t in pairs(tapes) do
            local dx, dy = me.x - t.cx, me.y - t.cy
            local d = sqrt(dx * dx + dy * dy)
            if not t.chains and d < stream then
                build(t)
            elseif t.chains and d > drop then
                unbuild(t)
            elseif t.chains and not t.groundOk and d < 60.0 then
                t.groundOk = settleGround(t)
            end
        end

        local n = 0
        if PHYS.Enabled then
            for _, t in ipairs(live) do
                local dx, dy, dz = me.x - t.cx, me.y - t.cy, me.z - t.cz
                if dx * dx + dy * dy + dz * dz < (PHYS.SimDistance + t.radius) ^ 2 then
                    n = n + 1
                    local s = spheres[n] or {}
                    s.x, s.y, s.z, s.r = t.cx, t.cy, t.cz, t.radius
                    spheres[n] = s
                end
            end
            if preview and preview.chain then
                local c = preview.chain
                local m = floor(c.n / 2)
                n = n + 1
                local s = spheres[n] or {}
                s.x, s.y, s.z, s.r = c.x[m], c.y[m], c.z[m], c.restLength * 0.5 + 1.0
                spheres[n] = s
            end
        end
        colliders.scan(spheres, n)

        tidy = tidy + 1
        if tidy % 40 == 0 then colliders.tidy() end
        Wait(300)
    end
end)

-- Simulate and draw, every frame there is anything to.
CreateThread(function()
    while true do
        if #live == 0 and not preview then
            Wait(400)
        else
            local dt = GetFrameTime()
            setupFrame()
            if PHYS.Enabled then colliders.update() end

            local ped = PlayerPedId()
            local me = GetEntityCoords(ped)
            holders.update()
            knockOver(ped, GetGameTimer())
            if PHYS.Enabled then holders.passVehicles(me.x, me.y) end

            local drawSq = RENDER.DrawDistance
            local nseen = 0
            for i = #live, 1, -1 do
                local t = live[i]
                if t and t.chains then
                    followHolders(t)
                    if PHYS.Enabled then
                        local dx, dy, dz = me.x - t.cx, me.y - t.cy, me.z - t.cz
                        if dx * dx + dy * dy + dz * dz < (PHYS.SimDistance + t.radius) ^ 2 then
                            local cols, ncols = gather(t)
                            simulate(t, dt, ncols, cols)
                        end
                    end

                    local vx, vy, vz = frame.cx - t.cx, frame.cy - t.cy, frame.cz - t.cz
                    local d = sqrt(vx * vx + vy * vy + vz * vz) - t.radius
                    if d < drawSq and IsSphereVisible(t.cx, t.cy, t.cz, t.radius) then
                        nseen = nseen + 1
                        seen[nseen] = t
                        t.seenD = d
                    end
                end
            end
            for i = nseen + 1, #seen do seen[i] = nil end

            if PHYS.Enabled then applyResistance() end

            local p = preview
            if p and p.chain then
                local c = p.chain
                if PHYS.Enabled then
                    local fake = { minx = math.huge, maxx = -math.huge, miny = math.huge, maxy = -math.huge, minz = math.huge, maxz = -math.huge }
                    for i = 1, c.n do
                        fake.minx, fake.maxx = min(fake.minx, c.x[i] - 0.5), max(fake.maxx, c.x[i] + 0.5)
                        fake.miny, fake.maxy = min(fake.miny, c.y[i] - 0.5), max(fake.maxy, c.y[i] + 0.5)
                        fake.minz, fake.maxz = min(fake.minz, c.z[i] - 0.5), max(fake.maxz, c.z[i] + 0.5)
                    end
                    local cols, ncols = gather(fake)
                    fake.chains = { c }
                    simulate(fake, dt, ncols, cols)
                end
            end

            draw()
            Wait(0)
        end
    end
end)


return world
