--!strict
-- The city fabric (docs/INTERFACES.md "M12 contracts" → "src/shared/CityFabric.luau"): how far
-- each parcel has developed, and the distance tests that clear the wild layer around the town.
-- Wave 3.2 adds the rules a tiles era brought: the stage a level starts from, which building site
-- a lot shows, the prop swaps of a city-changer slot, and the ground the highway ring clears.
--
-- Pure: numbers, strings and tables only, with no Vector3 and no Roblox globals or services. This
-- lets tools/cityfabric.py mirror it one to one and every client derive the same town from the
-- same owned slots, tier and visible stretches. Every tunable arrives as an argument.

-- Structural copies of Types.FabricParcel, Types.FabricLane and Types.FabricPullConfig: requiring
-- Types would need `script`, which purity forbids. The old solver compares nested tables
-- invariantly, so these must stay field for field in lockstep with Types.luau, or callers passing
-- Types.* tables stop typechecking.
type FabricParcel = {
	x: number,
	z: number,
	rotationY: number,
	size: "small" | "medium" | "narrow",
	stretch: string,
	along: number,
	row: number,
	front: number,
	lane: number?,
	laneAlong: number?,
}
type FabricLane = { points: { { number } }, stretch: string, along: number }
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
-- A segment clears whatever comes closer than its `margin` to it, or than the mask's `streetClear`
-- when it carries none (a street or a spur; wave 2.4's lane legs bring their own).
export type FabricSegment = { ax: number, az: number, bx: number, bz: number, margin: number? }
export type FabricMask = {
	rects: { FabricRect },
	segments: { FabricSegment },
	streetClear: number,
}
-- Wave 3.2: one `fabric.swaps` entry as ValidSwaps keeps it; `districts` is a set, nil for every
-- district.
export type FabricSwap = {
	requiresSlot: string,
	suffix: string,
	districts: { [string]: boolean }?,
}
-- Wave 3.2: the highway ramp as RingRects reads it: the ring cell it leaves as { x, z } and the
-- way it runs into the city ("+X" | "-X" | "+Z" | "-Z").
export type RingRamp = { cell: { number }, direction: string }

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
-- The contract's value for an absent `fabric.levelStages`: a level-2 parcel starts from stage 0,
-- level 3 from stage 1 and level 4 from stage 2, which is the rule every era had before wave 3.1.
local DEFAULT_LEVEL_STAGES = { 0, 1, 2 }
-- A ramp direction as a lattice step { x, z }.
local RAMP_STEPS: { [string]: { number } } = {
	["+X"] = { 1, 0 },
	["-X"] = { -1, 0 },
	["+Z"] = { 0, 1 },
	["-Z"] = { 0, -1 },
}

local CityFabric = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- The length of a table that is a plain array (keys 1..n and nothing else), nil for anything else.
-- A JSON object arrives as a table with string keys, which no list-shaped config value may be.
local function arrayLength(value: any): number?
	if type(value) ~= "table" then
		return nil
	end
	local count = 0
	for key in value do
		if type(key) ~= "number" then
			return nil
		end
		count += 1
	end
	return if count == #value then count else nil
end

-- A config entry by parcel size, nil for a size the entry leaves out or does not know.
local function forSize(entry: any, size: string): any
	if size == "small" or size == "medium" or size == "narrow" then
		return entry[size]
	end
	return nil
end

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
			-- Wave 2.4: a lot on a lane is reached through the lane's mouth, so it stands its
			-- `laneAlong` further from every landmark than the mouth does.
			local laneAlong = if parcel.lane ~= nil then parcel.laneAlong or 0 else 0
			for landmarkIndex, landmark in landmarks do
				local distance = parcelDistance(
					landmarkDistances[landmarkIndex],
					stretch,
					parcel.along
				) + laneAlong
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

-- Wave 2.4: how far along lane `laneIndex` a road is drawn, in studs of arc from its mouth: as far
-- as the far edge of the frontage of the farthest of its lots that has at least a building site
-- (`laneAlong` + half its frontage, `sizes[size][1]`), never past the lane's end, and 0 while none
-- has. Its lots are the parcels naming it by `lane`; `levels[i]` is parcel i's level. Only a lot
-- that can be drawn counts: its index within `budget` (the near plots' parcel budget) and its size
-- one `sizes` has a footprint for. Lots are visited in index order.
function CityFabric.LaneReach(
	lane: FabricLane,
	laneIndex: number,
	parcels: { FabricParcel },
	levels: { number },
	sizes: { [string]: { number } },
	budget: number
): number
	local length = 0
	local points = lane.points
	for index = 2, #points do
		local dx = points[index][1] - points[index - 1][1]
		local dz = points[index][2] - points[index - 1][2]
		length += math.sqrt(dx * dx + dz * dz)
	end
	local reach = 0
	for index, parcel in parcels do
		local laneAlong = parcel.laneAlong
		local footprint = sizes[parcel.size]
		local level = levels[index]
		if
			parcel.lane == laneIndex
			and laneAlong ~= nil
			and index <= budget
			and footprint ~= nil
			and level ~= nil
			and level >= 1
		then
			reach = math.max(reach, laneAlong + footprint[1] / 2)
		end
	end
	return math.min(reach, length)
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

-- True when a point of `radius` falls inside any rect's margin, or within any segment's own margin
-- (`streetClear` for one that carries none) ("Clearing").
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
		local margin = segment.margin or mask.streetClear
		if CityFabric.SegmentDistance(px, pz, segment) - radius < margin then
			return true
		end
	end
	return false
end

-- Wave 3.1 `fabric.levelStages`: the stage a parcel at `level` (2 or more) shows before the height
-- cap lowers it, for a prop of `stageCount` stages. Level L starts from entry L - 1 of the list;
-- past its end each further level adds one stage to the last entry; the result never passes the
-- last stage the prop has. The list counts only as a non-empty array of whole numbers of 0 or
-- more: anything else reads as absent, which is { 0, 1, 2 } and so `level - 2`, the rule before
-- the key existed.
function CityFabric.LevelStage(levelStages: any, level: number, stageCount: number): number
	local stages = DEFAULT_LEVEL_STAGES
	local length = arrayLength(levelStages)
	if length ~= nil and length > 0 then
		local whole = true
		for _, entry in levelStages do
			whole = whole and finite(entry) and entry >= 0 and entry == math.floor(entry)
		end
		if whole then
			stages = levelStages
		end
	end
	local index = math.floor(level) - 1
	local stage = 0
	if index >= 1 then
		local last = #stages
		stage = if index <= last then stages[index] else stages[last] + (index - last)
	end
	return math.max(math.min(stage, stageCount - 1), 0)
end

-- Wave 3.1 `fabric.siteVariants`: the building site a level-1 parcel shows. Where its size has a
-- non-empty list, parcel `index` takes list[((index - 1) % #list) + 1], as it takes a district
-- prop, and an entry there that is not a name shows nothing; any other size shows `sites[size]`.
-- Nil is "nothing to spawn". Either table may be missing or malformed.
function CityFabric.SiteProp(sites: any, siteVariants: any, size: string, index: number): string?
	if type(siteVariants) == "table" then
		local list = forSize(siteVariants, size)
		if type(list) == "table" and #list > 0 then
			local prop = list[(index - 1) % #list + 1]
			return if type(prop) == "string" then prop else nil
		end
	end
	if type(sites) ~= "table" then
		return nil
	end
	local prop = forSize(sites, size)
	return if type(prop) == "string" then prop else nil
end

-- Wave 3.2 `fabric.swaps`: the well-formed entries in list order. An entry needs a slot name and a
-- non-empty suffix; `districts`, when present, must be a list of names. Anything else is skipped,
-- and a value that is not a list has no entries at all.
function CityFabric.ValidSwaps(value: any): { FabricSwap }
	local swaps: { FabricSwap } = {}
	if type(value) ~= "table" then
		return swaps
	end
	for index = 1, #value do
		local entry = value[index]
		if type(entry) ~= "table" then
			continue
		end
		local slot, suffix, listed = entry.requiresSlot, entry.suffix, entry.districts
		if type(slot) ~= "string" or type(suffix) ~= "string" or suffix == "" then
			continue
		end
		local districts: { [string]: boolean }? = nil
		if listed ~= nil then
			local names: { [string]: boolean } = {}
			local wellFormed = arrayLength(listed) ~= nil
			if wellFormed then
				for _, name in listed do
					if type(name) == "string" then
						names[name] = true
					else
						wellFormed = false
					end
				end
			end
			if not wellFormed then
				continue
			end
			districts = names
		end
		table.insert(swaps, { requiresSlot = slot, suffix = suffix, districts = districts })
	end
	return swaps
end

-- Wave 3.2: the prop a building parcel shows once the swaps have had their say. Each swap whose
-- slot is in `owned` (and whose `districts`, if it lists any, hold the `district` of the parcel)
-- turns the prop into `<prop><suffix>` when `exists` says that prop can be spawned, in list order,
-- each on the name the one before produced. The stage belongs to the caller and does not change:
-- a twin shares its body with the original. Only buildings are asked about; a site never swaps.
function CityFabric.SwappedProp(
	prop: string,
	district: string?,
	swaps: { FabricSwap },
	owned: { [string]: boolean },
	exists: (prop: string) -> boolean
): string
	local shown = prop
	for _, swap in swaps do
		local districts = swap.districts
		if not owned[swap.requiresSlot] then
			continue
		end
		if districts ~= nil and (district == nil or not districts[district]) then
			continue
		end
		local twin = shown .. swap.suffix
		if exists(twin) then
			shown = twin
		end
	end
	return shown
end

-- Wave 3.1 (rulings): the ground the highway ring stands on, as clearing rects with margin 0 (the
-- mask grows them once the slot that builds the highway is owned). The deck band is `ring` plus or
-- minus half a cell on all four sides; the ramp adds `rampCells` whole cells from its ring cell
-- inward. Empty for a ring or a pitch that is not a positive finite number; a ramp without a known
-- direction or a two-number cell adds nothing.
function CityFabric.RingRects(
	ring: any,
	tileStuds: any,
	ramp: RingRamp?,
	rampCells: any
): { FabricRect }
	local rects: { FabricRect } = {}
	if not (finite(ring) and ring > 0 and finite(tileStuds) and tileStuds > 0) then
		return rects
	end
	local half = tileStuds / 2
	local reach = ring + half
	rects[1] = { x = 0, z = -ring, hx = reach, hz = half, rotationY = 0, margin = 0 }
	rects[2] = { x = 0, z = ring, hx = reach, hz = half, rotationY = 0, margin = 0 }
	rects[3] = { x = -ring, z = 0, hx = half, hz = reach, rotationY = 0, margin = 0 }
	rects[4] = { x = ring, z = 0, hx = half, hz = reach, rotationY = 0, margin = 0 }
	local step = if type(ramp) == "table" then RAMP_STEPS[ramp.direction] else nil
	local cell = if type(ramp) == "table" then ramp.cell else nil
	if
		step ~= nil
		and type(cell) == "table"
		and #cell == 2
		and finite(cell[1])
		and finite(cell[2])
		and finite(rampCells)
	then
		for k = 1, math.floor(rampCells) do
			table.insert(rects, {
				x = cell[1] + step[1] * tileStuds * k,
				z = cell[2] + step[2] * tileStuds * k,
				hx = half,
				hz = half,
				rotationY = 0,
				margin = 0,
			})
		end
	end
	return rects
end

return CityFabric
