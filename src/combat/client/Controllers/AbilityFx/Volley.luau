--!strict
-- AbilityFx child: the `volley` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local uiFolder = script.Parent.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

local lowEnd = Shared.lowEnd
local TAU = Shared.TAU
local FRESH_SECONDS = Shared.FRESH_SECONDS
local RING_WIDTH = Shared.RING_WIDTH
local SPARK_STYLE = Shared.SPARK_STYLE
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local easeOut = Shared.easeOut
local unitOf = Shared.unitOf
local basis = Shared.basis
local frameAlong = Shared.frameAlong
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local particles = Shared.particles
local muzzleOf = Shared.muzzleOf
local takePart = Pool.takePart
local takeParts = Pool.takeParts
local takeEmitter = Pool.takeEmitter
local emitAt = Pool.emitAt
local takeLight = Pool.takeLight
local lightAt = Pool.lightAt
local show = Pool.show
local showAll = Pool.showAll
local layCircle = Pool.layCircle
local layBar = Pool.layBar
local layBall = Pool.layBall

-- Volley: a gold flash and a fan of streaks across the volley's arc.
local VOLLEY_COLOR = Theme.COMBAT_RANGE_CHARGE_COLOR
local VOLLEY_SECONDS = 0.35
local VOLLEY_MAX_STREAKS = 16
local VOLLEY_STREAK_START = 0.4
local VOLLEY_STREAK_LENGTH = 4.5
local VOLLEY_STREAK_WIDTH = 0.18
local VOLLEY_STREAK_TRANSPARENCY = 0.1
local VOLLEY_GROW_SECONDS = 0.1
local VOLLEY_FLASH_SIZE = 2.8
local VOLLEY_RING_SEGMENTS = 12
local VOLLEY_RING_FROM = 0.4
local VOLLEY_RING_TO = 2.6
local VOLLEY_SPARKS = 14
local VOLLEY_LIGHT = 5
local VOLLEY_LIGHT_RANGE = 12

-- Volley: at the cast, a gold flash at the bow with a fan of streaks across arcDegrees (one per
-- arrow, up to the split cap), a ring snapping out round the aim, sparks and a light. Feedback
-- flies the arrows themselves.
local function buildVolley(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local count = positive(def.count)
	local arcDegrees = nonNegative(def.arcDegrees)
	if count == nil or arcDegrees == nil then
		return nil, nil
	end
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local right, up = basis(aim)
	local muzzle = muzzleOf(cast.userId, aim, cast.origin)
	local fan = math.clamp(math.floor(count), 1, VOLLEY_MAX_STREAKS)
	if lowEnd then
		fan = math.max(math.ceil(fan / 2), 1)
	end
	local spread = math.rad(arcDegrees)
	local directions: { Vector3 } = {}
	for index = 1, fan do
		local angle = if fan > 1 then -spread / 2 + spread * (index - 1) / (fan - 1) else 0
		table.insert(directions, (aim * math.cos(angle) + right * math.sin(angle)).Unit)
	end
	local streaks = takeParts(kit, fan, Enum.PartType.Block, VOLLEY_COLOR, Enum.Material.Neon)
	local flash = takePart(kit, Enum.PartType.Ball, VOLLEY_COLOR, Enum.Material.Neon)
	local ring: { BasePart } = {}
	if not lowEnd then
		ring = takeParts(
			kit,
			VOLLEY_RING_SEGMENTS,
			Enum.PartType.Block,
			VOLLEY_COLOR,
			Enum.Material.Neon
		)
	end
	local light = takeLight(kit, VOLLEY_COLOR, VOLLEY_LIGHT_RANGE)
	local sparks = takeEmitter(kit, SPARK_STYLE, VOLLEY_COLOR)
	local burst = false

	local function step(t: number, _dt: number): boolean
		if t >= VOLLEY_SECONDS then
			return false
		end
		if not burst then
			burst = true
			if t < FRESH_SECONDS then
				emitAt(sparks, frameAlong(muzzle, aim), particles(VOLLEY_SPARKS))
			end
		end
		local u = t / VOLLEY_SECONDS
		local grow = easeOut(clamp01(t / VOLLEY_GROW_SECONDS))
		local fade = 1 - clamp01((t - VOLLEY_GROW_SECONDS) / (VOLLEY_SECONDS - VOLLEY_GROW_SECONDS))
		for index, part in streaks do
			local direction = directions[index]
			local a = muzzle + direction * VOLLEY_STREAK_START
			layBar(part, a, a + direction * (VOLLEY_STREAK_LENGTH * grow), VOLLEY_STREAK_WIDTH, up)
			show(part, VOLLEY_STREAK_TRANSPARENCY, fade)
		end
		layBall(flash, muzzle, VOLLEY_FLASH_SIZE * (1 - easeOut(u)))
		show(flash, 0, 1 - u)
		if #ring > 0 then
			local spreadOut = lerp(VOLLEY_RING_FROM, VOLLEY_RING_TO, easeOut(u))
			layCircle(ring, muzzle, right, up, spreadOut, 0, TAU, RING_WIDTH, RING_WIDTH, true)
			showAll(ring, 0.1, 1 - u)
		end
		lightAt(light, muzzle, VOLLEY_LIGHT * (1 - u))
		return true
	end

	return step, nil
end

return buildVolley
