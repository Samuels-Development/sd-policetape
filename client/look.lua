---Looking at a tape: a text prompt says it can be edited, and the edit key opens its popup (its
---name and print, change its style, hold to take it down). A knocked-over post or cone works the
---same way: the prompt, then the popup, then hold to stand it back up. Nothing pops up just for
---walking past. Both keys are rebindable (Settings > Key Bindings > FiveM) and each has a
---controller binding as well.
local config = require 'configs.config'
local locale = require 'bridge.shared.locale'
local state = require 'client.state'
local world = require 'client.tape.world'
local nui = require 'client.nui'
local place = require 'client.place'

local KEYS = config.Keys
local HOLD = config.Holders or {}
local look = { tape = nil }

local C_CLOSE = 177 -- INPUT_CELLPHONE_CANCEL: Backspace / B
local LOSE_MS = 700 -- the popup stays this long once its tape has left the crosshair

local function t(key, vars) return locale.t(key, vars) end

local holding, pressed = false, false
local progress = 0.0

RegisterCommand('+sdtape_remove', function() holding, pressed = true, true end, false)
RegisterCommand('-sdtape_remove', function() holding = false end, false)
RegisterKeyMapping('+sdtape_remove', 'Police tape: edit, hold to take down', 'keyboard', KEYS.Remove)
RegisterCommand('+sdtape_remove_pad', function() holding, pressed = true, true end, false)
RegisterCommand('-sdtape_remove_pad', function() holding = false end, false)
RegisterKeyMapping('+sdtape_remove_pad', 'Police tape: edit, hold to take down (controller)', 'PAD_DIGITALBUTTON', KEYS.PadRemove)

-- The popup that is up: for a tape (`id`) or for the holder at end `which` of tape `id`. A hold
-- only counts once the key has been let go since the popup opened (`armed`), so the press that
-- opens it never takes the tape down as well.
local edit = nil ---@type { kind: 'tape'|'fallen', id: integer, which: string|nil, label: string|nil, armed: boolean, lostAt: integer|nil }|nil

local function restyle()
    if not edit or edit.kind ~= 'tape' or nui.busy() or place.active then return end
    local tape = world.get(edit.id)
    if not tape then return end
    local id = tape.id
    nui.openPicker(tape.style, function(style)
        if style and style ~= tape.style then
            TriggerServerEvent('sd-policetape:server:restyle', id, style)
        end
    end)
end

RegisterCommand('sdtape_restyle', restyle, false)
RegisterKeyMapping('sdtape_restyle', 'Police tape: change style of the tape you are editing', 'keyboard', KEYS.Restyle)
RegisterCommand('sdtape_restyle_pad', restyle, false)
RegisterKeyMapping('sdtape_restyle_pad', 'Police tape: change style (controller)', 'PAD_DIGITALBUTTON', KEYS.PadRestyle)

---Whether players may say per tape if it survives a restart (the admin menu can change both).
local function choosing()
    return config.Persist == true and config.PersistChoice ~= false
end

local function togglePersist()
    if not edit or edit.kind ~= 'tape' or nui.busy() or place.active or not choosing() then return end
    local tape = world.get(edit.id)
    if tape then TriggerServerEvent('sd-policetape:server:persist', tape.id, not tape.persist) end
end

RegisterCommand('sdtape_persist', togglePersist, false)
RegisterKeyMapping('sdtape_persist', 'Police tape: keep the tape you are editing after a restart, or not', 'keyboard', KEYS.Persist or 'F')
RegisterCommand('sdtape_persist_pad', togglePersist, false)
RegisterKeyMapping('sdtape_persist_pad', 'Police tape: keep it after a restart, or not (controller)', 'PAD_DIGITALBUTTON', KEYS.PadPersist or 'RUP_INDEX')

---The key a command is bound to right now, as the game would print it ("E", "G"), or the
---configured default when it cannot tell.
local function boundKey(command, fallback)
    local ok, label = pcall(GetControlInstructionalButton, 0, joaat(command) | 0x80000000, true)
    if ok and type(label) == 'string' and label:sub(1, 2) == 't_' then return label:sub(3) end
    return fallback
end

local FRIENDLY = { LMENU = 'Alt', RMENU = 'Alt Gr', LCONTROL = 'Ctrl', LSHIFT = 'Shift', BACK = 'Backspace', DELETE = 'Del' }

local function keyName(command, default, padCommand, padDefault)
    if not IsUsingKeyboard(0) then
        local pad = { LDOWN_INDEX = '↓', LLEFT_INDEX = '←', LUP_INDEX = '↑', LRIGHT_INDEX = '→', RUP_INDEX = 'Y', RDOWN_INDEX = 'A', RLEFT_INDEX = 'X', RRIGHT_INDEX = 'B' }
        return pad[padDefault] or padDefault
    end
    local k = boundKey(command, default)
    return FRIENDLY[k] or k
end

local function closeKey()
    return IsUsingKeyboard(0) and 'Backspace' or 'B'
end

