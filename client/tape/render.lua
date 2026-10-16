---Draws a simulated chain as a flat printed ribbon.
---
---The physics (sim.lua) knows only points. Everything that makes it look like tape is here:
---
---  sway     wind moves a tape sideways and twists it, added on top of the physics as a
---           function of time, so a tape nobody touches costs no simulation at all
---  ribbon   a width direction per node, kept "up" where it can be and carried along the tape
---           (parallel transport) where the tape turns vertical; where something presses on the
---           tape, its face turns to lie against that thing
---  print    one repeat of the print every Config.Tape.Repeat metres of tape MATERIAL (the
---           print stretches with the tape), a quad split at each repeat seam, and a mip level
---           of the atlas per segment by how big it is on screen
---  light    drawn sprites are unlit, so they are shaded here: by the clock, and per triangle by
---           which way the ribbon faces
---
---Drawn with DRAW_TEXTURED_POLY (DrawSpritePoly). Its three-colour sibling would shade per vertex,
---but on build 3258 it draws a runtime (DUI) texture as solid black whatever the colours, so the
---shading here is one colour per triangle: with 25 cm segments nobody can tell.
local render = {}

local sqrt, sin, cos, floor, abs, min, max, log = math.sqrt, math.sin, math.cos, math.floor, math.abs, math.min, math.max, math.log
local PI = math.pi
local LN2 = log(2)

local DrawSpritePoly = DrawSpritePoly

-- Scratch arrays, reused by every chain every frame.
local qx, qy, qz = {}, {}, {}      -- drawn positions
local wx, wy, wz = {}, {}, {}      -- width direction (unit)
local nx, ny, nz = {}, {}, {}      -- face normal (unit)
local lit = {}                     -- 0..255 brightness per node
local idx = {}                     -- the nodes drawn this time

---Which triangle order is drawn. The engine culls back faces: checked in game on build 3258,
---'ccw' (counter-clockwise as the camera sees it, which is what quad() emits) shows and 'cw'
---vanishes. 'both' doubles the draw calls and is only for checking a new game build
---(the command `sdtape_dbg winding both`).
render.winding = 'ccw'

---Per-frame constants, filled by world.lua once a frame.
---@class TapeFrame
---@field cx number camera
---@field cy number
---@field cz number
---@field lodK number atlas texels per screen pixel, per metre of distance (level 1)
---@field time number seconds
---@field windX number unit horizontal wind direction
---@field windY number
---@field windSpeed number m/s, after the config's strength
---@field flutter number radians of twist at full gust
---@field light number 0..1 overall brightness (time of day / interior)
---@field lx number direction towards the sun (unit)
---@field ly number
---@field lz number
---@field shading boolean
---@field mirror boolean
---@field halfWidth number
---@field repeatLen number
---@field txd string
---@field txn string
local frame = {}
render.frame = frame

---Wind displacement for one node. `e` is 0 where the tape is held and 1 where it is free.
local function sway(e, s, phase, tx, ty)
    local f = frame
    if e <= 0.0 or f.windSpeed <= 0.0 then return 0.0, 0.0, 0.0 end
    -- Sideways to the tape, the way the wind blows.
    local dx, dy = -ty, tx
    local l = sqrt(dx * dx + dy * dy)
    if l < 1e-4 then return 0.0, 0.0, 0.0 end
    dx, dy = dx / l, dy / l
    local side = dx * f.windX + dy * f.windY
    if side < 0.0 then dx, dy, side = -dx, -dy, -side end
    local t = f.time
    -- A lean downwind that breathes with the gusts, and a wave running along the tape.
    local gust = 0.62 + 0.38 * sin(t * 0.73 + phase) * sin(t * 0.31 + phase * 1.7)
    local amp = f.windSpeed * 0.012 * (0.35 + 0.65 * side)
    local lean = amp * gust
    local wave = amp * 0.32 * sin(t * 3.4 - s * 2.3 + phase)
    local off = (lean + wave) * e
    local lift = amp * 0.22 * e * sin(t * 2.1 - s * 1.7 + phase * 0.5)
    return dx * off, dy * off, lift
