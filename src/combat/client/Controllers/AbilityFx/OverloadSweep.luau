--!strict
-- AbilityFx child: the `overloadSweep` visual. Returns its builder; the parent module explains the
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
local UP = Shared.UP
local LIFT = Shared.LIFT
local JOINT_OVERLAP = Shared.JOINT_OVERLAP
local RING_WIDTH = Shared.RING_WIDTH
local RING_HEIGHT = Shared.RING_HEIGHT
local PULSE_SECONDS = Shared.PULSE_SECONDS
local SPARK_STYLE = Shared.SPARK_STYLE
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local envelope = Shared.envelope
local flatUnit = Shared.flatUnit
local turn = Shared.turn
local frameAlong = Shared.frameAlong
local barFrame = Shared.barFrame
local positive = Shared.positive
local rate = Shared.rate
local casterOf = Shared.casterOf
local floorUnder = Shared.floorUnder
local rootHeightOf = Shared.rootHeightOf
local takePart = Pool.takePart
local takeBeam = Pool.takeBeam
local takeEmitter = Pool.takeEmitter
local setEmitting = Pool.setEmitting
local takeLight = Pool.takeLight
local lightAt = Pool.lightAt
local place = Pool.place
local show = Pool.show
local layBeam = Pool.layBeam
local showBeam = Pool.showBeam
local widenBeam = Pool.widenBeam
local layBall = Pool.layBall
local triangle = Pool.triangle

type SectorPiece = { part: BasePart, offset: CFrame, slice: number, base: number }

-- Overload Sweep: a thick beam sweeping left to right, lighting each server slice as it lands.
local SWEEP_CORE_COLOR = Theme.COMBAT_RANGE_BEAM_CORE_COLOR
local SWEEP_GLOW_COLOR = Theme.COMBAT_RANGE_BEAM_COLOR
local SWEEP_CORE_WIDTH = 0.7
local SWEEP_GLOW_WIDTH = 2.4
local SWEEP_PULSE_WIDTH = 1.5
local SWEEP_GLOW_TRANSPARENCY = Theme.COMBAT_RANGE_BEAM_GLOW_TRANSPARENCY
local SWEEP_MAX_SLICES = 36
local SWEEP_FILL_TRANSPARENCY = 0.86
local SWEEP_RIM_TRANSPARENCY = 0.25
local SWEEP_SLICE_FADE_IN = 0.06
local SWEEP_FADE_IN = 0.06
local SWEEP_FADE_SECONDS = 0.3
local SWEEP_FLARE_SIZE = 2.2
local SWEEP_FLARE_FORWARD = 1
local SWEEP_TIP_SIZE = 1.6
local SWEEP_TIP_SPARK_RATE = 30
local SWEEP_LIGHT = 5
local SWEEP_LIGHT_RANGE = 14

