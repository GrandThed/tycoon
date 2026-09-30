--!strict
-- M12 growing city: one plot's city fabric (docs/INTERFACES.md "M12 contracts — Client";
-- docs/CITY_GROWTH.md section 2). Around the landmarks the player buys, parcels of ordinary houses,
-- workshops and fields develop on their own, the wild land recedes from the town, the next pad is
-- staked out as a building site, and (wave 1c) street-only upgrade slots dress whatever has
-- developed in layers of town trees, flower beds and banners. How far the town has grown is a pure
-- function of what the server replicates -- the owned set, each building's visible stage,
-- GrowthTier and the drawn streets -- through CityFabric, so every client and tools/cityfabric.py
-- agree on it. Only the pace is local: on a near plot a purchase ripples outward as staggered
-- building sites that become buildings seconds later, while a join, a restore, a rebuild or a far
-- plot shows the finished state at once.
--
-- The controller makes a Handle only for an era with both fabric data and a `fabric` config block,
-- syncs it right after the roads in every pass, and destroys it with the build, which cancels every
-- pending timer, animation and puff. Config and data are validated once, in Fabric.new: a missing
-- or malformed block, prop list, entry or template is an absent item or feature and never an
-- Output line, and every sync retries the spawns a late template skipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))
local Catalog = require(sharedFolder:WaitForChild("Catalog"))
local CityFabric = require(sharedFolder:WaitForChild("CityFabric"))

local uiFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(uiFolder:WaitForChild("Theme"))
local Motion = require(uiFolder:WaitForChild("Motion"))
local PropFactory = require(script.Parent:WaitForChild("PropFactory"))
local Scatter = require(script.Parent:WaitForChild("Scatter"))
local Dust = require(script.Parent:WaitForChild("Dust"))

-- Contract vocabulary (docs/INTERFACES.md "M12 contracts — Data").
local SMALL = "small"
local MEDIUM = "medium"
local NARROW = "narrow" -- round 2: 4-stud terraced frontage
local CLUMP = "clump"
local SINGLE = "single"
-- The numeric fields `pull` must carry, finite, before the pure CityFabric may read it.
local PULL_NUMBERS = { "radius", "tierTerm", "reach", "levelsOverTier", "smallMaxLevel" }
-- What a parcel shows at level 1, and at level 2 and up.
local SITE = "site"
local BUILDING = "building"
-- The waits a parcel on a near plot can be in; see `fire`.
local TIMER_SITE = "site"
local TIMER_BUILD = "build"
local TIMER_SWAP = "swap"
-- Wave 1c upgrade layers (town trees, flowers, banners): what an entry is anchored to, the level
-- at which a parcel's house stands (an entry on a parcel waits for it), and the waits an entry on a
-- near plot can be in (see `fireUpgrade`).
local ANCHOR_STRETCH = "stretch"
local ANCHOR_PARCEL = "parcel"
local BUILT_LEVEL = 2
local UPGRADE_APPEAR = "appear"
local UPGRADE_GROW = "grow"
-- How a placement shows itself.
local EFFECT_NONE = "none"
local EFFECT_DUST = "dust"
local EFFECT_RISE = "rise"
local EFFECT_POP = "pop"
-- A clump is four turned copies of its quarter prop; one cleared bit per quarter.
local QUARTERS = 4
local ALL_QUARTERS = 15
local QUARTER_TURN_DEGREES = 90
-- A rect's corners in order round it, as signs on its half extents.
local CORNER_SIGNS = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
-- The reveal scaffold is authored at 9x9 studs, the standard building footprint, and the contract
-- scales it by footprint / 9.
local REVEAL_DESIGN_STUDS = 9
-- Seeded construction times draw from a stream of their own: wave 2c's salts are 7001-7004
-- (Scatter) and the fabric's flocks take 7005 (Ambient).
local CONSTRUCTION_SALT = 7006
-- A staked-out site's look (the colours are config): surveyor's stakes at the footprint corners
-- and a taut string between them, sized to read from the tycoon camera rather than tuned.
local STAKE_WIDTH = 0.3
local STAKE_HEIGHT = 1.4
local STRING_THICKNESS = 0.08
local STRING_HEIGHT = 1.1
-- A puff's Dust handle is destroyed once its burst and the particles it left are gone (Dust's
-- longest particle lives 0.7 s).
local DUST_LINGER_SECONDS = 1
-- Enum.EasingStyle.Back's standard overshoot, for a new building growing out of its site.
local BACK_OVERSHOOT = 1.70158
-- Clearing tests bucket the mask on a grid of this pitch, so a wild item is only measured against
-- the rects and segments near it. A lookup aid, not a tunable: any pitch gives the same answer.
local GRID_CELL = 16
local GRID_BIAS = 1024 -- keeps cell indices positive anywhere on the map
local GRID_ROW = 4096

type Rect = CityFabric.FabricRect
type Segment = CityFabric.FabricSegment
type Mask = CityFabric.FabricMask

-- What a parcel shows: its building site, or a building prop at a stage. Nil is wild land.
type Look = { kind: string, prop: string, stage: number }

type ParcelView = {
	index: number,
	parcel: Types.FabricParcel,
	rect: Rect, -- the footprint about its centre, margin 0
	-- `fabric.sizes` has a footprint for its size. Without one (an optional size such as `narrow`
	-- left out of config) the parcel never draws and clears nothing.
	sized: boolean,
	frame: CFrame, -- plot-local pivot: bottom-centre on (x, 0, z), facing rotationY
	-- Well formed and inside the budget of a near plot (budget.parcels) or of a far one
	-- (budget.parcelsFar); any other parcel never draws there.
	nearOk: boolean,
	farOk: boolean,
	goal: Look?, -- what its level says it shows now
	-- The last develop moved the goal, so a ripple plays it. A goal that stood still but only now
	-- draws (the plot came near, past the far budget) is placed at once.
	changed: boolean,
	shown: Look?, -- what stands (or would, were its template there)
	model: Model?,
	timer: thread?, -- a pending transition; it shows the newest goal when it fires
}

type WildView = { whole: Model?, quarters: { [number]: Model }, single: Model? }

-- Wave 1c: one entry of an upgrade layer (a town tree, a flower bed, a banner). `planted` follows
-- ownership and the anchor on near and far plots alike, so an entry placed while nobody watched
-- appears at once when its plot comes near.
type UpgradeView = {
	index: number, -- its index in the layer's data list
	item: Types.FabricUpgradeItem,
	frame: CFrame, -- plot-local: its base on (x, 0, z), turned rotationY
	prop: string?, -- the layer's props[variant]; nil draws nothing
	planted: boolean,
	kept: boolean, -- not thinned out by City detail off
	goal: number?, -- the stage the tier gives it; nil while unplanted
	shown: number?,
	model: Model?,
	timer: thread?, -- a pending wave or growth step; it shows the newest goal when it fires
}

-- Wave 1c round 3: one upgrade layer, its config validated, its entries in data order.
type UpgradeLayer = {
	name: string,
	config: Types.FabricUpgradeLayerConfig,
	views: { UpgradeView },
}

type PadView = {
	part: BasePart,
	-- The server's look, put back when the fabric goes before the pad does (an era rebuild).
	material: Enum.Material,
	color: Color3,
	marker: Model?,
	stakes: { BasePart }, -- stakes and strings
	-- Running while the pad is gone: the dressing waits one lod.refreshSeconds for a cosmetics
	-- refresh to lay a new pad down before it goes too.
	expiry: thread?,
}

type Reveal = { model: Model, rect: Rect, timer: thread? }

-- One dust puff: a Dust handle of its own (a handle plays one burst at a time) and the timer that
-- destroys it once the burst and its particles are gone.
type Puff = { dust: Dust.Handle, cleanup: thread? }

