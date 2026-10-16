---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:init')

dprint('loading bridge.client.notify...')
require 'bridge.client.notify'
dprint('bridge.client.notify loaded')

dprint('loading bridge.client.inventory...')
require 'bridge.client.inventory'
dprint('bridge.client.inventory loaded')
