--!strict
-- AbilityFx child: the `leapSmash` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

local lowEnd = Shared.lowEnd
local TAU = Shared.TAU
local UP = Shared.UP
local FLAT_U = Shared.FLAT_U
local FLAT_V = Shared.FLAT_V
local FRESH_SECONDS = Shared.FRESH_SECONDS
local RING_WIDTH = Shared.RING_WIDTH
local RING_HEIGHT = Shared.RING_HEIGHT
local RING_TRANSPARENCY = Shared.RING_TRANSPARENCY
local FILL_TRANSPARENCY = Shared.FILL_TRANSPARENCY
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
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local particles = Shared.particles
local ringSegments = Shared.ringSegments
local bigSegments = Shared.bigSegments
local casterOf = Shared.casterOf
local groundOf = Pool.groundOf
local takePart = Pool.takePart
local takeParts = Pool.takeParts
local takeEmitter = Pool.takeEmitter
local takeTrail = Pool.takeTrail
local layTrail = Pool.layTrail
local takeLight = Pool.takeLight
local lightAt = Pool.lightAt
local place = Pool.place
local show = Pool.show
local showAll = Pool.showAll
local layCircle = Pool.layCircle
local layDisc = Pool.layDisc
local layNotches = Pool.layNotches
local dustRing = Pool.dustRing

type Chunk = { part: BasePart, velocity: Vector3, spin: Vector3 }

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
		if dustV > 0 and reach * spread > DUST_WALL_MIN_RADIUS then
			local height = DUST_WALL_HEIGHT * lerp(DUST_WALL_SETTLE, 1, dustV)
			layCircle(
				dustWall,
				centre + UP * (height / 2),
				FLAT_U,
				FLAT_V,
				reach * spread,
				0,
				TAU,
				DUST_WALL_WIDTH,
				height,
				true
			)
			showAll(dustWall, DUST_WALL_TRANSPARENCY, dustV)
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

return buildLeapSmash
