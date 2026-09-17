--!strict
-- Seeded placement plan for a plot's trees, filler houses, plazas, lamps and vehicle models
-- (docs/INTERFACES.md "M9 contracts — Trees, houses, plazas, lamps" and "Vehicles").
--
-- Determinism: one Random seeded with plotIndex * 7919 + Hash(eraName), consumed in a fixed
-- order that depends only on the layout and config (trees: 3 draws per zone candidate whether
-- or not it is kept; houses: 1 draw per lot; lamps: a Fisher-Yates over the sorted junction
-- slot ids; vehicles: 1 draw per possible vehicle). Rejection tests use every road the plot
-- can ever have, never the roads drawn so far, and budgets are allocated in layout order, so
-- the plan is the same on every client, on rejoin, and at any point in the plot's growth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local RoadGraph = require(script.Parent:WaitForChild("RoadGraph"))
local Noise = require(script.Parent:WaitForChild("Noise"))

-- Seed formula frozen by the contract.
local SEED_PLOT_MULTIPLIER = 7919
local FULL_TURN = 2 * math.pi

export type TreeSpot = {
	position: Vector3, -- plot-local, Y 0
	yaw: number, -- radians
	birthTier: number,
}

export type Plan = {
	trees: { TreeSpot },
	lotProps: { [number]: string }, -- lot index -> house prop (only lots inside the budget)
	plazaAllowed: { [number]: boolean }, -- plaza index -> inside the budget
	lampSlots: { [string]: boolean }, -- slots whose spur junction may carry a lamp
	vehicleProps: { string }, -- vehicle i's prop name
}

export type PlanInput = {
	plotIndex: number,
	eraName: string,
	plotSize: Vector3,
	layout: Types.EraLayout,
	config: Types.CityDressingConfig,
	era: Types.CityEraDressingConfig,
	roadWidth: number,
	-- RoadGraph.AllCentrelines: every potential road, straight and (ribbon eras) smoothed.
	centrelines: { { Vector3 } },
	junctionSlotIds: { string }, -- RoadGraph.JunctionSlotIds (sorted)
}

type Obstacle = { position: Vector3, radius: number }
-- Model-space XZ rectangle around a bottom-centre anchor (front -Z), not necessarily centred.
type Extents = { minX: number, maxX: number, minZ: number, maxZ: number }
-- Extents placed in the plot; `rotation` is the turn about Y only, with no translation.
type Footprint = { origin: Vector3, rotation: CFrame, extents: Extents }

local Scatter = {}

-- The seed hash lives in Noise so the road meander keys its phases with the same function.
function Scatter.Hash(text: string): number
	return Noise.Hash(text)
end

function Scatter.Seed(plotIndex: number, eraName: string): number
	return plotIndex * SEED_PLOT_MULTIPLIER + Scatter.Hash(eraName)
end

-- Maps one uniform draw onto a list index, so a draw is consumed even for an empty list.
local function pickIndex(draw: number, count: number): number?
	if count <= 0 then
		return nil
	end
	return math.min(math.floor(draw * count) + 1, count)
end

local function facingFor(rotationY: number): Vector3
	local radians = math.rad(rotationY)
	return Vector3.new(-math.sin(radians), 0, -math.cos(radians))
end

local function flat(point: Vector3): Vector3
	return Vector3.new(point.X, 0, point.Z)
end

local function centredExtents(sizeX: number, sizeZ: number): Extents
	return { minX = -sizeX / 2, maxX = sizeX / 2, minZ = -sizeZ / 2, maxZ = sizeZ / 2 }
end

local function isNumberTriple(value: any): boolean
	return type(value) == "table" and type(value[1]) == "number" and type(value[3]) == "number"
end

local function widen(into: Extents, other: Extents): ()
	into.minX = math.min(into.minX, other.minX)
	into.maxX = math.max(into.maxX, other.maxX)
	into.minZ = math.min(into.minZ, other.minZ)
	into.maxZ = math.max(into.maxZ, other.maxZ)
end

