--!strict
-- Pure combat math (docs/INTERFACES.md "C0 contracts" → "src/shared/Combat.luau"): wave specs,
-- enemy stats, reward shares, away efficiency and the pacing tempo. No RNG anywhere — every
-- result is a deterministic function of config plus state — and no Roblox globals beyond the
-- `script` needed to require Economy, so tools/sim_combat.py mirrors this file function for
-- function (and imports the sim_economy mirror of Economy for the cash multiplier).

local Economy = require(script.Parent:WaitForChild("Economy"))
-- C1: the hit/ability formulas start from the equipped weapon, and Armory owns that lookup.
-- Armory is pure too, so this is not a cycle and sim_combat.py mirrors both files together.
local Armory = require(script.Parent:WaitForChild("Armory"))

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
	color: { number }?,
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
type BossPatternDef = {
	kind: "slam" | "charge" | "summon",
	cooldown: number,
	windupSeconds: number,
	radius: number?,
	damageMult: number?,
	enemy: string?,
	count: number?,
}
type BossDef = {
	template: string,
	enemy: string,
	hpMult: number,
	damageMult: number,
	cashMult: number,
	materialsMult: number,
	valor: number,
	patterns: { BossPatternDef }?,
}
-- P5: the mission's `crowd` block (Types.MissionCrowdConfig and friends).
type MissionCrowdGroup = {
	kind: string,
	count: number,
	perExtra: number?,
	minDifficulty: string?,
}
type MissionCrowdBoss = { kind: string, at: { number }, valor: number }
type MissionCrowdWave = { groups: { MissionCrowdGroup }, boss: MissionCrowdBoss? }
type MissionCrowdReward = { cash: number, materials: number }
type MissionCrowdConfig = {
	hpScale: number,
	plateScale: number,
	damageScale: number,
	regenShare: number,
	maxAlive: number,
	burst: number,
	burstSpacing: number,
	eliteKind: string?,
	waves: { MissionCrowdWave },
	rewards: { [string]: MissionCrowdReward },
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
	crowd: MissionCrowdConfig?,
}

