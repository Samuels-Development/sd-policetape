---Validates and normalises a tape style recipe (see configs/styles.lua for the fields).
---
---Every style goes through here on the server before any client sees it: the built-ins when
---the resource starts, and studio styles when an admin saves one. The result is complete (every
---optional field present or explicitly false) so the painter never has to guess a default, and
---it holds nothing a client could use to make another client's page do something else: colours
---are #rrggbb, every choice is from a fixed list and every number is clamped.
local schema = {}

schema.CATEGORIES = { 'police', 'federal', 'crime', 'fire', 'ems', 'hazard', 'utility', 'plain', 'international', 'custom' }
schema.PATTERNS = { 'none', 'diagonal', 'blocks', 'checker', 'chevron', 'band', 'dashes', 'dots', 'zigzag', 'lines' }
schema.FONTS = { 'oswald', 'anton', 'bebas', 'barlow', 'roboto', 'teko', 'stencil', 'archivo', 'russo', 'staatliches', 'blackops' }
schema.SEPARATORS = { 'none', 'dot', 'star', 'bar', 'slash', 'diamond', 'cross', 'chevron' }
schema.EDGE_STYLES = { 'solid', 'double', 'dashed', 'checker' }
schema.FADES = { 'gradient', 'split' }

schema.MAX_ITEMS = 6
schema.MAX_ITEM_LENGTH = 32
schema.MAX_LABEL_LENGTH = 40

local function set(list)
    local s = {}
    for i = 1, #list do s[list[i]] = true end
    return s
end

local CATEGORY, PATTERN, FONT, SEPARATOR = set(schema.CATEGORIES), set(schema.PATTERNS), set(schema.FONTS), set(schema.SEPARATORS)
local EDGE_STYLE, FADE = set(schema.EDGE_STYLES), set(schema.FADES)

---@param v any
---@param fallback string
---@return string
local function color(v, fallback)
    if type(v) == 'string' and v:match('^#%x%x%x%x%x%x$') then return v:upper() end
    if type(v) == 'string' and v:match('^#%x%x%x$') then
        local r, g, b = v:sub(2, 2), v:sub(3, 3), v:sub(4, 4)
        return ('#' .. r .. r .. g .. g .. b .. b):upper()
    end
    return fallback
end

---@param v any
---@param lo number
---@param hi number
---@param fallback number
---@return number
local function num(v, lo, hi, fallback)
    v = tonumber(v)
    if not v or v ~= v then return fallback end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

---Text a player typed, made safe to print: no control characters, no markup characters, trimmed.
---@param v any
---@param maxLen integer
---@return string|nil
local function text(v, maxLen)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('[%c<>`\\]', ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s%s+', ' ')
    if v == '' then return nil end
    -- Cut by characters, not bytes, so an accented letter is never split in half.
    if utf8 and utf8.len(v) and utf8.len(v) > maxLen then
        v = v:sub(1, utf8.offset(v, maxLen + 1) - 1)
    elseif #v > maxLen * 4 then
        v = v:sub(1, maxLen)
    end
    return v
end
schema.text = text

---Normalises a style. Returns nil and a reason when it cannot be used at all.
---@param s any
---@return table|nil style
---@return string|nil reason
function schema.normalise(s)
    if type(s) ~= 'table' then return nil, 'not a table' end

    local id = type(s.id) == 'string' and s.id:lower() or nil
    if not id or not id:match('^[a-z0-9_]+$') or #id < 2 or #id > 48 then return nil, 'bad id' end

    local out = {
        id = id,
        label = text(s.label, schema.MAX_LABEL_LENGTH) or id,
        category = CATEGORY[s.category] and s.category or 'custom',
        region = type(s.region) == 'string' and s.region:upper():match('^%u%u?%u?$') or false,
        base = color(s.base, '#F6D10E'),
        custom = s.custom == true,
    }

    -- A second background colour: a gradient from top to bottom, or the tape split in two.
    local b2 = type(s.base2) == 'table' and s.base2 or nil
    out.base2 = b2 and FADE[b2.mode] and { color = color(b2.color, '#FFFFFF'), mode = b2.mode } or false

    local p = type(s.pattern) == 'table' and s.pattern or nil
    if p and PATTERN[p.type] and p.type ~= 'none' then
        out.pattern = {
            type = p.type,
            color = color(p.color, '#121212'),
            size = num(p.size, 0.15, 4.0, 0.6),
            angle = num(p.angle, -75, 75, 45),
            opacity = num(p.opacity, 0.1, 1, 1),
            fill = num(p.fill, 0.15, 0.85, 0.5), -- how much of each period is printed (stripes, blocks, dashes...)
        }
    else
        out.pattern = false
    end

    local e = type(s.edges) == 'table' and s.edges or nil
    if e and num(e.size, 0, 0.3, 0) > 0 then
        out.edges = {
            color = color(e.color, '#121212'),
            size = num(e.size, 0.01, 0.3, 0.08),
            style = EDGE_STYLE[e.style] and e.style or 'solid',
            inset = num(e.inset, 0, 0.2, 0), -- a gap of base colour between the band and the tape's edge
        }
    else
        out.edges = false
    end

    local t = type(s.text) == 'table' and s.text or nil
    local items = {}
    if t and type(t.items) == 'table' then
        for i = 1, math.min(#t.items, schema.MAX_ITEMS) do
            local item = text(t.items[i], schema.MAX_ITEM_LENGTH)
            if item then items[#items + 1] = item end
        end
    end

    if #items > 0 then
        local plate = type(t.plate) == 'table' and t.plate or nil
        local outline = type(t.outline) == 'table' and t.outline or nil
        local shadow = type(t.shadow) == 'table' and t.shadow or nil
        out.text = {
            items = items,
            color = color(t.color, '#121212'),
            altColor = t.altColor and color(t.altColor, false) or false, -- every other piece of wording in this
            font = FONT[t.font] and t.font or 'oswald',
            size = num(t.size, 0.2, 0.95, 0.6),
            spacing = num(t.spacing, -0.05, 0.4, 0.04),
            width = num(t.width, 0.6, 1.5, 1), -- letters narrower or wider than the face draws them
            offset = num(t.offset, -0.3, 0.3, 0), -- up (-) or down (+) from the middle, in tape widths
            italic = t.italic == true,
            plate = plate and { color = color(plate.color, '#FFFFFF'), padding = num(plate.padding, 0, 1, 0.25), radius = num(plate.radius, 0, 0.5, 0) } or false,
            outline = outline and num(outline.width, 0, 0.3, 0) > 0
                and { color = color(outline.color, '#000000'), width = num(outline.width, 0.01, 0.3, 0.08) } or false,
            shadow = shadow and { color = color(shadow.color, '#000000'), distance = num(shadow.distance, 0.01, 0.15, 0.04) } or false,
            separator = SEPARATOR[t.separator] and t.separator or 'none',
            separatorColor = t.separatorColor and color(t.separatorColor, false) or false,
            separatorSize = num(t.separatorSize, 0.5, 2, 1),
            repeats = math.floor(num(t.repeats, 1, 4, 1)),
        }
    else
        out.text = false
    end

    return out
end

return schema
