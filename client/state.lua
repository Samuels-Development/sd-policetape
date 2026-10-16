---What this client knows about itself: what it may do, the styles in order, and the style it
---last placed with (kept between sessions in KVP).
local state = {
    perms = { use = false, studio = false, admin = false },
    styles = {}, ---@type table[] in the server's order
    byId = {}, ---@type table<string, table>
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

function state.style(id)
    return state.byId[id]
end

---The style placing starts with: the last one used, if it still exists.
function state.defaultStyle()
    local saved = GetResourceKvpString(KVP)
    if saved and state.byId[saved] then return saved end
    return state.styles[1] and state.styles[1].id or nil
end

function state.setDefaultStyle(id)
    if state.byId[id] then SetResourceKvp(KVP, id) end
end

---The style `step` places away from `id` in the list, wrapping round.
function state.step(id, step)
    local n = #state.styles
    if n == 0 then return id end
    local s = state.byId[id]
    local i = s and s.index or 1
    return state.styles[((i - 1 + step) % n) + 1].id
end

return state
