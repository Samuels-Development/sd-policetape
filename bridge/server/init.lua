---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:init')

dprint('init: loading server bridge sub-modules...')

require 'bridge.server.player'
dprint('init: bridge.server.player loaded')

require 'bridge.server.notify'
dprint('init: bridge.server.notify loaded')

require 'bridge.server.inventory'
dprint('init: bridge.server.inventory loaded')

require 'bridge.server.job'
dprint('init: bridge.server.job loaded')

local version = require 'bridge.server.version'
dprint('init: bridge.server.version loaded')

---@type table Detected framework descriptor (bridge.shared.framework).
local framework = require 'bridge.shared.framework'

---@type table Detected inventory resource descriptor (bridge.shared.inventory_id).
local inventoryId = require 'bridge.shared.inventory_id'

dprint('init: all server bridge modules loaded — framework=%s inventory=%s', tostring(framework.name), tostring(inventoryId.name or 'framework-default'))

print(('^2[SD-POLICETAPE]^0 Bridge initialised — Framework: ^3%s^0, Inventory: ^3%s^0'):format(
    framework.name, inventoryId.name or 'framework-default'))

-- Best-effort check of our latest GitHub release against the installed version;
-- prints an up-to-date / update-available line to the server console. Async and
-- non-fatal, so it never blocks or breaks server boot.
version.check('sd-versions/sd-policetape')
