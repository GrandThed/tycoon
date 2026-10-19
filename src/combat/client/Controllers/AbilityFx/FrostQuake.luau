--!strict
-- AbilityFx child: the `frostQuake` visual (docs/prompts/l2-w3-contract.md, L2-50). The server
-- fires it on the Earthquake launcher (`count` rings round the caster's floor, ring k landing at
-- delaySeconds + (k-1) x tickSeconds with radius radius + (k-1) x spacing), so it keeps
-- Earthquake's rhythm in the ice palette: a slam of frost at the floor centre, a frost front that
-- steps out ring by ring, the exact ring flashing as it lands, and ice shards that spring up
-- round each ring and sink away. Feedback draws each ring's sphere strike on top. Abilities never
-- freeze water (WorldReact.StrikeElement): this is a look only. Returns its builder; the parent
-- module explains the timing rule and the low-end gate.
--
-- Fix round (Q4, c-s1): it draws the configured `count` of rings, whatever their radius (one at
-- 32 studs as tuned), so its shards are spaced along each ring (LOOK.shardGap studs apart, capped
-- for all rings together) rather than counted per ring, and a shard stands only where a floor
-- lies under it: one downward ray per shard at build (on Forest Road's 16-wide road most of a
-- 32-stud ring is over the void or the creek's open water, which no ray meets). The rings and the
-- front still draw whole, because they are the strike's area.

local Workspace = game:GetService("Workspace")

local uiFolder = script.Parent.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

type Shard = { part: BasePart, ring: number, base: Vector3, outward: Vector3, height: number }

local lowEnd = Shared.lowEnd
local TAU = Shared.TAU
local UP = Shared.UP
local FLAT_U = Shared.FLAT_U
local FLAT_V = Shared.FLAT_V
local FRESH_SECONDS = Shared.FRESH_SECONDS
local RING_HEIGHT = Shared.RING_HEIGHT
local DUST_STYLE = Shared.DUST_STYLE
local DUST_WALL_WIDTH = Shared.DUST_WALL_WIDTH
local DUST_WALL_HEIGHT = Shared.DUST_WALL_HEIGHT
local DUST_WALL_SETTLE = Shared.DUST_WALL_SETTLE
local DUST_WALL_TRANSPARENCY = Shared.DUST_WALL_TRANSPARENCY
local DUST_WALL_MIN_RADIUS = Shared.DUST_WALL_MIN_RADIUS
local MIN_SIZE = Shared.MIN_SIZE
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local easeOut = Shared.easeOut
local around = Shared.around
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local particles = Shared.particles
local bigSegments = Shared.bigSegments
local LIFT = Shared.LIFT
local FLOOR_PROBE_UP = Shared.FLOOR_PROBE_UP
local groundOf = Pool.groundOf
local worldParams = Pool.worldParams
local takePart = Pool.takePart
local takeParts = Pool.takeParts
local takeEmitter = Pool.takeEmitter
local place = Pool.place
local show = Pool.show
local showAll = Pool.showAll
local layCircle = Pool.layCircle
local layBall = Pool.layBall
local layDisc = Pool.layDisc
local dustRing = Pool.dustRing

-- Look: Earthquake's timing constants, with shards where it has cracks.
local LOOK = {
	maxRings = 8,
	expandSeconds = 0.12,
	frontFade = 0.3,
	markWidth = 0.4,
	markTransparency = 0.05,
	markSeconds = 0.5,
	-- Studs of ring between two shards (Earthquake's ten cracks round its 9-stud ring); a
	-- low-end device draws half as many.
	shardGap = 5.6,
	shardGapLowEnd = 11.2,
	shardsMin = 4, -- per ring
	shardsMax = 40, -- all rings together
	shardsMaxLowEnd = 20,
	shardSpread = 0.4, -- a share of the gap a shard may stray along the ring
	shardFloorDrop = 3, -- studs a shard's foot may sit under the ring (a step down); deeper = none
	shardWidth = 0.5,
	shardHeight = 2.2,
	shardJitter = 0.35, -- a share of the height
	shardTilt = 0.35, -- radians outward
	shardRise = 0.1,
	shardHold = 0.7,
	shardSink = 0.35,
	shardTransparency = 0.15,
	padSize = 4,
	padTransparency = 0.3,
	slamSize = 3.5,
	slamTransparency = 0.1,
	slamFade = 0.2,
	mistPoints = 16,
	mistPerPoint = 2,
}

-- Where a shard planted at `point` (on the ring, at the cast's floor height) stands: the floor
-- found from FLOOR_PROBE_UP above it down to LOOK.shardFloorDrop under it, lifted; nil when
-- there is none (the void, open water, a drop).
local function footAt(point: Vector3, params: RaycastParams): Vector3?
	local hit = Workspace:Raycast(
		point + UP * FLOOR_PROBE_UP,
		Vector3.new(0, -(FLOOR_PROBE_UP + LOOK.shardFloorDrop), 0),
		params
	)
	if hit == nil then
		return nil
	end
	return Vector3.new(point.X, hit.Position.Y + LIFT, point.Z)
end

local function buildFrostQuake(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local count = positive(def.count)
	local radius = nonNegative(def.radius)
	local tick = nonNegative(def.tickSeconds)
	if delay == nil or count == nil or radius == nil or tick == nil then
		return nil, nil
	end
	local rings = math.min(math.floor(count), LOOK.maxRings)
	if rings < 1 then
		return nil, nil
	end
	local spacing = def.spacing or 0
	local centre = groundOf(cast)
	local times: { number } = {}
	local radii: { number } = {}
	for ring = 1, rings do
		times[ring] = delay + (ring - 1) * tick
		radii[ring] = math.max(radius + (ring - 1) * spacing, 0)
	end
	local last = times[rings]
	local finish = last + LOOK.shardRise + LOOK.shardHold + LOOK.shardSink
	local segments = bigSegments()
	local frostColor = Theme.COMBAT_FROST_QUAKE_FROST_COLOR
	local ringColor = Theme.COMBAT_FROST_QUAKE_RING_COLOR
	local shardColor = Theme.COMBAT_FROST_QUAKE_SHARD_COLOR

	local front = takeParts(kit, segments, Enum.PartType.Block, frostColor, Enum.Material.Ice)
	local marks: { { BasePart } } = {}
	for ring = 1, rings do
		local parts = takeParts(kit, segments, Enum.PartType.Block, ringColor, Enum.Material.Neon)
		layCircle(
			parts,
			centre,
			FLAT_U,
			FLAT_V,
			radii[ring],
			0,
			TAU,
			LOOK.markWidth,
			RING_HEIGHT,
			true
		)
		table.insert(marks, parts)
	end

	local shards: { Shard } = {}
	local rng = Random.new(cast.seq)
	local shardGap = if lowEnd then LOOK.shardGapLowEnd else LOOK.shardGap
	local budget = math.max((if lowEnd then LOOK.shardsMaxLowEnd else LOOK.shardsMax) // rings, 1)
	local params = worldParams()
	for ring = 1, rings do
		local spaced = math.max(math.round(TAU * radii[ring] / shardGap), LOOK.shardsMin)
		local perRing = math.min(spaced, budget)
		local spread = LOOK.shardSpread * TAU / perRing
		for index = 1, perRing do
			-- Both draws come before the floor test, so every client strays each shard alike.
			local angle = TAU * (index - 1) / perRing + rng:NextNumber(-spread, spread)
			local height = LOOK.shardHeight
				* (1 + rng:NextNumber(-LOOK.shardJitter, LOOK.shardJitter))
			local outward = around(angle)
			local foot = footAt(centre + outward * radii[ring], params)
			if foot == nil then
				continue
			end
			local part = takePart(kit, Enum.PartType.Block, shardColor, Enum.Material.Ice)
			table.insert(shards, {
				part = part,
				ring = ring,
				base = foot,
				outward = outward,
				height = height,
			})
		end
	end

	local pad = takePart(kit, Enum.PartType.Cylinder, frostColor, Enum.Material.Ice)
	layDisc(pad, centre, LOOK.padSize / 2)
	local slam = takePart(kit, Enum.PartType.Ball, ringColor, Enum.Material.Neon)
	local mist = takeEmitter(kit, DUST_STYLE, frostColor)
	local landed = 0

	-- The front waits at the last ring and races out to the next one in LOOK.expandSeconds
	-- before it lands, so each ring reads as its own thump.
	local function frontRadius(t: number): number
		for ring = 1, rings do
			if t < times[ring] then
				local fromRadius = if ring == 1 then 0 else radii[ring - 1]
				local gap = times[ring] - (if ring == 1 then 0 else times[ring - 1])
				local window = math.min(LOOK.expandSeconds, gap)
				if window <= 0 then
					return fromRadius
				end
				local u = clamp01((t - (times[ring] - window)) / window)
				return lerp(fromRadius, radii[ring], easeOut(u))
			end
		end
		return radii[rings]
	end

	-- A shard's height at `age` seconds after its ring landed: springs up, holds, sinks.
	local function shardShare(age: number): number
		if age < 0 then
			return 0
		elseif age < LOOK.shardRise then
			return easeOut(age / LOOK.shardRise)
		elseif age < LOOK.shardRise + LOOK.shardHold then
			return 1
		end
		return 1 - clamp01((age - LOOK.shardRise - LOOK.shardHold) / LOOK.shardSink)
	end

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			return false
		end
		while landed < rings and t >= times[landed + 1] do
			landed += 1
			if t - times[landed] < FRESH_SECONDS then
				dustRing(
					mist,
					centre,
					radii[landed],
					particles(LOOK.mistPoints),
					particles(LOOK.mistPerPoint)
				)
			end
		end
		local reach = frontRadius(t)
		local frontV = if reach < DUST_WALL_MIN_RADIUS
			then 0
			elseif t <= last then 1
			else 1 - clamp01((t - last) / LOOK.frontFade)
		if frontV > 0 then
			local height = DUST_WALL_HEIGHT * lerp(DUST_WALL_SETTLE, 1, frontV)
			layCircle(
				front,
				centre + UP * (height / 2),
				FLAT_U,
				FLAT_V,
				reach,
				0,
				TAU,
				DUST_WALL_WIDTH,
				height,
				true
			)
		end
		showAll(front, DUST_WALL_TRANSPARENCY, frontV)
		for ring, parts in marks do
			local age = t - times[ring]
			local v = if age < 0 then 0 else 1 - clamp01(age / LOOK.markSeconds)
			showAll(parts, LOOK.markTransparency, v)
		end
		for _, shard in shards do
			local share = shardShare(t - times[shard.ring])
			if share <= 0 then
				show(shard.part, LOOK.shardTransparency, 0)
				continue
			end
			local height = math.max(shard.height * share, MIN_SIZE)
			shard.part.Size = Vector3.new(LOOK.shardWidth, height, LOOK.shardWidth)
			-- Standing on the ring, leaning outward, its foot on the floor.
			local lean = CFrame.fromAxisAngle(shard.outward:Cross(UP), -LOOK.shardTilt)
			place(shard.part, CFrame.new(shard.base) * lean * CFrame.new(0, height / 2, 0))
			show(shard.part, LOOK.shardTransparency, 1)
		end
		local padV = 1 - clamp01((t - last - LOOK.shardRise - LOOK.shardHold) / LOOK.shardSink)
		show(pad, LOOK.padTransparency, padV)
		local grow = if delay > 0 then clamp01(t / delay) else 1
		layBall(slam, centre, LOOK.slamSize * easeOut(grow))
		show(slam, LOOK.slamTransparency, 1 - clamp01((t - delay) / LOOK.slamFade))
		return true
	end

	return step, nil
end

return buildFrostQuake
