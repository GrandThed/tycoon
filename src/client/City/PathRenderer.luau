--!strict
-- Draws a plot's paths from the baked meshes (docs/INTERFACES.md "Wave 1d — baked paths":
-- "Client" and "Pieces"). RoadGraph owns the network, the visibility and the piece ids; this
-- module only clones, poses and reveals.
--
-- Two modes: `baked` clones ReplicatedStorage/Assets/Paths/<Era>/<pieceId> per visible piece;
-- `parts` is RoadGraph's own Part renderer, reached through the `onParts` callback. Anything
-- missing -- the Assets.Paths folder, the era folder, one piece's template, the `paths` config,
-- or a forced `road.renderer` of "parts" -- drops the plot to `parts` silently: a path that is
-- not uploaded yet must degrade, never error (M9 principles).
--
-- The templates are generated with each MeshPart already at its plot-local position and carrying
-- the 180 degree Y turn the Open Cloud import applies (tools/pathtest/gen_display.py), so a
-- clone is only lifted onto the plot frame: it must never be turned again here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local PropFactory = require(script.Parent:WaitForChild("PropFactory"))

export type Mode = "baked" | "parts"

-- Rojo mapping and template shape frozen in docs/INTERFACES.md ("Wave 1d — Pipeline").
local ASSETS_FOLDER = "Assets"
local PATHS_FOLDER = "Paths"
local RIM_PART_NAME = "Rim"
local FILL_PART_NAME = "Fill"
local RENDERER_PARTS = "parts"
-- Diagnostic for Studio playtests on Workspace/CityDressing/Plot<n>: the renderer in use now.
local RENDERER_ATTRIBUTE = "PathRenderer"

