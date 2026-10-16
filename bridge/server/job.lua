---@type table Detected framework descriptor (bridge.shared.framework).
local framework = require 'bridge.shared.framework'

---@type table Player resolution helpers (bridge.server.player).
local player_mod = require 'bridge.server.player'

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:job')

---@type table Job helper module returned to consumers.
local job = {}

dprint('module load — framework: %s', tostring(framework.name))

---Returns the player's current job name.
---@param source number
---@return string|nil
function job.getName(source)
    dprint('getName: src=%s', tostring(source))
    local p = player_mod.get(source)
    if not p then
        dprint('getName: player not found for src=%s — returning nil', tostring(source))
        return nil
    end
    if framework.name == 'esx'  then
        local name = p.job and p.job.name or nil
        dprint('getName: src=%s (ESX) → %s', tostring(source), tostring(name))
        return name
    end
    if framework.qb then
        local name = p.PlayerData.job and p.PlayerData.job.name or nil
        dprint('getName: src=%s (QBCore) → %s', tostring(source), tostring(name))
        return name
    end
    return nil
end

---Returns the player's current job grade level.
---@param source number
---@return integer
function job.getGrade(source)
    dprint('getGrade: src=%s', tostring(source))
    local p = player_mod.get(source)
    if not p then
        dprint('getGrade: player not found for src=%s — returning 0', tostring(source))
        return 0
    end
    if framework.name == 'esx'  then
        local grade = p.job and p.job.grade or 0
        dprint('getGrade: src=%s (ESX) → %d', tostring(source), grade)
        return grade
    end
    if framework.qb then
        local grade = p.PlayerData.job and p.PlayerData.job.grade and p.PlayerData.job.grade.level or 0
        dprint('getGrade: src=%s (QBCore) → %d', tostring(source), grade)
        return grade
    end
    return 0
end

---Predicate: does the player have `jobName` at grade ≥ `minGrade`?
---@param source number
---@param jobName string
---@param minGrade? integer Default 0.
---@return boolean
function job.has(source, jobName, minGrade)
    minGrade = minGrade or 0
    dprint('has: src=%s jobName=%s minGrade=%d', tostring(source), tostring(jobName), minGrade)
    local p = player_mod.get(source)
    if not p then
        dprint('has: player not found for src=%s — returning false', tostring(source))
        return false
    end

    if framework.qb then
        local data = p.PlayerData.job
        if data and data.name == jobName then
            local grade = data.grade and data.grade.level or 0
            local result = grade >= minGrade
            dprint('has: src=%s QBCore job=%s grade=%d minGrade=%d → %s', tostring(source), tostring(data.name), grade, minGrade, tostring(result))
            return result
        end
        dprint('has: src=%s QBCore job mismatch (current=%s wanted=%s) → false', tostring(source), tostring(data and data.name), tostring(jobName))
    elseif framework.name == 'esx' then
        local data = p.job
        if data and data.name == jobName then
            local grade = data.grade or 0
            local result = grade >= minGrade
            dprint('has: src=%s ESX job=%s grade=%d minGrade=%d → %s', tostring(source), tostring(data.name), grade, minGrade, tostring(result))
            return result
        end
        dprint('has: src=%s ESX job mismatch (current=%s wanted=%s) → false', tostring(source), tostring(data and data.name), tostring(jobName))
    end
    return false
end

