--!strict
-- AbilityFx child: the `earthquake` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

local lowEnd = Shared.lowEnd
local EPSILON = Shared.EPSILON
local TAU = Shared.TAU
local UP = Shared.UP
local FLAT_U = Shared.FLAT_U
local FLAT_V = Shared.FLAT_V
local FRESH_SECONDS = Shared.FRESH_SECONDS
local JOINT_OVERLAP = Shared.JOINT_OVERLAP
local RING_HEIGHT = Shared.RING_HEIGHT
local DUST_STYLE = Shared.DUST_STYLE
local ABILITY_COLOR = Shared.ABILITY_COLOR
local DUST_COLOR = Shared.DUST_COLOR
local DUST_WALL_WIDTH = Shared.DUST_WALL_WIDTH
local DUST_WALL_HEIGHT = Shared.DUST_WALL_HEIGHT
local DUST_WALL_SETTLE = Shared.DUST_WALL_SETTLE
local DUST_WALL_TRANSPARENCY = Shared.DUST_WALL_TRANSPARENCY
local DUST_WALL_MIN_RADIUS = Shared.DUST_WALL_MIN_RADIUS
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local easeOut = Shared.easeOut
local around = Shared.around
local barFrame = Shared.barFrame
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local particles = Shared.particles
local bigSegments = Shared.bigSegments
local groundOf = Pool.groundOf
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

type Crack = { part: BasePart, reach: number }

-- Earthquake: a dust front stepping out ring by ring, the exact ring flashing as each lands, and
-- glowing cracks that open behind the front.
local QUAKE_MARK_COLOR = ABILITY_COLOR
local QUAKE_CRACK_COLOR = Color3.fromRGB(255, 128, 44)
local QUAKE_CRATER_COLOR = Color3.fromRGB(74, 60, 48)
local QUAKE_MAX_RINGS = 8
local QUAKE_EXPAND_SECONDS = 0.12
local QUAKE_FRONT_FADE = 0.3
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
		local frontV = if reach < DUST_WALL_MIN_RADIUS
			then 0
			elseif t <= last then 1
			else 1 - clamp01((t - last) / QUAKE_FRONT_FADE)
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

return buildEarthquake
