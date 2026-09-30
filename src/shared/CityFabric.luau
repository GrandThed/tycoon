--!strict
-- The city fabric (docs/INTERFACES.md "M12 contracts" → "src/shared/CityFabric.luau"): how far
-- each parcel has developed, and the distance tests that clear the wild layer around the town.
--
-- Pure: numbers, strings and tables only, with no Vector3 and no Roblox globals or services. This
-- lets tools/cityfabric.py mirror it one to one and every client derive the same town from the
-- same owned slots, tier and visible stretches. Every tunable arrives as an argument.

-- Structural copies of Types.FabricParcel and Types.FabricPullConfig: requiring Types would need
-- `script`, which purity forbids. The old solver compares nested tables invariantly, so these must
-- stay field for field in lockstep with Types.luau, or callers passing Types.* tables stop
-- typechecking.
type FabricParcel = {
	x: number,
	z: number,
	rotationY: number,
	size: "small" | "medium" | "narrow",
	stretch: string,
	along: number,
	row: number,
	front: number,
}
type FabricPullConfig = {
	radius: number,
	tierTerm: number,
	thresholds: { number },
	reach: number,
	levelsOverTier: number,
	smallMaxLevel: number,
	rowLag: number?,
}

export type FabricStretch = { from: number, to: number, length: number } -- visible stretches only
export type FabricLandmark = { slotId: string, node: number, district: string }
export type FabricInput = {
	tier: number,
	stretches: { [string]: FabricStretch }, -- keyed by piece id
	landmarks: { FabricLandmark }, -- owned slots that have a district and a join node
	parcels: { FabricParcel },
}
export type FabricParcelState = { level: number, district: string?, governor: string? }
-- Centre (x, z), half extents (hx, hz) in the rect's own frame, turned rotationY degrees like a
-- slot. It clears whatever comes closer than `margin` to its edge.
export type FabricRect = {
	x: number,
	z: number,
	hx: number,
	hz: number,
	rotationY: number,
	margin: number,
}
export type FabricSegment = { ax: number, az: number, bx: number, bz: number }
export type FabricMask = {
	rects: { FabricRect },
	segments: { FabricSegment },
	streetClear: number,
}

type Edge = { node: number, length: number }
-- `nodes` is sorted ascending so the search settles tied nodes in the same order everywhere.
type Graph = { nodes: { number }, edges: { [number]: { Edge } } }
type Distances = { [number]: number } -- node -> network distance; absent = unreachable

-- IsCleared skips any rect whose centre is too far away for it to clear the point, which saves
-- the rotation for most rects. The slack keeps that skip strictly inside the exact test whatever
-- the float rounding, so the answer never changes and the mirror need not copy the skip.
local SKIP_SLACK = 0.01
-- The contract's value for an absent `pull.rowLag`, which is the wave 1 behaviour (a back row one
-- level behind its front).
local DEFAULT_ROW_LAG = 1

local CityFabric = {}

-- Step 1: every visible stretch is an undirected edge.
local function buildGraph(stretches: { [string]: FabricStretch }): Graph
	local nodes: { number } = {}
	local edges: { [number]: { Edge } } = {}
	local function connect(from: number, to: number, length: number)
		local list = edges[from]
		if list == nil then
			list = {}
			edges[from] = list
			table.insert(nodes, from)
		end
		table.insert(list, { node = to, length = length })
	end
	for _, stretch in stretches do
		connect(stretch.from, stretch.to, stretch.length)
		connect(stretch.to, stretch.from, stretch.length)
	end
	table.sort(nodes)
	return { nodes = nodes, edges = edges }
end

