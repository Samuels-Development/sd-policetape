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

DrawSpritePoly = function(...)
    calls = calls + 1
    local a = { ... }
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

local f = render.frame
f.cx, f.cy, f.cz = 4.0, -5.0, 1.7
f.lodK = (1024 / 1.2) * 2 * math.tan(math.rad(50) / 2) / 1080
f.time = 12.3
f.windX, f.windY, f.windSpeed, f.flutter = 0.6, 0.8, 4.0, 0.3
f.light, f.lx, f.ly, f.lz = 0.9, 0.3, 0.2, 0.93
f.shading, f.mirror = true, true
f.halfWidth, f.repeatLen = 0.0375, 1.2
f.txd, f.txn = 'sdtape_atlas', 'atlas'

local function run(label, chain, winding, stride)
    render.winding = winding or 'ccw'
    calls, bad = 0, {}
    local t0 = os.clock()
    for _ = 1, 100 do render.chain(chain, uvRects, 0.7, 255, stride) end
    local ms = (os.clock() - t0) * 10 -- per chain, ms (100 runs)
    print(('%-34s %3d nodes  %4d draw calls/frame  %.3f ms Lua/frame  %s'):format(label, chain.n, calls // 100, ms,
        #bad == 0 and 'ok' or ('BAD: ' .. bad[1] .. (' (+%d more)'):format(#bad - 1))))
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

-- A tape hanging straight down (torn half) exercises the parallel-transport fallback.
local P = {}
for k, v in pairs(sim.defaults) do P[k] = v end
local a, b = sim.newTorn(0, 0, 1, 8, 0, 1, 0.25, 0.16, 0.5, function() return 0.0 end, P)
run('torn half A', a)
run('torn half B', b)

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
    local W = {}
    for i = 1, 60 do
        local name, val = debug.getupvalue(render.chain, i)
        if not name then break end
        if name == 'wx' or name == 'wy' or name == 'wz' then W[name] = val end
    end
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
