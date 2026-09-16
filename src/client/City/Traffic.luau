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

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(script.Parent:WaitForChild("RoadGraph"))

type Lanes = RoadGraph.Lanes

-- A frame hitch must not spin through a tiny loop of lanes; past this the vehicle just parks
-- at the start of its current lane for the frame.
local MAX_LANE_HOPS_PER_FRAME = 8
local HALF_TURN = math.pi
local FULL_TURN = 2 * math.pi

type Vehicle = {
	plotId: number,
	model: Model,
	lanes: Lanes,
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
-- Unseeded on purpose: route choices are cosmetic and allowed to differ per client.
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
			distance -= lanes.length[lane]
			local laneEnd = lanes.origin[lane] + lanes.direction[lane] * lanes.length[lane]
			local residual = vehicle.blendOffset * (1 - alpha)
			lane = nextLane(lanes, lane)
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
	vehicle.lane = lane
	vehicle.distance = math.clamp(distance, 0, lanes.length[lane])
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
-- along the road network, alternating directions. Traffic owns the models from here on and
-- destroys any it has no room or road for; `mapVehicleBudget` is the whole-map vehicle cap
-- (CityDressing.json budget.vehiclesMap). Returns how many vehicles were placed.
function Traffic.SpawnPlot(
	plotId: number,
	lanes: Lanes,
	models: { Model },
	speed: number,
	turnSeconds: number,
	parent: Instance,
	mapVehicleBudget: number
): number
	removeWhere(plotId)

	-- Each two-way road piece counted once (the lane with the lower id of its pair).
	local total = 0
	for lane = 1, lanes.count do
		if lane < lanes.reverse[lane] then
			total += lanes.length[lane]
		end
	end
	local room = mapVehicleBudget - #vehicles
	local count = math.min(#models, room)
	if total <= 0 or count <= 0 then
		for _, model in models do
			model:Destroy()
		end
		return 0
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

		local modelParts: { BasePart } = {}
		local partOffsets: { CFrame } = {}
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(modelParts, descendant)
				table.insert(partOffsets, descendant.CFrame)
			end
		end
		local vehicle: Vehicle = {
			plotId = plotId,
			model = model,
			lanes = lanes,
			lane = lane,
			distance = 0,
			speed = math.max(speed, 0),
			turnSeconds = math.max(turnSeconds, 0),
			blendElapsed = 0,
			fromYaw = lanes.yaw[lane],
			blendOffset = Vector3.zero,
			renderYaw = lanes.yaw[lane],
			partStart = 0,
			partCount = 0,
			partOffsets = partOffsets,
			modelParts = modelParts,
		}
		seat(vehicle, lanes, lane, distance)
		vehicle.blendElapsed = vehicle.turnSeconds
		-- Placed before parenting so the model never flashes at the world origin.
		local frame = frameFor(
			lanes.origin[vehicle.lane] + lanes.direction[vehicle.lane] * vehicle.distance,
			vehicle.renderYaw
		)
		for partIndex, part in modelParts do
			part.CFrame = frame * partOffsets[partIndex]
		end
		model.Parent = parent
		table.insert(vehicles, vehicle)
	end
	rebuildArrays()
	updateConnection()
	return count
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
