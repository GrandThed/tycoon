--!strict
-- A chase region (docs/INTERFACES.md "L1b Wave 4 — no waits, no walls", rulings L1b-W4-1, -2,
-- -14 to -17): a set of flat rectangles at one height (an open camp's floor and the road cells
-- round it) that a camp's raiders may walk, as one union. Two cells whose rectangles overlap are
-- neighbours, and their overlap is the door between them; the cells form a tree, so the way from
-- any cell to any other is one list of doors, worked out once by Build.
--
-- Pure on purpose, as CampBrain is: tables, numbers and Vector3 values within the harness shim
-- (X Y Z, Vector3.new); no Instance, no clock and no yield. The server (CrowdBrain, CrowdService),
-- the client (CrowdRenderer's drawn charge) and tools/crowd_harness/stage_mirror.luau load this
-- one file, and tools/sim_range.py mirrors it rule by rule: change both. Bounds use
-- math.min(math.max(...)), never math.clamp, which throws when rounding leaves min over max.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local HitShapes = require(sharedFolder:WaitForChild("HitShapes"))
local Types = require(sharedFolder:WaitForChild("Types"))

-- Edges are included a hair either side: a body clamped onto an inset edge lands a rounding error
-- one way or the other, and must still count as inside.
local EPS = 1e-6

local Region = {}

local function isFinite(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

local function validCell(cell: any): boolean
	return typeof(cell) == "table"
		and isFinite(cell.x)
		and isFinite(cell.z)
		and isFinite(cell.hx)
		and isFinite(cell.hz)
		and cell.hx > 0
		and cell.hz > 0
end

-- The overlap of two rectangles on each axis: its widths and its centre. Widths of 0 or less mean
-- the two do not overlap on that axis (a shared edge is a width of 0).
local function overlap(a: Types.CampRect, b: Types.CampRect): (number, number, number, number)
	local loX = math.max(a.x - a.hx, b.x - b.hx)
	local hiX = math.min(a.x + a.hx, b.x + b.hx)
	local loZ = math.max(a.z - a.hz, b.z - b.hz)
	local hiZ = math.min(a.z + a.hz, b.z + b.hz)
	return hiX - loX, hiZ - loZ, (loX + hiX) / 2, (loZ + hiZ) / 2
end

-- Cells i < j that are neighbours, as Build and Problems both count them.
local function neighbours(a: any, b: any): boolean
	if not validCell(a) or not validCell(b) then
		return false
	end
	local wideX, wideZ = overlap(a, b)
	return wideX > EPS and wideZ > EPS
end

-- Inside one cell inset by `radius` on each axis (a cell narrower than the body is a line).
local function insideCell(cell: Types.CampRect, x: number, z: number, radius: number): boolean
	local limitX = math.max(cell.hx - radius, 0)
	local limitZ = math.max(cell.hz - radius, 0)
	return math.abs(x - cell.x) <= limitX + EPS and math.abs(z - cell.z) <= limitZ + EPS
end

-- The neighbours, their doors, and the next hop and hop count from every cell to every other, by
-- breadth-first search from each cell with its neighbours taken in index order. A cell no path
-- reaches has next 0 and hops math.huge. A malformed list never throws: a cell that is not a whole
-- finite rectangle simply has no neighbour (Problems names it).
function Region.Build(cells: { Types.CampRect }): Types.RegionGraph
	local count = if typeof(cells) == "table" then #cells else 0
	local nextHop: { { number } } = {}
	local hops: { { number } } = {}
	local doors: { [number]: { [number]: Types.ArenaPoint } } = {}
	local adjacent: { { number } } = {}
	for i = 1, count do
		doors[i] = {}
		adjacent[i] = {}
	end
	for i = 1, count do
		for j = i + 1, count do
			if neighbours(cells[i], cells[j]) then
				local _, _, centreX, centreZ = overlap(cells[i], cells[j])
				local door = { x = centreX, z = centreZ }
				doors[i][j] = door
				doors[j][i] = door
				table.insert(adjacent[i], j)
				table.insert(adjacent[j], i)
			end
		end
	end
	-- adjacent[k] is in index order: every i < k was inserted before any j > k.
	for i = 1, count do
		local rowNext = table.create(count, 0)
		local rowHops = table.create(count, math.huge)
		rowNext[i] = i
		rowHops[i] = 0
		local queue = { i }
		local head = 1
		while head <= #queue do
			local at = queue[head]
			head += 1
			for _, other in adjacent[at] do
				if rowHops[other] == math.huge then
					rowHops[other] = rowHops[at] + 1
					rowNext[other] = if at == i then other else rowNext[at]
					table.insert(queue, other)
				end
			end
		end
		nextHop[i] = rowNext
		hops[i] = rowHops
	end
	return {
		cells = if typeof(cells) == "table" then cells else {},
		next = nextHop,
		hops = hops,
		doors = doors,
	}
end

-- One line per problem: no cells; a cell that is not a whole finite rectangle with half sizes over
-- 0; a door narrower than minDoor on either axis; a cell no path joins to cell 1; a cycle (once
-- every cell is joined, a tree has exactly one neighbour pair fewer than it has cells).
function Region.Problems(cells: { Types.CampRect }, minDoor: number): { string }
	local problems: { string } = {}
	local count = if typeof(cells) == "table" then #cells else 0
	if count == 0 then
		table.insert(problems, "region: no cells")
		return problems
	end
	for k = 1, count do
		if not validCell(cells[k]) then
			table.insert(
				problems,
				`region cell {k}: a non-finite value, or a half size of 0 or less`
			)
		end
	end
	local pairCount = 0
	for i = 1, count do
		for j = i + 1, count do
			if neighbours(cells[i], cells[j]) then
				pairCount += 1
				local wideX, wideZ = overlap(cells[i], cells[j])
				if wideX < minDoor - EPS or wideZ < minDoor - EPS then
					table.insert(
						problems,
						`region cells {i} and {j}: a door of {wideX} x {wideZ} studs, under {minDoor} on an axis`
					)
				end
			end
		end
	end
	local graph = Region.Build(cells)
	local joined = true
	for k = 2, count do
		if graph.hops[1][k] == math.huge then
			joined = false
			table.insert(problems, `region cell {k}: not joined to cell 1`)
		end
	end
	if joined and pairCount ~= count - 1 then
		table.insert(
			problems,
			`region: the cells form a cycle ({pairCount} neighbour pairs for {count} cells, a tree has {count - 1})`
		)
	end
	return problems
end

-- The flat distance from (x, z) to the union: 0 inside or on an edge; math.huge with no cells.
function Region.Distance(cells: { Types.CampRect }, x: number, z: number): number
	local best = math.huge
	for _, cell in cells do
		local distance = HitShapes.FlatToRect(x, z, cell.x, cell.z, cell.hx, cell.hz)
		if distance < best then
			best = distance
		end
	end
	return best
end

-- Does a body of `radius` at `point` stand wholly in some cell (edges included)?
function Region.Inside(cells: { Types.CampRect }, point: Vector3, radius: number): boolean
	for _, cell in cells do
		if insideCell(cell, point.X, point.Z, radius) then
			return true
		end
	end
	return false
end

-- Where a body of `radius` may stand nearest `point`: the point itself when it is inside, else the
-- nearest point (on the flat) of the cells inset by the radius; the first cell strictly nearer
-- wins a tie. Y is the point's. No cells: the point.
function Region.Clamp(cells: { Types.CampRect }, point: Vector3, radius: number): Vector3
	if #cells == 0 or Region.Inside(cells, point, radius) then
		return point
	end
	local x = point.X
	local z = point.Z
	local bestX = x
	local bestZ = z
	local best = math.huge
	for _, cell in cells do
		local limitX = math.max(cell.hx - radius, 0)
		local limitZ = math.max(cell.hz - radius, 0)
		local cx = math.min(math.max(x, cell.x - limitX), cell.x + limitX)
		local cz = math.min(math.max(z, cell.z - limitZ), cell.z + limitZ)
		local dx = cx - x
		local dz = cz - z
		local squared = dx * dx + dz * dz
		if squared < best then
			best = squared
			bestX = cx
			bestZ = cz
		end
	end
	return Vector3.new(bestX, point.Y, bestZ)
end

-- The stretch [t0, t1] of the ray from (x, z) along (hx, hz) inside one inset cell; t0 > t1 when
-- the ray misses it. An axis the heading does not move along bounds nothing while the start is
-- within the cell on it, and excludes the cell otherwise.
local function slab(
	cell: Types.CampRect,
	x: number,
	z: number,
	headX: number,
	headZ: number,
	radius: number
): (number, number)
	local t0 = -math.huge
	local t1 = math.huge
	local limitX = math.max(cell.hx - radius, 0)
	local limitZ = math.max(cell.hz - radius, 0)
	if headX > 0 then
		t0 = math.max(t0, (cell.x - limitX - x) / headX)
		t1 = math.min(t1, (cell.x + limitX - x) / headX)
	elseif headX < 0 then
		t0 = math.max(t0, (cell.x + limitX - x) / headX)
		t1 = math.min(t1, (cell.x - limitX - x) / headX)
	elseif math.abs(x - cell.x) > limitX + EPS then
		return 1, 0
	end
	if headZ > 0 then
		t0 = math.max(t0, (cell.z - limitZ - z) / headZ)
		t1 = math.min(t1, (cell.z + limitZ - z) / headZ)
	elseif headZ < 0 then
		t0 = math.max(t0, (cell.z + limitZ - z) / headZ)
		t1 = math.min(t1, (cell.z - limitZ - z) / headZ)
	elseif math.abs(z - cell.z) > limitZ + EPS then
		return 1, 0
	end
	return t0, t1
end

-- How far a body of `radius` runs from `from` along the flat unit `heading` and stays in the union
-- of the inset cells: 0 from outside it or with no heading. The run takes the far end of every
-- cell's stretch that begins within what it has already covered, so it passes through a door and
-- stops where the union ends (a U-bend's void). With one cell it is CrowdBrain's old floor runway
-- exactly. Allocates nothing.
function Region.Runway(
	cells: { Types.CampRect },
	from: Vector3,
	heading: Vector3,
	radius: number
): number
	local headX = heading.X
	local headZ = heading.Z
	if (headX == 0 and headZ == 0) or not Region.Inside(cells, from, radius) then
		return 0
	end
	local x = from.X
	local z = from.Z
	local reach = 0
	local grew = true
	while grew do
		grew = false
		for _, cell in cells do
			local t0, t1 = slab(cell, x, z, headX, headZ, radius)
			if t0 <= t1 and t0 <= reach + EPS and t1 > reach then
				reach = t1
				grew = true
			end
		end
	end
	return reach
end

-- Where a body of `radius` at `from` should walk to reach `goal` inside the region: with both
-- clamped into it, the cell the body stands in and the cell the goal lies in that are the fewest
-- hops apart (ties: the lowest body cell, then the lowest goal cell). In one cell, or with no way
-- between them: the clamped goal, false. Otherwise the door to the next cell on the way, at the
-- body's own height, true; the caller seeks a door with a stop distance of 0. A body standing in a
-- door is in both cells, so it takes the one nearer the goal and heads for the next door.
function Region.Toward(
	graph: Types.RegionGraph,
	from: Vector3,
	goal: Vector3,
	radius: number
): (Vector3, boolean)
	local cells = graph.cells
	local g = Region.Clamp(cells, goal, radius)
	local f = Region.Clamp(cells, from, radius)
	local bestHops = math.huge
	local bestI = 0
	local bestJ = 0
	for i, cellI in cells do
		if not insideCell(cellI, f.X, f.Z, radius) then
			continue
		end
		local row = graph.hops[i]
		if row == nil then
			continue
		end
		for j, cellJ in cells do
			local hops = row[j]
			if hops ~= nil and hops < bestHops and insideCell(cellJ, g.X, g.Z, radius) then
				bestHops = hops
				bestI = i
				bestJ = j
			end
		end
	end
	if bestI == 0 or bestI == bestJ then
		return g, false
	end
	local step = graph.next[bestI][bestJ]
	local door = graph.doors[bestI][step]
	if door == nil then
		return g, false
	end
	return Vector3.new(door.x, from.Y, door.z), true
end

return Region
