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
	-- M9 wave 1e: the slot's visual IS the street (a surface swap drawn by the client), so the
	-- server spawns only an empty Building_<id> marker instead of modelName.
	streetOnly: boolean?,
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
	settings: { music: boolean, sfx: boolean, vipSkins: boolean, cityDetail: boolean },
	-- M5 (schema v2): the DoubleOffline amount a still-open purchase dialog is for, so a
	-- receipt delivered in a later session (player left with the dialog up) still grants it.
	-- 0 means "no reservation".
	pendingDoubleOfflineAmount: number,
	-- M6 (schema v3): Legacy shop purchases. `spent` is Legacy invested (never deducted from
	-- `legacy` itself — the multiplier keeps counting it); perks maps perkId -> tier owned.
	legacyShop: LegacyShopState,
	-- C0 (schema v5): the Expeditions profile — Armory gear, materials, Valor, mission records.
	-- Shared by both places (one ProfileStore key), so the combat place writes it directly.
	combat: CombatProfile,
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
	-- C0: server-computed Armory.GearPower (0 when Armory.json is absent), so the Power readout
	-- never re-derives it from the profile.
	gearPower: number,
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
	settings: { music: boolean, sfx: boolean, vipSkins: boolean, cityDetail: boolean }?,
	-- M6: the whole shop state whenever the legacyShop dirty flag flushes (a copy, never aliased).
	legacyShop: LegacyShopState?,
	-- C0: the whole combat profile whenever the combat dirty flag flushes (a deep copy, never
	-- aliased), with the recomputed Gear Power alongside it.
	combat: CombatProfile?,
	gearPower: number?,
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
	-- which slotId carries the perkId (locked = not the next tier / no such perk). C0 adds the
	-- four combat actions; their slotId carries the weapon slot ("melee"/"ranged"), the mission
	-- id, or the host userId as a string.
	action: "buy"
		| "levelUp"
		| "advanceEra"
		| "rebirth"
		| "buyPerk"
		| "buyGear"
		| "ascend"
		| "expedition"
		| "joinRun"
		| "party",
	slotId: string,
	ok: boolean,
	-- C0 adds `unavailable`: place id 0, Studio, a teleport that failed after its retries, or a
	-- run that is full or gone. insufficientFunds = materials/Valor short; locked = income/s
	-- below the unlockRate, the Ascension cap, or a mission era above highestEra.
	-- C2 (slotId = the other player's userId as a string for "party"): full = party or run at
	-- maxParty; over = run past joinUntilWave or ended; busy = invitee already in a party or
	-- departing; expired = invite timed out or withdrawn; notLeader = only the leader may do that.
	reason: (
		"insufficientFunds"
		| "locked"
		| "invalid"
		| "unavailable"
		| "full"
		| "over"
		| "busy"
		| "expired"
		| "notLeader"
	)?,
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
export type SettingKey = "music" | "sfx" | "vipSkins" | "cityDetail"

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
-- One baked path mesh (fill or rim) and one era's set, keyed by pieceId ("L<polyline>_<stretch>"
-- or "SP_<slotId>"); `tileStuds` is the world-planar UV tile the bake used.
export type AssetPathMesh = {
	assetId: number,
	meshId: number,
	size: { number },
	offset: { number },
}
export type AssetPathPiece = { fill: AssetPathMesh, rim: AssetPathMesh }
-- The *AssetId / *Sha256 keys are the uploader's bookkeeping (Decal id, idempotency hash).
export type AssetPathVariant = {
	fillAssetId: number,
	fillImageId: number,
	fillSha256: string,
	rimAssetId: number,
	rimImageId: number,
	rimSha256: string,
}
export type AssetPathsEra = {
	tileStuds: number,
	fillImageId: number,
	rimImageId: number,
	pieces: { [string]: AssetPathPiece },
	-- Wave 1e: extra surface textures by variant name; ids of 0 mean "not yet" (default look).
	variants: { [string]: AssetPathVariant }?,
}
export type AssetsConfig = {
	version: number,
	textures: { [string]: AssetTexture },
	eras: { [string]: { [string]: AssetModel } },
	-- v2 (M9): city-dressing props by era, then prop name; absent in v1 files.
	props: { [string]: { [string]: AssetModel } }?,
	-- v3 (M9 wave 1d): baked path meshes by era (optional, additive). The client never reads the
	-- ids -- it clones the generated templates -- but the preloader warms them, and an era with no
	-- entry simply has nothing to warm.
	paths: { [string]: AssetPathsEra }?,
	-- M13 wave 2: uploaded world mesh sets by set name ("Valley"); absent in older files. Luau reads
	-- only these two keys -- planHash ties Valley.json to the meshes that were uploaded -- and the
	-- ids and sizes beside them in the file are the template generator's.
	world: { [string]: { plotCount: number, planHash: string } }?,
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
	-- VIP skins toggle: a vipSkins flip rebuilds the whole plot, so flips inside this window
	-- collapse into one rebuild instead of one per call.
	skinRefreshDelaySeconds: number,
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
	-- M9: hand-authored spur (pad edge → spine) used verbatim where auto-routing would cut
	-- through something; studs relative to the plot centre.
	spur: { Vector3 }?,
	-- M12: a key of the era's `fabric.districts`, the kind of parcel this landmark pulls up.
	-- Absent means the slot pulls nothing (street upgrades such as dirtRoad).
	district: string?,
}

-- M9 street plan (docs/INTERFACES.md "Layouts"). Positions are studs relative to the plot
-- centre at Y 0; rotationY follows the slot convention (front −Z).
export type StreetLayout = { points: { Vector3 } }
-- Wave 2c: a "small" lot draws from `houses.smallProps` and reserves only those props' footprint;
-- absent means "house".
export type LotKind = "house" | "small"
export type LotLayout = { position: Vector3, rotationY: number, tier: number, kind: LotKind? }
export type PlazaLayout = { position: Vector3, rotationY: number, tier: number, prop: string }
export type TreeZoneLayout = { center: Vector3, radius: number, count: number }
-- Wave 2a: `ring` is the deck centreline's half-extent; `ramp.cell` is the ring cell holding the
-- deck T-junction and `direction` ("+X" | "-X" | "+Z" | "-Z") points from it into the city.
export type HighwayRampLayout = { cell: Vector3, direction: string }
export type HighwayLayout = { ring: number, ramp: HighwayRampLayout? }
export type SubwayEntranceLayout = { position: Vector3, rotationY: number }
-- Wave 2a blocks: a paved ground rectangle between streets, shown once any of its slots is owned.
export type BlockLayout = { min: Vector3, max: Vector3, slots: { string } }
-- Wave 2c: a parked-vehicle spot. `lot` (an index into `lots`) makes it a driveway shown only with
-- that lot's house; without it the spot is a kerb bay.
export type ParkingSpotLayout = { position: Vector3, rotationY: number, tier: number, lot: number? }

export type EraLayout = {
	plotSize: Vector3,
	baseColor: Color3,
	padSize: Vector3,
	padOffset: number,
	placeholderSize: Vector3,
	slots: { [string]: SlotLayout },
	-- M9 dressing: optional so a layout without a street plan stays valid (no dressing drawn).
	streets: { StreetLayout }?,
	lots: { LotLayout }?,
	plazas: { PlazaLayout }?,
	treeZones: { TreeZoneLayout }?,
	-- Wave 2a: absent means the era has no highway / subway dressing.
	highway: HighwayLayout?,
	subwayEntrances: { SubwayEntranceLayout }?,
	blocks: { BlockLayout }?,
	-- Wave 2c: absent means no greenery zones / no parked vehicles.
	greeneryZones: { TreeZoneLayout }?,
	parking: { ParkingSpotLayout }?,
}

