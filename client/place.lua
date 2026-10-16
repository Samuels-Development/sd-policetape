---Placing tape: aim, click where it starts, click where it is tied off. With Placement.Chain the
---next stretch starts where the last one ended, until Done.
---
---Uses the game's own controls (attack, aim, weapon wheel, phone up/down, detonate), so it works
---the same with a mouse or a controller, and follows whatever the player has bound those to.
local config = require 'configs.config'
local locale = require 'bridge.shared.locale'
local notify = require 'bridge.client.notify'
local holder = require 'shared.holder'
local state = require 'client.state'
local world = require 'client.tape.world'
local nui = require 'client.nui'

local PLACE = config.Placement

local place = { active = false }

-- The holder a new end stands on: the last one this player picked (kept between sessions).
local holderIndex = 1
do
    local saved = GetResourceKvpString('sd-policetape:holder')
    local want = holder.get(saved) or holder.default()
    for i, def in ipairs(holder.list) do
        if def == want then holderIndex = i end
    end
end

local function currentHolder()
    return holder.list[holderIndex] or holder.default()
end

local function nextHolder(step)
    local n = #holder.list
    if n == 0 then return end
    holderIndex = (holderIndex - 1 + step) % n + 1
    SetResourceKvp('sd-policetape:holder', currentHolder().id)
end

-- Controls (https://docs.fivem.net/docs/game-references/controls/)
local C_PLACE = 24 -- INPUT_ATTACK: LMB / RT
local C_DONE = 25 -- INPUT_AIM: RMB / LT
local C_CANCEL = 177 -- INPUT_CELLPHONE_CANCEL: Backspace / B
local C_NEXT, C_PREV = 14, 15 -- INPUT_WEAPON_WHEEL_NEXT / PREV: mouse wheel
local C_NEXT2, C_PREV2 = 173, 172 -- INPUT_CELLPHONE_DOWN / UP: arrows / d-pad
local C_PICKER = 47 -- INPUT_DETONATE: G / d-pad left
local C_HOLDER = 74 -- INPUT_VEH_HEADLIGHT: H / d-pad right (free on foot)

local BLOCK = { 24, 25, 14, 15, 16, 17, 37, 44, 47, 74, 140, 141, 142, 143, 172, 173, 177, 257, 263, 264 }

local function t(key, vars) return locale.t(key, vars) end

local function tell(text, kind)
    notify.show({ title = t('notify.title'), description = text, type = kind or 'error' })
end

local function camDir()
    local rot = GetFinalRenderedCamRot(2)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function ray(from, to, flags, ignore)
    local h = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, flags, ignore, 7)
    local _, hit, pos, normal, ent = GetShapeTestResult(h)
    return hit == 1 or hit == true, pos, normal, ent
end

-- Ghost holders, shown where a new one would stand.
local ghosts = {}

---Shows (or with nil, hides) a see-through `def` standing at ground point `pos`.
local function ghost(slot, pos, def)
    local g = ghosts[slot]
    if g and (not pos or g.def ~= def) then
        DeleteEntity(g.obj)
        ghosts[slot], g = nil, nil
    end
    if not pos then return end
    if not g then
        local model = joaat(def.model)
        if not IsModelInCdimage(model) then return end
        RequestModel(model)
        if not HasModelLoaded(model) then return end
        local obj = CreateObjectNoOffset(model, pos.x, pos.y, pos.z, false, false, false)
        SetEntityAlpha(obj, 150, false)
        SetEntityCollision(obj, false, false)
        FreezeEntityPosition(obj, true)
        SetModelAsNoLongerNeeded(model)
        g = { obj = obj, def = def }
        ghosts[slot] = g
    end
    SetEntityCoordsNoOffset(g.obj, pos.x, pos.y, pos.z, false, false, false)
end

