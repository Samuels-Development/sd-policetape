---Tape physics. Pure Lua: no natives, so tests/sim_harness.lua runs it under stock Lua 5.4.
---
---A tape is a chain of nodes integrated with Verlet and held together by distance constraints
---(position-based dynamics). Two kinds of chain:
---
---  span  both ends tied. Its rest shape (a shallow parabola with the configured sag) is known
---        exactly, and every node carries a soft spring back to its rest position. The springs
---        are what make a span come back to the same shape every time; the distance constraints
---        are what make a push spread along the tape into a taut V instead of a dent.
---  free  one end tied, one end loose: the two halves of a torn tape. Gravity, ground and
---        nothing else.
---
---Constraints only resist stretching. Real tape cannot push: compress it and it buckles, which
---is what the spring-to-rest already looks like.
---
---Colliders come in two shapes, built each frame by client/tape/colliders.lua:
---  capsule  one limb or the torso of a ped (bone to bone, with a radius)
---  vehicle  a vehicle's real shape as a height field of its top and bottom in model space
---and one that never moves (sim.staticCapsule): the post a torn half hangs from.
---
---Arrays are 1-based and parallel (x[i], y[i], z[i]) and nothing is allocated per step, because
---a busy scene steps a few thousand nodes a frame.
local sim = {}

local sqrt, floor, min, max = math.sqrt, math.floor, math.min, math.max

---@class TapeSimParams
---@field dt number fixed step, seconds
---@field iterations integer constraint passes per step
---@field damping number velocity kept per step (span)
---@field freeDamping number velocity kept per step (free chain)
---@field restK number spring back to rest shape, 1/s^2
---@field stiffness number 0..1 stretch correction per pass
---@field gravity number m/s^2 for free chains
---@field friction number 0..1 tangential velocity lost on contact
---@field groundFriction number 0..1 horizontal velocity lost on the ground
---@field margin number gap kept between tape and a collider, metres
sim.defaults = {
    dt = 1 / 60,
    iterations = 8,
    damping = 0.965,
    freeDamping = 0.975,
    restK = 22.0,
    stiffness = 0.85,
    gravity = 7.0,
    friction = 0.55,
    groundFriction = 0.6,
    margin = 0.012,
}

---Number of nodes for a length of tape.
---@param length number metres
---@param segLen number metres per segment
---@return integer
function sim.nodeCount(length, segLen)
    return max(5, min(64, floor(length / segLen + 0.5) + 1))
end

---Allocates the arrays every chain has.
---@param n integer
---@return table
local function alloc(n)
    local c = {
        n = n,
        x = {}, y = {}, z = {},
        px = {}, py = {}, pz = {},
        pin = {},
        rl = {},
        s = {},
        cnx = {}, cny = {}, cnz = {}, cw = {},
        ground = {},
        awake = false,
        quiet = 0.0,
        slip = 0.0,
        strain = 1.0,
        acc = 0.0,
        touched = {}, -- colliders touching it in the last step (sim.step), each with .depth and .node
        ntouched = 0,
    }
    for i = 1, n do
        c.pin[i] = false
        c.cnx[i], c.cny[i], c.cnz[i], c.cw[i] = 0.0, 0.0, 1.0, 0.0
        c.ground[i] = -1e9
    end
    return c
end

---Builds a span (both ends tied) between A and B, resting in its sag.
---@param ax number @param ay number @param az number
---@param bx number @param by number @param bz number
---@param segLen number metres per segment
---@param sag number metres the middle hangs below the straight line
---@param nodes? integer how many nodes (default: by its length). A tape whose ends move (a holder
---knocked over) keeps the count it had, so it can follow them without being rebuilt.
---@return table chain
function sim.newSpan(ax, ay, az, bx, by, bz, segLen, sag, nodes)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local length = sqrt(dx * dx + dy * dy + dz * dz)
    local n = nodes or sim.nodeCount(length, segLen)
    local c = alloc(n)

    c.kind = 'span'
    c.rx, c.ry, c.rz = {}, {}, {}
    c.sag = sag

    for i = 1, n do
        local t = (i - 1) / (n - 1)
        local drop = 4.0 * sag * t * (1.0 - t)
        local x, y, z = ax + dx * t, ay + dy * t, az + dz * t - drop
        c.x[i], c.y[i], c.z[i] = x, y, z
        c.px[i], c.py[i], c.pz[i] = x, y, z
        c.rx[i], c.ry[i], c.rz[i] = x, y, z
    end

    c.pin[1], c.pin[n] = true, true

    local s = 0.0
    c.s[1] = 0.0
    for i = 1, n - 1 do
        local ex, ey, ez = c.x[i + 1] - c.x[i], c.y[i + 1] - c.y[i], c.z[i + 1] - c.z[i]
        local l = sqrt(ex * ex + ey * ey + ez * ez)
        c.rl[i] = l
        s = s + l
        c.s[i + 1] = s
    end
    c.restLength = s

    return c
