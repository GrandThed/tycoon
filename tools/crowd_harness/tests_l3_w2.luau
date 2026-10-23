-- Cases for L3 W2, the models in the game (docs/prompts/l3-w2-contract.md): the pure WeaponLook
-- (L3-48: the three attribute names and values, a family's model name, its entry, its points, its
-- icon id, Read's reading of the attributes and the faults of a models file), first on entries
-- built here, then on WeaponModels.json as it ships; then, read as text (FIXTURES.source.l3w2,
-- run_harness.py L3W2_LINES, L3W2_PATTERNS and L3W2_ORDER), the contract's T1 to T14: the server
-- lines that show a player's weapons and the slot in use (L3-49, L3-50), and the client lines that
-- move another player's arm, draw from one muzzle, hang a sealed clone and turn the Armory stage
-- (L3-51 to L3-56). Appended last by run_harness.py, so every local of the earlier files is in
-- scope (check, near, load, L1, FIXTURES). Everything hangs off the W2L3 table (the 200-local
-- limit), and every group runs behind L1.group, so one that throws fails a check and the bundle
-- goes on.

print("L3 W2: the weapons' look (WeaponLook) and the lines that show it")

local W2L3: any = {
	Look = load("WeaponLook"),
	NAN = 0 / 0,
	-- L3-46: every weapons family and its model name, the id with its first letter capitalised.
	MODELS = {
		beam = "Beam",
		broadsword = "Broadsword",
		chaingun = "Chaingun",
		flamethrower = "Flamethrower",
		frostHammer = "FrostHammer",
		greataxe = "Greataxe",
		launcher = "Launcher",
		longbow = "Longbow",
		rifle = "Rifle",
		shotgun = "Shotgun",
		smg = "Smg",
		spear = "Spear",
		spinblade = "Spinblade",
		splitbow = "Splitbow",
		warhammer = "Warhammer",
	},
}

function W2L3.copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local made = {}
	for key, item in value do
		made[key] = W2L3.copy(item)
	end
	return made
end

function W2L3.same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not W2L3.same(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function W2L3.at(point: any, x: number, y: number, z: number): boolean
	return point ~= nil
		and near(point.X, x, 1e-9)
		and near(point.Y, y, 1e-9)
		and near(point.Z, z, 1e-9)
end

-- A whole entry like the generator writes, for `model`: grip at the origin, the tip along -Z.
function W2L3.entry(model: string): any
	return {
		model = model,
		points = {
			grip = { 0, 0, 0 },
			tip = { 0, 0.1, -3 },
			holster = { 0, 0, -1.5 },
			bladeBase = { 0, 0, -0.6 },
		},
		bounds = { min = { -0.2, -0.7, -3 }, max = { 0.2, 0.7, 0.6 } },
	}
end

-- A small models file: two families, the props folder "Weapons".
function W2L3.config(): any
	return {
		version = 1,
		folder = "Weapons",
		families = {
			broadsword = W2L3.entry("Broadsword"),
			longbow = W2L3.entry("Longbow"),
		},
	}
end

-- The config with one change made to broadsword's entry.
function W2L3.with(change: (entry: any, config: any) -> ()): any
	local config = W2L3.config()
	change(config.families.broadsword, config)
	return config
end

-- Assets.json with one icon entry: icons[set][model] = { imageId = id }.
function W2L3.assets(set: string, model: string, imageId: any): any
	return {
		version = 5,
		textures = {},
		eras = {},
		icons = { [set] = { [model] = { assetId = 99, imageId = imageId, sha256 = "x" } } },
	}
end

-- The weapons families a Problems case checks against: the config's two.
W2L3.WEAPONS = { broadsword = { slot = "melee" }, longbow = { slot = "ranged" } }

function W2L3.has(problems: { string }, text: string): boolean
	for _, problem in problems do
		if string.find(problem, text, 1, true) ~= nil then
			return true
		end
	end
	return false
end

function W2L3.nameTests(): ()
	print(" ModelName, the attribute names and Values (L3-46, L3-49)")
	local Look = W2L3.Look
	local wrong = {}
	for family, model in W2L3.MODELS do
		if Look.ModelName(family) ~= model then
			table.insert(wrong, `{family} -> {Look.ModelName(family)}`)
		end
	end
	table.sort(wrong)
	check(
		#wrong == 0,
		`ModelName capitalises the first letter of all 15 ids ({table.concat(wrong, ", ")})`
	)
	local count = 0
	local listed = true
	for family in FIXTURES.proving.weapons do
		count += 1
		listed = listed and W2L3.MODELS[family] ~= nil
	end
	check(count == 15 and listed, "the 15 ids are ProvingGrounds.json's weapons families")
	check(
		W2L3.same(
			Look.ATTRIBUTES,
			{ melee = "WeaponMelee", ranged = "WeaponRanged", held = "WeaponHeld" }
		) and table.isfrozen(Look.ATTRIBUTES),
		"the three attribute names, frozen"
	)
	local values = Look.Values({ melee = "spear", ranged = "smg" }, "ranged")
	check(
		W2L3.same(values, { WeaponMelee = "spear", WeaponRanged = "smg", WeaponHeld = "ranged" }),
		"Values: the held melee and ranged families and the slot in use, nothing else"
	)
	check(
		Look.Values({ melee = "spear", ranged = "smg" }, "melee").WeaponHeld == "melee",
		"Values: melee held"
	)
	check(
		Look.Values({ melee = "spear", ranged = "smg" }, "bogus").WeaponHeld == "melee"
			and Look.Values({ melee = "spear", ranged = "smg" }, "").WeaponHeld == "melee"
			and Look.Values({ melee = "spear", ranged = "smg" }, "Ranged").WeaponHeld == "melee",
		"Values: any other held word reads melee"
	)
end
L1.group("l3w2 nameTests", W2L3.nameTests)

function W2L3.readTests(): ()
	print(" Read: the attributes as a client reads them (L3-51)")
	local Look = W2L3.Look
	local function reader(values: any): (string) -> any
		return function(name: string): any
			return values[name]
		end
	end
	local melee, ranged, held =
		Look.Read(reader({ WeaponMelee = "spear", WeaponRanged = "smg", WeaponHeld = "ranged" }))
	check(melee == "spear" and ranged == "smg" and held == "ranged", "the pair and the slot in use")
	local m2, r2, h2 =
		Look.Read(reader(Look.Values({ melee = "greataxe", ranged = "beam" }, "melee")))
	check(m2 == "greataxe" and r2 == "beam" and h2 == "melee", "Read gives back what Values wrote")
	local m3, r3, h3 =
		Look.Read(reader({ WeaponMelee = 5, WeaponRanged = "", WeaponHeld = "Ranged" }))
	check(
		m3 == nil and r3 == nil and h3 == nil,
		"a number, an empty family and another held word read nil"
	)
	local m4, r4, h4 =
		Look.Read(reader({ WeaponMelee = { "spear" }, WeaponRanged = true, WeaponHeld = 1 }))
	check(m4 == nil and r4 == nil and h4 == nil, "a table, a boolean and a held number read nil")
	local m5, r5, h5 = Look.Read(reader({}))
	check(m5 == nil and r5 == nil and h5 == nil, "no attributes read nil (a bot, a rig)")
	local asked = {}
	Look.Read(function(name: string): any
		table.insert(asked, name)
		return nil
	end)
	table.sort(asked)
	check(
		W2L3.same(asked, { "WeaponHeld", "WeaponMelee", "WeaponRanged" }),
		`Read asks for the three attributes, each once ({table.concat(asked, ", ")})`
	)
end
L1.group("l3w2 readTests", W2L3.readTests)

function W2L3.defTests(): ()
	print(" Def: an entry is used only when whole (L3-48)")
	local Look = W2L3.Look
	local config = W2L3.config()
	check(
		Look.Def(config, "broadsword") == config.families.broadsword,
		"a whole entry is the entry"
	)
	check(Look.Def(config, "longbow") == config.families.longbow, "and the other one")
	check(Look.Def(nil, "broadsword") == nil, "no config: nil")
	check(Look.Def(config, "spear") == nil, "an unknown family: nil")
	check(
		Look.Def({ version = 1, folder = "Weapons" } :: any, "broadsword") == nil,
		"no families: nil"
	)
	check(Look.Def({ families = "x" } :: any, "broadsword") == nil, "families not a table: nil")
	check(Look.Def(config, 5 :: any) == nil, "a family that is not a string: nil")
	local cases = {
		{
			"the model in lower case",
			function(e)
				e.model = "broadsword"
			end,
		},
		{
			"another family's model",
			function(e)
				e.model = "Longbow"
			end,
		},
		{
			"no model",
			function(e)
				e.model = nil
			end,
		},
		{
			"no points",
			function(e)
				e.points = nil
			end,
		},
		{
			"no grip",
			function(e)
				e.points.grip = nil
			end,
		},
		{
			"no tip",
			function(e)
				e.points.tip = nil
			end,
		},
		{
			"no holster",
			function(e)
				e.points.holster = nil
			end,
		},
		{
			"a point of two numbers",
			function(e)
				e.points.tip = { 0, 0 }
			end,
		},
		{
			"a point of four numbers",
			function(e)
				e.points.holster = { 0, 0, -1, 0 }
			end,
		},
		{
			"a NaN",
			function(e)
				e.points.tip = { 0, W2L3.NAN, -3 }
			end,
		},
		{
			"an infinite number",
			function(e)
				e.points.holster = { 0, 0, math.huge }
			end,
		},
		{
			"a negative infinite number",
			function(e)
				e.points.grip = { -math.huge, 0, 0 }
			end,
		},
		{
			"a string in a point",
			function(e)
				e.points.tip = { 0, "0", -3 }
			end,
		},
		{
			"no bounds",
			function(e)
				e.bounds = nil
			end,
		},
		{
			"bounds.min of two numbers",
			function(e)
				e.bounds.min = { -0.2, -0.7 }
			end,
		},
		{
			"bounds.max with a NaN",
			function(e)
				e.bounds.max = { 0.2, W2L3.NAN, 0.6 }
			end,
		},
		{
			"min above max on x",
			function(e)
				e.bounds.min[1] = 0.3
			end,
		},
		{
			"min above max on y",
			function(e)
				e.bounds.min[2] = 0.8
			end,
		},
		{
			"min above max on z",
			function(e)
				e.bounds.max[3] = -3.5
			end,
		},
	}
	for _, case in cases do
		local mutated = W2L3.with(case[2])
		check(Look.Def(mutated, "broadsword") == nil, `{case[1]}: nil`)
		check(Look.Def(mutated, "longbow") ~= nil, `{case[1]}: the other entry still stands`)
	end
	local flat = W2L3.with(function(e)
		e.bounds.min[1] = 0
		e.bounds.max[1] = 0
	end)
	check(
		Look.Def(flat, "broadsword") ~= nil,
		"min equal to max on one axis is whole (a flat model)"
	)
	local badExtra = W2L3.with(function(e)
		e.points.bladeBase = { 0, 0 }
	end)
	check(
		Look.Def(badExtra, "broadsword") ~= nil,
		"a malformed extra point leaves the entry (Point refuses it)"
	)
end
L1.group("l3w2 defTests", W2L3.defTests)

function W2L3.pointTests(): ()
	print(" Point: a named point in the template's frame (L3-47, L3-48)")
	local Look = W2L3.Look
	local def = W2L3.entry("Broadsword")
	check(W2L3.at(Look.Point(def, "tip"), 0, 0.1, -3), "the tip")
	check(W2L3.at(Look.Point(def, "grip"), 0, 0, 0), "the grip, the origin")
	check(W2L3.at(Look.Point(def, "bladeBase"), 0, 0, -0.6), "an extra the builders wrote")
	check(Look.Point(def, "nock") == nil, "an absent point: nil")
	def.points.bladeBase = { 0, 0 }
	check(Look.Point(def, "bladeBase") == nil, "a point of two numbers: nil")
	def.points.bladeBase = { 0, W2L3.NAN, 1 }
	check(Look.Point(def, "bladeBase") == nil, "a point with a NaN: nil")
	def.points.bladeBase = { 0, 0, -math.huge }
	check(Look.Point(def, "bladeBase") == nil, "a point with an infinite number: nil")
	def.points.bladeBase = "0 0 -1"
	check(Look.Point(def, "bladeBase") == nil, "a point that is no table: nil")
	check(Look.Point({ model = "X" } :: any, "tip") == nil, "an entry with no points: nil")
	check(Look.Point(nil :: any, "tip") == nil, "no entry: nil")
end
L1.group("l3w2 pointTests", W2L3.pointTests)

function W2L3.iconTests(): ()
	print(" IconId: the shelf icon, else 0 (L3-48, L3-57)")
	local Look = W2L3.Look
	local config = W2L3.config()
	local id = 123456789
	check(
		Look.IconId(W2L3.assets("Weapons", "Broadsword", id), config, "broadsword") == id,
		"the id when all is there"
	)
	check(Look.IconId(nil, config, "broadsword") == 0, "no assets: 0")
	check(
		Look.IconId({ version = 4, textures = {}, eras = {} } :: any, config, "broadsword") == 0,
		"no icons: 0"
	)
	check(
		Look.IconId(W2L3.assets("Tools", "Broadsword", id), config, "broadsword") == 0,
		"no set: 0"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "Longbow", id), config, "broadsword") == 0,
		"no model: 0"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "broadsword", id), config, "broadsword") == 0,
		"keyed by the model name, never the family id"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "Broadsword", 0), config, "broadsword") == 0,
		"imageId 0: 0"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "Broadsword", -5), config, "broadsword") == 0,
		"negative: 0"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "Broadsword", 12.5), config, "broadsword") == 0,
		"fractional: 0"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "Broadsword", "123"), config, "broadsword") == 0,
		"a string: 0"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "Broadsword", W2L3.NAN), config, "broadsword") == 0,
		"NaN: 0"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "Broadsword", math.huge), config, "broadsword") == 0,
		"infinite: 0"
	)
	local noImage = W2L3.assets("Weapons", "Broadsword", id)
	noImage.icons.Weapons.Broadsword.imageId = nil
	check(Look.IconId(noImage, config, "broadsword") == 0, "an icon with no imageId: 0")
	check(
		Look.IconId(W2L3.assets("Weapons", "Broadsword", id), nil, "broadsword") == 0,
		"no models file: 0"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "Spear", id), config, "spear") == 0,
		"a family with no entry: 0"
	)
	local mismatched = W2L3.with(function(e)
		e.model = "Longbow"
	end)
	check(
		Look.IconId(W2L3.assets("Weapons", "Longbow", id), mismatched, "broadsword") == 0,
		"an entry Def refuses: 0"
	)
	local moved = W2L3.config()
	moved.folder = "Arms"
	check(
		Look.IconId(W2L3.assets("Arms", "Broadsword", 7), moved, "broadsword") == 7,
		"the set is the file's folder"
	)
	check(
		Look.IconId(W2L3.assets("Weapons", "Broadsword", 7), moved, "broadsword") == 0,
		"and only that folder"
	)
