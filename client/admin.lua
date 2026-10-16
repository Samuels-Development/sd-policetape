---The admin menu's client half. The server sends the snapshot (server/admin.lua); this adds what
---only a client can know (the street each tape is on, how far away it is) and does the two things
---that are this player's own business: going to a tape, and a waypoint to it. Every change goes
---to the server, which checks the caller is an admin again.
local locale = require 'bridge.shared.locale'
local notify = require 'bridge.client.notify'
local nui = require 'client.nui'

local admin = {}

local streets = {} ---@type table<integer, string> per tape id: the street never changes
local rows = {} ---@type table<integer, table> the last snapshot's tapes, by id

local function street(x, y, z)
    local s1 = GetStreetNameAtCoord(x, y, z)
    local name = GetStreetNameFromHashKey(s1)
    local zone = GetLabelText(GetNameOfZone(x, y, z))
    if zone == 'NULL' then zone = '' end
    if name == '' then return zone end
    if zone ~= '' then return ('%s, %s'):format(name, zone) end
    return name
end

---Adds the street and distance to every tape row, and normalises the lists (an empty Lua table
---can arrive as {} instead of []).
local function dress(snap)
    if type(snap) ~= 'table' then return nil end
    local me = GetEntityCoords(PlayerPedId())
    rows = {}
    local tapes = type(snap.tapes) == 'table' and snap.tapes or {}
    for _, row in ipairs(tapes) do
        local mx, my, mz = (row.a.x + row.b.x) / 2, (row.a.y + row.b.y) / 2, (row.a.z + row.b.z) / 2
        row.distance = math.floor(#(me - vector3(mx, my, mz)) + 0.5)
        streets[row.id] = streets[row.id] or street(mx, my, mz)
        row.street = streets[row.id]
        rows[row.id] = row
    end
    snap.tapes = tapes
    return snap
end

local function fetch()
    return dress(lib.callback.await('sd-policetape:server:admin:snapshot', false))
end

function admin.open()
    if nui.busy() then return end
    local snap = fetch()
    if not snap then
        notify.show({ title = locale.t('notify.title'), description = locale.t('notify.no_permission'), type = 'error' })
        return
    end
    nui.openAdmin(snap)
end

RegisterNetEvent('sd-policetape:client:openAdmin', admin.open)

RegisterNUICallback('adminRefresh', function(_, cb)
    cb(nui.adminIsOpen() and fetch() or false)
end)

RegisterNUICallback('adminAct', function(data, cb)
    if type(data) ~= 'table' or type(data.verb) ~= 'string' then return cb({ ok = false }) end
    local res = lib.callback.await('sd-policetape:server:admin:act', false, data.verb, data.data)
    if type(res) ~= 'table' then return cb({ ok = false }) end
    res.snapshot = dress(res.snapshot)
    cb(res)
end)

RegisterNUICallback('adminClose', function(_, cb)
    cb(1)
    nui.closeAdmin()
end)

---Beside the middle of a tape, on the ground, out of the way of the tape itself.
local function besideTape(row)
    local a, b = vector3(row.a.x, row.a.y, row.a.z), vector3(row.b.x, row.b.y, row.b.z)
    local mid = (a + b) / 2
    local d = b - a
    local side = #d > 0.01 and vector3(-d.y, d.x, 0.0) / math.max(0.01, math.sqrt(d.x * d.x + d.y * d.y)) or vector3(1.0, 0.0, 0.0)
    return mid + side * 1.5, mid
end

RegisterNUICallback('adminTeleport', function(data, cb)
    cb(1)
    local row = type(data) == 'table' and rows[tonumber(data.id) or -1]
    if not row then return end
    local at, mid = besideTape(row)
    local ped = PlayerPedId()
    nui.closeAdmin()
    CreateThread(function()
        DoScreenFadeOut(200)
        Wait(220)
        RequestCollisionAtCoord(at.x, at.y, at.z)
        SetEntityCoords(ped, at.x, at.y, at.z, false, false, false, false)
        local deadline = GetGameTimer() + 2000
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(0) end
        local found, ground = GetGroundZFor_3dCoord(at.x, at.y, at.z + 2.0, false)
        if found then SetEntityCoords(ped, at.x, at.y, ground, false, false, false, false) end
        SetEntityHeading(ped, GetHeadingFromVector_2d(mid.x - at.x, mid.y - at.y))
        DoScreenFadeIn(250)
    end)
end)

RegisterNUICallback('adminWaypoint', function(data, cb)
    cb(1)
    local row = type(data) == 'table' and rows[tonumber(data.id) or -1]
    if not row then return end
    SetNewWaypoint((row.a.x + row.b.x) / 2, (row.a.y + row.b.y) / 2)
end)

return admin