end

---Twist from gusts, in radians, for a node.
local function twist(e, s, phase)
    local f = frame
    if e <= 0.0 or f.flutter <= 0.0 then return 0.0 end
    return e * f.flutter * (0.6 * sin(f.time * 5.1 + s * 2.9 + phase) + 0.4 * sin(f.time * 8.3 - s * 4.1 + phase * 2.3))
end

---Emits one triangle, in the order(s) the engine is known (or not yet known) to show.
local function tri(x1, y1, z1, x2, y2, z2, x3, y3, z3, c1, c2, c3, a, u1, v1, u2, v2, u3, v3)
    local f = frame
    local w = render.winding
    local c = (c1 + c2 + c3) // 3
    -- quad() picks the order for both its triangles at once, but a quad that twists (where tape
    -- turns flat onto the ground or a bonnet, or flutters in a gust) is not flat, and from some
    -- angles one of its triangles then faces away and is culled: a hole. So each triangle is
    -- turned to face the camera itself.
    local ex, ey, ez = x2 - x1, y2 - y1, z2 - z1
    local gx, gy, gz = x3 - x1, y3 - y1, z3 - z1
    if (ey * gz - ez * gy) * (f.cx - x1) + (ez * gx - ex * gz) * (f.cy - y1) + (ex * gy - ey * gx) * (f.cz - z1) < 0.0 then
        x2, y2, z2, x3, y3, z3 = x3, y3, z3, x2, y2, z2
        u2, v2, u3, v3 = u3, v3, u2, v2
    end
    if w ~= 'cw' then
        DrawSpritePoly(x1, y1, z1, x2, y2, z2, x3, y3, z3, c, c, c, a, f.txd, f.txn, u1, v1, 1.0, u2, v2, 1.0, u3, v3, 1.0)
    end
    if w ~= 'ccw' then
        DrawSpritePoly(x1, y1, z1, x3, y3, z3, x2, y2, z2, c, c, c, a, f.txd, f.txn, u1, v1, 1.0, u3, v3, 1.0, u2, v2, 1.0)
    end
end

---Draws one quad of ribbon between material coordinates sa and sb, which lie inside one repeat
---of the print (tile index k). Corners: top/bottom at a, top/bottom at b.
local function quad(ax, ay, az, awx, awy, awz, bx, by, bz, bwx, bwy, bwz, ca, cb, sa, sb, k, uv, front, alpha)
    local f = frame
    local R = f.repeatLen
    local ua = sa / R - k
    local ub = sb / R - k
    if not front and f.mirror then ua, ub = 1.0 - ua, 1.0 - ub end
    local u0, v0, u1, v1 = uv[1], uv[2], uv[3], uv[4]
    local du = u1 - u0
    ua, ub = u0 + ua * du, u0 + ub * du

    local hw = f.halfWidth
    local tax, tay, taz = ax + awx * hw, ay + awy * hw, az + awz * hw
    local bax, bay, baz = ax - awx * hw, ay - awy * hw, az - awz * hw
    local tbx, tby, tbz = bx + bwx * hw, by + bwy * hw, bz + bwz * hw
    local bbx, bby, bbz = bx - bwx * hw, by - bwy * hw, bz - bwz * hw

    -- "front" means the camera is on the side the face normal points to; the two triangles are
    -- then counter-clockwise as the camera sees them.
    if front then
        tri(tax, tay, taz, bax, bay, baz, bbx, bby, bbz, ca, ca, cb, alpha, ua, v0, ua, v1, ub, v1)
        tri(tax, tay, taz, bbx, bby, bbz, tbx, tby, tbz, ca, cb, cb, alpha, ua, v0, ub, v1, ub, v0)
    else
        tri(tax, tay, taz, bbx, bby, bbz, bax, bay, baz, ca, cb, ca, alpha, ua, v0, ub, v1, ua, v1)
        tri(tax, tay, taz, tbx, tby, tbz, bbx, bby, bbz, ca, cb, cb, alpha, ua, v0, ub, v0, ub, v1)
    end
