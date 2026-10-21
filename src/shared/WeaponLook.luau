--!strict
-- L3 W2 (docs/prompts/l3-w2-contract.md, L3-48, L3-49): what a player's weapons look like, read
-- the same way by the server that writes it and by every client that draws it. Pure: no Instance,
-- no service, no clock (Vector3 only), so tools/crowd_harness tests the very functions both sides
-- run.
--
-- The server (WeaponService) writes three character attributes, the held families and the slot in
-- use (Values); every client reads them back (Read) and hangs the models WeaponModels.json names
-- (Def, Point). The Armory shelf's icon ids come from Assets.json's v5 `icons` (IconId). A model is
-- decoration only (L3-52): nothing here is read where a hit is judged.

local Types = require(script.Parent:WaitForChild("Types"))

local WeaponLook = {}

-- Infrastructure, like Unlocks' ability attributes: the character attributes that carry a
-- player's weapons to every client. A fresh character has none, and the server writes all three
-- on every fresh character (WeaponService.PrepareCharacter).
local ATTRIBUTES = table.freeze({
	melee = "WeaponMelee",
	ranged = "WeaponRanged",
	held = "WeaponHeld",
})
WeaponLook.ATTRIBUTES = ATTRIBUTES

-- The points every entry carries (L3-46); any other name is a builder's extra.
local REQUIRED_POINTS = table.freeze({ "grip", "tip", "holster" })
-- L3-46: how far a point may lie outside its entry's bounds (studs). The generator writes both
-- from one frame file, rounded to the thousandth. tools/assets/weapon_frames.py's POINT_SLACK is
-- this number on the writing side: change the two together, or one writes what the other warns of.
local BOUNDS_SLACK = 0.01

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Three finite numbers and nothing past them: a point, or a corner of the bounds.
local function triple(value: any): boolean
	return type(value) == "table"
		and #value == 3
		and finite(value[1])
		and finite(value[2])
		and finite(value[3])
end

-- The string keys of a table, sorted, so every list of problems comes in one order.
local function sortedKeys(map: any): { string }
	local keys: { string } = {}
	if type(map) == "table" then
		for key in map do
			if type(key) == "string" then
				table.insert(keys, key)
			end
		end
	end
	table.sort(keys)
	return keys
end

-- Why `family` has no usable entry in `models` (nil = it has one). Def's rule, with the words
-- Problems names it by.
local function defProblem(models: any, family: any): string?
	if type(models) ~= "table" or type(models.families) ~= "table" or type(family) ~= "string" then
		return "no model entry"
	end
	local def = models.families[family]
	if type(def) ~= "table" then
		return "no model entry"
	end
	local expected = WeaponLook.ModelName(family)
	if def.model ~= expected then
		return `its model {tostring(def.model)} is not {expected}`
	end
	local points = def.points
	if type(points) ~= "table" then
		return "it has no points"
	end
	for _, name in REQUIRED_POINTS do
		if not triple(points[name]) then
			return `its {name} is not three finite numbers`
		end
	end
	local bounds = def.bounds
	if type(bounds) ~= "table" or not triple(bounds.min) or not triple(bounds.max) then
		return "its bounds are not two corners of three finite numbers"
	end
	for axis = 1, 3 do
		if bounds.min[axis] > bounds.max[axis] then
			return "its bounds.min lies above its bounds.max"
		end
	end
	return nil
end

-- L3-46: a family's model name is its id with the first letter capitalised ("frostHammer" ->
-- "FrostHammer", "smg" -> "Smg"). WeaponModels.json writes it, and Def holds the two together.
function WeaponLook.ModelName(family: string): string
	return string.upper(string.sub(family, 1, 1)) .. string.sub(family, 2)
end

-- The entry for `family`, or nil unless it exists, its model is ModelName(family), grip, tip and
-- holster are three finite numbers each and its bounds' min lies at or below its max on every
-- axis. nil means that hand stays empty and the Armory shows its text placeholder (L3-59).
function WeaponLook.Def(models: Types.WeaponModelsConfig?, family: string): Types.WeaponModelDef?
	if models == nil or defProblem(models, family) ~= nil then
		return nil
	end
	return models.families[family]
end

-- The named point of an entry, in the template's frame (its pivot is the grip, L3-47); nil when
-- the entry has no such point or it is not three finite numbers.
function WeaponLook.Point(def: Types.WeaponModelDef, name: string): Vector3?
	local entry: any = def
	local points = if type(entry) == "table" then entry.points else nil
	local point = if type(points) == "table" then points[name] else nil
	if not triple(point) then
		return nil
	end
	return Vector3.new(point[1], point[2], point[3])
