--[[
    The built-in tape styles. A hundred of them.

    A style is a recipe, not a picture: every client paints it for itself (web/src/paint/tape.ts)
    into a strip that repeats every 1.2 m along the tape. So a new style costs nothing to ship,
    and the in-game Tape Studio (/tapestudio) makes more without touching this file. Styles made
    there live in data/styles.json; these here are the ones every server starts with.

    You can edit, reorder or delete anything below. Keep `id` unique and stable: placed tapes
    remember their style by id, and a tape whose style no longer exists falls back to the first
    style in this list.

    Fields (everything except id, label and base is optional):

      id        lowercase letters, digits, underscore
      label     the name players see
      category  police | federal | crime | fire | ems | hazard | utility | plain | international
      region    a country tag shown next to the name (GB, DE ...)
      base      background colour
      pattern   { type = 'diagonal' | 'blocks' | 'checker' | 'chevron' | 'band' | 'dashes',
                  color = '#rrggbb', size = 0.6 (in tape widths), angle = 45 (diagonal only) }
      edges     { color = '#rrggbb', size = 0.08 }   a band along both edges, as a fraction of the width
      text      {
                  items     = { 'POLICE LINE', 'DO NOT CROSS' }   printed in turn along the tape
                  color     = '#rrggbb'
                  font      = oswald | anton | bebas | barlow | roboto | teko | stencil | archivo | russo | staatliches | blackops
                  size      = 0.62   letter height as a fraction of the tape width
                  spacing   = 0.03   extra letter spacing (em)
                  italic    = false
                  plate     = { color = '#rrggbb', padding = 0.25 }   a box behind each item
                  outline   = { color = '#rrggbb', width = 0.08 }
                  separator = none | dot | star | bar | slash | diamond | cross | chevron
                  separatorColor = '#rrggbb'   (default: the text colour)
                  repeats   = 1      how many times the items appear per 1.2 m
                }

    Wording: the international styles use the everyday wording of each country's police tape.
    Agency names in the Los Santos styles (LSPD, BCSO, SAHP, FIB, LSFD, NOOSE) are the game's
    own fictional ones.
]]

local YELLOW = '#F6D10E'
local BLACK = '#121212'
local WHITE = '#FFFFFF'
local RED = '#C8102E'
local BLUE = '#0B3D91'
local NAVY = '#0A1F44'
local ORANGE = '#F26B1D'
local GREEN = '#0E8A4A'