end

---How free each node is to move in the wind: 0 at a tie, rising to 1 a metre or so away.
---@param c table chain
---@param i integer
---@return number
local function freedom(c, i)
    local n = c.n
    local s = c.s[i] - c.s[1]
    local total = c.s[n] - c.s[1]
    if c.kind == 'span' then
        return sin(PI * s / total)
    end
    -- A torn half: free from the tie outwards, still where it lies on the ground.
    local fromTie = c.pin[1] and s or (total - s)
    local e = min(1.0, fromTie / 1.2)
    local above = c.z[i] - c.ground[i]
    if above < 0.25 then e = e * max(0.0, above / 0.25) end
    return e
end

---Draws a chain. `uv` is the atlas rectangles of its style (atlas.acquire).
---@param c table
---@param uv table<integer, number[]>
---@param phase number per-tape random phase, so neighbouring tapes do not sway in step
---@param alpha integer 0..255
---@param stride? integer draw every stride-th node (far away, the shape needs fewer)
function render.chain(c, uv, phase, alpha, stride)
    local f = frame
    local n = c.n
    local x, y, z, s = c.x, c.y, c.z, c.s

    -- The nodes drawn: all of them close up, fewer further away, the last one always.
    stride = stride or 1
    local m = 0
    for i = 1, n, stride do
        m = m + 1
        idx[m] = i
    end
    if idx[m] ~= n then
        m = m + 1
        idx[m] = n
    end

    -- 1. Where each node is drawn: physics plus wind.
    local ex, ey = x[n] - x[1], y[n] - y[1]
    local el = sqrt(ex * ex + ey * ey)
    local tx, ty = 1.0, 0.0
    if el > 1e-4 then tx, ty = ex / el, ey / el end
    for k = 1, m do
        local i = idx[k]
        local e = c.pin[i] and 0.0 or freedom(c, i)
        local ox, oy, oz = sway(e, s[i], phase, tx, ty)
        -- Something pressing on the tape holds it still.
        local hold = 1.0 - (c.cw[i] or 0.0)
        qx[i], qy[i], qz[i] = x[i] + ox * hold, y[i] + oy * hold, z[i] + oz * hold
    end

    -- 2. The ribbon's width direction and face normal at each node.
    local pwx, pwy, pwz = 0.0, 0.0, 1.0
    for k = 1, m do
        local i = idx[k]
        local a, b = idx[k > 1 and k - 1 or 1], idx[k < m and k + 1 or m]
        local ttx, tty, ttz = qx[b] - qx[a], qy[b] - qy[a], qz[b] - qz[a]
        local tl = sqrt(ttx * ttx + tty * tty + ttz * ttz)
        if tl < 1e-6 then ttx, tty, ttz, tl = 1.0, 0.0, 0.0, 1.0 end
        ttx, tty, ttz = ttx / tl, tty / tl, ttz / tl

        -- Up, made square to the tape...
        local ux, uy, uz = -ttz * ttx, -ttz * tty, 1.0 - ttz * ttz
        local ul = sqrt(ux * ux + uy * uy + uz * uz)
        if ul > 0.35 then
            ux, uy, uz = ux / ul, uy / ul, uz / ul
        else
            -- ...unless the tape hangs nearly straight down: then the last direction, carried on.
            local d = pwx * ttx + pwy * tty + pwz * ttz
            ux, uy, uz = pwx - ttx * d, pwy - tty * d, pwz - ttz * d
            ul = sqrt(ux * ux + uy * uy + uz * uz)
            if ul < 1e-5 then ux, uy, uz, ul = -tty, ttx, 0.0, 1.0 end
            ux, uy, uz = ux / ul, uy / ul, uz / ul
        end

        -- Pressed against something: the face turns to lie against it.
        local cw = c.cw[i] or 0.0
        if cw > 0.02 then
            local cnx, cny, cnz = c.cnx[i], c.cny[i], c.cnz[i]
            local px_, py_, pz_ = cny * ttz - cnz * tty, cnz * ttx - cnx * ttz, cnx * tty - cny * ttx
            local pl = sqrt(px_ * px_ + py_ * py_ + pz_ * pz_)
            if pl > 1e-4 then
                px_, py_, pz_ = px_ / pl, py_ / pl, pz_ / pl
                -- Which way round: the side "up" is on. Lying flat (on the ground, a bonnet) the
                -- two are square to each other and that sign is rounding noise, which turned
                -- neighbouring nodes opposite ways (holes) and flipped them frame to frame
                -- (flicker). Then the side the ribbon before it is on, and failing that (where
                -- hanging tape turns flat) the way it already points.
                local side = px_ * ux + py_ * uy + pz_ * uz
                if abs(side) < 0.05 then
                    side = px_ * pwx + py_ * pwy + pz_ * pwz
                    if abs(side) < 0.05 then side = 1.0 end
                end
                if side < 0.0 then px_, py_, pz_ = -px_, -py_, -pz_ end
                ux, uy, uz = ux + (px_ - ux) * cw, uy + (py_ - uy) * cw, uz + (pz_ - uz) * cw
                ul = sqrt(ux * ux + uy * uy + uz * uz)
                ux, uy, uz = ux / ul, uy / ul, uz / ul
            end
        end

        -- Gust twist about the tape's own axis.
        local th = c.pin[i] and 0.0 or twist(freedom(c, i) * (1.0 - cw), s[i], phase)
        if th ~= 0.0 then
            local ct, st = cos(th), sin(th)
            local cx_, cy_, cz_ = tty * uz - ttz * uy, ttz * ux - ttx * uz, ttx * uy - tty * ux
            ux, uy, uz = ux * ct + cx_ * st, uy * ct + cy_ * st, uz * ct + cz_ * st
        end

        wx[i], wy[i], wz[i] = ux, uy, uz
        pwx, pwy, pwz = ux, uy, uz
        nx[i], ny[i], nz[i] = tty * uz - ttz * uy, ttz * ux - ttx * uz, ttx * uy - tty * ux

        -- Light: brighter facing the sun, never black on the shady side (sky light).
        local bright = f.light
        if f.shading then
            local d = abs(nx[i] * f.lx + ny[i] * f.ly + nz[i] * f.lz)
            bright = bright * (0.68 + 0.32 * d)
        end
        lit[i] = floor(min(255.0, bright * 255.0))
    end

    -- 3. Quads, segment by segment.
    local R = f.repeatLen
    local cxp, cyp, czp = f.cx, f.cy, f.cz
    local lodK = f.lodK
    for k = 1, m - 1 do
        local i, j = idx[k], idx[k + 1]
        local mx, my, mz = (qx[i] + qx[j]) * 0.5, (qy[i] + qy[j]) * 0.5, (qz[i] + qz[j]) * 0.5
        local vx, vy, vz = cxp - mx, cyp - my, czp - mz
        local d = sqrt(vx * vx + vy * vy + vz * vz)

        -- Mip level: how many atlas texels land on one screen pixel at this distance.
        local ratio = lodK * d
        local level = 1
        if ratio > 1.5 then level = min(4, 1 + floor(log(ratio / 1.5) / LN2 + 1.0)) end
        local rect = uv[level]

        local front = (nx[i] + nx[j]) * vx + (ny[i] + ny[j]) * vy + (nz[i] + nz[j]) * vz >= 0.0

        -- One quad per repeat of the print the segment covers: split at every seam.
        local sa, sb = s[i], s[j]
        local ax, ay, az, awx, awy, awz, ca = qx[i], qy[i], qz[i], wx[i], wy[i], wz[i], lit[i]
        local from = sa
        local tile = floor(sa / R)
        local last = floor(sb / R - 1e-7)
        while tile < last do
            local sm = (tile + 1) * R
            local t = (sm - sa) / (sb - sa)
            local kx, ky, kz = qx[i] + (qx[j] - qx[i]) * t, qy[i] + (qy[j] - qy[i]) * t, qz[i] + (qz[j] - qz[i]) * t
            local kwx, kwy, kwz = wx[i] + (wx[j] - wx[i]) * t, wy[i] + (wy[j] - wy[i]) * t, wz[i] + (wz[j] - wz[i]) * t
            local kl = sqrt(kwx * kwx + kwy * kwy + kwz * kwz)
            if kl > 1e-6 then kwx, kwy, kwz = kwx / kl, kwy / kl, kwz / kl end
            local kc = floor(lit[i] + (lit[j] - lit[i]) * t)
            quad(ax, ay, az, awx, awy, awz, kx, ky, kz, kwx, kwy, kwz, ca, kc, from, sm, tile, rect, front, alpha)
            ax, ay, az, awx, awy, awz, ca, from = kx, ky, kz, kwx, kwy, kwz, kc, sm
            tile = tile + 1
        end
        quad(ax, ay, az, awx, awy, awz, qx[j], qy[j], qz[j], wx[j], wy[j], wz[j], ca, lit[j], from, sb, tile, rect, front, alpha)
    end
