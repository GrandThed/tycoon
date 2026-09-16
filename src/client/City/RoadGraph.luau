--!strict
-- Per-plot roads (docs/INTERFACES.md "M9 contracts — Road routing"): spine Parts per visible
-- layout polyline, an L-shaped spur per owned slot, optional kit junction/bend props, and the
-- lane graph the traffic loop drives on. Roads are plain Parts and never need an asset.
--
-- Everything is computed in plot-local studs (origin at the plot's top-centre, front -Z, Y 0)
-- and placed through the plot frame, so every client derives identical geometry from the
-- layout alone. Budget allocation is decided up front from the whole layout rather than in the
-- order things appear, so which spurs/pieces fit never depends on purchase order and dressing
-- only ever adds: spine segments first, then spurs by sorted slot id, then bends, then
-- junction pieces, all within CityDressing.json budget.roadPieces. A cloned tile counts as one
-- piece (PropFactory drops its invisible Base).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

local PropFactory = require(script.Parent:WaitForChild("PropFactory"))

local SPINE_PART_NAME = "Road"
local SPUR_PART_NAME = "Spur"
-- Points closer than this are the same point; also the shortest leg worth a Part or an edge.
local MIN_LENGTH = 0.05
-- Graph nodes merge on a 1 / NODE_KEY_SCALE stud grid so float noise never splits a corner.
local NODE_KEY_SCALE = 10
-- Consecutive spine directions whose dot product reaches this are straight, not a bend.
local STRAIGHT_DOT = 0.999
local UP = Vector3.yAxis
-- Kit tile exits at rotY 0 (city-kit-roads, measured by the Boomtown prop-builder): the T
-- junction opens to -X, +X and +Z (straight kerb along -Z); the bend opens to -X and +Z.
local JUNCTION_EXITS = { Vector3.new(-1, 0, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) }
local BEND_EXITS = { Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1) }

export type Junction = {
	position: Vector3, -- plot-local, on the spine centreline when `polyline` is set
	direction: Vector3, -- unit XZ, travelling along the spur's last leg toward the spine
	polyline: number?, -- the spine polyline the spur joins; nil when it joins none
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
	config: Types.CityDressingConfig,
	era: Types.CityEraDressingConfig,
}

type SpurRoute = { points: { Vector3 }, junction: Junction? }
type Segment = { a: Vector3, b: Vector3, polyline: number }
type PieceSpec = {
	propName: string,
	position: Vector3,
	rotation: CFrame, -- quarter turn about Y lining the tile's exits up with the roads
	polyline: number,
	-- Junction pieces show once any of these spurs is drawn; empty for bends.
	slotIds: { string },
}

export type State = {
	context: Context,
	width: number,
	thickness: number,
	material: Enum.Material,
	color: Color3,
	polylines: { { Vector3 } },
	spineAllowed: { number }, -- per polyline: leading segments inside the budget
	visible: number, -- polylines drawn so far (1..visible)
	routes: { [string]: SpurRoute }, -- every routable layout slot
	spurSlotIds: { string }, -- sorted keys of `routes`
	spurAllowed: { [string]: boolean },
	pieceKeys: { string }, -- allocation order
	pieceSpecs: { [string]: PieceSpec },
	pieces: { [string]: Model },
	segments: { Segment }, -- drawn spine segments
	spurs: { [string]: SpurRoute }, -- drawn spurs
	parts: { Instance },
	lanes: Lanes?,
}

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

-- Nearest spine polyline to a point and the closest point on it; nil without any spine.
local function nearestSpine(
	point: Vector3,
	polylines: { { Vector3 } },
	aheadOf: Vector3?,
	facing: Vector3?
): (Vector3?, number?)
	local bestPoint: Vector3? = nil
	local bestPolyline: number? = nil
	local bestDistance = math.huge
	for polylineIndex, points in polylines do
		for index = 2, #points do
			local closest = RoadGraph.ClosestOnSegment(point, points[index - 1], points[index])
			local ahead = aheadOf == nil
				or facing == nil
				or (closest - aheadOf):Dot(facing) >= -MIN_LENGTH
			local distance = (closest - point).Magnitude
			if ahead and distance < bestDistance then
				bestPoint = closest
				bestPolyline = polylineIndex
				bestDistance = distance
			end
		end
	end
	return bestPoint, bestPolyline
end