return {
    -- Police -------------------------------------------------------------------------------------
    {
        id = 'police_line', label = 'Police Line', category = 'police', region = 'US', base = YELLOW,
        text = { items = { 'POLICE LINE', 'DO NOT CROSS' }, color = BLACK, font = 'oswald', size = 0.64, spacing = 0.04 },
    },
    {
        id = 'police_line_bold', label = 'Police Line (Bold)', category = 'police', region = 'US', base = YELLOW,
        edges = { color = BLACK, size = 0.09 },
        text = { items = { 'POLICE LINE', 'DO NOT CROSS' }, color = BLACK, font = 'anton', size = 0.64, spacing = 0.05, separator = 'dot' },
    },
    {
        id = 'police_line_blue', label = 'Police Line (Blue)', category = 'police', region = 'US', base = BLUE,
        text = { items = { 'POLICE LINE', 'DO NOT CROSS' }, color = WHITE, font = 'oswald', size = 0.62, spacing = 0.05, separator = 'bar' },
    },
    {
        id = 'police_line_white', label = 'Police Line (White)', category = 'police', region = 'US', base = WHITE,
        edges = { color = BLUE, size = 0.1 },
        text = { items = { 'POLICE LINE', 'DO NOT CROSS' }, color = BLUE, font = 'barlow', size = 0.56, spacing = 0.06, separator = 'star' },
    },
    {
        id = 'police_investigation', label = 'Police Investigation', category = 'police', region = 'US', base = YELLOW,
        text = { items = { 'POLICE INVESTIGATION', 'DO NOT ENTER' }, color = BLACK, font = 'barlow', size = 0.58, spacing = 0.03, separator = 'slash' },
    },
    {
        id = 'lspd_line', label = 'LSPD', category = 'police', region = 'LS', base = NAVY,
        edges = { color = '#C9A227', size = 0.08 },
        text = { items = { 'LSPD', 'POLICE LINE', 'DO NOT CROSS' }, color = WHITE, font = 'oswald', size = 0.56, spacing = 0.06, separator = 'star', separatorColor = '#C9A227' },
    },
    {
        id = 'sheriff_line', label = "Sheriff's Line", category = 'police', region = 'US', base = YELLOW,
        text = { items = { "SHERIFF'S LINE", 'DO NOT CROSS' }, color = BLACK, font = 'oswald', size = 0.62, spacing = 0.04, separator = 'star' },
    },
    {
        id = 'sheriff_green', label = "Sheriff's Line (Green)", category = 'police', region = 'US', base = '#1F4D2B',
        edges = { color = '#C9A86A', size = 0.08 },
        text = { items = { "SHERIFF'S LINE", 'DO NOT CROSS' }, color = '#F2E3B3', font = 'oswald', size = 0.56, spacing = 0.05, separator = 'star', separatorColor = '#C9A86A' },
    },
    {
        id = 'bcso_line', label = 'BCSO', category = 'police', region = 'LS', base = '#C9A86A',
        edges = { color = '#2B2116', size = 0.07 },
        text = { items = { 'BCSO', 'SHERIFF', 'DO NOT CROSS' }, color = '#2B2116', font = 'bebas', size = 0.6, spacing = 0.06, separator = 'star' },
    },
    {
        id = 'sahp_line', label = 'SAHP', category = 'police', region = 'LS', base = '#10263F',
        text = { items = { 'SAHP', 'STATE PATROL', 'DO NOT CROSS' }, color = '#F2C14E', font = 'barlow', size = 0.56, spacing = 0.06, separator = 'diamond' },
    },
    {
        id = 'lspd_white', label = 'LSPD (White)', category = 'police', region = 'LS', base = WHITE,
        edges = { color = NAVY, size = 0.1 },
        text = { items = { 'LOS SANTOS POLICE', 'DO NOT CROSS' }, color = NAVY, font = 'barlow', size = 0.54, spacing = 0.06, separator = 'star', separatorColor = '#C9A227' },
    },
    {
        id = 'lssd_line', label = 'LSSD', category = 'police', region = 'LS', base = '#5A4A2F',
        edges = { color = '#E0C27A', size = 0.07 },
        text = { items = { 'LSSD', "SHERIFF'S DEPARTMENT", 'DO NOT CROSS' }, color = '#F3E6C4', font = 'oswald', size = 0.52, spacing = 0.05, separator = 'star', separatorColor = '#E0C27A' },
    },
    {
        id = 'park_ranger', label = 'Park Ranger', category = 'police', region = 'LS', base = '#2F4A2A',
        edges = { color = '#D8C9A3', size = 0.06 },
        text = { items = { 'PARK RANGER', 'AREA CLOSED' }, color = '#F1E7CC', font = 'bebas', size = 0.6, spacing = 0.08, separator = 'diamond', separatorColor = '#D8C9A3' },
    },
    {
        id = 'police_k9', label = 'K-9 Unit', category = 'police', region = 'US', base = BLACK,
        edges = { color = YELLOW, size = 0.07 },
        text = { items = { 'K-9 UNIT', 'KEEP BACK' }, color = YELLOW, font = 'russo', size = 0.5, spacing = 0.06, separator = 'dot' },
    },
    {
        id = 'swat_line', label = 'SWAT', category = 'police', region = 'US', base = '#1C1F22',
        edges = { color = '#8A9199', size = 0.05 },
        text = { items = { 'SWAT', 'TACTICAL OPERATION', 'STAY BACK' }, color = WHITE, font = 'stencil', size = 0.52, spacing = 0.06, separator = 'bar', separatorColor = '#8A9199' },
    },
    {
        id = 'accident_investigation', label = 'Accident Investigation', category = 'police', region = 'US', base = YELLOW,
        edges = { color = BLUE, size = 0.07 },
        text = { items = { 'ACCIDENT INVESTIGATION', 'DO NOT CROSS' }, color = BLACK, font = 'oswald', size = 0.56, spacing = 0.04, separator = 'chevron' },
    },

    -- Federal ------------------------------------------------------------------------------------
    {
        id = 'fib_line', label = 'FIB', category = 'federal', region = 'LS', base = '#0E1A2B',
        text = { items = { 'FIB', 'FEDERAL INVESTIGATION', 'DO NOT CROSS' }, color = YELLOW, font = 'russo', size = 0.46, spacing = 0.06, separator = 'bar' },
    },
    {
        id = 'noose_line', label = 'NOOSE', category = 'federal', region = 'LS', base = '#151515',
        edges = { color = YELLOW, size = 0.06 },
        text = { items = { 'NOOSE', 'TACTICAL ZONE', 'KEEP BACK' }, color = '#E8E8E8', font = 'stencil', size = 0.56, spacing = 0.06, separator = 'chevron', separatorColor = YELLOW },
    },
    {
        id = 'fib_yellow', label = 'FIB (Yellow)', category = 'federal', region = 'LS', base = YELLOW,
        edges = { color = '#0E1A2B', size = 0.07 },
        text = { items = { 'FIB', 'FEDERAL CRIME SCENE', 'DO NOT CROSS' }, color = '#0E1A2B', font = 'russo', size = 0.46, spacing = 0.05, separator = 'bar' },
    },
    {
        id = 'iaa_line', label = 'IAA', category = 'federal', region = 'LS', base = '#2A2F36',
        edges = { color = '#B8BEC6', size = 0.05 },
        text = { items = { 'IAA', 'RESTRICTED ACCESS', 'DO NOT CROSS' }, color = '#E6E8EB', font = 'archivo', size = 0.42, spacing = 0.06, separator = 'diamond', separatorColor = '#B8BEC6' },
    },
    {
        id = 'doa_line', label = 'DOA', category = 'federal', region = 'LS', base = '#14213D',
        text = { items = { 'DOA', 'DRUG OBSERVATION AGENCY' }, color = '#F5B700', font = 'barlow', size = 0.54, spacing = 0.06, separator = 'star' },
    },
    {
        id = 'zancudo_line', label = 'Fort Zancudo', category = 'federal', region = 'LS', base = '#3B4A2C',
        edges = { color = '#C9B88A', size = 0.06 },
        text = { items = { 'FORT ZANCUDO', 'MILITARY ZONE' }, color = '#EDE6D0', font = 'stencil', size = 0.52, spacing = 0.06, separator = 'star', separatorColor = '#C9B88A' },
    },
    {
        id = 'government_property', label = 'Government Property', category = 'federal', region = 'US', base = WHITE,
        edges = { color = BLUE, size = 0.09 },
        text = { items = { 'GOVERNMENT PROPERTY', 'NO TRESPASSING' }, color = BLUE, font = 'roboto', size = 0.5, spacing = 0.05, separator = 'star', separatorColor = RED },
    },

    -- Crime scene --------------------------------------------------------------------------------
    {
        id = 'crime_scene', label = 'Crime Scene', category = 'crime', region = 'US', base = YELLOW,
        text = { items = { 'CRIME SCENE', 'DO NOT CROSS' }, color = BLACK, font = 'oswald', size = 0.64, spacing = 0.04 },
    },
    {
        id = 'crime_scene_bold', label = 'Crime Scene (Bold)', category = 'crime', region = 'US', base = YELLOW,
        edges = { color = BLACK, size = 0.09 },
        text = { items = { 'CRIME SCENE', 'DO NOT CROSS' }, color = BLACK, font = 'anton', size = 0.64, spacing = 0.05, separator = 'dot' },
    },
    {
        id = 'crime_scene_red', label = 'Crime Scene (Red)', category = 'crime', region = 'US', base = '#B3141C',
        text = { items = { 'CRIME SCENE', 'DO NOT CROSS' }, color = WHITE, font = 'oswald', size = 0.62, spacing = 0.05, separator = 'bar' },
    },
    {
        id = 'crime_scene_black', label = 'Crime Scene (Black)', category = 'crime', region = 'US', base = BLACK,
        edges = { color = YELLOW, size = 0.06 },
        text = { items = { 'CRIME SCENE', 'DO NOT CROSS' }, color = YELLOW, font = 'oswald', size = 0.58, spacing = 0.05 },
    },
    {
        id = 'csi', label = 'Crime Scene Investigation', category = 'crime', region = 'US', base = YELLOW,
        text = { items = { 'CRIME SCENE INVESTIGATION' }, color = BLACK, font = 'barlow', size = 0.62, spacing = 0.08, separator = 'slash' },
    },
    {
        id = 'evidence', label = 'Evidence', category = 'crime', region = 'US', base = '#ECE6D4',
        edges = { color = '#8B1A1A', size = 0.06 },
        text = { items = { 'EVIDENCE', 'DO NOT DISTURB' }, color = '#8B1A1A', font = 'bebas', size = 0.62, spacing = 0.08, separator = 'diamond' },
    },
    {
        id = 'crime_scene_blue', label = 'Crime Scene (Blue)', category = 'crime', region = 'US', base = BLUE,
        text = { items = { 'CRIME SCENE', 'DO NOT CROSS' }, color = WHITE, font = 'oswald', size = 0.62, spacing = 0.05, separator = 'star' },
    },
    {
        id = 'crime_scene_white', label = 'Crime Scene (White)', category = 'crime', region = 'US', base = WHITE,
        edges = { color = RED, size = 0.08 },
        text = { items = { 'CRIME SCENE', 'DO NOT CROSS' }, color = BLACK, font = 'barlow', size = 0.58, spacing = 0.06, separator = 'dot', separatorColor = RED },
    },
    {
        id = 'crime_scene_bilingual', label = 'Crime Scene (EN / ES)', category = 'crime', region = 'US', base = YELLOW,
        text = { items = { 'CRIME SCENE', 'ESCENA DEL CRIMEN' }, color = BLACK, font = 'oswald', size = 0.58, spacing = 0.03, separator = 'bar' },
    },
    {
        id = 'coroner', label = 'Coroner', category = 'crime', region = 'US', base = '#1A1A1A',
        edges = { color = WHITE, size = 0.05 },
        text = { items = { 'CORONER', 'DO NOT CROSS' }, color = WHITE, font = 'bebas', size = 0.62, spacing = 0.1, separator = 'bar' },
    },
    {
        id = 'homicide', label = 'Homicide', category = 'crime', region = 'US', base = '#7A0E12',
        edges = { color = BLACK, size = 0.07 },
        text = { items = { 'HOMICIDE', 'INVESTIGATION', 'DO NOT CROSS' }, color = '#F4E9D8', font = 'oswald', size = 0.56, spacing = 0.05, separator = 'diamond' },
    },

    -- Fire ---------------------------------------------------------------------------------------
    {
        id = 'fire_line', label = 'Fire Line', category = 'fire', region = 'US', base = RED,
        text = { items = { 'FIRE LINE', 'DO NOT CROSS' }, color = WHITE, font = 'oswald', size = 0.64, spacing = 0.04 },
    },
    {
        id = 'fire_line_yellow', label = 'Fire Line (Yellow)', category = 'fire', region = 'US', base = YELLOW,
        edges = { color = RED, size = 0.08 },
        text = { items = { 'FIRE LINE', 'DO NOT CROSS' }, color = RED, font = 'oswald', size = 0.58, spacing = 0.05, separator = 'bar' },
    },
    {
        id = 'lsfd_line', label = 'LSFD', category = 'fire', region = 'LS', base = '#9E1B1B',
        edges = { color = WHITE, size = 0.07 },
        text = { items = { 'LSFD', 'FIRE DEPARTMENT', 'DO NOT CROSS' }, color = WHITE, font = 'bebas', size = 0.6, spacing = 0.07, separator = 'cross' },
    },
    {
        id = 'fire_danger', label = 'Fire Danger Zone', category = 'fire', region = 'US', base = WHITE,
        pattern = { type = 'diagonal', color = RED, size = 0.55, angle = 45 },
        text = { items = { 'DANGER', 'FIRE ZONE' }, color = RED, font = 'anton', size = 0.52, spacing = 0.06, plate = { color = WHITE, padding = 0.3 } },
    },
    {
        id = 'fire_scene', label = 'Fire Scene', category = 'fire', region = 'US', base = BLACK,
        edges = { color = RED, size = 0.09 },
        text = { items = { 'FIRE SCENE', 'DO NOT ENTER' }, color = WHITE, font = 'anton', size = 0.56, spacing = 0.06, separator = 'dot', separatorColor = RED },
    },
    {
        id = 'arson', label = 'Arson Investigation', category = 'fire', region = 'US', base = '#2B2B2B',
        edges = { color = ORANGE, size = 0.07 },
        text = { items = { 'ARSON', 'INVESTIGATION', 'DO NOT CROSS' }, color = ORANGE, font = 'oswald', size = 0.56, spacing = 0.05, separator = 'slash' },
    },
    {
        id = 'fire_lane', label = 'Fire Lane', category = 'fire', region = 'US', base = RED,
        edges = { color = WHITE, size = 0.06 },
        text = { items = { 'FIRE LANE', 'NO PARKING' }, color = WHITE, font = 'barlow', size = 0.6, spacing = 0.06, separator = 'bar' },
    },
    {
        id = 'wildfire', label = 'Wildfire', category = 'fire', region = 'US', base = '#F2A900',
        edges = { color = '#B22222', size = 0.07 },
        text = { items = { 'WILDFIRE', 'AREA CLOSED' }, color = '#3A1F04', font = 'archivo', size = 0.46, spacing = 0.06, separator = 'chevron', separatorColor = '#B22222' },
    },

    -- EMS ----------------------------------------------------------------------------------------
    {
        id = 'ems_line', label = 'EMS', category = 'ems', region = 'US', base = '#1565C0',
        text = { items = { 'EMS', 'MEDICAL EMERGENCY', 'DO NOT CROSS' }, color = WHITE, font = 'barlow', size = 0.56, spacing = 0.05, separator = 'cross' },
    },
    {
        id = 'medical_zone', label = 'Medical Zone', category = 'ems', region = 'US', base = WHITE,
        edges = { color = GREEN, size = 0.09 },
        text = { items = { 'MEDICAL ZONE', 'KEEP CLEAR' }, color = GREEN, font = 'barlow', size = 0.56, spacing = 0.06, separator = 'cross' },
    },
    {
        id = 'pillbox_medical', label = 'Pillbox Medical', category = 'ems', region = 'LS', base = WHITE,
        edges = { color = RED, size = 0.07 },
        text = { items = { 'PILLBOX HILL MEDICAL', 'KEEP CLEAR' }, color = '#1565C0', font = 'barlow', size = 0.54, spacing = 0.05, separator = 'cross', separatorColor = RED },
    },
    {
        id = 'triage_immediate', label = 'Triage - Immediate', category = 'ems', base = RED,
        text = { items = { 'TRIAGE', 'IMMEDIATE' }, color = WHITE, font = 'oswald', size = 0.6, spacing = 0.06, separator = 'cross' },
    },
    {
        id = 'triage_delayed', label = 'Triage - Delayed', category = 'ems', base = YELLOW,
        text = { items = { 'TRIAGE', 'DELAYED' }, color = BLACK, font = 'oswald', size = 0.6, spacing = 0.06, separator = 'cross' },
    },
    {
        id = 'triage_minor', label = 'Triage - Minor', category = 'ems', base = GREEN,
        text = { items = { 'TRIAGE', 'MINOR' }, color = WHITE, font = 'oswald', size = 0.6, spacing = 0.06, separator = 'cross' },
    },
    {
        id = 'triage_expectant', label = 'Triage - Expectant', category = 'ems', base = BLACK,
        edges = { color = WHITE, size = 0.05 },
        text = { items = { 'TRIAGE', 'EXPECTANT' }, color = WHITE, font = 'oswald', size = 0.6, spacing = 0.06, separator = 'cross' },
    },

    -- Hazard -------------------------------------------------------------------------------------
    {
        id = 'caution', label = 'Caution', category = 'hazard', base = YELLOW,
        text = { items = { 'CAUTION' }, color = BLACK, font = 'anton', size = 0.62, spacing = 0.08, repeats = 4 },
    },
    {
        id = 'caution_do_not_enter', label = 'Caution - Do Not Enter', category = 'hazard', base = YELLOW,
        edges = { color = BLACK, size = 0.08 },
        text = { items = { 'CAUTION', 'DO NOT ENTER' }, color = BLACK, font = 'barlow', size = 0.58, spacing = 0.05, separator = 'chevron' },
    },
    {
        id = 'danger', label = 'Danger', category = 'hazard', base = RED,
        text = { items = { 'DANGER' }, color = WHITE, font = 'anton', size = 0.62, spacing = 0.08, repeats = 4 },
    },
    {
        id = 'danger_do_not_enter', label = 'Danger - Do Not Enter', category = 'hazard', base = WHITE,
        edges = { color = BLACK, size = 0.07 },
        text = { items = { 'DANGER', 'DO NOT ENTER' }, color = RED, font = 'oswald', size = 0.6, spacing = 0.05, separator = 'dot', separatorColor = BLACK },
    },
    {
        id = 'hazmat', label = 'Hazardous Materials', category = 'hazard', base = YELLOW,
        pattern = { type = 'diagonal', color = BLACK, size = 0.5, angle = 45 },
        text = { items = { 'HAZARDOUS MATERIALS', 'KEEP OUT' }, color = BLACK, font = 'stencil', size = 0.5, spacing = 0.05, plate = { color = YELLOW, padding = 0.28 } },
    },
    {
        id = 'biohazard', label = 'Biohazard', category = 'hazard', base = ORANGE,
        edges = { color = BLACK, size = 0.07 },
        text = { items = { 'BIOHAZARD', 'DO NOT ENTER' }, color = BLACK, font = 'oswald', size = 0.6, spacing = 0.05, separator = 'diamond' },
    },
    {
        id = 'radiation', label = 'Radiation', category = 'hazard', base = YELLOW,
        edges = { color = '#B5179E', size = 0.08 },
        text = { items = { 'CAUTION', 'RADIATION AREA' }, color = '#B5179E', font = 'oswald', size = 0.58, spacing = 0.05, separator = 'dot' },
    },
    {
        id = 'high_voltage', label = 'High Voltage', category = 'hazard', base = BLACK,
        edges = { color = YELLOW, size = 0.07 },
        text = { items = { 'DANGER', 'HIGH VOLTAGE' }, color = YELLOW, font = 'archivo', size = 0.46, spacing = 0.05, separator = 'chevron' },
    },
    {
        id = 'bomb_squad', label = 'Bomb Squad', category = 'hazard', base = ORANGE,
        pattern = { type = 'chevron', color = BLACK, size = 0.7 },
        text = { items = { 'BOMB SQUAD', 'KEEP BACK' }, color = BLACK, font = 'stencil', size = 0.5, spacing = 0.06, plate = { color = ORANGE, padding = 0.3 } },
    },
    {
        id = 'warning', label = 'Warning', category = 'hazard', base = ORANGE,
        text = { items = { 'WARNING' }, color = BLACK, font = 'anton', size = 0.62, spacing = 0.08, repeats = 4 },
    },
    {
        id = 'asbestos', label = 'Asbestos', category = 'hazard', base = WHITE,
        edges = { color = RED, size = 0.09 },
        text = { items = { 'DANGER', 'ASBESTOS', 'DO NOT ENTER' }, color = BLACK, font = 'oswald', size = 0.56, spacing = 0.05, separator = 'diamond', separatorColor = RED },
    },
    {
        id = 'gas_leak', label = 'Gas Leak', category = 'hazard', base = YELLOW,
        edges = { color = RED, size = 0.07 },
        text = { items = { 'GAS LEAK', 'NO SMOKING', 'NO FLAMES' }, color = BLACK, font = 'barlow', size = 0.6, spacing = 0.05, separator = 'diamond', separatorColor = RED },
    },
    {
        id = 'chemical_spill', label = 'Chemical Spill', category = 'hazard', base = WHITE,
        pattern = { type = 'diagonal', color = ORANGE, size = 0.5, angle = -45 },
        text = { items = { 'CHEMICAL SPILL', 'KEEP AWAY' }, color = BLACK, font = 'stencil', size = 0.5, spacing = 0.05, plate = { color = WHITE, padding = 0.28 } },
    },
    {
        id = 'humane_labs', label = 'Humane Labs Quarantine', category = 'hazard', region = 'LS', base = '#0F3B33',
        edges = { color = '#7BE0C3', size = 0.06 },
        text = { items = { 'HUMANE LABS', 'QUARANTINE', 'NO ENTRY' }, color = '#E6FFF7', font = 'russo', size = 0.44, spacing = 0.06, separator = 'cross', separatorColor = '#7BE0C3' },
    },
    {
        id = 'fumigation', label = 'Fumigation (Bugstars)', category = 'hazard', region = 'LS', base = '#2E7D32',
        edges = { color = YELLOW, size = 0.07 },
        text = { items = { 'BUGSTARS', 'FUMIGATION', 'DO NOT ENTER' }, color = YELLOW, font = 'oswald', size = 0.56, spacing = 0.05, separator = 'dot' },
    },

    -- Utility ------------------------------------------------------------------------------------
    {
        id = 'construction', label = 'Construction Zone', category = 'utility', base = ORANGE,
        text = { items = { 'CONSTRUCTION ZONE', 'KEEP OUT' }, color = BLACK, font = 'barlow', size = 0.58, spacing = 0.04, separator = 'bar' },
    },
    {
        id = 'road_closed', label = 'Road Closed', category = 'utility', base = WHITE,
        pattern = { type = 'diagonal', color = ORANGE, size = 0.6, angle = -45 },
        text = { items = { 'ROAD CLOSED' }, color = BLACK, font = 'oswald', size = 0.56, spacing = 0.06, plate = { color = WHITE, padding = 0.3 }, repeats = 2 },
    },
    {
        id = 'restricted_area', label = 'Restricted Area', category = 'utility', base = '#1B1B1F',
        edges = { color = WHITE, size = 0.06 },
        text = { items = { 'RESTRICTED AREA', 'AUTHORIZED PERSONNEL ONLY' }, color = WHITE, font = 'roboto', size = 0.48, spacing = 0.05, separator = 'bar' },
    },
    {
        id = 'private_property', label = 'Private Property', category = 'utility', base = '#263238',
        text = { items = { 'PRIVATE PROPERTY', 'NO TRESPASSING' }, color = WHITE, font = 'oswald', size = 0.56, spacing = 0.05, separator = 'bar', separatorColor = ORANGE },
    },
    {
        id = 'lsdwp_work', label = 'LS Water & Power', category = 'utility', region = 'LS', base = '#F2F2F2',
        edges = { color = '#1E5AA8', size = 0.08 },
        text = { items = { 'LSDWP', 'WORK ZONE', 'KEEP OUT' }, color = '#1E5AA8', font = 'archivo', size = 0.42, spacing = 0.06, separator = 'bar' },
    },
    {
        id = 'gruppe_sechs', label = 'Gruppe Sechs Security', category = 'utility', region = 'LS', base = '#2F3437',
        edges = { color = '#7AC943', size = 0.06 },
        text = { items = { 'GRUPPE SECHS', 'SECURITY CORDON' }, color = WHITE, font = 'barlow', size = 0.54, spacing = 0.06, separator = 'diamond', separatorColor = '#7AC943' },
    },
    {
        id = 'closed_set', label = 'Closed Set', category = 'utility', base = '#111111',
        edges = { color = '#E4B83A', size = 0.05 },
        text = { items = { 'CLOSED SET', 'FILMING IN PROGRESS' }, color = WHITE, font = 'staatliches', size = 0.56, spacing = 0.06, separator = 'star', separatorColor = '#E4B83A' },
    },
    {
        id = 'vip_area', label = 'VIP Area', category = 'utility', base = BLACK,
        edges = { color = '#C9A227', size = 0.06 },
        text = { items = { 'VIP AREA', 'STAFF ONLY' }, color = '#C9A227', font = 'bebas', size = 0.6, spacing = 0.12, separator = 'star' },
    },
    {
        id = 'race_course', label = 'Race Course', category = 'utility', base = WHITE,
        pattern = { type = 'checker', color = BLACK, size = 0.5 },
        text = { items = { 'RACE COURSE', 'SPECTATORS KEEP BACK' }, color = BLACK, font = 'russo', size = 0.44, spacing = 0.05, plate = { color = WHITE, padding = 0.3 } },
    },

    -- Plain --------------------------------------------------------------------------------------
    {
        id = 'barrier_red_white', label = 'Barrier (Red / White)', category = 'plain', base = WHITE,
        pattern = { type = 'diagonal', color = RED, size = 0.6, angle = 45 },
    },
    {
        id = 'barrier_yellow_black', label = 'Barrier (Yellow / Black)', category = 'plain', base = YELLOW,
        pattern = { type = 'diagonal', color = BLACK, size = 0.6, angle = 45 },
    },
    {
        id = 'barrier_blue_white', label = 'Barrier (Blue / White)', category = 'plain', base = WHITE,
        pattern = { type = 'diagonal', color = BLUE, size = 0.6, angle = 45 },
    },
    {
        id = 'barrier_blocks_red', label = 'Barrier Blocks (Red / White)', category = 'plain', base = WHITE,
        pattern = { type = 'blocks', color = RED, size = 2.2 },
    },
    {
        id = 'barrier_checker_blue', label = 'Checkered (Blue / White)', category = 'plain', base = WHITE,
        pattern = { type = 'checker', color = BLUE, size = 0.5 },
    },
    {
        id = 'barrier_orange_white', label = 'Barrier (Orange / White)', category = 'plain', base = WHITE,
        pattern = { type = 'diagonal', color = ORANGE, size = 0.6, angle = 45 },
    },
    {
        id = 'barrier_green_white', label = 'Barrier (Green / White)', category = 'plain', base = WHITE,
        pattern = { type = 'diagonal', color = GREEN, size = 0.6, angle = 45 },
    },
    {
        id = 'barrier_blocks_yellow', label = 'Barrier Blocks (Yellow / Black)', category = 'plain', base = YELLOW,
        pattern = { type = 'blocks', color = BLACK, size = 2.2 },
    },
    {
        id = 'barrier_chevron_red', label = 'Chevrons (Red / White)', category = 'plain', base = WHITE,
        pattern = { type = 'chevron', color = RED, size = 0.7 },
    },
    {
        id = 'barrier_checker_black', label = 'Checkered (Black / White)', category = 'plain', base = WHITE,
        pattern = { type = 'checker', color = BLACK, size = 0.5 },
    },

    -- International ------------------------------------------------------------------------------
    {
        id = 'gb_police', label = 'Police Line (UK)', category = 'international', region = 'GB', base = WHITE,
        edges = { color = '#1A3A8F', size = 0.12 },
        text = { items = { 'POLICE LINE', 'DO NOT CROSS' }, color = '#1A3A8F', font = 'roboto', size = 0.5, spacing = 0.06 },
    },
    {
        id = 'de_polizei', label = 'Polizei (DE)', category = 'international', region = 'DE', base = WHITE,
        pattern = { type = 'diagonal', color = '#0B4EA2', size = 0.6, angle = 45 },
        text = { items = { 'POLIZEI', 'ABSPERRUNG' }, color = '#0B4EA2', font = 'roboto', size = 0.54, spacing = 0.06, plate = { color = WHITE, padding = 0.28 } },
    },
    {
        id = 'nl_politie', label = 'Politie (NL)', category = 'international', region = 'NL', base = WHITE,
        pattern = { type = 'blocks', color = RED, size = 2.0 },
        text = { items = { 'POLITIE', 'NIET BETREDEN' }, color = '#13216A', font = 'barlow', size = 0.54, spacing = 0.06, plate = { color = WHITE, padding = 0.25 } },
    },
    {
        id = 'fr_police', label = 'Police (FR)', category = 'international', region = 'FR', base = '#002395',
        edges = { color = '#ED2939', size = 0.08 },
        text = { items = { 'POLICE', 'ZONE INTERDITE' }, color = WHITE, font = 'barlow', size = 0.56, spacing = 0.06, separator = 'bar' },
    },
    {
        id = 'es_policia', label = 'Policía (ES)', category = 'international', region = 'ES', base = WHITE,
        pattern = { type = 'blocks', color = BLUE, size = 2.0 },
        text = { items = { 'POLICÍA', 'NO PASAR' }, color = BLUE, font = 'oswald', size = 0.54, spacing = 0.05, plate = { color = WHITE, padding = 0.25 } },
    },
    {
        id = 'it_polizia', label = 'Polizia (IT)', category = 'international', region = 'IT', base = WHITE,
        pattern = { type = 'diagonal', color = RED, size = 0.6, angle = -45 },
        text = { items = { 'POLIZIA', 'NON OLTREPASSARE' }, color = '#0B2A6B', font = 'oswald', size = 0.52, spacing = 0.05, plate = { color = WHITE, padding = 0.25 } },
    },
    {
        id = 'br_policia', label = 'Polícia (BR / PT)', category = 'international', region = 'BR', base = YELLOW,
        text = { items = { 'POLÍCIA', 'NÃO ULTRAPASSE' }, color = BLACK, font = 'oswald', size = 0.6, spacing = 0.05, separator = 'dot' },
    },
    {
        id = 'se_polis', label = 'Polis (SE)', category = 'international', region = 'SE', base = WHITE,
        pattern = { type = 'diagonal', color = '#0A3B8C', size = 0.6, angle = 45 },
        text = { items = { 'POLIS', 'AVSPÄRRAT' }, color = '#0A3B8C', font = 'barlow', size = 0.56, spacing = 0.07, plate = { color = WHITE, padding = 0.3 } },
    },
    {
        id = 'pl_policja', label = 'Policja (PL)', category = 'international', region = 'PL', base = WHITE,
        pattern = { type = 'diagonal', color = '#DC143C', size = 0.6, angle = 45 },
        text = { items = { 'POLICJA', 'ZAKAZ WSTĘPU' }, color = '#0D2B6B', font = 'roboto', size = 0.52, spacing = 0.06, plate = { color = WHITE, padding = 0.28 } },
    },
    {
        id = 'au_police', label = 'Police Line (AU)', category = 'international', region = 'AU', base = WHITE,
        pattern = { type = 'checker', color = '#0A2A66', size = 0.5 },
        text = { items = { 'POLICE LINE', 'DO NOT CROSS' }, color = '#0A2A66', font = 'roboto', size = 0.5, spacing = 0.06, plate = { color = WHITE, padding = 0.28 } },
    },
    {
        id = 'ca_police', label = 'Police Line (CA)', category = 'international', region = 'CA', base = YELLOW,
        text = { items = { 'POLICE LINE', 'LIGNE DE POLICE' }, color = BLACK, font = 'oswald', size = 0.6, spacing = 0.04, separator = 'dot' },
    },
    {
        id = 'ie_garda', label = 'Garda (IE)', category = 'international', region = 'IE', base = WHITE,
        pattern = { type = 'blocks', color = '#1B3F8B', size = 2.0 },
        text = { items = { 'GARDA', 'DO NOT CROSS', 'NÁ TRASNAIGH' }, color = '#1B3F8B', font = 'roboto', size = 0.5, spacing = 0.05, plate = { color = WHITE, padding = 0.25 } },
    },
    {
        id = 'at_polizei', label = 'Polizei (AT)', category = 'international', region = 'AT', base = WHITE,
        pattern = { type = 'diagonal', color = '#C8102E', size = 0.6, angle = -45 },
        text = { items = { 'POLIZEI', 'ABSPERRUNG' }, color = BLACK, font = 'roboto', size = 0.54, spacing = 0.06, plate = { color = WHITE, padding = 0.28 } },
    },
    {
        id = 'ch_polizei', label = 'Polizei / Police (CH)', category = 'international', region = 'CH', base = WHITE,
        edges = { color = '#D52B1E', size = 0.12 },
        text = { items = { 'POLIZEI', 'POLICE', 'POLIZIA' }, color = BLACK, font = 'roboto', size = 0.5, spacing = 0.08, separator = 'cross', separatorColor = '#D52B1E' },
    },
    {
        id = 'no_politi', label = 'Politi (NO)', category = 'international', region = 'NO', base = WHITE,
        pattern = { type = 'diagonal', color = '#BA0C2F', size = 0.6, angle = 45 },
        text = { items = { 'POLITI', 'SPERRET' }, color = '#00205B', font = 'barlow', size = 0.56, spacing = 0.07, plate = { color = WHITE, padding = 0.3 } },
    },
    {
        id = 'fi_poliisi', label = 'Poliisi (FI)', category = 'international', region = 'FI', base = '#0A3D8F',
        edges = { color = WHITE, size = 0.07 },
        text = { items = { 'POLIISI', 'POLIS' }, color = WHITE, font = 'barlow', size = 0.56, spacing = 0.08, separator = 'bar' },
    },
    {
        id = 'tr_polis', label = 'Polis (TR)', category = 'international', region = 'TR', base = WHITE,
        edges = { color = '#E30A17', size = 0.1 },
        text = { items = { 'POLİS ŞERİDİ', 'GEÇMEYİNİZ' }, color = '#E30A17', font = 'roboto', size = 0.52, spacing = 0.05, separator = 'dot' },
    },
}
