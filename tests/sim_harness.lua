-- Offline checks for client/tape/sim.lua under stock Lua 5.4. Not shipped (not in fxmanifest).
--   lua tests/sim_harness.lua            (run from the resource folder)
-- Prints measurements rather than asserting exact numbers: the point is to tune by looking.
package.path = './client/tape/?.lua;' .. package.path
local sim = require 'sim'

local P = {}
for k, v in pairs(sim.defaults) do P[k] = v end
-- Optional overrides from the command line: lua tests/sim_harness.lua restK=30 damping=0.95
for _, a in ipairs(arg) do
    local k, v = a:match('^(%w+)=(.+)$')
    if k then P[k] = tonumber(v) end
end

local SEG = 0.25
local function sagFor(len) return 0.02 + 0.022 * len end

local function capsule(ax, ay, az, bx, by, bz, r, vx, vy, vz)
    return {
        kind = 1, ax = ax, ay = ay, az = az, bx = bx, by = by, bz = bz, r = r,
        vx = vx or 0, vy = vy or 0, vz = vz or 0,
        minx = math.min(ax, bx) - r - 0.05, maxx = math.max(ax, bx) + r + 0.05,
        miny = math.min(ay, by) - r - 0.05, maxy = math.max(ay, by) + r + 0.05,
        minz = math.min(az, bz) - r - 0.05, maxz = math.max(az, bz) + r + 0.05,
    }
end

-- A crude car: 1.9 x 4.6 m, bonnet at 0.95 m, roof 1.45 m with a sloped windscreen, 0.18 m
-- ground clearance. Model space: X right, Y forward, Z up, origin at the ground under the middle.
local function carProfile()
    local prof = { minx = -0.95, maxx = 0.95, miny = -2.3, maxy = 2.3, nx = 8, ny = 20, top = {}, bottom = {} }
    prof.cx = (prof.maxx - prof.minx) / prof.nx
    prof.cy = (prof.maxy - prof.miny) / prof.ny
    for iy = 0, prof.ny - 1 do
        local y = prof.miny + (iy + 0.5) * prof.cy
        local h
        if y > 1.2 then h = 0.95 - (y - 1.2) * 0.25          -- bonnet sloping down to the bumper
        elseif y > 0.4 then h = 0.95 + (1.2 - y) * 0.62       -- windscreen
        elseif y > -1.4 then h = 1.45                         -- roof
        else h = 1.45 - (-1.4 - y) * 0.6 end                  -- rear screen / boot
        for ix = 0, prof.nx - 1 do
            local x = prof.minx + (ix + 0.5) * prof.cx
            local edge = math.abs(x) > 0.75 and 0.08 or 0
            prof.top[ix + iy * prof.nx + 1] = h - edge
            prof.bottom[ix + iy * prof.nx + 1] = 0.18
        end
    end
    return prof
end

local function vehicle(prof, ox, oy, oz, heading, speed)
    local s, c = math.sin(heading), math.cos(heading)
    -- forward = (-sin, cos), right = (cos, sin): GTA heading convention
    local v = {
        kind = 2, prof = prof, ox = ox, oy = oy, oz = oz,
        rx = c, ry = s, rz = 0, fx = -s, fy = c, fz = 0, ux = 0, uy = 0, uz = 1,
        speed = speed,
    }
    v.vx, v.vy, v.vz = v.fx * speed, v.fy * speed, 0
    local r = 2.6
    v.minx, v.maxx, v.miny, v.maxy, v.minz, v.maxz = ox - r, ox + r, oy - r, oy + r, oz - 0.1, oz + 1.6
    return v
end

local function maxDeviation(c)
    local m = 0
    for i = 1, c.n do
        local dx, dy, dz = c.x[i] - c.rx[i], c.y[i] - c.ry[i], c.z[i] - c.rz[i]
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d > m then m = d end
    end
    return m
end

local function mid(c) local i = math.floor(c.n / 2) + 1 return c.x[i], c.y[i], c.z[i] end