-- Dust puff (Ben's choice for the appear effect). A built-in texture, so nothing to upload and
-- no id that could be 0. The numbers are the look, not tunables: the only path the config sets
-- is how long a burst takes to cross the piece.
local DUST_PART_NAME = "PathDust"
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
-- A burst shorter than this has no travel worth animating (a stub stretch), so it puffs in place.
local MIN_BURST_LENGTH = 0.05

export type Options = {
	folder: Instance,
	plotFrame: CFrame, -- the plot base's top-centre
	eraName: string,
	config: Types.CityDressingConfig,
	near: boolean,
	color: Color3, -- the era's road colour, which tints the dust
	width: number, -- the era's road width, which sizes the dust
	-- The piece's smoothed centreline in plot-local studs, join end first, for the dust travel.
	centrelineOf: (pieceId: string) -> { Vector3 }?,
	onParts: () -> (), -- RoadGraph redraws every revealed road with Parts
}

type Record = {
	template: Model,
	model: Model,
	-- Parented under `model` while shown; `rim` is nil on a far plot with paths.rimNearOnly, and
	-- `fill` is detached for paths.rimLeadSeconds while a piece appears.
	rim: BasePart?,
	fill: BasePart?,
}

export type Handle = {
	mode: Mode,
	options: Options,
	paths: Types.CityPathsConfig,
	destroyed: boolean,
	near: boolean,
	records: { [string]: Record },
	dustPart: Part?,
	dustEmitter: ParticleEmitter?,
}

-- One burst per plot at a time (the emitter is pooled per plot): a reveal while one runs
-- supersedes it, so a fast buyer never queues seconds of dust.
type Burst = {
	handle: Handle,
	points: { Vector3 }, -- world space
	arcs: { number }, -- cumulative length per point
	total: number,
	elapsed: number,
}

-- Every running burst on the map shares one Heartbeat connection, alive only while one runs.
local bursts: { Burst } = {}
local burstConnection: RBXScriptConnection? = nil

-- ------------------------------------------------------------------ templates

local function eraFolder(eraName: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER)
	local paths = if assets ~= nil then assets:FindFirstChild(PATHS_FOLDER) else nil
	return if paths ~= nil then paths:FindFirstChild(eraName) else nil
end

local function templateFor(eraName: string, pieceId: string): Model?
	local era = eraFolder(eraName)
	local template = if era ~= nil then era:FindFirstChild(pieceId) else nil
	return if template ~= nil and template:IsA("Model") then template :: Model else nil
end

-- A clone's parts already sit at their plot-local CFrames, turned as the importer left them, so
-- an identity pivot turns PivotTo into exactly "lift onto the plot" with no extra rotation.
local function pose(handle: Handle, clone: Model): ()
	clone.WorldPivot = CFrame.identity
	clone:PivotTo(handle.options.plotFrame)
	PropFactory.Seal(clone)
end

local function partNamed(model: Model, name: string): BasePart?
	local child = model:FindFirstChild(name)
	return if child ~= nil and child:IsA("BasePart") then child :: BasePart else nil
end

-- ------------------------------------------------------------------ dust

local function stopDust(handle: Handle): ()
	local emitter = handle.dustEmitter
	if emitter ~= nil then
		emitter.Enabled = false
	end
end

local function dropBursts(handle: Handle): ()
	for index = #bursts, 1, -1 do
		if bursts[index].handle == handle then
			table.remove(bursts, index)
		end
	end
	stopDust(handle)
	if #bursts == 0 then
		local connection = burstConnection
		if connection ~= nil then
			connection:Disconnect()
			burstConnection = nil
		end
	end
end

local function ensureDust(handle: Handle): ParticleEmitter
	local existing = handle.dustEmitter
	if existing ~= nil then
		return existing
	end
	local options = handle.options
	local part = Instance.new("Part")
	part.Name = DUST_PART_NAME
	part.Size = Vector3.one * DUST_PART_SIZE
	part.Transparency = 1
	part.CastShadow = false
	part.CFrame = options.plotFrame
	PropFactory.Seal(part)
	part.Parent = options.folder
	local size = math.max(options.width, DUST_PART_SIZE) * DUST_SIZE_WIDTHS
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = DUST_TEXTURE
	emitter.Enabled = false
	emitter.Rate = DUST_RATE
	emitter.Color = ColorSequence.new(options.color)
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
	handle.dustPart = part
	handle.dustEmitter = emitter
	return emitter
end

local function burstPoint(burst: Burst, distance: number): Vector3
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
	local t = if span < MIN_BURST_LENGTH then 0 else (target - arcs[lo]) / span
	return points[lo]:Lerp(points[hi], t)
end

local function stepBursts(dt: number): ()
	for index = #bursts, 1, -1 do
		local burst = bursts[index]
		local handle = burst.handle
		local part = handle.dustPart
		if handle.destroyed or handle.mode ~= "baked" or part == nil then
			table.remove(bursts, index)
			stopDust(handle)
			continue
		end
		burst.elapsed += dt
		local seconds = handle.paths.dustSeconds
		local t = if seconds > 0 then math.min(burst.elapsed / seconds, 1) else 1
		part.CFrame = CFrame.new(burstPoint(burst, burst.total * t))
		if t >= 1 then
			stopDust(handle)
			table.remove(bursts, index)
		end
	end
	if #bursts == 0 then
		local connection = burstConnection
		if connection ~= nil then
			connection:Disconnect()
			burstConnection = nil
		end
	end
end

-- One burst over the whole batch of pieces revealed together, in reveal order (entrance
-- outward), so a purchase reads as one puff running out to the new building.
local function startBurst(handle: Handle, pieceIds: { string }): ()
	local options = handle.options
	local points: { Vector3 } = {}
	local arcs: { number } = {}
	local total = 0
	-- Pieces revealed together are normally one chain running out from the entrance. A jump
	-- bigger than a road width means they are not (two purchases in one frame), and the burst
	-- ends there rather than streaking across the plot.
	local gapLimit = math.max(options.width, 1)
	for _, pieceId in pieceIds do
		local line = options.centrelineOf(pieceId)
		if line == nil then
			continue
		end
		local broken = false
		for _, point in line do
			local world = options.plotFrame:PointToWorldSpace(point)
			if #points > 0 then
				local step = (world - points[#points]).Magnitude
				if step < MIN_BURST_LENGTH then
					continue -- the pieces meet at their join, so the shared point is dropped
				end
				if step > gapLimit then
					broken = true
					break
				end
				total += step
			end
			table.insert(points, world)
			table.insert(arcs, total)
		end
		if broken then
			break
		end
	end
	if #points == 0 then
		return
	end
	if #points == 1 then
		-- A single sample has nowhere to travel; repeat it so the burst puffs in place.
		table.insert(points, points[1])
		table.insert(arcs, 0)
	end
	for index = #bursts, 1, -1 do
		if bursts[index].handle == handle then
			table.remove(bursts, index)
		end
	end
	local emitter = ensureDust(handle)
	local part = handle.dustPart
	if part ~= nil then
		part.CFrame = CFrame.new(points[1])
	end
	emitter.Enabled = true
	table.insert(bursts, {
		handle = handle,
		points = points,
		arcs = arcs,
		total = total,
		elapsed = 0,
	})
	if burstConnection == nil then
		burstConnection = RunService.Heartbeat:Connect(stepBursts)
	end
end

-- ------------------------------------------------------------------ pieces

local function destroyRecord(record: Record): ()
	local fill = record.fill
	-- Detached mid-appearance: it is not under the model, so Destroy would not reach it.
	if fill ~= nil and fill.Parent == nil then
		fill:Destroy()
	end
	record.model:Destroy()
end

local function destroyPieces(handle: Handle): ()
	for _, record in handle.records do
		destroyRecord(record)
	end
	table.clear(handle.records)
end

local function setMode(handle: Handle, mode: Mode): ()
	handle.mode = mode
	handle.options.folder:SetAttribute(RENDERER_ATTRIBUTE, mode)
end

local function fallback(handle: Handle): ()
	dropBursts(handle)
	destroyPieces(handle)
	local dust = handle.dustPart
	if dust ~= nil then
		dust:Destroy()
		handle.dustPart = nil
		handle.dustEmitter = nil
	end
	setMode(handle, "parts")
	handle.options.onParts()
end

-- Restores a rim dropped while the plot was far, from the template's own plot-local CFrame:
-- the same lift `pose` applies to a whole model, for one part.
local function showRim(handle: Handle, record: Record): ()
	if record.rim ~= nil then
		return
	end
	local source = partNamed(record.template, RIM_PART_NAME)
	if source == nil then
		return
	end
	local rim = source:Clone()
	rim.CFrame = handle.options.plotFrame * source.CFrame
	PropFactory.Seal(rim)
	PropFactory.Gate(record.template, rim)
	rim.Parent = record.model
	record.rim = rim
end

-- Clones one piece. False means its template is missing, which drops the whole plot to Parts:
-- half a path network is worse than a consistent Part one.
local function addPiece(handle: Handle, pieceId: string, animate: boolean): boolean
	local template = templateFor(handle.options.eraName, pieceId)
	if template == nil then
		return false
	end
	local clone = template:Clone()
	-- Hidden until its meshes and textures have loaded, exactly like a building.
	PropFactory.Gate(template, clone)
	pose(handle, clone)
	clone.Name = pieceId
	local record: Record = {
		template = template,
		model = clone,
		rim = partNamed(clone, RIM_PART_NAME),
		fill = partNamed(clone, FILL_PART_NAME),
	}
	local rim = record.rim
	if rim ~= nil and handle.paths.rimNearOnly and not handle.near then
		rim:Destroy()
		record.rim = nil
	end
	local fill = record.fill
	if animate and rim ~= nil and fill ~= nil then
		-- The rim leads the fill by paths.rimLeadSeconds, so the path looks cut before it fills.
		fill.Parent = nil
	end
	clone.Parent = handle.options.folder
	handle.records[pieceId] = record
	return true
end

local function applyBaked(handle: Handle, pieceIds: { string }, animate: boolean): ()
	local wanted: { [string]: boolean } = {}
	for _, pieceId in pieceIds do
		wanted[pieceId] = true
	end
	local stale: { string } = {}
	for pieceId in handle.records do
		if not wanted[pieceId] then
			table.insert(stale, pieceId)
		end
	end
	table.sort(stale)
	for _, pieceId in stale do
		destroyRecord(handle.records[pieceId])
		handle.records[pieceId] = nil
	end

	local revealed: { string } = {}
	local pending: { Record } = {}
	for _, pieceId in pieceIds do
		if handle.records[pieceId] ~= nil then
			continue
		end
		-- Far plots and rebuilds appear instantly; only a purchase on a near plot animates.
		local effect = animate and handle.near
		if not addPiece(handle, pieceId, effect) then
			fallback(handle)
			return
		end
		if effect then
			table.insert(revealed, pieceId)
			local record = handle.records[pieceId]
			if record.fill ~= nil and record.fill.Parent == nil then
				table.insert(pending, record)
			end
		end
	end
	if #pending > 0 then
		-- One timer for the batch: every fill of this reveal lands together.
		task.delay(math.max(handle.paths.rimLeadSeconds, 0), function()
			if handle.destroyed or handle.mode ~= "baked" then
				return
			end
			for _, record in pending do
				local fill = record.fill
				if fill ~= nil and fill.Parent == nil and record.model.Parent ~= nil then
					fill.Parent = record.model
				end
			end
		end)
	end
	if #revealed > 0 then
		startBurst(handle, revealed)
	end
end

-- ------------------------------------------------------------------ public

local PathRenderer = {}

-- The renderer a plot starts with. A forced "parts", a config without `paths`, and a missing
-- template folder (nothing uploaded or harvested yet) all land on Parts.
function PathRenderer.Select(options: Options): Mode
	if options.config.road.renderer == RENDERER_PARTS then
		return "parts"
	end
	if options.config.paths == nil or eraFolder(options.eraName) == nil then
		return "parts"
	end
	return "baked"
end

-- A handle for a baked plot, or nil when the plot draws Parts from the start. Either way the
-- plot folder's PathRenderer attribute names the renderer, and a fallback updates it.
function PathRenderer.Create(options: Options): Handle?
	local paths = options.config.paths
	if PathRenderer.Select(options) == "parts" or paths == nil then
		options.folder:SetAttribute(RENDERER_ATTRIBUTE, "parts")
		return nil
	end
	options.folder:SetAttribute(RENDERER_ATTRIBUTE, "baked")
	return {
		mode = "baked",
		options = options,
		paths = paths,
		destroyed = false,
		near = options.near,
		records = {},
		dustPart = nil,
		dustEmitter = nil,
	}
end

-- Draws exactly `pieceIds` (the whole visible network, not a delta, in reveal order from the
-- entrance outward). `animate` gives every piece new since the last call the appear effect; the
-- caller passes it only for purchases, and batches one sync's reveals into a single call.
function PathRenderer.Update(handle: Handle, pieceIds: { string }, animate: boolean): ()
	if handle.destroyed or handle.mode ~= "baked" then
		return
	end
	applyBaked(handle, pieceIds, animate)
end

-- Far plots drop their rims (half the parts, and the fill is what reads at distance) and get
-- them back when they are near again. Fills and the lane graph are untouched either way.
function PathRenderer.SetNear(handle: Handle, near: boolean): ()
	if handle.destroyed or handle.near == near then
		return
	end
	handle.near = near
	-- A plot that goes far mid-burst stops puffing, whether or not its rims come off: otherwise
	-- the dust (and the Heartbeat behind it) would run on across a plot nobody is standing on.
	if not near then
		dropBursts(handle)
	end
	if handle.mode ~= "baked" or not handle.paths.rimNearOnly then
		return
	end
	local pieceIds: { string } = {}
	for pieceId in handle.records do
		table.insert(pieceIds, pieceId)
	end
	table.sort(pieceIds)
	for _, pieceId in pieceIds do
		local record = handle.records[pieceId]
		if near then
			showRim(handle, record)
		else
			local rim = record.rim
			if rim ~= nil then
				rim:Destroy()
				record.rim = nil
			end
		end
	end
end

function PathRenderer.Destroy(handle: Handle): ()
	if handle.destroyed then
		return
	end
	handle.destroyed = true
	dropBursts(handle)
	destroyPieces(handle)
	local dust = handle.dustPart
	if dust ~= nil then
		dust:Destroy()
		handle.dustPart = nil
		handle.dustEmitter = nil
	end
end

return PathRenderer