end

---Moves a span's ends without rebuilding it: the rest shape follows, and the nodes spring
---towards it from wherever they were. Used for the preview while aiming, so the tape trails
---after the aim point instead of snapping. Returns false when the new length needs a different
---number of nodes (the caller then builds a new span).
---@param c table span
---@param nodes? integer as in sim.newSpan: given, the count is kept whatever the new length
---@return boolean
function sim.retarget(c, ax, ay, az, bx, by, bz, segLen, sag, nodes)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    local length = sqrt(dx * dx + dy * dy + dz * dz)
    local n = c.n
    if (nodes or sim.nodeCount(length, segLen)) ~= n then return false end

    for i = 1, n do
        local t = (i - 1) / (n - 1)
        local drop = 4.0 * sag * t * (1.0 - t)
        c.rx[i], c.ry[i], c.rz[i] = ax + dx * t, ay + dy * t, az + dz * t - drop
    end
    c.x[1], c.y[1], c.z[1] = ax, ay, az
    c.px[1], c.py[1], c.pz[1] = ax, ay, az
    c.x[n], c.y[n], c.z[n] = bx, by, bz
    c.px[n], c.py[n], c.pz[n] = bx, by, bz

    local s = 0.0
    for i = 1, n - 1 do
        local ex, ey, ez = c.rx[i + 1] - c.rx[i], c.ry[i + 1] - c.ry[i], c.rz[i + 1] - c.rz[i]
        local l = sqrt(ex * ex + ey * ey + ez * ez)
        c.rl[i] = l
        s = s + l
        c.s[i + 1] = s
    end
    c.restLength = s
    c.sag = sag
    sim.wake(c)
    return true
end

---Cuts a chain in two after node k. The halves keep their nodes' positions AND velocities,
---so a tape torn by a car flies apart the way it was moving. Material coordinates (c.s) are
---kept too, so the print does not jump.
---@param c table a span or free chain
---@param k integer last node of the first half (1 < k < n)
---@return table first half (tied at its node 1)
---@return table second half (tied at its last node)
function sim.split(c, k)
    local n = c.n
    k = max(2, min(n - 2, k))

    local function take(from, to, pinFirst)
        local m = to - from + 1
        local h = alloc(m)
        h.kind = 'free'
        for j = 1, m do
            local i = from + j - 1
            h.x[j], h.y[j], h.z[j] = c.x[i], c.y[i], c.z[i]
            h.px[j], h.py[j], h.pz[j] = c.px[i], c.py[i], c.pz[i]
            h.s[j] = c.s[i]
            h.ground[j] = c.ground[i]
            h.cnx[j], h.cny[j], h.cnz[j], h.cw[j] = c.cnx[i], c.cny[i], c.cnz[i], c.cw[i]
            if j < m then h.rl[j] = c.rl[i] end
        end
        if pinFirst then h.pin[1] = c.pin[from] else h.pin[m] = c.pin[to] end
        local rest = 0.0
        for j = 1, m - 1 do rest = rest + h.rl[j] end
        h.restLength = rest
        h.awake = true
        return h
    end

    -- The node at the tear goes with the first half and a copy of it starts the second, so
    -- neither half is a segment short.
    local h1, h2 = take(1, k, true), take(k, n, false)

    -- Stretched tape that snaps flies back towards where it is tied, the free end fastest.
    local recoil = min(9.0, max(0.0, ((c.strain or 1.0) - 1.0) * 30.0)) * (1 / 60)
    if recoil > 0.0 then
        for _, h in ipairs({ h1, h2 }) do
            local m = h.n
            for j = 1, m do
                if not h.pin[j] then
                    local towards = h.pin[1] and j - 1 or j + 1 -- the neighbour on the tied side
                    local dx, dy, dz = h.x[towards] - h.x[j], h.y[towards] - h.y[j], h.z[towards] - h.z[j]
                    local l = sqrt(dx * dx + dy * dy + dz * dz)
                    if l > 1e-5 then
                        local f = (h.pin[1] and (j - 1) or (m - j)) / (m - 1)
                        local v = recoil * f / l
                        h.px[j], h.py[j], h.pz[j] = h.px[j] - dx * v, h.py[j] - dy * v, h.pz[j] - dz * v
                    end
                end
            end
        end
    end
    return h1, h2
end