-- The text prompt (ox_lib's text UI). Only ever hides one this file put up.
local shown = nil
local function prompt(text)
    if text == shown then return end
    if text then
        lib.showTextUI(text, { icon = 'tape' })
    else
        local open, current = lib.isTextUIOpen()
        if open and (current == nil or current == shown) then lib.hideTextUI() end
    end
    shown = text
end

local function camDir()
    local rot = GetFinalRenderedCamRot(2)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function closeEdit()
    edit = nil
    progress = 0.0
    nui.progress(0)
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        local wait = 150
        local now = GetGameTimer()
        local dt = (now - last) / 1000.0
        last = now

        local ped = PlayerPedId()
        local able = state.perms.use and not place.active and IsPedOnFoot(ped) and not IsEntityDead(ped)
        local busy = nui.busy()

        local tape, fallen, fallenTape, fallenEnd = nil, nil, nil, nil
        if able and not busy then
            local cam = GetFinalRenderedCamCoord()
            local reach = 4.0 + #(cam - GetEntityCoords(ped))
            tape = world.pick(cam, camDir(), reach, 0.22)
            if not tape and HOLD.StandUp ~= false then
                local p, f = GetEntityCoords(ped), GetEntityForwardVector(ped)
                fallen, fallenTape, fallenEnd = world.fallenNear(p.x, p.y, p.z, f.x, f.y, 1.8)
            end
        end
        look.tape = tape

        -- The popup that is up: still for what is in front of the player?
        if edit and not able then closeEdit() end
        if edit and not busy then
            local same
            if edit.kind == 'tape' then
                same = tape ~= nil and tape.id == edit.id
            else
                same = fallen ~= nil and fallenTape == edit.id and fallenEnd == edit.which
            end
            if same then
                edit.lostAt = nil
            else
                edit.lostAt = edit.lostAt or now
                if now - edit.lostAt > LOSE_MS then closeEdit() end
            end
            if edit and edit.kind == 'tape' and not world.get(edit.id) then closeEdit() end
        end

        -- Opening it: the edit key, while the prompt is up.
        if not edit and pressed and able and not busy and (tape or fallen) then
            if tape then
                edit = { kind = 'tape', id = tape.id, armed = false }
            elseif fallen and fallenTape then
                edit = { kind = 'fallen', id = fallenTape, which = fallenEnd, label = fallen.def.label, armed = false }
            end
            progress = 0.0
        end
        pressed = false
        if edit and not holding then edit.armed = true end

        if edit and not busy then
            wait = 0
            DisableControlAction(0, C_CLOSE, true)
            if IsDisabledControlJustPressed(0, C_CLOSE) then closeEdit() end
        end

        if edit and not busy then
            prompt(nil)
            local removeKey = keyName('+sdtape_remove', KEYS.Remove, '+sdtape_remove_pad', KEYS.PadRemove)
            if edit.kind == 'tape' then
                local tp = world.get(edit.id)
                local style = tp and state.style(tp.style)
                local keys = {
                    { k = keyName('sdtape_restyle', KEYS.Restyle, 'sdtape_restyle_pad', KEYS.PadRestyle), t = t('ui.hud.change_style') },
                    { k = removeKey, t = t('ui.hud.take_down') },
                }
                if tp and choosing() then
                    keys[#keys + 1] = { k = keyName('sdtape_persist', KEYS.Persist or 'F', 'sdtape_persist_pad', KEYS.PadPersist or 'RUP_INDEX'), t = tp.persist and t('ui.hud.kept') or t('ui.hud.not_kept') }
                end
                keys[#keys + 1] = { k = closeKey(), t = t('ui.hud.close') }
                nui.hud({
                    mode = 'look',
                    styleId = tp and tp.style or state.defaultStyle(),
                    title = style and style.label or nil,
                    line = tp and tp.torn and t('ui.hud.torn') or nil,
                    lineKind = 'warn',
                    keys = keys,
                })
            else
                local tied = world.get(edit.id)
                nui.hud({
                    mode = 'look',
                    styleId = tied and tied.style or state.defaultStyle(),
                    title = edit.label,
                    line = t('ui.hud.knocked_over'),
                    lineKind = 'warn',
                    keys = { { k = removeKey, t = t('ui.hud.stand_up') }, { k = closeKey(), t = t('ui.hud.close') } },
                })
            end

            if holding and edit.armed then
                progress = progress + dt * 1000.0 / KEYS.HoldTime
                if progress >= 1.0 then
                    if edit.kind == 'tape' then
                        TriggerServerEvent('sd-policetape:server:remove', edit.id)
                    else
                        TriggerServerEvent('sd-policetape:server:standup', edit.id, edit.which)
                    end
                    closeEdit()
                end
            else
                progress = math.max(0.0, progress - dt * 3.0)
            end
            if edit then nui.progress(progress) end
        elseif not edit and able and not busy and (tape or fallen) then
            wait = 0
            local key = keyName('+sdtape_remove', KEYS.Remove, '+sdtape_remove_pad', KEYS.PadRemove)
            local label = tape and t('ui.hud.edit_tape') or t('ui.hud.stand_prompt', { name = fallen and fallen.def.label or '' })
            prompt(('[%s] %s'):format(key, label))
        else
            prompt(nil)
        end

        if not edit and not place.active and not busy then nui.hud(nil) end

        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then prompt(nil) end
end)

return look
