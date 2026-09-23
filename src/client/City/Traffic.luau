--!strict
-- The one vehicle loop for the whole map (docs/INTERFACES.md "M9 contracts — Vehicles").
-- Vehicles are anchored, sealed prop clones moved along RoadGraph lanes; nothing here is
-- physics, and two clients may see different positions.
--
-- Hot path (per Heartbeat, only while at least one vehicle exists): for each vehicle advance
-- speed * dt along its lane, hop to a random next lane at each node (U-turn at dead ends),
-- blend facing and the lane-change offset over vehicles.turnSeconds, write one CFrame per
-- part into the pre-allocated `cframes` array, then a single BulkMoveTo. The arrays are
-- rebuilt only when vehicles are added or removed; the loop allocates no tables.
--
-- Wave 2d spacing: every car on a plot drives at one speed, so two cars that reach a node
-- together would take the same lane and ride fused for the rest of their lives. Each lane keeps
-- the time it is free again (a car entered it and has since moved its own length plus
-- `vehicles.followGap`); a car at a node only takes a free lane -- the U-turn at a dead end too --
-- and waits at the node while none is. A lane's freedom always expires, so a wait never deadlocks.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(script.Parent:WaitForChild("RoadGraph"))

type Lanes = RoadGraph.Lanes

-- A frame hitch must not spin through a tiny loop of lanes; past this the vehicle just parks
-- at the start of its current lane for the frame.
local MAX_LANE_HOPS_PER_FRAME = 8
local HALF_TURN = math.pi
local FULL_TURN = 2 * math.pi
-- The contract's fallback when an era has no `vehicles.followGap` (a stale config file).
local DEFAULT_FOLLOW_GAP = 0.6

type Vehicle = {
	plotId: number,
	model: Model,
	lanes: Lanes,
	-- The free-again time of each lane of `lanes`, shared by every vehicle on that graph.
	freeAt: { number },
	-- Seconds this car keeps a lane it enters: (its length + followGap) / speed.
	hold: number,
	lane: number,
	distance: number,
	speed: number,
	turnSeconds: number,
	blendElapsed: number,
	fromYaw: number,
	blendOffset: Vector3,
	renderYaw: number,
	partStart: number,
	partCount: number,
	-- Part offsets from the model's bottom-centre pivot, captured once at spawn.
	partOffsets: { CFrame },
	modelParts: { BasePart },
}

local vehicles: { Vehicle } = {}
local parts: { BasePart } = {}
local offsets: { CFrame } = {}
local cframes: { CFrame } = {}
local heartbeat: RBXScriptConnection? = nil
-- Seconds of Heartbeat since the module loaded: the clock every lane's free-again time is on.
local clock = 0
-- Keyed weakly by the lane graph, so a graph RoadGraph has dropped takes its array with it.
local freeAtByLanes: { [Lanes]: { number } } = setmetatable({} :: any, { __mode = "k" })
-- Unseeded on purpose: route choices are cosmetic and allowed to differ per client.
local rng = Random.new()

local function numberOr(value: number?, fallback: number): number
	return if type(value) == "number" and value == value then value else fallback
end

local function wrapAngle(angle: number): number
	return (angle + HALF_TURN) % FULL_TURN - HALF_TURN
end

local function freeAtFor(lanes: Lanes): { number }
	local freeAt = freeAtByLanes[lanes]
	if freeAt == nil then
		local created: { number } = table.create(lanes.count, -math.huge)
		freeAtByLanes[lanes] = created
		return created
	end
	return freeAt
end

-- A random free outgoing lane that is not the way back; at a dead end the way back, if it is free.
-- Nil when every candidate is taken, and the car waits at the node for a frame.
local function nextLane(lanes: Lanes, lane: number, freeAt: { number }): number?
	local back = lanes.reverse[lane]
	local outgoing = lanes.outgoing[lanes.to[lane]]
	local forward = 0
	local free = 0
	for _, candidate in outgoing do
		if candidate ~= back then
			forward += 1
			if freeAt[candidate] <= clock then
				free += 1
			end
		end
	end
	if forward == 0 then
		return if freeAt[back] <= clock then back else nil
	end
	if free == 0 then
		return nil
	end
	local pick = rng:NextInteger(1, free)
	for _, candidate in outgoing do
		if candidate ~= back and freeAt[candidate] <= clock then
			pick -= 1
			if pick == 0 then
				return candidate
			end
		end
	end
	return nil
end

-- Marks `lane` taken until a car `along` studs into it has moved its hold clear of the start.
local function claim(vehicle: Vehicle, lane: number, along: number): ()
	local freeAt = vehicle.freeAt
	local freeFrom = clock + vehicle.hold - (if vehicle.speed > 0 then along / vehicle.speed else 0)
	if freeFrom > freeAt[lane] then
		freeAt[lane] = freeFrom
	end
end

