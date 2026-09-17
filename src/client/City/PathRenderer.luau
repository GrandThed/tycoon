--!strict
-- Draws a plot's ribbon paths (docs/INTERFACES.md "Wave 1c — ribbon paths": "Rendering, per
-- plot, by availability" and "Growth animation"). RoadGraph owns the network and visibility and
-- hands this module the visible spans; PathRibbon turns them into geometry.
--
-- Renderers, best first: `ribbon` (one EditableMesh + MeshPart per layer), `beam` (flat Beams
-- between Attachments on one anchor Part), `parts` (RoadGraph's Wave 1b Parts, reached through
-- the `onParts` callback). Every failure, at creation or any later edit, destroys what this
-- renderer made and drops the plot to the next one silently: nothing is logged, because the
-- mesh APIs legitimately fail in published games without the owner's verification and when the
-- memory budget is exhausted.
--
-- Mesh space: every layer mesh is centred on the plot origin at Y 0. Two tiny bounds triangles
-- pin its extents to +-extent (and +-BOUNDS_HALF_HEIGHT), so the MeshPart's size and centre never
-- change as pieces are added, removed or grown, whichever way the engine derives them.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local PathRibbon = require(script.Parent:WaitForChild("PathRibbon"))
local PropFactory = require(script.Parent:WaitForChild("PropFactory"))

export type Mode = "ribbon" | "beam" | "parts"

local RENDERER_BEAM = "beam"
local RENDERER_PARTS = "parts"
local MESH_PART_NAME = "PathRibbon"
local BEAM_ANCHOR_NAME = "PathBeams"
local ASSET_URI_PREFIX = "rbxassetid://"
-- Bounds triangles: small enough to be invisible, above and below the ribbon plane.
local BOUNDS_HALF_HEIGHT = 0.05
local BOUNDS_TRIANGLE_SIZE = 0.001
-- A cubic Bezier handle of a third of the chord matches a Catmull-Rom span's tangents.
local BEZIER_HANDLE = 1 / 3
local MAX_BEAM_SEGMENTS = 1000 -- Beam.Segments engine ceiling
-- Pieces whose ends differ by less than this are the same end when diffing for growth.
local SAME_END = 0.05
-- Diagnostic for Studio playtests on Workspace/CityDressing/Plot<n>: the renderer in use now.
local RENDERER_ATTRIBUTE = "PathRenderer"

export type Options = {
	folder: Instance,
	plotFrame: CFrame, -- the plot base's top-centre
	eraName: string,
	config: Types.CityDressingConfig,
	ribbon: Types.CityRibbonConfig,
	network: PathRibbon.Network,
	fullTriangles: number, -- the whole potential network's triangles (ownership-independent)
	extent: number, -- PathRibbon.Extent
	color: Color3,
	onParts: () -> (), -- RoadGraph redraws every revealed road with Parts
}

type PieceRecord = {
	piece: PathRibbon.Piece,
	rows: { number },
	vertexIds: { number },
	uvIds: { number },
	faceIds: { number },
	positions: { number },
	uvs: { number },
	scratch: PathRibbon.Scratch?, -- set while the piece grows
}

type Layer = {
	index: number,
	mesh: EditableMesh,
	normalId: number,
	part: MeshPart?,
	creating: boolean,
	records: { [string]: PieceRecord },
}

type BeamRecord = { piece: PathRibbon.Piece, instances: { Instance }, tweens: { Tween } }

export type Handle = {
	mode: Mode,
	options: Options,
	texture: string,
	destroyed: boolean,
	pieces: { PathRibbon.Piece }, -- what should be drawn now
	layers: { [number]: Layer },
	beams: { [string]: BeamRecord },
	anchor: Part?,
}

type GrowthJob = {
	handle: Handle,
	layer: Layer,
	record: PieceRecord,
	growth: PathRibbon.Growth,
	elapsed: number,
}

-- All growing ribbons on the map share one Heartbeat connection, alive only while one grows.
local jobs: { GrowthJob } = {}
local growthConnection: RBXScriptConnection? = nil
-- Set once a mesh API call throws (e.g. a published game whose owner has not enabled the
-- Mesh / Image APIs): every later plot this session starts on beams instead of retrying and
-- staying invisible until its own fallback. A nil from an exhausted memory budget is transient
-- and does not set it.
local meshApisBlocked = false