-- Pure routing for one slot: the layout's `spur` override verbatim, else pad outer edge →
-- along the facing until level with the nearest spine point → perpendicular onto it. A spine
-- segment ahead of the pad is preferred so leg 1 never runs back through the building.
function RoadGraph.RouteSlot(
	layout: Types.EraLayout,
	polylines: { { Vector3 } },
	slotLayout: Types.SlotLayout,
	width: number
): SpurRoute?
	local facing = facingFor(slotLayout.rotationY)
	local override = slotLayout.spur
	local points: { Vector3 } = {}
	-- Street-plan amendment P2: a one-point override means the building already sits on or
	-- against a road, so the slot has no spur at all (no Part, tile, lamp or graph edge).
	if type(override) == "table" and #override == 1 then
		return nil
	end
	if type(override) == "table" and #override >= 2 then
		for _, point in override do
			table.insert(points, flat(point))
		end
	else
		if #polylines == 0 then
			return nil
		end
		local padCentre = slotLayout.padPosition or slotLayout.position + facing * layout.padOffset
		local start = flat(padCentre + facing * (layout.padSize.Z / 2))
		local target = nearestSpine(start, polylines, start, facing)
			or nearestSpine(start, polylines, nil, nil)
		if target == nil then
			return nil
		end
		local corner = start + facing * (target - start):Dot(facing)
		table.insert(points, start)
		if (corner - start).Magnitude >= MIN_LENGTH then
			table.insert(points, corner)
		end
		if (target - points[#points]).Magnitude >= MIN_LENGTH then
			table.insert(points, target)
		end
	end

	local last = points[#points]
	local direction = if #points >= 2 then unitOrNil(last - points[#points - 1]) else nil
	local joinPoint, joinPolyline = nearestSpine(last, polylines, nil, nil)
	local joins = joinPoint ~= nil and (joinPoint - last).Magnitude <= width / 2 + MIN_LENGTH
	return {
		points = points,
		junction = {
			position = last,
			direction = direction or facing,
			polyline = if joins then joinPolyline else nil,
			approach = if #points >= 2 then (last - points[#points - 1]).Magnitude else 0,
		},
	}
end

local function legCount(route: SpurRoute): number
	return math.max(#route.points - 1, 0)
end

local function roadPart(state: State, name: string, a: Vector3, b: Vector3): ()
	local length = (b - a).Magnitude
	if length < MIN_LENGTH then
		return
	end
	local y = state.thickness / 2
	local mid = (a + b) / 2
	local part = Instance.new("Part")
	part.Name = name
	-- Length + width so consecutive legs overlap a full square at every corner.
	part.Size = Vector3.new(state.width, state.thickness, length + state.width)
	part.CFrame = state.context.plotFrame
		* CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z))
	part.Material = state.material
	part.Color = state.color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	PropFactory.Seal(part)
	part.Parent = state.context.folder
	table.insert(state.parts, part)
end

local function refreshPieces(state: State): ()
	local context = state.context
	for _, key in state.pieceKeys do
		local placed: Model? = state.pieces[key]
		if placed ~= nil then
			continue
		end
		local spec = state.pieceSpecs[key]
		if spec.polyline > state.visible then
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

-- Unit XZ directions in which roads leave `point`: each spine polyline through it (both ways
-- when it passes through, one way at its end) plus each listed spur arriving there.
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
		local junction = state.routes[slotId].junction
		if junction ~= nil then
			addArm(-junction.direction)
		end
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
		local rotation = CFrame.Angles(0, quarter * math.pi / 2, 0)
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

-- Budget plan for the whole layout; see the header for the order. Piece geometry is judged
-- against every road that can ever meet at the point, so a tile placed early is never wrong
-- once the rest of the plot grows in.
local function allocate(state: State): ()
	local context = state.context
	local road = context.era.road
	local remaining = context.config.budget.roadPieces

	for index, points in state.polylines do
		local allowed = math.min(#points - 1, remaining)
		state.spineAllowed[index] = allowed
		remaining -= allowed
	end
	for _, slotId in state.spurSlotIds do
		local legs = legCount(state.routes[slotId])
		if legs <= remaining then
			state.spurAllowed[slotId] = true
			remaining -= legs
		end
	end

	-- Spur-to-spine meeting points, each with the spurs arriving there (sorted slot order).
	local junctionKeys: { string } = {}
	local junctionSlots: { [string]: { string } } = {}
	local junctionPoints: { [string]: Junction } = {}
	for _, slotId in state.spurSlotIds do
		local junction = state.routes[slotId].junction
		if not state.spurAllowed[slotId] or junction == nil or junction.polyline == nil then
			continue
		end
		local key = keyFor(junction.position)
		local slots = junctionSlots[key]
		if slots == nil then
			slots = {}
			junctionSlots[key] = slots
			junctionPoints[key] = junction
			table.insert(junctionKeys, key)
		end
		table.insert(slots :: { string }, slotId)
	end

	local function addPiece(
		key: string,
		propName: string,
		position: Vector3,
		rotation: CFrame,
		polyline: number,
		slotIds: { string }
	): ()
		state.pieceSpecs[key] = {
			propName = propName,
			position = position,
			rotation = rotation,
			polyline = polyline,
			slotIds = slotIds,
		}
		table.insert(state.pieceKeys, key)
		remaining -= 1
	end

	local bendProp = road.bendProp
	if bendProp ~= nil then
		for polylineIndex, points in state.polylines do
			-- Only corners whose both segments are drawn, and never where a spur also meets.
			for index = 2, state.spineAllowed[polylineIndex] do
				local key = keyFor(points[index])
				if remaining <= 0 or junctionSlots[key] ~= nil or state.pieceSpecs[key] ~= nil then
					continue
				end
				local rotation = tileRotation(armsAt(state, points[index], {}), BEND_EXITS)
				if rotation ~= nil then
					addPiece(key, bendProp, points[index], rotation, polylineIndex, {})
				end
			end
		end
	end

	local junctionProp = road.junctionProp
	if junctionProp ~= nil then
		for _, key in junctionKeys do
			local junction = junctionPoints[key]
			local slotIds = junctionSlots[key]
			if remaining <= 0 or state.pieceSpecs[key] ~= nil then
				continue
			end
			local rotation = tileRotation(armsAt(state, junction.position, slotIds), JUNCTION_EXITS)
			if rotation ~= nil then
				addPiece(
					key,
					junctionProp,
					junction.position,
					rotation,
					junction.polyline :: number,
					slotIds
				)
			end
		end
	end
end

function RoadGraph.new(context: Context): State
	local road = context.era.road
	local width = math.max(road.width, MIN_LENGTH)
	local layout = context.layout
	local state: State = {
		context = context,
		width = width,
		thickness = math.max(context.config.road.thickness, MIN_LENGTH),
		material = materialFor(road.material),
		color = colorFor(road.color),
		polylines = RoadGraph.ReadPolylines(layout),
		spineAllowed = {},
		visible = 0,
		routes = {},
		spurSlotIds = {},
		spurAllowed = {},
		pieceKeys = {},
		pieceSpecs = {},
		pieces = {},
		segments = {},
		spurs = {},
		parts = {},
		lanes = nil,
	}
	-- Sorted: dictionary iteration order is not guaranteed identical across clients.
	local slotIds: { string } = {}
	for slotId in layout.slots do
		table.insert(slotIds, slotId)
	end
	table.sort(slotIds)
	for _, slotId in slotIds do
		local route = RoadGraph.RouteSlot(layout, state.polylines, layout.slots[slotId], width)
		if route ~= nil then
			state.routes[slotId] = route
			table.insert(state.spurSlotIds, slotId)
		end
	end
	allocate(state)
	return state
end

-- Draws the polylines the tier has unlocked (polyline i at tier i * spineTierStep). Returns
-- whether anything new appeared.
function RoadGraph.SetTier(state: State, tier: number): boolean
	local step = state.context.config.road.spineTierStep
	local changed = false
	for index = state.visible + 1, #state.polylines do
		if index * step > tier then
			break
		end
		local points = state.polylines[index]
		for segment = 1, state.spineAllowed[index] do
			local a, b = points[segment], points[segment + 1]
			roadPart(state, SPINE_PART_NAME, a, b)
			if (b - a).Magnitude >= MIN_LENGTH then
				table.insert(state.segments, { a = a, b = b, polyline = index })
			end
		end
		state.visible = index
		changed = true
	end
	if changed then
		state.lanes = nil
		refreshPieces(state)
	end
	return changed
end

-- Draws the slot's spur if it is routable, inside the budget and not drawn yet. A spur to a
-- spine that is not visible yet still draws (contract). Returns whether it was added.
function RoadGraph.AddSpur(state: State, slotId: string): boolean
	if state.spurs[slotId] ~= nil or not state.spurAllowed[slotId] then
		return false
	end
	local route = state.routes[slotId]
	for index = 2, #route.points do
		roadPart(state, SPUR_PART_NAME, route.points[index - 1], route.points[index])
	end
	state.spurs[slotId] = route
	state.lanes = nil
	refreshPieces(state)
	return true
end

-- Retries pieces whose templates were missing earlier (props replicate or upload later).
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

-- Every centreline the plot can ever have (all spines, every routable spur whether drawn or
-- not), so a seeded tree never lands where a later road will run.
function RoadGraph.AllCentrelines(state: State): { { Vector3 } }
	local lines: { { Vector3 } } = table.clone(state.polylines)
	for _, slotId in state.spurSlotIds do
		table.insert(lines, state.routes[slotId].points)
	end
	return lines
end

-- Sorted slots whose spur fits the budget and meets a spine: the only places a lamp can go.
function RoadGraph.JunctionSlotIds(state: State): { string }
	local slotIds: { string } = {}
	for _, slotId in state.spurSlotIds do
		local junction = state.routes[slotId].junction
		if state.spurAllowed[slotId] and junction ~= nil and junction.polyline ~= nil then
			table.insert(slotIds, slotId)
		end
	end
	return slotIds
end

local function buildLanes(state: State): Lanes
	local nodes: { Vector3 } = {}
	local nodeByKey: { [string]: number } = {}
	local function nodeAt(point: Vector3): number
		local key = keyFor(point)
		local id = nodeByKey[key]
		if id == nil then
			table.insert(nodes, point)
			id = #nodes
			nodeByKey[key] = id
		end
		return id
	end

	-- Road ends that land on another road split it there, so vehicles can turn in.
	local splits: { [number]: { number } } = {}
	local links: { { Vector3 } } = {}
	local attachRadius = state.width / 2 + MIN_LENGTH
	local function attach(point: Vector3, ownPolyline: number?): ()
		local bestIndex: number? = nil
		local bestT = 0
		local bestPoint = point
		local bestDistance = math.huge
		for index, segment in state.segments do
			if segment.polyline == ownPolyline then
				continue
			end
			local closest, t = RoadGraph.ClosestOnSegment(point, segment.a, segment.b)
			local distance = (closest - point).Magnitude
			if distance < bestDistance then
				bestIndex, bestT, bestPoint, bestDistance = index, t, closest, distance
			end
		end
		if bestIndex == nil or bestDistance > attachRadius then
			return
		end
		local list = splits[bestIndex]
		if list == nil then
			list = {}
			splits[bestIndex] = list
		end
		table.insert(list :: { number }, bestT)
		if bestDistance >= MIN_LENGTH then
			table.insert(links, { point, bestPoint })
		end
	end
	for index = 1, state.visible do
		local points = state.polylines[index]
		local drawn = state.spineAllowed[index]
		if drawn > 0 then
			attach(points[1], index)
			attach(points[drawn + 1], index)
		end
	end
	for _, route in state.spurs do
		attach(route.points[#route.points], nil)
	end

	local edgeFrom: { number } = {}
	local edgeTo: { number } = {}
	local seen: { [string]: boolean } = {}
	local function link(a: Vector3, b: Vector3): ()
		if (b - a).Magnitude < MIN_LENGTH then
			return
		end
		local u, v = nodeAt(a), nodeAt(b)
		if u == v then
			return
		end
		local key = if u < v then `{u}:{v}` else `{v}:{u}`
		if seen[key] then
			return
		end
		seen[key] = true
		table.insert(edgeFrom, u)
		table.insert(edgeTo, v)
	end
	for index, segment in state.segments do
		local ts: { number } = splits[index] or {}
		table.insert(ts, 0)
		table.insert(ts, 1)
		table.sort(ts)
		for k = 2, #ts do
			link(segment.a:Lerp(segment.b, ts[k - 1]), segment.a:Lerp(segment.b, ts[k]))
		end
	end
	for _, route in state.spurs do
		for index = 2, #route.points do
			link(route.points[index - 1], route.points[index])
		end
	end
	for _, pair in links do
		link(pair[1], pair[2])
	end

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
	for id = 1, #nodes do
		lanes.outgoing[id] = {}
	end
	local context = state.context
	local frame = context.plotFrame
	local offset = context.config.road.laneOffsetFraction * state.width
	local top = state.thickness
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
	for index, u in edgeFrom do
		local v = edgeTo[index]
		local a, b = nodes[u], nodes[v]
		local right = ((b - a).Unit):Cross(UP)
		local forward = addLane(u, v, a + right * offset, b + right * offset)
		local backward = addLane(v, u, b - right * offset, a - right * offset)
		lanes.reverse[forward] = backward
		lanes.reverse[backward] = forward
	end
	return lanes
end

-- Cached until a spine or spur appears.
function RoadGraph.GetLanes(state: State): Lanes
	local lanes = state.lanes
	if lanes == nil then
		lanes = buildLanes(state)
		state.lanes = lanes
	end
	return lanes :: Lanes
end

function RoadGraph.Destroy(state: State): ()
	for _, part in state.parts do
		part:Destroy()
	end
	for _, piece in state.pieces do
		piece:Destroy()
	end
	table.clear(state.parts)
	table.clear(state.pieces)
	table.clear(state.segments)
	table.clear(state.spurs)
	state.visible = 0
	state.lanes = nil
end

return RoadGraph