-- Dijkstra from any number of sources (node -> starting distance). The plain O(V²) form is enough
-- for graphs of under a hundred nodes, and it is the form the mirror copies: each round settles
-- the nearest unsettled node, the lowest id first among equals.
local function shortestDistances(graph: Graph, sources: Distances): Distances
	local dist: Distances = table.clone(sources)
	local settled: { [number]: boolean } = {}
	while true do
		local best: number? = nil
		local bestDistance = math.huge
		for _, node in graph.nodes do
			local d = dist[node]
			if d ~= nil and d < bestDistance and not settled[node] then
				best = node
				bestDistance = d
			end
		end
		if best == nil then
			break
		end
		settled[best] = true
		for _, edge in graph.edges[best] do
			local candidate = bestDistance + edge.length
			local current = dist[edge.node]
			if current == nil or candidate < current then
				dist[edge.node] = candidate
			end
		end
	end
	return dist
end

-- A parcel's front is `along` studs in from its stretch's `from` end, so it is reached through
-- whichever end is nearer.
local function parcelDistance(dist: Distances, stretch: FabricStretch, along: number): number
	local atFrom = dist[stretch.from]
	local atTo = dist[stretch.to]
	local viaFrom = if atFrom ~= nil then atFrom + along else math.huge
	local viaTo = if atTo ~= nil then atTo + (stretch.length - along) else math.huge
	return math.min(viaFrom, viaTo)
end

local function keepNearest(dist: Distances, node: number, distance: number)
	local current = dist[node]
	if current == nil or distance < current then
		dist[node] = distance
	end
end

local function bySlotId(a: FabricLandmark, b: FabricLandmark): boolean
	if a.slotId ~= b.slotId then
		return a.slotId < b.slotId
	end
	return a.node < b.node
end

-- Each parcel's development level, district and governor ("Develop (normative)", steps 1-8).
-- Index i of the result is parcel i.
function CityFabric.Develop(input: FabricInput, pull: FabricPullConfig): { FabricParcelState }
	local stretches = input.stretches
	local parcels = input.parcels
	local graph = buildGraph(stretches)

	-- Float addition is not associative, so pulls are summed in slot id order: a score that lands
	-- on a threshold then lands the same way on every client and in the mirror, whatever order
	-- the caller listed the landmarks in.
	local landmarks = table.clone(input.landmarks)
	table.sort(landmarks, bySlotId)

	-- Step 2. Landmarks that share a join node share one search.
	local searched: { [number]: Distances } = {}
	local landmarkDistances: { Distances } = {}
	for index, landmark in landmarks do
		local dist = searched[landmark.node]
		if dist == nil then
			dist = shortestDistances(graph, { [landmark.node] = 0 })
			searched[landmark.node] = dist
		end
		landmarkDistances[index] = dist
	end

	-- Steps 3 to 6: pull, score, level, governor.
	local states: { FabricParcelState } = {}
	for index, parcel in parcels do
		local stretch = stretches[parcel.stretch]
		local influence = 0
		local governor: FabricLandmark? = nil
		local governorPull = 0
		if stretch ~= nil then
			for landmarkIndex, landmark in landmarks do
				local distance =
					parcelDistance(landmarkDistances[landmarkIndex], stretch, parcel.along)
				local landmarkPull = math.max(0, 1 - distance / pull.radius)
				if landmarkPull > 0 then
					influence += landmarkPull
					if
						governor == nil
						or landmarkPull > governorPull
						or (landmarkPull == governorPull and landmark.slotId > governor.slotId)
					then
						governor = landmark
						governorPull = landmarkPull
					end
				end
			end
		end
		local score = if governor ~= nil then influence + pull.tierTerm * input.tier else 0
		local level = 0
		for _, threshold in pull.thresholds do
			if score >= threshold then
				level += 1
			end
		end
		level = math.min(level, input.tier + pull.levelsOverTier)
		if parcel.size == "small" then
			level = math.min(level, pull.smallMaxLevel)
		end
		if stretch == nil then
			level = 0
		end
		states[index] = {
			level = level,
			district = if governor ~= nil then governor.district else nil,
			governor = if governor ~= nil then governor.slotId else nil,
		}
	end

	-- Step 7: growth spreads outward. Each pass measures from the landmarks and from the parcels
	-- accepted in earlier passes, so the town never skips a gap wider than `reach`.
	local accepted: { [number]: boolean } = {}
	local acceptedOrder: { number } = {}
	local grew = true
	while grew do
		grew = false
		local sources: Distances = {}
		for _, landmark in landmarks do
			sources[landmark.node] = 0
		end
		for _, index in acceptedOrder do
			local parcel = parcels[index]
			local stretch = stretches[parcel.stretch]
			if stretch ~= nil then
				keepNearest(sources, stretch.from, parcel.along)
				keepNearest(sources, stretch.to, stretch.length - parcel.along)
			end
		end
		local dist = shortestDistances(graph, sources)
		for index, parcel in parcels do
			if parcel.row ~= 1 or accepted[index] or states[index].level < 1 then
				continue
			end
			local stretch = stretches[parcel.stretch]
			if stretch ~= nil and parcelDistance(dist, stretch, parcel.along) <= pull.reach then
				accepted[index] = true
				table.insert(acceptedOrder, index)
				grew = true
			end
		end
	end
	for index, parcel in parcels do
		if parcel.row == 1 and not accepted[index] then
			states[index].level = 0
		end
	end

	-- Step 8: a back-row parcel (row 2 behind row 1, row 3 behind row 2) stays `rowLag` levels
	-- behind the parcel in front of it and takes its kind. The data lists every parcel after its
	-- front, so one pass in index order reads each front's final level. A missing front reads as
	-- level 0.
	local rowLag = pull.rowLag or DEFAULT_ROW_LAG
	for index, parcel in parcels do
		if parcel.row >= 2 then
			local state = states[index]
			local front = states[parcel.front]
			local frontLevel = if front ~= nil then front.level else 0
			state.level = math.max(0, math.min(state.level, frontLevel - rowLag))
			state.district = if front ~= nil then front.district else nil
			state.governor = if front ~= nil then front.governor else nil
		end
	end
	return states
