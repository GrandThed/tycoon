--!strict
-- M9 city dressing lifecycle (docs/INTERFACES.md "M9 contracts — LOD and lifecycle"). Every
-- plot is dressed purely from what the server replicates: the plot folder's EraName and
-- GrowthTier attributes, the Building_<slotId> children of its Buildings folder, and its Base
-- (centre, size and orientation). Dressing lives in the client-created
-- Workspace/CityDressing/Plot<n>; nothing is ever parented into or changed under
-- Workspace/Plots, and nothing is sent to the server.
--
-- Each plot reconciles in one deferred `sync`: attribute and Buildings events only mark it,
-- so a server rebuild (24 removals + 24 additions + two attribute writes in one frame) costs a
-- single pass. Dressing only adds while a plot grows; an era change, a tier drop, or a drawn
-- spur whose building is gone clears the plot and rebuilds it. Near/far LOD (trees, lamps,
-- vehicles) and the vehicle-plot selection refresh every lod.refreshSeconds on a task.delay
-- chain. A missing (or pre-budget) CityDressing config means the controller does nothing at all.
--
-- Wave 1d: paths in eras with baked meshes are drawn by PathRenderer (through RoadGraph) on near
-- and far plots alike; only their rims follow the near/far flip. A path revealed by a purchase on
-- a near plot pops in with a dust burst; anything revealed while a build is still settling (join,
-- rejoin, era rebuild) appears at once.
--
-- Wave 1e: the owned set also picks the plot's street surface (RoadGraph.SetSurface, before the
-- renderer clones anything), and gates the lamp rows and crossing signals of eras whose config
-- names an upgrade slot. Still nothing but what the server already replicates.
--
-- Wave 2a: the same owned set drives the elevated highway ring and the subway entrances of a tiles
-- era. The ring's cars are a second Traffic "plot" on the same map budget, keyed by the plot index
-- negated, so they are cleared and counted exactly like the street ones. Park strips fill the
-- corridors that have not grown yet; their planters are the one dressing prop that also goes away,
-- as the tiles arrive under them.
--
-- Wave 2b: the ring may run in loop mode (the Orbital monorail) with its own deck vehicles, and the
-- player's `cityDetail` setting (pushed by UIController through SetCityDetail) thins what every
-- plot shows. The whole "detail off" rule lives in `detailPolicy`; the plan never changes with it,
-- so turning detail back on restores exactly what was there, and a flip only re-syncs the plots.
--
-- Wave 2c ("living city"): near plots also get greenery, parked vehicles, chimney smoke and bird
-- flocks, and the vehicle plots get walkers on their own loop (Walkers) with their own map budget.
-- All of it is planned by Scatter from salted streams, grows with the tier, and goes on far plots;
-- lots and their houses stay, since they are the city's silhouette.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local Theme = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))
local AssetPreloader = require(script.Parent:WaitForChild("AssetPreloader"))
local cityFolder = script.Parent.Parent:WaitForChild("City")
local PropFactory = require(cityFolder:WaitForChild("PropFactory"))
local RoadGraph = require(cityFolder:WaitForChild("RoadGraph"))
local Highway = require(cityFolder:WaitForChild("Highway"))
local Scatter = require(cityFolder:WaitForChild("Scatter"))
local Traffic = require(cityFolder:WaitForChild("Traffic"))
local Walkers = require(cityFolder:WaitForChild("Walkers"))
local Ambient = require(cityFolder:WaitForChild("Ambient"))

-- World naming frozen since M1/M9 (docs/INTERFACES.md), shared with PlotVisualsController.
local PLOTS_FOLDER = "Plots"
local PLOT_NAME_PATTERN = "^Plot_(%d+)$"
local BUILDINGS_FOLDER = "Buildings"
local BUILDING_NAME_PATTERN = "^Building_(.+)$"
local BASE_NAME = "Base"
local ERA_NAME_ATTRIBUTE = "EraName"
local GROWTH_TIER_ATTRIBUTE = "GrowthTier"
local PLOT_INDEX_ATTRIBUTE = "PlotIndex"
-- Wave 1e: a crossing prop waits until this many of its node's streets are drawn, so it never
-- stands beside a single road (docs/INTERFACES.md "Wave 1e — Lamps").
local SIGNAL_MIN_VISIBLE = 2
-- `detail.treeShare` for a config that predates the key: the contract's "halve".
local DEFAULT_TREE_SHARE = 0.5
-- Wave 2c: how far walkers keep from solids when `pedestrians.clearance` is missing (lead ruling,
-- the figure's half-width plus a hand's breadth); the config value wins whenever it is present.
local DEFAULT_WALK_CLEARANCE = 0.6

type TreeInstance = { model: Model, stage: number }

-- What the `cityDetail` setting allows right now. A nil cap = every planned tree / planter.
type DetailPolicy = {
	treeCap: number?,
	parkTreeCap: number?,
	lamps: boolean,
	vehiclesLocalOnly: boolean,
	-- Wave 2c: the share of planned greenery kept, and whether parked cars, walkers, smoke and
	-- birds show at all. Houses are never thinned: they are the city's silhouette.
	greeneryShare: number,
	living: boolean,
}

type Build = {
	eraName: string,
	era: Types.CityEraDressingConfig,
	layout: Types.EraLayout,
	plotFrame: CFrame,
	roads: RoadGraph.State,
	plan: Scatter.Plan,
	-- Wave 2c: kept so the walker lanes can ask the planner for the plot's solids on a rebuild.
	planInput: Scatter.PlanInput,
	houses: { [number]: Model },
	plazas: { [number]: Model },
	trees: { [number]: TreeInstance },
	-- Wave 2a: planters on the park strips, by plan index. Unlike every other prop here they also
	-- go away again -- when the street under them is paved.
	parkTrees: { [number]: Model },
	-- Keyed by junction slot id or, with row placement, by the post's plan key.
	lamps: { [string]: Model },
	signalSpots: { RoadGraph.SignalSpot },
	signals: { [number]: Model }, -- crossing node -> prop
	-- Wave 2a: nil in an era without a highway or without a `highway` layout table.
	highway: Highway.Handle?,
	subways: { [number]: Model }, -- plan index -> entrance prop
	-- Wave 2c, near plots only: plan index -> prop, and lot index -> the plume on its house.
	greenery: { [number]: Model },
	parked: { [number]: Model },
	smoke: { [number]: Attachment },
	createdAt: number, -- os.clock when the build started
}

type PlotEntry = {
	index: number,
	plot: Instance,
	folder: Folder,
	connections: { RBXScriptConnection },
	tier: number,
	near: boolean,
	vehicleSelected: boolean,
	vehicleTarget: number,
	-- Wave 2a: cars looping the highway deck, counted against the same per-plot ceiling, and the
	-- same "the map budget was full" retry flag the street vehicles carry.
	highwayTarget: number,
	highwayBlocked: boolean,
	-- The last spawn placed fewer vehicles than models because the map budget was full.
	vehiclesBlocked: boolean,
	-- Wave 2c: walkers (on the vehicle plots) and birds (on near plots), each with the same
	-- "the map budget was full" retry flag.
	walkerTarget: number,
	walkersBlocked: boolean,
	flockTarget: number,
	birdsBlocked: boolean,
	-- os.clock when a drawn spur's building was first seen missing; nil while none is. A server
	-- cosmetics refresh respawns every building in one frame but replication spreads it over
	-- several, so a missing building is only trusted after a full LOD interval.
	suspectSince: number?,
	-- Set by the LOD tick once that interval has passed: the next sync may rebuild.
	confirmSuspect: boolean,
	-- The roads were redrawn by a fallback renderer, so the vehicles' lane graph is out of date.
	lanesStale: boolean,
	scheduled: boolean,
	build: Build?,
}

