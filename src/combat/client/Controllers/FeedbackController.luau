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
local DEFAULT_WEAPON = "sword"
-- Pellet tracers are drawn only if the server puts the attack's `seq` on the strike (the
-- pattern is HitShapes.Pellets(seq)); until then the cone itself is the shotgun's effect.
local SEQ_FIELD = "seq"
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
}

type FxPart = { part: BasePart, base: number, fromSize: Vector3?, toSize: Vector3? }
type Effect = { parts: { FxPart }, started: number, seconds: number }

type Burst = {
	gui: BillboardGui,
	anchor: Attachment,
	scale: UIScale,
	main: TextLabel,
	count: TextLabel,
	strokes: { UIStroke },
	started: number,
	side: number,
	pop: number,
	active: boolean,
}

type HapticTarget = { input: Enum.UserInputType, motor: Enum.VibrationMotor }

-- A crowd sphere a pellet tracer may stop in (body or head).
type Body = { centre: Vector3, radius: number }

-- A local projectile in flight: the server sends the strike only at impact, so the shooter's
-- own shell is drawn from the muzzle to where the aim ray meets the world (or its reach).
type Shell = { part: BasePart, from: Vector3, to: Vector3, started: number, seconds: number }

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
local weaponName = DEFAULT_WEAPON
local variantName: string? = nil
local onTuneState: (() -> ())? = nil
local combo = 0
local comboExpires = 0
local killsToken = 0
local hitstopUntil = 0
local frozenTracks: { [AnimationTrack]: number } = {}
local hapticTargets: { HapticTarget } = {}
local hapticToken = 0
local shells: { Shell } = {}
-- True once InputController reports local attacks: the shell then shows the flight, so the
-- impact no longer needs a trail for the local player.
local drawsLocalShells = false

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

-- Pad, knockback and launch of a strike: its weapon variant's, or for the ground slam (a
-- strike with no weapon variant) the movement.slam* values the server resolved it with.
local function impactOf(variant: Types.RangeWeaponVariant?): (number, number, number)
	if variant ~= nil then
		return variant.pad, variant.knockback, variant.launch
	end
	local movement = config().movement
	return movement.slamPad, movement.slamKnockback, movement.slamLaunch
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
-- within +pad+r / -(reachDown+pad+r). An airborne swing's strike carries
-- endPoint = origin - (0, reachDown, 0); a grounded one has none. r is the thinnest crowd
-- kind's radius, the band every enemy is at least hit in.
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
	variant: Types.RangeWeaponVariant?,
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
	local pad = impactOf(variant)
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

local function capsuleEnds(strike: Strike): (Vector3, Vector3, number)
	local axis = unitOf(strike.direction) or Vector3.zAxis
	local diameter = strike.width or Theme.COMBAT_RANGE_HITBOX_DEFAULT_WIDTH
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
	local thin = Theme.COMBAT_RANGE_HITBOX_EDGE_WIDTH / 2
	segment(list, a, b, thin, thin, Vector3.yAxis, color, edge)
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

local function drawHitbox(
	strike: Strike,
	variant: Types.RangeWeaponVariant?,
	strength: number,
	crit: boolean
): ()
	if strength <= 0 then
		return
	end
	local list: { FxPart } = {}
	local color = if crit
		then Theme.COMBAT_RANGE_HITBOX_CRIT_COLOR
		else Theme.COMBAT_RANGE_HITBOX_COLOR
	-- Strength fades the effect in (below 1) and lets it linger (above 1).
	local opacity = math.min(strength, 1)
	local fill = 1 - (1 - Theme.COMBAT_RANGE_HITBOX_FILL_TRANSPARENCY) * opacity
	local edge = 1 - (1 - Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY) * opacity
	local shape = strike.shape
	if shape == "arc" then
		drawArc(list, strike, variant, color, fill, edge)
	elseif shape == "sphere" then
		local shell = 1 - (1 - Theme.COMBAT_RANGE_HITBOX_SPHERE_TRANSPARENCY) * opacity
		drawSphere(list, strike, color, shell, edge)
		local centre = sphereCentre(strike)
		local from = muzzleOf(strike.userId)
		local shellShown = drawsLocalShells and strike.userId == localUserId()
		if
			not shellShown
			and variant ~= nil
			and variant.kind == "ranged"
			and from ~= nil
			and (centre - from).Magnitude > Theme.COMBAT_RANGE_TRAIL_MIN_STUDS
		then
			tracer(list, from, centre, Theme.COMBAT_RANGE_TRACER_WIDTH)
		end
	elseif shape == "capsule" then
		drawCapsule(list, strike, color, fill, edge)
	elseif shape == "cone" then
		drawCone(list, strike, color, fill, edge)
		drawPellets(list, strike, variant)
	elseif shape == "ray" then
		drawRay(list, strike, color)
	end
	local seconds = math.clamp(
		Theme.COMBAT_RANGE_HITBOX_SECONDS * math.max(strength, 1),
		Theme.COMBAT_RANGE_HITBOX_SECONDS,
		Theme.COMBAT_RANGE_HITBOX_MAX_SECONDS
	)
	play(list, seconds)
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