---What is under the crosshair, as a place a tape end could go.
---@return { p: vector3|nil, post: boolean|nil, holder: HolderDef|nil, existing: boolean|nil, ground: vector3|nil, at: vector3|nil, reason: string|nil }
local function aim(ped)
    local cam = GetFinalRenderedCamCoord()
    local dir = camDir()
    local me = GetEntityCoords(ped)
    local reach = PLACE.Reach + #(cam - me)
    local hit, pos, normal, ent = ray(cam, cam + dir * reach, 511, ped)
    if not hit then return { reason = 'no_surface' } end

    -- An existing holder: tie to it.
    local e = world.holderAt(pos.x, pos.y, pos.z, PLACE.PostSnap)
    if e then
        return { p = vector3(e.x, e.y, e.z), post = true, holder = e.def, existing = true }
    end

    if ent ~= 0 and (IsEntityAVehicle(ent) or IsEntityAPed(ent)) then
        return { reason = 'no_surface', at = pos }
    end

    if #(pos - me) > PLACE.Reach then
        return { reason = 'too_far', at = pos }
    end

    if normal.z >= PLACE.GroundSlope then
        if not PLACE.Posts then return { reason = 'no_surface', at = pos } end
        local def = currentHolder()
        return { p = pos + vector3(0.0, 0.0, def.tie), post = true, holder = def, ground = pos }
    end

    -- A wall, fence, pole, tree: tie just off its surface.
    return { p = pos + normal * 0.012, post = false }
end

---Whether a stretch from a to b can be placed, and why not.
local function check(a, b, ped)
    local len = #(b - a)
    if len > PLACE.MaxLength then return false, t('ui.hud.too_long', { max = math.floor(PLACE.MaxLength) }) end
    if len < PLACE.MinLength then return false, t('ui.hud.too_short') end
    -- Nothing solid between the ends (a little short of each, so the walls they are tied to and
    -- the posts they are tied round do not count).
    local d = (b - a) / len
    if len > 0.4 then
        local blocked = ray(a + d * 0.15, b - d * 0.15, 1 + 16, ped)
        if blocked then return false, t('ui.hud.blocked') end
    end
    return true, t('ui.hud.length', { length = ('%.1f'):format(len) })
end

local function keyLabels()
    local kb = IsUsingKeyboard(0)
    return {
        place = kb and 'LMB' or 'RT',
        done = kb and 'RMB' or 'LT',
        style = kb and t('ui.hud.wheel') or t('ui.hud.dpad'),
        picker = kb and 'G' or '←',
        holder = kb and 'H' or '→',
    }
end