local function textureUri(eraName: string): string?
	local assets = Catalog.GetAssetsConfig()
	local textures = if assets ~= nil then assets.pathTextures else nil
	local entry = if type(textures) == "table" then textures[eraName] else nil
	local imageId = if type(entry) == "table" then entry.imageId else nil
	if type(imageId) ~= "number" or imageId ~= imageId or imageId <= 0 then
		return nil
	end
	return ASSET_URI_PREFIX .. string.format("%d", imageId)
end

local function layerOf(handle: Handle, piece: PathRibbon.Piece): number
	return handle.options.network.chains[piece.chain].layer
end

-- How a new piece grows from what was drawn on its chain before: from the old end it extends,
-- or (a fresh run) from its end nearer the entrance. Nil when it merges runs or changes both
-- ends, which draws at once rather than moving anything already drawn.
local function growthPlan(old: { PathRibbon.Piece }, piece: PathRibbon.Piece): PathRibbon.Growth?
	local overlapping: { PathRibbon.Piece } = {}
	for _, previous in old do
		if
			previous.chain == piece.chain
			and previous.hi >= piece.lo - SAME_END
			and previous.lo <= piece.hi + SAME_END
		then
			table.insert(overlapping, previous)
		end
	end
	if #overlapping == 0 then
		if piece.distHi <= piece.distLo then
			return { anchor = piece.hi, towardHigh = false, progress = 0 }
		end
		return { anchor = piece.lo, towardHigh = true, progress = 0 }
	end
	if #overlapping ~= 1 then
		return nil
	end
	local previous = overlapping[1]
	if math.abs(previous.lo - piece.lo) < SAME_END and piece.hi > previous.hi + SAME_END then
		return { anchor = previous.hi, towardHigh = true, progress = 0 }
	end
	if math.abs(previous.hi - piece.hi) < SAME_END and piece.lo < previous.lo - SAME_END then
		return { anchor = previous.lo, towardHigh = false, progress = 0 }
	end
	return nil
end

-- ------------------------------------------------------------------ growth loop

local fallback: (handle: Handle) -> ()

local function writeRecord(layer: Layer, record: PieceRecord, scratch: PathRibbon.Scratch): ()
	local mesh = layer.mesh
	local positions, uvs = record.positions, record.uvs
	local vertexIds, uvIds = record.vertexIds, record.uvIds
	for v = PathRibbon.VertexCount(scratch.first - 1), PathRibbon.VertexCount(scratch.last) - 1 do
		mesh:SetPosition(
			vertexIds[v + 1],
			Vector3.new(positions[v * 3 + 1], 0, positions[v * 3 + 3])
		)
		mesh:SetUV(uvIds[v + 1], Vector2.new(uvs[v * 2 + 1], uvs[v * 2 + 2]))
	end
end

-- One growth frame; returns whether the growth has finished. Module-level so the Heartbeat
-- step can pcall it without allocating a closure.
local function stepJob(job: GrowthJob, dt: number): boolean
	local handle = job.handle
	local record = job.record
	local scratch = record.scratch :: PathRibbon.Scratch
	job.elapsed += dt
	local seconds = handle.options.ribbon.growSeconds
	local t = if seconds > 0 then math.min(job.elapsed / seconds, 1) else 1
	-- Ease-out: the path shoots out of the junction and settles at the building.
	job.growth.progress = 1 - (1 - t) ^ 3
	PathRibbon.Fill(
		handle.options.network,
		record.piece,
		record.rows,
		job.growth,
		record.positions,
		record.uvs,
		scratch
	)
	writeRecord(job.layer, record, scratch)
	return t >= 1
end

local function stepGrowth(dt: number): ()
	local failed: { Handle }? = nil
	for index = #jobs, 1, -1 do
		local job = jobs[index]
		local handle = job.handle
		if handle.destroyed or handle.mode ~= "ribbon" then
			table.remove(jobs, index)
			continue
		end
		local ok, finished = pcall(stepJob, job, dt)
		if not ok then
			table.remove(jobs, index)
			local list = failed or {}
			table.insert(list, handle)
			failed = list
		elseif finished then
			job.record.scratch = nil
			table.remove(jobs, index)
		end
	end
	if failed ~= nil then
		for _, handle in failed do
			if not handle.destroyed and handle.mode == "ribbon" then
				fallback(handle)
			end
		end
	end
	if #jobs == 0 then
		local connection = growthConnection
		if connection ~= nil then
			connection:Disconnect()
			growthConnection = nil
		end
	end
