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
export type CityEraVehiclesConfig = { props: { string }, perPlot: number, speed: number }
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
export type ParkedConfig = { props: { string }, perTier: { number } }
export type PedestrianConfig = {
	firstTier: number,
	perTier: { number },
	offset: number, -- studs off the street centreline, both sides
	clearance: number?, -- studs walkers keep from any solid (absent = the client's default)
	speed: number,
	bobHeight: number,
	bobHz: number,
	props: { string },
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
export type CombatAnimationsConfig = {
	enemyIdle: number,
	enemyWalk: number,
	enemyAttack: number,
	enemyDeath: number,
}
-- Studio-only levers, named here so no attribute name is duplicated in code.
export type CombatDebugConfig = {
	missionAttribute: string,
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
	attackWindupSeconds: number,
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
}

-- Missions/<eraIndex>_<EraName>.json v1, resolved by numeric prefix like era configs.
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
export type BossDef = {
	template: string,
	enemy: string,
	hpMult: number,
	damageMult: number,
	cashMult: number,
	materialsMult: number,
	valor: number,
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
export type CombatFx =
	CombatFxHit
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

return {}
