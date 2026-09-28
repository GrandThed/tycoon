--!strict
-- Proving Grounds hit feedback (P1 contract, docs/INTERFACES.md "P1 contracts" → Feedback
-- layers; docs/COMBAT_DESIGN.md §1 pillar 2 and §4). There is no sound, so every hit must be
-- SEEN. Each `CombatFxStrike` (one per attack the server resolved) is turned into six stacked
-- layers, each scaled live by `feedback.<layer>` from Tuning (0 = off):
--
--  1. hitMarker    crosshair tick burst, bigger and yellow on a crit, red X on a kill, kick
--  2. numbers      ONE combined damage burst per strike (total + "×N"), white / yellow on crit
--  3. enemyFlash / enemyReaction   asked of CrowdRenderer.React (Render owns body motion)
--  4. hitboxEffect the strike's exact shape (arc slab, sphere shockwave, capsule, cone, beam)
--  5. hitstop / shake / edgeFlash / haptics   the screen
--  6. counters     running combo of enemies hit + kills of the last attack
--
-- The client decides nothing here: hits, crits, kills and every shape number arrive in the
-- strike. The weapon's pad / knockback / launch are read from Tuning only to pick which
-- reactions to ask for, how heavy the screen layer is, and how big the wireframe is.
--
-- Markers, numbers, screen and counters follow the LOCAL player's strikes only (someone
-- else's hit is not your hit); the shape and enemy reactions play for every strike so a
-- second player's swing is readable too.
--
-- Wireframe (RangePanel toggle) additionally draws the true padded shape the server tests
-- (HitShapes: shape grown by `pad`), in cyan and held longer, so the drawn effect can be
-- checked against it.
--
-- Device gating (spec §10, living-city ruling): Theme.reducedMotion is true on every touch
-- device, so it only shrinks motion (smaller pops, no drift, CameraController halves shake).
-- The hitbox effect is information and always draws; Theme.lowEndDevice drops its
-- translucent fill and halves its segment count. Parts are pooled because a 2.5 swings/s
-- sword draws ~40 of them per swing.
--
-- P2 (INTERFACES "P2 contracts"): every projectile is announced at fire time as a
-- `CombatFxShot`, and every client flies it here: an arrow is a thin shaft with a bright trail
-- (gold and lit at a full charge), a launcher shell a ball with a smoke trail, a split arrow
-- fans into its children where the server says it split (a CombatFxShot with split = true,
-- at splitDistance or early at the first enemy) using the server's own HitShapes.Fan pattern;
-- a local timer splits it only if that message is late. The visual follows origin + v·t + ½g·t² (blended out of the shooter's hand for the
-- first instant) and ends when its strike lands (matched by userId + seq), when it meets the
-- world, or on a timeout. Damage still arrives only as strikes, which add the bow effects:
-- pierce sparks on every enemy an arrow passed through, a burst for a full-charge blast or a
-- shell, and a forward streak for the spear's thrust.
--
-- P3 (INTERFACES "P3 contracts", rulings 6 and 8):
--  * One-off ability strikes (earthquake rings, landings, the dash, slug cones, the
--    overcharged ray, cluster blasts) draw their exact shape like any strike, in the ability
--    colour, with pad / knockback / launch read from the family's `ability` block. An ability
--    ray draws its full width, since that is the area it hit.
--  * Tick strikes (`tick`: zones, channels, sweeps) skip the generic flash, because AbilityFx
--    draws the lasting area at its exact size. They keep markers, reactions and counters, get
--    no hitstop and a softer shake, and their numbers run into ONE burst per shooter + ability.
--  * A `continuous` weapon (the Beam family) is ONE lasting beam per shooter from the hand to
--    the latest strike's end, with merged numbers and throttled markers instead of a tracer per
--    shot. The local beam follows the live crosshair at the server's last length (display
--    prediction; the next strike lands along the same camera ray).
--  * `links` (Chain Gun, Storm Coil) draw one jagged bolt per pair; id 0 is the strike origin
--    of an ability, or the shooter's hand for a weapon shot.
--  * Ability projectiles (Volley, Cluster Shell) fly as their family's arrow or shell, with the
--    ability's own count, spread and split distance.

