---@type table Framework descriptor (bridge.shared.framework) exposing name and core handle.
local framework = require 'bridge.shared.framework'

---@type table Inventory identity (bridge.shared.inventory_id) exposing the active inventory name and candidates.
local inventoryId = require 'bridge.shared.inventory_id'

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:inventory')

---@type table Client inventory bridge; holds the active inventory system name and item-query helpers.
local inventory = { system = inventoryId.name }

dprint('active inventory system: %s', tostring(inventoryId.name))

---Picks the right image-path resolver for the active inventory at module
---load. Each backend stores its NUI images at a different path layout.
---@return fun(item: string): string|nil
local function chooseImageResolver()
    local active = inventoryId.name
    dprint('chooseImageResolver: active=%s', tostring(active))
    if not active then
        dprint('chooseImageResolver: no active inventory — image resolver will return nil')
        return function() return nil end
    end

    if active == 'ox_inventory' or active == 'one_inventory' then
        -- one_inventory stores item icons in web/images/ (per its migration
        -- guide), the same layout ox_inventory uses.
        dprint('chooseImageResolver: selected nui://%s/web/images/ layout', active)
        return function(item)
            return ('nui://%s/web/images/%s.png'):format(active, item)
        end
    end

    if active == 'tgiann-inventory' then
        local imageResource = GetResourceState('inventory_images') == 'started' and 'inventory_images' or active
        local imagePath = imageResource == 'inventory_images' and 'images' or 'web/images'
        dprint('chooseImageResolver: tgiann-inventory — imageResource=%s imagePath=%s', imageResource, imagePath)
        return function(item)
            local ok, itemData = pcall(exports['tgiann-inventory'].Items, exports['tgiann-inventory'], item)
            if ok and itemData then
                local raw = (itemData.client and itemData.client.image) or itemData.image
                if raw then
                    if raw:match('^nui://') or raw:match('^https?://') then return raw end
                    return ('nui://%s/%s/%s'):format(imageResource, imagePath, raw)
                end
            end
            return ('nui://%s/%s/%s.png'):format(imageResource, imagePath, item)
        end
    end

    if active == 'jaksam_inventory' then
        dprint('chooseImageResolver: selected jaksam_inventory (getItemImagePath)')
        return function(item)
            local p = exports.jaksam_inventory:getItemImagePath(item)
            return p or ('nui://%s/web/images/%s.png'):format(active, item)
        end
    end

    if active == 'codem-inventory' then
        dprint('chooseImageResolver: selected codem-inventory (html/itemimages/ layout)')
        return function(item) return ('nui://%s/html/itemimages/%s.png'):format(active, item) end
    end

    if active == 'origen_inventory' then
        dprint('chooseImageResolver: selected origen_inventory (ui/images/ layout)')
        return function(item) return ('nui://%s/ui/images/%s.png'):format(active, item) end
    end

    dprint('chooseImageResolver: unknown inventory — falling back to html/images/ layout for %s', active)
    return function(item) return ('nui://%s/html/images/%s.png'):format(active, item) end
end

---@type fun(item: string): string|nil Active image-path resolver chosen at module load.
local resolveImage = chooseImageResolver()

---@type table<string, string|nil> Per-item image-path cache.
local imageCache = {}

---Returns the NUI image path for an item — used by menus that render their
---own item tiles. Result is cached per-item so the layout walk only happens
---once per unique key.
---@param item string
---@return string|nil
function inventory.image(item)
    if not item then return nil end
    local cached = imageCache[item]
    if cached ~= nil then
        dprint('image: cache hit item=%s path=%s', item, tostring(cached))
        return cached
    end

    local resolved = resolveImage(item)
    dprint('image: resolved item=%s path=%s', item, tostring(resolved))
    imageCache[item] = resolved
    return resolved
end

---Drops the in-memory image cache. Useful if you swap inventory resource at
---runtime (rare, but possible during dev iteration).
function inventory.clearImageCache()
    dprint('clearImageCache called')
    imageCache = {}
