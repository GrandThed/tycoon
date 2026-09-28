--!strict
-- Ability visuals for the Proving Grounds (P3, docs/INTERFACES.md "P3 contracts": ruling 6, the
-- ability table and CombatFxCast). There is no sound, so a cast must read from its visuals alone,
-- for the caster and for everyone watching (COMBAT_DESIGN pillar 2: what you see is what you hit).
--
-- Division of labour. Damage never comes from here: every ability hit is a CombatFxStrike that
-- FeedbackController draws (exact shape, numbers, reactions), and Feedback also flies every ability
-- projectile (volley arrows, the cluster shell) and draws chain lightning from `links`. It skips
-- its generic flash on `tick` strikes because this module draws the lasting area. So this module
-- adds only what lasts, or what one strike cannot show:
--   * the whole-duration area of a lasting ability at its exact server size, no pad (Whirlwind
--     ring = range, zone circles = radius, the Overload Sweep beam and sector = range);
--   * the build-up before a delayed hit (the Earthquake front, the Leap Smash landing marker, the
--     Overcharged Shot charge, the cluster bomblets blinking over their blast radius);
--   * caster flourishes (bow flash, muzzle blasts, Mag Dump heat, dash afterimages, trails).
--
-- Timing. A cast and its strikes reach this client with the same lag, so visuals run on the
-- receipt clock and land together with the damage the player sees. Only a cast later than
-- CATCH_UP_GRACE past its server `startsAt` (a stall, a join mid-cast) skips ahead by the excess, so
-- a zone never outlives the server's. The ability def is frozen at receipt: a slider moved mid-cast
-- changes the next cast, as it does on the server. Tick strikes pulse their zone, so the damage
-- rhythm shows too.
--
-- Budget. Everything is pooled (parts, wedges, beams, emitters, trails, lights) under one Workspace
-- folder, and per-frame moves go through one Workspace:BulkMoveTo. The crowd is never iterated.
-- Theme.lowEndDevice halves every particle rate and burst and drops the extras (fills, streaks,
-- debris, lights, reticle notches, some blades and afterimages). The areas always draw, because
-- they are information. Theme.reducedMotion is deliberately unused: it is true on every touch
-- device (living-city ruling), and phones are where these reads matter most.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))

type Def = Types.RangeAbilityDef

-- A validated CombatFxCast (never a cancel).
type Cast = {
	userId: number,
	weapon: string,
	ability: string,
	origin: Vector3,
	direction: Vector3,
	target: Vector3?,
	startsAt: number,
	seq: number,
}

-- The fields of an ability CombatFxStrike this module reacts to.
type AbilityStrike = {
	userId: number,
	ability: string,
	shape: string,
	origin: Vector3,
	direction: Vector3,
	size: number,
	endPoint: Vector3?,
	tick: boolean,
}

type BeamHandle = { beam: Beam, a0: Attachment, a1: Attachment, shown: number }
-- readyAt: a released emitter is reused only once its last particle has died, because a new
-- Color would re-tint particles still in the air.
type EmitterHandle = {
	attachment: Attachment,
	emitter: ParticleEmitter,
	readyAt: number,
	lifeMax: number,
}
type TrailHandle = { trail: Trail, a0: Attachment, a1: Attachment }
type LightHandle = { attachment: Attachment, light: PointLight }

-- Everything one visual took from the pools, given back in one go when it ends.
type Kit = {
	parts: { BasePart },
	beams: { BeamHandle },
	emitters: { EmitterHandle },
	trails: { TrailHandle },
	lights: { LightHandle },
}

-- t = seconds since the cast began on this client (catch-up included); false = finished.
type Step = (t: number, dt: number) -> boolean
-- An ability strike from the same caster and ability; true = it belonged to this visual.
type StrikeHook = (strike: AbilityStrike) -> boolean
type Builder = (cast: Cast, def: Def, kit: Kit) -> (Step?, StrikeHook?)

type Visual = {
	userId: number,
	ability: string,
	kit: Kit,
	clock0: number,
	step: Step,
	onStrike: StrikeHook?,
}

type EmitterStyle = {
	texture: string,
	lightEmission: number,
	lightInfluence: number,
	size: NumberSequence,
	transparency: NumberSequence,
	lifetime: NumberRange,
	speed: NumberRange,
	spreadDegrees: number,
	acceleration: Vector3,
	drag: number,
	rotSpeed: NumberRange,
}

type Placed = { part: BasePart, frame: CFrame }
type Streak = { part: BasePart, radius: number, angle: number, lift: number, born: number }
type Crack = { part: BasePart, reach: number }
type Chunk = { part: BasePart, velocity: Vector3, spin: Vector3 }
type Ghost = { parts: { BasePart }, born: number }
type SlugBlast = {
	flash: BasePart,
	streaks: { BasePart },
	casing: BasePart?,
	muzzle: Vector3,
	startsAt: number,
	casingVelocity: Vector3,
	fired: boolean,
}
type RingArc = { parts: { BasePart }, ring: number, index: number }
type Bomblet = { shell: BasePart, blink: BasePart, ring: { BasePart }, point: Vector3 }
type SectorPiece = { part: BasePart, offset: CFrame, slice: number, base: number }
type PylonSpec = { shape: Enum.PartType, size: Vector3, height: number, glow: boolean }
type PylonPiece = { part: BasePart, offset: CFrame, glow: boolean }

-- General --------------------------------------------------------------------------------

local FOLDER_NAME = "RangeAbilityFx"
local EPSILON = 1e-6
local TAU = 2 * math.pi
local UP = Vector3.yAxis
local FLAT_U = Vector3.xAxis
local FLAT_V = Vector3.zAxis
-- A Cylinder's axis is its X; this turn stands it upright (discs, pylon parts).
local STAND_UP = CFrame.Angles(0, 0, math.pi / 2)
-- Visuals alive at once. Past this the oldest ends, which only happens with cooldowns off.
local MAX_VISUALS = 24
-- Seconds of one-way lag plus batching that still count as on time (strikes lag the same).
local CATCH_UP_GRACE = 0.2
-- A one-off burst further in the past than this at its first step (a catch-up) is skipped.
local FRESH_SECONDS = 0.1
local PART_POOL_MAX = 500
local WEDGE_POOL_MAX = 80
local BEAM_POOL_MAX = 48
local EMITTER_POOL_MAX = 32
local TRAIL_POOL_MAX = 6
local LIGHT_POOL_MAX = 16
-- Ruling 4 step 4, mirrored: a down-ray from 3 studs above for 250 studs.
local FLOOR_PROBE_UP = 3
local FLOOR_PROBE_DOWN = 250
-- Root centre above the floor for an R6 rig (legs 2 + half the root); R15 reads HipHeight.
local R6_ROOT_HEIGHT = 3
-- The weapon sits this far along the aim from the right hand.
local MUZZLE_FORWARD = 1
-- Ground marks float this far above the floor so they never z-fight it.
local LIFT = 0.06
local MIN_RADIUS = 0.05
local MIN_SIZE = 0.05
-- Ring segments are lengthened by this share of their width so the joints close.
local JOINT_OVERLAP = 0.5
local RING_SEGMENTS = 32
local RING_SEGMENTS_LOW_END = 16
local BIG_RING_SEGMENTS = 24
local BIG_RING_SEGMENTS_LOW_END = 12
local RING_WIDTH = 0.35
local RING_HEIGHT = 0.12
local RING_TRANSPARENCY = 0.2
local FILL_TRANSPARENCY = 0.9
local FILL_PULSE_TRANSPARENCY = 0.78
local DISC_THICKNESS = 0.05
local SECTOR_THICKNESS = 0.05
-- A tick strike brightens its zone, decaying over this long.
local PULSE_SECONDS = 0.2
local ZONE_FADE_IN = 0.12
local ZONE_FADE_OUT = 0.2
-- A zone's tick strike starts at its ground point; horizontal slack when matching one.
local STRIKE_MATCH_STUDS = 2
-- Manual emission never catches up more than this many particles after a long frame.
local MAX_EMIT_BUDGET = 8
-- Engine-bundled textures (always present, no upload).
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local MOTE_LIFETIME = 0.4

local SPARK_STYLE: EmitterStyle = {
	texture = SPARK_TEXTURE,
	lightEmission = 1,
	lightInfluence = 0,
	size = NumberSequence.new(0.35, 0),
	transparency = NumberSequence.new(0, 0.3),
	lifetime = NumberRange.new(0.15, 0.4),
	speed = NumberRange.new(14, 32),
	spreadDegrees = 35,
	acceleration = Vector3.new(0, -40, 0),
	drag = 4,
	rotSpeed = NumberRange.new(0),
}
local DUST_STYLE: EmitterStyle = {
	texture = SMOKE_TEXTURE,
	lightEmission = 0,
	lightInfluence = 1,
	size = NumberSequence.new(1.4, 4),
	transparency = NumberSequence.new(0.35, 1),
	lifetime = NumberRange.new(0.7, 1.1),
	speed = NumberRange.new(5, 11),
	spreadDegrees = 25,
	acceleration = Vector3.new(0, 3, 0),
	drag = 2.5,
	rotSpeed = NumberRange.new(-50, 50),
}
local SMOKE_STYLE: EmitterStyle = {
	texture = SMOKE_TEXTURE,
	lightEmission = 0,
	lightInfluence = 1,
	size = NumberSequence.new(0.5, 2.2),
	transparency = NumberSequence.new(0.45, 1),
	lifetime = NumberRange.new(0.5, 0.9),
	speed = NumberRange.new(1.5, 4),
	spreadDegrees = 20,
	acceleration = Vector3.new(0, 5, 0),
	drag = 1.5,
	rotSpeed = NumberRange.new(-40, 40),
}
-- Motes fly straight at a point and die on arrival (speed = distance / MOTE_LIFETIME).
local MOTE_STYLE: EmitterStyle = {
	texture = SPARK_TEXTURE,
	lightEmission = 1,
	lightInfluence = 0,
	size = NumberSequence.new(0.35, 0.08),
	transparency = NumberSequence.new(0.05, 0.5),
	lifetime = NumberRange.new(MOTE_LIFETIME),
	speed = NumberRange.new(10),
	spreadDegrees = 0,
	acceleration = Vector3.zero,
	drag = 0,
	rotSpeed = NumberRange.new(0),
}
-- Shared palette (Theme, owned by Feedback). Exact areas and outlines use the ability colour, so a
-- lasting area and the strikes it lands read as one thing; families that already have a colour in
-- Feedback keep it (bows gold, Beam cyan, lightning blue-white). Flourishes (dust, fire, smoke,
-- metal) keep their material colours.
local ABILITY_COLOR = Theme.COMBAT_RANGE_ABILITY_COLOR
local HOT_WHITE = Theme.COMBAT_RANGE_BEAM_CORE_COLOR
local DUST_COLOR = Color3.fromRGB(196, 172, 134)
local DUST_RISE = 0.8
local SMOKE_COLOR = Color3.fromRGB(150, 150, 155)
local TRAIL_TRANSPARENCY = NumberSequence.new(0.15, 1)
local TRAIL_TAPER = NumberSequence.new(1, 0.3)

-- Whirlwind: three crescent slashes spinning at the reach, the exact ring on the floor, streaks.
local WHIRL_COLOR = HOT_WHITE
local WHIRL_GLOW = ABILITY_COLOR
local WHIRL_BLADES = 3
local WHIRL_BLADE_SEGMENTS = 8
local WHIRL_BLADE_DEGREES = 110
local WHIRL_BLADE_HEAD_WIDTH = 1.3
local WHIRL_BLADE_TAIL_WIDTH = 0.2
local WHIRL_BLADE_HEIGHT = 0.15
local WHIRL_BLADE_HEAD_TRANSPARENCY = 0
local WHIRL_BLADE_TAIL_TRANSPARENCY = 0.85
local WHIRL_SPIN = math.rad(900)
local WHIRL_SPIN_UP_SECONDS = 0.12
local WHIRL_FADE_SECONDS = 0.18
local WHIRL_STREAKS = 8
local WHIRL_STREAK_LENGTH = 2.6
local WHIRL_STREAK_WIDTH = 0.12
local WHIRL_STREAK_SECONDS = 0.3
local WHIRL_STREAK_SPEED = 1.4
local WHIRL_STREAK_MIN_SHARE = 0.35
local WHIRL_STREAK_MAX_SHARE = 0.95
local WHIRL_STREAK_LIFT = 1.2
local WHIRL_STREAK_TRANSPARENCY = 0.2
local WHIRL_FILL_TRANSPARENCY = 0.93

-- Earthquake: a dust front stepping out ring by ring, the exact ring flashing as each lands, and
-- glowing cracks that open behind the front.
local QUAKE_MARK_COLOR = ABILITY_COLOR
local QUAKE_CRACK_COLOR = Color3.fromRGB(255, 128, 44)
local QUAKE_CRATER_COLOR = Color3.fromRGB(74, 60, 48)
local QUAKE_MAX_RINGS = 8
local QUAKE_EXPAND_SECONDS = 0.12
local QUAKE_FRONT_WIDTH = 0.9
local QUAKE_FRONT_HEIGHT = 1.4
local QUAKE_FRONT_SETTLE = 0.4 -- share of its height the front keeps while fading
local QUAKE_FRONT_TRANSPARENCY = 0.25
local QUAKE_FRONT_FADE = 0.3
local QUAKE_FRONT_MIN_RADIUS = 0.5
local QUAKE_MARK_WIDTH = 0.4
local QUAKE_MARK_TRANSPARENCY = 0.05
local QUAKE_MARK_SECONDS = 0.5
local QUAKE_CRACKS = 8
local QUAKE_CRACKS_LOW_END = 5
local QUAKE_CRACK_START = 0.8
local QUAKE_CRACK_STEP = 2.5
local QUAKE_CRACK_JITTER = 0.22 -- radians of wander per step
local QUAKE_CRACK_WIDTH = 0.45
local QUAKE_CRACK_TIP_WIDTH = 0.15
local QUAKE_CRACK_HEIGHT = 0.08
local QUAKE_CRACK_TRANSPARENCY = 0.1
local QUAKE_CRACK_HOLD = 0.8
local QUAKE_CRACK_FADE = 0.4
local QUAKE_CRATER_SIZE = 4
local QUAKE_CRATER_TRANSPARENCY = 0.15
local QUAKE_SLAM_SIZE = 3.5
local QUAKE_SLAM_TRANSPARENCY = 0.1
local QUAKE_SLAM_FADE = 0.2
local QUAKE_DUST_POINTS = 16
local QUAKE_DUST_PER_POINT = 2

-- Blade Storm: a spinning blade thrown to the point, then blades spiralling into the centre.
local STORM_COLOR = ABILITY_COLOR
local STORM_BLADE_COLOR = HOT_WHITE
local STORM_THROW_ARC = 3
local STORM_THROW_SPIN = math.rad(1440)
local STORM_THROW_ARMS = 3
local STORM_THROW_ARM_LENGTH = 2.2
local STORM_ARM_WIDTH = 0.35
local STORM_ARM_THICKNESS = 0.1
local STORM_TRAIL_SECONDS = 0.2
local STORM_TRAIL_HALF = 0.5
local STORM_VORTEX_BLADES = 6
local STORM_VORTEX_BLADES_LOW_END = 3
local STORM_VORTEX_ARMS = 2
local STORM_VORTEX_ARM_LENGTH = 1.4
local STORM_INWARD_RATE = 0.9 -- rim-to-centre trips per second, per blade
local STORM_SPIN = math.rad(360)
local STORM_SWIRL = math.rad(540) -- extra turn over one trip, so the spiral tightens inward
local STORM_BLADE_SPIN = math.rad(1080)
local STORM_BLADE_LOW = 0.5
local STORM_BLADE_HIGH = 3.2
local STORM_EDGE_SHARE = 0.15 -- share of a trip spent fading in at the rim and out at the centre
local STORM_EYE_HEIGHT = 1.6
local STORM_EYE_SIZE = 1.4
local STORM_EYE_TRANSPARENCY = 0.35
local STORM_EYE_THROB = 12 -- radians per second
local STORM_SUCTION_RATE = 40