end

local function startJob(job: GrowthJob): ()
	table.insert(jobs, job)
	if growthConnection == nil then
		growthConnection = RunService.Heartbeat:Connect(stepGrowth)
	end
end

local function cancelJobs(handle: Handle, record: PieceRecord?): ()
	for index = #jobs, 1, -1 do
		local job = jobs[index]
		if job.handle == handle and (record == nil or job.record == record) then
			table.remove(jobs, index)
		end
	end
	if #jobs == 0 then
		local connection = growthConnection
		if connection ~= nil then
			connection:Disconnect()
			growthConnection = nil
		end
	end
end

-- ------------------------------------------------------------------ ribbon

local function destroyRibbon(handle: Handle): ()
	cancelJobs(handle, nil)
	for _, layer in handle.layers do
		local part = layer.part
		if part ~= nil then
			part:Destroy()
		end
		pcall(function()
			layer.mesh:Destroy()
		end)
	end
	table.clear(handle.layers)
end

local function addBoundsTriangle(
	mesh: EditableMesh,
	normalId: number,
	corner: Vector3,
	inward: number
): ()
	local a = mesh:AddVertex(corner)
	local b = mesh:AddVertex(corner + Vector3.new(0, 0, inward))
	local c = mesh:AddVertex(corner + Vector3.new(inward, 0, 0))
	local face = mesh:AddTriangle(a, b, c)
	local uv = mesh:AddUV(Vector2.zero)
	mesh:SetFaceUVs(face, { uv, uv, uv })
	mesh:SetFaceNormals(face, { normalId, normalId, normalId })
end

local function prepareMesh(mesh: EditableMesh, extent: number): number
	local normalId = mesh:AddNormal(Vector3.yAxis)
	addBoundsTriangle(
		mesh,
		normalId,
		Vector3.new(-extent, BOUNDS_HALF_HEIGHT, -extent),
		BOUNDS_TRIANGLE_SIZE
	)
	addBoundsTriangle(
		mesh,
		normalId,
		Vector3.new(extent, -BOUNDS_HALF_HEIGHT, extent),
		-BOUNDS_TRIANGLE_SIZE
	)
	return normalId
end

local function createLayer(handle: Handle, index: number): Layer
	local ok, created = pcall(function(): EditableMesh
		return AssetService:CreateEditableMesh()
	end)
	if not ok then
		meshApisBlocked = true
		error("EditableMesh unavailable")
	end
	-- The API returns nil when the memory budget is exhausted, despite its declared type.
	local mesh = created :: EditableMesh?
	if mesh == nil then
		error("EditableMesh budget exhausted")
	end
	local editable = mesh :: EditableMesh
	local prepared, normalId = pcall(prepareMesh, editable, handle.options.extent)
	if not prepared then
		-- Not in handle.layers yet, so no teardown would ever reach it.
		pcall(editable.Destroy, editable)
		error("EditableMesh setup failed")
	end
	local layer: Layer = {
		index = index,
		mesh = editable,
		normalId = normalId,
		part = nil,
		creating = false,
		records = {},
	}
	handle.layers[index] = layer
	return layer
end

local function configurePart(handle: Handle, layer: Layer, part: MeshPart): ()
	local options = handle.options
	part.Name = MESH_PART_NAME .. tostring(layer.index)
	part.Material = Enum.Material.SmoothPlastic
	-- Shows through only if the texture's alpha ever reveals the part colour.
	part.Color = options.color
	part.TextureContent = Content.fromUri(handle.texture)
	part.CastShadow = false
	-- DoubleSided stays at its default (false): it is not writable from scripts.
	part.CFrame = options.plotFrame
		* CFrame.new(0, PathRibbon.LayerHeight(options.network, layer.index), 0)
	PropFactory.Seal(part)
	part.Parent = options.folder
end