-- CityDressing.json v1 mirror (M9); field names follow the JSON keys exactly. JSON null props
-- arrive as absent keys, hence the optional prop fields: absent means "feature off".
export type CityTierConfig = { ownedWeight: number, thresholds: { number } }
export type CityLodConfig = {
	nearRadius: number,
	hysteresis: number,
	vehiclePlots: number,
	refreshSeconds: number,
}
-- Wave 1d: `renderer` is "auto" | "parts" and forces a road renderer for Studio tests; optional
-- so an older file still typechecks (absent = "auto").
export type CityRoadConfig = {
	thickness: number,
	laneOffsetFraction: number,
	renderer: string?,
}
-- roadClearance is added to road.width / 2 when rejecting tree spots near a centreline;
-- footprintMargin grows every slot/pad/lot/plaza footprint a tree spot must stay outside.
export type CityTreesConfig = {
	stages: number,
	edgeMargin: number,
	roadClearance: number,
	footprintMargin: number,
}
-- Per-plot part ceilings from the M9 contract (vehiclesMap is whole-map).
export type CityBudgetConfig = {
	roadPieces: number, -- far plots and straight-road eras
	-- Wave 1b; optional so a pre-v2 file still typechecks (readers fall back to roadPieces).
	roadPiecesNear: number?, -- meandered roads on near plots
	fillerPieces: number,
	trees: number,
	vehiclesPerPlot: number,
	vehiclesMap: number,
	-- Wave 1d; optional like roadPiecesNear. Cloned path-piece Models per plot.
	pathPieces: number?,
	-- Wave 1e; optional likewise. Row-placed lamp posts per plot (junction lamps share fillerPieces).
	lampPosts: number?,
	-- Wave 2a; optional likewise. Road-tile cells and highway cells per plot.
	tileCells: number?,
	highwayCells: number?,
	-- Wave 2c; optional likewise. Per plot (near only) except the two map-wide caps.
	greenery: number?,
	parked: number?,
	walkersPerPlot: number?,
	walkersMap: number?,
	birdsMap: number?,
	-- M12; optional likewise. Fabric parcels per near plot, and per far plot as an index prefix
	-- (wave 1c `parcelsFar`: the row-1 frontage nearest the heart); wild items per near plot and
	-- per far plot; town trees per near plot (wave 1c, an index prefix).
	parcels: number?,
	parcelsFar: number?,
	wild: number?,
	wildFar: number?,
}
export type CityLampsConfig = { firstTier: number, everyNthJunction: number, maxPerPlot: number }
export type CityVehiclesConfig = { firstTier: number, turnSeconds: number }
-- `material` is an Enum.Material name; `color` is RGB 0-255.
-- Wave 1b: a smooth sideways wobble along every drawn centreline, tapered to 0 at graph nodes.
export type CityMeanderConfig = {
	amplitude: number,
	wavelength: number,
	segmentLength: number,
	widthJitter: number,
}
-- Wave 1d: baked path meshes (docs/INTERFACES.md "Wave 1d — baked paths"). rimHeight and
-- fillHeight are baked into the templates; the client reads only the appear effect and the rim
-- LOD from here. A file without `paths` disables the baked renderer (the parts renderer draws).
export type CityPathsConfig = {
	rimHeight: number,
	fillHeight: number,
	rimLeadSeconds: number, -- the rim is parented this long before its fill
	dustSeconds: number, -- a dust burst crosses the piece in this long
	rimNearOnly: boolean, -- far plots drop their rims, halving the part count
	-- Wave 1e: studs the server raises every building model, so floors, ramps and steps lower
	-- than fillHeight clear the spur that runs under them. Must stay above fillHeight.
	buildingLift: number?,
}
-- Per era: the world-planar UV tile the bake used. An era without it draws Parts.
-- Wave 1e: `surface` picks the plot-wide texture variant from owned slots (last owned upgrade
-- wins, else `base`); "default" is the texture baked into the templates. `variants` is the look
-- the parts fallback draws for a variant.
export type CitySurfaceUpgrade = { slot: string, variant: string }
export type CitySurfaceConfig = { base: string, upgrades: { CitySurfaceUpgrade } }
export type CitySurfaceVariantLook = { material: string, color: { number } }
export type CityEraPathsConfig = {
	tileStuds: number,
	surface: CitySurfaceConfig?,
	variants: { [string]: CitySurfaceVariantLook }?,
}
-- Wave 2a: kit road tiles on a `tileStuds` lattice, one prop per cell chosen by the cell's
-- visible connectivity. Excludes `paths` and `meander`. Spurs stay plain footpath Parts.
export type CityTileLook = { width: number, material: string, color: { number } }
export type CityTilePropsConfig = {
	straight: string,
	["end"]: string,
	bend: string,
	tee: string,
	cross: string,
	crossing: string?,
}
-- Paved block slabs with street trees along their street-facing edges (treeSpacing 0 = none).
export type CityTileBlocksConfig = {
	material: string,
	color: { number },
	treeSpacing: number,
	treeInset: number,
	treeClearance: number,
}
-- Planted paving over planned-but-undrawn street cells, replaced by tiles as streets grow.
export type CityTileParkStripsConfig = {
	material: string,
	color: { number },
	treeSpacing: number,
	treeStage: number,
	maxTrees: number,
}
export type CityEraTilesConfig = {
	tileStuds: number,
	props: CityTilePropsConfig,
	pavement: CityTileLook?,
	spur: CityTileLook,
	blocks: CityTileBlocksConfig?,
	parkStrips: CityTileParkStripsConfig?,
}
-- Wave 2a: an elevated ring drawn while `requiresSlot` is owned; its cars never take the ramp.
-- Wave 2b: junction and ramp are absent in loop mode (Orbital monorail) — a plain closed ring.
export type CityHighwayPropsConfig = {
	deck: string,
	corner: string,
	junction: string?,
	ramp: string?,
	sign: string?,
}
export type CityEraHighwayConfig = {
	requiresSlot: string,
	props: CityHighwayPropsConfig,
	vehicles: { count: number, speed: number },
	revealCellsPerSecond: number,
	-- Wave 2b: the props that run on the deck; absent = the era's vehicles.props (Metropolis cars).
	vehicleProps: { string }?,
	-- Road-surface height of the deck props in studs. Merged props are one MeshPart, so the deck
	-- cannot be measured apart from its rails; absent = no deck cars.
	deckHeight: number?,
}
-- Wave 2a: street-corner entrances from the layout, shown while `requiresSlot` is owned.
export type CityEraSubwayConfig = { requiresSlot: string, prop: string, maxPerPlot: number }
export type CityEraRoadConfig = {
	width: number,
	material: string,
	color: { number },
	junctionProp: string?,
	bendProp: string?,
	-- Overrides road.laneOffsetFraction; Village sets 0 so carts run down the trail's middle.
	laneOffsetFraction: number?,
	meander: CityMeanderConfig?,
	paths: CityEraPathsConfig?,
	tiles: CityEraTilesConfig?,
}
export type CityEraTreesConfig = { maxCount: number, clearance: number, prop: string? }
export type CityEraPropsConfig = { props: { string } }
-- Wave 1e: `requiresSlot` replaces the lamps.firstTier gate with ownership of that slot;
-- `placement` "row" lines the spine centrelines every `spacing` studs, `offset` outside the edge.
export type CityEraLampsConfig = {
	prop: string?,
	requiresSlot: string?,
	placement: string?, -- "junction" (default) | "row"
	spacing: number?,
	offset: number?,
}
-- Wave 1e: one prop at each node where three or more spine stretches meet.
export type CityEraSignalsConfig = {
	prop: string?,
	requiresSlot: string?,
	offset: number,
	maxPerPlot: number,
}
export type CityEraVehiclesConfig = {
	props: { string },
	perPlot: number,
	speed: number,
	-- Wave 2d: runtime Model:ScaleTo of every moving car, deck cars included (absent = 1).
	scale: number?,
	-- Wave 2d: studs kept between a car and the one ahead where they enter the same lane.
	followGap: number?,
}
-- Wave 2c (docs/INTERFACES.md "Wave 2c — living city"). Every `perTier` is cumulative and indexed
-- by tier (1-5); tier 0 shows none.
export type CityEraHousesConfig = { props: { string }, smallProps: { string }? }
export type GreeneryConfig = {
	props: { string },
	perTier: { number },
	lotGarnish: number, -- pieces around each visible lot
	clearance: number, -- studs between pieces
	roadClearance: number, -- studs beyond the road edge
}
export type ParkedConfig = {
	props: { string },
	perTier: { number }, -- counts bays
	-- Wave 2d; absent = 1 car per bay at scale 1, 0.3 studs between packed cars.
	scale: number?,
	perBay: number?,
	gap: number?,
	bayLength: number?, -- packing length; absent = the pool's built-size footprint length
}
export type PedestrianConfig = {
	firstTier: number,
	perTier: { number },
	offset: number, -- studs off the street centreline, both sides
	clearance: number?, -- studs walkers keep from any solid (absent = the client's default)
	speed: number,
	bobHeight: number,
	bobHz: number,
	props: { string },
	scale: number?, -- wave 2d: runtime Model:ScaleTo of every walker (absent = 1)
}
export type SmokeConfig = {
	firstTier: number,
	eras: { string },
	props: { [string]: { number } }, -- house prop -> chimney offset [x, y, z] in the prop frame
	rate: number,
	lifetime: number,
	size: { number }, -- [start, end] studs
	color: { number }, -- RGB 0-255
}
export type BirdsConfig = {
	firstTier: number,
	flocksPerTier: { number },
	birdsPerFlock: number,
	radius: number,
	height: number,
	speed: number, -- studs per second along the circle
	prop: string,
	eras: { string }?, -- eras that get flocks; absent = none
}
export type AmbientConfig = { smoke: SmokeConfig?, birds: BirdsConfig? }

-- M12 growing city (docs/INTERFACES.md "M12 contracts"): Config/Fabric/<Era>.json, generated by
-- tools/fabric.py, and the era's CityDressing.json v4 `fabric` block. Field names follow the JSON
-- keys exactly. Coordinates are plot-local studs (origin at the plot centre, Y 0); rotationY
-- follows the slot convention (front −Z, facing the parcel's street).
export type FabricParcelSize = "small" | "medium" | "narrow"
-- Parcel i is its 1-based index in the list. `stretch` is the RoadGraph piece id of the stretch it
-- fronts and `along` the studs from that stretch's `a` end to the foot of the perpendicular from
-- its front-centre. Row 1 has front 0. A row-k parcel (k = 2 or 3, wave 1c) stands behind parcel
-- `front`, the row k − 1 parcel, which the list always names first. Row 2 repeats its front's
-- stretch and along.
export type FabricParcel = {
	x: number,
	z: number,
	rotationY: number,
	size: FabricParcelSize,
	stretch: string,
	along: number,
	row: number,
	front: number,
}
-- A clump draws `fabric.wild.clumps[variant]` (1-based, like any Luau array) and lists its four
-- quarter centres in `quads`, in plot coordinates, for clearing tests only; quarter q is the
-- quarter prop turned rotationY + 90·(q − 1). A single draws `prop`. `skirt` marks an entry
-- outside the plot base.
export type FabricWild = {
	kind: "clump" | "single",
	x: number,
	z: number,
	rotationY: number,
	scale: number,
	skirt: boolean,
	variant: number?,
	quads: { { number } }?,
	prop: string?,
}
-- Wave 1c round 3: an entry of a city upgrade layer (trees, flowers, banners), placed once the
-- layer's `requiresSlot` is owned and the anchor is developed: a "stretch" entry needs `stretch`
-- drawn, a "parcel" entry needs parcel `parcel` at level 2 or more (its house built). `variant`
-- is 1-based into the layer's `props`.
export type FabricUpgradeAnchor = "stretch" | "parcel"
export type FabricUpgradeItem = {
	x: number,
	z: number,
	rotationY: number,
	scale: number,
	variant: number,
	anchor: FabricUpgradeAnchor,
	stretch: string?,
	parcel: number?,
}
export type FabricData = {
	version: number,
	parcels: { FabricParcel },
	wild: { FabricWild },
	upgrades: { [string]: { FabricUpgradeItem } }?, -- wave 1c round 3; keyed by layer name
}
-- CityFabric.Develop's tunables: pull fades to 0 at `radius` studs along the drawn streets, a
-- parcel needs a landmark or a developed parcel within `reach` studs to develop, it never runs
-- more than `levelsOverTier` levels ahead of the tier, and a back-row parcel stays `rowLag` levels
-- behind the parcel in front of it (wave 1c; absent = 1).
export type FabricPullConfig = {
	radius: number,
	tierTerm: number,
	thresholds: { number },
	reach: number,
	levelsOverTier: number,
	smallMaxLevel: number,
	rowLag: number?,
}
-- Every district lists props for both sizes; a small prop in a medium list is centred.
-- Wave 1c round 2: `narrow` is optional; a missing size list falls back to `fabric.fallbackDistrict`.
export type FabricDistrictProps = { small: { string }, medium: { string }, narrow: { string }? }
-- `quarters[v]` shares `clumps[v]`'s origin with its trees in the local (+X, +Z) quadrant, so four
-- turned copies rebuild the clump and the woods can recede a quarter at a time.
export type FabricWildConfig = {
	clumps: { string },
	quarters: { string },
	quarterRadius: number,
	singleRadius: number,
}
-- Clearing margins in studs beyond owned slot footprints, pads, developed parcels and plazas, and
-- street and spur centrelines.
export type FabricClearConfig = { slot: number, pad: number, street: number, parcel: number }
export type FabricConstructionConfig = {
	minSeconds: number,
	maxSeconds: number,
	stagger: number,
	stageSeconds: number,
	riseSeconds: number,
	revealSeconds: number,
	-- Review amendment: concurrent dust puffs per plot; absent means no cap.
	maxPuffs: number?,
	-- Rounds 2-3 review: unanimated spawns placed per frame per plot; absent means no cap.
	spawnsPerFrame: number?,
}
-- `offset` is [x, y, z] from the pad centre in the slot's frame (turned by the slot's rotationY);
-- colours are RGB 0-255.
export type FabricMarkerConfig = {
	prop: string,
	offset: { number },
	stakeColor: { number },
	stringColor: { number },
}
-- `material` is an Enum.Material name; `color` is RGB 0-255.
export type FabricPadLookConfig = { material: string, color: { number } }
-- Wave 1c round 3: one city upgrade layer. A placed entry shows stage
-- clamp(tier − tierOffset, 0, #stages − 1), so things bought early still grow up with the town.
-- `stagger` (optional) is the planting wave's seconds per entry; absent means construction.stagger.
-- `budget` caps the layer on a near plot as an index prefix.
export type FabricUpgradeLayerConfig = {
	requiresSlot: string,
	props: { string },
	tierOffset: number,
	stagger: number?,
	budget: number,
}
-- `sizes` are footprints [x, z] in studs. `marker`, `padLook`, `reveal` and `upgrades` are
-- optional: absent means that feature is off.
export type FabricConfig = {
	sizes: { small: { number }, medium: { number }, narrow: { number }? },
	pull: FabricPullConfig,
	heightFloor: number,
	districts: { [string]: FabricDistrictProps },
	sites: { small: string, medium: string, narrow: string? },
	-- Wave 1c round 2: the district whose list a parcel uses when its own district has none for its size.
	fallbackDistrict: string?,
	wild: FabricWildConfig,
	clear: FabricClearConfig,
	construction: FabricConstructionConfig,
	marker: FabricMarkerConfig?,
	padLook: FabricPadLookConfig?,
	reveal: string?,
	upgrades: { [string]: FabricUpgradeLayerConfig }?,
}

export type CityEraDressingConfig = {
	road: CityEraRoadConfig,
	trees: CityEraTreesConfig,
	houses: CityEraHousesConfig,
	plazas: CityEraPropsConfig,
	lamps: CityEraLampsConfig,
	signals: CityEraSignalsConfig?,
	highway: CityEraHighwayConfig?,
	subway: CityEraSubwayConfig?,
	vehicles: CityEraVehiclesConfig,
	-- Wave 2c; absent = that feature off for the era.
	greenery: GreeneryConfig?,
	parked: ParkedConfig?,
	pedestrians: PedestrianConfig?,
	-- M12; absent (or no Config/Fabric/<Era>) = the era keeps its M9 / wave 2c dressing.
	fabric: FabricConfig?,
}
export type CityDressingConfig = {
	version: number,
	-- Wave 2b: what "City detail" off keeps (trees, park planters) as a share of the normal cap.
	detail: { treeShare: number }?,
	tier: CityTierConfig,
	lod: CityLodConfig,
	road: CityRoadConfig,
	budget: CityBudgetConfig,
	trees: CityTreesConfig,
	lamps: CityLampsConfig,
	vehicles: CityVehiclesConfig,
	-- Wave 1d; optional so a pre-wave-1d file still typechecks (absent = no baked paths).
	paths: CityPathsConfig?,
	-- Wave 2c; absent = no chimney smoke and no birds anywhere.
	ambient: AmbientConfig?,
	-- Keyed by era `name`; a missing era means no dressing for it.
	eras: { [string]: CityEraDressingConfig },
}

-- C0 combat ("Expeditions", docs/INTERFACES.md "C0 contracts"). Armory.json / Combat.json /
-- Places.json / Missions/*.json mirrors; field names follow the JSON keys exactly. Asset ids and
-- place ids of 0 mean "not yet" and never error.

-- The two permanent weapon slots. Also the ActionResult.slotId of buyGear/ascend.
export type WeaponSlot = "melee" | "ranged"

export type MissionRecord = { bestWave: number, bossClears: number, overdriveBest: number }

-- Profile schema v5. materials is keyed by material name ("Timber") and never negative; gear and
-- ascension hold a tier / Ascension level per slot (0 = starter / none); highestEra survives
-- Rebirth and gates mission tiles; expeditionSince/expeditionSeconds are the away-time split the
-- offline grant reads (both zeroed by ApplyOfflineGrant).
export type CombatProfile = {
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

export type PlacesConfig = { version: number, hubPlaceId: number, combatPlaceId: number }

-- Armory.json v1. `kind` and `fire` stay `string` because they are decoded from JSON, which Luau
-- cannot narrow to a union. Melee classes carry range/arcDegrees/chain/windows/comboReset/
-- finisherKnockback; ranged carry fire/cooldown/range plus the optional per-family fields.
export type BandDef = { band: number, eraName: string, material: string }
export type WeaponClassDef = {
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
export type AbilityDef = {
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
-- `model` is a prop name under ReplicatedStorage/Assets/Props/<band eraName>/ ("" = no model, so
-- the hands stay empty); `ability` keys ArmoryConfig.abilities ("" = none).
export type WeaponStarterDef = {
	name: string,
	class: string,
	damage: number,
	hp: number,
	ability: string,
	model: string,
}
-- `cost` is in the band material; `unlockRate` is the persisted income/s the city must reach.
export type WeaponTierDef = {
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
	-- C2: key into ArmoryConfig.partyEffects, fired on allies when this weapon's ability is cast.
	partyEffect: string?,
}
export type ArmorySlotDef = { starter: WeaponStarterDef, tiers: { WeaponTierDef } }
-- C2: rally heals allies (never the caster) by healFraction of their MaxHp; warcry multiplies
-- allies' outgoing damage by damageMult for `seconds`. Allies within `radius` of the caster.
export type PartyEffectDef = {
	kind: "rally" | "warcry",
	radius: number,
	healFraction: number?,
	damageMult: number?,
	seconds: number?,
}
export type AscensionLevelDef = {
	level: number,
	materials: { [string]: number },
	valor: number,
	damageMult: number,
	hpMult: number,
	abilityMult: number,
}
export type AscensionConfig = {
	requiresRebirth: number,
	levelsPerRebirth: number,
	levels: { AscensionLevelDef },
}
export type ArmoryConfig = {
	version: number,
	baseHp: number,
	power: { hpWeight: number },
	bands: { BandDef },
	classes: { [string]: WeaponClassDef },
	abilities: { [string]: AbilityDef },
	-- Keyed by WeaponSlot; a map (not a record) because every lookup comes from a validated
	-- client string or a config-driven loop.
	slots: { [string]: ArmorySlotDef },
	ascension: AscensionConfig,
	partyEffects: { [string]: PartyEffectDef },
}

-- Combat.json v1.
export type CombatOfflineConfig = { expeditionEfficiency: number }
-- No baseHp here: Armory.json owns it (Armory.MaxHp is the only thing that reads it), so the
-- two can never drift apart.
export type CombatPlayerConfig = {
	respawnSeconds: number,
	hitDistancePad: number,
	breatherRegenPerSecond: number,
	killCooldownRefundSeconds: number,
	comboTimingTolerance: number,
	aimAssistDegrees: number,
	corpseSeconds: number,
	dashHitRadius: number,
	burstConeDegrees: number,
}
export type CombatRemotesConfig = {
	attackCallsPerSecond: number,
	abilityCallsPerSecond: number,
	-- P3 range buckets: held beams, SMGs and Mag Dump send far more than a mission weapon.
	rangeAttackCallsPerSecond: number,
	rangeAbilityCallsPerSecond: number,
	runListCallsPerSecond: number,
	combatStateHz: number,
}
export type CombatDirectorConfig = {
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
	tempoWarmupSeconds: number,
}
export type CombatCoopConfig = {
	maxParty: number,
	joinUntilWave: number,
	contributionFloor: number,
	countPerExtraPlayer: number,
	mentorRatio: number,
	mentorValor: number,
	-- C2. Boss HP × (1 + bossHpPerExtraPlayer × (partySize − 1)); regular enemies still scale
	-- by count only.
	bossHpPerExtraPlayer: number,
	-- A mentee counts toward MentorBonus only if its raw (pre-floor) damage share of the boss
	-- wave reached this, so an idle alt cannot farm Valor for its main.
	mentorMinDamageShare: number,
	inviteSeconds: number,
	-- Re-inviting the same player waits this long; a decline blocks that leader for declineBlockSeconds.
	inviteCooldownSeconds: number,
	declineBlockSeconds: number,
	-- The lobby starts once every expected member is ready, or this long after the first arrival.
	lobbyWaitSeconds: number,
	-- Summary shown this long, then every remaining human goes home in ONE group teleport.
	returnGroupSeconds: number,
	-- A returning party re-forms in the hub only among members who arrive within this window.
	reformSeconds: number,
	-- Default of the Expedition panel's "Open to public" toggle.
	publicByDefault: boolean,
}
export type CombatOverdriveConfig = {
	requiresRebirth: number,
	countMult: number,
	hpMult: number,
	damageMult: number,
	spawnRateMult: number,
	rewardMult: number,
}
-- C2: listCacheSeconds = one registry read per hub server per window, shared by every viewer;
-- listMax = rows sent per RunList; friendChecksPerCall = IsFriendsWithAsync fan-out cap.
export type CombatRegistryConfig = {
	mapName: string,
	ttlSeconds: number,
	listCacheSeconds: number,
	listMax: number,
	friendChecksPerCall: number,
}
-- Animation asset ids; 0 = the procedural fallback. C2.5 adds run/hit for enemies and the player
-- slash/lunge overrides (Roblox-owned default tool animations are the intended first values).
export type CombatAnimationsConfig = {
	enemyIdle: number,
	enemyWalk: number,
	enemyAttack: number,
	enemyDeath: number,
	enemyRun: number,
	enemyHit: number,
	playerSlash: number,
	playerLunge: number,
}
-- C2.5 over-the-shoulder camera (client only). shoulderOffset = Humanoid.CameraOffset {x, y, z};
-- zoom values are studs; freeCursorPhases = RunPhase values in which the mouse is unlocked.
export type CombatCameraConfig = {
	shoulderOffset: { number },
	fieldOfView: number,
	defaultZoom: number,
	minZoom: number,
	maxZoom: number,
	touchSensitivity: number,
	gamepadSensitivity: number,
	touchAimAssistDegrees: number,
	freeCursorPhases: { string },
}
-- C2.5 enemy steering and reactions (server). Melee enemies take one of maxMeleeAttackers slots
-- around their target; the rest circle at holdRadius. Chargers wind up, then dash chargeDistance.
export type CombatAiConfig = {
	separationRadius: number,
	separationWeight: number,
	maxMeleeAttackers: number,
	holdRadius: number,
	strafeSpeedMult: number,
	rangedMinDistance: number,
	rangedMaxDistance: number,
	pathRecomputeSeconds: number,
	staggerSeconds: number,
	finisherStaggerSeconds: number,
	telegraphSeconds: number,
	chargeDistance: number,
	chargeSpeedMult: number,
	chargeWindupSeconds: number,
	-- Hit shapes checked at impact time (degrees are half-angles; lane half-width scales with body).
	strikeHalfArcDegrees: number,
	shotHalfConeDegrees: number,
	strikeReachPad: number,
	chargeLaneHalfWidth: number,
	postPatternAttackDelay: number,
	-- C2.5 review: the steering/reaction numbers that were code constants.
	-- memberRadius = a party member's body radius added to every hit shape; retargetHysteresis =
	-- studs closer another member must be before an enemy switches; cancelCooldownFraction = the
	-- share of attackCooldown a cancelled windup costs; chargeTriggerFraction = the share of
	-- chargeDistance a charger winds up inside; slamTriggerMargin = studs beyond a slam radius
	-- that still starts a slam; dashTimeoutPad = seconds after the ideal dash time a blocked dash
	-- ends; defaultSlamRadius / defaultSummonCount = pattern fallbacks; staggerShove = studs/s
	-- push on a stagger; bossStaggerMult scales both stagger durations for bosses;
	-- stunPatternRefundFraction = share of a boss pattern's cooldown returned when a stun cancels
	-- it during its windup.
	memberRadius: number,
	retargetHysteresis: number,
	cancelCooldownFraction: number,
	chargeTriggerFraction: number,
	slamTriggerMargin: number,
	dashTimeoutPad: number,
	defaultSlamRadius: number,
	defaultSummonCount: number,
	staggerShove: number,
	bossStaggerMult: number,
	stunPatternRefundFraction: number,
}
-- C2.5 client impact tunables.
export type CombatFeelConfig = {
	shakeLight: number,
	shakeHeavy: number,
	hitMarkerSeconds: number,
	trailSeconds: number,
	arrowSpeed: number,
	ragdollImpulse: number,
	ragdollSeconds: number,
	hitSparkCount: number,
}
-- Studio-only levers, named here so no attribute name is duplicated in code.
export type CombatDebugConfig = {
	missionAttribute: string,
	-- P1: Workspace boolean; true at boot = the Proving Grounds instead of a mission (Studio only).
	provingAttribute: string,
	overdriveAttribute: string,
	grantMaterialsAttribute: string,
	grantValorAttribute: string,
	waveAttribute: string,
	spawnAttribute: string,
	godModeAttribute: string,
	killAllAttribute: string,
	setGearAttribute: string,
	botsAttribute: string,
	fakeRunsAttribute: string,
	forceTeleportFailureAttribute: string,
	forceRegistryFailureAttribute: string,
	handoffStoreName: string,
	handoffMaxAgeSeconds: number,
	botHp: number,
	botDamagePerSecond: number,
	-- C2: the income/s a debug bot reports to MentorBonus (0 = every bot is a mentee).
	botIncomeRate: number,
	-- C2 hub levers (RequestDebug "fakeParty" / "fakeInvite" use the same names).
	fakePartyAttribute: string,
	fakeInviteAttribute: string,
}
-- Enemy AI tunables (EnemyService) and client presentation tunables (CombatFxController).
export type CombatEnemyConfig = {
	tickHz: number,
	aggroRange: number,
	retargetSeconds: number,
	eliteScale: number,
	bossScale: number,
	-- C2: colours moved out of EnemyService. RGB 0-255; EnemyDef.color overrides defaultColor.
	defaultColor: { number },
	bossColor: { number },
	botColor: { number },
}
export type CombatFeedbackConfig = {
	hitstopSeconds: number,
	cameraKickDegrees: number,
	damageNumberSeconds: number,
	bannerSeconds: number,
	lowHpFraction: number,
}
export type CombatConfig = {
	version: number,
	offline: CombatOfflineConfig,
	player: CombatPlayerConfig,
	remotes: CombatRemotesConfig,
	director: CombatDirectorConfig,
	coop: CombatCoopConfig,
	overdrive: CombatOverdriveConfig,
	registry: CombatRegistryConfig,
	animations: CombatAnimationsConfig,
	enemy: CombatEnemyConfig,
	feedback: CombatFeedbackConfig,
	debug: CombatDebugConfig,
	camera: CombatCameraConfig,
	ai: CombatAiConfig,
	feel: CombatFeelConfig,
}

-- Missions/<eraIndex>_<EraName>.json v1, resolved by numeric prefix like era configs.
-- kind: "melee" | "ranged" | "charger" (C2.5: chargers wind up and dash; see CombatAiConfig).
export type EnemyDef = {
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
-- The composition in force from `fromWave` until the next entry takes over.
export type CompositionDef = { fromWave: number, weights: { [string]: number } }
export type WaveTableDef = {
	baseCount: number,
	countPerWave: number,
	hpGrowth: number,
	damageGrowth: number,
	rewardGrowth: number,
	composition: { CompositionDef },
}
-- C2.5 boss attacks, cycled on their own cooldowns. slam = telegraphed AoE at the boss (radius,
-- damageMult); charge = the charger dash at the target; summon = `count` of mission enemy `enemy`.
export type BossPatternDef = {
	kind: "slam" | "charge" | "summon",
	cooldown: number,
	windupSeconds: number,
	radius: number?,
	damageMult: number?,
	enemy: string?,
	count: number?,
}
export type BossDef = {
	template: string,
	enemy: string,
	hpMult: number,
	damageMult: number,
	cashMult: number,
	materialsMult: number,
	valor: number,
	patterns: { BossPatternDef }?,
}
export type MissionConfig = {
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
	-- Keyed by the wave number as a string ("5"), because JSON has no integer keys.
	bosses: { [string]: BossDef },
}

-- The four numbers Combat.EnemyStats resolves for one spawned enemy. Declared here as well as
-- in Combat.luau (which is pure and cannot require this file) because it is the payload the
-- combat services hand each other.
export type EnemyStats = { hp: number, damage: number, cash: number, materials: number }

-- C1: the arena a mission is fought in (Shared/Layouts/Arenas/<mission.arena>). Plain numbers and
-- names rather than Vector3/Color3/Enum so the layout stays a data file: ArenaService converts.
-- Origin is the arena centre, the floor's TOP face is y = 0, and every obstacle sits on it.
export type ArenaObstacle = {
	x: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	material: string,
	color: { number },
}
export type ArenaSurface = { material: string, color: { number } }
export type ArenaPoint = { x: number, z: number }
export type ArenaLayout = {
	size: { x: number, z: number },
	floor: ArenaSurface,
	-- nil = open edges (no fence); `height` is studs above the floor.
	wall: { height: number, material: string, color: { number } }?,
	lobbyPad: ArenaPoint,
	-- At least 4 / 8 respectively, both used round-robin.
	playerSpawns: { ArenaPoint },
	enemySpawns: { ArenaPoint },
	obstacles: { ArenaObstacle },
}

-- Combat place run state (server to client on the RunState event). One authoritative payload for
-- the whole HUD, so the client never derives a phase.
export type RunPhase = "lobby" | "wave" | "breather" | "boss" | "summary" | "ended"
export type EnemyState = "idle" | "chasing" | "attacking" | "stunned" | "dead"
-- One row of the HUD party list. `bot` rows are Studio debug rigs: they scale the wave and take
-- aggro, but their reward share is discarded. `abilityReadyIn` is SECONDS remaining, so the
-- client can draw a cooldown ring without knowing the server clock.
export type PartyMember = {
	userId: number,
	name: string,
	hp: number,
	maxHp: number,
	ready: boolean,
	alive: boolean,
	bot: boolean,
	abilityReadyIn: { melee: number, ranged: number },
	stance: WeaponSlot,
	-- C2. host = the run's hostUserId. waiting = arrived or died mid-wave; enters at the next wave
	-- boundary, untargetable meanwhile. damageShare = raw share of the run's damage so far, 0-1.
	host: boolean,
	waiting: boolean,
	damageShare: number,
}
-- The server-side party record behind a PartyMember: it also holds the character, the ability
-- cooldown stamps and the per-run bookkeeping the client never sees. Lives in Types (not in
-- ArenaService) because EnemyService and CombatService take one as an argument, and a service
-- may not require the service above it in the boot order.
export type RunMember = {
	userId: number,
	name: string,
	-- nil for a debug bot; every other field works the same for both.
	player: Player?,
	bot: boolean,
	ready: boolean,
	character: Model?,
	humanoid: Humanoid?,
	stance: WeaponSlot,
	-- os.clock() stamps; a kill refunds killCooldownRefundSeconds off both.
	abilityReadyAt: { melee: number, ranged: number },
	godMode: boolean,
	-- os.clock() the corpse may respawn at; 0 = alive or waiting on the run to end.
	respawnAt: number,
	spawnIndex: number,
	-- C2: see PartyMember.waiting. incomeRate = profile incomeAtSave at admit (bots:
	-- debug.botIncomeRate). drawStartedAt = os.clock() of the last RequestDraw, 0 = none.
	-- empoweredUntil/empowerMult = an active warcry.
	waiting: boolean,
	incomeRate: number,
	drawStartedAt: number,
	empoweredUntil: number,
	empowerMult: number,
}
export type RunSummary = {
	missionId: string,
	overdrive: boolean,
	wavesCleared: number,
	bestWave: number,
	died: boolean,
	cash: number,
	materials: { [string]: number },
	valor: number,
	kills: number,
	seconds: number,
	-- C2: Valor from MentorBonus (already included in `valor`), and the raw run damage share.
	mentorValor: number,
	damageShare: number,
}
export type RunState = {
	kind: "run",
	phase: RunPhase,
	missionId: string,
	overdrive: boolean,
	wave: number,
	waves: number,
	alive: number,
	-- Still to spawn in the current wave.
	remaining: number,
	tempo: number,
	-- True while the current wave is running as "Waves N + N+1".
	merged: boolean,
	party: { PartyMember },
	breatherEndsIn: number?,
	-- Seconds left before director.runCapSeconds ends the run.
	runEndsIn: number,
	boss: { name: string, hp: number, maxHp: number }?,
	summary: RunSummary?,
	-- C2: seconds until the group return home during "summary"; nil otherwise.
	returnIn: number?,
}

-- Presentation events, batched per Heartbeat frame into one list per client. Damage numbers,
-- highlights, banners and camera kick are drawn from these; nothing here is authoritative.
export type CombatFxHit = {
	kind: "hit",
	enemyId: number,
	amount: number,
	finisher: boolean,
	position: Vector3,
	byUserId: number,
	-- C2.5: attacker → enemy, flattened; nil for DoT ticks. Drives sparks and the stagger lean.
	direction: Vector3?,
}
export type CombatFxKill = {
	kind: "kill",
	enemyId: number,
	position: Vector3,
	cash: number,
	materials: number,
	byUserId: number,
}
export type CombatFxPlayerHit = { kind: "playerHit", userId: number, amount: number }
export type CombatFxAbility = {
	kind: "ability",
	userId: number,
	key: string,
	slot: WeaponSlot,
	position: Vector3,
	radius: number?,
}
export type CombatFxWave = { kind: "wave", wave: number, merged: boolean, boss: boolean }
export type CombatFxBossDown = { kind: "bossDown", name: string, valor: number }
export type CombatFxPlayerDown = { kind: "playerDown", userId: number, respawnIn: number? }
export type CombatFxRefused = {
	kind: "refused",
	reason: "cooldown" | "dead" | "lobby" | "waiting",
}
-- C2. swing: a validated melee swing (step 1-3), sent to everyone except the swinger so other
-- players' combos animate. partyEffect: rally/warcry landed on targetIds. mentor: Valor paid to
-- userId for carrying `mentees` players through a boss wave.
export type CombatFxSwing = { kind: "swing", userId: number, step: number }
export type CombatFxPartyEffect = {
	kind: "partyEffect",
	userId: number,
	key: string,
	position: Vector3,
	radius: number,
	targetIds: { number },
}
export type CombatFxMentor = { kind: "mentor", userId: number, valor: number, mentees: number }
-- C2.5: a wind-up the client must draw BEFORE the blow lands (ground ring for slam, lane for
-- charge, glow for a strike). seconds = time until the hit.
export type CombatFxTelegraph = {
	kind: "telegraph",
	enemyId: number,
	attack: "strike" | "slam" | "charge" | "summon",
	position: Vector3,
	direction: Vector3?,
	radius: number?,
	seconds: number,
}
-- P2: a projectile left a player's weapon (range). Sent to everyone at fire time so every
-- client draws the same arrow/shell flying; the damage arrives later as CombatFxStrike.
-- direction is unit and already includes spread; seq seeds the split fan like pellets.
export type CombatFxShot = {
	kind: "shot",
	userId: number,
	weapon: string,
	variant: string,
	origin: Vector3,
	direction: Vector3,
	speed: number,
	gravity: number,
	charge: number,
	seq: number,
	-- True when this shot marks where an in-flight arrow SPLIT (origin = split point, direction =
	-- heading there): the client splits its matching userId+seq flight here instead of guessing.
	split: boolean?,
	-- P3: the ability id when an ability fired this projectile (Volley, Cluster Shell).
	ability: string?,
}
export type CombatFx =
	CombatFxShot
	| CombatFxCast
	| CombatFxTelegraph
	| CombatFxHit
	| CombatFxKill
	| CombatFxPlayerHit
	| CombatFxAbility
	| CombatFxWave
	| CombatFxBossDown
	| CombatFxPlayerDown
	| CombatFxRefused
	| CombatFxSwing
	| CombatFxPartyEffect
	| CombatFxMentor
	| CombatFxStrike

-- A run advertised in the MemoryStore registry. `accessCode` is server-only: the hub never sends
-- an ActiveRun to a client (it sends RunListEntry), so a client can never teleport itself into a
-- reserved server. C2: `public` comes from the RunTicket; memberIds = humans in the run now.
export type ActiveRun = {
	hostUserId: number,
	hostName: string,
	missionId: string,
	era: number,
	wave: number,
	overdrive: boolean,
	partySize: number,
	accessCode: string,
	public: boolean,
	memberIds: { number },
}

-- C2: the server-only record the hub writes to the ActiveRunsCodes hash map at departure. The
-- combat place trusts it (a server wrote it) and never the teleport data for these fields.
-- expected = the departing party's userIds, host included. privateServerId = ReserveServer's
-- second return ("studio" in bridge mode): the combat server honours a ticket only when it equals
-- game.PrivateServerId, so a client-forged teleport into a public server can never claim one.
export type RunTicket = {
	accessCode: string,
	privateServerId: string,
	missionId: string,
	overdrive: boolean,
	public: boolean,
	expected: { number },
}

-- C2: one row of the hub RunList event. Only joinable runs are sent (seat free, wave <=
-- joinUntilWave). relation orders the list: runs with a member in this hub server, then
-- friends' runs, then public runs.
export type RunRelation = "server" | "friend" | "public"
export type RunListEntry = {
	hostUserId: number,
	hostName: string,
	missionId: string,
	wave: number,
	overdrive: boolean,
	partySize: number,
	relation: RunRelation,
}

-- C2 hub party (PartyService, never persisted). Sent on the PartyState event to every member
-- (invitees get PartyInvite instead); nil = not in a party.
export type HubPartyMember = { userId: number, name: string }
export type HubPartyInvite = { userId: number, name: string, expiresIn: number }
export type HubParty = {
	leaderUserId: number,
	members: { HubPartyMember },
	pending: { HubPartyInvite },
}
-- The PartyInvite event, to the invitee only.
export type PartyInviteEvent = { leaderUserId: number, leaderName: string, expiresIn: number }

-- C2: teleport data (and Studio return record) on the way home. A hint, never an entitlement:
-- summaries are display-only; a party re-forms only among members whose OWN hints agree.
export type PartyHint = { leaderUserId: number, memberIds: { number } }
export type ReturnData = {
	summaries: { [string]: RunSummary },
	party: PartyHint?,
	refused: ("full" | "over" | "locked")?,
}

-- P1 Proving Grounds + crowd enemies (docs/COMBAT_DESIGN.md, INTERFACES "P1 contracts").
-- Config/ProvingGrounds.json. Every value here is live-tunable in Studio through Tuning.
export type HitShape = "arc" | "sphere" | "capsule" | "cone" | "ray"
-- One weapon variant. range = reach of arc/capsule/cone/ray, radius of sphere. pad = forgiveness
-- in studs added to every test. cap = max enemies per attack (0 = unlimited). rate = attacks/s.
-- projectileSpeed 0 = hitscan. Cone guns: the SERVER tests the whole cone (arcDegrees = full
-- opening angle), every enemy inside takes `damage` once (cap applies); `pellets` are cosmetic
-- tracers drawn inside the cone. spreadDegrees = machine-gun style random spread; pierce for rays;
-- splashRadius for projectiles that explode; chain = damage multipliers of a melee combo.
export type RangeWeaponVariant = {
	label: string,
	kind: "melee" | "ranged",
	shape: HitShape,
	range: number,
	arcDegrees: number?,
	width: number?,
	pad: number,
	cap: number,
	damage: number,
	rate: number,
	knockback: number,
	launch: number,
	pellets: number?,
	spreadDegrees: number?,
	pierce: number?,
	projectileSpeed: number?,
	splashRadius: number?,
	chain: { number }?,
	-- Melee only: the LAST chain hit uses this arc instead (360 = a full spin).
	finisherArcDegrees: number?,
	-- P2 bows. A ranged "ray" with projectileSpeed > 0 is a flying arrow that hits along its path.
	-- pierce = TOTAL enemies one projectile (or ray) can hit, everywhere (review ruling; 0 = 1); a "sphere" projectile explodes on contact
	-- (launcher). gravity = studs/s² of arrow drop. Charge weapons: hold to draw for up to
	-- chargeSeconds; damage scales from minChargeFraction to 1; a FULL charge also bursts
	-- blastRadius at the arrow's end for damage x blastDamageMult. Split arrows: after
	-- splitDistance studs the arrow becomes splitCount arrows fanned across splitArcDegrees, each
	-- hitting one enemy (plus pierce).
	gravity: number?,
	chargeSeconds: number?,
	minChargeFraction: number?,
	blastRadius: number?,
	blastDamageMult: number?,
	splitCount: number?,
	splitDistance: number?,
	splitArcDegrees: number?,
	-- P3 (INTERFACES "P3 contracts"). Chain Gun: every enemy the shot hits starts a chain that
	-- jumps chainCount times to the nearest enemy within chainRadius this shot has not hit yet,
	-- each jump dealing chainFalloff times the one before. bloomMult scales the bloom one shot
	-- adds (client only; nil = 1, 0 = none). continuous = a held beam: clients draw one lasting
	-- beam per shooter instead of a tracer per shot and merge its numbers.
	chainCount: number?,
	chainRadius: number?,
	chainFalloff: number?,
	bloomMult: number?,
	continuous: boolean?,
}
-- P3: a family's ability (docs/WEAPONS.md §2), cast with Q (melee slot) / E (ranged slot). id
-- picks the mechanic in AbilityService and name is the label; both are structural (untunable).
-- Every cooldown is scaled by abilities.cooldownScale; each kill by the caster takes
-- killRefundSeconds off BOTH slots' remaining cooldowns, never below cast + minCooldownSeconds.
-- What each optional field means for each id is the table in INTERFACES "P3 contracts".
export type RangeAbilityDef = {
	id: string,
	name: string,
	cooldownSeconds: number,
	minCooldownSeconds: number,
	killRefundSeconds: number,
	damage: number?,
	pad: number?,
	cap: number?,
	knockback: number?,
	launch: number?,
	radius: number?,
	range: number?,
	castRange: number?,
	arcDegrees: number?,
	width: number?,
	height: number?,
	delaySeconds: number?,
	durationSeconds: number?,
	tickSeconds: number?,
	count: number?,
	spacing: number?,
	falloff: number?,
	pull: number?,
	pierce: number?,
	targets: number?,
	speed: number?,
	gravity: number?,
	blastRadius: number?,
	blastDamageMult: number?,
	rateMult: number?,
	moveSpeedMult: number?,
}
-- P2: one weapon FAMILY (docs/WEAPONS.md). slot decides which Armory slot it fills; era is the
-- era that unlocks it (range ignores it); variants are range alternatives, default = shipped one.
-- P3: ability is family-level (every variant shares it).
export type RangeWeaponDef = {
	name: string,
	slot: "melee" | "ranged",
	era: number,
	default: string,
	variants: { [string]: RangeWeaponVariant },
	ability: RangeAbilityDef?,
}
-- P3: the range-wide ability switches.
export type RangeAbilitiesConfig = {
	-- Multiplies every cooldown and its floor: 1 = as tuned, 0 = no cooldowns (range testing).
	cooldownScale: number,
	-- A cast may arrive this many seconds before the server's ready time and still count.
	earlySeconds: number,
	-- Review round (P3): a cast may arrive this early before the caster's busy window ends
	-- (client clock slack), and Impale Dash stops this many studs short of a wall.
	busyEarlySeconds: number,
	dashWallClearance: number,
}
-- The family chosen for each slot plus the variant chosen per family.
export type RangeLoadout = { melee: string, ranged: string, variants: { [string]: string } }
-- A crowd enemy kind: body sphere (radius, centre at height/2) + head sphere (crit weak point).
export type CrowdKindDef = {
	radius: number,
	headRadius: number,
	height: number,
	speed: number,
	hp: number,
	color: { number },
	knockbackMult: number,
	-- Flat damage removed from every hit: dealt = max(amount - armor, amount * crowd.armorFloor).
	armor: number,
}
-- behaviour: idle = stands; walk = paces a line; strafe = side to side; jump = hops; chase = runs
-- at the nearest player (the stress test).
export type DummyGroupDef = {
	kind: string,
	behaviour: "idle" | "walk" | "strafe" | "jump" | "chase",
	count: number,
	-- Centre {x, z} in arena coordinates and the spacing of the packed grid / row.
	at: { number },
	spacing: number,
	respawnSeconds: number,
}
export type RangeMovementConfig = {
	jumpHeight: number,
	doubleJumpHeight: number,
	walkSpeed: number,
	dashDistance: number,
	dashSeconds: number,
	dashCooldown: number,
	dashIframes: number,
	slamMinHeight: number,
	slamRadius: number,
	slamDamage: number,
	slamCooldown: number,
	slamPad: number,
	slamKnockback: number,
	slamLaunch: number,
	slamFallSpeed: number,
	airAttackHangSeconds: number,
	-- Review round (P1): air swings reach this far BELOW the root; second-jump delay; slam grace;
	-- the minimum downward speed the server must see for a slam (a real dive, not any landing);
	-- camera height follow while airborne.
	airSwingReachDown: number,
	airJumpDelay: number,
	slamLandingGrace: number,
	slamMinDiveSpeed: number,
	cameraFollowRate: number,
	cameraMaxLag: number,
}
export type RangeShootingConfig = {
	bloomMinDegrees: number,
	bloomMaxDegrees: number,
	bloomMovePerSecond: number,
	bloomPerShot: number,
	bloomRecoverPerSecond: number,
	firstShotSeconds: number,
	adsFieldOfView: number,
	adsBloomMult: number,
	adsSpeedMult: number,
	originPad: number,
	critMult: number,
	-- Speed above which a character counts as moving for bloom; server origin check adds
	-- rootSpeed x (ping + originLagSeconds) to originPad.
	bloomMovingSpeed: number,
	originLagSeconds: number,
	-- Projectile lifetime (server and client) and how far each split child is jittered, as a
	-- share of the gap between children.
	projectileMaxSeconds: number,
	fanJitterShare: number,
	-- Review round (P3): shots of banked credit a slot may fire back to back after a pause
	-- (network jitter), on top of the one its rate allows.
	rateBurstShots: number,
}
-- touchMode: "autoFire" = attacks fire while the target is under the crosshair / in the hitbox;
-- "tapFire" = a tap anywhere on the right half attacks.
export type RangeControlsConfig = {
	touchMode: "autoFire" | "tapFire",
	autoFireAssistDegrees: number,
	autoSwingPad: number,
	tapMaxSeconds: number,
	tapMaxPixels: number,
	tapBufferSeconds: number,
	-- Extra width on auto-fire targets to cover the renderer's interpolation lag.
	assistLagPad: number,
	-- Melee combo resets on the server after this long without a swing.
	comboResetSeconds: number,
}
-- Each feedback layer's strength, 0 = off, 1 = default; values > 1 exaggerate.
export type RangeFeedbackConfig = {
	hitMarker: number,
	numbers: number,
	enemyFlash: number,
	enemyReaction: number,
	hitboxEffect: number,
	hitstop: number,
	shake: number,
	edgeFlash: number,
	haptics: number,
	counters: number,
}
export type ProvingGroundsConfig = {
	version: number,
	arena: string,
	crowd: {
		kinds: { [string]: CrowdKindDef },
		snapshotHz: number,
		maxAlive: number,
		stressCount: number,
		-- Dummy motion. walkLength = the whole pace line along Z; strafeWidth = the whole side-to-
		-- side span along X; hopHeight in studs; periods in seconds; chaseStandoff = studs beyond
		-- the enemy's own radius where a chaser stops short of the player's root.
		behaviour: {
			walkLength: number,
			strafeWidth: number,
			strafePeriod: number,
			hopHeight: number,
			hopPeriod: number,
			chaseStandoff: number,
			-- Return-home pace (share of speed), arrival slack in studs, walk pace (share of speed).
			homePace: number,
			homeTolerance: number,
			walkPace: number,
		},
		-- Seconds a corpse stays in the dead state before CrowdRemove.
		deadSeconds: number,
		-- Stagger seconds at knockbackMult 1 (scaled by the kind's knockbackMult).
		staggerSeconds: number,
		-- Ground friction on knockback (studs/s²) and the cap on stacked knockback speed (studs/s).
		knockFriction: number,
		knockMax: number,
		-- Share of every hit that always gets through armour: max(amount - armor, amount * armorFloor).
		armorFloor: number,
	},
	-- Keyed by family id (broadsword, warhammer, spinblade, greataxe, spear, longbow, splitbow,
	-- shotgun, rifle, launcher, P3: smg, beam, chaingun); loadout = the families a player starts
	-- the range with.
	weapons: { [string]: RangeWeaponDef },
	loadout: { melee: string, ranged: string },
	dummySets: { [string]: { DummyGroupDef } },
	defaultSet: string,
	movement: RangeMovementConfig,
	shooting: RangeShootingConfig,
	controls: RangeControlsConfig,
	feedback: RangeFeedbackConfig,
	abilities: RangeAbilitiesConfig,
}

-- World.json v1 mirror (M13 wave 1, docs/INTERFACES.md "M13 contracts"); field names follow the
-- JSON keys exactly. Colours are RGB 0-255 and materials are Enum.Material names, as in
-- FabricPadLookConfig. Every block is optional: absent means that feature stays as it was before
-- M13. Each `lighting` key is optional as well: absent leaves that Lighting property alone.
export type WorldLightingConfig = {
	clockTime: number?,
	geographicLatitude: number?,
	brightness: number?,
	ambient: { number }?,
	outdoorAmbient: { number }?,
	exposureCompensation: number?,
}
export type WorldAtmosphereConfig = {
	density: number,
	offset: number,
	color: { number },
	decay: { number },
	glare: number,
	haze: number,
}
export type WorldCloudsConfig = { cover: number, density: number, color: { number } }
-- `side` is the wanted side of the ground square in studs; WorldPlan.GroundSide bounds it.
export type WorldGroundConfig = { material: string, color: { number }, side: number }
-- `radius` must exceed Game.json's hubRadius; `height` is how far the surround's top stands above
-- the ground top (0 < height < plotSize.Y).
export type WorldHubSurroundConfig = {
	radius: number,
	height: number,
	material: string,
	color: { number },
}
export type WorldHubConfig = {
	material: string,
	color: { number },
	surround: WorldHubSurroundConfig?,
}
-- `width` in studs; `lift` is how far a strip's top stands above the ground top. A strip starts at
-- the hub wall and runs under the surround, so `lift` must be lower than `hub.surround.height`:
-- with a surround built and `lift` not below it, no roads are built.
export type WorldRoadsConfig = { width: number, lift: number, material: string, color: { number } }
-- M13 wave 2. `segments` flat invisible Parts in a ring, their inner faces tangent to Valley.json's
-- wallRadius, standing from the ground top to `height` (studs above it), `thickness` deep.
export type WorldValleyWallConfig = { height: number, thickness: number, segments: number }
-- The two apron bands' colours for one era (RGB 0-255).
export type WorldValleyApronConfig = { inner: { number }, outer: { number } }
-- `aprons` is keyed by era name; an era with no entry hides both bands. `skirtMargin` is the extra
-- studs around the river channel in the client's skirt rule.
export type WorldValleyConfig = {
	wall: WorldValleyWallConfig,
	aprons: { [string]: WorldValleyApronConfig },
	skirtMargin: number,
}
export type WorldConfig = {
	version: number,
	lighting: WorldLightingConfig?,
	atmosphere: WorldAtmosphereConfig?,
	clouds: WorldCloudsConfig?,
	ground: WorldGroundConfig?,
	hub: WorldHubConfig?,
	roads: WorldRoadsConfig?,
	valley: WorldValleyConfig?,
}

-- Valley.json v1 mirror (M13 wave 2, docs/INTERFACES.md "Wave 2 — the Valley meshes"). The file is
-- generated by tools/world/valley.py and never hand-edited; Luau reads it and never recomputes the
-- river, the bridges or the wall. X and Z are world studs; every height (`overlayLift`, `deckTop`,
-- `top`) is studs above the ground top, which is world Y = -plotSize.Y.
-- "world": one clone, at generator coordinates. "plot": one clone per plot, in the plot's own
-- frame (origin at the plot centre, -Z toward the hub).
export type ValleyFrame = "world" | "plot"
-- One template to place, ServerStorage.Assets.World.Valley.<name>. `required` absent means false:
-- a missing required mesh sends the whole world back to the wave 1 look, a missing optional one is
-- only left out. `tint` (plot frame only) names the World.json `valley.aprons` colour the mesh
-- takes from its plot's era: "apronInner" or "apronOuter".
export type ValleyMesh = { name: string, frame: ValleyFrame, required: boolean?, tint: string? }
-- `x`, `z` is the deck's centre. `yaw` is radians about +Y: 0 lays the long axis along +X and it
-- turns toward +Z. `length` is the deck alone; a ramp of run `rampLength` falls from `deckTop` to
-- the ground top at each end.
export type ValleyBridge = {
	x: number,
	z: number,
	yaw: number,
	length: number,
	width: number,
	deckTop: number,
	deckThickness: number,
	rampLength: number,
}
-- An upright cylinder standing on the ground top, its top at `top`.
export type ValleyStone = { x: number, z: number, radius: number, top: number }
export type ValleyPlan = {
	version: number,
	-- The ring the meshes were baked for; a live ring of another size keeps the wave 1 world.
	plotCount: number,
	ringRadius: number,
	planHash: string,
	overlayLift: number,
	wallRadius: number,
	-- Every template to place, in order.
	meshes: { ValleyMesh },
	bridges: { ValleyBridge },
	stones: { ValleyStone },
	-- Channel samples [x, z, halfWidth] along the river's centreline, pond included, from the wall
	-- inward only; halfWidth covers the visible water plus its bank. For the client's skirt rule.
	river: { { number } },
}

-- Crowd replication. CrowdSpawn (reliable) introduces an enemy once; CrowdSnapshot (unreliable,
-- buffer via CrowdCodec) carries every live enemy at crowd.snapshotHz; CrowdRemove ends it.
export type CrowdState = "idle" | "move" | "windup" | "stagger" | "airborne" | "dead"
export type CrowdSpawnInfo = { id: number, kind: string, maxHp: number }
export type CrowdSnapshotEntry = {
	id: number,
	position: Vector3,
	yaw: number,
	state: CrowdState,
	hpFraction: number,
}
-- One resolved attack, sent to every client in the range: draws the hitbox effect, the numbers
-- burst, markers and reactions. origin/direction are the shape's frame; size = range or radius.
export type StrikeHit = { id: number, amount: number, crit: boolean, killed: boolean }
export type CombatFxStrike = {
	kind: "strike",
	userId: number,
	weapon: string,
	variant: string,
	shape: HitShape,
	origin: Vector3,
	direction: Vector3,
	size: number,
	arcDegrees: number?,
	width: number?,
	endPoint: Vector3?,
	hits: { StrikeHit },
	-- Gun attacks: the attack seq, so clients can redraw the exact pellets with HitShapes.Pellets.
	seq: number?,
	-- P3: the ability id when an ability dealt this strike (weapon = its family). tick = one
	-- repeat of a lasting ability or a held beam: clients skip the generic hitbox flash (the
	-- lasting visual already shows the area) and soften hitstop and shake. links = chain
	-- lightning as flat pairs of enemy ids {from1, to1, from2, to2, ...}; 0 = the strike origin.
	ability: string?,
	tick: boolean?,
	links: { number }?,
}
-- P3: an ability was cast (range). Sent to everyone so every client draws its lasting visual;
-- damage still arrives as CombatFxStrike. origin = the caster's root at the cast; direction =
-- the unit aim (flattened for melee abilities); target = the resolved ground point of an aimed
-- ability (zones, leap), the end of a dash, or the floor centre of the Earthquake rings. startsAt = workspace:GetServerTimeNow() of the
-- cast; seq = the salted seed of any scatter (cluster bomblets). cancel = it ended early
-- (family switched, player left): stop its visuals.
export type CombatFxCast = {
	kind: "cast",
	userId: number,
	weapon: string,
	ability: string,
	origin: Vector3,
	direction: Vector3,
	target: Vector3?,
	startsAt: number,
	seq: number,
	cancel: boolean?,
}
-- P3: the caster's cooldowns, in workspace:GetServerTimeNow() seconds. readyAt = castable again;
-- floorAt = the earliest readyAt kill refunds can reach; busyUntil = the caster is locked in an
-- ability (channel, leap, dash, windup) until then. ability = "" when the family has none.
export type RangeAbilitySlotState = { ability: string, readyAt: number, floorAt: number }
-- refusedSeq (review round): set only on the answer to a refused cast, so the client cancels
-- that cast's local effects at once instead of waiting for a timeout.
export type RangeAbilityState = {
	melee: RangeAbilitySlotState,
	ranged: RangeAbilitySlotState,
	busyUntil: number,
	refusedSeq: number?,
}
-- P3, server only: one ability hit handed to RangeService.Strike. size = radius (sphere) or reach
-- (arc, cone, ray, capsule); capsule/ray width is the FULL width; a capsule runs origin →
-- endPoint (else origin + direction * size). knockback pushes away from the origin (along
-- direction for capsule and ray); pull > 0 pushes TOWARD the origin instead. crit: rays test the
-- head sphere. exclude: ids skipped, and every id hit is added (one sweep hits each enemy once).
-- chain: every enemy hit starts a chain (as the Chain Gun). cast = the cast id the readout sums.
-- airReach (review round): an arc around the caster's own root reaches down
-- movement.airSwingReachDown while the caster is airborne, exactly like a melee swing.
export type AbilityStrikeSpec = {
	shape: HitShape,
	origin: Vector3,
	direction: Vector3,
	size: number,
	arcDegrees: number?,
	width: number?,
	endPoint: Vector3?,
	pad: number,
	cap: number,
	damage: number,
	knockback: number,
	launch: number,
	pull: number?,
	crit: boolean?,
	exclude: { [number]: boolean }?,
	chain: { count: number, radius: number, falloff: number }?,
	tick: boolean?,
	airReach: boolean?,
	cast: number,
}
-- Studio tuning: a dot path into ProvingGroundsConfig ("weapons.rifle.variants.A.damage") → value.
export type TuneValue = number | boolean | string
export type TuneOverrides = { [string]: TuneValue }
-- Readouts for the range HUD, sent to the attacker after each attack and at 2 Hz.
export type RangeStats = {
	lastHits: number,
	lastKills: number,
	dps: number,
	clearSeconds: number?,
	alive: number,
	serverFrameMs: number,
	-- True on the attacker's copy when the server refused the attack (origin/rate), so the client
	-- drops the effects it already drew for it.
	refused: boolean?,
	-- P3: the latest ability cast's id and its running totals (every tick of a lasting ability
	-- adds to them); nil until the first cast. Normal attacks never touch these.
	ability: string?,
	abilityHits: number?,
	abilityKills: number?,
}

return {}
