---@type table Detected framework descriptor (bridge.shared.framework).
local framework = require 'bridge.shared.framework'

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:player')

---@type table Player helper module returned to consumers.
local player = {}

dprint('module load — framework: %s', tostring(framework.name))

---Picks the framework's GetPlayer implementation at module load.
---@return fun(source: number): any|nil
local function chooseGet()
    if framework.name == 'qbx' then
        dprint('chooseGet: selected Qbox (exports.qbx_core:GetPlayer)')
        return function(src)
            dprint('get: resolving src=%s via Qbox', tostring(src))
            local p = exports.qbx_core:GetPlayer(src)
            dprint('get: result=%s', p and 'found' or 'nil')
            return p
        end
    end
    if framework.qb then
        dprint('chooseGet: selected QBCore (Functions.GetPlayer)')
        return function(src)
            dprint('get: resolving src=%s via QBCore', tostring(src))
            local p = framework.core.Functions.GetPlayer(src)
            dprint('get: result=%s', p and 'found' or 'nil')
            return p
        end
    end
    if framework.name == 'esx' then
        dprint('chooseGet: selected ESX (GetPlayerFromId)')
        return function(src)
            dprint('get: resolving src=%s via ESX', tostring(src))
            local p = framework.core.GetPlayerFromId(src)
            dprint('get: result=%s', p and 'found' or 'nil')
            return p
        end
    end
    dprint('chooseGet: unsupported framework %s — returning error stub', tostring(framework.name))
    return function() return nil end
end

---@type fun(source: number): any|nil Resolved framework GetPlayer implementation.
local resolveGet = chooseGet()

---Resolves a framework-native player object for the given source.
---@param source number
---@return any|nil framework-specific player object
function player.get(source) return resolveGet(source) end

---Picks the framework's "extract identifier from player object" call at module load.
---@return fun(p: any): string|nil
local function chooseIdentifier()
    if framework.qb then
        dprint('chooseIdentifier: selected QBCore (PlayerData.citizenid)')
        return function(p) return p.PlayerData.citizenid end
    end
    if framework.name == 'esx' then
        dprint('chooseIdentifier: selected ESX (p.identifier)')
        return function(p) return p.identifier end
    end
    dprint('chooseIdentifier: unsupported framework %s — returning nil stub', tostring(framework.name))
    return function() return nil end
end

---@type fun(p: any): string|nil Resolved identifier-extraction implementation.
local resolveIdentifier = chooseIdentifier()

---Returns the player's persistent identifier (citizenid on QBCore, identifier
---on ESX). Used as the primary key for the `policetape` stats table.
---@param source number
---@return string|nil
function player.getIdentifier(source)
    dprint('getIdentifier: src=%s', tostring(source))
    local p = resolveGet(source)
    local id = p and resolveIdentifier(p) or nil
    -- Standalone: the Rockstar licence is the only identifier every player has.
    if not id and framework.name == 'standalone' then id = GetPlayerIdentifierByType(source, 'license') end
    dprint('getIdentifier: src=%s → %s', tostring(source), tostring(id))
    return id
end

---Returns a friendly "First Last" name for the player. Falls back to
---`'Unknown'` when the player can't be resolved.
---@param source number
---@return string
function player.getName(source)
    dprint('getName: src=%s', tostring(source))
    local p = resolveGet(source)
    if not p then
        dprint('getName: player not found for src=%s — returning Unknown', tostring(source))
        return framework.name == 'standalone' and (GetPlayerName(source) or 'Unknown') or 'Unknown'
    end

    if framework.name == 'esx'  then
        local name = p.getName()
        dprint('getName: src=%s (ESX) → %s', tostring(source), tostring(name))
        return name
    end
    if framework.qb then
        local name = ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname)
        dprint('getName: src=%s (QBCore) → %s', tostring(source), tostring(name))
        return name
    end
    dprint('getName: unsupported framework %s for src=%s — returning Unknown', tostring(framework.name), tostring(source))
    return 'Unknown'
end

---Returns the player's current job name.
---@param source number
---@return string|nil
function player.getJob(source)
    dprint('getJob: src=%s', tostring(source))
    local p = resolveGet(source)
    if not p then
        dprint('getJob: player not found for src=%s — returning nil', tostring(source))
        return nil
    end
    if framework.name == 'esx'  then
        local job = p.job and p.job.name or nil
        dprint('getJob: src=%s (ESX) → %s', tostring(source), tostring(job))
        return job
    end
    if framework.qb then
        local job = p.PlayerData.job and p.PlayerData.job.name or nil
        dprint('getJob: src=%s (QBCore) → %s', tostring(source), tostring(job))
        return job
    end
    return nil
end

---Returns the player's current gang name. QBCore/Qbox only — always nil on ESX.
---@param source number
---@return string|nil
function player.getGang(source)
    dprint('getGang: src=%s', tostring(source))
    local p = resolveGet(source)
    if not p then
        dprint('getGang: player not found for src=%s — returning nil', tostring(source))
        return nil
    end
    if framework.qb then
        local gang = p.PlayerData.gang and p.PlayerData.gang.name or nil
        dprint('getGang: src=%s (QBCore) → %s', tostring(source), tostring(gang))
        return gang
    end
    dprint('getGang: ESX has no gang — returning nil for src=%s', tostring(source))
    return nil
end

return player
