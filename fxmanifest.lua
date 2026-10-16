fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sd-policetape'
author 'Samuel#0008'
version '1.0.0'
description 'Police tape that sags, sways in the wind and gives way to people and vehicles: 100 styles and an in-game studio for more'

shared_scripts {
    '@ox_lib/init.lua',
    'bridge/shared/init.lua',
}

client_scripts {
    'bridge/client/init.lua',
    'client/main.lua',
}

server_scripts {
    'bridge/server/init.lua',
    'server/main.lua',
}

--[[
    Two pages. web/build/ui.html is the interface (the prompt while placing or looking at tape,
    the style picker, the Tape Studio). web/build/atlas.html is never seen: a DUI loads it and
    every tape in the world is drawn from its canvas (client/tape/atlas.lua).

    The post, the twenty cones and the roll in your hand stream from stream/ (made by
    tools/build_props.py and tools/build_cones.py). Every one of them in the world belongs to this
    resource and is deleted when it stops, so it can still be restarted with tape out. A model
    changed for players already connected needs a new name: a game keeps the first copy of a
    streamed file it loads.

    configs/server/ and configs/styles.lua are read by the server only and are not in files{}.
]]
ui_page 'web/build/ui.html'

data_file 'DLC_ITYP_REQUEST' 'stream/sd_policetape.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/sd_policetape_cones.ytyp'

files {
    'stream/sd_policetape.ytyp',
    'stream/sd_policetape_cones.ytyp',
    'bridge/client/*.lua',
    'bridge/shared/*.lua',
    'client/*.lua',
    'client/tape/*.lua',
    'shared/*.lua',
    'configs/config.lua',
    'configs/holders.lua',
    'locales/*.json',
    'web/build/ui.html',
    'web/build/atlas.html',
    'web/build/assets/*.js',
    'web/build/assets/*.css',
    'web/build/assets/*.woff2',
}

dependencies {
    'ox_lib',
}

escrow_ignore {
    'bridge/**/*.lua',
    'configs/*.lua',
    'configs/server/*.lua',
    'locales/*.json',
    'shared/schema.lua',
}
