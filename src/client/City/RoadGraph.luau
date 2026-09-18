--!strict
-- Per-plot roads (docs/INTERFACES.md "M9 contracts — Road routing", superseded in part by
-- "Wave 1b — natural paths"). One road network is built from all spine polylines. Each slot gets
-- a spur from its anchor, under the building and across its pad, onto that network. The spine
-- that exists is the union of shortest paths from the entrance (polyline 1, point 1) to every
-- drawn spur's join point. Optional kit junction/bend tiles sit where the geometry is exactly
-- that tile. Near plots in eras with `road.meander` draw a wobbling, width-jittered trail; far
-- plots and other eras draw straight Parts. The lane graph the traffic loop drives on follows
-- the (meandered) centreline of the roads the near rendering draws — vehicles only run on near
-- plots — and never changes on a near/far flip.
--
-- Wave 1d: eras with `road.paths` hand drawing to PathRenderer, which clones the baked path
-- meshes and falls back to the Parts here silently. Those plots have no near/far road rebuild
-- (only their rims come and go); their lanes follow PathRibbon's meandered centreline -- the same
-- curve the bake used -- and trees keep clear of the smoothed centreline of every potential
-- path.
--
-- Everything is computed in plot-local studs (origin at the plot's top-centre, front -Z, Y 0) and
-- placed through the plot frame, so every client derives identical geometry from the layout.
-- The network, the shortest-path tree and every budget decision are fixed once per plot/era
-- from the whole layout, so what appears never depends on purchase order and nothing already
-- drawn ever moves: buying a building only reveals the missing stretches of its path.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local PropFactory = require(script.Parent:WaitForChild("PropFactory"))
local Noise = require(script.Parent:WaitForChild("Noise"))
local PathRibbon = require(script.Parent:WaitForChild("PathRibbon"))
local PathRenderer = require(script.Parent:WaitForChild("PathRenderer"))

local SPINE_PART_NAME = "Road"
local SPUR_PART_NAME = "Spur"
-- Baked piece ids (docs/INTERFACES.md "Wave 1d — Pieces"); tools/paths/bake.py names the meshes
-- from the same numbering, so a client and the bake agree without exchanging anything.
local SPINE_PIECE_FORMAT = "L%d_%d"
local SPUR_PIECE_PREFIX = "SP_"
local SPUR_PIECE_PATTERN = "^SP_(.+)$"
local BEND_PART_NAME = "RoadBend"
-- Points closer than this are the same point; also the shortest leg worth a Part or an edge.
local MIN_LENGTH = 0.05
-- Graph nodes merge on a 1 / NODE_KEY_SCALE stud grid so float noise never splits a corner.
local NODE_KEY_SCALE = 10
-- Consecutive directions whose dot product reaches this are straight, not a bend.
local STRAIGHT_DOT = 0.999
local UP = Vector3.yAxis
local QUARTER_TURN = math.pi / 2
local FULL_TURN = 2 * math.pi
-- Wave 1e: the surface baked into the path templates, and the era road material/colour in Parts.
local DEFAULT_VARIANT = "default"
-- A crossing is a node where this many spine stretches meet; a signal stands in the corner
-- between the two arms with the widest usable gap, which is a real corner and never a road.
local SIGNAL_MIN_ARMS = 3
-- Geometry guards on that corner, not tunables: the corner sits `reach / sin(gap / 2)` from the
-- node, so a gap under 30 degrees would fling it across the plot, and one over 171 has no
-- bisector left to point along (the two arms are the same straight road).
local SIGNAL_GAP_MIN = math.pi / 6
local SIGNAL_GAP_MAX = math.pi * 0.95
-- Kit tile exits at rotY 0 (city-kit-roads, measured by the Boomtown prop-builder): the T
-- junction opens to -X, +X and +Z (straight kerb along -Z); the bend opens to -X and +Z.
local JUNCTION_EXITS = { Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) }
local BEND_EXITS = { Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1) }
-- Connector chains take phase key 97 + their 0-based stretch index (tools/pathmock/pathgeom.py),
-- which is 96 + the 1-based stretch id here.
local CONNECTOR_KEY_BASE = 96

export type Junction = {
	position: Vector3, -- plot-local join point on the spine centreline when `polyline` is set
	direction: Vector3, -- unit XZ, travelling along the spur's last leg toward the spine
	polyline: number?, -- the spine polyline the spur joins; nil when it joins none
	node: number?, -- the network node at `position`; nil when it joins none
	approach: number, -- length of the spur's last section (0 for a zero-leg spur)
}

-- Wave 1e (row lamps): one spine piece's drawn centreline, in polyline order rather than the
-- dust track's join-first order, and the piece id that must be drawn for a post on it to appear.
-- `stretch` is that piece id's ordinal, so posts can be ordered numerically rather than by a
-- string in which "L1_10" sorts before "L1_2".
export type SpinePiece = { pieceId: string, stretch: number, points: { Vector3 } }
-- A continuous run of pieces along one polyline; a piece outside the plan starts a new run.
export type SpineRun = { polyline: number, pieces: { SpinePiece } }
export type StreetLines = { runs: { SpineRun }, spurs: { { Vector3 } } }

-- Wave 1e: the corner of a crossing a signal prop stands on.
export type SignalSpot = { node: number, position: Vector3, yaw: number }

-- Directed lanes, struct-of-arrays so the Heartbeat loop reads numbers without allocating.
-- Positions are world space at the road top, already offset to the right-hand lane.
export type Lanes = {
	count: number,
	to: { number }, -- lane -> node it ends at
	reverse: { number }, -- lane -> the opposite lane of the same road piece
	origin: { Vector3 },
	direction: { Vector3 }, -- unit
	length: { number },
	yaw: { number }, -- CFrame.Angles(0, yaw, 0) faces `direction`
	outgoing: { { number } }, -- node -> lanes starting there
}

export type Context = {
	folder: Instance,
	plotFrame: CFrame, -- the plot base's top-centre
	layout: Types.EraLayout,
	eraName: string,
	seed: number, -- Scatter.Seed(plotIndex, eraName); keys the meander phases
	config: Types.CityDressingConfig,
	era: Types.CityEraDressingConfig,
	-- Called when the roads were redrawn by a different renderer after a silent fallback, so the
	-- lane graph changed without a new spur.
	onRoadsRedrawn: (() -> ())?,
}

-- Smoothed path curves for a layout, shared by every plot of the era (they depend on nothing
-- else), and the same curves tools/paths/bake.py baked the meshes from.
type PathData = {
	era: Types.CityEraDressingConfig,
	network: PathRibbon.Network,
	stretchChains: { [number]: number }, -- stretch id -> chain index
	stretchArcs: { [number]: { number } }, -- stretch id -> final arcs at a and b
	treeLines: { { Vector3 } },
	-- Baked piece id -> its drawn centreline. Memoised here, not per plot: it is a function of
	-- this data alone, so every plot of the era shares one copy.
	pieceCentrelines: { [string]: { Vector3 } },
}

-- The atomic piece of spine: the part of one polyline segment between two network nodes.
type Stretch = {
	a: Vector3,
	b: Vector3,
	fromNode: number,
	toNode: number,
	polyline: number,
	arcStart: number, -- arc length along its polyline at `a`, the meander's input
	length: number,
	group: number, -- the polyline segment (or connector) it belongs to
	ordinal: number, -- its index within its polyline, the second half of the piece id
	pieceId: string, -- baked piece id: "L<polyline>_<stretch within that polyline>"
}

-- A polyline segment, or a short connector from a polyline point onto another polyline.
type Group = { stretches: { number } } -- stretch ids in order from the group's start

type Connector = { from: Vector3, to: Vector3, polyline: number }

type SpurRoute = { points: { Vector3 }, junction: Junction, phases: Noise.Phases }

type PieceSpec = {
	propName: string,
	position: Vector3,
	rotation: CFrame, -- quarter turn about Y lining the tile's exits up with the roads
	node: number,
	-- Junction tiles show once any of these spurs is drawn; empty for bends.
	slotIds: { string },
}

export type State = {
	context: Context,
	width: number,
	thickness: number,
	material: Enum.Material,
	color: Color3,
	laneOffset: number,
	meander: Types.CityMeanderConfig?,
	polylines: { { Vector3 } },
	polylinePhases: { Noise.Phases },
	-- Static network.
	nodes: { Vector3 },
	nodeByKey: { [string]: number },
	stretches: { Stretch },
	groups: { Group },
	nodeStretches: { { number } },
	stretchByPieceId: { [string]: number },
	bendNodes: { number }, -- interior polyline points that turn
	entrance: number?,
	distance: { [number]: number }, -- node -> shortest distance from the entrance
	parent: { [number]: number }, -- node -> stretch leading back toward the entrance
	routes: { [string]: SpurRoute }, -- every routable layout slot
	spurSlotIds: { string }, -- sorted keys of `routes`
	-- Budget plan (straight budget decides what logically exists; the near budget only what the
	-- meandered rendering draws of it).
	groupAllowed: { [number]: boolean },
	spurAllowed: { [string]: boolean },
	nearStretchAllowed: { [number]: boolean },
	nearSpurAllowed: { [string]: boolean },
	nearBendAllowed: { [number]: boolean },
	-- Baked-piece plan: one cloned Model per stretch and per spur, capped by budget.pathPieces.
	pathStretchAllowed: { [number]: boolean },
	pathSpurAllowed: { [string]: boolean },
	pieceKeys: { string },
	pieceSpecs: { [string]: PieceSpec },
	-- Live.
	near: boolean,
	-- Wave 1e: the surface variant the whole plot wears; "" until the base is first applied.
	surfaceVariant: string,
	visible: { [number]: boolean }, -- stretch id -> revealed
	-- Groups that have been revealed. Tracked explicitly because a revealed group may legitimately
	-- draw zero Parts (its stretches outside the near budget), and it must still be redrawn on a
	-- near/far flip.
	revealedGroups: { [number]: boolean },
	spurs: { [string]: SpurRoute }, -- drawn spurs
	groupParts: { [number]: { Instance } },
	spurParts: { [string]: { Instance } },
	bendParts: { Instance },
	pieces: { [string]: Model },
	lanes: Lanes?,
	pathData: PathData?, -- eras with road.paths
	paths: PathRenderer.Handle?, -- nil: Parts from the start
	-- Spurs revealed since the last Flush while PathRenderer draws, and whether any of them
	-- should appear with the dust effect.
	pathsDirty: boolean,
	pathsAnimate: boolean,
	-- Wave 1e: the surface changed and the whole plot owes one puff, started by the same Flush so
	-- it covers the pieces that flush is about to clone as well.
	surfaceBurst: boolean,
}

