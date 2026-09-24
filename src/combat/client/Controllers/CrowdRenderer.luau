--!strict
-- Draws the Proving Grounds crowd (docs/INTERFACES.md "P1 contracts", decision 1 and the
-- Feedback layers bullet; docs/COMBAT_DESIGN.md sections 4 and 7). The server simulates crowd
-- enemies as plain records; this module is the only place they become visible.
--
-- Rules that shape the module:
-- * Bodies are pooled placeholder figures (legs, torso, a bright head = the crit point, a visor
--   that shows facing and glows on wind-up). A spawn never creates an Instance in steady state:
--   Start pre-warms the pool up to crowd.maxAlive over a few frames.
-- * One Heartbeat loop and one BulkMoveTo for every moved part. A body whose pose did not change
--   this frame is skipped, so an idle crowd costs almost nothing. The loop allocates no tables.
-- * Positions are drawn ~1 snapshot behind the newest packet, timed by the server clock each
--   packet carries (CrowdCodec header), so jitter in arrival never shows as stutter. Past the
--   newest packet the body extrapolates for at most EXTRAPOLATE_CAP_SECONDS, then holds.
-- * Reactions (React) are presentation only. The server already moves a knocked or launched
--   body; the client kick here covers the ~1 snapshot the server's slide takes to arrive and
--   then hands over to it, so a hit reacts on the frame it lands.
-- * Death: the server keeps a killed record in state "dead" for a moment, then sends
--   CrowdRemove. A body that turns "dead" waits DEATH_WAIT_SECONDS for Feedback's React("death")
--   (which knows the hit direction) and otherwise dies on its own, flung away from the camera.
--   CrowdRemove of a living body (a set switch, a reset) fades it out without a fling.
-- * Particles (the death burst) gate on Theme.lowEndDevice only: reducedMotion is true on every
--   touch device here, and hit feedback is the point of the range on phones too.
-- * Every enemy number (sizes, colours, snapshotHz, feedback strength) comes from Tuning.Get();
--   the constants below are the feel of the placeholder figure itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local CrowdCodec = require(sharedFolder:WaitForChild("CrowdCodec"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

export type Reaction = "flash" | "flinch" | "knockback" | "launch" | "death"
export type ForEachCallback = (
	id: number,
	position: Vector3,
	radius: number,
	headRadius: number,
	height: number
) -> ()

type Phase = "alive" | "dying" | "vanish"

type Entity = {
	id: number,
	kind: string,
	maxHp: number,
	hpFraction: number,
	state: Types.CrowdState,
	phase: Phase,
	phaseStart: number,
	-- os.clock() at which a body that turned "dead" dies on its own; math.huge = not waiting.
	deathDue: number,

	model: Model,
	legs: BasePart,
	torso: BasePart,
	head: BasePart,
	visor: BasePart,

	radius: number,
	headRadius: number,
	height: number,
	legHeight: number,
	torsoHeight: number,
	torsoSize: Vector3,
	knockbackMult: number,
	bodyColor: Color3,
	legColor: Color3,
	headColor: Color3,
	legOffset: CFrame,
	torsoOffset: CFrame,
	headOffset: CFrame,
	visorOffset: CFrame,
	midUp: CFrame,
	midDown: CFrame,

	-- Snapshot ring, oldest (A) to newest (C), stamped with the server time of the packet.
	samples: number,
	posA: Vector3,
	yawA: number,
	timeA: number,
	posB: Vector3,
	yawB: number,
	timeB: number,
	posC: Vector3,
	yawC: number,
	timeC: number,

	-- Interpolated feet (no reaction offsets): what aim assist and auto-fire read.
	position: Vector3,
	-- Feet as drawn this frame (reaction offsets and death flight included).
	shown: Vector3,
	yaw: number,
	lean: Vector3,

	flashing: boolean,
	flashUntil: number,
	flinchStart: number,
	flinchStrength: number,
	flinchDir: Vector3,
	knockStart: number,
	knockVector: Vector3,
	launchStart: number,
	launchHeight: number,
	launchAxis: Vector3,
	launchAngle: number,
	deathOrigin: Vector3,
	deathVelocity: Vector3,
	deathAxis: Vector3,
	deathSpin: number,
	deathTopple: boolean,

	fade: number,
	squash: number,
	visorHot: boolean,
	dirty: boolean,
	lastShown: Vector3,
	lastYaw: number,
	lastLean: Vector3,
	lastTumble: number,
	lastSquash: number,
	lastTuck: number,
	index: number,
}

local FOLDER_NAME = "CrowdBodies"
-- CrowdService encodes against its bounds centre, and every arena is built at the world origin
-- with its floor top at y = 0, so both sides decode against the same point.
local ARENA_ORIGIN = Vector3.zero

-- Interpolation.
local INTERP_SNAPSHOTS = 1.2 -- render this many snapshot intervals behind the newest packet
local EXTRAPOLATE_CAP_SECONDS = 0.12
local TELEPORT_STUDS = 16 -- a jump this long between two samples snaps instead of sliding
local LAG_RISE = 0.5 -- the delivery-lag estimate climbs fast (a late packet must not stall)...
local LAG_FALL = 0.05 -- ...and relaxes slowly (one early packet must not cause a stutter)
local YAW_SMOOTH_RATE = 14
local LEAN_SMOOTH_RATE = 12
local SETTLE_EPSILON = 0.002

-- State poses (radians of lean; tuck in leg heights).
local STAGGER_LEAN = 0.32
local WINDUP_LEAN = 0.22
local AIRBORNE_LEAN = 0.35
local AIRBORNE_TUCK = 0.35

-- Reactions. Each scales with React's strength; knockback, launch and fling also scale with the
-- kind's knockbackMult, so a boss (0) never slides or flies.
local FLASH_SECONDS = 0.08
local FLINCH_SECONDS = 0.16
local FLINCH_SQUASH = 0.3
local FLINCH_LEAN = 0.35
local FLINCH_MIN_KIND_SCALE = 0.35
local KNOCKBACK_SECONDS = 0.28
local KNOCKBACK_RISE = 0.3 -- share of the kick spent moving out; the rest hands over to the server
local KNOCKBACK_STUDS = 1.6
local LAUNCH_SECONDS = 0.45
local LAUNCH_STUDS = 2.2
local LAUNCH_TILT = 0.9
local MAX_STRENGTH = 3

-- Death.
local DEATH_WAIT_SECONDS = 0.12
local DEATH_SECONDS = 0.75
local DEATH_FADE_START = 0.3
local FLING_SPEED = 30
local FLING_UP = 24
local FLING_GRAVITY = 90
local DEATH_SPIN = 10
local TOPPLE_BELOW = 0.2 -- below this fling strength a body topples over instead of flying
local TOPPLE_SECONDS = 0.35
local VANISH_SECONDS = 0.2
local VANISH_SINK = 0.3 -- share of the height sunk into the floor while fading out

-- Death burst (skipped on low-end devices).
local BURST_PARTICLES = 10
local MAX_BURSTS_PER_STEP = 12

-- Figure proportions, as shares of the kind's radius / height.
local HEAD_OVERLAP = 0.92 -- the head sits slightly into the torso so no gap shows on a squash
local LEG_SHARE = 0.42
local TORSO_WIDTH = 1.9
local TORSO_DEPTH = 1.3
local LEG_WIDTH = 1.25
local LEG_DEPTH = 1.0
local MIN_NECK_SHARE = 0.35

-- Figure colours. Kind colours come from config; these are the placeholder's own contrast.
local HEAD_TINT = Color3.fromRGB(255, 222, 120) -- warm yellow: the crit point reads at a glance
local HEAD_TINT_SHARE = 0.6
local LEG_SHADE = Color3.fromRGB(20, 20, 24)
local LEG_SHADE_SHARE = 0.35
local VISOR_COLOR = Color3.fromRGB(28, 30, 36)
local VISOR_HOT_COLOR = Color3.fromRGB(255, 140, 40)
local FLASH_COLOR = Color3.new(1, 1, 1)
local BODY_MATERIAL = Enum.Material.SmoothPlastic
local FLASH_MATERIAL = Enum.Material.Neon

local PREWARM_PER_FRAME = 16
local TWO_PI = 2 * math.pi
local UP = Vector3.yAxis

local started = false
local destroyed = false
local folder: Folder? = nil
local template: Model? = nil
local connections: { RBXScriptConnection } = {}
local tuningConnection: Tuning.Connection? = nil

local active: { Entity } = {}
local byId: { [number]: Entity } = {}
local pool: { Entity } = {}

-- Reused every frame; entries past the live count are cleared so BulkMoveTo sees exact arrays.
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local moveCount = 0

local interval = 1 / 15
local lagEstimate: number? = nil
local newestStamp = -math.huge
local burstsThisStep = 0
local burstEmitters: { [string]: ParticleEmitter } = {}
local burstColors: { [string]: Color3 } = {}

local function angleDelta(from: number, to: number): number
	return (to - from + math.pi) % TWO_PI - math.pi
end

local function lookOf(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function kindDef(kind: string): Types.CrowdKindDef?
	local crowd = Tuning.Get().crowd
	if crowd == nil or crowd.kinds == nil then
		return nil
	end
	local def = crowd.kinds[kind]
	if def ~= nil then
		return def
	end
	-- An unknown kind still gets a body (degrade, never error): the fodder shape, else any.
	local fallback = crowd.kinds.fodder
	if fallback ~= nil then
		return fallback
	end
	for _, other in crowd.kinds do
		return other
	end
	return nil
end

local function colorOf(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1] or 128, rgb[2] or 128, rgb[3] or 128)
end

local function newPart(name: string, shape: Enum.PartType, castShadow: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = castShadow
	part.Material = BODY_MATERIAL
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.one
	return part
end

local function buildTemplate(): Model
	local model = Instance.new("Model")
	model.Name = "CrowdBody"
	-- Only the torso casts a shadow: enough to ground the figure, a quarter of the shadow cost.
	local legs = newPart("Legs", Enum.PartType.Block, false)
	local torso = newPart("Torso", Enum.PartType.Block, true)
	local head = newPart("Head", Enum.PartType.Ball, false)
	local visor = newPart("Visor", Enum.PartType.Block, false)
	visor.Color = VISOR_COLOR
	legs.Parent = model
	torso.Parent = model
	head.Parent = model
	visor.Parent = model
	model.PrimaryPart = torso
	return model
end

local function newEntity(): Entity?
	local source = template
	if source == nil then
		return nil
	end
	local model = source:Clone()
	local legs = model:FindFirstChild("Legs") :: BasePart
	local torso = model:FindFirstChild("Torso") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	local visor = model:FindFirstChild("Visor") :: BasePart
	local entity: Entity = {
		id = 0,
		kind = "",
		maxHp = 0,
		hpFraction = 1,
		state = "idle",
		phase = "alive",
		phaseStart = 0,
		deathDue = math.huge,
		model = model,
		legs = legs,
		torso = torso,
		head = head,
		visor = visor,
		radius = 1,
		headRadius = 0.5,
		height = 4,
		legHeight = 1,
		torsoHeight = 1,
		torsoSize = Vector3.one,
		knockbackMult = 1,
		bodyColor = FLASH_COLOR,
		legColor = FLASH_COLOR,
		headColor = FLASH_COLOR,
		legOffset = CFrame.identity,
		torsoOffset = CFrame.identity,
		headOffset = CFrame.identity,
		visorOffset = CFrame.identity,
		midUp = CFrame.identity,
		midDown = CFrame.identity,
		samples = 0,
		posA = Vector3.zero,
		yawA = 0,
		timeA = 0,
		posB = Vector3.zero,
		yawB = 0,
		timeB = 0,
		posC = Vector3.zero,
		yawC = 0,
		timeC = 0,
		position = Vector3.zero,
		shown = Vector3.zero,
		yaw = 0,
		lean = Vector3.zero,
		flashing = false,
		flashUntil = 0,
		flinchStart = -math.huge,
		flinchStrength = 0,
		flinchDir = Vector3.zero,
		knockStart = -math.huge,
		knockVector = Vector3.zero,
		launchStart = -math.huge,
		launchHeight = 0,
		launchAxis = Vector3.xAxis,
		launchAngle = 0,
		deathOrigin = Vector3.zero,
		deathVelocity = Vector3.zero,
		deathAxis = Vector3.xAxis,
		deathSpin = 0,
		deathTopple = false,
		fade = 0,
		squash = 1,
		visorHot = false,
		dirty = true,
		lastShown = Vector3.zero,
		lastYaw = 0,
		lastLean = Vector3.zero,
		lastTumble = 0,
		lastSquash = 1,
		lastTuck = 0,
		index = 0,
	}
	return entity
end

local function paint(entity: Entity, flash: boolean): ()
	local material = if flash then FLASH_MATERIAL else BODY_MATERIAL
	entity.legs.Color = if flash then FLASH_COLOR else entity.legColor
	entity.torso.Color = if flash then FLASH_COLOR else entity.bodyColor
	entity.head.Color = if flash then FLASH_COLOR else entity.headColor
	entity.legs.Material = material
	entity.torso.Material = material
	entity.head.Material = material
	entity.flashing = flash
end

local function setVisorHot(entity: Entity, hot: boolean): ()
	if entity.visorHot == hot then
		return
	end
	entity.visorHot = hot
	entity.visor.Color = if hot then VISOR_HOT_COLOR else VISOR_COLOR
	entity.visor.Material = if hot then FLASH_MATERIAL else BODY_MATERIAL
end

local function setFade(entity: Entity, fade: number): ()
	if entity.fade == fade then
		return
	end
	entity.fade = fade
	entity.legs.Transparency = fade
	entity.torso.Transparency = fade
	entity.head.Transparency = fade
	entity.visor.Transparency = fade
end

-- Sizes, offsets and colours from the kind's current def. Runs on spawn and when Tuning changes.
local function applyKind(entity: Entity, def: Types.CrowdKindDef): ()
	local radius = math.max(def.radius, 0.1)
	local headRadius = math.max(def.headRadius, 0.05)
	local height = math.max(def.height, 0.5)
	local headDiameter = 2 * headRadius
	local neck = math.max(height - headDiameter * HEAD_OVERLAP, height * MIN_NECK_SHARE)
	local legHeight = neck * LEG_SHARE
	local torsoHeight = neck - legHeight
	local headY = height - headRadius

	entity.radius = radius
	entity.headRadius = headRadius
	entity.height = height
	entity.legHeight = legHeight
	entity.torsoHeight = torsoHeight
	entity.knockbackMult = math.max(def.knockbackMult, 0)
	entity.torsoSize = Vector3.new(radius * TORSO_WIDTH, torsoHeight, radius * TORSO_DEPTH)

	entity.legs.Size = Vector3.new(radius * LEG_WIDTH, legHeight, radius * LEG_DEPTH)
	entity.torso.Size = entity.torsoSize
	entity.head.Size = Vector3.new(headDiameter, headDiameter, headDiameter)
	entity.visor.Size = Vector3.new(headDiameter * 0.72, headRadius * 0.34, headRadius * 0.3)
	entity.squash = 1

	entity.legOffset = CFrame.new(0, legHeight * 0.5, 0)
	entity.torsoOffset = CFrame.new(0, legHeight + torsoHeight * 0.5, 0)
	entity.headOffset = CFrame.new(0, headY, 0)
	entity.visorOffset = CFrame.new(0, headY + headRadius * 0.12, -headRadius * 0.82)
	entity.midUp = CFrame.new(0, height * 0.5, 0)
	entity.midDown = CFrame.new(0, -height * 0.5, 0)

	local base = colorOf(def.color)
	entity.bodyColor = base
	entity.legColor = base:Lerp(LEG_SHADE, LEG_SHADE_SHARE)
	entity.headColor = base:Lerp(HEAD_TINT, HEAD_TINT_SHARE)
	paint(entity, entity.flashing)
	entity.dirty = true
end

local function release(entity: Entity): ()
	local index = entity.index
	if index > 0 and active[index] == entity then
		local last = active[#active]
		active[index] = last
		last.index = index
		active[#active] = nil
	end
	entity.index = 0
	if byId[entity.id] == entity then
		byId[entity.id] = nil
	end
	entity.model.Parent = nil
	if entity.flashing then
		paint(entity, false)
	end
	setVisorHot(entity, false)
	setFade(entity, 0)
	if entity.squash ~= 1 then
		entity.torso.Size = entity.torsoSize
		entity.squash = 1
	end
	table.insert(pool, entity)
end

local function spawnEntity(id: number, kind: string, maxHp: number): ()
	local def = kindDef(kind)
	if def == nil then
		return
	end
	local existing = byId[id]
	if existing ~= nil then
		if existing.phase == "alive" then
			-- A re-announce (join sync) of a body already drawn: keep its motion.
			existing.kind = kind
			existing.maxHp = maxHp
			applyKind(existing, def)
			return
		end
		release(existing)
	end
	local entity = table.remove(pool) or newEntity()
	if entity == nil then
		return
	end
	entity.id = id
	entity.kind = kind
	entity.maxHp = maxHp
	entity.hpFraction = 1
	entity.state = "idle"
	entity.phase = "alive"
	entity.phaseStart = os.clock()
	entity.deathDue = math.huge
	entity.samples = 0
	entity.lean = Vector3.zero
	entity.flashUntil = 0
	entity.flinchStart = -math.huge
	entity.knockStart = -math.huge
	entity.launchStart = -math.huge
	entity.dirty = true
	applyKind(entity, def)
	table.insert(active, entity)
	entity.index = #active
	byId[id] = entity
	-- Parented on its first snapshot, so it never flashes up at the pool's last pose.
end

local function startVanish(entity: Entity): ()
	entity.phase = "vanish"
	entity.phaseStart = os.clock()
	entity.dirty = true
end

local function newEmitter(parent: Instance): ParticleEmitter
	local anchor = newPart("CrowdBurst", Enum.PartType.Block, false)
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	local attachment = Instance.new("Attachment")
	attachment.Parent = anchor
	local emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.Lifetime = NumberRange.new(0.3, 0.55)
	emitter.Speed = NumberRange.new(12, 26)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 3
	emitter.Acceleration = Vector3.new(0, -50, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new(0, 0.3)
	emitter.LightEmission = 0.4
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-240, 240)
	emitter.Parent = attachment
	anchor.Parent = parent
	return emitter
end

local function burstAt(entity: Entity, strength: number): ()
	local parent = folder
	if Theme.lowEndDevice or parent == nil or burstsThisStep >= MAX_BURSTS_PER_STEP then
		return
	end
	burstsThisStep += 1
	-- One emitter per kind: an emitter's Color re-tints its live particles, so kinds cannot share.
	local existing: ParticleEmitter? = burstEmitters[entity.kind]
	local emitter = if existing ~= nil then existing else newEmitter(parent)
	burstEmitters[entity.kind] = emitter
	if burstColors[entity.kind] ~= entity.bodyColor then
		burstColors[entity.kind] = entity.bodyColor
		emitter.Color = ColorSequence.new(FLASH_COLOR, entity.bodyColor)
	end
	local attachment = emitter.Parent :: Attachment
	attachment.WorldPosition = entity.shown + UP * (entity.height * 0.5)
	emitter:Emit(math.max(1, math.round(BURST_PARTICLES * math.min(strength, 2))))
end

-- direction: horizontal unit vector the body is flung along.
local function startDeath(entity: Entity, direction: Vector3, strength: number): ()
	if strength <= 0 then
		startVanish(entity)
		return
	end
	local push = strength * entity.knockbackMult
	entity.phase = "dying"
	entity.phaseStart = os.clock()
	entity.deathDue = math.huge
	entity.deathOrigin = entity.shown
	entity.deathVelocity = direction * (FLING_SPEED * push) + UP * (FLING_UP * push)
	-- Rotating about up × direction tips the head toward `direction` (away from the hit).
	entity.deathAxis = UP:Cross(direction)
	entity.deathTopple = push < TOPPLE_BELOW
	entity.deathSpin = DEATH_SPIN * math.min(push, 2)
	entity.dirty = true
	burstAt(entity, strength)
end

-- The horizontal direction a reaction pushes along; nil = away from the local camera.
local function reactionDirection(entity: Entity, direction: Vector3?): Vector3
	local raw = direction
	if raw == nil then
		local camera = Workspace.CurrentCamera
		if camera ~= nil then
			raw = entity.shown - camera.CFrame.Position
		end
	end
	if raw ~= nil then
		local flat = Vector3.new(raw.X, 0, raw.Z)
		if flat.Magnitude > 1e-3 then
			return flat.Unit
		end
	end
	return -lookOf(entity.yaw)
end

local function defaultDeathStrength(): number
	local feedback = Tuning.Get().feedback
	return if feedback ~= nil then feedback.enemyReaction else 1
end

local function blend(
	entity: Entity,
	fromPos: Vector3,
	fromYaw: number,
	fromTime: number,
	toPos: Vector3,
	toYaw: number,
	toTime: number,
	renderTime: number
): number
	local span = toTime - fromTime
	if span <= 0 or (toPos - fromPos).Magnitude > TELEPORT_STUDS then
		entity.position = toPos
		return toYaw
	end
	local u = (renderTime - fromTime) / span
	entity.position = fromPos:Lerp(toPos, u)
	return fromYaw + angleDelta(fromYaw, toYaw) * u
end

-- Writes entity.position for renderTime and returns the target yaw.
local function sampleAt(entity: Entity, renderTime: number): number
	if renderTime >= entity.timeC then
		if entity.samples >= 2 and entity.timeC > entity.timeB then
			local step = entity.posC - entity.posB
			if step.Magnitude <= TELEPORT_STUDS then
				local ahead = math.min(renderTime - entity.timeC, EXTRAPOLATE_CAP_SECONDS)
				entity.position = entity.posC + step * (ahead / (entity.timeC - entity.timeB))
				return entity.yawC
			end
		end
		entity.position = entity.posC
		return entity.yawC
	end
	if renderTime >= entity.timeB then
		return blend(
			entity,
			entity.posB,
			entity.yawB,
			entity.timeB,
			entity.posC,
			entity.yawC,
			entity.timeC,
			renderTime
		)
	end
	if renderTime >= entity.timeA then
		return blend(
			entity,
			entity.posA,
			entity.yawA,
			entity.timeA,
			entity.posB,
			entity.yawB,
			entity.timeB,
			renderTime
		)
	end
	entity.position = entity.posA
	return entity.yawA
end

local function pushSample(entity: Entity, entry: Types.CrowdSnapshotEntry, stamp: number): ()
	if entity.samples == 0 then
		entity.posA, entity.posB, entity.posC = entry.position, entry.position, entry.position
		entity.yawA, entity.yawB, entity.yawC = entry.yaw, entry.yaw, entry.yaw
		entity.timeA, entity.timeB, entity.timeC = stamp, stamp, stamp
		entity.samples = 1
		entity.position = entry.position
		entity.shown = entry.position
		entity.yaw = entry.yaw
		entity.dirty = true
		entity.model.Parent = folder
	elseif stamp > entity.timeC then
		entity.posA, entity.yawA, entity.timeA = entity.posB, entity.yawB, entity.timeB
		entity.posB, entity.yawB, entity.timeB = entity.posC, entity.yawC, entity.timeC
		entity.posC, entity.yawC, entity.timeC = entry.position, entry.yaw, stamp
		entity.samples = math.min(entity.samples + 1, 3)
	else
		return
	end
	entity.hpFraction = entry.hpFraction
	if entry.state ~= entity.state then
		entity.state = entry.state
		setVisorHot(entity, entry.state == "windup")
		entity.dirty = true
		if entry.state == "dead" and entity.deathDue == math.huge then
			entity.deathDue = os.clock() + DEATH_WAIT_SECONDS
		end
	end
end

local function onSnapshot(data: any): ()
	if typeof(data) ~= "buffer" then
		return
	end
	local packet = data :: buffer
	local stamp = CrowdCodec.ReadTime(packet)
	if stamp == nil then
		return
	end
	local serverNow = Workspace:GetServerTimeNow()
	if stamp <= 0 then
		stamp = serverNow
	end
	local crowd = Tuning.Get().crowd
	if crowd ~= nil and crowd.snapshotHz > 0 then
		interval = 1 / crowd.snapshotHz
	end
	-- Every packet of one frame shares its stamp; only the first of a new frame measures lag.
	if stamp > newestStamp then
		newestStamp = stamp
		local observed = serverNow - stamp
		local current = lagEstimate
		if current == nil then
			lagEstimate = observed
		else
			local rate = if observed > current then LAG_RISE else LAG_FALL
			lagEstimate = current + (observed - current) * rate
		end
	end
	for _, entry in CrowdCodec.Decode(packet, ARENA_ORIGIN) do
		local entity = byId[entry.id]
		if entity ~= nil and entity.phase == "alive" then
			pushSample(entity, entry, stamp)
		end
	end
end

local function onSpawn(payload: any): ()
	if typeof(payload) ~= "table" then
		return
	end
	for _, info in payload do
		if
			typeof(info) == "table"
			and typeof(info.id) == "number"
			and typeof(info.kind) == "string"
		then
			spawnEntity(
				info.id,
				info.kind,
				if typeof(info.maxHp) == "number" then info.maxHp else 0
			)
		end
	end
end

local function onRemove(payload: any): ()
	if typeof(payload) ~= "table" then
		return
	end
	for _, id in payload do
		local entity = if typeof(id) == "number" then byId[id] else nil
		if entity == nil then
			continue
		end
		if entity.samples == 0 then
			release(entity)
		elseif entity.phase == "alive" then
			if entity.state == "dead" then
				-- Killed and never reacted to (e.g. the packet with its "dead" state was lost).
				startDeath(entity, reactionDirection(entity, nil), defaultDeathStrength())
			else
				startVanish(entity)
			end
		end
	end
end

local function queuePose(entity: Entity, root: CFrame, squash: number, tuck: number): ()
	if math.abs(squash - entity.squash) > 0.005 then
		local widen = 1 / math.sqrt(squash)
		local size = entity.torsoSize
		entity.torso.Size = Vector3.new(size.X * widen, size.Y * squash, size.Z * widen)
		entity.squash = squash
	end
	local n = moveCount
	moveParts[n + 1] = entity.legs
	moveFrames[n + 1] = if tuck ~= 0
		then root * CFrame.new(0, entity.legHeight * 0.5 + tuck, 0)
		else root * entity.legOffset
	moveParts[n + 2] = entity.torso
	moveParts[n + 3] = entity.head
	moveParts[n + 4] = entity.visor
	if entity.squash ~= 1 then
		local drop = entity.torsoHeight * (1 - entity.squash)
		moveFrames[n + 2] = root
			* CFrame.new(0, entity.legHeight + entity.torsoHeight * entity.squash * 0.5, 0)
		local lowered = root * CFrame.new(0, -drop, 0)
		moveFrames[n + 3] = lowered * entity.headOffset
		moveFrames[n + 4] = lowered * entity.visorOffset
	else
		moveFrames[n + 2] = root * entity.torsoOffset
		moveFrames[n + 3] = root * entity.headOffset
		moveFrames[n + 4] = root * entity.visorOffset
	end
	moveCount = n + 4
end

local function rootFrame(
	entity: Entity,
	feet: Vector3,
	yaw: number,
	lean: Vector3,
	tumbleAxis: Vector3,
	tumbleAngle: number
): CFrame
	local root = CFrame.new(feet)
	local angle = lean.Magnitude
	if angle > 1e-4 then
		-- up × lean tips the top of the body toward `lean`, pivoting at the feet.
		root *= CFrame.fromAxisAngle(UP:Cross(lean) / angle, angle)
	end
	if tumbleAngle ~= 0 then
		root = root * entity.midUp * CFrame.fromAxisAngle(tumbleAxis, tumbleAngle) * entity.midDown
	end
	return root * CFrame.fromEulerAnglesYXZ(0, yaw, 0)
end

local function stateLeanTarget(entity: Entity): Vector3
	local state = entity.state
	if state == "stagger" then
		return lookOf(entity.yaw) * -STAGGER_LEAN
	elseif state == "windup" then
		return lookOf(entity.yaw) * -WINDUP_LEAN
	elseif state == "airborne" then
		return lookOf(entity.yaw) * -AIRBORNE_LEAN
	end
	return Vector3.zero
end

local function smoothstep(u: number): number
	return u * u * (3 - 2 * u)
end

-- Samples, smooths and poses one living body; queues its parts only when the pose changed.
local function stepAlive(
	entity: Entity,
	now: number,
	renderTime: number,
	yawAlpha: number,
	leanAlpha: number
): ()
	if now >= entity.deathDue then
		startDeath(entity, reactionDirection(entity, nil), defaultDeathStrength())
		return
	end
	local targetYaw = sampleAt(entity, renderTime)
	local turn = angleDelta(entity.yaw, targetYaw)
	entity.yaw = if math.abs(turn) < SETTLE_EPSILON then targetYaw else entity.yaw + turn * yawAlpha

	local leanTarget = stateLeanTarget(entity)
	local leanGap = leanTarget - entity.lean
	entity.lean = if leanGap.Magnitude < SETTLE_EPSILON
		then leanTarget
		else entity.lean + leanGap * leanAlpha

	local offset = Vector3.zero
	local lean = entity.lean
	local squash = 1
	local tumbleAngle = 0
	local tuck = if entity.state == "airborne" then entity.legHeight * AIRBORNE_TUCK else 0

	local knockAge = now - entity.knockStart
	if knockAge < KNOCKBACK_SECONDS then
		local u = knockAge / KNOCKBACK_SECONDS
		local reach = if u < KNOCKBACK_RISE
			then 1 - (1 - u / KNOCKBACK_RISE) ^ 2
			else 1 - smoothstep((u - KNOCKBACK_RISE) / (1 - KNOCKBACK_RISE))
		offset += entity.knockVector * reach
	end

	local launchAge = now - entity.launchStart
	if launchAge < LAUNCH_SECONDS then
		local u = launchAge / LAUNCH_SECONDS
		offset += UP * (entity.launchHeight * 4 * u * (1 - u))
		tumbleAngle = entity.launchAngle * math.sin(math.pi * u)
	end

	local flinchAge = now - entity.flinchStart
	if flinchAge < FLINCH_SECONDS then
		local envelope = (1 - flinchAge / FLINCH_SECONDS) ^ 2
		squash = math.max(0.5, 1 - FLINCH_SQUASH * entity.flinchStrength * envelope)
		squash = math.round(squash * 100) / 100
		lean += entity.flinchDir * (FLINCH_LEAN * entity.flinchStrength * envelope)
	end

	local shown = entity.position + offset
	entity.shown = shown
	if
		not entity.dirty
		and (shown - entity.lastShown).Magnitude < SETTLE_EPSILON
		and math.abs(entity.yaw - entity.lastYaw) < SETTLE_EPSILON
		and (lean - entity.lastLean).Magnitude < SETTLE_EPSILON
		and tumbleAngle == entity.lastTumble
		and squash == entity.lastSquash
		and tuck == entity.lastTuck
	then
		return
	end
	entity.dirty = false
	entity.lastShown = shown
	entity.lastYaw = entity.yaw
	entity.lastLean = lean
	entity.lastTumble = tumbleAngle
	entity.lastSquash = squash
	entity.lastTuck = tuck
	queuePose(
		entity,
		rootFrame(entity, shown, entity.yaw, lean, entity.launchAxis, tumbleAngle),
		squash,
		tuck
	)
end

local function stepDying(entity: Entity, now: number): ()
	local age = now - entity.phaseStart
	if age >= DEATH_SECONDS then
		release(entity)
		return
	end
	local origin = entity.deathOrigin
	local flight = entity.deathVelocity * age + UP * (-0.5 * FLING_GRAVITY * age * age)
	local feet = origin + flight
	if feet.Y < origin.Y then
		feet = Vector3.new(feet.X, origin.Y, feet.Z)
	end
	entity.shown = feet
	local root
	if entity.deathTopple then
		local tip = math.min(age / TOPPLE_SECONDS, 1)
		local lean = UP:Cross(entity.deathAxis) * -(smoothstep(tip) * math.pi * 0.5)
		-- deathAxis = up × dir, so -(up × deathAxis) = dir: the body falls away from the hit.
		root = rootFrame(entity, feet, entity.yaw, lean, entity.deathAxis, 0)
	else
		root = rootFrame(
			entity,
			feet,
			entity.yaw,
			Vector3.zero,
			entity.deathAxis,
			entity.deathSpin * age
		)
	end
	if age > DEATH_FADE_START then
		setFade(entity, (age - DEATH_FADE_START) / (DEATH_SECONDS - DEATH_FADE_START))
	end
	queuePose(entity, root, 1, 0)
end

local function stepVanish(entity: Entity, now: number): ()
	local u = (now - entity.phaseStart) / VANISH_SECONDS
	if u >= 1 then
		release(entity)
		return
	end
	setFade(entity, u)
	local feet = entity.shown - UP * (entity.height * VANISH_SINK * u)
	queuePose(entity, rootFrame(entity, feet, entity.yaw, entity.lean, entity.launchAxis, 0), 1, 0)
end

local function step(dt: number): ()
	burstsThisStep = 0
	if #active == 0 then
		return
	end
	local now = os.clock()
	local renderTime = Workspace:GetServerTimeNow()
		- (lagEstimate or 0)
		- interval * INTERP_SNAPSHOTS
	local yawAlpha = 1 - math.exp(-dt * YAW_SMOOTH_RATE)
	local leanAlpha = 1 - math.exp(-dt * LEAN_SMOOTH_RATE)
	local previousCount = moveCount
	moveCount = 0

	-- Backwards: release() swaps the last body into the freed slot, which was already stepped.
	for index = #active, 1, -1 do
		local entity = active[index]
		if entity.flashing and now >= entity.flashUntil then
			paint(entity, false)
		end
		if entity.samples == 0 then
			continue
		end
		if entity.phase == "alive" then
			stepAlive(entity, now, renderTime, yawAlpha, leanAlpha)
		elseif entity.phase == "dying" then
			stepDying(entity, now)
		else
			stepVanish(entity, now)
		end
	end

	for index = previousCount, moveCount + 1, -1 do
		moveParts[index] = nil
		moveFrames[index] = nil
	end
	if moveCount > 0 then
		Workspace:BulkMoveTo(moveParts, moveFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function onTuningChanged(): ()
	for _, entity in active do
		local def = kindDef(entity.kind)
		if def ~= nil then
			applyKind(entity, def)
		end
	end
end

local function prewarm(): ()
	local crowd = Tuning.Get().crowd
	local target = if crowd ~= nil then crowd.maxAlive else 0
	while not destroyed and #pool + #active < target do
		for _ = 1, PREWARM_PER_FRAME do
			local entity = newEntity()
			if entity == nil or #pool + #active >= target then
				return
			end
			table.insert(pool, entity)
		end
		task.wait()
	end
end

local function waitRemote(remotes: Instance, name: string): Instance?
	local remote = remotes:WaitForChild(name, Theme.COMBAT_REMOTE_WAIT_SECONDS)
	if remote == nil then
		warn(`[CrowdRenderer] {name} missing — the crowd will not be drawn`)
	end
	return remote
end

local function wire(): ()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", Theme.COMBAT_REMOTE_WAIT_SECONDS)
	if remotes == nil or destroyed then
		return
	end
	local spawnRemote = waitRemote(remotes, "CrowdSpawn")
	local snapshotRemote = waitRemote(remotes, "CrowdSnapshot")
	local removeRemote = waitRemote(remotes, "CrowdRemove")
	if destroyed or spawnRemote == nil or snapshotRemote == nil or removeRemote == nil then
		return
	end
	if not spawnRemote:IsA("RemoteEvent") or not removeRemote:IsA("RemoteEvent") then
		warn("[CrowdRenderer] CrowdSpawn/CrowdRemove are not RemoteEvents")
		return
	end
	if not snapshotRemote:IsA("UnreliableRemoteEvent") then
		warn("[CrowdRenderer] CrowdSnapshot is not an UnreliableRemoteEvent")
		return
	end
	table.insert(connections, spawnRemote.OnClientEvent:Connect(onSpawn))
	table.insert(connections, snapshotRemote.OnClientEvent:Connect(onSnapshot))
	table.insert(connections, removeRemote.OnClientEvent:Connect(onRemove))
	prewarm()
end

local CrowdRenderer = {}

-- Main's controller contract; everything happens in Start.
function CrowdRenderer.Init(): () end

-- Inert outside the Proving Grounds (the Workspace lever named by Combat.json
-- debug.provingAttribute), so a mission client never waits on crowd remotes.
function CrowdRenderer.Start(): ()
	if started or destroyed then
		return
	end
	local combatConfig = Catalog.GetCombatConfig()
	local attribute = if combatConfig ~= nil then combatConfig.debug.provingAttribute else nil
	if attribute == nil or Workspace:GetAttribute(attribute) ~= true then
		return
	end
	started = true

	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	folder = created
	template = buildTemplate()

	tuningConnection = Tuning.Changed:Connect(onTuningChanged)
	table.insert(connections, RunService.Heartbeat:Connect(step))
	task.spawn(wire)
end

function CrowdRenderer.Destroy(): ()
	if destroyed then
		return
	end
	destroyed = true
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	local tuningHandle = tuningConnection
	if tuningHandle ~= nil then
		tuningHandle:Disconnect()
		tuningConnection = nil
	end
	for _, entity in active do
		entity.model:Destroy()
	end
	for _, entity in pool do
		entity.model:Destroy()
	end
	table.clear(active)
	table.clear(pool)
	table.clear(byId)
	table.clear(moveParts)
	table.clear(moveFrames)
	moveCount = 0
	table.clear(burstEmitters)
	table.clear(burstColors)
	local source = template
	if source ~= nil then
		source:Destroy()
		template = nil
	end
	local root = folder
	if root ~= nil then
		root:Destroy()
		folder = nil
	end
end

-- Feet as drawn (reaction offsets and death flight included); nil once the body is gone.
function CrowdRenderer.GetPosition(id: number): Vector3?
	local entity = byId[id]
	if entity == nil or entity.samples == 0 then
		return nil
	end
	return entity.shown
end

function CrowdRenderer.GetBody(id: number): Model?
	local entity = byId[id]
	if entity == nil or entity.samples == 0 then
		return nil
	end
	return entity.model
end

function CrowdRenderer.GetHeight(id: number): number?
	local entity = byId[id]
	return if entity ~= nil then entity.height else nil
end

function CrowdRenderer.GetHpFraction(id: number): number?
	local entity = byId[id]
	return if entity ~= nil then entity.hpFraction else nil
end

-- Every living, drawn body: feet (interpolated, without reaction offsets), body radius, head
-- radius, height. Dying, dead-state and fading bodies are skipped so aim never locks a corpse.
-- The callback must not yield.
function CrowdRenderer.ForEach(callback: ForEachCallback): ()
	for _, entity in active do
		if entity.phase == "alive" and entity.samples > 0 and entity.state ~= "dead" then
			callback(entity.id, entity.position, entity.radius, entity.headRadius, entity.height)
		end
	end
end

-- direction: world direction of the hit (flattened; nil = away from the camera). strength: the
-- layer strength (feedback.enemyReaction or enemyFlash, times any per-weapon scale): 0 = off,
-- 1 = default, capped at MAX_STRENGTH.
function CrowdRenderer.React(
	id: number,
	reaction: Reaction,
	direction: Vector3?,
	strength: number
): ()
	local entity = byId[id]
	if entity == nil or entity.samples == 0 or entity.phase ~= "alive" then
		return
	end
	if strength ~= strength then
		return
	end
	local power = math.clamp(strength, 0, MAX_STRENGTH)
	if reaction == "death" then
		startDeath(entity, reactionDirection(entity, direction), power)
		return
	end
	if power <= 0 then
		return
	end
	local now = os.clock()
	if reaction == "flash" then
		entity.flashUntil = now + FLASH_SECONDS * math.clamp(power, 0.5, 2)
		if not entity.flashing then
			paint(entity, true)
		end
	elseif reaction == "flinch" then
		entity.flinchStart = now
		entity.flinchStrength = power * math.max(entity.knockbackMult, FLINCH_MIN_KIND_SCALE)
		entity.flinchDir = reactionDirection(entity, direction)
	elseif reaction == "knockback" then
		local push = power * entity.knockbackMult
		if push > 0 then
			entity.knockStart = now
			entity.knockVector = reactionDirection(entity, direction) * (KNOCKBACK_STUDS * push)
		end
	elseif reaction == "launch" then
		local push = power * entity.knockbackMult
		if push > 0 then
			local along = reactionDirection(entity, direction)
			entity.launchStart = now
			entity.launchHeight = LAUNCH_STUDS * push
			entity.launchAxis = UP:Cross(along)
			entity.launchAngle = LAUNCH_TILT * math.min(push, 1.5)
		end
	end
end

return CrowdRenderer
