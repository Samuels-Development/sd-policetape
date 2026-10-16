---Looking at a tape: its name comes up, a key changes its style, holding another takes it down.
---Both keys are rebindable (Settings > Key Bindings > FiveM) and each has a controller binding
---as well. Standing at a knocked-over post or cone, the same hold stands it back up.
local config = require 'configs.config'
local locale = require 'bridge.shared.locale'
local state = require 'client.state'
local world = require 'client.tape.world'
local nui = require 'client.nui'
local place = require 'client.place'

local KEYS = config.Keys
local HOLD = config.Holders or {}
local look = { tape = nil }

local function t(key, vars) return locale.t(key, vars) end

local holding = false
local progress = 0.0

RegisterCommand('+sdtape_remove', function() holding = true end, false)
RegisterCommand('-sdtape_remove', function() holding = false end, false)
RegisterKeyMapping('+sdtape_remove', 'Police tape: hold to take down', 'keyboard', KEYS.Remove)
RegisterCommand('+sdtape_remove_pad', function() holding = true end, false)
RegisterCommand('-sdtape_remove_pad', function() holding = false end, false)
RegisterKeyMapping('+sdtape_remove_pad', 'Police tape: hold to take down (controller)', 'PAD_DIGITALBUTTON', KEYS.PadRemove)

local function restyle()
    local tape = look.tape
    if not tape or nui.busy() or place.active then return end
    local id = tape.id
    nui.openPicker(tape.style, function(style)
        if style and style ~= tape.style then
            TriggerServerEvent('sd-policetape:server:restyle', id, style)
        end
    end)
end

RegisterCommand('sdtape_restyle', restyle, false)
RegisterKeyMapping('sdtape_restyle', 'Police tape: change style of the tape you look at', 'keyboard', KEYS.Restyle)
RegisterCommand('sdtape_restyle_pad', restyle, false)
RegisterKeyMapping('sdtape_restyle_pad', 'Police tape: change style (controller)', 'PAD_DIGITALBUTTON', KEYS.PadRestyle)

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
        local pad = { LDOWN_INDEX = '↓', LLEFT_INDEX = '←', LUP_INDEX = '↑', LRIGHT_INDEX = '→' }
        return pad[padDefault] or padDefault
    end
    local k = boundKey(command, default)
    return FRIENDLY[k] or k
end

local function camDir()
    local rot = GetFinalRenderedCamRot(2)
    local x, z = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

CreateThread(function()
    local last = GetGameTimer()
    while true do
        local wait = 150
        local now = GetGameTimer()
        local dt = (now - last) / 1000.0
        last = now

        local ped = PlayerPedId()
        local tape, fallen, fallenTape, fallenEnd = nil, nil, nil, nil
        if state.perms.use and not place.active and not nui.busy() and IsPedOnFoot(ped) and not IsEntityDead(ped) then
            local cam = GetFinalRenderedCamCoord()
            local reach = 4.0 + #(cam - GetEntityCoords(ped))
            tape = world.pick(cam, camDir(), reach, 0.22)
            if not tape and HOLD.StandUp ~= false then
                local p, f = GetEntityCoords(ped), GetEntityForwardVector(ped)
                fallen, fallenTape, fallenEnd = world.fallenNear(p.x, p.y, p.z, f.x, f.y, 1.8)
            end
        end

        local target = tape or fallen
        if target ~= look.target then
            progress = 0.0
            nui.progress(0)
        end
        look.target = target
        look.tape = tape

        if tape then
            wait = 0
            local style = state.style(tape.style)
            local keys = {
                { k = keyName('sdtape_restyle', KEYS.Restyle, 'sdtape_restyle_pad', KEYS.PadRestyle), t = t('ui.hud.change_style') },
                { k = keyName('+sdtape_remove', KEYS.Remove, '+sdtape_remove_pad', KEYS.PadRemove), t = t('ui.hud.take_down') },
            }
            nui.hud({
                mode = 'look',
                styleId = tape.style,
                title = style and style.label or nil,
                line = tape.torn and t('ui.hud.torn') or nil,
                lineKind = 'warn',
                keys = keys,
            })

            if holding then
                progress = progress + dt * 1000.0 / KEYS.HoldTime
                if progress >= 1.0 then
                    TriggerServerEvent('sd-policetape:server:remove', tape.id)
                    holding = false
                    progress = 0.0
                end
            else
                progress = math.max(0.0, progress - dt * 3.0)
            end
            nui.progress(progress)
        elseif fallen then
            wait = 0
            local tied = world.get(fallenTape)
            nui.hud({
                mode = 'look',
                styleId = tied and tied.style or state.defaultStyle(),
                title = fallen.def.label,
                line = t('ui.hud.knocked_over'),
                lineKind = 'warn',
                keys = { { k = keyName('+sdtape_remove', KEYS.Remove, '+sdtape_remove_pad', KEYS.PadRemove), t = t('ui.hud.stand_up') } },
            })

            if holding then
                progress = progress + dt * 1000.0 / KEYS.HoldTime
                if progress >= 1.0 then
                    TriggerServerEvent('sd-policetape:server:standup', fallenTape, fallenEnd)
                    holding = false
                    progress = 0.0
                end
            else
                progress = math.max(0.0, progress - dt * 3.0)
            end
            nui.progress(progress)
        elseif not place.active and not nui.busy() then
            nui.hud(nil)
        end

        Wait(wait)
    end
end)

return look
