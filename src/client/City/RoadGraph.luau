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
-- Wave 1c: eras with `road.ribbon` hand drawing to PathRenderer (smooth textured ribbons, or
-- flat Beams), which falls back to the Parts here silently. Those plots have no near/far road
-- rebuild; their lanes follow PathRibbon's meandered centreline and trees keep clear of its
-- smoothed centreline of every potential path.
--
-- Everything is computed in plot-local studs (origin at the plot's top-centre, front -Z, Y 0) and
-- placed through the plot frame, so every client derives identical geometry from the layout.
-- The network, the shortest-path tree and every budget decision are fixed once per plot/era
-- from the whole layout, so what appears never depends on purchase order and nothing already
-- drawn ever moves: buying a building only reveals the missing stretches of its path.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local PropFactory = require(script.Parent:WaitForChild("PropFactory"))
local Noise = require(script.Parent:WaitForChild("Noise"))
local PathRibbon = require(script.Parent:WaitForChild("PathRibbon"))
local PathRenderer = require(script.Parent:WaitForChild("PathRenderer"))

local SPINE_PART_NAME = "Road"
local SPUR_PART_NAME = "Spur"
local BEND_PART_NAME = "RoadBend"
-- Points closer than this are the same point; also the shortest leg worth a Part or an edge.
local MIN_LENGTH = 0.05
-- Graph nodes merge on a 1 / NODE_KEY_SCALE stud grid so float noise never splits a corner.
local NODE_KEY_SCALE = 10
-- Consecutive directions whose dot product reaches this are straight, not a bend.
local STRAIGHT_DOT = 0.999
local UP = Vector3.yAxis
local QUARTER_TURN = math.pi / 2
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

-- Ribbon geometry for a layout, shared by every plot of the era (it depends on nothing else).
type RibbonData = {
	era: Types.CityEraDressingConfig,
	thickness: number,
	network: PathRibbon.Network,
	stretchChains: { [number]: number }, -- stretch id -> chain index
	stretchArcs: { [number]: { number } }, -- stretch id -> final arcs at a and b
	fullTriangles: number,
	extent: number,
	treeLines: { { Vector3 } },
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
	pieceKeys: { string },
	pieceSpecs: { [string]: PieceSpec },
	-- Live.
	near: boolean,
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
	ribbon: RibbonData?, -- eras with road.ribbon
	paths: PathRenderer.Handle?, -- nil: Parts from the start
	-- Spurs revealed since the last Flush while PathRenderer draws, and whether any of them
	-- should grow in.
	pathsDirty: boolean,
	pathsAnimate: boolean,
}

local ribbonCache: { [Types.EraLayout]: RibbonData } = {}
local pathSpans: (state: State) -> { PathRibbon.Span }

local materialsByName: { [string]: Enum.Material }? = nil

local function materialFor(name: string): Enum.Material
	local lookup = materialsByName
	if lookup == nil then
		local built: { [string]: Enum.Material } = {}
		for _, item in Enum.Material:GetEnumItems() do
			built[item.Name] = item
		end
		lookup = built
		materialsByName = built
	end
	return (lookup :: { [string]: Enum.Material })[name] or Enum.Material.Plastic
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

	type Ranked = { index: number, distance: number }
	local function byDistance(a: Ranked, b: Ranked): boolean
		if a.distance == b.distance then
			return a.index < b.index
		end
		return a.distance < b.distance
	end

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

-- The final-curve arc of a network node on a chain. A polyline's own end points map to the
-- chain's ends exactly: a joiner's end was snapped onto its host, so projecting the unsnapped
-- point could land a little way along the curve.
local function chainArc(
	network: PathRibbon.Network,
	chainIndex: number,
	point: Vector3,
	polyline: { Vector3 }?
): number
	local lo, hi = PathRibbon.FullSpan(network, chainIndex)
	if polyline ~= nil then
		local key = keyFor(point)
		if key == keyFor(polyline[1]) then
			return lo
		elseif key == keyFor(polyline[#polyline]) then
			return hi
		end
	end
	return PathRibbon.ArcAt(network, chainIndex, point.X, point.Z)
end

local function toPoints(points: { Vector3 }): { PathRibbon.Point }
	local out: { PathRibbon.Point } = {}
	for _, point in points do
		table.insert(out, { point.X, point.Z })
	end
	return out
end

-- Every visible stretch and drawn spur as a span of its ribbon chain.
pathSpans = function(state: State): { PathRibbon.Span }
	local spans: { PathRibbon.Span } = {}
	local ribbon = state.ribbon
	if ribbon == nil then
		return spans
	end
	for id, stretch in state.stretches do
		local chain = ribbon.stretchChains[id]
		if not state.visible[id] or chain == nil then
			continue
		end
		local arcs = ribbon.stretchArcs[id]
		table.insert(spans, {
			chain = chain,
			a = arcs[1],
			b = arcs[2],
			distA = state.distance[stretch.fromNode] or math.huge,
			distB = state.distance[stretch.toNode] or math.huge,
		})
	end
	for _, slotId in state.spurSlotIds do
		local chain = ribbon.network.spurChains[slotId]
		if state.spurs[slotId] == nil or chain == nil then
			continue
		end
		local lo, hi = PathRibbon.FullSpan(ribbon.network, chain)
		-- A spur grows from its join toward the building.
		table.insert(spans, { chain = chain, a = lo, b = hi, distA = math.huge, distB = 0 })
	end
	return spans
end

-- Smooths the whole potential network once per layout. The triangle count covers what can ever
-- be drawn (the allowed groups and spurs), so the renderer choice never depends on ownership.
local function ribbonDataFor(state: State, ribbonConfig: Types.CityRibbonConfig): RibbonData
	local context = state.context
	local cached = ribbonCache[context.layout]
	if cached ~= nil and cached.era == context.era and cached.thickness == state.thickness then
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
		thickness = state.thickness,
		meander = if meander ~= nil
			then {
				amplitude = meander.amplitude,
				wavelength = meander.wavelength,
				widthJitter = meander.widthJitter,
			}
			else nil,
		ribbon = ribbonConfig,
		polylines = polylines,
		connectors = connectors,
		spurs = spurs,
	})

	local data: RibbonData = {
		era = context.era,
		thickness = state.thickness,
		network = network,
		stretchChains = {},
		stretchArcs = {},
		fullTriangles = 0,
		extent = PathRibbon.Extent(network),
		treeLines = {},
	}
	local allSpans: { PathRibbon.Span } = {}
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
			local lo, hi = PathRibbon.FullSpan(network, chain)
			arcs = { lo, hi }
		else
			local polyline = state.polylines[stretch.polyline]
			arcs = {
				chainArc(network, chain, stretch.a, polyline),
				chainArc(network, chain, stretch.b, polyline),
			}
		end
		data.stretchChains[id] = chain
		data.stretchArcs[id] = arcs
		if state.groupAllowed[stretch.group] and stretchNearDistance(state, id) ~= nil then
			table.insert(
				allSpans,
				{ chain = chain, a = arcs[1], b = arcs[2], distA = 0, distB = 0 }
			)
		end
	end
	for _, slotId in state.spurSlotIds do
		local chain = network.spurChains[slotId]
		if chain ~= nil and state.spurAllowed[slotId] then
			local lo, hi = PathRibbon.FullSpan(network, chain)
			table.insert(allSpans, { chain = chain, a = lo, b = hi, distA = 0, distB = 0 })
		end
	end
	for _, piece in PathRibbon.Pieces(network, allSpans) do
		data.fullTriangles += PathRibbon.TriangleCount(#PathRibbon.Rows(network, piece))
	end
	-- Sampled about a road width apart: on the tightest fillet (radius cornerRadiusWidths *
	-- width) the chord strays well under the clearance margin, and it is a fraction of the
	-- segments the mesh needs.
	for _, line in PathRibbon.SmoothedCentrelines(network, state.width) do
		local points: { Vector3 } = {}
		for _, point in line do
			table.insert(points, Vector3.new(point[1], 0, point[2]))
		end
		table.insert(data.treeLines, points)
	end
	ribbonCache[context.layout] = data
	return data
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
		pieceKeys = {},
		pieceSpecs = {},
		near = near,
		visible = {},
		revealedGroups = {},
		spurs = {},
		groupParts = {},
		spurParts = {},
		bendParts = {},
		pieces = {},
		lanes = nil,
		ribbon = nil,
		paths = nil,
		pathsDirty = false,
		pathsAnimate = false,
	}
	buildNetwork(state)
	buildShortestPaths(state)
	allocate(state)
	local ribbonConfig = road.ribbon
	if ribbonConfig ~= nil then
		local ribbon = ribbonDataFor(state, ribbonConfig)
		state.ribbon = ribbon
		-- Also sets the plot folder's PathRenderer attribute (a Studio diagnostic).
		state.paths = PathRenderer.Create({
			folder = context.folder,
			plotFrame = context.plotFrame,
			eraName = context.eraName,
			config = context.config,
			ribbon = ribbonConfig,
			network = ribbon.network,
			fullTriangles = ribbon.fullTriangles,
			extent = ribbon.extent,
			color = state.color,
			onParts = function()
				redrawParts(state)
			end,
		})
	end
	return state
end

-- Whether the plot's roads are drawn by PathRenderer (ribbon or beam) rather than Parts.
function RoadGraph.UsesPaths(state: State): boolean
	local paths = state.paths
	return paths ~= nil and paths.mode ~= "parts"
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
-- `animate` grows the new path (ribbon and beam renderers only). With those renderers nothing is
-- drawn until Flush, so a sync that reveals many spurs rebuilds the meshes once.
function RoadGraph.AddSpur(state: State, slotId: string, animate: boolean?): boolean
	if state.spurs[slotId] ~= nil or not state.spurAllowed[slotId] then
		return false
	end
	local route = state.routes[slotId]
	state.spurs[slotId] = route
	local node = route.junction.node
	local paths = state.paths
	local drawsParts = paths == nil or paths.mode == "parts"
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
-- lane graph and everything else stay. Eras without meander look the same either way.
function RoadGraph.SetNear(state: State, near: boolean): ()
	if state.near == near then
		return
	end
	state.near = near
	if state.meander == nil or RoadGraph.UsesPaths(state) then
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

-- Retries tiles whose templates were missing earlier (props replicate or upload later).
-- Hands every spur revealed since the last Flush to PathRenderer in one update, growing them all
-- together when any was a purchase. A fallback to Parts meanwhile already drew them.
function RoadGraph.Flush(state: State): ()
	if not state.pathsDirty then
		return
	end
	local animate = state.pathsAnimate
	state.pathsDirty = false
	state.pathsAnimate = false
	local paths = state.paths
	if paths ~= nil and paths.mode ~= "parts" then
		-- A fallback inside Update redraws every revealed road with Parts.
		PathRenderer.Update(paths, pathSpans(state), animate)
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
	-- Ribbon eras also keep clear of the smoothed curves, which cut inside corners; the straight
	-- lines stay so a Parts fallback never draws under a tree either.
	local ribbon = state.ribbon
	if ribbon ~= nil then
		for _, line in ribbon.treeLines do
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

-- Lanes follow the same centreline function as the meandered rendering (whether or not the
-- plot is near right now), cut into short lanes joined through pass-through nodes, so vehicles
-- stay on the trail. Network nodes are shared; the pass-through nodes are not. Plots drawn by
-- PathRenderer take PathRibbon's meandered centreline instead, with the network's own node ids
-- at stretch ends and joins, since the drawn curves meet only to within float noise.
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

	local ribbon = state.ribbon
	if ribbon ~= nil and RoadGraph.UsesPaths(state) then
		-- Network node ids first, so stretch ends and spur joins share lane nodes by id.
		for _ = 1, #state.nodes do
			freshNode()
		end
		local network = ribbon.network
		local spacing = network.ribbon.sampleSpacing
		local function sampled(chainIndex: number, a: number, b: number): { Vector3 }
			local points: { Vector3 } = {}
			for _, point in PathRibbon.Centreline(network, chainIndex, a, b, spacing) do
				table.insert(points, Vector3.new(point[1], 0, point[2]))
			end
			return points
		end
		for id, stretch in state.stretches do
			local chainIndex = ribbon.stretchChains[id]
			if state.visible[id] and chainIndex ~= nil then
				local arcs = ribbon.stretchArcs[id]
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
			if route == nil or chainIndex == nil then
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