type Animation = {
	owner: Handle,
	model: Model,
	pivot: CFrame, -- world frame the parts scale about (the prop's bottom-centre)
	parts: { BasePart },
	sizes: { Vector3 },
	offsets: { CFrame }, -- each part relative to `pivot` at full size
	kind: string, -- EFFECT_RISE | EFFECT_POP
	seconds: number,
	elapsed: number,
}

type Grid = { cells: { [number]: { number } }, mask: Mask }

export type Context = {
	folder: Instance, -- the plot's dressing folder
	plotFrame: CFrame, -- the plot base's top-centre
	eraName: string,
	seed: number, -- Scatter.Seed(plotIndex, eraName)
	layout: Types.EraLayout,
	config: Types.FabricConfig,
	data: Types.FabricData,
	budget: Types.CityBudgetConfig,
	-- Scatter.Solids of the plot: the slot, pad and plaza keep-outs, read from the one module that
	-- measures harvested extents.
	solids: { Scatter.Footprint },
	-- RoadGraph.EntrancePoint: where a ripple spreads from when no purchase started it.
	entrance: Vector3?,
	dustWidth: number, -- the era road width, which sizes a puff like the path dust
	dustColor: () -> Color3, -- the plot's live road colour
	-- How far below the plot top the ground outside the base lies (the base rests on it), which is
	-- where a skirt entry stands.
	groundDrop: number,
	-- lod.refreshSeconds: how long a pad's dressing outlives the pad.
	padGraceSeconds: number,
}

export type SyncInput = {
	tier: number,
	owned: { string }, -- sorted
	stages: { [string]: number }, -- owned slot -> its visible Stage<n> (0 without one)
	-- RoadGraph.FabricNetwork: visible stretches by piece id, join nodes, street segments.
	stretches: { [string]: CityFabric.FabricStretch },
	joins: { [string]: number },
	segments: { Segment },
	pads: { [string]: BasePart }, -- slot -> its buy pad in the live Pads folder (dressing only)
	plazas: { number }, -- layout indices of the plazas showing now
	near: boolean,
	-- The controller's purchase flag: near, settled, and not a restore (a bulk change).
	animate: boolean,
	wildShare: number, -- detailPolicy: the share of the wild layer kept, thinned by index
	upgradeShare: number, -- detailPolicy: the share of every upgrade layer kept, thinned by index
}

export type Handle = {
	context: Context,
	-- Config as validated in Fabric.new; nil where a block is missing or malformed, which turns
	-- that feature off.
	pull: Types.FabricPullConfig?,
	clear: Types.FabricClearConfig?,
	wildConfig: Types.FabricWildConfig?,
	timing: Types.FabricConstructionConfig?,
	maxPuffs: number?, -- concurrent puffs; nil means no cap
	-- The data as validated: a malformed parcel is a blank that never develops (keeping every index),
	-- a malformed wild entry is skipped where it stands.
	parcelData: { Types.FabricParcel },
	wildData: { Types.FabricWild },
	wildValid: { [number]: boolean },
	parcels: { ParcelView }, -- parcel i at index i; empty without `sizes`
	durations: { number }, -- parcel -> seeded construction seconds
	-- Wave 1c round 3: the upgrade layers with both a valid config and data, in name order.
	layers: { UpgradeLayer },
	parcelUpgrades: { [number]: { UpgradeView } }, -- parcel index -> every entry anchored to it
	slotRects: { [string]: Rect },
	padRects: { [string]: Rect },
	plazaRects: { [number]: Rect },
	slotFrames: { [string]: CFrame }, -- plot-local anchor frames
	streetOnly: { [string]: boolean },
	modelNames: { [string]: string },
	slotOrder: { string }, -- the era's slots in purchase order
	requires: { [string]: string }, -- effective `requires` (PlotService's rule)
	heights: { [string]: { number } }, -- memoised stage heights, "p:<prop>" and "b:<modelName>"
	wildNear: { [number]: boolean }, -- entries inside budget.wild
	wildFar: { [number]: boolean }, -- clumps inside budget.wildFar
	dustGap: number, -- a puff's gap limit: the longest rect side it can run round, plus a stud
	-- Live.
	states: { CityFabric.FabricParcelState },
	stretches: { [string]: CityFabric.FabricStretch },
	-- Every slot seen owned in this build and the highest stage seen on each: within an era both only
	-- grow, and a building missing for a moment (a cosmetics refresh respawns them all, replicated
	-- over several frames) must not tear the town down. A real removal rebuilds the whole plot.
	owned: { [string]: boolean },
	ownedList: { string }, -- sorted
	stages: { [string]: number },
	developKey: string,
	maskKey: string,
	cleared: { [number]: number }, -- wild entry -> cleared quarters (bit q - 1); a single is bit 0
	wild: { [number]: WildView },
	pads: { [string]: PadView },
	reveals: { Reveal },
	puffs: { Puff }, -- live puffs, oldest first
	lastTrigger: Vector3, -- plot-local; the last purchase or stage swap an animated sync saw
	destroyed: boolean,
}

local animations: { Animation } = {}
local heartbeat: RBXScriptConnection? = nil
-- Reused by every clearing lookup (none of them yields): the candidates near one wild item.
local scratchRects: { Rect } = {}
local scratchSegments: { Segment } = {}
local scratchSeen: { [number]: number } = {}
local scratchStamp = 0
local materialsByName: { [string]: Enum.Material }? = nil

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function numberOr(value: any, fallback: number): number
	return if finite(value) then value else fallback
end

-- A config entry by parcel size: sizes, sites and district prop lists all key small, medium and
-- (round 2, optional) narrow. Nil for a size the entry leaves out.
local function forSize<T>(size: string, small: T, medium: T, narrow: T?): T?
	if size == SMALL then
		return small
	elseif size == MEDIUM then
		return medium
	elseif size == NARROW then
		return narrow
	end
	return nil
end

local function materialNamed(name: any): Enum.Material?
	if type(name) ~= "string" then
		return nil
	end
	local lookup = materialsByName
	if lookup == nil then
		local built: { [string]: Enum.Material } = {}
		for _, item in Enum.Material:GetEnumItems() do
			built[item.Name] = item
		end
		lookup = built
		materialsByName = built
	end
	return (lookup :: { [string]: Enum.Material })[name]
end

local function colorFrom(rgb: any, fallback: Color3): Color3
	if type(rgb) ~= "table" then
		return fallback
	end
	local function channel(index: number): number
		return math.clamp(numberOr(rgb[index], 0), 0, 255)
	end
	return Color3.fromRGB(channel(1), channel(2), channel(3))
end

local function isTriple(value: any): boolean
	return type(value) == "table"
		and type(value[1]) == "number"
		and type(value[2]) == "number"
		and type(value[3]) == "number"
end

-- ------------------------------------------------------------------ validation

-- `pull` as CityFabric may use it -- five finite numbers and an array of finite thresholds, copied
-- so no stray key reaches the trusting pure module -- or nil, which keeps every parcel at level 0.
local function validPull(pull: any): Types.FabricPullConfig?
	if type(pull) ~= "table" then
		return nil
	end
	for _, key in PULL_NUMBERS do
		if not finite(pull[key]) then
			return nil
		end
	end
	local thresholds = pull.thresholds
	if type(thresholds) ~= "table" then
		return nil
	end
	local count = 0
	for key, value in thresholds do
		if type(key) ~= "number" or not finite(value) then
			return nil
		end
		count += 1
	end
	-- Holes or fractional keys leave the count and the length apart.
	if count ~= #thresholds then
		return nil
	end
	-- Wave 1c: `rowLag` may be left out (CityFabric then holds a back row 1 level behind the one in
	-- front), but one that is there must be a whole number of levels, 0 or more.
	local rowLag = pull.rowLag
	if rowLag ~= nil and not (finite(rowLag) and rowLag >= 0 and rowLag == math.floor(rowLag)) then
		return nil
	end
	return {
		radius = pull.radius,
		tierTerm = pull.tierTerm,
		thresholds = table.clone(thresholds),
		reach = pull.reach,
		levelsOverTier = pull.levelsOverTier,
		smallMaxLevel = pull.smallMaxLevel,
		rowLag = rowLag,
	}
end

-- A list of prop names kept by position, since a clump's variant is an index into it. Anything that
-- is not a name reads as a missing prop, and a missing list as an empty one.
local function propList(value: any): { string }
	local list: { string } = {}
	if type(value) == "table" then
		for index, name in value do
			if type(index) == "number" and type(name) == "string" then
				list[index] = name
			end
		end
	end
	return list
end

local function validWildConfig(wild: any): Types.FabricWildConfig?
	if type(wild) ~= "table" then
		return nil
	end
	return {
		clumps = propList(wild.clumps),
		quarters = propList(wild.quarters),
		quarterRadius = numberOr(wild.quarterRadius, 0),
		singleRadius = numberOr(wild.singleRadius, 0),
	}
end

-- Every field CityFabric reads and Fabric.new places by. Wave 1c: rows 1 to 3 only (a back row
-- repeats its front parcel's stretch and along).
local function validParcel(parcel: any): boolean
	return type(parcel) == "table"
		and finite(parcel.x)
		and finite(parcel.z)
		and finite(parcel.rotationY)
		and finite(parcel.along)
		and (parcel.row == 1 or parcel.row == 2 or parcel.row == 3)
		and finite(parcel.front)
		and type(parcel.stretch) == "string"
		and (parcel.size == SMALL or parcel.size == MEDIUM or parcel.size == NARROW)
end

-- Stands in for a malformed parcel: on no street, so it never develops, and later parcels keep
-- their indices (a row-2 parcel names its front parcel by index).
local function blankParcel(): Types.FabricParcel
	return {
		x = 0,
		z = 0,
		rotationY = 0,
		size = "small",
		stretch = "",
		along = 0,
		row = 1,
		front = 0,
	}
end

local function validWildEntry(entry: any): boolean
	if
		type(entry) ~= "table"
		or not (finite(entry.x) and finite(entry.z) and finite(entry.rotationY))
	then
		return false
	end
	return entry.kind == CLUMP or (entry.kind == SINGLE and type(entry.prop) == "string")
end

-- Wave 1c round 3: one upgrade layer's config, or nil (that layer off) when a field is missing or
-- bad: a slot to buy, a prop list, a whole `tierOffset` (so a stage is always whole), a whole
-- `budget` of 0 or more, and an optional `stagger` of 0 or more.
local function validUpgradeLayer(value: any): Types.FabricUpgradeLayerConfig?
	if
		type(value) ~= "table"
		or type(value.requiresSlot) ~= "string"
		or type(value.props) ~= "table"
	then
		return nil
	end
	local tierOffset, budget, stagger = value.tierOffset, value.budget, value.stagger
	if not finite(tierOffset) or tierOffset ~= math.floor(tierOffset) then
		return nil
	end
	if not finite(budget) or budget < 0 or budget ~= math.floor(budget) then
		return nil
	end
	if stagger ~= nil and not (finite(stagger) and stagger >= 0) then
		return nil
	end
	return {
		requiresSlot = value.requiresSlot,
		props = propList(value.props),
		tierOffset = tierOffset,
		stagger = stagger,
		budget = budget,
	}
end

-- An upgrade entry the renderer can place: a position, turn, variant and a positive scale,
-- anchored to a stretch by piece id or to a parcel by index. Any other entry is skipped where it
-- stands.
local function validUpgradeItem(entry: any): boolean
	if
		type(entry) ~= "table"
		or not (finite(entry.x) and finite(entry.z) and finite(entry.rotationY))
		or not (finite(entry.variant) and finite(entry.scale) and entry.scale > 0)
	then
		return false
	end
	if entry.anchor == ANCHOR_STRETCH then
		return type(entry.stretch) == "string"
	end
	return entry.anchor == ANCHOR_PARCEL and finite(entry.parcel)
end

-- ------------------------------------------------------------------ heights

-- Each stage's harvested height: max(offset.y + size.y / 2) minus min(offset.y - size.y / 2) over
-- the stage's parts ("What a parcel shows"), 0 for a stage with nothing measured. A glTF import
-- turns a mesh about Y only, so the Y offsets need no correction. Empty without an entry.
local function stageHeights(model: Types.AssetModel?): { number }
	local heights: { number } = {}
	if model == nil or type(model.stages) ~= "table" then
		return heights
	end
	for index, stage in model.stages do
		local top, bottom = -math.huge, math.huge
		if type(stage.parts) == "table" then
			for _, part in stage.parts do
				if isTriple(part.size) and isTriple(part.offset) then
					top = math.max(top, part.offset[2] + part.size[2] / 2)
					bottom = math.min(bottom, part.offset[2] - part.size[2] / 2)
				end
			end
		end
		heights[index] = if top >= bottom then top - bottom else 0
	end
	return heights
end

-- Assets.json models of the era: its props, or its landmark buildings.
local function assetModels(eraName: string, props: boolean): { [string]: Types.AssetModel }?
	local assets = Catalog.GetAssetsConfig()
	if assets == nil then
		return nil
	end
	if props then
		local propsByEra = assets.props
		return if propsByEra ~= nil then propsByEra[eraName] else nil
	end
	return assets.eras[eraName]
end

local function heightsOf(handle: Handle, key: string, model: Types.AssetModel?): { number }
	local cached = handle.heights[key]
	if cached == nil then
		cached = stageHeights(model)
		handle.heights[key] = cached
	end
	return cached :: { number }
end

local function propHeights(handle: Handle, prop: string): { number }
	local models = assetModels(handle.context.eraName, true)
	return heightsOf(handle, "p:" .. prop, if models ~= nil then models[prop] else nil)
end

-- A governor's harvested height at the stage it shows now; 0 without a template (the contract's H).
local function landmarkHeight(handle: Handle, slotId: string?): number
	local modelName = if slotId ~= nil then handle.modelNames[slotId] else nil
	if slotId == nil or modelName == nil then
		return 0
	end
	local models = assetModels(handle.context.eraName, false)
	local heights =
		heightsOf(handle, "b:" .. modelName, if models ~= nil then models[modelName] else nil)
	return heights[(handle.stages[slotId] or 0) + 1] or 0
end

-- ------------------------------------------------------------------ rects and clearing

-- A Scatter footprint as a clearing rect: its extents need not be centred on its origin, so the
-- rect's centre is the extents' middle carried into the plot.
local function footprintRect(footprint: Scatter.Footprint, rotationY: number): Rect
	local extents = footprint.extents
	local middle =
		Vector3.new((extents.minX + extents.maxX) / 2, 0, (extents.minZ + extents.maxZ) / 2)
	local centre = footprint.origin + footprint.rotation:VectorToWorldSpace(middle)
	return {
		x = centre.X,
		z = centre.Z,
		hx = (extents.maxX - extents.minX) / 2,
		hz = (extents.maxZ - extents.minZ) / 2,
		rotationY = rotationY,
		margin = 0,
	}
end

local function grown(rect: Rect, margin: number): Rect
	return {
		x = rect.x,
		z = rect.z,
		hx = rect.hx,
		hz = rect.hz,
		rotationY = rect.rotationY,
		margin = margin,
	}
end

-- The rect's corners, plot-local at Y 0, in order round it.
local function rectCorners(rect: Rect): { Vector3 }
	local rotation = CFrame.Angles(0, math.rad(rect.rotationY), 0)
	local centre = Vector3.new(rect.x, 0, rect.z)
	local corners: { Vector3 } = {}
	for _, sign in CORNER_SIGNS do
		table.insert(
			corners,
			centre
				+ rotation:VectorToWorldSpace(Vector3.new(sign[1] * rect.hx, 0, sign[2] * rect.hz))
		)
	end
	return corners
end

local function cellOf(value: number): number
	return math.floor(value / GRID_CELL) + GRID_BIAS
end

-- Buckets every rect by its bounding square (centre +- half diagonal + margin) and every segment by
-- its box grown by the street margin. A point within reach of an item always shares a cell with
-- it, so a lookup over the cells round the point sees every item that could clear it.
local function buildGrid(mask: Mask): Grid
	local cells: { [number]: { number } } = {}
	local function insert(id: number, x0: number, x1: number, z0: number, z1: number): ()
		for ix = cellOf(x0), cellOf(x1) do
			for iz = cellOf(z0), cellOf(z1) do
				local key = ix * GRID_ROW + iz
				local ids = cells[key]
				if ids == nil then
					ids = {}
					cells[key] = ids
				end
				table.insert(ids :: { number }, id)
			end
		end
	end
	for id, rect in mask.rects do
		local reach = math.sqrt(rect.hx * rect.hx + rect.hz * rect.hz) + math.max(rect.margin, 0)
		insert(id, rect.x - reach, rect.x + reach, rect.z - reach, rect.z + reach)
	end
	local rectCount = #mask.rects
	local street = math.max(mask.streetClear, 0)
	for index, segment in mask.segments do
		insert(
			rectCount + index,
			math.min(segment.ax, segment.bx) - street,
			math.max(segment.ax, segment.bx) + street,
			math.min(segment.az, segment.bz) - street,
			math.max(segment.az, segment.bz) + street
		)
	end
	return { cells = cells, mask = mask }
end

-- CityFabric.IsCleared over the part of the mask near the point, which answers exactly as the
-- whole mask would.
local function clearedAt(grid: Grid, x: number, z: number, radius: number): boolean
	local reach = math.max(radius, 0)
	local mask = grid.mask
	local rectCount = #mask.rects
	scratchStamp += 1
	table.clear(scratchRects)
	table.clear(scratchSegments)
	for ix = cellOf(x - reach), cellOf(x + reach) do
		for iz = cellOf(z - reach), cellOf(z + reach) do
			local ids = grid.cells[ix * GRID_ROW + iz]
			if ids == nil then
				continue
			end
			for _, id in ids do
				if scratchSeen[id] == scratchStamp then
					continue
				end
				scratchSeen[id] = scratchStamp
				if id <= rectCount then
					table.insert(scratchRects, mask.rects[id])
				else
					table.insert(scratchSegments, mask.segments[id - rectCount])
				end
			end
		end
	end
	if #scratchRects == 0 and #scratchSegments == 0 then
		return false
	end
	return CityFabric.IsCleared(x, z, radius, {
		rects = scratchRects,
		segments = scratchSegments,
		streetClear = mask.streetClear,
	})
end

-- ------------------------------------------------------------------ effects

-- One dust burst along `points` (plot-local, in order). Low-end devices get none (spec section
-- 10: particles go with the low-end signal, not with touch alone), and a plot plays at most
-- `maxPuffs` at once: past that, a new puff takes over the oldest one's handle.
local function puff(handle: Handle, points: { Vector3 }): ()
	local timing = handle.timing
	local cap = handle.maxPuffs
	if Theme.lowEndDevice or handle.destroyed or timing == nil or #points == 0 then
		return
	end
	if cap ~= nil and cap <= 0 then
		return
	end
	local context = handle.context
	local seconds = math.max(numberOr(timing.riseSeconds, 0), 0)
	local world: { Vector3 } = {}
	for _, point in points do
		table.insert(world, context.plotFrame:PointToWorldSpace(point))
	end
	local record: Puff
	if cap ~= nil and #handle.puffs >= cap then
		record = table.remove(handle.puffs, 1) :: Puff
		local cleanup = record.cleanup
		if cleanup ~= nil then
			record.cleanup = nil
			task.cancel(cleanup)
		end
	else
		record = {
			dust = Dust.Create(
				context.folder,
				context.plotFrame,
				context.dustWidth,
				handle.dustGap
			),
			cleanup = nil,
		}
	end
	-- A handle plays one burst at a time, so on a taken-over handle this cuts the old puff short.
	Dust.Burst(record.dust, world, context.dustColor(), seconds)
	table.insert(handle.puffs, record)
	record.cleanup = task.delay(seconds + DUST_LINGER_SECONDS, function()
		record.cleanup = nil
		local index = table.find(handle.puffs, record)
		if index ~= nil then
			table.remove(handle.puffs, index)
		end
		Dust.Destroy(record.dust)
	end)
end

-- Dust running once round a rect's edge: the base of a building going up or coming down.
local function puffAround(handle: Handle, rect: Rect): ()
	local corners = rectCorners(rect)
	table.insert(corners, corners[1])
	puff(handle, corners)
end

local function puffAt(handle: Handle, x: number, y: number, z: number): ()
	puff(handle, { Vector3.new(x, y, z) })
end

-- A far plot or a restore plays nothing, so puffs still running stop where they are.
local function stopPuffs(handle: Handle): ()
	for _, record in handle.puffs do
		Dust.Stop(record.dust)
	end
end

local function backOut(t: number): number
	local u = t - 1
	return 1 + (BACK_OVERSHOOT + 1) * u * u * u + BACK_OVERSHOOT * u * u
end

local function quadOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

-- The scale an animation shows at `t` in [0, 1). A rise grows out of the ground with the landmark
-- reveal's overshoot; a pop dips and overshoots like a landmark's stage pop (both looks from
-- Theme, so filler and landmarks move alike). Reduced motion runs both straight to full size.
local function scaleAt(kind: string, t: number): number
	if kind == EFFECT_RISE then
		local start = Theme.REVEAL_START_SCALE
		return start + (1 - start) * (if Theme.reducedMotion then t else backOut(t))
	end
	local start = Theme.STAGE_POP_START_SCALE
	if Theme.reducedMotion then
		return start + (1 - start) * t
	end
	local peak = Theme.STAGE_POP_PEAK_SCALE
	local peakAt = Theme.STAGE_POP_PEAK_FRACTION
	if t < peakAt then
		return start + (peak - start) * quadOut(t / peakAt)
	end
	return peak + (1 - peak) * quadOut((t - peakAt) / (1 - peakAt))
end

local function applyScale(animation: Animation, scale: number): ()
	for index, part in animation.parts do
		if part.Parent ~= nil then
			local offset = animation.offsets[index]
			part.Size = animation.sizes[index] * scale
			part.CFrame = animation.pivot * (offset.Rotation + offset.Position * scale)
		end
	end
end

local function step(dt: number): ()
	for index = #animations, 1, -1 do
		local animation = animations[index]
		animation.elapsed += dt
		if animation.elapsed >= animation.seconds then
			applyScale(animation, 1)
			table.remove(animations, index)
		else
			applyScale(animation, scaleAt(animation.kind, animation.elapsed / animation.seconds))
		end
	end
	local connection = heartbeat
	if #animations == 0 and connection ~= nil then
		connection:Disconnect()
		heartbeat = nil
	end
end

-- Scales a freshly spawned model about its bottom-centre over riseSeconds (shortened by reduced
-- motion), on the one Heartbeat every fabric shares while anything moves.
local function startAnimation(handle: Handle, model: Model, pivot: CFrame, kind: string): ()
	local timing = handle.timing
	local seconds = if timing ~= nil
		then Motion.Seconds(math.max(numberOr(timing.riseSeconds, 0), 0))
		else 0
	if seconds <= 0 then
		return
	end
	local animation: Animation = {
		owner = handle,
		model = model,
		pivot = pivot,
		parts = {},
		sizes = {},
		offsets = {},
		kind = kind,
		seconds = seconds,
		elapsed = 0,
	}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(animation.parts, descendant)
			table.insert(animation.sizes, descendant.Size)
			table.insert(animation.offsets, pivot:ToObjectSpace(descendant.CFrame))
		end
	end
	applyScale(animation, scaleAt(kind, 0))
	table.insert(animations, animation)
	if heartbeat == nil then
		heartbeat = RunService.Heartbeat:Connect(step)
	end
end

-- Drops the animations of one model (about to be destroyed) or of a whole handle.
local function stopAnimations(model: Model?, owner: Handle?): ()
	for index = #animations, 1, -1 do
		local animation = animations[index]
		if animation.model == model or animation.owner == owner then
			table.remove(animations, index)
		end
	end
end

local function spawnAt(
	handle: Handle,
	prop: string?,
	stage: number,
	frame: CFrame,
	scale: number?
): Model?
	local context = handle.context
	return PropFactory.Spawn(
		context.eraName,
		prop,
		stage,
		context.plotFrame * frame,
		context.folder,
		scale
	)
end

-- ------------------------------------------------------------------ parcels

local function sameLook(a: Look?, b: Look?): boolean
	if a == nil or b == nil then
		return a == b
	end
	return a.kind == b.kind and a.prop == b.prop and a.stage == b.stage
end

local function siteLook(handle: Handle, view: ParcelView): Look?
	local sites = handle.context.config.sites
	if type(sites) ~= "table" then
		return nil
	end
	local prop = forSize(view.parcel.size, sites.small, sites.medium, sites.narrow)
	return if type(prop) == "string" then { kind = SITE, prop = prop, stage = 0 } else nil
end

-- A district's non-empty prop list for a parcel size, or nil when it has none.
local function districtList(handle: Handle, district: string?, size: string): { string }?
	local districts = handle.context.config.districts
	if district == nil or type(districts) ~= "table" then
		return nil
	end
	local props = districts[district]
	if type(props) ~= "table" then
		return nil
	end
	local list = forSize(size, props.small, props.medium, props.narrow)
	return if type(list) == "table" and #list > 0 then list else nil
end

-- "What a parcel shows": nothing at level 0, the site at 1, and from 2 the district's prop for
-- this parcel at the highest stage its level allows that stays under the governor's height (and
-- never under the floor every stage 0 is built to). Round 2: a district without props for the
-- parcel's size lends `fallbackDistrict`'s; without those either the parcel shows nothing, so no
-- rise ever comes and the upgrades anchored to it go in without waiting.
local function goalFor(
	handle: Handle,
	view: ParcelView,
	state: CityFabric.FabricParcelState?
): Look?
	if state == nil or state.level <= 0 then
		return nil
	end
	if state.level == 1 then
		return siteLook(handle, view)
	end
	local config = handle.context.config
	local size = view.parcel.size
	local fallback = config.fallbackDistrict
	local list = districtList(handle, state.district, size)
		or districtList(handle, if type(fallback) == "string" then fallback else nil, size)
	if list == nil then
		return nil
	end
	local prop = list[(view.index - 1) % #list + 1]
	if type(prop) ~= "string" then
		return nil
	end
	local heights = propHeights(handle, prop)
	local stage = math.max(math.min(state.level - 2, #heights - 1), 0)
	local cap = math.max(numberOr(config.heightFloor, 0), landmarkHeight(handle, state.governor))
	while stage > 0 and heights[stage + 1] > cap do
		stage -= 1
	end
	return { kind = BUILDING, prop = prop, stage = stage }
end

local function ensureModel(handle: Handle, view: ParcelView): ()
	local shown = view.shown
	if view.model == nil and shown ~= nil then
		view.model = spawnAt(handle, shown.prop, shown.stage, view.frame, nil)
	end
end

-- Puts `look` on the parcel in place of whatever stood there. A puff marks only something that
-- actually appeared or went, so a missing template stays silent in every sense.
local function place(handle: Handle, view: ParcelView, look: Look?, effect: string): ()
	local old = view.model
	view.model = nil
	view.shown = look
	if old ~= nil then
		stopAnimations(old, nil)
		old:Destroy()
	end
	local model = if look ~= nil
		then spawnAt(handle, look.prop, look.stage, view.frame, nil)
		else nil
	view.model = model
	if effect == EFFECT_NONE or (model == nil and old == nil) then
		return
	end
	if model ~= nil and (effect == EFFECT_RISE or effect == EFFECT_POP) then
		startAnimation(handle, model, handle.context.plotFrame * view.frame, effect)
	end
	puffAround(handle, view.rect)
end

local function cancelTimer(view: ParcelView): ()
	local timer = view.timer
	if timer ~= nil then
		view.timer = nil
		task.cancel(timer)
	end
end

-- Forward-declared: a site that went up starts its building's timer.
local fire: (handle: Handle, view: ParcelView, kind: string) -> ()
-- Forward-declared (the upgrade layers come later in the file): a house that rose out of its site
-- brings the upgrade entries that were waiting for it.
local releaseParcelUpgrades: (handle: Handle, parcel: number) -> ()

local function startTimer(handle: Handle, view: ParcelView, kind: string, seconds: number): ()
	cancelTimer(view)
	view.timer = task.delay(math.max(seconds, 0), function()
		view.timer = nil
		if not handle.destroyed then
			fire(handle, view, kind)
		end
	end)
end

-- A transition comes due. It shows the parcel's goal as it stands now, not as it stood when the
-- wait began, so a target that rose meanwhile lands in one step.
fire = function(handle: Handle, view: ParcelView, kind: string): ()
	local goal = view.goal
	if goal == nil then
		-- Back to wild land while it waited; never within an era, but it must not leave a site.
		place(handle, view, nil, EFFECT_DUST)
		return
	end
	if kind == TIMER_SITE then
		local site = siteLook(handle, view)
		if not sameLook(view.shown, site) then
			place(handle, view, site, EFFECT_DUST)
		end
		if goal.kind == BUILDING then
			startTimer(handle, view, TIMER_BUILD, handle.durations[view.index] or 0)
		end
		return
	end
	if not sameLook(view.shown, goal) then
		place(handle, view, goal, if kind == TIMER_BUILD then EFFECT_RISE else EFFECT_POP)
	end
	if kind == TIMER_BUILD then
		releaseParcelUpgrades(handle, view.index)
	end
end

-- Sorts `items` nearest-first by straight-line distance from the nearest origin, ties by index, so
-- every staggered start -- sites, the planting wave, growth steps -- spreads outward from where the
-- change began. `locate` gives an item's x, z and index.
local function sortOutward<T>(
	items: { T },
	origins: { Vector3 },
	locate: (item: T) -> (number, number, number)
): ()
	local distances: { [T]: number } = {}
	local indices: { [T]: number } = {}
	for _, item in items do
		local x, z, index = locate(item)
		local best = math.huge
		for _, origin in origins do
			local dx, dz = x - origin.X, z - origin.Z
			best = math.min(best, dx * dx + dz * dz)
		end
		distances[item] = best
		indices[item] = index
	end
	table.sort(items, function(a: T, b: T): boolean
		if distances[a] == distances[b] then
			return indices[a] < indices[b]
		end
		return distances[a] < distances[b]
	end)
end

-- Where a ripple spreads from: this sync's purchases and stage swaps, else the last one seen (the
-- entrance until there is one).
local function rippleOrigins(handle: Handle, triggers: { Vector3 }): { Vector3 }
	return if #triggers > 0 then triggers else { handle.lastTrigger }
end

local function parcelSpot(view: ParcelView): (number, number, number)
	return view.rect.x, view.rect.z, view.index
end

-- Without animation -- a join, a restore, a rebuild, a far plot -- every parcel shows its goal at
-- once, or nothing where the plot's budget leaves it out (wave 1c: a far plot keeps only the
-- frontage nearest the heart).
local function settleParcels(handle: Handle, near: boolean): ()
	for _, view in handle.parcels do
		view.changed = false
		cancelTimer(view)
		local drawn = if near then view.nearOk else view.farOk
		local target = if drawn then view.goal else nil
		if sameLook(view.shown, target) then
			ensureModel(handle, view)
		else
			place(handle, view, target, EFFECT_NONE)
		end
	end
end

-- A purchase, a stage swap or a new tier on a near plot: new sites go up one by one outward from
-- the building that set them off, a site turns into its building after the parcel's seeded
-- construction time, and a building takes its next stage after `stageSeconds`, one by one outward
-- too, so a tier-up never swaps every house in one frame.
local function rippleParcels(
	handle: Handle,
	timing: Types.FabricConstructionConfig,
	triggers: { Vector3 }
): ()
	local starting: { ParcelView } = {}
	local swapping: { ParcelView } = {}
	for _, view in handle.parcels do
		local changed = view.changed
		view.changed = false
		if not view.nearOk or view.timer ~= nil then
			continue
		end
		local goal = view.goal
		local shown = view.shown
		if sameLook(shown, goal) then
			ensureModel(handle, view)
		elseif not changed then
			-- Its goal stood still and it only now draws: the plot came near, and a far plot leaves
			-- the back rows out. Placed as it is, since nothing happened to it.
			place(handle, view, goal, EFFECT_NONE)
		elseif goal == nil then
			place(handle, view, nil, EFFECT_DUST)
		elseif shown == nil then
			table.insert(starting, view)
		elseif goal.kind == SITE then
			place(handle, view, goal, EFFECT_DUST)
		elseif shown.kind == SITE then
			startTimer(handle, view, TIMER_BUILD, handle.durations[view.index] or 0)
		else
			table.insert(swapping, view)
		end
	end
	local origins = rippleOrigins(handle, triggers)
	local stagger = math.max(numberOr(timing.stagger, 0), 0)
	local stageSeconds = numberOr(timing.stageSeconds, 0)
	sortOutward(swapping, origins, parcelSpot)
	for rank, view in swapping do
		startTimer(handle, view, TIMER_SWAP, stageSeconds + (rank - 1) * stagger)
	end
	sortOutward(starting, origins, parcelSpot)
	for rank, view in starting do
		startTimer(handle, view, TIMER_SITE, (rank - 1) * stagger)
	end
end

local function develop(handle: Handle, input: SyncInput): { CityFabric.FabricParcelState }
	local pull = handle.pull
	if pull == nil then
		local states: { CityFabric.FabricParcelState } = {}
		for index = 1, #handle.parcelData do
			states[index] = { level = 0, district = nil, governor = nil }
		end
		return states
	end
	local slots = handle.context.layout.slots
	local landmarks: { CityFabric.FabricLandmark } = {}
	for _, slotId in handle.ownedList do
		local slotLayout = slots[slotId]
		local district = if slotLayout ~= nil then slotLayout.district else nil
		local node = input.joins[slotId]
		if district ~= nil and node ~= nil then
			table.insert(landmarks, { slotId = slotId, node = node, district = district })
		end
	end
	return CityFabric.Develop({
		tier = input.tier,
		stretches = input.stretches,
		landmarks = landmarks,
		parcels = handle.parcelData,
	}, pull)
end

-- Everything Develop and the height caps read: a change in any of them re-develops the town.
local function developKey(handle: Handle, input: SyncInput): string
	local parts: { string } = { tostring(input.tier) }
	for _, slotId in handle.ownedList do
		table.insert(parts, slotId .. "=" .. tostring(handle.stages[slotId] or 0))
	end
	-- Visible stretches only ever grow within a build, so their count names the set.
	local count = 0
	for _ in input.stretches do
		count += 1
	end
	table.insert(parts, tostring(count))
	return table.concat(parts, "|")
end

-- ------------------------------------------------------------------ the clearing mask

-- The slots whose pads the owned set implies: unowned, with the effective `requires` owned
-- (PlotService.refreshPads' rule). The mask takes its pad part from these rather than from the
-- live Pads folder, so a cosmetics refresh that re-lays every pad never un-clears the woods.
local function buyableSlots(handle: Handle): { string }
	local buyable: { string } = {}
	for _, slotId in handle.slotOrder do
		local requires = handle.requires[slotId]
		if not handle.owned[slotId] and (requires == nil or handle.owned[requires]) then
			table.insert(buyable, slotId)
		end
	end
	return buyable
end

-- Everything the mask is built from. The buyable slots follow from the owned set, and owned slots,
-- drawn streets and developed parcels only grow within a build, so listing them names the mask.
local function maskKeyOf(handle: Handle, input: SyncInput): string
	local developed: { string } = {}
	for index, state in handle.states do
		if state.level >= 1 then
			table.insert(developed, tostring(index))
		end
	end
	local plazas: { string } = {}
	for _, index in input.plazas do
		table.insert(plazas, tostring(index))
	end
	return table.concat({
		table.concat(handle.ownedList, ","),
		table.concat(developed, ","),
		table.concat(plazas, ","),
		tostring(#input.segments),
	}, "|")
end

-- The clearing mask ("Clearing", with the review amendment's pads): owned slot footprints, the
-- footprint and pad of every buyable slot, developed parcels, visible plazas, and the visible
-- stretches and drawn spurs.
local function buildMask(handle: Handle, clear: Types.FabricClearConfig, input: SyncInput): Mask
	local rects: { Rect } = {}
	local slotMargin = numberOr(clear.slot, 0)
	local padMargin = numberOr(clear.pad, 0)
	local parcelMargin = numberOr(clear.parcel, 0)
	for _, slotId in handle.ownedList do
		local rect = handle.slotRects[slotId]
		if rect ~= nil then
			table.insert(rects, grown(rect, slotMargin))
		end
		-- A bought slot keeps the pad clearing it had while buyable: its footprint and path do not
		-- always cover that ground (dirtRoad has no spur), and woods must never grow back on a buy.
		local pad = handle.padRects[slotId]
		if pad ~= nil then
			table.insert(rects, grown(pad, padMargin))
		end
	end
	for _, slotId in buyableSlots(handle) do
		local footprint = handle.slotRects[slotId]
		if footprint ~= nil then
			table.insert(rects, grown(footprint, padMargin))
		end
		local pad = handle.padRects[slotId]
		if pad ~= nil then
			table.insert(rects, grown(pad, padMargin))
		end
	end
	for index, state in handle.states do
		local view = handle.parcels[index]
		if state.level >= 1 and view ~= nil and view.sized then
			table.insert(rects, grown(view.rect, parcelMargin))
		end
	end
	for _, index in input.plazas do
		local rect = handle.plazaRects[index]
		if rect ~= nil then
			table.insert(rects, grown(rect, parcelMargin))
		end
	end
	return { rects = rects, segments = input.segments, streetClear = numberOr(clear.street, 0) }
end

-- Which quarters of each wild entry the mask clears: a clump's four `quads` at quarterRadius, a
-- single's point at singleRadius.
local function clearedFlags(
	handle: Handle,
	wildConfig: Types.FabricWildConfig,
	mask: Mask
): { [number]: number }
	local grid = buildGrid(mask)
	local quarterRadius = numberOr(wildConfig.quarterRadius, 0)
	local singleRadius = numberOr(wildConfig.singleRadius, 0)
	local flags: { [number]: number } = {}
	for index, entry in handle.wildData do
		local bits = 0
		if not handle.wildValid[index] then
			flags[index] = bits
			continue
		end
		if entry.kind == CLUMP then
			local quads = entry.quads
			for quarter = 1, QUARTERS do
				-- A clump written without its quads is tested at its centre, all or nothing.
				local point = if type(quads) == "table" then quads[quarter] else nil
				local x = if type(point) == "table" then numberOr(point[1], entry.x) else entry.x
				local z = if type(point) == "table" then numberOr(point[2], entry.z) else entry.z
				if clearedAt(grid, x, z, quarterRadius) then
					bits = bit32.bor(bits, bit32.lshift(1, quarter - 1))
				end
			end
		elseif clearedAt(grid, entry.x, entry.z, singleRadius) then
			bits = 1
		end
		flags[index] = bits
	end
	return flags
end

-- ------------------------------------------------------------------ wild land

-- The ground an entry stands on: the plot top, or past the base's edge the ground plane below it.
local function wildGround(handle: Handle, entry: Types.FabricWild): number
	return if entry.skirt == true then -handle.context.groundDrop else 0
end

local function wildFrame(handle: Handle, entry: Types.FabricWild, turn: number): CFrame
	return CFrame.new(entry.x, wildGround(handle, entry), entry.z)
		* CFrame.Angles(0, math.rad(entry.rotationY + turn), 0)
end

-- Where the dust goes when part of an entry is cleared: the middle of the quarters that just went.
local function clearedCentre(entry: Types.FabricWild, newly: number): (number, number)
	local quads = entry.quads
	if entry.kind ~= CLUMP or type(quads) ~= "table" then
		return entry.x, entry.z
	end
	local sumX, sumZ, count = 0, 0, 0
	for quarter = 1, QUARTERS do
		local point = quads[quarter]
		if bit32.btest(newly, bit32.lshift(1, quarter - 1)) and type(point) == "table" then
			sumX += numberOr(point[1], entry.x)
			sumZ += numberOr(point[2], entry.z)
			count += 1
		end
	end
	if count == 0 then
		return entry.x, entry.z
	end
	return sumX / count, sumZ / count
end

-- Near plots draw every uncleared clump, quarter and single among the first budget.wild entries;
-- far plots only the whole clumps among the first budget.wildFar clumps. Detail off keeps an even
-- share by index. A near purchase puffs dust where the woods just gave way; any other change
-- (detail, near/far, a restore, a late template) swaps silently.
local function syncWild(handle: Handle, input: SyncInput, previous: { [number]: number }): ()
	local wildConfig = handle.wildConfig
	if wildConfig == nil then
		return
	end
	local cleared = handle.cleared
	local share = math.clamp(numberOr(input.wildShare, 1), 0, 1)
	local puffs = input.animate and input.near
	for index, entry in handle.wildData do
		if not handle.wildValid[index] then
			continue
		end
		local bits = cleared[index] or 0
		local kept = share >= 1 or math.floor(index * share) > math.floor((index - 1) * share)
		local inBudget = if input.near
			then handle.wildNear[index] == true
			else handle.wildFar[index] == true
		local show = kept and inBudget
		local clump = entry.kind == CLUMP
		local wantWhole = clump and show and bits == 0
		local wantQuarters = clump and show and input.near and bits ~= 0 and bits ~= ALL_QUARTERS
		local wantSingle = not clump and show and input.near and bits == 0
		local view = handle.wild[index]
		if view == nil then
			if not (wantWhole or wantQuarters or wantSingle) then
				continue
			end
			view = { whole = nil, quarters = {}, single = nil }
			handle.wild[index] = view
		end
		local current = view :: WildView
		local drawn = current.whole ~= nil or current.single ~= nil or next(current.quarters) ~= nil

		local whole = current.whole
		if whole ~= nil and not wantWhole then
			whole:Destroy()
			current.whole = nil
		end
		local single = current.single
		if single ~= nil and not wantSingle then
			single:Destroy()
			current.single = nil
		end
		for quarter = 1, QUARTERS do
			local placed: Model? = current.quarters[quarter]
			local wanted = wantQuarters and not bit32.btest(bits, bit32.lshift(1, quarter - 1))
			if placed ~= nil and not wanted then
				placed:Destroy()
				current.quarters[quarter] = nil
			end
		end

		-- Validated lists: a variant with no name in them is a missing prop, never an error.
		local variant = entry.variant
		if wantWhole and current.whole == nil then
			local prop = if variant ~= nil then wildConfig.clumps[variant] else nil
			current.whole = spawnAt(handle, prop, 0, wildFrame(handle, entry, 0), entry.scale)
		end
		if wantSingle and current.single == nil then
			current.single =
				spawnAt(handle, entry.prop, 0, wildFrame(handle, entry, 0), entry.scale)
		end
		if wantQuarters then
			local prop = if variant ~= nil then wildConfig.quarters[variant] else nil
			for quarter = 1, QUARTERS do
				local existing: Model? = current.quarters[quarter]
				if existing ~= nil or bit32.btest(bits, bit32.lshift(1, quarter - 1)) then
					continue
				end
				local model = spawnAt(
					handle,
					prop,
					0,
					wildFrame(handle, entry, QUARTER_TURN_DEGREES * (quarter - 1)),
					entry.scale
				)
				if model ~= nil then
					current.quarters[quarter] = model
				end
			end
		end

		local newly = bit32.band(bits, bit32.bnot(previous[index] or 0))
		if puffs and drawn and newly ~= 0 then
			local x, z = clearedCentre(entry, newly)
			puffAt(handle, x, wildGround(handle, entry), z)
		end
	end
end

-- ------------------------------------------------------------------ upgrade layers (wave 1c)

-- The stage a placed entry shows: clamp(tier - tierOffset, 0, #stages - 1), its stages counted in
-- Assets.json as a parcel's are. A single-stage prop, or one with none there, shows its first.
local function upgradeStage(
	handle: Handle,
	view: UpgradeView,
	tierOffset: number,
	tier: number
): number
	local prop = view.prop
	local count = if prop ~= nil then #propHeights(handle, prop) else 0
	return math.max(math.min(tier - tierOffset, count - 1), 0)
end

-- Whether the anchor has developed: a street entry's stretch is drawn, a parcel entry's house is
-- built.
local function anchorDeveloped(handle: Handle, view: UpgradeView): boolean
	local item = view.item
	if item.anchor == ANCHOR_STRETCH then
		local stretch = item.stretch
		return stretch ~= nil and handle.stretches[stretch] ~= nil
	end
	local parcel = item.parcel
	local state = if parcel ~= nil then handle.states[parcel] else nil
	return state ~= nil and state.level >= BUILT_LEVEL
end

-- Puts the entry at `stage` (nil takes it away). EFFECT_POP scales it in; a puff at its base marks
-- only an entry that actually appeared, so a missing template stays silent.
local function placeUpgrade(
	handle: Handle,
	view: UpgradeView,
	stage: number?,
	effect: string,
	dust: boolean
): ()
	local old = view.model
	view.model = nil
	view.shown = stage
	if old ~= nil then
		stopAnimations(old, nil)
		old:Destroy()
	end
	if stage == nil then
		return
	end
	local model = spawnAt(handle, view.prop, stage, view.frame, view.item.scale)
	view.model = model
	if model == nil then
		return
	end
	if effect == EFFECT_POP then
		startAnimation(handle, model, handle.context.plotFrame * view.frame, EFFECT_POP)
	end
	if dust then
		puffAt(handle, view.item.x, 0, view.item.z)
	end
end

local function ensureUpgrade(handle: Handle, view: UpgradeView): ()
	local shown = view.shown
	if view.model == nil and shown ~= nil then
		view.model = spawnAt(handle, view.prop, shown, view.frame, view.item.scale)
	end
end

local function cancelUpgradeTimer(view: UpgradeView): ()
	local timer = view.timer
	if timer ~= nil then
		view.timer = nil
		task.cancel(timer)
	end
end

-- Whether a placed parcel entry must wait for its house in animation: only while a rise can still
-- come, meaning its parcel draws here and its goal is a building not yet shown. A parcel at level 2
-- with no building to show (a district without props) never rises, so its entries go in as any
-- other. The final state is the contract's, placed at level 2, so an unanimated sync places it at
-- once.
local function waitsForHouse(handle: Handle, view: UpgradeView): boolean
	local parcel = view.item.parcel
	if view.item.anchor ~= ANCHOR_PARCEL or parcel == nil then
		return false
	end
	local house = handle.parcels[parcel]
	if house == nil or not house.nearOk then
		return false
	end
	local goal = house.goal
	local shown = house.shown
	return goal ~= nil and goal.kind == BUILDING and (shown == nil or shown.kind ~= BUILDING)
end

local function upgradeSpot(view: UpgradeView): (number, number, number)
	return view.item.x, view.item.z, view.index
end

-- Forward-declared: an entry that went in with the wave starts its growth step.
local fireUpgrade: (handle: Handle, view: UpgradeView, kind: string) -> ()

local function startUpgradeTimer(
	handle: Handle,
	view: UpgradeView,
	kind: string,
	seconds: number
): ()
	cancelUpgradeTimer(view)
	view.timer = task.delay(math.max(seconds, 0), function()
		view.timer = nil
		if not handle.destroyed then
			fireUpgrade(handle, view, kind)
		end
	end)
end

-- The planting wave reaches an entry: it goes in at its first stage (a sapling) with a puff, then
-- grows to the stage the tier gives it after stageSeconds, with a pop; a single-stage prop stops
-- at the first. Both read the newest goal.
fireUpgrade = function(handle: Handle, view: UpgradeView, kind: string): ()
	local goal = view.goal
	if goal == nil then
		placeUpgrade(handle, view, nil, EFFECT_NONE, false)
		return
	end
	if kind == UPGRADE_APPEAR then
		placeUpgrade(handle, view, 0, EFFECT_NONE, true)
		local timing = handle.timing
		if goal > 0 then
			local seconds = if timing ~= nil then numberOr(timing.stageSeconds, 0) else 0
			startUpgradeTimer(handle, view, UPGRADE_GROW, seconds)
		end
		return
	end
	if view.shown ~= goal then
		placeUpgrade(handle, view, goal, EFFECT_POP, false)
	end
end

-- The house rose on a near plot (a parcel's rise timer only runs there): the placed entries of
-- every layer anchored to it go in with it, with a pop. The rise already puffs dust round the
-- parcel.
releaseParcelUpgrades = function(handle: Handle, parcel: number): ()
	local waiting = handle.parcelUpgrades[parcel]
	if waiting == nil then
		return
	end
	for _, view in waiting do
		local goal = view.goal
		if
			view.planted
			and view.kept
			and goal ~= nil
			and view.shown == nil
			and view.timer == nil
		then
			placeUpgrade(handle, view, goal, EFFECT_POP, false)
		end
	end
end

-- One layer, on near plots only and thinned evenly by index when City detail is off. Placement is
-- tracked on every plot, so the animation knows what is new. On the animated sync that buys the
-- layer's slot, the entries it places go in at their first stage in a wave spreading from that
-- slot's pad at the layer's pace. A street entry placed later, as its stretch is drawn, pops in
-- with a puff; a parcel entry goes in with its house, when the building rises out of its site.
-- Growth steps pop after stageSeconds, one by one outward from the last trigger at the layer's
-- pace, so a tier-up never pops a whole layer in one frame. Anything else -- an unanimated sync, a
-- restore, a plot coming near, detail turned back on -- shows the final state at once.
local function syncLayer(
	handle: Handle,
	layer: UpgradeLayer,
	input: SyncInput,
	rippling: boolean,
	fresh: { string },
	triggers: { Vector3 }
): ()
	local config = layer.config
	local timing = handle.timing
	local slotId = config.requiresSlot
	local slotOwned = handle.owned[slotId] == true
	local animated = rippling and timing ~= nil
	local bought = animated and table.find(fresh, slotId) ~= nil
	local stageSeconds = if timing ~= nil then numberOr(timing.stageSeconds, 0) else 0
	local share = math.clamp(numberOr(input.upgradeShare, 1), 0, 1)
	local fallback = if timing ~= nil then numberOr(timing.stagger, 0) else 0
	local stagger = math.max(config.stagger or fallback, 0)
	local wave: { UpgradeView } = {}
	local growing: { UpgradeView } = {}
	for _, view in layer.views do
		local wasPlanted = view.planted
		view.planted = slotOwned and anchorDeveloped(handle, view)
		local goal = if view.planted
			then upgradeStage(handle, view, config.tierOffset, input.tier)
			else nil
		view.goal = goal
		local index = view.index
		view.kept = share >= 1 or math.floor(index * share) > math.floor((index - 1) * share)
		if not input.near or not animated or not view.kept then
			cancelUpgradeTimer(view)
			local target = if input.near and view.kept then goal else nil
			if view.shown == target then
				ensureUpgrade(handle, view)
			else
				placeUpgrade(handle, view, target, EFFECT_NONE, false)
			end
			continue
		end
		if view.timer ~= nil then
			continue -- it shows the newest goal when it fires
		end
		local shown = view.shown
		if shown == goal then
			ensureUpgrade(handle, view)
		elseif goal == nil then
			placeUpgrade(handle, view, nil, EFFECT_NONE, false)
		elseif shown == nil and waitsForHouse(handle, view) then
			continue -- releaseParcelUpgrades brings it with its house
		elseif not wasPlanted then
			if bought then
				table.insert(wave, view)
			else
				placeUpgrade(handle, view, goal, EFFECT_POP, true)
			end
		elseif shown == nil then
			-- Placed while the plot was far, or its template came late: nothing to play.
			placeUpgrade(handle, view, goal, EFFECT_NONE, false)
		else
			table.insert(growing, view)
		end
	end
	sortOutward(growing, rippleOrigins(handle, triggers), upgradeSpot)
	for rank, view in growing do
		startUpgradeTimer(handle, view, UPGRADE_GROW, stageSeconds + (rank - 1) * stagger)
	end
	if #wave == 0 then
		return
	end
	-- The wave spreads from the pad the slot was bought on, else from its anchor.
	local pad = handle.padRects[slotId]
	local frame: CFrame? = handle.slotFrames[slotId]
	local originX, originZ = 0, 0
	if pad ~= nil then
		originX, originZ = pad.x, pad.z
	elseif frame ~= nil then
		originX, originZ = frame.Position.X, frame.Position.Z
	end
	sortOutward(wave, { Vector3.new(originX, 0, originZ) }, upgradeSpot)
	for rank, view in wave do
		startUpgradeTimer(handle, view, UPGRADE_APPEAR, (rank - 1) * stagger)
	end
end

-- Every layer by the same rules, in name order (Fabric.new sorted them), so each plot runs them
-- alike; the plot's puff cap is shared between them.
local function syncUpgrades(
	handle: Handle,
	input: SyncInput,
	rippling: boolean,
	fresh: { string },
	triggers: { Vector3 }
): ()
	for _, layer in handle.layers do
		syncLayer(handle, layer, input, rippling, fresh, triggers)
	end
end

-- ------------------------------------------------------------------ the next pad

local function applyPadLook(handle: Handle, part: BasePart): ()
	local look = handle.context.config.padLook
	if type(look) ~= "table" then
		return
	end
	local material = materialNamed(look.material)
	if material ~= nil then
		part.Material = material
	end
	part.Color = colorFrom(look.color, part.Color)
end

-- Local only: the server's Part, its touch-to-buy and its label are left as they are, and the
-- look it had is kept to be put back.
local function bindPad(handle: Handle, view: PadView, part: BasePart): ()
	view.part = part
	view.material = part.Material
	view.color = part.Color
	applyPadLook(handle, part)
end

local function restorePad(view: PadView): ()
	local part = view.part
	if part.Parent ~= nil then
		part.Material = view.material
		part.Color = view.color
	end
end

local function clearPadDetails(view: PadView): ()
	local marker = view.marker
	if marker ~= nil then
		marker:Destroy()
		view.marker = nil
	end
	for _, part in view.stakes do
		part:Destroy()
	end
	table.clear(view.stakes)
end

local function sitePart(
	handle: Handle,
	name: string,
	size: Vector3,
	cframe: CFrame,
	material: Enum.Material,
	color: Color3
): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = handle.context.plotFrame * cframe
	part.Material = material
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	PropFactory.Seal(part)
	part.Parent = handle.context.folder
	return part
end

-- The marker beside the pad, and (for a slot that raises a building) stakes and strings round the
-- ground it will stand on. Near plots only: from afar they are details nobody can make out.
local function placePadDetails(handle: Handle, slotId: string, view: PadView): ()
	local marker = handle.context.config.marker
	if type(marker) ~= "table" then
		return
	end
	local padRect = handle.padRects[slotId]
	local slotFrame: CFrame? = handle.slotFrames[slotId]
	if
		view.marker == nil
		and padRect ~= nil
		and slotFrame ~= nil
		and type(marker.prop) == "string"
	then
		-- The offset is in the slot's frame and the board faces the slot's front, so it stands
		-- beside the pad, clear of the staked ground, whichever way the slot is turned.
		local offset = if type(marker.offset) == "table" then marker.offset else {}
		local turn = slotFrame.Rotation
		local shift = turn:VectorToWorldSpace(
			Vector3.new(numberOr(offset[1], 0), numberOr(offset[2], 0), numberOr(offset[3], 0))
		)
		view.marker = spawnAt(
			handle,
			marker.prop,
			0,
			CFrame.new(padRect.x + shift.X, shift.Y, padRect.z + shift.Z) * turn,
			nil
		)
	end
	local rect = handle.slotRects[slotId]
	if #view.stakes > 0 or handle.streetOnly[slotId] or rect == nil then
		return
	end
	local stakeColor = colorFrom(marker.stakeColor, Color3.new())
	local stringColor = colorFrom(marker.stringColor, Color3.new(1, 1, 1))
	local turn = CFrame.Angles(0, math.rad(rect.rotationY), 0)
	local corners = rectCorners(rect)
	for index, corner in corners do
		table.insert(
			view.stakes,
			sitePart(
				handle,
				"SiteStake",
				Vector3.new(STAKE_WIDTH, STAKE_HEIGHT, STAKE_WIDTH),
				CFrame.new(corner.X, STAKE_HEIGHT / 2, corner.Z) * turn,
				Enum.Material.Wood,
				stakeColor
			)
		)
		local following = corners[index % #corners + 1]
		local a = Vector3.new(corner.X, STRING_HEIGHT, corner.Z)
		local b = Vector3.new(following.X, STRING_HEIGHT, following.Z)
		local length = (b - a).Magnitude
		if length > 0 then
			table.insert(
				view.stakes,
				sitePart(
					handle,
					"SiteString",
					Vector3.new(STRING_THICKNESS, STRING_THICKNESS, length),
					CFrame.lookAt((a + b) / 2, b),
					Enum.Material.SmoothPlastic,
					stringColor
				)
			)
		end
	end
end

local function dropPad(handle: Handle, slotId: string, view: PadView): ()
	handle.pads[slotId] = nil
	local expiry = view.expiry
	if expiry ~= nil then
		view.expiry = nil
		task.cancel(expiry)
	end
	clearPadDetails(view)
	restorePad(view)
end

-- The dressing follows the live Pads folder. A pad that goes keeps its dressing for one
-- lod.refreshSeconds, and a new Part laid down for the same slot meanwhile (a cosmetics refresh
-- re-lays every pad) takes the dressing over instead of rebuilding it.
local function syncPads(handle: Handle, input: SyncInput): ()
	for slotId, part in input.pads do
		local view = handle.pads[slotId]
		if view == nil then
			local fresh: PadView = {
				part = part,
				material = part.Material,
				color = part.Color,
				marker = nil,
				stakes = {},
				expiry = nil,
			}
			handle.pads[slotId] = fresh
			bindPad(handle, fresh, part)
			continue
		end
		local expiry = view.expiry
		if expiry ~= nil then
			view.expiry = nil
			task.cancel(expiry)
		end
		if view.part ~= part then
			restorePad(view)
			bindPad(handle, view, part)
		end
	end
	local grace = math.max(numberOr(handle.context.padGraceSeconds, 0), 0)
	for slotId, view in handle.pads do
		local present: BasePart? = input.pads[slotId]
		if present == nil and view.expiry == nil then
			view.expiry = task.delay(grace, function()
				view.expiry = nil
				if not handle.destroyed and handle.pads[slotId] == view then
					dropPad(handle, slotId, view)
				end
			end)
		end
		if input.near then
			placePadDetails(handle, slotId, view)
		else
			clearPadDetails(view)
		end
	end
end

-- ------------------------------------------------------------------ landmark reveal

local function removeReveal(handle: Handle, reveal: Reveal, dust: boolean): ()
	local timer = reveal.timer
	if timer ~= nil then
		reveal.timer = nil
		task.cancel(timer)
	end
	local index = table.find(handle.reveals, reveal)
	if index ~= nil then
		table.remove(handle.reveals, index)
	end
	reveal.model:Destroy()
	if dust then
		puffAround(handle, reveal.rect)
	end
end

-- A landmark bought just now stands in an open timber scaffold for revealSeconds. Street upgrades
-- raise no building, so they get no scaffold, as they get no stakes.
local function startReveals(handle: Handle, fresh: { string }): ()
	local timing = handle.timing
	local prop = handle.context.config.reveal
	if timing == nil or type(prop) ~= "string" then
		return
	end
	for _, slotId in fresh do
		local rect: Rect? = handle.slotRects[slotId]
		local frame: CFrame? = handle.slotFrames[slotId]
		if handle.streetOnly[slotId] or rect == nil or frame == nil then
			continue
		end
		local footprint = 2 * math.max(math.abs(rect.hx), math.abs(rect.hz))
		local model = spawnAt(handle, prop, 0, frame, footprint / REVEAL_DESIGN_STUDS)
		if model == nil then
			continue
		end
		local reveal: Reveal = { model = model, rect = rect, timer = nil }
		reveal.timer = task.delay(math.max(numberOr(timing.revealSeconds, 0), 0), function()
			reveal.timer = nil
			if not handle.destroyed then
				removeReveal(handle, reveal, true)
			end
		end)
		table.insert(handle.reveals, reveal)
	end
end

-- ------------------------------------------------------------------ API

local Fabric = {}

function Fabric.new(context: Context): Handle
	local config = context.config
	local data = context.data
	local layout = context.layout
	local budget = context.budget
	local timing = if type(config.construction) == "table" then config.construction else nil
	local maxPuffs = if timing ~= nil then timing.maxPuffs else nil
	local handle: Handle = {
		context = context,
		pull = validPull(config.pull),
		clear = if type(config.clear) == "table" then config.clear else nil,
		wildConfig = validWildConfig(config.wild),
		timing = timing,
		maxPuffs = if finite(maxPuffs) then math.floor(maxPuffs :: number) else nil,
		parcelData = {},
		wildData = if type(data) == "table" and type(data.wild) == "table" then data.wild else {},
		wildValid = {},
		parcels = {},
		durations = {},
		layers = {},
		parcelUpgrades = {},
		slotRects = {},
		padRects = {},
		plazaRects = {},
		slotFrames = {},
		streetOnly = {},
		modelNames = {},
		slotOrder = {},
		requires = {},
		heights = {},
		wildNear = {},
		wildFar = {},
		dustGap = 1,
		states = {},
		stretches = {},
		owned = {},
		ownedList = {},
		stages = {},
		developKey = "",
		maskKey = "",
		cleared = {},
		wild = {},
		pads = {},
		reveals = {},
		puffs = {},
		lastTrigger = context.entrance or Vector3.zero,
		destroyed = false,
	}

	-- The effective `requires` exactly as PlotService.getEraMaps resolves it: the slot's own, else
	-- the previous slot in purchase order; the first slot needs nothing.
	for eraIndex = 1, Catalog.GetEraCount() do
		local eraConfig = Catalog.GetEraConfig(eraIndex)
		if eraConfig ~= nil and eraConfig.name == context.eraName then
			local previous: string? = nil
			for _, slot in eraConfig.slots do
				handle.modelNames[slot.id] = slot.modelName
				handle.streetOnly[slot.id] = slot.streetOnly == true
				table.insert(handle.slotOrder, slot.id)
				local requires = slot.requires or previous
				if requires ~= nil then
					handle.requires[slot.id] = requires
				end
				previous = slot.id
			end
			break
		end
	end
	for slotId, slotLayout in layout.slots do
		handle.slotFrames[slotId] = Scatter.PropFrame(slotLayout.position, slotLayout.rotationY)
	end
	-- Scatter's keep-outs, so the woods clear exactly the rects the rest of the dressing avoids. A
	-- pad lies unturned in the plot frame (PlotService.padWorldCFrame).
	for _, footprint in context.solids do
		local slotId = footprint.slotId
		local slotLayout = if slotId ~= nil then layout.slots[slotId] else nil
		if slotId == nil or slotLayout == nil then
			continue
		end
		if footprint.pad then
			handle.padRects[slotId] = footprintRect(footprint, 0)
		else
			handle.slotRects[slotId] = footprintRect(footprint, slotLayout.rotationY)
		end
	end
	-- A plaza's solid is the unslotted one standing on its position: Scatter alone reads a plaza
	-- prop's harvested extents, so its rect is taken from there rather than measured twice.
	local plazas: { Types.PlazaLayout } = layout.plazas or {}
	for index, plaza in plazas do
		for _, footprint in context.solids do
			local origin = footprint.origin
			if
				footprint.slotId == nil
				and origin.X == plaza.position.X
				and origin.Z == plaza.position.Z
			then
				handle.plazaRects[index] = footprintRect(footprint, plaza.rotationY)
				break
			end
		end
	end

	-- A key a stale config lacks turns its feature off: no ceiling means nothing drawn. Wave 1c: a
	-- far plot draws only the first budget.parcelsFar (the frontage nearest the heart), or without
	-- that key what a near plot draws.
	local parcelBudget = math.max(math.floor(numberOr(budget.parcels, 0)), 0)
	local farParcelBudget = math.max(math.floor(numberOr(budget.parcelsFar, parcelBudget)), 0)
	local rawParcels: { Types.FabricParcel } = if type(data) == "table"
			and type(data.parcels) == "table"
		then data.parcels
		else {}
	local sizes = config.sizes
	for index = 1, #rawParcels do
		local raw = rawParcels[index]
		local wellFormed = validParcel(raw)
		-- A row-k parcel (k 2 or 3) stands behind an earlier parcel of row k - 1, which the data
		-- lists first; one that does not is malformed and becomes a blank that keeps its index.
		if wellFormed and raw.row ~= 1 then
			local front = raw.front
			local ahead = if front == math.floor(front)
					and front >= 1
					and front < index
				then handle.parcelData[front]
				else nil
			wellFormed = ahead ~= nil and ahead.row == raw.row - 1
		end
		local parcel = if wellFormed then raw else blankParcel()
		handle.parcelData[index] = parcel
		if type(sizes) ~= "table" then
			continue
		end
		local footprint = forSize(parcel.size, sizes.small, sizes.medium, sizes.narrow)
		local sized = type(footprint) == "table" and finite(footprint[1]) and finite(footprint[2])
		local width = if sized then (footprint :: { number })[1] else 0
		local depth = if sized then (footprint :: { number })[2] else 0
		table.insert(handle.parcels, {
			index = index,
			parcel = parcel,
			rect = {
				x = parcel.x,
				z = parcel.z,
				hx = width / 2,
				hz = depth / 2,
				rotationY = parcel.rotationY,
				margin = 0,
			},
			sized = sized,
			frame = Scatter.PropFrame(Vector3.new(parcel.x, 0, parcel.z), parcel.rotationY),
			nearOk = wellFormed and sized and index <= parcelBudget,
			farOk = wellFormed and sized and index <= farParcelBudget,
			goal = nil,
			changed = false,
			shown = nil,
			model = nil,
			timer = nil,
		})
	end
	local shortest = if timing ~= nil then math.max(numberOr(timing.minSeconds, 0), 0) else 0
	local longest = if timing ~= nil
		then math.max(numberOr(timing.maxSeconds, shortest), shortest)
		else shortest
	local rng = Random.new(context.seed + CONSTRUCTION_SALT)
	for index = 1, #handle.parcelData do
		handle.durations[index] = shortest + (longest - shortest) * rng:NextNumber()
	end
	-- Every fabric puff runs round one slot or parcel rect at most, so one gap limit fits them all.
	local widest = 0
	for _, rect in handle.slotRects do
		widest = math.max(widest, math.abs(rect.hx), math.abs(rect.hz))
	end
	for _, view in handle.parcels do
		widest = math.max(widest, math.abs(view.rect.hx), math.abs(view.rect.hz))
	end
	handle.dustGap = 2 * widest + 1

	-- The wild budgets are spent in data order and never re-spent, so clearing one item can never
	-- make another appear.
	local nearBudget = math.max(math.floor(numberOr(budget.wild, 0)), 0)
	local farBudget = math.max(math.floor(numberOr(budget.wildFar, 0)), 0)
	local clumps = 0
	for index = 1, #handle.wildData do
		local entry = handle.wildData[index]
		local wellFormed = validWildEntry(entry)
		handle.wildValid[index] = wellFormed
		handle.wildNear[index] = index <= nearBudget
		if wellFormed and entry.kind == CLUMP then
			clumps += 1
			handle.wildFar[index] = clumps <= farBudget
		end
	end

	-- Wave 1c round 3: the upgrade layers in name order, so every plot walks them alike. Each keeps
	-- its well-formed entries inside its own budget, an index prefix of its data. A layer without a
	-- valid config or a data list is off; a missing prop leaves that entry bare.
	local layerConfigs = config.upgrades
	local layerData = if type(data) == "table" then data.upgrades else nil
	if type(layerConfigs) == "table" and type(layerData) == "table" then
		local names: { string } = {}
		for name in layerConfigs do
			if type(name) == "string" then
				table.insert(names, name)
			end
		end
		table.sort(names)
		for _, name in names do
			local layerConfig = validUpgradeLayer(layerConfigs[name])
			local items = layerData[name]
			if layerConfig == nil or type(items) ~= "table" then
				continue
			end
			local layer: UpgradeLayer = { name = name, config = layerConfig, views = {} }
			for index = 1, math.min(#items, layerConfig.budget) do
				local item = items[index]
				if not validUpgradeItem(item) then
					continue
				end
				local view: UpgradeView = {
					index = index,
					item = item,
					frame = CFrame.new(item.x, 0, item.z)
						* CFrame.Angles(0, math.rad(item.rotationY), 0),
					prop = layerConfig.props[item.variant],
					planted = false,
					kept = true,
					goal = nil,
					shown = nil,
					model = nil,
					timer = nil,
				}
				table.insert(layer.views, view)
				local parcel = item.parcel
				if item.anchor == ANCHOR_PARCEL and parcel ~= nil then
					local onParcel = handle.parcelUpgrades[parcel]
					if onParcel == nil then
						onParcel = {}
						handle.parcelUpgrades[parcel] = onParcel
					end
					table.insert(onParcel :: { UpgradeView }, view)
				end
			end
			table.insert(handle.layers, layer)
		end
	end
	return handle
end

-- One pass: what changed since the last sync, the development levels, the clearing mask, the next
-- pad, the reveal, then parcels and wild land. Called after RoadGraph in the same controller pass,
-- so the visible stretches are the ones just drawn.
function Fabric.Sync(handle: Handle, input: SyncInput): ()
	if handle.destroyed then
		return
	end
	-- A purchase or a stage swap is where a ripple starts; the first sync of a build sees every
	-- slot as new, but it is never animated.
	local triggers: { Vector3 } = {}
	local fresh: { string } = {}
	for _, slotId in input.owned do
		local isNew = not handle.owned[slotId]
		if isNew then
			handle.owned[slotId] = true
			table.insert(handle.ownedList, slotId)
			table.insert(fresh, slotId)
		end
		local stage = input.stages[slotId] or 0
		local known = handle.stages[slotId]
		local raised = known == nil or stage > known
		if raised then
			handle.stages[slotId] = stage
		end
		local frame: CFrame? = handle.slotFrames[slotId]
		if frame ~= nil and (isNew or (raised and known ~= nil)) then
			table.insert(triggers, frame.Position)
		end
	end
	if #fresh > 0 then
		table.sort(handle.ownedList)
	end
	handle.stretches = input.stretches

	local key = developKey(handle, input)
	if key ~= handle.developKey then
		handle.developKey = key
		handle.states = develop(handle, input)
		for _, view in handle.parcels do
			local goal = goalFor(handle, view, handle.states[view.index])
			if not sameLook(goal, view.goal) then
				view.changed = true
			end
			view.goal = goal
		end
	end

	local previous = handle.cleared
	local wildConfig = handle.wildConfig
	local clear = handle.clear
	if wildConfig ~= nil then
		local maskKey = if clear ~= nil then maskKeyOf(handle, input) else ""
		if maskKey ~= handle.maskKey then
			handle.maskKey = maskKey
			local mask: Mask = if clear ~= nil
				then buildMask(handle, clear, input)
				else { rects = {}, segments = {}, streetClear = 0 }
			handle.cleared = clearedFlags(handle, wildConfig, mask)
		end
	end

	syncPads(handle, input)
	local rippling = input.animate and input.near
	if rippling then
		startReveals(handle, fresh)
	else
		-- Far, or a restore: nothing plays, and a scaffold or puff still running goes quietly.
		for index = #handle.reveals, 1, -1 do
			removeReveal(handle, handle.reveals[index], false)
		end
		stopPuffs(handle)
	end
	local timing = handle.timing
	if timing ~= nil and rippling then
		rippleParcels(handle, timing, triggers)
	else
		settleParcels(handle, input.near)
	end
	syncWild(handle, input, previous)
	syncUpgrades(handle, input, rippling, fresh, triggers)
	-- A restore's slots are not purchases, so only a ripple moves the origin the next one starts at.
	if rippling and #triggers > 0 then
		handle.lastTrigger = triggers[1]
	end
end

-- M12 walk solids: every row-1 parcel on a drawn street, developed or not. The lanes are rebuilt
-- only when a street is drawn, which is exactly when this set changes, so walkers never re-seat as
-- sites go up; a parcel that develops later is already clear of every lane. Back rows stand behind
-- row 1 and can never reach a lane, so leaving them out only saves the clipping work.
function Fabric.WalkSolids(handle: Handle): { Scatter.Footprint }
	local solids: { Scatter.Footprint } = {}
	for _, view in handle.parcels do
		local street = handle.stretches[view.parcel.stretch]
		if view.nearOk and view.parcel.row == 1 and street ~= nil then
			local rect = view.rect
			table.insert(solids, {
				origin = Vector3.new(rect.x, 0, rect.z),
				rotation = CFrame.Angles(0, math.rad(rect.rotationY), 0),
				extents = { minX = -rect.hx, maxX = rect.hx, minZ = -rect.hz, maxZ = rect.hz },
			})
		end
	end
	return solids
end

-- Plot-local centres of the clumps a near plot still draws something of, in data order: what the
-- birds circle when the layout has no tree zones.
function Fabric.SurvivingClumps(handle: Handle): { Vector3 }
	local centres: { Vector3 } = {}
	-- The skirt past the plot edge is never cleared, so a flock over it would never move; birds
	-- circle the town's own woods and fall back to the skirt only once every plot clump is felled.
	local skirt: { Vector3 } = {}
	if handle.wildConfig == nil then
		return centres
	end
	for index, entry in handle.wildData do
		if
			handle.wildValid[index]
			and entry.kind == CLUMP
			and handle.wildNear[index]
			and (handle.cleared[index] or 0) ~= ALL_QUARTERS
		then
			table.insert(if entry.skirt then skirt else centres, Vector3.new(entry.x, 0, entry.z))
		end
	end
	return if #centres > 0 then centres else skirt
end

-- Cancels every timer, animation and puff and removes everything the fabric placed, giving any
-- pad that is still there its own look back.
function Fabric.Destroy(handle: Handle): ()
	if handle.destroyed then
		return
	end
	handle.destroyed = true
	stopAnimations(nil, handle)
	for _, view in handle.parcels do
		cancelTimer(view)
		local model = view.model
		if model ~= nil then
			model:Destroy()
			view.model = nil
		end
		view.shown = nil
	end
	for _, view in handle.wild do
		local whole = view.whole
		if whole ~= nil then
			whole:Destroy()
		end
		local single = view.single
		if single ~= nil then
			single:Destroy()
		end
		for _, quarter in view.quarters do
			quarter:Destroy()
		end
	end
	table.clear(handle.wild)
	for _, layer in handle.layers do
		for _, view in layer.views do
			cancelUpgradeTimer(view)
			local model = view.model
			if model ~= nil then
				model:Destroy()
				view.model = nil
			end
			view.shown = nil
		end
	end
	for slotId, view in handle.pads do
		dropPad(handle, slotId, view)
	end
	for index = #handle.reveals, 1, -1 do
		removeReveal(handle, handle.reveals[index], false)
	end
	for _, record in handle.puffs do
		local cleanup = record.cleanup
		if cleanup ~= nil then
			record.cleanup = nil
			task.cancel(cleanup)
		end
		Dust.Destroy(record.dust)
	end
	table.clear(handle.puffs)
end

return Fabric
