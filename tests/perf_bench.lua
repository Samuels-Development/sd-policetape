-- lua tests/perf_bench.lua (from the resource folder). Not shipped.
-- Times the per-frame Lua work for one tape: a physics step with nobody near, with one person
-- standing against it (12 bone capsules), and with a crowd. In game, multiply by the frame rate's
-- steps per frame (1 at 60 fps) and add the draw calls.
package.path = './client/tape/?.lua;' .. package.path
local sim = require 'sim'

local P = {}
for k, v in pairs(sim.defaults) do P[k] = v end

local SEG = 0.25
local function sagFor(len) return 0.015 + 0.018 * len end

local function capsule(ax, ay, az, bx, by, bz, r)
    return {
        kind = 1, ax = ax, ay = ay, az = az, bx = bx, by = by, bz = bz, r = r,
        vx = 0, vy = 0, vz = 0, grip = 0.7, entity = 1, mine = false, player = false,
        minx = math.min(ax, bx) - r - 0.05, maxx = math.max(ax, bx) + r + 0.05,
        miny = math.min(ay, by) - r - 0.05, maxy = math.max(ay, by) + r + 0.05,
        minz = math.min(az, bz) - r - 0.05, maxz = math.max(az, bz) + r + 0.05,
    }
end

-- A standing person at (x, y), as colliders.lua builds them: 12 capsules between bones.
local function person(x, y, list)
    local parts = {
        { 0, 0, 0.95, 0, 0, 1.35, 0.16 }, { 0, 0, 1.35, 0, 0, 1.55, 0.15 }, { 0, 0, 1.55, 0, 0, 1.7, 0.11 },
        { -0.1, 0, 0.92, 0.1, 0, 0.92, 0.11 },
        { -0.1, 0, 0.92, -0.1, 0, 0.5, 0.085 }, { -0.1, 0, 0.5, -0.1, 0, 0.08, 0.06 },
        { 0.1, 0, 0.92, 0.1, 0, 0.5, 0.085 }, { 0.1, 0, 0.5, 0.1, 0, 0.08, 0.06 },
        { -0.2, 0, 1.45, -0.25, 0, 1.15, 0.055 }, { -0.25, 0, 1.15, -0.27, 0, 0.9, 0.045 },
        { 0.2, 0, 1.45, 0.25, 0, 1.15, 0.055 }, { 0.25, 0, 1.15, 0.27, 0, 0.9, 0.045 },
    }
    for _, p in ipairs(parts) do
        list[#list + 1] = capsule(x + p[1], y + p[2], p[3], x + p[4], y + p[5], p[6], p[7])
    end
end

local function bench(label, len, people, dy)
    local c = sim.newSpan(0, 0, 1.0, len, 0, 1.0, SEG, sagFor(len))
    local cols = {}
    for k = 1, people do person(len * k / (people + 1), dy or 0.6, cols) end
    -- settle once, then time steady-state steps
    for _ = 1, 120 do sim.wake(c); sim.step(c, P, cols, #cols) end
    local N = 2000
    local t0 = os.clock()
    for _ = 1, N do
        if #cols > 0 then sim.wake(c) end
        sim.step(c, P, cols, #cols)
    end
    local ms = (os.clock() - t0) * 1000 / N
    print(('%-46s %3d nodes  %3d capsules  %.3f ms per step'):format(label, c.n, #cols, ms))
end

bench('8 m span, nobody near (awake)', 8, 0)
bench('8 m span, one person 0.6 m away', 8, 1, 0.6)
bench('8 m span, one person against it', 8, 1, 0.05)
bench('15 m span, nobody near (awake)', 15, 0)
bench('15 m span, one person against it', 15, 1, 0.05)
bench('15 m span, four people against it', 15, 4, 0.05)
-- A busy pavement: people walking past near the tape, not touching it.
bench('8 m span, 3 people walking past 1.5 m off', 8, 3, 1.5)
bench('8 m span, 6 people walking past 2 m off', 8, 6, 2.0)
bench('8 m span, 6 people against it', 8, 6, 0.05)