print(('params: iterations=%d damping=%.3f restK=%.1f stiffness=%.2f friction=%.2f'):format(
    P.iterations, P.damping, P.restK, P.stiffness, P.friction))

-- 1. Rest shape holds still.
do
    local c = sim.newSpan(0, 0, 1, 8, 0, 1, SEG, sagFor(8))
    for _ = 1, 240 do sim.step(c, P, nil, 0, false) end
    local _, _, z = mid(c)
    print(('[rest]   8 m span, %d nodes, sag %.3f m, mid z %.3f, drift after 4 s %.5f m, strain %.4f'):format(
        c.n, sagFor(8), z, maxDeviation(c), c.strain))
end

-- 2. A ped walks into the middle of an 8 m tape at walking pace, stands 0.6 m past the line for
-- a second, then walks back out. Torso capsule + two legs.
do
    local c = sim.newSpan(0, 0, 1, 8, 0, 1, SEG, sagFor(8))
    sim.wake(c)
    local cols = {}
    local t, y = 0.0, -0.8
    local peakStrain, peakPush = 1.0, 0.0
    local phase = 'in'
    local releaseT
    local frames = 0
    -- Roughly a GTA freemode ped: pelvis at 0.97 m, thighs to the knees at 0.52, calves to 0.08.
    local function body(yc, vy)
        cols[1] = capsule(4.0, yc, 1.0, 4.0, yc, 1.38, 0.16, 0, vy, 0)          -- torso
        cols[2] = capsule(3.9, yc, 0.95, 4.1, yc, 0.95, 0.11, 0, vy, 0)          -- hips
        cols[3] = capsule(3.9, yc, 0.93, 3.89, yc + 0.03, 0.52, 0.085, 0, vy, 0) -- left thigh
        cols[4] = capsule(4.1, yc, 0.93, 4.11, yc + 0.03, 0.52, 0.085, 0, vy, 0) -- right thigh
        cols[5] = capsule(3.89, yc + 0.03, 0.52, 3.88, yc, 0.08, 0.06, 0, vy, 0) -- left calf
        cols[6] = capsule(4.11, yc + 0.03, 0.52, 4.12, yc, 0.08, 0.06, 0, vy, 0) -- right calf
    end
    while t < 6.0 do
        local vy = 0
        if phase == 'in' then
            vy = 1.4; y = y + vy * P.dt
            if y >= 0.6 then phase = 'hold'; releaseT = t + 1.0 end
        elseif phase == 'hold' then
            if t >= releaseT then phase = 'out' end
        elseif phase == 'out' then
            vy = -1.4; y = y + vy * P.dt
            if y <= -1.0 then phase = 'gone'; releaseT = t end
        end
        local ncols = 0
        if phase ~= 'gone' then body(y, vy); ncols = 6 end
        sim.step(c, P, cols, ncols, false)
        frames = frames + 1
        local _, my = mid(c)
        if my > peakPush then peakPush = my end
        if c.strain > peakStrain then peakStrain = c.strain end
        t = t + P.dt
        if phase == 'gone' and maxDeviation(c) < 0.01 then
            print(('[ped]    peak push %.2f m, peak strain %.3f, back to rest (1 cm) %.2f s after leaving'):format(
                peakPush, peakStrain, t - releaseT))
            break
        end
    end
    if phase ~= 'gone' or maxDeviation(c) >= 0.01 then
        print(('[ped]    did not settle: phase %s dev %.3f'):format(phase, maxDeviation(c)))
    end

    -- Straightness while held: how far the tape between anchor and body sags off a straight V.
end

