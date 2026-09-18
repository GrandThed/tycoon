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
-- two maps are independent namespaces) never collapse into one entry.
local function collectModels(
	into: { [string]: Types.AssetModel },
	models: ModelMap?,
	keyPrefix: string
): ()
	if type(models) ~= "table" then
		return
	end
	for modelName, assetModel in models :: ModelMap do
		if type(assetModel) == "table" and type(assetModel.stages) == "table" then
			into[keyPrefix .. modelName] = assetModel
		end
	end
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
	collectModels(models, config.eras[eraName], BUILDING_KEY_PREFIX)
	collectModels(models, eraProps, PROP_KEY_PREFIX)

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
