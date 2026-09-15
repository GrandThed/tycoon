--!strict
-- Shared type definitions, frozen in docs/INTERFACES.md (M1 + the M2/M3 amendments). Slot ids
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
	-- M3 (schema v1.1): Kenney kit for the asset manifest only; Luau never reads it. Optional
	-- in the type so pre-v1.1 configs still typecheck; the generator's --check requires it.
	kit: string?,
}

export type EraConfig = {
	eraIndex: number,
	name: string,
	-- M3: human copy (spaces allowed); `name` stays the module/folder key.
	displayName: string,
	slots: { SlotConfig },
}

export type SlotState = { level: number }

-- Full profile schema (spec §7 v1 + the M5 v2 field), persisted via ProfileStore since M2.
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
	-- M5 (schema v2): the DoubleOffline amount a still-open purchase dialog is for, so a
	-- receipt delivered in a later session (player left with the dialog up) still grants it.
	-- 0 means "no reservation".
	pendingDoubleOfflineAmount: number,
	-- M6 (schema v3): Legacy shop purchases. `spent` is Legacy invested (never deducted from
	-- `legacy` itself — the multiplier keeps counting it); perks maps perkId -> tier owned.
	legacyShop: LegacyShopState,
}

-- M6 Legacy shop (docs/INTERFACES.md "M6 contracts"). LegacyShop.json v1 mirror; perk ids are
-- persistence keys (state.legacyShop.perks) and may never be renamed.
export type PerkEffect =
	"incomeMult"
	| "levelCostDiscount"
	| "startingSlots"
	| "levelFloor"
	| "extraMilestone"
	| "neighbours"
	| "offlineCapSeconds"
	| "cosmetic"
