---@type table Detected framework descriptor (bridge.shared.framework).
local framework = require 'bridge.shared.framework'

---@type table Detected inventory resource descriptor (bridge.shared.inventory_id).
local inventoryId = require 'bridge.shared.inventory_id'

---@type table Player resolution helpers (bridge.server.player).
local player_mod = require 'bridge.server.player'

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:inventory')

---@type table Inventory helper module returned to consumers.
local inventory = { system = inventoryId.name }

---@type string ox_inventory resource name.
local OX = 'ox_inventory'

---@type string tgiann-inventory resource name.
local TG = 'tgiann-inventory'

---@type string jaksam_inventory resource name.
local JK = 'jaksam_inventory'

---@type string qb-inventory resource name.
local QB = 'qb-inventory'

---@type string qs-inventory-pro resource name.
local QSP = 'qs-inventory-pro'

---@type string qs-inventory resource name.
local QS = 'qs-inventory'

---@type string origen_inventory resource name.
local OG = 'origen_inventory'

---@type string codem-inventory resource name.
local CD = 'codem-inventory'

---@type string one_inventory resource name (onestudios).
local ONE = 'one_inventory'

---@type string Active inventory resource name for the current server.
local active = inventoryId.name

dprint('module load — active inventory backend: %s (framework: %s)', tostring(active), tostring(framework.name))

---@type table<string, string> Per-backend metadata key holding durability/condition.
local DURABILITY_KEYS = {
    [OX] = 'durability',
    [TG] = 'durability',
    [JK] = 'durability',
    [ONE] = 'durability',
    [QB] = 'quality',
    [QSP] = 'quality',
    [QS] = 'quality',
    [OG] = 'quality',
    [CD] = 'quality',
    ['ps-inventory'] = 'quality',
    ['lj-inventory'] = 'quality',
}

---@type string Active backend's durability metadata key.
inventory.durabilityKey = DURABILITY_KEYS[active] or 'durability'

dprint('durabilityKey resolved: backend=%s key=%s', tostring(active), tostring(inventory.durabilityKey))

---Picks the inventory backend's AddItem implementation at module load.
---@return fun(source: number, item: string, count: number, metadata?: table): boolean
local function chooseAdd()
    if active == OX then
        dprint('chooseAdd: selected backend %s (ox_inventory export)', OX)
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), OX)
            local result = exports[OX]:AddItem(src, item, count, metadata)
            dprint('add: result=%s', tostring(result))
            return result
        end
    end
    if active == TG then
        dprint('chooseAdd: selected backend %s (tgiann-inventory export)', TG)
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), TG)
            local result = exports[TG]:AddItem(src, item, count, metadata)
            dprint('add: result=%s', tostring(result))
            return result
        end
    end
    if active == JK then
        dprint('chooseAdd: selected backend %s (jaksam_inventory export)', JK)
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), JK)
            local ok = exports[JK]:addItem(src, item, count, metadata)
            dprint('add: result=%s', tostring(ok or false))
            return ok or false
        end
    end
    if active == CD then
        dprint('chooseAdd: selected backend %s (codem-inventory export)', CD)
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), CD)
            local result = exports[CD]:AddItem(src, item, count, metadata)
            dprint('add: result=%s', tostring(result))
            return result
        end
    end
    if active == ONE then
        -- one_inventory: AddItem(inv, item, count, metadata, slot) -> boolean, reason?
        -- The player's source doubles as their inventory identifier. Truncate the
        -- multi-return so callers only see the success boolean.
        dprint('chooseAdd: selected backend %s (one_inventory export)', ONE)
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), ONE)
            local result = (exports[ONE]:AddItem(src, item, count, metadata)) and true or false
            dprint('add: result=%s', tostring(result))
            return result
        end
    end
    if active == QS or active == QSP then
        local inv = active
        dprint('chooseAdd: selected backend %s (qs-inventory export)', inv)
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), inv)
            local result = exports[inv]:AddItem(src, item, count, nil, metadata)
            dprint('add: result=%s', tostring(result))
            return result
        end
    end
    if active == OG then
        dprint('chooseAdd: selected backend %s (origen_inventory export)', OG)
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), OG)
            local result = exports[OG]:addItem(src, item, count, metadata)
            dprint('add: result=%s', tostring(result))
            return result
        end
    end
    if active == QB then
        dprint('chooseAdd: selected backend %s (qb-inventory export)', QB)
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), QB)
            local result = exports[QB]:AddItem(src, item, count, metadata)
            dprint('add: result=%s', tostring(result))
            return result
        end
    end

    if framework.name == 'esx' then
        dprint('chooseAdd: selected ESX framework fallback (addInventoryItem)')
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via ESX framework', tostring(src), tostring(item), tostring(count))
            local p = player_mod.get(src)
            if not p then
                dprint('add: player not found for src=%s — aborting', tostring(src))
                return false
            end
            p.addInventoryItem(item, count, metadata)
            return true
        end
    end
    if framework.qb then
        dprint('chooseAdd: selected QBCore framework fallback (Functions.AddItem)')
        return function(src, item, count, metadata)
            dprint('add: src=%s item=%s count=%s via QBCore framework', tostring(src), tostring(item), tostring(count))
            local p = player_mod.get(src)
            if not p then
                dprint('add: player not found for src=%s — aborting', tostring(src))
                return false
            end
            return p.Functions.AddItem(item, count, nil, metadata)
        end
    end
    dprint('chooseAdd: no matching backend or framework — returning no-op (active=%s, framework=%s)', tostring(active), tostring(framework.name))
    return function() return false end
