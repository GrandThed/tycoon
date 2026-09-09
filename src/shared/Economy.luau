--!strict
-- Pure economy math (spec §4, formulas frozen in docs/INTERFACES.md). No Roblox globals of
-- any kind — tools/sim_economy.py mirrors this file at M2 — so every config value arrives as
-- an argument and only the Lua standard library is used.

-- Structural copies of the shapes in Types.luau: requiring Types would need `script`, which
-- purity forbids. Keep these in lockstep with Types.luau; callers pass the Types.* tables and
-- Luau's structural typing accepts them.
type SlotState = { level: number }

type SlotType = "building" | "unlock" | "decor" | "monument"

type SlotConfig = {
	id: string,
	type: SlotType,
	name: string,
	modelName: string,
	description: string,
	baseCost: number,
	baseIncome: number,
	requires: string?,
	multiplier: number?,
	kit: string?,
}

type EraConfig = {
	eraIndex: number,
	name: string,
	displayName: string,
	slots: { SlotConfig },
}

type GameConfig = {
	maxLevel: number,
	levelIncomeBonus: number,
	milestoneLevels: { number },
	milestoneMultiplier: number,
	levelCost: { factor: number, growth: number, minBase: number },
	legacy: {
		incomePerPoint: number,
		gainBase: number,
		gainLevelsDivisor: number,
		gainRebirthBonus: number,
		softcap: number?,
	},
	-- Exact mirror of Types.OfflineConfig: the old solver compares nested tables invariantly.
	offline: {
		capSeconds: number,
		capSecondsOfflinePro: number,
		efficiency: number,
		efficiencyOfflinePro: number,
		welcomeBackMinSeconds: number,
	},
	neighbors: { perPlayer: number, maxBonus: number },
}

-- perk is optional HERE only (Types.Multipliers requires it) so a caller still passing the
-- pre-M6 four-field table multiplies by 1 instead of erroring at runtime.
type Multipliers = {
	legacy: number,
	perk: number?,
	pass: number,
	premium: number,
	neighbors: number,
}

-- M6 Legacy shop shapes: exact structural copies of Types.PerkTier/PerkDef/LegacyShopConfig/
-- LegacyShopState (nested tables must match field-for-field under the old solver).
type PerkTier = { cost: number, value: number, maxBonus: number? }
type PerkDef = {
	id: string,
	name: string,
	description: string,
	cosmetic: boolean,
	effect: "incomeMult"
		| "levelCostDiscount"
		| "startingSlots"
		| "levelFloor"
		| "extraMilestone"
		| "neighbours"
		| "offlineCapSeconds"
		| "cosmetic",
	tiers: { PerkTier },
	titles: { string }?,
	color: string?,
}
type LegacyShopConfig = { version: number, perks: { PerkDef } }
type LegacyShopState = { spent: number, perks: { [string]: number } }
type LegacyOwner = { legacy: number, legacyShop: LegacyShopState? }

-- Perk ids are frozen persistence keys (docs/INTERFACES.md M6); the helpers below look each
-- one up by id, so a perk missing from the config simply contributes nothing.
local PERK_FOUNDERS = "founders"
local PERK_BUILDERS = "builders"
local PERK_INHERITANCE = "inheritance"
local PERK_LEVEL_FLOOR = "levelFloor"
local PERK_MILESTONE = "milestone75"
local PERK_NEIGHBOURS = "neighbours"
local PERK_LONG_MEMORY = "longMemory"

-- Structural copy of Types.MonetizationConfig's multiplier block (purity forbids requiring
-- Types); only the fields these functions read are declared.
type MonetizationConfig = {
	multipliers: { doubleCash: number, vip: number, premium: number },
}

local Economy = {}

function Economy.MilestoneMult(
	level: number,
	milestoneLevels: { number },
	milestoneMultiplier: number
): number
	local reached = 0
	for _, milestone in milestoneLevels do
		if milestone <= level then
			reached += 1
		end
	end
	return milestoneMultiplier ^ reached
end

