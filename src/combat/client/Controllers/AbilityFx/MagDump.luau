--!strict
-- AbilityFx child: the `magDump` visual. Returns its builder; the parent module explains the
-- division of labour with FeedbackController, the timing rule and the low-end gate.

local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook

local UP = Shared.UP
local MUZZLE_FORWARD = Shared.MUZZLE_FORWARD
local SPARK_STYLE = Shared.SPARK_STYLE
local SMOKE_STYLE = Shared.SMOKE_STYLE
local SMOKE_COLOR = Shared.SMOKE_COLOR
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local envelope = Shared.envelope
local unitOf = Shared.unitOf
local frameAlong = Shared.frameAlong
local positive = Shared.positive
local rate = Shared.rate
local casterOf = Shared.casterOf
local handOf = Shared.handOf
local aimOf = Shared.aimOf
local takePart = Pool.takePart
local takeEmitter = Pool.takeEmitter
local setEmitting = Pool.setEmitting
local takeLight = Pool.takeLight
local lightAt = Pool.lightAt
local show = Pool.show
local layBall = Pool.layBall

-- Mag Dump: the gun glows hotter, spits sparks and smokes for the whole buff.
local MAG_HEAT_COLOR = Color3.fromRGB(255, 96, 32)
local MAG_HOT_COLOR = Color3.fromRGB(255, 236, 180)
local MAG_SPARK_COLOR = Color3.fromRGB(255, 200, 90)
local MAG_WHITE_SHARE = 0.5 -- how far toward white-hot the glow gets at the end
local MAG_GLOW_MIN = 0.6
local MAG_GLOW_MAX = 1.2
local MAG_HEAT_GROWTH = 0.4
local MAG_GLOW_TRANSPARENCY_MIN = 0.15
local MAG_GLOW_TRANSPARENCY_MAX = 0.45
local MAG_HAND_GLOW = 1.6
local MAG_HAND_COOL = 0.85
local MAG_HAND_HOT = 0.55
local MAG_SPARK_RATE = 45
local MAG_SMOKE_RATE = 10
local MAG_FADE_IN = 0.05
local MAG_TAIL_SECONDS = 0.25
local MAG_LIGHT = 3
local MAG_LIGHT_HEAT = 4
local MAG_LIGHT_RANGE = 10

-- Mag Dump: for durationSeconds the gun hand glows and heats from orange toward white, a
-- flickering muzzle glow spits sparks forward, smoke curls up and a light flickers; everything
-- follows the caster's hand and aim.
local function buildMagDump(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local duration = positive(def.durationSeconds)
	if duration == nil then
		return nil, nil
	end
	local firing: number = duration
	local finish = firing + MAG_TAIL_SECONDS
	local heat = takePart(kit, Enum.PartType.Ball, MAG_HEAT_COLOR, Enum.Material.Neon)
	local hand = takePart(kit, Enum.PartType.Ball, MAG_HEAT_COLOR, Enum.Material.Neon)
	local sparks = takeEmitter(kit, SPARK_STYLE, MAG_SPARK_COLOR)
	sparks.emitter.Rate = rate(MAG_SPARK_RATE)
	local smoke = takeEmitter(kit, SMOKE_STYLE, SMOKE_COLOR)
	smoke.emitter.Rate = rate(MAG_SMOKE_RATE)
	local light = takeLight(kit, MAG_HEAT_COLOR, MAG_LIGHT_RANGE)
	local rng = Random.new(cast.seq)
	local look = unitOf(cast.direction) or Vector3.zAxis
	local handPoint = cast.origin
	local muzzle = cast.origin + look * MUZZLE_FORWARD

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			setEmitting(sparks, false)
			setEmitting(smoke, false)
			return false
		end
		local root, _, character = casterOf(cast.userId)
		if root ~= nil then
			look = aimOf(cast.userId, root)
			handPoint = handOf(character, root)
			muzzle = handPoint + look * MUZZLE_FORWARD
		end
		local share = clamp01(t / firing)
		local v = envelope(t, 0, finish, MAG_FADE_IN, MAG_TAIL_SECONDS)
		local flicker = rng:NextNumber()
		heat.Color = MAG_HEAT_COLOR:Lerp(MAG_HOT_COLOR, share * MAG_WHITE_SHARE)
		layBall(
			heat,
			muzzle,
			lerp(MAG_GLOW_MIN, MAG_GLOW_MAX, flicker) * (1 + MAG_HEAT_GROWTH * share)
		)
		show(heat, lerp(MAG_GLOW_TRANSPARENCY_MIN, MAG_GLOW_TRANSPARENCY_MAX, flicker), v)
		layBall(hand, handPoint, MAG_HAND_GLOW)
		show(hand, lerp(MAG_HAND_COOL, MAG_HAND_HOT, share), v)
		local on = t < firing
		sparks.attachment.WorldCFrame = frameAlong(muzzle, look)
		setEmitting(sparks, on)
		smoke.attachment.WorldCFrame = frameAlong(muzzle, UP)
		setEmitting(smoke, on)
		lightAt(light, muzzle, (MAG_LIGHT + MAG_LIGHT_HEAT * share) * (0.7 + 0.3 * flicker) * v)
		return true
	end

	return step, nil
end

return buildMagDump