-- Leap Smash: the exact landing circle filling in, a trail on the caster, a dust burst on landing.
local LEAP_COLOR = ABILITY_COLOR
local LEAP_BLINK_RATE = 14
local LEAP_FILL_RING_TRANSPARENCY = 0.35
local LEAP_NOTCHES = 4
local LEAP_NOTCH_LENGTH = 1.6
local LEAP_MARKER_FADE = 0.12
local LEAP_TRAIL_HALF = 1.1
local LEAP_TRAIL_SECONDS = 0.3
local LEAP_DUST_EXPAND = 0.18
local LEAP_DUST_FADE = 0.5
local LEAP_TAIL = 0.8
local LEAP_DUST_POINTS = 16
local LEAP_DEBRIS = 10
local LEAP_DEBRIS_SIZE_MIN = 0.4
local LEAP_DEBRIS_SIZE_MAX = 0.9
local LEAP_DEBRIS_OUT_MIN = 10
local LEAP_DEBRIS_OUT_MAX = 22
local LEAP_DEBRIS_UP_MIN = 16
local LEAP_DEBRIS_UP_MAX = 28
local LEAP_DEBRIS_GRAVITY = 80
local LEAP_DEBRIS_SECONDS = 0.7
local LEAP_DEBRIS_SPIN = 12
local LEAP_LIGHT = 6
local LEAP_LIGHT_SECONDS = 0.3

-- Impale Dash: a streak from the cast root to the dash end with the capsule's edges, afterimages.
local DASH_COLOR = ABILITY_COLOR
local DASH_CORE_COLOR = HOT_WHITE
local DASH_TAIL_WIDTH = 0.15
local DASH_HEAD_WIDTH = 1.4
local DASH_TAIL_TRANSPARENCY = 0.8
local DASH_HEAD_TRANSPARENCY = 0
local DASH_EDGE_WIDTH = 0.2
local DASH_EDGE_TRANSPARENCY = 0.35
local DASH_COLLAPSE_SECONDS = 0.2
local DASH_AFTERIMAGES = 4
local DASH_AFTERIMAGES_LOW_END = 2
local DASH_POSE_PARTS = 16
local DASH_AFTERIMAGE_TRANSPARENCY = 0.45
local DASH_AFTERIMAGE_SECONDS = 0.35

-- Arrow Rain: the exact circle, blinking while the arrows are in the air, then a steady rain.
local RAIN_COLOR = Theme.COMBAT_RANGE_CHARGE_COLOR
local RAIN_ARROW_COLOR = Theme.COMBAT_RANGE_ARROW_COLOR
local RAIN_ARROWS_PER_SECOND = 36
local RAIN_ARROWS_PER_SECOND_LOW_END = 16
local RAIN_FALL_SECONDS = 0.22
local RAIN_FALL_SPEED = 150
local RAIN_SLANT = 0.35 -- arrows lean in from the caster's side
local RAIN_ARROW_LENGTH = 3
local RAIN_ARROW_WIDTH = 0.16
local RAIN_STREAK_LENGTH = 6
local RAIN_STREAK_WIDTH = 0.1
local RAIN_STREAK_TRANSPARENCY = 0.45
local RAIN_SINK = 0.7
local RAIN_STICK_SECONDS = 0.35
local RAIN_FADE_SECONDS = 0.15
local RAIN_SPARKS = 3
local RAIN_BLINK_RATE = 18
local RAIN_BLINK_LOW = 0.05
local RAIN_BLINK_HIGH = 0.55
local RAIN_LOCK_FROM = 1.5 -- the lock-on ring closes from this multiple of the radius
local RAIN_LOCK_TRANSPARENCY = 0.35
local RAIN_NOTCHES = 4
local RAIN_NOTCH_LENGTH = 1.8

-- Volley: a gold flash and a fan of streaks across the volley's arc.
local VOLLEY_COLOR = Theme.COMBAT_RANGE_CHARGE_COLOR
local VOLLEY_SECONDS = 0.35
local VOLLEY_MAX_STREAKS = 16
local VOLLEY_STREAK_START = 0.4
local VOLLEY_STREAK_LENGTH = 4.5
local VOLLEY_STREAK_WIDTH = 0.18
local VOLLEY_STREAK_TRANSPARENCY = 0.1
local VOLLEY_GROW_SECONDS = 0.1
local VOLLEY_FLASH_SIZE = 2.8
local VOLLEY_RING_SEGMENTS = 12
local VOLLEY_RING_FROM = 0.4
local VOLLEY_RING_TO = 2.6
local VOLLEY_SPARKS = 14
local VOLLEY_LIGHT = 5
local VOLLEY_LIGHT_RANGE = 12

-- Slug Burst: one muzzle blast per slug (flash, flare streaks inside the cone, smoke, a shell).
local SLUG_COLOR = Theme.COMBAT_RANGE_BLAST_COLOR
local SLUG_CASING_COLOR = Color3.fromRGB(200, 60, 50)
local SLUG_MAX_BLASTS = 12
local SLUG_FLASH_SECONDS = 0.14
local SLUG_FLASH_SIZE = 2.6
local SLUG_FLASH_MIN = 0.3
local SLUG_FLASH_FORWARD = 0.8
local SLUG_STREAKS = 6
local SLUG_STREAKS_LOW_END = 3
local SLUG_STREAK_SHARE = 0.8 -- flare streaks lean out to this share of the cone's half-angle
local SLUG_STREAK_LENGTH = 3.8
local SLUG_STREAK_WIDTH = 0.28
local SLUG_SMOKE = 6
local SLUG_SPARKS = 10
local SLUG_CASING_SIZE = Vector3.new(0.22, 0.22, 0.5)
local SLUG_CASING_SECONDS = 0.5
local SLUG_CASING_SIDE_MIN = 6
local SLUG_CASING_SIDE_MAX = 10
local SLUG_CASING_UP_MIN = 8
local SLUG_CASING_UP_MAX = 12
local SLUG_CASING_GRAVITY = 60
local SLUG_CASING_TUMBLE = 20
local SLUG_LIGHT = 7
local SLUG_LIGHT_RANGE = 14

-- Overcharged Shot: a charge ball with closing rings and a laser sight, then the beam afterglow.
local OC_CORE_COLOR = HOT_WHITE
local OC_GLOW_COLOR = ABILITY_COLOR
local OC_CORE_FROM = 0.3
local OC_CORE_TO = 1.8
local OC_GLOW_FROM = 0.6
local OC_GLOW_TO = 3.4
local OC_GLOW_TRANSPARENCY = 0.55
local OC_FLICKER = 0.25
local OC_RINGS = 2
local OC_RING_ARCS = 3
local OC_RING_ARC_DEGREES = 70
local OC_RING_ARC_SEGMENTS = 4
local OC_RING_FROM = 2.6
local OC_RING_TO = 0.9
local OC_RING_INNER_SHARE = 0.75
local OC_RING_SPIN = math.rad(540)
local OC_RING_WIDTH = 0.12
local OC_LASER_WIDTH = 0.08
local OC_LASER_FROM = 0.75
local OC_LASER_TRANSPARENCY = 0.3
local OC_MOTE_RATE = 60
local OC_MOTE_RADIUS = 3
local OC_LIGHT_CHARGE = 4
local OC_LIGHT_FIRE = 10
local OC_LIGHT_RANGE = 16
-- Feedback's full-width tube from the ray strike is the hitbox; this is only a thin trace that
-- outlasts it briefly, so the hitboxEffect slider can still hide the tube.
local OC_AFTERGLOW_SECONDS = 0.3
local OC_AFTERGLOW_WIDTH = 0.25
local OC_AFTERGLOW_TRANSPARENCY = 0.1
local OC_FLASH_SIZE = 3.2
local OC_FLASH_SECONDS = 0.15
local OC_SHOCK_SEGMENTS = 16
local OC_SHOCK_FROM = 0.5
local OC_SHOCK_TO = 3.2
local OC_SHOCK_SECONDS = 0.25
local OC_END_SPARKS = 20

-- Mag Dump: the gun glows hotter, spits sparks and smokes for the whole buff.
local MAG_HEAT_COLOR = Color3.fromRGB(255, 96, 32)
local MAG_HOT_COLOR = Color3.fromRGB(255, 236, 180)
local MAG_SPARK_COLOR = Color3.fromRGB(255, 200, 90)
local MAG_WHITE_SHARE = 0.5 -- how far toward white-hot the glow gets at the end
local MAG_GLOW_MIN = 0.6
local MAG_GLOW_MAX = 1.2
local MAG_HEAT_GROWTH = 0.4
local MAG_GLOW_TRANSPARENCY_MIN = 0.15
local MAG_GLOW_TRANSPARENCY_MAX = 0.45
local MAG_HAND_GLOW = 1.6
local MAG_HAND_COOL = 0.85
local MAG_HAND_HOT = 0.55
local MAG_SPARK_RATE = 45
local MAG_SMOKE_RATE = 10
local MAG_FADE_IN = 0.05
local MAG_TAIL_SECONDS = 0.25
local MAG_LIGHT = 3
local MAG_LIGHT_HEAT = 4
local MAG_LIGHT_RANGE = 10

-- Cluster Shell: bomblets hop out of the splash and blink over their exact blast radius.
local CLUSTER_SHELL_COLOR = Theme.COMBAT_RANGE_SHELL_COLOR
local CLUSTER_BLINK_COLOR = Color3.fromRGB(255, 50, 40)
local CLUSTER_RING_COLOR = ABILITY_COLOR
local CLUSTER_PENDING_SLACK = 1
local CLUSTER_MATCH_STUDS = 1
local CLUSTER_HOP_SECONDS = 0.25
local CLUSTER_HOP_SHARE = 0.6 -- a short fuse still leaves time to blink after the hop
local CLUSTER_HOP_HEIGHT = 4
local CLUSTER_SIZE = 0.8
local CLUSTER_BLINK_SIZE = 1.1
local CLUSTER_BLINK_TRANSPARENCY = 0.1
local CLUSTER_BLINK_SLOW = 0.22
local CLUSTER_BLINK_FAST = 0.06
local CLUSTER_RING_SEGMENTS = 12
local CLUSTER_RING_SEGMENTS_LOW_END = 8
local CLUSTER_RING_ON = 0.2
local CLUSTER_RING_OFF = 0.7
local CLUSTER_TAIL_SECONDS = 0.03

-- Overload Sweep: a thick beam sweeping left to right, lighting each server slice as it lands.
local SWEEP_CORE_COLOR = Theme.COMBAT_RANGE_BEAM_CORE_COLOR
local SWEEP_GLOW_COLOR = Theme.COMBAT_RANGE_BEAM_COLOR
local SWEEP_CORE_WIDTH = 0.7
local SWEEP_GLOW_WIDTH = 2.4
local SWEEP_PULSE_WIDTH = 1.5
local SWEEP_GLOW_TRANSPARENCY = Theme.COMBAT_RANGE_BEAM_GLOW_TRANSPARENCY
local SWEEP_MAX_SLICES = 36
local SWEEP_FILL_TRANSPARENCY = 0.86
local SWEEP_RIM_TRANSPARENCY = 0.25
local SWEEP_SLICE_FADE_IN = 0.06
local SWEEP_FADE_IN = 0.06
local SWEEP_FADE_SECONDS = 0.3
local SWEEP_FLARE_SIZE = 2.2
local SWEEP_FLARE_FORWARD = 1
local SWEEP_TIP_SIZE = 1.6
local SWEEP_TIP_SPARK_RATE = 30
local SWEEP_LIGHT = 5
local SWEEP_LIGHT_RANGE = 14

-- Storm Coil: a pylon thrown to the point, crackling inside the exact (faint) zap radius.
local COIL_COLOR = Theme.COMBAT_RANGE_LIGHTNING_COLOR
local COIL_METAL_COLOR = Color3.fromRGB(70, 76, 88)
local COIL_ARC_COLOR = Theme.COMBAT_RANGE_LIGHTNING_CORE_COLOR
-- Shared with Feedback, whose zap bolts start at the pylon's glowing top.
local COIL_TOP_HEIGHT = Theme.COMBAT_RANGE_COIL_TOP_HEIGHT
local COIL_PYLON: { PylonSpec } = {
	{
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.6, 1.8, 1.8),
		height = 0.3,
		glow = false,
	},
	{
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(3.6, 0.45, 0.45),
		height = 2.4,
		glow = false,
	},
	{
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.2, 1.4, 1.4),
		height = 1.4,
		glow = true,
	},
	{
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.2, 1.2, 1.2),
		height = 2.3,
		glow = true,
	},
	{ shape = Enum.PartType.Cylinder, size = Vector3.new(0.2, 1, 1), height = 3.2, glow = true },
	{
		shape = Enum.PartType.Ball,
		size = Vector3.new(1, 1, 1),
		height = COIL_TOP_HEIGHT,
		glow = true,
	},
}
local COIL_PIVOT_HEIGHT = 2.2
local COIL_GLOW_TRANSPARENCY = 0.1
local COIL_THROW_ARC = 4
local COIL_TUMBLE = math.rad(720)
local COIL_DEPLOY_SECONDS = 0.18
local COIL_RING_TRANSPARENCY = 0.45
local COIL_FILL_TRANSPARENCY = 0.94
local COIL_ARCS = 3
local COIL_ARCS_LOW_END = 1
local COIL_ARC_SEGMENTS = 3
local COIL_ARC_MIN = 1.2
local COIL_ARC_REACH = 2.6
local COIL_ARC_JITTER = 0.5
local COIL_ARC_WIDTH = 0.12
local COIL_ARC_CHANCE = 0.7
local COIL_CRACKLE_SECONDS = 0.07
local COIL_FADE_SECONDS = 0.25
local COIL_LIGHT = 3
local COIL_LIGHT_PULSE = 6
local COIL_LIGHT_RANGE = 14
local COIL_PULSE_SPARKS = 12

local AbilityFx = {}

local connections: { RBXScriptConnection } = {}
local folder: Folder? = nil
local anchor: Part? = nil
local partPool: { Part } = {}
local wedgePool: { WedgePart } = {}
local beamPool: { BeamHandle } = {}
local emitterPool: { EmitterHandle } = {}
local trailPool: { TrailHandle } = {}
local lightPool: { LightHandle } = {}
-- Parts past the pool cap wait here for one BulkMoveTo, which may still hold a move for them.
local doomed: { BasePart } = {}
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local visuals: { Visual } = {}
local lowEnd = false
local started = false
local destroyed = false

-- Maths ----------------------------------------------------------------------------------

local function lerp(a: number, b: number, u: number): number
	return a + (b - a) * u
end

local function clamp01(u: number): number
	return math.clamp(u, 0, 1)
end

local function easeOut(u: number): number
	return 1 - (1 - u) * (1 - u)
end

-- 1 inside [from, to), rising over `rise` seconds and falling over the last `fall` seconds.
local function envelope(t: number, from: number, to: number, rise: number, fall: number): number
	if t < from or t >= to then
		return 0
	end
	local up = if rise > 0 then clamp01((t - from) / rise) else 1
	local down = if fall > 0 then clamp01((to - t) / fall) else 1
	return math.min(up, down)
end

local function unitOf(vector: Vector3): Vector3?
	if vector.Magnitude < EPSILON then
		return nil
	end
	return vector.Unit
end

local function flatUnit(vector: Vector3): Vector3?
	return unitOf(Vector3.new(vector.X, 0, vector.Z))
end

-- Two unit vectors perpendicular to `axis` and to each other (right first).
local function basis(axis: Vector3): (Vector3, Vector3)
	local reference = if math.abs(axis.Y) < 0.99 then UP else Vector3.xAxis
	local right = axis:Cross(reference).Unit
	return right, right:Cross(axis).Unit