end

---Draws the turns of tape tied round a post: a short band circling the post at the tie, its
---print running round with it.
---@param px number @param py number @param pz number centre of the post at the tie height
---@param radius number
---@param heading number radians, where the band starts (towards the tape)
---@param uv table<integer, number[]>
---@param alpha integer
---@param ux? number the post's axis (default straight up; a knocked-over one lies along another)
---@param uy? number
---@param uz? number
function render.wrap(px, py, pz, radius, heading, uv, alpha, ux, uy, uz)
    local f = frame
    local steps = 10
    local vx, vy, vz = f.cx - px, f.cy - py, f.cz - pz
    local d = sqrt(vx * vx + vy * vy + vz * vz)
    local ratio = f.lodK * d
    local level = 1
    if ratio > 1.5 then level = min(4, 1 + floor(log(ratio / 1.5) / LN2 + 1.0)) end
    local rect = uv[level]
    local c = floor(min(255.0, f.light * 0.92 * 255.0))
    local circumference = 2 * PI * radius
    local R = f.repeatLen

    -- The band's frame: e1 towards the tape (square to the axis), e2 = axis x e1.
    ux, uy, uz = ux or 0.0, uy or 0.0, uz or 1.0
    local hx, hy = cos(heading), sin(heading)
    local dd = hx * ux + hy * uy
    local e1x, e1y, e1z = hx - ux * dd, hy - uy * dd, -uz * dd
    local l = sqrt(e1x * e1x + e1y * e1y + e1z * e1z)
    if l < 1e-4 then
        e1x, e1y, e1z = uy, -ux, 0.0
        l = sqrt(e1x * e1x + e1y * e1y)
        if l < 1e-4 then e1x, e1y, e1z, l = 1.0, 0.0, 0.0, 1.0 end
    end
    e1x, e1y, e1z = e1x / l, e1y / l, e1z / l
    local e2x, e2y, e2z = uy * e1z - uz * e1y, uz * e1x - ux * e1z, ux * e1y - uy * e1x

    for i = 0, steps - 1 do
        local a0 = (i / steps) * 2 * PI
        local a1 = ((i + 1) / steps) * 2 * PI
        local c0, s0, c1, s1 = cos(a0), sin(a0), cos(a1), sin(a1)
        local n0x, n0y, n0z = e1x * c0 + e2x * s0, e1y * c0 + e2y * s0, e1z * c0 + e2z * s0
        local n1x, n1y, n1z = e1x * c1 + e2x * s1, e1y * c1 + e2y * s1, e1z * c1 + e2z * s1
        -- Only the outside of the band is ever seen.
        if (n0x + n1x) * vx + (n0y + n1y) * vy + (n0z + n1z) * vz >= 0.0 then
            local sa = (i / steps) * circumference
            local sb = ((i + 1) / steps) * circumference
            quad(px + n0x * radius, py + n0y * radius, pz + n0z * radius, ux, uy, uz,
                px + n1x * radius, py + n1y * radius, pz + n1z * radius, ux, uy, uz,
                c, c, sa, sb, floor(sa / R), rect, true, alpha)
        end
    end
end

return render
