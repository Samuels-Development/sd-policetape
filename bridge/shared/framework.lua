---@class FrameworkInfo
---@field name 'qbx'|'qb'|'esx'|'standalone' Detected framework identifier.
---@field qb boolean True for both Qbox and QBCore, whose player objects share a shape.
---@field core any Live core object (`exports['qb-core']:GetCoreObject()` or ESX shared object).
---Nil on Qbox, which has no core object: everything it needs is a discrete export.

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:framework')

---Detects which framework is running and returns a populated `FrameworkInfo`
---table, or nil if none of qbx_core, qb-core or es_extended is started. Qbox is
---checked before qb-core so it is driven through its own exports rather than
---through the qb-core compatibility layer it provides.
---@return FrameworkInfo|nil
local function detect()
    dprint('probing for framework...')
    dprint('  qbx_core state=%s', GetResourceState('qbx_core'))
    if GetResourceState('qbx_core') == 'started' then
        dprint('selected backend: qbx')
        return { name = 'qbx', qb = true }
    end
    dprint('  qb-core state=%s', GetResourceState('qb-core'))
    if GetResourceState('qb-core') == 'started' then
        dprint('selected backend: qb')
        return { name = 'qb', qb = true, core = exports['qb-core']:GetCoreObject() }
    end
    dprint('  es_extended state=%s', GetResourceState('es_extended'))
    if GetResourceState('es_extended') == 'started' then
        dprint('selected backend: esx')
        return { name = 'esx', qb = false, core = exports['es_extended']:getSharedObject() }
    end
    dprint('^1no supported framework found — qbx_core, qb-core and es_extended all not started^7')
    return nil
end

---@type FrameworkInfo|nil Detected framework descriptor, or nil if none is started.
local info = detect()

if not info then
    -- sd-policetape runs without a framework too: permissions then come from ACE alone and the
    -- tape item is skipped unless ox_inventory is running (see server/permissions.lua).
    print('^3[SD-POLICETAPE]^0 No framework found (qbx_core, qb-core, es_extended) - running standalone, ACE permissions only')
    info = { name = 'standalone', qb = false }
end

dprint('framework resolved: name=%s qb=%s core=%s', info.name, tostring(info.qb), tostring(info.core))
print(('^2[SD-POLICETAPE]^0 Framework detected: ^3%s^0'):format(info.name))

return info
