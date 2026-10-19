--!strict
-- The frost hammer's swings, on every client (docs/prompts/l2-w3-contract.md, L2-49 and L2-56).
-- Display only: damage and every freeze are the server's (WeaponService, LevelService.React).
--
--  * An ice family (Unlocks.ElementOf: the family's `element` is "ice") draws its swing's hitbox
--    effect in Theme.COMBAT_FROST_HITBOX_COLOR (FeedbackController asks IsIce) and throws a frost
--    puff along the arc: on the press frame for the local player (OnSwing), on the server's
--    strike for everyone else (OnStrike). The puff is particles only, so a low-end device draws
--    none (spec section 10; never gated on Theme.reducedMotion, which every touch device has):
--    the hitbox colour still says ice.
--  * The local player's swing also asks ReactFx for its ghosts of ice (ReactFx.PredictFreeze),
--    with the strike the server will build from it: WorldReact.SwingStrike, the one pure rule
--    WeaponService.resolveMelee builds its strike with (fix round c-m3), on the swing's origin,
--    flat heading and predicted combo step. The ghosts are that swing's (by seq): its answering
--    strike starts their grace (OnAnswered), its refusal takes them (OnRefused).
--
-- FeedbackController owns the wiring (its swing handler, its strike listener, its refusals,
-- Destroy): it is the one strike listener and InputController's one swing handler. No sound
-- (combat has none).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local Types = require(sharedFolder:WaitForChild("Types"))
local Unlocks = require(sharedFolder:WaitForChild("Unlocks"))
local WorldReact = require(sharedFolder:WaitForChild("WorldReact"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local ReactFx = require(script.Parent:WaitForChild("ReactFx"))

-- What OnSwing reads of InputController's PredictedSwing (that module is not required here:
-- FeedbackController hands the swing over).
export type Swing = {
	seq: number,
	family: string,
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	heading: Vector3,
	step: number,
}

-- What OnStrike reads of a strike from the network (FeedbackController's parsed Strike).
export type ResolvedSwing = {
	weapon: string,
	shape: string,
	origin: Vector3,
	direction: Vector3,
	size: number,
	arcDegrees: number?,
}

local ICE: Types.Element = "ice"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local EPSILON = 1e-4

local FrostFx = {}

local state = {
	attachment = nil :: Attachment?,
	emitter = nil :: ParticleEmitter?,
}

-- Whether `weapon` is a family whose element is ice (its swings freeze water).
function FrostFx.IsIce(weapon: string?): boolean
	if weapon == nil then
		return false
	end
	local config = Catalog.GetProvingGroundsConfig()
	return config ~= nil and Unlocks.ElementOf(config.weapons, weapon) == ICE
end

-- One emitter for every puff: moved to each point along the arc and told to emit there.
local function emitter(): (Attachment, ParticleEmitter)
	local attachment, made = state.attachment, state.emitter
	if attachment ~= nil and made ~= nil and attachment.Parent ~= nil then
		return attachment, made
	end
	local holder = Instance.new("Attachment")
	holder.Name = "FrostPuff"
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Frost"
	particles.Texture = SMOKE_TEXTURE
	particles.EmissionDirection = Enum.NormalId.Front
	particles.Color = ColorSequence.new(Theme.COMBAT_FROST_PUFF_COLOR)
	particles.LightEmission = 0.4
	particles.LightInfluence = 0.3
	particles.Size = NumberSequence.new(0.6, 1.8)
	particles.Transparency = NumberSequence.new(0.35, 1)
	particles.Lifetime =
		NumberRange.new(Theme.COMBAT_FROST_PUFF_SECONDS * 0.6, Theme.COMBAT_FROST_PUFF_SECONDS)
	particles.Speed = NumberRange.new(2, 5)
	particles.SpreadAngle = Vector2.new(35, 35)
	particles.Acceleration = Vector3.new(0, -3, 0)
	particles.Drag = 2
	particles.RotSpeed = NumberRange.new(-60, 60)
	particles.Rotation = NumberRange.new(0, 360)
	particles.Rate = 0
	particles.Enabled = false
	particles.Parent = holder
	holder.Parent = Workspace.Terrain
	state.attachment = holder
	state.emitter = particles
	return holder, particles
end

-- A frost puff along an arc swing: COMBAT_FROST_PUFF_POINTS points across the sweep, a share of
-- the reach out and a little under the origin, each throwing mist outward.
local function puff(origin: Vector3, direction: Vector3, range: number, arcDegrees: number?): ()
	if Theme.lowEndDevice then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < EPSILON or not (range > 0) then
		return
	end
	local heading = flat.Unit
	local sweep = math.clamp(arcDegrees or 360, 0, 360)
	local half = math.rad(sweep / 2)
	local points = math.max(Theme.COMBAT_FROST_PUFF_POINTS, 1)
	local reach = range * Theme.COMBAT_FROST_PUFF_REACH_SHARE
	local base = origin - Vector3.new(0, Theme.COMBAT_FROST_PUFF_DROP, 0)
	local attachment, particles = emitter()
	for index = 1, points do
		local share = if points == 1 then 0.5 else (index - 1) / (points - 1)
		local angle = -half + share * 2 * half
		local outward = CFrame.fromAxisAngle(Vector3.yAxis, angle):VectorToWorldSpace(heading)
		local at = base + outward * reach
		attachment.WorldCFrame = CFrame.lookAt(at, at + outward)
		particles:Emit(Theme.COMBAT_FROST_PUFF_PER_POINT)
	end
end

-- The local player's swing, on the frame it was sent (FeedbackController's swing handler).
function FrostFx.OnSwing(swing: Swing): ()
	if not FrostFx.IsIce(swing.family) then
		return
	end
	local strike = WorldReact.SwingStrike(swing.variant, swing.step, swing.origin, swing.heading)
	puff(strike.origin, strike.direction, strike.size, strike.arcDegrees)
	ReactFx.PredictFreeze(strike, swing.seq)
end

-- c-m2: the strike that answers the local player's swing `seq` has come (FeedbackController).
function FrostFx.OnAnswered(seq: number): ()
	ReactFx.AnswerFreeze(seq)
end

-- c-m2: the server refused the local player's attack `seq` (FeedbackController.OnRefused).
function FrostFx.OnRefused(seq: number): ()
	ReactFx.RefuseFreeze(seq)
end

-- Someone else's melee swing, as the server resolved it (FeedbackController's strike listener;
-- the local player's own swing puffed on its press).
function FrostFx.OnStrike(strike: ResolvedSwing): ()
	if strike.shape ~= "arc" or not FrostFx.IsIce(strike.weapon) then
		return
	end
	puff(strike.origin, strike.direction, strike.size, strike.arcDegrees)
end

function FrostFx.Destroy(): ()
	local attachment = state.attachment
	if attachment ~= nil then
		attachment:Destroy()
	end
	state.attachment = nil
	state.emitter = nil
end

return FrostFx