---Convenience: returns true if the player matches any `{ name=..., minGrade=? }`
---entry. An empty list returns true so callers can use it as a default-allow
---gate.
---@param source number
---@param options { name: string, minGrade?: integer }[]
---@return boolean
function job.hasAny(source, options)
    dprint('hasAny: src=%s options count=%d', tostring(source), options and #options or 0)
    if not options or #options == 0 then
        dprint('hasAny: empty options list — default-allow → true')
        return true
    end
    for i = 1, #options do
        if job.has(source, options[i].name, options[i].minGrade or 0) then
            dprint('hasAny: src=%s matched option[%d] name=%s → true', tostring(source), i, tostring(options[i].name))
            return true
        end
    end
    dprint('hasAny: src=%s no match found → false', tostring(source))
    return false
end

---Sets the player's job to `jobName` at grade `grade`. Returns true on success.
---@param source number
---@param jobName string
---@param grade? integer Default 0.
---@return boolean
function job.set(source, jobName, grade)
    grade = grade or 0
    dprint('set: src=%s jobName=%s grade=%d', tostring(source), tostring(jobName), grade)
    local p = player_mod.get(source)
    if not p then
        dprint('set: player not found for src=%s — returning false', tostring(source))
        return false
    end

    if framework.qb then
        local result = p.Functions.SetJob(jobName, grade)
        dprint('set: src=%s QBCore SetJob(%s, %d) → %s', tostring(source), tostring(jobName), grade, tostring(result))
        return result
    end
    if framework.name == 'esx' then
        p.setJob(jobName, grade)
        dprint('set: src=%s ESX setJob(%s, %d) called', tostring(source), tostring(jobName), grade)
        return true
    end
    dprint('set: unsupported framework %s for src=%s — returning false', tostring(framework.name), tostring(source))
    return false
end

---Builds a `{ [jobName] = true }` lookup from a job-name array.
---@param jobNames string[]|nil
---@return table<string, boolean>
local function nameSet(jobNames)
    local set = {}
    for i = 1, #(jobNames or {}) do set[jobNames[i]] = true end
    return set
end

---Every online player object the framework knows about, as a plain array.
---Prefers the framework's bulk accessor and falls back to resolving the
---`GetPlayers()` source list one at a time.
---@return any[]
local function onlinePlayers()
    local out = {}

    if framework.name == 'qbx' then
        local ok, players = pcall(function() return exports.qbx_core:GetQBPlayers() end)
        if ok and type(players) == 'table' then
            for _, p in pairs(players) do out[#out + 1] = p end
            dprint('onlinePlayers: Qbox GetQBPlayers → %d player(s)', #out)
            return out
        end
        dprint('onlinePlayers: Qbox GetQBPlayers unavailable — falling back to GetPlayers()')
    elseif framework.qb then
        local ok, players = pcall(function() return framework.core.Functions.GetQBPlayers() end)
        if ok and type(players) == 'table' then
            for _, p in pairs(players) do out[#out + 1] = p end
            dprint('onlinePlayers: QBCore GetQBPlayers → %d player(s)', #out)
            return out
        end
        dprint('onlinePlayers: QBCore GetQBPlayers unavailable — falling back to GetPlayers()')
    elseif framework.name == 'esx' then
        local ok, players = pcall(function() return framework.core.GetExtendedPlayers() end)
        if ok and type(players) == 'table' then
            for _, p in pairs(players) do out[#out + 1] = p end
            dprint('onlinePlayers: ESX GetExtendedPlayers → %d player(s)', #out)
            return out
        end
        dprint('onlinePlayers: ESX GetExtendedPlayers unavailable — falling back to GetPlayers()')
    end

    local sources = GetPlayers()
    for i = 1, #sources do
        local p = player_mod.get(tonumber(sources[i]))
        if p then out[#out + 1] = p end
    end
    dprint('onlinePlayers: GetPlayers() fallback → %d resolved player(s)', #out)
    return out
end

---Reads the job name and duty flag off a framework-native player object.
---@param p any Framework player object.
---@return string|nil name
---@return boolean onduty
local function jobOf(p)
    local data
    if framework.qb then
        data = p.PlayerData and p.PlayerData.job
    else
        data = p.job
    end
    if not data then return nil, false end
    return data.name, data.onduty == true
end

---Counts online players whose job name appears in `jobNames`.
---
---`onDutyOnly` is QBCore/Qbox only: ESX has no native duty state, so every
---player holding a matching job is counted there whatever the flag says.
---@param jobNames string[] Job names that count towards the total.
---@param onDutyOnly? boolean Count only players flagged on duty (QBCore/Qbox only).
---@return integer
function job.countOnline(jobNames, onDutyOnly)
    dprint('countOnline: jobNames=%d entries onDutyOnly=%s', jobNames and #jobNames or 0, tostring(onDutyOnly))
    if not jobNames or #jobNames == 0 then
        dprint('countOnline: empty job list → 0')
        return 0
    end

    local wanted = nameSet(jobNames)
    local dutyGate = onDutyOnly and framework.qb
    local players = onlinePlayers()
    local count = 0

    for i = 1, #players do
        local name, onduty = jobOf(players[i])
        if name and wanted[name] then
            if not dutyGate or onduty then
                count = count + 1
            else
                dprint('countOnline: skipping job=%s — matching job but off duty', tostring(name))
            end
        end
    end

    dprint('countOnline: → %d matching player(s)', count)
    return count
end

return job