local player = Players.LocalPlayer
local entries: { [Instance]: PlotEntry } = {}
local rootFolder: Folder? = nil
local started = false
-- The profile default; an old snapshot without the key never reaches SetCityDetail as false.
local cityDetail = true

-- Silent degradation (M9 principles): a config file too old to carry the part ceilings can't be
-- allocated against, so it counts as no config at all rather than erroring mid-build.
local function dressingConfig(): Types.CityDressingConfig?
	local config = Catalog.GetCityDressingConfig()
	if config == nil or type(config.budget) ~= "table" then
		return nil
	end
	return config
end

-- The single place the `cityDetail` setting turns into rules, so a later dressing kind that detail
-- off should also drop is added here and nowhere else. Detail on is the unrestricted policy, which
-- leaves every sync path exactly as it was before the setting existed.
local function detailPolicy(
	era: Types.CityEraDressingConfig,
	config: Types.CityDressingConfig
): DetailPolicy
	if cityDetail then
		return {
			treeCap = nil,
			parkTreeCap = nil,
			lamps = true,
			vehiclesLocalOnly = false,
			greeneryShare = 1,
			living = true,
		}
	end
	local detail = config.detail
	local share = math.clamp(
		RoadGraph.BudgetValue(if detail ~= nil then detail.treeShare else nil, DEFAULT_TREE_SHARE),
		0,
		1
	)
	local full = math.min(math.max(era.trees.maxCount, 0), config.budget.trees)
	local tiles = era.road.tiles
	local parkStrips = if tiles ~= nil then tiles.parkStrips else nil
	local parkFull = if parkStrips ~= nil
		then math.max(RoadGraph.BudgetValue(parkStrips.maxTrees, 0), 0)
		else 0
	return {
		treeCap = math.floor(full * share),
		parkTreeCap = math.floor(parkFull * share),
		lamps = false,
		vehiclesLocalOnly = true,
		greeneryShare = share,
		living = false,
	}
end

local function baseOf(plot: Instance): BasePart?
	local base = plot:FindFirstChild(BASE_NAME)
	return if base ~= nil and base:IsA("BasePart") then base else nil
end

local function tierOf(plot: Instance, config: Types.CityDressingConfig): number
	local value = plot:GetAttribute(GROWTH_TIER_ATTRIBUTE)
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, #config.tier.thresholds)
end

-- Owned slots of the plot's current layout, sorted so spur order is identical everywhere.
local function ownedSlotIds(
	plot: Instance,
	layout: Types.EraLayout
): ({ string }, { [string]: boolean })
	local list: { string } = {}
	local set: { [string]: boolean } = {}
	local buildings = plot:FindFirstChild(BUILDINGS_FOLDER)
	if buildings == nil then
		return list, set
	end
	for _, child in buildings:GetChildren() do
		local slotId = string.match(child.Name, BUILDING_NAME_PATTERN)
		if slotId ~= nil and layout.slots[slotId] ~= nil and not set[slotId] then
			set[slotId] = true
			table.insert(list, slotId)
		end
	end
	table.sort(list)
	return list, set
end

local function clearTrees(build: Build): ()
	for _, tree in build.trees do
		tree.model:Destroy()
	end
	table.clear(build.trees)
end

local function clearParkTrees(build: Build): ()
	for _, tree in build.parkTrees do
		tree:Destroy()
	end
	table.clear(build.parkTrees)
end

local function clearLamps(build: Build): ()
	for _, lamp in build.lamps do
		lamp:Destroy()
	end
	table.clear(build.lamps)
end

local function clearSignals(build: Build): ()
	for _, signal in build.signals do
		signal:Destroy()
	end
	table.clear(build.signals)
end

local function clearSubways(build: Build): ()
	for _, entrance in build.subways do
		entrance:Destroy()
	end
	table.clear(build.subways)
end

local function clearGreenery(build: Build): ()
	for _, piece in build.greenery do
		piece:Destroy()
	end
	table.clear(build.greenery)
end

local function clearParked(build: Build): ()
	for _, vehicle in build.parked do
		vehicle:Destroy()
	end
	table.clear(build.parked)
end

-- The houses stay (far plots keep them); only the plumes on them go.
local function clearSmoke(build: Build): ()
	for _, plume in build.smoke do
		plume:Destroy()
	end
	table.clear(build.smoke)
end

-- The highway's cars are their own Traffic plot; the index is negated so it can never collide with
-- a street one (plots are numbered from 1).
local function highwayPlotId(index: number): number
	return -index
end

local function clearBuild(entry: PlotEntry): ()
	local build = entry.build
	Traffic.ClearPlot(entry.index)
	Traffic.ClearPlot(highwayPlotId(entry.index))
	Walkers.ClearPlot(entry.index)
	Ambient.ClearPlot(entry.index)
	entry.walkerTarget = 0
	entry.walkersBlocked = false
	entry.flockTarget = 0
	entry.birdsBlocked = false
	entry.vehicleTarget = 0
	entry.highwayTarget = 0
	entry.highwayBlocked = false
	entry.vehiclesBlocked = false
	entry.suspectSince = nil
	entry.confirmSuspect = false
	if build == nil then
		return
	end
	entry.build = nil
	RoadGraph.Destroy(build.roads)
	local highway = build.highway
	if highway ~= nil then
		Highway.Destroy(highway)
	end
	clearTrees(build)
	clearParkTrees(build)
	clearLamps(build)
	clearSignals(build)
	clearSubways(build)
	clearGreenery(build)
	clearParked(build)
	clearSmoke(build)
	for _, model in build.houses do
		model:Destroy()
	end
	for _, model in build.plazas do
		model:Destroy()
	end
	entry.folder:ClearAllChildren()
end

-- Forward-declared: a build's fallback callback schedules its own plot.
local schedule: (entry: PlotEntry) -> ()