local function frameFor(position: Vector3, yaw: number): CFrame
	local c, s = math.cos(yaw), math.sin(yaw)
	-- CFrame.Angles(0, yaw, 0) + position in one constructor (one allocation instead of three).
	return CFrame.new(position.X, position.Y, position.Z, c, 0, s, 0, 1, 0, -s, 0, c)
end

-- A model's extent along its own Z (front -Z), from part offsets taken at an identity pivot.
local function lengthOf(modelParts: { BasePart }, partOffsets: { CFrame }): number
	local low, high = math.huge, -math.huge
	for index, part in modelParts do
		local offset = partOffsets[index]
		local size = part.Size
		local _, _, _, _, _, _, _, _, _, r20, r21, r22 = offset:GetComponents()
		local half = (math.abs(r20) * size.X + math.abs(r21) * size.Y + math.abs(r22) * size.Z) / 2
		low = math.min(low, offset.Z - half)
		high = math.max(high, offset.Z + half)
	end
	return if low <= high then high - low else 0
end

local function rebuildArrays(): ()
	table.clear(parts)
	table.clear(offsets)
	table.clear(cframes)
	for _, vehicle in vehicles do
		vehicle.partStart = #parts + 1
		vehicle.partCount = #vehicle.modelParts
		for index, part in vehicle.modelParts do
			table.insert(parts, part)
			table.insert(offsets, vehicle.partOffsets[index])
			table.insert(cframes, part.CFrame)
		end
	end
end

-- Forward-declared so a failed BulkMoveTo can prune and the loop can stop itself.
local updateConnection: () -> ()

local function pruneDetached(): ()
	for index = #vehicles, 1, -1 do
		if not vehicles[index].model:IsDescendantOf(Workspace) then
			vehicles[index].model:Destroy()
			table.remove(vehicles, index)
		end
	end
	rebuildArrays()
	updateConnection()
end

local function step(dt: number): ()
	clock += dt
	for _, vehicle in vehicles do
		local lanes = vehicle.lanes
		local turnSeconds = vehicle.turnSeconds
		local alpha = if turnSeconds > 0 then math.min(vehicle.blendElapsed / turnSeconds, 1) else 1
		local lane = vehicle.lane
		local distance = vehicle.distance + vehicle.speed * dt
		local hops = 0
		while distance >= lanes.length[lane] do
			if hops >= MAX_LANE_HOPS_PER_FRAME then
				distance = 0
				break
			end
			local following = nextLane(lanes, lane, vehicle.freeAt)
			if following == nil then
				-- Every way on is taken: wait at the node and ask again next frame.
				distance = lanes.length[lane]
				break
			end
			distance -= lanes.length[lane]
			local laneEnd = lanes.origin[lane] + lanes.direction[lane] * lanes.length[lane]
			local residual = vehicle.blendOffset * (1 - alpha)
			lane = following
			claim(vehicle, lane, 0)
			-- Straight hops produce a zero offset and equal yaw, so only real turns blend.
			vehicle.blendOffset = laneEnd + residual - lanes.origin[lane]
			vehicle.fromYaw = vehicle.renderYaw
			vehicle.blendElapsed = 0
			alpha = if turnSeconds > 0 then 0 else 1
			hops += 1
		end
		vehicle.lane = lane
		vehicle.distance = distance
		if alpha < 1 then
			vehicle.blendElapsed += dt
			alpha = math.min(vehicle.blendElapsed / turnSeconds, 1)
		end

		local position = lanes.origin[lane]
			+ lanes.direction[lane] * distance
			+ vehicle.blendOffset * (1 - alpha)
		local yaw = vehicle.fromYaw + wrapAngle(lanes.yaw[lane] - vehicle.fromYaw) * alpha
		vehicle.renderYaw = yaw
		local frame = frameFor(position, yaw)
		for index = vehicle.partStart, vehicle.partStart + vehicle.partCount - 1 do
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
	if #vehicles > 0 then
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

local function seat(vehicle: Vehicle, lanes: Lanes, lane: number, distance: number): ()
	vehicle.lanes = lanes
	vehicle.freeAt = freeAtFor(lanes)
	vehicle.lane = lane
	vehicle.distance = math.clamp(distance, 0, lanes.length[lane])
	claim(vehicle, vehicle.lane, vehicle.distance)
end

local function removeWhere(plotId: number): ()
	local removed = false
	for index = #vehicles, 1, -1 do
		local vehicle = vehicles[index]
		if vehicle.plotId == plotId then
			vehicle.model:Destroy()
			table.remove(vehicles, index)
			removed = true
		end
	end
	if removed then
		rebuildArrays()
		updateConnection()
	end
end

local Traffic = {}

