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
--
-- Wave 1e: the whole plot wears one surface variant, which RoadGraph resolves from the owned
-- slots and pushes through SetSurface. Because the UVs are world-planar, a variant is only a
-- different image on the same meshes, so it costs two writes per live piece and nothing else.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local AssetPreloader =
	require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("AssetPreloader"))
local PropFactory = require(script.Parent:WaitForChild("PropFactory"))
local Dust = require(script.Parent:WaitForChild("Dust"))

export type Mode = "baked" | "parts"

-- Rojo mapping and template shape frozen in docs/INTERFACES.md ("Wave 1d — Pipeline").
local ASSETS_FOLDER = "Assets"
local PATHS_FOLDER = "Paths"
local RIM_PART_NAME = "Rim"
local FILL_PART_NAME = "Fill"
local RENDERER_PARTS = "parts"
-- Diagnostic for Studio playtests on Workspace/CityDressing/Plot<n>: the renderer in use now.
local RENDERER_ATTRIBUTE = "PathRenderer"
local ASSET_PREFIX = "rbxassetid://"

export type Options = {
	folder: Instance,
	plotFrame: CFrame, -- the plot base's top-centre
	eraName: string,
	config: Types.CityDressingConfig,
	near: boolean,
	-- The road colour that tints the dust, read per burst rather than captured: a surface variant
	-- changes it, and cobble must not puff dirt.
	colorOf: () -> Color3,
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
	-- The pooled dust emitter of this plot (docs/INTERFACES.md "Wave 1d"), shared with the tile
	-- renderer's implementation so a new street puffs the same way in every era.
	dust: Dust.Handle,
	-- Wave 1e surface variant; nil is "the texture baked into the templates".
	fillImageId: number?,
	rimImageId: number?,
}

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

-- ------------------------------------------------------------------ surface

-- Ids are up to 15 digits; %d keeps them integral where tostring could print an exponent.
local function contentFor(imageId: number): string
	return ASSET_PREFIX .. string.format("%d", imageId)
end

-- A variant image is not the texture PropFactory's template gate waits on, so a piece cloned just
-- after an upgrade would render untextured for a moment. One waiter per image for the whole map,
-- keyed by the content string: there are a handful of those, unlike the clones wearing them.
local loadedSurfaces: { [string]: boolean } = {}
local waitingSurfaces: { [string]: { BasePart } } = {}

local function gateSurface(part: BasePart, content: string): ()
	if loadedSurfaces[content] then
		return
	end
	local waiting = waitingSurfaces[content]
	local startWaiter = waiting == nil
	if waiting == nil then
		waiting = {}
		waitingSurfaces[content] = waiting
	end
	part.LocalTransparencyModifier = 1
	table.insert(waiting :: { BasePart }, part)
	if not startWaiter then
		return
	end
	task.spawn(function()
		-- The part already carries the image, so waiting on it warms exactly that texture. A
		-- timeout counts as loaded, like a template's: untextured beats invisible.
		AssetPreloader.AwaitInstance(part, Theme.ASSET_LOAD_TIMEOUT_SECONDS)
		loadedSurfaces[content] = true
		local released = waitingSurfaces[content]
		waitingSurfaces[content] = nil
		if released ~= nil then
			for _, hidden in released do
				-- Parts destroyed meanwhile accept the write harmlessly.
				hidden.LocalTransparencyModifier = 0
			end
		end
	end)
end

-- One surface image onto one cloned mesh. A nil id restores the texture the template carries, so
-- dropping back to "default" needs no record of what the baked image was.
local function paint(part: BasePart?, source: BasePart?, imageId: number?): ()
	if part == nil or not part:IsA("MeshPart") then
		return
	end
	local mesh = part :: MeshPart
	if imageId ~= nil and imageId > 0 then
		mesh.TextureID = contentFor(imageId)
	elseif source ~= nil and source:IsA("MeshPart") then
		mesh.TextureID = (source :: MeshPart).TextureID
	end
end

-- Painting a fresh clone also hides it until its image has loaded. A live piece is repainted
-- without the gate: it is already on screen wearing the old surface, and hiding it would blink.
local function paintClone(part: BasePart?, source: BasePart?, imageId: number?): ()
	paint(part, source, imageId)
	if part ~= nil and imageId ~= nil and imageId > 0 then
		gateSurface(part, contentFor(imageId))
	end
end

-- The plot's current variant on one record, from the template part it was cloned from.
local function paintRecord(handle: Handle, record: Record, fresh: boolean): ()
	local apply: (BasePart?, BasePart?, number?) -> () = if fresh then paintClone else paint
	apply(record.fill, partNamed(record.template, FILL_PART_NAME), handle.fillImageId)
	apply(record.rim, partNamed(record.template, RIM_PART_NAME), handle.rimImageId)
end

-- ------------------------------------------------------------------ dust

-- One burst over the whole batch of pieces revealed together, in reveal order (entrance
-- outward), so a purchase reads as one puff running out to the new building. Dust decides where
-- the track breaks and how long it runs.
local function startBurst(handle: Handle, pieceIds: { string }): ()
	local options = handle.options
	local points: { Vector3 } = {}
	for _, pieceId in pieceIds do
		local line = options.centrelineOf(pieceId)
		if line == nil then
			continue
		end
		for _, point in line do
			table.insert(points, options.plotFrame:PointToWorldSpace(point))
		end
	end
	Dust.Burst(handle.dust, points, options.colorOf(), handle.paths.dustSeconds)
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
	destroyPieces(handle)
	-- The plot draws Parts from here on, so its emitter never puffs again.
	Dust.Destroy(handle.dust)
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
	paintClone(rim, source, handle.rimImageId)
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
	-- Before the clone is parented, so a piece arriving on an upgraded plot never shows the
	-- baked surface for a frame.
	paintRecord(handle, record, true)
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
		dust = Dust.Create(options.folder, options.plotFrame, options.width, options.width),
		fillImageId = nil,
		rimImageId = nil,
	}
end

-- The plot's surface variant (docs/INTERFACES.md "Wave 1e — Surfaces"): nil ids mean the texture
-- baked into the templates. Every live Fill/Rim is rewritten and every later clone follows.
function PathRenderer.SetSurface(handle: Handle, fillImageId: number?, rimImageId: number?): ()
	if
		handle.destroyed
		or (handle.fillImageId == fillImageId and handle.rimImageId == rimImageId)
	then
		return
	end
	handle.fillImageId = fillImageId
	handle.rimImageId = rimImageId
	for _, record in handle.records do
		paintRecord(handle, record, false)
	end
end

-- Replays the appear dust over pieces that are already drawn, so a surface upgrade reads as work
-- done on the street rather than a texture popping. Far plots and the Parts renderer stay still.
function PathRenderer.Burst(handle: Handle, pieceIds: { string }): ()
	if handle.destroyed or handle.mode ~= "baked" or not handle.near then
		return
	end
	startBurst(handle, pieceIds)
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
		Dust.Stop(handle.dust)
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
	Dust.Destroy(handle.dust)
	destroyPieces(handle)
end

return PathRenderer