-- Ranked by network distance from the entrance, ties by index: identical on every client.
type Ranked = { index: number, distance: number }

local function byDistance(a: Ranked, b: Ranked): boolean
	if a.distance == b.distance then
		return a.index < b.index
	end
	return a.distance < b.distance
end

-- The owned set a plot starts from, before any building has replicated (never written to).
local NO_SLOTS_OWNED: { [string]: boolean } = {}

local pathCache: { [Types.EraLayout]: PathData } = {}
local pathPieceIds: (state: State) -> { string }

local materialsByName: { [string]: Enum.Material }? = nil

local function materialOr(name: string, fallback: Enum.Material): Enum.Material
	local lookup = materialsByName
	if lookup == nil then
		local built: { [string]: Enum.Material } = {}
		for _, item in Enum.Material:GetEnumItems() do
			built[item.Name] = item
		end
		lookup = built
		materialsByName = built
	end
	return (lookup :: { [string]: Enum.Material })[name] or fallback
end

local function materialFor(name: string): Enum.Material
	return materialOr(name, Enum.Material.Plastic)
end

local function colorFor(rgb: { number }): Color3
	local function channel(index: number): number
		local value = if type(rgb) == "table" then rgb[index] else nil
		return if type(value) == "number" then math.clamp(value, 0, 255) else 0
	end
	return Color3.fromRGB(channel(1), channel(2), channel(3))
end

local function flat(point: Vector3): Vector3
	return Vector3.new(point.X, 0, point.Z)
end

local function unitOrNil(vector: Vector3): Vector3?
	local magnitude = vector.Magnitude
	if magnitude < MIN_LENGTH then
		return nil
	end
	return vector / magnitude
end

local function keyFor(point: Vector3): string
	return string.format(
		"%d,%d",
		math.round(point.X * NODE_KEY_SCALE),
		math.round(point.Z * NODE_KEY_SCALE)
	)
end

-- rotationY follows the slot convention: 0 faces -Z, positive turns counter-clockwise.
local function facingFor(rotationY: number): Vector3
	local radians = math.rad(rotationY)
	return Vector3.new(-math.sin(radians), 0, -math.cos(radians))
end

-- Budget keys a stale CityDressing.json may not have yet: degrade to `fallback`, never error.
local function budgetValue(value: number?, fallback: number): number
	return if type(value) == "number" and value == value then value else fallback
end

local function destroyAll(instances: { Instance }): ()
	for _, instance in instances do
		instance:Destroy()
	end
	table.clear(instances)
end

local RoadGraph = {}

function RoadGraph.ClosestOnSegment(point: Vector3, a: Vector3, b: Vector3): (Vector3, number)
	local ab = b - a
	local lengthSquared = ab:Dot(ab)
	if lengthSquared < MIN_LENGTH * MIN_LENGTH then
		return a, 0
	end
	local t = math.clamp((point - a):Dot(ab) / lengthSquared, 0, 1)
	return a + ab * t, t
end

-- Layout polylines flattened to Y 0; entries with fewer than two points are ignored.
function RoadGraph.ReadPolylines(layout: Types.EraLayout): { { Vector3 } }
	local polylines: { { Vector3 } } = {}
	local streets = layout.streets
	if type(streets) ~= "table" then
		return polylines
	end
	for _, street in streets :: { Types.StreetLayout } do
		local points = if type(street) == "table" then street.points else nil
		if type(points) == "table" and #points >= 2 then
			local flattened: { Vector3 } = {}
			for _, point in points do
				table.insert(flattened, flat(point))
			end
			table.insert(polylines, flattened)
		end
	end
	return polylines
end

-- Nearest point on any spine polyline segment, with where it lies; nil without a spine.
local function nearestOnSpine(
	point: Vector3,
	polylines: { { Vector3 } },
	skipPolyline: number?,
	aheadOf: Vector3?,
	facing: Vector3?
): (Vector3?, number?, number?, number?, number)
	local bestPoint: Vector3? = nil
	local bestPolyline: number? = nil
	local bestSegment: number? = nil
	local bestT: number? = nil
	local bestDistance = math.huge
	for polylineIndex, points in polylines do
		if polylineIndex == skipPolyline then
			continue
		end
		for index = 2, #points do
			local closest, t = RoadGraph.ClosestOnSegment(point, points[index - 1], points[index])
			local ahead = aheadOf == nil
				or facing == nil
				or (closest - aheadOf):Dot(facing) >= -MIN_LENGTH
			local distance = (closest - point).Magnitude
			if ahead and distance < bestDistance then
				bestPoint, bestPolyline, bestSegment, bestT = closest, polylineIndex, index - 1, t
				bestDistance = distance
			end
		end
	end
	return bestPoint, bestPolyline, bestSegment, bestT, bestDistance
end

-- A slot's spur centreline, before it is attached to the network: the layout's override (with
-- the anchor prepended) or anchor → along the facing until level with the nearest spine point
-- ahead of the pad → perpendicular onto it. Nil for "no spur" (P2 one-point override, or no
-- spine to route to).
local function routePoints(
	layout: Types.EraLayout,
	polylines: { { Vector3 } },
	slotLayout: Types.SlotLayout
): { Vector3 }?
	local override = slotLayout.spur
	if type(override) == "table" and #override == 1 then
		return nil
	end
	local anchor = flat(slotLayout.position)
	local points: { Vector3 } = {}
	if type(override) == "table" and #override >= 2 then
		if (flat(override[1]) - anchor).Magnitude >= MIN_LENGTH then
			table.insert(points, anchor)
		end
		for _, point in override do
			table.insert(points, flat(point))
		end
		return points
	end
	if #polylines == 0 then
		return nil
	end
	local facing = facingFor(slotLayout.rotationY)
	local padCentre = slotLayout.padPosition or slotLayout.position + facing * layout.padOffset
	local padEdge = flat(padCentre + facing * (layout.padSize.Z / 2))
	local target = nearestOnSpine(padEdge, polylines, nil, padEdge, facing)
		or nearestOnSpine(padEdge, polylines, nil, nil, nil)
	if target == nil then
		return nil
	end
	local corner = anchor + facing * (target - anchor):Dot(facing)
	table.insert(points, anchor)
	if (corner - anchor).Magnitude >= MIN_LENGTH then
		table.insert(points, corner)
	end
	if (target - points[#points]).Magnitude >= MIN_LENGTH then
		table.insert(points, target)
	end
	return points
end

-- Centreline points of one straight run, meandered when the era has `road.meander`: cut into
-- pieces of about segmentLength, each cut moved sideways by amplitude * taper * wave(arc).
-- The taper is 0 at both ends (every run ends at a network node, spur corner or spur end), so
-- anything meeting there lines up exactly.
local function centreline(
	state: State,
	a: Vector3,
	b: Vector3,
	arcStart: number,
	phases: Noise.Phases
): ({ Vector3 }, { number })
	local length = (b - a).Magnitude
	local meander = state.meander
	if meander == nil or length < MIN_LENGTH then
		return { a, b }, { arcStart, arcStart + length }
	end
	local count = math.max(1, math.round(length / math.max(meander.segmentLength, MIN_LENGTH)))
	local along = (b - a) / length
	local right = along:Cross(UP)
	local wavelength = math.max(meander.wavelength, MIN_LENGTH)
	local points: { Vector3 } = {}
	local arcs: { number } = {}
	for index = 0, count do
		local u = length * index / count
		local taper = math.clamp(math.min(u, length - u) / state.width, 0, 1)
		local arc = arcStart + u
		local offset = meander.amplitude * taper * Noise.Wave(arc, wavelength, phases[1], phases[2])
		table.insert(points, a + along * u + right * offset)
		table.insert(arcs, arc)
	end
	return points, arcs
end

local function pieceCount(state: State, length: number): number
	local meander = state.meander
	if meander == nil then
		return 1
	end
	return math.max(1, math.round(length / math.max(meander.segmentLength, MIN_LENGTH)))
end

local function slab(
	state: State,
	into: { Instance },
	name: string,
	a: Vector3,
	b: Vector3,
	width: number,
	extension: number
): ()
	local length = (b - a).Magnitude
	if length < MIN_LENGTH then
		return
	end
	local y = state.thickness / 2
	local mid = (a + b) / 2
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(width, state.thickness, length + extension)
	-- Flat, turned about Y only: the top face stays flush at road.thickness everywhere.
	part.CFrame = state.context.plotFrame
		* CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z))
	part.Material = state.material
	part.Color = state.color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	PropFactory.Seal(part)
	part.Parent = state.context.folder
	table.insert(into, part)
