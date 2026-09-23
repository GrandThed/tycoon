--!strict
-- Ambient life (docs/INTERFACES.md "Wave 2c — Ambient"): chimney smoke on the filler houses that
-- have a chimney, and bird flocks circling over the groves. Purely cosmetic and client-side; both
-- are skipped entirely on low-end devices (Theme.lowEndDevice; phones keep them, spec section 10).
--
-- Smoke is one ParticleEmitter on an Attachment inside the house it rises from, so it goes when
-- the house goes and costs no Part and no Heartbeat. Birds are anchored, sealed prop clones moved
-- by one Heartbeat for the whole map, alive only while a bird exists; like Traffic it writes every
-- CFrame into pre-allocated arrays and makes a single BulkMoveTo.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local Scatter = require(script.Parent:WaitForChild("Scatter"))

local SMOKE_ATTACHMENT_NAME = "ChimneySmoke"
-- The same built-in puff the path dust uses (Dust.luau), so nothing needs uploading.
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
-- The look of a chimney plume rather than tunables: a slow column that leans with a faint breeze
-- and thins out as it rises.
local SMOKE_SPEED_MIN = 1
local SMOKE_SPEED_MAX = 2
local SMOKE_SPREAD = 8
local SMOKE_DRIFT = Vector3.new(0.4, 0.3, 0)
local SMOKE_START_TRANSPARENCY = 0.35
local SMOKE_ROTATION_SPEED = 20
-- A flock is a loose group, not a carousel: its birds trail over this much of the circle, sit up to
-- this fraction in or out from it and this many studs above or below it, and rise and fall
-- gently as they fly.
local FLOCK_SPREAD = 1.2 -- radians
local FLOCK_RADIAL_JITTER = 0.2
local FLOCK_HEIGHT_JITTER = 1.5
local BIRD_BOB_HEIGHT = 0.4
local BIRD_BOB_RATE = 2.5 -- radians per second
local FULL_TURN = 2 * math.pi
-- A flock circle smaller than this has no speed to speak of; it hovers instead of spinning.
local MIN_RADIUS = 0.5

type Bird = {
	plotId: number,
	model: Model,
	plotFrame: CFrame,
	center: Vector3, -- plot-local
	radius: number,
	height: number,
	angle: number, -- current angle on the circle
	angularSpeed: number, -- signed radians per second
	bobPhase: number,
	partStart: number,
	partCount: number,
	partOffsets: { CFrame },
	modelParts: { BasePart },
}

local birds: { Bird } = {}
local parts: { BasePart } = {}
local offsets: { CFrame } = {}
local cframes: { CFrame } = {}
local heartbeat: RBXScriptConnection? = nil
local elapsed = 0

local function numberOr(value: any, fallback: number): number
	return if type(value) == "number" and value == value then value else fallback
end

local function colorFor(rgb: any): Color3
	local function channel(index: number): number
		local value = if type(rgb) == "table" then rgb[index] else nil
		return if type(value) == "number" then math.clamp(value, 0, 255) else 255
	end
	return Color3.fromRGB(channel(1), channel(2), channel(3))
end

local function rebuildArrays(): ()
	table.clear(parts)
	table.clear(offsets)
	table.clear(cframes)
	for _, bird in birds do
		bird.partStart = #parts + 1
		bird.partCount = #bird.modelParts
		for index, part in bird.modelParts do
			table.insert(parts, part)
			table.insert(offsets, bird.partOffsets[index])
			table.insert(cframes, part.CFrame)
		end
	end
end

-- The bird's frame in world space: on its circle, nose along the direction of flight (front -Z).
local function birdFrame(bird: Bird): CFrame
	local c, s = math.cos(bird.angle), math.sin(bird.angle)
	local x = bird.center.X + c * bird.radius
	local z = bird.center.Z + s * bird.radius
	local y = bird.height + BIRD_BOB_HEIGHT * math.sin(elapsed * BIRD_BOB_RATE + bird.bobPhase)
	-- Velocity is (-sin, cos) times the sign of the turn; a yaw of atan2(-vx, -vz) faces it.
	local sign = if bird.angularSpeed < 0 then -1 else 1
	local yaw = math.atan2(s * sign, -c * sign)
	local cy, sy = math.cos(yaw), math.sin(yaw)
	return bird.plotFrame * CFrame.new(x, y, z, cy, 0, sy, 0, 1, 0, -sy, 0, cy)
end

-- Forward-declared so a failed BulkMoveTo can prune and the loop can stop itself.
local updateConnection: () -> ()

local function pruneDetached(): ()
	for index = #birds, 1, -1 do
		if not birds[index].model:IsDescendantOf(Workspace) then
			birds[index].model:Destroy()
			table.remove(birds, index)
		end
	end
	rebuildArrays()
	updateConnection()
end

