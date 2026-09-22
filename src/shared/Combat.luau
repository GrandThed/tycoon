--!strict
-- Pure combat math (docs/INTERFACES.md "C0 contracts" → "src/shared/Combat.luau"): wave specs,
-- enemy stats, reward shares, away efficiency and the pacing tempo. No RNG anywhere — every
-- result is a deterministic function of config plus state — and no Roblox globals beyond the
-- `script` needed to require Economy, so tools/sim_combat.py mirrors this file function for
-- function (and imports the sim_economy mirror of Economy for the cash multiplier).

local Economy = require(script.Parent:WaitForChild("Economy"))

-- Structural copies of the shapes in Types.luau: requiring Types would need more than `script`
-- provides for a pure module, and the old solver compares nested tables invariantly, so every
-- field below must stay in lockstep with Types.luau.
type MissionRecord = { bestWave: number, bossClears: number, overdriveBest: number }
type CombatProfile = {
	materials: { [string]: number },
	valor: number,
	gear: { melee: number, ranged: number },
	ascension: { melee: number, ranged: number },
	missions: { [string]: MissionRecord },
	highestEra: number,
	expeditionSince: number,
	expeditionSeconds: number,
	stats: { kills: number, wavesCleared: number, expeditions: number, cashFromCombat: number },
}

type EnemyDef = {
	template: string,
	kind: string,
	hp: number,
	damage: number,
	speed: number,
	reach: number,
	attackCooldown: number,
	cash: number,
	materials: number,
	elite: boolean,
}
type CompositionDef = { fromWave: number, weights: { [string]: number } }
type WaveTableDef = {
	baseCount: number,
	countPerWave: number,
	hpGrowth: number,
	damageGrowth: number,
	rewardGrowth: number,
	composition: { CompositionDef },
}
type BossDef = {
	template: string,
	enemy: string,
	hpMult: number,
	damageMult: number,
	cashMult: number,
	materialsMult: number,
	valor: number,
}
type MissionConfig = {
	version: number,
	id: string,
	era: number,
	eraName: string,
	name: string,
	arena: string,
	material: string,
	waves: number,
	bossWaves: { number },
	recommendedPower: number,
	targetMinutes: number,
	targetWaveSeconds: number,
	enemies: { [string]: EnemyDef },
	waveTable: WaveTableDef,
	bosses: { [string]: BossDef },
}

type CombatCoopConfig = {
	maxParty: number,
	joinUntilWave: number,
	contributionFloor: number,
	countPerExtraPlayer: number,
	mentorRatio: number,
	mentorValor: number,
}
type CombatOverdriveConfig = {
	requiresRebirth: number,
	countMult: number,
	hpMult: number,
	damageMult: number,
	spawnRateMult: number,
	rewardMult: number,
}
type CombatDirectorConfig = {
	windowSeconds: number,
	tempoMin: number,
	tempoMax: number,
	mergeThreshold: number,
	mergeTempo: number,
	eliteTempo: number,
	breatherSeconds: number,
	breatherMaxSeconds: number,
	maxAlive: number,
	runCapSeconds: number,
}
-- The two Combat.json blocks these functions read; callers pass the whole Types.CombatConfig.
type CombatRules = { coop: CombatCoopConfig, overdrive: CombatOverdriveConfig }

-- Exact structural copies of the Economy.luau parameter types, so the values forwarded to
-- Economy.LegacyMult / Economy.PerkIncomeMult typecheck without a cast.
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
	offline: {
		capSeconds: number,
		capSecondsOfflinePro: number,
		efficiency: number,
		efficiencyOfflinePro: number,
		welcomeBackMinSeconds: number,
	},
	neighbors: { perPlayer: number, maxBonus: number },
}

-- The slices of PlayerState these functions read; callers pass the whole state.
type CombatOwner = { era: number, rebirthCount: number, combat: CombatProfile }
type CashOwner = { legacy: number, legacyShop: LegacyShopState }

-- One wave, fully resolved: how many enemies and by how much their stats and rewards are
-- multiplied. `boss` is the entry for this wave when it is a boss wave.
export type WaveSpec = {
	count: number,
	hpMult: number,
	damageMult: number,
	rewardMult: number,
	boss: BossDef?,
	weights: { [string]: number },
}