---A collider that never moves and is never let through (unlike a ped, which tape slips off):
---the holder a torn half is tied to. Same fields as a ped capsule from colliders.lua, and it may
---taper: radius `r` at A, `r1` at B (a cone's body).
---@return table
function sim.staticCapsule(ax, ay, az, bx, by, bz, r, r1)
    local rr = max(r, r1 or r)
    return {
        kind = 3, ax = ax, ay = ay, az = az, bx = bx, by = by, bz = bz, r = r, r1 = r1,
        vx = 0.0, vy = 0.0, vz = 0.0, speed = 0.0, grip = 0.0,
        minx = min(ax, bx) - rr - 0.05, maxx = max(ax, bx) + rr + 0.05,
        miny = min(ay, by) - rr - 0.05, maxy = max(ay, by) + rr + 0.05,
        minz = min(az, bz) - rr - 0.05, maxz = max(az, bz) + rr + 0.05,
    }
end

---Moves a torn half's tied node to where the tape really leaves what it is tied to, and turns
---its face to lie against it. The tie point of a post is on its axis, which is right for the
---turns drawn round it but not for the end of a torn tape: hung from there, it hangs inside.
---@param c table
---@param i integer the pinned node
---@param tie { x: number, y: number, z: number, nx: number, ny: number, nz: number } nx..nz: out of the surface
function sim.tieOff(c, i, tie)
    c.x[i], c.y[i], c.z[i] = tie.x, tie.y, tie.z
    c.px[i], c.py[i], c.pz[i] = tie.x, tie.y, tie.z
    c.cnx[i], c.cny[i], c.cnz[i], c.cw[i] = tie.nx, tie.ny, tie.nz, 1.0
end

---Marks a chain as needing simulation.
---@param c table
function sim.wake(c)
    if not c.awake then
        c.awake = true
        c.quiet = 0.0
    end
end

---Distance from point P to the segment AB, squared, and the parameter of the closest point.
local function closestOnSegment(px, py, pz, ax, ay, az, bx, by, bz)
    local abx, aby, abz = bx - ax, by - ay, bz - az
    local ll = abx * abx + aby * aby + abz * abz
    local t = 0.0
    if ll > 1e-12 then
        t = ((px - ax) * abx + (py - ay) * aby + (pz - az) * abz) / ll
        if t < 0.0 then t = 0.0 elseif t > 1.0 then t = 1.0 end
    end
    return ax + abx * t, ay + aby * t, az + abz * t, t
end

---Height of a vehicle profile's top (or bottom) at a model-space point, bilinear where the
---four cells around it are all solid, nearest cell otherwise. nil = no vehicle there.
---@param grid table<integer, number|false>
local function sampleGrid(prof, grid, lx, ly)
    local fx = (lx - prof.minx) / prof.cx - 0.5
    local fy = (ly - prof.miny) / prof.cy - 0.5
    local nx, ny = prof.nx, prof.ny
    local ix, iy = floor(fx), floor(fy)
    local tx, ty = fx - ix, fy - iy

    if ix >= 0 and iy >= 0 and ix + 1 < nx and iy + 1 < ny then
        local h00 = grid[ix + iy * nx + 1]
        local h10 = grid[ix + 1 + iy * nx + 1]
        local h01 = grid[ix + (iy + 1) * nx + 1]
        local h11 = grid[ix + 1 + (iy + 1) * nx + 1]
        if h00 and h10 and h01 and h11 then
            return (h00 * (1 - tx) + h10 * tx) * (1 - ty) + (h01 * (1 - tx) + h11 * tx) * ty
        end
    end

    local cx = floor(fx + 0.5)
    local cy = floor(fy + 0.5)
    if cx < 0 then cx = 0 elseif cx >= nx then cx = nx - 1 end
    if cy < 0 then cy = 0 elseif cy >= ny then cy = ny - 1 end
    return grid[cx + cy * nx + 1] or nil
end

---Whether a world point is inside a vehicle collider's shape (its measured height field),
---grown by `pad` metres. Used to tell when a vehicle runs into a holder.
---@param v table vehicle collider (colliders.lua, kind 2)
---@return boolean
function sim.insideVehicle(v, x, y, z, pad)
    local prof = v.prof
    local ox, oy, oz = x - v.ox, y - v.oy, z - v.oz
    local lx = ox * v.rx + oy * v.ry + oz * v.rz
    local ly = ox * v.fx + oy * v.fy + oz * v.fz
    local lz = ox * v.ux + oy * v.uy + oz * v.uz
    if lx <= prof.minx - pad or lx >= prof.maxx + pad or ly <= prof.miny - pad or ly >= prof.maxy + pad then return false end
    local cx = min(max(lx, prof.minx + 1e-3), prof.maxx - 1e-3)
    local cy = min(max(ly, prof.miny + 1e-3), prof.maxy - 1e-3)
    local top = sampleGrid(prof, prof.top, cx, cy)
    if not top or lz > top + pad then return false end
    local bottom = sampleGrid(prof, prof.bottom, cx, cy)
    return not bottom or lz > bottom - pad
end

---Whether a model-space point is inside the vehicle's volume at cell (ix, iy).
local function solidAt(prof, ix, iy, lz)
    local k = ix + iy * prof.nx + 1
    local top = prof.top[k]
    if not top or lz >= top then return false end
    local bottom = prof.bottom[k]
    return not bottom or lz > bottom
end

---Pushes one node out of a vehicle. Returns true and writes the world-space contact normal
---into the chain when it moved the node.
---@param c table chain
---@param i integer node
---@param v table vehicle collider
---@param margin number
---@return boolean
local function pushOutOfVehicle(c, i, v, margin)
    local prof = v.prof
    local ox, oy, oz = c.x[i] - v.ox, c.y[i] - v.oy, c.z[i] - v.oz
    local lx = ox * v.rx + oy * v.ry + oz * v.rz
    local ly = ox * v.fx + oy * v.fy + oz * v.fz
    local lz = ox * v.ux + oy * v.uy + oz * v.uz

    if lx <= prof.minx or lx >= prof.maxx or ly <= prof.miny or ly >= prof.maxy then return false end

    local top = sampleGrid(prof, prof.top, lx, ly)
    if not top or lz >= top + margin then return false end

    local bottom = sampleGrid(prof, prof.bottom, lx, ly)
    if bottom and lz <= bottom - margin then return false end

    local nx, ny = prof.nx, prof.ny
    local ix = floor((lx - prof.minx) / prof.cx)
    local iy = floor((ly - prof.miny) / prof.cy)
    if ix < 0 then ix = 0 elseif ix >= nx then ix = nx - 1 end
    if iy < 0 then iy = 0 elseif iy >= ny then iy = ny - 1 end

    -- Five ways out: over the top, under the bottom, or sideways to where the body ends at
    -- this height. The shortest one wins, which is what lets a tape ride up a windscreen.
    local best = top + margin - lz
    local mx, my, mz = 0.0, 0.0, best
    local nlx, nly, nlz

    -- Normal of the top surface, from the height field's slope, so the tape lies along a
    -- bonnet or windscreen rather than standing on edge.
    do
        local e = 0.12
        local hx1 = sampleGrid(prof, prof.top, lx + e, ly) or top
        local hx0 = sampleGrid(prof, prof.top, lx - e, ly) or top
        local hy1 = sampleGrid(prof, prof.top, lx, ly + e) or top
        local hy0 = sampleGrid(prof, prof.top, lx, ly - e) or top
        local gx, gy = (hx1 - hx0) / (2 * e), (hy1 - hy0) / (2 * e)
        local l = sqrt(gx * gx + gy * gy + 1)
        nlx, nly, nlz = -gx / l, -gy / l, 1 / l
    end

    if bottom then
        local d = lz - (bottom - margin)
        if d < best then best, mx, my, mz, nlx, nly, nlz = d, 0.0, 0.0, -d, 0.0, 0.0, -1.0 end
    end

    local d = prof.maxx - lx + margin
    for j = ix + 1, nx - 1 do
        if not solidAt(prof, j, iy, lz) then d = prof.minx + j * prof.cx - lx + margin break end
    end
    if d < best then best, mx, my, mz, nlx, nly, nlz = d, d, 0.0, 0.0, 1.0, 0.0, 0.0 end

    d = lx - prof.minx + margin
    for j = ix - 1, 0, -1 do
        if not solidAt(prof, j, iy, lz) then d = lx - (prof.minx + (j + 1) * prof.cx) + margin break end
    end
    if d < best then best, mx, my, mz, nlx, nly, nlz = d, -d, 0.0, 0.0, -1.0, 0.0, 0.0 end

    d = prof.maxy - ly + margin
    for j = iy + 1, ny - 1 do
        if not solidAt(prof, ix, j, lz) then d = prof.miny + j * prof.cy - ly + margin break end
    end
    if d < best then best, mx, my, mz, nlx, nly, nlz = d, 0.0, d, 0.0, 0.0, 1.0, 0.0 end

    d = ly - prof.miny + margin
    for j = iy - 1, 0, -1 do
        if not solidAt(prof, ix, j, lz) then d = ly - (prof.miny + (j + 1) * prof.cy) + margin break end
    end
    if d < best then best, mx, my, mz, nlx, nly, nlz = d, 0.0, -d, 0.0, 0.0, -1.0, 0.0 end

    c.x[i] = c.x[i] + mx * v.rx + my * v.fx + mz * v.ux
    c.y[i] = c.y[i] + mx * v.ry + my * v.fy + mz * v.uy
    c.z[i] = c.z[i] + mx * v.rz + my * v.fz + mz * v.uz

    c.cnx[i] = nlx * v.rx + nly * v.fx + nlz * v.ux
    c.cny[i] = nlx * v.ry + nly * v.fy + nlz * v.uy
    c.cnz[i] = nlx * v.rz + nly * v.fz + nlz * v.uz
    return true
end

---Pushes one node out of a capsule. Same contract as pushOutOfVehicle.
local function pushOutOfCapsule(c, i, k, margin)
    local x, y, z = c.x[i], c.y[i], c.z[i]
    local qx, qy, qz, t = closestOnSegment(x, y, z, k.ax, k.ay, k.az, k.bx, k.by, k.bz)
    local dx, dy, dz = x - qx, y - qy, z - qz
    local r = (k.r1 and k.r + (k.r1 - k.r) * t or k.r) + margin
    local dd = dx * dx + dy * dy + dz * dz
    if dd >= r * r then return false end

    local d = sqrt(dd)
    local nx, ny, nz
    if d > 1e-5 then
        nx, ny, nz = dx / d, dy / d, dz / d
    else
        -- Dead centre: leave the way the node came in.
        local vx, vy, vz = c.px[i] - x, c.py[i] - y, c.pz[i] - z
        local l = sqrt(vx * vx + vy * vy + vz * vz)
        if l > 1e-6 then nx, ny, nz = vx / l, vy / l, vz / l else nx, ny, nz = 0.0, 0.0, 1.0 end
    end

    c.x[i], c.y[i], c.z[i] = qx + nx * r, qy + ny * r, qz + nz * r
    c.cnx[i], c.cny[i], c.cnz[i] = nx, ny, nz
    return true
end

---Pushes a whole SEGMENT out of a capsule. Nodes are 25 cm apart and a leg is 16 cm across,
---so testing nodes alone lets a leg pass between two of them. This finds the closest points
---of the segment and the capsule's axis and moves both ends of the segment, each by its share.
local function pushSegmentOutOfCapsule(c, j, k, margin)
    local j1 = j + 1
    local x1, y1, z1 = c.x[j], c.y[j], c.z[j]
    local x2, y2, z2 = c.x[j1], c.y[j1], c.z[j1]

    -- Closest points between segment P(s) = P1 + s*d1 and Q(t) = A + t*d2.
    local d1x, d1y, d1z = x2 - x1, y2 - y1, z2 - z1
    local d2x, d2y, d2z = k.bx - k.ax, k.by - k.ay, k.bz - k.az
    local rx, ry, rz = x1 - k.ax, y1 - k.ay, z1 - k.az
    local a = d1x * d1x + d1y * d1y + d1z * d1z
    local e = d2x * d2x + d2y * d2y + d2z * d2z
    local f = d2x * rx + d2y * ry + d2z * rz
    local s, t
    if a < 1e-10 then return false end
    local cc = d1x * rx + d1y * ry + d1z * rz
    if e < 1e-10 then
        t = 0.0
        s = -cc / a
    else
        local b = d1x * d2x + d1y * d2y + d1z * d2z
        local denom = a * e - b * b
        if denom > 1e-10 then s = (b * f - cc * e) / denom else s = 0.0 end
        if s < 0.0 then s = 0.0 elseif s > 1.0 then s = 1.0 end
        t = (b * s + f) / e
        if t < 0.0 then
            t = 0.0
            s = -cc / a
        elseif t > 1.0 then
            t = 1.0
            s = (b - cc) / a
        end
    end
    if s < 0.0 then s = 0.0 elseif s > 1.0 then s = 1.0 end

    -- Only the inside of a segment: the nodes themselves are handled point-wise.
    if s < 0.02 or s > 0.98 then return false end

    local px, py, pz = x1 + d1x * s, y1 + d1y * s, z1 + d1z * s
    local qx, qy, qz = k.ax + d2x * t, k.ay + d2y * t, k.az + d2z * t
    local nx, ny, nz = px - qx, py - qy, pz - qz
    local r = (k.r1 and k.r + (k.r1 - k.r) * t or k.r) + margin
    local dd = nx * nx + ny * ny + nz * nz
    if dd >= r * r then return false end
    local d = sqrt(dd)
    if d > 1e-5 then
        nx, ny, nz = nx / d, ny / d, nz / d
    else
        -- The axis runs through the segment: leave sideways, the way the tape was not going.
        local ux, uy, uz = d1y * d2z - d1z * d2y, d1z * d2x - d1x * d2z, d1x * d2y - d1y * d2x
        local l = sqrt(ux * ux + uy * uy + uz * uz)
        if l < 1e-6 then return false end
        nx, ny, nz = ux / l, uy / l, uz / l
    end

    local depth = r - d
    local w1 = c.pin[j] and 0.0 or (1.0 - s)
    local w2 = c.pin[j1] and 0.0 or s
    local ws = w1 * w1 + w2 * w2
    if ws < 1e-6 then return false end
    local m1, m2 = depth * w1 / ws, depth * w2 / ws
    c.x[j], c.y[j], c.z[j] = x1 + nx * m1, y1 + ny * m1, z1 + nz * m1
    c.x[j1], c.y[j1], c.z[j1] = x2 + nx * m2, y2 + ny * m2, z2 + nz * m2
    c.cnx[j], c.cny[j], c.cnz[j] = nx, ny, nz
    c.cnx[j1], c.cny[j1], c.cnz[j1] = nx, ny, nz
    return true
end

---@type table<integer, table|false> Which collider last touched each node this step (reused).
local touchedBy = {}

---Counts steps, so a collider shared by several tapes is listed once per tape per step.
local stepMark = 0

---Advances a chain by one fixed step.
---
---`cols` is the frame's collider list and `ncols` how many of it to read; colliders whose box
---misses the chain's box should already have been filtered out by the caller. `noPeds` skips
---ped capsules (the tape is slipping off someone).
---
---Returns the fastest vehicle collider that touched the tape this step and the node it
---touched, for tearing.
---@param c table
---@param p TapeSimParams
---@param cols table[]|nil
---@param ncols integer
---@param noPeds boolean
---@return table|nil vehicle
---@return integer|nil node
function sim.step(c, p, cols, ncols, noPeds)
    local n = c.n
    local x, y, z, px, py, pz, pin = c.x, c.y, c.z, c.px, c.py, c.pz, c.pin
    local dt = p.dt
    local dt2 = dt * dt
    local span = c.kind == 'span'
    local damp = span and p.damping or p.freeDamping
    local k = p.restK
    local g = p.gravity
    local rx, ry, rz = c.rx, c.ry, c.rz
    local ground = c.ground

    -- Integrate.
    for i = 1, n do
        if not pin[i] then
            local xi, yi, zi = x[i], y[i], z[i]
            local vx, vy, vz = (xi - px[i]) * damp, (yi - py[i]) * damp, (zi - pz[i]) * damp
            local ax, ay, az
            if span then
                ax, ay, az = k * (rx[i] - xi), k * (ry[i] - yi), k * (rz[i] - zi)
            else
                ax, ay, az = 0.0, 0.0, -g
            end
            px[i], py[i], pz[i] = xi, yi, zi
            x[i], y[i], z[i] = xi + vx + ax * dt2, yi + vy + ay * dt2, zi + vz + az * dt2
        end
        touchedBy[i] = false
    end

    local rl = c.rl
    local stiff = p.stiffness
    local margin = p.margin
    local iters = p.iterations
    local hitVeh, hitNode, hitSpeed = nil, nil, -1.0

    for it = 1, iters do
        -- Stretch constraints, sweeping alternate ways so a correction travels both directions.
        local from, to, step = 1, n - 1, 1
        if it % 2 == 0 then from, to, step = n - 1, 1, -1 end
        for j = from, to, step do
            local j1 = j + 1
            local dx, dy, dz = x[j1] - x[j], y[j1] - y[j], z[j1] - z[j]
            local dd = dx * dx + dy * dy + dz * dz
            local L = rl[j]
            if dd > L * L then
                local d = sqrt(dd)
                local w1 = pin[j] and 0.0 or 1.0
                local w2 = pin[j1] and 0.0 or 1.0
                local ws = w1 + w2
                if ws > 0.0 then
                    local corr = (d - L) / d * stiff / ws
                    if w1 > 0.0 then
                        x[j], y[j], z[j] = x[j] + dx * corr, y[j] + dy * corr, z[j] + dz * corr
                    end
                    if w2 > 0.0 then
                        x[j1], y[j1], z[j1] = x[j1] - dx * corr, y[j1] - dy * corr, z[j1] - dz * corr
                    end
                end
            end
        end

        -- Collisions inside the loop, so the constraints and the bodies agree by the end.
        if ncols > 0 then
            for i = 1, n do
                if not pin[i] then
                    local xi, yi, zi = x[i], y[i], z[i]
                    for ci = 1, ncols do
                        local col = cols[ci]
                        if xi > col.minx and xi < col.maxx and yi > col.miny and yi < col.maxy
                            and zi > col.minz and zi < col.maxz then
                            local hit
                            if col.kind == 1 then
                                if not noPeds then hit = pushOutOfCapsule(c, i, col, margin) end
                            elseif col.kind == 3 then
                                hit = pushOutOfCapsule(c, i, col, margin)
                            elseif not (not span and zi < ground[i] + 0.08) then
                                -- (a torn half lying on the road is driven over, not shoved)
                                hit = pushOutOfVehicle(c, i, col, margin)
                            end
                            if hit then
                                touchedBy[i] = col
                                xi, yi, zi = x[i], y[i], z[i]
                                if col.kind == 2 and col.speed > hitSpeed then
                                    hitVeh, hitNode, hitSpeed = col, i, col.speed
                                end
                            end
                        end
                    end
                end
            end

            -- Ped capsules only when the tape is not slipping off them; posts always.
            local capsule = noPeds and 3 or 1
            if not noPeds or not span then
                for j = 1, n - 1 do
                    local j1 = j + 1
                    -- Box of the segment against the box of each capsule.
                    local sx0, sx1 = x[j], x[j1]
                    if sx0 > sx1 then sx0, sx1 = sx1, sx0 end
                    local sy0, sy1 = y[j], y[j1]
                    if sy0 > sy1 then sy0, sy1 = sy1, sy0 end
                    local sz0, sz1 = z[j], z[j1]
                    if sz0 > sz1 then sz0, sz1 = sz1, sz0 end
                    for ci = 1, ncols do
                        local col = cols[ci]
                        local kind = col.kind
                        if (kind == 3 or kind == capsule) and sx1 > col.minx and sx0 < col.maxx and sy1 > col.miny
                            and sy0 < col.maxy and sz1 > col.minz and sz0 < col.maxz then
                            if pushSegmentOutOfCapsule(c, j, col, margin) then
                                if not pin[j] then touchedBy[j] = col end
                                if not pin[j1] then touchedBy[j1] = col end
                                sx0, sx1 = min(x[j], x[j1]), max(x[j], x[j1])
                                sy0, sy1 = min(y[j], y[j1]), max(y[j], y[j1])
                                sz0, sz1 = min(z[j], z[j1]), max(z[j], z[j1])
                            end
                        end
                    end
                end
            end
        end

        -- Ground.
        for i = 1, n do
            local gz = ground[i] + 0.006
            if z[i] < gz then z[i] = gz end
        end
    end

    -- Friction: a touched node moves with the body touching it, minus what slides. Grip is the
    -- part of that slide which never happens at all: without it the constraints drag the tape
    -- round a body, one pass at a time, and it slips off anyone who walks into it.
    stepMark = stepMark + 1
    local touched, nt = c.touched, 0
    local fr = 1.0 - p.friction
    local gfr = 1.0 - p.groundFriction
    local moved = 0.0
    for i = 1, n do
        local col = touchedBy[i]
        if col then
            local vcx, vcy, vcz = col.vx * dt, col.vy * dt, col.vz * dt
            local rvx, rvy, rvz = (x[i] - px[i]) - vcx, (y[i] - py[i]) - vcy, (z[i] - pz[i]) - vcz
            local nx, ny, nz = c.cnx[i], c.cny[i], c.cnz[i]
            local vn = rvx * nx + rvy * ny + rvz * nz
            if vn < 0.0 then rvx, rvy, rvz = rvx - nx * vn, rvy - ny * vn, rvz - nz * vn end
            local grip = col.grip or 0.0
            if grip > 0.0 then
                local rn = rvx * nx + rvy * ny + rvz * nz
                local tx, ty, tz = (rvx - nx * rn) * grip, (rvy - ny * rn) * grip, (rvz - nz * rn) * grip
                x[i], y[i], z[i] = x[i] - tx, y[i] - ty, z[i] - tz
                rvx, rvy, rvz = rvx - tx, rvy - ty, rvz - tz
            end
            px[i] = x[i] - (vcx + rvx * fr)
            py[i] = y[i] - (vcy + rvy * fr)
            pz[i] = z[i] - (vcz + rvz * fr)
            c.cw[i] = 1.0

            -- Who is touching the tape, and how far each has pushed it off its rest shape.
            if col.mark ~= stepMark then
                col.mark, col.depth, col.node = stepMark, 0.0, i
                nt = nt + 1
                touched[nt] = col
            end
            if span then
                local dx, dy, dz = x[i] - rx[i], y[i] - ry[i], z[i] - rz[i]
                local d = sqrt(dx * dx + dy * dy + dz * dz)
                if d > col.depth then col.depth, col.node = d, i end
            end
        else
            -- (a tied end keeps lying against what it is tied to: sim.tieOff)
            if c.cw[i] > 0.0 and not pin[i] then c.cw[i] = c.cw[i] * 0.93 end
            if z[i] <= ground[i] + 0.0061 then
                px[i] = x[i] - (x[i] - px[i]) * gfr
                py[i] = y[i] - (y[i] - py[i]) * gfr
            end
            if not pin[i] then
                -- On the road, or nearly (bridging a dip, coming down to it): lie flat on it.
                -- Turning flat over the last 20 cm, not only when touching: a node a centimetre
                -- up stood on edge, half under the ground, with a fold where it met a flat one.
                -- (A span only where it touches: tied low, its middle hangs on edge just above.)
                local flat = 1.0 - (z[i] - ground[i] - 0.006) / (span and 0.03 or 0.2)
                if flat > 1.0 then flat = 1.0 end
                if flat > c.cw[i] then c.cnx[i], c.cny[i], c.cnz[i], c.cw[i] = 0.0, 0.0, 1.0, flat end
            end
        end
        local mx, my, mz = x[i] - px[i], y[i] - py[i], z[i] - pz[i]
        local m = mx * mx + my * my + mz * mz
        if m > moved then moved = m end
    end

    -- How stretched the whole tape is, for slipping and tearing.
    local len = 0.0
    for j = 1, n - 1 do
        local dx, dy, dz = x[j + 1] - x[j], y[j + 1] - y[j], z[j + 1] - z[j]
        len = len + sqrt(dx * dx + dy * dy + dz * dz)
    end
    c.strain = len / c.restLength
    c.moved = sqrt(moved)
    for j = nt + 1, #touched do touched[j] = nil end
    c.ntouched = nt

    return hitVeh, hitNode
end

---Puts a span exactly back on its rest shape and stops it, on top of the ground where its rest
---shape would be below it (slack tape whose holder has been knocked over lies on the road).
---@param c table
function sim.rest(c)
    if c.kind ~= 'span' then return end
    local ground = c.ground
    for i = 1, c.n do
        local z = c.rz[i]
        local gz = ground[i] + 0.006
        local lying = z < gz
        if lying then z = gz end
        c.x[i], c.y[i], c.z[i] = c.rx[i], c.ry[i], z
        c.px[i], c.py[i], c.pz[i] = c.rx[i], c.ry[i], z
        if lying then
            c.cnx[i], c.cny[i], c.cnz[i], c.cw[i] = 0.0, 0.0, 1.0, 1.0
        else
            c.cw[i] = 0.0
        end
    end
    c.strain = 1.0
end

---Measures the ground again under every loose node that has moved `far` metres or more from
---where its ground was last measured. The ground a tape is built with is what lies under it
---where it hangs; a torn half falls towards its tie and a car flings it metres away, so on a kerb
---or a cambered road those heights would put it inside the pavement or in the air.
---@param c table
---@param groundAt fun(x: number, y: number, z: number): number|nil ground height under a point
---@param far number
function sim.reground(c, groundAt, far)
    local gx, gy = c.gx, c.gy
    if not gx then
        gx, gy = {}, {}
        c.gx, c.gy = gx, gy
    end
    local x, y, z, ground, pin = c.x, c.y, c.z, c.ground, c.pin
    local ff = far * far
    for i = 1, c.n do
        if not pin[i] then
            local ox = gx[i]
            local dx, dy = ox and x[i] - ox, ox and y[i] - gy[i]
            if not ox or dx * dx + dy * dy >= ff then
                local g = groundAt(x[i], y[i], z[i])
                -- No collision there yet: keep the old height and try again next time.
                if g and g > -1e8 then
                    ground[i] = g
                    gx[i], gy[i] = x[i], y[i]
                end
            end
        end
    end
end

---Runs a chain with no colliders until it hangs still (used for torn halves appearing in
---sight, which should already be lying where they fell). With `groundAt`, the ground is
---measured again as it falls.
---@param c table
---@param p TapeSimParams
---@param steps integer
---@param groundAt? fun(x: number, y: number, z: number): number|nil
---@param cols? table[] colliders that never move (sim.staticCapsule)
---@param ncols? integer
function sim.settle(c, p, steps, groundAt, cols, ncols)
    for s = 1, steps do
        if groundAt and s % 8 == 1 then sim.reground(c, groundAt, 0.1) end
        sim.step(c, p, cols, cols and ncols or 0, true)
        if c.moved < 2e-5 then break end
    end
end

---Builds the two hanging halves of a span that was torn at fraction t of its length, already
---settled, for a tape that comes into sight torn.
---@param ax number @param ay number @param az number
---@param bx number @param by number @param bz number
---@param segLen number
---@param sag number
---@param t number 0..1 where along the tape it broke
---@param groundAt fun(x: number, y: number, z: number): number|nil ground height under a point
---@param p TapeSimParams
---@param opts? { tieA: table|nil, tieB: table|nil, cols: table[]|nil, ncols: integer|nil } where each end is
---really tied (sim.tieOff), and what it hangs against (the posts)
---@return table, table
function sim.newTorn(ax, ay, az, bx, by, bz, segLen, sag, t, groundAt, p, opts)
    local span = sim.newSpan(ax, ay, az, bx, by, bz, segLen, sag)
    if groundAt then
        for i = 1, span.n do span.ground[i] = groundAt(span.x[i], span.y[i], span.z[i]) or -1e9 end
    end
    local k = max(2, min(span.n - 1, floor(t * (span.n - 1) + 1.5)))
    local a, b = sim.split(span, k)
    local cols, ncols = nil, 0
    if opts then
        if opts.tieA then sim.tieOff(a, 1, opts.tieA) end
        if opts.tieB then sim.tieOff(b, b.n, opts.tieB) end
        cols, ncols = opts.cols, opts.ncols or 0
    end
    sim.settle(a, p, 600, groundAt, cols, ncols)
    sim.settle(b, p, 600, groundAt, cols, ncols)
    a.awake, b.awake = false, false
    return a, b
end

return sim
