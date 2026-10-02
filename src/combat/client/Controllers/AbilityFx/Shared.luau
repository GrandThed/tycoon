--!strict
-- AbilityFx child: the types, shared look constants, maths and character lookups every
-- ability module uses. No instances are created here (Pool owns those). Exported as one
-- table so each child aliases only what it needs: a module's top level is one function and
-- Studio's debug compile gives every top-level local its own register (limit 200).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local uiFolder = script.Parent.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))

export type Def = Types.RangeAbilityDef

-- A validated CombatFxCast (never a cancel).
export type Cast = {
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
export type AbilityStrike = {
	userId: number,
	ability: string,
	shape: string,
	origin: Vector3,
	direction: Vector3,
	size: number,
	endPoint: Vector3?,
	tick: boolean,
}

export type BeamHandle = { beam: Beam, a0: Attachment, a1: Attachment, shown: number }

-- readyAt: a released emitter is reused only once its last particle has died, because a new
-- Color would re-tint particles still in the air.
export type EmitterHandle = {
	attachment: Attachment,
	emitter: ParticleEmitter,
	readyAt: number,
	lifeMax: number,
}

export type TrailHandle = { trail: Trail, a0: Attachment, a1: Attachment }

export type LightHandle = { attachment: Attachment, light: PointLight }

-- Everything one visual took from the pools, given back in one go when it ends.
export type Kit = {
	parts: { BasePart },
	beams: { BeamHandle },
	emitters: { EmitterHandle },
	trails: { TrailHandle },
	lights: { LightHandle },
}

-- t = seconds since the cast began on this client (catch-up included); false = finished.
export type Step = (t: number, dt: number) -> boolean

-- An ability strike from the same caster and ability; true = it belonged to this visual.
export type StrikeHook = (strike: AbilityStrike) -> boolean

export type Builder = (cast: Cast, def: Def, kit: Kit) -> (Step?, StrikeHook?)

export type EmitterStyle = {
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

export type Placed = { part: BasePart, frame: CFrame }

-- Read once at load: Theme decides it at boot, before any cast can arrive.
local lowEnd = Theme.lowEndDevice

local EPSILON = 1e-6
local TAU = 2 * math.pi
local UP = Vector3.yAxis
local FLAT_U = Vector3.xAxis
local FLAT_V = Vector3.zAxis
-- A Cylinder's axis is its X; this turn stands it upright (discs, pylon parts).
local STAND_UP = CFrame.Angles(0, 0, math.pi / 2)
-- A one-off burst further in the past than this at its first step (a catch-up) is skipped.
local FRESH_SECONDS = 0.1
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
local DUST_WALL_WIDTH = 0.9
local DUST_WALL_HEIGHT = 1.4
local DUST_WALL_SETTLE = 0.4 -- share of its height the front keeps while fading
local DUST_WALL_TRANSPARENCY = 0.25
local DUST_WALL_MIN_RADIUS = 0.5

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

-- Whether a zone's tick strike belongs to the zone centred at `centre` (its capsule or sphere
-- starts at the zone's ground point).
local function isZoneStrike(strike: AbilityStrike, centre: Vector3): boolean
	local offset = strike.origin - centre
	return strike.tick and Vector3.new(offset.X, 0, offset.Z).Magnitude <= STRIKE_MATCH_STUDS
end

return {
	lowEnd = lowEnd,
	EPSILON = EPSILON,
	TAU = TAU,
	UP = UP,
	FLAT_U = FLAT_U,
	FLAT_V = FLAT_V,
	STAND_UP = STAND_UP,
	FRESH_SECONDS = FRESH_SECONDS,
	FLOOR_PROBE_UP = FLOOR_PROBE_UP,
	FLOOR_PROBE_DOWN = FLOOR_PROBE_DOWN,
	R6_ROOT_HEIGHT = R6_ROOT_HEIGHT,
	MUZZLE_FORWARD = MUZZLE_FORWARD,
	LIFT = LIFT,
	MIN_RADIUS = MIN_RADIUS,
	MIN_SIZE = MIN_SIZE,
	JOINT_OVERLAP = JOINT_OVERLAP,
	RING_SEGMENTS = RING_SEGMENTS,
	RING_SEGMENTS_LOW_END = RING_SEGMENTS_LOW_END,
	BIG_RING_SEGMENTS = BIG_RING_SEGMENTS,
	BIG_RING_SEGMENTS_LOW_END = BIG_RING_SEGMENTS_LOW_END,
	RING_WIDTH = RING_WIDTH,
	RING_HEIGHT = RING_HEIGHT,
	RING_TRANSPARENCY = RING_TRANSPARENCY,
	FILL_TRANSPARENCY = FILL_TRANSPARENCY,
	FILL_PULSE_TRANSPARENCY = FILL_PULSE_TRANSPARENCY,
	DISC_THICKNESS = DISC_THICKNESS,
	PULSE_SECONDS = PULSE_SECONDS,
	ZONE_FADE_IN = ZONE_FADE_IN,
	ZONE_FADE_OUT = ZONE_FADE_OUT,
	STRIKE_MATCH_STUDS = STRIKE_MATCH_STUDS,
	MAX_EMIT_BUDGET = MAX_EMIT_BUDGET,
	SPARK_TEXTURE = SPARK_TEXTURE,
	SMOKE_TEXTURE = SMOKE_TEXTURE,
	MOTE_LIFETIME = MOTE_LIFETIME,
	SPARK_STYLE = SPARK_STYLE,
	DUST_STYLE = DUST_STYLE,
	SMOKE_STYLE = SMOKE_STYLE,
	MOTE_STYLE = MOTE_STYLE,
	ABILITY_COLOR = ABILITY_COLOR,
	HOT_WHITE = HOT_WHITE,
	DUST_COLOR = DUST_COLOR,
	DUST_RISE = DUST_RISE,
	SMOKE_COLOR = SMOKE_COLOR,
	DUST_WALL_WIDTH = DUST_WALL_WIDTH,
	DUST_WALL_HEIGHT = DUST_WALL_HEIGHT,
	DUST_WALL_SETTLE = DUST_WALL_SETTLE,
	DUST_WALL_TRANSPARENCY = DUST_WALL_TRANSPARENCY,
	DUST_WALL_MIN_RADIUS = DUST_WALL_MIN_RADIUS,
	lerp = lerp,
	clamp01 = clamp01,
	easeOut = easeOut,
	envelope = envelope,
	unitOf = unitOf,
	flatUnit = flatUnit,
	basis = basis,
	around = around,
	tangentOf = tangentOf,
	turn = turn,
	frameAlong = frameAlong,
	barFrame = barFrame,
	positive = positive,
	nonNegative = nonNegative,
	particles = particles,
	rate = rate,
	ringSegments = ringSegments,
	bigSegments = bigSegments,
	casterOf = casterOf,
	floorUnder = floorUnder,
	rootHeightOf = rootHeightOf,
	handOf = handOf,
	muzzleOf = muzzleOf,
	aimOf = aimOf,
	isZoneStrike = isZoneStrike,
}
