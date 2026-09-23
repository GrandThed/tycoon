--!strict
-- The one pedestrian loop for the whole map (docs/INTERFACES.md "Wave 2c — Pedestrians"). Shaped
-- like Traffic and budgeted apart from it: walkers are anchored, sealed prop clones strolling the
-- RoadGraph.WalkLanes of their plot, never physics, and two clients may see different positions.
--
-- At a lane end a walker takes a random outgoing lane (a dead end turns it back). The next lane
-- usually starts somewhere else -- the far pavement, the kerb of the street a spur meets -- so the
-- walker strolls straight across to it, which is how it crosses a carriageway at a junction.
--
-- Hot path (per Heartbeat, only while at least one walker exists): advance each walker, add the
-- bob, write one CFrame per part into the pre-allocated `cframes` array, then a single
-- BulkMoveTo. The arrays are rebuilt only when walkers are added or removed; the loop allocates
-- no tables.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local RoadGraph = require(script.Parent:WaitForChild("RoadGraph"))

type Lanes = RoadGraph.Lanes

-- A frame hitch must not spin through a tiny loop of lanes; past this the walker waits a frame.
local MAX_LANE_HOPS_PER_FRAME = 8
-- A gap between one lane's end and the next lane's start shorter than this is the same spot.
local CROSS_MIN = 0.05
-- How quickly a figure turns to its new heading (per second, exponential): quick enough that it
-- never walks sideways, slow enough that a corner is not a snap.
local TURN_RATE = 10
local HALF_TURN = math.pi
local FULL_TURN = 2 * math.pi

type Walker = {
	plotId: number,
	model: Model,
	lanes: Lanes,
	lane: number,
	distance: number,
	speed: number,
	bobHeight: number,
	bobRate: number, -- radians of |sin| per second: one hop per half period
	elapsed: number,
	-- A straight stroll between two lanes (or back onto the network after SetLanes).
	crossing: boolean,
	crossFrom: Vector3,
	crossDirection: Vector3,
	crossLength: number,
	crossDistance: number,
	resumeAt: number, -- where on `lane` the walker picks up once the stroll is done
	renderYaw: number,
	partStart: number,
	partCount: number,
	partOffsets: { CFrame },
	modelParts: { BasePart },
}

local walkers: { Walker } = {}
local parts: { BasePart } = {}
local offsets: { CFrame } = {}
local cframes: { CFrame } = {}
local heartbeat: RBXScriptConnection? = nil
-- Unseeded on purpose: routes and bob phases are cosmetic and allowed to differ per client.
local rng = Random.new()

local function wrapAngle(angle: number): number
	return (angle + HALF_TURN) % FULL_TURN - HALF_TURN
end

local function nextLane(lanes: Lanes, lane: number): number
	local back = lanes.reverse[lane]
	local outgoing = lanes.outgoing[lanes.to[lane]]
	local choices = #outgoing
	for _, candidate in outgoing do
		if candidate == back then
			choices -= 1
		end
	end
	if choices <= 0 then
		return back
	end
	local pick = rng:NextInteger(1, choices)
	for _, candidate in outgoing do
		if candidate ~= back then
			pick -= 1
			if pick == 0 then
				return candidate
			end
		end
	end
	return back
end

local function frameFor(position: Vector3, yaw: number): CFrame
	local c, s = math.cos(yaw), math.sin(yaw)
	-- CFrame.Angles(0, yaw, 0) + position in one constructor (one allocation instead of three).
	return CFrame.new(position.X, position.Y, position.Z, c, 0, s, 0, 1, 0, -s, 0, c)
end

local function startCrossing(walker: Walker, from: Vector3, to: Vector3, resumeAt: number): ()
	local delta = to - from
	local length = delta.Magnitude
	if length < CROSS_MIN then
		walker.crossing = false
		walker.distance = resumeAt
		return
	end
	walker.crossing = true
	walker.crossFrom = from
	walker.crossDirection = delta / length
	walker.crossLength = length
	walker.crossDistance = 0
	walker.resumeAt = resumeAt
end

local function drawnPosition(walker: Walker): Vector3
	if walker.crossing then
		return walker.crossFrom + walker.crossDirection * walker.crossDistance
	end
	local lanes = walker.lanes
	return lanes.origin[walker.lane] + lanes.direction[walker.lane] * walker.distance