type CombatCoopConfig = {
	maxParty: number,
	joinUntilWave: number,
	contributionFloor: number,
	countPerExtraPlayer: number,
	mentorRatio: number,
	mentorValor: number,
	bossHpPerExtraPlayer: number,
	mentorMinDamageShare: number,
	inviteSeconds: number,
	inviteCooldownSeconds: number,
	declineBlockSeconds: number,
	lobbyWaitSeconds: number,
	returnGroupSeconds: number,
	reformSeconds: number,
	publicByDefault: boolean,
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

-- Exact structural copies of Armory.luau's own local config types (which are not exported).
-- The old solver compares nested tables invariantly, so every field below must stay in lockstep
-- with Armory.luau AND Types.luau; a mismatch shows up as a type error at the first Armory call.
type BandDef = { band: number, eraName: string, material: string }
type WeaponClassDef = {
	kind: string,
	range: number,
	arcDegrees: number?,
	chain: { number }?,
	windows: { number }?,
	comboReset: number?,
	finisherKnockback: number?,
	fire: string?,
	cooldown: number?,
	chargeSeconds: number?,
	minDamageFraction: number?,
	spreadDegrees: number?,
	pierce: number?,
}
type AbilityDef = {
	kind: string,
	cooldown: number,
	damageMult: number,
	radius: number?,
	shots: number?,
	knockback: number?,
	stunSeconds: number?,
	dashStuds: number?,
	dotSeconds: number?,
	dotTicks: number?,
	pierce: number?,
}
type WeaponStarterDef = {
	name: string,
	class: string,
	damage: number,
	hp: number,
	ability: string,
	model: string,
}
type WeaponTierDef = {
	tier: number,
	band: number,
	cost: number,
	unlockRate: number,
	name: string,
	class: string,
	damage: number,
	hp: number,
	ability: string,
	model: string,
	partyEffect: string?,
}
type ArmorySlotDef = { starter: WeaponStarterDef, tiers: { WeaponTierDef } }
type AscensionLevelDef = {
	level: number,
	materials: { [string]: number },
	valor: number,
	damageMult: number,
	hpMult: number,
	abilityMult: number,
}
type AscensionConfig = {
	requiresRebirth: number,
	levelsPerRebirth: number,
	levels: { AscensionLevelDef },
}
type PartyEffectDef = {
	kind: "rally" | "warcry",
	radius: number,
	healFraction: number?,
	damageMult: number?,
	seconds: number?,
}
type ArmoryConfig = {
	version: number,
	baseHp: number,
	power: { hpWeight: number },
	bands: { BandDef },
	classes: { [string]: WeaponClassDef },
	abilities: { [string]: AbilityDef },
	slots: { [string]: ArmorySlotDef },
	ascension: AscensionConfig,
	partyEffects: { [string]: PartyEffectDef },
}

-- The slices of PlayerState these functions read; callers pass the whole state.
type CombatOwner = { era: number, rebirthCount: number, combat: CombatProfile }
type CashOwner = { legacy: number, legacyShop: LegacyShopState }

-- One kill's unsplit reward (L1b-15: a kill is split and paid as it falls).
export type RewardPool = { cash: number, materials: number, valor: number, kills: number }
export type RewardShare = { cash: number, materials: number, valor: number }
-- Per userId: the fractions SplitCarry has not paid yet, each under 1. Kept for a run.
export type Carry = { [number]: RewardShare }

-- One wave, fully resolved: how many enemies and by how much their stats and rewards are
-- multiplied. `boss` is the entry for this wave when it is a boss wave. `bossHpMult` (C2) is the
-- party-size HP factor that only the boss entity takes; see EnemyStats.
export type WaveSpec = {
	count: number,
	hpMult: number,
	damageMult: number,
	rewardMult: number,
	bossHpMult: number,
	boss: BossDef?,
	weights: { [string]: number },
}

export type EnemyStats = { hp: number, damage: number, cash: number, materials: number }

-- P5: one crowd wave, fully resolved (docs/INTERFACES.md "P5 contracts" → "Server modules").
-- `groups` counts are already scaled for party size and Overdrive; `total` leaves the boss out.
-- The scales multiply ProvingGrounds.json's tier-1 kind numbers.
export type CrowdWaveSpec = {
	wave: number,
	groups: { { kind: string, count: number } },
	total: number,
	boss: MissionCrowdBoss?,
	bossHpMult: number,
	hpScale: number,
	plateScale: number,
	damageScale: number,
	regenShare: number,
	rewardMult: number,
}

-- L1: what a difficulty (or, for the arena adapter, the mission's own block) scales a camp by.
-- A structural slice of Types.LevelDifficulty: a whole one may be passed.
export type CampScales = {
	hpScale: number,
	damageScale: number,
	plateScale: number,
	countMult: number,
	rewardMult: number,
}

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

-- Party size scales COUNT for ordinary enemies (never their HP or damage): more players must not
-- make each raider tankier. Overdrive is the only thing that raises hp/damage across the board.
-- C2 (Ben's ruling): the ONE boss entity is the exception, because a boss that melts in seconds
-- under four players is no boss. tools/sim_combat.py mirrors this exactly:
--   extras     = max(partySize, 1) - 1
--   bossHpMult = 1 + coop.bossHpPerExtraPlayer * extras
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
		bossHpMult = 1 + combatCfg.coop.bossHpPerExtraPlayer * extras,
		boss = mission.bosses[tostring(wave)],
		weights = weightsForWave(mission, wave),
	}
end

-- Cash and materials are FIXED per enemy (no RNG, no loot tables): the wave multipliers are the
-- only thing that moves them. The boss multipliers ride on the ONE entity the spawner marks with
-- `isBoss` -- never on the ordinary enemies of the same key, which would have turned every brute
-- in Village wave 10 into a Warlord (the sim measured 7:58 -> 10:37). nil for an unknown key.
-- C2: the boss entity's HP also takes spec.bossHpMult, applied AFTER the boss and Overdrive
-- multipliers and before the single rounding:
--   hp = round(enemy.hp * spec.hpMult * boss.hpMult * spec.bossHpMult)   -- boss entity
--   hp = round(enemy.hp * spec.hpMult)                                   -- everything else
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
	local partyHp = if applyBoss then spec.bossHpMult else NEUTRAL_MULT
	return {
		hp = math.round(enemy.hp * spec.hpMult * bossHp * partyHp),
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

-- ---------------------------------------------------------------------------------------------
-- C1: wave shaping and hit math. Still no RNG: every spawn order, interval and damage number is
-- a function of config, wave and the profile, so tools/sim_combat.py reproduces a run exactly.
-- ---------------------------------------------------------------------------------------------

-- Deterministic largest-remainder allocation, then an interleave. The alternative (rolling a
-- weighted die per spawn) would make two identical runs differ and the sim untrustworthy.
-- Ties break on the key name ascending, which is why every loop below sorts first.
function Combat.WaveComposition(count: number, weights: { [string]: number }): { string }
	local keys: { string } = {}
	local total = 0
	for key, weight in weights do
		if weight > 0 then
			table.insert(keys, key)
			total += weight
		end
	end
	if count <= 0 or total <= 0 or #keys == 0 then
		return {}
	end
	table.sort(keys)

	local quota: { [string]: number } = {}
	local fraction: { [string]: number } = {}
	local assigned = 0
	for _, key in keys do
		local exact = count * weights[key] / total
		local whole = math.floor(exact)
		quota[key] = whole
		fraction[key] = exact - whole
		assigned += whole
	end
	-- Largest remainders take the rounding leftovers.
	local byFraction = table.clone(keys)
	table.sort(byFraction, function(a: string, b: string): boolean
		if fraction[a] == fraction[b] then
			return a < b
		end
		return fraction[a] > fraction[b]
	end)
	local leftover = count - assigned
	local index = 1
	while leftover > 0 do
		local key = byFraction[index]
		quota[key] += 1
		leftover -= 1
		index += 1
		if index > #byFraction then
			index = 1
		end
	end

	-- Interleave: always place the key that is furthest behind its own quota, so a 70/30 wave
	-- arrives mixed instead of as two blocks.
	local placed: { [string]: number } = {}
	for _, key in keys do
		placed[key] = 0
	end
	local order: { string } = {}
	for _ = 1, count do
		local bestKey: string? = nil
		local bestRatio = math.huge
		for _, key in keys do
			local target = quota[key]
			if target > 0 and placed[key] < target then
				local ratio = placed[key] / target
				if ratio < bestRatio then
					bestRatio = ratio
					bestKey = key
				end
			end
		end
		if bestKey == nil then
			break
		end
		placed[bestKey] += 1
		table.insert(order, bestKey)
	end
	return order
end

-- Seconds between two spawns of the same wave: the whole wave is meant to land inside
-- targetWaveSeconds, and a party killing fast (tempo > 1) gets it sooner.
function Combat.SpawnInterval(
	mission: MissionConfig,
	spec: WaveSpec,
	tempo: number,
	overdrive: boolean,
	combatCfg: CombatRules
): number
	if spec.count <= 0 or tempo <= 0 then
		return mission.targetWaveSeconds
	end
	local rateMult = if overdrive then combatCfg.overdrive.spawnRateMult else NEUTRAL_MULT
	return mission.targetWaveSeconds / spec.count / tempo / rateMult
end

-- The breather stretches when the party is struggling (tempo at tempoMin) and shrinks to the
-- floor when they are ahead: the director only ever changes PACING, never enemy stats.
function Combat.BreatherSeconds(tempo: number, director: CombatDirectorConfig): number
	local span = 1 - director.tempoMin
	local slowness = if span > 0 then math.clamp((1 - tempo) / span, 0, 1) else 0
	return director.breatherSeconds
		+ (director.breatherMaxSeconds - director.breatherSeconds) * slowness
end

-- Merge the next wave into this one: only when the party is both fast AND has already cleared
-- most of what is on the field, so a merge never piles onto a party that is behind.
function Combat.ShouldMerge(
	tempo: number,
	deadFraction: number,
	director: CombatDirectorConfig
): boolean
	return tempo >= director.mergeTempo and deadFraction >= director.mergeThreshold
end

local function gearTier(state: CombatOwner, slot: string): number
	if slot == "ranged" then
		return state.combat.gear.ranged
	end
	return state.combat.gear.melee
end

local function ascensionTier(state: CombatOwner, slot: string): number
	if slot == "ranged" then
		return state.combat.ascension.ranged
	end
	return state.combat.ascension.melee
end

-- Step is 1..3 of the melee chain; the class's chain multiplier is the whole difference between
-- a normal hit and the finisher (chain[3] = 1.6 in Armory.json), so no extra finisher factor.
function Combat.MeleeDamage(cfg: ArmoryConfig, state: CombatOwner, step: number): number
	local tier = gearTier(state, "melee")
	local def = Armory.TierDef(cfg, "melee", tier)
	if def == nil then
		return 0
	end
	local class = Armory.ClassDef(cfg, def.class)
	local chain = if class ~= nil then class.chain else nil
	local stepMult = if chain ~= nil and chain[step] ~= nil then chain[step] else NEUTRAL_MULT
	return Armory.WeaponDamage(cfg, "melee", tier, ascensionTier(state, "melee")) * stepMult
end

-- `charge` is the SERVER's clamped draw fraction (elapsed / chargeSeconds), never the client's
-- claim. Non-charge families ignore it entirely.
function Combat.RangedDamage(cfg: ArmoryConfig, state: CombatOwner, charge: number): number
	local tier = gearTier(state, "ranged")
	local def = Armory.TierDef(cfg, "ranged", tier)
	if def == nil then
		return 0
	end
	local base = Armory.WeaponDamage(cfg, "ranged", tier, ascensionTier(state, "ranged"))
	local class = Armory.ClassDef(cfg, def.class)
	if class == nil or class.fire ~= "charge" then
		return base
	end
	local floorFraction = class.minDamageFraction or 0
	return base * (floorFraction + (1 - floorFraction) * math.clamp(charge, 0, 1))
end

local function slotAbility(cfg: ArmoryConfig, state: CombatOwner, slot: string): AbilityDef?
	local def = Armory.TierDef(cfg, slot, gearTier(state, slot))
	if def == nil or def.ability == "" then
		return nil
	end
	return Armory.AbilityDef(cfg, def.ability)
end

-- Ascension scales abilities on its own curve (abilityMult), which is why this is not simply
-- WeaponDamage x damageMult.
function Combat.AbilityDamage(cfg: ArmoryConfig, state: CombatOwner, slot: string): number
	local ability = slotAbility(cfg, state, slot)
	if ability == nil then
		return 0
	end
	local ascLevel = ascensionTier(state, slot)
	local levelDef = if ascLevel > 0 then cfg.ascension.levels[ascLevel] else nil
	local ascMult = if levelDef ~= nil then levelDef.abilityMult else NEUTRAL_MULT
	local base = Armory.WeaponDamage(cfg, slot, gearTier(state, slot), ascLevel)
	return base * ability.damageMult * ascMult
end

-- 0 for a weapon with no ability: the caller reads that as "nothing to fire", never as "ready".
function Combat.AbilityCooldown(cfg: ArmoryConfig, state: CombatOwner, slot: string): number
	local ability = slotAbility(cfg, state, slot)
	if ability == nil then
		return 0
	end
	return ability.cooldown
end

-- L1b-15: what a kill pays is split the moment it falls, so a share is often a fraction of a
-- unit (a party of two splits a slinger's 1 Timber 0.9 / 0.1). Each member is paid the whole
-- units of their share and keeps the fraction in their carry, which is added to their next
-- credit: over a run nobody loses a fraction, and nobody is paid more than the pools held.
-- `cashMults[userId]` (CombatCashMult; nil = 1) multiplies cash inside the carry, so it is
-- floored once. A share that is not a finite number of at least 0 pays nothing and leaves that
-- member's carry as it was; a member not in `shares` keeps theirs. Mutates `carry`.
local function whole(exact: number): (number, number)
	local paid = math.floor(exact + 1e-9)
	return paid, math.max(exact - paid, 0)
end

function Combat.SplitCarry(
	pool: RewardPool,
	shares: { [number]: number },
	carry: Carry,
	cashMults: { [number]: number }?
): { [number]: RewardShare }
	local split: { [number]: RewardShare } = {}
	for userId, share in shares do
		if not (share >= 0 and share < math.huge) then
			continue
		end
		local held = carry[userId]
		if held == nil then
			held = { cash = 0, materials = 0, valor = 0 }
			carry[userId] = held
		end
		local mult = if cashMults ~= nil then cashMults[userId] or NEUTRAL_MULT else NEUTRAL_MULT
		local cash, cashLeft = whole(pool.cash * share * mult + held.cash)
		local materials, materialsLeft = whole(pool.materials * share + held.materials)
		local valor, valorLeft = whole(pool.valor * share + held.valor)
		held.cash = cashLeft
		held.materials = materialsLeft
		held.valor = valorLeft
		split[userId] = { cash = cash, materials = materials, valor = valor }
	end
	return split
end

-- ---------------------------------------------------------------------------------------------
-- P5: crowd missions. Party size scales the counts of the ordinary groups and the boss body's
-- HP only (the C2 rule); Overdrive scales counts, HP, damage and rewards, never plates or regen.
-- L1: the three rules below (CampWave, CampReward, BurstSeconds) are the ones a run reads; a
-- level's camp passes its difficulty's scales. CrowdWave, CrowdReward and BurstInterval are the
-- mission-shaped callers kept for the simulator's assertions, and give the same numbers.
-- tools/sim_combat.py mirrors all six exactly.
-- ---------------------------------------------------------------------------------------------

-- One wave of a camp, resolved for a difficulty and a party. `rank` is the played difficulty's
-- place in Expeditions.json `difficulties` and `ranks` every difficulty's: a group is fielded
-- when it names no minDifficulty, or one at or under the played rank (an unknown name fields
-- nothing). `wave` is 0 here: the caller numbers it.
--   count = max(round(count * (1 + (perExtra or coop.countPerExtraPlayer) * extras) * countMult), 0)
function Combat.CampWave(
	waveDef: MissionCrowdWave,
	regenShare: number,
	scales: CampScales,
	rank: number,
	ranks: { [string]: number },
	partySize: number,
	combatCfg: CombatRules
): CrowdWaveSpec
	local extras = math.max(partySize, 1) - 1
	local groups: { { kind: string, count: number } } = {}
	local total = 0
	for _, group in waveDef.groups do
		local needs = group.minDifficulty
		local needsRank = if needs ~= nil then ranks[needs] else nil
		if needs ~= nil and (needsRank == nil or needsRank > rank) then
			continue
		end
		local perExtra = group.perExtra or combatCfg.coop.countPerExtraPlayer
		local count =
			math.max(math.round(group.count * (1 + perExtra * extras) * scales.countMult), 0)
		table.insert(groups, { kind = group.kind, count = count })
		total += count
	end
	return {
		wave = 0,
		groups = groups,
		total = total,
		boss = waveDef.boss,
		bossHpMult = 1 + combatCfg.coop.bossHpPerExtraPlayer * extras,
		hpScale = scales.hpScale,
		plateScale = scales.plateScale,
		damageScale = scales.damageScale,
		regenShare = regenShare,
		rewardMult = scales.rewardMult,
	}
end

-- L1b-15: fixed cash and materials for one kill of `kind` at a difficulty's `rewardMult`,
-- rounded to the nearest; a kind with no rewards entry pays nothing.
function Combat.KillReward(
	rewards: { [string]: MissionCrowdReward },
	kind: string,
	rewardMult: number
): (number, number)
	local reward = rewards[kind]
	if reward == nil then
		return 0, 0
	end
	return math.round(reward.cash * rewardMult), math.round(reward.materials * rewardMult)
end

-- KillReward at the spec's rewardMult (the mission-shaped callers' form).
function Combat.CampReward(
	rewards: { [string]: MissionCrowdReward },
	kind: string,
	spec: CrowdWaveSpec
): (number, number)
	return Combat.KillReward(rewards, kind, spec.rewardMult)
end

-- Seconds between two bursts of the same wave: the whole wave is meant to land inside
-- targetWaveSeconds, and a party killing fast (tempo > 1) gets it sooner.
function Combat.BurstSeconds(targetWaveSeconds: number, bursts: number, tempo: number): number
	if bursts <= 0 or tempo <= 0 then
		return targetWaveSeconds
	end
	return targetWaveSeconds / bursts / tempo
end

-- nil when the mission has no `crowd` block or no such wave.
function Combat.CrowdWave(
	mission: MissionConfig,
	wave: number,
	partySize: number,
	overdrive: boolean,
	combatCfg: CombatRules
): CrowdWaveSpec?
	local crowd = mission.crowd
	if crowd == nil then
		return nil
	end
	local waveDef = crowd.waves[wave]
	if waveDef == nil then
		return nil
	end
	local overdriveCfg = combatCfg.overdrive
	local spec = Combat.CampWave(waveDef, crowd.regenShare, {
		hpScale = crowd.hpScale * (if overdrive then overdriveCfg.hpMult else NEUTRAL_MULT),
		damageScale = crowd.damageScale
			* (if overdrive then overdriveCfg.damageMult else NEUTRAL_MULT),
		plateScale = crowd.plateScale,
		countMult = if overdrive then overdriveCfg.countMult else NEUTRAL_MULT,
		rewardMult = if overdrive then overdriveCfg.rewardMult else NEUTRAL_MULT,
	}, 0, {}, partySize, combatCfg)
	spec.wave = wave
	return spec
end

function Combat.CrowdReward(
	mission: MissionConfig,
	kind: string,
	spec: CrowdWaveSpec
): (number, number)
	local crowd = mission.crowd
	if crowd == nil then
		return 0, 0
	end
	return Combat.CampReward(crowd.rewards, kind, spec)
end

-- BurstSeconds, faster under Overdrive.
function Combat.BurstInterval(
	mission: MissionConfig,
	bursts: number,
	tempo: number,
	overdrive: boolean,
	combatCfg: CombatRules
): number
	local seconds = Combat.BurstSeconds(mission.targetWaveSeconds, bursts, tempo)
	if bursts <= 0 or tempo <= 0 then
		return seconds
	end
	local rateMult = if overdrive then combatCfg.overdrive.spawnRateMult else NEUTRAL_MULT
	return seconds / rateMult
end

return Combat