export type EnemyStats = { hp: number, damage: number, cash: number, materials: number }

local NEUTRAL_MULT = 1

local Combat = {}

-- PlotService.tryAdvanceEra is frozen this milestone, so the highest era a player ever reached
-- is raised lazily by every combat entry point instead of at the moment of the advance.
-- Idempotent and monotonic: Rebirth drops `era` back to 1 but never lowers this.
function Combat.TouchHighestEra(state: CombatOwner): ()
	local combat = state.combat
	if state.era > combat.highestEra then
		combat.highestEra = state.era
	end
end

-- A mission stays visible but locked until the city has reached its era; Overdrive is the
-- Rebirth difficulty spike, so it needs the configured lap count on top.
function Combat.MissionUnlocked(
	state: CombatOwner,
	mission: MissionConfig,
	overdrive: boolean,
	combatCfg: CombatRules
): boolean
	if mission.era > state.combat.highestEra then
		return false
	end
	if overdrive and state.rebirthCount < combatCfg.overdrive.requiresRebirth then
		return false
	end
	return true
end

-- The composition in force at `wave`: the last entry whose fromWave has been reached. A shallow
-- clone, never the config's own table: a spawner that normalises or drops a weight must not be
-- able to edit Missions/*.json for the rest of the server's life.
local function weightsForWave(mission: MissionConfig, wave: number): { [string]: number }
	local weights: { [string]: number } = {}
	local bestFromWave = -math.huge
	for _, entry in mission.waveTable.composition do
		if entry.fromWave <= wave and entry.fromWave > bestFromWave then
			bestFromWave = entry.fromWave
			weights = table.clone(entry.weights)
		end
	end
	return weights
end

-- Party size scales COUNT only (never enemy HP or damage): more players must not make each
-- enemy tankier. Overdrive is the only thing that raises hp/damage.
function Combat.WaveSpec(
	mission: MissionConfig,
	wave: number,
	partySize: number,
	overdrive: boolean,
	combatCfg: CombatRules
): WaveSpec
	local waveTable = mission.waveTable
	local overdriveCfg = combatCfg.overdrive
	local extras = math.max(partySize, 1) - 1
	local baseCount = waveTable.baseCount + waveTable.countPerWave * (wave - 1)
	local partyMult = 1 + combatCfg.coop.countPerExtraPlayer * extras
	local count = math.round(
		baseCount * partyMult * (if overdrive then overdriveCfg.countMult else NEUTRAL_MULT)
	)
	return {
		count = count,
		hpMult = (1 + waveTable.hpGrowth) ^ (wave - 1)
			* (if overdrive then overdriveCfg.hpMult else NEUTRAL_MULT),
		damageMult = (1 + waveTable.damageGrowth) ^ (wave - 1)
			* (if overdrive then overdriveCfg.damageMult else NEUTRAL_MULT),
		rewardMult = (1 + waveTable.rewardGrowth) ^ (wave - 1)
			* (if overdrive then overdriveCfg.rewardMult else NEUTRAL_MULT),
		boss = mission.bosses[tostring(wave)],
		weights = weightsForWave(mission, wave),
	}
end

-- Cash and materials are FIXED per enemy (no RNG, no loot tables): the wave multipliers are the
-- only thing that moves them. The boss multipliers ride on the ONE entity the spawner marks with
-- `isBoss` -- never on the ordinary enemies of the same key, which would have turned every brute
-- in Village wave 10 into a Warlord (the sim measured 7:58 -> 10:37). nil for an unknown key.
function Combat.EnemyStats(
	mission: MissionConfig,
	key: string,
	spec: WaveSpec,
	isBoss: boolean?
): EnemyStats?
	local enemy = mission.enemies[key]
	if enemy == nil then
		return nil
	end
	-- The key check stays as a guard so a mismarked spawn cannot apply another enemy's boss
	-- multipliers; tools/sim_combat.py gates on exactly these two conditions.
	local boss = spec.boss
	local applyBoss = isBoss == true and boss ~= nil and boss.enemy == key
	local bossHp = if applyBoss and boss ~= nil then boss.hpMult else NEUTRAL_MULT
	local bossDamage = if applyBoss and boss ~= nil then boss.damageMult else NEUTRAL_MULT
	local bossCash = if applyBoss and boss ~= nil then boss.cashMult else NEUTRAL_MULT
	local bossMaterials = if applyBoss and boss ~= nil then boss.materialsMult else NEUTRAL_MULT
	return {
		hp = math.round(enemy.hp * spec.hpMult * bossHp),
		damage = math.round(enemy.damage * spec.damageMult * bossDamage),
		cash = math.round(enemy.cash * spec.rewardMult * bossCash),
		materials = math.round(enemy.materials * spec.rewardMult * bossMaterials),
	}
end

-- Valor only ever drops from bosses; Overdrive pays the reward multiplier on it like cash.
function Combat.BossValor(
	mission: MissionConfig,
	wave: number,
	overdrive: boolean,
	combatCfg: CombatRules
): number
	local boss = mission.bosses[tostring(wave)]
	if boss == nil then
		return 0
	end
	return math.round(
		boss.valor * (if overdrive then combatCfg.overdrive.rewardMult else NEUTRAL_MULT)
	)
end

-- What the Expedition tile compares the player's Gear Power against. Overdrive multiplies enemy
-- HP, so the bar the player has to clear moves with it.
function Combat.RecommendedPower(
	mission: MissionConfig,
	overdrive: boolean,
	combatCfg: CombatRules
): number
	return mission.recommendedPower
		* (if overdrive then combatCfg.overdrive.hpMult else NEUTRAL_MULT)
end

-- Combat cash carries the PERMANENT city multipliers only (Legacy and Founder's Blessing).
-- Deliberately not the passes, Premium or the neighbors bonus: those are the city's idle
-- economy, and paying them on kills would price expeditions against the wrong curve.
function Combat.CombatCashMult(
	state: CashOwner,
	gameConfig: GameConfig,
	shopConfig: LegacyShopConfig
): number
	return Economy.LegacyMult(state.legacy, gameConfig)
		* Economy.PerkIncomeMult(shopConfig, state.legacyShop)
end

-- Damage-share split with a floor, so a low-power friend still earns: every participant gets
-- `floor` of the pot, and the rest is split by damage dealt. An all-zero-damage run (everyone
-- died to the timer) splits evenly rather than paying nothing.
function Combat.ContributionShares(
	damageByUser: { [number]: number },
	floor: number
): { [number]: number }
	local total = 0
	local count = 0
	for _, damage in damageByUser do
		total += damage
		count += 1
	end
	local shares: { [number]: number } = {}
	if count == 0 then
		return shares
	end
	if total <= 0 then
		for userId in damageByUser do
			shares[userId] = 1 / count
		end
		return shares
	end
	local variable = 1 - floor * count
	for userId, damage in damageByUser do
		shares[userId] = floor + variable * (damage / total)
	end
	return shares
end

-- Mentor bonus: Valor for carrying someone far below your own rate, paid per such member.
function Combat.MentorBonus(
	combatCfg: CombatRules,
	hostRate: number,
	partyRates: { number }
): number
	local coop = combatCfg.coop
	local threshold = hostRate * coop.mentorRatio
	local mentored = 0
	for _, rate in partyRates do
		if rate < threshold then
			mentored += 1
		end
	end
	return mentored * coop.mentorValor
end

-- Time-weighted offline efficiency: the seconds the player spent inside the combat place earn at
-- `expeditionEfficiency`, the rest of the absence at the normal `efficiency`.
function Combat.AwayEfficiency(
	elapsed: number,
	expeditionSeconds: number,
	efficiency: number,
	expeditionEfficiency: number
): number
	if elapsed <= 0 then
		return efficiency
	end
	local away = math.clamp(expeditionSeconds, 0, elapsed)
	local rest = elapsed - away
	return (away * expeditionEfficiency + rest * efficiency) / elapsed
end

-- How fast the party is actually killing, relative to the expected pace: the pacing director
-- merges waves above mergeThreshold and stretches breathers below it. Never raises enemy stats.
function Combat.Tempo(
	killsInWindow: number,
	windowSeconds: number,
	expectedKillsPerSecond: number,
	director: CombatDirectorConfig
): number
	if expectedKillsPerSecond <= 0 or windowSeconds <= 0 then
		return director.tempoMin
	end
	local actual = killsInWindow / windowSeconds
	return math.clamp(actual / expectedKillsPerSecond, director.tempoMin, director.tempoMax)
end

return Combat