local function newBuild(
	entry: PlotEntry,
	config: Types.CityDressingConfig,
	eraName: string,
	base: BasePart
): Build?
	local era = config.eras[eraName]
	local layout = Catalog.GetLayout(eraName)
	if era == nil or layout == nil then
		return nil
	end
	-- Cheap when repeated (the preloader dedups), and covers other players' eras.
	AssetPreloader.PreloadEra(eraName, false)
	local plotFrame = base.CFrame * CFrame.new(0, base.Size.Y / 2, 0)
	local roads = RoadGraph.new({
		folder = entry.folder,
		plotFrame = plotFrame,
		layout = layout,
		eraName = eraName,
		seed = Scatter.Seed(entry.index, eraName),
		config = config,
		era = era,
		onRoadsRedrawn = function()
			entry.lanesStale = true
			schedule(entry)
		end,
	}, entry.near)
	local planInput: Scatter.PlanInput = {
		plotIndex = entry.index,
		eraName = eraName,
		plotSize = base.Size,
		layout = layout,
		config = config,
		era = era,
		roadWidth = roads.width,
		centrelines = RoadGraph.AllCentrelines(roads),
		junctionSlotIds = RoadGraph.JunctionSlotIds(roads),
		streetLines = function(): RoadGraph.StreetLines
			return RoadGraph.StreetLines(roads)
		end,
		entrance = RoadGraph.EntrancePoint(roads),
	}
	local plan = Scatter.Plan(planInput)
	-- Before the first Flush lays anything: the park strips leave the kiosks' ground alone, and the
	-- planner is the only reader of a prop's harvested extents.
	RoadGraph.SetTileKeepOut(roads, Scatter.KioskRects(planInput))
	local signals = era.signals
	-- Wave 2a: the ring needs both the era's config and the layout's geometry; either missing is a
	-- plot without a highway, silently.
	local highwayConfig = era.highway
	local highwayLayout = layout.highway
	local highway: Highway.Handle? = nil
	if highwayConfig ~= nil and highwayLayout ~= nil then
		local tiles = era.road.tiles
		local pavementWidth = if tiles ~= nil and tiles.pavement ~= nil
			then tiles.pavement.width
			else 0
		local centrelines = planInput.centrelines
		local highwaySolids: { Scatter.Footprint }? = nil
		highway = Highway.Create({
			folder = entry.folder,
			plotFrame = plotFrame,
			eraName = eraName,
			config = highwayConfig,
			layout = highwayLayout,
			tileStuds = if tiles ~= nil then tiles.tileStuds else roads.width,
			roadWidth = roads.width,
			pavementWidth = pavementWidth,
			laneOffset = roads.laneOffset,
			entrance = planInput.entrance,
			budgetCells = RoadGraph.BudgetValue(
				config.budget.highwayCells,
				RoadGraph.BudgetValue(config.budget.roadPieces, 0)
			),
			near = entry.near,
			-- The sign asks the planner the same question the trees do, and stays a road width and
			-- kerb clear of every centreline the plot can ever draw, so it can never stand inside a
			-- building, on a pad or over the asphalt. The solids are gathered lazily: only a plot
			-- that owns the ramp and has a sign prop ever asks.
			clearOf = function(position: Vector3, halfExtent: number): boolean
				local solids = highwaySolids
				if solids == nil then
					solids = Scatter.Solids(planInput)
					highwaySolids = solids
				end
				if not Scatter.Clear(solids :: { Scatter.Footprint }, position, halfExtent) then
					return false
				end
				local keepOff = roads.width / 2 + pavementWidth + halfExtent
				for _, line in centrelines do
					for index = 2, #line do
						local closest =
							RoadGraph.ClosestOnSegment(position, line[index - 1], line[index])
						if (closest - position).Magnitude < keepOff then
							return false
						end
					end
				end
				return true
			end,
			onReady = function()
				schedule(entry)
			end,
		})
	end
	return {
		eraName = eraName,
		era = era,
		layout = layout,
		plotFrame = plotFrame,
		roads = roads,
		plan = plan,
		planInput = planInput,
		houses = {},
		plazas = {},
		trees = {},
		parkTrees = {},
		lamps = {},
		signalSpots = if signals ~= nil and signals.prop ~= nil
			then RoadGraph.SignalSpots(roads, signals.offset, signals.maxPerPlot)
			else {},
		signals = {},
		highway = highway,
		subways = {},
		greenery = {},
		parked = {},
		smoke = {},
		createdAt = os.clock(),
	}
end

local function syncFiller(build: Build, tier: number, folder: Instance): ()
	local layout = build.layout
	local lots: { Types.LotLayout } = layout.lots or {}
	local plazas: { Types.PlazaLayout } = layout.plazas or {}
	for index, lot in lots do
		local propName = build.plan.lotProps[index]
		local house: Model? = build.houses[index]
		if house == nil and propName ~= nil and lot.tier <= tier then
			local model = PropFactory.Spawn(
				build.eraName,
				propName,
				0,
				build.plotFrame * Scatter.PropFrame(lot.position, lot.rotationY),
				folder
			)
			if model ~= nil then
				build.houses[index] = model
			end
		end
	end
	for index, plaza in plazas do
		local placed: Model? = build.plazas[index]
		if placed == nil and build.plan.plazaAllowed[index] and plaza.tier <= tier then
			local model = PropFactory.Spawn(
				build.eraName,
				plaza.prop,
				0,
				build.plotFrame * Scatter.PropFrame(plaza.position, plaza.rotationY),
				folder
			)
			if model ~= nil then
				build.plazas[index] = model
			end
		end
	end
end

-- Whether a paved block is down: any of its buildings owned, the rule TileRenderer lays it by.
local function blockPaved(build: Build, index: number, owned: { [string]: boolean }): boolean
	local blocks: { Types.BlockLayout } = build.layout.blocks or {}
	local block = blocks[index]
	if block == nil then
		return false
	end
	for _, slotId in block.slots do
		if owned[slotId] then
			return true
		end
	end
	return false
end

-- The plan indices a capped policy keeps, thinned evenly over the plan's order (the row-lamp rule)
-- so every zone, block and street keeps its share. Nil when the cap keeps them all.
local function keptIndices(total: number, cap: number?): { [number]: boolean }?
	if cap == nil or total <= cap then
		return nil
	end
	local kept: { [number]: boolean } = {}
	for index = 1, total do
		if (index * cap) // total ~= ((index - 1) * cap) // total then
			kept[index] = true
		end
	end
	return kept
end

