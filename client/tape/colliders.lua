---What tape can bump into: the peds and vehicles near it, in the shapes sim.lua understands.
---
---A ped is a dozen capsules between its bones (torso, hips, legs, arms, head), read every frame,
---so tape wraps around legs and a waist rather than a cylinder.
---
---A vehicle is a height field of its own top and underside, in model space, found once per
---model by casting rays down and up through a live instance. That is what lets tape ride up a
---bonnet onto a windscreen, or catch under a truck's bumper. Until a model's profile is done it is
---treated as its bounding box. A ray costs about 50 microseconds, and a model takes hundreds, so
---only models that come up to tape are measured, a few rays a frame, one model at a time, and a
---finished profile is kept on the player's PC (resource KVP) so a model is only ever measured once.
local config = require 'configs.config'
local log = require 'shared.log'

local colliders = {}

local sqrt, max, min, floor = math.sqrt, math.max, math.min, math.floor

-- Bone ids (SKEL_*).
local B = {
    pelvis = 11816, spine3 = 24818, neck = 39317, head = 31086,
    lThigh = 58271, lCalf = 63931, lFoot = 14201,
    rThigh = 51826, rCalf = 36864, rFoot = 52301,
    lUpper = 45509, lFore = 61163, lHand = 18905,
    rUpper = 40269, rFore = 28252, rHand = 57005,
}

-- The bones read, each once a frame, and the { from, to, radius } capsules between them (indexes
-- into BONES) that make up a ped.
local BONES = {
    B.pelvis, B.spine3, B.neck, B.head,
    B.lThigh, B.lCalf, B.lFoot, B.rThigh, B.rCalf, B.rFoot,
    B.lUpper, B.lFore, B.lHand, B.rUpper, B.rFore, B.rHand,
}
local BODY = {
    { 1, 2, 0.16 },   -- pelvis to spine
    { 2, 3, 0.15 },   -- spine to neck
    { 3, 4, 0.11 },   -- neck to head
    { 5, 8, 0.11 },   -- hips
    { 5, 6, 0.085 },  -- left thigh
    { 6, 7, 0.06 },   -- left calf
    { 8, 9, 0.085 },  -- right thigh
    { 9, 10, 0.06 },  -- right calf
    { 11, 12, 0.055 }, -- left upper arm
    { 12, 13, 0.045 }, -- left forearm
    { 14, 15, 0.055 }, -- right upper arm
    { 15, 16, 0.045 }, -- right forearm
}

