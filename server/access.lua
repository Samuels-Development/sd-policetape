---Who may do what. The defaults come from Config.Access; configs/server/permissions.lua has the
---final word.
local config = require 'configs.config'
local hooks = require 'configs.server.permissions'
local job = require 'bridge.server.job'

local ACCESS = config.Access
local access = {}

---A real boolean. IsPlayerAceAllowed answers 1 or false, and 1 == true is false in Lua, which
---made every ACE check (admins included) fail until this was found in game.
local function ace(source, name)
    if not name or name == '' then return false end
    local allowed = IsPlayerAceAllowed(source, name)
    return allowed == true or allowed == 1
end

local function hasJob(source, jobs)
    if not jobs or next(jobs) == nil then return false end
    local name = job.getName(source)
    if not name then return false end
    local min = jobs[name]
    if min == nil then return false end
    return (job.getGrade(source) or 0) >= (tonumber(min) or 0)
end

function access.isAdmin(source)
    -- txAdmin's `add_ace group.admin command allow` grants every command.* ace, so an admin can
    -- always run the clear command; IsPlayerAceAllowed(src, 'group.admin') is never true.
    local default = ace(source, ACCESS.AdminAce) or ace(source, 'command.' .. config.Commands.Clear)
    return hooks.IsAdmin(source, default) and true or false
end

function access.canUse(source)
    local default = ACCESS.Everyone == true or hasJob(source, ACCESS.Jobs) or ace(source, ACCESS.Ace)
        or access.isAdmin(source)
    return hooks.CanUse(source, default) and true or false
end

function access.canStudio(source)
    local default = ace(source, ACCESS.StudioAce) or ace(source, 'command.' .. config.Commands.Studio)
        or hasJob(source, ACCESS.StudioJobs) or access.isAdmin(source)
    return hooks.CanStudio(source, default) and true or false
end

---What the client is told (only to show or hide things; every action is checked again here).
function access.perms(source)
    return { use = access.canUse(source), studio = access.canStudio(source), admin = access.isAdmin(source) }
end

return access