local function syncTrees(
	build: Build,
	config: Types.CityDressingConfig,
	tier: number,
	folder: Instance,
	owned: { [string]: boolean },
	policy: DetailPolicy
): ()
	local propName = build.era.trees.prop
	local kept = keptIndices(#build.plan.trees, policy.treeCap)
	for index, spot in build.plan.trees do
		if kept ~= nil and not kept[index] then
			local existing = build.trees[index]
			if existing ~= nil then
				existing.model:Destroy()
				build.trees[index] = nil
			end
			continue
		end
		local wanted = Scatter.TreeStage(spot, tier, config.trees.stages)
		if wanted == nil then
			continue
		end
		-- A street tree waits for both halves of its street: the spine piece it stands beside (a
		-- neighbour's spur can draw that first) and the paving of its own block. A zone tree carries
		-- neither and only waits for its birth tier.
		local pieceId = spot.pieceId
		local blockIndex = spot.blockIndex
		if pieceId ~= nil and not RoadGraph.PieceVisible(build.roads, pieceId) then
			continue
		end
		if blockIndex ~= nil and not blockPaved(build, blockIndex, owned) then
			continue
		end
		local stage = PropFactory.ChosenStage(build.eraName, propName, wanted)
		local existing = build.trees[index]
		if stage == nil or (existing ~= nil and existing.stage == stage) then
			continue
		end
		local model = PropFactory.Spawn(
			build.eraName,
			propName,
			wanted,
			build.plotFrame * CFrame.new(spot.position) * CFrame.Angles(0, spot.yaw, 0),
			folder
		)
		if model ~= nil then
			if existing ~= nil then
				existing.model:Destroy()
			end
			build.trees[index] = { model = model, stage = stage }
		end
	end
end

-- Park-strip planters (wave 2a): a tree stands while the strip under it is down and goes in the
-- same sync the tiles land on that cell, so the dust burst covers the swap. Near plots only --
-- a far plot draws the strip slabs alone.
local function syncParkTrees(build: Build, folder: Instance, policy: DetailPolicy): ()
	local tiles = build.era.road.tiles
	local parkStrips = if tiles ~= nil then tiles.parkStrips else nil
	if parkStrips == nil then
		return
	end
	-- A config too old (or too new) to carry a sane stage plants the youngest one rather than
	-- erroring on a NaN, like every other budget read.
	local stage = math.max(math.floor(RoadGraph.BudgetValue(parkStrips.treeStage, 0)), 0)
	local kept = keptIndices(#build.plan.parkTrees, policy.parkTreeCap)
	for index, spot in build.plan.parkTrees do
		local placed: Model? = build.parkTrees[index]
		local wanted = (kept == nil or kept[index] == true)
			and RoadGraph.ParkStripAt(build.roads, spot.position)
		if wanted == (placed ~= nil) then
			continue
		end
		if placed ~= nil then
			placed:Destroy()
			build.parkTrees[index] = nil
			continue
		end
		local model = PropFactory.Spawn(
			build.eraName,
			build.era.trees.prop,
			stage,
			build.plotFrame * CFrame.new(spot.position) * CFrame.Angles(0, spot.yaw, 0),
			folder
		)
		if model ~= nil then
			build.parkTrees[index] = model
		end
	end
end

-- Lamp posts down both sides of the drawn streets (wave 1e). The plan is fixed and capped; a post
-- appears as soon as the piece it stands on is drawn, and never moves again.
local function syncLampRow(build: Build, folder: Instance): ()
	for _, post in build.plan.lampPosts do
		local lamp: Model? = build.lamps[post.key]
		if lamp ~= nil or not RoadGraph.PieceVisible(build.roads, post.pieceId) then
			continue
		end
		local model = PropFactory.Spawn(
			build.eraName,
			build.era.lamps.prop,
			0,
			build.plotFrame * CFrame.new(post.position) * CFrame.Angles(0, post.yaw, 0),
			folder
		)
		if model ~= nil then
			build.lamps[post.key] = model
		end
	end
end

local function syncLamps(
	build: Build,
	config: Types.CityDressingConfig,
	tier: number,
	folder: Instance,
	owned: { [string]: boolean }
): ()
	-- Wave 1e: an era that names a street slot is lit by owning it, not by reaching a tier.
	local requiresSlot = build.era.lamps.requiresSlot
	if requiresSlot ~= nil then
		if not owned[requiresSlot] then
			clearLamps(build)
			return
		end
	elseif tier < config.lamps.firstTier then
		return
	end
	if build.era.lamps.placement == Scatter.ROW_PLACEMENT then
		syncLampRow(build, folder)
		return
	end
	-- Sorted so the attempt order never depends on dictionary iteration.
	local slotIds: { string } = {}
	for slotId in build.plan.lampSlots do
		table.insert(slotIds, slotId)
	end
	table.sort(slotIds)
	for _, slotId in slotIds do
		local lamp: Model? = build.lamps[slotId]
		if lamp ~= nil then
			continue
		end
		local junction = RoadGraph.GetJunction(build.roads, slotId)
		-- A lamp needs the spine it lights: a spur to an unreachable join point has none.
		if junction == nil or not RoadGraph.JoinVisible(build.roads, slotId) then
			continue
		end
		local model = PropFactory.Spawn(
			build.eraName,
			build.era.lamps.prop,
			0,
			build.plotFrame * Scatter.LampFrame(junction, build.roads.width),
			folder
		)
		if model ~= nil then
			build.lamps[slotId] = model
		end
	end
end

-- Crossing signals (wave 1e): one prop per planned corner, while the slot that installs them is
-- owned and the crossing itself is drawn. Absent config, a nil prop or a missing template is a
-- plot with no signals and no error, like every other dressing feature.
local function syncSignals(build: Build, folder: Instance, owned: { [string]: boolean }): ()
	local signals = build.era.signals
	if signals == nil or signals.prop == nil then
		return
	end
	local requiresSlot = signals.requiresSlot
	if requiresSlot ~= nil and not owned[requiresSlot] then
		clearSignals(build)
		return
	end
	for _, spot in build.signalSpots do
		local placed: Model? = build.signals[spot.node]
		if placed ~= nil or RoadGraph.VisibleAt(build.roads, spot.node) < SIGNAL_MIN_VISIBLE then
			continue
		end
		local model = PropFactory.Spawn(
			build.eraName,
			signals.prop,
			0,
			build.plotFrame * CFrame.new(spot.position) * CFrame.Angles(0, spot.yaw, 0),
			folder
		)
		if model ~= nil then
			build.signals[spot.node] = model
		end
	end
end

-- Subway entrances (wave 2a): while the slot is owned, each planned spot appears with the street
-- it was tied to; the one nearest the plot entrance never waits. Near plots only, like lamps.
local function syncSubway(build: Build, folder: Instance, owned: { [string]: boolean }): ()
	local subway = build.era.subway
	if subway == nil then
		return
	end
	if not owned[subway.requiresSlot] then
		clearSubways(build)
		return
	end
	for index, spot in build.plan.subwayEntrances do
		local placed: Model? = build.subways[index]
		if placed ~= nil then
			continue
		end
		local pieceId = spot.pieceId
		local due = spot.exempt or (pieceId ~= nil and RoadGraph.PieceVisible(build.roads, pieceId))
		if not due then
			continue
		end
		local model = PropFactory.Spawn(
			build.eraName,
			subway.prop,
			0,
			build.plotFrame * Scatter.PropFrame(spot.position, spot.rotationY),
			folder
		)
		if model ~= nil then
			build.subways[index] = model
		end
	end
end

-- The elevated ring (wave 2a) follows its slot: bought on a near plot it builds outward from the
-- ramp, and a sale it never sees (an era rebuild clears the whole plot) takes it down.
local function syncHighway(build: Build, owned: { [string]: boolean }, animate: boolean): ()
	local handle = build.highway
	local config = build.era.highway
	if handle == nil or config == nil then
		return
	end
	Highway.SetOwned(handle, owned[config.requiresSlot] == true, animate)
end

local function localPlotIndex(): number?
	local value = player:GetAttribute(PLOT_INDEX_ATTRIBUTE)
	return if typeof(value) == "number" then value else nil
end

-- Whether the policy lets this plot run vehicles at all (street and deck alike).
local function vehiclesAllowed(entry: PlotEntry, policy: DetailPolicy): boolean
	return not policy.vehiclesLocalOnly or entry.index == localPlotIndex()
end

local function highwayTargetFor(
	entry: PlotEntry,
	build: Build,
	config: Types.CityDressingConfig,
	policy: DetailPolicy
): number
	local handle = build.highway
	local era = build.era.highway
	if
		handle == nil
		or era == nil
		or not entry.near
		or not entry.vehicleSelected
		or not vehiclesAllowed(entry, policy)
	then
		return 0
	end
	-- Lanes are nil until the ring is closed and its deck has been measured, so a deck template
	-- that has not replicated yet simply means "not this sync" rather than cars stuck at 0 studs.
	if Highway.Lanes(handle) == nil then
		return 0
	end
	local vehicles = era.vehicles
	if type(vehicles) ~= "table" then
		return 0
	end
	local wanted = math.floor(RoadGraph.BudgetValue(vehicles.count, 0))
	return math.clamp(wanted, 0, math.max(config.budget.vehiclesPerPlot, 0))
end

local function vehicleTargetFor(
	entry: PlotEntry,
	build: Build,
	config: Types.CityDressingConfig,
	policy: DetailPolicy
): number
	local tierCount = #config.tier.thresholds
	if
		not entry.near
		or not entry.vehicleSelected
		or not vehiclesAllowed(entry, policy)
		or tierCount <= 0
		or entry.tier < config.vehicles.firstTier
	then
		return 0
	end
	local wanted = math.ceil(build.era.vehicles.perPlot * entry.tier / tierCount)
	-- The deck's cars are part of the plot's share, so the streets take what is left of it. What is
	-- actually on the deck, not what was asked for: cars the map budget refused must not go on
	-- reserving street slots that nothing is using.
	local room =
		math.max(config.budget.vehiclesPerPlot - Traffic.Count(highwayPlotId(entry.index)), 0)
	return math.clamp(wanted, 0, math.min(#build.plan.vehicleProps, room))
end

local function spawnVehicles(entry: PlotEntry, build: Build, config: Types.CityDressingConfig): ()
	Traffic.ClearPlot(entry.index)
	entry.vehiclesBlocked = false
	if entry.vehicleTarget <= 0 then
		return
	end
	local lanes = RoadGraph.GetLanes(build.roads)
	if lanes.count == 0 then
		return
	end
	local models: { Model } = {}
	-- Scaled about the base before Traffic reads the part offsets, so the smaller car rides the
	-- road surface with no height correction of its own.
	local scale = PropFactory.ScaleOf(build.era.vehicles.scale)
	for index = 1, entry.vehicleTarget do
		local model = PropFactory.Spawn(
			build.eraName,
			build.plan.vehicleProps[index],
			0,
			CFrame.identity,
			nil,
			scale
		)
		if model ~= nil then
			table.insert(models, model)
		end
	end
	if #models == 0 then
		return
	end
	-- Only a full map budget is worth retrying; a street too short for more cars stays as it is.
	local _, budgetLimited = Traffic.SpawnPlot(
		entry.index,
		lanes,
		models,
		build.era.vehicles.speed,
		config.vehicles.turnSeconds,
		build.era.vehicles.followGap,
		entry.folder,
		config.budget.vehiclesMap
	)
	entry.vehiclesBlocked = budgetLimited
end

-- The ring's cars ride the same Traffic loop on their own lane graph, so they never take the ramp
-- and cost nothing beyond the models themselves.
local function spawnHighwayVehicles(
	entry: PlotEntry,
	build: Build,
	config: Types.CityDressingConfig
): ()
	local plotId = highwayPlotId(entry.index)
	Traffic.ClearPlot(plotId)
	entry.highwayBlocked = false
	local handle = build.highway
	local era = build.era.highway
	if handle == nil or era == nil or entry.highwayTarget <= 0 then
		return
	end
	local lanes = Highway.Lanes(handle)
	if lanes == nil or lanes.count == 0 then
		return
	end
	-- Wave 2b: an era can run its own props on the deck (the monorail train); without the key the
	-- ring takes the street's seeded picks, as the Metropolis cars always have.
	local props = era.vehicleProps or build.plan.vehicleProps
	if #props == 0 then
		return
	end
	local models: { Model } = {}
	-- Wave 2d: the deck runs at the street cars' scale, whichever props it carries.
	local scale = PropFactory.ScaleOf(build.era.vehicles.scale)
	for index = 1, entry.highwayTarget do
		local model = PropFactory.Spawn(
			build.eraName,
			props[(index - 1) % #props + 1],
			0,
			CFrame.identity,
			nil,
			scale
		)
		if model ~= nil then
			table.insert(models, model)
		end
	end
	if #models == 0 then
		return
	end
	local _, budgetLimited = Traffic.SpawnPlot(
		plotId,
		lanes,
		models,
		era.vehicles.speed,
		config.vehicles.turnSeconds,
		build.era.vehicles.followGap,
		entry.folder,
		config.budget.vehiclesMap
	)
	entry.highwayBlocked = budgetLimited
end

-- Wave 2c greenery: a zone piece appears on its tier, a garnish piece with its lot's house.
local function syncGreenery(build: Build, tier: number, folder: Instance, policy: DetailPolicy): ()
	local share = policy.greeneryShare
	for index, spot in build.plan.greenery do
		local placed: Model? = build.greenery[index]
		-- Even thinning by plan index, so detail back on restores exactly the pieces it hid.
		local kept = share >= 1 or math.floor(index * share) > math.floor((index - 1) * share)
		if not kept then
			if placed ~= nil then
				placed:Destroy()
				build.greenery[index] = nil
			end
			continue
		end
		if placed ~= nil then
			continue
		end
		local lot = spot.lot
		local spotTier = spot.tier
		local house: Model? = if lot ~= nil then build.houses[lot] else nil
		local due = if lot ~= nil then house ~= nil else spotTier ~= nil and spotTier <= tier
		if not due then
			continue
		end
		local model = PropFactory.Spawn(
			build.eraName,
			spot.prop,
			0,
			build.plotFrame * CFrame.new(spot.position) * CFrame.Angles(0, spot.yaw, 0),
			folder
		)
		if model ~= nil then
			build.greenery[index] = model
		end
	end
end

-- Wave 2c parked vehicles: on their tier, with their lot's house when they have one, and only
-- once the street beside them is drawn -- a car parked beside bare ground reads as a mistake.
local function syncParked(build: Build, tier: number, folder: Instance): ()
	local parked = build.era.parked
	local scale = PropFactory.ScaleOf(if parked ~= nil then parked.scale else nil)
	for index, spot in build.plan.parked do
		local placed: Model? = build.parked[index]
		if placed ~= nil or spot.tier > tier then
			continue
		end
		local lot = spot.lot
		local pieceId = spot.pieceId
		local house: Model? = if lot ~= nil then build.houses[lot] else nil
		if lot ~= nil and house == nil then
			continue
		end
		if pieceId == nil or not RoadGraph.PieceVisible(build.roads, pieceId) then
			continue
		end
		local model = PropFactory.Spawn(
			build.eraName,
			spot.prop,
			0,
			build.plotFrame * Scatter.PropFrame(spot.position, spot.rotationY),
			folder,
			scale
		)
		if model ~= nil then
			build.parked[index] = model
		end
	end
end

-- Whether `list` names `value`: the smoke config's era filter.
local function listHas(list: { string }?, value: string): boolean
	if type(list) ~= "table" then
		return false
	end
	for _, item in list do
		if item == value then
			return true
		end
	end
	return false
end

-- Wave 2c chimney smoke: one plume on each placed house whose prop has a chimney offset, from the
-- smoke tier, in the eras the config names, and never on a low-end device (Ambient.Enabled).
local function syncSmoke(build: Build, config: Types.CityDressingConfig, tier: number): ()
	local ambient = config.ambient
	local smoke = if ambient ~= nil then ambient.smoke else nil
	if
		smoke == nil
		or not Ambient.Enabled()
		or not listHas(smoke.eras, build.eraName)
		-- A missing tier key is "never", like every other wave 2c key: the feature is simply off.
		or tier < RoadGraph.BudgetValue(smoke.firstTier, math.huge)
		or type(smoke.props) ~= "table"
	then
		clearSmoke(build)
		return
	end
	local lots: { Types.LotLayout } = build.layout.lots or {}
	for index, house in build.houses do
		local plume: Attachment? = build.smoke[index]
		if plume ~= nil then
			continue
		end
		local lot = lots[index]
		local propName = build.plan.lotProps[index]
		-- Keyed "Era/Prop" first: Village and Boomtown both have a HouseA with different chimneys.
		local offset = if propName ~= nil
			then smoke.props[build.eraName .. "/" .. propName] or smoke.props[propName]
			else nil
		if lot == nil or type(offset) ~= "table" then
			continue
		end
		local x, y, z = offset[1], offset[2], offset[3]
		if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
			continue
		end
		local chimney = build.plotFrame
			* Scatter.PropFrame(lot.position, lot.rotationY)
			* CFrame.new(x, y, z)
		local added = Ambient.AddSmoke(house, chimney, smoke)
		if added ~= nil then
			build.smoke[index] = added
		end
	end
end

-- The street furniture walkers keep clear of: every planned row lamp and crossing signal, and the
-- junction lamp of every drawn spur -- planned, not placed, so the lanes do not change as the
-- props pop in.
local function walkFurniture(build: Build): { { frame: CFrame, prop: string? } }
	local furniture: { { frame: CFrame, prop: string? } } = {}
	local lamps = build.era.lamps
	if lamps.prop ~= nil then
		if lamps.placement == Scatter.ROW_PLACEMENT then
			for _, post in build.plan.lampPosts do
				table.insert(furniture, {
					frame = CFrame.new(post.position) * CFrame.Angles(0, post.yaw, 0),
					prop = lamps.prop,
				})
			end
		else
			for slotId in build.plan.lampSlots do
				local junction = RoadGraph.GetJunction(build.roads, slotId)
				if junction ~= nil then
					table.insert(furniture, {
						frame = Scatter.LampFrame(junction, build.roads.width),
						prop = lamps.prop,
					})
				end
			end
		end
	end
	local signals = build.era.signals
	if signals ~= nil and signals.prop ~= nil then
		for _, spot in build.signalSpots do
			table.insert(furniture, {
				frame = CFrame.new(spot.position) * CFrame.Angles(0, spot.yaw, 0),
				prop = signals.prop,
			})
		end
	end
	return furniture
end

-- The plot's walker lanes, clipped clear of every solid (RoadGraph.WalkLanes caches them).
local function walkLanesFor(build: Build, pedestrians: Types.PedestrianConfig): RoadGraph.Lanes
	return RoadGraph.WalkLanes(
		build.roads,
		pedestrians.offset,
		RoadGraph.BudgetValue(pedestrians.clearance, DEFAULT_WALK_CLEARANCE),
		function(): { RoadGraph.WalkSolid }
			return Scatter.WalkSolids(build.planInput, walkFurniture(build))
		end
	)
end

-- Walkers stroll the same nearest plots the cars drive on, from the era's first walker tier.
local function walkerTargetFor(entry: PlotEntry, build: Build, policy: DetailPolicy): number
	local pedestrians = build.era.pedestrians
	if
		pedestrians == nil
		or not policy.living
		or not entry.near
		or not entry.vehicleSelected
		or entry.tier < RoadGraph.BudgetValue(pedestrians.firstTier, math.huge)
	then
		return 0
	end
	return math.min(Scatter.PerTier(pedestrians.perTier, entry.tier), #build.plan.walkerProps)
end

local function spawnWalkers(entry: PlotEntry, build: Build, config: Types.CityDressingConfig): ()
	Walkers.ClearPlot(entry.index)
	entry.walkersBlocked = false
	local pedestrians = build.era.pedestrians
	if pedestrians == nil or entry.walkerTarget <= 0 then
		return
	end
	local lanes = walkLanesFor(build, pedestrians)
	if lanes.count == 0 then
		return
	end
	local models: { Model } = {}
	local scale = PropFactory.ScaleOf(pedestrians.scale)
	for index = 1, entry.walkerTarget do
		local model = PropFactory.Spawn(
			build.eraName,
			build.plan.walkerProps[index],
			0,
			CFrame.identity,
			nil,
			scale
		)
		if model ~= nil then
			table.insert(models, model)
		end
	end
	if #models == 0 then
		return
	end
	local offered = #models
	local placed = Walkers.SpawnPlot(
		entry.index,
		lanes,
		models,
		pedestrians.speed,
		pedestrians.bobHeight,
		pedestrians.bobHz,
		entry.folder,
		RoadGraph.BudgetValue(config.budget.walkersMap, 0)
	)
	entry.walkersBlocked = placed < offered
end

local function birdsConfig(config: Types.CityDressingConfig): Types.BirdsConfig?
	local ambient = config.ambient
	return if ambient ~= nil then ambient.birds else nil
end

-- Birds circle over the groves of near plots only, in the eras the config names, from the flock
-- tier, never on a low-end device (Ambient.Enabled).
local function flockTargetFor(
	entry: PlotEntry,
	build: Build,
	config: Types.CityDressingConfig,
	policy: DetailPolicy
): number
	local birds = birdsConfig(config)
	if
		birds == nil
		or not policy.living
		or not entry.near
		or not Ambient.Enabled()
		or not listHas(birds.eras, build.eraName)
		or entry.tier < RoadGraph.BudgetValue(birds.firstTier, math.huge)
	then
		return 0
	end
	return math.min(Scatter.PerTier(birds.flocksPerTier, entry.tier), #build.plan.flocks)
end

local function spawnFlocks(entry: PlotEntry, build: Build, config: Types.CityDressingConfig): ()
	Ambient.ClearPlot(entry.index)
	entry.birdsBlocked = false
	local birds = birdsConfig(config)
	if birds == nil or entry.flockTarget <= 0 then
		return
	end
	local flocks = table.move(build.plan.flocks, 1, entry.flockTarget, 1, {})
	local models: { Model } = {}
	for _, flock in flocks do
		for _ = 1, #flock.birds do
			local model = PropFactory.Spawn(build.eraName, birds.prop, 0, CFrame.identity, nil)
			if model == nil then
				-- No Bird template for this era: no flocks, silently.
				for _, spawned in models do
					spawned:Destroy()
				end
				return
			end
			table.insert(models, model)
		end
	end
	if #models == 0 then
		return
	end
	local placed = Ambient.SpawnFlocks(
		entry.index,
		build.plotFrame,
		flocks,
		birds,
		models,
		entry.folder,
		RoadGraph.BudgetValue(config.budget.birdsMap, 0)
	)
	entry.birdsBlocked = placed < #models
end

local function sync(entry: PlotEntry): ()
	local config = dressingConfig()
	if config == nil or entries[entry.plot] ~= entry then
		return
	end
	local plot = entry.plot
	local base = baseOf(plot)
	local eraName = plot:GetAttribute(ERA_NAME_ATTRIBUTE)
	local tier = tierOf(plot, config)
	if base == nil or typeof(eraName) ~= "string" then
		clearBuild(entry)
		entry.tier = tier
		return
	end

	-- The owned set is read once per layout per sync: the rebuild check, the spur loop, the
	-- surface variant and the street-upgrade gates all ask for the same thing.
	local ownedList: { string } = {}
	local owned: { [string]: boolean } = {}
	local ownedLayout: Types.EraLayout? = nil
	local function readOwned(layout: Types.EraLayout): ()
		if ownedLayout == layout then
			return
		end
		ownedList, owned = ownedSlotIds(plot, layout)
		ownedLayout = layout
	end

	local build = entry.build
	if build ~= nil then
		local rebuild = build.eraName ~= eraName or tier < entry.tier
		if not rebuild then
			readOwned(build.layout)
			local missing = false
			for _, slotId in RoadGraph.DrawnSlotIds(build.roads) do
				if not owned[slotId] then
					missing = true
					break
				end
			end
			if not missing then
				entry.suspectSince = nil
			elseif entry.confirmSuspect then
				rebuild = true
			elseif entry.suspectSince == nil then
				entry.suspectSince = os.clock()
			end
		end
		entry.confirmSuspect = false
		if rebuild then
			clearBuild(entry)
			build = nil
		end
	end
	entry.tier = tier
	if build == nil then
		build = newBuild(entry, config, eraName, base)
		entry.build = build
		if build == nil then
			return
		end
	end
	local current = build :: Build
	local folder = entry.folder

	-- Roads grow with buildings, not tiers; near/far only swaps meandered and straight Parts.
	RoadGraph.SetNear(current.roads, entry.near)
	local highway = current.highway
	if highway ~= nil then
		Highway.SetNear(highway, entry.near)
	end
	local roadsChanged = entry.lanesStale
	entry.lanesStale = false
	-- Buildings replicate over several frames after a join or rebuild; only a building that
	-- appears once the build has settled for one LOD interval is a purchase worth animating.
	local animate = entry.near and os.clock() - current.createdAt >= config.lod.refreshSeconds
	readOwned(current.layout)
	for _, slotId in ownedList do
		if RoadGraph.AddSpur(current.roads, slotId, animate) then
			roadsChanged = true
		end
	end
	-- Before the flush that clones them: a piece must never appear in the surface it is about to
	-- be repainted out of.
	RoadGraph.SetSurface(current.roads, owned, animate)
	-- Paved blocks follow the same owned set; the slab goes down before the trees on it.
	RoadGraph.SetBlocks(current.roads, owned, animate)
	-- One renderer update for every spur revealed above.
	RoadGraph.Flush(current.roads)
	RoadGraph.RefreshPieces(current.roads)
	syncFiller(current, tier, folder)
	syncHighway(current, owned, animate)

	local policy = detailPolicy(current.era, config)
	if entry.near then
		syncTrees(current, config, tier, folder, owned, policy)
		syncParkTrees(current, folder, policy)
		if policy.lamps then
			syncLamps(current, config, tier, folder, owned)
		else
			clearLamps(current)
		end
		syncSignals(current, folder, owned)
		syncSubway(current, folder, owned)
		syncGreenery(current, tier, folder, policy)
		if policy.living then
			syncParked(current, tier, folder)
			syncSmoke(current, config, tier)
		else
			clearParked(current)
			clearSmoke(current)
		end
	else
		clearTrees(current)
		clearParkTrees(current)
		clearLamps(current)
		clearSignals(current)
		clearSubways(current)
		clearGreenery(current)
		clearParked(current)
		clearSmoke(current)
	end

	local deckTarget = highwayTargetFor(entry, current, config, policy)
	if deckTarget ~= entry.highwayTarget then
		entry.highwayTarget = deckTarget
		spawnHighwayVehicles(entry, current, config)
	elseif
		deckTarget > 0
		and entry.highwayBlocked
		and Traffic.Room(config.budget.vehiclesMap) > 0
	then
		-- Room freed elsewhere since the map budget cut the deck short.
		spawnHighwayVehicles(entry, current, config)
	end
	local target = vehicleTargetFor(entry, current, config, policy)
	if target ~= entry.vehicleTarget then
		entry.vehicleTarget = target
		spawnVehicles(entry, current, config)
	elseif target > 0 and entry.vehiclesBlocked and Traffic.Room(config.budget.vehiclesMap) > 0 then
		-- Room freed elsewhere since the map budget cut this plot short.
		spawnVehicles(entry, current, config)
	elseif roadsChanged and target > 0 then
		-- A plot whose streets were too short for all its cars (Traffic keeps them a car length
		-- apart) respawns when they grow instead of carrying the short count forward.
		local driving = Traffic.Count(entry.index)
		if driving > 0 and driving >= target then
			Traffic.SetLanes(entry.index, RoadGraph.GetLanes(current.roads))
		else
			spawnVehicles(entry, current, config)
		end
	end

	local walkerTarget = walkerTargetFor(entry, current, policy)
	local walkersMap = RoadGraph.BudgetValue(config.budget.walkersMap, 0)
	local pedestrians = current.era.pedestrians
	if walkerTarget ~= entry.walkerTarget then
		entry.walkerTarget = walkerTarget
		spawnWalkers(entry, current, config)
	elseif walkerTarget > 0 and entry.walkersBlocked and Walkers.Room(walkersMap) > 0 then
		spawnWalkers(entry, current, config)
	elseif roadsChanged and walkerTarget > 0 and pedestrians ~= nil then
		if Walkers.Count(entry.index) > 0 then
			Walkers.SetLanes(entry.index, walkLanesFor(current, pedestrians))
		else
			spawnWalkers(entry, current, config)
		end
	end

	local flockTarget = flockTargetFor(entry, current, config, policy)
	local birdsMap = RoadGraph.BudgetValue(config.budget.birdsMap, 0)
	if flockTarget ~= entry.flockTarget then
		entry.flockTarget = flockTarget
		spawnFlocks(entry, current, config)
	elseif flockTarget > 0 and entry.birdsBlocked and Ambient.Room(birdsMap) > 0 then
		spawnFlocks(entry, current, config)
	end
end

schedule = function(entry: PlotEntry): ()
	if entry.scheduled or not started then
		return
	end
	entry.scheduled = true
	task.defer(function()
		entry.scheduled = false
		sync(entry)
	end)
end

local function removePlot(plot: Instance): ()
	local entry = entries[plot]
	if entry == nil then
		return
	end
	entries[plot] = nil
	for _, connection in entry.connections do
		connection:Disconnect()
	end
	clearBuild(entry)
	entry.folder:Destroy()
end

local function watchBuildings(entry: PlotEntry, buildings: Instance): ()
	local function onChanged(child: Instance): ()
		if string.match(child.Name, BUILDING_NAME_PATTERN) ~= nil then
			schedule(entry)
		end
	end
	table.insert(entry.connections, buildings.ChildAdded:Connect(onChanged))
	table.insert(entry.connections, buildings.ChildRemoved:Connect(onChanged))
end

local function addPlot(plot: Instance): ()
	local digits = string.match(plot.Name, PLOT_NAME_PATTERN)
	local index = if digits ~= nil then tonumber(digits) else nil
	local root = rootFolder
	if index == nil or root == nil or entries[plot] ~= nil then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = Theme.CITY_PLOT_FOLDER_PREFIX .. tostring(index)
	folder.Parent = root
	local entry: PlotEntry = {
		index = index,
		plot = plot,
		folder = folder,
		connections = {},
		tier = 0,
		near = false,
		vehicleSelected = false,
		vehicleTarget = 0,
		highwayTarget = 0,
		highwayBlocked = false,
		vehiclesBlocked = false,
		walkerTarget = 0,
		walkersBlocked = false,
		flockTarget = 0,
		birdsBlocked = false,
		suspectSince = nil,
		confirmSuspect = false,
		lanesStale = false,
		scheduled = false,
		build = nil,
	}
	entries[plot] = entry

	local function reschedule(): ()
		schedule(entry)
	end
	table.insert(
		entry.connections,
		plot:GetAttributeChangedSignal(ERA_NAME_ATTRIBUTE):Connect(reschedule)
	)
	table.insert(
		entry.connections,
		plot:GetAttributeChangedSignal(GROWTH_TIER_ATTRIBUTE):Connect(reschedule)
	)
	local buildings = plot:FindFirstChild(BUILDINGS_FOLDER)
	if buildings ~= nil then
		watchBuildings(entry, buildings)
	end
	-- Base or Buildings replicating after the folder (streaming) dress the plot when they land.
	table.insert(
		entry.connections,
		plot.ChildAdded:Connect(function(child: Instance)
			if child.Name == BUILDINGS_FOLDER and buildings == nil then
				buildings = child
				watchBuildings(entry, child)
			end
			if child.Name == BUILDINGS_FOLDER or child.Name == BASE_NAME then
				schedule(entry)
			end
		end)
	)
	table.insert(
		entry.connections,
		plot.AncestryChanged:Connect(function()
			if not plot:IsDescendantOf(Workspace) then
				removePlot(plot)
			end
		end)
	)
	schedule(entry)
end

type Ranked = { entry: PlotEntry, score: number }

-- Near/far with hysteresis, then the lod.vehiclePlots nearest plots (the local plot always
-- first). Selected plots get the same hysteresis as a head start so two equidistant plots do
-- not trade vehicles back and forth.
local function refreshLod(config: Types.CityDressingConfig): ()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local lod = config.lod
	local cameraPosition = camera.CFrame.Position
	local localIndex = localPlotIndex()
	local ranked: { Ranked } = {}
	for _, entry in entries do
		local base = baseOf(entry.plot)
		if base == nil then
			continue
		end
		local distance = (base.Position - cameraPosition).Magnitude
		local near = entry.near
		if distance < lod.nearRadius then
			near = true
		elseif distance > lod.nearRadius + lod.hysteresis then
			near = false
		end
		if near ~= entry.near then
			entry.near = near
			schedule(entry)
		end
		local score = if entry.index == localIndex
			then -math.huge
			elseif entry.vehicleSelected then distance - lod.hysteresis
			else distance
		table.insert(ranked, { entry = entry, score = score })
	end
	table.sort(ranked, function(a: Ranked, b: Ranked): boolean
		if a.score == b.score then
			return a.entry.index < b.entry.index
		end
		return a.score < b.score
	end)
	for position, item in ranked do
		local selected = position <= lod.vehiclePlots
		if selected ~= item.entry.vehicleSelected then
			item.entry.vehicleSelected = selected
			schedule(item.entry)
		end
	end

	local now = os.clock()
	for _, entry in entries do
		-- Despawn synchronously, before any deferred sync spawns, so the room freed by a plot
		-- leaving the vehicle set is available to the plot entering it in this same tick.
		if entry.vehicleTarget > 0 and (not entry.near or not entry.vehicleSelected) then
			entry.vehicleTarget = 0
			entry.vehiclesBlocked = false
			Traffic.ClearPlot(entry.index)
		end
		if entry.highwayTarget > 0 and (not entry.near or not entry.vehicleSelected) then
			entry.highwayTarget = 0
			entry.highwayBlocked = false
			Traffic.ClearPlot(highwayPlotId(entry.index))
		end
		-- Wave 2c: walkers and birds free their map budget the same way, before any sync spawns.
		if entry.walkerTarget > 0 and (not entry.near or not entry.vehicleSelected) then
			entry.walkerTarget = 0
			entry.walkersBlocked = false
			Walkers.ClearPlot(entry.index)
		end
		if entry.flockTarget > 0 and not entry.near then
			entry.flockTarget = 0
			entry.birdsBlocked = false
			Ambient.ClearPlot(entry.index)
		end
		local suspectSince = entry.suspectSince
		if suspectSince ~= nil and now - suspectSince >= lod.refreshSeconds then
			entry.confirmSuspect = true
			schedule(entry)
		end
	end
	if Traffic.Room(config.budget.vehiclesMap) > 0 then
		for _, entry in entries do
			if entry.vehiclesBlocked or entry.highwayBlocked then
				schedule(entry)
			end
		end
	end
	local walkersRoom = Walkers.Room(RoadGraph.BudgetValue(config.budget.walkersMap, 0)) > 0
	local birdsRoom = Ambient.Room(RoadGraph.BudgetValue(config.budget.birdsMap, 0)) > 0
	if walkersRoom or birdsRoom then
		for _, entry in entries do
			if (walkersRoom and entry.walkersBlocked) or (birdsRoom and entry.birdsBlocked) then
				schedule(entry)
			end
		end
	end
end

local function lodLoop(): ()
	local config = dressingConfig()
	if config == nil then
		return
	end
	refreshLod(config)
	task.delay(math.max(config.lod.refreshSeconds, 0), lodLoop)
end

local function start(): ()
	if started or dressingConfig() == nil then
		return
	end
	started = true
	local root = Instance.new("Folder")
	root.Name = Theme.CITY_DRESSING_FOLDER
	root.Parent = Workspace
	rootFolder = root
	task.spawn(function()
		-- PlotService builds every plot at server boot, so the folder exists by now.
		local plots = Workspace:WaitForChild(PLOTS_FOLDER)
		for _, plot in plots:GetChildren() do
			addPlot(plot)
		end
		plots.ChildAdded:Connect(addPlot)
		-- LOD first so the deferred first syncs already know which plots are near: trees and
		-- vehicles are never spawned only to be removed a moment later.
		lodLoop()
	end)
end

local CityDressingController = {}

function CityDressingController.Init(): ()
	-- Needs replicated remotes and plots; everything happens in Start so Init stays yield-free.
end

-- UIController calls this with every trusted settings table (join snapshot, settings delta, and the
-- local tap ahead of the server's echo). A flip re-syncs every plot: trees are thinned or restored
-- from the unchanged plan, lamps cleared or re-placed, and vehicle targets re-evaluated, while the
-- roads, blocks, highway and filler are left exactly as they are.
function CityDressingController.SetCityDetail(enabled: boolean): ()
	if enabled == cityDetail then
		return
	end
	cityDetail = enabled
	for _, entry in entries do
		schedule(entry)
	end
end

function CityDressingController.Start(): ()
	if dressingConfig() == nil then
		return
	end
	task.spawn(function()
		local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
		local stateChanged = remotesFolder:WaitForChild("StateChanged") :: RemoteEvent
		local connection: RBXScriptConnection? = nil
		connection = stateChanged.OnClientEvent:Connect(function(payload: any)
			if typeof(payload) ~= "table" or payload.kind ~= "snapshot" then
				return
			end
			if connection ~= nil then
				connection:Disconnect()
			end
			if typeof(payload.eraName) == "string" then
				local vip = typeof(payload.state) == "table"
					and typeof(payload.state.passes) == "table"
					and payload.state.passes.VIP == true
				AssetPreloader.PreloadEra(payload.eraName, vip)
			end
		end)
	end)
	-- UIController may consume the join snapshot before this listener exists, so dressing starts
	-- as soon as the server assigns the local plot (the PlotIndex attribute PlotVisualsController
	-- reads). newBuild preloads each plot's own era; the timeout still covers a player whose data
	-- never loads and so never gets a plot.
	if localPlotIndex() ~= nil then
		start()
	else
		local plotConnection: RBXScriptConnection? = nil
		plotConnection = player:GetAttributeChangedSignal(PLOT_INDEX_ATTRIBUTE):Connect(function()
			if localPlotIndex() == nil then
				return
			end
			if plotConnection ~= nil then
				plotConnection:Disconnect()
			end
			start()
		end)
	end
	task.delay(Theme.CITY_SNAPSHOT_WAIT_SECONDS, start)
end

return CityDressingController