end

-- The widest a meandered piece can be (its width is width + widthJitter * wave, wave in [-1, 1]),
-- so a corner disc is never narrower than the pieces it joins.
local function discDiameter(state: State): number
	local meander = state.meander
	if meander == nil then
		return state.width
	end
	return state.width + math.max(meander.widthJitter, 0)
end

-- A flat round disc (a Cylinder stood on end) that rounds a meandered corner.
local function disc(state: State, into: { Instance }, point: Vector3): ()
	local diameter = discDiameter(state)
	local part = Instance.new("Part")
	part.Name = BEND_PART_NAME
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(state.thickness, diameter, diameter)
	part.CFrame = state.context.plotFrame
		* CFrame.new(point.X, state.thickness / 2, point.Z)
		* CFrame.Angles(0, 0, QUARTER_TURN)
	part.Material = state.material
	part.Color = state.color
	part.CastShadow = false
	PropFactory.Seal(part)
	part.Parent = state.context.folder
	table.insert(into, part)
end

local function meanderedNow(state: State): boolean
	return state.meander ~= nil and state.near
end

-- Meandered pieces of one run: width jitters per piece, and pieces overlap by half a width so
-- the joints between slightly turned pieces stay closed.
local function drawMeandered(
	state: State,
	into: { Instance },
	name: string,
	a: Vector3,
	b: Vector3,
	arcStart: number,
	phases: Noise.Phases
): ()
	local meander = state.meander :: Types.CityMeanderConfig
	local wavelength = math.max(meander.wavelength, MIN_LENGTH)
	local points, arcs = centreline(state, a, b, arcStart, phases)
	for index = 2, #points do
		local arc = (arcs[index - 1] + arcs[index]) / 2
		local width = math.max(
			state.width + meander.widthJitter * Noise.Wave(arc, wavelength, phases[3], phases[4]),
			MIN_LENGTH
		)
		slab(state, into, name, points[index - 1], points[index], width, width / 2)
	end
end

local function drawGroup(state: State, groupIndex: number): ()
	local parts = state.groupParts[groupIndex]
	if parts == nil then
		parts = {}
		state.groupParts[groupIndex] = parts
	end
	local into = parts :: { Instance }
	destroyAll(into)
	local group = state.groups[groupIndex]
	if meanderedNow(state) then
		for _, id in group.stretches do
			if state.visible[id] and state.nearStretchAllowed[id] then
				local stretch = state.stretches[id]
				drawMeandered(
					state,
					into,
					SPINE_PART_NAME,
					stretch.a,
					stretch.b,
					stretch.arcStart,
					state.polylinePhases[stretch.polyline]
				)
			end
		end
		return
	end
	-- Straight: one Part per contiguous visible run, overlapping a full width at each end.
	local runStart: Vector3? = nil
	local runEnd: Vector3? = nil
	local function flush(): ()
		if runStart ~= nil and runEnd ~= nil then
			slab(state, into, SPINE_PART_NAME, runStart, runEnd, state.width, state.width)
		end
		runStart, runEnd = nil, nil
	end
	for _, id in group.stretches do
		local stretch = state.stretches[id]
		if state.visible[id] then
			runStart = runStart or stretch.a
			runEnd = stretch.b
		else
			flush()
		end
	end
	flush()
end

local function drawSpur(state: State, slotId: string): ()
	local parts = state.spurParts[slotId]
	if parts == nil then
		parts = {}
		state.spurParts[slotId] = parts
	end
	local into = parts :: { Instance }
	destroyAll(into)
	local route = state.spurs[slotId]
	if route == nil then
		return
	end
	local points = route.points
	if meanderedNow(state) then
		if not state.nearSpurAllowed[slotId] then
			return
		end
		local arc = 0
		for index = 2, #points do
			drawMeandered(
				state,
				into,
				SPUR_PART_NAME,
				points[index - 1],
				points[index],
				arc,
				route.phases
			)
			arc += (points[index] - points[index - 1]).Magnitude
			if index < #points then
				disc(state, into, points[index])
			end
		end
		return
	end
	for index = 2, #points do
		slab(
			state,
			into,
			SPUR_PART_NAME,
			points[index - 1],
			points[index],
			state.width,
			state.width
		)
	end
end

local function nodeSpineVisible(state: State, node: number): boolean
	local stretches = state.nodeStretches[node]
	if stretches == nil or #stretches == 0 then
		return false
	end
	for _, id in stretches do
		if not state.visible[id] then
			return false
		end
	end
	return true
end

local function nodeTouchesVisible(state: State, node: number): boolean
	local stretches: { number } = state.nodeStretches[node] or {}
	for _, id in stretches do
		if state.visible[id] then
			return true
		end
	end
	return false
end

local function drawBends(state: State): ()
	destroyAll(state.bendParts)
	if not meanderedNow(state) then
		return
	end
	for _, node in state.bendNodes do
		-- Every stretch at the node, not just one: a trail that dead-ends at a bend vertex would
		-- otherwise get a disc sticking out past its end.
		if state.nearBendAllowed[node] and nodeSpineVisible(state, node) then
			disc(state, state.bendParts, state.nodes[node])
		end
	end
end

local function refreshPieces(state: State): ()
	local context = state.context
	for _, key in state.pieceKeys do
		local placed: Model? = state.pieces[key]
		if placed ~= nil then
			continue
		end
		local spec = state.pieceSpecs[key]
		-- A tile only where every spine stretch through it is visible.
		if not nodeSpineVisible(state, spec.node) then
			continue
		end
		local due = #spec.slotIds == 0
		for _, slotId in spec.slotIds do
			if state.spurs[slotId] ~= nil then
				due = true
				break
			end
		end
		if not due then
			continue
		end
		-- Retried on every refresh, so a template that replicates late still appears. The tile
		-- sits on top of the road Parts (lifted by road.thickness) so its own asphalt and kerbs
		-- show instead of z-fighting with the plain surface running underneath.
		local model = PropFactory.Spawn(
			context.eraName,
			spec.propName,
			0,
			context.plotFrame
				* CFrame.new(spec.position.X, state.thickness, spec.position.Z)
				* spec.rotation,
			context.folder
		)
		if model ~= nil then
			state.pieces[key] = model
		end
	end
end

-- Unit XZ directions in which roads can ever leave `point`: each spine polyline through it (both
-- ways when it passes through, one way at its end) plus each listed spur arriving there.
local function armsAt(state: State, point: Vector3, slotIds: { string }): { Vector3 }
	local arms: { Vector3 } = {}
	local function addArm(direction: Vector3?): ()
		if direction == nil then
			return
		end
		for _, arm in arms do
			if arm:Dot(direction) >= STRAIGHT_DOT then
				return
			end
		end
		table.insert(arms, direction)
	end
	for _, points in state.polylines do
		for index = 2, #points do
			local a, b = points[index - 1], points[index]
			local closest = RoadGraph.ClosestOnSegment(point, a, b)
			if (closest - point).Magnitude >= MIN_LENGTH then
				continue
			end
			local along = unitOrNil(b - a)
			if along ~= nil and (point - a).Magnitude >= MIN_LENGTH then
				addArm(-along)
			end
			if along ~= nil and (b - point).Magnitude >= MIN_LENGTH then
				addArm(along)
			end
		end
	end
	for _, slotId in slotIds do
		addArm(-state.routes[slotId].junction.direction)
	end
	return arms
end

-- The quarter-turn that lines a kit tile's exits up exactly with the arms meeting at a point,
-- or nil when the geometry is not that tile (a bend with a spur, a 4-way, a diagonal road):
-- skipping beats placing a wrong piece.
local function tileRotation(arms: { Vector3 }, exits: { Vector3 }): CFrame?
	if #arms ~= #exits then
		return nil
	end
	for quarter = 0, 3 do
		local rotation = CFrame.Angles(0, quarter * QUARTER_TURN, 0)
		local matchesAll = true
		for _, exit in exits do
			local rotated = rotation:VectorToWorldSpace(exit)
			local matched = false
			for _, arm in arms do
				if arm:Dot(rotated) >= STRAIGHT_DOT then
					matched = true
					break
				end
			end
			if not matched then
				matchesAll = false
				break
			end
		end
		if matchesAll then
			return rotation
		end
	end
	return nil
end