end

-- The shelf icon's image id for `family`: Assets.json icons[<folder>][<model>].imageId when it is
-- a positive whole number, else 0 (no config, no entry, not harvested yet, or still in
-- moderation): 0 keeps today's text card (L3-57).
function WeaponLook.IconId(
	assets: Types.AssetsConfig?,
	models: Types.WeaponModelsConfig?,
	family: string
): number
	local def = WeaponLook.Def(models, family)
	local config: any = assets
	if def == nil or models == nil or type(config) ~= "table" then
		return 0
	end
	local folder: any = models.folder
	local icons = config.icons
	local set = if type(icons) == "table" and type(folder) == "string" then icons[folder] else nil
	local icon = if type(set) == "table" then set[def.model] else nil
	local imageId = if type(icon) == "table" then icon.imageId else nil
	if finite(imageId) and imageId > 0 and imageId % 1 == 0 then
		return imageId
	end
	return 0
end

-- L3-49: the three attribute values the server writes for a loadout and the slot in use. `held`
-- is "melee" or "ranged"; anything else reads "melee", the slot every player starts in.
function WeaponLook.Values(
	loadout: { melee: string, ranged: string },
	held: string
): { [string]: string }
	local values: { [string]: string } = {}
	values[ATTRIBUTES.melee] = loadout.melee
	values[ATTRIBUTES.ranged] = loadout.ranged
	values[ATTRIBUTES.held] = if held == "ranged" then "ranged" else "melee"
	return values
end

-- A family as an attribute carries it: a non-empty string, else nil.
local function familyOf(value: any): string?
	return if type(value) == "string" and value ~= "" then value else nil
end

-- L3-51: melee, ranged and held as a client reads them through `get` (a character's
-- GetAttribute): each family a non-empty string, held "melee" or "ranged"; anything else is nil
-- (nothing hangs for it).
function WeaponLook.Read(get: (name: string) -> any): (string?, string?, string?)
	local held = get(ATTRIBUTES.held)
	return familyOf(get(ATTRIBUTES.melee)),
		familyOf(get(ATTRIBUTES.ranged)),
		if held == "melee" or held == "ranged" then held else nil
end

-- Whether `point` lies inside `bounds`, each side grown by BOUNDS_SLACK.
local function inside(point: Vector3, bounds: any): boolean
	local coordinates = { point.X, point.Y, point.Z }
	for axis = 1, 3 do
		local value = coordinates[axis]
		if value < bounds.min[axis] - BOUNDS_SLACK or value > bounds.max[axis] + BOUNDS_SLACK then
			return false
		end
	end
	return true
end

-- Every fault of a WeaponModels config against the weapon families (ProvingGrounds.json
-- `weapons`): a family with no usable entry (and why), an entry that names no family, a grip off
-- the origin, a point that is not three finite numbers or lies outside its bounds (by more than
-- BOUNDS_SLACK), a missing folder. The whole list is sorted, so each family's faults come
-- together, in family order, whichever pass found them. Empty when all is well. HeldWeapons.Start
-- warns them once; tools/assets/weapon_frames.py refuses to write such a file.
function WeaponLook.Problems(
	models: Types.WeaponModelsConfig?,
	weapons: { [string]: any }
): { string }
	local problems: { string } = {}
	local config: any = models
	if type(config) ~= "table" or type(config.families) ~= "table" then
		table.insert(problems, "WeaponModels.json has no families: every hand stays empty")
		return problems
	end
	if type(config.folder) ~= "string" or config.folder == "" then
		table.insert(problems, "WeaponModels.json names no folder")
	end
	for _, family in sortedKeys(weapons) do
		local problem = defProblem(config, family)
		if problem ~= nil then
			table.insert(problems, `{family}: {problem}`)
		end
	end
	for _, family in sortedKeys(config.families) do
		if weapons[family] == nil then
			table.insert(problems, `{family}: not a weapons family`)
			continue
		end
		local def = WeaponLook.Def(config, family)
		if def == nil then
			continue
		end
		local grip = WeaponLook.Point(def, "grip")
		if grip ~= nil and (grip.X ~= 0 or grip.Y ~= 0 or grip.Z ~= 0) then
			table.insert(problems, `{family}: its grip is not the origin`)
		end
		for _, name in sortedKeys(def.points) do
			local point = WeaponLook.Point(def, name)
			if point == nil then
				table.insert(problems, `{family}: its {name} is not three finite numbers`)
			elseif not inside(point, def.bounds) then
				table.insert(problems, `{family}: its {name} lies outside its bounds`)
			end
		end
	end
	table.sort(problems)
	return problems
end

return WeaponLook
