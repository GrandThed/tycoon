--!strict
-- AbilityFx child: the `overchargedShot` visual. Returns its builder; the parent module explains the
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
local FRESH_SECONDS = Shared.FRESH_SECONDS
local RING_WIDTH = Shared.RING_WIDTH
local MAX_EMIT_BUDGET = Shared.MAX_EMIT_BUDGET
local MOTE_LIFETIME = Shared.MOTE_LIFETIME
local SPARK_STYLE = Shared.SPARK_STYLE
local MOTE_STYLE = Shared.MOTE_STYLE
local ABILITY_COLOR = Shared.ABILITY_COLOR
local HOT_WHITE = Shared.HOT_WHITE
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local easeOut = Shared.easeOut
local unitOf = Shared.unitOf
local basis = Shared.basis
local frameAlong = Shared.frameAlong
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local particles = Shared.particles
local rate = Shared.rate
local muzzleOf = Shared.muzzleOf
local rayEnd = Pool.rayEnd
local takePart = Pool.takePart
local takeParts = Pool.takeParts
local takeBeam = Pool.takeBeam
local takeEmitter = Pool.takeEmitter
local emitAt = Pool.emitAt
local takeLight = Pool.takeLight
local lightAt = Pool.lightAt
local show = Pool.show
local showAll = Pool.showAll
local layBeam = Pool.layBeam
local showBeam = Pool.showBeam
local widenBeam = Pool.widenBeam
local layCircle = Pool.layCircle
local layBall = Pool.layBall

type RingArc = { parts: { BasePart }, ring: number, index: number }

-- Overcharged Shot: a charge ball with closing rings and a laser sight, then the beam afterglow.
local OC_CORE_COLOR = HOT_WHITE
local OC_GLOW_COLOR = ABILITY_COLOR
local OC_CORE_FROM = 0.3
local OC_CORE_TO = 1.8
local OC_GLOW_FROM = 0.6
local OC_GLOW_TO = 3.4
local OC_GLOW_TRANSPARENCY = 0.55
local OC_FLICKER = 0.25
local OC_RINGS = 2
local OC_RING_ARCS = 3
local OC_RING_ARC_DEGREES = 70
local OC_RING_ARC_SEGMENTS = 4
local OC_RING_FROM = 2.6
local OC_RING_TO = 0.9
local OC_RING_INNER_SHARE = 0.75
local OC_RING_SPIN = math.rad(540)
local OC_RING_WIDTH = 0.12
local OC_LASER_WIDTH = 0.08
local OC_LASER_FROM = 0.75
local OC_LASER_TRANSPARENCY = 0.3
local OC_MOTE_RATE = 60
local OC_MOTE_RADIUS = 3
local OC_LIGHT_CHARGE = 4
local OC_LIGHT_FIRE = 10
local OC_LIGHT_RANGE = 16
-- Feedback's full-width tube from the ray strike is the hitbox; this is only a thin trace that
-- outlasts it briefly, so the hitboxEffect slider can still hide the tube.
local OC_AFTERGLOW_SECONDS = 0.3
local OC_AFTERGLOW_WIDTH = 0.25
local OC_AFTERGLOW_TRANSPARENCY = 0.1
local OC_FLASH_SIZE = 3.2
local OC_FLASH_SECONDS = 0.15
local OC_SHOCK_SEGMENTS = 16
local OC_SHOCK_FROM = 0.5
local OC_SHOCK_TO = 3.2
local OC_SHOCK_SECONDS = 0.25
local OC_END_SPARKS = 20