-- XZ bounds of every harvested part of every stage, so a building's rectangle also covers its
-- largest future stage. Read from Assets.json, which the templates are generated from and which
-- every client has identically from the first frame. A template's own `Base` is a 1x1 anchor
-- (docs/INTERFACES.md "Template shape") and carries no footprint.
local function modelExtents(model: Types.AssetModel?): Extents?
	if model == nil or type(model.stages) ~= "table" then
		return nil
	end
	local extents: Extents? = nil
	for _, stage in model.stages do
		for _, part in stage.parts do
			if not isNumberTriple(part.size) or not isNumberTriple(part.offset) then
				continue
			end
			local partExtents: Extents = {
				minX = part.offset[1] - part.size[1] / 2,
				maxX = part.offset[1] + part.size[1] / 2,
				minZ = part.offset[3] - part.size[3] / 2,
				maxZ = part.offset[3] + part.size[3] / 2,
			}
			local current = extents
			if current == nil then
				extents = partExtents
			else
				widen(current, partExtents)
			end
		end
	end
	return extents
end

local function slotModelNames(eraName: string): { [string]: string }
	local names: { [string]: string } = {}
	for eraIndex = 1, Catalog.GetEraCount() do
		local eraConfig = Catalog.GetEraConfig(eraIndex)
		if eraConfig ~= nil and eraConfig.name == eraName then
			for _, slot in eraConfig.slots do
				names[slot.id] = slot.modelName
			end
			break
		end
	end
	return names
end

local function footprintsFor(input: PlanInput): { Footprint }
	local layout = input.layout
	local assets = Catalog.GetAssetsConfig()
	local eraModels: { [string]: Types.AssetModel }? = if assets ~= nil
		then assets.eras[input.eraName]
		else nil
	local propsByEra = if assets ~= nil then assets.props else nil
	local eraProps: { [string]: Types.AssetModel }? = if propsByEra ~= nil
		then propsByEra[input.eraName]
		else nil
	local modelNames = slotModelNames(input.eraName)

	local footprints: { Footprint } = {}
	local function add(position: Vector3, rotationY: number, extents: Extents): ()
		table.insert(footprints, {
			origin = flat(position),
			rotation = CFrame.Angles(0, math.rad(rotationY), 0),
			extents = extents,
		})
	end

	-- A slot without harvested assets stands as a placeholder of the layout's placeholderSize.
	local largestX = layout.placeholderSize.X
	local largestZ = layout.placeholderSize.Z
	local slotExtents: { [string]: Extents } = {}
	for slotId in layout.slots do
		local modelName = modelNames[slotId]
		local model: Types.AssetModel? = if eraModels ~= nil and modelName ~= nil
			then eraModels[modelName]
			else nil
		local extents = modelExtents(model)
			or centredExtents(layout.placeholderSize.X, layout.placeholderSize.Z)
		slotExtents[slotId] = extents
		largestX = math.max(largestX, extents.maxX - extents.minX)
		largestZ = math.max(largestZ, extents.maxZ - extents.minZ)
	end
	-- A prop with no harvested sizes yet is assumed as large as the era's largest slot (the
	-- monument): it errs toward fewer trees rather than trees inside a square.
	local function propExtents(propName: string?): Extents
		local model: Types.AssetModel? = if eraProps ~= nil and propName ~= nil
			then eraProps[propName]
			else nil
		return modelExtents(model) or centredExtents(largestX, largestZ)
	end

	for slotId, slotLayout in layout.slots do
		add(slotLayout.position, slotLayout.rotationY, slotExtents[slotId])
		local padCentre = slotLayout.padPosition
			or slotLayout.position + facingFor(slotLayout.rotationY) * layout.padOffset
		-- Pads are placed unrotated in the plot frame (PlotService.padWorldCFrame).
		add(padCentre, 0, centredExtents(layout.padSize.X, layout.padSize.Z))
	end

	-- A lot's house is picked only after the trees (fixed draw order), so a lot reserves the
	-- union of every house prop the era could place on it.
	local lotExtents = propExtents(nil)
	local houseProps = input.era.houses.props
	if #houseProps > 0 then
		lotExtents = table.clone(propExtents(houseProps[1]))
		for index = 2, #houseProps do
			widen(lotExtents, propExtents(houseProps[index]))
		end
	end
	local lots: { Types.LotLayout } = layout.lots or {}
	for _, lot in lots do
		add(lot.position, lot.rotationY, lotExtents)
	end
	local plazas: { Types.PlazaLayout } = layout.plazas or {}
	for _, plaza in plazas do
		add(plaza.position, plaza.rotationY, propExtents(plaza.prop))
	end
	return footprints
