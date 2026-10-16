-- lua tests/schema_utf8.lua : UTF-8 text must survive sanitising and be cut on character boundaries.
local schema = dofile('shared/schema.lua')
local src = 'ZAKAZ WSTĘPU ÆØÅ ÄÖÜ ÉÍ'
local out = schema.text(src, 32)
assert(out == src, 'changed: ' .. tostring(out))
local cut = schema.text(('Ę'):rep(40), 32)
assert(utf8.len(cut) == 32, 'cut length ' .. tostring(utf8.len(cut)))
assert(schema.text('<b>hi</b>\n\tthere', 32) == 'bhi/bthere', schema.text('<b>hi</b>\n\tthere', 32))
print('ok', #src, utf8.len(src))
