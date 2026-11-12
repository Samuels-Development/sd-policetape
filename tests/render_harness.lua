-- lua tests/render_harness.lua (from the resource folder). Not shipped.
-- Runs client/tape/render.lua against a stub DrawSpritePoly and checks every triangle it
-- would send: finite positions, UVs inside the style's atlas cell, the print's seams split, and
-- how many draw calls a tape costs.
package.path = './client/tape/?.lua;' .. package.path

local calls, bad = 0, {}
local rect = { 0.1, 0.2, 0.6, 0.23 } -- u0, v0, u1, v1 of some atlas cell
local uvRects = { rect, rect, rect, rect }

local function finite(v) return v == v and v ~= math.huge and v ~= -math.huge end

-- Set to a table to count triangles turned away from the camera, which the engine culls.
local facing = nil
local cam = { 0, 0, 0 }

-- Set to a table to keep every triangle drawn ({ x1, y1, z1, x2, y2, z2, x3, y3, z3 }).
local capture = nil

DrawSpritePoly = function(...)
    calls = calls + 1
    local a = { ... }
    if capture then capture[#capture + 1] = { a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9] } end
    if facing then
        local ax, ay, az = a[4] - a[1], a[5] - a[2], a[6] - a[3]
        local bx, by, bz = a[7] - a[1], a[8] - a[2], a[9] - a[3]
        local nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
        local vx, vy, vz = cam[1] - a[1], cam[2] - a[2], cam[3] - a[3]
        local nl = math.sqrt(nx * nx + ny * ny + nz * nz) * math.sqrt(vx * vx + vy * vy + vz * vz)
        facing.total = facing.total + 1
        -- (seen exactly edge-on, the sign means nothing)
        if nl > 1e-12 and (nx * vx + ny * vy + nz * vz) / nl < -0.02 then facing.away = facing.away + 1 end
        if facing.post then
            -- sd_tape_post at the origin: pole r 0.0275 from 0.075 to 0.985, base r 0.15 to 0.045
            local cx, cy, cz = (a[1] + a[4] + a[7]) / 3, (a[2] + a[5] + a[8]) / 3, (a[3] + a[6] + a[9]) / 3
            for _, q in ipairs({ { a[1], a[2], a[3] }, { a[4], a[5], a[6] }, { a[7], a[8], a[9] }, { cx, cy, cz } }) do
                local r = math.sqrt(q[1] * q[1] + q[2] * q[2])
                if (r < 0.0275 and q[3] > 0.075 and q[3] < 0.985) or (r < 0.15 and q[3] < 0.042) then
                    facing.inPost = facing.inPost + 1
                    break
                end
            end
        end
        if facing.ground then
            for k = 1, 7, 3 do
                if a[k + 2] < facing.ground(a[k], a[k + 1]) - 0.015 then facing.buried = facing.buried + 1 break end
            end
        end
    end
    for i = 1, 9 do
        if not finite(a[i]) then bad[#bad + 1] = ('call %d: position arg %d = %s'):format(calls, i, tostring(a[i])) end
    end
    for i = 10, 13 do
        if type(a[i]) ~= 'number' or a[i] < 0 or a[i] > 255 then bad[#bad + 1] = ('call %d: colour arg %d = %s'):format(calls, i, tostring(a[i])) end
    end
    for _, k in ipairs({ 16, 19, 22 }) do
        local u, v = a[k], a[k + 1]
        if not (u >= rect[1] - 1e-9 and u <= rect[3] + 1e-9) then bad[#bad + 1] = ('call %d: u %.5f outside cell'):format(calls, u) end
        if not (math.abs(v - rect[2]) < 1e-9 or math.abs(v - rect[4]) < 1e-9) then bad[#bad + 1] = ('call %d: v %.5f not an edge'):format(calls, v) end
    end
end

local sim = require 'sim'
local render = require 'render'

---render.lua's scratch arrays (qx, wx, ...): upvalues of `shape`, which render.chain calls.
local function shapeInternals()
    local shapeFn
    for i = 1, 60 do
        local name, val = debug.getupvalue(render.chain, i)
        if not name then break end
        if name == 'shape' then shapeFn = val end
    end
    local up = {}
    for i = 1, 80 do
        local name, val = debug.getupvalue(shapeFn, i)
        if not name then break end
        up[name] = val
    end
    return up
end

local f = render.frame
f.cx, f.cy, f.cz = 4.0, -5.0, 1.7
f.lodK = (1024 / 1.2) * 2 * math.tan(math.rad(50) / 2) / 1080
f.time = 12.3
f.windX, f.windY, f.windSpeed, f.flutter = 0.6, 0.8, 4.0, 0.3
f.light, f.lx, f.ly, f.lz = 0.9, 0.3, 0.2, 0.93
f.shading, f.mirror = true, true
f.halfWidth, f.repeatLen = 0.0375, 1.2
f.txd, f.txn = 'sdtape_atlas', 'atlas'
-- As world.lua sets it: 1080 lines, a 50 degree field of view.
local PIX_PER_M = 2 * math.tan(math.rad(50) / 2) / 1080
f.pix = render.tolerancePx * PIX_PER_M

local function run(label, chain, winding, stride)
    render.winding = winding or 'ccw'
    render.simplify = false
    calls = 0
    render.chain(chain, uvRects, 0.7, 255, stride)
    local every = calls
    render.simplify = true
    calls, bad = 0, {}
    local t0 = os.clock()
    for _ = 1, 100 do render.chain(chain, uvRects, 0.7, 255, stride) end
    local ms = (os.clock() - t0) * 10 -- per chain, ms (100 runs)
    print(('%-34s %3d nodes  %4d draw calls/frame (every node: %3d)  %.3f ms Lua/frame  %s'):format(label, chain.n, calls // 100,
        every, ms, #bad == 0 and 'ok' or ('BAD: ' .. bad[1] .. (' (+%d more)'):format(#bad - 1))))
end

local span = sim.newSpan(0, 0, 1, 8, 0, 1, 0.25, 0.16)
run('8 m span, one winding', span)
run('8 m span, both windings', span, 'both')

-- Camera behind the tape: the print must be mirrored (u running backwards) and still in the cell.
f.cy = 5.0
run('8 m span seen from behind', span)
f.cy = -5.0

local long = sim.newSpan(0, 0, 1, 15, 3, 1.4, 0.25, 0.3)
run('15 m span', long)
run('15 m span, stride 2 (20-45 m away)', long, nil, 2)
run('15 m span, stride 4 (45 m+ away)', long, nil, 4)
run('15 m span, seam to seam (TILE)', long, nil, render.TILE)
run('8 m span, seam to seam (TILE)', span, nil, render.TILE)
f.cy = 5.0
run('8 m span from behind, TILE', span, nil, render.TILE)
f.cy = -5.0

-- A tape hanging straight down (torn half) exercises the parallel-transport fallback.
local P = {}
for k, v in pairs(sim.defaults) do P[k] = v end
local a, b = sim.newTorn(0, 0, 1, 8, 0, 1, 0.25, 0.16, 0.5, function() return 0.0 end, P)
run('torn half A', a)
run('torn half B', b)
run('torn half B, TILE', b, nil, render.TILE)

-- Pressed against a car bonnet: contact normals up.
local pressed = sim.newSpan(0, 0, 1, 8, 0, 1, 0.25, 0.16)
for i = 10, 20 do pressed.cnx[i], pressed.cny[i], pressed.cnz[i], pressed.cw[i] = 0, 0, 1, 1 end
run('span pressed flat on a bonnet', pressed)

-- Post wrap.
calls, bad = 0, {}
render.winding = 'ccw'
render.wrap(0, 0, 1, 0.029, 0.5, uvRects, 255)
print(('%-34s           %4d draw calls        %s'):format('wrap round a post', calls, #bad == 0 and 'ok' or bad[1]))

-- Seam check: count quads whose material span crosses a 1.2 m boundary without being split.
local seams, crossed = 0, 0
for i = 1, span.n - 1 do
    local ka, kb = math.floor(span.s[i] / 1.2), math.floor(span.s[i + 1] / 1.2 - 1e-7)
    if ka ~= kb then seams = seams + 1 end
end
print(('print seams inside the 8 m span: %d (each one splits a quad)'):format(seams))

-- Tape lying on the ground shows as one unbroken ribbon: no triangle turned away from the
-- camera (the engine culls those, leaving holes), and none that turns away a frame later while
-- the physics nudges it by a hair. Torn halves at many angles, on flat and on bumpy ground.
do
    local P2 = {}
    for k, v in pairs(sim.defaults) do P2[k] = v end
    local function bumpy(x, y) return 0.02 * math.sin(x * 3.1) + 0.015 * math.sin(y * 4.7 + x * 1.3) end
    -- The width direction render.chain gave each node (its scratch arrays), to see the ribbon
    -- turn over between neighbours or from one frame to the next (the print flickering).
    local W = shapeInternals()
    local function check(label, chains, ground)
        facing = { total = 0, away = 0, buried = 0, ground = ground }
        local flips, before = 0, {}
        for frame = 1, 30 do
            for ci, c in ipairs(chains) do
                for i = 1, c.n do
                    if not c.pin[i] then c.z[i] = c.z[i] + 2e-6 * math.sin(i * 7.1 + frame) end
                end
                render.chain(c, uvRects, 0.7, 255, 1)
                local prev = before[ci] or {}
                for i = 1, c.n do
                    local wx, wy, wz = W.wx[i], W.wy[i], W.wz[i]
                    local p = prev[i]
                    if p and p[1] * wx + p[2] * wy + p[3] * wz < 0.0 then flips = flips + 1 end
                    if i > 1 and c.cw[i] > 0.9 and c.cw[i - 1] > 0.9
                        and W.wx[i - 1] * wx + W.wy[i - 1] * wy + W.wz[i - 1] * wz < 0.0 then flips = flips + 1 end
                    prev[i] = { wx, wy, wz }
                end
                before[ci] = prev
            end
        end
        facing.flips = flips
        print(('%-34s %5d triangles, %d turned away from the camera, %d in the ground, %d turned over  %s'):format(
            label, facing.total, facing.away, facing.buried, facing.flips,
            (facing.away == 0 and facing.buried == 0 and facing.flips == 0) and 'ok' or 'WRONG'))
        facing = nil
    end
    local flat, rough = {}, {}
    for _, deg in ipairs({ 10, 23, 37, 52, 68, 81, 117, 143, 200, 251, 300, 333 }) do
        local r = math.rad(deg)
        local bx, by = 8 * math.cos(r), 8 * math.sin(r)
        local a1, b1 = sim.newTorn(0, 0, 1, bx, by, 1, 0.25, 0.16, 0.5, function() return 0.0 end, P2)
        local a2, b2 = sim.newTorn(0, 0, 1, bx, by, 1, 0.25, 0.16, 0.5, bumpy, P2)
        flat[#flat + 1], flat[#flat + 2] = a1, b1
        rough[#rough + 1], rough[#rough + 2] = a2, b2
    end
    render.winding = 'ccw'
    f.cx, f.cy, f.cz = 2.5, -3.0, 1.8
    cam[1], cam[2], cam[3] = f.cx, f.cy, f.cz
    check('torn halves on flat ground', flat, function() return 0.0 end)
    check('torn halves on bumpy ground', rough, bumpy)
    -- And the span cases, which must not change.
    check('8 m span', { sim.newSpan(0, 0, 1, 8, 0, 1, 0.25, 0.16) })
    check('span pressed flat on a bonnet', { pressed })
end

-- Torn at a post: the ribbon (both its edges, not only its middle) stays outside the pole and on
-- top of the rubber base, whichever way the tape ran and wherever it broke.
do
    local P3 = {}
    for k, v in pairs(sim.defaults) do P3[k] = v end
    local post = sim.staticCapsule(0, 0, 0.045, 0, 0, 1.05, 0.031)
    local function ground(x, y) return (x * x + y * y < 0.155 * 0.155) and 0.045 or 0.0 end
    facing = { total = 0, away = 0, buried = 0, inPost = 0, post = true }
    render.winding = 'ccw'
    for _, deg in ipairs({ 0, 40, 95, 160, 220, 290 }) do
        local r = math.rad(deg)
        local hx, hy = math.cos(r), math.sin(r)
        for _, frac in ipairs({ 0.06, 0.15, 0.3, 0.5 }) do
            local a = sim.newTorn(0, 0, 1, 8 * hx, 8 * hy, 1, 0.25, 0.16, frac, function(x, y) return ground(x, y) end, P3, {
                tieA = { x = 0.03 * hx, y = 0.03 * hy, z = 1, nx = hx, ny = hy, nz = 0 }, cols = { post }, ncols = 1,
            })
            f.cx, f.cy, f.cz = 1.5 * math.cos(r + 1), 1.5 * math.sin(r + 1), 1.6
            cam[1], cam[2], cam[3] = f.cx, f.cy, f.cz
            render.chain(a, uvRects, 0.7, 255, 1)
        end
    end
    print(('%-34s %5d triangles, %d inside the post or its base  %s'):format('torn at a post (6 ways, 4 places)',
        facing.total, facing.inPost, facing.inPost == 0 and 'ok' or 'WRONG'))
    facing = nil
end

-- The frame's budget (world.lua). render.cost has to count exactly what render.chain draws, at
-- every detail and from wherever a chain's print starts (a torn half starts mid-print), or a
-- frame is planned wrong; a wrap may never cost more than render.wrapCost says; and nothing is
-- drawn once frame.left is spent, whatever was planned.
do
    local wrong, checked = {}, 0
    local chains = { { '8 m span', span }, { '15 m span', long }, { 'torn half A', a }, { 'torn half B', b }, { 'pressed', pressed } }
    for _, len in ipairs({ 0.6, 1.19, 1.2, 1.21, 2.4, 3.7, 6.0, 9.9, 12.0, 14.95 }) do
        chains[#chains + 1] = { ('%.2f m span'):format(len), sim.newSpan(0, 0, 1, len, 0.3, 1.1, 0.25, 0.05 + 0.01 * len) }
    end
    -- Drawing every node, the cost is exact; leaving nodes out, it is what the frame plans for
    -- and never less than what is drawn.
    for _, simplify in ipairs({ false, true }) do
        render.simplify = simplify
        for _, winding in ipairs({ 'ccw', 'both' }) do
            render.winding = winding
            for _, entry in ipairs(chains) do
                for _, detail in ipairs({ 1, 2, 4, render.TILE }) do
                    calls, bad = 0, {}
                    render.chain(entry[2], uvRects, 0.7, 255, detail)
                    local said = render.cost(entry[2], detail)
                    checked = checked + 1
                    if (simplify and calls > said) or (not simplify and calls ~= said) then
                        wrong[#wrong + 1] = ('%s, %s, detail %d%s: drew %d, cost said %d'):format(entry[1], winding, detail,
                            simplify and ' (nodes left out)' or '', calls, said)
                    end
                    if #bad > 0 then wrong[#wrong + 1] = ('%s, %s, detail %d: %s'):format(entry[1], winding, detail, bad[1]) end
                end
            end
        end
    end
    render.simplify = true
    render.winding = 'ccw'
    print(('%-34s %4d chains x details x windings, %s'):format('render.cost >= what is drawn', checked,
        #wrong == 0 and 'ok' or ('WRONG: ' .. wrong[1] .. (' (+%d more)'):format(#wrong - 1))))

    for _, dist in ipairs({ 3.0, 11.9, 12.1, 20.0, 39.0 }) do
        local most = 0
        for k = 0, 199 do
            local r, el = k * 0.37, -1.2 + (k % 23) * 0.1
            f.cx, f.cy, f.cz = dist * math.cos(r) * math.cos(el), dist * math.sin(r) * math.cos(el), 1 + dist * math.sin(el)
            calls = 0
            render.wrap(0, 0, 1, 0.029, r * 1.7, uvRects, 255)
            if calls > most then most = calls end
        end
        print(('%-34s %4d draw calls at most, wrapCost %d  %s'):format(('wrap from 200 places %.1f m away'):format(dist), most,
            render.wrapCost(dist), most <= render.wrapCost(dist) and 'ok' or 'WRONG'))
    end
    f.cx, f.cy, f.cz = 4.0, -5.0, 1.7

    f.left = 50
    calls = 0
    render.chain(long, uvRects, 0.7, 255, 1)
    render.wrap(0, 0, 1, 0.029, 0.5, uvRects, 255)
    local stopped = calls == 50 and f.left == 0
    f.left = math.huge
    print(('%-34s %4d draw calls with 50 left             %s'):format('budget spent mid-tape', calls, stopped and 'ok' or 'WRONG'))
end

-- Leaving nodes out may not move the ribbon visibly. Every node's centre and both edges, where the
-- tape is with every node drawn, lie within the tolerance (render.tolerancePx at 1080p, 1.5 mm close up) of a
-- triangle drawn without them: tapes at rest and pushed, in the wind, from near and far.
do
    local function closest(px, py, pz, t)
        -- Distance from a point to a triangle (Ericson, Real-Time Collision Detection 5.1.5).
        local ax, ay, az, bx, by, bz, cx, cy, cz = t[1], t[2], t[3], t[4], t[5], t[6], t[7], t[8], t[9]
        local abx, aby, abz, acx, acy, acz = bx - ax, by - ay, bz - az, cx - ax, cy - ay, cz - az
        local apx, apy, apz = px - ax, py - ay, pz - az
        local function dot(x1, y1, z1, x2, y2, z2) return x1 * x2 + y1 * y2 + z1 * z2 end
        local function dist(qx, qy, qz) return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2 + (pz - qz) ^ 2) end
        local d1, d2 = dot(abx, aby, abz, apx, apy, apz), dot(acx, acy, acz, apx, apy, apz)
        if d1 <= 0 and d2 <= 0 then return dist(ax, ay, az) end
        local bpx, bpy, bpz = px - bx, py - by, pz - bz
        local d3, d4 = dot(abx, aby, abz, bpx, bpy, bpz), dot(acx, acy, acz, bpx, bpy, bpz)
        if d3 >= 0 and d4 <= d3 then return dist(bx, by, bz) end
        local vc = d1 * d4 - d3 * d2
        if vc <= 0 and d1 >= 0 and d3 <= 0 then
            local v = d1 / (d1 - d3)
            return dist(ax + abx * v, ay + aby * v, az + abz * v)
        end
        local cpx, cpy, cpz = px - cx, py - cy, pz - cz
        local d5, d6 = dot(abx, aby, abz, cpx, cpy, cpz), dot(acx, acy, acz, cpx, cpy, cpz)
        if d6 >= 0 and d5 <= d6 then return dist(cx, cy, cz) end
        local vb = d5 * d2 - d1 * d6
        if vb <= 0 and d2 >= 0 and d6 <= 0 then
            local w = d2 / (d2 - d6)
            return dist(ax + acx * w, ay + acy * w, az + acz * w)
        end
        local va = d3 * d6 - d5 * d4
        if va <= 0 and (d4 - d3) >= 0 and (d5 - d6) >= 0 then
            local w = (d4 - d3) / ((d4 - d3) + (d5 - d6))
            return dist(bx + (cx - bx) * w, by + (cy - by) * w, bz + (cz - bz) * w)
        end
        local denom = 1 / (va + vb + vc)
        local v, w = vb * denom, vc * denom
        return dist(ax + abx * v + acx * w, ay + aby * v + acy * w, az + abz * v + acz * w)
    end

    local up = shapeInternals()
    local hw = f.halfWidth
    local worst, worstAt, nodesChecked, saved, every = 0, '', 0, 0, 0
    local cases = { { '8 m span', span }, { '15 m span', long }, { 'pressed on a bonnet', pressed }, { 'torn half A', a }, { 'torn half B', b } }
    local pushed = sim.newSpan(0, 0, 1, 8, 0, 1, 0.25, 0.16)
    for i = 12, 18 do pushed.y[i] = pushed.y[i] + 0.3 * math.sin((i - 12) / 6 * math.pi) end
    cases[#cases + 1] = { 'pushed 30 cm by a leg', pushed }
    for _, entry in ipairs(cases) do
        local c = entry[2]
        for _, dist in ipairs({ 1.2, 3.0, 8.0, 20.0, 40.0 }) do
            for k = 0, 5 do
                local r = k * 1.1
                f.cx, f.cy, f.cz = 4 + dist * math.cos(r), dist * math.sin(r), 1.6 + (k % 3) * 0.8
                for _, time in ipairs({ 3.0, 12.3, 40.7 }) do
                    f.time = time
                    render.simplify = false
                    calls = 0
                    render.chain(c, uvRects, 0.7, 255, 1)
                    every = every + calls
                    local pts = {}
                    for i = 1, c.n do
                        local x, y, z = up.qx[i], up.qy[i], up.qz[i]
                        local ux, uy, uz = up.wx[i] * hw, up.wy[i] * hw, up.wz[i] * hw
                        -- (the tolerance is measured at the node's centre, as render.lua does)
                        local cd = math.sqrt((x - f.cx) ^ 2 + (y - f.cy) ^ 2 + (z - f.cz) ^ 2)
                        pts[#pts + 1] = { x, y, z, cd }
                        pts[#pts + 1] = { x + ux, y + uy, z + uz, cd }
                        pts[#pts + 1] = { x - ux, y - uy, z - uz, cd }
                    end
                    render.simplify = true
                    capture, calls = {}, 0
                    render.chain(c, uvRects, 0.7, 255, 1)
                    saved = saved + calls
                    for _, q in ipairs(pts) do
                        local best = math.huge
                        for _, t in ipairs(capture) do
                            local d = closest(q[1], q[2], q[3], t)
                            if d < best then best = d end
                        end
                        local tol = math.max(0.0015, f.pix * q[4])
                        nodesChecked = nodesChecked + 1
                        if best / tol > worst then
                            worst, worstAt = best / tol, ('%s, %.1f m away (%.2f mm off)'):format(entry[1], dist, best * 1000)
                        end
                    end
                    capture = nil
                end
            end
        end
    end
    f.cx, f.cy, f.cz, f.time = 4.0, -5.0, 1.7, 12.3
    print(('%-34s %5d points, worst %.2f of the tolerance (%s)  %s'):format('nodes left out stay on the ribbon',
        nodesChecked, worst, worstAt, worst <= 1.0 and 'ok' or 'WRONG'))
    print(('%-34s %5d draw calls instead of %d (%.0f%% fewer)'):format('the same frames, nodes left out', saved, every,
        100 * (1 - saved / every)))
end

-- A still chain is drawn again for render.REDRAW instead of being worked out every frame: the
-- same triangles, each still facing the camera after it has gone round to the other side, never
-- past the frame's budget, and worked out anew (the wind has moved it) once REDRAW has passed.
do
    local c = sim.newSpan(0, 0, 1.0, 8, 0, 1.0, 0.25, 0.16)
    sim.rest(c)
    local function at(time, cx, cy, left)
        f.time, f.cx, f.cy, f.cz, f.left = time, cx, cy, 1.7, left or 600
        cam = { cx, cy, 1.7 }
    end
    local function draw(time, cx, cy, left)
        at(time, cx, cy, left)
        capture, calls = {}, 0
        render.chain(c, uvRects, 0.7, 255, 1, true)
        local got = capture
        capture = nil
        return got, calls
    end
    local function same(a, b)
        if #a ~= #b then return false end
        for i = 1, #a do for k = 1, 9 do if a[i][k] ~= b[i][k] then return false end end end
        return true
    end
    render.winding = 'ccw'
    local first = draw(30.0, 4, -5)
    local again = draw(30.0 + render.REDRAW * 0.5, 4, -5)
    print(('%-34s %4d triangles, drawn again the same: %s  %s'):format('still chain drawn again', #first,
        tostring(same(first, again)), same(first, again) and 'ok' or 'WRONG'))

    facing = { total = 0, away = 0 }
    draw(30.0 + render.REDRAW * 0.6, 4, 5)
    print(('%-34s %4d triangles, %d turned away from the camera  %s'):format('drawn again from the other side',
        facing.total, facing.away, facing.away == 0 and 'ok' or 'WRONG'))
    facing = nil

    local _, n = draw(30.0 + render.REDRAW * 0.7, 4, -5, 5)
    print(('%-34s %4d draw calls with 5 left  %s'):format('drawn again within the budget', n, n <= 5 and 'ok' or 'WRONG'))

    local later = draw(30.0 + render.REDRAW * 1.5, 4, -5)
    print(('%-34s moved: %s  %s'):format('worked out anew after REDRAW', tostring(not same(first, later)),
        not same(first, later) and 'ok' or 'WRONG'))
    f.cx, f.cy, f.cz, f.time, f.left = 4.0, -5.0, 1.7, 12.3, math.huge
end