end

local function rebuildArrays(): ()
	table.clear(parts)
	table.clear(offsets)
	table.clear(cframes)
	for _, walker in walkers do
		walker.partStart = #parts + 1
		walker.partCount = #walker.modelParts
		for index, part in walker.modelParts do
			table.insert(parts, part)
			table.insert(offsets, walker.partOffsets[index])
			table.insert(cframes, part.CFrame)
		end
	end
end

-- Forward-declared so a failed BulkMoveTo can prune and the loop can stop itself.
local updateConnection: () -> ()

local function pruneDetached(): ()
	for index = #walkers, 1, -1 do
		if not walkers[index].model:IsDescendantOf(Workspace) then
			walkers[index].model:Destroy()
			table.remove(walkers, index)
		end
	end
	rebuildArrays()
	updateConnection()
end

local function advance(walker: Walker, travel: number): ()
	local lanes = walker.lanes
	local hops = 0
	while travel > 0 do
		if walker.crossing then
			local left = walker.crossLength - walker.crossDistance
			if travel < left then
				walker.crossDistance += travel
				return
			end
			travel -= left
			walker.crossing = false
			walker.distance = walker.resumeAt
			continue
		end
		local lane = walker.lane
		local left = lanes.length[lane] - walker.distance
		if travel < left then
			walker.distance += travel
			return
		end
		hops += 1
		if hops > MAX_LANE_HOPS_PER_FRAME then
			walker.distance = lanes.length[lane]
			return
		end
		travel -= left
		local laneEnd = lanes.origin[lane] + lanes.direction[lane] * lanes.length[lane]
		local following = nextLane(lanes, lane)
		walker.lane = following
		startCrossing(walker, laneEnd, lanes.origin[following], 0)
	end
end

