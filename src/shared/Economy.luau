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
}

type EraConfig = {
	eraIndex: number,
	name: string,
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
	},
	neighbors: { perPlayer: number, maxBonus: number },
}

type Multipliers = { legacy: number, pass: number, premium: number, neighbors: number }

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

function Economy.SlotIncome(baseIncome: number, level: number, gameConfig: GameConfig): number
	return baseIncome
		* (1 + gameConfig.levelIncomeBonus * (level - 1))
		* Economy.MilestoneMult(level, gameConfig.milestoneLevels, gameConfig.milestoneMultiplier)
end

function Economy.LevelUpCost(baseCost: number, targetLevel: number, gameConfig: GameConfig): number
	-- The minBase floor keeps level-ups from being free on zero-cost starter slots.
	return math.max(baseCost, gameConfig.levelCost.minBase)
		* gameConfig.levelCost.factor
		* gameConfig.levelCost.growth ^ (targetLevel - 1)
end

function Economy.LevelUpCostTotal(
	baseCost: number,
	fromLevel: number,
	toLevel: number,
	gameConfig: GameConfig
): number
	local total = 0
	for targetLevel = fromLevel + 1, toLevel do
		total += Economy.LevelUpCost(baseCost, targetLevel, gameConfig)
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

function Economy.LegacyMult(legacy: number, gameConfig: GameConfig): number
	return 1 + gameConfig.legacy.incomePerPoint * legacy
end

function Economy.NeighborsMult(playerCount: number, gameConfig: GameConfig): number
	return 1
		+ math.min(
			gameConfig.neighbors.perPlayer * (playerCount - 1),
			gameConfig.neighbors.maxBonus
		)
end

function Economy.IncomePerSecond(
	slots: { [string]: SlotState },
	eraConfig: EraConfig,
	gameConfig: GameConfig,
	mults: Multipliers
): number
	local base = 0
	for _, slot in eraConfig.slots do
		local owned = slots[slot.id]
		if owned ~= nil and slot.type == "building" then
			base += Economy.SlotIncome(slot.baseIncome, owned.level, gameConfig)
		end
	end
	return base
		* Economy.EraMult(slots, eraConfig)
		* mults.legacy
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

-- Frozen now, used at M2 for offline progress.
function Economy.OfflineGrant(
	elapsedSeconds: number,
	incomePerSecond: number,
	capSeconds: number,
	efficiency: number
): number
	return math.clamp(elapsedSeconds, 0, capSeconds) * incomePerSecond * efficiency
end

return Economy
