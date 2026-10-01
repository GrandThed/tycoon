--!strict
-- Client asset warm-up (docs/INTERFACES.md, "Amendment — asset preload, no grey flash").
-- Template MeshParts replicate before their mesh and texture have downloaded, so a building
-- renders grey and colours in a moment later. PreloadEra warms the era's content ahead of
-- time from Assets.json; AwaitInstance lets PlotVisualsController hold a freshly replicated
-- stage hidden until its actual MeshParts (which carry the server's VIP texture choice, not
-- necessarily the Assets.json image) are loaded. M9: PreloadEra also warms the era's city
-- dressing props (Assets.json v2 `props`) and baked path pieces (v3 `paths`), which the City
-- modules gate the same way. A utility module, not a controller: it has no Init/Start and
-- Main.client does not boot it.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local ASSET_PREFIX = "rbxassetid://"
-- Sort-key prefixes keeping buildings and props (independent name spaces) apart in one pass.
local BUILDING_KEY_PREFIX = "b:"
local PROP_KEY_PREFIX = "p:"

-- Content strings already handed to ContentProvider this session. ContentProvider dedups on
-- its own, but skipping here keeps repeat PreloadEra calls (every era/VIP change) free.
local requested: { [string]: boolean } = {}

-- Ids are up to 15 digits; %d keeps them integral where tostring could print an exponent.
local function contentFor(id: number): string
	return ASSET_PREFIX .. string.format("%d", id)
end

-- A nil id is a key a hand-edited Assets.json never grew, and reads exactly like "not uploaded".
local function queue(list: { string }, id: number?): ()
	if id == nil or id <= 0 then
		return -- 0 means "not uploaded yet"; never an error
	end
	local content = contentFor(id)
	if requested[content] then
		return
	end
	requested[content] = true
	table.insert(list, content)
end

-- Failures are otherwise ignored on purpose: a building whose asset failed is shown anyway.
local function preload(content: { any }, onFetched: ((string, Enum.AssetFetchStatus) -> ())?): ()
	pcall(function()
		ContentProvider:PreloadAsync(content, onFetched)
	end)
end

-- A failed or timed-out id is forgotten so the next PreloadEra (era/VIP change) retries it.
local function forgetUnfetched(content: string, status: Enum.AssetFetchStatus): ()
	if status ~= Enum.AssetFetchStatus.Success then
		requested[content] = nil
	end
end

local AssetPreloader = {}

type ModelMap = { [string]: Types.AssetModel }

-- Appends one map's models under a key prefix, so a prop and a building sharing a name (the
-- two maps are independent namespaces) never collapse into one entry. `skip` names models to
-- leave out; `only`, when given, names the models to take and leaves out every other.
local function collectModels(
	into: { [string]: Types.AssetModel },
	models: ModelMap?,
	keyPrefix: string,
	skip: { [string]: boolean }?,
	only: { [string]: boolean }?
): ()
	if type(models) ~= "table" then
		return
	end
	for modelName, assetModel in models :: ModelMap do
		if (skip ~= nil and skip[modelName]) or (only ~= nil and not only[modelName]) then
			continue
		end
		if type(assetModel) == "table" and type(assetModel.stages) == "table" then
			into[keyPrefix .. modelName] = assetModel
		end
	end
end

