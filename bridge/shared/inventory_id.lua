---@type string[] Inventory resources probed in priority order; first started match wins.
local CANDIDATES = {
    'ox_inventory',
    'one_inventory',
    'tgiann-inventory',
    'jaksam_inventory',
    'qs-inventory',
    'qs-inventory-pro',
    'origen_inventory',
    'qb-inventory',
    'ps-inventory',
    'lj-inventory',
    'codem-inventory',
}

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:inventory')

---Walks `CANDIDATES` and returns the first inventory resource that's
---currently started. Returns nil when no supported inventory is running, in
---which case downstream modules fall back to framework-native paths.
---@return string|nil resource name, or nil if none is started.
local function detect()
    dprint('detecting inventory — probing %d candidates', #CANDIDATES)
    for i = 1, #CANDIDATES do
        local state = GetResourceState(CANDIDATES[i])
        dprint('  probe: %-18s state=%s', CANDIDATES[i], tostring(state))
        if state == 'started' then
            dprint('detected inventory: %s', CANDIDATES[i])
            return CANDIDATES[i]
        end
    end
    dprint('no recognised inventory resource started — using framework-default paths')
    return nil
end

return {
    name = detect(),
    candidates = CANDIDATES,
}