local HapticService = game:GetService("HapticService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Format = require(sharedFolder:WaitForChild("Format"))
local Tuning = require(sharedFolder:WaitForChild("Tuning"))
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Create = require(uiFolder:WaitForChild("Create"))
local Theme = require(uiFolder:WaitForChild("Theme"))
local Motion = require(uiFolder:WaitForChild("Motion"))
local Crosshair = require(uiFolder:WaitForChild("Crosshair"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local CrowdRenderer = require(script.Parent:WaitForChild("CrowdRenderer"))

-- Below this length a vector has no heading (mirrors HitShapes' own epsilon).
local EPSILON = 1e-6
-- A strike with this many hits or more is centred on this many bodies: the burst sits over
-- the crowd either way, and 100 bounding boxes a frame buy nothing.
local BURST_SAMPLE = 16
-- A charge at or above this reads as full (the server clamps charge to [0, 1]).
local FULL_CHARGE = 0.999
-- The ability whose chain links leave a coil top rather than its ground-point origin.
local COIL_ABILITY = "stormCoil"
-- Hit parts for a haptic pulse: gamepads have two motors, phones (where supported) one.
local HAPTIC_INPUTS = { Enum.UserInputType.Gamepad1, Enum.UserInputType.Touch }
local HAPTIC_MOTORS = { Enum.VibrationMotor.Large, Enum.VibrationMotor.Small }

type Strike = {
	userId: number,
	weapon: string,
	variant: string,
	shape: string,
	origin: Vector3,
	direction: Vector3,
	size: number,
	arcDegrees: number?,
	width: number?,
	endPoint: Vector3?,
	seq: number?,
	hits: { Types.StrikeHit },
	ability: string?,
	tick: boolean,
	links: { number }?,
}

-- Pad, knockback, launch (and an ability's pull) the server resolved a strike with: the weapon
-- variant's, the family ability's for an ability strike, movement.slam* for the ground slam.
type Impact = { pad: number, knockback: number, launch: number, pull: number }

-- fromSize/toSize and fromCFrame/toCFrame animate a part during the effect's hold phase
-- (a shockwave growing, a thrust streak shooting forward).
type FxPart = {
	part: BasePart,
	base: number,
	fromSize: Vector3?,
	toSize: Vector3?,
	fromCFrame: CFrame?,
	toCFrame: CFrame?,
}
type Effect = { parts: { FxPart }, started: number, seconds: number }

-- `started` is when the pop-arc-fall starts (in the future while a merged burst is held open);
-- `popAt` when its last pop began; `token` changes every time the pool hands the burst out, so
-- a merge that still points at a recycled burst knows it lost it; `target` is where an open
-- merged burst drifts (its latest hits).
type Burst = {
	gui: BillboardGui,
	anchor: Attachment,
	scale: UIScale,
	main: TextLabel,
	count: TextLabel,
	strokes: { UIStroke },
	started: number,
	popAt: number,
	side: number,
	pop: number,
	active: boolean,
	token: number,
	target: Vector3?,
}

-- One running burst for a shooter + ability (or a held beam): the totals it shows so far.
type Merge = {
	burst: Burst,
	token: number,
	total: number,
	crit: boolean,
	ids: { [number]: boolean },
	count: number,
	kills: number,
	openedAt: number,
	lastAt: number,
}

-- One shooter's held beam. origin / length / wallStop describe the latest strike (its camera
-- ray and where the server stopped it); target is that stop. width = the ray's true width.
type BeamFx = {
	start: Attachment,
	finish: Attachment,
	core: Beam,
	glow: Beam?,
	tip: BasePart,
	muzzle: BasePart?,
	width: number,
	lastAt: number,
	linger: number,
	range: number,
	origin: Vector3,
	length: number,
	wallStop: boolean,
	target: Vector3,
	shown: Vector3?,
	phase: number,
	wiredAt: number,
}

type Spark = { anchor: Attachment, emitter: ParticleEmitter, freeAt: number }

type HapticTarget = { input: Enum.UserInputType, motor: Enum.VibrationMotor }

-- A crowd sphere a pellet tracer may stop in (body or head).
type Body = { centre: Vector3, radius: number }

-- A projectile in flight (arrow, split child or shell), announced by CombatFxShot. `key` is
-- userId:seq, the pair its strike carries. `offset` is the hand-to-camera gap blended out over
-- the first instant, so the shaft leaves the bow, not the lens.
type Flight = {
	key: string,
	part: BasePart,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	offset: Vector3,
	started: number,
	lifetime: number,
	last: Vector3,
	-- Seconds after launch when the client splits the arrow itself if the server's split shot
	-- has not arrived (nil = not a split parent, or already split).
	splitAt: number?,
	splitCount: number,
	splitArc: number,
	seq: number,
	glow: boolean,
}

local FeedbackController = {}

local connections: { RBXScriptConnection } = {}
local fxFolder: Folder? = nil
local pools: { [string]: { BasePart } } = { Part = {}, WedgePart = {} }
local pooledCount = 0
local effects: { Effect } = {}
local bursts: { Burst } = {}
local crosshair: Crosshair.CrosshairHandle? = nil
local overlayRoot: Frame? = nil
local counterRoot: Frame? = nil
local counterScale: UIScale? = nil
local comboValue: TextLabel? = nil
local comboCaption: TextLabel? = nil
local killsLabel: TextLabel? = nil
local edgeBars: { Frame } = {}
local layoutScale = 1
local wireframe = false
local currentLoadout: Types.RangeLoadout? = nil
local onTuneState: (() -> ())? = nil
local combo = 0
local comboExpires = 0
local killsToken = 0
local hitstopUntil = 0
local frozenTracks: { [AnimationTrack]: number } = {}
local hapticTargets: { HapticTarget } = {}
local hapticToken = 0
local flights: { Flight } = {}
local merges: { [string]: Merge } = {}
local beams: { [number]: BeamFx } = {}
local sparks: { Spark } = {}
-- The local held beam's last crosshair mark and pulse (os.clock), for the throttle.
local beamMarkedAt = 0
-- When the local player's previous strike with hits landed: hitstop never outlasts a share of
-- the gap between two strikes (SMG, Mag Dump), whatever the weapon's configured rate.
local lastLocalHitAt = 0

-- Live numbers ------------------------------------------------------------------------

local function config(): Types.ProvingGroundsConfig
	return Tuning.Get()
end

local function feedbackStrength(layer: string): number
	local feedback = (config() :: any).feedback
	local value = if typeof(feedback) == "table" then feedback[layer] else nil
	return if typeof(value) == "number" then math.max(value, 0) else 1
end

local function variantOf(weapon: string, variant: string?): Types.RangeWeaponVariant?
	local weapons = (config() :: any).weapons
	local def = if typeof(weapons) == "table" then weapons[weapon] else nil
	if typeof(def) ~= "table" then
		return nil
	end
	local key = variant or def.default
	local variants = def.variants
	local found = if typeof(variants) == "table" and typeof(key) == "string"
		then variants[key]
		else nil
	return if typeof(found) == "table" then found :: Types.RangeWeaponVariant else nil
end

-- A family's ability block, found by its id: the family's own first (the usual case), else
-- any family that carries that id (a strike racing a family switch).
local function abilityDefOf(family: string, id: string): Types.RangeAbilityDef?
	local weapons = (config() :: any).weapons
	if typeof(weapons) ~= "table" then
		return nil
	end
	local own = weapons[family]
	if typeof(own) == "table" and typeof(own.ability) == "table" and own.ability.id == id then
		return own.ability :: Types.RangeAbilityDef
	end
	for _, def in weapons do
		if typeof(def) == "table" and typeof(def.ability) == "table" and def.ability.id == id then
			return def.ability :: Types.RangeAbilityDef
		end
	end
	return nil
end

local function impactOf(strike: Strike, variant: Types.RangeWeaponVariant?): Impact
	local id = strike.ability
	if id ~= nil then
		local ability = abilityDefOf(strike.weapon, id)
		return {
			pad = if ability ~= nil then ability.pad or 0 else 0,
			knockback = if ability ~= nil then ability.knockback or 0 else 0,
			launch = if ability ~= nil then ability.launch or 0 else 0,
			pull = if ability ~= nil then ability.pull or 0 else 0,
		}
	end
	if variant ~= nil then
		return {
			pad = variant.pad,
			knockback = variant.knockback,
			launch = variant.launch,
			pull = 0,
		}
	end
	-- The ground slam: a strike with no weapon variant.
	local movement = config().movement
	return {
		pad = movement.slamPad,
		knockback = movement.slamKnockback,
		launch = movement.slamLaunch,
		pull = 0,
	}
end

-- Arrows and shells: their flight is drawn from CombatFxShot, so their strike needs no trail.
local function isProjectile(variant: Types.RangeWeaponVariant?): boolean
	return variant ~= nil and variant.kind == "ranged" and (variant.projectileSpeed or 0) > 0
end

-- The projectile an ability fires (Volley, Cluster Shell) flies as its family's arrow or shell,
-- with the ability's own numbers, as the server builds it for RangeService.FireProjectile: an
-- arrow ability splits after `spacing` studs into `count` arrows over `arcDegrees`; a shell
-- ability explodes with `radius`. nil when the family has no such ability or no projectile.
local function abilityShotVariant(family: string, id: string): Types.RangeWeaponVariant?
	local ability = abilityDefOf(family, id)
	local base = variantOf(family, nil)
	if ability == nil or base == nil then
		return nil
	end
	local arrow = base.shape ~= "sphere"
	return {
		label = ability.name,
		kind = "ranged",
		shape = base.shape,
		range = ability.range or base.range,
		width = ability.width,
		pad = ability.pad or 0,
		cap = ability.cap or 0,
		damage = ability.damage or 0,
		rate = base.rate,
		knockback = ability.knockback or 0,
		launch = ability.launch or 0,
		pierce = ability.pierce,
		projectileSpeed = ability.speed,
		gravity = ability.gravity,
		splashRadius = if arrow then nil else ability.radius,
		-- Clamped exactly as AbilityService builds it, so both sides fan the same arrows.
		splitCount = if arrow and ability.count ~= nil
			then math.clamp(math.floor(ability.count), 1, HitShapes.MAX_FAN)
			else nil,
		splitDistance = if arrow then ability.spacing else nil,
		splitArcDegrees = if arrow then ability.arcDegrees else nil,
	}
end

-- Ability strikes that end a flight: the ones of an ability that fires a projectile.
local function abilityFlies(strike: Strike): boolean
	local id = strike.ability
	if id == nil or strike.tick then
		return false
	end
	local ability = abilityDefOf(strike.weapon, id)
	return ability ~= nil and (ability.speed or 0) > 0
end

local function localUserId(): number
	return Players.LocalPlayer.UserId
end

-- Geometry helpers ---------------------------------------------------------------------

local function flatten(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < EPSILON then
		return nil
	end
	return flat.Unit
end

local function unitOf(vector: Vector3): Vector3?
	if vector.Magnitude < EPSILON then
		return nil
	end
	return vector.Unit
end

-- Two unit vectors perpendicular to `axis` (and to each other).
local function basis(axis: Vector3): (Vector3, Vector3)
	local reference = if math.abs(axis.Y) < 0.99 then Vector3.yAxis else Vector3.xAxis
	local right = axis:Cross(reference).Unit
	return right, right:Cross(axis).Unit
end

local function segmentCount(degrees: number): number
	local step = if Theme.lowEndDevice
		then Theme.COMBAT_RANGE_HITBOX_LOW_END_SEGMENT_DEGREES
		else Theme.COMBAT_RANGE_HITBOX_SEGMENT_DEGREES
	return math.clamp(math.ceil(degrees / step), 3, 360 // step)
end

-- Part pool ----------------------------------------------------------------------------

local function acquire(className: string, color: Color3, transparency: number): BasePart
	local pool = pools[className]
	local part = table.remove(pool)
	if part == nil then
		part = Create(className, {
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Material = Enum.Material.Neon,
			TopSurface = Enum.SurfaceType.Smooth,
			BottomSurface = Enum.SurfaceType.Smooth,
			Parent = fxFolder,
		}) :: BasePart
	else
		pooledCount -= 1
	end
	local resolved = part :: BasePart
	resolved.Color = color
	resolved.Transparency = transparency
	return resolved
end

local function release(part: BasePart): ()
	-- Fully transparent parts are skipped by the renderer, so a parked part costs nothing.
	part.Transparency = 1
	if pooledCount >= Theme.COMBAT_RANGE_FX_POOL_MAX or pools[part.ClassName] == nil then
		part:Destroy()
		return
	end
	pooledCount += 1
	table.insert(pools[part.ClassName], part)
end

-- A pooled Part of the given shape (the pool holds Parts and WedgeParts under one type).
local function shapedPart(shape: Enum.PartType, color: Color3, transparency: number): BasePart
	local part = acquire("Part", color, transparency)
	local shaped = part :: Part
	shaped.Shape = shape
	return part
end

-- Drawing primitives -------------------------------------------------------------------

-- A flat bar from a to b, `width` wide across and `thickness` along `normal`.
local function segment(
	list: { FxPart },
	a: Vector3,
	b: Vector3,
	width: number,
	thickness: number,
	normal: Vector3,
	color: Color3,
	transparency: number
): ()
	local along = b - a
	local length = along.Magnitude
	if length < EPSILON then
		return
	end
	local up = normal
	if math.abs(along.Unit:Dot(normal)) > 0.99 then
		local _, fallback = basis(along.Unit)
		up = fallback
	end
	local part = shapedPart(Enum.PartType.Block, color, transparency)
	part.Size = Vector3.new(width, thickness, length)
	part.CFrame = CFrame.lookAt((a + b) / 2, b, up)
	table.insert(list, { part = part, base = transparency })
end

-- A filled triangle from two wedges (the standard right-triangle split).
local function triangle(
	list: { FxPart },
	a: Vector3,
	b: Vector3,
	c: Vector3,
	color: Color3,
	transparency: number
): ()
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
		return
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local thickness = Theme.COMBAT_RANGE_HITBOX_THICKNESS
	local first = acquire("WedgePart", color, transparency)
	first.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	first.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	table.insert(list, { part = first, base = transparency })
	local second = acquire("WedgePart", color, transparency)
	second.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	second.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	table.insert(list, { part = second, base = transparency })
end

-- Points on a circle (or an arc of one) around `centre` in the plane spanned by u, v.
local function arcPoints(
	centre: Vector3,
	u: Vector3,
	v: Vector3,
	radius: number,
	fromAngle: number,
	toAngle: number,
	count: number
): { Vector3 }
	local points: { Vector3 } = {}
	for index = 0, count do
		local angle = fromAngle + (toAngle - fromAngle) * index / count
		table.insert(points, centre + (u * math.cos(angle) + v * math.sin(angle)) * radius)
	end
	return points
end

local function polyline(
	list: { FxPart },
	points: { Vector3 },
	width: number,
	normal: Vector3,
	color: Color3,
	transparency: number
): ()
	for index = 1, #points - 1 do
		segment(list, points[index], points[index + 1], width, width, normal, color, transparency)
	end
end

local function ball(
	list: { FxPart },
	centre: Vector3,
	diameter: number,
	color: Color3,
	transparency: number,
	grow: boolean
): ()
	local part = shapedPart(Enum.PartType.Ball, color, transparency)
	local size = Vector3.one * diameter
	part.CFrame = CFrame.new(centre)
	if grow and not Theme.reducedMotion then
		local from = size * Theme.COMBAT_RANGE_HITBOX_GROW_FROM
		part.Size = from
		table.insert(list, { part = part, base = transparency, fromSize = from, toSize = size })
	else
		part.Size = size
		table.insert(list, { part = part, base = transparency })
	end
end

local function cylinder(
	list: { FxPart },
	a: Vector3,
	b: Vector3,
	diameter: number,
	color: Color3,
	transparency: number
): ()
	local length = (b - a).Magnitude
	if length < EPSILON then
		return
	end
	local part = shapedPart(Enum.PartType.Cylinder, color, transparency)
	-- A cylinder's axis is its X; turn the look frame so X runs from a to b.
	part.Size = Vector3.new(length, diameter, diameter)
	part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	table.insert(list, { part = part, base = transparency })
end

-- A bar that shoots from a to b during the hold phase (reduce motion: drawn whole at once).
local function streak(
	list: { FxPart },
	a: Vector3,
	b: Vector3,
	width: number,
	color: Color3,
	transparency: number
): ()
	local along = b - a
	local length = along.Magnitude
	if length < EPSILON then
		return
	end
	local part = shapedPart(Enum.PartType.Block, color, transparency)
	local toSize = Vector3.new(width, width, length)
	local toCFrame = CFrame.lookAt((a + b) / 2, b)
	if Theme.reducedMotion then
		part.Size = toSize
		part.CFrame = toCFrame
		table.insert(list, { part = part, base = transparency })
		return
	end
	local tip = math.min(length, width)
	local fromSize = Vector3.new(width, width, tip)
	local fromCFrame = CFrame.lookAt(a + along.Unit * (tip / 2), b)
	part.Size = fromSize
	part.CFrame = fromCFrame
	table.insert(list, {
		part = part,
		base = transparency,
		fromSize = fromSize,
		toSize = toSize,
		fromCFrame = fromCFrame,
		toCFrame = toCFrame,
	})
end

-- A pooled emitter whose last spray has died out (its colour may change without recolouring
-- live particles), or a new one while the pool has room; nil when every one is still busy.
local function takeSpark(now: number): Spark?
	for _, spark in sparks do
		if now >= spark.freeAt then
			return spark
		end
	end
	if #sparks >= Theme.COMBAT_RANGE_SPARK_POOL then
		return nil
	end
	local anchor =
		Create("Attachment", { Name = "RangeSparks", Parent = Workspace.Terrain }) :: Attachment
	local emitter = Create("ParticleEmitter", {
		Enabled = false,
		LightEmission = 1,
		LightInfluence = 0,
		Size = NumberSequence.new(Theme.COMBAT_SPARK_SIZE, 0),
		Lifetime = NumberRange.new(
			Theme.COMBAT_SPARK_LIFETIME_MIN,
			Theme.COMBAT_SPARK_LIFETIME_MAX
		),
		Speed = NumberRange.new(Theme.COMBAT_SPARK_SPEED_MIN, Theme.COMBAT_SPARK_SPEED_MAX),
		Acceleration = Vector3.new(0, -Theme.COMBAT_SPARK_GRAVITY, 0),
		Drag = Theme.COMBAT_SPARK_DRAG,
		EmissionDirection = Enum.NormalId.Top,
		Parent = anchor,
	}) :: ParticleEmitter
	local spark: Spark = { anchor = anchor, emitter = emitter, freeAt = 0 }
	table.insert(sparks, spark)
	return spark
end

-- A one-shot particle spray (dropped on low-end devices; the parts carry the information).
-- With a direction the sparks leave along it; without one they fly out all round.
local function sparkBurst(position: Vector3, direction: Vector3?, count: number, color: Color3): ()
	if Theme.lowEndDevice or count <= 0 then
		return
	end
	local now = os.clock()
	local spark = takeSpark(now)
	if spark == nil then
		return
	end
	local axis = if direction ~= nil then unitOf(direction) else nil
	local frame = CFrame.new(position)
	if axis ~= nil then
		local right = basis(axis)
		-- The emitter sprays along the attachment's +Y (EmissionDirection Top).
		frame = CFrame.fromMatrix(position, right, axis)
	end
	local spread = if axis ~= nil then Theme.COMBAT_SPARK_SPREAD else 180
	spark.anchor.WorldCFrame = frame
	spark.emitter.Color = ColorSequence.new(color)
	spark.emitter.SpreadAngle = Vector2.new(spread, spread)
	spark.emitter:Emit(count)
	spark.freeAt = now + Theme.COMBAT_SPARK_LIFETIME_MAX
end

-- A brief point light at a blast (low-end devices skip it).
local function lightFlash(position: Vector3, color: Color3, brightness: number, range: number): ()
	if Theme.lowEndDevice then
		return
	end
	local anchor =
		Create("Attachment", { Name = "RangeFlash", Parent = Workspace.Terrain }) :: Attachment
	anchor.WorldPosition = position
	local light = Create("PointLight", {
		Color = color,
		Brightness = brightness,
		Range = range,
		Shadows = false,
		Parent = anchor,
	}) :: PointLight
	local tween = TweenService:Create(
		light,
		TweenInfo.new(
			Theme.COMBAT_RANGE_BLAST_SECONDS,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		),
		{ Brightness = 0 }
	)
	tween.Completed:Once(function()
		anchor:Destroy()
	end)
	tween:Play()
end

local function play(list: { FxPart }, seconds: number): ()
	if #list == 0 then
		return
	end
	table.insert(effects, { parts = list, started = os.clock(), seconds = seconds })
end

-- The shooter's hand, where a tracer starts. The camera origin is where the shot is aimed
-- from, but a tracer from the eye is invisible to the one firing it.
local function muzzleOf(userId: number): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	local character = if player ~= nil then player.Character else nil
	if character == nil then
		return nil
	end
	local hand = character:FindFirstChild("RightHand")
		or character:FindFirstChild("HumanoidRootPart")
	if hand ~= nil and hand:IsA("BasePart") then
		return hand.Position
	end
	return nil
end

-- Hitbox effect (exact shape) ----------------------------------------------------------

-- The arc's vertical band around its origin, for a body centre (RangeService + HitShapes):
-- the body sphere must overlap [origin.Y - reachDown - pad, origin.Y + pad], so centres lie
-- within +pad+r / -(reachDown+pad+r). An airborne swing's strike (and, from the P3 review, an
-- airborne Whirlwind or Overload Sweep arc) carries endPoint = origin - (0, reachDown, 0); a
-- grounded one has none. r is the thinnest crowd kind's radius, the band every enemy is at
-- least hit in.
local function arcBand(strike: Strike, pad: number): (number, number)
	local radius = math.huge
	for _, kind in config().crowd.kinds do
		radius = math.min(radius, kind.radius)
	end
	if radius == math.huge then
		radius = 0
	end
	local bottom = strike.endPoint
	local reachDown = if bottom ~= nil then math.max(strike.origin.Y - bottom.Y, 0) else 0
	local up = pad + radius
	return up, up + reachDown
end

local function drawArc(
	list: { FxPart },
	strike: Strike,
	pad: number,
	color: Color3,
	fill: number,
	edge: number
): ()
	local heading = flatten(strike.direction)
	if heading == nil then
		return
	end
	local sweep = math.clamp(strike.arcDegrees or 0, 0, 360)
	local half = math.rad(sweep / 2)
	local right = heading:Cross(Vector3.yAxis).Unit
	-- Same parameterisation as HitShapes.Arc: `heading` at 0, sweeping +/- half.
	local points =
		arcPoints(strike.origin, heading, right, strike.size, -half, half, segmentCount(sweep))
	if not Theme.lowEndDevice then
		for index = 1, #points - 1 do
			triangle(list, strike.origin, points[index], points[index + 1], color, fill)
		end
	end
	polyline(list, points, Theme.COMBAT_RANGE_HITBOX_EDGE_WIDTH, Vector3.yAxis, color, edge)
	if sweep < 360 then
		local thin = Theme.COMBAT_RANGE_HITBOX_EDGE_WIDTH / 2
		segment(list, strike.origin, points[1], thin, thin, Vector3.yAxis, color, edge)
		segment(list, strike.origin, points[#points], thin, thin, Vector3.yAxis, color, edge)
	end
	-- The band the slice reaches above and below: thin outer arcs joined by posts at the
	-- ends and the middle, fainter than the slice so the swing itself stays the read.
	local up, down = arcBand(strike, pad)
	local band = (fill + edge) / 2
	local thin = Theme.COMBAT_RANGE_HITBOX_EDGE_WIDTH / 2
	local top = Vector3.new(0, up, 0)
	local bottom = Vector3.new(0, -down, 0)
	for _, lift in { top, bottom } do
		local shifted: { Vector3 } = {}
		for _, point in points do
			table.insert(shifted, point + lift)
		end
		polyline(list, shifted, thin, Vector3.yAxis, color, band)
	end
	for _, index in { 1, (#points + 1) // 2, #points } do
		local point = points[index]
		segment(list, point + bottom, point + top, thin, thin, heading, color, band)
	end
end

local function sphereCentre(strike: Strike): Vector3
	-- A launcher's strike is sent at impact: the blast is at the end point, whatever frame the
	-- origin carries. A slam or shockwave has no end point and is centred on its origin.
	return strike.endPoint or strike.origin
end

local function drawSphere(
	list: { FxPart },
	strike: Strike,
	color: Color3,
	shell: number,
	edge: number
): ()
	local centre = sphereCentre(strike)
	local radius = strike.size
	-- A see-through shell (thinner than an arc's fill, since it covers the whole view when
	-- the player stands inside it) that grows out to the exact radius.
	ball(list, centre, radius * 2, color, shell, true)
	-- The shockwave ring on the sphere's equator reads the radius on the ground.
	local count = segmentCount(360)
	polyline(
		list,
		arcPoints(centre, Vector3.xAxis, Vector3.zAxis, radius, 0, 2 * math.pi, count),
		Theme.COMBAT_RANGE_HITBOX_EDGE_WIDTH,
		Vector3.yAxis,
		color,
		edge
	)
end

-- An ability capsule (the impale dash, a zone) carries its real segment origin → endPoint; a
-- weapon thrust has no end point and runs `size` along its direction.
local function capsuleEnds(strike: Strike): (Vector3, Vector3, number)
	local axis = unitOf(strike.direction) or Vector3.zAxis
	local diameter = strike.width or Theme.COMBAT_RANGE_HITBOX_DEFAULT_WIDTH
	local finish = strike.endPoint
	if finish ~= nil then
		return strike.origin, finish, diameter / 2
	end
	return strike.origin, strike.origin + axis * strike.size, diameter / 2
end

local function drawCapsule(
	list: { FxPart },
	strike: Strike,
	color: Color3,
	fill: number,
	edge: number
): ()
	local a, b, radius = capsuleEnds(strike)
	cylinder(list, a, b, radius * 2, color, fill)
	ball(list, a, radius * 2, color, fill, false)
	ball(list, b, radius * 2, color, fill, false)
	-- The thrust: a bright core and a pair of speed lines shooting out to the tip.
	local axis = unitOf(b - a) or Vector3.zAxis
	local side = basis(axis)
	local core = Theme.COMBAT_RANGE_THRUST_WIDTH
	streak(list, a, b, core, Theme.COMBAT_RANGE_TRACER_COLOR, edge)
	for _, sign in { -1, 1 } do
		local shift = side * (sign * radius * Theme.COMBAT_RANGE_THRUST_LINE_OFFSET)
		streak(list, a + shift, b + shift, core / 2, color, edge)
	end
end

-- Cone half-angle: the strike's arcDegrees is the whole opening, like an arc's sweep.
local function coneHalf(strike: Strike): number
	return math.rad(math.clamp(strike.arcDegrees or 0, 0, 180) / 2)
end

local function drawCone(
	list: { FxPart },
	strike: Strike,
	color: Color3,
	fill: number,
	edge: number
): ()
	local axis = unitOf(strike.direction)
	if axis == nil then
		return
	end
	local half = coneHalf(strike)
	local u, v = basis(axis)
	-- HitShapes.Cone is a spherical sector: its rim is `size` from the apex along the edge.
	local rimCentre = strike.origin + axis * (strike.size * math.cos(half))
	local rimRadius = strike.size * math.sin(half)
	local rim = arcPoints(rimCentre, u, v, rimRadius, 0, 2 * math.pi, segmentCount(360))
	polyline(list, rim, Theme.COMBAT_RANGE_HITBOX_EDGE_WIDTH, axis, color, edge)
	if not Theme.lowEndDevice then
		for index = 1, #rim - 1 do
			triangle(list, strike.origin, rim[index], rim[index + 1], color, fill)
		end
	end
	local thin = Theme.COMBAT_RANGE_HITBOX_EDGE_WIDTH / 2
	local spokes = Theme.COMBAT_RANGE_CONE_SPOKES
	for index = 1, spokes do
		local point = rim[1 + math.floor((index - 1) * (#rim - 1) / spokes)]
		segment(list, strike.origin, point, thin, thin, u, color, edge)
	end
end

local function rayEnd(strike: Strike): Vector3
	local axis = unitOf(strike.direction) or Vector3.zAxis
	return strike.endPoint or strike.origin + axis * strike.size
end

local function impact(list: { FxPart }, position: Vector3, color: Color3): ()
	ball(
		list,
		position,
		Theme.COMBAT_RANGE_IMPACT_SIZE,
		color,
		Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY,
		true
	)
end

local function tracer(list: { FxPart }, from: Vector3, to: Vector3, width: number): ()
	segment(
		list,
		from,
		to,
		width,
		width,
		Vector3.yAxis,
		Theme.COMBAT_RANGE_TRACER_COLOR,
		Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY
	)
end

local function drawRay(list: { FxPart }, strike: Strike, color: Color3): ()
	local finish = rayEnd(strike)
	-- The aimed ray starts at the camera, so the shooter would see it end-on; the tracer runs
	-- from the hand to the same end point, which is where the shot stopped.
	local from = muzzleOf(strike.userId) or strike.origin
	local width = math.max(strike.width or 0, Theme.COMBAT_RANGE_TRACER_WIDTH)
	tracer(list, from, finish, math.min(width, Theme.COMBAT_RANGE_TRACER_WIDTH * 2))
	impact(list, finish, color)
end

-- An ability ray (the overcharged shot) hit everything inside its FULL width, so that whole
-- tube is drawn (a weapon tracer is capped thinner), with a bright core shooting down it.
local function drawAbilityRay(
	list: { FxPart },
	strike: Strike,
	color: Color3,
	fill: number,
	edge: number
): ()
	local finish = rayEnd(strike)
	local from = muzzleOf(strike.userId) or strike.origin
	local diameter = strike.width or Theme.COMBAT_RANGE_HITBOX_DEFAULT_WIDTH
	cylinder(list, from, finish, diameter, color, fill)
	streak(
		list,
		from,
		finish,
		Theme.COMBAT_RANGE_ABILITY_RAY_CORE_WIDTH,
		Theme.COMBAT_RANGE_TRACER_COLOR,
		edge
	)
	ball(list, finish, diameter, color, edge, true)
end

-- Chain lightning ----------------------------------------------------------------------

-- A crowd body's centre as drawn (reaction offsets included), nil once it is gone.
local function centreOf(id: number): Vector3?
	local feet = CrowdRenderer.GetPosition(id)
	if feet == nil then
		return nil
	end
	local height = CrowdRenderer.GetHeight(id) or Theme.COMBAT_RANGE_NUMBER_FALLBACK_HEIGHT
	return feet + Vector3.new(0, height / 2, 0)
end

-- One jagged bolt from a to b: a bright core over a wider faint glow (the glow drops on low-end
-- devices, and so do half the kinks). The kinks are random per client; both ends are exact.
local function bolt(list: { FxPart }, a: Vector3, b: Vector3, opacity: number): ()
	local along = b - a
	local length = along.Magnitude
	if length < EPSILON then
		return
	end
	local u, v = basis(along / length)
	local pieces = math.clamp(
		math.ceil(length / Theme.COMBAT_RANGE_LIGHTNING_KINK_STUDS),
		2,
		Theme.COMBAT_RANGE_LIGHTNING_MAX_KINKS + 1
	)
	if Theme.lowEndDevice then
		pieces = math.max(pieces // 2, 2)
	end
	local jitter = math.min(
		Theme.COMBAT_RANGE_LIGHTNING_JITTER,
		length * Theme.COMBAT_RANGE_LIGHTNING_JITTER_SHARE
	)
	local points: { Vector3 } = { a }
	for index = 1, pieces - 1 do
		local t = index / pieces
		local turn = math.random() * 2 * math.pi
		-- Widest in the middle, pinned at both ends.
		local swing = jitter * math.sin(math.pi * t) * (0.4 + 0.6 * math.random())
		table.insert(points, a + along * t + (u * math.cos(turn) + v * math.sin(turn)) * swing)
	end
	table.insert(points, b)
	local core = 1 - (1 - Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY) * opacity
	polyline(
		list,
		points,
		Theme.COMBAT_RANGE_LIGHTNING_WIDTH,
		u,
		Theme.COMBAT_RANGE_LIGHTNING_CORE_COLOR,
		core
	)
	if not Theme.lowEndDevice then
		local glow = 1 - (1 - Theme.COMBAT_RANGE_LIGHTNING_GLOW_TRANSPARENCY) * opacity
		polyline(
			list,
			points,
			Theme.COMBAT_RANGE_LIGHTNING_GLOW_WIDTH,
			u,
			Theme.COMBAT_RANGE_LIGHTNING_COLOR,
			glow
		)
	end
end

-- One bolt per id pair of strike.links (id 0 = `start`), with a spark where each lands. A pair
-- whose body is already gone is skipped. True when a drawn link left the start.
local function drawLinks(list: { FxPart }, strike: Strike, start: Vector3, opacity: number): boolean
	local links = strike.links
	if links == nil then
		return false
	end
	local fromStart = false
	local count = math.min(#links // 2, Theme.COMBAT_RANGE_LIGHTNING_MAX_LINKS)
	for index = 1, count do
		local fromId = links[index * 2 - 1]
		local toId = links[index * 2]
		local a = if fromId == 0 then start else centreOf(fromId)
		local b = if toId == 0 then start else centreOf(toId)
		if a ~= nil and b ~= nil then
			bolt(list, a, b, opacity)
			sparkBurst(
				b,
				b - a,
				Theme.COMBAT_RANGE_LIGHTNING_SPARKS,
				Theme.COMBAT_RANGE_LIGHTNING_COLOR
			)
			fromStart = fromStart or fromId == 0
		end
	end
	return fromStart
end

-- A Chain Gun shot is lightning from the hand: its links, or on a miss one bolt to where the
-- ray stopped.
local function drawChainShot(list: { FxPart }, strike: Strike, color: Color3, opacity: number): ()
	local from = muzzleOf(strike.userId) or strike.origin
	if not drawLinks(list, strike, from, opacity) then
		local finish = rayEnd(strike)
		bolt(list, from, finish, opacity)
		impact(list, finish, color)
	end
end

-- An arrow strike: its flight was already drawn, so the strike marks where it went: shards and
-- sparks bursting forward out of every enemy it pierced, and a small flash where it stopped.
local function drawArrowHits(list: { FxPart }, strike: Strike, color: Color3, tube: number?): ()
	local axis = unitOf(strike.direction) or Vector3.zAxis
	local finish = strike.endPoint
	local u, v = basis(axis)
	local shards = Theme.COMBAT_RANGE_PIERCE_SHARDS
	local spread = math.rad(Theme.COMBAT_RANGE_PIERCE_SPREAD_DEGREES)
	local length = Theme.COMBAT_RANGE_PIERCE_SHARD_LENGTH
	for _, hit in strike.hits do
		local feet = CrowdRenderer.GetPosition(hit.id)
		if feet ~= nil then
			local height = CrowdRenderer.GetHeight(hit.id)
				or Theme.COMBAT_RANGE_NUMBER_FALLBACK_HEIGHT
			local centre = feet + Vector3.new(0, height / 2, 0)
			-- A full-charge blast strike mixes the arrow's last hits with the blast's victims;
			-- only bodies on the arrow's line, behind its end point, were pierced.
			local pierced = true
			if tube ~= nil and finish ~= nil then
				local offset = centre - finish
				local along = offset:Dot(axis)
				pierced = along <= tube and (offset - axis * along).Magnitude <= tube
			end
			if not pierced then
				continue
			end
			for index = 1, shards do
				local turn = 2 * math.pi * index / shards
				local dir = (
					axis * math.cos(spread)
					+ (u * math.cos(turn) + v * math.sin(turn)) * math.sin(spread)
				).Unit
				streak(
					list,
					centre,
					centre + dir * length,
					Theme.COMBAT_RANGE_TRACER_WIDTH / 2,
					color,
					Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY
				)
			end
			sparkBurst(
				centre,
				axis,
				Theme.COMBAT_RANGE_PIERCE_SPARKS,
				Theme.COMBAT_RANGE_TRACER_COLOR
			)
		end
	end
	-- Only the strike that ends the arrow names where it stopped (a blast draws its own core).
	if finish ~= nil and tube == nil then
		ball(
			list,
			finish,
			Theme.COMBAT_RANGE_PELLET_IMPACT_SIZE,
			Theme.COMBAT_RANGE_TRACER_COLOR,
			Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY,
			true
		)
	end
end

-- A projectile's sphere strike (launcher shell, full-charge arrow): on top of the shockwave,
-- a hot core flash, a spray of sparks all round and a light. A bow blast burns gold.
local function drawBlast(list: { FxPart }, strike: Strike, variant: Types.RangeWeaponVariant): ()
	local centre = sphereCentre(strike)
	local bowBlast = variant.shape ~= "sphere"
	local color = if bowBlast
		then Theme.COMBAT_RANGE_CHARGE_COLOR
		else Theme.COMBAT_RANGE_BLAST_COLOR
	ball(
		list,
		centre,
		strike.size * 2 * Theme.COMBAT_RANGE_BLAST_CORE_SCALE,
		color,
		Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY,
		true
	)
	sparkBurst(centre, nil, Theme.COMBAT_RANGE_BLAST_SPARKS, color)
	lightFlash(centre, color, Theme.COMBAT_RANGE_BLAST_LIGHT_BRIGHTNESS, strike.size * 2)
end

-- Cosmetic pellet tracers inside the cone (the server tests the whole cone, not these rays),
-- seeded by the strike's seq so every client draws the same pattern. Each stops at the first
-- crowd body or wall it meets on this client: one pass over the crowd, one raycast each.
local function drawPellets(list: { FxPart }, strike: Strike, variant: Types.RangeWeaponVariant?): ()
	local seq = strike.seq
	if seq == nil or variant == nil or variant.pellets == nil then
		return
	end
	local origin = strike.origin
	local reach = strike.size
	local bodies: { Body } = {}
	CrowdRenderer.ForEach(
		function(_id: number, feet: Vector3, radius: number, headRadius: number, height: number)
			local centre = feet + Vector3.new(0, height / 2, 0)
			if (centre - origin).Magnitude <= reach + height then
				table.insert(bodies, { centre = centre, radius = radius })
				local head = feet + Vector3.new(0, height - headRadius, 0)
				table.insert(bodies, { centre = head, radius = headRadius })
			end
		end
	)
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignore, character)
		end
	end
	local folder = fxFolder
	if folder ~= nil then
		table.insert(ignore, folder)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local from = muzzleOf(strike.userId) or origin
	local halfAngle = (strike.arcDegrees or 0) / 2
	for _, direction in HitShapes.Pellets(strike.direction, variant.pellets, halfAngle, seq) do
		local stop = reach
		local wall = Workspace:Raycast(origin, direction * reach, params)
		if wall ~= nil then
			stop = wall.Distance
		end
		for _, body in bodies do
			local entry = HitShapes.Ray(origin, direction, stop, 0, 0, body.centre, body.radius)
			if entry ~= nil and entry < stop then
				stop = entry
			end
		end
		local finish = origin + direction * stop
		tracer(list, from, finish, Theme.COMBAT_RANGE_TRACER_WIDTH / 2)
		if stop < reach then
			ball(
				list,
				finish,
				Theme.COMBAT_RANGE_PELLET_IMPACT_SIZE,
				Theme.COMBAT_RANGE_TRACER_COLOR,
				Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY,
				true
			)
		end
	end
end

-- How long a hitbox effect of this strength holds (strength above 1 lets it linger).
local function hitboxSeconds(strength: number): number
	return math.clamp(
		Theme.COMBAT_RANGE_HITBOX_SECONDS * math.max(strength, 1),
		Theme.COMBAT_RANGE_HITBOX_SECONDS,
		Theme.COMBAT_RANGE_HITBOX_MAX_SECONDS
	)
end

-- `flight`: the strike resolves a projectile (its flight was drawn from the shot). `chain`: a
-- Chain Gun shot, drawn as lightning instead of a tracer.
local function drawHitbox(
	strike: Strike,
	variant: Types.RangeWeaponVariant?,
	impactValues: Impact,
	strength: number,
	crit: boolean,
	flight: boolean,
	chain: boolean
): ()
	if strength <= 0 then
		return
	end
	local list: { FxPart } = {}
	local color = if crit
		then Theme.COMBAT_RANGE_HITBOX_CRIT_COLOR
		elseif strike.ability ~= nil then Theme.COMBAT_RANGE_ABILITY_COLOR
		else Theme.COMBAT_RANGE_HITBOX_COLOR
	-- Strength fades the effect in (below 1) and lets it linger (above 1).
	local opacity = math.min(strength, 1)
	local fill = 1 - (1 - Theme.COMBAT_RANGE_HITBOX_FILL_TRANSPARENCY) * opacity
	local edge = 1 - (1 - Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY) * opacity
	local shape = strike.shape
	if shape == "arc" then
		drawArc(list, strike, impactValues.pad, color, fill, edge)
	elseif shape == "sphere" then
		local shell = 1 - (1 - Theme.COMBAT_RANGE_HITBOX_SPHERE_TRANSPARENCY) * opacity
		drawSphere(list, strike, color, shell, edge)
		if variant ~= nil and variant.kind == "ranged" then
			if flight or variant.shape ~= "sphere" then
				if variant.shape == "ray" then
					-- A bow's full-charge end strike also carries the arrow's final-frame hits.
					local tube = (variant.width or 0) / 2
						+ variant.pad
						+ Theme.COMBAT_RANGE_PIERCE_TUBE_PAD
					drawArrowHits(list, strike, color, tube)
				end
				drawBlast(list, strike, variant)
			else
				-- A hitscan blast never flew, so a trail from the hand shows where it went.
				local centre = sphereCentre(strike)
				local from = muzzleOf(strike.userId)
				if
					from ~= nil
					and (centre - from).Magnitude > Theme.COMBAT_RANGE_TRAIL_MIN_STUDS
				then
					tracer(list, from, centre, Theme.COMBAT_RANGE_TRACER_WIDTH)
				end
			end
		end
	elseif shape == "capsule" then
		drawCapsule(list, strike, color, fill, edge)
	elseif shape == "cone" then
		drawCone(list, strike, color, fill, edge)
		drawPellets(list, strike, variant)
	elseif shape == "ray" then
		if flight then
			drawArrowHits(list, strike, color, nil)
		elseif chain then
			drawChainShot(list, strike, color, opacity)
		elseif strike.ability ~= nil then
			drawAbilityRay(list, strike, color, fill, edge)
		else
			drawRay(list, strike, color)
		end
	end
	play(list, hitboxSeconds(strength))
end

-- The lightning of an ability strike (Storm Coil ticks included): its links from the strike
-- origin, drawn even when the tick itself skips the generic flash.
local function drawAbilityLinks(strike: Strike, strength: number): ()
	if strength <= 0 or strike.links == nil then
		return
	end
	local list: { FxPart } = {}
	-- Storm Coil's origin is its ground point; its bolts leave the glowing top AbilityFx draws.
	local start = if strike.ability == COIL_ABILITY
		then strike.origin + Vector3.new(0, Theme.COMBAT_RANGE_COIL_TOP_HEIGHT, 0)
		else strike.origin
	drawLinks(list, strike, start, math.min(strength, 1))
	play(
		list,
		math.min(
			Theme.COMBAT_RANGE_LIGHTNING_SECONDS * math.max(strength, 1),
			Theme.COMBAT_RANGE_HITBOX_MAX_SECONDS
		)
	)
end

-- Wireframe (true padded shape) ---------------------------------------------------------

local function wireCircle(
	list: { FxPart },
	centre: Vector3,
	u: Vector3,
	v: Vector3,
	radius: number
): ()
	local color = Theme.COMBAT_RANGE_WIRE_COLOR
	local t = Theme.COMBAT_RANGE_WIRE_TRANSPARENCY
	local points =
		arcPoints(centre, u, v, radius, 0, 2 * math.pi, Theme.COMBAT_RANGE_WIRE_CIRCLE_SEGMENTS)
	polyline(list, points, Theme.COMBAT_RANGE_WIRE_THICKNESS, u:Cross(v).Unit, color, t)
end

local function wireLine(list: { FxPart }, a: Vector3, b: Vector3): ()
	local w = Theme.COMBAT_RANGE_WIRE_THICKNESS
	segment(
		list,
		a,
		b,
		w,
		w,
		Vector3.yAxis,
		Theme.COMBAT_RANGE_WIRE_COLOR,
		Theme.COMBAT_RANGE_WIRE_TRANSPARENCY
	)
end

-- The flat arc grown by pad: the outer arc at range + pad, both straight edges pushed out by
-- pad, a pad-radius cap around the apex; drawn at the slice and at +/- pad (its vertical
-- reach, HitShapes.Arc).
local function wireArc(list: { FxPart }, strike: Strike, pad: number): ()
	local heading = flatten(strike.direction)
	if heading == nil then
		return
	end
	local sweep = math.clamp(strike.arcDegrees or 0, 0, 360)
	local half = math.rad(sweep / 2)
	local right = heading:Cross(Vector3.yAxis).Unit
	local count = segmentCount(sweep)
	local up, down = arcBand(strike, pad)
	for _, lift in { -down, 0, up } do
		local origin = strike.origin + Vector3.new(0, lift, 0)
		local outer = arcPoints(origin, heading, right, strike.size + pad, -half, half, count)
		local w = Theme.COMBAT_RANGE_WIRE_THICKNESS
		polyline(
			list,
			outer,
			w,
			Vector3.yAxis,
			Theme.COMBAT_RANGE_WIRE_COLOR,
			Theme.COMBAT_RANGE_WIRE_TRANSPARENCY
		)
		if sweep < 360 then
			for _, sign in { -1, 1 } do
				local angle = sign * half
				local edgeDir = heading * math.cos(angle) + right * math.sin(angle)
				local outward = heading * math.cos(angle + sign * math.pi / 2)
					+ right * math.sin(angle + sign * math.pi / 2)
				local edgeEnd = origin + edgeDir * strike.size + outward * pad
				wireLine(list, origin + outward * pad, edgeEnd)
				if lift == 0 then
					-- Posts at the outer corners show the band's full height.
					local corner = strike.origin + edgeDir * (strike.size + pad)
					wireLine(list, corner - Vector3.new(0, down, 0), corner + Vector3.new(0, up, 0))
				end
				-- The rounded corner to the outer arc, drawn as its chord.
				wireLine(list, edgeEnd, origin + edgeDir * (strike.size + pad))
			end
			-- The apex cap runs behind the swing, from one edge's outward normal to the other.
			local cap = arcPoints(
				origin,
				heading,
				right,
				pad,
				half + math.pi / 2,
				2 * math.pi - half - math.pi / 2,
				math.max(count // 2, 3)
			)
			polyline(
				list,
				cap,
				w,
				Vector3.yAxis,
				Theme.COMBAT_RANGE_WIRE_COLOR,
				Theme.COMBAT_RANGE_WIRE_TRANSPARENCY
			)
		end
	end
end

local function drawWireframe(strike: Strike, impactValues: Impact): ()
	local list: { FxPart } = {}
	local pad = impactValues.pad
	local shape = strike.shape
	if shape == "arc" then
		wireArc(list, strike, pad)
	elseif shape == "sphere" then
		local centre = sphereCentre(strike)
		local radius = strike.size + pad
		wireCircle(list, centre, Vector3.xAxis, Vector3.zAxis, radius)
		wireCircle(list, centre, Vector3.xAxis, Vector3.yAxis, radius)
		wireCircle(list, centre, Vector3.zAxis, Vector3.yAxis, radius)
	elseif shape == "capsule" then
		local a, b, radius = capsuleEnds(strike)
		local grown = radius + pad
		local axis = unitOf(b - a) or Vector3.zAxis
		local u, v = basis(axis)
		wireCircle(list, a, u, v, grown)
		wireCircle(list, b, u, v, grown)
		for _, offset in { u, -u, v, -v } do
			wireLine(list, a + offset * grown, b + offset * grown)
		end
	elseif shape == "cone" then
		local axis = unitOf(strike.direction)
		if axis == nil then
			return
		end
		local half = coneHalf(strike)
		local u, v = basis(axis)
		local rimCentre = strike.origin + axis * (strike.size * math.cos(half))
		wireCircle(list, rimCentre, u, v, strike.size * math.sin(half) + pad)
		wireCircle(list, strike.origin, u, v, pad)
		for _, side in { u, -u, v, -v } do
			local edgeDir = axis * math.cos(half) + side * math.sin(half)
			local outward = (axis * -math.sin(half) + side * math.cos(half)).Unit
			wireLine(
				list,
				strike.origin + outward * pad,
				strike.origin + edgeDir * strike.size + outward * pad
			)
		end
	elseif shape == "ray" then
		local axis = unitOf(strike.direction) or Vector3.zAxis
		local finish = rayEnd(strike)
		local reach = (strike.width or 0) / 2 + pad
		local u, v = basis(axis)
		for _, offset in { u, -u, v, -v } do
			wireLine(list, strike.origin + offset * reach, finish + offset * reach)
		end
		wireCircle(list, finish, u, v, reach)
	end
	play(list, Theme.COMBAT_RANGE_WIRE_SECONDS)
end

-- Damage numbers -----------------------------------------------------------------------

local function newBurst(playerGui: Instance): Burst
	local anchor =
		Create("Attachment", { Name = "RangeNumberAnchor", Parent = Workspace.Terrain }) :: Attachment
	local gui = Create("BillboardGui", {
		Name = "RangeNumber",
		Adornee = anchor,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Enabled = false,
		Parent = playerGui,
	}) :: BillboardGui
	local scale = Create("UIScale", { Parent = gui }) :: UIScale
	local main = Create("TextLabel", {
		Name = "Total",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0.68),
		Font = Theme.FONT_BOLD,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "",
		Parent = gui,
	}) :: TextLabel
	local count = Create("TextLabel", {
		Name = "Count",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0, 0.64),
		Size = UDim2.fromScale(1, 0.36),
		Font = Theme.FONT_BOLD,
		TextColor3 = Theme.COLOR_TEXT,
		Text = "",
		Parent = gui,
	}) :: TextLabel
	local strokes: { UIStroke } = {}
	for _, label in { main, count } do
		table.insert(
			strokes,
			Create("UIStroke", {
				Color = Theme.COLOR_TEXT_DARK,
				Thickness = Theme.STROKE_THICKNESS,
				Parent = label,
			}) :: UIStroke
		)
	end
	return {
		gui = gui,
		anchor = anchor,
		scale = scale,
		main = main,
		count = count,
		strokes = strokes,
		started = 0,
		popAt = 0,
		side = 1,
		pop = 1,
		active = false,
		token = 0,
		target = nil,
	}
end

-- A free burst, or the oldest one recycled: a fast gun into a crowd must never pile up more
-- than MAX_ACTIVE billboards. A merged burst held open has a future `started`, so it is the
-- last to be taken.
local function takeBurst(): Burst?
	local oldest: Burst? = nil
	local chosen: Burst? = nil
	for _, burst in bursts do
		if not burst.active then
			chosen = burst
			break
		end
		if oldest == nil or burst.started < oldest.started then
			oldest = burst
		end
	end
	if chosen == nil and #bursts < Theme.COMBAT_RANGE_NUMBER_MAX_ACTIVE then
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui == nil then
			return nil
		end
		local burst = newBurst(playerGui)
		table.insert(bursts, burst)
		chosen = burst
	end
	local taken = chosen or oldest
	if taken ~= nil then
		taken.token += 1
		taken.target = nil
	end
	return taken
end

-- Top of a crowd body as drawn: CrowdRenderer.GetPosition is the feet (reaction offsets
-- included), so the head is one body height up. nil once the body is gone.
local function topOf(id: number): Vector3?
	local feet = CrowdRenderer.GetPosition(id)
	if feet == nil then
		return nil
	end
	local height = CrowdRenderer.GetHeight(id) or Theme.COMBAT_RANGE_NUMBER_FALLBACK_HEIGHT
	return feet + Vector3.new(0, height, 0)
end

local function burstPosition(strike: Strike): Vector3
	local sum = Vector3.zero
	local top = -math.huge
	local sampled = 0
	for _, hit in strike.hits do
		if sampled >= BURST_SAMPLE then
			break
		end
		local point = topOf(hit.id)
		if point ~= nil then
			sum += point
			top = math.max(top, point.Y)
			sampled += 1
		end
	end
	if sampled > 0 then
		local centre = sum / sampled
		return Vector3.new(centre.X, top + Theme.COMBAT_RANGE_NUMBER_HEAD_CLEARANCE, centre.Z)
	end
	-- Every body already gone (killed and removed): fall back to where the shape landed.
	if strike.shape == "sphere" then
		return sphereCentre(strike)
	elseif strike.shape == "ray" then
		return rayEnd(strike)
	end
	local axis = unitOf(strike.direction) or Vector3.zAxis
	return strike.origin + axis * strike.size * 0.5
end

-- A total and its "×N" (enemies hit) written into a burst, sized by the crowd and the strength.
local function paintBurst(
	burst: Burst,
	total: number,
	count: number,
	crit: boolean,
	strength: number
): ()
	local size = math.clamp(
		strength,
		Theme.COMBAT_RANGE_NUMBER_MIN_STRENGTH,
		Theme.COMBAT_RANGE_NUMBER_MAX_STRENGTH
	)
	local color = if crit then Theme.COMBAT_RANGE_CRIT_COLOR else Theme.COLOR_TEXT
	-- Bigger crowds make bigger numbers: a few px per doubling of the hit count.
	local text = (
		if crit then Theme.COMBAT_RANGE_NUMBER_CRIT_TEXT else Theme.COMBAT_RANGE_NUMBER_TEXT
	) + Theme.COMBAT_RANGE_NUMBER_GROWTH_PER_DOUBLING * math.log(math.max(count, 1), 2)
	burst.main.TextSize = math.floor(math.min(text, Theme.COMBAT_RANGE_NUMBER_MAX_TEXT))
	burst.main.Text = Format.Cash(total)
	burst.main.TextColor3 = color
	burst.count.TextSize = Theme.COMBAT_RANGE_NUMBER_COUNT_TEXT
	burst.count.Text = if count > 1 then "×" .. Format.Cash(count) else ""
	burst.count.TextColor3 = color
	burst.gui.Size = UDim2.fromOffset(
		Theme.COMBAT_RANGE_NUMBER_WIDTH * layoutScale * size,
		Theme.COMBAT_RANGE_NUMBER_HEIGHT * layoutScale * size
	)
end

-- Shows a painted burst at `position`: popped now, fully opaque, and still until `started`.
local function launchBurst(burst: Burst, position: Vector3): ()
	burst.main.TextTransparency = 0
	burst.count.TextTransparency = 0
	for _, stroke in burst.strokes do
		stroke.Transparency = 0
	end
	burst.anchor.WorldPosition = position
	burst.gui.StudsOffset = Vector3.zero
	burst.side = if math.random() < 0.5 then -1 else 1
	burst.pop = if Theme.reducedMotion
		then Theme.COMBAT_RANGE_NUMBER_REDUCED_POP_SCALE
		else Theme.COMBAT_RANGE_NUMBER_POP_SCALE
	burst.scale.Scale = burst.pop
	local now = os.clock()
	burst.popAt = now
	burst.started = now
	burst.active = true
	burst.gui.Enabled = true
end

local function showNumbers(strike: Strike, total: number, crit: boolean, strength: number): ()
	if strength <= 0 or total <= 0 then
		return
	end
	local burst = takeBurst()
	if burst == nil then
		return
	end
	paintBurst(burst, total, #strike.hits, crit, strength)
	launchBurst(burst, burstPosition(strike))
end

-- Lasting hits (ticks, a held beam) of one shooter + ability run into ONE burst: the first
-- opens it, each later one arriving within `gap` of the previous adds to it, re-pops it a
-- little and holds it open over the latest hits; it falls once the hits stop or it has been
-- open TICK_MERGE_MAX_SECONDS (the next hit then opens a fresh one). "×N" counts the distinct
-- enemies. Returns the kills the open burst has counted so far (this strike's alone when
-- numbers are off).
local function mergeNumbers(
	key: string,
	strike: Strike,
	total: number,
	crit: boolean,
	kills: number,
	gap: number,
	strength: number
): number
	local now = os.clock()
	local maxOpen = Theme.COMBAT_RANGE_TICK_MERGE_MAX_SECONDS
	local merge: Merge? = merges[key]
	if
		merge ~= nil
		and (
			merge.burst.token ~= merge.token
			or not merge.burst.active
			or now - merge.lastAt > gap
			or now - merge.openedAt >= maxOpen
		)
	then
		merges[key] = nil
		merge = nil
	end
	if strength <= 0 or total <= 0 then
		return if merge ~= nil then merge.kills + kills else kills
	end
	local opened = merge == nil
	local running: Merge
	if merge ~= nil then
		running = merge
	else
		local burst = takeBurst()
		if burst == nil then
			return kills
		end
		running = {
			burst = burst,
			token = burst.token,
			total = 0,
			crit = false,
			ids = {},
			count = 0,
			kills = 0,
			openedAt = now,
			lastAt = now,
		}
		merges[key] = running
	end
	running.total += total
	running.crit = running.crit or crit
	running.kills += kills
	running.lastAt = now
	for _, hit in strike.hits do
		if not running.ids[hit.id] then
			running.ids[hit.id] = true
			running.count += 1
		end
	end
	local burst = running.burst
	paintBurst(burst, running.total, running.count, running.crit, strength)
	local position = burstPosition(strike)
	if opened then
		launchBurst(burst, position)
	else
		burst.pop = if Theme.reducedMotion
			then Theme.COMBAT_RANGE_TICK_REDUCED_POP_SCALE
			else Theme.COMBAT_RANGE_TICK_POP_SCALE
		burst.popAt = now
		burst.target = position
	end
	-- Held until the next hit is overdue, never past the merge's own cap.
	burst.started = math.min(now + gap, running.openedAt + maxOpen)
	return running.kills
end

-- Pop, then an arc that peaks and falls below its start (Fortnite-style), fading at the end.
-- A merged burst held open (now < started) stays put at full size between its re-pops and
-- drifts to its latest hits.
local function stepBurst(burst: Burst, now: number, deltaTime: number): ()
	local seconds = Theme.COMBAT_RANGE_NUMBER_SECONDS
	local u = math.max(now - burst.started, 0) / seconds
	if u >= 1 then
		burst.active = false
		burst.gui.Enabled = false
		burst.target = nil
		return
	end
	local popLeft = math.max(0, 1 - (now - burst.popAt) / Theme.COMBAT_RANGE_NUMBER_POP_SECONDS)
	burst.scale.Scale = 1 + (burst.pop - 1) * popLeft
	local target = burst.target
	if target ~= nil then
		local alpha = if Theme.reducedMotion
			then 1
			else 1 - math.exp(-Theme.COMBAT_RANGE_NUMBER_FOLLOW_RATE * deltaTime)
		burst.anchor.WorldPosition = burst.anchor.WorldPosition:Lerp(target, alpha)
	end
	local drift = if Theme.reducedMotion then 0 else Theme.COMBAT_RANGE_NUMBER_DRIFT
	burst.gui.StudsOffset = Vector3.new(
		burst.side * drift * u,
		Theme.COMBAT_RANGE_NUMBER_RISE * (3 * u - 3.6 * u * u),
		0
	)
	local fadeFrom = Theme.COMBAT_RANGE_NUMBER_FADE_FROM
	local fade = if u <= fadeFrom then 0 else (u - fadeFrom) / (1 - fadeFrom)
	burst.main.TextTransparency = fade
	burst.count.TextTransparency = fade
	for _, stroke in burst.strokes do
		stroke.Transparency = fade
	end
end

-- Enemy reactions ----------------------------------------------------------------------

-- Away from the attack: along a ray, or from the shape's origin (a sphere's centre) to the
-- body for the shapes that spread out from a point.
local function awayFrom(strike: Strike, id: number): Vector3
	if strike.shape ~= "ray" then
		local position = CrowdRenderer.GetPosition(id)
		local from = if strike.shape == "sphere" then sphereCentre(strike) else strike.origin
		if position ~= nil then
			local away = flatten(position - from)
			if away ~= nil then
				return away
			end
		end
	end
	return flatten(strike.direction) or Vector3.zAxis
end

-- CrowdRenderer owns the body motion; the strength is the layer's alone (Render's contract),
-- and the server has already applied the real push, so a heavier weapon reads heavier on its
-- own through the snapshot positions. Without "death" within its grace window the renderer
-- kills the body itself, so every killed hit names it here.
local function react(strike: Strike, impactValues: Impact): ()
	local flash = feedbackStrength("enemyFlash")
	local reaction = feedbackStrength("enemyReaction")
	if flash <= 0 and reaction <= 0 then
		return
	end
	-- A pulling ability (Blade Storm) drags bodies toward its centre, so they react inward.
	local pulls = impactValues.pull > 0
	local knocks = impactValues.knockback > 0 or pulls
	local launches = impactValues.launch > 0
	for _, hit in strike.hits do
		if flash > 0 then
			CrowdRenderer.React(hit.id, "flash", nil, flash)
		end
		if reaction > 0 then
			local away = awayFrom(strike, hit.id)
			if pulls then
				away = -away
			end
			CrowdRenderer.React(hit.id, "flinch", away, reaction)
			if knocks then
				CrowdRenderer.React(hit.id, "knockback", away, reaction)
			end
			if launches then
				CrowdRenderer.React(hit.id, "launch", away, reaction)
			end
			if hit.killed then
				CrowdRenderer.React(hit.id, "death", away, reaction)
			end
		end
	end
end

-- Screen -------------------------------------------------------------------------------

-- Hitstop freezes the local character's animations for a beat. The body keeps its physics:
-- stopping the root would fight the dash and the air hang, which are gameplay.
local function hitstop(seconds: number): ()
	if seconds <= 0 then
		return
	end
	local now = os.clock()
	local finish = now + seconds
	if finish <= hitstopUntil then
		return
	end
	hitstopUntil = finish
	local character = Players.LocalPlayer.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	local animator = if humanoid ~= nil then humanoid:FindFirstChildOfClass("Animator") else nil
	if animator == nil then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if frozenTracks[track] == nil then
			frozenTracks[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
end

local function releaseHitstop(): ()
	for track, speed in frozenTracks do
		if track.IsPlaying then
			track:AdjustSpeed(speed)
		end
	end
	table.clear(frozenTracks)
end

local function detectHaptics(): ()
	table.clear(hapticTargets)
	for _, input in HAPTIC_INPUTS do
		local ok, supported = pcall(function()
			return HapticService:IsVibrationSupported(input)
		end)
		if ok and supported == true then
			for _, motor in HAPTIC_MOTORS do
				local motorOk, motorSupported = pcall(function()
					return HapticService:IsMotorSupported(input, motor)
				end)
				if motorOk and motorSupported == true then
					table.insert(hapticTargets, { input = input, motor = motor })
				end
			end
		end
	end
end

local function setMotors(value: number): ()
	for _, target in hapticTargets do
		-- pcall: a gamepad unplugged mid-fight must not break the feedback loop.
		pcall(function()
			HapticService:SetMotor(target.input, target.motor, value)
		end)
	end
end

local function pulse(amount: number, seconds: number): ()
	if amount <= 0 or #hapticTargets == 0 then
		return
	end
	hapticToken += 1
	local token = hapticToken
	setMotors(math.clamp(amount, 0, 1))
	task.delay(seconds, function()
		if token == hapticToken then
			setMotors(0)
		end
	end)
end

local function edgeFlash(strength: number): ()
	if strength <= 0 or #edgeBars == 0 then
		return
	end
	local start = 1 - (1 - Theme.COMBAT_RANGE_EDGE_FLASH_TRANSPARENCY) * math.min(strength, 1)
	local info = Motion.Info(
		Theme.COMBAT_RANGE_EDGE_FLASH_SECONDS,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	for _, bar in edgeBars do
		bar.BackgroundTransparency = start
		TweenService:Create(bar, info, { BackgroundTransparency = 1 }):Play()
	end
end

-- Counters -----------------------------------------------------------------------------

local function popCounter(label: TextLabel): ()
	local popScale = label:FindFirstChildOfClass("UIScale")
	if popScale == nil then
		return
	end
	local peak = if Theme.reducedMotion
		then 1 + (Theme.COMBAT_RANGE_COUNTER_POP_SCALE - 1) * Theme.REDUCED_MOTION_FACTOR
		else Theme.COMBAT_RANGE_COUNTER_POP_SCALE
	popScale.Scale = peak
	TweenService
		:Create(popScale, Motion.Info(Theme.COMBAT_RANGE_COUNTER_POP_SECONDS), { Scale = 1 })
		:Play()
end

local function fadeLabel(label: TextLabel, visible: boolean): ()
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local goal = if visible then 0 else 1
	if visible then
		label.TextTransparency = 0
		if stroke ~= nil then
			stroke.Transparency = 0
		end
		return
	end
	local info = Motion.Info(Theme.COMBAT_RANGE_COUNTER_FADE_SECONDS)
	TweenService:Create(label, info, { TextTransparency = goal }):Play()
	if stroke ~= nil then
		TweenService:Create(stroke, info, { Transparency = goal }):Play()
	end
end

local function updateCounters(hits: number, kills: number, strength: number): ()
	local root = counterRoot
	local value = comboValue
	local caption = comboCaption
	local killLine = killsLabel
	local scale = counterScale
	if root == nil or value == nil or caption == nil or killLine == nil or scale == nil then
		return
	end
	if strength <= 0 then
		root.Visible = false
		return
	end
	root.Visible = true
	scale.Scale = layoutScale
		* math.clamp(
			strength,
			Theme.COMBAT_RANGE_NUMBER_MIN_STRENGTH,
			Theme.COMBAT_RANGE_NUMBER_MAX_STRENGTH
		)
	local now = os.clock()
	if now > comboExpires then
		combo = 0
	end
	combo += hits
	comboExpires = now + Theme.COMBAT_RANGE_COMBO_WINDOW_SECONDS
	value.Text = Format.Cash(combo)
	fadeLabel(value, true)
	fadeLabel(caption, true)
	popCounter(value)
	if kills > 0 then
		killsToken += 1
		local token = killsToken
		killLine.Text = Format.Cash(kills) .. (if kills == 1 then " KILL" else " KILLS")
		fadeLabel(killLine, true)
		popCounter(killLine)
		task.delay(Theme.COMBAT_RANGE_KILLS_SECONDS, function()
			if token == killsToken then
				fadeLabel(killLine, false)
			end
		end)
	end
end

local function expireCombo(now: number): ()
	if combo > 0 and now > comboExpires then
		combo = 0
		local value = comboValue
		local caption = comboCaption
		if value ~= nil and caption ~= nil then
			fadeLabel(value, false)
			fadeLabel(caption, false)
		end
	end
end

-- Flights ----------------------------------------------------------------------------

-- The world a projectile can stop against: everything but characters and our own fx (crowd
-- bodies are not queryable, so a piercing arrow flies on through them, as on the server).
local function flightParams(): RaycastParams
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignore, character)
		end
	end
	local folder = fxFolder
	if folder ~= nil then
		table.insert(ignore, folder)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	-- The server's projectile ray ignores non-colliding parts; a flight must pass them too.
	params.RespectCanCollide = true
	return params
end

local function maxFlightSeconds(): number
	return config().shooting.projectileMaxSeconds
end

-- The flying body: a shaft (or ball) with a camera-facing trail from its tail.
local function buildProjectile(shell: boolean, glow: boolean): BasePart
	local color = if glow
		then Theme.COMBAT_RANGE_CHARGE_COLOR
		elseif shell then Theme.COMBAT_RANGE_SHELL_COLOR
		else Theme.COMBAT_RANGE_ARROW_COLOR
	local thickness = Theme.COMBAT_RANGE_ARROW_THICKNESS
	local length = Theme.COMBAT_RANGE_ARROW_LENGTH
	local part = Create("Part", {
		Name = if shell then "RangeShell" else "RangeArrow",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Shape = if shell then Enum.PartType.Ball else Enum.PartType.Block,
		Size = if shell
			then Vector3.one * Theme.COMBAT_RANGE_SHELL_SIZE
			else Vector3.new(thickness, thickness, length),
		Material = if glow or shell then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		Color = color,
		Parent = fxFolder,
	}) :: Part
	local width = if glow
		then Theme.COMBAT_RANGE_ARROW_GLOW_TRAIL_WIDTH
		else Theme.COMBAT_RANGE_ARROW_TRAIL_WIDTH
	-- The part looks along -Z, so the tail is at +Z.
	local tail = if shell then 0 else length / 2
	local top =
		Create("Attachment", { Position = Vector3.new(0, width / 2, tail), Parent = part }) :: Attachment
	local bottom = Create(
		"Attachment",
		{ Position = Vector3.new(0, -width / 2, tail), Parent = part }
	) :: Attachment
	local trailColor = if glow
		then Theme.COMBAT_RANGE_CHARGE_COLOR
		elseif shell then Theme.COMBAT_RANGE_SHELL_TRAIL_COLOR
		else Theme.COMBAT_RANGE_TRACER_COLOR
	Create("Trail", {
		Attachment0 = top,
		Attachment1 = bottom,
		FaceCamera = true,
		LightEmission = if shell then 0 else 1,
		Lifetime = Theme.COMBAT_RANGE_ARROW_TRAIL_SECONDS,
		MinLength = 0,
		Color = ColorSequence.new(trailColor),
		Transparency = NumberSequence.new(Theme.COMBAT_RANGE_ARROW_TRAIL_TRANSPARENCY, 1),
		WidthScale = NumberSequence.new(1, 0),
		Parent = part,
	})
	if glow and not Theme.lowEndDevice then
		Create("PointLight", {
			Color = color,
			Brightness = Theme.COMBAT_RANGE_ARROW_LIGHT_BRIGHTNESS,
			Range = Theme.COMBAT_RANGE_ARROW_LIGHT_RANGE,
			Shadows = false,
			Parent = part,
		})
	end
	return part
end

-- The flight's true position and velocity t seconds in (the server's ballistic).
local function ballistic(flight: Flight, t: number): (Vector3, Vector3)
	local g = Vector3.new(0, -flight.gravity, 0)
	return flight.origin + flight.velocity * t + g * (0.5 * t * t), flight.velocity + g * t
end

-- The body stops where it is and its trail is left to fade before it goes.
local function endFlight(index: number, at: Vector3?): ()
	if index < 1 or index > #flights then
		return
	end
	local flight = table.remove(flights, index)
	if flight == nil then
		return
	end
	local part = flight.part
	if at ~= nil then
		part.Position = at
	end
	part.Transparency = 1
	for _, child in part:GetChildren() do
		if child:IsA("PointLight") then
			child.Enabled = false
		end
	end
	task.delay(Theme.COMBAT_RANGE_ARROW_TRAIL_SECONDS, function()
		part:Destroy()
	end)
end

local function spawnFlight(
	key: string,
	part: BasePart,
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	offset: Vector3,
	lifetime: number,
	seq: number,
	glow: boolean,
	variant: Types.RangeWeaponVariant?
): ()
	local speed = velocity.Magnitude
	local splitCount = if variant ~= nil then math.floor(variant.splitCount or 0) else 0
	local splitDistance = if variant ~= nil then variant.splitDistance else nil
	local flight: Flight = {
		key = key,
		part = part,
		origin = origin,
		velocity = velocity,
		gravity = gravity,
		offset = offset,
		started = os.clock(),
		lifetime = lifetime,
		last = origin,
		splitAt = if splitCount > 1
				and splitDistance ~= nil
				and speed > 0
			then splitDistance / speed + Theme.COMBAT_RANGE_SPLIT_GRACE_SECONDS
			else nil,
		splitCount = splitCount,
		splitArc = if variant ~= nil then variant.splitArcDegrees or 0 else 0,
		seq = seq,
		glow = glow,
	}
	part.CFrame = CFrame.lookAt(origin + offset, origin + offset + velocity)
	table.insert(flights, flight)
end

-- What a volley's children inherit from their parent arrow. `offset` is the part of the
-- parent's hand-to-aim gap not yet blended out: a split right at the bow (Volley splits after
-- one stud) must fan out of the hand, not out of the camera.
type Fan = {
	key: string,
	speed: number,
	gravity: number,
	count: number,
	arc: number,
	seq: number,
	glow: boolean,
	offset: Vector3,
}

-- The share of a flight's hand offset still shown t seconds after launch.
local function blendLeft(t: number): number
	return math.max(1 - t / Theme.COMBAT_RANGE_FLIGHT_BLEND_SECONDS, 0)
end

-- The children of a split at `position`, fanned by the server's own pattern (HitShapes.Fan
-- around `heading`, seeded by seq, jittered by shooting.fanJitterShare); each keeps the
-- parent's speed, drop and remaining time.
local function fanOut(fan: Fan, position: Vector3, heading: Vector3, remaining: number): ()
	local jitter = config().shooting.fanJitterShare
	for _, direction in HitShapes.Fan(heading, fan.count, fan.arc, fan.seq, jitter) do
		spawnFlight(
			fan.key,
			buildProjectile(false, fan.glow),
			position,
			direction * fan.speed,
			fan.gravity,
			fan.offset,
			remaining,
			fan.seq,
			fan.glow,
			nil
		)
	end
end

local function fanOf(flight: Flight, t: number): Fan
	return {
		key = flight.key,
		speed = flight.velocity.Magnitude,
		gravity = flight.gravity,
		count = flight.splitCount,
		arc = flight.splitArc,
		seq = flight.seq,
		glow = flight.glow,
		offset = flight.offset * blendLeft(t),
	}
end

-- The fallback split: where the parent is now (the server's split shot did not come in time).
local function splitFlight(index: number, t: number): ()
	local flight = flights[index]
	local position, heading = ballistic(flight, t)
	endFlight(index, nil)
	fanOut(fanOf(flight, t), position, heading, flight.lifetime - t)
end

-- Every parent of a shot that is still waiting to split, split where it is now.
local function splitPending(key: string, now: number): ()
	for index = #flights, 1, -1 do
		local flight = flights[index]
		if flight.key == key and flight.splitAt ~= nil then
			splitFlight(index, now - flight.started)
		end
	end
end

local function stepFlights(now: number): ()
	if #flights == 0 then
		return
	end
	local params = flightParams()
	for index = #flights, 1, -1 do
		local flight = flights[index]
		local t = now - flight.started
		if t >= flight.lifetime then
			endFlight(index, nil)
			continue
		end
		local position, velocity = ballistic(flight, t)
		local hit = Workspace:Raycast(flight.last, position - flight.last, params)
		if hit ~= nil then
			endFlight(index, hit.Position)
			continue
		end
		local splitAt = flight.splitAt
		if splitAt ~= nil and t >= splitAt then
			splitFlight(index, t)
			continue
		end
		local shown = position + flight.offset * blendLeft(t)
		if velocity.Magnitude > EPSILON then
			flight.part.CFrame = CFrame.lookAt(shown, shown + velocity)
		else
			flight.part.Position = shown
		end
		flight.last = position
	end
end

local function onShot(fx: { [string]: any }): ()
	if
		typeof(fx.userId) ~= "number"
		or typeof(fx.weapon) ~= "string"
		or typeof(fx.origin) ~= "Vector3"
		or typeof(fx.direction) ~= "Vector3"
		or typeof(fx.speed) ~= "number"
		or typeof(fx.seq) ~= "number"
		or fx.speed <= 0
	then
		return
	end
	local direction = unitOf(fx.direction)
	if direction == nil or fxFolder == nil then
		return
	end
	-- An ability's projectile (Volley, Cluster Shell) splits and flies by the ability's numbers.
	local variant = if typeof(fx.ability) == "string"
		then abilityShotVariant(fx.weapon, fx.ability)
		else variantOf(fx.weapon, if typeof(fx.variant) == "string" then fx.variant else nil)
	local gravity = if typeof(fx.gravity) == "number" then math.max(fx.gravity, 0) else 0
	local charge = if typeof(fx.charge) == "number" then fx.charge else 0
	local shell = variant ~= nil and variant.shape == "sphere"
	local glow = variant ~= nil and variant.chargeSeconds ~= nil and charge >= FULL_CHARGE
	local key = tostring(fx.userId) .. ":" .. tostring(fx.seq)
	local maxSeconds = maxFlightSeconds()
	local range = if variant ~= nil then variant.range else fx.speed * maxSeconds
	local lifetime =
		math.min(range / fx.speed + Theme.COMBAT_RANGE_FLIGHT_SLACK_SECONDS, maxSeconds)
	if fx.split == true then
		-- The server split this shot here: whatever this client drew for it (the parent, or
		-- children its fallback timer made) gives way to a fan from the true point.
		local now = os.clock()
		local carried = Vector3.zero
		for index = #flights, 1, -1 do
			local flight = flights[index]
			if flight.key == key then
				local age = now - flight.started
				lifetime = math.min(lifetime, flight.lifetime - age)
				if flight.splitAt ~= nil then
					carried = flight.offset * blendLeft(age)
				end
				endFlight(index, nil)
			end
		end
		fanOut({
			key = key,
			speed = fx.speed,
			gravity = gravity,
			count = if variant ~= nil then math.floor(variant.splitCount or 0) else 0,
			arc = if variant ~= nil then variant.splitArcDegrees or 0 else 0,
			seq = fx.seq,
			glow = glow,
			offset = carried,
		}, fx.origin, direction, math.max(lifetime, 0))
		return
	end
	local muzzle = muzzleOf(fx.userId)
	local offset = if muzzle ~= nil then muzzle - fx.origin else Vector3.zero
	spawnFlight(
		key,
		buildProjectile(shell, glow),
		fx.origin,
		direction * fx.speed,
		gravity,
		offset,
		lifetime,
		fx.seq,
		glow,
		variant
	)
end

-- A strike with an end point ends the flight it resolved: the one of its shot nearest that
-- point (a split volley has one per child). A strike without one is an arrow still piercing
-- its way through (RangeService), so the flight carries on.
local function landFlight(strike: Strike): ()
	local seq = strike.seq
	local finish = strike.endPoint
	if seq == nil or finish == nil or #flights == 0 then
		return
	end
	local key = tostring(strike.userId) .. ":" .. tostring(seq)
	local now = os.clock()
	-- A parent still waiting for its split is never ended whole: its children are what the
	-- server is resolving, so it splits first and the nearest child takes the strike.
	splitPending(key, now)
	local best: number? = nil
	local bestDistance = math.huge
	for index, flight in flights do
		if flight.key == key then
			local position = ballistic(flight, now - flight.started)
			local distance = (position - finish).Magnitude
			if distance < bestDistance then
				best = index
				bestDistance = distance
			end
		end
	end
	if best ~= nil then
		endFlight(best, finish)
	end
end

-- Held beams ---------------------------------------------------------------------------

local function beamLayer(
	name: string,
	start: Attachment,
	finish: Attachment,
	color: Color3,
	transparency: number
): Beam
	return Create("Beam", {
		Name = name,
		Attachment0 = start,
		Attachment1 = finish,
		FaceCamera = true,
		LightEmission = 1,
		LightInfluence = 0,
		Segments = 1,
		Color = ColorSequence.new(color),
		Transparency = NumberSequence.new(transparency),
		Width0 = 0,
		Width1 = 0,
		Parent = start,
	}) :: Beam
end

local function destroyBeam(userId: number): ()
	local beam = beams[userId]
	if beam == nil then
		return
	end
	beams[userId] = nil
	release(beam.tip)
	local muzzle = beam.muzzle
	if muzzle ~= nil then
		release(muzzle)
	end
	beam.start:Destroy()
	beam.finish:Destroy()
end

-- A Beam-family strike keeps its shooter's one beam alive and moves its end: the beam runs from
-- the hand to where the server stopped the ray, as wide as the ray really is. It is the
-- weapon's own visual, not a hitbox overlay, so feedback.hitboxEffect never hides it (review
-- round); only its wireframe follows the panel toggle like every strike's.
local function feedBeam(strike: Strike, variant: Types.RangeWeaponVariant): ()
	if fxFolder == nil then
		return
	end
	local direction = unitOf(strike.direction)
	if direction == nil then
		return
	end
	local finish = rayEnd(strike)
	local length = (finish - strike.origin).Magnitude
	local beam = beams[strike.userId]
	if beam == nil then
		local start =
			Create("Attachment", { Name = "RangeBeamStart", Parent = Workspace.Terrain }) :: Attachment
		local stop =
			Create("Attachment", { Name = "RangeBeamEnd", Parent = Workspace.Terrain }) :: Attachment
		local created: BeamFx = {
			start = start,
			finish = stop,
			core = beamLayer(
				"Core",
				start,
				stop,
				Theme.COMBAT_RANGE_BEAM_CORE_COLOR,
				Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY
			),
			-- Low-end devices draw the core alone.
			glow = if Theme.lowEndDevice
				then nil
				else beamLayer(
					"Glow",
					start,
					stop,
					Theme.COMBAT_RANGE_BEAM_COLOR,
					Theme.COMBAT_RANGE_BEAM_GLOW_TRANSPARENCY
				),
			tip = shapedPart(
				Enum.PartType.Ball,
				Theme.COMBAT_RANGE_BEAM_COLOR,
				Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY
			),
			muzzle = if Theme.lowEndDevice
				then nil
				else shapedPart(
					Enum.PartType.Ball,
					Theme.COMBAT_RANGE_BEAM_CORE_COLOR,
					Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY
				),
			width = 0,
			lastAt = 0,
			linger = 0,
			range = 0,
			origin = strike.origin,
			length = length,
			wallStop = true,
			target = finish,
			shown = nil,
			-- Two players' beams never flicker in step.
			phase = math.random(),
			wiredAt = 0,
		}
		beams[strike.userId] = created
		beam = created
	end
	local live = beam :: BeamFx
	live.width = math.max(strike.width or variant.width or 0, Theme.COMBAT_RANGE_BEAM_MIN_WIDTH)
	live.lastAt = os.clock()
	-- Never under the floor: at rate 10, 2 / rate alone blinks the beam off on network jitter.
	live.linger = math.max(
		Theme.COMBAT_RANGE_BEAM_LINGER_INTERVALS / math.max(variant.rate, EPSILON),
		Theme.COMBAT_RANGE_BEAM_MIN_LINGER_SECONDS
	)
	live.range = math.max(variant.range, length)
	live.origin = strike.origin
	live.length = length
	live.target = finish
	if strike.userId == localUserId() then
		-- The local beam follows the live crosshair, so it must know what stopped this ray:
		-- open air or a wall (it may reach past as the aim sweeps) or a spent pierce (it
		-- stays this short until the next strike says otherwise).
		local tolerance = Theme.COMBAT_RANGE_BEAM_STOP_TOLERANCE
		if length >= variant.range - tolerance then
			live.wallStop = true
		else
			local wall = Workspace:Raycast(strike.origin, direction * variant.range, flightParams())
			live.wallStop = wall ~= nil and wall.Distance <= length + tolerance
		end
	end
end

local function stepBeams(now: number, deltaTime: number): ()
	if next(beams) == nil then
		return
	end
	local me = localUserId()
	for userId, beam in beams do
		if now - beam.lastAt > beam.linger then
			destroyBeam(userId)
			continue
		end
		local from = muzzleOf(userId) or beam.origin
		local goal = beam.target
		if userId == me then
			-- Display prediction: the next strike leaves along the live camera ray, so the
			-- local beam points there now at the length the server last allowed.
			local aimOrigin, look = CameraController.GetAimRay()
			local wall = Workspace:Raycast(aimOrigin, look * beam.range, flightParams())
			local reach = if wall ~= nil then wall.Distance else beam.range
			goal = aimOrigin
				+ look * (if beam.wallStop then reach else math.min(beam.length, reach))
		end
		local previous = beam.shown
		local shown = if previous == nil
				or userId == me
				or Theme.reducedMotion
			then goal
			else previous:Lerp(
				goal,
				1 - math.exp(-Theme.COMBAT_RANGE_BEAM_FOLLOW_RATE * deltaTime)
			)
		beam.shown = shown
		beam.start.WorldPosition = from
		beam.finish.WorldPosition = shown
		local wobble = if Theme.reducedMotion
			then 1
			else 1 + Theme.COMBAT_RANGE_BEAM_FLICKER * math.sin(
				(now + beam.phase) * 2 * math.pi * Theme.COMBAT_RANGE_BEAM_FLICKER_HZ
			)
		local width = beam.width * wobble
		local core = width * Theme.COMBAT_RANGE_BEAM_CORE_SHARE
		beam.core.Width0 = core
		beam.core.Width1 = core
		local glow = beam.glow
		if glow ~= nil then
			glow.Width0 = width
			glow.Width1 = width
		end
		beam.tip.Size = Vector3.one * (Theme.COMBAT_RANGE_BEAM_TIP_SIZE * wobble)
		beam.tip.Position = shown
		local muzzle = beam.muzzle
		if muzzle ~= nil then
			muzzle.Size = Vector3.one * (Theme.COMBAT_RANGE_BEAM_MUZZLE_SIZE * wobble)
			muzzle.Position = from
		end
	end
end

-- Strike intake ------------------------------------------------------------------------

local function parseHits(raw: any): { Types.StrikeHit }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local hits: { Types.StrikeHit } = {}
	for _, hit in raw :: { any } do
		if
			typeof(hit) == "table"
			and typeof(hit.id) == "number"
			and typeof(hit.amount) == "number"
		then
			table.insert(hits, {
				id = hit.id,
				amount = hit.amount,
				crit = hit.crit == true,
				killed = hit.killed == true,
			})
		end
	end
	return hits
end

-- Chain links are flat id pairs; anything that is not a whole number pair is dropped.
local function parseLinks(raw: any): { number }?
	if typeof(raw) ~= "table" then
		return nil
	end
	local links: { number } = {}
	local list = raw :: { any }
	for index = 1, #list - 1, 2 do
		local fromId = list[index]
		local toId = list[index + 1]
		if typeof(fromId) == "number" and typeof(toId) == "number" then
			table.insert(links, fromId)
			table.insert(links, toId)
		end
	end
	return if #links > 0 then links else nil
end

-- Only a strike with every field the drawing needs is trusted; it arrives from the network.
local function parseStrike(fx: { [string]: any }): Strike?
	local hits = parseHits(fx.hits)
	if
		hits == nil
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
		weapon = if typeof(fx.weapon) == "string" then fx.weapon else "",
		variant = if typeof(fx.variant) == "string" then fx.variant else "",
		shape = fx.shape,
		origin = fx.origin,
		direction = fx.direction,
		size = fx.size,
		arcDegrees = if typeof(fx.arcDegrees) == "number" then fx.arcDegrees else nil,
		width = if typeof(fx.width) == "number" then fx.width else nil,
		endPoint = if typeof(fx.endPoint) == "Vector3" then fx.endPoint else nil,
		seq = if typeof(fx.seq) == "number" then fx.seq else nil,
		hits = hits :: { Types.StrikeHit },
		ability = if typeof(fx.ability) == "string" and fx.ability ~= "" then fx.ability else nil,
		tick = fx.tick == true,
		links = parseLinks(fx.links),
	}
end

-- How long after one lasting hit the next still joins its burst: the ability's tick interval
-- (an Overload Sweep's slice interval), or a held beam's fire interval, plus the merge grace.
local function mergeGap(strike: Strike, variant: Types.RangeWeaponVariant?): number
	local interval = 0
	local id = strike.ability
	if id ~= nil then
		local ability = abilityDefOf(strike.weapon, id)
		if ability ~= nil then
			local tickSeconds = ability.tickSeconds
			local duration = ability.durationSeconds
			local count = ability.count
			if tickSeconds ~= nil then
				interval = tickSeconds
			elseif duration ~= nil and count ~= nil and count > 0 then
				interval = duration / count
			end
		end
	elseif variant ~= nil and variant.rate > 0 then
		interval = 1 / variant.rate
	end
	return math.max(interval, 0) + Theme.COMBAT_RANGE_TICK_MERGE_SECONDS
end

local function onStrike(strike: Strike): ()
	local variant = variantOf(strike.weapon, strike.variant)
	local ability = strike.ability
	-- Only a weapon shot is its family's held beam; a Beam-family ability (Overload Sweep) is
	-- not. Held-beam strikes also arrive as ticks: the beam path owns them.
	local beamWeapon = ability == nil and variant ~= nil and variant.continuous == true
	local lasting = strike.tick or beamWeapon
	local flight = if ability ~= nil then abilityFlies(strike) else isProjectile(variant)
	if flight then
		landFlight(strike)
		-- An empty end strike (a set/reset/stress clearing the air, or a split child whose
		-- siblings filled the cap) only stops its flight: no flash, no sparks.
		if #strike.hits == 0 and strike.size <= 0 then
			return
		end
	end
	local chain = ability == nil
		and strike.shape == "ray"
		and variant ~= nil
		and (variant.chainCount or 0) > 0
	local impactValues = impactOf(strike, variant)
	local total = 0
	local kills = 0
	local crit = false
	for _, hit in strike.hits do
		total += hit.amount
		if hit.killed then
			kills += 1
		end
		crit = crit or hit.crit
	end
	local hitCount = #strike.hits
	local now = os.clock()

	-- Every drawing reads the bodies before react() starts any death flight.
	local hitboxStrength = feedbackStrength("hitboxEffect")
	local wire = wireframe
	if beamWeapon then
		feedBeam(strike, variant :: Types.RangeWeaponVariant)
		-- One wireframe per marker interval: ten a second would bury the beam.
		local beam = beams[strike.userId]
		if beam ~= nil then
			wire = wire and now - beam.wiredAt >= Theme.COMBAT_RANGE_BEAM_MARKER_SECONDS
			if wire then
				beam.wiredAt = now
			end
		end
	elseif not strike.tick then
		drawHitbox(strike, variant, impactValues, hitboxStrength, crit, flight, chain)
	end
	if ability ~= nil then
		drawAbilityLinks(strike, hitboxStrength)
	end
	if wire then
		drawWireframe(strike, impactValues)
	end
	if hitCount > 0 then
		react(strike, impactValues)
	end
	if strike.userId ~= localUserId() or hitCount == 0 then
		return
	end

	-- A held beam marks and pulses at most once per BEAM_MARKER_SECONDS; a kill always does.
	local quiet = beamWeapon
		and kills == 0
		and now - beamMarkedAt < Theme.COMBAT_RANGE_BEAM_MARKER_SECONDS
	if beamWeapon and not quiet then
		beamMarkedAt = now
	end
	local marker = crosshair
	if marker ~= nil and not quiet then
		marker.Mark(crit, kills > 0, feedbackStrength("hitMarker"))
	end

	local shownKills = kills
	if lasting then
		local key = tostring(strike.userId) .. ":" .. (ability or ("beam:" .. strike.weapon))
		shownKills = mergeNumbers(
			key,
			strike,
			total,
			crit,
			kills,
			mergeGap(strike, variant),
			feedbackStrength("numbers")
		)
	else
		showNumbers(strike, total, crit, feedbackStrength("numbers"))
		local hitstopSeconds = math.min(
			Theme.COMBAT_RANGE_HITSTOP_BASE + Theme.COMBAT_RANGE_HITSTOP_PER_HIT * (hitCount - 1),
			Theme.COMBAT_RANGE_HITSTOP_MAX,
			(now - lastLocalHitAt) * Theme.COMBAT_RANGE_HITSTOP_INTERVAL_SHARE
		)
		hitstop(hitstopSeconds * feedbackStrength("hitstop"))
	end
	lastLocalHitAt = now

	-- Lasting hits never count as heavy: their shake and pulse are a soft running rumble.
	local heavy = not lasting
		and (
			impactValues.knockback >= Theme.COMBAT_RANGE_HEAVY_KNOCKBACK
			or kills >= Theme.COMBAT_RANGE_EDGE_FLASH_KILLS
		)
	local shake = if heavy
		then Theme.COMBAT_RANGE_SHAKE_HEAVY
		else math.min(
			Theme.COMBAT_RANGE_SHAKE_LIGHT + Theme.COMBAT_RANGE_SHAKE_PER_KILL * kills,
			Theme.COMBAT_RANGE_SHAKE_HEAVY
		)
	local soften = if lasting then Theme.COMBAT_RANGE_TICK_SHAKE_SCALE else 1
	CameraController.Shake(shake * soften * feedbackStrength("shake"))
	if kills >= Theme.COMBAT_RANGE_EDGE_FLASH_KILLS then
		edgeFlash(feedbackStrength("edgeFlash"))
	end
	if not quiet then
		local haptics = feedbackStrength("haptics")
			* (if lasting then Theme.COMBAT_RANGE_TICK_HAPTIC_SCALE else 1)
		if heavy then
			pulse(
				Theme.COMBAT_RANGE_HAPTIC_HEAVY * haptics,
				Theme.COMBAT_RANGE_HAPTIC_HEAVY_SECONDS
			)
		else
			pulse(Theme.COMBAT_RANGE_HAPTIC_LIGHT * haptics, Theme.COMBAT_RANGE_HAPTIC_SECONDS)
		end
	end
	-- A lasting hit's kill line shows the running total of its burst.
	updateCounters(hitCount, if kills > 0 then shownKills else 0, feedbackStrength("counters"))
end

local function applyFx(fx: any): ()
	if typeof(fx) ~= "table" then
		return
	end
	if fx.kind == "shot" then
		onShot(fx :: { [string]: any })
	elseif fx.kind == "strike" then
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

-- TuneState is (overrides, loadout); only a loadout with both slots and a variants map is kept.
local function parseLoadout(raw: any): Types.RangeLoadout?
	if
		typeof(raw) ~= "table"
		or typeof(raw.melee) ~= "string"
		or typeof(raw.ranged) ~= "string"
	then
		return nil
	end
	local variants: { [string]: string } = {}
	if typeof(raw.variants) == "table" then
		for family, key in raw.variants do
			if typeof(family) == "string" and typeof(key) == "string" then
				variants[family] = key
			end
		end
	end
	return { melee = raw.melee, ranged = raw.ranged, variants = variants }
end

local function onTuneStateEvent(overrides: any, rawLoadout: any): ()
	if typeof(overrides) == "table" then
		-- The server owns the overrides; every client applies the same merge (Tuning
		-- validates each entry and drops anything malformed).
		Tuning.SetOverrides(overrides)
	end
	local loadout = parseLoadout(rawLoadout)
	if loadout ~= nil then
		currentLoadout = loadout
		-- This is the only TuneState listener on the client (one event, one ordering): input
		-- learns the confirmed loadout from here, after the overrides it reads are in place.
		InputController.SetLoadout(loadout)
	end
	local handler = onTuneState
	if handler ~= nil then
		handler()
	end
end

-- Per frame ----------------------------------------------------------------------------

local function stepEffects(now: number): ()
	for index = #effects, 1, -1 do
		local effect = effects[index]
		local u = (now - effect.started) / effect.seconds
		if u >= 1 then
			for _, item in effect.parts do
				release(item.part)
			end
			table.remove(effects, index)
		else
			local hold = Theme.COMBAT_RANGE_HITBOX_HOLD_FRACTION
			local grow = math.min(u / hold, 1)
			local fade = if u <= hold then 0 else (u - hold) / (1 - hold)
			for _, item in effect.parts do
				item.part.Transparency = item.base + (1 - item.base) * fade
				local from = item.fromSize
				local to = item.toSize
				if from ~= nil and to ~= nil then
					item.part.Size = from:Lerp(to, grow)
				end
				local fromFrame = item.fromCFrame
				local toFrame = item.toCFrame
				if fromFrame ~= nil and toFrame ~= nil then
					item.part.CFrame = fromFrame:Lerp(toFrame, grow)
				end
			end
		end
	end
end

local function updateCrosshair(): ()
	local marker = crosshair
	if marker == nil then
		return
	end
	-- The weapon in the active slot: the confirmed loadout, else the config's starting one.
	local slot = InputController.GetActiveSlot()
	local loadout = currentLoadout
	local startLoadout = config().loadout
	local family = if loadout ~= nil
		then (if slot == "melee" then loadout.melee else loadout.ranged)
		else (if slot == "melee" then startLoadout.melee else startLoadout.ranged)
	local variant = variantOf(family, if loadout ~= nil then loadout.variants[family] else nil)
	local ranged = variant ~= nil and variant.kind == "ranged"
	-- Only a bow has a draw: a held beam or a Mag Dump reuses input's hold, never the ring.
	local charges = ranged and variant ~= nil and (variant.chargeSeconds or 0) > 0
	local gapPixels: number? = nil
	local camera = Workspace.CurrentCamera
	if ranged and camera ~= nil then
		-- The bloom cone's radius on screen: tan(bloom) over tan(half the vertical FOV),
		-- times half the viewport height.
		local bloom = InputController.GetBloomDegrees()
		local halfFov = math.rad(math.max(camera.FieldOfView, 1) / 2)
		gapPixels = math.tan(math.rad(bloom)) / math.tan(halfFov) * camera.ViewportSize.Y / 2
	end
	marker.Update(
		gapPixels,
		InputController.IsAiming(),
		CameraController.IsActive(),
		if charges then InputController.GetCharge() or 0 else 0
	)
end

local function onRenderStep(deltaTime: number): ()
	local now = os.clock()
	stepEffects(now)
	stepFlights(now)
	stepBeams(now, deltaTime)
	for _, burst in bursts do
		if burst.active then
			stepBurst(burst, now, deltaTime)
		end
	end
	if next(frozenTracks) ~= nil and now >= hitstopUntil then
		releaseHitstop()
	end
	expireCombo(now)
	updateCrosshair()
end

-- Overlay ------------------------------------------------------------------------------

local function counterLabel(
	name: string,
	textSize: number,
	order: number,
	parent: Instance
): TextLabel
	local label = Create("TextLabel", {
		Name = name,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, textSize + Theme.SCREEN_MARGIN / 2),
		Font = Theme.FONT_BOLD,
		TextSize = textSize,
		TextColor3 = Theme.COLOR_TEXT,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
		Text = "",
		Parent = parent,
	}) :: TextLabel
	Create("UIStroke", {
		Color = Theme.COLOR_TEXT_DARK,
		Thickness = Theme.STROKE_THICKNESS,
		Transparency = 1,
		Parent = label,
	})
	Create("UIScale", { Parent = label })
	return label
end

local function buildOverlay(screenGui: ScreenGui): ()
	-- Inactive throughout: nothing here may swallow an aiming drag on a phone.
	local root = Create("Frame", {
		Name = "RangeFeedback",
		Active = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}) :: Frame
	overlayRoot = root

	-- Edge flash: four bars fading inward (no vignette image asset exists).
	local thickness = Theme.COMBAT_RANGE_EDGE_FLASH_THICKNESS
	type Edge = { size: UDim2, position: UDim2, anchor: Vector2, rotation: number, flip: boolean }
	local vertical = UDim2.new(0, thickness, 1, 0)
	local horizontal = UDim2.new(1, 0, 0, thickness)
	local edges: { Edge } = {
		{
			size = vertical,
			position = UDim2.fromScale(0, 0),
			anchor = Vector2.zero,
			rotation = 0,
			flip = false,
		},
		{
			size = vertical,
			position = UDim2.fromScale(1, 0),
			anchor = Vector2.xAxis,
			rotation = 0,
			flip = true,
		},
		{
			size = horizontal,
			position = UDim2.fromScale(0, 0),
			anchor = Vector2.zero,
			rotation = 90,
			flip = false,
		},
		{
			size = horizontal,
			position = UDim2.fromScale(0, 1),
			anchor = Vector2.yAxis,
			rotation = 90,
			flip = true,
		},
	}
	for _, edge in edges do
		local bar = Create("Frame", {
			Name = "EdgeFlash",
			Active = false,
			Size = edge.size,
			Position = edge.position,
			AnchorPoint = edge.anchor,
			BackgroundColor3 = Theme.COMBAT_RANGE_CRIT_COLOR,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = root,
		}) :: Frame
		Create("UIGradient", {
			Rotation = edge.rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, if edge.flip then 1 else 0),
				NumberSequenceKeypoint.new(1, if edge.flip then 0 else 1),
			}),
			Parent = bar,
		})
		table.insert(edgeBars, bar)
	end

	-- Counters sit right of the crosshair so they read without looking away from the aim.
	local counters = Create("Frame", {
		Name = "Counters",
		Active = false,
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(Theme.COMBAT_RANGE_COUNTER_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = root,
	}) :: Frame
	counterScale = Create("UIScale", { Parent = counters }) :: UIScale
	Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = counters })
	comboValue = counterLabel("Combo", Theme.COMBAT_RANGE_COMBO_TEXT, 1, counters)
	local caption = counterLabel("ComboCaption", Theme.COMBAT_RANGE_COMBO_LABEL_TEXT, 2, counters)
	caption.Text = "HITS"
	caption.TextColor3 = Theme.COLOR_TEXT_DIM
	comboCaption = caption
	local kills = counterLabel("Kills", Theme.COMBAT_RANGE_KILLS_TEXT, 3, counters)
	kills.TextColor3 = Theme.COMBAT_RANGE_KILL_COLOR
	killsLabel = kills
	counterRoot = counters
end

-- Public API ---------------------------------------------------------------------------

function FeedbackController.Init(): ()
	-- Remotes and PlayerGui are replicated instances: everything happens in Start.
end

function FeedbackController.Start(): ()
	-- Missions keep their own feedback (CombatFxController); strikes exist only in the range.
	if not CameraController.IsRange() then
		return
	end
	fxFolder =
		Create("Folder", { Name = Theme.COMBAT_RANGE_FX_FOLDER, Parent = Workspace }) :: Folder
	detectHaptics()
	table.insert(connections, RunService.RenderStepped:Connect(onRenderStep))
	-- A player who leaves mid-beam takes the beam along (no more strikes would end it on time).
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			destroyBeam(player.UserId)
		end)
	)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local combatFx =
			remotes:WaitForChild("CombatFx", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if combatFx == nil then
			warn("[FeedbackController] CombatFx missing — range feedback is disabled")
		else
			table.insert(connections, combatFx.OnClientEvent:Connect(onCombatFx))
		end
		local tuneState =
			remotes:WaitForChild("TuneState", Theme.COMBAT_REMOTE_WAIT_SECONDS) :: RemoteEvent?
		if tuneState == nil then
			warn("[FeedbackController] TuneState missing — the range runs on base values")
		else
			table.insert(connections, tuneState.OnClientEvent:Connect(onTuneStateEvent))
		end
	end)
end

-- CombatUIController mounts the range HUD (a ScreenGui that ignores the GUI inset, so its
-- centre is the camera's centre line) and hands over the crosshair it built there.
function FeedbackController.Mount(screenGui: ScreenGui, reticle: Crosshair.CrosshairHandle): ()
	crosshair = reticle
	if overlayRoot == nil then
		buildOverlay(screenGui)
	end
end

function FeedbackController.SetLayout(scale: number): ()
	layoutScale = scale
	local counters = counterRoot
	local counterUiScale = counterScale
	if counters ~= nil and counterUiScale ~= nil then
		counters.Position = UDim2.new(
			0.5,
			Theme.COMBAT_RANGE_COUNTER_OFFSET_X * scale,
			0.5,
			-Theme.COMBAT_RANGE_COUNTER_OFFSET_Y * scale
		)
		counterUiScale.Scale = scale
	end
end

function FeedbackController.SetWireframe(on: boolean): ()
	wireframe = on
end

function FeedbackController.IsWireframe(): boolean
	return wireframe
end

-- The loadout the server last confirmed on TuneState (nil until the first one arrives).
function FeedbackController.GetLoadout(): Types.RangeLoadout?
	return currentLoadout
end

-- Every projectile in flight goes (a dummy set was loaded or reset: the server dropped its
-- projectiles with the crowd).
function FeedbackController.ClearFlights(): ()
	for index = #flights, 1, -1 do
		endFlight(index, nil)
	end
end

-- Called after every TuneState, once the overrides are applied to Tuning.
function FeedbackController.SetTuneStateHandler(handler: () -> ()): ()
	onTuneState = handler
end

-- The server dropped the local player's last attack (RangeStats.refused): grey the crosshair
-- once. Nothing was drawn for it: flights start from the server's shot, strikes from its hits.
function FeedbackController.OnRefused(): ()
	local marker = crosshair
	if marker ~= nil then
		marker.Refused()
	end
end

function FeedbackController.Destroy(): ()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	releaseHitstop()
	hapticToken += 1
	setMotors(0)
	for _, effect in effects do
		for _, item in effect.parts do
			item.part:Destroy()
		end
	end
	table.clear(effects)
	for _, flight in flights do
		flight.part:Destroy()
	end
	table.clear(flights)
	for userId in beams do
		destroyBeam(userId)
	end
	table.clear(merges)
	for _, spark in sparks do
		spark.anchor:Destroy()
	end
	table.clear(sparks)
	for _, burst in bursts do
		burst.gui:Destroy()
		burst.anchor:Destroy()
	end
	table.clear(bursts)
	for className in pools do
		pools[className] = {}
	end
	pooledCount = 0
	local folder = fxFolder
	if folder ~= nil then
		folder:Destroy()
		fxFolder = nil
	end
	local root = overlayRoot
	if root ~= nil then
		root:Destroy()
		overlayRoot = nil
	end
	table.clear(edgeBars)
	counterRoot = nil
	counterScale = nil
	comboValue = nil
	comboCaption = nil
	killsLabel = nil
	crosshair = nil
end

return FeedbackController