end

local function insideFootprint(footprint: Footprint, point: Vector3, margin: number): boolean
	local localPoint = footprint.rotation:PointToObjectSpace(point - footprint.origin)
	local extents = footprint.extents
	return localPoint.X >= extents.minX - margin
		and localPoint.X <= extents.maxX + margin
		and localPoint.Z >= extents.minZ - margin
		and localPoint.Z <= extents.maxZ + margin
end

local function obstaclesFor(input: PlanInput, clearance: number): { Obstacle }
	local layout = input.layout
	local obstacles: { Obstacle } = {}
	local function add(position: Vector3): ()
		table.insert(obstacles, { position = flat(position), radius = clearance })
	end
	for _, slotLayout in layout.slots do
		add(slotLayout.position)
		local padCentre = slotLayout.padPosition
			or slotLayout.position + facingFor(slotLayout.rotationY) * layout.padOffset
		add(padCentre)
	end
	local lots: { Types.LotLayout } = layout.lots or {}
	local plazas: { Types.PlazaLayout } = layout.plazas or {}
	for _, lot in lots do
		add(lot.position)
	end
	for _, plaza in plazas do
		add(plaza.position)
	end
	-- The plot sign straddles the front (-Z) edge centre (PlotService.buildWorld).
	add(Vector3.new(0, 0, -input.plotSize.Z / 2))
	return obstacles
end