-- 3. Same, but the ped keeps walking 3 m past the line (the world module would make it slip).
do
    local c = sim.newSpan(0, 0, 0.6, 8, 0, 0.6, SEG, sagFor(8))
    sim.wake(c)
    local cols = {}
    local y = -0.8
    local strainAt = {}
    for f = 1, 200 do
        y = y + 1.4 * P.dt
        cols[1] = capsule(3.89, y, 0.93, 3.89, y, 0.08, 0.075, 0, 1.4, 0) -- left leg only
        sim.step(c, P, cols, 1, false)
        if f % 40 == 0 then strainAt[#strainAt + 1] = ('y=%.1f:%.3f'):format(y, c.strain) end
    end
    print('[walkthrough] strain as the ped walks on: ' .. table.concat(strainAt, '  '))
end

-- 4. Car through the tape at 3 m/s and at 12 m/s; report strain and where the tape sits on it.
for _, speed in ipairs({ 3, 12 }) do
    local c = sim.newSpan(0, 0, 0.95, 8, 0, 0.95, SEG, sagFor(8))
    sim.wake(c)
    local prof = carProfile()
    local y = -3.0 -- car centre, heading 0 = facing +Y
    local cols = {}
    local first, log = nil, {}
    for f = 1, 300 do
        y = y + speed * P.dt
        cols[1] = vehicle(prof, 4.0, y, 0.0, 0.0, speed)
        local veh, node = sim.step(c, P, cols, 1, false)
        if veh and not first then first = f end
        if f % 15 == 0 and first then
            local _, my, mz = mid(c)
            log[#log + 1] = ('t+%.2fs strain %.3f mid y-car %.2f z %.2f'):format((f - first) * P.dt, c.strain, my - y, mz)
        end
        if c.strain > 1.8 then break end
    end
    print(('[car %2d m/s] contact at frame %s'):format(speed, tostring(first)))
    for i = 1, math.min(#log, 8) do print('    ' .. log[i]) end
end

-- 5. Torn tape: halves hang from 1 m anchors and should lie on flat ground at z = 0.
do
    local a, b = sim.newTorn(0, 0, 1, 8, 0, 1, SEG, sagFor(8), 0.5, function() return 0.0 end, P)
    local onGround, lowest = 0, 1e9
    for i = 1, a.n do
        if a.z[i] < 0.02 then onGround = onGround + 1 end
        if a.z[i] < lowest then lowest = a.z[i] end
    end
    print(('[torn]   half A: %d nodes, %d on the ground, lowest z %.3f, free end at (%.2f, %.2f, %.2f), strain %.3f'):format(
        a.n, onGround, lowest, a.x[a.n], a.y[a.n], a.z[a.n], a.strain))
    print(('         half B: %d nodes, first node pinned=%s last pinned=%s'):format(b.n, tostring(b.pin[1]), tostring(b.pin[b.n])))
end

-- 6. Cost: an awake 12 m span with a ped touching it, 1000 steps.
do
    local c = sim.newSpan(0, 0, 1, 12, 0, 1, SEG, sagFor(12))
    sim.wake(c)
    local cols = { capsule(6.0, 0.2, 0.95, 6.0, 0.2, 1.45, 0.17), capsule(5.9, 0.2, 0.08, 5.9, 0.2, 0.92, 0.08), capsule(6.1, 0.2, 0.08, 6.1, 0.2, 0.92, 0.08) }
    local t0 = os.clock()
    for _ = 1, 1000 do sim.step(c, P, cols, 3, false) end
    local ms = (os.clock() - t0)
    print(('[cost]   12 m span (%d nodes) + 3 capsules: %.3f ms per step (stock Lua; FiveM is similar)'):format(c.n, ms))
end

-- 7. Grip, resistance and snapping (Config.Tear.PeoplePush / VehiclePush).
-- A ped walks into the tape at 1.4 m/s; the further the tape is pushed, the slower they go
-- (world.lua's resistance: move rate 1 - 0.75 r, r from push depth). It snaps when pushed past
-- PUSH. Reports whether the tape stays on the body (depth only grows) and when it would snap.
local PUSH, VPUSH = tonumber(os.getenv('PUSH') or '') or 1.0, tonumber(os.getenv('VPUSH') or '') or 1.8
local function pushTest(label, xAt, len)
    local c = sim.newSpan(0, 0, 1, len, 0, 1, SEG, sagFor(len))
    sim.wake(c)
    local cols = {}
    local y, t, maxDepth, slipped, snapAt = -0.6, 0.0, 0.0, false, nil
    for _ = 1, 600 do
        local depth = 0.0
        for k = 1, c.ntouched do depth = math.max(depth, c.touched[k].depth or 0) end
        local r = math.min(1, math.max(0, (depth - 0.12) / (PUSH - 0.12)))
        local v = 1.4 * math.max(0.25, 1 - 0.75 * r)
        y = y + v * P.dt
        local function cap(ax, ay, az, bx, by, bz, rad)
            local k = capsule(ax, ay, az, bx, by, bz, rad, 0, v, 0)
            k.grip = 0.7
            return k
        end
        cols[1] = cap(xAt, y, 1.0, xAt, y, 1.38, 0.16)
        cols[2] = cap(xAt - 0.1, y, 0.95, xAt + 0.1, y, 0.95, 0.11)
        cols[3] = cap(xAt - 0.1, y, 0.93, xAt - 0.11, y + 0.03, 0.52, 0.085)
        cols[4] = cap(xAt + 0.1, y, 0.93, xAt + 0.11, y + 0.03, 0.52, 0.085)
        sim.step(c, P, cols, 4, false)
        t = t + P.dt
        local d = 0.0
        for k = 1, c.ntouched do d = math.max(d, c.touched[k].depth or 0) end
        if d < maxDepth - 0.15 and maxDepth > 0.3 then slipped = true end
        if d > maxDepth then maxDepth = d end
        if d >= PUSH then snapAt = t break end
    end
    print(('[push %s] %s: max push %.2f m, strain %.3f, %s'):format(label, slipped and 'SLIPPED' or 'held on',
        maxDepth, c.strain, snapAt and ('snaps after %.2f s'):format(snapAt) or 'never snaps'))
end
pushTest('centre of 8 m', 4.0, 8)
pushTest('1.5 m from a tie, 8 m', 1.5, 8)
pushTest('centre of 3 m', 1.5, 3)

do
    local c = sim.newSpan(0, 0, 0.95, 8, 0, 0.95, SEG, sagFor(8))
    sim.wake(c)
    local prof = carProfile()
    local y, t, snapAt = -3.0, 0.0, nil
    local cols = {}
    for _ = 1, 600 do
        y = y + 3 * P.dt
        cols[1] = vehicle(prof, 4.0, y, 0.0, 0.0, 3)
        cols[1].grip = 0.85
        sim.step(c, P, cols, 1, false)
        t = t + P.dt
        local d = 0.0
        for k = 1, c.ntouched do d = math.max(d, c.touched[k].depth or 0) end
        if d >= VPUSH or c.strain >= 1.4 then snapAt = t break end
    end
    local _, my, mz = mid(c)
    print(('[car 3 m/s, grip] %s; mid of tape %.2f m from the car centre, at height %.2f'):format(
        snapAt and ('snaps after %.2f s'):format(snapAt) or 'never snaps', my - y, mz))
    local h1, h2 = sim.split(c, math.floor(c.n / 2))
    print(('[snap recoil] strain %.3f -> free end speeds %.2f m/s and %.2f m/s'):format(c.strain,
        math.sqrt((h1.x[h1.n] - h1.px[h1.n]) ^ 2 + (h1.y[h1.n] - h1.py[h1.n]) ^ 2) * 60,
        math.sqrt((h2.x[1] - h2.px[1]) ^ 2 + (h2.y[1] - h2.py[1]) ^ 2) * 60))
end

-- 8. Torn halves land on the ground that is really under them. The ground is measured under the
-- tape where it hung, but a torn half falls towards its tie and a car flings it metres away: on
-- a kerb or a cambered road the old heights put it inside the pavement or in the air. Each half
-- must be measured again where it goes (sim.reground, called by world.lua while it moves).
do
    -- Posts on 15 cm pavements, road between, and the road rising 4% the way the car drags.
    local function ground(x, y) return ((x < 1.5 or x > 6.5) and 0.15 or 0.0) + 0.04 * math.max(0, y) end
    local function at(x, y, _) return ground(x, y) end
    local function check(label, h)
        local under, worst, over = 0, 0.0, 0
        -- From the tie outwards: it hangs, then lies. Once it has reached the ground it should
        -- stay on it (a node next to a change of level may bridge it).
        local first, last, step = 1, h.n, 1
        if not h.pin[1] then first, last, step = h.n, 1, -1 end
        local lying = false
        for i = first, last, step do
            local d = h.z[i] - ground(h.x[i], h.y[i])
            if d < -0.005 then under = under + 1 end
            if d < worst then worst = d end
            if d < 0.01 then lying = true end
            local j = i - step
            local edge = j >= 1 and j <= h.n and math.abs(ground(h.x[j], h.y[j]) - ground(h.x[i], h.y[i])) > 0.05
            if lying and d > 0.03 and not edge then over = over + 1 end
        end
        print(('[torn ground] %-26s %2d nodes: %d inside the ground (worst %.3f m), %d hovering  %s'):format(
            label, h.n, under, worst, over, (under == 0 and over == 0) and 'ok' or 'WRONG'))
    end

    local a = sim.newTorn(0, 0, 1.15, 8, 0, 1.15, SEG, sagFor(8), 0.5, at, P)
    check('built torn, kerbs', a)

    -- Torn by a car: the middle dragged 1.5 m down the road at 10 m/s, then it snaps; then the
    -- halves are simulated the way world.lua does it.
    local c = sim.newSpan(0, 0, 1.0, 8, 0, 1.0, SEG, sagFor(8))
    for i = 1, c.n do c.ground[i] = at(c.x[i], c.y[i], c.z[i]) end
    for i = 2, c.n - 1 do
        local w = 1 - math.abs((i - 1) / (c.n - 1) - 0.5) * 2
        c.y[i] = c.y[i] + 1.5 * w
        c.py[i] = c.y[i] - 10 * P.dt * w
    end
    c.strain = 1.3
    local h1, h2 = sim.split(c, math.floor(c.n / 2) + 1)
    for _ = 1, 1200 do
        for _, h in ipairs({ h1, h2 }) do
            sim.reground(h, at, 0.1)
            sim.step(h, P, nil, 0, true)
        end
    end
    check('torn by a car, kerb + slope', h1)
    check('(other half)', h2)
end

-- 9. Torn at a post: the half still tied to it hangs down the OUTSIDE of the post and lies on
-- the rubber base, not inside them (the ribbon itself: tests/render_harness.lua). sd_tape_post (tools/build_props.py): base r 0.15 up
-- to 0.045, pole r 0.031 up to 1.05, tie point on the axis at 1.0. world.lua ties the torn end
-- off at the groove's surface on the side the tape left by, facing out, and gives the post to the
-- physics as a solid.
do
    local post = sim.staticCapsule(0, 0, 0.045, 0, 0, 1.05, 0.031)
    local function ground(x, y) return (x * x + y * y < 0.155 * 0.155) and 0.045 or 0.0 end
    for _, frac in ipairs({ 0.08, 0.15, 0.3, 0.5 }) do
        local a = sim.newTorn(0, 0, 1, 8, 0, 1, SEG, sagFor(8), frac, function(x, y) return ground(x, y) end, P, {
            tieA = { x = 0.03, y = 0, z = 1, nx = 1, ny = 0, nz = 0 }, cols = { post }, ncols = 1,
        })
        -- (the tied node itself sits in the groove, r 0.026: that one is meant to be in there)
        local hidden = 0
        for i = 2, a.n do
            local r = math.sqrt(a.x[i] ^ 2 + a.y[i] ^ 2)
            if r < 0.031 and a.z[i] > 0.045 and a.z[i] < 1.05 then hidden = hidden + 1 end
            if r < 0.15 and a.z[i] < 0.045 then hidden = hidden + 1 end
        end
        print(('[torn at a post] torn %2d%% along, %.2f m left on the post: %d nodes inside the post or its base  %s'):format(
            frac * 100, a.s[a.n] - a.s[1], hidden, hidden == 0 and 'ok' or 'WRONG'))
    end
end