-- Builds nodes, stretches, groups, spur routes and join points from the layout.
local function buildNetwork(state: State): ()
	local context = state.context
	local layout = context.layout
	local polylines = state.polylines
	local attachRadius = state.width / 2 + MIN_LENGTH

	local function nodeAt(point: Vector3): number
		local key = keyFor(point)
		local id = state.nodeByKey[key]
		if id == nil then
			table.insert(state.nodes, point)
			id = #state.nodes
			state.nodeByKey[key] = id
			state.nodeStretches[id] = {}
		end
		return id
	end
	for _, points in polylines do
		for _, point in points do
			nodeAt(point)
		end
	end

	-- Split parameters per polyline segment, keyed "polyline:segment".
	local splits: { [string]: { number } } = {}
	local function addSplit(polyline: number, segment: number, t: number): ()
		local key = `{polyline}:{segment}`
		local list = splits[key]
		if list == nil then
			list = {}
			splits[key] = list
		end
		table.insert(list :: { number }, t)
	end

	-- Polyline points lying on another polyline join the network there; a point just off the
	-- other line gets a short connector onto it.
	local connectors: { Connector } = {}
	for polylineIndex, points in polylines do
		for _, point in points do
			local closest, otherPolyline, segment, t, distance =
				nearestOnSpine(point, polylines, polylineIndex, nil, nil)
			if closest == nil or distance > attachRadius then
				continue
			end
			addSplit(otherPolyline :: number, segment :: number, t :: number)
			if distance >= MIN_LENGTH then
				table.insert(
					connectors,
					{ from = point, to = closest :: Vector3, polyline = polylineIndex }
				)
			end
		end
	end

	-- Spur routes for every slot (sorted: dictionary order differs between clients), each
	-- attached to the nearest spine within half a width of its end.
	local slotIds: { string } = {}
	for slotId in layout.slots do
		table.insert(slotIds, slotId)
	end
	table.sort(slotIds)
	for _, slotId in slotIds do
		local slotLayout = layout.slots[slotId]
		local points = routePoints(layout, polylines, slotLayout)
		if points == nil then
			continue
		end
		local route = points :: { Vector3 }
		local last = route[#route]
		local closest, polyline, segment, t, distance =
			nearestOnSpine(last, polylines, nil, nil, nil)
		local joins = closest ~= nil and distance <= attachRadius
		if joins then
			addSplit(polyline :: number, segment :: number, t :: number)
			-- The join point is always exactly on the spine, so it keys the same network node.
			if distance >= MIN_LENGTH then
				table.insert(route, closest :: Vector3)
			else
				route[#route] = closest :: Vector3
			end
		end
		local finalPoint = route[#route]
		local direction = if #route >= 2 then unitOrNil(finalPoint - route[#route - 1]) else nil
		state.routes[slotId] = {
			points = route,
			junction = {
				position = finalPoint,
				direction = direction or facingFor(slotLayout.rotationY),
				polyline = if joins then polyline else nil,
				node = nil,
				approach = if #route >= 2 then (finalPoint - route[#route - 1]).Magnitude else 0,
			},
			phases = Noise.Phases(`{context.seed}:slot:{slotId}`),
		}
		table.insert(state.spurSlotIds, slotId)
	end

	local seenPairs: { [string]: boolean } = {}
	local function addStretch(
		group: Group,
		groupIndex: number,
		a: Vector3,
		b: Vector3,
		polyline: number,
		arcStart: number
	): ()
		local length = (b - a).Magnitude
		if length < MIN_LENGTH then
			return
		end
		local fromNode, toNode = nodeAt(a), nodeAt(b)
		local pairKey = if fromNode < toNode then `{fromNode}:{toNode}` else `{toNode}:{fromNode}`
		if fromNode == toNode or seenPairs[pairKey] then
			return
		end
		seenPairs[pairKey] = true
		table.insert(state.stretches, {
			a = a,
			b = b,
			fromNode = fromNode,
			toNode = toNode,
			polyline = polyline,
			arcStart = arcStart,
			length = length,
			group = groupIndex,
			ordinal = 0,
			pieceId = "",
		})
		local id = #state.stretches
		table.insert(group.stretches, id)
		table.insert(state.nodeStretches[fromNode], id)
		table.insert(state.nodeStretches[toNode], id)
	end

	for polylineIndex, points in polylines do
		local arcBase = 0
		for segment = 1, #points - 1 do
			local a, b = points[segment], points[segment + 1]
			local length = (b - a).Magnitude
			local ts: { number } = table.clone(splits[`{polylineIndex}:{segment}`] or {})
			table.insert(ts, 0)
			table.insert(ts, 1)
			table.sort(ts)
			local group: Group = { stretches = {} }
			table.insert(state.groups, group)
			local groupIndex = #state.groups
			for index = 2, #ts do
				addStretch(
					group,
					groupIndex,
					a:Lerp(b, ts[index - 1]),
					a:Lerp(b, ts[index]),
					polylineIndex,
					arcBase + length * ts[index - 1]
				)
			end
			arcBase += length
		end
		for index = 2, #points - 1 do
			local incoming = unitOrNil(points[index] - points[index - 1])
			local outgoing = unitOrNil(points[index + 1] - points[index])
			if incoming ~= nil and outgoing ~= nil and incoming:Dot(outgoing) < STRAIGHT_DOT then
				table.insert(state.bendNodes, nodeAt(points[index]))
			end
		end
	end
	for _, connector in connectors do
		local group: Group = { stretches = {} }
		table.insert(state.groups, group)
		addStretch(group, #state.groups, connector.from, connector.to, connector.polyline, 0)
	end

	-- Baked piece ids: the n-th stretch of a polyline, counted in creation order (segments in
	-- order, then that polyline's connectors), so they are a function of the layout alone.
	local perPolyline: { [number]: number } = {}
	for id, stretch in state.stretches do
		local ordinal = (perPolyline[stretch.polyline] or 0) + 1
		perPolyline[stretch.polyline] = ordinal
		stretch.ordinal = ordinal
		stretch.pieceId = string.format(SPINE_PIECE_FORMAT, stretch.polyline, ordinal)
		state.stretchByPieceId[stretch.pieceId] = id
	end

	for _, slotId in state.spurSlotIds do
		local junction = state.routes[slotId].junction
		if junction.polyline ~= nil then
			junction.node = state.nodeByKey[keyFor(junction.position)]
		end
	end
	if #polylines > 0 then
		state.entrance = state.nodeByKey[keyFor(polylines[1][1])]
	end
end

-- Dijkstra from the entrance. Nodes are numbered in layout order and ties keep the earlier
-- node, so the tree (and every path in it) is identical on every client.
local function buildShortestPaths(state: State): ()
	local entrance = state.entrance
	if entrance == nil then
		return
	end
	state.distance[entrance] = 0
	local done: { [number]: boolean } = {}
	while true do
		local best: number? = nil
		for node = 1, #state.nodes do
			local distance = state.distance[node]
			if
				not done[node]
				and distance ~= nil
				and (best == nil or distance < state.distance[best])
			then
				best = node
			end
		end
		if best == nil then
			break
		end
		local current = best :: number
		done[current] = true
		for _, id in state.nodeStretches[current] do
			local stretch = state.stretches[id]
			local other = if stretch.fromNode == current then stretch.toNode else stretch.fromNode
			local candidate = state.distance[current] + stretch.length
			local known = state.distance[other]
			if known == nil or candidate < known then
				state.distance[other] = candidate
				state.parent[other] = id
			end
		end
	end
end

local function stretchNearDistance(state: State, id: number): number?
	local stretch = state.stretches[id]
	local a, b = state.distance[stretch.fromNode], state.distance[stretch.toNode]
	if a == nil or b == nil then
		return nil
	end
	return math.min(a, b)
end

-- The spine the paths can ever cover: the union of the shortest paths from the entrance to every
-- routable spur's join node (Wave 1b's growth rule), ranked from the entrance outward. The bake
-- emits a piece for exactly this union (tools/paths/network.py `visible_stretches`), so the baked
-- budget is spent over it and nothing else, and the two sides cannot drift into asking for a piece
-- that was never baked.
local function pathStretchOrder(state: State): { Ranked }
	local order: { Ranked } = {}
	local seen: { [number]: boolean } = {}
	for _, slotId in state.spurSlotIds do
		local node = state.routes[slotId].junction.node
		if node == nil or state.distance[node] == nil then
			continue
		end
		local current = node
		while current ~= state.entrance do
			local id = state.parent[current]
			if id == nil or seen[id] then
				break -- the rest of the way back to the entrance is in the union already
			end
			seen[id] = true
			local stretch = state.stretches[id]
			local distance = stretchNearDistance(state, id)
			-- A stretch whose group missed the straight budget can never be revealed (`reveal`
			-- stops there), so it must not hold a baked slot either.
			if distance ~= nil and state.groupAllowed[stretch.group] then
				table.insert(order, { index = id, distance = distance })
			end
			current = if stretch.fromNode == current then stretch.toNode else stretch.fromNode
		end
	end
	table.sort(order, byDistance)
	return order
end

-- Budget plan for the whole layout. Straight budget (budget.roadPieces) decides what exists:
-- spine groups nearest the entrance first (a group is 1 Part, or 2 when its visible part can be
-- reached from both ends), then spurs by sorted slot id, then bends, then junction tiles. The
-- near budget (budget.roadPiecesNear) decides which of those the meandered rendering draws:
-- stretches nearest the entrance, then spurs, then bend discs. Both walk the shortest-path tree
-- outward and stop at the first spine piece that does not fit, so a drawn path never has a gap.
local function allocate(state: State): ()
	local context = state.context
	local budget = context.config.budget
	local road = context.era.road

	-- Silent degradation (M9 principles): a stale config file that predates a budget key must
	-- fall back, never hit nil arithmetic. A v1 file has no `roadPiecesNear`.
	local straightBudget = budgetValue(budget.roadPieces, 0)
	local remaining = straightBudget
	local groupOrder: { Ranked } = {}
	for groupIndex, group in state.groups do
		local nearest: number? = nil
		for _, id in group.stretches do
			local distance = stretchNearDistance(state, id)
			if distance ~= nil and (nearest == nil or distance < nearest) then
				nearest = distance
			end
		end
		if nearest ~= nil then
			table.insert(groupOrder, { index = groupIndex, distance = nearest })
		end
	end
	table.sort(groupOrder, byDistance)
	for _, ranked in groupOrder do
		local towardStart, towardEnd = false, false
		for _, id in state.groups[ranked.index].stretches do
			local stretch = state.stretches[id]
			local a, b = state.distance[stretch.fromNode], state.distance[stretch.toNode]
			if a ~= nil and b ~= nil then
				if a <= b then
					towardStart = true
				else
					towardEnd = true
				end
			end
		end
		local cost = if towardStart and towardEnd then 2 else 1
		if cost > remaining then
			break
		end
		state.groupAllowed[ranked.index] = true
		remaining -= cost
	end
	for _, slotId in state.spurSlotIds do
		local legs = math.max(#state.routes[slotId].points - 1, 0)
		if legs <= remaining then
			state.spurAllowed[slotId] = true
			remaining -= legs
		end
	end

	-- Spur-to-spine meeting nodes, each with the spurs arriving there (sorted slot order).
	local junctionNodes: { number } = {}
	local junctionSlots: { [number]: { string } } = {}
	for _, slotId in state.spurSlotIds do
		local node = state.routes[slotId].junction.node
		if not state.spurAllowed[slotId] or node == nil then
			continue
		end
		local slots = junctionSlots[node]
		if slots == nil then
			slots = {}
			junctionSlots[node] = slots
			table.insert(junctionNodes, node)
		end
		table.insert(slots :: { string }, slotId)
	end
	local function addPiece(
		node: number,
		propName: string,
		rotation: CFrame,
		slotIds: { string }
	): ()
		local key = keyFor(state.nodes[node])
		state.pieceSpecs[key] = {
			propName = propName,
			position = state.nodes[node],
			rotation = rotation,
			node = node,
			slotIds = slotIds,
		}
		table.insert(state.pieceKeys, key)
		remaining -= 1
	end
	local bendProp = road.bendProp
	if bendProp ~= nil then
		for _, node in state.bendNodes do
			local key = keyFor(state.nodes[node])
			if remaining <= 0 or junctionSlots[node] ~= nil or state.pieceSpecs[key] ~= nil then
				continue
			end
			local rotation = tileRotation(armsAt(state, state.nodes[node], {}), BEND_EXITS)
			if rotation ~= nil then
				addPiece(node, bendProp, rotation, {})
			end
		end
	end
	local junctionProp = road.junctionProp
	if junctionProp ~= nil then
		for _, node in junctionNodes do
			local key = keyFor(state.nodes[node])
			if remaining <= 0 or state.pieceSpecs[key] ~= nil then
				continue
			end
			local slotIds = junctionSlots[node]
			local rotation = tileRotation(armsAt(state, state.nodes[node], slotIds), JUNCTION_EXITS)
			if rotation ~= nil then
				addPiece(node, junctionProp, rotation, slotIds)
			end
		end
	end

	-- Baked pieces: one cloned Model per stretch of the path union and per drawn spur, spent
	-- nearest the entrance first (then spurs in sorted slot order) so an overrun never leaves a
	-- gap in the middle of a path. Decided from the layout, never from what is owned.
	if road.paths ~= nil then
		local pathRemaining = budgetValue(budget.pathPieces, straightBudget)
		for _, ranked in pathStretchOrder(state) do
			if pathRemaining <= 0 then
				break
			end
			state.pathStretchAllowed[ranked.index] = true
			pathRemaining -= 1
		end
		for _, slotId in state.spurSlotIds do
			if state.spurAllowed[slotId] and pathRemaining > 0 then
				state.pathSpurAllowed[slotId] = true
				pathRemaining -= 1
			end
		end
	end

	if state.meander == nil then
		return
	end
	local nearRemaining = budgetValue(budget.roadPiecesNear, straightBudget)
	local stretchOrder: { Ranked } = {}
	for id, stretch in state.stretches do
		local distance = stretchNearDistance(state, id)
		if distance ~= nil and state.groupAllowed[stretch.group] then
			table.insert(stretchOrder, { index = id, distance = distance })
		end
	end
	table.sort(stretchOrder, byDistance)
	for _, ranked in stretchOrder do
		local cost = pieceCount(state, state.stretches[ranked.index].length)
		if cost > nearRemaining then
			break
		end
		state.nearStretchAllowed[ranked.index] = true
		nearRemaining -= cost
	end
	for _, slotId in state.spurSlotIds do
		if not state.spurAllowed[slotId] then
			continue
		end
		local points = state.routes[slotId].points
		local cost = math.max(#points - 2, 0) -- corner discs
		for index = 2, #points do
			cost += pieceCount(state, (points[index] - points[index - 1]).Magnitude)
		end
		if cost <= nearRemaining then
			state.nearSpurAllowed[slotId] = true
			nearRemaining -= cost
		end
	end
	for _, node in state.bendNodes do
		if nearRemaining <= 0 then
			break
		end
		state.nearBendAllowed[node] = true
		nearRemaining -= 1
	end
end

local function toPoints(points: { Vector3 }): { PathRibbon.Point }
	local out: { PathRibbon.Point } = {}
	for _, point in points do
		table.insert(out, { point.X, point.Z })
	end
	return out
end

-- Every visible stretch and drawn spur as a baked piece id, in reveal order from the entrance
-- outward: the order the renderer clones them in and a dust burst runs along them.
pathPieceIds = function(state: State): { string }
	local ids: { string } = {}
	local data = state.pathData
	if data == nil then
		return ids
	end
	local ranked: { Ranked } = {}
	for id in state.stretches do
		if state.visible[id] and state.pathStretchAllowed[id] then
			table.insert(ranked, {
				index = id,
				distance = stretchNearDistance(state, id) or math.huge,
			})
		end
	end
	table.sort(ranked, byDistance)
	for _, item in ranked do
		table.insert(ids, state.stretches[item.index].pieceId)
	end
	for _, slotId in state.spurSlotIds do
		-- Only a spur that kept a chain: PathRibbon.Build drops a route that collapses to one
		-- point, exactly as the bake does, so no mesh was ever baked for it. Asking for that
		-- template would fail and drop the whole plot to Parts.
		if
			state.spurs[slotId] ~= nil
			and state.pathSpurAllowed[slotId]
			and data.network.spurChains[slotId] ~= nil
		then
			table.insert(ids, SPUR_PIECE_PREFIX .. slotId)
		end
	end
	return ids
end

-- A baked piece's drawn (meandered) centreline in plot-local studs, join end first: a spur runs
-- from the spine back under its building, a spine stretch from its end nearer the entrance.
-- Memoised on the PathData, which every plot of the era shares; only the dust effect asks for it.
local function pieceCentreline(state: State, pieceId: string): { Vector3 }?
	local data = state.pathData
	if data == nil then
		return nil
	end
	local cached = data.pieceCentrelines[pieceId]
	if cached ~= nil then
		return cached
	end
	local network = data.network
	local chain: number?
	local from, to = 0, 0
	local slotId = string.match(pieceId, SPUR_PIECE_PATTERN)
	if slotId ~= nil then
		chain = network.spurChains[slotId]
		if chain ~= nil then
			local lo, hi = PathRibbon.FullSpan(network, chain)
			from, to = hi, lo
		end
	else
		local id = state.stretchByPieceId[pieceId]
		local stretch = if id ~= nil then state.stretches[id] else nil
		local arcs = if id ~= nil then data.stretchArcs[id] else nil
		if stretch ~= nil and arcs ~= nil then
			chain = data.stretchChains[id]
			local atFrom = state.distance[stretch.fromNode] or math.huge
			local atTo = state.distance[stretch.toNode] or math.huge
			if atFrom <= atTo then
				from, to = arcs[1], arcs[2]
			else
				from, to = arcs[2], arcs[1]
			end
		end
	end
	if chain == nil then
		return nil
	end
	local points: { Vector3 } = {}
	for _, point in PathRibbon.Centreline(network, chain, from, to, state.width) do
		table.insert(points, Vector3.new(point[1], 0, point[2]))
	end
	data.pieceCentrelines[pieceId] = points
	return points
end

-- Smooths the whole potential network once per layout, whatever is owned, exactly as the bake
-- did, and maps every stretch onto its chain and arc range.
local function pathDataFor(state: State): PathData
	local context = state.context
	local cached = pathCache[context.layout]
	if cached ~= nil and cached.era == context.era then
		return cached
	end
	local segmentGroups = 0
	for _, points in state.polylines do
		segmentGroups += #points - 1
	end
	local polylines: { { PathRibbon.Point } } = {}
	for _, points in state.polylines do
		table.insert(polylines, toPoints(points))
	end
	local connectors: { PathRibbon.ConnectorInput } = {}
	for id, stretch in state.stretches do
		if stretch.group > segmentGroups then
			table.insert(connectors, {
				key = CONNECTOR_KEY_BASE + id,
				from = { stretch.a.X, stretch.a.Z },
				to = { stretch.b.X, stretch.b.Z },
			})
		end
	end
	local spurs: { PathRibbon.SpurInput } = {}
	for _, slotId in state.spurSlotIds do
		table.insert(spurs, { id = slotId, points = toPoints(state.routes[slotId].points) })
	end
	local meander = context.era.road.meander
	local network = PathRibbon.Build({
		width = state.width,
		meander = if meander ~= nil
			then { amplitude = meander.amplitude, wavelength = meander.wavelength }
			else nil,
		polylines = polylines,
		connectors = connectors,
		spurs = spurs,
	})

	local data: PathData = {
		era = context.era,
		network = network,
		stretchChains = {},
		stretchArcs = {},
		treeLines = {},
		pieceCentrelines = {},
	}
	for id, stretch in state.stretches do
		local connector = stretch.group > segmentGroups
		local chain = if connector
			then network.connectorChains[CONNECTOR_KEY_BASE + id]
			else network.polylineChains[stretch.polyline]
		if chain == nil then
			continue
		end
		local arcs: { number }
		if connector then
			-- A connector chain is the stretch itself, so its whole span is the piece; the bake
			-- lands on the same two numbers (verified to 3e-14 over both eras).
			local lo, hi = PathRibbon.FullSpan(network, chain)
			arcs = { lo, hi }
		else
			-- Projected, never forced onto the chain's ends. tools/paths/network.py `arc_at`
			-- projects too, and a polyline end that hosts a join has been snapped and re-splined:
			-- forcing it put Village L3_1 1.86 studs off the baked piece, which the dust burst and
			-- the lane a cart turns onto would both have shown.
			arcs = {
				PathRibbon.ArcAt(network, chain, stretch.a.X, stretch.a.Z),
				PathRibbon.ArcAt(network, chain, stretch.b.X, stretch.b.Z),
			}
		end
		data.stretchChains[id] = chain
		data.stretchArcs[id] = arcs
	end
	-- Sampled about a road width apart: on the tightest fillet (radius CORNER_RADIUS_WIDTHS *
	-- width) the chord strays well under the clearance margin, and it is a fraction of what the
	-- baked mesh holds.
	for _, line in PathRibbon.SmoothedCentrelines(network, state.width) do
		local points: { Vector3 } = {}
		for _, point in line do
			table.insert(points, Vector3.new(point[1], 0, point[2]))
		end
		table.insert(data.treeLines, points)
	end
	pathCache[context.layout] = data
	return data
end

-- ------------------------------------------------------------------ surface (wave 1e)

-- The uploaded images per variant name for this era, or nil while none are uploaded.
local function eraVariantImages(state: State): { [string]: Types.AssetPathVariant }?
	local assets = Catalog.GetAssetsConfig()
	local pathsByEra = if assets ~= nil then assets.paths else nil
	local eraPaths = if pathsByEra ~= nil then pathsByEra[state.context.eraName] else nil
	return if eraPaths ~= nil then eraPaths.variants else nil
end

-- The variant the whole plot wears (docs/INTERFACES.md "Wave 1e — Surfaces"): the last owned
-- upgrade, else the base, else "default". A variant whose images are not uploaded yet resolves to
-- "default" as well, so a config that runs ahead of the texture pipeline still looks like today.
local function resolveVariant(
	state: State,
	owned: { [string]: boolean }
): (string, number?, number?)
	local paths = state.context.era.road.paths
	local surface = if paths ~= nil then paths.surface else nil
	if surface == nil then
		return DEFAULT_VARIANT, nil, nil
	end
	local name = surface.base
	local upgrades = surface.upgrades
	if type(upgrades) == "table" then
		for _, upgrade in upgrades do
			if owned[upgrade.slot] then
				name = upgrade.variant
			end
		end
	end
	if name == DEFAULT_VARIANT then
		return DEFAULT_VARIANT, nil, nil
	end
	local variants = eraVariantImages(state)
	local images = if variants ~= nil then variants[name] else nil
	local fillImageId = if images ~= nil then images.fillImageId else nil
	local rimImageId = if images ~= nil then images.rimImageId else nil
	if type(fillImageId) ~= "number" or type(rimImageId) ~= "number" then
		return DEFAULT_VARIANT, nil, nil
	end
	if fillImageId <= 0 or rimImageId <= 0 then
		return DEFAULT_VARIANT, nil, nil
	end
	return name, fillImageId, rimImageId
end

-- Parts mode repaints in place rather than redrawing: a variant changes the look of the roads,
-- not their geometry, and a redraw would rebuild the lane graph and respawn the plot's vehicles.
local function repaintParts(state: State): ()
	local function paint(instances: { Instance }): ()
		for _, instance in instances do
			if instance:IsA("BasePart") then
				instance.Material = state.material
				instance.Color = state.color
			end
		end
	end
	for _, parts in state.groupParts do
		paint(parts)
	end
	for _, parts in state.spurParts do
		paint(parts)
	end
	paint(state.bendParts)
end

-- Applies the resolved variant to whichever renderer is drawing. `initial` is the base applied
-- while the plot is still empty, so nothing is repainted and nothing puffs.
local function setVariant(
	state: State,
	owned: { [string]: boolean },
	animate: boolean,
	initial: boolean
): ()
	local name, fillImageId, rimImageId = resolveVariant(state, owned)
	if name == state.surfaceVariant then
		return
	end
	state.surfaceVariant = name
	local road = state.context.era.road
	local paths = road.paths
	local variants = if paths ~= nil then paths.variants else nil
	-- "default" is the era's own road look by definition, whatever a `variants` entry might say.
	local look = if name == DEFAULT_VARIANT or variants == nil then nil else variants[name]
	-- An unknown Enum.Material name keeps the era's own road material rather than dropping the
	-- whole plot to Plastic.
	local material = materialFor(road.material)
	state.material = if look ~= nil then materialOr(look.material, material) else material
	state.color = if look ~= nil then colorFor(look.color) else colorFor(road.color)
	local handle = state.paths
	if handle ~= nil then
		PathRenderer.SetSurface(handle, fillImageId, rimImageId)
	end
	if initial then
		return
	end
	if handle ~= nil and handle.mode == "baked" then
		-- Left to the flush: a purchase that changes the surface usually reveals a path as well,
		-- and one puff over the whole new surface beats a puff over the new piece alone.
		state.surfaceBurst = state.surfaceBurst or animate
		state.pathsDirty = state.pathsDirty or animate
		return
	end
	repaintParts(state)
end

-- After a silent renderer fallback: every revealed road again, as Parts.
local function redrawParts(state: State): ()
	state.lanes = nil
	for groupIndex in state.revealedGroups do
		drawGroup(state, groupIndex)
	end
	for slotId in state.spurs do
		drawSpur(state, slotId)
	end
	drawBends(state)
	local callback = state.context.onRoadsRedrawn
	if callback ~= nil then
		callback()
	end
end

function RoadGraph.new(context: Context, near: boolean): State
	local road = context.era.road
	local width = math.max(road.width, MIN_LENGTH)
	local polylines = RoadGraph.ReadPolylines(context.layout)
	local polylinePhases: { Noise.Phases } = {}
	for index in polylines do
		polylinePhases[index] = Noise.Phases(`{context.seed}:polyline:{index}`)
	end
	local laneFraction = if road.laneOffsetFraction ~= nil
		then road.laneOffsetFraction
		else context.config.road.laneOffsetFraction
	local state: State = {
		context = context,
		width = width,
		thickness = math.max(context.config.road.thickness, MIN_LENGTH),
		material = materialFor(road.material),
		color = colorFor(road.color),
		laneOffset = laneFraction * width,
		meander = road.meander,
		polylines = polylines,
		polylinePhases = polylinePhases,
		nodes = {},
		nodeByKey = {},
		stretches = {},
		groups = {},
		nodeStretches = {},
		stretchByPieceId = {},
		bendNodes = {},
		entrance = nil,
		distance = {},
		parent = {},
		routes = {},
		spurSlotIds = {},
		groupAllowed = {},
		spurAllowed = {},
		nearStretchAllowed = {},
		nearSpurAllowed = {},
		nearBendAllowed = {},
		pathStretchAllowed = {},
		pathSpurAllowed = {},
		pieceKeys = {},
		pieceSpecs = {},
		near = near,
		surfaceVariant = "",
		visible = {},
		revealedGroups = {},
		spurs = {},
		groupParts = {},
		spurParts = {},
		bendParts = {},
		pieces = {},
		lanes = nil,
		pathData = nil,
		paths = nil,
		pathsDirty = false,
		pathsAnimate = false,
		surfaceBurst = false,
	}
	buildNetwork(state)
	buildShortestPaths(state)
	allocate(state)
	if road.paths ~= nil then
		state.pathData = pathDataFor(state)
		-- Also sets the plot folder's PathRenderer attribute (a Studio diagnostic).
		state.paths = PathRenderer.Create({
			folder = context.folder,
			plotFrame = context.plotFrame,
			eraName = context.eraName,
			config = context.config,
			near = near,
			colorOf = function(): Color3
				return state.color
			end,
			width = width,
			centrelineOf = function(pieceId: string): { Vector3 }?
				return pieceCentreline(state, pieceId)
			end,
			onParts = function()
				redrawParts(state)
			end,
		})
	end
	-- The base surface before a single piece is cloned: a Boomtown plot must never flash asphalt
	-- on its way to gravel.
	setVariant(state, NO_SLOTS_OWNED, false, true)
	return state
end

-- The plot-wide surface variant for the slots owned right now (docs/INTERFACES.md "Wave 1e").
-- `animate` replays the dust over the drawn pieces, which only a purchase asks for: joins,
-- rejoins and era rebuilds switch instantly, exactly as a revealed path does.
function RoadGraph.SetSurface(state: State, owned: { [string]: boolean }, animate: boolean?): ()
	setVariant(state, owned, animate == true, false)
end

-- Whether the plot's paths are drawn from the baked meshes rather than as Parts.
function RoadGraph.UsesPaths(state: State): boolean
	local paths = state.paths
	return paths ~= nil and paths.mode == "baked"
end

-- Reveals the shortest path from the entrance to `node`, returning the groups that changed. The
-- path is walked back only until it meets a visible stretch (everything nearer the entrance is
-- then visible already), and revealed from the entrance outward up to the first stretch outside
-- the budget. An unreachable node reveals nothing.
local function reveal(state: State, node: number): { [number]: boolean }
	local changed: { [number]: boolean } = {}
	if state.distance[node] == nil then
		return changed
	end
	local path: { number } = {}
	local current = node
	while current ~= state.entrance do
		local id = state.parent[current]
		if id == nil or state.visible[id] then
			break
		end
		table.insert(path, id)
		local stretch = state.stretches[id]
		current = if stretch.fromNode == current then stretch.toNode else stretch.fromNode
	end
	for index = #path, 1, -1 do
		local stretch = state.stretches[path[index]]
		if not state.groupAllowed[stretch.group] then
			break
		end
		state.visible[path[index]] = true
		state.revealedGroups[stretch.group] = true
		changed[stretch.group] = true
	end
	return changed
end

-- Draws the slot's spur and reveals its path from the entrance if it is routable, inside the
-- budget and not drawn yet. Returns whether the network changed.
-- `animate` gives the new path the appear effect (baked renderer only). With that renderer
-- nothing is drawn until Flush, so a sync that reveals many spurs clones them in one pass.
function RoadGraph.AddSpur(state: State, slotId: string, animate: boolean?): boolean
	if state.spurs[slotId] ~= nil or not state.spurAllowed[slotId] then
		return false
	end
	local route = state.routes[slotId]
	state.spurs[slotId] = route
	local node = route.junction.node
	local drawsParts = not RoadGraph.UsesPaths(state)
	if node ~= nil then
		for groupIndex in reveal(state, node) do
			if drawsParts then
				drawGroup(state, groupIndex)
			end
		end
	end
	state.lanes = nil
	if not drawsParts then
		state.pathsDirty = true
		state.pathsAnimate = state.pathsAnimate or animate == true
	else
		drawSpur(state, slotId)
		drawBends(state)
	end
	refreshPieces(state)
	return true
end

-- Near/far flip: only the road Parts are redrawn (meandered near, straight far); tiles, the
-- lane graph and everything else stay. Eras without meander look the same either way. Baked
-- plots only drop and restore their rims, so neither their fills nor the lane graph move.
function RoadGraph.SetNear(state: State, near: boolean): ()
	if state.near == near then
		return
	end
	state.near = near
	local paths = state.paths
	if paths ~= nil and paths.mode == "baked" then
		PathRenderer.SetNear(paths, near)
		return
	end
	if state.meander == nil then
		return
	end
	-- Every revealed group, not only those currently holding Parts: a group whose stretches fall
	-- outside the near budget draws nothing while near and must still get its straight version.
	for groupIndex in state.revealedGroups do
		drawGroup(state, groupIndex)
	end
	for slotId in state.spurs do
		drawSpur(state, slotId)
	end
	drawBends(state)
end

-- Hands every spur revealed since the last Flush to PathRenderer in one update, with the appear
-- effect when any of them was a purchase. A fallback to Parts meanwhile already drew them.
function RoadGraph.Flush(state: State): ()
	if not state.pathsDirty then
		return
	end
	local animate = state.pathsAnimate
	local surfaceBurst = state.surfaceBurst
	state.pathsDirty = false
	state.pathsAnimate = false
	state.surfaceBurst = false
	local paths = state.paths
	if paths ~= nil and paths.mode == "baked" then
		local pieceIds = pathPieceIds(state)
		-- A fallback inside Update redraws every revealed road with Parts.
		PathRenderer.Update(paths, pieceIds, animate)
		-- Started last so it supersedes the reveal's puff (one burst runs per plot): the surface
		-- arrived everywhere at once, including on the pieces Update just cloned.
		if surfaceBurst then
			PathRenderer.Burst(paths, pieceIds)
		end
	end
end

function RoadGraph.RefreshPieces(state: State): ()
	refreshPieces(state)
end

function RoadGraph.DrawnSlotIds(state: State): { string }
	local slotIds: { string } = {}
	for slotId in state.spurs do
		table.insert(slotIds, slotId)
	end
	return slotIds
end

function RoadGraph.GetJunction(state: State, slotId: string): Junction?
	local route = state.spurs[slotId]
	return if route ~= nil then route.junction else nil
end

-- Whether the spine at a drawn spur's join point is visible (lamps wait for it).
function RoadGraph.JoinVisible(state: State, slotId: string): boolean
	local route = state.spurs[slotId]
	local node = if route ~= nil then route.junction.node else nil
	return node ~= nil and nodeTouchesVisible(state, node)
end

-- Every centreline the plot can ever have (all spines, every routable spur whether drawn or
-- not), so a seeded tree never lands where a later road will run.
function RoadGraph.AllCentrelines(state: State): { { Vector3 } }
	local lines: { { Vector3 } } = table.clone(state.polylines)
	for _, slotId in state.spurSlotIds do
		table.insert(lines, state.routes[slotId].points)
	end
	-- Baked eras also keep clear of the smoothed curves, which cut inside corners; the straight
	-- lines stay so a Parts fallback never draws under a tree either.
	local data = state.pathData
	if data ~= nil then
		for _, line in data.treeLines do
			table.insert(lines, line)
		end
	end
	return lines
end

-- Sorted slots whose spur fits the budget and meets a spine: the only places a lamp can go.
function RoadGraph.JunctionSlotIds(state: State): { string }
	local slotIds: { string } = {}
	for _, slotId in state.spurSlotIds do
		if state.spurAllowed[slotId] and state.routes[slotId].junction.node ~= nil then
			table.insert(slotIds, slotId)
		end
	end
	return slotIds
end

-- Whether a baked piece is drawn right now: a row lamp post waits for the piece it stands on.
function RoadGraph.PieceVisible(state: State, pieceId: string): boolean
	local id = state.stretchByPieceId[pieceId]
	if id == nil or not state.visible[id] then
		return false
	end
	-- After a silent fallback the meandered Parts renderer draws the near budget rather than the
	-- baked plan, so a post must not stand beside a stretch that renderer skipped. Straight eras
	-- draw every visible stretch, near or far.
	if RoadGraph.UsesPaths(state) or state.meander == nil then
		return true
	end
	return state.nearStretchAllowed[id] == true
end

-- How many of a node's spine stretches are drawn; a signal waits for two, so it stands at a
-- crossing that exists rather than beside a single street.
function RoadGraph.VisibleAt(state: State, node: number): number
	local stretches: { number } = state.nodeStretches[node] or {}
	local count = 0
	for _, id in stretches do
		if state.visible[id] then
			count += 1
		end
	end
	return count
end

-- A stretch the plot can ever draw. Ownership plays no part, so a plan built from these is the
-- same at any point in the plot's growth, like every other dressing plan.
local function plannedStretch(state: State, id: number): boolean
	if state.pathData ~= nil then
		return state.pathStretchAllowed[id] == true
	end
	return state.groupAllowed[state.stretches[id].group] == true
end

-- One spine stretch's drawn centreline in polyline order (the dust track runs from the join end
-- instead), so consecutive pieces of a street can be walked as one curve.
local function stretchLine(state: State, id: number): { Vector3 }?
	local stretch = state.stretches[id]
	local data = state.pathData
	if data == nil then
		return (
			centreline(
				state,
				stretch.a,
				stretch.b,
				stretch.arcStart,
				state.polylinePhases[stretch.polyline]
			)
		)
	end
	local chain = data.stretchChains[id]
	local arcs = data.stretchArcs[id]
	if chain == nil or arcs == nil then
		return nil
	end
	local network = data.network
	local points: { Vector3 } = {}
	local sampled = PathRibbon.Centreline(
		network,
		chain,
		math.min(arcs[1], arcs[2]),
		math.max(arcs[1], arcs[2]),
		network.sampleSpacing
	)
	for _, point in sampled do
		table.insert(points, Vector3.new(point[1], 0, point[2]))
	end
	return points
end

-- Wave 1e: every drawable spine piece as a drawn centreline, grouped into continuous runs along
-- each polyline, plus every spur's drawn centreline. Scatter walks the runs to place lamp posts
-- and keeps them off the spurs; nothing here depends on what is owned or on the renderer in use.
function RoadGraph.StreetLines(state: State): StreetLines
	local lines: StreetLines = { runs = {}, spurs = {} }
	local segmentGroups = 0
	for _, points in state.polylines do
		segmentGroups += #points - 1
	end
	local open: { [number]: SpineRun } = {} -- polyline -> the run still being extended
	for groupIndex, group in state.groups do
		for _, id in group.stretches do
			local stretch = state.stretches[id]
			local points = if plannedStretch(state, id) then stretchLine(state, id) else nil
			if points == nil then
				-- A piece outside the plan breaks the street: a walk must not step over the gap.
				open[stretch.polyline] = nil
				continue
			end
			-- A connector is a short link onto another polyline, not a continuation of one.
			local continues = groupIndex <= segmentGroups
			local run: SpineRun? = if continues then open[stretch.polyline] else nil
			if run == nil then
				local fresh: SpineRun = { polyline = stretch.polyline, pieces = {} }
				table.insert(lines.runs, fresh)
				if continues then
					open[stretch.polyline] = fresh
				end
				run = fresh
			end
			table.insert((run :: SpineRun).pieces, {
				pieceId = stretch.pieceId,
				stretch = stretch.ordinal,
				points = points,
			})
		end
	end
	for _, slotId in state.spurSlotIds do
		if state.spurAllowed[slotId] then
			table.insert(
				lines.spurs,
				pieceCentreline(state, SPUR_PIECE_PREFIX .. slotId) or state.routes[slotId].points
			)
		end
	end
	return lines
end

-- Wave 1e: one spot per crossing (a node where SIGNAL_MIN_ARMS spine stretches meet), in the
-- corner between the two arms with the widest usable gap, `offset` studs outside both road edges.
-- Derived from the layout alone, so every client stands its signals in the same corners.
function RoadGraph.SignalSpots(state: State, offset: number, maxCount: number): { SignalSpot }
	local spots: { SignalSpot } = {}
	local nodes: { number } = {}
	for node, stretches in state.nodeStretches do
		if #stretches >= SIGNAL_MIN_ARMS then
			table.insert(nodes, node)
		end
	end
	table.sort(nodes)
	local reach = state.width / 2 + math.max(offset, 0)
	for _, node in nodes do
		if #spots >= maxCount then
			break
		end
		local point = state.nodes[node]
		local arms: { Vector3 } = {}
		for _, id in state.nodeStretches[node] do
			local stretch = state.stretches[id]
			local far = if stretch.fromNode == node then stretch.b else stretch.a
			local direction = unitOrNil(far - point)
			if direction ~= nil then
				table.insert(arms, direction)
			end
		end
		if #arms < SIGNAL_MIN_ARMS then
			continue
		end
		table.sort(arms, function(a: Vector3, b: Vector3): boolean
			return math.atan2(a.Z, a.X) < math.atan2(b.Z, b.X)
		end)
		local corner: Vector3? = nil
		local bestGap = 0
		for index, arm in arms do
			local following = arms[index % #arms + 1]
			local gap = math.atan2(following.Z, following.X) - math.atan2(arm.Z, arm.X)
			if gap <= 0 then
				gap += FULL_TURN
			end
			if gap >= SIGNAL_GAP_MIN and gap <= SIGNAL_GAP_MAX and gap > bestGap then
				corner = unitOrNil(arm + following)
				bestGap = gap
			end
		end
		if corner == nil then
			continue
		end
		local bisector = corner :: Vector3
		table.insert(spots, {
			node = node,
			position = point + bisector * (reach / math.sin(bestGap / 2)),
			-- The corner direction points away from the crossing, and the prop faces it.
			yaw = math.atan2(bisector.X, bisector.Z),
		})
	end
	return spots
end

-- Lanes follow the same centreline function as the meandered rendering (whether or not the
-- plot is near right now), cut into short lanes joined through pass-through nodes, so vehicles
-- stay on the trail. Network nodes are shared; the pass-through nodes are not. Plots drawn by
-- PathRenderer take PathRibbon's meandered centreline instead -- the curve the meshes were baked
-- from -- with the network's own node ids at stretch ends and joins, since the drawn curves meet
-- only to within float noise.
local function buildLanes(state: State): Lanes
	local lanes: Lanes = {
		count = 0,
		to = {},
		reverse = {},
		origin = {},
		direction = {},
		length = {},
		yaw = {},
		outgoing = {},
	}
	local nodeCount = 0
	local nodeByKey: { [string]: number } = {}
	local function freshNode(): number
		nodeCount += 1
		lanes.outgoing[nodeCount] = {}
		return nodeCount
	end
	local function nodeAt(point: Vector3): number
		local key = keyFor(point)
		local id = nodeByKey[key]
		if id == nil then
			id = freshNode()
			nodeByKey[key] = id
		end
		return id :: number
	end

	local frame = state.context.plotFrame
	local top = state.thickness
	local offset = state.laneOffset
	local function addLane(fromNode: number, toNode: number, a: Vector3, b: Vector3): number
		local worldA = frame:PointToWorldSpace(Vector3.new(a.X, top, a.Z))
		local worldB = frame:PointToWorldSpace(Vector3.new(b.X, top, b.Z))
		local delta = worldB - worldA
		local length = delta.Magnitude
		local direction = delta / length
		lanes.count += 1
		local id = lanes.count
		lanes.to[id] = toNode
		lanes.origin[id] = worldA
		lanes.direction[id] = direction
		lanes.length[id] = length
		lanes.yaw[id] = math.atan2(-direction.X, -direction.Z)
		table.insert(lanes.outgoing[fromNode], id)
		return id
	end
	local function chainBetween(points: { Vector3 }, firstNode: number, lastNode: number): ()
		local previous = firstNode
		for index = 2, #points do
			local a, b = points[index - 1], points[index]
			if (b - a).Magnitude < MIN_LENGTH then
				continue
			end
			local current = if index == #points then lastNode else freshNode()
			local right = ((b - a).Unit):Cross(UP)
			local forward = addLane(previous, current, a + right * offset, b + right * offset)
			local backward = addLane(current, previous, b - right * offset, a - right * offset)
			lanes.reverse[forward] = backward
			lanes.reverse[backward] = forward
			previous = current
		end
	end
	local function chain(points: { Vector3 }): ()
		chainBetween(points, nodeAt(points[1]), nodeAt(points[#points]))
	end

	local data = state.pathData
	if data ~= nil and RoadGraph.UsesPaths(state) then
		-- Network node ids first, so stretch ends and spur joins share lane nodes by id.
		for _ = 1, #state.nodes do
			freshNode()
		end
		local network = data.network
		local spacing = network.sampleSpacing
		local function sampled(chainIndex: number, a: number, b: number): { Vector3 }
			local points: { Vector3 } = {}
			for _, point in PathRibbon.Centreline(network, chainIndex, a, b, spacing) do
				table.insert(points, Vector3.new(point[1], 0, point[2]))
			end
			return points
		end
		for id, stretch in state.stretches do
			local chainIndex = data.stretchChains[id]
			if state.visible[id] and state.pathStretchAllowed[id] and chainIndex ~= nil then
				local arcs = data.stretchArcs[id]
				chainBetween(
					sampled(chainIndex, arcs[1], arcs[2]),
					stretch.fromNode,
					stretch.toNode
				)
			end
		end
		for _, slotId in state.spurSlotIds do
			local route = state.spurs[slotId]
			local chainIndex = network.spurChains[slotId]
			if route == nil or chainIndex == nil or not state.pathSpurAllowed[slotId] then
				continue
			end
			local lo, hi = PathRibbon.FullSpan(network, chainIndex)
			chainBetween(
				sampled(chainIndex, lo, hi),
				freshNode(),
				route.junction.node or freshNode()
			)
		end
		return lanes
	end

	-- Vehicles only ever run on near plots, so in a meander era the lanes follow exactly what the
	-- near rendering draws: a stretch or spur outside budget.roadPiecesNear has no Part under it
	-- and is left out, even though it exists straight on far plots. That can leave a short lane
	-- island when the budget runs out mid-network; a vehicle shuttling along a drawn piece of road
	-- beats one driving over bare ground. Eras without meander draw everything visible, so they
	-- take the whole network.
	local meandered = state.meander ~= nil
	for id, stretch in state.stretches do
		if state.visible[id] and (not meandered or state.nearStretchAllowed[id]) then
			chain(
				(
					centreline(
						state,
						stretch.a,
						stretch.b,
						stretch.arcStart,
						state.polylinePhases[stretch.polyline]
					)
				)
			)
		end
	end
	for _, slotId in state.spurSlotIds do
		local route = state.spurs[slotId]
		if route == nil or (meandered and not state.nearSpurAllowed[slotId]) then
			continue
		end
		local arc = 0
		for index = 2, #route.points do
			local a, b = route.points[index - 1], route.points[index]
			chain((centreline(state, a, b, arc, route.phases)))
			arc += (b - a).Magnitude
		end
	end
	return lanes
end

-- Cached until a spur (and so possibly spine) appears; near/far never invalidates it.
function RoadGraph.GetLanes(state: State): Lanes
	local lanes = state.lanes
	if lanes == nil then
		lanes = buildLanes(state)
		state.lanes = lanes
	end
	return lanes :: Lanes
end

function RoadGraph.Destroy(state: State): ()
	local paths = state.paths
	if paths ~= nil then
		PathRenderer.Destroy(paths)
	end
	for _, parts in state.groupParts do
		destroyAll(parts)
	end
	for _, parts in state.spurParts do
		destroyAll(parts)
	end
	destroyAll(state.bendParts)
	for _, piece in state.pieces do
		piece:Destroy()
	end
	table.clear(state.groupParts)
	table.clear(state.spurParts)
	table.clear(state.pieces)
	table.clear(state.visible)
	table.clear(state.revealedGroups)
	table.clear(state.spurs)
	state.lanes = nil
end

return RoadGraph
