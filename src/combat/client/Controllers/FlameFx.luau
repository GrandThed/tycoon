--!strict
-- The Flamethrower's held stream, on every client (docs/prompts/l2-w2-contract.md, L2-29).
-- Display only: damage is the server's, and each tick still reaches FeedbackController as an
-- ordinary `tick` strike (numbers, marker, reactions). This module draws the fire itself.
--
--  * A stream is a continuous family whose shape is not a ray (`IsStream`): the Beam's held ray
--    keeps FeedbackController's beam. One stream per shooter, from the hand to where the server
--    cut the capsule at the first wall (the strike's `size`), as wide as the capsule.
--  * Someone else's stream follows their strikes and goes out COMBAT_FLAME_LINGER_INTERVALS
--    ticks after the last one. The local player's starts on the frame the shot is sent
--    (InputController's stream handler, the P3.1 lesson: no waiting for the server) and points
--    along the live camera ray, cut at the first wall the way the server cuts it; the server's
--    strikes only keep it alive and correct its width.
--  * Look: particles in a widening cone (lifetime x speed = the reach, spread = the capsule's
--    half-width at the far end) over a translucent tapered core Beam. On a low-end device the
--    core alone is drawn, more opaque, and no light (spec section 10). The core's flicker is off
--    under Theme.reducedMotion. No sound (combat has none).
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
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local InputController = require(script.Parent:WaitForChild("InputController"))

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
	-- The server's last word (others are drawn from it): origin, unit direction, reach.
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
-- The fire leaves this far along the aim from the right hand.
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

local function muzzleOf(userId: number, aim: Vector3): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	local character = if player ~= nil then player.Character else nil
	if character == nil then
		return nil
	end
	local hand = character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("HumanoidRootPart")
	if hand ~= nil and hand:IsA("BasePart") then
		return hand.Position + aim * MUZZLE_FORWARD
	end
	return nil
end

-- What the server's capsule stops at: every player's body and the effect folders are passed
-- through, and so is anything that does not collide (worldReach's rule).
local function wallParams(): RaycastParams
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character ~= nil then
			table.insert(ignore, character)
		end
	end
	local fx = Workspace:FindFirstChild(Theme.COMBAT_RANGE_FX_FOLDER)
	if fx ~= nil then
		table.insert(ignore, fx)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
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
	local wobble = if Theme.reducedMotion
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
	local params: RaycastParams? = nil
	for userId, stream in streams do
		if now - stream.lastAt > stream.linger then
			destroyStream(userId)
			continue
		end
		local aim = stream.aim
		local reach = stream.reach
		if userId == me then
			-- Display prediction: the next tick leaves along the live camera ray, so the local
			-- flame points there now, cut at the first wall up to the family's range.
			local aimOrigin, look = CameraController.GetAimRay()
			aim = look
			local cast = params or wallParams()
			params = cast
			local wall = Workspace:Raycast(aimOrigin, look * stream.range, cast)
			local tipPoint = if wall ~= nil then wall.Position else aimOrigin + look * stream.range
			local from = muzzleOf(userId, look) or stream.origin
			reach = math.max((tipPoint - from):Dot(look), 0)
			draw(stream, from, aim, reach, now)
		else
			local tipPoint = stream.origin + aim * reach
			local from = muzzleOf(userId, aim) or stream.origin
			local toward = unitOf(tipPoint - from) or aim
			draw(stream, from, toward, (tipPoint - from).Magnitude, now)
		end
	end
end

-- A strike of a stream family (FeedbackController checked IsStream). Keeps the shooter's
-- stream alive and moves it to where the server resolved this tick.
function FlameFx.OnStrike(strike: StreamStrike, variant: Types.RangeWeaponVariant?): ()
	if not started then
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
	if variant ~= nil then
		stream.range = math.max(stream.range, variant.range)
	end
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
	if stream.reach <= 0 then
		stream.reach = variant.range
	end
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