-- milestoneLevels overrides game.milestoneLevels (Extra Milestone perk); absent ⇒ the game list.
function Economy.SlotIncome(
	baseIncome: number,
	level: number,
	gameConfig: GameConfig,
	milestoneLevels: { number }?
): number
	return baseIncome
		* (1 + gameConfig.levelIncomeBonus * (level - 1))
		* Economy.MilestoneMult(
			level,
			milestoneLevels or gameConfig.milestoneLevels,
			gameConfig.milestoneMultiplier
		)
end

-- discount (Master Builders, 0..1) is applied HERE and nowhere else, so the Build panel preview
-- and the server charge can never disagree.
function Economy.LevelUpCost(
	baseCost: number,
	targetLevel: number,
	gameConfig: GameConfig,
	discount: number?
): number
	-- The minBase floor keeps level-ups from being free on zero-cost starter slots.
	return math.max(baseCost, gameConfig.levelCost.minBase)
		* gameConfig.levelCost.factor
		* gameConfig.levelCost.growth ^ (targetLevel - 1)
		* (1 - (discount or 0))
end

function Economy.LevelUpCostTotal(
	baseCost: number,
	fromLevel: number,
	toLevel: number,
	gameConfig: GameConfig,
	discount: number?
): number
	local total = 0
	for targetLevel = fromLevel + 1, toLevel do
		total += Economy.LevelUpCost(baseCost, targetLevel, gameConfig, discount)
	end
	return total
end

function Economy.EraMult(slots: { [string]: SlotState }, eraConfig: EraConfig): number
	local bonus = 0
	for _, slot in eraConfig.slots do
		local multiplier = slot.multiplier
		if
			multiplier ~= nil
			and slots[slot.id] ~= nil
			and (slot.type == "unlock" or slot.type == "decor")
		then
			bonus += multiplier
		end
	end
	return 1 + bonus
end

-- Softcap (Game.json v1.6): past `softcap` points Legacy counts logarithmically, continuous and
-- smooth at the knee, so late laps keep a reason to buy perks instead of running away. No
-- softcap key ⇒ linear, exactly the pre-M6 curve.
function Economy.LegacyMult(legacy: number, gameConfig: GameConfig): number
	local softcap = gameConfig.legacy.softcap
	local effective = if softcap ~= nil and legacy > softcap
		then softcap + softcap * math.log(legacy / softcap)
		else legacy
	return 1 + gameConfig.legacy.incomePerPoint * effective
end

-- perPlayer/maxBonus override game.neighbors (Good Neighbours perk); absent ⇒ the game values.
function Economy.NeighborsMult(
	playerCount: number,
	gameConfig: GameConfig,
	perPlayer: number?,
	maxBonus: number?
): number
	return 1
		+ math.min(
			(perPlayer or gameConfig.neighbors.perPlayer) * (playerCount - 1),
			maxBonus or gameConfig.neighbors.maxBonus
		)
end

-- milestoneLevels: the owner's list from Economy.MilestoneLevels (Extra Milestone perk); absent
-- ⇒ the game list. Threaded here because SlotIncome is called inside this loop.
function Economy.IncomePerSecond(
	slots: { [string]: SlotState },
	eraConfig: EraConfig,
	gameConfig: GameConfig,
	mults: Multipliers,
	milestoneLevels: { number }?
): number
	local base = 0
	for _, slot in eraConfig.slots do
		local owned = slots[slot.id]
		if owned ~= nil and slot.type == "building" then
			base += Economy.SlotIncome(slot.baseIncome, owned.level, gameConfig, milestoneLevels)
		end
	end
	return base
		* Economy.EraMult(slots, eraConfig)
		* mults.legacy
		* (mults.perk or 1)
		* mults.pass
		* mults.premium
		* mults.neighbors
end