local function step(dt: number): ()
	local turn = math.min(dt * TURN_RATE, 1)
	for _, walker in walkers do
		advance(walker, walker.speed * dt)
		walker.elapsed += dt
		local lanes = walker.lanes
		local targetYaw = if walker.crossing
			then math.atan2(-walker.crossDirection.X, -walker.crossDirection.Z)
			else lanes.yaw[walker.lane]
		local yaw = walker.renderYaw + wrapAngle(targetYaw - walker.renderYaw) * turn
		walker.renderYaw = yaw
		local position = drawnPosition(walker)
		if walker.bobHeight > 0 then
			position += Vector3.yAxis * (walker.bobHeight * math.abs(
				math.sin(walker.elapsed * walker.bobRate)
			))
		end
		local frame = frameFor(position, yaw)
		for index = walker.partStart, walker.partStart + walker.partCount - 1 do
			cframes[index] = frame * offsets[index]
		end
	end
	-- Method reference rather than a closure keeps the call allocation-free. It only fails if a
	-- part left the DataModel behind our back; prune once instead of erroring every frame.
	local ok =
		pcall(Workspace.BulkMoveTo, Workspace, parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	if not ok then
		pruneDetached()
	end
end

updateConnection = function(): ()
	if #walkers > 0 then
		if heartbeat == nil then
			heartbeat = RunService.Heartbeat:Connect(step)
		end
		return
	end
	local connection = heartbeat
	if connection then
		connection:Disconnect()
		heartbeat = nil
	end
end

local function removeWhere(plotId: number): ()
	local removed = false
	for index = #walkers, 1, -1 do
		local walker = walkers[index]
		if walker.plotId == plotId then
			walker.model:Destroy()
			table.remove(walkers, index)
			removed = true
		end
	end
	if removed then
		rebuildArrays()
		updateConnection()
	end
end

local Walkers = {}

-- Replaces the plot's walkers with `models` (pivoted with their bottom-centre at CFrame.identity,
-- as PropFactory.Spawn(…, CFrame.identity, nil) leaves them), spaced evenly along the walk lanes,
-- alternating directions. `bobHeight` studs of hop `bobHz` times a second; none under
-- Theme.reducedMotion, where walkers glide. Walkers owns the models from here on and destroys any
-- it has no room or lane for; `mapWalkerBudget` is the whole-map cap (CityDressing.json
-- budget.walkersMap). Returns how many walkers were placed.
function Walkers.SpawnPlot(
	plotId: number,
	lanes: Lanes,
	models: { Model },
	speed: number,
	bobHeight: number,
	bobHz: number,
	parent: Instance,
	mapWalkerBudget: number
): number
	removeWhere(plotId)

	-- Each two-way lane pair counted once (the lane with the lower id of its pair).
	local total = 0
	for lane = 1, lanes.count do
		if lane < lanes.reverse[lane] then
			total += lanes.length[lane]
		end
	end
	local room = mapWalkerBudget - #walkers
	local count = math.min(#models, room)
	if total <= 0 or count <= 0 then
		for _, model in models do
			model:Destroy()
		end
		return 0
	end

	local bob = if Theme.reducedMotion then 0 else math.max(bobHeight, 0)
	for index, model in models do
		if index > count then
			model:Destroy()
			continue
		end
		local target = (index - 0.5) * total / count
		local chosen = 0
		local along = 0
		for lane = 1, lanes.count do
			if lane < lanes.reverse[lane] then
				chosen = lane
				along = target
				if target <= lanes.length[lane] then
					break
				end
				target -= lanes.length[lane]
			end
		end
		local lane, distance = chosen, along
		if index % 2 == 0 then
			lane = lanes.reverse[chosen]
			distance = lanes.length[chosen] - along
		end

		local modelParts: { BasePart } = {}
		local partOffsets: { CFrame } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(modelParts, descendant)
				table.insert(partOffsets, descendant.CFrame)
			end
		end
		local walker: Walker = {
			plotId = plotId,
			model = model,
			lanes = lanes,
			lane = lane,
			distance = math.clamp(distance, 0, lanes.length[lane]),
			speed = math.max(speed, 0),
			bobHeight = bob,
			bobRate = math.pi * math.max(bobHz, 0),
			-- A random start in the stride, so a street of walkers does not hop in step.
			elapsed = rng:NextNumber() * FULL_TURN,
			crossing = false,
			crossFrom = Vector3.zero,
			crossDirection = Vector3.zAxis,
			crossLength = 0,
			crossDistance = 0,
			resumeAt = 0,
			renderYaw = lanes.yaw[lane],
			partStart = 0,
			partCount = 0,
			partOffsets = partOffsets,
			modelParts = modelParts,
		}
		-- Placed before parenting so the model never flashes at the world origin.
		local frame = frameFor(drawnPosition(walker), walker.renderYaw)
		for partIndex, part in modelParts do
			part.CFrame = frame * partOffsets[partIndex]
		end
		model.Parent = parent
		table.insert(walkers, walker)
	end
	rebuildArrays()
	updateConnection()
	return count
end

-- The plot's streets changed: each of its walkers strolls from where it is drawn onto the nearest
-- point of the new lanes and carries on from there. An empty graph removes them.
function Walkers.SetLanes(plotId: number, lanes: Lanes): ()
	if lanes.count == 0 then
		removeWhere(plotId)
		return
	end
	for _, walker in walkers do
		if walker.plotId ~= plotId then
			continue
		end
		local drawn = drawnPosition(walker)
		local bestLane = 1
		local bestAlong = 0
		local bestDistance = math.huge
		for lane = 1, lanes.count do
			local along = math.clamp(
				(drawn - lanes.origin[lane]):Dot(lanes.direction[lane]),
				0,
				lanes.length[lane]
			)
			local gap = (lanes.origin[lane] + lanes.direction[lane] * along - drawn).Magnitude
			if gap < bestDistance then
				bestLane, bestAlong, bestDistance = lane, along, gap
			end
		end
		walker.lanes = lanes
		walker.lane = bestLane
		startCrossing(
			walker,
			drawn,
			lanes.origin[bestLane] + lanes.direction[bestLane] * bestAlong,
			bestAlong
		)
	end
end

-- Walkers the whole map can still take under `mapWalkerBudget`.
function Walkers.Room(mapWalkerBudget: number): number
	return math.max(mapWalkerBudget - #walkers, 0)
end

function Walkers.ClearPlot(plotId: number): ()
	removeWhere(plotId)
end

function Walkers.Count(plotId: number): number
	local count = 0
	for _, walker in walkers do
		if walker.plotId == plotId then
			count += 1
		end
	end
	return count
end

return Walkers
