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
local Scatter = require(cityFolder:WaitForChild("Scatter"))
local Traffic = require(cityFolder:WaitForChild("Traffic"))

-- World naming frozen since M1/M9 (docs/INTERFACES.md), shared with PlotVisualsController.
local PLOTS_FOLDER = "Plots"
local PLOT_NAME_PATTERN = "^Plot_(%d+)$"
local BUILDINGS_FOLDER = "Buildings"
local BUILDING_NAME_PATTERN = "^Building_(.+)$"
local BASE_NAME = "Base"
local ERA_NAME_ATTRIBUTE = "EraName"
local GROWTH_TIER_ATTRIBUTE = "GrowthTier"
local PLOT_INDEX_ATTRIBUTE = "PlotIndex"

type TreeInstance = { model: Model, stage: number }

type Build = {
	eraName: string,
	era: Types.CityEraDressingConfig,
	layout: Types.EraLayout,
	plotFrame: CFrame,
	roads: RoadGraph.State,
	plan: Scatter.Plan,
	houses: { [number]: Model },
	plazas: { [number]: Model },
	trees: { [number]: TreeInstance },
	lamps: { [string]: Model },
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
	-- The last spawn placed fewer vehicles than models because the map budget was full.
	vehiclesBlocked: boolean,
	-- os.clock when a drawn spur's building was first seen missing; nil while none is. A server
	-- cosmetics refresh respawns every building in one frame but replication spreads it over
	-- several, so a missing building is only trusted after a full LOD interval.
	suspectSince: number?,
	-- Set by the LOD tick once that interval has passed: the next sync may rebuild.
	confirmSuspect: boolean,
	scheduled: boolean,
	build: Build?,
}

local player = Players.LocalPlayer
local entries: { [Instance]: PlotEntry } = {}
local rootFolder: Folder? = nil
local started = false

-- Silent degradation (M9 principles): a config file too old to carry the part ceilings can't be
-- allocated against, so it counts as no config at all rather than erroring mid-build.
local function dressingConfig(): Types.CityDressingConfig?
	local config = Catalog.GetCityDressingConfig()
	if config == nil or type(config.budget) ~= "table" then
		return nil
	end
	return config
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

local function clearLamps(build: Build): ()
	for _, lamp in build.lamps do
		lamp:Destroy()
	end
	table.clear(build.lamps)
end

local function clearBuild(entry: PlotEntry): ()
	local build = entry.build
	Traffic.ClearPlot(entry.index)
	entry.vehicleTarget = 0
	entry.vehiclesBlocked = false
	entry.suspectSince = nil
	entry.confirmSuspect = false
	if build == nil then
		return
	end
	entry.build = nil
	RoadGraph.Destroy(build.roads)
	clearTrees(build)
	clearLamps(build)
	for _, model in build.houses do
		model:Destroy()
	end
	for _, model in build.plazas do
		model:Destroy()
	end
	entry.folder:ClearAllChildren()
end

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
	}, entry.near)
	local plan = Scatter.Plan({
		plotIndex = entry.index,
		eraName = eraName,
		plotSize = base.Size,
		layout = layout,
		config = config,
		era = era,
		roadWidth = roads.width,
		centrelines = RoadGraph.AllCentrelines(roads),
		junctionSlotIds = RoadGraph.JunctionSlotIds(roads),
	})
	return {
		eraName = eraName,
		era = era,
		layout = layout,
		plotFrame = plotFrame,
		roads = roads,
		plan = plan,
		houses = {},
		plazas = {},
		trees = {},
		lamps = {},
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

local function syncTrees(
	build: Build,
	config: Types.CityDressingConfig,
	tier: number,
	folder: Instance
): ()
	local propName = build.era.trees.prop
	for index, spot in build.plan.trees do
		local wanted = Scatter.TreeStage(spot, tier, config.trees.stages)
		if wanted == nil then
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

local function syncLamps(
	build: Build,
	config: Types.CityDressingConfig,
	tier: number,
	folder: Instance
): ()
	if tier < config.lamps.firstTier then
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

local function vehicleTargetFor(
	entry: PlotEntry,
	build: Build,
	config: Types.CityDressingConfig
): number
	local tierCount = #config.tier.thresholds
	if
		not entry.near
		or not entry.vehicleSelected
		or tierCount <= 0
		or entry.tier < config.vehicles.firstTier
	then
		return 0
	end
	local wanted = math.ceil(build.era.vehicles.perPlot * entry.tier / tierCount)
	return math.clamp(wanted, 0, #build.plan.vehicleProps)
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
	for index = 1, entry.vehicleTarget do
		local model = PropFactory.Spawn(
			build.eraName,
			build.plan.vehicleProps[index],
			0,
			CFrame.identity,
			nil
		)
		if model ~= nil then
			table.insert(models, model)
		end
	end
	if #models == 0 then
		return
	end
	local offered = #models
	local placed = Traffic.SpawnPlot(
		entry.index,
		lanes,
		models,
		build.era.vehicles.speed,
		config.vehicles.turnSeconds,
		entry.folder,
		config.budget.vehiclesMap
	)
	entry.vehiclesBlocked = placed < offered
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

	local build = entry.build
	if build ~= nil then
		local rebuild = build.eraName ~= eraName or tier < entry.tier
		if not rebuild then
			local _, owned = ownedSlotIds(plot, build.layout)
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
	local roadsChanged = false
	for _, slotId in (ownedSlotIds(plot, current.layout)) do
		if RoadGraph.AddSpur(current.roads, slotId) then
			roadsChanged = true
		end
	end
	RoadGraph.RefreshPieces(current.roads)
	syncFiller(current, tier, folder)

	if entry.near then
		syncTrees(current, config, tier, folder)
		syncLamps(current, config, tier, folder)
	else
		clearTrees(current)
		clearLamps(current)
	end

	local target = vehicleTargetFor(entry, current, config)
	if target ~= entry.vehicleTarget then
		entry.vehicleTarget = target
		spawnVehicles(entry, current, config)
	elseif target > 0 and entry.vehiclesBlocked and Traffic.Room(config.budget.vehiclesMap) > 0 then
		-- Room freed elsewhere since the map budget cut this plot short.
		spawnVehicles(entry, current, config)
	elseif roadsChanged and target > 0 then
		if Traffic.Count(entry.index) > 0 then
			Traffic.SetLanes(entry.index, RoadGraph.GetLanes(current.roads))
		else
			spawnVehicles(entry, current, config)
		end
	end
end

local function schedule(entry: PlotEntry): ()
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
		vehiclesBlocked = false,
		suspectSince = nil,
		confirmSuspect = false,
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

local function localPlotIndex(): number?
	local value = player:GetAttribute(PLOT_INDEX_ATTRIBUTE)
	return if typeof(value) == "number" then value else nil
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
		local suspectSince = entry.suspectSince
		if suspectSince ~= nil and now - suspectSince >= lod.refreshSeconds then
			entry.confirmSuspect = true
			schedule(entry)
		end
	end
	if Traffic.Room(config.budget.vehiclesMap) > 0 then
		for _, entry in entries do
			if entry.vehiclesBlocked then
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
