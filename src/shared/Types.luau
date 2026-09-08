--!strict
-- Shared type definitions, frozen in docs/INTERFACES.md (M1 + the M2 amendments). Slot ids
-- stored in PlayerState.slots are persistence keys since M2 and may never be renamed.

export type SlotType = "building" | "unlock" | "decor" | "monument"

export type SlotConfig = {
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

export type EraConfig = {
	eraIndex: number,
	name: string,
	slots: { SlotConfig },
}

export type SlotState = { level: number }

-- Full profile schema v1 (spec §7), persisted via ProfileStore since M2.
export type PlayerState = {
	version: number,
	cash: number,
	era: number,
	rebirthCount: number,
	legacy: number,
	slots: { [string]: SlotState },
	passes: { [string]: boolean },
	processedReceipts: { string },
	lastSeen: number,
	incomeAtSave: number,
	stats: { totalCashAllTime: number, erasCompleted: number, playtimeSeconds: number },
	settings: { music: boolean, sfx: boolean },
}

export type Multipliers = { legacy: number, pass: number, premium: number, neighbors: number }

export type WelcomeBack = { grantedCash: number, elapsedSeconds: number }

export type Snapshot = {
	kind: "snapshot",
	plotIndex: number,
	eraName: string,
	state: PlayerState,
	incomePerSecond: number,
	-- M2: present only on the first snapshot after an offline grant (elapsed >= 60 s).
	welcomeBack: WelcomeBack?,
}

export type Delta = {
	kind: "delta",
	cash: number?,
	incomePerSecond: number?,
	slots: { [string]: SlotState }?,
}

export type ActionResult = {
	-- M2 adds the era actions; for them slotId is "" (no slot involved).
	action: "buy" | "levelUp" | "advanceEra" | "rebirth",
	slotId: string,
	ok: boolean,
	reason: ("insufficientFunds" | "locked" | "invalid")?,
}

-- Game.json v1.3 mirror; field names follow the JSON keys exactly.
export type LevelCostConfig = { factor: number, growth: number, minBase: number }

export type LegacyConfig = {
	incomePerPoint: number,
	gainBase: number,
	gainLevelsDivisor: number,
	gainRebirthBonus: number,
}

export type OfflineConfig = {
	capSeconds: number,
	capSecondsOfflinePro: number,
	efficiency: number,
	efficiencyOfflinePro: number,
	welcomeBackMinSeconds: number,
}

export type NeighborsConfig = { perPlayer: number, maxBonus: number }

export type RemotesConfig = {
	callsPerSecond: number,
	stateDeltaHz: number,
	padTouchDebounce: number,
}

export type DebugConfig = { studioIncomeMultiplier: number, studioFreeBuy: boolean }

export type GameConfig = {
	tickRate: number,
	plotCount: number,
	plotMargin: number,
	hubRadius: number,
	maxLevel: number,
	levelIncomeBonus: number,
	milestoneLevels: { number },
	milestoneMultiplier: number,
	levelCost: LevelCostConfig,
	legacy: LegacyConfig,
	offline: OfflineConfig,
	neighbors: NeighborsConfig,
	remotes: RemotesConfig,
	debug: DebugConfig,
}

-- Era layouts are Luau modules because JSON cannot hold Vector3/Color3 (docs/INTERFACES.md).
export type SlotLayout = {
	position: Vector3,
	rotationY: number,
	padPosition: Vector3?,
}

export type EraLayout = {
	plotSize: Vector3,
	baseColor: Color3,
	padSize: Vector3,
	padOffset: number,
	placeholderSize: Vector3,
	slots: { [string]: SlotLayout },
}

return {}
