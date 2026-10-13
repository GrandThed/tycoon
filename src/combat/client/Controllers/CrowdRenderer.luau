--!strict
-- Draws the Proving Grounds crowd (docs/INTERFACES.md "P1 contracts", decision 1 and the
-- Feedback layers bullet; docs/COMBAT_DESIGN.md sections 4 and 7). The server simulates crowd
-- enemies as plain records; this module is the only place they become visible.
--
-- Rules that shape the module:
-- * Bodies are pooled placeholder figures (legs, torso, a bright head = the crit point, a visor
--   that shows facing and glows on wind-up). A spawn never creates an Instance in steady state:
--   the pool is pre-warmed over a few frames, to the bench's crowd.maxAlive in the range and to
--   the mission's own in a mission (Prewarm).
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
-- * P4 (docs/INTERFACES.md "P4 contracts": "State timing", "Codec v2" and the rule "Tells are
--   drawn against server time"). Codec v2 names the attack an enemy is in the middle of, and
--   its three states are drawn on the SERVER clock, not on the delayed clock the positions use.
--   The first packet that shows a windup is stamped with its start, so the impact is that
--   stamp plus the attack's windup, exactly; only when the packet before it was lost is the
--   start taken as one step after the enemy's previous sighting, the earliest it can have
--   been, so the blow is never shown later than the server's. From there the attack runs on
--   this client's own clock (windup, the blow at the impact, recover after the strike) and
--   the wire only corrects it: a recover that arrives before the blow was a cancelled windup,
--   and the thrust is taken back. A stagger or a hop shows over an attack; the attack index
--   in that packet says whether it still runs underneath (set) or is over (0).
--   A fodder's tell is its body alone: pose and colour, never an Instance. The elite's `arc`
--   also lays a pooled wedge on the floor (its reach and angle, along the locked facing) whose
--   fill grows to its outline at the impact. Tells are information, so nothing here thins them
--   on reducedMotion or lowEndDevice; a low-end device only gets a coarser wedge. Their numbers
--   come from the kind's `attacks` and crowd.threat; their look from Theme.COMBAT_RANGE_TELL_*.
-- * P4 wave 2 ("Wave 2 — roles"). The other four shapes are drawn by ThreatFx: a lane and a
--   line from the clock kept here (ForEachThreat), a shot and a lob from their own effects.
--   What stays here is the body:
--   - each fighting role wears one cheap shape cue (ThreatFx/Cues: a slinger's orb, a
--     marksman's barrel, a lobber's pack, a brute's horns, the elite's shell), a few pooled
--     parts on those few bodies and none on fodder; a shooter's lit piece swells and reddens
--     through its windup, which is its whole tell before it fires;
--   - the plate: a shell while the wire says `plated`, a two-row bar over the head (the plate
--     running down, then the health), a burst when it breaks, and the reel that follows drawn
--     as the opening it is;
--   - a lane's charge is drawn on the server clock, ahead of its own delayed snapshots
--     (stepRush), because at that speed "a snapshot behind" is several studs and the server
--     hits where the brute is.
-- * P4 Stop 2 ("Stop 2 — the Colossus"). A kind with `boss` is tracked for the boss bar
--   (GetBoss), wears a boss's cue set and breathes. Its second phase is read off the health
--   share the wire already carries and latched as the server latches it (pushSample): from
--   then on its colours are turned, its crown is lit, it heaves, and every attack it starts
--   runs on the scaled windup and recover. Chained attacks need nothing: the wire goes from
--   one attack's blow straight to the next one's windup, and each attack runs its own clock.
--   The slam's ring and the call's circle are ThreatFx's (ForEachThreat); the slam and the
--   call themselves are poses here; a body the call raised comes up through the floor.
-- * P4 Stop 3 ("Stop 3 — the Warlord and his guard"). A boss with `guarded` is a commander:
--   its own cue set, and a plate its guard protects. Who guards it and whether they live is
--   read in one place (isWardOf / wardsOf, off the `summonerId` each summoned body is
--   announced with); from that come the ward its shell is drawn as, the tethers
--   (ForEachWard) and the pips on its bar (GetBoss). The word a hit on it earns comes
--   with the hit itself. Its second phase begins when its plate breaks (`enrage.at` 1, the
--   same latch), and from then it fights with `enrage.brain`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local CrowdCodec = require(sharedFolder:WaitForChild("CrowdCodec"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
-- P4 wave 2: what hangs on a body. Children of ThreatFx (never ThreatFx itself, which
-- requires this module).
local Cues = require(script.Parent:WaitForChild("ThreatFx"):WaitForChild("Cues"))
local PlateBar = require(script.Parent:WaitForChild("ThreatFx"):WaitForChild("PlateBar"))

-- "block" (P4 wave 2): a plate turned the hit. Nothing moves; the shell glints.
export type Reaction = "flash" | "flinch" | "knockback" | "launch" | "death" | "block"
export type ForEachCallback = (
	id: number,
	position: Vector3,
	radius: number,
	headRadius: number,
	height: number
) -> ()
-- P4 wave 2: one body's lane or line, for ThreatFx to draw. `striking` = its blow is under way
-- (the charge, the shot); phaseAt = the server time that phase began; impactAt = the end of
-- its windup; origin = the body's floor point (where the charge began, once it has); yaw =
-- the facing the attack runs along (the wire's latest for a line, which follows its target
-- until the lock). Stop 2: a ring's and a summon's `range` is the circle's radius, a ring's
-- `width` the thickness of its front, and `speed` what a lane or a ring's front moves at.
export type ThreatCallback = (
	id: number,
	shape: string,
	striking: boolean,
	phaseAt: number,
	impactAt: number,
	origin: Vector3,
	yaw: number,
	range: number,
	width: number,
	lockSeconds: number,
	strikeSeconds: number,
	speed: number
) -> ()
-- Stop 3: one tether (ForEachWard): a living guard, and the chests of it and of the boss whose
-- plate it protects.
export type WardCallback = (guardId: number, guardChest: Vector3, bossChest: Vector3) -> ()
-- Stop 3: the boss as its bar shows it (GetBoss). health = its health share, 0 once it is
-- dead; plate = its plate's share, -1 for a kind with no plate; enrageAt = the health share
-- its second phase begins at (0 = it has none); label = what that phase is called on the bar;
-- guards / guardTotal = how many of the guard it calls live, and how many it calls; guarded =
-- its plate cannot be touched now, because one of them lives.
export type BossInfo = {
	id: number,
	name: string,
	health: number,
	plate: number,
	enrageAt: number,
	enraged: boolean,
	label: string,
	guards: number,
	guardTotal: number,
	guarded: boolean,
}

type Phase = "alive" | "dying" | "vanish"
-- P4: the part of an attack being drawn ("none" = no attack, or one the config does not have).
type Threat = "none" | "windup" | "attack" | "recover"

-- The elite's ground tell: a flat wedge on the arena floor. `edge` outlines the whole reach
-- from the first frame (one bar per slice of the rim, two more for the sides); `fill` is two
-- wedges per slice and grows from the body to that outline. centre / fillRadius / laid and the
-- two shown transparencies are what was last written, so a frame writes only what changed.
type Tell = {
	fill: { BasePart },
	edge: { BasePart },
	slices: number,
	centre: Vector3,
	fillRadius: number,
	laid: boolean,
	fillShown: number,
	edgeShown: number,
}

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

	-- P4 threat (codec v2). attack = the wire's index into the kind's `attacks`, 0 = none;
	-- plated = its plate is still on (hpFraction is then the plate's share, not the health's).
	attack: number,
	plated: boolean,
	-- Wave 2, what hangs on the body: its role cue pieces, the plate's bar (kinds with a plate
	-- only), how far a windup has charged the lit piece (0-1), when the plate broke and when
	-- it last turned a hit (os.clock), and until when the body reels from the break (server
	-- time, 0 = it is not reeling; the reel then holds on while the wire still says stagger;
	-- `reeling` = that pose's dull tint is on and must be taken off again).
	cues: Cues.CueSet?,
	bar: PlateBar.Bar?,
	charge: number,
	breakAt: number,
	glintAt: number,
	reelUntil: number,
	reeling: boolean,
	-- The attack as drawn: `threat` is its phase on this client's clock and threatAt the server
	-- time that phase began; impactAt = the end of its windup. threatOpen = that windup's clock
	-- is running and the wire has not shown its attack or recover yet; threatAttack = the index
	-- the numbers below were read for.
	threat: Threat,
	threatAt: number,
	impactAt: number,
	threatOpen: boolean,
	threatAttack: number,
	threatShape: string,
	windupSeconds: number,
	strikeSeconds: number,
	recoverSeconds: number,
	-- lunge: studs the figure jabs forward; arc: the wedge's radius, its angle in radians and
	-- the facing the windup locked. Wave 2: a lane's or a line's length, its width, and a
	-- line's lock time; threatOrigin = the floor point the attack is thrown from (the body's
	-- newest position through the windup, frozen once the blow starts).
	threatReach: number,
	threatArc: number,
	threatYaw: number,
	threatWidth: number,
	threatLock: number,
	threatSpeed: number,
	threatOrigin: Vector3,
	tell: Tell?,
	-- A lane's charge is drawn on the server clock, ahead of the delayed snapshots: `rush` is
	-- what that adds to the sampled position, rushTarget the lane's end, and until
	-- rushHoldUntil (server time) the body waits there for its snapshots to arrive.
	rush: Vector3,
	rushTarget: Vector3,
	rushHoldUntil: number,
	-- Recover. walks = the kind keeps its distance (brain keepAway), so it walks through its
	-- recover instead of standing spent; stride = how much of the slump that walking has lifted
	-- (0-1, eased). recoverFrom = the server time a recover began that a stagger or a hop is
	-- showing over (0 = none), for when the wire shows the rest of it.
	walks: boolean,
	stride: number,
	recoverFrom: number,
	-- Stop 2. boss = the kind has the boss bar (and a boss's cue set, and breathes); title =
	-- the name that bar shows. enrageAt = the health share its second phase begins at (0 = it
	-- has none); enraged = it is in it, for good: the look, and the scaled times of every
	-- attack that starts from then on. riseStart = os.clock() a summoned body began to come up
	-- through the floor.
	boss: boolean,
	title: string,
	enrageAt: number,
	enraged: boolean,
	riseStart: number,
	-- Stop 3, the guard. phaseLabel = what the bar calls this boss's second phase. guards =
	-- this kind is the guard some boss calls (it carries the pennant). guardKind / guardTotal
	-- = for a kind whose plate its guard protects, the kind it calls and how many; "" = none.
	-- summonerId = the crowd id of the boss that called this body, 0 for a set's own.
	-- wards = how many of the bodies it called live now; called = this client has seen one
	-- of them; opened = a hit on it has come back without the guard's flag, so it is
	-- unguarded here until it calls again. warded = its plate is on and cannot be touched (the shell is
	-- drawn as a ward, and the tethers are up). plateMax = the kind has a plate.
	phaseLabel: string,
	guards: boolean,
	guardKind: string,
	guardTotal: number,
	summonerId: number,
	wards: number,
	called: boolean,
	opened: boolean,
	warded: boolean,
	plateMax: number,
	-- Body tint: how far the kind's own colours are taken toward tintColor (a few fixed steps),
	-- and neon for the instant of the blow.
	tint: number,
	tintColor: Color3,
	glow: boolean,

	dirty: boolean,
	lastShown: Vector3,
	lastYaw: number,
	lastLean: Vector3,
	lastTumble: number,
	lastSquash: number,
	lastTuck: number,
	index: number,
}

-- The crowd's floor: its top centre and its half extents in X and Z (nil = unknown).
type Floor = { centre: Vector3, half: Vector3? }

local FOLDER_NAME = "CrowdBodies"
-- The wire's origin is the world origin, for good (L1 ruling 12): CrowdService encodes every
-- snapshot against it wherever the crowd's floor is, and this decodes against it. Until L1 this
-- one constant was also the floor's height (a tell's, a threat origin's) and the centre a
-- charge is bounded round; those three now read `floor`, which the server tells (SetFloor).
local WIRE_ORIGIN = Vector3.zero

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
-- P4 ground tells, pooled whole: only the few elites of a set ever need one at a time.
local tellPool: { Tell } = {}

-- Reused every frame; entries past the live count are cleared so BulkMoveTo sees exact arrays.
local moveParts: { BasePart } = {}
local moveFrames: { CFrame } = {}
local moveCount = 0

local interval = 1 / 15
-- The packet being decoded, read by onEntry (a module function, so a snapshot allocates no
-- closure).
local decodeStamp = 0
local lagEstimate: number? = nil
local newestStamp = -math.huge
local burstsThisStep = 0
local burstEmitters: { [string]: ParticleEmitter } = {}
local burstColors: { [string]: Color3 } = {}
-- The crowd's floor as last told (SetFloor): its top centre, and its half extents in X and Z
-- (nil = unknown: nothing bounds a charge). A camp's floor in a level (L1 ruling 30), the
-- arena's in the range (SetArena). With no camp it is the world origin at height 0.
local floor: Floor = { centre = Vector3.zero, half = nil }
-- Stop 2: the boss the bar shows (the first one alive, kept through its death flight so the
-- bar can empty and go).
local bossEntity: Entity? = nil
-- Stop 3: what GetBoss hands out, the same table every frame.
local bossInfo: BossInfo = {
	id = 0,
	name = "",
	health = 0,
	plate = -1,
	enrageAt = 0,
	enraged = false,
	label = "",
	guards = 0,
	guardTotal = 0,
	guarded = false,
}
-- The crowd ids of the bosses that died or were taken away since ThreatFx last asked: a
-- boss's end takes back what that body had in the air, and its circles and shots are
-- ThreatFx's to drop.
local bossEnds: { number } = {}

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
		attack = 0,
		plated = false,
		cues = nil,
		bar = nil,
		charge = 0,
		breakAt = -math.huge,
		glintAt = -math.huge,
		reelUntil = 0,
		reeling = false,
		threat = "none",
		threatAt = 0,
		impactAt = 0,
		threatOpen = false,
		threatAttack = 0,
		threatShape = "",
		windupSeconds = 0,
		strikeSeconds = 0,
		recoverSeconds = 0,
		threatReach = 0,
		threatArc = 0,
		threatYaw = 0,
		threatWidth = 0,
		threatLock = 0,
		threatSpeed = 0,
		threatOrigin = Vector3.zero,
		tell = nil,
		rush = Vector3.zero,
		rushTarget = Vector3.zero,
		rushHoldUntil = 0,
		walks = false,
		stride = 0,
		recoverFrom = 0,
		boss = false,
		title = "",
		enrageAt = 0,
		enraged = false,
		riseStart = -math.huge,
		phaseLabel = "",
		guards = false,
		guardKind = "",
		guardTotal = 0,
		summonerId = 0,
		wards = 0,
		called = false,
		opened = false,
		warded = false,
		plateMax = 0,
		tint = 0,
		tintColor = FLASH_COLOR,
		glow = false,
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

-- The white hit flash wins; under it the kind's colours, taken toward the attack's tint. The
-- head goes half as far, so the crit point still reads as the crit point.
local function paint(entity: Entity, flash: boolean): ()
	local material = if flash or entity.glow then FLASH_MATERIAL else BODY_MATERIAL
	local tint = entity.tint
	if flash then
		entity.legs.Color = FLASH_COLOR
		entity.torso.Color = FLASH_COLOR
		entity.head.Color = FLASH_COLOR
	elseif tint > 0 then
		entity.legs.Color = entity.legColor:Lerp(entity.tintColor, tint)
		entity.torso.Color = entity.bodyColor:Lerp(entity.tintColor, tint)
		entity.head.Color = entity.headColor:Lerp(entity.tintColor, tint * 0.5)
	else
		entity.legs.Color = entity.legColor
		entity.torso.Color = entity.bodyColor
		entity.head.Color = entity.headColor
	end
	entity.legs.Material = material
	entity.torso.Material = material
	entity.head.Material = material
	entity.flashing = flash
end

-- P4: tints the body toward `color` by `share` (0-1), in a few fixed steps so a whole windup
-- repaints a handful of times rather than every frame. A hit flash showing meanwhile keeps the
-- body; the tint is there when it ends.
local function setTint(entity: Entity, share: number, color: Color3, glow: boolean): ()
	local steps = Theme.COMBAT_RANGE_TELL_TINT_STEPS
	local tint = math.round(math.clamp(share, 0, 1) * steps) / steps
	if tint == entity.tint and glow == entity.glow and (tint == 0 or color == entity.tintColor) then
		return
	end
	entity.tint = tint
	entity.tintColor = color
	entity.glow = glow
	if not entity.flashing then
		paint(entity, false)
	end
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
	local cues = entity.cues
	if cues ~= nil then
		Cues.Fade(cues, fade)
	end
end

-- P4 wave 2: takes the role cue and the plate's bar off a body (it is leaving, or its kind's
-- numbers changed and both are about to be put on again).
local function undress(entity: Entity): ()
	local cues = entity.cues
	if cues ~= nil then
		entity.cues = nil
		Cues.Detach(cues)
	end
	local bar = entity.bar
	if bar ~= nil then
		entity.bar = nil
		PlateBar.Give(bar)
	end
end

-- The plate's bar: the plate's share while it is on (the wire's one fraction is the plate's
-- then, and health cannot change under it), the health's after.
local function showBar(entity: Entity): ()
	local bar = entity.bar
	if bar ~= nil then
		if entity.plated then
			PlateBar.Set(bar, entity.hpFraction, 1)
		else
			PlateBar.Set(bar, 0, entity.hpFraction)
		end
	end
end

local function newTellPart(wedge: boolean, parent: Instance): BasePart
	local part: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	part.Name = "CrowdTell"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = FLASH_MATERIAL
	part.Color = Theme.COMBAT_RANGE_TELL_COLOR
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A ground tell for a wedge of `slices` slices, `radius` out and `arc` radians wide: from the
-- pool, grown if this wedge needs more parts than its last one. Everything comes out hidden;
-- the outline is sized here once, the fill each time it grows.
local function takeTell(parent: Instance, slices: number, radius: number, arc: number): Tell
	local tell: Tell = table.remove(tellPool)
		or {
			fill = {},
			edge = {},
			slices = 0,
			centre = Vector3.zero,
			fillRadius = 0,
			laid = false,
			fillShown = 1,
			edgeShown = 1,
		}
	while #tell.fill < slices * 2 do
		table.insert(tell.fill, newTellPart(true, parent))
	end
	while #tell.edge < slices + 2 do
		table.insert(tell.edge, newTellPart(false, parent))
	end
	tell.slices = slices
	tell.laid = false
	tell.fillRadius = 0
	local width = Theme.COMBAT_RANGE_TELL_EDGE_WIDTH
	local height = Theme.COMBAT_RANGE_TELL_EDGE_HEIGHT
	-- Half a width longer than the chord, so neighbouring bars close the rim's corners.
	local rim = Vector3.new(width, height, 2 * radius * math.sin(arc / slices * 0.5) + width * 0.5)
	for index = 1, slices do
		tell.edge[index].Size = rim
	end
	local side = Vector3.new(width, height, radius)
	tell.edge[slices + 1].Size = side
	tell.edge[slices + 2].Size = side
	return tell
end

local function releaseTell(entity: Entity): ()
	local tell = entity.tell
	if tell == nil then
		return
	end
	entity.tell = nil
	for _, part in tell.fill do
		part.Transparency = 1
	end
	for _, part in tell.edge do
		part.Transparency = 1
	end
	tell.fillShown = 1
	tell.edgeShown = 1
	table.insert(tellPool, tell)
end

-- P4: sets the phase of the attack being drawn (`at` = the server time it began). The ground
-- tell belongs to the windup and the blow of an arc; the visor is hot through both and cold
-- in recover; "none" hands the body back to its kind's colours and the P1 visor rule.
local function setThreat(entity: Entity, threat: Threat, at: number): ()
	entity.threat = threat
	entity.threatAt = at
	entity.dirty = true
	-- Every phase starts with the body standing where the last one left it.
	entity.stride = 0
	local parent = folder
	local wantsTell = (threat == "windup" or threat == "attack")
		and entity.threatShape == "arc"
		and entity.threatReach > 0
		and entity.threatArc > 0
	if not wantsTell then
		releaseTell(entity)
	elseif entity.tell == nil and parent ~= nil then
		local degrees = if Theme.lowEndDevice
			then Theme.COMBAT_RANGE_TELL_LOW_END_SEGMENT_DEGREES
			else Theme.COMBAT_RANGE_TELL_SEGMENT_DEGREES
		local slices = math.max(math.ceil(entity.threatArc / math.rad(degrees)), 1)
		entity.tell = takeTell(parent, slices, entity.threatReach, entity.threatArc)
	end
	if threat ~= "windup" then
		-- Wave 2: a shooter's lit piece is charged only while the windup runs. The shot
		-- leaving, a cancel and the end all leave it spent at once.
		entity.charge = 0
	end
	if threat == "none" then
		setTint(entity, 0, FLASH_COLOR, false)
		setVisorHot(entity, entity.state == "windup")
	else
		setVisorHot(entity, threat ~= "recover")
	end
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

	-- Stop 2: what makes a boss a boss, and its second phase. Enraged, the body's own colours
	-- move toward hot red for good, so every tint laid over them (a windup's heat, the spent
	-- dullness) still reads against them.
	local enrage = def.enrage
	entity.boss = def.boss == true
	entity.title = def.name or entity.kind
	-- Stop 3: who guards whom, read off the config and never off a name. A kind with
	-- `guarded` is protected by whatever it summons; a kind some such boss summons is a guard.
	entity.guardKind = ""
	entity.guardTotal = 0
	entity.guards = false
	entity.plateMax = math.max(def.plate or 0, 0)
	for name, other in Tuning.Get().crowd.kinds do
		if other.guarded == true and other.attacks ~= nil then
			for _, attack in other.attacks do
				if attack.shape == "summon" and attack.summon ~= nil then
					if attack.summon == entity.kind then
						entity.guards = true
					end
					if name == entity.kind then
						entity.guardKind = attack.summon
						entity.guardTotal = math.max(math.floor(attack.count or 0), 0)
					end
				end
			end
		end
	end
	-- The bar's word for the second phase. For a boss with a guard that phase is the turn
	-- from siege to duel; any other boss is enraged.
	entity.phaseLabel = if entity.guardKind ~= ""
		then Theme.COMBAT_RANGE_BOSS_BAR_DUEL_LABEL
		else Theme.COMBAT_RANGE_BOSS_BAR_ENRAGED_LABEL
	entity.enrageAt = if enrage ~= nil then math.clamp(enrage.at, 0, 1) else 0
	if entity.enrageAt <= 0 then
		entity.enraged = false
	end
	local base = colorOf(def.color)
	if entity.enraged then
		base = base:Lerp(Theme.COMBAT_RANGE_ENRAGE_COLOR, Theme.COMBAT_RANGE_ENRAGE_SHARE)
	end
	entity.bodyColor = base
	entity.legColor = base:Lerp(LEG_SHADE, LEG_SHADE_SHARE)
	entity.headColor = base:Lerp(HEAD_TINT, HEAD_TINT_SHARE)
	paint(entity, entity.flashing)
	entity.dirty = true

	-- Wave 2: the role's shape cue (none for a kind that only lunges or never fights) and,
	-- for a kind with a plate, the bar over its head. Both are measured against the figure
	-- above, so they are put on again whenever it changes.
	undress(entity)
	entity.cues = Cues.Attach(
		entity.model,
		def,
		radius,
		height,
		legHeight,
		torsoHeight,
		headRadius,
		entity.torsoSize,
		base,
		entity.enraged,
		entity.guards
	)
	-- A boss's plate is on the boss bar; a second bar over its head would only repeat it.
	if (def.plate or 0) > 0 and not entity.boss and entity.phase == "alive" then
		entity.bar = PlateBar.Take(entity.head, headRadius + Theme.COMBAT_RANGE_PLATE_BAR_RISE)
		showBar(entity)
	end
	local cues = entity.cues
	if cues ~= nil then
		Cues.Fade(cues, entity.fade)
	end
end

-- Stop 3: is `other` one of the bodies `boss` called, alive? This and wardsOf are the one
-- place that knows who guards a boss now. The wire says it: every summoned body is
-- announced with its summoner's crowd id, late joiners included.
local function isWardOf(boss: Entity, other: Entity): boolean
	return other.summonerId == boss.id
		and other.phase == "alive"
		and other.samples > 0
		and other.state ~= "dead"
end

-- Stop 3: how many of its guard live now (0 for a kind nobody guards).
local function wardsOf(boss: Entity): number
	if boss.guardKind == "" then
		return 0
	end
	local count = 0
	for _, other in active do
		if isWardOf(boss, other) then
			count += 1
		end
	end
	return count
end

-- Stop 2: a body that is gone stops being the boss the bar shows; another living boss, if
-- the set has one, takes its place.
local function untrackBoss(entity: Entity): ()
	if bossEntity ~= entity then
		return
	end
	bossEntity = nil
	for _, other in active do
		if other ~= entity and other.boss and other.phase == "alive" then
			bossEntity = other
			return
		end
	end
end

local function release(entity: Entity): ()
	untrackBoss(entity)
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
	entity.threatOpen = false
	setThreat(entity, "none", 0)
	undress(entity)
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

-- summonerId = the crowd id of the boss that called this body, 0 for a set's own.
local function spawnEntity(id: number, kind: string, maxHp: number, summonerId: number): ()
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
			existing.summonerId = summonerId
			applyKind(existing, def)
			if existing.boss and bossEntity == nil then
				bossEntity = existing
			end
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
	entity.attack = 0
	entity.plated = false
	entity.charge = 0
	entity.breakAt = -math.huge
	entity.glintAt = -math.huge
	entity.reelUntil = 0
	entity.reeling = false
	entity.rush = Vector3.zero
	entity.rushHoldUntil = 0
	entity.recoverFrom = 0
	entity.enraged = false
	entity.riseStart = -math.huge
	entity.summonerId = summonerId
	entity.wards = 0
	entity.called = false
	entity.opened = false
	entity.warded = false
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
	-- Stop 3: a fresh body a boss called. If a hit had told this client that boss was
	-- unguarded, that is over: a guard that can be called again guards again. (One that is
	-- called once never gets here twice.)
	local summoner = if summonerId ~= 0 then byId[summonerId] else nil
	if summoner ~= nil then
		summoner.opened = false
	end
	local shown = bossEntity
	if entity.boss and (shown == nil or shown.phase ~= "alive") then
		-- A fresh boss takes the bar, also from one still in its death flight.
		bossEntity = entity
	end
	-- Parented on its first snapshot, so it never flashes up at the pool's last pose.
end

-- A body that stops being alive stops attacking: its tint, its glow and its ground tell go.
-- So do the plate's bar (a corpse has nothing left to read) and whatever its charge had been
-- drawn ahead of its snapshots.
local function dropThreat(entity: Entity): ()
	entity.threatOpen = false
	if entity.threat ~= "none" then
		setThreat(entity, "none", 0)
	end
	if entity.boss and table.find(bossEnds, entity.id) == nil then
		-- Stop 2: noted for ThreatFx (DrainBossEnds), by body, so another boss of the same
		-- kind keeps what it has in the air.
		table.insert(bossEnds, entity.id)
	end
	entity.rush = Vector3.zero
	entity.rushHoldUntil = 0
	entity.reelUntil = 0
	entity.recoverFrom = 0
	local bar = entity.bar
	if bar ~= nil then
		entity.bar = nil
		PlateBar.Give(bar)
	end
end

local function startVanish(entity: Entity): ()
	dropThreat(entity)
	-- Taken away, not killed: the boss bar has nothing to show an ending for.
	untrackBoss(entity)
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
	dropThreat(entity)
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

-- P4: reads the numbers of the attack the wire names into the entity, once per attack, when
-- its first state is seen. False = the config has no such attack: nothing is drawn for it
-- beyond the P1 look (a hot visor and a fixed lean while the wire says windup).
local function loadThreat(entity: Entity): boolean
	local kind = kindDef(entity.kind)
	local attacks = if kind ~= nil then kind.attacks else nil
	local attack = if attacks ~= nil and entity.attack > 0 then attacks[entity.attack] else nil
	if attack == nil then
		return false
	end
	local threat = Tuning.Get().crowd.threat
	local range = math.max(attack.range or 0, 0)
	local speed = attack.speed or 0
	entity.threatAttack = entity.attack
	entity.threatShape = attack.shape
	-- Stop 3: the brain it fights with now. A commander who kept his distance closes in once
	-- enraged, and a body that closes in stands spent through its recover.
	local turned = if kind ~= nil and entity.enraged then kind.enrage else nil
	local brain = if turned ~= nil and turned.brain ~= nil
		then turned.brain
		elseif kind ~= nil then kind.brain
		else nil
	entity.walks = brain == "keepAway"
	-- Stop 2: an attack that starts in the enraged phase runs on the scaled times. The phase
	-- is the one this body was in when the attack's first state was seen (pushSample latches
	-- it before this runs), as the server takes it when the attack starts.
	local enrage = if kind ~= nil and entity.enraged then kind.enrage else nil
	entity.windupSeconds = math.max(attack.windup, 0)
		* (if enrage ~= nil then math.max(enrage.windupScale, 0) else 1)
	entity.recoverSeconds = math.max(attack.recover, 0)
		* (if enrage ~= nil then math.max(enrage.recoverScale, 0) else 1)
	-- "State timing": a lane's attack state lasts its charge, every other shape's the shared
	-- strike time.
	entity.strikeSeconds = if attack.shape == "lane" and speed > 0
		then range / speed
		elseif threat ~= nil then math.max(threat.strikeSeconds, 0)
		else 0
	entity.threatYaw = entity.yawC
	entity.threatOrigin = Vector3.new(entity.posC.X, floor.centre.Y, entity.posC.Z)
	entity.threatWidth = math.max(attack.width or 0, 0)
	entity.threatLock = math.max(attack.lockSeconds or 0, 0)
	entity.threatSpeed = math.max(speed, 0)
	entity.threatArc = 0
	if attack.shape == "lunge" then
		-- `range` is measured from the body's centre: the figure jabs a share of what lies
		-- beyond its own front. A visual offset only; the real position is the snapshot's.
		entity.threatReach = math.max(range - entity.radius, 0)
			* Theme.COMBAT_RANGE_TELL_LUNGE_SHARE
	elseif attack.shape == "arc" then
		entity.threatReach = range
		entity.threatArc = math.rad(math.clamp(attack.arcDegrees or 360, 0, 360))
	elseif attack.shape == "lane" or attack.shape == "line" then
		-- Wave 2: the charge's length, the shot's length. ThreatFx draws both on the floor.
		entity.threatReach = range
	elseif attack.shape == "ring" or attack.shape == "summon" then
		-- Stop 2: how far the slam's front runs; the circle the summoned rise on. ThreatFx
		-- draws both (threatWidth is then the front's thickness, threatSpeed its speed).
		entity.threatReach = math.max(attack.radius or 0, 0)
	else
		entity.threatReach = 0
	end
	return true
end

-- P4: the first sighting of an attack whose windup is (or may be) still running: its clock
-- starts here. The server sets `windup` in the very step the windup starts and stamps that
-- step's snapshot with its time, so with the snapshot before it in hand the start is `stamp`
-- exactly. When that snapshot was lost, the start is only known to lie after this enemy's
-- previous sighting: one step after it is the earliest it can have been, and timing the tell
-- from there never shows the impact later than the server's.
local function beginWindup(entity: Entity, stamp: number, previous: number): ()
	entity.recoverFrom = 0
	if not loadThreat(entity) then
		entity.threatOpen = false
		setThreat(entity, "none", stamp)
		return
	end
	local start = math.min(stamp, previous + interval)
	entity.threatOpen = true
	entity.impactAt = start + entity.windupSeconds
	setThreat(entity, "windup", start)
end

-- P4: the wire's state or attack index changed. `stamp` = that packet's server time;
-- `previous` = this enemy's sighting before it, which is the earliest a state the server
-- changed between two steps (the blow, the recover) can have begun. The drawn attack runs on
-- its own clock from its first sighting; here the wire starts it, confirms it, or corrects it.
local function followThreat(entity: Entity, stamp: number, previous: number): ()
	local state = entity.state
	-- The attack already being drawn, back on the wire after a stagger or a hop that showed
	-- OVER it (the last branch). Its clock never stopped, so nothing restarts.
	local drawn = entity.threat ~= "none" and entity.threatAttack == entity.attack
	if state == "windup" then
		-- A drawn attack already in recover has had its blow: this windup is the next one.
		if not (drawn and entity.threatOpen and entity.threat ~= "recover") then
			beginWindup(entity, stamp, previous)
		end
	elseif state == "attack" then
		if entity.threatOpen then
			-- The blow the windup built to. This clock is already there unless the windup's
			-- start had to be estimated from a late sighting; then it starts here.
			entity.threatOpen = false
			if entity.threat == "windup" then
				setThreat(entity, "attack", math.min(entity.impactAt, previous))
			end
		elseif drawn then
			return
		elseif loadThreat(entity) then
			setThreat(entity, "attack", previous)
		else
			setThreat(entity, "none", stamp)
		end
	elseif state == "recover" then
		local threat = entity.threat
		local open = entity.threatOpen
		entity.threatOpen = false
		if drawn and threat == "attack" and entity.threatShape == "lane" then
			-- A charge this clock still has running, which the wire says is over. The wire is
			-- the authority on that: the body is where its snapshots put it, so the charge ends
			-- here and its lead over them is let go.
			entity.rushHoldUntil = 0
			setThreat(entity, "recover", previous)
		elseif open then
			-- Ruling 9: a cancelled windup goes straight to recover. A recover that arrives
			-- before the blow, or inside the first half of a strike this clock began on its
			-- own, is that: the blow never fell, so the thrust is taken back.
			if
				threat == "windup"
				or (threat == "attack" and stamp < entity.threatAt + entity.strikeSeconds * 0.5)
			then
				setThreat(entity, "recover", previous)
			end
		elseif threat == "none" and loadThreat(entity) then
			-- A recover seen from nothing. After a stagger or a hop that showed over it (a hit
			-- that cancelled the windup, a plate break and its reel) this is what is left of it,
			-- timed from where it began, so the body wakes when the server's does. Otherwise it
			-- began after the previous sighting.
			local from = entity.recoverFrom
			setThreat(entity, "recover", if from > 0 then from else previous)
		end
		entity.recoverFrom = 0
	else
		-- A stagger or a hop shows OVER the attack's state, and the wire says what goes on
		-- under it: the attack index stays set while that windup or blow is still running (an
		-- elite's arc lands on time even mid-hop, so its tell must not blink out for a shove)
		-- and is 0 once it was cancelled or is over. Set: the attack goes on being drawn on
		-- its clock, or starts if this is its first sighting. 0: the tell and any thrust not
		-- yet thrown are dropped at once; only a body already spent keeps its slump, which
		-- warns of nothing.
		local overlaid = state == "stagger" or state == "airborne"
		if overlaid then
			if entity.attack > 0 then
				if not drawn then
					beginWindup(entity, stamp, previous)
				end
				return
			elseif entity.threat == "recover" then
				return
			end
		end
		if not overlaid then
			entity.recoverFrom = 0
		elseif entity.threat ~= "none" then
			-- A windup or a blow that was still on at the previous sighting and is off under
			-- this stagger or hop: the server put the body in recover in between. Should that
			-- recover outlast what shows over it, the wire names it then.
			entity.recoverFrom = previous
		end
		entity.threatOpen = false
		setThreat(entity, "none", stamp)
	end
end

local function pushSample(
	entity: Entity,
	position: Vector3,
	yaw: number,
	state: Types.CrowdState,
	hpFraction: number,
	plated: boolean,
	attack: number,
	stamp: number
): ()
	local first = entity.samples == 0
	if first then
		entity.posA, entity.posB, entity.posC = position, position, position
		entity.yawA, entity.yawB, entity.yawC = yaw, yaw, yaw
		entity.timeA, entity.timeB, entity.timeC = stamp, stamp, stamp
		entity.samples = 1
		entity.position = position
		entity.shown = position
		entity.yaw = yaw
		entity.dirty = true
		entity.model.Parent = folder
		-- A body a boss called (it was announced with its summoner's id) comes up through
		-- the floor instead of appearing. A client that joins later sees those already
		-- standing rise once, as its first sight of them.
		if entity.summonerId ~= 0 then
			entity.riseStart = os.clock()
			burstAt(entity, 1)
		end
	elseif stamp > entity.timeC then
		entity.posA, entity.yawA, entity.timeA = entity.posB, entity.yawB, entity.timeB
		entity.posB, entity.yawB, entity.timeB = entity.posC, entity.yawC, entity.timeC
		entity.posC, entity.yawC, entity.timeC = position, yaw, stamp
		entity.samples = math.min(entity.samples + 1, 3)
	else
		return
	end
	-- This enemy's sighting before this one (the ring has just been shifted). A body seen for
	-- the first time has none, and nothing says how long it has been doing what it is doing:
	-- it is timed as if that began one step ago, which is a guess. A windup that was already
	-- under way therefore shows its blow late, by up to its windup less a step, until the
	-- wire's `attack` state starts the thrust instead. Only a player who joins mid-fight can
	-- meet this, and it is accepted (contract ruling 25).
	local previous = if entity.samples > 1 then entity.timeB else stamp - 2 * interval
	if plated ~= entity.plated or hpFraction ~= entity.hpFraction then
		if entity.plated and not plated then
			-- Wave 2: the plate broke. The shell bursts, and the body reels for
			-- crowd.plateBreakSeconds from the hit that did it, which fell after the previous
			-- sighting: the opening is drawn from there, so it never outlasts the server's.
			entity.breakAt = os.clock()
			-- Stop 3: only a body the wire shows staggered (or thrown up) by that hit reels. One
			-- that cannot be staggered goes straight on, and so does its drawing.
			if state == "stagger" or state == "airborne" then
				entity.reelUntil = previous + math.max(Tuning.Get().crowd.plateBreakSeconds or 0, 0)
			end
			entity.dirty = true
			-- Shards, where the device can afford particles; the shell's own burst (Cues) and
			-- the reel carry the break without them.
			burstAt(entity, 1)
		end
		entity.plated = plated
		entity.hpFraction = hpFraction
		showBar(entity)
	end
	-- Stop 2: the second phase is read off the health share already on the wire. The server
	-- enters it, for good, at the first moment the share is at or under `enrage.at` and the
	-- body is not in a windup or a blow; that is latched here the same way, on the wire's own
	-- states. It runs before the state below is followed, so an attack whose first state rides
	-- in this packet already takes the scaled times.
	if
		entity.enrageAt > 0
		and not entity.enraged
		and not plated
		and state ~= "dead"
		and hpFraction <= entity.enrageAt
	then
		local wasBusy = entity.state == "windup"
			or entity.state == "attack"
			or ((entity.state == "stagger" or entity.state == "airborne") and entity.attack > 0)
		local isBusy = state == "windup"
			or state == "attack"
			or ((state == "stagger" or state == "airborne") and attack > 0)
		if first or not (wasBusy and isBusy) then
			entity.enraged = true
			local def = kindDef(entity.kind)
			if def ~= nil then
				applyKind(entity, def)
				local phase = def.enrage
				if
					phase ~= nil
					and state == "recover"
					and entity.state ~= "recover"
					and entity.threat ~= "none"
				then
					-- It crossed during the attack that has just ended. The server asks the
					-- question again as that attack ends, so the recover that follows is
					-- already the scaled one, though this attack was loaded unscaled.
					entity.recoverSeconds *= math.max(phase.recoverScale, 0)
				end
			end
			if not first then
				-- The beat on the body itself: a white flash and a burst as its colours turn.
				-- A client that first sees it already enraged gets the look and no beat.
				entity.flashUntil = os.clock() + FLASH_SECONDS * 3
				paint(entity, true)
				burstAt(entity, 2)
			end
		end
	end
	if state ~= entity.state or attack ~= entity.attack then
		entity.state = state
		entity.attack = attack
		followThreat(entity, stamp, previous)
		entity.dirty = true
		if state == "dead" and entity.deathDue == math.huge then
			entity.deathDue = os.clock() + DEATH_WAIT_SECONDS
			if entity.boss and table.find(bossEnds, entity.id) == nil then
				-- Dead on the wire: what it had in the air goes now, not when the body falls.
				table.insert(bossEnds, entity.id)
			end
		end
	end
	-- A body in windup is planted, but a hit can still shove it: its attack is thrown from
	-- where it stands now. Once the blow starts the floor point is frozen (a lane's charge
	-- moves the body away from it). A line's aim follows its target until the lock and is
	-- frozen after it (snapped to the wire's own step, so the wall drawn from it is the
	-- server's lane); the wire's yaw is that aim either way, through windup and blow. In
	-- recover the marksman turns to its target again, and that yaw is no longer the shot's: a
	-- recover snapshot that beats this clock to the end of the blow must not swing the wall.
	if entity.threat == "windup" then
		entity.threatOrigin = Vector3.new(position.X, floor.centre.Y, position.Z)
	end
	if
		entity.threatShape == "line"
		and state ~= "recover"
		and (entity.threat == "windup" or entity.threat == "attack")
	then
		entity.threatYaw = yaw
	end
end

-- CrowdCodec.DecodeEach callback: world coordinates as plain numbers, no table per entry.
-- Unknown ids (a snapshot that beat its CrowdSpawn) are ignored until announced.
local function onEntry(
	id: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	state: Types.CrowdState,
	hpFraction: number,
	plated: boolean,
	attack: number
): ()
	local entity = byId[id]
	if entity ~= nil and entity.phase == "alive" then
		pushSample(
			entity,
			Vector3.new(x, y, z),
			yaw,
			state,
			hpFraction,
			plated,
			attack,
			decodeStamp
		)
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
	-- Clamped exactly as CrowdService clamps its step, so a tuned 0 or 500 cannot desync the delay.
	local hz = if crowd ~= nil then crowd.snapshotHz else CrowdCodec.MIN_HZ
	if typeof(hz) ~= "number" or hz ~= hz or hz == math.huge or hz == -math.huge then
		hz = CrowdCodec.MIN_HZ
	end
	interval = 1 / math.clamp(hz, CrowdCodec.MIN_HZ, CrowdCodec.MAX_HZ)
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
	decodeStamp = stamp
	CrowdCodec.DecodeEach(packet, WIRE_ORIGIN, onEntry)
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
			local summoner = info.summonerId
			spawnEntity(
				info.id,
				info.kind,
				if typeof(info.maxHp) == "number" then info.maxHp else 0,
				if typeof(summoner) == "number" and summoner == summoner then summoner else 0
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
	-- What sits on the torso rides down (or up) with its top when it is squashed.
	local carried = root
	if entity.squash ~= 1 then
		local drop = entity.torsoHeight * (1 - entity.squash)
		moveFrames[n + 2] = root
			* CFrame.new(0, entity.legHeight + entity.torsoHeight * entity.squash * 0.5, 0)
		carried = root * CFrame.new(0, -drop, 0)
		moveFrames[n + 3] = carried * entity.headOffset
		moveFrames[n + 4] = carried * entity.visorOffset
	else
		moveFrames[n + 2] = root * entity.torsoOffset
		moveFrames[n + 3] = root * entity.headOffset
		moveFrames[n + 4] = root * entity.visorOffset
	end
	moveCount = n + 4
	-- Wave 2: the role's cue pieces (fodder have none). Stop 2: they ride with the head, so a
	-- boss's shoulders and crown come down with its slam instead of hanging over it.
	local cues = entity.cues
	if cues ~= nil then
		moveCount = Cues.Queue(cues, carried, moveParts, moveFrames, moveCount)
	end
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

-- P4: queues a ground tell's parts for a wedge of `radius` and `arc` radians about `yaw`,
-- centred on tell.centre, with its fill out to `reach`. `edges` = the outline moves too: the
-- first frame, a shoved body, and the blow, whose leading side crosses the wedge by `sweep`
-- (0-1). Each slice's fill is the triangle (centre, rim, rim) split down its middle into two
-- right-angled wedges.
local function layTell(
	tell: Tell,
	yaw: number,
	radius: number,
	arc: number,
	reach: number,
	edges: boolean,
	sweep: number
): ()
	local slices = tell.slices
	local centre = tell.centre
	local span = arc / slices
	local start = yaw - arc * 0.5
	local half = reach * math.sin(span * 0.5)
	local depth = reach * math.cos(span * 0.5)
	local size = Vector3.new(Theme.COMBAT_RANGE_TELL_THICKNESS, half, depth)
	local resize = math.abs(reach - tell.fillRadius) > SETTLE_EPSILON
	tell.fillRadius = reach
	local n = moveCount
	for index = 1, slices do
		local middle = start + span * (index - 0.5)
		local out = lookOf(middle)
		local side = Vector3.new(-math.cos(middle), 0, math.sin(middle))
		local chord = centre + out * depth
		local first = tell.fill[index * 2 - 1]
		local second = tell.fill[index * 2]
		if resize then
			first.Size = size
			second.Size = size
		end
		-- A wedge's right angle sits at its bottom back edge: bottom toward the centre, back
		-- along the rim. Its own centre is the middle of the slanted side.
		moveParts[n + 1] = first
		moveFrames[n + 1] = CFrame.fromMatrix((centre + chord + side * half) * 0.5, -UP, side, out)
		moveParts[n + 2] = second
		moveFrames[n + 2] = CFrame.fromMatrix((centre + chord - side * half) * 0.5, UP, -side, out)
		n += 2
	end
	if edges then
		for index = 1, slices do
			local from = centre + lookOf(start + span * (index - 1)) * radius
			local to = centre + lookOf(start + span * index) * radius
			moveParts[n + 1] = tell.edge[index]
			moveFrames[n + 1] = CFrame.lookAt((from + to) * 0.5, to, UP)
			n += 1
		end
		local leading = centre + lookOf(start + arc * sweep) * radius
		local trailing = centre + lookOf(start + arc) * radius
		moveParts[n + 1] = tell.edge[slices + 1]
		moveFrames[n + 1] = CFrame.lookAt((centre + leading) * 0.5, leading, UP)
		moveParts[n + 2] = tell.edge[slices + 2]
		moveFrames[n + 2] = CFrame.lookAt((centre + trailing) * 0.5, trailing, UP)
		n += 2
	end
	moveCount = n
end

-- P4: one frame of an arc's ground tell. Windup: the outline shows the whole reach and the
-- fill has grown `share` (0-1) of the way to it. The blow (`striking`, `u` = its progress): the
-- whole wedge at its brightest, one side sweeping across, fading out as the strike ends. The
-- wedge lies on the arena floor under the body's NEWEST position, not its delayed drawn one.
local function drawTell(entity: Entity, tell: Tell, share: number, striking: boolean, u: number): ()
	local at = entity.posC
	local centre = Vector3.new(at.X, floor.centre.Y + Theme.COMBAT_RANGE_TELL_LIFT, at.Z)
	local moved = not tell.laid or (centre - tell.centre).Magnitude > SETTLE_EPSILON
	if moved then
		tell.centre = centre
		tell.laid = true
	end
	local radius = entity.threatReach
	local least = Theme.COMBAT_RANGE_TELL_MIN_FILL
	local reach = radius * (least + (1 - least) * math.clamp(share, 0, 1))
	local sweep = if striking
		then smoothstep(math.min(u / Theme.COMBAT_RANGE_TELL_ARC_SWEEP_SHARE, 1))
		else 0
	if moved or striking or math.abs(reach - tell.fillRadius) > SETTLE_EPSILON then
		layTell(tell, entity.threatYaw, radius, entity.threatArc, reach, moved or striking, sweep)
	end
	local seen = if striking then 1 - u else 1
	local fillBase = if striking
		then Theme.COMBAT_RANGE_TELL_STRIKE_TRANSPARENCY
		else Theme.COMBAT_RANGE_TELL_FILL_TRANSPARENCY
	local fill = 1 - (1 - fillBase) * seen
	local edge = 1 - (1 - Theme.COMBAT_RANGE_TELL_EDGE_TRANSPARENCY) * seen
	if math.abs(fill - tell.fillShown) > 0.01 then
		tell.fillShown = fill
		for index = 1, tell.slices * 2 do
			tell.fill[index].Transparency = fill
		end
	end
	if math.abs(edge - tell.edgeShown) > 0.01 then
		tell.edgeShown = edge
		for index = 1, tell.slices + 2 do
			tell.edge[index].Transparency = edge
		end
	end
end

-- P4: the attack as drawn this frame, on the server clock: lean in radians (+ = forward),
-- forward thrust in studs, twist in radians, squash. Runs the phase clock on first (the blow
-- at the windup's end, recover after the strike) and keeps the tint and the ground tell in
-- step. The wire ends a recover; the clock ends it too, so a lost packet never leaves a body
-- slumped.
local function threatPose(entity: Entity, serverNow: number): (number, number, number, number)
	if entity.threat == "windup" and serverNow >= entity.impactAt then
		setThreat(entity, "attack", entity.impactAt)
	end
	if entity.threat == "attack" and serverNow >= entity.threatAt + entity.strikeSeconds then
		setThreat(entity, "recover", entity.threatAt + entity.strikeSeconds)
	end
	local threat = entity.threat
	local shape = entity.threatShape
	local age = math.max(serverNow - entity.threatAt, 0)
	local twistMost = entity.threatArc * 0.5 * Theme.COMBAT_RANGE_TELL_ARC_TWIST_SHARE
	if threat == "windup" then
		local u = if entity.windupSeconds > 0 then math.min(age / entity.windupSeconds, 1) else 1
		local coil = Theme.COMBAT_RANGE_TELL_COIL_SHARE
		-- Squared: a slow start and an unmistakable end, so the pose reads as building.
		local build = math.min(u / coil, 1) ^ 2
		-- Wave 2: a shooter's lit piece swells with the same build (ThreatFx/Cues). It runs
		-- straight on the windup, not on the coil, so it is at its largest exactly at the shot.
		entity.charge = u * u
		setTint(
			entity,
			build * Theme.COMBAT_RANGE_TELL_HEAT_SHARE,
			Theme.COMBAT_RANGE_TELL_COLOR,
			false
		)
		local back = -Theme.COMBAT_RANGE_TELL_LEAN_BACK * build
		if shape == "lunge" then
			local pull = -entity.radius * Theme.COMBAT_RANGE_TELL_PULL_BACK * build
			if u <= coil then
				return back, pull, 0, 1
			end
			-- The last of the windup is the thrust leaving, so the figure is fully out
			-- exactly at the impact and never after it.
			local snap = ((u - coil) / (1 - coil)) ^ 2
			return back + (Theme.COMBAT_RANGE_TELL_LEAN_FORWARD - back) * snap,
				pull + (entity.threatReach - pull) * snap,
				0,
				1
		elseif shape == "ring" then
			-- Stop 2, the slam: up on its toes through the coil, then down, so the body is
			-- flat on the floor exactly at the impact, when the front leaves its feet.
			local rise = 1 + Theme.COMBAT_RANGE_RING_SLAM_RISE * build
			if u <= coil then
				return back, 0, 0, rise
			end
			local snap = ((u - coil) / (1 - coil)) ^ 2
			return back + (Theme.COMBAT_RANGE_RING_SLAM_LEAN - back) * snap,
				0,
				0,
				rise + (Theme.COMBAT_RANGE_RING_SLAM_SQUASH - rise) * snap
		elseif shape == "summon" then
			-- Stop 2, the call: head thrown back and the whole body shaking harder as it
			-- builds. It hurts nobody, so the pose and the circle on the floor are all of it.
			return -Theme.COMBAT_RANGE_CALL_LEAN * build,
				0,
				Theme.COMBAT_RANGE_CALL_SHAKE * build * math.sin(
					serverNow * TWO_PI * Theme.COMBAT_RANGE_CALL_SHAKE_HZ
				),
				1 + Theme.COMBAT_RANGE_CALL_STRETCH * build
		end
		local tell = entity.tell
		if tell ~= nil then
			drawTell(entity, tell, u, false, 0)
		end
		return back, 0, -twistMost * build, 1
	elseif threat == "attack" then
		local u = if entity.strikeSeconds > 0 then math.min(age / entity.strikeSeconds, 1) else 1
		local left = 1 - u
		setTint(entity, 1, Theme.COMBAT_RANGE_TELL_COLOR, true)
		local forward = Theme.COMBAT_RANGE_TELL_LEAN_FORWARD * left
		if shape == "lunge" then
			return forward, entity.threatReach * left * left, 0, 1
		elseif shape == "lane" then
			-- Head down for the whole charge. The run itself is stepRush's: the body is moved
			-- on the server clock, not thrust from where it stands.
			return Theme.COMBAT_RANGE_TELL_LEAN_FORWARD, 0, 0, 1
		elseif shape == "ring" then
			-- Down flat at the impact, rising again as the front runs out.
			return Theme.COMBAT_RANGE_RING_SLAM_LEAN * left,
				0,
				0,
				1 - (1 - Theme.COMBAT_RANGE_RING_SLAM_SQUASH) * left
		end
		local tell = entity.tell
		if tell ~= nil then
			drawTell(entity, tell, 1, true, u)
		end
		local sweep = smoothstep(math.min(u / Theme.COMBAT_RANGE_TELL_ARC_SWEEP_SHARE, 1))
		return forward, 0, twistMost * (2 * sweep - 1), 1
	end
	if age >= entity.recoverSeconds then
		-- Over by this clock even if the wire never showed its blow or its recover: whatever
		-- the wire names next is a new attack.
		entity.threatOpen = false
		setThreat(entity, "none", serverNow)
		return 0, 0, 0, 1
	end
	-- Spent: slumped and dull, settling in fast and waking as the opening closes.
	-- Stop 2: an enraged boss may chain. The wire then goes from this blow straight to the
	-- next windup, which this client learns a snapshot and its lag later; the slump waits
	-- that long, so a chain shows no nod between its attacks.
	local held = if entity.enraged then interval + (lagEstimate or 0) else 0
	local settle =
		math.min(math.max(age - held, 0) / Theme.COMBAT_RANGE_TELL_SPENT_SETTLE_SECONDS, 1)
	local wake =
		math.min((entity.recoverSeconds - age) / Theme.COMBAT_RANGE_TELL_SPENT_WAKE_SECONDS, 1)
	local spent = math.min(settle, wake)
	setTint(
		entity,
		spent * Theme.COMBAT_RANGE_TELL_SPENT_SHARE,
		Theme.COMBAT_RANGE_TELL_SPENT_COLOR,
		false
	)
	-- An arc's body unwinds from wherever it was last turned to: the end of its sweep, or part
	-- of the way back when its windup was cancelled.
	local twist = if shape == "arc"
		then angleDelta(entity.yaw, entity.lastYaw) * (1 - settle)
		else 0
	-- The slump is a standing body's. A shooter walks through its recover, facing its target
	-- even as it backs off, and a slumped figure gliding over the floor reads as dragged: the
	-- pose lifts with its pace (stepAlive) and only the dull tint above goes with it.
	local slump = spent * (1 - entity.stride)
	return Theme.COMBAT_RANGE_TELL_SPENT_LEAN * slump,
		0,
		twist,
		1 - (1 - Theme.COMBAT_RANGE_TELL_SPENT_SQUASH) * slump
end

-- P4 wave 2: how far a lane's charge really runs: its range, or less where the arena's edge
-- is nearer. The server stops the body there while its `attack` state runs on for the full
-- range / speed, so the wire never says the charge stopped short; the client has to know the
-- edge. This mirrors CrowdBrain's runway (a body of its radius stays wholly on the floor),
-- and the floor is the one the server told (SetFloor), so it is the server's rectangle. With
-- no floor known nothing bounds the charge here.
local function laneReach(entity: Entity): number
	local reach = entity.threatReach
	local half = floor.half
	if half == nil then
		return reach
	end
	local middle = floor.centre
	local heading = lookOf(entity.threatYaw)
	local from = entity.threatOrigin
	-- The kind's radius as the config has it, which is what the server measures with: the
	-- drawn figure's is floored.
	local def = kindDef(entity.kind)
	local radius = if def ~= nil then def.radius else entity.radius
	local limitX = math.max(half.X - radius, 0)
	local limitZ = math.max(half.Z - radius, 0)
	if heading.X > 0 then
		reach = math.min(reach, (middle.X + limitX - from.X) / heading.X)
	elseif heading.X < 0 then
		reach = math.min(reach, (middle.X - limitX - from.X) / heading.X)
	end
	if heading.Z > 0 then
		reach = math.min(reach, (middle.Z + limitZ - from.Z) / heading.Z)
	elseif heading.Z < 0 then
		reach = math.min(reach, (middle.Z - limitZ - from.Z) / heading.Z)
	end
	return math.max(reach, 0)
end

-- P4 wave 2: a lane's charge, drawn on the server clock. Positions are drawn a little over
-- one snapshot behind the server, which at a walk nobody sees; at a charge's speed it is
-- several studs, and the server judges the hit where the brute IS (the commit rule: its body
-- as it was `lag` ago against the player's root now, which is this screen at this moment). So
-- while the charge runs the body is put where the clock has it, origin + facing x speed x
-- time up to the lane's end, and `rush` is what that adds to the sampled position. When the
-- clock says the attack is over, its snapshots may still be on their way: the body waits at
-- the lane's end until they reach it, then lets the last of the lead go. A charge the wire
-- ends early lets go at once. `alpha` = this frame's share of an exponential ease.
local function stepRush(entity: Entity, serverNow: number, alpha: number): ()
	local sampled = entity.position
	if entity.threat == "attack" and entity.threatShape == "lane" then
		local reach = laneReach(entity)
		local facing = lookOf(entity.threatYaw)
		local run = math.min(entity.threatSpeed * math.max(serverNow - entity.threatAt, 0), reach)
		local target = entity.threatOrigin + facing * run
		entity.rushTarget = entity.threatOrigin + facing * reach
		entity.rush = Vector3.new(target.X - sampled.X, 0, target.Z - sampled.Z)
		entity.rushHoldUntil = entity.threatAt
			+ entity.strikeSeconds
			+ (lagEstimate or 0)
			+ interval * (INTERP_SNAPSHOTS + 1)
	elseif entity.rush ~= Vector3.zero then
		local finish = entity.rushTarget
		local gap = Vector3.new(finish.X - sampled.X, 0, finish.Z - sampled.Z)
		if
			serverNow < entity.rushHoldUntil
			and gap.Magnitude > Theme.COMBAT_RANGE_TELL_RUSH_ARRIVE
		then
			entity.rush = gap
		else
			entity.rushHoldUntil = 0
			local left = entity.rush * (1 - alpha)
			entity.rush = if left.Magnitude < SETTLE_EPSILON then Vector3.zero else left
		end
	else
		return
	end
	entity.position = sampled + entity.rush
end

-- Samples, smooths and poses one living body; queues its parts only when the pose changed.
local function stepAlive(
	entity: Entity,
	now: number,
	serverNow: number,
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

	local offset = Vector3.zero
	local drawnYaw = entity.yaw
	local squash = 1
	-- Wave 2: the reel after a plate breaks is a stagger on the wire, crowd.plateBreakSeconds
	-- from the hit. It holds by its clock (that hit may have thrown the body up, and `airborne`
	-- shows over the stagger first) and then for as long as the wire still says stagger, so
	-- nothing blinks between its end and what the wire names next: the rest of a recover, when
	-- the break cancelled a windup.
	if entity.reelUntil > 0 and serverNow >= entity.reelUntil and entity.state ~= "stagger" then
		entity.reelUntil = 0
	end
	if entity.threat ~= "none" then
		if entity.threat == "recover" and entity.walks then
			-- How fast the body is walking, off its two newest sightings. Only a kind that
			-- keeps its distance walks in recover (a rusher stands spent, and what moves it is
			-- the crowd's jostling), and only while the wire itself says recover: under a
			-- stagger the movement is a shove, and a shoved body stays slumped.
			local pace = 0
			if
				entity.state == "recover"
				and entity.samples >= 2
				and entity.timeC > entity.timeB
			then
				local step = entity.posC - entity.posB
				pace = math.sqrt(step.X * step.X + step.Z * step.Z) / (entity.timeC - entity.timeB)
			end
			local stride = math.min(pace / Theme.COMBAT_RANGE_TELL_SPENT_WALK_SPEED, 1)
			local gap = stride - entity.stride
			entity.stride = if math.abs(gap) < 0.01 then stride else entity.stride + gap * leanAlpha
		end
		local leanAngle, thrust, twist, slump = threatPose(entity, serverNow)
		local facing = lookOf(entity.yaw)
		local leanTo = facing * leanAngle
		if entity.threat == "recover" then
			-- The slump warns of nothing, so it may be eased: a body coming out of a reel or a
			-- cancelled coil rocks into it instead of snapping.
			local leanGap = leanTo - entity.lean
			entity.lean = if leanGap.Magnitude < SETTLE_EPSILON
				then leanTo
				else entity.lean + leanGap * leanAlpha
		else
			-- The attack's own clock is the easing: smoothing on top would show the blow late.
			entity.lean = leanTo
		end
		offset = facing * thrust
		drawnYaw += twist
		squash = math.round(slump * 100) / 100
	else
		-- The reel is the opening: thrown further back than a plain stagger, swaying, and dull
		-- and slumped like a spent body, which is how wave 1 taught the player to read "hit me
		-- now".
		local reeling = entity.reelUntil > 0
		local leanTarget = if reeling
			then lookOf(entity.yaw) * -Theme.COMBAT_RANGE_REEL_LEAN
			else stateLeanTarget(entity)
		local leanGap = leanTarget - entity.lean
		entity.lean = if leanGap.Magnitude < SETTLE_EPSILON
			then leanTarget
			else entity.lean + leanGap * leanAlpha
		if reeling then
			drawnYaw += Theme.COMBAT_RANGE_REEL_SWAY * math.sin(
				serverNow * TWO_PI * Theme.COMBAT_RANGE_REEL_SWAY_HZ
			)
			squash = Theme.COMBAT_RANGE_REEL_SQUASH
			entity.reeling = true
			setTint(
				entity,
				Theme.COMBAT_RANGE_TELL_SPENT_SHARE,
				Theme.COMBAT_RANGE_TELL_SPENT_COLOR,
				false
			)
		elseif entity.reeling then
			entity.reeling = false
			setTint(entity, 0, FLASH_COLOR, false)
		end
		if entity.boss and not reeling then
			-- Stop 2: between attacks a boss breathes, so it is never a statue; enraged, it
			-- heaves, which is the phase read off the body's motion alone. The server clock
			-- runs it, so every client sees the same breath.
			local depth = if entity.enraged
				then Theme.COMBAT_RANGE_ENRAGE_BREATH
				else Theme.COMBAT_RANGE_BOSS_BREATH
			local rate = if entity.enraged
				then Theme.COMBAT_RANGE_ENRAGE_BREATH_HZ
				else Theme.COMBAT_RANGE_BOSS_BREATH_HZ
			squash = math.round((1 + depth * math.sin(serverNow * TWO_PI * rate)) * 100) / 100
		end
	end
	-- The charge moves the sampled position itself, so aim assist and the numbers follow it.
	if entity.rush ~= Vector3.zero or entity.threatShape == "lane" then
		stepRush(entity, serverNow, leanAlpha)
	end
	-- Wave 2: the role cue's own state (the lit piece's charge, the shell). It changes sizes
	-- and colours, never a frame, so it runs whether or not the pose below is redrawn.
	if entity.guardKind ~= "" then
		-- Stop 3: is its plate guarded now? The server guards it from its spawn until its
		-- guard has been called AND is dead, so here: the plate is on, and either one of the
		-- bodies it called lives or this client has never seen one (it has not called yet;
		-- a client that joined after they all died learns better from its first hit, which
		-- comes back without the guard's flag: NoteUnguarded). While it holds, the shell is a
		-- ward and the tethers are up (ThreatFx draws them from ForEachWard). When it ends
		-- the shell flashes white and is a plain plate again: it has opened to attack.
		local wards = wardsOf(entity)
		if wards > 0 then
			entity.called = true
		end
		local warded = entity.plated and not entity.opened and (wards > 0 or not entity.called)
		if entity.warded and not warded and entity.plated then
			entity.glintAt = now
				+ Theme.COMBAT_RANGE_WARD_OPEN_SECONDS
				- Theme.COMBAT_RANGE_CUE_GLINT_SECONDS
			burstAt(entity, 1)
		end
		entity.wards = wards
		entity.warded = warded
	end
	local cues = entity.cues
	if cues ~= nil then
		Cues.Paint(
			cues,
			entity.charge,
			entity.plated,
			(now - entity.breakAt) / Theme.COMBAT_RANGE_CUE_BREAK_SECONDS,
			now - entity.glintAt < Theme.COMBAT_RANGE_CUE_GLINT_SECONDS,
			entity.warded
		)
	end

	local lean = entity.lean
	local tumbleAngle = 0
	local tuck = if entity.state == "airborne" then entity.legHeight * AIRBORNE_TUCK else 0

	-- Stop 2: a summoned body comes up through the floor, fast at first and settling, so the
	-- call visibly raises what it raises.
	local riseAge = now - entity.riseStart
	if riseAge < Theme.COMBAT_RANGE_RISE_SECONDS then
		local left = 1 - riseAge / Theme.COMBAT_RANGE_RISE_SECONDS
		offset -= UP * (entity.height * left * left)
	end

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
		local flinched = math.max(0.5, 1 - FLINCH_SQUASH * entity.flinchStrength * envelope)
		squash = math.min(squash, math.round(flinched * 100) / 100)
		lean += entity.flinchDir * (FLINCH_LEAN * entity.flinchStrength * envelope)
	end

	local shown = entity.position + offset
	entity.shown = shown
	if
		not entity.dirty
		and (shown - entity.lastShown).Magnitude < SETTLE_EPSILON
		and math.abs(drawnYaw - entity.lastYaw) < SETTLE_EPSILON
		and (lean - entity.lastLean).Magnitude < SETTLE_EPSILON
		and tumbleAngle == entity.lastTumble
		and squash == entity.lastSquash
		and tuck == entity.lastTuck
	then
		return
	end
	entity.dirty = false
	entity.lastShown = shown
	entity.lastYaw = drawnYaw
	entity.lastLean = lean
	entity.lastTumble = tumbleAngle
	entity.lastSquash = squash
	entity.lastTuck = tuck
	queuePose(
		entity,
		rootFrame(entity, shown, drawnYaw, lean, entity.launchAxis, tumbleAngle),
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
	local serverNow = Workspace:GetServerTimeNow()
	local renderTime = serverNow - (lagEstimate or 0) - interval * INTERP_SNAPSHOTS
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
			stepAlive(entity, now, serverNow, renderTime, yawAlpha, leanAlpha)
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

-- Builds bodies into the pool, a few a frame, until `target` exist (drawn and spare). Yields.
local function prewarm(target: number): ()
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
	-- The range fills its pool to the bench's cap here. A mission waits for its own, smaller
	-- cap (Prewarm), so a 60-body mission does not build the bench's 160.
	if CameraController.IsRange() then
		local crowd = Tuning.Get().crowd
		prewarm(if crowd ~= nil then crowd.maxAlive else 0)
	end
end

local CrowdRenderer = {}

-- Main's controller contract; everything happens in Start.
function CrowdRenderer.Init(): () end

-- L1 ruling 30: the crowd's floor, as the server tells it in RunState.floor from a camp's
-- trigger until that camp is cleared. `center` = the floor's top centre (its Y is the height
-- tells and threat origins are drawn at), `halfSize` = its half extents in X and Z (what a
-- charge is bounded by). nil = no camp: height 0 and no bound. The wire's origin does not move
-- with it (WIRE_ORIGIN), so a floor that arrives late only draws a tell at the old height for a
-- moment; no body is ever misplaced.
function CrowdRenderer.SetFloor(center: Vector3?, halfSize: Vector3?): ()
	floor.centre = center or Vector3.zero
	floor.half = if center ~= nil then halfSize else nil
end

-- The range's floor: Shared/Layouts/Arenas/<name> at the world origin, as ArenaService builds
-- it (the range names its arena in ProvingGrounds.json). An unknown name leaves no bound. A
-- level never calls this: its floors come through SetFloor.
function CrowdRenderer.SetArena(name: string): ()
	CrowdRenderer.SetFloor(nil, nil)
	local layouts = sharedFolder:FindFirstChild("Layouts")
	local arenas = if layouts ~= nil then layouts:FindFirstChild("Arenas") else nil
	local module = if arenas ~= nil then arenas:FindFirstChild(name) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return
	end
	local ok, layout = pcall(require, module)
	local size = if ok and typeof(layout) == "table" then (layout :: any).size else nil
	if typeof(size) == "table" and typeof(size.x) == "number" and typeof(size.z) == "number" then
		CrowdRenderer.SetFloor(Vector3.zero, Vector3.new(size.x / 2, 0, size.z / 2))
	end
end

-- P5: a mission's pool is filled to that mission's `crowd.maxAlive`, which CombatUIController
-- hands over once the first RunState names the mission. Never past the bench's own cap, which
-- is the most the server will ever field; a body past the pool is still built on demand.
function CrowdRenderer.Prewarm(count: number): ()
	if not started or destroyed or count ~= count then
		return
	end
	local crowd = Tuning.Get().crowd
	local cap = if crowd ~= nil then crowd.maxAlive else 0
	task.spawn(prewarm, math.max(math.min(math.floor(count), cap), 0))
end

-- Inert unless the range's combat runs. CameraController.IsCrowdCombat is that gate (the range,
-- and since P5 every crowd mission), so a build without the ProvingGrounds config never waits
-- on crowd remotes.
function CrowdRenderer.Start(): ()
	if started or destroyed or not CameraController.IsCrowdCombat() then
		return
	end
	started = true

	local created = Instance.new("Folder")
	created.Name = FOLDER_NAME
	created.Parent = Workspace
	folder = created
	template = buildTemplate()

	if CameraController.IsRange() then
		CrowdRenderer.SetArena(Tuning.Get().arena)
	end

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
	bossEntity = nil
	-- The tells' parts live in the folder destroyed below.
	table.clear(tellPool)
	-- Cue pieces in use went with their bodies' models; these are the spare ones and the bars.
	Cues.Destroy()
	PlateBar.Destroy()
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

-- P4 wave 2: every living body that is winding up or throwing a lane or a line, the two
-- attacks whose tells ThreatFx draws from the snapshot. The clock is this module's: an
-- attack that was cancelled or is over is simply no longer reported. The callback must not
-- yield. Stop 2: a ring and a summon are reported the same way.
function CrowdRenderer.ForEachThreat(callback: ThreatCallback): ()
	for _, entity in active do
		local threat = entity.threat
		local shape = entity.threatShape
		if
			entity.phase == "alive"
			and (threat == "windup" or threat == "attack")
			and (shape == "lane" or shape == "line" or shape == "ring" or shape == "summon")
		then
			-- A lane is as long as the charge really runs (the arena's edge may cut it), and
			-- its blow lasts as long as the brute takes to cover that, not the full attack
			-- state: the lane behind the brute goes dark at the brute's own pace.
			local reach = entity.threatReach
			local lasts = entity.strikeSeconds
			if shape == "lane" then
				reach = laneReach(entity)
				if entity.threatSpeed > 0 then
					lasts = reach / entity.threatSpeed
				end
			end
			callback(
				entity.id,
				shape,
				threat == "attack",
				entity.threatAt,
				entity.impactAt,
				entity.threatOrigin,
				entity.threatYaw,
				reach,
				entity.threatWidth,
				entity.threatLock,
				lasts,
				entity.threatSpeed
			)
		end
	end
end

-- Stop 2: is this body still drawn and alive (not dead on the wire, dying or fading out)?
-- What a body threw that ends with it (a slam's front) asks every frame.
function CrowdRenderer.IsAlive(id: number): boolean
	local entity = byId[id]
	return entity ~= nil and entity.phase == "alive" and entity.state ~= "dead"
end

-- Stop 2: hands `callback` the crowd id of every boss that died or was taken away since the
-- last call, and forgets them. A boss's end takes back everything that body had in the air;
-- the caller drops its circles and shots, and nobody else's. The callback must not yield.
function CrowdRenderer.DrainBossEnds(callback: (id: number) -> ()): ()
	for index = #bossEnds, 1, -1 do
		local id = bossEnds[index]
		bossEnds[index] = nil
		callback(id)
	end
end

-- Stop 2: the boss the bar shows, if there is one (BossInfo; the same table every call, so
-- a frame allocates nothing: read it, do not keep it). Its health is 0 once it is dead,
-- through its death flight. nil = no boss; a boss that was taken away (a set load) simply
-- stops being reported. Stop 3: under a plate the wire's one fraction is the plate's, and
-- health cannot have moved, so it reads full.
function CrowdRenderer.GetBoss(): BossInfo?
	local entity = bossEntity
	if entity == nil or entity.samples == 0 then
		return nil
	end
	local dead = entity.phase ~= "alive" or entity.state == "dead"
	local info = bossInfo
	info.id = entity.id
	info.name = entity.title
	info.health = if dead then 0 elseif entity.plated then 1 else entity.hpFraction
	info.plate = if entity.plateMax <= 0
		then -1
		elseif entity.plated and not dead then entity.hpFraction
		else 0
	info.enrageAt = entity.enrageAt
	info.enraged = entity.enraged
	info.label = entity.phaseLabel
	-- Before it has called anyone its guard is whole, not dead: the pips are all lit, as the
	-- plate they stand over is the guard's colour.
	info.guards = if dead
		then 0
		elseif
			entity.guardKind ~= ""
			and not entity.called
			and not entity.opened
		then entity.guardTotal
		else entity.wards
	info.guardTotal = entity.guardTotal
	info.guarded = entity.warded and not dead
	return info
end

-- Stop 3: a hit on this body came back without the guard's flag. For a body its guard
-- protects that settles it: the server does not guard it now, whatever this client has or
-- has not seen of its guard. It stays so until a fresh body it calls is seen (spawnEntity).
-- Any other body: nothing.
function CrowdRenderer.NoteUnguarded(id: number): ()
	local entity = byId[id]
	if entity ~= nil and entity.guardKind ~= "" then
		entity.opened = true
	end
end

-- Stop 3: every tether there is to draw: for each living body whose plate is guarded now,
-- each living one of its guard, with the two chests the tether runs between (as drawn this
-- frame). The callback must not yield.
function CrowdRenderer.ForEachWard(callback: WardCallback): ()
	for _, boss in active do
		if boss.warded and boss.phase == "alive" then
			local to = boss.shown + UP * (boss.legHeight + boss.torsoHeight * 0.6)
			for _, other in active do
				if isWardOf(boss, other) then
					callback(
						other.id,
						other.shown + UP * (other.legHeight + other.torsoHeight * 0.6),
						to
					)
				end
			end
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
	if reaction == "block" then
		-- Wave 2: the plate turned the hit, and the server moved nothing. Only the shell
		-- answers (Cues.Paint lights it while the glint lasts).
		entity.glintAt = now
	elseif reaction == "flash" then
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