end

-- 0 inside the rect. The point is taken into the rect's frame with the inverse of
-- CFrame.Angles(0, a, 0), which maps local (x, z) to (x·cos a + z·sin a, −x·sin a + z·cos a).
function CityFabric.RectDistance(px: number, pz: number, rect: FabricRect): number
	local angle = math.rad(rect.rotationY)
	local cosA, sinA = math.cos(angle), math.sin(angle)
	local dx, dz = px - rect.x, pz - rect.z
	local lx = dx * cosA - dz * sinA
	local lz = dx * sinA + dz * cosA
	local ox = math.max(math.abs(lx) - rect.hx, 0)
	local oz = math.max(math.abs(lz) - rect.hz, 0)
	return math.sqrt(ox * ox + oz * oz)
end

-- A zero-length segment is its end point.
function CityFabric.SegmentDistance(px: number, pz: number, seg: FabricSegment): number
	local dx, dz = seg.bx - seg.ax, seg.bz - seg.az
	local lengthSq = dx * dx + dz * dz
	local t = 0
	if lengthSq > 0 then
		t = math.max(0, math.min(1, ((px - seg.ax) * dx + (pz - seg.az) * dz) / lengthSq))
	end
	local ex, ez = px - (seg.ax + t * dx), pz - (seg.az + t * dz)
	return math.sqrt(ex * ex + ez * ez)
end

-- True when a point of `radius` falls inside any rect's margin or within `streetClear` of any
-- segment ("Clearing").
function CityFabric.IsCleared(px: number, pz: number, radius: number, mask: FabricMask): boolean
	for _, rect in mask.rects do
		-- No point of a rect lies farther than |hx| + |hz| from its centre.
		local bound = rect.margin + radius + math.abs(rect.hx) + math.abs(rect.hz) + SKIP_SLACK
		local dx, dz = px - rect.x, pz - rect.z
		local outOfReach = bound > 0 and dx * dx + dz * dz >= bound * bound
		if not outOfReach and CityFabric.RectDistance(px, pz, rect) - radius < rect.margin then
			return true
		end
	end
	for _, segment in mask.segments do
		if CityFabric.SegmentDistance(px, pz, segment) - radius < mask.streetClear then
			return true
		end
	end
	return false
end

return CityFabric