end

-- A horizontal unit vector at `angle` (radians) in the X–Z plane, and its direction of travel.
local function around(angle: number): Vector3
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

local function tangentOf(angle: number): Vector3
	return Vector3.new(-math.sin(angle), 0, math.cos(angle))
end

-- HitShapes / AbilityService sweep convention: negative angles are the caster's left (heading
-- × up is the right), so a left-to-right sweep runs from -half to +half.
local function turn(heading: Vector3, angle: number): Vector3
	return heading * math.cos(angle) + heading:Cross(UP) * math.sin(angle)
end

-- An emitter frame whose +Y (EmissionDirection Top) points along `direction` (unit).
local function frameAlong(position: Vector3, direction: Vector3): CFrame
	local right = basis(direction)
	return CFrame.fromMatrix(position, right, direction)
end

-- The frame and length of a bar from a to b whose thin side faces `up`.
local function barFrame(a: Vector3, b: Vector3, up: Vector3): (CFrame, number)
	local along = b - a
	local length = along.Magnitude
	if length < EPSILON then
		return CFrame.new(a), 0
	end
	local normal = up
	if math.abs(along.Unit:Dot(normal)) > 0.99 then
		local _, fallback = basis(along.Unit)
		normal = fallback
	end
	return CFrame.lookAt((a + b) / 2, b, normal), length
end

local function positive(value: number?): number?
	if value ~= nil and value == value and value > 0 then
		return value
	end
	return nil
end

local function nonNegative(value: number?): number?
	if value ~= nil and value == value and value >= 0 then
		return value
	end
	return nil
end

local function particles(count: number): number
	if lowEnd and count > 0 then
		return math.max(count // 2, 1)
	end
	return count
end

local function rate(perSecond: number): number
	return if lowEnd then perSecond / 2 else perSecond
end

local function ringSegments(): number
	return if lowEnd then RING_SEGMENTS_LOW_END else RING_SEGMENTS
end

local function bigSegments(): number
	return if lowEnd then BIG_RING_SEGMENTS_LOW_END else BIG_RING_SEGMENTS
end

-- Characters and the world -----------------------------------------------------------------

-- The caster's root, humanoid and character, or nils while the character is missing.
local function casterOf(userId: number): (BasePart?, Humanoid?, Model?)
	local player = Players:GetPlayerByUserId(userId)
	local character = if player ~= nil then player.Character else nil
	if character == nil then
		return nil, nil, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return root, character:FindFirstChildOfClass("Humanoid"), character
end

local function floorUnder(root: BasePart, humanoid: Humanoid?): number
	if humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	end
	return root.Position.Y - R6_ROOT_HEIGHT
end

local function rootHeightOf(userId: number): number
	local root, humanoid = casterOf(userId)
	if root == nil then
		return R6_ROOT_HEIGHT
	end
	return root.Position.Y - floorUnder(root, humanoid)
end

local function handOf(character: Model?, root: BasePart): Vector3
	local hand = if character ~= nil
		then character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		else nil
	if hand ~= nil and hand:IsA("BasePart") then
		return hand.Position
	end
	return root.Position
end

-- Where a caster's weapon is: the right hand pushed along the aim, else the fallback.
local function muzzleOf(userId: number, aim: Vector3, fallback: Vector3): Vector3
	local root, _, character = casterOf(userId)
	if root == nil then
		return fallback
	end
	return handOf(character, root) + aim * MUZZLE_FORWARD
end

-- The local player aims with the camera; anyone else faces where they aim.
local function aimOf(userId: number, root: BasePart): Vector3
	local camera = Workspace.CurrentCamera
	if userId == Players.LocalPlayer.UserId and camera ~= nil then
		return camera.CFrame.LookVector
	end
	return root.CFrame.LookVector
end

-- Skips every character and this module's folder. Crowd bodies and Feedback's fx parts have
-- CanQuery off, so the world is all that is left.
local function worldParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = {}
	local root = folder
	if root ~= nil then
		table.insert(ignored, root)
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignored, character)
		end
	end
	params.FilterDescendantsInstances = ignored
	params.IgnoreWater = true
	return params
end

local function rayEnd(from: Vector3, direction: Vector3, range: number): Vector3
	local hit = Workspace:Raycast(from, direction * range, worldParams())
	return if hit ~= nil then hit.Position else from + direction * range
end

local function floorBelow(position: Vector3, fallbackY: number): Vector3
	local hit = Workspace:Raycast(
		position + UP * FLOOR_PROBE_UP,
		Vector3.new(0, -FLOOR_PROBE_DOWN, 0),
		worldParams()
	)
	if hit ~= nil then
		return hit.Position
	end
	return Vector3.new(position.X, fallbackY, position.Z)
end

-- The cast's ground point (zones, landing, Earthquake's floor centre), lifted off the floor. The
-- server always sends one for these; the probe below the cast root covers an older server.
local function groundOf(cast: Cast): Vector3
	local target = cast.target
	local ground = if target ~= nil
		then target
		else floorBelow(cast.origin, cast.origin.Y - rootHeightOf(cast.userId))
	return ground + UP * LIFT
end

-- Pools ------------------------------------------------------------------------------------

local function newKit(): Kit
	return { parts = {}, beams = {}, emitters = {}, trails = {}, lights = {} }
end

local function newPart(className: string): BasePart
	return Create(className, {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		Parent = folder,
	}) :: BasePart
end

-- Every part comes out hidden; the visual's step decides when it shows.
local function takePart(
	kit: Kit,
	shape: Enum.PartType,
	color: Color3,
	material: Enum.Material
): BasePart
	local part = table.remove(partPool) or newPart("Part") :: Part
	part.Shape = shape
	part.Color = color
	part.Material = material
	part.Transparency = 1
	table.insert(kit.parts, part)
	-- Callers keep parts in records typed BasePart (table fields are invariant).
	return part :: BasePart
end

local function takeParts(
	kit: Kit,
	count: number,
	shape: Enum.PartType,
	color: Color3,
	material: Enum.Material
): { BasePart }
	local parts: { BasePart } = {}
	for _ = 1, count do
		table.insert(parts, takePart(kit, shape, color, material))
	end
	return parts
end

local function takeWedge(kit: Kit, color: Color3): BasePart
	local wedge = table.remove(wedgePool) or newPart("WedgePart") :: WedgePart
	wedge.Color = color
	wedge.Material = Enum.Material.Neon
	wedge.Transparency = 1
	table.insert(kit.parts, wedge)
	return wedge :: BasePart
end

local function givePart(part: BasePart): ()
	part.Transparency = 1
	if part:IsA("WedgePart") then
		if #wedgePool < WEDGE_POOL_MAX then
			table.insert(wedgePool, part)
			return
		end
	elseif part:IsA("Part") then
		if #partPool < PART_POOL_MAX then
			table.insert(partPool, part)
			return
		end
	end
	table.insert(doomed, part)
end

local function newAttachment(name: string): Attachment
	return Create("Attachment", { Name = name, Parent = anchor }) :: Attachment
end

-- A camera-facing ribbon between two pooled attachments, fully transparent until shown.
local function takeBeam(kit: Kit, color: Color3, width: number): BeamHandle
	local handle = table.remove(beamPool)
	if handle == nil then
		local a0 = newAttachment("BeamStart")
		local a1 = newAttachment("BeamEnd")
		local beam = Create("Beam", {
			Attachment0 = a0,
			Attachment1 = a1,
			FaceCamera = true,
			LightEmission = 1,
			LightInfluence = 0,
			Segments = 1,
			Enabled = false,
			Parent = anchor,
		}) :: Beam
		handle = { beam = beam, a0 = a0, a1 = a1, shown = 1 }
	end
	local resolved = handle :: BeamHandle
	resolved.beam.Color = ColorSequence.new(color)
	resolved.beam.Width0 = width
	resolved.beam.Width1 = width
	resolved.beam.Transparency = NumberSequence.new(1)
	resolved.shown = 1
	resolved.beam.Enabled = true
	table.insert(kit.beams, resolved)
	return resolved
end

local function giveBeam(handle: BeamHandle): ()
	handle.beam.Enabled = false
	if #beamPool < BEAM_POOL_MAX then
		table.insert(beamPool, handle)
		return
	end
	handle.beam:Destroy()
	handle.a0:Destroy()
	handle.a1:Destroy()
end

local function takeEmitter(kit: Kit, style: EmitterStyle, color: Color3): EmitterHandle
	local now = os.clock()
	local handle: EmitterHandle? = nil
	for index = #emitterPool, 1, -1 do
		if emitterPool[index].readyAt <= now then
			handle = table.remove(emitterPool, index)
			break
		end
	end
	if handle == nil then
		local attachment = newAttachment("Emitter")
		local emitter = Create("ParticleEmitter", {
			Enabled = false,
			EmissionDirection = Enum.NormalId.Top,
			Rotation = NumberRange.new(0, 360),
			Rate = 0,
			Parent = attachment,
		}) :: ParticleEmitter
		handle = { attachment = attachment, emitter = emitter, readyAt = 0, lifeMax = 0 }
	end
	local resolved = handle :: EmitterHandle
	local emitter = resolved.emitter
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Texture = style.texture
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = style.lightEmission
	emitter.LightInfluence = style.lightInfluence
	emitter.Size = style.size
	emitter.Transparency = style.transparency
	emitter.Lifetime = style.lifetime
	emitter.Speed = style.speed
	emitter.SpreadAngle = Vector2.new(style.spreadDegrees, style.spreadDegrees)
	emitter.Acceleration = style.acceleration
	emitter.Drag = style.drag
	emitter.RotSpeed = style.rotSpeed
	resolved.lifeMax = style.lifetime.Max
	table.insert(kit.emitters, resolved)
	return resolved
end

local function giveEmitter(handle: EmitterHandle): ()
	handle.emitter.Enabled = false
	handle.readyAt = os.clock() + handle.lifeMax
	if #emitterPool < EMITTER_POOL_MAX then
		table.insert(emitterPool, handle)
		return
	end
	-- Past the cap: let the last particles land before the emitter goes.
	local attachment = handle.attachment
	task.delay(handle.lifeMax, function()
		attachment:Destroy()
	end)
end

local function emitAt(handle: EmitterHandle, frame: CFrame, count: number): ()
	if count <= 0 then
		return
	end
	handle.attachment.WorldCFrame = frame
	handle.emitter:Emit(count)
end

local function setEmitting(handle: EmitterHandle, on: boolean): ()
	if handle.emitter.Enabled ~= on then
		handle.emitter.Enabled = on
	end
end

-- A trail between two attachments this module moves (never parented into a character, so a
-- respawn cannot take pooled instances with it).
local function takeTrail(
	kit: Kit,
	color: Color3,
	lifetime: number,
	centre: Vector3,
	halfWidth: number
): TrailHandle
	local handle = table.remove(trailPool)
	if handle == nil then
		local a0 = newAttachment("TrailTop")
		local a1 = newAttachment("TrailBottom")
		local trail = Create("Trail", {
			Attachment0 = a0,
			Attachment1 = a1,
			FaceCamera = true,
			LightEmission = 1,
			LightInfluence = 0,
			MinLength = 0.05,
			Transparency = TRAIL_TRANSPARENCY,
			WidthScale = TRAIL_TAPER,
			Enabled = false,
			Parent = anchor,
		}) :: Trail
		handle = { trail = trail, a0 = a0, a1 = a1 }
	end
	local resolved = handle :: TrailHandle
	resolved.trail.Color = ColorSequence.new(color)
	resolved.trail.Lifetime = lifetime
	resolved.a0.WorldPosition = centre + UP * halfWidth
	resolved.a1.WorldPosition = centre - UP * halfWidth
	-- Cleared after the move, so no streak runs from wherever the pooled trail last was.
	resolved.trail:Clear()
	resolved.trail.Enabled = true
	table.insert(kit.trails, resolved)
	return resolved
end

local function layTrail(handle: TrailHandle, centre: Vector3, halfWidth: number): ()
	handle.a0.WorldPosition = centre + UP * halfWidth
	handle.a1.WorldPosition = centre - UP * halfWidth
end

local function giveTrail(handle: TrailHandle): ()
	handle.trail.Enabled = false
	handle.trail:Clear()
	if #trailPool < TRAIL_POOL_MAX then
		table.insert(trailPool, handle)
		return
	end
	handle.trail:Destroy()
	handle.a0:Destroy()
	handle.a1:Destroy()
end

-- Low-end devices get no lights at all (nil), and every caller accepts that.
local function takeLight(kit: Kit, color: Color3, range: number): LightHandle?
	if lowEnd then
		return nil
	end
	local handle = table.remove(lightPool)
	if handle == nil then
		local attachment = newAttachment("Light")
		local light = Create("PointLight", {
			Shadows = false,
			Brightness = 0,
			Parent = attachment,
		}) :: PointLight
		handle = { attachment = attachment, light = light }
	end
	local resolved = handle :: LightHandle
	resolved.light.Color = color
	resolved.light.Range = range
	resolved.light.Brightness = 0
	resolved.light.Enabled = true
	table.insert(kit.lights, resolved)
	return resolved
end

local function lightAt(handle: LightHandle?, position: Vector3, brightness: number): ()
	if handle == nil then
		return
	end
	handle.attachment.WorldPosition = position
	handle.light.Brightness = math.max(brightness, 0)
end

local function giveLight(handle: LightHandle): ()
	handle.light.Brightness = 0
	handle.light.Enabled = false
	if #lightPool < LIGHT_POOL_MAX then
		table.insert(lightPool, handle)
		return
	end
	handle.attachment:Destroy()
end

local function releaseKit(kit: Kit): ()
	for _, part in kit.parts do
		givePart(part)
	end
	for _, handle in kit.beams do
		giveBeam(handle)
	end
	for _, handle in kit.emitters do
		giveEmitter(handle)
	end
	for _, handle in kit.trails do
		giveTrail(handle)
	end
	for _, handle in kit.lights do
		giveLight(handle)
	end
	table.clear(kit.parts)
	table.clear(kit.beams)
	table.clear(kit.emitters)
	table.clear(kit.trails)
	table.clear(kit.lights)
end

-- Drawing ---------------------------------------------------------------------------------

local function place(part: BasePart, frame: CFrame): ()
	table.insert(moveParts, part)
	table.insert(moveFrames, frame)
end

-- `base` transparency at full visibility, scaled toward invisible as v falls to 0.
local function visibleAs(base: number, v: number): number
	if v <= 0 then
		return 1
	end
	return 1 - (1 - base) * math.min(v, 1)
end

local function show(part: BasePart, base: number, v: number): ()
	local value = visibleAs(base, v)
	if math.abs(part.Transparency - value) > 1e-3 then
		part.Transparency = value
	end
end

local function showAll(parts: { BasePart }, base: number, v: number): ()
	local value = visibleAs(base, v)
	for _, part in parts do
		if math.abs(part.Transparency - value) > 1e-3 then
			part.Transparency = value
		end
	end
end

local function layBeam(handle: BeamHandle, from: Vector3, to: Vector3): ()
	handle.a0.WorldPosition = from
	handle.a1.WorldPosition = to
end

local function showBeam(handle: BeamHandle, base: number, v: number): ()
	local value = visibleAs(base, v)
	if math.abs(handle.shown - value) > 1e-3 then
		handle.beam.Transparency = NumberSequence.new(value)
		handle.shown = value
	end
end

local function widenBeam(handle: BeamHandle, width: number): ()
	if math.abs(handle.beam.Width0 - width) > 1e-3 then
		handle.beam.Width0 = width
		handle.beam.Width1 = width
	end
end

