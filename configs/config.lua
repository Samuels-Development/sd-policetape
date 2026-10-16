-- sd-policetape configuration. Loaded on both sides with `require 'configs.config'`.
--
-- Who may do what is decided on the server, in configs/server/permissions.lua (which never ships
-- to clients). This file only says which jobs and ACEs that file looks at by default.
return {
    Locale = 'en', -- en, nl, de, fr, es (locales/<Locale>.json); anything missing falls back to English
    Debug = false, -- cyan [sd-policetape] diagnostic prints, client and server
    DebugPrints = false, -- the bridge's own (very verbose) prints

    Commands = {
        Place = 'tape', -- start placing tape (also: use the item)
        Styles = 'tapestyles', -- open the style picker to choose the style you place with
        Studio = 'tapestudio', -- the Tape Studio, for making new styles
        Clear = 'cleartape', -- /cleartape [radius | all] (admins)
        Admin = 'tapeadmin', -- the admin menu: every tape on the server, the switches below, and which styles and holders police get (admins)
    },

    -- A roll of tape as an inventory item. Add it to your inventory's items (see README).
    Item = {
        Enabled = true, -- false: anyone allowed to use tape needs no item
        Name = 'police_tape',
        Consume = false, -- take one roll per stretch of tape placed
        Refund = true, -- with Consume: give the roll back to whoever takes their own tape down
    },

    -- Default access, read by configs/server/permissions.lua. Jobs are name = minimum grade.
    Access = {
        Everyone = false, -- true: every player may place, restyle and take down tape
        Jobs = {
            police = 0, lspd = 0, bcso = 0, sheriff = 0, sasp = 0, sahp = 0, fib = 0,
            ambulance = 0, ems = 0, fire = 0, lsfd = 0, doj = 0,
        },
        Ace = 'sd-policetape.use', -- also grants access, whatever the job
        OthersTapes = true, -- false: players take down only their own tape (admins any)
        StudioJobs = {}, -- e.g. { police = 4 }: grades that may make styles in the Tape Studio
        StudioAce = 'sd-policetape.studio', -- txAdmin's `group.admin` has every command ace, not this one: see README
        AdminAce = 'sd-policetape.admin', -- /cleartape, and take down anyone's tape
    },

    Placement = {
        Reach = 10.0, -- how far you can aim a tape end, metres
        MaxLength = 15.0, -- longest single stretch, metres
        MinLength = 0.6,
        Chain = true, -- after tying off, keep going from that point until you press Done
        Posts = true, -- aiming at open ground stands a holder there to tie to (a post or a cone)
        Holder = 'post', -- which one, until a player picks another with H / d-pad right (configs/holders.lua)
        PostSnap = 0.45, -- aiming this close to an existing holder ties to it instead of adding one
        GroundSlope = 0.75, -- a surface whose normal points up more than this counts as ground
        RollModel = 'sd_tape_roll', -- the roll in your hand while placing
        RollBone = 57005, -- SKEL_R_Hand
        RollOffset = vec3(0.11, 0.02, -0.03),
        RollRotation = vec3(-70.0, 0.0, 15.0),
        OnFoot = true, -- must be on foot to place
    },

    -- What the tape is like. Changing Width or Repeat changes how big the print is.
    Tape = {
        Width = 0.075, -- metres (3 inch tape)
        Repeat = 1.2, -- metres of tape per repeat of the print; keep it 16 x Width
        SegmentLength = 0.25, -- physics resolution
        SagBase = 0.015, -- how far the middle hangs below a straight line:
        SagPerMeter = 0.018, --   SagBase + SagPerMeter * length (metres)
    },

    Physics = {
        Enabled = true, -- false: tape never moves (no pushing, no tearing; wind still sways it)
        SimDistance = 40.0, -- tape further than this from you never runs physics
        WakeDistance = 1.5, -- a ped or vehicle this close wakes a tape up
        Peds = true, -- people push tape
        Vehicles = true, -- vehicles push tape
        Resistance = true, -- pushing into tape slows you down, the more the further it gives
        PedGrip = 0.7, -- 0..1: how much tape grips a body instead of sliding round it
        VehicleGrip = 0.85, -- the same for vehicles (low: tape rides up over the bonnet and roof)
        -- Solver tuning (see client/tape/sim.lua and tests/sim_harness.lua). Leave alone unless
        -- you know what you want: these were tuned by measuring, not guessed.
        Iterations = 8,
        Damping = 0.965,
        RestSpring = 22.0,
        Stiffness = 0.85,
        Friction = 0.55,
    },

    Wind = {
        Enabled = true, -- tape sways with the game's wind (GetWindSpeed / GetWindDirection)
        Strength = 1.0,
        Flutter = 1.0, -- how much the ribbon twists in gusts
    },

    -- Tape gives a little, then snaps for everybody. Every tear is checked by the server.
    Tear = {
        Enabled = true, -- false: tape never breaks. Pushed past its limit it slips off whatever is pushing it and springs back into line
        SpeedKmh = 30.0, -- a vehicle at least this fast tears tape on contact
        VehiclePush = 1.8, -- metres a slower vehicle can drag tape before it snaps (or slips off)
        Stretch = 1.4, -- any tape stretched this far (1.4 = 40% longer) snaps (or slips off)
        People = true, -- people pushing through tape snap it (with Enabled off: it springs back); false: it holds them at PeoplePush
        PeoplePush = 1.0, -- metres a person can push tape out before it snaps (or slips off, or stops them)
        RemoveAfter = 300, -- seconds before torn tape is cleared away (0: it stays until taken down)
    },

    -- The posts and cones tape is tied to. Knocked over, a holder goes down for everybody and the
    -- tape goes down with it (slack, or torn if it was already). Every knock is checked by the server.
    Holders = {
        Knock = true, -- false: holders cannot be knocked over (and vehicles still pass through them)
        Vehicles = true, -- a vehicle driving into one knocks it over and sends it along the road
        VehicleSpeedKmh = 3.0, -- slower than this, a vehicle only nudges against it
        Kick = true, -- a kick or punch right at one knocks it over
        Run = true, -- running into one knocks it over (walking only bumps into it)
        StandUp = true, -- anyone allowed to use tape can stand a knocked-over holder back up (hold Keys.Remove)
    },

    Render = {
        DrawDistance = 90.0, -- tape is drawn this far away
        StreamDistance = 130.0, -- tape is built (and posts spawned) this far away
        NightBrightness = 0.42, -- tape is drawn by the script, so it is dimmed at night by hand
        InteriorBrightness = 0.8,
        Shading = true, -- light the ribbon by which way it faces
        MirrorBack = true, -- the print reads correctly from both sides
    },

    Lifetime = 0, -- minutes before tape comes down by itself (0: never)
    Persist = true, -- tape survives restarts (data/tapes.json)

    Limits = {
        PerPlayer = 40, -- tapes one player can have out at once
        Total = 800, -- tapes on the whole server
        PlacePerMinute = 40, -- placements per player per minute
        CustomStyles = 100, -- styles the Tape Studio can hold
    },

    -- Defaults for the rebindable keys (Settings > Key Bindings > FiveM). Placing uses the game's
    -- own attack / aim / weapon-wheel controls, so it works on a controller as it is.
    Keys = {
        Remove = 'E', -- hold while looking at tape to take it down (not Left Alt: ox_target / qb-target own it)
        Restyle = 'G', -- while looking at tape: choose another style
        HoldTime = 900, -- ms to hold Remove
        PadRemove = 'LDOWN_INDEX', -- controller: d-pad down
        PadRestyle = 'LLEFT_INDEX', -- controller: d-pad left
    },
}