local function drawWireframe(strike: Strike, variant: Types.RangeWeaponVariant?): ()
	local list: { FxPart } = {}
	local pad = impactOf(variant)
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
		side = 1,
		pop = 1,
		active = false,
	}
end

-- A free burst, or the oldest one recycled: a fast gun into a crowd must never pile up more
-- than MAX_ACTIVE billboards.
local function takeBurst(): Burst?
	local oldest: Burst? = nil
	for _, burst in bursts do
		if not burst.active then
			return burst
		end
		if oldest == nil or burst.started < oldest.started then
			oldest = burst
		end
	end
	if #bursts < Theme.COMBAT_RANGE_NUMBER_MAX_ACTIVE then
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui == nil then
			return nil
		end
		local burst = newBurst(playerGui)
		table.insert(bursts, burst)
		return burst
	end
	return oldest
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

local function showNumbers(strike: Strike, total: number, crit: boolean, strength: number): ()
	if strength <= 0 or total <= 0 then
		return
	end
	local burst = takeBurst()
	if burst == nil then
		return
	end
	local size = math.clamp(
		strength,
		Theme.COMBAT_RANGE_NUMBER_MIN_STRENGTH,
		Theme.COMBAT_RANGE_NUMBER_MAX_STRENGTH
	)
	local hitCount = #strike.hits
	local color = if crit then Theme.COMBAT_RANGE_CRIT_COLOR else Theme.COLOR_TEXT
	-- Bigger crowds make bigger numbers: a few px per doubling of the hit count.
	local text = (
		if crit then Theme.COMBAT_RANGE_NUMBER_CRIT_TEXT else Theme.COMBAT_RANGE_NUMBER_TEXT
	) + Theme.COMBAT_RANGE_NUMBER_GROWTH_PER_DOUBLING * math.log(math.max(hitCount, 1), 2)
	burst.main.TextSize = math.floor(math.min(text, Theme.COMBAT_RANGE_NUMBER_MAX_TEXT))
	burst.main.Text = Format.Cash(total)
	burst.main.TextColor3 = color
	burst.count.TextSize = Theme.COMBAT_RANGE_NUMBER_COUNT_TEXT
	burst.count.Text = if hitCount > 1 then "×" .. Format.Cash(hitCount) else ""
	burst.count.TextColor3 = color
	burst.main.TextTransparency = 0
	burst.count.TextTransparency = 0
	for _, stroke in burst.strokes do
		stroke.Transparency = 0
	end
	burst.gui.Size = UDim2.fromOffset(
		Theme.COMBAT_RANGE_NUMBER_WIDTH * layoutScale * size,
		Theme.COMBAT_RANGE_NUMBER_HEIGHT * layoutScale * size
	)
	burst.anchor.WorldPosition = burstPosition(strike)
	burst.gui.StudsOffset = Vector3.zero
	burst.side = if math.random() < 0.5 then -1 else 1
	burst.pop = if Theme.reducedMotion
		then Theme.COMBAT_RANGE_NUMBER_REDUCED_POP_SCALE
		else Theme.COMBAT_RANGE_NUMBER_POP_SCALE
	burst.scale.Scale = burst.pop
	burst.started = os.clock()
	burst.active = true
	burst.gui.Enabled = true
end

