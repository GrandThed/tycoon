--!strict
-- AbilityFx child: the `arrowRain` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local uiFolder = script.Parent.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
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
local FRESH_SECONDS = Shared.FRESH_SECONDS
local RING_WIDTH = Shared.RING_WIDTH
local RING_HEIGHT = Shared.RING_HEIGHT
local RING_TRANSPARENCY = Shared.RING_TRANSPARENCY
local FILL_TRANSPARENCY = Shared.FILL_TRANSPARENCY
local FILL_PULSE_TRANSPARENCY = Shared.FILL_PULSE_TRANSPARENCY
local PULSE_SECONDS = Shared.PULSE_SECONDS
local ZONE_FADE_IN = Shared.ZONE_FADE_IN
local ZONE_FADE_OUT = Shared.ZONE_FADE_OUT
local SPARK_STYLE = Shared.SPARK_STYLE
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local easeOut = Shared.easeOut
local envelope = Shared.envelope
local flatUnit = Shared.flatUnit
local around = Shared.around
local frameAlong = Shared.frameAlong
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local particles = Shared.particles
local ringSegments = Shared.ringSegments
local isZoneStrike = Shared.isZoneStrike
local groundOf = Pool.groundOf
local takePart = Pool.takePart
local takeParts = Pool.takeParts
local takeEmitter = Pool.takeEmitter
local emitAt = Pool.emitAt
local place = Pool.place
local show = Pool.show
local showAll = Pool.showAll
local layCircle = Pool.layCircle
local layDisc = Pool.layDisc
local layNotches = Pool.layNotches

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

return buildArrowRain
