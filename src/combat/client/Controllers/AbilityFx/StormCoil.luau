--!strict
-- AbilityFx child: the `stormCoil` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local uiFolder = script.Parent.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type AbilityStrike = Shared.AbilityStrike
type BeamHandle = Shared.BeamHandle
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

local lowEnd = Shared.lowEnd
local TAU = Shared.TAU
local UP = Shared.UP
local FLAT_U = Shared.FLAT_U
local FLAT_V = Shared.FLAT_V
local STAND_UP = Shared.STAND_UP
local RING_WIDTH = Shared.RING_WIDTH
local RING_HEIGHT = Shared.RING_HEIGHT
local FILL_PULSE_TRANSPARENCY = Shared.FILL_PULSE_TRANSPARENCY
local PULSE_SECONDS = Shared.PULSE_SECONDS
local ZONE_FADE_IN = Shared.ZONE_FADE_IN
local SPARK_STYLE = Shared.SPARK_STYLE
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local easeOut = Shared.easeOut
local envelope = Shared.envelope
local unitOf = Shared.unitOf
local frameAlong = Shared.frameAlong
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local particles = Shared.particles
local ringSegments = Shared.ringSegments
local muzzleOf = Shared.muzzleOf
local isZoneStrike = Shared.isZoneStrike
local groundOf = Pool.groundOf
local takePart = Pool.takePart
local takeParts = Pool.takeParts
local takeBeam = Pool.takeBeam
local takeEmitter = Pool.takeEmitter
local emitAt = Pool.emitAt
local takeLight = Pool.takeLight
local lightAt = Pool.lightAt
local place = Pool.place
local show = Pool.show
local showAll = Pool.showAll
local layBeam = Pool.layBeam
local showBeam = Pool.showBeam
local layCircle = Pool.layCircle
local layDisc = Pool.layDisc

type PylonSpec = { shape: Enum.PartType, size: Vector3, height: number, glow: boolean }
type PylonPiece = { part: BasePart, offset: CFrame, glow: boolean }

-- Storm Coil: a pylon thrown to the point, crackling inside the exact (faint) zap radius.
local COIL_COLOR = Theme.COMBAT_RANGE_LIGHTNING_COLOR
local COIL_METAL_COLOR = Color3.fromRGB(70, 76, 88)
local COIL_ARC_COLOR = Theme.COMBAT_RANGE_LIGHTNING_CORE_COLOR
-- Shared with Feedback, whose zap bolts start at the pylon's glowing top.
local COIL_TOP_HEIGHT = Theme.COMBAT_RANGE_COIL_TOP_HEIGHT
local COIL_PYLON: { PylonSpec } = {
	{
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.6, 1.8, 1.8),
		height = 0.3,
		glow = false,
	},
	{
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(3.6, 0.45, 0.45),
		height = 2.4,
		glow = false,
	},
	{
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.2, 1.4, 1.4),
		height = 1.4,
		glow = true,
	},
	{
		shape = Enum.PartType.Cylinder,
		size = Vector3.new(0.2, 1.2, 1.2),
		height = 2.3,
		glow = true,
	},
	{ shape = Enum.PartType.Cylinder, size = Vector3.new(0.2, 1, 1), height = 3.2, glow = true },
	{
		shape = Enum.PartType.Ball,
		size = Vector3.new(1, 1, 1),
		height = COIL_TOP_HEIGHT,
		glow = true,
	},
}
local COIL_PIVOT_HEIGHT = 2.2
local COIL_GLOW_TRANSPARENCY = 0.1
local COIL_THROW_ARC = 4
local COIL_TUMBLE = math.rad(720)
local COIL_DEPLOY_SECONDS = 0.18
local COIL_RING_TRANSPARENCY = 0.45
local COIL_FILL_TRANSPARENCY = 0.94
local COIL_ARCS = 3
local COIL_ARCS_LOW_END = 1
local COIL_ARC_SEGMENTS = 3
local COIL_ARC_MIN = 1.2
local COIL_ARC_REACH = 2.6
local COIL_ARC_JITTER = 0.5
local COIL_ARC_WIDTH = 0.12
local COIL_ARC_CHANCE = 0.7
local COIL_CRACKLE_SECONDS = 0.07
local COIL_FADE_SECONDS = 0.25
local COIL_LIGHT = 3
local COIL_LIGHT_PULSE = 6
local COIL_LIGHT_RANGE = 14
local COIL_PULSE_SPARKS = 12

