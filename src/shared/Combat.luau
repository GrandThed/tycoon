--!strict
-- Pure combat math (docs/INTERFACES.md "C0 contracts" → "src/shared/Combat.luau"): a camp's
-- waves and rewards, reward shares, away efficiency and the pacing tempo. No RNG anywhere — every
-- result is a deterministic function of config plus state — and no Roblox globals beyond the
-- `script` needed to require Economy, so tools/sim_combat.py mirrors this file function for
-- function (and imports the sim_economy mirror of Economy for the cash multiplier).
-- L4 W1b deleted C1's wave, enemy and hit math with the services that read it.

local Economy = require(script.Parent:WaitForChild("Economy"))

-- Structural copies of the shapes in Types.luau: requiring Types would need more than `script`
-- provides for a pure module, and the old solver compares nested tables invariantly, so every
-- field below must stay in lockstep with Types.luau.
type MissionRecord = { bestWave: number, bossClears: number, overdriveBest: number }
type SavedLoadout = { melee: string?, ranged: string?, variants: { [string]: string } }
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
	abilities: { [string]: boolean }?,
	secrets: { [string]: { [string]: boolean } }?,
	families: { [string]: boolean }?,
	shortcuts: { [string]: { [string]: boolean } }?,
	tiers: { [string]: number }?,
	loadout: SavedLoadout?,
	stars: { [string]: { [string]: boolean } }?,
}

-- A level's camp waves and rewards (Types.MissionCrowdGroup and friends).
type MissionCrowdGroup = {
	kind: string,
	count: number,
	perExtra: number?,
	minDifficulty: string?,
}
type MissionCrowdBoss = { kind: string, at: { number }, valor: number }
type MissionCrowdWave = { groups: { MissionCrowdGroup }, boss: MissionCrowdBoss? }
type MissionCrowdReward = { cash: number, materials: number }

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
-- L4 W3 (L4W3-7): Combat.json `rewards`.
type CombatRewardsConfig = { eraCashMult: { number } }
type CombatDirectorConfig = {
	windowSeconds: number,
	tempoMin: number,
	tempoMax: number,
	mergeThreshold: number,
	mergeTempo: number,
	eliteTempo: number,
	breatherSeconds: number,
	breatherMaxSeconds: number,
	runCapSeconds: number,
}
-- The Combat.json block these functions read; callers pass the whole Types.CombatConfig.
type CombatRules = { coop: CombatCoopConfig }

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
type CombatOwner = { era: number, combat: CombatProfile }
type CashOwner = { legacy: number, legacyShop: LegacyShopState }

-- One kill's unsplit reward (L1b-15: a kill is split and paid as it falls).
export type RewardPool = { cash: number, materials: number, valor: number, kills: number }
export type RewardShare = { cash: number, materials: number, valor: number }
-- Per userId: the fractions SplitCarry has not paid yet, each under 1. Kept for a run.
export type Carry = { [number]: RewardShare }

-- P5: one crowd wave, fully resolved (docs/INTERFACES.md "P5 contracts" → "Server modules").
-- `groups` counts are already scaled for party size and the difficulty; `total` leaves the boss
-- out. The scales multiply ProvingGrounds.json's tier-1 kind numbers.
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

-- L1: what a difficulty scales a camp by. A structural slice of Types.LevelDifficulty: a whole
-- one may be passed.
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

-- L4 W3 (L4W3-7, Ben's pick: docs/prompts/l4-w3-cash-study.md (c) at M = 3): a city era's run
-- cash factor, `rewards.eraCashMult[era]`. An era past the list takes the last entry and one under
-- 1 the first. No block, a list that is not a table (an empty one has no entry), an era that is
-- not a finite number or an entry that is not a finite number of at least 1 all read 1: a config
-- fault degrades to today's pay, never to an error or to a run that pays nothing.
function Combat.EraCashMult(rewards: CombatRewardsConfig?, era: number): number
	local list: any = if rewards ~= nil then rewards.eraCashMult else nil
	if type(list) ~= "table" then
		return NEUTRAL_MULT
	end
	if type(era) ~= "number" or era ~= era or era == math.huge or era == -math.huge then
		return NEUTRAL_MULT
	end
	local entry: any = list[math.min(math.max(math.floor(era), 1), #list)]
	if type(entry) ~= "number" or entry ~= entry or entry == math.huge or entry < 1 then
		return NEUTRAL_MULT
	end
	return entry
end

-- Combat cash carries the PERMANENT city multipliers only (Legacy and Founder's Blessing).
-- Deliberately not the passes, Premium or the neighbors bonus: those are the city's idle
-- economy, and paying them on kills would price expeditions against the wrong curve. L4 W3: times
-- the member's own era factor (EraCashMult), so a clear stays a few minutes of the new era's
-- income right after each Advance; Legacy and Founder's stay on top of it.
function Combat.CombatCashMult(
	state: CashOwner,
	gameConfig: GameConfig,
	shopConfig: LegacyShopConfig,
	rewards: CombatRewardsConfig?,
	era: number
): number
	return Economy.LegacyMult(state.legacy, gameConfig)
		* Economy.PerkIncomeMult(shopConfig, state.legacyShop)
		* Combat.EraCashMult(rewards, era)
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
-- P5, L1: a level's camps. Party size scales the counts of the ordinary groups and the boss
-- body's HP only (the C2 rule); a camp's difficulty passes its scales. tools/sim_combat.py
-- mirrors every rule below exactly.
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

-- L1b-W2-21: a camp's clear bonus, `share` of what its whole `stock` (bodies by kind) pays at
-- the difficulty's price: KillReward per kind, so a kind with no rewards entry adds nothing.
-- Rounded once, at the end. A share of 0 or an empty stock pays 0, 0.
function Combat.ClearBonus(
	stock: { [string]: number },
	rewards: { [string]: MissionCrowdReward },
	rewardMult: number,
	share: number
): (number, number)
	local cash = 0
	local materials = 0
	for kind, count in stock do
		local each, eachMaterials = Combat.KillReward(rewards, kind, rewardMult)
		cash += count * each
		materials += count * eachMaterials
	end
	return math.round(share * cash), math.round(share * materials)
end

-- L1b-W2-21: what a wave queued, added to a locking camp's `stock` by kind: every group of
-- `spec`, and the director's extra elite when it took one. Never the boss or its calls.
function Combat.WaveStock(stock: { [string]: number }, spec: CrowdWaveSpec, elite: string?): ()
	for _, group in spec.groups do
		stock[group.kind] = (stock[group.kind] or 0) + group.count
	end
	if elite ~= nil then
		stock[elite] = (stock[elite] or 0) + 1
	end
end

-- L1b-W2-26: the merge test's dead fraction counts only the bodies the waves queued:
-- `queuedAlive` is the floor's living bodies less those that belong to a group (residents, a
-- tent's). 0 when nothing was spawned; never under 0 or over 1.
function Combat.DeadFraction(spawned: number, queuedAlive: number): number
	if spawned <= 0 then
		return 0
	end
	return math.min(math.max((spawned - math.max(queuedAlive, 0)) / spawned, 0), 1)
end

-- Seconds between two bursts of the same wave: the whole wave is meant to land inside
-- targetWaveSeconds, and a party killing fast (tempo > 1) gets it sooner.
function Combat.BurstSeconds(targetWaveSeconds: number, bursts: number, tempo: number): number
	if bursts <= 0 or tempo <= 0 then
		return targetWaveSeconds
	end
	return targetWaveSeconds / bursts / tempo
end

return Combat