local function treeSpots(input: PlanInput, rng: Random): { TreeSpot }
	local era = input.era
	local clearance = era.trees.clearance
	local obstacles = obstaclesFor(input, clearance)
	local footprints = footprintsFor(input)
	local footprintMargin = input.config.trees.footprintMargin
	-- A meandered trail can wander `amplitude` off its centreline, so trees keep that much more.
	local meander = era.road.meander
	local roadClearance = input.roadWidth / 2
		+ (if meander ~= nil then meander.amplitude else 0)
		+ input.config.trees.roadClearance
	local margin = input.config.trees.edgeMargin
	local halfX = input.plotSize.X / 2 - margin
	local halfZ = input.plotSize.Z / 2 - margin

	local function accepted(point: Vector3): boolean
		if math.abs(point.X) > halfX or math.abs(point.Z) > halfZ then
			return false
		end
		for _, obstacle in obstacles do
			if (point - obstacle.position).Magnitude < obstacle.radius then
				return false
			end
		end
		for _, footprint in footprints do
			if insideFootprint(footprint, point, footprintMargin) then
				return false
			end
		end
		for _, line in input.centrelines do
			for index = 2, #line do
				local closest = RoadGraph.ClosestOnSegment(point, line[index - 1], line[index])
				if (closest - point).Magnitude < roadClearance then
					return false
				end
			end
		end
		return true
	end

	local kept: { TreeSpot } = {}
	local zones: { Types.TreeZoneLayout } = input.layout.treeZones or {}
	for _, zone in zones do
		local count = math.max(math.floor(zone.count), 0)
		local radius = math.max(zone.radius, 0)
		for _ = 1, count do
			-- Always three draws, kept or rejected, so later features see the same stream.
			local radial = radius * math.sqrt(rng:NextNumber())
			local angle = FULL_TURN * rng:NextNumber()
			local yaw = FULL_TURN * rng:NextNumber()
			local point = Vector3.new(
				zone.center.X + radial * math.cos(angle),
				0,
				zone.center.Z + radial * math.sin(angle)
			)
			if accepted(point) then
				table.insert(kept, { position = point, yaw = yaw, birthTier = 0 })
			end
		end
	end

	if era.trees.prop == nil then
		return {}
	end
	local cap = math.min(math.max(era.trees.maxCount, 0), input.config.budget.trees)
	while #kept > cap do
		table.remove(kept)
	end
	-- Birth tiers spread evenly over the tiers (tier count = #thresholds, 5 in v1).
	local tierCount = #input.config.tier.thresholds
	for index, spot in kept do
		spot.birthTier = 1 + math.floor((index - 1) * tierCount / #kept)
	end
	return kept
end

function Scatter.Plan(input: PlanInput): Plan
	local rng = Random.new(Scatter.Seed(input.plotIndex, input.eraName))
	local era = input.era
	local layout = input.layout
	local plan: Plan = {
		trees = treeSpots(input, rng),
		lotProps = {},
		plazaAllowed = {},
		lampSlots = {},
		vehicleProps = {},
	}

	-- Filler budget, in layout order: plazas, then lots, then lamps.
	local remaining = input.config.budget.fillerPieces
	local plazas: { Types.PlazaLayout } = layout.plazas or {}
	local lots: { Types.LotLayout } = layout.lots or {}
	for index in plazas do
		if remaining > 0 then
			plan.plazaAllowed[index] = true
			remaining -= 1
		end
	end
	local houseProps = era.houses.props
	for index in lots do
		local pick = pickIndex(rng:NextNumber(), #houseProps)
		if pick ~= nil and remaining > 0 then
			plan.lotProps[index] = houseProps[pick]
			remaining -= 1
		end
	end

	-- Lamp eligibility is fixed per slot (every Nth in seeded order, capped), so a lamp
	-- never moves when a later purchase lands earlier in the order.
	local order = table.clone(input.junctionSlotIds)
	for index = #order, 2, -1 do
		local swap = pickIndex(rng:NextNumber(), index) :: number
		order[index], order[swap] = order[swap], order[index]
	end
	local lamps = input.config.lamps
	local lampCap = math.min(math.max(lamps.maxPerPlot, 0), remaining)
	local every = math.max(math.floor(lamps.everyNthJunction), 1)
	if era.lamps.prop ~= nil then
		local placed = 0
		for index, slotId in order do
			if placed >= lampCap then
				break
			end
			if index % every == 0 then
				plan.lampSlots[slotId] = true
				placed += 1
			end
		end
	end

	local vehicleProps = era.vehicles.props
	local vehicleCap =
		math.min(math.max(era.vehicles.perPlot, 0), input.config.budget.vehiclesPerPlot)
	for index = 1, vehicleCap do
		local pick = pickIndex(rng:NextNumber(), #vehicleProps)
		if pick ~= nil then
			plan.vehicleProps[index] = vehicleProps[pick]
		end
	end
	return plan
end

-- A tree's visible stage at a tier, or nil before its birth tier.
function Scatter.TreeStage(spot: TreeSpot, tier: number, stages: number): number?
	if tier < spot.birthTier then
		return nil
	end
	return math.clamp(tier - spot.birthTier, 0, math.max(stages - 1, 0))
end

-- Lamp on the right-hand edge of the spur where it meets the spine, facing the road. The
-- step back from the junction stops at the start of the spur's last section, so a short spur
-- never pushes the lamp onto the pad or into the building.
function Scatter.LampFrame(junction: RoadGraph.Junction, roadWidth: number): CFrame
	local direction = junction.direction
	local right = direction:Cross(Vector3.yAxis)
	local stepBack = math.clamp(junction.approach, 0, roadWidth)
	local position = junction.position - direction * stepBack + right * (roadWidth / 2)
	return CFrame.lookAt(position, position - right)
end

function Scatter.PropFrame(position: Vector3, rotationY: number): CFrame
	return CFrame.new(flat(position)) * CFrame.Angles(0, math.rad(rotationY), 0)
end

return Scatter
