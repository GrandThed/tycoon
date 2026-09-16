--!strict
-- Client asset warm-up (docs/INTERFACES.md, "Amendment — asset preload, no grey flash").
-- Template MeshParts replicate before their mesh and texture have downloaded, so a building
-- renders grey and colours in a moment later. PreloadEra warms the era's content ahead of
-- time from Assets.json; AwaitInstance lets PlotVisualsController hold a freshly replicated
-- stage hidden until its actual MeshParts (which carry the server's VIP texture choice, not
-- necessarily the Assets.json image) are loaded. A utility module, not a controller: it has
-- no Init/Start and Main.client does not boot it.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))

local ASSET_PREFIX = "rbxassetid://"

-- Content strings already handed to ContentProvider this session. ContentProvider dedups on
-- its own, but skipping here keeps repeat PreloadEra calls (every era/VIP change) free.
local requested: { [string]: boolean } = {}

-- Ids are up to 15 digits; %d keeps them integral where tostring could print an exponent.
local function contentFor(id: number): string
	return ASSET_PREFIX .. string.format("%d", id)
end

local function queue(list: { string }, id: number): ()
	if id <= 0 then
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

function AssetPreloader.PreloadEra(eraName: string, includeVip: boolean): ()
	local config = Catalog.GetAssetsConfig()
	if config == nil then
		return
	end
	local era = config.eras[eraName]
	if era == nil then
		return
	end

	-- Sorted so the request order (and so what the player sees first) is deterministic.
	local modelNames: { string } = {}
	local stageCount = 0
	for modelName, assetModel in era do
		table.insert(modelNames, modelName)
		stageCount = math.max(stageCount, #assetModel.stages)
	end
	table.sort(modelNames)

	-- Textures first: one kit image colours many meshes, so it is the cheapest win.
	local content: { string } = {}
	local kits: { [string]: boolean } = {}
	for _, modelName in modelNames do
		for _, stage: Types.AssetStage in era[modelName].stages do
			for _, part in stage.parts do
				queue(content, part.imageId)
				kits[part.kit] = true
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
	-- Meshes by stage: every stage 0 (what a fresh plot shows) before any later growth stage.
	for stageIndex = 1, stageCount do
		for _, modelName in modelNames do
			local stage = era[modelName].stages[stageIndex]
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
