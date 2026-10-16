---What this client knows about itself: what it may do, the styles in order, the style it last
---placed with (kept between sessions in KVP), and which styles and holders the admin menu has
---taken away from players.
local state = {
    perms = { use = false, studio = false, admin = false },
    styles = {}, ---@type table[] in the server's order
    byId = {}, ---@type table<string, table>
    off = { styles = {}, holders = {} }, ---@type { styles: table<string, true>, holders: table<string, true> }
}

local KVP = 'sd-policetape:style'

function state.setStyles(list)
    state.styles = list
    local byId = {}
    for i = 1, #list do
        list[i].index = i
        byId[list[i].id] = list[i]
    end
    state.byId = byId
end

---What players cannot put up: two lists of ids from the server (an empty one may come as {}).
function state.setOff(styles, holders)
    local function set(v)
        local out = {}
        if type(v) == 'table' then
            for _, id in pairs(v) do
                if type(id) == 'string' then out[id] = true end
            end
        end
        return out
    end
    state.off = { styles = set(styles), holders = set(holders) }
end

function state.style(id)
    return state.byId[id]
end

---Whether this player may put up tape in style `id`.
function state.styleAllowed(id)
    return state.byId[id] ~= nil and not state.off.styles[id]
end

function state.holderAllowed(id)
    return id ~= nil and not state.off.holders[id]
end

---The first style that may be put up.
function state.firstStyle()
    for i = 1, #state.styles do
        if not state.off.styles[state.styles[i].id] then return state.styles[i].id end
    end
    return nil
end

---The style placing starts with: the last one used, if it still exists and may be used.
function state.defaultStyle()
    local saved = GetResourceKvpString(KVP)
    if saved and state.styleAllowed(saved) then return saved end
    return state.firstStyle()
end

function state.setDefaultStyle(id)
    if state.styleAllowed(id) then SetResourceKvp(KVP, id) end
end

---The style `step` places away from `id` in the list, wrapping round and skipping what is off.
function state.step(id, step)
    local n = #state.styles
    if n == 0 then return id end
    local s = state.byId[id]
    local i = s and s.index or 1
    for _ = 1, n do
        i = ((i - 1 + step) % n) + 1
        if not state.off.styles[state.styles[i].id] then return state.styles[i].id end
    end
    return id
end

return state