end

inventory.add = chooseAdd()

---Picks the inventory backend's count-of-item implementation at module load.
---@return fun(source: number, item: string): number
local function chooseCount()
    if active == OX then
        dprint('chooseCount: selected backend %s (Search/slots)', OX)
        return function(src, item)
            dprint('count: src=%s item=%s via %s', tostring(src), tostring(item), OX)
            local items = exports[OX]:Search(src, 'slots', item)
            if type(items) ~= 'table' then
                dprint('count: Search returned non-table — returning 0')
                return 0
            end
            local total = 0
            for _, row in pairs(items) do total = total + (row.count or 0) end
            dprint('count: result=%d', total)
            return total
        end
    end
    if active == TG then
        dprint('chooseCount: selected backend %s (GetItemCount)', TG)
        return function(src, item)
            dprint('count: src=%s item=%s via %s', tostring(src), tostring(item), TG)
            local result = exports[TG]:GetItemCount(src, item) or 0
            dprint('count: result=%d', result)
            return result
        end
    end
    if active == JK then
        dprint('chooseCount: selected backend %s (getTotalItemAmount)', JK)
        return function(src, item)
            dprint('count: src=%s item=%s via %s', tostring(src), tostring(item), JK)
            local result = exports[JK]:getTotalItemAmount(src, item) or 0
            dprint('count: result=%d', result)
            return result
        end
    end
    if active == CD then
        dprint('chooseCount: selected backend %s (GetItemsTotalAmount)', CD)
        return function(src, item)
            dprint('count: src=%s item=%s via %s', tostring(src), tostring(item), CD)
            local result = exports[CD]:GetItemsTotalAmount(src, item) or 0
            dprint('count: result=%d', result)
            return result
        end
    end
    if active == ONE then
        dprint('chooseCount: selected backend %s (GetItemCount)', ONE)
        return function(src, item)
            dprint('count: src=%s item=%s via %s', tostring(src), tostring(item), ONE)
            local result = exports[ONE]:GetItemCount(src, item) or 0
            dprint('count: result=%d', result)
            return result
        end
    end
    if active == OG then
        dprint('chooseCount: selected backend %s (getItemCount)', OG)
        return function(src, item)
            dprint('count: src=%s item=%s via %s', tostring(src), tostring(item), OG)
            local result = exports[OG]:getItemCount(src, item, false, false) or 0
            dprint('count: result=%d', result)
            return result
        end
    end
    if active == QB then
        dprint('chooseCount: selected backend %s (GetItemCount)', QB)
        return function(src, item)
            dprint('count: src=%s item=%s via %s', tostring(src), tostring(item), QB)
            local result = exports[QB]:GetItemCount(src, item) or 0
            dprint('count: result=%d', result)
            return result
        end
    end
    if active == QS or active == QSP then
        local inv = active
        dprint('chooseCount: selected backend %s (GetItemTotalAmount)', inv)
        return function(src, item)
            dprint('count: src=%s item=%s via %s', tostring(src), tostring(item), inv)
            local result = exports[inv]:GetItemTotalAmount(src, item) or 0
            dprint('count: result=%d', result)
            return result
        end
    end

    if framework.name == 'esx' then
        dprint('chooseCount: selected ESX framework fallback (getInventoryItem)')
        return function(src, item)
            dprint('count: src=%s item=%s via ESX framework', tostring(src), tostring(item))
            local p = player_mod.get(src); if not p then return 0 end
            local data = p.getInventoryItem(item)
            local result = data and (data.count or data.amount) or 0
            dprint('count: result=%d', result)
            return result
        end
    end
    if framework.qb then
        dprint('chooseCount: selected QBCore framework fallback (GetItemByName)')
        return function(src, item)
            dprint('count: src=%s item=%s via QBCore framework', tostring(src), tostring(item))
            local p = player_mod.get(src); if not p then return 0 end
            local data = p.Functions.GetItemByName(item)
            local result = data and (data.amount or data.count) or 0
            dprint('count: result=%d', result)
            return result
        end
    end
    dprint('chooseCount: no matching backend or framework — returning no-op (active=%s, framework=%s)', tostring(active), tostring(framework.name))
    return function() return 0 end