-- Overcharged Shot: for delaySeconds a charge ball swells at the muzzle, two broken rings close
-- in around the aim, motes stream into it, a thin laser sight marks the line and a light builds.
-- At delaySeconds it fires: a muzzle flash and shock ring, sparks where the shot stopped (the
-- server's end point once its strike arrives) and a thin afterglow along the line. The
-- full-width beam is Feedback's hitbox effect of the ray strike, drawn once, there.
local function buildOverchargedShot(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local range = positive(def.range)
	if delay == nil or range == nil then
		return nil, nil
	end
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local right, up = basis(aim)
	local finish = delay + OC_AFTERGLOW_SECONDS
	local muzzle = muzzleOf(cast.userId, aim, cast.origin)
	local aimEnd = rayEnd(muzzle, aim, range)

	local core = takePart(kit, Enum.PartType.Ball, OC_CORE_COLOR, Enum.Material.Neon)
	local glow = takePart(kit, Enum.PartType.Ball, OC_GLOW_COLOR, Enum.Material.Neon)
	local arcs: { RingArc } = {}
	if not lowEnd then
		for ringIndex = 1, OC_RINGS do
			for index = 1, OC_RING_ARCS do
				table.insert(arcs, {
					parts = takeParts(
						kit,
						OC_RING_ARC_SEGMENTS,
						Enum.PartType.Block,
						OC_GLOW_COLOR,
						Enum.Material.Neon
					),
					ring = ringIndex,
					index = index,
				})
			end
		end
	end
	local laser = takeBeam(kit, OC_GLOW_COLOR, OC_LASER_WIDTH)
	local motes = takeEmitter(kit, MOTE_STYLE, OC_GLOW_COLOR)
	motes.emitter.Speed = NumberRange.new(OC_MOTE_RADIUS / MOTE_LIFETIME)
	local light = takeLight(kit, OC_GLOW_COLOR, OC_LIGHT_RANGE)
	local afterglow = takeBeam(kit, OC_CORE_COLOR, OC_AFTERGLOW_WIDTH)
	local flash = takePart(kit, Enum.PartType.Ball, OC_CORE_COLOR, Enum.Material.Neon)
	local shock: { BasePart } = {}
	if not lowEnd then
		shock = takeParts(
			kit,
			OC_SHOCK_SEGMENTS,
			Enum.PartType.Block,
			OC_CORE_COLOR,
			Enum.Material.Neon
		)
	end
	local sparks = takeEmitter(kit, SPARK_STYLE, OC_GLOW_COLOR)
	local rng = Random.new(cast.seq)
	local budget = 0
	local fired = false
	local fireFrom = muzzle
	local fireTo = aimEnd
	local struck: Vector3? = nil

	local function step(t: number, dt: number): boolean
		if t >= finish then
			return false
		end
		if t < delay then
			muzzle = muzzleOf(cast.userId, aim, muzzle)
			local u = t / delay
			local flicker = 1 + OC_FLICKER * (rng:NextNumber() - 0.5)
			layBall(core, muzzle, lerp(OC_CORE_FROM, OC_CORE_TO, u) * flicker)
			show(core, 0, 1)
			layBall(glow, muzzle, lerp(OC_GLOW_FROM, OC_GLOW_TO, u) * flicker)
			show(glow, OC_GLOW_TRANSPARENCY, 1)
			local arcSpan = math.rad(OC_RING_ARC_DEGREES)
			for _, arc in arcs do
				local direction = if arc.ring % 2 == 1 then 1 else -1
				local size = lerp(OC_RING_FROM, OC_RING_TO, u)
					* (if arc.ring % 2 == 1 then 1 else OC_RING_INNER_SHARE)
				local start = direction * t * OC_RING_SPIN + TAU * (arc.index - 1) / OC_RING_ARCS
				layCircle(
					arc.parts,
					muzzle,
					right,
					up,
					size,
					start,
					start + arcSpan,
					OC_RING_WIDTH,
					OC_RING_WIDTH,
					true
				)
				showAll(arc.parts, 0.1, 1)
			end
			layBeam(laser, muzzle, aimEnd)
			showBeam(laser, lerp(OC_LASER_FROM, OC_LASER_TRANSPARENCY, u), 1)
			budget = math.min(budget + rate(OC_MOTE_RATE) * dt, MAX_EMIT_BUDGET)
			while budget >= 1 do
				budget -= 1
				local outward = rng:NextUnitVector()
				emitAt(motes, frameAlong(muzzle + outward * OC_MOTE_RADIUS, -outward), 1)
			end
			lightAt(light, muzzle, OC_LIGHT_CHARGE * u)
			return true
		end
		local age = t - delay
		if not fired then
			fired = true
			fireFrom = muzzleOf(cast.userId, aim, muzzle)
			fireTo = struck or aimEnd
			show(core, 0, 0)
			show(glow, 0, 0)
			for _, arc in arcs do
				showAll(arc.parts, 0, 0)
			end
			showBeam(laser, 0, 0)
			if age < FRESH_SECONDS then
				emitAt(sparks, frameAlong(fireTo, -aim), particles(OC_END_SPARKS))
			end
		end
		local u = clamp01(age / OC_AFTERGLOW_SECONDS)
		widenBeam(afterglow, OC_AFTERGLOW_WIDTH * (1 - u))
		layBeam(afterglow, fireFrom, fireTo)
		showBeam(afterglow, OC_AFTERGLOW_TRANSPARENCY, 1 - u)
		local flashU = clamp01(age / OC_FLASH_SECONDS)
		layBall(flash, fireFrom, OC_FLASH_SIZE * (1 - flashU))
		show(flash, 0, 1 - flashU)
		if #shock > 0 then
			local shockU = clamp01(age / OC_SHOCK_SECONDS)
			local size = lerp(OC_SHOCK_FROM, OC_SHOCK_TO, easeOut(shockU))
			layCircle(shock, fireFrom, right, up, size, 0, TAU, RING_WIDTH, RING_WIDTH, true)
			showAll(shock, 0.1, 1 - shockU)
		end
		lightAt(light, fireFrom, OC_LIGHT_FIRE * (1 - u))
		return true
	end

	-- The ray's strike names where the shot really stopped (first wall, or the end of range).
	local function onStrike(strike: AbilityStrike): boolean
		if strike.tick or strike.shape ~= "ray" then
			return false
		end
		local unit = unitOf(strike.direction) or aim
		local stop = strike.endPoint or strike.origin + unit * strike.size
		struck = stop
		if fired then
			fireTo = stop
		end
		return true
	end

	return step, onStrike
end

return buildOverchargedShot