-- Pop, then an arc that peaks and falls below its start (Fortnite-style), fading at the end.
local function stepBurst(burst: Burst, now: number): ()
	local seconds = Theme.COMBAT_RANGE_NUMBER_SECONDS
	local elapsed = now - burst.started
	local u = elapsed / seconds
	if u >= 1 then
		burst.active = false
		burst.gui.Enabled = false
		return
	end
	local popLeft = math.max(0, 1 - elapsed / Theme.COMBAT_RANGE_NUMBER_POP_SECONDS)
	burst.scale.Scale = 1 + (burst.pop - 1) * popLeft
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
local function react(strike: Strike, variant: Types.RangeWeaponVariant?): ()
	local flash = feedbackStrength("enemyFlash")
	local reaction = feedbackStrength("enemyReaction")
	if flash <= 0 and reaction <= 0 then
		return
	end
	local _, knockback, launch = impactOf(variant)
	local knocks = knockback > 0
	local launches = launch > 0
	for _, hit in strike.hits do
		if flash > 0 then
			CrowdRenderer.React(hit.id, "flash", nil, flash)
		end
		if reaction > 0 then
			local away = awayFrom(strike, hit.id)
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

-- Shells -----------------------------------------------------------------------------

local function stepShells(now: number): ()
	for index = #shells, 1, -1 do
		local shell = shells[index]
		local u = (now - shell.started) / shell.seconds
		if u >= 1 then
			release(shell.part)
			table.remove(shells, index)
		else
			shell.part.CFrame = CFrame.new(shell.from:Lerp(shell.to, u))
		end
	end
end

-- The impact strike is the truth: it retires the oldest shell still in the air.
local function landShell(): ()
	local shell = table.remove(shells, 1)
	if shell ~= nil then
		release(shell.part)
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
	local seq = fx[SEQ_FIELD]
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
		seq = if typeof(seq) == "number" then seq else nil,
		hits = hits :: { Types.StrikeHit },
	}
end

local function onStrike(strike: Strike): ()
	local variant = variantOf(strike.weapon, strike.variant)
	if strike.userId == localUserId() and variant ~= nil and (variant.projectileSpeed or 0) > 0 then
		landShell()
	end
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

	drawHitbox(strike, variant, feedbackStrength("hitboxEffect"), crit)
	if wireframe then
		drawWireframe(strike, variant)
	end
	if hitCount > 0 then
		react(strike, variant)
	end
	if strike.userId ~= localUserId() or hitCount == 0 then
		return
	end

	local marker = crosshair
	if marker ~= nil then
		marker.Mark(crit, kills > 0, feedbackStrength("hitMarker"))
	end
	showNumbers(strike, total, crit, feedbackStrength("numbers"))

	local hitstopSeconds = math.min(
		Theme.COMBAT_RANGE_HITSTOP_BASE + Theme.COMBAT_RANGE_HITSTOP_PER_HIT * (hitCount - 1),
		Theme.COMBAT_RANGE_HITSTOP_MAX
	)
	hitstop(hitstopSeconds * feedbackStrength("hitstop"))

	local _, knockback = impactOf(variant)
	local heavy = knockback >= Theme.COMBAT_RANGE_HEAVY_KNOCKBACK
		or kills >= Theme.COMBAT_RANGE_EDGE_FLASH_KILLS
	local shake = if heavy
		then Theme.COMBAT_RANGE_SHAKE_HEAVY
		else Theme.COMBAT_RANGE_SHAKE_LIGHT + Theme.COMBAT_RANGE_SHAKE_PER_KILL * kills
	CameraController.Shake(
		math.min(shake, Theme.COMBAT_RANGE_SHAKE_HEAVY) * feedbackStrength("shake")
	)
	if kills >= Theme.COMBAT_RANGE_EDGE_FLASH_KILLS then
		edgeFlash(feedbackStrength("edgeFlash"))
	end
	local haptics = feedbackStrength("haptics")
	if heavy then
		pulse(Theme.COMBAT_RANGE_HAPTIC_HEAVY * haptics, Theme.COMBAT_RANGE_HAPTIC_HEAVY_SECONDS)
	else
		pulse(Theme.COMBAT_RANGE_HAPTIC_LIGHT * haptics, Theme.COMBAT_RANGE_HAPTIC_SECONDS)
	end
	updateCounters(hitCount, kills, feedbackStrength("counters"))
end

local function applyFx(fx: any): ()
	if typeof(fx) ~= "table" or fx.kind ~= "strike" then
		return
	end
	local strike = parseStrike(fx :: { [string]: any })
	if strike ~= nil then
		onStrike(strike)
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

