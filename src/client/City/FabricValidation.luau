--!strict
-- The city fabric's vocabulary and its config and data checks (docs/INTERFACES.md "M12 contracts —
-- Data" and the review amendment "Config is validated once, in Fabric.new"). Fabric.new runs each
-- check once per plot: a missing or malformed block, list or entry comes back as nil, false or an
-- empty list, which turns that feature or item off, and nothing here ever raises an error or
-- writes to the Output. tools/cityfabric.py mirrors every check by name (`valid_pull`,
-- `valid_parcel`, ...), so a rule changed here changes there too. The checks the pure CityFabric
-- holds itself (`ValidSwaps`, `ValidWildSwaps`, `ValidUpgradeItem`) are not repeated here: those
-- are cross-checked against the mirror by tools/check_mirror.py.
--
-- A module of its own because Fabric.luau's top level is one function to Studio's compiler, which
-- gives it 200 registers (tools/check_compile.py): the checks are pure and read nothing of a plot,
-- so they are the part that can live elsewhere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
local Types = require(sharedFolder:WaitForChild("Types"))

-- The numeric fields `pull` must carry, finite, before the pure CityFabric may read it.
local PULL_NUMBERS = { "radius", "tierTerm", "reach", "levelsOverTier", "smallMaxLevel" }

local FabricValidation = {}

-- Contract vocabulary: a parcel's size, and a wild entry's kind (a clump is four turned copies of
-- its quarter prop, with one cleared bit per quarter).
FabricValidation.SIZE = { small = "small", medium = "medium", narrow = "narrow" }
FabricValidation.WILD = {
	clump = "clump",
	single = "single",
	quarters = 4,
	allQuarters = 15,
	quarterTurnDegrees = 90,
}
-- A lane leg shorter than this draws nothing, and a lane with no longer leg is not a lane.
FabricValidation.LANE_MIN = 0.01

local SIZE = FabricValidation.SIZE
local WILD = FabricValidation.WILD

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function numberOr(value: any, fallback: number): number
	return if finite(value) then value else fallback
end

FabricValidation.Finite = finite
FabricValidation.NumberOr = numberOr

-- `pull` as CityFabric may use it -- five finite numbers and an array of finite thresholds, copied
-- so no stray key reaches the trusting pure module -- or nil, which keeps every parcel at level 0.
function FabricValidation.Pull(pull: any): Types.FabricPullConfig?
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

function FabricValidation.WildConfig(wild: any): Types.FabricWildConfig?
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
function FabricValidation.Parcel(parcel: any): boolean
	return type(parcel) == "table"
		and finite(parcel.x)
		and finite(parcel.z)
		and finite(parcel.rotationY)
		and finite(parcel.along)
		and (parcel.row == 1 or parcel.row == 2 or parcel.row == 3)
		and finite(parcel.front)
		and type(parcel.stretch) == "string"
		and (parcel.size == SIZE.small or parcel.size == SIZE.medium or parcel.size == SIZE.narrow)
end

-- Stands in for a malformed parcel: on no street, so it never develops, and later parcels keep
-- their indices (a row-2 parcel names its front parcel by index).
function FabricValidation.BlankParcel(): Types.FabricParcel
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

function FabricValidation.WildEntry(entry: any): boolean
	if
		type(entry) ~= "table"
		or not (finite(entry.x) and finite(entry.z) and finite(entry.rotationY))
	then
		return false
	end
	return entry.kind == WILD.clump or (entry.kind == WILD.single and type(entry.prop) == "string")
end

-- Wave 1c round 3: one upgrade layer's config, or nil (that layer off) when a field is missing or
-- bad: a slot to buy, a prop list, a whole `tierOffset` (so a stage is always whole), a whole
-- `budget` of 0 or more, and an optional `stagger` of 0 or more.
function FabricValidation.UpgradeLayer(value: any): Types.FabricUpgradeLayerConfig?
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

-- Wave 2.4: a lane the renderer can lay -- a polyline of 2 to 4 [x, z] points of finite numbers,
-- at least one leg of which is long enough to draw, and its mouth's address on the street it
-- leaves. Any other entry is not drawn, and its lots are blanks: a lane whose points all coincide
-- must not let houses rise beside a road that never comes.
function FabricValidation.Lane(lane: any): boolean
	if type(lane) ~= "table" or type(lane.stretch) ~= "string" or not finite(lane.along) then
		return false
	end
	local points = lane.points
	if type(points) ~= "table" or #points < 2 or #points > 4 then
		return false
	end
	for index = 1, #points do
		local point = points[index]
		if type(point) ~= "table" or not finite(point[1]) or not finite(point[2]) then
			return false
		end
	end
	for index = 2, #points do
		local dx = points[index][1] - points[index - 1][1]
		local dz = points[index][2] - points[index - 1][2]
		if math.sqrt(dx * dx + dz * dz) >= FabricValidation.LANE_MIN then
			return true
		end
	end
	return false
end

-- `fabric.lanes` as far as the client reads it: a width above 0 (the dust along a baked lane, the
-- slabs of one laid as Parts) and the height of those slabs' tops. Nil draws no lane and clears
-- nothing for one; their lots still develop.
function FabricValidation.LanesConfig(lanes: any): Types.FabricLanesConfig?
	if
		type(lanes) ~= "table"
		or not (finite(lanes.width) and lanes.width > 0)
		or not finite(lanes.fillHeight)
	then
		return nil
	end
	return { width = lanes.width, fillHeight = lanes.fillHeight }
end

-- Wave 2.0: the fabric keys of `ambient.smoke`. `every` must be a whole number of 1 or more and
-- `fabricProps` a table, or fabric smoke is off (nil). A chimney top is exactly three finite
-- numbers; any other entry -- [] by convention -- is a stage without a chimney, as is a stage past
-- the end of its list. Only this era's "<Era>/<Prop>" keys are kept, by prop name.
function FabricValidation.Chimneys(
	smoke: any,
	eraName: string
): ({ [string]: { [number]: CFrame } }?, number?)
	if type(smoke) ~= "table" then
		return nil, nil
	end
	local every, props = smoke.every, smoke.fabricProps
	if type(props) ~= "table" or not finite(every) or every < 1 or every ~= math.floor(every) then
		return nil, nil
	end
	local prefix = eraName .. "/"
	local chimneys: { [string]: { [number]: CFrame } } = {}
	for key, stages in props do
		if
			type(key) ~= "string"
			or type(stages) ~= "table"
			or string.sub(key, 1, #prefix) ~= prefix
		then
			continue
		end
		local tops: { [number]: CFrame } = {}
		for index, top in stages do
			if
				type(index) == "number"
				and type(top) == "table"
				and #top == 3
				and finite(top[1])
				and finite(top[2])
				and finite(top[3])
			then
				tops[index] = CFrame.new(top[1], top[2], top[3])
			end
		end
		chimneys[string.sub(key, #prefix + 1)] = tops
	end
	return chimneys, every
end

return FabricValidation