-- How far a ped's bones (and their capsules) reach from where the game puts the ped, at most:
-- a ped further than this outside every tape's box cannot touch any of them.
local BODY_REACH = 1.3
-- The same for a whole tape, from the straight line between its ends plus however far its tape
-- is from that line right now (the chain's `dev`). A box round a tape that runs diagonally takes in
-- a lot of pavement, and on a busy street the people walking along it.
local LINE_REACH = 1.5

-- This frame's bone positions, reused for every ped.
local bx, by, bz = {}, {}, {}

---@type integer[] peds near a tape, refreshed by scan()
local pedList = {}
---@type integer[]
local vehList = {}

---@type table[] this frame's colliders
colliders.list = {}
colliders.count = 0

---@type table<integer, table> reusable collider tables, by entity then part
local pool = {}

local function slot(key)
    local c = pool[key]
    if not c then
        c = {}
        pool[key] = c
    end
    return c
end

---Which peds and vehicles are near enough to any of `spheres` to matter. Called a few times a
---second, never per frame: the game pools are long.
---@param spheres { x: number, y: number, z: number, r: number }[]
---@param count integer
function colliders.scan(spheres, count)
    local peds, vehs = {}, {}
    if count > 0 then
        local me = PlayerPedId()
        if config.Physics.Peds then
            for _, ped in ipairs(GetGamePool('CPed')) do
                local p = GetEntityCoords(ped)
                for i = 1, count do
                    local s = spheres[i]
                    local dx, dy, dz = p.x - s.x, p.y - s.y, p.z - s.z
                    local r = s.r + 3.0
                    if dx * dx + dy * dy + dz * dz < r * r then
                        -- (only now: most peds in the pool are nowhere near tape)
                        if ped == me or not IsPedInAnyVehicle(ped, false) then peds[#peds + 1] = ped end
                        break
                    end
                end
            end
        end
        if config.Physics.Vehicles then
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                local p = GetEntityCoords(veh)
                for i = 1, count do
                    local s = spheres[i]
                    local dx, dy, dz = p.x - s.x, p.y - s.y, p.z - s.z
                    local r = s.r + 9.0
                    if dx * dx + dy * dy + dz * dz < r * r then
                        vehs[#vehs + 1] = veh
                        break
                    end
                end
            end
        end
    end
    pedList, vehList = peds, vehs
end

-- Vehicle profiles ---------------------------------------------------------------------------

---@type table<integer, table> model hash -> profile
local profiles = {}

---A profile that is just the model's box, until the real one is measured.
local function boxProfile(model)
    local mn, mx = GetModelDimensions(model)
    local prof = {
        minx = mn.x, maxx = mx.x, miny = mn.y, maxy = mx.y, minz = mn.z,
        nx = 1, ny = 1, top = { mx.z }, bottom = { mn.z + 0.25 },
        ready = false,
    }
    prof.cx = prof.maxx - prof.minx
    prof.cy = prof.maxy - prof.miny
    prof.radius = sqrt(max(mn.x * mn.x, mx.x * mx.x) + max(mn.y * mn.y, mx.y * mx.y) + max(mn.z * mn.z, mx.z * mx.z))
    return prof
end

---Model-space basis of an entity: position, right (X), forward (Y), up (Z).
local function basis(ent)
    local o = GetEntityCoords(ent)
    local r = GetOffsetFromEntityInWorldCoords(ent, 1.0, 0.0, 0.0) - o
    local f = GetOffsetFromEntityInWorldCoords(ent, 0.0, 1.0, 0.0) - o
    local u = GetOffsetFromEntityInWorldCoords(ent, 0.0, 0.0, 1.0) - o
    return o, r, f, u
end

local function ray(x1, y1, z1, x2, y2, z2)
    local h = StartExpensiveSynchronousShapeTestLosProbe(x1, y1, z1, x2, y2, z2, 2, 0, 7)
    local _, hit, pos, _, ent = GetShapeTestResult(h)
    return hit == 1 or hit == true, pos, ent
end

-- Measuring ---------------------------------------------------------------------------------------

local RAYS_PER_FRAME = 3      -- about 0.15 ms a frame while a model is being measured
local KVP_PREFIX = 'sdtape:vehprof:v1:'

---@type table<integer, { veh: integer, seen: integer }> models waiting to be measured
local queue = {}
local measuring = false

---A finished profile kept from an earlier session, or nil.
local function loadSaved(model)
    local raw = GetResourceKvpString(KVP_PREFIX .. model)
    local ok, saved = pcall(json.decode, raw or '')
    if not ok or type(saved) ~= 'table' or not saved.nx or not saved.top or not saved.bottom then return nil end
    -- (json has no false: an empty cell was saved as -1000, below any real height)
    for k = 1, saved.nx * saved.ny do
        if saved.top[k] == nil or saved.top[k] <= -999 then saved.top[k], saved.bottom[k] = false, false end
    end
    return saved
end

local function save(model, prof)
    local top, bottom = {}, {}
    for k = 1, prof.nx * prof.ny do
        top[k], bottom[k] = prof.top[k] or -1000, prof.bottom[k] or -1000
    end
    SetResourceKvp(KVP_PREFIX .. model, json.encode({ nx = prof.nx, ny = prof.ny, cx = prof.cx, cy = prof.cy, top = top, bottom = bottom }))
end

---One cell of a model's profile: a ray down onto it, and one up into its underside.
---@return integer rays cast
local function measureCell(veh, m, k)
    local ix, iy = (k - 1) % m.nx, (k - 1) // m.nx
    local lx = m.mnx + (ix + 0.5) * m.cx
    local ly = m.mny + (iy + 0.5) * m.cy
    local o, r, f, u = basis(veh)
    local function at(lz) return o + r * lx + f * ly + u * lz end
    local a, b = at(m.mxz + 0.5), at(m.mnz - 0.6)

    local hit, pos, ent = ray(a.x, a.y, a.z, b.x, b.y, b.z)
    if not (hit and ent == veh) then
        m.top[k], m.bottom[k] = false, false
        return 1
    end
    m.top[k] = (pos - o).x * u.x + (pos - o).y * u.y + (pos - o).z * u.z
    local hit2, pos2, ent2 = ray(b.x, b.y, b.z, a.x, a.y, a.z)
    m.bottom[k] = (hit2 and ent2 == veh) and ((pos2 - o).x * u.x + (pos2 - o).y * u.y + (pos2 - o).z * u.z) or m.mnz
    return 2
end

---Works through the queue, RAYS_PER_FRAME rays a frame, one model at a time. A model's progress
---is kept on its profile, so when its vehicle drives off the next one of that model carries on.
local function runQueue()
    if measuring then return end
    measuring = true
    CreateThread(function()
        while true do
            local model, entry
            for m, e in pairs(queue) do
                if DoesEntityExist(e.veh) and GetEntityModel(e.veh) == m then
                    model, entry = m, e
                    break
                end
                -- Not seen near tape for a minute: forget it until one comes back.
                if GetGameTimer() - e.seen > 60000 then queue[m] = nil end
            end
            if not model then break end

            local prof = profiles[model]
            local m = prof.measure
            if not m then
                local mn, mx = GetModelDimensions(model)
                local w, l = mx.x - mn.x, mx.y - mn.y
                local nx = max(6, min(12, floor(w / 0.24 + 0.5)))
                local ny = max(12, min(44, floor(l / 0.24 + 0.5)))
                m = { nx = nx, ny = ny, cx = w / nx, cy = l / ny, mnx = mn.x, mny = mn.y, mnz = mn.z, mxz = mx.z, top = {}, bottom = {}, next = 1 }
                prof.measure = m
            end

            local rays = 0
            while rays < RAYS_PER_FRAME and m.next <= m.nx * m.ny and DoesEntityExist(entry.veh) do
                rays = rays + measureCell(entry.veh, m, m.next)
                m.next = m.next + 1
            end

            if m.next > m.nx * m.ny then
                prof.nx, prof.ny, prof.cx, prof.cy = m.nx, m.ny, m.cx, m.cy
                prof.top, prof.bottom = m.top, m.bottom
                prof.measure = nil
                prof.ready = true
                queue[model] = nil
                save(model, prof)
                log.debug('colliders', 'measured %s: %dx%d cells', tostring(model), m.nx, m.ny)
            end
            Wait(0)
        end
        measuring = false
    end)
end

local function profileOf(veh)
    local model = GetEntityModel(veh)
    local prof = profiles[model]
    if not prof then
        prof = boxProfile(model)
        local saved = loadSaved(model)
        if saved then
            prof.nx, prof.ny, prof.cx, prof.cy = saved.nx, saved.ny, saved.cx, saved.cy
            prof.top, prof.bottom = saved.top, saved.bottom
            prof.ready = true
        end
        profiles[model] = prof
    end
    return prof
end

---For `sdtape_dbg`: vehicle models known, measured, waiting, and the one part-measured.
function colliders.profileStats()
    local known, ready, waiting, partial = 0, 0, 0, nil
    for _, prof in pairs(profiles) do
        known = known + 1
        if prof.ready then ready = ready + 1 end
        if prof.measure then partial = ('%d/%d cells'):format(prof.measure.next - 1, prof.measure.nx * prof.measure.ny) end
    end
    for _ in pairs(queue) do waiting = waiting + 1 end
    return known, ready, waiting, partial
end

---A vehicle of an unmeasured model is up against tape: measure that model.
local function wantMeasured(veh, prof)
    if prof.ready then return end
    local model = GetEntityModel(veh)
    local e = queue[model]
    if e then
        e.veh, e.seen = veh, GetGameTimer()
    else
        queue[model] = { veh = veh, seen = GetGameTimer() }
    end
    runQueue()
end

-- Per frame -------------------------------------------------------------------------------------

---Whether a point is within `pad` of any of the boxes (minx..maxz fields).
---@param boxes table[]
---@param nboxes integer
local function inBoxes(boxes, nboxes, x, y, z, pad)
    for i = 1, nboxes do
        local t = boxes[i]
        if x > t.minx - pad and x < t.maxx + pad and y > t.miny - pad and y < t.maxy + pad
            and z > t.minz - pad and z < t.maxz + pad then
            return true
        end
    end
    return false
end

---Whether a ped at x, y, z could touch tape in one of `boxes`: inside a box, and for a whole tape
---(a box with `lineChain`) near the line between its ends as well.
local function bodyReaches(boxes, nboxes, x, y, z)
    local pad = BODY_REACH
    for i = 1, nboxes do
        local t = boxes[i]
        if x > t.minx - pad and x < t.maxx + pad and y > t.miny - pad and y < t.maxy + pad
            and z > t.minz - pad and z < t.maxz + pad then
            local c = t.lineChain
            if not c then return true end
            local n = c.n
            local ax, ay = c.x[1], c.y[1]
            local dx, dy = c.x[n] - ax, c.y[n] - ay
            local l2 = dx * dx + dy * dy
            if l2 < 0.01 then return true end
            local u = ((x - ax) * dx + (y - ay) * dy) / l2
            u = u < 0.0 and 0.0 or (u > 1.0 and 1.0 or u)
            local ex, ey = ax + dx * u - x, ay + dy * u - y
            local r = LINE_REACH + c.dev
            if ex * ex + ey * ey < r * r then return true end
        end
    end
    return false
end

---Builds this frame's colliders from the scanned peds and vehicles. A ped is only built where
---its body can reach one of `boxes` (the tapes this frame, as minx..maxz): its sixteen bones are
---most of what this costs, and a ped a few metres from tape cannot touch it.
---@param boxes table[]
---@param nboxes integer
function colliders.update(boxes, nboxes)
    local list, n = colliders.list, 0
    local me = PlayerPedId()
    local pedGrip = config.Physics.PedGrip or 0.7
    local vehGrip = config.Physics.VehicleGrip or 0.85

    for _, ped in ipairs(pedList) do
        local at = GetEntityCoords(ped)
        if bodyReaches(boxes, nboxes, at.x, at.y, at.z) and DoesEntityExist(ped)
            and not IsPedInAnyVehicle(ped, false) then
            local v = GetEntityVelocity(ped)
            local mine, isPlayer = ped == me, IsPedAPlayer(ped) and true or false
            for k = 1, #BONES do
                local p = GetPedBoneCoords(ped, BONES[k], 0.0, 0.0, 0.0)
                bx[k], by[k], bz[k] = p.x, p.y, p.z
            end
            for pi = 1, #BODY do
                local part = BODY[pi]
                local ia, ib, r = part[1], part[2], part[3]
                local ax, ay, az, ex, ey, ez = bx[ia], by[ia], bz[ia], bx[ib], by[ib], bz[ib]
                local c = slot(ped * 16 + pi)
                c.kind, c.entity, c.mine, c.player, c.grip = 1, ped, mine, isPlayer, pedGrip
                c.ax, c.ay, c.az, c.bx, c.by, c.bz, c.r = ax, ay, az, ex, ey, ez, r
                c.vx, c.vy, c.vz, c.speed = v.x, v.y, v.z, 0.0
                c.minx, c.maxx = min(ax, ex) - r - 0.05, max(ax, ex) + r + 0.05
                c.miny, c.maxy = min(ay, ey) - r - 0.05, max(ay, ey) + r + 0.05
                c.minz, c.maxz = min(az, ez) - r - 0.05, max(az, ez) + r + 0.05
                n = n + 1
                list[n] = c
            end
        end
    end

    -- A vehicle only once it is within its own size and a bit of a tape's box (which takes in the
    -- posts): close enough to touch the tape, knock a post or need to pass through one.
    for _, veh in ipairs(vehList) do
        local prof = DoesEntityExist(veh) and profileOf(veh)
        local at = prof and GetEntityCoords(veh)
        if prof and inBoxes(boxes, nboxes, at.x, at.y, at.z, prof.radius + 2.5) then
            wantMeasured(veh, prof)
            local o, r, f, u = basis(veh)
            local v = GetEntityVelocity(veh)
            local c = slot(-veh)
            c.kind, c.entity, c.prof, c.grip = 2, veh, prof, vehGrip
            c.ox, c.oy, c.oz = o.x, o.y, o.z
            c.rx, c.ry, c.rz = r.x, r.y, r.z
            c.fx, c.fy, c.fz = f.x, f.y, f.z
            c.ux, c.uy, c.uz = u.x, u.y, u.z
            c.vx, c.vy, c.vz = v.x, v.y, v.z
            c.speed = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
            local rad = prof.radius + 0.1
            c.minx, c.maxx, c.miny, c.maxy, c.minz, c.maxz = o.x - rad, o.x + rad, o.y - rad, o.y + rad, o.z - rad, o.z + rad
            n = n + 1
            list[n] = c
        end
    end

    for i = n + 1, colliders.count do list[i] = nil end
    colliders.count = n
end

---Forgets reusable tables of entities that are gone (call now and then).
function colliders.tidy()
    for key, c in pairs(pool) do
        if not DoesEntityExist(c.entity or 0) then pool[key] = nil end
    end
end

return colliders
