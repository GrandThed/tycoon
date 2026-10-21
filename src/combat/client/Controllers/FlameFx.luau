--!strict
-- The Flamethrower's held stream, on every client (docs/prompts/l2-w2-contract.md, L2-29).
-- Display only: damage is the server's, and each tick still reaches FeedbackController as an
-- ordinary `tick` strike (numbers, marker, reactions). This module draws the fire itself.
--
--  * A stream is a continuous family whose shape is not a ray (`IsStream`): the Beam's held ray
--    keeps FeedbackController's beam. One stream per shooter, from the nozzle (HeldWeapons.Muzzle:
--    the tip of the model in the hand, L3-52; with no model, a stud ahead of the hand along the
--    aim) to where the server cut the capsule at the first wall (the strike's `size`), as wide as
--    the capsule.
--  * Someone else's stream follows their strikes and goes out COMBAT_FLAME_LINGER_INTERVALS
--    ticks after the last one. The local player's starts on the frame the shot is sent
--    (InputController's stream handler, the P3.1 lesson: no waiting for the server), lives on
--    those local shots alone (it goes out on release, c-m6) and points along the live shot line
--    (InputController.ShotRay: the crosshair line from the head's depth, where the server's
--    capsule starts), cut at the first wall by the server's rule (InputController.StreamReach);
--    the server's strikes only correct its width.
--  * Look: particles in a widening cone (lifetime x speed = the reach, spread = the capsule's
--    half-width at the far end) over a translucent tapered core Beam. On a low-end device the
--    core alone is drawn, more opaque, with no flicker and no light (spec section 10; never
--    gated on Theme.reducedMotion, which every touch device has). No sound (combat has none).
--
-- FeedbackController owns the wiring (Start, OnStrike, Destroy): it is the one strike listener.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local Create = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Create"))
local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local InputController = require(script.Parent:WaitForChild("InputController"))
local HeldWeapons = require(script.Parent:WaitForChild("HeldWeapons"))

-- What FeedbackController hands over of a strike (its parsed Strike has more).
export type StreamStrike = {
	userId: number,
	weapon: string,
	origin: Vector3,
	direction: Vector3,
	size: number,
	width: number?,
}

type Stream = {
	start: Attachment,
	finish: Attachment,
	core: Beam,
	emitter: ParticleEmitter?,
	light: PointLight?,
	lastAt: number,
	linger: number,
	-- Another shooter's stream is drawn from the server's last word: origin, unit direction,
	-- reach. The local stream reads only `range` (its family's, from the last local shot).
	origin: Vector3,
	aim: Vector3,
	reach: number,
	range: number,
	width: number,
	phase: number,
	-- Last values written to the emitter, so a still stream writes nothing.
	speed: number,
	spread: number,
	endSize: number,
}

-- The engine's own fire texture (bundled, no upload).
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local EPSILON = 1e-4
-- With no model in the hand, the fire leaves this far along the aim from it.
local MUZZLE_FORWARD = 1
-- A write to the emitter only when a value moved more than this share.
local REWRITE_SHARE = 0.05

local FlameFx = {}

local streams: { [number]: Stream } = {}
local connections: { RBXScriptConnection } = {}
local started = false

local function localUserId(): number
	local player = Players.LocalPlayer
	return if player ~= nil then player.UserId else 0
end

-- A continuous family drawn as a stream: anything but a held ray (the Beam keeps its beam).
function FlameFx.IsStream(variant: Types.RangeWeaponVariant?): boolean
	return variant ~= nil and variant.continuous == true and variant.shape ~= "ray"
end

local function unitOf(vector: Vector3): Vector3?
	local length = vector.Magnitude
	if length < EPSILON then
		return nil
	end
	return vector / length
end

-- The nozzle is the model's tip; only the hand fallback is pushed along the aim.
local function muzzleOf(userId: number, aim: Vector3): Vector3?
	local point, fromModel = HeldWeapons.Muzzle(userId)
	if point == nil or fromModel then
		return point
	end
	return point + aim * MUZZLE_FORWARD
end

local function lingerOf(variant: Types.RangeWeaponVariant?): number
	local rate = if variant ~= nil then variant.rate else 0
	local byRate = if rate > 0 then Theme.COMBAT_FLAME_LINGER_INTERVALS / rate else 0
	return math.max(byRate, Theme.COMBAT_FLAME_MIN_LINGER_SECONDS)
end

local function newStream(origin: Vector3, aim: Vector3): Stream
	local start =
		Create("Attachment", { Name = "FlameStart", Parent = Workspace.Terrain }) :: Attachment
	local finish =
		Create("Attachment", { Name = "FlameEnd", Parent = Workspace.Terrain }) :: Attachment
	local lowEnd = Theme.lowEndDevice
	local core = Create("Beam", {
		Name = "FlameCore",
		Attachment0 = start,
		Attachment1 = finish,
		FaceCamera = true,
		LightEmission = 1,
		LightInfluence = 0,
		Segments = 1,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.COMBAT_FLAME_CORE_COLOR),
			ColorSequenceKeypoint.new(0.45, Theme.COMBAT_FLAME_EDGE_COLOR),
			ColorSequenceKeypoint.new(1, Theme.COMBAT_FLAME_TAIL_COLOR),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(
				0,
				if lowEnd
					then Theme.COMBAT_FLAME_CORE_LOW_END_TRANSPARENCY
					else Theme.COMBAT_FLAME_CORE_TRANSPARENCY
			),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Width0 = Theme.COMBAT_FLAME_CORE_START_WIDTH,
		Width1 = Theme.COMBAT_FLAME_DEFAULT_WIDTH,
		Parent = start,
	}) :: Beam
	local emitter: ParticleEmitter? = nil
	local light: PointLight? = nil
	if not lowEnd then
		emitter = Create("ParticleEmitter", {
			Name = "Flame",
			Texture = FIRE_TEXTURE,
			EmissionDirection = Enum.NormalId.Front,
			Rate = Theme.COMBAT_FLAME_PARTICLE_RATE,
			Lifetime = NumberRange.new(
				Theme.COMBAT_FLAME_PARTICLE_LIFETIME * 0.8,
				Theme.COMBAT_FLAME_PARTICLE_LIFETIME
			),
			Speed = NumberRange.new(0),
			LightEmission = 1,
			LightInfluence = 0,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.COMBAT_FLAME_CORE_COLOR),
				ColorSequenceKeypoint.new(0.4, Theme.COMBAT_FLAME_EDGE_COLOR),
				ColorSequenceKeypoint.new(1, Theme.COMBAT_FLAME_TAIL_COLOR),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(0.7, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
			RotSpeed = NumberRange.new(-120, 120),
			Rotation = NumberRange.new(0, 360),
			Enabled = true,
			Parent = start,
		}) :: ParticleEmitter
		light = Create("PointLight", {
			Color = Theme.COMBAT_FLAME_EDGE_COLOR,
			Range = Theme.COMBAT_FLAME_LIGHT_RANGE,
			Brightness = Theme.COMBAT_FLAME_LIGHT_BRIGHTNESS,
			Shadows = false,
			Parent = finish,
		}) :: PointLight
	end
	return {
		start = start,
		finish = finish,
		core = core,
		emitter = emitter,
		light = light,
		lastAt = 0,
		linger = Theme.COMBAT_FLAME_MIN_LINGER_SECONDS,
		origin = origin,
		aim = aim,
		reach = 0,
		range = 0,
		width = Theme.COMBAT_FLAME_DEFAULT_WIDTH,
		-- Two shooters' flames never flicker in step.
		phase = math.random(),
		speed = -1,
		spread = -1,
		endSize = -1,
	}
end

local function destroyStream(userId: number): ()
	local stream = streams[userId]
	if stream == nil then
		return
	end
	streams[userId] = nil
	-- The emitter goes with its attachment; particles already out vanish with it, which at
	-- 0.3 s of lifetime nobody reads as a cut.
	stream.start:Destroy()
	stream.finish:Destroy()
end

local function streamFor(userId: number, origin: Vector3, aim: Vector3): Stream
	local stream = streams[userId]
	if stream == nil then
		stream = newStream(origin, aim)
		streams[userId] = stream
	end
	return stream :: Stream
end

local function moved(previous: number, value: number): boolean
	return math.abs(value - previous) > math.max(math.abs(previous) * REWRITE_SHARE, EPSILON)
end

-- One stream drawn this frame, from `from` along `aim` for `reach`, `width` across at the end.
local function draw(stream: Stream, from: Vector3, aim: Vector3, reach: number, now: number): ()
	local width = stream.width
	local wobble = if Theme.lowEndDevice
		then 1
		else 1 + Theme.COMBAT_FLAME_WOBBLE * math.sin(
			(now + stream.phase) * 2 * math.pi * Theme.COMBAT_FLAME_WOBBLE_HZ
		)
	local tip = from + aim * reach
	stream.start.WorldCFrame = CFrame.lookAt(from, tip)
	stream.finish.WorldPosition = tip
	stream.core.Width1 = width * wobble
	local emitter = stream.emitter
	if emitter ~= nil then
		local lifetime = Theme.COMBAT_FLAME_PARTICLE_LIFETIME
		local speed = reach / lifetime
		if moved(stream.speed, speed) then
			stream.speed = speed
			emitter.Speed = NumberRange.new(speed * 0.85, speed)
		end
		local spread = math.deg(math.atan2(width * 0.5, math.max(reach, EPSILON)))
		if moved(stream.spread, spread) then
			stream.spread = spread
			emitter.SpreadAngle = Vector2.new(spread, spread)
		end
		local endSize = width * Theme.COMBAT_FLAME_PARTICLE_END_SHARE
		if moved(stream.endSize, endSize) then
			stream.endSize = endSize
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, Theme.COMBAT_FLAME_PARTICLE_START_SIZE),
				NumberSequenceKeypoint.new(1, endSize),
			})
		end
	end