-- The roll in the player's hand.
local roll
local function holdRoll(ped)
    local model = joaat(PLACE.RollModel)
    if not IsModelInCdimage(model) then return end
    RequestModel(model)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    roll = CreateObject(model, 0.0, 0.0, 0.0, false, false, false)
    local o, r = PLACE.RollOffset, PLACE.RollRotation
    AttachEntityToEntity(roll, ped, GetPedBoneIndex(ped, PLACE.RollBone), o.x, o.y, o.z, r.x, r.y, r.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
end

local function dropRoll()
    if roll and DoesEntityExist(roll) then DeleteEntity(roll) end
    roll = nil
end

local function stop()
    place.active = false
    world.setPreview(nil)
    ghost('a', nil)
    ghost('b', nil)
    dropRoll()
    nui.hud(nil)
end

---Starts placing. `style` defaults to the one last used.
---@param style? string
function place.start(style)
    if place.active or nui.busy() then return end
    if not state.perms.use then
        tell(t('notify.no_permission'))
        return
    end
    local ped = PlayerPedId()
    if PLACE.OnFoot and IsPedInAnyVehicle(ped, false) then
        tell(t('notify.in_vehicle'))
        return
    end

    style = (style and state.style(style)) and style or state.defaultStyle()
    if not style then return end

    place.active = true
    holdRoll(ped)

    CreateThread(function()
        local a = nil ---@type { p: vector3, post: boolean, holder: HolderDef|nil, existing: boolean|nil }|nil
        local placed = 0
        local busy = false

        while place.active do
            ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedRagdoll(ped) or (PLACE.OnFoot and IsPedInAnyVehicle(ped, false)) then break end

            for i = 1, #BLOCK do DisableControlAction(0, BLOCK[i], true) end

            local target = aim(ped)
            local ok, line, kind = false, nil, 'ok'
            if not target.p then
                line, kind = t('ui.hud.' .. (target.reason or 'no_surface')), 'stop'
            elseif a then
                ok, line = check(a.p, target.p, ped)
                kind = ok and 'ok' or 'stop'
            else
                ok = true
                line = target.post and not target.existing and t('ui.hud.holder_here', { name = target.holder.label }) or nil
            end

            -- Markers: where it starts (if started) and where it would go, green or red.
            local col = ok and { 70, 220, 120 } or { 235, 70, 60 }
            if a then
                DrawMarker(28, a.p.x, a.p.y, a.p.z, 0, 0, 0, 0, 0, 0, 0.06, 0.06, 0.06, 70, 220, 120, 200, false, false, 2, false, nil, nil, false)
            end
            local at = target.p or target.at
            if at then
                DrawMarker(28, at.x, at.y, at.z, 0, 0, 0, 0, 0, 0, 0.07, 0.07, 0.07, col[1], col[2], col[3], 210, false, false, 2, false, nil, nil, false)
            end
            ghost('a', a and a.post and not a.existing and (a.p - vector3(0.0, 0.0, a.holder.tie)) or nil, a and a.holder)
            ghost('b', target.ground and not target.existing and target.ground or nil, target.holder)

            -- The tape itself, live, from the start point to the aim.
            if a and target.p then
                world.setPreview({ style = style, a = a.p, b = target.p, ok = ok })
            else
                world.setPreview(nil)
            end

            local keys = keyLabels()
            local hudKeys = {
                { k = keys.place, t = a and t('ui.hud.tie_off') or t('ui.hud.set_point') },
                { k = keys.style, t = t('ui.hud.style') },
                { k = keys.picker, t = t('ui.hud.all_styles') },
            }
            if PLACE.Posts and #holder.list > 1 then
                hudKeys[#hudKeys + 1] = { k = keys.holder, t = currentHolder().label }
            end
            hudKeys[#hudKeys + 1] = { k = keys.done, t = (a or placed > 0) and t('ui.hud.done') or t('ui.hud.cancel') }
            if not nui.busy() then
                nui.hud({
                    mode = 'place',
                    styleId = style,
                    title = state.style(style) and state.style(style).label or t('ui.hud.placing'),
                    line = line or (a and t('ui.hud.aim_next') or t('ui.hud.aim_first')),
                    lineKind = line and kind or 'ok',
                    keys = hudKeys,
                })
            end

            if not busy and not nui.busy() then
                if IsDisabledControlJustPressed(0, C_PLACE) and ok and target.p then
                    if not a then
                        a = { p = target.p, post = target.post, holder = target.holder, existing = target.existing }
                    else
                        busy = true
                        local b = { p = target.p, post = target.post, holder = target.holder, existing = target.existing }
                        local from = a
                        CreateThread(function()
                            local res = lib.callback.await('sd-policetape:server:place', false, {
                                style = style,
                                a = { x = from.p.x, y = from.p.y, z = from.p.z },
                                b = { x = b.p.x, y = b.p.y, z = b.p.z },
                                ap = from.post == true,
                                bp = b.post == true,
                                ah = from.holder and from.holder.id or nil,
                                bh = b.holder and b.holder.id or nil,
                            })
                            busy = false
                            if type(res) == 'table' and res.ok then
                                placed = placed + 1
                                state.setDefaultStyle(style)
                                PlaySoundFrontend(-1, 'CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE', true)
                                if PLACE.Chain then
                                    -- The end just tied is where the next stretch starts; a post
                                    -- there is now an existing one.
                                    a = { p = b.p, post = b.post, holder = b.holder, existing = b.post }
                                else
                                    place.active = false
                                end
                            elseif type(res) == 'table' and res.reason then
                                tell(res.reason)
                            end
                        end)
                    end
                elseif IsDisabledControlJustPressed(0, C_DONE) or IsDisabledControlJustPressed(0, C_CANCEL) then
                    if a and placed == 0 then
                        a = nil -- back a step: forget the start point
                    else
                        break
                    end
                elseif IsDisabledControlJustPressed(0, C_NEXT) or IsDisabledControlJustPressed(0, C_NEXT2) then
                    style = state.step(style, 1)
                elseif IsDisabledControlJustPressed(0, C_PREV) or IsDisabledControlJustPressed(0, C_PREV2) then
                    style = state.step(style, -1)
                elseif IsDisabledControlJustPressed(0, C_HOLDER) and PLACE.Posts then
                    nextHolder(1)
                elseif IsDisabledControlJustPressed(0, C_PICKER) then
                    local before = style
                    nui.openPicker(style, function(id)
                        style = id or before
                    end, function(id)
                        style = id
                    end)
                end
            end

            Wait(0)
        end

        if nui.busy() then nui.closePicker() end
        stop()
    end)
end

function place.cancel()
    place.active = false
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then stop() end
end)

return place