-- Floor wraps the whole product (documented spec clarification per §12.6): the spec's literal
-- formula floors only the first factor and can yield fractional legacy; this keeps it integral.
function Economy.LegacyGain(
	eraIndex: number,
	totalLevelsThisEra: number,
	rebirthCount: number,
	gameConfig: GameConfig
): number
	local legacyConfig = gameConfig.legacy
	return math.floor(
		legacyConfig.gainBase
			* eraIndex
			* (1 + totalLevelsThisEra / legacyConfig.gainLevelsDivisor)
			* (1 + rebirthCount * legacyConfig.gainRebirthBonus)
	)
end

-- M4 monetization math. Kept here (not in MonetizationService) so tools/sim_economy.py can
-- mirror it and the client can preview the same grant the server will compute.

-- Every slot in the era, owned or not: the anti-skip cap is a flat era-relative ceiling, so a
-- player near the end of an era still gets a meaningful pack (lead ruling, docs/INTERFACES.md).
function Economy.EraSlotCostTotal(eraConfig: EraConfig): number
	local total = 0
	for _, slot in eraConfig.slots do
		total += slot.baseCost
	end
	return total
end

-- Packs are priced in minutes of the player's CURRENT income (spec §6 rule 6), then capped so
-- one purchase can never buy more than capFraction of an era.
function Economy.PackGrant(
	minutes: number,
	incomePerSecond: number,
	eraSlotCostTotal: number,
	capFraction: number
): number
	local uncapped = minutes * 60 * incomePerSecond
	local cap = capFraction * eraSlotCostTotal
	return math.max(math.min(uncapped, cap), 0)
end

-- An unowned pass, or one whose id is still 0 (never granted), contributes exactly 1.
function Economy.PassMult(
	passes: { [string]: boolean },
	monetizationConfig: MonetizationConfig
): number
	local multipliers = monetizationConfig.multipliers
	local mult = 1
	if passes.DoubleCash == true then
		mult *= multipliers.doubleCash
	end
	if passes.VIP == true then
		mult *= multipliers.vip
	end
	return mult
end

function Economy.PremiumMult(isPremium: boolean, monetizationConfig: MonetizationConfig): number
	return if isPremium then monetizationConfig.multipliers.premium else 1
end

-- Frozen now, used at M2 for offline progress.
function Economy.OfflineGrant(
	elapsedSeconds: number,
	incomePerSecond: number,
	capSeconds: number,
	efficiency: number
): number
	return math.clamp(elapsedSeconds, 0, capSeconds) * incomePerSecond * efficiency
end

-- M6 Legacy shop helpers. Every one takes the shop config as an argument so the server, the
-- client and tools/sim_economy.py read the same LegacyShop.json and agree to the digit.

local function findPerkDef(shop: LegacyShopConfig, perkId: string): PerkDef?
	for _, perkDef in shop.perks do
		if perkDef.id == perkId then
			return perkDef
		end
	end
	return nil
end

-- Tier owned; 0 when the perk is unowned or there is no shop state at all.
function Economy.PerkTier(shopState: LegacyShopState?, perkId: string): number
	if shopState == nil then
		return 0
	end
	local tier: number? = shopState.perks[perkId]
	return tier or 0
end