end

local function step(): ()
	if next(streams) == nil then
		return
	end
	local now = os.clock()
	local me = localUserId()
	for userId, stream in streams do
		if now - stream.lastAt > stream.linger then
			destroyStream(userId)
			continue
		end
		if userId == me then
			-- Display prediction: the next tick leaves along the shot line, so the local flame
			-- points there now, its tip where the server will cut the capsule.
			local shotFrom, look = InputController.ShotRay()
			if shotFrom == nil or look == nil then
				destroyStream(userId)
				continue
			end
			local tipPoint = shotFrom
				+ look * InputController.StreamReach(shotFrom, look, stream.range)
			local from = muzzleOf(userId, look) or shotFrom
			draw(stream, from, look, math.max((tipPoint - from):Dot(look), 0), now)
		else
			local aim = stream.aim
			local tipPoint = stream.origin + aim * stream.reach
			local from = muzzleOf(userId, aim) or stream.origin
			local toward = unitOf(tipPoint - from) or aim
			draw(stream, from, toward, (tipPoint - from).Magnitude, now)
		end
	end
end

-- A strike of a stream family (FeedbackController checked IsStream). Keeps another shooter's
-- stream alive and moves it to where the server resolved this tick. The local player's own
-- strikes only correct the width (c-m6: arriving a round trip late, they would keep the flame
-- burning after the trigger is released).
function FlameFx.OnStrike(strike: StreamStrike, variant: Types.RangeWeaponVariant?): ()
	if not started then
		return
	end
	if strike.userId == localUserId() then
		local own = streams[strike.userId]
		if own ~= nil and strike.width ~= nil then
			own.width = strike.width
		end
		return
	end
	local aim = unitOf(strike.direction)
	if aim == nil then
		return
	end
	local stream = streamFor(strike.userId, strike.origin, aim)
	stream.lastAt = os.clock()
	stream.linger = lingerOf(variant)
	stream.origin = strike.origin
	stream.aim = aim
	stream.reach = math.max(strike.size, 0)
	stream.width = strike.width
		or (if variant ~= nil then variant.width else nil)
		or Theme.COMBAT_FLAME_DEFAULT_WIDTH
