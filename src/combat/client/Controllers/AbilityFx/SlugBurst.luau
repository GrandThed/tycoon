--!strict
-- AbilityFx child: the `slugBurst` visual. Returns its builder; the parent module explains the
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
local UP = Shared.UP
local FRESH_SECONDS = Shared.FRESH_SECONDS
local SPARK_STYLE = Shared.SPARK_STYLE
local SMOKE_STYLE = Shared.SMOKE_STYLE
local SMOKE_COLOR = Shared.SMOKE_COLOR
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
local place = Pool.place
local show = Pool.show
local layBar = Pool.layBar
local layBall = Pool.layBall

type SlugBlast = {
	flash: BasePart,
	streaks: { BasePart },
	casing: BasePart?,
	muzzle: Vector3,
	startsAt: number,
	casingVelocity: Vector3,
	fired: boolean,
}

-- Slug Burst: one muzzle blast per slug (flash, flare streaks inside the cone, smoke, a shell).
local SLUG_COLOR = Theme.COMBAT_RANGE_BLAST_COLOR
local SLUG_CASING_COLOR = Color3.fromRGB(200, 60, 50)
local SLUG_MAX_BLASTS = 12
local SLUG_FLASH_SECONDS = 0.14
local SLUG_FLASH_SIZE = 2.6
local SLUG_FLASH_MIN = 0.3
local SLUG_FLASH_FORWARD = 0.8
local SLUG_STREAKS = 6
local SLUG_STREAKS_LOW_END = 3
local SLUG_STREAK_SHARE = 0.8 -- flare streaks lean out to this share of the cone's half-angle
local SLUG_STREAK_LENGTH = 3.8
local SLUG_STREAK_WIDTH = 0.28
local SLUG_SMOKE = 6
local SLUG_SPARKS = 10
local SLUG_CASING_SIZE = Vector3.new(0.22, 0.22, 0.5)
local SLUG_CASING_SECONDS = 0.5
local SLUG_CASING_SIDE_MIN = 6
local SLUG_CASING_SIDE_MAX = 10
local SLUG_CASING_UP_MIN = 8
local SLUG_CASING_UP_MAX = 12
local SLUG_CASING_GRAVITY = 60
local SLUG_CASING_TUMBLE = 20
local SLUG_LIGHT = 7
local SLUG_LIGHT_RANGE = 14

-- Slug Burst: a muzzle blast per slug at (k−1)·tickSeconds (count blasts): a flash, flare
-- streaks leaning out inside the cone's opening, smoke, sparks, an ejected shell and a light
-- kick. Feedback draws each slug's cone.
local function buildSlugBurst(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local count = positive(def.count)
	local tick = nonNegative(def.tickSeconds)
	local arcDegrees = nonNegative(def.arcDegrees)
	if count == nil or tick == nil or arcDegrees == nil then
		return nil, nil
	end
	local blasts = math.min(math.floor(count), SLUG_MAX_BLASTS)
	if blasts < 1 then
		return nil, nil
	end
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local right, up = basis(aim)
	local lean = math.rad(math.clamp(arcDegrees, 0, 179) / 2) * SLUG_STREAK_SHARE
	local streakCount = if lowEnd then SLUG_STREAKS_LOW_END else SLUG_STREAKS
	local directions: { Vector3 } = {}
	for index = 1, streakCount do
		local around3 = TAU * (index - 1) / streakCount
		local sideways = right * math.cos(around3) + up * math.sin(around3)
		table.insert(directions, (aim * math.cos(lean) + sideways * math.sin(lean)).Unit)
	end
	local list: { SlugBlast } = {}
	for index = 1, blasts do
		local casing: BasePart? = nil
		if not lowEnd then
			local shell =
				takePart(kit, Enum.PartType.Block, SLUG_CASING_COLOR, Enum.Material.SmoothPlastic)
			shell.Size = SLUG_CASING_SIZE
			casing = shell
		end
		table.insert(list, {
			flash = takePart(kit, Enum.PartType.Ball, SLUG_COLOR, Enum.Material.Neon),
			streaks = takeParts(
				kit,
				streakCount,
				Enum.PartType.Block,
				SLUG_COLOR,
				Enum.Material.Neon
			),
			casing = casing,
			muzzle = cast.origin,
			startsAt = (index - 1) * tick,
			casingVelocity = Vector3.zero,
			fired = false,
		})
	end
	local smoke = takeEmitter(kit, SMOKE_STYLE, SMOKE_COLOR)
	local sparks = takeEmitter(kit, SPARK_STYLE, SLUG_COLOR)
	local light = takeLight(kit, SLUG_COLOR, SLUG_LIGHT_RANGE)
	local rng = Random.new(cast.seq)
	local finish = (blasts - 1) * tick + math.max(SLUG_CASING_SECONDS, SLUG_FLASH_SECONDS)
	local lastMuzzle = cast.origin

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			return false
		end
		local brightest = 0
		for _, blast in list do
			local age = t - blast.startsAt
			if age < 0 then
				continue
			end
			if not blast.fired then
				blast.fired = true
				blast.muzzle = muzzleOf(cast.userId, aim, cast.origin)
				blast.casingVelocity = right
						* rng:NextNumber(SLUG_CASING_SIDE_MIN, SLUG_CASING_SIDE_MAX)
					+ UP * rng:NextNumber(SLUG_CASING_UP_MIN, SLUG_CASING_UP_MAX)
				if age < FRESH_SECONDS then
					local frame = frameAlong(blast.muzzle + aim * SLUG_FLASH_FORWARD, aim)
					emitAt(smoke, frame, particles(SLUG_SMOKE))
					emitAt(sparks, frame, particles(SLUG_SPARKS))
				end
			end
			lastMuzzle = blast.muzzle
			local u = clamp01(age / SLUG_FLASH_SECONDS)
			layBall(
				blast.flash,
				blast.muzzle + aim * SLUG_FLASH_FORWARD,
				lerp(SLUG_FLASH_SIZE, SLUG_FLASH_MIN, u)
			)
			show(blast.flash, 0, 1 - u)
			for index, part in blast.streaks do
				local tip = blast.muzzle
					+ directions[index] * (SLUG_STREAK_LENGTH * (0.4 + 0.6 * easeOut(u)))
				layBar(part, blast.muzzle, tip, SLUG_STREAK_WIDTH * (1 - 0.6 * u), aim)
				show(part, 0.05, 1 - u)
			end
			local casing = blast.casing
			if casing ~= nil then
				local position = blast.muzzle
					+ blast.casingVelocity * age
					+ Vector3.new(0, -0.5 * SLUG_CASING_GRAVITY * age * age, 0)
				local tumble = age * SLUG_CASING_TUMBLE
				place(casing, CFrame.new(position) * CFrame.Angles(tumble, tumble * 0.65, 0))
				local casingU = age / SLUG_CASING_SECONDS
				show(casing, 0, if casingU >= 1 then 0 else 1 - clamp01((casingU - 0.7) / 0.3))
			end
			brightest = math.max(brightest, 1 - u)
		end
		lightAt(light, lastMuzzle, SLUG_LIGHT * brightest)
		return true
	end

	return step, nil
end

return buildSlugBurst
