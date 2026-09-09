--!strict
-- Shared config lookup: the one place that does Instance traversal + caching for Game.json,
-- Sounds.json, era configs, and layout modules, so server and client resolve them identically.
--
-- Era/layout lookups use FindFirstChild and return nil when absent: the server must boot (and
-- warn) even if an era file is missing, and the client only queries after a Snapshot arrives,
-- by which point ReplicatedStorage has fully replicated.

local Types = require(script.Parent:WaitForChild("Types"))

local sharedFolder = script.Parent :: Instance
local configFolder = sharedFolder:WaitForChild("Config")

-- Schema version stamped on the fallback config when Sounds.json is absent (mirrors its v1).
local SOUNDS_SCHEMA_VERSION = 1

local cachedGameConfig: Types.GameConfig? = nil
local cachedSoundsConfig: Types.SoundsConfig? = nil
local cachedEraConfigs: { [number]: Types.EraConfig } = {}
local cachedLayouts: { [string]: Types.EraLayout } = {}
local cachedEraCount: number? = nil

local Catalog = {}

function Catalog.GetGameConfig(): Types.GameConfig
	local cached = cachedGameConfig
	if cached == nil then
		cached = require(configFolder:WaitForChild("Game") :: ModuleScript) :: Types.GameConfig
		cachedGameConfig = cached
	end
	return cached :: Types.GameConfig
end

-- Sounds.json is presentation-only, so a missing file degrades to a silent, empty-but-valid
-- config instead of blocking boot (spec §9: nothing may depend on audio). The fallback is not
-- cached and is a fresh table per call: if the module shows up later (client replication
-- order) the next call picks it up, and callers can never mutate a shared placeholder.
function Catalog.GetSoundsConfig(): Types.SoundsConfig
	local cached = cachedSoundsConfig
	if cached ~= nil then
		return cached
	end
	local soundsModule = configFolder:FindFirstChild("Sounds")
	if soundsModule == nil or not soundsModule:IsA("ModuleScript") then
		return { version = SOUNDS_SCHEMA_VERSION, groups = {}, sounds = {}, ambient = {} }
	end
	cached = require(soundsModule) :: Types.SoundsConfig
	cachedSoundsConfig = cached
	return cached :: Types.SoundsConfig
end

-- Era config modules are named "<eraIndex>_<Name>" (e.g. "1_Village"); resolve by prefix.
function Catalog.GetEraConfig(eraIndex: number): Types.EraConfig?
	local cached = cachedEraConfigs[eraIndex]
	if cached ~= nil then
		return cached
	end
	local erasFolder = configFolder:FindFirstChild("Eras")
	if erasFolder == nil then
		return nil
	end
	local prefix = tostring(eraIndex) .. "_"
	for _, child in erasFolder:GetChildren() do
		if child:IsA("ModuleScript") and string.sub(child.Name, 1, #prefix) == prefix then
			local eraConfig = require(child) :: Types.EraConfig
			cachedEraConfigs[eraIndex] = eraConfig
			return eraConfig
		end
	end
	return nil
end

-- Number of era config modules present; the max era index is never hardcoded (M2 contract).
-- Counted once: era configs are static per server run, and the client only calls this after
-- a Snapshot arrives, by which point Config/Eras has fully replicated.
function Catalog.GetEraCount(): number
	local cached = cachedEraCount
	if cached ~= nil then
		return cached
	end
	local count = 0
	local erasFolder = configFolder:FindFirstChild("Eras")
	if erasFolder ~= nil then
		for _, child in erasFolder:GetChildren() do
			-- Only "<eraIndex>_<Name>" modules count; ignores stray non-era children.
			if child:IsA("ModuleScript") and string.match(child.Name, "^%d+_") ~= nil then
				count += 1
			end
		end
	end
	cachedEraCount = count
	return count
end

-- The layout ModuleScript name equals the era's `name` field (e.g. Layouts/Village).
function Catalog.GetLayout(eraName: string): Types.EraLayout?
	local cached = cachedLayouts[eraName]
	if cached ~= nil then
		return cached
	end
	local layoutsFolder = sharedFolder:FindFirstChild("Layouts")
	if layoutsFolder == nil then
		return nil
	end
	local layoutModule = layoutsFolder:FindFirstChild(eraName)
	if layoutModule == nil or not layoutModule:IsA("ModuleScript") then
		return nil
	end
	local layout = require(layoutModule) :: Types.EraLayout
	cachedLayouts[eraName] = layout
	return layout
end

return Catalog