-- CreateMeshPartAsync yields, so it runs detached; the mesh keeps taking edits meanwhile and the
-- part shows them once it exists.
local function ensurePart(handle: Handle, layer: Layer): ()
	if layer.part ~= nil or layer.creating then
		return
	end
	layer.creating = true
	task.spawn(function()
		local ok, result = pcall(function(): MeshPart
			return AssetService:CreateMeshPartAsync(
				Content.fromObject(layer.mesh),
				{ CollisionFidelity = Enum.CollisionFidelity.Box }
			)
		end)
		if not ok then
			meshApisBlocked = true
		end
		local part = if ok then result :: MeshPart? else nil
		if handle.destroyed or handle.mode ~= "ribbon" or handle.layers[layer.index] ~= layer then
			if part ~= nil then
				part:Destroy()
			end
			return
		end
		layer.creating = false
		if part == nil then
			fallback(handle)
			return
		end
		local created = part :: MeshPart
		if not pcall(configurePart, handle, layer, created) then
			created:Destroy()
			fallback(handle)
			return
		end
		layer.part = created
	end)
end

local function addPiece(
	handle: Handle,
	layer: Layer,
	piece: PathRibbon.Piece,
	growth: PathRibbon.Growth?
): PieceRecord
	local network = handle.options.network
	local rows = PathRibbon.Rows(network, piece)
	local vertexCount = PathRibbon.VertexCount(#rows)
	local record: PieceRecord = {
		piece = piece,
		rows = rows,
		vertexIds = table.create(vertexCount),
		uvIds = table.create(vertexCount),
		faceIds = {},
		positions = table.create(vertexCount * 3),
		uvs = table.create(vertexCount * 2),
		scratch = nil,
	}
	PathRibbon.Fill(network, piece, rows, growth, record.positions, record.uvs)
	local mesh = layer.mesh
	local positions, uvs = record.positions, record.uvs
	for v = 0, vertexCount - 1 do
		record.vertexIds[v + 1] =
			mesh:AddVertex(Vector3.new(positions[v * 3 + 1], 0, positions[v * 3 + 3]))
		record.uvIds[v + 1] = mesh:AddUV(Vector2.new(uvs[v * 2 + 1], uvs[v * 2 + 2]))
	end
	local normalId = layer.normalId
	local indices = PathRibbon.Triangles(#rows)
	for i = 1, #indices, 3 do
		local a, b, c = indices[i], indices[i + 1], indices[i + 2]
		local face = mesh:AddTriangle(record.vertexIds[a], record.vertexIds[b], record.vertexIds[c])
		mesh:SetFaceUVs(face, { record.uvIds[a], record.uvIds[b], record.uvIds[c] })
		mesh:SetFaceNormals(face, { normalId, normalId, normalId })
		table.insert(record.faceIds, face)
	end
	layer.records[piece.key] = record
	return record
end

local function applyRibbon(handle: Handle, pieces: { PathRibbon.Piece }, animate: boolean): ()
	local options = handle.options
	local wanted: { [string]: boolean } = {}
	local triangles = 0
	for _, piece in pieces do
		wanted[piece.key] = true
		triangles += PathRibbon.TriangleCount(#PathRibbon.Rows(options.network, piece))
	end
	local budget = options.config.budget.ribbonTriangles
	if type(budget) == "number" and triangles > budget then
		error("ribbon triangle budget")
	end

	local removed: { PathRibbon.Piece } = {}
	for _, layer in handle.layers do
		local stale: { string } = {}
		for key in layer.records do
			if not wanted[key] then
				table.insert(stale, key)
			end
		end
		table.sort(stale)
		for _, key in stale do
			local record = layer.records[key]
			cancelJobs(handle, record)
			for _, face in record.faceIds do
				layer.mesh:RemoveFace(face)
			end
			layer.records[key] = nil
			table.insert(removed, record.piece)
		end
		if #stale > 0 then
			layer.mesh:RemoveUnused()
		end
	end

	for _, piece in pieces do
		local index = layerOf(handle, piece)
		local layer = handle.layers[index] or createLayer(handle, index)
		if layer.records[piece.key] ~= nil then
			continue
		end
		local growth = if animate then growthPlan(removed, piece) else nil
		local record = addPiece(handle, layer, piece, growth)
		if growth ~= nil then
			record.scratch =
				PathRibbon.NewScratch(handle.options.network, piece, record.rows, growth)
			startJob({
				handle = handle,
				layer = layer,
				record = record,
				growth = growth,
				elapsed = 0,
			})
		end
		ensurePart(handle, layer)
	end
end

-- ------------------------------------------------------------------ beam

local function destroyBeams(handle: Handle): ()
	for _, record in handle.beams do
		for _, tween in record.tweens do
			tween:Cancel()
		end
	end
	table.clear(handle.beams)
	local anchor = handle.anchor
	if anchor ~= nil then
		anchor:Destroy()
		handle.anchor = nil
	end
end

local function ensureAnchor(handle: Handle): Part
	local existing = handle.anchor
	if existing ~= nil then
		return existing
	end
	local anchor = Instance.new("Part")
	anchor.Name = BEAM_ANCHOR_NAME
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.CastShadow = false
	anchor.CFrame = handle.options.plotFrame
	PropFactory.Seal(anchor)
	anchor.Parent = handle.options.folder
	handle.anchor = anchor
	return anchor
end

local function addBeams(
	handle: Handle,
	anchor: Part,
	piece: PathRibbon.Piece,
	growth: PathRibbon.Growth?
): BeamRecord
	local options = handle.options
	local network = options.network
	local ribbon = options.ribbon
	local y = PathRibbon.LayerHeight(network, layerOf(handle, piece))
	local knots = PathRibbon.Knots(network, piece, ribbon.textureLength)
	local record: BeamRecord = { piece = piece, instances = {}, tweens = {} }
	local attachments: { Attachment } = {}
	for _, knot in knots do
		local attachment = Instance.new("Attachment")
		-- Axis (X) along the path so CurveSize bends along it; up (Y) is the beam's face normal,
		-- which lays the width flat on the ground.
		attachment.CFrame = CFrame.fromMatrix(
			Vector3.new(knot.x, y, knot.z),
			Vector3.new(knot.tx, 0, knot.tz),
			Vector3.yAxis
		)
		attachment.Parent = anchor
		table.insert(attachments, attachment)
		table.insert(record.instances, attachment)
	end
	-- Spans on the growing side of the anchor, in reveal order.
	local revealOrder: { [number]: number } = {}
	if growth ~= nil then
		local order: { number } = {}
		for span = 1, #knots - 1 do
			local mid = (knots[span].arc + knots[span + 1].arc) / 2
			if
				(growth.towardHigh and mid > growth.anchor)
				or (not growth.towardHigh and mid < growth.anchor)
			then
				table.insert(order, span)
			end
		end
		if not growth.towardHigh then
			table.sort(order, function(a: number, b: number): boolean
				return a > b
			end)
		end
		for position, span in order do
			revealOrder[span] = position
		end
	end
	local revealCount = 0
	for _ in revealOrder do
		revealCount += 1
	end
	local step = if revealCount > 0 then ribbon.growSeconds / revealCount else 0
	for span = 1, #knots - 1 do
		local from, to = knots[span], knots[span + 1]
		local chord = Vector3.new(to.x - from.x, 0, to.z - from.z).Magnitude
		local beam = Instance.new("Beam")
		beam.Attachment0 = attachments[span]
		beam.Attachment1 = attachments[span + 1]
		beam.FaceCamera = false
		-- Lit like the ground it lies on (the default 0 renders it full-bright).
		beam.LightInfluence = 1
		beam.Texture = handle.texture
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = ribbon.textureLength
		beam.CurveSize0 = chord * BEZIER_HANDLE
		beam.CurveSize1 = chord * BEZIER_HANDLE
		beam.Segments = math.clamp(
			math.ceil(chord / math.max(ribbon.sampleSpacing, 0.05)),
			1,
			MAX_BEAM_SEGMENTS
		)
		-- Higher layers render nearer the camera, so spurs sit on top of lanes.
		beam.ZOffset = layerOf(handle, piece) * ribbon.layerLift
		local order = revealOrder[span]
		if order ~= nil and step > 0 then
			beam.Width0 = 0
			beam.Width1 = 0
			local tween = TweenService:Create(
				beam,
				TweenInfo.new(
					step,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out,
					0,
					false,
					(order - 1) * step
				),
				{ Width0 = from.width, Width1 = to.width }
			)
			tween:Play()
			table.insert(record.tweens, tween)
		else
			beam.Width0 = from.width
			beam.Width1 = to.width
		end
		beam.Parent = anchor
		table.insert(record.instances, beam)
	end
	return record
end

local function applyBeam(handle: Handle, pieces: { PathRibbon.Piece }, animate: boolean): ()
	local wanted: { [string]: boolean } = {}
	for _, piece in pieces do
		wanted[piece.key] = true
	end
	local removed: { PathRibbon.Piece } = {}
	local stale: { string } = {}
	for key in handle.beams do
		if not wanted[key] then
			table.insert(stale, key)
		end
	end
	for _, key in stale do
		local record = handle.beams[key]
		for _, tween in record.tweens do
			tween:Cancel()
		end
		for _, instance in record.instances do
			instance:Destroy()
		end
		handle.beams[key] = nil
		table.insert(removed, record.piece)
	end
	local anchor = ensureAnchor(handle)
	for _, piece in pieces do
		if handle.beams[piece.key] ~= nil then
			continue
		end
		local growth = if animate then growthPlan(removed, piece) else nil
		handle.beams[piece.key] = addBeams(handle, anchor, piece, growth)
	end
end

-- ------------------------------------------------------------------ selection and fallback

local function setMode(handle: Handle, mode: Mode): ()
	handle.mode = mode
	handle.options.folder:SetAttribute(RENDERER_ATTRIBUTE, mode)
end

fallback = function(handle: Handle): ()
	local from = handle.mode
	destroyRibbon(handle)
	destroyBeams(handle)
	if from == "ribbon" then
		setMode(handle, "beam")
		if pcall(applyBeam, handle, handle.pieces, false) then
			return
		end
		destroyBeams(handle)
	end
	setMode(handle, "parts")
	handle.options.onParts()
end

local PathRenderer = {}

-- The renderer a plot starts with. `parts` needs no handle; ribbon eras without a texture, a
-- forced "parts", and eras without `road.ribbon` all land there.
function PathRenderer.Select(options: Options): Mode
	local forced = options.config.road.renderer
	if forced == RENDERER_PARTS or textureUri(options.eraName) == nil then
		return "parts"
	end
	if forced == RENDERER_BEAM then
		return "beam"
	end
	local budget = options.config.budget.ribbonTriangles
	if meshApisBlocked or (type(budget) == "number" and options.fullTriangles > budget) then
		return "beam"
	end
	return "ribbon"
end

-- A handle for a ribbon or beam plot, or nil when the plot draws Parts from the start. Either way
-- the plot folder's PathRenderer attribute names the renderer, and every fallback updates it.
function PathRenderer.Create(options: Options): Handle?
	local mode: Mode = PathRenderer.Select(options)
	local texture = textureUri(options.eraName)
	if mode == "parts" or texture == nil then
		options.folder:SetAttribute(RENDERER_ATTRIBUTE, "parts")
		return nil
	end
	options.folder:SetAttribute(RENDERER_ATTRIBUTE, mode)
	local handle: Handle = {
		mode = mode,
		options = options,
		texture = texture,
		destroyed = false,
		pieces = {},
		layers = {},
		beams = {},
		anchor = nil,
	}
	return handle
end

-- Draws exactly `spans` (the whole visible network, not a delta). `animate` grows every piece
-- that is new since the last call, all at once; the caller passes it only for purchases on near
-- plots, and batches a sync's reveals into one call so they never cancel each other.
function PathRenderer.Update(handle: Handle, spans: { PathRibbon.Span }, animate: boolean): ()
	if handle.destroyed or handle.mode == "parts" then
		return
	end
	local ok, pieces = pcall(PathRibbon.Pieces, handle.options.network, spans)
	if not ok then
		fallback(handle)
		return
	end
	-- Recorded first: a fallback redraws exactly this set.
	handle.pieces = pieces
	local apply = if handle.mode == "ribbon" then applyRibbon else applyBeam
	if not pcall(apply, handle, pieces, animate) then
		fallback(handle)
	end
end

function PathRenderer.Destroy(handle: Handle): ()
	if handle.destroyed then
		return
	end
	handle.destroyed = true
	destroyRibbon(handle)
	destroyBeams(handle)
end

return PathRenderer
