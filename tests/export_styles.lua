-- lua tests/export_styles.lua > web/src/ui/dev-styles.json
-- The built-in styles, normalised exactly as the server does it, as JSON for the browser preview
-- (npm run dev). Not shipped.
local schema = dofile('shared/schema.lua')
local styles = dofile('configs/styles.lua')

local function encode(v)
    local t = type(v)
    if t == 'table' then
        if #v > 0 or next(v) == nil then
            local out = {}
            for i = 1, #v do out[i] = encode(v[i]) end
            return '[' .. table.concat(out, ',') .. ']'
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys)
        local out = {}
        for _, k in ipairs(keys) do out[#out + 1] = '"' .. k .. '":' .. encode(v[k]) end
        return '{' .. table.concat(out, ',') .. '}'
    elseif t == 'string' then
        local escaped = v:gsub('[%c"\\]', function(c) return ('\\u%04x'):format(c:byte()) end)
        return '"' .. escaped .. '"'
    elseif t == 'number' then
        return (math.type(v) == 'integer') and tostring(v) or ('%.4g'):format(v)
    else
        return tostring(v)
    end
end

local out = {}
for i, s in ipairs(styles) do out[i] = assert(schema.normalise(s)) end
io.write(encode(out))
