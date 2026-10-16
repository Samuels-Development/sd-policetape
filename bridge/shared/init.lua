---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:init')

dprint('loading bridge.shared.framework...')
require 'bridge.shared.framework'
dprint('bridge.shared.framework loaded')

dprint('loading bridge.shared.locale...')
require 'bridge.shared.locale'
dprint('bridge.shared.locale loaded')