-- `value` is the TOTAL effect once the tier is owned, never a per-tier increment.
export type PerkTier = { cost: number, value: number, maxBonus: number? }
export type PerkDef = {
	id: string,
	name: string,
	description: string,
	cosmetic: boolean,
	effect: PerkEffect,
	tiers: { PerkTier },
	-- Cosmetic extras: signTitle carries titles (indexed by min(rebirthCount + 1, #titles));
	-- nameTagColour and goldenRoads carry a "#RRGGBB" colour.
	titles: { string }?,
	color: string?,
}
export type LegacyShopConfig = { version: number, perks: { PerkDef } }
export type LegacyShopState = { spent: number, perks: { [string]: number } }

-- perk: Founder's Blessing (1 when none). Legacy/pass/premium/neighbors as before.
export type Multipliers = {
	legacy: number,
	perk: number,
	pass: number,
	premium: number,
	neighbors: number,
}

export type WelcomeBack = { grantedCash: number, elapsedSeconds: number }

export type Snapshot = {
	kind: "snapshot",
	plotIndex: number,
	eraName: string,
	state: PlayerState,
	incomePerSecond: number,
	-- M4 (wave 2): the persisted rate — no Studio debug multiplier, neighbors pinned to 1 — is
	-- what the server prices cash packs with, so the shop previews grants against THIS and
	-- never reconstructs it client-side. Always present on a snapshot.
	persistedIncomePerSecond: number,
	-- M2: present only on the first snapshot after an offline grant (elapsed >= 60 s).
	welcomeBack: WelcomeBack?,
}

export type Delta = {
	kind: "delta",
	cash: number?,
	incomePerSecond: number?,
	-- M4 (wave 2): emitted alongside incomePerSecond whenever the income flag flushes.
	persistedIncomePerSecond: number?,
	slots: { [string]: SlotState }?,
	-- M3: the whole settings table whenever a RequestSetSetting write lands.
	settings: { music: boolean, sfx: boolean }?,
	-- M6: the whole shop state whenever the legacyShop dirty flag flushes (a copy, never aliased).
	legacyShop: LegacyShopState?,
}

-- M5: sent on StateChanged while a player has no loaded state (safe mode), so the client can
-- show a loading/failed card instead of booting blank. Never sent once a snapshot exists.
export type LoadStatus = {
	kind: "loadStatus",
	phase: "loading" | "failed",
	-- 1-based count of load attempts this session, retries included.
	attempt: number,
	-- Seconds until RequestRetryLoad is honored; 0 = now. Always 0 while loading.
	retryAvailableIn: number,
}
-- The StateChanged payload union is Snapshot | Delta | LoadStatus, discriminated by `kind`.

export type ActionResult = {
	-- M2 adds the era actions; for them slotId is "" (no slot involved). M6 adds buyPerk, for
	-- which slotId carries the perkId (locked = not the next tier / no such perk).
	action: "buy" | "levelUp" | "advanceEra" | "rebirth" | "buyPerk",
	slotId: string,
	ok: boolean,
	reason: ("insufficientFunds" | "locked" | "invalid")?,
}

-- M3 presentation events (server → client, owner only, never on bulk restore), discriminated
-- by `kind`. milestone is true iff a milestoneLevels entry lies in (fromLevel, toLevel].
export type FxReveal = { kind: "reveal", slotId: string, slotType: SlotType, modelName: string }
export type FxLevelUp = {
	kind: "levelUp",
	slotId: string,
	fromLevel: number,
	toLevel: number,
	milestone: boolean,
}
export type FxEraAdvance = {
	kind: "eraAdvance",
	fromEra: number,
	toEra: number,
	legacyGained: number,
}
export type FxRebirth = {
	kind: "rebirth",
	fromEra: number,
	toEra: number,
	legacyGained: number,
	rebirthCount: number,
}
-- M4 monetization events. purchase carries the server-computed grant (packs are capped, so
-- the client can never derive it); passGranted fires the moment a pass applies mid-session.
export type FxPurchase = { kind: "purchase", productKey: string, grantedCash: number }
export type FxPassGranted = { kind: "passGranted", passKey: string }
-- M6: a Legacy shop tier just bought (earned currency, no Robux anywhere near it).
export type FxPerkBought = { kind: "perkBought", perkId: string, tier: number }
-- M7: a building's visible stage just changed on a base-milestone crossing. `stage` is the
-- Stage<n> now shown (0-4); it trails PlotService.stageForLevel when a template lacks a stage.
export type FxStageUp = { kind: "stageUp", slotId: string, stage: number }
export type FxEvent =
	FxReveal
	| FxLevelUp
	| FxEraAdvance
	| FxRebirth
	| FxPurchase
	| FxPassGranted
	| FxPerkBought
	| FxStageUp

-- Monetization.json v1 mirror; field names follow the JSON keys exactly. PassKey/ProductKey
-- are persistence keys (state.passes) and analytics SKUs — never rename them. The def tables
-- keep `key: string` because they are decoded from JSON, which Luau cannot narrow to a union.
export type PassKey = "DoubleCash" | "OfflinePro" | "VIP"
export type ProductKey = "Cash30m" | "Cash2h" | "Cash8h" | "DoubleOffline"

export type PassDef = { key: string, id: number, name: string, description: string }

export type ProductDef = {
	key: string,
	id: number,
	name: string,
	description: string,
	-- Cash packs only: minutes of current income the pack is priced in. DoubleOffline has none.
	minutes: number?,
	-- Cash packs only: this pack's own anti-skip ceiling, as a fraction of the era's total slot
	-- cost. Absent ⇒ the config-wide packCapFractionOfEraSlotCost. Per-pack because one global
	-- cap made every pack converge on the same grant past the first fifth of an era, so the
	-- expensive packs delivered exactly what the cheapest one buys (docs/INTERFACES.md M4).
	capFraction: number?,
	shopVisible: boolean,
}

export type MonetizationMultipliers = { doubleCash: number, vip: number, premium: number }

export type MonetizationConfig = {
	version: number,
	multipliers: MonetizationMultipliers,
	packCapFractionOfEraSlotCost: number,
	receiptHistoryLimit: number,
	passes: { PassDef },
	products: { ProductDef },
}

-- RequestSetSetting keys; anything else is dropped by the remote validator.
export type SettingKey = "music" | "sfx"

-- Sounds.json v1 mirror; field names follow the JSON keys exactly.
export type SoundGroupName = "SFX" | "Music" | "UI"
export type SoundDef = {
	id: number,
	group: SoundGroupName,
	volume: number,
	pitchPerMilestone: number?,
}
export type SoundsConfig = {
	version: number,
	groups: { [string]: number },
	sounds: { [string]: SoundDef },
	ambient: { [string]: SoundDef },
}

-- Assets.json v1 mirror (M7; docs/INTERFACES.md "Assets.json — schema v1"), generated by the
-- asset pipeline and optional at runtime. Field names follow the JSON keys exactly; ids of 0
-- mean "not yet" and never error; sizes and offsets are studs. Kit names key `textures` and
-- name each template MeshPart, which is how the VIP texture swap finds its image.
export type AssetPart = {
	kit: string,
	meshId: number,
	imageId: number,
	size: { number },
	offset: { number },
}
export type AssetStage = { modelAssetId: number, parts: { AssetPart } }
export type AssetTexture = { vipSwatchAssetId: number, vipImageId: number }
-- 5 stages for `building` slots, 1 otherwise; keyed by modelName under the era name.
export type AssetModel = { stages: { AssetStage } }
export type AssetsConfig = {
	version: number,
	textures: { [string]: AssetTexture },
	eras: { [string]: { [string]: AssetModel } },
}

-- Game.json v1.3 mirror; field names follow the JSON keys exactly.
export type LevelCostConfig = { factor: number, growth: number, minBase: number }

export type LegacyConfig = {
	incomePerPoint: number,
	gainBase: number,
	gainLevelsDivisor: number,
	gainRebirthBonus: number,
	-- v1.6: Legacy past this point counts logarithmically toward the multiplier. Optional so an
	-- older Game.json still typechecks and behaves linearly.
	softcap: number?,
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
	-- v1.4: RequestPrompt opens a modal OS dialog, so it gets its own much tighter budget.
	promptCallsPerSecond: number,
	-- v1.5: RequestSnapshot answers with a full state snapshot, the most expensive reply the
	-- server makes, so it does not share the gameplay budget.
	snapshotCallsPerSecond: number,
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
