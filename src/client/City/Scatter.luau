--!strict
-- Seeded placement plan for a plot's trees, filler houses, plazas, lamps and vehicle models
-- (docs/INTERFACES.md "M9 contracts — Trees, houses, plazas, lamps" and "Vehicles").
--
-- Determinism: one Random seeded with plotIndex * 7919 + Hash(eraName), consumed in a fixed
-- order that depends only on the layout and config (trees: 3 draws per zone candidate whether
-- or not it is kept; houses: 1 draw per lot; lamps: a Fisher-Yates over the sorted junction
-- slot ids whichever placement the era uses; vehicles: 1 draw per possible vehicle). Wave 1e's
-- row lamp posts are walked off the streets and draw nothing. Rejection tests use every road the plot
-- can ever have, never the roads drawn so far, and budgets are allocated in layout order, so
-- the plan is the same on every client, on rejoin, and at any point in the plot's growth.
--
-- Wave 2c: greenery, parked vehicles, walkers and bird flocks each draw from their own Random,
-- seeded with the plot seed plus a frozen salt, after all of the above; the only draw the wave
-- adds to the main stream is one per new lot, which may shift lamp and vehicle picks (cosmetic).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local RoadGraph = require(script.Parent:WaitForChild("RoadGraph"))
local Noise = require(script.Parent:WaitForChild("Noise"))
local PropFactory = require(script.Parent:WaitForChild("PropFactory"))

-- Seed formula frozen by the contract.
local SEED_PLOT_MULTIPLIER = 7919
local FULL_TURN = 2 * math.pi
local UP = Vector3.yAxis
-- Wave 1e: lamps down both sides of the streets instead of one at a spur junction.
local ROW_PLACEMENT = "row"
-- Wave 2c: the lot kind that draws from `houses.smallProps`; anything else is a house.
local SMALL_LOT = "small"
-- Wave 2c: each new category draws from its own stream, salted off the plot seed and consumed
-- after the existing plan, so adding one never moves a tree, lamp or vehicle (docs/INTERFACES.md
-- "Wave 2c — Principles"; the salts are frozen there).
local GREENERY_SALT = 7001
local PARKED_SALT = 7002
local WALKERS_SALT = 7003
local AMBIENT_SALT = 7004
-- Wave 2d: studs between two cars packed into one bay when `parked.gap` is absent (the contract's
-- default, not a tunable of its own).
local DEFAULT_PARKED_GAP = 0.3
-- Wave 2d: a `parked.perBay` typo must not multiply the parked stream's draws without bound.
local MAX_PER_BAY = 4
-- Garnish goes on one of a lot's four sides, in the lot's own frame (front -Z faces the street).
local LOT_SIDES = 4
-- Samples closer together than this are the same point, and the shortest leg worth walking.
local MIN_STEP = 0.05
-- How square a block edge and a street have to be for the edge to count as fronting that street.
local STRAIGHT_ENOUGH = 0.9
-- A street tree's turn is hashed into whole degrees, so it varies without touching the Random.
local FULL_CIRCLE_DEGREES = 360

export type TreeSpot = {
	position: Vector3, -- plot-local, Y 0
	yaw: number, -- radians
	birthTier: number,
	-- Wave 2a street trees: the spine piece this tree stands beside (as a row lamp carries one) and
	-- the block it stands on, which has to be paved before it grows. A zone tree has neither and
	-- appears on its birth tier alone.
	pieceId: string?,
	blockIndex: number?,
}

-- Wave 1e row lamps: `key` is the stable identity the controller diffs on, `pieceId` the spine
-- piece that must be drawn before the post appears, and (polyline, stretch, step) the numeric
-- order the cap is thinned over -- by id string, "L1_10" would sort before "L1_2" and one trail
-- would take the whole budget.
export type LampPost = {
	key: string,
	pieceId: string,
	polyline: number,
	stretch: number,
	step: number,
	position: Vector3, -- plot-local, Y 0
	yaw: number, -- radians, facing the road
}

-- Wave 2a: one subway entrance from the layout, tied to the spine piece it stands beside (as a row
-- lamp is). `exempt` marks the entrance nearest the plot entrance, which shows as soon as the slot
-- is owned, so buying the line always puts at least one staircase on the street.
export type SubwaySpot = {
	position: Vector3, -- plot-local, Y 0
	rotationY: number,
	pieceId: string?,
	exempt: boolean,
}

-- Wave 2a park strips: one planter down the centreline of a planned street, standing only while
-- that ground is still a strip. (polyline, stretch, step) is the numeric order the cap is thinned
-- over, for the same reason the row lamps carry one.
export type ParkTree = {
	polyline: number,
	stretch: number,
	step: number,
	position: Vector3, -- plot-local, Y 0
	yaw: number, -- radians
}