end

---Pre-warms the cache. Accepts arrays of strings, of `{item=...}` rows, or
---of `{name=...}` / `{id=...}` rows — covers every reward-config shape.
---@param items table
function inventory.preCacheImages(items)
    if not items then return end
    dprint('preCacheImages: warming %d entries', #items)
    for i = 1, #items do
        local v = items[i]
        if type(v) == 'string' then
            inventory.image(v)
        elseif type(v) == 'table' then
            inventory.image(v.item or v.name or v.id)
        end
    end
    dprint('preCacheImages: done')
end

---Picks the right item-label resolver for the active inventory at module
---load. Returns nil for items the backend doesn't know about so the cache
---layer can store a definitive "we already looked and failed" sentinel.
---@return fun(itemName: string): string|nil
local function chooseLabelResolver()
    local active = inventoryId.name
    dprint('chooseLabelResolver: active=%s framework=%s', tostring(active), tostring(framework.name))
    if active == 'ox_inventory' or active == 'tgiann-inventory' then
        dprint('chooseLabelResolver: selected %s (.Items export)', active)
        return function(itemName)
            local ok, item = pcall(exports[active].Items, exports[active], itemName)
            if not ok then
                dprint('label: %s.Items pcall failed for item=%s', active, itemName)
            end
            return (ok and item) and item.label or nil
        end
    end
    if active == 'jaksam_inventory' then
        dprint('chooseLabelResolver: selected jaksam_inventory (getItemLabel)')
        return function(itemName)
            local ok, label = pcall(exports[active].getItemLabel, exports[active], itemName)
            if not ok then
                dprint('label: jaksam_inventory.getItemLabel pcall failed for item=%s', itemName)
            end
            return ok and label or nil
        end
    end
    if active == 'origen_inventory' then
        dprint('chooseLabelResolver: selected origen_inventory (GetItemLabel)')
        return function(itemName)
            local ok, label = pcall(exports[active].GetItemLabel, exports[active], itemName)
            if not ok then
                dprint('label: origen_inventory.GetItemLabel pcall failed for item=%s', itemName)
            end
            return ok and label or nil
        end
    end
    if active == 'one_inventory' then
        dprint('chooseLabelResolver: selected one_inventory (GetItemDefinition)')
        return function(itemName)
            local ok, def = pcall(exports.one_inventory.GetItemDefinition, exports.one_inventory, itemName)
            if not ok then
                dprint('label: one_inventory.GetItemDefinition pcall failed for item=%s', itemName)
            end
            return (ok and def) and def.label or nil
        end
    end

    if framework.qb and framework.core and framework.core.Shared and framework.core.Shared.Items then
        dprint('chooseLabelResolver: falling back to qb Shared.Items table')
        return function(itemName)
            local item = framework.core.Shared.Items[itemName]
            return item and item.label or nil
        end
    end
    dprint('chooseLabelResolver: no suitable backend — label resolver will always return nil')
    return function() return nil end
end

---@type fun(itemName: string): string|nil Active item-label resolver chosen at module load.
local resolveLabel = chooseLabelResolver()

---@type table<string, string|false> Per-item label cache; false is a negative-lookup sentinel.
local labelCache = {}

---Resolves a player-readable label for an item key (e.g. `lockpick` →
---`Lockpick`). Missing-label results are negatively cached so repeat
---lookups don't re-query the inventory each time.
---@param itemName string
---@return string|nil
function inventory.label(itemName)
    if not itemName then return nil end
    local cached = labelCache[itemName]
    if cached ~= nil then
        dprint('label: cache hit item=%s label=%s', itemName, tostring(cached == false and nil or cached))
        return cached == false and nil or cached
    end

    local label = resolveLabel(itemName)
    dprint('label: resolved item=%s label=%s', itemName, tostring(label))
    labelCache[itemName] = label or false
    return label
end

---Picks the right item-count resolver for the active inventory at module
---load. Falls back to walking the framework's `PlayerData` items list when
---the active inventory doesn't expose a tidy count export.
---@return fun(item: string): number
local function chooseCountResolver()
    local active = inventoryId.name
    dprint('chooseCountResolver: active=%s', tostring(active))

    if active == 'ox_inventory' then
        dprint('chooseCountResolver: selected ox_inventory (Search count)')
        return function(item) return exports.ox_inventory:Search('count', item) or 0 end
    end
    if active == 'tgiann-inventory' then
        dprint('chooseCountResolver: selected tgiann-inventory (GetItemCount)')
        return function(item) return exports['tgiann-inventory']:GetItemCount(item) or 0 end
    end
    if active == 'jaksam_inventory' then
        dprint('chooseCountResolver: selected jaksam_inventory (getTotalItemAmount)')
        return function(item) return exports.jaksam_inventory:getTotalItemAmount(item) or 0 end
    end
    if active == 'origen_inventory' then
        dprint('chooseCountResolver: selected origen_inventory (getItemCount)')
        return function(item) return exports.origen_inventory:getItemCount(item) or 0 end
    end
    if active == 'codem-inventory' then
        dprint('chooseCountResolver: selected codem-inventory (GetItemsTotalAmount)')
        return function(item) return exports['codem-inventory']:GetItemsTotalAmount(item) or 0 end
    end
    if active == 'one_inventory' then
        dprint('chooseCountResolver: selected one_inventory (GetItemCount)')
        return function(item) return exports.one_inventory:GetItemCount(item) or 0 end
    end
    if active == 'qs-inventory' or active == 'qs-inventory-pro' then
        dprint('chooseCountResolver: selected %s (GetItemTotalAmount)', active)
        return function(item) return exports[active]:GetItemTotalAmount(item) or 0 end
    end

    if framework.qb then
        dprint('chooseCountResolver: falling back to qb GetPlayerData items walk')
        return function(item)
            local data = framework.name == 'qbx' and exports.qbx_core:GetPlayerData()
                or (framework.core and framework.core.Functions.GetPlayerData())
            if not data or not data.items then return 0 end
            local total = 0
            for _, slot in pairs(data.items) do
                if slot and slot.name == item then
                    total = total + (slot.amount or slot.count or 0)
                end
            end
            return total
        end
    end
    if framework.name == 'esx' then
        dprint('chooseCountResolver: falling back to esx GetPlayerData inventory walk')
        return function(item)
            local data = framework.core.GetPlayerData()
            if not data or not data.inventory then return 0 end
            for _, slot in pairs(data.inventory) do
                if slot and slot.name == item then return slot.count or 0 end
            end
            return 0
        end
    end
    dprint('chooseCountResolver: no suitable backend — count resolver will always return 0')
    return function() return 0 end
end

---@type fun(item: string): number Active item-count resolver chosen at module load.
local resolveCount = chooseCountResolver()

---Returns the *count* of `item` in the player's inventory (0 if missing).
---@param item string
---@return number
function inventory.count(item)
    if not item then return 0 end
    return resolveCount(item) or 0
end

---Predicate form — true if the player has at least `amount` of `item`.
---@param item string
---@param amount? number Defaults to 1.
---@return boolean
function inventory.has(item, amount)
    if not item then return false end
    return inventory.count(item) >= (amount or 1)
end

---Registers metadata display labels in ox_inventory's tooltip layer.
---No-op on inventories that don't support the feature.
---@param metadata table<string, string>
---@return boolean ok
function inventory.registerDisplayMetadata(metadata)
    if inventoryId.name ~= 'ox_inventory' then
        dprint('registerDisplayMetadata: skipped — active inventory is %s not ox_inventory', tostring(inventoryId.name))
        return false
    end
    if not metadata or not next(metadata) then
        dprint('registerDisplayMetadata: skipped — metadata table is empty or nil')
        return false
    end
    dprint('registerDisplayMetadata: registering metadata with ox_inventory')
    exports.ox_inventory:displayMetadata(metadata)
    return true
end

return inventory