-- Storm Coil: a pylon tumbles from the caster's hand to the ground point over delaySeconds and
-- plants itself; a faint ring snaps out to exactly `radius` and holds for durationSeconds while
-- small arcs crackle round its top. Every zap tick flares the coils, the ring and the light and
-- throws sparks. Feedback draws the zaps and their chains from `links`.
local function buildStormCoil(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local delay = nonNegative(def.delaySeconds)
	local duration = positive(def.durationSeconds)
	local radius = positive(def.radius)
	if delay == nil or duration == nil or radius == nil then
		return nil, nil
	end
	local reach: number = radius
	local centre = groundOf(cast)
	local top = centre + UP * COIL_TOP_HEIGHT
	local zoneEnd = delay + duration
	local finish = zoneEnd + COIL_FADE_SECONDS
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local start = muzzleOf(cast.userId, aim, cast.origin)

	local pylon: { PylonPiece } = {}
	for _, spec in COIL_PYLON do
		local part = if spec.glow
			then takePart(
				kit,
				spec.shape,
				if spec.shape == Enum.PartType.Ball then COIL_ARC_COLOR else COIL_COLOR,
				Enum.Material.Neon
			)
			else takePart(kit, spec.shape, COIL_METAL_COLOR, Enum.Material.Metal)
		part.Size = spec.size
		local offset = CFrame.new(0, spec.height, 0)
		if spec.shape == Enum.PartType.Cylinder then
			offset *= STAND_UP
		end
		table.insert(pylon, { part = part, offset = offset, glow = spec.glow })
	end
	local ring = takeParts(kit, ringSegments(), Enum.PartType.Block, COIL_COLOR, Enum.Material.Neon)
	local fill: BasePart? = nil
	if not lowEnd then
		local disc = takePart(kit, Enum.PartType.Cylinder, COIL_COLOR, Enum.Material.Neon)
		layDisc(disc, centre, reach)
		fill = disc
	end
	local arcs: { { BeamHandle } } = {}
	for _ = 1, if lowEnd then COIL_ARCS_LOW_END else COIL_ARCS do
		local list: { BeamHandle } = {}
		for _ = 1, COIL_ARC_SEGMENTS do
			table.insert(list, takeBeam(kit, COIL_ARC_COLOR, COIL_ARC_WIDTH))
		end
		table.insert(arcs, list)
	end
	local sparks = takeEmitter(kit, SPARK_STYLE, COIL_COLOR)
	local light = takeLight(kit, COIL_COLOR, COIL_LIGHT_RANGE)
	local rng = Random.new(cast.seq)
	local nextCrackle = 0
	local deployed = false
	local pulse = 0
	local sparked = false

	local function hideArcs(): ()
		for _, list in arcs do
			for _, beam in list do
				showBeam(beam, 0, 0)
			end
		end
	end

	local function step(t: number, dt: number): boolean
		if t >= finish then
			return false
		end
		pulse = math.max(pulse - dt / PULSE_SECONDS, 0)
		local frame: CFrame
		if t < delay then
			local u = t / delay
			local position = start:Lerp(centre + UP * COIL_PIVOT_HEIGHT, u)
				+ UP * (COIL_THROW_ARC * 4 * u * (1 - u))
			local tumble = t * COIL_TUMBLE
			frame = CFrame.new(position)
				* CFrame.Angles(tumble, 0, tumble * 0.7)
				* CFrame.new(0, -COIL_PIVOT_HEIGHT, 0)
		else
			frame = CFrame.new(centre)
		end
		local pylonV = envelope(t, 0, finish, 0, COIL_FADE_SECONDS)
		for _, piece in pylon do
			place(piece.part, frame * piece.offset)
			show(piece.part, if piece.glow then COIL_GLOW_TRANSPARENCY * (1 - pulse) else 0, pylonV)
		end

		local zoneV = envelope(t, delay, finish, ZONE_FADE_IN, COIL_FADE_SECONDS)
		if t >= delay and not deployed then
			local deploy = clamp01((t - delay) / COIL_DEPLOY_SECONDS)
			layCircle(
				ring,
				centre,
				FLAT_U,
				FLAT_V,
				reach * easeOut(deploy),
				0,
				TAU,
				RING_WIDTH,
				RING_HEIGHT,
				true
			)
			deployed = deploy >= 1
		end
		showAll(ring, COIL_RING_TRANSPARENCY * (1 - pulse), zoneV)
		local disc = fill
		if disc ~= nil then
			show(disc, lerp(COIL_FILL_TRANSPARENCY, FILL_PULSE_TRANSPARENCY, pulse), zoneV)
		end

		if t >= delay and t < zoneEnd then
			if t >= nextCrackle then
				nextCrackle = t + COIL_CRACKLE_SECONDS
				for _, list in arcs do
					if rng:NextNumber() >= COIL_ARC_CHANCE + pulse then
						for _, beam in list do
							showBeam(beam, 0, 0)
						end
						continue
					end
					local reachOut = top
						+ rng:NextUnitVector() * rng:NextNumber(COIL_ARC_MIN, COIL_ARC_REACH)
					local previous = top
					for index, beam in list do
						local point = top:Lerp(reachOut, index / #list)
						if index < #list then
							point += rng:NextUnitVector() * COIL_ARC_JITTER
						end
						layBeam(beam, previous, point)
						showBeam(beam, 0, zoneV)
						previous = point
					end
				end
			end
		else
			hideArcs()
		end
		if sparked then
			sparked = false
			emitAt(sparks, frameAlong(top, UP), particles(COIL_PULSE_SPARKS))
		end
		lightAt(light, top, (COIL_LIGHT + COIL_LIGHT_PULSE * pulse) * zoneV)
		return true
	end

	local function onStrike(strike: AbilityStrike): boolean
		if not isZoneStrike(strike, centre) then
			return false
		end
		pulse = 1
		sparked = true
		return true
	end

	return step, onStrike
end

return buildStormCoil
