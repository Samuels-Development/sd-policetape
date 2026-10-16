-- lua tests/holders_check.lua (from the resource folder). Not shipped.
-- The posts and cones tape is tied to (configs/holders.lua, shared/holder.lua):
--   * the config matches the models as built (tools/cones.lua, written by tools/build_cones.py)
--   * every one lies down sensibly when knocked over: on the ground, nothing under it
--   * a tape whose holder is knocked over goes slack and lies on the road, not under it
--   * a tape torn at a cone hangs down the outside of it, standing or lying
package.path = './?.lua;./client/tape/?.lua;' .. package.path
vec3 = function(x, y, z) return { x = x, y = y, z = z } end -- configs/config.lua uses it

local holder = require 'shared.holder'
local sim = require 'sim'

local fails = 0
local function check(ok, what)
    if not ok then
        fails = fails + 1
        print('  WRONG: ' .. what)
    end
end

-- 1. The list --------------------------------------------------------------------------------------
do
    local ids, models = {}, {}
    for _, def in ipairs(holder.list) do
        check(not ids[def.id], 'duplicate id ' .. def.id)
        check(not models[def.model], 'duplicate model ' .. def.model)
        ids[def.id], models[def.model] = true, true
        local b = def.body
        check(def.tie > b[1] and def.tie < b[3], def.id .. ': tie point outside the body')
        local rAtTie = b[2] + (b[4] - b[2]) * (def.tie - b[1]) / (b[3] - b[1])
        -- (a groove may take the turns in: the post's is 5 mm deep)
        check(def.tieRadius >= rAtTie - 0.006, def.id .. ': the turns of tape would sit inside it')
    end

    local ok, built = pcall(dofile, 'tools/cones.lua')
    if ok then
        local n = 0
        for _, c in ipairs(built) do
            n = n + 1
            local def = holder.get(c.id)
            check(def ~= nil, 'cone ' .. c.id .. ' is built but not in configs/holders.lua')
            if def then
                check(def.model == c.model, c.id .. ': model ' .. def.model .. ' but built as ' .. c.model)
                check(math.abs(def.tie - c.tie) < 1e-4 and math.abs(def.tieRadius - c.tieRadius) < 1e-4, c.id .. ': tie differs from the model')
                for i = 1, 4 do check(math.abs(def.body[i] - c.body[i]) < 1e-4, c.id .. ': body differs from the model') end
                for i = 1, 2 do check(math.abs(def.base[i] - c.base[i]) < 1e-4, c.id .. ': base differs from the model') end
                check(def.base[3] == c.base[3], c.id .. ': base shape differs from the model')
            end
        end
        print(('[holders] %d holders in the config, %d cones as built: %s'):format(#holder.list, n, fails == 0 and 'match' or 'MISMATCH'))
    else
        print('[holders] tools/cones.lua not found: model sizes not compared')
    end
end

-- 2. Lying down ------------------------------------------------------------------------------------
do
    local before = fails
    local worstBelow, minDeg, maxDeg = 0.0, 999, 0
    for _, def in ipairs(holder.list) do
        local deg = math.deg(def.rest)
        minDeg, maxDeg = math.min(minDeg, deg), math.max(maxDeg, deg)
        check(deg > 90 and deg < 125, ('%s: lies at %.1f degrees'):format(def.id, deg))
        for _, heading in ipairs({ 0.0, 0.7, 2.2, -1.3 }) do
            for _, dir in ipairs({ { 1, 0 }, { 0, 1 }, { -0.6, 0.8 }, { 0.28, -0.96 } }) do
                local fall = { x = dir[1], y = dir[2], s = 0.0 }
                local up = holder.pose(def, 10, 20, 5, heading, nil)
                local start = holder.pose(def, 10, 20, 5, heading, fall, 0.0, 0.0)
                check(math.abs(start.x - up.x) + math.abs(start.y - up.y) + math.abs(start.z - up.z) < 1e-9,
                    def.id .. ': a fall does not start where it stands')
                local lie = holder.pose(def, 10, 20, 5, heading, fall, 1.0, 1.0)
                -- Every point of its outline (base rim, body bottom and top, at 16 angles) on or above the ground.
                local p, h = def.base[1], def.base[2]
                local b = def.body
                for k = 0, 15 do
                    local a = k * math.pi / 8
                    local c, s = math.cos(a), math.sin(a)
                    for _, q in ipairs({ { p, 0 }, { p, h }, { b[2], b[1] }, { b[4], b[3] } }) do
                        local _, _, z = holder.point(lie, q[1] * c, q[1] * s, q[2])
                        if z - 5 < worstBelow then worstBelow = z - 5 end
                    end
                end
                -- Lying, its tie point is down near the ground, and on the side it fell to.
                local tx, ty, tz = holder.point(lie, 0, 0, def.tie)
                check(tz - 5 < 0.3, def.id .. ': tie point still high once down')
                check((tx - 10) * dir[1] + (ty - 20) * dir[2] > 0.5 * def.tie, def.id .. ': did not fall the way it was pushed')
                -- The quaternion is the same rotation.
                local qx, qy, qz, qw = holder.quat(lie)
                local m = lie.m
                local r11 = 1 - 2 * (qy * qy + qz * qz)
                local r23 = 2 * (qy * qz - qx * qw)
                local r31 = 2 * (qx * qz - qy * qw)
                check(math.abs(r11 - m[1]) < 1e-6 and math.abs(r23 - m[6]) < 1e-6 and math.abs(r31 - m[7]) < 1e-6,
                    def.id .. ': quaternion does not match the rotation')
            end
        end
    end
    check(worstBelow > -0.005, ('a holder lies %.3f m under the ground'):format(-worstBelow))
    print(('[holders] knocked over: lie at %.1f to %.1f degrees, lowest point %.4f m from the ground  %s'):format(
        minDeg, maxDeg, worstBelow, fails == before and 'ok' or 'WRONG'))
end

-- 3. The tape goes down with it --------------------------------------------------------------------
-- A 6 m tape from a post to a cone; the cone is knocked towards the post. The tape keeps its
-- length, so it goes slack: it should lie on the road, not under it, and follow the cone without
-- being rebuilt.
local P = {}
for k, v in pairs(sim.defaults) do P[k] = v end
do
    local before = fails
    local post, cone = holder.get('post'), holder.get('cone_orange')
    local ax, ay, az = 0, 0, post.tie
    local bx, by, bz = 6, 0, cone.tie
    local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2)
    local nodes = sim.nodeCount(len, 0.25)
    local function sag(d)
        local s0 = 0.015 + 0.018 * len
        return d >= len and s0 or math.sqrt(s0 * s0 + 3 * d * (len - d) / 8)
    end
    local c = sim.newSpan(ax, ay, az, bx, by, bz, 0.25, sag(len), nodes)
    for i = 1, c.n do c.ground[i] = 0.0 end
    sim.wake(c)
    local fall = { x = -1, y = 0, s = 0.0 }
    local rebuilt = false
    for frame = 1, 240 do
        local fa, fs = holder.ease(frame / 60, 0.6)
        local pose = holder.pose(cone, 6, 0, 0, 0.0, fall, fa, fs)
        local x, y, z = holder.point(pose, 0, 0, cone.tie)
        local d = math.sqrt((x - ax) ^ 2 + (y - ay) ^ 2 + (z - az) ^ 2)
        if not sim.retarget(c, ax, ay, az, x, y, z, 0.25, sag(d), nodes) then rebuilt = true end
        for i = 1, c.n do c.ground[i] = 0.0 end
        sim.step(c, P, nil, 0, false)
    end
    for _ = 1, 600 do sim.step(c, P, nil, 0, false) end
    local under, onRoad = 0, 0
    for i = 1, c.n do
        if c.z[i] < -0.002 then under = under + 1 end
        if c.z[i] < 0.02 then onRoad = onRoad + 1 end
    end
    sim.rest(c)
    local underRested = 0
    for i = 1, c.n do if c.z[i] < -0.002 then underRested = underRested + 1 end end
    check(not rebuilt, 'the tape had to be rebuilt to follow the cone')
    check(under == 0 and underRested == 0, ('%d nodes under the road (%d once at rest)'):format(under, underRested))
    check(onRoad > 0, 'the slack tape never reaches the road')
    print(('[holders] cone knocked over: tape followed it (%d nodes kept), %d nodes lie on the road, %d under it  %s'):format(
        c.n, onRoad, under + underRested, fails == before and 'ok' or 'WRONG'))
end

-- 4. Torn at a cone, standing and lying -------------------------------------------------------------
do
    local before = fails
    local cone = holder.get('cone_orange')
    for _, lying in ipairs({ false, true }) do
        local fall = lying and { x = 0, y = 1, s = 0 } or nil
        local pose = holder.pose(cone, 0, 0, 0, 0.0, fall, 1, 1)
        local up = holder.pose(cone, 0, 0, 0, 0.0, nil)
        local tx, ty, tz = holder.point(pose, 0, 0, cone.tie)
        local lx, ly = holder.local_(up, 1, 0, 0)
        local r = cone.tieRadius + 0.004
        local x, y, z = holder.point(pose, lx * r, ly * r, cone.tie)
        local nx, ny, nz = holder.dir(pose, lx, ly, 0)
        local b = cone.body
        local ax_, ay_, az_ = holder.point(pose, 0, 0, b[1])
        local bx_, by_, bz_ = holder.point(pose, 0, 0, b[3])
        local col = sim.staticCapsule(ax_, ay_, az_, bx_, by_, bz_, b[2], b[4])
        local base = cone.base
        local function ground(px, py)
            if not lying and px * px + py * py < (base[1] + 0.005) ^ 2 then return base[2] end
            return 0.0
        end
        local a = sim.newTorn(tx, ty, tz, tx + 6, ty, tz, 0.25, 0.12, 0.1, function(px, py) return ground(px, py) end, P, {
            tieA = { x = x, y = y, z = z, nx = nx, ny = ny, nz = nz }, cols = { col }, ncols = 1,
        })
        -- Inside the cone: closer to its axis than its radius there.
        local inside = 0
        local ux, uy, uz = bx_ - ax_, by_ - ay_, bz_ - az_
        local L = math.sqrt(ux * ux + uy * uy + uz * uz)
        ux, uy, uz = ux / L, uy / L, uz / L
        for i = 2, a.n do
            local vx, vy, vz = a.x[i] - ax_, a.y[i] - ay_, a.z[i] - az_
            local t = vx * ux + vy * uy + vz * uz
            if t > 0 and t < L then
                local px, py, pz = vx - ux * t, vy - uy * t, vz - uz * t
                local rr = b[2] + (b[4] - b[2]) * t / L
                if math.sqrt(px * px + py * py + pz * pz) < rr - 0.002 then inside = inside + 1 end
            end
        end
        check(inside == 0, ('%s: %d nodes inside the cone'):format(lying and 'lying' or 'standing', inside))
        print(('[holders] torn at a %s cone: %d nodes inside it  %s'):format(lying and 'knocked-over' or 'standing',
            inside, inside == 0 and 'ok' or 'WRONG'))
    end
    if fails ~= before then print('  (see above)') end
end

print(fails == 0 and 'all ok' or (fails .. ' failed'))
os.exit(fails == 0 and 0 or 1)