end

-- InputController's stream handler: the local player just sent a shot of a continuous family.
local function onLocalShot(
	_family: string,
	variant: Types.RangeWeaponVariant,
	origin: Vector3,
	direction: Vector3
): ()
	if not FlameFx.IsStream(variant) then
		return
	end
	local aim = unitOf(direction)
	if aim == nil then
		return
	end
	local stream = streamFor(localUserId(), origin, aim)
	stream.lastAt = os.clock()
	stream.linger = lingerOf(variant)
	stream.origin = origin
	stream.aim = aim
	stream.range = variant.range
	stream.width = variant.width or Theme.COMBAT_FLAME_DEFAULT_WIDTH
end

-- Called by FeedbackController.Start in a build that fights with the range's weapons.
function FlameFx.Start(): ()
	if started then
		return
	end
	started = true
	InputController.SetStreamHandler(onLocalShot)
	table.insert(connections, RunService.RenderStepped:Connect(step))
	-- A shooter who leaves mid-stream takes the stream along.
	table.insert(
		connections,
		Players.PlayerRemoving:Connect(function(player: Player)
			destroyStream(player.UserId)
		end)
	)
end

-- Every stream out now (a leave, a cleared set): the next strike starts a fresh one.
function FlameFx.Clear(userId: number?): ()
	if userId ~= nil then
		destroyStream(userId)
		return
	end
	for id in streams do
		destroyStream(id)
	end
end

function FlameFx.Destroy(): ()
	InputController.SetStreamHandler(nil)
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	FlameFx.Clear(nil)
	started = false
end

return FlameFx