local function onTuneStateEvent(overrides: any, weapon: any, variant: any): ()
	if typeof(overrides) == "table" then
		-- The server owns the overrides; every client applies the same merge (Tuning
		-- validates each entry and drops anything malformed).
		Tuning.SetOverrides(overrides)
	end
	if typeof(weapon) == "string" then
		weaponName = weapon
	end
	if typeof(variant) == "string" then
		variantName = variant
	end
	-- This is the only TuneState listener on the client (one event, one ordering): input
	-- learns the confirmed loadout from here, after the overrides it reads are in place.
	InputController.SetLoadout(weaponName, variantName or "")
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
			end
		end
	end
end

local function updateCrosshair(): ()
	local marker = crosshair
	if marker == nil then
		return
	end
	local variant = variantOf(weaponName, variantName)
	local ranged = variant ~= nil and variant.kind == "ranged"
	local gapPixels: number? = nil
	local camera = Workspace.CurrentCamera
	if ranged and camera ~= nil then
		-- The bloom cone's radius on screen: tan(bloom) over tan(half the vertical FOV),
		-- times half the viewport height.
		local bloom = InputController.GetBloomDegrees()
		local halfFov = math.rad(math.max(camera.FieldOfView, 1) / 2)
		gapPixels = math.tan(math.rad(bloom)) / math.tan(halfFov) * camera.ViewportSize.Y / 2
	end
	marker.Update(gapPixels, InputController.IsAiming(), CameraController.IsActive())
end

local function onRenderStep(): ()
	local now = os.clock()
	stepEffects(now)
	stepShells(now)
	for _, burst in bursts do
		if burst.active then
			stepBurst(burst, now)
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

-- The weapon and variant the server last announced on TuneState (variant nil = the
-- weapon's config default until the first TuneState arrives).
function FeedbackController.GetLoadout(): (string, string?)
	return weaponName, variantName
end

-- Called after every TuneState, once the overrides are applied to Tuning.
function FeedbackController.SetTuneStateHandler(handler: () -> ()): ()
	onTuneState = handler
end

-- The server dropped the local player's last attack (RangeStats.refused): take back the
-- shell drawn for it (the newest) and grey the crosshair once. Strikes are drawn only when
-- the server resolves them, so a refused attack left nothing else on screen.
function FeedbackController.OnRefused(): ()
	local shell = table.remove(shells)
	if shell ~= nil then
		release(shell.part)
	end
	local marker = crosshair
	if marker ~= nil then
		marker.Refused()
	end
end

-- Called by InputController (through CombatUIController) right after the local player's
-- RequestRangeAttack, with the same origin and direction it sent. Draws the shell of a
-- projectile weapon; hitscan weapons and melee draw nothing here.
function FeedbackController.OnLocalAttack(
	weapon: string,
	variant: string,
	origin: Vector3,
	direction: Vector3
): ()
	drawsLocalShells = true
	local def = variantOf(weapon, variant)
	local speed = if def ~= nil then def.projectileSpeed or 0 else 0
	local unit = unitOf(direction)
	if def == nil or def.kind ~= "ranged" or speed <= 0 or unit == nil then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	local character = Players.LocalPlayer.Character
	if character ~= nil then
		table.insert(ignore, character)
	end
	local folder = fxFolder
	if folder ~= nil then
		table.insert(ignore, folder)
	end
	params.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(origin, unit * def.range, params)
	local target = if result ~= nil then result.Position else origin + unit * def.range
	local from = muzzleOf(localUserId()) or origin
	local seconds =
		math.min((target - from).Magnitude / speed, Theme.COMBAT_RANGE_SHELL_MAX_SECONDS)
	if seconds <= 0 then
		return
	end
	local part = shapedPart(
		Enum.PartType.Ball,
		Theme.COMBAT_RANGE_TRACER_COLOR,
		Theme.COMBAT_RANGE_HITBOX_EDGE_TRANSPARENCY
	)
	part.Size = Vector3.one * Theme.COMBAT_RANGE_SHELL_SIZE
	part.CFrame = CFrame.new(from)
	table.insert(
		shells,
		{ part = part, from = from, to = target, started = os.clock(), seconds = seconds }
	)
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
	for _, shell in shells do
		shell.part:Destroy()
	end
	table.clear(shells)
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