export type Plan = {
	trees: { TreeSpot },
	lotProps: { [number]: string }, -- lot index -> house prop (only lots inside the budget)
	plazaAllowed: { [number]: boolean }, -- plaza index -> inside the budget
	lampSlots: { [string]: boolean }, -- slots whose spur junction may carry a lamp
	lampPosts: { LampPost }, -- row placement only, in sorted piece order
	parkTrees: { ParkTree }, -- wave 2a, capped by road.tiles.parkStrips.maxTrees
	subwayEntrances: { SubwaySpot }, -- wave 2a, capped by subway.maxPerPlot
	vehicleProps: { string }, -- vehicle i's prop name
	-- Wave 2c, each from its own salted stream after everything above.
	greenery: { GreenerySpot }, -- capped by budget.greenery
	parked: { ParkedSpot }, -- capped by budget.parked
	walkerProps: { string }, -- walker i's prop name, capped by budget.walkersPerPlot
	flocks: { Flock }, -- flock i circles the ((i - 1) % #treeZones + 1)th zone
}

-- Wave 2c greenery: a zone piece carries the tier it appears at; a lot garnish piece carries its
-- lot instead and shows while that lot's house stands.
export type GreenerySpot = {
	position: Vector3, -- plot-local, Y 0
	yaw: number, -- radians
	prop: string,
	tier: number?,
	lot: number?,
}

-- Wave 2c parked vehicles, one entry per car (wave 2d packs up to `parked.perBay` into a bay).
-- `tier` already folds in the era's cumulative `parked.perTier`; `pieceId` is the spine piece
-- beside the bay, which must be drawn before the car appears (nil: no street beside it, so it
-- never does). Cars of one bay are consecutive and share `bay` and `bayPosition`.
export type ParkedSpot = {
	position: Vector3, -- plot-local, Y 0: this car's anchor
	rotationY: number,
	prop: string,
	tier: number,
	lot: number?,
	pieceId: string?,
	bay: number, -- the bay's rank in (tier, index) order
	bayPosition: Vector3, -- plot-local, Y 0: the layout spot
}

-- Wave 2c birds: one flock circling a tree zone centre. The per-bird numbers are unit draws in
-- [0, 1); Ambient turns them into the flock's shape, which is look rather than plan.
export type BirdDraw = { lead: number, radial: number, lift: number }
export type Flock = {
	center: Vector3, -- plot-local, Y 0
	phase: number, -- radians
	clockwise: boolean,
	birds: { BirdDraw },
}

export type PlanInput = {
	plotIndex: number,
	eraName: string,
	plotSize: Vector3,
	layout: Types.EraLayout,
	config: Types.CityDressingConfig,
	era: Types.CityEraDressingConfig,
	roadWidth: number,
	-- RoadGraph.AllCentrelines: every potential road, straight and (baked eras) smoothed.
	centrelines: { { Vector3 } },
	junctionSlotIds: { string }, -- RoadGraph.JunctionSlotIds (sorted)
	-- RoadGraph.StreetLines, called only by row lamps and subway entrances: sampling every drawn
	-- curve is real work and the other eras' lamps stand at junctions.
	streetLines: () -> RoadGraph.StreetLines,
	-- RoadGraph.EntrancePoint, the plot's way in; nil when the layout has no streets.
	entrance: Vector3?,
}

type Obstacle = { position: Vector3, radius: number }
-- Model-space XZ rectangle around a bottom-centre anchor (front -Z), not necessarily centred.
export type Extents = { minX: number, maxX: number, minZ: number, maxZ: number }
-- Extents placed in the plot; `rotation` is the turn about Y only, with no translation.
-- `slotId` (wave 2c) marks a slot's own building and pad, which that slot's footpath may cross;
-- `pad` marks a buy pad, which is flat walkable ground to a walker.
export type Footprint = {
	origin: Vector3,
	rotation: CFrame,
	extents: Extents,
	slotId: string?,
	pad: boolean?,
}
-- An axis-aligned plot-local rectangle, the shape TileRenderer cuts its slabs against.
export type Rect = { x0: number, x1: number, z0: number, z1: number }

local Scatter = {}

-- The `lamps.placement` value the controller tests for too, so the vocabulary lives in one place.
Scatter.ROW_PLACEMENT = ROW_PLACEMENT

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

-- A half-written config key plans nothing rather than erroring in the middle of a sync.
local function numberOr(value: any, fallback: number): number
	return if type(value) == "number" and value == value then value else fallback
end

local function facingFor(rotationY: number): Vector3
	local radians = math.rad(rotationY)
	return Vector3.new(-math.sin(radians), 0, -math.cos(radians))
end

local function flat(point: Vector3): Vector3
	return Vector3.new(point.X, 0, point.Z)
end

-- The lattice cell a plot-local point falls in, rounded exactly as TileRenderer rounds it so a
-- planter and the strip it stands on always agree on which cell they are in.
local function cellKey(point: Vector3, tileStuds: number): string
	return string.format("%d:%d", math.round(point.X / tileStuds), math.round(point.Z / tileStuds))
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
--
-- A harvested `offset` is in the imported frame, which the glTF import turned 180 degrees about Y;
-- `gen_templates.harvested_cframe` negates x and z to put the mesh back at its blueprint
-- coordinate, so a reader of Assets.json has to negate them too. A part with no mesh id has not
-- been harvested at all -- its offset is still the unturned merged-GLB centre
-- (tools/assets/assets_config.py) -- so it is skipped and the caller falls back to a placeholder.
local function modelExtents(model: Types.AssetModel?): Extents?
	if model == nil or type(model.stages) ~= "table" then
		return nil
	end
	local extents: Extents? = nil
	for _, stage in model.stages do
		for _, part in stage.parts do
			if
				not isNumberTriple(part.size)
				or not isNumberTriple(part.offset)
				or type(part.meshId) ~= "number"
				or part.meshId <= 0
			then
				continue
			end
			local centreX, centreZ = -part.offset[1], -part.offset[3]
			local partExtents: Extents = {
				minX = centreX - part.size[1] / 2,
				maxX = centreX + part.size[1] / 2,
				minZ = centreZ - part.size[3] / 2,
				maxZ = centreZ + part.size[3] / 2,
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

-- Wave 2a: a subway kiosk is a solid like any other prop, so no tree and no row lamp is ever
-- planned on top of one, and no park strip is laid under one (its steps sink into the paving). Its
-- harvested bounds win; until the prop is uploaded it stands as the layout's placeholder, the same
-- stand-in an unharvested slot gets -- the "as large as the era's largest slot" fallback the other
-- props take would fence off a whole corner of a block.
local function subwayFootprints(input: PlanInput): { Footprint }
	local layout = input.layout
	local subway = input.era.subway
	local entrances: { Types.SubwayEntranceLayout }? = layout.subwayEntrances
	if subway == nil or entrances == nil then
		return {}
	end
	local assets = Catalog.GetAssetsConfig()
	local propsByEra = if assets ~= nil then assets.props else nil
	local eraProps: { [string]: Types.AssetModel }? = if propsByEra ~= nil
		then propsByEra[input.eraName]
		else nil
	local model: Types.AssetModel? = if eraProps ~= nil then eraProps[subway.prop] else nil
	local extents = modelExtents(model)
		or centredExtents(layout.placeholderSize.X, layout.placeholderSize.Z)
	local kiosks: { Footprint } = {}
	for _, entrance in entrances do
		table.insert(kiosks, {
			origin = flat(entrance.position),
			rotation = CFrame.Angles(0, math.rad(entrance.rotationY), 0),
			extents = extents,
		})
	end
	return kiosks
end

-- Every solid of the plot, plus (wave 2c) each lot's own footprint by lot index, so greenery can
-- garnish a lot from just outside the rectangle that lot reserves.
local function solidsFor(input: PlanInput): ({ Footprint }, { [number]: Footprint })
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
	local function add(position: Vector3, rotationY: number, extents: Extents, slotId: string?): ()
		table.insert(footprints, {
			origin = flat(position),
			rotation = CFrame.Angles(0, math.rad(rotationY), 0),
			extents = extents,
			slotId = slotId,
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
		add(slotLayout.position, slotLayout.rotationY, slotExtents[slotId], slotId)
		local padCentre = slotLayout.padPosition
			or slotLayout.position + facingFor(slotLayout.rotationY) * layout.padOffset
		-- Pads are placed unrotated in the plot frame (PlotService.padWorldCFrame).
		add(padCentre, 0, centredExtents(layout.padSize.X, layout.padSize.Z), slotId)
		footprints[#footprints].pad = true
	end

	-- A lot's house is picked only after the trees (fixed draw order), so a lot reserves the
	-- union of every house prop the era could place on it -- per kind since wave 2c, so a small
	-- lot reserves only what a small prop can cover.
	local function poolExtents(pool: { string }?): Extents
		if type(pool) ~= "table" or #pool == 0 then
			return propExtents(nil)
		end
		local union = table.clone(propExtents(pool[1]))
		for index = 2, #pool do
			widen(union, propExtents(pool[index]))
		end
		return union
	end
	local houseExtents = poolExtents(input.era.houses.props)
	local smallExtents = poolExtents(input.era.houses.smallProps)
	local lotFootprints: { [number]: Footprint } = {}
	local lots: { Types.LotLayout } = layout.lots or {}
	for index, lot in lots do
		add(
			lot.position,
			lot.rotationY,
			if lot.kind == SMALL_LOT then smallExtents else houseExtents
		)
		lotFootprints[index] = footprints[#footprints]
	end
	local plazas: { Types.PlazaLayout } = layout.plazas or {}
	for _, plaza in plazas do
		add(plaza.position, plaza.rotationY, propExtents(plaza.prop))
	end

	for _, kiosk in subwayFootprints(input) do
		table.insert(footprints, kiosk)
	end
	return footprints, lotFootprints
end

local function footprintsFor(input: PlanInput): { Footprint }
	return (solidsFor(input))
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

local function treeSpots(input: PlanInput, rng: Random, taken: number): { TreeSpot }
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
	-- Street trees are placed first and count against the same ceiling; the zones take the rest.
	local cap =
		math.max(math.min(math.max(era.trees.maxCount, 0), input.config.budget.trees) - taken, 0)
	-- Thinned evenly over the whole (zone, candidate) order rather than truncated, so every zone
	-- keeps its share instead of the first ones spending the budget -- the row-lamp rule. A plot
	-- whose zones already fit (no street trees took a share) keeps every candidate untouched.
	local total = #kept
	if total > cap then
		local thinned: { TreeSpot } = {}
		for index, spot in kept do
			if (index * cap) // total ~= ((index - 1) * cap) // total then
				table.insert(thinned, spot)
			end
		end
		kept = thinned
	end
	-- Birth tiers spread evenly over the tiers (tier count = #thresholds, 5 in v1).
	local tierCount = #input.config.tier.thresholds
	for index, spot in kept do
		spot.birthTier = 1 + math.floor((index - 1) * tierCount / #kept)
	end
	return kept
end

-- Whether `point` is within `limit` of a polyline.
local function nearLine(point: Vector3, line: { Vector3 }, limit: number): boolean
	for index = 2, #line do
		local closest = RoadGraph.ClosestOnSegment(point, line[index - 1], line[index])
		if (closest - point).Magnitude < limit then
			return true
		end
	end
	return false
end

-- Row lamps (docs/INTERFACES.md "Wave 1e — Lamps"): a post every `spacing` studs of arc along
-- each spine run, alternating sides, `width / 2 + offset` outside the drawn centreline and facing
-- it. The walk is a function of the layout alone, so it draws no numbers from the plan's Random
-- and leaves every later feature's stream exactly as it was before this wave.
local function lampPosts(input: PlanInput, streetLines: () -> RoadGraph.StreetLines): { LampPost }
	local lamps = input.era.lamps
	local spacing = lamps.spacing
	if
		lamps.prop == nil
		or lamps.placement ~= ROW_PLACEMENT
		or spacing == nil
		or spacing < MIN_STEP
	then
		return {}
	end
	local lines = streetLines()
	local footprints = footprintsFor(input)
	local reach = input.roadWidth / 2 + math.max(lamps.offset or 0, 0)
	local clearance = input.roadWidth / 2
	-- A post inside anything the plot builds on, or on another road, is dropped. Its own street is
	-- what it was measured from, so that one is not tested against.
	local function blocked(position: Vector3, polyline: number): boolean
		for _, footprint in footprints do
			if insideFootprint(footprint, position, 0) then
				return true
			end
		end
		for _, other in lines.runs do
			if other.polyline == polyline then
				continue
			end
			for _, piece in other.pieces do
				if nearLine(position, piece.points, clearance) then
					return true
				end
			end
		end
		for _, spur in lines.spurs do
			if nearLine(position, spur, clearance) then
				return true
			end
		end
		return false
	end

	local posts: { LampPost } = {}
	for _, run in lines.runs do
		-- The run as one curve, so the spacing carries across the pieces of a street.
		local points: { Vector3 } = {}
		local arcs: { number } = {}
		local pieces: { RoadGraph.SpinePiece } = {}
		local total = 0
		for _, piece in run.pieces do
			for _, point in piece.points do
				if #points > 0 then
					local advance = (point - points[#points]).Magnitude
					if advance < MIN_STEP then
						continue
					end
					total += advance
				end
				table.insert(points, point)
				table.insert(arcs, total)
				table.insert(pieces, piece)
			end
		end
		local index = 2
		for step = 1, math.floor(total / spacing) do
			local target = spacing * step
			while index < #arcs and arcs[index] < target do
				index += 1
			end
			local a, b = points[index - 1], points[index]
			local hand = if step % 2 == 1 then 1 else -1
			local right = ((b - a).Unit):Cross(UP) * hand
			local position = a:Lerp(b, (target - arcs[index - 1]) / (arcs[index] - arcs[index - 1]))
				+ right * reach
			local piece = pieces[index]
			if not blocked(position, run.polyline) then
				table.insert(posts, {
					key = string.format("%s:%d", piece.pieceId, step),
					pieceId = piece.pieceId,
					polyline = run.polyline,
					stretch = piece.stretch,
					step = step,
					position = position,
					-- The post stands on the road's `right` side and looks back across it.
					yaw = math.atan2(right.X, right.Z),
				})
			end
		end
	end
	table.sort(posts, function(a: LampPost, b: LampPost): boolean
		if a.polyline ~= b.polyline then
			return a.polyline < b.polyline
		end
		if a.stretch ~= b.stretch then
			return a.stretch < b.stretch
		end
		return a.step < b.step
	end)
	-- Row posts have their own ceiling; a file too old to carry it falls back to the lamp count.
	-- An overrun is thinned evenly over the whole order rather than truncated, so the last trail
	-- keeps its share instead of the first one spending the budget (docs/INTERFACES.md "Wave 1e").
	local cap = math.max(input.config.budget.lampPosts or input.config.lamps.maxPerPlot, 0)
	local count = #posts
	if count <= cap then
		return posts
	end
	local kept: { LampPost } = {}
	for index, post in posts do
		if (index * cap) // count ~= ((index - 1) * cap) // count then
			table.insert(kept, post)
		end
	end
	return kept
end

-- Subway entrances (docs/INTERFACES.md "Wave 2a — Subway entrances"): the layout's spots, capped
-- by `subway.maxPerPlot`, each tied to the spine piece it stands nearest so it arrives with the
-- street it belongs to. Like the row lamps this is a walk over the layout and draws no numbers
-- from the plan's Random, so every later feature's stream is exactly what it was before wave 2a.
local function subwaySpots(
	input: PlanInput,
	streetLines: () -> RoadGraph.StreetLines
): { SubwaySpot }
	local subway = input.era.subway
	local entrances: { Types.SubwayEntranceLayout }? = input.layout.subwayEntrances
	if subway == nil or entrances == nil or #entrances == 0 then
		return {}
	end
	local cap = math.max(math.floor(numberOr(subway.maxPerPlot, 0)), 0)
	local lines = streetLines()
	local spots: { SubwaySpot } = {}
	for _, entrance in entrances do
		if #spots >= cap then
			break
		end
		local position = flat(entrance.position)
		-- A kiosk stands on the pavement of the street it opens onto, which is the street it faces
		-- (front -Z, the slot convention). Two streets can be the same distance away -- a corner
		-- spot, or a piece boundary exactly abeam -- and the one in front wins that tie, so an
		-- entrance never binds to the cross street behind it.
		local facing = facingFor(entrance.rotationY)
		local nearestPiece: string? = nil
		local nearestDistance = math.huge
		local nearestAhead = false
		for _, run in lines.runs do
			for _, piece in run.pieces do
				for index = 2, #piece.points do
					local closest = RoadGraph.ClosestOnSegment(
						position,
						piece.points[index - 1],
						piece.points[index]
					)
					local distance = (closest - position).Magnitude
					local ahead = (closest - position):Dot(facing) > 0
					local nearer = distance < nearestDistance - MIN_STEP
					local tied = distance < nearestDistance + MIN_STEP
						and ahead
						and not nearestAhead
					if nearer or tied then
						nearestDistance, nearestPiece, nearestAhead = distance, piece.pieceId, ahead
					end
				end
			end
		end
		table.insert(spots, {
			position = position,
			rotationY = entrance.rotationY,
			pieceId = nearestPiece,
			exempt = false,
		})
	end
	-- The one nearest the way in is exempt from the visibility rule; with no street plan at all
	-- the plot centre stands in for the entrance, which still picks the same spot on every client.
	local reference = input.entrance or Vector3.zero
	local chosen: SubwaySpot? = nil
	local chosenDistance = math.huge
	for _, spot in spots do
		local distance = (spot.position - reference).Magnitude
		if distance < chosenDistance then
			chosenDistance, chosen = distance, spot
		end
	end
	if chosen ~= nil then
		chosen.exempt = true
	end
	return spots
end

-- Street trees (docs/INTERFACES.md "Paved blocks"): a tree every `treeSpacing` studs along each
-- block edge that faces a street, `treeInset` inside the edge. An edge faces a street when a
-- pavement strip runs within `pavement.width + 1` of it -- the strip reaches from `width / 2` to
-- `width / 2 + pavement.width` off the centreline, hence the reach below. Like the row lamps this
-- is a walk over the layout: it draws no numbers from the plan's Random, and each tree carries the
-- spine piece it stands beside so it arrives with its street.
local function streetTreeSpots(
	input: PlanInput,
	streetLines: () -> RoadGraph.StreetLines
): { TreeSpot }
	local tiles = input.era.road.tiles
	local blocks: { Types.BlockLayout }? = input.layout.blocks
	local config = if tiles ~= nil then tiles.blocks else nil
	if config == nil or blocks == nil or input.era.trees.prop == nil then
		return {}
	end
	local spacing = config.treeSpacing
	if type(spacing) ~= "number" or spacing < MIN_STEP then
		return {}
	end
	local pavementWidth = if tiles ~= nil and tiles.pavement ~= nil then tiles.pavement.width else 0
	local spurWidth = if tiles ~= nil then tiles.spur.width else input.roadWidth
	-- Daylight between a trunk and anything it stands beside (`blocks.treeClearance`).
	local clearance = math.max(config.treeClearance, 0)
	local reach = input.roadWidth / 2 + 2 * pavementWidth + clearance
	local inset = math.max(config.treeInset, 0)
	local lines = streetLines()
	local footprints = footprintsFor(input)

	-- The nearest point of any drawable spine piece, with that piece's id and its direction.
	local function nearestPiece(point: Vector3): (number, string?, Vector3?)
		local best, bestId, bestAlong = math.huge, nil, nil
		for _, run in lines.runs do
			for _, piece in run.pieces do
				for index = 2, #piece.points do
					local a, b = piece.points[index - 1], piece.points[index]
					local closest = RoadGraph.ClosestOnSegment(point, a, b)
					local distance = (closest - point).Magnitude
					if distance < best then
						best, bestId, bestAlong = distance, piece.pieceId, b - a
					end
				end
			end
		end
		return best, bestId, bestAlong
	end

	local function blocked(point: Vector3): boolean
		for _, footprint in footprints do
			if insideFootprint(footprint, point, clearance) then
				return true
			end
		end
		for _, spur in lines.spurs do
			if nearLine(point, spur, spurWidth / 2 + clearance) then
				return true
			end
		end
		return false
	end

	local spots: { TreeSpot } = {}
	for blockIndex, block in blocks do
		local minX, maxX = math.min(block.min.X, block.max.X), math.max(block.min.X, block.max.X)
		local minZ, maxZ = math.min(block.min.Z, block.max.Z), math.max(block.min.Z, block.max.Z)
		-- The four edges in a fixed order, each with the direction it is walked and the inward
		-- normal the trees are inset along, so (block, edge, step) is a numeric order.
		local edges = {
			{
				from = Vector3.new(minX, 0, minZ),
				to = Vector3.new(maxX, 0, minZ),
				inward = Vector3.new(0, 0, 1),
			},
			{
				from = Vector3.new(maxX, 0, minZ),
				to = Vector3.new(maxX, 0, maxZ),
				inward = Vector3.new(-1, 0, 0),
			},
			{
				from = Vector3.new(minX, 0, maxZ),
				to = Vector3.new(maxX, 0, maxZ),
				inward = Vector3.new(0, 0, -1),
			},
			{
				from = Vector3.new(minX, 0, minZ),
				to = Vector3.new(minX, 0, maxZ),
				inward = Vector3.new(1, 0, 0),
			},
		}
		for edgeIndex, edge in edges do
			local span = edge.to - edge.from
			local length = span.Magnitude
			if length < spacing then
				continue
			end
			local along = span / length
			local midpoint = (edge.from + edge.to) / 2 + edge.inward * inset
			local distance, _pieceId, direction = nearestPiece(midpoint)
			-- Only an edge that runs alongside a street, not one that merely ends near its mouth.
			local parallel = direction ~= nil
				and math.abs((direction :: Vector3).Unit:Dot(along)) > STRAIGHT_ENOUGH
			if distance > reach or not parallel then
				continue
			end
			for step = 1, math.floor(length / spacing) do
				local position = edge.from + along * (spacing * step) + edge.inward * inset
				if blocked(position) then
					continue
				end
				local _, pieceId = nearestPiece(position)
				if pieceId == nil then
					continue
				end
				table.insert(spots, {
					blockIndex = blockIndex,
					position = position,
					-- Deterministic and stream-free: the same key gives the same turn everywhere.
					yaw = Noise.Hash(`{blockIndex}:{edgeIndex}:{step}`)
						% FULL_CIRCLE_DEGREES
						/ FULL_CIRCLE_DEGREES
						* FULL_TURN,
					birthTier = 1,
					pieceId = pieceId,
				})
			end
		end
	end
	return spots
end

-- Park-strip planters (docs/INTERFACES.md "Park strips in undrawn corridors"): a tree every
-- `parkStrips.treeSpacing` studs down the centreline of every street the plot can ever draw. The
-- controller shows one only while the strip under it is still down, so the row is a plan, not a
-- placement. Like the row lamps this is a walk over the layout with no Random draw, so it shifts
-- no other feature's stream, and the cap is thinned evenly over its own numeric order.
local function parkStripTrees(
	input: PlanInput,
	streetLines: () -> RoadGraph.StreetLines
): { ParkTree }
	local tiles = input.era.road.tiles
	local config = if tiles ~= nil then tiles.parkStrips else nil
	if tiles == nil or config == nil or input.era.trees.prop == nil then
		return {}
	end
	local spacing = config.treeSpacing
	-- No lattice, no cells to plant on: a tile pitch of zero is a config that draws no streets.
	if type(spacing) ~= "number" or spacing < MIN_STEP or tiles.tileStuds < MIN_STEP then
		return {}
	end
	-- A planter keeps the daylight a street tree keeps from the same solids; an era that plants
	-- strips without paving blocks simply has no such distance to keep.
	local clearance = if tiles.blocks ~= nil then math.max(tiles.blocks.treeClearance, 0) else 0
	local spurWidth = math.max(tiles.spur.width, 0)
	local footprints = footprintsFor(input)
	local lines = streetLines()

	local function blocked(point: Vector3): boolean
		for _, footprint in footprints do
			if insideFootprint(footprint, point, clearance) then
				return true
			end
		end
		-- The footpath to a building crosses the corridor it serves; a tree on it would block the
		-- walk to the pad the moment its own street is still unpaved.
		for _, spur in lines.spurs do
			if nearLine(point, spur, spurWidth / 2 + clearance) then
				return true
			end
		end
		return false
	end

	local trees: { ParkTree } = {}
	local taken: { [string]: boolean } = {}
	for _, run in lines.runs do
		-- The run as one curve, exactly as the row lamps walk it: the spacing carries across the
		-- pieces of a street, so a 5-cell stretch followed by a 9-cell one plants an even row
		-- instead of restarting -- and losing a mark -- at the joint.
		local points: { Vector3 } = {}
		local arcs: { number } = {}
		local pieces: { RoadGraph.SpinePiece } = {}
		local total = 0
		for _, piece in run.pieces do
			for _, point in piece.points do
				if #points > 0 then
					local advance = (point - points[#points]).Magnitude
					if advance < MIN_STEP then
						continue
					end
					total += advance
				end
				table.insert(points, point)
				table.insert(arcs, total)
				table.insert(pieces, piece)
			end
		end
		local index = 2
		for step = 1, math.floor(total / spacing) do
			local target = spacing * step
			while index < #arcs and arcs[index] < target do
				index += 1
			end
			local a, b = points[index - 1], points[index]
			local position =
				flat(a:Lerp(b, (target - arcs[index - 1]) / (arcs[index] - arcs[index - 1])))
			local piece = pieces[index]
			-- One planter to a cell: two polylines meeting at a junction would otherwise each
			-- plant one in it, and the strip under them is a single square of grass.
			local cell = cellKey(position, tiles.tileStuds)
			if not taken[cell] and not blocked(position) then
				taken[cell] = true
				table.insert(trees, {
					polyline = run.polyline,
					stretch = piece.stretch,
					step = step,
					position = position,
					-- Hashed, not drawn: the same planter turns the same way everywhere.
					yaw = Noise.Hash(`{run.polyline}:{piece.stretch}:{step}`)
						% FULL_CIRCLE_DEGREES
						/ FULL_CIRCLE_DEGREES
						* FULL_TURN,
				})
			end
		end
	end
	table.sort(trees, function(a: ParkTree, b: ParkTree): boolean
		if a.polyline ~= b.polyline then
			return a.polyline < b.polyline
		end
		if a.stretch ~= b.stretch then
			return a.stretch < b.stretch
		end
		return a.step < b.step
	end)
	local cap = math.max(math.floor(numberOr(config.maxTrees, 0)), 0)
	local count = #trees
	if count <= cap then
		return trees
	end
	local kept: { ParkTree } = {}
	for index, tree in trees do
		if (index * cap) // count ~= ((index - 1) * cap) // count then
			table.insert(kept, tree)
		end
	end
	return kept
end

-- The highest count a cumulative `perTier` list reaches, which is what a plan is drawn up for.
local function perTierMax(perTier: { number }?): number
	if type(perTier) ~= "table" then
		return 0
	end
	local best = 0
	for _, value in perTier do
		best = math.max(best, math.floor(numberOr(value, 0)))
	end
	return best
end

-- The first tier at which a cumulative `perTier` list shows `rank` pieces; nil when it never does.
local function tierForRank(perTier: { number }?, rank: number): number?
	if type(perTier) ~= "table" then
		return nil
	end
	local running = 0
	for tier, value in perTier do
		running = math.max(running, math.floor(numberOr(value, 0)))
		if running >= rank then
			return tier
		end
	end
	return nil
end

-- A wave 2c budget key a stale config lacks turns its feature off rather than guessing a ceiling.
local function budgetCap(value: number?): number
	return math.max(math.floor(numberOr(value, 0)), 0)
end

local function nonEmptyList(value: any): boolean
	return type(value) == "table" and #value > 0
end

-- The spine piece drawn nearest `point`, over every piece the plot can ever draw.
local function nearestPieceId(lines: RoadGraph.StreetLines, point: Vector3): string?
	local best, bestId = math.huge, nil
	for _, run in lines.runs do
		for _, piece in run.pieces do
			for index = 2, #piece.points do
				local closest =
					RoadGraph.ClosestOnSegment(point, piece.points[index - 1], piece.points[index])
				local distance = (closest - point).Magnitude
				if distance < best then
					best, bestId = distance, piece.pieceId
				end
			end
		end
	end
	return bestId
end

-- The XZ union of an era prop list's harvested bounds, nil while none of them is harvested.
local function harvestedUnion(eraName: string, names: { string }): Extents?
	local assets = Catalog.GetAssetsConfig()
	local propsByEra = if assets ~= nil then assets.props else nil
	local eraProps: { [string]: Types.AssetModel }? = if propsByEra ~= nil
		then propsByEra[eraName]
		else nil
	if eraProps == nil then
		return nil
	end
	local union: Extents? = nil
	for _, name in names do
		local extents = modelExtents(eraProps[name])
		if extents == nil then
			continue
		end
		local current = union
		if current == nil then
			union = table.clone(extents)
		else
			widen(current, extents)
		end
	end
	return union
end

-- A point on one side of a lot's rectangle, in the lot's own frame (front -Z faces the street):
-- side 1 left, 2 right, 3 back, 4 front; `along` runs 0..1 down that side, `out` beyond it.
local function lotSidePoint(extents: Extents, side: number, along: number, out: number): Vector3
	local alongX = extents.minX + along * (extents.maxX - extents.minX)
	local alongZ = extents.minZ + along * (extents.maxZ - extents.minZ)
	if side == 1 then
		return Vector3.new(extents.minX - out, 0, alongZ)
	elseif side == 2 then
		return Vector3.new(extents.maxX + out, 0, alongZ)
	elseif side == 3 then
		return Vector3.new(alongX, 0, extents.maxZ + out)
	end
	return Vector3.new(alongX, 0, extents.minZ - out)
end

-- A harvested prop's XZ bounds about its anchor at `scale`, nil before it is harvested.
local function scaledExtents(eraName: string, propName: string, scale: number): Extents?
	local extents = harvestedUnion(eraName, { propName })
	if extents == nil then
		return nil
	end
	return {
		minX = extents.minX * scale,
		maxX = extents.maxX * scale,
		minZ = extents.minZ * scale,
		maxZ = extents.maxZ * scale,
	}
end

-- Wave 2d: where `props` sit end to end along a bay's long axis (the car's own Z, front -Z),
-- centred on the bay with `gap` between them -- each car's anchor Z in the bay frame. The bay is
-- `bayLength` long about `centre`; nil when the row is longer than that, the length is unknown,
-- or anything in the row is not harvested yet, and the bay keeps its first car alone.
local function packBay(
	eraName: string,
	props: { string },
	scale: number,
	gap: number,
	bayLength: number?,
	centre: number
): { number }?
	if bayLength == nil then
		return nil
	end
	local lengths: { number } = {}
	local fronts: { number } = {}
	local total = gap * (#props - 1)
	for index, name in props do
		local extents = scaledExtents(eraName, name, scale)
		if extents == nil then
			return nil
		end
		lengths[index] = extents.maxZ - extents.minZ
		fronts[index] = extents.minZ
		total += lengths[index]
	end
	if total > bayLength then
		return nil
	end
	local anchors: { number } = {}
	local cursor = centre - total / 2
	for index in props do
		anchors[index] = cursor - fronts[index]
		cursor += lengths[index] + gap
	end
	return anchors
end

-- A bay's ground (wave 2d): the pool's built-size harvested union, and the length a row of packed
-- cars may fill -- `parked.bayLength` when set, else that union's length (nil before harvest).
local function bayShape(eraName: string, parked: Types.ParkedConfig): (Extents?, number?)
	local union = harvestedUnion(eraName, parked.props)
	local configured = numberOr(parked.bayLength, 0)
	if configured > 0 and configured < math.huge then
		return union, configured
	end
	return union, if union ~= nil then union.maxZ - union.minZ else nil
end

-- Parked vehicles (docs/INTERFACES.md "Wave 2c — Parked vehicles", "Wave 2d"): the layout's spots
-- in (tier, index) order, as many bays as the cumulative `parked.perTier` names, and cars into
-- them until `budget.parked` (which counts cars) runs out. One prop draw per spot, kept or not, so
-- a spot's pick never depends on the ones before it being kept; wave 2d's extra cars per bay draw
-- after all of those, so a bay's first car is the pick it always had.
local function parkedSpots(
	input: PlanInput,
	rng: Random,
	streetLines: () -> RoadGraph.StreetLines
): { ParkedSpot }
	local parked = input.era.parked
	local spots: { Types.ParkingSpotLayout }? = input.layout.parking
	if parked == nil or spots == nil or #spots == 0 or not nonEmptyList(parked.props) then
		return {}
	end
	local bayCap = perTierMax(parked.perTier)
	local carsLeft = budgetCap(input.config.budget.parked)
	local picks: { string } = {}
	for index in spots do
		picks[index] = parked.props[pickIndex(rng:NextNumber(), #parked.props) :: number]
	end
	local perBay = math.clamp(math.floor(numberOr(parked.perBay, 1)), 1, MAX_PER_BAY)
	local extraPicks: { { string } } = {}
	for index in spots do
		local extra: { string } = {}
		for car = 2, perBay do
			extra[car - 1] = parked.props[pickIndex(rng:NextNumber(), #parked.props) :: number]
		end
		extraPicks[index] = extra
	end
	local scale = PropFactory.ScaleOf(parked.scale)
	local gap = math.max(numberOr(parked.gap, DEFAULT_PARKED_GAP), 0)
	-- The row is centred on the pool's union, the ground a single car always stood on.
	local bayExtents, bayLength = bayShape(input.eraName, parked)
	local bayCentre = if bayExtents ~= nil then (bayExtents.minZ + bayExtents.maxZ) / 2 else 0
	local order: { number } = {}
	for index in spots do
		table.insert(order, index)
	end
	table.sort(order, function(a: number, b: number): boolean
		local tierA, tierB = numberOr(spots[a].tier, 0), numberOr(spots[b].tier, 0)
		if tierA ~= tierB then
			return tierA < tierB
		end
		return a < b
	end)
	local lines = streetLines()
	local planned: { ParkedSpot } = {}
	for rank, index in order do
		if rank > bayCap or carsLeft <= 0 then
			break
		end
		local rankTier = tierForRank(parked.perTier, rank)
		if rankTier == nil then
			break
		end
		local spot = spots[index]
		local position = flat(spot.position)
		local rotationY = numberOr(spot.rotationY, 0)
		local tier = math.max(numberOr(spot.tier, 0), rankTier)
		local pieceId = nearestPieceId(lines, position)
		local props: { string } = { picks[index] }
		for _, name in extraPicks[index] do
			if #props >= carsLeft then
				break
			end
			table.insert(props, name)
		end
		local anchors = if #props > 1
			then packBay(input.eraName, props, scale, gap, bayLength, bayCentre)
			else nil
		if anchors == nil then
			-- A lone car keeps the anchor it always had.
			props = { props[1] }
			anchors = { 0 }
		end
		local along = anchors :: { number }
		-- The car frame's +Z in the plot, as Scatter.PropFrame turns it.
		local radians = math.rad(rotationY)
		local axis = Vector3.new(math.sin(radians), 0, math.cos(radians))
		for car, name in props do
			table.insert(planned, {
				position = if along[car] == 0 then position else position + axis * along[car],
				rotationY = rotationY,
				prop = name,
				tier = tier,
				lot = spot.lot,
				pieceId = pieceId,
				bay = rank,
				bayPosition = position,
			})
		end
		carsLeft -= #props
	end
	return planned
end

-- Greenery (docs/INTERFACES.md "Wave 2c — Greenery"): zone pieces spread round-robin over the
-- zones so each tier step greens every zone a little, then garnish around each lot that holds a
-- house, lots taken in (tier, index) order so the budget runs out on the latest ones. Every
-- candidate costs a fixed four draws, kept or rejected, so the stream never depends on a test.
local function greenerySpots(input: PlanInput, plan: Plan, rng: Random): { GreenerySpot }
	local era = input.era
	local greenery = era.greenery
	if greenery == nil or not nonEmptyList(greenery.props) then
		return {}
	end
	local budget = budgetCap(input.config.budget.greenery)
	local zoneCap = math.min(perTierMax(greenery.perTier), budget)
	local props = greenery.props
	local clearance = math.max(numberOr(greenery.clearance, 0), 0)
	-- A piece counts as a disc of half the spacing, so two neighbours at most touch.
	local reach = clearance / 2
	local meander = era.road.meander
	local tiles = era.road.tiles
	local pavement = if tiles ~= nil and tiles.pavement ~= nil then tiles.pavement.width else 0
	local roadKeep = input.roadWidth / 2
		+ (if meander ~= nil then meander.amplitude else 0)
		+ math.max(pavement, 0)
		+ math.max(numberOr(greenery.roadClearance, 0), 0)
	-- Walkers stroll along the verge; a bush on their line would have them walk through it.
	local pedestrians = era.pedestrians
	if pedestrians ~= nil then
		roadKeep = math.max(roadKeep, numberOr(pedestrians.offset, 0) + reach)
	end
	local margin = input.config.trees.edgeMargin
	local halfX = input.plotSize.X / 2 - margin
	local halfZ = input.plotSize.Z / 2 - margin
	-- The plot sign straddles the front (-Z) edge centre (PlotService.buildWorld).
	local sign = Vector3.new(0, 0, -input.plotSize.Z / 2)
	local solids, lotFootprints = solidsFor(input)
	-- Parked vehicles stand on their bays whatever the tier; a hedge must not grow under one. The
	-- whole bay stays clear -- the built-size union, stretched about its centre to `bayLength` when
	-- that is longer -- not just the scaled cars packed into it.
	local parked = era.parked
	local parkedExtents: Extents? = nil
	if parked ~= nil and nonEmptyList(parked.props) then
		local union, length = bayShape(input.eraName, parked)
		if union ~= nil then
			local grown = table.clone(union)
			if length ~= nil and length > union.maxZ - union.minZ then
				local centre = (union.minZ + union.maxZ) / 2
				grown.minZ = centre - length / 2
				grown.maxZ = centre + length / 2
			end
			parkedExtents = grown
		end
	end
	local lastBay = 0
	for _, spot in plan.parked do
		if spot.bay == lastBay then
			continue
		end
		lastBay = spot.bay
		table.insert(solids, {
			origin = spot.bayPosition,
			rotation = CFrame.Angles(0, math.rad(spot.rotationY), 0),
			extents = parkedExtents or centredExtents(0, 0),
		})
	end
	local taken: { Vector3 } = {}
	for _, tree in plan.trees do
		table.insert(taken, tree.position)
	end

	local function accepted(point: Vector3): boolean
		if math.abs(point.X) > halfX or math.abs(point.Z) > halfZ then
			return false
		end
		if (point - sign).Magnitude < era.trees.clearance then
			return false
		end
		for _, footprint in solids do
			if insideFootprint(footprint, point, reach) then
				return false
			end
		end
		for _, other in taken do
			if (other - point).Magnitude < clearance then
				return false
			end
		end
		for _, line in input.centrelines do
			if nearLine(point, line, roadKeep) then
				return false
			end
		end
		return true
	end

	local byZone: { { GreenerySpot } } = {}
	local zones: { Types.TreeZoneLayout } = input.layout.greeneryZones or {}
	for zoneIndex, zone in zones do
		local kept: { GreenerySpot } = {}
		byZone[zoneIndex] = kept
		local radius = math.max(numberOr(zone.radius, 0), 0)
		for _ = 1, math.max(math.floor(numberOr(zone.count, 0)), 0) do
			local radial = radius * math.sqrt(rng:NextNumber())
			local angle = FULL_TURN * rng:NextNumber()
			local yaw = FULL_TURN * rng:NextNumber()
			local prop = props[pickIndex(rng:NextNumber(), #props) :: number]
			local point = Vector3.new(
				zone.center.X + radial * math.cos(angle),
				0,
				zone.center.Z + radial * math.sin(angle)
			)
			if accepted(point) then
				table.insert(taken, point)
				table.insert(kept, { position = point, yaw = yaw, prop = prop })
			end
		end
	end
	local spots: { GreenerySpot } = {}
	local round = 1
	local more = true
	while more and #spots < zoneCap do
		more = false
		for _, kept in byZone do
			local spot = kept[round]
			if spot == nil then
				continue
			end
			more = true
			if #spots < zoneCap then
				spot.tier = tierForRank(greenery.perTier, #spots + 1)
				table.insert(spots, spot)
			end
		end
		round += 1
	end

	local perLot = math.max(math.floor(numberOr(greenery.lotGarnish, 0)), 0)
	local lots: { Types.LotLayout } = input.layout.lots or {}
	local lotOrder: { number } = {}
	for index in lots do
		if plan.lotProps[index] ~= nil and lotFootprints[index] ~= nil then
			table.insert(lotOrder, index)
		end
	end
	table.sort(lotOrder, function(a: number, b: number): boolean
		local tierA, tierB = numberOr(lots[a].tier, 0), numberOr(lots[b].tier, 0)
		if tierA ~= tierB then
			return tierA < tierB
		end
		return a < b
	end)
	-- A hair beyond the reach the solids test keeps, so a garnish clears its own lot.
	local out = reach + MIN_STEP
	for _, lotIndex in lotOrder do
		local footprint = lotFootprints[lotIndex]
		for _ = 1, perLot do
			local side = pickIndex(rng:NextNumber(), LOT_SIDES) :: number
			local along = rng:NextNumber()
			local yaw = FULL_TURN * rng:NextNumber()
			local prop = props[pickIndex(rng:NextNumber(), #props) :: number]
			if #spots >= budget then
				continue
			end
			local localPoint = lotSidePoint(footprint.extents, side, along, out)
			local point = flat(footprint.origin + footprint.rotation:PointToWorldSpace(localPoint))
			if accepted(point) then
				table.insert(taken, point)
				table.insert(spots, { position = point, yaw = yaw, prop = prop, lot = lotIndex })
			end
		end
	end
	return spots
end

-- Walkers (docs/INTERFACES.md "Wave 2c — Pedestrians"): one prop draw per walker the era can
-- ever show, so the tier only decides how many of them walk.
local function walkerProps(input: PlanInput, rng: Random): { string }
	local pedestrians = input.era.pedestrians
	if pedestrians == nil or not nonEmptyList(pedestrians.props) then
		return {}
	end
	local cap =
		math.min(perTierMax(pedestrians.perTier), budgetCap(input.config.budget.walkersPerPlot))
	local picks: { string } = {}
	for index = 1, cap do
		picks[index] = pedestrians.props[pickIndex(rng:NextNumber(), #pedestrians.props) :: number]
	end
	return picks
end

-- Bird flocks (docs/INTERFACES.md "Wave 2c — Ambient"): flock i circles tree zone
-- ((i - 1) % #zones + 1). Two draws per flock and three per bird, whatever is later shown.
local function flocks(input: PlanInput, rng: Random): { Flock }
	local ambient = input.config.ambient
	local birds = if ambient ~= nil then ambient.birds else nil
	local zones: { Types.TreeZoneLayout } = input.layout.treeZones or {}
	if birds == nil or #zones == 0 then
		return {}
	end
	-- One plot can never show more birds than the whole map may.
	local perFlock = math.min(
		math.max(math.floor(numberOr(birds.birdsPerFlock, 0)), 0),
		budgetCap(input.config.budget.birdsMap)
	)
	local planned: { Flock } = {}
	for index = 1, perTierMax(birds.flocksPerTier) do
		local zone = zones[(index - 1) % #zones + 1]
		local flock: Flock = {
			center = flat(zone.center),
			phase = FULL_TURN * rng:NextNumber(),
			clockwise = rng:NextNumber() < 0.5,
			birds = {},
		}
		for _ = 1, perFlock do
			table.insert(flock.birds, {
				lead = rng:NextNumber(),
				radial = rng:NextNumber(),
				lift = rng:NextNumber(),
			})
		end
		table.insert(planned, flock)
	end
	return planned
end

function Scatter.Plan(input: PlanInput): Plan
	local rng = Random.new(Scatter.Seed(input.plotIndex, input.eraName))
	local era = input.era
	local layout = input.layout
	-- Both street-line readers share one sampling pass; neither runs in an era that needs neither.
	local cachedLines: RoadGraph.StreetLines? = nil
	local function streetLines(): RoadGraph.StreetLines
		local lines = cachedLines
		if lines == nil then
			lines = input.streetLines()
			cachedLines = lines
		end
		return lines :: RoadGraph.StreetLines
	end
	-- Walked before the zones and without a single Random draw, so every later feature sees exactly
	-- the stream it saw before this wave; thinned evenly over its own numeric order, like row lamps.
	local streetTrees = streetTreeSpots(input, streetLines)
	local treeCap = math.min(math.max(era.trees.maxCount, 0), input.config.budget.trees)
	local streetCount = #streetTrees
	if streetCount > treeCap then
		local thinned: { TreeSpot } = {}
		for index, spot in streetTrees do
			if (index * treeCap) // streetCount ~= ((index - 1) * treeCap) // streetCount then
				table.insert(thinned, spot)
			end
		end
		streetTrees = thinned
	end
	local plan: Plan = {
		trees = treeSpots(input, rng, #streetTrees),
		lotProps = {},
		plazaAllowed = {},
		lampSlots = {},
		lampPosts = {},
		parkTrees = {},
		subwayEntrances = {},
		vehicleProps = {},
		greenery = {},
		parked = {},
		walkerProps = {},
		flocks = {},
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
	local smallProps: { string } = era.houses.smallProps or {}
	for index, lot in lots do
		-- One draw per lot whatever its kind, so a lot's kind never shifts the stream behind it.
		local pool = if lot.kind == SMALL_LOT then smallProps else houseProps
		local pick = pickIndex(rng:NextNumber(), #pool)
		if pick ~= nil and remaining > 0 then
			plan.lotProps[index] = pool[pick]
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
	-- Row placement lines the streets instead. The shuffle above still runs either way, so the
	-- choice of placement never shifts the Random stream the vehicles draw from.
	if era.lamps.prop ~= nil and era.lamps.placement ~= ROW_PLACEMENT then
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
	for _, spot in streetTrees do
		table.insert(plan.trees, spot)
	end
	plan.lampPosts = lampPosts(input, streetLines)
	plan.parkTrees = parkStripTrees(input, streetLines)
	plan.subwayEntrances = subwaySpots(input, streetLines)

	local vehicleProps = era.vehicles.props
	local vehicleCap =
		math.min(math.max(era.vehicles.perPlot, 0), input.config.budget.vehiclesPerPlot)
	for index = 1, vehicleCap do
		local pick = pickIndex(rng:NextNumber(), #vehicleProps)
		if pick ~= nil then
			plan.vehicleProps[index] = vehicleProps[pick]
		end
	end

	-- Wave 2c: new streams only, so nothing above moves when these keys arrive or change.
	local seed = Scatter.Seed(input.plotIndex, input.eraName)
	local parkedRng = Random.new(seed + PARKED_SALT)
	plan.parked = parkedSpots(input, parkedRng, streetLines)
	local greeneryRng = Random.new(seed + GREENERY_SALT)
	plan.greenery = greenerySpots(input, plan, greeneryRng)
	plan.walkerProps = walkerProps(input, Random.new(seed + WALKERS_SALT))
	plan.flocks = flocks(input, Random.new(seed + AMBIENT_SALT))
	return plan
end

-- How many of a cumulative `perTier` list show at `tier` (tier 0, or a malformed entry, is none).
function Scatter.PerTier(perTier: { number }?, tier: number): number
	if type(perTier) ~= "table" or tier < 1 then
		return 0
	end
	local count = 0
	for index = 1, math.min(tier, #perTier) do
		count = math.max(count, math.floor(numberOr(perTier[index], 0)))
	end
	return count
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

-- Everything solid the planner already knows about a plot: every slot and its pad, every filler
-- lot, plaza and subway kiosk. Shared so a caller placing something of its own (the highway sign)
-- can ask the same question the trees and the row lamps do, instead of guessing.
-- Wave 2c: what walkers must stay out of -- every solid above plus the street furniture the plot
-- stands on its pavements (`frames` plot-local, each with the prop it holds), sized by that prop's
-- harvested bounds or, before harvest, as a point the walker's clearance grows around.
function Scatter.WalkSolids(
	input: PlanInput,
	furniture: { { frame: CFrame, prop: string? } }
): { Footprint }
	-- Pads are flat ground a walker crosses (a Metropolis block pad covers the pavement); every
	-- other solid stays.
	local solids: { Footprint } = {}
	for _, footprint in footprintsFor(input) do
		if not footprint.pad then
			table.insert(solids, footprint)
		end
	end
	for _, item in furniture do
		local prop = item.prop
		local extents = if prop ~= nil then harvestedUnion(input.eraName, { prop }) else nil
		table.insert(solids, {
			origin = flat(item.frame.Position),
			rotation = item.frame.Rotation,
			extents = extents or centredExtents(0, 0),
		})
	end
	return solids
end

function Scatter.Solids(input: PlanInput): { Footprint }
	return footprintsFor(input)
end

-- Whether a `margin`-radius square at `position` (plot-local) misses every solid. The margin is
-- the thing's own half-extent, which makes the test exact for an axis-aligned prop and
-- conservative for a turned one -- erring toward not placing it.
function Scatter.Clear(solids: { Footprint }, position: Vector3, margin: number): boolean
	for _, footprint in solids do
		if insideFootprint(footprint, flat(position), margin) then
			return false
		end
	end
	return true
end

-- Wave 2a: every subway kiosk's ground as an axis-aligned plot-local rectangle (the corners of its
-- extents turned by its rotation, then bounded), which is the shape the tile renderer cuts its park
-- strips around. Empty in an era without kiosks, so the caller can ask for any plot.
function Scatter.KioskRects(input: PlanInput): { Rect }
	local rects: { Rect } = {}
	for _, kiosk in subwayFootprints(input) do
		local extents = kiosk.extents
		local rect: Rect? = nil
		for _, corner in
			{
				Vector3.new(extents.minX, 0, extents.minZ),
				Vector3.new(extents.maxX, 0, extents.minZ),
				Vector3.new(extents.minX, 0, extents.maxZ),
				Vector3.new(extents.maxX, 0, extents.maxZ),
			}
		do
			local point = kiosk.origin + kiosk.rotation:PointToWorldSpace(corner)
			local current = rect
			if current == nil then
				rect = { x0 = point.X, x1 = point.X, z0 = point.Z, z1 = point.Z }
			else
				current.x0 = math.min(current.x0, point.X)
				current.x1 = math.max(current.x1, point.X)
				current.z0 = math.min(current.z0, point.Z)
				current.z1 = math.max(current.z1, point.Z)
			end
		end
		if rect ~= nil then
			table.insert(rects, rect)
		end
	end
	return rects
end

function Scatter.PropFrame(position: Vector3, rotationY: number): CFrame
	return CFrame.new(flat(position)) * CFrame.Angles(0, math.rad(rotationY), 0)
end

return Scatter