end
L1.group("l3w2 iconTests", W2L3.iconTests)

function W2L3.problemTests(): ()
	print(" Problems: every fault of a models file, on built copies (L3-48)")
	local Look = W2L3.Look
	local weapons = W2L3.WEAPONS
	local clean = Look.Problems(W2L3.config(), weapons)
	check(#clean == 0, `a whole file has no problem ({clean[1] or ""})`)
	local absent = Look.Problems(nil, weapons)
	check(
		#absent == 1 and W2L3.has(absent, "no families"),
		"no file: one problem, every hand empty"
	)
	-- One fault each: exactly one problem, and it names the family and the fault.
	local cases = {
		{
			"a missing family",
			"longbow: no model entry",
			function(_e, c)
				c.families.longbow = nil
			end,
		},
		{
			"an extra family",
			"dagger: not a weapons family",
			function(_e, c)
				c.families.dagger = W2L3.entry("Dagger")
			end,
		},
		{
			"the grip off the origin",
			"broadsword: its grip is not the origin",
			function(e)
				e.points.grip = { 0, 0.1, 0 }
			end,
		},
		{
			"a point outside its bounds",
			"broadsword: its tip lies outside its bounds",
			function(e)
				e.points.tip = { 0, 0.1, -3.02 }
			end,
		},
		{
			"a point outside its bounds above",
			"broadsword: its bladeBase lies outside its bounds",
			function(e)
				e.points.bladeBase = { 0, 0.72, -0.6 }
			end,
		},
		{
			"a malformed extra",
			"broadsword: its bladeBase is not three finite numbers",
			function(e)
				e.points.bladeBase = { 0, 0 }
			end,
		},
		{
			"a model that breaks the name rule",
			"broadsword: its model broadsword is not Broadsword",
			function(e)
				e.model = "broadsword"
			end,
		},
		{
			"no tip",
			"broadsword: its tip is not three finite numbers",
			function(e)
				e.points.tip = nil
			end,
		},
		{
			"bounds turned over",
			"broadsword: its bounds.min lies above its bounds.max",
			function(e)
				e.bounds.min[2] = 0.9
			end,
		},
		{
			"no folder",
			"WeaponModels.json names no folder",
			function(_e, c)
				c.folder = ""
			end,
		},
	}
	for _, case in cases do
		local problems = Look.Problems(W2L3.with(case[3]), weapons)
		check(
			#problems == 1 and problems[1] == case[2],
			`{case[1]}: "{case[2]}" ({#problems}: {problems[1] or ""})`
		)
	end
	local slack = Look.Problems(
		W2L3.with(function(e)
			e.points.tip = { 0, 0.1, -3.005 }
			e.points.holster = { 0.205, 0, -1.5 }
		end),
		weapons
	)
	check(#slack == 0, `a point 0.005 outside its bounds is inside the slack ({slack[1] or ""})`)
	local both = Look.Problems(
		W2L3.with(function(e, c)
			e.points.tip = { 0, 0.1, -3.05 }
			c.families.longbow.points.grip = { 0.01, 0, 0 }
		end),
		weapons
	)
	check(
		W2L3.same(both, {
			"broadsword: its tip lies outside its bounds",
			"longbow: its grip is not the origin",
		}),
		`two faults in two families, sorted by family ({table.concat(both, "; ")})`
	)
	-- The fix round's S5 (2-s4): the whole list is sorted, so a family the file lacks (found
	-- first, from the weapons' side) comes after an earlier family's fault in the file.
	local mixed = Look.Problems(
		W2L3.with(function(e, c)
			e.points.tip = { 0, 0.1, -3.05 }
			c.families.longbow = nil
		end),
		weapons
	)
	check(
		W2L3.same(mixed, {
			"broadsword: its tip lies outside its bounds",
			"longbow: no model entry",
		}),
		`a missing family and an earlier family's fault, in family order ({table.concat(mixed, "; ")})`
	)
end
L1.group("l3w2 problemTests", W2L3.problemTests)

-- WeaponModels.json as it ships (L3-46): the 15 families, whole, and no fault.
function W2L3.shippedTests(): ()
	print(" WeaponModels.json as it ships (L3-46)")
	local Look = W2L3.Look
	local models = FIXTURES.weaponModels
	if type(models) ~= "table" then
		check(false, "src/shared/Config/WeaponModels.json is there")
		return
	end
	check(models.version == 1 and models.folder == "Weapons", "version 1, folder Weapons")
	local problems = Look.Problems(models, FIXTURES.proving.weapons)
	check(
		#problems == 0,
		`Problems finds nothing ({#problems}{if #problems > 0 then ": " .. problems[1] else ""})`
	)
	local whole = {}
	local count = 0
	for family in models.families do
		count += 1
		local def = Look.Def(models, family)
		if def ~= nil and def.model == W2L3.MODELS[family] and Look.Point(def, "tip") ~= nil then
			table.insert(whole, family)
		end
	end
	check(count == 15 and #whole == 15, `all 15 families have a whole entry ({#whole} of {count})`)
	local away = {}
	for family in models.families do
		local def = Look.Def(models, family)
		local tip = if def ~= nil then Look.Point(def, "tip") else nil
		if tip == nil or tip.Magnitude < 0.3 then
			table.insert(away, family)
		end
	end
	table.sort(away)
	check(
		#away == 0,
		`every tip lies away from its grip, so a muzzle is never the hand ({table.concat(away, ", ")})`
	)
end
L1.group("l3w2 shippedTests", W2L3.shippedTests)

-- T1 to T14 (docs/prompts/l3-w2-contract.md §9), read as text: key = { expected count, what it pins }.
W2L3.LINES = {
	-- T1: WeaponService's one writer of the attributes.
	showSignature = { 1, "T1: showWeapons(shooter, character?) is the one writer" },
	showTarget = {
		1,
		"T1: it writes on the character given, else the live one, and nothing without one",
	},
	showValues = {
		1,
		"T1: every value of WeaponLook.Values(shooter.loadout, shooter.held) goes on it",
	},
	showExits = { 1, "T1: showWeapons' one way out is the missing character" },
	showCalls = {
		4,
		"T1: showWeapons is defined once and called three times (PrepareCharacter, SetFamily, noteHeld)",
	},
	lookReads = { 1, "T1: WeaponService reads WeaponLook only for the values it writes" },
	-- T2: every fresh character.
	prepareShow = {
		1,
		"T2: PrepareCharacter shows the weapons inside `if shooter ~= nil then`, after resetAir",
	},
	prepareActive = { 1, "T2: its one guard is the inactive service" },
	prepareExits = { 1, "T2: and PrepareCharacter has no other way out" },
	addPrepares = { 1, "T2: a mission's admit prepares the character it finds" },
	addMission = { 1, "T2 (S2): ... inside AddPlayer's own mission test, the code exactly" },
	addExits = { 1, "T2 (S2): and AddPlayer's one way out is its guard, before the shooter exists" },
	rangePrepares = { 1, "T2: the range prepares every character it places" },
	rangePrepareExits = { 0, "T2 (S2): and the range's prepareCharacter has no way out" },
	rangeAddWeapons = { 1, "T2 (S2): the range's AddPlayer gives the weapons first ..." },
	rangeRespawn = { 1, "T2 (S2): ... prepares every respawn ..." },
	rangeFirst = { 1, "T2 (S2): ... and the character it finds at its admit" },
	rangeAddExits = { 1, "T2 (S2): its one way out is its guard" },
	missionHook = {
		1,
		"T2 (S2): a mission's Init hands PrepareCharacter to ArenaService's hook, a whole line at one tab",
	},
	initExits = {
		3,
		"T2 (S2): Init's ways out are the range's return and its two sources' answers",
	},
	hookSetters = { 1, "T2 (S2): WaveService sets the character hook once" },
	arenaHookSet = { 1, "T2 (S2): ArenaService keeps the hook it is handed ..." },
	hookWrites = { 1, "T2 (S2): ... and writes it nowhere else" },
	arenaHook = {
		1,
		"T2 (S2): every character an admitted member gets is placed, then handed to the hook",
	},
	-- T3: every loadout change.
	familyShow = {
		1,
		"T3: SetFamily shows the pair after writing it and drawStartedAt = 0, outside `if previous ~= family`",
	},
	familySlot = { 1, "T3: SetFamily's slot is the family's own" },
	familyExits = { 3, "T3: SetFamily's ways out: no shooter, no family, done" },
	-- T4, T5: an accepted attack and draw.
	attackHeld = { 1, "T4: OnAttack notes the slot on the line after the acceptance (lastSeq)" },
	attackSlot = { 1, "T4: OnAttack's slot is the attacking family's own" },
	attackExits = { 12, "T4: OnAttack's ways out are its refusals" },
	attackExitsAfter = { 0, "T4 (S5): none of them after the noted line" },
	drawHeld = { 1, "T5: OnDraw notes the slot on the line after the draw is stamped, its last" },
	drawSlot = { 1, "T5: OnDraw's slot is the drawing family's own" },
	drawRanged = {
		1,
		"T5 (S4): OnDraw refuses a family not of the ranged slot, beside its other refusals",
	},
	drawExits = { 3, "T5: OnDraw's ways out are its refusals" },
	-- T6: a cast, before its effect is sent (S6).
	castHeld = {
		1,
		"T6 (S6): OnCast notes the cast's slot on the line before its effect is sent",
	},
	castSlot = { 1, "T6: the cast's slot is its own" },
	castNotes = { 1, "T6: AbilityService tells WeaponService once" },
	castExits = { 9, "T6: OnCast's ways out are its refusals" },
	castExitsAfter = {
		1,
		"T6 (S5, S6): one of them after the noted line, the projectile budget's",
	},
	-- T7: shown only on a change.
	noteBody = { 1, "T7: noteHeld returns on the same slot, else writes it and shows it" },
	noteExits = { 1, "T7: noteHeld's one way out is the same slot" },
	noteGuard = { 1, "T7: NoteHeld ignores a player without weapons and any other slot word" },
	noteCall = { 1, "T7: and notes melee or ranged" },
	NoteExits = { 1, "T7: NoteHeld's one way out is its guard" },
	noteCalls = { 4, "T7: noteHeld is defined once and called by OnAttack, OnDraw and NoteHeld" },
	heldWrites = { 1, "T7: `held` is written in noteHeld alone" },
	heldIndexed = { 0, 'T7 (S5): and never by index (["held"])' },
	loadoutWrites = { 2, "T1, T3: the held pair is written in SetFamily alone, which shows it" },
	loadoutWhole = { 0, "T1, T3 (S5): and no whole loadout replaces it" },
	lookLiterals = {
		0,
		"T1 (S5): no file under src but WeaponLook spells an attribute name as a literal",
	},
	addHeld = { 1, "T7: a new shooter holds melee, the client's starting stance" },
	-- T8: no hit reads the look.
	hit_damageScale = { 0, "T8: damageScale reads no look" },
	hit_meleeOrigin = { 0, "T8: meleeOrigin reads no look" },
	hit_aimAllowed = { 0, "T8: aimAllowed reads no look" },
	hit_claimSlack = { 0, "T8: claimSlack reads no look" },
	hit_resolveMelee = { 0, "T8: resolveMelee reads no look" },
	hit_resolveRanged = { 0, "T8: resolveRanged reads no look" },
	hit_strike = { 0, "T8: strike reads no look" },
	heldReads = {
		3,
		"T8 (S1): WeaponService reads `held` in the Values call and noteHeld's compare and write alone",
	},
	abilityHeld = { 0, "T8 (S1): AbilityService never reads `held`" },
	-- T9: another player's arm.
	otherInBranch = {
		1,
		"T9: SwingOther(strike.userId, strike.step or 1) a whole line one tab inside `elseif swing and not mine then`",
	},
	otherBlocks = { 0, "T9 (S3): with no line opening a block between the branch head and it" },
	otherFlush = {
		1,
		"T9 (G1): HeldWeapons.Flush(strike.userId) a whole line one tab inside the branch ...",
	},
	otherFlushFirst = { 1, "T9 (G1): ... its first code line ..." },
	otherFlushBefore = {
		1,
		"T9 (G1): ... before SwingOther, so a slot change lowers the arm before the swing starts",
	},
	otherCalls = { 1, "T9: FeedbackController calls SwingOther there alone" },
	otherRequire = { 1, "T9: FeedbackController requires WeaponController" },
	otherMine = { 1, "T9: mine is the strike's own user" },
	otherSwing = { 1, "T9: a swing is a weapon's melee strike, never an ability or a tick" },
	otherWired = { 1, "T9: onStrike is reached from the strike remote" },
	strikeExits = {
		1,
		"T9: onStrike's one way out before the SwingOther call is an empty flight's end (ruling 7)",
	},
	-- T10: one muzzle.
	feedbackHand = { 0, 'T10: no "RightHand" in FeedbackController' },
	feedbackOwnMuzzle = { 0, "T10: FeedbackController has no muzzleOf of its own" },
	feedbackHeld = { 7, "T10: its seven tracer sites call (HeldWeapons.Muzzle(userId))" },
	feedbackMuzzles = { 7, "T10: and FeedbackController asks for the muzzle nowhere else" },
	flameHand = { 0, 'T10: no "RightHand" in FlameFx' },
	flameHeld = {
		1,
		"T10: FlameFx's muzzleOf asks HeldWeapons.Muzzle for the point and where it is from",
	},
	flamePush = { 1, "T10: and pushes it along the aim only when it is not a model's tip" },
	sharedHands = { 1, 'T10: AbilityFx/Shared names "RightHand" once ...' },
	sharedHandOf = { 1, "T10: ... inside handOf" },
	sharedHeld = {
		1,
		"T10: AbilityFx/Shared's muzzleOf asks HeldWeapons.Muzzle, the fallback with no character",
	},
	sharedPush = { 1, "T10: and pushes the point along the aim only when it is not a model's tip" },
	magMuzzles = { 2, "T10: MagDump's two `muzzle =` lines ..." },
	magFromHelper = { 2, "T10: ... both take it from muzzleOf" },
	magHelper = { 1, "T10: MagDump's muzzleOf is AbilityFx/Shared's" },
	magOldMuzzle = { 0, "T10: MagDump no longer pushes its hand forward itself" },
	pointIsHelper = { 1, "T10: WeaponController's muzzlePoint is the helper call alone" },
	heldHands = { 1, 'T10: HeldWeapons names "RightHand" once ...' },
	heldHandList = { 1, "T10: ... in its one hand list" },
	heldFallback = { 1, "T10: HeldWeapons.Muzzle falls back to that list's hand" },
	heldTip = {
		1,
		"T10: HeldWeapons.Muzzle answers the tip of the model in the hand, from a model",
	},
	controllerCycle = {
		0,
		"L3-53: WeaponController requires neither FeedbackController nor InputController",
	},
	heldCycle = { 0, "L3-53: HeldWeapons requires none of the controllers that call it" },
	heldStarted = { 1, "L3-51: WeaponController.Start starts HeldWeapons" },
	heldStance = { 1, "L3-54: SetStance cancels the pose and hands HeldWeapons the local stance" },
	-- T11 to T13: HeldWeapons.
	heldClones = { 1, "T11: HeldWeapons clones in one place ..." },
	modelClones = { 1, "T11: ... modelFor" },
	heldCached = { 1, "T11: modelFor answers from the cache first" },
	cacheBeforeClone = { 1, "T11: the clone comes after the cache's answer" },
	heldFrames = { 0, "T11: no RunService in HeldWeapons (never per frame)" },
	sealCalls = { 1, "T12: modelFor seals the clone" },
	sealBeforeParent = { 1, "T12: before its first parent" },
	sealLoop = { 1, "T12: seal visits every BasePart of the clone" },
	seal1 = { 1, "T12: seal unanchors" },
	seal2 = { 1, "T12: seal turns collisions off" },
	seal3 = { 1, "T12: seal turns queries off" },
	seal4 = { 1, "T12: seal turns touches off" },
	seal5 = { 1, "T12: seal makes it massless" },
	sealUndone = { 0, "T12 (S3): no line of HeldWeapons turns one of them back" },
	heldDeep = { 0, "T13: no recursive FindFirstChild in HeldWeapons" },
	-- T14: the stage's turn.
	stageReduced = { 0, "T14: ArmoryStage never reads Theme.reducedMotion" },
	stageFrames = { 1, "T14: ArmoryStage connects RenderStepped once ..." },
	activeFrames = { 1, "T14 (C3): ... in syncTurn ..." },
	gatedFrames = {
		1,
		"T14 (S3, C3): ... behind exactly `if look.turn == nil and not Theme.lowEndDevice then`",
	},
	stagePoses = { 1, "T14: the model is posed once ..." },
	selectPoses = { 1, "T14: ... in the select path" },
	selectPose = { 1, "T14: to the display pose, the tip rising by ARMORY_STAGE_TILT_DEGREES" },
	screenActive = {
		1,
		"T14: the screen turns the stage on while open on the Weapons tab, off on the others",
	},
	screenClosed = { 1, "T14: and off when it closes" },
	-- The fix round's S3 (3-m3) and C1 to C3, the stage.
	stageStops = { 1, "S3: SetActive(false) stops the stage" },
	activeSyncs = { 1, "C3: SetActive(true) syncs the turn, after the warm-up" },
	setActiveExits = { 2, "C3: SetActive's ways out: the same state, and the close" },
	selectClears = { 1, "S3: a selection destroys the previous clone first" },
	selectBase = { 1, "C1: the stage's clone finds Base by name and makes it PrimaryPart" },
	baseBeforePose = { 1, "C1: before the pose" },
	stageTemplateBase = { 1, "C1: a stage template with no Base counts as missing" },
	stageBaseName = { 1, 'C1: the stage names its Base "Base"' },
	stagePrimaryReads = { 0, "C1: the stage never reads a PrimaryPart ref" },
	syncStops = {
		1,
		"C3: syncTurn stops everything unless the screen is open on Weapons with a model",
	},
	syncCalls = { 4, "C3: syncTurn is called on SetActive(true), Show(nil) and a selection" },
	syncExits = { 2, "C3: syncTurn's ways out: the stop, and the turn's wait for a drag" },
	syncStep = {
		1,
		"C3: the per-frame turn turns the view at ARMORY_STAGE_TURN_DEGREES_PER_SECOND",
	},
	syncFocusOnce = { 1, "C3: a live stage connects one focus listener ..." },
	syncFocus = { 1, "C3: ... and a lost window focus ends a drag" },
	stopDrops = { 1, "C3: stop drops the focus listener and any drag" },
	stageSticks = { 0, "G3: no gamepad stick turns the stage (the world camera reads it unsunk)" },
	showNilSyncs = { 1, "C3: Show(nil) clears the clone and syncs (the stage stops)" },
	selectSyncs = { 1, "C3: a selection syncs" },
	stageSilhouette = { 1, "S3: an unowned model is the near-black silhouette" },
	dragLost = { 1, "C3: a mouse move with the button up ends a drag" },
	dragEnds = { 1, "C3: a drag ends on its own release" },
	shelfGhost = { 1, "C2: an unowned shelf icon takes the ghost tone" },
	shelfSilhouette = { 0, "C2: the shelf never draws the stage's silhouette" },
	-- S3 (3-m3) and C1, C4, HeldWeapons.
	heldCleanup = { 1, "S3: a family that leaves the loadout is destroyed" },
	heldWatched = { 1, "S3: all three attributes are watched, each change queued (C4)" },
	heldMountShows = { 1, "S3: a mount part arriving is watched and re-shows" },
	attachShows = { 1, "S3: an attachment arriving re-shows" },
	bindShows = { 1, "S3: bind ends on a show" },
	bindExits = { 0, "S3: bind has no way out" },
	stanceShows = { 1, "S3: the local switch shows at once, on its own frame" },
	stanceExits = { 1, "S3: SetLocalStance's one way out is the same stance" },
	playerWatch = { 1, "S3: every player who joins is watched ..." },
	playersNow = { 1, "S3: ... and every player already in" },
	startExits = { 1, "S3: Start's one way out is a second start" },
	heldDirectShows = { 4, "C4: show(rig) direct in flush, bind, SetLocalStance and refreshAll" },
	heldQueues = { 3, "C4: queued from the attribute, mount part and attachment handlers" },
	queueOnce = { 1, "C4: one deferred flush per batch" },
	flushShows = { 1, "C4: the flush shows a pending change of a rig still bound" },
	unbindUnbinds = { 1, "C4: unbind marks the rig gone" },
	muzzleFlushes = { 1, "C4, 3-m1 (G1): Muzzle's first line is HeldWeapons.Flush(userId) ..." },
	muzzleFlushFirst = { 1, "G2: ... before it reads the hand" },
	flushPublic = {
		1,
		"G1: Flush shows the pending change of that player's current character's rig",
	},
	flushPublicExits = { 0, "G1: Flush has no way out" },
	rigPending = { 1, "G2: a new rig starts with no show pending (else queueShow never defers)" },
	rigBound = { 1, "G2: a new rig starts bound (else every queued show is dropped)" },
	heldBaseName = { 1, 'C1: HeldWeapons names its Base "Base"' },
	heldTemplateBase = { 1, "C1: a template with no Base counts as missing" },
	heldBase = { 1, "C1: the clone finds Base by name and makes it PrimaryPart" },
	baseBeforeWelds = { 1, "C1: before any weld" },
	heldPrimaryReads = { 0, "C1: HeldWeapons never reads a PrimaryPart ref" },
	-- The lead's ruling 6 (§11), HeldWeapons: the hold each slot hangs by, and the raised hand.
	hangHold = {
		1,
		"R6: the back holds by COMBAT_HOLD_BACK, a ranged hand _GRIP_RANGED, a melee hand _GRIP_MELEE",
	},
	hangPoint = { 1, "R6: the hand hangs a model by its grip, the back by its holster" },
	hangWeld = {
		1,
		"R6: the weld takes the attachment, the hold and the point, then the model hangs",
	},
	hangExits = { 4, "R6: hang's ways out: no family, no mount, no model, hung" },
	showSlot = {
		1,
		"R6: the slot in use is the local stance for the local character, WeaponHeld for others",
	},
	showRaised = {
		1,
		"R6: the hand is held as its slot holds, raised only while a ranged model is in it",
	},
	showTold = { 1, "R6: each change of the raised hand is kept and told to the listener" },
	heldShowExits = {
		2,
		"R6: show's one way out is a character gone (and the attribute reader's answer)",
	},
	holdSet = { 1, "R6: OnHold keeps the listener" },
	holdReplay = { 1, "R6: and tells it at once of every hand already raised" },
	holdSetExits = { 1, "R6: OnHold's one way out is a cleared listener" },
	-- Ruling 6, WeaponController: every pose ends at the rest.
	restRaise = { 1, "R6: the rest is COMBAT_HOLD_RANGED_RAISE_DEGREES for a raised hand, else 0" },
	restAngle = { 1, "R6: the rest frame turns the hanging arm by the rest" },
	cancelRest = { 1, "R6: cancelRig ends with motor.C0 = restFrame(rig)" },
	cancelExits = { 0, "R6: cancelRig has no way out before it" },
	setRestWrite = { 1, "R6: setRest writes a new rest" },
	swingSettle = { 1, "R6: the swing's last leg goes back to rig.rest" },
	swingExits = { 5, "R6: swingRig's ways out are its old ones" },
	releaseRest = { 1, "R6: Release goes back to localPose.rest" },
	releaseExits = { 1, "R6: Release's one way out is a missing shoulder" },
	kickRest = { 1, "R6: the shot kick is localPose.rest + COMBAT_SHOOT_KICK_DEGREES" },
	kickReleased = { 1, "R6: and the kick is released back to the rest" },
	holdWired = { 1, "R6: Start hands HeldWeapons.OnHold(onHold) before HeldWeapons.Start()" },
	onHoldBody = { 1, "R6: onHold keeps the raised hand and eases the other's or the local rest" },
	onHoldExits = { 0, "R6: onHold has no way out" },
	bindRest = { 1, "R6: the local shoulder, once found, takes the rest at once" },
	remoteRest = { 1, "R6: another player's record starts at its rest" },
	setRestEase = { 1, "R6 (S3): a new rest eases the arm there at once" },
	setRestExits = { 2, "R6 (S3): setRest's ways out are the same rest and no shoulder" },
	remoteSnap = {
		1,
		"R6 (S3): another player's fresh record snaps a raised arm up",
	},
	remotePoseExits = { 2, "R6 (S3): remotePoseFor answers its cached record or the fresh one" },
	restWrites = { 6, "R6: the rest is written by setRest, the records' starts and resets only" },
	raisedWrites = { 1, "R6: the raised set is written by onHold alone" },
}

function W2L3.sourceTests(): ()
	print(" T1 to T14 and ruling 6, read as text (L3-49 to L3-56, §11 item 6)")
	local reading = FIXTURES.source.l3w2
	local missing = {}
	for name, found in reading.found do
		if not found then
			table.insert(missing, name)
		end
	end
	table.sort(missing)
	check(
		#missing == 0,
		`every function the lines live in is there ({table.concat(missing, ", ")})`
	)
	local unknown = {}
	for key in reading.counts do
		if W2L3.LINES[key] == nil then
			table.insert(unknown, key)
		end
	end
	table.sort(unknown)
	check(
		#unknown == 0,
		`every line read has an expected count here ({table.concat(unknown, ", ")})`
	)
	local keys = {}
	for key in W2L3.LINES do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local expected = W2L3.LINES[key]
		local count = reading.counts[key]
		check(
			count == expected[1],
			`{expected[2]} ({key}: {tostring(count)}, expected {expected[1]})`
		)
	end
end
L1.group("l3w2 sourceTests", W2L3.sourceTests)

-- L4 W1b (docs/prompts/l4-w1b-contract.md §4, §5): the service lines that apply L4B-7 and L4B-8, read as
-- text (FIXTURES.source.l4b, run_harness.py's L4B_LINES and L4B_ORDER; none of the three services
-- loads here). The rules themselves are tests_l4b.luau's (DashProof) and tests_l4b_run.luau's (RunFloors).
local L4BP: any = {
	LINES = {
		dashGrantsNothing = { 0, "WeaponService.OnDash grants nothing: no GrantIframes, DashProof, showIframes or window write (L4B-7)" },
		dashClaim = { 1, "OnDash records the claim at the request (dashClaimAt = now)" },
		dashStamp = { 1, "and stamps the cooldown (lastDashAt = now)" },
		dashDown = { 1, "and refuses a downed player" },
		trackRecordThenProve = { 1, "trackAir proves a pending claim right after this frame's ring sample" },
		trackNoRootClears = { 1, "and a frame with no living root drops the claim" },
		trackEach = { 1, "trackAir runs each shooter under its own xpcall, the loop holding nothing else (H2)" },
		trackOneDefined = { 1, "one shooter's air tracking (trackOne) lives inside trackAir (H2)" },
		trackOneNames = { 2, "trackOne is named twice: its definition and the xpcall (H2)" },
		proveStep = { 1, "proveDash runs DashProof.Step on the ring, now, the root, the rule and dashIframes" },
		proveShows = { 1, "and shows the attribute only for a proof" },
		proveWritesNothing = { 0, "proveDash itself writes no claim and no window (Step does)" },
		ruleRead = { 1, "the rule is read from movement and shooting (dashRule)" },
		ruleCalls = { 1, "DashProof.Rule( is spelled once" },
		pendingNoClaim = { 1, "pendingDash answers 0, 0, 0 before building a rule when there is no claim (s2)" },
		pendingClaim = { 1, "pendingDash answers DashProof.Pending on the shooter's claim (F1)" },
		hookClaim = { 1, "VitalsService is handed pendingDash as its dashClaim hook (F1)" },
		stepHead = { 1, "step opens with the clock, then the proofs, then VitalsService, nothing between (G3)" },
		stepVitals = { 1, "WeaponService's step runs VitalsService.Step under xpcall (F1: one handler; G2)" },
		stepRest = { 1, "and the rest under xpcall (G2)" },
		startConnects = { 1, "Start connects step itself to the Heartbeat (G3)" },
		stepFailedBody = { 1, "stepFailed as one block: each message warned once, with its traceback, never silent (G2; m2)" },
		vitalsStepCalls = { 1, "VitalsService.Step is named once" },
		heartbeats = { 1, "WeaponService connects one Heartbeat" },
		grantOpens = { 1, "GrantIframes opens from now, or the earlier `from` (G1), through DashProof.Open, then shows it" },
		openCalls = { 1, "DashProof.Open( is spelled once in WeaponService (GrantIframes)" },
		stepCalls = { 1, "DashProof.Step( is spelled once (proveDash)" },
		claimWrites = { 3, "shooter.dashClaimAt is written three times: OnDash, trackAir's no-root clear, resetAir" },
		resetDropsClaim = { 1, "resetAir drops a pending claim" },
		runStateSpelled = { 1, "ArenaService spells \"RunState\" once: sendRunState's FireClient (L4B-8)" },
		sendRunStateCalls = { 3, "sendRunState( three times: its definition, sendSummaryTo, Broadcast" },
		attachCalls = { 2, "RunFloors.Attach( twice: sendRunState and BuildRunState" },
		sendSkip = { 1, "sendRunState reaches Attach only for a member not noted for this set (slice 2 s1)" },
		sendAttach = { 1, "and asks Attach with the member's note" },
		sendCellsWent = { 1, "and swaps the cells in only when Attach says they went (F3)" },
		sendClone = { 1, "on a copy of the RunState, never the one Broadcast shares (F3)" },
		sendFloors = { 1, "and sends the floors Attach answered" },
		sendFloorsWrites = { 1, "sent.floors is written only there" },
		sendNote = { 1, "and records the set it sent" },
		sendFires = { 1, "and fires what it built (sent), not the bare RunState" },
		buildAttach = { 1, "BuildRunState builds its floors with no cells (sentSeq = the set)" },
		buildFloors = { 1, "BuildRunState's payload carries those floors" },
		buildSeq = { 1, "and the set's number" },
		admitClears = { 1, "Admit clears the member's note: a rejoin gets the cells" },
		removeClears = { 1, "Remove clears it too" },
		noteWrites = { 3, "play.cellsSent[...] is written three times (the send, Admit, Remove)" },
		floorsAssigned = { 1, "WaveService assigns run.floors once (in setFloors)" },
		seqRaised = { 1, "setFloors raises boot.floorsSeq" },
		seqWrites = { 1, "and nothing else writes it" },
		setFloorsCalls = { 4, "setFloors( four times: its definition, the start, the lobby, Reset" },
		startSets = { 1, "a start's floors are a new set" },
		lobbySets = { 2, "the lobby's and a session reset's empty list are new sets too" },
		pushSeq = { 1, "pushRunFields hands the set's number to ArenaService" },
		uiHeld = { 1, "applyFloors merges against what it holds (F3)" },
		uiMerge = { 1, "and through RunFloors.Merge with the held set's number" },
		uiSeq = { 1, "then keeps the incoming set's number" },
		uiKeep = { 1, "and keeps the merged floors" },
		uiCall = { 1, "onRunState hands over the floors with the RunState's floorsSeq (0 when missing)" },
		uiApplyCalls = { 2, "applyFloors( twice: its definition and onRunState" },
		uiMergeCalls = { 1, "RunFloors.Merge( once in CombatUIController" },
		uiSeqWrites = { 1, "st.floorsSeq is written only there" },
		uiConnect = { 1, "onRunState is the RunState listener" },
		mentorTotal = { 1, "payMentors weighs every share against the sum of the boss's damage (s1)" },
		mentorNone = { 1, "payMentors pays nobody when nobody hurt the boss (F6)" },
		mentorFloor = { 1, "a mentor waiting in the lobby camp or under the damage floor is not paid" },
		menteeOther = { 1, "a mentee is another member" },
		menteeFloor = { 1, "whose share of the boss reached the floor" },
		menteeRate = { 1, "and the mentee's own income rate is what is weighed" },
		mentorBonusCall = { 1, "against the mentor's rate, through Combat.MentorBonus (check_stage_mirror compares it)" },
		mentorValor = { 1, "the bonus goes to the mentor's Valor" },
		mentorCard = { 1, "and onto the mentor's card" },
		mentorNoBonus = { 1, "a mentor whose bonus is nothing gets no Valor, card or toast (s1)" },
		mentorBonusCalls = { 1, "Combat.MentorBonus( once in WaveService" },
		bossPaysMentors = { 1, "the boss's kill pays the mentors" },
		h1Body = { 1, "fieldHeld as one block: a waiting blow holds a clear field, the down keeps the tick's finding, the cap (H1)" },
		h1Asks = { 1, "fieldHeld asks HasWaiting of every fighter" },
		h1DownKeeps = { 1, "the down's advance keeps the last tick's finding (its list is already empty)" },
		h1Notes = { 1, "the tick notes what it found" },
		h1ClearOnly = { 1, "only a field that would read clear is held" },
		h1Resets = { 1, "the deferral starts over when nothing waits" },
		h1Starts = { 1, "the deferral's start is noted" },
		h1Rule = { 1, "the lapse is the rule WeaponService proves claims by" },
		h1Lapse = { 1, "no rule, no lapse (nothing can wait)" },
		h1Cap = { 1, "never held longer than a lapse and the frame" },
		h1Writes = { 3, "blowWaits and heldSince are written only in fieldHeld" },
		h1Defs = { 1, "fieldHeld is defined once" },
		h1Calls = { 2, "fieldHeld( twice: its definition and advance" },
		h1AdvanceDelta = { 1, "advance takes the frame (nil from OnDown)" },
		h1AdvanceHolds = { 1, "advance asks fieldHeld with the frame" },
		h1AdvanceHoldWrites = { 1, "a held field does not read clear" },
		h1SpawningWrites = { 1, "input.spawningDone is written only there" },
		h1AdvanceCalls = { 2, "advance is called by the tick and by OnDown" },
		h1TickDelta = { 1, "tick takes the Heartbeat's frame" },
		h1TickAdvance = { 1, "the tick passes its frame to advance" },
		h1DownAdvance = { 1, "OnDown passes none: the down keeps the tick's finding" },
		h1BootTick = { 1, "Boot's Heartbeat passes its frame to the tick" },
		h1FreshBlowWaits = { 1, "a run starts with no blow found" },
		h1FreshHeldSince = { 1, "and no deferral" },
		h1DashProof = { 1, "WaveService requires DashProof for the lapse" },
	},
	ORDER = {
		trackOrder = "trackAir: the ring sample comes before the claim is judged",
		frameOrder = "step: the proofs (trackAir) come before VitalsService decides (F1)",
		restLast = "step: the rest after VitalsService (G2)",
		sendOrder = "sendRunState: Attach comes before the note",
		uiMergeThenSeq = "applyFloors: the merge reads the held number before it is replaced",
		uiMergeThenSame = "and the comparison sees the merged floors",
		uiGuardThenFloors = "onRunState: the floors after the guard",
		uiFloorsFirst = "and before the new-level branch (F4)",
		mentorFloorThenPay = "payMentors: the mentor's floor is tested before the pay",
		bonusGuardThenPay = "payMentors: a bonus of nothing is turned back before the pay (s1)",
		h1InputThenHold = "advance: the hold reads the input it has built (H1)",
		h1HoldThenAdvance = "advance: the hold before StageFlow decides (H1)",
	},
}

function L4BP.sourceTests(): ()
	print(" L4 W1b: the lines that apply the dash proof and the floor sets (source.l4b)")
	local reading = FIXTURES.source.l4b
	check(
		#reading.missing == 0,
		`every function the lines live in is there ({table.concat(reading.missing, ", ")})`
	)
	local keys = {}
	for key in L4BP.LINES do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local expected = L4BP.LINES[key]
		local count = reading.counts[key]
		check(count == expected[1], `{expected[2]} ({key}: {tostring(count)}, expected {expected[1]})`)
	end
	local unknown = {}
	for key in reading.counts do
		if L4BP.LINES[key] == nil then
			table.insert(unknown, key)
		end
	end
	for key, text in L4BP.ORDER do
		check(reading.order[key] == true, `{text} ({key})`)
	end
	for key in reading.order do
		if L4BP.ORDER[key] == nil then
			table.insert(unknown, key)
		end
	end
	table.sort(unknown)
	check(#unknown == 0, `every line read has an expected count here ({table.concat(unknown, ", ")})`)
end
L1.group("l4b sourceTests", L4BP.sourceTests)

-- L4 W2 (docs/prompts/l4-w2-contract.md 2.2, 3.2, 5, 8, section 0) and its fix round (K3, K7, K8, K9):
-- the service lines that lay LevelDress's answer, lower a seated head in every hit, send the pools'
-- counts, carry the chest's key and pull the Z lever, and the client lines that act on ScenePlan's
-- answers and read the seat, read as text (FIXTURES.source.l4w2, run_harness.py's L4W2_LINES and
-- L4W2_ORDER). The rules themselves are tests_l4w2.luau's and tests_l4w2_scenery.luau's. On L4BP (the
-- bundle's 200-local limit).
L4BP.W2 = {
	LINES = {
		constructLooks = { 1, "construct builds in the laid looks (the dress's over Expeditions.json's)" },
		constructHidden = { 1, "construct reads the hidden names from the laid answer" },
		constructPieces = { 1, "and builds the laid pieces (the walls among them)" },
		constructSkips = { 2, "leaving one out only when the groups were refused (one continue; one return, at the end)" },
		constructWallRole = { 1, "construct knows a dress wall by LevelDress.WALL_ROLE" },
		constructNoGroupNoWall = { 1, "and builds no wall, a camp's or the dress's, when the groups were refused" },
		constructWallBranch = { 1, "a dress wall has a branch of its own" },
		constructGroups = { 2, "the camp's wall and the dress wall are each put in BarrierGroups.BARRIER" },
		constructArmed = { 1, "the dress wall collides from the build (no camp opens it)" },
		constructWallLook = { 1, "the dress wall is unseen, untouched, shadowless and armed, in that branch" },
		constructCollides = { 3, "construct writes CanCollide three times: a piece that does not collide, the camp's wall off, the dress wall on" },
		constructSkinnedIf = { 1, "a hidden piece is known by its name in the laid set" },
		constructSkinned = { 1, "and marked Skinned" },
		constructSkinnedWrites = { 1, "made invisible and shadowless, collision and query untouched, before it is parented" },
		placeConstruct = { 1, "place builds the laid answer under its pcall" },
		raiseBase = { 1, "the lobby's base looks are Expeditions.json's" },
		raiseLaid = { 1, "and the lobby is laid grey in them" },
		templatesIds = { 1, "templatesOf lists each Model's MeshIds" },
		templatesMeshPart = { 1, "from its MeshParts" },
		templatesMeshId = { 1, "each one's own MeshId (LevelDress.Present judges it)" },
		templatesFound = { 1, "under the Model's name" },
		dressFailRead = { 1, "dressOf reads the Z lever" },
		dressFailSpent = { 1, "and spends it, taken or not" },
		dressFailWrites = { 1, "the lever is written once in dressOf" },
		dressAccept = { 1, "Decide is asked with the dress, the uploaded hash, the lever, the templates, the layout, the pieces, the found shortcuts, the groups, maxParts and the layout's name" },
		dressRefused = { 1, "a refused dress is known by a nil answer" },
		dressGreyWarns = { 1, "and warns once that the level is grey" },
		dressAnswers = { 1, "dressOf answers Decide's answer as it is" },
		buildNilDress = { 1, "Build clears Dress first" },
		buildNilHash = { 1, "and DressHash" },
		buildAcceptedNil = { 1, "Build starts with no dress" },
		buildNamed = { 1, "and asks for one only of a level with a name" },
		buildDressOf = { 1, "Build asks dressOf with the pieces and the shortcut set" },
		buildAcceptedWrites = { 1, "the answer is written once" },
		buildLay = { 1, "LevelDress.Lay lays the answer over Expeditions.json's looks" },
		buildPlace = { 1, "and the laid answer is placed" },
		buildLooks = { 1, "SetCamp's looks are the laid ones" },
		buildWord = { 1, "the word comes from the laid answer" },
		buildWorded = { 1, "and is written only when there is one" },
		buildDressHash = { 1, "Build sets DressHash to the word's plan hash" },
		buildDress = { 1, "and Dress to the word's layout" },
		buildDressWrites = { 4, "Build writes the two attributes four times: nil first, the word last" },
		clearNilDress = { 1, "Clear clears Dress" },
		clearNilHash = { 1, "and DressHash" },
		gatherRestDrop = { 1, "gather reads crowd.restDrop" },
		gatherDrop = { 1, "gather drops each candidate's head by its seat (HitShapes.SeatDrop, crowd.restDrop)" },
		gatherHead = { 1, "the head at height - headRadius - drop" },
		gatherTest = { 1, "and the drop handed to the test" },
		gatherSeatDrops = { 1, "SeatDrop is asked once in gather" },
		rayDrop = { 1, "rayCandidates hands CrowdRay the drop" },
		startPrewarm = { 1, "startLevel keeps the plan's kinds as the run's prewarm" },
		startBuild = { 1, "and builds the level with the level file's layout (the dress's name)" },
		pushPrewarm = { 1, "pushRunFields hands the lobby's kinds in the lobby, the run's prewarm otherwise" },
		lobbyOnce = { 1, "refreshLobbyKinds runs until it has an answer, once per floor set" },
		lobbySeq = { 1, "and notes the floor set it tried" },
		lobbyLevels = { 1, "it plans every built level" },
		lobbyDifficulties = { 1, "at every difficulty" },
		lobbyResolve = { 1, "resolved as startLevel resolves it" },
		lobbyPlan = { 1, "and planned as startLevel plans it" },
		lobbyBounds = { 1, "in the layout's bounds" },
		lobbyKindsTuned = { 1, "with the tuned crowd kinds" },
		lobbyKeeps = { 1, "each plan's kinds kept" },
		lobbyMerged = { 1, "and merged by StageFlow.MostKinds" },
		bootLobbyKinds = { 1, "Boot makes the lobby's kinds before the loop starts" },
		tickLobbyKinds = { 1, "and tries again before each broadcast" },
		bootLobbyCalls = { 2, "Boot calls refreshLobbyKinds twice" },
		announceKey = { 1, "the chest's found event carries its key" },
		sendPrewarm = { 1, "sendRunState sends the prewarm" },
		sendPrewarmWrites = { 1, "and writes it once" },
		leverDressFail = { 1, "the lever dressFail fails the next dress" },
		sealAnchored = { 1, "the scenery's parts are anchored" },
		sealCollide = { 1, "collide with nothing" },
		sealQuery = { 1, "stop no ray" },
		sealTouch = { 1, "and touch nothing" },
		failPath = { 1, "a failed client warns, tears down, marks itself failed and shows the grey view, in that order" },
		showSkinned = { 1, "the failed view shows the Skinned parts" },
		showSkinnedPaint = { 1, "fully opaque" },
		showWalls = { 1, "and draws every wall" },
		showWallColor = { 1, "in the grey look (red only in Studio's walls view)" },
		showWallPaint = { 1, "at the drawn wall's transparency" },
		viewShow = { 1, "applyView asks ScenePlan.Show with the failed flag" },
		viewFolder = { 1, "parents the scenery by its answer" },
		viewChild = { 1, "and shows every child of the level" },
		addedShow = { 1, "a later child is judged by the same Show" },
		addedChild = { 1, "and shown the same way" },
		buildPcall = { 1, "the build's whole thread runs under one pcall" },
		buildFails = { 1, "a throw in the current build" },
		buildFailCall = { 1, "fails the scenery" },
		startFails = { 1, "a throw before the thread fails it too" },
		startSpawns = { 1, "the thread is the pcalled build" },
		sceneryBareSteps = { 0, "and buildSteps never runs bare in a thread" },
		evalKey = { 1, "evaluate keys the word by name and hash" },
		evalSame = { 1, "and skips a word already acted on" },
		evalDressed = { 1, "tells the camera whether the server dressed the level" },
		evalDecide = { 1, "asks ScenePlan.Decide with whether the place has loaded" },
		evalKeep = { 1, "keeps the key only when the answer is kept" },
		evalBuild = { 1, "builds on a build answer with a dress" },
		evalFail = { 1, "fails on a fail answer" },
		evalFailCall = { 1, "with its reason" },
		evalWait = { 1, "and waits for the place on a wait answer" },
		awaitIf = { 1, "awaitLoaded waits for game.Loaded unless loaded" },
		awaitEval = { 1, "then reads the word again" },
		stepsJobs = { 1, "the build's jobs drop the fires on a low-end device" },
		stepsGeneration = { 1, "and a build a newer word outlived stops at its next frame" },
		moodRule = { 1, "mood B needs the body out of the lobby camp" },
		placedLobby = { 1, "a placement says whether the body is in the lobby camp" },
		lobbyBox = { 1, "judged on the lobby's box grown by levels.boxMargin" },
		startPlaced = { 1, "LevelScenery listens to the camera's placements" },
		detachDressed = { 1, "a detached level tells the camera it is not dressed" },
		cameraEnds = { 1, "in a dressed level the summary and ended phases keep the shoulder camera" },
		cameraDressed = { 1, "SetDressed writes the flag" },
		cameraDressedWrites = { 2, "the flag is written only where it is declared and in SetDressed" },
		sightsRayDrop = { 1, "the assist's CrowdRay is handed the drop" },
		sightsRefusedBody = { 1, "a refused body's sphere is lowered by its seat, never under its foot" },
		sightsRefusedHead = { 1, "and its head lowered" },
		sightsBody = { 1, "a taken body's sphere is lowered by its seat, never under its foot" },
		sightsHead = { 1, "and its head lowered" },
		reachBody = { 1, "the melee reach's body sphere is lowered the same way" },
		reachHead = { 1, "and its head" },
		forEachDrop = { 1, "ForEach hands the server's seat drop" },
		figuresHead = { 1, "Figures reads the model's head point" },
		figuresScored = { 1, "against the server's crit head (height - headRadius)" },
		figuresHeadTest = { 1, "refusing a head point off it on any axis" },
		figuresEpsilon = { 1, "by 0.01" },
		figuresAnchor = { 1, "the anchor is laid by RaiderPose.Rig's anchor" },
		figuresLean = { 1, "the lean is split by RaiderPose.Lean" },
		-- Fix round 2 (docs/prompts/l4-w2-fix2.md L4, the fix-diff review's m1; L1, L2, L3).
		takeTakes = { 1, "Take answers a pooled figure or nil" },
		takeBuilds = { 0, "and never builds one (a spawn batch would build them all in one frame)" },
		prewarmRoom = { 1, "Prewarm's room is the cap" },
		prewarmShare = { 1, "over it every kind gets its share" },
		prewarmExact = { 1, "each kind's count is scaled by the share" },
		buildBudget = { 1, "Build keeps to COMBAT_RAIDER_PREWARM_PER_FRAME a frame, at least one" },
		buildWaitBudget = { 1, "the waiting bodies' figures within the budget" },
		buildRoundBudget = { 1, "the goals' rounds within it" },
		buildGoalBudget = { 1, "and each goal's figure within it" },
		dressTakes = { 1, "dressFigure takes a pooled figure" },
		dressWants = { 1, "and a body that met an empty pool waits for its model" },
		wearReady = { 1, "wear puts the model on only once its pool has one" },
		wearWaits = { 1, "else the body counts as waiting this frame" },
		wearDresses = { 1, "and the ready body is dressed again (applyKind)" },
		stepBuilds = { 1, "the pools fill on every step" },
		stepWants = { 1, "a living body's wish is read" },
		stepWears = { 1, "and a waiting body wears its model" },
		uiPrewarmCounts = { 1, "every RunState's prewarm is read into counts (the lobby's too)" },
		uiPrewarmHands = { 1, "and handed to the renderer" },
		isSkinnedRule = { 1, "a Skinned part is a BasePart marked Skinned" },
		isWallRule = { 1, "a wall is a BasePart out of the Default group" },
		teardownState = { 1, "teardown drops the dress, the built flag and the failure, in that order" },
		teardownFailedWrites = { 1, "teardown writes the failure once" },
		lobbyKnown = { 1, "bodyInLobby answers the server's last word when there is one" },
		lobbyRoot = { 1, "else reads the body's root, no root: not in the lobby" },
		lobbyJudged = { 1, "and judges the root where it stands" },
		lobbyAnswers = { 3, "bodyInLobby answers in three places only" },
		cameraScenePlan = { 1, "CameraController requires ScenePlan" },
		cameraRunOver = { 1, "the camera's run-over phases are ScenePlan.RUN_OVER" },
		cameraCrosshair = { 1, "ShowsCrosshair is ScenePlan.Crosshair on the camera, the phase and the bench" },
		feedbackCrosshair = { 1, "the crosshair is drawn by ShowsCrosshair" },
		feedbackNoActive = { 0, "not by IsActive" },
		campHead = { 1, "a camp mark reads its body's head part each frame" },
		campEnds = { 1, "and ends only when it is old or the body is gone" },
		campRehangs = { 1, "a new head part takes the mark" },
		hangHead = { 1, "hang keeps the part" },
		hangAdornee = { 1, "adorns it" },
		hangOffset = { 1, "and lifts the mark over its top" },
		alertHangs = { 1, "Alert hangs a new mark the same way" },
		sweepSectors = { 1, "raiderpose's sweep gate bins at 5 degrees" },
		sweepKinds = { 1, "for the Camp Chief" },
		sweepTell = { 1, "the tell's leading edge runs from his right to his left" },
		sweepLeading = { 1, "the hammer's leading end is its leftmost angle at range" },
		sweepBehind = { 1, "the lag is that end behind the tell's leading edge" },
		sweepGate = { 1, "every sector, the span's ends and the lag decide the row" },
	},
	ORDER = {
		wallThenArmed = "construct: the dress wall's branch arms it",
		hiddenThenSkinned = "construct: a hidden piece is marked inside its test",
		failReadThenSpent = "dressOf: the lever read before it is spent",
		failSpentThenDecide = "dressOf: spent before Decide is asked",
		nilThenPieces = "Build: the words cleared before the pieces",
		piecesThenDress = "Build: the dress asked after the pieces",
		layThenPlace = "Build: laid before it is placed",
		placeThenBuilt = "Build: placed before it is built",
		builtThenWord = "Build: the word written after the level stands",
		hashThenDress = "Build: DressHash, then Dress (K7)",
		clearNilThenParts = "Clear: the words gone before any Part",
		gatherRestThenDrop = "gather: crowd.restDrop read before the drop",
		gatherDropThenHead = "gather: the drop before the head",
		cellsWentThenPrewarm = "sendRunState: the prewarm only with the cells",
		lobbyKindsThenBroadcast = "Boot: the lobby's kinds before a broadcast",
		evalDressedThenDecide = "evaluate: the camera told before the decision",
		evalKeepThenTeardown = "evaluate: the key kept or dropped before the teardown",
	},
}

function L4BP.w2SourceTests(): ()
	print(" L4 W2: the lines that lay the dress, seat the hits, send the pools and draw the scenery (source.l4w2)")
	local reading = FIXTURES.source.l4w2
	local W2 = L4BP.W2
	check(
		#reading.missing == 0,
		`every function the lines live in is there ({table.concat(reading.missing, ", ")})`
	)
	local keys = {}
	for key in W2.LINES do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local expected = W2.LINES[key]
		local count = reading.counts[key]
		check(count == expected[1], `{expected[2]} ({key}: {tostring(count)}, expected {expected[1]})`)
	end
	local unknown = {}
	for key in reading.counts do
		if W2.LINES[key] == nil then
			table.insert(unknown, key)
		end
	end
	for key, text in W2.ORDER do
		check(reading.order[key] == true, `{text} ({key})`)
	end
	for key in reading.order do
		if W2.ORDER[key] == nil then
			table.insert(unknown, key)
		end
	end
	table.sort(unknown)
	check(#unknown == 0, `every L4 W2 line read has an expected count here ({table.concat(unknown, ", ")})`)
end
L1.group("l4w2 sourceTests", L4BP.w2SourceTests)

print(if failures == 0 then "HARNESS: PASS" else `HARNESS: FAIL ({failures})`)