local function step(dt: number): ()
	elapsed += dt
	for _, bird in birds do
		bird.angle = (bird.angle + bird.angularSpeed * dt) % FULL_TURN
		local frame = birdFrame(bird)
		for index = bird.partStart, bird.partStart + bird.partCount - 1 do
			cframes[index] = frame * offsets[index]
		end
	end
	local ok =
		pcall(Workspace.BulkMoveTo, Workspace, parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	if not ok then
		pruneDetached()
	end
end

updateConnection = function(): ()
	if #birds > 0 then
		if heartbeat == nil then
			heartbeat = RunService.Heartbeat:Connect(step)
		end
		return
	end
	local connection = heartbeat
	if connection then
		connection:Disconnect()
		heartbeat = nil
	end
end

local function removeWhere(plotId: number): ()
	local removed = false
	for index = #birds, 1, -1 do
		local bird = birds[index]
		if bird.plotId == plotId then
			bird.model:Destroy()
			table.remove(birds, index)
			removed = true
		end
	end
	if removed then
		rebuildArrays()
		updateConnection()
	end
end

local Ambient = {}

-- Whether ambient life may run at all on this device (smoke and birds alike). Touch alone is
-- not enough to drop it: most players are on phones and it is cheap (one emitter, one BulkMoveTo).
function Ambient.Enabled(): boolean
	return not Theme.lowEndDevice
end

-- One plume at `chimney` (world space) rising from `model`, which it lives inside so it goes when
-- the house does. Nil under reduced motion or when the model has no part to hang it on.
function Ambient.AddSmoke(model: Model, chimney: CFrame, smoke: Types.SmokeConfig): Attachment?
	if not Ambient.Enabled() then
		return nil
	end
	local host = model:FindFirstChildWhichIsA("BasePart", true)
	if host == nil then
		return nil
	end
	local size = if type(smoke.size) == "table" then smoke.size else {}
	local startSize = math.max(numberOr(size[1], 1), 0)
	local endSize = math.max(numberOr(size[2], startSize), 0)
	local lifetime = math.max(numberOr(smoke.lifetime, 0), 0)
	local attachment = Instance.new("Attachment")
	attachment.Name = SMOKE_ATTACHMENT_NAME
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SMOKE_TEXTURE
	emitter.Rate = math.max(numberOr(smoke.rate, 0), 0)
	emitter.Lifetime = NumberRange.new(lifetime)
	emitter.Speed = NumberRange.new(SMOKE_SPEED_MIN, SMOKE_SPEED_MAX)
	emitter.SpreadAngle = Vector2.new(SMOKE_SPREAD, SMOKE_SPREAD)
	emitter.Acceleration = SMOKE_DRIFT
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Color = ColorSequence.new(colorFor(smoke.color))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, startSize),
		NumberSequenceKeypoint.new(1, endSize),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, SMOKE_START_TRANSPARENCY),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.RotSpeed = NumberRange.new(-SMOKE_ROTATION_SPEED, SMOKE_ROTATION_SPEED)
	-- Lit like the roofs it drifts over (the default 0 renders full-bright).
	emitter.LightInfluence = 1
	emitter.Parent = attachment
	-- Upright whatever the house's turn, so the plume always rises.
	attachment.Parent = host
	attachment.WorldCFrame = CFrame.new(chimney.Position)
	return attachment
end

-- Replaces the plot's birds. `models` holds one clone per bird of `flocks` in order (pivoted with
-- their bottom-centre at CFrame.identity, as PropFactory.Spawn(…, CFrame.identity, nil) leaves
-- them); Ambient owns them from here on and destroys any past `mapBirdBudget`, the whole-map cap
-- (CityDressing.json budget.birdsMap), or all of them under reduced motion. Returns how many birds
-- were placed.
function Ambient.SpawnFlocks(
	plotId: number,
	plotFrame: CFrame,
	flocks: { Scatter.Flock },
	config: Types.BirdsConfig,
	models: { Model },
	parent: Instance,
	mapBirdBudget: number
): number
	removeWhere(plotId)
	local room = if Ambient.Enabled() then math.max(mapBirdBudget - #birds, 0) else 0
	local radius = math.max(numberOr(config.radius, 0), 0)
	local speed = numberOr(config.speed, 0)
	local height = numberOr(config.height, 0)
	local placed = 0
	local modelIndex = 0
	for _, flock in flocks do
		for _, draw in flock.birds do
			modelIndex += 1
			local model: Model? = models[modelIndex]
			if model == nil then
				continue
			end
			if placed >= room then
				model:Destroy()
				continue
			end
			local birdRadius = radius * (1 + (draw.radial * 2 - 1) * FLOCK_RADIAL_JITTER)
			local direction = if flock.clockwise then -1 else 1
			local modelParts: { BasePart } = {}
			local partOffsets: { CFrame } = {}
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					table.insert(modelParts, descendant)
					table.insert(partOffsets, descendant.CFrame)
				end
			end
			local bird: Bird = {
				plotId = plotId,
				model = model,
				plotFrame = plotFrame,
				center = flock.center,
				radius = birdRadius,
				height = height + (draw.lift * 2 - 1) * FLOCK_HEIGHT_JITTER,
				-- Trailing the flock's lead bird, against the direction it flies.
				angle = (flock.phase - direction * draw.lead * FLOCK_SPREAD) % FULL_TURN,
				angularSpeed = if birdRadius >= MIN_RADIUS
					then direction * speed / birdRadius
					else 0,
				bobPhase = draw.lift * FULL_TURN,
				partStart = 0,
				partCount = 0,
				partOffsets = partOffsets,
				modelParts = modelParts,
			}
			-- Placed before parenting so the model never flashes at the world origin.
			local frame = birdFrame(bird)
			for partIndex, part in modelParts do
				part.CFrame = frame * partOffsets[partIndex]
			end
			model.Parent = parent
			table.insert(birds, bird)
			placed += 1
		end
	end
	-- Models past the plan (a caller that over-spawned) are ours to clean up too.
	for index = modelIndex + 1, #models do
		models[index]:Destroy()
	end
	rebuildArrays()
	updateConnection()
	return placed
end

-- Birds the whole map can still take under `mapBirdBudget`.
function Ambient.Room(mapBirdBudget: number): number
	return math.max(mapBirdBudget - #birds, 0)
end

function Ambient.ClearPlot(plotId: number): ()
	removeWhere(plotId)
end

function Ambient.Count(plotId: number): number
	local count = 0
	for _, bird in birds do
		if bird.plotId == plotId then
			count += 1
		end
	end
	return count
end

return Ambient