-- Replaces the plot's vehicles with `models` (pivoted with their bottom-centre at
-- CFrame.identity, as PropFactory.Spawn(…, CFrame.identity, nil) leaves them), spaced evenly
-- along the road network, alternating directions, and never closer than the longest car plus
-- `followGap` (vehicles.followGap) to the next one going the same way -- a short network takes
-- fewer cars. Traffic owns the models from here on and destroys any it has no room or road for;
-- `mapVehicleBudget` is the whole-map vehicle cap (CityDressing.json budget.vehiclesMap).
-- Returns how many vehicles were placed, and whether the map budget (not the road) refused any,
-- which is the only shortfall a later retry can fix.
function Traffic.SpawnPlot(
	plotId: number,
	lanes: Lanes,
	models: { Model },
	speed: number,
	turnSeconds: number,
	followGap: number?,
	parent: Instance,
	mapVehicleBudget: number
): (number, boolean)
	removeWhere(plotId)

	-- Each two-way road piece counted once (the lane with the lower id of its pair).
	local total = 0
	for lane = 1, lanes.count do
		if lane < lanes.reverse[lane] then
			total += lanes.length[lane]
		end
	end
	local room = mapVehicleBudget - #vehicles
	local budgetLimited = room < #models
	local gap = math.max(numberOr(followGap, DEFAULT_FOLLOW_GAP), 0)
	local driveSpeed = math.max(speed, 0)

	-- Read off the clones as spawned, so a wave 2d ScaleTo (done about the base, before this) is
	-- already in every offset: a half-size car rides at half the height with no correction here.
	local measured: { { parts: { BasePart }, offsets: { CFrame }, length: number } } = {}
	local spacing = gap
	for index, model in models do
		local modelParts: { BasePart } = {}
		local partOffsets: { CFrame } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(modelParts, descendant)
				table.insert(partOffsets, descendant.CFrame)
			end
		end
		local length = lengthOf(modelParts, partOffsets)
		measured[index] = { parts = modelParts, offsets = partOffsets, length = length }
		spacing = math.max(spacing, length + gap)
	end
	-- Alternate cars share a direction, so same-way neighbours start 2 * total / count apart.
	local fits = if spacing > 0 then math.max(math.floor(2 * total / spacing), 1) else #models
	local count = math.min(#models, room, fits)
	if total <= 0 or count <= 0 then
		for _, model in models do
			model:Destroy()
		end
		return 0, budgetLimited
	end

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

		local shape = measured[index]
		local vehicle: Vehicle = {
			plotId = plotId,
			model = model,
			lanes = lanes,
			freeAt = freeAtFor(lanes),
			hold = if driveSpeed > 0 then (shape.length + gap) / driveSpeed else 0,
			lane = lane,
			distance = 0,
			speed = driveSpeed,
			turnSeconds = math.max(turnSeconds, 0),
			blendElapsed = 0,
			fromYaw = lanes.yaw[lane],
			blendOffset = Vector3.zero,
			renderYaw = lanes.yaw[lane],
			partStart = 0,
			partCount = 0,
			partOffsets = shape.offsets,
			modelParts = shape.parts,
		}
		seat(vehicle, lanes, lane, distance)
		vehicle.blendElapsed = vehicle.turnSeconds
		-- Placed before parenting so the model never flashes at the world origin.
		local frame = frameFor(
			lanes.origin[vehicle.lane] + lanes.direction[vehicle.lane] * vehicle.distance,
			vehicle.renderYaw
		)
		for partIndex, part in shape.parts do
			part.CFrame = frame * shape.offsets[partIndex]
		end
		model.Parent = parent
		table.insert(vehicles, vehicle)
	end
	rebuildArrays()
	updateConnection()
	return count, budgetLimited
end

-- The plot's road network changed: move each of its vehicles onto the nearest lane of the new
-- graph, blending from where it was drawn. An empty graph removes them.
function Traffic.SetLanes(plotId: number, lanes: Lanes): ()
	if lanes.count == 0 then
		removeWhere(plotId)
		return
	end
	for _, vehicle in vehicles do
		if vehicle.plotId ~= plotId then
			continue
		end
		local old = vehicle.lanes
		local turnSeconds = vehicle.turnSeconds
		local alpha = if turnSeconds > 0 then math.min(vehicle.blendElapsed / turnSeconds, 1) else 1
		local drawn = old.origin[vehicle.lane]
			+ old.direction[vehicle.lane] * vehicle.distance
			+ vehicle.blendOffset * (1 - alpha)
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
		seat(vehicle, lanes, bestLane, bestAlong)
		vehicle.blendOffset = drawn
			- (lanes.origin[bestLane] + lanes.direction[bestLane] * bestAlong)
		vehicle.fromYaw = vehicle.renderYaw
		vehicle.blendElapsed = 0
	end
end

-- Vehicles the whole map can still take under `mapVehicleBudget`.
function Traffic.Room(mapVehicleBudget: number): number
	return math.max(mapVehicleBudget - #vehicles, 0)
end

function Traffic.ClearPlot(plotId: number): ()
	removeWhere(plotId)
end

function Traffic.Count(plotId: number): number
	local count = 0
	for _, vehicle in vehicles do
		if vehicle.plotId == plotId then
			count += 1
		end
	end
	return count
end

return Traffic
