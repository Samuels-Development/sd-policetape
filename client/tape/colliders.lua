---What tape can bump into: the peds and vehicles near it, in the shapes sim.lua understands.
---
---A ped is a dozen capsules between its bones (torso, hips, legs, arms, head), read every frame,
---so tape wraps around legs and a waist rather than a cylinder.
---
---A vehicle is a height field of its own top and underside, in model space, found once per
---model by casting rays down and up through a live instance (a few dozen rays a frame, so nobody
---sees a hitch). That is what lets tape ride up a bonnet onto a windscreen, or catch under a
---truck's bumper. Until a model's profile is done it is treated as its bounding box.
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

-- { from, to, radius } capsules making up a ped.
local BODY = {
    { B.pelvis, B.spine3, 0.16 },
    { B.spine3, B.neck, 0.15 },
    { B.neck, B.head, 0.11 },
    { B.lThigh, B.rThigh, 0.11 },
    { B.lThigh, B.lCalf, 0.085 },
    { B.lCalf, B.lFoot, 0.06 },
    { B.rThigh, B.rCalf, 0.085 },
    { B.rCalf, B.rFoot, 0.06 },
    { B.lUpper, B.lFore, 0.055 },
    { B.lFore, B.lHand, 0.045 },
    { B.rUpper, B.rFore, 0.055 },
    { B.rFore, B.rHand, 0.045 },
}

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
                if ped == me or not IsPedInAnyVehicle(ped, false) then
                    local p = GetEntityCoords(ped)
                    for i = 1, count do
                        local s = spheres[i]
                        local dx, dy, dz = p.x - s.x, p.y - s.y, p.z - s.z
                        local r = s.r + 3.0
                        if dx * dx + dy * dy + dz * dz < r * r then
                            peds[#peds + 1] = ped
                            break
                        end
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

---Measures a model's real shape from one of its vehicles, a few rays a frame.
local function measure(veh, model, prof)
    CreateThread(function()
        local mn, mx = GetModelDimensions(model)
        local w, l = mx.x - mn.x, mx.y - mn.y
        local nx = max(6, min(12, floor(w / 0.24 + 0.5)))
        local ny = max(12, min(44, floor(l / 0.24 + 0.5)))
        local cx, cy = w / nx, l / ny
        local top, bottom = {}, {}
        local perFrame, done = 24, 0

        for iy = 0, ny - 1 do
            for ix = 0, nx - 1 do
                if not DoesEntityExist(veh) then
                    profiles[model] = nil -- try again with another one
                    return
                end
                local lx = mn.x + (ix + 0.5) * cx
                local ly = mn.y + (iy + 0.5) * cy
                local o, r, f, u = basis(veh)
                local function at(lz) return o + r * lx + f * ly + u * lz end
                local a, b = at(mx.z + 0.5), at(mn.z - 0.6)
                local k = ix + iy * nx + 1

                local hit, pos, ent = ray(a.x, a.y, a.z, b.x, b.y, b.z)
                if hit and ent == veh then
                    top[k] = (pos - o).x * u.x + (pos - o).y * u.y + (pos - o).z * u.z
                    local hit2, pos2, ent2 = ray(b.x, b.y, b.z, a.x, a.y, a.z)
                    if hit2 and ent2 == veh then
                        bottom[k] = (pos2 - o).x * u.x + (pos2 - o).y * u.y + (pos2 - o).z * u.z
                    else
                        bottom[k] = mn.z
                    end
                else
                    top[k] = false
                    bottom[k] = false
                end

                done = done + 1
                if done % perFrame == 0 then Wait(0) end
            end
        end

        prof.nx, prof.ny, prof.cx, prof.cy = nx, ny, cx, cy
        prof.top, prof.bottom = top, bottom
        prof.ready = true
        log.debug('colliders', 'measured %s: %dx%d cells', tostring(model), nx, ny)
    end)
end

local function profileOf(veh)
    local model = GetEntityModel(veh)
    local prof = profiles[model]
    if not prof then
        prof = boxProfile(model)
        profiles[model] = prof
        measure(veh, model, prof)
    end
    return prof
end

-- Per frame -------------------------------------------------------------------------------------

---Builds this frame's colliders from the scanned peds and vehicles.
function colliders.update()
    local list, n = colliders.list, 0
    local me = PlayerPedId()
    local pedGrip = config.Physics.PedGrip or 0.7
    local vehGrip = config.Physics.VehicleGrip or 0.85

    for _, ped in ipairs(pedList) do
        if DoesEntityExist(ped) and not IsPedInAnyVehicle(ped, false) then
            local v = GetEntityVelocity(ped)
            local mine, isPlayer = ped == me, IsPedAPlayer(ped) and true or false
            local pts = {}
            for pi, part in ipairs(BODY) do
                local a = pts[part[1]] or GetPedBoneCoords(ped, part[1], 0.0, 0.0, 0.0)
                local b = pts[part[2]] or GetPedBoneCoords(ped, part[2], 0.0, 0.0, 0.0)
                pts[part[1]], pts[part[2]] = a, b
                local r = part[3]
                local c = slot(ped * 16 + pi)
                c.kind, c.entity, c.mine, c.player, c.grip = 1, ped, mine, isPlayer, pedGrip
                c.ax, c.ay, c.az, c.bx, c.by, c.bz, c.r = a.x, a.y, a.z, b.x, b.y, b.z, r
                c.vx, c.vy, c.vz, c.speed = v.x, v.y, v.z, 0.0
                c.minx, c.maxx = min(a.x, b.x) - r - 0.05, max(a.x, b.x) + r + 0.05
                c.miny, c.maxy = min(a.y, b.y) - r - 0.05, max(a.y, b.y) + r + 0.05
                c.minz, c.maxz = min(a.z, b.z) - r - 0.05, max(a.z, b.z) + r + 0.05
                n = n + 1
                list[n] = c
            end
        end
    end

    for _, veh in ipairs(vehList) do
        if DoesEntityExist(veh) then
            local prof = profileOf(veh)
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
