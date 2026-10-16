--[[
    Permission hooks. Server-only: this file is not in the fxmanifest's files{}, so clients never
    receive it.

    Each hook is given the player's server id and what sd-policetape would decide on its own
    (from Config.Access: jobs, grades and ACEs). Return true or false to decide yourself, for
    example from Discord roles, a whitelist or your own duty system:

        CanUse = function(source, default)
            return default and exports['my-duty']:IsOnDuty(source)
        end,

    CanUse     place tape, restyle tape, take tape down
    CanStudio  open the Tape Studio and save or delete styles
    IsAdmin    /cleartape, and take down anybody's tape
]]
return {
    CanUse = function(source, default)
        return default
    end,

    CanStudio = function(source, default)
        return default
    end,

    IsAdmin = function(source, default)
        return default
    end,
}