-- The era's building models that can never spawn: every slot naming one is `streetOnly`, for
-- which the server lays an empty marker and the client redresses the streets instead (wave 1e;
-- M12's city-changer slots). Their meshes would be downloaded for nothing. Read from the slot
-- flag, so a slot that changes kind needs no change here; a model no slot names is kept, as it
-- always was.
local function neverSpawned(eraName: string): { [string]: boolean }
	local spawns: { [string]: boolean } = {}
	local skip: { [string]: boolean } = {}
	for eraIndex = 1, Catalog.GetEraCount() do
		local eraConfig = Catalog.GetEraConfig(eraIndex)
		if eraConfig == nil or eraConfig.name ~= eraName then
			continue
		end
		for _, slot in eraConfig.slots do
			if slot.streetOnly == true then
				skip[slot.modelName] = true
			else
				spawns[slot.modelName] = true
			end
		end
		break
	end
	for modelName in spawns do
		skip[modelName] = nil
	end
	return skip
end

-- Every string anywhere inside `value`: a config block names its props as values, at whatever
-- depth, and a string that is not a prop name matches nothing in Assets.json and costs nothing.
local function collectStrings(into: { [string]: boolean }, value: any): ()
	if type(value) == "string" then
		into[value] = true
	elseif type(value) == "table" then
		for _, item in value do
			collectStrings(into, item)
		end
	end
end

local function present(value: any): boolean
	return type(value) == "table" and next(value) ~= nil
end

-- The props an era with a city fabric can still spawn, or nil for an era without one, which
-- preloads every prop it has, as it always did. The fabric replaces the layout's lots, groves,
-- greenery zones and parking, so the props those features draw from no longer appear and need no
-- download. Nothing here lists a prop: the names are whatever the era's own config block says --
-- its fabric (districts, sites, woods, marker, scaffold, upgrade layers), roads, lamps, signals,
-- vehicles and their unlocks, walkers -- plus the plazas and wild singles its layout and fabric
-- data place and the birds, and a block is left out only while the layout lacks what it is
-- placed by. A new config key that names props is therefore picked up with no change here.
local function spawnableProps(eraName: string): { [string]: boolean }?
	local dressing = Catalog.GetCityDressingConfig()
	local eras = if dressing ~= nil then dressing.eras else nil
	local era: any = if type(eras) == "table" then eras[eraName] else nil
	local data: any = Catalog.GetFabric(eraName)
	-- The controller's own test for "this era grows a fabric".
	if type(era) ~= "table" or type(era.fabric) ~= "table" or type(data) ~= "table" then
		return nil
	end
	local layout: any = Catalog.GetLayout(eraName) or {}
	local tiles = if type(era.road) == "table" then era.road.tiles else nil
	-- Config block -> whether the layout still carries what that feature is placed by.
	local placed: { [string]: boolean } = {
		houses = present(layout.lots),
		-- The layout names each plaza's prop itself; the config list is only its pool.
		plazas = false,
		-- Groves, or a tiles era's street trees and park-strip planters.
		trees = present(layout.treeZones) or type(tiles) == "table",
		greenery = present(layout.greeneryZones) or present(layout.lots),
		parked = present(layout.parking),
		subway = present(layout.subwayEntrances),
		highway = present(layout.highway),
	}
	local names: { [string]: boolean } = {}
	for key, block in era do
		if placed[key] ~= false then
			collectStrings(names, block)
		end
	end
	if type(layout.plazas) == "table" then
		for _, plaza in layout.plazas do
			collectStrings(names, if type(plaza) == "table" then plaza.prop else nil)
		end
	end
	if type(data.wild) == "table" then
		for _, entry in data.wild do
			collectStrings(names, if type(entry) == "table" then entry.prop else nil)
		end
	end
	local ambient: any = if dressing ~= nil then dressing.ambient else nil
	local birds = if type(ambient) == "table" then ambient.birds else nil
	collectStrings(names, if type(birds) == "table" then birds.prop else nil)
	return names
end

function AssetPreloader.PreloadEra(eraName: string, includeVip: boolean): ()
	local config = Catalog.GetAssetsConfig()
	if config == nil then
		return
	end
	-- Path pieces (v3) are two meshes and two shared images per era; a v1/v2 file has none.
	local pathsByEra = config.paths
	local eraPaths: Types.AssetPathsEra? = if pathsByEra ~= nil then pathsByEra[eraName] else nil
	-- Buildings and (Assets.json v2) city-dressing props share one pass; a v1 file has no
	-- `props` key and simply contributes nothing.
	local propsByEra = config.props
	local eraProps: ModelMap? = if propsByEra ~= nil then propsByEra[eraName] else nil
	local models: { [string]: Types.AssetModel } = {}
	collectModels(models, config.eras[eraName], BUILDING_KEY_PREFIX, neverSpawned(eraName), nil)
	collectModels(models, eraProps, PROP_KEY_PREFIX, nil, spawnableProps(eraName))

	-- Sorted so the request order (and so what the player sees first) is deterministic.
	local modelKeys: { string } = {}
	local stageCount = 0
	for modelKey, assetModel in models do
		table.insert(modelKeys, modelKey)
		stageCount = math.max(stageCount, #assetModel.stages)
	end
	if #modelKeys == 0 and eraPaths == nil then
		return
	end
	table.sort(modelKeys)

	-- Textures first: one kit image colours many meshes, so it is the cheapest win.
	local content: { string } = {}
	local kits: { [string]: boolean } = {}
	if eraPaths ~= nil then
		queue(content, eraPaths.fillImageId)
		queue(content, eraPaths.rimImageId)
		-- Wave 1e surface variants: two more images per variant, shared by every piece of the era,
		-- warmed whether or not this plot has earned the upgrade yet.
		local variants = eraPaths.variants
		if type(variants) == "table" then
			local variantNames: { string } = {}
			for variantName in variants do
				table.insert(variantNames, variantName)
			end
			table.sort(variantNames)
			for _, variantName in variantNames do
				local variant = variants[variantName]
				queue(content, variant.fillImageId)
				queue(content, variant.rimImageId)
			end
		end
	end
	for _, modelKey in modelKeys do
		-- Only buildings wear VIP skins; a prop-only kit's VIP image would never be shown.
		local isBuilding = string.sub(modelKey, 1, #BUILDING_KEY_PREFIX) == BUILDING_KEY_PREFIX
		for _, stage: Types.AssetStage in models[modelKey].stages do
			for _, part in stage.parts do
				queue(content, part.imageId)
				if isBuilding then
					kits[part.kit] = true
				end
			end
		end
	end
	if includeVip then
		for kit in kits do
			local texture = config.textures[kit]
			if texture ~= nil then
				queue(content, texture.vipImageId)
			end
		end
	end
	-- Paths before the buildings' later stages: a plot's first purchase draws one immediately.
	if eraPaths ~= nil and type(eraPaths.pieces) == "table" then
		local pieceIds: { string } = {}
		for pieceId in eraPaths.pieces do
			table.insert(pieceIds, pieceId)
		end
		table.sort(pieceIds)
		for _, pieceId in pieceIds do
			local piece = eraPaths.pieces[pieceId]
			queue(content, piece.fill.meshId)
			queue(content, piece.rim.meshId)
		end
	end
	-- Meshes by stage: every stage 0 (what a fresh plot shows) before any later growth stage.
	for stageIndex = 1, stageCount do
		for _, modelKey in modelKeys do
			local stage = models[modelKey].stages[stageIndex]
			if stage ~= nil then
				for _, part in stage.parts do
					queue(content, part.meshId)
				end
			end
		end
	end

	if #content > 0 then
		task.spawn(preload, content, forgetUnfetched)
	end
end

function AssetPreloader.AwaitInstance(instance: Instance, timeoutSeconds: number): ()
	local meshParts: { Instance } = {}
	if instance:IsA("MeshPart") then
		table.insert(meshParts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("MeshPart") then
			table.insert(meshParts, descendant)
		end
	end
	if #meshParts == 0 then
		return
	end

	local thread = coroutine.running()
	local resumed = false
	-- Deferred, not spawned: PreloadAsync can return without yielding when everything is
	-- cached, and resuming a thread that has not reached its yield yet would error.
	local function resume(): ()
		if resumed then
			return
		end
		resumed = true
		task.defer(thread)
	end
	local timeoutThread = task.delay(timeoutSeconds, resume)
	task.spawn(function()
		preload(meshParts, nil)
		if not resumed then
			task.cancel(timeoutThread)
			resume()
		end
	end)
	coroutine.yield()
end

return AssetPreloader