end

inventory.count = chooseCount()

---Predicate form of `count` — returns true when the player has at least
---`amount` of `item` (default 1).
---@param source number
---@param item string
---@param amount? number Defaults to 1.
---@return boolean
function inventory.has(source, item, amount)
    if not item then
        dprint('has: called with nil item for src=%s — returning false', tostring(source))
        return false
    end
    local result = inventory.count(source, item) >= (amount or 1)
    dprint('has: src=%s item=%s amount=%s → %s', tostring(source), tostring(item), tostring(amount or 1), tostring(result))
    return result
end

---Picks the inventory backend's RemoveItem implementation at module load.
---@return fun(source: number, item: string, count: number, metadata?: table): boolean
local function chooseRemove()
    if active == OX then
        dprint('chooseRemove: selected backend %s (ox_inventory export)', OX)
        return function(src, item, count, metadata)
            dprint('remove: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), OX)
            local result = exports[OX]:RemoveItem(src, item, count, metadata)
            dprint('remove: result=%s', tostring(result))
            return result
        end
    end
    if active == TG then
        dprint('chooseRemove: selected backend %s (tgiann-inventory export)', TG)
        return function(src, item, count, metadata)
            dprint('remove: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), TG)
            local result = exports[TG]:RemoveItem(src, item, count, metadata)
            dprint('remove: result=%s', tostring(result))
            return result
        end
    end
    if active == JK then
        dprint('chooseRemove: selected backend %s (jaksam_inventory export)', JK)
        return function(src, item, count, metadata)
            dprint('remove: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), JK)
            local ok = exports[JK]:removeItem(src, item, count, metadata)
            dprint('remove: result=%s', tostring(ok or false))
            return ok or false
        end
    end
    if active == CD then
        dprint('chooseRemove: selected backend %s (codem-inventory export)', CD)
        return function(src, item, count, metadata)
            dprint('remove: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), CD)
            local result = exports[CD]:RemoveItem(src, item, count, metadata)
            dprint('remove: result=%s', tostring(result))
            return result
        end
    end
    if active == ONE then
        -- one_inventory: RemoveItem(inv, item, count, metadata, slot) -> boolean, reason?
        dprint('chooseRemove: selected backend %s (one_inventory export)', ONE)
        return function(src, item, count, metadata)
            dprint('remove: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), ONE)
            local result = (exports[ONE]:RemoveItem(src, item, count, metadata)) and true or false
            dprint('remove: result=%s', tostring(result))
            return result
        end
    end
    if active == OG then
        dprint('chooseRemove: selected backend %s (origen_inventory export)', OG)
        return function(src, item, count, metadata)
            dprint('remove: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), OG)
            local result = exports[OG]:removeItem(src, item, count, metadata)
            dprint('remove: result=%s', tostring(result))
            return result
        end
    end
    if active == QB then
        dprint('chooseRemove: selected backend %s (qb-inventory export)', QB)
        return function(src, item, count, metadata)
            dprint('remove: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), QB)
            local result = exports[QB]:RemoveItem(src, item, count, metadata)
            dprint('remove: result=%s', tostring(result))
            return result
        end
    end
    if active == QS or active == QSP then
        local inv = active
        dprint('chooseRemove: selected backend %s (qs-inventory export)', inv)
        return function(src, item, count, metadata)
            dprint('remove: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), inv)
            local result = exports[inv]:RemoveItem(src, item, count, metadata)
            dprint('remove: result=%s', tostring(result))
            return result
        end
    end

    if framework.name == 'esx' then
        dprint('chooseRemove: selected ESX framework fallback (removeInventoryItem)')
        return function(src, item, count, metadata)
            dprint('remove: src=%s item=%s count=%s via ESX framework', tostring(src), tostring(item), tostring(count))
            local p = player_mod.get(src); if not p then
                dprint('remove: player not found for src=%s — aborting', tostring(src))
                return false
            end
            p.removeInventoryItem(item, count, metadata)
            return true
        end
    end
    if framework.qb then
        dprint('chooseRemove: selected QBCore framework fallback (Functions.RemoveItem)')
        return function(src, item, count, _metadata)
            dprint('remove: src=%s item=%s count=%s via QBCore framework', tostring(src), tostring(item), tostring(count))
            local p = player_mod.get(src); if not p then
                dprint('remove: player not found for src=%s — aborting', tostring(src))
                return false
            end
            return p.Functions.RemoveItem(item, count)
        end
    end
    dprint('chooseRemove: no matching backend or framework — returning no-op (active=%s, framework=%s)', tostring(active), tostring(framework.name))
    return function() return false end
end

inventory.remove = chooseRemove()

---Picks the inventory backend's "can the player carry this?" check at
---module load. Most backends just expose a CanCarryItem export; for ESX we
---emulate it with weight maths.
---@return fun(source: number, item: string, count: number, slot?: any): boolean
local function chooseCanCarry()
    if active == CD then
        dprint('chooseCanCarry: selected backend %s — always returns true (no weight API)', CD)
        return function() return true end
    end
    if active == OX then
        dprint('chooseCanCarry: selected backend %s (CanCarryItem export)', OX)
        return function(src, item, count, metadata)
            dprint('canCarry: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), OX)
            local result = exports[OX]:CanCarryItem(src, item, count, metadata)
            dprint('canCarry: result=%s', tostring(result))
            return result
        end
    end
    if active == TG then
        dprint('chooseCanCarry: selected backend %s (CanCarryItem export)', TG)
        return function(src, item, count)
            dprint('canCarry: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), TG)
            local result = exports[TG]:CanCarryItem(src, item, count)
            dprint('canCarry: result=%s', tostring(result))
            return result
        end
    end
    if active == ONE then
        dprint('chooseCanCarry: selected backend %s (CanCarryItem export)', ONE)
        return function(src, item, count)
            dprint('canCarry: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), ONE)
            local result = exports[ONE]:CanCarryItem(src, item, count)
            dprint('canCarry: result=%s', tostring(result))
            return result
        end
    end
    if active == JK then
        dprint('chooseCanCarry: selected backend %s (canCarryItem export)', JK)
        return function(src, item, count)
            dprint('canCarry: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), JK)
            local result = exports[JK]:canCarryItem(src, item, count)
            dprint('canCarry: result=%s', tostring(result))
            return result
        end
    end
    if active == OG then
        dprint('chooseCanCarry: selected backend %s (canCarryItem export)', OG)
        return function(src, item, count)
            dprint('canCarry: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), OG)
            local result = exports[OG]:canCarryItem(src, item, count)
            dprint('canCarry: result=%s', tostring(result))
            return result
        end
    end
    if active == QB then
        dprint('chooseCanCarry: selected backend %s (CanAddItem export)', QB)
        return function(src, item, count)
            dprint('canCarry: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), QB)
            local result = exports[QB]:CanAddItem(src, item, count)
            dprint('canCarry: result=%s', tostring(result))
            return result
        end
    end
    if active == QSP then
        dprint('chooseCanCarry: selected backend %s (CanCarryItem export)', QSP)
        return function(src, item, count)
            dprint('canCarry: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), QSP)
            local result = exports[QSP]:CanCarryItem(src, item, count)
            dprint('canCarry: result=%s', tostring(result))
            return result
        end
    end
    if active == QS then
        dprint('chooseCanCarry: selected backend %s (CanCarryItem export)', QS)
        return function(src, item, count)
            dprint('canCarry: src=%s item=%s count=%s via %s', tostring(src), tostring(item), tostring(count), QS)
            local result = exports[QS]:CanCarryItem(src, item, count)
            dprint('canCarry: result=%s', tostring(result))
            return result
        end
    end

    if framework.name == 'esx' then
        dprint('chooseCanCarry: selected ESX framework fallback (weight calculation)')
        return function(src, item, count)
            dprint('canCarry: src=%s item=%s count=%s via ESX weight calc', tostring(src), tostring(item), tostring(count))
            local p = player_mod.get(src); if not p then
                dprint('canCarry: player not found for src=%s — returning false', tostring(src))
                return false
            end
            local current = p.getInventoryItem(item)
            if not current then
                dprint('canCarry: item %s not in item registry — returning false', tostring(item))
                return false
            end
            local maxW = p.getMaxWeight()
            local curW = p.getWeight()
            local result = curW + ((current.weight or 0) * count) <= maxW
            dprint('canCarry: curW=%.1f maxW=%.1f itemWeight=%.1f count=%s → %s', curW, maxW, current.weight or 0, tostring(count), tostring(result))
            return result
        end
    end
    if framework.qb then
        dprint('chooseCanCarry: selected QBCore framework fallback (Functions.CanAddItem)')
        return function(src, item, count, slot)
            dprint('canCarry: src=%s item=%s count=%s via QBCore framework', tostring(src), tostring(item), tostring(count))
            local p = player_mod.get(src); if not p then
                dprint('canCarry: player not found for src=%s — returning false', tostring(src))
                return false
            end
            return p.Functions.CanAddItem(item, count, slot)
        end
    end
    dprint('chooseCanCarry: no matching backend or framework — returning no-op (active=%s, framework=%s)', tostring(active), tostring(framework.name))
    return function() return false end
end

inventory.canCarry = chooseCanCarry()

---Picks the right "register a usable item" implementation at module load.
---ox_inventory has no single API for this — instead it dispatches to a
---per-item export, so we auto-derive the export name from the item key.
---Other inventories expose their own CreateUsableItem / RegisterUsableItem.
---@return fun(item: string, cb: fun(source: number, item?: any, inv?: table, slot?: any, data?: any)): nil
local function chooseRegisterUsable()
    if active == OX then
        dprint('chooseRegisterUsable: selected backend %s (export-per-item pattern)', OX)
        return function(item, cb)
            local exportName = 'use' .. item:gsub('^%l', string.upper)
            dprint('registerUsable: registering ox export %q for item %s', exportName, tostring(item))
            exports(exportName, function(event, _item, inv, slot, data)
                if event == 'usingItem' then
                    dprint('registerUsable: ox usingItem fired — item=%s src=%s', tostring(_item and _item.name or _item), tostring(inv and inv.id))
                    cb(inv.id, _item, inv, slot, data)
                end
            end)
        end
    end
    if active == QSP then
        dprint('chooseRegisterUsable: selected backend %s (CreateUsableItem export)', QSP)
        return function(item, cb)
            dprint('registerUsable: registering item %s via %s:CreateUsableItem', tostring(item), QSP)
            return exports[QSP]:CreateUsableItem(item, cb)
        end
    end
    if active == OG then
        dprint('chooseRegisterUsable: selected backend %s (CreateUseableItem export)', OG)
        return function(item, cb)
            dprint('registerUsable: registering item %s via %s:CreateUseableItem', tostring(item), OG)
            return exports[OG]:CreateUseableItem(item, cb)
        end
    end
    if active == ONE then
        -- one_inventory has no CreateUsableItem export. Instead it broadcasts a
        -- `one_inventory:onItemUsed` server event after a player uses an item
        -- (payload: { source, item, slot, metadata }). We register that listener
        -- exactly once and route each use to the per-item callback registered
        -- here, normalising the call to the bridge's (source, item, _inv, slot,
        -- metadata) shape. Consumers re-validate possession, so a spoofed event
        -- can't grant anything the player doesn't actually hold.
        dprint('chooseRegisterUsable: selected backend %s (one_inventory:onItemUsed event listener)', ONE)
        local handlers = {}
        local listening = false
        return function(item, cb)
            dprint('registerUsable: registering item %s via %s event pattern', tostring(item), ONE)
            handlers[item] = cb
            if not listening then
                listening = true
                dprint('registerUsable: registering one_inventory:onItemUsed net event listener')
                RegisterNetEvent('one_inventory:onItemUsed', function(payload)
                    if type(payload) ~= 'table' then return end
                    local handler = handlers[payload.item]
                    if handler then
                        dprint('registerUsable: one_inventory:onItemUsed fired — item=%s src=%s', tostring(payload.item), tostring(payload.source))
                        handler(payload.source, payload.item, nil, payload.slot, payload.metadata)
                    end
                end)
            end
        end
    end

    if framework.name == 'esx' then
        dprint('chooseRegisterUsable: selected ESX framework fallback (RegisterUsableItem)')
        return function(item, cb)
            dprint('registerUsable: registering item %s via ESX:RegisterUsableItem', tostring(item))
            return framework.core.RegisterUsableItem(item, cb)
        end
    end
    if framework.name == 'qbx' then
        dprint('chooseRegisterUsable: selected Qbox framework fallback (exports.qbx_core:CreateUseableItem)')
        return function(item, cb)
            dprint('registerUsable: registering item %s via qbx_core:CreateUseableItem', tostring(item))
            return exports.qbx_core:CreateUseableItem(item, cb)
        end
    end
    if framework.qb then
        dprint('chooseRegisterUsable: selected QBCore framework fallback (Functions.CreateUseableItem)')
        return function(item, cb)
            dprint('registerUsable: registering item %s via QBCore:Functions.CreateUseableItem', tostring(item))
            return framework.core.Functions.CreateUseableItem(item, cb)
        end
    end

    dprint('chooseRegisterUsable: no matching backend or framework — returning error stub (active=%s, framework=%s)', tostring(active), tostring(framework.name))
    return function(item)
        error(('inventory.registerUsable: no supported registration path for item %q'):format(item))
    end
end

inventory.registerUsable = chooseRegisterUsable()

---Picks the right item-label resolver at module load. Falls back to the
---framework's shared items table for backends that don't expose a dedicated
---label API.
---@return fun(itemName: string): string|nil
local function chooseLabel()
    if active == OX or active == TG then
        dprint('chooseLabel: selected backend %s (Items export)', active)
        return function(itemName)
            local ok, item = pcall(exports[active].Items, exports[active], itemName)
            if not ok then
                dprint('label: pcall to %s:Items failed for %s', active, tostring(itemName))
            end
            return (ok and item) and item.label or itemName
        end
    end
    if active == JK then
        dprint('chooseLabel: selected backend %s (getItemLabel export)', JK)
        return function(itemName) return exports[JK]:getItemLabel(itemName) or itemName end
    end
    if active == OG then
        dprint('chooseLabel: selected backend %s (GetItemLabel export)', OG)
        return function(itemName) return exports[OG]:GetItemLabel(itemName) or itemName end
    end
    if active == ONE then
        dprint('chooseLabel: selected backend %s (GetItemDefinition export)', ONE)
        return function(itemName)
            local def = exports[ONE]:GetItemDefinition(itemName)
            return (def and def.label) or itemName
        end
    end

    if framework.qb then
        dprint('chooseLabel: selected QBCore framework fallback (Shared.Items table)')
        return function(itemName)
            local shared = framework.core and framework.core.Shared
            local item = shared and shared.Items and shared.Items[itemName]
            return item and item.label or itemName
        end
    end
    if framework.name == 'esx' then
        dprint('chooseLabel: selected ESX framework fallback (GetItemLabel)')
        return function(itemName) return framework.core.GetItemLabel(itemName) or itemName end
    end
    dprint('chooseLabel: no matching backend or framework — returning identity (active=%s, framework=%s)', tostring(active), tostring(framework.name))
    return function(itemName) return itemName end
end

---@type fun(itemName: string): string Label-lookup backend, chosen once at load.
local resolveLabel = chooseLabel()
---@type table<string, string> Item key -> resolved label cache.
local labelCache = {}

---Returns the player-readable label for an item key, falling back to the
---raw key when the backend has no label registered. Cached after first lookup.
---@param itemName string
---@return string
function inventory.label(itemName)
    if not itemName then return '' end
    local cached = labelCache[itemName]
    if cached ~= nil then
        dprint('label: cache hit for %s → %s', tostring(itemName), tostring(cached))
        return cached
    end

    local label = resolveLabel(itemName) or itemName
    dprint('label: resolved %s → %s', tostring(itemName), tostring(label))
    labelCache[itemName] = label
    return label
end

---Returns the player's stacks of `item`, each with its slot id, count, and
---per-slot metadata. ox_inventory exposes this directly; the other supported
---backends are mapped from their own read exports (see the tool-wear bridge
---research). Field names differ between backends (count vs amount, metadata vs
---info), so each branch normalises to `{ slot, count, metadata }` and reads
---both candidate keys defensively. Backends with no per-slot metadata access
---collapse to one aggregate pseudo-slot (slot = nil, empty metadata) so
---metadata-priced callers still function via their fallback value.
---@param source number
---@param item string
---@return { slot: any, count: integer, metadata: table }[]
function inventory.getSlots(source, item)
    dprint('getSlots: src=%s item=%s via backend %s', tostring(source), tostring(item), tostring(active))
    if active == OX or active == TG then
        local res = exports[active]:Search(source, 'slots', item)
        local out = {}
        if type(res) == 'table' then
            for _, s in pairs(res) do
                out[#out + 1] = {
                    slot = s.slot,
                    count = s.count or s.amount or 0,
                    metadata = s.metadata or s.info or {},
                }
            end
        end
        return out
    end

    if active == JK then
        local res = exports[JK]:getItemsByName(source, item)
        local out = {}
        if type(res) == 'table' then
            for _, s in pairs(res) do
                out[#out + 1] = {
                    slot = s.slot,
                    count = s.amount or s.count or 0,
                    metadata = s.metadata or {},
                }
            end
        end
        return out
    end

    if active == QB or active == CD then
        local res = exports[active]:GetItemsByName(source, item)
        local out = {}
        if type(res) == 'table' then
            for _, s in pairs(res) do
                out[#out + 1] = {
                    slot = s.slot,
                    count = s.amount or s.count or 0,
                    metadata = s.info or s.metadata or {},
                }
            end
        end
        return out
    end

    if active == QS or active == QSP then
        local inv = exports[active]:GetInventory(source)
        local out = {}
        if type(inv) == 'table' then
            for slotId, s in pairs(inv) do
                if type(s) == 'table' and s.name == item then
                    out[#out + 1] = {
                        slot = s.slot or slotId,
                        count = s.amount or s.count or 0,
                        metadata = s.info or s.metadata or {},
                    }
                end
            end
        end
        return out
    end

    if active == OG then
        local ids = exports[OG]:getSlotsIdWithItem(source, item)
        local out = {}
        if type(ids) == 'table' then
            for _, slotId in pairs(ids) do
                local s = exports[OG]:getSlot(source, slotId)
                if type(s) == 'table' then
                    out[#out + 1] = {
                        slot = slotId,
                        count = s.amount or s.count or 0,
                        metadata = s.metadata or s.info or {},
                    }
                end
            end
        end
        return out
    end

    if active == ONE then
        -- one_inventory: resolve matching slot ids, then read each slot. GetSlot
        -- returns { name, slot, count, metadata }. Durability is a first-class
        -- 0-100 slot field (set via SetItemDurability), so we surface it under
        -- metadata.durability when it isn't already there — that's the key
        -- `durabilityOf` reads (see DURABILITY_KEYS[ONE]).
        local ids = exports[ONE]:GetSlotIdsWithItem(source, item)
        local out = {}
        if type(ids) == 'table' then
            for _, slotId in pairs(ids) do
                local s = exports[ONE]:GetSlot(source, slotId)
                if type(s) == 'table' then
                    local meta = s.metadata or {}
                    if meta.durability == nil and s.durability ~= nil then
                        meta.durability = s.durability
                    end
                    out[#out + 1] = {
                        slot = s.slot or slotId,
                        count = s.count or s.amount or 0,
                        metadata = meta,
                    }
                end
            end
        end
        return out
    end

    local total = inventory.count(source, item)
    dprint('getSlots: backend %s has no slot API — aggregate fallback total=%d', tostring(active), total)
    if total <= 0 then return {} end
    return { { slot = nil, count = total, metadata = {} } }
end

---Removes `count` of `item` from a specific slot when the backend supports
---slot-targeted removal (ox_inventory); otherwise falls back to a
---metadata-agnostic removal of `count`.
---@param source number
---@param item string
---@param count number
---@param slot? any Slot id from `inventory.getSlots`.
---@return boolean
function inventory.removeFromSlot(source, item, count, slot)
    dprint('removeFromSlot: src=%s item=%s count=%s slot=%s via backend %s', tostring(source), tostring(item), tostring(count), tostring(slot), tostring(active))
    if slot ~= nil then
        if active == OX then
            return exports[OX]:RemoveItem(source, item, count, nil, slot) and true or false
        end
        if active == TG then
            return exports[TG]:RemoveItem(source, item, count, slot) and true or false
        end
        if active == JK then
            return (exports[JK]:removeItem(source, item, count, nil, slot)) ~= false
        end
        if active == QB then
            return exports[QB]:RemoveItem(source, item, count, slot) and true or false
        end
        if active == QS or active == QSP then
            return exports[active]:RemoveItem(source, item, count, slot) and true or false
        end
        if active == OG then
            return exports[OG]:removeItem(source, item, count, slot) and true or false
        end
        if active == CD then
            return exports[CD]:RemoveItem(source, item, count, slot) and true or false
        end
        if active == ONE then
            -- RemoveItem(inv, item, count, metadata, slot) — slot is the 5th arg.
            return (exports[ONE]:RemoveItem(source, item, count, nil, slot)) and true or false
        end
    end
    dprint('removeFromSlot: slot-targeted path not available for backend %s or slot nil — falling back to inventory.remove', tostring(active))
    return inventory.remove(source, item, count) and true or false
end

---Reads the durability/condition value out of a slot's metadata table, using
---the active backend's key (`inventory.durabilityKey`). Returns nil when no
---value is stamped — callers treat that as "full / fresh tool".
---@param metadata table|nil
---@return number|nil
function inventory.durabilityOf(metadata)
    if type(metadata) ~= 'table' then
        dprint('durabilityOf: metadata is not a table (%s) — returning nil', tostring(metadata))
        return nil
    end
    local v = metadata[inventory.durabilityKey]
    if type(v) == 'number' then
        dprint('durabilityOf: key=%s value=%.2f', tostring(inventory.durabilityKey), v)
        return v
    end
    dprint('durabilityOf: key=%s not present or non-numeric (%s) — returning nil', tostring(inventory.durabilityKey), tostring(v))
    return nil
end

---Writes a durability/condition `value` onto a specific `slot` of `item`, in
---place (no remove/re-add), using the active backend's native API + durability
---key. Returns true only when the backend actually supports the write; returns
---false when `slot` is nil or the backend has no per-slot metadata write, so
---the tool-wear caller knows durability couldn't persist and skips it (the
---chance-break path still works via type-based removal).
---@param source number
---@param item string
---@param slot any Slot id from `inventory.getSlots`.
---@param value number
---@return boolean
function inventory.setDurability(source, item, slot, value)
    dprint('setDurability: src=%s item=%s slot=%s value=%s via backend %s', tostring(source), tostring(item), tostring(slot), tostring(value), tostring(active))
    if slot == nil then
        dprint('setDurability: slot is nil — returning false (no per-slot write possible)')
        return false
    end
    local key = inventory.durabilityKey

    if active == OX then
        dprint('setDurability: calling %s:SetDurability slot=%s value=%s', OX, tostring(slot), tostring(value))
        exports[OX]:SetDurability(source, slot, value)
        return true
    end

    if active == JK then
        dprint('setDurability: calling %s:setDurability slot=%s value=%s', JK, tostring(slot), tostring(value))
        return (exports[JK]:setDurability(source, slot, value)) ~= false
    end

    if active == ONE then
        -- one_inventory exposes a purpose-built durability setter (0-100), so we
        -- skip the read-modify-write metadata dance the other backends need.
        dprint('setDurability: calling %s:SetItemDurability slot=%s value=%s', ONE, tostring(slot), tostring(value))
        return (exports[ONE]:SetItemDurability(source, slot, value)) ~= false
    end

    if active == OG then
        dprint('setDurability: calling %s:addItemMetadata slot=%s key=%s value=%s', OG, tostring(slot), tostring(key), tostring(value))
        return exports[OG]:addItemMetadata(source, item, slot, { [key] = value }) and true or false
    end

    if active == TG then
        dprint('setDurability: read-modify-write via %s:UpdateItemMetadata slot=%s key=%s value=%s', TG, tostring(slot), tostring(key), tostring(value))
        local cur = exports[TG]:GetItemBySlot(source, slot)
        local meta = (cur and (cur.metadata or cur.info)) or {}
        meta[key] = value
        exports[TG]:UpdateItemMetadata(source, item, slot, meta)
        return true
    end

    if active == QS or active == QSP then
        dprint('setDurability: read-modify-write via %s:SetItemMetadata slot=%s key=%s value=%s', active, tostring(slot), tostring(key), tostring(value))
        local cur = exports[active]:GetItemBySlot(source, slot)
        local meta = (cur and (cur.info or cur.metadata)) or {}
        meta[key] = value
        exports[active]:SetItemMetadata(source, slot, meta)
        return true
    end

    if active == CD then
        dprint('setDurability: read-modify-write via %s:SetItemMetadata slot=%s key=%s value=%s', CD, tostring(slot), tostring(key), tostring(value))
        local cur = exports[CD]:GetItemBySlot(source, slot)
        local meta = (cur and (cur.info or cur.metadata)) or {}
        meta[key] = value
        exports[CD]:SetItemMetadata(source, slot, meta)
        return true
    end

    if active == QB then
        dprint('setDurability: read-modify-write via %s:SetItemData slot=%s key=%s value=%s', QB, tostring(slot), tostring(key), tostring(value))
        local row = exports[QB]:GetItemBySlot(source, slot)
        local info = (row and row.info) or {}
        info[key] = value
        return exports[QB]:SetItemData(source, item, 'info', info, slot) and true or false
    end

    dprint('setDurability: no supported write path for backend %s — returning false', tostring(active))
    return false
end

return inventory
