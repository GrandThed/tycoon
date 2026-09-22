--!strict
-- The dust puff that marks street arriving (docs/INTERFACES.md "Wave 1d — Client", appear effect,
-- and "Wave 2a — Tile streets", where a new cell drops in the same way). One pooled emitter per
-- plot, moved along a world-space track; every running burst on the map shares a single Heartbeat,
-- alive only while one runs.
--
-- The numbers here are the look, not tunables: the only thing the config sets is how long a burst
-- takes to cross its track. Baked paths and road tiles both come through here, so a puff reads the
-- same whichever renderer drew the street.

local RunService = game:GetService("RunService")

local PropFactory = require(script.Parent:WaitForChild("PropFactory"))

local DUST_PART_NAME = "PathDust"
-- A built-in texture, so nothing to upload and no id that could be 0.
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local DUST_PART_SIZE = 0.2
local DUST_RATE = 90
local DUST_LIFETIME_MIN = 0.35
local DUST_LIFETIME_MAX = 0.7
local DUST_SPEED_MIN = 1
local DUST_SPEED_MAX = 3
local DUST_RISE = 2 -- studs/s^2 upward: the puff drifts up and fades instead of hanging
local DUST_SIZE_WIDTHS = 0.55 -- of the road width, so a 3-stud trail puffs smaller than asphalt
local DUST_SIZE_GROWTH = 2
local DUST_START_TRANSPARENCY = 0.45
local DUST_SPREAD = 55
local DUST_ROTATION = 180
local DUST_ROTATION_SPEED = 60
-- Samples closer than this are the same point; a track shorter than it puffs in place.
local MIN_TRACK_STEP = 0.05

export type Handle = {
	folder: Instance,
	plotFrame: CFrame,
	width: number, -- the era's road width, which sizes the puff
	-- The furthest two consecutive samples of a track can be and still be the same street: a road
	-- width for a drawn centreline, a cell pitch for tiles.
	gapLimit: number,
	part: Part?,
	emitter: ParticleEmitter?,
	destroyed: boolean,
}

type Burst = {
	handle: Handle,
	points: { Vector3 }, -- world space
	arcs: { number }, -- cumulative length per point
	total: number,
	seconds: number,
	elapsed: number,
}

local bursts: { Burst } = {}
local connection: RBXScriptConnection? = nil

local function stopEmitter(handle: Handle): ()
	local emitter = handle.emitter
	if emitter ~= nil then
		emitter.Enabled = false
	end
end

local function stopConnectionWhenIdle(): ()
	if #bursts > 0 then
		return
	end
	local running = connection
	if running ~= nil then
		running:Disconnect()
		connection = nil
	end
end

local function drop(handle: Handle): ()
	for index = #bursts, 1, -1 do
		if bursts[index].handle == handle then
			table.remove(bursts, index)
		end
	end
	stopEmitter(handle)
	stopConnectionWhenIdle()
end

local function ensureEmitter(handle: Handle): ParticleEmitter
	local existing = handle.emitter
	if existing ~= nil then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = DUST_PART_NAME
	part.Size = Vector3.one * DUST_PART_SIZE
	part.Transparency = 1
	part.CastShadow = false
	part.CFrame = handle.plotFrame
	PropFactory.Seal(part)
	part.Parent = handle.folder
	local size = math.max(handle.width, DUST_PART_SIZE) * DUST_SIZE_WIDTHS
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = DUST_TEXTURE
	emitter.Enabled = false
	emitter.Rate = DUST_RATE
	emitter.Lifetime = NumberRange.new(DUST_LIFETIME_MIN, DUST_LIFETIME_MAX)
	emitter.Speed = NumberRange.new(DUST_SPEED_MIN, DUST_SPEED_MAX)
	emitter.SpreadAngle = Vector2.new(DUST_SPREAD, DUST_SPREAD)
	emitter.Acceleration = Vector3.new(0, DUST_RISE, 0)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, size * DUST_SIZE_GROWTH),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, DUST_START_TRANSPARENCY),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Rotation = NumberRange.new(-DUST_ROTATION, DUST_ROTATION)
	emitter.RotSpeed = NumberRange.new(-DUST_ROTATION_SPEED, DUST_ROTATION_SPEED)
	-- Lit like the ground it kicks up (the default 0 renders full-bright).
	emitter.LightInfluence = 1
	emitter.Parent = part
	handle.part = part
	handle.emitter = emitter
	return emitter