-- The owned tier's total `value`; nil when unowned or the perk is absent from the config. A
-- profile tier beyond the config's tier count (a shrunk config) clamps to the last tier rather
-- than vanishing, so a player never loses a perk they paid for to a config edit.
function Economy.PerkValue(
	shop: LegacyShopConfig,
	shopState: LegacyShopState?,
	perkId: string
): number?
	local tier = Economy.PerkTier(shopState, perkId)
	if tier <= 0 then
		return nil
	end
	local perkDef = findPerkDef(shop, perkId)
	if perkDef == nil or #perkDef.tiers == 0 then
		return nil
	end
	return perkDef.tiers[math.min(tier, #perkDef.tiers)].value
end

function Economy.PerkIncomeMult(shop: LegacyShopConfig, shopState: LegacyShopState?): number
	return Economy.PerkValue(shop, shopState, PERK_FOUNDERS) or 1
end

function Economy.LevelCostDiscount(shop: LegacyShopConfig, shopState: LegacyShopState?): number
	return Economy.PerkValue(shop, shopState, PERK_BUILDERS) or 0
end

function Economy.LevelFloor(shop: LegacyShopConfig, shopState: LegacyShopState?): number
	return Economy.PerkValue(shop, shopState, PERK_LEVEL_FLOOR) or 1
end

-- The game's milestone list plus the Extra Milestone tier's level when owned, sorted; always a
-- fresh table so callers can never mutate Game.json's array.
function Economy.MilestoneLevels(
	shop: LegacyShopConfig,
	shopState: LegacyShopState?,
	gameConfig: GameConfig
): { number }
	local levels = table.clone(gameConfig.milestoneLevels)
	local extra = Economy.PerkValue(shop, shopState, PERK_MILESTONE)
	-- A level below 1 would be "reached" by every slot and silently double all income.
	if extra ~= nil and extra >= 1 and table.find(levels, extra) == nil then
		table.insert(levels, extra)
		table.sort(levels)
	end
	return levels
end

-- (perPlayer, maxBonus) for NeighborsMult: the Good Neighbours tier's value/maxBonus when
-- owned, else the game defaults. maxBonus lives on the tier because it must scale with
-- perPlayer or the perk is worthless past the cap (docs/LEGACY_SHOP.md §8).
function Economy.NeighborsParams(
	shop: LegacyShopConfig,
	shopState: LegacyShopState?,
	gameConfig: GameConfig
): (number, number)
	local tier = Economy.PerkTier(shopState, PERK_NEIGHBOURS)
	local perkDef = findPerkDef(shop, PERK_NEIGHBOURS)
	if tier <= 0 or perkDef == nil or #perkDef.tiers == 0 then
		return gameConfig.neighbors.perPlayer, gameConfig.neighbors.maxBonus
	end
	local tierDef = perkDef.tiers[math.min(tier, #perkDef.tiers)]
	return tierDef.value, tierDef.maxBonus or gameConfig.neighbors.maxBonus
end

-- Pass cap (Offline Pro or default) plus Long Memory's extra seconds. Efficiency is deliberately
-- not sold (it would erode the pass), so the caller keeps its own efficiency logic.
function Economy.OfflineCapSeconds(
	passes: { [string]: boolean },
	shopState: LegacyShopState?,
	shop: LegacyShopConfig,
	gameConfig: GameConfig
): number
	local offline = gameConfig.offline
	local base = if passes.OfflinePro == true
		then offline.capSecondsOfflinePro
		else offline.capSeconds
	return base + (Economy.PerkValue(shop, shopState, PERK_LONG_MEMORY) or 0)
end

-- Cash granted on entering an era: the baseCost of the first N slots in array order (array
-- order, not the requires chain — layouts branch). Cash only; slots are still bought in order.
function Economy.InheritanceCash(
	eraConfig: EraConfig,
	shop: LegacyShopConfig,
	shopState: LegacyShopState?
): number
	local slotCount = Economy.PerkValue(shop, shopState, PERK_INHERITANCE) or 0
	local total = 0
	for index, slot in eraConfig.slots do
		if index > slotCount then
			break
		end
		total += slot.baseCost
	end
	return total
end

-- Legacy invested stays in `legacy` (it keeps multiplying income); only the remainder is
-- spendable in the shop.
function Economy.LegacySpendable(state: LegacyOwner): number
	local shopState = state.legacyShop
	return state.legacy - (if shopState ~= nil then shopState.spent else 0)
end

-- The tier the player may buy next (tiers are bought strictly in order) and its 1-based index;
-- (nil, 0) when the perk is unknown or fully owned.
function Economy.NextPerkTier(
	shop: LegacyShopConfig,
	shopState: LegacyShopState?,
	perkId: string
): (PerkTier?, number)
	local perkDef = findPerkDef(shop, perkId)
	if perkDef == nil then
		return nil, 0
	end
	local index = Economy.PerkTier(shopState, perkId) + 1
	local tier: PerkTier? = perkDef.tiers[index]
	if tier == nil then
		return nil, 0
	end
	return tier, index
end

return Economy