-- Lays `parts` end to end along the circle of `radius` around `centre` in the plane (u, v), from
-- angle `from` to `to` (radians). The centreline runs on the circle, as Feedback's hitbox rings do,
-- so an outline of radius r is the shape's radius r. Sizes are written only when `resize`.
local function layCircle(
	parts: { BasePart },
	centre: Vector3,
	u: Vector3,
	v: Vector3,
	radius: number,
	from: number,
	to: number,
	width: number,
	height: number,
	resize: boolean
): ()
	local count = #parts
	if count == 0 or math.abs(to - from) < EPSILON then
		return
	end
	local r = math.max(radius, MIN_RADIUS)
	local step = (to - from) / count
	local normal = v:Cross(u)
	local length = 2 * r * math.abs(math.sin(step / 2)) + width * JOINT_OVERLAP
	for index, part in parts do
		local a = from + step * (index - 1)
		local b = a + step
		local pa = centre + (u * math.cos(a) + v * math.sin(a)) * r
		local pb = centre + (u * math.cos(b) + v * math.sin(b)) * r
		if resize then
			part.Size = Vector3.new(width, height, length)
		end
		place(part, CFrame.lookAt((pa + pb) / 2, pb, normal))
	end
end

local function layBar(part: BasePart, a: Vector3, b: Vector3, width: number, up: Vector3): ()
	local frame, length = barFrame(a, b, up)
	part.Size = Vector3.new(width, width, math.max(length, MIN_SIZE))
	place(part, frame)
end

local function layBall(part: BasePart, centre: Vector3, diameter: number): ()
	part.Size = Vector3.one * math.max(diameter, MIN_SIZE)
	place(part, CFrame.new(centre))
end

-- A flat disc of `radius` (a standing Cylinder), placed once.
local function layDisc(part: BasePart, centre: Vector3, radius: number): ()
	part.Size = Vector3.new(DISC_THICKNESS, radius * 2, radius * 2)
	place(part, CFrame.new(centre) * STAND_UP)
end

-- Short radial bars just inside a circle's edge, like a reticle's notches.
local function layNotches(parts: { BasePart }, centre: Vector3, radius: number, length: number): ()
	for index, part in parts do
		local angle = TAU * (index - 1) / #parts + math.pi / 4
		local outer = centre + around(angle) * radius
		local inner = centre + around(angle) * math.max(radius - length, 0)
		local frame, span = barFrame(inner, outer, UP)
		part.Size = Vector3.new(RING_WIDTH, RING_HEIGHT, math.max(span, MIN_SIZE))
		place(part, frame)
	end
end

-- A filled triangle from two wedges (the standard right-triangle split, as Feedback draws its
-- arcs). Sized now; the frames are returned so a caller can move the triangle with the caster.
local function triangle(kit: Kit, a: Vector3, b: Vector3, c: Vector3, color: Color3): { Placed }
	local placed: { Placed } = {}
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- Relabel so bc is the longest edge; the split point then lies inside it.
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < EPSILON or bc.Magnitude < EPSILON then
		return placed
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local first = takeWedge(kit, color)
	first.Size = Vector3.new(SECTOR_THICKNESS, height, math.abs(ab:Dot(back)))
	table.insert(placed, { part = first, frame = CFrame.fromMatrix((a + b) / 2, right, up, back) })
	local second = takeWedge(kit, color)
	second.Size = Vector3.new(SECTOR_THICKNESS, height, math.abs(ac:Dot(back)))
	table.insert(
		placed,
		{ part = second, frame = CFrame.fromMatrix((a + c) / 2, -right, up, -back) }
	)
	return placed
end

-- Dust thrown up and out all round a ring (Earthquake rings, Leap Smash landing).
local function dustRing(
	handle: EmitterHandle,
	centre: Vector3,
	radius: number,
	points: number,
	perPoint: number
): ()
	for index = 1, points do
		local outward = around(TAU * (index - 1) / points)
		local rise = (outward + UP * DUST_RISE).Unit
		local frame = CFrame.fromMatrix(
			centre + outward * radius,
			tangentOf(TAU * (index - 1) / points),
			rise
		)
		emitAt(handle, frame, perPoint)
	end
end

-- Whether a zone's tick strike belongs to the zone centred at `centre` (its capsule or sphere
-- starts at the zone's ground point).
local function isZoneStrike(strike: AbilityStrike, centre: Vector3): boolean
	local offset = strike.origin - centre
	return strike.tick and Vector3.new(offset.X, 0, offset.Z).Magnitude <= STRIKE_MATCH_STUDS
end

-- Abilities ---------------------------------------------------------------------------------