end

local function pointAt(burst: Burst, distance: number): Vector3
	local arcs = burst.arcs
	local points = burst.points
	local target = math.clamp(distance, 0, burst.total)
	local lo, hi = 1, #arcs
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if arcs[mid] <= target then
			lo = mid
		else
			hi = mid
		end
	end
	local span = arcs[hi] - arcs[lo]
	local t = if span < MIN_TRACK_STEP then 0 else (target - arcs[lo]) / span
	return points[lo]:Lerp(points[hi], t)
end

local function step(dt: number): ()
	for index = #bursts, 1, -1 do
		local burst = bursts[index]
		local handle = burst.handle
		local part = handle.part
		if handle.destroyed or part == nil then
			table.remove(bursts, index)
			stopEmitter(handle)
			continue
		end
		burst.elapsed += dt
		local t = if burst.seconds > 0 then math.min(burst.elapsed / burst.seconds, 1) else 1
		part.CFrame = CFrame.new(pointAt(burst, burst.total * t))
		if t >= 1 then
			stopEmitter(handle)
			table.remove(bursts, index)
		end
	end
	stopConnectionWhenIdle()
end

local Dust = {}

-- Lazy: the Part and emitter are only created by the first burst, so a plot that never grows
-- while the player watches costs nothing.
function Dust.Create(folder: Instance, plotFrame: CFrame, width: number, gapLimit: number): Handle
	return {
		folder = folder,
		plotFrame = plotFrame,
		width = width,
		gapLimit = gapLimit,
		part = nil,
		emitter = nil,
		destroyed = false,
	}
end

-- One burst travelling along `points` (world space, in travel order) over `seconds`. Points
-- revealed together are normally one chain running out from the entrance; a jump bigger than the
-- handle's gap limit means they are not (two purchases in one frame), and the track ends there
-- rather than streaking across the plot. A running burst on the same plot is superseded, so a fast
-- buyer never queues seconds of dust.
function Dust.Burst(handle: Handle, points: { Vector3 }, color: Color3, seconds: number): ()
	if handle.destroyed or #points == 0 then
		return
	end
	local gapLimit = math.max(handle.gapLimit, 1)
	local track: { Vector3 } = {}
	local arcs: { number } = {}
	local total = 0
	for _, point in points do
		if #track > 0 then
			local advance = (point - track[#track]).Magnitude
			if advance < MIN_TRACK_STEP then
				continue -- consecutive pieces meet at their join, so the shared point is dropped
			end
			if advance > gapLimit then
				break
			end
			total += advance
		end
		table.insert(track, point)
		table.insert(arcs, total)
	end
	if #track == 0 then
		return
	end
	if #track == 1 then
		-- A single sample has nowhere to travel; repeat it so the burst puffs in place.
		table.insert(track, track[1])
		table.insert(arcs, 0)
	end
	drop(handle)
	local emitter = ensureEmitter(handle)
	local part = handle.part
	if part ~= nil then
		part.CFrame = CFrame.new(track[1])
	end
	-- Per burst, so the puff follows the surface the plot wears right now.
	emitter.Color = ColorSequence.new(color)
	emitter.Enabled = true
	table.insert(bursts, {
		handle = handle,
		points = track,
		arcs = arcs,
		total = total,
		seconds = seconds,
		elapsed = 0,
	})
	if connection == nil then
		connection = RunService.Heartbeat:Connect(step)
	end
end

-- Cuts any burst short (a plot going far mid-puff): the dust, and the Heartbeat behind it, must
-- not run on across a plot nobody is standing on.
function Dust.Stop(handle: Handle): ()
	drop(handle)
end

function Dust.Destroy(handle: Handle): ()
	if handle.destroyed then
		return
	end
	handle.destroyed = true
	drop(handle)
	local part = handle.part
	if part ~= nil then
		part:Destroy()
		handle.part = nil
		handle.emitter = nil
	end
end

return Dust
