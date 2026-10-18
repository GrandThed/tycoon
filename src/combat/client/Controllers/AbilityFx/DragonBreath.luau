--!strict
-- AbilityFx child: the `dragonBreath` visual (docs/prompts/l2-w2-contract.md, L2-29). The server
-- fires it on the Slug Burst launcher (`count` cones every `tickSeconds` from the muzzle), so it
-- keeps Slug Burst's rhythm: one gout of flame per cone at (k-1) x tickSeconds, filling the cone
-- out to its range, with a muzzle flash, smoke and a light kick. Feedback draws each cone's exact
-- area. Returns its builder; the parent module explains the timing rule and the low-end gate.

local uiFolder = script.Parent.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local Shared = require(script.Parent:WaitForChild("Shared"))
local Pool = require(script.Parent:WaitForChild("Pool"))

type Def = Shared.Def
type Cast = Shared.Cast
type Kit = Shared.Kit
type Step = Shared.Step
type StrikeHook = Shared.StrikeHook
type EmitterStyle = Shared.EmitterStyle

local FRESH_SECONDS = Shared.FRESH_SECONDS
local SMOKE_STYLE = Shared.SMOKE_STYLE
local SMOKE_COLOR = Shared.SMOKE_COLOR
local lerp = Shared.lerp
local clamp01 = Shared.clamp01
local unitOf = Shared.unitOf
local frameAlong = Shared.frameAlong
local positive = Shared.positive
local nonNegative = Shared.nonNegative
local particles = Shared.particles
local muzzleOf = Shared.muzzleOf
local takePart = Pool.takePart
local takeEmitter = Pool.takeEmitter
local emitAt = Pool.emitAt
local takeLight = Pool.takeLight
local lightAt = Pool.lightAt
local show = Pool.show
local layBall = Pool.layBall

type Gout = {
	flash: BasePart,
	startsAt: number,
	fired: boolean,
	muzzle: Vector3,
}

-- The engine's own fire texture (bundled, no upload).
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local BREATH_COLOR = Theme.COMBAT_FLAME_EDGE_COLOR
local BREATH_CORE_COLOR = Theme.COMBAT_FLAME_CORE_COLOR
local BREATH_MAX_GOUTS = 12
local BREATH_LIFETIME = 0.35 -- a gout's flames reach the cone's end in this long
local BREATH_FLAMES = 46
local BREATH_SMOKE = 8
local BREATH_FLASH_SECONDS = 0.16
local BREATH_FLASH_SIZE = 3
local BREATH_FLASH_MIN = 0.4
local BREATH_FLASH_FORWARD = 0.9
-- Share of the cone's half-angle the flames spread over (the rest is the particles' own size).
local BREATH_SPREAD_SHARE = 0.8
local BREATH_END_SIZE = 3.2
local BREATH_LIGHT = 8
local BREATH_LIGHT_RANGE = 18

local function flameStyle(range: number, halfDegrees: number): EmitterStyle
	local speed = range / BREATH_LIFETIME
	return {
		texture = FIRE_TEXTURE,
		lightEmission = 1,
		lightInfluence = 0,
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(1, BREATH_END_SIZE),
		}),
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.7, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		}),
		lifetime = NumberRange.new(BREATH_LIFETIME * 0.75, BREATH_LIFETIME),
		speed = NumberRange.new(speed * 0.8, speed),
		spreadDegrees = halfDegrees * BREATH_SPREAD_SHARE,
		acceleration = Vector3.new(0, 4, 0),
		drag = 0.5,
		rotSpeed = NumberRange.new(-140, 140),
	}
end

local function buildDragonBreath(cast: Cast, def: Def, kit: Kit): (Step?, StrikeHook?)
	local count = positive(def.count)
	local tick = nonNegative(def.tickSeconds)
	local arcDegrees = nonNegative(def.arcDegrees)
	local range = positive(def.range)
	if count == nil or tick == nil or arcDegrees == nil or range == nil then
		return nil, nil
	end
	local gouts = math.min(math.floor(count), BREATH_MAX_GOUTS)
	if gouts < 1 then
		return nil, nil
	end
	local aim = unitOf(cast.direction) or Vector3.zAxis
	local half = math.clamp(arcDegrees, 0, 179) / 2
	local list: { Gout } = {}
	for index = 1, gouts do
		table.insert(list, {
			flash = takePart(kit, Enum.PartType.Ball, BREATH_CORE_COLOR, Enum.Material.Neon),
			startsAt = (index - 1) * tick,
			fired = false,
			muzzle = cast.origin,
		})
	end
	local flames = takeEmitter(kit, flameStyle(range, half), BREATH_COLOR)
	local smoke = takeEmitter(kit, SMOKE_STYLE, SMOKE_COLOR)
	local light = takeLight(kit, BREATH_COLOR, BREATH_LIGHT_RANGE)
	local finish = (gouts - 1) * tick + math.max(BREATH_FLASH_SECONDS, BREATH_LIFETIME)
	local lastMuzzle = cast.origin

	local function step(t: number, _dt: number): boolean
		if t >= finish then
			return false
		end
		local brightest = 0
		for _, gout in list do
			local age = t - gout.startsAt
			if age < 0 then
				continue
			end
			if not gout.fired then
				gout.fired = true
				gout.muzzle = muzzleOf(cast.userId, aim, cast.origin)
				if age < FRESH_SECONDS then
					local frame = frameAlong(gout.muzzle + aim * BREATH_FLASH_FORWARD, aim)
					emitAt(flames, frame, particles(BREATH_FLAMES))
					emitAt(smoke, frame, particles(BREATH_SMOKE))
				end
			end
			lastMuzzle = gout.muzzle
			local u = clamp01(age / BREATH_FLASH_SECONDS)
			layBall(
				gout.flash,
				gout.muzzle + aim * BREATH_FLASH_FORWARD,
				lerp(BREATH_FLASH_SIZE, BREATH_FLASH_MIN, u)
			)
			show(gout.flash, 0, 1 - u)
			brightest = math.max(brightest, 1 - clamp01(age / BREATH_LIFETIME))
		end
		lightAt(light, lastMuzzle + aim * (range * 0.4), BREATH_LIGHT * brightest)
		return true
	end

	return step, nil
end

return buildDragonBreath