-- Whirlwind: three crescent slashes spin around the caster with their outer edge exactly at
-- `range`, the same ring lies on the floor under them, and streaks whip round inside. Follows
-- the caster every frame for durationSeconds; every tick flashes the floor ring.
local function buildWhirlwind(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local range = positive(def.range)
	local duration = positive(def.durationSeconds)
	if range == nil or duration == nil then
		return nil, nil
	end
	local reach: number = range
	local finish = duration + WHIRL_FADE_SECONDS
	local segmentAngle = math.rad(WHIRL_BLADE_DEGREES) / WHIRL_BLADE_SEGMENTS
	local widths: { number } = {}
	local bases: { number } = {}
	local radii: { number } = {}
	for index = 1, WHIRL_BLADE_SEGMENTS do
		local share = (index - 1) / math.max(WHIRL_BLADE_SEGMENTS - 1, 1)
		local width = math.min(lerp(WHIRL_BLADE_HEAD_WIDTH, WHIRL_BLADE_TAIL_WIDTH, share), reach)
		widths[index] = width
		bases[index] = lerp(WHIRL_BLADE_HEAD_TRANSPARENCY, WHIRL_BLADE_TAIL_TRANSPARENCY, share)
		-- The blade's outer edge is the reach: the slash ends exactly where the hit does.
		radii[index] = math.max(reach - width / 2, MIN_RADIUS)
	end
	local blades: { { BasePart } } = {}
	for _ = 1, WHIRL_BLADES do
		local parts = takeParts(
			kit,
			WHIRL_BLADE_SEGMENTS,
			Enum.PartType.Block,
			WHIRL_COLOR,
			Enum.Material.Neon
		)
		for index, part in parts do
			local chord = 2 * radii[index] * math.sin(segmentAngle / 2)
			part.Size = Vector3.new(
				widths[index],
				WHIRL_BLADE_HEIGHT,
				chord + widths[index] * JOINT_OVERLAP
			)
		end
		table.insert(blades, parts)
	end
	local ground =
		takeParts(kit, ringSegments(), Enum.PartType.Block, WHIRL_GLOW, Enum.Material.Neon)
	local rng = Random.new(cast.seq)
	local function respawn(streak: Streak, t: number): ()
		streak.born = t
		streak.radius = reach * rng:NextNumber(WHIRL_STREAK_MIN_SHARE, WHIRL_STREAK_MAX_SHARE)
		streak.angle = rng:NextNumber(0, TAU)
		streak.lift = rng:NextNumber(-WHIRL_STREAK_LIFT, WHIRL_STREAK_LIFT)
	end
	local fill: BasePart? = nil
	local streaks: { Streak } = {}
	if not lowEnd then
		local disc = takePart(kit, Enum.PartType.Cylinder, WHIRL_GLOW, Enum.Material.Neon)
		disc.Size = Vector3.new(DISC_THICKNESS, reach * 2, reach * 2)
		fill = disc
		for _ = 1, WHIRL_STREAKS do
			local part = takePart(kit, Enum.PartType.Block, WHIRL_COLOR, Enum.Material.Neon)
			part.Size = Vector3.new(WHIRL_STREAK_WIDTH, WHIRL_STREAK_WIDTH, WHIRL_STREAK_LENGTH)
			local streak: Streak = { part = part, radius = 0, angle = 0, lift = 0, born = 0 }
			-- Staggered births, so the streaks never all respawn on one frame.
			respawn(streak, -rng:NextNumber(0, WHIRL_STREAK_SECONDS))
			table.insert(streaks, streak)
		end
	end
	local centre = cast.origin
	local floorY = cast.origin.Y - rootHeightOf(cast.userId)
	local pulse = 0
	local sized = false
	-- Built once and rebuilt only when the caster respawns: the probe starts inside the caster,
	-- so their current character must always be excluded.
	local probe = worldParams()
	local _, _, probedCharacter = casterOf(cast.userId)

	local function step(t: number, dt: number): boolean
		if t >= finish then
			return false
		end
		local root, humanoid, character = casterOf(cast.userId)
		if root ~= nil then
			centre = root.Position
			if character ~= probedCharacter then
				probe = worldParams()
				probedCharacter = character
			end
			-- The ring stays on the real floor when the caster jumps mid-channel (ruling 3);
			-- the hip estimate is only the fallback over a void.
			local hit = Workspace:Raycast(centre, Vector3.new(0, -FLOOR_PROBE_DOWN, 0), probe)
			floorY = if hit ~= nil then hit.Position.Y else floorUnder(root, humanoid)
		end
		pulse = math.max(pulse - dt / PULSE_SECONDS, 0)
		local v = envelope(t, 0, finish, WHIRL_SPIN_UP_SECONDS, WHIRL_FADE_SECONDS)
		local floorCentre = Vector3.new(centre.X, floorY + LIFT, centre.Z)
		layCircle(
			ground,
			floorCentre,
			FLAT_U,
			FLAT_V,
			reach,
			0,
			TAU,
			RING_WIDTH,
			RING_HEIGHT,
			not sized
		)
		sized = true
		showAll(ground, RING_TRANSPARENCY * (1 - pulse), v)
		local spin = t * WHIRL_SPIN
		for bladeIndex, parts in blades do
			local head = spin + TAU * (bladeIndex - 1) / #blades
			for index, part in parts do
				local angle = head - segmentAngle * (index - 1)
				local a = centre + around(angle) * radii[index]
				local b = centre + around(angle - segmentAngle) * radii[index]
				place(part, CFrame.lookAt((a + b) / 2, b))
				show(part, bases[index], v)
			end
		end
		for _, streak in streaks do
			local age = t - streak.born
			if age >= WHIRL_STREAK_SECONDS then
				respawn(streak, t)
				age = 0
			end
			local angle = streak.angle + age * WHIRL_SPIN * WHIRL_STREAK_SPEED
			local point = centre + around(angle) * streak.radius + UP * streak.lift
			place(streak.part, CFrame.lookAt(point, point + tangentOf(angle)))
			local life = math.sin(math.pi * age / WHIRL_STREAK_SECONDS)
			show(streak.part, WHIRL_STREAK_TRANSPARENCY, v * life)
		end
		local disc = fill
		if disc ~= nil then
			place(disc, CFrame.new(centre) * STAND_UP)
			show(disc, lerp(WHIRL_FILL_TRANSPARENCY, FILL_PULSE_TRANSPARENCY, pulse), v)
		end
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if not strike.tick then
			return false
		end
		pulse = 1
		return true
	end

	return step, onStrike
end

-- Earthquake: a slam flash and crater at the floor centre, then a dust front that steps out and
-- lands on ring k exactly at delaySeconds + (k−1)·tickSeconds with radius radius + (k−1)·spacing.
-- Each ring flashes its exact radius as it lands (with a dust burst), and glowing cracks open
-- behind the front and linger. Feedback draws each ring's sphere strike on top.
local function buildEarthquake(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local count = positive(def.count)
	local radius = nonNegative(def.radius)
	local tick = nonNegative(def.tickSeconds)
	if delay == nil or count == nil or radius == nil or tick == nil then
		return nil, nil
	end
	local rings = math.min(math.floor(count), QUAKE_MAX_RINGS)
	if rings < 1 then
		return nil, nil
	end
	local spacing = def.spacing or 0
	local centre = groundOf(cast)
	local times: { number } = {}
	local radii: { number } = {}
	local outer = 0
	for ring = 1, rings do
		times[ring] = delay + (ring - 1) * tick
		radii[ring] = math.max(radius + (ring - 1) * spacing, 0)
		outer = math.max(outer, radii[ring])
	end
	local last = times[rings]
	local finish = last + QUAKE_CRACK_HOLD + QUAKE_CRACK_FADE
	local segments = bigSegments()

	local front =
		takeParts(kit, segments, Enum.PartType.Block, DUST_COLOR, Enum.Material.SmoothPlastic)
	local marks: { { BasePart } } = {}
	for ring = 1, rings do
		local parts =
			takeParts(kit, segments, Enum.PartType.Block, QUAKE_MARK_COLOR, Enum.Material.Neon)
		layCircle(
			parts,
			centre,
			FLAT_U,
			FLAT_V,
			radii[ring],
			0,
			TAU,
			QUAKE_MARK_WIDTH,
			RING_HEIGHT,
			true
		)
		table.insert(marks, parts)
	end

	local cracks: { Crack } = {}
	local rng = Random.new(cast.seq)
	local crackCount = if lowEnd then QUAKE_CRACKS_LOW_END else QUAKE_CRACKS
	for index = 1, crackCount do
		local angle = TAU * (index - 1) / crackCount
			+ rng:NextNumber(-QUAKE_CRACK_JITTER, QUAKE_CRACK_JITTER)
		local reach = QUAKE_CRACK_START
		local from = centre + around(angle) * reach
		while reach < outer - EPSILON do
			local nextReach = math.min(reach + QUAKE_CRACK_STEP, outer)
			angle += rng:NextNumber(-QUAKE_CRACK_JITTER, QUAKE_CRACK_JITTER)
			local to = centre + around(angle) * nextReach
			local part = takePart(kit, Enum.PartType.Block, QUAKE_CRACK_COLOR, Enum.Material.Neon)
			local width = lerp(QUAKE_CRACK_WIDTH, QUAKE_CRACK_TIP_WIDTH, nextReach / outer)
			local frame, length = barFrame(from, to, UP)
			part.Size = Vector3.new(width, QUAKE_CRACK_HEIGHT, length + width * JOINT_OVERLAP)
			place(part, frame)
			table.insert(cracks, { part = part, reach = nextReach })
			from = to
			reach = nextReach
		end
	end

	local crater =
		takePart(kit, Enum.PartType.Cylinder, QUAKE_CRATER_COLOR, Enum.Material.SmoothPlastic)
	layDisc(crater, centre, QUAKE_CRATER_SIZE / 2)
	local slam = takePart(kit, Enum.PartType.Ball, QUAKE_CRACK_COLOR, Enum.Material.Neon)
	local dust = takeEmitter(kit, DUST_STYLE, DUST_COLOR)
	local landed = 0

	-- The front waits at the last ring and races out to the next one in the QUAKE_EXPAND_SECONDS
	-- before it lands, so each ring reads as its own thump.
	local function frontRadius(t: number): number
		for ring = 1, rings do
			if t < times[ring] then
				local fromRadius = if ring == 1 then 0 else radii[ring - 1]
				local gap = times[ring] - (if ring == 1 then 0 else times[ring - 1])
				local window = math.min(QUAKE_EXPAND_SECONDS, gap)
				if window <= 0 then
					return fromRadius
				end
				local u = clamp01((t - (times[ring] - window)) / window)
				return lerp(fromRadius, radii[ring], easeOut(u))
			end
		end
		return radii[rings]
	end

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			return false
		end
		while landed < rings and t >= times[landed + 1] do
			landed += 1
			if t - times[landed] < FRESH_SECONDS then
				dustRing(
					dust,
					centre,
					radii[landed],
					particles(QUAKE_DUST_POINTS),
					particles(QUAKE_DUST_PER_POINT)
				)
			end
		end
		local reach = frontRadius(t)
		local frontV = if reach < QUAKE_FRONT_MIN_RADIUS
			then 0
			elseif t <= last then 1
			else 1 - clamp01((t - last) / QUAKE_FRONT_FADE)
		if frontV > 0 then
			local height = QUAKE_FRONT_HEIGHT * lerp(QUAKE_FRONT_SETTLE, 1, frontV)
			layCircle(
				front,
				centre + UP * (height / 2),
				FLAT_U,
				FLAT_V,
				reach,
				0,
				TAU,
				QUAKE_FRONT_WIDTH,
				height,
				true
			)
		end
		showAll(front, QUAKE_FRONT_TRANSPARENCY, frontV)
		for ring, parts in marks do
			local age = t - times[ring]
			local v = if age < 0 then 0 else 1 - clamp01(age / QUAKE_MARK_SECONDS)
			showAll(parts, QUAKE_MARK_TRANSPARENCY, v)
		end
		local crackV = 1 - clamp01((t - last - QUAKE_CRACK_HOLD) / QUAKE_CRACK_FADE)
		for _, crack in cracks do
			show(crack.part, QUAKE_CRACK_TRANSPARENCY, if reach >= crack.reach then crackV else 0)
		end
		show(crater, QUAKE_CRATER_TRANSPARENCY, crackV)
		local grow = if delay > 0 then clamp01(t / delay) else 1
		layBall(slam, centre, QUAKE_SLAM_SIZE * easeOut(grow))
		show(slam, QUAKE_SLAM_TRANSPARENCY, 1 - clamp01((t - delay) / QUAKE_SLAM_FADE))
		return true
	end

	return step, nil
end

local function placeShuriken(arms: { BasePart }, position: Vector3, spin: number): ()
	for index, arm in arms do
		place(arm, CFrame.new(position) * CFrame.Angles(0, spin + math.pi * (index - 1) / #arms, 0))
	end
end

local function takeShuriken(kit: Kit, arms: number, length: number): { BasePart }
	local parts = takeParts(kit, arms, Enum.PartType.Block, STORM_BLADE_COLOR, Enum.Material.Neon)
	for _, part in parts do
		part.Size = Vector3.new(STORM_ARM_WIDTH, STORM_ARM_THICKNESS, length)
	end
	return parts
end

-- Blade Storm: a spinning blade arcs from the caster's hand to the ground point over
-- delaySeconds, then the exact circle of `radius` holds for durationSeconds while blades spiral
-- from its rim into a glowing eye and motes stream inward (the pull). Ticks pulse the circle.
local function buildBladeStorm(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local radius = positive(def.radius)
	local duration = positive(def.durationSeconds)
	if delay == nil or radius == nil or duration == nil then
		return nil, nil
	end
	local reach: number = radius
	local centre = groundOf(cast)
	local zoneEnd = delay + duration
	local finish = zoneEnd + ZONE_FADE_OUT
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local start = muzzleOf(cast.userId, aim, cast.origin)
	local landing = centre + UP * STORM_BLADE_HIGH

	local thrown = takeShuriken(kit, STORM_THROW_ARMS, STORM_THROW_ARM_LENGTH)
	local trail = takeTrail(kit, STORM_COLOR, STORM_TRAIL_SECONDS, start, STORM_TRAIL_HALF)
	local ring =
		takeParts(kit, ringSegments(), Enum.PartType.Block, STORM_COLOR, Enum.Material.Neon)
	layCircle(ring, centre, FLAT_U, FLAT_V, reach, 0, TAU, RING_WIDTH, RING_HEIGHT, true)
	local fill: BasePart? = nil
	if not lowEnd then
		local disc = takePart(kit, Enum.PartType.Cylinder, STORM_COLOR, Enum.Material.Neon)
		layDisc(disc, centre, reach)
		fill = disc
	end
	local vortex: { { BasePart } } = {}
	for _ = 1, if lowEnd then STORM_VORTEX_BLADES_LOW_END else STORM_VORTEX_BLADES do
		table.insert(vortex, takeShuriken(kit, STORM_VORTEX_ARMS, STORM_VORTEX_ARM_LENGTH))
	end
	local eye = takePart(kit, Enum.PartType.Ball, STORM_COLOR, Enum.Material.Neon)
	local eyePoint = centre + UP * STORM_EYE_HEIGHT
	local suction = takeEmitter(kit, MOTE_STYLE, STORM_COLOR)
	suction.emitter.Speed = NumberRange.new(reach / MOTE_LIFETIME)
	local rng = Random.new(cast.seq)
	local budget = 0
	local pulse = 0

	local function step(t: number, dt: number): boolean
		if t >= finish then
			return false
		end
		pulse = math.max(pulse - dt / PULSE_SECONDS, 0)
		if t < delay then
			local u = t / delay
			local position = start:Lerp(landing, u) + UP * (STORM_THROW_ARC * 4 * u * (1 - u))
			placeShuriken(thrown, position, t * STORM_THROW_SPIN)
			showAll(thrown, 0, 1)
			layTrail(trail, position, STORM_TRAIL_HALF)
		else
			showAll(thrown, 0, 0)
		end
		local zoneV = envelope(t, delay, finish, ZONE_FADE_IN, ZONE_FADE_OUT)
		showAll(ring, RING_TRANSPARENCY * (1 - pulse), zoneV)
		local disc = fill
		if disc ~= nil then
			show(disc, lerp(FILL_TRANSPARENCY, FILL_PULSE_TRANSPARENCY, pulse), zoneV)
		end
		local age = t - delay
		for index, arms in vortex do
			if zoneV <= 0 then
				showAll(arms, 0, 0)
				continue
			end
			local phase = (index - 1) / #vortex
			local cycle = (age * STORM_INWARD_RATE + phase) % 1
			local angle = TAU * phase + age * STORM_SPIN + STORM_SWIRL * cycle
			local height = lerp(STORM_BLADE_LOW, STORM_BLADE_HIGH, cycle)
			local position = centre + around(angle) * (reach * (1 - cycle)) + UP * height
			placeShuriken(arms, position, age * STORM_BLADE_SPIN)
			local edge = math.min(cycle, 1 - cycle) / STORM_EDGE_SHARE
			showAll(arms, 0, zoneV * clamp01(edge))
		end
		local throb = 1 + 0.25 * math.sin(age * STORM_EYE_THROB) + 0.5 * pulse
		layBall(eye, eyePoint, STORM_EYE_SIZE * throb)
		show(eye, STORM_EYE_TRANSPARENCY, zoneV)
		if t >= delay and t < zoneEnd then
			budget = math.min(budget + rate(STORM_SUCTION_RATE) * dt, MAX_EMIT_BUDGET)
			while budget >= 1 do
				budget -= 1
				local from = centre
					+ around(rng:NextNumber(0, TAU)) * reach
					+ UP * rng:NextNumber(STORM_BLADE_LOW, STORM_BLADE_HIGH)
				local toward = unitOf(eyePoint - from)
				if toward ~= nil then
					emitAt(suction, frameAlong(from, toward), 1)
				end
			end
		end
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if not isZoneStrike(strike, centre) then
			return false
		end
		pulse = 1
		return true
	end

	return step, onStrike
end

-- Leap Smash: from the cast, the exact landing circle of `radius` at the ground point blinks
-- faster while a second ring fills out to meet it at delaySeconds, and a trail follows the
-- caster's root. At delaySeconds: dust bursts round the circle, a dust ring rolls out to the
-- radius, debris flies and a light flashes. Feedback draws the landing sphere strike.
local function buildLeapSmash(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local radius = positive(def.radius)
	if delay == nil or radius == nil then
		return nil, nil
	end
	local reach: number = radius
	local centre = groundOf(cast)
	local finish = delay + LEAP_TAIL
	local marker =
		takeParts(kit, ringSegments(), Enum.PartType.Block, LEAP_COLOR, Enum.Material.Neon)
	layCircle(marker, centre, FLAT_U, FLAT_V, reach, 0, TAU, RING_WIDTH, RING_HEIGHT, true)
	local filling =
		takeParts(kit, ringSegments(), Enum.PartType.Block, LEAP_COLOR, Enum.Material.Neon)
	local fill: BasePart? = nil
	local notches: { BasePart } = {}
	if not lowEnd then
		local disc = takePart(kit, Enum.PartType.Cylinder, LEAP_COLOR, Enum.Material.Neon)
		layDisc(disc, centre, reach)
		fill = disc
		notches = takeParts(kit, LEAP_NOTCHES, Enum.PartType.Block, LEAP_COLOR, Enum.Material.Neon)
		layNotches(notches, centre, reach, LEAP_NOTCH_LENGTH)
	end
	local dustWall =
		takeParts(kit, bigSegments(), Enum.PartType.Block, DUST_COLOR, Enum.Material.SmoothPlastic)
	local dust = takeEmitter(kit, DUST_STYLE, DUST_COLOR)
	local light = takeLight(kit, LEAP_COLOR, reach * 2)
	local rng = Random.new(cast.seq)
	local chunks: { Chunk } = {}
	if not lowEnd then
		for _ = 1, LEAP_DEBRIS do
			local part = takePart(kit, Enum.PartType.Block, DUST_COLOR, Enum.Material.SmoothPlastic)
			part.Size = Vector3.one * rng:NextNumber(LEAP_DEBRIS_SIZE_MIN, LEAP_DEBRIS_SIZE_MAX)
			local outward = around(rng:NextNumber(0, TAU))
			table.insert(chunks, {
				part = part,
				velocity = outward * rng:NextNumber(LEAP_DEBRIS_OUT_MIN, LEAP_DEBRIS_OUT_MAX)
					+ UP * rng:NextNumber(LEAP_DEBRIS_UP_MIN, LEAP_DEBRIS_UP_MAX),
				spin = rng:NextUnitVector() * LEAP_DEBRIS_SPIN,
			})
		end
	end
	local root = casterOf(cast.userId)
	local trail = takeTrail(
		kit,
		LEAP_COLOR,
		LEAP_TRAIL_SECONDS,
		if root ~= nil then root.Position else cast.origin,
		LEAP_TRAIL_HALF
	)
	local landed = false

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			return false
		end
		if t < delay then
			local u = t / delay
			-- The blink quickens as the landing nears.
			local blink = 0.5 + 0.5 * math.cos(t * LEAP_BLINK_RATE * (1 + 2 * u))
			showAll(marker, lerp(0.05, 0.35, blink), 1)
			layCircle(
				filling,
				centre,
				FLAT_U,
				FLAT_V,
				reach * u,
				0,
				TAU,
				RING_WIDTH,
				RING_HEIGHT,
				true
			)
			showAll(filling, LEAP_FILL_RING_TRANSPARENCY, if reach * u > RING_WIDTH then 1 else 0)
			local disc = fill
			if disc ~= nil then
				show(disc, FILL_TRANSPARENCY, 1)
			end
			showAll(notches, RING_TRANSPARENCY, 1)
			local caster = casterOf(cast.userId)
			if caster ~= nil then
				layTrail(trail, caster.Position, LEAP_TRAIL_HALF)
			end
			return true
		end
		local age = t - delay
		if not landed then
			landed = true
			if age < FRESH_SECONDS then
				dustRing(dust, centre, reach * 0.6, particles(LEAP_DUST_POINTS), particles(2))
			end
		end
		local markerV = 1 - clamp01(age / LEAP_MARKER_FADE)
		showAll(marker, 0.05, markerV)
		showAll(filling, 0, 0)
		local disc = fill
		if disc ~= nil then
			show(disc, FILL_TRANSPARENCY, markerV)
		end
		showAll(notches, RING_TRANSPARENCY, markerV)
		local spread = easeOut(clamp01(age / LEAP_DUST_EXPAND))
		local dustV = 1 - clamp01((age - LEAP_DUST_EXPAND) / LEAP_DUST_FADE)
		if dustV > 0 and reach * spread > QUAKE_FRONT_MIN_RADIUS then
			local height = QUAKE_FRONT_HEIGHT * lerp(QUAKE_FRONT_SETTLE, 1, dustV)
			layCircle(
				dustWall,
				centre + UP * (height / 2),
				FLAT_U,
				FLAT_V,
				reach * spread,
				0,
				TAU,
				QUAKE_FRONT_WIDTH,
				height,
				true
			)
			showAll(dustWall, QUAKE_FRONT_TRANSPARENCY, dustV)
		else
			showAll(dustWall, 0, 0)
		end
		for _, chunk in chunks do
			if age >= LEAP_DEBRIS_SECONDS then
				show(chunk.part, 0, 0)
				continue
			end
			local position = centre
				+ chunk.velocity * age
				+ Vector3.new(0, -0.5 * LEAP_DEBRIS_GRAVITY * age * age, 0)
			local floor = centre.Y + chunk.part.Size.Y / 2
			position = Vector3.new(position.X, math.max(position.Y, floor), position.Z)
			local spin = chunk.spin * age
			place(chunk.part, CFrame.new(position) * CFrame.Angles(spin.X, spin.Y, spin.Z))
			show(chunk.part, 0, 1 - clamp01((age / LEAP_DEBRIS_SECONDS - 0.7) / 0.3))
		end
		lightAt(light, centre + UP, LEAP_LIGHT * (1 - clamp01(age / LEAP_LIGHT_SECONDS)))
		return true
	end

	return step, nil
end

-- Impale Dash: over delaySeconds a bright streak shoots from the cast root to the dash end
-- (the head keeps pace with the dash), flanked by two lines at ±width/2, the capsule's exact
-- edges. Afterimages of the caster's pose drop along the line as the head passes them. After
-- the dash the tail catches up and everything fades. Feedback draws the capsule strike itself.
local function buildImpaleDash(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local width = positive(def.width)
	if delay == nil or width == nil then
		return nil, nil
	end
	local from = cast.origin
	local heading = flatUnit(cast.direction) or Vector3.zAxis
	local range = positive(def.range)
	local to = cast.target or (if range ~= nil then from + heading * range else from)
	local line = to - from
	if line.Magnitude < EPSILON then
		return nil, nil
	end
	local side = heading:Cross(UP) * (width / 2)
	local finish = delay + math.max(DASH_COLLAPSE_SECONDS, DASH_AFTERIMAGE_SECONDS)
	local core = takeBeam(kit, DASH_CORE_COLOR, DASH_HEAD_WIDTH)
	core.beam.Width0 = DASH_TAIL_WIDTH
	local edges = {
		takeBeam(kit, DASH_COLOR, DASH_EDGE_WIDTH),
		takeBeam(kit, DASH_COLOR, DASH_EDGE_WIDTH),
	}

	local ghosts: { Ghost } = {}
	local root, _, character = casterOf(cast.userId)
	if root ~= nil and character ~= nil then
		local offsets: { CFrame } = {}
		local sizes: { Vector3 } = {}
		for _, child in character:GetChildren() do
			if child:IsA("BasePart") and child ~= root and #offsets < DASH_POSE_PARTS then
				table.insert(offsets, root.CFrame:ToObjectSpace(child.CFrame))
				table.insert(sizes, child.Size)
			end
		end
		local count = if lowEnd then DASH_AFTERIMAGES_LOW_END else DASH_AFTERIMAGES
		for index = 1, count do
			local share = (index - 0.5) / count
			local point = from + line * share
			local frame = CFrame.lookAt(point, point + heading)
			local parts =
				takeParts(kit, #offsets, Enum.PartType.Block, DASH_COLOR, Enum.Material.Neon)
			for part = 1, #offsets do
				parts[part].Size = sizes[part]
				place(parts[part], frame * offsets[part])
			end
			table.insert(ghosts, { parts = parts, born = share * delay })
		end
	end

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			return false
		end
		local u = if delay > 0 then clamp01(t / delay) else 1
		local collapse = if t <= delay then 0 else clamp01((t - delay) / DASH_COLLAPSE_SECONDS)
		local head = from + line * u
		local tail = from + line * collapse
		local v = 1 - collapse
		layBeam(core, tail, head)
		core.beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, visibleAs(DASH_TAIL_TRANSPARENCY, v)),
			NumberSequenceKeypoint.new(1, visibleAs(DASH_HEAD_TRANSPARENCY, v)),
		})
		for index, edge in edges do
			local offset = if index == 1 then side else -side
			layBeam(edge, tail + offset, head + offset)
			showBeam(edge, DASH_EDGE_TRANSPARENCY, v)
		end
		for _, ghost in ghosts do
			local age = t - ghost.born
			local ghostV = if age < 0 then 0 else 1 - clamp01(age / DASH_AFTERIMAGE_SECONDS)
			showAll(ghost.parts, DASH_AFTERIMAGE_TRANSPARENCY, ghostV)
		end
		return true
	end

	return step, nil
end

-- Arrow Rain: from the cast, the exact circle of `radius` blinks at the ground point while a
-- lock-on ring closes onto it; from delaySeconds to delaySeconds + durationSeconds arrows streak
-- down into it (landing points uniform over the disc), stick for a moment and fade. Ticks pulse
-- the circle.
local function buildArrowRain(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local radius = positive(def.radius)
	local delay = nonNegative(def.delaySeconds)
	local duration = positive(def.durationSeconds)
	if radius == nil or delay == nil or duration == nil then
		return nil, nil
	end
	local reach: number = radius
	local centre = groundOf(cast)
	local zoneEnd = delay + duration
	local finish = zoneEnd + RAIN_STICK_SECONDS + RAIN_FADE_SECONDS
	local ring = takeParts(kit, ringSegments(), Enum.PartType.Block, RAIN_COLOR, Enum.Material.Neon)
	layCircle(ring, centre, FLAT_U, FLAT_V, reach, 0, TAU, RING_WIDTH, RING_HEIGHT, true)
	local fill: BasePart? = nil
	local lock: { BasePart } = {}
	local notches: { BasePart } = {}
	if not lowEnd then
		local disc = takePart(kit, Enum.PartType.Cylinder, RAIN_COLOR, Enum.Material.Neon)
		layDisc(disc, centre, reach)
		fill = disc
		lock = takeParts(kit, ringSegments(), Enum.PartType.Block, RAIN_COLOR, Enum.Material.Neon)
		notches = takeParts(kit, RAIN_NOTCHES, Enum.PartType.Block, RAIN_COLOR, Enum.Material.Neon)
		layNotches(notches, centre, reach, RAIN_NOTCH_LENGTH)
	end

	local perSecond = if lowEnd then RAIN_ARROWS_PER_SECOND_LOW_END else RAIN_ARROWS_PER_SECOND
	local total = math.max(math.round(duration * perSecond), 1)
	local rng = Random.new(cast.seq)
	local landings: { Vector3 } = {}
	local landTimes: { number } = {}
	for index = 1, total do
		local distance = reach * math.sqrt(rng:NextNumber())
		landings[index] = centre + around(rng:NextNumber(0, TAU)) * distance
		landTimes[index] = delay + duration * (index - 0.5) / total
	end
	local toward = flatUnit(centre - cast.origin) or flatUnit(cast.direction) or Vector3.zAxis
	local fall = (toward * RAIN_SLANT - UP).Unit
	local life = RAIN_FALL_SECONDS + RAIN_STICK_SECONDS + RAIN_FADE_SECONDS
	-- Arrows in the air or stuck at once, plus slack: the slots are reused round-robin.
	local slots = math.ceil(life * total / duration) + 2
	local shafts = takeParts(kit, slots, Enum.PartType.Block, RAIN_ARROW_COLOR, Enum.Material.Neon)
	local streaks = takeParts(kit, slots, Enum.PartType.Block, RAIN_COLOR, Enum.Material.Neon)
	for slot = 1, slots do
		shafts[slot].Size = Vector3.new(RAIN_ARROW_WIDTH, RAIN_ARROW_WIDTH, RAIN_ARROW_LENGTH)
		streaks[slot].Size = Vector3.new(RAIN_STREAK_WIDTH, RAIN_STREAK_WIDTH, RAIN_STREAK_LENGTH)
	end
	local owned: { boolean } = table.create(slots, false)
	local sparks = takeEmitter(kit, SPARK_STYLE, RAIN_COLOR)
	local first = 1
	local landed = 0
	local pulse = 0

	local function step(t: number, dt: number): boolean
		if t >= finish then
			return false
		end
		pulse = math.max(pulse - dt / PULSE_SECONDS, 0)
		local circleV = envelope(t, 0, zoneEnd + ZONE_FADE_OUT, ZONE_FADE_IN, ZONE_FADE_OUT)
		local base = if t < delay
			then lerp(RAIN_BLINK_LOW, RAIN_BLINK_HIGH, 0.5 + 0.5 * math.cos(t * RAIN_BLINK_RATE))
			else RAIN_BLINK_LOW + (RING_TRANSPARENCY - RAIN_BLINK_LOW) * (1 - pulse)
		showAll(ring, base, circleV)
		local disc = fill
		if disc ~= nil then
			show(disc, lerp(FILL_TRANSPARENCY, FILL_PULSE_TRANSPARENCY, pulse), circleV)
		end
		showAll(notches, RING_TRANSPARENCY, circleV)
		if #lock > 0 then
			if t < delay then
				local closing = lerp(RAIN_LOCK_FROM, 1, easeOut(t / delay))
				layCircle(
					lock,
					centre,
					FLAT_U,
					FLAT_V,
					reach * closing,
					0,
					TAU,
					RING_WIDTH,
					RING_HEIGHT,
					true
				)
				showAll(lock, RAIN_LOCK_TRANSPARENCY, 1)
			else
				showAll(lock, 0, 0)
			end
		end

		while first <= total and t >= landTimes[first] + RAIN_STICK_SECONDS + RAIN_FADE_SECONDS do
			first += 1
		end
		for index = first, total do
			local land = landTimes[index]
			if t < land - RAIN_FALL_SECONDS then
				break
			end
			local slot = (index - 1) % slots + 1
			owned[slot] = true
			local point = landings[index]
			local shaft = shafts[slot]
			local streak = streaks[slot]
			if t < land then
				local tip = point - fall * (RAIN_FALL_SPEED * (land - t))
				place(shaft, CFrame.lookAt(tip - fall * (RAIN_ARROW_LENGTH / 2), tip))
				show(shaft, 0, 1)
				local tail = tip - fall * (RAIN_ARROW_LENGTH + RAIN_STREAK_LENGTH / 2)
				place(streak, CFrame.lookAt(tail, tip))
				show(streak, RAIN_STREAK_TRANSPARENCY, 1)
			else
				local tip = point + fall * RAIN_SINK
				place(shaft, CFrame.lookAt(tip - fall * (RAIN_ARROW_LENGTH / 2), tip))
				local gone = land + RAIN_STICK_SECONDS + RAIN_FADE_SECONDS
				show(shaft, 0, clamp01((gone - t) / RAIN_FADE_SECONDS))
				show(streak, 0, 0)
			end
		end
		for slot = 1, slots do
			if not owned[slot] then
				show(shafts[slot], 0, 0)
				show(streaks[slot], 0, 0)
			end
			owned[slot] = false
		end
		while landed < total and t >= landTimes[landed + 1] do
			landed += 1
			if t - landTimes[landed] < FRESH_SECONDS then
				emitAt(sparks, frameAlong(landings[landed], UP), particles(RAIN_SPARKS))
			end
		end
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if not isZoneStrike(strike, centre) then
			return false
		end
		pulse = 1
		return true
	end

	return step, onStrike
end

-- Volley: at the cast, a gold flash at the bow with a fan of streaks across arcDegrees (one per
-- arrow, up to the split cap), a ring snapping out round the aim, sparks and a light. Feedback
-- flies the arrows themselves.
local function buildVolley(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local count = positive(def.count)
	local arcDegrees = nonNegative(def.arcDegrees)
	if count == nil or arcDegrees == nil then
		return nil, nil
	end
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local right, up = basis(aim)
	local muzzle = muzzleOf(cast.userId, aim, cast.origin)
	local fan = math.clamp(math.floor(count), 1, VOLLEY_MAX_STREAKS)
	if lowEnd then
		fan = math.max(math.ceil(fan / 2), 1)
	end
	local spread = math.rad(arcDegrees)
	local directions: { Vector3 } = {}
	for index = 1, fan do
		local angle = if fan > 1 then -spread / 2 + spread * (index - 1) / (fan - 1) else 0
		table.insert(directions, (aim * math.cos(angle) + right * math.sin(angle)).Unit)
	end
	local streaks = takeParts(kit, fan, Enum.PartType.Block, VOLLEY_COLOR, Enum.Material.Neon)
	local flash = takePart(kit, Enum.PartType.Ball, VOLLEY_COLOR, Enum.Material.Neon)
	local ring: { BasePart } = {}
	if not lowEnd then
		ring = takeParts(
			kit,
			VOLLEY_RING_SEGMENTS,
			Enum.PartType.Block,
			VOLLEY_COLOR,
			Enum.Material.Neon
		)
	end
	local light = takeLight(kit, VOLLEY_COLOR, VOLLEY_LIGHT_RANGE)
	local sparks = takeEmitter(kit, SPARK_STYLE, VOLLEY_COLOR)
	local burst = false

	local function step(t: number, _dt: number): boolean
		if t >= VOLLEY_SECONDS then
			return false
		end
		if not burst then
			burst = true
			if t < FRESH_SECONDS then
				emitAt(sparks, frameAlong(muzzle, aim), particles(VOLLEY_SPARKS))
			end
		end
		local u = t / VOLLEY_SECONDS
		local grow = easeOut(clamp01(t / VOLLEY_GROW_SECONDS))
		local fade = 1 - clamp01((t - VOLLEY_GROW_SECONDS) / (VOLLEY_SECONDS - VOLLEY_GROW_SECONDS))
		for index, part in streaks do
			local direction = directions[index]
			local a = muzzle + direction * VOLLEY_STREAK_START
			layBar(part, a, a + direction * (VOLLEY_STREAK_LENGTH * grow), VOLLEY_STREAK_WIDTH, up)
			show(part, VOLLEY_STREAK_TRANSPARENCY, fade)
		end
		layBall(flash, muzzle, VOLLEY_FLASH_SIZE * (1 - easeOut(u)))
		show(flash, 0, 1 - u)
		if #ring > 0 then
			local spreadOut = lerp(VOLLEY_RING_FROM, VOLLEY_RING_TO, easeOut(u))
			layCircle(ring, muzzle, right, up, spreadOut, 0, TAU, RING_WIDTH, RING_WIDTH, true)
			showAll(ring, 0.1, 1 - u)
		end
		lightAt(light, muzzle, VOLLEY_LIGHT * (1 - u))
		return true
	end

	return step, nil
end

-- Slug Burst: a muzzle blast per slug at (k−1)·tickSeconds (count blasts): a flash, flare
-- streaks leaning out inside the cone's opening, smoke, sparks, an ejected shell and a light
-- kick. Feedback draws each slug's cone.
local function buildSlugBurst(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local count = positive(def.count)
	local tick = nonNegative(def.tickSeconds)
	local arcDegrees = nonNegative(def.arcDegrees)
	if count == nil or tick == nil or arcDegrees == nil then
		return nil, nil
	end
	local blasts = math.min(math.floor(count), SLUG_MAX_BLASTS)
	if blasts < 1 then
		return nil, nil
	end
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local right, up = basis(aim)
	local lean = math.rad(math.clamp(arcDegrees, 0, 179) / 2) * SLUG_STREAK_SHARE
	local streakCount = if lowEnd then SLUG_STREAKS_LOW_END else SLUG_STREAKS
	local directions: { Vector3 } = {}
	for index = 1, streakCount do
		local around3 = TAU * (index - 1) / streakCount
		local sideways = right * math.cos(around3) + up * math.sin(around3)
		table.insert(directions, (aim * math.cos(lean) + sideways * math.sin(lean)).Unit)
	end
	local list: { SlugBlast } = {}
	for index = 1, blasts do
		local casing: BasePart? = nil
		if not lowEnd then
			local shell =
				takePart(kit, Enum.PartType.Block, SLUG_CASING_COLOR, Enum.Material.SmoothPlastic)
			shell.Size = SLUG_CASING_SIZE
			casing = shell
		end
		table.insert(list, {
			flash = takePart(kit, Enum.PartType.Ball, SLUG_COLOR, Enum.Material.Neon),
			streaks = takeParts(
				kit,
				streakCount,
				Enum.PartType.Block,
				SLUG_COLOR,
				Enum.Material.Neon
			),
			casing = casing,
			muzzle = cast.origin,
			startsAt = (index - 1) * tick,
			casingVelocity = Vector3.zero,
			fired = false,
		})
	end
	local smoke = takeEmitter(kit, SMOKE_STYLE, SMOKE_COLOR)
	local sparks = takeEmitter(kit, SPARK_STYLE, SLUG_COLOR)
	local light = takeLight(kit, SLUG_COLOR, SLUG_LIGHT_RANGE)
	local rng = Random.new(cast.seq)
	local finish = (blasts - 1) * tick + math.max(SLUG_CASING_SECONDS, SLUG_FLASH_SECONDS)
	local lastMuzzle = cast.origin

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			return false
		end
		local brightest = 0
		for _, blast in list do
			local age = t - blast.startsAt
			if age < 0 then
				continue
			end
			if not blast.fired then
				blast.fired = true
				blast.muzzle = muzzleOf(cast.userId, aim, cast.origin)
				blast.casingVelocity = right
						* rng:NextNumber(SLUG_CASING_SIDE_MIN, SLUG_CASING_SIDE_MAX)
					+ UP * rng:NextNumber(SLUG_CASING_UP_MIN, SLUG_CASING_UP_MAX)
				if age < FRESH_SECONDS then
					local frame = frameAlong(blast.muzzle + aim * SLUG_FLASH_FORWARD, aim)
					emitAt(smoke, frame, particles(SLUG_SMOKE))
					emitAt(sparks, frame, particles(SLUG_SPARKS))
				end
			end
			lastMuzzle = blast.muzzle
			local u = clamp01(age / SLUG_FLASH_SECONDS)
			layBall(
				blast.flash,
				blast.muzzle + aim * SLUG_FLASH_FORWARD,
				lerp(SLUG_FLASH_SIZE, SLUG_FLASH_MIN, u)
			)
			show(blast.flash, 0, 1 - u)
			for index, part in blast.streaks do
				local tip = blast.muzzle
					+ directions[index] * (SLUG_STREAK_LENGTH * (0.4 + 0.6 * easeOut(u)))
				layBar(part, blast.muzzle, tip, SLUG_STREAK_WIDTH * (1 - 0.6 * u), aim)
				show(part, 0.05, 1 - u)
			end
			local casing = blast.casing
			if casing ~= nil then
				local position = blast.muzzle
					+ blast.casingVelocity * age
					+ Vector3.new(0, -0.5 * SLUG_CASING_GRAVITY * age * age, 0)
				local tumble = age * SLUG_CASING_TUMBLE
				place(casing, CFrame.new(position) * CFrame.Angles(tumble, tumble * 0.65, 0))
				local casingU = age / SLUG_CASING_SECONDS
				show(casing, 0, if casingU >= 1 then 0 else 1 - clamp01((casingU - 0.7) / 0.3))
			end
			brightest = math.max(brightest, 1 - u)
		end
		lightAt(light, lastMuzzle, SLUG_LIGHT * brightest)
		return true
	end

	return step, nil
end

-- Overcharged Shot: for delaySeconds a charge ball swells at the muzzle, two broken rings close
-- in around the aim, motes stream into it, a thin laser sight marks the line and a light builds.
-- At delaySeconds it fires: a muzzle flash and shock ring, sparks where the shot stopped (the
-- server's end point once its strike arrives) and a thin afterglow along the line. The
-- full-width beam is Feedback's hitbox effect of the ray strike, drawn once, there.
local function buildOverchargedShot(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local range = positive(def.range)
	if delay == nil or range == nil then
		return nil, nil
	end
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local right, up = basis(aim)
	local finish = delay + OC_AFTERGLOW_SECONDS
	local muzzle = muzzleOf(cast.userId, aim, cast.origin)
	local aimEnd = rayEnd(muzzle, aim, range)

	local core = takePart(kit, Enum.PartType.Ball, OC_CORE_COLOR, Enum.Material.Neon)
	local glow = takePart(kit, Enum.PartType.Ball, OC_GLOW_COLOR, Enum.Material.Neon)
	local arcs: { RingArc } = {}
	if not lowEnd then
		for ringIndex = 1, OC_RINGS do
			for index = 1, OC_RING_ARCS do
				table.insert(arcs, {
					parts = takeParts(
						kit,
						OC_RING_ARC_SEGMENTS,
						Enum.PartType.Block,
						OC_GLOW_COLOR,
						Enum.Material.Neon
					),
					ring = ringIndex,
					index = index,
				})
			end
		end
	end
	local laser = takeBeam(kit, OC_GLOW_COLOR, OC_LASER_WIDTH)
	local motes = takeEmitter(kit, MOTE_STYLE, OC_GLOW_COLOR)
	motes.emitter.Speed = NumberRange.new(OC_MOTE_RADIUS / MOTE_LIFETIME)
	local light = takeLight(kit, OC_GLOW_COLOR, OC_LIGHT_RANGE)
	local afterglow = takeBeam(kit, OC_CORE_COLOR, OC_AFTERGLOW_WIDTH)
	local flash = takePart(kit, Enum.PartType.Ball, OC_CORE_COLOR, Enum.Material.Neon)
	local shock: { BasePart } = {}
	if not lowEnd then
		shock = takeParts(
			kit,
			OC_SHOCK_SEGMENTS,
			Enum.PartType.Block,
			OC_CORE_COLOR,
			Enum.Material.Neon
		)
	end
	local sparks = takeEmitter(kit, SPARK_STYLE, OC_GLOW_COLOR)
	local rng = Random.new(cast.seq)
	local budget = 0
	local fired = false
	local fireFrom = muzzle
	local fireTo = aimEnd
	local struck: Vector3? = nil

	local function step(t: number, dt: number): boolean
		if t >= finish then
			return false
		end
		if t < delay then
			muzzle = muzzleOf(cast.userId, aim, muzzle)
			local u = t / delay
			local flicker = 1 + OC_FLICKER * (rng:NextNumber() - 0.5)
			layBall(core, muzzle, lerp(OC_CORE_FROM, OC_CORE_TO, u) * flicker)
			show(core, 0, 1)
			layBall(glow, muzzle, lerp(OC_GLOW_FROM, OC_GLOW_TO, u) * flicker)
			show(glow, OC_GLOW_TRANSPARENCY, 1)
			local arcSpan = math.rad(OC_RING_ARC_DEGREES)
			for _, arc in arcs do
				local direction = if arc.ring % 2 == 1 then 1 else -1
				local size = lerp(OC_RING_FROM, OC_RING_TO, u)
					* (if arc.ring % 2 == 1 then 1 else OC_RING_INNER_SHARE)
				local start = direction * t * OC_RING_SPIN + TAU * (arc.index - 1) / OC_RING_ARCS
				layCircle(
					arc.parts,
					muzzle,
					right,
					up,
					size,
					start,
					start + arcSpan,
					OC_RING_WIDTH,
					OC_RING_WIDTH,
					true
				)
				showAll(arc.parts, 0.1, 1)
			end
			layBeam(laser, muzzle, aimEnd)
			showBeam(laser, lerp(OC_LASER_FROM, OC_LASER_TRANSPARENCY, u), 1)
			budget = math.min(budget + rate(OC_MOTE_RATE) * dt, MAX_EMIT_BUDGET)
			while budget >= 1 do
				budget -= 1
				local outward = rng:NextUnitVector()
				emitAt(motes, frameAlong(muzzle + outward * OC_MOTE_RADIUS, -outward), 1)
			end
			lightAt(light, muzzle, OC_LIGHT_CHARGE * u)
			return true
		end
		local age = t - delay
		if not fired then
			fired = true
			fireFrom = muzzleOf(cast.userId, aim, muzzle)
			fireTo = struck or aimEnd
			show(core, 0, 0)
			show(glow, 0, 0)
			for _, arc in arcs do
				showAll(arc.parts, 0, 0)
			end
			showBeam(laser, 0, 0)
			if age < FRESH_SECONDS then
				emitAt(sparks, frameAlong(fireTo, -aim), particles(OC_END_SPARKS))
			end
		end
		local u = clamp01(age / OC_AFTERGLOW_SECONDS)
		widenBeam(afterglow, OC_AFTERGLOW_WIDTH * (1 - u))
		layBeam(afterglow, fireFrom, fireTo)
		showBeam(afterglow, OC_AFTERGLOW_TRANSPARENCY, 1 - u)
		local flashU = clamp01(age / OC_FLASH_SECONDS)
		layBall(flash, fireFrom, OC_FLASH_SIZE * (1 - flashU))
		show(flash, 0, 1 - flashU)
		if #shock > 0 then
			local shockU = clamp01(age / OC_SHOCK_SECONDS)
			local size = lerp(OC_SHOCK_FROM, OC_SHOCK_TO, easeOut(shockU))
			layCircle(shock, fireFrom, right, up, size, 0, TAU, RING_WIDTH, RING_WIDTH, true)
			showAll(shock, 0.1, 1 - shockU)
		end
		lightAt(light, fireFrom, OC_LIGHT_FIRE * (1 - u))
		return true
	end

	-- The ray's strike names where the shot really stopped (first wall, or the end of range).
	local function onStrike(strike: AbilityStrike): boolean
		if strike.tick or strike.shape ~= "ray" then
			return false
		end
		local unit = unitOf(strike.direction) or aim
		local stop = strike.endPoint or strike.origin + unit * strike.size
		struck = stop
		if fired then
			fireTo = stop
		end
		return true
	end

	return step, onStrike
end

-- Mag Dump: for durationSeconds the gun hand glows and heats from orange toward white, a
-- flickering muzzle glow spits sparks forward, smoke curls up and a light flickers; everything
-- follows the caster's hand and aim.
local function buildMagDump(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local duration = positive(def.durationSeconds)
	if duration == nil then
		return nil, nil
	end
	local firing: number = duration
	local finish = firing + MAG_TAIL_SECONDS
	local heat = takePart(kit, Enum.PartType.Ball, MAG_HEAT_COLOR, Enum.Material.Neon)
	local hand = takePart(kit, Enum.PartType.Ball, MAG_HEAT_COLOR, Enum.Material.Neon)
	local sparks = takeEmitter(kit, SPARK_STYLE, MAG_SPARK_COLOR)
	sparks.emitter.Rate = rate(MAG_SPARK_RATE)
	local smoke = takeEmitter(kit, SMOKE_STYLE, SMOKE_COLOR)
	smoke.emitter.Rate = rate(MAG_SMOKE_RATE)
	local light = takeLight(kit, MAG_HEAT_COLOR, MAG_LIGHT_RANGE)
	local rng = Random.new(cast.seq)
	local look = unitOf(cast.direction) or Vector3.zAxis
	local handPoint = cast.origin
	local muzzle = cast.origin + look * MUZZLE_FORWARD

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			setEmitting(sparks, false)
			setEmitting(smoke, false)
			return false
		end
		local root, _, character = casterOf(cast.userId)
		if root ~= nil then
			look = aimOf(cast.userId, root)
			handPoint = handOf(character, root)
			muzzle = handPoint + look * MUZZLE_FORWARD
		end
		local share = clamp01(t / firing)
		local v = envelope(t, 0, finish, MAG_FADE_IN, MAG_TAIL_SECONDS)
		local flicker = rng:NextNumber()
		heat.Color = MAG_HEAT_COLOR:Lerp(MAG_HOT_COLOR, share * MAG_WHITE_SHARE)
		layBall(
			heat,
			muzzle,
			lerp(MAG_GLOW_MIN, MAG_GLOW_MAX, flicker) * (1 + MAG_HEAT_GROWTH * share)
		)
		show(heat, lerp(MAG_GLOW_TRANSPARENCY_MIN, MAG_GLOW_TRANSPARENCY_MAX, flicker), v)
		layBall(hand, handPoint, MAG_HAND_GLOW)
		show(hand, lerp(MAG_HAND_COOL, MAG_HAND_HOT, share), v)
		local on = t < firing
		sparks.attachment.WorldCFrame = frameAlong(muzzle, look)
		setEmitting(sparks, on)
		smoke.attachment.WorldCFrame = frameAlong(muzzle, UP)
		setEmitting(smoke, on)
		lightAt(light, muzzle, (MAG_LIGHT + MAG_LIGHT_HEAT * share) * (0.7 + 0.3 * flicker) * v)
		return true
	end

	return step, nil
end

-- Cluster Shell: nothing until the shell bursts (Feedback flies it). The first sphere strike
-- with an end point from this caster's clusterShell is the splash: bomblets hop out to exactly
-- HitShapes.Scatter(impact, count, spacing, seq), the server's points at the impact's height,
-- and blink ever faster over a ring of their exact blastRadius until delaySeconds after the
-- splash, when Feedback draws their blasts. Bomblet blasts (sphere strikes on those points, no
-- end point) are claimed here so they never start a second cast's bomblets.
local function buildClusterShell(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local count = positive(def.count)
	local spacing = nonNegative(def.spacing)
	local delay = nonNegative(def.delaySeconds)
	local blastRadius = positive(def.blastRadius)
	if count == nil or spacing == nil or delay == nil or blastRadius == nil then
		return nil, nil
	end
	local fuse: number = delay
	local blast: number = blastRadius
	local pending = Tuning.Get().shooting.projectileMaxSeconds + CLUSTER_PENDING_SLACK
	local hop = math.min(CLUSTER_HOP_SECONDS, fuse * CLUSTER_HOP_SHARE)
	local impact: Vector3? = nil
	local abandoned = false
	local points: { Vector3 } = {}
	local splashAt: number? = nil
	local bomblets: { Bomblet } = {}
	local blinkPhase = 0

	local function spawnBomblets(): ()
		local segments = if lowEnd then CLUSTER_RING_SEGMENTS_LOW_END else CLUSTER_RING_SEGMENTS
		for _, point in points do
			local shell =
				takePart(kit, Enum.PartType.Ball, CLUSTER_SHELL_COLOR, Enum.Material.SmoothPlastic)
			shell.Size = Vector3.one * CLUSTER_SIZE
			local blink = takePart(kit, Enum.PartType.Ball, CLUSTER_BLINK_COLOR, Enum.Material.Neon)
			blink.Size = Vector3.one * CLUSTER_BLINK_SIZE
			local ring = takeParts(
				kit,
				segments,
				Enum.PartType.Block,
				CLUSTER_RING_COLOR,
				Enum.Material.Neon
			)
			layCircle(ring, point, FLAT_U, FLAT_V, blast, 0, TAU, RING_WIDTH, RING_HEIGHT, true)
			table.insert(bomblets, { shell = shell, blink = blink, ring = ring, point = point })
		end
	end

	local function step(t: number, dt: number): boolean
		if abandoned then
			return false
		end
		local burstAt = splashAt
		local origin = impact
		if burstAt == nil then
			if origin == nil then
				return t < pending
			end
			splashAt = t
			burstAt = t
			spawnBomblets()
		end
		if origin == nil or burstAt == nil then
			return false
		end
		local age = t - burstAt
		if age >= fuse + CLUSTER_TAIL_SECONDS then
			return false
		end
		local u = if fuse > 0 then clamp01(age / fuse) else 1
		blinkPhase += dt / lerp(CLUSTER_BLINK_SLOW, CLUSTER_BLINK_FAST, u)
		local on = blinkPhase % 1 < 0.5
		local h = if hop > 0 then clamp01(age / hop) else 1
		for _, bomblet in bomblets do
			local position = origin:Lerp(bomblet.point, h)
				+ UP * (CLUSTER_HOP_HEIGHT * 4 * h * (1 - h))
			place(bomblet.shell, CFrame.new(position))
			show(bomblet.shell, 0, 1)
			place(bomblet.blink, CFrame.new(position))
			show(bomblet.blink, CLUSTER_BLINK_TRANSPARENCY, if on then 1 else 0)
			local ringV = if h >= 1 then 1 else 0
			showAll(bomblet.ring, if on then CLUSTER_RING_ON else CLUSTER_RING_OFF, ringV)
		end
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if impact == nil then
			if strike.shape == "sphere" and strike.endPoint ~= nil then
				local centre = strike.endPoint :: Vector3
				impact = centre
				points = HitShapes.Scatter(centre, count, spacing, cast.seq)
				return true
			end
			-- An empty end strike: a set or reset dropped the shell before it burst.
			if strike.shape == "ray" and strike.size <= 0 then
				abandoned = true
				return true
			end
			return false
		end
		for _, point in points do
			if (point - strike.origin).Magnitude <= CLUSTER_MATCH_STUDS then
				return true
			end
		end
		return false
	end

	return step, onStrike
end

-- Overload Sweep: a thick beam of length `range` from the caster's root sweeps left to right,
-- crossing each server slice's centre as that slice fires ((i−1)·durationSeconds/count), while
-- the floor under the swept sector lights up slice by slice (exact radius, no pad). Follows the
-- caster; every tick widens the beam for a moment.
local function buildOverloadSweep(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local duration = positive(def.durationSeconds)
	local count = positive(def.count)
	local arcDegrees = positive(def.arcDegrees)
	local range = positive(def.range)
	if duration == nil or count == nil or arcDegrees == nil or range == nil then
		return nil, nil
	end
	local sweepSeconds: number = duration
	local reach: number = range
	local heading = flatUnit(cast.direction) or Vector3.zAxis
	local slices = math.clamp(math.floor(count), 1, SWEEP_MAX_SLICES)
	local sweep = math.rad(math.min(arcDegrees, 360))
	local slice = sweep / slices
	local firstAngle = -sweep / 2 + slice / 2
	local lastAngle = sweep / 2 - slice / 2
	local lastFire = (slices - 1) * sweepSeconds / slices
	local finish = sweepSeconds + SWEEP_FADE_SECONDS
	local base =
		Vector3.new(cast.origin.X, cast.origin.Y - rootHeightOf(cast.userId) + LIFT, cast.origin.Z)
	local toBase = CFrame.new(-base)
	local pieces: { SectorPiece } = {}
	for index = 1, slices do
		local a0 = -sweep / 2 + slice * (index - 1)
		local p0 = base + turn(heading, a0) * reach
		local p1 = base + turn(heading, a0 + slice) * reach
		if not lowEnd then
			for _, wedge in triangle(kit, base, p0, p1, SWEEP_GLOW_COLOR) do
				table.insert(pieces, {
					part = wedge.part,
					offset = toBase * wedge.frame,
					slice = index,
					base = SWEEP_FILL_TRANSPARENCY,
				})
			end
		end
		local rim = takePart(kit, Enum.PartType.Block, SWEEP_GLOW_COLOR, Enum.Material.Neon)
		local frame, length = barFrame(p0, p1, UP)
		rim.Size = Vector3.new(RING_WIDTH, RING_HEIGHT, length + RING_WIDTH * JOINT_OVERLAP)
		table.insert(pieces, {
			part = rim,
			offset = toBase * frame,
			slice = index,
			base = SWEEP_RIM_TRANSPARENCY,
		})
	end
	local core = takeBeam(kit, SWEEP_CORE_COLOR, SWEEP_CORE_WIDTH)
	local glow = takeBeam(kit, SWEEP_GLOW_COLOR, SWEEP_GLOW_WIDTH)
	local flare = takePart(kit, Enum.PartType.Ball, SWEEP_CORE_COLOR, Enum.Material.Neon)
	local tip = takePart(kit, Enum.PartType.Ball, SWEEP_GLOW_COLOR, Enum.Material.Neon)
	local tipSparks = takeEmitter(kit, SPARK_STYLE, SWEEP_GLOW_COLOR)
	tipSparks.emitter.Rate = rate(SWEEP_TIP_SPARK_RATE)
	local light = takeLight(kit, SWEEP_GLOW_COLOR, SWEEP_LIGHT_RANGE)
	local rng = Random.new(cast.seq)
	local rootPoint = cast.origin
	local floorY = base.Y - LIFT
	local pulse = 0

	local function step(t: number, dt: number): boolean
		if t >= finish then
			setEmitting(tipSparks, false)
			return false
		end
		local root, humanoid = casterOf(cast.userId)
		if root ~= nil then
			rootPoint = root.Position
			floorY = floorUnder(root, humanoid)
		end
		pulse = math.max(pulse - dt / PULSE_SECONDS, 0)
		local v = envelope(t, 0, finish, SWEEP_FADE_IN, SWEEP_FADE_SECONDS)
		local progress = if lastFire > 0 then clamp01(t / lastFire) else 1
		local direction = turn(heading, lerp(firstAngle, lastAngle, progress))
		local reachPoint = rootPoint + direction * reach
		layBeam(core, rootPoint, reachPoint)
		showBeam(core, 0, v)
		widenBeam(glow, SWEEP_GLOW_WIDTH + SWEEP_PULSE_WIDTH * pulse)
		layBeam(glow, rootPoint, reachPoint)
		showBeam(glow, SWEEP_GLOW_TRANSPARENCY, v)
		layBall(
			flare,
			rootPoint + direction * SWEEP_FLARE_FORWARD,
			SWEEP_FLARE_SIZE * (0.85 + 0.3 * rng:NextNumber())
		)
		show(flare, 0, v)
		layBall(tip, reachPoint, SWEEP_TIP_SIZE)
		show(tip, 0.1, v)
		tipSparks.attachment.WorldCFrame = frameAlong(reachPoint, -direction)
		setEmitting(tipSparks, t < sweepSeconds)
		local shift = CFrame.new(Vector3.new(rootPoint.X, floorY + LIFT, rootPoint.Z))
		for _, piece in pieces do
			place(piece.part, shift * piece.offset)
			local fireAt = (piece.slice - 1) * sweepSeconds / slices
			local reveal = if t < fireAt then 0 else clamp01((t - fireAt) / SWEEP_SLICE_FADE_IN)
			show(piece.part, piece.base, math.min(reveal, v))
		end
		lightAt(light, rootPoint + direction * SWEEP_FLARE_FORWARD, SWEEP_LIGHT * v)
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if not strike.tick then
			return false
		end
		pulse = 1
		return true
	end

	return step, onStrike
end

-- Storm Coil: a pylon tumbles from the caster's hand to the ground point over delaySeconds and
-- plants itself; a faint ring snaps out to exactly `radius` and holds for durationSeconds while
-- small arcs crackle round its top. Every zap tick flares the coils, the ring and the light and
-- throws sparks. Feedback draws the zaps and their chains from `links`.
local function buildStormCoil(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local duration = positive(def.durationSeconds)
	local radius = positive(def.radius)
	if delay == nil or duration == nil or radius == nil then
		return nil, nil
	end
	local reach: number = radius
	local centre = groundOf(cast)
	local top = centre + UP * COIL_TOP_HEIGHT
	local zoneEnd = delay + duration
	local finish = zoneEnd + COIL_FADE_SECONDS
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local start = muzzleOf(cast.userId, aim, cast.origin)

	local pylon: { PylonPiece } = {}
	for _, spec in COIL_PYLON do
		local part = if spec.glow
			then takePart(
				kit,
				spec.shape,
				if spec.shape == Enum.PartType.Ball then COIL_ARC_COLOR else COIL_COLOR,
				Enum.Material.Neon
			)
			else takePart(kit, spec.shape, COIL_METAL_COLOR, Enum.Material.Metal)
		part.Size = spec.size
		local offset = CFrame.new(0, spec.height, 0)
		if spec.shape == Enum.PartType.Cylinder then
			offset *= STAND_UP
		end
		table.insert(pylon, { part = part, offset = offset, glow = spec.glow })
	end
	local ring = takeParts(kit, ringSegments(), Enum.PartType.Block, COIL_COLOR, Enum.Material.Neon)
	local fill: BasePart? = nil
	if not lowEnd then
		local disc = takePart(kit, Enum.PartType.Cylinder, COIL_COLOR, Enum.Material.Neon)
		layDisc(disc, centre, reach)
		fill = disc
	end
	local arcs: { { BeamHandle } } = {}
	for _ = 1, if lowEnd then COIL_ARCS_LOW_END else COIL_ARCS do
		local list: { BeamHandle } = {}
		for _ = 1, COIL_ARC_SEGMENTS do
			table.insert(list, takeBeam(kit, COIL_ARC_COLOR, COIL_ARC_WIDTH))
		end
		table.insert(arcs, list)
	end
	local sparks = takeEmitter(kit, SPARK_STYLE, COIL_COLOR)
	local light = takeLight(kit, COIL_COLOR, COIL_LIGHT_RANGE)
	local rng = Random.new(cast.seq)
	local nextCrackle = 0
	local deployed = false
	local pulse = 0
	local sparked = false

	local function hideArcs(): ()
		for _, list in arcs do
			for _, beam in list do
				showBeam(beam, 0, 0)
			end
		end
	end

	local function step(t: number, dt: number): boolean
		if t >= finish then
			return false
		end
		pulse = math.max(pulse - dt / PULSE_SECONDS, 0)
		local frame: CFrame
		if t < delay then
			local u = t / delay
			local position = start:Lerp(centre + UP * COIL_PIVOT_HEIGHT, u)
				+ UP * (COIL_THROW_ARC * 4 * u * (1 - u))
			local tumble = t * COIL_TUMBLE
			frame = CFrame.new(position)
				* CFrame.Angles(tumble, 0, tumble * 0.7)
				* CFrame.new(0, -COIL_PIVOT_HEIGHT, 0)
		else
			frame = CFrame.new(centre)
		end
		local pylonV = envelope(t, 0, finish, 0, COIL_FADE_SECONDS)
		for _, piece in pylon do
			place(piece.part, frame * piece.offset)
			show(piece.part, if piece.glow then COIL_GLOW_TRANSPARENCY * (1 - pulse) else 0, pylonV)
		end

		local zoneV = envelope(t, delay, finish, ZONE_FADE_IN, COIL_FADE_SECONDS)
		if t >= delay and not deployed then
			local deploy = clamp01((t - delay) / COIL_DEPLOY_SECONDS)
			layCircle(
				ring,
				centre,
				FLAT_U,
				FLAT_V,
				reach * easeOut(deploy),
				0,
				TAU,
				RING_WIDTH,
				RING_HEIGHT,
				true
			)
			deployed = deploy >= 1
		end
		showAll(ring, COIL_RING_TRANSPARENCY * (1 - pulse), zoneV)
		local disc = fill
		if disc ~= nil then
			show(disc, lerp(COIL_FILL_TRANSPARENCY, FILL_PULSE_TRANSPARENCY, pulse), zoneV)
		end

		if t >= delay and t < zoneEnd then
			if t >= nextCrackle then
				nextCrackle = t + COIL_CRACKLE_SECONDS
				for _, list in arcs do
					if rng:NextNumber() >= COIL_ARC_CHANCE + pulse then
						for _, beam in list do
							showBeam(beam, 0, 0)
						end
						continue
					end
					local reachOut = top
						+ rng:NextUnitVector() * rng:NextNumber(COIL_ARC_MIN, COIL_ARC_REACH)
					local previous = top
					for index, beam in list do
						local point = top:Lerp(reachOut, index / #list)
						if index < #list then
							point += rng:NextUnitVector() * COIL_ARC_JITTER
						end
						layBeam(beam, previous, point)
						showBeam(beam, 0, zoneV)
						previous = point
					end
				end
			end
		else
			hideArcs()
		end
		if sparked then
			sparked = false
			emitAt(sparks, frameAlong(top, UP), particles(COIL_PULSE_SPARKS))
		end
		lightAt(light, top, (COIL_LIGHT + COIL_LIGHT_PULSE * pulse) * zoneV)
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if not isZoneStrike(strike, centre) then
			return false
		end
		pulse = 1
		sparked = true
		return true
	end

	return step, onStrike
end

local BUILDERS: { [string]: Builder } = {
	whirlwind = buildWhirlwind,
	earthquake = buildEarthquake,
	bladeStorm = buildBladeStorm,
	leapSmash = buildLeapSmash,
	impaleDash = buildImpaleDash,
	arrowRain = buildArrowRain,
	volley = buildVolley,
	slugBurst = buildSlugBurst,
	overchargedShot = buildOverchargedShot,
	magDump = buildMagDump,
	clusterShell = buildClusterShell,
	overloadSweep = buildOverloadSweep,
	stormCoil = buildStormCoil,
}

-- Visual lifecycle --------------------------------------------------------------------------

local function retire(visual: Visual): ()
	local index = table.find(visuals, visual)
	if index == nil then
		return
	end
	table.remove(visuals, index)
	releaseKit(visual.kit)
end

-- Ends at once every visual of `userId` (a cancel names one ability; a leave ends them all).
local function stopWhere(userId: number, ability: string?): ()
	for index = #visuals, 1, -1 do
		local visual = visuals[index]
		if visual.userId == userId and (ability == nil or visual.ability == ability) then
			table.remove(visuals, index)
			releaseKit(visual.kit)
		end
	end
end

-- The family's ability as tuned right now, copied so the visual keeps these numbers.
local function defFor(weapon: string, ability: string): Def?
	local family: Types.RangeWeaponDef? = Tuning.Get().weapons[weapon]
	local def = if family ~= nil then family.ability else nil
	if def == nil or def.id ~= ability then
		return nil
	end
	return table.clone(def)
end

local function parseCast(fx: { [string]: any }): Cast?
	if
		typeof(fx.userId) ~= "number"
		or typeof(fx.weapon) ~= "string"
		or typeof(fx.ability) ~= "string"
		or typeof(fx.origin) ~= "Vector3"
		or typeof(fx.direction) ~= "Vector3"
		or typeof(fx.startsAt) ~= "number"
		or typeof(fx.seq) ~= "number"
	then
		return nil
	end
	return {
		userId = fx.userId,
		weapon = fx.weapon,
		ability = fx.ability,
		origin = fx.origin,
		direction = fx.direction,
		target = if typeof(fx.target) == "Vector3" then fx.target else nil,
		startsAt = fx.startsAt,
		seq = fx.seq,
	}
end

local function parseStrike(fx: { [string]: any }): AbilityStrike?
	if
		typeof(fx.ability) ~= "string"
		or typeof(fx.userId) ~= "number"
		or typeof(fx.shape) ~= "string"
		or typeof(fx.origin) ~= "Vector3"
		or typeof(fx.direction) ~= "Vector3"
		or typeof(fx.size) ~= "number"
	then
		return nil
	end
	return {
		userId = fx.userId,
		ability = fx.ability,
		shape = fx.shape,
		origin = fx.origin,
		direction = fx.direction,
		size = fx.size,
		endPoint = if typeof(fx.endPoint) == "Vector3" then fx.endPoint else nil,
		tick = fx.tick == true,
	}
end

local function onCast(fx: { [string]: any }): ()
	if fx.cancel == true then
		if typeof(fx.userId) == "number" and typeof(fx.ability) == "string" then
			stopWhere(fx.userId, fx.ability)
		end
		return
	end
	local cast = parseCast(fx)
	if cast == nil or folder == nil then
		return
	end
	local builder = BUILDERS[cast.ability]
	local def = defFor(cast.weapon, cast.ability)
	if builder == nil or def == nil then
		return
	end
	local kit = newKit()
	local ok, step, hook = pcall(builder, cast, def, kit)
	if not ok or step == nil then
		if not ok then
			warn(`[AbilityFx] {cast.ability} failed to build: {step}`)
		end
		releaseKit(kit)
		return
	end
	if #visuals >= MAX_VISUALS then
		retire(visuals[1])
	end
	local late = math.max(Workspace:GetServerTimeNow() - cast.startsAt - CATCH_UP_GRACE, 0)
	table.insert(visuals, {
		userId = cast.userId,
		ability = cast.ability,
		kit = kit,
		clock0 = os.clock() - late,
		step = step,
		onStrike = hook,
	})
end

-- Oldest visual first, so a zone that was cast earlier claims its own ticks and a cluster
-- shell's splash goes to the cast that is still waiting for one.
local function onStrike(strike: AbilityStrike): ()
	for _, visual in visuals do
		local hook = visual.onStrike
		if hook ~= nil and visual.userId == strike.userId and visual.ability == strike.ability then
			local ok, taken = pcall(hook, strike)
			if ok and taken then
				return
			end
		end
	end
end

local function applyFx(fx: any): ()
	if typeof(fx) ~= "table" then
		return
	end
	if fx.kind == "cast" then
		onCast(fx :: { [string]: any })
	elseif fx.kind == "strike" and fx.ability ~= nil then
		local strike = parseStrike(fx :: { [string]: any })
		if strike ~= nil then
			onStrike(strike)
		end
	end
end

-- CombatFx carries a batch (an array of fx); a lone fx table is accepted too.
local function onCombatFx(payload: any): ()
	if typeof(payload) ~= "table" then
		return
	end
	if payload.kind ~= nil then
		applyFx(payload)
		return
	end
	for _, fx in payload :: { any } do
		applyFx(fx)
	end
end

local function flushMoves(): ()
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
		table.clear(moveParts)
		table.clear(moveFrames)
	end
	for _, part in doomed do
		part:Destroy()
	end
	table.clear(doomed)
end

-- Nothing here yields: every step is plain maths and property writes.
local function onRenderStep(dt: number): ()
	local now = os.clock()
	local finished: { Visual } = {}
	for _, visual in visuals do
		local ok, alive = pcall(visual.step, now - visual.clock0, dt)
		if not ok then
			warn(`[AbilityFx] {visual.ability} visual failed: {alive}`)
			table.insert(finished, visual)
		elseif not alive then
			table.insert(finished, visual)
		end
	end
	flushMoves()
	for _, visual in finished do
		retire(visual)
	end
end

-- Public API --------------------------------------------------------------------------------

function AbilityFx.Init(): ()
	-- Remotes are replicated instances: everything happens in Start.
end

-- Inert outside the Proving Grounds, like every range controller (CameraController.IsRange).
function AbilityFx.Start(): ()
	if started or destroyed or not CameraController.IsRange() then
		return
	end
	started = true
	lowEnd = Theme.lowEndDevice
	local root = Create("Folder", { Name = FOLDER_NAME, Parent = Workspace }) :: Folder
	folder = root
	-- One invisible part at the origin holds every attachment, so an attachment's position is
	-- its world position and nothing pooled ever lives inside a character.
	anchor = Create("Part", {
		Name = "Anchor",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 1,
		Size = Vector3.one * MIN_SIZE,
		CFrame = CFrame.identity,
		Parent = root,
	}) :: Part
	table.insert(connections, RunService.RenderStepped:Connect(onRenderStep))
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			stopWhere(player.UserId, nil)
		end)
	)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local combatFx =
			remotes:WaitForChild("CombatFx", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if combatFx == nil then
			warn("[AbilityFx] CombatFx missing — ability visuals are disabled")
			return
		end
		if destroyed then
			return
		end
		table.insert(connections, combatFx.OnClientEvent:Connect(onCombatFx))
	end)
end

function AbilityFx.Destroy(): ()
	destroyed = true
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(visuals)
	table.clear(moveParts)
	table.clear(moveFrames)
	table.clear(doomed)
	table.clear(partPool)
	table.clear(wedgePool)
	table.clear(beamPool)
	table.clear(emitterPool)
	table.clear(trailPool)
	table.clear(lightPool)
	local root = folder
	if root ~= nil then
		root:Destroy()
		folder = nil
	end
	anchor = nil
end

return AbilityFx
