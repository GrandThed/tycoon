--!strict
-- AbilityFx child: the `bladeStorm` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type AbilityStrike = Shared.AbilityStrike
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

local lowEnd = Shared.lowEnd
local TAU = Shared.TAU
local UP = Shared.UP
local FLAT_U = Shared.FLAT_U
local FLAT_V = Shared.FLAT_V
local RING_WIDTH = Shared.RING_WIDTH
local RING_HEIGHT = Shared.RING_HEIGHT
local RING_TRANSPARENCY = Shared.RING_TRANSPARENCY
local FILL_TRANSPARENCY = Shared.FILL_TRANSPARENCY
local FILL_PULSE_TRANSPARENCY = Shared.FILL_PULSE_TRANSPARENCY
local PULSE_SECONDS = Shared.PULSE_SECONDS
local ZONE_FADE_IN = Shared.ZONE_FADE_IN
local ZONE_FADE_OUT = Shared.ZONE_FADE_OUT
local MAX_EMIT_BUDGET = Shared.MAX_EMIT_BUDGET
local MOTE_LIFETIME = Shared.MOTE_LIFETIME
local MOTE_STYLE = Shared.MOTE_STYLE
local ABILITY_COLOR = Shared.ABILITY_COLOR
local HOT_WHITE = Shared.HOT_WHITE
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local envelope = Shared.envelope
local unitOf = Shared.unitOf
local around = Shared.around
local frameAlong = Shared.frameAlong
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local rate = Shared.rate
local ringSegments = Shared.ringSegments
local muzzleOf = Shared.muzzleOf
local isZoneStrike = Shared.isZoneStrike
local groundOf = Pool.groundOf
local takePart = Pool.takePart
local takeParts = Pool.takeParts
local takeEmitter = Pool.takeEmitter
local emitAt = Pool.emitAt
local takeTrail = Pool.takeTrail
local layTrail = Pool.layTrail
local place = Pool.place
local show = Pool.show
local showAll = Pool.showAll
local layCircle = Pool.layCircle
local layBall = Pool.layBall
local layDisc = Pool.layDisc

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

return buildBladeStorm
