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
-- Stamped on the fallback config when Monetization.json is absent (mirrors its v1). The
-- fallback carries no passes/products and neutral multipliers, so an absent file behaves
-- exactly like the shipping all-ids-zero state: no shop, no prompts, no multipliers.
local MONETIZATION_SCHEMA_VERSION = 1
-- Mirrors the shipped Monetization.json value. Never 0: the fallback config is used for real
-- receipt bookkeeping, and a 0 limit would trim the idempotency log empty on the first insert.
local MONETIZATION_DEFAULT_RECEIPT_HISTORY_LIMIT = 200
-- Stamped on the fallback config when LegacyShop.json is absent (mirrors its v1). No perks ⇒
-- every Economy perk helper returns its neutral value and the client hides the shop.
local LEGACY_SHOP_SCHEMA_VERSION = 1

local cachedGameConfig: Types.GameConfig? = nil
local cachedSoundsConfig: Types.SoundsConfig? = nil
local cachedEraConfigs: { [number]: Types.EraConfig } = {}
local cachedLayouts: { [string]: Types.EraLayout } = {}
local cachedEraCount: number? = nil
local cachedMonetizationConfig: Types.MonetizationConfig? = nil
local cachedLegacyShopConfig: Types.LegacyShopConfig? = nil
local cachedAssetsConfig: Types.AssetsConfig? = nil

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

-- Monetization.json is optional in exactly the same sense as Sounds.json: the game must be
-- fully playable before the human creates a single pass or product. A missing module degrades
-- to a neutral config instead of blocking boot; the fallback is a fresh table per call so a
-- later-replicating module is picked up and callers can never mutate a shared placeholder.
function Catalog.GetMonetizationConfig(): Types.MonetizationConfig
	local cached = cachedMonetizationConfig
	if cached ~= nil then
		return cached
	end
	local monetizationModule = configFolder:FindFirstChild("Monetization")
	if monetizationModule == nil or not monetizationModule:IsA("ModuleScript") then
		return {
			version = MONETIZATION_SCHEMA_VERSION,
			multipliers = { doubleCash = 1, vip = 1, premium = 1 },
			packCapFractionOfEraSlotCost = 0,
			receiptHistoryLimit = MONETIZATION_DEFAULT_RECEIPT_HISTORY_LIMIT,
			passes = {},
			products = {},
		}
	end
	cached = require(monetizationModule) :: Types.MonetizationConfig
	cachedMonetizationConfig = cached
	return cached :: Types.MonetizationConfig
end

-- Linear scans over at most a handful of entries; the arrays are display order, so a map would
-- have to be kept alongside them anyway.
function Catalog.GetPassDef(key: string): Types.PassDef?
	for _, passDef in Catalog.GetMonetizationConfig().passes do
		if passDef.key == key then
			return passDef
		end
	end
	return nil
end

function Catalog.GetProductDef(key: string): Types.ProductDef?
	for _, productDef in Catalog.GetMonetizationConfig().products do
		if productDef.key == key then
			return productDef
		end
	end
	return nil
end

-- LegacyShop.json (M6) is optional in the same sense as Monetization.json: with the file absent
-- the shop hides and every perk helper is neutral, so the game runs before the designer's file
-- lands. Fresh fallback table per call for the same reasons as the other two fallbacks.
function Catalog.GetLegacyShopConfig(): Types.LegacyShopConfig
	local cached = cachedLegacyShopConfig
	if cached ~= nil then
		return cached
	end
	local shopModule = configFolder:FindFirstChild("LegacyShop")
	if shopModule == nil or not shopModule:IsA("ModuleScript") then
		return { version = LEGACY_SHOP_SCHEMA_VERSION, perks = {} }
	end
	cached = require(shopModule) :: Types.LegacyShopConfig
	cachedLegacyShopConfig = cached
	return cached :: Types.LegacyShopConfig
end

function Catalog.GetPerkDef(perkId: string): Types.PerkDef?
	for _, perkDef in Catalog.GetLegacyShopConfig().perks do
		if perkDef.id == perkId then
			return perkDef
		end
	end
	return nil
end

-- Assets.json (M7) is generated by the asset pipeline and optional at runtime. Unlike the other
-- optional configs there is no neutral fallback table: nil IS the signal ("no assets"), and
-- every consumer degrades to placeholders and plain textures on it. Re-checked per call until
-- the module shows up (client replication order), cached from then on.
function Catalog.GetAssetsConfig(): Types.AssetsConfig?
	local cached = cachedAssetsConfig
	if cached ~= nil then
		return cached
	end
	local assetsModule = configFolder:FindFirstChild("Assets")
	if assetsModule == nil or not assetsModule:IsA("ModuleScript") then
		return nil
	end
	cached = require(assetsModule) :: Types.AssetsConfig
	cachedAssetsConfig = cached
	return cached
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