-- Overload Sweep: a thick beam of length `range` from the caster's root sweeps left to right,
-- crossing each server slice's centre as that slice fires ((i−1)·durationSeconds/count), while
-- the floor under the swept sector lights up slice by slice (exact radius, no pad). Follows the
-- caster; every tick widens the beam for a moment.
local function buildOverloadSweep(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local duration = positive(def.durationSeconds)
	local count = positive(def.count)
	local arcDegrees = positive(def.arcDegrees)
	local range = positive(def.range)
	if duration == nil or count == nil or arcDegrees == nil or range == nil then
		return nil, nil
	end
	local sweepSeconds: number = duration
	local reach: number = range
	local heading = flatUnit(cast.direction) or Vector3.zAxis
	local slices = math.clamp(math.floor(count), 1, SWEEP_MAX_SLICES)
	local sweep = math.rad(math.min(arcDegrees, 360))
	local slice = sweep / slices
	local firstAngle = -sweep / 2 + slice / 2
	local lastAngle = sweep / 2 - slice / 2
	local lastFire = (slices - 1) * sweepSeconds / slices
	local finish = sweepSeconds + SWEEP_FADE_SECONDS
	local base =
		Vector3.new(cast.origin.X, cast.origin.Y - rootHeightOf(cast.userId) + LIFT, cast.origin.Z)
	local toBase = CFrame.new(-base)
	local pieces: { SectorPiece } = {}
	for index = 1, slices do
		local a0 = -sweep / 2 + slice * (index - 1)
		local p0 = base + turn(heading, a0) * reach
		local p1 = base + turn(heading, a0 + slice) * reach
		if not lowEnd then
			for _, wedge in triangle(kit, base, p0, p1, SWEEP_GLOW_COLOR) do
				table.insert(pieces, {
					part = wedge.part,
					offset = toBase * wedge.frame,
					slice = index,
					base = SWEEP_FILL_TRANSPARENCY,
				})
			end
		end
		local rim = takePart(kit, Enum.PartType.Block, SWEEP_GLOW_COLOR, Enum.Material.Neon)
		local frame, length = barFrame(p0, p1, UP)
		rim.Size = Vector3.new(RING_WIDTH, RING_HEIGHT, length + RING_WIDTH * JOINT_OVERLAP)
		table.insert(pieces, {
			part = rim,
			offset = toBase * frame,
			slice = index,
			base = SWEEP_RIM_TRANSPARENCY,
		})
	end
	local core = takeBeam(kit, SWEEP_CORE_COLOR, SWEEP_CORE_WIDTH)
	local glow = takeBeam(kit, SWEEP_GLOW_COLOR, SWEEP_GLOW_WIDTH)
	local flare = takePart(kit, Enum.PartType.Ball, SWEEP_CORE_COLOR, Enum.Material.Neon)
	local tip = takePart(kit, Enum.PartType.Ball, SWEEP_GLOW_COLOR, Enum.Material.Neon)
	local tipSparks = takeEmitter(kit, SPARK_STYLE, SWEEP_GLOW_COLOR)
	tipSparks.emitter.Rate = rate(SWEEP_TIP_SPARK_RATE)
	local light = takeLight(kit, SWEEP_GLOW_COLOR, SWEEP_LIGHT_RANGE)
	local rng = Random.new(cast.seq)
	local rootPoint = cast.origin
	local floorY = base.Y - LIFT
	local pulse = 0

	local function step(t: number, dt: number): boolean
		if t >= finish then
			setEmitting(tipSparks, false)
			return false
		end
		local root, humanoid = casterOf(cast.userId)
		if root ~= nil then
			rootPoint = root.Position
			floorY = floorUnder(root, humanoid)
		end
		pulse = math.max(pulse - dt / PULSE_SECONDS, 0)
		local v = envelope(t, 0, finish, SWEEP_FADE_IN, SWEEP_FADE_SECONDS)
		local progress = if lastFire > 0 then clamp01(t / lastFire) else 1
		local direction = turn(heading, lerp(firstAngle, lastAngle, progress))
		local reachPoint = rootPoint + direction * reach
		layBeam(core, rootPoint, reachPoint)
		showBeam(core, 0, v)
		widenBeam(glow, SWEEP_GLOW_WIDTH + SWEEP_PULSE_WIDTH * pulse)
		layBeam(glow, rootPoint, reachPoint)
		showBeam(glow, SWEEP_GLOW_TRANSPARENCY, v)
		layBall(
			flare,
			rootPoint + direction * SWEEP_FLARE_FORWARD,
			SWEEP_FLARE_SIZE * (0.85 + 0.3 * rng:NextNumber())
		)
		show(flare, 0, v)
		layBall(tip, reachPoint, SWEEP_TIP_SIZE)
		show(tip, 0.1, v)
		tipSparks.attachment.WorldCFrame = frameAlong(reachPoint, -direction)
		setEmitting(tipSparks, t < sweepSeconds)
		local shift = CFrame.new(Vector3.new(rootPoint.X, floorY + LIFT, rootPoint.Z))
		for _, piece in pieces do
			place(piece.part, shift * piece.offset)
			local fireAt = (piece.slice - 1) * sweepSeconds / slices
			local reveal = if t < fireAt then 0 else clamp01((t - fireAt) / SWEEP_SLICE_FADE_IN)
			show(piece.part, piece.base, math.min(reveal, v))
		end
		lightAt(light, rootPoint + direction * SWEEP_FLARE_FORWARD, SWEEP_LIGHT * v)
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if not strike.tick then
			return false
		end
		pulse = 1
		return true
	end

	return step, onStrike
end

return buildOverloadSweep
